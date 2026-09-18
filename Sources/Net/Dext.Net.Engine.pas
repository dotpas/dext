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
unit Dext.Net.Engine;

{$I Dext.inc}

interface

{$IF defined(DEXT_FORCE_INDY) or (CompilerVersion < 29.0)}
uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  Dext.Net.Download;

type
  TDextNetHeader = record
    Name: string;
    Value: string;
    constructor Create(const AName, AValue: string);
  end;
  TDextNetHeaders = TArray<TDextNetHeader>;
{$ELSE}
uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.Net.URLClient,
  System.Net.HttpClient,
  Dext.Net.Download;

type
  TDextNetHeader = System.Net.URLClient.TNetHeader;
  TDextNetHeaders = System.Net.URLClient.TNetHeaders;
{$ENDIF}

type
  IDextHttpResponse = interface
    ['{F2C4E6A8-0246-80AC-CE02-4680ACE02468}']
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetContentStream: TStream;
    function GetHeaders: TDextNetHeaders;
  end;

  IDextHttpEngine = interface
    ['{B9D8A7C6-B5E4-4D3C-2B1A-0F9E8D7C6B5A}']
    procedure SetConnectionTimeout(AMilliseconds: Integer);
    procedure SetSendTimeout(AMilliseconds: Integer);
    procedure SetResponseTimeout(AMilliseconds: Integer);
    procedure SetIgnoreCertificateErrors(AValue: Boolean);
    procedure SetClientCertificate(const APath, APassword: string); overload;
    procedure SetClientCertificate(AStream: TStream; const APassword: string); overload;
    procedure ClearClientCertificate;
    function Execute(const AMethod, AUrl: string; const ABody: TStream; const AHeaders: TDextNetHeaders): IDextHttpResponse;
    /// <summary>
    ///   Same as Execute, but the response body is written straight into
    ///   ATarget as it arrives instead of being buffered in memory.
    /// </summary>
    /// <param name="ATarget">
    ///   Destination for the body. Its current position is honoured, so a
    ///   resumed download appends instead of overwriting.
    /// </param>
    /// <param name="AProgress">
    ///   Called once per received chunk on the calling thread. Setting AAbort
    ///   stops the transfer and raises EOperationCancelled.
    /// </param>
    /// <returns>
    ///   A response whose ContentStream is nil on success -- the body went to
    ///   ATarget -- and holds the (bounded) error payload when the status is
    ///   400 or above. An error body never reaches ATarget.
    /// </returns>
    function ExecuteInto(const AMethod, AUrl: string; const ABody: TStream;
      const AHeaders: TDextNetHeaders; const ATarget: TStream;
      const AProgress: TDextReceiveProgress = nil): IDextHttpResponse;
  end;

function CreateHttpEngine: IDextHttpEngine;

implementation

{$IF defined(DEXT_FORCE_INDY) or (CompilerVersion < 29.0)}
uses
  IdHTTP,
  IdSSLOpenSSL,
  IdSSL,
  IdComponent,
  IdHeaderList;
{$ENDIF}

{$IF defined(DEXT_FORCE_INDY) or (CompilerVersion < 29.0)}
{ TDextNetHeader }

constructor TDextNetHeader.Create(const AName, AValue: string);
begin
  Name := AName;
  Value := AValue;
end;
{$ENDIF}

type
  TDextHttpResponseImpl = class(TInterfacedObject, IDextHttpResponse)
  private
    FStatusCode: Integer;
    FStatusText: string;
    FContentStream: TStream;
    /// True when this instance owns FContentStream and must free it. False when
    /// the stream belongs to someone else, kept alive by FKeepAlive.
    FOwnsStream: Boolean;
    /// Holds a reference to whoever owns the content stream (the RTL's
    /// IHTTPResponse), so the bytes stay valid for as long as this response does.
    FKeepAlive: IInterface;
    FHeaders: TDextNetHeaders;
  public
    /// <summary>Takes the response over WITHOUT copying its content.</summary>
    /// <param name="AOwnsStream">
    ///   True: this instance frees AStream (caller must not).
    ///   False: AKeepAlive must reference the owner, so the memory outlives us.
    /// </param>
    /// <remarks>
    ///   The payload used to be copied into a private TMemoryStream, which meant
    ///   every response existed twice in RAM at once -- a 500 MB download peaked
    ///   at a gigabyte. Nothing here needs a copy: the bytes are already in a
    ///   stream that we can either adopt or keep alive.
    /// </remarks>
    constructor Create(AStatusCode: Integer; const AStatusText: string;
      AStream: TStream; const AHeaders: TDextNetHeaders;
      AOwnsStream: Boolean; const AKeepAlive: IInterface = nil);
    destructor Destroy; override;
    function GetStatusCode: Integer;
    function GetStatusText: string;
    function GetContentStream: TStream;
    function GetHeaders: TDextNetHeaders;
  end;

