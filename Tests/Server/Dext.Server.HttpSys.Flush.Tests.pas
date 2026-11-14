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
{  Windows only. Tests of Flush followed by Write on the raw http.sys       }
{  engine, on a local port driven by a raw TCP client, each one with        }
{  SkipIocpOnSuccess off and on: every part arrives, and the client can     }
{  tell where the response ends (chunked on HTTP/1.1, the connection        }
{  closed on HTTP/1.0, the Content-Length when the handler gave one).       }
{  WriteFile too: after Flush the file goes in a chunk of its own, and      }
{  without Flush the body written before goes first.                        }
{                                                                           }
{  The port needs an http.sys URL reservation, or run as administrator.    }
{  Another port: environment variable DEXT_HTTPSYS_TEST_PORT.               }
{                                                                           }
{***************************************************************************}
unit Dext.Server.HttpSys.Flush.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows,
  Winapi.WinSock2,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Server.Engine.Types,
  Dext.Server.Engine.Interfaces,
  Dext.Server.HttpSys;

type
  [TestFixture('Dext.Server http.sys Flush then Write (local port)')]
  THttpSysFlushTests = class
  private
    FEngine: IDextServerEngine;
    FPort: Word;
    procedure StartEngine(ASkip: Boolean);
    procedure StopEngine;
    function Connect: TSocket;
    procedure SendText(ASocket: TSocket; const AText: string);
    function ReadUntil(ASocket: TSocket; const AEnd: string): string;
    function ReadChunked(ASocket: TSocket): string;
    function ReadToEnd(ASocket: TSocket; out AClosed: Boolean): string;
    function ReadCount(ASocket: TSocket; ACount: Integer): string;
    procedure CheckOkOnSameConnection(ASocket: TSocket);
    procedure CheckChunked(const APath, AExpected: string);
    procedure CheckHttp10(const APath, AExpected: string);
    procedure CheckContentLength(const APath, AExpected: string);
  public
    [Test]
    procedure FlushThenWrite_Http11_ChunkedAndKeepAlive;
    [Test]
    procedure FlushOnly_Http11_ChunkedAndKeepAlive;
    [Test]
    procedure FlushThenWrite_Http10_EndsWithTheConnection;
    [Test]
    procedure FlushThenWrite_WithContentLength_NotChunked;
    [Test]
    procedure FlushThenWriteFile_Http11_FileInItsOwnChunk;
    [Test]
    procedure FlushThenWriteFile_EmptyFile_BodyGoesOn;
    [Test]
    procedure FlushThenWriteFile_Http10_EndsWithTheConnection;
    [Test]
    procedure WriteThenWriteFile_BodyFirst_LengthOfBoth;
  end;

implementation

const
  DEFAULT_TEST_PORT = 28796;
  CRLF = #13#10;
  ALL_PARTS = 'part1;part2;part3;part4;';
  FILE_TEXT = 'the file;';

var
  GError: string;
  GLock: TCriticalSection;
  GFile: string;
  GEmptyFile: string;

procedure AddError(const AText: string);
begin
  GLock.Enter;
  try
    GError := GError + AText + '; ';
  finally
    GLock.Leave;
  end;
end;

procedure WritePart(const AResponse: IDextRawResponse; const AText: string);
var
  B: TBytes;
begin
  B := TEncoding.ASCII.GetBytes(AText);
  AResponse.Write(B, 0, Length(B));
end;

procedure HandleRequest(const AConnection: IDextServerConnection;
  const ARequest: IDextRawRequest; const AResponse: IDextRawResponse);
var
  I: Integer;
