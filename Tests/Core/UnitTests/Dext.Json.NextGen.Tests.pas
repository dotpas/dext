unit Dext.Json.NextGen.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Core.Span,
  Dext.Json,
  Dext.Json.Types,
  Dext.Core.Json.NextGen;

type
  [TestFixture('JSON NextGen Parser Tests')]
  TJsonNextGenTests = class
  public
    [Test('Should parse primitives correctly (int, double, bool, null)')]
    procedure TestParsePrimitives;

    [Test('Should parse object navigation and property lookups')]
    procedure TestParseObject;

    [Test('Should parse arrays and indexing')]
    procedure TestParseArray;

    [Test('Should reuse object pools correctly')]
    procedure TestPoolRentReturn;

    [Test('Should scan structural chars via SSE42/Pascal fallback')]
    procedure TestScanStructural;

    [Test('Should write and escape JSON correctly')]
    procedure TestWriter;

    [Test('Should raise exceptions on invalid JSON syntax')]
    procedure TestValidationExceptions;

    [Test('Should write 3-byte and 4-byte UTF-8 sequences (U+0800 and above, emoji)')]
    procedure TestWriterUtf8MultiByte;

    [Test('Should keep every character of a string through the writer')]
    procedure TestWriterUtf8RoundTrip;

    [Test('Should write U+FFFD for unpaired surrogates, also at the end of the string')]
    procedure TestWriterUnpairedSurrogates;

    [Test('Should keep characters from U+0800 up in TDextJson.Serialize')]
    procedure TestSerializeKeepsMultiByteChars;

    [Test('NextGen: Should enforce default maximum nesting depth (64)')]
    procedure TestMaxDepthDefaultLimitNextGen;

    [Test('NextGen: Should enforce custom maximum nesting depth')]
    procedure TestMaxDepthCustomLimitNextGen;

    [Test('NextGen: Should allow deep nesting when MaxDepth is unlimited')]
    procedure TestMaxDepthUnlimitedNextGen;

    [Test('JsonDataObjects: Should enforce maximum nesting depth and prevent stack overflow')]
    procedure TestMaxDepthJsonDataObjects;

    [Test('DextJson: Deeply nested JSON should raise EJsonParserException without stack overflow')]
    procedure TestMaxDepthDeeplyNestedNoCrash;
  end;

implementation

uses
  DextJsonDataObjects;

{ TJsonNextGenTests }

procedure TJsonNextGenTests.TestParsePrimitives;
var
  Json: string;
  Bytes: TBytes;
  Node: IDextJsonNode;
  Arr: IDextJsonArray;
begin
  Json := '[123, -456.78, true, false, null]';
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));

  Should(Node <> nil).BeTrue;
  Should(Node.NodeType = TDextJsonNodeType.jntArray).BeTrue;

  Arr := Node as IDextJsonArray;
  Should(Arr.GetCount).Be(5);
  Should(Arr.GetInteger(0)).Be(123);
  Should(Abs(Arr.GetDouble(1) + 456.78) < 0.001).BeTrue;
  Should(Arr.GetBoolean(2)).BeTrue;
  Should(Arr.GetBoolean(3)).BeFalse;
  Should(Arr.GetNode(4).IsNull).BeTrue;
end;

procedure TJsonNextGenTests.TestParseObject;
var
  Json: string;
  Bytes: TBytes;
  Node: IDextJsonNode;
  Obj: IDextJsonObject;
begin
  Json := '{"name": "NextGen", "ver": 2, "active": true}';
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));

  Should(Node <> nil).BeTrue;
  Should(Node.NodeType = TDextJsonNodeType.jntObject).BeTrue;

  Obj := Node as IDextJsonObject;
  Should(Obj.Contains('name')).BeTrue;
  Should(Obj.GetString('name')).Be('NextGen');
  Should(Obj.GetInteger('ver')).Be(2);
  Should(Obj.GetBoolean('active')).BeTrue;
end;

procedure TJsonNextGenTests.TestParseArray;
var
  Json: string;
  Bytes: TBytes;
  Node: IDextJsonNode;
  Arr: IDextJsonArray;
