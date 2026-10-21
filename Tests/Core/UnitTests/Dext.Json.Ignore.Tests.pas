unit Dext.Json.Ignore.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Core.Span,
  Dext.Json,
  Dext.Json.Types,
  Dext.Json.Utf8.Serializer;

type
  /// A class with every kind of [JsonIgnore].
  TJsonIgnoreRow = class
  private
    FCode: string;
    FInternal: string;
    FPassword: string;
    FTotal: Integer;
    FHidden: string;
  public
    property Code: string read FCode write FCode;
    // Neither written nor read
    [JsonIgnore]
    property Internal: string read FInternal write FInternal;
    // Read, not written
    [JsonIgnore(TJsonIgnoreMode.OnWrite)]
    property Password: string read FPassword write FPassword;
    // Written, not read
    [JsonIgnore(TJsonIgnoreMode.OnRead)]
    property Total: Integer read FTotal write FTotal;
    // The explicit form of [JsonIgnore]
    [JsonIgnore(TJsonIgnoreMode.Always)]
    property Hidden: string read FHidden write FHidden;
  end;

  {$M+}
  /// Only the published properties reach the JSON, in both directions.
  [JsonPublishedOnly]
  TJsonIgnorePublishedOnly = class
  private
    FName: string;
    FWork: string;
  public
    property Work: string read FWork write FWork;
  published
    property Name: string read FName write FName;
  end;

  /// [JsonPublishedOnly] is inherited.
  TJsonIgnorePublishedOnlyChild = class(TJsonIgnorePublishedOnly)
  private
    FMore: string;
  public
    property More: string read FMore write FMore;
  end;

  /// A class holding another one: the nested object follows the same rules.
  TJsonIgnoreParent = class
  private
    FChild: TJsonIgnoreRow;
  public
    constructor Create;
    destructor Destroy; override;
    property Child: TJsonIgnoreRow read FChild write FChild;
  end;

  /// The same as TJsonIgnoreRow, as a record.
  TJsonIgnoreRecord = record
    Code: string;
    [JsonIgnore]
    Internal: string;
    [JsonIgnore(TJsonIgnoreMode.OnWrite)]
    Password: string;
    [JsonIgnore(TJsonIgnoreMode.OnRead)]
    Total: Integer;
  end;

  [TestFixture('JSON - [JsonIgnore] and [JsonPublishedOnly] when reading, and the one-direction ignore')]
  TJsonIgnoreTests = class
  public
    // Classes
    [Test('Reading a class does not set a [JsonIgnore] property')]
    procedure Class_Read_SkipsJsonIgnore;
    [Test('Reading a class with case-insensitive names does not set a [JsonIgnore] property')]
    procedure Class_Read_CaseInsensitive_SkipsJsonIgnore;
    [Test('Populate leaves a [JsonIgnore] property as it was')]
    procedure Class_Populate_KeepsJsonIgnore;
    [Test('A nested object does not get its [JsonIgnore] property set')]
    procedure Class_Nested_SkipsJsonIgnore;
    [Test('Reading a [JsonPublishedOnly] class does not set its public properties')]
    procedure Class_Read_PublishedOnly;
    [Test('Reading a subclass of a [JsonPublishedOnly] class does not set its public properties')]
    procedure Class_Read_PublishedOnly_Inherited;
    [Test('OnWrite: not written, read')]
    procedure Class_OnWrite_ReadNotWritten;
    [Test('OnRead: written, not read')]
    procedure Class_OnRead_WrittenNotRead;
    [Test('Always and [JsonIgnore]: neither written nor read')]
    procedure Class_Always_NeitherWrittenNorRead;
    // Records
    [Test('Record: [JsonIgnore] neither written nor read')]
    procedure Record_JsonIgnore_NeitherWrittenNorRead;
    [Test('Record: OnWrite read, not written; OnRead written, not read')]
    procedure Record_OneDirection;
    [Test('The UTF-8 record deserializer (body binding) skips what is ignored on read')]
    procedure Utf8Record_SkipsIgnoredOnRead;
  end;

implementation

const
  // Every member of TJsonIgnoreRow / TJsonIgnoreRecord in the JSON
  FullJson = '{"Code":"C","Internal":"i","Password":"p","Total":7,"Hidden":"h"}';

{ TJsonIgnoreParent }

constructor TJsonIgnoreParent.Create;
begin
  inherited Create;
  FChild := TJsonIgnoreRow.Create;
end;

destructor TJsonIgnoreParent.Destroy;
begin
  FChild.Free;
  inherited;
end;

function Utf8Record(const AJson: string): TJsonIgnoreRecord;
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AJson);
  Result := TUtf8JsonSerializer.Deserialize<TJsonIgnoreRecord>(
    TByteSpan.Create(@Bytes[0], Length(Bytes)));
end;

