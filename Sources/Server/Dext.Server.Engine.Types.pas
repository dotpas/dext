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
{  Configuration options and types for native server engines.               }
{                                                                           }
{***************************************************************************}
unit Dext.Server.Engine.Types;

interface

uses
  System.SysUtils;

{$SCOPEDENUMS ON}

type
  /// <summary>
  ///   Configuration options for the Dext high-performance server engines.
  /// </summary>
  TServerEngineOptions = record
    /// <summary>Number of I/O worker threads. 0 means auto-detect (CPU count).</summary>
    IoThreadCount: Integer;
    /// <summary>Size of the receive buffer per connection in bytes (default: 8192).</summary>
    ReceiveBufferSize: Integer;
    /// <summary>Maximum concurrent connections. 0 means unlimited.</summary>
    MaxConnections: Integer;
    /// <summary>Graceful shutdown drain timeout in milliseconds (default: 5000).</summary>
    ShutdownTimeoutMs: Integer;
    /// <summary>Enable Keep-Alive (default: True).</summary>
    KeepAlive: Boolean;
    /// <summary>Keep-Alive timeout in seconds (default: 120).</summary>
    KeepAliveTimeoutSec: Integer;
    /// <summary>The IP address or host to bind the server to (default: '0.0.0.0').</summary>
    BindAddress: string;
    /// <summary>Max threads for task executor (default: 0 - inline).</summary>
    MaxExecutorThreads: Integer;
    /// <summary>Max queue capacity for task executor (default: 1024).</summary>
    MaxQueueCapacity: Integer;
    /// <summary>Outstanding Http.Sys receives per I/O worker (default: 2).</summary>
    OutstandingReceiveDepth: Integer;
    /// <summary>
    ///   Total outstanding Http.Sys receives. 0 (default) keeps
    ///   IoThreadCount x OutstandingReceiveDepth. Set it to run more workers
    ///   than receives: extra workers then only pick up requests while others
    ///   are blocked (database, file, remote call).
    /// </summary>
    OutstandingReceives: Integer;
    /// <summary>
    ///   Http.sys request-queue length (HttpServerQueueLengthProperty).
    ///   0 leaves the kernel default (typically 1000).
    /// </summary>
    QueueLength: Integer;
    /// <summary>
    ///   Http.sys max bandwidth in bytes/sec (HttpServerQosProperty).
    ///   0 means unlimited / not configured.
    /// </summary>
    MaxBandwidth: Integer;
    /// <summary>
    ///   Http.sys EntityBody timeout in seconds. 0 leaves the system default.
    /// </summary>
    EntityBodyTimeoutSec: Integer;
    /// <summary>
    ///   Http.sys HeaderWait timeout in seconds. 0 leaves the system default.
    /// </summary>
    HeaderWaitTimeoutSec: Integer;
    /// <summary>
    ///   Http.sys RequestQueue timeout in seconds. 0 leaves the system default.
    /// </summary>
    RequestQueueTimeoutSec: Integer;
    /// <summary>
    ///   Http.sys DrainEntityBody timeout in seconds. 0 leaves the system default.
    /// </summary>
    DrainEntityBodyTimeoutSec: Integer;
    /// <summary>
    ///   Http.sys MinSendRate in bytes/sec. 0 leaves the system default.
    /// </summary>
    MinSendRate: Integer;
    /// <summary>Maximum accepted native request-header buffer size.</summary>
    MaxRequestHeaderSize: Integer;
    /// <summary>Maximum accepted request body size.</summary>
    MaxRequestBodySize: Int64;
    /// <summary>Enable HTTPS/SSL on the server engine (default: False).</summary>
    UseHttps: Boolean;
    /// <summary>SSL Certificate Hash (Thumbprint) for Windows Schannel / http.sys.</summary>
    SslCertHash: string;
    /// <summary>PEM certificate chain used by user-mode TLS providers.</summary>
    SslCertFile: string;
    /// <summary>PEM private key used by user-mode TLS providers.</summary>
    SslKeyFile: string;
    /// <summary>Optional CA bundle used by user-mode TLS providers.</summary>
    SslRootCertFile: string;
    /// <summary>Configured TLS provider name.</summary>
    SslProvider: string;
    /// <summary>Windows certificate store used by the http.sys binding.</summary>
    SslCertStoreName: string;
    /// <summary>Administrative owner of an http.sys SSL binding.</summary>
    HttpSysAppId: TGUID;
    /// <summary>
    ///   Validate the http.sys SSL binding at startup (default: True). Set it to
    ///   False when the bindings are managed outside the service (IIS, win-acme,
    ///   Group Policy, central certificate store).
    /// </summary>
    ValidateSslBinding: Boolean;
    /// <summary>Base path prefix (e.g. '/myapp').</summary>
    PathBase: string;

    /// <summary>Creates a default configuration options record.</summary>
    class function Default: TServerEngineOptions; static;
  end;

  /// <summary>
  ///   Fluent helper for TServerEngineOptions to chain configurations.
  /// </summary>
  TServerEngineOptionsHelper = record helper for TServerEngineOptions
    /// <summary>Enables or disables HTTPS/SSL on the server engine.</summary>
    function WithHttps(AValue: Boolean = True): TServerEngineOptions;
    /// <summary>Configures the SSL Certificate Hash (Thumbprint) for Windows Schannel / http.sys.</summary>
    function WithSslCertHash(const AHash: string): TServerEngineOptions;
    /// <summary>Enables or disables the http.sys SSL binding validation at startup.</summary>
    function WithSslBindingValidation(AValue: Boolean = True): TServerEngineOptions;
    /// <summary>Configures the number of worker I/O threads.</summary>
    /// <param name="ACount">Number of threads (0 for CPU count auto-detection).</param>
    function WithIoThreads(ACount: Integer): TServerEngineOptions;
    /// <summary>Configures the connection socket read/receive buffer size.</summary>
    /// <param name="ASize">Buffer size in bytes.</param>
    function WithReceiveBufferSize(ASize: Integer): TServerEngineOptions;
    /// <summary>Configures the maximum concurrent connections limit.</summary>
    /// <param name="AConnections">Connections limit (0 for unlimited).</param>
    function WithMaxConnections(AConnections: Integer): TServerEngineOptions;
    /// <summary>Configures the graceful shutdown timeout.</summary>
    /// <param name="ATimeoutMs">Timeout duration in milliseconds.</param>
    function WithShutdownTimeout(ATimeoutMs: Integer): TServerEngineOptions;
    /// <summary>Configures keep-alive socket configuration.</summary>
    /// <param name="AEnable">True to enable keep-alive.</param>
    /// <param name="ATimeoutSec">Keep-alive timeout in seconds.</param>
    function WithKeepAlive(AEnable: Boolean; ATimeoutSec: Integer = 120): TServerEngineOptions;
    /// <summary>Configures the server bind address (e.g. '0.0.0.0', '127.0.0.1', or '+').</summary>
    /// <param name="AAddress">The bind address string.</param>
    function WithBindAddress(const AAddress: string): TServerEngineOptions;
    /// <summary>Configures max threads for request executor pool.</summary>
    function WithMaxExecutorThreads(ACount: Integer): TServerEngineOptions;
    /// <summary>Configures max queue capacity for request executor.</summary>
    function WithMaxQueueCapacity(ACapacity: Integer): TServerEngineOptions;
    /// <summary>Configures outstanding Http.Sys receives per worker (1..8).</summary>
    function WithOutstandingReceiveDepth(
      ADepth: Integer): TServerEngineOptions;
    /// <summary>Configures the total outstanding Http.Sys receives (0 = workers x depth).</summary>
    function WithOutstandingReceives(ACount: Integer): TServerEngineOptions;
    /// <summary>Configures the http.sys request-queue length (0 = kernel default).</summary>
    function WithQueueLength(ALength: Integer): TServerEngineOptions;
    /// <summary>Configures the http.sys max bandwidth in bytes/sec (0 = unlimited).</summary>
    function WithMaxBandwidth(ABytesPerSec: Integer): TServerEngineOptions;
    /// <summary>Configures http.sys kernel timeouts (seconds; 0 = system default).</summary>
    function WithHttpSysTimeouts(AEntityBodySec: Integer = 0;
      AHeaderWaitSec: Integer = 0; ARequestQueueSec: Integer = 0;
      ADrainEntityBodySec: Integer = 0;
      AMinSendRate: Integer = 0): TServerEngineOptions;
    /// <summary>Configures native request header and body size limits.</summary>
    function WithRequestSizeLimits(AHeaderBytes: Integer;
      ABodyBytes: Int64): TServerEngineOptions;
    /// <summary>Configures the base path prefix (e.g. '/myapp').</summary>
    function WithPathBase(const APathBase: string): TServerEngineOptions;
  end;

  /// <summary>
  ///   Common low-level HTTP parsing helper utilities for raw byte buffers.
  /// </summary>
  TDextHttpParserCommon = record
  public
    class function FindByte(const ABuffer: TBytes; AStart, AEnd: Integer; AByte: Byte): Integer; static; inline;
    class function FindCRLF(const ABuffer: TBytes; AStart, AEnd: Integer): Integer; static; inline;
    class function CompareBytesCI(const ABuffer: TBytes; AStart, ALen: Integer; const AStr: string): Boolean; static; inline;
  end;

