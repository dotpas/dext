unit Dext.Collections.Concurrent;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Dext.Collections.Comparers,
  Dext.Collections.Dict;

type
  /// <summary>Interface for thread-safe dictionaries optimized for high concurrency.</summary>
  IDextConcurrentDictionary<K, V> = interface
    /// <summary>
    ///   Gets the value if it exists or creates it with ValueFactory. The factory
    ///   runs outside any lock, so under contention it can run in several threads
    ///   for the same key; exactly one result is stored and every caller receives
    ///   that stored value. Each caller runs the factory at most once.
    /// </summary>
    function GetOrAdd(const Key: K; const ValueFactory: TFunc<K, V>): V;
    /// <summary>Attempts to add a key-value pair. Returns False if the key already exists.</summary>
    function TryAdd(const Key: K; const Value: V): Boolean;
    /// <summary>Attempts to safely get the value associated with a key.</summary>
    function TryGetValue(const Key: K; out Value: V): Boolean;
    /// <summary>Attempts to remove a key and returns its value.</summary>
    function TryRemove(const Key: K; out Value: V): Boolean;
    /// <summary>Compares the current value with ComparisonValue and, if equal, updates it to NewValue (Atomic CAS).</summary>
    function TryUpdate(const Key: K; const NewValue, ComparisonValue: V): Boolean;
    /// <summary>Clears all items from all lock stripes.</summary>
    procedure Clear;
    function GetCount: Integer;
    property Count: Integer read GetCount;
  end;

  /// <summary>
  ///   High-performance concurrent dictionary using Lock Striping technique.
  ///   Divides storage into multiple stripes, each with its own SpinLock,
  ///   allowing multiple write operations to occur simultaneously in different stripes.
  /// </summary>
  TConcurrentDictionary<K, V> = class(TInterfacedObject, IDextConcurrentDictionary<K, V>)
  private
    const DEFAULT_CONCURRENCY_LEVEL = 32;
  type
    TStripe = record
      Lock: TSpinLock;
      Items: IDictionary<K, V>;
    end;
  private
    FStripes: TArray<TStripe>;
    FConcurrencyLevel: Integer;
    FComparer: IEqualityComparer<K>;
    function GetStripeIndex(const Key: K): Integer; inline;
  public
    /// <summary>Creates the concurrent dictionary with the specified parallelism level.</summary>
    constructor Create(ConcurrencyLevel: Integer = DEFAULT_CONCURRENCY_LEVEL);
    
    function GetOrAdd(const Key: K; const ValueFactory: TFunc<K, V>): V;
    function TryAdd(const Key: K; const Value: V): Boolean;
    function TryGetValue(const Key: K; out Value: V): Boolean;
    function TryRemove(const Key: K; out Value: V): Boolean;
    function TryUpdate(const Key: K; const NewValue, ComparisonValue: V): Boolean;
    procedure Clear;
    function GetCount: Integer;
    /// <summary>Returns the total sum of items across all lock stripes.</summary>
    property Count: Integer read GetCount;
  end;

implementation

{ TConcurrentDictionary<K, V> }

constructor TConcurrentDictionary<K, V>.Create(ConcurrencyLevel: Integer);
var
  I: Integer;
begin
  inherited Create;
  if ConcurrencyLevel < 1 then
    ConcurrencyLevel := DEFAULT_CONCURRENCY_LEVEL;
  FConcurrencyLevel := ConcurrencyLevel;
  FComparer := TEqualityComparer<K>.Default;
  
  SetLength(FStripes, FConcurrencyLevel);
  for I := 0 to FConcurrencyLevel - 1 do
  begin
    FStripes[I].Lock := TSpinLock.Create(False);
    FStripes[I].Items := TDictionary<K, V>.Create;
  end;
end;

function TConcurrentDictionary<K, V>.GetStripeIndex(const Key: K): Integer;
var
  HashCode: Integer;
begin
  HashCode := FComparer.GetHashCode(Key);
  // Unsigned arithmetic: Abs(Low(Integer)) would stay negative.
  Result := Integer(Cardinal(HashCode) mod Cardinal(FConcurrencyLevel));
end;