{ TDextHttpResponseImpl }

constructor TDextHttpResponseImpl.Create(AStatusCode: Integer;
  const AStatusText: string; AStream: TStream; const AHeaders: TDextNetHeaders;
  AOwnsStream: Boolean; const AKeepAlive: IInterface);
begin
  inherited Create;
  FStatusCode := AStatusCode;
  FStatusText := AStatusText;
  FHeaders := AHeaders;
  FContentStream := AStream;
  FOwnsStream := AOwnsStream;
  FKeepAlive := AKeepAlive;
  if Assigned(FContentStream) then
    FContentStream.Position := 0;
end;

destructor TDextHttpResponseImpl.Destroy;
begin
  if FOwnsStream then
    FContentStream.Free;
  FKeepAlive := nil;
  inherited;
end;

function TDextHttpResponseImpl.GetContentStream: TStream;
begin
  Result := FContentStream;
end;

function TDextHttpResponseImpl.GetHeaders: TDextNetHeaders;
begin
  Result := FHeaders;
end;

function TDextHttpResponseImpl.GetStatusCode: Integer;
begin
  Result := FStatusCode;
end;

function TDextHttpResponseImpl.GetStatusText: string;
begin
  Result := FStatusText;
end;

{$IF defined(DEXT_FORCE_INDY) or (CompilerVersion < 29.0)}
type
  /// <summary>
  ///   Reaches TIdCustomHTTP.DoRequest, which is protected and has no public
  ///   equivalent for an arbitrary verb (PATCH, QUERY, ...).
  /// </summary>
  TIdHTTPAccess = class(TIdHTTP);

  TDextIndyHttpEngine = class(TInterfacedObject, IDextHttpEngine)
  private
    FIdHttp: TIdHTTP;
    FIgnoreCertErrors: Boolean;
    /// Streaming state, valid only while one ExecuteInto call is running. The
    /// engine is lent out by a pool to one caller at a time, so fields are
    /// enough -- but they must be cleared before it goes back to the pool.
    FGate: TDextDownloadGate;
    FProgress: TDextReceiveProgress;
    FProgressMax: Int64;
    FAborted: Boolean;
    function VerifyPeer(ACertificate: TIdX509; AOk: Boolean; ADepth, AError: Integer): Boolean;
    procedure PrepareRequest(const AUrl: string; const AHeaders: TDextNetHeaders);
    function CollectResponseHeaders: TDextNetHeaders;
    procedure Perform(const AMethod, AUrl: string; const ABody, ATarget: TStream);
    procedure HandleHeadersAvailable(Sender: TObject; AHeaders: TIdHeaderList; var VContinue: Boolean);
    procedure HandleWorkBegin(ASender: TObject; AWorkMode: TWorkMode; AWorkCountMax: Int64);
    procedure HandleWork(ASender: TObject; AWorkMode: TWorkMode; AWorkCount: Int64);
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetConnectionTimeout(AMilliseconds: Integer);
    procedure SetSendTimeout(AMilliseconds: Integer);
    procedure SetResponseTimeout(AMilliseconds: Integer);
    procedure SetIgnoreCertificateErrors(AValue: Boolean);
    procedure SetClientCertificate(const APath, APassword: string); overload;
    procedure SetClientCertificate(AStream: TStream; const APassword: string); overload;
    procedure ClearClientCertificate;
    function Execute(const AMethod, AUrl: string; const ABody: TStream; const AHeaders: TDextNetHeaders): IDextHttpResponse;
    function ExecuteInto(const AMethod, AUrl: string; const ABody: TStream;
      const AHeaders: TDextNetHeaders; const ATarget: TStream;
      const AProgress: TDextReceiveProgress = nil): IDextHttpResponse;
  end;

{ TDextIndyHttpEngine }

constructor TDextIndyHttpEngine.Create;
begin
  inherited Create;
  FIdHttp := TIdHTTP.Create(nil);
  FIdHttp.HandleRedirects := True;
end;

destructor TDextIndyHttpEngine.Destroy;
begin
  FIdHttp.Free;
  inherited;
