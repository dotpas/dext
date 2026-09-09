program GraphDemo;

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
  Dext.AI.Agent.Observer,
  Dext.AI.Graph.Contracts,
  Dext.AI.Graph.State,
  Dext.AI.Graph.Edge,
  Dext.AI.Graph.Graph,
  Dext.AI.Graph.Compiled,
  Dext.AI.Graph.Checkpointer,
  Dext.AI.Graph.Node.LLM,
  Dext.AI.Graph.Node.Tools;

type
  TFileSystemTools = class(TMCPToolProvider)
  public
    [MCPTool('list_files', 'Lista arquivos em um diretório')]
    [MCPParam('path', 'Caminho do diretório', ptString, True)]
    [MCPParam('extension', 'Filtro ex: .pas (opcional)', ptString, False)]
    function ListFiles(const Args: TJsonObject): TMCPToolResult;

    [MCPTool('read_file', 'Lê o conteúdo de um arquivo')]
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

// Condição de roteamento do nó 'call_llm'. Igual ao DefaultShouldContinue,
// mas manda o fluxo passar pelo subgrafo 'polish_agent' antes do GRAPH_END,
// em vez de encerrar direto — é assim que se pluga um subgrafo no meio do
// roteamento condicional de um grafo existente.
function ShouldContinueOrPolish(const AState: TAgentState): string;
begin
  if AState.HasPendingCalls then
    Result := 'execute_tools'
  else
    Result := 'polish_agent';
end;

var
  Config:        TAgentConfig;
  Provider:      ILLMProvider;
  Observer:      IAgentObserver;
  ToolsNode:     TToolsNode;
  LLMNode:       TLLMNode;
  Graph:         TAgentGraph;
  Agent:         ICompiledAgent;
  Checkpointer:  ICheckpointer;
  Input, ThreadId, CheckpointDir: string;
  RunResult:     TGraphRunResult;
  Confirm:       string;

  // ── Subgrafo "polish_agent" ────────────────────────────────────────────
  // Um grafo compilado independente (seu próprio TAgentGraph, seu próprio
  // TLLMNode, sem tools), embutido no grafo principal como um nó comum via
  // ICompiledAgent.AsNode. Reescreve a resposta bruta do 'call_llm' de forma
  // mais objetiva antes de virar a resposta final ao usuário.
  //
  // IMPORTANTE: um subgrafo não pode ter RequireApproval/InterruptBefore em
  // nenhum nó seu — AsNode levantaria EGraphCompileError (aprovação humana
  // aninhada não é suportada). Se o fluxo do subgrafo precisar de aprovação,
  // ela deve ficar no nó do grafo PAI que o invoca (aqui, seria em
  // 'polish_agent' do grafo principal, não dentro do PolishGraph).
  PolishConfig:   TAgentConfig;
  PolishLLMNode:  TLLMNode;
  PolishGraph:    TAgentGraph;
  PolishAgent:    ICompiledAgent;

