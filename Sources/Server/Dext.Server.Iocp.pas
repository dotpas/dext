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
{  High-performance Windows IOCP socket engine implementation.              }
{                                                                           }
{***************************************************************************}
unit Dext.Server.Iocp;

interface

{$IFDEF MSWINDOWS}
uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Defaults,
  Winapi.Windows,
  Winapi.WinSock2,
  Dext.Threading.ProcessorGroups,
  Dext.Server.Engine.Types,
  Dext.Server.Engine.Interfaces,
  Dext.Server.Iocp.HttpParser,
  Dext.Collections.Dict,
  Dext.Core.Span;


type
  TDextIocpEngine = class;

  /// <summary>
  ///   Raw connection implementation wrapper for IOCP sockets.
  /// </summary>
  /// <summary>
  ///   Raw connection implementation wrapper for IOCP sockets.
  /// </summary>
  TDextIocpConnection = class(TInterfacedObject, IDextServerConnection, IDextTransportConnection)
  private
    FConnectionId: UInt64;
    FSocket: TSocket;
    FRemoteAddress: string;
    FRemotePort: Word;
    FLocalPort: Word;
  public
    /// <summary>Initializes a new IOCP connection wrapper.</summary>
    /// <param name="ASocket">The raw socket descriptor.</param>
    /// <param name="ARemoteAddress">The client IP address.</param>
    /// <param name="ARemotePort">The client port.</param>
    /// <param name="ALocalPort">The local server listening port.</param>
    constructor Create(ASocket: TSocket; const ARemoteAddress: string; ARemotePort, ALocalPort: Word);
    procedure Init(ASocket: TSocket; const ARemoteAddress: string; ARemotePort, ALocalPort: Word);
    /// <summary>Cleans up connection resources.</summary>
    destructor Destroy; override;
    
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

    /// <summary>Sends a byte array to the client.</summary>
    procedure Send(const ABuffer: TBytes); overload;
    /// <summary>Sends a span of bytes to the client.</summary>
    procedure Send(const ASpan: TByteSpan); overload;

    /// <summary>Checks if connection upgrade is supported.</summary>
    function SupportsUpgrade: Boolean;
    /// <summary>Upgrades the active connection to WebSockets.</summary>
    function UpgradeToWebSocket: IDextWebSocketConnection;
  end;

  TDextReadOnlyBytesStream = class(TCustomMemoryStream)
  public
    constructor Create(const ABytes: TBytes; AOffset, ALen: Integer);
    procedure Init(const ABytes: TBytes; AOffset, ALen: Integer);
  end;

  /// <summary>
  ///   Raw request implementation wrapper for IOCP socket connection.
  /// </summary>
  TDextIocpRequest = class(TInterfacedObject, IDextRawRequest)
  private
    FMethod: string;
    FPath: string;
    FQuery: string;
    FBuffer: TBytes;
    FHeaderSegments: THeaderSegments;
    FResolvedHeaders: TDictionary<string, string>;
    FHeaderCacheKeys: array[0..7] of string;
    FHeaderCacheValues: array[0..7] of string;
    FHeaderCacheCount: Integer;
    FBodyStream: TCustomMemoryStream;
    FContentLength: Int64;
    function GetMethod: string;
    function GetPath: string;
    function GetQueryString: string;
    function GetHeader(const AName: string): string;
    procedure PopulateHeaders(ADict: TDictionary<string, string>);
    function GetContentLength: Int64;
    function GetBodyStream: TStream;
    function ResolveHeader(const AName: string): string;
  public
    /// <summary>Initializes the raw IOCP request wrapper.</summary>
    /// <param name="AMethod">The HTTP method.</param>
    /// <param name="APath">The request path.</param>
    /// <param name="AQuery">The raw query string.</param>
    /// <param name="AHeaderSegments">The header segments array.</param>
    /// <param name="ABody">The raw body buffer.</param>
    /// <param name="ABodyOffset">Offset in the buffer where the body starts.</param>
    /// <param name="ABodyLen">Length of the body data in the buffer.</param>
    /// <param name="AContentLength">The content length header value.</param>
    constructor Create(
      const AMethod, APath, AQuery: string;
      const AHeaderSegments: THeaderSegments;
      ABody: TBytes;
      ABodyOffset, ABodyLen: Integer;
      AContentLength: Int64
    );
    procedure Init(
      const AMethod, APath, AQuery: string;
      const AHeaderSegments: THeaderSegments;
      ABody: TBytes;
      ABodyOffset, ABodyLen: Integer;
      AContentLength: Int64
    );
    /// <summary>Cleans up request resources.</summary>
    destructor Destroy; override;
  end;

  TDextIocpSession = class;

  /// <summary>
  ///   Raw response implementation wrapper for IOCP socket connection.
  /// </summary>
  TDextIocpResponse = class(TInterfacedObject, IDextRawResponse)
  private
    FSocket: TSocket;
    FHeadersSent: Boolean;
    FFailed: Boolean;
    FStatusCode: Integer;
    FReason: string;
    FHeaders: TDictionary<string, string>;
    FHeaderBuffer: TBytes;
    FBuffer: TBytes;
    procedure InternalSend(const AData: TBytes);
  public
    /// <summary>Initializes a new IOCP response wrapper.</summary>
    /// <param name="ASocket">The raw socket descriptor.</param>
    constructor Create(ASocket: TSocket);
    procedure Init(ASocket: TSocket);
    /// <summary>Cleans up response resources.</summary>
    destructor Destroy; override;

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
  ///   Winsock Extension functions types.
  /// </summary>
  TAcceptEx = function(sListenSocket, sAcceptSocket: TSocket; lpOutputBuffer: Pointer;
    dwReceiveDataLength, dwLocalAddressLength, dwRemoteAddressLength: DWORD;
    var lpdwBytesReceived: DWORD; lpOverlapped: POverlapped): BOOL; stdcall;

  TGetAcceptExSockaddrs = procedure(lpOutputBuffer: Pointer;
    dwReceiveDataLength, dwLocalAddressLength, dwRemoteAddressLength: DWORD;
    var LocalSockaddr: PSockAddr; var LocalSockaddrLength: Integer;
    var RemoteSockaddr: PSockAddr; var RemoteSockaddrLength: Integer); stdcall;

  /// <summary>
  ///   IOCP overlapped operation key.
  /// </summary>
  TIocpOpType = (ioAccept, ioRead, ioWrite);

  PIocpOverlapped = ^TIocpOverlapped;
  TIocpOverlapped = record
    Overlapped: TOverlapped;
    OpType: TIocpOpType;
    Socket: TSocket;
    Buffer: array[0..16383] of Byte;
    BytesTransferred: DWORD;
    Connection: Pointer;
    Data: PByte;       // Heap send buffer, owned by this overlapped, freed on ioWrite
    DataLen: Integer;
  end;

  /// <summary>
  ///   Maintains per-client connection state, accumulated read buffer and async I/O.
  /// </summary>
  TDextIocpSession = class
  private
    FEngine: TDextIocpEngine;
    FSocket: TSocket;
    FRemoteAddress: string;
    FRemotePort: Word;
    FLocalPort: Word;
    FOverlapped: PIocpOverlapped;
    FAccum: TBytes;
    FConnIntf: IDextServerConnection;
    FClosed: Boolean;
  public
    constructor Create(
      AEngine: TDextIocpEngine;
      ASocket: TSocket;
      const ARemoteAddress: string;
      ARemotePort, ALocalPort: Word;
      AOverlapped: PIocpOverlapped
    );
    destructor Destroy; override;

    function PostRecv: Boolean;
    procedure CloseSession;

    property Socket: TSocket read FSocket;
    property RemoteAddress: string read FRemoteAddress;
    property RemotePort: Word read FRemotePort;
    property LocalPort: Word read FLocalPort;
    property Accum: TBytes read FAccum write FAccum;
    property ConnIntf: IDextServerConnection read FConnIntf;
    property IsClosed: Boolean read FClosed;
  end;

  /// <summary>
  ///   Worker thread running GetQueuedCompletionStatus event loop.
  /// </summary>
  TDextIocpWorker = class(TThread)
  private
    FEngine: TDextIocpEngine;
    FIocp: THandle;
    FAffinity: TDextProcessorGroupAffinity;
  protected
    procedure Execute; override;
  public
    /// <summary>Initializes a new IOCP worker thread.</summary>
    /// <param name="AEngine">The IOCP engine instance.</param>
    /// <param name="AIocp">The IOCP port handle.</param>
    constructor Create(AEngine: TDextIocpEngine; AIocp: THandle; const AAffinity: TDextProcessorGroupAffinity);
  end;

  /// <summary>
  ///   Native Windows raw IOCP socket server engine.
  /// </summary>
  TDextIocpEngine = class(TInterfacedObject, IDextServerEngine)
  private
    FOptions: TServerEngineOptions;
    FListenSocket: TSocket;
    FIocp: THandle;
    FRunning: Boolean;
    FListeningPort: Word;
    FAddress: string;
    
    FAcceptEx: TAcceptEx;
    FGetAcceptExSockaddrs: TGetAcceptExSockaddrs;

    FOnConnection: TConnectionEventHandler;
    FOnDisconnection: TConnectionEventHandler;
    FOnRequest: TRequestEventHandler;
    FOnUpgrade: TUpgradeEventHandler;
    FConnectionHandler: IConnectionHandler;

    FActiveConnections: Integer;
    FTotalRequests: Int64;

    FWorkers: TList;
    procedure LoadExtensions;
    procedure QueueAccept;
  public
    /// <summary>Initializes a new IOCP server engine.</summary>
    /// <param name="AOptions">The engine configuration options.</param>
    constructor Create(const AOptions: TServerEngineOptions);
    /// <summary>Destroys the engine and releases resources.</summary>
    destructor Destroy; override;

    /// <summary>Binds the engine to the specified address and port.</summary>
    /// <param name="AAddress">IP address to bind to.</param>
    /// <param name="APort">Port to listen on.</param>
    procedure Bind(const AAddress: string; APort: Word);
    /// <summary>Starts the IOCP listener port and worker threads loop.</summary>
    procedure Start;
    /// <summary>Stops the engine and socket listener.</summary>
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
    /// <summary>Sets the custom connection handler.</summary>
    procedure SetConnectionHandler(const AHandler: IConnectionHandler);
  end;
{$ENDIF}

