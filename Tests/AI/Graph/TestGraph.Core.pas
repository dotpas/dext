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
{           software distributed under the LICENSE is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Unit Tests for Dext.AI.Graph                                             }
{  Covers: TAgentState.ToJson/FromJson round-trip, conditional edge         }
{  routing, TFileCheckpointer.SanitizeId collision safety, human-in-the-    }
{  loop (RequireApproval/Resume/Cancel/GetState) and subgraph-as-node       }
{  (ICompiledAgent.AsNode).                                                 }
{                                                                           }
{***************************************************************************}
unit TestGraph.Core;

interface

uses
  System.SysUtils,
  System.IOUtils,
  DextJsonDataObjects,
  Dext.Testing,
  Dext.AI.Agent.Contracts,
  Dext.AI.Agent.Runner,
  Dext.AI.Graph.Contracts,
  Dext.AI.Graph.State,
  Dext.AI.Graph.Edge,
  Dext.AI.Graph.Graph,
  Dext.AI.Graph.Compiled,
  Dext.AI.Graph.Checkpointer,
  Dext.AI.Graph.Node.Tools,
  Dext.AI.MCP.Attributes,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Protocol,
  Dext.AI.MCP.Tools;

type
  // Provider falso e determinístico: devolve as respostas de FResponses em
  // sequência (repetindo a última quando a sequência se esgota), sem chamar
  // nenhuma API real — usado por todos os testes deste arquivo.
  TFakeLLMProvider = class(TInterfacedObject, ILLMProvider)
  private
    FResponses: TArray<TLLMResponse>;
    FCallCount: Integer;
  public
    constructor Create(const AResponses: TArray<TLLMResponse>); overload;
    constructor Create(const AFinalAnswer: string = 'ok'); overload;
    function Complete(const AMessages: TArray<TLLMMessage>;
      const ATools: TArray<TToolSchema>): TLLMResponse;
    function ProviderName: string;
    function ModelName: string;
    property CallCount: Integer read FCallCount;
  end;

  [TestFixture('TAgentState - JSON round-trip')]
  TStateJsonTests = class
  public
    [Test]
    procedure RoundTrip_PreservesMessagesToolCallsMetadataAndCursor;
    [Test]
    procedure RoundTrip_PreservesDoneAndFinalAnswer;
  end;

  [TestFixture('TAgentGraph - Conditional Edges')]
  TConditionalEdgeTests = class
  public
    [Test]
    procedure RoutesToToolsNode_WhenPendingCallsExist;
    [Test]
    procedure RoutesToEnd_WhenNoPendingCalls;
  end;

  [TestFixture('TAgentGraph - Compile-time validation')]
  TGraphValidationTests = class
  public
    [Test]
    procedure AddEdge_SecondFixedEdgeFromSameSource_RaisesCompileError;
    [Test]
    procedure AddConditionalEdge_WhenFixedEdgeAlreadyExistsFromSameSource_RaisesCompileError;
    [Test]
    procedure Compile_NoPathToEnd_RaisesENoPathToEnd;
    [Test]
    procedure Compile_CycleWithValidExit_DoesNotRaise;
  end;

  [TestFixture('TFileCheckpointer - SanitizeId')]
  TCheckpointerSanitizeTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure SaveLoadExistsDelete_RoundTrip;
    [Test]
    procedure DifferentIdsThatSanitizeToSameCleanName_DoNotCollide;
  end;

  [TestFixture('ICompiledAgent - Human-in-the-loop')]
  THitlTests = class
  public
    [Test]
    procedure Run_PausesBeforeApprovalNode;
    [Test]
    procedure Resume_ExecutesApprovedNodeAndFinishes;
    [Test]
    procedure Cancel_DeletesCheckpoint_GetStateThenReturnsNil;
  end;

  [TestFixture('ICompiledAgent - Subgraph (AsNode)')]
  TSubgraphTests = class
  public
    [Test]
    procedure AsNode_RunsSubgraphThenParentContinues;
    [Test]
    procedure AsNode_RejectsSubgraphWithRequireApproval;
    [Test]
    procedure AsNode_PropagatesSubgraphErrorAsGrsError;
  end;

  // Provider MCP real (via RTTI) — usado para verificar que TToolsNode e
  // TAgentRunner, depois de passarem a delegar para TMCPToolRegistry em vez
  // de reimplementar o scan RTTI, ainda registram/despacham/liberam um
  // provider de verdade sem double-free (o registry assume a ownership).
  TEchoToolProvider = class(TMCPToolProvider)
  public
    [MCPTool('echo', 'Echoes the input text back')]
    [MCPParam('text', 'Text to echo', ptString)]
    function Echo(const Args: TJsonObject): TMCPToolResult; virtual;
  end;

  [TestFixture('TMCPToolRegistry adoption (TToolsNode / TAgentRunner)')]
  TToolAdoptionTests = class
  public
    [Test]
    procedure ToolsNode_ExecutesRegisteredProviderTool;
    [Test]
    procedure ToolsNode_UnknownTool_ReturnsErrorMessage;
    [Test]
    procedure AgentRunner_ExecutesRegisteredProviderToolAndFinishes;
  end;

