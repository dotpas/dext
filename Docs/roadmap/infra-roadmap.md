# 🏗️ Dext Infrastructure - Roadmap

Este documento centraliza o desenvolvimento da infraestrutura de baixo nível do framework, com foco em **Performance Extrema**.

> **Visão:** Prover uma fundação sólida, "Metal-to-the-Pedal", que permita ao Dext competir em performance com frameworks Go, Rust e .NET.

---

## 📊 Status Atual: **Release Candidate 1.0** 🚀

A infraestrutura base está estabilizada, com drivers plugáveis para alta performance e suporte a zero-allocation parsing.

*Última atualização: 07 de Abril de 2026*

## 🚀 High Performance HTTP Server

Estratégia de servidores plugáveis (`Server Adapters`) para permitir estabilidade imediata e performance extrema futura, sem quebrar a API pública.

### 1. V1: Driver Indy (Estabilidade) - ✅ Concluído
- [x] **TDextIndyWrapper**: Wrapper para compatibilidade Indy. Renomeado para clareza de licenciamento.
- [x] **Lazy Evaluation**: Headers e Query String processados sob demanda.
- [x] **Stream Wrapping**: Encapsulamento de buffers sem cópia de memória.

### 2. V2: Enterprise Driver (Kestrel NativeAOT) - 📅 Planejado

Estratégia para performance "estado da arte" usando o motor do ASP.NET Core via interoperabilidade nativa.

- [ ] **NativeAOT Wrapper**: Biblioteca C# compilada como Native Library (`.dll`/`.so`) exportando interface C.
- [ ] **Zero-Copy Bridge**: Passagem de ponteiros de memória (Pinned Memory) do .NET para o Delphi.
- [x] **TSpan<T>**: Implementação de `Memory<T>`/`Span<T>` no Delphi para ler os buffers do Kestrel sem alocação de strings.

### 3. V3: Native Drivers (Bare Metal) - 🔮 Futuro

Implementações 100% Pascal para cenários onde dependências externas não são desejadas.

> 📑 **Specs**: [S39 — Native Server Engine](../Specs/S39-Native-Server-Engine.md) | [S40 — WebSocket & SignalR](../Specs/S40-WebSocket-SignalR.md) | [S41 — HTTP/2 Framing](../Specs/S41-Http2-Framing.md)

- [ ] **Windows**: Integração direta com `http.sys` (Kernel Mode) + IOCP Sockets para protocolos customizados.
- [ ] **Linux**: Event Loop baseado em `epoll` integrado ao Scheduler do Dext.Async.
- [ ] **WebSocket**: Transporte nativo RFC 6455 integrado ao `Dext.Web.Hubs` (SignalR).
- [ ] **HTTP/2**: HPACK + Stream Multiplexing para suporte a gRPC (S02).

Reescrita do núcleo HTTP para eliminar gargalos de arquiteturas legadas (Indy/WebBroker) e explorar recursos nativos do SO.

### 1. Windows: Kernel Mode (`http.sys`)

Integração direta com o driver `http.sys` do Windows (mesma stack do IIS e Kestrel).

- [ ] **Native API Binding**: Importação da `httpapi.dll` (HttpInitialize, HttpCreateHttpHandle).
- [ ] **Zero-Copy**: Utilizar buffers do kernel para evitar cópias desnecessárias de memória.
- [ ] **Kernel-Mode Caching**: Servir arquivos estáticos e respostas cacheadas diretamente do Kernel.
- [ ] **Port Sharing**: Permitir compartilhar a porta 80/443 com IIS e outras apps.
- [ ] **HTTP/3 (QUIC)**: Suporte experimental ao novo protocolo HTTP sobre UDP para performance em redes instáveis.

### 2. Linux: Event-Driven I/O (`epoll`)

Modelo não-bloqueante para alta concorrência no Linux.

- [ ] **Epoll Integration**: Uso de `epoll_create1`, `epoll_ctl`, `epoll_wait`.
- [ ] **Thread Pool**: Workers fixos (CPU Bound) processando eventos de I/O de milhares de conexões.
- [ ] **Non-Blocking Sockets**: Eliminar o modelo "Thread-per-Connection".

### 3. Memory & String Optimization (Zero-Allocation)

