# 🤖 Agentes de IA & Orquestração (Dext.AI.Agent + Dext.AI.Graph)

O Dext traz duas camadas de orquestração construídas sobre o [Dext MCP](../15-mcp-server/README.md), para quem quer o modelo mental do LangChain/LangGraph em Delphi nativo, sem nenhuma dependência externa além da RTL:

- **`Dext.AI.Agent`** — um loop ReAct de agente único (pense no `AgentExecutor` do **LangChain**): um provider, um conjunto de tools, uma conversa.
- **`Dext.AI.Graph`** — orquestração via grafo por cima disso (pense no `StateGraph` do **LangGraph**): nós e edges explícitos, roteamento condicional, estado com checkpoint entre turnos, aprovação humana (human-in-the-loop) e composição de sub-agentes.

Use `Dext.AI.Agent` quando um loop simples "chama o LLM, executa tools, repete até terminar" já resolve. Use `Dext.AI.Graph` quando precisar de mais de uma etapa distinta (um roteador, uma etapa de revisão, vários agentes cooperando) ou precisar pausar e retomar entre turnos/processos.

As duas camadas usam diretamente o padrão `TMCPToolProvider` / `[MCPTool]` / `[MCPParam]` do [capítulo de MCP](../15-mcp-server/README.md) — as mesmas tools declarativas que você exporia para um cliente de IA externo podem ser reaproveitadas como o conjunto de tools do próprio agente.

---

## 📦 Onde fica cada coisa

```
Sources/AI/Agent/
├── Dext.AI.Agent.Contracts.pas      ILLMProvider, TLLMMessage, TAgentConfig, IAgentObserver
├── Dext.AI.Agent.Factory.pas        TLLMFactory.CreateProvider(config)
├── Dext.AI.Agent.Runner.pas         TAgentRunner (loop ReAct de agente único)
├── Dext.AI.Agent.Observer.pas       IAgentObserver, TConsoleObserver
└── Providers/
    ├── Dext.AI.Agent.Provider.OpenAI.pas
    ├── Dext.AI.Agent.Provider.Anthropic.pas
    └── Dext.AI.Agent.Provider.Ollama.pas

Sources/AI/Graph/
├── Dext.AI.Graph.Contracts.pas      ICompiledAgent, ICheckpointer, TNodeHandler, TNodeContext
├── Dext.AI.Graph.State.pas          TAgentState (imutável)
├── Dext.AI.Graph.Edge.pas           TEdge, TEdgeRoute, TEdgeCondition
├── Dext.AI.Graph.Graph.pas          TAgentGraph (o StateGraph)
├── Dext.AI.Graph.Compiled.pas       TCompiledAgent (Run/Resume/Cancel/GetState/AsNode)
├── Dext.AI.Graph.Checkpointer.pas   TMemoryCheckpointer, TFileCheckpointer
└── Nodes/
    ├── Dext.AI.Graph.Node.LLM.pas    TLLMNode (nó padrão que chama o LLM)
    └── Dext.AI.Graph.Node.Tools.pas  TToolsNode (nó padrão que executa tools)
```

---

## 🚀 Dext.AI.Agent — Início Rápido

```pascal
uses
  Dext.AI.Agent.Contracts,
  Dext.AI.Agent.Factory,
  Dext.AI.Agent.Observer,
  Dext.AI.MCP.Tools;

var
  Config:   TAgentConfig;
  Provider: ILLMProvider;
  Runner:   TAgentRunner;
  Result:   TAgentResult;
begin
  Config := TAgentConfig.OpenAI('gpt-4o');
  Config.ApiKey       := GetEnvironmentVariable('OPENAI_API_KEY');
  Config.SystemPrompt := 'Você é um assistente útil. Use as tools para responder com precisão.';

  Provider := TLLMFactory.CreateProvider(Config);

  Runner := TAgentRunner.Create(Provider, Config, TConsoleObserver.Create);
  try
    Runner.RegisterProvider(TMyToolProvider.Create); // qualquer TMCPToolProvider
    Result := Runner.Run('Quantos arquivos .pas existem em Sources/AI/Graph?');
    Writeln(Result.FinalAnswer);
  finally
    Runner.Free;
  end;
end;
```

`TAgentConfig` tem construtores de fábrica para os três providers nativos:

```pascal
TAgentConfig.OpenAI('gpt-4o');
TAgentConfig.Anthropic('claude-sonnet-4-6');
TAgentConfig.Ollama('llama3.2');            // BaseUrl padrão: http://localhost:11434
```

`TLLMFactory.CreateProvider(Config)` lê `Config.ProviderString` (`'openai:gpt-4o'`, `'anthropic:...'`, `'ollama:...'`) e devolve o `ILLMProvider` correspondente. `ILLMProvider` é uma interface de estratégia pequena — implemente a sua para qualquer provider que não venha pronto:

```pascal
ILLMProvider = interface
  function Complete(const AMessages: TArray<TLLMMessage>;
    const ATools: TArray<TToolSchema>): TLLMResponse;
  function ProviderName: string;
  function ModelName: string;
end;
```

