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
{  Tests of the IOCP socket engine on Windows: the request parser with the  }
{  checks a server facing the network needs (RFC 9112), and the engine on   }
{  a local port driven by a raw TCP client (limits, Connection: close,      }
{  HTTP/1.0, Expect: 100-continue, the Date header, keep-alive).            }
{                                                                           }
{***************************************************************************}
unit Dext.Server.Iocp.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.WinSock2,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Server.Engine.Types,
  Dext.Server.Engine.Interfaces,
  Dext.Server.Iocp.HttpParser,
  Dext.Server.Iocp;

type
  [TestFixture('Dext.Server IOCP request parser')]
  TDextIocpParserTests = class
  private
    function Parse(const ARequest: string; AMaxHeader: Integer = 0): TDextHttpParseResult; overload;
    function Parse(const ARequest: string; out AInfo: TDextHttpRequestInfo;
      out AContentLength: Int64): TDextHttpParseResult; overload;
  public
    [Test]
    procedure ValidRequest_IsOk;
    [Test]
    procedure IncompleteHeaders_AreIncomplete;
    [Test]
    procedure Http10WithoutHeaders_IsComplete;
    [Test]
    procedure ContentLengthWithLetters_IsBadRequest;
    [Test]
    procedure ContentLengthNegative_IsBadRequest;
    [Test]
    procedure ContentLengthRepeatedWithAnotherValue_IsBadRequest;
    [Test]
    procedure ContentLengthRepeatedWithSameValue_IsOk;
    [Test]
    procedure TransferEncoding_IsNotImplemented;
    [Test]
    procedure TransferEncodingWithContentLength_IsBadRequest;
    [Test]
    procedure HeaderWithoutColon_IsBadRequest;
    [Test]
    procedure WhitespaceBeforeColon_IsBadRequest;
    [Test]
    procedure ObsoleteLineFolding_IsBadRequest;
    [Test]
    procedure MalformedRequestLine_IsBadRequest;
    [Test]
    procedure UnknownHttpVersion_IsVersionNotSupported;
    [Test]
    procedure IncompleteHeadersOverTheLimit_AreTooLarge;
    [Test]
    procedure CompleteHeadersOverTheLimit_AreTooLarge;
    [Test]
    procedure ConnectionAndExpect_AreReported;
  end;

  [TestFixture('Dext.Server IOCP engine on a local port')]
  TDextIocpEngineTests = class
  private
    FEngine: IDextServerEngine;
    function Connect: TSocket;
    procedure SendText(ASocket: TSocket; const AText: string);
    function ReadResponse(ASocket: TSocket): string;
    function ReadUntil(ASocket: TSocket; const AEnd: string): string;
    function PeerClosed(ASocket: TSocket): Boolean;
  public
    [BeforeAll]
    procedure StartEngine;
    [AfterAll]
    procedure StopEngine;

    [Test]
    procedure KeepAlive_TwoRequestsOnOneConnection;
    [Test]
    procedure Response_HasDateHeader;
    [Test]
    procedure ConnectionClose_IsHonoured;
    [Test]
    procedure Http10_ClosesAfterTheResponse;
    [Test]
    procedure ExpectContinue_Gets100BeforeTheBody;
    [Test]
    procedure BodyOverTheLimit_Gets413AndClose;
    [Test]
    procedure HeadersOverTheLimit_Get431AndClose;
    [Test]
    procedure BadContentLength_Gets400AndClose;
    [Test]
    procedure ChunkedBody_Gets501AndClose;
  end;

implementation

const
  TEST_PORT = 28791;
  TEST_MAX_HEADER = 4096;
  TEST_MAX_BODY = 1024;
  CRLF = #13#10;

{ TDextIocpParserTests }

function TDextIocpParserTests.Parse(const ARequest: string; AMaxHeader: Integer): TDextHttpParseResult;
var
  Buffer: TBytes;
  Method, Path, Query: string;
  Segments: THeaderSegments;
  BodyOffset: Integer;
  ContentLength: Int64;
  Info: TDextHttpRequestInfo;
begin
  Buffer := TEncoding.ASCII.GetBytes(ARequest);
  Result := TDextIocpHttpParser.TryParseRequestEx(Buffer, Length(Buffer), AMaxHeader, Method, Path,
    Query, Segments, BodyOffset, ContentLength, Info);
end;

function TDextIocpParserTests.Parse(const ARequest: string; out AInfo: TDextHttpRequestInfo;
  out AContentLength: Int64): TDextHttpParseResult;
var
  Buffer: TBytes;
  Method, Path, Query: string;
  Segments: THeaderSegments;
  BodyOffset: Integer;
begin
  Buffer := TEncoding.ASCII.GetBytes(ARequest);
  Result := TDextIocpHttpParser.TryParseRequestEx(Buffer, Length(Buffer), 0, Method, Path,
    Query, Segments, BodyOffset, AContentLength, AInfo);
end;

procedure TDextIocpParserTests.ValidRequest_IsOk;
var
  Info: TDextHttpRequestInfo;
  Len: Int64;
