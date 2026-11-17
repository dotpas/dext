{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{***************************************************************************}

unit Dext.Web.Binding.Tests;

interface

uses
  System.Classes,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Auth.Identity,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Core.Reflection,
  Dext.DI.Interfaces,
  Dext.Entity.Attributes,
  Dext.Testing,
  Dext.Web.Interfaces,
  Dext.Web.ModelBinding,
  Dext.Server.Engine.Interfaces;

type
  { Mocks }

  TMockHttpRequest = class(TInterfacedObject, IHttpRequest)
  private
    FQuery: IStringDictionary;
    FHeaders: IStringDictionary;
    FRouteParams: TRouteValueDictionary;
    FBody: TStream;
    FPath: string;
    FPathBase: string;
  public
    constructor Create;
    destructor Destroy; override;
    function GetMethod: string;
    function GetPath: string;
    procedure SetPath(const AValue: string);
    function GetPathBase: string;
    procedure SetPathBase(const AValue: string);
    function ToAppUrl(const ARelativePath: string): string;
    function GetQuery: IStringDictionary;
    function GetBody: TStream;
    function GetRouteParams: TRouteValueDictionary;
    function GetHeaders: IStringDictionary;
    function GetRemoteIpAddress: string;
    function GetHeader(const AName: string): string;
    function GetQueryParam(const AName: string): string;
    function GetCookies: IStringDictionary;
    function GetFiles: IFormFileCollection;
    property PathBase: string read GetPathBase write SetPathBase;
  end;

  TMockHttpContext = class(TInterfacedObject, IHttpContext)
  private
    FRequest: IHttpRequest;
    FEndpointMetadata: TEndpointMetadata;
  public
    constructor Create(ARequest: IHttpRequest);
    function GetConnection: IDextServerConnection;
    function GetRequest: IHttpRequest;
    function GetResponse: IHttpResponse;
    procedure SetResponse(const AValue: IHttpResponse);
    function GetServices: IServiceProvider;
    procedure SetServices(const AValue: IServiceProvider);
    function GetUser: IClaimsPrincipal;
    procedure SetUser(const AValue: IClaimsPrincipal);
    function GetItems: IDictionary<string, TValue>;
    function GetSession: IStreamableSession;
    procedure SetRouteParams(const AParams: TRouteValueDictionary);
    function GetEndpointMetadata: TEndpointMetadata;
    procedure SetEndpointMetadata(const AMetadata: TEndpointMetadata);

    property EndpointMetadata: TEndpointMetadata
      read GetEndpointMetadata write SetEndpointMetadata;
  end;

  { Test Models }

  {$M+}{$RTTI EXPLICIT FIELDS([vcPrivate..vcPublic]) PROPERTIES([vcPrivate..vcPublic])}
  TTestRecord = record
    [DefaultValue('John Doe')]
    Name: string;
    [DefaultValue(25)]
    Age: Integer;
    [DefaultValue('2024-01-01')]
    JoinDate: TDateTime;
  end;
  {$M-}

  TTestClass = class
  private
    FName: string;
    FAge: Integer;
  public
    [DefaultValue('Jane Doe')]
    property Name: string read FName write FName;
    [DefaultValue(30)]
    property Age: Integer read FAge write FAge;
  end;

  TDummyController = class
    procedure Action([DefaultValue('Dext')] Name: string; [DefaultValue(100)] Score: Integer);
    procedure MultiBodyAction(
      [FromBody] const codice: string;
      [FromBody] const denominazione: string;
      [FromBody] [DefaultValue('DefaultPiano')] const piano: string;
      [FromBody] const note: string);
    procedure ArrayAction(
      [FromBody] const tables: TArray<string>;
      [FromBody] const codes: TArray<Integer>;
      [FromBody] const names: TArray<string>);
  end;

  [TestClass]
  TWebBindingTests = class
  private
    FBinder: IModelBinder;
    function CreateMockContext(AQueryParams: TArray<string> = []): IHttpContext;
    function CreateMockContextWithBody(const AJson: string): IHttpContext;
  public
    [Setup]
    procedure Setup;
    
    [Test]
    procedure Test_BindParameter_With_DefaultValue;
    
    [Test]
    procedure Test_BindRecord_Hybrid_With_DefaultValue;

    [Test]
    procedure Test_BindQuery_Class_With_DefaultValue;

    [Test]
    procedure Test_BindBodyPrimitive_Present;

    [Test]
    procedure Test_BindBodyPrimitive_Absent_WithDefaultValue;

    [Test]
    procedure Test_BindBodyPrimitive_Absent_NoDefaultValue;

    [Test]
    procedure Test_BindBodyPrimitive_Array_In_Object;

    [Test]
    procedure Test_BindBodyPrimitive_Array_Direct;

    [Test]
    procedure Test_BindBodyPrimitive_Array_Malformed;

    [Test]
    procedure Test_BindBodyPrimitive_String_Not_UrlDecoded;

    [Test]
    procedure Test_BindBodyPrimitive_BareString_Not_UrlDecoded;

    [Test]
    procedure Test_CastFromString_Decode_Default_And_Plain;
  end;

implementation

{ TMockHttpRequest }

constructor TMockHttpRequest.Create;
begin
  inherited;
  FQuery := TDextStringDictionary.Create;
  FHeaders := TDextStringDictionary.Create;
  FRouteParams.Clear;
  FBody := nil;
end;

destructor TMockHttpRequest.Destroy;
begin
  FBody.Free;
  inherited;
end;

function TMockHttpRequest.GetBody: TStream; begin Result := FBody; end;
function TMockHttpRequest.GetCookies: IStringDictionary; begin Result := nil; end;
function TMockHttpRequest.GetFiles: IFormFileCollection; begin Result := nil; end;
function TMockHttpRequest.GetHeader(const AName: string): string; begin if not FHeaders.TryGetValue(AName, Result) then Result := ''; end;
function TMockHttpRequest.GetHeaders: IStringDictionary; begin Result := FHeaders; end;
function TMockHttpRequest.GetMethod: string; begin Result := 'GET'; end;
function TMockHttpRequest.GetPath: string; begin if FPath <> '' then Result := FPath else Result := '/'; end;
procedure TMockHttpRequest.SetPath(const AValue: string); begin FPath := AValue; end;
function TMockHttpRequest.GetPathBase: string; begin Result := FPathBase; end;
procedure TMockHttpRequest.SetPathBase(const AValue: string); begin FPathBase := AValue; end;
function TMockHttpRequest.ToAppUrl(const ARelativePath: string): string;
var
  LBase, LRel: string;
begin
  LBase := GetPathBase;
  LRel := ARelativePath;
  if LBase = '/' then LBase := '';
  if (LRel <> '') and not LRel.StartsWith('/') then LRel := '/' + LRel;
  Result := LBase + LRel;
  if Result = '' then Result := '/';
end;
function TMockHttpRequest.GetQuery: IStringDictionary; begin Result := FQuery; end;
function TMockHttpRequest.GetQueryParam(const AName: string): string; begin if not FQuery.TryGetValue(AName, Result) then Result := ''; end;
function TMockHttpRequest.GetRemoteIpAddress: string; begin Result := '127.0.0.1'; end;
function TMockHttpRequest.GetRouteParams: TRouteValueDictionary; begin Result := FRouteParams; end;

{ TMockHttpContext }

constructor TMockHttpContext.Create(ARequest: IHttpRequest);
begin
  inherited Create;
  FRequest := ARequest;
end;

function TMockHttpContext.GetConnection: IDextServerConnection; begin Result := nil; end;
function TMockHttpContext.GetItems: IDictionary<string, TValue>; begin Result := nil; end;
function TMockHttpContext.GetSession: IStreamableSession; begin Result := nil; end;
function TMockHttpContext.GetRequest: IHttpRequest; begin Result := FRequest; end;
function TMockHttpContext.GetResponse: IHttpResponse; begin Result := nil; end;
function TMockHttpContext.GetServices: IServiceProvider; begin Result := nil; end;
function TMockHttpContext.GetUser: IClaimsPrincipal; begin Result := nil; end;
procedure TMockHttpContext.SetResponse(const AValue: IHttpResponse); begin end;
procedure TMockHttpContext.SetUser(const AValue: IClaimsPrincipal); begin end;
procedure TMockHttpContext.SetServices(const AValue: IServiceProvider); begin end;

function TMockHttpContext.GetEndpointMetadata: TEndpointMetadata;
begin
  Result := FEndpointMetadata;
end;

procedure TMockHttpContext.SetEndpointMetadata(
  const AMetadata: TEndpointMetadata
);
begin
  FEndpointMetadata := AMetadata;
end;

procedure TMockHttpContext.SetRouteParams(const AParams: TRouteValueDictionary);
begin
  if FRequest is TMockHttpRequest then
    TMockHttpRequest(FRequest).FRouteParams := AParams;
end;

{ TDummyController }

procedure TDummyController.Action(Name: string; Score: Integer); begin end;
procedure TDummyController.MultiBodyAction(const codice, denominazione, piano, note: string); begin end;
procedure TDummyController.ArrayAction(const tables: TArray<string>; const codes: TArray<Integer>; const names: TArray<string>); begin end;

{ TWebBindingTests }

procedure TWebBindingTests.Setup;
begin
  FBinder := TModelBinder.Create;
end;

function TWebBindingTests.CreateMockContext(AQueryParams: TArray<string>): IHttpContext;
var
  Req: TMockHttpRequest;
  I: Integer;
begin
  Req := TMockHttpRequest.Create;
  I := 0;
  while I < Length(AQueryParams) do
  begin
    Req.FQuery.Add(AQueryParams[I], AQueryParams[I+1]);
    Inc(I, 2);
  end;
  Result := TMockHttpContext.Create(Req);
end;

function TWebBindingTests.CreateMockContextWithBody(const AJson: string): IHttpContext;
var
  Req: TMockHttpRequest;
  Bytes: TBytes;
begin
  Req := TMockHttpRequest.Create;
  if AJson <> '' then
  begin
    Bytes := TEncoding.UTF8.GetBytes(AJson);
    Req.FBody := TBytesStream.Create(Bytes);
  end;
  Result := TMockHttpContext.Create(Req);
end;

procedure TWebBindingTests.Test_BindParameter_With_DefaultValue;
var
  Context: IHttpContext;
  Val: TValue;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
begin
  Context := CreateMockContext([]); // Empty query
  Meth := Ctx.GetType(TDummyController).GetMethod('Action');
  
  // Param 1: Name
  Param := Meth.GetParameters[0];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsString).Be('Dext');
  
  // Param 2: Score
  Param := Meth.GetParameters[1];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsInteger).Be(100);
  
  // Now with values in query
  Context := CreateMockContext(['Name', 'NewName', 'Score', '200']);
  
  Param := Meth.GetParameters[0];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsString).Be('NewName');
  
  // Actually, for query parameters it uses lowercase typically or exact match?
  // Our model binding currently seems to match case as found in earlier conversation fixes.
  
  Param := Meth.GetParameters[1];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsInteger).Be(200);
