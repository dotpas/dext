# 📑 S43: Net-Advanced (MessagePack, Permessage-Deflate & Native TLS Architecture)

**Status:** ✅ 100% Validated (Core & Runtime Linux/Windows) | ⏳ SignalR .NET Interop Pending External .NET Env
**Owner:** Cesar Romero & Engineering Team
**Created:** 2026-06-18
**Updated:** 2026-07-30
**Dependencies:** S39 (Native Server Engine), S40 (WebSocket & SignalR Hubs), S41 (HTTP/2 Framing)
**Enables:** Enterprise Native Security (WSS/HTTPS/TLS) across Web Servers (http.sys, epoll, IOCP, Indy), Redis Client (`TDextRedisClient`), REST Client (`TRestClient`), and Raw Sockets without requiring Reverse Proxies.

> **Note (2026-11):** The IOCP engine (S39, Phase 3) is the next consumer of `IDextTLSEngine`; it does not use it yet. The provider choice for Windows (SChannel, OpenSSL or both) is open decision D1 in S39, section 8. Companion documents: [Status](S43-Net-Advanced.Status.md) and [Validation Plan](S43-Net-Advanced.Validation-Plan.md).

---

## 1. Goal & Vision

Establish an abstraction layer and concrete provider implementation for **SSL/TLS Security across the entire Dext Framework**, enabling high-performance, zero-allocation, transparent encryption across all networking modules.

Specifically, this spec covers:
1. **Unified SSL/TLS Abstraction Layer (`Dext.Net.Security.pas`)**: Interface-driven TLS engines (`IDextTLSEngine`, `IDextTLSContextProvider`, `IDextTLSStream`) decoupling transport logic from SSL implementations (OpenSSL 1.1/3.x, Windows Schannel / http.sys, Taurus TLS, Indy fallback).
2. **Native OpenSSL Memory BIO Engine (`Dext.Net.Security.OpenSSL.pas`)**: Zero-copy/low-allocation TLS handshake and framing for raw asynchronous TCP Sockets (`IOCP` on Windows / `epoll` on Linux).
3. **Windows `http.sys` Native SSL Binding**: Direct Windows Kernel SSL configuration and X.509 certificate store integration.
4. **`TDextRedisClient` SSL/TLS Support (`rediss://`)**: Transparent TLS wrapping for raw TCP Redis connections.
5. **`TRestClient` / `THttpClient` Transparent HTTPS**: Unified client SSL configuration.
6. **Fluent DSL & `appsettings.json` Integration**: Uniform, declarative configuration across Web Apps, Redis Client, and HTTP Clients.
7. **Native CLI Certificate Tooling (`dext dev-certs https`)**: 100% pure Pascal CryptoAPI implementation for generating self-signed development certificates with Subject Alternative Name (SAN - `localhost`, `127.0.0.1`), automatic root trust store registration, and zero PowerShell dependencies.
8. **Taurus TLS / OpenSSL 3.x Support**: Modern TLS 1.3 / OpenSSL 3.x integration for Indy-based server engines.
9. **WebSocket Permessage-Deflate & MessagePack Hub Protocol**: Bandwidth and payload optimizations for SignalR and WebSockets.

---

## 2. Component Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                Dext Unified Fluent DSL                                 │
│       App.UseHttps(...)  |  TDextRedisOptions.UseSsl(...)  |  TRestOptions.UseSsl(...) │
└────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                        Dext.Net.Security Abstraction Layer                             │
│       IDextTLSContextProvider  │  IDextTLSEngine  │  IDextTLSStream  │  TDextTLSOptions   │
└────────────────────────────────────────────────────────────────────────────────────────┘
            │                                 │                                │
            ▼                                 ▼                                ▼
┌───────────────────────┐         ┌───────────────────────┐        ┌───────────────────────┐
│ OpenSSL Native Engine │         │ Windows Http.sys      │        │ Fallback / Indy /     │
│ (BIO_s_mem IOCP/epoll)│         │ (Kernel X.509 Store)  │        │ Taurus SSL Providers  │
└───────────────────────┘         └───────────────────────┘        └───────────────────────┘
            │                                 │                                │
            └─────────────────────────────────┼────────────────────────────────┘
                                              ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                     Consumer Framework Modules (HTTPS / WSS / TLS)                      │