begin
  try
    if (ARequest.GetPath = '/parts') or (ARequest.GetPath = '/parts-length') then
    begin
      // Four parts, Flush after the first one
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      if ARequest.GetPath = '/parts-length' then
        AResponse.SetHeader('Content-Length', IntToStr(Length(ALL_PARTS)));
      for I := 1 to 4 do
      begin
        WritePart(AResponse, 'part' + IntToStr(I) + ';');
        if I = 1 then
          AResponse.Flush;
      end;
    end
    else if (ARequest.GetPath = '/flush-file') or
      (ARequest.GetPath = '/flush-empty-file') then
    begin
      // Write, Flush, WriteFile, Write
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      WritePart(AResponse, 'head;');
      AResponse.Flush;
      if ARequest.GetPath = '/flush-file' then
        AResponse.WriteFile(GFile, 0, 0)
      else
        AResponse.WriteFile(GEmptyFile, 0, 0);
      WritePart(AResponse, 'tail;');
    end
    else if ARequest.GetPath = '/write-file' then
    begin
      // Write, then WriteFile without Flush
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      WritePart(AResponse, 'head;');
      AResponse.WriteFile(GFile, 0, 0);
    end
    else if ARequest.GetPath = '/flush-only' then
    begin
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      WritePart(AResponse, 'only');
      AResponse.Flush;
    end
    else
    begin
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      WritePart(AResponse, 'ok');
    end;
  except
    on E: Exception do
      AddError(ARequest.GetPath + ': ' + E.Message);
  end;
end;

{ THttpSysFlushTests }

procedure THttpSysFlushTests.StartEngine(ASkip: Boolean);
var
  Data: TWSAData;
  Options: TServerEngineOptions;
begin
  WSAStartup($0202, Data);
  GError := '';
  FPort := StrToIntDef(GetEnvironmentVariable('DEXT_HTTPSYS_TEST_PORT'), DEFAULT_TEST_PORT);
  Options := TServerEngineOptions.Default.WithSkipIocpOnSuccess(ASkip);
  Options.IoThreadCount := 2;
  FEngine := TDextHttpSysEngine.Create(Options);
  FEngine.SetOnRequest(HandleRequest);
  FEngine.Bind('0.0.0.0', FPort);
  FEngine.Start;
end;

procedure THttpSysFlushTests.StopEngine;
begin
  if FEngine <> nil then
    FEngine.Stop;
  FEngine := nil;
end;

function THttpSysFlushTests.Connect: TSocket;
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

procedure THttpSysFlushTests.SendText(ASocket: TSocket; const AText: string);
var
  B: TBytes;
begin
  B := TEncoding.ASCII.GetBytes(AText);
  send(ASocket, B[0], Length(B), 0);
end;

function THttpSysFlushTests.ReadUntil(ASocket: TSocket; const AEnd: string): string;
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

function THttpSysFlushTests.ReadCount(ASocket: TSocket; ACount: Integer): string;
var
  Ch: AnsiChar;
  I: Integer;
begin
  Result := '';
  for I := 1 to ACount do
  begin
    if recv(ASocket, Ch, 1, 0) <> 1 then
      Break;
    Result := Result + Char(Ch);
  end;
end;

function THttpSysFlushTests.ReadChunked(ASocket: TSocket): string;
var
  SizeLine: string;
  Size: Integer;
begin
  // The body of a chunked response; '<malformed>' when the framing is wrong
  Result := '';
  repeat
    SizeLine := ReadUntil(ASocket, CRLF);
    if not SizeLine.EndsWith(CRLF) then
      Exit('<malformed: ' + Result + SizeLine + '>');
    Size := StrToIntDef('$' + Trim(SizeLine), -1);
    if Size < 0 then
      Exit('<malformed: ' + Result + SizeLine + '>');
    if Size > 0 then
      Result := Result + ReadCount(ASocket, Size);
    if ReadCount(ASocket, 2) <> CRLF then
      Exit('<malformed: ' + Result + '>');
  until Size = 0;
end;

function THttpSysFlushTests.ReadToEnd(ASocket: TSocket; out AClosed: Boolean): string;
var
  Ch: AnsiChar;
  N: Integer;
begin
  // Up to the end of the connection (AClosed) or the receive timeout
  Result := '';
  AClosed := False;
  repeat
    N := recv(ASocket, Ch, 1, 0);
    if N = 1 then
      Result := Result + Char(Ch);
  until N <> 1;
  AClosed := N = 0;
end;

procedure THttpSysFlushTests.CheckOkOnSameConnection(ASocket: TSocket);
var
  Head: string;
