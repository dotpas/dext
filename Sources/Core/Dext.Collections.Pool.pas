unit Dext.Collections.Pool;

interface

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Dext.Resilience;

type
  /// <summary>
  ///   Interface implemented by objects that require automated state cleanup
  ///   or sanitization before returning to a TDextPool instance.
  /// </summary>
  IPoolable = interface
    ['{8E7A6B5C-4D3E-2F1A-0B9C-8D7E6F5A4B3C}']
    procedure ResetState;
  end;

  /// <summary>
  ///   Configuration settings for TDextPool<T>.
  /// </summary>
  TDextPoolConfig = record
    MinSize: Integer;
    MaxSize: Integer;
    IdleTimeoutMs: Integer;
    AcquireTimeoutMs: Integer;
    class function Default: TDextPoolConfig; static;
  end;

  /// <summary>
  ///   ARC-managed wrapper that automatically releases an acquired pool item back to its pool
  ///   when the interface goes out of scope (RAII pattern).
  /// </summary>
  IPooledObject<T: class> = interface
    ['{7A8B9C0D-1E2F-3A4B-5C6D-7E8F9A0B1C2D}']
    function GetItem: T;
    function HasItem: Boolean;
    property Item: T read GetItem;
  end;

  IDextPool<T: class> = interface;

  /// <summary>
  ///   Implementation of IPooledObject<T> for automatic RAII pool item release.
  /// </summary>
  TPooledObject<T: class> = class(TInterfacedObject, IPooledObject<T>)
  private
    FPool: IDextPool<T>;
    FItem: T;
  public
    constructor Create(const APool: IDextPool<T>; AItem: T);
    destructor Destroy; override;
    function GetItem: T;
    function HasItem: Boolean;
    property Item: T read GetItem;
  end;

  /// <summary>
  ///   Generic interface for high-performance thread-safe object pools.
  /// </summary>
  IDextPool<T: class> = interface
    ['{1F2E3D4C-5B6A-7F8E-9D0C-1A2B3C4D5E6F}']
    function Acquire(out AItem: T): Boolean;
    function AcquireScoped(out AScoped: IPooledObject<T>): Boolean; overload;
    function AcquireScoped: IPooledObject<T>; overload;
    procedure Release(AItem: T);
    procedure Use(const AProc: TProc<T>); overload;
    function GetCount: Integer;
    property Count: Integer read GetCount;
  end;

  /// <summary>
  ///   High-performance, thread-safe generic object pool with auto-recycling.
  /// </summary>
  TDextPool<T: class, constructor> = class(TInterfacedObject, IDextPool<T>)
  private
    FConfig: TDextPoolConfig;
    FFactory: TFunc<T>;
    FResetAction: TProc<T>;
    FItems: TArray<T>;
    FIdleSince: TArray<UInt64>; // tick at which each idle item was returned
    FLock: TSpinLock;
    FAvailableEvent: TEvent;
    FCount: Integer;
    FTotalAllocated: Integer;
    FIsDisposing: Integer; // 0 = False, 1 = True (atomic access)
    FActiveWaiters: Integer; // Active acquire waiters count (atomic access)
    procedure InternalPush(AItem: T);
    function InternalPop(out AItem: T): Boolean;
    function CreateInstance: T;
    procedure TrimIdle;
  public
    constructor Create(const AConfig: TDextPoolConfig; const AResetAction: TProc<T> = nil); overload;
    constructor Create(const AConfig: TDextPoolConfig; const AFactory: TFunc<T>; const AResetAction: TProc<T> = nil); overload;
    destructor Destroy; override;

    function Acquire(out AItem: T): Boolean;
    function AcquireScoped(out AScoped: IPooledObject<T>): Boolean; overload;
    function AcquireScoped: IPooledObject<T>; overload;
    procedure Release(AItem: T);
    procedure Use(const AProc: TProc<T>); overload;
    function Use<TResult>(const AFunc: TFunc<T, TResult>): TResult; overload;
    function GetCount: Integer;
    property Count: Integer read GetCount;
  end;

implementation

uses
  System.Diagnostics;

{ TDextPoolConfig }

class function TDextPoolConfig.Default: TDextPoolConfig;
begin
  Result.MinSize := 4;
  Result.MaxSize := 64;
  Result.IdleTimeoutMs := 30000;
  Result.AcquireTimeoutMs := 5000;
end;

{ TDextPool<T> }

constructor TDextPool<T>.Create(const AConfig: TDextPoolConfig; const AResetAction: TProc<T>);
begin
  Create(AConfig, nil, AResetAction);
end;

constructor TDextPool<T>.Create(const AConfig: TDextPoolConfig; const AFactory: TFunc<T>; const AResetAction: TProc<T>);
var
  I: Integer;
  Item: T;
