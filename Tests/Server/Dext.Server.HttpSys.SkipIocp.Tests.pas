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
{  Tests of the http.sys engine on the paths that SkipIocpOnSuccess         }
{  (FILE_SKIP_COMPLETION_PORT_ON_SUCCESS) touches, each run with the option }
{  off and on: a request body larger than 64 KB (several body receives),    }
{  Flush followed by Close (streaming), a client that disconnects in the    }
{  middle of a response. (WebSocket: see the pull request.)                 }
{                                                                           }
{  http.sys needs the URL: run as administrator, or reserve it once:        }
{    netsh http add urlacl url=http://+:28797/ user=Everyone                }
{  Another port: environment variable DEXT_HTTPSYS_TEST_PORT.               }
{                                                                           }
{***************************************************************************}
unit Dext.Server.HttpSys.SkipIocp.Tests;

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
  [TestFixture('Dext.Server http.sys with SkipIocpOnSuccess off and on')]
  TDextHttpSysSkipIocpTests = class
  private
    FEngine: IDextServerEngine;
    FPort: Word;
    procedure StartEngine(ASkip: Boolean);
    procedure StopEngine;
    function Connect: TSocket;
    procedure SendBytes(ASocket: TSocket; const ABytes: TBytes);
    procedure SendText(ASocket: TSocket; const AText: string);
    function ReadUntil(ASocket: TSocket; const AEnd: string): string;
    function ReadResponse(ASocket: TSocket): string;
    function ReadChunked(ASocket: TSocket): string;
    procedure CheckLargeBody;
    procedure CheckFlushThenClose;
    procedure CheckDisconnectMidResponse;
  public
    [Test]
    procedure LargeBody_IsReceivedWhole;
    [Test]
    procedure FlushThenClose_SendsEveryPart;
    [Test]
    procedure ClientDisconnectsMidResponse_EngineKeepsServing;
  end;

implementation

const
  DEFAULT_TEST_PORT = 28797;
  CRLF = #13#10;
  // Over 64 KB: the body is received in several HttpReceiveRequestEntityBody.
  LARGE_BODY = 300000;
  // Large enough to be still sending when the client goes away (13 MB).
  BIG_RESPONSE = 200 * 65536;

{ Handler }

procedure HandleRequest(const AConnection: IDextServerConnection;
  const ARequest: IDextRawRequest; const AResponse: IDextRawResponse);
var
  Body: TBytes;
  Stream: TStream;
  Buffer: TBytes;
  Sum: Int64;
  N, I: Integer;
begin
  if ARequest.GetPath = '/sum' then
  begin
    // The length and the sum of the bytes of the body.
    Stream := ARequest.GetBodyStream;
    Stream.Position := 0;
    SetLength(Buffer, 8192);
    Sum := 0;
    repeat
      N := Stream.Read(Buffer[0], Length(Buffer));
      for I := 0 to N - 1 do
        Inc(Sum, Buffer[I]);
    until N <= 0;
    Body := TEncoding.ASCII.GetBytes(IntToStr(Stream.Size) + ' ' + IntToStr(Sum));
    AResponse.SetStatus(200);
    AResponse.SetHeader('Content-Type', 'text/plain');
    AResponse.Write(Body, 0, Length(Body));
  end
  else if ARequest.GetPath = '/stream' then
  begin
    // Two parts with a Flush between them, then Close.
    AResponse.SetStatus(200);
    AResponse.SetHeader('Content-Type', 'text/plain');
    Body := TEncoding.ASCII.GetBytes('first-part;');
    AResponse.Write(Body, 0, Length(Body));
    AResponse.Flush;
    Body := TEncoding.ASCII.GetBytes('second-part');
    AResponse.Write(Body, 0, Length(Body));
    AResponse.Close;
  end
  else if ARequest.GetPath = '/big' then
  begin
    // One large body, sent by Close with its Content-Length: the client can
    // go away while it is being sent.
    AResponse.SetStatus(200);
    AResponse.SetHeader('Content-Type', 'application/octet-stream');
    SetLength(Body, BIG_RESPONSE);
    FillChar(Body[0], BIG_RESPONSE, Ord('x'));
    AResponse.Write(Body, 0, Length(Body));
  end
  else
  begin
    Body := TEncoding.ASCII.GetBytes('ok');
    AResponse.SetStatus(200);
    AResponse.SetHeader('Content-Type', 'text/plain');
    AResponse.Write(Body, 0, Length(Body));
  end;
end;

{ TDextHttpSysSkipIocpTests }

procedure TDextHttpSysSkipIocpTests.StartEngine(ASkip: Boolean);
var
  Options: TServerEngineOptions;
begin
  FPort := StrToIntDef(GetEnvironmentVariable('DEXT_HTTPSYS_TEST_PORT'), DEFAULT_TEST_PORT);
  Options := TServerEngineOptions.Default.WithSkipIocpOnSuccess(ASkip);
  Options.IoThreadCount := 2;
  FEngine := TDextHttpSysEngine.Create(Options);
  FEngine.SetOnRequest(HandleRequest);
  FEngine.Bind('0.0.0.0', FPort);
  FEngine.Start;
end;

procedure TDextHttpSysSkipIocpTests.StopEngine;
begin
  if FEngine <> nil then
    FEngine.Stop;
  FEngine := nil;
end;

function TDextHttpSysSkipIocpTests.Connect: TSocket;
var
  Addr: TSockAddrIn;
  Timeout: DWORD;
begin
  Result := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  Timeout := 5000;
  setsockopt(Result, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(FPort);
  Addr.sin_addr.S_addr := inet_addr('127.0.0.1');
  if Winapi.WinSock2.connect(Result, PSockAddr(@Addr)^, SizeOf(Addr)) <> 0 then
    raise Exception.Create('connect failed: ' + IntToStr(WSAGetLastError));
end;

procedure TDextHttpSysSkipIocpTests.SendBytes(ASocket: TSocket; const ABytes: TBytes);
var
  Sent, N: Integer;
begin
  Sent := 0;
  while Sent < Length(ABytes) do
  begin
    N := send(ASocket, ABytes[Sent], Length(ABytes) - Sent, 0);
    if N <= 0 then
      raise Exception.Create('send failed: ' + IntToStr(WSAGetLastError));
    Inc(Sent, N);
  end;
end;

procedure TDextHttpSysSkipIocpTests.SendText(ASocket: TSocket; const AText: string);
begin
  SendBytes(ASocket, TEncoding.ASCII.GetBytes(AText));
end;

function TDextHttpSysSkipIocpTests.ReadUntil(ASocket: TSocket; const AEnd: string): string;
var
  Ch: AnsiChar;
begin
  // One byte at a time: nothing past AEnd is consumed.
  Result := '';
  while not Result.EndsWith(AEnd) do
  begin
    if recv(ASocket, Ch, 1, 0) <> 1 then
      Break;
    Result := Result + Char(Ch);
  end;
end;

function TDextHttpSysSkipIocpTests.ReadResponse(ASocket: TSocket): string;
var
  Head: string;
  P, Len, I: Integer;
  Ch: AnsiChar;
begin
  Head := ReadUntil(ASocket, CRLF + CRLF);
  Result := Head;
  Len := 0;
  P := Pos('content-length:', LowerCase(Head));
  if P > 0 then
    Len := StrToIntDef(Trim(Copy(Head, P + 15, Pos(#13, Head, P) - P - 15)), 0);
  for I := 1 to Len do
  begin
    if recv(ASocket, Ch, 1, 0) <> 1 then
      Break;
    Result := Result + Char(Ch);
  end;
end;

function TDextHttpSysSkipIocpTests.ReadChunked(ASocket: TSocket): string;
var
  SizeLine: string;
  Size, I: Integer;
  Ch: AnsiChar;
begin
  // The body of a chunked response; '<malformed>' when the framing is wrong.
  Result := '';
  repeat
    SizeLine := ReadUntil(ASocket, CRLF);
    Size := StrToIntDef('$' + Trim(SizeLine), -1);
    if Size < 0 then
      Exit('<malformed: ' + Result + SizeLine + '>');
    for I := 1 to Size do
    begin
      if recv(ASocket, Ch, 1, 0) <> 1 then
        Exit('<malformed: ' + Result + '>');
      Result := Result + Char(Ch);
    end;
    if ReadUntil(ASocket, CRLF) <> CRLF then
      Exit('<malformed: ' + Result + '>');
  until Size = 0;
end;

procedure TDextHttpSysSkipIocpTests.CheckLargeBody;
var
  S: TSocket;
  Body: TBytes;
  Sum: Int64;
  I: Integer;
begin
  SetLength(Body, LARGE_BODY);
  Sum := 0;
  for I := 0 to High(Body) do
  begin
    Body[I] := Byte(I * 7 + 3);
    Inc(Sum, Body[I]);
  end;
  S := Connect;
  try
    SendText(S, 'POST /sum HTTP/1.1' + CRLF + 'Host: x' + CRLF +
      'Content-Length: ' + IntToStr(LARGE_BODY) + CRLF + CRLF);
    SendBytes(S, Body);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith(
      CRLF + IntToStr(LARGE_BODY) + ' ' + IntToStr(Sum));
    // A second one on the same connection.
    SendText(S, 'POST /sum HTTP/1.1' + CRLF + 'Host: x' + CRLF +
      'Content-Length: ' + IntToStr(LARGE_BODY) + CRLF + CRLF);
    SendBytes(S, Body);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith(
      CRLF + IntToStr(LARGE_BODY) + ' ' + IntToStr(Sum));
  finally
    closesocket(S);
  end;
end;

procedure TDextHttpSysSkipIocpTests.CheckFlushThenClose;
var
  S: TSocket;
  Head: string;
begin
  S := Connect;
  try
    SendText(S, 'GET /stream HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Head := ReadUntil(S, CRLF + CRLF);
    Should(Head).StartWith('HTTP/1.1 200');
    // No length at Flush: the body goes chunked, and ends with the last chunk
    Should(Head).Contain('Transfer-Encoding: chunked' + CRLF);
    Should(ReadChunked(S)).Be('first-part;second-part');
    // The response ended where the client thought: the next one on the
    // same connection.
    SendText(S, 'GET /ok HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith(CRLF + 'ok');
  finally
    closesocket(S);
  end;
end;

procedure TDextHttpSysSkipIocpTests.CheckDisconnectMidResponse;
var
  S: TSocket;
  Lingering: TLinger;
  Round, N: Integer;
  Got: Int64;
  Buffer: TBytes;
begin
  // First the whole response, on a connection that stays open: every byte.
  S := Connect;
  try
    SendText(S, 'GET /big HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Should(ReadUntil(S, CRLF + CRLF)).StartWith('HTTP/1.1 200').&And.Contain(
      'Content-Length: ' + IntToStr(BIG_RESPONSE) + CRLF);
    SetLength(Buffer, 65536);
    Got := 0;
    while Got < BIG_RESPONSE do
    begin
      N := recv(S, Buffer[0], Length(Buffer), 0);
      if N <= 0 then
        Break;
      Inc(Got, N);
    end;
    Should(Got).Be(BIG_RESPONSE);
  finally
    closesocket(S);
  end;
  for Round := 1 to 3 do
  begin
    S := Connect;
    SendText(S, 'GET /big HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Should(ReadUntil(S, CRLF + CRLF)).StartWith('HTTP/1.1 200');
    // Some of the body, then the client goes away.
    SetLength(Buffer, 65536);
    recv(S, Buffer[0], Length(Buffer), 0);
    // Abortive close (RST) with most of the response still to come.
    Lingering.l_onoff := 1;
    Lingering.l_linger := 0;
    setsockopt(S, SOL_SOCKET, SO_LINGER, PAnsiChar(@Lingering), SizeOf(Lingering));
    closesocket(S);
  end;
  Sleep(300);
  // The engine still answers.
  S := Connect;
  try
    SendText(S, 'GET /ok HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith(CRLF + 'ok');
  finally
    closesocket(S);
  end;
end;

procedure TDextHttpSysSkipIocpTests.LargeBody_IsReceivedWhole;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckLargeBody;
    finally
      StopEngine;
    end;
  end;
end;

procedure TDextHttpSysSkipIocpTests.FlushThenClose_SendsEveryPart;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckFlushThenClose;
    finally
      StopEngine;
    end;
  end;
end;

procedure TDextHttpSysSkipIocpTests.ClientDisconnectsMidResponse_EngineKeepsServing;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckDisconnectMidResponse;
    finally
      StopEngine;
    end;
  end;
end;

end.
