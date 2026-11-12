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
{  Author:  Cesar Romero & Dext Contributors                                }
{  Created: 2026-07-07                                                      }
{                                                                           }
{  Description:                                                             }
{    gRPC client and data provider bridge for TEntityDataSet.               }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.GrpcProvider;

{$I Dext.inc}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Web.Interfaces,
  Dext.Web.Grpc.Server,
  Dext.Grpc.Codec,
  Dext.Serialization.Protobuf,
  Dext.Grpc.Attributes,
  Dext.DI.Interfaces,
  Dext.Server.Engine.Interfaces,
  Dext.Auth.Identity,
  {$IFDEF DEXT_ENABLE_ENTITY}
  Dext.Entity.Core,
  {$ENDIF}
  Dext.Entity.FastQuery;

type
  IEntityDataProvider<T: class, constructor> = interface
    ['{789A5F12-3D2F-4A9B-8E7C-901D2E3F4A5B}']
    function FetchAll(const AQuery: string): TList<T>;
    procedure ApplyChanges(const AList: TList<T>);
  end;

  /// <summary>
  ///   gRPC Client to invoke remote gRPC methods.
  ///   Supports both real transport (stubbed) and direct in-process dispatching.
  /// </summary>
  TGrpcClient = class
  private
    FHost: string;
    FPort: Integer;
    FDispatcher: TDextGrpcDispatcher;
  public
    constructor Create(const AHost: string; APort: Integer); overload;
    constructor Create(ADispatcher: TDextGrpcDispatcher); overload;

    procedure CallMethod(const AServiceName, AMethodName: string;
      ARequest, AResponse: TObject);
  end;

  TGenericQueryRequest = class
  private
    FQuery: string;
  public
    [ProtoMember(1)]
    property Query: string read FQuery write FQuery;
  end;

  /// <summary>
  ///   The reply of a list call: the items are the repeated field 1, the
  ///   same shape a service reply with a list in field 1 has.
  /// </summary>
  TGenericListResponse<TItem: class, constructor> = class
  private
    FItems: IList<TItem>;
  public
    constructor Create;
    destructor Destroy; override;
    [ProtoMember(1)]
    property Items: IList<TItem> read FItems write FItems;
  end;

  /// <summary>
  ///   TEntityDataSet provider that syncs entities over gRPC.
  /// </summary>
  TEntitygRpcProvider<T: class, constructor> = class(
    TInterfacedObject, IEntityDataProvider<T>)
  private
    FClient: TGrpcClient;
    FServiceName: string;
  public
    constructor Create(AClient: TGrpcClient; const AServiceName: string);
    function FetchAll(const AQuery: string): TList<T>;
    procedure ApplyChanges(const AList: TList<T>);
  end;

implementation

uses
  System.Net.HttpClient, System.Net.URLClient, System.Diagnostics,
  System.JSON, Dext.Logging, Dext.Logging.Global, Dext.Logging.Telemetry,
  Dext.Logging.Tracing;

