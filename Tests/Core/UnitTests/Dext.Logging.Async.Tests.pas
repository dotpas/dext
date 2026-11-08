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
{  Created: 2026-11-08                                                      }
{                                                                           }
{  Dext.Logging.Async.Tests - Async logging pipeline                        }
{                                                                           }
{  TRingBuffer: order, full queue, unpublished slots, laps, slot clearing,  }
{  event wake-up. TAsyncLoggerFactory: minimum level, no-sink fast path,    }
{  category, drop report. Stress: 8 producers, every entry exactly once     }
{  and in order per producer.                                               }
{                                                                           }
{***************************************************************************}

unit Dext.Logging.Async.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Dext.Collections,
  Dext.Testing,
  Dext.Logging,
  Dext.Logging.RingBuffer,
  Dext.Logging.Async;

type
  /// <summary>Sink that keeps what it receives, for the assertions.</summary>
  TCollectSink = class(TInterfacedObject, ILogSink)
  private
    FLock: TObject;
    FMessages: IList<string>;
    FCategories: IList<string>;
    FCount: Integer;
    FTarget: Integer;
    FReached: TEvent;
    FGate: TEvent;
    FEmitTicks: Int64;
  public
    constructor Create(ATarget: Integer = 1; ABlockFirstEmit: Boolean = False);
    destructor Destroy; override;
    procedure Emit(const Entry: TLogEntry);
    procedure Flush;
    /// <summary>Waits until ATarget entries arrived; False on timeout.</summary>
    function WaitTarget(TimeoutMs: Cardinal): Boolean;
    /// <summary>Lets a sink created with ABlockFirstEmit go on.</summary>
    procedure OpenGate;
    function Count: Integer;
    function MessageAt(Index: Integer): string;
    function CategoryAt(Index: Integer): string;
    function HasMessageContaining(const Text: string): Boolean;
    property EmitTicks: Int64 read FEmitTicks;
  end;

  [TestFixture('TRingBuffer: bounded MPSC queue of log entries')]
  TRingBufferTests = class
  public
    [Test('Entries come out in the order they were published')]
    procedure Publish_And_Read_Keep_Order;
    [Test('A full queue refuses the entry and counts the drop')]
    procedure Full_Queue_Drops_And_Counts;
    [Test('A reserved slot is invisible until it is published')]
    procedure Reserved_Slot_Is_Invisible_Until_Published;
    [Test('Slots are reused lap after lap without stale entries')]
    procedure Slots_Reused_Across_Laps;
    [Test('Reading clears the slot: the next lap starts with empty strings')]
    procedure Release_Clears_The_Slot;
    [Test('WaitForData returns as soon as a producer publishes')]
    procedure WaitForData_Wakes_On_Publish;
    [Test('WaitForData gives up after the timeout on an empty queue')]
    procedure WaitForData_Times_Out_When_Empty;
  end;

  [TestFixture('TAsyncLoggerFactory: level, sinks, category, drops')]
  TAsyncLoggerTests = class
  public
    [Test('Entries below the minimum level never reach the sink')]
    procedure Minimum_Level_Discards_Below;
    [Test('Without a sink the logger reports itself disabled')]
    procedure No_Sink_Means_Disabled;
    [Test('The sink receives the category of the logger')]
    procedure Category_Reaches_The_Sink;
    [Test('Dropped entries are counted and reported to the sinks')]
    procedure Dropped_Entries_Are_Reported;
    [Test('An idle consumer delivers an entry in under 5 ms (median)')]
    [Category('Performance')]
    procedure Idle_Consumer_Wakes_Fast;
  end;

  [TestFixture('TRingBuffer under 8 concurrent producers')]
  TRingBufferStressTests = class
  public
    [Test('Every entry arrives exactly once and in order per producer')]
    [Category('Stress')]
    procedure Eight_Producers_Each_Entry_Once_In_Order;
  end;

implementation

const
  WAIT_MS = 5000;

{ TCollectSink }

constructor TCollectSink.Create(ATarget: Integer; ABlockFirstEmit: Boolean);
begin
  inherited Create;
  FLock := TObject.Create;
  FMessages := TCollections.CreateList<string>;
  FCategories := TCollections.CreateList<string>;
  FTarget := ATarget;
  FReached := TEvent.Create(nil, True, False, '');
  if ABlockFirstEmit then
    FGate := TEvent.Create(nil, True, False, '');
end;

destructor TCollectSink.Destroy;
begin
  FReached.Free;
  FGate.Free;
  FLock.Free;
  inherited;
