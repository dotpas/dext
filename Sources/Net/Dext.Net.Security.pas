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
{  Author:  Cesar Romero & Antigravity                                      }
{  Created: 2026-07-23                                                      }
{                                                                           }
{  Unified SSL/TLS abstraction layer for Dext Framework.                     }
{                                                                           }
{***************************************************************************}
unit Dext.Net.Security;

{$I Dext.inc}

interface

uses
  System.Classes,
  System.SysUtils;

type
  /// <summary>Supported TLS protocol versions.</summary>
  TDextTLSVersion = (tls1_0, tls1_1, tls1_2, tls1_3);
  TDextTLSVersions = set of TDextTLSVersion;

  /// <summary>Operating mode for TLS engine.</summary>
  TDextTLSMode = (tlsmClient, tlsmServer);

  /// <summary>Unified SSL/TLS configuration options record.</summary>
  TDextTLSOptions = record
    Enabled: Boolean;
    Mode: TDextTLSMode;
    CertFile: string;
    KeyFile: string;
    RootCertFile: string;
    CertHash: string;
    StoreName: string;
    Host: string;
    Protocols: TDextTLSVersions;
    VerifyServerCertificate: Boolean;
    ALPNProtocols: TArray<string>;
    Provider: string; // 'Auto', 'OpenSSL', 'HttpSys', 'Indy'

    class function DefaultClient: TDextTLSOptions; static;
    class function DefaultServer(const ACertFile, AKeyFile: string): TDextTLSOptions; static;
  end;

  /// <summary>Fluent builder for SSL/TLS configuration options.</summary>
  TDextTLSOptionsBuilder = record
  private
    FOptions: TDextTLSOptions;
  public
    class function Create(AEnabled: Boolean = True; const AHost: string = ''): TDextTLSOptionsBuilder; static;
    class function Client(const AHost: string = ''): TDextTLSOptionsBuilder; static;
    class function Server(const ACertFile: string = ''; const AKeyFile: string = ''): TDextTLSOptionsBuilder; static;

    function Host(const Value: string): TDextTLSOptionsBuilder;
    function Provider(const Value: string): TDextTLSOptionsBuilder;
    function UseOpenSSL: TDextTLSOptionsBuilder;
    function UseHttpSys: TDextTLSOptionsBuilder;
    function UseIndy: TDextTLSOptionsBuilder;
    function CertificateFile(const Value: string): TDextTLSOptionsBuilder;
    function PrivateKeyFile(const Value: string): TDextTLSOptionsBuilder;
    function CAFile(const Value: string): TDextTLSOptionsBuilder;
    function CertFile(const Value: string): TDextTLSOptionsBuilder;
    function KeyFile(const Value: string): TDextTLSOptionsBuilder;
    function RootCertFile(const Value: string): TDextTLSOptionsBuilder;
    function CertHash(const Value: string): TDextTLSOptionsBuilder;
    function StoreName(const Value: string): TDextTLSOptionsBuilder;
    function Protocols(Value: TDextTLSVersions): TDextTLSOptionsBuilder;
    function VerifyServerCertificate(Value: Boolean = True): TDextTLSOptionsBuilder;
    function AllowSelfSigned(Value: Boolean = True): TDextTLSOptionsBuilder;
    function ALPN(const AProtocols: array of string): TDextTLSOptionsBuilder;
    function Mode(Value: TDextTLSMode): TDextTLSOptionsBuilder;

    function Build: TDextTLSOptions;
    class operator Implicit(const ABuilder: TDextTLSOptionsBuilder): TDextTLSOptions;
  end;

  TDextTLSBuilder = TDextTLSOptionsBuilder;

  /// <summary>Status of asynchronous TLS engine processing.</summary>
  TDextTLSEngineStatus = (
    tlsHandshakeNeedRead,
    tlsHandshakeNeedWrite,
    tlsHandshakeCompleted,
    tlsDataReady,
    tlsError
  );

  /// <summary>Result of the most recent TLS data operation.</summary>
  TDextTLSIOStatus = (
    tlsIOOk,
    tlsIONeedRead,
    tlsIONeedWrite,
    tlsIOClosed,
    tlsIOError
  );

  /// <summary>
  ///   Core abstraction for asynchronous, memory-based TLS engine (Memory BIOs).
  ///   Decouples network IO from encryption logic.
  /// </summary>
  IDextTLSEngine = interface
    ['{F5C6D7E8-F9A0-4B1C-8D2E-3F4A5B6C7D8E}']
    /// <summary>Processes raw encrypted incoming network data into the engine.</summary>
    function EncryptedIncoming(const ABuffer: Pointer; ACount: Integer): Integer;
    /// <summary>Reads decrypted plaintext payload out of the engine.</summary>
    function PlaintextRead(const ABuffer: Pointer; ACount: Integer): Integer;
    /// <summary>Writes plaintext payload into the engine for encryption.</summary>
    function PlaintextWrite(const ABuffer: Pointer; ACount: Integer): Integer;
    /// <summary>Reads encrypted outgoing network payload ready to be sent over socket.</summary>
    function EncryptedOutgoing(const ABuffer: Pointer; ACount: Integer): Integer;

    /// <summary>Drives the TLS handshake process forward.</summary>
    function DoHandshake: TDextTLSEngineStatus;
    /// <summary>Returns true if the TLS handshake has completed.</summary>
    function IsHandshakeCompleted: Boolean;
    /// <summary>Returns negotiated ALPN protocol if present (e.g. 'h2', 'http/1.1').</summary>
    function GetNegotiatedALPN: string;
    /// <summary>Returns the status of the most recent TLS data operation.</summary>
    function GetLastIOStatus: TDextTLSIOStatus;
    /// <summary>Returns the most recent native TLS error code.</summary>
    function GetLastErrorCode: NativeUInt;
    /// <summary>Returns encrypted bytes waiting in the output BIO.</summary>
    function GetPendingEncryptedBytes: NativeInt;
    /// <summary>Starts or advances the TLS close-notify handshake.</summary>
    function Shutdown: TDextTLSIOStatus;
  end;

  /// <summary>
  ///   Factory interface to initialize SSL/TLS Contexts.
  /// </summary>
  IDextTLSContextProvider = interface
    ['{E4D3C2B1-A0F9-4E8D-7C6B-5A4F3E2D1C0B}']
    function CreateEngine(AMode: TDextTLSMode): IDextTLSEngine;
    function GetOptions: TDextTLSOptions;
  end;

  /// <summary>
  ///   Stream wrapper that provides transparent TLS encryption over standard TStream.
  /// </summary>
  IDextTLSStream = interface
    ['{D3C2B1A0-F9E8-4D7C-6B5A-4F3E2D1C0B9A}']
    function GetUnderlyingStream: TStream;
    function Read(const ABuffer: Pointer; ACount: Longint): Longint;
    function Write(const ABuffer: Pointer; ACount: Longint): Longint;
  end;