`IAgentObserver` é chamado a cada passo do loop ReAct (`OnIterationStart`, `OnToolCall`, `OnToolResult`, `OnLLMResponse`, `OnFinished`) — implemente o seu próprio para transmitir o progresso para uma UI, um arquivo de log ou um endpoint SSE, em vez do `TConsoleObserver` (que escreve no console).

**Exemplo completo funcionando:** [Examples/AI/AgentDemo](../../Examples/AI/AgentDemo/)

---

## 🕸️ Dext.AI.Graph — Início Rápido

A API do grafo espelha o `StateGraph` do LangGraph quase um para um:

```pascal
LangGraph (Python)              Dext.AI.Graph (Delphi)
──────────────────────────      ────────────────────────────────
StateGraph(State)             → TAgentGraph.Create
graph.add_node(name, fn)      → Graph.AddNode(name, Handler)
graph.set_entry_point(name)   → Graph.SetEntryPoint(name)
graph.add_edge(a, b)          → Graph.AddEdge(a, b)
graph.add_conditional_edges   → Graph.AddConditionalEdge(from, cond, routes)
START / END                   → GRAPH_START / GRAPH_END
graph.compile()                → Graph.Compile(Provider, Config, Observer, Checkpointer)
compiled.invoke(input)         → Agent.Run(input, threadId)
MemorySaver                    → TMemoryCheckpointer
interrupt_before                → InterruptBefore([...]) / .RequireApproval(node)
Command(resume=...)            → Agent.Resume(threadId)
Subgraphs                      → ICompiledAgent.AsNode
```

Um grafo ReAct mínimo — `call_llm` chama o modelo, roteia para `execute_tools` se ele pediu uma tool, volta em loop, e para quando o modelo tem uma resposta final:

```pascal
uses
  Dext.AI.Graph.Contracts, Dext.AI.Graph.State, Dext.AI.Graph.Edge,
  Dext.AI.Graph.Graph, Dext.AI.Graph.Compiled, Dext.AI.Graph.Checkpointer,
  Dext.AI.Graph.Node.LLM, Dext.AI.Graph.Node.Tools;

var
  ToolsNode: TToolsNode;
  LLMNode:   TLLMNode;
  Graph:     TAgentGraph;
  Agent:     ICompiledAgent;
  Result:    TGraphRunResult;
begin
  ToolsNode := TToolsNode.Create;
  ToolsNode.RegisterProvider(TMyToolProvider.Create);
  LLMNode := TLLMNode.Create(ToolsNode.GetToolSchemas);

  Graph := TAgentGraph.Create;
  try
    Agent := Graph
      .AddNode('call_llm', LLMNode.AsHandler)
      .AddNode('execute_tools', ToolsNode.AsHandler)
      .SetEntryPoint('call_llm')
      .AddConditionalEdge('call_llm', DefaultShouldContinue,
        [TEdgeRoute.To_('execute_tools'), TEdgeRoute.ToEnd])
      .AddEdge('execute_tools', 'call_llm')
      .Compile(Provider, Config, Observer, TMemoryCheckpointer.Create);
  finally
    Graph.Free; // TCompiledAgent copia nós/edges — seguro liberar logo após o Compile
  end;

  Result := Agent.Run('Quantos arquivos .pas existem em Sources/AI/Graph?', 'thread-1');
  Writeln(Result.FinalAnswer);
end;
```

**Exemplo completo (todos os recursos abaixo ligados juntos):** [Examples/AI/GraphDemo](../../Examples/AI/GraphDemo/)

### Conceitos principais

| Tipo | Papel |
|---|---|
| `TAgentState` | Estado imutável que flui pelo grafo — mensagens, tool calls pendentes, nó atual, contador de iteração, metadata. Todo método `With*` devolve uma **nova** instância; nada é alterado no lugar. |
| `TNodeHandler` | `reference to function(const AState: TAgentState; const ACtx: TNodeContext): TAgentState` — um nó é só uma função de estado para estado. |
| `TEdge` | Fixa (`AddEdge`) ou condicional (`AddConditionalEdge`, guiada por um `TEdgeCondition` que inspeciona o estado e devolve o nome do próximo nó). |
| `ICompiledAgent` | O resultado do `Compile()` — `Run`, `Resume`, `Cancel`, `GetState`, `AsNode`. |
| `ICheckpointer` | Persiste o `TAgentState` de uma thread (como JSON) para que a mesma `AThreadId` possa ser retomada entre chamadas de `Run` — e, com `TFileCheckpointer`, entre reinícios do processo. |

### Human-in-the-loop (aprovação humana)

Marque um nó como exigindo aprovação — o grafo pausa **antes** de executá-lo e devolve `grsWaitingApproval` em vez de rodar:

```pascal
Graph.RequireApproval('execute_tools');
// equivalente: Graph.InterruptBefore(['execute_tools']);
```

```pascal
Result := Agent.Run(Input, ThreadId);
if Result.Status = grsWaitingApproval then
begin
  Writeln('Nó pendente: ' + Result.PendingNode);
  if UsuarioAprovou then
    Result := Agent.Resume(ThreadId)
  else
    Agent.Cancel(ThreadId);
end;
```

