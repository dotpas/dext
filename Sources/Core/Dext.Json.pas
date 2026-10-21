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
  ///   When [JsonIgnore] applies.
  /// </summary>
  {$SCOPEDENUMS ON}
  TJsonIgnoreMode = (
    /// <summary>Neither written nor read (the default).</summary>
    Always,
    /// <summary>Not written, read: a value that comes in and never goes back out (a password).</summary>
    OnWrite,
    /// <summary>Written, not read: a value the server decides (who created the row, a computed total).</summary>
    OnRead
  );
  {$SCOPEDENUMS OFF}

  /// <summary>
  ///   Indicates that a field should be ignored during serialization and
  ///   deserialization, or in one direction only with a TJsonIgnoreMode:
  ///   [JsonIgnore(TJsonIgnoreMode.OnRead)].
  /// </summary>
  JsonIgnoreAttribute = class(DextJsonAttribute)
  private
    FMode: TJsonIgnoreMode;
  public
    constructor Create; overload;
    constructor Create(AMode: TJsonIgnoreMode); overload;
    /// <summary>True when the member is not written to the JSON.</summary>
    function IgnoresWrite: Boolean;
    /// <summary>True when the member is not read from the JSON.</summary>
    function IgnoresRead: Boolean;
    property Mode: TJsonIgnoreMode read FMode;
  end;

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
    /// <summary>True for TDateTime, TDate and TTime.</summary>
    class function IsDateType(AType: PTypeInfo): Boolean; static;
    /// <summary>
    ///   The JSON text of a date, the same on every path. With
    ///   TDateFormat.ISO8601 (the default) the standard (RFC 3339 / ISO 8601):
    ///   a TDateTime is the local time with its UTC offset
    ///   ("2026-07-15T10:30:00.000+02:00", Dext.Core.DateUtils.FormatJsonDateTime),
    ///   a TDate the calendar day ("2026-07-15"), a TTime the wall clock
    ///   ("10:30:00.000"). Otherwise FormatDateTime(ASettings.DateFormat), as
    ///   before (records write TDateFormat.UnixTimestamp as a number).
    /// </summary>
    class function DateToJsonText(const AValue: TDateTime; AType: PTypeInfo;
      const ASettings: TJsonSettings): string; static;
    /// <summary>
    ///   True when a date is written as null: a TDateTime or TDate that is 0
    ///   ("no date") with ZeroDateAsNull, the default, or one of the
    ///   NullDates. A TTime never is: 0 is midnight there. Every path that
    ///   writes a date asks this first.
    /// </summary>
    class function IsNoDate(const AValue: TDateTime; AType: PTypeInfo;
      const ASettings: TJsonSettings): Boolean; static; inline;
    /// <summary>
    ///   Reads a JSON date for a TDateTime, TDate or TTime: the standard forms
    ///   first (a 'Z' or an offset is converted to local time, no zone is local
    ///   time; Dext.Core.DateUtils.TryParseJsonDateTime / TryParseJsonTime),
    ///   then the other forms TryParseCommonDate knows. A TDate keeps the day,
    ///   a TTime the time of day.
    /// </summary>
    class function TryJsonTextToDate(const AText: string; AType: PTypeInfo;
      out AValue: TDateTime): Boolean; static;
    class function ToPascalCase(const S: string): string; static;
    class function ToSnakeCase(const S: string): string; static;
    class function ApplyCaseStyle(const S: string; Style: TCaseStyle): string; static;
    /// <summary>
    ///   True when a [JsonFormat] date format can be read back: made of
    ///   yyyy yy mm m dd d hh h nn n ss s zzz z and of fixed text (in quotes,
    ///   or characters that are not letters). Month and day names, am/pm and
    ///   the other FormatDateTime letters are written but cannot be read.
    /// </summary>
    class function IsReadableDateFormat(const AFormat: string): Boolean; static;
    /// <summary>
    ///   Reads AText with a [JsonFormat] date format (see
    ///   IsReadableDateFormat): the digits of each part, the fixed text equal.
    ///   A part the format does not have takes the value of 1899-12-30 00:00.
    ///   False when the text does not match or is not a valid date or time.
    /// </summary>
    class function TryParseDateWithFormat(const AText, AFormat: string;
      out AValue: TDateTime): Boolean; static;
    ///   The JSON name of a record field under SmartRecordMapping. A backing
    ///   field, 'F' followed by an uppercase letter or '_' (FName, FValue,
    ///   F_Note), loses the 'F'; any other name is left as it is (Flag,
    ///   Format, Fee, Fattura). One rule for the record plan and GetFieldName.
    /// </summary>
    class function SmartRecordFieldName(const AName: string): string; static;
    /// <summary>
    ///   True for a byte array: TBytes, TArray&lt;Byte&gt; or any other
    ///   dynamic array of Byte. In JSON it is binary data, written as Base64.
    /// </summary>
    class function IsBytesType(AType: PTypeInfo): Boolean; static;
    /// <summary>
    ///   Base64 on one line, with padding (RFC 4648, TNetEncoding.Base64String):
    ///   not the MIME form, which breaks the line every 76 characters.
    /// </summary>
    class function BytesToBase64(const ABytes: TBytes): string; overload; static;
    class function BytesToBase64(AData: Pointer; ASize: Integer): string; overload; static;
    /// <summary>
    ///   Base64 (RFC 4648) to bytes. Also accepted: without the final '=',
    ///   with line breaks and spaces (the MIME form), and the URL alphabet
    ///   ('-' and '_'). False for any other character, the two alphabets
    ///   mixed, a '=' that is not at the end, or an impossible length, so
    ///   that a text that is not Base64 is not turned into random bytes.
    ///   An empty text is an empty array.
    /// </summary>
    class function TryBase64ToBytes(const AText: string; out ABytes: TBytes): Boolean; static;
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
    /// <summary>A byte array (TJsonUtils.IsBytesType): Base64.</summary>
    skBytes,
    skInterface,
    skUnknown
  );

  /// <summary>
  ///   The format attributes of a field or property: [JsonFormat],
  ///   [JsonString], [JsonNumber], [JsonBoolean] (#262). They work the same on
  ///   classes and records, when writing and when reading; the plan checks
  ///   them when it is built (Validate).
  /// </summary>
  TJsonFieldFormat = record
    /// <summary>[JsonFormat]: the date/time format, '' when not set.</summary>
    Format: string;
    /// <summary>[JsonString]: a number or a Boolean written as a string.</summary>
    AsString: Boolean;
    /// <summary>[JsonNumber]: a string written as a number.</summary>
    AsNumber: Boolean;
    /// <summary>[JsonBoolean]: an integer written as true/false.</summary>
    AsBoolean: Boolean;
    /// <summary>True when one of the four attributes is present.</summary>
    function IsSet: Boolean; inline;
    /// <summary>The format attributes among AAttributes.</summary>
    class function FromAttributes(const AAttributes: TArray<TCustomAttribute>)
      : TJsonFieldFormat; static;
    /// <summary>
    ///   Raises EDextJsonException when the attributes cannot work on AType:
    ///   more than one of them, [JsonFormat] not on a date or with a format
    ///   that cannot be read back, [JsonString] not on a number or Boolean,
    ///   [JsonNumber] not on a string, [JsonBoolean] not on an integer.
    /// </summary>
    procedure Validate(AType: PTypeInfo; const AOwner, AMember: string);
  end;

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
    /// <summary>
    ///   [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262). A
    ///   property with one of them is not on the direct path.
    /// </summary>
    Format: TJsonFieldFormat;
  end;
  PSerializationPlanItem = ^TSerializationPlanItem;

  TRecordPlanItem = record
    OriginalFieldName: string;
    CustomName: string;
    ResolvedNames: array[TCaseStyle, Boolean] of string;
    Field: TRttiField;
    Kind: TSerializeKind;
    IsSmartProp: Boolean;
    /// <summary>[JsonFormat], [JsonString], [JsonNumber], [JsonBoolean].</summary>
    Format: TJsonFieldFormat;
    FieldTypeInfo: PTypeInfo;
    /// <summary>[JsonIgnore(OnWrite)]: read, not written.</summary>
    IgnoreOnWrite: Boolean;
    /// <summary>[JsonIgnore(OnRead)]: written, not read.</summary>
    IgnoreOnRead: Boolean;
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
    /// <summary>[JsonPublishedOnly] on the class or on an ancestor: reading
    ///   uses it too.</summary>
    PublishedOnly: Boolean;
  end;
  PSerializationPlan = ^TSerializationPlan;

  /// <summary>
  ///   Internal class responsible for complex conversion logic.
  ///   Manages type mapping, RTTI, attributes, and List/Dictionary conversion.
  /// </summary>
  TDextSerializer = class
  private
    // One TObjectDictionary<PTypeInfo, TObject> wrapping TSerializationPlan
    // per case style: the JSON names in a plan depend on it
    class var FPlanCaches: array[TCaseStyle] of TObject;
    class var FPlanLock: TObject;   // TCriticalSection for thread-safe plan creation
    class var FRecordPlanCache: TObject; // TObjectDictionary<PTypeInfo, TObject> wrapping TRecordPlan
    class var FRecordPlanLock: TObject;  // TCriticalSection for thread-safe record plan creation
    class constructor Create;
    class destructor Destroy;
  private
    FSettings: TJsonSettings;
    function CreateInstanceForDeserialization(AType: PTypeInfo): TValue;
    function GetOrBuildPlan(AType: PTypeInfo): PSerializationPlan;
    /// <summary>
    ///   Writes AValue with its format attributes (#262): [JsonFormat] with the
    ///   invariant settings, [JsonString] as a string, [JsonNumber] as a
    ///   number (empty text as null, text that is not a number as it is),
    ///   [JsonBoolean] as true/false.
    /// </summary>
    procedure WriteFormattedValue(const AObj: IDextJsonObject; const AName: string;
      const AValue: TValue; AType: PTypeInfo; const AFormat: TJsonFieldFormat);
    /// <summary>
    ///   Reads ANode with its format attributes (#262). False when the node is
    ///   in the normal form (a number for [JsonString], a standard date for
    ///   [JsonFormat]...): the normal reading takes it, so both forms are read.
    /// </summary>
    function ReadFormattedValue(const ANode: IDextJsonNode; AType: PTypeInfo;
      const AFormat: TJsonFieldFormat; out AValue: TValue): Boolean;
    function GetOrBuildRecordPlan(AType: PTypeInfo): PRecordPlan;
    function ResolveFieldName(Item: PRecordPlanItem): string;
    function SerializeObjectWithPlan(Obj: TObject; const Plan: TSerializationPlan): IDextJsonObject;
    function TryReadBytesRoot(const AJson: string; AType: PTypeInfo; out AValue: TValue): Boolean;
    function ParseJson(const AJson: string): IDextJsonNode;
  protected
    function GetFieldName(AField: TRttiField): string;
    function GetRecordName(ARttiType: TRttiType): string;
    function SerializeRecord(const AValue: TValue): IDextJsonObject;
    function SerializeObject(const AValue: TValue): IDextJsonObject;
    function ShouldSkipField(AField: TRttiField; const AValue: TValue): Boolean;
    // A date member or array element: null when TJsonUtils.IsNoDate, else the text
    procedure SetDateMember(const AObj: IDextJsonObject; const AName: string;
      const AValue: TDateTime; AType: PTypeInfo);
    procedure AddDateElement(const AArray: IDextJsonArray; const AValue: TDateTime;
      AType: PTypeInfo);

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
  System.NetEncoding,
  System.SyncObjs,
  System.Variants,
  Dext.Core.Reflection,
  Dext.Core.DateUtils,
  Dext.Json.Utf8,
  Dext.Core.Json.NextGen, // Default driver NextGen
  Dext.Json.Driver.DextJsonDataObjects;

