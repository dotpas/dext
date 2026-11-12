{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{***************************************************************************}
unit Dext.Server.BoundedExecutor;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  /// <summary>
  ///   Callback procedure pointer type for executor tasks.
  /// </summary>
  TDextTaskProc = procedure(Data: Pointer);

  /// <summary>
  ///   Called for every queued raw task (Proc/Data) that is thrown away without running
  ///   (Shutdown without draining, or destruction). The owner of Data frees it here.
  /// </summary>
  TDextTaskDiscard = reference to procedure(AProc: TDextTaskProc; AData: Pointer);

  TDextTaskItem = record
    Proc: TDextTaskProc;
    Data: Pointer;
  end;

  /// <summary>
  ///   High-performance non-generic circular ring buffer task queue.
  /// </summary>
  TDextTaskQueue = record
  private
    FItems: TArray<TDextTaskItem>;
    FHead: Integer;
    FTail: Integer;
    FCount: Integer;
    FCapacity: Integer;
  public
    procedure Initialize(ACapacity: Integer);
    procedure Clear;
    function Enqueue(const ATask: TDextTaskItem): Boolean;
    function Dequeue(var ATask: TDextTaskItem): Boolean;
    property Count: Integer read FCount;
  end;

  /// <summary>
  ///   Lightweight high-performance bounded task executor pool.
  /// </summary>
  TDextBoundedExecutor = class
  private
    FThreads: TArray<TThread>;
    FQueue: TDextTaskQueue;
    FLock: TCriticalSection;
    FSemaphore: TSemaphore;
    FMaxThreads: Integer;
    FMaxQueueCapacity: Integer;
    FRunning: Boolean;
    FQueueCount: Integer;
    FOnException: TProc<Exception>;
    FOnDiscard: TDextTaskDiscard;
    FFailureCount: Integer;
    FLastFailure: string;
    procedure WorkerExecute(AThread: TThread);
    procedure DiscardItem(const ATask: TDextTaskItem);
    procedure DiscardPending;
    procedure RecordFailure(E: Exception);
    function GetLastFailure: string;
    function GetRunning: Boolean;
  public
    constructor Create(AMaxThreads, AMaxQueueCapacity: Integer);
    destructor Destroy; override;
    function TryEnqueue(AProc: TDextTaskProc; AData: Pointer): Boolean; overload;
    function TryEnqueue(const AProc: TProc): Boolean; overload;
    /// <summary>
    ///   Stops accepting tasks and joins the workers. With ADrain = False (default) the
    ///   tasks still queued are discarded (see OnDiscard); with ADrain = True the workers
    ///   first run everything that was already accepted. Tasks that are running always
    ///   finish: a thread is never killed. Safe to call more than once.
    /// </summary>
    procedure Shutdown(ADrain: Boolean = False);
    property QueueCount: Integer read FQueueCount;
    /// <summary>True until Shutdown was requested.</summary>
    property Running: Boolean read GetRunning;
    /// <summary>Called (on the worker thread) when a task raises. Exceptions raised by the handler are contained.</summary>
    property OnException: TProc<Exception> read FOnException write FOnException;
    /// <summary>Called for raw tasks discarded without running, so their Data can be freed.</summary>
    property OnDiscard: TDextTaskDiscard read FOnDiscard write FOnDiscard;
    /// <summary>Number of tasks that raised, whether or not OnException is set.</summary>
    property FailureCount: Integer read FFailureCount;
    /// <summary>Message of the most recent task failure.</summary>
    property LastFailure: string read GetLastFailure;
  end;

type
  THackThread = class(TThread);

implementation

{ TDextTaskQueue }

procedure TDextTaskQueue.Initialize(ACapacity: Integer);
begin
  SetLength(FItems, ACapacity);
  FHead := 0;
  FTail := 0;
  FCount := 0;
  FCapacity := ACapacity;
end;

procedure TDextTaskQueue.Clear;
var
  i: Integer;
begin
  for i := 0 to Length(FItems) - 1 do
  begin
    FItems[i].Proc := nil;
    FItems[i].Data := nil;
  end;
  FHead := 0;
  FTail := 0;
  FCount := 0;
end;

function TDextTaskQueue.Enqueue(const ATask: TDextTaskItem): Boolean;
begin
  if FCount >= FCapacity then
    Exit(False);

  FItems[FTail] := ATask;
  FTail := (FTail + 1) mod FCapacity;
  Inc(FCount);
  Result := True;
end;

function TDextTaskQueue.Dequeue(var ATask: TDextTaskItem): Boolean;
begin
  if FCount <= 0 then
    Exit(False);

  ATask := FItems[FHead];
  FItems[FHead].Proc := nil;
  FItems[FHead].Data := nil;
  FHead := (FHead + 1) mod FCapacity;
  Dec(FCount);
  Result := True;
end;

{ TDextBoundedExecutor }

constructor TDextBoundedExecutor.Create(
  AMaxThreads, AMaxQueueCapacity: Integer);
var
  i: Integer;
begin
  inherited Create;
  FMaxThreads := AMaxThreads;
  FMaxQueueCapacity := AMaxQueueCapacity;
  FQueue.Initialize(FMaxQueueCapacity);
  FLock := TCriticalSection.Create;
  FSemaphore := TSemaphore.Create(nil, 0, FMaxQueueCapacity + FMaxThreads, '');
  FRunning := True;
  FQueueCount := 0;

  SetLength(FThreads, FMaxThreads);
  for i := 0 to FMaxThreads - 1 do
  begin
    FThreads[i] := TThread.CreateAnonymousThread(
      procedure
      begin
        WorkerExecute(TThread.CurrentThread);
      end);
    FThreads[i].FreeOnTerminate := False;
    FThreads[i].Start;
  end;
end;

procedure AnonymousTaskExecutor(Data: Pointer); forward;

destructor TDextBoundedExecutor.Destroy;
begin
  Shutdown(False);
  DiscardPending;
  FLock.Free;
  FSemaphore.Free;
  inherited Destroy;
end;

function TDextBoundedExecutor.GetRunning: Boolean;
begin
  FLock.Enter;
  try
    Result := FRunning;
  finally
    FLock.Leave;
  end;
end;

function TDextBoundedExecutor.GetLastFailure: string;
begin
  FLock.Enter;
  try
    Result := FLastFailure;
  finally
    FLock.Leave;
  end;
end;

procedure TDextBoundedExecutor.RecordFailure(E: Exception);
begin
  TInterlocked.Increment(FFailureCount);
  FLock.Enter;
  try
    FLastFailure := E.ClassName + ': ' + E.Message;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnException) then
  begin
    try
      FOnException(E);
    except
      // A faulty handler must not take the worker thread down with it.
    end;
  end;