end;

procedure TWebBindingTests.Test_BindRecord_Hybrid_With_DefaultValue;
var
  Context: IHttpContext;
  Rec: TTestRecord;
begin
  Context := CreateMockContext([]); // Empty
  
  Rec := FBinder.BindRecordHybrid(TypeInfo(TTestRecord), Context).AsType<TTestRecord>;
  
  Should(Rec.Name).Be('John Doe');
  Should(Rec.Age).Be(25);
  Should(FormatDateTime('yyyy-mm-dd', Rec.JoinDate)).Be('2024-01-01');
end;

procedure TWebBindingTests.Test_BindQuery_Class_With_DefaultValue;
var
  Context: IHttpContext;
  Obj: TTestClass;
begin
  Context := CreateMockContext([]); // Empty
  
  Obj := TModelBinderHelper.BindQuery<TTestClass>(FBinder, Context);
  try
    Should(Obj.Name).Be('Jane Doe');
    Should(Obj.Age).Be(30);
  finally
    Obj.Free;
  end;
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_Present;
var
  Context: IHttpContext;
  Val: TValue;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
begin
  Context := CreateMockContextWithBody('{"codice":"acme","denominazione":"ACME"}');
  Meth := Ctx.GetType(TDummyController).GetMethod('MultiBodyAction');
  
  // Param 0: codice
  Param := Meth.GetParameters[0];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsString).Be('acme');
  
  // Param 1: denominazione
  Param := Meth.GetParameters[1];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsString).Be('ACME');
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_Absent_WithDefaultValue;
var
  Context: IHttpContext;
  Val: TValue;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