type
  TRecordCacheEntry = record
    TypeInfo: PTypeInfo;
    Plan: PRecordPlan;
  end;

  /// <summary>
  ///   Wrapper object to store a TSerializationPlan inside TObjectDictionary.
  ///   The JSON names of a plan depend on the case style, so a plan belongs
  ///   to a class AND a case style: both are kept here, next to the plan.
  /// </summary>
  TSerializationPlanHolder = class
  public
    TypeInfo: PTypeInfo;
    CaseStyle: TCaseStyle;
    Plan: TSerializationPlan;
  end;

var
  GRecordPlanCache: array[0..15] of TRecordCacheEntry;
  // A slot is a single pointer, written in one store: a reader sees either
  // the old holder or the new one, never the type of one with the plan of
  // the other.
  GClassPlanCache: array[0..15] of TSerializationPlanHolder;
  GRecordCacheIdx: Integer = 0;
  GClassCacheIdx: Integer = 0;

const
  ValueField = 'value';

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

class function TJsonUtils.IsDateType(AType: PTypeInfo): Boolean;
begin
  Result := (AType = TypeInfo(TDateTime)) or (AType = TypeInfo(TDate)) or
    (AType = TypeInfo(TTime));
end;

class function TJsonUtils.IsNoDate(const AValue: TDateTime; AType: PTypeInfo;
  const ASettings: TJsonSettings): Boolean;
begin
  // The list is looked at only when there is one: the default costs a nil check
  Result := (AType <> TypeInfo(TTime)) and
    (((AValue = 0) and ASettings.FZeroDateAsNull) or
     ((ASettings.FNullDates <> nil) and ASettings.IsNullDate(AValue)));
end;

class function TJsonUtils.DateToJsonText(const AValue: TDateTime; AType: PTypeInfo;
  const ASettings: TJsonSettings): string;
begin
  if ASettings.DateFormatStyle <> TDateFormat.ISO8601 then
    Result := FormatDateTime(ASettings.DateFormat, AValue)
  else if AType = TypeInfo(TDate) then
    Result := FormatJsonDate(AValue)
  else if AType = TypeInfo(TTime) then
    Result := FormatJsonTime(AValue)
  else
    Result := FormatJsonDateTime(AValue);
end;

class function TJsonUtils.TryJsonTextToDate(const AText: string; AType: PTypeInfo;
  out AValue: TDateTime): Boolean;
begin
  if AType = TypeInfo(TTime) then
    Result := TryParseJsonTime(AText, AValue)
  else
    Result := TryParseJsonDateTime(AText, AValue);
  if not Result then
    Result := TryParseCommonDate(AText, AValue);
  if not Result then
    Exit;
  if AType = TypeInfo(TDate) then
    AValue := Trunc(AValue)
  else if AType = TypeInfo(TTime) then
    AValue := Frac(AValue);
