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
{  Created: 2026-02-24                                                      }
{                                                                           }
{  Non-generic hash map backend for Dext.Collections.                       }
{  Uses open addressing with linear probing and separated metadata.         }
{  Capacity is always a power of 2 for fast modulo via bitmask.             }
{                                                                           }
{  This unit has NO generic types - everything operates on                  }
{  Pointer + PTypeInfo + ElementSize.                                       }
{                                                                           }
{***************************************************************************}
unit Dext.Collections.RawDict;

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Collections.Memory;

type
  /// <summary>Callback for hashing a raw key to a 32-bit hash code</summary>
  TRawHashFunc = reference to function(Key: Pointer; KeySize: Integer): Cardinal;

  /// <summary>Callback for comparing two raw keys for equality</summary>
  TRawEqualFunc = reference to function(A, B: Pointer; KeySize: Integer): Boolean;

  /// <summary>
  ///   Non-generic hash map with open addressing and linear probing.
  ///   Keys and values are stored as contiguous raw memory.
  /// </summary>
  TRawDictionary = class
  public
    const
      SLOT_EMPTY     = 0;
      SLOT_OCCUPIED  = 1;
      SLOT_TOMBSTONE = 2;
      DEFAULT_CAPACITY = 4;
      MAX_LOAD_FACTOR = 75; // percent
  private
    FSlots: Pointer;         // Array of [Key|Value] pairs, contiguous
    FMetadata: PByte;        // Array of slot states (1 byte each)
    FCount: Integer;
    // Tombstones (removed slots) still consume probe positions, so they MUST be
    // taken into account by the load factor: only a rehash clears them. Without
    // this, a long-running Add/Remove cycle fills the table with tombstones
    // without ever growing, until no SLOT_EMPTY is left and FindSlot cannot
    // terminate.
    FTombstones: Integer;
    FCapacity: Integer;      // Always power of 2
    FKeySize: Integer;
    FValueSize: Integer;
    FSlotSize: Integer;      // KeySize + ValueSize
    FKeyTypeInfo: PTypeInfo;
    FValueTypeInfo: PTypeInfo;
    FKeyIsManaged: Boolean;
    FValueIsManaged: Boolean;
    FHashFunc: TRawHashFunc;
    FEqualFunc: TRawEqualFunc;
    function GetCount: Integer; inline;
    function GetCapacity: Integer; inline;
    function GetKeySize: Integer; inline;
    function GetValueSize: Integer; inline;

    function GetSlotPtr(Index: Integer): Pointer; inline;
    function GetKeyPtr(SlotPtr: Pointer): Pointer; inline;
    function GetValuePtr(SlotPtr: Pointer): Pointer; inline;
    function FindSlot(Key: Pointer; out SlotIndex: Integer): Boolean; overload; inline;
    /// <summary>FindSlot that also hands back the hash of Key, so that an
    ///   insertion can store its H2 byte without hashing the key again.</summary>
    function FindSlot(Key: Pointer; out SlotIndex: Integer; out Hash: Cardinal): Boolean; overload; inline;
    /// <summary>Finds the slot for a key that FindSlot reported absent,
    ///   growing the table first if the new entry would exceed the load
    ///   factor. Only a key that is really added can grow the table.</summary>
    function SlotForNewKey(Key: Pointer; SlotIndex: Integer): Integer;
    /// <summary>Writes a new entry in a free slot.</summary>
    procedure StoreNew(SlotIndex: Integer; Key, Value: Pointer; Hash: Cardinal);
    procedure Grow;
    procedure Rehash(NewCapacity: Integer);
    procedure FreeSlotContent(SlotPtr: Pointer);
  public
    constructor Create(AKeySize, AValueSize: Integer;
      AKeyTypeInfo, AValueTypeInfo: PTypeInfo;
      AHashFunc: TRawHashFunc; AEqualFunc: TRawEqualFunc;
      AInitialCapacity: Integer = 0);
    destructor Destroy; override;

    /// <summary>Adds or updates a key-value pair</summary>
    procedure AddOrSetRaw(Key, Value: Pointer);

    /// <summary>Adds a key-value pair. Raises exception if key already exists</summary>
    procedure AddRaw(Key, Value: Pointer);

    /// <summary>
    ///   Adds a key-value pair if the key is not there yet, with a single
    ///   lookup. Returns False, and changes nothing, if the key already exists.
    /// </summary>
    function TryAddRaw(Key, Value: Pointer): Boolean;

    /// <summary>Tries to get the value for a key. Returns pointer to value storage or nil</summary>
    function TryGetRaw(Key: Pointer; out ValuePtr: Pointer): Boolean; inline;

    /// <summary>Returns True if the key exists</summary>
    function ContainsKeyRaw(Key: Pointer): Boolean;

    /// <summary>Removes a key-value pair. Returns True if found and removed</summary>
    function RemoveRaw(Key: Pointer): Boolean;

    /// <summary>Removes all entries</summary>
    procedure Clear;

    /// <summary>
    ///   Iterates over all occupied slots. Callback receives key and value pointers.
    ///   Return True from callback to continue, False to stop.
    /// </summary>
    procedure ForEachRaw(Callback: TFunc<Pointer, Pointer, Boolean>);

    function IsSlotOccupied(Index: Integer): Boolean; inline;
    function GetKeyPtrAtIndex(Index: Integer): Pointer; inline;
    function GetValuePtrAtIndex(Index: Integer): Pointer; inline;

    property Count: Integer read GetCount;
    property Capacity: Integer read GetCapacity;
    property KeySize: Integer read GetKeySize;
    property ValueSize: Integer read GetValueSize;
  end;