end;

procedure TCollectSink.Emit(const Entry: TLogEntry);
begin
  if FGate <> nil then
    FGate.WaitFor(WAIT_MS);
  FEmitTicks := TStopwatch.GetTimeStamp;
  TMonitor.Enter(FLock);
  try
    FMessages.Add(Entry.FormattedMessage);
    FCategories.Add(Entry.Category);
    Inc(FCount);
    if FCount >= FTarget then
      FReached.SetEvent;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TCollectSink.Flush;
begin
end;

function TCollectSink.WaitTarget(TimeoutMs: Cardinal): Boolean;
begin
  Result := FReached.WaitFor(TimeoutMs) = wrSignaled;
end;

procedure TCollectSink.OpenGate;
begin
  if FGate <> nil then
    FGate.SetEvent;
end;

function TCollectSink.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCount;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCollectSink.MessageAt(Index: Integer): string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FMessages[Index];
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCollectSink.CategoryAt(Index: Integer): string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCategories[Index];
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TCollectSink.HasMessageContaining(const Text: string): Boolean;
var
  i: Integer;
begin
  TMonitor.Enter(FLock);
  try
    for i := 0 to FMessages.Count - 1 do
      if FMessages[i].Contains(Text) then
        Exit(True);
    Result := False;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ Helpers }

procedure PublishText(Buffer: TRingBuffer; const Text: string);
var
  Position: Integer;
  Entry: PLogEntry;
begin
  if not Buffer.TryReserve(Position, Entry) then
    raise Exception.Create('queue unexpectedly full');
  Entry.FormattedMessage := Text;
  Buffer.Publish(Position);
end;

{ TRingBufferTests }

procedure TRingBufferTests.Publish_And_Read_Keep_Order;
var
  Buffer: TRingBuffer;
  Entry: TLogEntry;
  i: Integer;
begin
  Buffer := TRingBuffer.Create(4);
  try
    for i := 1 to 10 do
      PublishText(Buffer, IntToStr(i));
    for i := 1 to 10 do
    begin
      Should(Buffer.TryRead(Entry)).BeTrue;
      Should(Entry.FormattedMessage).Be(IntToStr(i));
    end;
    Should(Buffer.TryRead(Entry)).BeFalse;
  finally
    Buffer.Free;
  end;
end;

procedure TRingBufferTests.Full_Queue_Drops_And_Counts;
var
  Buffer: TRingBuffer;
  Position: Integer;
  Entry: PLogEntry;
  i: Integer;
begin
  Buffer := TRingBuffer.Create(2); // 4 slots
  try
    for i := 1 to 4 do
      PublishText(Buffer, 'x');
    Should(Buffer.TryReserve(Position, Entry)).BeFalse;
    Should(Buffer.TryReserve(Position, Entry)).BeFalse;
    Should(Buffer.Dropped).Be(2);
  finally
    Buffer.Free;
  end;
end;

procedure TRingBufferTests.Reserved_Slot_Is_Invisible_Until_Published;
var
  Buffer: TRingBuffer;
  Position: Integer;
  Reserved, Peeked: PLogEntry;
begin
  Buffer := TRingBuffer.Create(2);
  try
    Should(Buffer.TryReserve(Position, Reserved)).BeTrue;
    Reserved.FormattedMessage := 'pending';
    Should(Buffer.TryPeek(Peeked)).BeFalse;
    Buffer.Publish(Position);
    Should(Buffer.TryPeek(Peeked)).BeTrue;
    Should(Peeked.FormattedMessage).Be('pending');
    Buffer.Release;
  finally
    Buffer.Free;
  end;
end;

procedure TRingBufferTests.Slots_Reused_Across_Laps;
var
  Buffer: TRingBuffer;
  Entry: TLogEntry;
  i: Integer;
begin
  Buffer := TRingBuffer.Create(1); // 2 slots: every entry after the 2nd reuses one
  try
    for i := 1 to 50 do
    begin
      PublishText(Buffer, IntToStr(i));
      Should(Buffer.TryRead(Entry)).BeTrue;
      Should(Entry.FormattedMessage).Be(IntToStr(i));
      Should(Entry.SequenceId).Be(Int64(i - 1));
      Should(Buffer.TryRead(Entry)).BeFalse;
    end;
    Should(Buffer.Dropped).Be(0);
  finally
    Buffer.Free;
  end;
end;

procedure TRingBufferTests.Release_Clears_The_Slot;
var
  Buffer: TRingBuffer;
  Entry: TLogEntry;
  Position: Integer;
  Reserved: PLogEntry;