begin
  inherited Create;
  FConfig := AConfig;
  FFactory := AFactory;
  FResetAction := AResetAction;
  FLock := TSpinLock.Create(False);
  FAvailableEvent := TEvent.Create(nil, True, False, ''); // ManualReset = True for broadcast signaling
  FCount := 0;
  FTotalAllocated := 0;
  FIsDisposing := 0;
  FActiveWaiters := 0;

  if FConfig.MaxSize < 1 then
    FConfig.MaxSize := 64;
  if FConfig.MinSize > FConfig.MaxSize then
    FConfig.MinSize := FConfig.MaxSize;

  SetLength(FItems, FConfig.MaxSize);
  SetLength(FIdleSince, FConfig.MaxSize);

  // Warm-up pool with MinSize instances
  for I := 0 to FConfig.MinSize - 1 do
  begin
    Item := CreateInstance;
    InternalPush(Item);
  end;
end;

destructor TDextPool<T>.Destroy;
var
  Item: T;
  Obj: TObject;
begin
  // 1. Mark shutdown atomically
  AtomicExchange(FIsDisposing, 1);

  // 2. Unblock any threads waiting on FAvailableEvent
  FAvailableEvent.SetEvent;

  // 3. Wait for all active waiters to exit their WaitFor block cleanly
  while AtomicCmpExchange(FActiveWaiters, 0, 0) > 0 do
    TThread.Sleep(1);

  FLock.Enter;
  try
    while FCount > 0 do
    begin
      Dec(FCount);
      Item := FItems[FCount];
      FItems[FCount] := nil;
      Obj := TObject(Item);
      Obj.Free;
    end;
  finally
    FLock.Exit;
  end;

  FAvailableEvent.Free;
  inherited Destroy;
end;

function TDextPool<T>.CreateInstance: T;
begin
  if Assigned(FFactory) then
    Result := FFactory()
  else
    Result := T.Create;
  Inc(FTotalAllocated);
end;

procedure TDextPool<T>.InternalPush(AItem: T);
begin
  FItems[FCount] := AItem;
  FIdleSince[FCount] := GetTickCount64;
  Inc(FCount);
end;

function TDextPool<T>.InternalPop(out AItem: T): Boolean;
begin
  if FCount > 0 then
  begin
    Dec(FCount);
    AItem := FItems[FCount];
    FItems[FCount] := nil;
    Result := True;
  end
  else
  begin
    AItem := nil;
    Result := False;
  end;
end;

procedure TDextPool<T>.TrimIdle;
var
  Victims: TArray<TObject>;
  Now: UInt64;
  I, K: Integer;
begin
  // Lazy idle eviction, run by Acquire and Release. The stack keeps the
  // oldest idle item at the bottom, so the idle ones are a prefix: they are
  // removed until MinSize is reached or an item still within the limit.
  if FConfig.IdleTimeoutMs <= 0 then
    Exit;
  Victims := nil;
  FLock.Enter;
  try
    Now := GetTickCount64;
    K := 0;
    while (FCount - K > FConfig.MinSize) and
          (Now - FIdleSince[K] >= UInt64(FConfig.IdleTimeoutMs)) do
      Inc(K);
    if K = 0 then
      Exit;
    SetLength(Victims, K);
    for I := 0 to K - 1 do
      Victims[I] := TObject(FItems[I]);
    for I := K to FCount - 1 do
    begin
      FItems[I - K] := FItems[I];
      FIdleSince[I - K] := FIdleSince[I];
    end;
    for I := FCount - K to FCount - 1 do
      FItems[I] := nil;
    Dec(FCount, K);
    Dec(FTotalAllocated, K);
  finally
    FLock.Exit;
  end;
  // Outside the lock: a destructor must not run while the pool is locked.
  for I := 0 to High(Victims) do
    Victims[I].Free;
end;

function TDextPool<T>.Acquire(out AItem: T): Boolean;
var
  Popped: Boolean;
  CanAllocate: Boolean;
  WaitRes: TWaitResult;
  TimeoutMs: Integer;
  Deadline: UInt64;
  NowTick: UInt64;
  RemainingMs: Int64;
