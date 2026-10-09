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
{  Created: 2025-12-08                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Json;

interface

uses
  System.Character,
  System.Rtti,
  System.StrUtils,
  System.SysUtils,
  System.TypInfo,
  Dext.Core.Span,
  Dext.Collections,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Core.Activator,
  Dext.Core.DirectAccess,
  Dext.Core.TypeModel,
  Dext.DI.Interfaces,
  Dext.Json.Types,
  Dext.Types.UUID;

type
  TJsonSettings = Dext.Json.Types.TJsonSettings;
  /// <summary>Non-capturing sink callback for direct UTF-8 serialization.</summary>
  TDextJsonWriteProc = procedure(AContext, AData: Pointer; ALength: Integer);
  /// <summary>
  ///   Exception raised for errors during JSON serialization or deserialization.
  /// </summary>
  EDextJsonException = class(Exception);

  /// <summary>
  ///   Base class for all Dext JSON attributes.
  /// </summary>
  DextJsonAttribute = class abstract(TCustomAttribute)
  end;

  /// <summary>
  ///   Specifies a custom name for a field in the JSON output.
  /// </summary>
  JsonNameAttribute = class(DextJsonAttribute)
  private
    FName: string;
  public
    /// <summary>
    ///   Initializes a new instance of the JsonNameAttribute class.
    /// </summary>
    /// <param name="AName">
    ///   The custom name to be used in the JSON.
    /// </param>
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Indicates that a field should be ignored during serialization and deserialization.
  /// </summary>
  JsonIgnoreAttribute = class(DextJsonAttribute);

  /// <summary>
  ///   On a class: only its published properties are serialized. Public
  ///   properties stay working members that never reach the JSON. Inherited
  ///   by subclasses.
  /// </summary>
  JsonPublishedOnlyAttribute = class(DextJsonAttribute);

  /// <summary>
  ///   Specifies a custom format string for date/time fields.
  /// </summary>
  JsonFormatAttribute = class(DextJsonAttribute)
  private
    FFormat: string;
  public
    /// <summary>
    ///   Initializes a new instance of the JsonFormatAttribute class.
    /// </summary>
    /// <param name="AFormat">
    ///   The format string (e.g., 'yyyy-mm-dd').
    /// </param>
    constructor Create(const AFormat: string);
    property Format: string read FFormat;
  end;

  /// <summary>
  ///   Forces a numeric field to be serialized as a string.
  /// </summary>
  JsonStringAttribute = class(DextJsonAttribute);

  /// <summary>
  ///   Forces a string field to be serialized as a number (if possible).
  /// </summary>
  JsonNumberAttribute = class(DextJsonAttribute);

  /// <summary>
  ///   Forces a field to be serialized as a boolean.
  /// </summary>
  JsonBooleanAttribute = class(DextJsonAttribute);

  /// <summary>Deprecated alias for TCaseStyle.</summary>
  TDextCaseStyle = TCaseStyle deprecated 'Use TCaseStyle instead';

  /// <summary>Deprecated alias for TEnumStyle.</summary>
  TDextEnumStyle = TEnumStyle deprecated 'Use TEnumStyle instead';

  /// <summary>Deprecated alias for TJsonFormatting.</summary>
  TDextFormatting = TJsonFormatting deprecated 'Use TJsonFormatting instead';

  /// <summary>Deprecated alias for TDateFormat.</summary>
  TDextDateFormat = TDateFormat deprecated 'Use TDateFormat instead';

  /// <summary>
  ///   Utilities for JSON manipulation, including casing.
  /// </summary>
  TJsonUtils = record
  public
    class function ToCamelCase(const S: string): string; static;
    class function ToPascalCase(const S: string): string; static;
    class function ToSnakeCase(const S: string): string; static;
    class function ApplyCaseStyle(const S: string; Style: TCaseStyle): string; static;
  end;

  /// <summary>Deprecated alias for TJsonSettings.</summary>
  TDextSettings = TJsonSettings deprecated 'Use TJsonSettings instead';

  /// <summary>
  ///   Main entry point for JSON serialization and deserialization in Dext.
  ///   Acts as a high-level facade that uses configurable providers (drivers).
  /// </summary>
  TDextJson = class
  private
    class var FProvider: IDextJsonProvider;
    class var FDefaultSettings: TJsonSettings;
    class var FInterfaceMappings: IDictionary<string, string>;
    class function GetProvider: IDextJsonProvider; static;
    class function GetInterfaceMappings: IDictionary<string, string>; static;
  public
    /// <summary>
    ///   Registers a default implementation class for an interface type.
    ///   Used during deserialization when an interface is encountered.
    /// </summary>
    class procedure RegisterImplementation(const AInterfaceName, AImplementationName: string); static;
  public
    /// <summary>
    ///   Sets the default settings to be used for all serialization/deserialization
    ///   operations that don't explicitly provide settings.
    /// </summary>
    class procedure SetDefaultSettings(const ASettings: TJsonSettings); static;

    /// <summary>
    ///   Gets the current default settings.
    /// </summary>
    class function GetDefaultSettings: TJsonSettings; static;
    /// <summary>
    ///   Gets or sets the JSON provider (driver) to be used.
    ///   Defaults to JsonDataObjects if not set.
    /// </summary>
    class property Provider: IDextJsonProvider read GetProvider write FProvider;

    /// <summary>
    ///   Deserializes a JSON string into a value of type T using default settings.
    /// </summary>
    class function Deserialize<T>(const AJson: string): T; overload; static;

    /// <summary>
    ///   Deserializes a JSON string into a value of type T using custom settings.
    /// </summary>
    class function Deserialize<T>(const AJson: string; const ASettings: TJsonSettings): T; overload; static;

    /// <summary>
    ///   Deserializes a JSON string into a TValue based on the provided type info.
    /// </summary>
    class function Deserialize(AType: PTypeInfo; const AJson: string): TValue; overload; static;

    /// <summary>
    ///   Deserializes a JSON string into a TValue based on the provided type info with custom settings.
    /// </summary>
    class function Deserialize(AType: PTypeInfo; const AJson: string; const ASettings: TJsonSettings): TValue; overload; static;

    /// <summary>
    ///   Deserializes a JSON string into a record TValue.
    /// </summary>
    class function DeserializeRecord(AType: PTypeInfo; const AJson: string): TValue; static;

    /// <summary>
    ///   Serializes a value of type T into a JSON string using default settings.
    /// </summary>
    class function Serialize<T>(const AValue: T): string; overload; static;

    /// <summary>
    ///   Serializes a value of type T into a JSON string using custom settings.
    /// </summary>
    class function Serialize<T>(const AValue: T; const ASettings: TJsonSettings): string; overload; static;

    /// <summary>
    ///   Serializes a TValue into a JSON string using default settings.
    /// </summary>
    class function Serialize(const AValue: TValue): string; overload; static;

    /// <summary>
    ///   Serializes a value of type T into UTF-8 JSON bytes using default settings.
    /// </summary>
    class function SerializeUtf8<T>(const AValue: T): TBytes; overload; static;

    /// <summary>
    ///   Serializes a value of type T into UTF-8 JSON bytes using custom settings.
    /// </summary>
    class function SerializeUtf8<T>(const AValue: T; const ASettings: TJsonSettings): TBytes; overload; static;

    /// <summary>
    ///   Serializes an interface value into UTF-8 JSON bytes using default settings.
    /// </summary>
    class function SerializeUtf8(const AValue: IInterface): TBytes; overload; static;

    /// <summary>
    ///   Serializes an interface value into UTF-8 JSON bytes using custom settings.
    /// </summary>
    class function SerializeUtf8(const AValue: IInterface; const ASettings: TJsonSettings): TBytes; overload; static;

    /// <summary>
    ///   Serializes a TValue into UTF-8 JSON bytes using default settings.
    /// </summary>
    class function SerializeUtf8(const AValue: TValue): TBytes; overload; static;

    /// <summary>
    ///   Serializes a TValue into UTF-8 JSON bytes using custom settings.
    /// </summary>
    class function SerializeUtf8(const AValue: TValue; const ASettings: TJsonSettings): TBytes; overload; static;
    /// <summary>Serializes a TValue directly to a UTF-8 byte sink.</summary>
    class procedure SerializeUtf8To(const AValue: TValue; AContext: Pointer;
      AWrite: TDextJsonWriteProc); overload; static;
    /// <summary>Serializes a TValue directly to a UTF-8 byte sink.</summary>
    class procedure SerializeUtf8To(const AValue: TValue;
      const ASettings: TJsonSettings; AContext: Pointer;
      AWrite: TDextJsonWriteProc); overload; static;

    /// <summary>
    ///   Serializes a TValue into a JSON string using custom settings.
    /// </summary>
    class function Serialize(const AValue: TValue; const ASettings: TJsonSettings): string; overload; static;
  end;

  /// <summary>
  ///   Classification of how a property should be serialized.
  ///   Pre-computed once per type to avoid repeated RTTI dispatch.
  /// </summary>
  TSerializeKind = (
    skInteger,
    skFloat,
    skDateTime,
    skString,
    skBoolean,
    skEnumAsString,
    skEnumAsNumber,
    skRecord,
    skRecordGUID,
    skRecordUUID,
    skClass,
    skList,
    skDynArray,
    skInterface,
    skUnknown
  );

  /// <summary>
  ///   Pre-computed serialization metadata for a single property.
  ///   Built once per type, reused across all instances.
  /// </summary>
  TSerializationPlanItem = record
    /// <summary>Final JSON key name (with case style and JsonNameAttribute already applied).</summary>
    JsonName: string;
    /// <summary>Cached property handler for fast Get/Set (avoids repeated RTTI lookups).</summary>
    Handler: IInterface;
    /// <summary>Fallback RTTI property reference (used when Handler is nil).</summary>
    Prop: TRttiProperty;
    /// <summary>Pre-classified serialization strategy.</summary>
    Kind: TSerializeKind;
    /// <summary>Whether this property is a SmartProp that needs unwrapping.</summary>
    IsSmartProp: Boolean;
    /// <summary>Whether the underlying type is a list (for tkClass/tkInterface).</summary>
    IsListType: Boolean;
    /// <summary>PTypeInfo of the property value type (after SmartProp unwrap).</summary>
    ValueTypeInfo: PTypeInfo;
    /// <summary>PTypeInfo of the list element type when the property is a list.</summary>
    ElementTypeInfo: PTypeInfo;
    /// <summary>Shared native kind for the list element when available.</summary>
    ElementNativeKind: TDextNativeKind;
    /// <summary>Indicates whether a list field owns its objects.</summary>
    ListOwnsObjects: Boolean;
    /// <summary>Physical field offset for direct scalar serialization when safe.</summary>
    DirectOffset: NativeInt;
    /// <summary>Native scalar kind associated with DirectOffset.</summary>
    DirectKind: TDextNativeKind;
    /// <summary>True when JSON can read this property without TValue/RTTI.</summary>
    UseDirect: Boolean;
    /// <summary>
    ///   Direct path on a Nullable: offset of its HasValue flag (a Boolean),
    ///   -1 when the property is not a Nullable. A Nullable without a value
    ///   is written as null, not as the inner default.
    /// </summary>
    HasValueOffset: NativeInt;
  end;
  PSerializationPlanItem = ^TSerializationPlanItem;

  TRecordPlanItem = record
    OriginalFieldName: string;
    CustomName: string;
    ResolvedNames: array[TCaseStyle, Boolean] of string;
    Field: TRttiField;
    Kind: TSerializeKind;
    IsSmartProp: Boolean;
    HasCustomFormat: Boolean;
    CustomFormat: string;
    ForceString: Boolean;
    ForceNumber: Boolean;
    FieldTypeInfo: PTypeInfo;
  end;
  PRecordPlanItem = ^TRecordPlanItem;

  TRecordPlan = record
    Items: TArray<TRecordPlanItem>;
    Count: Integer;
  end;
  PRecordPlan = ^TRecordPlan;

  /// <summary>
  ///   Complete serialization plan for a class type.
  ///   Built once per PTypeInfo, cached globally for reuse.
  /// </summary>
  TSerializationPlan = record
    Items: TArray<TSerializationPlanItem>;
    Count: Integer;
  end;
  PSerializationPlan = ^TSerializationPlan;

  /// <summary>
  ///   Internal class responsible for complex conversion logic.
  ///   Manages type mapping, RTTI, attributes, and List/Dictionary conversion.
  /// </summary>
  TDextSerializer = class
  private
    class var FPlanCache: TObject;  // TObjectDictionary<PTypeInfo, TObject> wrapping TSerializationPlan
    class var FPlanLock: TObject;   // TCriticalSection for thread-safe plan creation
    class var FRecordPlanCache: TObject; // TObjectDictionary<PTypeInfo, TObject> wrapping TRecordPlan
    class var FRecordPlanLock: TObject;  // TCriticalSection for thread-safe record plan creation
    class constructor Create;
    class destructor Destroy;
  private
    FSettings: TJsonSettings;
    function CreateInstanceForDeserialization(AType: PTypeInfo): TValue;
    function GetOrBuildPlan(AType: PTypeInfo): PSerializationPlan;
    function GetOrBuildRecordPlan(AType: PTypeInfo): PRecordPlan;
    function ResolveFieldName(Item: PRecordPlanItem): string;
    function SerializeObjectWithPlan(Obj: TObject; const Plan: TSerializationPlan): IDextJsonObject;
  protected
    function GetFieldName(AField: TRttiField): string;
    function GetRecordName(ARttiType: TRttiType): string;
    function SerializeRecord(const AValue: TValue): IDextJsonObject;
    function SerializeObject(const AValue: TValue): IDextJsonObject;
    function ShouldSkipField(AField: TRttiField; const AValue: TValue): Boolean;

    function JsonToValue(AJson: IDextJsonObject; AType: PTypeInfo): TValue;
    function ValueToJson(const AValue: TValue): IDextJsonObject;

    function DeserializeArray(AJson: IDextJsonArray; AType: PTypeInfo): TValue;
    function DeserializeList(AJson: IDextJsonArray; AType: PTypeInfo): TValue; overload;
    function DeserializeList(AJson: IDextJsonArray; AType: PTypeInfo; const AExisting: TValue): TValue; overload;
    function SerializeArray(const AValue: TValue): IDextJsonArray;
    function SerializeList(const AValue: TValue): IDextJsonArray;

    function IsListType(AType: PTypeInfo): Boolean;
    function IsArrayType(AType: PTypeInfo): Boolean;
    function IsDictionaryType(AType: PTypeInfo): Boolean;
    function GetListElementType(AType: PTypeInfo): PTypeInfo;
    function GetArrayElementType(AType: PTypeInfo): PTypeInfo;
    function GetDictionaryKeyType(AType: PTypeInfo): PTypeInfo;
    function GetDictionaryValueType(AType: PTypeInfo): PTypeInfo;
    function DeserializeDictionary(AJson: IDextJsonObject; AType: PTypeInfo): TValue;
    function ApplyCaseStyle(const AName: string): string;
  public
    constructor Create(const ASettings: TJsonSettings);
    function Deserialize<T>(const AJson: string): T;
    function DeserializeRecord(AJson: IDextJsonObject; AType: PTypeInfo): TValue;
    function DeserializeObject(AJson: IDextJsonObject; AType: PTypeInfo; AInstance: TObject = nil): TValue;
    function Serialize<T>(const AValue: T): string; overload;
    function Serialize(const AValue: TValue): string; overload;
    procedure Populate(AInstance: TObject; const AJson: string);
  end;

  /// <summary>
  ///   Fluent builder for programmatic construction of JSON objects and arrays.
  /// </summary>
  TJsonBuilder = class
  private
    type
      TBuilderNode = class
        NodeType: (ntObject, ntArray);
        Parent: TBuilderNode;
        Key: string;
        JsonObj: IDextJsonObject;
        JsonArr: IDextJsonArray;
      end;
  private
    FRoot: TBuilderNode;
    FCurrent: TBuilderNode;
    FNodeStack: IList<TBuilderNode>;
    function GetCurrentObject: IDextJsonObject;
    function GetCurrentArray: IDextJsonArray;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Adds a string value to the current object.</summary>
    function Add(const AKey, AValue: string): TJsonBuilder; overload;

    /// <summary>Adds an integer value to the current object.</summary>
    function Add(const AKey: string; AValue: Integer): TJsonBuilder; overload;

    /// <summary>Adds a 64-bit integer value to the current object.</summary>
    function Add(const AKey: string; AValue: Int64): TJsonBuilder; overload;

    /// <summary>Adds a floating-point value to the current object.</summary>
    function Add(const AKey: string; AValue: Double): TJsonBuilder; overload;

    /// <summary>Adds a boolean value to the current object.</summary>
    function Add(const AKey: string; AValue: Boolean): TJsonBuilder; overload;

    /// <summary>Starts a nested object with the given key.</summary>
    function AddObject(const AKey: string): TJsonBuilder;

    /// <summary>Ends the current nested object and returns to the parent.</summary>
    function EndObject: TJsonBuilder;

    /// <summary>Starts a nested array with the given key.</summary>
    function AddArray(const AKey: string): TJsonBuilder;

    /// <summary>Ends the current nested array and returns to the parent.</summary>
    function EndArray: TJsonBuilder;

    /// <summary>Adds a string value to the current array.</summary>
    function AddValue(const AValue: string): TJsonBuilder; overload;

    /// <summary>Adds an integer value to the current array.</summary>
    function AddValue(AValue: Integer): TJsonBuilder; overload;

    /// <summary>Adds a boolean value to the current array.</summary>
    function AddValue(AValue: Boolean): TJsonBuilder; overload;

    /// <summary>Returns the built JSON as a compact string.</summary>
    function ToString: string; override;

    /// <summary>Returns the built JSON as an indented string.</summary>
    function ToIndentedString: string;

    /// <summary>Creates a new JSON builder instance.</summary>
    class function NewBuilder: TJsonBuilder;
  end;

/// <summary>
///   Returns a default TJsonSettings instance for fluent configuration.
///   Usage: JsonDefaultSettings(JsonSettings.CamelCase.CaseInsensitive);
/// </summary>
function JsonSettings: TJsonSettings;

/// <summary>
///   Sets the default JSON settings globally. Shorthand for TDextJson.SetDefaultSettings.
///   Usage: JsonDefaultSettings(JsonSettings.CamelCase.CaseInsensitive);
/// </summary>
procedure JsonDefaultSettings(const ASettings: TJsonSettings);

implementation

uses
  System.Classes,
  System.DateUtils,
  System.Generics.Collections,
  System.SyncObjs,
  System.Variants,
  Dext.Core.Reflection,
  Dext.Core.DateUtils,
  Dext.Json.Utf8,
  Dext.Core.Json.NextGen; // Default driver NextGen

type
  TRecordCacheEntry = record
    TypeInfo: PTypeInfo;
    Plan: PRecordPlan;
  end;

  TClassCacheEntry = record
    TypeInfo: PTypeInfo;
    Plan: PSerializationPlan;
  end;

var
  GRecordPlanCache: array[0..15] of TRecordCacheEntry;
  GClassPlanCache: array[0..15] of TClassCacheEntry;
  GRecordCacheIdx: Integer = 0;
  GClassCacheIdx: Integer = 0;

const
  ValueField = 'value';

function FloatToJsonString(Value: Extended): string;
begin
  Result := FloatToStr(Value, TFormatSettings.Invariant);
end;

function JsonStringToFloat(const Value: string): Extended;
var
  CleanValue: string;
begin

  if Pos(',', Value) > 0 then
    CleanValue := StringReplace(Value, ',', '.', [rfReplaceAll])
  else
    CleanValue := Value;

  Result := StrToFloatDef(CleanValue, 0, TFormatSettings.Invariant);
end;

function IntToJsonString(Value: Int64): string;
begin
  Result := IntToStr(Value);
end;

function JsonStringToInt(const Value: string): Int64;
begin
  Result := StrToInt64Def(Value, 0);
end;

class function TDextJson.SerializeUtf8<T>(const AValue: T): TBytes;
begin
  Result := SerializeUtf8<T>(AValue, GetDefaultSettings);
end;

class function TDextJson.SerializeUtf8(const AValue: IInterface): TBytes;
begin
  Result := SerializeUtf8(TValue.From<IInterface>(AValue), GetDefaultSettings);
end;

class function TDextJson.SerializeUtf8<T>(const AValue: T; const ASettings: TJsonSettings): TBytes;
begin
  Result := SerializeUtf8(TValue.From<T>(AValue), ASettings);
end;


class function TDextJson.SerializeUtf8(const AValue: TValue): TBytes;
begin
  Result := SerializeUtf8(AValue, GetDefaultSettings);
end;

class function TDextJson.SerializeUtf8(const AValue: IInterface; const ASettings: TJsonSettings): TBytes;
begin
  Result := SerializeUtf8(TValue.From<IInterface>(AValue), ASettings);
end;

class function TDextJson.SerializeUtf8(const AValue: TValue; const ASettings: TJsonSettings): TBytes;
var
  Json: string;
  Obj: TObject;
begin
  if AValue.IsObject then
  begin
    Obj := AValue.AsObject;
    if Obj is TJsonBaseObject then
    begin
      Json := TJsonBaseObject(Obj).ToJson;
      Result := TEncoding.UTF8.GetBytes(Json);
      Exit;
    end;
  end;

  Json := Serialize(AValue, ASettings);
  Result := TEncoding.UTF8.GetBytes(Json);
end;

class procedure TDextJson.SerializeUtf8To(const AValue: TValue;
  AContext: Pointer; AWrite: TDextJsonWriteProc);
begin
  SerializeUtf8To(AValue, GetDefaultSettings, AContext, AWrite);
end;

class procedure TDextJson.SerializeUtf8To(const AValue: TValue;
  const ASettings: TJsonSettings; AContext: Pointer;
  AWrite: TDextJsonWriteProc);
var
  Writer: TUtf8JsonWriter;
begin
  if not Assigned(AWrite) then
    raise EArgumentNilException.Create('AWrite');
  Writer := TUtf8JsonWriter.Create(AContext, TUtf8WriteProc(AWrite), False);
  Writer.Settings := ASettings;
  Writer.WriteValue(AValue);
end;

{ TJsonUtils }

class function TJsonUtils.ToCamelCase(const S: string): string;
var
  C: Char;
begin
  if S.IsEmpty then Exit('');
  Result := S;
  C := Result[1];
  if (C >= 'A') and (C <= 'Z') then
    Result[1] := Chr(Ord(C) + 32)
  else
    Result[1] := LowerCase(C)[1];
end;

class function TJsonUtils.ToPascalCase(const S: string): string;
begin
  if S.Length > 0 then
    Result := UpperCase(S[1]) + Copy(S, 2, MaxInt)
  else
    Result := S;
end;

class function TJsonUtils.ToSnakeCase(const S: string): string;
var
  C: Char;
  i: Integer;
  SB: TStringBuilder;
begin
  if S.IsEmpty then Exit('');

  SB := TStringBuilder.Create;
  try
    for i := 0 to S.Length - 1 do
    begin
      C := S.Chars[i];
      if C.IsUpper then
      begin
        if i > 0 then
          SB.Append('_');
        SB.Append(C.ToLower);
      end
      else
        SB.Append(C);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TJsonUtils.ApplyCaseStyle(const S: string; Style: TCaseStyle): string;
begin
  case Style of
    TCaseStyle.CaseInherit,
    TCaseStyle.Unchanged: Result := S;
    TCaseStyle.CamelCase: Result := ToCamelCase(S);
    TCaseStyle.PascalCase: Result := ToPascalCase(S);
    TCaseStyle.SnakeCase: Result := ToSnakeCase(S);
  else
    Result := S;
  end;
end;

{ JsonNameAttribute }

constructor JsonNameAttribute.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

{ JsonFormatAttribute }

constructor JsonFormatAttribute.Create(const AFormat: string);
begin
  inherited Create;
  FFormat := AFormat;
end;

{ JsonSettings global function }

function JsonSettings: TJsonSettings;
begin
  Result := TJsonSettings.Default;
end;

{ JsonDefaultSettings global procedure }

procedure JsonDefaultSettings(const ASettings: TJsonSettings);
begin
  TDextJson.SetDefaultSettings(ASettings);
end;

{ TDextJson }

class function TDextJson.Deserialize<T>(const AJson: string): T;
begin
  Result := Deserialize<T>(AJson, GetDefaultSettings);
end;

class function TDextJson.Deserialize<T>(const AJson: string; const ASettings: TJsonSettings): T;
var
  Serializer: TDextSerializer;
begin
  Serializer := TDextSerializer.Create(ASettings);
  try
    Result := Serializer.Deserialize<T>(AJson);
  finally
    Serializer.Free;
  end;
end;

class function TDextJson.Deserialize(AType: PTypeInfo; const AJson: string): TValue;
begin
  // Use RTTI to call the appropriate generic method
  case AType.Kind of
    tkInteger:
      Result := TValue.From<Integer>(Deserialize<Integer>(AJson));
    tkInt64:
      Result := TValue.From<Int64>(Deserialize<Int64>(AJson));
    tkFloat:
      if (AType = TypeInfo(TDateTime)) or (AType = TypeInfo(TDate)) or (AType = TypeInfo(TTime)) then
        Result := TValue.From<TDateTime>(Deserialize<TDateTime>(AJson))
      else
        Result := TValue.From<Double>(Deserialize<Double>(AJson));
    tkString, tkLString, tkWString, tkUString:
      Result := TValue.From<string>(Deserialize<string>(AJson));
    tkEnumeration:
      if AType = TypeInfo(Boolean) then
        Result := TValue.From<Boolean>(Deserialize<Boolean>(AJson))
      else
        Result := TValue.FromOrdinal(AType, Deserialize<Integer>(AJson));
    tkRecord:
      Result := DeserializeRecord(AType, AJson);
    tkClass, tkDynArray:
      Result := Deserialize(AType, AJson, GetDefaultSettings);
    else
      raise EDextJsonException.CreateFmt('Unsupported type for deserialization: %s', [AType.NameFld.ToString]);
  end;
end;

class function TDextJson.Deserialize(AType: PTypeInfo; const AJson: string; const ASettings: TJsonSettings): TValue;
var
  JsonNode: IDextJsonNode;
  Serializer: TDextSerializer;
begin
  Serializer := TDextSerializer.Create(ASettings);
  try
    JsonNode := TDextJson.Provider.Parse(AJson);
    if JsonNode.GetNodeType = jntObject then
    begin
      if AType.Kind = tkRecord then
        Result := Serializer.DeserializeRecord(JsonNode as IDextJsonObject, AType)
      else if AType.Kind = tkClass then
        Result := Serializer.DeserializeObject(JsonNode as IDextJsonObject, AType)
      else
        raise EDextJsonException.CreateFmt('Unsupported type for deserialization with settings: %s', [AType.NameFld.ToString]);
    end
    else if JsonNode.GetNodeType = jntArray then
    begin
      if Serializer.IsArrayType(AType) then
        Result := Serializer.DeserializeArray(JsonNode as IDextJsonArray, AType)
      else if Serializer.IsListType(AType) then
        Result := Serializer.DeserializeList(JsonNode as IDextJsonArray, AType)
      else
        raise EDextJsonException.Create('JSON is an array but target type is not array/list');
    end
    else
      raise EDextJsonException.Create('JSON root must be Object or Array');
  finally
    Serializer.Free;
  end;
end;

class function TDextJson.DeserializeRecord(AType: PTypeInfo; const AJson: string): TValue;
var
  JsonNode: IDextJsonNode;
  Serializer: TDextSerializer;
begin
  Serializer := TDextSerializer.Create(GetDefaultSettings);
  try
    JsonNode := TDextJson.Provider.Parse(AJson);
    if JsonNode.GetNodeType = jntObject then
      Result := Serializer.DeserializeRecord(JsonNode as IDextJsonObject, AType)
    else
      raise EDextJsonException.Create('JSON root must be Object for record deserialization');
  finally
    Serializer.Free;
  end;
end;

class function TDextJson.Serialize<T>(const AValue: T): string;
begin
  Result := Serialize<T>(AValue, GetDefaultSettings);
end;

class function TDextJson.Serialize<T>(const AValue: T; const ASettings: TJsonSettings): string;
var
  Serializer: TDextSerializer;
begin
  Serializer := TDextSerializer.Create(ASettings);
  try
    Result := Serializer.Serialize<T>(AValue);
  finally
    Serializer.Free;
  end;
end;

class function TDextJson.Serialize(const AValue: TValue): string;
begin
  Result := Serialize(AValue, GetDefaultSettings);
end;

class function TDextJson.Serialize(const AValue: TValue; const ASettings: TJsonSettings): string;
var
  Serializer: TDextSerializer;
begin
  Serializer := TDextSerializer.Create(ASettings);
  try
    Result := Serializer.Serialize(AValue);
  finally
    Serializer.Free;
  end;
end;

function GetUUIDString(const V: TValue): string;
var
  U: TUUID;
begin
  V.ExtractRawData(@U);
  Result := U.ToString;
end;

function GetGUIDString(const V: TValue): string;
var
  G: TGUID;
begin
  V.ExtractRawData(@G);
  Result := GUIDToString(G);
end;

{ TDextSerializer }

type
  /// <summary>
  ///   Wrapper object to store a TSerializationPlan inside TObjectDictionary.
  /// </summary>
  TSerializationPlanHolder = class
  public
    Plan: TSerializationPlan;
  end;

  TRecordPlanHolder = class
  public
    Plan: TRecordPlan;
  end;

class constructor TDextSerializer.Create;
begin
  FPlanCache := TObjectDictionary<PTypeInfo, TSerializationPlanHolder>.Create([doOwnsValues]);
  FPlanLock := TCriticalSection.Create;
  FRecordPlanCache := TObjectDictionary<PTypeInfo, TRecordPlanHolder>.Create([doOwnsValues]);
  FRecordPlanLock := TCriticalSection.Create;
end;

class destructor TDextSerializer.Destroy;
begin
  FreeAndNil(FPlanCache);
  FreeAndNil(FPlanLock);
  FreeAndNil(FRecordPlanCache);
  FreeAndNil(FRecordPlanLock);
end;

function TDextSerializer.GetOrBuildPlan(AType: PTypeInfo): PSerializationPlan;
var
  Cache: TObjectDictionary<PTypeInfo, TSerializationPlanHolder>;
  Lock: TCriticalSection;
  Holder: TSerializationPlanHolder;
  RttiType: TRttiType;
  Props: TArray<TRttiProperty>;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  I, ItemCount: Integer;
  ShouldSkip: Boolean;
  PropName: string;
  LTypeInfo: PTypeInfo;
  LTypeKind: TTypeKind;
  Item: TSerializationPlanItem;
  Idx: Integer;
  TypePlan: IDextTypeCodecPlan;
  TypeFields: TArray<TDextFieldPlan>;
  TypeField: TDextFieldPlan;
  SmartMeta: TTypeMetadata;
  BackingField: TRttiField;
  PublishedOnly: Boolean;
  Base: TRttiType;
begin
  // Lock-free slot cache lookup
  for I := 0 to 15 do
  begin
    if GClassPlanCache[I].TypeInfo = AType then
      Exit(GClassPlanCache[I].Plan);
  end;

  Cache := TObjectDictionary<PTypeInfo, TSerializationPlanHolder>(FPlanCache);
  Lock := TCriticalSection(FPlanLock);

  // Fast path: plan already exists (lock-free read)
  Lock.Enter;
  try
    if Cache.TryGetValue(AType, Holder) then
    begin
      Result := @Holder.Plan;
      
      // Update lock-free cache slot
      Idx := TInterlocked.Increment(GClassCacheIdx) and 15;
      GClassPlanCache[Idx].TypeInfo := AType;
      GClassPlanCache[Idx].Plan := Result;
      
      Exit;
    end;
  finally
    Lock.Leave;
  end;

  // Slow path: build plan
  RttiType := TReflection.GetMetadata(AType).RttiType;
  Props := RttiType.GetProperties;
  TypePlan := TDextTypeModel.GetPlan(AType);
  if TypePlan <> nil then
    TypeFields := TypePlan.GetFields
  else
    TypeFields := nil;

  Holder := TSerializationPlanHolder.Create;
  SetLength(Holder.Plan.Items, Length(Props));
  ItemCount := 0;

  // [JsonPublishedOnly] on the class or on an ancestor
  PublishedOnly := False;
  Base := RttiType;
  while (Base <> nil) and not PublishedOnly do
  begin
    for Attr in Base.GetAttributes do
      if Attr is JsonPublishedOnlyAttribute then
        PublishedOnly := True;
    Base := Base.BaseType;
  end;

  for I := 0 to High(Props) do
  begin
    Prop := Props[I];

    // Skip non-public/published properties
    if (Prop.Visibility <> mvPublic) and (Prop.Visibility <> mvPublished) then
      Continue;
    if PublishedOnly and (Prop.Visibility <> mvPublished) then
      Continue;

    // Skip TObject/TInterfacedObject internals
    if (Prop.Parent <> nil) and
       ((Prop.Parent.Name = 'TObject') or (Prop.Parent.Name = 'TInterfacedObject')) then
      Continue;

    // Skip if has JsonIgnore attribute
    ShouldSkip := False;
    for Attr in Prop.GetAttributes do
    begin
      if (Attr is JsonIgnoreAttribute) or (Attr.ClassName = 'NotMappedAttribute') then
      begin
        ShouldSkip := True;
        Break;
      end;
    end;
    if ShouldSkip then
      Continue;

    // Determine JSON name
    PropName := ApplyCaseStyle(Prop.Name);
    for Attr in Prop.GetAttributes do
      if Attr is JsonNameAttribute then
      begin
        PropName := JsonNameAttribute(Attr).Name;
        Break;
      end;

    Item := Default(TSerializationPlanItem);
    Item.JsonName := PropName;
    Item.Prop := Prop;
    Item.Handler := TReflection.GetHandler(AType, Prop.Name);
    Item.DirectOffset := -1;
    Item.DirectKind := nkUnknown;
    Item.ElementTypeInfo := nil;
    Item.ElementNativeKind := nkUnknown;
    Item.ListOwnsObjects := False;
    Item.UseDirect := False;
    Item.HasValueOffset := -1;

    for TypeField in TypeFields do
    begin
      if SameText(TypeField.Name, Prop.Name) and
         (TypeField.AccessMode = amDirectField) and
         (TypeField.Offset >= 0) and
         (TDextTypeModel.IsDirectKind(TypeField.NativeKind) or
          TDextTypeModel.IsDirectReferenceKind(TypeField.NativeKind)) then
      begin
        Item.DirectOffset := TypeField.Offset;
        Item.DirectKind := TypeField.NativeKind;
        Item.UseDirect := True;
        Break;
      end;
    end;

    // Determine the type info for classification
    if Prop.PropertyType <> nil then
    begin
      LTypeInfo := Prop.PropertyType.Handle;
      LTypeKind := Prop.PropertyType.TypeKind;
    end
    else
    begin
      LTypeInfo := nil;
      LTypeKind := tkUnknown;
    end;

    // Check for SmartProp
    Item.IsSmartProp := (LTypeKind = tkRecord) and (LTypeInfo <> nil) and
                         TReflection.IsSmartProp(LTypeInfo);

    if Item.IsSmartProp then
    begin
      SmartMeta := TReflection.GetMetadata(LTypeInfo);
      if (SmartMeta <> nil) and (SmartMeta.ValueField <> nil) then
      begin
        if not Item.UseDirect then
        begin
          BackingField := RttiType.GetField('F' + Prop.Name);
          if (BackingField <> nil) and (SmartMeta.InnerType <> nil) then
          begin
            Item.DirectKind := TDextTypeModel.NativeKindOf(SmartMeta.InnerType);
            if TDextTypeModel.IsDirectKind(Item.DirectKind) or
               TDextTypeModel.IsDirectReferenceKind(Item.DirectKind) then
            begin
              Item.DirectOffset := BackingField.Offset;
              Item.UseDirect := True;
            end;
          end;
        end;

        // A Nullable read straight at its value would turn "no value" into
        // the inner default (0, ''): the direct path also needs its HasValue
        // flag. When that flag is not a Boolean the property stays on the
        // RTTI path, which already checks HasValue (TryUnwrapProp).
        if Item.UseDirect and SmartMeta.IsNullable then
        begin
          if (SmartMeta.HasValueField <> nil) and
             (SmartMeta.HasValueField.FieldType <> nil) and
             (SmartMeta.HasValueField.FieldType.Handle = TypeInfo(Boolean)) then
            Item.HasValueOffset := Item.DirectOffset + SmartMeta.HasValueField.Offset
          else
            Item.UseDirect := False;
        end;

        if Item.UseDirect then
          Item.DirectOffset := Item.DirectOffset + SmartMeta.ValueField.Offset;
      end
      else
        Item.UseDirect := False;
    end;
    // If SmartProp, classify by inner type
    if Item.IsSmartProp then
    begin
      LTypeInfo := TReflection.GetUnderlyingType(LTypeInfo);
      if LTypeInfo <> nil then
        LTypeKind := LTypeInfo.Kind
      else
        LTypeKind := tkUnknown;
    end;

    Item.ValueTypeInfo := LTypeInfo;

    // Check if it's a list type
    Item.IsListType := (LTypeKind in [tkClass, tkInterface]) and (LTypeInfo <> nil) and
                        IsListType(LTypeInfo);
    if Item.IsListType then
    begin
      Item.ElementTypeInfo := GetListElementType(LTypeInfo);
      Item.ElementNativeKind := TDextTypeModel.NativeKindOf(Item.ElementTypeInfo);
      Item.ListOwnsObjects := (Item.ElementNativeKind = nkObject) and
        (Item.ElementTypeInfo <> nil) and (Item.ElementTypeInfo.Kind = tkClass);
    end;

    // Classify serialization kind
    case LTypeKind of
      tkInteger, tkInt64:
        Item.Kind := skInteger;
      tkFloat:
        begin
          if (LTypeInfo = TypeInfo(TDateTime)) or (LTypeInfo = TypeInfo(TDate)) or
             (LTypeInfo = TypeInfo(TTime)) then
            Item.Kind := skDateTime
          else
            Item.Kind := skFloat;
        end;
      tkString, tkLString, tkWString, tkUString:
        Item.Kind := skString;
      tkEnumeration:
        begin
          if LTypeInfo = TypeInfo(Boolean) then
            Item.Kind := skBoolean
          else
            Item.Kind := skEnumAsString;
        end;
      tkRecord:
        begin
          if LTypeInfo = TypeInfo(TGUID) then
            Item.Kind := skRecordGUID
          else if LTypeInfo = TypeInfo(TUUID) then
            Item.Kind := skRecordUUID
          else
            Item.Kind := skRecord;
        end;
      tkClass:
        begin
          if Item.IsListType then
            Item.Kind := skList
          else
            Item.Kind := skClass;
        end;
      tkInterface:
        begin
          if Item.IsListType then
            Item.Kind := skList
          else
            Item.Kind := skInterface;
        end;
      tkDynArray:
        Item.Kind := skDynArray;
    else
      Item.Kind := skUnknown;
    end;

    Holder.Plan.Items[ItemCount] := Item;
    Inc(ItemCount);
  end;

  Holder.Plan.Count := ItemCount;
  SetLength(Holder.Plan.Items, ItemCount);

  // Store in cache
  Lock.Enter;
  try
    if not Cache.ContainsKey(AType) then
      Cache.Add(AType, Holder)
    else
    begin
      // Another thread built it first - use theirs
      Holder.Free;
      Cache.TryGetValue(AType, Holder);
    end;
  finally
    Lock.Leave;
  end;

  Result := @Holder.Plan;
  Idx := TInterlocked.Increment(GClassCacheIdx) and 15;
  GClassPlanCache[Idx].TypeInfo := AType;
  GClassPlanCache[Idx].Plan := Result;
end;

function TDextSerializer.ResolveFieldName(Item: PRecordPlanItem): string;
begin
  if Item^.CustomName <> '' then
    Exit(Item^.CustomName);

  Result := Item^.ResolvedNames[FSettings.CaseStyle, FSettings.FSmartRecordMapping];
end;

function TDextSerializer.GetOrBuildRecordPlan(AType: PTypeInfo): PRecordPlan;
var
  Cache: TObjectDictionary<PTypeInfo, TRecordPlanHolder>;
  Lock: TCriticalSection;
  Holder: TRecordPlanHolder;
  RttiType: TRttiType;
  Fields: TArray<TRttiField>;
  Field: TRttiField;
  Attr: TCustomAttribute;
  I, ItemCount: Integer;
  LTypeInfo: PTypeInfo;
  LTypeKind: TTypeKind;
  Item: TRecordPlanItem;
  ShouldSkip: Boolean;
  Style: TCaseStyle;
  SmartMap: Boolean;
  NameStr: string;
  Idx: Integer;
begin
  // Lock-free slot cache lookup
  for I := 0 to 15 do
  begin
    if GRecordPlanCache[I].TypeInfo = AType then
      Exit(GRecordPlanCache[I].Plan);
  end;

  Cache := TObjectDictionary<PTypeInfo, TRecordPlanHolder>(FRecordPlanCache);
  Lock := TCriticalSection(FRecordPlanLock);

  // Fast path
  Lock.Enter;
  try
    if Cache.TryGetValue(AType, Holder) then
    begin
      Result := @Holder.Plan;
      
      // Update lock-free cache slot
      Idx := TInterlocked.Increment(GRecordCacheIdx) and 15;
      GRecordPlanCache[Idx].TypeInfo := AType;
      GRecordPlanCache[Idx].Plan := Result;
      
      Exit;
    end;
  finally
    Lock.Leave;
  end;

  // Slow path
  RttiType := TReflection.GetMetadata(AType).RttiType;
  Fields := RttiType.GetFields;

  Holder := TRecordPlanHolder.Create;
  SetLength(Holder.Plan.Items, Length(Fields));
  ItemCount := 0;

  for I := 0 to High(Fields) do
  begin
    Field := Fields[I];

    // Check if has JsonIgnore attribute
    ShouldSkip := False;
    for Attr in Field.GetAttributes do
    begin
      if (Attr is JsonIgnoreAttribute) or (Attr.ClassName = 'NotMappedAttribute') then
      begin
        ShouldSkip := True;
        Break;
      end;
    end;
    if ShouldSkip then
      Continue;

    Item := Default(TRecordPlanItem);
    Item.OriginalFieldName := Field.Name;
    Item.Field := Field;
    Item.CustomName := '';
    Item.ForceString := False;
    Item.ForceNumber := False;
    Item.HasCustomFormat := False;
    Item.CustomFormat := '';

    for Attr in Field.GetAttributes do
    begin
      if Attr is JsonNameAttribute then
      begin
        Item.CustomName := JsonNameAttribute(Attr).Name;
      end
      else if Attr is JsonFormatAttribute then
      begin
        Item.HasCustomFormat := True;
        Item.CustomFormat := JsonFormatAttribute(Attr).Format;
      end
      else if Attr is JsonStringAttribute then
      begin
        Item.ForceString := True;
      end
      else if Attr is JsonNumberAttribute then
      begin
        Item.ForceNumber := True;
      end;
    end;

    // Pre-resolve names for all case styles and smart mapping flags
    if Item.CustomName = '' then
    begin
      for Style := Low(TCaseStyle) to High(TCaseStyle) do
      begin
        for SmartMap := False to True do
        begin
          NameStr := Item.OriginalFieldName;
          if SmartMap and (NameStr.Length > 1) and (NameStr.Chars[0] = 'F') then
            NameStr := NameStr.Substring(1);
          
          Item.ResolvedNames[Style, SmartMap] := TJsonUtils.ApplyCaseStyle(NameStr, Style);
        end;
      end;
    end;

    if Field.FieldType <> nil then
    begin
      LTypeInfo := Field.FieldType.Handle;
      LTypeKind := Field.FieldType.TypeKind;
    end
    else
    begin
      LTypeInfo := nil;
      LTypeKind := tkUnknown;
    end;

    // Check for SmartProp
    Item.IsSmartProp := (LTypeKind = tkRecord) and (LTypeInfo <> nil) and
                         TReflection.IsSmartProp(LTypeInfo);

    if Item.IsSmartProp then
    begin
      LTypeInfo := TReflection.GetUnderlyingType(LTypeInfo);
      if LTypeInfo <> nil then
        LTypeKind := LTypeInfo.Kind
      else
        LTypeKind := tkUnknown;
    end;

    Item.FieldTypeInfo := LTypeInfo;

    // Classify serialization kind
    case LTypeKind of
      tkInteger, tkInt64:
        Item.Kind := skInteger;
      tkFloat:
        begin
          if (LTypeInfo = TypeInfo(TDateTime)) or (LTypeInfo = TypeInfo(TDate)) or
             (LTypeInfo = TypeInfo(TTime)) then
            Item.Kind := skDateTime
          else
            Item.Kind := skFloat;
        end;
      tkString, tkLString, tkWString, tkUString:
        Item.Kind := skString;
      tkEnumeration:
        begin
          if LTypeInfo = TypeInfo(Boolean) then
            Item.Kind := skBoolean
          else
            Item.Kind := skEnumAsString;
        end;
      tkRecord:
        begin
          if LTypeInfo = TypeInfo(TGUID) then
            Item.Kind := skRecordGUID
          else if LTypeInfo = TypeInfo(TUUID) then
            Item.Kind := skRecordUUID
          else
            Item.Kind := skRecord;
        end;
      tkClass, tkInterface:
        begin
          if IsListType(LTypeInfo) then
            Item.Kind := skList
          else if (LTypeKind = tkClass) then
            Item.Kind := skClass
          else
            Item.Kind := skInterface;
        end;
      tkDynArray:
        Item.Kind := skDynArray;
    else
      Item.Kind := skUnknown;
    end;

    Holder.Plan.Items[ItemCount] := Item;
    Inc(ItemCount);
  end;

  Holder.Plan.Count := ItemCount;
  SetLength(Holder.Plan.Items, ItemCount);

  // Store in cache
  Lock.Enter;
  try
    if not Cache.ContainsKey(AType) then
      Cache.Add(AType, Holder)
    else
    begin
      // Another thread built it first
      Holder.Free;
      Cache.TryGetValue(AType, Holder);
    end;
  finally
    Lock.Leave;
  end;

  Result := @Holder.Plan;
  Idx := TInterlocked.Increment(GRecordCacheIdx) and 15;
  GRecordPlanCache[Idx].TypeInfo := AType;
  GRecordPlanCache[Idx].Plan := Result;
end;

function TDextSerializer.SerializeObjectWithPlan(Obj: TObject; const Plan: TSerializationPlan): IDextJsonObject;
var
  I: Integer;
  Item: PSerializationPlanItem;
  PropValue: TValue;
  Unwrapped: TValue;
  NestedObj: TObject;
  NestedIntf: IInterface;
  Defaults: Boolean;
begin
  Result := TDextJson.Provider.CreateObject;
  if Obj = nil then Exit;

  // IgnoreDefaultValues and ZeroDateAsNull: checked only when one is on, so
  // the default path pays nothing.
  Defaults := FSettings.IgnoreDefaultValues or FSettings.FZeroDateAsNull;

  for I := 0 to Plan.Count - 1 do
  begin
    Item := @Plan.Items[I];

    if Item^.UseDirect then
    begin
      // A Nullable without a value: null, like the RTTI path below.
      if (Item^.HasValueOffset >= 0) and
         not TDextDirectAccess.ReadBoolean(Obj, Item^.HasValueOffset) then
      begin
        if not FSettings.FIgnoreNullValues then
          Result.SetNull(Item^.JsonName);
        Continue;
      end;

      if Defaults then
        case Item^.DirectKind of
          nkInt32:
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadInt32(Obj, Item^.DirectOffset) = 0) then
              Continue;
          nkInt64:
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadInt64(Obj, Item^.DirectOffset) = 0) then
              Continue;
          nkBoolean:
            if FSettings.IgnoreDefaultValues and
              not TDextDirectAccess.ReadBoolean(Obj, Item^.DirectOffset) then
              Continue;
          nkSingle:
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadSingle(Obj, Item^.DirectOffset) = 0) then
              Continue;
          nkCurrency:
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadCurrency(Obj, Item^.DirectOffset) = 0) then
              Continue;
          nkDouble:
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset) = 0) then
              Continue;
          nkString:
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadString(Obj, Item^.DirectOffset) = '') then
              Continue;
          nkDateTime:
            if TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset) = 0 then
            begin
              if FSettings.IgnoreDefaultValues then
                Continue;
              if FSettings.FZeroDateAsNull then
              begin
                if not FSettings.FIgnoreNullValues then
                  Result.SetNull(Item^.JsonName);
                Continue;
              end;
            end;
        end;

      case Item^.DirectKind of
        nkInt32:
          Result.SetInt64(Item^.JsonName, TDextDirectAccess.ReadInt32(Obj, Item^.DirectOffset));
        nkInt64:
          Result.SetInt64(Item^.JsonName, TDextDirectAccess.ReadInt64(Obj, Item^.DirectOffset));
        nkBoolean:
          Result.SetBoolean(Item^.JsonName, TDextDirectAccess.ReadBoolean(Obj, Item^.DirectOffset));
        nkSingle:
          Result.SetDouble(Item^.JsonName, TDextDirectAccess.ReadSingle(Obj, Item^.DirectOffset));
        nkCurrency:
          Result.SetDouble(Item^.JsonName, TDextDirectAccess.ReadCurrency(Obj, Item^.DirectOffset));
        nkDouble:
          Result.SetDouble(Item^.JsonName, TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset));
        nkDateTime:
          Result.SetString(Item^.JsonName, FormatDateTime(FSettings.DateFormat,
            TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset)));
        nkString:
          Result.SetString(Item^.JsonName, TDextDirectAccess.ReadString(Obj, Item^.DirectOffset));
        nkGuid:
          Result.SetString(Item^.JsonName, GUIDToString(TDextDirectAccess.ReadGUID(Obj, Item^.DirectOffset)));
        nkUuid:
          Result.SetString(Item^.JsonName, TDextDirectAccess.ReadUUID(Obj, Item^.DirectOffset).ToString);
        nkObject:
          begin
            if (Item^.ValueTypeInfo <> nil) and (Item^.ValueTypeInfo.Kind = tkClass) then
            begin
              NestedObj := TDextDirectAccess.ReadObject(Obj, Item^.DirectOffset);
              if NestedObj = nil then
                Result.SetNull(Item^.JsonName)
              else
                Result.SetObject(Item^.JsonName, SerializeObject(TValue.From<TObject>(NestedObj)));
            end
            else
              Result.SetNull(Item^.JsonName);
          end;
        nkList:
          begin
            if (Item^.ValueTypeInfo <> nil) and (Item^.ValueTypeInfo.Kind = tkClass) then
            begin
              NestedObj := TDextDirectAccess.ReadObject(Obj, Item^.DirectOffset);
              if NestedObj = nil then
                Result.SetNull(Item^.JsonName)
              else
              begin
                TValue.Make(@NestedObj, NestedObj.ClassInfo, PropValue);
                Result.SetArray(Item^.JsonName, SerializeList(PropValue));
              end;
            end
            else if (Item^.ValueTypeInfo <> nil) and (Item^.ValueTypeInfo.Kind = tkInterface) then
            begin
              NestedIntf := TDextDirectAccess.ReadInterface(Obj, Item^.DirectOffset);
              if NestedIntf = nil then
                Result.SetNull(Item^.JsonName)
              else
              begin
                TValue.Make(@NestedIntf, Item^.ValueTypeInfo, PropValue);
                Result.SetArray(Item^.JsonName, SerializeList(PropValue));
              end;
            end
            else
              Result.SetNull(Item^.JsonName);
          end;
      end;
      Continue;
    end;
    // Get property value (handler is faster than RTTI GetProperty)
    if Item^.Handler <> nil then
      PropValue := (Item^.Handler as IPropertyHandler).GetValue(Pointer(Obj))
    else
      PropValue := Item^.Prop.GetValue(Pointer(Obj));

    // Unwrap SmartProp if needed
    if Item^.IsSmartProp then
    begin
      if TReflection.TryUnwrapProp(PropValue, Unwrapped) then
        PropValue := Unwrapped;
    end;

    // Handle null/empty values
    if PropValue.IsEmpty then
    begin
      if not FSettings.FIgnoreNullValues then
        Result.SetNull(Item^.JsonName);
      Continue;
    end;

    // Default values and the zero date (same rules as ShouldSkipField for
    // fields; a TTime of 0 is midnight, not "no date").
    if Defaults then
      case Item^.Kind of
        skInteger:
          if FSettings.IgnoreDefaultValues and (PropValue.AsInt64 = 0) then
            Continue;
        skFloat:
          if FSettings.IgnoreDefaultValues and (PropValue.AsExtended = 0) then
            Continue;
        skString:
          if FSettings.IgnoreDefaultValues and (PropValue.AsString = '') then
            Continue;
        skBoolean:
          if FSettings.IgnoreDefaultValues and not PropValue.AsBoolean then
            Continue;
        skEnumAsString, skEnumAsNumber:
          if FSettings.IgnoreDefaultValues and not FSettings.FKeepDefaultEnums and
            (PropValue.AsOrdinal = 0) then
            Continue;
        skDateTime:
          if PropValue.AsExtended = 0 then
          begin
            if FSettings.IgnoreDefaultValues then
              Continue;
            if FSettings.FZeroDateAsNull and (Item^.ValueTypeInfo <> TypeInfo(TTime)) then
            begin
              if not FSettings.FIgnoreNullValues then
                Result.SetNull(Item^.JsonName);
              Continue;
            end;
          end;
      end;

    // Dispatch based on pre-computed kind
    case Item^.Kind of
      skInteger:
        Result.SetInt64(Item^.JsonName, PropValue.AsInt64);
      skFloat:
        Result.SetDouble(Item^.JsonName, PropValue.AsExtended);
      skDateTime:
        Result.SetString(Item^.JsonName, FormatDateTime(FSettings.DateFormat, PropValue.AsExtended));
      skString:
        Result.SetString(Item^.JsonName, PropValue.AsString);
      skBoolean:
        Result.SetBoolean(Item^.JsonName, PropValue.AsBoolean);
      skEnumAsString:
        Result.SetString(Item^.JsonName, GetEnumName(Item^.ValueTypeInfo, PropValue.AsOrdinal));
      skEnumAsNumber:
        Result.SetInt64(Item^.JsonName, PropValue.AsOrdinal);
      skRecordGUID:
        Result.SetString(Item^.JsonName, GetGUIDString(PropValue));
      skRecordUUID:
        Result.SetString(Item^.JsonName, GetUUIDString(PropValue));
      skRecord:
        Result.SetObject(Item^.JsonName, SerializeRecord(PropValue));
      skClass:
        begin
          if PropValue.AsObject = nil then
            Result.SetNull(Item^.JsonName)
          else
            Result.SetObject(Item^.JsonName, SerializeObject(PropValue));
        end;
      skList:
        Result.SetArray(Item^.JsonName, SerializeList(PropValue));
      skDynArray:
        Result.SetArray(Item^.JsonName, SerializeArray(PropValue));
      skInterface:
        Result.SetNull(Item^.JsonName);
    end;
  end;