begin
  Context := CreateMockContextWithBody('{"codice":"acme","denominazione":"ACME"}'); // piano is omitted
  Meth := Ctx.GetType(TDummyController).GetMethod('MultiBodyAction');
  
  // Param 2: piano
  Param := Meth.GetParameters[2];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsString).Be('DefaultPiano');
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_Absent_NoDefaultValue;
var
  Context: IHttpContext;
  Val: TValue;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
begin
  Context := CreateMockContextWithBody('{"codice":"acme","denominazione":"ACME"}'); // note is omitted
  Meth := Ctx.GetType(TDummyController).GetMethod('MultiBodyAction');
  
  // Param 3: note
  Param := Meth.GetParameters[3];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.AsString).Be('');
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_Array_In_Object;
var
  Context: IHttpContext;
  Val: TValue;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
  ArrStr: TArray<string>;
  ArrInt: TArray<Integer>;
begin
  Context := CreateMockContextWithBody('{"tables":["Comuni","Province"],"codes":[10,20],"names":null}');
  Meth := Ctx.GetType(TDummyController).GetMethod('ArrayAction');
  
  // Param 0: tables
  Param := Meth.GetParameters[0];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.IsArray).BeTrue;
  ArrStr := Val.AsType<TArray<string>>;
  Should(Length(ArrStr)).Be(2);
  Should(ArrStr[0]).Be('Comuni');
  Should(ArrStr[1]).Be('Province');

  // Param 1: codes
  Param := Meth.GetParameters[1];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.IsArray).BeTrue;
  ArrInt := Val.AsType<TArray<Integer>>;
  Should(Length(ArrInt)).Be(2);
  Should(ArrInt[0]).Be(10);
  Should(ArrInt[1]).Be(20);

  // Param 2: names (null)
  Param := Meth.GetParameters[2];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.IsArray).BeTrue;
  Should(Length(Val.AsType<TArray<string>>)).Be(0);
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_Array_Direct;
var
  Context: IHttpContext;
  Val: TValue;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
  ArrStr: TArray<string>;
