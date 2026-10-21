unit Dext.Web.Routing.Versioning.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes;

type
  /// <summary>
  ///   Versioned routes (#244). A version that no route on the path serves,
  ///   or no version where every route requires one, answers 400 with a
  ///   problem document, not 405. A route that declares the requested
  ///   version wins over an unversioned route on the same path, whatever the
  ///   registration order; the unversioned route is the fallback.
  /// </summary>
  [TestFixture('Routing - API versions')]
  TApiVersionRoutingTests = class
  public
    [Test('A supported version reaches its route (query and header)')]
    procedure SupportedVersion_ReachesItsRoute;
    [Test('A version no route serves -> 400 UnsupportedApiVersion, not 405')]
    procedure UnsupportedVersion_400;
    [Test('A version no route serves, from the header -> 400 UnsupportedApiVersion')]
    procedure UnsupportedVersion_FromHeader_400;
    [Test('No version where every route requires one -> 400 ApiVersionUnspecified')]
    procedure NoVersion_400Unspecified;
    [Test('A parameter path with a version no route serves -> 400')]
    procedure UnsupportedVersion_ParameterPath_400;
    [Test('The requested version in the problem document is escaped')]
    procedure UnsupportedVersion_IsEscaped;
    [Test('A wrong method on a versioned path is still 405')]
    procedure WrongMethod_Still405;
    [Test('The exact version wins over the unversioned route, both orders, literal path')]
    procedure ExactVersionWins_Literal;
    [Test('The exact version wins over the unversioned route, both orders, parameter path')]
    procedure ExactVersionWins_Parameter;
    [Test('The unversioned route is the fallback: no version, or a version no route declares')]
    procedure Unversioned_IsTheFallback;
    [Test('Custom query version reader (?v=2.0)')]
    procedure CustomQueryVersionReader;
    [Test('Custom header version reader (X-Api-Version: 2.0)')]
    procedure CustomHeaderVersionReader;
    [Test('Custom composite version reader (Header X-Custom-Ver, fallback query ?ver=)')]
    procedure CustomCompositeVersionReader;
  end;

implementation

uses
  System.JSON,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.Extensions,
  Dext.Web.WebApplication,
  Dext.Testing.WebApplicationFactory;

procedure MapNamed(App: TWebApplication; const AMethod, APath, AName: string;
  const AVersion: string = '');
var
  Builder: IApplicationBuilder;
  Handler: TStaticHandler;
begin
  Builder := App.GetApplicationBuilder;
  Handler :=
    procedure(Ctx: IHttpContext)
    begin
      Ctx.Response.Write(AName);
    end;
  if AMethod = 'POST' then
    Builder.MapPost(APath, Handler)
  else
    Builder.MapGet(APath, Handler);
  if AVersion <> '' then
    TWebRouteHelpers.HasApiVersion(Builder, AVersion);
end;

function CreateFactory: TDextApplicationFactory<TObject>;
begin
  Result := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        // Two versions of one path
        MapNamed(App, 'GET', '/v', 'one', '1.0');
        MapNamed(App, 'GET', '/v', 'two', '2.0');
        // A parameter path, one version
        MapNamed(App, 'GET', '/c/{id}', 'c1', '1.0');
        // Versioned and unversioned on the same path, both orders
        MapNamed(App, 'GET', '/m', 'm2', '2.0');
        MapNamed(App, 'GET', '/m', 'mplain');
        MapNamed(App, 'GET', '/n', 'nplain');
        MapNamed(App, 'GET', '/n', 'n2', '2.0');
        MapNamed(App, 'GET', '/k/{id}', 'kplain');
        MapNamed(App, 'GET', '/k/{id}', 'k2', '2.0');
        MapNamed(App, 'GET', '/j/{id}', 'j2', '2.0');
        MapNamed(App, 'GET', '/j/{id}', 'jplain');
        // Unversioned only
        MapNamed(App, 'GET', '/u', 'u');
      end);
end;