type
  TMockHttpRequest = class(TInterfacedObject, Dext.Web.Interfaces.IHttpRequest)
  private
    FPath: string;
    FBody: TStream;
    FHeaders: IStringDictionary;
    FPathBase: string;
  public
    constructor Create(const APath: string; ABody: TBytes);
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

  TMockHttpResponse = class(TInterfacedObject, Dext.Web.Interfaces.IHttpResponse)
  private
    FStatusCode: Integer;
    FContentType: string;
    FBody: TMemoryStream;
    FHeaders: IStringDictionary;
  public
    constructor Create;
    destructor Destroy; override;
    function GetStatusCode: Integer;
    function GetContentType: string;
    function Status(AValue: Integer): Dext.Web.Interfaces.IHttpResponse; overload;
    function Status(AValue: Integer; const AMessage: string): Dext.Web.Interfaces.IHttpResponse; overload;
    procedure SetStatusCode(AValue: Integer);
    procedure SetContentType(const AValue: string);
    procedure SetContentLength(const AValue: Int64);
    procedure Flush;
    procedure Write(const AContent: string); overload;
    procedure Write(const ABuffer: TBytes); overload;
    procedure Write(const AStream: TStream); overload;
    procedure SendJsonUtf8(const AUtf8Json: RawByteString); overload;
    procedure SendJsonUtf8(const ABuffer: TBytes); overload;
    function GetOutputStream: TStream;
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
    procedure AddHeader(const AName, AValue: string);
    procedure AppendCookie(const AName, AValue: string;
      const AOptions: TCookieOptions); overload;
    procedure AppendCookie(const AName, AValue: string); overload;
    procedure DeleteCookie(const AName: string);
    procedure Redirect(const AUrl: string; APermanent: Boolean = False);
    procedure Unauthorized(const AMessage: string = '');
    procedure Forbidden(const AMessage: string = '');
    procedure BadRequest(const AMessage: string = '');
    procedure NotFound(const AMessage: string = '');
    function GetHtmx: IHtmxResponse;
    function GetHeaders: IStringDictionary;
    property Body: TMemoryStream read FBody;
    property Headers: IStringDictionary read FHeaders;
  end;

  TMockHttpContext = class(TInterfacedObject, Dext.Web.Interfaces.IHttpContext)
  private
    FRequest: Dext.Web.Interfaces.IHttpRequest;
    FResponse: Dext.Web.Interfaces.IHttpResponse;
    FItems: IDictionary<string, TValue>;
  public
    constructor Create(AReq: Dext.Web.Interfaces.IHttpRequest;
      ARes: Dext.Web.Interfaces.IHttpResponse);
    destructor Destroy; override;
    function GetConnection: IDextServerConnection;
    function GetRequest: Dext.Web.Interfaces.IHttpRequest;
    function GetResponse: Dext.Web.Interfaces.IHttpResponse;
    procedure SetResponse(const AValue: Dext.Web.Interfaces.IHttpResponse);
    function GetServices: IServiceProvider;
    procedure SetServices(const AValue: IServiceProvider);
    function GetUser: IClaimsPrincipal;
    procedure SetUser(const AValue: IClaimsPrincipal);
    function GetItems: IDictionary<string, TValue>;
    function GetSession: IStreamableSession;
    function GetEndpointMetadata: TEndpointMetadata;
    procedure SetEndpointMetadata(const AMetadata: TEndpointMetadata);
    procedure SetRouteParams(const AParams: TRouteValueDictionary);
  end;

{ TMockHttpRequest }

constructor TMockHttpRequest.Create(const APath: string; ABody: TBytes);
begin
  FPath := APath;
  FBody := TBytesStream.Create(ABody);
  FHeaders := TCollections.CreateStringDictionary(True);
  FHeaders.Add('content-type', 'application/grpc');
end;

destructor TMockHttpRequest.Destroy;
begin
  FBody.Free;
  inherited;
end;

function TMockHttpRequest.GetMethod: string; begin Result := 'POST'; end;
function TMockHttpRequest.GetPath: string; begin Result := FPath; end;
procedure TMockHttpRequest.SetPath(const AValue: string); begin FPath := AValue; end;
function TMockHttpRequest.GetPathBase: string; begin Result := FPathBase; end;
procedure TMockHttpRequest.SetPathBase(const AValue: string); begin FPathBase := AValue; end;
function TMockHttpRequest.ToAppUrl(const ARelativePath: string): string;
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
function TMockHttpRequest.GetQuery: IStringDictionary; begin Result := nil; end;
function TMockHttpRequest.GetBody: TStream; begin Result := FBody; end;
function TMockHttpRequest.GetRouteParams: TRouteValueDictionary;
var
  Dict: TRouteValueDictionary;
begin
  Dict.Clear;
  Result := Dict;
end;
function TMockHttpRequest.GetHeaders: IStringDictionary; begin Result := FHeaders; end;
function TMockHttpRequest.GetRemoteIpAddress: string; begin Result := '127.0.0.1'; end;
function TMockHttpRequest.GetHeader(const AName: string): string;
begin
  if not FHeaders.TryGetValue(AName, Result) then Result := '';
