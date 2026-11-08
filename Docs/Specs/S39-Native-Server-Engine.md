# 📑 S39: Native High-Performance Server Engine

**Status:** ✅ Finalized
**Owner:** Cesar Romero & Engineering Team
**Reviewers:** Architecture Team
**Created:** 2026-06-17
**Updated:** 2026-11-08 (TLS on the socket engines now points to S43; IOCP status and open decisions added)
**Dependencies:** None (foundational spec)
**Enables:** S40 (WebSocket), S41 (HTTP/2), S02 (gRPC)

---

## 1. Goal

Provide a **zero-dependency, 100% Pascal** server engine layer for the Dext Framework that delivers kernel-level I/O performance on Windows and Linux, eliminating the need for external libraries (Indy, Delphi-Cross-Socket) in production deployments.

The engine must:

- On **Windows**: Use `http.sys` (Kernel Mode HTTP) for standard HTTP workloads **and** raw IOCP sockets for custom protocols (WebSocket, HTTP/2, gRPC).
- On **Linux**: Use `epoll`-based event-driven I/O with a fixed thread pool for high concurrency.
- Integrate seamlessly with the existing `IWebHost` / `TRequestDelegate` pipeline.
- Support **WebSocket upgrade** (delegating framing to S40).
- Be designed to support **HTTP/2 framing** in the future (S41).

### 1.1 Non-Goals (Deferred)

- HTTP/3 (QUIC) — architectural hooks only, no implementation.
- `io_uring` (Linux 5.1+) — future driver, `epoll` is sufficient for V1.
- macOS/FreeBSD `kqueue` — use DCS adapter for macOS until demand justifies a native driver.
- TLS in the socket-level engines (IOCP, epoll): specified in **S43** (unified `IDextTLSEngine` abstraction and an OpenSSL Memory BIO engine). The epoll engine already uses it; the IOCP engine does not yet (see 3.1). `http.sys` uses the operating system's TLS (certificate binding).

---

## 2. Current State

### 2.1 Existing Server Adapters

| Adapter | Unit | I/O Model | Protocol | License |
|---------|------|-----------|----------|---------|
| **Indy (V1)** | `Dext.Web.Indy.Server.pas` | Thread-per-connection | HTTP/1.1 | Embarcadero |
| **DCS** | `Dext.Web.DCS.pas` | IOCP/epoll/kqueue | HTTP/1.1 | LGPL-3.0 |
| **Kestrel (V2)** | — (planned) | NativeAOT bridge | HTTP/1.1+2 | MIT (.NET) |

### 2.2 Existing Abstractions

```
IWebHost
  ├── Run()
  ├── Start()
  ├── Stop()
  └── Port: Integer

TServerFactory = function(Port, Pipeline, Services): IWebHost
```

These abstractions are sufficient for V1 but **lack**:
- Connection-level control (for WebSocket upgrade)
- Graceful shutdown with connection draining
- Backpressure signaling
- Engine-specific configuration (thread count, buffer sizes)



## 3. Architecture

### 3.1 Engine Abstraction Layer