end;

constructor TDextSerializer.Create(const ASettings: TJsonSettings);
begin
  inherited Create;
  FSettings := ASettings;
end;

function TDextSerializer.CreateInstanceForDeserialization(AType: PTypeInfo): TValue;
begin
  if FSettings.FServiceProvider <> nil then
    Result := TActivator.CreateInstance(FSettings.FServiceProvider, AType)
  else
    Result := TActivator.CreateInstanceRttiOnly(AType);
end;

function TDextSerializer.Deserialize<T>(const AJson: string): T;
var
  JsonNode: IDextJsonNode;
  Value: TValue;
begin
  JsonNode := TDextJson.Provider.Parse(AJson);
  try
    if JsonNode.GetNodeType = jntObject then
      Value := JsonToValue(JsonNode as IDextJsonObject, TypeInfo(T))
    else if JsonNode.GetNodeType = jntArray then
    begin
      // Handle root array deserialization
      if IsArrayType(TypeInfo(T)) then
        Value := DeserializeArray(JsonNode as IDextJsonArray, TypeInfo(T))
      else if IsListType(TypeInfo(T)) then
        Value := DeserializeList(JsonNode as IDextJsonArray, TypeInfo(T))
      else
        raise EDextJsonException.Create('JSON is an array but target type is not array/list');
    end
    else
      raise EDextJsonException.Create('JSON root must be Object or Array');

    Result := Value.AsType<T>;
  finally
    // Interface reference counting handles destruction
  end;