end;

procedure TDextIndyHttpEngine.SetConnectionTimeout(AMilliseconds: Integer);
begin
  FIdHttp.ConnectTimeout := AMilliseconds;
end;

procedure TDextIndyHttpEngine.SetSendTimeout(AMilliseconds: Integer);
begin
  // Indy does not have a separate send timeout, we map to ReadTimeout
  FIdHttp.ReadTimeout := AMilliseconds;
end;

procedure TDextIndyHttpEngine.SetResponseTimeout(AMilliseconds: Integer);
begin
  FIdHttp.ReadTimeout := AMilliseconds;
end;

procedure TDextIndyHttpEngine.SetIgnoreCertificateErrors(AValue: Boolean);
begin
  FIgnoreCertErrors := AValue;
end;

procedure TDextIndyHttpEngine.SetClientCertificate(const APath, APassword: string);
begin
  // Indy stub - client certificate configuration
end;

procedure TDextIndyHttpEngine.SetClientCertificate(AStream: TStream; const APassword: string);
begin
  // Indy stub - client certificate configuration
end;

procedure TDextIndyHttpEngine.ClearClientCertificate;
begin
  // Indy stub - client certificate cleanup
end;

function TDextIndyHttpEngine.VerifyPeer(ACertificate: TIdX509; AOk: Boolean;
  ADepth, AError: Integer): Boolean;
begin
  Result := True;
end;

procedure TDextIndyHttpEngine.PrepareRequest(const AUrl: string; const AHeaders: TDextNetHeaders);
var
  i: Integer;
  SSLIOHandler: TIdSSLIOHandlerSocketOpenSSL;
begin
  FIdHttp.Request.CustomHeaders.Clear;
  for i := 0 to High(AHeaders) do
  begin
    if SameText(AHeaders[i].Name, 'User-Agent') then
      FIdHttp.Request.UserAgent := AHeaders[i].Value
    else if SameText(AHeaders[i].Name, 'Content-Type') then
      FIdHttp.Request.ContentType := AHeaders[i].Value
    else if SameText(AHeaders[i].Name, 'Accept') then
      FIdHttp.Request.Accept := AHeaders[i].Value
    else
      FIdHttp.Request.CustomHeaders.Values[AHeaders[i].Name] := AHeaders[i].Value;
  end;

  if AUrl.StartsWith('https', True) then
  begin
    if not Assigned(FIdHttp.IOHandler) then
    begin
      SSLIOHandler := TIdSSLIOHandlerSocketOpenSSL.Create(FIdHttp);
      SSLIOHandler.SSLOptions.Method := sslvTLSv1_2;
      SSLIOHandler.SSLOptions.SSLVersions := [sslvTLSv1, sslvTLSv1_1, sslvTLSv1_2];
      SSLIOHandler.SSLOptions.Mode := sslmClient;
      SSLIOHandler.OnVerifyPeer := VerifyPeer;
      FIdHttp.IOHandler := SSLIOHandler;
    end;
  end;
end;

function TDextIndyHttpEngine.CollectResponseHeaders: TDextNetHeaders;
var
  HeadersList: TList<TDextNetHeader>;
  i, Pos: Integer;
  Line: string;
begin
  HeadersList := TList<TDextNetHeader>.Create;
  try
    for i := 0 to FIdHttp.Response.RawHeaders.Count - 1 do
    begin
      Line := FIdHttp.Response.RawHeaders[i];
      Pos := Line.IndexOf(':');
      if Pos > 0 then
        HeadersList.Add(TDextNetHeader.Create(
          Line.Substring(0, Pos).Trim,
          Line.Substring(Pos + 1).Trim
        ));
    end;
    Result := HeadersList.ToArray;
  finally
    HeadersList.Free;
  end;
end;

procedure TDextIndyHttpEngine.Perform(const AMethod, AUrl: string; const ABody, ATarget: TStream);
begin
  if SameText(AMethod, 'GET') then
    FIdHttp.Get(AUrl, ATarget)
  else if SameText(AMethod, 'POST') then
    FIdHttp.Post(AUrl, ABody, ATarget)
  else if SameText(AMethod, 'PUT') then
    FIdHttp.Put(AUrl, ABody, ATarget)
  else if SameText(AMethod, 'DELETE') then
    FIdHttp.Delete(AUrl, ATarget)
  else
    TIdHTTPAccess(FIdHttp).DoRequest(AMethod, AUrl, ABody, ATarget, []);
end;