```pascal
type
  /// Server engine configuration
  TServerEngineOptions = record
    /// Number of I/O worker threads (0 = CPU count)
    IoThreadCount: Integer;
    /// Size of the receive buffer per connection (default: 8192)
    ReceiveBufferSize: Integer;
    /// Maximum concurrent connections (0 = unlimited)
    MaxConnections: Integer;
    /// Graceful shutdown drain timeout in milliseconds
    ShutdownTimeoutMs: Integer;
    /// Enable keep-alive (default: True)
    KeepAlive: Boolean;
    /// Keep-alive timeout in seconds (default: 120)
    KeepAliveTimeoutSec: Integer;
  end;

  TConnectionEventHandler = reference to procedure(const AConnection: IDextServerConnection);
  TRequestEventHandler = reference to procedure(const AConnection: IDextServerConnection;
    const ARequest: IDextRawRequest; const AResponse: IDextRawResponse);
  TUpgradeEventHandler = reference to procedure(const AConnection: IDextServerConnection;
    var AAccepted: Boolean);

  /// Core server engine interface
  IDextServerEngine = interface
    ['{...}']
    /// Binds the engine to an address and port
    procedure Bind(const AAddress: string; APort: Word);

    /// Starts accepting connections
    procedure Start;

    /// Stops the engine with optional graceful drain
    procedure Stop(AGracefulTimeoutMs: Integer = 5000);

    /// Returns the actual listening port (useful when port 0 is used)
    function GetListenPort: Word;

    /// Engine-level event handlers
    procedure SetOnConnection(const AHandler: TConnectionEventHandler);
    procedure SetOnDisconnection(const AHandler: TConnectionEventHandler);
    procedure SetOnRequest(const AHandler: TRequestEventHandler);
    procedure SetOnUpgrade(const AHandler: TUpgradeEventHandler);

    /// Read-only access to engine metrics
    function GetActiveConnections: Integer;
    function GetTotalRequests: Int64;

    property ListenPort: Word read GetListenPort;
    property ActiveConnections: Integer read GetActiveConnections;
    property TotalRequests: Int64 read GetTotalRequests;
  end;

  /// Raw server-side connection handle
  IDextServerConnection = interface
    ['{...}']
    function GetConnectionId: UInt64;
    function GetRemoteAddress: string;
    function GetRemotePort: Word;
    function GetLocalPort: Word;
    function IsSecure: Boolean;
    procedure Close;

    /// WebSocket upgrade support
    function SupportsUpgrade: Boolean;
    function UpgradeToWebSocket: IDextWebSocketConnection;

    property ConnectionId: UInt64 read GetConnectionId;
    property RemoteAddress: string read GetRemoteAddress;
  end;
```

### 3.2 Engine Selection Strategy

```pascal
/// Auto-selects the best engine for the current platform
function CreateNativeEngine(const AOptions: TServerEngineOptions): IDextServerEngine;
begin
  {$IFDEF MSWINDOWS}
  // Primary: http.sys for standard HTTP
  // Falls back to IOCP sockets if http.sys unavailable (pre-XP SP2)
  Result := TDextHttpSysEngine.Create(AOptions);
  {$ENDIF}
  {$IFDEF LINUX}
  Result := TDextEpollEngine.Create(AOptions);
  {$ENDIF}
end;

/// For custom protocol support (WebSocket, HTTP/2)
function CreateSocketEngine(const AOptions: TServerEngineOptions): IDextServerEngine;
begin
  {$IFDEF MSWINDOWS}
  Result := TDextIocpEngine.Create(AOptions);
  {$ENDIF}
  {$IFDEF LINUX}
  Result := TDextEpollEngine.Create(AOptions);
  {$ENDIF}
end;
```

### 3.3 Integration with IWebApplication

```pascal
// Current usage (Indy - default):
App := WebApplication;
App.Run(9000);

// New usage (http.sys):
App := WebApplication;
App.UseServerFactory(TDextHttpSysEngine.Factory);
App.Run(9000);

// New usage (auto-detect best native engine):
App := WebApplication;
App.UseNativeServer;
App.Run(9000);

// New usage (IOCP with custom options):
App := WebApplication;
App.UseNativeServer(TServerEngineOptions.Create
  .WithIoThreads(8)
  .WithMaxConnections(100000));
App.Run(9000);
```

---

## 4. Implementation Phases

### Phase 1: Engine Interfaces & Types

**Files:**
- `Sources/Server/Dext.Server.Engine.Interfaces.pas`
- `Sources/Server/Dext.Server.Engine.Types.pas`

**Scope:** Define `IDextServerEngine`, `IDextServerConnection`, `IDextWebSocketConnection`, `TServerEngineOptions`, and all shared types.

**Estimated effort:** 3 days

---

### Phase 2: Windows http.sys Engine

**Files:**
- `Sources/Server/Dext.Server.HttpSys.Api.pas` — Windows HTTP API v2 type declarations
- `Sources/Server/Dext.Server.HttpSys.pas` — Engine implementation

**Key Windows API imports** (from `httpapi.dll`):

