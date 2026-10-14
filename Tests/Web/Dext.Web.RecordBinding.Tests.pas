unit Dext.Web.RecordBinding.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Web.ModelBinding;

type
  TBindStatus = (bsOpen, bsClosed);

  TBindBody = record
    Id: Integer;
    Name: string;
    Price: Currency;
    Rate: Double;
    Active: Boolean;
    Status: TBindStatus;
    When: TDateTime;
    Key: TGUID;
    Small: Byte;
    Big: Int64;
    Huge: UInt64;
  end;

  // Bound only from the query: an empty body is fine.
  TBindQueryOnly = record
    [FromQuery]
    Id: Integer;
  end;

  // No attribute: from the body, with route and query as fallbacks.
  TBindId = record
    Id: Integer;
    Status: TBindStatus;
  end;

  /// <summary>
  ///   A record bound by the hybrid binder (MapPost&lt;T&gt;, MapGet&lt;T&gt;)
  ///   refuses what it cannot bind: malformed JSON, a body that is not an
  ///   object, an empty body when a field expects it, and a value that does
  ///   not convert to its field type. The client gets a 400 and the handler
  ///   does not run, instead of running with default values.
  /// </summary>
  [TestFixture('Record binding refuses what it cannot bind')]
  TRecordBindingTests = class
  public
    // The rows of the reproduction in #217
    [Test('Valid body: every field type is bound')]
    procedure TestValidBodyBindsEveryType;
    [Test('Malformed JSON -> 400, handler not run')]
    procedure TestMalformedJson;
    [Test('Empty body -> 400, handler not run')]
    procedure TestEmptyBody;
    [Test('JSON array instead of an object -> 400, handler not run')]
    procedure TestArrayBody;
    [Test('"abc" for an Integer -> 400 naming the field, handler not run')]
    procedure TestStringForInteger;
    // Conversions
    [Test('"7" for an Integer is accepted')]
    procedure TestNumericStringForInteger;
    [Test('7.5 for an Integer -> 400')]
    procedure TestFractionForInteger;
    [Test('300 for a Byte -> 400')]
    procedure TestOutOfRange;
    // A JSON number is converted from its text as written, so the range and
    // fraction checks see the real value.
    [Test('Int64 above 2^53 is bound with its exact value')]
    procedure TestInt64AboveDoublePrecision;
    [Test('Int64 one past High(Int64) -> 400, not wrapped')]
    procedure TestInt64Overflow;
    [Test('UInt64 above High(Int64) is bound')]
    procedure TestUInt64AboveInt64;
    [Test('A number with an exponent for a Double is bound')]
    procedure TestExponentForDouble;
    [Test('Enum by ordinal number is bound')]
    procedure TestEnumByOrdinal;
    [Test('A number or a Boolean for a string is taken as its JSON text')]
    procedure TestNumberAndBooleanForString;
    [Test('"maybe" for a Boolean -> 400')]
    procedure TestInvalidBoolean;
    [Test('Enum by name is bound (it became the first member)')]
    procedure TestEnumByName;
    [Test('Unknown enum name -> 400')]
    procedure TestUnknownEnum;
    [Test('"yesterday" for a TDateTime -> 400')]
    procedure TestInvalidDate;
    [Test('"xyz" for a TGUID -> 400')]
    procedure TestInvalidGuid;
    [Test('An object for a string -> 400')]
    procedure TestObjectForString;
    [Test('A JSON string is taken as written, not URL-decoded')]
    procedure TestStringNotUrlDecoded;
    // What stays accepted
    [Test('Fields missing from the body keep their defaults')]
    procedure TestMissingFieldsKeepDefaults;
    [Test('null keeps the default')]
    procedure TestNullKeepsDefault;
    [Test('Empty body, record bound only from the query: accepted')]
    procedure TestEmptyBodyQueryOnlyRecord;
    [Test('Empty body, body field provided by the query fallback: accepted')]
    procedure TestEmptyBodyQueryFallback;
    // Route, query and header values
    [Test('GET: "abc" in the query for an Integer -> 400')]
    procedure TestQueryIntegerNotANumber;
    [Test('GET: enum by name in the query is bound')]
    procedure TestQueryEnumByName;
  end;

implementation

uses
  System.DateUtils,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.WebApplication,
  Dext.Testing.WebApplicationFactory;

