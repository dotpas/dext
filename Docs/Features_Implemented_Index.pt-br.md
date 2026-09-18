# Dext Framework 1.0 — Índice de Features

> **Reading this in English?** The full English index — same coverage, same organization — is in [Features_Implemented_Index.md](Features_Implemented_Index.md). If English is more comfortable, click through and read that document instead.

Índice mestre de todas as funcionalidades implementadas no **Dext 1.0**. Cada item aponta para a unit em `Sources/`.

Organizado por módulo — Core, Web, ORM, Networking, Testing e o restante do ecossistema — para que cada capacidade viva num único capítulo canônico.

> [!IMPORTANT]
> Auditoria nos fontes. Os bullets únicos foram mantidos; duplicatas copiadas foram removidas. Textos sobrepostos foram fundidos.

**Próximas leituras:** [Livro do Dext](Book.pt-br/README.md) · [Matriz de compatibilidade](Delphi_Compatibility_Matrix.md) · [Paridade .NET](Comparison/Feature_Comparison_Dext_vs_DotNet.pt-br.md)

---

## Sumário

1. [Core Foundation](#1-core-foundation) — DI, JSON, configuração, tipos, threading, jobs
2. [Collections](#2-collections) — listas, dicionários, LINQ, SIMD, canais
3. [Web Framework](#3-web-framework) — Minimal APIs, Controllers, middleware, DataAPI, HTTP/2, SSR
4. [ORM & Entity](#4-orm--entity) — DbContext, queries, dialetos, EntityDataSet
5. [Networking](#5-networking) — REST client, Redis, TLS, sockets, MQTT, gRPC
6. [Event Bus](#6-event-bus)
7. [Testing & Quality](#7-testing--quality)
8. [Template Engine](#8-template-engine)
9. [Validation](#9-validation)
10. [Mapper](#10-mapper)
11. [Multi-Tenancy](#11-multi-tenancy)
12. [Desktop UI & Design-Time](#12-desktop-ui--design-time)
13. [CLI & Scaffolding](#13-cli--scaffolding)
14. [Observability](#14-observability)
15. [AI Skills](#15-ai-skills)
16. [MCP Server](#16-mcp-server)

---
## 1. Core Foundation

O Dext foi desenhado para alavancar o Object Pascal moderno, com um piso de compatibilidade documentado. A implementação vive em `Sources\Core` e `Sources\Core\Base`.

### 1.0 Compatibilidade Delphi
- **Mínimo arquitetural**: Delphi 2010 (Extended RTTI, Generics, Attributes).
- **Piso de compilação**: Delphi XE2 ou superior, com fallback HTTP Indy abaixo do XE8 (`TDextIndyHttpEngine`).
- **Tier 1 (completo)**: 10.4 Sydney, 11 Alexandria, 12 Athens — desenvolvimento e CI principais.
- **Tier 2 (suportado)**: 10.1 Berlin – 10.3 Rio — sem variáveis inline; primitivas de sync retroportadas.
- **Web Stencils**: Delphi 12.2+ (Windows). Controlado por `DEXT_ENABLE_WEB_STENCILS` em `Dext.inc`.

Veja a **[Matriz de Compatibilidade Delphi](Delphi_Compatibility_Matrix.md)** para requisitos por feature e compilador.
### 1.1 Reflection Engine (`Dext.Core.Reflection`)
- **TReflection** — Fachada estática de alto desempenho para o sistema RTTI do Delphi. Mantém um `TRttiContext` compartilhado globalmente.
- **Metadata Cache** (`TTypeMetadata`) — Cache global de metadados de tipo (propriedades, campos, atributos) com inicialização thread-safe via `TMREWSync` (Multiple-Read Exclusive-Write). Caminhos hot-path são lock-free (leitura sem lock).
- **Smart Properties** (`Prop<T>`, `Nullable<T>`, `Lazy<T>`) — Detecção automática de wrappers genéricos via análise de `PTypeInfo.Name`. O metadata cache armazena `IsSmartProp`, `IsNullable`, `IsLazy`, `InnerType` e ponteiro direto para `FValue` field.
- **Property Path Resolution** — Resolução recursiva de caminhos aninhados (ex: `User.Address.Street`) via `TReflection.GetPropertyValue` com cache de `TRttiProperty` por segmento.
- **Custom Attribute Scanning** — `GetAttributes<T>` e `HasAttribute<T>` com varredura em campos, propriedades e métodos. Usado por DI, Validation, JSON e ORM.
- **Property Handlers** — `TPropertyHandler` para acesso otimizado a propriedades com cache de getter/setter.

### 1.2 Dependency Injection (`Dext.DI.Core`, `Dext.DI.Interfaces`, `Dext.DI.Attributes`)
- **TDextServices** — Fachada fluente para registro de serviços. Métodos: `AddSingleton<T>`, `AddTransient<T>`, `AddScoped<T>`, `AddSingletonInstance<T>`, `AddSingletonFactory<T>`.
- **Mapeamento Interface/Implementação** — Desacoplamento total entre definições e lógica concreta.
- **TServiceCollection** — Repositório interno de `TServiceDescriptor` com busca reversa (LIFO) para permitir override de registros.
- **TDextServiceProvider** — Container IoC com armazenamento híbrido: `FSingletonInstances` (ARC/Interfaces) + `FSingletonObjects` (Non-ARC/Classes manuais) + `FScopedInstances`/`FScopedObjects` para escopo.
- **Ciclos de Vida** — `Singleton` (instância única global), `Transient` (nova instância por resolução), `Scoped` (instância única por escopo DI via `CreateScope`).
- **Scope Isolation** — `IServiceScope` com `TDextServiceScope` que cria um provider filho isolado. Destruição do scope libera todos os objetos scoped.
- **Auto-Collections** — Resolução automática de `IList<T>`, `IEnumerable<T>`, `IDictionary<K,V>` via `TActivator.IsListType`/`IsDictionaryType`.
- **Atributos DI** — `[Inject]` para injeção em propriedades/campos, `[ServiceConstructor]` para seleção explícita de construtor, overriding a estratégia Greedy.

### 1.3 Object Activator (`Dext.Core.Activator`)
- **TActivator** — Motor central de instanciação dinâmica via RTTI com 4 overloads de `CreateInstance`:
  1. **Manual** — Argumentos posicionais explícitos.
  2. **Pure DI (Greedy Strategy)** — Seleciona o construtor com MAIS parâmetros resolvíveis pelo container. Prioriza construtores da classe mais derivada em caso de empate.
  3. **Hybrid** — Argumentos posicionais iniciais + resolução DI para os restantes.
  4. **PTypeInfo-based** — Instanciação por `PTypeInfo` (suporta classes e interfaces, incluindo auto-instanciação de coleções).
- **[ServiceConstructor] Attribute** — First-pass: se encontrado, o construtor anotado tem prioridade absoluta sobre a estratégia Greedy.
- **Constructor Cache** — Cache thread-safe (`TMREWSync`) de `TConstructorEntry` (método + array de `PTypeInfo` dos parâmetros) para evitar re-scanning RTTI.
- **Field/Property Injection** — `InjectFields` processa `[Inject]` em campos e propriedades após a construção, suportando `TargetTypeInfo` customizado.
- **Default Implementation Registry** — `RegisterDefault(TBase, TImpl)` e `RegisterDefault<TService, TImpl>` para mapeamento base→implementação (ex: `TStrings→TStringList`).

### 1.4 JSON Engine (`Dext.Json`, `Dext.Json.Types`)
- **TDextJson** — Fachada estática de serialização/deserialização com `Serialize<T>` e `Deserialize<T>`.
- **Driver Architecture** — `IDextJsonProvider` plugável (`DextJsonDataObjects` padrão, `System.JSON` alternativo). Drivers implementam `CreateObject`, `CreateArray`, `Parse`.
- **TJsonSettings (Fluent Record API)** — Configuração imutável via chaining: `.CamelCase`, `.SnakeCase`, `.PascalCase`, `.EnumAsString`, `.EnumAsNumber`, `.IgnoreNullValues`, `.CaseInsensitive`, `.ISODateFormat`, `.UnixTimestamp`, `.CustomDateFormat(fmt)`, `.ServiceProvider(p)`.
- **Automatic Casing** (`TCaseStyle`) — 5 modos: `CaseInherit`, `Unchanged`, `CamelCase`, `PascalCase`, `SnakeCase`. Aplicado automaticamente durante serialização.
- **Enum Serialization** (`TEnumStyle`) — `AsNumber` (ordinal) ou `AsString` (nome RTTI do enum).
- **Date Formats** (`TDateFormat`) — `ISO8601`, `UnixTimestamp`, `CustomFormat`. Default: `yyyy-mm-dd"T"hh:nn:ss.zzz`.
- **DOM Abstraction** — `IDextJsonNode`, `IDextJsonObject`, `IDextJsonArray` com tipagem forte (6 node types: Null, String, Number, Boolean, Object, Array).
- **TJsonBuilder** — Builder fluente para construção programática de JSON sem strings.
- **Atributos** — `[JsonName]` (renomear campo), `[JsonIgnore]` (excluir campo), `[JsonCaseStyle]` (override por classe).
- **Perfis Arquiteturais**:
  - **Dext DOM (IDextJsonNode)** — Otimizado para 99% dos casos (APIs REST, Configurações). Alta velocidade de acesso aleatório e manipulação de objetos via árvore em memória (engine DataObjects).
  - **Dext UTF-8 (Low-Level Streaming)** — Ferramenta cirúrgica para Big Data. Processamento sequencial zero-allocation de volumes massivos (GBs) com footprint de memória constante.
- **TUtf8JsonSerializer** (`Dext.Json.Utf8.Serializer`) — Serializador zero-allocation para records. Opera diretamente sobre `TByteSpan` (UTF-8 raw) sem conversão intermediária para `string`. Cache de `TJsonRecordInfo` por `PTypeInfo` para eliminar overhead RTTI em hot-paths. `ToUtf8JSON` no driver `DextJsonDataObjects` para output UTF-8 nativo.
- **S54 Codecs Diretos** — `Dext.Core.TypeModel`, `Dext.Core.DirectAccess`, `Dext.Codecs.Registry`, `Dext.Serialization.Protobuf`, `TDextJson`, hidratação ORM e a CLI de codecs compartilham planos de campos, habilitando leitura/escrita direta por offset, registro de codecs protobuf gerados, despacho gRPC por invoker estático, objetos/listas aninhados com ownership explícito, edge cases de SmartProp/Nullable, `TGUID`/`TUUID` e exportação `.proto` a partir de DTOs code-first. Os diagnósticos do IDE Expert ficam documentados como DX adiado.

### 1.5 Configuration System (`Dext.Configuration.*`)
- **TDextConfiguration (Fluent Builder)** — `.AddJsonFile(path)`, `.AddYamlFile(path)`, `.AddEnvironmentVariables(prefix)`, `.AddCommandLine(args, mappings)`, `.AddUserSecrets(secretsId)`, `.AddInMemoryCollection`.
- **TConfigurationRoot** — Agregador multi-provider com precedência LIFO (último provider registrado vence). Implementa `IConfiguration`.
- **Pipeline Padrão de 5 Camadas de Precedência** — (1) Arquivos Base JSON/YAML $\rightarrow$ (2) Arquivos de Ambiente JSON/YAML $\rightarrow$ (3) User Secrets (Apenas em Development) $\rightarrow$ (4) Variáveis de Ambiente do S.O. $\rightarrow$ (5) Argumentos de Linha de Comando (CLI).
- **CommandLine Configuration Provider** (`Dext.Configuration.CommandLine`) — Parsing de argumentos de alta performance suportando `--Key=Value`, `/Key=Value`, valores separados por espaço `--Key Value`, conversão de duplo sublinhado (`--Key__SubKey=Value` $\rightarrow$ `Key:SubKey`), flags booleanas e mapeamento customizado de switches/aliases (`-p` $\rightarrow$ `Server:Port`).
- **User Secrets Configuration Provider** (`Dext.Configuration.UserSecrets`) — Armazenamento e isolamento de credenciais de desenvolvimento fora do repositório git (`%APPDATA%\Dext\UserSecrets\<Id>\secrets.json` no Windows, `~/.dext/usersecrets/<Id>/secrets.json` no Linux/macOS).
- **Hierarchical Keys** — Acesso via `:` separator (ex: `Database:ConnectionString`). `GetSection(key)` retorna sub-árvore.
- **Options Pattern** — `IOptions<T>` para binding tipado de seções de configuração em classes; callback de validação opcional em `Configure<T>`; **ValidateOnStart** (S68) resolve e valida eagerly em `TWebApplication.BuildServices` antes de abrir a porta (`EConfigurationException`).
- **Section Validators** — `AddSectionValidator(section, validator)` para validação de configuração no startup.
- **Change Tracking** — `IChangeToken` com `OnReload` callback para hot-reload de configuração.

### 1.6 Type System (`Dext.Types.*`)
- **TUUID** (`Dext.Types.UUID`) — Tipo RFC 9562 com armazenamento Big-Endian (Network Byte Order). `NewV4` (random), `NewV7` (time-ordered, 48-bit Unix timestamp ms + random). Conversão implícita bidirecional com `TGUID` (endianness swap automático) e `string`. Operadores `=` e `<>` via `CompareMem`. Compatível com PostgreSQL `uuid` e Web APIs.
- **Nullable\<T\>** (`Dext.Types.Nullable`) — Wrapper genérico para value types anuláveis. `HasValue`, `Value`, `GetValueOrDefault`, `Clear`. Operadores implícitos: `T→Nullable<T>`, `Nullable<T>→T`, `Variant→Nullable<T>`, `Nullable<T>→Variant`. Comparação via `TEqualityComparer<T>.Default`. `TNullableHelper` para acesso low-level via raw `PTypeInfo` sem genéricos.
- **Lazy\<T\>** (`Dext.Types.Lazy`) — Inicialização lazy thread-safe via `TCriticalSection` (double-checked locking). `ILazy` e `ILazy<T>` interfaces. `TLazy<T>` (factory-based) e `TValueLazy<T>` (pre-computed). Operadores implícitos: `T→Lazy<T>`, `Lazy<T>→T`, `TFunc<T>→Lazy<T>`. Ownership management: `AOwnsValue` parameter controla se o valor é destruído com o lazy.

### 1.7 Smart Types & Expression Trees (`Dext.Core.SmartTypes`, `Dext.Specifications.*`)
- **TEntityType\<T\>** (`Dext.Entity.TypeSystem`) — Classes de definição separadas para queries. Permite separar dados de metadados trabalhando com POCOs puros, gerando as mesmas árvores de expressão sem precisar embutir `Prop<T>` na própria entidade. Ideal para sistemas legados ou quando a separação estrita é preferida.
- **Prop\<T\>** (`Dext.Core.SmartTypes`) — Record genérico que opera em **modo dual**: (1) **Runtime Mode** — armazena valor `T` normalmente, (2) **Query Mode** — gera árvores de expressão (`IExpression` / AST) automaticamente via operator overloading. É o pilar central da **DSL fluente LINQ-like** do Dext.
- **BooleanExpression** — Record híbrido que pode conter um `Boolean` literal OU um nó `IExpression` (AST). Operadores `and`, `or`, `not`, `xor` geram nós `TLogicalExpression` automaticamente em query mode.
- **Type Aliases** — `StringType`, `IntType`, `Int64Type`, `BoolType`, `FloatType`, `CurrencyType`, `DateTimeType`, `DateType`, `TimeType` — aliases semânticos para `Prop<T>` que tornam as entidades autodocumentadas.
- **Operator Overloading Completo** — `=`, `<>`, `>`, `>=`, `<`, `<=`, `+`, `-`, `*`, `/`, negação unária — todos geram `TBinaryExpression` com `boEqual`, `boGreaterThan`, etc., em query mode.
- **String Methods** — `Like`, `StartsWith`, `EndsWith`, `Contains` geram `TFunctionExpression` com a operação correspondente.
- **Collection Methods** — `In(values)`, `NotIn(values)`, `Between(lower, upper)`, `IsNull`, `IsNotNull`.
- **OrderBy** — `Prop.Asc` / `Prop.Desc` retornam `IOrderBy` para composição de ordenação.
- **IPropInfo** — Metadata portado que carrega o nome da coluna física no banco, injetado por `TPrototype`.
- **TQueryPredicate\<T\>** — Delegate `function(Arg: T): BooleanExpression` usado pelo ORM como predicado de query.
- **Expression Tree Nodes** (`Dext.Specifications.Types`) — `TPropertyExpression`, `TLiteralExpression`, `TConstantExpression`, `TBinaryExpression`, `TLogicalExpression`, `TUnaryExpression`, `TFunctionExpression`, `TFluentExpression`.
- **Nullable\<T\> Interop** — Conversão implícita bidirecional entre `Prop<T>` e `Nullable<T>`.
- **Variant Interop** — Conversão implícita bidirecional entre `Prop<T>` e `Variant`.

### 1.8 Value Converter Engine (`Dext.Core.ValueConverters`)
- **TValueConverterRegistry** — Registro global de conversores com lookup em 3 níveis: (1) Exact Match por `PTypeInfo` pair, (2) Kind Match por `TTypeKind` pair, (3) Fallback para `tkVariant` source.
- **TValueConverter** — Motor de execução que orquestra conversões, com tratamento automático de Smart Types (`Prop<T>`) e `Nullable<T>` (detecta via `TReflection.GetMetadata`).
- **20+ Conversores Built-in** — `Variant→Integer/String/Boolean/Float/DateTime/Date/Time/Enum/GUID/Class/TBytes/TUUID`, `Integer→Enum/String`, `String→GUID/TBytes/TUUID/Integer/Float/DateTime/Boolean`, `Float→String`, `Boolean→String`, `Class→Class`.
- **Suporte Nativo a TBcd & ftFMTBcd** — Conversores bidirecionais de alta performance e zero-alloc: `TBcd` <-> `Currency`, `TBcd` <-> `Double`, `TBcd` <-> `string` (invariante), `TBcd` <-> `Integer/Int64`, `Variant` <-> `TBcd`, `String` <-> `TBcd`, `Float` <-> `TBcd`, `Currency` <-> `TBcd`. Garante preservação total de precisão ponta-a-ponta para colunas numéricas de alta precisão (`NUMERIC`/`DECIMAL`).
- **ConvertAndSet / ConvertAndSetField** — Conversão + atribuição via RTTI em uma única chamada (usado pelo ORM e Model Binding).

### 1.9 Memory & Span (`Dext.Core.Span`, `Dext.Core.Memory`)
- **TSpan\<T\>** — Referência zero-allocation a região contígua de memória. `Slice`, `ToArray`, `Clear`, `GetEnumerator` (for-in). Bounds checking em todos os acessos.
- **TVector\<T\>** — Vetores dinâmicos e eficientes alocados na stack/heap para alta performance.
- **TReadOnlySpan\<T\>** — Versão imutável de `TSpan<T>`. Operador implícito `TSpan<T>→TReadOnlySpan<T>` e `TArray<T>→TReadOnlySpan<T>`.
- **TByteSpan** — Span especializado para bytes. `Equals` via `TDextSimd.EqualsBytes` (SIMD-accelerated). `EqualsString` compara com UTF-8 sem alocação. `IndexOf`, `ToString` (UTF-8→string), `ToBytes`. Otimizado para parsers JSON/REST e protocolos de rede.
- **ILifetime\<T\>** (`Dext.Core.Memory`) — Wrapper ARC para gerenciamento de lifecycle de objetos Non-ARC. `TLifetime<T>` encapsula objeto e o libera automaticamente quando a interface sai de escopo.
- **IDeferred / TDeferredAction** (`Dext.Core.Memory`) — Padrão Defer (inspirado em Go). Ação executada automaticamente no destructor quando a interface sai de escopo. Útil para cleanup de recursos temporários.

### 1.10 Threading & Async (`Dext.Threading.*`)
- **TAsyncTask** — Implementação fluente de Async/Await para operações assíncronas.
- **Escalonador Work-Stealing** — Distribuição eficiente de tarefas entre os núcleos da CPU para máxima performance paralela.
- **ICancellationToken** — Cancelamento cooperativo com `WaitForCancellation(timeout)` e `IsCancellationRequested`. Integrado com Event Bus Lifecycle e Background Services.
- **Windows Processor Groups** — Suporte nativo para máquinas Windows com >64 cores lógicos. Detecta automaticamente múltiplos grupos de processadores e vincula threads de worker usando `SetThreadGroupAffinity` para otimização e balanceamento.
- **GetSystemLogicalProcessorCount** — Helper que consulta a topologia do processador em nível de sistema de todos os grupos no Windows (com fallback para o padrão `CPUCount` nas outras plataformas) para evitar sub-provisionamento de threads de servidor.
- **Round-Robin Group Affinity** — Alocador automático que distribui uniformemente threads de trabalho (workers) entre os nós NUMA e grupos de processadores disponíveis.

### 1.11 Generic Object Pooling (`Dext.Collections.Pool`)
- **TDextPool\<T\>** — Pool genérico de objetos thread-safe com `TSpinLock`, `ManualReset` event broadcast, rastreamento atômico de waiters e deadline monotônica de timeout (`AcquireTimeoutMs`).
- **Reciclagem Automática (`IPoolable`)** — Execução automática do método `ResetState` durante o `Release` do objeto antes de seu retorno ao estoque.
- **Protocolo Drain-Before-Free** — Shutdown atômico com broadcast (`FAvailableEvent.SetEvent`) e espera por *drain* de waiters (`FActiveWaiters = 0`) prevenindo *use-after-free*.
- **MapFast HTTP Fallback 503** — Retorno automático de `HTTP 503 Service Unavailable` em endpoints `App.MapFast<TDbContext>` sob exaustão do pool de contextos.

### 1.12 Logging Pipeline (`Dext.Logging`, `Dext.Logging.Sinks.APM`)
- **ILoggerFactory** — Factory de loggers com registro de múltiplos providers. `CreateLogger(categoryName)` retorna `ILogger` composto.
- **ILogger** — Interface com métodos por nível: `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`. Suporte a structured templates com placeholders.
- **Aggregate Logger** — Cada `ILogger` criado pela factory agrega todos os providers registrados, despachando cada log entry para todos simultaneamente.
- **TBatchingTelemetrySink** — Sink base abstrato e assíncrono para envio em lotes (batching) com buffering em fila, sincronização thread-safe e execução em background.
- **TSeqLogSink** — Sink de logs estruturados utilizando o formato Compact Log Event Format (CLEF) para envio de lotes a servidores Seq via HTTP.
- **TOTLPTelemetrySink** — Sink de telemetria no padrão OpenTelemetry (OTLP/HTTP JSON) para exportar Logs a coletores OTel (SigNoz, Datadog).
- **TTelemetrySinkRegistry** — Registro plugável de criadores de sinks que desacopla dependências circulares entre as camadas de pacotes.
- **Fluent Logging Builders** — Extensões de inicialização que suportam `AddSeq()` e `AddOpenTelemetry()` com configurações customizadas de batching e serviços.

### 1.13 I/O Writers (`Dext.Core.Writers`)
- **IDextWriter** — Abstração thread-safe para output do framework. Implementações: `TConsoleWriter` (stdout), `TWindowsDebugWriter` (OutputDebugString com buffering), `TStringsWriter` (TStringList/TMemo), `TNullWriter` (silent).
- **SafeWrite / SafeWriteLn** (`Dext.Utils`) — Funções globais que roteiam output via `IDextWriter` ativo. Detecção automática de console disponível. Escrita Unicode nativa via `WriteConsoleW` (Windows) com fallback UTF-8 para pipes.
- **SafeAttachConsole** — Attach ao console do processo pai (CMD/PowerShell) ou `AllocConsole` para aplicações GUI executadas via F5.

### 1.14 Text Escaping (`Dext.Text.Escaping`)
- **TDextEscaping** — Utilitários centralizados para escaping de texto: `Html`, `Xml`, `Json` (manual character-by-character com suporte a `\uXXXX`), `Url`. Usado por Reporters, Serializers e RestClient.

### 1.15 Date Utilities (`Dext.Core.DateUtils`)
- **TryParseISODateTime** — Parser robusto de ISO 8601 (`YYYY-MM-DDTHH:NN:SS.ZZZ`) com suporte a variações (separador `T` ou espaço, milissegundos opcionais).
- **TryParseCommonDate** — Parser multi-formato: ISO 8601 → `dd/mm/yyyy` → `mm/dd/yyyy` → `yyyy/mm/dd` com detecção automática de formato.

### 1.16 Resilience Pipeline (`Dext.Resilience`)
- **IResiliencePipeline / TResiliencePipeline** — Wrapper em record fluente e interface expondo políticas estilo Polly. Suporte a execuções assíncronas e síncronas genéricas/não-genéricas (`Execute<T>` e `Execute`).
- **Retry Policy** (`TRetryPolicy`) — Tratamento de falhas transitórias com número de tentativas customizável e estratégias de backoff (linear, exponencial com jitter).
- **Circuit Breaker Policy** (`TCircuitBreakerPolicy`) — Implementa estados `Closed`, `Open` e `Half-Open`, falhando rápido e lançando `ECircuitBrokenException` quando limites de falhas são excedidos.
- **Fallback Policy** (`TFallbackPolicy`) — Intercepta exceções retornando valores alternativos ou executando ações de fallback customizadas.
- **Timeout Policy** (`TTimeoutPolicy`) — Lança `ETimeoutException` caso operações excedam a duração máxima permitida através de cancelamento cooperativo e futures assíncronas.
- **RestClient Integration** — O `TRestClient` integra-se nativamente com o motor de resiliência, permitindo o uso retrocompatível dos métodos `.Retry()` e `.Timeout()`, além de configuração de pipelines customizados.

### 1.17 Persistent Background Jobs (`Dext.BackgroundJobs.*`)
- **`IJobStorage`** — Abstração de armazenamento desacoplada com suporte a múltiplos provedores.
- **`IJobClient` / `TDextJobs`** — Cliente thread-safe para enfileiramento e fachada utilitária estática (`TDextJobs.Enqueue<T>`, `TDextJobs.Schedule<T>`).
- **`TInMemoryJobStorage`** — Provedor de persistência em memória projetado para testes locais rápidos.
- **`TSqliteJobStorage`** — Provedor de persistência baseado no SQLite via FireDAC, com criação automática de tabelas e transações ACID seguras.
- **`TJobServer` / `TBackgroundJobsService`** — Motor de processamento multi-threaded em background executado como um `IHostedService` (`TBackgroundService`), realizando polling, travamento, execução e monitoramento de jobs.
- **`TJobSerializer`** — Serializador e deserializador de argumentos de métodos (`TValue` arrays) via RTTI utilizando o DOM JSON do Dext.

---

## 2. Collections

Coleções de alta performance em `Sources\Core`. Binary Code Folding (`TRawList`) consolida especializações genéricas num único motor de memória bruta (até 60% menos tempo de compilação). Dicionários CPU-friendly (`TRawDictionary`, open addressing) até **6,6×** mais rápidos que a RTL; varreduras SIMD (`Dext.Collections.Simd`, AVX2/SSE2) até **6,8×** em listas nativas.

### 2.1 Core Collections (`Dext.Collections`, `Dext.Collections.Base`, `Dext.Collections.OrderedDict`)
- **TRawList\<T\>** — Backbone de todas as coleções. Lista genérica baseada em array dinâmico com `Move`-based insertion/deletion para minimizar overhead. Suporte a `for-in` via enumerator customizado.
- **TList\<T\>** / **IList\<T\>** — Lista genérica de alto desempenho. Operações: `Add`, `Insert`, `Remove`, `IndexOf`, `Sort`, `BinarySearch`, `Contains`, `ToArray`.
- **TDictionary\<K,V\>** / **IDictionary\<K,V\>** — Hash map genérico com suporte a `TryGetValue`, `AddOrSetValue`, `ContainsKey`, `Keys`, `Values`.
- **TOrderedDictionary\<K,V\>** / **IOrderedDictionary\<K,V\>** — Hash map genérico ordenado por inserção que combina buscas $O(1)$ de chaves com iteração densa na ordem de inserção, indexação posicional (`KeyAt`, `ValueAt`, `PairAt`, `IndexOf`) e gerenciamento de ciclo de vida de objetos via `OwnsValues`. Suportado por `TRawOrderedDict` para evitar inchaço de código (code bloat).
- **THashSet\<T\>** / **IHashSet\<T\>** — Conjunto de valores únicos com operações de teoria dos conjuntos: `UnionWith`, `IntersectWith`, `ExceptWith`.
- **TCollections (Factory)** — Factory estática: `CreateList<T>`, `CreateDictionary<K,V>`, `CreateOrderedDictionary<K,V>`, `CreateHashSet<T>`, `CreateSortedList<T>`, etc.
- **TSmartEnumerator\<T\>** — Enumerador base extensível para iteração customizada em coleções derivadas.

### 2.2 LINQ Extensions (`Dext.Collections.Extensions`)
- **Operações Fluentes** — `Where`, `Select`, `OrderBy`, `OrderByDescending`, `First`, `FirstOrDefault`, `Last`, `Any`, `All`, `Count`, `Sum`, `Min`, `Max`, `Average`, `Distinct`, `Take`, `Skip`, `GroupBy`, `SelectMany`, `Aggregate`, `Contains`, `ToList`, `ToDictionary`, `ForEach`.

### 2.3 Concurrent Collections (`Dext.Collections.Concurrent`)
- **TConcurrentDictionary\<K,V\>** — Dicionário thread-safe com **Lock Striping** via array de `TSpinLock` (múltiplos buckets de lock independentes para reduzir contenção).
- **TConcurrentQueue\<T\>** / **TConcurrentStack\<T\>** — Filas e pilhas thread-safe para cenários producer/consumer.

### 2.4 Frozen Collections (`Dext.Collections.Frozen`)
- **TFrozenDictionary\<K,V\>** / **TFrozenSet\<T\>** — Estruturas imutáveis otimizadas para cenários de leitura intensa (estilo .NET 8 `FrozenDictionary`). Após construção, nenhuma modificação é permitida, permitindo otimizações de layout em memória.

### 2.5 Channels (`Dext.Collections.Channels`)
- **TChannel\<T\>** — Primitiva de comunicação assíncrona estilo Go channels para pipelines Producer/Consumer.
- **Bounded Channel** — Capacidade fixa com back-pressure (writer bloqueia quando cheio).
- **Unbounded Channel** — Capacidade ilimitada (writer nunca bloqueia).
- **ChannelReader / ChannelWriter** — Interfaces segregadas para leitura e escrita.

### 2.6 SIMD & Hardware Acceleration (`Dext.Collections.Simd`)
- **TDextSimd** — Operações vetorizadas com detecção automática de instruction set:
  - `EqualsBytes` — Comparação de arrays de bytes via **AVX2** (32 bytes/ciclo), **SSE2** (16 bytes/ciclo) ou fallback Pascal.
  - `IndexOfByte` — Busca linear acelerada via instruções vetoriais.
  - `FillByte` / `MoveMem` — Preenchimento e cópia de memória otimizados.
- **Runtime Detection** — Detecção via CPUID no startup. Seleção automática do melhor path disponível.

### 2.7 Comparers & Algorithms (`Dext.Collections.Comparers`, `Dext.Collections.Algorithms`)
- **TEqualityComparer\<T\>** / **TComparer\<T\>** — Comparadores genéricos padrão com suporte a tipos primitivos, records e classes.
- **Algoritmos** — `Sort` (IntroSort), `BinarySearch`, `Reverse`, `Shuffle`.

---

## 3. Web Framework

### 3.1 Bootstrapping & Minimal API
- **TWebApplication** — Fachada fluente para inicialização: carrega automaticamente `appsettings.json`, `appsettings.yaml`, Environment Variables, registra serviços e constrói o pipeline em uma única cadeia.
- **Minimal API** — Registro direto de handlers via delegates sem controllers (`app.MapGet`, `app.MapPost`, `app.MapQuery`).
- **FastPath** (`app.MapFast`) — Registro de rotas de altíssimo throughput com desvio (bypass) de DI Scope e ativação de RTTI, reduzindo o tempo por requisição ao mínimo possível.
- **Data API Streaming Direct UTF-8** (`Db.UseSql`) — Execução de SQL nativo com serialização e gravação direta dos dados em UTF-8 no stream do socket (`Res.GetOutputStream`) sem alocação de objetos `TJsonObject` na Heap.
- **Mapeamento HTTP QUERY** — Endpoints de consulta de dados seguros e idempotentes utilizando corpos de requisição estruturados.

### 3.2 Controllers (`Dext.Web.Controllers`, `Dext.Web.ControllerScanner`)
Endpoints em classes no estilo MVC, descobertos via RTTI — o par das Minimal APIs quando o domínio passa de uns poucos lambdas `MapGet`.

- **`[ApiController]` / `[ApiController('/prefixo')]`** — Marca a classe como controller. Prefixo opcional no atributo, ou estilo `.NET` separado com `[Route('/api/users')]`.
- **Atributos de verbo** — `[HttpGet]`, `[HttpPost]`, `[HttpPut]`, `[HttpPatch]`, `[HttpDelete]`, `[HttpHead]`, `[HttpOptions]`, `[HttpQuery]`. Rotas com parâmetro **devem** começar com `/` (ex.: `[HttpGet('/{id}')]`).
- **`AddControllers` + `MapControllers`** — `TControllerScanner` encontra tipos `[ApiController]`, registra no DI e mapeia as actions antes do Swagger.
- **Injeção por construtor** — Serviços resolvidos pelo container (`IUserService`, `ILogger`, `TDbContext`, …).
- **Actions `IResult`** — `Results.Ok`, `Created`, `Accepted`, `NoContent`, `BadRequest`, `NotFound`, `ValidationProblem`, `StatusCode`, `Json<T>`.
- **Não nomeie uma action de `Create`** — Conflita com construtores Delphi (`E2254`). Use `CreateUser`, `CreateOrder`, etc.

### 3.3 Middleware Pipeline
- **Chain of Responsibility** — Middlewares funcionais (delegates anônimos) e baseados em classe com injeção de dependência via construtor.
- **Built-in Middlewares**:
  - **HTTP Logging (`THttpLoggingMiddleware`)** — Registro de requisições e respostas com mascaramento configurável case-insensitive (`RedactHeaders`) de cabeçalhos sensíveis (`Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`).
  - **Exception Handling (`TExceptionHandlerMiddleware`)** — Tratamento global de exceções formatado conforme **RFC 9457** (Problem Details, substituindo RFC 7807), geração de `TraceId` via UUIDv7 para rastreabilidade e omissão automática de `E.Message` em produção em erros status `500`. Violações de regra de domínio via **`EDomainException` / `EDomainValidationException`** mapeiam para **HTTP 422** com `type` `https://dext.dev/errors/domain-validation` (S68).
  - **DeveloperExceptionPage (`TDeveloperExceptionPageMiddleware`)** — Exibição detalhada de erros e stack trace exclusiva para ambiente de desenvolvimento.
  - **CORS (`TCorsMiddleware`)** — Suporte estrito a preflight CORS (`OPTIONS` com `Origin` e `Access-Control-Request-Method`), validação rigorosa de Origens, Métodos e Cabeçalhos solicitados com rejeição status `403 Forbidden`, fail-fast no startup contra `AllowAnyOrigin + AllowCredentials` e mesclagem limpa de `Vary: Origin`.
  - **Rate Limiting (`TRateLimitMiddleware`)** — Controle de tráfego com cabeçalhos padronizados da **RFC 9333** (`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, `Retry-After`) emitidos em requisições permitidas e rejeitadas (status `429`).
  - **Response Caching (`TResponseCacheMiddleware`)** — Cache de respostas HTTP server-side com proteção estrita contra armazenamento de conteúdos autenticados (`Authorization`, cookies de sessão/auth), rejeição de respostas com `Set-Cookie` ou diretivas `private`/`no-store`/`no-cache` e reconstrução automática de `Cache-Control: public, max-age=N` em cache HITs.
  - **Compression (`TCompressionMiddleware`)** — Compactação de respostas via GZip.
  - **Security Headers (`TSecurityHeadersMiddleware`)** — Injeção de HSTS, `X-Content-Type-Options`, `X-Frame-Options` e `X-XSS-Protection`.
  - **Feature Flags (`Dext.FeatureFlags`)** — Gerenciamento dinâmico de chaves operacionais e rollouts graduais (`IFeatureManager`) com suporte a filtros estáticos booleans, percentuais de rollout (`TPercentageFilter`), janelas de tempo (`TTimeWindowFilter`), atributos declarativos (`[FeatureGate]`) e integração nativa com a infraestrutura de configuração do Dext (`IConfiguration`).
  - **Reload de Feature Flags (S68)** — `IFeatureManager` lê `FeatureManagement:*` ao vivo; o host habilita JSON/YAML com **ReloadOnChange**; `TFeatureConfiguration.Reload` força `IConfigurationRoot.Reload`.
  - **Forwarded Headers (`Dext.Web.ForwardedHeaders`)** — Validação segura de proxies reversos (`X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host`) lidos da direita para a esquerda com controle de `KnownProxies`, subredes CIDR e limite de encaminhamento contra IP Spoofing.
  - **Antiforgery CSRF Protection (`Dext.Web.Antiforgery`)** — Proteção contra ataques Cross-Site Request Forgery via padrão Double Submit Cookie, validação de tokens em tempo constante contra timing attacks e suporte nativo a formulários SSR (`WebStencils`) e cabeçalhos HTMX (`X-XSRF-TOKEN`).
  - **Base Path Hosting (`UsePathBase`)** — Suporte a hospedagem sob prefixo de caminho (`app.UsePathBase('/myapp')`), remoção automática do prefixo no pipeline (`TDextPathBaseMiddleware`), preenchimento de `Request.PathBase` e gerador de URL `Request.ToAppUrl('/route')`. Registro nativo de prefixos no kernel do HTTP.sys (`http://+:8080/myapp/`).

### 3.4 Routing Engine
- **Parâmetros Dinâmicos** — Rotas com `{id}`, `{slug}`, restrições de tipo.
- **API Versioning** — `THeaderApiVersionReader`, `TQueryStringApiVersionReader`, `TPathApiVersionReader`, `TCompositeApiVersionReader` (composição de múltiplas estratégias).
- **Descoberta HTTP QUERY** — Roteamento automático de requisições OPTIONS gerando os cabeçalhos padrão `Allow` e `Accept-Query` contendo os tipos de mídia configurados para a consulta (ex: `application/jsonpath`).
- **Roteamento por Árvore Radix (Trie)** — Busca linear de rotas substituída por uma estrutura em árvore otimizada com `TRouteNode`, alcançando complexidade de correspondência de caminhos de $O(L)$ (onde $L$ é a profundidade de segmentos) e resolução determinística.
- **Backtracking de Segmentos** — Suporte completo a segmentos fixos (literais), parâmetros de rota (`{param}`) e parâmetros curinga com backtracking segmento a segmento para resolução de sobreposições.
- **Mapeamento de Metadados de Requisição Zero-Allocation** — Evita o encapsulamento dinâmico pesado com RTTI (eliminando alocações de dicionários e `TValue` no heap) ao expor e atribuir `EndpointMetadata` diretamente nas propriedades de `IHttpContext` das rotas correspondidas.

### 3.5 Model Binding
- **Hybrid Binding** — Atributos `[FromBody]`, `[FromQuery]`, `[FromRoute]`, `[FromHeader]`, `[FromServices]`.
- **Zero-Allocation** — Deserialização UTF-8 direta para records e classes via `TByteSpan`.
- **Multipart/Form-Data** — Processamento de uploads via abstração `IFormFile`.
- **Object Lifecycle Management** — Tracking de objetos criados por Model Binding com integração ao **ChangeTracker** do ORM para transferência automática de ownership.
- **Binding Problem Details (S68)** — Falhas de conversão retornam **HTTP 400** com `application/problem+json` (`Results.BindingProblem` / RFC 9457: `type`, `title`, `status`, `detail`, `instance`).
- **Auto-Validation Problem Details (S68)** — Validação automática (atributos/fluente) no `THandlerInvoker` emite `Results.ValidationProblem` (`application/problem+json` com mapa `errors`).
- **Results.Accepted (S68)** — Factory semântica **HTTP 202** com cabeçalho `Location` opcional (mesmo padrão de `Created`).
- **Results.UnsupportedMediaType (S68 P2-05 parcial)** — Factory semântica **HTTP 415** para rejeição de mídia no código da aplicação (ex.: extensão de upload).
- **Content Negotiation** — `IOutputFormatter` / `IOutputFormatterSelector` / `AddContentNegotiation`. Respeita `Accept` (formatter JSON embutido; formatters plugáveis para outros media types).

### 3.6 Hosting & Native Server
- **IWebHost / IWebHostBuilder** — Abstrações de hospedagem. Suporte a **Portas Dinâmicas (Porta 0)** com atribuição automática pelo SO.
- **Server Adapters** — Indy (padrão, OpenSSL/Taurus SSL), **WebBroker Adapter** (ISAPI/CGI para IIS/Apache), **DCS Adapter** (Delphi-Cross-Socket, non-blocking) e **Native Server Engine** (kernel-mode `http.sys` no Windows e sockets `epoll` não-bloqueantes no Linux).
- **Parser HTTP Zero-Allocation** (`TDextIocpHttpParser`) — Parsing incremental dos cabeçalhos da requisição HTTP/1.1 diretamente dos buffers de rede sem alocações intermediárias na heap.
- **IHostedService** — Tarefas de background com `StartAsync`/`StopAsync`. `TBackgroundService` com `Execute(ICancellationToken)`.
- **IHostApplicationLifetime** — Tokens para `ApplicationStarted`, `ApplicationStopping`, `ApplicationStopped`.
- **`ServerEngineOptions`** (`Dext.Server.Engine.Types.pas`) — Função de entrada global e helpers fluentes (`WithHttps`, `WithSslCertHash`, `WithIoThreads`, `WithReceiveBufferSize`) para configuração elegante de servidores HTTPS sem burocracia.
- **`TRestClient.IgnoreCertificateErrors / AllowSelfSigned`** (`Dext.Net.RestClient.pas`) — Interface fluente para controle explícito de validação de certificados SSL/TLS em clientes REST, permitindo conexões HTTPS com certificados auto-assinados de ambiente de desenvolvimento.

#### Motor Epoll no Linux (S50)
- **Afinidade de Núcleo (CPU Pinning)**: Vinculação automática de threads de rede (`TDextEpollWorker`) a núcleos de CPU dedicados via `pthread_setaffinity_np` para reduzir trocas de contexto e degradação de cache.
- **Otimizações de Pré-Aceitação**: Uso de `TCP_DEFER_ACCEPT` no socket servidor para evitar desperdício de wake-ups e `TCP_FASTOPEN` (TFO) para suportar envio de dados no handshake SYN.
- **Transmissão Zero-Copy via sendfile**: Transmissão direta de arquivos em sockets não-bloqueantes usando a chamada de sistema do kernel `sendfile`, eliminando buffers e cópias em espaço do usuário.
- **Pool de Contexto Zero-Allocation**: Reutilização de descritores de conexões (`TDextEpollContext`) por meio de pools locais de cada thread de trabalho, evitando fragmentação do heap sob alta concorrência.
- **Varredura Ativa de Keep-Alive**: Monitoramento ativo de inatividade de descritores fechando conexões ociosas (>15s) e configuração refinada de keep-alive a nível de kernel com opção de fechamento limpo via `SO_LINGER`.

### 3.7 Segurança, Identidade & Autorização (S06)
- **IClaimsPrincipal** — Autenticação JWT, Basic Auth (RFC 7617) e Cookies.
- **Rate Limiting** — Fixed Window, Sliding Window, Token Bucket, Concurrency Limiter.
O Dext possui um motor nativo de segurança e identidade baseado nos padrões de mercado (JWT, OAuth2 e OpenID Connect), garantindo conformidade empresarial com alta performance.

### 3.7.1 Engine Criptográfica e Validação JWT (`Dext.Auth.JWT`)
- **TJwtTokenHandler** — Gerenciador completo de JSON Web Tokens (JWT) com suporte nativo à assinatura HS256 e validação assimétrica RS256.
- **Integração com Windows CNG** — Validação e assinatura de alto desempenho utilizando as APIs de criptografia nativas do Windows (`bcrypt.dll`) de forma dinâmica, com fallback transparente para `System.Hash` (Delphi XE8+) ou Indy/OpenSSL para máxima compatibilidade.
- **Parsing Otimizado** — Análise estruturada de tokens JWT usando indexadores de string (`IndexOf`) e spans de memória, eliminando alocações desnecessárias no heap.
- **Tratamento de Claims** — Estrutura de Claims flexível (`TClaim`) e builder fluente de identidades (`TClaimsBuilder`).

### 3.7.2 Middleware de Autenticação JWT (`Dext.Auth.Middleware`)
- **TJwtAuthenticationMiddleware** — Middleware de pipeline HTTP que extrai o token do cabeçalho `Authorization: Bearer`, valida sua assinatura, tempo de expiração (`exp`), emissor (`iss`) e audiência (`aud`), e injeta o principal (`IClaimsPrincipal`) no contexto da requisição (`IHttpContext.User`).

### 3.7.3 Autorização Declarativa e Baseada em Políticas (`Dext.Auth.Attributes`, `Dext.Auth.Identity`)
- **Atributos de Autorização** — `[Authorize]`, `[AuthorizePolicy]` e `[AllowAnonymous]` para proteção declarativa de controllers e actions (`[Authorize('Admin')]` para roles/schemes; `[AuthorizePolicy('Nome')]` para políticas nomeadas — Delphi não tem named arguments em atributos).
- **Validação de Roles** — Controle de acesso baseado em roles diretamente no fluxo de execução do dispatcher de rotas.
- **Motor de Políticas** — Registro e avaliação de políticas customizadas em runtime através do `TAuthorizationPolicyRegistry` (ex: política de idade mínima ou escopos de acesso).

### 3.7.4 Provedores de Identidade Externos (OIDC)
- **Métodos Plug-and-Play** — Extensões para configuração expressa de provedores externos via OIDC: `UseGoogleAuthentication`, `UseEntraIdAuthentication` (Azure AD) e `UseKeycloakAuthentication`.

### 3.8 Tempo real, cache e health
- **SSE (Server-Sent Events)** — Streaming unidirecional de eventos como fallback.
- **WebSockets e Hubs SignalR** — Motor nativo autônomo de WebSockets (RFC 6455) e Dext Hubs:
  - **Protocol Engine (`Dext.WebSocket.Protocol.pas`)**: Processamento de framing RFC 6455 (`wsText`, `wsBinary`, `wsPing`, `wsPong`, `wsClose`), mascaramento/desmascaramento vetorizado, payload 64-bit e integridade.
  - **Handshake Engine (`Dext.WebSocket.Handshake.pas`)**: Validação de upgrade HTTP `101 Switching Protocols`, cálculo SHA-1/Base64 de `Sec-WebSocket-Accept`.
  - **Permessage-Deflate (`Dext.WebSocket.Compression.pas`)**: Negociação e compressão **RFC 7692** via ZLib nativo (até 80% de redução no payload).
  - **Hubs Transport (`Dext.Web.Hubs.Transport.WebSocket.pas`)**: Integração completa com `Dext.Web.Hubs` para mensageria bidirecional em tempo real, dispatching de grupos (`IHubClients`), reconexão automática e heartbeats ping/pong.
  - **Cross-Platform I/O**: Executa sobre raw sockets com `epoll` no Linux e `WSAPoll` / `IOCP` no Windows.
- **Cliente Hub Delphi (SignalR-compatible)** — Biblioteca cliente nativa em Delphi (`Dext.Web.Hubs.Client`) de alta performance, com suporte a transportes WebSocket e SSE, protocolos de negociação/handshake automáticos, heartbeat via ping e dispatches thread-safe com marshaling opcional para a thread principal (UI).
- **Caching** — Motor de cache em memória e provedor de cache Redis nativo (`TRedisCacheStore`). Gera chaves de cache exclusivas para requisições HTTP QUERY calculando um hash `THashSHA1` do stream de corpo da requisição. Suporte para registro de cache de resposta no pipeline via `.UseRedisCache` no `TAppBuilder`. **Health Checks** com probes `/health`, `/health/live` (liveness) e `/health/ready` (readiness) via `THealthCheckMiddleware` / `THealthCheckOptions` (S68).

### 3.9 API Documentation & Scaffolding
- **OpenAPI / Swagger** — Geração automática de especificação.
- **Auto-Migrations (S11)** — Sincronização automática de schema durante startup com detecção de renomeação de tabelas/colunas via atributos.
- **View Engine & WebStencils (S09)** — Motor de templates baseado em AST (estilo Razor), zero-dependência.

### 3.10 Database as API (`Dext.Web.DataApi`)
Uma das features mais poderosas do Dext: **geração automática de APIs REST completas a partir de entidades ORM — com uma única linha de código**. Não é um scaffold que gera código — é um runtime handler que mapeia entities para endpoints dinamicamente.

#### Registro (3 modos coexistentes)
- **Automático por Atributo** — `[DataApi]` na entidade + `App.MapDataApis` no startup. `TDataApi.MapAll` escaneia RTTI e registra todas as entidades decoradas automaticamente.
- **Manual tipado** — `TDataApiHandler<TProduct>.Map(App, '/api/products')`.
- **Manual Fluente** — `App.Builder.MapDataApi<T>(path, DataApiOptions.AllowRead.RequireAuth)`.

#### 5 Endpoints CRUD Gerados
| Método | Rota | Handler |
|---|---|---|
| `GET` | `/api/{entity}` | `HandleGetList` — Lista com paginação, ordenação e filtros |
| `GET` | `/api/{entity}/{id}` | `HandleGet` — Busca por PK (simples ou composta) |
| `POST` | `/api/{entity}` | `HandlePost` — Cria novo registro, retorna 201 |
| `PUT` | `/api/{entity}/{id}` | `HandlePut` — Atualiza registro existente |
| `DELETE` | `/api/{entity}/{id}` | `HandleDelete` — Remove registro |

#### Dynamic Specification Mapping (Filtros via QueryString)
- **11 operadores** parseados automaticamente da URL: `_eq`, `_neq`, `_gt`, `_gte`, `_lt`, `_lte`, `_cont` (LIKE %x%), `_sw` (LIKE x%), `_ew` (LIKE %x), `_in` (IN), `_null` (IS NULL).
- **Paginação** — `?_limit=20&_offset=40` com teto **MaxPageSize** (default 100; fluente `.MaxPageSize(N)`, `0` desativa) — S68.
- **Ordenação** — `?_orderby=price desc,name asc`.
- **Resolução de nomes** — `ResolvePropertyName` via `TReflection.GetMetadata().GetHandlerBySnakeCase` para converter snake_case da URL para PascalCase da propriedade Delphi.
- Cada filtro gera um `IExpression` via `TStringExpressionParser.Parse` e é injetado no `ISpecification` — a mesma AST usada pelas Smart Properties.

#### TDataApiOptions — API Fluente de Configuração
- **Segurança** — `RequireAuth`, `RequireRole(roles)`, `RequireReadRole(roles)`, `RequireWriteRole(roles)` — Separação de permissões read/write com validação JWT integrada via `IClaimsPrincipal`.
- **Métodos Permitidos** — `Allow([amGet, amGetList])` restringe quais endpoints são gerados.
- **Multi-Tenancy** — `RequireTenant` para isolamento por tenant.
- **Naming Strategy** — `UseSnakeCase`, `UseCamelCase` para controle de casing na serialização.
- **Enum Style** — `EnumsAsStrings`, `EnumsAsNumbers`.
- **DbContext Explícito** — `DbContext<TMyContext>` para selecionar qual contexto usar.
- **SQL Customizado** — `UseSql('SELECT ...')` para queries customizadas.
- **Swagger** — `UseSwagger`, `Tag('Products')`, `Description('...')` para documentação automática.

#### Convenções de Nomenclatura (`TDataApiNaming`)
- **Auto-Discovery** — Prefixo `T` removido automaticamente via `TReflection.NormalizeFieldName`.
- **Pluralização** — Inglês: `y→ies`, `ch/sh/x/s→es`, default `→s` (ex: `TCategory` → `/api/category`).
- **Rotas Customizadas** — `[DataApi('/meu/caminho')]` sobrescreve convenção.
- **Case Mapping** — `PascalCase` na propriedade Delphi → `snake_case` na URL para filtros.

#### Entity ID Resolver (`TEntityIdResolver`)
- **Resolução automática de tipo de PK** — Delega ao `IModelBinder` para conversão transparente: Integer, String, TUUID, TGUID.
- **Composite Keys** — Separador `|` para chaves compostas (ex: `/api/entity/1|ABC`).

#### Integração com o Ecossistema
- **DI Scope** — `GetDbContext` resolve o `TDbContext` do DI container (suporta múltiplos contextos via `ContextClass`).
- **Telemetria** — `TDiagnosticSource.Write('DataApi.ModelBinding.Start/Complete')` emite eventos rastreáveis.
- **Logging** — Todos os handlers emitem logs via `Log.Debug`/`Log.Error` com structured templates.
- **Serialização** — `TDextJson.Deserialize` + `TDextSerializer` com settings configuráveis per-endpoint.
- **Swagger** — Endpoints registrados aparecem automaticamente na documentação OpenAPI.
- **`[DataApiIgnore]`** — Atributo para excluir entidades específicas do scan automático.

### 3.11 SSR, HTMX & View Engines
### 3.11.1 HTMX Integration
- **Auto-Detection** — O pipeline detecta automaticamente headers `HX-Request` vindos do navegador e **suprime o layout global** em endpoints compatíveis.
- **Partial Rendering** — `Results.View<T>('fragment', Query).WithLayout('')` para renderização de fragmentos parciais sem layout.
- **Full-Stack SPA Feel** — Combina SSR server-side com substituições dinâmicas HTMX para apps altamente responsivos sem JavaScript pesado.

### 3.11.2 Flyweight Iterators (Streaming SSR)
- **O(1) Memory** — `TStreamingViewIterator<T>` itera sob demanda durante o `@foreach` do template. 10.000 registros renderizados usando memória equivalente a **um único objeto**.
- **Sem `ToList`** — Passe `Db.Customers.QueryAll` diretamente para `Results.View<T>('customers', Query)` e o framework engata o streaming automaticamente.
- **Smart Properties in Templates** — `@(Prop(item.Name))` para unwrap automático de `Prop<T>` dentro de templates HTML.

### 3.11.3 Web Stencils (Delphi 12.2+)
- **Provider Nativo** — `Services.AddWebStencils(...)` com whitelist de entidades via `TWebStencilsProcessor.Whitelist.Configure`.
- **Agnóstico** — Mesma interface `IViewEngine` para Dext Template Engine e Web Stencils; troque sem alterar código.

### 3.12 HTTP/2 Framing & HPACK (S41)
O framework inclui suporte nativo à especificação **HTTP/2 (RFC 9113)** e ao algoritmo de compressão de cabeçalhos **HPACK (RFC 7541)**, permitindo multiplexação de streams e comunicação de alta eficiência em conexões persistentes, servindo de base para implementações de alto desempenho como gRPC e Delphi Hub Client.

### 3.12.1 Engine de Framing HTTP/2
- **Multiplexação Completa** — Suporte a múltiplos streams lógicos independentes e concorrentes sobre uma única conexão TCP, eliminando o bloqueio de cabeça de fila (Head-of-Line blocking) no nível da aplicação.
- **Tipos de Frames RFC 9113** — Implementação e decodificação rigorosa de frames `HEADERS`, `DATA`, `SETTINGS`, `RST_STREAM`, `PING`, `GOAWAY` e `WINDOW_UPDATE`.
- **Controle de Fluxo por Stream & Conexão** — Gerenciamento dinâmico de janelas de transmissão de dados (`WINDOW_UPDATE`) para evitar saturação de buffer do receptor e otimizar throughput de rede.
- **State Machine de Conexões** — Máquina de estados completa para gerenciar o handshake inicial (`SETTINGS`), controle de encerramento amigável (`GOAWAY`), detecção de conexões ativas (`PING`) e fechamento prematuro de streams (`RST_STREAM`).

### 3.12.2 Compressão de Cabeçalhos HPACK
- **Tabela Estática** — Implementação completa da tabela estática de 61 entradas padrão da especificação RFC 7541 para mapeamento de cabeçalhos comuns.
- **Tabela Dinâmica** — Gerenciamento dinâmico de cabeçalhos adicionais com controle de tamanho máximo de buffer (padrão de 4096 bytes) e desalocação FIFO de entradas antigas conforme novos índices são inseridos.
- **Codificação Huffman** — Codificador e decodificador Huffman baseado em tabelas estáticas de árvores de bits para compressão eficiente de strings de texto enviadas nos nomes e valores dos cabeçalhos.
- **Representações de Campo** — Suporte completo para campos indexados, campos literais indexados (com ou sem atualização de tabela dinâmica) e literais nunca indexados.

### 3.12.3 Integração gRPC Unary Transport
- **Suporte gRPC** — Exemplo prático de transporte gRPC Unary demonstrando o processamento de corpos de mensagem binários no padrão *Length-Prefixed Message* (1 byte de flag de compressão + 4 bytes big-endian de tamanho do corpo + dados protobuf).
- **Tratamento de Headers e Trailers** — Emissão correta de cabeçalhos de resposta gRPC e envio final de trailers HTTP/2 (`grpc-status`, `grpc-message`) em um frame `HEADERS` com flag `END_STREAM`.

---

## 4. ORM & Entity

### 4.1 Core Persistence
- **TDbContext** — Unit of Work with **Change Tracking** automático (estados: Added, Modified, Deleted, Unchanged). **Identity Map** para unicidade de instâncias por chave primária.
- **DbSet\<T\>** — Repository genérico. Operações: `Add`, `Update`, `Remove`, `Find`, `FirstOrDefault`, `Where`, `Include`, `ToList`.
- **SaveChanges** — Persiste todas as mudanças rastreadas em uma transação.
- **Fluent Connection Setup & Pooling Auto-Detection** — Construtores de conexão fluente (`UsePostgreSQL`, `UseFirebird`, etc.) com sincronização e extração automática de parâmetros via setters de propriedade, eliminando bugs de opções vazias ou pooling desconfigurado.
- **Suporte a ConnectionDefName (FireDAC)** — Suporte nativo para definições de conexão registradas no FireDAC (`UseConnectionDef`). Resolve dinamicamente o dialeto, driver ID e status de pooling consultando o `FDManager.ConnectionDefs` global do FireDAC.
- **Suporte a Shadow Properties (Propriedades de Sombra)** — Permite mapear colunas do banco (ex: `TenantId`, `CreatedAt`, `IsDeleted`) que são processadas e persistidas sem precisar declará-las como campos ou propriedades físicas na classe.

### 4.2 Query Engine (LINQ-like)
- Query fluída com **Projeção (Select)** (`Select(array of string)`, projeções tipadas por propriedade), preservação de especificação no servidor, **Paging** (`Skip`/`Take`), **Aggregates** (`Count`, `Sum`, `Max`, `Min`, `Average`).
- **SQL Cache** — Reaproveitamento de comandos SQL gerados para queries repetidas.
- **Joins Fluentes Fortemente Tipados** (`JoinInner`, `JoinLeft`, `JoinRight`, `JoinFull`, `JoinCross`) — Compilam diretamente em joins SQL otimizados no banco de dados (INNER, LEFT, RIGHT, FULL, CROSS) usando expressões de condição explícitas, auto-resolução implícita via metadados de relacionamento (`TModelBuilder`), ou produto cartesiano via Cross Join.
- **Pessimistic Locking** — `FOR UPDATE` para controle de concorrência.
- **Multi-Mapping** (estilo Dapper) — Recursive hydration via atributo `[Nested]`.
- **Integração com Validação Fluente** — Verificação automática de entidades no `SaveChanges` antes da execução das transações físicas no banco de dados.

### 4.3 Specification Pattern (`Dext.Specifications`)
- **Fluent Specification Builder** — `Where`, `OrderBy`, `Include`, `Take`, `Skip` para regras de negócio desacopladas e reutilizáveis.
- **TExpressionEvaluator** (`Dext.Specifications.Evaluator`) — Avaliador **in-memory** da mesma AST usada pelo SQL Compiler. Avalia `IExpression` contra objetos (`TObject`) ou dicionários (`TDictionary<string, Variant>`). Suporta: comparações (`=`, `<>`, `>`, `>=`, `<`, `<=`), `LIKE` (case-insensitive com `%`), `IN`/`NOT IN`, `IS NULL`/`IS NOT NULL`, operações bitwise (`AND`/`OR`/`XOR`), aritmética (`+`, `-`, `*`, `/`, `mod`, `div`), short-circuit em `AND`/`OR`. Faz **unwrap automático de `Prop<T>`** (Smart Types) via RTTI.
- **TStringExpressionParser** (`Dext.Specifications.Parser`) — Parser que converte strings no formato `"Campo Operador Valor"` para nós `IExpression`. Conversão automática de tipos: Boolean, Float (invariant), Integer, String. Usado internamente pelo **Database as API** para transformar filtros da QueryString em expression trees.
- **IExpressionVisitor** — Padrão Visitor para percorrer a árvore de expressão, usado tanto pelo SQL Compiler (gerando SQL) quanto pelo Evaluator (filtrando in-memory).

### 4.4 Relationships & Loading
- **One-to-One**, **One-to-Many**, **Many-to-Many**.
- **Lazy Loading** via Proxy Objects (interceptação transparente).
- **Eager Loading** — `Include`/`ThenInclude` para pré-carregamento de grafos.
- **Split Queries Loading (Carregamento Dividido)** — Resolução otimizada de coleções aninhadas via consultas SQL adicionais isoladas usando cláusulas `IN` com IDs parametrizados, evitando explosão cartesiana de JOINS.

### 4.5 Migrations System
- Evolução Code-First automatizada com snapshots cronológicos do modelo de dados.

### 4.6 Dialect Support (Poliglota)
- PostgreSQL, SQL Server, MySQL, SQLite, Oracle, Firebird, InterBase.
- **Legacy Paging** — Envelopamento automático para `ROWNUM` em Oracle/SQL Server antigos.
- **Driver Oracle (`TOracleDialect`)** — Suporte nativo a Oracle OCI via FireDAC:
  - Definição de colunas identity (`GENERATED BY DEFAULT AS IDENTITY`).
  - Sintaxe nativa `RETURNING "ID" INTO :RET_VAL` para recuperação de PK gerada.
  - Paginação automática com wrapper `ROWNUM` em versões legadas e modernas.
  - Mapeamento preciso: `NUMBER(1,0)` → `Boolean`/`BoolType`, `NUMBER(4,0)` → `SmallInt`/`Int16Type`, `NUMBER(9,0)` → `Integer`/`IntType`, `NUMBER(18,0)` → `Int64`/`Int64Type`, `NUMBER(p, s)` → `Currency`/`Double`, `DATE` → `TDateTime` (preserva hora), `RAW(16)` → `TGUID`/`GuidType`, e mapeamento de coluna `JSON`.

### 4.7 Soft Delete (`[SoftDelete]`)
- **Atributo Declarativo** — `[SoftDelete('IsDeleted')]` transforma `Remove()` em `UPDATE` automático.
- **Valores Customizados** — `[SoftDelete('Status', 99, 0)]` para inteiros/enums.
- **HardDelete** — `Db.Tasks.HardDelete(Task)` para exclusão física.
- **Restore** — `Db.Tasks.Restore(Task)` para restaurar registros soft-deleted.
- **Query Filters Automáticos** — Registros excluídos ficam **invisíveis** por padrão. `IgnoreQueryFilters` para ver tudo, `OnlyDeleted` para a lixeira.
- **Soft Delete por Timestamp** (`[DeletedAt]`) — Converte automaticamente `Remove()` em uma atualização definindo o timestamp atual, e gera filtros `IS NULL` para registros ativos (Issue #121).
- **IdentityMap Cleanup** — Entidades soft-deleted são removidas do cache de memória após `SaveChanges`.

### 4.8 JSON/JSONB Column Queries (`[JsonColumn]`)
- **Atributo `[JsonColumn]`** — Marca propriedades string como colunas JSON. `[JsonColumn(True)]` para JSONB no PostgreSQL.
- **Query Fluente** — `.Json('path')` para consultar propriedades dentro de colunas JSON: `Prop('Settings').Json('role') = 'admin'`.
- **Propriedades Aninhadas** — `Prop('Settings').Json('profile.details.level') = 5` com notação de ponto.
- **IS NULL** — `Prop('Settings').Json('nonexistent').IsNull` para chaves inexistentes.
- **Cross-Database** — PostgreSQL (`#>>` / JSONB indexado), MySQL (`JSON_EXTRACT` / `JSON_UNQUOTE`), SQLite (`json_extract` + JSON1), SQL Server (`JSON_VALUE`).
- **INSERT com Cast** — `::jsonb` automático no PostgreSQL para `[JsonColumn(True)]`.

### 4.9 Operações em Lote Conscientes do Dialeto (`Dext.Entity.BatchStrategy`) — Spec S59
- **TDextBatchStrategyFactory** — Seleção dinâmica de estratégias de batch `UPDATE` e `DELETE` baseadas em `TDatabaseDialect`.
- **Estratégia PostgreSQL** (`TDextPostgresBatchStrategy`) — Reescreve lotes de `UPDATE` em instrução única `UPDATE table AS t SET ... FROM (VALUES (...), (...)) AS v(...) WHERE t.pk = v.pk` e deleções em `WHERE (pk1, pk2) IN (...)`.
- **Estratégia MySQL / MariaDB** (`TDextMySqlBatchStrategy`) — Reescreve lotes de `UPDATE` em instrução única `UPDATE table SET col = CASE WHEN pk = x THEN y END WHERE pk IN (...)`.
- **Estratégia Array DML Nativo** (`TDextNativeArrayDmlStrategy`) — Mantém binding de arrays nativo para Oracle OCI e Firebird 4+.
- **Desempenho** — Elimina a emulação iterativa do Array DML do FireDAC em PostgreSQL e MySQL, reduzindo o tempo de latência de ~650 µs para ~118 µs por registro.
- **Cross-Database** — PostgreSQL (`#>>` / JSONB indexado), MySQL (`JSON_EXTRACT` / `JSON_UNQUOTE`), SQLite (`json_extract` + JSON1), SQL Server (`JSON_VALUE`).

### 4.10 EntityDataSet (`Dext.Data.EntityDataSet`)
- **Ponte ORM ↔ VCL/FMX** — Conecta componentes (DBGrid, FastReport) a coleções `TList<T>` de POCOs preservando a arquitetura limpa.
- **Zero-Allocation Memory** — Acesso via offsets de memória mapeados pelo `TEntityMap` elimina a necessidade de RTTI ou cópias de string a cada leitura de registro.
- **`LoadFromUtf8Json`** — Carregamento direto de streams/buffers JSON via `TByteSpan` sem conversão prévia de encoding.
- **Setup Automático (Parse AST)** — Em design-time, as *Verbs* "Sync Fields" e "Refresh Entity" fazem o parse direto das units `.pas` e criam os `TFields` dinamicamente **sem precisar compilar o projeto**.
- **Live Data Preview (Híbrido)** — A maior mágica da IDE: informando um `TFDConnection` e um `DataProvider`, o Dext **gera SQL dinâmico** e exibe dados reais na Grid durante o desenvolvimento. Em *runtime*, esse SQL é completamente ignorado e o componente consome apenas as coleções injetadas.
- **Filtros por Expressão** — `DataSet.Filter := 'Score > 100'` suportado usando o mesmo `TExpressionEvaluator` do framework in-memory.
- **Auto-Stabilization** — A propriedade `Active` nunca é serializada como `True` no DFM; evita erros de instâncias ausentes em runtime.
- **DML Memory Mode** — Operações de `Append`, `Edit`, `Post` e `Delete` operam nativamente na lista subjacente na memória.

### 4.11 Inheritance Mapping
- **TPH (Table-Per-Hierarchy)** — Hidratação polimórfica automática baseada em discriminadores via atributos.

### 4.12 Advanced Features
- **Streaming Iterators** (Flyweight pattern) — O(1) de memória para renderizar grandes volumes em views SSR. `TStreamingViewIterator<T>` itera sob demanda durante o `@foreach` do template.
- Conversores automáticos para GUID, Enums, JSONB e UUID v7.
- **Stored Procedures** — Execução declarativa via `[StoredProcedure]` e `[DbParam]`.
- **Multi-Tenancy** — Banco Compartilhado (TenantId), Isolamento por Schema (`search_path`), Tenant per Database.
- **Operações em Lote / Bulk** — APIs em lote de alta performance: `AddRange`, `UpdateRange`, e `RemoveRange` com suporte a coleções genéricas brutas (`TArray<T>`, `IEnumerable<T>`) para persistência em massa em uma única transação de contexto, incluindo fatiamento automático configurável (com padrão de 100 registros, customizável via `WithBulkBatchSize` no `TDbContextOptions`) para otimizar pacotes de rede e respeitar limites de parâmetros do driver (ex: FireDAC).
- **Database Sequence Generators & HiLo** (`Dext.Entity.Sequences`) — Mapeamento declarativo de sequences através do atributo `[Sequence('name', allocationSize)]` ou via fluent `UseSequence`. Utiliza um `TSequenceManager` thread-safe com otimizador Pooled-lo para pré-alocar blocos de chaves na memória, ativando inserções em lote (bulk) de alta performance para chaves primárias sequenciadas. Suporte a SQLite emulado via tabela dedicada (`dext_sequences`).

### 4.13 Filtros Dinâmicos de Query
- **`IgnoreQueryFilters` (API Fluente)** — `Db.Users.IgnoreQueryFilters.ToList` — ignora todos os filtros globais de query registrados (Soft Delete, Multi-Tenancy) para uma única chamada. Não afeta chamadas subsequentes.
- **Controle no Nível da Specification** — `ISpecification<T>.IgnoreQueryFilters` e `ISpecification<T>.IsIgnoringFilters`: permite que classes de specification declarem a intenção, mantendo queries administrativas autocontidas e reutilízaveis.
- **`IsOnlyDeleted` (Integração com Spec)** — `ISpecification<T>.IsOnlyDeleted` propagaa flag de query da lixeira pelo mesmo mecanismo, permitindo que `OnlyDeleted` seja declarado em uma spec.
- **Propagação com Escopo** — Em `TDbSet<T>.ToList(ASpec)`, as flags da spec são propagadas para o estado interno `FIgnoreQueryFilters` / `FOnlyDeleted` antes da geração do SQL e redefinidas via `ResetQueryFlags` em um bloco `finally` — garantindo isolamento entre chamadas.
- **Integração com SQL Generator** — `TSQLGenerator<T>.GetSoftDeleteFilter` retorna string vazia quando `FIgnoreQueryFilters` é `True`. `GetQueryFiltersSQL` também sai cedo pelo mesmo motivo.
- **Padrão Admin Spec** — Permite construir classes de specification dedicadas (`TAdminListSpec`) que chamam `IgnoreQueryFilters` no construtor, habilitando acesso declarativo e sem fricção a dados brutos.

### 4.14 Sincronização remota do TEntityDataSet (S51)
Oferece controle de alterações distribuído e descompressão de rede.

### 4.14.1 Registro Nativo de Alterações (Change-Log) no TEntityDataSet
- **Rastreamento de Estados de Linha** — Controle de modificações usando
  `TEntityRowState` exposto pela lista `Changes` (`TEntityChange`).
- **Tombstones para Exclusão** — Preserva chaves primárias (`Key`) dos registros
  excluídos, permitindo sincronizar remoções com o servidor.
- **Gestão Transacional** — API nativa `AcceptChanges` para consolidar o estado
  em memória pós-sincronização bem-sucedida.

### 4.14.2 Mapeamento de Endpoints "Agreed Service"
- **Roteamento Automático** — Mapeamento via `MapEntityDataSet<T>` expõe
  `GET` para listagem e `POST` `/apply` para persistência das alterações.
- **Persistência Customizável** — Interface plugável `IEntityDataSetStore`
  integrada ao ciclo transacional do ORM (`DbContext.SaveChanges`).

---

## 5. Networking

### 5.1 High-Performance REST Client (`Dext.Net.RestClient`)
- **Fluent API** — Consumo de APIs sem componentes visuais. Métodos: `RestClient('url').BearerToken('...').Get<T>('/path').Await`.
- **Factory de Requisições REST Fluente** — Padrão de agrupamento usando `Client.Request.Get('/path')` para isolar o modo de planejamento/builder, evitando o inchaço de escopo na raiz do cliente e limitações de tipo de retorno (Issue #119).
- **Payloads de Body sem Restrição** — Suporte nativo à serialização de `record` e `TArray<T>` nos payloads de requisição `Body<T>` e no helper de array `BodyArray<T>`, contornando limitações de restrições genéricas do compilador.
- **Deserialização de Records & Arrays** — Deserialização nativa de arrays e objetos JSON diretamente em records e arrays dinâmicos (`TArray<T>`) durante a execução de requisições.
- **Respostas Ergonômicas** — Helper booleano `IRestResponse.IsSuccess` para verificação imediata de status codes na faixa `200..299`.
- **Connection Pooling** — Reuso inteligente de instâncias `TNetHttpClient` (pooling thread-safe), eliminando o overhead de handshakes TCP/SSL repetitivos e reduzindo drasticamente o uso de recursos do SO.
- **Auto-Serialization** — Integração nativa com o motor JSON do Dext para hidratação de objetos e coleções genéricas (`IList<T>`).
- **Async First** — Totalmente integrado ao `Dext.Threading.Async` com suporte a `ICancellationToken` para cancelamento cooperativo e proteção contra Access Violations na UI.
- **Retry Logic** — Recuperação automática com backoff exponencial e suporte a Async/Await.
- **Typed Responses** — `Client.Get<TUser>('/users/1')` com deserialização automática.
- **Async Chaining** — `Client.Get<TToken>('/auth').ThenBy<TUser>(...)`.OnComplete(...)`.Start`.
- **Cancellation** — `ICancellationToken` para abortar requisições em andamento.
- **Pluggable Auth** — `TBearerAuthProvider`, `TBasicAuthProvider`, `TApiKeyAuthProvider`.
- **Thread Safety** — Snapshot imutável da configuração no `Execute`; execução isolada via pool.
- **Response Headers** — Acesso completo via `GetHeader` (case-insensitive) e `GetHeaders` (TNetHeaders array).
- **THttpRequestInfo** — Integração com parsers `.http` para execução de requisições ad-hoc.
- **Campos de Formulário Multipart com Content-Type** — Suporte para definição de tipos MIME específicos (ex: `application/json`) para campos individuais de formulário em requisições multipart via `AddFormField` e `AddMultipartField` (Issue #125).
- **Parâmetros de Consulta Condicionais** — Suporte para adição fluente de parâmetros de consulta condicionais (`QueryParamIfNotEmpty`, `QueryParamIf` e sobrecargas com valores padrão fallback) para simplificar a construção de requisições (Issue #123).
- **Compatibilidade Legada e Fallback Indy** — Abstração completa do motor HTTP (`IDextHttpEngine`) com fallback automático via Indy (`TIdHTTP`) para IDEs antigas (Delphi XE2 a XE7), ativado em versões inferiores ao XE8 ou sob a diretiva `DEXT_FORCE_INDY`. Requisição de OpenSSL DLLs para chamadas HTTPS legadas.
- **Negociação Automática** — O `TRestClient` sinaliza `Accept-Encoding`
  e realiza a descompactação via `TZDecompressionStream` de forma transparente.
- **Preservação de Stream Bruto** — Mantém o stream compactado original
  disponível em `RawContentStream` para inspeção e auditoria.
- **Certificado de Cliente Dinâmico / mTLS** — `TRestClient.ClientCertificate` com sobrecargas para arquivo (`cert.pfx`, `cert.p12`) e stream em memória (`TStream`). Permite a comunicação com webservices públicos (como SAF-T em Portugal) sem necessidade de instalação prévia no repositório de certificados do Windows. Isolamento automático por requisição e limpeza nos pools de conexão.

### 5.2 Authentication Providers
- **Bearer Token (JWT)** — Envio automático de `Authorization: Bearer <token>`.
- **Basic Auth (RFC 7617)** — Encoding Base64 de `user:password`.
- **API Key** — Header ou query string customizável.
- **OAuth 2.0 Client Credentials (RFC 6749 §4.4)** — Token caching automático, refresh thread-safe com margem de segurança de 30s para evitar uso de tokens expirados.

### 5.3 Cliente Redis Nativo (S13) (`Dext.Net.Redis`)
O Dext inclui uma biblioteca cliente nativa e de alta performance para o Redis, suportando os protocolos RESP2 e RESP3. Ele conta com otimizações de parsing zero-allocation, connection pooling integrado, pipelines assíncronos de comandos via `TAsyncTask` e processamento de Pub/Sub concorrente utilizando canais.

### 5.3.1 Serialização de Alta Performance (RESP2/RESP3)
- **Parser Zero-Allocation** — O `TDextRedisParser` analisa os streams de bytes RESP sem alocações desnecessárias no heap usando spans de memória (`TByteSpan`).
- **Novos Tipos do RESP3** — Suporte nativo para os novos tipos de retorno do RESP3: Nulos (`_`), Booleanos (`#`) e Double Floats (`,`).

### 5.3.2 Connection Pool & Thread Safety
- **TDextRedisConnectionPool** — Pool de conexões seguro e concorrente (`IStack<TDextRedisConnection>`) para evitar custos de conexão repetida e gerenciar recursos de forma eficiente.
- **Comandos Thread-Safe** — Gerenciamento transparente na aquisição e liberação das conexões durante chamadas concorrentes ao cliente.

### 5.3.3 Pub/Sub Reativo e Canais
- **TDextRedisPubSub** — Motor de Pub/Sub assíncrono integrado com canais concorrentes do Dext (`IChannel<TDextRedisMessage>`) para despacho seguro de mensagens entre threads.

### 5.3.4 Integração com RedisJSON & Dext.Json
- **Suporte ao Módulo RedisJSON** — Integração nativa com a engine `Dext.Json` para serializar e deserializar objetos complexos em Delphi diretamente de e para o servidor Redis.

### 5.4 Arquitetura TLS/SSL (`Dext.Net.Security`)
- **Abstração Unificada de TLS** — Definições de `IDextTLSEngine`, `IDextTLSContextProvider` e `IDextTLSStream` para desacoplamento de transporte.
- **Motor OpenSSL 3.x Memory BIO** — Zero-copy/lock-free TLS handshake e framing criptografado em memória para sockets TCP assíncronos (`epoll` no Linux e `IOCP` no Windows).
- **Integração HTTP.sys & Windows Schannel** — Suporte nativo a bindings HTTPS e certificados do Windows Certificate Store sem DLLs externas.
- **Taurus TLS & Indy SSL** — Provedor de TLS 1.3 / OpenSSL 3.x (`TDextTaurusTLSContext`) para servidores Indy.
- **Suporte SSL no TDextRedisClient (`rediss://`)** — Envoltório TLS transparente para o cliente Redis nativo.
- **Ferramenta CLI dev-certs (`dext dev-certs https`)** — Gerador CryptoAPI nativo em Pascal para certificados RSA X.509 de desenvolvimento com extensão SAN (`localhost`, `127.0.0.1`) e registro automático no Root Certificate Store.

### 5.5 Sockets & MQTT nativo (S47)
O framework inclui suporte para desacoplamento de transporte no servidor IOCP/Epoll para exposição de sockets TCP/UDP puros e uma implementação nativa do protocolo MQTT v3.1.1 (cliente e broker) para mensageria assíncrona.

### 5.5.1 Desacoplamento de Transporte (IConnectionHandler)
- **Desacoplamento de Engine** — Abstração de conexões físicas (`IDextTransportConnection`) e manipulador customizado (`IConnectionHandler`) que permite interceptar conexões puras de rede diretamente na engine IOCP/Epoll sem passar pelo parser de requisições HTTP.

### 5.5.2 Servidores e Clientes TCP/UDP
- **TDextTcpServer & TDextTcpClient** — Servidor TCP baseado nas engines assíncronas do Dext e cliente leve com controle de timeouts de leitura e escrita.
- **TDextUdpServer & TDextUdpClient** — Componentes UDP para transmissão rápida de pacotes, com suporte a spans de bytes e callback assíncrona de recebimento.

### 5.5.3 Protocolo MQTT v3.1.1 Nativo
- **Encoder/Decoder Binário** — Parser de alta performance com codificação e decodificação eficiente de inteiros de comprimento variável (Remaining Length) e suporte para todas as mensagens de controle MQTT (CONNECT, CONNACK, PUBLISH, PUBACK, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK, PINGREQ, PINGRESP, DISCONNECT).
- **Roteador Trie Tree** — Árvore Trie customizada para correspondência eficiente de tópicos com suporte completo aos coringas de nível único (`+`) e múltiplos níveis (`#`).
- **Broker Server e Client** — Servidor broker concorrente com suporte a sessões limpas e controle de assinaturas, e cliente assíncrono com thread de recebimento dedicada e keep-alive automático via ping/pong.

### 5.6 gRPC & Protocol Buffers (S02)
Implementação do protocolo de transporte binário de alta performance.

### 5.6.1 Serializador Protobuf (`Dext.Serialization.Protobuf`)
- **TProtobufSerializer** — Engine de serialização binária de alta velocidade e zero alocação no heap para Protocol Buffers (proto3).
- **Formatadores Específicos** — Suporte a formatação Varint, Fixed32, Fixed64 e Length-Prefixed usando a abstração de memória de alto desempenho `TSpan`.
- **Marshalling via RTTI** — Serialização direta de objetos Delphi baseada em mapeamento de atributos `[ProtoMember]` e ordinais de campo.

### 5.6.2 Codec de Mensagens gRPC (`Dext.Grpc.Codec`)
- **TGrpcCodec** — Implementação do codec de enquadramento (framing) para mensagens gRPC Length-Prefixed Message (LPM).
- **Suporte a Compressão** — Tratamento do flag de compressão de 1 byte seguido de tamanho em big-endian de 4 bytes para entrega segura em streams HTTP/2.

### 5.6.3 Servidor gRPC (`Dext.Web.Grpc.Server`)
- **TGrpcDispatcher** — Decodificador de frames HTTP/2 que despacha requisições `application/grpc` para os respectivos métodos e classes de serviço registrados.
- **Mapeamento RTTI** — Resolução e chamada dinâmica de serviços baseados em interfaces usando tabelas de roteamento otimizadas.

### 5.6.4 Integração Cliente e DataSet (`Dext.Entity.GrpcProvider`)
- **TEntitygRpcProvider** — Provedor de sincronização remota gRPC integrado para `TEntityDataSet`, possibilitando persistência bidirecional estruturada.
- **TgRpcClient** — Cliente gRPC de baixo nível responsável pelo transporte de streams Protobuf e recebimento de payloads binários de resposta.

---

## 6. Event Bus

Publish/Subscribe in-process inspirado no **MediatR** (`Dext.Events`). Handlers respeitam o ciclo de vida do DI (handlers Scoped compartilham o contexto da request).

### 6.1 Core Architecture (`Dext.Events.Interfaces`, `Dext.Events.Bus`)
- **IEventBus** — Barramento central de eventos in-memory para desacoplamento total entre produtores e consumidores.
- **IEventHandler\<T\>** — Interface tipada para handlers de eventos. Múltiplos handlers por tipo de evento, executados em ordem de registro.
- **IEventPublisher\<T\>** — Fachada ISP (Interface Segregation Principle) para componentes que publicam apenas um tipo de evento.
- **Dispatch Síncrono** — `IEventBus.Dispatch` invoca todos os handlers e retorna `TPublishResult` com estatísticas (`HandlersInvoked`, `HandlersFailed`, `HandlersSucceeded`).
- **Dispatch Assíncrono** — `DispatchBackground` executa handlers em thread separada com escopo DI isolado (fire-and-forget).
- **TEventBusExtensions** — Helpers estáticos genéricos `Publish<T>` e `PublishBackground<T>` que fazem boxing do evento para `TValue` e delegam ao `IEventBus`.

### 6.2 Behavior Pipeline (`Dext.Events.Behaviors`)
- **IEventBehavior** — Middleware cross-cutting para o pipeline de eventos. Método `Intercept(AEventType, AEvent, ANext)` — chamar `ANext()` continua o pipeline; omitir short-circuits.
- **TEventLoggingBehavior** — Logging estruturado via `ILogger`. Debug antes/depois do handler com elapsed time. Error com re-raise em falhas.
- **TEventTimingBehavior** — Debug-only, registra tempo de dispatch via `OutputDebugString`.
- **TEventExceptionBehavior** — Wrapping estruturado de exceções em `EEventDispatchException` com nome do tipo de evento. Re-raise preserva contexto original.
- **Behaviors Globais vs Per-Event** — Globais aplicam-se a todos os eventos; Per-event aplicam-se apenas ao tipo específico e executam DENTRO dos globais.

### 6.3 DI Extensions (`Dext.Events.Extensions`)
- **`Services.AddEventBus`** — Registra `IEventBus` como Singleton (cada Publish cria escopo DI filho).
- **`Services.AddScopedEventBus`** — Registra como Scoped (handlers compartilham o mesmo escopo, ideal para web requests com DbContext compartilhado).
- **`Services.AddEventHandler<TEvent, THandler>`** — Registro tipado de handler com auto-registro Transient (respeita registros existentes).
- **`Services.AddEventBehavior<T>`** — Behavior global. **`AddEventBehaviorFor<TEvent, T>`** — Behavior per-event.
- **`Services.AddEventPublisher<T>`** — Registra `IEventPublisher<T>` transient para injeção ISP.
- **`Services.AddEventBusLifecycle`** — Registra `TEventBusLifecycleService` como `IHostedService`.

### 6.4 Lifecycle Events (`Dext.Events.Lifecycle`)
- **TEventBusLifecycleService** — Background service que escuta `IHostApplicationLifetime` e publica `TApplicationStartedEvent`, `TApplicationStoppingEvent`, `TApplicationStoppedEvent` no `IEventBus`.
- **Hosting Bridge** (`Dext.Hosting.Events.Bridge`) — `THostingLifecycleEventBridge` para integração com o background services builder via `AddLifecycleEvents`.

### 6.5 Testing Support (`Dext.Events.Testing`)
- **TEventBusTracker** — `IEventBus` falso para testes: grava cada publish em lista tipada. `DispatchBackground` é síncrono.
- **Registro no DI** — `TEventBusTracker.Register(Services, Tracker)` no lugar de `AddEventBus`, encadeável com `AddEventPublisher` / `AddTransient`.
- **Asserções** — `HasPublished<T>`, `PublishedCount<T>`, `LastPublished<T>`, `GetPublished<T>`, `Clear`.

### 6.6 Aggregate Exception Handling
- **EEventDispatchAggregate** — Exceção agregada contendo `Errors: TArray<string>` com uma entrada por handler que falhou. Todos os handlers sempre são invocados antes do raise.

---

## 7. Testing & Quality

### 7.1 Test Runner
- **CLI Runner** — `dext test` executa a suíte do projeto. Em Windows, `--coverage` gera HTML/XML e `dext_coverage.xml` (SonarQube coverage) via Delphi Code Coverage. O host vivo da suíte é o **Dext Test Explorer** (S36 / seção 7.7), não um dashboard web embutido.
- **Fluent Runner API** (`Dext.Testing.Fluent`) — Configuração programática: `TTest.Configure.Verbose.RegisterFixtures([...]).Run`. O exe da suíte já lê `-filter:`, `-category:`, `-fixture:`, `-junit:`, `-html:`, `-json:`.

### 7.2 Attribute-Based Runner (`Dext.Testing.Attributes`)
Permite a escrita de testes sem herança de classes base, usando metadados RTTI.
- **Core Attributes** — `[Fixture]`, `[Test]`, `[Fact]`, `[TestClass]`.
- **Lifecycle Management** — `[Setup]`, `[TearDown]`, `[BeforeAll]`, `[AfterAll]`, `[AssemblyInitialize]`, `[AssemblyCleanup]`.
- **Data-Driven Testing** —
  - `[TestCase(A, B, Expected)]` — Testes parametrizados inline.
  - `[TestCaseSource('MethodName')]` — Provedores de dados dinâmicos via método.
- **Execution Filters & Control** —
  - `[Ignore('Reason')]`, `[Skip('Reason')]` — Pular testes.
  - `[Explicit]` — Testes executados apenas se selecionados nominalmente.
  - `[Category('Tag')]`, `[Trait('Name', 'Value')]` — Categorização e filtragem.
  - `[MaxTime(ms)]` — Aviso se o teste passar do orçamento (não falha).
  - `[Repeat(n)]` — Repete o método n vezes.
  - `[Priority(n)]` — Ordem de execução (menor número primeiro). Não é filtro de CLI.
  - `[Platform('Windows, Linux')]` — Restrição por sistema operacional.

### 7.3 Fluent Assertions (`Dext.Assertions`)
API fluente baseada no padrão `Should(Value)`.
- **Typed Assertions** — Métodos específicos para `ShouldString`, `ShouldInteger`, `ShouldDouble` (aproximação), `ShouldBoolean`, `ShouldDateTime`, `ShouldGuid`, `ShouldUUID`, `ShouldObject`.
- **List/Collection Assertions** — `Should(List).HaveCount(5).Contain(X).OnlyContain(Predicate).AllSatisfy(Predicate)`.
- **Structural Comparison** — `BeEquivalentTo` for deep object and collection comparison (order-independent).
- **Soft Asserts** — `Assert.Multiple(procedure ... end)` to collect multiple failures in a block before interrupting the test.
- **Action Assertions** — `Should(Proc).Throw<EException>().WithMessageContaining('...')`.

### 7.3b Web Application Factory (S66 / S68)
- **`TDextApplicationFactory<TApp>`** / **`TDextWebApplicationFactory<TApp>`** — Monta `TWebApplication` com `WithTestServices` / `WithConfigure`.
- **`CreateClient: IDextTestHttpClient`** — GET/POST/PUT/DELETE in-process (sem TCP); despacha via `TWebApplication.BuildRequestPipeline`.
- **`IDextTestHttpResponse`** — StatusCode, ContentType, Body, headers.

### 7.4 Snapshot Testing
- **`MatchSnapshot('name')`** — Verificação de objetos complexos e payloads JSON via comparação de baselines em disco.
- **Pasta** — Baselines em `{ExeDir}\Snapshots\` (não `__snapshots__/`).
- **Structural JSON Compare** — Comparação inteligente que ignora formatação e ordem de propriedades em JSON.
- **Update Mode** — Variável de ambiente `SNAPSHOT_UPDATE=1` para atualizar baselines.

### 7.5 Mocking & Interception (`Dext.Mocks`, `Dext.Interception`)
- **Dynamic Proxies** — `TProxy` (Interfaces) e `TClassProxy` (Classes com métodos virtuais) via `TVirtualInterface` e `TVirtualMethodInterceptor`.
- **Fluent Mocking** — `Mock<T>.Setup.Returns(Val).When.Method(Args)`.
- **Argument Matchers** — `Arg.Any<T>`, `Arg.Matches<T>` (`Arg.&Is<T>`), `Arg.IsNil<T>`, `Arg.IsNotNil<T>`.
- **Verification** — `Received(Times.Once)`, `Received(Times.AtLeast(n))`.
- **Auto-Mocking** — `TAutoMocker` for automated mock injection into the DI container during unit tests.

### 7.6 Reporting & CI/CD (`Dext.Testing.Report`)
- **Multi-Format Export** — JUnit XML, xUnit XML, TRX (Azure DevOps), HTML (Dark Theme), JSON.
- **SonarQube Integration** — Geração de relatórios de cobertura de código e falhas compatíveis com Quality Gates.
- **Integração TestInsight Desacoplada** (`Dext.Testing.TestInsight`) — Gancho de execução e ouvinte desacoplado para o plugin TestInsight que direciona execuções e envia resultados para a IDE de forma transparente, eliminando acoplamento em tempo de compilação.
- **Decoupled Test Runner Integration & Registry** (`Dext.Testing.Integration`) — Registro por linha de comando e processamento de parâmetros para execução desacoplada do executor de testes a partir da IDE ou da CLI, sem dependências de BPLs intermediárias.
- **Native DUnitX Integration** (`Dext.Testing.DUnitX`) — Adaptador de runner desacoplado para DUnitX que trafega resultados, status em tempo real e filtros via HTTP/SSE locais para o Expert Dext Test Explorer.
- **Native DUnit Integration** (`Dext.Testing.DUnit`) — Adaptador de runner desacoplado para DUnit que registra ouvintes customizados para trafegar resultados, metadados de tempo de execução e streams de execução para o Dext Test Explorer.
- **Native DUnit2 Integration** (`Dext.Testing.DUnit2`) — Adaptador de runner desacoplado usando interfaces proxy para trafegar resultados em tempo real e hierarquia de suites do DUnit2 para o Dext Test Explorer.
- **Test Context Injection** — `ITestContext` injetável via parâmetro para `WriteLine`, `AttachFile` (screenshots) e metadados de execução.
- **Histórico por método no Test Explorer** (`TTelemetryTracker` em `Dext.Testing.Design.DockableForm`) — Arquivo `{projeto}\.dext\testing\history.json` (até 1000 linhas). O painel Details marca teste flaky e regressão de duração. Não é o JSON de totais da suíte.
- **`TTestHistoryManager`** (`Dext.Testing.History`, `dext_test_history.json`) — Totais por **run** (passed/failed/skipped/duration, últimas 50). Hoje só o dashboard sidecar consome. O Explorer ainda não mostra essa série — backlog S75 F-10.
- **Telemetria de Testes OpenTelemetry** (`Dext.Testing.Listeners.Telemetry`) — Listener integrado de telemetria enviando métricas de execução de testes (`test_duration_ms`, `test_count_passed`, `test_count_failed`) para coletores OpenTelemetry.

### 7.7 RAD Studio Expert & IDE Integration (`Dext.Testing.Design.*`)
- **Dext Test Explorer Dockable Window** (`Dext.Testing.Design.DockableForm`) — Janela ancorável nativa no RAD Studio exibindo árvore interativa de suítes, filtros por status e busca. Histórico **por método** no Details (flaky / duração). Totais da suíte ao longo das runs: S75 F-10.
- **Gutter Margin Icons** (`Dext.Testing.Design.Gutter`) — Marcas visuais interativas na margem esquerda do editor de código do RAD Studio (verdes para sucesso, vermelhas para falhas).
- **Servidor HTTP/SSE Local da IDE** (`Dext.Testing.Design.Server`) — Servidor de comunicação em tempo real embutido no Expert que recebe o fluxo de execução dos testes sem BPLs intermediárias.
- **Visualizador de Cobertura de Código** (`Dext.Testing.Design.Coverage`) — Destaque direto no editor das linhas de código cobridas por testes via parsing AST (`Dext.Testing.Design.AST`).

### 7.8 Escala e rigor
O Dext é validado continuamente por uma infraestrutura de testes massiva para garantir a integridade entre seus subsistemas:

- **Estatísticas de Engenharia** — O projeto ultrapassa **200.000 linhas de código Pascal puro** (excluindo templates e documentação), refletindo um investimento massivo em estabilidade e abstrações de alto nível.
- **Cobertura Massiva** — Centenas de suítes de testes com milhares de asserções individuais validando desde o Core (Memory, Collections) até integrações complexas de Web e ORM.
- **Matriz Multi-DB (ORM)** — O motor de persistência é testado exaustivamente em uma matriz real de 5 bancos de dados: PostgreSQL, SQL Server, MySQL, SQLite e Firebird.
- **Stress & Concurrency Testing** — Validação de coleções concorrentes, canais e async tasks sob alta carga para garantir ausência de Race Conditions.
- **Evidências de Campo** — Framework validado em projetos reais com deploy em **AWS e Azure**, e sistemas de gestão fiscal processando picos de **~800.000 requisições diárias**.
- **CI/CD** — Relatórios JUnit / xUnit / TRX / HTML / JSON e cobertura SonarQube (`dext_coverage.xml`) para pipelines Azure DevOps e GitHub Actions.

---

## 8. Template Engine

### 8.1 Core Architecture
- **ITemplateEngine** — Interface principal: `Render(template, context)` e `RenderTemplate(name, context)`.
- **TDextTemplateEngine** — Implementação completa com parser de AST (Abstract Syntax Tree). Cada diretiva é compilada em um nó (`TTemplateNode`) com método `Render`.
- **ITemplateContext** — Contexto hierárquico com valores string, objetos e listas. `CreateChildScope` para escopo aninhado.

### 8.2 Template Loader
- **ITemplateLoader** — Interface plugável para carregamento de templates. Implementações: FileSystem e In-Memory.

### 8.3 Node Types (AST)
- `TTextNode` (texto literal), `TExpressionNode` (interpolação `{{ var }}`), `TIfNode`/`TElseIfNode`/`TElseNode` (condicionais), `TForEachNode` (iteração com `@index`, `@first`, `@last`), `TBlockNode` (blocos nomeados), `TExtendsNode` (herança de layout), `TSectionNode` (seções), `TMacroNode` (macros reutilizáveis), `TBreakNode`/`TContinueNode` (controle de fluxo em loops).

### 8.4 Expression Engine
- Parser de expressões com suporte a operadores aritméticos, comparação, lógicos (`and`, `or`, `not`).
- **Chained Filters** — `{{ value | upper | truncate(10) }}` com pipeline de filtros.
- **Filter Registry** (`ITemplateFilterRegistry`) — `RegisterFilter(name, func)` para filtros customizados.
- **Built-in Filters** — `upper`, `lower`, `capitalize`, `truncate`, `default`, `date`, `html_escape`, etc.

### 8.5 Advanced Features
- **Layout Inheritance** — `{% extends "base.html" %}` com override de blocos.
- **Whitespace Control** — `{%- -%}` para controle de whitespace em diretivas.
- **HTML Mode** — `IsHtmlMode` para auto-escaping de output.
- **Source Position Tracking** — `TSourcePos` com linha, coluna e filename para error reporting preciso.
- **ETemplateException** — Exceções com posição e snippet do template para debugging.

---

## 9. Validation

- **Attribute-Based Validation** — Decoradores RTTI: `[Required]`, `[StringLength(min, max)]`, `[Range(min, max)]`, `[RegularExpression(pattern)]`, `[EmailAddress]`, `[Url]`.
- **Fluent Validation API** — Classe base de validação fortemente tipada `TAbstractValidator<T>` que implementa `IValidator<T>` como uma alternativa moderna ao FluentValidation do C#.
- **Fluent Rule Builder** — Record `TValidationRuleBuilder<T>` extremamente eficiente em memória que evita alocações na heap ao construir regras de validação encadeadas (`Required`, `Length`, `Range`, `EmailAddress`, `Matches`, `MatchesPattern`, `Must`, `When`).
- **Integração com Smart Properties** — Sobrecargas concretas de `RuleFor` para propriedades inteligentes padrão `Prop<T>` (ex: `Prop<string>`, `Prop<Integer>`, `Prop<Boolean>`, etc.) para extrair automaticamente nomes de propriedade a partir de entidades fantasmas de protótipo (`Prototype.Entity<T>`) sem magic strings ou problemas de coerção implícita de tipos.
- **Pattern Registry** — Registro `TValidationPatterns` mapeando chaves para expressões regulares específicas de localização (ex: telefone e CEP para Pt-BR ou En-US).
- **TValidator** — Helper não-genérico: `Validate(obj)` retorna `TValidationResult` com lista de `TValidationError` (campo + mensagem).
- **TValidator\<T\>** — Versão genérica tipada.
- **Custom Validators** — Herança de `ValidationAttribute` para regras de negócio customizadas.
- **Integração Web** — Resolução automática de validadores registrados (`IValidator<T>`) a partir do container de Injeção de Dependências (DI) dentro do pipeline de model binding Web (`THandlerInvoker.Validate`), gerando exceções `TWebValidationException` que retornam payloads JSON/HTMX de erro estruturados.

---

## 10. Mapper

- **TMapper** — Fachada estática e registro centralizado para mapeamento objeto a objeto usando RTTI Delphi.
- **Configuração de Mapeamento Fluente** — Record `TTypeMapConfig<TSource, TDest>` com suporte a mapeamentos customizados via sintaxe fluente:
  - `ForMember(DestName, MapFunc)` — Define funções de mapeamento customizadas para converter valores da origem para o destino.
  - `Ignore(DestName)` — Evita a cópia de propriedades específicas.
- **Mapeamento de Instância** — `TMapper.Map<TSource, TDest>(Source)` instancia e retorna uma nova classe de destino mapeada.
- **Mapeamento Em-Lugar** — `TMapper.Map<TSource, TDest>(Source, Dest)` mapeia as propriedades da origem sobre uma referência de objeto de destino existente.
- **Mapeamento de Coleções** — `TMapper.MapList<TSource, TDest>(SourceList)` mapeia listas e coleções genéricas automaticamente.
- **Mapeamento de Records** — Copia campos e propriedades equivalentes entre classes e records.
- **Otimização de Valores Padrão** — Parâmetro `AOnlyNonDefault` para mapear apenas valores não-padrão (evitando sobrescrever valores previamente inicializados no destino).
- **CreateMap\<TSource, TDest\>** — Registro de mapeamento com reflexão automática de propriedades por nome (complementa o `TTypeMapConfig` acima).

---

## 11. Multi-Tenancy

- **ITenantProvider** — Abstração para identificação do tenant atual.
- **ITenantConnectionStringProvider** — Resolução dinâmica de connection strings por tenant.
- **Estratégias** — Shared Database (discriminador TenantId), Schema Isolation (`search_path` no PostgreSQL), Database per Tenant.
- **Filtros Tenant em DML (S68)** — `GenerateUpdate` / `GenerateDelete` (e templates batch) acrescentam `AND TenantId = :…` para entidades `ITenantAware` via `ITenantProvider` (respeita `.IgnoreQueryFilters`).
- **Integração DI** — Registro como serviço Scoped para resolução por request.

---

## 12. Desktop UI & Design-Time

### 12.1 Navigator Framework (Flutter-style)
- **ISimpleNavigator** — Navegação Push/Pop/Replace/PopUntil com passagem de dados via `TValue`.
- **3 Adapters** — `TCustomContainerAdapter` (embutir frames em painel), `TPageControlAdapter` (tabs), `TMDIAdapter` (janelas filhas).
- **Middleware Pipeline** — `TLoggingMiddleware`, `TAuthMiddleware`, `TRoleMiddleware` — mesma arquitetura do Web pipeline.
- **Lifecycle Hooks** — `INavigationAware` com `OnNavigatedTo(Context)` e `OnNavigatedFrom`.
- **DI Integration** — Navigator registrado como serviço Singleton no container.

### 12.2 Magic Binding (`Dext.UI.Binding`)
- **Two-Way Binding por Atributos** — `[BindEdit('Name')]`, `[BindCheckBox('Active')]`, `[BindText('ErrorMessage')]`.
- **Nested Properties** — `[BindEdit('Customer.Address.City')]` com notação de ponto.
- **Message Dispatch** — `[OnClickMsg(TSaveMsg)]` elimina handlers `OnClick` manuais.
- **Custom Converters** — `IValueConverter` com `Convert`/`ConvertBack` para tipos complexos (ex: `TCurrencyConverter`).
- **TBindingEngine** — Motor central que sincroniza ViewModel ↔ UI automaticamente.

### 12.3 MVVM Patterns
- Arquitetura limpa com ViewModel + Controller + DI.
- **Integração com Validação** — `FViewModel.Validate` com erros automaticamente refletidos na UI via binding.

### 12.4 Infraestrutura
- **Interception Engine** — Motor de proxy para intercepção de métodos, base para Mocks e recursos de AOP (Aspect-Oriented Programming).
- **Design-Time Experts** — Data Preview em IDE Grid e editores de propriedades especializados para metadados.

### 12.5 Design-Time Scaffolding Experts (`Dext.EF.Design.Scaffolding`)
- **Integração via TSelectionEditor** — Menus de contexto não invasivos para `TFDConnection` e `TDataSet` (FireDAC e Genérico). Os menus do Dext coexistem com os menus nativos da IDE.
- **TTableSelectionForm** — Interface de seleção avançada com filtro em tempo real, atalhos "Selecionar Tudo/Nenhum" e contadores dinâmicos de tabelas/seleção.
- **Live Scaffolding Preview** — Janela de preview de alta fidelidade com geração de código em tempo real, estatísticas (Entidades/Metadados/Linhas) e troca de estilo (POCO vs. Smart).
- **Smart PascalCase Engine** — Lógica de nomenclatura consciente de acrônimos (`EmployeeID` → `EmployeeId`, `ReportsTo` preservado) com suporte a normalização de `snake_case` e `ALL_CAPS`.
- **Inferência de Metadados Avançada** — Detecção precisa de AutoInc via RTTI e `ftAutoInc`, garantindo paridade 1:1 com o schema do banco de dados.
- **Automação IOTA** — Criação fluida de novas units em memória e associação automática com o projeto Delphi ativo.

---

## 13. CLI & Scaffolding

- **Dext CLI (S01)** — Motor CLI unificado (`dext.exe`) para gerenciamento de projetos e automação de desenvolvimento.
- **Advanced Scaffolding** — Geração de projetos e arquivos via templates inteligentes: `dext new` (projetos), `dext scaffold` (controllers, entidades ORM, DTOs, middlewares).
- **`dext dev-certs`** — Provisionador nativo CryptoAPI de certificados X.509 de desenvolvimento local com extensão SAN e registro automático no Root Certificate Store.
- **`dext test --coverage`** — Executor da suíte com **cobertura de código** via `.map` (Windows). Gera HTML/XML do Delphi Code Coverage e `dext_coverage.xml` (SonarQube coverage) automaticamente. Sem flag `--sonar` à parte.
- **`dext migrate [up|down|list|generate]`** — Gerenciador CLI de migrações de esquema de banco de dados para o Dext ORM.
- **`dext doc`** — Geração automatizada de documentação técnica estática HTML e mapas visuais de rotas.
- **`dext ui`** — Dashboard web local de **configuração do projeto** (não é monitor da suíte de testes).
- **`dext index`** — Mapeamento e indexação de todos os símbolos públicos (classes, records, interfaces, métodos) em Markdown, JSON e CSV otimizados para consumo por agentes de IA e NotebookLM.
- Scaffolding com resolução automática de schema em maiúsculas para metadados Oracle (`MetaCurSchema`, `MetaDefSchema`), como no índice em inglês.

---

## 14. Observability

- **TDiagnosticSource (S03)** — Publicador de eventos centralizado baseado em payloads JSON, garantindo desacoplamento entre produtores (ORM, Web) e consumidores. Observadores interceptam o ciclo de vida HTTP e a execução SQL sem acoplar monitoramento à regra de negócio.
- **Activity Tracking** — CorrelationId / rastreamento de atividades para depuração de fluxos complexos e distribuídos.
- **Dext Sidecar (`DextSidecar.exe`)** — Aplicação nativa acoplada para monitoramento em tempo real (`Dext.Services.FileWatcher.pas`), streaming de logs (`Dext.Sidecar.LogStreamer.pas`), servidor web de telemetria (`TSidecarServer`) e interface System Tray VCL (`Dext.Vcl.TrayIcon.pas`).
- **Telemetry Bridge** (`Dext.Logging.Telemetry`) — Integração automática com `ILogger`, permitindo visualizar telemetria HTTP e SQL no console ou arquivos de log.
- **SQL Capture** — Extração e formatação de instruções SQL nativas do ORM para auditoria em tempo real.
- **HTTP Life-cycle** — Tracing de latência, códigos de status e rotas do framework web.
- **Stack Trace Extraction** (`Dext.Core.Debug`) — Extração precisa e detalhada do stack trace no momento da exception. Fundamental para debugar um framework altamente integrado onde o fluxo de execução é dinâmico e o mesmo erro pode ter origens completamente diferentes dependendo do contexto.

O framework inclui uma suíte de observabilidade premium, de alta performance e assíncrona, para coleta, armazenamento e visualização de logs estruturados, spans distribuídos, métricas do sistema e profiling de chamadas de banco de dados e conexões de rede externas.

### 14.1 Tracing Distribuído & Logging Estruturado (S24)
- **Ring Buffer Assíncrono** — Pipeline de logs estruturados e spans armazenados em ring buffer de alta performance na memória (limite de 1000 itens) para evitar gargalos de I/O em threads de execução HTTP.
- **Persistência Assíncrona** — Thread de background dedicada (`TDashboardSaveTimer`) que descarrega periodicamente os logs para `telemetry.json` a cada 30 segundos de forma não-bloqueante.
- **Visualização Gantt Hierárquica** — O Dashboard renderiza em tempo real a árvore de spans sob o contexto de trace pai (`TraceId`/`SpanId`), permitindo analisar tempos de resposta e gargalos de processamento de forma sequencial.

### 14.2 Métricas de Sistema & Throughput (S25)
- **RED Metrics & Performance** — Gráficos em tempo real no Dashboard monitorando HTTP RPS (Requisições por Segundo), SQL QPS (Queries por Segundo), HTTP Errors e Latência média de processamento.
- **System Health Monitor** — Coleta e amostragem de dados do sistema operacional: uso de CPU (%), consumo de memória física (Working Set em MB), contagem de threads ativas no processo e conexões de banco ativas.
- **Persistência Não-Bloqueante** — Métricas serializadas em buffer circular e gravadas a cada 30s em `metrics.json` via timer assíncrono.

### 14.3 Profiler de Banco de Dados & Outbound HTTP (S27)
- **Auto-Instrumentação FireDAC** — Interceptação automática nas camadas do driver de banco de dados (`Dext.Entity.Drivers.FireDAC.pas`). Captura comandos SQL (`db.statement`), serialização de parâmetros de queries (`db.params`), elapsed time de execução do comando e captura automática de exceções nativas.
- **Auto-Instrumentação Outbound HTTP** — Interceptação de chamadas de rede no cliente REST (`Dext.Net.RestClient.pas`), capturando URL de destino, método HTTP, tempos de resposta de rede, códigos de status e tratamento de falhas.
- **Context Inspector Drawer** — Painel deslizante no Dashboard que abre ao clicar em caixas de spans na árvore. Exibe a query SQL formatada, os parâmetros do banco estruturados, cURL pronto para cópia da chamada HTTP, e metadados adicionais.

### 14.4 Streamable Sessions & HTMX (S23)
- **IStreamableSessionManager** — Gerenciador de canais SSE com limpeza de sessões expiradas (Garbage Collector a cada 60s expulsando sessões inativas após 30 minutos).
- **HTMX Fragment Swap** — Endpoints que expõem fragmentos HTML dinâmicos (como `/sidecar/fragments/metrics`) permitindo atualização visual direta no DOM em tempo real via HTMX sem escrever código JavaScript.

---

## 15. AI Skills

- **Native AI Skills** — Arquivos de instrução modulares (`dext-web.md`, `dext-orm.md`, `dext-auth.md`) que ensinam assistentes de IA (Cursor, Antigravity, Copilot, Claude) a gerar código idiomático Dext.
- **3 modos de integração** — Cópia direta para `.agents/skills/`, configuração global customizada, ou symlinks.
- **Modular por Design** — Skills atômicos para poupar tokens de contexto; carregue apenas o módulo relevante para a feature atual.
- **Compatibilidade** — Claude Code, Cursor, Antigravity, Cline, OpenCode, GitHub Copilot.

---

## 16. MCP Server

O framework fornece uma implementação nativa e sem dependências da especificação **MCP 2025-03-26**, permitindo que aplicações Dext exponham ferramentas, recursos e prompts para agentes de IA (como Claude Desktop e Claude Code).

- **Transportes Suportados** — `HTTP Streamable` (POST síncrono com sessões), `SSE` (Legado Server-Sent Events) e `Stdio`.
- **API RTTI Declarativa** — `TMCPToolProvider` com atributos `[MCPTool]`, `[MCPParam]`, `[MCPResource]` e `[MCPPrompt]` para registro de endpoints sem fricção.
- **API Builder Fluente** — Registro encadeado: `Server.Tool('nome').Description('...').OnCall(...)`.
- **Tipos de Conteúdo Ricos** — Suporte integrado para `TMCPContent` (Texto, Imagem, Áudio, Recursos Embutidos) e `TMCPToolResult` retornando múltiplos blocos e estados de erro.
- **Integração** — Roda nativamente sobre o `TWebHostBuilder` do Dext, permitindo que endpoints MCP e REST coexistam no mesmo processo sem bloqueio.
### 16.1 TMCPServer & TMCPServerBuilder
- **TMCPServerBuilder** — Builder fluente para configurar servidores MCP.
- **Seleção de Stack HTTP** — Escolha entre as stacks Indy e HTTP.sys.
- **Registro de Provedores** — Mapeamento automatizado de provedores customizados.
---

*Dext Framework 1.0 — Índice de Features. Revisão: setembro de 2026.*
