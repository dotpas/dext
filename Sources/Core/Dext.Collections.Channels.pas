unit Dext.Collections.Channels;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.TypInfo,
  Dext.Collections.Memory,
  Dext.Threading.CancellationToken;

type
  /// <summary>Base class of the channel exceptions.</summary>
  EChannelException = class(Exception);

  /// <summary>Raised by Write when the channel was closed.</summary>
  EChannelClosedException = class(EChannelException);

  /// <summary>
  ///   Raised by Read when the channel was closed and every item was already
  ///   consumed: the normal end of a stream, not a fault.
  /// </summary>
  EChannelCompletedException = class(EChannelException);

  /// <summary>
  ///   Represents a concurrent communication channel for passing data between
  ///   threads. Blocking members have variants with a timeout and with a
  ///   cancellation token, so a thread is never stuck forever by design.
  /// </summary>
  IChannel<T> = interface
    /// <summary>Attempts to write an item to the channel without blocking. Returns true if successful.</summary>
    function TryWrite(const Value: T): Boolean; overload;
    /// <summary>Waits up to ATimeoutMs for room. False if the channel stayed full or was closed.</summary>
    function TryWrite(const Value: T; ATimeoutMs: Cardinal): Boolean; overload;
    /// <summary>Attempts to read an item from the channel without blocking. Returns true if an item was read.</summary>
    function TryRead(out Value: T): Boolean; overload;
    /// <summary>
    ///   Waits up to ATimeoutMs for an item. False on timeout or when the
    ///   channel is completed (tell them apart with IsCompleted).
    /// </summary>
    function TryRead(out Value: T; ATimeoutMs: Cardinal): Boolean; overload;
    /// <summary>Writes an item. Blocks while a bounded channel is full. Raises EChannelClosedException if closed.</summary>
    procedure Write(const Value: T); overload;
    /// <summary>Like Write, but raises EOperationCancelled when AToken is cancelled while waiting.</summary>
    procedure Write(const Value: T; const AToken: ICancellationToken); overload;
    /// <summary>Reads an item. Blocks until one arrives. Raises EChannelCompletedException at the end of the stream.</summary>
    function Read: T; overload;
    /// <summary>Like Read, but raises EOperationCancelled when AToken is cancelled while waiting.</summary>
    function Read(const AToken: ICancellationToken): T; overload;
    /// <summary>Closes the channel, preventing further writes. Items already queued can still be read.</summary>
    procedure Close;
    /// <summary>Indicates whether the channel has been closed.</summary>
    function IsClosed: Boolean;
    /// <summary>True when the channel is closed and empty: nothing more will ever be read.</summary>
    function IsCompleted: Boolean;
    /// <summary>Number of items waiting to be read.</summary>
    function Count: Integer;
  end;

  TChannelQueue<T> = class
  private
    FData: Pointer;
    FHead, FTail, FCount, FCapacity: Integer;
    procedure EnsureCapacity(NewCapacity: Integer);
  public
    constructor Create(InitialCapacity: Integer = 16);
    destructor Destroy; override;
    
    procedure Enqueue(const Value: T);
    function Dequeue(out Value: T): Boolean;
    property Count: Integer read FCount;
    property Capacity: Integer read FCapacity;
  end;

  TBoundedChannel<T> = class(TInterfacedObject, IChannel<T>)
  private
    type
      TOutcome = (oReady, oClosed, oTimeout, oCancelled);
  private
    FQueue: TChannelQueue<T>;
    FMaxCapacity: Integer;
    FClosed: Boolean;
    FLockObj: TObject;
    function Await(AForWrite: Boolean; ATimeoutMs: Cardinal;
      const AToken: ICancellationToken): TOutcome;
    function DoRead(out Value: T; ATimeoutMs: Cardinal;
      const AToken: ICancellationToken): TOutcome;
    function DoWrite(const Value: T; ATimeoutMs: Cardinal;
      const AToken: ICancellationToken): TOutcome;
  public
    constructor Create(MaxCapacity: Integer);
    destructor Destroy; override;
    
    function TryWrite(const Value: T): Boolean; overload;
    function TryWrite(const Value: T; ATimeoutMs: Cardinal): Boolean; overload;
    function TryRead(out Value: T): Boolean; overload;
    function TryRead(out Value: T; ATimeoutMs: Cardinal): Boolean; overload;
    procedure Write(const Value: T); overload;
    procedure Write(const Value: T; const AToken: ICancellationToken); overload;
    function Read: T; overload;
    function Read(const AToken: ICancellationToken): T; overload;
    procedure Close;
    function IsClosed: Boolean;
    function IsCompleted: Boolean;
    function Count: Integer;
  end;

  /// <summary>A bounded channel whose limit is never reached in practice.</summary>
  TUnboundedChannel<T> = class(TBoundedChannel<T>)
  public
    constructor Create;
  end;

  /// <summary>
  ///   Factory for creating concurrent communication channels.
  /// </summary>
  TChannel<T> = class
  public
    /// <summary>Creates a channel with a fixed maximum capacity (must be at least 1).</summary>
    class function CreateBounded(Capacity: Integer): IChannel<T>;
    /// <summary>Creates a channel with virtually unlimited capacity.</summary>
    class function CreateUnbounded: IChannel<T>;
  end;