var
  // What the handlers received.
  Ran: Boolean;
  Received: TBindBody;
  ReceivedId: TBindId;
  ReceivedQueryOnly: TBindQueryOnly;

function CreateFactory: TDextApplicationFactory<TObject>;
begin
  Ran := False;
  Received := Default(TBindBody);
  ReceivedId := Default(TBindId);
  ReceivedQueryOnly := Default(TBindQueryOnly);
  Result := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.Builder.MapPost<TBindBody>('/bind/body',
          procedure(B: TBindBody)
          begin
            Ran := True;
            Received := B;
          end);
        App.Builder.MapPost<TBindQueryOnly>('/bind/query-only',
          procedure(B: TBindQueryOnly)
          begin
            Ran := True;
            ReceivedQueryOnly := B;
          end);
        App.Builder.MapPost<TBindId>('/bind/id',
          procedure(B: TBindId)
          begin
            Ran := True;
            ReceivedId := B;
          end);
        App.Builder.MapGet<TBindId>('/bind/get',
          procedure(B: TBindId)
          begin
            Ran := True;
            ReceivedId := B;
          end);
      end);
end;

procedure PostBody(const AJson: string; out AStatus: Integer; out ABody: string);
var
  Factory: TDextApplicationFactory<TObject>;
  Resp: IDextTestHttpResponse;
begin
  Factory := CreateFactory;
  try
    Resp := Factory.CreateClient.PostJson('/bind/body', AJson);
    AStatus := Resp.StatusCode;
    ABody := Resp.Body;
  finally
    Factory.Free;
  end;
end;

procedure ShouldRefuse(const AJson: string; const AField: string = '');
var
  Status: Integer;
  Body: string;
begin
  PostBody(AJson, Status, Body);
  Should(Status).Be(400);
  Should(Ran).BeFalse;
  if AField <> '' then
    Should(Body).Contain('Field \"' + AField + '\"');
end;

procedure ShouldAccept(const AJson: string);
var
  Status: Integer;
  Body: string;
begin
  PostBody(AJson, Status, Body);
  Should(Ran).BeTrue;
end;

{ TRecordBindingTests }

procedure TRecordBindingTests.TestValidBodyBindsEveryType;
begin
  ShouldAccept('{"Id":7,"Name":"Ann","Price":12.34,"Rate":0.5,"Active":true,' +
    '"Status":"bsClosed","When":"2026-10-05T10:30:00Z",' +
    '"Key":"{A1B2C3D4-0000-0000-0000-000000000001}","Small":200}');
  Should(Received.Id).Be(7);
  Should(Received.Name).Be('Ann');
  Should(Received.Price = 12.34).BeTrue;
  Should(Received.Rate).Be(0.5);
  Should(Received.Active).BeTrue;
  Should(Ord(Received.Status)).Be(Ord(bsClosed));
  // The 'Z' is UTC: converted to the local time of this machine
  Should(FormatDateTime('yyyy-mm-dd hh:nn', Received.When)).Be(FormatDateTime('yyyy-mm-dd hh:nn',
    TTimeZone.Local.ToLocalTime(EncodeDateTime(2026, 10, 5, 10, 30, 0, 0))));
  Should(GUIDToString(Received.Key)).Be('{A1B2C3D4-0000-0000-0000-000000000001}');
  Should(Integer(Received.Small)).Be(200);
end;

procedure TRecordBindingTests.TestMalformedJson;
begin
  ShouldRefuse('{x');
end;

procedure TRecordBindingTests.TestEmptyBody;
begin
  ShouldRefuse('');
end;

procedure TRecordBindingTests.TestArrayBody;
begin
  ShouldRefuse('[1,2,3]');
end;

procedure TRecordBindingTests.TestStringForInteger;
begin
  ShouldRefuse('{"Id":"abc"}', 'Id');
end;

procedure TRecordBindingTests.TestNumericStringForInteger;
begin
  ShouldAccept('{"Id":"7"}');
  Should(Received.Id).Be(7);
end;

procedure TRecordBindingTests.TestFractionForInteger;
begin
  ShouldRefuse('{"Id":7.5}', 'Id');
end;

procedure TRecordBindingTests.TestOutOfRange;
begin
  ShouldRefuse('{"Small":300}', 'Small');
end;

