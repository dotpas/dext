unit Dext.Json.NullDates.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types,
  Dext.Json.Utf8,
  Dext.Core.DateUtils,
  Dext.Types.Nullable;

type
  /// Plain properties: the RTTI path.
  TNullDatesRow = class
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
  TNullDatesNullableRow = class
  private
    FWhen: Nullable<TDateTime>;
    FDay: Nullable<TDate>;
  public
    property When: Nullable<TDateTime> read FWhen write FWhen;
    property Day: Nullable<TDate> read FDay write FDay;
  end;

  TNullDatesRecord = record
    When: TDateTime;
    Day: TDate;
  end;

  [TestFixture('JSON - NullDates: the dates that mean "no date" for the application')]
  TJsonNullDatesTests = class
  public
    [Test('Without NullDates a sentinel day is written as a date (the default)')]
    procedure Default_SentinelIsADate;
    [Test('A class: the sentinel days are null, on the RTTI and on the direct path')]
    procedure Class_SentinelsNull;
    [Test('A record, an array, a single value and the UTF-8 writer: null')]
    procedure OtherPaths_SentinelsNull;
    [Test('IgnoreNullValues drops them')]
    procedure IgnoreNullValues_Drops;
    [Test('The exact value: a sentinel day with a time is still a date')]
    procedure SentinelWithATime_IsADate;
    [Test('Without ZeroDateAsNull, 1899-12-30 can be listed; a TTime is never "no date"')]
    procedure ZeroDayListed_TimeLeftAlone;
    [Test('A text that is not a day raises; an empty list turns it off')]
    procedure BadText_Raises_EmptyListOff;
  end;

implementation

function Day(Y, M, D: Word): TDateTime;
begin
  Result := EncodeDate(Y, M, D);
end;

function Sentinels: TJsonSettings;
begin
  Result := TJsonSettings.Default.NullDates(['0001-01-01', '1900-01-01']);
end;

{ TJsonNullDatesTests }

procedure TJsonNullDatesTests.Default_SentinelIsADate;
var
  R: TNullDatesRow;
begin
  R := TNullDatesRow.Create;
  try
    R.When := Day(1900, 1, 1);
    R.Day := Day(1, 1, 1);
    R.Clock := EncodeTime(8, 0, 0, 0);
    Should(TDextJson.Serialize(R)).Be('{"When":"' + FormatJsonDateTime(Day(1900, 1, 1)) +
      '","Day":"0001-01-01","Clock":"08:00:00.000"}');
  finally
    R.Free;
  end;
end;

procedure TJsonNullDatesTests.Class_SentinelsNull;
var
  R: TNullDatesRow;
  N: TNullDatesNullableRow;
begin
  R := TNullDatesRow.Create;
  try
    R.When := Day(1900, 1, 1);
    R.Day := Day(1, 1, 1);
    R.Clock := EncodeTime(8, 0, 0, 0);
    Should(TDextJson.Serialize(R, Sentinels)).Be('{"When":null,"Day":null,"Clock":"08:00:00.000"}');
    R.Day := Day(2026, 7, 15);
    Should(TDextJson.Serialize(R, Sentinels)).Be('{"When":null,"Day":"2026-07-15","Clock":"08:00:00.000"}');
  finally
    R.Free;
  end;
  N := TNullDatesNullableRow.Create;
  try
    N.When := Nullable<TDateTime>.Create(Day(1, 1, 1));
    N.Day := Nullable<TDate>.Create(Day(1900, 1, 1));
    Should(TDextJson.Serialize(N, Sentinels)).Be('{"When":null,"Day":null}');
  finally
    N.Free;
  end;
end;

procedure TJsonNullDatesTests.OtherPaths_SentinelsNull;
var
  Rec: TNullDatesRecord;
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
  Saved: TJsonSettings;
  S: UTF8String;
begin
  Rec.When := Day(1, 1, 1);
  Rec.Day := Day(1900, 1, 1);
  Should(TDextJson.Serialize<TNullDatesRecord>(Rec, Sentinels)).Be('{"When":null,"Day":null}');
  Should(TDextJson.Serialize<TArray<TDate>>([Day(1900, 1, 1), Day(2026, 7, 15)], Sentinels)).Be(
    '[null,"2026-07-15"]');
  Should(TDextJson.Serialize<TDateTime>(Day(1900, 1, 1), Sentinels)).Be('{"value":null}');
  Should(GetJsonVal(TValue.From<TDate>(Day(1, 1, 1)), Sentinels)).Be('null');
  // The writer takes the global settings when it is created
  Saved := TDextJson.GetDefaultSettings;
  Stream := TMemoryStream.Create;
  try
    TDextJson.SetDefaultSettings(Sentinels);
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteValue(TValue.From<TDateTime>(Day(1900, 1, 1)));
    SetString(S, PAnsiChar(Stream.Memory), Stream.Size);
    Should(string(S)).Be('null');
  finally
    TDextJson.SetDefaultSettings(Saved);
    Stream.Free;
  end;
end;

procedure TJsonNullDatesTests.IgnoreNullValues_Drops;
var
  Rec: TNullDatesRecord;
begin
  Rec.When := Day(1900, 1, 1);
  Rec.Day := Day(2026, 7, 15);
  Should(TDextJson.Serialize<TNullDatesRecord>(Rec, Sentinels.IgnoreNullValues)).Be(
    '{"Day":"2026-07-15"}');
end;

procedure TJsonNullDatesTests.SentinelWithATime_IsADate;
var
  Rec: TNullDatesRecord;
  When: TDateTime;
begin
  When := Day(1900, 1, 1) + EncodeTime(8, 30, 0, 0);
  Rec.When := When;
  Rec.Day := Day(1900, 1, 1);
  Should(TDextJson.Serialize<TNullDatesRecord>(Rec, Sentinels)).Be(
    '{"When":"' + FormatJsonDateTime(When) + '","Day":null}');
end;

procedure TJsonNullDatesTests.ZeroDayListed_TimeLeftAlone;
var
  R: TNullDatesRow;
  Settings: TJsonSettings;
begin
  Settings := TJsonSettings.Default.ZeroDateAsNull(False).NullDates(['1899-12-30']);
  R := TNullDatesRow.Create;
  try
    Should(TDextJson.Serialize(R, Settings)).Be('{"When":null,"Day":null,"Clock":"00:00:00.000"}');
  finally
    R.Free;
  end;
end;

procedure TJsonNullDatesTests.BadText_Raises_EmptyListOff;
var
  Rec: TNullDatesRecord;
begin
  Should(procedure begin Sentinels.NullDates(['1900-1-1']) end).Throw<EConvertError>;
  Should(procedure begin Sentinels.NullDates(['1900-01-01T00:00:00']) end).Throw<EConvertError>;
  Should(procedure begin Sentinels.NullDates(['1900-02-30']) end).Throw<EConvertError>;
  Should(procedure begin Sentinels.NullDates(['01/01/1900']) end).Throw<EConvertError>;
  Rec.When := Day(1900, 1, 1);
  Rec.Day := Day(1, 1, 1);
  Should(TDextJson.Serialize<TNullDatesRecord>(Rec, Sentinels.NullDates([]))).Be(
    '{"When":"' + FormatJsonDateTime(Day(1900, 1, 1)) + '","Day":"0001-01-01"}');
end;

end.
