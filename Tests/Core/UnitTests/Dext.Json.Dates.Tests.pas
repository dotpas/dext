unit Dext.Json.Dates.Tests;

interface

uses
  System.SysUtils,
  System.DateUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  System.Rtti,
  Dext.Core.Span,
  Dext.Core.DateUtils,
  Dext.Core.Reflection,
  Dext.Json,
  Dext.Json.Types,
  Dext.Json.Utf8,
  Dext.Json.Utf8.Serializer,
  DextJsonDataObjects;

type
  TJsonDatesRow = class
  private
    FWhen: TDateTime;
    FDay: TDate;
    FClock: TTime;
  public
    property When: TDateTime read FWhen write FWhen;
    property Day: TDate read FDay write FDay;
    property Clock: TTime read FClock write FClock;
  end;

  TJsonDatesRecord = record
    When: TDateTime;
    Day: TDate;
    Clock: TTime;
  end;

  TJsonDatesArrays = class
  private
    FMoments: TArray<TDateTime>;
    FDays: TArray<TDate>;
  public
    property Moments: TArray<TDateTime> read FMoments write FMoments;
    property Days: TArray<TDate> read FDays write FDays;
  end;

  [TestFixture('JSON - dates: the writer with the UTC offset and the reader (#254, #255)')]
  TJsonDatesTests = class
  public
    // The writer
    [Test('A TDateTime is the local time with its offset')]
    procedure DateTime_LocalWithOffset;
    [Test('Two thousand values from 1950 to 2059 have the offset of the system')]
    procedure DateTime_ManyValues_OffsetOfTheSystem;
    [Test('Every minute of the days the offset changes: the same text as JsonDataObjects')]
    procedure DateTime_DaysOfChange_SameAsJsonDataObjects;
    [Test('A TDate is the calendar day, a TTime the wall clock')]
    procedure Date_And_Time;
    [Test('The buffer form writes the same text')]
    procedure Buffer_SameText;
    // #255
    [Test('DateTimeToISO8601: whole minutes, not +01:59 (#255)')]
    procedure DriverOffset_WholeMinutes;
    [Test('DateTimeToISO8601: 1899-12-30 has the offset of that day, not +23:00 (#255)')]
    procedure DriverOffset_BeforeDecember31_1899;
    // The reader
    [Test('Reading: a date, a local date and time, the fraction')]
    procedure Read_DateAndLocal;
    [Test('Reading: Z and an offset are converted to local time')]
    procedure Read_ZoneToLocal;
    [Test('Reading: what is not a JSON date is refused')]
    procedure Read_Refused;
    [Test('Reading a time of day')]
    procedure Read_Time;
    [Test('Written and read back: the same value')]
    procedure RoundTrip;
    [Test('TryParseCommonDate reads the zone too')]
    procedure CommonDate_ReadsTheZone;
    // The serializers
    [Test('A class: TDateTime with its offset, TDate the day, TTime the clock')]
    procedure Class_Written;
    [Test('A class read back, and a Z or an offset converted to local time')]
    procedure Class_Read;
    [Test('A record: written and read the same way')]
    procedure Record_WrittenAndRead;
    [Test('Arrays of dates: written as text, read back')]
    procedure Arrays_WrittenAndRead;
    [Test('The UTF-8 writer: the same text, not a Z on the local time (#254)')]
    procedure Utf8Writer_SameText;
    [Test('The UTF-8 record deserializer converts the zone')]
    procedure Utf8Record_Read;
    [Test('CustomDateFormat keeps its format')]
    procedure CustomFormat_Kept;
    [Test('A parameter from a route or a query reads the zone and the milliseconds')]
    procedure CastFromString_ReadsTheZone;
  end;

implementation

function OffsetText(AMinutes: Integer): string;
begin
  if AMinutes = 0 then
    Exit('Z');
  if AMinutes > 0 then
    Result := '+'
  else
    Result := '-';
  AMinutes := Abs(AMinutes);
  Result := Result + Format('%.2d:%.2d', [AMinutes div 60, AMinutes mod 60]);
end;

// The offset the system gives for a local time, in whole minutes, through
// TTimeZone: a way of its own, to compare with.
function ExpectedOffset(const AValue: TDateTime): Integer;
begin
  Result := Round(TTimeZone.Local.GetUtcOffset(AValue).TotalMinutes);