begin
  // The response before ended where the client thought: the connection
  // carries the next one.
  SendText(ASocket, 'GET /ok HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
  Head := ReadUntil(ASocket, CRLF + CRLF);
  Should(Head).StartWith('HTTP/1.1 200');
  Should(Head).Contain('Content-Length: 2' + CRLF);
  Should(ReadCount(ASocket, 2)).Be('ok');
end;

procedure THttpSysFlushTests.CheckChunked(const APath, AExpected: string);
var
  S: TSocket;
  Head: string;
begin
  S := Connect;
  try
    SendText(S, 'GET ' + APath + ' HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Head := ReadUntil(S, CRLF + CRLF);
    Should(Head).StartWith('HTTP/1.1 200');
    Should(Head).Contain('Transfer-Encoding: chunked' + CRLF);
    Should(Head).NotContain('Content-Length');
    Should(ReadChunked(S)).Be(AExpected);
    CheckOkOnSameConnection(S);
  finally
    closesocket(S);
  end;
end;

procedure THttpSysFlushTests.CheckHttp10(const APath, AExpected: string);
var
  S: TSocket;
  Head: string;
  Closed: Boolean;
begin
  S := Connect;
  try
    SendText(S, 'GET ' + APath + ' HTTP/1.0' + CRLF + 'Host: x' + CRLF + CRLF);
    Head := ReadUntil(S, CRLF + CRLF);
    Should(Head).StartWith('HTTP/1.');
    Should(Head).NotContain('chunked');
    Should(ReadToEnd(S, Closed)).Be(AExpected);
    Should(Closed).BeTrue;
  finally
    closesocket(S);
  end;
end;

procedure THttpSysFlushTests.CheckContentLength(const APath, AExpected: string);
var
  S: TSocket;
  Head: string;
begin
  S := Connect;
  try
    SendText(S, 'GET ' + APath + ' HTTP/1.1' + CRLF + 'Host: x' + CRLF + CRLF);
    Head := ReadUntil(S, CRLF + CRLF);
    Should(Head).StartWith('HTTP/1.1 200');
    Should(Head).Contain('Content-Length: ' + IntToStr(Length(AExpected)) + CRLF);
    Should(Head).NotContain('chunked');
    Should(ReadCount(S, Length(AExpected))).Be(AExpected);
    CheckOkOnSameConnection(S);
  finally
    closesocket(S);
  end;
end;

procedure THttpSysFlushTests.FlushThenWrite_Http11_ChunkedAndKeepAlive;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckChunked('/parts', ALL_PARTS);
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.FlushOnly_Http11_ChunkedAndKeepAlive;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckChunked('/flush-only', 'only');
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.FlushThenWrite_Http10_EndsWithTheConnection;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckHttp10('/parts', ALL_PARTS);
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.FlushThenWrite_WithContentLength_NotChunked;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckContentLength('/parts-length', ALL_PARTS);
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.FlushThenWriteFile_Http11_FileInItsOwnChunk;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckChunked('/flush-file', 'head;' + FILE_TEXT + 'tail;');
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.FlushThenWriteFile_EmptyFile_BodyGoesOn;
var
  Skip: Boolean;
begin
  // An empty chunk is the last chunk: an empty file must not end the body
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckChunked('/flush-empty-file', 'head;tail;');
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.FlushThenWriteFile_Http10_EndsWithTheConnection;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckHttp10('/flush-file', 'head;' + FILE_TEXT + 'tail;');
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

procedure THttpSysFlushTests.WriteThenWriteFile_BodyFirst_LengthOfBoth;
var
  Skip: Boolean;
begin
  for Skip := False to True do
  begin
    StartEngine(Skip);
    try
      CheckContentLength('/write-file', 'head;' + FILE_TEXT);
      Should(GError).Be('');
    finally
      StopEngine;
    end;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GFile := TPath.GetTempFileName;
  TFile.WriteAllText(GFile, FILE_TEXT, TEncoding.ASCII);
  GEmptyFile := TPath.GetTempFileName;

finalization
  System.SysUtils.DeleteFile(GFile);
  System.SysUtils.DeleteFile(GEmptyFile);
  GLock.Free;

end.
