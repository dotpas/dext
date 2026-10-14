unit Dext.Json.FormatAttributes.Tests;

interface

uses
  System.SysUtils,
  System.DateUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types;

type
  TJsonFormatClass = class
  private
    FDay: TDateTime;
    FCompact: TDate;
    FId: Int64;
    FPrice: Currency;
    FActive: Boolean;
    FCode: string;
    FFlag: Integer;
    FName: string;
  public
    [JsonFormat('dd/mm/yyyy hh:nn')]
    property Day: TDateTime read FDay write FDay;
    [JsonFormat('yyyymmdd')]
    property Compact: TDate read FCompact write FCompact;
    [JsonString]
    property Id: Int64 read FId write FId;
    [JsonString]
    property Price: Currency read FPrice write FPrice;
    [JsonString]
    property Active: Boolean read FActive write FActive;
    [JsonNumber]
    property Code: string read FCode write FCode;
    [JsonBoolean]
    property Flag: Integer read FFlag write FFlag;
    property Name: string read FName write FName;
  end;

  TJsonFormatRecord = record
    [JsonFormat('mm/dd/yyyy')]
    Day: TDate;
    [JsonString]
    Id: Int64;
    [JsonNumber]
    Code: string;
    [JsonBoolean]
    Enabled: Integer; // not Flag: a record field starting with F is #261
  end;

  TJsonFormatWrongType = class
  private
    FName: string;
  public
    [JsonString]
    property Name: string read FName write FName;
  end;

  TJsonFormatTwoAttributes = class
  private
    FId: Int64;
  public
    [JsonString]
    [JsonBoolean]
    property Id: Int64 read FId write FId;
  end;

  TJsonFormatUnreadable = class
  private
    FDay: TDateTime;
  public
    [JsonFormat('dd mmm yyyy')]
    property Day: TDateTime read FDay write FDay;
  end;

  TJsonFormatWrongRecord = record
    [JsonBoolean]
    Name: string;
  end;

  [TestFixture('JSON - [JsonFormat], [JsonString], [JsonNumber], [JsonBoolean] (#262)')]
  TJsonFormatAttributesTests = class
  public
    [Test('Class, writing: the four attributes')]
    procedure Class_Writes;
    [Test('Class, reading: the attribute form')]
    procedure Class_ReadsAttributeForm;
    [Test('Class, reading: the normal form is read too')]
    procedure Class_ReadsNormalForm;
    [Test('Class, round trip')]
    procedure Class_RoundTrip;
    [Test('Record, writing and reading')]
    procedure Record_WritesAndReads;
    [Test('[JsonFormat] writes with the invariant settings, whatever the locale')]
    procedure Format_Invariant;
    [Test('[JsonString] keeps an Int64 beyond 2^53 exact')]
    procedure String_Int64BeyondJavaScript;
    [Test('[JsonNumber]: empty text is null, text that is not a number stays text')]
    procedure Number_EmptyAndNotANumber;
    [Test('[JsonBoolean]: 0 is false, anything else true')]
    procedure Boolean_ZeroAndNonZero;
    [Test('The date format parser')]
    procedure Parser_TryParseDateWithFormat;
    [Test('An attribute on the wrong type raises')]
    procedure Validate_WrongType;
    [Test('Two attributes on one member raise')]
    procedure Validate_TwoAttributes;
    [Test('A format that cannot be read back raises')]
    procedure Validate_UnreadableFormat;
    [Test('A record field with an attribute on the wrong type raises')]
    procedure Validate_WrongTypeOnRecord;
  end;

implementation

function Sample: TJsonFormatClass;
begin
  Result := TJsonFormatClass.Create;
  Result.Day := EncodeDateTime(2026, 7, 15, 10, 30, 0, 0);
  Result.Compact := EncodeDate(2026, 7, 5);
  Result.Id := 42;
  Result.Price := 12.5;
  Result.Active := True;
  Result.Code := '123';
  Result.Flag := 1;
  Result.Name := 'x';
end;

procedure TJsonFormatAttributesTests.Class_Writes;
var
  C: TJsonFormatClass;