end;

// True when the offset is the same at the start and at the end of the day
function QuietDay(const AValue: TDateTime): Boolean;
begin
  Result := ExpectedOffset(Trunc(AValue)) =
    ExpectedOffset(Trunc(AValue) + EncodeTime(23, 59, 59, 0));
end;

function Digits(const AValue: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss"."zzz', AValue);
end;

function Parse(const AText: string): TDateTime;
begin
  if not TryParseJsonDateTime(AText, Result) then
    raise Exception.Create('not read: ' + AText);
end;

{ TJsonDatesTests }

procedure TJsonDatesTests.DateTime_LocalWithOffset;
var
  V: TDateTime;
begin
  V := EncodeDateTime(2026, 7, 15, 10, 30, 0, 0);
  Should(FormatJsonDateTime(V)).Be('2026-07-15T10:30:00.000' + OffsetText(ExpectedOffset(V)));
  V := EncodeDateTime(2026, 1, 15, 8, 5, 9, 7);
  Should(FormatJsonDateTime(V)).Be('2026-01-15T08:05:09.007' + OffsetText(ExpectedOffset(V)));
end;

procedure TJsonDatesTests.DateTime_ManyValues_OffsetOfTheSystem;
var
  I, Wrong: Integer;
  V: TDateTime;
begin
  RandSeed := 255;
  Wrong := 0;
  for I := 1 to 2000 do
  begin
    V := EncodeDate(1950, 1, 1) + Random * (EncodeDate(2060, 1, 1) - EncodeDate(1950, 1, 1));
    if not QuietDay(V) then
      Continue;
    if FormatJsonDateTime(V) <> Digits(V) + OffsetText(ExpectedOffset(V)) then
      Inc(Wrong);
  end;
  Should(Wrong).Be(0);
end;

procedure TJsonDatesTests.DateTime_DaysOfChange_SameAsJsonDataObjects;
var
  Day: TDateTime;
  Minute, Wrong, Days: Integer;
  V: TDateTime;
begin
  // The days of 2026 when the offset changes in this time zone (none where
  // there is no daylight saving time: then the test has nothing to compare)
  Wrong := 0;
  Days := 0;
  Day := EncodeDate(2026, 1, 1);
  while Day < EncodeDate(2027, 1, 1) do
  begin
    if not QuietDay(Day) then
    begin
      Inc(Days);
      for Minute := 0 to 1439 do
      begin
        V := Day + Minute / MinsPerDay + 17.5 / SecsPerDay;
        if FormatJsonDateTime(V) <> TJsonBaseObject.DateTimeToJSON(V, False) then
          Inc(Wrong);
      end;
    end;
    Day := Day + 1;
  end;
  Should(Wrong).Be(0);
  Should(Days <= 4).BeTrue;
end;

procedure TJsonDatesTests.Date_And_Time;
begin
  Should(FormatJsonDate(EncodeDateTime(2026, 7, 5, 23, 59, 59, 999))).Be('2026-07-05');
  Should(FormatJsonTime(EncodeTime(9, 5, 7, 42))).Be('09:05:07.042');
  // A TIME column comes from a driver on 1899-12-30: only the clock counts
  Should(FormatJsonTime(EncodeTime(23, 0, 0, 0))).Be('23:00:00.000');
  Should(FormatJsonTime(EncodeDate(2026, 7, 5) + EncodeTime(10, 30, 0, 0))).Be('10:30:00.000');
end;

procedure TJsonDatesTests.Buffer_SameText;
var
  Buffer: array[0..JsonDateTimeMaxChars - 1] of Char;
  Count: Integer;
  V: TDateTime;
  Text: string;
begin
  V := EncodeDateTime(2026, 3, 1, 12, 0, 0, 0);
  Count := FormatJsonDateTimeBuffer(V, @Buffer[0]);
  SetString(Text, PChar(@Buffer[0]), Count);
  Should(Text).Be(FormatJsonDateTime(V));
end;

procedure TJsonDatesTests.DriverOffset_WholeMinutes;
var
  V: TDateTime;
  I, Wrong: Integer;
begin
  // The value of #255: 2000-04-02 02:08:15.980
  V := 36618.089073836806;
  Should(TJsonBaseObject.DateTimeToJSON(V, False)).Be(Digits(V) + OffsetText(ExpectedOffset(V)));
  RandSeed := 2026;
  Wrong := 0;
  for I := 1 to 2000 do
  begin
    V := EncodeDate(1950, 1, 1) + Random * (EncodeDate(2060, 1, 1) - EncodeDate(1950, 1, 1));
    if not QuietDay(V) then
      Continue;
    if TJsonBaseObject.DateTimeToJSON(V, False) <> Digits(V) + OffsetText(ExpectedOffset(V)) then
      Inc(Wrong);
  end;
  Should(Wrong).Be(0);
end;

procedure TJsonDatesTests.DriverOffset_BeforeDecember31_1899;
var
  Midnight, Noon: string;
begin
  // 1899-12-30 00:00 and 12:00: the same day, the same offset
  Midnight := TJsonBaseObject.DateTimeToJSON(0, False);
  Noon := TJsonBaseObject.DateTimeToJSON(0.5, False);
  Should(Copy(Midnight, 24, MaxInt)).Be(Copy(Noon, 24, MaxInt));
  Should(Copy(Midnight, 1, 23)).Be('1899-12-30T00:00:00.000');
  // And the writer of the serializers says the same
  Should(FormatJsonDateTime(0)).Be(Midnight);
end;

procedure TJsonDatesTests.Read_DateAndLocal;
begin
  ShouldDate(Parse('2026-07-15')).Be(EncodeDate(2026, 7, 15));
  ShouldDate(Parse('2026-07-15T10:30:00.000')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 0));
  ShouldDate(Parse('2026-07-15T10:30:00')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 0));
  ShouldDate(Parse('2026-07-15T10:30')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 0));
  ShouldDate(Parse('2026-07-15 10:30:00')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 0));
  ShouldDate(Parse('2026-07-15T10:30:00.5')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 500));
  ShouldDate(Parse('2026-07-15T10:30:00.123456')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 123));
  ShouldDate(Parse(' 2026-07-15T10:30:00.000 ')).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 0));
