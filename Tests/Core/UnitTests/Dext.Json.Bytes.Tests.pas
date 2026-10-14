unit Dext.Json.Bytes.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Core.Span,
  Dext.Json,
  Dext.Json.Types,
  Dext.Json.Utf8.Serializer;

type
  /// A dynamic array of Byte with its own type: binary data too.
  TJsonBytesOwn = array of Byte;

  TJsonBytesRow = class
  private
    FName: string;
    FData: TBytes;
  public
    property Name: string read FName write FName;
    property Data: TBytes read FData write FData;
  end;

  TJsonBytesOwnRow = class
  private
    FData: TJsonBytesOwn;
  public
    property Data: TJsonBytesOwn read FData write FData;
  end;

  TJsonBytesManyRow = class
  private
    FParts: TArray<TBytes>;
  public
    property Parts: TArray<TBytes> read FParts write FParts;
  end;

  TJsonBytesRecord = record
    Name: string;
    Data: TBytes;
  end;

  [TestFixture('JSON - TBytes as Base64 (#256)')]
  TJsonBytesTests = class
  public
    // Writing
    [Test('A TBytes property is written as Base64 on one line, with padding')]
    procedure Class_WritesBase64;
    [Test('A long TBytes has no line breaks (not the MIME form)')]
    procedure Class_LongData_OneLine;
    [Test('Any dynamic array of Byte is binary data')]
    procedure Class_OwnByteArrayType;
    [Test('A record field is written as Base64')]
    procedure Record_WritesBase64;
    [Test('An array of TBytes is an array of Base64 strings')]
    procedure ArrayOfBytes_WritesStrings;
    [Test('A TBytes as the root is a Base64 string')]
    procedure Root_WritesString;
    [Test('BytesAsBase64(False) writes an array of numbers, as before')]
    procedure BytesAsBase64Off_WritesNumbers;
    [Test('The UTF-8 writer writes a TBytes value as Base64')]
    procedure Utf8Writer_WritesBase64;
    // Reading
    [Test('Reading a class: Base64, URL alphabet, no padding, MIME line breaks')]
    procedure Class_ReadsEveryBase64Form;
    [Test('Reading a class: an array of numbers, as written before')]
    procedure Class_ReadsArrayOfNumbers;
    [Test('Reading a class: what is not Base64 raises and names the field')]
    procedure Class_RefusesWhatIsNotBase64;
    [Test('Reading a class: a number outside 0..255 or not whole raises')]
    procedure Class_RefusesBadNumbers;
    [Test('Reading a class: a value that is neither a string nor an array raises')]
    procedure Class_RefusesOtherValues;
    [Test('Reading a record field and an array of TBytes')]
    procedure Record_And_ArrayOfBytes_Read;
    [Test('Reading a TBytes as the root, as a string and as an array')]
    procedure Root_Reads;
    [Test('Written and read back, Base64 and numbers')]
    procedure RoundTrip;
    [Test('The UTF-8 record deserializer (body binding) reads Base64 and numbers')]
    procedure Utf8Record_Reads;
    [Test('The UTF-8 record deserializer refuses what is not binary data')]
    procedure Utf8Record_Refuses;
    // The rules of the decoder
    [Test('TryBase64ToBytes: what is accepted and what is refused')]
    procedure TryBase64ToBytes_Rules;
  end;

implementation

const
  // $00 $01 $FE $FF $41 $42: the two characters + and / both appear
  Sample: array[0..5] of Byte = ($00, $01, $FE, $FF, $41, $42);
  SampleBase64 = 'AAH+/0FC';

function SampleBytes: TBytes;
begin
  SetLength(Result, Length(Sample));
  Move(Sample[0], Result[0], Length(Sample));
end;

function Hex(const ABytes: array of Byte): string;
var
  B: Byte;
begin
  Result := '';
  for B in ABytes do
    Result := Result + IntToHex(B, 2);
end;

function Utf8Record(const AJson: string): TJsonBytesRecord;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AJson);
  Result := TUtf8JsonSerializer.Deserialize<TJsonBytesRecord>(
    TByteSpan.Create(@Bytes[0], Length(Bytes)));
end;

procedure WriteToString(AContext, AData: Pointer; ALength: Integer);
var
  Bytes: TBytes;
begin
  SetLength(Bytes, ALength);
  Move(AData^, Bytes[0], ALength);
  PString(AContext)^ := PString(AContext)^ + TEncoding.UTF8.GetString(Bytes);