implementation

{$IFDEF MSWINDOWS}
const
  // MSDN WSAID_ACCEPTEX / WSAID_GETACCEPTEXSOCKADDRS (mswsock.h)
  WSAID_ACCEPTEX: TGUID = '{b5367df1-cbac-11cf-95ca-00805f48a192}';
  WSAID_GETACCEPTEXSOCKADDRS: TGUID = '{b5367df2-cbac-11cf-95ca-00805f48a192}';
  SIO_GET_EXTENSION_FUNCTION_POINTER = $C8000006;

{ TDextIocpConnection }

constructor TDextIocpConnection.Create(ASocket: TSocket; const ARemoteAddress: string; ARemotePort, ALocalPort: Word);
begin
  inherited Create;
  Init(ASocket, ARemoteAddress, ARemotePort, ALocalPort);
end;

procedure TDextIocpConnection.Init(ASocket: TSocket; const ARemoteAddress: string; ARemotePort, ALocalPort: Word);
begin
  FSocket := ASocket;
  FRemoteAddress := ARemoteAddress;
  FRemotePort := ARemotePort;
  FLocalPort := ALocalPort;
  FConnectionId := UInt64(ASocket);
end;

destructor TDextIocpConnection.Destroy;
begin
  Close;
  inherited;
end;