/// <summary>Default hash function using BobJenkins one-at-a-time</summary>
function DefaultRawHash(Key: Pointer; KeySize: Integer): Cardinal;

/// <summary>Default equality by raw memory comparison</summary>
function DefaultRawEqual(A, B: Pointer; KeySize: Integer): Boolean;

/// <summary>Hash function optimized for string keys</summary>
function StringRawHash(Key: Pointer; KeySize: Integer): Cardinal;

/// <summary>Equality function for string keys</summary>
function StringRawEqual(A, B: Pointer; KeySize: Integer): Boolean;

/// <summary>Case-insensitive hash function optimized for string keys</summary>
function StringRawHashIgnoreCase(Key: Pointer; KeySize: Integer): Cardinal;
/// <summary>Case-insensitive equality function for string keys</summary>
function StringRawEqualIgnoreCase(A, B: Pointer; KeySize: Integer): Boolean;

/// <summary>Fast hash function for 4-byte keys</summary>
function FastHash4(Key: Pointer; KeySize: Integer): Cardinal;
/// <summary>Fast hash function for 8-byte keys</summary>
function FastHash8(Key: Pointer; KeySize: Integer): Cardinal;
/// <summary>Fast equality function for 4-byte keys</summary>
function FastEqual4(A, B: Pointer; KeySize: Integer): Boolean;
/// <summary>Fast equality function for 8-byte keys</summary>
function FastEqual8(A, B: Pointer; KeySize: Integer): Boolean;

implementation

const
  FNV_OFFSET_BASIS = 2166136261;
  FNV_PRIME = 16777619;

{ Hash Functions - overflow is intentional in hash algorithms }
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

function DefaultRawHash(Key: Pointer; KeySize: Integer): Cardinal;
var
  P: PByte;
  I: Integer;
begin
  // Bob Jenkins one-at-a-time hash
  Result := 0;
  P := PByte(Key);
  for I := 0 to KeySize - 1 do
  begin
    Result := Result + P^;
    Result := Result + (Result shl 10);
    Result := Result xor (Result shr 6);
    Inc(P);
  end;
  Result := Result + (Result shl 3);
  Result := Result xor (Result shr 11);
  Result := Result + (Result shl 15);
end;

function DefaultRawEqual(A, B: Pointer; KeySize: Integer): Boolean;
begin
  Result := CompareMem(A, B, KeySize);
end;

function StringRawHash(Key: Pointer; KeySize: Integer): Cardinal;
var
  S: string;
  I: Integer;
begin
  // Key points to a string variable (pointer to string data)
  S := PString(Key)^;
  if S = '' then
    Exit(0);

  // FNV-1a hash for strings
  Result := FNV_OFFSET_BASIS;
  for I := 1 to Length(S) do
  begin
    Result := Result xor Ord(S[I]);
    Result := Result * FNV_PRIME;
  end;
end;

function StringRawEqual(A, B: Pointer; KeySize: Integer): Boolean;
begin
  Result := PString(A)^ = PString(B)^;
