unit Dext.Collections.Vector;

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Core.Span,
  Dext.Collections.Memory,
  Dext.Collections.Comparers;

const
  SVO_BUFFER_SIZE = 64; // Bytes reservados na Stack

type
  /// <summary>
  ///   A high-performance, stack-allocated vector with Small Vector Optimization (SVO).
  ///   Stores elements in a fixed stack buffer until capacity is exceeded, then transitions to heap allocation.
  /// </summary>
  TVector<T> = record
  private
    FCount: NativeInt;
    FCapacity: NativeInt;     // Negative = SVO mode (on stack buffer). Positive = Heap allocated
    FBuffer: array[0..SVO_BUFFER_SIZE - 1] of Byte; // SVO inline
    FHeapData: Pointer;       // Heap Data (when SVO is outgrown)
    FVersion: Integer;        // For Span invalidation
    
    
    procedure InternalSort(L, R: NativeInt; const AComparer: IComparer<T>);
    
    function GetDataPtr: Pointer; inline;
    function GetItemPtr(Index: NativeInt): Pointer; inline;
    function GetCapacity: NativeInt; inline;
    procedure SetCapacity(NewCapacity: NativeInt);
    
    function GetItem(Index: NativeInt): T;
    procedure SetItem(Index: NativeInt; const Value: T);
    
    procedure Grow;
  public
    // Auto-Initialization & Finalization hooks (Public to avoid Unused hints)
    class operator Initialize(out Dest: TVector<T>);
    class operator Finalize(var Dest: TVector<T>);
    class operator Assign(var Dest: TVector<T>; const [ref] Src: TVector<T>);

    /// <summary>Adds an item to the vector. Grows to heap if stack buffer is full.</summary>
    procedure Add(const Value: T); inline;
    /// <summary>Alias for Add.</summary>
    procedure Push(const Value: T); inline; 
    /// <summary>Removes the last item and decrements count.</summary>
    procedure Pop;
    /// <summary>Removes all items. Does not deallocate heap memory immediately.</summary>
    procedure Clear;
    
    /// <summary>Finds the index of a value using the default equality comparer.</summary>
    function IndexOf(const Value: T): NativeInt;
    /// <summary>Removes the first occurrence of a value.</summary>
    procedure Remove(const Value: T);
    /// <summary>Removes the item at the specified index and shifts subsequent items.</summary>
    procedure RemoveAt(Index: NativeInt);
    
    // Sub-segmentation
    /// <summary>Exposes the vector's memory as a mutable Span.</summary>
    function AsSpan: TSpan<T>;
    /// <summary>Exposes the vector's memory as a Read-Only Span.</summary>
    function AsReadOnlySpan: TReadOnlySpan<T>;
    /// <summary>Copies elements to a new or existing array.</summary>
    procedure ToArray(out DestArray: TArray<T>); overload;
    /// <summary>Returns a new array containing the vector's elements.</summary>
    function ToArray: TArray<T>; overload;
    
    // Iteration
    /// <summary>Enables 'for..in' iteration using Spans.</summary>
    function GetEnumerator: TSpanEnumerator<T>; inline;
    
    /// <summary>Sorts the vector elements using the provided comparer.</summary>
    procedure Sort(const AComparer: IComparer<T>);
    
    property Items[Index: NativeInt]: T read GetItem write SetItem; default;
    property Count: NativeInt read FCount;
    property Capacity: NativeInt read GetCapacity write SetCapacity;
    property Data: Pointer read GetDataPtr;
  end;

implementation

{ TVector<T> }

class operator TVector<T>.Initialize(out Dest: TVector<T>);
begin
  Dest.FCount := 0;
  // Initialize with SVO enabled (Negative capacity marks Stack usage)
  Dest.FCapacity := -(SVO_BUFFER_SIZE div SizeOf(T));
  Dest.FHeapData := nil;
  Dest.FVersion := 0;
  FillChar(Dest.FBuffer, SVO_BUFFER_SIZE, 0);
end;

class operator TVector<T>.Finalize(var Dest: TVector<T>);
begin
  if Dest.FCount > 0 then
    RawFinalize(Dest.GetDataPtr, Dest.FCount, SizeOf(T), System.TypeInfo(T));
    
  if Dest.FCapacity > 0 then // On the heap
    FreeMem(Dest.FHeapData);
    
  Dest.FHeapData := nil;
  Dest.FCapacity := 0;
  Dest.FCount := 0;
  Inc(Dest.FVersion);