procedure TDextIndyHttpEngine.HandleHeadersAvailable(Sender: TObject;
  AHeaders: TIdHeaderList; var VContinue: Boolean);
begin
  VContinue := True;
  // The headers are in, so the status is known: this is the moment we learn
  // whether the bytes about to arrive belong in the caller's stream or in the
  // error buffer.
  if (FGate <> nil) and (FIdHttp.ResponseCode < 300) then
    FGate.Open;
end;

procedure TDextIndyHttpEngine.HandleWorkBegin(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCountMax: Int64);
begin
  if AWorkMode = wmRead then
    // Zero when the server sent no Content-Length (chunked): the callback
    // contract is that a zero total means "unknown".
    FProgressMax := AWorkCountMax;
end;

procedure TDextIndyHttpEngine.HandleWork(ASender: TObject; AWorkMode: TWorkMode;
  AWorkCount: Int64);
var
  Abort: Boolean;
begin
  if (AWorkMode <> wmRead) or not Assigned(FProgress) then
    Exit;
  // An error page is not progress, and Indy reports it through this same event.
  if (FGate <> nil) and not FGate.IsOpen then
    Exit;
  Abort := False;
  FProgress(FProgressMax, AWorkCount, Abort);
  if Abort then
  begin
    FAborted := True;
    // Indy has no "stop reading" flag: dropping the socket is the way out. It
    // surfaces as a read failure, which ExecuteInto turns back into a cancel.
    FIdHttp.Disconnect(False);
  end;
end;

function TDextIndyHttpEngine.Execute(const AMethod, AUrl: string; const ABody: TStream; const AHeaders: TDextNetHeaders): IDextHttpResponse;
var
  ResponseStream: TMemoryStream;
begin
  PrepareRequest(AUrl, AHeaders);

  ResponseStream := TMemoryStream.Create;
  try
    Perform(AMethod, AUrl, ABody, ResponseStream);
  except
    ResponseStream.Free;
    raise;
  end;

  try
    // The response ADOPTS the stream (no copy, and we must not free it here).
    Result := TDextHttpResponseImpl.Create(
      FIdHttp.ResponseCode,
      FIdHttp.ResponseText,
      ResponseStream,
      CollectResponseHeaders,
      True { AOwnsStream }
    );
  except
    ResponseStream.Free;
    raise;
  end;
end;

function TDextIndyHttpEngine.ExecuteInto(const AMethod, AUrl: string; const ABody: TStream;
  const AHeaders: TDextNetHeaders; const ATarget: TStream;
  const AProgress: TDextReceiveProgress): IDextHttpResponse;
var
  Gate: TDextDownloadGate;
  SavedOptions: TIdHTTPOptions;
  ErrorStream: TBytesStream;
begin
  Gate := TDextDownloadGate.Create(ATarget);
  try
    PrepareRequest(AUrl, AHeaders);
    // Indy decompresses from a temporary buffer rather than as it reads, so a
    // compressed body would defeat the point of streaming. Ask for the bytes
    // as they are.
    if FIdHttp.Request.AcceptEncoding = '' then
      FIdHttp.Request.AcceptEncoding := 'identity';

    FGate := Gate;
    FProgress := AProgress;
    FProgressMax := 0;
    FAborted := False;
    SavedOptions := FIdHttp.HTTPOptions;
    // Let an error status come back as a response instead of an exception, so
    // the caller can read what the server said. The payload is in the gate,
    // never in ATarget.
    FIdHttp.HTTPOptions := SavedOptions + [hoNoProtocolErrorException, hoWantProtocolErrorContent];
    FIdHttp.OnHeadersAvailable := HandleHeadersAvailable;
    FIdHttp.OnWorkBegin := HandleWorkBegin;
    FIdHttp.OnWork := HandleWork;
    try
      try
        Perform(AMethod, AUrl, ABody, Gate);
      except
        if FAborted then
          raise EOperationCancelled.Create('Download cancelled by the progress callback');
        raise;
      end;
    finally
      FIdHttp.OnHeadersAvailable := nil;
      FIdHttp.OnWorkBegin := nil;
      FIdHttp.OnWork := nil;
      FIdHttp.HTTPOptions := SavedOptions;
      FGate := nil;
      FProgress := nil;
    end;

    if FAborted then
      raise EOperationCancelled.Create('Download cancelled by the progress callback');
    // A success with an empty body never opens the gate on its own.
    if FIdHttp.ResponseCode < 400 then
      Gate.Open;

    if Gate.IsOpen then
      Result := TDextHttpResponseImpl.Create(FIdHttp.ResponseCode, FIdHttp.ResponseText,
        nil, CollectResponseHeaders, False { AOwnsStream })
    else
    begin
      ErrorStream := TBytesStream.Create(Gate.ErrorBytes);
      Result := TDextHttpResponseImpl.Create(FIdHttp.ResponseCode, FIdHttp.ResponseText,
        ErrorStream, CollectResponseHeaders, True { AOwnsStream });
    end;
  finally
    Gate.Free;
  end;
