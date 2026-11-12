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
{  Created: 2026-01-28                                                      }
{                                                                           }
{  Dext.Logging.Async - Asynchronous logging pipeline                       }
{                                                                           }
{  TAsyncLogger formats the message on the caller's thread and publishes    }
{  it to a TRingBuffer; one TLogConsumerThread hands the entries to the     }
{  sinks. The consumer sleeps on an event while the queue is empty (no      }
{  polling), honours the factory's minimum level and reports the entries    }
{  dropped when the queue was full. With no sink registered, a log call     }
{  returns before formatting anything.                                      }
{                                                                           }
{***************************************************************************}

unit Dext.Logging.Async;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Dext.Types.UUID,
  Dext.Collections,
  Dext.Logging,
  Dext.Logging.RingBuffer,
  Dext.Telemetry.Context;

const
  /// <summary>Queue size of TAsyncLoggerFactory: 2^16 = 65,536 entries.</summary>
  ASYNC_LOG_QUEUE_POWER = 16;
  /// <summary>
  ///   Longest sleep of the idle consumer. A safety net only: producers wake
  ///   it through an event, so an idle process wakes once per second.
  /// </summary>
  ASYNC_LOG_IDLE_TIMEOUT_MS = 1000;
  /// <summary>
  ///   Rounds of a short busy-wait (CPU "pause") the consumer does before it
  ///   sleeps: about 50 us. In a steady stream the next entry usually comes
  ///   within it, and the producer is spared a SetEvent and a thread wake-up.
  /// </summary>
  ASYNC_LOG_SPIN_ROUNDS = 200;

type
  /// <summary>
  ///   Consumer interface for log entries.
  /// </summary>
  ILogSink = interface
    ['{D1E2F3A4-B5C6-7890-1234-567890ABCDEF}']
    /// <summary>Receives one entry, on the consumer thread.</summary>
    procedure Emit(const Entry: TLogEntry);
    /// <summary>Writes what the sink buffered (called when the pipeline stops).</summary>
    procedure Flush;
  end;

  /// <summary>
  ///   State shared by a factory and its loggers, read on every log call
  ///   without locks: the minimum level and how many sinks are registered.
  /// </summary>
  TAsyncLogState = class
  private
    FMinimumLevel: Integer;
    FSinkCount: Integer;
    function GetMinimumLevel: TLogLevel;
    function GetSinkCount: Integer;
  public
    constructor Create;
    /// <summary>Changes the minimum level seen by every logger of the factory.</summary>
    procedure SetMinimumLevel(ALevel: TLogLevel);
    /// <summary>True when ALevel passes the minimum level and a sink would receive it.</summary>
    function Accepts(ALevel: TLogLevel): Boolean; inline;
    property MinimumLevel: TLogLevel read GetMinimumLevel;
    property SinkCount: Integer read GetSinkCount;
  end;

  /// <summary>
  ///   Logger that formats on the caller's thread and publishes to a
  ///   TRingBuffer. Never blocks: a full queue drops (and counts) the entry.
  /// </summary>
  TAsyncLogger = class(TAbstractLogger)
  private
    FCategory: string;
    FBuffer: TRingBuffer;
    FState: TAsyncLogState;
  protected
    procedure Log(ALevel: TLogLevel; const AMessage: string; const AArgs: array of const); override;
    procedure Log(ALevel: TLogLevel; const AException: Exception; const AMessage: string; const AArgs: array of const); override;

    function IsEnabled(ALevel: TLogLevel): Boolean; override;

    function BeginScope(const AMessage: string; const AArgs: array of const): IDisposable; override;
    function BeginScope(const AState: TObject): IDisposable; override;
  public
    /// <summary>
    ///   Creates a logger for ACategory. AState (owned by the factory) gives
    ///   the minimum level and the sink count; without it every level is
    ///   accepted.
    /// </summary>
    constructor Create(const ACategory: string; ABuffer: TRingBuffer;
      AState: TAsyncLogState = nil);
  end;

  /// <summary>
  ///   Background thread that takes entries from the TRingBuffer and hands
  ///   them to the sinks. Sleeps on the buffer's event while it is empty.
  /// </summary>
  TLogConsumerThread = class(TThread)
  private
    FBuffer: TRingBuffer;
    FState: TAsyncLogState;
    FOwnsState: Boolean;
    FSinks: IList<ILogSink>;
    FLock: TObject;
    FReportedDropped: Integer;
    FStartRequested: Boolean;
    FExecuted: Integer;
    FFinished: Integer;

    function DrainBatch: Integer;
    procedure DispatchEntry(const Entry: TLogEntry);
    procedure ReportDropped;
    procedure Finish;
    function SpinForData: Boolean;
  protected
    procedure Execute; override;
  public
    /// <summary>Creates the (suspended) consumer of ABuffer.</summary>
    constructor Create(ABuffer: TRingBuffer; AState: TAsyncLogState = nil);
    destructor Destroy; override;

    /// <summary>
    ///   Starts the thread. TThread.Started only turns True once the thread is
    ///   already running, so Stop could not tell "never started" from "about
    ///   to run": the request is recorded here.
    /// </summary>
    procedure Start; reintroduce;

    /// <summary>Registers a sink. Thread-safe.</summary>
    procedure AddSink(const ASink: ILogSink);
    /// <summary>Unregisters a sink. Thread-safe.</summary>
    procedure RemoveSink(const ASink: ILogSink);
    /// <summary>True when at least one sink is registered.</summary>
    function HasSinks: Boolean;
    /// <summary>
    ///   Dispatches what is already queued, reports drops, flushes the sinks
    ///   and ends the thread. Safe to call more than once.
    /// </summary>
    procedure Stop;
  end;

  /// <summary>
  ///   Factory that coordinates the async logging pipeline: one queue, one
  ///   consumer thread and the loggers created from it.
  /// </summary>
  TAsyncLoggerFactory = class(TInterfacedObject, ILoggerFactory)
  private
    FBuffer: TRingBuffer;
    FConsumer: TLogConsumerThread;
    FState: TAsyncLogState;
    function GetDropped: Integer;
    function GetMinimumLevel: TLogLevel;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Creates a logger whose entries carry ACategoryName.</summary>
    function CreateLogger(const ACategoryName: string): ILogger;
    /// <summary>Not supported in async mode (sinks replace providers); ignored.</summary>
    procedure AddProvider(const AProvider: ILoggerProvider);
    /// <summary>Registers a sink on the consumer thread.</summary>
    procedure AddSink(const ASink: ILogSink);
    /// <summary>True when at least one sink receives the entries.</summary>
    function HasSinks: Boolean;
    /// <summary>Stops the consumer after it dispatches what is queued.</summary>
    procedure Dispose;
    /// <summary>Entries below ALevel are discarded before formatting.</summary>
    procedure SetMinimumLevel(ALevel: TLogLevel);

    property MinimumLevel: TLogLevel read GetMinimumLevel;
    /// <summary>Entries dropped because the queue was full.</summary>
    property Dropped: Integer read GetDropped;
  end;

implementation

{ TAsyncLogState }

constructor TAsyncLogState.Create;
begin
  inherited Create;
  FMinimumLevel := Ord(TLogLevel.Information);
  FSinkCount := 0;
end;

function TAsyncLogState.GetMinimumLevel: TLogLevel;
begin
  Result := TLogLevel(FMinimumLevel);
end;

function TAsyncLogState.GetSinkCount: Integer;
begin
  Result := FSinkCount;
end;

procedure TAsyncLogState.SetMinimumLevel(ALevel: TLogLevel);
begin
  TInterlocked.Exchange(FMinimumLevel, Ord(ALevel));
end;

function TAsyncLogState.Accepts(ALevel: TLogLevel): Boolean;
begin
  // Aligned Integer reads are atomic; a stale value only delays a change by
  // one call
  Result := (Ord(ALevel) >= FMinimumLevel) and (FSinkCount > 0);
end;

{ TAsyncLogger }

constructor TAsyncLogger.Create(const ACategory: string; ABuffer: TRingBuffer;
  AState: TAsyncLogState);
begin
  inherited Create;
  FCategory := ACategory;
  FBuffer := ABuffer;
  FState := AState;
end;

function TAsyncLogger.IsEnabled(ALevel: TLogLevel): Boolean;
begin
  Result := (ALevel <> TLogLevel.None) and ((FState = nil) or FState.Accepts(ALevel));
end;

procedure TAsyncLogger.Log(ALevel: TLogLevel; const AMessage: string; const AArgs: array of const);
var
  Entry: PLogEntry;
  Position: Integer;
  Node: PScopeNode;
begin
  // Below the minimum level, or nobody listening: no formatting, no slot
  if not IsEnabled(ALevel) then
    Exit;

  if not FBuffer.TryReserve(Position, Entry) then
    Exit; // queue full: dropped and counted by the buffer

  Entry.TimeStamp := Now;
  Entry.Level := ALevel;
  Entry.ThreadID := TThread.CurrentThread.ThreadID;
  Entry.Category := FCategory;

  Node := TraceContext.Current;
  if Node <> nil then
  begin
    Entry.TraceId := Node.TraceId;
    Entry.SpanId := Node.SpanId;
  end
  else
  begin
    Entry.TraceId := TUUID.Empty;
    Entry.SpanId := TUUID.Empty;
  end;

  // The arguments point to the caller's stack: format here, not on the consumer
  Entry.FormattedMessage := TLogFormatter.FormatMessage(AMessage, AArgs);
  Entry.ScopeSnapshot := nil;
  Entry.MessageTemplate := AMessage;

  FBuffer.Publish(Position);
end;

procedure TAsyncLogger.Log(ALevel: TLogLevel; const AException: Exception; const AMessage: string; const AArgs: array of const);
begin
  if not IsEnabled(ALevel) then
    Exit;
  if AException <> nil then
    Log(ALevel, AMessage + ' [Ex: ' + AException.Message + ']', AArgs)
  else
    Log(ALevel, AMessage, AArgs);
end;

function TAsyncLogger.BeginScope(const AMessage: string; const AArgs: array of const): IDisposable;
var
  Node: PScopeNode;
begin
  // Start new scope with generated IDs (auto-handled by TraceContext)
  Node := TraceContext.Push(TLogFormatter.FormatMessage(AMessage, AArgs), TUUID.Empty, TUUID.Empty);
  Result := TScopeGuard.Create(Node);
end;

function TAsyncLogger.BeginScope(const AState: TObject): IDisposable;
var
  Node: PScopeNode;
begin
  Node := TraceContext.Push('ObjectScope', TUUID.Empty, TUUID.Empty);
  Node.State := AState;
  Result := TScopeGuard.Create(Node);
end;

{ TLogConsumerThread }

constructor TLogConsumerThread.Create(ABuffer: TRingBuffer; AState: TAsyncLogState);
begin
  inherited Create(True);
  FBuffer := ABuffer;
  FState := AState;
  FOwnsState := AState = nil;
  if FOwnsState then
    FState := TAsyncLogState.Create;
  FSinks := TCollections.CreateList<ILogSink>;
  FLock := TObject.Create;
  FreeOnTerminate := False;
end;

destructor TLogConsumerThread.Destroy;
begin
  Stop;
  FSinks := nil;
  FLock.Free;
  if FOwnsState then
    FState.Free;
  inherited;
end;

procedure TLogConsumerThread.Start;
begin
  FStartRequested := True;
  inherited Start;
end;

procedure TLogConsumerThread.AddSink(const ASink: ILogSink);
begin
  TMonitor.Enter(FLock);
  try
    FSinks.Add(ASink);
    TInterlocked.Increment(FState.FSinkCount);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogConsumerThread.RemoveSink(const ASink: ILogSink);
begin
  TMonitor.Enter(FLock);
  try
    if FSinks.Remove(ASink) then
      TInterlocked.Decrement(FState.FSinkCount);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLogConsumerThread.HasSinks: Boolean;
begin
  Result := FState.SinkCount > 0;
end;

procedure TLogConsumerThread.Stop;
begin
  if not FStartRequested then
    Exit;
  Terminate;
  FBuffer.Wake;
  WaitFor;
  // TThread skips Execute when it is terminated before the thread starts
  // running: the final drain and flush must still happen
  if FExecuted = 0 then
    Finish;
end;

procedure TLogConsumerThread.DispatchEntry(const Entry: TLogEntry);
var
  i: Integer;
begin
  // Caller holds FLock
  for i := 0 to FSinks.Count - 1 do
  begin
    try
      FSinks[i].Emit(Entry);
    except
      // A failing sink must not stop the pipeline
    end;
  end;
end;

function TLogConsumerThread.DrainBatch: Integer;
var
  Entry: PLogEntry;
begin
  Result := 0;
  if not FBuffer.TryPeek(Entry) then
    Exit;
  // One lock per batch, not per entry
  TMonitor.Enter(FLock);
  try
    repeat
      DispatchEntry(Entry^);
      FBuffer.Release;
      Inc(Result);
    until not FBuffer.TryPeek(Entry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogConsumerThread.ReportDropped;
var
  Dropped: Integer;
  Entry: TLogEntry;
begin
  Dropped := FBuffer.Dropped;
  if Dropped = FReportedDropped then
    Exit;
  Entry := Default(TLogEntry);
  Entry.TimeStamp := Now;
  Entry.Level := TLogLevel.Warning;
  Entry.ThreadID := TThread.CurrentThread.ThreadID;
  Entry.Category := 'Dext.Logging';
  Entry.MessageTemplate := '{Count} log entries dropped: the async queue was full';
  Entry.FormattedMessage := Format('%d log entries dropped: the async queue was full',
    [Dropped - FReportedDropped]);
  FReportedDropped := Dropped;
  TMonitor.Enter(FLock);
  try
    DispatchEntry(Entry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLogConsumerThread.SpinForData: Boolean;
var
  i: Integer;
  Entry: PLogEntry;
begin
  for i := 1 to ASYNC_LOG_SPIN_ROUNDS do
  begin
    if FBuffer.TryPeek(Entry) or Terminated then
      Exit(True);
    TThread.SpinWait(20);
  end;
  Result := False;
end;

procedure TLogConsumerThread.Finish;
begin
  if TInterlocked.Exchange(FFinished, 1) <> 0 then
    Exit;
  // Entries published while we were stopping
  DrainBatch;
  ReportDropped;

  TMonitor.Enter(FLock);
  try
    FSinks.ForEach(
      procedure(S: ILogSink)
      begin
        S.Flush;
      end);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogConsumerThread.Execute;
var
  Count: Integer;
begin
  FExecuted := 1;
  while True do
  begin
    Count := DrainBatch;
    // After a drain, so the warning lands next to the gap it explains
    ReportDropped;
    if Terminated then
      Break;
    // Sleep only when the stream really stopped
    if (Count = 0) and not SpinForData then
      FBuffer.WaitForData(ASYNC_LOG_IDLE_TIMEOUT_MS);
  end;
  Finish;
end;

{ TAsyncLoggerFactory }

constructor TAsyncLoggerFactory.Create;
begin
  inherited Create;
  FState := TAsyncLogState.Create;
  FBuffer := TRingBuffer.Create(ASYNC_LOG_QUEUE_POWER);
  FConsumer := TLogConsumerThread.Create(FBuffer, FState);
  FConsumer.Start;
end;

destructor TAsyncLoggerFactory.Destroy;
begin
  Dispose;
  FConsumer.Free;
  FBuffer.Free;
  FState.Free;
  inherited;
end;

procedure TAsyncLoggerFactory.Dispose;
begin
  if FConsumer <> nil then
    FConsumer.Stop;
end;

procedure TAsyncLoggerFactory.AddProvider(const AProvider: ILoggerProvider);
begin
  // Async mode routes to sinks (AddSink); providers are not wrapped
end;

procedure TAsyncLoggerFactory.AddSink(const ASink: ILogSink);
begin
  FConsumer.AddSink(ASink);
end;

function TAsyncLoggerFactory.HasSinks: Boolean;
begin
  Result := FState.SinkCount > 0;
end;

function TAsyncLoggerFactory.CreateLogger(const ACategoryName: string): ILogger;
begin
  Result := TAsyncLogger.Create(ACategoryName, FBuffer, FState);
end;

function TAsyncLoggerFactory.GetDropped: Integer;
begin
  Result := FBuffer.Dropped;
end;

function TAsyncLoggerFactory.GetMinimumLevel: TLogLevel;
begin
  Result := FState.MinimumLevel;
end;

procedure TAsyncLoggerFactory.SetMinimumLevel(ALevel: TLogLevel);
begin
  FState.SetMinimumLevel(ALevel);
end;

end.