```pascal
function HttpInitialize(Version: HTTPAPI_VERSION; Flags: ULONG;
  pReserved: Pointer): ULONG; stdcall; external 'httpapi.dll';
function HttpCreateServerSession(Version: HTTPAPI_VERSION;
  var ServerSessionId: HTTP_SERVER_SESSION_ID;
  Reserved: ULONG): ULONG; stdcall; external 'httpapi.dll';
function HttpCreateUrlGroup(ServerSessionId: HTTP_SERVER_SESSION_ID;
  var UrlGroupId: HTTP_URL_GROUP_ID;
  Reserved: ULONG): ULONG; stdcall; external 'httpapi.dll';
function HttpCreateRequestQueue(Version: HTTPAPI_VERSION;
  pName: PWideChar; pSecurityAttributes: Pointer; Flags: ULONG;
  var ReqQueueHandle: THandle): ULONG; stdcall; external 'httpapi.dll';
function HttpReceiveHttpRequest(ReqQueueHandle: THandle;
  RequestId: HTTP_REQUEST_ID; Flags: ULONG;
  pRequestBuffer: PHTTP_REQUEST; RequestBufferLength: ULONG;
  var BytesReturned: ULONG;
  pOverlapped: POverlapped): ULONG; stdcall; external 'httpapi.dll';
// ... etc
```

**Features:**
- HTTP API v2 (Server Sessions, URL Groups, Request Queues)
- Kernel-mode response caching for static files
- Port sharing (coexistence with IIS)
- OS-managed TLS (certificate binding via `netsh http`)
- Worker thread pool processing completion port events

**Estimated effort:** 10 days

---

### Phase 3: Windows IOCP Socket Engine

**Files:**
- `Sources/Server/Dext.Server.Iocp.pas`
- `Sources/Server/Dext.Server.Iocp.HttpParser.pas`

**Architecture:**
```
1. CreateIoCompletionPort (IOCP handle)
2. WSASocket + bind + listen
3. AcceptEx (async accept, pre-allocated)
4. Worker threads: GetQueuedCompletionStatus loop
5. WSARecv (zero-byte read notification)
6. Parse HTTP/1.1 incrementally (TSpan<Byte>)
7. WSASend (response)
```

**HTTP/1.1 Parser requirements:**
- Incremental (may receive partial headers across multiple reads)
- Zero-allocation: parse directly from byte buffer using `TSpan<Byte>`
- Support chunked transfer encoding
- Support keep-alive pipelining

**Estimated effort:** 14 days

#### 3.1 Implementation status (2026-11)

