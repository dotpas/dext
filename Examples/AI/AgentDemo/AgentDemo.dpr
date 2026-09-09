program AgentDemo;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math,
  DextJsonDataObjects,
  System.IOUtils,
  System.Classes,
  Dext.AI.MCP.Tools,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Protocol,
  Dext.AI.MCP.Attributes,
  Dext.AI.Agent.Contracts,
  Dext.AI.Agent.Factory,
  Dext.AI.Agent.Runner,
  Dext.AI.Agent.Observer;

// ─── Tools de demonstração ────────────────────────────────────────────────
// Reutiliza EXATAMENTE o padrão TMCPToolProvider do Dext existente

type
  TFileSystemTools = class(TMCPToolProvider)
  public
    [MCPTool('list_files', 'Lista arquivos em um diretório')]
    [MCPParam('path', 'Caminho do diretório', ptString, True)]
    [MCPParam('extension', 'Filtro de extensão ex: .pas (opcional)', ptString, False)]
    function ListFiles(const Args: TJsonObject): TMCPToolResult;

    [MCPTool('read_file', 'Lê o conteúdo de um arquivo texto')]
    [MCPParam('path', 'Caminho completo do arquivo', ptString, True)]
    [MCPParam('max_lines', 'Máximo de linhas (default: 50)', ptInteger, False)]
    function ReadFile(const Args: TJsonObject): TMCPToolResult;

    [MCPTool('count_lines', 'Conta linhas de código em um arquivo')]
    [MCPParam('path', 'Caminho completo do arquivo', ptString, True)]
    function CountLines(const Args: TJsonObject): TMCPToolResult;
  end;

function TFileSystemTools.ListFiles(const Args: TJsonObject): TMCPToolResult;
var
  Path, Ext, Pattern: string;
  SR: TSearchRec;
  JA: TJsonArray;
  JO: TJsonObject;
begin
  Path := Args.S['path'];
  if Path = '' then Path := '.';
  Ext  := Args.S['extension'];

  if not DirectoryExists(Path) then
    Exit(TMCPToolResult.Error('Diretório não encontrado: ' + Path));

  Pattern := IncludeTrailingPathDelimiter(Path) + '*' + Ext;
  JA := TJsonArray.Create;
  try
    if FindFirst(Pattern, faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) = 0 then
        begin
          JO := JA.AddObject;
          JO.S['name'] := SR.Name;
          JO.L['size'] := SR.Size;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
    Result := TMCPToolResult.Text(
      Format('{"path":"%s","filter":"%s","count":%d,"files":%s}',
        [Path, Ext, JA.Count, JA.ToJSON])
    );
  finally
    JA.Free;
  end;
end;

function TFileSystemTools.ReadFile(const Args: TJsonObject): TMCPToolResult;
var
  Path: string;
  MaxLines, I: Integer;
  Lines: TStringList;
  SB: TStringBuilder;
begin
  Path := Args.S['path'];
  if Args.Contains('max_lines') then
    MaxLines := Args.I['max_lines']
  else
    MaxLines := 50;

  if not FileExists(Path) then
    Exit(TMCPToolResult.Error('Arquivo não encontrado: ' + Path));

  Lines := TStringList.Create;
  SB    := TStringBuilder.Create;
  try
    Lines.LoadFromFile(Path, TEncoding.UTF8);
    SB.AppendLine(Format('// %s — %d linhas total', [ExtractFileName(Path), Lines.Count]));
    for I := 0 to Min(MaxLines - 1, Lines.Count - 1) do
      SB.AppendFormat('%4d  %s', [I + 1, Lines[I]]).AppendLine;
    if Lines.Count > MaxLines then
      SB.AppendLine(Format('// ... (%d linhas restantes)', [Lines.Count - MaxLines]));
    Result := TMCPToolResult.Text(SB.ToString);
  finally
    Lines.Free;
    SB.Free;
  end;
end;