/// <summary>
///   Global entry point for fluently configuring TServerEngineOptions.
/// </summary>
function ServerEngineOptions: TServerEngineOptions; inline;

implementation

{ TServerEngineOptions }

class function TServerEngineOptions.Default: TServerEngineOptions;
begin
  Result.IoThreadCount := 0;
  Result.ReceiveBufferSize := 8192;
  Result.MaxConnections := 0;
  Result.ShutdownTimeoutMs := 5000;
  Result.KeepAlive := True;
  Result.KeepAliveTimeoutSec := 120;
  Result.BindAddress := '0.0.0.0';
  Result.MaxExecutorThreads := 0;
  Result.MaxQueueCapacity := 1024;
  Result.OutstandingReceiveDepth := 2;
  Result.OutstandingReceives := 0;
  Result.QueueLength := 0;
  Result.MaxBandwidth := 0;
  Result.EntityBodyTimeoutSec := 0;
  Result.HeaderWaitTimeoutSec := 0;
  Result.RequestQueueTimeoutSec := 0;
  Result.DrainEntityBodyTimeoutSec := 0;
  Result.MinSendRate := 0;
  Result.MaxRequestHeaderSize := 64 * 1024;
  Result.MaxRequestBodySize := 16 * 1024 * 1024;
  Result.UseHttps := False;
  Result.SslCertStoreName := 'MY';
  Result.SslProvider := 'Auto';
  Result.HttpSysAppId := TGUID.Empty;
  Result.ValidateSslBinding := True;
  Result.PathBase := '';