end;

// A JSON string read into a TDateTime, TDate or TTime of type AType;
// EDextJsonException when it is not a date.
function DateValueFromJsonText(const AText: string; AType: PTypeInfo): TValue;
var
  D: TDateTime;
begin
  if not TJsonUtils.TryJsonTextToDate(AText, AType, D) then
    raise EDextJsonException.CreateFmt('"%s" is not a date', [AText]);
  TValue.Make(@D, AType, Result);
end;

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

{ TJsonFieldFormat }

function TJsonFieldFormat.IsSet: Boolean;
begin
  Result := (Format <> '') or AsString or AsNumber or AsBoolean;
end;

class function TJsonFieldFormat.FromAttributes(
  const AAttributes: TArray<TCustomAttribute>): TJsonFieldFormat;
var
  Attr: TCustomAttribute;
begin
  Result := Default(TJsonFieldFormat);
  for Attr in AAttributes do
    if Attr is JsonFormatAttribute then
      Result.Format := JsonFormatAttribute(Attr).Format
    else if Attr is JsonStringAttribute then
      Result.AsString := True
    else if Attr is JsonNumberAttribute then
      Result.AsNumber := True
    else if Attr is JsonBooleanAttribute then
      Result.AsBoolean := True;
end;

procedure TJsonFieldFormat.Validate(AType: PTypeInfo; const AOwner, AMember: string);

  procedure Refuse(const AAttribute, ATypes: string);
  begin
    raise EDextJsonException.CreateFmt('%s.%s: %s applies to %s only',
      [AOwner, AMember, AAttribute, ATypes]);
  end;

var
  IsDate, IsInt, IsNum, IsText: Boolean;
begin
  if Ord(Format <> '') + Ord(AsString) + Ord(AsNumber) + Ord(AsBoolean) > 1 then
    raise EDextJsonException.CreateFmt('%s.%s: [JsonFormat], [JsonString], ' +
      '[JsonNumber] and [JsonBoolean] exclude each other: one per member',
      [AOwner, AMember]);
  IsDate := TJsonUtils.IsDateType(AType);
  IsInt := (AType <> nil) and (AType^.Kind in [tkInteger, tkInt64]);
  IsNum := IsInt or ((AType <> nil) and (AType^.Kind = tkFloat) and not IsDate) or
    (AType = TypeInfo(Boolean));
  IsText := (AType <> nil) and (AType^.Kind in [tkString, tkLString, tkWString, tkUString]);
  if (Format <> '') and not IsDate then
    Refuse('[JsonFormat]', 'TDateTime, TDate and TTime');
  if (Format <> '') and not TJsonUtils.IsReadableDateFormat(Format) then
    raise EDextJsonException.CreateFmt('%s.%s: the [JsonFormat] format ''%s'' ' +
      'cannot be read back (yyyy yy mm m dd d hh h nn n ss s zzz z and fixed text)',
      [AOwner, AMember, Format]);
  if AsString and not IsNum then
    Refuse('[JsonString]', 'integers, floats, Currency and Boolean');
  if AsNumber and not IsText then
    Refuse('[JsonNumber]', 'strings');
  if AsBoolean and not IsInt then
    Refuse('[JsonBoolean]', 'integers');
end;

// The next part of a [JsonFormat] date format: a run of the same letter
// (lowercase, in AToken) or fixed text (in ALiteral: a quoted string, or one
// character that is not a letter).
function NextFormatPart(const AFormat: string; var P: Integer;
  out AToken, ALiteral: string): Boolean;
var
  C, Q: Char;
  Start: Integer;