implementation

{ TFakeLLMProvider }

constructor TFakeLLMProvider.Create(const AResponses: TArray<TLLMResponse>);
begin
  inherited Create;
  FResponses := Copy(AResponses);
end;

constructor TFakeLLMProvider.Create(const AFinalAnswer: string);
var
  R: TLLMResponse;
begin
  inherited Create;
  R := Default(TLLMResponse);
  R.StopReason := srEndTurn;
  R.Content := AFinalAnswer;
  FResponses := [R];
end;

function TFakeLLMProvider.Complete(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TLLMResponse;
var
  Idx: Integer;
begin
  Idx := FCallCount;
  if Idx > High(FResponses) then
    Idx := High(FResponses);
  Result := FResponses[Idx];
  Inc(FCallCount);
end;

function TFakeLLMProvider.ProviderName: string;
begin
  Result := 'fake';
end;

function TFakeLLMProvider.ModelName: string;
begin
  Result := 'fake-model';
end;

// ── Handlers de nó reutilizados pelos testes de HITL/edges ────────────────

function FakeLLMHandler(const AState: TAgentState; const ACtx: TNodeContext): TAgentState;
var
  Resp: TLLMResponse;
  Old: TAgentState;
begin
  Resp := ACtx.Provider.Complete(AState.Messages, nil);
  Result := AState.WithMessage(TLLMMessage.Assistant(Resp.Content, Resp.ToolCalls));
  Old := Result;
  if Length(Resp.ToolCalls) > 0 then
    Result := Result.WithPendingCalls(Resp.ToolCalls)
  else
    Result := Result.AsDone(Resp.Content);
  Old.Free;
end;

function FakeToolsHandler(const AState: TAgentState; const ACtx: TNodeContext): TAgentState;
var
  TC: TLLMToolCall;
  Old: TAgentState;
begin
  Result := AState;
  for TC in AState.PendingCalls do
  begin
    Old := Result;
    Result := Result.WithMessage(TLLMMessage.ToolResult(TC.Id, 'fake-result-for-' + TC.Name));
    if Old <> AState then
      Old.Free;
  end;
  Old := Result;
  Result := Result.ClearPendingCalls;
  if Old <> AState then
    Old.Free;
end;

function RouteToolsOrEnd(const AState: TAgentState): string;
begin
  if AState.HasPendingCalls then
    Result := 'tools'
  else
    Result := GRAPH_END;
end;

function SubgraphRaisingHandler(const AState: TAgentState; const ACtx: TNodeContext): TAgentState;
begin
  raise Exception.Create('boom-from-subgraph');
end;

function BuildToolLoopGraph(AProvider: ILLMProvider; ARequireApproval: Boolean;
  ACheckpointer: ICheckpointer): ICompiledAgent;
var
  Graph: TAgentGraph;
  Config: TAgentConfig;
begin
  Config := Default(TAgentConfig);
  Config.MaxIterations := 10;

  Graph := TAgentGraph.Create;
  Graph
    .AddNode('call_llm', FakeLLMHandler)
    .AddNode('tools', FakeToolsHandler)
    .SetEntryPoint('call_llm')
    .AddConditionalEdge('call_llm', RouteToolsOrEnd,
      [TEdgeRoute.To_('tools'), TEdgeRoute.ToEnd])
    .AddEdge('tools', 'call_llm');
  if ARequireApproval then
    Graph.RequireApproval('tools');
  Result := Graph.Compile(AProvider, Config, nil, ACheckpointer);
  Graph.Free;
end;

function MakeToolCallResponse(const AToolName, AArgsJson: string): TLLMResponse;
var
  TC: TLLMToolCall;
begin
  TC := Default(TLLMToolCall);
  TC.Id := 'call-1';
  TC.Name := AToolName;
  TC.ArgsJson := AArgsJson;
  Result := Default(TLLMResponse);
  Result.StopReason := srToolUse;
  Result.Content := '';
  Result.ToolCalls := [TC];
end;

function MakeFinalResponse(const AContent: string): TLLMResponse;
begin
  Result := Default(TLLMResponse);
  Result.StopReason := srEndTurn;
  Result.Content := AContent;
end;

{ TStateJsonTests }

procedure TStateJsonTests.RoundTrip_PreservesMessagesToolCallsMetadataAndCursor;
var
  S, Old, Restored: TAgentState;
  TC: TLLMToolCall;
  Json: string;
begin
  TC := Default(TLLMToolCall);
  TC.Id := 'call-1';
  TC.Name := 'search';
  TC.ArgsJson := '{"q":"delphi"}';

  S := TAgentState.Create('thread-1');
  try
    Old := S; S := S.WithMessage(TLLMMessage.System('be helpful')); Old.Free;
    Old := S; S := S.WithMessage(TLLMMessage.User('hi')); Old.Free;
    Old := S; S := S.WithMessage(TLLMMessage.Assistant('', [TC])); Old.Free;
    Old := S; S := S.WithPendingCalls([TC]); Old.Free;
    Old := S; S := S.WithMeta('key1', 'value1'); Old.Free;
    Old := S; S := S.WithCurrentNode('call_llm'); Old.Free;
    Old := S; S := S.NextIteration; Old.Free;

    Json := S.ToJson;
  finally
    S.Free;
  end;

  Restored := TAgentState.FromJson(Json);
  try
    Should(Length(Restored.Messages)).Be(3);
    Should(Ord(Restored.Messages[0].Role)).Be(Ord(lrSystem));
    Should(Restored.Messages[1].Content).Be('hi');
    Should(Length(Restored.Messages[2].ToolCalls)).Be(1);
    Should(Restored.Messages[2].ToolCalls[0].Name).Be('search');
    Should(Restored.HasPendingCalls).BeTrue;
    Should(Restored.PendingCalls[0].ArgsJson).Be('{"q":"delphi"}');
    Should(Restored.GetMeta('key1')).Be('value1');
    Should(Restored.CurrentNode).Be('call_llm');
    Should(Restored.Iteration).Be(1);
    Should(Restored.ThreadId).Be('thread-1');
  finally
    Restored.Free;
  end;
end;

procedure TStateJsonTests.RoundTrip_PreservesDoneAndFinalAnswer;
var
  S, Old, Restored: TAgentState;
  Json: string;
begin
  S := TAgentState.Create('thread-2');
  try
    Old := S; S := S.AsDone('the final answer'); Old.Free;
    Json := S.ToJson;
  finally
    S.Free;
  end;

  Restored := TAgentState.FromJson(Json);
  try
    Should(Restored.IsDone).BeTrue;
    Should(Restored.FinalAnswer).Be('the final answer');
  finally
    Restored.Free;
  end;
end;

{ TConditionalEdgeTests }

procedure TConditionalEdgeTests.RoutesToToolsNode_WhenPendingCallsExist;
var
  Provider: TFakeLLMProvider;
  Agent: ICompiledAgent;
  Result: TGraphRunResult;
begin
  Provider := TFakeLLMProvider.Create([
    MakeToolCallResponse('search', '{}'),
    MakeFinalResponse('done')
  ]);
  Agent := BuildToolLoopGraph(Provider, False, TMemoryCheckpointer.Create);

  Result := Agent.Run('go', 'thread-edge-1');

  Should(Ord(Result.Status)).Be(Ord(grsFinished));
  Should(Result.FinalAnswer).Be('done');
  Should(Provider.CallCount).Be(2)
    .Because('a rota condicional deve levar a "tools" e voltar para "call_llm" antes de terminar');
end;

procedure TConditionalEdgeTests.RoutesToEnd_WhenNoPendingCalls;
var
  Provider: TFakeLLMProvider;
  Agent: ICompiledAgent;
  Result: TGraphRunResult;
begin
  Provider := TFakeLLMProvider.Create('immediate-answer');
  Agent := BuildToolLoopGraph(Provider, False, TMemoryCheckpointer.Create);

  Result := Agent.Run('go', 'thread-edge-2');

  Should(Ord(Result.Status)).Be(Ord(grsFinished));
  Should(Result.FinalAnswer).Be('immediate-answer');
  Should(Provider.CallCount).Be(1)
    .Because('sem tool calls pendentes, a rota condicional deve ir direto para GRAPH_END');
end;

{ TGraphValidationTests }

procedure TGraphValidationTests.AddEdge_SecondFixedEdgeFromSameSource_RaisesCompileError;
var
  Graph: TAgentGraph;
  Raised: Boolean;
begin
  Graph := TAgentGraph.Create;
  try
    Graph
      .AddNode('a', FakeLLMHandler)
      .AddNode('b', FakeLLMHandler)
      .AddNode('c', FakeLLMHandler)
      .AddEdge('a', 'b');

    Raised := False;
    try
      Graph.AddEdge('a', 'c');
    except
      on E: EGraphCompileError do
        Raised := True;
    end;
    Should(Raised).BeTrue
      .Because('uma segunda AddEdge do mesmo nó seria ignorada silenciosamente em runtime (ResolveNextNode usa a primeira que casar)');
  finally
    Graph.Free;
  end;
end;

procedure TGraphValidationTests.AddConditionalEdge_WhenFixedEdgeAlreadyExistsFromSameSource_RaisesCompileError;
var
  Graph: TAgentGraph;
  Raised: Boolean;
begin
  Graph := TAgentGraph.Create;
  try
    Graph
      .AddNode('a', FakeLLMHandler)
      .AddNode('b', FakeLLMHandler)
      .AddEdge('a', 'b');

    Raised := False;
    try
      Graph.AddConditionalEdge('a', RouteToolsOrEnd, [TEdgeRoute.ToEnd]);
    except
      on E: EGraphCompileError do
        Raised := True;
    end;
    Should(Raised).BeTrue
      .Because('misturar edge fixa e condicional do mesmo nó de origem também é ambíguo em runtime');
  finally
    Graph.Free;
  end;
end;

procedure TGraphValidationTests.Compile_NoPathToEnd_RaisesENoPathToEnd;
var
  Graph: TAgentGraph;
  Config: TAgentConfig;
  Provider: TFakeLLMProvider;
  Raised: Boolean;
begin
  Config := Default(TAgentConfig);
  Provider := TFakeLLMProvider.Create;
  Graph := TAgentGraph.Create;
  try
    Graph
      .AddNode('a', FakeLLMHandler)
      .AddNode('b', FakeLLMHandler)
      .SetEntryPoint('a')
      .AddEdge('a', 'b')
      .AddEdge('b', 'a'); // ciclo fechado - nunca alcança GRAPH_END

    Raised := False;
    try
      Graph.Compile(Provider, Config, nil, nil);
    except
      on E: ENoPathToEnd do
        Raised := True;
    end;
    Should(Raised).BeTrue;
  finally
    Graph.Free;
  end;
end;

procedure TGraphValidationTests.Compile_CycleWithValidExit_DoesNotRaise;
var
  Agent: ICompiledAgent;
  Raised: Boolean;
begin
  // BuildToolLoopGraph replica o padrão ReAct real (call_llm <-> tools) -
  // um ciclo intencional que deve compilar sem erro, já que existe uma
  // rota condicional de call_llm até GRAPH_END. Ciclos não são o problema;
  // a ausência de QUALQUER caminho até GRAPH_END é.
  Raised := False;
  try
    Agent := BuildToolLoopGraph(TFakeLLMProvider.Create, False, TMemoryCheckpointer.Create);
  except
    Raised := True;
  end;
  Should(Raised).BeFalse
    .Because('ciclos intencionais não são erro de compile');
end;

{ TCheckpointerSanitizeTests }

procedure TCheckpointerSanitizeTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'dext-ai-graph-tests-' + TGUID.NewGuid.ToString);
end;

procedure TCheckpointerSanitizeTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
end;

procedure TCheckpointerSanitizeTests.SaveLoadExistsDelete_RoundTrip;
var
  CP: ICheckpointer;
begin
  CP := TFileCheckpointer.Create(FDir);

  Should(CP.Exists('thread-1')).BeFalse;
  CP.Save('thread-1', '{"answer":"hi"}');
  Should(CP.Exists('thread-1')).BeTrue;
  Should(CP.Load('thread-1')).Be('{"answer":"hi"}');

  CP.Delete('thread-1');
  Should(CP.Exists('thread-1')).BeFalse;
end;

procedure TCheckpointerSanitizeTests.DifferentIdsThatSanitizeToSameCleanName_DoNotCollide;
var
  CP: ICheckpointer;
begin
  // "a/b" e "a:b" têm a mesma parte "legível" após substituir caracteres
  // inválidos por "_" (ambos viram "a_b") — sem um sufixo que distinga o id
  // original, salvar as duas threads gravaria no mesmo arquivo e uma
  // sobrescreveria silenciosamente o estado da outra.
  CP := TFileCheckpointer.Create(FDir);

  CP.Save('a/b', '{"who":"first"}');
  CP.Save('a:b', '{"who":"second"}');

  Should(CP.Load('a/b')).Be('{"who":"first"}')
    .Because('threads com ids diferentes não podem compartilhar arquivo de checkpoint');
  Should(CP.Load('a:b')).Be('{"who":"second"}');
