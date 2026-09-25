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
{  Windows HTTP Server (http.sys) driver implementation.                    }
{***************************************************************************}
unit Dext.Server.HttpSys;

interface

{$IFDEF MSWINDOWS}
uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.NetEncoding,
  Winapi.Windows,
  Winapi.Winsock2,
  Dext.Collections.Dict,
  Dext.Collections,
  Dext.Threading.ProcessorGroups,
  Dext.Server.Engine.Types,
  Dext.Server.Engine.Interfaces,
  Dext.Server.HttpSys.Api,
  Dext.WebSocket.Compression,
  Dext.Web.Interfaces,
  Dext.DI.Interfaces,
  Dext.Web.ResponseWriter;


type
  TDextHttpSysEngine = class;
  TDextHttpSysRequest = class;
  TDextHttpSysResponse = class;
  TDextHttpSysConnection = class;
  TDextHttpSysContext = class;

  TDextHttpSysOperationKind = (
    hokReceiveRequest,
    hokReceiveBody,
    hokSendHeaders,
    hokSendBody,
    hokWebSocketReceive,
    hokWebSocketSend
  );

  TDextHttpSysOperation = record
    Overlapped: TOverlapped;
    Kind: TDextHttpSysOperationKind;
    Context: Pointer;
    Generation: Cardinal;
  end;
  PDextHttpSysOperation = ^TDextHttpSysOperation;

  TDextHttpSysContext = class
  public
    FReceiveOp: TDextHttpSysOperation;
    FBodyOp: TDextHttpSysOperation;
    FBuffer: TBytes;
    FBufferCapacity: Cardinal;
    FGeneration: Cardinal;
    FRequestId: HTTP_REQUEST_ID;
    FRequest: TDextHttpSysRequest;
    FResponse: TDextHttpSysResponse;
    FResponseIntf: IDextRawResponse;
    FRequestIntf: IDextRawRequest;
    FConnection: TDextHttpSysConnection;
    FRefCount: Integer;
    FBodyEvent: TEvent;
    FBodyBytesReceived: DWORD;
    FBodyError: DWORD;
    FBodyBuffer: TBytes;
    FPrefetchedBody: TMemoryStream;
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    procedure ReleaseRequestReference;
    procedure ReleaseResponseReference;
  end;

  /// <summary>
  ///   Thread-safe, zero-allocation memory stream pool for http.sys responses.
  /// </summary>
  TDextHttpSysBufferPool = class
  private
    FPool: TList;
    FLock: TSpinLock;
    FMaxPoolSize: Integer;
  public
    constructor Create(AMaxPoolSize: Integer = 64);
    destructor Destroy; override;
    function Acquire: TMemoryStream;
    procedure Release(ABuffer: TMemoryStream);
  end;

  /// <summary>
  ///   Raw request implementation wrapper for Windows http.sys.
  /// </summary>
  TDextHttpSysRequest = class(TInterfacedObject, IDextRawRequest)
  private
    FEngine: TDextHttpSysEngine;
    FReqQueue: THandle;
    FRequest: PHTTP_REQUEST;
    FBodyStream: TCustomMemoryStream;
    FEntityBodyBuffer: TMemoryStream;
    FBodyRead: Boolean;
    FContext: TDextHttpSysContext;
    function GetMethod: string;
    function GetPath: string;
    function GetQueryString: string;
    function GetHeader(const AName: string): string;
    procedure PopulateHeaders(ADict: TDictionary<string, string>);
    function GetContentLength: Int64;
    function GetBodyStream: TStream;
    function _Release: Integer; stdcall;
  public
    /// <summary>Initializes a raw http.sys request wrapper.</summary>
    /// <param name="ARequest">Pointer to the native HTTP_REQUEST structure.</param>
    constructor Create(ARequest: PHTTP_REQUEST);
    /// <summary>Cleans up the request resources.</summary>
    destructor Destroy; override;
    procedure Init(AEngine: TDextHttpSysEngine; ARequest: PHTTP_REQUEST;
      AContext: TDextHttpSysContext = nil);
  end;

  /// <summary>
  ///   Raw response implementation wrapper for Windows http.sys.
  /// </summary>
  TDextHttpSysResponse = class(TInterfacedObject, IDextRawResponse,
    IDextRawResponseSink)
  private
    FEngine: TDextHttpSysEngine;
    FReqQueue: THandle;
    FRequestId: HTTP_REQUEST_ID;
    FHeadersSent: Boolean;
    FResponseComplete: Boolean;
    FStatusCode: USHORT;
    FHeaderData: array[0..4095] of AnsiChar;
    FHeaderDataLen: Integer;
    FHeaderValues: array[0..29] of record
      Offset: Integer;
      Length: Integer;
    end;
    FReasonBuffer: array[0..127] of AnsiChar;
    FReasonLen: Integer;
    FResponseWriter: TDextResponseWriter;
    FUnknownHeaders: array[0..31] of HTTP_UNKNOWN_HEADER;
    FUnknownHeadersCount: Integer;
    FLastUnknownHeadersCount: Integer;
    FContext: TDextHttpSysContext;
    FSendOp: TDextHttpSysOperation;
    FNativeResponse: HTTP_RESPONSE;
    FChunks: TArray<HTTP_DATA_CHUNK>;
    procedure ResetUnknownHeaders;
    procedure SendHeadersInternal(AMoreData: Boolean);
    function _Release: Integer; stdcall;
    procedure SetHeaderInt(AIndex: Integer; AValue: Int64);
  public
    /// <summary>Initializes a new http.sys response wrapper.</summary>
    /// <param name="AEngine">The http.sys engine reference.</param>
    /// <param name="AReqQueue">Handle to the request queue.</param>
    /// <param name="ARequestId">The unique ID of the request to respond to.</param>
    constructor Create(AEngine: TDextHttpSysEngine; AReqQueue: THandle; ARequestId: HTTP_REQUEST_ID);
    /// <summary>Cleans up the response resources.</summary>
    destructor Destroy; override;
    procedure Init(AEngine: TDextHttpSysEngine; AReqQueue: THandle;
      ARequestId: HTTP_REQUEST_ID; AContext: TDextHttpSysContext = nil);

    /// <summary>Sets the HTTP status code and optional reason phrase.</summary>
    /// <param name="ACode">The HTTP status code (e.g., 200, 404).</param>
    /// <param name="AReason">Optional HTTP reason phrase.</param>
    procedure SetStatus(ACode: Integer; const AReason: string = '');
    /// <summary>Sets the value of a specific HTTP response header.</summary>
    /// <param name="AName">The name of the header.</param>
    /// <param name="AValue">The value of the header.</param>
    procedure SetHeader(const AName, AValue: string);
    /// <summary>Forces sending of response headers to the client.</summary>
    procedure SendHeaders;
    /// <summary>Writes raw bytes into the response body stream.</summary>
    /// <param name="ABuffer">The byte array buffer containing data to write.</param>
    /// <param name="AOffset">The zero-based byte offset in ABuffer from which to begin writing.</param>
    /// <param name="ACount">The number of bytes to write.</param>
    procedure Write(const ABuffer: TBytes; AOffset, ACount: Integer);
    /// <summary>Writes a raw byte span into response-owned segments.</summary>
    procedure WriteBytes(AData: Pointer; ALength: Integer);
    /// <summary>Writes a file directly to the response socket using zero-copy transmission.</summary>
    /// <param name="APath">The path to the file to serve.</param>
    /// <param name="AOffset">The byte offset from where to start reading the file.</param>
    /// <param name="ACount">The number of bytes to send. If <= 0, serves until the end of the file.</param>
    procedure WriteFile(const APath: string; AOffset, ACount: Int64);
    /// <summary>Flushes any buffered response data to the network.</summary>
    procedure Flush;
    /// <summary>Closes the response stream and connection.</summary>
    procedure Close;
  end;

  /// <summary>
  ///   Thread-safe, zero-allocation request pool for http.sys requests.
  /// </summary>
  TDextHttpSysRequestPool = class
  private
    FPool: TList;
    FLock: TSpinLock;
    FMaxPoolSize: Integer;
  public
    constructor Create(AMaxPoolSize: Integer = 64);
    destructor Destroy; override;
    function Acquire(AEngine: TDextHttpSysEngine; ARequest: PHTTP_REQUEST;
      AContext: TDextHttpSysContext = nil): TDextHttpSysRequest;
    procedure Release(ARequest: TDextHttpSysRequest);
  end;

  /// <summary>
  ///   Thread-safe, zero-allocation response pool for http.sys responses.
  /// </summary>
  TDextHttpSysResponsePool = class
  private
    FPool: TList;
    FLock: TSpinLock;
    FMaxPoolSize: Integer;
  public
    constructor Create(AMaxPoolSize: Integer = 64);
    destructor Destroy; override;
    function Acquire(AEngine: TDextHttpSysEngine; AReqQueue: THandle;
      ARequestId: HTTP_REQUEST_ID;
      AContext: TDextHttpSysContext = nil): TDextHttpSysResponse;
    procedure Release(AResponse: TDextHttpSysResponse);
  end;

  TDextHttpSysWebSocketConnection = class(TInterfacedObject,
    IDextWebSocketConnection, IDextAsyncWebSocketConnection,
    IDextWebSocketQueueMetrics, IDextCompressedWebSocketConnection)
  private
    FEngine: TDextHttpSysEngine;
    FConnectionId: UInt64;
    FReqQueue: THandle;
    FRequestId: HTTP_REQUEST_ID;
    FClosed: Boolean;
    FClosing: Boolean;
    FClosedNotified: Boolean;
    FAsyncMode: Boolean;
    FReceiveActive: Boolean;
    FSendActive: Boolean;
    FReceiveOp: TDextHttpSysOperation;
    FSendOp: TDextHttpSysOperation;
    FReceiveBuffer: TBytes;
    FCurrentSend: TBytes;
    FSendChunk: HTTP_DATA_CHUNK_INMEMORY;
    FCurrentDisconnect: Boolean;
    FSendQueue: IQueue<TBytes>;
    FQueuedBytes: NativeInt;
    FPeakQueuedBytes: NativeInt;
    FRejectedSendCount: Int64;
    FCompressionEnabled: Boolean;
    FLock: TCriticalSection;
    FOnData: TWebSocketDataEvent;
    FOnClosed: TWebSocketClosedEvent;
    procedure SendFrameSync(const AFrame: TBytes);
    procedure PostReceive;
    procedure PostNextSend;
    procedure CompleteReceive(ATransferred, AError: DWORD);
    procedure CompleteSend(ATransferred, AError: DWORD);
    procedure NotifyClosed;
  public
    constructor Create(AEngine: TDextHttpSysEngine; AConnectionId: UInt64;
      AReqQueue: THandle; ARequestId: HTTP_REQUEST_ID;
      const ASecWebSocketKey, ASecWebSocketExtensions: string);
    destructor Destroy; override;
    
    function GetConnectionId: UInt64;
    procedure SendText(const AText: string);
    procedure SendBinary(const AData: TBytes);
    procedure SendFrame(const AFrame: TBytes);
    procedure Close(AStatusCode: Word = 1000; const AReason: string = '');
    function Receive(var ABuffer: TBytes; AOffset, ACount: Integer): Integer;
    procedure SetOnData(const AHandler: TWebSocketDataEvent);
    procedure SetOnClosed(const AHandler: TWebSocketClosedEvent);
    procedure StartReceive;
    function GetPendingSendBytes: NativeInt;
    function GetPeakPendingSendBytes: NativeInt;
    function GetRejectedSendCount: Int64;
    function IsCompressionEnabled: Boolean;
    function CompressMessage(const AData: TBytes): TBytes;
    function DecompressMessage(const AData: TBytes): TBytes;
  end;

  /// <summary>
  ///   Raw connection implementation wrapper for Windows http.sys.
  /// </summary>
  TDextHttpSysConnection = class(TInterfacedObject, IDextServerConnection)
  private
    FConnectionId: HTTP_CONNECTION_ID;
    FSecure: Boolean;
    FLocalPort: Word;
    FRemotePort: Word;
    FRemoteAddress: string;
    FReqQueue: THandle;
    FRequestId: HTTP_REQUEST_ID;
    FSecWebSocketKey: string;
    FSecWebSocketExtensions: string;
    FEngine: TDextHttpSysEngine;
  public
    /// <summary>Initializes a new http.sys connection wrapper.</summary>
    /// <param name="ARequest">The native HTTP_REQUEST structure of the connection.</param>
    constructor Create(AEngine: TDextHttpSysEngine;
      const ARequest: HTTP_REQUEST; AReqQueue: THandle);
    procedure Init(AEngine: TDextHttpSysEngine;
      const ARequest: HTTP_REQUEST; AReqQueue: THandle);
    
    /// <summary>Returns the unique connection identifier.</summary>
    function GetConnectionId: UInt64;
    /// <summary>Returns the remote client's IP address.</summary>
    function GetRemoteAddress: string;
    /// <summary>Returns the remote client's port.</summary>
    function GetRemotePort: Word;
    /// <summary>Returns the local listening port.</summary>
    function GetLocalPort: Word;
    /// <summary>Indicates if the connection is encrypted (SSL/TLS).</summary>
    function IsSecure: Boolean;
    /// <summary>Closes the connection.</summary>
    procedure Close;

    /// <summary>Checks if connection upgrade is supported.</summary>
    function SupportsUpgrade: Boolean;
    /// <summary>Upgrades the active connection to WebSockets.</summary>
    function UpgradeToWebSocket: IDextWebSocketConnection;
  end;

  /// <summary>
  ///   Worker thread for processing request queue events.
  /// </summary>
  TDextHttpSysWorker = class(TThread)
  private
    FEngine: TDextHttpSysEngine;
    FReqQueue: THandle;
    FAffinity: TDextProcessorGroupAffinity;
    FRequestCache: TDextHttpSysRequest;
    FResponseCache: TDextHttpSysResponse;
    FConnectionCache: TDextHttpSysConnection;
    procedure DispatchRequest(AContext: TDextHttpSysContext);
    procedure PostBodyReceive(AContext: TDextHttpSysContext);
  protected
    procedure Execute; override;
  public
    /// <summary>Initializes the http.sys worker thread.</summary>
    /// <param name="AEngine">The http.sys engine instance.</param>
    /// <param name="AReqQueue">Handle to the request queue.</param>
    constructor Create(AEngine: TDextHttpSysEngine; AReqQueue: THandle; const AAffinity: TDextProcessorGroupAffinity);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Native Windows kernel-mode http.sys Dext server engine.
  /// </summary>
  TDextHttpSysEngine = class(TInterfacedObject, IDextServerEngine)
  private
    FOptions: TServerEngineOptions;
    FServerSessionId: HTTP_SERVER_SESSION_ID;
    FUrlGroupId: HTTP_URL_GROUP_ID;
    FReqQueue: THandle;
    FRunning: Boolean;
    FListeningPort: Word;
    FAddress: string;
    
    FOnConnection: TConnectionEventHandler;
    FOnDisconnection: TConnectionEventHandler;
    FOnRequest: TRequestEventHandler;
    FOnUpgrade: TUpgradeEventHandler;

    FActiveConnections: Integer;
    FTotalRequests: Int64;

    FIocp: THandle;
    FContextPool: TList;
    FAllContexts: TList;
    FContextPoolLock: TSpinLock;
    FWorkers: TList;
    FBufferPool: TDextHttpSysBufferPool;
    FRequestPool: TDextHttpSysRequestPool;
    FResponsePool: TDextHttpSysResponsePool;
    procedure RegisterSslBinding;
    procedure InitializeHttpSys;
    procedure ConfigureTimeouts;
    procedure ConfigureLimits;
    procedure RecycleRequest(ARequest: TDextHttpSysRequest);
    procedure RecycleResponse(AResponse: TDextHttpSysResponse);
    function AcquireContext: TDextHttpSysContext;
    procedure ReleaseContext(AContext: TDextHttpSysContext);
    procedure PostReceiveRequest(AContext: TDextHttpSysContext);
  public
    /// <summary>Initializes a new http.sys server engine.</summary>
    /// <param name="AOptions">The engine configuration options.</param>
    constructor Create(const AOptions: TServerEngineOptions);
    /// <summary>Destroys the engine and releases resources.</summary>
    destructor Destroy; override;

    /// <summary>Binds the engine to the specified address and port.</summary>
    /// <param name="AAddress">IP address to bind to.</param>
    /// <param name="APort">Port to listen on.</param>
    procedure Bind(const AAddress: string; APort: Word);
    /// <summary>Starts the http.sys request queue listener and worker threads.</summary>
    procedure Start;
    /// <summary>Stops the engine and closes the request queue.</summary>
    /// <param name="AGracefulTimeoutMs">Timeout in milliseconds for graceful shutdown.</param>
    procedure Stop(AGracefulTimeoutMs: Integer = 5000);
    
    /// <summary>Returns the port the engine is currently listening on.</summary>
    function GetListenPort: Word;
    /// <summary>Returns the count of active client connections.</summary>
    function GetActiveConnections: Integer;
    /// <summary>Returns the total number of processed requests.</summary>
    function GetTotalRequests: Int64;

    /// <summary>Sets the connection event handler.</summary>
    procedure SetOnConnection(const AHandler: TConnectionEventHandler);
    /// <summary>Sets the disconnection event handler.</summary>
    procedure SetOnDisconnection(const AHandler: TConnectionEventHandler);
    /// <summary>Sets the request event handler.</summary>
    procedure SetOnRequest(const AHandler: TRequestEventHandler);
    /// <summary>Sets the socket upgrade event handler.</summary>
    procedure SetOnUpgrade(const AHandler: TUpgradeEventHandler);
    /// <summary>Sets the custom connection handler (unsupported for HTTP.sys).</summary>
    procedure SetConnectionHandler(const AHandler: IConnectionHandler);

    /// <summary>Static factory method for creating and registering the http.sys web host.</summary>
    class function Factory(Port: Integer; Pipeline: TRequestDelegate; Services: IServiceProvider): IWebHost; static;
    property BufferPool: TDextHttpSysBufferPool read FBufferPool;
  end;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