procedure TDextIocpConnection.Close;
begin
  if FSocket <> INVALID_SOCKET then
  begin
    closesocket(FSocket);
    FSocket := INVALID_SOCKET;
  end;
end;

procedure TDextIocpConnection.Send(const ABuffer: TBytes);
begin
  if Length(ABuffer) > 0 then
    Winapi.WinSock2.send(FSocket, ABuffer[0], Length(ABuffer), 0);
end;

procedure TDextIocpConnection.Send(const ASpan: TByteSpan);
begin
  if ASpan.Length > 0 then
    Winapi.WinSock2.send(FSocket, ASpan.Data^, ASpan.Length, 0);
end;

function TDextIocpConnection.GetConnectionId: UInt64;
begin
  Result := FConnectionId;
end;

function TDextIocpConnection.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TDextIocpConnection.GetRemoteAddress: string;
begin
  Result := FRemoteAddress;
end;

function TDextIocpConnection.GetRemotePort: Word;
begin
  Result := FRemotePort;
end;

function TDextIocpConnection.IsSecure: Boolean;
begin
  Result := False; // Phase 1/3 does not implement SSL yet
end;

function TDextIocpConnection.SupportsUpgrade: Boolean;
begin
  Result := True;
end;

function TDextIocpConnection.UpgradeToWebSocket: IDextWebSocketConnection;
begin
  Result := nil; // WebSocket upgrade handled in S40
end;

{ TDextReadOnlyBytesStream }

constructor TDextReadOnlyBytesStream.Create(const ABytes: TBytes; AOffset, ALen: Integer);
begin
  inherited Create;
  Init(ABytes, AOffset, ALen);
end;

procedure TDextReadOnlyBytesStream.Init(const ABytes: TBytes; AOffset, ALen: Integer);
begin
  if ALen > 0 then
    SetPointer(@ABytes[AOffset], ALen)
  else
    SetPointer(nil, 0);
end;

{ TDextIocpRequest }

constructor TDextIocpRequest.Create(
  const AMethod, APath, AQuery: string;
  const AHeaderSegments: THeaderSegments;
  ABody: TBytes;
  ABodyOffset, ABodyLen: Integer;
  AContentLength: Int64
);
begin
  inherited Create;
  Init(AMethod, APath, AQuery, AHeaderSegments, ABody, ABodyOffset, ABodyLen, AContentLength);
end;

procedure TDextIocpRequest.Init(
  const AMethod, APath, AQuery: string;
  const AHeaderSegments: THeaderSegments;
  ABody: TBytes;
  ABodyOffset, ABodyLen: Integer;
  AContentLength: Int64
);
begin
  FMethod := AMethod;
  FPath := APath;
  FQuery := AQuery;
  FHeaderSegments := AHeaderSegments;
  FContentLength := AContentLength;
  FHeaderCacheCount := 0;
  FBuffer := ABody;

  if FResolvedHeaders = nil then
    FResolvedHeaders := TDictionary<string, string>.Create(True, False, 0)
  else
    FResolvedHeaders.Clear;

  if FBodyStream = nil then
    FBodyStream := TDextReadOnlyBytesStream.Create(FBuffer, ABodyOffset, ABodyLen)
  else
    TDextReadOnlyBytesStream(FBodyStream).Init(FBuffer, ABodyOffset, ABodyLen);
end;

destructor TDextIocpRequest.Destroy;
begin
  FResolvedHeaders.Free;
  FBodyStream.Free;
  inherited;
end;

function TDextIocpRequest.GetBodyStream: TStream;
begin
  Result := FBodyStream;
end;

function TDextIocpRequest.GetContentLength: Int64;
begin
  Result := FContentLength;
end;

function TDextIocpRequest.ResolveHeader(const AName: string): string;
var
  i: Integer;
  Seg: THeaderSegment;
  ValStart: Integer;
  ValLen: Integer;
begin
  for i := 0 to FHeaderCacheCount - 1 do
  begin
    if FHeaderCacheKeys[i] = AName then
    begin
      Result := FHeaderCacheValues[i];
      Exit;
    end;
  end;

  for i := 0 to FHeaderCacheCount - 1 do
  begin
    if SameText(FHeaderCacheKeys[i], AName) then
    begin
      Result := FHeaderCacheValues[i];
      Exit;
    end;
  end;

  for i := 0 to Length(FHeaderSegments) - 1 do
  begin
    Seg := FHeaderSegments[i];
    if TDextIocpHttpParser.CompareBytesCI(FBuffer, Seg.KeyStart, Seg.KeyLen, AName) then
    begin
      ValStart := Seg.ValueStart;
      ValLen := Seg.ValueLen;
      while (ValLen > 0) and ((FBuffer[ValStart] = 32) or (FBuffer[ValStart] = 9)) do
      begin
        Inc(ValStart);
        Dec(ValLen);
      end;
      while (ValLen > 0) and ((FBuffer[ValStart + ValLen - 1] = 32) or (FBuffer[ValStart + ValLen - 1] = 9)) do
        Dec(ValLen);

      Result := TEncoding.UTF8.GetString(FBuffer, ValStart, ValLen);
      if FHeaderCacheCount < Length(FHeaderCacheKeys) then
      begin
        FHeaderCacheKeys[FHeaderCacheCount] := AName;
        FHeaderCacheValues[FHeaderCacheCount] := Result;
        Inc(FHeaderCacheCount);
      end;
      Exit;
    end;
  end;

  Result := '';
  if FHeaderCacheCount < Length(FHeaderCacheKeys) then
  begin
    FHeaderCacheKeys[FHeaderCacheCount] := AName;
    FHeaderCacheValues[FHeaderCacheCount] := '';
    Inc(FHeaderCacheCount);
  end;
