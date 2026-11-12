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
{  Windows only. Tests of a WebSocket upgrade on the raw http.sys engine,   }
{  on a local port driven by a raw TCP client: the 101 goes out, the frames }
{  of the client reach the handler, SendText and SendBinary answer, and the }
{  worker does not send a second response for the upgraded request.        }
{                                                                           }
{  The port needs an http.sys URL reservation, or run as administrator.    }
{  Another port: environment variable DEXT_HTTPSYS_TEST_PORT.               }
{                                                                           }
{***************************************************************************}
unit Dext.Server.HttpSys.WebSocket.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Winapi.Windows,
  Winapi.WinSock2,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Server.Engine.Types,
  Dext.Server.Engine.Interfaces,
  Dext.Server.HttpSys;

type
  [TestFixture('Dext.Server http.sys WebSocket upgrade (local port)')]
  THttpSysWebSocketTests = class
  private
    FEngine: IDextServerEngine;
    FPort: Word;
    procedure StartEngine;
    procedure StopEngine;
    function Connect: TSocket;
    function Upgrade(ASocket: TSocket): string;
    procedure SendMaskedFrame(ASocket: TSocket; AOpcode: Byte; const APayload: TBytes);
    function ReadFrame(ASocket: TSocket; out AOpcode: Byte): TBytes;
  public
    [Test]
    procedure Upgrade_Sends101WithTheAcceptKey;
    [Test]
    procedure Upgrade_SendTextAnswersEveryMessage;
    [Test]
    procedure Upgrade_SendBinaryAnswers;
    [Test]
    procedure Upgrade_NoSecondResponseForTheRequest;
  end;

implementation

const
  DEFAULT_TEST_PORT = 28799;
  CRLF = #13#10;
  // The sample key of RFC 6455, 1.3, and its accept value.
  SAMPLE_KEY = 'dGhlIHNhbXBsZSBub25jZQ==';
  SAMPLE_ACCEPT = 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=';

var
  // One WebSocket at a time (the tests run one after the other).
  GWs: IDextWebSocketConnection;
  GError: string;
  GBinary: Boolean;
  GReceived: Integer;
  GLock: TCriticalSection;

procedure AddError(const AText: string);
begin
  GLock.Enter;
  try
    GError := GError + AText + '; ';
  finally
    GLock.Leave;
  end;
end;

procedure HandleRequest(const AConnection: IDextServerConnection;
  const ARequest: IDextRawRequest; const AResponse: IDextRawResponse);
var
  Async: IDextAsyncWebSocketConnection;
  Ws: IDextWebSocketConnection;
begin
  if ARequest.GetPath <> '/ws' then
    Exit;
  try
    Ws := AConnection.UpgradeToWebSocket;
    GWs := Ws;
    if Supports(Ws, IDextAsyncWebSocketConnection, Async) then
    begin
      Async.SetOnData(
        procedure(const ABuffer: TBytes; ACount: Integer)
        begin
          TInterlocked.Increment(GReceived);
          try
            // The answer: "echo" for every chunk received
            if GBinary then
              GWs.SendBinary(TBytes.Create(1, 2, 3))
            else
              GWs.SendText('echo');
          except
            on E: Exception do
              AddError('send: ' + E.Message);
          end;
        end);
      Async.StartReceive;
    end
    else
      AddError('no async WebSocket');
  except
    on E: Exception do
      AddError('upgrade: ' + E.Message);
  end;
end;

{ THttpSysWebSocketTests }

procedure THttpSysWebSocketTests.StartEngine;
var
  Data: TWSAData;
  Options: TServerEngineOptions;
begin
  WSAStartup($0202, Data);
  GError := '';
  GBinary := False;
  GReceived := 0;
  GWs := nil;
  FPort := StrToIntDef(GetEnvironmentVariable('DEXT_HTTPSYS_TEST_PORT'), DEFAULT_TEST_PORT);
  Options := TServerEngineOptions.Default;
  Options.IoThreadCount := 2;
  FEngine := TDextHttpSysEngine.Create(Options);
  FEngine.SetOnRequest(HandleRequest);
  FEngine.Bind('0.0.0.0', FPort);
  FEngine.Start;
end;

procedure THttpSysWebSocketTests.StopEngine;
begin
  GWs := nil;
  if FEngine <> nil then
    FEngine.Stop;
  FEngine := nil;
end;

function THttpSysWebSocketTests.Connect: TSocket;
var
  Addr: TSockAddrIn;
  Timeout: DWORD;