implementation

uses
  System.Diagnostics;

{ TChannelQueue<T> }

constructor TChannelQueue<T>.Create(InitialCapacity: Integer);
begin
  inherited Create;
  if InitialCapacity < 4 then InitialCapacity := 4;
  FCapacity := InitialCapacity;
  FCount := 0;
  FHead := 0;
  FTail := 0;
  GetMem(FData, FCapacity * SizeOf(T));
  FillChar(FData^, FCapacity * SizeOf(T), 0);
end;

destructor TChannelQueue<T>.Destroy;
var
  I, Idx: Integer;
begin
  if FCount > 0 then
  begin
    for I := 0 to FCount - 1 do
    begin
      Idx := (FHead + I) mod FCapacity;
      RawFinalizeElement(PByte(FData) + (Idx * SizeOf(T)), SizeOf(T), System.TypeInfo(T));
    end;
  end;
  FreeMem(FData);
  inherited;
end;

procedure TChannelQueue<T>.EnsureCapacity(NewCapacity: Integer);
var
  NewData: Pointer;
  I: Integer;
begin
  if NewCapacity <= FCapacity then Exit;
  
  GetMem(NewData, NewCapacity * SizeOf(T));
  FillChar(NewData^, NewCapacity * SizeOf(T), 0);
  
  // Realign elements to the new buffer starting from index 0
  for I := 0 to FCount - 1 do
  begin
    RawMove(
      PByte(NewData) + (I * SizeOf(T)), 
      PByte(FData) + (((FHead + I) mod FCapacity) * SizeOf(T)), 
      1, SizeOf(T), System.TypeInfo(T)
    );
  end;
  
  FreeMem(FData);
  FData := NewData;
  FCapacity := NewCapacity;
  FHead := 0;
  FTail := FCount;
end;

procedure TChannelQueue<T>.Enqueue(const Value: T);
begin
  if FCount = FCapacity then
    EnsureCapacity(FCapacity * 2);
    
  RawCopyElement(PByte(FData) + (FTail * SizeOf(T)), @Value, SizeOf(T), System.TypeInfo(T));
  FTail := (FTail + 1) mod FCapacity;
  Inc(FCount);
end;

function TChannelQueue<T>.Dequeue(out Value: T): Boolean;
var
  TargetPtr: Pointer;
begin
  if FCount = 0 then Exit(False);
  
  TargetPtr := PByte(FData) + (FHead * SizeOf(T));
  RawCopyElement(@Value, TargetPtr, SizeOf(T), System.TypeInfo(T));
  RawFinalizeElement(TargetPtr, SizeOf(T), System.TypeInfo(T));
  
  FHead := (FHead + 1) mod FCapacity;
  Dec(FCount);
  Result := True;
