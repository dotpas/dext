{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
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
{  Author:  Cesar Romero                                                    }
{  Created: 2026-06-17                                                      }
{                                                                           }
{  Dext native adapters for web host, contexts, request, and responses.     }
{                                                                           }
{***************************************************************************}
unit Dext.Server.Native;

{$I Dext.inc}

interface

uses
  System.Classes,
  System.SysUtils,
  System.Rtti,
  System.SyncObjs,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Web.Interfaces,
  {$IFDEF DEXT_ENABLE_ENTITY}
  Dext.Entity.Core,
  {$ENDIF}
  Dext.Entity.FastQuery,
  Dext.DI.Interfaces,
  Dext.Auth.Identity,
  Dext.Web.Results,
  Dext.Json,
  Dext.Server.Engine.Types,
  Dext.Server.Engine.Interfaces;

type
  /// <summary>
  ///   Native form file implementation.
  /// </summary>
  TDextNativeFormFile = class(TInterfacedObject, IFormFile)
  private
    FName: string;
    FFileName: string;
    FContentType: string;
    FStream: TStream;
  public
    /// <summary>Initializes a new instance of the native form file adapter.</summary>
    constructor Create(const AName, AFileName, AContentType: string; AStream: TStream);
    /// <summary>Destroys the instance and frees the underlying stream.</summary>
    destructor Destroy; override;
    /// <summary>Returns the form field name.</summary>
    function GetName: string;
    /// <summary>Returns the filename sent by the client.</summary>
    function GetFileName: string;
    /// <summary>Returns the Content-Type of the uploaded file.</summary>
    function GetContentType: string;
    /// <summary>Returns the length of the file in bytes.</summary>
    function GetLength: Int64;
    /// <summary>Returns the file content stream.</summary>
    function GetStream: TStream;
  end;

  /// <summary>
  ///   Dext native implementation of IHttpRequest.
  /// </summary>
  TDextNativeHttpRequest = class(TInterfacedObject, IHttpRequest)
  private
    FRawRequest: IDextRawRequest;
    FQuery: IStringDictionary;
    FBodyStream: TStream;
    FRouteParams: TRouteValueDictionary;
    FHeaders: IStringDictionary;
    FCookies: IStringDictionary;
    FFiles: IFormFileCollection;
    FRemoteIp: string;
    FPath: string;
    FPathBase: string;
    FHasCustomPath: Boolean;
    // Method and raw path, read once: the raw request builds a new string on
    // every call, and routing, the matcher and telemetry each ask.
    FMethod: string;
    FRawPath: string;
    FRawPathRead: Boolean;
    function ParseQueryString(const AQuery: string): IStringDictionary;
    function ParseHeaders: IStringDictionary;
  public
    /// <summary>Initializes a new instance of the native HTTP request adapter.</summary>
    constructor Create(const ARawRequest: IDextRawRequest; const ARemoteIp: string);
    /// <summary>Destroys the instance and frees internal cached dictionary structures.</summary>
    destructor Destroy; override;

    /// <summary>Gets the HTTP request verb/method.</summary>
    function GetMethod: string;
    /// <summary>Gets the request URL path.</summary>
    function GetPath: string;
    /// <summary>Sets a custom request URL path.</summary>
    procedure SetPath(const AValue: string);
    /// <summary>Gets the base path prefix.</summary>
    function GetPathBase: string;
    /// <summary>Sets the base path prefix.</summary>
    procedure SetPathBase(const AValue: string);
    /// <summary>Builds an absolute application URL using PathBase.</summary>
    function ToAppUrl(const ARelativePath: string): string;
    /// <summary>Gets the collection of parsed query parameters.</summary>
    function GetQuery: IStringDictionary;
    /// <summary>Gets the body data stream.</summary>
    function GetBody: TStream;
    /// <summary>Gets the route parameters collection.</summary>
    function GetRouteParams: TRouteValueDictionary;
    /// <summary>Gets the request headers collection.</summary>
    function GetHeaders: IStringDictionary;
    /// <summary>Gets the remote client IP address.</summary>
    function GetRemoteIpAddress: string;
    /// <summary>Gets a specific header value by case-insensitive name.</summary>
    function GetHeader(const AName: string): string;
    /// <summary>Gets a specific query parameter value by name.</summary>
    function GetQueryParam(const AName: string): string;
    /// <summary>Gets the parsed cookies collection.</summary>
    function GetCookies: IStringDictionary;
    /// <summary>Gets the parsed multi-part uploaded files collection.</summary>
    function GetFiles: IFormFileCollection;

    property Method: string read GetMethod;
    property Path: string read GetPath;
    property PathBase: string read GetPathBase write SetPathBase;
    property Query: IStringDictionary read GetQuery;
    property Body: TStream read GetBody;
    property RouteParams: TRouteValueDictionary read GetRouteParams;
    property Headers: IStringDictionary read GetHeaders;
    property Cookies: IStringDictionary read GetCookies;
    property Files: IFormFileCollection read GetFiles;
    property RemoteIpAddress: string read GetRemoteIpAddress;
  end;

  TDextNativeHttpResponse = class;

  /// <summary>
  ///   Write-only stream handed out by GetOutputStream. Every write is
  ///   forwarded straight to the response sink, so a caller that prefers a
  ///   TStream gets the same zero-copy path as SendJsonUtf8, with no
  ///   intermediate buffer.
  /// </summary>
  /// <remarks>
  ///   Deliberately neither readable nor seekable: the bytes are already on
  ///   their way out, so a Position that could be moved would be lying. Seek
  ///   answers the current write count for the no-op forms the RTL relies on
  ///   (offset 0 from soCurrent or soEnd) and refuses the rest.
  /// </remarks>
  TDextResponseSinkStream = class(TStream)
  private
    FOwner: TDextNativeHttpResponse;
    FWritten: Int64;
  public
    constructor Create(AOwner: TDextNativeHttpResponse);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  /// <summary>
  ///   Dext native implementation of IHttpResponse.
  /// </summary>
  TDextNativeHttpResponse = class(TInterfacedObject, IHttpResponse,
    IUtf8ResponseSink)
  private
    FRawResponse: IDextRawResponse;
    FHtmx: IHtmxResponse;
    // The headers set so far, mirrored for whoever reads Response.Headers.
    // The first few stay in a fixed array (no allocation: a typical response
    // sets only Content-Type); the dictionary is built from them on demand.
    FHeaders: IStringDictionary;
    FPendingNames: array [0 .. 3] of string;
    FPendingValues: array [0 .. 3] of string;
    FPendingCount: Integer;
    FStreamBuffer: TBytes;
    FStatusCode: Integer;
    FOutputStream: TDextResponseSinkStream;
  public
    /// <summary>Initializes a new instance of the native HTTP response adapter.</summary>
    constructor Create(const ARawResponse: IDextRawResponse);
    /// <summary>Destroys the instance.</summary>
    destructor Destroy; override;

    /// <summary>Gets the HTTP status code.</summary>
    function GetStatusCode: Integer;
    /// <summary>Gets the response Content-Type header value.</summary>
    function GetContentType: string;
    /// <summary>Sets the HTTP status code fluently.</summary>
    function Status(AValue: Integer): IHttpResponse; overload;
    function Status(AValue: Integer; const AMessage: string): IHttpResponse; overload;
    /// <summary>Sets the HTTP status code.</summary>
    procedure SetStatusCode(AValue: Integer);
    /// <summary>Sets the response Content-Type header.</summary>
    procedure SetContentType(const AValue: string);
    /// <summary>Sets the response Content-Length header.</summary>
    procedure SetContentLength(const AValue: Int64);
    /// <summary>Flushes buffered response data to the underlying transport.</summary>
    procedure Flush;
    /// <summary>Writes a UTF-8 string to the response body.</summary>
    procedure Write(const AContent: string); overload;
    procedure Write(const ABuffer: TBytes); overload;
    procedure Write(const AStream: TStream); overload;
    procedure SendJsonUtf8(const AUtf8Json: RawByteString); overload;
    procedure SendJsonUtf8(const ABuffer: TBytes); overload;
    function GetOutputStream: TStream;
    /// <summary>Writes UTF-8 bytes directly to a native response sink.</summary>
    procedure WriteUtf8(AData: Pointer; ALength: Integer);
    /// <summary>Sends a JSON string directly as response.</summary>
    procedure Json(const AJson: string); overload;
    /// <summary>Serializes a TValue to JSON and sends it.</summary>
    procedure Json(const AValue: TValue); overload;
    procedure WriteJson(const AValue: TValue); overload;
    procedure WriteJson(ACode: Integer; const AValue: TValue); overload;
    procedure WriteJson(const AQuery: IDextFastQuery); overload;
    procedure WriteJson(ACode: Integer; const AQuery: IDextFastQuery); overload;
    {$IFDEF DEXT_ENABLE_ENTITY}
    procedure WriteJson(const AStream: IDbSetFastStream); overload;
    procedure WriteJson(ACode: Integer; const AStream: IDbSetFastStream); overload;
    {$ENDIF}
    /// <summary>Adds a header value to the response.</summary>
    procedure AddHeader(const AName, AValue: string);
    /// <summary>Appends a cookie with options to the response.</summary>
    procedure AppendCookie(const AName, AValue: string; const AOptions: TCookieOptions); overload;
    /// <summary>Appends a cookie with default options to the response.</summary>
    procedure AppendCookie(const AName, AValue: string); overload;
    /// <summary>Sets a cookie to expire immediately to delete it.</summary>
    procedure DeleteCookie(const AName: string);
    /// <summary>Sends a redirect status code (301/302) with Location header.</summary>
    procedure Redirect(const AUrl: string; APermanent: Boolean = False);
    /// <summary>Sets 401 Unauthorized status and optional message.</summary>
    procedure Unauthorized(const AMessage: string = '');
    /// <summary>Sets 403 Forbidden status and optional message.</summary>
    procedure Forbidden(const AMessage: string = '');
    /// <summary>Sets 400 Bad Request status and optional message.</summary>
    procedure BadRequest(const AMessage: string = '');
    /// <summary>Sets 404 Not Found status and optional message.</summary>
    procedure NotFound(const AMessage: string = '');
    /// <summary>Returns the fluent HTMX helper interface.</summary>
    function GetHtmx: IHtmxResponse;
    /// <summary>Returns the response headers collection.</summary>
    function GetHeaders: IStringDictionary;

    property StatusCode: Integer read GetStatusCode write SetStatusCode;
    property ContentType: string read GetContentType write SetContentType;
    property Htmx: IHtmxResponse read GetHtmx;
    property Headers: IStringDictionary read GetHeaders;
  end;

  /// <summary>
  ///   Dext native implementation of IHttpContext.
  /// </summary>
  TDextNativeHttpContext = class(TInterfacedObject, IHttpContext)
  private
    FConnection: IDextServerConnection;
    FRequest: IHttpRequest;
    FResponse: IHttpResponse;
    FScope: IServiceScope;
    FServices: IServiceProvider;
    // The root provider: the request scope is created from it on first use.
    FRootServices: IServiceProvider;
    FUser: IClaimsPrincipal;
    FItems: IDictionary<string, TValue>;
    FEndpointMetadata: TEndpointMetadata;
  public
    /// <summary>Initializes a new request context with the native connection/request/response.</summary>
    constructor Create(
      const AConnection: IDextServerConnection;
      const ARawRequest: IDextRawRequest;
      const ARawResponse: IDextRawResponse;
      const AServices: IServiceProvider
    );
    /// <summary>Destroys the context and releases the request scope.</summary>
    destructor Destroy; override;

    /// <summary>Sets the route parameters dictionary for the request.</summary>
    procedure SetRouteParams(const AParams: TRouteValueDictionary);
    /// <summary>Returns the HTTP connection interface.</summary>
    function GetConnection: IDextServerConnection;
    /// <summary>Returns the HTTP request interface.</summary>
    function GetRequest: IHttpRequest;
    /// <summary>Returns the HTTP response interface.</summary>
    function GetResponse: IHttpResponse;
    /// <summary>Sets the HTTP response interface.</summary>
    procedure SetResponse(const AValue: IHttpResponse);
    /// <summary>Returns the request scoped service provider.</summary>
    function GetServices: IServiceProvider;
    /// <summary>Sets the request scoped service provider.</summary>
    procedure SetServices(const AValue: IServiceProvider);
    /// <summary>Returns the authenticated user principal.</summary>
    function GetUser: IClaimsPrincipal;
    /// <summary>Sets the authenticated user principal.</summary>
    procedure SetUser(const AValue: IClaimsPrincipal);
    /// <summary>Returns the items/state dictionary for the current request.</summary>
    function GetItems: IDictionary<string, TValue>;
    /// <summary>Returns the active session interface, if configured.</summary>
    function GetSession: IStreamableSession;
    function GetEndpointMetadata: TEndpointMetadata;
    procedure SetEndpointMetadata(const AMetadata: TEndpointMetadata);

    property Request: IHttpRequest read GetRequest;
    property Response: IHttpResponse read GetResponse write SetResponse;
    property Services: IServiceProvider read GetServices write SetServices;
    property User: IClaimsPrincipal read GetUser write SetUser;
    property Items: IDictionary<string, TValue> read GetItems;
    property EndpointMetadata: TEndpointMetadata
      read GetEndpointMetadata write SetEndpointMetadata;
  end;

  /// <summary>
  ///   IWebHost implementation that wraps the native platform server engines.
  /// </summary>
  TDextNativeWebServer = class(TInterfacedObject, IWebHost)
  private
    FPort: Integer;
    FEngine: IDextServerEngine;
    FPipeline: TRequestDelegate;
    FServices: IServiceProvider;
    FOptions: TServerEngineOptions;
    FRunning: Boolean;
  public
    /// <summary>Initializes a new native web server instance.</summary>
    constructor Create(
      APort: Integer;
      const APipeline: TRequestDelegate;
      const AServices: IServiceProvider;
      const AOptions: TServerEngineOptions
    );
    /// <summary>Destroys the server instance and stops the engine.</summary>
    destructor Destroy; override;

    /// <summary>Gets the port number the server is listening on.</summary>
    function GetPort: Integer;
    /// <summary>Starts the server and blocks the main thread (for CLI/Service usage).</summary>
    procedure Run;
    /// <summary>Starts the server in background threads (non-blocking, for VCL/GUI/Sidecar).</summary>
    procedure Start;
    /// <summary>Stops the server gracefully.</summary>
    procedure Stop;

    property Port: Integer read GetPort;
  end;

  /// <summary>Helper method to perform URL decoding on paths and query strings.</summary>
  function UrlDecode(const AStr: string): string;

implementation

uses
  Dext.Logging.Global,
  Dext.Utils;

function UrlDecode(const AStr: string): string;
var
  I, J, Len: Integer;
  Ch: Char;
  Code: Integer;
begin
  Len := Length(AStr);
  if Len = 0 then Exit('');

  // 1. Quick check to avoid any allocation if no decoding is needed
  J := 0;
  for I := 1 to Len do
    if (AStr[I] = '%') or (AStr[I] = '+') then
    begin
      J := 1;
      Break;
    end;
  if J = 0 then Exit(AStr);

  // 2. Pre-allocate the maximum potential buffer size
  SetLength(Result, Len);
  I := 1;
  J := 1;
  while I <= Len do
  begin
    Ch := AStr[I];
    if Ch = '%' then
    begin
      if (I + 2 <= Len) and TryStrToInt('$' + Copy(AStr, I + 1, 2), Code) then
      begin
        Result[J] := Char(Code);
        Inc(I, 2);
      end
      else
        Result[J] := Ch;
    end
    else if Ch = '+' then
      Result[J] := ' '
    else
      Result[J] := Ch;
    Inc(I);
    Inc(J);
  end;
  // 3. Shrink string to actual decoded length
  SetLength(Result, J - 1);
end;

{ TDextNativeFormFile }

constructor TDextNativeFormFile.Create(const AName, AFileName, AContentType: string; AStream: TStream);
begin
  inherited Create;
  FName := AName;
  FFileName := AFileName;
  FContentType := AContentType;
  FStream := AStream;
end;

destructor TDextNativeFormFile.Destroy;
begin
  FStream.Free;
  inherited;
end;

function TDextNativeFormFile.GetContentType: string; begin Result := FContentType; end;
function TDextNativeFormFile.GetFileName: string; begin Result := FFileName; end;
function TDextNativeFormFile.GetLength: Int64; begin Result := FStream.Size; end;
function TDextNativeFormFile.GetName: string; begin Result := FName; end;
function TDextNativeFormFile.GetStream: TStream; begin Result := FStream; end;

{ TDextNativeHttpRequest }

constructor TDextNativeHttpRequest.Create(const ARawRequest: IDextRawRequest; const ARemoteIp: string);
begin
  inherited Create;
  FRawRequest := ARawRequest;
  FRemoteIp := ARemoteIp;
  FRouteParams.Clear;
  // FFiles: created on first use (GetFiles); most requests carry no files.
end;

destructor TDextNativeHttpRequest.Destroy;
begin
  FQuery := nil;
  FBodyStream := nil;
  FHeaders := nil;
  FCookies := nil;
  FFiles := nil;
  FRawRequest := nil;
  inherited;
end;

function TDextNativeHttpRequest.GetMethod: string;
begin
  if FMethod = '' then
    FMethod := FRawRequest.Method;
  Result := FMethod;
end;

function TDextNativeHttpRequest.GetPath: string;
begin
  if FHasCustomPath then
    Exit(FPath);
  if not FRawPathRead then
  begin
    FRawPath := FRawRequest.Path;
    if FRawPath = '' then
      FRawPath := '/';
    FRawPathRead := True;
  end;
  Result := FRawPath;
end;

procedure TDextNativeHttpRequest.SetPath(const AValue: string);
begin
  FPath := AValue;
  FHasCustomPath := True;
end;

function TDextNativeHttpRequest.GetPathBase: string;
begin
  Result := FPathBase;
end;

procedure TDextNativeHttpRequest.SetPathBase(const AValue: string);
begin
  FPathBase := AValue;
end;

function TDextNativeHttpRequest.ToAppUrl(const ARelativePath: string): string;
var
  BasePath, RelPath: string;
begin
  BasePath := GetPathBase;
  RelPath := ARelativePath;
  if BasePath = '/' then BasePath := '';
  if (RelPath <> '') and not RelPath.StartsWith('/') then RelPath := '/' + RelPath;
  Result := BasePath + RelPath;
  if Result = '' then Result := '/';
end;

function TDextNativeHttpRequest.GetBody: TStream;
begin
  if FBodyStream = nil then
    FBodyStream := FRawRequest.BodyStream;
  Result := FBodyStream;
end;

function TDextNativeHttpRequest.GetHeader(const AName: string): string;
begin
  Result := FRawRequest.GetHeader(AName);
end;

function TDextNativeHttpRequest.GetHeaders: IStringDictionary;
begin
  if FHeaders = nil then
    FHeaders := ParseHeaders;
  Result := FHeaders;
end;

function TDextNativeHttpRequest.ParseHeaders: IStringDictionary;
var
  Dict: TDictionary<string, string>;
  Pair: TPair<string, string>;
begin
  Result := TCollections.CreateStringDictionary(True);
  Dict := TDictionary<string, string>.Create;
  try
    FRawRequest.PopulateHeaders(Dict);
    for Pair in Dict do
      Result.SetItem(Pair.Key, Pair.Value);
  finally
    Dict.Free;
  end;
end;

function TDextNativeHttpRequest.GetRemoteIpAddress: string;
begin
  Result := FRemoteIp;
end;

function TDextNativeHttpRequest.GetRouteParams: TRouteValueDictionary;
begin
  Result := FRouteParams;
end;

function TDextNativeHttpRequest.GetQuery: IStringDictionary;
begin
  if FQuery = nil then
    FQuery := ParseQueryString(FRawRequest.QueryString);
  Result := FQuery;
end;

function TDextNativeHttpRequest.GetQueryParam(const AName: string): string;
begin
  if not GetQuery.TryGetValue(AName, Result) then
    Result := '';
end;

function TDextNativeHttpRequest.ParseQueryString(const AQuery: string): IStringDictionary;
var
  P, EndP: PChar;
  Key, Value: string;
  Len: Integer;
  EqP, AmpP: PChar;
  CleanQuery: string;
begin
  Result := TCollections.CreateStringDictionary(True);
  CleanQuery := AQuery;
  if CleanQuery.StartsWith('?') then
    CleanQuery := CleanQuery.Substring(1);
    
  if CleanQuery = '' then Exit;
  
  P := PChar(CleanQuery);
  Len := Length(CleanQuery);
  EndP := P + Len;

  while P < EndP do
  begin
    EqP := StrScan(P, '=');
    AmpP := StrScan(P, '&');

    if (AmpP = nil) or (AmpP > EndP) then
      AmpP := EndP;

    if (EqP <> nil) and (EqP < AmpP) then
    begin
      SetString(Key, P, EqP - P);
      SetString(Value, EqP + 1, AmpP - (EqP + 1));
      Result.SetItem(UrlDecode(Key), UrlDecode(Value));
    end
    else
    begin
      SetString(Key, P, AmpP - P);
      if Key <> '' then
        Result.SetItem(UrlDecode(Key), '');
    end;

    P := AmpP + 1;
  end;
end;

function TDextNativeHttpRequest.GetCookies: IStringDictionary;
var
  CookieHeader: string;
  Len: Integer;
  PosIdx: Integer;
  StartIdx: Integer;
  EndIdx: Integer;
  EqIdx: Integer;
  KeyStart: Integer;
  KeyEnd: Integer;
  ValStart: Integer;
  ValEnd: Integer;
  Key: string;
  Value: string;
begin
  if FCookies = nil then
  begin
    FCookies := TCollections.CreateStringDictionary(True);
    CookieHeader := GetHeader('Cookie');
    Len := Length(CookieHeader);
    PosIdx := 1;

    while PosIdx <= Len do
    begin
      while (PosIdx <= Len) and ((CookieHeader[PosIdx] = ';') or
        (CookieHeader[PosIdx] = ' ') or (CookieHeader[PosIdx] = #9)) do
        Inc(PosIdx);
      if PosIdx > Len then
        Break;

      StartIdx := PosIdx;
      while (PosIdx <= Len) and (CookieHeader[PosIdx] <> ';') do
        Inc(PosIdx);
      EndIdx := PosIdx - 1;

      EqIdx := StartIdx;
      while (EqIdx <= EndIdx) and (CookieHeader[EqIdx] <> '=') do
        Inc(EqIdx);

      KeyStart := StartIdx;
      KeyEnd := EqIdx - 1;
      while (KeyStart <= KeyEnd) and ((CookieHeader[KeyStart] = ' ') or
        (CookieHeader[KeyStart] = #9)) do
        Inc(KeyStart);
      while (KeyEnd >= KeyStart) and ((CookieHeader[KeyEnd] = ' ') or
        (CookieHeader[KeyEnd] = #9)) do
        Dec(KeyEnd);

      if KeyStart <= KeyEnd then
      begin
        Key := Copy(CookieHeader, KeyStart, KeyEnd - KeyStart + 1);
        if EqIdx <= EndIdx then
        begin
          ValStart := EqIdx + 1;
          ValEnd := EndIdx;
          while (ValStart <= ValEnd) and ((CookieHeader[ValStart] = ' ') or
            (CookieHeader[ValStart] = #9)) do
            Inc(ValStart);
          while (ValEnd >= ValStart) and ((CookieHeader[ValEnd] = ' ') or
            (CookieHeader[ValEnd] = #9)) do
            Dec(ValEnd);
          if ValStart <= ValEnd then
          begin
            Value := Copy(CookieHeader, ValStart, ValEnd - ValStart + 1);
            FCookies.SetItem(Key, UrlDecode(Value));
          end
          else
            FCookies.SetItem(Key, '');
        end
        else
          FCookies.SetItem(Key, '');
      end;

      Inc(PosIdx);
    end;
  end;
  Result := FCookies;
end;

function TDextNativeHttpRequest.GetFiles: IFormFileCollection;
begin
  if FFiles = nil then
    FFiles := TFormFileCollection.Create(TCollections.CreateList<IFormFile>);
  Result := FFiles;
end;

{ TDextNativeHttpResponse }

constructor TDextNativeHttpResponse.Create(const ARawResponse: IDextRawResponse);
begin
  inherited Create;
  FRawResponse := ARawResponse;
  FStatusCode := 200;
end;

destructor TDextNativeHttpResponse.Destroy;
begin
  FOutputStream.Free;
  FHeaders := nil;
  FHtmx := nil;
  FStreamBuffer := nil;
  FRawResponse := nil;
  inherited;
end;

procedure TDextNativeHttpResponse.AddHeader(const AName, AValue: string);
var
  I: Integer;
begin
  FRawResponse.SetHeader(AName, AValue);
  if FHeaders = nil then
  begin
    // Same rule as the dictionary (AddOrSetValue, case-insensitive keys).
    for I := 0 to FPendingCount - 1 do
      if SameText(FPendingNames[I], AName) then
      begin
        FPendingValues[I] := AValue;
        Exit;
      end;
    if FPendingCount <= High(FPendingNames) then
    begin
      FPendingNames[FPendingCount] := AName;
      FPendingValues[FPendingCount] := AValue;
      Inc(FPendingCount);
      Exit;
    end;
  end;
  GetHeaders.AddOrSetValue(AName, AValue);
end;

procedure TDextNativeHttpResponse.AppendCookie(const AName, AValue: string; const AOptions: TCookieOptions);
var
  CookieStr: string;
begin
  CookieStr := Format('%s=%s', [AName, AValue]);
  if AOptions.Path <> '' then
    CookieStr := CookieStr + '; Path=' + AOptions.Path;
  if AOptions.Domain <> '' then
    CookieStr := CookieStr + '; Domain=' + AOptions.Domain;
  if AOptions.Expires <> 0 then
    CookieStr := CookieStr + '; Expires=' + FormatDateTime('ddd, dd mmm yyyy hh:nn:ss "GMT"', AOptions.Expires, TFormatSettings.Invariant);
  if AOptions.HttpOnly then
    CookieStr := CookieStr + '; HttpOnly';
  if AOptions.Secure then
    CookieStr := CookieStr + '; Secure';
  if AOptions.SameSite <> '' then
    CookieStr := CookieStr + '; SameSite=' + AOptions.SameSite;

  AddHeader('Set-Cookie', CookieStr);
end;

procedure TDextNativeHttpResponse.AppendCookie(const AName, AValue: string);
begin
  AppendCookie(AName, AValue, TCookieOptions.Default);
end;

procedure TDextNativeHttpResponse.DeleteCookie(const AName: string);
var
  Opts: TCookieOptions;
begin
  Opts := TCookieOptions.Default;
  Opts.Expires := Now - 1;
  AppendCookie(AName, '', Opts);
end;

procedure TDextNativeHttpResponse.Json(const AJson: string);
begin
  SetContentType('application/json; charset=utf-8');
  Write(AJson);
end;

procedure TDextNativeHttpResponse.Json(const AValue: TValue);
begin
  Json(TDextJson.Serialize(AValue));
end;

procedure TDextNativeHttpResponse.Redirect(const AUrl: string; APermanent: Boolean);
begin
  if APermanent then
    SetStatusCode(301)
  else
    SetStatusCode(302);
  AddHeader('Location', AUrl);
end;

procedure TDextNativeHttpResponse.SetContentLength(const AValue: Int64);
begin
  AddHeader('Content-Length', AValue.ToString);
end;

procedure TDextNativeHttpResponse.SetContentType(const AValue: string);
begin
  AddHeader('Content-Type', AValue);
end;

procedure TDextNativeHttpResponse.SetStatusCode(AValue: Integer);
begin
  FStatusCode := AValue;
  FRawResponse.SetStatus(AValue);
end;

function TDextNativeHttpResponse.Status(AValue: Integer): IHttpResponse;
begin
  SetStatusCode(AValue);
  Result := Self;
end;

function TDextNativeHttpResponse.Status(AValue: Integer; const AMessage: string): IHttpResponse;
begin
  SetStatusCode(AValue);
  Result := Self;
end;

procedure TDextNativeHttpResponse.WriteJson(const AValue: TValue);
var
  {$IFDEF DEXT_ENABLE_ENTITY}
  FastStream: IDbSetFastStream;
  {$ENDIF}
  FastQuery: IDextFastQuery;
  Stream: TStream;
begin
  SetContentType('application/json; charset=utf-8');
  if AValue.IsEmpty then Exit;

  if AValue.Kind = tkInterface then
  begin
    {$IFDEF DEXT_ENABLE_ENTITY}
    if Supports(AValue.AsInterface, IDbSetFastStream, FastStream) then
    begin
      Stream := GetOutputStream;
      FastStream.ExecuteToUtf8Stream(Stream);
      Exit;
    end;
    {$ENDIF}

    if Supports(AValue.AsInterface, IDextFastQuery, FastQuery) then
    begin
      Stream := GetOutputStream;
      FastQuery.ExecuteToUtf8Proc(
        procedure(Data: Pointer; Len: Integer)
        begin
          Stream.WriteBuffer(Data^, Len);
        end
      );
      Exit;
    end;
  end;

  Json(AValue);
end;

procedure TDextNativeHttpResponse.WriteJson(ACode: Integer; const AValue: TValue);
begin
  SetStatusCode(ACode);
  WriteJson(AValue);
end;

procedure TDextNativeHttpResponse.WriteJson(const AQuery: IDextFastQuery);
var
  Stream: TStream;
begin
  SetContentType('application/json; charset=utf-8');
  if AQuery = nil then Exit;
  Stream := GetOutputStream;
  AQuery.ExecuteToUtf8Proc(
    procedure(Data: Pointer; Len: Integer)
    begin
      Stream.WriteBuffer(Data^, Len);
    end
  );
end;

procedure TDextNativeHttpResponse.WriteJson(ACode: Integer; const AQuery: IDextFastQuery);
begin
  SetStatusCode(ACode);
  WriteJson(AQuery);
end;

{$IFDEF DEXT_ENABLE_ENTITY}
procedure TDextNativeHttpResponse.WriteJson(const AStream: IDbSetFastStream);
var
  Stream: TStream;
begin
  SetContentType('application/json; charset=utf-8');
  if AStream = nil then Exit;
  Stream := GetOutputStream;
  AStream.ExecuteToUtf8Stream(Stream);
end;

procedure TDextNativeHttpResponse.WriteJson(ACode: Integer; const AStream: IDbSetFastStream);
begin
  SetStatusCode(ACode);
  WriteJson(AStream);
end;
{$ENDIF}

procedure TDextNativeHttpResponse.Unauthorized(const AMessage: string);
begin
  SetStatusCode(401);
  if AMessage <> '' then Write(AMessage);
end;

procedure TDextNativeHttpResponse.Forbidden(const AMessage: string);
begin
  SetStatusCode(403);
  if AMessage <> '' then Write(AMessage);
end;

procedure TDextNativeHttpResponse.BadRequest(const AMessage: string);
begin
  SetStatusCode(400);
  if AMessage <> '' then Write(AMessage);
end;

procedure TDextNativeHttpResponse.NotFound(const AMessage: string);
begin
  SetStatusCode(404);
  if AMessage <> '' then Write(AMessage);
end;

procedure TDextNativeHttpResponse.Flush;
begin
  FRawResponse.Flush;
end;

procedure TDextNativeHttpResponse.Write(const AContent: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AContent);
  FRawResponse.Write(Bytes, 0, Length(Bytes));
end;

procedure TDextNativeHttpResponse.Write(const ABuffer: TBytes);
begin
  FRawResponse.Write(ABuffer, 0, Length(ABuffer));
end;

procedure TDextNativeHttpResponse.WriteUtf8(AData: Pointer; ALength: Integer);
var
  Sink: IDextRawResponseSink;
  Buffer: TBytes;
begin
  if ALength <= 0 then
    Exit;
  if Supports(FRawResponse, IDextRawResponseSink, Sink) then
  begin
    Sink.WriteBytes(AData, ALength);
    Exit;
  end;
  SetLength(Buffer, ALength);
  Move(AData^, Buffer[0], ALength);
  FRawResponse.Write(Buffer, 0, ALength);
end;

procedure TDextNativeHttpResponse.Write(const AStream: TStream);
var
  ReadBytes: Integer;
  FileStream: TFileStream;
begin
  if AStream is TFileStream then
  begin
    FileStream := TFileStream(AStream);
    FRawResponse.WriteFile(FileStream.FileName, 0, FileStream.Size);
    Exit;
  end;

  if Length(FStreamBuffer) < 32768 then
    SetLength(FStreamBuffer, 32768);
  AStream.Position := 0;
  while True do
  begin
    ReadBytes := AStream.Read(FStreamBuffer[0], Length(FStreamBuffer));
    if ReadBytes <= 0 then Break;
    FRawResponse.Write(FStreamBuffer, 0, ReadBytes);
  end;
end;

procedure TDextNativeHttpResponse.SendJsonUtf8(const AUtf8Json: RawByteString);
begin
  SetContentType('application/json; charset=utf-8');
  if Length(AUtf8Json) > 0 then
    WriteUtf8(@AUtf8Json[1], Length(AUtf8Json));
end;

procedure TDextNativeHttpResponse.SendJsonUtf8(const ABuffer: TBytes);
begin
  SetContentType('application/json; charset=utf-8');
  if Length(ABuffer) > 0 then
    WriteUtf8(@ABuffer[0], Length(ABuffer));
end;

function TDextNativeHttpResponse.GetOutputStream: TStream;
begin
  SetContentType('application/json; charset=utf-8');
  // Lazily created and owned by the response: handing out a fresh stream per
  // call would make interleaved writes from two callers unpredictable, and
  // leaves the caller wondering who frees it.
  if FOutputStream = nil then
    FOutputStream := TDextResponseSinkStream.Create(Self);
  Result := FOutputStream;
end;

{ TDextResponseSinkStream }

constructor TDextResponseSinkStream.Create(AOwner: TDextNativeHttpResponse);
begin
  inherited Create;
  FOwner := AOwner;
end;

function TDextResponseSinkStream.Read(var Buffer; Count: Longint): Longint;
begin
  // A response body cannot be read back: it has already gone out.
  Result := 0;
end;

function TDextResponseSinkStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
  if Count <= 0 then
    Exit;
  FOwner.WriteUtf8(@Buffer, Count);
  Inc(FWritten, Count);
  Result := Count;
end;

function TDextResponseSinkStream.Seek(const Offset: Int64;
  Origin: TSeekOrigin): Int64;
begin
  // Only the no-op forms the RTL uses to ask "where am I" are answered; an
  // actual seek is refused rather than silently ignored, because pretending to
  // rewind a socket would corrupt the response in a way nothing would report.
  if (Offset = 0) and (Origin in [soCurrent, soEnd]) then
    Exit(FWritten);
  raise EStreamError.Create('The HTTP response output stream cannot seek: ' +
    'the bytes have already been sent.');
end;

function TDextNativeHttpResponse.GetContentType: string;
var
  I: Integer;
begin
  if FHeaders = nil then
  begin
    for I := 0 to FPendingCount - 1 do
      if SameText(FPendingNames[I], 'Content-Type') then
        Exit(FPendingValues[I]);
    Exit('');
  end;
  Result := FHeaders.GetValue('Content-Type');
end;

function TDextNativeHttpResponse.GetHeaders: IStringDictionary;
var
  I: Integer;
begin
  if FHeaders = nil then
  begin
    FHeaders := TCollections.CreateStringDictionary(True);
    for I := 0 to FPendingCount - 1 do
      FHeaders.AddOrSetValue(FPendingNames[I], FPendingValues[I]);
    FPendingCount := 0;
  end;
  Result := FHeaders;
end;

function TDextNativeHttpResponse.GetHtmx: IHtmxResponse;
begin
  if FHtmx = nil then
    FHtmx := THtmxResponse.Create(Self);
  Result := FHtmx;
end;

function TDextNativeHttpResponse.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

{ TDextNativeHttpContext }

constructor TDextNativeHttpContext.Create(
  const AConnection: IDextServerConnection;
  const ARawRequest: IDextRawRequest;
  const ARawResponse: IDextRawResponse;
  const AServices: IServiceProvider
);
begin
  inherited Create;
  FConnection := AConnection;
  // The request scope and the Items dictionary are created on first use
  // (GetServices, GetItems): a route that touches neither -- a plain ping, a
  // query that writes its JSON -- no longer pays a service scope with two
  // dictionaries and a TValue dictionary on every request.
  FRootServices := AServices;
  FServices := nil;
  FScope := nil;
  FItems := nil;
  FRequest := TDextNativeHttpRequest.Create(ARawRequest, AConnection.RemoteAddress);
  FResponse := TDextNativeHttpResponse.Create(ARawResponse);
end;

destructor TDextNativeHttpContext.Destroy;
begin
  FRequest := nil;
  FResponse := nil;
  FItems := nil;
  FServices := nil;
  FScope := nil;
  FRootServices := nil;
  FConnection := nil;
  inherited;
end;

function TDextNativeHttpContext.GetConnection: IDextServerConnection; begin Result := FConnection; end;
function TDextNativeHttpContext.GetItems: IDictionary<string, TValue>;
begin
  if FItems = nil then
    FItems := TCollections.CreateDictionary<string, TValue>;
  Result := FItems;
end;

function TDextNativeHttpContext.GetRequest: IHttpRequest; begin Result := FRequest; end;
function TDextNativeHttpContext.GetResponse: IHttpResponse; begin Result := FResponse; end;
procedure TDextNativeHttpContext.SetResponse(const AValue: IHttpResponse); begin FResponse := AValue; end;
function TDextNativeHttpContext.GetServices: IServiceProvider;
begin
  // Create scope per request, on first use
  if (FServices = nil) and (FRootServices <> nil) then
  begin
    FScope := FRootServices.CreateScope;
    FServices := FScope.ServiceProvider;
  end;
  Result := FServices;
end;

procedure TDextNativeHttpContext.SetServices(const AValue: IServiceProvider);
begin
  // An explicit provider wins: no lazy scope after this.
  FRootServices := nil;
  FServices := AValue;
end;

function TDextNativeHttpContext.GetUser: IClaimsPrincipal; begin Result := FUser; end;
procedure TDextNativeHttpContext.SetUser(const AValue: IClaimsPrincipal); begin FUser := AValue; end;
function TDextNativeHttpContext.GetSession: IStreamableSession; begin Result := nil; end;

function TDextNativeHttpContext.GetEndpointMetadata: TEndpointMetadata;
begin
  Result := FEndpointMetadata;
end;

procedure TDextNativeHttpContext.SetEndpointMetadata(
  const AMetadata: TEndpointMetadata
);
begin
  FEndpointMetadata := AMetadata;
end;

procedure TDextNativeHttpContext.SetRouteParams(const AParams: TRouteValueDictionary);
begin
  TDextNativeHttpRequest(FRequest).FRouteParams := AParams;
end;

{ TDextNativeWebServer }

constructor TDextNativeWebServer.Create(
  APort: Integer;
  const APipeline: TRequestDelegate;
  const AServices: IServiceProvider;
  const AOptions: TServerEngineOptions
);
begin
  inherited Create;
  FPort := APort;
  FPipeline := APipeline;
  FServices := AServices;
  FOptions := AOptions;
  FRunning := False;
  
  // Decide best engine based on platform/options
  {$IFDEF MSWINDOWS}
  FEngine := CreateNativeEngine(AOptions);
  {$ELSE}
  FEngine := CreateSocketEngine(AOptions);
  {$ENDIF}
end;

destructor TDextNativeWebServer.Destroy;
begin
  Stop;
  if FEngine <> nil then
    FEngine.SetOnRequest(nil);
  FEngine := nil;
  FPipeline := nil;
  inherited;
end;

function TDextNativeWebServer.GetPort: Integer;
begin
  Result := FPort;
end;

procedure TDextNativeWebServer.Run;
begin
  Start;
  
  if FindCmdLineSwitch('no-wait', ['-', '/'], True) then Exit;
  
  SafeWriteLn('Press Ctrl+C to stop the server...');
  while FRunning do
    Sleep(100);
end;

procedure TDextNativeWebServer.Start;
begin
  if FRunning then Exit;

  FEngine.Bind(FOptions.BindAddress, FPort);
  FEngine.SetOnRequest(
    procedure(const AConnection: IDextServerConnection; const ARequest: IDextRawRequest; const AResponse: IDextRawResponse)
    var
      Ctx: IHttpContext;
    begin
      try
        Ctx := TDextNativeHttpContext.Create(AConnection, ARequest, AResponse, FServices);
        FPipeline(Ctx);
      except
        on E: Exception do
        begin
          AResponse.SetStatus(500);
          AResponse.SetHeader('Content-Type', 'text/plain; charset=utf-8');
          AResponse.Write(TEncoding.UTF8.GetBytes('Internal Server Error: ' + E.Message), 0, Length(E.Message) + 23);
        end;
      end;
    end
  );

  FEngine.Start;
  FPort := FEngine.ListenPort;
  FRunning := True;

  var Scheme: string := 'http';
  if FOptions.UseHttps then
    Scheme := 'https';

  SafeWriteLn(Format('Dext high-performance native server running on %s://localhost:%d', [Scheme, FPort]));
end;

procedure TDextNativeWebServer.Stop;
begin
  try
    if not FRunning then Exit;
    FRunning := False;
    if FEngine <> nil then
    begin
      FEngine.Stop;
      FEngine.SetOnRequest(nil);
    end;
  except
    on E: Exception do
      SafeWriteLn(E.ClassName + ': ' + E.Message);
  end;
end;

end.