begin
  C := Sample;
  try
    Should(TDextJson.Serialize(C)).Be('{"Day":"15/07/2026 10:30","Compact":"20260705",' +
      '"Id":"42","Price":"12.5","Active":"true","Code":123,"Flag":true,"Name":"x"}');
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Class_ReadsAttributeForm;
var
  C: TJsonFormatClass;
begin
  C := TDextJson.Deserialize<TJsonFormatClass>('{"Day":"16/08/2026 11:45",' +
    '"Compact":"20261231","Id":"9","Price":"7.25","Active":"false","Code":456,' +
    '"Flag":true}');
  try
    Should(C.Day).Be(EncodeDateTime(2026, 8, 16, 11, 45, 0, 0));
    Should(C.Compact).Be(EncodeDate(2026, 12, 31));
    Should(C.Id).Be(9);
    Should(C.Price).Be(7.25);
    Should(C.Active).BeFalse;
    Should(C.Code).Be('456');
    Should(C.Flag).Be(1);
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Class_ReadsNormalForm;
var
  C: TJsonFormatClass;
begin
  C := TDextJson.Deserialize<TJsonFormatClass>('{"Day":"2026-08-16T11:45:00.000",' +
    '"Id":9,"Price":7.25,"Active":true,"Code":"abc","Flag":0}');
  try
    Should(C.Day).Be(EncodeDateTime(2026, 8, 16, 11, 45, 0, 0));
    Should(C.Id).Be(9);
    Should(C.Price).Be(7.25);
    Should(C.Active).BeTrue;
    Should(C.Code).Be('abc');
    Should(C.Flag).Be(0);
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Class_RoundTrip;
var
  C, R: TJsonFormatClass;
begin
  C := Sample;
  try
    R := TDextJson.Deserialize<TJsonFormatClass>(TDextJson.Serialize(C));
    try
      Should(R.Day).Be(C.Day);
      Should(R.Compact).Be(C.Compact);
      Should(R.Id).Be(C.Id);
      Should(R.Price).Be(C.Price);
      Should(R.Active).Be(C.Active);
      Should(R.Code).Be(C.Code);
      Should(R.Flag).Be(C.Flag);
      Should(R.Name).Be(C.Name);
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Record_WritesAndReads;
var
  R, B: TJsonFormatRecord;
  Json: string;
begin
  R.Day := EncodeDate(2026, 7, 5);
  R.Id := 7;
  R.Code := '3.5';
  R.Enabled := 0;
  Json := TDextJson.Serialize(R);
  Should(Json).Be('{"Day":"07/05/2026","Id":"7","Code":3.5,"Enabled":false}');
  B := TDextJson.Deserialize<TJsonFormatRecord>(Json);
  Should(B.Day).Be(R.Day);
  Should(B.Id).Be(7);
  Should(B.Code).Be('3.5');
  Should(B.Enabled).Be(0);
  B := TDextJson.Deserialize<TJsonFormatRecord>('{"Day":"12/31/2026","Enabled":true}');
  Should(B.Day).Be(EncodeDate(2026, 12, 31));
  Should(B.Enabled).Be(1);
end;

procedure TJsonFormatAttributesTests.Format_Invariant;
var
  C: TJsonFormatClass;
  OldDate, OldTime: Char;
begin
  OldDate := FormatSettings.DateSeparator;
  OldTime := FormatSettings.TimeSeparator;
  FormatSettings.DateSeparator := '.';
  FormatSettings.TimeSeparator := '-';
  C := Sample;
  try
    Should(TDextJson.Serialize(C)).Contain('"Day":"15/07/2026 10:30"');
  finally
    C.Free;
    FormatSettings.DateSeparator := OldDate;
    FormatSettings.TimeSeparator := OldTime;
  end;
end;

procedure TJsonFormatAttributesTests.String_Int64BeyondJavaScript;
var
  C, R: TJsonFormatClass;
begin
  C := Sample;
  try
    C.Id := 9007199254740993; // 2^53 + 1: a double cannot hold it
    Should(TDextJson.Serialize(C)).Contain('"Id":"9007199254740993"');
    R := TDextJson.Deserialize<TJsonFormatClass>(TDextJson.Serialize(C));
    try
      Should(R.Id).Be(9007199254740993);
    finally
      R.Free;
    end;
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Number_EmptyAndNotANumber;
var
  C: TJsonFormatClass;
