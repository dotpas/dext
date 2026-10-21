unit Dext.Json.Types;

interface

uses
  System.SysUtils, System.Classes, Dext.DI.Interfaces;

type
  TDextJsonNodeType = (jntNull, jntString, jntNumber, jntBoolean, jntObject, jntArray);

  TCaseStyle = (
    /// <summary>Inherit from global settings or parent context.</summary>
    CaseInherit,
    /// <summary>Keep names as they are in the record/class.</summary>
    Unchanged, 
    /// <summary>Convert to camelCase (e.g., myProperty).</summary>
    CamelCase, 
    /// <summary>Convert to PascalCase (e.g., MyProperty).</summary>
    PascalCase, 
    /// <summary>Convert to snake_case (e.g., my_property).</summary>
    SnakeCase
  );

  /// <summary>
  ///   Defines how enumerations are serialized.
  /// </summary>
  TEnumStyle = (
    /// <summary>Inherit from global settings or parent context.</summary>
    EnumInherit,
    /// <summary>Serialize as the underlying integer value.</summary>
    AsNumber, 
    /// <summary>Serialize as the string name of the enum value.</summary>
    AsString
  );

  /// <summary>
  ///   Defines JSON output formatting.
  /// </summary>
  TJsonFormatting = (
    /// <summary>Compact JSON (no whitespace).</summary>
    None, 
    /// <summary>Indented JSON for readability.</summary>
    Indented
  );

  /// <summary>
  ///   Defines standard date/time formats.
  /// </summary>
  TDateFormat = (
    /// <summary>ISO 8601 format (e.g., "2025-11-16T11:07:37.565").</summary>
    ISO8601,        
    /// <summary>Unix timestamp (seconds since epoch).</summary>
    UnixTimestamp,  
    /// <summary>Custom format string.</summary>
    CustomFormat    
  );

  IDextJsonNode = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}']
    function GetNodeType: TDextJsonNodeType;
    function AsString: string;
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsDouble: Double;
    function AsBoolean: Boolean;
    function ToJson(Indented: Boolean = False): string;
    function IsNull: Boolean;
    property NodeType: TDextJsonNodeType read GetNodeType;
  end;

  IDextJsonArray = interface;

  IDextJsonObject = interface(IDextJsonNode)
    ['{B1B2C3D4-E5F6-7890-ABCD-EF1234567891}']
    function Contains(const Name: string): Boolean;
    function GetNode(const Name: string): IDextJsonNode;
    function GetString(const Name: string): string;
    function GetInteger(const Name: string): Integer;
    function GetInt64(const Name: string): Int64;
    function GetDouble(const Name: string): Double;
    function GetBoolean(const Name: string): Boolean;
    function GetObject(const Name: string): IDextJsonObject;
    function GetArray(const Name: string): IDextJsonArray;
    function GetCount: Integer;
    function GetName(Index: Integer): string;
    procedure SetString(const Name, Value: string);
    procedure SetInteger(const Name: string; Value: Integer);
    procedure SetInt64(const Name: string; Value: Int64);
    procedure SetDouble(const Name: string; Value: Double);
    procedure SetBoolean(const Name: string; Value: Boolean);
    procedure SetObject(const Name: string; Value: IDextJsonObject);
    procedure SetArray(const Name: string; Value: IDextJsonArray);
    procedure SetNode(const Name: string; Value: IDextJsonNode);
    procedure SetNull(const Name: string);
    property Count: Integer read GetCount;
  end;

  IDextJsonArray = interface(IDextJsonNode)
    ['{C1B2C3D4-E5F6-7890-ABCD-EF1234567892}']
    function GetCount: NativeInt;
    function GetNode(Index: Integer): IDextJsonNode;
    function GetString(Index: Integer): string;
    function GetInteger(Index: Integer): Integer;
    function GetInt64(Index: Integer): Int64;
    function GetDouble(Index: Integer): Double;
    function GetBoolean(Index: Integer): Boolean;
    function GetObject(Index: Integer): IDextJsonObject;
    function GetArray(Index: Integer): IDextJsonArray;
    procedure Add(const Value: string); overload;
    procedure Add(Value: Integer); overload;
    procedure Add(Value: Int64); overload;
    procedure Add(Value: Double); overload;
    procedure Add(Value: Boolean); overload;
    procedure Add(Value: IDextJsonObject); overload;
    procedure Add(Value: IDextJsonArray); overload;
    procedure AddNull;
    property Count: NativeInt read GetCount;
  end;

const
  /// <summary>
  ///   Default maximum allowed nesting depth for JSON parsers to prevent stack overflow DoS attacks.
  /// </summary>
  DEFAULT_MAX_JSON_DEPTH = 64;

  /// <summary>
  ///   Special nesting depth value to disable recursion depth checking in JSON parsers.
  /// </summary>
  UNLIMITED_JSON_DEPTH = -1;