begin
  Should(Ord(Parse('POST /a?b=1 HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Content-Length: 5' + CRLF + CRLF + 'hello',
    Info, Len))).Be(Ord(hprOk));
  Should(Len).Be(Int64(5));
  Should(Info.Http10).BeFalse;
end;

procedure TDextIocpParserTests.IncompleteHeaders_AreIncomplete;
begin
  Should(Ord(Parse('GET / HTTP/1.1' + CRLF + 'Host: x' + CRLF))).Be(Ord(hprIncomplete));
end;

procedure TDextIocpParserTests.Http10WithoutHeaders_IsComplete;
var
  Info: TDextHttpRequestInfo;
  Len: Int64;
begin
  Should(Ord(Parse('GET / HTTP/1.0' + CRLF + CRLF, Info, Len))).Be(Ord(hprOk));
  Should(Info.Http10).BeTrue;
end;

procedure TDextIocpParserTests.ContentLengthWithLetters_IsBadRequest;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Content-Length: 12abc' + CRLF + CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.ContentLengthNegative_IsBadRequest;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Content-Length: -5' + CRLF + CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.ContentLengthRepeatedWithAnotherValue_IsBadRequest;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Content-Length: 5' + CRLF + 'Content-Length: 6' + CRLF + CRLF)))
    .Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.ContentLengthRepeatedWithSameValue_IsOk;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Content-Length: 5' + CRLF + 'Content-Length: 5' + CRLF + CRLF)))
    .Be(Ord(hprOk));
end;

procedure TDextIocpParserTests.TransferEncoding_IsNotImplemented;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Transfer-Encoding: chunked' + CRLF + CRLF)))
    .Be(Ord(hprNotImplemented));
end;

procedure TDextIocpParserTests.TransferEncodingWithContentLength_IsBadRequest;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Content-Length: 5' + CRLF + 'Transfer-Encoding: chunked' + CRLF +
    CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.HeaderWithoutColon_IsBadRequest;