uses
  System.SysConst,
  Dext.WebSocket.Handshake,
  Dext.WebSocket.Protocol,
  Dext.Core.Span,
  Dext.Utils;

var
  KnownRequestHeadersMapGlobal: TDictionary<string, Integer>;
  KnownResponseHeadersMapGlobal: TDictionary<string, Integer>;

threadvar
  FLocalContextPool: TList;
  FLocalRequestPool: TList;
  FLocalResponsePool: TList;

/// <summary>Frees the calling thread's lock-free pools.</summary>
/// <remarks>
///   These are threadvars, so only the owning thread can release them, and any
///   thread that touches Acquire/Release creates them lazily. Worker threads do
///   it when their loop ends -- but so must the thread that calls Start, which
///   pre-posts the initial receives from there
///   (PostReceiveRequest(AcquireContext)) and so ends up owning a pool nobody
///   was freeing. The lists hold pointers to objects the engine owns, so
///   freeing the list is all that belongs here.
/// </remarks>
procedure ReleaseThreadLocalPools;
begin
  FreeAndNil(FLocalContextPool);
  FreeAndNil(FLocalRequestPool);
  FreeAndNil(FLocalResponsePool);
end;

{ TDextHttpSysContext }

constructor TDextHttpSysContext.Create;
begin
  inherited Create;
  FReceiveOp.Kind := hokReceiveRequest;
  FReceiveOp.Context := Self;
  FBodyOp.Kind := hokReceiveBody;
  FBodyOp.Context := Self;
  FBodyEvent := TEvent.Create(nil, False, False, '');
  SetLength(FBodyBuffer, 65536);
  FPrefetchedBody := TMemoryStream.Create;
  FBufferCapacity := 16384;
  SetLength(FBuffer, FBufferCapacity);
  FGeneration := 1;
  FRequestId := 0;
  FRequest := nil;
  FResponse := nil;
  FConnection := nil;
  FBodyBytesReceived := 0;
  FBodyError := 0;
end;

destructor TDextHttpSysContext.Destroy;
begin
  FPrefetchedBody.Free;
  FBodyEvent.Free;
  inherited;
end;

procedure TDextHttpSysContext.Reset;
begin
  Inc(FGeneration);
  if FGeneration = 0 then
    FGeneration := 1;
  FRequestId := 0;
  FRequest := nil;
  FResponse := nil;
  FResponseIntf := nil;
  FRequestIntf := nil;
  FConnection := nil;
  FillChar(FReceiveOp.Overlapped, SizeOf(TOverlapped), 0);
  FillChar(FBodyOp.Overlapped, SizeOf(TOverlapped), 0);
  FBodyEvent.ResetEvent;
  FBodyBytesReceived := 0;
  FBodyError := ERROR_SUCCESS;
  FPrefetchedBody.Size := 0;
  FPrefetchedBody.Position := 0;
end;

procedure TDextHttpSysContext.ReleaseRequestReference;
begin
  if TInterlocked.Decrement(FRefCount) = 0 then
    TDextHttpSysEngine(FRequest.FEngine).ReleaseContext(Self);
end;

procedure TDextHttpSysContext.ReleaseResponseReference;
begin
  if TInterlocked.Decrement(FRefCount) = 0 then
    TDextHttpSysEngine(FResponse.FEngine).ReleaseContext(Self);
end;

{ TDextHttpSysEngine Context helpers }

function TDextHttpSysEngine.AcquireContext: TDextHttpSysContext;
begin
  if FLocalContextPool = nil then
    FLocalContextPool := TList.Create;

  if FLocalContextPool.Count > 0 then
  begin
    Result := TDextHttpSysContext(FLocalContextPool.Last);
    FLocalContextPool.Delete(FLocalContextPool.Count - 1);
  end
  else
  begin
    FContextPoolLock.Enter;
    try
      if FContextPool.Count > 0 then
      begin
        Result := TDextHttpSysContext(FContextPool.Last);
        FContextPool.Delete(FContextPool.Count - 1);
      end
      else
      begin
        Result := TDextHttpSysContext.Create;
        FAllContexts.Add(Result);
      end;
    finally
      FContextPoolLock.Exit;
    end;
  end;
end;

procedure TDextHttpSysEngine.ReleaseContext(AContext: TDextHttpSysContext);
begin
  AContext.Reset;
  if FLocalContextPool = nil then
    FLocalContextPool := TList.Create;

  if FLocalContextPool.Count < 64 then
  begin
    FLocalContextPool.Add(AContext);
  end
  else
  begin
    FContextPoolLock.Enter;
    try
      FContextPool.Add(AContext);
    finally
      FContextPoolLock.Exit;
    end;
  end;
end;

procedure TDextHttpSysEngine.PostReceiveRequest(AContext: TDextHttpSysContext);
var
  Ret: ULONG;
  BytesReturned: ULONG;
  Request: PHTTP_REQUEST;
begin
  BytesReturned := 0;
  if AContext.FRequestId = 0 then
    AContext.Reset
  else
    FillChar(AContext.FReceiveOp.Overlapped, SizeOf(TOverlapped), 0);
  AContext.FReceiveOp.Generation := AContext.FGeneration;
  
  Ret := HttpReceiveHttpRequest(
    FReqQueue,
    AContext.FRequestId,
    HTTP_RECEIVE_REQUEST_FLAG_COPY_BODY,
    PHTTP_REQUEST(@AContext.FBuffer[0]),
    AContext.FBufferCapacity,
    BytesReturned,
    @AContext.FReceiveOp.Overlapped
  );

  if (Ret <> ERROR_SUCCESS) and (Ret <> ERROR_IO_PENDING) then
  begin
    if Ret = ERROR_MORE_DATA then
    begin
      if (FOptions.MaxRequestHeaderSize > 0) and
         (BytesReturned > Cardinal(FOptions.MaxRequestHeaderSize)) then
      begin
        ReleaseContext(AContext);
        Exit;
      end;
      Request := PHTTP_REQUEST(@AContext.FBuffer[0]);
      AContext.FRequestId := Request.RequestId;
      AContext.FBufferCapacity := BytesReturned;
      SetLength(AContext.FBuffer, AContext.FBufferCapacity);
      PostReceiveRequest(AContext);
    end
    else
      ReleaseContext(AContext);
  end;
end;

{ TDextHttpSysBufferPool }

constructor TDextHttpSysBufferPool.Create(AMaxPoolSize: Integer);
begin
  inherited Create;
  FPool := TList.Create;
  FMaxPoolSize := AMaxPoolSize;
end;

destructor TDextHttpSysBufferPool.Destroy;
var
  Item: Pointer;
begin
  FLock.Enter;
  try
    for Item in FPool do
      TMemoryStream(Item).Free;
    FPool.Free;
  finally
    FLock.Exit;
  end;
  inherited;
end;

function TDextHttpSysBufferPool.Acquire: TMemoryStream;
begin
  Result := nil;
  FLock.Enter;
  try
    if FPool.Count > 0 then
    begin
      Result := TMemoryStream(FPool.Last);
      FPool.Delete(FPool.Count - 1);
    end;
  finally
    FLock.Exit;
  end;
  if Result = nil then
  begin
    Result := TMemoryStream.Create;
    Result.Size := 65536; // Pre-allocated 64KB initial buffer
    Result.Position := 0;
  end;
end;

procedure TDextHttpSysBufferPool.Release(ABuffer: TMemoryStream);
begin
  if ABuffer = nil then Exit;
  
  FLock.Enter;
  try
    if FPool.Count < FMaxPoolSize then
    begin
      ABuffer.Position := 0;
      if ABuffer.Size > 65536 then
        ABuffer.Size := 65536;
      FPool.Add(ABuffer);
    end
    else
    begin
      ABuffer.Free;
    end;
  finally
    FLock.Exit;
  end;
end;

{ TDextHttpSysRequest }

constructor TDextHttpSysRequest.Create(ARequest: PHTTP_REQUEST);
begin
  inherited Create;
  FRequest := ARequest;
  FBodyStream := nil;
  FEntityBodyBuffer := TMemoryStream.Create;
  FEngine := nil;
  FReqQueue := 0;
  FBodyRead := False;
end;

destructor TDextHttpSysRequest.Destroy;
begin
  if Assigned(FEntityBodyBuffer) then
    FEntityBodyBuffer.Free;
  if Assigned(FBodyStream) then
    FBodyStream.Free;
  inherited;
end;

procedure TDextHttpSysRequest.Init(AEngine: TDextHttpSysEngine; ARequest: PHTTP_REQUEST;
  AContext: TDextHttpSysContext = nil);