type
  /// <summary>
  ///   Configuration settings for the JSON serializer.
  /// </summary>
  TJsonSettings = record
  public
    FCaseInsensitive: Boolean;
    FIgnoreNullValues: Boolean;
    FServiceProvider: IServiceProvider;
    FSmartRecordMapping: Boolean;
    FZeroDateAsNull: Boolean;
    FKeepDefaultEnums: Boolean;
    FBytesAsBase64: Boolean;
    FNullDates: TArray<TDateTime>;
    FMaxDepth: Integer;
    Formatting: TJsonFormatting;
    IgnoreDefaultValues: Boolean;
    DateFormat: string;
    CaseStyle: TCaseStyle;
    EnumStyle: TEnumStyle;
    DateFormatStyle: TDateFormat;
    
    class function Default: TJsonSettings; static;
    class function Indented: TJsonSettings; static;

    function CamelCase: TJsonSettings;
    function PascalCase: TJsonSettings;
    function SnakeCase: TJsonSettings;
    function UnchangedCase: TJsonSettings;
    function EnumAsString: TJsonSettings;
    function EnumAsNumber: TJsonSettings;
    function IgnoreNullValues: TJsonSettings;
    function CaseInsensitive: TJsonSettings;
    function SmartRecordMapping(AValue: Boolean = True): TJsonSettings;
    /// <summary>
    ///   Configures the maximum allowed depth of nested JSON structures (objects and arrays).
    ///   Default is 64. Pass UNLIMITED_JSON_DEPTH (-1) to disable depth checks.
    /// </summary>
    function MaxDepth(AValue: Integer): TJsonSettings; overload;
    /// <summary>
    ///   Returns the effective maximum depth limit. Defaults to 64 if not set.
    /// </summary>
    function MaxDepth: Integer; overload;

    /// <summary>
    ///   A TDateTime or TDate that is 0 (1899-12-30, "no date") is written as
    ///   null instead of "1899-12-30T00:00:00.000" (dropped with
    ///   IgnoreNullValues), on every path: class properties, record fields,
    ///   array elements, single values. A TTime is left alone: 0 is midnight
    ///   there. On by default; ZeroDateAsNull(False) writes the zero date.
    /// </summary>
    function ZeroDateAsNull(AValue: Boolean = True): TJsonSettings;
    /// <summary>
    ///   The dates that mean "no date" for this application, as 'yyyy-mm-dd'
    ///   (for example '0001-01-01' and '1900-01-01', the values legacy
    ///   databases and NOT NULL columns use): written as null like the zero
    ///   date, on every path, and dropped with IgnoreNullValues. A value is
    ///   "no date" when it is exactly that day: a sentinel has no time, so
    ///   '1900-01-01 08:30' is still a date. A TTime is left alone. The list
    ///   replaces the previous one; an empty list turns it off (the default).
    ///   Reading is not affected. A text that is not a valid day raises
    ///   EConvertError.
    /// </summary>
    function NullDates(const ADates: array of string): TJsonSettings;
    /// <summary>True when AValue is one of the NullDates.</summary>
    function IsNullDate(const AValue: TDateTime): Boolean;
    /// <summary>
    ///   With IgnoreDefaultValues, an enum at its first value (ordinal 0) is
    ///   still written: that value is often a business state ("Draft",
    ///   "Active") that a consumer must see. A False Boolean is still dropped.
    /// </summary>
    function KeepDefaultEnums(AValue: Boolean = True): TJsonSettings;
    /// <summary>
    ///   A byte array (TBytes, or any dynamic array of Byte) is written as a
    ///   Base64 string on one line, with padding (RFC 4648, OpenAPI
    ///   "format: byte"). It is the default; False writes it as an array of
    ///   numbers, as before. Reading accepts both, whatever this setting.
    /// </summary>
    function BytesAsBase64(AValue: Boolean = True): TJsonSettings;
    function ISODateFormat: TJsonSettings;
    function UnixTimestamp: TJsonSettings;
    function CustomDateFormat(const Format: string): TJsonSettings;
    function ServiceProvider(const AProvider: IServiceProvider): TJsonSettings;
  end;

  IDextJsonProvider = interface
    ['{D1B2C3D4-E5F6-7890-ABCD-EF1234567893}']
    function CreateObject: IDextJsonObject;
    function CreateArray: IDextJsonArray;
    function Parse(const Json: string): IDextJsonNode;
  end;

implementation

// 'yyyy-mm-dd' and nothing else: a day of NullDates
function TryReadDay(const AText: string; out ADay: TDateTime): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (Length(AText) <> 10) or (AText[5] <> '-') or (AText[8] <> '-') then
    Exit;
  for I := 1 to 10 do
    if (I <> 5) and (I <> 8) and not CharInSet(AText[I], ['0'..'9']) then
      Exit;
  Result := TryEncodeDate(StrToInt(Copy(AText, 1, 4)), StrToInt(Copy(AText, 6, 2)),
    StrToInt(Copy(AText, 9, 2)), ADay);
end;

{ TJsonSettings }

function TJsonSettings.NullDates(const ADates: array of string): TJsonSettings;
var
  I: Integer;
