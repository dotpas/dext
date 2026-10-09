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
unit TRestClient_Timeout_Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Net.RestClient,
  Dext.Web,
  Dext.Web.Interfaces;

type
  /// <summary>
  ///   The client Timeout against a real in-process server whose route answers
  ///   after 1.5 s. On Windows THTTPClient (WinHTTP) does not honour its
  ///   ResponseTimeout reliably: of ten identical calls with 300 ms only every
  ///   third one failed (after ~1 s), the others waited the full 1.5 s.
  /// </summary>
  [TestFixture('TRestClient Timeout')]
  TRestClientTimeoutTests = class
  private
    FHost: IWebHost;
    FBaseUrl: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Timeout_FiresOnEveryCall;
    [Test]
    procedure Timeout_TheClientWorksAfterwards;
    [Test]
    procedure Timeout_LongerThanTheServer_DoesNotFire;
    [Test]
    procedure Timeout_FiresOnExecuteIntoToo;
  end;

implementation

const
  SLOW_MS = 1500;
  TIMEOUT_MS = 300;
  // Generous: the point is "not the 1.5 s of the server", on any machine.
  LIMIT_MS = 1000;

procedure Slow(Ctx: IHttpContext);
begin
  Sleep(SLOW_MS);
  Ctx.Response.SetContentType('text/plain');
  Ctx.Response.Write(TEncoding.UTF8.GetBytes('slow'));
end;

procedure Fast(Ctx: IHttpContext);
begin
  Ctx.Response.SetContentType('text/plain');
  Ctx.Response.Write(TEncoding.UTF8.GetBytes('fast'));
end;

{ TRestClientTimeoutTests }

procedure TRestClientTimeoutTests.Setup;
var
  Builder: IWebHostBuilder;
begin
  Builder := TWebHost.CreateDefaultBuilder.UseUrls('http://127.0.0.1:0');
  Builder.Configure(
    procedure(App: IApplicationBuilder)
    begin
      App.MapEndpoint('GET', '/slow', Slow);
      App.MapEndpoint('GET', '/fast', Fast);
    end);
  FHost := Builder.Build;
  FHost.Start;
  FBaseUrl := 'http://localhost:' + FHost.Port.ToString;
end;

procedure TRestClientTimeoutTests.TearDown;
begin
  FHost.Stop;
  FHost := nil;
end;

procedure TRestClientTimeoutTests.Timeout_FiresOnEveryCall;
var
  I, Fired: Integer;
  Sw: TStopwatch;
  Slowest: Int64;
begin
  Fired := 0;
  Slowest := 0;
  for I := 1 to 6 do
  begin
    Sw := TStopwatch.StartNew;
    try
      RestClient(FBaseUrl).Timeout(TIMEOUT_MS).Get('/slow').Await;
    except
      Inc(Fired);
    end;
    if Sw.ElapsedMilliseconds > Slowest then
      Slowest := Sw.ElapsedMilliseconds;
  end;
  Should(Fired).Be(6);
  Should(Slowest < LIMIT_MS).BeTrue;
end;

procedure TRestClientTimeoutTests.Timeout_TheClientWorksAfterwards;
var
  Resp: IRestResponse;
begin
  try
    RestClient(FBaseUrl).Timeout(TIMEOUT_MS).Get('/slow').Await;
  except
    // expected
  end;
  // The engines come from a shared pool: the one that timed out serves again.
  Resp := RestClient(FBaseUrl).Timeout(5000).Get('/fast').Await;
  Should(Resp.StatusCode).Be(200);
  Should(Resp.ContentString).Be('fast');
end;

procedure TRestClientTimeoutTests.Timeout_LongerThanTheServer_DoesNotFire;
var
  Resp: IRestResponse;
begin
  Resp := RestClient(FBaseUrl).Timeout(SLOW_MS * 3).Get('/slow').Await;
  Should(Resp.StatusCode).Be(200);
  Should(Resp.ContentString).Be('slow');
end;

procedure TRestClientTimeoutTests.Timeout_FiresOnExecuteIntoToo;
var
  I, Fired: Integer;
  Target: TMemoryStream;
  Sw: TStopwatch;
  Slowest: Int64;
begin
  Fired := 0;
  Slowest := 0;
  Target := TMemoryStream.Create;
  try
    for I := 1 to 3 do
    begin
      Sw := TStopwatch.StartNew;
      try
        RestClient(FBaseUrl).Timeout(TIMEOUT_MS).GetInto('/slow', Target).Await;
      except
        Inc(Fired);
      end;
      if Sw.ElapsedMilliseconds > Slowest then
        Slowest := Sw.ElapsedMilliseconds;
    end;
  finally
    Target.Free;
  end;
  Should(Fired).Be(3);
  Should(Slowest < LIMIT_MS).BeTrue;
end;

end.