begin
  FEngine := AEngine;
  if Assigned(AEngine) then
    FReqQueue := AEngine.FReqQueue
  else
    FReqQueue := 0;
  FRequest := ARequest;
  FContext := AContext;
  FBodyRead := False;
  if Assigned(FBodyStream) then
  begin
    FBodyStream.Size := 0;
    FBodyStream.Position := 0;
  end;
  if Assigned(FEntityBodyBuffer) then
  begin
    FEntityBodyBuffer.Size := 0;
    FEntityBodyBuffer.Position := 0;
  end;
end;

function TDextHttpSysRequest._Release: Integer;
var
  LContext: TDextHttpSysContext;
begin
  Result := TInterlocked.Decrement(FRefCount);
  if Result = 0 then
  begin
    LContext := FContext;
    if Assigned(FEngine) then
      FEngine.RecycleRequest(Self)
    else
      Destroy;
    if LContext <> nil then
      LContext.ReleaseRequestReference;
  end;
end;

function TDextHttpSysRequest.GetBodyStream: TStream;
begin
  if FContext <> nil then
  begin
    FContext.FPrefetchedBody.Position := 0;
    FBodyRead := True;
    Exit(FContext.FPrefetchedBody);
  end;

  if FBodyStream = nil then
    FBodyStream := TMemoryStream.Create;
  FBodyRead := True;
  FBodyStream.Position := 0;
  Result := FBodyStream;
end;

function TDextHttpSysRequest.GetContentLength: Int64;
var
  Header: HTTP_KNOWN_HEADER;
  P: PAnsiChar;
  i: Integer;
  Digit: Integer;
begin
  Result := 0;
  Header := FRequest.Headers.KnownHeaders[11];
  if (Header.RawValueLength = 0) or (Header.pRawValue = nil) then
    Exit;

  P := PAnsiChar(Header.pRawValue);
  for i := 0 to Header.RawValueLength - 1 do
  begin
    Digit := Ord(P[i]) - Ord('0');
    if (Digit < 0) or (Digit > 9) then
      Exit(0);
    Result := (Result * 10) + Digit;
  end;
end;

const
  HTTP_KNOWN_REQUEST_HEADERS: array[0..40] of string = (
    'Cache-Control', 'Connection', 'Date', 'Keep-Alive', 'Pragma', 'Trailer',
    'Transfer-Encoding', 'Upgrade', 'Via', 'Warning', 'Allow', 'Content-Length',
    'Content-Type', 'Content-Encoding', 'Content-Language', 'Content-Location',
    'Content-MD5', 'Content-Range', 'Expires', 'Last-Modified', 'Accept',
    'Accept-Charset', 'Accept-Encoding', 'Accept-Language', 'Authorization',
    'Cookie', 'Expect', 'From', 'Host', 'If-Match', 'If-Modified-Since',
    'If-None-Match', 'If-Range', 'If-Unmodified-Since', 'Max-Forwards',
    'Proxy-Authorization', 'Referer', 'Range', 'TE', 'Translate', 'User-Agent'
  );

  HTTP_KNOWN_RESPONSE_HEADERS: array[0..29] of string = (
    'Cache-Control', 'Connection', 'Date', 'Keep-Alive', 'Pragma', 'Trailer',
    'Transfer-Encoding', 'Upgrade', 'Via', 'Warning', 'Allow', 'Content-Length',
    'Content-Type', 'Content-Encoding', 'Content-Language', 'Content-Location',
    'Content-MD5', 'Content-Range', 'Expires', 'Last-Modified', 'Accept-Ranges',
    'Age', 'ETag', 'Location', 'Proxy-Authenticate', 'Retry-After', 'Server',
    'Set-Cookie', 'Vary', 'Www-Authenticate'
  );

function TryGetCommonKnownRequestHeaderIndex(const AName: string;
  out AIndex: Integer): Boolean;
begin
  Result := True;
  case Length(AName) of
    4:
      if AName = 'Host' then
        AIndex := 28
      else
        Result := False;
    6:
      if AName = 'Cookie' then
        AIndex := 25
      else
        Result := False;
    10:
      if AName = 'Connection' then
        AIndex := 1
      else
        Result := False;
    12:
      if AName = 'Content-Type' then
        AIndex := 12
      else
        Result := False;
    14:
      if AName = 'Content-Length' then
        AIndex := 11
      else
        Result := False;
    15:
      if AName = 'Accept-Encoding' then
        AIndex := 22
      else
        Result := False;
  else
    Result := False;
  end;
end;

function TDextHttpSysRequest.GetHeader(const AName: string): string;
var
  Index: Integer;
  I: Integer;
  UnknownName: string;
begin
  Result := '';
  // Check known headers. Common framework lookups avoid dictionary hashing.
  if TryGetCommonKnownRequestHeaderIndex(AName, Index) or
     KnownRequestHeadersMapGlobal.TryGetValue(AName, Index) then
  begin
    if FRequest.Headers.KnownHeaders[Index].RawValueLength > 0 then
    begin
      SetString(Result, PAnsiChar(FRequest.Headers.KnownHeaders[Index].pRawValue), FRequest.Headers.KnownHeaders[Index].RawValueLength);
      Exit;
    end;
  end;

  // Check unknown headers
  if (FRequest.Headers.UnknownHeaderCount > 0) and (FRequest.Headers.pUnknownHeaders <> nil) then
  begin
    for I := 0 to FRequest.Headers.UnknownHeaderCount - 1 do
    begin
      SetString(UnknownName, PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].pName), PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].NameLength);
      if SameText(UnknownName, AName) then
      begin
        SetString(Result, PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].pRawValue), PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].RawValueLength);
        Exit;
      end;
    end;
  end;
end;

procedure TDextHttpSysRequest.PopulateHeaders(ADict: TDictionary<string, string>);
var
  I: Integer;
  Val: string;
  UnknownName: string;
begin
  for I := 0 to 40 do
  begin
    if FRequest.Headers.KnownHeaders[I].RawValueLength > 0 then
    begin
      SetString(Val, PAnsiChar(FRequest.Headers.KnownHeaders[I].pRawValue), FRequest.Headers.KnownHeaders[I].RawValueLength);
      ADict.AddOrSetValue(HTTP_KNOWN_REQUEST_HEADERS[I], Val);
    end;
  end;

  if (FRequest.Headers.UnknownHeaderCount > 0) and (FRequest.Headers.pUnknownHeaders <> nil) then
  begin
    for I := 0 to FRequest.Headers.UnknownHeaderCount - 1 do
    begin
      SetString(UnknownName, PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].pName), PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].NameLength);
      SetString(Val, PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].pRawValue), PHTTP_UNKNOWN_HEADER_ARRAY(FRequest.Headers.pUnknownHeaders)^[I].RawValueLength);
      ADict.AddOrSetValue(UnknownName, Val);
    end;
  end;
end;

function TDextHttpSysRequest.GetMethod: string;
begin
  case FRequest.Verb of
    HttpVerbGET: Result := 'GET';
    HttpVerbPOST: Result := 'POST';
    HttpVerbPUT: Result := 'PUT';
    HttpVerbDELETE: Result := 'DELETE';
    HttpVerbOPTIONS: Result := 'OPTIONS';
    HttpVerbHEAD: Result := 'HEAD';
    HttpVerbTRACE: Result := 'TRACE';
    HttpVerbCONNECT: Result := 'CONNECT';
  else
    if FRequest.pUnknownVerb <> nil then
      SetString(Result, PAnsiChar(FRequest.pUnknownVerb), FRequest.UnknownVerbLength)
    else
      Result := 'GET';
  end;
end;

function TDextHttpSysRequest.GetPath: string;
begin
  if FRequest.CookedUrl.pAbsPath <> nil then
    SetString(Result, FRequest.CookedUrl.pAbsPath, FRequest.CookedUrl.AbsPathLength div SizeOf(WideChar))
  else
    Result := '/';
end;

// Forward request implementation properties
function TDextHttpSysRequest.GetQueryString: string;
begin
  if FRequest.CookedUrl.pQueryString <> nil then
    SetString(Result, FRequest.CookedUrl.pQueryString, FRequest.CookedUrl.QueryStringLength div SizeOf(WideChar))
  else
    Result := '';
end;

{ TDextHttpSysResponse }

constructor TDextHttpSysResponse.Create(AEngine: TDextHttpSysEngine; AReqQueue: THandle; ARequestId: HTTP_REQUEST_ID);
begin
  inherited Create;
  FEngine := AEngine;
  FReqQueue := AReqQueue;
  FRequestId := ARequestId;
  FHeadersSent := False;
  FResponseComplete := False;
  FStatusCode := 200;

  FReasonBuffer[0] := 'O';
  FReasonBuffer[1] := 'K';
  FReasonBuffer[2] := #0;
  FReasonLen := 2;

  FHeaderDataLen := 0;
  FillChar(FHeaderValues, SizeOf(FHeaderValues), 0);
  FUnknownHeadersCount := 0;
  FLastUnknownHeadersCount := 0;
  FillChar(FUnknownHeaders, SizeOf(FUnknownHeaders), 0);

  FResponseWriter.Init;
end;

destructor TDextHttpSysResponse.Destroy;
begin
  // Reset releases response buffers; Clear also releases the dynamically
  // grown segment table allocated by GrowSegments.
  FResponseWriter.Clear;
  inherited;
end;

procedure TDextHttpSysResponse.Init(AEngine: TDextHttpSysEngine; AReqQueue: THandle;
  ARequestId: HTTP_REQUEST_ID; AContext: TDextHttpSysContext = nil);
begin
  FEngine := AEngine;
  FReqQueue := AReqQueue;
  FRequestId := ARequestId;
  FContext := AContext;
  FHeadersSent := False;
  FResponseComplete := False;
  FStatusCode := 200;

  FReasonBuffer[0] := 'O';
  FReasonBuffer[1] := 'K';
  FReasonBuffer[2] := #0;
  FReasonLen := 2;

  FHeaderDataLen := 0;
  FillChar(FHeaderValues, SizeOf(FHeaderValues), 0);
  ResetUnknownHeaders;

  FResponseWriter.Reset;
  FResponseWriter.Init;

  FSendOp.Kind := hokSendBody;
  FSendOp.Context := AContext;
  if AContext <> nil then
    FSendOp.Generation := AContext.FGeneration;
end;

function TDextHttpSysResponse._Release: Integer;
var
  LContext: TDextHttpSysContext;
begin
  Result := TInterlocked.Decrement(FRefCount);
  if Result = 0 then
  begin
    LContext := FContext;
    if Assigned(FEngine) then
      FEngine.RecycleResponse(Self)
    else
      Destroy;
    if LContext <> nil then
      LContext.ReleaseResponseReference;
  end;
end;

procedure TDextHttpSysResponse.SetHeaderInt(AIndex: Integer; AValue: Int64);
var
  Temp: array[0..31] of AnsiChar;
  P: PAnsiChar;
  Val: Int64;
  Len: Integer;
begin
  if FHeadersSent then
    raise EInvalidOp.Create('Headers already sent');

  Val := AValue;
  P := @Temp[31];
  P^ := #0;
  Len := 0;
  if Val = 0 then
  begin
    Dec(P);
    P^ := '0';
    Inc(Len);
  end
  else
  begin
    while Val > 0 do
    begin
      Dec(P);
      P^ := AnsiChar(Ord('0') + (Val mod 10));
      Val := Val div 10;
      Inc(Len);
    end;
  end;

  if FHeaderDataLen + Len >= SizeOf(FHeaderData) then
    Exit;

  Move(P^, FHeaderData[FHeaderDataLen], Len);
  FHeaderData[FHeaderDataLen + Len] := #0;
  
  FHeaderValues[AIndex].Offset := FHeaderDataLen;
  FHeaderValues[AIndex].Length := Len;
  FHeaderDataLen := FHeaderDataLen + Len + 1;
end;

procedure TDextHttpSysResponse.Close;
var
  I: Integer;
  Seg: PDextBufferSegment;
  SegCount: Integer;
  TotalLen: Int64;
  Ret: ULONG;
  BytesSent: ULONG;