│   Web Application (http.sys / epoll)  │  TDextRedisClient  │  TRestClient  │ Raw TCP   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Core Abstraction Specification (`Dext.Net.Security`)

### 3.1 Data Types & Configurations
```pascal
type
  TDextTLSVersion = (tls1_0, tls1_1, tls1_2, tls1_3);
  TDextTLSVersions = set of TDextTLSVersion;
  TDextTLSMode = (tlsmClient, tlsmServer);

  TDextTLSOptions = record
    Enabled: Boolean;
    Mode: TDextTLSMode;
    CertFile: string;
    KeyFile: string;
    RootCertFile: string;
    CertHash: string;         // For Windows Cert Store / http.sys
    StoreName: string;        // Default 'MY'
    Protocols: TDextTLSVersions;
    VerifyServerCertificate: Boolean;
    ALPNProtocols: TArray<string>; // e.g. ['h2', 'http/1.1', 'redis']
    Provider: string;         // 'Auto', 'OpenSSL', 'Taurus', 'HttpSys', 'Indy'
  end;
```

### 3.2 Interfaces
- **`IDextTLSContextProvider`**: Factory interface responsible for creating and configuring SSL contexts (loading keys, certificates, ALPN, and SSL methods).
- **`IDextTLSEngine`**: Asynchronous/Memory-based TLS processing engine. Consumes encrypted incoming wire data and produces plaintext data (and vice-versa) using OpenSSL memory BIOs (`BIO_s_mem`).
- **`IDextTLSStream`**: Synchronous or Task-based wrapper stream over standard `TStream` or raw socket file descriptors.

---

## 4. Specific Implementations & Integrations

### 4.1 Native OpenSSL Engine (Epoll / IOCP / Raw Sockets / Redis)
- **File**: `Dext.Net.Security.OpenSSL.pas`
- Encapsulates dynamic loading of OpenSSL (`libssl` / `libcrypto`, supporting 1.1.1 and 3.x).
- Uses `BIO_s_mem` pairs (`rbio`, `wbio`) so network IO reads encrypted data into `rbio`, `SSL_read` extracts plaintext, `SSL_write` puts plaintext into `wbio`, and `BIO_read` extracts encrypted data for socket transmission.

### 4.2 Windows `http.sys` Native Security
- **File**: `Dext.Server.HttpSys.pas`
- Configures SSL bindings using Windows HTTPS HTTP API parameters (`HTTP_SERVICE_CONFIG_SSL_SET`) or binds port to certificate thumbprints in the Windows Certificate Store.

### 4.3 Taurus TLS / OpenSSL 3.x Integration
- **Files**: `Dext.Web.Indy.SSL.Taurus.pas`, `Dext.inc` (`{$DEFINE DEXT_ENABLE_TAURUS_TLS}`)
- Provides modern TLS 1.3 / OpenSSL 3.x support for Indy web servers using Taurus TLS wrappers.

### 4.4 Development Certificates CLI Tooling (`dext dev-certs https`)
- **File**: `Dext.Hosting.CLI.Commands.DevCerts.pas`
- Pure Pascal CryptoAPI implementation for self-signed X.509 certificate generation with PKCS#1 RSA private key formatting and custom ASN.1 Subject Alternative Name (SAN - `localhost`, `127.0.0.1`) extension encoding.
- Automatic registration in Windows Root Certificate Store (`Root`) for zero-warning browser development.

### 4.5 Redis Client SSL (`TDextRedisClient`)
- **File**: `Dext.Net.Redis.pas`
- Updates `TDextRedisOptions` with `.UseSsl(True)` and `.SslOptions(...)`.
- When SSL is enabled, `TDextRedisClient` wraps its underlying TCP socket stream with `IDextTLSStream` during initial connection prior to issuing `AUTH` / `PING`.

### 4.6 REST Client HTTPS (`TRestClient`)
- **File**: `Dext.Net.RestClient.pas`
- Provides unified SSL certificate validation callbacks, TLS options, and automatic handling of `https://` URLs using the default system or OpenSSL TLS engine.