end;

function TDextSerializer.DeserializeObject(AJson: IDextJsonObject; AType: PTypeInfo; AInstance: TObject): TValue;
var
  ActualPropName: string;
  Attr: TCustomAttribute;
  Found: Boolean;
  Handler: IPropertyHandler;
  I: Integer;
  Instance: TObject;
  Key: string;
  LowerProp: string;
  Node: IDextJsonNode;
  Prop: TRttiProperty;
  PropName: string;
  RttiType: TRttiType;
  Val: TValue;
  ExistingPropVal: TValue;
  ExistingObj: TObject;
  ExistingIntf: IInterface;
  TypePlan: IDextTypeCodecPlan;
  TypeFields: TArray<TDextFieldPlan>;
  TypeField: TDextFieldPlan;
  DirectField: TDextFieldPlan;
  DirectFound: Boolean;
begin
  if AJson = nil then
    Exit(TValue.Empty);

  if AInstance <> nil then
  begin
    Instance := AInstance;
    Result := Instance;
  end
  else
  begin
    Result := CreateInstanceForDeserialization(AType);
    Instance := Result.AsObject;
  end;

  if Instance = nil then
    Exit;

  RttiType := TReflection.GetMetadata(AType).RttiType;
  TypePlan := TDextTypeModel.GetPlan(AType);
  if TypePlan <> nil then
    TypeFields := TypePlan.GetFields
  else
    TypeFields := nil;
  try
    for Prop in RttiType.GetProperties do
    begin
      if (Prop.Visibility <> mvPublic) and (Prop.Visibility <> mvPublished) then
        Continue;

      if not Prop.IsWritable then
        Continue;

      PropName := ApplyCaseStyle(Prop.Name);

      // Check JsonName
      for Attr in Prop.GetAttributes do
        if Attr is JsonNameAttribute then
        begin
          PropName := JsonNameAttribute(Attr).Name;
          Break;
        end;

      ActualPropName := PropName;
      Found := AJson.Contains(PropName);

      if (not Found) and FSettings.FCaseInsensitive then
      begin
         // Simple scan
        LowerProp := LowerCase(PropName);
        for I := 0 to AJson.GetCount - 1 do
        begin
          Key := AJson.GetName(I);
          if LowerCase(Key) = LowerProp then
          begin
            ActualPropName := Key;
            Found := True;
            Break;
          end;
        end;
      end;

      if not Found then
        Continue;

      Node := AJson.GetNode(ActualPropName);
      if Node <> nil then
      begin
        ExistingPropVal := TValue.Empty;
        ExistingIntf := nil;
        DirectFound := False;
        DirectField := Default(TDextFieldPlan);
        for TypeField in TypeFields do
        begin
          if SameText(TypeField.Name, Prop.Name) and
             (TypeField.AccessMode = amDirectField) and
             (TypeField.Offset >= 0) and
             (TDextTypeModel.IsDirectKind(TypeField.NativeKind) or
              TDextTypeModel.IsDirectReferenceKind(TypeField.NativeKind)) then
          begin
            DirectField := TypeField;
            DirectFound := True;
            Break;
          end;
        end;

        if DirectFound then
        begin
          case DirectField.NativeKind of
            nkInt32:
              if Node.GetNodeType = jntNumber then
              begin
                TDextDirectAccess.WriteInt32(Instance, DirectField.Offset, Integer(Node.AsInt64));
                Continue;
              end;
            nkInt64:
              if Node.GetNodeType = jntNumber then
              begin
                TDextDirectAccess.WriteInt64(Instance, DirectField.Offset, Node.AsInt64);
                Continue;
              end;
            nkBoolean:
              if Node.GetNodeType = jntBoolean then
              begin
                TDextDirectAccess.WriteBoolean(Instance, DirectField.Offset, Node.AsBoolean);
                Continue;
              end;
            nkSingle:
              if Node.GetNodeType = jntNumber then
              begin
                TDextDirectAccess.WriteSingle(Instance, DirectField.Offset, Node.AsDouble);
                Continue;
              end;
            nkCurrency:
              if Node.GetNodeType = jntNumber then
              begin
                TDextDirectAccess.WriteCurrency(Instance, DirectField.Offset, Currency(Node.AsDouble));
                Continue;
              end;
            nkDouble:
              if Node.GetNodeType = jntNumber then
              begin
                TDextDirectAccess.WriteDouble(Instance, DirectField.Offset, Node.AsDouble);
                Continue;
              end;
            nkDateTime:
              if Node.GetNodeType = jntString then
              begin
                TDextDirectAccess.WriteDouble(Instance, DirectField.Offset, ISO8601ToDate(Node.AsString));
                Continue;
              end
              else if Node.GetNodeType = jntNumber then
              begin
                TDextDirectAccess.WriteDouble(Instance, DirectField.Offset, Node.AsDouble);
                Continue;
              end;
            nkString:
              if Node.GetNodeType = jntString then
              begin
                TDextDirectAccess.WriteString(Instance, DirectField.Offset, Node.AsString);
                Continue;
              end;
            nkGuid:
              if Node.GetNodeType = jntString then
              begin
                TDextDirectAccess.WriteGUID(Instance, DirectField.Offset, StringToGUID(Node.AsString));
                Continue;
              end;
            nkUuid:
              if Node.GetNodeType = jntString then
              begin
                TDextDirectAccess.WriteUUID(Instance, DirectField.Offset, TUUID.FromString(Node.AsString));
                Continue;
              end;
            nkObject:
              if (Node.GetNodeType = jntObject) and (DirectField.TypeInfo <> nil) and
                 (DirectField.TypeInfo.Kind = tkClass) then
              begin
                ExistingObj := TDextDirectAccess.ReadObject(Instance, DirectField.Offset);
                if ExistingObj <> nil then
                begin
                  DeserializeObject(Node as IDextJsonObject, ExistingObj.ClassInfo, ExistingObj);
                end
                else
                begin
                  Val := DeserializeObject(Node as IDextJsonObject, DirectField.TypeInfo);
                  if not Val.IsEmpty and (Val.Kind = tkClass) and (Val.AsObject <> nil) then
                    TDextDirectAccess.WriteObject(Instance, DirectField.Offset, Val.AsObject);
                end;
                Continue;
              end;
            nkList:
              if (Node.GetNodeType = jntArray) and (DirectField.TypeInfo <> nil) then
              begin
                ExistingPropVal := TValue.Empty;
                if DirectField.TypeInfo.Kind = tkClass then
                begin
                  ExistingObj := TDextDirectAccess.ReadObject(Instance, DirectField.Offset);
                  if ExistingObj <> nil then
                    ExistingPropVal := TValue.From<TObject>(ExistingObj);
                end
                else if DirectField.TypeInfo.Kind = tkInterface then
                begin
                  ExistingIntf := TDextDirectAccess.ReadInterface(Instance, DirectField.Offset);
                  if ExistingIntf <> nil then
                    ExistingPropVal := TValue.From<IInterface>(ExistingIntf);
                end;

                if ExistingPropVal.IsEmpty then
                  Val := DeserializeList(Node as IDextJsonArray, DirectField.TypeInfo)
                else
                  Val := DeserializeList(Node as IDextJsonArray, DirectField.TypeInfo, ExistingPropVal);

                if ExistingPropVal.IsEmpty then
                begin
                  if not Val.IsEmpty and (Val.Kind = tkClass) and (Val.AsObject <> nil) then
                    TDextDirectAccess.WriteObject(Instance, DirectField.Offset, Val.AsObject)
                  else if not Val.IsEmpty and (Val.Kind = tkInterface) and (Val.AsInterface <> nil) then
                    TDextDirectAccess.WriteInterface(Instance, DirectField.Offset, Val.AsInterface);
                end;
                Continue;
              end;
          end;
        end;
        Handler := TReflection.GetHandler(AType, Prop.Name);
        Val := TValue.Empty;
        case Node.GetNodeType of
          jntString:
            Val := TValue.From<string>(Node.AsString);
          jntNumber:
            begin
              case Prop.PropertyType.TypeKind of
                tkInteger:
                  Val := TValue.FromOrdinal(Prop.PropertyType.Handle, Node.AsInt64);
                tkInt64:
                  Val := Node.AsInt64;
                tkFloat:
                  if Prop.PropertyType.Handle = TypeInfo(TDateTime) then
                    Val := ISO8601ToDate(Node.AsString)
                  else
                    Val := TValue.From<Double>(Node.AsDouble);
                tkRecord:
                  if TReflection.IsSmartProp(Prop.PropertyType.Handle) then
                    Val := TValue.From<Double>(Node.AsDouble)
                  else
                    Val := TValue.Empty;
              else
                Val := TValue.Empty;
              end;
            end;
          jntBoolean:
            Val := TValue.From<Boolean>(Node.AsBoolean);
          jntObject:
            begin
              if (Prop.PropertyType.TypeKind = tkClass) or (Prop.PropertyType.TypeKind = tkInterface) then
              begin
                // Check if the property already holds an instance (e.g. created in constructor).
                // If so, populate it in-place instead of creating a new one.
                ExistingPropVal := Prop.GetValue(Instance);
                ExistingObj := nil;
                if not ExistingPropVal.IsEmpty then
                begin
                  if Prop.PropertyType.TypeKind = tkClass then
                    ExistingObj := ExistingPropVal.AsObject
                  else if (Prop.PropertyType.TypeKind = tkInterface) and
                          (ExistingPropVal.AsInterface <> nil) then
                    ExistingObj := ExistingPropVal.AsInterface as TObject;
                end;

                if ExistingObj <> nil then
                begin
                  // Populate the existing instance in-place using its actual runtime type.
                  // Leave Val = Empty so Handler.SetValue is skipped - the reference is already correct.
                  DeserializeObject(Node as IDextJsonObject,
                    TReflection.Context.GetType(ExistingObj.ClassType).Handle, ExistingObj);
                end
                else
                  Val := DeserializeObject(Node as IDextJsonObject, Prop.PropertyType.Handle);
              end
              else if (Prop.PropertyType.TypeKind = tkRecord) then
                Val := DeserializeRecord(Node as IDextJsonObject, Prop.PropertyType.Handle)
              else if IsDictionaryType(Prop.PropertyType.Handle) then
                Val := DeserializeDictionary(Node as IDextJsonObject, Prop.PropertyType.Handle)
              else
                Val := TValue.Empty;
            end;
          jntArray:
            begin
              if IsArrayType(Prop.PropertyType.Handle) then
                Val := DeserializeArray(Node as IDextJsonArray, Prop.PropertyType.Handle)
              else if IsListType(Prop.PropertyType.Handle) then
              begin
                ExistingPropVal := Prop.GetValue(Instance);
                if ExistingPropVal.IsEmpty then
                  Val := DeserializeList(Node as IDextJsonArray, Prop.PropertyType.Handle)
                else
                  Val := DeserializeList(Node as IDextJsonArray, Prop.PropertyType.Handle, ExistingPropVal);
              end
              else
                Val := TValue.Empty;
            end;
        else
          Val := TValue.Empty;
        end;

        if not Val.IsEmpty then
        begin
          if Handler <> nil then
            Handler.SetValue(Instance, Val)
          else
            Prop.SetValue(Instance, Val);
        end;
      end;
    end;
  except
    if AInstance = nil then
      Instance.Free;
    raise;
  end;
