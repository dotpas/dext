unit Dext.Server.Native.Request.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Collections,
  Dext.Collections.RawDict,
  Dext.Collections.Dict,
  Dext.DI.Interfaces,
  Dext.Server.Engine.Interfaces,
  Dext.Server.Native,
  Dext.Web.Interfaces,
  Dext.Web.Routing;

type
  /// <summary>
  ///   The per-request objects of the native server, built on fake raw
  ///   request/response/connection (no HTTP.sys binding needed). They guard the
  ///   allocations removed from the request path: the request scope and Items
  ///   created on first use, the response headers mirrored without a
  ///   dictionary until someone reads them, method and path read once, the
  ///   API version read only when some route is versioned, and the
  ///   case-insensitive string hash computed without an upper-case copy.
  /// </summary>
  [TestFixture('Native server - the per-request objects')]
  TNativeRequestTests = class
  public
    [Test('The request scope: same scoped instance within a request, another per request')]
    procedure Scope_SameWithinARequest_OtherPerRequest;
    [Test('The request scope frees its scoped services with the context')]
    procedure Scope_FreedWithTheContext;
    [Test('An explicit SetServices wins over the lazy scope')]
    procedure Scope_SetServicesWins;
    [Test('Items keeps its values and is the same dictionary each time')]
    procedure Items_KeepsValues;
    [Test('Response headers: every one reaches the raw response, the mirror has them all')]
    procedure ResponseHeaders_MirrorAndRaw;
    [Test('Response headers: a header set again replaces the value, case-insensitively')]
    procedure ResponseHeaders_ReplaceIgnoringCase;
    [Test('Request: method and path as the raw request says, SetPath wins, files collection')]
    procedure Request_MethodPathFiles;
    [Test('The case-insensitive hash equals hashing the upper-case copy')]
    procedure Hash_EqualsTheUpperCaseCopy;
    [Test('Routing without versioned routes ignores the requested version')]
    procedure Routing_NoVersionedRoutes_VersionIgnored;
    [Test('Routing with versioned routes picks the version from query or header')]
    procedure Routing_VersionedRoutes_PicksTheVersion;
  end;

implementation

type
  TFakeConnection = class(TInterfacedObject, IDextServerConnection)
  public
    function GetConnectionId: UInt64;
    function GetRemoteAddress: string;
    function GetRemotePort: Word;
    function GetLocalPort: Word;
    function IsSecure: Boolean;
    procedure Close;
    function SupportsUpgrade: Boolean;
    function UpgradeToWebSocket: IDextWebSocketConnection;
  end;

  TFakeRawRequest = class(TInterfacedObject, IDextRawRequest)
  private
    FMethod, FPath, FQuery: string;
    FHeaders: TStringList; // Name=Value
  public
    MethodReads, PathReads: Integer;
    constructor Create(const AMethod, APath, AQuery: string);
    destructor Destroy; override;
    procedure AddHeader(const AName, AValue: string);
    function GetMethod: string;
    function GetPath: string;
    function GetQueryString: string;
    function GetHeader(const AName: string): string;
    procedure PopulateHeaders(ADict: TDictionary<string, string>);
    function GetContentLength: Int64;
    function GetBodyStream: TStream;
  end;

  TFakeRawResponse = class(TInterfacedObject, IDextRawResponse)
  public
    Sent: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure SetStatus(ACode: Integer; const AReason: string = '');
    procedure SetHeader(const AName, AValue: string);
    procedure SendHeaders;
    procedure Write(const ABuffer: TBytes; AOffset, ACount: Integer);
    procedure WriteFile(const APath: string; AOffset, ACount: Int64);
    procedure Flush;
    procedure Close;
  end;

  TScopedThing = class
  public
    class var Created, Destroyed: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

{ TFakeConnection }

