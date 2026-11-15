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
{  Core native server engine interfaces and factory methods.                }
{                                                                           }
{***************************************************************************}
unit Dext.Server.Engine.Interfaces;

interface

uses
  System.Classes,
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.Comparers,
  Dext.Collections.Dict,
  Dext.Server.Engine.Types,
  Dext.Core.Span;

type
  IDextServerConnection = interface;
  IDextRawRequest = interface;
  IDextRawResponse = interface;
  IDextWebSocketConnection = interface;
  IDextTransportConnection = interface;
  IConnectionHandler = interface;

  /// <summary>Event raised when a connection is established or closed.</summary>
  TConnectionEventHandler = reference to procedure(const AConnection: IDextServerConnection);

  /// <summary>Event raised when a complete raw HTTP request is received.</summary>
  TRequestEventHandler = reference to procedure(const AConnection: IDextServerConnection;
    const ARequest: IDextRawRequest; const AResponse: IDextRawResponse);

  /// <summary>Event raised to evaluate if a connection upgrade to WebSockets is accepted.</summary>
  TUpgradeEventHandler = reference to procedure(const AConnection: IDextServerConnection;
    var AAccepted: Boolean);
  TWebSocketDataEvent = reference to procedure(const ABuffer: TBytes;
    ACount: Integer);
  TWebSocketClosedEvent = reference to procedure;

  IDextTransportConnection = interface
    ['{C3F54B78-C392-4AEB-B410-6C2A9B890F12}']
    function GetConnectionId: UInt64;
    function GetRemoteAddress: string;
    function GetRemotePort: Word;
    procedure Send(const ABuffer: TBytes); overload;
    procedure Send(const ASpan: TByteSpan); overload;
    procedure Close;
    property ConnectionId: UInt64 read GetConnectionId;
    property RemoteAddress: string read GetRemoteAddress;
    property RemotePort: Word read GetRemotePort;
  end;

  IConnectionHandler = interface
    ['{A672F8B0-4A0B-4712-A3DF-8BFCE48FA472}']
    procedure OnConnect(const AConnection: IDextTransportConnection);
    procedure OnDisconnect(const AConnection: IDextTransportConnection);
    procedure OnData(const AConnection: IDextTransportConnection; const ASpan: TByteSpan);
    procedure OnError(const AConnection: IDextTransportConnection; AException: Exception);
  end;

  /// <summary>
  ///   Represents a low-level, high-performance raw HTTP request.
  /// </summary>
  IDextRawRequest = interface
    ['{8F9A7B3C-2D1E-4B0A-9D8C-7E6F5A4B3C2E}']
    /// <summary>Returns the HTTP request method (e.g. GET, POST).</summary>
    function GetMethod: string;
    /// <summary>Returns the request path (excluding query parameters).</summary>
    function GetPath: string;
    /// <summary>Returns the raw query string (e.g. key1=val1&key2=val2).</summary>
    function GetQueryString: string;
    /// <summary>Gets the value of a specific HTTP header.</summary>
    /// <param name="AName">The name of the header.</param>
    function GetHeader(const AName: string): string;
    /// <summary>Populates the provided dictionary with all request headers.</summary>
    /// <param name="ADict">The dictionary to populate.</param>
    procedure PopulateHeaders(ADict: TDictionary<string, string>);
    /// <summary>Returns the request content length.</summary>
    function GetContentLength: Int64;
    /// <summary>Returns a stream containing the request body.</summary>
    function GetBodyStream: TStream;

    property Method: string read GetMethod;
    property Path: string read GetPath;
    property QueryString: string read GetQueryString;
    property ContentLength: Int64 read GetContentLength;
    property BodyStream: TStream read GetBodyStream;
  end;

  /// <summary>
  ///   Represents a low-level, high-performance raw HTTP response.
  /// </summary>
  IDextRawResponse = interface
    ['{7E6F5A4B-3C2D-1E0F-9A8B-8C7D6E5F4A3B}']
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
    /// <param name="AOffset">The zero-based byte offset in ABuffer.</param>
    /// <param name="ACount">The number of bytes to write.</param>
    procedure Write(const ABuffer: TBytes; AOffset, ACount: Integer);
    /// <summary>Writes a file directly to the response socket using zero-copy transmission.</summary>
    procedure WriteFile(const APath: string; AOffset, ACount: Int64);
    /// <summary>Flushes any buffered response data to the underlying transport.</summary>
    procedure Flush;
    /// <summary>Closes the HTTP response, finishing the request lifecycle.</summary>
    procedure Close;
  end;

  /// <summary>Optional zero-copy byte sink exposed by native responses.</summary>
  IDextRawResponseSink = interface
    ['{D51C8A85-96D7-4EA3-A637-471077510B55}']
    /// <summary>Copies a byte span directly into transport-owned segments.</summary>
    procedure WriteBytes(AData: Pointer; ALength: Integer);
  end;

  /// <summary>
  ///   Represents a raw WebSocket connection upgraded from a standard server connection.
  /// </summary>
  IDextWebSocketConnection = interface
    ['{6D5C4B3A-2D1E-0F9A-8B7C-6E5D4C3B2A10}']
    /// <summary>Returns the unique connection ID.</summary>
    function GetConnectionId: UInt64;
    /// <summary>Sends a UTF-8 text frame over the WebSocket connection.</summary>
    /// <param name="AText">The text string to send.</param>
    procedure SendText(const AText: string);
    /// <summary>Sends a binary data frame over the WebSocket connection.</summary>
    /// <param name="AData">The byte array containing binary data.</param>
    procedure SendBinary(const AData: TBytes);
    /// <summary>Sends an already encoded WebSocket frame.</summary>
    procedure SendFrame(const AFrame: TBytes);
    /// <summary>Closes the WebSocket connection with a status code and reason.</summary>
    /// <param name="AStatusCode">The WebSocket status code (default: 1000 - Normal Close).</param>
    /// <param name="AReason">Optional descriptive reason string.</param>
    procedure Close(AStatusCode: Word = 1000; const AReason: string = '');
    /// <summary>Reads raw data from the WebSocket connection (blocking).</summary>
    /// <returns>Number of bytes read, 0 on disconnect, or -1 on error/timeout.</returns>
    function Receive(var ABuffer: TBytes; AOffset, ACount: Integer): Integer;
    
    property ConnectionId: UInt64 read GetConnectionId;
  end;

  /// <summary>Optional event-driven WebSocket transport implemented by native engines.</summary>
  IDextAsyncWebSocketConnection = interface
    ['{FA7639E3-F7E4-41C3-9813-998FC5B25362}']
    procedure SetOnData(const AHandler: TWebSocketDataEvent);
    procedure SetOnClosed(const AHandler: TWebSocketClosedEvent);
    procedure StartReceive;
  end;

  /// <summary>Optional per-connection send-queue observability.</summary>
  IDextWebSocketQueueMetrics = interface
    ['{CB4AFA7B-8A7E-4D62-B136-DAA0D988C27F}']
    function GetPendingSendBytes: NativeInt;
    function GetPeakPendingSendBytes: NativeInt;
    function GetRejectedSendCount: Int64;
    property PendingSendBytes: NativeInt read GetPendingSendBytes;
    property PeakPendingSendBytes: NativeInt read GetPeakPendingSendBytes;
    property RejectedSendCount: Int64 read GetRejectedSendCount;
  end;

  /// <summary>Optional RFC 7692 compression owned by the native connection.</summary>
  IDextCompressedWebSocketConnection = interface
    ['{41826C83-5CF8-456E-B346-B304645D5BC9}']
    function IsCompressionEnabled: Boolean;
    function CompressMessage(const AData: TBytes): TBytes;
    function DecompressMessage(const AData: TBytes): TBytes;
  end;

  /// <summary>
  ///   Represents an active server-side client connection.
  /// </summary>
  IDextServerConnection = interface
    ['{5C4B3A2D-1E0F-9A8B-7C6E-5D4C3B2A10F9}']
    /// <summary>Returns the unique connection ID.</summary>
    function GetConnectionId: UInt64;
    /// <summary>Returns the remote client IP address.</summary>
    function GetRemoteAddress: string;
    /// <summary>Returns the remote client TCP port.</summary>
    function GetRemotePort: Word;
    /// <summary>Returns the local listener TCP port.</summary>
    function GetLocalPort: Word;
    /// <summary>Returns True if the connection is running over HTTPS/TLS.</summary>
    function IsSecure: Boolean;
    /// <summary>Closes the client connection abruptly.</summary>
    procedure Close;

    /// <summary>Returns True if the connection supports WebSocket upgrade protocols.</summary>
    function SupportsUpgrade: Boolean;
    /// <summary>Performs the WebSocket upgrade handshake and returns the connection.</summary>
    function UpgradeToWebSocket: IDextWebSocketConnection;

    property ConnectionId: UInt64 read GetConnectionId;
    property RemoteAddress: string read GetRemoteAddress;
    property RemotePort: Word read GetRemotePort;
    property LocalPort: Word read GetLocalPort;
  end;

  /// <summary>
  ///   Core native server engine interface.
  /// </summary>
  IDextServerEngine = interface
    ['{4B3A2D1E-0F9A-8B7C-6E5D-4C3B2A10F9E8}']
    /// <summary>Binds the engine to a specific address and port.</summary>
    /// <param name="AAddress">The network interface address (e.g., '0.0.0.0').</param>
    /// <param name="APort">The port number to bind to.</param>
    procedure Bind(const AAddress: string; APort: Word);
    /// <summary>Starts listening for incoming connections.</summary>
    procedure Start;
    /// <summary>Stops the engine and drains active requests gracefully.</summary>
    /// <param name="AGracefulTimeoutMs">Maximum time in milliseconds to wait for requests to finish.</param>
    procedure Stop(AGracefulTimeoutMs: Integer = 5000);
    
    /// <summary>Returns the actual port the engine is listening on (useful if bound to 0).</summary>
    function GetListenPort: Word;
    /// <summary>Returns the current count of active connections.</summary>
    function GetActiveConnections: Integer;
    /// <summary>Returns the total number of HTTP requests processed.</summary>
    function GetTotalRequests: Int64;

    /// <summary>Sets the callback handler invoked when a new connection is established.</summary>
    procedure SetOnConnection(const AHandler: TConnectionEventHandler);
    /// <summary>Sets the callback handler invoked when a connection is closed.</summary>
    procedure SetOnDisconnection(const AHandler: TConnectionEventHandler);
    /// <summary>Sets the callback handler invoked when a complete request is received.</summary>
    procedure SetOnRequest(const AHandler: TRequestEventHandler);
    /// <summary>Sets the callback handler invoked to evaluate WebSocket upgrades.</summary>
    procedure SetOnUpgrade(const AHandler: TUpgradeEventHandler);
    /// <summary>Sets the custom connection handler for non-HTTP raw protocol execution.</summary>
    procedure SetConnectionHandler(const AHandler: IConnectionHandler);

    property ListenPort: Word read GetListenPort;
    property ActiveConnections: Integer read GetActiveConnections;
    property TotalRequests: Int64 read GetTotalRequests;
  end;

  /// <summary>
  ///   Auto-selects the best native engine for the current platform (HTTP.sys on Windows).
  /// </summary>
  /// <param name="AOptions">The server options configuration.</param>
  /// <returns>The IDextServerEngine interface instance.</returns>
  function CreateNativeEngine(const AOptions: TServerEngineOptions): IDextServerEngine;

  /// <summary>
  ///   Creates the platform socket engine (IOCP on Windows, epoll on Linux) for custom protocols.
  /// </summary>
  /// <param name="AOptions">The server options configuration.</param>
  /// <returns>The IDextServerEngine interface instance.</returns>
  function CreateSocketEngine(const AOptions: TServerEngineOptions): IDextServerEngine;