begin
  if FContext.FGeneration <> FSendOp.Generation then Exit;
  if FResponseComplete then Exit;
  FResponseComplete := True;

  // Retain context interface references to keep this response alive during async IOCP
  FContext.FResponseIntf := Self;
  FContext.FRequestIntf := FContext.FRequest;

  try
    if not FHeadersSent then
    begin
      FillChar(FNativeResponse, SizeOf(FNativeResponse), 0);
      FNativeResponse.StatusCode := FStatusCode;
      FNativeResponse.ReasonLength := FReasonLen;
      FNativeResponse.pReason := @FReasonBuffer[0];
      FNativeResponse.Version.MajorVersion := 1;
      FNativeResponse.Version.MinorVersion := 1;

      if FHeaderValues[11].Length = 0 then
      begin
        TotalLen := 0;
        Seg := FResponseWriter.Segments;
        for I := 0 to FResponseWriter.SegmentCount - 1 do
        begin
          TotalLen := TotalLen + Seg^.Length;
          Inc(Seg);
        end;
        SetHeaderInt(11, TotalLen);
      end;

      for I := 0 to 29 do
      begin
        if FHeaderValues[I].Length > 0 then
        begin
          FNativeResponse.Headers.KnownHeaders[I].pRawValue :=
            @FHeaderData[FHeaderValues[I].Offset];
          FNativeResponse.Headers.KnownHeaders[I].RawValueLength :=
            FHeaderValues[I].Length;
        end;
      end;

      if FUnknownHeadersCount > 0 then
      begin
        FNativeResponse.Headers.UnknownHeaderCount := FUnknownHeadersCount;
        FNativeResponse.Headers.pUnknownHeaders := @FUnknownHeaders[0];
      end;

      SegCount := FResponseWriter.SegmentCount;
      if SegCount > 0 then
      begin
        SetLength(FChunks, SegCount);
        Seg := FResponseWriter.Segments;
        for I := 0 to SegCount - 1 do
        begin
          FillChar(FChunks[I], SizeOf(HTTP_DATA_CHUNK), 0);
          FChunks[I].DataChunkType := hctFromMemory;
          FChunks[I].pBuffer := Seg^.Data;
          FChunks[I].BufferLength := Seg^.Length;
          Inc(Seg);
        end;

        FNativeResponse.EntityChunkCount := SegCount;
        FNativeResponse.pEntityChunks := @FChunks[0];
      end;

      FillChar(FSendOp.Overlapped, SizeOf(TOverlapped), 0);
      FSendOp.Generation := FContext.FGeneration;

      Ret := HttpSendHttpResponse(
        FReqQueue,
        FRequestId,
        0,
        @FNativeResponse,
        nil,
        BytesSent,
        nil,
        0,
        @FSendOp.Overlapped,
        nil
      );
      if (Ret <> ERROR_SUCCESS) and (Ret <> ERROR_IO_PENDING) then
        raise EOSError.Create('HttpSendHttpResponse failed with error code: ' + IntToStr(Ret));

      FHeadersSent := True;
    end
    else
    begin
      SegCount := FResponseWriter.SegmentCount;
      FillChar(FSendOp.Overlapped, SizeOf(TOverlapped), 0);
      FSendOp.Generation := FContext.FGeneration;

      if SegCount > 0 then
      begin
        SetLength(FChunks, SegCount);
        Seg := FResponseWriter.Segments;
        for I := 0 to SegCount - 1 do
        begin
          FillChar(FChunks[I], SizeOf(HTTP_DATA_CHUNK), 0);
          FChunks[I].DataChunkType := hctFromMemory;
          FChunks[I].pBuffer := Seg^.Data;
          FChunks[I].BufferLength := Seg^.Length;
          Inc(Seg);
        end;

        Ret := HttpSendResponseEntityBody(
          FReqQueue,
          FRequestId,
          0,
          SegCount,
          @FChunks[0],
          BytesSent,
          nil,
          nil,
          @FSendOp.Overlapped,
          nil
        );
      end
      else
      begin
        Ret := HttpSendResponseEntityBody(
          FReqQueue,
          FRequestId,
          0,
          0,
          nil,
          BytesSent,
          nil,
          nil,
          @FSendOp.Overlapped,
          nil
        );
      end;

      if (Ret <> ERROR_SUCCESS) and (Ret <> ERROR_IO_PENDING) then
        raise EOSError.Create('HttpSendResponseEntityBody failed with error code: ' + IntToStr(Ret));
    end;
  except
    on E: Exception do
    begin
      FContext.FResponseIntf := nil;
      FContext.FRequestIntf := nil;
      FResponseWriter.Reset;
      raise;
    end;
  end;
end;

procedure TDextHttpSysResponse.Flush;
var
  I: Integer;
  Seg: PDextBufferSegment;
  SegCount: Integer;
  Ret: ULONG;
  BytesSent: ULONG;
begin
  if FContext.FGeneration <> FSendOp.Generation then Exit;
  if FHeadersSent then Exit;

  // Retain context interface references to keep this response alive during async IOCP
  FContext.FResponseIntf := Self;
  FContext.FRequestIntf := FContext.FRequest;

  try
    FillChar(FNativeResponse, SizeOf(FNativeResponse), 0);
    FNativeResponse.StatusCode := FStatusCode;
    FNativeResponse.ReasonLength := FReasonLen;
    FNativeResponse.pReason := @FReasonBuffer[0];
    FNativeResponse.Version.MajorVersion := 1;
    FNativeResponse.Version.MinorVersion := 1;

    for I := 0 to 29 do
    begin
      if FHeaderValues[I].Length > 0 then
      begin
        FNativeResponse.Headers.KnownHeaders[I].pRawValue :=
          @FHeaderData[FHeaderValues[I].Offset];
        FNativeResponse.Headers.KnownHeaders[I].RawValueLength :=
          FHeaderValues[I].Length;
      end;
    end;

    if FUnknownHeadersCount > 0 then
    begin
      FNativeResponse.Headers.UnknownHeaderCount := FUnknownHeadersCount;
      FNativeResponse.Headers.pUnknownHeaders := @FUnknownHeaders[0];
    end;

    SegCount := FResponseWriter.SegmentCount;
    if SegCount > 0 then
    begin
      SetLength(FChunks, SegCount);
      Seg := FResponseWriter.Segments;
      for I := 0 to SegCount - 1 do
      begin
        FillChar(FChunks[I], SizeOf(HTTP_DATA_CHUNK), 0);
        FChunks[I].DataChunkType := hctFromMemory;
        FChunks[I].pBuffer := Seg^.Data;
        FChunks[I].BufferLength := Seg^.Length;
        Inc(Seg);
      end;

      FNativeResponse.EntityChunkCount := SegCount;
      FNativeResponse.pEntityChunks := @FChunks[0];
    end;

    FillChar(FSendOp.Overlapped, SizeOf(TOverlapped), 0);
    FSendOp.Generation := FContext.FGeneration;

    Ret := HttpSendHttpResponse(
      FReqQueue,
      FRequestId,
      HTTP_SEND_RESPONSE_FLAG_MORE_DATA,
      @FNativeResponse,
      nil,
      BytesSent,
      nil,
      0,
      @FSendOp.Overlapped,
      nil
    );

    if (Ret <> ERROR_SUCCESS) and (Ret <> ERROR_IO_PENDING) then
      raise EOSError.Create('HttpSendHttpResponse failed with error code: ' + IntToStr(Ret));

    FHeadersSent := True;
  except
    on E: Exception do
    begin
      FContext.FResponseIntf := nil;
      FContext.FRequestIntf := nil;
      FResponseWriter.Reset;
      raise;
    end;
  end;
end;
procedure TDextHttpSysResponse.SendHeaders;
begin
  SendHeadersInternal(False);
end;

procedure TDextHttpSysResponse.SendHeadersInternal(AMoreData: Boolean);
var
  Response: HTTP_RESPONSE;
  BytesSent: ULONG;
  Ret: ULONG;
  Flags: ULONG;
  I: Integer;
begin
  if FHeadersSent then Exit;

  FillChar(Response, SizeOf(Response), 0);
  Response.StatusCode := FStatusCode;
  Response.ReasonLength := FReasonLen;
  Response.pReason := @FReasonBuffer[0];
  Response.Version.MajorVersion := 1;
  Response.Version.MinorVersion := 1;

  for I := 0 to 29 do
  begin
    if FHeaderValues[I].Length > 0 then
    begin
      Response.Headers.KnownHeaders[I].pRawValue := @FHeaderData[FHeaderValues[I].Offset];
      Response.Headers.KnownHeaders[I].RawValueLength := FHeaderValues[I].Length;
    end;
  end;

  if FUnknownHeadersCount > 0 then
  begin
    Response.Headers.UnknownHeaderCount := FUnknownHeadersCount;
    Response.Headers.pUnknownHeaders := @FUnknownHeaders[0];
  end;

  if AMoreData then
    Flags := HTTP_SEND_RESPONSE_FLAG_MORE_DATA
  else
    Flags := 0;

  Ret := HttpSendHttpResponse(
    FReqQueue,
    FRequestId,
    Flags,
    @Response,
    nil,
    BytesSent,
    nil,
    0,
    nil,
    nil
  );

  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpSendHttpResponse failed with error code: ' + IntToStr(Ret));

  FHeadersSent := True;
end;

procedure TDextHttpSysResponse.SetHeader(const AName, AValue: string);
var
  Index: Integer;
  Written: Integer;
  WName: Integer;
begin
  if FHeadersSent then
    raise EInvalidOp.Create('Headers already sent');

  if (not SameText(AName, 'Set-Cookie')) and
     KnownResponseHeadersMapGlobal.TryGetValue(AName, Index) then
  begin
    if FHeaderDataLen + Length(AValue) * 3 + 1 >= SizeOf(FHeaderData) then
      Exit;

    Written := WideCharToMultiByte(
      CP_UTF8, 0, PChar(AValue), Length(AValue),
      @FHeaderData[FHeaderDataLen],
      SizeOf(FHeaderData) - FHeaderDataLen - 1, nil, nil
    );
    if Written > 0 then
    begin
      FHeaderData[FHeaderDataLen + Written] := #0;
      FHeaderValues[Index].Offset := FHeaderDataLen;
      FHeaderValues[Index].Length := Written;
      FHeaderDataLen := FHeaderDataLen + Written + 1;
    end;
    Exit;
  end;

  if FUnknownHeadersCount >= Length(FUnknownHeaders) then
    Exit;

  if FHeaderDataLen + (Length(AName) + Length(AValue)) * 3 + 2 >=
     SizeOf(FHeaderData) then
    Exit;

  WName := WideCharToMultiByte(
    CP_UTF8, 0, PChar(AName), Length(AName),
    @FHeaderData[FHeaderDataLen],
    SizeOf(FHeaderData) - FHeaderDataLen - 1, nil, nil
  );
  if WName <= 0 then
    Exit;

  FHeaderData[FHeaderDataLen + WName] := #0;
  FUnknownHeaders[FUnknownHeadersCount].pName := @FHeaderData[FHeaderDataLen];
  FUnknownHeaders[FUnknownHeadersCount].NameLength := WName;
  FHeaderDataLen := FHeaderDataLen + WName + 1;

  Written := WideCharToMultiByte(
    CP_UTF8, 0, PChar(AValue), Length(AValue),
    @FHeaderData[FHeaderDataLen],
    SizeOf(FHeaderData) - FHeaderDataLen - 1, nil, nil
  );
  if Written > 0 then
  begin
    FHeaderData[FHeaderDataLen + Written] := #0;
    FUnknownHeaders[FUnknownHeadersCount].pRawValue :=
      @FHeaderData[FHeaderDataLen];
    FUnknownHeaders[FUnknownHeadersCount].RawValueLength := Written;
    FHeaderDataLen := FHeaderDataLen + Written + 1;
  end
  else
  begin
    FHeaderData[FHeaderDataLen] := #0;
    FUnknownHeaders[FUnknownHeadersCount].pRawValue :=
      @FHeaderData[FHeaderDataLen];
    FUnknownHeaders[FUnknownHeadersCount].RawValueLength := 0;
    FHeaderDataLen := FHeaderDataLen + 1;
  end;

  Inc(FUnknownHeadersCount);
  if FUnknownHeadersCount > FLastUnknownHeadersCount then
    FLastUnknownHeadersCount := FUnknownHeadersCount;
end;

procedure TDextHttpSysResponse.ResetUnknownHeaders;
var
  i: Integer;
begin
  for i := 0 to FLastUnknownHeadersCount - 1 do
    FillChar(FUnknownHeaders[i], SizeOf(HTTP_UNKNOWN_HEADER), 0);
  FUnknownHeadersCount := 0;
  FLastUnknownHeadersCount := 0;
end;

procedure TDextHttpSysResponse.SetStatus(ACode: Integer; const AReason: string);
var
  ReasonStr: string;
begin
  if FHeadersSent then
    raise EInvalidOp.Create('Headers already sent');
  FStatusCode := ACode;
  if AReason <> '' then
    ReasonStr := AReason
  else
    ReasonStr := 'OK';

  FReasonLen := WideCharToMultiByte(CP_UTF8, 0, PChar(ReasonStr), Length(ReasonStr), @FReasonBuffer[0], SizeOf(FReasonBuffer) - 1, nil, nil);
  FReasonBuffer[FReasonLen] := #0;
end;

procedure TDextHttpSysResponse.Write(const ABuffer: TBytes; AOffset, ACount: Integer);
var
  Chunk: HTTP_DATA_CHUNK;
  BytesSent: ULONG;
  Ret: ULONG;
begin
  if ACount <= 0 then Exit;

  if FHeadersSent then
  begin
    FillChar(Chunk, SizeOf(Chunk), 0);
    Chunk.DataChunkType := hctFromMemory;
    Chunk.pBuffer := @ABuffer[AOffset];
    Chunk.BufferLength := ACount;

    Ret := HttpSendResponseEntityBody(
      FReqQueue,
      FRequestId,
      0,
      1,
      @Chunk,
      BytesSent,
      nil,
      nil,
      nil,
      nil
    );
    if Ret <> ERROR_SUCCESS then
      raise EOSError.Create('HttpSendResponseEntityBody failed with error code: '
        + IntToStr(Ret));
    FResponseComplete := True;
  end
  else
  begin
    FResponseWriter.Write(TByteSpan.Create(@ABuffer[AOffset], ACount));
  end;
end;

procedure TDextHttpSysResponse.WriteFile(const APath: string; AOffset, ACount: Int64);
var
  FileHandle: THandle;
  Chunk: HTTP_DATA_CHUNK_FILEHANDLE;
  Ret: ULONG;
  BytesSent: ULONG;
  Remaining: Int64;
  FileSizeVal: Int64;