end;

function StringRawHashIgnoreCase(Key: Pointer; KeySize: Integer): Cardinal;
var
  P: PChar;
  I, Len: Integer;
  C: Char;
begin
  // The same value as hashing UpperCase(S) (ASCII letters only, like
  // UpperCase and SameText), without building the upper-case copy: this runs
  // on every lookup of a case-insensitive dictionary (request and response
  // headers), and the copy was an allocation each time.
  Len := Length(PString(Key)^);
  if Len = 0 then
    Exit(0);
  P := PChar(PString(Key)^);
  Result := FNV_OFFSET_BASIS;
  for I := 0 to Len - 1 do
  begin
    C := P[I];
    if (C >= 'a') and (C <= 'z') then
      C := Char(Ord(C) - 32);
    Result := Result xor Ord(C);
    Result := Result * FNV_PRIME;
  end;
end;

function StringRawEqualIgnoreCase(A, B: Pointer; KeySize: Integer): Boolean;
begin
  Result := SameText(PString(A)^, PString(B)^);
end;

function FastHash4(Key: Pointer; KeySize: Integer): Cardinal;
begin
  Result := PCardinal(Key)^;
  // Simple rejuvenation for power-of-2 distributions
  Result := Result xor (Result shr 16);
end;

function FastHash8(Key: Pointer; KeySize: Integer): Cardinal;
var
  V: UInt64;
begin
  V := PUInt64(Key)^;
  Result := Cardinal(V) xor Cardinal(V shr 32);
end;

function FastEqual4(A, B: Pointer; KeySize: Integer): Boolean;
begin
  Result := PCardinal(A)^ = PCardinal(B)^;
end;

function FastEqual8(A, B: Pointer; KeySize: Integer): Boolean;
begin
  Result := PUInt64(A)^ = PUInt64(B)^;
end;

{$IFDEF DEBUG}
  {$OVERFLOWCHECKS ON}
  {$RANGECHECKS ON}
{$ENDIF}

{ TRawDictionary }

function TRawDictionary.GetCapacity: Integer;
begin
  Result := FCapacity;
end;

function TRawDictionary.GetCount: Integer;
begin
  Result := FCount;
end;

function TRawDictionary.GetKeySize: Integer;
begin
  Result := FKeySize;
end;

function TRawDictionary.GetValueSize: Integer;
begin
  Result := FValueSize;
end;

constructor TRawDictionary.Create(AKeySize, AValueSize: Integer;
  AKeyTypeInfo, AValueTypeInfo: PTypeInfo;
  AHashFunc: TRawHashFunc; AEqualFunc: TRawEqualFunc;
  AInitialCapacity: Integer = 0);
var
  Cap: Integer;
begin
  inherited Create;
  FKeySize := AKeySize;
  FValueSize := AValueSize;
  FSlotSize := AKeySize + AValueSize;
  FKeyTypeInfo := AKeyTypeInfo;
  FValueTypeInfo := AValueTypeInfo;
  FKeyIsManaged := IsManagedType(AKeyTypeInfo);
  FValueIsManaged := IsManagedType(AValueTypeInfo);
  if Assigned(AHashFunc) and Assigned(AEqualFunc) then
  begin
    FHashFunc := AHashFunc;
    FEqualFunc := AEqualFunc;
  end
  else if PTypeInfo(AKeyTypeInfo)^.Kind in [tkUString, tkLString, tkWString] then
  begin
    FHashFunc := StringRawHash;
    FEqualFunc := StringRawEqual;
  end
  else
  begin
    case AKeySize of
      4: begin FHashFunc := FastHash4; FEqualFunc := FastEqual4; end;
      8: begin FHashFunc := FastHash8; FEqualFunc := FastEqual8; end;
    else
      begin FHashFunc := DefaultRawHash; FEqualFunc := DefaultRawEqual; end;
    end;
  end;

  FCount := 0;

  // Round up to power of 2
  if AInitialCapacity <= 0 then
    Cap := DEFAULT_CAPACITY
  else
  begin
    Cap := DEFAULT_CAPACITY;
    while Cap < AInitialCapacity do
      Cap := Cap shl 1;
  end;

  FCapacity := Cap;
  FSlots := System.AllocMem(FCapacity * FSlotSize);
  FMetadata := System.AllocMem(FCapacity);
  FillChar(FMetadata^, FCapacity, SLOT_EMPTY);