begin
  Json := '["item1", "item2"]';
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));

  Should(Node <> nil).BeTrue;
  Arr := Node as IDextJsonArray;
  Should(Arr.GetString(0)).Be('item1');
  Should(Arr.GetString(1)).Be('item2');
end;

procedure TJsonNextGenTests.TestPoolRentReturn;
var
  Obj: Dext.Core.Json.NextGen.TJsonObject;
  Arr: Dext.Core.Json.NextGen.TJsonArray;
begin
  Obj := TNextGenJsonPool.RentObject;
  Should(Obj <> nil).BeTrue;
  TNextGenJsonPool.ReturnObject(Obj);

  Arr := TNextGenJsonPool.RentArray;
  Should(Arr <> nil).BeTrue;
  TNextGenJsonPool.ReturnArray(Arr);
end;

procedure TJsonNextGenTests.TestScanStructural;
var
  Json: string;
  Bytes: TBytes;
  Idx: Integer;
begin
  Json := '   { "test": 1 }';
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Idx := TNextGenJsonParser.ScanStructural_SSE42(@Bytes[0], Length(Bytes));
  Should(Idx >= 0).BeTrue;
  Should(Bytes[Idx]).Be(Ord('{'));
end;

procedure TJsonNextGenTests.TestWriter;
var
  Writer: TNextGenJsonWriter;
  S: string;
begin
  Writer.Init(1024);
  Writer.StartObject;
  Writer.WritePropertyName('name');
  Writer.WriteStringValue('NextGen \ " Test');
  Writer.WritePropertyName('version');
  Writer.WriteNumber(2);
  Writer.WritePropertyName('active');
  Writer.WriteBoolean(True);
  Writer.WritePropertyName('nullval');
  Writer.WriteNull;
  Writer.EndObject;

  S := Writer.ToString;
  Should(S).Be(
    '{"name":"NextGen \\ \" Test",' +
    '"version":2,"active":true,"nullval":null}'
  );
end;

procedure TJsonNextGenTests.TestValidationExceptions;
var
  Bytes: TBytes;
  Pass: Boolean;
  procedure AssertFail(const AJson: string);
  begin
    Pass := False;
    try
      Bytes := TEncoding.UTF8.GetBytes(AJson);
      TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));
    except
      on E: EJsonException do
        Pass := True;
    end;
    Should(Pass).BeTrue;
  end;