begin
  FileHandle := CreateFileW(
    PWideChar(APath),
    GENERIC_READ,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    0
  );
  if FileHandle = INVALID_HANDLE_VALUE then
    raise EOSError.Create('Failed to open file: ' + APath);

  try
    Remaining := ACount;
    if Remaining <= 0 then
    begin
      if GetFileSizeEx(FileHandle, FileSizeVal) then
        Remaining := FileSizeVal - AOffset
      else
        Remaining := 0;
    end;

    if not FHeadersSent then
    begin
      if FHeaderValues[11].Length = 0 then
        SetHeaderInt(11, Remaining);
      SendHeadersInternal(True);
    end;

    FillChar(Chunk, SizeOf(Chunk), 0);
    Chunk.DataChunkType := hctFromFileHandle;
    Chunk.ByteRange.StartingOffset.QuadPart := AOffset;
    Chunk.ByteRange.Length.QuadPart := Remaining;
    Chunk.FileHandle := FileHandle;

    Ret := HttpSendResponseEntityBody(
      FReqQueue,
      FRequestId,
      HTTP_SEND_RESPONSE_FLAG_MORE_DATA,
      1,
      @Chunk,
      BytesSent,
      nil,
      nil,
      nil,
      nil
    );
    if Ret <> ERROR_SUCCESS then
      raise EOSError.Create('HttpSendResponseEntityBody (File) failed with error: ' + IntToStr(Ret));
  finally
    CloseHandle(FileHandle);
  end;
end;



{ TDextHttpSysWebSocketConnection }

constructor TDextHttpSysWebSocketConnection.Create(AEngine: TDextHttpSysEngine;
  AConnectionId: UInt64; AReqQueue: THandle; ARequestId: HTTP_REQUEST_ID;
  const ASecWebSocketKey, ASecWebSocketExtensions: string);
var
  Response: HTTP_RESPONSE;
  AcceptKey: string;
  AcceptKeyAnsi: AnsiString;
  UpgradeAnsi: AnsiString;
  ConnectionAnsi: AnsiString;
  SecWebSocketAcceptNameAnsi: AnsiString;
  SecWebSocketExtensionsNameAnsi: AnsiString;
  SecWebSocketExtensionsValueAnsi: AnsiString;
  UnknownHeaders: array[0..1] of HTTP_UNKNOWN_HEADER;
  UnknownHeaderCount: Integer;
  BytesSent: ULONG;
  Ret: ULONG;
  ReasonStrAnsi: AnsiString;
  NegotiatedExtensions: string;
begin
  inherited Create;
  FEngine := AEngine;
  FConnectionId := AConnectionId;
  FReqQueue := AReqQueue;
  FRequestId := ARequestId;
  FClosed := False;
  FClosing := False;
  FClosedNotified := False;
  FAsyncMode := False;
  FReceiveActive := False;
  FSendActive := False;
  FLock := TCriticalSection.Create;
  FCompressionEnabled := TWebSocketHandshake.TryNegotiatePermessageDeflate(
    ASecWebSocketExtensions, NegotiatedExtensions);
  FSendQueue := TCollections.CreateQueue<TBytes>;
  SetLength(FReceiveBuffer, 8 * 1024);
  FillChar(FReceiveOp, SizeOf(FReceiveOp), 0);
  FReceiveOp.Kind := hokWebSocketReceive;
  FReceiveOp.Context := Self;
  FillChar(FSendOp, SizeOf(FSendOp), 0);
  FSendOp.Kind := hokWebSocketSend;
  FSendOp.Context := Self;

  if ASecWebSocketKey <> '' then
  begin
    AcceptKey := TWebSocketHandshake.ComputeAcceptKey(ASecWebSocketKey);
    AcceptKeyAnsi := AnsiString(AcceptKey);
    UpgradeAnsi := 'websocket';
    ConnectionAnsi := 'Upgrade';
    SecWebSocketAcceptNameAnsi := 'Sec-WebSocket-Accept';
    SecWebSocketExtensionsNameAnsi := 'Sec-WebSocket-Extensions';
    SecWebSocketExtensionsValueAnsi := AnsiString(NegotiatedExtensions);
    ReasonStrAnsi := 'Switching Protocols';

    FillChar(Response, SizeOf(Response), 0);
    Response.StatusCode := 101;
    Response.ReasonLength := Length(ReasonStrAnsi);
    Response.pReason := PAnsiChar(ReasonStrAnsi);
    Response.Version.MajorVersion := 1;
    Response.Version.MinorVersion := 1;

    // Set known header 'Upgrade' (index 7)
    Response.Headers.KnownHeaders[7].pRawValue := PAnsiChar(UpgradeAnsi);
    Response.Headers.KnownHeaders[7].RawValueLength := Length(UpgradeAnsi);

    // Set known header 'Connection' (index 1)
    Response.Headers.KnownHeaders[1].pRawValue := PAnsiChar(ConnectionAnsi);
    Response.Headers.KnownHeaders[1].RawValueLength := Length(ConnectionAnsi);

    // Set unknown header 'Sec-WebSocket-Accept'
    FillChar(UnknownHeaders, SizeOf(UnknownHeaders), 0);
    UnknownHeaders[0].NameLength := Length(SecWebSocketAcceptNameAnsi);
    UnknownHeaders[0].RawValueLength := Length(AcceptKeyAnsi);
    UnknownHeaders[0].pName := PAnsiChar(SecWebSocketAcceptNameAnsi);
    UnknownHeaders[0].pRawValue := PAnsiChar(AcceptKeyAnsi);
    UnknownHeaderCount := 1;
    if FCompressionEnabled then
    begin
      UnknownHeaders[1].NameLength := Length(SecWebSocketExtensionsNameAnsi);
      UnknownHeaders[1].RawValueLength := Length(SecWebSocketExtensionsValueAnsi);
      UnknownHeaders[1].pName := PAnsiChar(SecWebSocketExtensionsNameAnsi);
      UnknownHeaders[1].pRawValue := PAnsiChar(SecWebSocketExtensionsValueAnsi);
      Inc(UnknownHeaderCount);
    end;

    Response.Headers.UnknownHeaderCount := UnknownHeaderCount;
    Response.Headers.pUnknownHeaders := @UnknownHeaders[0];

    Ret := HttpSendHttpResponse(
      FReqQueue,
      FRequestId,
      HTTP_SEND_RESPONSE_FLAG_OPAQUE,
      @Response,
      nil,
      BytesSent,
      nil,
      0,
      nil,
      nil
    );
    if Ret <> ERROR_SUCCESS then
      raise EOSError.Create('HttpSendHttpResponse (Opaque Upgrade) failed with error: ' + IntToStr(Ret));
  end;
end;

destructor TDextHttpSysWebSocketConnection.Destroy;
begin
  if not FClosed then
    Close(1000);
  FSendQueue := nil;
  FLock.Free;
  inherited;
end;

function TDextHttpSysWebSocketConnection.GetConnectionId: UInt64;
begin
  Result := FConnectionId;
end;

procedure TDextHttpSysWebSocketConnection.SendText(const AText: string);
var
  Payload: TBytes;
  FrameBytes: TBytes;
  Frame: TWebSocketFrame;
begin
  if FClosed then Exit;
  Payload := TEncoding.UTF8.GetBytes(AText);
  Frame := Default(TWebSocketFrame);
  Frame.FIN := True;
  Frame.Opcode := wsText;
  Frame.RSV1 := FCompressionEnabled;
  if Frame.RSV1 then
    Frame.Payload := CompressMessage(Payload)
  else
    Frame.Payload := Payload;
  FrameBytes := TWebSocketFrameCodec.Encode(Frame);
  SendFrame(FrameBytes);
end;

procedure TDextHttpSysWebSocketConnection.SendBinary(const AData: TBytes);
var
  Payload: TBytes;
  FrameBytes: TBytes;
  Frame: TWebSocketFrame;
begin
  Frame := Default(TWebSocketFrame);
  Frame.FIN := True;
  Frame.Opcode := wsBinary;
  Frame.RSV1 := FCompressionEnabled;
  if Frame.RSV1 then
    Payload := CompressMessage(AData)
  else
    Payload := AData;
  Frame.Payload := Payload;
  FrameBytes := TWebSocketFrameCodec.Encode(Frame);
  SendFrame(FrameBytes);
end;

function TDextHttpSysWebSocketConnection.IsCompressionEnabled: Boolean;
begin
  Result := FCompressionEnabled;
end;

function TDextHttpSysWebSocketConnection.CompressMessage(
  const AData: TBytes): TBytes;
begin
  if not FCompressionEnabled then Exit(AData);
  var Context := TWebSocketDeflatePool.Acquire;
  try
    Result := Context.Compress(AData);
  finally
    TWebSocketDeflatePool.Release(Context);
  end;
end;

function TDextHttpSysWebSocketConnection.DecompressMessage(
  const AData: TBytes): TBytes;
begin
  if not FCompressionEnabled then Exit(AData);
  var Context := TWebSocketDeflatePool.Acquire;
  try
    Result := Context.Decompress(AData);
  finally
    TWebSocketDeflatePool.Release(Context);
  end;
end;

procedure TDextHttpSysWebSocketConnection.SendFrame(const AFrame: TBytes);
const
  MAX_QUEUED_BYTES = 16 * 1024 * 1024;
var
  StartSend: Boolean;
  QueueOverflow: Boolean;
begin
  if Length(AFrame) = 0 then Exit;
  if not FAsyncMode then
  begin
    SendFrameSync(AFrame);
    Exit;
  end;

  StartSend := False;
  QueueOverflow := False;
  FLock.Enter;
  try
    if FClosed then Exit;
    if FQueuedBytes + Length(AFrame) > MAX_QUEUED_BYTES then
    begin
      FClosed := True;
      Inc(FRejectedSendCount);
      QueueOverflow := True;
    end;
    if not QueueOverflow then
    begin
      FSendQueue.Enqueue(AFrame);
      Inc(FQueuedBytes, Length(AFrame));
      if FQueuedBytes > FPeakQueuedBytes then
        FPeakQueuedBytes := FQueuedBytes;
      if not FSendActive then
      begin
        FSendActive := True;
        StartSend := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if QueueOverflow then
    NotifyClosed
  else if StartSend then
    PostNextSend;
end;

function TDextHttpSysWebSocketConnection.GetPendingSendBytes: NativeInt;
begin
  FLock.Enter;
  try
    Result := FQueuedBytes;
  finally
    FLock.Leave;
  end;
end;

function TDextHttpSysWebSocketConnection.GetPeakPendingSendBytes: NativeInt;
begin
  FLock.Enter;
  try
    Result := FPeakQueuedBytes;
  finally
    FLock.Leave;
  end;
end;

function TDextHttpSysWebSocketConnection.GetRejectedSendCount: Int64;
begin
  FLock.Enter;
  try
    Result := FRejectedSendCount;
  finally
    FLock.Leave;
  end;
end;

procedure TDextHttpSysWebSocketConnection.SendFrameSync(
  const AFrame: TBytes);
var
  Chunk: HTTP_DATA_CHUNK_INMEMORY;
  BytesSent: ULONG;
  Ret: ULONG;
begin
  if FClosed then Exit;
  if Length(AFrame) = 0 then Exit;

  FillChar(Chunk, SizeOf(Chunk), 0);
  Chunk.DataChunkType := hctFromMemory;
  Chunk.pBuffer := @AFrame[0];
  Chunk.BufferLength := Length(AFrame);

  Ret := HttpSendResponseEntityBody(
    FReqQueue,
    FRequestId,
    HTTP_SEND_RESPONSE_FLAG_MORE_DATA,
    1,
    @Chunk,
    BytesSent,
    nil,
    nil,
    nil,
    nil
  );
  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpSendResponseEntityBody failed with error: ' + IntToStr(Ret));
end;

procedure TDextHttpSysWebSocketConnection.SetOnData(
  const AHandler: TWebSocketDataEvent);
begin
  FLock.Enter;
  try
    FOnData := AHandler;
  finally
    FLock.Leave;
  end;
end;

procedure TDextHttpSysWebSocketConnection.SetOnClosed(
  const AHandler: TWebSocketClosedEvent);
begin
  FLock.Enter;
  try
    FOnClosed := AHandler;
  finally
    FLock.Leave;
  end;
end;

procedure TDextHttpSysWebSocketConnection.StartReceive;
var
  ShouldPost: Boolean;
begin
  ShouldPost := False;
  FLock.Enter;
  try
    FAsyncMode := True;
    if not FClosed and not FReceiveActive then
    begin
      FReceiveActive := True;
      ShouldPost := True;
    end;
  finally
    FLock.Leave;
  end;
  if ShouldPost then
    PostReceive;
end;

procedure TDextHttpSysWebSocketConnection.PostReceive;
var
  BytesReceived: ULONG;
  Ret: ULONG;
begin
  FillChar(FReceiveOp.Overlapped, SizeOf(TOverlapped), 0);
  FReceiveOp.Kind := hokWebSocketReceive;
  FReceiveOp.Context := Self;
  BytesReceived := 0;
  _AddRef;
  Ret := HttpReceiveRequestEntityBody(
    FReqQueue,
    FRequestId,
    0,
    @FReceiveBuffer[0],
    Length(FReceiveBuffer),
    BytesReceived,
    @FReceiveOp.Overlapped
  );
  if (Ret <> ERROR_SUCCESS) and (Ret <> ERROR_IO_PENDING) then
  begin
    FLock.Enter;
    try
      FReceiveActive := False;
    finally
      FLock.Leave;
    end;
    _Release;
    NotifyClosed;
  end;