{ TJsonIgnoreTests }

procedure TJsonIgnoreTests.Class_Read_SkipsJsonIgnore;
var
  R: TJsonIgnoreRow;
begin
  R := TDextJson.Deserialize<TJsonIgnoreRow>(FullJson);
  try
    Should(R.Code).Be('C');
    Should(R.Internal).Be('');
    Should(R.Hidden).Be('');
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_Read_CaseInsensitive_SkipsJsonIgnore;
var
  R: TJsonIgnoreRow;
begin
  R := TDextJson.Deserialize<TJsonIgnoreRow>(
    '{"code":"C","internal":"i","total":7}',
    TJsonSettings.Default.CaseInsensitive);
  try
    Should(R.Code).Be('C');
    Should(R.Internal).Be('');
    Should(R.Total).Be(0);
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_Populate_KeepsJsonIgnore;
var
  R: TJsonIgnoreRow;
  S: TDextSerializer;
begin
  R := TJsonIgnoreRow.Create;
  S := TDextSerializer.Create(TJsonSettings.Default);
  try
    R.Internal := 'kept';
    R.Total := 42;
    S.Populate(R, FullJson);
    Should(R.Code).Be('C');
    Should(R.Internal).Be('kept');
    Should(R.Total).Be(42);
    Should(R.Password).Be('p');
  finally
    S.Free;
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_Nested_SkipsJsonIgnore;
var
  P: TJsonIgnoreParent;
begin
  P := TDextJson.Deserialize<TJsonIgnoreParent>('{"Child":' + FullJson + '}');
  try
    Should(P.Child.Code).Be('C');
    Should(P.Child.Internal).Be('');
    Should(P.Child.Total).Be(0);
    Should(P.Child.Password).Be('p');
  finally
    P.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_Read_PublishedOnly;
var
  R: TJsonIgnorePublishedOnly;
begin
  R := TDextJson.Deserialize<TJsonIgnorePublishedOnly>('{"Name":"n","Work":"w"}');
  try
    Should(R.Name).Be('n');
    Should(R.Work).Be('');
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_Read_PublishedOnly_Inherited;
var
  R: TJsonIgnorePublishedOnlyChild;
begin
  R := TDextJson.Deserialize<TJsonIgnorePublishedOnlyChild>(
    '{"Name":"n","Work":"w","More":"m"}');
  try
    Should(R.Name).Be('n');
    Should(R.Work).Be('');
    Should(R.More).Be('');
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_OnWrite_ReadNotWritten;
var
  R: TJsonIgnoreRow;
begin
  R := TDextJson.Deserialize<TJsonIgnoreRow>(FullJson);
  try
    Should(R.Password).Be('p');
    Should(TDextJson.Serialize(R)).NotContain('Password');
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_OnRead_WrittenNotRead;
var
  R: TJsonIgnoreRow;
begin
  R := TDextJson.Deserialize<TJsonIgnoreRow>(FullJson);
  try
    Should(R.Total).Be(0);
    R.Total := 9;
    Should(TDextJson.Serialize(R)).Contain('"Total":9');
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Class_Always_NeitherWrittenNorRead;
var
  R: TJsonIgnoreRow;
  Json: string;
begin
  R := TJsonIgnoreRow.Create;
  try
    R.Code := 'C';
    R.Internal := 'i';
    R.Hidden := 'h';
    R.Total := 9;
    Json := TDextJson.Serialize(R);
    Should(Json).Be('{"Code":"C","Total":9}');
  finally
    R.Free;
  end;
end;

procedure TJsonIgnoreTests.Record_JsonIgnore_NeitherWrittenNorRead;
var
  R: TJsonIgnoreRecord;
begin
  R := TDextJson.Deserialize<TJsonIgnoreRecord>(FullJson);
  Should(R.Code).Be('C');
  Should(R.Internal).Be('');
  R.Internal := 'i';
  Should(TDextJson.Serialize<TJsonIgnoreRecord>(R)).NotContain('Internal');
end;

procedure TJsonIgnoreTests.Record_OneDirection;
var
  R: TJsonIgnoreRecord;
  Json: string;
begin
  R := TDextJson.Deserialize<TJsonIgnoreRecord>(FullJson);
  Should(R.Password).Be('p');
  Should(R.Total).Be(0);
  R.Total := 9;
  Json := TDextJson.Serialize<TJsonIgnoreRecord>(R);
  Should(Json).NotContain('Password');
  Should(Json).Contain('"Total":9');
end;

procedure TJsonIgnoreTests.Utf8Record_SkipsIgnoredOnRead;
var
  R: TJsonIgnoreRecord;
begin
  R := Utf8Record(FullJson);
  Should(R.Code).Be('C');
  Should(R.Internal).Be('');
  Should(R.Total).Be(0);
  Should(R.Password).Be('p');
end;

end.
