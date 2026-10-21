unit Dext.Json.NoDate.Tests;

interface

uses
  System.SysUtils,
  System.DateUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types,
  Dext.Json.Utf8,
  Dext.Core.DateUtils,
  Dext.Types.Nullable;

type
  /// Plain properties: the plan reads them on the RTTI path.
  TNoDateRow = class
  private
    FWhen: TDateTime;
    FDay: TDate;
    FClock: TTime;
  public
    property When: TDateTime read FWhen write FWhen;
    property Day: TDate read FDay write FDay;
    property Clock: TTime read FClock write FClock;
  end;

  /// Nullable properties backed by their F<Name> field: the direct path.
  TNoDateNullableRow = class
  private
    FWhen: Nullable<TDateTime>;
    FDay: Nullable<TDate>;
    FClock: Nullable<TTime>;
  public
    property When: Nullable<TDateTime> read FWhen write FWhen;
    property Day: Nullable<TDate> read FDay write FDay;
    property Clock: Nullable<TTime> read FClock write FClock;
  end;

  TNoDateRecord = record
    When: TDateTime;
    Day: TDate;
    Clock: TTime;
  end;

  [TestFixture('JSON - a zero date is "no date": null on every path (ZeroDateAsNull, on by default)')]
  TJsonNoDateTests = class
  public
    [Test('Default: a zero TDateTime and TDate are null, a zero TTime is midnight (class)')]
    procedure Default_Class_ZeroDatesNull_TimeMidnight;
    [Test('Default: the same for a Nullable on the direct path, TDate included')]
    procedure Default_NullableClass_ZeroDatesNull_TimeMidnight;
    [Test('Default: the same for record fields')]
    procedure Default_Record_ZeroDatesNull_TimeMidnight;
    [Test('A record writes "no date" as null with UnixTimestamp and CustomDateFormat too')]
    procedure Record_UnixAndCustomFormat_Null;
    [Test('IgnoreNullValues drops the zero dates, class and record')]
    procedure IgnoreNullValues_DropsZeroDates;
    [Test('Array elements: null in place, never dropped (the positions stay)')]
    procedure Array_ZeroElementNull_KeepsPositions;
    [Test('A list of dates: null in place')]
    procedure List_ZeroElementNull;
    [Test('A single value: null')]
    procedure SingleValue_Null;
    [Test('The UTF-8 writer and GetJsonVal: null')]
    procedure Utf8_Null;
    [Test('ZeroDateAsNull(False) writes the zero date, on every path')]
    procedure Off_WritesTheZeroDate;
    [Test('A real date is written as a date')]
    procedure RealDates_Untouched;
  end;

implementation

const
  RealDay = 46218; // 2026-07-15

function RealWhen: TDateTime;
begin
  Result := EncodeDate(2026, 7, 15) + EncodeTime(10, 30, 0, 0);
end;

function Utf8Write(const AValue: TValue): string;
var
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
  S: UTF8String;
begin
  Stream := TMemoryStream.Create;
  try
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteValue(AValue);
    SetString(S, PAnsiChar(Stream.Memory), Stream.Size);
    Result := string(S);
  finally
    Stream.Free;
  end;
end;

{ TJsonNoDateTests }

procedure TJsonNoDateTests.Default_Class_ZeroDatesNull_TimeMidnight;
var
  R: TNoDateRow;
begin
  R := TNoDateRow.Create;
  try
    Should(TDextJson.Serialize(R)).Be('{"When":null,"Day":null,"Clock":"00:00:00.000"}');
  finally
    R.Free;
  end;
end;

procedure TJsonNoDateTests.Default_NullableClass_ZeroDatesNull_TimeMidnight;
var
  R: TNoDateNullableRow;
begin
  R := TNoDateNullableRow.Create;
  try
    R.When := Nullable<TDateTime>.Create(0);
    R.Day := Nullable<TDate>.Create(0);
    R.Clock := Nullable<TTime>.Create(0);
    Should(TDextJson.Serialize(R)).Be('{"When":null,"Day":null,"Clock":"00:00:00.000"}');
    // Explicitly on: the TDate of the direct path was written as a date
    Should(TDextJson.Serialize(R, TJsonSettings.Default.ZeroDateAsNull)).Be(
      '{"When":null,"Day":null,"Clock":"00:00:00.000"}');
  finally
    R.Free;
  end;
end;

procedure TJsonNoDateTests.Default_Record_ZeroDatesNull_TimeMidnight;
begin
  Should(TDextJson.Serialize<TNoDateRecord>(Default(TNoDateRecord))).Be(
    '{"When":null,"Day":null,"Clock":"00:00:00.000"}');
end;

procedure TJsonNoDateTests.Record_UnixAndCustomFormat_Null;
var
  R: TNoDateRecord;
  Json: string;
begin
  R := Default(TNoDateRecord);
  R.Day := RealDay;
  Json := TDextJson.Serialize<TNoDateRecord>(R, TJsonSettings.Default.UnixTimestamp);
  Should(Json).Contain('"When":null');
  Should(Json).Contain('"Day":' + IntToStr(DateTimeToUnix(RealDay)));
  Json := TDextJson.Serialize<TNoDateRecord>(R, TJsonSettings.Default.CustomDateFormat('dd/mm/yyyy'));
  Should(Json).Contain('"When":null');
  Should(Json).Contain('"Day":"15/07/2026"');