`Resume` reexecuta o próprio nó pausado e continua o loop normalmente. `Cancel` apaga o checkpoint da thread.

### Checkpointing

```pascal
TMemoryCheckpointer.Create;              // local ao processo, some ao sair
TFileCheckpointer.Create;                // arquivos JSON em %TEMP%\dext-ai-graph
TFileCheckpointer.Create('C:\MeuCaminho'); // ou um caminho à sua escolha
```

Os dois implementam a interface `ICheckpointer`, pequena (`Save`/`Load`/`Exists`/`Delete`) — implemente a sua para persistir numa tabela de banco de dados em vez disso.

### Subgrafos (`AsNode`)

Um grafo compilado pode ser embutido como um único nó de outro grafo — é assim que se compõem sub-agentes independentes e testáveis separadamente (um agente "Fiscal" dentro de um grafo "ERP" maior, por exemplo), em vez de achatar os nós de cada sub-agente num único grafo gigante:

```pascal
FiscalAgent := FiscalGraph.AddNode(...).SetEntryPoint(...).Compile(Provider, Config);

ERPGraph.AddNode('fiscal_agent', FiscalAgent.AsNode);
```

`TAgentState` é um único tipo concreto em todos os grafos do Dext.AI.Graph (diferente dos schemas tipados por grafo do LangGraph), então não há etapa de tradução de estado na fronteira do subgrafo — o estado do pai passa direto, o subgrafo roda do seu próprio ponto de entrada até seu próprio `GRAPH_END`, e o estado resultante (incluindo toda mensagem que ele anexou) volta para o pai, que então decide o que acontece depois através das suas próprias edges.

> **Restrição:** um subgrafo não pode declarar `RequireApproval`/`InterruptBefore` em nenhum nó seu — `AsNode` levanta `EGraphCompileError` imediatamente, em vez de pular a aprovação silenciosamente. Se alguma parte do fluxo do subgrafo precisar de aprovação humana, coloque `RequireApproval` no nó do grafo **pai** que envolve a chamada do subgrafo. Human-in-the-loop aninhado ainda não é suportado.

---

## 🧭 Vem do LangGraph? O que está coberto, o que não está

| LangGraph | Dext.AI.Graph |
|---|---|
| `StateGraph` | ✅ `TAgentGraph` |
| funções de nó | ✅ `TNodeHandler` |
| `add_edge` / `add_conditional_edges` | ✅ `AddEdge` / `AddConditionalEdge` |
| `compile()` | ✅ `Compile()` |
| `MemorySaver` | ✅ `TMemoryCheckpointer` / `TFileCheckpointer` |
| multi-turn via `thread_id` | ✅ `AThreadId` |
| `interrupt_before` + resume/cancel | ✅ `RequireApproval` / `InterruptBefore` + `Resume` / `Cancel` |
| Subgrafos | ✅ `ICompiledAgent.AsNode` |
| `recursion_limit` | ✅ `MaxIterations` |
| Schema de estado tipado por grafo | ❌ `TAgentState` é um tipo fixo único; dados extras vão no `Metadata` (string→string) |
| Entry point condicional/dinâmico | ❌ `GRAPH_START` existe só como nome reservado; a entrada é sempre fixa via `SetEntryPoint` |
| `interrupt_after` | ❌ só "antes" é suportado |
| Interrupts dinâmicos (`interrupt()` dentro de um nó) | ❌ interrupts precisam ser declarados estaticamente no grafo |
| `update_state` | ❌ `GetState` é somente leitura; não há como editar o estado pausado antes do `Resume` |
| Human-in-the-loop aninhado | ❌ explicitamente rejeitado pelo `AsNode` (falha alto, não silenciosamente) |
| `get_state_history` / time travel | ❌ o checkpointer guarda só o último estado por thread |
| `Store` (memória de longo prazo entre threads) | ❌ persistência é só por thread |
| `stream_mode` (streaming de primeira classe) | ⚠️ parcial — `IAgentObserver` dá callbacks síncronos, não um stream/generator |
| Fan-out / ramos paralelos (`Send`) | ⚠️ **armadilha**: adicionar mais de um `AddEdge` a partir do mesmo nó de origem não é erro — só a *primeira* é usada, o resto é ignorado silenciosamente. Não há fan-out paralelo automático. |
| Retry policy / cache de resultado por nó | ❌ não implementado |
| `Command` (nó devolve roteamento + atualização de estado juntos) | ❌ o roteamento sempre passa pelas edges |

Se o seu caso de uso precisar de ramos paralelos de verdade, histórico de estado para auditoria, ou memória entre threads, esses são gaps reais hoje, não só documentação faltando.

---

## 📂 Exemplos

- **[AgentDemo](../../Examples/AI/AgentDemo/)** — loop ReAct de agente único com tools de sistema de arquivos.
- **[GraphDemo](../../Examples/AI/GraphDemo/)** — todo o conjunto de recursos do grafo ligado junto: roteamento condicional, `RequireApproval` + `Resume`/`Cancel`, persistência via `TFileCheckpointer` entre reinícios, e um subgrafo `polish_agent` embutido via `AsNode`.