function Get(const APath: string; const AHeader: string = '';
  const AValue: string = ''): IDextTestHttpResponse;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
begin
  Factory := CreateFactory;
  try
    Client := Factory.CreateClient;
    if AHeader <> '' then
      Client := Client.Header(AHeader, AValue);
    Result := Client.Get(APath);
  finally
    Factory.Free;
  end;
end;

function Post(const APath: string): IDextTestHttpResponse;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory;
  try
    Result := Factory.CreateClient.Post(APath);
  finally
    Factory.Free;
  end;
end;

procedure ShouldBeVersionProblem(const AResp: IDextTestHttpResponse;
  const ACode: string);
var
  Json: TJSONValue;
begin
  Should(AResp.StatusCode).Be(400);
  Should(AResp.ContentType).Contain('application/problem+json');
  Json := TJSONObject.ParseJSONValue(AResp.Body);
  try
    Should(Json <> nil).BeTrue.Because('the body is a JSON document');
    Should(Json.GetValue<Integer>('status')).Be(400);
    Should(Json.GetValue<string>('code')).Be(ACode);
  finally
    Json.Free;
  end;
end;

{ TApiVersionRoutingTests }

procedure TApiVersionRoutingTests.SupportedVersion_ReachesItsRoute;
begin
  Should(Get('/v?api-version=2.0').Body).Be('two');
  Should(Get('/v?api-version=1.0').Body).Be('one');
  Should(Get('/v', 'X-Version', '2.0').Body).Be('two');
  Should(Get('/c/5?api-version=1.0').Body).Be('c1');
end;

procedure TApiVersionRoutingTests.UnsupportedVersion_400;
var
  Resp: IDextTestHttpResponse;
begin
  Resp := Get('/v?api-version=3.0');
  ShouldBeVersionProblem(Resp, 'UnsupportedApiVersion');
  Should(Resp.Body).Contain('3.0');
  Should(Resp.GetHeader('Allow')).Be('');
end;

procedure TApiVersionRoutingTests.UnsupportedVersion_FromHeader_400;
begin
  ShouldBeVersionProblem(Get('/v', 'X-Version', '3.0'), 'UnsupportedApiVersion');
end;

procedure TApiVersionRoutingTests.NoVersion_400Unspecified;
begin
  ShouldBeVersionProblem(Get('/v'), 'ApiVersionUnspecified');
  ShouldBeVersionProblem(Get('/c/5'), 'ApiVersionUnspecified');
end;

procedure TApiVersionRoutingTests.UnsupportedVersion_ParameterPath_400;
begin
  ShouldBeVersionProblem(Get('/c/5?api-version=3.0'), 'UnsupportedApiVersion');
end;

procedure TApiVersionRoutingTests.UnsupportedVersion_IsEscaped;
var
  Resp: IDextTestHttpResponse;
begin
  // ShouldBeVersionProblem parses the body: a raw quote would break it.
  Resp := Get('/v', 'X-Version', '3"x');
  ShouldBeVersionProblem(Resp, 'UnsupportedApiVersion');
end;

procedure TApiVersionRoutingTests.WrongMethod_Still405;
var
  Resp: IDextTestHttpResponse;
begin
  Resp := Post('/v?api-version=1.0');
  Should(Resp.StatusCode).Be(405);
  Should(Resp.GetHeader('Allow')).Contain('GET');
end;

procedure TApiVersionRoutingTests.ExactVersionWins_Literal;
begin
  // /m: 2.0 registered first; /n: unversioned registered first
  Should(Get('/m?api-version=2.0').Body).Be('m2');
  Should(Get('/n?api-version=2.0').Body).Be('n2');
end;

procedure TApiVersionRoutingTests.ExactVersionWins_Parameter;
begin
  // /k: unversioned registered first; /j: 2.0 registered first
  Should(Get('/k/1?api-version=2.0').Body).Be('k2');
  Should(Get('/j/1?api-version=2.0').Body).Be('j2');
end;