function TConcurrentDictionary<K, V>.GetCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FConcurrencyLevel - 1 do
  begin
    FStripes[I].Lock.Enter;
    try
      Inc(Result, FStripes[I].Items.Count);
    finally
      FStripes[I].Lock.Exit;
    end;
  end;
end;

procedure TConcurrentDictionary<K, V>.Clear;
var
  I: Integer;
begin
  for I := 0 to FConcurrencyLevel - 1 do
  begin
    FStripes[I].Lock.Enter;
    try
      // The current TDictionary does not have a Clear method in its interface yet.
      // We can just re-create it or drop items by iterating (re-creating is safer/faster for now)
      FStripes[I].Items := TDictionary<K, V>.Create;
    finally
      FStripes[I].Lock.Exit;
    end;
  end;
end;

function TConcurrentDictionary<K, V>.GetOrAdd(const Key: K; const ValueFactory: TFunc<K, V>): V;
var
  StripeIdx: Integer;
  Created, Existing: V;
begin
  StripeIdx := GetStripeIndex(Key);
  
  // Fast read
  FStripes[StripeIdx].Lock.Enter;
  try
    if FStripes[StripeIdx].Items.TryGetValue(Key, Result) then
      Exit;
  finally
    FStripes[StripeIdx].Lock.Exit;
  end;
  
  // The factory runs outside the lock: it may be slow, may call back into
  // this dictionary, and must never be able to hold a spin lock hostage.
  Created := ValueFactory(Key);
  
  FStripes[StripeIdx].Lock.Enter;
  try
    // Another thread may have won the race: its value is the one that counts.
    if FStripes[StripeIdx].Items.TryGetValue(Key, Existing) then
      Result := Existing
    else
    begin
      FStripes[StripeIdx].Items.AddOrSetValue(Key, Created);
      Result := Created;
    end;
  finally
    FStripes[StripeIdx].Lock.Exit;
  end;
end;

function TConcurrentDictionary<K, V>.TryAdd(const Key: K; const Value: V): Boolean;
var
  StripeIdx: Integer;
  Existing: V;
begin
  StripeIdx := GetStripeIndex(Key);
  FStripes[StripeIdx].Lock.Enter;
  try
    if FStripes[StripeIdx].Items.TryGetValue(Key, Existing) then
      Result := False
    else
    begin
      FStripes[StripeIdx].Items.AddOrSetValue(Key, Value);
      Result := True;
    end;
  finally
    FStripes[StripeIdx].Lock.Exit;
  end;
end;

function TConcurrentDictionary<K, V>.TryGetValue(const Key: K; out Value: V): Boolean;
var
  StripeIdx: Integer;
begin
  StripeIdx := GetStripeIndex(Key);
  FStripes[StripeIdx].Lock.Enter;
  try
    Result := FStripes[StripeIdx].Items.TryGetValue(Key, Value);
  finally
    FStripes[StripeIdx].Lock.Exit;
  end;
end;

function TConcurrentDictionary<K, V>.TryRemove(const Key: K; out Value: V): Boolean;
var
  StripeIdx: Integer;
begin
  StripeIdx := GetStripeIndex(Key);
  FStripes[StripeIdx].Lock.Enter;
  try
    if FStripes[StripeIdx].Items.TryGetValue(Key, Value) then
    begin
      Result := FStripes[StripeIdx].Items.Remove(Key);
    end
    else
      Result := False;
  finally
    FStripes[StripeIdx].Lock.Exit;
  end;
end;

function TConcurrentDictionary<K, V>.TryUpdate(const Key: K; const NewValue, ComparisonValue: V): Boolean;
var
  StripeIdx: Integer;
  CurrentValue: V;
  ValComparer: IEqualityComparer<V>;
begin
  StripeIdx := GetStripeIndex(Key);
  ValComparer := TEqualityComparer<V>.Default;
  
  FStripes[StripeIdx].Lock.Enter;
  try
    if FStripes[StripeIdx].Items.TryGetValue(Key, CurrentValue) then
    begin
      if ValComparer.Equals(CurrentValue, ComparisonValue) then
      begin
        FStripes[StripeIdx].Items.AddOrSetValue(Key, NewValue);
        Result := True;
      end
      else
        Result := False;
    end
    else
      Result := False;
  finally
    FStripes[StripeIdx].Lock.Exit;
  end;
end;

end.