end;


{ TBoundedChannel<T> }

constructor TBoundedChannel<T>.Create(MaxCapacity: Integer);
begin
  inherited Create;
  if MaxCapacity < 1 then
    raise EArgumentOutOfRangeException.CreateFmt(
      'Channel capacity must be at least 1 (got %d).', [MaxCapacity]);
  FMaxCapacity := MaxCapacity;
  // The queue grows on demand: a large limit does not reserve memory.
  if MaxCapacity < 16 then
    FQueue := TChannelQueue<T>.Create(MaxCapacity)
  else
    FQueue := TChannelQueue<T>.Create(16);
  FLockObj := TObject.Create;
end;

destructor TBoundedChannel<T>.Destroy;
begin
  // Also runs when the constructor raised (invalid capacity): fields may be nil.
  if FLockObj <> nil then
    Close;
  FQueue.Free;
  FLockObj.Free;
  inherited;
end;

procedure TBoundedChannel<T>.Close;
begin
  System.TMonitor.Enter(FLockObj);
  try
    FClosed := True;
    System.TMonitor.PulseAll(FLockObj);
  finally
    System.TMonitor.Exit(FLockObj);
  end;
end;

function TBoundedChannel<T>.IsClosed: Boolean;
begin
  System.TMonitor.Enter(FLockObj);
  try
    Result := FClosed;
  finally
    System.TMonitor.Exit(FLockObj);
  end;
end;

function TBoundedChannel<T>.IsCompleted: Boolean;
begin
  System.TMonitor.Enter(FLockObj);
  try
    Result := FClosed and (FQueue.Count = 0);
  finally
    System.TMonitor.Exit(FLockObj);
  end;
end;

function TBoundedChannel<T>.Count: Integer;
begin
  System.TMonitor.Enter(FLockObj);
  try
    Result := FQueue.Count;
  finally
    System.TMonitor.Exit(FLockObj);
  end;
end;

// Must be called with the lock held. Waits (releasing the lock) until the
// operation can proceed, the channel closes, the time runs out or the token
// is cancelled. A cancellation wakes the wait through the callback registered
// by the caller.
function TBoundedChannel<T>.Await(AForWrite: Boolean; ATimeoutMs: Cardinal;
  const AToken: ICancellationToken): TOutcome;
var
  LWatch: TStopwatch;
  LElapsed: Int64;
  LWait: Cardinal;
begin
  LWatch := TStopwatch.StartNew;
  while True do
  begin
    if AForWrite then
    begin
      if FClosed then Exit(oClosed);
      if FQueue.Count < FMaxCapacity then Exit(oReady);
    end
    else
    begin
      if FQueue.Count > 0 then Exit(oReady);
      if FClosed then Exit(oClosed);
    end;

    if (AToken <> nil) and AToken.IsCancellationRequested then
      Exit(oCancelled);

    if ATimeoutMs = INFINITE then
      LWait := INFINITE
    else
    begin
      LElapsed := LWatch.ElapsedMilliseconds;
      if LElapsed >= ATimeoutMs then
        Exit(oTimeout);
      LWait := Cardinal(ATimeoutMs - LElapsed);
    end;
    System.TMonitor.Wait(FLockObj, LWait);
  end;
end;

function TBoundedChannel<T>.DoRead(out Value: T; ATimeoutMs: Cardinal;
  const AToken: ICancellationToken): TOutcome;
var
  LReg: ICancellationRegistration;