begin
  // fail01: \x invalid escape
  AssertFail('["\x"]');
  // fail02: Objects require colon
  AssertFail('{"a" 1}');
  // fail03: Objects require colon, not comma
  AssertFail('{"a", 1}');
  // fail04: Arrays require comma, not colon
  AssertFail('[1 : 2]');
  // fail05: Invalid literal
  AssertFail('[truth]');
  // fail06: Single quotes not allowed
  AssertFail('[''test'']');
  // fail07: Raw newline in string
  AssertFail('["line'#10'break"]');
  // fail09: Unclosed array
  AssertFail('[1, 2');
  // fail10: Numbers require exponent value
  AssertFail('[1e]');
  // fail11: Single sign allowed
  AssertFail('[+-1]');
  // fail12: Trailing comma in object
  AssertFail('{"a": 1,}');
  // fail15: Key string must be quoted
  AssertFail('{a: 1}');
  // fail16: Trailing comma in array
  AssertFail('[1, 2,]');
  // fail17: Double comma in array
  AssertFail('[1,,2]');
  // fail18: Extra trailing data
  AssertFail('{} {}');
  // fail21: Leading zeros not allowed
  AssertFail('[01]');
  // fail22: Hex numbers not allowed
  AssertFail('[0x1]');
  // fail23: Decimal needs digit before dot
  AssertFail('[.1]');
end;

function BytesToHex(const ABytes: TBytes): string;
var
  B: Byte;
begin
  Result := '';
  for B in ABytes do
    Result := Result + IntToHex(B, 2) + ' ';
  Result := Trim(Result);
end;

function WriteString(const AValue: string): TBytes;
var
  Writer: TNextGenJsonWriter;
begin
  Writer.Init(256);
  Writer.WriteStringValue(AValue);
  Result := Writer.ToBytes;
end;

procedure TJsonNextGenTests.TestWriterUtf8MultiByte;
begin
  // U+0800 (first 3-byte), U+20AC euro, U+2014 em dash, U+FFFD,
  // U+1F600 (a surrogate pair: 4 bytes). Before the fix every one of them
  // vanished without an error, while U+07FF (2 bytes) was kept.
  Should(BytesToHex(WriteString(#$07FF))).Be('22 DF BF 22');
  Should(BytesToHex(WriteString(#$0800))).Be('22 E0 A0 80 22');
  Should(BytesToHex(WriteString(#$20AC))).Be('22 E2 82 AC 22');
  Should(BytesToHex(WriteString(#$2014))).Be('22 E2 80 94 22');
  Should(BytesToHex(WriteString(#$FFFD))).Be('22 EF BF BD 22');
  Should(BytesToHex(WriteString(#$D83D#$DE00))).Be('22 F0 9F 98 80 22');
end;

procedure TJsonNextGenTests.TestWriterUtf8RoundTrip;
const
  Text = 'A' + #$07FF + 'B' + #$0800 + 'C' + #$20AC + 'D' + #$2014 + 'E' +
    #$201C + 'quoted' + #$201D + #$2026 + #$3042 + #$D83D#$DE00 + 'F';
var
  Writer: TNextGenJsonWriter;
begin
  Writer.Init(256);
  Writer.WriteStringValue(Text);
  Should(Writer.ToString).Be('"' + Text + '"');
end;

procedure TJsonNextGenTests.TestWriterUnpairedSurrogates;
begin
  // A high surrogate followed by a normal char: U+FFFD, and the char stays.
  Should(BytesToHex(WriteString(#$D800 + 'A'))).Be('22 EF BF BD 41 22');
  // A lone low surrogate.
  Should(BytesToHex(WriteString('A' + #$DC00))).Be('22 41 EF BF BD 22');
  // A high surrogate at the very end: no read past the string.
  Should(BytesToHex(WriteString('A' + #$D800))).Be('22 41 EF BF BD 22');
end;

procedure TJsonNextGenTests.TestSerializeKeepsMultiByteChars;
const
  Text = 'Detr. 0,10 ' + #$20AC + ' ' + #$2014 + ' ' + #$D83D#$DE00;
var
  Json: string;
begin
  Json := TDextJson.Serialize<TArray<string>>([Text]);
  Should(Json).Be('["' + Text + '"]');
end;

function BuildNestedArrayJson(ADepth: Integer): string;
begin
  Result := StringOfChar('[', ADepth) + '1' + StringOfChar(']', ADepth);
end;

function BuildNestedObjectJson(ADepth: Integer): string;
var
  i: Integer;
  Sb: TStringBuilder;
begin
  Sb := TStringBuilder.Create;
  try
    for i := 1 to ADepth do
      Sb.Append('{"a":');
    Sb.Append('1');
    for i := 1 to ADepth do
      Sb.Append('}');
    Result := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

procedure AssertRaisesParserException(const AProc: TProc);
var
  Passed: Boolean;
begin
  Passed := False;
  try
    AProc();
  except
    on E: Dext.Core.Json.NextGen.EJsonParserException do
      Passed := True;
    on E: DextJsonDataObjects.EJsonParserException do
      Passed := True;
  end;
  Should(Passed).BeTrue;
end;

procedure TJsonNextGenTests.TestMaxDepthDefaultLimitNextGen;
var
  ValidJson: string;
  InvalidJson: string;
  Bytes: TBytes;
  Node: IDextJsonNode;
begin
  // Array: depth 64 should succeed
  ValidJson := BuildNestedArrayJson(64);
  Bytes := TEncoding.UTF8.GetBytes(ValidJson);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));
  Should(Node <> nil).BeTrue;

  // Array: depth 65 should raise EJsonParserException
  InvalidJson := BuildNestedArrayJson(65);
  Bytes := TEncoding.UTF8.GetBytes(InvalidJson);
  AssertRaisesParserException(
    procedure
    begin
      TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));
    end
  );

  // Object: depth 64 should succeed
  ValidJson := BuildNestedObjectJson(64);
  Bytes := TEncoding.UTF8.GetBytes(ValidJson);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));
  Should(Node <> nil).BeTrue;

  // Object: depth 65 should raise EJsonParserException
  InvalidJson := BuildNestedObjectJson(65);
  Bytes := TEncoding.UTF8.GetBytes(InvalidJson);
  AssertRaisesParserException(
    procedure
    begin
      TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes));
    end
  );
end;

procedure TJsonNextGenTests.TestMaxDepthCustomLimitNextGen;
var
  ValidJson: string;
  InvalidJson: string;
  Bytes: TBytes;
  Node: IDextJsonNode;
begin
  // Custom limit of 3
  ValidJson := BuildNestedArrayJson(3);
  Bytes := TEncoding.UTF8.GetBytes(ValidJson);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes), nil, 3);
  Should(Node <> nil).BeTrue;

  InvalidJson := BuildNestedArrayJson(4);
  Bytes := TEncoding.UTF8.GetBytes(InvalidJson);
  AssertRaisesParserException(
    procedure
    begin
      TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes), nil, 3);
    end
  );
end;

procedure TJsonNextGenTests.TestMaxDepthUnlimitedNextGen;
var
  DeepJson: string;
  Bytes: TBytes;
  Node: IDextJsonNode;
begin
  // Depth 100 with UNLIMITED_JSON_DEPTH (-1)
  DeepJson := BuildNestedArrayJson(100);
  Bytes := TEncoding.UTF8.GetBytes(DeepJson);
  Node := TNextGenJsonParser.Parse(TByteSpan.FromBytes(Bytes), nil, UNLIMITED_JSON_DEPTH);
  Should(Node <> nil).BeTrue;
end;

procedure TJsonNextGenTests.TestMaxDepthJsonDataObjects;
var
  ValidJson: string;
  InvalidJson: string;
  Obj: DextJsonDataObjects.TJsonObject;
begin
  // Default limit 64 on TJsonObject.Parse
  ValidJson := BuildNestedObjectJson(64);
  Obj := DextJsonDataObjects.TJsonObject.Parse(ValidJson) as DextJsonDataObjects.TJsonObject;
  try
    Should(Obj <> nil).BeTrue;
  finally
    Obj.Free;
  end;

  // Depth 65 exceeds default 64
  InvalidJson := BuildNestedObjectJson(65);
  AssertRaisesParserException(
    procedure
    begin
      DextJsonDataObjects.TJsonObject.Parse(InvalidJson);
    end
  );

  // Custom limit 5
  InvalidJson := BuildNestedObjectJson(6);
  AssertRaisesParserException(
    procedure
    begin
      DextJsonDataObjects.TJsonObject.Parse(InvalidJson, nil, 5);
    end
  );
end;

procedure TJsonNextGenTests.TestMaxDepthDeeplyNestedNoCrash;
var
  DeepArray: string;
  DeepObject: string;
begin
  // 5000 nested brackets would previously blow stack and crash process
  DeepArray := StringOfChar('[', 5000) + StringOfChar(']', 5000);
  AssertRaisesParserException(
    procedure
    begin
      TNextGenJsonParser.Parse(TByteSpan.FromBytes(TEncoding.UTF8.GetBytes(DeepArray)));
    end
  );

  AssertRaisesParserException(
    procedure
    begin
      DextJsonDataObjects.TJsonObject.Parse(DeepArray);
    end
  );

  // 2000 nested objects
  DeepObject := BuildNestedObjectJson(2000);
  AssertRaisesParserException(
    procedure
    begin
      TNextGenJsonParser.Parse(TByteSpan.FromBytes(TEncoding.UTF8.GetBytes(DeepObject)));
    end
  );

  AssertRaisesParserException(
    procedure
    begin
      DextJsonDataObjects.TJsonObject.Parse(DeepObject);
    end
  );
end;

end.
