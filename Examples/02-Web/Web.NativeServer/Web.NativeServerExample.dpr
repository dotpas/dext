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
{  Example project showing usage of the high-performance native server.     }
{                                                                           }
{***************************************************************************}
program Web.NativeServerExample;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Utils,
  System.DateUtils,
  System.SysUtils,
  Dext.WebHost,
  Dext.DI.Interfaces,
  Dext.Web.Interfaces,
  Dext.Web.Results,
  Dext.Web;

var
  Builder: IWebHostBuilder;
  Host: IWebHost;

begin
  try
    SetConsoleCharSet(65001);
    WriteLn('🚀 Dext High-Performance Native Server Example');
    WriteLn('==============================================');
    WriteLn;

    Builder := TDextWebHost.CreateDefaultBuilder;

    Builder.Configure(
      procedure(App: IApplicationBuilder)
      begin
        App.UseMiddleware(TRequestLoggingMiddleware);

        // GET / - Root info
        App.MapGet('/',
          procedure(Context: IHttpContext)
          begin
            Context.Response.Write('Welcome to Dext Native Server Engine!');
          end);

        // GET /health - Health status check
        App.MapGet('/health',
          procedure(Context: IHttpContext)
          begin
            Context.Response.Json('{"status": "healthy", "engine": "native"}');
          end);

        // GET /time - Current time
        App.MapGet('/time',
          procedure(Context: IHttpContext)
          begin
            Context.Response.Write(Format('Server Time: %s', [DateTimeToStr(Now)]));
          end);
      end);

    Host := Builder.Build;

    // Configure Dext to use the Native HTTP.sys / epoll server engine
    (Host as IWebApplication).UseNativeServer;

    // 8080 fica com o Web.SslDemo. http.sys não aceita http://+:8080/ e https://+:8080/ juntos.
    Host.Run(8090);
    Host.Stop;

  except
    on E: Exception do
      WriteLn('❌ Error: ', E.Message);
  end;
  ConsolePause;
end.