end;

{ THitlTests }

procedure THitlTests.Run_PausesBeforeApprovalNode;
var
  Provider: TFakeLLMProvider;
  Agent: ICompiledAgent;
  Result: TGraphRunResult;
begin
  Provider := TFakeLLMProvider.Create([
    MakeToolCallResponse('search', '{}'),
    MakeFinalResponse('done')
  ]);
  Agent := BuildToolLoopGraph(Provider, True, TMemoryCheckpointer.Create);

  Result := Agent.Run('go', 'thread-hitl-1');

  Should(Ord(Result.Status)).Be(Ord(grsWaitingApproval));
  Should(Result.PendingNode).Be('tools');
  Should(Provider.CallCount).Be(1)
    .Because('a execução deve parar ANTES do nó "tools", sem chamar o LLM de novo');
end;

procedure THitlTests.Resume_ExecutesApprovedNodeAndFinishes;
var
  Provider: TFakeLLMProvider;
  Agent: ICompiledAgent;
  R1, R2: TGraphRunResult;
begin
  Provider := TFakeLLMProvider.Create([
    MakeToolCallResponse('search', '{}'),
    MakeFinalResponse('done')
  ]);
  Agent := BuildToolLoopGraph(Provider, True, TMemoryCheckpointer.Create);

  R1 := Agent.Run('go', 'thread-hitl-2');
  Should(Ord(R1.Status)).Be(Ord(grsWaitingApproval));

  R2 := Agent.Resume('thread-hitl-2');

  Should(Ord(R2.Status)).Be(Ord(grsFinished));
  Should(R2.FinalAnswer).Be('done');
  Should(Provider.CallCount).Be(2);