end;
function TMockHttpRequest.GetQueryParam(const AName: string): string; begin Result := ''; end;
function TMockHttpRequest.GetCookies: IStringDictionary; begin Result := nil; end;
function TMockHttpRequest.GetFiles: IFormFileCollection; begin Result := nil; end;

{ TMockHttpResponse }

constructor TMockHttpResponse.Create;
begin
  FBody := TMemoryStream.Create;
  FHeaders := TCollections.CreateStringDictionary(True);
end;

destructor TMockHttpResponse.Destroy;
begin
  FBody.Free;
  inherited;
end;

function TMockHttpResponse.GetStatusCode: Integer; begin Result := FStatusCode; end;
function TMockHttpResponse.GetContentType: string; begin Result := FContentType; end;
function TMockHttpResponse.Status(AValue: Integer): Dext.Web.Interfaces.IHttpResponse;
begin
  FStatusCode := AValue;
  Result := Self;
end;
function TMockHttpResponse.Status(AValue: Integer; const AMessage: string): Dext.Web.Interfaces.IHttpResponse;
begin
  FStatusCode := AValue;
  Result := Self;
end;
procedure TMockHttpResponse.SetStatusCode(AValue: Integer); begin FStatusCode := AValue; end;
procedure TMockHttpResponse.SetContentType(const AValue: string); begin FContentType := AValue; end;
procedure TMockHttpResponse.SetContentLength(const AValue: Int64); begin end;
procedure TMockHttpResponse.Flush; begin end;
procedure TMockHttpResponse.Write(const AContent: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AContent);
  if Length(Bytes) > 0 then
    FBody.Write(Bytes[0], Length(Bytes));
end;
procedure TMockHttpResponse.Write(const ABuffer: TBytes);
begin
  if Length(ABuffer) > 0 then
    FBody.Write(ABuffer[0], Length(ABuffer));
end;
procedure TMockHttpResponse.Write(const AStream: TStream);
begin
  FBody.CopyFrom(AStream, AStream.Size - AStream.Position);
end;
procedure TMockHttpResponse.SendJsonUtf8(const AUtf8Json: RawByteString);
begin
  SetContentType('application/json');
  if Length(AUtf8Json) > 0 then
    FBody.Write(AUtf8Json[1], Length(AUtf8Json));
end;
procedure TMockHttpResponse.SendJsonUtf8(const ABuffer: TBytes);
begin
  SetContentType('application/json');
  if Length(ABuffer) > 0 then
    FBody.Write(ABuffer[0], Length(ABuffer));
end;
function TMockHttpResponse.GetOutputStream: TStream;
begin
  SetContentType('application/json');
  Result := FBody;
end;
procedure TMockHttpResponse.Json(const AJson: string); begin end;
procedure TMockHttpResponse.Json(const AValue: TValue); begin end;
procedure TMockHttpResponse.WriteJson(const AValue: TValue); begin end;
procedure TMockHttpResponse.WriteJson(ACode: Integer; const AValue: TValue); begin end;
procedure TMockHttpResponse.WriteJson(const AQuery: IDextFastQuery); begin end;
procedure TMockHttpResponse.WriteJson(ACode: Integer; const AQuery: IDextFastQuery); begin end;
{$IFDEF DEXT_ENABLE_ENTITY}
procedure TMockHttpResponse.WriteJson(const AStream: IDbSetFastStream); begin end;
procedure TMockHttpResponse.WriteJson(ACode: Integer; const AStream: IDbSetFastStream); begin end;
{$ENDIF}
procedure TMockHttpResponse.AddHeader(const AName, AValue: string);
begin
  FHeaders.AddOrSetValue(AName, AValue);
end;
procedure TMockHttpResponse.AppendCookie(const AName, AValue: string;
  const AOptions: TCookieOptions); begin end;
