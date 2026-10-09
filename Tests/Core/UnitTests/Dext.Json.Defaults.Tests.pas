unit Dext.Json.Defaults.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types;

type
  /// A plain class: public properties, no attributes.
  TJsonDefaultsRow = class
  private
    FName: string;
    FWhen: TDateTime;
    FDay: TDate;
    FTime: TTime;
    FCount: Integer;
    FBig: Int64;
    FAmount: Double;
    FActive: Boolean;
  public
    property Name: string read FName write FName;
    property When: TDateTime read FWhen write FWhen;
    property Day: TDate read FDay write FDay;
    property Time: TTime read FTime write FTime;
    property Count: Integer read FCount write FCount;
    property Big: Int64 read FBig write FBig;
    property Amount: Double read FAmount write FAmount;
    property Active: Boolean read FActive write FActive;
  end;

  TJsonDefaultsStatus = (jdsDraft, jdsActive, jdsClosed);

  /// A plain class with an enum: its first value is also its default.
  TJsonDefaultsEnumRow = class
  private
    FName: string;
    FStatus: TJsonDefaultsStatus;
    FActive: Boolean;
  public
    property Name: string read FName write FName;
    property Status: TJsonDefaultsStatus read FStatus write FStatus;
    property Active: Boolean read FActive write FActive;
  end;

  /// The same, as a record.
  TJsonDefaultsRecord = record
    Name: string;
    Count: Integer;
    Amount: Double;
    When: TDateTime;
    Active: Boolean;
    Status: TJsonDefaultsStatus;
  end;

  {$M+}
  /// Only the published property reaches the JSON.
  [JsonPublishedOnly]
  TJsonPublishedOnlyRow = class
  private
    FWorking: string;
    FShown: string;
  public
    property Working: string read FWorking write FWorking;
  published
    property Shown: string read FShown write FShown;
  end;

  /// Inherits the attribute.
  TJsonPublishedOnlyChild = class(TJsonPublishedOnlyRow)
  private
    FMore: Integer;
    FAlsoShown: Integer;
  public
    property More: Integer read FMore write FMore;
  published
    property AlsoShown: Integer read FAlsoShown write FAlsoShown;
  end;
  {$M-}

  [TestFixture('JSON - IgnoreDefaultValues, ZeroDateAsNull and JsonPublishedOnly on classes')]
  TJsonDefaultsTests = class
  public
    [Test('IgnoreDefaultValues drops the default values of class properties')]
    procedure IgnoreDefaultValues_OnClassProperties;
    [Test('IgnoreDefaultValues keeps the values that are not defaults')]
    procedure IgnoreDefaultValues_KeepsTheRest;
    [Test('ZeroDateAsNull writes a zero TDateTime and TDate as null, not a TTime')]
    procedure ZeroDateAsNull_DateAndDateTime_NotTime;
    [Test('ZeroDateAsNull with IgnoreNullValues drops the zero dates')]
    procedure ZeroDateAsNull_WithIgnoreNullValues;
    [Test('A real date is still written as a date with ZeroDateAsNull')]
    procedure ZeroDateAsNull_RealDateUntouched;
    [Test('Without the options the output does not change')]
    procedure Default_Unchanged;
    [Test('JsonPublishedOnly serializes only the published properties')]
    procedure PublishedOnly_OnlyPublished;
    [Test('JsonPublishedOnly is inherited')]
    procedure PublishedOnly_Inherited;
    [Test('IgnoreDefaultValues drops the default values of record fields')]
    procedure IgnoreDefaultValues_OnRecordFields;
    [Test('IgnoreDefaultValues keeps the record fields that are not defaults')]
    procedure IgnoreDefaultValues_Record_KeepsTheRest;
    [Test('Without the options a record is written whole')]
    procedure Default_Record_Unchanged;
    [Test('IgnoreDefaultValues drops an enum at its first value (class, as string and as number)')]
    procedure IgnoreDefaultValues_DropsEnumAtZero_Class;
    [Test('IgnoreDefaultValues drops an enum at its first value (record, as string and as number)')]
    procedure IgnoreDefaultValues_DropsEnumAtZero_Record;
    [Test('KeepDefaultEnums keeps an enum at its first value (class, as string and as number)')]
    procedure KeepDefaultEnums_KeepsEnumAtZero_Class;
    [Test('KeepDefaultEnums keeps an enum at its first value (record, as string and as number)')]
    procedure KeepDefaultEnums_KeepsEnumAtZero_Record;
    [Test('KeepDefaultEnums does not keep a False Boolean')]
    procedure KeepDefaultEnums_BooleanStillDropped;
    [Test('KeepDefaultEnums leaves an enum that is not at its first value alone')]
    procedure KeepDefaultEnums_OtherValuesUnchanged;
    [Test('KeepDefaultEnums is off by default, and without IgnoreDefaultValues changes nothing')]
    procedure KeepDefaultEnums_DefaultOff_AndInertAlone;
  end;

implementation

function EmptyRow: TJsonDefaultsRow;
begin
  Result := TJsonDefaultsRow.Create; // every field at its default
end;