end;

procedure THitlTests.Cancel_DeletesCheckpoint_GetStateThenReturnsNil;
var
  Provider: TFakeLLMProvider;
  Agent: ICompiledAgent;
  Result: TGraphRunResult;
  StateBefore, StateAfter: TAgentState;
begin
  Provider := TFakeLLMProvider.Create([
    MakeToolCallResponse('search', '{}'),
    MakeFinalResponse('done')
  ]);
  Agent := BuildToolLoopGraph(Provider, True, TMemoryCheckpointer.Create);

  Result := Agent.Run('go', 'thread-hitl-3');
  Should(Ord(Result.Status)).Be(Ord(grsWaitingApproval));

  StateBefore := Agent.GetState('thread-hitl-3');
  Should(StateBefore).NotBeNil;

  Agent.Cancel('thread-hitl-3');

  StateAfter := Agent.GetState('thread-hitl-3');
  Should(StateAfter).BeNil;
end;

{ TSubgraphTests }

procedure TSubgraphTests.AsNode_RunsSubgraphThenParentContinues;
var
  SubProvider, ParentProvider: TFakeLLMProvider;
  SubGraph, ParentGraph: TAgentGraph;
  SubAgent, ParentAgent: ICompiledAgent;
  Config: TAgentConfig;
  Result: TGraphRunResult;