procedure TMockHttpResponse.AppendCookie(const AName, AValue: string); begin end;
procedure TMockHttpResponse.DeleteCookie(const AName: string); begin end;
procedure TMockHttpResponse.Redirect(const AUrl: string; APermanent: Boolean); begin end;
procedure TMockHttpResponse.Unauthorized(const AMessage: string); begin end;
procedure TMockHttpResponse.Forbidden(const AMessage: string); begin end;
procedure TMockHttpResponse.BadRequest(const AMessage: string); begin end;
procedure TMockHttpResponse.NotFound(const AMessage: string); begin end;
function TMockHttpResponse.GetHtmx: IHtmxResponse; begin Result := nil; end;
function TMockHttpResponse.GetHeaders: IStringDictionary; begin Result := FHeaders; end;

{ TMockHttpContext }

constructor TMockHttpContext.Create(AReq: Dext.Web.Interfaces.IHttpRequest;
  ARes: Dext.Web.Interfaces.IHttpResponse);
begin
  FRequest := AReq;
  FResponse := ARes;
  FItems := TCollections.CreateDictionary<string, TValue>;
end;

destructor TMockHttpContext.Destroy;
begin
  inherited;
end;

// Interface method mappings omitted for space, inline:
function TMockHttpContext.GetConnection: IDextServerConnection; begin Result := nil; end;
function TMockHttpContext.GetRequest: Dext.Web.Interfaces.IHttpRequest; begin Result := FRequest; end;
function TMockHttpContext.GetResponse: Dext.Web.Interfaces.IHttpResponse; begin Result := FResponse; end;
procedure TMockHttpContext.SetResponse(const AValue: Dext.Web.Interfaces.IHttpResponse); begin FResponse := AValue; end;
function TMockHttpContext.GetServices: IServiceProvider; begin Result := nil; end;
procedure TMockHttpContext.SetServices(const AValue: IServiceProvider); begin end;
function TMockHttpContext.GetUser: IClaimsPrincipal; begin Result := nil; end;
procedure TMockHttpContext.SetUser(const AValue: IClaimsPrincipal); begin end;
function TMockHttpContext.GetItems: IDictionary<string, TValue>; begin Result := FItems; end;
function TMockHttpContext.GetSession: IStreamableSession; begin Result := nil; end;
function TMockHttpContext.GetEndpointMetadata: TEndpointMetadata;
var
  Meta: TEndpointMetadata;
begin
  Result := Meta;
end;
procedure TMockHttpContext.SetEndpointMetadata(
  const AMetadata: TEndpointMetadata); begin end;
procedure TMockHttpContext.SetRouteParams(
  const AParams: TRouteValueDictionary); begin end;

{ TGrpcClient }

constructor TGrpcClient.Create(const AHost: string; APort: Integer);
begin
  FHost := AHost;
  FPort := APort;
end;

constructor TGrpcClient.Create(ADispatcher: TDextGrpcDispatcher);
begin
  FDispatcher := ADispatcher;
end;

procedure TGrpcClient.CallMethod(const AServiceName, AMethodName: string;
  ARequest, AResponse: TObject);
var
  Client: THTTPClient;
  Compressed: Boolean;
  Context: Dext.Web.Interfaces.IHttpContext;
  FramedReq: TBytes;
  LogInfoActive: Boolean;
  MockReq: TMockHttpRequest;
  MockRes: TMockHttpResponse;
  MsgBytes: TBytes;
  MsgVal: string;
  Offset: Integer;
  Payload: TJSONObject;
  ReqBytes: TBytes;
  ReqStream, ResStream: TMemoryStream;
  ResBytes: TBytes;
  Response: IHTTPResponse;
  Span: TSpan;
  StatusVal: string;
  Sw: TStopwatch;
  SwSub: TStopwatch;
  TelemetryActive: Boolean;
  TimingActive: Boolean;
  Url: string;