end;

function TDextSerializer.DeserializeRecord(AJson: IDextJsonObject; AType: PTypeInfo): TValue;
var
  Plan: PRecordPlan;
  I, J: Integer;
  Item: PRecordPlanItem;
  Node: IDextJsonNode;
  Val: TValue;
  FieldPtr: ^IInterface;
  ActualName: string;
  LowerFieldName: string;
  FieldName: string;
begin
  if AType = TypeInfo(TGUID) then
    Exit(TValue.From<TGUID>(StringToGUID(AJson.GetString(ValueField))));
  if AType = TypeInfo(TUUID) then
    Exit(TValue.From<TUUID>(TUUID.FromString(AJson.GetString(ValueField))));

  TValue.Make(nil, AType, Result);
  Plan := GetOrBuildRecordPlan(AType);

  for I := 0 to Plan.Count - 1 do
  begin
    Item := @Plan.Items[I];

    FieldName := ResolveFieldName(Item);
    Node := AJson.GetNode(FieldName);

    // Case-insensitive fallback for records:
    if ((Node = nil) or Node.IsNull) and (FSettings.FCaseInsensitive or FSettings.FSmartRecordMapping) then
    begin
      LowerFieldName := LowerCase(FieldName);
      for J := 0 to AJson.GetCount - 1 do
      begin
        ActualName := AJson.GetName(J);
        if LowerCase(ActualName) = LowerFieldName then
        begin
          Node := AJson.GetNode(ActualName);
          Break;
        end;
      end;
    end;

    if (Node = nil) or Node.IsNull then
      Continue;

    Val := TValue.Empty; // Reset for each field

    case Node.GetNodeType of
      jntString: Val := TValue.From<string>(Node.AsString);
      jntNumber:
        begin
          if (Item^.FieldTypeInfo = TypeInfo(Integer)) then
            Val := TValue.From<Integer>(Node.AsInteger)
          else if (Item^.FieldTypeInfo = TypeInfo(Int64)) then
            Val := TValue.From<Int64>(Node.AsInt64)
          else
            Val := TValue.From<Double>(Node.AsDouble);
        end;
      jntBoolean: Val := TValue.From<Boolean>(Node.AsBoolean);
      jntNull: Val := TValue.Empty;
      jntObject:
        begin
          if (Item^.Kind = skClass) or (Item^.Kind = skList) then
            Val := DeserializeObject(Node as IDextJsonObject, Item^.FieldTypeInfo)
          else if (Item^.Kind = skRecord) then
            Val := DeserializeRecord(Node as IDextJsonObject, Item^.FieldTypeInfo)
          else if (Item^.Kind = skInterface) then
            Val := DeserializeObject(Node as IDextJsonObject, Item^.FieldTypeInfo)
          else
            Val := TValue.Empty;
        end;
      jntArray:
        begin
          if IsArrayType(Item^.FieldTypeInfo) then
            Val := DeserializeArray(Node as IDextJsonArray, Item^.FieldTypeInfo)
          else if IsListType(Item^.FieldTypeInfo) then
            Val := DeserializeList(Node as IDextJsonArray, Item^.FieldTypeInfo)
          else
            Val := TValue.Empty;
        end;
      else Val := TValue.Empty;
    end;

    if not Val.IsEmpty then
    begin
      if (Item^.Kind = skInterface) then
      begin
        FieldPtr := Pointer(PByte(Result.GetReferenceToRawData) + Item^.Field.Offset);
        FieldPtr^ := Val.AsInterface;
      end
      else
        TReflection.SetValue(Result.GetReferenceToRawData, Item^.Field, Val);
    end;
  end;