function TFileSystemTools.CountLines(const Args: TJsonObject): TMCPToolResult;
var
  Path: string;
  Lines: TStringList;
  Code, Comment, Blank: Integer;
  Line: string;
begin
  Path := Args.S['path'];
  if not FileExists(Path) then
    Exit(TMCPToolResult.Error('Arquivo não encontrado: ' + Path));

  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Path, TEncoding.UTF8);
    Code := 0; Comment := 0; Blank := 0;
    for Line in Lines do
    begin
      var T := Line.Trim;
      if T = '' then Inc(Blank)
      else if T.StartsWith('//') or T.StartsWith('{') or T.StartsWith('(*') then Inc(Comment)
      else Inc(Code);
    end;
    Result := TMCPToolResult.Text(
      Format('{"file":"%s","total":%d,"code":%d,"comments":%d,"blank":%d}',
        [ExtractFileName(Path), Lines.Count, Code, Comment, Blank])
    );
  finally
    Lines.Free;
  end;
end;

// ─── MAIN ─────────────────────────────────────────────────────────────────

var
  Config:   TAgentConfig;
  Provider: ILLMProvider;
  Observer: IAgentObserver;
  Runner:   TAgentRunner;
  Input:    string;
  Res:      TAgentResult;

begin
  ReportMemoryLeaksOnShutdown := True;

  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);

  // ── Configuração via variável de ambiente ──────────────────────────────
  // Para usar OpenAI:    set OPENAI_API_KEY=sk-...
  // Para usar Anthropic: set ANTHROPIC_API_KEY=sk-ant-...
  // Para usar Ollama:    (sem key — roda local)

  Config := TAgentConfig.OpenAI('gpt-4o');  // trocar aqui para mudar provider
  Config.ApiKey := GetEnvironmentVariable('OPENAI_API_KEY');

  // Descomente para usar Anthropic:
  // Config := TAgentConfig.Anthropic('claude-sonnet-4-6');
  // Config.ApiKey := GetEnvironmentVariable('ANTHROPIC_API_KEY');

  // Descomente para usar Ollama local (sem key):
  // Config := TAgentConfig.Ollama('llama3.2');

  Config.SystemPrompt :=
    'Você é um assistente técnico especializado em projetos Delphi. ' +
    'Analise os arquivos do projeto e responda com precisão. ' +
    'Nunca invente dados — use apenas as tools disponíveis.';

  if (Config.ApiKey = '') and not Config.ProviderString.StartsWith('ollama') then
  begin
    Writeln('ERRO: API key não encontrada.');
    Writeln('Para OpenAI:    set OPENAI_API_KEY=sk-...');
    Writeln('Para Anthropic: set ANTHROPIC_API_KEY=sk-ant-...');
    ExitCode := 1;
    Exit;
  end;

  // ── Criar provider via Factory (igual ao init_chat_model do LangChain) ─
  try
    Provider := TLLMFactory.CreateProvider(Config);
  except
    on E: ELLMProviderError do
    begin
      Writeln('ERRO: ' + E.Message);
      ExitCode := 1;
      Exit;
    end;
  end;

  Observer := TConsoleObserver.Create;
  Runner   := TAgentRunner.Create(Provider, Config, Observer);
  try
    Runner.RegisterProvider(TFileSystemTools.Create);

    Writeln('═══════════════════════════════════════════════════════');
    Writeln(Format('  Dext.AI.Agent — Demo ao Vivo', []));
    Writeln(Format('  Provider: %s | Model: %s', [Provider.ProviderName, Provider.ModelName]));
    Writeln('  Digite sua pergunta. Enter em branco para sair.');
    Writeln('═══════════════════════════════════════════════════════');
    Writeln;

    repeat
      Write('Pergunta: ');
      Readln(Input);
      if Input.Trim = '' then Break;

      Writeln;
      Res := Runner.Run(Input);

      if not Res.Success then
      begin
        Writeln;
        Writeln('ERRO: ' + Res.ErrorMsg);
      end;
      Writeln;
    until False;

  finally
    Runner.Free;
  end;
end.