begin
  TelemetryActive := TDiagnosticSource.Instance.IsActive;
  LogInfoActive := Log.Logger.IsEnabled(TLogLevel.Information);
  TimingActive := TelemetryActive or LogInfoActive;
  if TelemetryActive then
    Span := TTracer.BeginSpan('gRPC Client ' + AServiceName + '/' + AMethodName,
      'gRPC')
  else
    Span := TSpan.Create(nil);
  try
    if TelemetryActive then
      SwSub := TStopwatch.StartNew;
    ReqBytes := TProtobufSerializer.Serialize(ARequest);
    if TelemetryActive then
    begin
      SwSub.Stop;
      Payload := TJSONObject.Create;
      Payload.AddPair('service', AServiceName);
      Payload.AddPair('method', AMethodName);
      Payload.AddPair('size', TJSONNumber.Create(Length(ReqBytes)));
      TDiagnosticSource.Instance.Write('gRPC.Client.Serialize', Payload,
        'gRPC', SwSub.ElapsedMilliseconds);
    end;

    if TelemetryActive then
      SwSub := TStopwatch.StartNew;
    FramedReq := TGrpcMessageCodec.Encode(ReqBytes);
    if TelemetryActive then
    begin
      SwSub.Stop;
      Payload := TJSONObject.Create;
      Payload.AddPair('service', AServiceName);
      Payload.AddPair('method', AMethodName);
      Payload.AddPair('size', TJSONNumber.Create(Length(FramedReq)));
      TDiagnosticSource.Instance.Write('gRPC.Client.Encode', Payload,
        'gRPC', SwSub.ElapsedMilliseconds);
    end;

    if TimingActive then
      Sw := TStopwatch.StartNew;

    if Assigned(FDispatcher) then
    begin
      MockReq := TMockHttpRequest.Create('/' + AServiceName + '/' + AMethodName,
        FramedReq);
      MockRes := TMockHttpResponse.Create;
      Context := TMockHttpContext.Create(MockReq, MockRes);

      FDispatcher.Invoke(Context);

      if TimingActive then
        Sw.Stop;

      if MockRes.Headers.TryGetValue('grpc-status', StatusVal) and
         (StatusVal <> '0') then
      begin
        MockRes.Headers.TryGetValue('grpc-message', MsgVal);
        Log.Error('[gRPC-Client] In-Process Error: {Msg} (Status: {Status})',
          [MsgVal, StatusVal]);

        Span.SetStatus('Error', MsgVal);
        if TelemetryActive then
        begin
          Payload := TJSONObject.Create;
          Payload.AddPair('service', AServiceName);
          Payload.AddPair('method', AMethodName);
          Payload.AddPair('transport', 'in-process');
          Payload.AddPair('status', StatusVal);
          Payload.AddPair('error', MsgVal);
          TDiagnosticSource.Instance.Write('gRPC.Client.Error', Payload,
            'gRPC', Sw.ElapsedMilliseconds);
        end;

        raise Exception.CreateFmt('gRPC Remote Error: %s (Status: %s)',
          [MsgVal, StatusVal]);
      end;

      if MockRes.Body.Size > 0 then
      begin
        SetLength(ResBytes, MockRes.Body.Size);
        MockRes.Body.Position := 0;
        MockRes.Body.Read(ResBytes[0], MockRes.Body.Size);
      end
      else
        SetLength(ResBytes, 0);

      if MockRes.GetStatusCode <> 200 then
        raise Exception.CreateFmt('HTTP Error: %d %s',
          [MockRes.GetStatusCode, TEncoding.UTF8.GetString(ResBytes)]);

      if LogInfoActive then
        Log.Info('[gRPC-Client] In-Process Call: {Service}/{Method} | ' +
          'Duration: {Time} ms | Req: {ReqSz} bytes | Res: {ResSz} bytes',
          [AServiceName, AMethodName, Sw.ElapsedMilliseconds, Length(FramedReq),
           Length(ResBytes)]);

      Span.SetStatus('Success');
      if TelemetryActive then
      begin
        Payload := TJSONObject.Create;
        Payload.AddPair('service', AServiceName);
        Payload.AddPair('method', AMethodName);
        Payload.AddPair('transport', 'in-process');
        Payload.AddPair('req_size', TJSONNumber.Create(Length(FramedReq)));
        Payload.AddPair('res_size', TJSONNumber.Create(Length(ResBytes)));
        TDiagnosticSource.Instance.Write('gRPC.Client.Call', Payload, 'gRPC',
          Sw.ElapsedMilliseconds);
      end;
    end
    else
    begin
      Client := THTTPClient.Create;
      ReqStream := TMemoryStream.Create;
      ResStream := TMemoryStream.Create;
      try
        if Length(FramedReq) > 0 then
          ReqStream.WriteBuffer(FramedReq[0], Length(FramedReq));
        ReqStream.Position := 0;

        Url := Format('http://%s:%d/%s/%s', [FHost, FPort, AServiceName,
          AMethodName]);

        Client.ContentType := 'application/grpc';

        if TelemetryActive then
          SwSub := TStopwatch.StartNew;
        Response := Client.Post(Url, ReqStream, ResStream);
        if TelemetryActive then
          SwSub.Stop;

        if TimingActive then
          Sw.Stop;

        if TelemetryActive then
        begin
          Payload := TJSONObject.Create;
          Payload.AddPair('service', AServiceName);
          Payload.AddPair('method', AMethodName);
          Payload.AddPair('url', Url);
          Payload.AddPair('status_code',
            TJSONNumber.Create(Response.StatusCode));
          TDiagnosticSource.Instance.Write('gRPC.Client.Transport', Payload,
            'gRPC', SwSub.ElapsedMilliseconds);
        end;

        if Response.StatusCode <> 200 then
        begin
          Log.Error('[gRPC-Client] HTTP Error {Code}: {Text} | {Service}/{Method}',
            [Response.StatusCode, Response.StatusText, AServiceName,
             AMethodName]);

          Span.SetStatus('Error', Response.StatusText);
          if TelemetryActive then
          begin
            Payload := TJSONObject.Create;
            Payload.AddPair('service', AServiceName);
            Payload.AddPair('method', AMethodName);
            Payload.AddPair('transport', 'network');
            Payload.AddPair('http_status',
              TJSONNumber.Create(Response.StatusCode));
            Payload.AddPair('error', Response.StatusText);
            TDiagnosticSource.Instance.Write('gRPC.Client.Error', Payload,
              'gRPC', Sw.ElapsedMilliseconds);
          end;

          raise Exception.CreateFmt('HTTP Error: %d %s',
            [Response.StatusCode, Response.StatusText]);
        end;

        StatusVal := Response.HeaderValue['grpc-status'];
        if (StatusVal <> '') and (StatusVal <> '0') then
        begin
          MsgVal := Response.HeaderValue['grpc-message'];
          Log.Error('[gRPC-Client] Remote Error: {Msg} (Status: {Status})',
            [MsgVal, StatusVal]);

          Span.SetStatus('Error', MsgVal);
          if TelemetryActive then
          begin
            Payload := TJSONObject.Create;
            Payload.AddPair('service', AServiceName);
            Payload.AddPair('method', AMethodName);
            Payload.AddPair('transport', 'network');
            Payload.AddPair('status', StatusVal);
            Payload.AddPair('error', MsgVal);
            TDiagnosticSource.Instance.Write('gRPC.Client.Error', Payload,
              'gRPC', Sw.ElapsedMilliseconds);
          end;

          raise Exception.CreateFmt('gRPC Remote Error: %s (Status: %s)',
            [MsgVal, StatusVal]);
        end;

        if ResStream.Size > 0 then
        begin
          SetLength(ResBytes, ResStream.Size);
          ResStream.Position := 0;
          ResStream.ReadBuffer(ResBytes[0], ResStream.Size);
        end
        else
          SetLength(ResBytes, 0);

        if LogInfoActive then
          Log.Info('[gRPC-Client] HTTP Call: {Service}/{Method} | ' +
            'Duration: {Time} ms | Req: {ReqSz} bytes | Res: {ResSz} bytes',
            [AServiceName, AMethodName, Sw.ElapsedMilliseconds, Length(FramedReq),
             Length(ResBytes)]);

        Span.SetStatus('Success');
        if TelemetryActive then
        begin
          Payload := TJSONObject.Create;
          Payload.AddPair('service', AServiceName);
          Payload.AddPair('method', AMethodName);
          Payload.AddPair('transport', 'network');
          Payload.AddPair('req_size', TJSONNumber.Create(Length(FramedReq)));
          Payload.AddPair('res_size', TJSONNumber.Create(Length(ResBytes)));
          TDiagnosticSource.Instance.Write('gRPC.Client.Call', Payload,
            'gRPC', Sw.ElapsedMilliseconds);
        end;
      finally
        ReqStream.Free;
        ResStream.Free;
        Client.Free;
      end;
    end;

    Offset := 0;
    if TelemetryActive then
      SwSub := TStopwatch.StartNew;
    if TGrpcMessageCodec.TryDecode(ResBytes, Offset, Compressed, MsgBytes) then
    begin
      if TelemetryActive then
      begin
        SwSub.Stop;
        Payload := TJSONObject.Create;
        Payload.AddPair('service', AServiceName);
        Payload.AddPair('method', AMethodName);
        Payload.AddPair('size', TJSONNumber.Create(Length(MsgBytes)));
        TDiagnosticSource.Instance.Write('gRPC.Client.Decode', Payload,
          'gRPC', SwSub.ElapsedMilliseconds);
      end;

      if TelemetryActive then
        SwSub := TStopwatch.StartNew;
      TProtobufSerializer.Deserialize(MsgBytes, AResponse);
      if TelemetryActive then
      begin
        SwSub.Stop;
        Payload := TJSONObject.Create;
        Payload.AddPair('service', AServiceName);
        Payload.AddPair('method', AMethodName);
        TDiagnosticSource.Instance.Write('gRPC.Client.Deserialize', Payload,
          'gRPC', SwSub.ElapsedMilliseconds);
      end;
    end
    else
    begin
      raise Exception.Create('Failed to unpack gRPC response frame');
    end;
  except
    on E: Exception do
    begin
      Span.SetStatus('Error', E.Message);
      raise;
    end;
  end;
