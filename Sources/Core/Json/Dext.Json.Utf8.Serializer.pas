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
{  Created: 2025-12-19                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Json.Utf8.Serializer;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Collections.Vector,
  Dext.Core.Span,
  Dext.Json.Utf8,
  Dext.Core.DateUtils,
  Dext.Types.UUID,
  Dext.Core.Reflection;

type
  /// <summary>
  ///   Exception type for UTF-8 JSON serialization errors.
  /// </summary>
  EUtf8SerializationException = class(Exception);

  /// <summary>
  ///   Pointer to a TUUID record.
  /// </summary>
  PTUUID = ^TUUID;

  /// <summary>
  ///   Holds reflection and offset information for a JSON serializable field.
  /// </summary>
  TJsonFieldInfo = record
    NameBytes: TBytes;
    Offset: Integer;
    TypeKind: TTypeKind;
    TypeInfo: PTypeInfo;
  end;

  /// <summary>
  ///   Holds the mapping of all fields for a JSON serializable record.
  /// </summary>
  TJsonRecordInfo = record
    Fields: TArray<TJsonFieldInfo>;
  end;

  /// <summary>
  ///   Global cache for UTF-8 JSON serialization metadata.
  /// </summary>
  TUtf8JsonSerializerCache = class
  public class var
    Cache: IDictionary<PTypeInfo, TJsonRecordInfo>;
    class constructor Create;
  end;

  /// <summary>
  ///   High-performance, zero-allocation UTF-8 JSON serializer for records.
  /// </summary>
  TUtf8JsonSerializer = record
  private
    class function GetRecordInfo(AType: PTypeInfo): TJsonRecordInfo; static;
    class procedure DeserializeRecord(var AReader: TUtf8JsonReader; AType: PTypeInfo; AInstance: Pointer); static;
    class procedure DeserializeFieldDirect(var AReader: TUtf8JsonReader; const FieldInfo: TJsonFieldInfo; Instance: Pointer); static;
    class procedure ReadBytes(var AReader: TUtf8JsonReader; const FieldInfo: TJsonFieldInfo; P: Pointer); static;
  public
    class function Deserialize<T>(const AData: TByteSpan): T; static;
  end;

implementation

uses
  Dext.Json; // JsonIgnoreAttribute

{ TUtf8JsonSerializerCache }

class constructor TUtf8JsonSerializerCache.Create;
begin
  Cache := TCollections.CreateDictionary<PTypeInfo, TJsonRecordInfo>;
end;

{ TUtf8JsonSerializer }

class function TUtf8JsonSerializer.GetRecordInfo(AType: PTypeInfo): TJsonRecordInfo;
var
  RType: TRttiType;
  Field: TRttiField;
  FldInfo: TJsonFieldInfo;
  Fields: TVector<TJsonFieldInfo>;
  Attr: TCustomAttribute;
  IgnoreRead: Boolean;
begin
  if TUtf8JsonSerializerCache.Cache.TryGetValue(AType, Result) then
    Exit;

  RType := TReflection.Context.GetType(AType);
  if RType = nil then Exit;

  for Field in RType.GetFields do
  begin
    // This is a reader: a field ignored on read is not in the list, so its
    // name in the JSON is skipped like an unknown one.
    IgnoreRead := False;
    for Attr in Field.GetAttributes do
      if (Attr is JsonIgnoreAttribute) and JsonIgnoreAttribute(Attr).IgnoresRead then
        IgnoreRead := True;
    if IgnoreRead then
      Continue;

    FldInfo.NameBytes := TEncoding.UTF8.GetBytes(Field.Name);
    FldInfo.Offset := Field.Offset;
    if Field.FieldType <> nil then
    begin
      FldInfo.TypeKind := Field.FieldType.TypeKind;
      FldInfo.TypeInfo := Field.FieldType.Handle;
    end
    else
    begin
      FldInfo.TypeKind := tkUnknown;
      FldInfo.TypeInfo := nil;
    end;
    Fields.Add(FldInfo);
  end;

  Result.Fields := Fields.ToArray;
  TUtf8JsonSerializerCache.Cache.Add(AType, Result);
end;

class function TUtf8JsonSerializer.Deserialize<T>(const AData: TByteSpan): T;
var
  Reader: TUtf8JsonReader;
  TypeInfoInfo: PTypeInfo;
begin
  Reader := TUtf8JsonReader.Create(AData);
  TypeInfoInfo := System.TypeInfo(T);

  // Initial Read to get to the start
  if not Reader.Read then
    Exit(Default(T)); 

  if TypeInfoInfo.Kind = tkRecord then
  begin
    Result := Default(T);
    DeserializeRecord(Reader, TypeInfoInfo, @Result);
  end
  else
    raise EUtf8SerializationException.Create('Only Records are supported for zero-allocation deserialization currently.');
end;

class procedure TUtf8JsonSerializer.DeserializeRecord(var AReader: TUtf8JsonReader; AType: PTypeInfo; AInstance: Pointer);
var
  RecInfo: TJsonRecordInfo;
  I: Integer;
  Found: Boolean;
  ValSpan: TByteSpan;
begin
  if AReader.TokenType <> TJsonTokenType.StartObject then
   if AReader.TokenType <> TJsonTokenType.StartObject then
     raise EUtf8SerializationException.Create('Expected StartObject');

  RecInfo := GetRecordInfo(AType);

  while AReader.Read do
  begin
    if AReader.TokenType = TJsonTokenType.EndObject then
      Break;

    if AReader.TokenType = TJsonTokenType.PropertyName then
    begin
      ValSpan := AReader.ValueSpan;
      Found := False;
      
      for I := 0 to High(RecInfo.Fields) do
      begin
        if ValSpan.Equals(TByteSpan.FromBytes(RecInfo.Fields[I].NameBytes)) then
        begin
          if not AReader.Read then
            raise EUtf8SerializationException.Create('Unexpected end of JSON while reading value');
            
          DeserializeFieldDirect(AReader, RecInfo.Fields[I], AInstance);
          Found := True;
          Break;
        end;
      end;
      
      if not Found then
      begin
        // Advance to Value and Skip
        if AReader.Read then
          AReader.Skip;
      end;
    end;
  end;
end;

class procedure TUtf8JsonSerializer.DeserializeFieldDirect(var AReader: TUtf8JsonReader; const FieldInfo: TJsonFieldInfo; Instance: Pointer);
var
  P: Pointer;
  DateStr: string;
  Dt: TDateTime;
  GuidStr: string;
  G: TGUID;
  EnumText: string;
  N: Int64;
  Data: PTypeData;
begin
  P := Pointer(NativeUInt(Instance) + NativeUInt(FieldInfo.Offset));
  case FieldInfo.TypeKind of
    tkInteger:
      PInteger(P)^ := AReader.GetInt32;
      
    tkInt64:
      PInt64(P)^ := AReader.GetInt64;
      
    tkFloat:
      if (FieldInfo.TypeInfo = TypeInfo(TDateTime)) or
         (FieldInfo.TypeInfo = TypeInfo(TDate)) or
         (FieldInfo.TypeInfo = TypeInfo(TTime)) then
      begin
         DateStr := AReader.GetString;
         // The standard forms first: a zone is converted to local time
         if TJsonUtils.TryJsonTextToDate(DateStr, FieldInfo.TypeInfo, Dt) then
           PDateTime(P)^ := Dt
         else
           PDateTime(P)^ := 0;
      end
      else if FieldInfo.TypeInfo = TypeInfo(Currency) then
        // Bug #93: Currency is stored as Int64 * 10000 (fixed-point, ftCurr).
        // Writing raw IEEE-754 Double bits via PDouble^ produces wildly incorrect
        // values. Assigning via PCurrency^ lets the compiler emit the correct
        // FILD/FISTP pair that converts Double → Int64*10000 properly.
        PCurrency(P)^ := AReader.GetDouble
      else
        PDouble(P)^ := AReader.GetDouble;
      
    tkString, tkLString, tkWString, tkUString:
      PString(P)^ := AReader.GetString;
      
    tkEnumeration:
      if FieldInfo.TypeInfo = TypeInfo(Boolean) then
        PBoolean(P)^ := AReader.GetBoolean
      else if AReader.TokenType <> TJsonTokenType.NullValue then
      begin
        // By name or by number, whatever EnumStyle wrote it. What is not a
        // value of the enum is refused, not stored.
        if AReader.TokenType = TJsonTokenType.Number then
        begin
          EnumText := '';
          N := AReader.GetInt64;
        end
        else
        begin
          EnumText := AReader.GetString;
          N := GetEnumValue(FieldInfo.TypeInfo, EnumText);
        end;
        Data := GetTypeData(FieldInfo.TypeInfo);
        if (N < Data^.MinValue) or (N > Data^.MaxValue) then
        begin
          if EnumText = '' then
            EnumText := IntToStr(N);
          raise EUtf8SerializationException.CreateFmt('%s is not a value of %s',
            [EnumText, GetTypeName(FieldInfo.TypeInfo)]);
        end;
        case Data^.OrdType of
          otSByte, otUByte:
            PByte(P)^ := Byte(N);
          otSWord, otUWord:
            PWord(P)^ := Word(N);
        else
          PCardinal(P)^ := Cardinal(N);
        end;
      end;
        
    tkRecord:
      begin
        if FieldInfo.TypeInfo = TypeInfo(TGUID) then
        begin
          GuidStr := AReader.GetString;
          
          if GuidStr.Trim = '' then
            G := TGUID.Empty
          else if GuidStr.StartsWith('{') and GuidStr.EndsWith('}') then
            G := StringToGUID(GuidStr)
          else if GuidStr.Length = 36 then
            G := StringToGUID('{' + GuidStr + '}')
          else
            G := StringToGUID(GuidStr);
            
          PGUID(P)^ := G;
        end
        else if FieldInfo.TypeInfo = TypeInfo(TUUID) then
        begin
          GuidStr := AReader.GetString;
          if GuidStr.Trim = '' then
            PTUUID(P)^ := TUUID.Null
          else
            PTUUID(P)^ := TUUID.FromString(GuidStr);
        end
        else
        begin
          AReader.Skip;
        end;
      end;

    tkDynArray:
      if TJsonUtils.IsBytesType(FieldInfo.TypeInfo) then
        ReadBytes(AReader, FieldInfo, P)
      else
        AReader.Skip;
      
    else
      AReader.Skip;
  end;
end;

class procedure TUtf8JsonSerializer.ReadBytes(var AReader: TUtf8JsonReader;
  const FieldInfo: TJsonFieldInfo; P: Pointer);

  procedure Refuse(const AWhy: string);
  begin
    raise EUtf8SerializationException.CreateFmt('Field "%s": %s',
      [TEncoding.UTF8.GetString(FieldInfo.NameBytes), AWhy]);
  end;

var
  Bytes: TBytes;
  Count: Integer;
  N: Int64;
begin
  // A byte array: a Base64 string, or an array of numbers from 0 to 255 (as
  // Dext.Json reads it). null leaves the field as it is.
  case AReader.TokenType of
    TJsonTokenType.NullValue:
      Exit;
    TJsonTokenType.StringValue:
      if not TJsonUtils.TryBase64ToBytes(AReader.GetString, Bytes) then
        Refuse('the text is not Base64');
    TJsonTokenType.StartArray:
      begin
        Count := 0;
        while AReader.Read and (AReader.TokenType <> TJsonTokenType.EndArray) do
        begin
          if (AReader.TokenType <> TJsonTokenType.Number) or
             not TryStrToInt64(AReader.ValueSpan.ToString, N) or (N < 0) or (N > 255) then
            Refuse(Format('item %d is not a number from 0 to 255', [Count]));
          if Count = Length(Bytes) then
            SetLength(Bytes, Count * 2 + 16);
          Bytes[Count] := Byte(N);
          Inc(Count);
        end;
        if AReader.TokenType <> TJsonTokenType.EndArray then
          raise EUtf8SerializationException.Create('Unexpected end of JSON while reading an array');
        SetLength(Bytes, Count);
      end;
  else
    Refuse('binary data must be a Base64 string or an array of numbers from 0 to 255');
  end;
  // Any dynamic array of Byte has the layout of TBytes
  TBytes(P^) := Bytes;
end;

end.