end;

function TDextSerializer.GetFieldName(AField: TRttiField): string;
var
  Attribute: TCustomAttribute;
  RttiType: TRttiType;
begin
  for Attribute in AField.GetAttributes do
    if Attribute is JsonNameAttribute then
      Exit(JsonNameAttribute(Attribute).Name);

  Result := AField.Name;

  // Standard Dext Convention for Records:
  // If field starts with 'F' and it is a record, we assume it is a storage field
  // and strip the 'F' to match the intended property name in JSON.
  RttiType := AField.Parent;
  if (RttiType <> nil) and (RttiType.IsRecord) and (FSettings.FSmartRecordMapping) then
  begin
    if (Result.Length > 1) and (Result.Chars[0] = 'F') then
    begin
      Result := Result.Substring(1);
    end;
  end;
  
  Result := ApplyCaseStyle(Result);
end;

function TDextSerializer.GetRecordName(ARttiType: TRttiType): string;
var
  Attribute: TCustomAttribute;
begin
  for Attribute in ARttiType.GetAttributes do
  begin
    if Attribute is JsonNameAttribute then
      Exit(JsonNameAttribute(Attribute).Name);
  end;
  Result := '';
end;

function TDextSerializer.JsonToValue(AJson: IDextJsonObject; AType: PTypeInfo): TValue;
var
  Arr: IDextJsonArray;
  DtStr: string;
  DtVal: TDateTime;
