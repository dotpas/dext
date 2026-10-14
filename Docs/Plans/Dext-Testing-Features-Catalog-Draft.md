# Dext Testing Features Catalog (Draft) — .NET → Dext

**Status:** Fase 0 rascunho → promover a v1 na Fase 1  
**Fonte:** `Docs/Features_Implemented_Index.md` §7  
**Regra:** não inflar o que está desligado ou incompleto.

## Maturidade

| Label | Significado |
|-------|-------------|
| **Stable** | Uso diário; regressões cobertas |
| **Evolving** | Funciona com gaps conhecidos |
| **Preview** | API/UX pode mudar |
| **Planned** | Spec/backlog, sem ship |

## Mapa .NET counterpart → Dext

| .NET / Visual Studio | Dext | Maturidade | Notas |
|----------------------|------|------------|--------|
| xUnit / NUnit / MSTest (attributes) | `Dext.Testing.Attributes` (`[Fact]`, `[Test]`, `[TestCase]`, lifecycle) | Stable | Runner próprio attribute-based |
| xUnit runner / `dotnet test` | `dext test` + suite EXE + Fluent Runner | Stable | Host live = Test Explorer, não dashboard embutido |
| Moq / NSubstitute | `Dext.Mocks` + `Dext.Interception` | Stable | `Mock<T>`, Arg, Times, AutoMocker |
| FluentAssertions | `Dext.Assertions` (`Should`) | Stable | Soft asserts, collections, Throw |
| Verify / snapshot libs | Snapshot testing (`MatchSnapshot`) | Stable | `SNAPSHOT_UPDATE=1` |
| WebApplicationFactory | `TDextApplicationFactory` / `TDextWebApplicationFactory` | Stable | In-process HTTP |
| Coverlet / VS coverage | `dext test --coverage` (Delphi Code Coverage) | Stable (CLI) | HTML/XML + `dext_coverage.xml` Sonar |
| Coverage in editor (VS) | `Dext.Testing.Design.Coverage` gutter | Evolving | Visualizer existe; gutter notifier desligado por lifetime OTA — reabilitar Fase 1 |
| Test Explorer (VS) | Dext Test Explorer (S36) | Evolving | Árvore, filtros, history por método; suite totals = S75 F-10 |
| TestInsight / DUnitX IDE | Adapters DUnit / DUnitX / DUnit2 → Explorer | Stable | Legado sem reescrever suite |
| JUnit / TRX / Azure DevOps | `Dext.Testing.Report` | Stable | JUnit, xUnit, TRX, HTML, JSON |
| SonarQube | `dext_coverage.xml` + reports | Stable | Quality gates |
| OpenTelemetry test metrics | `Dext.Testing.Listeners.Telemetry` | Evolving | Listener dedicado |
| Live suite web dashboard | Embedded Indy+SSE / `dext ui` | Evolving | Redesign http.sys+SignalR = backlog Fase 4 |
| Coded UI / Playwright (desktop) | — | Planned | Spike UI Automation (Delphi 13 VCL UIA) |
| C++ Test Explorer | — | Planned | Discovery Fase 0 → Expert DLL Fase 3 |

## Separação honesta (para Features index / roadmap)

| Camada | Status sugerido | Inclui |
|--------|-----------------|--------|
| **Framework de testes** | Stable | Attributes, Assertions, Mocks, Snapshots, Reports, Adapters DUnit*, Factory web |
| **IDE / Explorer tooling** | Evolving | Expert S36, gutter coverage, suite stats, logs ricos |
| **Dashboard / sidecar UI** | Evolving | `dext ui`, Indy+SSE legado |
| **C++Builder / UI Automation** | Planned | Após discovery + fundação Expert |

## Gaps explícitos (não esconder no pitch)

1. Coverage gutter IDE desabilitado (crash `NotifyDestroyed`) — Fase 1.
2. Suite-total history no Explorer ausente (S75 F-10) — Fase 1.
3. Dashboard live ainda Indy+SSE; livro promete redesign — Fase 4.
4. Sem Explorer C++Builder — Fase 3.
5. Sem harness UI Automation Dext — Fase 4 spike.

## Próximo (Fase 1 catalog v1)

- Publicar versão limpa em `Docs/` (EN + PT-BR resumo).
- Atualizar `Features_Implemented_Index` §7 com labels Stable/Evolving.
- Atualizar `Features_Maturity_Learning_Paths` e `roadmap` Quality.
