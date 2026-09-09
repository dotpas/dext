# 🧠 Dext AI - Roadmap

Este roadmap define a estratégia para integrar Inteligência Artificial Generativa (GenAI) e LLMs diretamente no ecossistema Dext.

> **Visão:** Trazer o poder de orquestração do **Semantic Kernel** e **LangChain** para o Delphi, permitindo que desenvolvedores construam aplicações "AI-Native" com a mesma facilidade que constroem APIs Web.

---

## 🌐 Model Context Protocol (MCP) Server

Permite expor ferramentas e recursos do Dext para agentes de IA externos (como Claude Desktop/Code).
- [x] **Core Server**: Implementação da especificação MCP 2025-03-26. (Concluído com contribuição da comunidade)
- [x] **Transports**: Suporte a `HTTP Streamable`, `SSE` e `Stdio`. (Concluído com contribuição da comunidade)
- [x] **RTTI Attributes**: `[MCPTool]`, `[MCPResource]`, `[MCPPrompt]` para registro declarativo. (Concluído com contribuição da comunidade)
- [x] **Integração Web**: Suporte a endpoints concorrentes `/mcp` e `HTTP Streamable Sessions` integrado ao Dext.WebHost. (Concluído com contribuição da comunidade)

---

## 🤖 Dext.SemanticKernel (Orchestration)

Inspirado no Microsoft Semantic Kernel, este módulo será o "cérebro" para integrar LLMs com código nativo.

> **Nota (2026-08):** o núcleo de orquestração (chamada de LLM multi-provider, function
> calling via RTTI, loop de agente com tools, e agora orquestração via grafo estilo
> LangGraph) já foi implementado — mas sob os nomes `Dext.AI.Agent` e `Dext.AI.Graph`,
> não `Dext.SemanticKernel`. Ver [Capítulo 16 do Book](../Book/16-ai-agents/README.md).
> Os itens abaixo marcados como concluídos refletem o que já existe sob esses nomes;
> o restante (embeddings, planner dedicado, plugins ao estilo Semantic Kernel) continua
> em aberto. Mantendo o roadmap original sem reescrever a decisão de nomenclatura —
> só sinalizando onde o que já existe se encaixa.

### 1. Core Abstractions
- [x] **IChatCompletion**: interface unificada de chat multi-provider — implementada como
      `ILLMProvider` (`Dext.AI.Agent.Contracts`), com providers para OpenAI, Anthropic e Ollama.
- [ ] **ITextEmbedding**: Interface para geração de vetores (embeddings).
- [ ] **Prompt Templates**: Engine para renderizar prompts dinâmicos com variáveis (`"Olá {{name}}, ajude-me com..."`).

### 2. Plugins & Native Functions (The "Glue")
A capacidade de LLMs chamarem código Delphi (Function Calling).
- [x] **Native Plugins**: expor classes Delphi como tools para a IA via RTTI — implementado
      como `TMCPToolProvider` + `[MCPTool]`/`[MCPParam]` (`Dext.AI.MCP.*`), reaproveitado
      diretamente por `Dext.AI.Agent`/`Dext.AI.Graph` como o conjunto de tools do agente.
  - Geração automática de Schema JSON para a LLM entender a função. ✅
- [x] **Planner**: um agente que decide quais funções chamar para resolver uma solicitação
      complexa — implementado como o loop ReAct de `TAgentRunner` (agente único) e como o
      grafo `TAgentGraph`/`ICompiledAgent` (roteamento condicional, checkpoint,
      human-in-the-loop, subgrafos via `AsNode`) para orquestração multi-etapa/multi-agente.

### 3. Structured Output (Pydantic-like)
- [ ] **Schema Validation**: Garantir que a IA retorne JSON válido que mapeia exatamente para um `record` ou `class` Delphi.
- [ ] **Auto-Repair**: Tentar corrigir JSON inválido automaticamente.

---

## 🧠 Memory & Vector Database (RAG)

Implementação do padrão RAG (Retrieval-Augmented Generation) para dar "memória" e contexto à IA.

### 1. Vector Store Abstraction (`IVectorStore`)
Interface genérica para armazenar e buscar vetores.
- [ ] **In-Memory Store**: Para testes e datasets pequenos.
- [ ] **Pgvector Support**: Integração nativa com PostgreSQL (via Dext ORM).
- [ ] **Qdrant/Pinecone**: Drivers para bancos vetoriais dedicados.

### 2. Document Processing
- [ ] **Text Splitters**: Utilitários para quebrar textos grandes em chunks (Token-based, Line-based).
- [ ] **Document Loaders**: Leitores para PDF, Text, Markdown.

---

## ⚡ Local Inference & Data

### 1. Local LLM Support
- [ ] **Ollama Integration**: Cliente nativo otimizado para Ollama (Llama 3, Phi-3).
- [ ] **ONNX Runtime**: (Investigação) Executar modelos menores (embeddings, classificação) in-process.

### 2. Data Processing
- [ ] **Dext.Data**: Estruturas de dados leves para manipulação tabular (inspirado em DataFrames, mas focado em performance e tipagem).

---

## 📅 Exemplo de Uso (Vision)

```delphi
var
  Kernel: IKernel;
  Result: string;
begin
  Kernel := TSemanticKernel.CreateBuilder
    .AddOpenAIChatCompletion('gpt-4')
    .AddPlugin<TOrderPlugin>('Orders') // Expose Delphi code
    .Build;

  // A IA decide chamar TOrderPlugin.GetOrderStatus(123) automaticamente
  Result := await Kernel.InvokeAsync('Qual o status do meu pedido 123?');
end;
```