begin
  TrimIdle;

  TimeoutMs := FConfig.AcquireTimeoutMs;
  if TimeoutMs < 0 then
    TimeoutMs := 5000;

  Deadline := GetTickCount64 + UInt64(TimeoutMs);

  repeat
    if AtomicCmpExchange(FIsDisposing, 0, 0) <> 0 then
    begin
      AItem := nil;
      Result := False;
      Exit;
    end;

    FLock.Enter;
    try
      if AtomicCmpExchange(FIsDisposing, 0, 0) <> 0 then
      begin
        AItem := nil;
        Result := False;
        Exit;
      end;

      Popped := InternalPop(AItem);
      if Popped then
      begin
        // If items still remain or we can allocate more, keep event signaled for other waiters
        CanAllocate := (FConfig.MaxSize <= 0) or (FTotalAllocated < FConfig.MaxSize);
        if (FCount = 0) and (not CanAllocate) then
          FAvailableEvent.ResetEvent;
        Result := True;
        Exit;
      end;

      CanAllocate := (FConfig.MaxSize <= 0) or (FTotalAllocated < FConfig.MaxSize);
      if CanAllocate then
      begin
        AItem := CreateInstance;
        // Check if allocating pushed pool to max capacity and no items in pool
        CanAllocate := (FConfig.MaxSize <= 0) or (FTotalAllocated < FConfig.MaxSize);
        if (FCount = 0) and (not CanAllocate) then
          FAvailableEvent.ResetEvent;
        Result := True;
        Exit;
      end;

      if TimeoutMs = 0 then
      begin
        AItem := nil;
        Result := False;
        Exit;
      end;

      NowTick := GetTickCount64;
      if NowTick >= Deadline then
      begin
        AItem := nil;
        Result := False;
        Exit;
      end;
      RemainingMs := Int64(Deadline - NowTick);

      // Pool is exhausted, reset signal for this waiting phase and register waiter
      FAvailableEvent.ResetEvent;
      AtomicIncrement(FActiveWaiters);
    finally
      FLock.Exit;
    end;

    // Wait for an item to be released back or shutdown broadcast using calculated remaining timeout
    try
      WaitRes := FAvailableEvent.WaitFor(Cardinal(RemainingMs));
    finally
      AtomicDecrement(FActiveWaiters);
    end;

    if AtomicCmpExchange(FIsDisposing, 0, 0) <> 0 then
    begin
      AItem := nil;
      Result := False;
      Exit;
    end;

    if WaitRes <> wrSignaled then
    begin
      AItem := nil;
      Result := False;
      Exit;
    end;
    // Loop back to acquire item under FLock state protection
  until False;
end;

procedure TDextPool<T>.Release(AItem: T);
var
  Poolable: IPoolable;
  ShouldDestroy: Boolean;
begin
  if AItem = nil then
    Exit;

  // Sanitization / Recycling
  try
    if Assigned(FResetAction) then
      FResetAction(AItem);

    if Supports(AItem, IPoolable, Poolable) then
      Poolable.ResetState;
  except
    FLock.Enter;
    try
      Dec(FTotalAllocated);
    finally
      FLock.Exit;
    end;
    AItem.Free;
    FAvailableEvent.SetEvent;
    Exit;
  end;

  ShouldDestroy := False;
  FLock.Enter;
  try
    if (FConfig.MaxSize > 0) and (FCount >= FConfig.MaxSize) then
    begin
      ShouldDestroy := True;
      Dec(FTotalAllocated);
    end
    else
      InternalPush(AItem);
  finally
    FLock.Exit;
  end;

  FAvailableEvent.SetEvent;

  if ShouldDestroy then
    TObject(AItem).Free
  else
    TrimIdle;
end;

procedure TDextPool<T>.Use(const AProc: TProc<T>);
var
  Item: T;
begin
  if not Acquire(Item) then
    raise Exception.Create('Failed to acquire instance from object pool: Pool exhausted or timeout.');
  try
    AProc(Item);
  finally
    Release(Item);
  end;
end;

function TDextPool<T>.Use<TResult>(const AFunc: TFunc<T, TResult>): TResult;
var
  Item: T;
begin
  if not Acquire(Item) then
    raise Exception.Create('Failed to acquire instance from object pool: Pool exhausted or timeout.');
  try
    Result := AFunc(Item);
  finally
    Release(Item);
  end;
end;

{ TPooledObject<T> }

constructor TPooledObject<T>.Create(const APool: IDextPool<T>; AItem: T);
begin
  inherited Create;
  FPool := APool;
  FItem := AItem;
end;

destructor TPooledObject<T>.Destroy;
begin
  if (FPool <> nil) and (FItem <> nil) then
    FPool.Release(FItem);
  inherited Destroy;
end;

function TPooledObject<T>.GetItem: T;
begin
  Result := FItem;
end;

function TPooledObject<T>.HasItem: Boolean;
begin
  Result := FItem <> nil;
end;

function TDextPool<T>.AcquireScoped(out AScoped: IPooledObject<T>): Boolean;
var
  Item: T;
begin
  if Acquire(Item) then
  begin
    AScoped := TPooledObject<T>.Create(Self, Item);
    Result := True;
  end
  else
  begin
    AScoped := nil;
    Result := False;
  end;
end;

function TDextPool<T>.AcquireScoped: IPooledObject<T>;
var
  Scoped: IPooledObject<T>;
begin
  if not AcquireScoped(Scoped) then
    raise Exception.Create('Failed to acquire scoped instance from object pool: Pool exhausted or timeout.');
  Result := Scoped;
end;

function TDextPool<T>.GetCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCount;
  finally
    FLock.Exit;
  end;
end;

end.