begin
  ReportMemoryLeaksOnShutdown := True;

  SetConsoleOutputCP(CP_UTF8);
  SetConsoleCP(CP_UTF8);

  Config := TAgentConfig.OpenAI('gpt-4o');
  Config.ApiKey := GetEnvironmentVariable('OPENAI_API_KEY');
  Config.SystemPrompt :=
    'Você é um assistente técnico especializado em projetos Delphi. ' +
    'Use as tools disponíveis para responder. Nunca invente dados.';

  if Config.ApiKey = '' then
  begin
    Writeln('ERRO: Defina OPENAI_API_KEY');
    ExitCode := 1;
    Exit;
  end;

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

  Observer      := TConsoleObserver.Create;
  ToolsNode     := TToolsNode.Create;
  LLMNode       := nil;
  PolishLLMNode := nil;
  try
    ToolsNode.RegisterProvider(TFileSystemTools.Create);
    LLMNode := TLLMNode.Create(ToolsNode.GetToolSchemas);

    // TFileCheckpointer em vez de TMemoryCheckpointer: o estado da thread
    // sobrevive ao encerramento do processo — feche o GraphDemo, abra de
    // novo, use a mesma ThreadId e o histórico continua de onde parou.
    Checkpointer  := TFileCheckpointer.Create;
    CheckpointDir := TPath.Combine(TPath.GetTempPath, 'dext-ai-graph');

    // ── Compila o subgrafo 'polish_agent' primeiro (grafo independente) ──
    PolishConfig := Config;
    PolishConfig.SystemPrompt :=
      'Reescreva a última resposta do assistente de forma mais clara e ' +
      'objetiva para o usuário final. Mantenha os fatos exatamente como ' +
      'estão — não invente, não adicione e não remova informação.';
    PolishLLMNode := TLLMNode.Create(nil); // sem tools: só reescreve texto

    PolishGraph := TAgentGraph.Create;
    try
      PolishAgent := PolishGraph
        .AddNode('polish_llm', PolishLLMNode.AsHandler)
        .SetEntryPoint('polish_llm')
        .Compile(Provider, PolishConfig, Observer, nil);
    finally
      PolishGraph.Free;
    end;

    // ── Grafo principal: embute o subgrafo como o nó 'polish_agent' ──────
    Graph := TAgentGraph.Create;
    try
      Agent := Graph
        .AddNode('call_llm', LLMNode.AsHandler)
        .AddNode('execute_tools', ToolsNode.AsHandler)
        .AddNode('polish_agent', PolishAgent.AsNode)
        .SetEntryPoint('call_llm')
        .AddConditionalEdge('call_llm',
          ShouldContinueOrPolish,
          [TEdgeRoute.To_('execute_tools'), TEdgeRoute.To_('polish_agent')])
        .AddEdge('execute_tools', 'call_llm')
        .AddEdge('polish_agent', GRAPH_END)
        .RequireApproval('execute_tools')
        .Compile(Provider, Config, Observer, Checkpointer);
    finally
      Graph.Free;
    end;

    Writeln('═══════════════════════════════════════════════════════');
    Writeln('  Dext.AI.Graph — Demo (estilo LangGraph)');
    Writeln(Format('  Provider: %s | Model: %s',
      [Provider.ProviderName, Provider.ModelName]));
    Writeln('  Grafo: call_llm -> execute_tools (aprovação) -> polish_agent (subgrafo) -> fim');
    Writeln('  Checkpoint em disco: ' + CheckpointDir);
    Writeln('  Digite sua pergunta, ":estado" para inspecionar a thread, ou Enter em branco para sair.');
    Writeln('═══════════════════════════════════════════════════════');
    Writeln;

    ThreadId := 'demo-session-001';

    repeat
      Write('Pergunta: ');
      Readln(Input);
      if Input.Trim = '' then
        Break;

      if SameText(Input.Trim, ':estado') then
      begin
        var CurState := Agent.GetState(ThreadId);
        if CurState = nil then
          Writeln('  (nenhum estado salvo ainda para esta thread)')
        else
          Writeln(Format(
            '  nó atual=%s | iteração=%d | concluído=%s | mensagens=%d | pendências=%d',
            [CurState.CurrentNode, CurState.Iteration, BoolToStr(CurState.IsDone, True),
             Length(CurState.Messages), Length(CurState.PendingCalls)]));
        Writeln;
        Continue;
      end;

      Writeln;
      RunResult := Agent.Run(Input, ThreadId);

      case RunResult.Status of
        grsFinished:
          Writeln('');

        grsWaitingApproval:
        begin
          Writeln;
          Writeln('⏸  Aguardando aprovação humana...');
          Writeln('   Nó pendente: ' + RunResult.PendingNode);
          Write('   Aprovar? (s/n): ');
          Readln(Confirm);
          if Confirm.ToLower = 's' then
          begin
            RunResult := Agent.Resume(ThreadId);
            Writeln('   Continuando...');
          end
          else
          begin
            Agent.Cancel(ThreadId);
            Writeln('   Cancelado.');
          end;
        end;

        grsError:
          Writeln('ERRO: ' + RunResult.ErrorMsg);
      end;
      Writeln;
    until False;
  finally
    Agent := nil;
    PolishAgent := nil;
    LLMNode.Free;
    PolishLLMNode.Free;
    ToolsNode.Free;
  end;
end.