begin
  Result := P <= Length(AFormat);
  if not Result then
    Exit;
  AToken := '';
  ALiteral := '';
  C := AFormat[P];
  if (C = '"') or (C = '''') then
  begin
    Q := C;
    Inc(P);
    Start := P;
    while (P <= Length(AFormat)) and (AFormat[P] <> Q) do
      Inc(P);
    ALiteral := Copy(AFormat, Start, P - Start);
    Inc(P); // the closing quote
    Exit;
  end;
  // A letter is always a placeholder for FormatDateTime (also c, t, a...):
  // fixed text that is a letter goes in quotes.
  if CharInSet(C, ['A'..'Z', 'a'..'z']) then
  begin
    Start := P;
    while (P <= Length(AFormat)) and (UpCase(AFormat[P]) = UpCase(C)) do
      Inc(P);
    AToken := LowerCase(Copy(AFormat, Start, P - Start));
    Exit;
  end;
  ALiteral := C;
  Inc(P);
end;

class function TJsonUtils.IsReadableDateFormat(const AFormat: string): Boolean;
var
  P: Integer;
  Token, Literal: string;
begin
  Result := AFormat <> '';
  P := 1;
  while Result and NextFormatPart(AFormat, P, Token, Literal) do
    if Token <> '' then
      Result := (Token = 'yyyy') or (Token = 'yy') or (Token = 'mm') or
        (Token = 'm') or (Token = 'dd') or (Token = 'd') or (Token = 'hh') or
        (Token = 'h') or (Token = 'nn') or (Token = 'n') or (Token = 'ss') or
        (Token = 's') or (Token = 'zzz') or (Token = 'z');
end;

class function TJsonUtils.TryParseDateWithFormat(const AText, AFormat: string;
  out AValue: TDateTime): Boolean;
var
  P, T, Digits, MaxDigits, V, I: Integer;
  Token, Literal: string;
  Y, M, D, H, N, S, Z: Integer;
  DatePart, TimePart: TDateTime;
begin
  Result := False;
  if not IsReadableDateFormat(AFormat) then
    Exit;
  Y := 1899;
  M := 12;
  D := 30;
  H := 0;
  N := 0;
  S := 0;
  Z := 0;
  P := 1;
  T := 1;
  while NextFormatPart(AFormat, P, Token, Literal) do
  begin
    if Token = '' then
    begin
      // the fixed text must be there, equal
      for I := 1 to Length(Literal) do
      begin
        if (T > Length(AText)) or (AText[T] <> Literal[I]) then
          Exit;
        Inc(T);
      end;
      Continue;
    end;
    // yyyy 4 digits, zzz 3, mm dd hh nn ss yy 2; m d h n s z one or more
    if Token = 'yyyy' then
      MaxDigits := 4
    else if (Token = 'zzz') or (Token = 'z') then
      MaxDigits := 3
    else
      MaxDigits := 2;
    Digits := 0;
    V := 0;
    while (T <= Length(AText)) and (Digits < MaxDigits) and
      CharInSet(AText[T], ['0'..'9']) do
    begin
      V := V * 10 + Ord(AText[T]) - Ord('0');
      Inc(T);
      Inc(Digits);
    end;
    if (Digits = 0) or ((Length(Token) > 1) and (Digits <> MaxDigits)) then
      Exit;
    case Token[1] of
      'y':
        if Token = 'yy' then
          Y := 2000 + V // as FormatDateTime writes two digits
        else
          Y := V;
      'm': M := V;
      'd': D := V;
      'h': H := V;
      'n': N := V;
      's': S := V;
      'z': Z := V;
    end;
  end;
  if T <= Length(AText) then
    Exit; // more text than the format
  if not TryEncodeDate(Y, M, D, DatePart) or not TryEncodeTime(H, N, S, Z, TimePart) then
    Exit;
  AValue := DatePart + TimePart;
  Result := True;
end;

class function TJsonUtils.SmartRecordFieldName(const AName: string): string;
begin
  if (AName.Length > 1) and (AName.Chars[0] = 'F') and
    CharInSet(AName.Chars[1], ['A'..'Z', '_']) then
    Result := AName.Substring(1)
  else
    Result := AName;
end;

class function TJsonUtils.IsBytesType(AType: PTypeInfo): Boolean;
var
  Element: PPTypeInfo;
begin
  Result := False;
  if (AType = nil) or (AType.Kind <> tkDynArray) then
    Exit;
  // The element itself (elType2 is not it for an array of arrays)
  Element := AType.TypeData^.DynArrElType;
  Result := (Element <> nil) and (Element^ = TypeInfo(Byte));
end;

class function TJsonUtils.BytesToBase64(const ABytes: TBytes): string;
begin
  Result := BytesToBase64(Pointer(ABytes), Length(ABytes));
end;

class function TJsonUtils.BytesToBase64(AData: Pointer; ASize: Integer): string;
{$IF CompilerVersion < 35.0}
var
  I, N: Integer;
{$ENDIF}
begin
  if (AData = nil) or (ASize <= 0) then
    Exit('');
{$IF CompilerVersion >= 35.0}
  Result := TNetEncoding.Base64String.EncodeBytesToString(AData, ASize);
{$ELSE}
  Result := TNetEncoding.Base64.EncodeBytesToString(AData, ASize);
  // Single-pass in-place strip of CRLF without double reallocation
  N := 0;
  for I := 1 to Length(Result) do
  begin
    if (Result[I] <> #13) and (Result[I] <> #10) then
    begin
      Inc(N);
      Result[N] := Result[I];
    end;
  end;
  SetLength(Result, N);
{$ENDIF}
end;

class function TJsonUtils.TryBase64ToBytes(const AText: string; out ABytes: TBytes): Boolean;
var
  Clean: string;
  I, N, Pads: Integer;
  C: Char;
  Standard, Url: Boolean;
begin
  ABytes := nil;
  Result := False;
  SetLength(Clean, Length(AText));
  N := 0;
  Pads := 0;
  Standard := False;
  Url := False;
  for I := 1 to Length(AText) do
  begin
    C := AText[I];
    // Line breaks and spaces (the MIME form) are skipped
    if C <= ' ' then
      Continue;
    if C = '=' then
    begin
      Inc(Pads);
      Continue;
    end;
    // After a '=' only other '=' (and spaces) may follow
    if Pads > 0 then
      Exit;
    case C of
      'A'..'Z', 'a'..'z', '0'..'9':
        ;
      '+', '/':
        Standard := True;
      '-':
        begin
          Url := True;
          C := '+';
        end;
      '_':
        begin
          Url := True;
          C := '/';
        end;
    else
      Exit;
    end;
    Inc(N);
    Clean[N] := C;
  end;
  // A group of 4 characters carries 3 bytes: a last group of 1 is impossible
  if (Standard and Url) or (Pads > 2) or (N mod 4 = 1) then
    Exit;
  SetLength(Clean, N);
  while Length(Clean) mod 4 <> 0 do
    Clean := Clean + '=';
{$IF CompilerVersion >= 35.0}
  ABytes := TNetEncoding.Base64String.DecodeStringToBytes(Clean);
{$ELSE}
  ABytes := TNetEncoding.Base64.DecodeStringToBytes(Clean);
{$ENDIF}
  Result := True;
end;

{ Byte arrays }

function BytesValueToBase64(const AValue: TValue): string;
var
  P: Pointer;
begin
  P := PPointer(AValue.GetReferenceToRawData)^;
  Result := TJsonUtils.BytesToBase64(P, DynArraySize(P));
end;

/// A byte array read from JSON: a Base64 string (TJsonUtils.TryBase64ToBytes)
/// or an array of numbers from 0 to 255, as it was written before. null is
/// no value (TValue.Empty). Anything else raises, naming the field.
function BytesFromJsonNode(const ANode: IDextJsonNode; AType: PTypeInfo;
  const AName: string): TValue;
var
  Bytes: TBytes;
  Arr: IDextJsonArray;
  Item: IDextJsonNode;
  I: Integer;
  V: Double;
  Where: string;
begin
  Result := TValue.Empty;
  if AName <> '' then
    Where := 'Field "' + AName + '": '
  else
    Where := '';
  case ANode.GetNodeType of
    jntNull:
      Exit;
    jntString:
      if not TJsonUtils.TryBase64ToBytes(ANode.AsString, Bytes) then
        raise EDextJsonException.Create(Where + 'the text is not Base64');
    jntArray:
      begin
        Arr := ANode as IDextJsonArray;
        SetLength(Bytes, Arr.GetCount);
        for I := 0 to Arr.GetCount - 1 do
        begin
          Item := Arr.GetNode(I);
          if (Item = nil) or (Item.GetNodeType <> jntNumber) then
            raise EDextJsonException.CreateFmt('%sitem %d is not a number from 0 to 255', [Where, I]);
          V := Item.AsDouble;
          if (V < 0) or (V > 255) or (Frac(V) <> 0) then
            raise EDextJsonException.CreateFmt('%sitem %d is not a number from 0 to 255', [Where, I]);
          Bytes[I] := Byte(Trunc(V));
        end;
      end;
  else
    raise EDextJsonException.Create(Where +
      'binary data must be a Base64 string or an array of numbers from 0 to 255');
  end;
  TValue.Make(@Bytes, AType, Result);
end;

{ JsonIgnoreAttribute }

constructor JsonIgnoreAttribute.Create;
begin
  Create(TJsonIgnoreMode.Always);
end;

constructor JsonIgnoreAttribute.Create(AMode: TJsonIgnoreMode);
begin
  inherited Create;
  FMode := AMode;
end;

function JsonIgnoreAttribute.IgnoresWrite: Boolean;
begin
  Result := FMode <> TJsonIgnoreMode.OnRead;
end;

function JsonIgnoreAttribute.IgnoresRead: Boolean;
begin
  Result := FMode <> TJsonIgnoreMode.OnWrite;
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
    // A byte array as the root: a Base64 string (an array goes on below)
    if Serializer.TryReadBytesRoot(AJson, AType, Result) then
      Exit;
    JsonNode := Serializer.ParseJson(AJson);
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
    JsonNode := Serializer.ParseJson(AJson);
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

// Reads an enum from its name or from its number, whatever EnumStyle wrote
// it. A number outside the enum raises: it would otherwise become a value the
// enum does not have.
function EnumFromJsonNode(AType: PTypeInfo; const ANode: IDextJsonNode): TValue;
var
  Data: PTypeData;
  N: Int64;
begin
  if ANode.GetNodeType = jntNumber then
  begin
    Data := GetTypeData(AType);
    N := ANode.AsInt64;
    if (N < Data^.MinValue) or (N > Data^.MaxValue) then
      raise EDextJsonException.CreateFmt('%d is not a value of %s',
        [N, GetTypeName(AType)]);
    Result := TValue.FromOrdinal(AType, N);
  end
  else
    Result := TValue.FromOrdinal(AType, GetEnumValue(AType, ANode.AsString));
end;

{ TDextSerializer }

type
  TRecordPlanHolder = class
  public
    Plan: TRecordPlan;
  end;

class constructor TDextSerializer.Create;
var
  Style: TCaseStyle;
begin
  for Style := Low(TCaseStyle) to High(TCaseStyle) do
    FPlanCaches[Style] := TObjectDictionary<PTypeInfo, TSerializationPlanHolder>.Create([doOwnsValues]);
  FPlanLock := TCriticalSection.Create;
  FRecordPlanCache := TObjectDictionary<PTypeInfo, TRecordPlanHolder>.Create([doOwnsValues]);
  FRecordPlanLock := TCriticalSection.Create;
end;

class destructor TDextSerializer.Destroy;
var
  Style: TCaseStyle;
begin
  for Style := Low(TCaseStyle) to High(TCaseStyle) do
    FreeAndNil(FPlanCaches[Style]);
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
  Style: TCaseStyle;
  Slot: TSerializationPlanHolder;
begin
  // The plan holds the JSON names, so it is looked up by class AND case style
  Style := FSettings.CaseStyle;

  // Lock-free slot cache lookup
  for I := 0 to 15 do
  begin
    Slot := GClassPlanCache[I];
    if (Slot <> nil) and (Slot.TypeInfo = AType) and (Slot.CaseStyle = Style) then
      Exit(@Slot.Plan);
  end;

  Cache := TObjectDictionary<PTypeInfo, TSerializationPlanHolder>(FPlanCaches[Style]);
  Lock := TCriticalSection(FPlanLock);

  // Fast path: plan already exists (lock-free read)
  Lock.Enter;
  try
    if Cache.TryGetValue(AType, Holder) then
    begin
      Result := @Holder.Plan;

      // Update lock-free cache slot
      Idx := TInterlocked.Increment(GClassCacheIdx) and 15;
      GClassPlanCache[Idx] := Holder;

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
  Holder.TypeInfo := AType;
  Holder.CaseStyle := Style;
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
  Holder.Plan.PublishedOnly := PublishedOnly;

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

    // Skip if has JsonIgnore attribute (unless it ignores only on read).
    // [NotMapped] is about the database only: it does not touch the JSON.
    ShouldSkip := False;
    for Attr in Prop.GetAttributes do
    begin
      if (Attr is JsonIgnoreAttribute) and JsonIgnoreAttribute(Attr).IgnoresWrite then
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

    // [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262): checked
    // when the plan is built; a formatted property leaves the direct path.
    Item.Format := TJsonFieldFormat.FromAttributes(Prop.GetAttributes);
    if Item.Format.IsSet then
    begin
      Item.Format.Validate(LTypeInfo, RttiType.Name, Prop.Name);
      Item.UseDirect := False;
    end;

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
        if TJsonUtils.IsBytesType(LTypeInfo) then
          Item.Kind := skBytes
        else
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
  GClassPlanCache[Idx] := Holder;
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

    // Check if has JsonIgnore attribute. The plan serves both directions: a
    // field ignored in one direction only stays, marked. [NotMapped] is about
    // the database only: it does not touch the JSON.
    Item := Default(TRecordPlanItem);
    for Attr in Field.GetAttributes do
    begin
      if Attr is JsonIgnoreAttribute then
      begin
        if JsonIgnoreAttribute(Attr).IgnoresWrite then
          Item.IgnoreOnWrite := True;
        if JsonIgnoreAttribute(Attr).IgnoresRead then
          Item.IgnoreOnRead := True;
      end;
    end;
    if Item.IgnoreOnWrite and Item.IgnoreOnRead then
      Continue;

    Item.OriginalFieldName := Field.Name;
    Item.Field := Field;
    Item.CustomName := '';

    for Attr in Field.GetAttributes do
    begin
      if Attr is JsonNameAttribute then
      begin
        Item.CustomName := JsonNameAttribute(Attr).Name;
      end;
    end;
    Item.Format := TJsonFieldFormat.FromAttributes(Field.GetAttributes);

    // Pre-resolve names for all case styles and smart mapping flags
    if Item.CustomName = '' then
    begin
      for Style := Low(TCaseStyle) to High(TCaseStyle) do
      begin
        for SmartMap := False to True do
        begin
          NameStr := Item.OriginalFieldName;
          if SmartMap then
            NameStr := TJsonUtils.SmartRecordFieldName(NameStr);
          
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
    if Item.Format.IsSet then
      Item.Format.Validate(LTypeInfo, RttiType.Name, Field.Name);

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
        if TJsonUtils.IsBytesType(LTypeInfo) then
          Item.Kind := skBytes
        else
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

procedure TDextSerializer.WriteFormattedValue(const AObj: IDextJsonObject;
  const AName: string; const AValue: TValue; AType: PTypeInfo;
  const AFormat: TJsonFieldFormat);
var
  Text: string;
  I64: Int64;
  F: Double;
begin
  if AFormat.Format <> '' then
    // The invariant settings: '/' and ':' stay as written in the format
    AObj.SetString(AName, FormatDateTime(AFormat.Format, AValue.AsExtended,
      TFormatSettings.Invariant))
  else if AFormat.AsString then
  begin
    if AType = TypeInfo(Boolean) then
      AObj.SetString(AName, BoolToStr(AValue.AsBoolean, True).ToLower)
    else if (AType <> nil) and (AType^.Kind in [tkInteger, tkInt64]) then
      AObj.SetString(AName, IntToStr(AValue.AsInt64))
    else if AType = TypeInfo(Currency) then
      AObj.SetString(AName, CurrToStr(AValue.AsCurrency, TFormatSettings.Invariant))
    else
      AObj.SetString(AName, FloatToStr(AValue.AsExtended, TFormatSettings.Invariant));
  end
  else if AFormat.AsNumber then
  begin
    // Empty text is null; text that is not a number is written as it is
    Text := Trim(AValue.AsString);
    if Text = '' then
      AObj.SetNull(AName)
    else if TryStrToInt64(Text, I64) then
      AObj.SetInt64(AName, I64)
    else if TryStrToFloat(Text, F, TFormatSettings.Invariant) then
      AObj.SetDouble(AName, F)
    else
      AObj.SetString(AName, AValue.AsString);
  end
  else // [JsonBoolean]: 0 is false, anything else true
    AObj.SetBoolean(AName, AValue.AsInt64 <> 0);
end;

function TDextSerializer.ReadFormattedValue(const ANode: IDextJsonNode;
  AType: PTypeInfo; const AFormat: TJsonFieldFormat; out AValue: TValue): Boolean;
var
  Text: string;
  D: TDateTime;
  I64: Int64;
  F: Double;
  C: Currency;
  Si: Single;
begin
  Result := False;
  AValue := TValue.Empty;
  if AType = nil then
    Exit;
  case ANode.GetNodeType of
    jntString:
      begin
        Text := ANode.AsString;
        if AFormat.Format <> '' then
        begin
          // The attribute's form; a standard date is read by the normal path
          if not TJsonUtils.TryParseDateWithFormat(Text, AFormat.Format, D) then
            Exit;
          if AType = TypeInfo(TDate) then
            D := Trunc(D)
          else if AType = TypeInfo(TTime) then
            D := Frac(D);
          TValue.Make(@D, AType, AValue);
          Result := True;
        end
        else if AFormat.AsString then
        begin
          Text := Trim(Text);
          if AType = TypeInfo(Boolean) then
          begin
            if SameText(Text, 'true') then
              AValue := TValue.From<Boolean>(True)
            else if SameText(Text, 'false') then
              AValue := TValue.From<Boolean>(False)
            else
              Exit;
          end
          else if AType^.Kind = tkInt64 then
          begin
            if not TryStrToInt64(Text, I64) then
              Exit;
            TValue.Make(@I64, AType, AValue);
          end
          else if AType^.Kind = tkInteger then
          begin
            if not TryStrToInt64(Text, I64) then
              Exit;
            AValue := TValue.FromOrdinal(AType, I64);
          end
          else if AType = TypeInfo(Currency) then
          begin
            if not TryStrToCurr(Text, C, TFormatSettings.Invariant) then
              Exit;
            TValue.Make(@C, AType, AValue);
          end
          else if AType = TypeInfo(Single) then
          begin
            if not TryStrToFloat(Text, F, TFormatSettings.Invariant) then
              Exit;
            Si := F;
            TValue.Make(@Si, AType, AValue);
          end
          else
          begin
            if not TryStrToFloat(Text, F, TFormatSettings.Invariant) then
              Exit;
            TValue.Make(@F, AType, AValue);
          end;
          Result := True;
        end;
      end;
    jntNumber:
      if AFormat.AsNumber then
      begin
        // A number for a string: its text, an integer without decimals
        F := ANode.AsDouble;
        if (Frac(F) = 0) and (Abs(F) < 1E15) then
          AValue := TValue.From<string>(IntToStr(ANode.AsInt64))
        else
          AValue := TValue.From<string>(FloatToStr(F, TFormatSettings.Invariant));
        Result := True;
      end;
    jntBoolean:
      if AFormat.AsBoolean then
      begin
        I64 := Ord(ANode.AsBoolean);
        if AType^.Kind = tkInt64 then
          TValue.Make(@I64, AType, AValue)
        else
          AValue := TValue.FromOrdinal(AType, I64);
        Result := True;
      end;
  end;
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

  // IgnoreDefaultValues: checked only when it is on, so the default path pays
  // nothing. "No date" (TJsonUtils.IsNoDate) is checked where a date is written.
  Defaults := FSettings.IgnoreDefaultValues;

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
            if FSettings.IgnoreDefaultValues and
              (TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset) = 0) then
              Continue;
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
          // A TDate or TTime on the direct path is a date, not a number
          if Item^.Kind = skDateTime then
            SetDateMember(Result, Item^.JsonName,
              TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset), Item^.ValueTypeInfo)
          else
            Result.SetDouble(Item^.JsonName, TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset));
        nkDateTime:
          SetDateMember(Result, Item^.JsonName,
            TDextDirectAccess.ReadDouble(Obj, Item^.DirectOffset), Item^.ValueTypeInfo);
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

    // Default values (same rules as ShouldSkipField for fields)
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
          if FSettings.IgnoreDefaultValues and (PropValue.AsExtended = 0) then
            Continue;
      end;

    // "No date": null, whatever the form the date would be written in
    if (Item^.Kind = skDateTime) and
      TJsonUtils.IsNoDate(PropValue.AsExtended, Item^.ValueTypeInfo, FSettings) then
    begin
      if not FSettings.FIgnoreNullValues then
        Result.SetNull(Item^.JsonName);
      Continue;
    end;

    // [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262)
    if Item^.Format.IsSet then
    begin
      WriteFormattedValue(Result, Item^.JsonName, PropValue, Item^.ValueTypeInfo,
        Item^.Format);
      Continue;
    end;

    // Dispatch based on pre-computed kind
    case Item^.Kind of
      skInteger:
        Result.SetInt64(Item^.JsonName, PropValue.AsInt64);
      skFloat:
        Result.SetDouble(Item^.JsonName, PropValue.AsExtended);
      skDateTime:
        Result.SetString(Item^.JsonName,
          TJsonUtils.DateToJsonText(PropValue.AsExtended, Item^.ValueTypeInfo, FSettings));
      skString:
        Result.SetString(Item^.JsonName, PropValue.AsString);
      skBoolean:
        Result.SetBoolean(Item^.JsonName, PropValue.AsBoolean);
      skEnumAsString, skEnumAsNumber:
        // The plan is cached per type and shared across settings, so the
        // style is read here, when writing.
        if FSettings.EnumStyle = TEnumStyle.AsNumber then
          Result.SetInt64(Item^.JsonName, PropValue.AsOrdinal)
        else
          Result.SetString(Item^.JsonName, GetEnumName(Item^.ValueTypeInfo, PropValue.AsOrdinal));
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
      skBytes:
        if FSettings.FBytesAsBase64 then
          Result.SetString(Item^.JsonName, BytesValueToBase64(PropValue))
        else
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

function TDextSerializer.ParseJson(const AJson: string): IDextJsonNode;
var
  Prov: IDextJsonProvider;
  NextGenProv: TNextGenJsonProvider;
  DataObjectsProv: TJsonDataObjectsProvider;
  OldDepth: Integer;
begin
  Prov := TDextJson.Provider;
  if FSettings.FMaxDepth <> 0 then
  begin
    if Prov is TNextGenJsonProvider then
    begin
      NextGenProv := TNextGenJsonProvider(Prov);
      OldDepth := NextGenProv.MaxDepth;
      NextGenProv.MaxDepth := FSettings.MaxDepth;
      try
        Result := NextGenProv.Parse(AJson);
      finally
        NextGenProv.MaxDepth := OldDepth;
      end;
      Exit;
    end
    else if Prov is TJsonDataObjectsProvider then
    begin
      DataObjectsProv := TJsonDataObjectsProvider(Prov);
      OldDepth := DataObjectsProv.MaxDepth;
      DataObjectsProv.MaxDepth := FSettings.MaxDepth;
      try
        Result := DataObjectsProv.Parse(AJson);
      finally
        DataObjectsProv.MaxDepth := OldDepth;
      end;
      Exit;
    end;
  end;
  Result := Prov.Parse(AJson);
end;

function TDextSerializer.Deserialize<T>(const AJson: string): T;
var
  JsonNode: IDextJsonNode;
  Value: TValue;
begin
  // A byte array as the root: a Base64 string (an array goes on below)
  if TryReadBytesRoot(AJson, TypeInfo(T), Value) then
    Exit(Value.AsType<T>);

  JsonNode := ParseJson(AJson);
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

function TDextSerializer.TryReadBytesRoot(const AJson: string; AType: PTypeInfo;
  out AValue: TValue): Boolean;
var
  S: string;
  Bytes: TBytes;
begin
  Result := False;
  if not TJsonUtils.IsBytesType(AType) then
    Exit;
  S := Trim(AJson);
  if (Length(S) < 2) or (S[1] <> '"') or (S[Length(S)] <> '"') then
    Exit;
  // Base64 has nothing to escape, but a writer may escape the '/' as '\/'
  S := StringReplace(Copy(S, 2, Length(S) - 2), '\/', '/', [rfReplaceAll]);
  if not TJsonUtils.TryBase64ToBytes(S, Bytes) then
    raise EDextJsonException.Create('the text is not Base64');
  TValue.Make(@Bytes, AType, AValue);
  Result := True;
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
  PublishedOnly: Boolean;
  IgnoreRead: Boolean;
  HasName: Boolean;
  PropAttrs: TArray<TCustomAttribute>;
  PropFormat: TJsonFieldFormat;
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
  // [JsonPublishedOnly] restricts reading as it restricts writing: the class
  // plan knows it.
  PublishedOnly := (AType <> nil) and (AType^.Kind = tkClass) and
    GetOrBuildPlan(AType)^.PublishedOnly;
  try
    for Prop in RttiType.GetProperties do
    begin
      if (Prop.Visibility <> mvPublic) and (Prop.Visibility <> mvPublished) then
        Continue;
      if PublishedOnly and (Prop.Visibility <> mvPublished) then
        Continue;

      if not Prop.IsWritable then
        Continue;

      PropName := ApplyCaseStyle(Prop.Name);

      // Check JsonName, and JsonIgnore unless it ignores only on write
      HasName := False;
      IgnoreRead := False;
      PropAttrs := Prop.GetAttributes;
      for Attr in PropAttrs do
        if (Attr is JsonNameAttribute) and not HasName then
        begin
          PropName := JsonNameAttribute(Attr).Name;
          HasName := True;
        end
        else if (Attr is JsonIgnoreAttribute) and JsonIgnoreAttribute(Attr).IgnoresRead then
          IgnoreRead := True;
      if IgnoreRead then
        Continue;
      // [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262)
      PropFormat := TJsonFieldFormat.FromAttributes(PropAttrs);

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
        // The format attributes first, before the direct path: the normal
        // form falls through to it. Not on a smart property (Prop<T>).
        if PropFormat.IsSet and not TReflection.IsSmartProp(Prop.PropertyType.Handle) and
          ReadFormattedValue(Node, Prop.PropertyType.Handle, PropFormat, Val) then
        begin
          Handler := TReflection.GetHandler(AType, Prop.Name);
          if Handler <> nil then
            Handler.SetValue(Instance, Val)
          else
            Prop.SetValue(Instance, Val);
          Continue;
        end;
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
                TDextDirectAccess.WriteDouble(Instance, DirectField.Offset,
                  DateValueFromJsonText(Node.AsString, TypeInfo(TDateTime)).AsExtended);
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
        // Binary data: a Base64 string, or an array of numbers from 0 to 255
        if TJsonUtils.IsBytesType(Prop.PropertyType.Handle) then
        begin
          Val := BytesFromJsonNode(Node, Prop.PropertyType.Handle, Prop.Name);
          if not Val.IsEmpty then
          begin
            if Handler <> nil then
              Handler.SetValue(Instance, Val)
            else
              Prop.SetValue(Instance, Val);
          end;
          Continue;
        end;
        case Node.GetNodeType of
          jntString:
            // A date: the standard forms, the zone converted to local time
            if TJsonUtils.IsDateType(Prop.PropertyType.Handle) then
              Val := DateValueFromJsonText(Node.AsString, Prop.PropertyType.Handle)
            else
              Val := TValue.From<string>(Node.AsString);
          jntNumber:
            begin
              case Prop.PropertyType.TypeKind of
                tkInteger:
                  Val := TValue.FromOrdinal(Prop.PropertyType.Handle, Node.AsInt64);
                tkInt64:
                  Val := Node.AsInt64;
                tkEnumeration:
                  // An enum written with EnumAsNumber. A name arrives as a
                  // string (jntString) and is converted by the handler.
                  if Prop.PropertyType.Handle <> TypeInfo(Boolean) then
                    Val := EnumFromJsonNode(Prop.PropertyType.Handle, Node);
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
    if Item^.IgnoreOnRead then
      Continue;

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

    // [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262); the
    // normal form is read below. Not on a smart property (Prop<T>).
    if Item^.Format.IsSet and not Item^.IsSmartProp and
      ReadFormattedValue(Node, Item^.FieldTypeInfo, Item^.Format, Val) then
    begin
      TReflection.SetValue(Result.GetReferenceToRawData, Item^.Field, Val);
      Continue;
    end;

    // Binary data: a Base64 string, or an array of numbers from 0 to 255
    if Item^.Kind = skBytes then
    begin
      TReflection.SetValue(Result.GetReferenceToRawData, Item^.Field,
        BytesFromJsonNode(Node, Item^.FieldTypeInfo, FieldName));
      Continue;
    end;

    case Node.GetNodeType of
      jntString:
        // A date: the standard forms, the zone converted to local time
        if TJsonUtils.IsDateType(Item^.FieldTypeInfo) then
          Val := DateValueFromJsonText(Node.AsString, Item^.FieldTypeInfo)
        else
          Val := TValue.From<string>(Node.AsString);
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
  // a backing field ('F' + uppercase letter or '_', as FName) loses the 'F' to
  // match the intended property name in JSON; Flag or Fattura stay as they are.
  RttiType := AField.Parent;
  if (RttiType <> nil) and (RttiType.IsRecord) and (FSettings.FSmartRecordMapping) then
    Result := TJsonUtils.SmartRecordFieldName(Result);
  
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
            Result := EnumFromJsonNode(AType, AJson.GetNode(ValueField));
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
  // A byte array as the root: a Base64 string
  if FSettings.FBytesAsBase64 and TJsonUtils.IsBytesType(TypeInfo(T)) then
    Exit('"' + TJsonUtils.BytesToBase64(PPointer(@AValue)^,
      DynArraySize(PPointer(@AValue)^)) + '"');

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
  // A byte array as the root: a Base64 string
  if FSettings.FBytesAsBase64 and TJsonUtils.IsBytesType(AValue.TypeInfo) then
    Exit('"' + BytesValueToBase64(AValue) + '"');

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
    if Item^.IgnoreOnWrite then
      Continue;

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

    // "No date": null, whatever the form the date would be written in
    if (Item^.Kind = skDateTime) and
      TJsonUtils.IsNoDate(FieldValue.AsExtended, Item^.FieldTypeInfo, FSettings) then
    begin
      if not FSettings.FIgnoreNullValues then
        Result.SetNull(FieldName);
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

    // [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262)
    if Item^.Format.IsSet then
    begin
      WriteFormattedValue(Result, FieldName, FieldValue, Item^.FieldTypeInfo,
        Item^.Format);
      Continue;
    end;

    case Item^.Kind of
      skInteger:
        Result.SetInt64(FieldName, FieldValue.AsInt64);

      skDateTime:
        begin
            case FSettings.DateFormatStyle of
              TDateFormat.ISO8601:
                Result.SetString(FieldName,
                  TJsonUtils.DateToJsonText(FieldValue.AsExtended, Item^.FieldTypeInfo, FSettings));
              TDateFormat.UnixTimestamp:
                Result.SetInt64(FieldName, DateTimeToUnix(FieldValue.AsExtended));
              TDateFormat.CustomFormat:
                Result.SetString(FieldName, FormatDateTime(FSettings.DateFormat, FieldValue.AsExtended));
            end;
        end;

      skFloat:
        Result.SetDouble(FieldName, FieldValue.AsExtended);

      skString:
        Result.SetString(FieldName, FieldValue.AsString);

      skBoolean:
        Result.SetBoolean(FieldName, FieldValue.AsBoolean);

      skEnumAsString, skEnumAsNumber:
        begin
          // AsString, and EnumInherit (no style of its own), write the name.
          if FSettings.EnumStyle = TEnumStyle.AsNumber then
            Result.SetInteger(FieldName, FieldValue.AsOrdinal)
          else
            Result.SetString(FieldName, GetEnumName(Item^.FieldTypeInfo, FieldValue.AsOrdinal));
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

      skBytes:
        if FSettings.FBytesAsBase64 then
          Result.SetString(FieldName, BytesValueToBase64(FieldValue))
        else
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

procedure TDextSerializer.SetDateMember(const AObj: IDextJsonObject; const AName: string;
  const AValue: TDateTime; AType: PTypeInfo);
begin
  if TJsonUtils.IsNoDate(AValue, AType, FSettings) then
  begin
    if not FSettings.FIgnoreNullValues then
      AObj.SetNull(AName);
  end
  else
    AObj.SetString(AName, TJsonUtils.DateToJsonText(AValue, AType, FSettings));
end;

procedure TDextSerializer.AddDateElement(const AArray: IDextJsonArray;
  const AValue: TDateTime; AType: PTypeInfo);
begin
  // An element is never dropped: the positions of the others would move
  if TJsonUtils.IsNoDate(AValue, AType, FSettings) then
    AArray.AddNull
  else
    AArray.Add(TJsonUtils.DateToJsonText(AValue, AType, FSettings));
end;

function TDextSerializer.ShouldSkipField(AField: TRttiField; const AValue: TValue): Boolean;
var
  Attribute: TCustomAttribute;
  FieldValue: TValue;
  Unwrapped: TValue;
begin
  for Attribute in AField.GetAttributes do
  begin
    if (Attribute is JsonIgnoreAttribute) and JsonIgnoreAttribute(Attribute).IgnoresWrite then
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
        if TJsonUtils.IsDateType(AValue.TypeInfo) then
          SetDateMember(Result, ValueField, AValue.AsExtended, AValue.TypeInfo)
        else
          Result.SetDouble(ValueField, AValue.AsExtended);
      end;

    tkString, tkLString, tkWString, tkUString:
      Result.SetString(ValueField, AValue.AsString);

    tkEnumeration:
      begin
        if AValue.TypeInfo = TypeInfo(Boolean) then
          Result.SetBoolean(ValueField, AValue.AsBoolean)
        else if FSettings.EnumStyle = TEnumStyle.AsNumber then
          Result.SetInt64(ValueField, AValue.AsOrdinal)
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
  Node := ParseJson(AJson);
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
  // A byte array: only numbers from 0 to 255, nothing truncated
  if TJsonUtils.IsBytesType(AType) then
    Exit(BytesFromJsonNode(AJson, AType, ''));

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
          if TJsonUtils.IsDateType(ElementType) and (Node <> nil) and (Node.GetNodeType = jntString) then
            ElementValue := DateValueFromJsonText(Node.AsString, ElementType)
          else
            ElementValue := TValue.From<Double>(AJson.GetDouble(I));
        tkString, tkLString, tkWString, tkUString:
          ElementValue := TValue.From<string>(AJson.GetString(I));
        tkEnumeration:
          if ElementType = TypeInfo(Boolean) then
            ElementValue := TValue.From<Boolean>(AJson.GetBoolean(I))
          else
            ElementValue := EnumFromJsonNode(ElementType, AJson.GetNode(I));
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
            // A byte array element may also be a Base64 string
            if (Node <> nil) and TJsonUtils.IsBytesType(ElementType) then
              ElementValue := BytesFromJsonNode(Node, ElementType, Format('[%d]', [I]))
            else if (Node <> nil) and (Node.GetNodeType = jntArray) then
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
            if TJsonUtils.IsDateType(ElementType) and (Node <> nil) and (Node.GetNodeType = jntString) then
              ElementValue := DateValueFromJsonText(Node.AsString, ElementType)
            else
              ElementValue := TValue.From<Double>(AJson.GetDouble(I));
          tkString, tkLString, tkWString, tkUString:
            ElementValue := TValue.From<string>(AJson.GetString(I));
          tkEnumeration:
            if ElementType = TypeInfo(Boolean) then
              ElementValue := TValue.From<Boolean>(AJson.GetBoolean(I))
            else
              ElementValue := EnumFromJsonNode(ElementType, AJson.GetNode(I));
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
              // A byte array element may also be a Base64 string
              if (Node <> nil) and TJsonUtils.IsBytesType(ElementType) then
                ElementValue := BytesFromJsonNode(Node, ElementType, Format('[%d]', [I]))
              else if (Node <> nil) and (Node.GetNodeType = jntArray) then
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
        if TJsonUtils.IsDateType(ElementType) then
          AddDateElement(Result, ElementValue.AsExtended, ElementType)
        else
          Result.Add(ElementValue.AsExtended);
      tkString, tkLString, tkWString, tkUString:
        Result.Add(ElementValue.AsString);
      tkEnumeration:
        if ElementType = TypeInfo(Boolean) then
          Result.Add(ElementValue.AsBoolean)
        else if FSettings.EnumStyle = TEnumStyle.AsNumber then
          Result.Add(Int64(ElementValue.AsOrdinal))
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
        if FSettings.FBytesAsBase64 and TJsonUtils.IsBytesType(ElementValue.TypeInfo) then
          Result.Add(BytesValueToBase64(ElementValue))
        else
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
          if FSettings.FBytesAsBase64 and TJsonUtils.IsBytesType(ElementValue.TypeInfo) then
            Result.Add(BytesValueToBase64(ElementValue))
          else
            Result.Add(SerializeArray(ElementValue));
        tkInteger, tkInt64:
          Result.Add(ElementValue.AsInt64);
        tkFloat:
          if TJsonUtils.IsDateType(ElementValue.TypeInfo) then
            AddDateElement(Result, ElementValue.AsExtended, ElementValue.TypeInfo)
          else
            Result.Add(ElementValue.AsExtended);
        tkString, tkLString, tkWString, tkUString:
          Result.Add(ElementValue.AsString);
        tkEnumeration:
          if ElementValue.TypeInfo = TypeInfo(Boolean) then
            Result.Add(ElementValue.AsBoolean)
          else if FSettings.EnumStyle = TEnumStyle.AsNumber then
            Result.Add(Int64(ElementValue.AsOrdinal))
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
            if FSettings.FBytesAsBase64 and TJsonUtils.IsBytesType(ElementValue.TypeInfo) then
              Result.Add(BytesValueToBase64(ElementValue))
            else
              Result.Add(SerializeArray(ElementValue));
          tkInteger, tkInt64:
            Result.Add(ElementValue.AsInt64);
          tkFloat:
            if TJsonUtils.IsDateType(ElementValue.TypeInfo) then
              AddDateElement(Result, ElementValue.AsExtended, ElementValue.TypeInfo)
            else
              Result.Add(ElementValue.AsExtended);
          tkString, tkLString, tkWString, tkUString:
            Result.Add(ElementValue.AsString);
          tkEnumeration:
            if ElementValue.TypeInfo = TypeInfo(Boolean) then
              Result.Add(ElementValue.AsBoolean)
            else if FSettings.EnumStyle = TEnumStyle.AsNumber then
              Result.Add(Int64(ElementValue.AsOrdinal))
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