function TFakeConnection.GetConnectionId: UInt64; begin Result := 1; end;
function TFakeConnection.GetRemoteAddress: string; begin Result := '127.0.0.1'; end;
function TFakeConnection.GetRemotePort: Word; begin Result := 50000; end;
function TFakeConnection.GetLocalPort: Word; begin Result := 80; end;
function TFakeConnection.IsSecure: Boolean; begin Result := False; end;
procedure TFakeConnection.Close; begin end;
function TFakeConnection.SupportsUpgrade: Boolean; begin Result := False; end;
function TFakeConnection.UpgradeToWebSocket: IDextWebSocketConnection; begin Result := nil; end;

{ TFakeRawRequest }

constructor TFakeRawRequest.Create(const AMethod, APath, AQuery: string);
begin
  inherited Create;
  FMethod := AMethod;
  FPath := APath;
  FQuery := AQuery;
  FHeaders := TStringList.Create;
end;

destructor TFakeRawRequest.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TFakeRawRequest.AddHeader(const AName, AValue: string);
begin
  FHeaders.Values[AName] := AValue;
end;

function TFakeRawRequest.GetMethod: string;
begin
  Inc(MethodReads);
  Result := FMethod;
end;

function TFakeRawRequest.GetPath: string;
begin
  Inc(PathReads);
  Result := FPath;
end;

function TFakeRawRequest.GetQueryString: string; begin Result := FQuery; end;

function TFakeRawRequest.GetHeader(const AName: string): string;
begin
  // TStringList.Values ignores the case of the name, like HTTP headers
  Result := FHeaders.Values[AName];
end;

procedure TFakeRawRequest.PopulateHeaders(ADict: TDictionary<string, string>);
var
  I: Integer;
begin
  for I := 0 to FHeaders.Count - 1 do
    ADict.AddOrSetValue(FHeaders.Names[I], FHeaders.ValueFromIndex[I]);
end;

function TFakeRawRequest.GetContentLength: Int64; begin Result := 0; end;
function TFakeRawRequest.GetBodyStream: TStream; begin Result := nil; end;

{ TFakeRawResponse }

constructor TFakeRawResponse.Create;
begin
  inherited Create;
  Sent := TStringList.Create;
end;

destructor TFakeRawResponse.Destroy;
begin
  Sent.Free;
  inherited;
end;

procedure TFakeRawResponse.SetStatus(ACode: Integer; const AReason: string); begin end;

procedure TFakeRawResponse.SetHeader(const AName, AValue: string);
begin
  Sent.Add(AName + '=' + AValue);
end;

procedure TFakeRawResponse.SendHeaders; begin end;
procedure TFakeRawResponse.Write(const ABuffer: TBytes; AOffset, ACount: Integer); begin end;
procedure TFakeRawResponse.WriteFile(const APath: string; AOffset, ACount: Int64); begin end;
procedure TFakeRawResponse.Flush; begin end;
procedure TFakeRawResponse.Close; begin end;

{ TScopedThing }

constructor TScopedThing.Create;
begin
  inherited Create;
  Inc(Created);
end;

destructor TScopedThing.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function NewProvider: IServiceProvider;
var
  Services: TDextServices;
begin
  Services := TDextServices.New;
  Services.AddScoped<TScopedThing>;
  Result := Services.Collection.BuildServiceProvider;
end;

function NewContext(const AServices: IServiceProvider;
  const ARaw: IDextRawRequest = nil;
  const ARawResponse: IDextRawResponse = nil): IHttpContext;
var
  Raw: IDextRawRequest;
  RawResponse: IDextRawResponse;
begin
  Raw := ARaw;
  if Raw = nil then
    Raw := TFakeRawRequest.Create('GET', '/x', '');
  RawResponse := ARawResponse;
  if RawResponse = nil then
    RawResponse := TFakeRawResponse.Create;
  Result := TDextNativeHttpContext.Create(TFakeConnection.Create, Raw,
    RawResponse, AServices);
end;

function Thing(const AContext: IHttpContext): TObject;
begin
  Result := AContext.Services.GetService(TServiceType.FromClass(TScopedThing));
end;

{ TNativeRequestTests }

procedure TNativeRequestTests.Scope_SameWithinARequest_OtherPerRequest;
var
  Provider: IServiceProvider;
  A, B: IHttpContext;
  A1, A2, B1: TObject;