end;

destructor TRawDictionary.Destroy;
begin
  Clear;
  System.FreeMem(FSlots);
  System.FreeMem(FMetadata);
  inherited;
end;

function TRawDictionary.GetSlotPtr(Index: Integer): Pointer;
begin
  Result := Pointer(NativeUInt(FSlots) + NativeUInt(Index * FSlotSize));
end;

function TRawDictionary.GetKeyPtr(SlotPtr: Pointer): Pointer;
begin
  Result := SlotPtr;
end;

function TRawDictionary.GetValuePtr(SlotPtr: Pointer): Pointer;
begin
  Result := Pointer(NativeUInt(SlotPtr) + NativeUInt(FKeySize));
end;

procedure TRawDictionary.FreeSlotContent(SlotPtr: Pointer);
begin
  if FKeyIsManaged then
    System.FinalizeArray(SlotPtr, FKeyTypeInfo, 1);
  if FValueIsManaged then
    System.FinalizeArray(Pointer(NativeUInt(SlotPtr) + NativeUInt(FKeySize)), FValueTypeInfo, 1);
  FillChar(SlotPtr^, FSlotSize, 0);
end;

function TRawDictionary.FindSlot(Key: Pointer; out SlotIndex: Integer; out Hash: Cardinal): Boolean;
var
  Mask: Integer;
  Idx: Integer;
  FirstTombstone: Integer;
  MetaPtr: PByte;
  Meta, H2: Byte;
  Probes: Integer;
begin
  Hash := FHashFunc(Key, FKeySize);
  H2 := Byte(Hash shr 24) or $80; // H2 Metadata: store high bits of hash
  Mask := FCapacity - 1;
  Idx := Integer(Hash and Cardinal(Mask));
  FirstTombstone := -1;
  Result := False;
  // Safety net: never probe more than the whole table. With the load factor
  // accounting for tombstones there is always a SLOT_EMPTY to stop at, so this
  // can only trigger if that invariant is ever broken again -- and returning
  // "not found" is infinitely better than spinning forever.
  Probes := 0;

  while Probes <= FCapacity do
  begin
    MetaPtr := FMetadata + Idx;
    Meta := MetaPtr^;

    if Meta = SLOT_EMPTY then
    begin
      if FirstTombstone >= 0 then SlotIndex := FirstTombstone
      else SlotIndex := Idx;
      Exit;
    end
    else if Meta = SLOT_TOMBSTONE then
    begin
      if FirstTombstone < 0 then
        FirstTombstone := Idx;
    end
    else if Meta >= $80 then // SLOT_OCCUPIED (H2 bit set)
    begin
      // H2 Metadata Optimization: Only run FEqualFunc if Hash fragments match
      if (FCapacity < 256) or (Meta = H2) then
      begin
        if FEqualFunc(Pointer(NativeUInt(FSlots) + NativeUInt(Idx * FSlotSize)), Key, FKeySize) then
        begin
          SlotIndex := Idx;
          Result := True;
          Exit;
        end;
      end;
    end;

    Idx := (Idx + 1) and Mask;
    Inc(Probes);
  end;

  // Table exhausted without finding the key: report a reusable tombstone if we
  // saw one, otherwise signal "no slot" with -1 (insertions check for it).
  if FirstTombstone >= 0 then
    SlotIndex := FirstTombstone
  else
    SlotIndex := -1;
end;

function TRawDictionary.FindSlot(Key: Pointer; out SlotIndex: Integer): Boolean;
var
  Hash: Cardinal;
begin
  Result := FindSlot(Key, SlotIndex, Hash);
end;

procedure TRawDictionary.Grow;
begin
  if FCapacity = 0 then
  begin
    Rehash(DEFAULT_CAPACITY);
    Exit;
  end;
  // The load factor now counts tombstones, so Grow can also be reached while the
  // number of LIVE entries is nowhere near the limit -- e.g. a steady add/remove
  // cycle, where every round leaves a tombstone behind. Doubling there would make
  // the table grow without bound for a constant working set: rehashing at the
  // SAME capacity is enough, since a rehash carries over occupied slots only and
  // drops every tombstone. Grow only when the live entries really need the room.
  if (FCount + 1) * 100 <= FCapacity * (MAX_LOAD_FACTOR div 2) then
    Rehash(FCapacity)
  else
    Rehash(FCapacity * 2);