end;

{ TEntitygRpcProvider<T> }

constructor TEntitygRpcProvider<T>.Create(AClient: TGrpcClient;
  const AServiceName: string);
begin
  FClient := AClient;
  FServiceName := AServiceName;
end;

{ TGenericListResponse<TItem> }

constructor TGenericListResponse<TItem>.Create;
begin
  inherited Create;
  // Does not own the items: FetchAll hands them to the caller.
  FItems := TCollections.CreateList<TItem>(False);
end;

destructor TGenericListResponse<TItem>.Destroy;
var
  Item: TItem;
begin
  for Item in FItems do
    Item.Free;
  FItems := nil;
  inherited;
end;

function TEntitygRpcProvider<T>.FetchAll(const AQuery: string): TList<T>;
var
  Request: TGenericQueryRequest;
  Response: TGenericListResponse<T>;
  Item: T;
begin
  Request := TGenericQueryRequest.Create;
  Request.Query := AQuery;
  Response := TGenericListResponse<T>.Create;
  try
    FClient.CallMethod(FServiceName, 'FetchAll', Request, Response);
    Result := TList<T>.Create;
    for Item in Response.Items do
    begin
      Result.Add(Item);
    end;
    Response.Items.Clear;
  finally
    Request.Free;
    Response.Free;
  end;
end;

procedure TEntitygRpcProvider<T>.ApplyChanges(const AList: TList<T>);
begin
  // A list of entities does not say what changed. Failing here is better
  // than a call that returns and sends nothing.
  raise ENotSupportedException.Create(
    'TEntitygRpcProvider<T>.ApplyChanges is not implemented. Send the ' +
    'changes of the dataset with a service call of your own.');
end;

end.