end;

{$ELSE}

type
  TDextNetHttpEngine = class(TInterfacedObject, IDextHttpEngine)
  private
    FClient: THTTPClient;
    FIgnoreCertErrors: Boolean;
    FCertPath: string;
    FCertPassword: string;
    FCertStream: TMemoryStream;
    procedure ValidateServerCertificate(const Sender: TObject; const ARequest: TURLRequest; const Certificate: TCertificate; var AValidate: Boolean);
    procedure ApplyClientCertificate(const ARequest: IHTTPRequest);
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetConnectionTimeout(AMilliseconds: Integer);
    procedure SetSendTimeout(AMilliseconds: Integer);
    procedure SetResponseTimeout(AMilliseconds: Integer);
    procedure SetIgnoreCertificateErrors(AValue: Boolean);
    procedure SetClientCertificate(const APath, APassword: string); overload;
    procedure SetClientCertificate(AStream: TStream; const APassword: string); overload;
    procedure ClearClientCertificate;
    function Execute(const AMethod, AUrl: string; const ABody: TStream; const AHeaders: TDextNetHeaders): IDextHttpResponse;
    function ExecuteInto(const AMethod, AUrl: string; const ABody: TStream;
      const AHeaders: TDextNetHeaders; const ATarget: TStream;
      const AProgress: TDextReceiveProgress = nil): IDextHttpResponse;
  end;

{ TDextNetHttpEngine }

constructor TDextNetHttpEngine.Create;
begin
  inherited Create;
  FIgnoreCertErrors := True;
  FClient := THTTPClient.Create;
  FClient.OnValidateServerCertificate := ValidateServerCertificate;
end;

procedure TDextNetHttpEngine.ValidateServerCertificate(const Sender: TObject; const ARequest: TURLRequest; const Certificate: TCertificate; var AValidate: Boolean);
begin
  if FIgnoreCertErrors then
    AValidate := True;
end;

procedure TDextNetHttpEngine.SetIgnoreCertificateErrors(AValue: Boolean);
begin
  FIgnoreCertErrors := AValue;
end;

destructor TDextNetHttpEngine.Destroy;
begin
  ClearClientCertificate;
  FClient.Free;
  inherited;
end;

procedure TDextNetHttpEngine.SetConnectionTimeout(AMilliseconds: Integer);
begin
  FClient.ConnectionTimeout := AMilliseconds;
end;

procedure TDextNetHttpEngine.SetSendTimeout(AMilliseconds: Integer);
begin
  FClient.SendTimeout := AMilliseconds;
end;

procedure TDextNetHttpEngine.SetResponseTimeout(AMilliseconds: Integer);
begin
  FClient.ResponseTimeout := AMilliseconds;
end;

procedure TDextNetHttpEngine.SetClientCertificate(const APath, APassword: string);
begin
  ClearClientCertificate;
  FCertPath := APath;
  FCertPassword := APassword;
end;

procedure TDextNetHttpEngine.SetClientCertificate(AStream: TStream; const APassword: string);
begin
  ClearClientCertificate;
  FCertPassword := APassword;
  if Assigned(AStream) then
  begin
    FCertStream := TMemoryStream.Create;
    AStream.Position := 0;
    FCertStream.CopyFrom(AStream, AStream.Size);
    FCertStream.Position := 0;
  end;
end;

procedure TDextNetHttpEngine.ClearClientCertificate;
begin
  FCertPath := '';
  FCertPassword := '';
  FreeAndNil(FCertStream);
end;

procedure TDextNetHttpEngine.ApplyClientCertificate(const ARequest: IHTTPRequest);
begin
  if not Assigned(ARequest) then Exit;
  if Assigned(FCertStream) then
  begin
    FCertStream.Position := 0;
    ARequest.SetClientCertificate(FCertStream, FCertPassword);
  end
  else if FCertPath <> '' then
    ARequest.SetClientCertificate(FCertPath, FCertPassword);