begin
  if AType.Kind = tkRecord then
  begin
    if AType = TypeInfo(TGUID) then
      Result := TValue.From<TGUID>(StringToGUID(AJson.GetString(ValueField)))
    else if AType = TypeInfo(TUUID) then
      Result := TValue.From<TUUID>(TUUID.FromString(AJson.GetString(ValueField)))
    else
      Result := DeserializeRecord(AJson, AType);
  end
  else if AType.Kind = tkClass then
  begin
    Result := DeserializeObject(AJson, AType);
  end
  else if IsArrayType(AType) then
  begin
    if AJson.Contains('value') then
    begin
      Arr := AJson.GetArray('value');
      if Arr <> nil then
        Result := DeserializeArray(Arr, AType)
      else
        Result := TValue.Empty;
    end
    else
      Result := TValue.Empty;
  end
  else if IsListType(AType) then
  begin
    if AJson.Contains('value') then
    begin
      Arr := AJson.GetArray('value');
      if Arr <> nil then
        Result := DeserializeList(Arr, AType)
      else
        Result := TValue.Empty;
    end
    else
      Result := TValue.Empty;
  end
  else if IsDictionaryType(AType) then
  begin
    Result := DeserializeDictionary(AJson, AType);
  end
  else if AJson.Contains(ValueField) then
  begin
    case AType.Kind of
      tkInteger:
        Result := TValue.From<Integer>(AJson.GetInteger(ValueField));

      tkInt64:
        Result := TValue.From<Int64>(AJson.GetInt64(ValueField));

      tkFloat:
        begin
          if (AType = TypeInfo(TDateTime)) or
             (AType = TypeInfo(TDate)) or
             (AType = TypeInfo(TTime)) then
          begin
            DtStr := AJson.GetString(ValueField);
            if TryParseCommonDate(DtStr, DtVal) then
              Result := TValue.From<TDateTime>(DtVal)
            else
              Result := TValue.From<TDateTime>(0);
          end
          else
            Result := TValue.From<Double>(AJson.GetDouble(ValueField));
        end;

      tkString, tkLString, tkWString, tkUString:
        Result := TValue.From<string>(AJson.GetString(ValueField));

      tkEnumeration:
        begin
          if AType = TypeInfo(Boolean) then
            Result := TValue.From<Boolean>(AJson.GetBoolean(ValueField))
          else
            Result := TValue.FromOrdinal(AType, GetEnumValue(AType, AJson.GetString(ValueField)));
        end;

      else
        Result := TValue.Empty;
    end;
  end
  else
    Result := TValue.Empty;
end;

function TDextSerializer.Serialize<T>(const AValue: T): string;
var
  JsonNode: IDextJsonNode;
begin
  // Check if root is array or list
  if IsArrayType(TypeInfo(T)) then
    JsonNode := SerializeArray(TValue.From<T>(AValue))
  else if IsListType(TypeInfo(T)) then
    JsonNode := SerializeList(TValue.From<T>(AValue))
  else
    JsonNode := ValueToJson(TValue.From<T>(AValue));

  if FSettings.Formatting = TJsonFormatting.Indented then
    Result := JsonNode.ToJson(True)
  else
    Result := JsonNode.ToJson(False);
end;

function TDextSerializer.Serialize(const AValue: TValue): string;
var
  JsonNode: IDextJsonNode;
begin
  // Check if root is array or list
  if IsArrayType(AValue.TypeInfo) then
    JsonNode := SerializeArray(AValue)
  else if IsListType(AValue.TypeInfo) then
    JsonNode := SerializeList(AValue)
  else
    JsonNode := ValueToJson(AValue);

  if FSettings.Formatting = TJsonFormatting.Indented then
    Result := JsonNode.ToJson(True)
  else
    Result := JsonNode.ToJson(False);
end;

function TDextSerializer.SerializeRecord(const AValue: TValue): IDextJsonObject;
var
  Plan: PRecordPlan;
  I: Integer;
  Item: PRecordPlanItem;
  FieldValue: TValue;
  Unwrapped: TValue;
  NestedRecord: IDextJsonObject;
  NumValue: Double;
  FieldName: string;
begin
  if AValue.TypeInfo = TypeInfo(TGUID) then
  begin
    Result := TDextJson.Provider.CreateObject;
    Result.SetString(ValueField, GetGUIDString(AValue));
    Exit;
  end;

  if AValue.TypeInfo = TypeInfo(TUUID) then
  begin
    Result := TDextJson.Provider.CreateObject;
    Result.SetString(ValueField, GetUUIDString(AValue));
    Exit;
  end;

  Result := TDextJson.Provider.CreateObject;
  Plan := GetOrBuildRecordPlan(AValue.TypeInfo);

  for I := 0 to Plan.Count - 1 do
  begin
    Item := @Plan.Items[I];

    FieldName := ResolveFieldName(Item);
    FieldValue := Item^.Field.GetValue(AValue.GetReferenceToRawData);

    // Smart Properties Support: Unwrap Prop<T>
    if Item^.IsSmartProp then
    begin
      if TReflection.TryUnwrapProp(FieldValue, Unwrapped) then
        FieldValue := Unwrapped;
    end;

    // Handle null/empty values (e.g. Nullable without value)
    if FieldValue.IsEmpty then
    begin
      if not FSettings.FIgnoreNullValues then
        Result.SetNull(FieldName);
      Continue;
    end;

    // Default values: the same rules as SerializeObjectWithPlan for class
    // properties. ShouldSkipField did this for record fields before the
    // record plan, and is no longer called.
    if FSettings.IgnoreDefaultValues then
      case Item^.Kind of
        skInteger:
          if FieldValue.AsInt64 = 0 then
            Continue;
        skFloat, skDateTime:
          if FieldValue.AsExtended = 0 then
            Continue;
        skString:
          if FieldValue.AsString = '' then
            Continue;
        skBoolean:
          if not FieldValue.AsBoolean then
            Continue;
        skEnumAsString, skEnumAsNumber:
          if not FSettings.FKeepDefaultEnums and (FieldValue.AsOrdinal = 0) then
            Continue;
      end;

    if (Item^.FieldTypeInfo = TypeInfo(TGUID)) then
    begin
      Result.SetString(FieldName, GetGUIDString(FieldValue));
      Continue;
    end;

    if (Item^.FieldTypeInfo = TypeInfo(TUUID)) then
    begin
      Result.SetString(FieldName, GetUUIDString(FieldValue));
      Continue;
    end;

    case Item^.Kind of
      skInteger:
        begin
          if Item^.ForceString then
            Result.SetString(FieldName, IntToJsonString(FieldValue.AsInt64))
          else
            Result.SetInt64(FieldName, FieldValue.AsInt64);
        end;

      skDateTime:
        begin
          if Item^.HasCustomFormat then
            Result.SetString(FieldName, FormatDateTime(Item^.CustomFormat, FieldValue.AsExtended))
          else
            case FSettings.DateFormatStyle of
              TDateFormat.ISO8601:
                Result.SetString(FieldName, FormatDateTime(FSettings.DateFormat, FieldValue.AsExtended));
              TDateFormat.UnixTimestamp:
                Result.SetInt64(FieldName, DateTimeToUnix(FieldValue.AsExtended));
              TDateFormat.CustomFormat:
                Result.SetString(FieldName, FormatDateTime(FSettings.DateFormat, FieldValue.AsExtended));
            end;
        end;

      skFloat:
        begin
          if Item^.ForceString then
            Result.SetString(FieldName, FloatToJsonString(FieldValue.AsExtended))
          else
            Result.SetDouble(FieldName, FieldValue.AsExtended);
        end;

      skString:
        begin
          if Item^.ForceNumber then
          begin
            NumValue := JsonStringToFloat(FieldValue.AsString);
            Result.SetDouble(FieldName, NumValue);
          end
          else
          begin
            Result.SetString(FieldName, FieldValue.AsString);
          end;
        end;

      skBoolean:
        begin
          if Item^.ForceString then
            Result.SetString(FieldName, BoolToStr(FieldValue.AsBoolean, True).ToLower)
          else
            Result.SetBoolean(FieldName, FieldValue.AsBoolean);
        end;

      skEnumAsString, skEnumAsNumber:
        begin
          case FSettings.EnumStyle of
            TEnumStyle.AsString:
              Result.SetString(FieldName, GetEnumName(Item^.FieldTypeInfo, FieldValue.AsOrdinal));
            TEnumStyle.AsNumber:
              Result.SetInteger(FieldName, FieldValue.AsOrdinal);
          end;
        end;

      skRecord:
        begin
          NestedRecord := SerializeRecord(FieldValue);
          Result.SetObject(FieldName, NestedRecord);
        end;

      skList:
        Result.SetArray(FieldName, SerializeList(FieldValue));

      skDynArray:
        Result.SetArray(FieldName, SerializeArray(FieldValue));

      skClass, skInterface:
        Result.SetObject(FieldName, SerializeObject(FieldValue));
    end;
  end;
end;

function TDextSerializer.SerializeObject(const AValue: TValue): IDextJsonObject;
var
  Obj: TObject;
  Plan: PSerializationPlan;
begin
  if AValue.IsEmpty then
  begin
    Result := TDextJson.Provider.CreateObject;
    Exit;
  end;

  Obj := AValue.AsObject;
  if Obj = nil then
  begin
    Result := TDextJson.Provider.CreateObject;
    Exit;
  end;

  Plan := GetOrBuildPlan(Obj.ClassInfo);
  Result := SerializeObjectWithPlan(Obj, Plan^);
end;

function TDextSerializer.ShouldSkipField(AField: TRttiField; const AValue: TValue): Boolean;
var
  Attribute: TCustomAttribute;
  FieldValue: TValue;
  Unwrapped: TValue;
begin
  for Attribute in AField.GetAttributes do
  begin
    if Attribute is JsonIgnoreAttribute then
      Exit(True);
  end;

  if not AValue.IsEmpty then
    FieldValue := AField.GetValue(AValue.GetReferenceToRawData)
  else
    FieldValue := TValue.Empty;

  if FSettings.FIgnoreNullValues and FieldValue.IsEmpty then
    Exit(True);

  if FSettings.IgnoreDefaultValues then
  begin
    // Support Smart Properties (Prop<T>)
    if (FieldValue.Kind = tkRecord) and (FieldValue.TypeInfo <> nil) and
       TReflection.IsSmartProp(FieldValue.TypeInfo) then
    begin
      if TReflection.TryUnwrapProp(FieldValue, Unwrapped) then
        FieldValue := Unwrapped;
    end;

    case FieldValue.Kind of
      tkInteger: if FieldValue.AsInteger = 0 then Exit(True);
      tkInt64: if FieldValue.AsInt64 = 0 then Exit(True);
      tkFloat: if FieldValue.AsExtended = 0 then Exit(True);
      tkUString, tkString, tkWString, tkLString:
        if FieldValue.AsString = '' then Exit(True);
      tkEnumeration:
        if FieldValue.TypeInfo = TypeInfo(Boolean) then
        begin
          if not FieldValue.AsBoolean then Exit(True)
        end
        else if not FSettings.FKeepDefaultEnums and (FieldValue.AsOrdinal = 0) then Exit(True);
    end;
  end;

  Result := (AField.FieldType = nil) or
            (AField.Name.StartsWith('$'));

  // Normal visibility check for classes
  // For records, we allow private fields starting with 'F' (storage fields)
  if not Assigned(AField.Parent) or not AField.Parent.IsRecord then
  begin
    if (AField.Visibility <> mvPublic) and (AField.Visibility <> mvPublished) then
      Result := True;
  end
  else
  begin
    // In records, if it's not public and doesn't start with F, skip it
    if (AField.Visibility <> mvPublic) and not AField.Name.StartsWith('F') then
      Result := True;
  end;
end;

function TDextSerializer.ValueToJson(const AValue: TValue): IDextJsonObject;
begin
  Result := TDextJson.Provider.CreateObject;

  if AValue.IsEmpty then
    Exit;

  case AValue.TypeInfo.Kind of
    tkInteger, tkInt64:
      Result.SetInt64(ValueField, AValue.AsInt64);

    tkFloat:
      begin
        if AValue.TypeInfo = TypeInfo(TDateTime) then
          Result.SetString(ValueField, FormatDateTime(FSettings.DateFormat, AValue.AsExtended))
        else
          Result.SetDouble(ValueField, AValue.AsExtended);
      end;

    tkString, tkLString, tkWString, tkUString:
      Result.SetString(ValueField, AValue.AsString);

    tkEnumeration:
      begin
        if AValue.TypeInfo = TypeInfo(Boolean) then
          Result.SetBoolean(ValueField, AValue.AsBoolean)
        else
          Result.SetString(ValueField, GetEnumName(AValue.TypeInfo, AValue.AsOrdinal));
      end;

    tkRecord:
      begin
        if AValue.TypeInfo = TypeInfo(TGUID) then
          Result.SetString(ValueField, GetGUIDString(AValue))
        else if AValue.TypeInfo = TypeInfo(TUUID) then
          Result.SetString(ValueField, GetUUIDString(AValue))
        else
          // Replace result with serialized record
          // Note: ValueToJson returns Object. If SerializeRecord returns Object, we are good.
          Result := SerializeRecord(AValue);
      end;

    // Array handling in ValueToJson is tricky because return type is IDextJsonObject
    // But SerializeArray returns IDextJsonArray.
    // We should probably change ValueToJson to return IDextJsonNode or handle arrays separately.
    // For now, let's wrap in "value" field if it's array, or change logic.
    // The original code did: Result.A[ValueField] := SerializeArray(AValue);
    tkDynArray:
      begin
        Result.SetArray(ValueField, SerializeArray(AValue));
      end;

    tkClass:
      begin
        // Distinguish between lists and regular objects
        if IsListType(AValue.TypeInfo) then
          Result.SetArray(ValueField, SerializeList(AValue))
        else
          Result := SerializeObject(AValue);
      end;
  end;