| Area | State |
|---|---|
| Incremental HTTP/1.1 parser, keep-alive, pipelining | Implemented |
| `Date` header, header/body limits (431/413), RFC 9112 request checks (400/501/505), `Connection: close`, HTTP/1.0, `Expect: 100-continue` | In review (#282) |
| Inline completion (`FILE_SKIP_COMPLETION_PORT_ON_SUCCESS`), two-buffer send, per-connection accumulator and object reuse | In review (#282) |
| Chunked request bodies | **Pending.** Until then a request with `Transfer-Encoding` gets `501` (a safe interim: it must never be read as the next request) |
| Idle/header/body timeouts | **Pending.** Same design as the epoll timing wheel (S50, section 3.6) |
| TLS | **Pending.** See S43; the IOCP session must be plugged into `IDextTLSEngine` as `Dext.Server.Epoll` does |
| IPv6, `SO_EXCLUSIVEADDRUSE` | **Pending** |
| Selecting this engine on Windows | **Pending.** `UseNativeServer` always creates the `http.sys` engine on Windows (`TDextNativeWebServer` fixes the choice per platform). `CreateSocketEngine` exists but nothing selects it; the intent is a provider with its own `Factory`, chosen with `UseServerFactory`, like the other providers (Indy, DCS, WebBroker) |

---

### Phase 4: Linux epoll Engine

**Files:**
- `Sources/Server/Dext.Server.Epoll.pas`

**Architecture:**
```
1. epoll_create1(0)
2. socket + bind + listen (non-blocking)
3. epoll_ctl(EPOLL_CTL_ADD, listen_fd, EPOLLIN)
4. Worker threads: epoll_wait loop
5. accept4 (non-blocking accept)
6. Edge-triggered + EPOLLONESHOT for thread-safety
7. eventfd for shutdown signaling
8. recv/send (non-blocking)
```

**Key design decisions:**
- **Edge-triggered + EPOLLONESHOT**: Prevents the same socket event from being dispatched to multiple threads simultaneously
- **eventfd**: Clean shutdown signaling across all worker threads
- **send queue**: Required because epoll doesn't have WSASend-like async completion — must manage partial sends

**Estimated effort:** 14 days (can run in parallel with Phase 3)

---

### Phase 5: Pipeline Integration

**Files:**
- `Sources/Server/Dext.Server.Native.pas` — `IWebHost` adapter
- `Sources/Web/Dext.Web.Interfaces.pas` — extend interfaces
- `Sources/Web/Dext.Web.WebApplication.pas` — `UseNativeServer`

**Scope:**
- Bridge `IDextServerEngine` → `IWebHost` (wrapping raw requests into `IHttpContext`)
- Create `IHttpRequest` / `IHttpResponse` implementations backed by engine buffers
- Reuse existing `TRouteValueDictionary`, `TRequestDelegate`, middleware chain
- Auto-detect platform and select best engine

**Estimated effort:** 5 days

---

## 5. Acceptance Criteria

- [ ] On Windows, `App.UseNativeServer; App.Run(9000)` starts an http.sys-backed server that serves REST endpoints.
- [ ] On Linux, the same code starts an epoll-backed server.
- [ ] Performance: **≥ 2x throughput** vs Indy adapter on equivalent hardware (measured with `wrk`).
- [ ] Concurrent connections: sustain **10,000+** simultaneous connections with < 500MB RSS.
- [ ] All existing middleware, controllers, and Hubs continue to work unchanged.
- [ ] http.sys engine supports port sharing (coexist with IIS on port 80/443).
- [ ] The IOCP engine supports WebSocket upgrade (connection hand-off to S40).
- [ ] Zero external runtime dependencies in the default configuration - no DLLs beyond Windows system libraries. **[DECISION D1]** An optional OpenSSL provider (S43) is opt-in and ships its own DLLs.
- [ ] Graceful shutdown: drain active connections before stopping.
- [ ] The IOCP engine holds 10,000 idle keep-alive connections under 500 MB RSS (measured, not estimated).
- [ ] The HTTP/1.1 parser has a randomized/mutation (fuzz) test in the suite.

---

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| http.sys admin rights required for URL reservation | Deployment complexity | Provide `dext admin register-url` CLI command (like `netsh http add urlacl`) |
| IOCP/epoll complexity → bugs under load | Production stability | Extensive stress testing with `wrk`, fuzzing of HTTP parser |
| HTTP/1.1 parser edge cases | Security (request smuggling) | Study mORMot's parser, follow RFC 9110 strictly, fuzz with HTTP-specific tools |
| epoll thread safety with EPOLLONESHOT | Deadlocks under contention | Follow DCS patterns, extensive concurrent testing |

---

## 7. Future Considerations

- **io_uring** (Linux 5.1+): A future `TDextIoUringEngine` could replace epoll for even higher throughput. The `IDextServerEngine` abstraction supports this transparently.
- **kqueue** (macOS/FreeBSD): A native kqueue engine could be added following the same pattern as epoll. Currently deferred — use DCS adapter.
- **HTTP/3 (QUIC)**: Requires UDP sockets + QUIC protocol implementation. The engine layer's `Bind` method could accept a `TTransportProtocol` enum (TCP/UDP) in a future version.
- **TLS on IOCP/epoll**: see S43. The epoll engine is integrated with `IDextTLSEngine`. For IOCP the provider is an open decision (D1 in section 8).

---

## 8. Open decisions

| # | Decision | Options | Notes |
|---|---|---|---|
| D1 | TLS provider for the IOCP engine on Windows | SChannel (no extra DLL, Windows certificate store, matches the "no DLL" criterion); OpenSSL Memory BIO (already written, same behaviour as Linux); both behind `IDextTLSEngine` | Leaning: both behind the interface. To confirm: SChannel ALPN for `h2` on the supported Windows versions |
| D2 | The socket engine as a provider on Windows | One more provider with its own `Factory`, chosen by the developer, next to Indy, DCS, WebBroker and the native `http.sys`; documented as experimental until timeouts and TLS exist | `UseNativeServer` stays as it is (`http.sys` on Windows, `epoll` on Linux) |
| D3 | Parser fuzzing | Where it lives and which corpus | Section 6 already asks for it |

---

*Created by Cesar Romero & Antigravity AI — June 2026*
