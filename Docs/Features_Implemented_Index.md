# Dext Framework 1.0 — Features Index

> **Lê em português?** O índice completo em português — a mesma cobertura, organizada do mesmo jeito — está em [Features_Implemented_Index.pt-br.md](Features_Implemented_Index.pt-br.md). Se o português for mais confortável, clique e leia o documento inteiro por lá.

Exhaustive master index of implemented features in **Dext 1.0**. Each item points at the implementation unit under `Sources/`.

Organized by module — Core, Web, ORM, Networking, Testing, and the rest of the ecosystem — so each capability lives in one canonical chapter.

> [!IMPORTANT]
> Source-audited. Unique bullets were kept; copy-paste duplicates were removed. Overlapping write-ups were merged.

**Next reads:** [Dext Book](Book/README.md) · [Compatibility matrix](Delphi_Compatibility_Matrix.md) · [.NET parity](Comparison/Feature_Comparison_Dext_vs_DotNet.md)

---

## Contents

1. [Core Foundation](#1-core-foundation) — DI, JSON, configuration, types, threading, jobs
2. [Collections](#2-collections) — lists, dictionaries, LINQ, SIMD, channels
3. [Web Framework](#3-web-framework) — Minimal APIs, Controllers, middleware, DataAPI, HTTP/2, SSR
4. [ORM & Entity](#4-orm--entity) — DbContext, queries, dialects, EntityDataSet
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

Dext was designed to leverage modern Object Pascal while keeping a documented compatibility floor. Implementation lives in `Sources\Core` and `Sources\Core\Base`.

### 1.0 Delphi Compatibility
- **Architectural minimum**: Delphi 2010 (Extended RTTI, Generics, Attributes).
- **Compile floor**: Delphi XE2 and higher, with Indy HTTP fallback below XE8 (`TDextIndyHttpEngine`).
- **Tier 1 (full)**: 10.4 Sydney, 11 Alexandria, 12 Athens — primary development and CI.
- **Tier 2 (supported)**: 10.1 Berlin – 10.3 Rio — no inline variables; backported sync primitives.
- **Web Stencils**: Delphi 12.2+ (Windows). Gated by `DEXT_ENABLE_WEB_STENCILS` in `Dext.inc`.

See the **[Delphi Compatibility Matrix](Delphi_Compatibility_Matrix.md)** for feature-by-feature compiler requirements.
### 1.1 Reflection Engine (`Dext.Core.Reflection`)
- **TReflection** — High-performance static facade for Delphi's RTTI system. Maintains a globally shared `TRttiContext`.
- **Metadata Cache** (`TTypeMetadata`) — Global cache of type metadata (properties, fields, attributes) with thread-safe initialization via `TMREWSync` (Multiple-Read Exclusive-Write). Hot-paths are lock-free.
- **Smart Properties** (`Prop<T>`, `Nullable<T>`, `Lazy<T>`) — Automatic detection of generic wrappers via `PTypeInfo.Name` analysis. The metadata cache stores `IsSmartProp`, `IsNullable`, `IsLazy`, `InnerType`, and direct pointer to the `FValue` field.
- **Property Path Resolution** — Recursive resolution of nested paths (e.g., `User.Address.Street`) via `TReflection.GetPropertyValue` with `TRttiProperty` caching per segment.
- **Custom Attribute Scanning** — `GetAttributes<T>` and `HasAttribute<T>` with scanning on fields, properties, and methods. Used by DI, Validation, JSON, and ORM.
- **Property Handlers** — `TPropertyHandler` for optimized property access with getter/setter caching.

### 1.2 Dependency Injection (`Dext.DI.Core`, `Dext.DI.Interfaces`, `Dext.DI.Attributes`)
- **TDextServices** — Fluent facade for service registration. Methods: `AddSingleton<T>`, `AddTransient<T>`, `AddScoped<T>`, `AddSingletonInstance<T>`, `AddSingletonFactory<T>`.
- **Interface/Implementation Mapping** — Complete decoupling between definitions and concrete logic.
- **TServiceCollection** — Internal repository of `TServiceDescriptor` with reverse search (LIFO) to allow registration overrides.
- **TDextServiceProvider** — IoC container with hybrid storage: `FSingletonInstances` (ARC/Interfaces) + `FSingletonObjects` (Non-ARC/Manual Classes) + `FScopedInstances`/`FScopedObjects` for scoping.
- **Lifecycles** — `Singleton` (global single instance), `Transient` (new instance per resolution), `Scoped` (single instance per DI scope via `CreateScope`).
- **Scope Isolation** — `IServiceScope` with `TDextServiceScope` creating an isolated child provider. Scope destruction releases all scoped objects.
- **Auto-Collections** — Automatic resolution of `IList<T>`, `IEnumerable<T>`, `IDictionary<K,V>` via `TActivator.IsListType`/`IsDictionaryType`.
- **DI Attributes** — `[Inject]` for property/field injection, `[ServiceConstructor]` for explicit constructor selection, overriding the Greedy strategy.

### 1.3 Object Activator (`Dext.Core.Activator`)
- **TActivator** — Central RTTI-based dynamic instantiation engine with 4 `CreateInstance` overloads:
  1. **Manual** — Explicit positional arguments.
  2. **Pure DI (Greedy Strategy)** — Selects the constructor with the MOST resolvable parameters from the container. Prioritizes the most derived class in case of a tie.
  3. **Hybrid** — Initial positional arguments + DI resolution for the rest.
  4. **PTypeInfo-based** — Instantiation by `PTypeInfo` (supports classes and interfaces, including auto-instantiation of collections).
- **[ServiceConstructor] Attribute** — First-pass priority over the Greedy strategy.
- **Constructor Cache** — Thread-safe cache (`TMREWSync`) of `TConstructorEntry` (method + `PTypeInfo` array of parameters) to avoid redundant RTTI scanning.
- **Field/Property Injection** — `InjectFields` processes `[Inject]` on fields and properties after construction, supporting custom `TargetTypeInfo`.
- **Default Implementation Registry** — `RegisterDefault(TBase, TImpl)` and `RegisterDefault<TService, TImpl>` for base→implementation mapping (e.g., `TStrings→TStringList`).

### 1.4 JSON Engine (`Dext.Json`, `Dext.Json.Types`)
- **TDextJson** — Static facade for serialization/deserialization with `Serialize<T>` and `Deserialize<T>`.
- **Driver Architecture** — Pluggable `IDextJsonProvider` (`DextJsonDataObjects` default, `System.JSON` alternative). Drivers implement `CreateObject`, `CreateArray`, `Parse`.
- **TJsonSettings (Fluent Record API)** — Immutable configuration via chaining: `.CamelCase`, `.SnakeCase`, `.PascalCase`, `.EnumAsString`, `.EnumAsNumber`, `.IgnoreNullValues`, `.CaseInsensitive`, `.ISODateFormat`, `.UnixTimestamp`, `.CustomDateFormat(fmt)`, `.ServiceProvider(p)`.
- **Automatic Casing** (`TCaseStyle`) — 5 modes: `CaseInherit`, `Unchanged`, `CamelCase`, `PascalCase`, `SnakeCase`. Automatically applied during serialization.
- **Enum Serialization** (`TEnumStyle`) — `AsNumber` (ordinal) or `AsString` (RTTI enum name).
- **Date Formats** (`TDateFormat`) — `ISO8601`, `UnixTimestamp`, `CustomFormat`. Default: `yyyy-mm-dd"T"hh:nn:ss.zzz`.
- **DOM Abstraction** — `IDextJsonNode`, `IDextJsonObject`, `IDextJsonArray` with strong typing (6 node types: Null, String, Number, Boolean, Object, Array).
- **TJsonBuilder** — Fluent builder for programmatic JSON construction without strings.
- **Attributes** — `[JsonName]` (rename field), `[JsonIgnore]` (exclude field), `[JsonCaseStyle]` (class-level override).
- **Architectural Profiles**:
  - **Dext DOM (IDextJsonNode)** — Optimized for 99% of use cases (REST APIs, Configs). High-speed random access and object manipulation via in-memory tree (DataObjects engine).
  - **Dext UTF-8 (Low-Level Streaming)** — Surgical tool for Big Data. Zero-allocation sequential processing of massive volumes (GBs) with constant memory footprint.
- **TUtf8JsonSerializer** (`Dext.Json.Utf8.Serializer`) — Zero-allocation record serializer. Operates directly on `TByteSpan` (raw UTF-8) without intermediate `string` conversion. `TJsonRecordInfo` caching per `PTypeInfo` to eliminate RTTI overhead in hot-paths. `ToUtf8JSON` in the `DextJsonDataObjects` driver for native UTF-8 output.
- **S54 Direct Codecs** — `Dext.Core.TypeModel`, `Dext.Core.DirectAccess`, `Dext.Codecs.Registry`, `Dext.Serialization.Protobuf`, `TDextJson`, ORM hydration, and the codecs CLI share field plans, enabling direct offset reads/writes, generated protobuf codec registration, static gRPC dispatch by invoker, nested object/list support with explicit ownership, SmartProp/Nullable edge cases, `TGUID`/`TUUID`, and `.proto` export from code-first DTOs. IDE Expert diagnostics are documented as deferred DX work.

### 1.5 Configuration System (`Dext.Configuration.*`)
- **TDextConfiguration (Fluent Builder)** — `.AddJsonFile(path)`, `.AddYamlFile(path)`, `.AddEnvironmentVariables(prefix)`, `.AddCommandLine(args, mappings)`, `.AddUserSecrets(secretsId)`, `.AddInMemoryCollection`.
- **TConfigurationRoot** — Multi-provider aggregator with LIFO precedence (last registered wins). Implements `IConfiguration`.
- **5-Layer Standard Precedence Pipeline** — (1) Base JSON/YAML $\rightarrow$ (2) Environment JSON/YAML $\rightarrow$ (3) User Secrets (Development only) $\rightarrow$ (4) OS Environment Variables $\rightarrow$ (5) Command-line Arguments (CLI).
- **CommandLine Configuration Provider** (`Dext.Configuration.CommandLine`) — High-performance argument parsing supporting `--Key=Value`, `/Key=Value`, space-delimited `--Key Value`, double-underscore mapping (`--Key__SubKey=Value` $\rightarrow$ `Key:SubKey`), boolean flags, and custom switch aliases dictionary (`-p` $\rightarrow$ `Server:Port`).
- **User Secrets Configuration Provider** (`Dext.Configuration.UserSecrets`) — Storage and isolation of development credentials outside git repository (`%APPDATA%\Dext\UserSecrets\<Id>\secrets.json` on Windows, `~/.dext/usersecrets/<Id>/secrets.json` on Linux/macOS).
- **Hierarchical Keys** — Access via `:` separator (e.g., `Database:ConnectionString`). `GetSection(key)` returns sub-tree.
- **Options Pattern** — `IOptions<T>` for typed binding of configuration sections to classes; optional validator callback on `Configure<T>`; **ValidateOnStart** (S68) eagerly resolves and validates during `TWebApplication.BuildServices` before the host listens (raises `EConfigurationException`).
- **Section Validators** — `AddSectionValidator(section, validator)` for startup configuration validation.
- **Change Tracking** — `IChangeToken` with `OnReload` callback for hot-reload configuration.

### 1.6 Type System (`Dext.Types.*`)
- **TUUID** (`Dext.Types.UUID`) — RFC 9562 compliant type with Big-Endian storage (Network Byte Order). `NewV4` (random), `NewV7` (time-ordered, 48-bit Unix timestamp ms + random). Implicit bidirectional conversion with `TGUID` (automatic endianness swap) and `string`. Operators `=` and `<>` via `CompareMem`. Compatible with PostgreSQL `uuid` and Web APIs.
- **Nullable\<T\>** (`Dext.Types.Nullable`) — Generic wrapper for nullable value types. `HasValue`, `Value`, `GetValueOrDefault`, `Clear`. Implicit operators: `T→Nullable<T>`, `Nullable<T>→T`, `Variant→Nullable<T>`, `Nullable<T>→Variant`. Comparison via `TEqualityComparer<T>.Default`. `TNullableHelper` for low-level access via raw `PTypeInfo` without generics.
- **Lazy\<T\>** (`Dext.Types.Lazy`) — Thread-safe lazy initialization via `TCriticalSection` (double-checked locking). `ILazy` and `ILazy<T>` interfaces. `TLazy<T>` (factory-based) and `TValueLazy<T>` (pre-computed). Implicit operators: `T→Lazy<T>`, `Lazy<T>→T`, `TFunc<T>→Lazy<T>`. Ownership management: `AOwnsValue` parameter controls if the value is destroyed with the lazy wrapper.

### 1.7 Smart Types & Expression Trees (`Dext.Core.SmartTypes`, `Dext.Specifications.*`)
- **TEntityType\<T\>** (`Dext.Entity.TypeSystem`) — Separate definition classes for queries. Allows separating data from metadata by working with pure POCOs, generating the same expression trees without embedding `Prop<T>` in the entity itself. Ideal for legacy systems or strict separation.
- **Prop\<T\>** (`Dext.Core.SmartTypes`) — Generic record operating in **dual mode**: (1) **Runtime Mode** — stores value `T` normally, (2) **Query Mode** — generates expression trees (`IExpression` / AST) automatically via operator overloading. The central pillar of Dext's **LINQ-like fluent DSL**.
- **BooleanExpression** — Hybrid record that can contain a literal `Boolean` OR an `IExpression` node (AST). Operators `and`, `or`, `not`, `xor` automatically generate `TLogicalExpression` nodes in query mode.
- **Type Aliases** — `StringType`, `IntType`, `Int64Type`, `BoolType`, `FloatType`, `CurrencyType`, `DateTimeType`, `DateType`, `TimeType` — semantic aliases for `Prop<T>` that make entities self-documenting.
- **Full Operator Overloading** — `=`, `<>`, `>`, `>=`, `<`, `<=`, `+`, `-`, `*`, `/`, unary negation — all generate `TBinaryExpression` with `boEqual`, `boGreaterThan`, etc., in query mode.
- **String Methods** — `Like`, `StartsWith`, `EndsWith`, `Contains` generate `TFunctionExpression` with the corresponding operation.
- **Collection Methods** — `In(values)`, `NotIn(values)`, `Between(lower, upper)`, `IsNull`, `IsNotNull`.
- **OrderBy** — `Prop.Asc` / `Prop.Desc` return `IOrderBy` for sorting composition.
- **IPropInfo** — Ported metadata carrying the physical column name, injected by `TPrototype`.
- **TQueryPredicate\<T\>** — `function(Arg: T): BooleanExpression` delegate used by the ORM as a query predicate.
- **Expression Tree Nodes** (`Dext.Specifications.Types`) — `TPropertyExpression`, `TLiteralExpression`, `TConstantExpression`, `TBinaryExpression`, `TLogicalExpression`, `TUnaryExpression`, `TFunctionExpression`, `TFluentExpression`.
- **Nullable\<T\> Interop** — Implicit bidirectional conversion between `Prop<T>` and `Nullable<T>`.
- **Variant Interop** — Implicit bidirectional conversion between `Prop<T>` and `Variant`.

### 1.8 Value Converter Engine (`Dext.Core.ValueConverters`)
- **TValueConverterRegistry** — Global converter registry with 3-level lookup: (1) Exact Match by `PTypeInfo` pair, (2) Kind Match by `TTypeKind` pair, (3) Fallback for `tkVariant` source.
- **TValueConverter** — Execution engine orchestrating conversions, with automatic handling of Smart Types (`Prop<T>`) and `Nullable<T>` (detected via `TReflection.GetMetadata`).
- **20+ Built-in Converters** — `Variant→Integer/String/Boolean/Float/DateTime/Date/Time/Enum/GUID/Class/TBytes/TUUID`, `Integer→Enum/String`, `String→GUID/TBytes/TUUID/Integer/Float/DateTime/Boolean`, `Float→String`, `Boolean→String`, `Class→Class`.
- **TBcd & ftFMTBcd First-Class Support** — Bidirectional zero-alloc converters: `TBcd` <-> `Currency`, `TBcd` <-> `Double`, `TBcd` <-> `string` (invariant), `TBcd` <-> `Integer/Int64`, `Variant` <-> `TBcd`, `String` <-> `TBcd`, `Float` <-> `TBcd`, `Currency` <-> `TBcd`. Provides end-to-end precision preservation for high-precision `NUMERIC`/`DECIMAL` database columns.
- **ConvertAndSet / ConvertAndSetField** — Conversion + assignment via RTTI in a single call (used by ORM and Model Binding).

### 1.9 Memory & Span (`Dext.Core.Span`, `Dext.Core.Memory`)
- **TSpan\<T\>** — Zero-allocation reference to a contiguous memory region. `Slice`, `ToArray`, `Clear`, `GetEnumerator` (for-in). Bounds checking on all accesses.
- **TVector\<T\>** — Efficient, growable stack-allocated vectors for high-speed buffer management.
- **TReadOnlySpan\<T\>** — Immutable version of `TSpan<T>`. Implicit operator `TSpan<T>→TReadOnlySpan<T>` and `TArray<T>→TReadOnlySpan<T>`.
- **TByteSpan** — Specialized span for bytes. `Equals` via `TDextSimd.EqualsBytes` (SIMD-accelerated). `EqualsString` compares with UTF-8 without allocation. `IndexOf`, `ToString` (UTF-8→string), `ToBytes`. Optimized for JSON/REST parsers and network protocols.
- **ILifetime\<T\>** (`Dext.Core.Memory`) — ARC wrapper for Non-ARC object lifecycle management. `TLifetime<T>` encapsulates an object and automatically releases it when the interface goes out of scope.
- **IDeferred / TDeferredAction** (`Dext.Core.Memory`) — Defer pattern (Go-inspired). Action executed automatically in the destructor when the interface goes out of scope. Useful for temporary resource cleanup.

### 1.10 Threading & Async (`Dext.Threading.*`)
- **TAsyncTask** — Fluent Async/Await implementation for asynchronous operations.
- **Work-Stealing Scheduler** — Efficient task distribution across CPU cores for maximum parallel performance.
- **ICancellationToken** — Cooperative cancellation with `WaitForCancellation(timeout)` and `IsCancellationRequested`. Integrated with Event Bus Lifecycle and Background Services.
- **Windows Processor Groups** — Native support for Windows machines with >64 logical cores. Automatically detects multiple processor groups and binds worker threads using `SetThreadGroupAffinity` to scale and balance workloads.
- **GetSystemLogicalProcessorCount** — Helper that queries system-wide processor topology across all groups on Windows (falling back to standard `CPUCount` on other platforms) to prevent under-provisioning of server IO workers.
- **Round-Robin Group Affinity** — Auto-allocator that distributes worker threads evenly across available NUMA nodes and processor groups.

### 1.11 Generic Object Pooling (`Dext.Collections.Pool`)
- **TDextPool\<T\>** — High-performance thread-safe generic object pool with `TSpinLock`, `ManualReset` event broadcast, atomic waiter tracking, and monotonic deadline timeouts (`AcquireTimeoutMs`).
- **Automatic Recycling (`IPoolable`)** — Automatic execution of `ResetState` upon object `Release` back to the pool.
- **Drain-Before-Free Protocol** — Atomic shutdown with broadcast (`FAvailableEvent.SetEvent`) and waiter drain waiting (`FActiveWaiters = 0`) preventing *use-after-free*.
- **MapFast HTTP Fallback 503** — Automatic `HTTP 503 Service Unavailable` response in `App.MapFast<TDbContext>` endpoints upon context pool exhaustion.

### 1.12 Logging Pipeline (`Dext.Logging`, `Dext.Logging.Sinks.APM`)
- **ILoggerFactory** — Factory for loggers with multiple provider registration. `CreateLogger(categoryName)` returns a composite `ILogger`.
- **ILogger** — Interface with methods per level: `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`. Structured template support with placeholders.
- **Aggregate Logger** — Each `ILogger` created by the factory aggregates all registered providers, dispatching every log entry to all simultaneously.
- **TBatchingTelemetrySink** — Base abstract asynchronous batching sink with queue buffering, thread-safe synchronization, and background thread execution.
- **TSeqLogSink** — Compact Log Event Format (CLEF) structured logger sink sending batches to Seq servers over HTTP.
- **TOTLPTelemetrySink** — OpenTelemetry (OTLP/HTTP JSON) telemetry sink for exporting Logs to OTel collectors (SigNoz, Datadog).
- **TTelemetrySinkRegistry** — Pluggable sink creator registry decoupling circular dependencies between package layers.
- **Fluent Logging Builders** — Startup extensions supporting `AddSeq()` and `AddOpenTelemetry()` with custom batching and service settings.

### 1.13 I/O Writers (`Dext.Core.Writers`)
- **IDextWriter** — Thread-safe abstraction for framework output. Implementations: `TConsoleWriter` (stdout), `TWindowsDebugWriter` (OutputDebugString with buffering), `TStringsWriter` (TStringList/TMemo), `TNullWriter` (silent).
- **SafeWrite / SafeWriteLn** (`Dext.Utils`) — Global functions routing output via the active `IDextWriter`. Automatic console detection. Native Unicode writing via `WriteConsoleW` (Windows) with UTF-8 fallback for pipes.
- **SafeAttachConsole** — Attach to parent process console (CMD/PowerShell) or `AllocConsole` for F5-executed GUI applications.

### 1.14 Text Escaping (`Dext.Text.Escaping`)
- **TDextEscaping** — Centralized text escaping utilities: `Html`, `Xml`, `Json` (manual character-by-character with `\uXXXX` support), `Url`. Used by Reporters, Serializers, and RestClient.

### 1.15 Date Utilities (`Dext.Core.DateUtils`)
- **TryParseISODateTime** — Robust ISO 8601 parser (`YYYY-MM-DDTHH:NN:SS.ZZZ`) with support for variations (separator `T` or space, optional milliseconds).
- **TryParseCommonDate** — Multi-format parser: ISO 8601 → `dd/mm/yyyy` → `mm/dd/yyyy` → `yyyy/mm/dd` with automatic format detection.

### 1.16 Resilience Pipeline (`Dext.Resilience`)
- **IResiliencePipeline / TResiliencePipeline** — Fluent record wrapper and interface exposing Polly-style policies. Synchronous and asynchronous generic/non-generic execution support (`Execute<T>` and `Execute`).
- **Retry Policy** (`TRetryPolicy`) — Handles transient failures with customizable retry count and backoff strategies (linear, exponential backoff with jitter).
- **Circuit Breaker Policy** (`TCircuitBreakerPolicy`) — Implements `Closed`, `Open`, and `Half-Open` states, failing fast and throwing `ECircuitBrokenException` once failure thresholds are exceeded.
- **Fallback Policy** (`TFallbackPolicy`) — Intercepts exceptions and returns fallback alternative values or executes fallback actions.
- **Timeout Policy** (`TTimeoutPolicy`) — Throws `ETimeoutException` when operations exceed set duration limits using cooperative task cancellation and asynchronous futures.
- **RestClient Integration** — `TRestClient` natively integrates with the resilience engine, enabling backwards-compatible `.Retry()` and `.Timeout()` methods, plus custom pipeline configuration.

### 1.17 Persistent Background Jobs (`Dext.BackgroundJobs.*`)
- **`IJobStorage`** — Decoupled storage abstraction supporting multiple providers.
- **`IJobClient` / `TDextJobs`** — Thread-safe enqueueing client and static utility facade (`TDextJobs.Enqueue<T>`, `TDextJobs.Schedule<T>`).
- **`TInMemoryJobStorage`** — Memory-only job storage provider designed for rapid local testing.
- **`TSqliteJobStorage`** — SQLite database job persistence provider using FireDAC, supporting automated schema creation and transactional safety.
- **`TJobServer` / `TBackgroundJobsService`** — Robust multi-threaded background worker engine running as an `IHostedService` (`TBackgroundService`), polling, locking, executing, and monitoring jobs.
- **`TJobSerializer`** — RTTI-based method parameter serializer using Dext JSON DOM to serialize and deserialize class method parameters (`TValue` arrays).

---

## 2. Collections

High-performance collections in `Sources\Core`. Binary Code Folding (`TRawList`) consolidates generic specializations into a single raw-memory engine (compile times down by up to 60%). CPU-friendly dictionaries (`TRawDictionary`, open addressing) are up to **6.6×** faster than RTL lookups; SIMD scans (`Dext.Collections.Simd`, AVX2/SSE2) up to **6.8×** on native lists.

### 2.1 Core Collections (`Dext.Collections`, `Dext.Collections.Base`, `Dext.Collections.OrderedDict`)
- **TRawList\<T\>** — Backbone of all collections. Generic list based on dynamic arrays with `Move`-based insertion/deletion to minimize overhead. `for-in` support via custom enumerator.
- **TList\<T\>** / **IList\<T\>** — High-performance generic list. Operations: `Add`, `Insert`, `Remove`, `IndexOf`, `Sort`, `BinarySearch`, `Contains`, `ToArray`.
- **TDictionary\<K,V\>** / **IDictionary\<K,V\>** — Generic hash map supporting `TryGetValue`, `AddOrSetValue`, `ContainsKey`, `Keys`, `Values`.
- **TOrderedDictionary\<K,V\>** / **IOrderedDictionary\<K,V\>** — Generic insertion-ordered hash map combining $O(1)$ key lookups with dense insertion-order iteration, positional indexing (`KeyAt`, `ValueAt`, `PairAt`, `IndexOf`), and `OwnsValues` object lifecycle management. Backed by `TRawOrderedDict` to prevent code bloat.
- **THashSet\<T\>** / **IHashSet\<T\>** — Set of unique values with set theory operations: `UnionWith`, `IntersectWith`, `ExceptWith`.
- **TCollections (Factory)** — Static factory: `CreateList<T>`, `CreateDictionary<K,V>`, `CreateOrderedDictionary<K,V>`, `CreateHashSet<T>`, `CreateSortedList<T>`, etc.
- **TSmartEnumerator\<T\>** — Extensible base enumerator for custom iteration in derived collections.

### 2.2 LINQ Extensions (`Dext.Collections.Extensions`)
- **Fluent Operations** — `Where`, `Select`, `OrderBy`, `OrderByDescending`, `First`, `FirstOrDefault`, `Last`, `Any`, `All`, `Count`, `Sum`, `Min`, `Max`, `Average`, `Distinct`, `Take`, `Skip`, `GroupBy`, `SelectMany`, `Aggregate`, `Contains`, `ToList`, `ToDictionary`, `ForEach`.

### 2.3 Concurrent Collections (`Dext.Collections.Concurrent`)
- **TConcurrentDictionary\<K,V\>** — Thread-safe dictionary with **Lock Striping** via `TSpinLock` array (multiple independent lock buckets to reduce contention).
- **TConcurrentQueue\<T\>** / **TConcurrentStack\<T\>** — Thread-safe queue and stack for producer/consumer scenarios.

### 2.4 Frozen Collections (`Dext.Collections.Frozen`)
- **TFrozenDictionary\<K,V\>** / **TFrozenSet\<T\>** — Immutable structures optimized for high-read scenarios (.NET 8 `FrozenDictionary` style). Once constructed, no modifications are allowed, enabling memory layout optimizations.

### 2.5 Channels (`Dext.Collections.Channels`)
- **TChannel\<T\>** — Go-style async communication primitive for Producer/Consumer pipelines.
- **Bounded Channel** — Fixed capacity with back-pressure (writer blocks when full).
- **Unbounded Channel** — Unlimited capacity (writer never blocks).
- **ChannelReader / ChannelWriter** — Segregated interfaces for reading and writing.

### 2.6 SIMD & Hardware Acceleration (`Dext.Collections.Simd`)
- **TDextSimd** — Vectorized operations with automatic instruction set detection:
  - `EqualsBytes` — Byte array comparison via **AVX2** (32 bytes/cycle), **SSE2** (16 bytes/cycle), or Pascal fallback.
  - `IndexOfByte` — Linear search accelerated via vector instructions.
  - `FillByte` / `MoveMem` — Optimized memory fill and copy.
- **Runtime Detection** — CPUID detection at startup. Automatic selection of the best available path.

### 2.7 Comparers & Algorithms (`Dext.Collections.Comparers`, `Dext.Collections.Algorithms`)
- **TEqualityComparer\<T\>** / **TComparer\<T\>** — Standard generic comparers supporting primitives, records, and classes.
- **Algorithms** — `Sort` (IntroSort), `BinarySearch`, `Reverse`, `Shuffle`.

---

## 3. Web Framework

### 3.1 Bootstrapping & Minimal API
- **TWebApplication** — Fluent facade for initialization: automatically loads `appsettings.json`, `appsettings.yaml`, Environment Variables, registers services, and builds the pipeline in a single chain.
- **Minimal API** — Direct handler registration via delegates without controllers (`app.MapGet`, `app.MapPost`, `app.MapQuery`).
- **FastPath** (`app.MapFast`) — High-throughput route handler bypassing DI Scope creation and RTTI activation for minimal latency and maximum RPS.
- **Data API Direct UTF-8 Streaming** (`Db.UseSql`) — Execution of native SQL queries with direct UTF-8 serialization and socket stream writing (`Res.GetOutputStream`) without intermediate `TJsonObject` heap allocations.
- **HTTP QUERY Mapping** — Safe, idempotent data retrieval endpoints utilizing structured request bodies.

### 3.2 Controllers (`Dext.Web.Controllers`, `Dext.Web.ControllerScanner`)
MVC-style, class-based endpoints discovered by RTTI — the counterpart to Minimal APIs when a domain grows past a handful of `MapGet` lambdas.

- **`[ApiController]` / `[ApiController('/prefix')]`** — Marks a class as a controller. Optional prefix on the attribute, or split `.NET`-style with `[Route('/api/users')]`.
- **Verb attributes** — `[HttpGet]`, `[HttpPost]`, `[HttpPut]`, `[HttpPatch]`, `[HttpDelete]`, `[HttpHead]`, `[HttpOptions]`, `[HttpQuery]`. Parameter routes **must** start with `/` (e.g. `[HttpGet('/{id}')]`).
- **`AddControllers` + `MapControllers`** — `TControllerScanner` finds `[ApiController]` types, registers them in DI, and maps actions before Swagger.
- **Constructor injection** — Services resolved by the DI container (`IUserService`, `ILogger`, `TDbContext`, …).
- **`IResult` actions** — `Results.Ok`, `Created`, `Accepted`, `NoContent`, `BadRequest`, `NotFound`, `ValidationProblem`, `StatusCode`, `Json<T>`.
- **Do not name an action `Create`** — Conflicts with Delphi constructors (`E2254`). Use `CreateUser`, `CreateOrder`, etc.

### 3.3 Middleware Pipeline
- **Chain of Responsibility** — Functional (anonymous delegates) and class-based middlewares with DI constructor injection.
- **Built-in Middlewares**:
  - **HTTP Logging (`THttpLoggingMiddleware`)** — Request/response logging with configurable case-insensitive redaction (`RedactHeaders`) for sensitive headers (`Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`).
  - **Exception Handling (`TExceptionHandlerMiddleware`)** — Global exception handling adhering to **RFC 9457** (Problem Details, obsoleting RFC 7807), UUIDv7 `TraceId` correlation fallback, and environment-driven `E.Message` sanitization on status 500 errors in Production mode. Domain rule violations via **`EDomainException` / `EDomainValidationException`** map to **HTTP 422** with `type` `https://dext.dev/errors/domain-validation` (S68).
  - **DeveloperExceptionPage (`TDeveloperExceptionPageMiddleware`)** — Rich exception page and stack trace viewer for development mode.
  - **CORS (`TCorsMiddleware`)** — Strict CORS preflight checking (`OPTIONS` with `Origin` and `Access-Control-Request-Method`), allowlist validation for Origin, Method, and Headers returning `403 Forbidden` on invalid preflights, startup fail-fast against `AllowAnyOrigin + AllowCredentials`, and clean `Vary: Origin` header merging.
  - **Rate Limiting (`TRateLimitMiddleware`)** — Traffic control emitting standard **RFC 9333** headers (`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, `Retry-After`) on both allowed and HTTP 429 rejected requests.
  - **Response Caching (`TResponseCacheMiddleware`)** — Server-side HTTP response caching with strict protection against caching authenticated requests (`Authorization`, session/auth cookies), rejection of responses with `Set-Cookie` or `private`/`no-store`/`no-cache` directives, and automatic reconstruction of `Cache-Control: public, max-age=N` headers on cache HITs.
  - **Compression (`TCompressionMiddleware`)** — Response compression via GZip.
  - **Security Headers (`TSecurityHeadersMiddleware`)** — Injection of HSTS, `X-Content-Type-Options`, `X-Frame-Options`, and `X-XSS-Protection`.
  - **Feature Flags (`Dext.FeatureFlags`)** — `IFeatureManager` / `TFeatureManager` reads `FeatureManagement:*` live from configuration; host enables JSON/YAML **ReloadOnChange**; `TFeatureConfiguration.Reload` forces `IConfigurationRoot.Reload` (S68). Boolean flags, `TPercentageFilter` (deterministic rollout per user/tenant key), `TTimeWindowFilter` (ISO-8601 window), custom `IFeatureFilter`, and `[FeatureGate('FeatureName')]`.
  - **Forwarded Headers (`TForwardedHeadersMiddleware`)** — Zero-Trust processing of `X-Forwarded-For`, `X-Forwarded-Proto`, and `X-Forwarded-Host` from trusted reverse proxies (NGINX, Caddy, Cloudflare, Traefik), with `KnownProxies`, CIDR subnets, and hop limits against IP spoofing.
  - **Antiforgery CSRF (`IAntiforgery`)** — HMAC-SHA256 tokens, constant-time comparison, Origin/Host validation, Double Submit Cookie, and `X-CSRF-TOKEN` / `X-XSRF-TOKEN` (SSR forms and HTMX).
  - **Base Path Hosting (`UsePathBase`)** — Support for serving under path prefixes (`app.UsePathBase('/myapp')`), engine-agnostic path stripping (`TDextPathBaseMiddleware`), `Request.PathBase` population, and app-relative URL builder (`Request.ToAppUrl('/route')`). Native HTTP.sys kernel prefix registration (`http://+:8080/myapp/`).

### 3.4 Routing Engine
- **Dynamic Parameters** — Routes with `{id}`, `{slug}`, and type constraints.
- **API Versioning** — `THeaderApiVersionReader`, `TQueryStringApiVersionReader`, `TPathApiVersionReader`, `TCompositeApiVersionReader` (composite strategy).
- **HTTP QUERY Discovery** — Automatic `OPTIONS` routing generating standard `Allow` and `Accept-Query` headers carrying configured query media types (e.g. `application/jsonpath`).
- **Radix Tree (Trie) Routing Matching** — Path segment route scanning replaced with an optimized `TRouteNode` tree structure, achieving $O(L)$ path matching complexity (where $L$ is path segment depth) and deterministic route resolution.
- **Backtracking Segment Traversal** — Fully supports literal matching, path parameters (`{param}`), and wildcard parameters with segment-by-segment backtracking to resolve overlaps.
- **Zero-Allocation Request Metadata Mapping** — Bypasses RTTI-heavy dynamic wrapping (eliminating dictionary and `TValue` heap allocations) by directly exposing and assigning `EndpointMetadata` via `IHttpContext` properties on matched routes.

### 3.5 Model Binding
- **Hybrid Binding** — `[FromBody]`, `[FromQuery]`, `[FromRoute]`, `[FromHeader]`, `[FromServices]` attributes.
- **Zero-Allocation** — Direct UTF-8 deserialization to records and classes via `TByteSpan`.
- **Multipart/Form-Data** — Upload processing via `IFormFile` abstraction.
- **Object Lifecycle Management** — Tracking of objects created by Model Binding with integration to ORM **ChangeTracker** for automatic ownership transfer.
- **Binding Problem Details (S68)** — Conversion failures return **HTTP 400** with `application/problem+json` (`Results.BindingProblem` / RFC 9457: `type`, `title`, `status`, `detail`, `instance`).
- **Auto-Validation Problem Details (S68)** — Failed attribute/fluent validation in `THandlerInvoker` emits `Results.ValidationProblem` (`application/problem+json` with `errors` map).
- **Results.Accepted (S68)** — Semantic **HTTP 202** factory with optional `Location` header (mirrors `Created`).
- **Results.UnsupportedMediaType (S68 P2-05 partial)** — Semantic **HTTP 415** factory for application-level media rejection (e.g. upload extension checks).
- **Content Negotiation** — `IOutputFormatter` / `IOutputFormatterSelector` / `AddContentNegotiation`. Honors `Accept` (JSON formatter built-in; pluggable formatters for additional media types).

### 3.6 Hosting & Native Server
- **IWebHost / IWebHostBuilder** — Hosting abstractions. Support for **Dynamic Ports (Port 0)** with automatic OS assignment.
- **Server Adapters** — Indy (default, OpenSSL/Taurus SSL), **WebBroker Adapter** (ISAPI/CGI for IIS/Apache), **DCS Adapter** (Delphi-Cross-Socket, non-blocking), and **Native Server Engine** (kernel-mode `http.sys` on Windows and non-blocking `epoll` sockets on Linux).
- **Zero-Allocation HTTP Parser** (`TDextIocpHttpParser`) — Incremental parsing of HTTP/1.1 request headers directly from network buffers without intermediate heap allocations.
- **IHostedService** — Background tasks with `StartAsync`/`StopAsync`. `TBackgroundService` with `Execute(ICancellationToken)`.
- **IHostApplicationLifetime** — Tokens for `ApplicationStarted`, `ApplicationStopping`, `ApplicationStopped`.
- **`ServerEngineOptions`** (`Dext.Server.Engine.Types.pas`) — Global entry function and fluent helpers (`WithHttps`, `WithSslCertHash`, `WithIoThreads`, `WithReceiveBufferSize`) for clean, zero-boilerplate HTTPS server setup.
- **`TRestClient.IgnoreCertificateErrors / AllowSelfSigned`** (`Dext.Net.RestClient.pas`) — Fluent API for explicit SSL/TLS certificate validation control in REST clients, enabling HTTPS connections with self-signed development certificates.

#### Linux Epoll Engine (S50)

- **Thread Core Affinity (CPU Pinning)**: Auto-binding of I/O worker threads (`TDextEpollWorker`) to dedicated CPU cores via `pthread_setaffinity_np` to avoid scheduler migration overhead and maximize cache locality.
- **Kernel-level Pre-acceptance Optimization**: Implements socket-level `TCP_DEFER_ACCEPT` to postpone worker wake-ups until incoming payload arrives, and `TCP_FASTOPEN` (TFO) to support payload transmission in the initial SYN packet.
- **Zero-Copy File Transmission (sendfile)**: Integrated support for direct file streaming using the non-blocking kernel `sendfile` system call, bypassing user-space copy buffers.
- **Context Allocation Pooling**: Features a lock-free, thread-safe pre-allocated connection context pool (`TDextEpollContext`) to completely avoid heap fragmentation during highly concurrent connection spikes.
- **Active Keep-Alive Sweep**: High-efficiency background sweep monitoring connection activity timestamps, automatically terminating idle descriptors (>15 seconds) under descriptor pressure, coupled with `SO_LINGER` socket teardown.

### 3.7 Security, Identity & Authorization (S06)
- **IClaimsPrincipal** — JWT, Basic Auth (RFC 7617), and Cookie authentication.
- **Rate Limiting** — Fixed Window, Sliding Window, Token Bucket, Concurrency Limiter.
Dext features a native, high-performance security and identity engine based on industry standards (JWT, OAuth2, and OpenID Connect) to guarantee enterprise-level compliance and safety.

### 3.7.1 Cryptographic Engine and JWT Validation (`Dext.Auth.JWT`)
- **TJwtTokenHandler** — Full-featured JSON Web Token (JWT) manager with native support for HS256 signatures and RS256 asymmetric validation.
- **Windows CNG Integration** — High-performance validation and signing dynamically leveraging Windows Native Cryptography APIs (`bcrypt.dll`), with a transparent fallback to `System.Hash` (Delphi XE8+) or Indy/OpenSSL for maximum compatibility across versions.
- **Optimized Parsing** — Structured parsing of JWT tokens using fast string indexers (`IndexOf`) and memory spans (`TByteSpan`), avoiding heap allocations.
- **Claims Handling** — Flexible claim records (`TClaim`) and a fluent identity builder (`TClaimsBuilder`).

### 3.7.2 JWT Authentication Middleware (`Dext.Auth.Middleware`)
- **TJwtAuthenticationMiddleware** — HTTP pipeline middleware that extracts tokens from the `Authorization: Bearer` header, validates signatures, expiration times (`exp`), issuer (`iss`), and audience (`aud`), then injects the claims principal (`IClaimsPrincipal`) directly into the request context (`IHttpContext.User`).

### 3.7.3 Declarative and Policy-Based Authorization (`Dext.Auth.Attributes`, `Dext.Auth.Identity`)
- **Authorization Attributes** — `[Authorize]`, `[AuthorizePolicy]`, and `[AllowAnonymous]` for declarative protection of controllers and actions (`[Authorize('Admin')]` for roles/schemes; `[AuthorizePolicy('Name')]` for named policies — Delphi has no attribute named arguments).
- **Role Validation** — Role-based access control evaluated dynamically inside the route execution and controller scanning dispatch flow.
- **Policy Engine** — Runtime registration and evaluation of complex custom policies through the `TAuthorizationPolicyRegistry` (e.g., minimum age requirements or custom scope checks).

### 3.7.4 External Identity Providers (OIDC)
- **Plug-and-Play Methods** — Middleware extensions for out-of-the-box configuration of third-party identity providers via OIDC: `UseGoogleAuthentication`, `UseEntraIdAuthentication` (Azure AD), and `UseKeycloakAuthentication`.

### 3.8 Real-time, Caching & Health
- **SSE (Server-Sent Events)** — Unidirectional event streaming fallback.
- **WebSockets & SignalR Hubs** — Native autonomous WebSockets (RFC 6455) and Dext Hubs engine:
  - **Protocol Engine (`Dext.WebSocket.Protocol.pas`)**: RFC 6455 framing processing (`wsText`, `wsBinary`, `wsPing`, `wsPong`, `wsClose`), vectorized masking/unmasking, 64-bit payload, and integrity validation.
  - **Handshake Engine (`Dext.WebSocket.Handshake.pas`)**: HTTP `101 Switching Protocols` upgrade validation, SHA-1/Base64 `Sec-WebSocket-Accept` computation.
  - **Permessage-Deflate (`Dext.WebSocket.Compression.pas`)**: Negotiation and **RFC 7692** compression via native ZLib (up to 80% payload reduction).
  - **Hubs Transport (`Dext.Web.Hubs.Transport.WebSocket.pas`)**: Full integration with `Dext.Web.Hubs` for bi-directional real-time messaging, group dispatching (`IHubClients`), automatic reconnection, and ping/pong heartbeats.
  - **Cross-Platform I/O**: Runs over raw sockets with **`epoll` on Linux** and `WSAPoll` / `IOCP` on Windows.
- **Delphi Hub Client (SignalR-compatible)** — Native, high-performance Delphi client library (`Dext.Web.Hubs.Client`) supporting WebSocket and SSE transports, automated negotiate/handshake protocols, ping heartbeats, and thread-safe callbacks with optional main UI thread marshaling.
- **Caching** — In-Memory caching engine, and native Redis cache engine (`TRedisCacheStore`). Generates unique cache keys for HTTP QUERY requests by computing a `THashSHA1` hash of the query request body stream. Support for native response cache registration via `.UseRedisCache` in `TAppBuilder`. **Health Checks** with probes `/health`, `/health/live` (liveness), and `/health/ready` (readiness) via `THealthCheckMiddleware` / `THealthCheckOptions` (S68).

### 3.9 API Documentation & Scaffolding
- **OpenAPI / Swagger** — Automatic specification generation.
- **Auto-Migrations (S11)** — Automatic schema synchronization during startup with table/column rename detection via attributes.
- **View Engine & WebStencils (S09)** — AST-based template engine (Razor-style), zero-dependency.

### 3.10 Database as API (`Dext.Web.DataApi`)
One of Dext's most powerful features: **automatic generation of full REST APIs from ORM entities — with a single line of code**. Not a scaffold that generates code — it's a runtime handler mapping entities to endpoints dynamically.

#### Registration (3 coexisting modes)
- **Automatic by Attribute** — `[DataApi]` on the entity + `App.MapDataApis` at startup. `TDataApi.MapAll` scans RTTI and registers all decorated entities automatically.
- **Typed Manual** — `TDataApiHandler<TProduct>.Map(App, '/api/products')`.
- **Fluent Manual** — `App.Builder.MapDataApi<T>(path, DataApiOptions.AllowRead.RequireAuth)`.

#### 5 Generated CRUD Endpoints
| Method | Route | Handler |
|---|---|---|
| `GET` | `/api/{entity}` | `HandleGetList` — List with pagination, sorting, and filters |
| `GET` | `/api/{entity}/{id}` | `HandleGet` — PK lookup (simple or composite) |
| `POST` | `/api/{entity}` | `HandlePost` — Creates new record, returns 201 |
| `PUT` | `/api/{entity}/{id}` | `HandlePut` — Updates existing record |
| `DELETE` | `/api/{entity}/{id}` | `HandleDelete` — Removes record |

#### Dynamic Specification Mapping (QueryString Filters)
- **11 Operators** automatically parsed from URL: `_eq`, `_neq`, `_gt`, `_gte`, `_lt`, `_lte`, `_cont` (LIKE %x%), `_sw` (LIKE x%), `_ew` (LIKE %x), `_in` (IN), `_null` (IS NULL).
- **Pagination** — `?_limit=20&_offset=40` with **MaxPageSize** cap (default 100; fluent `.MaxPageSize(N)`, `0` disables) — S68.
- **Sorting** — `?_orderby=price desc,name asc`.
- **Name Resolution** — `ResolvePropertyName` via `TReflection.GetMetadata().GetHandlerBySnakeCase` to convert URL snake_case to Delphi property PascalCase.
- Each filter generates an `IExpression` via `TStringExpressionParser.Parse` and is injected into the `ISpecification` — the same AST used by Smart Properties.

#### TDataApiOptions — Fluent Configuration API
- **Security** — `RequireAuth`, `RequireRole(roles)`, `RequireReadRole(roles)`, `RequireWriteRole(roles)` — Read/write permission separation with integrated JWT validation via `IClaimsPrincipal`.
- **Allowed Methods** — `Allow([amGet, amGetList])` restricts which endpoints are generated.
- **Multi-Tenancy** — `RequireTenant` for tenant isolation.
- **Naming Strategy** — `UseSnakeCase`, `UseCamelCase` for serialization casing control.
- **Enum Style** — `EnumsAsStrings`, `EnumsAsNumbers`.
- **Explicit DbContext** — `DbContext<TMyContext>` to select which context to use.
- **Custom SQL** — `UseSql('SELECT ...')` for custom queries.
- **Swagger** — `UseSwagger`, `Tag('Products')`, `Description('...')` for automatic documentation.

#### Naming Conventions (`TDataApiNaming`)
- **Auto-Discovery** — `T` prefix automatically removed via `TReflection.NormalizeFieldName`.
- **Pluralization** — English: `y→ies`, `ch/sh/x/s→es`, default `→s` (e.g., `TCategory` → `/api/category`).
- **Custom Routes** — `[DataApi('/my/path')]` overrides conventions.
- **Case Mapping** — Delphi property `PascalCase` → URL `snake_case` for filters.

#### Entity ID Resolver (`TEntityIdResolver`)
- **Automatic PK Type Resolution** — Delegates to `IModelBinder` for transparent conversion: Integer, String, TUUID, TGUID.
- **Composite Keys** — `|` separator for composite keys (e.g., `/api/entity/1|ABC`).

#### Ecosystem Integration
- **DI Scope** — `GetDbContext` resolves `TDbContext` from the DI container (supports multiple contexts via `ContextClass`).
- **Telemetry** — `TDiagnosticSource.Write('DataApi.ModelBinding.Start/Complete')` emits traceable events.
- **Logging** — All handlers emit logs via `Log.Debug`/`Log.Error` with structured templates.
- **Serialization** — `TDextJson.Deserialize` + `TDextSerializer` with per-endpoint configurable settings.
- **Swagger** — Registered endpoints automatically appear in OpenAPI documentation.
- **`[DataApiIgnore]`** — Attribute to exclude specific entities from automatic scanning.

### 3.11 SSR, HTMX & View Engines
### 3.11.1 HTMX Integration
- **Auto-Detection** — The pipeline automatically detects `HX-Request` headers and **suppresses the global layout** on compatible endpoints.
- **Partial Rendering** — `Results.View<T>('fragment', Query).WithLayout('')` for partial fragment rendering without layout.
- **HTMX 4 Request Inspection** — `Htmx.Request(Context)` reads `HX-Request-Type` (`partial` / `full`) plus source, target, current URL, boosted, and history-restore headers.
- **HTMX 4 Multi-Target Partials** — `Htmx.Partials.Target(...).Id(...).AsResult` builds `<hx-partial>` responses without manual lifetime management.
- **Full-Stack SPA Feel** — Combines server-side SSR with dynamic HTMX swapping for highly responsive apps without heavy JavaScript.

### 3.11.2 Flyweight Iterators (Streaming SSR)
- **O(1) Memory** — `TStreamingViewIterator<T>` iterates on demand during template `@foreach`. 10.000 records rendered using memory equivalent to **a single object**.
- **No `ToList`** — Pass `Db.Customers.QueryAll` directly to `Results.View<T>('customers', Query)` and the framework automatically engages streaming.
- **Smart Properties in Templates** — `@(Prop(item.Name))` for automatic `Prop<T>` unwrapping inside HTML templates.

### 3.11.3 Web Stencils (Delphi 12.2+)
- **Native Provider** — `Services.AddWebStencils(...)` with entity whitelisting via `TWebStencilsProcessor.Whitelist.Configure`.
- **Agnostic** — Same `IViewEngine` interface for Dext Template Engine and Web Stencils; switch without changing code.

### 3.12 HTTP/2 Framing & HPACK (S41)
- **THpackDecoder & THpackEncoder** — HPACK header compressor (RFC 7541). Includes support for the 61-entry static table, dynamic table ring-buffer with FIFO size-bound eviction, and client Huffman decoding via FSM.
- **TDextHttp2FrameCodec** — Complete parser and serializer for all 10 HTTP/2 frame types. Zero-allocation parsing via `TByteSpan` and direct buffer writers.
- **TDextHttp2StreamMap** — Sorted active streams map using binary search for $O(\log n)$ lookup performance. Handles stream-level state machine transitions and flow-control.
- **TDextHttp2Connection** — HTTP/2 connection state machine coordinating preface validation, SETTINGS exchange, and frame demultiplexing.
- **gRPC Compatibility Layer** — Length-prefixed message unpacking/packing and trailers support to serve as the transport layer for gRPC (S02).

---

## 4. ORM & Entity

### 4.1 Core Persistence
- **TDbContext** — Unit of Work with automatic **Change Tracking** (states: Added, Modified, Deleted, Unchanged). **Identity Map** for instance uniqueness by primary key.
- **DbSet\<T\>** — Generic repository. Operations: `Add`, `Update`, `Remove`, `Find`, `FirstOrDefault`, `Where`, `Include`, `ToList`.
- **SaveChanges** — Persists all tracked changes in a transaction.
- **Fluent Connection Setup & Pooling Auto-Detection** — Connection builders (`UsePostgreSQL`, `UseFirebird`, etc.) support automatic parameter extraction and synchronization with property setters, resolving empty-options/pooling bugs.
- **ConnectionDefName Support (FireDAC)** — Direct support for FireDAC connection definition names (`UseConnectionDef`). Automatically queries `FDManager.ConnectionDefs` to resolve the database dialect, driver ID, and pooling configuration dynamically.
- **Shadow Properties Support** — Declares columns (like `TenantId`, `CreatedAt`, `IsDeleted`) in database mappings that are tracked and saved without needing to be exposed as physical fields in class declarations.

### 4.2 Query Engine (LINQ-like)
- Fluent queries with **Projection (Select)** (`Select(array of string)`, typed property projections), preserving server-side specifications, **Paging** (`Skip`/`Take`), and **Aggregates** (`Count`, `Sum`, `Max`, `Min`, `Average`).
- **SQL Cache** — Reuse of generated SQL commands for repeated queries.
- **Strongly-Typed Fluent Joins** (`JoinInner`, `JoinLeft`, `JoinRight`, `JoinFull`, `JoinCross`) — Compiles directly into optimized database-level joins (INNER, LEFT, RIGHT, FULL, CROSS) using explicit condition expressions, implicit auto-resolution via relations metadata (`TModelBuilder`), or Cross Join Cartesian product execution.
- **Pessimistic Locking** — `FOR UPDATE` for concurrency control.
- **Multi-Mapping** (Dapper-style) — Recursive hydration via `[Nested]` attribute.
- **Fluent Validation Integration** — Integrates with validation engine inside `SaveChanges` to run automatic object verification before executing commits.

### 4.3 Specification Pattern (`Dext.Specifications`)
- **Fluent Specification Builder** — `Where`, `OrderBy`, `Include`, `Take`, `Skip` for decoupled and reusable business rules.
- **TExpressionEvaluator** (`Dext.Specifications.Evaluator`) — **In-memory** evaluator for the same AST used by the SQL Compiler. Evaluates `IExpression` against objects (`TObject`) or dictionaries (`TDictionary<string, Variant>`). Supports: comparisons (`=`, `<>`, `>`, `>=`, `<`, `<=`), `LIKE` (case-insensitive with `%`), `IN`/`NOT IN`, `IS NULL`/`IS NOT NULL`, bitwise operations (`AND`/`OR`/`XOR`), arithmetic (`+`, `-`, `*`, `/`, `mod`, `div`), and `AND`/`OR` short-circuiting. Automatically **unwraps `Prop<T>`** (Smart Types) via RTTI.
- **TStringExpressionParser** (`Dext.Specifications.Parser`) — Parser converting `"Field Operator Value"` strings into `IExpression` nodes. Automatic type conversion: Boolean, Float (invariant), Integer, String. Used internally by **Database as API** to transform QueryString filters into expression trees.
- **IExpressionVisitor** — Visitor pattern for traversing the expression tree, used by both the SQL Compiler (generating SQL) and the Evaluator (in-memory filtering).

### 4.4 Relationships & Loading
- **One-to-One**, **One-to-Many**, **Many-to-Many**.
- **Lazy Loading** via Proxy Objects (transparent interception).
- **Eager Loading** — `Include`/`ThenInclude` for graph pre-loading.
- **Split Queries Loading** — Collection navigation properties loaded via dedicated SQL queries using `IN` bounds parameters to avoid cartesian join explosion.

### 4.5 Migrations System
- Automated Code-First evolution with chronological database model snapshots.

### 4.6 Dialect Support (Polyglot)
- PostgreSQL, SQL Server, MySQL, SQLite, Oracle, Firebird, InterBase.
- **Legacy Paging** — Automatic wrapping for `ROWNUM` in older Oracle/SQL Server versions.
- **Oracle Driver (`TOracleDialect`)** — Native support for Oracle OCI via FireDAC:
  - Identity column definitions (`GENERATED BY DEFAULT AS IDENTITY`).
  - Native `RETURNING "ID" INTO :RET_VAL` syntax for high-performance auto-generated PK retrieval.
  - Automatic `ROWNUM` multi-level wrapper paging for legacy and modern Oracle versions.
  - Precise type mapping: `NUMBER(1,0)` $\rightarrow$ `Boolean`/`BoolType`, `NUMBER(4,0)` $\rightarrow$ `SmallInt`/`Int16Type`, `NUMBER(9,0)` $\rightarrow$ `Integer`/`IntType`, `NUMBER(18,0)` $\rightarrow$ `Int64`/`Int64Type`, `NUMBER(p, s)` $\rightarrow$ `Currency`/`Double`, `DATE` $\rightarrow$ `TDateTime` (protects time component), `RAW(16)` $\rightarrow$ `TGUID`/`GuidType`, and `JSON` column mapping.

### 4.7 Soft Delete (`[SoftDelete]`)
- **Declarative Attribute** — `[SoftDelete('IsDeleted')]` transforms `Remove()` into an automatic `UPDATE`.
- **Custom Values** — `[SoftDelete('Status', 99, 0)]` for integers/enums.
- **HardDelete** — `Db.Tasks.HardDelete(Task)` for physical deletion.
- **Restore** — `Db.Tasks.Restore(Task)` to restore soft-deleted records.
- **Automatic Query Filters** — Deleted records are **invisible** by default. `IgnoreQueryFilters` to see everything, `OnlyDeleted` for the trash bin.
- **Timestamp Soft Delete** (`[DeletedAt]`) — Automatically converts `Remove()` into an update setting the current timestamp, and generates `IS NULL` filters for active records (Issue #121).
- **IdentityMap Cleanup** — Soft-deleted entities are removed from the memory cache after `SaveChanges`.

### 4.8 JSON/JSONB Column Queries (`[JsonColumn]`)
- **`[JsonColumn]` Attribute** — Marks string properties as JSON columns. `[JsonColumn(True)]` for JSONB in PostgreSQL.
- **Fluent Query** — `.Json('path')` to query properties inside JSON columns: `Prop('Settings').Json('role') = 'admin'`.
- **Nested Properties** — `Prop('Settings').Json('profile.details.level') = 5` using dot notation.
- **IS NULL** — `Prop('Settings').Json('nonexistent').IsNull` for missing keys.
- **Cross-Database** — PostgreSQL (`#>>` / indexed JSONB), MySQL (`JSON_EXTRACT` / `JSON_UNQUOTE`), SQLite (`json_extract` + JSON1), SQL Server (`JSON_VALUE`).
- **INSERT with Cast** — Automatic `::jsonb` in PostgreSQL for `[JsonColumn(True)]`.

### 4.9 Dialect-Aware Batch Operations (`Dext.Entity.BatchStrategy`) — Spec S59
- **TDextBatchStrategyFactory** — Dynamic selection of batch `UPDATE` and `DELETE` strategies based on `TDatabaseDialect`.
- **PostgreSQL Strategy** (`TDextPostgresBatchStrategy`) — Rewrites batch `UPDATE` into a single-statement `UPDATE table AS t SET ... FROM (VALUES (...), (...)) AS v(...) WHERE t.pk = v.pk` and batch deletes into `WHERE (pk1, pk2) IN (...)`.
- **MySQL / MariaDB Strategy** (`TDextMySqlBatchStrategy`) — Rewrites batch `UPDATE` into a single-statement `UPDATE table SET col = CASE WHEN pk = x THEN y END WHERE pk IN (...)`.
- **Native Array DML Strategy** (`TDextNativeArrayDmlStrategy`) — Preserves native protocol array binding for Oracle OCI (`OCIStmtExecute` delivering 17x bulk performance gain) and Firebird 4+.
- **Performance** — Eliminates FireDAC sequential Array DML emulation bottleneck on PostgreSQL and MySQL, reducing per-record latency from ~650 µs to ~118 µs, while unlocking true native vector execution on Oracle.

### 4.10 EntityDataSet (`Dext.Data.EntityDataSet`)
- **ORM ↔ VCL/FMX Bridge** — Connects components (DBGrid, FastReport) to `TList<T>` POCO collections while preserving a clean architecture.
- **Zero-Allocation Memory** — Access via `TEntityMap` mapped memory offsets eliminates RTTI or string copying on every record read.
- **`LoadFromUtf8Json`** — Direct loading from JSON streams/buffers via `TByteSpan` without prior encoding conversion.
- **Automatic Setup (AST Parsing)** — In design-time, "Sync Fields" and "Refresh Entity" *Verbs* directly parse `.pas` units and create `TFields` dynamically **without needing to compile the project**.
- **Live Data Preview (Hybrid)** — IDE magic: by providing a `TFDConnection` and a `DataProvider`, Dext **generates dynamic SQL** and displays real data in the Grid during development. In *runtime*, this SQL is completely ignored, and the component consumes only the injected collections.
- **Expression Filtering** — `DataSet.Filter := 'Score > 100'` supported using the same `TExpressionEvaluator` as the in-memory framework.
- **Auto-Stabilization** — The `Active` property is never serialized as `True` in the DFM; prevents missing instance errors at runtime.
- **DML Memory Mode** — `Append`, `Edit`, `Post`, and `Delete` operations natively manipulate the underlying in-memory list.

### 4.11 Inheritance Mapping
- **TPH (Table-Per-Hierarchy)** — Automatic polymorphic hydration based on discriminators via attributes.

### 4.12 Advanced Features
- **Streaming Iterators** (Flyweight pattern) — O(1) memory for rendering large volumes in SSR views. `TStreamingViewIterator<T>` iterates on demand during template `@foreach`.
- Automatic converters for GUID, Enums, JSONB, and UUID v7.
- **Stored Procedures** — Declarative execution via `[StoredProcedure]` and `[DbParam]`.
- **Multi-Tenancy** — Shared Database (TenantId), Schema Isolation (`search_path`), Tenant per Database.
- **Bulk / Batch Operations** — High-performance batch APIs: `AddRange`, `UpdateRange`, and `RemoveRange` supporting raw generic collections (`TArray<T>`, `IEnumerable<T>`) for bulk database operations in a single context transaction, featuring configurable automatic chunking (defaulting to 100 records, customizable via `WithBulkBatchSize` in `TDbContextOptions`) to optimize network packets and satisfy parameter limit boundaries of DB drivers (e.g. FireDAC).
- **Database Sequence Generators & HiLo** (`Dext.Entity.Sequences`) — Declarative mapping of sequences via `[Sequence('name', allocationSize)]` attribute or fluent `UseSequence`. Leverages a thread-safe `TSequenceManager` with a Pooled-lo range optimizer to pre-allocate key ranges in memory, enabling high-performance bulk inserts for entities with sequenced primary keys. SQLite support is emulated via a specialized table (`dext_sequences`).

### 4.13 Dynamic Query Filters (`Dext.Entity.DbSet`, `Dext.Specifications.SQL.Generator`)
- **`IgnoreQueryFilters` (Fluent API)** — `Db.Users.IgnoreQueryFilters.ToList` — bypasses all registered global query filters (Soft Delete, Multi-Tenancy) for a single query. Does not affect subsequent calls.
- **Specification-Level Control** — `ISpecification<T>.IgnoreQueryFilters` and `ISpecification<T>.IsIgnoringFilters`: enables specification classes to declare intent, keeping admin queries self-contained and reusable.
- **`IsOnlyDeleted` (Spec Integration)** — `ISpecification<T>.IsOnlyDeleted` propagates the trash-bin query flag in the same mechanism, allowing `OnlyDeleted` to be declared in a spec.
- **Scoped Propagation** — In `TDbSet<T>.ToList(ASpec)`, spec flags are propagated to the internal `FIgnoreQueryFilters` / `FOnlyDeleted` state before SQL generation and reset via `ResetQueryFlags` in a `finally` block — ensuring isolation between calls.
- **SQL Generator Integration** — `TSQLGenerator<T>.GetSoftDeleteFilter` returns empty string when `FIgnoreQueryFilters` is `True`. `GetQueryFiltersSQL` exits early for the same reason.
- **Admin Spec Pattern** — Allows building dedicated specification classes (`TAdminListSpec`) that call `IgnoreQueryFilters` in their constructor, enabling declarative, zero-friction access to raw data.

### 4.14 Remote TEntityDataSet Sync (S51)
Exposes delta-tracking mechanisms and transport decompression.

### 4.14.1 Native Change-Log Tracking in TEntityDataSet
- **Row State Tracking** — Native change tracking via `TEntityRowState` 
  and change list property `Changes` (`TEntityChange`).
- **Tombstones for Deletion** — Retains primary key maps (`Key`) of deleted
  entities during `Delete`, enabling synchronization of removals.
- **Transactional Consolidating** — Native `AcceptChanges` API to clear
  accumulated change logs after successful updates.

### 4.14.2 Server-side agreed service mapping
- **Automated Routing Endpoints** — Native `MapEntityDataSet<T>` exposing
  `GET` for fetching and `POST` `/apply` for persisting the change list.
- **Custom Persistence Engine** — Pluggable `IEntityDataSetStore` interface
  defaulting to `TDbContextEntityDataSetStore` (`DbContext.SaveChanges`).

---

## 5. Networking

### 5.1 High-Performance REST Client (`Dext.Net.RestClient`)
- **Fluent API** — Consume APIs without visual components. Methods: `RestClient('url').BearerToken('...').Get<T>('/path').Await`.
- **Fluent REST Request Factory** — Grouping pattern using `Client.Request.Get('/path')` to isolate request building, avoiding root-level client scope bloat and return type limitations (Issue #119).
- **Unrestricted Body Payloads** — Native support for serializing `record` and `TArray<T>` in request payloads (`Body<T>` and the array helper `BodyArray<T>`), bypassing generic compiler restrictions.
- **Record & Array Deserialization** — Native deserialization of JSON arrays and objects directly into records and dynamic arrays (`TArray<T>`) during request execution.
- **Ergonomic Responses** — Boolean helper `IRestResponse.IsSuccess` for immediate status code validation in the `200..299` range.
- **Connection Pooling** — Intelligent `TNetHttpClient` instance reuse (thread-safe pooling), eliminating TCP/SSL handshake overhead and radically reducing OS resource usage.
- **Auto-Serialization** — Native integration with Dext's JSON engine for hydrating objects and generic collections (`IList<T>`).
- **Async First** — Fully integrated with `Dext.Threading.Async` with `ICancellationToken` support for cooperative cancellation and UI Access Violation protection.
- **Retry Logic** — Automatic recovery with exponential backoff and Async/Await support.
- **Typed Responses** — `Client.Get<TUser>('/users/1')` with automatic deserialization.
- **Async Chaining** — `Client.Get<TToken>('/auth').ThenBy<TUser>(...)`.OnComplete(...)`.Start`.
- **Cancellation** — `ICancellationToken` to abort ongoing requests.
- **Pluggable Auth** — `TBearerAuthProvider`, `TBasicAuthProvider`, `TApiKeyAuthProvider`.
- **Thread Safety** — Immutable configuration snapshot in `Execute`; isolated execution via pool.
- **Response Headers** — Full access via `GetHeader` (case-insensitive) and `GetHeaders` (TNetHeaders array).
- **THttpRequestInfo** — Integration with `.http` parsers for ad-hoc request execution.
- **Multipart Form Fields with Content-Type** — Support for specifying custom MIME types (e.g. `application/json`) for individual form fields in multipart requests via `AddFormField` and `AddMultipartField` (Issue #125).
- **Conditional Query Parameters** — Support for fluently adding query parameters conditionally (`QueryParamIfNotEmpty`, `QueryParamIf`, and overloads with default values) to simplify request building (Issue #123).
- **Legacy Compatibility and Indy Fallback** — Complete abstraction of the HTTP engine (`IDextHttpEngine`) with automatic fallback using Indy (`TIdHTTP`) for older IDEs (Delphi XE2 to XE7), active in compilers below XE8 or under the `DEXT_FORCE_INDY` directive. OpenSSL DLLs required for legacy HTTPS requests.
- **Transparent Inbound Decompression** — `TRestClient` advertises
  `Accept-Encoding` and decompresses response streams dynamically.
- **Raw Stream Preservation** — Preserves raw compressed bytes via
  `RawContentStream` property for audit or direct byte checking.
- **Dynamic Client Certificate / mTLS** — `TRestClient.ClientCertificate` with overloads for file path (`cert.pfx`, `cert.p12`) and in-memory stream (`TStream`). Enables direct submission to public webservices (such as Portugal SAF-T) without requiring certificates installed in the Windows certificate store. Automatic per-request isolation and cleanup in connection pools.

### 5.2 Authentication Providers
- **Bearer Token (JWT)** — Automatic `Authorization: Bearer <token>` header.
- **Basic Auth (RFC 7617)** — Base64 encoding of `user:password`.
- **API Key** — Customizable header or query string.
- **OAuth 2.0 Client Credentials (RFC 6749 §4.4)** — Automatic token caching, thread-safe refresh with a 30s safety margin to prevent using expired tokens.

### 5.3 Native Redis Client (S13) (`Dext.Net.Redis`)
Dext features a native, high-performance Redis client library supporting RESP2/RESP3 serialization, connection pooling, reactive Pub/Sub channels, and RedisJSON.

### 5.3.1 High-Performance Serialization (RESP2/RESP3)
- **Zero-Allocation Parser** — Highly optimized `TDextRedisParser` parsing incoming RESP byte streams using memory spans (`TByteSpan`), avoiding heap allocations.
- **RESP3 Additions** — Native support for new RESP3 value types including Nulls (`_`), Booleans (`#`), and Double Floats (`,`).

### 5.3.2 Connection Pool & Thread Safety
- **TDextRedisConnectionPool** — Safe, high-concurrency client pooling (`IStack<TDextRedisConnection>`) to minimize socket creation overhead and manage connections efficiently.
- **Thread-Safe Commands** — Automatic acquisition and release of pooled connection handles during command executions.

### 5.3.3 Reactive Pub/Sub & Channels
- **TDextRedisPubSub** — Asynchronous Pub/Sub engine using Dext's native concurrent channels (`IChannel<TDextRedisMessage>`) for thread-safe message dispatching.

### 5.3.4 RedisJSON & Dext.Json Integration
- **RedisJSON Module Support** — Native integration with the `Dext.Json` serialization engine to store and retrieve structured Delphi objects directly as JSON values.

### 5.4 Native TLS/SSL (`Dext.Net.Security`)
- **Unified TLS Abstraction** — `IDextTLSEngine`, `IDextTLSContextProvider`, and `IDextTLSStream` definitions for decoupled transport security.
- **OpenSSL 3.x Memory BIO Engine** — Zero-copy/lock-free TLS handshake and memory-buffered encrypted framing for raw asynchronous TCP Sockets (`epoll` on Linux and `IOCP` on Windows).
- **HTTP.sys & Windows Schannel Integration** — Native HTTPS bindings and Windows Certificate Store integration without external DLLs.
- **Taurus TLS & Indy SSL** — Modern TLS 1.3 / OpenSSL 3.x provider (`TDextTaurusTLSContext`) for Indy server engines.
- **`TDextRedisClient` SSL Support (`rediss://`)** — Transparent SSL/TLS stream wrapper for the native Redis client.
- **`dext dev-certs` CLI Tooling** — Pure Pascal CryptoAPI generator for self-signed X.509 development certificates with SAN extension (`localhost`, `127.0.0.1`) and automatic Root Certificate Store registration.

### 5.5 Sockets & Native MQTT (S47)
The framework includes support for network transport decoupling inside the IOCP/Epoll server to expose raw TCP/UDP sockets, alongside a native implementation of the MQTT v3.1.1 protocol (client and broker) for asynchronous pub/sub messaging.

### 5.5.1 Transport Layer Decoupling (IConnectionHandler)
- **Engine Decoupling** — Abstraction of physical connections (`IDextTransportConnection`) and custom handlers (`IConnectionHandler`) allowing raw TCP/UDP streams to bypass the HTTP parser layer completely directly at the IOCP/Epoll worker threads.

### 5.5.2 TCP & UDP Sockets
- **TDextTcpServer & TDextTcpClient** — Concurrent, asynchronous TCP server and lightweight TCP client supporting configurable read/write timeouts.
- **TDextUdpServer & TDextUdpClient** — Low-level UDP communication components supporting raw byte spans and non-blocking receive callbacks.

### 5.5.3 Native MQTT v3.1.1 Protocol Stack
- **Binary Frame Encoder/Decoder** — High-performance packet encoder and decoder supporting variable-byte Remaining Length representation and all standard MQTT control frames (CONNECT, CONNACK, PUBLISH, PUBACK, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK, PINGREQ, PINGRESP, DISCONNECT).
- **Trie Tree Route Router** — Highly optimized Trie tree data structure for wildcards and topic subscription matching, with full support for single-level (`+`) and multi-level (`#`) wildcards.
- **Broker Server & Client** — Multi-session concurrent MQTT broker supporting subscription states and clean sessions, alongside a non-blocking MQTT client with background keep-alive ping loop.

### 5.6 gRPC & Protocol Buffers (S02)
High-performance binary transport protocol implementation.

### 5.6.1 Protobuf Serialization Engine (`Dext.Serialization.Protobuf`)
- **TProtobufSerializer** — High-speed, zero-allocation binary serialization engine for Protocol Buffers (proto3).
- **Format Handlers** — Supports Varint, Fixed32, Fixed64, and Length-Prefixed formatting types using high-performance `TSpan` memory representations.
- **Entity Binding via RTTI** — Marshals Delphi objects directly to Protobuf binary format, evaluating attributes such as `[ProtoMember]` and field ordinals.

### 5.6.2 Length-Prefixed Message Codec (`Dext.Grpc.Codec`)
- **TGrpcCodec** — Framing codec for gRPC Length-Prefixed Messages (LPM).
- **Compression Support** — Compression flag handling (1-byte compressed flag, 4-byte big-endian message length) for HTTP/2 transmission.

### 5.6.3 gRPC Server Engine (`Dext.Web.Grpc.Server`)
- **TGrpcDispatcher** — Decodes HTTP/2 frames and maps incoming `application/grpc` requests to the registered service handlers.
- **Service Mappings** — Dynamic routing and method dispatch via reflection and interface lookup tables.

### 5.6.4 Client & DataSet Integration (`Dext.Entity.GrpcProvider`)
- **TEntitygRpcProvider** — Pluggable gRPC sync provider for `TEntityDataSet`, enabling bi-directional remote synchronization.
- **TgRpcClient** — Low-level client engine sending Protobuf streams and parsing gRPC binary responses.

---

## 6. Event Bus

In-process **MediatR**-style publish/subscribe (`Dext.Events`). Handlers respect DI lifecycles (scoped handlers share the request context).

### 6.1 Core Architecture (`Dext.Events.Interfaces`, `Dext.Events.Bus`)
- **IEventBus** — Central in-memory event bus for total decoupling between producers and consumers.
- **IEventHandler\<T\>** — Typed interface for event handlers. Multiple handlers per event type, executed in registration order.
- **IEventPublisher\<T\>** — ISP (Interface Segregation Principle) facade for components that only publish a specific event type.
- **Synchronous Dispatch** — `IEventBus.Dispatch` invokes all handlers and returns `TPublishResult` with statistics (`HandlersInvoked`, `HandlersFailed`, `HandlersSucceeded`).
- **Asynchronous Dispatch** — `DispatchBackground` executes handlers in a separate thread with an isolated DI scope (fire-and-forget).
- **TEventBusExtensions** — Generic static helpers `Publish<T>` and `PublishBackground<T>` that box the event to `TValue` and delegate to `IEventBus`.

### 6.2 Behavior Pipeline (`Dext.Events.Behaviors`)
- **IEventBehavior** — Cross-cutting middleware for the event pipeline. `Intercept(AEventType, AEvent, ANext)` method — calling `ANext()` continues the pipeline; omitting it short-circuits.
- **TEventLoggingBehavior** — Structured logging via `ILogger`. Debug before/after handler with elapsed time. Error handling with failure re-raise.
- **TEventTimingBehavior** — Debug-only, records dispatch time via `OutputDebugString`.
- **TEventExceptionBehavior** — Structured exception wrapping in `EEventDispatchException` with event type name. Re-raise preserves original context.
- **Global vs Per-Event Behaviors** — Global apply to all events; Per-event apply only to the specific type and execute INSIDE global ones.

### 6.3 DI Extensions (`Dext.Events.Extensions`)
- **`Services.AddEventBus`** — Registers `IEventBus` as a Singleton (each Publish creates a child DI scope).
- **`Services.AddScopedEventBus`** — Registers as Scoped (handlers share the same scope, ideal for web requests with a shared DbContext).
- **`Services.AddEventHandler<TEvent, THandler>`** — Typed handler registration with automatic Transient registration.
- **`Services.AddEventBehavior<T>`** — Global behavior. **`AddEventBehaviorFor<TEvent, T>`** — Per-event behavior.
- **`Services.AddEventPublisher<T>`** — Registers `IEventPublisher<T>` as transient for ISP injection.
- **`Services.AddEventBusLifecycle`** — Registers `TEventBusLifecycleService` as an `IHostedService`.

### 6.4 Lifecycle Events (`Dext.Events.Lifecycle`)
- **TEventBusLifecycleService** — Background service listening to `IHostApplicationLifetime` and publishing `TApplicationStartedEvent`, `TApplicationStoppingEvent`, `TApplicationStoppedEvent` to the `IEventBus`.
- **Hosting Bridge** (`Dext.Hosting.Events.Bridge`) — `THostingLifecycleEventBridge` for integration with the background services builder via `AddLifecycleEvents`.

### 6.5 Testing Support (`Dext.Events.Testing`)
- **TEventBusTracker** — Fake `IEventBus` for tests: records every publish in a typed list. `DispatchBackground` is synchronous.
- **DI registration** — `TEventBusTracker.Register(Services, Tracker)` instead of `AddEventBus`; chainable with `AddEventPublisher` / `AddTransient`.
- **Assertions** — `HasPublished<T>`, `PublishedCount<T>`, `LastPublished<T>`, `GetPublished<T>`, `Clear`.

### 6.6 Aggregate Exception Handling
- **EEventDispatchAggregate** — Aggregate exception containing `Errors: TArray<string>` with one entry per failed handler. All handlers are always invoked before raising.

---

## 7. Testing & Quality

### 7.1 Test Runner
- **CLI Runner** — `dext test` runs the project suite. On Windows, `--coverage` produces HTML/XML plus `dext_coverage.xml` (SonarQube coverage) via Delphi Code Coverage. The live host for the suite is **Dext Test Explorer** (S36 / section 7.7), not an embedded web dashboard.
- **Fluent Runner API** (`Dext.Testing.Fluent`) — Programmatic configuration: `TTest.Configure.Verbose.RegisterFixtures([...]).Run`. The suite exe already reads `-filter:`, `-category:`, `-fixture:`, `-junit:`, `-html:`, `-json:`.

### 7.2 Attribute-Based Runner (`Dext.Testing.Attributes`)
Write tests without base class inheritance using RTTI metadata.
- **Core Attributes** — `[Fixture]`, `[Test]`, `[Fact]`, `[TestClass]`.
- **Lifecycle Management** — `[Setup]`, `[TearDown]`, `[BeforeAll]`, `[AfterAll]`, `[AssemblyInitialize]`, `[AssemblyCleanup]`.
- **Data-Driven Testing** —
  - `[TestCase(A, B, Expected)]` — Inline parameterized tests.
  - `[TestCaseSource('MethodName')]` — Dynamic data providers via methods.
- **Execution Filters & Control** —
  - `[Ignore('Reason')]`, `[Skip('Reason')]` — Skip tests.
  - `[Explicit]` — Tests run only when explicitly selected.
  - `[Category('Tag')]`, `[Trait('Name', 'Value')]` — Categorization and filtering.
  - `[MaxTime(ms)]` — Warning if the test exceeds the budget (does not fail).
  - `[Repeat(n)]` — Repeats the method n times.
  - `[Priority(n)]` — Execution order (lower number first). Not a CLI filter.
  - `[Platform('Windows, Linux')]` — OS-specific restrictions.

### 7.3 Fluent Assertions (`Dext.Assertions`)
Fluent API based on the `Should(Value)` pattern.
- **Typed Assertions** — Specific methods for `ShouldString`, `ShouldInteger`, `ShouldDouble` (approximation), `ShouldBoolean`, `ShouldDateTime`, `ShouldGuid`, `ShouldUUID`, `ShouldObject`.
- **List/Collection Assertions** — `Should(List).HaveCount(5).Contain(X).OnlyContain(Predicate).AllSatisfy(Predicate)`.
- **Structural Comparison** — `BeEquivalentTo` for deep object and collection comparison (order-independent).
- **Soft Asserts** — `Assert.Multiple(procedure ... end)` to collect multiple failures in a block before failing the test.
- **Action Assertions** — `Should(Proc).Throw<EException>().WithMessageContaining('...')`.

### 7.3b Web Application Factory (S66 / S68)
- **`TDextApplicationFactory<TApp>`** / **`TDextWebApplicationFactory<TApp>`** — Builds `TWebApplication` with `WithTestServices` / `WithConfigure`.
- **`CreateClient: IDextTestHttpClient`** — In-process GET/POST/PUT/DELETE (no TCP); dispatches through `TWebApplication.BuildRequestPipeline`.
- **`IDextTestHttpResponse`** — StatusCode, ContentType, Body, headers.

### 7.4 Snapshot Testing
- **`MatchSnapshot('name')`** — Verify complex objects and JSON payloads via disk-based baseline comparison.
- **Folder** — Baselines live in `{ExeDir}\Snapshots\` (not `__snapshots__/`).
- **Structural JSON Compare** — Smart comparison that ignores formatting and property order in JSON.
- **Update Mode** — `SNAPSHOT_UPDATE=1` environment variable to refresh baselines.

### 7.5 Mocking & Interception (`Dext.Mocks`, `Dext.Interception`)
- **Dynamic Proxies** — `TProxy` (Interfaces) and `TClassProxy` (Classes with virtual methods) via `TVirtualInterface` and `TVirtualMethodInterceptor`.
- **Fluent Mocking** — `Mock<T>.Setup.Returns(Val).When.Method(Args)`.
- **Argument Matchers** — `Arg.Any<T>`, `Arg.Matches<T>` (`Arg.&Is<T>`), `Arg.IsNil<T>`, `Arg.IsNotNil<T>`.
- **Verification** — `Received(Times.Once)`, `Received(Times.AtLeast(n))`.
- **Auto-Mocking** — `TAutoMocker` for automated mock injection into the DI container during unit tests.

### 7.6 Reporting & CI/CD (`Dext.Testing.Report`)
- **Multi-Format Export** — JUnit XML, xUnit XML, TRX (Azure DevOps), HTML (Dark Theme), JSON.
- **SonarQube Integration** — Generate code coverage and failure reports compatible with Quality Gates.
- **Decoupled TestInsight Integration** (`Dext.Testing.TestInsight`) — Decoupled execution hook and listener for TestInsight plugin that automatically routes test runs and results to the IDE without framework compile-time coupling.
- **Decoupled Test Runner Integration & Registry** (`Dext.Testing.Integration`) — Command-line registry and parameter processing system enabling decoupled executions from the IDE or CLI without intermediate BPL dependencies.
- **Native DUnitX Integration** (`Dext.Testing.DUnitX`) — Decoupled runner adaptation for DUnitX that pipes real-time results, status streams, and filtering logic over local HTTP/SSE to the Dext Test Explorer IDE Expert.
- **Native DUnit Integration** (`Dext.Testing.DUnit`) — Decoupled runner adaptation for DUnit that registers custom listeners to pipe results, duration metadata, and execution streams to the Dext Test Explorer.
- **Native DUnit2 Integration** (`Dext.Testing.DUnit2`) — Decoupled runner adaptation using proxy interfaces to pipe real-time results and suite hierarchies from DUnit2 frameworks to the Dext Test Explorer.
- **Test Context Injection** — `ITestContext` injectable via parameter for `WriteLine`, `AttachFile` (screenshots), and execution metadata.
- **Per-test history in Test Explorer** (`TTelemetryTracker` in `Dext.Testing.Design.DockableForm`) — `{project}\.dext\testing\history.json` (up to 1000 rows). The Details pane flags flaky tests and duration regression. This is not the suite-total JSON.
- **`TTestHistoryManager`** (`Dext.Testing.History`, `dext_test_history.json`) — Per-**run** totals (passed/failed/skipped/duration, last 50). Only the sidecar dashboard consumes it today. Explorer does not show that series yet — S75 F-10.
- **OpenTelemetry Test Telemetry** (`Dext.Testing.Listeners.Telemetry`) — Integrated telemetry listener piping test execution metrics (`test_duration_ms`, `test_count_passed`, `test_count_failed`) to OpenTelemetry collectors.

### 7.7 RAD Studio Expert & IDE Integration (`Dext.Testing.Design.*`)
- **Dext Test Explorer Dockable Window** (`Dext.Testing.Design.DockableForm`) — Native dockable window in RAD Studio displaying interactive test tree, status filters, and search. Per-test history in Details (flaky / duration). Suite totals across runs: S75 F-10.
- **Gutter Margin Icons** (`Dext.Testing.Design.Gutter`) — Interactive visual icons in the left code editor margin (green checkmark for pass, red cross for failure).
- **Embedded Local IDE HTTP/SSE Server** (`Dext.Testing.Design.Server`) — Real-time event streaming server embedded in the Expert receiving test execution streams without BPL coupling.
- **Code Coverage Visualizer** (`Dext.Testing.Design.Coverage`) — Direct editor highlighting of lines covered by test runs via AST parsing (`Dext.Testing.Design.AST`).

### 7.8 Scale and Rigor
Dext is continuously validated by a massive testing infrastructure to ensure integrity across its subsystems:

- **Engineering Statistics** — The project exceeds **200,000 lines of pure Pascal code** (excluding templates and documentation), reflecting a massive investment in stability and high-level abstractions.
- **Massive Coverage** — Hundreds of test suites with thousands of individual assertions validating everything from the Core (Memory, Collections) to complex Web and ORM integrations.
- **Multi-DB Matrix (ORM)** — The persistence engine is exhaustively tested across a real matrix of 5 databases: PostgreSQL, SQL Server, MySQL, SQLite, and Firebird.
- **Stress & Concurrency Testing** — Validation of concurrent collections, channels, and async tasks under high load to ensure no Race Conditions.
- **Field Evidence** — Framework validated in real-world projects deployed on **AWS and Azure**, with fiscal management systems processing peaks of **~800,000 daily requests**.
- **CI/CD** — JUnit / xUnit / TRX / HTML / JSON reports and SonarQube coverage (`dext_coverage.xml`) for Azure DevOps and GitHub Actions pipelines.

---

## 8. Template Engine

### 8.1 Core Architecture
- **ITemplateEngine** — Main interface: `Render(template, context)` and `RenderTemplate(name, context)`.
- **TDextTemplateEngine** — Complete implementation with AST (Abstract Syntax Tree) parser. Each directive is compiled into a node (`TTemplateNode`) with a `Render` method.
- **ITemplateContext** — Hierarchical context with string values, objects, and lists. `CreateChildScope` for nested scoping.

### 8.2 Template Loader
- **ITemplateLoader** — Pluggable interface for loading templates. Implementations: FileSystem and In-Memory.

### 8.3 Node Types (AST)
- `TTextNode` (literal text), `TExpressionNode` (interpolation `{{ var }}`), `TIfNode`/`TElseIfNode`/`TElseNode` (conditionals), `TForEachNode` (iteration with `@index`, `@first`, `@last`), `TBlockNode` (named blocks), `TExtendsNode` (layout inheritance), `TSectionNode` (sections), `TMacroNode` (reusable macros), `TBreakNode`/`TContinueNode` (loop flow control).

### 8.4 Expression Engine
- Expression parser with support for arithmetic, comparison, and logical operators (`and`, `or`, `not`).
- **Chained Filters** — `{{ value | upper | truncate(10) }}` with filter pipeline.
- **Filter Registry** (`ITemplateFilterRegistry`) — `RegisterFilter(name, func)` for custom filters.
- **Built-in Filters** — `upper`, `lower`, `capitalize`, `truncate`, `default`, `date`, `html_escape`, etc.

### 8.5 Advanced Features
- **Layout Inheritance** — `{% extends "base.html" %}` with block overrides.
- **Whitespace Control** — `{%- -%}` for whitespace control in directives.
- **HTML Mode** — `IsHtmlMode` for automatic output escaping.
- **Source Position Tracking** — `TSourcePos` with line, column, and filename for precise error reporting.
- **ETemplateException** — Exceptions with position and template snippet for debugging.

---

## 9. Validation

- **Attribute-Based Validation** — RTTI decorators: `[Required]`, `[StringLength(min, max)]`, `[Range(min, max)]`, `[RegularExpression(pattern)]`, `[EmailAddress]`, `[Url]`.
- **Fluent Validation API** — Strongly-typed validation base class `TAbstractValidator<T>` implementing `IValidator<T>` as a modern C# FluentValidation-like alternative.
- **Fluent Rule Builder** — Memory-efficient record `TValidationRuleBuilder<T>` that avoids heap allocations while building chained validation rules (`Required`, `Length`, `Range`, `EmailAddress`, `Matches`, `MatchesPattern`, `Must`, `When`).
- **Smart Property Integration** — Concrete `RuleFor` overloads for standard `Prop<T>` smart properties (e.g., `Prop<string>`, `Prop<Integer>`, `Prop<Boolean>`, etc.) to automatically extract property names from Prototype ghost entities without magic strings or compiler casting issues.
- **Pattern Registry** — `TValidationPatterns` registry mapping keys to locale-specific regular expressions (e.g. Pt-BR or En-US phone numbers and zipcodes).
- **TValidator** — Non-generic helper: `Validate(obj)` returns `TValidationResult` with a list of `TValidationError` (field + message).
- **TValidator\<T\>** — Typed generic version.
- **Custom Validators** — Inherit from `ValidationAttribute` for custom business rules.
- **Web Integration** — Automatic resolution of registered validators (`IValidator<T>`) from the Dependency Injection (DI) container inside the web model binding pipeline (`THandlerInvoker.Validate`), raising `TWebValidationException` to yield structured error JSON/HTMX payloads.

---

## 10. Mapper

- **TMapper** — Static facade and central registry for object-to-object mapping using Delphi RTTI.
- **Fluent Mapping Configuration** — `TTypeMapConfig<TSource, TDest>` record supporting custom mappings using fluent notation:
  - `ForMember(DestName, MapFunc)` — Define custom mapping functions mapping source to target values.
  - `Ignore(DestName)` — Prevent copying specific properties.
- **Instance Mapping** — `TMapper.Map<TSource, TDest>(Source)` returns a newly instantiated mapped destination class.
- **In-Place Mapping** — `TMapper.Map<TSource, TDest>(Source, Dest)` maps source properties onto an existing destination object reference.
- **Collection Mapping** — `TMapper.MapList<TSource, TDest>(SourceList)` maps lists and generic collections automatically.
- **Record Mapping** — Maps matching fields and properties between classes and records.
- **Default Value Optimization** — Support for mapping only non-default values using the `AOnlyNonDefault` parameter to avoid overwriting initialized destination values.
- **CreateMap\<TSource, TDest\>** — Mapping registration with automatic property reflection by name (complements `TTypeMapConfig` above).

---

## 11. Multi-Tenancy

- **ITenantProvider** — Abstraction for current tenant identification.
- **ITenantConnectionStringProvider** — Dynamic connection string resolution per tenant.
- **Strategies** — Shared Database (TenantId), Schema Isolation (`search_path`), Tenant per Database.
- **DML Tenant Filters (S68)** — `GenerateUpdate` / `GenerateDelete` (and batch templates) append `AND TenantId = :…` for `ITenantAware` entities using the current `ITenantProvider` (honors `.IgnoreQueryFilters`).
- **DI Integration** — Registered as a Scoped service for resolution per request.

---

## 12. Desktop UI & Design-Time

### 12.1 Navigator Framework (Flutter-style)
- **ISimpleNavigator** — Push/Pop/Replace/PopUntil navigation with `TValue` data passing.
- **3 Adapters** — `TCustomContainerAdapter` (embed frames in panel), `TPageControlAdapter` (tabs), `TMDIAdapter` (child windows).
- **Middleware Pipeline** — `TLoggingMiddleware`, `TAuthMiddleware`, `TRoleMiddleware` — same architecture as the Web pipeline.
- **Lifecycle Hooks** — `INavigationAware` with `OnNavigatedTo(Context)` and `OnNavigatedFrom`.
- **DI Integration** — Navigator registered as a Singleton service in the container.

### 12.2 Magic Binding (`Dext.UI.Binding`)
- **Two-Way Attribute-Based Binding** — `[BindEdit('Name')]`, `[BindCheckBox('Active')]`, `[BindText('ErrorMessage')]`.
- **Nested Properties** — `[BindEdit('Customer.Address.City')]` with dot notation.
- **Message Dispatch** — `[OnClickMsg(TSaveMsg)]` eliminates manual `OnClick` handlers.
- **Custom Converters** — `IValueConverter` with `Convert`/`ConvertBack` for complex types (e.g., `TCurrencyConverter`).
- **TBindingEngine** — Central engine automatically synchronizing ViewModel ↔ UI.

### 12.3 MVVM Patterns
- Clean architecture with ViewModel + Controller + DI.
- **Validation Integration** — `FViewModel.Validate` with errors automatically reflected in the UI via binding.

### 12.4 Infrastructure
- **Interception Engine** — Proxy engine for method interception, base for Mocks and AOP (Aspect-Oriented Programming) features.
- **Design-Time Experts** — IDE Grid Data Preview and specialized metadata property editors.

### 12.5 Design-Time Scaffolding Experts (`Dext.EF.Design.Scaffolding`)
- **TSelectionEditor Integration** — Non-invasive context menu integration for `TFDConnection` and `TDataSet` (FireDAC and Generic). Dext menus coexist with native IDE menus.
- **TTableSelectionForm** — Advanced selection UI with real-time filtering, "Select All/None" shortcuts, and live table/selection counters.
- **Live Scaffolding Preview** — High-fidelity preview window with real-time code generation, statistics (Entities/Metadata/Lines), and style switching (POCO vs. Smart).
- **Smart PascalCase Engine** — Acronym-aware naming logic (`EmployeeID` → `EmployeeId`, `ReportsTo` preserved) with support for `snake_case` and `ALL_CAPS` normalization.
- **Enhanced Meta-Inference** — Precise AutoInc detection via RTTI and `ftAutoInc`, ensuring 1:1 parity with database schema.
- **IOTA Automation** — Seamless creation of new units in memory and automatic association with the active Delphi project.

---

---

## 13. CLI & Scaffolding

- **Dext CLI (S01)** — Unified CLI engine (`dext.exe`) for project management and development automation.
- **Advanced Scaffolding** — Project and file generation via smart templates: `dext new` (projects), `dext scaffold` (controllers, ORM entities, DTOs, middlewares) supporting all major relational engines (SQLite, PostgreSQL, SQL Server, Firebird, MySQL/MariaDB, Oracle) with automatic uppercase schema resolution for Oracle dictionary metadata (`MetaCurSchema`, `MetaDefSchema`).
- **`dext dev-certs`** — Native CryptoAPI provisioner for local development X.509 certificates with SAN extension and automatic Root Certificate Store trust.
- **`dext test --coverage`** — Suite runner with **code coverage** via `.map` files (Windows). Produces Delphi Code Coverage HTML/XML and `dext_coverage.xml` (SonarQube coverage) automatically. No separate `--sonar` flag.
- **`dext migrate [up|down|list|generate]`** — CLI manager for Dext ORM database schema migrations.
- **`dext doc`** — Automated static HTML technical documentation generator with interactive route visual maps.
- **`dext ui`** — Local web dashboard for **project configuration** (not a live test-suite monitor).
- **`dext index`** — Indexing of all public symbols (classes, records, interfaces, methods) in Markdown, JSON, and CSV optimized for AI agents and NotebookLM.

---

## 14. Observability

- **TDiagnosticSource (S03)** — Centralized event publisher based on JSON payloads, ensuring decoupling between producers (ORM, Web) and consumers. Observers intercept HTTP request lifecycle and SQL execution without coupling monitoring to business logic.
- **Activity Tracking** — CorrelationId / activity tracking for debugging complex and distributed flows.
- **Dext Sidecar (`DextSidecar.exe`)** — Sidecar native process for real-time file watching (`Dext.Services.FileWatcher.pas`), log streaming (`Dext.Sidecar.LogStreamer.pas`), embedded telemetry web server (`TSidecarServer`), and System Tray VCL interface (`Dext.Vcl.TrayIcon.pas`).
- **Telemetry Bridge** (`Dext.Logging.Telemetry`) — Automatic `ILogger` integration, enabling HTTP and SQL telemetry visualization in console or log files.
- **SQL Capture** — ORM native SQL instruction extraction and formatting for real-time auditing.
- **HTTP Lifecycle** — Latency, status codes, and web framework route tracing.
- **Stack Trace Extraction** (`Dext.Core.Debug`) — Precise and detailed stack trace extraction at the point of exception. Critical for debugging highly integrated frameworks with dynamic execution flows.

The framework embeds a premium, high-performance, asynchronous observability suite designed to gather, persist, and visualize structured logs, distributed spans, system health metrics, and detailed database query and external network profiling.

### 14.1 Distributed Tracing & Structured Logging (S24)
- **Asynchronous Ring Buffer** — Log entries and spans are collected into a high-performance in-memory ring buffer (capped at 1000 items), eliminating disk I/O bottlenecks in critical request-handling threads.
- **Asynchronous Persistence** — A dedicated background worker (`TDashboardSaveTimer`) periodically flushes traces to `telemetry.json` every 30 seconds in a non-blocking manner.
- **Hierarchical Gantt Tree** — The Dashboard renders visual span nodes nested under their parent trace contexts (`TraceId`/`SpanId`) in real time, making latency and processing bottlenecks simple to analyze.

### 14.2 System Metrics & Throughput (S25)
- **RED Metrics Dashboard** — Real-time visual graphs in the Dashboard tracking HTTP RPS (Requests per Second), SQL QPS (Queries per Second), HTTP Errors, and average latency.
- **System Health Monitor** — Operating system resource sampling: CPU usage (%), physical memory (Working Set in MB), active thread count, and active DB connections.
- **Non-Blocking Persistence** — Serialized metrics are appended to a ring buffer and written to `metrics.json` every 30s via the async background timer.

### 14.3 Database & Outbound HTTP Profiler (S27)
- **FireDAC Auto-Instrumentation** — Zero-coupling interception inside the DB driver layers (`Dext.Entity.Drivers.FireDAC.pas`), automatically capturing raw SQL queries (`db.statement`), query parameters (`db.params`), query elapsed execution times, and routing database exceptions.
- **Outbound HTTP Auto-Instrumentation** — Network call interception inside the Rest Client (`Dext.Net.RestClient.pas`), capturing target URLs, HTTP methods, response elapsed timings, HTTP status codes, and exceptions.
- **Context Inspector Drawer** — A sliding overlay panel in the Dashboard triggered by clicking any span node in the tree. Displays pretty-printed SQL statements, structured query parameters, copied cURL commands, and generic metadata tags.

### 14.4 Streamable Sessions & HTMX (S23)
- **IStreamableSessionManager** — SSE channel manager with automatic garbage collection (runs every 60s, evicting idle sessions after 30 minutes).
- **HTMX Fragment Swap** — Endpoints serving dynamic HTML fragments (e.g. `/sidecar/fragments/metrics`), allowing live DOM updates via HTMX without writing any client-side JavaScript.

---

## 15. AI Skills

- **Native AI Skills** — Modular instruction files (`dext-web.md`, `dext-orm.md`, `dext-auth.md`) teaching AI assistants (Cursor, Antigravity, Copilot, Claude) to generate idiomatic Dext code.
- **3 Integration Modes** — Direct copy to `.agents/skills/`, global custom configuration, or symlinks.
- **Modular by Design** — Atomic skills to save context tokens; load only relevant modules for the current feature.
- **Compatibility** — Claude Code, Cursor, Antigravity, Cline, OpenCode, GitHub Copilot.

---

## 16. MCP Server

The framework provides a native, zero-dependency implementation of the **MCP 2025-03-26** specification, enabling Dext applications to expose tools, resources, and prompts to AI agents (like Claude Desktop and Claude Code).

- **Supported Transports** — `HTTP Streamable` (Synchronous POST with Sessions), `SSE` (Legacy Server-Sent Events), and `Stdio`.
- **Declarative RTTI API** — `TMCPToolProvider` with `[MCPTool]`, `[MCPParam]`, `[MCPResource]`, and `[MCPPrompt]` attributes for frictionless endpoint registration.
- **Fluent Builder API** — Chainable registration: `Server.Tool('name').Description('...').OnCall(...)`.
- **Rich Content Types** — Built-in support for `TMCPContent` (Text, Image, Audio, Embedded Resources) and `TMCPToolResult` returning multiple blocks and error states.
- **Integration** — Runs natively on top of Dext's `TWebHostBuilder` allowing MCP and REST endpoints to coexist non-blocking in the same process.
### 16.1 TMCPServer & TMCPServerBuilder
- **TMCPServerBuilder** — Fluent builder to configure MCP servers.
- **HTTP Stack Selection** — Support for Indy and HTTP.sys (Native) stacks.
- **Provider Registration** — Automated mapping of custom providers.
---

*Dext Framework 1.0 — Features Index. Revision: September 2026.*