/// <summary>Factory function returning a fluent builder for SSL/TLS options.</summary>
function TlsOptions: TDextTLSOptionsBuilder; overload;
function TlsOptions(const AHost: string): TDextTLSOptionsBuilder; overload;
function TlsOptions(AEnabled: Boolean; const AHost: string = ''): TDextTLSOptionsBuilder; overload;

implementation

{ TDextTLSOptions }

class function TDextTLSOptions.DefaultClient: TDextTLSOptions;
begin
  // Result is the caller's storage, already initialized: release its managed
  // fields before zeroing it, or the strings and interfaces it held are leaked.
  Finalize(Result);
  FillChar(Result, SizeOf(Result), 0);
  Result.Enabled := True;
  Result.Mode := tlsmClient;
  Result.Protocols := [tls1_2, tls1_3];
  Result.VerifyServerCertificate := True;
  Result.Provider := 'Auto';
end;

class function TDextTLSOptions.DefaultServer(const ACertFile, AKeyFile: string): TDextTLSOptions;
begin
  // Result is the caller's storage, already initialized: release its managed
  // fields before zeroing it, or the strings and interfaces it held are leaked.
  Finalize(Result);
  FillChar(Result, SizeOf(Result), 0);
  Result.Enabled := True;
  Result.Mode := tlsmServer;
  Result.CertFile := ACertFile;
  Result.KeyFile := AKeyFile;
  Result.Protocols := [tls1_2, tls1_3];
  Result.StoreName := 'MY';
  Result.Provider := 'Auto';