end;

procedure TJsonDatesTests.Read_ZoneToLocal;
var
  Utc: TDateTime;
begin
  Utc := EncodeDateTime(2026, 7, 15, 8, 30, 0, 0);
  ShouldDate(Parse('2026-07-15T08:30:00.000Z')).Be(TTimeZone.Local.ToLocalTime(Utc));
  ShouldDate(Parse('2026-07-15T08:30:00Z')).Be(TTimeZone.Local.ToLocalTime(Utc));
  ShouldDate(Parse('2026-07-15T10:30:00.000+02:00')).Be(TTimeZone.Local.ToLocalTime(Utc));
  ShouldDate(Parse('2026-07-15T10:30:00+0200')).Be(TTimeZone.Local.ToLocalTime(Utc));
  ShouldDate(Parse('2026-07-15T10:30:00+02')).Be(TTimeZone.Local.ToLocalTime(Utc));
  ShouldDate(Parse('2026-07-15T03:00:00-05:30')).Be(TTimeZone.Local.ToLocalTime(Utc));
  // Across midnight
  ShouldDate(Parse('2026-07-16T01:00:00+09:00')).Be(
    TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 7, 15, 16, 0, 0, 0)));
end;

procedure TJsonDatesTests.Read_Refused;

  procedure Refused(const AText: string);
  var
    V: TDateTime;
  begin
    Should(TryParseJsonDateTime(AText, V)).Because(AText).BeFalse;
  end;

begin
  Refused('');
  Refused('abc');
  Refused('2026-13-01');
  Refused('2026-02-30');
  Refused('2026-07-15X10:30');
  Refused('2026-07-15T25:00:00');
  Refused('2026-07-15T10:30:00.');
  Refused('2026-07-15T10:30:00+2');
  Refused('2026-07-15T10:30:00+02:0');
  Refused('2026-07-15T10:30:00+24:00');
  Refused('2026-07-15T10:30:00Zx');
  Refused('15/07/2026');
end;

procedure TJsonDatesTests.Read_Time;
var
  V: TDateTime;