end;

procedure TJsonNoDateTests.IgnoreNullValues_DropsZeroDates;
var
  R: TNoDateRow;
begin
  R := TNoDateRow.Create;
  try
    Should(TDextJson.Serialize(R, TJsonSettings.Default.IgnoreNullValues)).Be(
      '{"Clock":"00:00:00.000"}');
  finally
    R.Free;
  end;
  Should(TDextJson.Serialize<TNoDateRecord>(Default(TNoDateRecord),
    TJsonSettings.Default.IgnoreNullValues)).Be('{"Clock":"00:00:00.000"}');
end;

procedure TJsonNoDateTests.Array_ZeroElementNull_KeepsPositions;
var
  Moments: TArray<TDateTime>;
  Days: TArray<TDate>;
  Clocks: TArray<TTime>;
begin
  Moments := [0, RealWhen];
  Should(TDextJson.Serialize<TArray<TDateTime>>(Moments)).Be(
    '[null,"' + FormatJsonDateTime(RealWhen) + '"]');
  Should(TDextJson.Serialize<TArray<TDateTime>>(Moments,
    TJsonSettings.Default.IgnoreNullValues)).Be('[null,"' + FormatJsonDateTime(RealWhen) + '"]');
  Days := [RealDay, 0];
  Should(TDextJson.Serialize<TArray<TDate>>(Days)).Be('["2026-07-15",null]');
  Clocks := [0];
  Should(TDextJson.Serialize<TArray<TTime>>(Clocks)).Be('["00:00:00.000"]');
end;

procedure TJsonNoDateTests.List_ZeroElementNull;
var
  L: TList<TDateTime>;
begin
  L := TList<TDateTime>.Create;
  try
    L.Add(RealWhen);
    L.Add(0);
    Should(TDextJson.Serialize<TList<TDateTime>>(L)).Be(
      '["' + FormatJsonDateTime(RealWhen) + '",null]');
  finally
    L.Free;
  end;
end;

procedure TJsonNoDateTests.SingleValue_Null;
begin
  Should(TDextJson.Serialize<TDateTime>(0)).Be('{"value":null}');
  Should(TDextJson.Serialize<TDate>(0)).Be('{"value":null}');
  Should(TDextJson.Serialize<TTime>(0)).Be('{"value":"00:00:00.000"}');
end;

procedure TJsonNoDateTests.Utf8_Null;
begin
  Should(Utf8Write(TValue.From<TDateTime>(0))).Be('null');
  Should(Utf8Write(TValue.From<TDate>(0))).Be('null');
  Should(Utf8Write(TValue.From<TTime>(0))).Be('"00:00:00.000"');
  Should(Utf8Write(TValue.From<Double>(0))).Be('0');
  Should(GetJsonVal(TValue.From<TDateTime>(0))).Be('null');
  Should(GetJsonVal(TValue.From<TDate>(0))).Be('null');
  Should(GetJsonVal(TValue.From<TTime>(0))).Be('"00:00:00.000"');
  Should(GetJsonVal(TValue.From<Double>(0))).Be('0');
end;

procedure TJsonNoDateTests.Off_WritesTheZeroDate;
var
  Off: TJsonSettings;
  R: TNoDateRow;
  N: TNoDateNullableRow;
  Expected: string;
begin
  Off := TJsonSettings.Default.ZeroDateAsNull(False);
  Expected := '{"When":"' + FormatJsonDateTime(0) + '","Day":"1899-12-30","Clock":"00:00:00.000"}';
  R := TNoDateRow.Create;
  try
    Should(TDextJson.Serialize(R, Off)).Be(Expected);
  finally
    R.Free;
  end;
  N := TNoDateNullableRow.Create;
  try
    N.When := Nullable<TDateTime>.Create(0);
    N.Day := Nullable<TDate>.Create(0);
    N.Clock := Nullable<TTime>.Create(0);
    Should(TDextJson.Serialize(N, Off)).Be(Expected);
  finally
    N.Free;
  end;
  Should(TDextJson.Serialize<TNoDateRecord>(Default(TNoDateRecord), Off)).Be(Expected);
  Should(TDextJson.Serialize<TArray<TDate>>([0], Off)).Be('["1899-12-30"]');
  Should(TDextJson.Serialize<TDateTime>(0, Off)).Be('{"value":"' + FormatJsonDateTime(0) + '"}');
end;

procedure TJsonNoDateTests.RealDates_Untouched;
var
  R: TNoDateRecord;
begin
  R.When := RealWhen;
  R.Day := RealDay;
  R.Clock := EncodeTime(10, 30, 0, 0);
  Should(TDextJson.Serialize<TNoDateRecord>(R)).Be('{"When":"' + FormatJsonDateTime(RealWhen) +
    '","Day":"2026-07-15","Clock":"10:30:00.000"}');
end;

end.