begin
  Result := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  Timeout := 3000;
  setsockopt(Result, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(FPort);
  Addr.sin_addr.S_addr := inet_addr('127.0.0.1');
  if Winapi.WinSock2.connect(Result, PSockAddr(@Addr)^, SizeOf(Addr)) <> 0 then
    raise Exception.Create('connect failed: ' + IntToStr(WSAGetLastError));
end;

function THttpSysWebSocketTests.Upgrade(ASocket: TSocket): string;
var
  Req: AnsiString;
  Ch: AnsiChar;
  Head: AnsiString;
begin
  Req := 'GET /ws HTTP/1.1' + CRLF + 'Host: localhost' + CRLF +
    'Upgrade: websocket' + CRLF + 'Connection: Upgrade' + CRLF +
    'Sec-WebSocket-Key: ' + SAMPLE_KEY + CRLF +
    'Sec-WebSocket-Version: 13' + CRLF + CRLF;
  send(ASocket, Req[1], Length(Req), 0);
  // The head of the answer, byte by byte (the frames come after it)
  Head := '';
  while (Length(Head) < 4) or (Copy(Head, Length(Head) - 3, 4) <> CRLF + CRLF) do
  begin
    if recv(ASocket, Ch, 1, 0) <> 1 then
      Break;
    Head := Head + Ch;
  end;
  Result := string(Head);
end;

procedure THttpSysWebSocketTests.SendMaskedFrame(ASocket: TSocket; AOpcode: Byte;
  const APayload: TBytes);
const
  Mask: array[0..3] of Byte = ($11, $22, $33, $44);
var
  Frame: TBytes;
  I: Integer;
begin
  // A short frame (payload under 126 bytes), masked as a client must
  SetLength(Frame, 6 + Length(APayload));
  Frame[0] := $80 or AOpcode;
  Frame[1] := $80 or Byte(Length(APayload));
  Move(Mask[0], Frame[2], 4);
  for I := 0 to High(APayload) do
    Frame[6 + I] := APayload[I] xor Mask[I mod 4];
  send(ASocket, Frame[0], Length(Frame), 0);
end;

function THttpSysWebSocketTests.ReadFrame(ASocket: TSocket; out AOpcode: Byte): TBytes;
var
  Head: array[0..1] of Byte;
  Len, Got, N: Integer;
begin
  // A short unmasked frame from the server
  Result := nil;
  AOpcode := 0;
  Got := 0;
  while Got < 2 do
  begin
    N := recv(ASocket, Head[Got], 2 - Got, 0);
    if N <= 0 then
      Exit;
    Inc(Got, N);
  end;
  AOpcode := Head[0] and $0F;
  Len := Head[1] and $7F;
  SetLength(Result, Len);
  Got := 0;
  while Got < Len do
  begin
    N := recv(ASocket, Result[Got], Len - Got, 0);
    if N <= 0 then
      Exit(nil);
    Inc(Got, N);
  end;
end;

procedure THttpSysWebSocketTests.Upgrade_Sends101WithTheAcceptKey;
var
  S: TSocket;
  Head: string;
begin
  StartEngine;
  try
    S := Connect;
    try
      Head := Upgrade(S);
      Should(Head).StartWith('HTTP/1.1 101');
      Should(Head).Contain('Sec-WebSocket-Accept: ' + SAMPLE_ACCEPT);
    finally
      closesocket(S);
    end;
    Should(GError).Be('');
  finally
    StopEngine;
  end;
end;

procedure THttpSysWebSocketTests.Upgrade_SendTextAnswersEveryMessage;
var
  S: TSocket;
  Opcode: Byte;
  I: Integer;
begin
  StartEngine;
  try
    S := Connect;
    try
      Should(Upgrade(S)).StartWith('HTTP/1.1 101');
      for I := 1 to 3 do
      begin
        SendMaskedFrame(S, 1, TEncoding.UTF8.GetBytes('hello' + IntToStr(I)));
        Should(TEncoding.UTF8.GetString(ReadFrame(S, Opcode))).Be('echo');
        Should(Integer(Opcode)).Be(1);
      end;
    finally
      closesocket(S);
    end;
    Should(GError).Be('');
    Should(GReceived).Be(3);
  finally
    StopEngine;
  end;
end;

procedure THttpSysWebSocketTests.Upgrade_SendBinaryAnswers;
var
  S: TSocket;
  Opcode: Byte;
  Answer: TBytes;
begin
  StartEngine;
  try
    GBinary := True;
    S := Connect;
    try
      Should(Upgrade(S)).StartWith('HTTP/1.1 101');
      SendMaskedFrame(S, 2, TBytes.Create(9, 8, 7));
      Answer := ReadFrame(S, Opcode);
      Should(Integer(Opcode)).Be(2);
      Should(Length(Answer)).Be(3);
      Should(Integer(Answer[0])).Be(1);
      Should(Integer(Answer[2])).Be(3);
    finally
      closesocket(S);
    end;
    Should(GError).Be('');
  finally
    StopEngine;
  end;
end;

procedure THttpSysWebSocketTests.Upgrade_NoSecondResponseForTheRequest;
var
  S: TSocket;
  Opcode: Byte;
  Buffer: array[0..255] of Byte;
  Timeout: DWORD;
begin
  StartEngine;
  try
    S := Connect;
    try
      Should(Upgrade(S)).StartWith('HTTP/1.1 101');
      // The handler has returned: the worker closed the response. Nothing
      // else may arrive on the connection (no second HTTP response), and it
      // must still carry the WebSocket.
      Timeout := 500;
      setsockopt(S, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
      Should(recv(S, Buffer[0], SizeOf(Buffer), 0)).Be(SOCKET_ERROR);
      Should(WSAGetLastError).Be(WSAETIMEDOUT);
      Timeout := 3000;
      setsockopt(S, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
      SendMaskedFrame(S, 1, TEncoding.UTF8.GetBytes('still there'));
      Should(TEncoding.UTF8.GetString(ReadFrame(S, Opcode))).Be('echo');
    finally
      closesocket(S);
    end;
    Should(GError).Be('');
  finally
    StopEngine;
  end;
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  GLock.Free;

end.
