# Sprint E — Checklist QA Embarcadero (DoD)

Validado por **Cesar** (2026-10): Explorer / coverage / Cap. 18b conforme esperado. Sidecar UI **não** faz parte do DoD de pitch (ver notas).

| # | Item | 10.4 | 13.2 | Notas |
|---|------|:----:|:----:|-------|
| 1 | Run All — IDE editável durante compile/run; sem wall de PASS no Console ListView | [x] | [x] | Suite grande OK |
| 2 | FAIL no Console → dbl-click → Inspector | [x] | [x] | |
| 3 | Failed + Debug Trace — frames; dbl-click → unit:linha | [x] | [x] | |
| 4 | Coverage Collect → Run All → aba Coverage → gutter | [x] | [x] | Covered / Not covered / Instrumented |
| 5 | Release / sem MAP → `Coverage (!)` âmbar; sem modal | [x] | [x] | Soft-fail |
| 6 | Generate HTML + Open HTML (Actions **e** contexto aba) | [x] | [x] | E1.9k |
| 7 | Clear Generated Coverage Files | [x] | [x] | |
| 8 | Cap. 18b — `LegacyCobrancaTests` no Explorer | [x] | [x] | [Roteiro](Dext-Testing-Cap18b-Explorer-Demo.md) |
| 9 | Sidecar smoke — Start + `/health` | [x] | [x] | Processo sobe; **aba Testes da SPA quebrada** — ver [Sidecar §1.1](Dext-Sidecar-LongTerm.md) |

**Fora do DoD / próximo ciclo Sidecar:** run na aba Testes (árvore some ao executar); Settings vazio; polish Painel/Projetos/HTTP/Traces/Logs.

**Hold produto:** E1.9 restante (Prev/Next, WebView2 E1.9l, …); E4.3 C++ discovery — após contato Embarcadero / escolha explícita.