begin
  LReg := nil;
  if AToken <> nil then
    LReg := AToken.Register(
      procedure
      begin
        System.TMonitor.Enter(FLockObj);
        try
          System.TMonitor.PulseAll(FLockObj);
        finally
          System.TMonitor.Exit(FLockObj);
        end;
      end);
  try
    System.TMonitor.Enter(FLockObj);
    try
      Result := Await(False, ATimeoutMs, AToken);
      if Result = oReady then
      begin
        FQueue.Dequeue(Value);
        System.TMonitor.PulseAll(FLockObj);
      end;
    finally
      System.TMonitor.Exit(FLockObj);
    end;
  finally
    if LReg <> nil then
      LReg.Unregister;
  end;
end;

function TBoundedChannel<T>.DoWrite(const Value: T; ATimeoutMs: Cardinal;
  const AToken: ICancellationToken): TOutcome;
var
  LReg: ICancellationRegistration;
begin
  LReg := nil;
  if AToken <> nil then
    LReg := AToken.Register(
      procedure
      begin
        System.TMonitor.Enter(FLockObj);
        try
          System.TMonitor.PulseAll(FLockObj);
        finally
          System.TMonitor.Exit(FLockObj);
        end;
      end);
  try
    System.TMonitor.Enter(FLockObj);
    try
      Result := Await(True, ATimeoutMs, AToken);
      if Result = oReady then
      begin
        FQueue.Enqueue(Value);
        System.TMonitor.PulseAll(FLockObj);
      end;
    finally
      System.TMonitor.Exit(FLockObj);
    end;
  finally
    if LReg <> nil then
      LReg.Unregister;
  end;
end;

function TBoundedChannel<T>.TryRead(out Value: T): Boolean;
begin
  System.TMonitor.Enter(FLockObj);
  try
    if FQueue.Count > 0 then
    begin
      FQueue.Dequeue(Value);
      System.TMonitor.PulseAll(FLockObj);
      Exit(True);
    end;
    Result := False;
  finally
    System.TMonitor.Exit(FLockObj);
  end;
end;

function TBoundedChannel<T>.TryRead(out Value: T; ATimeoutMs: Cardinal): Boolean;
begin
  Result := DoRead(Value, ATimeoutMs, nil) = oReady;
end;

function TBoundedChannel<T>.TryWrite(const Value: T): Boolean;
begin
  System.TMonitor.Enter(FLockObj);
  try
    if FClosed then Exit(False);
    if FQueue.Count < FMaxCapacity then
    begin
      FQueue.Enqueue(Value);
      System.TMonitor.PulseAll(FLockObj);
      Exit(True);
    end;
    Result := False;
  finally
    System.TMonitor.Exit(FLockObj);
  end;
end;

function TBoundedChannel<T>.TryWrite(const Value: T; ATimeoutMs: Cardinal): Boolean;
begin
  Result := DoWrite(Value, ATimeoutMs, nil) = oReady;
end;

function TBoundedChannel<T>.Read: T;
begin
  Result := Read(nil);
end;

function TBoundedChannel<T>.Read(const AToken: ICancellationToken): T;
begin
  case DoRead(Result, INFINITE, AToken) of
    oReady: Exit;
    oCancelled: AToken.ThrowIfCancellationRequested;
  end;
  raise EChannelCompletedException.Create(
    'Channel is closed and has no more items.');
end;

procedure TBoundedChannel<T>.Write(const Value: T);
begin
  Write(Value, nil);
end;

procedure TBoundedChannel<T>.Write(const Value: T; const AToken: ICancellationToken);
begin
  case DoWrite(Value, INFINITE, AToken) of
    oReady: Exit;
    oCancelled: AToken.ThrowIfCancellationRequested;
  end;
  raise EChannelClosedException.Create('Channel is closed.');
end;


{ TUnboundedChannel<T> }

constructor TUnboundedChannel<T>.Create;
begin
  inherited Create(High(Integer));
end;


{ TChannel<T> }

class function TChannel<T>.CreateBounded(Capacity: Integer): IChannel<T>;
begin
  Result := TBoundedChannel<T>.Create(Capacity);
end;

class function TChannel<T>.CreateUnbounded: IChannel<T>;
begin
  Result := TUnboundedChannel<T>.Create;
end;

end.