end;

procedure TDextBoundedExecutor.DiscardItem(const ATask: TDextTaskItem);
begin
  if not Assigned(ATask.Proc) then
    Exit;
  if @ATask.Proc = @AnonymousTaskExecutor then
  begin
    if ATask.Data <> nil then
      IInterface(ATask.Data)._Release;
  end
  else if Assigned(FOnDiscard) then
    FOnDiscard(ATask.Proc, ATask.Data);
end;

procedure TDextBoundedExecutor.DiscardPending;
var
  Task: TDextTaskItem;
  Got: Boolean;
begin
  repeat
    FLock.Enter;
    try
      Got := FQueue.Dequeue(Task);
      FQueueCount := FQueue.Count;
    finally
      FLock.Leave;
    end;
    if Got then
      DiscardItem(Task);
  until not Got;
end;

procedure TDextBoundedExecutor.Shutdown(ADrain: Boolean);
var
  i: Integer;
begin
  FLock.Enter;
  try
    if not FRunning then
      Exit;
    FRunning := False;
  finally
    FLock.Leave;
  end;

  if not ADrain then
    DiscardPending;

  if Length(FThreads) > 0 then
    FSemaphore.Release(Length(FThreads));

  for i := 0 to Length(FThreads) - 1 do
  begin
    if FThreads[i] <> nil then
    begin
      // When draining, the workers leave by themselves once the queue is empty.
      if not ADrain then
        FThreads[i].Terminate;
      FThreads[i].WaitFor;
      FThreads[i].Free;
      FThreads[i] := nil;
    end;
  end;

  // With no workers (or tasks accepted by a race) nothing runs the rest: discard it.
  if ADrain then
    DiscardPending;
end;

procedure AnonymousTaskExecutor(Data: Pointer);
var
  Proc: TProc;
  P: Pointer absolute Proc;
begin
  if Data = nil then
    Exit;

  P := Data;
  try
    if Assigned(Proc) then
      Proc();
  finally
    // Release the manual reference held for the queue, and zero out P (Proc)
    // so the compiler's automatic _IntfClear does not run on freed memory.
    IInterface(Data)._Release;
    P := nil;
  end;
end;

function TDextBoundedExecutor.TryEnqueue(AProc: TDextTaskProc; AData: Pointer): Boolean;
var
  Item: TDextTaskItem;
begin
  Result := False;
  Item.Proc := AProc;
  Item.Data := AData;
  FLock.Enter;
  try
    if FRunning and FQueue.Enqueue(Item) then
    begin
      FQueueCount := FQueue.Count;
      Result := True;
    end;
  finally
    FLock.Leave;
  end;
  if Result then
    FSemaphore.Release;
end;

function TDextBoundedExecutor.TryEnqueue(const AProc: TProc): Boolean;
var
  LProc: TProc;
  P: Pointer absolute LProc;
begin
  if not Assigned(AProc) then
    Exit(False);

  LProc := AProc;
  IInterface(P)._AddRef; // Explicitly retain 1 reference for queue duration

  if not TryEnqueue(AnonymousTaskExecutor, P) then
  begin
    IInterface(P)._Release;
    Exit(False);
  end;
  Result := True;
end;

procedure TDextBoundedExecutor.WorkerExecute(AThread: TThread);
var
  Task: TDextTaskItem;
  Got: Boolean;
  Running: Boolean;
begin
  while not THackThread(AThread).Terminated do
  begin
    FSemaphore.WaitFor(INFINITE);

    Task.Proc := nil;
    Task.Data := nil;
    FLock.Enter;
    try
      Got := FQueue.Dequeue(Task);
      if Got then
        FQueueCount := FQueue.Count;
      Running := FRunning;
    finally
      FLock.Leave;
    end;

    if Got then
    begin
      try
        Task.Proc(Task.Data);
      except
        on E: Exception do
          RecordFailure(E);
      end;
    end
    else if not Running then
      Break; // shut down and nothing left to run
  end;
end;

end.
