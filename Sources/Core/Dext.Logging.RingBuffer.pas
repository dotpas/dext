{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2026-01-25                                                      }
{                                                                           }
{  Dext.Logging.RingBuffer - Bounded MPSC queue for async logging           }
{                                                                           }
{  Many producer threads, one consumer thread. Each slot carries its own    }
{  sequence number (Dmitry Vyukov's bounded queue, the same idea as the     }
{  LMAX Disruptor): a producer may write a slot only when the sequence      }
{  equals its position, and publishes it by storing position + 1; the       }
{  consumer reads it only when the sequence is position + 1 and frees it    }
{  by storing position + Capacity. A slot from the previous lap can never   }
{  be mistaken for a new one.                                               }
{                                                                           }
{  The consumer sleeps on an event when the queue is empty; a producer      }
{  signals it only when it finds the consumer asleep, so a burst costs one  }
{  SetEvent, not one per entry. When the queue is full the entry is         }
{  dropped and counted: logging never blocks the caller.                    }
{                                                                           }
{***************************************************************************}

unit Dext.Logging.RingBuffer;

{$OVERFLOWCHECKS OFF} // positions and sequences wrap around on purpose
{$RANGECHECKS OFF}

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Classes,
  Dext.Types.UUID,
  Dext.Logging;

const
  CACHE_LINE_SIZE = 64;

type
  PLogEntry = ^TLogEntry;

  /// <summary>
  ///   A single log event as the sinks receive it.
  /// </summary>
  TLogEntry = record
    /// <summary>Position of the entry in the queue (monotonic, wraps at 2^32).</summary>
    SequenceId: Int64;
    TimeStamp: TDateTime;
    Level: TLogLevel;
    ThreadID: TThreadID;
    /// <summary>Category of the logger that wrote the entry (e.g. 'App').</summary>
    Category: string;

    // Context
    TraceId: TUUID;
    SpanId: TUUID;

    ScopeSnapshot: IInterface;
    MessageTemplate: string;
    /// <summary>
    ///   Message formatted by the producer. The arguments of an "array of
    ///   const" point to the caller's stack, so they cannot cross threads.
    /// </summary>
    FormattedMessage: string;
  end;

  /// <summary>
  ///   One slot of the queue: the entry and the sequence that says whose
  ///   turn it is (producer: Sequence = position; consumer: position + 1).
  /// </summary>
  TLogSlot = record
    Sequence: Integer;
    Entry: TLogEntry;
  end;

  /// <summary>
  ///   Producer and consumer positions on separate cache lines, so the
  ///   producers' CAS on Head does not invalidate the consumer's Tail.
  /// </summary>
  TRingBufferPointers = record
    Head: Integer; // next position to reserve (producers)
    Padding1: array[0..CACHE_LINE_SIZE - SizeOf(Integer) - 1] of Byte;
    Tail: Integer; // next position to read (single consumer)
    Padding2: array[0..CACHE_LINE_SIZE - SizeOf(Integer) - 1] of Byte;
  end;

  /// <summary>
  ///   Bounded multi-producer, single-consumer queue of log entries with an
  ///   event-based wake-up for the consumer.
  /// </summary>
  TRingBuffer = class
  private
    FSlots: TArray<TLogSlot>;
    FMask: Integer;
    FCapacity: Integer;
    FPointers: TRingBufferPointers;
    FDropped: Integer;
    FSleeping: Integer;
    FWakeEvent: TEvent;
    function GetDropped: Integer;
  public
    /// <summary>Creates a queue with 2^SizePowerOfTwo slots (1 to 2^24).</summary>
    constructor Create(SizePowerOfTwo: Integer);
    destructor Destroy; override;

    /// <summary>
    ///   Reserves the next slot for writing. Returns False, and counts a
    ///   drop, when the queue is full. After filling Entry the producer
    ///   must call Publish(Position).
    /// </summary>
    function TryReserve(out Position: Integer; out Entry: PLogEntry): Boolean;

    /// <summary>
    ///   Makes the reserved slot visible to the consumer and wakes it if it
    ///   is waiting.
    /// </summary>
    procedure Publish(Position: Integer);

    /// <summary>
    ///   Consumer only. Points Entry at the next published entry without
    ///   copying it. The consumer must call Release after using it.
    /// </summary>
    function TryPeek(out Entry: PLogEntry): Boolean;

    /// <summary>
    ///   Consumer only. Clears the entry returned by TryPeek (so its strings
    ///   are freed now, not a lap later) and hands the slot back.
    /// </summary>
    procedure Release;

    /// <summary>
    ///   Consumer only. Copies the next published entry and releases its
    ///   slot. Returns False when nothing is published yet.
    /// </summary>
    function TryRead(out Entry: TLogEntry): Boolean;

    /// <summary>
    ///   Consumer only. Sleeps until a producer publishes, Wake is called or
    ///   TimeoutMs elapses. Returns at once if an entry is already waiting.
    /// </summary>
    procedure WaitForData(TimeoutMs: Cardinal);

    /// <summary>Wakes the consumer (used to stop it).</summary>
    procedure Wake;

    /// <summary>Number of slots.</summary>
    property Capacity: Integer read FCapacity;
    /// <summary>Entries dropped because the queue was full.</summary>
    property Dropped: Integer read GetDropped;
  end;

implementation

/// <summary>
///   Acquire load of a sequence. On x86/x64 an aligned 32-bit load is atomic
///   and already has acquire semantics; ARM needs the explicit barrier. A
///   locked CompareExchange here would take the cache line exclusively and
///   make producer and consumer fight over it on every entry.
/// </summary>
function LoadAcquire(const Value: Integer): Integer; inline;
begin
  Result := Value;
  {$IF defined(CPUARM) or defined(CPUARM64)}
  MemoryBarrier;
  {$ENDIF}
end;

{ TRingBuffer }

constructor TRingBuffer.Create(SizePowerOfTwo: Integer);
var
  i: Integer;
begin
  inherited Create;
  if (SizePowerOfTwo < 0) or (SizePowerOfTwo > 24) then
    raise EArgumentException.Create('Invalid size power');

  FCapacity := 1 shl SizePowerOfTwo;
  FMask := FCapacity - 1;
  SetLength(FSlots, FCapacity);
  for i := 0 to FCapacity - 1 do
    FSlots[i].Sequence := i; // slot i is free for position i
  FPointers.Head := 0;
  FPointers.Tail := 0;
  FWakeEvent := TEvent.Create(nil, False, False, ''); // auto-reset
end;

destructor TRingBuffer.Destroy;
begin
  FWakeEvent.Free;
  inherited;
end;

function TRingBuffer.GetDropped: Integer;
begin
  Result := LoadAcquire(FDropped);
end;

function TRingBuffer.TryReserve(out Position: Integer; out Entry: PLogEntry): Boolean;
var
  Pos, Seq, Dif: Integer;
  Slot: ^TLogSlot;
begin
  Pos := FPointers.Head;
  while True do
  begin
    Slot := @FSlots[Pos and FMask];
    Seq := LoadAcquire(Slot.Sequence);
    Dif := Seq - Pos;
    if Dif = 0 then
    begin
      // The slot is free for this position: try to claim the position
      if TInterlocked.CompareExchange(FPointers.Head, Pos + 1, Pos) = Pos then
        Break;
      Pos := FPointers.Head;
    end
    else if Dif < 0 then
    begin
      // The slot still holds the entry from the previous lap: queue full
      TInterlocked.Increment(FDropped);
      Exit(False);
    end
    else
      Pos := FPointers.Head; // another producer took it; try the new head
  end;

  Position := Pos;
  Entry := @Slot.Entry;
  Entry.SequenceId := Pos;
  Result := True;
end;

procedure TRingBuffer.Publish(Position: Integer);
begin
  // Full barrier: the entry's fields are visible before the new sequence,
  // and the sequence is visible before we read FSleeping below
  TInterlocked.Exchange(FSlots[Position and FMask].Sequence, Position + 1);

  if (FSleeping <> 0) and (TInterlocked.CompareExchange(FSleeping, 0, 1) = 1) then
    FWakeEvent.SetEvent;
end;

function TRingBuffer.TryPeek(out Entry: PLogEntry): Boolean;
var
  Slot: ^TLogSlot;
begin
  Slot := @FSlots[FPointers.Tail and FMask];
  if LoadAcquire(Slot.Sequence) <> FPointers.Tail + 1 then
    Exit(False); // empty, or reserved but not published yet
  Entry := @Slot.Entry;
  Result := True;
end;

procedure TRingBuffer.Release;
var
  Pos: Integer;
  Slot: ^TLogSlot;
begin
  Pos := FPointers.Tail;
  Slot := @FSlots[Pos and FMask];
  // Frees the strings now (not a lap later); the other fields are
  // overwritten by the next producer
  Slot.Entry.Category := '';
  Slot.Entry.MessageTemplate := '';
  Slot.Entry.FormattedMessage := '';
  Slot.Entry.ScopeSnapshot := nil;
  // Hand the slot to the producer of the next lap
  TInterlocked.Exchange(Slot.Sequence, Pos + FCapacity);
  FPointers.Tail := Pos + 1;
end;

function TRingBuffer.TryRead(out Entry: TLogEntry): Boolean;
var
  Slot: PLogEntry;
begin
  Result := TryPeek(Slot);
  if Result then
  begin
    Entry := Slot^;
    Release;
  end;
end;

procedure TRingBuffer.WaitForData(TimeoutMs: Cardinal);
var
  Dummy: PLogEntry;
begin
  // Announce the sleep, then look again: a producer that published before
  // the announcement is seen here; one that publishes after it sees the flag
  // and signals. Both sides use full barriers, so no wake-up is lost.
  TInterlocked.Exchange(FSleeping, 1);
  if not TryPeek(Dummy) then
    FWakeEvent.WaitFor(TimeoutMs);
  TInterlocked.Exchange(FSleeping, 0);
end;

procedure TRingBuffer.Wake;
begin
  FWakeEvent.SetEvent;
end;

end.
