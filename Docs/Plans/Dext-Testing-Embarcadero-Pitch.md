# Pitch Pack — Dext Testing × Embarcadero / Marco Cantú

**Goal:** Propose Dext Testing tooling as a credible path toward **official Delphi IDE integration** for unit testing quality — without claiming product ownership Embarcadero has not granted.

**Prerequisite:** Catalog v1 + [Embarcadero Roadmap](Dext-Testing-Embarcadero-Roadmap.md). Explorer/coverage gutter demo-ready; Sidecar essentials optional for first contact.

## One-pager (email / PDF blurb)

**Subject:** Native Test Explorer + coverage for RAD Studio — open collaboration proposal

Marco / Embarcadero team —

Delphi still lacks a first-class, modern unit-testing host in the IDE comparable to Visual Studio Test Explorer. **Dext Testing** already ships:

1. **Attribute runner + Fluent Assertions + mocks** (xUnit/Moq/FluentAssertions-class surface in Object Pascal).
2. **Native Dext Test Explorer** (dockable OTA expert): tree, filters, async compile/run, flaky/duration history, **suite trends**.
3. **Legacy bridge:** DUnit / DUnitX / DUnit2 adapters — teams keep existing suites.
4. **CI:** JUnit, xUnit, TRX, HTML, JSON + SonarQube coverage via **`dext test --coverage`** (Stable).
5. **Editor coverage gutter** after Delphi Code Coverage XML (Reload Coverage + path-tolerant gutter).
6. **Failed → stack frames** in Inspector (dbl-click → unit:line) + Apply Debug Trace Options.
7. **Roadmap:** C++Builder Expert path; Sidecar as optional local companion (essentials).

We are publishing a public **.NET → Dext feature catalog**, an **Embarcadero roadmap**, and a book chapter on **testing non-Dext / legacy suites** without rewriting the domain. We would like Embarcadero’s feedback on GetIt packaging, possible co-marketing, and whether pieces of this Expert could inform an official RAD Studio quality workflow.

Happy to demo three scenarios live (15 min).

— Cesar Romero

## Three demos (15 minutes)

| # | Demo | Shows |
|---|------|--------|
| 1 | **Explorer + fail path** | Run All (IDE stays usable) → FAIL in structured console → Inspector frames → dbl-click jump |
| 2 | **Coverage gutter** | `dext test --coverage` → Actions → Reload Coverage → green/red/yellow; Ctrl+Alt+C covering tests |
| 3 | **Legacy / CI** | DUnitX adapter in tree **or** Export JUnit + `dext_coverage.xml` for Sonar / Azure DevOps |

### Script curto (antes da call)

1. Rebuild `Dext.Testing.Design` (+ Expert se Sidecar); reiniciar IDE.  
2. Abrir group com suite de testes; Debug Trace Mode (Actions → Apply) se stack vazia.  
3. Run All → mostrar console ListView (sem wall de PASS) + um FAIL.  
4. Inspector → frames → abrir unit.  
5. Coverage XML → Reload → gutter.  
6. (Opcional) Tools → Dext Sidecar → Start / Open Dashboard.

## Attachments / links

- [Dext-Testing-Features-Catalog.md](../Dext-Testing-Features-Catalog.md)
- [Dext-Testing-Features-Catalog.pt-br.md](../Dext-Testing-Features-Catalog.pt-br.md)
- [Dext-Testing-Embarcadero-Roadmap.md](Dext-Testing-Embarcadero-Roadmap.md)
- Demo Explorer (legacy DUnitX): [`Tests/Samples/Cap18b.LegacyDUnitX`](../../Tests/Samples/Cap18b.LegacyDUnitX/) · [roteiro](Dext-Testing-Cap18b-Explorer-Demo.md)
- Explorer backlog: [Dext-Testing-Explorer-Plan.md](Dext-Testing-Explorer-Plan.md)
- Specs: S36 Test Explorer + refactoring proposal/status

## Ask (pick one primary)

1. Feedback meeting with Delphi PM / IDE team.
2. GetIt listing guidance / partner program path.
3. Blog or CodeRage joint session on “unit testing in RAD Studio 13+”.

## Do not claim

- That Embarcadero has adopted Dext.
- That C++Builder Expert is shipping (discovery / Planned only).
- That Sidecar is a finished Product Dashboard (essentials companion only).
- That Testcontainers / mutation / contract testing already ship.