procedure TApiVersionRoutingTests.Unversioned_IsTheFallback;
begin
  Should(Get('/m').Body).Be('mplain');
  Should(Get('/n').Body).Be('nplain');
  Should(Get('/k/1').Body).Be('kplain');
  Should(Get('/j/1').Body).Be('jplain');
  Should(Get('/m?api-version=3.0').Body).Be('mplain');
  Should(Get('/j/1?api-version=3.0').Body).Be('jplain');
  Should(Get('/u?api-version=9.0').Body).Be('u');
end;

procedure TApiVersionRoutingTests.CustomQueryVersionReader;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
begin
  Factory := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.GetApplicationBuilder.UseApiVersionReader(
          TQueryStringApiVersionReader.Create('v')
        );
        MapNamed(App, 'GET', '/custom', 'v1', '1.0');
        MapNamed(App, 'GET', '/custom', 'v2', '2.0');
      end);
  try
    Client := Factory.CreateClient;
    Should(Client.Get('/custom?v=2.0').Body).Be('v2');
    Should(Client.Get('/custom?v=1.0').Body).Be('v1');
    // Using default api-version should NOT be recognized now
    ShouldBeVersionProblem(Client.Get('/custom?api-version=2.0'), 'ApiVersionUnspecified');
  finally
    Factory.Free;
  end;
end;

procedure TApiVersionRoutingTests.CustomHeaderVersionReader;
  function CallHeader(const AHeader, AValue: string): IDextTestHttpResponse;
  var
    Factory: TDextApplicationFactory<TObject>;
  begin
    Factory := TDextApplicationFactory<TObject>.Create
      .WithConfigure(
        procedure(App: TWebApplication)
        begin
          App.GetApplicationBuilder.UseApiVersionReader(
            THeaderApiVersionReader.Create('X-Api-Version')
          );
          MapNamed(App, 'GET', '/header-ver', 'v1', '1.0');
          MapNamed(App, 'GET', '/header-ver', 'v2', '2.0');
        end);
    try
      Result := Factory.CreateClient.Header(AHeader, AValue).Get('/header-ver');
    finally
      Factory.Free;
    end;
  end;
begin
  Should(CallHeader('X-Api-Version', '2.0').Body).Be('v2');
  Should(CallHeader('X-Api-Version', '1.0').Body).Be('v1');
  // Default X-Version header should not be recognized
  ShouldBeVersionProblem(CallHeader('X-Version', '2.0'), 'ApiVersionUnspecified');
end;

procedure TApiVersionRoutingTests.CustomCompositeVersionReader;
  function CallComposite(const APath: string; const AHeader: string = '';
    const AValue: string = ''): IDextTestHttpResponse;
  var
    Factory: TDextApplicationFactory<TObject>;
    Client: IDextTestHttpClient;
  begin
    Factory := TDextApplicationFactory<TObject>.Create
      .WithConfigure(
        procedure(App: TWebApplication)
        begin
          App.GetApplicationBuilder.UseApiVersionReader(
            TCompositeApiVersionReader.Create([
              THeaderApiVersionReader.Create('X-Custom-Ver'),
              TQueryStringApiVersionReader.Create('ver')
            ])
          );
          MapNamed(App, 'GET', '/comp', 'v1', '1.0');
          MapNamed(App, 'GET', '/comp', 'v2', '2.0');
        end);
    try
      Client := Factory.CreateClient;
      if AHeader <> '' then
        Client := Client.Header(AHeader, AValue);
      Result := Client.Get(APath);
    finally
      Factory.Free;
    end;
  end;
begin
  // 1. Matched by Header
  Should(CallComposite('/comp', 'X-Custom-Ver', '1.0').Body).Be('v1');
  // 2. Matched by Query string
  Should(CallComposite('/comp?ver=2.0').Body).Be('v2');
  // 3. Header takes priority over Query
  Should(CallComposite('/comp?ver=1.0', 'X-Custom-Ver', '2.0').Body).Be('v2');
end;

end.