end;

function TDextIocpRequest.GetHeader(const AName: string): string;
begin
  Result := ResolveHeader(AName);
end;

procedure TDextIocpRequest.PopulateHeaders(ADict: TDictionary<string, string>);
var
  i: Integer;
  Seg: THeaderSegment;
  Key, Value: string;
  KeyStart, KeyLen: Integer;
  ValStart, ValLen: Integer;
begin
  for i := 0 to Length(FHeaderSegments) - 1 do
  begin
    Seg := FHeaderSegments[i];

    KeyStart := Seg.KeyStart;
    KeyLen := Seg.KeyLen;
    while (KeyLen > 0) and ((FBuffer[KeyStart] = 32) or (FBuffer[KeyStart] = 9)) do
    begin
      Inc(KeyStart);
      Dec(KeyLen);
    end;
    while (KeyLen > 0) and ((FBuffer[KeyStart + KeyLen - 1] = 32) or (FBuffer[KeyStart + KeyLen - 1] = 9)) do
      Dec(KeyLen);

    ValStart := Seg.ValueStart;
    ValLen := Seg.ValueLen;
    while (ValLen > 0) and ((FBuffer[ValStart] = 32) or (FBuffer[ValStart] = 9)) do
    begin
      Inc(ValStart);
      Dec(ValLen);
    end;
    while (ValLen > 0) and ((FBuffer[ValStart + ValLen - 1] = 32) or (FBuffer[ValStart + ValLen - 1] = 9)) do
      Dec(ValLen);

    Key := TEncoding.UTF8.GetString(FBuffer, KeyStart, KeyLen);
    Value := TEncoding.UTF8.GetString(FBuffer, ValStart, ValLen);
    ADict.AddOrSetValue(Key, Value);
  end;
end;

function TDextIocpRequest.GetMethod: string;
begin
  Result := FMethod;
end;

function TDextIocpRequest.GetPath: string;
begin
  Result := FPath;
end;

function TDextIocpRequest.GetQueryString: string;
begin
  Result := FQuery;
end;

{ TDextIocpResponse }

constructor TDextIocpResponse.Create(ASocket: TSocket);
begin
  inherited Create;
  Init(ASocket);
end;

procedure TDextIocpResponse.Init(ASocket: TSocket);
begin
  FSocket := ASocket;
  FHeadersSent := False;
  FFailed := False;
  FStatusCode := 200;
  FReason := 'OK';
  FBuffer := nil;
  FHeaderBuffer := nil;
  if FHeaders = nil then
    FHeaders := TDictionary<string, string>.Create
  else
    FHeaders.Clear;
end;

destructor TDextIocpResponse.Destroy;
begin
  FHeaders.Free;
  inherited;
end;

procedure TDextIocpResponse.InternalSend(const AData: TBytes);
var
  O: PIocpOverlapped;
  WsaBuf: TWsaBuf;
  Bytes: DWORD;
  Ret: Integer;
begin
  if FFailed or (Length(AData) = 0) then Exit;
  if FSocket = INVALID_SOCKET then
  begin
    FFailed := True;
    Exit;
  end;

  New(O);
  FillChar(O^, SizeOf(TIocpOverlapped), 0);
  GetMem(O^.Data, Length(AData));
  Move(AData[0], O^.Data^, Length(AData));
  O^.DataLen := Length(AData);
  O^.OpType := ioWrite;
  O^.Socket := FSocket;
  O^.Connection := nil;

  WsaBuf.buf := PAnsiChar(O^.Data);
  WsaBuf.len := Length(AData);
  Bytes := 0;

  {$IF CompilerVersion > 35.0}
  Ret := WSASend(FSocket, @WsaBuf, 1, @Bytes, 0, LPWSAOVERLAPPED(@O^.Overlapped), nil);
  {$ELSE}
  Ret := WSASend(FSocket, @WsaBuf, 1, Bytes, 0, LPWSAOVERLAPPED(@O^.Overlapped), nil);
  {$IFEND}

  if (Ret <> 0) and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    FreeMem(O^.Data);
    Dispose(O);
    FFailed := True;
  end;
end;

procedure TDextIocpResponse.Close;
var
  Pair: TPair<string, string>;
  BufferOffset: Integer;
  FullBuffer: TBytes;
  HeaderLen, BodyLen: Integer;

  procedure EnsureCapacity(ARequired: Integer);
  var
    NewCapacity: Integer;
  begin
    if ARequired <= Length(FHeaderBuffer) then
      Exit;
    NewCapacity := Length(FHeaderBuffer);
    if NewCapacity < 512 then
      NewCapacity := 512;
    while NewCapacity < ARequired do
      NewCapacity := NewCapacity * 2;
    SetLength(FHeaderBuffer, NewCapacity);
  end;

  procedure AppendStr(const AStr: string; var AOffset: Integer);
  var
    i: Integer;
    StrLen: Integer;
  begin
    StrLen := Length(AStr);
    if StrLen = 0 then
      Exit;
    EnsureCapacity(AOffset + StrLen);
    for i := 1 to StrLen do
    begin
      FHeaderBuffer[AOffset] := Byte(AStr[i]);
      Inc(AOffset);
    end;
  end;