begin
  Buffer := TRingBuffer.Create(0); // 1 slot: the next reserve gets the same one
  try
    PublishText(Buffer, 'old message');
    Should(Buffer.TryRead(Entry)).BeTrue;
    Should(Buffer.TryReserve(Position, Reserved)).BeTrue;
    Should(Reserved.FormattedMessage).Be('');
    Buffer.Publish(Position);
  finally
    Buffer.Free;
  end;
end;

procedure TRingBufferTests.WaitForData_Wakes_On_Publish;
var
  Buffer: TRingBuffer;
  Producer: TThread;
  Watch: TStopwatch;
begin
  Buffer := TRingBuffer.Create(4);
  try
    Producer := TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(50);
        PublishText(Buffer, 'late');
      end);
    Producer.FreeOnTerminate := False;
    try
      Producer.Start;
      Watch := TStopwatch.StartNew;
      Buffer.WaitForData(WAIT_MS);
      Should(Watch.ElapsedMilliseconds).BeLessThan(Int64(1000));
      Producer.WaitFor;
    finally
      Producer.Free;
    end;
  finally
    Buffer.Free;
  end;
end;

procedure TRingBufferTests.WaitForData_Times_Out_When_Empty;
var
  Buffer: TRingBuffer;
  Watch: TStopwatch;
begin
  Buffer := TRingBuffer.Create(4);
  try
    Watch := TStopwatch.StartNew;
    Buffer.WaitForData(60);
    Should(Watch.ElapsedMilliseconds).BeInRange(40, 1000);
  finally
    Buffer.Free;
  end;
end;

{ TAsyncLoggerTests }

procedure TAsyncLoggerTests.Minimum_Level_Discards_Below;
var
  Factory: TAsyncLoggerFactory;
  Sink: TCollectSink;
  SinkRef: ILogSink;
  Logger: ILogger;
begin
  Factory := TAsyncLoggerFactory.Create;
  try
    Sink := TCollectSink.Create(1);
    SinkRef := Sink;
    Factory.AddSink(SinkRef);
    Factory.SetMinimumLevel(TLogLevel.Warning);
    Logger := Factory.CreateLogger('Tests');

    Logger.Debug('debug');
    Logger.Info('info');
    Logger.Warn('warning');

    Should(Sink.WaitTarget(WAIT_MS)).BeTrue;
    Sleep(50); // anything that slipped through would arrive by now
    Should(Sink.Count).Be(1);
    Should(Sink.MessageAt(0)).Be('warning');
    Logger := nil;
  finally
    Factory.Dispose;
    Factory.Free;
  end;
end;

procedure TAsyncLoggerTests.No_Sink_Means_Disabled;
var
  Factory: TAsyncLoggerFactory;
  Logger: ILogger;
  SinkRef: ILogSink;
begin
  Factory := TAsyncLoggerFactory.Create;
  try
    Logger := Factory.CreateLogger('Tests');
    Should(Factory.HasSinks).BeFalse;
    Should(Logger.IsEnabled(TLogLevel.Critical)).BeFalse;

    SinkRef := TCollectSink.Create(1);
    Factory.AddSink(SinkRef);
    Should(Factory.HasSinks).BeTrue;
    Should(Logger.IsEnabled(TLogLevel.Information)).BeTrue;
    Should(Logger.IsEnabled(TLogLevel.Debug)).BeFalse; // default level: Information
    Logger := nil;
  finally
    Factory.Dispose;
    Factory.Free;
  end;
end;

procedure TAsyncLoggerTests.Category_Reaches_The_Sink;
var
  Factory: TAsyncLoggerFactory;
  Sink: TCollectSink;
  SinkRef: ILogSink;
  Logger: ILogger;
begin
  Factory := TAsyncLoggerFactory.Create;
  try
    Sink := TCollectSink.Create(1);
    SinkRef := Sink;
    Factory.AddSink(SinkRef);
    Logger := Factory.CreateLogger('Billing');
    Logger.Info('invoice {Id} paid', [42]);
    Should(Sink.WaitTarget(WAIT_MS)).BeTrue;
    Should(Sink.CategoryAt(0)).Be('Billing');
    Logger := nil;
  finally
    Factory.Dispose;
    Factory.Free;
  end;
end;

procedure TAsyncLoggerTests.Dropped_Entries_Are_Reported;
const
  Total = 70000; // more than the 65,536 slots
