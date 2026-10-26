{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero & Antigravity                                      }
{  Created: 2026-08-10                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Testing.WebApplicationFactory;

interface

{$I Dext.inc}

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.DI.Interfaces,
  Dext.Server.Engine.Interfaces,
  Dext.Web.Interfaces,
  Dext.Web.WebApplication,
  Dext.Web;

type
  /// <summary>Captured HTTP response from an in-process test request.</summary>
  IDextTestHttpResponse = interface
    ['{A7C3E91B-2D4F-4B8A-9E01-6F5D4C3B2A10}']
    function GetStatusCode: Integer;
    function GetContentType: string;
    function GetBody: string;
    function GetHeader(const AName: string): string;
    property StatusCode: Integer read GetStatusCode;
    property ContentType: string read GetContentType;
    property Body: string read GetBody;
  end;

  /// <summary>
  ///   In-process HTTP client that dispatches into the application middleware
  ///   pipeline without opening a TCP port.
  /// </summary>
  IDextTestHttpClient = interface
    ['{B8D4F02C-3E5A-4C9B-A012-7F6E5D4C3B21}']
    function Header(const AName, AValue: string): IDextTestHttpClient;
    function Get(const APath: string): IDextTestHttpResponse;
    function Post(const APath: string; const ABody: string = ''): IDextTestHttpResponse;
    function PostJson(const APath, AJson: string): IDextTestHttpResponse;
    function Put(const APath: string; const ABody: string = ''): IDextTestHttpResponse;
    function PutJson(const APath, AJson: string): IDextTestHttpResponse;
    function Delete(const APath: string): IDextTestHttpResponse;
  end;

  /// <summary>
  ///   Fluent in-memory ApplicationFactory for integration testing (S66 / S68).
  /// </summary>
  TDextApplicationFactory<TApp: class> = class
  private
    FApp: TWebApplication;
    // TWebApplication is reference counted (TInterfacedObject). Without an
    // interface reference, a configure step that gets the application back as
    // IWebApplication (MapControllers returns Self) would free it when that
    // temporary interface is released. This reference keeps it alive and is
    // the one that frees it.
    FAppRef: IWebApplication;
    FConfigureServicesProc: TProc<IServiceCollection>;
    FConfigureAppProc: TProc<TWebApplication>;
    FPipeline: TRequestDelegate;
    FClient: IDextTestHttpClient;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Overrides or injects mocks into the DI container prior to pipeline build.</summary>
    function WithTestServices(AProc: TProc<IServiceCollection>): TDextApplicationFactory<TApp>; overload;
    function WithTestServices(AProc: TProc<TDextServices>): TDextApplicationFactory<TApp>; overload;

    /// <summary>Configures routes/middlewares on the test application before CreateClient.</summary>
    function WithConfigure(AProc: TProc<TWebApplication>): TDextApplicationFactory<TApp>;

    /// <summary>Initializes the in-memory application and returns the WebApplication instance.</summary>
    function CreateApplication: TWebApplication;

    /// <summary>
    ///   Builds the request pipeline (no TCP host) and returns an in-process HTTP client.
    /// </summary>
    function CreateClient: IDextTestHttpClient;
  end;

  /// <summary>
  ///   S66 naming. The fluent methods return this type, so the chain can be
  ///   assigned to a TDextWebApplicationFactory&lt;TApp&gt; variable.
  /// </summary>
  TDextWebApplicationFactory<TApp: class> = class(TDextApplicationFactory<TApp>)
  public
    /// <summary>Injects test services and returns this factory, so the chain keeps the derived type.</summary>
    function WithTestServices(AProc: TProc<IServiceCollection>): TDextWebApplicationFactory<TApp>; reintroduce; overload;
    /// <summary>Injects test services and returns this factory, so the chain keeps the derived type.</summary>
    function WithTestServices(AProc: TProc<TDextServices>): TDextWebApplicationFactory<TApp>; reintroduce; overload;
    /// <summary>Configures the test application and returns this factory, so the chain keeps the derived type.</summary>
    function WithConfigure(AProc: TProc<TWebApplication>): TDextWebApplicationFactory<TApp>; reintroduce;
  end;

/// <summary>
///   Creates an in-process test client. Exposed at unit scope so generic
///   factory methods (E2506) do not reference implementation-only types.
/// </summary>
function CreateDextTestHttpClient(APipeline: TRequestDelegate;
  AServices: IServiceProvider): IDextTestHttpClient;

implementation

uses
  Dext.Json,
  Dext.Entity.FastQuery,
  System.TypInfo
  {$IFDEF DEXT_ENABLE_ENTITY}
  ,Dext.Entity.Core
  {$ENDIF}
  ;

type
  TTestHttpResponse = class(TInterfacedObject, IHttpResponse, IDextTestHttpResponse)
  private
    FStatusCode: Integer;
    FContentType: string;
    FBody: TStringBuilder;
    FHeaders: IStringDictionary;
  public
    constructor Create;
    destructor Destroy; override;

    function GetHtmx: IHtmxResponse;
    function GetHeaders: IStringDictionary;
    function GetContentType: string;
    function GetStatusCode: Integer;
    function GetBody: string;
    function GetHeader(const AName: string): string;
    function Status(AValue: Integer): IHttpResponse; overload;
    function Status(AValue: Integer; const AMessage: string): IHttpResponse; overload;
    procedure AddHeader(const AName, AValue: string);
    procedure AppendCookie(const AName, AValue: string); overload;
    procedure AppendCookie(const AName, AValue: string; const AOptions: TCookieOptions); overload;
    procedure DeleteCookie(const AName: string);
    procedure Json(const AJson: string); overload;
    procedure Json(const AValue: TValue); overload;
    procedure WriteJson(const AValue: TValue); overload;
    procedure WriteJson(ACode: Integer; const AValue: TValue); overload;
    procedure WriteJson(const AQuery: IDextFastQuery); overload;
    procedure WriteJson(ACode: Integer; const AQuery: IDextFastQuery); overload;
    {$IFDEF DEXT_ENABLE_ENTITY}
    procedure WriteJson(const AStream: IDbSetFastStream); overload;
    procedure WriteJson(ACode: Integer; const AStream: IDbSetFastStream); overload;
    {$ENDIF}
    procedure SetContentLength(const AValue: Int64);
    procedure SetContentType(const AValue: string);
    procedure SetStatusCode(AValue: Integer);
    procedure Flush;
    procedure Write(const ABuffer: TBytes); overload;
    procedure Write(const AContent: string); overload;
    procedure Write(const AStream: TStream); overload;
    procedure SendJsonUtf8(const AUtf8Json: RawByteString); overload;
    procedure SendJsonUtf8(const ABuffer: TBytes); overload;
    function GetOutputStream: TStream;
    procedure Redirect(const AUrl: string; APermanent: Boolean = False);
    procedure Unauthorized(const AMessage: string = '');
    procedure Forbidden(const AMessage: string = '');
    procedure BadRequest(const AMessage: string = '');
    procedure NotFound(const AMessage: string = '');
  end;

  TTestHttpRequest = class(TInterfacedObject, IHttpRequest)
  private
    FMethod: string;
    FPath: string;
    FPathBase: string;
    FQuery: IStringDictionary;
    FHeaders: IStringDictionary;
    FCookies: IStringDictionary;
    FBody: TMemoryStream;
    FRouteParams: TRouteValueDictionary;
    FFiles: IFormFileCollection;
  public
    constructor Create(const AMethod, APath, ABody: string; AHeaders: IStringDictionary);
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
  end;

  TTestHttpContext = class(TInterfacedObject, IHttpContext)
  private
    FRequest: IHttpRequest;
    FResponse: IHttpResponse;
    FServices: IServiceProvider;
    FUser: IClaimsPrincipal;
    FItems: IDictionary<string, TValue>;
    FEndpointMetadata: TEndpointMetadata;
  public
    constructor Create(ARequest: IHttpRequest; AResponse: IHttpResponse; AServices: IServiceProvider);
    function GetConnection: IDextServerConnection;
    function GetItems: IDictionary<string, TValue>;
    function GetRequest: IHttpRequest;
    function GetResponse: IHttpResponse;
    function GetServices: IServiceProvider;
    function GetUser: IClaimsPrincipal;
    function GetSession: IStreamableSession;
    function GetEndpointMetadata: TEndpointMetadata;
    procedure SetEndpointMetadata(const AMetadata: TEndpointMetadata);
    procedure SetResponse(const AValue: IHttpResponse);
    procedure SetServices(const AValue: IServiceProvider);
    procedure SetUser(const AValue: IClaimsPrincipal);
    procedure SetRouteParams(const AParams: TRouteValueDictionary);
  end;

  TDextTestHttpClient = class(TInterfacedObject, IDextTestHttpClient)
  private
    FPipeline: TRequestDelegate;
    FServices: IServiceProvider;
    FHeaders: IStringDictionary;
    function Send(const AMethod, APath, ABody: string): IDextTestHttpResponse;
  public
    constructor Create(APipeline: TRequestDelegate; AServices: IServiceProvider);
    function Header(const AName, AValue: string): IDextTestHttpClient;
    function Get(const APath: string): IDextTestHttpResponse;
    function Post(const APath: string; const ABody: string = ''): IDextTestHttpResponse;
    function PostJson(const APath, AJson: string): IDextTestHttpResponse;
    function Put(const APath: string; const ABody: string = ''): IDextTestHttpResponse;
    function PutJson(const APath, AJson: string): IDextTestHttpResponse;
    function Delete(const APath: string): IDextTestHttpResponse;
  end;

{ TTestHttpResponse }

constructor TTestHttpResponse.Create;
begin
  inherited Create;
  FStatusCode := 200;
  FContentType := 'text/plain';
  FBody := TStringBuilder.Create;
  FHeaders := TCollections.CreateStringDictionary(True);
end;

destructor TTestHttpResponse.Destroy;
begin
  FBody.Free;
  FHeaders := nil;
  inherited;
end;

function TTestHttpResponse.GetHtmx: IHtmxResponse;
begin
  Result := nil;
end;

function TTestHttpResponse.GetHeaders: IStringDictionary;
begin
  Result := FHeaders;
end;

function TTestHttpResponse.GetContentType: string;
begin
  Result := FContentType;
end;

function TTestHttpResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function TTestHttpResponse.GetBody: string;
begin
  Result := FBody.ToString;
end;

function TTestHttpResponse.GetHeader(const AName: string): string;
begin
  if not FHeaders.TryGetValue(AName, Result) then
    Result := '';
end;

function TTestHttpResponse.Status(AValue: Integer): IHttpResponse;
begin
  FStatusCode := AValue;
  Result := Self;
end;

function TTestHttpResponse.Status(AValue: Integer; const AMessage: string): IHttpResponse;
begin
  FStatusCode := AValue;
  Result := Self;
end;

procedure TTestHttpResponse.AddHeader(const AName, AValue: string);
begin
  FHeaders.AddOrSetValue(AName, AValue);
end;

procedure TTestHttpResponse.AppendCookie(const AName, AValue: string);
begin
end;

procedure TTestHttpResponse.AppendCookie(const AName, AValue: string; const AOptions: TCookieOptions);
begin
end;

procedure TTestHttpResponse.DeleteCookie(const AName: string);
begin
end;

procedure TTestHttpResponse.Json(const AJson: string);
begin
  FContentType := 'application/json';
  FBody.Clear;
  FBody.Append(AJson);
end;

procedure TTestHttpResponse.Json(const AValue: TValue);
begin
  Json(TDextJson.Serialize(AValue));
end;

procedure TTestHttpResponse.WriteJson(const AValue: TValue);
begin
  Json(AValue);
end;

procedure TTestHttpResponse.WriteJson(ACode: Integer; const AValue: TValue);
begin
  FStatusCode := ACode;
  Json(AValue);
end;

procedure TTestHttpResponse.WriteJson(const AQuery: IDextFastQuery);
begin
  FContentType := 'application/json';
end;

procedure TTestHttpResponse.WriteJson(ACode: Integer; const AQuery: IDextFastQuery);
begin
  FStatusCode := ACode;
  FContentType := 'application/json';
end;

{$IFDEF DEXT_ENABLE_ENTITY}
procedure TTestHttpResponse.WriteJson(const AStream: IDbSetFastStream);
begin
  FContentType := 'application/json';
end;

procedure TTestHttpResponse.WriteJson(ACode: Integer; const AStream: IDbSetFastStream);
begin
  FStatusCode := ACode;
  FContentType := 'application/json';
end;
{$ENDIF}

procedure TTestHttpResponse.SetContentLength(const AValue: Int64);
begin
end;

procedure TTestHttpResponse.SetContentType(const AValue: string);
begin
  FContentType := AValue;
end;

procedure TTestHttpResponse.SetStatusCode(AValue: Integer);
begin
  FStatusCode := AValue;
end;

procedure TTestHttpResponse.Flush;
begin
end;

procedure TTestHttpResponse.Write(const AContent: string);
begin
  FBody.Append(AContent);
end;

procedure TTestHttpResponse.Write(const ABuffer: TBytes);
begin
  FBody.Append(TEncoding.UTF8.GetString(ABuffer));
end;

procedure TTestHttpResponse.Write(const AStream: TStream);
var
  Bytes: TBytes;
begin
  if AStream = nil then
    Exit;
  SetLength(Bytes, AStream.Size - AStream.Position);
  if Length(Bytes) > 0 then
  begin
    AStream.ReadBuffer(Bytes[0], Length(Bytes));
    Write(Bytes);
  end;
end;

procedure TTestHttpResponse.SendJsonUtf8(const AUtf8Json: RawByteString);
begin
  FContentType := 'application/json';
  FBody.Clear;
  FBody.Append(string(UTF8ToString(AUtf8Json)));
end;

procedure TTestHttpResponse.SendJsonUtf8(const ABuffer: TBytes);
begin
  FContentType := 'application/json';
  FBody.Clear;
  FBody.Append(TEncoding.UTF8.GetString(ABuffer));
end;

function TTestHttpResponse.GetOutputStream: TStream;
begin
  Result := nil;
end;

procedure TTestHttpResponse.Redirect(const AUrl: string; APermanent: Boolean);
begin
  if APermanent then
    FStatusCode := 301
  else
    FStatusCode := 302;
  AddHeader('Location', AUrl);
end;

procedure TTestHttpResponse.Unauthorized(const AMessage: string);
begin
  FStatusCode := 401;
  if AMessage <> '' then
    Write(AMessage);
end;

procedure TTestHttpResponse.Forbidden(const AMessage: string);
begin
  FStatusCode := 403;
  if AMessage <> '' then
    Write(AMessage);
end;

procedure TTestHttpResponse.BadRequest(const AMessage: string);
begin
  FStatusCode := 400;
  if AMessage <> '' then
    Write(AMessage);
end;

procedure TTestHttpResponse.NotFound(const AMessage: string);
begin
  FStatusCode := 404;
  if AMessage <> '' then
    Write(AMessage);
end;

{ TTestHttpRequest }

constructor TTestHttpRequest.Create(const AMethod, APath, ABody: string;
  AHeaders: IStringDictionary);
var
  PathOnly: string;
  QueryPart: string;
  QPos: Integer;
  Bytes: TBytes;
  Pair: TPair<string, string>;
  EmptyFiles: IList<IFormFile>;
  Parts: TArray<string>;
  Part: string;
  Eq: Integer;
begin
  inherited Create;
  FMethod := AMethod;
  FPathBase := '';
  FQuery := TCollections.CreateStringDictionary(True);
  FHeaders := TCollections.CreateStringDictionary(True);
  FCookies := TCollections.CreateStringDictionary(True);
  FRouteParams.Clear;
  EmptyFiles := TCollections.CreateList<IFormFile>;
  FFiles := TFormFileCollection.Create(EmptyFiles);

  if AHeaders <> nil then
    for Pair in AHeaders.ToArray do
      FHeaders.AddOrSetValue(Pair.Key, Pair.Value);

  QPos := Pos('?', APath);
  if QPos > 0 then
  begin
    PathOnly := Copy(APath, 1, QPos - 1);
    QueryPart := Copy(APath, QPos + 1, MaxInt);
  end
  else
  begin
    PathOnly := APath;
    QueryPart := '';
  end;
  FPath := PathOnly;

  if QueryPart <> '' then
  begin
    Parts := QueryPart.Split(['&']);
    for Part in Parts do
    begin
      Eq := Pos('=', Part);
      if Eq > 0 then
        FQuery.AddOrSetValue(Copy(Part, 1, Eq - 1), Copy(Part, Eq + 1, MaxInt))
      else if Part <> '' then
        FQuery.AddOrSetValue(Part, '');
    end;
  end;

  FBody := TMemoryStream.Create;
  if ABody <> '' then
  begin
    Bytes := TEncoding.UTF8.GetBytes(ABody);
    FBody.WriteBuffer(Bytes[0], Length(Bytes));
    FBody.Position := 0;
  end;
end;

destructor TTestHttpRequest.Destroy;
begin
  FBody.Free;
  FQuery := nil;
  FHeaders := nil;
  FCookies := nil;
  FFiles := nil;
  inherited;
end;

function TTestHttpRequest.GetMethod: string;
begin
  Result := FMethod;
end;

function TTestHttpRequest.GetPath: string;
begin
  Result := FPath;
end;

procedure TTestHttpRequest.SetPath(const AValue: string);
begin
  FPath := AValue;
end;

function TTestHttpRequest.GetPathBase: string;
begin
  Result := FPathBase;
end;

procedure TTestHttpRequest.SetPathBase(const AValue: string);
begin
  FPathBase := AValue;
end;

function TTestHttpRequest.ToAppUrl(const ARelativePath: string): string;
begin
  Result := FPathBase + ARelativePath;
end;

function TTestHttpRequest.GetQuery: IStringDictionary;
begin
  Result := FQuery;
end;

function TTestHttpRequest.GetBody: TStream;
begin
  Result := FBody;
end;

function TTestHttpRequest.GetRouteParams: TRouteValueDictionary;
begin
  Result := FRouteParams;
end;

function TTestHttpRequest.GetHeaders: IStringDictionary;
begin
  Result := FHeaders;
end;

function TTestHttpRequest.GetRemoteIpAddress: string;
begin
  Result := '127.0.0.1';
end;

function TTestHttpRequest.GetHeader(const AName: string): string;
begin
  if not FHeaders.TryGetValue(AName, Result) then
    Result := '';
end;

function TTestHttpRequest.GetQueryParam(const AName: string): string;
begin
  if not FQuery.TryGetValue(AName, Result) then
    Result := '';
end;

function TTestHttpRequest.GetCookies: IStringDictionary;
begin
  Result := FCookies;
end;

function TTestHttpRequest.GetFiles: IFormFileCollection;
begin
  Result := FFiles;
end;

{ TTestHttpContext }

constructor TTestHttpContext.Create(ARequest: IHttpRequest; AResponse: IHttpResponse;
  AServices: IServiceProvider);
begin
  inherited Create;
  FRequest := ARequest;
  FResponse := AResponse;
  FServices := AServices;
  FItems := TCollections.CreateDictionary<string, TValue>;
end;

function TTestHttpContext.GetConnection: IDextServerConnection;
begin
  Result := nil;
end;

function TTestHttpContext.GetItems: IDictionary<string, TValue>;
begin
  Result := FItems;
end;

function TTestHttpContext.GetRequest: IHttpRequest;
begin
  Result := FRequest;
end;

function TTestHttpContext.GetResponse: IHttpResponse;
begin
  Result := FResponse;
end;

function TTestHttpContext.GetServices: IServiceProvider;
begin
  Result := FServices;
end;

function TTestHttpContext.GetUser: IClaimsPrincipal;
begin
  Result := FUser;
end;

function TTestHttpContext.GetSession: IStreamableSession;
begin
  Result := nil;
end;

function TTestHttpContext.GetEndpointMetadata: TEndpointMetadata;
begin
  Result := FEndpointMetadata;
end;

procedure TTestHttpContext.SetEndpointMetadata(const AMetadata: TEndpointMetadata);
begin
  FEndpointMetadata := AMetadata;
end;

procedure TTestHttpContext.SetResponse(const AValue: IHttpResponse);
begin
  FResponse := AValue;
end;

procedure TTestHttpContext.SetServices(const AValue: IServiceProvider);
begin
  FServices := AValue;
end;

procedure TTestHttpContext.SetUser(const AValue: IClaimsPrincipal);
begin
  FUser := AValue;
end;

procedure TTestHttpContext.SetRouteParams(const AParams: TRouteValueDictionary);
begin
  // Route params live on the request; test double keeps an empty dictionary.
end;

{ TDextTestHttpClient }

function CreateDextTestHttpClient(APipeline: TRequestDelegate;
  AServices: IServiceProvider): IDextTestHttpClient;
begin
  Result := TDextTestHttpClient.Create(APipeline, AServices);
end;

constructor TDextTestHttpClient.Create(APipeline: TRequestDelegate; AServices: IServiceProvider);
begin
  inherited Create;
  FPipeline := APipeline;
  FServices := AServices;
  FHeaders := TCollections.CreateStringDictionary(True);
end;

function TDextTestHttpClient.Header(const AName, AValue: string): IDextTestHttpClient;
begin
  FHeaders.AddOrSetValue(AName, AValue);
  Result := Self;
end;

function TDextTestHttpClient.Send(const AMethod, APath, ABody: string): IDextTestHttpResponse;
var
  Request: IHttpRequest;
  ResponseObj: TTestHttpResponse;
  Response: IHttpResponse;
  Context: IHttpContext;
begin
  ResponseObj := TTestHttpResponse.Create;
  Response := ResponseObj;
  Request := TTestHttpRequest.Create(AMethod, APath, ABody, FHeaders);
  Context := TTestHttpContext.Create(Request, Response, FServices);
  if Assigned(FPipeline) then
    FPipeline(Context);
  Result := ResponseObj;
end;

function TDextTestHttpClient.Get(const APath: string): IDextTestHttpResponse;
begin
  Result := Send('GET', APath, '');
end;

function TDextTestHttpClient.Post(const APath, ABody: string): IDextTestHttpResponse;
begin
  Result := Send('POST', APath, ABody);
end;

function TDextTestHttpClient.PostJson(const APath, AJson: string): IDextTestHttpResponse;
begin
  Header('Content-Type', 'application/json');
  Result := Send('POST', APath, AJson);
end;

function TDextTestHttpClient.Put(const APath, ABody: string): IDextTestHttpResponse;
begin
  Result := Send('PUT', APath, ABody);
end;

function TDextTestHttpClient.PutJson(const APath, AJson: string): IDextTestHttpResponse;
begin
  Header('Content-Type', 'application/json');
  Result := Send('PUT', APath, AJson);
end;

function TDextTestHttpClient.Delete(const APath: string): IDextTestHttpResponse;
begin
  Result := Send('DELETE', APath, '');
end;

{ TDextApplicationFactory<TApp> }

constructor TDextApplicationFactory<TApp>.Create;
begin
  inherited Create;
  FApp := nil;
  FConfigureServicesProc := nil;
  FConfigureAppProc := nil;
  FPipeline := nil;
  FClient := nil;
end;

destructor TDextApplicationFactory<TApp>.Destroy;
begin
  FClient := nil;
  FPipeline := nil;
  if FApp <> nil then
  begin
    FApp.Stop;
    FApp := nil;
    FAppRef := nil; // Frees the application
  end;
  inherited Destroy;
end;

function TDextApplicationFactory<TApp>.WithTestServices(
  AProc: TProc<IServiceCollection>): TDextApplicationFactory<TApp>;
begin
  FConfigureServicesProc := AProc;
  Result := Self;
end;

function TDextApplicationFactory<TApp>.WithTestServices(
  AProc: TProc<TDextServices>): TDextApplicationFactory<TApp>;
begin
  FConfigureServicesProc := procedure(AServices: IServiceCollection)
    begin
      if Assigned(AProc) then
        AProc(TDextServices.Create(AServices));
    end;
  Result := Self;
end;

function TDextApplicationFactory<TApp>.WithConfigure(
  AProc: TProc<TWebApplication>): TDextApplicationFactory<TApp>;
begin
  FConfigureAppProc := AProc;
  Result := Self;
end;

{ TDextWebApplicationFactory<TApp> }

function TDextWebApplicationFactory<TApp>.WithTestServices(
  AProc: TProc<IServiceCollection>): TDextWebApplicationFactory<TApp>;
begin
  inherited WithTestServices(AProc);
  Result := Self;
end;

function TDextWebApplicationFactory<TApp>.WithTestServices(
  AProc: TProc<TDextServices>): TDextWebApplicationFactory<TApp>;
begin
  inherited WithTestServices(AProc);
  Result := Self;
end;

function TDextWebApplicationFactory<TApp>.WithConfigure(
  AProc: TProc<TWebApplication>): TDextWebApplicationFactory<TApp>;
begin
  inherited WithConfigure(AProc);
  Result := Self;
end;

function TDextApplicationFactory<TApp>.CreateApplication: TWebApplication;
begin
  if FApp = nil then
  begin
    FApp := TWebApplication.Create;
    FAppRef := FApp;
    if Assigned(FConfigureServicesProc) then
      FConfigureServicesProc(FApp.GetServices.Collection);
    if Assigned(FConfigureAppProc) then
      FConfigureAppProc(FApp);
  end;
  Result := FApp;
end;

function TDextApplicationFactory<TApp>.CreateClient: IDextTestHttpClient;
begin
  if FClient = nil then
  begin
    CreateApplication;
    // Explicit () required: BuildRequestPipeline returns TRequestDelegate;
    // without (), Delphi treats it as a method pointer.
    FPipeline := FApp.BuildRequestPipeline();
    FClient := CreateDextTestHttpClient(FPipeline, FApp.BuildServices);
  end;
  Result := FClient;
end;

end.