begin
  Should(TryParseJsonTime('10:30:00.000', V)).BeTrue;
  ShouldDate(V).Be(EncodeTime(10, 30, 0, 0));
  Should(TryParseJsonTime('10:30', V)).BeTrue;
  ShouldDate(V).Be(EncodeTime(10, 30, 0, 0));
  Should(TryParseJsonTime('10:30:00Z', V)).BeTrue;
  ShouldDate(V).Be(EncodeTime(10, 30, 0, 0));
  Should(TryParseJsonTime('2026-07-15T10:30:00.000', V)).BeTrue;
  ShouldDate(V).Be(EncodeTime(10, 30, 0, 0));
  Should(TryParseJsonTime('10:30:00x', V)).BeFalse;
  Should(TryParseJsonTime('25:00', V)).BeFalse;
end;

procedure TJsonDatesTests.RoundTrip;
var
  I, Wrong: Integer;
  V: TDateTime;
begin
  RandSeed := 254;
  Wrong := 0;
  for I := 1 to 2000 do
  begin
    V := RecodeMilliSecond(EncodeDate(1950, 1, 1) +
      Random * (EncodeDate(2060, 1, 1) - EncodeDate(1950, 1, 1)), Random(1000));
    // The hour skipped by daylight saving time has no local reading
    if not QuietDay(V) then
      Continue;
    if not SameDateTime(Parse(FormatJsonDateTime(V)), V) then
      Inc(Wrong);
  end;
  Should(Wrong).Be(0);
end;

procedure TJsonDatesTests.CommonDate_ReadsTheZone;
var
  V: TDateTime;
begin
  Should(TryParseCommonDate('2026-07-15T08:30:00.000Z', V)).BeTrue;
  ShouldDate(V).Be(TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 7, 15, 8, 30, 0, 0)));
  // The other forms as before
  Should(TryParseCommonDate('15/07/2026', V)).BeTrue;
  Should(Trunc(V)).Be(Trunc(EncodeDate(2026, 7, 15)));
end;

function SampleWhen: TDateTime;
begin
  Result := EncodeDateTime(2026, 7, 15, 10, 30, 0, 250);
end;

procedure WriteToString(AContext, AData: Pointer; ALength: Integer);
var
  Bytes: TBytes;
begin
  SetLength(Bytes, ALength);
  Move(AData^, Bytes[0], ALength);
  PString(AContext)^ := PString(AContext)^ + TEncoding.UTF8.GetString(Bytes);
end;

procedure TJsonDatesTests.Class_Written;
var
  R: TJsonDatesRow;
begin
  R := TJsonDatesRow.Create;
  try
    R.When := SampleWhen;
    R.Day := EncodeDate(2026, 7, 15);
    R.Clock := EncodeTime(10, 30, 0, 250);
    Should(TDextJson.Serialize(R)).Be('{"When":"' + FormatJsonDateTime(SampleWhen) +
      '","Day":"2026-07-15","Clock":"10:30:00.250"}');
  finally
    R.Free;
  end;
end;

procedure TJsonDatesTests.Class_Read;
var
  R: TJsonDatesRow;
begin
  R := TDextJson.Deserialize<TJsonDatesRow>('{"When":"' + FormatJsonDateTime(SampleWhen) +
    '","Day":"2026-07-15","Clock":"10:30:00.250"}');
  try
    ShouldDate(R.When).Be(SampleWhen);
    ShouldDate(R.Day).Be(EncodeDate(2026, 7, 15));
    ShouldDate(R.Clock).Be(EncodeTime(10, 30, 0, 250));
  finally
    R.Free;
  end;
  R := TDextJson.Deserialize<TJsonDatesRow>('{"When":"2026-07-15T08:30:00.000Z"}');
  try
    ShouldDate(R.When).Be(TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 7, 15, 8, 30, 0, 0)));
  finally
    R.Free;
  end;
  R := TDextJson.Deserialize<TJsonDatesRow>('{"When":"2026-07-15T10:30:00.000+02:00"}');
  try
    ShouldDate(R.When).Be(TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 7, 15, 8, 30, 0, 0)));
  finally
    R.Free;
  end;
  // A local date and time without a zone stays as written
  R := TDextJson.Deserialize<TJsonDatesRow>('{"When":"2026-07-15T10:30:00.000"}');
  try
    ShouldDate(R.When).Be(EncodeDateTime(2026, 7, 15, 10, 30, 0, 0));
  finally
    R.Free;
  end;
end;