end;

function TDextNetHttpEngine.Execute(const AMethod, AUrl: string; const ABody: TStream; const AHeaders: TDextNetHeaders): IDextHttpResponse;
var
  i: Integer;
  Request: IHTTPRequest;
  Response: IHTTPResponse;
begin
  Request := FClient.GetRequest(AMethod, TURI.Create(AUrl));
  for i := 0 to High(AHeaders) do
    Request.AddHeader(AHeaders[i].Name, AHeaders[i].Value);
  if Assigned(ABody) then
    Request.SourceStream := ABody;

  ApplyClientCertificate(Request);

  Response := FClient.Execute(Request) as IHTTPResponse;
  // No copy: the RTL already buffered the payload. We hand the same stream over
  // and keep the IHTTPResponse referenced, so its memory stays valid.
  Result := TDextHttpResponseImpl.Create(
    Response.StatusCode,
    Response.StatusText,
    Response.ContentStream,
    Response.Headers,
    False { AOwnsStream },
    Response { AKeepAlive }
  );
end;

function TDextNetHttpEngine.ExecuteInto(const AMethod, AUrl: string; const ABody: TStream;
  const AHeaders: TDextNetHeaders; const ATarget: TStream;
  const AProgress: TDextReceiveProgress): IDextHttpResponse;
var
  i: Integer;
  LRequest: IHTTPRequest;
  LResponse: IHTTPResponse;
  Gate: TDextDownloadGate;
  Aborted: Boolean;
  ErrorStream: TBytesStream;
  SavedDecompression: THTTPCompressionMethods;
begin
  Gate := TDextDownloadGate.Create(ATarget);
  SavedDecompression := FClient.AutomaticDecompression;
  try
    Aborted := False;
    // Decompression ON THE FLY -- which is the whole point here. With the body
    // going straight into the caller's stream there is no later stage left to
    // decode it, so a gzipped response would land on disk still gzipped. The RTL
    // decodes as it reads and negotiates Accept-Encoding by itself. Saved and
    // restored because engines come from a shared pool.
    FClient.AutomaticDecompression := [THTTPCompressionMethod.GZip,
      THTTPCompressionMethod.Deflate];
    LRequest := FClient.GetRequest(AMethod, TURI.Create(AUrl));
    for i := 0 to High(AHeaders) do
      LRequest.AddHeader(AHeaders[i].Name, AHeaders[i].Value);
    if Assigned(ABody) then
      LRequest.SourceStream := ABody;

    ApplyClientCertificate(LRequest);

    // On the REQUEST, not on the client: engines come from a shared pool, and a
    // callback left behind on the client would fire for the next borrower.
    LRequest.ReceiveDataCallback :=
      procedure(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean)
      begin
        // The RTL raises this only below status 300, so the first call is proof
        // that these bytes belong in the caller's stream.
        Gate.Open;
        if Assigned(AProgress) then
          AProgress(AContentLength, AReadCount, AAbort);
        if AAbort then
          Aborted := True;
      end;

    try
      LResponse := FClient.Execute(LRequest, Gate);
    except
      // An abort surfaces as a socket or protocol failure. Say what it was.
      if Aborted then
        raise EOperationCancelled.Create('Download cancelled by the progress callback');
      raise;
    end;

    if Aborted then
      raise EOperationCancelled.Create('Download cancelled by the progress callback');
    // A success with an empty body never fires the callback, so "no bytes" must
    // not be mistaken for an error payload.
    if LResponse.StatusCode < 400 then
      Gate.Open;

    if Gate.IsOpen then
      Result := TDextHttpResponseImpl.Create(LResponse.StatusCode, LResponse.StatusText,
        nil, LResponse.Headers, False { AOwnsStream })
    else
    begin
      ErrorStream := TBytesStream.Create(Gate.ErrorBytes);
      Result := TDextHttpResponseImpl.Create(LResponse.StatusCode, LResponse.StatusText,
        ErrorStream, LResponse.Headers, True { AOwnsStream });
    end;
  finally
    FClient.AutomaticDecompression := SavedDecompression;
    Gate.Free;
  end;
end;

{$ENDIF}

function CreateHttpEngine: IDextHttpEngine;
begin
  {$IF defined(DEXT_FORCE_INDY) or (CompilerVersion < 29.0)}
  Result := TDextIndyHttpEngine.Create;
  {$ELSE}
  Result := TDextNetHttpEngine.Create;
  {$ENDIF}
end;

end.