Eliminar o custo de conversão `UTF-8` <-> `UTF-16` (UnicodeString) no core do framework.

- [x] **RawUTF8 / Span<byte>**: Tipo de dados base para manipulação de strings sem conversão.
- [x] **Zero-Allocation Parsing**: Roteamento e Headers processados varrendo bytes diretamente.
- [x] **UTF-8 JSON Parser**: Novo parser JSON otimizado para ler/escrever UTF-8 diretamente, sem alocações intermediárias de strings Delphi.

---

## 🛠️ Core Infrastructure

### 1. Memory Optimization

- [x] **TSpan<T>**: Estrutura para fatiamento de arrays/memória sem alocação (essencial para o JSON Parser V2).
- [x] **Zero-Allocation JSON**: Parser JSON baseado em `TSpan<Byte>` (UTF-8) para evitar transcoding para UTF-16.

### 2. JSON Configuration Enhancements

- [x] **Global Default Settings**: Configuração global de `TDextSettings` via `TDextJson.SetDefaultSettings` para aplicar case-insensitivity e outras opções em toda a aplicação.
- [ ] **Per-Context Settings**: Permitir configuração de JSON settings por contexto/endpoint via middleware ou atributos, útil para integração com APIs externas (bancos, governo) que possuem padrões diferentes.
  - *Exemplo*: `[JsonSettings(CaseStyle.SnakeCase)]` em um controller específico.
  - *Middleware*: `UseJsonSettings(settings)` para aplicar em um grupo de rotas.

### 3. Telemetry & Observability Foundation

Base para o suporte a OpenTelemetry nos frameworks superiores.

- [ ] **Activity/Span API**: Abstração para rastreamento distribuído.
- [ ] **Metrics API**: Contadores, Histogramas e Gauges de alta performance.
- [ ] **Logging Abstraction**: Zero-allocation logging interface.

### 3. Advanced Async & Concurrency

Evolução da `Fluent Tasks API` para suportar cenários complexos de orquestração e alta performance.

- [x] **Fluent Tasks Core**: Implementação base (`TAsyncTask`, `ThenBy`, `WithCancellation`).
- [x] **Unsynchronized Callbacks**: Opção para executar callbacks em thread de background (evitar gargalo na Main Thread).
- [ ] **Testing Scheduler**: Implementação de `DefaultScheduler` para permitir testes unitários determinísticos (síncronos) de código assíncrono.
  - *API*: `.OnCompleteAsync(proc)`, `.OnExceptionAsync(proc)`
- [ ] **Composition Patterns (Fork/Join)**:
  - `WhenAll(Tasks)`: Aguardar múltiplas tasks finalizarem (Scatter-Gather).
  - `WhenAny(Tasks)`: Retornar assim que a primeira task finalizar (Redundancy/Race).
- [ ] **Parallel Data Processing**:
  - Integração com loops paralelos fluentes.
  - *Exemplo*: `TAsyncTask.For(0, 1000).Process(procedure(I) ...).Start`
- [ ] **Resilience Patterns**:
  - **Retry**: `.Retry(Count, Delay)` para falhas transientes.
  - **Circuit Breaker**: Proteger recursos externos de sobrecarga.
  - **Timeout**: `Timeout(500ms)` forçando cancelamento se exceder o tempo.
- [ ] **Progress Reporting**:
  - Suporte a `IProgress<T>` para notificar progresso granular sem acoplar com UI.
- [ ] **Telemetry Hooks**:
  - Log automático de tempo de execução, exceções e cancelamentos via `Core.Telemetry`.

---

## 🧪 Testing Ecosystem & Quality Assurance (Dext.Testing)