procedure TRecordBindingTests.TestInt64AboveDoublePrecision;
begin
  // 2^53 + 1: through a Double it was written as 9.00719925474099E15 and
  // refused.
  ShouldAccept('{"Big":9007199254740993}');
  Should(Received.Big = 9007199254740993).BeTrue;
end;

procedure TRecordBindingTests.TestInt64Overflow;
begin
  ShouldRefuse('{"Big":9223372036854775808}', 'Big');
end;

procedure TRecordBindingTests.TestUInt64AboveInt64;
begin
  ShouldAccept('{"Huge":18446744073709551615}');
  Should(Received.Huge = High(UInt64)).BeTrue;
end;

procedure TRecordBindingTests.TestExponentForDouble;
begin
  ShouldAccept('{"Rate":1.5e2}');
  Should(Received.Rate).Be(150.0);
end;

procedure TRecordBindingTests.TestEnumByOrdinal;
begin
  ShouldAccept('{"Status":1}');
  Should(Ord(Received.Status)).Be(Ord(bsClosed));
end;

procedure TRecordBindingTests.TestNumberAndBooleanForString;
begin
  ShouldAccept('{"Name":12.50}');
  Should(Received.Name).Be('12.50');
  ShouldAccept('{"Name":true}');
  Should(Received.Name).Be('true');
end;

procedure TRecordBindingTests.TestInvalidBoolean;
begin
  ShouldRefuse('{"Active":"maybe"}', 'Active');
end;

procedure TRecordBindingTests.TestEnumByName;
begin
  ShouldAccept('{"Status":"bsClosed"}');
  Should(Ord(Received.Status)).Be(Ord(bsClosed));
end;

procedure TRecordBindingTests.TestUnknownEnum;
begin
  ShouldRefuse('{"Status":"bsNope"}', 'Status');
end;

procedure TRecordBindingTests.TestInvalidDate;
begin
  ShouldRefuse('{"When":"yesterday"}', 'When');
end;

procedure TRecordBindingTests.TestInvalidGuid;
begin
  ShouldRefuse('{"Key":"xyz"}', 'Key');
end;

procedure TRecordBindingTests.TestObjectForString;
begin
  ShouldRefuse('{"Name":{"a":1}}', 'Name');
end;

procedure TRecordBindingTests.TestStringNotUrlDecoded;
begin
  ShouldAccept('{"Name":"a+b 100%"}');
  Should(Received.Name).Be('a+b 100%');
end;

procedure TRecordBindingTests.TestMissingFieldsKeepDefaults;
begin
  ShouldAccept('{"Id":7}');
  Should(Received.Id).Be(7);
  Should(Received.Name).Be('');
  Should(Ord(Received.Status)).Be(Ord(bsOpen));
end;

procedure TRecordBindingTests.TestNullKeepsDefault;
begin
  ShouldAccept('{"Id":null,"Name":"Ann"}');
  Should(Received.Id).Be(0);
  Should(Received.Name).Be('Ann');
end;

procedure TRecordBindingTests.TestEmptyBodyQueryOnlyRecord;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory;
  try
    Factory.CreateClient.PostJson('/bind/query-only?Id=5', '');
    Should(Ran).BeTrue;
    Should(ReceivedQueryOnly.Id).Be(5);
  finally
    Factory.Free;
  end;
end;

procedure TRecordBindingTests.TestEmptyBodyQueryFallback;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory;
  try
    Factory.CreateClient.PostJson('/bind/id?Id=5&Status=bsClosed', '');
    Should(Ran).BeTrue;
    Should(ReceivedId.Id).Be(5);
  finally
    Factory.Free;
  end;
end;

procedure TRecordBindingTests.TestQueryIntegerNotANumber;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory;
  try
    Should(Factory.CreateClient.Get('/bind/get?Id=abc').StatusCode).Be(400);
    Should(Ran).BeFalse;
  finally
    Factory.Free;
  end;
end;

procedure TRecordBindingTests.TestQueryEnumByName;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory;
  try
    Factory.CreateClient.Get('/bind/get?Id=3&Status=bsClosed');
    Should(Ran).BeTrue;
    Should(ReceivedId.Id).Be(3);
    Should(Ord(ReceivedId.Status)).Be(Ord(bsClosed));
  finally
    Factory.Free;
  end;
end;

end.
