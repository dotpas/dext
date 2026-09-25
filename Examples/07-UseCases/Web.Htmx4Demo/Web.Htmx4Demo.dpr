{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
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
{  Example: HTMX 4 multi-target partial responses with Dext.                }
{                                                                           }
{  Demonstrates Dext.Web.Htmx:                                              }
{    - Htmx.Request  : inspect HX-Request-Type (partial / full)             }
{    - Htmx.Partials : build several <hx-partial> elements in one response  }
{                                                                           }
{  Open http://localhost:5299/ and use the buttons; the "Load invoices"     }
{  request answers with two <hx-partial> elements that update the grid and  }
{  the counter with a single response.                                      }
{                                                                           }
{***************************************************************************}
program Web.Htmx4Demo;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Utils,
  System.SyncObjs,
  System.SysUtils,
  Dext.WebHost,
  Dext.DI.Interfaces,
  Dext.Web.Interfaces,
  Dext.Web.Results,
  Dext.Web,
  Dext.Web.Htmx;

const
  DemoPort = 5299;

var
  Builder: IWebHostBuilder;
  Host: IWebHost;
  fRequestCounter: Integer = 0;

function GreetingPage: string;
begin
  Result :=
    '<!DOCTYPE html>' + sLineBreak +
    '<html lang="en">' + sLineBreak +
    '<head>' + sLineBreak +
    '  <meta charset="utf-8">' + sLineBreak +
    '  <title>Dext HTMX 4 Demo</title>' + sLineBreak +
    '  <script src="https://cdn.jsdelivr.net/npm/htmx.org@4.0.0" ' +
    'integrity="sha384-BvJpBiO8Kh31EqtJe5DRIeWrHWnCGkwytKs9NKFi86Hhw96dEqdEMzZDeK9iEGTc" ' +
    'crossorigin="anonymous"></script>' + sLineBreak +
    '  <style>' + sLineBreak +
    '    body { font-family: Segoe UI, sans-serif; margin: 2rem auto; max-width: 720px; }' + sLineBreak +
    '    button { margin-right: .5rem; padding: .4rem 1rem; }' + sLineBreak +
    '    #invoice-grid { border: 1px solid #ccc; min-height: 3rem; padding: .5rem; }' + sLineBreak +
    '    #invoice-count { color: #0a7; font-weight: 600; }' + sLineBreak +
    '    table { width: 100%; border-collapse: collapse; }' + sLineBreak +
    '    td { border-bottom: 1px solid #eee; padding: .25rem .5rem; }' + sLineBreak +
    '  </style>' + sLineBreak +
    '</head>' + sLineBreak +
    '<body>' + sLineBreak +
    '  <h1>Dext + HTMX 4</h1>' + sLineBreak +
    '  <p>One response, two targets: the response carries two <code>&lt;hx-partial&gt;</code>' + sLineBreak +
    '     elements; the client swaps each into its own place.</p>' + sLineBreak +
    '  <p>' + sLineBreak +
    '    <button hx-get="/invoices" hx-swap="none">Load invoices (partial)</button>' + sLineBreak +
    '    <button hx-get="/invoices/append" hx-swap="none">Append row (beforeend)</button>' + sLineBreak +
    '    <button hx-get="/invoices" hx-target="body">Full page (HX-Request-Type: full)</button>' + sLineBreak +
    '  </p>' + sLineBreak +
    '  <p id="invoice-count">Invoices: no data yet</p>' + sLineBreak +
    '  <div id="invoice-grid">Click "Load invoices" to fetch two partials at once.</div>' + sLineBreak +
    '</body>' + sLineBreak +
    '</html>';
end;

procedure HandleInvoices(Context: IHttpContext);
var
  RequestNo: Integer;
begin
  RequestNo := TInterlocked.Increment(fRequestCounter);

  if Htmx.Request(Context).IsPartial then
  begin
    Htmx.Partials
      .Target('#invoice-grid',
        Format('<table><tr><td>INV-%d</td><td>rendered %s</td></tr></table>',
          [RequestNo, DateTimeToStr(Now)]))
      .Id('invoice-count',
        Format('%d response(s) served', [RequestNo]))
      .AsResult.Execute(Context);
    Exit;
  end;

  Results.Html(GreetingPage).Execute(Context);
end;

procedure HandleAppendRow(Context: IHttpContext);
var
  RequestNo: Integer;
begin
  RequestNo := TInterlocked.Increment(fRequestCounter);

  Htmx.Partials
    .Target('#invoice-grid',
      Format('<tr><td>INV-%d</td><td>appended %s</td></tr>',
        [RequestNo, DateTimeToStr(Now)]),
      'beforeend')
    .Id('invoice-count',
      Format('%d response(s) served', [RequestNo]))
    .AsResult.Execute(Context);
end;

begin
  try
    SetConsoleCharSet(65001);
    WriteLn('Dext HTMX 4 Demo');
    WriteLn('================');
    WriteLn;
    WriteLn('Open http://localhost:', DemoPort, '/ in your browser.');
    WriteLn;

    Builder := TDextWebHost.CreateDefaultBuilder;
    Builder.UseUrls(Format('http://localhost:%d', [DemoPort]));

    Builder.Configure(
      procedure(App: IApplicationBuilder)
      begin
        App.MapGet('/',
          procedure(Context: IHttpContext)
          begin
            Results.Html(GreetingPage).Execute(Context);
          end);

        App.MapGet('/invoices', HandleInvoices);
        App.MapGet('/invoices/append', HandleAppendRow);
      end);

    Host := Builder.Build;
    (Host as IWebApplication).UseNativeServer;
    // 8080 fica com o Web.SslDemo. http.sys não aceita http://+:8080/ e https://+:8080/ juntos.
    Host.Run(8091);
    Host.Stop;

  except
    on E: Exception do
      WriteLn('Error: ', E.Message);
  end;
  ConsolePause;
end.
