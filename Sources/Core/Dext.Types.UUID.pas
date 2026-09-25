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
{  Created: 2025-12-20                                                      }
{                                                                           }
{  Purpose: RFC 9562 compliant UUID type with proper Big-Endian storage    }
{           and automatic conversion to/from Delphi's TGUID.                }
{                                                                           }
{***************************************************************************}
unit Dext.Types.UUID;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.Math;

type
  /// <summary>
  ///   RFC 9562 compliant UUID stored in Big-Endian format (Network Byte Order).
  ///   Compatible with PostgreSQL uuid type and web APIs.
  ///   Automatically converts to/from Delphi's TGUID via implicit operators.
  /// </summary>
  TUUID = record
  private
    FBytes: array[0..15] of Byte; // Big-Endian storage
    
    class function SwapEndianness(const G: TGUID): TGUID; static;
    class function GUIDToBytes(const G: TGUID): TArray<Byte>; static;
  public
    class function BytesToGUID(const Bytes: array of Byte): TGUID; static;

    /// <summary>Generates a new UUID v4 (random).</summary>
    class function NewV4: TUUID; static;
    
    /// <summary>Generates a new UUID v7 (time-ordered, recommended for databases).</summary>
    class function NewV7: TUUID; static;
    
    /// <summary>Creates UUID from string (with or without braces/hyphens).</summary>
    class function FromString(const S: string): TUUID; static;
    
    /// <summary>Creates UUID from TGUID (handles endianness conversion).</summary>
    class function FromGUID(const G: TGUID): TUUID; static;
    
    /// <summary>Returns canonical string representation (lowercase, no braces).</summary>
    function ToString: string;
    
    /// <summary>Returns string with braces (Delphi format).</summary>
    function ToStringWithBraces: string;
    
    /// <summary>Converts to Delphi TGUID (handles endianness conversion).</summary>
    function ToGUID: TGUID;
    
    /// <summary>Returns raw bytes in Big-Endian format.</summary>
    function ToBytes: TArray<Byte>;
    
    /// <summary>Checks if UUID is null (all zeros).</summary>
    function IsNull: Boolean;
    
    /// <summary>Alias for IsNull - checks if UUID is empty (all zeros).</summary>
    function IsEmpty: Boolean; inline;
    
    /// <summary>Returns a null UUID (all zeros).</summary>
    class function Null: TUUID; static;
    
    /// <summary>Alias for Null - returns an empty UUID (all zeros).</summary>
    class function Empty: TUUID; static; inline;
    
    // Implicit conversions for seamless usage
    class operator Implicit(const S: string): TUUID;
    class operator Implicit(const U: TUUID): string;
    class operator Implicit(const G: TGUID): TUUID;
    class operator Implicit(const U: TUUID): TGUID;
    
    // Comparison operators
    class operator Equal(const A, B: TUUID): Boolean;
    class operator NotEqual(const A, B: TUUID): Boolean;
  end;

implementation

{ TUUID }

class function TUUID.SwapEndianness(const G: TGUID): TGUID;
begin
  Result := G;
  // Swap D1 (4 bytes)
  Result.D1 := ((Result.D1 and $000000FF) shl 24) or
               ((Result.D1 and $0000FF00) shl 8) or
               ((Result.D1 and $00FF0000) shr 8) or
               ((Result.D1 and $FF000000) shr 24);
  // Swap D2 (2 bytes)
  Result.D2 := Swap(Result.D2);
  // Swap D3 (2 bytes)
  Result.D3 := Swap(Result.D3);
  // D4 stays the same (already Big-Endian)
end;

class function TUUID.BytesToGUID(const Bytes: array of Byte): TGUID;
begin
  if Length(Bytes) <> 16 then
    raise Exception.Create('Invalid byte array length for UUID');
  Move(Bytes[0], Result, 16);
end;

class function TUUID.GUIDToBytes(const G: TGUID): TArray<Byte>;
begin
  SetLength(Result, 16);
  Move(G, Result[0], 16);
end;

class function TUUID.NewV4: TUUID;
var
  G: TGUID;
begin
  CreateGUID(G);
  Result := FromGUID(G);
end;

class function TUUID.NewV7: TUUID;
var
  UnixTimeMs: Int64;
  RandomBits: array[0..9] of Byte;
  I: Integer;
begin
  // 1. Get Unix timestamp in milliseconds (UTC)
  UnixTimeMs := DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Now), False) * 1000 + MillisecondOf(Now);

  // 2. Generate random bytes for the rest
  Randomize;
  for I := 0 to 9 do
    RandomBits[I] := Random(256);

  // 3. Fill timestamp (48 bits, Big-Endian)
  Result.FBytes[0] := (UnixTimeMs shr 40) and $FF;
  Result.FBytes[1] := (UnixTimeMs shr 32) and $FF;
  Result.FBytes[2] := (UnixTimeMs shr 24) and $FF;
  Result.FBytes[3] := (UnixTimeMs shr 16) and $FF;
  Result.FBytes[4] := (UnixTimeMs shr 8) and $FF;
  Result.FBytes[5] := UnixTimeMs and $FF;

  // 4. Fill random part
  Result.FBytes[6] := RandomBits[0];
  Result.FBytes[7] := RandomBits[1];
  Result.FBytes[8] := RandomBits[2];
  Result.FBytes[9] := RandomBits[3];
  Result.FBytes[10] := RandomBits[4];
  Result.FBytes[11] := RandomBits[5];
  Result.FBytes[12] := RandomBits[6];
  Result.FBytes[13] := RandomBits[7];
  Result.FBytes[14] := RandomBits[8];
  Result.FBytes[15] := RandomBits[9];

  // 5. Set version (7) in byte 6, bits 4-7
  Result.FBytes[6] := (Result.FBytes[6] and $0F) or $70;

  // 6. Set variant (10xx) in byte 8, bits 6-7
  Result.FBytes[8] := (Result.FBytes[8] and $3F) or $80;
