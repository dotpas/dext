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
{  Created: 2025-12-18                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.TypeConverters;

interface

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Types.UUID,
  Dext.Entity.Dialects,
  Dext.Entity.Attributes;

type
  /// <summary>
  ///   Marks an enum property to be saved as string instead of integer.
  /// </summary>
  EnumAsStringAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a TArray&lt;T&gt; property as database array column.
  /// </summary>
  ArrayColumnAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Specifies custom database type for a column.
  /// </summary>
  ColumnTypeAttribute = class(TCustomAttribute)
  private
    FTypeName: string;
  public
    constructor Create(const ATypeName: string);
    property TypeName: string read FTypeName;
  end;

  /// <summary>
  ///   Interface for type converters that handle database-specific type mappings.
  /// </summary>
  ITypeConverter = interface
    ['{A1B2C3D4-E5F6-7890-1234-567890ABCDEF}']
    /// <summary>
    ///   Returns true if this converter can handle the given type.
    /// </summary>
    function CanConvert(ATypeInfo: PTypeInfo): Boolean;
    
    /// <summary>
    ///   Converts a Delphi value to database representation.
    /// </summary>
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
    
    /// <summary>
    ///   Converts a database value to Delphi representation.
    /// </summary>
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
    
    /// <summary>
    ///   Returns SQL cast expression for the given parameter.
    /// </summary>
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
  end;

  /// <summary>
  ///   Base class for type converters.
  /// </summary>
  TTypeConverterBase = class abstract(TInterfacedObject, ITypeConverter)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; virtual; abstract;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; virtual; abstract;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; virtual; abstract;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; virtual;
  end;

  /// <summary>
  ///   Converter for TGUID type.
  /// </summary>
  TGuidConverter = class(TTypeConverterBase)
  private
    FSwapEndianness: Boolean;
    function DoSwap(const G: TGUID): TGUID;
  public
    constructor Create(ASwapEndianness: Boolean = False);
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for TUUID type (RFC 9562).
  /// </summary>
  TUuidConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for Enum types.
  /// </summary>
  TEnumConverter = class(TTypeConverterBase)
  private
    FUseString: Boolean;
  public
    constructor Create(AUseString: Boolean);
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
  end;

  /// <summary>
  ///   Converter for JSON/JSONB types (stores objects as JSON strings).
  /// </summary>
  TJsonConverter = class(TTypeConverterBase)
  private
    FUseJsonB: Boolean;
  public
    constructor Create(AUseJsonB: Boolean = True);
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for Array types (PostgreSQL arrays).
  /// </summary>
  TArrayConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for TDateTime types.
  /// </summary>
  TDateTimeConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for TDate types.
  /// </summary>
  TDateConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for TTime types.
  /// </summary>
  TTimeConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
    function GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string; override;
  end;

  /// <summary>
  ///   Converter for TBytes types (BLOBs).
  /// </summary>
  TBytesConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
  end;

  /// <summary>
  ///   Converter for Prop&lt;T&gt; types.
  /// </summary>
  TPropConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
  end;

  /// <summary>
  ///   Converter for TStrings and descendants (TStringList).
  /// </summary>
  TStringsConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
  end;

  /// <summary>
  ///   Registry for type converters.
  /// </summary>
  TTypeConverterRegistry = class
  private
    class var FInstance: TTypeConverterRegistry;
    FLock: TCriticalSection;
    FConverters: IList<ITypeConverter>;
    FCustomConverters: Dext.Collections.Dict.IDictionary<PTypeInfo, ITypeConverter>; // For property-specific converters
    class constructor Create;
    class destructor Destroy;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>
    ///   Registers a global type converter.
    /// </summary>
    procedure RegisterConverter(AConverter: ITypeConverter);
    
    /// <summary>
    ///   Registers a converter for a specific type (overrides global).
    /// </summary>
    procedure RegisterConverterForType(ATypeInfo: PTypeInfo; AConverter: ITypeConverter);
    
    /// <summary>
    ///   Gets the appropriate converter for a type.
    /// </summary>
    function GetConverter(ATypeInfo: PTypeInfo): ITypeConverter;
    
    /// <summary>
    ///   Clears all custom converters (useful for testing).
    /// </summary>
    procedure ClearCustomConverters;
    
    class property Instance: TTypeConverterRegistry read FInstance;
  end;

implementation

uses
  System.Variants,
  Dext.Core.Reflection,
  Dext.Core.ValueConverters,
  Dext.Json,
  Dext.Utils;

{ ColumnTypeAttribute }

constructor ColumnTypeAttribute.Create(const ATypeName: string);
begin
  inherited Create;
  FTypeName := ATypeName;
end;

{ TTypeConverterBase }

function TTypeConverterBase.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  // Default: no cast
  Result := AParamName;
end;

{ TGuidConverter }

constructor TGuidConverter.Create(ASwapEndianness: Boolean);
begin
  inherited Create;
  FSwapEndianness := ASwapEndianness;
end;

function TGuidConverter.DoSwap(const G: TGUID): TGUID;
begin
  Result := G;
  Result.D1 := ((Result.D1 and $000000FF) shl 24) or
               ((Result.D1 and $0000FF00) shl 8) or
               ((Result.D1 and $00FF0000) shr 8) or
               ((Result.D1 and $FF000000) shr 24);
  Result.D2 := Swap(Result.D2);
  Result.D3 := Swap(Result.D3);
end;

function TGuidConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TGUID);
end;

function TGuidConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
var
  Guid: TGUID;
  U: TUUID;
begin
  AValue.ExtractRawData(@Guid);
  // Convert to TUUID for proper Big-Endian string representation (no braces)
  U := TUUID.FromGUID(Guid);
  Result := U.ToString; // Returns 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' (lowercase, no braces)
end;

function TGuidConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  Guid: TGUID;
  GuidStr: string;
  U: TUUID;
begin
  if AValue.IsEmpty then
  begin
    FillChar(Guid, SizeOf(TGUID), 0);
    TValue.Make(@Guid, TypeInfo(TGUID), Result);
  end
  else if AValue.TypeInfo = TypeInfo(TGUID) then
  begin
    // FireDAC returns TGUID directly - use as-is (byte-order is consistent)
    AValue.ExtractRawData(@Guid);
    if FSwapEndianness then
      Guid := DoSwap(Guid);
    TValue.Make(@Guid, TypeInfo(TGUID), Result);
  end
  else
  begin
    GuidStr := AValue.AsString;
    try
      // Use TUUID to parse (handles with/without braces, Big-Endian)
      U := TUUID.FromString(GuidStr);
      Guid := U.ToGUID; // Convert to Delphi TGUID (Little-Endian)
      
      if FSwapEndianness then
        Guid := DoSwap(Guid);
    except
      on E: Exception do
        raise Exception.CreateFmt('''%s'' is not a valid GUID value (SourceType: %s, Kind: %d)', 
          [GuidStr, AValue.TypeInfo.Name, Ord(AValue.Kind)]);
    end;
    TValue.Make(@Guid, TypeInfo(TGUID), Result);
  end;
end;

function TGuidConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL:
      Result := Format('%s::uuid', [AParamName]);
    ddSQLServer:
      Result := Format('CAST(%s AS UNIQUEIDENTIFIER)', [AParamName]);
    ddMySQL, ddMariaDB, ddSQLite:
      Result := AParamName; // Use as string
    else
      Result := AParamName;
  end;
end;


{ TUuidConverter }

function TUuidConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TUUID);
end;

function TUuidConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
var
  U: TUUID;
begin
  AValue.ExtractRawData(@U);
  Result := U.ToString; // Canonical string
end;

function TUuidConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  U: TUUID;
  GuidStr: string;
  G: TGUID;
  Bytes: array[0..15] of Byte;
begin
  if AValue.IsEmpty then
  begin
    U := TUUID.Null;
    TValue.Make(@U, TypeInfo(TUUID), Result);
  end
  else if AValue.TypeInfo = TypeInfo(TGUID) then
  begin
    // FireDAC returns TGUID when reading PostgreSQL uuid columns
    // The raw bytes in TGUID memory are correct (Big-Endian) - extract them directly
    AValue.ExtractRawData(@G);
    Move(G, Bytes[0], 16);
    // Format as canonical UUID string from raw bytes
    GuidStr := LowerCase(Format('%2.2x%2.2x%2.2x%2.2x-%2.2x%2.2x-%2.2x%2.2x-%2.2x%2.2x-%2.2x%2.2x%2.2x%2.2x%2.2x%2.2x',
      [Bytes[0], Bytes[1], Bytes[2], Bytes[3], Bytes[4], Bytes[5], Bytes[6], Bytes[7],
       Bytes[8], Bytes[9], Bytes[10], Bytes[11], Bytes[12], Bytes[13], Bytes[14], Bytes[15]]));
    U := TUUID.FromString(GuidStr);
    TValue.Make(@U, TypeInfo(TUUID), Result);
  end
  else
  begin
    GuidStr := AValue.AsString;
    try
      U := TUUID.FromString(GuidStr);
    except
      on E: Exception do
        raise Exception.CreateFmt('''%s'' is not a valid UUID value (SourceType: %s)', 
          [GuidStr, AValue.TypeInfo.Name]);
    end;
    TValue.Make(@U, TypeInfo(TUUID), Result);
  end;