end;

procedure TRawDictionary.Rehash(NewCapacity: Integer);
var
  OldSlots: Pointer;
  OldMetadata: PByte;
  OldCapacity: Integer;
  I: Integer;
  SlotPtr: Pointer;
  KeyPtr: Pointer;
  Hash: Cardinal;
  Mask: Integer;
  Idx: Integer;
  NewSlotPtr: Pointer;
  Meta: Byte;
begin
  OldSlots := FSlots;
  OldMetadata := FMetadata;
  OldCapacity := FCapacity;

  // Allocate new arrays
  FCapacity := NewCapacity;
  FSlots := System.AllocMem(FCapacity * FSlotSize);
  FMetadata := System.AllocMem(FCapacity);
  FillChar(FMetadata^, FCapacity, SLOT_EMPTY);
  FTombstones := 0; // only occupied entries are carried over below

  // Re-insert all occupied entries
  Mask := FCapacity - 1;
  for I := 0 to OldCapacity - 1 do
  begin
    Meta := PByte(NativeUInt(OldMetadata) + NativeUInt(I))^;
    if Meta >= $80 then
    begin
      SlotPtr := Pointer(NativeUInt(OldSlots) + NativeUInt(I * FSlotSize));
      KeyPtr := SlotPtr; 

      Hash := FHashFunc(KeyPtr, FKeySize);
      Idx := Integer(Hash and Cardinal(Mask));

      // Linear probe for empty slot
      while PByte(NativeUInt(FMetadata) + NativeUInt(Idx))^ <> SLOT_EMPTY do
        Idx := (Idx + 1) and Mask;

      // Move data (transfer ownership, no addref needed)
      NewSlotPtr := Pointer(NativeUInt(FSlots) + NativeUInt(Idx * FSlotSize));
      System.Move(SlotPtr^, NewSlotPtr^, FSlotSize);
      PByte(NativeUInt(FMetadata) + NativeUInt(Idx))^ := Byte(Hash shr 24) or $80;
    end
    else if Meta <> SLOT_EMPTY then
    begin
      // Tombstone - content already finalized on Remove, skip
    end;
  end;

  // Free old arrays (content was moved, not copied, so no finalization needed)
  System.FreeMem(OldSlots);
  System.FreeMem(OldMetadata);
end;

function TRawDictionary.SlotForNewKey(Key: Pointer; SlotIndex: Integer): Integer;
begin
  Result := SlotIndex;
  // Tombstones count towards the load: they occupy probe positions until the
  // next rehash, and ignoring them lets an Add/Remove cycle saturate the table.
  // The check comes after the lookup, so an existing key never grows the
  // table; after a rehash the slot found before is stale and is looked up
  // again (the rare path).
  if ((FCount + FTombstones + 1) * 100 > FCapacity * MAX_LOAD_FACTOR) or (Result < 0) then
  begin
    Grow;
    FindSlot(Key, Result);
  end;
  if Result < 0 then
    raise Exception.Create('TRawDictionary: no free slot available (internal invariant violated)');
end;

procedure TRawDictionary.StoreNew(SlotIndex: Integer; Key, Value: Pointer; Hash: Cardinal);
var
  SlotPtr: Pointer;
begin
  SlotPtr := GetSlotPtr(SlotIndex);

  if FKeyIsManaged then
    System.CopyArray(SlotPtr, Key, FKeyTypeInfo, 1)
  else
    System.Move(Key^, SlotPtr^, FKeySize);

  if FValueIsManaged then
    System.CopyArray(GetValuePtr(SlotPtr), Value, FValueTypeInfo, 1)
  else
    System.Move(Value^, GetValuePtr(SlotPtr)^, FValueSize);

  // H2 from the hash FindSlot already computed
  PByte(NativeUInt(FMetadata) + NativeUInt(SlotIndex))^ := Byte(Hash shr 24) or $80;
  Inc(FCount);
end;

procedure TRawDictionary.AddOrSetRaw(Key, Value: Pointer);
var
  SlotIndex: Integer;
  SlotPtr: Pointer;
  Hash: Cardinal;