begin
  C := Sample;
  try
    C.Code := '';
    Should(TDextJson.Serialize(C)).Contain('"Code":null');
    C.Code := 'A-12';
    Should(TDextJson.Serialize(C)).Contain('"Code":"A-12"');
    C.Code := '-7';
    Should(TDextJson.Serialize(C)).Contain('"Code":-7');
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Boolean_ZeroAndNonZero;
var
  C: TJsonFormatClass;
begin
  C := Sample;
  try
    C.Flag := 0;
    Should(TDextJson.Serialize(C)).Contain('"Flag":false');
    C.Flag := 5;
    Should(TDextJson.Serialize(C)).Contain('"Flag":true');
  finally
    C.Free;
  end;
end;

procedure TJsonFormatAttributesTests.Parser_TryParseDateWithFormat;
var
  D: TDateTime;
begin
  Should(TJsonUtils.TryParseDateWithFormat('05/07/2026', 'dd/mm/yyyy', D)).BeTrue;
  Should(D).Be(EncodeDate(2026, 7, 5));
  Should(TJsonUtils.TryParseDateWithFormat('5.7.26', 'd.m.yy', D)).BeTrue;
  Should(D).Be(EncodeDate(2026, 7, 5));
  Should(TJsonUtils.TryParseDateWithFormat('2026-07-05T10:30:15.250',
    'yyyy-mm-dd"T"hh:nn:ss.zzz', D)).BeTrue;
  Should(D).Be(EncodeDateTime(2026, 7, 5, 10, 30, 15, 250));
  Should(TJsonUtils.TryParseDateWithFormat('10:30', 'hh:nn', D)).BeTrue;
  Should(D).Be(EncodeTime(10, 30, 0, 0));
  Should(TJsonUtils.TryParseDateWithFormat('31/02/2026', 'dd/mm/yyyy', D)).BeFalse;
  Should(TJsonUtils.TryParseDateWithFormat('05-07-2026', 'dd/mm/yyyy', D)).BeFalse;
  Should(TJsonUtils.TryParseDateWithFormat('05/07/2026x', 'dd/mm/yyyy', D)).BeFalse;
  Should(TJsonUtils.TryParseDateWithFormat('5/07/2026', 'dd/mm/yyyy', D)).BeFalse;
  Should(TJsonUtils.IsReadableDateFormat('dd mmm yyyy')).BeFalse;
  Should(TJsonUtils.IsReadableDateFormat('hh:nn ampm')).BeFalse;
  Should(TJsonUtils.IsReadableDateFormat('yyyymmdd')).BeTrue;
end;

function RaisesJsonException(AProc: TProc): Boolean;
begin
  Result := False;
  try
    AProc();
  except
    on EDextJsonException do
      Result := True;
  end;
end;

procedure TJsonFormatAttributesTests.Validate_WrongType;
begin
  Should(RaisesJsonException(
    procedure
    var
      C: TJsonFormatWrongType;
    begin
      C := TJsonFormatWrongType.Create;
      try
        TDextJson.Serialize(C);
      finally
        C.Free;
      end;
    end)).BeTrue;
end;

procedure TJsonFormatAttributesTests.Validate_TwoAttributes;
begin
  Should(RaisesJsonException(
    procedure
    var
      C: TJsonFormatTwoAttributes;
    begin
      C := TDextJson.Deserialize<TJsonFormatTwoAttributes>('{"Id":"1"}');
      C.Free;
    end)).BeTrue;
end;

procedure TJsonFormatAttributesTests.Validate_UnreadableFormat;
begin
  Should(RaisesJsonException(
    procedure
    var
      C: TJsonFormatUnreadable;
    begin
      C := TJsonFormatUnreadable.Create;
      try
        TDextJson.Serialize(C);
      finally
        C.Free;
      end;
    end)).BeTrue;
end;

procedure TJsonFormatAttributesTests.Validate_WrongTypeOnRecord;
begin
  Should(RaisesJsonException(
    procedure
    var
      R: TJsonFormatWrongRecord;
    begin
      R.Name := 'x';
      TDextJson.Serialize(R);
    end)).BeTrue;
end;

end.