function FullRow: TJsonDefaultsRow;
begin
  Result := TJsonDefaultsRow.Create;
  Result.Name := 'x';
  Result.When := EncodeDate(2026, 10, 6) + EncodeTime(13, 45, 0, 0);
  Result.Day := EncodeDate(2026, 10, 6);
  Result.Time := EncodeTime(13, 45, 0, 0);
  Result.Count := 7;
  Result.Big := 9007199254740993;
  Result.Amount := 1.5;
  Result.Active := True;
end;

{ TJsonDefaultsTests }

procedure TJsonDefaultsTests.IgnoreDefaultValues_OnClassProperties;
var
  R: TJsonDefaultsRow;
  S: TJsonSettings;
begin
  R := EmptyRow;
  try
    S := TJsonSettings.Default;
    S.IgnoreDefaultValues := True;
    // Before: every property was written, the option had no effect on classes.
    Should(TDextJson.Serialize(R, S)).Be('{}');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.IgnoreDefaultValues_KeepsTheRest;
var
  R: TJsonDefaultsRow;
  S: TJsonSettings;
  Json: string;
begin
  R := FullRow;
  try
    S := TJsonSettings.Default;
    S.IgnoreDefaultValues := True;
    Json := TDextJson.Serialize(R, S);
    Should(Json).Contain('"Name":"x"');
    Should(Json).Contain('"Count":7');
    Should(Json).Contain('"Big":9007199254740993');
    Should(Json).Contain('"Amount":1.5');
    Should(Json).Contain('"Active":true');
    Should(Json).Contain('"When":"2026-10-06T13:45:00.000"');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.ZeroDateAsNull_DateAndDateTime_NotTime;
var
  R: TJsonDefaultsRow;
  Json: string;
begin
  R := EmptyRow;
  try
    Json := TDextJson.Serialize(R, TJsonSettings.Default.ZeroDateAsNull);
    Should(Json).Contain('"When":null');
    Should(Json).Contain('"Day":null');
    // 0 is midnight for a TTime, not "no date"
    Should(Json).Contain('"Time":"1899-12-30T00:00:00.000"');
    // the other defaults are untouched
    Should(Json).Contain('"Count":0');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.ZeroDateAsNull_WithIgnoreNullValues;
var
  R: TJsonDefaultsRow;
  Json: string;
begin
  R := EmptyRow;
  try
    Json := TDextJson.Serialize(R, TJsonSettings.Default.ZeroDateAsNull.IgnoreNullValues);
    Should(Json).NotContain('"When"');
    Should(Json).NotContain('"Day"');
    Should(Json).Contain('"Time"');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.ZeroDateAsNull_RealDateUntouched;
var
  R: TJsonDefaultsRow;
  Json: string;
begin
  R := FullRow;
  try
    Json := TDextJson.Serialize(R, TJsonSettings.Default.ZeroDateAsNull);
    Should(Json).Contain('"When":"2026-10-06T13:45:00.000"');
    Should(Json).Contain('"Day":"2026-10-06T00:00:00.000"');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.Default_Unchanged;
var
  R: TJsonDefaultsRow;
begin
  R := EmptyRow;
  try
    Should(TDextJson.Serialize(R)).Be('{"Name":"","When":"1899-12-30T00:00:00.000",' +
      '"Day":"1899-12-30T00:00:00.000","Time":"1899-12-30T00:00:00.000",' +
      '"Count":0,"Big":0,"Amount":0,"Active":false}');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.PublishedOnly_OnlyPublished;
var
  R: TJsonPublishedOnlyRow;
begin
  R := TJsonPublishedOnlyRow.Create;
  try
    R.Working := 'internal';
    R.Shown := 'out';
    Should(TDextJson.Serialize(R)).Be('{"Shown":"out"}');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.PublishedOnly_Inherited;
var
  R: TJsonPublishedOnlyChild;
  Json: string;
begin
  R := TJsonPublishedOnlyChild.Create;
  try
    R.Working := 'internal';
    R.Shown := 'out';
    R.More := 5;
    R.AlsoShown := 6;
    Json := TDextJson.Serialize(R);
    Should(Json).Contain('"Shown":"out"');
    Should(Json).Contain('"AlsoShown":6');
    Should(Json).NotContain('Working');
    Should(Json).NotContain('More');
  finally
    R.Free;
  end;
end;

function FullRecord: TJsonDefaultsRecord;
begin
  Result := Default(TJsonDefaultsRecord);
  Result.Name := 'x';
  Result.Count := 7;
  Result.Amount := 1.5;
  Result.When := EncodeDate(2026, 10, 6) + EncodeTime(13, 45, 0, 0);
  Result.Active := True;
  Result.Status := jdsClosed;
end;

function IgnoringDefaults: TJsonSettings;
begin
  Result := TJsonSettings.Default;
  Result.IgnoreDefaultValues := True;
end;

procedure TJsonDefaultsTests.IgnoreDefaultValues_OnRecordFields;
begin
  // Before: the option had no effect on records (every field was written).
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Default(TJsonDefaultsRecord),
    IgnoringDefaults)).Be('{}');
end;