begin
  Context := CreateMockContextWithBody('["One","Two","Three"]');
  Meth := Ctx.GetType(TDummyController).GetMethod('ArrayAction');
  
  // Param 0: tables
  Param := Meth.GetParameters[0];
  Val := FBinder.BindParameter(Param, Context);
  Should(Val.IsArray).BeTrue;
  ArrStr := Val.AsType<TArray<string>>;
  Should(Length(ArrStr)).Be(3);
  Should(ArrStr[0]).Be('One');
  Should(ArrStr[1]).Be('Two');
  Should(ArrStr[2]).Be('Three');
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_Array_Malformed;
var
  Context: IHttpContext;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
  Param: TRttiParameter;
begin
  Context := CreateMockContextWithBody('["One", "Two"');
  Meth := Ctx.GetType(TDummyController).GetMethod('ArrayAction');
  Param := Meth.GetParameters[0];
  Assert.WillRaise(
    procedure
    begin
      FBinder.BindParameter(Param, Context);
    end,
    EBindingException
  );
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_String_Not_UrlDecoded;
var
  Context: IHttpContext;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
begin
  // A JSON string is plain text: '+' and '%xx' must arrive as they were sent
  // (Base64, hashes, signatures, passwords).
  Context := CreateMockContextWithBody(
    '{"codice":"a+b","denominazione":"100%41","note":"AQID+/8="}');
  Meth := Ctx.GetType(TDummyController).GetMethod('MultiBodyAction');
  Should(FBinder.BindParameter(Meth.GetParameters[0], Context).AsString).Be('a+b');
  Should(FBinder.BindParameter(Meth.GetParameters[1], Context).AsString).Be('100%41');
  Should(FBinder.BindParameter(Meth.GetParameters[3], Context).AsString).Be('AQID+/8=');
end;

procedure TWebBindingTests.Test_BindBodyPrimitive_BareString_Not_UrlDecoded;
var
  Context: IHttpContext;
  Ctx: TRttiContext;
  Meth: TRttiMethod;
begin
  // The whole body is a JSON string
  Context := CreateMockContextWithBody('"a+b%41"');
  Meth := Ctx.GetType(TDummyController).GetMethod('MultiBodyAction');
  Should(FBinder.BindParameter(Meth.GetParameters[0], Context).AsString).Be('a+b%41');
end;

procedure TWebBindingTests.Test_CastFromString_Decode_Default_And_Plain;
begin
  // Route, query and header values: URL-decoded by default, as before
  Should(TReflection.CastFromString('a+b%41', TypeInfo(string)).AsString).Be('a bA');
  // Plain text (a JSON string): left as it is
  Should(TReflection.CastFromString('a+b%41', TypeInfo(string), False).AsString).Be('a+b%41');
  Should(TReflection.CastFromString('42', TypeInfo(Integer), False).AsInteger).Be(42);
end;

end.
