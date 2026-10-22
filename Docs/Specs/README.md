# 📑 Dext Framework: Engineering Specifications

This directory contains the formal technical specifications and requirements for the Dext Framework evolution. Each "Spec" defines the architecture, user experience (CLI/API), and implementation constraints for a core feature.

## 🚀 Active Specifications

ID | Title | Status | Goal
:---: | :--- | :---: | :---
**S01** | [Advanced Scaffolding](S01-Advanced-Scaffolding.md) | ✅ Finalized | Automate the creation of Startups, Entities, and Endpoints using templates.
**S02** | [Modernizer: gRPC & Protobuf](S02-Modernizer-gRPC.md) | ✅ Finalized | High-speed binary communication as a legacy replacement for DataSnap/RDW.
**S03** | [Live Observability Dashboard](S03-Live-Observability.md) | ✅ Finalized | Real-time debugging of SQL, HTTP and Exceptions via Telemetry (Core done, UI next).
**S04** | [DataAPI Conventions](S04-DataApi-Conventions.md) | ✅ Finalized | Simplify REST endpoint exposure using attributes and global defaults.
**S05** | [Advanced Tooling](S05-Advanced-Tooling.md) | 📝 Draft | IDE Wizards, Code-First Parsers (Pending), and TFDConnection Scaffolding (Implemented).
**S06** | [Security & Identity](S06-Security-Identity.md) | ✅ Finalized | Native OAuth2, OpenID Connect, and JWT policy-based authorization.
**S07** | [High-Performance Reflection](S07-High-Perf-Reflection.md) | ✅ Finalized | Zero-boxing type handlers, fast-path reflection registry, and thread-safe RTTI caches.
**S08** | [Dynamic Ports](S08-Dynamic-Ports.md) | ✅ Finalized | Support for Port 0 (OS picks free port) for Demos and CI.
**S09** | [Template Engine](S09-Template-Engine.md) | ✅ Finalized | Zero-dependency AST-based template engine (Razor-like).
**S10** | [Advanced View Engine](S10-Advanced-View-Engine.md) | 🔴 Superseded | Superseded by S12.
**S11** | [Migration Audit & Finalization](S11-Migration-Finalization.md) | ✅ Finalized | Safe schema evolution with renaming detection and CLI automation.
**S12** | [Advanced Template Engine](S12-Template-Engine-Advanced.md) | ✅ Finalized | Layouts, partials, inheritance, AST cache, smart positions, @encoded, and high-performance iterators.
**S13** | [Redis Client](S13-Redis-Client.md) | ✅ Finalized | High-performance async Redis client with RESP3 and RedisJSON support.
**S14** | [SOA via Interfaces](S14-SOA-Interfaces.md) | 📝 Draft | Code-First RPC exposing Delphi interfaces via gRPC natively.
**S15** | [Dext Studio & Visual Scaffolding](S15-Dext-Studio-IDE-Expert.md) | 📝 Draft | Visual IDE Expert for schema mapping, GitOps (YAML), and continuous DB syncing.
**S16** | [Simd Quad Search](S16-Simd_Quad_Search.md) | 📝 Reserved | Reserved for the Future (Idea / Study).
**S17** | [Design-Time Scaffolding](S17-Design-Time-Scaffolding.md) | ✅ Finalized | DB integration and IDE scaffolding support.
**S18** | [Performance Benchmarks](S18-Performance-Benchmarks.md) | ✅ Finalized | Benchmark suite for core Reflection, JSON, FastPath, and ORM components.
**S19** | [FluentQuery Join Evolution](S19-FluentQuery-Join-Evolution.md) | ✅ Finalized | Unified DSL for complex SQL Joins via Managed Records.
**S20** | [Fluent REST Evolution](S20-Fluent-Rest-Evolution.md) | ✅ Finalized | Enhanced TRestClient factories and native record/array payload support.
**S21** | [Soft Delete: Timestamp-based Audit](S21-SoftDelete-Timestamp-Audit.md) | ✅ Finalized | Soft Delete based on nullable timestamps for audit trails.
**S22** | [Prop and Nullable Convergence](S22-Prop-Nullable-Convergence.md) | ✅ Finalized | Convergence of Smart Properties and Nullable wrappers.
**S23** | [HTTP Streamable Sessions & HTMX](S23-Http-Streamable-HTMX.md) | ✅ Finalized | Native HTMX fragment rendering and Streamable Sessions.
**S24** | [Live Logging & Tracing](S24-Sidecar-Logging-Tracing.md) | ✅ Finalized | Distributed tracing and observability suite for logs/spans.
**S25** | [Metrics & Health Monitoring](S25-Sidecar-Metrics-Health.md) | ✅ Finalized | RED metrics, system performance and runtime health dashboards.
**S26** | [Interactive Test Runner](S26-Sidecar-Test-Runner.md) | 🔴 Superseded | Superseded by S36.
**S27** | [Database & HTTP Profiler](S27-Sidecar-DB-HTTP-Profiler.md) | ✅ Finalized | Capturing database queries (SQL) and Rest Client outbound calls.
**S28** | [Conditional Query Parameters](S28-Conditional-Query-Parameters.md) | ✅ Finalized | Fluent chaining of dynamic/optional query parameters in TRestRequest builder.
**S29** | [SIMD and Fast Integer-to-String Conversion](S29-Simd-Fast-Itoa.md) | 📝 Proposed | Zero-allocation division-free integer formatting for high-speed JSON APIs.
**S30** | [DbContext Auto-Hydration](S30-DbContext-AutoHydration.md) | ✅ Finalized | Eliminate generic IDbSet boilerplate getters.
**S31** | [Fluent Validation API & Smart Property Integration](S31-Validation.md) | ✅ Finalized | Strong-typed fluent validation engine integrated with Prop<T> and Web model binding.
**S32** | [Resilience Pipeline & Fault Handling](S32-Resilience-Pipeline.md) | ✅ Finalized | Polly-style transient-fault handling (Retry, Circuit Breaker, Fallback, Timeout) for generic I/O.
**S33** | [Persistent Background Jobs](S33-Background-Jobs.md) | ✅ Finalized | Out-of-process scheduled/recurring background tasks with database/Redis persistence.
**S34** | [Dynamic Query Filters](S34-Dynamic-Query-Filters.md) | ✅ Finalized | Bypassing global query filters (soft-delete, multi-tenancy) dynamically via `IgnoreQueryFilters`.
**S35** | [APM Log Sinks & Unified Telemetry Pipeline (OTLP & Seq)](S35-APM-Log-Sinks.md) | ✅ Finalized | Asynchronous batch-oriented telemetry sinks targeting Seq and OpenTelemetry (OTLP) collectors.
**S36** | [Native Delphi IDE Test Runner (VCL Premium)](S36-IDE-Test-Runner.md) | ✅ Finalized | Native IDE Test Runner expert with decoupled DUnitX, DUnit, DUnit2, and TestInsight integrations and rich reporting.
**S37** | [HTTP Client Engine Abstraction & Indy Fallback](S37-Http-Engine-Indy-Fallback.md) | ✅ Finalized | Abstraction of HTTP Engine and TIdHTTP fallback for older Delphi IDEs.
**S38** | [Legacy Package Synchronization](S38-Legacy-Package-Sync.md) | ✅ Finalized | TMSDev replacement with custom PowerShell automation.
**S39** | [Native High-Performance Server Engine](S39-Native-Server-Engine.md) | ✅ Finalized | Zero-dependency native server engines: `http.sys` (Windows), IOCP sockets (Windows), `epoll` (Linux).
**S40** | [WebSocket Transport & SignalR Hub Integration](S40-WebSocket-SignalR.md) | ✅ Finalized | RFC 6455 WebSocket protocol and full-duplex transport for `Dext.Web.Hubs`.
**S41** | [HTTP/2 Framing & gRPC Transport](S41-Http2-Framing.md) | ✅ Finalized | HPACK compression, HTTP/2 stream multiplexing — foundation for gRPC (S02).
**S42** | [Delphi Hub Client (SignalR-compatible)](S42-Delphi-Hub-Client.md) | ✅ Finalized | Native Delphi client connection library for Dext Hubs.
**S43** | [Net-Advanced (MessagePack, Permessage-Deflate & Native TLS)](S43-Net-Advanced.md) | ✅ Finalized | Advanced networking optimizations: Native TLS, http.sys HTTPS, OpenSSL 3.x, dev-certs CLI, and TRestClient SSL.
**S44** | [HTTP/3 & QUIC Transport Engine](S44-Http3-Quic.md) | 📝 Draft | Native UDP-based QUIC transport and HTTP/3 protocol mapping.
**S45** | [Advanced Kernel I/O (io_uring & kqueue)](S45-Kernel-Io.md) | 📝 Draft | High-performance OS I/O drivers: io_uring for Linux and kqueue for macOS/BSD.
**S46** | [Database Sequence Generators & HiLo](S46-Sequence-Generators.md) | ✅ Finalized | Database sequence mapping and HiLo pre-allocation.
**S47** | [Expose TCP/UDP & MQTT Server/Client](S47-Network-Exposing.md) | ✅ Finalized | Decouple IOCP/Epoll engine to expose raw TCP/UDP sockets and implement MQTT protocol stack.
**S48** | [Processor Groups](S48-Processor-Groups.md) | ✅ Finalized | Windows Processor Groups optimization (NUMA-Aware scaling) for >64 logical cores.
**S49** | [HTTP QUERY Method](S49-Http-Query-Method.md) | ✅ Finalized | Standardized HTTP QUERY method support (RFC 10008) on client and server.
**S50** | [Linux Epoll Server Engine Evolution](S50-Linux-Epoll-Evolution.md) | ✅ Finalized | CPU Pinning, TCP_DEFER_ACCEPT, TFO, zero-copy sendfile, lock-free buffer pooling, and keep-alive timing wheels.
**S51** | [EntityDataSet Remote Sync](S51-EntityDataSet-Remote-Sync.md) | ✅ Finalized | Remote tracking, delta packaging, and transport decompression.
**S52** | [SOCKS5 Proxy Client & Server](S52-Net-Proxy-Socks5.md) | 📝 Draft | Support SOCKS5 client tunnels, Socks over TLS, and SOCKS5 server backlog.
**S53** | [Cloud Object Storage](S53-Storage-ObjectStorage.md) | 📝 Draft | Unified object storage API (S3-Compatible, AWS, OCI, MinIO) and cloud backlog (Queues, Email, Document DBs).
**S54** | [Direct Codecs & Static Code Generation](S54-Codegen-Direct-Codecs.md) | ✅ Runtime Finalized | Shared direct-offset and generated-code codec architecture for gRPC, REST/JSON, ORM, and EntityDataSet. IDE Expert DX is deferred to S15/S54.
**S55** | [Base Path Support (#182)](S55-Base-Path-Support.md) | ✅ Finalized | HTTP.sys URL prefix path binding, TDextPathBaseMiddleware, and Request.ToAppUrl builder.
**S57** | [FastPath ORM Hydration & Streaming Optimization](S57-FastPath-Orm-Hydration-Optimization.md) | ✅ Finalized | Zero-alloc struct/record hydration, DbSet `ExecuteToUtf8Proc` streaming, and pre-compiled RTTI mappers.
**S58** | [High-Performance Generic Object Pooling & Context Recycling](S58-Generic-Object-Pooling.md) | ✅ Finalized | High-performance generic object pool with TSpinLock, manual-reset event broadcast, automatic TDbContext recycling, TRestClient pooling, and FastPath integration.
**S59** | [DbSet Dialect-Aware Batch UPDATE & DELETE Strategy](../../Docs/Specs/S59-DbSet-Batch-Update-Delete.md) | ✅ Finalized | Single-statement dialect-aware batching for PostgreSQL (`unnest`/`VALUES`), MySQL (`CASE-WHEN`), and Tuple-IN deletes.
**S60** | [TBcd & ftFMTBcd High-Precision Decimal Support](S55-TBcd-FmtBcd-Support.md) | ✅ Finalized | First-class end-to-end TBcd / ftFMTBcd support across FireDAC driver, ORM hydration, type converters, and Smart Properties.
**S63** | [Feature Flags & Feature Management](S63-Feature-Flags.md) | 🟡 In Progress | Dynamic toggle keys, rollout filters, time windows and [FeatureGate] attributes.
**S64** | [Forwarded Headers Middleware](S64-Forwarded-Headers.md) | 🟡 In Progress | Reverse proxy header validation (X-Forwarded-For/Proto/Host) and KnownProxies security.
**S65** | [Antiforgery / CSRF Protection](S65-Antiforgery-CSRF.md) | 🟡 In Progress | Double Submit Cookie anti-CSRF protection for SSR HTML forms and HTMX.
**S66** | [Testing WebApplicationFactory](S66-WebApplicationFactory.md) | ✅ Finalized | Fluent in-memory `CreateClient` / `IDextTestHttpClient` (S68) with DI overrides via `WithTestServices` / `WithConfigure`.
**S67** | [CommandLine & UserSecrets Configuration Providers](S67-CommandLine-UserSecrets-Configuration.md) | ✅ Finalized | Enterprise 5-layer configuration pipeline with CLI argument parsing and isolated developer secrets.
**S68** | [Book Review Gaps — Framework Alignment](S68-Book-Review-Framework-Gaps.md) | ✅ P0+P1 Done | Executable P0+P1 delivered; P2 deferred to `Docs\Specs` S69–S74 (plus partial 415 helper).
**S75** | [C++Builder Test Explorer](S75-CppBuilder-Test-Explorer.md) | 🟡 In review | Win64x line coverage via llvm-cov, coverage UI hidden on other `.cbproj` platforms, manual expert install. GetIt and a signed DLL are still open. Full C++ support is not announced.

---

## 🔍 Project Status & Roadmap
For a high-level view of all roadmap items and their current waves, see the [Master Roadmap](../ROADMAP.md).

---

## 🏗️ Spec Maturity Levels
1. **Draft**: Conceptual stage, requirements gathering.
2. **Review**: Architectural design refined, seeking feedback.
3. **Approved**: Ready for implementation.
4. **Implementing**: Currently being developed.
5. **Finalized**: Feature delivered and documented in the Book.

---
*Last update: June 2026*
