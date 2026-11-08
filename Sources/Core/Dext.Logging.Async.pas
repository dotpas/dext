{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
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

type
  /// <summary>
  ///   Consumer interface for log entries.
  /// </summary>
  ILogSink = interface
    ['{D1E2F3A4-B5C6-7890-1234-567890ABCDEF}']
    procedure Emit(const Entry: TLogEntry);
    procedure Flush;
  end;

  /// <summary>
  ///   Logger implementation that pushes to a RingBuffer.
  /// </summary>
  TAsyncLogger = class(TAbstractLogger)
  private
    FCategory: string;
    FBuffer: TRingBuffer;
  protected
    procedure Log(ALevel: TLogLevel; const AMessage: string; const AArgs: array of const); override;
    procedure Log(ALevel: TLogLevel; const AException: Exception; const AMessage: string; const AArgs: array of const); override;
    
    function IsEnabled(ALevel: TLogLevel): Boolean; override;
    
    function BeginScope(const AMessage: string; const AArgs: array of const): IDisposable; override;
    function BeginScope(const AState: TObject): IDisposable; override;
  public
    constructor Create(const ACategory: string; ABuffer: TRingBuffer);
  end;

  /// <summary>
  ///   Background thread that consumes logs from RingBuffer and dispatches to Sinks.
  /// </summary>
  TLogConsumerThread = class(TThread)
  private
    FBuffer: TRingBuffer;
    FSinks: IList<ILogSink>;
    FLock: TObject;
    FShutdownEvent: TEvent;
    
    procedure DispatchEntry(const Entry: TLogEntry);
  protected
    procedure Execute; override;
  public
    constructor Create(ABuffer: TRingBuffer);
    destructor Destroy; override;
    
    procedure AddSink(const ASink: ILogSink);
    procedure RemoveSink(const ASink: ILogSink);
    function HasSinks: Boolean;
    procedure Stop;
  end;

  /// <summary>
  ///   Factory that coordinates the Async Logging Pipeline.
  ///   Replaces the standard TLoggerFactory.
  /// </summary>
  TAsyncLoggerFactory = class(TInterfacedObject, ILoggerFactory)
  private
    FBuffer: TRingBuffer;
    FConsumer: TLogConsumerThread;
    FMinimumLevel: TLogLevel;
  public
    constructor Create;
    destructor Destroy; override;

    function CreateLogger(const ACategoryName: string): ILogger;
    procedure AddProvider(const AProvider: ILoggerProvider); // Adapts provider to Sink?
    procedure AddSink(const ASink: ILogSink); // Native method
    /// <summary>True when at least one sink receives the entries.</summary>
    function HasSinks: Boolean;
    procedure Dispose;
    
    procedure SetMinimumLevel(ALevel: TLogLevel);
  end;

implementation

{ TAsyncLogger }

constructor TAsyncLogger.Create(const ACategory: string; ABuffer: TRingBuffer);
begin
  inherited Create;
  FCategory := ACategory;
  FBuffer := ABuffer;
end;

function TAsyncLogger.IsEnabled(ALevel: TLogLevel): Boolean;
begin
  // Optimization: Could check global atomic level
  Result := ALevel <> TLogLevel.None;
end;

procedure TAsyncLogger.Log(ALevel: TLogLevel; const AMessage: string; const AArgs: array of const);
var
  Entry: PLogEntry;
  Node: PScopeNode;
begin
  if not IsEnabled(ALevel) then Exit;
  
  if FBuffer.TryWrite(Entry) then
  begin
    Entry.SequenceId := 0; 
    Entry.TimeStamp := Now;
    Entry.Level := ALevel;
    Entry.ThreadID := TThread.CurrentThread.ThreadID;
    
    // Capture Context
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
    
    // Simplification for V1: Format immediately
    Entry.FormattedMessage := TLogFormatter.FormatMessage(AMessage, AArgs);
      
    Entry.ScopeSnapshot := nil; // We don't need to keep node alive if we copied IDs? 
                                // Actually, if we want full properies we might need to clone.
                                // But for TraceId/SpanId we are good.
    Entry.MessageTemplate := AMessage;
    
    Entry.IsReady := True; // Commit
  end;
end;

procedure TAsyncLogger.Log(ALevel: TLogLevel; const AException: Exception; const AMessage: string; const AArgs: array of const);
begin
  if not IsEnabled(ALevel) then Exit;
  // Similar to above, but formatting exception
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
  // Simpler scope
  Node := TraceContext.Push('ObjectScope', TUUID.Empty, TUUID.Empty);
  Node.State := AState;
  Result := TScopeGuard.Create(Node);
end;

{ TLogConsumerThread }

constructor TLogConsumerThread.Create(ABuffer: TRingBuffer);
begin
  inherited Create(True);
  FBuffer := ABuffer;
  FSinks := TCollections.CreateList<ILogSink>;
  FLock := TObject.Create;
  FShutdownEvent := TEvent.Create;
  FreeOnTerminate := False;
end;

destructor TLogConsumerThread.Destroy;
begin
  FSinks := nil;
  FLock.Free;
  FShutdownEvent.Free;
  inherited;
end;

procedure TLogConsumerThread.AddSink(const ASink: ILogSink);
begin
  TMonitor.Enter(FLock);
  try
    FSinks.Add(ASink);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogConsumerThread.RemoveSink(const ASink: ILogSink);
begin
  TMonitor.Enter(FLock);
  try
    FSinks.Remove(ASink);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLogConsumerThread.HasSinks: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FSinks.Count > 0;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLogConsumerThread.Stop;
begin
  FShutdownEvent.SetEvent;
  WaitFor;
end;

procedure TLogConsumerThread.Execute;
var
  Entry: TLogEntry;
  WaitRes: TWaitResult;
begin
  while not Terminated do
  begin
    if FBuffer.TryRead(Entry) then
    begin
      DispatchEntry(Entry);
    end
    else
    begin
      // If buffer empty, wait or sleep
      // Check for shutdown
      WaitRes := FShutdownEvent.WaitFor(1); // Sleep 1ms or wake on shutdown
      if WaitRes = wrSignaled then
      begin
        // Drain buffer
        while FBuffer.TryRead(Entry) do
          DispatchEntry(Entry);
        Terminate;
      end;
    end;
  end;
  
  // Final flush
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

procedure TLogConsumerThread.DispatchEntry(const Entry: TLogEntry);
var
  I: Integer;
begin
  TMonitor.Enter(FLock);
  try
    for I := 0 to FSinks.Count - 1 do
    begin
      try
        FSinks[I].Emit(Entry);
      except
        // Swallow sink errors to protect pipeline
      end;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TAsyncLoggerFactory }