end;

function ServerEngineOptions: TServerEngineOptions;
begin
  Result := TServerEngineOptions.Default;
end;

{ TServerEngineOptionsHelper }

function TServerEngineOptionsHelper.WithHttps(AValue: Boolean): TServerEngineOptions;
begin
  Self.UseHttps := AValue;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithSslCertHash(const AHash: string): TServerEngineOptions;
begin
  Self.SslCertHash := AHash;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithSslBindingValidation(AValue: Boolean): TServerEngineOptions;
begin
  Self.ValidateSslBinding := AValue;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithIoThreads(ACount: Integer): TServerEngineOptions;
begin
  Self.IoThreadCount := ACount;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithReceiveBufferSize(ASize: Integer): TServerEngineOptions;
begin
  Self.ReceiveBufferSize := ASize;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithMaxConnections(AConnections: Integer): TServerEngineOptions;
begin
  Self.MaxConnections := AConnections;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithShutdownTimeout(ATimeoutMs: Integer): TServerEngineOptions;
begin
  Self.ShutdownTimeoutMs := ATimeoutMs;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithKeepAlive(AEnable: Boolean; ATimeoutSec: Integer): TServerEngineOptions;
begin
  Self.KeepAlive := AEnable;
  Self.KeepAliveTimeoutSec := ATimeoutSec;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithBindAddress(
  const AAddress: string): TServerEngineOptions;
