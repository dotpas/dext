# 🤖 AI Agents & Orchestration (Dext.AI.Agent + Dext.AI.Graph)

Dext ships two orchestration layers on top of [Dext MCP](../15-mcp-server/README.md), for teams who want the LangChain/LangGraph mental model in native Delphi, with zero external dependencies beyond the RTL:

- **`Dext.AI.Agent`** — a single-agent ReAct loop (think **LangChain**'s `AgentExecutor`): one provider, one tool set, one conversation.
- **`Dext.AI.Graph`** — graph-based orchestration on top of it (think **LangGraph**'s `StateGraph`): explicit nodes and edges, conditional routing, checkpointed multi-turn state, human-in-the-loop approval, and sub-agent composition.

Use `Dext.AI.Agent` when a plain "call the LLM, run tools, repeat until done" loop is enough. Reach for `Dext.AI.Graph` when you need more than one distinct step (a router, a review step, multiple cooperating agents) or you need to pause and resume across turns/processes.

Both build directly on the `TMCPToolProvider` / `[MCPTool]` / `[MCPParam]` pattern from the [MCP chapter](../15-mcp-server/README.md) — the same declarative tools you'd expose to an external AI client can be reused as an agent's own tool set.

---

## 📦 Where things live

```
Sources/AI/Agent/
├── Dext.AI.Agent.Contracts.pas      ILLMProvider, TLLMMessage, TAgentConfig, IAgentObserver
├── Dext.AI.Agent.Factory.pas        TLLMFactory.CreateProvider(config)
├── Dext.AI.Agent.Runner.pas         TAgentRunner (single-agent ReAct loop)
├── Dext.AI.Agent.Observer.pas       IAgentObserver, TConsoleObserver
└── Providers/
    ├── Dext.AI.Agent.Provider.OpenAI.pas
    ├── Dext.AI.Agent.Provider.Anthropic.pas
    └── Dext.AI.Agent.Provider.Ollama.pas

Sources/AI/Graph/
├── Dext.AI.Graph.Contracts.pas      ICompiledAgent, ICheckpointer, TNodeHandler, TNodeContext
├── Dext.AI.Graph.State.pas          TAgentState (immutable)
├── Dext.AI.Graph.Edge.pas           TEdge, TEdgeRoute, TEdgeCondition
├── Dext.AI.Graph.Graph.pas          TAgentGraph (the StateGraph)
├── Dext.AI.Graph.Compiled.pas       TCompiledAgent (Run/Resume/Cancel/GetState/AsNode)
├── Dext.AI.Graph.Checkpointer.pas   TMemoryCheckpointer, TFileCheckpointer
└── Nodes/
    ├── Dext.AI.Graph.Node.LLM.pas    TLLMNode (default LLM-calling node)
    └── Dext.AI.Graph.Node.Tools.pas  TToolsNode (default tool-executing node)
```

---

## 🚀 Dext.AI.Agent — Quick Start

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
  Config.SystemPrompt := 'You are a helpful assistant. Use tools to answer accurately.';

  Provider := TLLMFactory.CreateProvider(Config);

  Runner := TAgentRunner.Create(Provider, Config, TConsoleObserver.Create);
  try
    Runner.RegisterProvider(TMyToolProvider.Create); // any TMCPToolProvider
    Result := Runner.Run('How many .pas files are in Sources/AI/Graph?');
    Writeln(Result.FinalAnswer);
  finally
    Runner.Free;
  end;
end;
```

`TAgentConfig` has factory constructors for the three built-in providers:

```pascal
TAgentConfig.OpenAI('gpt-4o');
TAgentConfig.Anthropic('claude-sonnet-4-6');
TAgentConfig.Ollama('llama3.2');            // BaseUrl defaults to http://localhost:11434
```

`TLLMFactory.CreateProvider(Config)` reads `Config.ProviderString` (`'openai:gpt-4o'`, `'anthropic:...'`, `'ollama:...'`) and returns the matching `ILLMProvider`. `ILLMProvider` is a single, small strategy interface — implement it yourself for any provider not built in:

```pascal
ILLMProvider = interface
  function Complete(const AMessages: TArray<TLLMMessage>;
    const ATools: TArray<TToolSchema>): TLLMResponse;
  function ProviderName: string;
  function ModelName: string;
end;
```

`IAgentObserver` gets called at every step of the ReAct loop (`OnIterationStart`, `OnToolCall`, `OnToolResult`, `OnLLMResponse`, `OnFinished`) — implement your own to stream progress into a UI, log file, or SSE endpoint instead of `TConsoleObserver`'s stdout.

**Full working example:** [Examples/AI/AgentDemo](../../Examples/AI/AgentDemo/)

---

## 🕸️ Dext.AI.Graph — Quick Start

The graph API mirrors LangGraph's `StateGraph` almost one to one:

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

A minimal ReAct graph — `call_llm` calls the model, routes to `execute_tools` if it asked for a tool, loops back, and stops when the model has a final answer:

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
    Graph.Free; // TCompiledAgent copies nodes/edges — safe to free right after Compile
  end;

  Result := Agent.Run('How many .pas files are in Sources/AI/Graph?', 'thread-1');
  Writeln(Result.FinalAnswer);
end;
```

**Full working example (all features below wired together):** [Examples/AI/GraphDemo](../../Examples/AI/GraphDemo/)

### Core concepts

| Type | Role |
|---|---|
| `TAgentState` | Immutable state that flows through the graph — messages, pending tool calls, current node, iteration count, metadata. Every `With*` method returns a **new** instance; nothing mutates in place. |
| `TNodeHandler` | `reference to function(const AState: TAgentState; const ACtx: TNodeContext): TAgentState` — a node is just a function from state to state. |
| `TEdge` | Fixed (`AddEdge`) or conditional (`AddConditionalEdge`, driven by a `TEdgeCondition` that inspects state and returns the next node's name). |
| `ICompiledAgent` | The result of `Compile()` — `Run`, `Resume`, `Cancel`, `GetState`, `AsNode`. |
| `ICheckpointer` | Persists a thread's `TAgentState` (as JSON) so the same `AThreadId` can be resumed across `Run` calls — and, with `TFileCheckpointer`, across process restarts. |

### Human-in-the-loop

Mark a node as requiring approval — the graph pauses **before** running it and returns `grsWaitingApproval` instead of executing:

```pascal
Graph.RequireApproval('execute_tools');
// equivalent: Graph.InterruptBefore(['execute_tools']);
```

```pascal
Result := Agent.Run(Input, ThreadId);
if Result.Status = grsWaitingApproval then
begin
  Writeln('Pending node: ' + Result.PendingNode);
  if UserApproves then
    Result := Agent.Resume(ThreadId)
  else
    Agent.Cancel(ThreadId);
end;
```

`Resume` re-executes the paused node itself, then continues the loop normally. `Cancel` deletes the thread's checkpoint.

### Checkpointing

```pascal
TMemoryCheckpointer.Create;              // process-local, gone on exit
TFileCheckpointer.Create;                // JSON files under %TEMP%\dext-ai-graph
TFileCheckpointer.Create('C:\MyPath');   // or a path you choose
```

Both implement the tiny `ICheckpointer` interface (`Save`/`Load`/`Exists`/`Delete`) — implement your own to persist to a database table instead.

### Subgraphs (`AsNode`)

A compiled graph can be embedded as a single node of another graph — this is how you compose independent, separately-tested sub-agents (a "Fiscal" agent inside a larger "ERP" graph, for example) instead of flattening every sub-agent's nodes into one giant graph:

```pascal
FiscalAgent := FiscalGraph.AddNode(...).SetEntryPoint(...).Compile(Provider, Config);

ERPGraph.AddNode('fiscal_agent', FiscalAgent.AsNode);
```

`TAgentState` is a single concrete type across every graph in Dext.AI.Graph (unlike LangGraph's per-graph typed schemas), so there is no state-translation step at the subgraph boundary — the parent's state is passed straight through, the subgraph runs from its own entry point to its own `GRAPH_END`, and the resulting state (including every message it appended) flows back to the parent, which then decides what happens next via its own edges.

> **Constraint:** a subgraph cannot itself declare `RequireApproval`/`InterruptBefore` on any node — `AsNode` raises `EGraphCompileError` immediately rather than silently skipping the approval step. If part of a subgraph's flow needs human approval, put `RequireApproval` on the **parent** node that wraps the subgraph call. Nested human-in-the-loop isn't supported yet.

---

## 🧭 Coming from LangGraph? What's covered, what isn't

| LangGraph | Dext.AI.Graph |
|---|---|
| `StateGraph` | ✅ `TAgentGraph` |
| node functions | ✅ `TNodeHandler` |
| `add_edge` / `add_conditional_edges` | ✅ `AddEdge` / `AddConditionalEdge` |
| `compile()` | ✅ `Compile()` |
| `MemorySaver` | ✅ `TMemoryCheckpointer` / `TFileCheckpointer` |
| `thread_id` multi-turn | ✅ `AThreadId` |
| `interrupt_before` + resume/cancel | ✅ `RequireApproval` / `InterruptBefore` + `Resume` / `Cancel` |
| Subgraphs | ✅ `ICompiledAgent.AsNode` |
| `recursion_limit` | ✅ `MaxIterations` |
| Typed per-graph state schema | ❌ `TAgentState` is one fixed type; extra data goes in `Metadata` (string→string) |
| Conditional/dynamic entry point | ❌ `GRAPH_START` exists only as a reserved name; entry is always fixed via `SetEntryPoint` |
| `interrupt_after` | ❌ only "before" is supported |
| Dynamic interrupts (`interrupt()` inside a node) | ❌ interrupts must be statically declared on the graph |
| `update_state` | ❌ `GetState` is read-only; no way to edit paused state before `Resume` |
| Nested human-in-the-loop | ❌ explicitly rejected by `AsNode` (fails loud, not silently) |
| `get_state_history` / time travel | ❌ the checkpointer keeps only the latest state per thread |
| `Store` (cross-thread long-term memory) | ❌ persistence is per-thread only |
| `stream_mode` (first-class streaming) | ⚠️ partial — `IAgentObserver` gives synchronous callbacks, not a stream/generator |
| Fan-out / parallel branches (`Send`) | ⚠️ **pitfall**: adding more than one `AddEdge` from the same source node is not an error — only the *first* one is ever used, the rest are silently ignored. There is no automatic parallel fan-out. |
| Retry policy / node result caching | ❌ not implemented |
| `Command` (node returns routing + state update together) | ❌ routing always goes through edges |

If your use case needs real parallel branches, state history for auditing, or cross-thread memory, those are gaps today, not just missing docs.

---

## 📂 Example Projects

- **[AgentDemo](../../Examples/AI/AgentDemo/)** — single-agent ReAct loop with filesystem tools.
- **[GraphDemo](../../Examples/AI/GraphDemo/)** — the full graph feature set wired together: conditional routing, `RequireApproval` + `Resume`/`Cancel`, `TFileCheckpointer` persistence across restarts, and a `polish_agent` subgraph embedded via `AsNode`.