type
  /// <summary>
  ///   Called on a worker thread of the Windows engines (http.sys and IOCP
  ///   sockets) when that worker has handled work and then waited
  ///   DextWorkerIdleMs without any: once per idle period, on that thread.
  ///   It lets the application release per-thread caches, for example a memory
  ///   manager with thread-local heaps that only trims a heap when its own
  ///   thread asks (mimalloc: mi_collect).
  /// </summary>
  TDextWorkerIdleProc = procedure;

var
  /// <summary>
  ///   The idle hook (see TDextWorkerIdleProc). nil (default): the workers wait
  ///   as before. Set it, and DextWorkerIdleMs, before the server starts: each
  ///   worker reads them when it starts. It runs on the worker thread, so it
  ///   must be quick and must not raise.
  /// </summary>
  DextWorkerIdle: TDextWorkerIdleProc = nil;
  /// <summary>How long a worker waits without work before DextWorkerIdle (ms).</summary>
  DextWorkerIdleMs: Cardinal = 1000;

implementation

{$IFDEF MSWINDOWS}
uses
  Dext.Server.HttpSys,
  Dext.Server.Iocp;
{$ELSE}
uses
  Dext.Server.Epoll;
{$ENDIF}

function CreateNativeEngine(const AOptions: TServerEngineOptions): IDextServerEngine;
begin
  {$IFDEF MSWINDOWS}
  Result := TDextHttpSysEngine.Create(AOptions);
  {$ELSE}
  Result := TDextEpollEngine.Create(AOptions);
  {$ENDIF}
end;

function CreateSocketEngine(const AOptions: TServerEngineOptions): IDextServerEngine;
begin
  {$IFDEF MSWINDOWS}
  Result := TDextIocpEngine.Create(AOptions);
  {$ELSE}
  Result := TDextEpollEngine.Create(AOptions);
  {$ENDIF}
end;

end.