begin
  Should(Ord(Parse('GET / HTTP/1.1' + CRLF + 'Host x' + CRLF + CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.WhitespaceBeforeColon_IsBadRequest;
begin
  Should(Ord(Parse('POST / HTTP/1.1' + CRLF + 'Content-Length : 5' + CRLF + CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.ObsoleteLineFolding_IsBadRequest;
begin
  Should(Ord(Parse('GET / HTTP/1.1' + CRLF + 'X-A: 1' + CRLF + ' 2' + CRLF + CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.MalformedRequestLine_IsBadRequest;
begin
  Should(Ord(Parse('GARBAGE' + CRLF + 'Host: x' + CRLF + CRLF))).Be(Ord(hprBadRequest));
  Should(Ord(Parse('GET  / HTTP/1.1' + CRLF + CRLF))).Be(Ord(hprBadRequest));
  Should(Ord(Parse('GET / HTTP/1.1 extra' + CRLF + CRLF))).Be(Ord(hprBadRequest));
end;

procedure TDextIocpParserTests.UnknownHttpVersion_IsVersionNotSupported;
begin
  Should(Ord(Parse('GET / HTTP/2.0' + CRLF + CRLF))).Be(Ord(hprVersionNotSupported));
end;

procedure TDextIocpParserTests.IncompleteHeadersOverTheLimit_AreTooLarge;
begin
  Should(Ord(Parse('GET / HTTP/1.1' + CRLF + 'X-A: ' + StringOfChar('a', 200), 100)))
    .Be(Ord(hprHeadersTooLarge));
end;

procedure TDextIocpParserTests.CompleteHeadersOverTheLimit_AreTooLarge;
begin
  Should(Ord(Parse('GET / HTTP/1.1' + CRLF + 'X-A: ' + StringOfChar('a', 200) + CRLF + CRLF, 100)))
    .Be(Ord(hprHeadersTooLarge));
end;

procedure TDextIocpParserTests.ConnectionAndExpect_AreReported;
var
  Info: TDextHttpRequestInfo;
  Len: Int64;
begin
  Parse('POST / HTTP/1.1' + CRLF + 'Connection: Upgrade, Close' + CRLF + 'Expect: 100-continue' + CRLF +
    'Content-Length: 3' + CRLF + CRLF, Info, Len);
  Should(Info.ConnectionClose).BeTrue;
  Should(Info.ExpectContinue).BeTrue;
  Parse('GET / HTTP/1.0' + CRLF + 'Connection: keep-alive' + CRLF + CRLF, Info, Len);
  Should(Info.Http10).BeTrue;
  Should(Info.ConnectionKeepAlive).BeTrue;
  Should(Info.ConnectionClose).BeFalse;
end;

{ TDextIocpEngineTests }

procedure TDextIocpEngineTests.StartEngine;
var
  Options: TServerEngineOptions;
begin
  Options := TServerEngineOptions.Default;
  Options.IoThreadCount := 2;
  Options.MaxRequestHeaderSize := TEST_MAX_HEADER;
  Options.MaxRequestBodySize := TEST_MAX_BODY;
  FEngine := TDextIocpEngine.Create(Options);
  FEngine.SetOnRequest(
    procedure(const AConnection: IDextServerConnection; const ARequest: IDextRawRequest;
      const AResponse: IDextRawResponse)
    var
      Body: TBytes;
    begin
      // Answers with the method and the length of the body it received.
      Body := TEncoding.ASCII.GetBytes(ARequest.GetMethod + ' ' + IntToStr(ARequest.GetBodyStream.Size));
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      AResponse.Write(Body, 0, Length(Body));
    end);
  FEngine.Bind('127.0.0.1', TEST_PORT);
  FEngine.Start;
end;

procedure TDextIocpEngineTests.StopEngine;
begin
  if FEngine <> nil then
    FEngine.Stop;
  FEngine := nil;
end;

function TDextIocpEngineTests.Connect: TSocket;
var
  Addr: TSockAddrIn;
  Timeout: DWORD;
begin
  Result := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  Timeout := 3000;
  setsockopt(Result, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
  FillChar(Addr, SizeOf(Addr), 0);
  Addr.sin_family := AF_INET;
  Addr.sin_port := htons(TEST_PORT);
  Addr.sin_addr.S_addr := inet_addr('127.0.0.1');
  if Winapi.WinSock2.connect(Result, PSockAddr(@Addr)^, SizeOf(Addr)) <> 0 then
    raise Exception.Create('connect failed: ' + IntToStr(WSAGetLastError));
end;

procedure TDextIocpEngineTests.SendText(ASocket: TSocket; const AText: string);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.ASCII.GetBytes(AText);
  if Length(Bytes) > 0 then
    send(ASocket, Bytes[0], Length(Bytes), 0);
end;

function TDextIocpEngineTests.ReadUntil(ASocket: TSocket; const AEnd: string): string;
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

function TDextIocpEngineTests.ReadResponse(ASocket: TSocket): string;
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

function TDextIocpEngineTests.PeerClosed(ASocket: TSocket): Boolean;
var
  Ch: AnsiChar;
  R: Integer;
begin
  // 0 = orderly close; a timeout (-1) means the connection is still open.
  R := recv(ASocket, Ch, 1, 0);
  Result := R = 0;
end;

procedure TDextIocpEngineTests.KeepAlive_TwoRequestsOnOneConnection;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'GET /a HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith('GET 0');
    SendText(S, 'POST /b HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Content-Length: 3' + CRLF + CRLF + 'abc');
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith('POST 3');
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.Response_HasDateHeader;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'GET / HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Should(ReadResponse(S)).MatchRegex('\r\nDate: [A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT\r\n');
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.ConnectionClose_IsHonoured;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'GET / HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Connection: close' + CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.Contain('Connection: close' + CRLF);
    Should(PeerClosed(S)).BeTrue;
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.Http10_ClosesAfterTheResponse;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'GET / HTTP/1.0' + CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith('GET 0');
    Should(PeerClosed(S)).BeTrue;
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.ExpectContinue_Gets100BeforeTheBody;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'POST / HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Content-Length: 5' + CRLF +
      'Expect: 100-continue' + CRLF + CRLF);
    Should(ReadUntil(S, CRLF + CRLF)).Be('HTTP/1.1 100 Continue' + CRLF + CRLF);
    SendText(S, 'hello');
    Should(ReadResponse(S)).StartWith('HTTP/1.1 200').&And.EndWith('POST 5');
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.BodyOverTheLimit_Gets413AndClose;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'POST / HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Content-Length: ' + IntToStr(TEST_MAX_BODY + 1) +
      CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 413');
    Should(PeerClosed(S)).BeTrue;
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.HeadersOverTheLimit_Get431AndClose;
var
  S: TSocket;
begin
  S := Connect;
  try
    // A header block that never ends: the server must not wait for it forever.
    SendText(S, 'GET / HTTP/1.1' + CRLF + 'X-A: ' + StringOfChar('a', TEST_MAX_HEADER + 100));
    Should(ReadResponse(S)).StartWith('HTTP/1.1 431');
    Should(PeerClosed(S)).BeTrue;
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.BadContentLength_Gets400AndClose;
var
  S: TSocket;
begin
  S := Connect;
  try
    SendText(S, 'POST / HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Content-Length: 3x' + CRLF + CRLF + 'abc');
    Should(ReadResponse(S)).StartWith('HTTP/1.1 400');
    Should(PeerClosed(S)).BeTrue;
  finally
    closesocket(S);
  end;
end;

procedure TDextIocpEngineTests.ChunkedBody_Gets501AndClose;
var
  S: TSocket;
begin
  S := Connect;
  try
    // Before: the chunked body was taken as the next request on the connection.
    SendText(S, 'POST / HTTP/1.1' + CRLF + 'Host: x' + CRLF + 'Transfer-Encoding: chunked' + CRLF + CRLF +
      '3' + CRLF + 'abc' + CRLF + '0' + CRLF + CRLF);
    Should(ReadResponse(S)).StartWith('HTTP/1.1 501');
    Should(PeerClosed(S)).BeTrue;
  finally
    closesocket(S);
  end;
end;

end.
