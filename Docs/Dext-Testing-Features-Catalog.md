# Dext Testing Features Catalog v1

**Audience:** Embarcadero, partners, book readers, product pitch  
**Source of truth:** [Features_Implemented_Index.md](Features_Implemented_Index.md) §7 + this maturity split

## Maturity model

| Label | Meaning |
|-------|---------|
| **Stable** | Daily use; regressions covered |
| **Evolving** | Ships with known gaps tracked below |
| **Preview** | API/UX may change |
| **Planned** | Spec/backlog / roadmap only |

## Layer split (honest)

| Layer | Maturity | Includes |
|-------|----------|----------|
| Framework de testes | **Stable** | Attributes, Assertions, Mocks, Snapshots, Reports, DUnit/DUnitX/DUnit2 adapters, WebApplicationFactory |
| Coverage (CLI) | **Stable** | `dext test --coverage` → HTML/XML + `dext_coverage.xml` (Sonar) via Delphi Code Coverage |
| Coverage (IDE visual) | **Evolving** | Editor gutter — polish / demo reliability is the gap, not the engine |
| IDE / Test Explorer | **Evolving** | S36 Expert (async run, suite stats, coverage gutter), RichEdit colored console — **#1 product priority** |
| **DextSidecar** | **Evolving** | Tray companion; http.sys + SignalR preferred; **essentials only** for near-term (session/notify) |
| `dext ui` (CLI) | **Removed** | Use DextSidecar only |
| Test containers (`infra/tests`) | **Preview** | Docker Compose multi-DB for ORM integration tests; productize later (± Sidecar tab) |
| C++Builder Expert | **In review** | Win64x line coverage is in the Explorer. Full C++ support, GetIt and a signed DLL are still open. See S75. |
| UI Automation harness | **Planned** | Spike on Delphi 13 VCL UIA |

## .NET / Visual Studio → Dext map

| .NET / VS | Dext | Maturity |
|-----------|------|----------|
| xUnit / NUnit / MSTest attributes | `Dext.Testing.Attributes` | Stable |
| `dotnet test` | `dext test` + suite EXE | Stable |
| Moq / NSubstitute | `Dext.Mocks` + Interception | Stable |
| FluentAssertions | `Dext.Assertions` (`Should`) | Stable |
| Verify / snapshots | `MatchSnapshot` | Stable |
| WebApplicationFactory | `TDextApplicationFactory` | Stable |
| Coverlet | `dext test --coverage` | **Stable** (CLI) |
| Coverage in editor | Design.Coverage gutter | **Evolving** (visual IDE polish) |
| Test Explorer | Dext Test Explorer (S36) | Evolving |
| DUnitX / TestInsight | Native adapters → Explorer | Stable |
| JUnit / TRX / Sonar | `Dext.Testing.Report` | Stable |
| Suite trend charts | `suite_history.json` in Explorer (S75 F-10) | Evolving |
| Observability dashboard | **DextSidecar** (`localhost:3030`) | Evolving (essentials) |
| Testcontainers | `infra/tests` Docker + scripts | Preview |
| HttpClient / typed REST | `Dext.Net.RestClient` (full stack) | **Stable** (complementary; not a testing gap) |
| Coded UI / desktop UIA | — | Planned |
| C++ Test Explorer | — | Planned |

## Related (ORM / networking — not testing gaps)

| Area | Status |
|------|--------|
| Databases | PostgreSQL, SQL Server, MySQL, SQLite, Oracle, Firebird, **InterBase** — all **Stable** |
| REST client | Complete fluent client (resilience, mTLS, compression, OTel) — **Stable** |

## Known gaps (do not hide in outreach)

1. Coverage **CLI is done**; IDE gutter needs visual/reliability polish for demos.
2. Sidecar companion (AutoAttach / session) is essentials-track — not a blocker for book/pitch.
3. C++Builder Expert not shipped as ready (discovery + scaffold only) — call it **Planned**. C++ line coverage, when it is shown, is Win64x (`bcc64x`) via llvm-cov. The Explorer hides coverage settings on any other `.cbproj` platform. Win32 and classic Win64 do not get line coverage. See S75.
4. UI Automation = spike only.
5. Contract tests / mutation / WireMock-like / productized Testcontainers = **roadmap** (see Embarcadero Roadmap P2).

## Post-1.0 roadmap (large features — not current sprint)

Contract/consumer-driven tests · HTTP stub server · PR-scoped mutation · property-based/fuzz · Testcontainers API + optional Sidecar tab · VCL UIA · full WebView2 shell · Aspire/AppHost (cloud roadmap).

## Related docs

- [S36 IDE Test Runner](Specs/S36-IDE-Test-Runner.md)
- [CLI/Sidecar dashboard book](Book/09-cli/dashboard.md)
- [infra/tests](../infra/tests/README.md)
- PT-BR: [Dext-Testing-Features-Catalog.pt-br.md](Dext-Testing-Features-Catalog.pt-br.md)