var
  Factory: TAsyncLoggerFactory;
  Sink: TCollectSink;
  SinkRef: ILogSink;
  Logger: ILogger;
  i: Integer;
begin
  Factory := TAsyncLoggerFactory.Create;
  try
    Sink := TCollectSink.Create(MaxInt, True); // blocks the consumer on the first entry
    SinkRef := Sink;
    Factory.AddSink(SinkRef);
    Logger := Factory.CreateLogger('Tests');
    for i := 1 to Total do
      Logger.Info('entry');
    Should(Factory.Dropped).BeGreaterThan(0);

    Sink.OpenGate;
    Logger := nil;
    Factory.Dispose; // drains, reports the drops, flushes
    Should(Sink.HasMessageContaining('log entries dropped')).BeTrue;
    Should(Sink.Count).Be(Total - Factory.Dropped + 1); // + the drop report
  finally
    Factory.Free;
  end;
end;

procedure TAsyncLoggerTests.Idle_Consumer_Wakes_Fast;
const
  Samples = 21;
var
  Factory: TAsyncLoggerFactory;
  Sink: TCollectSink;
  SinkRef: ILogSink;
  Logger: ILogger;
  Latencies: IList<Int64>;
  i: Integer;
  Sent: Int64;
begin
  Factory := TAsyncLoggerFactory.Create;
  try
    Sink := TCollectSink.Create(MaxInt);
    SinkRef := Sink;
    Factory.AddSink(SinkRef);
    Logger := Factory.CreateLogger('Tests');
    Latencies := TCollections.CreateList<Int64>;
    for i := 1 to Samples do
    begin
      Sleep(20); // let the consumer fall asleep
      Sent := TStopwatch.GetTimeStamp;
      Logger.Info('ping');
      while Sink.Count < i do
        Sleep(0);
      Latencies.Add((Sink.EmitTicks - Sent) * 1000000 div TStopwatch.Frequency);
    end;
    Latencies.Sort;
    Should(Latencies[Samples div 2])
      .Because('the consumer is woken by an event, not by a 15.6 ms timer tick')
      .BeLessThan(5000);
    Logger := nil;
  finally
    Factory.Dispose;
    Factory.Free;
  end;
end;

{ TRingBufferStressTests }

procedure TRingBufferStressTests.Eight_Producers_Each_Entry_Once_In_Order;
const
  Producers = 8;
  PerProducer = 200000;
var
  Buffer: TRingBuffer;
  Threads: array[0..Producers - 1] of TThread;
  Expected: array[0..Producers - 1] of Int64;
  Entry: TLogEntry;
  Received, Producer, Errors: Integer;
  Value: Int64;
  i: Integer;

  function MakeProducer(ABuffer: TRingBuffer; Index: Integer): TThread;
  begin
    Result := TThread.CreateAnonymousThread(
      procedure
      var
        n: Integer;
        Position: Integer;
        Slot: PLogEntry;
      begin
        for n := 0 to PerProducer - 1 do
        begin
          // Retry instead of dropping: this test is about integrity
          while not ABuffer.TryReserve(Position, Slot) do
            TThread.Yield;
          Slot.ThreadID := TThreadID(Index);
          Slot.TimeStamp := n; // the counter travels in a field with no allocation
          ABuffer.Publish(Position);
        end;
      end);
    Result.FreeOnTerminate := False;
  end;

begin
  Buffer := TRingBuffer.Create(10); // 1,024 slots: about 1,500 laps
  try
    for i := 0 to Producers - 1 do
    begin
      Expected[i] := 0;
      Threads[i] := MakeProducer(Buffer, i);
    end;
    for i := 0 to Producers - 1 do
      Threads[i].Start;

    Received := 0;
    Errors := 0;
    while Received < Producers * PerProducer do
    begin
      if Buffer.TryRead(Entry) then
      begin
        Producer := Integer(Entry.ThreadID);
        Value := Round(Entry.TimeStamp);
        if (Producer < 0) or (Producer >= Producers) or (Value <> Expected[Producer]) then
          Inc(Errors)
        else
          Expected[Producer] := Value + 1;
        Inc(Received);
      end
      else
        Buffer.WaitForData(WAIT_MS);
    end;

    for i := 0 to Producers - 1 do
    begin
      Threads[i].WaitFor;
      Threads[i].Free;
    end;

    Should(Errors).Be(0);
    for i := 0 to Producers - 1 do
      Should(Expected[i]).Be(Int64(PerProducer));
    Should(Buffer.TryRead(Entry)).BeFalse;
  finally
    Buffer.Free;
  end;
end;

end.