begin
  Result := Self;
  SetLength(Result.FNullDates, Length(ADates));
  for I := 0 to High(ADates) do
    if not TryReadDay(ADates[I], Result.FNullDates[I]) then
      raise EConvertError.CreateFmt('NullDates: "%s" is not a day (yyyy-mm-dd)', [ADates[I]]);
end;

function TJsonSettings.IsNullDate(const AValue: TDateTime): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FNullDates) do
    if FNullDates[I] = AValue then
      Exit(True);
  Result := False;
end;

function TJsonSettings.CamelCase: TJsonSettings;
begin
  Result := Self;
  Result.CaseStyle := TCaseStyle.CamelCase;
end;

function TJsonSettings.CaseInsensitive: TJsonSettings;
begin
  Result := Self;
  Result.FCaseInsensitive := True;
end;

function TJsonSettings.CustomDateFormat(const Format: string): TJsonSettings;
begin
  Result := Self;
  Result.DateFormatStyle := TDateFormat.CustomFormat;
  Result.DateFormat := Format;
end;

class function TJsonSettings.Default: TJsonSettings;
begin
  // Result is the caller's storage, already initialized: release its managed
  // fields before zeroing it, or the strings and interfaces it held are leaked.
  Finalize(Result);
  FillChar(Result, SizeOf(Result), 0);
  Result.Formatting := TJsonFormatting.None;
  Result.FIgnoreNullValues := False;
  Result.IgnoreDefaultValues := False;
  Result.DateFormat := 'yyyy-mm-dd"T"hh:nn:ss.zzz';
  Result.DateFormatStyle := TDateFormat.ISO8601;
  Result.CaseStyle := TCaseStyle.Unchanged;
  Result.EnumStyle := TEnumStyle.AsString;
  Result.FCaseInsensitive := False;
  Result.FSmartRecordMapping := True; // Default is True
  Result.FZeroDateAsNull := True;
  Result.FKeepDefaultEnums := False;
  Result.FBytesAsBase64 := True;
  Result.FMaxDepth := DEFAULT_MAX_JSON_DEPTH;
end;

function TJsonSettings.MaxDepth(AValue: Integer): TJsonSettings;
begin
  Result := Self;
  Result.FMaxDepth := AValue;
end;

function TJsonSettings.MaxDepth: Integer;
begin
  if FMaxDepth = 0 then
    Result := DEFAULT_MAX_JSON_DEPTH
  else
    Result := FMaxDepth;
end;

function TJsonSettings.EnumAsNumber: TJsonSettings;
begin
  Result := Self;
  Result.EnumStyle := TEnumStyle.AsNumber;
end;

function TJsonSettings.EnumAsString: TJsonSettings;
begin
  Result := Self;
  Result.EnumStyle := TEnumStyle.AsString;
end;

function TJsonSettings.IgnoreNullValues: TJsonSettings;
begin
  Result := Self;
  Result.FIgnoreNullValues := True;
end;

class function TJsonSettings.Indented: TJsonSettings;
begin
  Result := Default;
  Result.Formatting := TJsonFormatting.Indented;
end;

function TJsonSettings.ISODateFormat: TJsonSettings;
begin
  Result := Self;
  Result.DateFormatStyle := TDateFormat.ISO8601;
  Result.DateFormat := 'yyyy-mm-dd"T"hh:nn:ss.zzz';
end;

function TJsonSettings.PascalCase: TJsonSettings;
begin
  Result := Self;
  Result.CaseStyle := TCaseStyle.PascalCase;
end;

function TJsonSettings.ServiceProvider(const AProvider: IServiceProvider): TJsonSettings;
begin
  Result := Self;
  Result.FServiceProvider := AProvider;
end;

function TJsonSettings.SmartRecordMapping(AValue: Boolean): TJsonSettings;
begin
  Result := Self;
  Result.FSmartRecordMapping := AValue;
end;

function TJsonSettings.KeepDefaultEnums(AValue: Boolean): TJsonSettings;
begin
  Result := Self;
  Result.FKeepDefaultEnums := AValue;
end;

function TJsonSettings.BytesAsBase64(AValue: Boolean): TJsonSettings;
begin
  Result := Self;
  Result.FBytesAsBase64 := AValue;
end;

function TJsonSettings.ZeroDateAsNull(AValue: Boolean): TJsonSettings;
begin
  Result := Self;
  Result.FZeroDateAsNull := AValue;
end;

function TJsonSettings.SnakeCase: TJsonSettings;
begin
  Result := Self;
  Result.CaseStyle := TCaseStyle.SnakeCase;
end;

function TJsonSettings.UnchangedCase: TJsonSettings;
begin
  Result := Self;
  Result.CaseStyle := TCaseStyle.Unchanged;
end;

function TJsonSettings.UnixTimestamp: TJsonSettings;
begin
  Result := Self;
  Result.DateFormatStyle := TDateFormat.UnixTimestamp;
  Result.DateFormat := '';
end;

end.