end;

function TUuidConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL: Result := Format('%s::uuid', [AParamName]);
    ddSQLServer: Result := Format('CAST(%s AS UNIQUEIDENTIFIER)', [AParamName]);
    else Result := AParamName;
  end;
end;


{ TEnumConverter }

constructor TEnumConverter.Create(AUseString: Boolean);
begin
  inherited Create;
  FUseString := AUseString;
end;

function TEnumConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := (ATypeInfo <> nil) and 
            (ATypeInfo.Kind = tkEnumeration) and 
            (ATypeInfo <> TypeInfo(Boolean)); // Boolean is handled separately
end;

function TEnumConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  if FUseString then
    Result := GetEnumName(AValue.TypeInfo, AValue.AsOrdinal)
  else
    Result := AValue.AsOrdinal;
end;

function TEnumConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  OrdValue: Integer;
begin
  if AValue.IsEmpty then
  begin
    TValue.Make(0, ATypeInfo, Result);
  end
  else if FUseString then
  begin
    OrdValue := GetEnumValue(ATypeInfo, AValue.AsString);
    if OrdValue = -1 then
      raise Exception.CreateFmt('Invalid enum value: %s', [AValue.AsString]);
    TValue.Make(OrdValue, ATypeInfo, Result);
  end
  else
  begin
    TValue.Make(AValue.AsInteger, ATypeInfo, Result);
  end;
end;

{ TJsonConverter }

constructor TJsonConverter.Create(AUseJsonB: Boolean);
begin
  inherited Create;
  FUseJsonB := AUseJsonB;
end;

function TJsonConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  // Auto-convert known complex types effectively if registered without attribute,
  // but usually we rely on property attributes.
  // However, returning True here allows Global Registration to work.
  Result := (ATypeInfo.Kind in [tkClass, tkRecord, tkDynArray]) and
            (ATypeInfo <> TypeInfo(TGUID)) and
            (ATypeInfo <> TypeInfo(TUUID)) and
            (ATypeInfo <> TypeInfo(TBytes));
  if not Result and (ATypeInfo.Kind = tkInterface) then
    Result := TReflection.IsListType(ATypeInfo);
end;

function TJsonConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  if AValue.IsEmpty then
    Exit(TValue.Empty);

  if AValue.IsObject then
  begin
    if AValue.AsObject = nil then
      Exit(TValue.Empty);
    Result := TDextJson.Serialize(AValue.AsObject);
  end
  else if (AValue.Kind = tkInterface) and TReflection.IsListType(AValue.TypeInfo) then
  begin
    Result := TDextJson.Serialize(AValue);
  end
  else if AValue.Kind in [tkRecord, tkDynArray] then
  begin
    Result := TDextJson.Serialize(AValue);
  end
  else
    Result := AValue.AsString;
end;

function TJsonConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  JsonStr: string;
begin
  if AValue.IsEmpty then
    Exit(TValue.Empty);

  JsonStr := AValue.AsString;
  if JsonStr.Trim.IsEmpty then
    Exit(TValue.Empty);

  if (ATypeInfo.Kind in [tkClass, tkRecord, tkDynArray]) or
     ((ATypeInfo.Kind = tkInterface) and TReflection.IsListType(ATypeInfo)) then
  begin
    Result := TDextJson.Deserialize(ATypeInfo, JsonStr);
  end
  else
    Result := AValue;
end;

function TJsonConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL:
      if FUseJsonB then
        Result := Format('%s::jsonb', [AParamName])
      else
        Result := Format('%s::json', [AParamName]);
    else
      Result := AParamName;
  end;
end;

{ TArrayConverter }

function TArrayConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
var
  ElementType: PTypeInfo;
begin
  Result := False;
  if (ATypeInfo = nil) or (ATypeInfo.Kind <> tkDynArray) then
    Exit;

  ElementType := ATypeInfo.TypeData^.DynArrElType^;
  Result := (ElementType <> nil) and
    (ElementType.Kind in [tkInteger, tkInt64, tkFloat, tkString, tkLString, tkWString, tkUString, tkEnumeration, tkRecord]);
end;

function TArrayConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  if AValue.IsEmpty then
    Exit(TValue.Empty);

  Result := TDextJson.Serialize(AValue);
end;

function TArrayConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  JsonStr: string;
begin
  if AValue.IsEmpty then
    Exit(TValue.Empty);

  if (AValue.Kind = tkDynArray) and (AValue.TypeInfo = ATypeInfo) then
    Exit(AValue);

  JsonStr := AValue.AsString;
  if JsonStr.IsEmpty then
    Exit(TDextJson.Deserialize(ATypeInfo, '[]'));

  Result := TDextJson.Deserialize(ATypeInfo, JsonStr);
end;

function TArrayConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL:
      // The array is stored as JSON text (see ToDatabase), in a jsonb column.
      Result := Format('%s::jsonb', [AParamName]);
    else
      Result := AParamName;
  end;
end;

{ TTypeConverterRegistry }

class constructor TTypeConverterRegistry.Create;
begin
  FInstance := TTypeConverterRegistry.Create;
end;

class destructor TTypeConverterRegistry.Destroy;
begin
  FInstance.Free;
end;

constructor TTypeConverterRegistry.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FConverters := TCollections.CreateList<ITypeConverter>;
  FCustomConverters := TCollections.CreateDictionary<PTypeInfo, ITypeConverter>;
  
  // Register built-in converters
  RegisterConverter(TGuidConverter.Create);
  RegisterConverter(TUuidConverter.Create);
  RegisterConverter(TDateTimeConverter.Create);
  RegisterConverter(TDateConverter.Create);
  RegisterConverter(TTimeConverter.Create);
  RegisterConverter(TBytesConverter.Create);
  RegisterConverter(TArrayConverter.Create);
  RegisterConverter(TPropConverter.Create);
  RegisterConverter(TStringsConverter.Create);
  // Note: Enum, JSON, Array converters are registered dynamically or explicitly
end;

destructor TTypeConverterRegistry.Destroy;
begin
  FLock.Free;
  FCustomConverters := nil;
  FConverters := nil;
  inherited;
end;

procedure TTypeConverterRegistry.RegisterConverter(AConverter: ITypeConverter);
begin
  FLock.Enter;
  try
    FConverters.Add(AConverter);
  finally
    FLock.Leave;
  end;
end;

procedure TTypeConverterRegistry.RegisterConverterForType(ATypeInfo: PTypeInfo; AConverter: ITypeConverter);
begin
  FLock.Enter;
  try
    FCustomConverters.AddOrSetValue(ATypeInfo, AConverter);
  finally
    FLock.Leave;
  end;
end;

procedure TTypeConverterRegistry.ClearCustomConverters;
begin
  FLock.Enter;
  try
    FCustomConverters.Clear;
  finally
    FLock.Leave;
  end;