end;

{ TJsonBytesTests }

procedure TJsonBytesTests.Class_WritesBase64;
var
  R: TJsonBytesRow;
begin
  R := TJsonBytesRow.Create;
  try
    R.Name := 'x';
    R.Data := SampleBytes;
    Should(TDextJson.Serialize(R)).Be('{"Name":"x","Data":"' + SampleBase64 + '"}');
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Class_LongData_OneLine;
var
  R: TJsonBytesRow;
  Json: string;
  I: Integer;
  Data: TBytes;
begin
  R := TJsonBytesRow.Create;
  try
    SetLength(Data, 300);
    for I := 0 to High(Data) do
      Data[I] := Byte(I * 7);
    R.Data := Data;
    Json := TDextJson.Serialize(R);
    Should(Json).NotContain(#10);
    Should(Json).NotContain('\n');
    Should(Json).Contain('"Data":"' + TJsonUtils.BytesToBase64(Data) + '"');
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Class_OwnByteArrayType;
var
  R: TJsonBytesOwnRow;
  Data: TJsonBytesOwn;
begin
  R := TJsonBytesOwnRow.Create;
  try
    SetLength(Data, 3);
    Data[0] := $41;
    Data[1] := $42;
    Data[2] := $43;
    R.Data := Data;
    Should(TDextJson.Serialize(R)).Be('{"Data":"QUJD"}');
  finally
    R.Free;
  end;
  R := TDextJson.Deserialize<TJsonBytesOwnRow>('{"Data":"QUJD"}');
  try
    Should(Hex(R.Data)).Be('414243');
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Record_WritesBase64;
var
  Rec: TJsonBytesRecord;
begin
  Rec.Name := 'x';
  Rec.Data := SampleBytes;
  Should(TDextJson.Serialize(Rec)).Be('{"Name":"x","Data":"' + SampleBase64 + '"}');
end;

procedure TJsonBytesTests.ArrayOfBytes_WritesStrings;
var
  R: TJsonBytesManyRow;
begin
  R := TJsonBytesManyRow.Create;
  try
    R.Parts := [SampleBytes, TEncoding.ASCII.GetBytes('ABC')];
    Should(TDextJson.Serialize(R)).Be('{"Parts":["' + SampleBase64 + '","QUJD"]}');
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Root_WritesString;
begin
  Should(TDextJson.Serialize<TBytes>(SampleBytes)).Be('"' + SampleBase64 + '"');
  Should(TDextJson.Serialize(TValue.From<TBytes>(SampleBytes))).Be('"' + SampleBase64 + '"');
end;

procedure TJsonBytesTests.BytesAsBase64Off_WritesNumbers;
var
  R: TJsonBytesRow;
  Rec: TJsonBytesRecord;
  Settings: TJsonSettings;
begin
  Settings := TJsonSettings.Default.BytesAsBase64(False);
  R := TJsonBytesRow.Create;
  try
    R.Name := 'x';
    R.Data := SampleBytes;
    Should(TDextJson.Serialize(R, Settings)).Be('{"Name":"x","Data":[0,1,254,255,65,66]}');
  finally
    R.Free;
  end;
  Rec.Name := 'x';
  Rec.Data := SampleBytes;
  Should(TDextJson.Serialize(Rec, Settings)).Be('{"Name":"x","Data":[0,1,254,255,65,66]}');
  Should(TDextJson.Serialize<TBytes>(SampleBytes, Settings)).Be('[0,1,254,255,65,66]');
end;

procedure TJsonBytesTests.Utf8Writer_WritesBase64;
var
  Text: string;
begin
  Text := '';
  TDextJson.SerializeUtf8To(TValue.From<TBytes>(SampleBytes), @Text, WriteToString);
  Should(Text).Be('"' + SampleBase64 + '"');
  // With Base64 off, and any other array: the array, not its type name
  Text := '';
  TDextJson.SerializeUtf8To(TValue.From<TBytes>(SampleBytes),
    TJsonSettings.Default.BytesAsBase64(False), @Text, WriteToString);
  Should(Text).Be('[0,1,254,255,65,66]');
  Text := '';
  TDextJson.SerializeUtf8To(TValue.From<TArray<Integer>>([1, 2, 3]), @Text, WriteToString);
  Should(Text).Be('[1,2,3]');
end;

procedure TJsonBytesTests.Class_ReadsEveryBase64Form;
var
  R: TJsonBytesRow;

  procedure Check(const AJsonValue: string);
  begin
    R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":' + AJsonValue + '}');
    try
      Should(Hex(R.Data)).Be(Hex(Sample));
    finally
      R.Free;
    end;
  end;

begin
  Check('"AAH+/0FC"');      // standard
  Check('"AAH-_0FC"');      // URL alphabet
  Check('"AAH+\n/0FC"');    // MIME: a line break in the middle
  Check('"AAH+ /0FC"');     // a space
  Check('"AAH+\/0FC"');     // the '/' escaped by the writer
  // Without padding: "QUI" is "AB", "QUI=" with it
  R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":"QUI"}');
  try
    Should(Hex(R.Data)).Be('4142');
  finally
    R.Free;
  end;
  R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":"QUI="}');
  try
    Should(Hex(R.Data)).Be('4142');
  finally
    R.Free;
  end;
  // An empty text is an empty array
  R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":""}');
  try
    Should(Length(R.Data)).Be(0);
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Class_ReadsArrayOfNumbers;
var
  R: TJsonBytesRow;
begin
  R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":[0,1,254,255,65,66]}');
  try
    Should(Hex(R.Data)).Be(Hex(Sample));
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Class_RefusesWhatIsNotBase64;

  procedure Refused(const AJsonValue: string);
  begin
    Should(
      procedure
      var
        R: TJsonBytesRow;
      begin
        R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":' + AJsonValue + '}');
        R.Free;
      end).Throw<EDextJsonException>.ThrowWithMessageContaining('"Data"');
  end;

begin
  Refused('"not base64!"');   // a character outside both alphabets
  Refused('"AAH+_0FC"');      // the two alphabets mixed
  Refused('"QU=I"');          // a '=' in the middle
  Refused('"QUJDR"');         // 5 characters: a last group of 1 is impossible
  Refused('"QQ==="');         // three '='
end;

procedure TJsonBytesTests.Class_RefusesBadNumbers;

  procedure Refused(const AJsonValue: string);
  begin
    Should(
      procedure
      var
        R: TJsonBytesRow;
      begin
        R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":' + AJsonValue + '}');
        R.Free;
      end).Throw<EDextJsonException>;
  end;

begin
  Refused('[1,256]');
  Refused('[-1]');
  Refused('[1.5]');
  Refused('["1"]');
  Refused('[[1]]');
end;

procedure TJsonBytesTests.Class_RefusesOtherValues;
begin
  Should(
    procedure
    var
      R: TJsonBytesRow;
    begin
      R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":12}');
      R.Free;
    end).Throw<EDextJsonException>.ThrowWithMessageContaining('"Data"');
  Should(
    procedure
    var
      R: TJsonBytesRow;
    begin
      R := TDextJson.Deserialize<TJsonBytesRow>('{"Data":{"a":1}}');
      R.Free;
    end).Throw<EDextJsonException>;
end;

procedure TJsonBytesTests.Record_And_ArrayOfBytes_Read;
var
  Rec: TJsonBytesRecord;
  R: TJsonBytesManyRow;
begin
  Rec := TDextJson.Deserialize<TJsonBytesRecord>('{"Name":"x","Data":"' + SampleBase64 + '"}');
  Should(Rec.Name).Be('x');
  Should(Hex(Rec.Data)).Be(Hex(Sample));
  Rec := TDextJson.Deserialize<TJsonBytesRecord>('{"Name":"x","Data":[0,1,254,255,65,66]}');
  Should(Hex(Rec.Data)).Be(Hex(Sample));

  R := TDextJson.Deserialize<TJsonBytesManyRow>('{"Parts":["' + SampleBase64 + '",[65,66,67]]}');
  try
    Should(Length(R.Parts)).Be(2);
    Should(Hex(R.Parts[0])).Be(Hex(Sample));
    Should(Hex(R.Parts[1])).Be('414243');
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Root_Reads;
begin
  Should(Hex(TDextJson.Deserialize<TBytes>('"' + SampleBase64 + '"'))).Be(Hex(Sample));
  Should(Hex(TDextJson.Deserialize<TBytes>(' "' + SampleBase64 + '" '))).Be(Hex(Sample));
  Should(Hex(TDextJson.Deserialize<TBytes>('[0,1,254,255,65,66]'))).Be(Hex(Sample));
  Should(Hex(TDextJson.Deserialize(TypeInfo(TBytes), '"' + SampleBase64 + '"',
    TJsonSettings.Default).AsType<TBytes>)).Be(Hex(Sample));
  Should(
    procedure
    begin
      TDextJson.Deserialize<TBytes>('[300]');
    end).Throw<EDextJsonException>;
  Should(
    procedure
    begin
      TDextJson.Deserialize<TBytes>('"not base64!"');
    end).Throw<EDextJsonException>;
end;

procedure TJsonBytesTests.RoundTrip;
var
  R, Back: TJsonBytesRow;
  Data: TBytes;
  I: Integer;
begin
  SetLength(Data, 256);
  for I := 0 to 255 do
    Data[I] := Byte(I);
  R := TJsonBytesRow.Create;
  try
    R.Data := Data;
    Back := TDextJson.Deserialize<TJsonBytesRow>(TDextJson.Serialize(R));
    try
      Should(Hex(Back.Data)).Be(Hex(Data));
    finally
      Back.Free;
    end;
    Back := TDextJson.Deserialize<TJsonBytesRow>(
      TDextJson.Serialize(R, TJsonSettings.Default.BytesAsBase64(False)));
    try
      Should(Hex(Back.Data)).Be(Hex(Data));
    finally
      Back.Free;
    end;
  finally
    R.Free;
  end;
end;

procedure TJsonBytesTests.Utf8Record_Reads;
var
  Rec: TJsonBytesRecord;
begin
  Rec := Utf8Record('{"Name":"x","Data":"' + SampleBase64 + '"}');
  Should(Rec.Name).Be('x');
  Should(Hex(Rec.Data)).Be(Hex(Sample));
  Rec := Utf8Record('{"Data":"AAH-_0FC","Name":"y"}');
  Should(Rec.Name).Be('y');
  Should(Hex(Rec.Data)).Be(Hex(Sample));
  Rec := Utf8Record('{"Data":[0,1,254,255,65,66],"Name":"z"}');
  Should(Rec.Name).Be('z');
  Should(Hex(Rec.Data)).Be(Hex(Sample));
  Rec := Utf8Record('{"Data":[],"Name":"w"}');
  Should(Rec.Name).Be('w');
  Should(Length(Rec.Data)).Be(0);
end;

procedure TJsonBytesTests.Utf8Record_Refuses;
begin
  Should(
    procedure
    begin
      Utf8Record('{"Data":"not base64!"}');
    end).Throw<EUtf8SerializationException>.ThrowWithMessageContaining('"Data"');
  Should(
    procedure
    begin
      Utf8Record('{"Data":[1,256]}');
    end).Throw<EUtf8SerializationException>;
  Should(
    procedure
    begin
      Utf8Record('{"Data":[1.5]}');
    end).Throw<EUtf8SerializationException>;
  Should(
    procedure
    begin
      Utf8Record('{"Data":12}');
    end).Throw<EUtf8SerializationException>;
end;

procedure TJsonBytesTests.TryBase64ToBytes_Rules;
var
  B: TBytes;
begin
  Should(TJsonUtils.TryBase64ToBytes('', B)).BeTrue;
  Should(Length(B)).Be(0);
  Should(TJsonUtils.TryBase64ToBytes('QQ', B)).BeTrue;
  Should(Hex(B)).Be('41');
  Should(TJsonUtils.TryBase64ToBytes('QQ==', B)).BeTrue;
  Should(Hex(B)).Be('41');
  Should(TJsonUtils.TryBase64ToBytes(#13#10'QU'#13#10'JD'#13#10, B)).BeTrue;
  Should(Hex(B)).Be('414243');
  Should(TJsonUtils.TryBase64ToBytes('Q', B)).BeFalse;
  Should(TJsonUtils.TryBase64ToBytes('QQ=Q', B)).BeFalse;
  Should(TJsonUtils.TryBase64ToBytes('+-', B)).BeFalse;
  Should(TJsonUtils.TryBase64ToBytes('QQ!', B)).BeFalse;
  Should(Length(B)).Be(0);
  Should(TJsonUtils.BytesToBase64(nil)).Be('');
  Should(TJsonUtils.BytesToBase64(SampleBytes)).Be(SampleBase64);
end;

end.