end;

class operator TVector<T>.Assign(var Dest: TVector<T>; const [ref] Src: TVector<T>);
begin
  if @Dest = @Src then Exit;
  
  // Clear any existing allocation
  Dest.Clear;
  
  if Src.FCount = 0 then Exit;
  
  // Duplicate Heap or Stack
  if Src.FCapacity > 0 then
  begin
    Dest.FCapacity := Src.FCapacity;
    GetMem(Dest.FHeapData, Dest.FCapacity * SizeOf(T));
    FillChar(Dest.FHeapData^, Dest.FCapacity * SizeOf(T), 0);
    RawCopy(Dest.FHeapData, Src.FHeapData, Src.FCount, SizeOf(T), System.TypeInfo(T));
  end
  else
  begin
    Dest.FCapacity := Src.FCapacity;
    RawCopy(@Dest.FBuffer[0], @Src.FBuffer[0], Src.FCount, SizeOf(T), System.TypeInfo(T));
  end;
  
  Dest.FCount := Src.FCount;
  Inc(Dest.FVersion);
end;

function TVector<T>.GetDataPtr: Pointer;
begin
  if FCapacity < 0 then
    Result := @FBuffer[0]
  else
    Result := FHeapData;
end;

function TVector<T>.GetItemPtr(Index: NativeInt): Pointer;
begin
  Result := PByte(GetDataPtr) + (Index * SizeOf(T));
end;

function TVector<T>.GetCapacity: NativeInt;
begin
  Result := Abs(FCapacity);
end;

procedure TVector<T>.SetCapacity(NewCapacity: NativeInt);
var
  NewHeapData: Pointer;
begin
  if NewCapacity <= Abs(FCapacity) then Exit; // Prevent shrinking for now
  
  GetMem(NewHeapData, NewCapacity * SizeOf(T));
  FillChar(NewHeapData^, NewCapacity * SizeOf(T), 0);
  
  if FCount > 0 then
  begin
    // Safely shift current buffer items and transfer ownership to the rest of the heap
    if FCapacity < 0 then
      RawMove(NewHeapData, @FBuffer[0], FCount, SizeOf(T), System.TypeInfo(T))
    else
      RawMove(NewHeapData, FHeapData, FCount, SizeOf(T), System.TypeInfo(T));
  end;
  
  if FCapacity > 0 then
    FreeMem(FHeapData);
    
  FHeapData := NewHeapData;
  FCapacity := NewCapacity; // Positive signals moving to the heap
  Inc(FVersion);
end;

procedure TVector<T>.Grow;
var
  NewCapacity: NativeInt;
begin
  if FCapacity < 0 then
    NewCapacity := Abs(FCapacity) * 2 // Jump from SVO buffer size
  else
    NewCapacity := FCapacity * 2;
    
  if NewCapacity < 4 then NewCapacity := 4; // Absolute minimum (if SVO is terribly small)
    
  SetCapacity(NewCapacity);
end;

procedure TVector<T>.Add(const Value: T);
begin
  if FCount >= Abs(FCapacity) then
    Grow;
    
  // Simple copy operation using helpers
  RawCopyElement(GetItemPtr(FCount), @Value, SizeOf(T), System.TypeInfo(T));
  Inc(FCount);
  Inc(FVersion);
end;

procedure TVector<T>.Push(const Value: T);
begin
  Add(Value);
end;

procedure TVector<T>.Pop;
begin
  if FCount > 0 then
  begin
    RawFinalizeElement(GetItemPtr(FCount - 1), SizeOf(T), System.TypeInfo(T));
    Dec(FCount);
    Inc(FVersion);
  end;
end;

procedure TVector<T>.Clear;
begin
  if FCount > 0 then
  begin
    RawFinalize(GetDataPtr, FCount, SizeOf(T), System.TypeInfo(T));
    FCount := 0;
    Inc(FVersion);
  end;
end;

function TVector<T>.IndexOf(const Value: T): NativeInt;
var
  I: NativeInt;
  Comparer: Dext.Collections.Comparers.IEqualityComparer<T>;