end;

function TTypeConverterRegistry.GetConverter(ATypeInfo: PTypeInfo): ITypeConverter;
var
  Converter: ITypeConverter;
begin
  Result := nil;
  
  if ATypeInfo = nil then
    Exit;
  
  FLock.Enter;
  try
    // Check custom converters first (highest priority)
    if FCustomConverters.TryGetValue(ATypeInfo, Result) then
      Exit;
    
    // Find global converter
    for Converter in FConverters do
    begin
      if Converter.CanConvert(ATypeInfo) then
      begin
        Result := Converter;
        Exit;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

{ TDateTimeConverter }

function TDateTimeConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TDateTime);
end;

function TDateTimeConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  Result := AValue; // TDateTime is already TValue compatible
end;

function TDateTimeConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
begin
  Result := AValue;
end;

function TDateTimeConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL: Result := Format('%s::timestamp', [AParamName]);
    ddSQLServer: Result := Format('CAST(%s AS DATETIME2)', [AParamName]);
    else Result := AParamName;
  end;
end;

{ TDateConverter }

function TDateConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TDate);
end;

function TDateConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  Result := AValue;
end;

function TDateConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
begin
  Result := AValue;
end;

function TDateConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL: Result := Format('%s::date', [AParamName]);
    ddSQLServer: Result := Format('CAST(%s AS DATE)', [AParamName]);
    else Result := AParamName;
  end;
end;

{ TTimeConverter }

function TTimeConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TTime);
end;

function TTimeConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  Result := AValue;
end;

function TTimeConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
begin
  Result := AValue;
end;

function TTimeConverter.GetSQLCast(const AParamName: string; ADialect: TDatabaseDialect): string;
begin
  case ADialect of
    ddPostgreSQL: Result := Format('%s::time', [AParamName]);
    ddSQLServer: Result := Format('CAST(%s AS TIME)', [AParamName]);
    else Result := AParamName;
  end;
end;

{ TBytesConverter }

function TBytesConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := (ATypeInfo <> nil) and (ATypeInfo = TypeInfo(TBytes));
end;

function TBytesConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  Result := AValue;
end;

function TBytesConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
begin
  Result := AValue;
end;

{ TPropConverter }

function TPropConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
var
  Typ: TRttiType;
  TypeName: string;
begin
  Result := False;
  if ATypeInfo = nil then Exit;
  
  TypeName := string(ATypeInfo.Name);
  
  // Explicitly exclude Nullable types as they are handled by TValueConverter/TReflection
  // and require setting FHasValue which TPropConverter doesn't do.
  if TypeName.StartsWith('Nullable<') or TypeName.StartsWith('TNullable') then
    Exit(False);
  
  if TypeName.StartsWith('Prop<') then
    Exit(True);

  // Fallback for aliased types: look for FValue field
  Typ := TReflection.Context.GetType(ATypeInfo);
  if (Typ <> nil) and (Typ.TypeKind = tkRecord) then
    Result := Typ.GetField('FValue') <> nil;
end;

function TPropConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
var
  Typ: TRttiType;
  Field: TRttiField;
  ValPropType: PTypeInfo;
  InnerConverter: ITypeConverter;
begin
  if AValue.IsEmpty then Exit(TValue.Empty);
  Typ := TReflection.Context.GetType(AValue.TypeInfo);
  // Use Field 'FValue' instead of Property 'Value' to avoid potential RTTI property access issues on generic records
  Field := Typ.GetField('FValue');
  
  if Field <> nil then
  begin
    ValPropType := Field.FieldType.Handle;
    Result := Field.GetValue(AValue.GetReferenceToRawData);
    
    // Recursive conversion
    if not Result.IsEmpty then
    begin
      InnerConverter := TTypeConverterRegistry.Instance.GetConverter(ValPropType);
      if InnerConverter <> nil then
        Result := InnerConverter.ToDatabase(Result, ADialect);
    end;
  end
  else
    Result := AValue;
end;

function TPropConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  Typ: TRttiType;
  Field: TRttiField;
  ValPropType: PTypeInfo;
  UnwrappedValue: TValue;