end;

class function TDextJson.GetProvider: IDextJsonProvider;
begin
  if FProvider = nil then
    FProvider := TNextGenJsonProvider.Create;
  Result := FProvider;
end;

class procedure TDextJson.SetDefaultSettings(const ASettings: TJsonSettings);
begin
  FDefaultSettings := ASettings;
end;

class function TDextJson.GetDefaultSettings: TJsonSettings;
begin
  // If not explicitly set, return the default
  if (FDefaultSettings.DateFormat = '') and not FDefaultSettings.FCaseInsensitive then
    Result := TJsonSettings.Default
  else
    Result := FDefaultSettings;
end;

class function TDextJson.GetInterfaceMappings: IDictionary<string, string>;
begin
  if not Assigned(FInterfaceMappings) then
    FInterfaceMappings := TCollections.CreateDictionary<string, string>;

  Result := FInterfaceMappings;
end;

class procedure TDextJson.RegisterImplementation(const AInterfaceName, AImplementationName: string);
begin
  GetInterfaceMappings.AddOrSetValue(AInterfaceName, AImplementationName);
end;

function TDextSerializer.IsArrayType(AType: PTypeInfo): Boolean;
begin
  Result := (AType.Kind = tkDynArray);
end;

function TDextSerializer.IsListType(AType: PTypeInfo): Boolean;
var
  TypeName: string;
begin
  Result := TActivator.IsListType(AType);
  if not Result and (AType <> nil) and (AType.Kind = tkInterface) then
  begin
    TypeName := string(AType.Name);
    Result := TypeName.Contains('IList<') or TypeName.Contains('IReadOnlyList<') or TypeName.Contains('IEnumerable<');
  end;
end;

function TDextSerializer.IsDictionaryType(AType: PTypeInfo): Boolean;
begin
  Result := TActivator.IsDictionaryType(AType);
end;

function TDextSerializer.GetDictionaryKeyType(AType: PTypeInfo): PTypeInfo;
begin
  Result := TActivator.GetDictionaryKeyType(AType);
end;

function TDextSerializer.GetDictionaryValueType(AType: PTypeInfo): PTypeInfo;
begin
  Result := TActivator.GetDictionaryValueType(AType);
end;

function TDextSerializer.GetArrayElementType(AType: PTypeInfo): PTypeInfo;
begin
  Result := AType.TypeData^.DynArrElType^;
end;

function TDextSerializer.GetListElementType(AType: PTypeInfo): PTypeInfo;
begin
  Result := TActivator.GetListElementType(AType);
end;

procedure TDextSerializer.Populate(AInstance: TObject; const AJson: string);
var
  Node: IDextJsonNode;
begin
  if (AInstance = nil) or (AJson = '') then Exit;
  Node := TDextJson.Provider.Parse(AJson);
  if (Node <> nil) and (Node.GetNodeType = jntObject) then
    DeserializeObject(Node as IDextJsonObject, AInstance.ClassInfo, AInstance);
end;

function TDextSerializer.DeserializeArray(AJson: IDextJsonArray; AType: PTypeInfo): TValue;
var
  Count: NativeInt;
  DynArray: Pointer;
  ElementType: PTypeInfo;
  ElementValue: TValue;
  I: Integer;
  Node: IDextJsonNode;
  P: PByte;
  ElSize: Integer;
begin
  ElementType := GetArrayElementType(AType);
  DynArray := nil;
  Count := AJson.GetCount;
  DynArraySetLength(DynArray, AType, 1, @Count); // AJson.Count -> GetCount
  ElSize := TReflection.GetMetadata(ElementType).RttiType.TypeSize;

  try
    for I := 0 to AJson.GetCount - 1 do
    begin
      Node := AJson.GetNode(I);
      case ElementType.Kind of
        tkInteger:
          ElementValue := TValue.From<Integer>(AJson.GetInteger(I));
        tkInt64:
          ElementValue := TValue.From<Int64>(AJson.GetInt64(I));
        tkFloat:
          if ElementType = TypeInfo(TDateTime) then
            ElementValue := TValue.From<TDateTime>(ISO8601ToDate(AJson.GetString(I)))
          else
            ElementValue := TValue.From<Double>(AJson.GetDouble(I));
        tkString, tkLString, tkWString, tkUString:
          ElementValue := TValue.From<string>(AJson.GetString(I));
        tkEnumeration:
          if ElementType = TypeInfo(Boolean) then
            ElementValue := TValue.From<Boolean>(AJson.GetBoolean(I))
          else
            ElementValue := TValue.FromOrdinal(ElementType, GetEnumValue(ElementType, AJson.GetString(I)));
        tkRecord:
          begin
            if ElementType = TypeInfo(TGUID) then
              ElementValue := TValue.From<TGUID>(StringToGUID(AJson.GetString(I)))
            else if ElementType = TypeInfo(TUUID) then
              ElementValue := TValue.From<TUUID>(TUUID.FromString(AJson.GetString(I)))
            else
            begin
              if (Node <> nil) and (Node.GetNodeType = jntObject) then
                ElementValue := DeserializeRecord(Node as IDextJsonObject, ElementType)
              else
                ElementValue := TValue.Empty;
            end;
          end;
        tkClass:
          begin
            if (Node <> nil) and (Node.GetNodeType = jntObject) then
               ElementValue := DeserializeObject(Node as IDextJsonObject, ElementType)
            else
               ElementValue := TValue.Empty;
          end;
        tkDynArray:
          begin
            if (Node <> nil) and (Node.GetNodeType = jntArray) then
               ElementValue := DeserializeArray(Node as IDextJsonArray, ElementType)
            else
               ElementValue := TValue.Empty;
          end;
      else
        ElementValue := TValue.Empty;
      end;

      if not ElementValue.IsEmpty then
      begin
        P := PByte(DynArray) + (I * ElSize);
        if TRttiContext.Create.GetType(ElementType).IsManaged then
          System.CopyArray(P, ElementValue.GetReferenceToRawData, ElementType, 1)
        else
          System.Move(ElementValue.GetReferenceToRawData^, P^, ElSize);
      end;
    end;

    TValue.Make(@DynArray, AType, Result);
    DynArrayClear(DynArray, AType);
    DynArray := nil;
  except
    if DynArray <> nil then
      DynArrayClear(DynArray, AType);
    raise;
  end;
end;

function TDextSerializer.DeserializeList(AJson: IDextJsonArray; AType: PTypeInfo): TValue;
begin
  Result := DeserializeList(AJson, AType, TValue.Empty);
end;

function TDextSerializer.DeserializeList(AJson: IDextJsonArray; AType: PTypeInfo; const AExisting: TValue): TValue;
var
  ActualRttiType: TRttiType;
  AddMethod: TRttiMethod;
  Collection: ICollection;
  ElementType: PTypeInfo;
  ElementValue: TValue;
  I: Integer;
  InstObj: TObject;
  Intf: TRttiInterfaceType;
  Method: TRttiMethod;
  Obj: TObject;
  Node: IDextJsonNode;
  OwnsProp: TRttiProperty;
  ClearMethod: TRttiMethod;
  RttiType: TRttiType;
  StrictValue: TValue;
  TargetInst: TValue;
begin
  try
    ElementType := GetListElementType(AType);
    if ElementType = nil then
      raise EDextJsonException.CreateFmt('Could not determine element type for %s', [AType.NameFld.ToString]);

    if AExisting.IsEmpty then
      Result := CreateInstanceForDeserialization(AType)
    else
      Result := AExisting;

    RttiType := TReflection.GetMetadata(AType).RttiType;

    if ElementType.Kind = tkClass then
    begin
      if Result.Kind = tkInterface then
      begin
        if Supports(Result.AsInterface, ICollection, Collection) then
          Collection.OwnsObjects := True;
      end
      else if Result.Kind = tkClass then
      begin
        OwnsProp := RttiType.GetProperty('OwnsObjects');
        if (OwnsProp <> nil) and (OwnsProp.PropertyType.Handle = TypeInfo(Boolean)) then
          OwnsProp.SetValue(Result.AsObject, True);
      end;
    end;

    InstObj := nil;
    if Result.Kind = tkClass then
      InstObj := Result.AsObject;

    if Assigned(InstObj) then
      ActualRttiType := TReflection.Context.GetType(InstObj.ClassType)
    else
      ActualRttiType := RttiType;

    AddMethod := nil;
    ClearMethod := nil;

    if not AExisting.IsEmpty then
    begin
      if ActualRttiType is TRttiInstanceType then
        ClearMethod := ActualRttiType.GetMethod('Clear')
      else if RttiType is TRttiInterfaceType then
      begin
        Intf := TRttiInterfaceType(RttiType);
        while (Intf <> nil) and (ClearMethod = nil) do
        begin
          for Method in Intf.GetMethods do
            if (Method.Name = 'Clear') and (Length(Method.GetParameters) = 0) then
            begin
              ClearMethod := Method;
              Break;
            end;
          if ClearMethod <> nil then
            Break;
          if Intf.BaseType is TRttiInterfaceType then
            Intf := TRttiInterfaceType(Intf.BaseType)
          else
            Intf := nil;
        end;
      end;

      if ClearMethod <> nil then
        ClearMethod.Invoke(Result, []);
    end;

    if ActualRttiType is TRttiInstanceType then
    begin
      for Method in ActualRttiType.GetMethods do
        if (Method.Name = 'Add') and (Length(Method.GetParameters) = 1) then
        begin
          AddMethod := Method;
          Break;
        end;
    end;

    if not Assigned(AddMethod) and (RttiType is TRttiInterfaceType) then
    begin
      Intf := TRttiInterfaceType(RttiType);
      while Intf <> nil do
      begin
        for Method in Intf.GetMethods do
          if (Method.Name = 'Add') and (Length(Method.GetParameters) = 1) then
          begin
            AddMethod := Method;
            Break;
          end;
        if Assigned(AddMethod) then
          Break;
        if Intf.BaseType is TRttiInterfaceType then
          Intf := TRttiInterfaceType(Intf.BaseType)
        else
          Intf := nil;
      end;
    end;

    if not Assigned(AddMethod) then
      raise EDextJsonException.CreateFmt('Could not find Add method for list type %s', [AType.NameFld.ToString]);

    for I := 0 to AJson.GetCount - 1 do
    begin
      Node := AJson.GetNode(I);
      if (Node <> nil) and (Node.GetNodeType = jntObject) then
      begin
        if (ElementType.Kind = tkClass) or (ElementType.Kind = tkInterface) then
          ElementValue := DeserializeObject(Node as IDextJsonObject, ElementType)
        else
          ElementValue := DeserializeRecord(Node as IDextJsonObject, ElementType);
      end
      else
      begin
        case ElementType.Kind of
          tkInteger: ElementValue := TValue.From<Integer>(AJson.GetInteger(I));
          tkInt64: ElementValue := TValue.From<Int64>(AJson.GetInt64(I));
          tkFloat:
            if ElementType = TypeInfo(TDateTime) then
              ElementValue := TValue.From<TDateTime>(ISO8601ToDate(AJson.GetString(I)))
            else
              ElementValue := TValue.From<Double>(AJson.GetDouble(I));
          tkString, tkLString, tkWString, tkUString:
            ElementValue := TValue.From<string>(AJson.GetString(I));
          tkEnumeration:
            if ElementType = TypeInfo(Boolean) then
              ElementValue := TValue.From<Boolean>(AJson.GetBoolean(I))
            else
              ElementValue := TValue.FromOrdinal(ElementType, GetEnumValue(ElementType, AJson.GetString(I)));
          tkRecord:
            if ElementType = TypeInfo(TGUID) then
              ElementValue := TValue.From<TGUID>(StringToGUID(AJson.GetString(I)))
            else if ElementType = TypeInfo(TUUID) then
              ElementValue := TValue.From<TUUID>(TUUID.FromString(AJson.GetString(I)))
            else
              ElementValue := TValue.Empty;
          tkClass:
            begin
              if (Node <> nil) and (Node.GetNodeType = jntObject) then
                ElementValue := DeserializeObject(Node as IDextJsonObject, ElementType)
              else
                ElementValue := TValue.Empty;
            end;
          tkDynArray:
            begin
              if (Node <> nil) and (Node.GetNodeType = jntArray) then
                ElementValue := DeserializeArray(Node as IDextJsonArray, ElementType)
              else
                ElementValue := TValue.Empty;
            end;
        else
          ElementValue := TValue.Empty;
        end;
      end;

      if not ElementValue.IsEmpty then
      begin
        if Assigned(InstObj) and (AddMethod.Parent.IsInstance) then
          TargetInst := InstObj
        else
          TargetInst := Result;

        StrictValue := ElementValue;
        if (ElementType.Kind = tkClass) and (StrictValue.AsObject <> nil) then
        begin
          Obj := StrictValue.AsObject;
          TValue.Make(@Obj, ElementType, StrictValue);
        end;

        AddMethod.Invoke(TargetInst, [StrictValue]);
      end;
    end;

    Exit(Result);
  finally
  end;
end;

function TDextSerializer.DeserializeDictionary(AJson: IDextJsonObject; AType: PTypeInfo): TValue;
var
  ActualRttiType: TRttiType;
  AddMethod: TRttiMethod;
  I: Integer;
  InstObj: TObject;
  Intf: TRttiInterfaceType;
  KeyName: string;
  KeyType, ValueType: PTypeInfo;
  KeyVal, ValVal: TValue;
  Method: TRttiMethod;
  Node: IDextJsonNode;
  RttiType: TRttiType;
  TargetInst: TValue;