begin
  Self.BindAddress := AAddress;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithMaxExecutorThreads(
  ACount: Integer): TServerEngineOptions;
begin
  Self.MaxExecutorThreads := ACount;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithMaxQueueCapacity(
  ACapacity: Integer): TServerEngineOptions;
begin
  Self.MaxQueueCapacity := ACapacity;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithOutstandingReceives(
  ACount: Integer): TServerEngineOptions;
begin
  Self.OutstandingReceives := ACount;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithOutstandingReceiveDepth(
  ADepth: Integer): TServerEngineOptions;
begin
  if ADepth < 1 then
    ADepth := 1
  else if ADepth > 8 then
    ADepth := 8;
  Self.OutstandingReceiveDepth := ADepth;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithQueueLength(
  ALength: Integer): TServerEngineOptions;
begin
  Self.QueueLength := ALength;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithMaxBandwidth(
  ABytesPerSec: Integer): TServerEngineOptions;
begin
  Self.MaxBandwidth := ABytesPerSec;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithHttpSysTimeouts(
  AEntityBodySec, AHeaderWaitSec, ARequestQueueSec, ADrainEntityBodySec,
  AMinSendRate: Integer): TServerEngineOptions;
begin
  Self.EntityBodyTimeoutSec := AEntityBodySec;
  Self.HeaderWaitTimeoutSec := AHeaderWaitSec;
  Self.RequestQueueTimeoutSec := ARequestQueueSec;
  Self.DrainEntityBodyTimeoutSec := ADrainEntityBodySec;
  Self.MinSendRate := AMinSendRate;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithRequestSizeLimits(
  AHeaderBytes: Integer; ABodyBytes: Int64): TServerEngineOptions;
begin
  Self.MaxRequestHeaderSize := AHeaderBytes;
  Self.MaxRequestBodySize := ABodyBytes;
  Result := Self;
end;

function TServerEngineOptionsHelper.WithPathBase(
  const APathBase: string): TServerEngineOptions;
begin
  Self.PathBase := APathBase;
  Result := Self;
end;

{ TDextHttpParserCommon }

class function TDextHttpParserCommon.FindByte(const ABuffer: TBytes; AStart, AEnd: Integer; AByte: Byte): Integer;
var
  I: Integer;
begin
  for I := AStart to AEnd - 1 do
    if ABuffer[I] = AByte then
      Exit(I);
  Result := -1;
end;

class function TDextHttpParserCommon.FindCRLF(const ABuffer: TBytes; AStart, AEnd: Integer): Integer;
var
  I: Integer;
begin
  for I := AStart to AEnd - 2 do
    if (ABuffer[I] = 13) and (ABuffer[I+1] = 10) then
      Exit(I);
  Result := -1;
end;

class function TDextHttpParserCommon.CompareBytesCI(const ABuffer: TBytes; AStart, ALen: Integer; const AStr: string): Boolean;
var
  I: Integer;
  B1, B2: Byte;
  PStr: PChar;
begin
  if ALen <> Length(AStr) then Exit(False);
  PStr := PChar(AStr);
  for I := 0 to ALen - 1 do
  begin
    B1 := ABuffer[AStart + I];
    B2 := Ord(PStr[I]);
    if (B1 >= 65) and (B1 <= 90) then B1 := B1 + 32;
    if (B2 >= 65) and (B2 <= 90) then B2 := B2 + 32;
    if B1 <> B2 then Exit(False);
  end;
  Result := True;
end;

end.