end;

procedure TDextHttpSysWebSocketConnection.CompleteReceive(
  ATransferred, AError: DWORD);
var
  Handler: TWebSocketDataEvent;
  ContinueReceive: Boolean;
begin
  Handler := nil;
  ContinueReceive := False;
  FLock.Enter;
  try
    FReceiveActive := False;
    if not FClosed and (AError = ERROR_SUCCESS) and
       (ATransferred > 0) then
      Handler := FOnData;
  finally
    FLock.Leave;
  end;

  if (AError <> ERROR_SUCCESS) or (ATransferred = 0) then
  begin
    NotifyClosed;
    Exit;
  end;

  if Assigned(Handler) then
    Handler(FReceiveBuffer, ATransferred);

  FLock.Enter;
  try
    if not FClosed and not FClosing and not FReceiveActive then
    begin
      FReceiveActive := True;
      ContinueReceive := True;
    end;
  finally
    FLock.Leave;
  end;
  if ContinueReceive then
    PostReceive;
end;

procedure TDextHttpSysWebSocketConnection.PostNextSend;
var
  BytesSent: ULONG;
  Ret: ULONG;
  Flags: ULONG;
begin
  FLock.Enter;
  try
    if FSendQueue.Count = 0 then
    begin
      FSendActive := False;
      Exit;
    end;
    FCurrentSend := FSendQueue.Dequeue;
    Dec(FQueuedBytes, Length(FCurrentSend));
    FCurrentDisconnect := FClosing and (FSendQueue.Count = 0);
  finally
    FLock.Leave;
  end;

  FillChar(FSendChunk, SizeOf(FSendChunk), 0);
  FSendChunk.DataChunkType := hctFromMemory;
  FSendChunk.pBuffer := @FCurrentSend[0];
  FSendChunk.BufferLength := Length(FCurrentSend);
  FillChar(FSendOp.Overlapped, SizeOf(TOverlapped), 0);
  FSendOp.Kind := hokWebSocketSend;
  FSendOp.Context := Self;
  if FCurrentDisconnect then
    Flags := HTTP_SEND_RESPONSE_FLAG_DISCONNECT
  else
    Flags := HTTP_SEND_RESPONSE_FLAG_MORE_DATA;
  BytesSent := 0;
  _AddRef;
  Ret := HttpSendResponseEntityBody(
    FReqQueue,
    FRequestId,
    Flags,
    1,
    @FSendChunk,
    BytesSent,
    nil,
    nil,
    @FSendOp.Overlapped,
    nil
  );
  if (Ret <> ERROR_SUCCESS) and (Ret <> ERROR_IO_PENDING) then
  begin
    _Release;
    NotifyClosed;
  end;
end;

procedure TDextHttpSysWebSocketConnection.CompleteSend(
  ATransferred, AError: DWORD);
var
  WasDisconnect: Boolean;
  WasClosed: Boolean;
begin
  WasDisconnect := FCurrentDisconnect;
  FCurrentSend := nil;
  FLock.Enter;
  try
    WasClosed := FClosed;
  finally
    FLock.Leave;
  end;
  if (AError <> ERROR_SUCCESS) or WasDisconnect or WasClosed then
  begin
    NotifyClosed;
    Exit;
  end;
  PostNextSend;
end;

procedure TDextHttpSysWebSocketConnection.NotifyClosed;
var
  Handler: TWebSocketClosedEvent;
begin
  Handler := nil;
  FLock.Enter;
  try
    FClosed := True;
    FReceiveActive := False;
    FSendActive := False;
    FSendQueue.Clear;
    FQueuedBytes := 0;
    if not FClosedNotified then
    begin
      FClosedNotified := True;
      Handler := FOnClosed;
      FOnData := nil;
      FOnClosed := nil;
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(Handler) then
    Handler;
end;

procedure TDextHttpSysWebSocketConnection.Close(AStatusCode: Word; const AReason: string);
var
  FrameBytes: TBytes;
  Chunk: HTTP_DATA_CHUNK_INMEMORY;
  BytesSent: ULONG;
begin
  if FClosed then Exit;
  if FAsyncMode then
  begin
    FrameBytes := TWebSocketFrameCodec.EncodeClose(AStatusCode, AReason);
    FLock.Enter;
    try
      if FClosed or FClosing then Exit;
      FClosing := True;
    finally
      FLock.Leave;
    end;
    SendFrame(FrameBytes);
    Exit;
  end;
  FClosed := True;

  FrameBytes := TWebSocketFrameCodec.EncodeClose(AStatusCode, AReason);
  if Length(FrameBytes) > 0 then
  begin
    FillChar(Chunk, SizeOf(Chunk), 0);
    Chunk.DataChunkType := hctFromMemory;
    Chunk.pBuffer := @FrameBytes[0];
    Chunk.BufferLength := Length(FrameBytes);

    HttpSendResponseEntityBody(
      FReqQueue,
      FRequestId,
      HTTP_SEND_RESPONSE_FLAG_DISCONNECT,
      1,
      @Chunk,
      BytesSent,
      nil,
      nil,
      nil,
      nil
    );
  end;
end;

function TDextHttpSysWebSocketConnection.Receive(var ABuffer: TBytes; AOffset, ACount: Integer): Integer;
var
  BytesReceived: ULONG;
  Ret: ULONG;
begin
  if FClosed then Exit(0);
  
  BytesReceived := 0;
  Ret := HttpReceiveRequestEntityBody(
    FReqQueue,
    FRequestId,
    0,
    @ABuffer[AOffset],
    ACount,
    BytesReceived,
    nil
  );
  if Ret = ERROR_SUCCESS then
    Result := BytesReceived
  else if Ret = ERROR_HANDLE_EOF then
    Result := 0
  else
    Result := -1;
end;

{ TDextHttpSysConnection }

constructor TDextHttpSysConnection.Create(AEngine: TDextHttpSysEngine;
  const ARequest: HTTP_REQUEST; AReqQueue: THandle);
begin
  inherited Create;
  Init(AEngine, ARequest, AReqQueue);
end;

procedure TDextHttpSysConnection.Init(AEngine: TDextHttpSysEngine;
  const ARequest: HTTP_REQUEST; AReqQueue: THandle);
var
  I: Integer;
  UnknownName: string;
begin
  FEngine := AEngine;
  FConnectionId := ARequest.ConnectionId;
  FSecure := ARequest.pSslInfo <> nil;
  FLocalPort := 80;
  FRemotePort := 0;
  FRemoteAddress := '';
  FReqQueue := AReqQueue;
  FRequestId := ARequest.RequestId;

  FSecWebSocketKey := '';
  FSecWebSocketExtensions := '';
  if (ARequest.Headers.UnknownHeaderCount > 0) and (ARequest.Headers.pUnknownHeaders <> nil) then
  begin
    for I := 0 to ARequest.Headers.UnknownHeaderCount - 1 do
    begin
      SetString(UnknownName, PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(ARequest.Headers.pUnknownHeaders)^[I].pName), PHTTP_UNKNOWN_HEADER_ARRAY(ARequest.Headers.pUnknownHeaders)^[I].NameLength);
      if SameText(UnknownName, 'Sec-WebSocket-Key') then
      begin
        SetString(FSecWebSocketKey, PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(ARequest.Headers.pUnknownHeaders)^[I].pRawValue), PHTTP_UNKNOWN_HEADER_ARRAY(ARequest.Headers.pUnknownHeaders)^[I].RawValueLength);
      end;
      if SameText(UnknownName, 'Sec-WebSocket-Extensions') then
        SetString(FSecWebSocketExtensions,
          PAnsiChar(PHTTP_UNKNOWN_HEADER_ARRAY(ARequest.Headers.pUnknownHeaders)^[I].pRawValue),
          PHTTP_UNKNOWN_HEADER_ARRAY(ARequest.Headers.pUnknownHeaders)^[I].RawValueLength);
    end;
  end;
end;

procedure TDextHttpSysConnection.Close;
begin
  // Handled by request-level response close
end;

function TDextHttpSysConnection.GetConnectionId: UInt64;
begin
  Result := FConnectionId;
end;

function TDextHttpSysConnection.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TDextHttpSysConnection.GetRemoteAddress: string;
begin
  Result := FRemoteAddress;
end;

function TDextHttpSysConnection.GetRemotePort: Word;
begin
  Result := FRemotePort;
end;

function TDextHttpSysConnection.IsSecure: Boolean;
begin
  Result := FSecure;
end;

function TDextHttpSysConnection.SupportsUpgrade: Boolean;
begin
  Result := FSecWebSocketKey <> '';
end;

function TDextHttpSysConnection.UpgradeToWebSocket: IDextWebSocketConnection;
begin
  Result := TDextHttpSysWebSocketConnection.Create(
    FEngine, FConnectionId, FReqQueue, FRequestId, FSecWebSocketKey,
    FSecWebSocketExtensions);
end;

{ TDextHttpSysRequestPool }

constructor TDextHttpSysRequestPool.Create(AMaxPoolSize: Integer);
begin
  inherited Create;
  FPool := TList.Create;
  FMaxPoolSize := AMaxPoolSize;
end;

destructor TDextHttpSysRequestPool.Destroy;
var
  Item: Pointer;
begin
  FLock.Enter;
  try
    for Item in FPool do
    begin
      TDextHttpSysRequest(Item).FEngine := nil;
      TDextHttpSysRequest(Item).Free;
    end;
    FPool.Free;
  finally
    FLock.Exit;
  end;
  inherited;
end;

function TDextHttpSysRequestPool.Acquire(AEngine: TDextHttpSysEngine; ARequest: PHTTP_REQUEST;
  AContext: TDextHttpSysContext = nil): TDextHttpSysRequest;
begin
  Result := nil;
  FLock.Enter;
  try
    if FPool.Count > 0 then
    begin
      Result := TDextHttpSysRequest(FPool.Last);
      FPool.Delete(FPool.Count - 1);
    end;
  finally
    FLock.Exit;
  end;

  if Result = nil then
    Result := TDextHttpSysRequest.Create(ARequest);
  Result.Init(AEngine, ARequest, AContext);
end;

procedure TDextHttpSysRequestPool.Release(ARequest: TDextHttpSysRequest);
begin
  if ARequest = nil then Exit;

  FLock.Enter;
  try
    if FPool.Count < FMaxPoolSize then
    begin
      FPool.Add(ARequest);
    end
    else
    begin
      ARequest.FEngine := nil;
      ARequest.Free;
    end;
  finally
    FLock.Exit;
  end;
end;

{ TDextHttpSysResponsePool }

constructor TDextHttpSysResponsePool.Create(AMaxPoolSize: Integer);
begin
  inherited Create;
  FPool := TList.Create;
  FMaxPoolSize := AMaxPoolSize;
end;

destructor TDextHttpSysResponsePool.Destroy;
var
  Item: Pointer;
begin
  FLock.Enter;
  try
    for Item in FPool do
    begin
      TDextHttpSysResponse(Item).FEngine := nil;
      TDextHttpSysResponse(Item).Free;
    end;
    FPool.Free;
  finally
    FLock.Exit;
  end;
  inherited;
end;

function TDextHttpSysResponsePool.Acquire(AEngine: TDextHttpSysEngine; AReqQueue: THandle;
  ARequestId: HTTP_REQUEST_ID; AContext: TDextHttpSysContext = nil): TDextHttpSysResponse;
begin
  Result := nil;
  FLock.Enter;
  try
    if FPool.Count > 0 then
    begin
      Result := TDextHttpSysResponse(FPool.Last);
      FPool.Delete(FPool.Count - 1);
    end;
  finally
    FLock.Exit;
  end;

  if Result = nil then
    Result := TDextHttpSysResponse.Create(AEngine, AReqQueue, ARequestId);
  Result.Init(AEngine, AReqQueue, ARequestId, AContext);
end;

procedure TDextHttpSysResponsePool.Release(AResponse: TDextHttpSysResponse);
begin
  if AResponse = nil then Exit;

  FLock.Enter;
  try
    if FPool.Count < FMaxPoolSize then
    begin
      FPool.Add(AResponse);
    end
    else
    begin
      AResponse.FEngine := nil;
      AResponse.Free;
    end;
  finally
    FLock.Exit;
  end;
end;

{ TDextHttpSysWorker }

constructor TDextHttpSysWorker.Create(AEngine: TDextHttpSysEngine; AReqQueue: THandle; const AAffinity: TDextProcessorGroupAffinity);
begin
  inherited Create(True);
  FEngine := AEngine;
  FReqQueue := AReqQueue;
  FAffinity := AAffinity;
  FRequestCache := nil;
  FResponseCache := nil;
  FConnectionCache := nil;
  FreeOnTerminate := False;
end;


destructor TDextHttpSysWorker.Destroy;
begin
  if FRequestCache <> nil then
    FRequestCache.Free;
  if FResponseCache <> nil then
    FResponseCache.Free;
  if FConnectionCache <> nil then
    FConnectionCache.Free;
  inherited;
end;

procedure TDextHttpSysResponse.WriteBytes(AData: Pointer; ALength: Integer);
var
  Chunk: HTTP_DATA_CHUNK;
  BytesSent: ULONG;
  ResultCode: ULONG;