procedure TJsonDatesTests.Record_WrittenAndRead;
var
  Rec, Back: TJsonDatesRecord;
  Json: string;
begin
  Rec.When := SampleWhen;
  Rec.Day := EncodeDate(2026, 7, 15);
  Rec.Clock := EncodeTime(10, 30, 0, 250);
  Json := TDextJson.Serialize(Rec);
  Should(Json).Be('{"When":"' + FormatJsonDateTime(SampleWhen) +
    '","Day":"2026-07-15","Clock":"10:30:00.250"}');
  Back := TDextJson.Deserialize<TJsonDatesRecord>(Json);
  ShouldDate(Back.When).Be(SampleWhen);
  ShouldDate(Back.Day).Be(EncodeDate(2026, 7, 15));
  ShouldDate(Back.Clock).Be(EncodeTime(10, 30, 0, 250));
end;

procedure TJsonDatesTests.Arrays_WrittenAndRead;
var
  A, Back: TJsonDatesArrays;
  Json: string;
begin
  A := TJsonDatesArrays.Create;
  try
    A.Moments := [SampleWhen];
    A.Days := [EncodeDate(2026, 7, 15)];
    Json := TDextJson.Serialize(A);
    Should(Json).Be('{"Moments":["' + FormatJsonDateTime(SampleWhen) +
      '"],"Days":["2026-07-15"]}');
    Back := TDextJson.Deserialize<TJsonDatesArrays>(Json);
    try
      ShouldDate(Back.Moments[0]).Be(SampleWhen);
      ShouldDate(Back.Days[0]).Be(EncodeDate(2026, 7, 15));
    finally
      Back.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TJsonDatesTests.Utf8Writer_SameText;
var
  Text: string;
begin
  Text := '';
  TDextJson.SerializeUtf8To(TValue.From<TDateTime>(SampleWhen), @Text, WriteToString);
  Should(Text).Be('"' + FormatJsonDateTime(SampleWhen) + '"');
  Should(GetJsonVal(TValue.From<TDateTime>(SampleWhen))).Be('"' + FormatJsonDateTime(SampleWhen) + '"');
  Should(GetJsonVal(TValue.From<TDate>(EncodeDate(2026, 7, 15)))).Be('"2026-07-15"');
  Should(GetJsonVal(TValue.From<TTime>(EncodeTime(10, 30, 0, 250)))).Be('"10:30:00.250"');
end;

procedure TJsonDatesTests.Utf8Record_Read;
var
  Bytes: TBytes;
  Rec: TJsonDatesRecord;
begin
  Bytes := TEncoding.UTF8.GetBytes(
    '{"When":"2026-07-15T08:30:00Z","Day":"2026-07-15","Clock":"10:30:00.250"}');
  Rec := TUtf8JsonSerializer.Deserialize<TJsonDatesRecord>(TByteSpan.Create(@Bytes[0], Length(Bytes)));
  ShouldDate(Rec.When).Be(TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 7, 15, 8, 30, 0, 0)));
  ShouldDate(Rec.Day).Be(EncodeDate(2026, 7, 15));
  ShouldDate(Rec.Clock).Be(EncodeTime(10, 30, 0, 250));
end;

procedure TJsonDatesTests.CustomFormat_Kept;
var
  R: TJsonDatesRow;
begin
  R := TJsonDatesRow.Create;
  try
    R.When := SampleWhen;
    Should(TDextJson.Serialize(R, TJsonSettings.Default.CustomDateFormat('yyyy-mm-dd"T"hh":"nn":"ss.zzz')))
      .Contain('"When":"2026-07-15T10:30:00.250"');
  finally
    R.Free;
  end;
end;

procedure TJsonDatesTests.CastFromString_ReadsTheZone;
begin
  ShouldDate(TReflection.CastFromString('2026-07-15T08:30:00.000Z', TypeInfo(TDateTime)).AsType<TDateTime>)
    .Be(TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 7, 15, 8, 30, 0, 0)));
  ShouldDate(TReflection.CastFromString('2026-07-15T10:30:00.250', TypeInfo(TDateTime)).AsType<TDateTime>)
    .Be(SampleWhen);
  ShouldDate(TReflection.CastFromString('10:30:00.250', TypeInfo(TTime)).AsType<TDateTime>)
    .Be(EncodeTime(10, 30, 0, 250));
end;

end.
