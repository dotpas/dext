program MCP.FullDemo;

{$APPTYPE CONSOLE}
{$R *.res}

(*****************************************************************************)
(*                                                                           *)
(*  MCP Full Demo - Dext MCP 2025-03-26                                      *)
(*                                                                           *)
(*  Demonstra o uso completo do Dext MCP Server:                             *)
(*                                                                           *)
(*    TRANSPORT   HTTP Streamable (POST /mcp) - protocolo 2025-03-26         *)
(*    TOOLS       4 tools via provider RTTI ([MCPTool] + [MCPParam])         *)
(*    RESOURCES   2 resources via provider RTTI ([MCPResource])              *)
(*    PROMPTS     2 prompts via provider RTTI ([MCPPrompt] + [MCPPromptArg]) *)
(*    RESULTADO   TMCPToolResult rico (Text, Error, multi-content)           *)
(*                                                                           *)
(*  Stack HTTP: Indy TIdHTTPServer (via TWebHostBuilder do Dext)             *)
(*                                                                           *)
(*  Uso:                                                                     *)
(*    MCP.FullDemo.exe                -> Streamable em http://localhost:3031 *)
(*    MCP.FullDemo.exe --port 3040    -> Streamable em porta customizada     *)
(*    MCP.FullDemo.exe --sse          -> SSE legacy (Claude Desktop antigo)  *)
(*    MCP.FullDemo.exe --stdio        -> Stdio (Claude Desktop processo)     *)
(*                                                                           *)
(*  Conectar ao Claude Code:                                                 *)
(*    claude mcp add demo http://localhost:3031/mcp                          *)
(*                                                                           *)
(*  Verificar manualmente (curl):                                            *)
(*    curl -X POST http://localhost:3031/mcp \                               *)
(*      -H "Content-Type: application/json" \                                *)
(*      -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{         *)
(*           "protocolVersion":"2025-03-26",                                 *)
(*           "clientInfo":{"name":"test","version":"1.0"}}}'                 *)
(*                                                                           *)
(*****************************************************************************)

uses
  System.SysUtils,
  Dext.AI.MCP.Server,
  Dext.Server.Engine.Types,
  MCP.FullDemo.Provider in 'MCP.FullDemo.Provider.pas';

// ---------------------------------------------------------------------------
// Arg parsing helpers
// ---------------------------------------------------------------------------

function HasFlag(const AFlag: string): Boolean;
var I: Integer;
begin
  for I := 1 to ParamCount do
    if ParamStr(I).ToLower = AFlag.ToLower then Exit(True);
  Result := False;
end;

function GetParam(const AFlag, ADefault: string): string;
var I: Integer;
begin
  for I := 1 to ParamCount - 1 do
    if ParamStr(I).ToLower = AFlag.ToLower then Exit(ParamStr(I + 1));
  Result := ADefault;
end;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

var
  Builder: TMCPServerBuilder;
  Port, Url: string;
  Server: TMCPServer;
  Transport: TMCPTransport;
  UseHttpSys: Boolean;

begin
  ReportMemoryLeaksOnShutdown := True;
  Randomize;

  Port := GetParam('--port', '3031');
  var UseHttps: Boolean := HasFlag('--https');
  var CertHash: string := GetParam('--cert-hash', '');

  if UseHttps then
    Url := 'https://localhost:' + Port
  else
    Url := 'http://localhost:' + Port;

  Transport  := mtStreamable;
  UseHttpSys := HasFlag('--httpsys');

  if HasFlag('--sse') then
    Transport := mtSSE
  else if HasFlag('--stdio') then
    Transport := mtStdio;

  Builder := TMCPServerBuilder.Create;
  try
    Builder
      .Name('full-demo')
      .Version('1.0.0')
      .Transport(Transport)
      .Url(Url);

    if UseHttpSys then
    begin
      var Opts := ServerEngineOptions;
      if UseHttps then
      begin
        Opts := Opts.WithHttps(True);
        if CertHash <> '' then
          Opts := Opts.WithSslCertHash(CertHash);
      end;
      Builder.UseHttpSys(Opts);
    end
    else
      Builder.UseIndy;

    Builder.RegisterProvider(TDemoProvider.Create);
    Server := Builder.Build;
  finally
    Builder.Free;
  end;

  try
    // Também é possível registrar itens extras via fluent API:
    //
    // Server.Tool('tool-adicional')
    //   .Description('Tool registrada via fluent API além do provider')
    //   .OnCallResult(function(Args: TJsonObject): TMCPToolResult
    //     begin Result := TMCPToolResult.Text('ok'); end);

    if Transport = mtStdio then
    begin
      // Stdio: Claude Desktop gerencia este processo diretamente
      Server.Run(mtStdio);
      Exit;
    end;

    // Print startup banner
    Writeln;
    Writeln('╔══════════════════════════════════════════════════╗');
    Writeln('║         Dext MCP Full Demo - v1.0.0              ║');
    Writeln('╚══════════════════════════════════════════════════╝');
    Writeln;
    Writeln('  Protocolo   : MCP 2025-03-26');
    if UseHttpSys then
      Writeln('  Stack HTTP  : http.sys (Windows Native)')
    else
      Writeln('  Stack HTTP  : Indy TIdHTTPServer');

    if Transport = mtStreamable then
    begin
      Writeln('  Transport   : HTTP Streamable (recomendado)');
      Writeln;
      Writeln('  Endpoint    : POST ' + Url + '/mcp');
      Writeln('  Fechar sess.: DELETE ' + Url + '/mcp');
    end
    else
    begin
      Writeln('  Transport   : SSE legacy');
      Writeln;
      Writeln('  SSE stream  : GET  ' + Url + '/sse');
      Writeln('  Mensagens   : POST ' + Url + '/message?sessionId=<uuid>');
    end;

    Writeln('  Health      : GET  ' + Url + '/health');
    Writeln;
    Writeln('  Tools       : ' + IntToStr(Server.Registry.Count));
    Writeln('    calcular-desconto        - desconto progressivo');
    Writeln('    validar-cpf              - verificação algoritmo RF');
    Writeln('    calcular-imc             - classificação OMS');
    Writeln('    gerar-relatorio-texto    - multi-content result');
    Writeln;
    Writeln('  Resources   : ' + IntToStr(Server.Resources.Count));
    Writeln('    config://demo            - configurações do servidor');
    Writeln('    docs://regras-desconto   - tabela de descontos');
    Writeln;
    Writeln('  Prompts     : ' + IntToStr(Server.Prompts.Count));
    Writeln('    analise-venda            - análise comercial');
    Writeln('    revisao-codigo-delphi    - revisão de código');
    Writeln;

    if Transport = mtStreamable then
    begin
      Writeln('  ─── Conectar ao Claude Code ──────────────────────');
      Writeln('  claude mcp add full-demo ' + Url + '/mcp');
      Writeln;
      Writeln('  ─── Testar manualmente (curl / .http file) ───────');
      Writeln('  Ver: mcp_test.http');
    end
    else
    begin
      Writeln('  ─── Claude Desktop config ────────────────────────');
      Writeln('  "full-demo": { "url": "' + Url + '/sse" }');
    end;

    Writeln;
    Writeln('  Pressione Enter para parar...');
    Writeln;

    Server.Run;
    Readln;

    Writeln('Encerrando...');
    Server.Stop;
  finally
    Server.Free;
  end;
end.