begin
  Provider := NewProvider;
  A := NewContext(Provider);
  B := NewContext(Provider);
  A1 := Thing(A);
  A2 := Thing(A);
  B1 := Thing(B);
  Should(A1 <> nil).BeTrue;
  Should(A1 = A2).BeTrue.Because('one scope per request');
  Should(A1 <> B1).BeTrue.Because('each request has its own scope');
  Should(A.Services = A.Services).BeTrue.Because('the scope is created once');
end;

procedure TNativeRequestTests.Scope_FreedWithTheContext;
var
  Provider: IServiceProvider;
  Ctx: IHttpContext;
  Before: Integer;
begin
  Provider := NewProvider;
  Before := TScopedThing.Destroyed;
  Ctx := NewContext(Provider);
  Thing(Ctx);
  Ctx := nil;
  Should(TScopedThing.Destroyed - Before).Be(1);
end;

procedure TNativeRequestTests.Scope_SetServicesWins;
var
  Provider, Other: IServiceProvider;
  Ctx: IHttpContext;
begin
  Provider := NewProvider;
  Other := NewProvider;
  Ctx := NewContext(Provider);
  Ctx.Services := Other;
  Should(Ctx.Services = Other).BeTrue;
end;

procedure TNativeRequestTests.Items_KeepsValues;
var
  Ctx: IHttpContext;
  V: TValue;
begin
  Ctx := NewContext(nil);
  Ctx.Items.AddOrSetValue('a', TValue.From<Integer>(7));
  Should(Ctx.Items.TryGetValue('a', V)).BeTrue;
  Should(V.AsInteger).Be(7);
  Should(Ctx.Items = Ctx.Items).BeTrue;
end;

procedure TNativeRequestTests.ResponseHeaders_MirrorAndRaw;
var
  Raw: TFakeRawResponse;
  RawIntf: IDextRawResponse;
  Ctx: IHttpContext;
  I: Integer;
begin
  Raw := TFakeRawResponse.Create;
  RawIntf := Raw;
  Ctx := NewContext(nil, nil, RawIntf);
  Ctx.Response.SetContentType('application/json');
  Should(Ctx.Response.ContentType).Be('application/json');
  for I := 1 to 6 do
    Ctx.Response.AddHeader('X-H' + I.ToString, 'v' + I.ToString);
  Should(Raw.Sent.Count).Be(7).Because('every header reaches the raw response');
  Should(Ctx.Response.Headers.Count).Be(7);
  Should(Ctx.Response.Headers.GetValue('x-h6')).Be('v6');
  Should(Ctx.Response.ContentType).Be('application/json');
  // after the dictionary exists, new headers go there too
  Ctx.Response.AddHeader('X-Late', 'yes');
  Should(Ctx.Response.Headers.GetValue('X-Late')).Be('yes');
end;

procedure TNativeRequestTests.ResponseHeaders_ReplaceIgnoringCase;
var
  Ctx: IHttpContext;
begin
  Ctx := NewContext(nil);
  Ctx.Response.SetContentType('text/plain');
  Ctx.Response.AddHeader('content-type', 'text/html');
  Should(Ctx.Response.ContentType).Be('text/html');
  Should(Ctx.Response.Headers.Count).Be(1);
end;

procedure TNativeRequestTests.Request_MethodPathFiles;
var
  Raw: TFakeRawRequest;
  RawIntf: IDextRawRequest;
  Ctx: IHttpContext;
begin
  Raw := TFakeRawRequest.Create('POST', '', 'a=1');
  RawIntf := Raw;
  Ctx := NewContext(nil, RawIntf);
  Should(Ctx.Request.Method).Be('POST');
  Should(Ctx.Request.Method).Be('POST');
  Should(Ctx.Request.Path).Be('/').Because('an empty raw path is the root');
  Should(Ctx.Request.Path).Be('/');
  Should(Raw.MethodReads).Be(1).Because('the method is read once');
  Should(Raw.PathReads).Be(1).Because('the path is read once');
  Ctx.Request.SetPath('/other');
  Should(Ctx.Request.Path).Be('/other');
  Should(Ctx.Request.Files <> nil).BeTrue;
  Should(Ctx.Request.Files = Ctx.Request.Files).BeTrue;