begin
  if ALength <= 0 then
    Exit;
  if not FHeadersSent then
  begin
    FResponseWriter.Write(TByteSpan.Create(AData, ALength));
    Exit;
  end;

  FillChar(Chunk, SizeOf(Chunk), 0);
  Chunk.DataChunkType := hctFromMemory;
  Chunk.pBuffer := AData;
  Chunk.BufferLength := ALength;
  ResultCode := HttpSendResponseEntityBody(FReqQueue, FRequestId, 0, 1,
    @Chunk, BytesSent, nil, nil, nil, nil);
  if ResultCode <> ERROR_SUCCESS then
    raise EOSError.Create('HttpSendResponseEntityBody failed with error code: '
      + IntToStr(ResultCode));
  FResponseComplete := True;
end;

procedure TDextHttpSysWorker.PostBodyReceive(AContext: TDextHttpSysContext);
var
  BytesReceived: ULONG;
  ResultCode: ULONG;
begin
  BytesReceived := 0;
  FillChar(AContext.FBodyOp.Overlapped, SizeOf(TOverlapped), 0);
  AContext.FBodyOp.Generation := AContext.FGeneration;
  ResultCode := HttpReceiveRequestEntityBody(FReqQueue, AContext.FRequestId,
    0, @AContext.FBodyBuffer[0], Length(AContext.FBodyBuffer), BytesReceived,
    @AContext.FBodyOp.Overlapped);
  if (ResultCode <> ERROR_SUCCESS) and (ResultCode <> ERROR_IO_PENDING) then
  begin
    if ResultCode = ERROR_HANDLE_EOF then
      DispatchRequest(AContext)
    else
      FEngine.ReleaseContext(AContext);
  end;
end;

procedure TDextHttpSysWorker.DispatchRequest(AContext: TDextHttpSysContext);
var
  Connection: IDextServerConnection;
  RawRequest: IDextRawRequest;
  RawResponse: IDextRawResponse;
begin
  AContext.FPrefetchedBody.Position := 0;
  AContext.FConnection := TDextHttpSysConnection.Create(
    FEngine, PHTTP_REQUEST(@AContext.FBuffer[0])^, FReqQueue);
  AContext.FRequest := FEngine.FRequestPool.Acquire(FEngine,
    PHTTP_REQUEST(@AContext.FBuffer[0]), AContext);
  AContext.FResponse := FEngine.FResponsePool.Acquire(FEngine,
    FReqQueue, AContext.FRequestId, AContext);
  AContext.FRefCount := 2;

  Connection := AContext.FConnection;
  RawRequest := AContext.FRequest;
  RawResponse := AContext.FResponse;
  try
    try
      if Assigned(FEngine.FOnRequest) then
        FEngine.FOnRequest(Connection, RawRequest, RawResponse);
    except
      on E: Exception do
        SafeWriteLn('--- EXCEPTION IN WORKER FOnRequest: ' + E.ClassName +
          ': ' + E.Message);
    end;
  finally
    try
      RawResponse.Close;
    except
      on E: Exception do
        SafeWriteLn('--- EXCEPTION IN RawResponse.Close: ' + E.ClassName +
          ': ' + E.Message);
    end;
    RawRequest := nil;
    RawResponse := nil;
    Connection := nil;
    TInterlocked.Decrement(FEngine.FActiveConnections);
  end;
end;

procedure TDextHttpSysWorker.Execute;
var
  Transferred: DWORD;
  CompletionKey: NativeUInt;
  Overlapped: POverlapped;
  Op: PDextHttpSysOperation;
  Context: TDextHttpSysContext;
  WebSocket: TDextHttpSysWebSocketConnection;
  Ret: DWORD;
  BodyChunk: PHTTP_DATA_CHUNK_INMEMORY;
  BodyChunkIndex: Integer;
begin
  ApplyGroupAffinityToThread(GetCurrentThread, FAffinity);

  try
    while not Terminated and FEngine.FRunning do
  begin
    Transferred := 0;
    CompletionKey := 0;
    Overlapped := nil;
    Ret := ERROR_SUCCESS;

    if not GetQueuedCompletionStatus(FEngine.FIocp, Transferred,
      CompletionKey, Overlapped, 1000) then
    begin
      Ret := GetLastError;
      if (Ret = WAIT_TIMEOUT) or (Overlapped = nil) then
        Continue;
    end;

    if Overlapped <> nil then
    begin
      Op := PDextHttpSysOperation(Overlapped);

      case Op^.Kind of
        hokReceiveRequest:
        begin
          Context := TDextHttpSysContext(Op^.Context);
          if Op^.Generation <> Context.FGeneration then
            Continue;
          if Ret = ERROR_MORE_DATA then
          begin
            if (FEngine.FOptions.MaxRequestHeaderSize > 0) and
               (Transferred > Cardinal(FEngine.FOptions.MaxRequestHeaderSize)) then
            begin
              FEngine.ReleaseContext(Context);
              Continue;
            end;
            Context.FRequestId := PHTTP_REQUEST(@Context.FBuffer[0]).RequestId;
            Context.FBufferCapacity := Transferred;
            SetLength(Context.FBuffer, Context.FBufferCapacity);
            FEngine.PostReceiveRequest(Context);
            Continue;
          end;
          if Ret <> ERROR_SUCCESS then
          begin
            FEngine.ReleaseContext(Context);
            Continue;
          end;

          TInterlocked.Increment(FEngine.FTotalRequests);
          TInterlocked.Increment(FEngine.FActiveConnections);

          // Post replacement receive
          FEngine.PostReceiveRequest(FEngine.AcquireContext);

          Context.FRequestId := PHTTP_REQUEST(
            @Context.FBuffer[0]).RequestId;
          Context.FPrefetchedBody.Size := 0;
          BodyChunk := PHTTP_DATA_CHUNK_INMEMORY(PHTTP_REQUEST(
            @Context.FBuffer[0]).pEntityChunks);
          for BodyChunkIndex := 0 to PHTTP_REQUEST(
            @Context.FBuffer[0]).EntityChunkCount - 1 do
          begin
            if (BodyChunk^.DataChunkType = hctFromMemory) and
               (BodyChunk^.pBuffer <> nil) and
               (BodyChunk^.BufferLength > 0) then
              Context.FPrefetchedBody.WriteBuffer(BodyChunk^.pBuffer^,
                BodyChunk^.BufferLength);
            Inc(BodyChunk);
          end;

          if (PHTTP_REQUEST(@Context.FBuffer[0]).Flags and
              HTTP_REQUEST_FLAG_MORE_ENTITY_BODY_EXISTS) <> 0 then
            PostBodyReceive(Context)
          else
            DispatchRequest(Context);
        end;

        hokReceiveBody:
        begin
          Context := TDextHttpSysContext(Op^.Context);
          if Op^.Generation <> Context.FGeneration then
            Continue;
          if Transferred > 0 then
          begin
            if (FEngine.FOptions.MaxRequestBodySize > 0) and
               (Context.FPrefetchedBody.Size + Transferred >
                FEngine.FOptions.MaxRequestBodySize) then
            begin
              TInterlocked.Decrement(FEngine.FActiveConnections);
              FEngine.ReleaseContext(Context);
              Continue;
            end;
            Context.FPrefetchedBody.WriteBuffer(Context.FBodyBuffer[0],
              Transferred);
          end;
          if (Ret = ERROR_SUCCESS) and (Transferred > 0) then
            PostBodyReceive(Context)
          else if (Ret = ERROR_SUCCESS) or (Ret = ERROR_HANDLE_EOF) then
            DispatchRequest(Context)
          else
          begin
            TInterlocked.Decrement(FEngine.FActiveConnections);
            FEngine.ReleaseContext(Context);
          end;
        end;

        hokSendHeaders, hokSendBody:
        begin
          Context := TDextHttpSysContext(Op^.Context);
          if Op^.Generation <> Context.FGeneration then
            Continue;
          if Context.FResponse <> nil then
            Context.FResponse.FResponseWriter.Reset;
          Context.FResponseIntf := nil;
          Context.FRequestIntf := nil;
        end;

        hokWebSocketReceive:
        begin
          WebSocket := TDextHttpSysWebSocketConnection(Op^.Context);
          try
            WebSocket.CompleteReceive(Transferred, Ret);
          finally
            WebSocket._Release;
          end;
        end;

        hokWebSocketSend:
        begin
          WebSocket := TDextHttpSysWebSocketConnection(Op^.Context);
          try
            WebSocket.CompleteSend(Transferred, Ret);
          finally
            WebSocket._Release;
          end;
        end;
      end;
    end;
  end;
  finally
    ReleaseThreadLocalPools;
  end;
end;

{ TDextHttpSysEngine }

constructor TDextHttpSysEngine.Create(const AOptions: TServerEngineOptions);
begin
  inherited Create;
  FOptions := AOptions;
  FServerSessionId := 0;
  FUrlGroupId := 0;
  FReqQueue := 0;
  FRunning := False;
  FIocp := 0;
  FContextPool := TList.Create;
  FAllContexts := TList.Create;
  FContextPoolLock := TSpinLock.Create(False);
  FWorkers := TList.Create;
  FBufferPool := TDextHttpSysBufferPool.Create(64);
  FRequestPool := TDextHttpSysRequestPool.Create(64);
  FResponsePool := TDextHttpSysResponsePool.Create(64);
  InitializeHttpSys;
end;

destructor TDextHttpSysEngine.Destroy;
var
  I: Integer;
begin
  //raise Exception.Create('TDextHttpSysEngine.Destroy CALLED');
  Stop;
  FWorkers.Free;
  FRequestPool.Free;
  FResponsePool.Free;
  FBufferPool.Free;
  for I := 0 to FAllContexts.Count - 1 do
    TDextHttpSysContext(FAllContexts[I]).Free;
  FAllContexts.Free;
  FContextPool.Free;
  inherited;
end;

procedure TDextHttpSysEngine.RecycleRequest(ARequest: TDextHttpSysRequest);
begin
  if Assigned(FRequestPool) then
    FRequestPool.Release(ARequest)
  else
    ARequest.Free;
end;

procedure TDextHttpSysEngine.RecycleResponse(AResponse: TDextHttpSysResponse);
begin
  if Assigned(FResponsePool) then
    FResponsePool.Release(AResponse)
  else
    AResponse.Free;
end;

procedure TDextHttpSysEngine.Bind(const AAddress: string; APort: Word);
begin
  FAddress := AAddress;
  FListeningPort := APort;
end;

procedure TDextHttpSysEngine.InitializeHttpSys;
var
  Ret: ULONG;
begin
  Ret := HttpInitialize(HTTPAPI_VERSION_2, HTTP_INITIALIZE_SERVER, nil);
  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpInitialize failed with error code: ' + IntToStr(Ret));

  Ret := HttpCreateServerSession(HTTPAPI_VERSION_2, FServerSessionId, 0);
  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpCreateServerSession failed with error code: ' + IntToStr(Ret));

  Ret := HttpCreateUrlGroup(FServerSessionId, FUrlGroupId, 0);
  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpCreateUrlGroup failed with error code: ' + IntToStr(Ret));

  Ret := HttpCreateRequestQueue(HTTPAPI_VERSION_2, nil, nil, 0, FReqQueue);
  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpCreateRequestQueue failed with error code: ' + IntToStr(Ret));

  ConfigureTimeouts;
  ConfigureLimits;
end;

procedure TDextHttpSysEngine.ConfigureLimits;
var
  Binding: HTTP_BINDING_INFO;
  Ret: ULONG;
begin
  Binding.Flags := 1;
  Binding.RequestQueueHandle := FReqQueue;

  Ret := HttpSetUrlGroupProperty(
    FUrlGroupId,
    HttpServerBindingProperty,
    @Binding,
    SizeOf(Binding)
  );

  if Ret <> ERROR_SUCCESS then
    raise EOSError.Create('HttpSetUrlGroupProperty (Binding) failed with error code: ' + IntToStr(Ret));
end;

procedure TDextHttpSysEngine.ConfigureTimeouts;
begin
  // Set configuration timeouts if specified in Options
end;

procedure TDextHttpSysEngine.RegisterSslBinding;
const
  ERROR_FILE_NOT_FOUND = 2;
  ERROR_INSUFFICIENT_BUFFER = 122;
var
  Address: SOCKADDR_IN;
  Query: HTTP_SERVICE_CONFIG_SSL_QUERY;
  Binding: PHTTP_SERVICE_CONFIG_SSL_SET;
  Buffer: TBytes;
  Required: ULONG;
  Ret: ULONG;
  ActualHash: string;
  ExpectedHash: string;
  ActualStore: string;
  I: Integer;

  function NormalizeHash(const Value: string): string;
  var
    Ch: Char;
  begin
    Result := '';
    for Ch in Value do
      if CharInSet(Ch, ['0'..'9', 'a'..'f', 'A'..'F']) then
        Result := Result + UpCase(Ch);
  end;

  function IsEmptyGuid(const Value: TGUID): Boolean;
  begin
    Result := IsEqualGUID(Value, TGUID.Empty);
  end;