begin
  Config := Default(TAgentConfig);
  Config.MaxIterations := 10;

  SubProvider := TFakeLLMProvider.Create('sub-answer');
  SubGraph := TAgentGraph.Create;
  SubAgent := SubGraph
    .AddNode('sub_llm', FakeLLMHandler)
    .SetEntryPoint('sub_llm')
    .Compile(SubProvider, Config, nil, nil);
  SubGraph.Free;

  ParentProvider := TFakeLLMProvider.Create('parent-answer');
  ParentGraph := TAgentGraph.Create;
  ParentAgent := ParentGraph
    .AddNode('fiscal_agent', SubAgent.AsNode)
    .AddNode('finalize', FakeLLMHandler)
    .SetEntryPoint('fiscal_agent')
    .AddEdge('fiscal_agent', 'finalize')
    .Compile(ParentProvider, Config, nil, TMemoryCheckpointer.Create);
  ParentGraph.Free;

  Result := ParentAgent.Run('oi', 'thread-subgraph-1');

  Should(Ord(Result.Status)).Be(Ord(grsFinished));
  Should(SubProvider.CallCount).Be(1);
  Should(ParentProvider.CallCount).Be(1);
  Should(Result.FinalAnswer).Be('parent-answer')
    .Because('a resposta final deve vir do nó "finalize" do grafo pai, não do subgrafo');
end;

procedure TSubgraphTests.AsNode_RejectsSubgraphWithRequireApproval;
var
  SubProvider: TFakeLLMProvider;
  SubGraph: TAgentGraph;
  SubAgent: ICompiledAgent;
  Config: TAgentConfig;
  Raised: Boolean;
begin
  Config := Default(TAgentConfig);
  Config.MaxIterations := 10;

  SubProvider := TFakeLLMProvider.Create('sub-answer');
  SubGraph := TAgentGraph.Create;
  SubAgent := SubGraph
    .AddNode('sub_llm', FakeLLMHandler, True) // RequiresApproval = True
    .SetEntryPoint('sub_llm')
    .Compile(SubProvider, Config, nil, nil);
  SubGraph.Free;

  Raised := False;
  try
    SubAgent.AsNode;
  except
    on E: EGraphCompileError do
      Raised := True;
  end;

  Should(Raised).BeTrue
    .Because('aprovação humana aninhada não é suportada (v1) — AsNode deve recusar');
end;

procedure TSubgraphTests.AsNode_PropagatesSubgraphErrorAsGrsError;
var
  Provider: TFakeLLMProvider;
  SubGraph, ParentGraph: TAgentGraph;
  SubAgent, ParentAgent: ICompiledAgent;
  Config: TAgentConfig;
  Result: TGraphRunResult;
begin
  Config := Default(TAgentConfig);
  Config.MaxIterations := 10;

  Provider := TFakeLLMProvider.Create('unused');
  SubGraph := TAgentGraph.Create;
  SubAgent := SubGraph
    .AddNode('boom', SubgraphRaisingHandler)
    .SetEntryPoint('boom')
    .Compile(Provider, Config, nil, nil);
  SubGraph.Free;

  ParentGraph := TAgentGraph.Create;
  ParentAgent := ParentGraph
    .AddNode('fiscal_agent', SubAgent.AsNode)
    .SetEntryPoint('fiscal_agent')
    .Compile(Provider, Config, nil, nil);
  ParentGraph.Free;

  Result := ParentAgent.Run('oi', 'thread-subgraph-3');

  Should(Ord(Result.Status)).Be(Ord(grsError));
  Should(Result.ErrorMsg).Contain('boom-from-subgraph');