begin
  if FindSlot(Key, SlotIndex, Hash) then
  begin
    // Update existing value
    SlotPtr := GetSlotPtr(SlotIndex);
    if FValueIsManaged then
    begin
      System.FinalizeArray(GetValuePtr(SlotPtr), FValueTypeInfo, 1);
      System.CopyArray(GetValuePtr(SlotPtr), Value, FValueTypeInfo, 1);
    end
    else
      System.Move(Value^, GetValuePtr(SlotPtr)^, FValueSize);
  end
  else
    StoreNew(SlotForNewKey(Key, SlotIndex), Key, Value, Hash);
end;

procedure TRawDictionary.AddRaw(Key, Value: Pointer);
begin
  if not TryAddRaw(Key, Value) then
    raise Exception.Create('An item with the same key has already been added.');
end;

function TRawDictionary.TryAddRaw(Key, Value: Pointer): Boolean;
var
  SlotIndex: Integer;
  Hash: Cardinal;
begin
  // One lookup: it says whether the key exists, where a new one goes, and
  // gives the hash for the H2 byte.
  if FindSlot(Key, SlotIndex, Hash) then
    Exit(False);
  StoreNew(SlotForNewKey(Key, SlotIndex), Key, Value, Hash);
  Result := True;
end;

function TRawDictionary.TryGetRaw(Key: Pointer; out ValuePtr: Pointer): Boolean;
var
  SlotIndex: Integer;
begin
  Result := FindSlot(Key, SlotIndex);
  if Result then
    ValuePtr := GetValuePtr(GetSlotPtr(SlotIndex))
  else
    ValuePtr := nil;
end;

function TRawDictionary.ContainsKeyRaw(Key: Pointer): Boolean;
var
  SlotIndex: Integer;
begin
  Result := FindSlot(Key, SlotIndex);
end;

function TRawDictionary.RemoveRaw(Key: Pointer): Boolean;
var
  SlotIndex: Integer;
  SlotPtr: Pointer;
begin
  Result := FindSlot(Key, SlotIndex);
  if not Result then
    Exit;

  SlotPtr := GetSlotPtr(SlotIndex);
  FreeSlotContent(SlotPtr);
  PByte(NativeUInt(FMetadata) + NativeUInt(SlotIndex))^ := SLOT_TOMBSTONE;
  Dec(FCount);
  Inc(FTombstones); // cleared only by Rehash/Clear -- see the field's comment
end;

procedure TRawDictionary.Clear;
var
  I: Integer;
  SlotPtr: Pointer;
  Meta: Byte;
begin
  if (FKeyIsManaged or FValueIsManaged) and (FCount > 0) then
  begin
    for I := 0 to FCapacity - 1 do
    begin
      Meta := PByte(NativeUInt(FMetadata) + NativeUInt(I))^;
      if Meta >= $80 then
      begin
        SlotPtr := GetSlotPtr(I);
        FreeSlotContent(SlotPtr);
      end;
    end;
  end;

  if FCapacity > 0 then
  begin
    FillChar(FSlots^, FCapacity * FSlotSize, 0);
    FillChar(FMetadata^, FCapacity, SLOT_EMPTY);
  end;
  FCount := 0;
  FTombstones := 0; // every slot is SLOT_EMPTY again
end;

procedure TRawDictionary.ForEachRaw(Callback: TFunc<Pointer, Pointer, Boolean>);
var
  I: Integer;
  Meta: Byte;
  SlotPtr: Pointer;
begin
  for I := 0 to FCapacity - 1 do
  begin
    Meta := PByte(NativeUInt(FMetadata) + NativeUInt(I))^;
    if Meta >= $80 then
    begin
      SlotPtr := GetSlotPtr(I);
      if not Callback(GetKeyPtr(SlotPtr), GetValuePtr(SlotPtr)) then
        Exit;
    end;
  end;
end;

function TRawDictionary.IsSlotOccupied(Index: Integer): Boolean;
begin
  Result := PByte(NativeUInt(FMetadata) + NativeUInt(Index))^ >= $80;
end;

function TRawDictionary.GetKeyPtrAtIndex(Index: Integer): Pointer;
begin
  Result := GetKeyPtr(GetSlotPtr(Index));
end;

function TRawDictionary.GetValuePtrAtIndex(Index: Integer): Pointer;
begin
  Result := GetValuePtr(GetSlotPtr(Index));
end;

end.