begin
  if not FOptions.UseHttps then Exit;

  Ret := HttpInitialize(HTTPAPI_VERSION_2, HTTP_INITIALIZE_CONFIG, nil);
  if Ret <> ERROR_SUCCESS then
    raise EOSError.CreateFmt(
      'HttpInitialize(CONFIG) failed while validating HTTPS binding (error %d)', [Ret]);
  try
    FillChar(Address, SizeOf(Address), 0);
    Address.sin_family := AF_INET;
    Address.sin_port := htons(FListeningPort);
    if (FAddress <> '') and (FAddress <> '+') and (FAddress <> '0.0.0.0') then
    begin
      Address.sin_addr := inet_addr(PAnsiChar(AnsiString(FAddress)));
      if Address.sin_addr = INADDR_NONE then
        raise EArgumentException.CreateFmt(
          'http.sys HTTPS binding validation requires an IPv4 address; received "%s"',
          [FAddress]);
    end;

    FillChar(Query, SizeOf(Query), 0);
    Query.QueryDesc := HttpServiceConfigQueryExact;
    Query.KeyDesc.pIpPort := @Address;
    Required := 0;
    Ret := HttpQueryServiceConfiguration(0, Ord(HttpServiceConfigSslCertInfo),
      @Query, SizeOf(Query), nil, 0, Required, nil);
    if Ret = ERROR_FILE_NOT_FOUND then
      raise EInvalidOperation.CreateFmt(
        'No http.sys SSL binding exists for %s:%d. Inspect or provision it with: netsh http show sslcert ipport=%s:%d',
        [FAddress, FListeningPort, FAddress, FListeningPort]);
    if (Ret <> ERROR_INSUFFICIENT_BUFFER) or (Required = 0) then
      raise EOSError.CreateFmt(
        'Unable to query http.sys SSL binding for %s:%d (error %d)',
        [FAddress, FListeningPort, Ret]);

    SetLength(Buffer, Required);
    Ret := HttpQueryServiceConfiguration(0, Ord(HttpServiceConfigSslCertInfo),
      @Query, SizeOf(Query), Pointer(Buffer), Length(Buffer), Required, nil);
    if Ret <> ERROR_SUCCESS then
      raise EOSError.CreateFmt(
        'Unable to read http.sys SSL binding for %s:%d (error %d)',
        [FAddress, FListeningPort, Ret]);

    Binding := PHTTP_SERVICE_CONFIG_SSL_SET(Pointer(Buffer));
    ActualHash := '';
    for I := 0 to Integer(Binding.ParamDesc.CertHashLength) - 1 do
      ActualHash := ActualHash +
        IntToHex(PByte(NativeUInt(Binding.ParamDesc.pCertHash) + NativeUInt(I))^, 2);
    ExpectedHash := NormalizeHash(FOptions.SslCertHash);
    if (ExpectedHash <> '') and not SameText(ExpectedHash, ActualHash) then
      raise EInvalidOperation.CreateFmt(
        'http.sys SSL binding certificate mismatch for %s:%d. Expected %s, found %s',
        [FAddress, FListeningPort, ExpectedHash, ActualHash]);

    if Binding.ParamDesc.pCertStoreName <> nil then
      ActualStore := Binding.ParamDesc.pCertStoreName
    else
      ActualStore := '';
    if (FOptions.SslCertStoreName <> '') and
       not SameText(FOptions.SslCertStoreName, ActualStore) then
      raise EInvalidOperation.CreateFmt(
        'http.sys SSL binding store mismatch for %s:%d. Expected %s, found %s',
        [FAddress, FListeningPort, FOptions.SslCertStoreName, ActualStore]);

    if not IsEmptyGuid(FOptions.HttpSysAppId) and
       not IsEqualGUID(FOptions.HttpSysAppId, Binding.ParamDesc.AppId) then
      raise EInvalidOperation.CreateFmt(
        'http.sys SSL binding AppId mismatch for %s:%d. Expected %s, found %s',
        [FAddress, FListeningPort, GUIDToString(FOptions.HttpSysAppId),
         GUIDToString(Binding.ParamDesc.AppId)]);

    SafeWriteLn(Format(
      '[http.sys] Validated HTTPS binding %s:%d (certificate %s, store %s, AppId %s)',
      [FAddress, FListeningPort, ActualHash, ActualStore,
       GUIDToString(Binding.ParamDesc.AppId)]));
  finally
    HttpTerminate(HTTP_INITIALIZE_CONFIG, nil);
  end;
end;

procedure TDextHttpSysEngine.Start;
var
  UrlPrefix: string;
  Ret: ULONG;
  i: Integer;
  ThreadCount: Integer;
  Worker: TDextHttpSysWorker;
  Err: EOSError;
  Affinity: TDextProcessorGroupAffinity;
  Scheme: string;
  FormattedPathBase: string;
  LocalhostPrefix: string;
  LocalIpPrefix: string;

  function AddUrl(const Prefix: string): ULONG;
  var
    WidePrefix: WideString;
  begin
    WidePrefix := Prefix;
    Result := HttpAddUrlToUrlGroup(FUrlGroupId, PWideChar(WidePrefix), 0, 0);
  end;

begin
  if FRunning then Exit;

  Scheme := 'http';
  if FOptions.UseHttps then
  begin
    Scheme := 'https';
    RegisterSslBinding;
  end;

  FormattedPathBase := '';
  if FOptions.PathBase <> '' then
  begin
    FormattedPathBase := FOptions.PathBase;
    if not FormattedPathBase.StartsWith('/') then
      FormattedPathBase := '/' + FormattedPathBase;
    if FormattedPathBase.EndsWith('/') then
      FormattedPathBase := Copy(FormattedPathBase, 1,
        Length(FormattedPathBase) - 1);
  end;

  // Register prefix
  if (FAddress = '0.0.0.0') or (FAddress = '+') or (FAddress = '') then
    UrlPrefix := Format('%s://+:%d%s/', [Scheme, FListeningPort,
      FormattedPathBase])
  else
    UrlPrefix := Format('%s://%s:%d%s/', [Scheme, FAddress, FListeningPort,
      FormattedPathBase]);
    
  SafeWriteLn('[http.sys] Registering URL Prefix in Kernel: ' + UrlPrefix);
  Ret := AddUrl(UrlPrefix);

  if Ret = ERROR_SUCCESS then
    SafeWriteLn('[http.sys] URL Prefix successfully registered in Kernel: ' +
      UrlPrefix)
  else if Ret = 183 {ERROR_ALREADY_EXISTS} then
    SafeWriteLn('[http.sys] URL Prefix is already active in Kernel: ' +
      UrlPrefix);

  if (Ret = 5) and ((FAddress = '0.0.0.0') or (FAddress = '+') or
    (FAddress = '')) then
  begin
    UrlPrefix := Format('%s://127.0.0.1:%d%s/', [Scheme, FListeningPort,
      FormattedPathBase]);
    Ret := AddUrl(UrlPrefix);
    if (Ret = ERROR_SUCCESS) or (Ret = 183 {ERROR_ALREADY_EXISTS}) then
    begin
      LocalhostPrefix := Format('%s://localhost:%d%s/',
        [Scheme, FListeningPort, FormattedPathBase]);
      AddUrl(LocalhostPrefix);
    end;
  end
  else if (Ret = ERROR_SUCCESS) or (Ret = 183 {ERROR_ALREADY_EXISTS}) then
  begin
    // Garante escuta nos aliases locais caso escutando via + ou 0.0.0.0
    LocalhostPrefix := Format('%s://localhost:%d%s/',
      [Scheme, FListeningPort, FormattedPathBase]);
    AddUrl(LocalhostPrefix);
    LocalIpPrefix := Format('%s://127.0.0.1:%d%s/',
      [Scheme, FListeningPort, FormattedPathBase]);
    AddUrl(LocalIpPrefix);
  end;

  // 183 (ERROR_ALREADY_EXISTS) é tolerado pois o prefixo já se encontra registrado no Kernel
  if (Ret <> ERROR_SUCCESS) and (Ret <> 183 {ERROR_ALREADY_EXISTS}) then
  begin
    if Ret = 5 then
    begin
      Err := EOSError.Create(
        'HttpAddUrlToUrlGroup failed to register ' + UrlPrefix
        + ' (Access Denied).' + #13#10 +
        'This error occurs because registering URL prefixes on all'
        + ' interfaces (+ or 0.0.0.0) requires admin privileges.'
      );
      Err.ErrorCode := Ret;
      raise Err;
    end
    else
    begin
      Err := EOSError.Create('HttpAddUrlToUrlGroup failed to register '
        + UrlPrefix + ' with error code: ' + IntToStr(Ret));
      Err.ErrorCode := Ret;
      raise Err;
    end;
  end;

  FIocp := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  if FIocp = 0 then
    raise EOSError.Create('CreateIoCompletionPort failed');

  if CreateIoCompletionPort(FReqQueue, FIocp, 1, 0) = 0 then
    raise EOSError.Create('Failed to associate request queue with IOCP');

  FRunning := True;

  // Start Worker Threads
  ThreadCount := FOptions.IoThreadCount;
  if ThreadCount <= 0 then
    ThreadCount := GetSystemLogicalProcessorCount;

  for i := 0 to ThreadCount - 1 do
  begin
    GetProcessorGroupAffinityForWorker(i, Affinity);
    Worker := TDextHttpSysWorker.Create(Self, FReqQueue, Affinity);
    FWorkers.Add(Worker);
    Worker.Start;
  end;

  if FOptions.OutstandingReceiveDepth < 1 then
    FOptions.OutstandingReceiveDepth := 2
  else if FOptions.OutstandingReceiveDepth > 8 then
    FOptions.OutstandingReceiveDepth := 8;
  for i := 0 to (ThreadCount * FOptions.OutstandingReceiveDepth) - 1 do
    PostReceiveRequest(AcquireContext);
end;

procedure TDextHttpSysEngine.Stop(AGracefulTimeoutMs: Integer);
var
  I: Integer;
  Worker: TDextHttpSysWorker;
begin
  if not FRunning then Exit;

  FRunning := False;

  if FReqQueue <> 0 then
  begin
    HttpCloseRequestQueue(FReqQueue);
    FReqQueue := 0;
  end;

  // Stop threads
  for I := 0 to FWorkers.Count - 1 do
  begin
    Worker := TDextHttpSysWorker(FWorkers[I]);
    Worker.Terminate;
  end;

  for I := 0 to FWorkers.Count - 1 do
  begin
    Worker := TDextHttpSysWorker(FWorkers[I]);
    Worker.WaitFor;
    Worker.Free;
  end;
  FWorkers.Clear;

  if FIocp <> 0 then
  begin
    CloseHandle(FIocp);
    FIocp := 0;
  end;

  if FUrlGroupId <> 0 then
  begin
    HttpCloseUrlGroup(FUrlGroupId);
    FUrlGroupId := 0;
  end;

  if FServerSessionId <> 0 then
  begin
    HttpCloseServerSession(FServerSessionId);
    FServerSessionId := 0;
  end;

  HttpTerminate(HTTP_INITIALIZE_SERVER, nil);
  FReqQueue := 0;

  // Start pre-posted the first receives from THIS thread, which gave it a pool
  // of its own. Only this thread can free it.
  ReleaseThreadLocalPools;
end;

function TDextHttpSysEngine.GetActiveConnections: Integer;
begin
  Result := FActiveConnections;
end;

function TDextHttpSysEngine.GetListenPort: Word;
begin
  Result := FListeningPort;
end;

function TDextHttpSysEngine.GetTotalRequests: Int64;
begin
  Result := FTotalRequests;
end;

procedure TDextHttpSysEngine.SetOnConnection(const AHandler: TConnectionEventHandler);
begin
  FOnConnection := AHandler;
end;

procedure TDextHttpSysEngine.SetOnDisconnection(const AHandler: TConnectionEventHandler);
begin
  FOnDisconnection := AHandler;
end;

procedure TDextHttpSysEngine.SetOnRequest(const AHandler: TRequestEventHandler);
begin
  FOnRequest := AHandler;
end;

procedure TDextHttpSysEngine.SetOnUpgrade(const AHandler: TUpgradeEventHandler);
begin
  FOnUpgrade := AHandler;
end;

procedure TDextHttpSysEngine.SetConnectionHandler(const AHandler: IConnectionHandler);
begin
  // HTTP.sys is a kernel-mode HTTP listener and does not support raw connection handlers
end;

class function TDextHttpSysEngine.Factory(Port: Integer; Pipeline: TRequestDelegate; Services: IServiceProvider): IWebHost;
begin
  Result := nil;
end;
{$ENDIF}

procedure LoadKnownRequestHeadersMap;
{$IFDEF MSWINDOWS}
var
  i: Integer;
begin
  KnownRequestHeadersMapGlobal := TDictionary<string, Integer>.Create(True, False, 0);
  for i := 0 to 40 do
    KnownRequestHeadersMapGlobal.Add(HTTP_KNOWN_REQUEST_HEADERS[i], i);

  KnownResponseHeadersMapGlobal := TDictionary<string, Integer>.Create(True, False, 0);
  for i := 0 to 29 do
    KnownResponseHeadersMapGlobal.Add(HTTP_KNOWN_RESPONSE_HEADERS[i], i);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure UnloadKnownRequestHeadersMap;
begin
{$IFDEF MSWINDOWS}
  KnownRequestHeadersMapGlobal.Free;
  KnownResponseHeadersMapGlobal.Free;
{$ENDIF}
end;

initialization
  LoadKnownRequestHeadersMap;

finalization
  UnloadKnownRequestHeadersMap;

end.