end;

{ TEchoToolProvider }

function TEchoToolProvider.Echo(const Args: TJsonObject): TMCPToolResult;
begin
  Result := TMCPToolResult.Text('echo:' + Args.S['text']);
end;

{ TToolAdoptionTests }

procedure TToolAdoptionTests.ToolsNode_ExecutesRegisteredProviderTool;
var
  Node: TToolsNode;
  Schemas: TArray<TToolSchema>;
  State, Old, Result: TAgentState;
  TC: TLLMToolCall;
  Ctx: TNodeContext;
begin
  Node := TToolsNode.Create;
  try
    Node.RegisterProvider(TEchoToolProvider.Create);

    Schemas := Node.GetToolSchemas;
    Should(Length(Schemas)).Be(1);
    Should(Schemas[0].Name).Be('echo');
    Should(Schemas[0].InputSchema).Contain('text')
      .Because('o schema deve vir do scan RTTI feito pelo TMCPToolRegistry');

    TC := Default(TLLMToolCall);
    TC.Id := 'call-1';
    TC.Name := 'echo';
    TC.ArgsJson := '{"text":"hi"}';

    State := TAgentState.Create('thread-tools-1');
    try
      Old := State; State := State.WithPendingCalls([TC]); Old.Free;

      Ctx := Default(TNodeContext);
      Result := Node.Execute(State, Ctx);
      try
        Should(Result.HasPendingCalls).BeFalse;
        Should(Length(Result.Messages)).Be(1);
        Should(Result.Messages[0].Content).Be('echo:hi');
      finally
        if Result <> State then
          Result.Free;
      end;
    finally
      State.Free;
    end;
  finally
    Node.Free; // libera o registry, que libera o TEchoToolProvider — sem double-free
  end;
end;

procedure TToolAdoptionTests.ToolsNode_UnknownTool_ReturnsErrorMessage;
var
  Node: TToolsNode;
  State, Old, Result: TAgentState;
  TC: TLLMToolCall;
  Ctx: TNodeContext;
begin
  Node := TToolsNode.Create;
  try
    Node.RegisterProvider(TEchoToolProvider.Create);

    TC := Default(TLLMToolCall);
    TC.Id := 'call-1';
    TC.Name := 'does-not-exist';
    TC.ArgsJson := '{}';

    State := TAgentState.Create('thread-tools-2');
    try
      Old := State; State := State.WithPendingCalls([TC]); Old.Free;

      Ctx := Default(TNodeContext);
      Result := Node.Execute(State, Ctx);
      try
        Should(Result.Messages[0].Content).Contain('Tool not found');
      finally
        if Result <> State then
          Result.Free;
      end;
    finally
      State.Free;
    end;
  finally
    Node.Free;
  end;
end;

procedure TToolAdoptionTests.AgentRunner_ExecutesRegisteredProviderToolAndFinishes;
var
  Provider: TFakeLLMProvider;
  Config: TAgentConfig;
  Runner: TAgentRunner;
  Result: TAgentResult;
begin
  Provider := TFakeLLMProvider.Create([
    MakeToolCallResponse('echo', '{"text":"hi"}'),
    MakeFinalResponse('done')
  ]);
  Config := Default(TAgentConfig);
  Config.MaxIterations := 10;

  Runner := TAgentRunner.Create(Provider, Config, nil);
  try
    Runner.RegisterProvider(TEchoToolProvider.Create);

    Result := Runner.Run('go');

    Should(Result.Success).BeTrue;
    Should(Result.FinalAnswer).Be('done');
    Should(Provider.CallCount).Be(2)
      .Because('primeira chamada pede a tool "echo", a segunda já fecha com srEndTurn');
  finally
    Runner.Free; // idem: registry libera o provider, TAgentRunner não guarda referência própria
  end;
end;

end.