begin
  TValue.Make(nil, ATypeInfo, Result); // Initialize Prop<T> result
  // Zero-init record memory to avoid garbage in managed interface/string fields
  FillChar(Result.GetReferenceToRawData^, ATypeInfo.TypeData.RecSize, 0);
  
  Typ := TReflection.Context.GetType(ATypeInfo);
  Field := Typ.GetField('FValue');

  if Field <> nil then
  begin
    ValPropType := Field.FieldType.Handle;
    
    try
      // Try standard properties conversion
      UnwrappedValue := TValueConverter.Convert(AValue, ValPropType);
    except
      on E: Exception do
        UnwrappedValue := AValue;
    end;

    // Align PTypeInfo for records across DCU boundaries to avoid EInvalidCast in native RTTI SetValue
    if (UnwrappedValue.TypeInfo <> ValPropType) and (UnwrappedValue.TypeInfo <> nil) and (ValPropType <> nil) and
       (UnwrappedValue.TypeInfo.Kind = tkRecord) and (ValPropType.Kind = tkRecord) and
       SameText(string(UnwrappedValue.TypeInfo.Name), string(ValPropType.Name)) then
    begin
      TValue.Make(UnwrappedValue.GetReferenceToRawData, ValPropType, UnwrappedValue);
    end;
      
    Field.SetValue(Result.GetReferenceToRawData, UnwrappedValue);
  end;
end;

{ TStringsConverter }

function TStringsConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
var
  Typ: TRttiType;
begin
  Result := False;
  if (ATypeInfo <> nil) and (ATypeInfo.Kind = tkClass) then
  begin
    Typ := TReflection.Context.GetType(ATypeInfo);
    if Typ is TRttiInstanceType then
      Result := TRttiInstanceType(Typ).MetaclassType.InheritsFrom(TStrings);
  end;
end;

function TStringsConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  if AValue.IsEmpty or (AValue.AsObject = nil) then
    Exit(TValue.Empty);
    
  Result := (AValue.AsObject as TStrings).Text;
end;

function TStringsConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
var
  Strings: TStrings;
  Typ: TRttiType;
  LClass: TClass;
  LConstructor: TRttiMethod;
begin
  if AValue.IsEmpty or (AValue.ToString = '') then
    Exit(TValue.Empty);

  Typ := TReflection.Context.GetType(ATypeInfo);
  if Typ is TRttiInstanceType then
  begin
    LClass := TRttiInstanceType(Typ).MetaclassType;
    if (LClass = TStrings) then
      LClass := TStringList;

    if LClass = TStringList then
      Strings := TStringList.Create
    else
    begin
      LConstructor := TReflection.Context.GetType(LClass).GetMethod('Create');
      if (LConstructor <> nil) and (LConstructor.IsConstructor) then
        Strings := LConstructor.Invoke(LClass, []).AsObject as TStrings
      else
        Strings := TStrings(LClass.NewInstance);
    end;

    Strings.Text := AValue.ToString;
    Result := TValue.From<TStrings>(Strings);
  end
  else
    Result := TValue.Empty;
end;

initialization
  // Register missing converters for loose typing (e.g. SQLite returning strings for Integers)
  TValueConverterRegistry.RegisterConverter(TypeInfo(string), TypeInfo(Integer), TVariantToIntegerConverter.Create);
  TValueConverterRegistry.RegisterConverter(TypeInfo(string), TypeInfo(Int64), TVariantToIntegerConverter.Create);
  TValueConverterRegistry.RegisterConverter(TypeInfo(string), TypeInfo(Double), TVariantToFloatConverter.Create);
  TValueConverterRegistry.RegisterConverter(TypeInfo(string), TypeInfo(TDateTime), TVariantToDateTimeConverter.Create);

  // Register Kind-based converters at Entity level for extra safety
  TValueConverterRegistry.RegisterConverter(tkUString, tkFloat, TVariantToFloatConverter.Create);
  TValueConverterRegistry.RegisterConverter(tkString, tkFloat, TVariantToFloatConverter.Create);
end.