procedure TJsonDefaultsTests.IgnoreDefaultValues_Record_KeepsTheRest;
var
  Json: string;
begin
  Json := TDextJson.Serialize<TJsonDefaultsRecord>(FullRecord, IgnoringDefaults);
  Should(Json).Contain('"Name":"x"');
  Should(Json).Contain('"Count":7');
  Should(Json).Contain('"Amount":1.5');
  Should(Json).Contain('"When":"2026-10-06T13:45:00.000"');
  Should(Json).Contain('"Active":true');
  Should(Json).Contain('"Status":2');
end;

procedure TJsonDefaultsTests.Default_Record_Unchanged;
begin
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Default(TJsonDefaultsRecord))).Be(
    '{"Name":"","Count":0,"Amount":0,"When":"1899-12-30T00:00:00.000",' +
    '"Active":false,"Status":0}');
end;

procedure TJsonDefaultsTests.IgnoreDefaultValues_DropsEnumAtZero_Class;
var
  R: TJsonDefaultsEnumRow;
begin
  R := TJsonDefaultsEnumRow.Create; // Status = jdsDraft
  try
    Should(TDextJson.Serialize(R, IgnoringDefaults.EnumAsString)).Be('{}');
    Should(TDextJson.Serialize(R, IgnoringDefaults.EnumAsNumber)).Be('{}');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.IgnoreDefaultValues_DropsEnumAtZero_Record;
begin
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Default(TJsonDefaultsRecord),
    IgnoringDefaults.EnumAsString)).Be('{}');
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Default(TJsonDefaultsRecord),
    IgnoringDefaults.EnumAsNumber)).Be('{}');
end;

procedure TJsonDefaultsTests.KeepDefaultEnums_KeepsEnumAtZero_Class;
var
  R: TJsonDefaultsEnumRow;
  Json: string;
begin
  R := TJsonDefaultsEnumRow.Create;
  try
    // The enum stays; the other defaults are still dropped.
    Should(TDextJson.Serialize(R, IgnoringDefaults.EnumAsString.KeepDefaultEnums))
      .Be('{"Status":"jdsDraft"}');
    // A class property is written by name whatever the EnumStyle (the class
    // plan always picks skEnumAsString), so only its presence is checked here.
    Json := TDextJson.Serialize(R, IgnoringDefaults.EnumAsNumber.KeepDefaultEnums);
    Should(Json).Contain('"Status":');
    Should(Json).NotContain('Name');
  finally
    R.Free;
  end;
end;

procedure TJsonDefaultsTests.KeepDefaultEnums_KeepsEnumAtZero_Record;
begin
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Default(TJsonDefaultsRecord),
    IgnoringDefaults.EnumAsString.KeepDefaultEnums)).Be('{"Status":"jdsDraft"}');
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Default(TJsonDefaultsRecord),
    IgnoringDefaults.EnumAsNumber.KeepDefaultEnums)).Be('{"Status":0}');
end;

procedure TJsonDefaultsTests.KeepDefaultEnums_BooleanStillDropped;
var
  R: TJsonDefaultsEnumRow;
  Rec: TJsonDefaultsRecord;
begin
  // A Boolean is an enumeration to RTTI, but False is not a business state.
  R := TJsonDefaultsEnumRow.Create;
  try
    Should(TDextJson.Serialize(R, IgnoringDefaults.KeepDefaultEnums))
      .NotContain('Active');
  finally
    R.Free;
  end;
  Rec := Default(TJsonDefaultsRecord);
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Rec,
    IgnoringDefaults.KeepDefaultEnums)).NotContain('Active');
end;

procedure TJsonDefaultsTests.KeepDefaultEnums_OtherValuesUnchanged;
var
  R: TJsonDefaultsEnumRow;
  Rec: TJsonDefaultsRecord;
begin
  R := TJsonDefaultsEnumRow.Create;
  try
    R.Status := jdsActive;
    Should(TDextJson.Serialize(R, IgnoringDefaults.EnumAsString))
      .Be('{"Status":"jdsActive"}');
    Should(TDextJson.Serialize(R, IgnoringDefaults.EnumAsString.KeepDefaultEnums))
      .Be('{"Status":"jdsActive"}');
  finally
    R.Free;
  end;
  Rec := Default(TJsonDefaultsRecord);
  Rec.Status := jdsActive;
  Should(TDextJson.Serialize<TJsonDefaultsRecord>(Rec,
    IgnoringDefaults.EnumAsNumber.KeepDefaultEnums)).Be('{"Status":1}');
end;

procedure TJsonDefaultsTests.KeepDefaultEnums_DefaultOff_AndInertAlone;
var
  R: TJsonDefaultsEnumRow;
begin
  Should(TJsonSettings.Default.FKeepDefaultEnums).BeFalse;
  R := TJsonDefaultsEnumRow.Create;
  try
    // Without IgnoreDefaultValues every value is written anyway.
    Should(TDextJson.Serialize(R, TJsonSettings.Default.KeepDefaultEnums))
      .Be(TDextJson.Serialize(R, TJsonSettings.Default));
  finally
    R.Free;
  end;
end;

end.