end;

{ TDextTLSOptionsBuilder }

class function TDextTLSOptionsBuilder.Create(AEnabled: Boolean; const AHost: string): TDextTLSOptionsBuilder;
begin
  Result.FOptions := TDextTLSOptions.DefaultClient;
  Result.FOptions.Enabled := AEnabled;
  Result.FOptions.Host := AHost;
end;

class function TDextTLSOptionsBuilder.Client(const AHost: string): TDextTLSOptionsBuilder;
begin
  Result.FOptions := TDextTLSOptions.DefaultClient;
  Result.FOptions.Host := AHost;
end;

class function TDextTLSOptionsBuilder.Server(const ACertFile, AKeyFile: string): TDextTLSOptionsBuilder;
begin
  Result.FOptions := TDextTLSOptions.DefaultServer(ACertFile, AKeyFile);
end;

function TDextTLSOptionsBuilder.Host(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Host := Value;
end;

function TDextTLSOptionsBuilder.Provider(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Provider := Value;
end;

function TDextTLSOptionsBuilder.UseOpenSSL: TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Provider := 'OpenSSL';
end;

function TDextTLSOptionsBuilder.UseHttpSys: TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Provider := 'HttpSys';
end;

function TDextTLSOptionsBuilder.UseIndy: TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Provider := 'Indy';
end;

function TDextTLSOptionsBuilder.CertificateFile(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.CertFile := Value;
end;

function TDextTLSOptionsBuilder.PrivateKeyFile(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.KeyFile := Value;
end;

function TDextTLSOptionsBuilder.CAFile(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.RootCertFile := Value;
end;

function TDextTLSOptionsBuilder.CertFile(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.CertFile := Value;
end;

function TDextTLSOptionsBuilder.KeyFile(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.KeyFile := Value;
end;

function TDextTLSOptionsBuilder.RootCertFile(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.RootCertFile := Value;
end;

function TDextTLSOptionsBuilder.CertHash(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.CertHash := Value;
end;

function TDextTLSOptionsBuilder.StoreName(const Value: string): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.StoreName := Value;
end;

function TDextTLSOptionsBuilder.Protocols(Value: TDextTLSVersions): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Protocols := Value;
end;

function TDextTLSOptionsBuilder.VerifyServerCertificate(Value: Boolean): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.VerifyServerCertificate := Value;
end;

function TDextTLSOptionsBuilder.AllowSelfSigned(Value: Boolean): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.VerifyServerCertificate := not Value;
end;

function TDextTLSOptionsBuilder.ALPN(const AProtocols: array of string): TDextTLSOptionsBuilder;
var
  I: Integer;
begin
  Result := Self;
  SetLength(Result.FOptions.ALPNProtocols, Length(AProtocols));
  for I := 0 to High(AProtocols) do
    Result.FOptions.ALPNProtocols[I] := AProtocols[I];
end;

function TDextTLSOptionsBuilder.Mode(Value: TDextTLSMode): TDextTLSOptionsBuilder;
begin
  Result := Self;
  Result.FOptions.Mode := Value;
end;

function TDextTLSOptionsBuilder.Build: TDextTLSOptions;
begin
  Result := FOptions;
end;

class operator TDextTLSOptionsBuilder.Implicit(const ABuilder: TDextTLSOptionsBuilder): TDextTLSOptions;
begin
  Result := ABuilder.FOptions;
end;

function TlsOptions: TDextTLSOptionsBuilder;
begin
  Result := TDextTLSOptionsBuilder.Client;
end;

function TlsOptions(const AHost: string): TDextTLSOptionsBuilder;
begin
  Result := TDextTLSOptionsBuilder.Client(AHost);
end;

function TlsOptions(AEnabled: Boolean; const AHost: string): TDextTLSOptionsBuilder;
begin
  Result := TDextTLSOptionsBuilder.Create(AEnabled, AHost);
end;

end.