begin
  Flush;
  if FFailed then Exit;

  if not FHeaders.ContainsKey('Content-Type') then
    FHeaders.Add('Content-Type', 'text/plain');
  if not FHeaders.ContainsKey('Content-Length') then
    FHeaders.AddOrSetValue('Content-Length', IntToStr(Length(FBuffer)));

  BufferOffset := 0;
  EnsureCapacity(512);
  AppendStr('HTTP/1.1 ', BufferOffset);
  AppendStr(IntToStr(FStatusCode), BufferOffset);
  AppendStr(' ', BufferOffset);
  AppendStr(FReason, BufferOffset);
  AppendStr(#13#10, BufferOffset);

  for Pair in FHeaders do
  begin
    AppendStr(Pair.Key, BufferOffset);
    AppendStr(': ', BufferOffset);
    AppendStr(Pair.Value, BufferOffset);
    AppendStr(#13#10, BufferOffset);
  end;

  AppendStr(#13#10, BufferOffset);

  HeaderLen := BufferOffset;
  BodyLen := Length(FBuffer);
  SetLength(FullBuffer, HeaderLen + BodyLen);
  if HeaderLen > 0 then
    Move(FHeaderBuffer[0], FullBuffer[0], HeaderLen);
  if BodyLen > 0 then
    Move(FBuffer[0], FullBuffer[HeaderLen], BodyLen);

  InternalSend(FullBuffer);
  FBuffer := nil;
  FHeaderBuffer := nil;
  // Connection remains open for HTTP/1.1 keep-alive
end;

procedure TDextIocpResponse.Flush;
begin
  if not FHeadersSent then
    FHeadersSent := True;
end;

procedure TDextIocpResponse.SendHeaders;
begin
  if FHeadersSent then Exit;
  FHeadersSent := True;
end;

procedure TDextIocpResponse.SetHeader(const AName, AValue: string);
begin
  if FHeadersSent then
    raise EInvalidOp.Create('Headers already sent');
  FHeaders.AddOrSetValue(AName, AValue);
end;

procedure TDextIocpResponse.SetStatus(ACode: Integer; const AReason: string);
begin
  if FHeadersSent then
    raise EInvalidOp.Create('Headers already sent');
  FStatusCode := ACode;
  if AReason <> '' then
    FReason := AReason
  else
    FReason := 'OK';
end;

procedure TDextIocpResponse.Write(const ABuffer: TBytes; AOffset, ACount: Integer);
var
  OldLen: Integer;
begin
  if (ACount <= 0) or FFailed then Exit;
  OldLen := Length(FBuffer);
  SetLength(FBuffer, OldLen + ACount);
  Move(ABuffer[AOffset], FBuffer[OldLen], ACount);
end;

procedure TDextIocpResponse.WriteFile(const APath: string; AOffset, ACount: Int64);
var
  FileStream: TFileStream;
  Remaining: Int64;
  OldLen: Integer;
begin
  if FFailed then Exit;
  FileStream := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    FileStream.Position := AOffset;
    Remaining := ACount;
    if Remaining <= 0 then
      Remaining := FileStream.Size - AOffset;
    if Remaining <= 0 then Exit;

    OldLen := Length(FBuffer);
    SetLength(FBuffer, OldLen + Remaining);
    FileStream.ReadBuffer(FBuffer[OldLen], Remaining);
  finally
    FileStream.Free;
  end;
end;

{ TDextIocpSession }

constructor TDextIocpSession.Create(
  AEngine: TDextIocpEngine;
  ASocket: TSocket;
  const ARemoteAddress: string;
  ARemotePort, ALocalPort: Word;
  AOverlapped: PIocpOverlapped
);
begin
  inherited Create;
  FEngine := AEngine;
  FSocket := ASocket;
  FRemoteAddress := ARemoteAddress;
  FRemotePort := ARemotePort;
  FLocalPort := ALocalPort;
  FOverlapped := AOverlapped;
  FOverlapped^.Connection := Self;
  FAccum := nil;
  FClosed := False;
  FConnIntf := TDextIocpConnection.Create(FSocket, FRemoteAddress, FRemotePort, FLocalPort);
end;

destructor TDextIocpSession.Destroy;
begin
  CloseSession;
  FConnIntf := nil;
  FAccum := nil;
  inherited;
end;

procedure TDextIocpSession.CloseSession;
begin
  if not FClosed then
  begin
    FClosed := True;
    if FSocket <> INVALID_SOCKET then
    begin
      closesocket(FSocket);
      FSocket := INVALID_SOCKET;
    end;
    if Assigned(FEngine) then
    begin
      TInterlocked.Decrement(FEngine.FActiveConnections);
      if Assigned(FEngine.FOnDisconnection) and Assigned(FConnIntf) then
      begin
        try
          FEngine.FOnDisconnection(FConnIntf);
        except
        end;
      end;
      if (FEngine.FOptions.MaxConnections > 0) and FEngine.FRunning then
        FEngine.QueueAccept;
    end;
  end;
end;

function TDextIocpSession.PostRecv: Boolean;
var
  WsaBuf: TWsaBuf;
  Bytes, Flags: DWORD;
  Ret: Integer;
begin
  if FClosed or (FSocket = INVALID_SOCKET) or (not FEngine.FRunning) then
  begin
    Result := False;
    Exit;
  end;

  FillChar(FOverlapped^.Overlapped, SizeOf(TOverlapped), 0);
  FOverlapped^.OpType := ioRead;
  FOverlapped^.Socket := FSocket;
  FOverlapped^.Connection := Self;

  WsaBuf.buf := PAnsiChar(@FOverlapped^.Buffer[0]);
  WsaBuf.len := SizeOf(FOverlapped^.Buffer);
  Bytes := 0;
  Flags := 0;

  Ret := WSARecv(FSocket, @WsaBuf, 1, Bytes, Flags, LPWSAOVERLAPPED(@FOverlapped^.Overlapped), nil);
  if (Ret <> 0) and (WSAGetLastError <> WSA_IO_PENDING) then
  begin
    CloseSession;
    Result := False;
  end
  else
    Result := True;
end;

{ TDextIocpWorker }

constructor TDextIocpWorker.Create(AEngine: TDextIocpEngine; AIocp: THandle; const AAffinity: TDextProcessorGroupAffinity);
begin
  inherited Create(True);
  FEngine := AEngine;
  FIocp := AIocp;
  FAffinity := AAffinity;
  FreeOnTerminate := False;
end;

procedure TDextIocpWorker.Execute;
var
  BytesTransferred: DWORD;
  CompletionKey: ULONG_PTR;
  IocpOverlapped: PIocpOverlapped;
  Ret: BOOL;
  LocalAddr, RemoteAddr: PSockAddr;
  LocalAddrLen, RemoteAddrLen: Integer;
  RemoteAddress: string;
  LocalPort, RemotePort: Word;
  Method, Path, Query: string;
  HeaderSegments: THeaderSegments;
  BodyOffset: Integer;
  ContentLength: Int64;
  ReqBodyLen: Integer;
  ConsumeLen: Integer;
  RawRequest: IDextRawRequest;
  RawResponse: IDextRawResponse;
  Session: TDextIocpSession;
  Acc: TBytes;
  OldLen: Integer;
  DataLen: Integer;
begin
  ApplyGroupAffinityToThread(GetCurrentThread, FAffinity);

  IocpOverlapped := nil;

  while not Terminated do
  begin
    BytesTransferred := 0;
    CompletionKey := 0;
    IocpOverlapped := nil;

    Ret := GetQueuedCompletionStatus(
      FIocp,
      BytesTransferred,
      CompletionKey,
      POverlapped(IocpOverlapped),
      INFINITE
    );

    if (not Ret) or (IocpOverlapped = nil) then
    begin
      if IocpOverlapped = nil then
        Break; // Sentinel sent by Stop() to terminate thread

      case IocpOverlapped.OpType of
        ioAccept:
        begin
          if IocpOverlapped.Socket <> INVALID_SOCKET then
            closesocket(IocpOverlapped.Socket);
          Dispose(IocpOverlapped);
        end;
        ioWrite:
        begin
          if Assigned(IocpOverlapped.Data) then
          begin
            FreeMem(IocpOverlapped.Data);
            IocpOverlapped.Data := nil;
          end;
          Dispose(IocpOverlapped);
        end;
        ioRead:
        begin
          Session := TDextIocpSession(IocpOverlapped.Connection);
          if Session <> nil then
          begin
            Session.CloseSession;
            Session.Free;
          end;
          Dispose(IocpOverlapped);
        end;
      end;
      Continue;
    end;

    case IocpOverlapped.OpType of
      ioAccept:
      begin
        if not FEngine.FRunning then
        begin
          closesocket(IocpOverlapped.Socket);
          Dispose(IocpOverlapped);
          Continue;
        end;

        // Process new client socket accepted
        // Load local/remote address info
        FEngine.FGetAcceptExSockaddrs(
          @IocpOverlapped.Buffer[0],
          0,
          SizeOf(TSockAddrIn) + 16,
          SizeOf(TSockAddrIn) + 16,
          LocalAddr,
          LocalAddrLen,
          RemoteAddr,
          RemoteAddrLen
        );

        RemoteAddress := string(AnsiString(inet_ntoa(PSockAddrIn(RemoteAddr).sin_addr)));
        RemotePort := ntohs(PSockAddrIn(RemoteAddr).sin_port);
        LocalPort := ntohs(PSockAddrIn(LocalAddr).sin_port);

        // Associate accepted client socket with IOCP port
        if CreateIoCompletionPort(IocpOverlapped.Socket, FIocp, 0, 0) = 0 then
        begin
          closesocket(IocpOverlapped.Socket);
          Dispose(IocpOverlapped);
          FEngine.QueueAccept;
          Continue;
        end;

        TInterlocked.Increment(FEngine.FActiveConnections);

        // Replenish the accept pool immediately
        FEngine.QueueAccept;

        Session := TDextIocpSession.Create(
          FEngine,
          IocpOverlapped.Socket,
          RemoteAddress,
          RemotePort,
          LocalPort,
          IocpOverlapped
        );

        if Assigned(FEngine.FOnConnection) then
        begin
          try
            FEngine.FOnConnection(Session.ConnIntf);
          except
          end;
        end;

        if not Session.PostRecv then
        begin
          Session.Free;
          Dispose(IocpOverlapped);
        end;
      end;

      ioRead:
      begin
        Session := TDextIocpSession(IocpOverlapped.Connection);
        if Session = nil then
        begin
          Dispose(IocpOverlapped);
          Continue;
        end;

        if BytesTransferred = 0 then
        begin
          // Graceful peer close
          Session.CloseSession;
          Session.Free;
          Dispose(IocpOverlapped);
          Continue;
        end;

        DataLen := Integer(BytesTransferred);
        Acc := Session.Accum;
        OldLen := Length(Acc);
        SetLength(Acc, OldLen + DataLen);
        Move(IocpOverlapped.Buffer[0], Acc[OldLen], DataLen);
        Session.Accum := Acc;

        if Assigned(FEngine.FConnectionHandler) then
        begin
          try
            FEngine.FConnectionHandler.OnData(
              Session.ConnIntf as IDextTransportConnection,
              TByteSpan.Create(@IocpOverlapped.Buffer[0], DataLen)
            );
          except
            on E: Exception do
              FEngine.FConnectionHandler.OnError(Session.ConnIntf as IDextTransportConnection, E);
          end;
        end
        else
        begin
          // HTTP handling loop for pipelining or partial requests
          while (Session.Accum <> nil) and (Length(Session.Accum) > 0) do
          begin
            if not TDextIocpHttpParser.TryParseRequest(
              Session.Accum,
              Length(Session.Accum),
              Method,
              Path,
              Query,
              HeaderSegments,
              BodyOffset,
              ContentLength
            ) then
              Break; // Need more data to complete HTTP headers

            if (ContentLength > 0) and ((Length(Session.Accum) - BodyOffset) < ContentLength) then
              Break; // Need more data for request body

            ReqBodyLen := Length(Session.Accum) - BodyOffset;
            if (ContentLength >= 0) and (ReqBodyLen > ContentLength) then
              ReqBodyLen := ContentLength;

            TInterlocked.Increment(FEngine.FTotalRequests);

            RawRequest := TDextIocpRequest.Create(
              Method, Path, Query, HeaderSegments,
              Session.Accum, BodyOffset, ReqBodyLen, ContentLength
            );
            RawResponse := TDextIocpResponse.Create(Session.Socket);
            try
              if Assigned(FEngine.FOnRequest) then
                FEngine.FOnRequest(Session.ConnIntf, RawRequest, RawResponse);
            finally
              RawResponse.Close;
              RawResponse := nil;
              RawRequest := nil;
            end;

            ConsumeLen := BodyOffset;
            if ContentLength > 0 then
              Inc(ConsumeLen, Integer(ContentLength));

            if ConsumeLen >= Length(Session.Accum) then
            begin
              Session.Accum := nil;
              Break;
            end
            else
            begin
              Session.Accum := Copy(Session.Accum, ConsumeLen, Length(Session.Accum) - ConsumeLen);
            end;
          end;
        end;

        // Keep-alive: post next async read on this connection
        if not Session.PostRecv then
        begin
          Session.Free;
          Dispose(IocpOverlapped);
        end;
      end;

      ioWrite:
      begin
        if Assigned(IocpOverlapped.Data) then
        begin
          FreeMem(IocpOverlapped.Data);
          IocpOverlapped.Data := nil;
        end;
        Dispose(IocpOverlapped);
        Continue;
      end;
    end;
  end;
end;

{ TDextIocpEngine }

constructor TDextIocpEngine.Create(const AOptions: TServerEngineOptions);
var
  WsaData: TWsaData;
begin
  inherited Create;
  FOptions := AOptions;
  FListenSocket := INVALID_SOCKET;
  FIocp := 0;
  FRunning := False;
  FWorkers := TList.Create;
  
  if WSAStartup($0202, WsaData) <> 0 then
    raise EOSError.Create('WSAStartup failed');
end;

destructor TDextIocpEngine.Destroy;
begin
  Stop;
  FWorkers.Free;
  WSACleanup;
  inherited;
end;

procedure TDextIocpEngine.Bind(const AAddress: string; APort: Word);
begin
  FAddress := AAddress;
  FListeningPort := APort;
end;

procedure TDextIocpEngine.LoadExtensions;
var
  Socket: TSocket;
  Bytes: DWORD;
  GuidAcceptEx: TGUID;
  GuidGetSockAddrs: TGUID;
  PtrAcceptEx: Pointer;
  PtrGetSockAddrs: Pointer;
begin
  Socket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  if Socket = INVALID_SOCKET then
    raise EOSError.Create('Failed to create temporary socket: ' + IntToStr(WSAGetLastError));

  try
    GuidAcceptEx := WSAID_ACCEPTEX;
    PtrAcceptEx := nil;
    if WSAIoctl(Socket, SIO_GET_EXTENSION_FUNCTION_POINTER, @GuidAcceptEx,
      SizeOf(GuidAcceptEx), @PtrAcceptEx, SizeOf(PtrAcceptEx), Bytes, nil, nil) <> 0 then
      raise EOSError.Create('WSAIoctl(WSAID_ACCEPTEX) failed with error code: ' +
        IntToStr(WSAGetLastError));

    GuidGetSockAddrs := WSAID_GETACCEPTEXSOCKADDRS;
    PtrGetSockAddrs := nil;
    if WSAIoctl(Socket, SIO_GET_EXTENSION_FUNCTION_POINTER, @GuidGetSockAddrs,
      SizeOf(GuidGetSockAddrs), @PtrGetSockAddrs, SizeOf(PtrGetSockAddrs), Bytes, nil, nil) <> 0 then
      raise EOSError.Create('WSAIoctl(WSAID_GETACCEPTEXSOCKADDRS) failed with error code: ' +
        IntToStr(WSAGetLastError));

    FAcceptEx := TAcceptEx(PtrAcceptEx);
    FGetAcceptExSockaddrs := TGetAcceptExSockaddrs(PtrGetSockAddrs);
  finally
    closesocket(Socket);
  end;

  if not Assigned(FAcceptEx) or not Assigned(FGetAcceptExSockaddrs) then
    raise EOSError.Create('Failed to load AcceptEx extension function pointers');
end;

procedure TDextIocpEngine.QueueAccept;
var
  AcceptSocket: TSocket;
  Overlapped: PIocpOverlapped;
  BytesReceived: DWORD;
  Ret: BOOL;
  Attempt: Integer;
begin
  if not FRunning then Exit;

  // Backpressure check against MaxConnections option
  if (FOptions.MaxConnections > 0) and (FActiveConnections >= FOptions.MaxConnections) then
    Exit;

  for Attempt := 1 to 50 do
  begin
    if not FRunning then Exit;

    AcceptSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
    if AcceptSocket = INVALID_SOCKET then
    begin
      Sleep(1);
      Continue;
    end;

    New(Overlapped);
    FillChar(Overlapped^, SizeOf(TIocpOverlapped), 0);
    Overlapped.OpType := ioAccept;
    Overlapped.Socket := AcceptSocket;

    Ret := FAcceptEx(
      FListenSocket,
      AcceptSocket,
      @Overlapped.Buffer[0],
      0,
      SizeOf(TSockAddrIn) + 16,
      SizeOf(TSockAddrIn) + 16,
      BytesReceived,
      POverlapped(Overlapped)
    );

    if Ret or (WSAGetLastError = WSA_IO_PENDING) then
      Exit;

    Dispose(Overlapped);
    closesocket(AcceptSocket);
    Sleep(1);
  end;
end;

procedure TDextIocpEngine.Start;
var
  Addr: TSockAddrIn;
  i: Integer;
  ThreadCount: Integer;
  InitialAccepts: Integer;
  Worker: TDextIocpWorker;
  Affinity: TDextProcessorGroupAffinity;
begin
  if FRunning then Exit;

  LoadExtensions;

  FIocp := CreateIoCompletionPort(INVALID_HANDLE_VALUE, 0, 0, 0);
  if FIocp = 0 then
    raise EOSError.Create('Failed to create completion port');

  FListenSocket := WSASocket(AF_INET, SOCK_STREAM, IPPROTO_TCP, nil, 0, WSA_FLAG_OVERLAPPED);
  if FListenSocket = INVALID_SOCKET then
    raise EOSError.Create('Failed to create listen socket');

  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(FListeningPort);
  if (FAddress = '') or (FAddress = '0.0.0.0') then
    Addr.sin_addr.S_addr := INADDR_ANY
  else if SameText(FAddress, 'localhost') or (FAddress = '127.0.0.1') then
    Addr.sin_addr.S_addr := inet_addr('127.0.0.1')
  else
    Addr.sin_addr.S_addr := inet_addr(PAnsiChar(AnsiString(FAddress)));

  if Winapi.WinSock2.bind(FListenSocket, PSockAddr(@Addr)^, SizeOf(Addr)) = SOCKET_ERROR then
    raise EOSError.Create('Socket bind failed');

  if listen(FListenSocket, SOMAXCONN) = SOCKET_ERROR then
    raise EOSError.Create('Socket listen failed');

  // Associate listen socket with IOCP
  CreateIoCompletionPort(FListenSocket, FIocp, 0, 0);

  FRunning := True;

  // Queue initial accept operations
  InitialAccepts := 1024;
  if (FOptions.MaxConnections > 0) and (InitialAccepts > FOptions.MaxConnections) then
    InitialAccepts := FOptions.MaxConnections;

  for i := 1 to InitialAccepts do
    QueueAccept;

  // Start Worker Threads
  ThreadCount := FOptions.IoThreadCount;
  if ThreadCount <= 0 then
    ThreadCount := GetSystemLogicalProcessorCount;

  for i := 0 to ThreadCount - 1 do
  begin
    GetProcessorGroupAffinityForWorker(i, Affinity);
    Worker := TDextIocpWorker.Create(Self, FIocp, Affinity);
    FWorkers.Add(Worker);
    Worker.Start;
  end;
end;

procedure TDextIocpEngine.Stop(AGracefulTimeoutMs: Integer);
var
  I: Integer;
  Worker: TDextIocpWorker;
  BytesTransferred: DWORD;
  CompletionKey: ULONG_PTR;
  IocpOverlapped: PIocpOverlapped;
begin
  if not FRunning then Exit;

  FRunning := False;

  if FListenSocket <> INVALID_SOCKET then
  begin
    closesocket(FListenSocket);
    FListenSocket := INVALID_SOCKET;
  end;

  // Signal termination to all workers
  for I := 0 to FWorkers.Count - 1 do
  begin
    Worker := TDextIocpWorker(FWorkers[I]);
    Worker.Terminate;
  end;

  if FIocp <> 0 then
  begin
    // Post sentinels to wake up and terminate all worker threads
    for I := 0 to FWorkers.Count - 1 do
      PostQueuedCompletionStatus(FIocp, 0, 0, nil);
  end;

  for I := 0 to FWorkers.Count - 1 do
  begin
    Worker := TDextIocpWorker(FWorkers[I]);
    Worker.WaitFor;
    Worker.Free;
  end;
  FWorkers.Clear;

  if FIocp <> 0 then
  begin
    // Drain any remaining completions in the port (such as cancelled AcceptEx requests)
    repeat
      BytesTransferred := 0;
      CompletionKey := 0;
      IocpOverlapped := nil;
      GetQueuedCompletionStatus(FIocp, BytesTransferred, CompletionKey, POverlapped(IocpOverlapped), 0);
      if IocpOverlapped <> nil then
      begin
        case IocpOverlapped.OpType of
          ioAccept:
          begin
            if IocpOverlapped.Socket <> INVALID_SOCKET then
              closesocket(IocpOverlapped.Socket);
            Dispose(IocpOverlapped);
          end;
          ioWrite:
          begin
            if Assigned(IocpOverlapped.Data) then
              FreeMem(IocpOverlapped.Data);
            Dispose(IocpOverlapped);
          end;
          ioRead:
          begin
            Dispose(IocpOverlapped);
          end;
        end;
      end;
    until IocpOverlapped = nil;

    CloseHandle(FIocp);
    FIocp := 0;
  end;
end;

function TDextIocpEngine.GetActiveConnections: Integer;
begin
  Result := FActiveConnections;
end;

function TDextIocpEngine.GetListenPort: Word;
begin
  Result := FListeningPort;
end;

function TDextIocpEngine.GetTotalRequests: Int64;
begin
  Result := FTotalRequests;
end;

procedure TDextIocpEngine.SetOnConnection(const AHandler: TConnectionEventHandler);
begin
  FOnConnection := AHandler;
end;

procedure TDextIocpEngine.SetOnDisconnection(const AHandler: TConnectionEventHandler);
begin
  FOnDisconnection := AHandler;
end;

procedure TDextIocpEngine.SetOnRequest(const AHandler: TRequestEventHandler);
begin
  FOnRequest := AHandler;
end;

procedure TDextIocpEngine.SetOnUpgrade(const AHandler: TUpgradeEventHandler);
begin
  FOnUpgrade := AHandler;
end;

procedure TDextIocpEngine.SetConnectionHandler(const AHandler: IConnectionHandler);
begin
  FConnectionHandler := AHandler;
end;

{$ENDIF}

end.