begin
  try
    KeyType := GetDictionaryKeyType(AType);
    ValueType := GetDictionaryValueType(AType);

    if (KeyType = nil) or (ValueType = nil) then
      raise EDextJsonException.CreateFmt('Could not determine dictionary types for %s', [string(AType^.Name)]);

    // Instantiate via Activator
    Result := CreateInstanceForDeserialization(AType);

    RttiType := TReflection.GetMetadata(AType).RttiType;

    InstObj := nil;
    if Result.Kind = tkInterface then
    begin
      try
        InstObj := Result.AsInterface as TObject;
      except
        InstObj := nil;
      end;
    end
    else if Result.Kind = tkClass then
      InstObj := Result.AsObject;

    if Assigned(InstObj) then
      ActualRttiType := TReflection.Context.GetType(InstObj.ClassType)
    else
      ActualRttiType := RttiType;

    AddMethod := nil;

    // First try concrete instance type
    if ActualRttiType is TRttiInstanceType then
    begin
      for Method in ActualRttiType.GetMethods do
        if ((Method.Name = 'Add') or (Method.Name = 'AddOrSetValue')) and (Length(Method.GetParameters) = 2) then
        begin
          AddMethod := Method;
          Break;
        end;
    end;

    // Fallback to interface hierarchy
    if not Assigned(AddMethod) and (RttiType is TRttiInterfaceType) then
    begin
      Intf := TRttiInterfaceType(RttiType);
      while Intf <> nil do
      begin
        for Method in Intf.GetMethods do
          if ((Method.Name = 'Add') or (Method.Name = 'AddOrSetValue')) and (Length(Method.GetParameters) = 2) then
          begin
            AddMethod := Method;
            Break;
          end;
        if Assigned(AddMethod) then Break;
        if Intf.BaseType is TRttiInterfaceType then
          Intf := TRttiInterfaceType(Intf.BaseType)
        else
          Intf := nil;
      end;
    end;

    if not Assigned(AddMethod) then
      raise EDextJsonException.CreateFmt('Could not find Add method for dictionary type %s', [string(AType^.Name)]);

    for I := 0 to AJson.GetCount - 1 do
    begin
      KeyName := AJson.GetName(I);

      // Key conversion
      case KeyType.Kind of
        tkUString, tkString, tkWString, tkLString: KeyVal := TValue.From<string>(KeyName);
        tkInteger: KeyVal := TValue.From<Integer>(StrToIntDef(KeyName, 0));
        tkInt64: KeyVal := TValue.From<Int64>(StrToInt64Def(KeyName, 0));
        else KeyVal := TValue.Empty;
      end;

      if KeyVal.IsEmpty then Continue;

      // Value conversion
      Node := AJson.GetNode(KeyName);
      if (Node <> nil) and (Node.GetNodeType = jntObject) then
      begin
        if (ValueType.Kind = tkClass) or (ValueType.Kind = tkInterface) then
          ValVal := DeserializeObject(Node as IDextJsonObject, ValueType)
        else if ValueType.Kind = tkRecord then
          ValVal := DeserializeRecord(Node as IDextJsonObject, ValueType)
        else ValVal := TValue.Empty;
      end
      else if (Node <> nil) and (Node.GetNodeType = jntArray) then
      begin
        if IsArrayType(ValueType) then ValVal := DeserializeArray(Node as IDextJsonArray, ValueType)
        else if IsListType(ValueType) then ValVal := DeserializeList(Node as IDextJsonArray, ValueType)
        else ValVal := TValue.Empty;
      end
      else if (Node <> nil) then
      begin
        case ValueType.Kind of
          tkInteger: ValVal := TValue.From<Integer>(Node.AsInteger);
          tkInt64: ValVal := TValue.From<Int64>(Node.AsInt64);
          tkFloat: ValVal := TValue.From<Double>(Node.AsDouble);
          tkString, tkLString, tkWString, tkUString: ValVal := TValue.From<string>(Node.AsString);
          tkEnumeration:
            if ValueType = TypeInfo(Boolean) then ValVal := TValue.From<Boolean>(Node.AsBoolean)
            else ValVal := TValue.Empty;
          else ValVal := TValue.Empty;
        end;
      end;

      if not ValVal.IsEmpty then
      begin
        if Assigned(InstObj) and (AddMethod.Parent.IsInstance) then
          TargetInst := InstObj
        else
          TargetInst := Result;

        AddMethod.Invoke(TargetInst, [KeyVal, ValVal]);
      end;
    end;
  finally
  end;
end;


function TDextSerializer.SerializeArray(const AValue: TValue): IDextJsonArray;
var
  ElementType: PTypeInfo;
  I, Count: Integer;
  ElementValue: TValue;
begin
  Result := TDextJson.Provider.CreateArray;

  ElementType := GetArrayElementType(AValue.TypeInfo);
  Count := AValue.GetArrayLength;

  for I := 0 to Count - 1 do
  begin
    ElementValue := AValue.GetArrayElement(I);

    case ElementType.Kind of
      tkInteger:
        Result.Add(ElementValue.AsInteger);
      tkInt64:
        Result.Add(ElementValue.AsInt64);
      tkFloat:
        if ElementType = TypeInfo(TDateTime) then
          Result.Add(FormatDateTime(FSettings.DateFormat, ElementValue.AsExtended))
        else
          Result.Add(ElementValue.AsExtended);
      tkString, tkLString, tkWString, tkUString:
        Result.Add(ElementValue.AsString);
      tkEnumeration:
        if ElementType = TypeInfo(Boolean) then
          Result.Add(ElementValue.AsBoolean)
        else
          Result.Add(GetEnumName(ElementType, ElementValue.AsOrdinal));
      tkRecord:
        if ElementType = TypeInfo(TGUID) then
          Result.Add(GetGUIDString(ElementValue))
        else if ElementType = TypeInfo(TUUID) then
          Result.Add(GetUUIDString(ElementValue))
        else
          Result.Add(SerializeRecord(ElementValue));
      tkClass:
        begin
          if ElementValue.AsObject = nil then
            Result.AddNull
          else
            Result.Add(SerializeObject(ElementValue));
        end;
      tkDynArray:
        Result.Add(SerializeArray(ElementValue));
    else
      Result.AddNull;
    end;
  end;
end;


function TDextSerializer.SerializeList(const AValue: TValue): IDextJsonArray;
var
  Count: Integer;
  CountMethod, GetItemMethod: TRttiMethod;
  CountProp: TRttiProperty;
  ElementValue: TValue;
  I: Integer;
  Instance: TObject;
  IntfValue: IInterface;
  RttiType: TRttiType;
begin
  Result := TDextJson.Provider.CreateArray;
  if AValue.IsEmpty then Exit;

  RttiType := TActivator.GetRttiContext.GetType(AValue.TypeInfo);

  // For interfaces, we need to get the interface value
  if AValue.Kind = tkInterface then
  begin
    IntfValue := AValue.AsInterface;
    if IntfValue = nil then Exit;

    // Try to get Count via GetCount method instead of property
    CountMethod := RttiType.GetMethod('GetCount');
    if not Assigned(CountMethod) then Exit;

    Count := CountMethod.Invoke(AValue, []).AsInteger;

    // Get the GetItem method
    GetItemMethod := RttiType.GetMethod('GetItem');
    if not Assigned(GetItemMethod) then Exit;

    for I := 0 to Count - 1 do
    begin
      ElementValue := GetItemMethod.Invoke(AValue, [I]);

      if ElementValue.IsEmpty then
      begin
        Result.AddNull;
        Continue;
      end;

      case ElementValue.TypeInfo.Kind of
        tkRecord:
          if ElementValue.TypeInfo = TypeInfo(TGUID) then
            Result.Add(GetGUIDString(ElementValue))
          else if ElementValue.TypeInfo = TypeInfo(TUUID) then
            Result.Add(GetUUIDString(ElementValue))
          else
            Result.Add(SerializeRecord(ElementValue));
        tkClass:
          begin
            if ElementValue.AsObject = nil then
              Result.AddNull
            else
              Result.Add(SerializeObject(ElementValue));
          end;
        tkDynArray:
          Result.Add(SerializeArray(ElementValue));
        tkInteger, tkInt64:
          Result.Add(ElementValue.AsInt64);
        tkFloat:
          Result.Add(ElementValue.AsExtended);
        tkString, tkLString, tkWString, tkUString:
          Result.Add(ElementValue.AsString);
        tkEnumeration:
          if ElementValue.TypeInfo = TypeInfo(Boolean) then
            Result.Add(ElementValue.AsBoolean)
          else
            Result.Add(GetEnumName(ElementValue.TypeInfo, ElementValue.AsOrdinal));
      else
        Result.AddNull;
      end;
    end;
  end
  else if AValue.Kind = tkClass then
  begin
    // For classes, use the original RTTI approach
    Instance := AValue.AsObject;
    if Instance = nil then Exit;

    CountProp := RttiType.GetProperty('Count');
    if not Assigned(CountProp) then Exit;

    Count := CountProp.GetValue(Instance).AsInteger;

    GetItemMethod := RttiType.GetMethod('GetItem');
    if not Assigned(GetItemMethod) then
      GetItemMethod := RttiType.GetMethod('Items');

    if Assigned(GetItemMethod) then
    begin
      for I := 0 to Count - 1 do
      begin
        ElementValue := GetItemMethod.Invoke(Instance, [I]);

        case ElementValue.TypeInfo.Kind of
          tkRecord:
            if ElementValue.TypeInfo = TypeInfo(TGUID) then
              Result.Add(GetGUIDString(ElementValue))
            else if ElementValue.TypeInfo = TypeInfo(TUUID) then
              Result.Add(GetUUIDString(ElementValue))
            else
              Result.Add(SerializeRecord(ElementValue));
          tkClass:
            begin
              if ElementValue.AsObject = nil then
                Result.AddNull
              else
                Result.Add(SerializeObject(ElementValue));
            end;
          tkDynArray:
            Result.Add(SerializeArray(ElementValue));
          tkInteger, tkInt64:
            Result.Add(ElementValue.AsInt64);
          tkFloat:
            Result.Add(ElementValue.AsExtended);
          tkString, tkLString, tkWString, tkUString:
            Result.Add(ElementValue.AsString);
          tkEnumeration:
            if ElementValue.TypeInfo = TypeInfo(Boolean) then
              Result.Add(ElementValue.AsBoolean)
            else
              Result.Add(GetEnumName(ElementValue.TypeInfo, ElementValue.AsOrdinal));
        else
          Result.AddNull;
        end;
      end;
    end;
  end;
end;

function TDextSerializer.ApplyCaseStyle(const AName: string): string;
begin
  Result := TJsonUtils.ApplyCaseStyle(AName, FSettings.CaseStyle);
end;

{ TJsonBuilder }

constructor TJsonBuilder.Create;
begin
  inherited Create;
  FNodeStack := TCollections.CreateList<TBuilderNode>;

  FRoot := TBuilderNode.Create;
  FRoot.NodeType := ntObject;
  FRoot.JsonObj := TDextJson.Provider.CreateObject;
  FRoot.Parent := nil;

  FCurrent := FRoot;
  FNodeStack.Add(FRoot);
end;

destructor TJsonBuilder.Destroy;
var
  Node: TBuilderNode;
begin
  for Node in FNodeStack do
    Node.Free;
  FNodeStack := nil;
  inherited;
end;
function TJsonBuilder.GetCurrentObject: IDextJsonObject;
begin
  if FCurrent.NodeType = ntObject then
    Result := FCurrent.JsonObj
  else
    raise EDextJsonException.Create('Current context is not an object');
end;

function TJsonBuilder.GetCurrentArray: IDextJsonArray;
begin
  if FCurrent.NodeType = ntArray then
    Result := FCurrent.JsonArr
  else
    raise EDextJsonException.Create('Current context is not an array');
end;

function TJsonBuilder.Add(const AKey, AValue: string): TJsonBuilder;
begin
  GetCurrentObject.SetString(AKey, AValue);
  Result := Self;
end;

function TJsonBuilder.Add(const AKey: string; AValue: Integer): TJsonBuilder;
begin
  GetCurrentObject.SetInteger(AKey, AValue);
  Result := Self;
end;

function TJsonBuilder.Add(const AKey: string; AValue: Int64): TJsonBuilder;
begin
  GetCurrentObject.SetInt64(AKey, AValue);
  Result := Self;
end;

function TJsonBuilder.Add(const AKey: string; AValue: Double): TJsonBuilder;
begin
  GetCurrentObject.SetDouble(AKey, AValue);
  Result := Self;
end;

function TJsonBuilder.Add(const AKey: string; AValue: Boolean): TJsonBuilder;
begin
  GetCurrentObject.SetBoolean(AKey, AValue);
  Result := Self;
end;

function TJsonBuilder.AddObject(const AKey: string): TJsonBuilder;
var
  NewNode: TBuilderNode;
  NewObj: IDextJsonObject;
begin
  NewObj := TDextJson.Provider.CreateObject;
  GetCurrentObject.SetObject(AKey, NewObj);

  NewNode := TBuilderNode.Create;
  NewNode.NodeType := ntObject;
  NewNode.JsonObj := NewObj;
  NewNode.Parent := FCurrent;
  NewNode.Key := AKey;

  FNodeStack.Add(NewNode);
  FCurrent := NewNode;
  Result := Self;
end;

function TJsonBuilder.EndObject: TJsonBuilder;
begin
  if FCurrent.Parent = nil then
    raise EDextJsonException.Create('Cannot end root object');

  FCurrent := FCurrent.Parent;
  Result := Self;
end;

function TJsonBuilder.AddArray(const AKey: string): TJsonBuilder;
var
  NewNode: TBuilderNode;
  NewArr: IDextJsonArray;
begin
  NewArr := TDextJson.Provider.CreateArray;
  GetCurrentObject.SetArray(AKey, NewArr);

  NewNode := TBuilderNode.Create;
  NewNode.NodeType := ntArray;
  NewNode.JsonArr := NewArr;
  NewNode.Parent := FCurrent;
  NewNode.Key := AKey;

  FNodeStack.Add(NewNode);
  FCurrent := NewNode;
  Result := Self;
end;

function TJsonBuilder.EndArray: TJsonBuilder;
begin
  if FCurrent.Parent = nil then
    raise EDextJsonException.Create('Cannot end root array');

  FCurrent := FCurrent.Parent;
  Result := Self;
end;

function TJsonBuilder.AddValue(const AValue: string): TJsonBuilder;
begin
  GetCurrentArray.Add(AValue);
  Result := Self;
end;

function TJsonBuilder.AddValue(AValue: Integer): TJsonBuilder;
begin
  GetCurrentArray.Add(AValue);
  Result := Self;
end;

function TJsonBuilder.AddValue(AValue: Boolean): TJsonBuilder;
begin
  GetCurrentArray.Add(AValue);
  Result := Self;
end;

function TJsonBuilder.ToString: string;
begin
  Result := FRoot.JsonObj.ToJson(False);
end;

function TJsonBuilder.ToIndentedString: string;
begin
  Result := FRoot.JsonObj.ToJson(True);
end;

class function TJsonBuilder.NewBuilder: TJsonBuilder;
begin
  Result := TJsonBuilder.Create;
end;

initialization

finalization
  TDextJson.FInterfaceMappings := nil;

end.