begin
  Comparer := Dext.Collections.Comparers.TEqualityComparer<T>.Default;
  for I := 0 to FCount - 1 do
    if Comparer.Equals(GetItem(I), Value) then
      Exit(I);
  Result := -1;
end;

procedure TVector<T>.RemoveAt(Index: NativeInt);
var
  TargetPtr, NextPtr: Pointer;
begin
  if (Index < 0) or (Index >= FCount) then Exit;
  
  TargetPtr := GetItemPtr(Index);
  RawFinalizeElement(TargetPtr, SizeOf(T), System.TypeInfo(T));
  
  if Index < FCount - 1 then
  begin
    // The target slot is already finalized; shift the tail down by one slot
    // (ownership of managed values moves with the bytes) and clear the
    // vacated last slot so nothing is finalized twice.
    NextPtr := GetItemPtr(Index + 1);
    System.Move(NextPtr^, TargetPtr^, (FCount - 1 - Index) * SizeOf(T));
    FillChar(GetItemPtr(FCount - 1)^, SizeOf(T), 0);
  end;
  
  Dec(FCount);
  Inc(FVersion);
end;

procedure TVector<T>.Remove(const Value: T);
var
  Idx: NativeInt;
begin
  Idx := IndexOf(Value);
  if Idx >= 0 then
    RemoveAt(Idx);
end;

function TVector<T>.GetItem(Index: NativeInt): T;
begin
  {$IFDEF DEBUG}
  if (Index < 0) or (Index >= FCount) then
    raise Exception.CreateFmt('TVector index out of bounds: %d (Count: %d)', [Index, FCount]);
  {$ENDIF}
  RawCopyElement(@Result, PByte(GetDataPtr) + (Index * SizeOf(T)), SizeOf(T), System.TypeInfo(T));
end;

procedure TVector<T>.SetItem(Index: NativeInt; const Value: T);
var
  TargetPtr: Pointer;
begin
  {$IFDEF DEBUG}
  if (Index < 0) or (Index >= FCount) then
    raise Exception.CreateFmt('TVector index out of bounds: %d (Count: %d)', [Index, FCount]);
  {$ENDIF}
  TargetPtr := GetItemPtr(Index);
  RawFinalizeElement(TargetPtr, SizeOf(T), System.TypeInfo(T)); // Drops existing obj safely
  RawCopyElement(TargetPtr, @Value, SizeOf(T), System.TypeInfo(T)); // Embeds new
  Inc(FVersion);
end;

function TVector<T>.AsSpan: TSpan<T>;
begin
  Result := TSpan<T>.Create(GetDataPtr, FCount);
end;

function TVector<T>.AsReadOnlySpan: TReadOnlySpan<T>;
begin
  Result := TReadOnlySpan<T>.Create(GetDataPtr, FCount);
end;

procedure TVector<T>.ToArray(out DestArray: TArray<T>);
begin
  SetLength(DestArray, FCount);
  if FCount > 0 then
    RawCopy(@DestArray[0], GetDataPtr, FCount, SizeOf(T), System.TypeInfo(T));
end;

function TVector<T>.ToArray: TArray<T>;
begin
  ToArray(Result);
end;

procedure TVector<T>.InternalSort(L, R: NativeInt; const AComparer: IComparer<T>);
var
  I, J: NativeInt;
  Pivot, Temp: T;
begin
  I := L;
  J := R;
  Pivot := GetItem(L + (R - L) div 2);
  repeat
    while AComparer.Compare(GetItem(I), Pivot) < 0 do Inc(I);
    while AComparer.Compare(GetItem(J), Pivot) > 0 do Dec(J);
    if I <= J then
    begin
      if I <> J then
      begin
        Temp := GetItem(I);
        SetItem(I, GetItem(J));
        SetItem(J, Temp);
      end;
      Inc(I);
      Dec(J);
    end;
  until I > J;
  if L < J then InternalSort(L, J, AComparer);
  if I < R then InternalSort(I, R, AComparer);
end;

procedure TVector<T>.Sort(const AComparer: IComparer<T>);
begin
  if FCount > 1 then
    InternalSort(0, FCount - 1, AComparer);
end;

function TVector<T>.GetEnumerator: TSpanEnumerator<T>;
begin
  Result := AsSpan.GetEnumerator;
end;

end.