---

## 5. Implementation Phases & Milestones

- [x] **Phase 1: Architecture & Abstraction (`Dext.Net.Security.pas`)**
  - Define `IDextTLSContextProvider`, `IDextTLSEngine`, `IDextTLSStream`, `TDextTLSOptions`.
  - Add unified configuration integration into `IConfiguration` / `appsettings.json`.
- [x] **Phase 2: OpenSSL Engine & Taurus TLS Integration**
  - Implement `Dext.Net.Security.OpenSSL.pas` (OpenSSL 1.1/3.x Memory BIOs).
  - Implement `Dext.Web.Indy.SSL.Taurus.pas` (Taurus TLS / OpenSSL 3.x / TLS 1.3).
- [x] **Phase 3: Native CLI Certificate Tooling (`dext dev-certs https`)**
  - Implement 100% pure Pascal Windows CryptoAPI RSA key generator and X.509 cert encoder.
  - Implement native ASN.1 encoder for Subject Alternative Name (SAN) extension (`localhost`, `127.0.0.1`).
  - Implement automatic Windows Root Store trust installer with `certutil`.
  - Update `Web.SslDemo` example with dual OpenSSL 1.0.2 & Taurus TLS 1.3 verification.
- [x] **Phase 4: Web Server Testing & Linux/WSL Runtime Validation**
  - Test `http.sys` and `epoll` engines with HTTP/HTTPS (`Web.SslDemo`).
  - Validate native Linux `epoll` server runtime live inside WSL with 100% route success.
  - Validate native Linux test runner (`Dext.Web.UnitTests`) with **133/133 unit tests passed (100% pass rate)**.
  - Validate native OpenSSL 3.x Memory BIO engine and TLS tests on Linux (`Dext.Net.Socket.Tests`).
- [x] **Phase 5: Clients SSL Integration**
  - Test `TRestClient` / `THttpClient` with SSL/HTTPS and explicit `IgnoreCertificateErrors` / `AllowSelfSigned` fluent API.
  - Test `TDextRedisClient` SSL connection capability (`rediss://`) against Memurai on port 6380 (20/20 unit tests passed).
- [x] **Phase 6: Optimization, Permessage-Deflate, MessagePack & High-Load Benchmarking**
  - Implement MessagePack Hub Protocol (`Dext.Web.Hubs.Protocol.MessagePack.pas`).
  - Implement WebSocket Permessage-Deflate (RFC 7692).
  - Execute high-concurrency `bombardier` HTTP load tests (32,338+ RPS, 32 connections, 986µs latency, 11MB RAM working set).

---

## 6. Validation & Current Pending Status

| Component / Feature | Environment | Validation Status | Evidence |
| :--- | :--- | :--- | :--- |
| **OpenSSL 3.x Native Engine** | Windows / Linux (WSL) | ✅ 100% Passed | `Dext.Net.Socket.Tests` (14/14 SSL/TLS tests passed on Linux & Win) |
| **Linux Epoll Engine Runtime** | Linux (WSL2) | ✅ 100% Passed | Live `curl` to `Dext.ServerTest` (`/`, `/hello`, `/time`, `/users/42`) |
| **Dext Web Framework Suite** | Linux (WSL2) | ✅ 100% Passed | `Dext.Web.UnitTests` (133/133 tests passed in 2.58s) |
| **Redis SSL/TLS (`rediss://`)** | Windows (Memurai) | ✅ 100% Passed | Tested with Memurai SSL on port 6380 |
| **HTTPS Enforced Server Demo** | Windows / Linux | ✅ 100% Passed | `Web.SslDemo` (OpenSSL 3.x & http.sys) |
| **High Concurrency Load Test** | Windows / Linux | ✅ 32.3k+ RPS | `bombardier` load test (32 conc, 10s, 0 errors, 11MB RAM) |
| **SignalR .NET Client Interop** | External .NET SDK | ⏳ Pending .NET Env | Unit tests & MessagePack protocol valid; pending `dotnet` CLI setup |

---

*Updated by Cesar Romero & Antigravity AI — July 30, 2026*