end;

class function TUUID.FromString(const S: string): TUUID;
var
  CleanStr: string;
  I: Integer;
begin
  CleanStr := S.Trim;
  if CleanStr = '' then
    Exit(TUUID.Empty);

  // Remove braces if present
  if CleanStr.StartsWith('{') and CleanStr.EndsWith('}') then
    CleanStr := CleanStr.Substring(1, CleanStr.Length - 2);
  
  // Remove hyphens for parsing
  CleanStr := CleanStr.Replace('-', '', [rfReplaceAll]);
  
  if CleanStr.Length <> 32 then
    raise Exception.CreateFmt('Invalid UUID string: %s', [S]);
  
  // Parse hex string to bytes (Big-Endian)
  for I := 0 to 15 do
    Result.FBytes[I] := StrToInt('$' + CleanStr.Substring(I * 2, 2));
end;

class function TUUID.FromGUID(const G: TGUID): TUUID;
var
  Swapped: TGUID;
  Bytes: TArray<Byte>;
begin
  // Swap endianness to convert from Delphi's Little-Endian to Big-Endian
  Swapped := SwapEndianness(G);
  Bytes := GUIDToBytes(Swapped);
  Move(Bytes[0], Result.FBytes[0], 16);
end;

function TUUID.ToString: string;
begin
  Result := Format('%2.2x%2.2x%2.2x%2.2x-%2.2x%2.2x-%2.2x%2.2x-%2.2x%2.2x-%2.2x%2.2x%2.2x%2.2x%2.2x%2.2x',
    [FBytes[0], FBytes[1], FBytes[2], FBytes[3],
     FBytes[4], FBytes[5],
     FBytes[6], FBytes[7],
     FBytes[8], FBytes[9],
     FBytes[10], FBytes[11], FBytes[12], FBytes[13], FBytes[14], FBytes[15]]).ToLower;
end;

function TUUID.ToStringWithBraces: string;
begin
  Result := '{' + ToString + '}';
end;

function TUUID.ToGUID: TGUID;
var
  BigEndianGUID: TGUID;
begin
  // Create GUID from Big-Endian bytes
  Move(FBytes[0], BigEndianGUID, 16);
  
  // Swap to Little-Endian for Delphi
  Result := SwapEndianness(BigEndianGUID);
end;

function TUUID.ToBytes: TArray<Byte>;
begin
  SetLength(Result, 16);
  Move(FBytes[0], Result[0], 16);
end;

function TUUID.IsNull: Boolean;
var
  I: Integer;
begin
  for I := 0 to 15 do
    if FBytes[I] <> 0 then
      Exit(False);
  Result := True;
end;

class function TUUID.Null: TUUID;
begin
  FillChar(Result.FBytes, 16, 0);
end;

function TUUID.IsEmpty: Boolean;
begin
  Result := IsNull;
end;

class function TUUID.Empty: TUUID;
begin
  Result := Null;
end;

class operator TUUID.Implicit(const S: string): TUUID;
begin
  Result := FromString(S);
end;

class operator TUUID.Implicit(const U: TUUID): string;
begin
  Result := U.ToString;
end;

class operator TUUID.Implicit(const G: TGUID): TUUID;
begin
  Result := FromGUID(G);
end;

class operator TUUID.Implicit(const U: TUUID): TGUID;
begin
  Result := U.ToGUID;
end;

class operator TUUID.Equal(const A, B: TUUID): Boolean;
begin
  Result := CompareMem(@A.FBytes[0], @B.FBytes[0], 16);
end;

class operator TUUID.NotEqual(const A, B: TUUID): Boolean;
begin
  Result := not CompareMem(@A.FBytes[0], @B.FBytes[0], 16);
end;

end.