end;

procedure TNativeRequestTests.Hash_EqualsTheUpperCaseCopy;
const
  Samples: array [0 .. 7] of string = ('', 'a', 'Content-Type', 'X-VERSION',
    'mixed Case 123 !?', #$00E0#$00E8#$00EC#$00F2#$00F9,
    #$00DF' and '#$00C4#$00D6#$00DC, '{}[]_^~`');
var
  S, Upper: string;
  Expected: Cardinal;
  I: Integer;
begin
  for S in Samples do
  begin
    // the previous implementation: UpperCase, then FNV-1a over the chars
    Upper := UpperCase(S);
    if Upper = '' then
      Expected := 0
    else
    begin
      {$Q-}
      Expected := 2166136261;
      for I := 1 to Length(Upper) do
        Expected := (Expected xor Ord(Upper[I])) * 16777619;
      {$Q+}
    end;
    Should(StringRawHashIgnoreCase(@S, SizeOf(string))).Be(Expected)
      .Because('"' + S + '"');
  end;
end;

var
  GCalled: string; // which route handler ran

function RouteTo(const APath: string; const AVersions: TArray<string>;
  const AName: string): TRouteDefinition;
var
  Meta: TEndpointMetadata;
begin
  Result := TRouteDefinition.Create('GET', APath,
    procedure(AContext: IHttpContext)
    begin
      GCalled := AName;
    end);
  Meta := Result.Metadata;
  Meta.ApiVersions := AVersions;
  Result.Metadata := Meta;
end;

function Match(const AMatcher: IRouteMatcher; const AContext: IHttpContext;
  out AHandler: TRequestDelegate): Boolean;
var
  Params: TRouteValueDictionary;
  Meta: TEndpointMetadata;
begin
  Result := AMatcher.FindMatchingRoute(AContext, AHandler, Params, Meta);
end;

procedure TNativeRequestTests.Routing_NoVersionedRoutes_VersionIgnored;
var
  Routes: IList<TRouteDefinition>;
  Matcher: IRouteMatcher;
  Raw: TFakeRawRequest;
  Handler: TRequestDelegate;
  Ctx: IHttpContext;
begin
  Routes := TCollections.CreateList<TRouteDefinition>(True);
  Routes.Add(RouteTo('/x', nil, 'plain'));
  Matcher := TRouteMatcher.Create(Routes);
  Raw := TFakeRawRequest.Create('GET', '/x', 'api-version=9.0');
  Raw.AddHeader('X-Version', '7.0');
  Ctx := NewContext(nil, Raw);
  Should(Match(Matcher, Ctx, Handler)).BeTrue;
  Handler(Ctx);
  Should(GCalled).Be('plain');
end;

procedure TNativeRequestTests.Routing_VersionedRoutes_PicksTheVersion;
var
  Routes: IList<TRouteDefinition>;
  Matcher: IRouteMatcher;
  Raw: TFakeRawRequest;
  Handler: TRequestDelegate;
  Ctx: IHttpContext;
begin
  Routes := TCollections.CreateList<TRouteDefinition>(True);
  Routes.Add(RouteTo('/v', ['1.0'], 'one'));
  Routes.Add(RouteTo('/v', ['2.0'], 'two'));
  Matcher := TRouteMatcher.Create(Routes);

  Ctx := NewContext(nil, TFakeRawRequest.Create('GET', '/v', 'api-version=2.0'));
  Should(Match(Matcher, Ctx, Handler)).BeTrue;
  Handler(Ctx);
  Should(GCalled).Be('two').Because('the query string version');

  Raw := TFakeRawRequest.Create('GET', '/v', '');
  Raw.AddHeader('X-Version', '1.0');
  Ctx := NewContext(nil, Raw);
  Should(Match(Matcher, Ctx, Handler)).BeTrue;
  Handler(Ctx);
  Should(GCalled).Be('one').Because('the X-Version header');
  // A version that no route serves (3.0) still finds a route, here and on
  // main alike: not touched by this change.
end;

end.