> Catálogo: [Dext-Testing-Features-Catalog.md](../Dext-Testing-Features-Catalog.md).  
> Framework + coverage CLI = Stable · Explorer = Evolving (#1) · Sidecar essentials // · C++ / UIA / mutation / contracts = Planned.

### 1. Framework (shipped — Stable)

- [x] Attribute runner, Fluent Assertions (`Should`), Mocks + Arg/Times, Snapshots, multi-format reports.
- [x] DUnit / DUnitX / DUnit2 adapters → Test Explorer.
- [x] `dext test --coverage` (HTML/XML/Sonar).
- [ ] **Async Mocking**: `ReturnsAsync` helpers (roadmap).
- [ ] Contract tests / mutation / WireMock-like (roadmap P2).

### 2. IDE Test Explorer (S36 — Evolving) — prioridade #1

> Package: `Packages/d13/Dext.Testing.Design.dproj`.

- [x] MVP Presenter, async compile/run, Winsock shutdown with client close.
- [x] Coverage gutter re-enabled with OTA lifetime management.
- [x] Suite-total history in Explorer (`suite_history.json`, S75 F-10).
- [x] Tagged console log + RichEdit color polish.
- [ ] Coverage **visual** polish for demos / daily use.
- [ ] Further Passive View migration of remaining DockableForm paths.
- [x] Non-Dext / legacy demo sample (`Tests/Samples/Cap18b.LegacyDUnitX`).

### 3. Sidecar (essentials in parallel)

- [x] http.sys + SignalR/SSE; `dext ui` removed.
- [ ] Companion AutoAttach + session — **não bloqueia livro**.
- [ ] Testcontainers-like + aba Sidecar ← evolve `infra/tests` (later).

### 4. C++Builder & UI Automation (Planned — strategic)

- [ ] Expert como DLL/OTA + instalador.
- [ ] Spike UI Automation (Delphi 13 VCL UIA).

---

## 📦 Deployment & Modularization

### 1. Pluggable Database Drivers (Professional/Community Edition Support)

Evitar dependências obrigatórias de todos os bancos de dados no package principal.

- [x] **Compiler Directives**: Implementação de `DEXT_ENABLE_DB_*` no `Dext.inc` para isolar unidades físicas do FireDAC.
- [ ] **Modular Packages**: Separar drivers físicos em packages específicos (ex: `Dext.EF.Driver.PostgreSQL.dpk`).
- [ ] **Auto-Discovery/Factory**: Sistema para registrar drivers dinamicamente via `initialization`.

### 2. Dext Installer & CLI

Facilitar o setup do ambiente e seleção de módulos.

- [ ] **Modularity Web UI**: Gerador de projetos onde o dev seleciona os bancos e middlewares desejados.
- [ ] **Library Path Manager**: Ferramenta CLI para configurar caminhos do Delphi automaticamente.
- [ ] **Modern CLI Argument Parser**: Criar uma classe robusta para parsing de argumentos de linha de comando (CLI), inspirada nos padrões do .NET (`System.CommandLine` / `CommandLineParser`). O atual `FindCmdLineSwitch` da RTL é limitado.

## 📚 Documentation Generator (dext doc)

Ferramenta para geração de sites estáticos de documentação a partir do código fonte (AST).

### 1. Customization & Theming

- [ ] **Metadata Customization**: Opções CLI/Config para definir Título do Site, Autor, Copyright e Footer personalizado.
- [ ] **Custom CSS/JS**: Suporte a injeção de arquivos `.css` e `.js` do usuário para alterar o tema padrão.
- [ ] **Templates**: Suporte a templates customizáveis (Mustache/Handlebars) para alterar o layout HTML.

### 2. Navigation & Linking

- [ ] **Type Hyperlinking**: Criar links navegáveis automaticamente entre tipos (ex: clicar no tipo de retorno de um método e ir para a página daquele tipo).
- [ ] **Breadcrumbs**: Implementar navegação de migalhas de pão baseada em namespaces.
- [ ] **"View Source" Link**: Link direto para o repositório (GitHub/GitLab) na linha exata da declaração.
- [ ] **Dependency Graphs**: Diagrama Mermaid de dependências entre Units.

### 3. Advanced Content & Parsing

- [ ] **XML Documentation**: Suporte completo às tags XML (`<summary>`, `<param>`, `<returns>`, `<remarks>`, `<code`, `<see cref>`).
- [ ] **Versioning**: Suporte a dropdown de versões (v1, v2) no cabeçalho.
- [ ] **Intelligent Search**: Atalho (Ctrl+K), filtros por tipo (ex: `I:Service`) e busca fuzzy.
- [ ] **Badges**: Badges de métricas (Linhas de código, número de métodos, estabilidade).