constructor TAsyncLoggerFactory.Create;
begin
  inherited Create;
  // 65536 entries
  FBuffer := TRingBuffer.Create(16); 
  FConsumer := TLogConsumerThread.Create(FBuffer);
  FConsumer.Start;
  FMinimumLevel := TLogLevel.Information;
end;

destructor TAsyncLoggerFactory.Destroy;
begin
  Dispose;
  FConsumer.Free;
  FBuffer.Free;
  inherited;
end;

procedure TAsyncLoggerFactory.Dispose;
begin
  if FConsumer <> nil then
    FConsumer.Stop;
end;

procedure TAsyncLoggerFactory.AddSink(const ASink: ILogSink);
begin
  FConsumer.AddSink(ASink);
end;

function TAsyncLoggerFactory.HasSinks: Boolean;
begin
  Result := (FConsumer <> nil) and FConsumer.HasSinks;
end;

procedure TAsyncLoggerFactory.AddProvider(const AProvider: ILoggerProvider);
begin
  // Adaptation layer: If we must support ILoggerProvider, we need to wrap it?
  // Or simply ignore it if we move to Sinks.
  // For Dext compatibility, we might need to wrap.
  // Ignoring for phase 1.
end;

function TAsyncLoggerFactory.CreateLogger(const ACategoryName: string): ILogger;
begin
  Result := TAsyncLogger.Create(ACategoryName, FBuffer);
end;

procedure TAsyncLoggerFactory.SetMinimumLevel(ALevel: TLogLevel);
begin
  FMinimumLevel := ALevel;
end;

end.
