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
{  Tests of the worker idle hook (DextWorkerIdle) on the IOCP socket        }
{  engine, on a local port driven by a raw TCP client: called once per idle }
{  period on a worker that handled work, never on a worker that did not,    }
{  and an exception from the hook does not end the worker.                  }
{                                                                           }
{***************************************************************************}
unit Dext.Server.WorkerIdle.Tests;

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
  Dext.Server.Iocp;

type
  [TestFixture('Dext.Server worker idle hook (IOCP engine on a local port)')]
  TDextWorkerIdleTests = class
  private
    FEngine: IDextServerEngine;
    procedure StartEngine(APort: Word; AHook: TDextWorkerIdleProc);
    procedure StopEngine;
    function Get(APort: Word): string;
  public
    [Test]
    procedure Idle_NotCalledBeforeAnyWork;
    [Test]
    procedure Idle_CalledOncePerIdlePeriodAfterWork;
    [Test]
    procedure Idle_ExceptionDoesNotEndTheWorker;
  end;

implementation

const
  TEST_PORT = 28795;
  IDLE_MS = 100;
  CRLF = #13#10;

var
  IdleCalls: Integer;

procedure CountIdle;
begin
  TInterlocked.Increment(IdleCalls);
end;

procedure CountIdleAndRaise;
begin
  TInterlocked.Increment(IdleCalls);
  raise Exception.Create('idle hook failure');
end;

{ TDextWorkerIdleTests }

procedure TDextWorkerIdleTests.StartEngine(APort: Word; AHook: TDextWorkerIdleProc);
var
  Options: TServerEngineOptions;
begin
  IdleCalls := 0;
  DextWorkerIdle := AHook;
  DextWorkerIdleMs := IDLE_MS;
  Options := TServerEngineOptions.Default;
  // One worker: the accept and the request completions all reach it, so the
  // number of idle calls is exact.
  Options.IoThreadCount := 1;
  FEngine := TDextIocpEngine.Create(Options);
  FEngine.SetOnRequest(
    procedure(const AConnection: IDextServerConnection; const ARequest: IDextRawRequest;
      const AResponse: IDextRawResponse)
    var
      Body: TBytes;
    begin
      Body := TEncoding.ASCII.GetBytes('ok');
      AResponse.SetStatus(200);
      AResponse.SetHeader('Content-Type', 'text/plain');
      AResponse.Write(Body, 0, Length(Body));
    end);
  FEngine.Bind('127.0.0.1', APort);
  FEngine.Start;
end;

procedure TDextWorkerIdleTests.StopEngine;
begin
  try
    if FEngine <> nil then
      FEngine.Stop;
    FEngine := nil;
  finally
    DextWorkerIdle := nil;
    DextWorkerIdleMs := 1000;
  end;
end;

function TDextWorkerIdleTests.Get(APort: Word): string;
var
  S: TSocket;
  Addr: TSockAddrIn;
  Timeout: DWORD;
  Bytes: TBytes;
  Ch: AnsiChar;
begin
  // One request on a new connection with Connection: close, read to the end.
  Result := '';
  S := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  try
    Timeout := 3000;
    setsockopt(S, SOL_SOCKET, SO_RCVTIMEO, PAnsiChar(@Timeout), SizeOf(Timeout));
    FillChar(Addr, SizeOf(Addr), 0);
    Addr.sin_family := AF_INET;
    Addr.sin_port := htons(APort);
    Addr.sin_addr.S_addr := inet_addr('127.0.0.1');
    if Winapi.WinSock2.connect(S, PSockAddr(@Addr)^, SizeOf(Addr)) <> 0 then
      raise Exception.Create('connect failed: ' + IntToStr(WSAGetLastError));
    Bytes := TEncoding.ASCII.GetBytes('GET / HTTP/1.1' + CRLF + 'Host: x' + CRLF +
      'Connection: close' + CRLF + CRLF);
    send(S, Bytes[0], Length(Bytes), 0);
    while not Result.EndsWith(CRLF + CRLF + 'ok') do
    begin
      if recv(S, Ch, 1, 0) <> 1 then
        Break;
      Result := Result + Char(Ch);
    end;
  finally
    closesocket(S);
  end;
end;

procedure TDextWorkerIdleTests.Idle_NotCalledBeforeAnyWork;
begin
  StartEngine(TEST_PORT, CountIdle);
  try
    Sleep(IDLE_MS * 5);
    Should(IdleCalls).Be(0);
  finally
    StopEngine;
  end;
end;

procedure TDextWorkerIdleTests.Idle_CalledOncePerIdlePeriodAfterWork;
begin
  StartEngine(TEST_PORT + 1, CountIdle);
  try
    Should(Get(TEST_PORT + 1)).StartWith('HTTP/1.1 200');
    // Several timeouts go by: the hook runs once, not once per timeout.
    Sleep(IDLE_MS * 6);
    Should(IdleCalls).Be(1);
    Should(Get(TEST_PORT + 1)).StartWith('HTTP/1.1 200');
    Sleep(IDLE_MS * 6);
    Should(IdleCalls).Be(2);
  finally
    StopEngine;
  end;
end;

procedure TDextWorkerIdleTests.Idle_ExceptionDoesNotEndTheWorker;
begin
  StartEngine(TEST_PORT + 2, CountIdleAndRaise);
  try
    Should(Get(TEST_PORT + 2)).StartWith('HTTP/1.1 200');
    Sleep(IDLE_MS * 4);
    Should(IdleCalls).Be(1);
    // The only worker raised in the hook: it must still answer.
    Should(Get(TEST_PORT + 2)).StartWith('HTTP/1.1 200');
  finally
    StopEngine;
  end;
end;

end.
