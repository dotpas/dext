# Dext Test Explorer — plano de melhorias e refactor

**Package:** [`Packages/d13/Dext.Testing.Design.dproj`](../../Packages/d13/Dext.Testing.Design.dproj) (`Dext.Testing.Design.dpk`)  
**Sources:** `Sources/Testing/Design/` (`DockableForm`, `Presenter`, `Server`, `Coverage`, `Gutter`, `AST`, `Expert`, `Registration`)  
**Prioridade produto:** #1 para Embarcadero / livro — ver [Embarcadero-Roadmap](Dext-Testing-Embarcadero-Roadmap.md)

Specs de origem:

| Doc | Papel |
|-----|--------|
| [S36-IDE-Test-Runner.md](../Specs/S36-IDE-Test-Runner.md) | Spec funcional |
| [S36-IDE-Test-Runner-Refactoring-Proposal.md](../Specs/S36-IDE-Test-Runner-Refactoring-Proposal.md) | Proposta MVP |
| [S36-IDE-Test-Runner-Refactoring-Status.md](../Specs/S36-IDE-Test-Runner-Refactoring-Status.md) | Status Fase 1 |

---

## 1. Problemas reportados (2026-10) — P0

### 1.1 IDE irresponsiva durante Run All

**Sintoma:** ao rodar todos os testes de um projeto, não dá para editar código, selecionar teste no tree, nem ler o Console Log.

**Causas (código real — `DockableForm`, não o Presenter async):**

| Causa | Onde | Efeito |
|-------|------|--------|
| `BuildProject(cmOTAMake, False, **True**)` | `RunActiveProjectTests` | **Wait=True** bloqueia a UI thread na compilação (~segundos; no print: Tests 0,93s / Total 14,38s) |
| Comentário mentia | “Returns immediately” | Frase errada; Wait era True |
| `RecordTestResult` por teste | `TTelemetryTracker` | **Read + parse + write** de `history.json` a cada resultado na UI thread (×230 = IDE morta) |
| `LogMsg` → `DetailsMemo.Update` | cada linha | Paint síncrono em massa |
| `LogMsg('Result received…')` em todo PASS | `OnTestResultReceived` | Centenas de linhas inúteis no RichEdit |

**Presenter async existe** (`CompileAndRunTests` + `TTask.Run`), mas **Run All do form não usa o Presenter** (`FPresenter` ausente no DockableForm).

**Fixes aplicados:**

- [x] `BuildProject(..., Wait=False)` nos três call sites  
- [x] Buffer de `RecordTestResult` → flush uma vez no fim da suite  
- [x] Remover `DetailsMemo.Update` de `LogMsg`  
- [x] Não logar PASS individual (“Result received”)  
- [x] **Server:** coalescer `TThread.Queue` (um drain por burst, não 1 msg/teste)  
- [x] **Form:** fila + flush com budget ~12 ms + `ForceQueue` (cede à IDE entre fatias)  
- [x] Índice `FNodeByName` (sem scan linear da árvore por teste)  
- [x] Labels/progress 1× por fatia; sem `InvalidateRect` por nó durante batch  

**Validação (2026-10):**

- [x] Run All bem mais rápido; brief stalls ocasionais — **aceitável por enquanto**  
- [x] PASS individual omitido no console (ok)  
- [x] FAILED/ERROR sempre no console (nome + error + stack)  
- [ ] Uso prolongado OnIdle/OnSave + interação durante suite  
- [ ] Ligar Run All ao Presenter async (opcional)  
- [x] Console estruturado (ListView) — E1.7 (`FConsoleListView` Time/Kind/Message)  
- [x] Inspector: stack legível + aviso Debug Trace Options se vazio — [StackTrace-Plan](Dext-Testing-StackTrace-Plan.md)  
- [x] Coverage gutter polish + Reload Coverage — E1.6  
- [x] **E1.8 Coverage run** — Find/Install `CodeCoverage.exe` (shared `Dext.Testing.CodeCoverage.Tool`), opt-in *Collect code coverage*, wrap Run All sob DCC (`-xml -xmllines -ife -tec -twd`), parser dual Sonar + `linehits`, discovery sem path hardcoded  
- [x] **E1.8b Coverage UX v1** — aba **Coverage** (file/%/Instrumented), dbl-click → open; gutter via `RequestGutterColumn` (D13); cores BGR; só linhas instrumentadas (sem var/procedure/blank)  
- [x] **E1.8c Coverage UX v1.1** — soft-fail MAP (log + aba `Coverage (!)` âmbar, sem modal); limpa grid/gutter em falha; header agregado Covered/Not covered/Instrumented; **HTML opt-in** (default false); Open/Clear desabilitados sem arquivos; coluna `%` só numérico  
- [x] **E1.9k** — Open HTML no **contexto da aba Coverage** (+ Actions ⋯)

### 1.2 Console Log visual (JetBrains / VS)

**Sintoma (print):** aba Console Log = dump monoespaçado com timestamps + tags `[PASS]`/`[LOG]`/`[FAIL]` + tabela ASCII de history/trend.

**Direção (não é polish cosmético — é UX do host):**

Substituir `TRichEdit` dump por um **structured output pane**:

```text
┌ Console / Output ─────────────────────────────────────┐
│ [filtros: All | Errors | Warnings | Analytics] [Clear]│
├──────┬──────────┬─────────────────────────────────────┤
│ icon │ time     │ message                             │
│ ●    │ 16:44:03 │ Suite started · 230 tests           │
│ ✓    │ 16:44:03 │ (agregado) 230 passed — ocultar PASS│
│ ✕    │ …        │ Failed: Foo.Bar — click → Inspector │
│ 📈   │ …        │ PERF REGRESSION · …                 │
│ 📊   │ …        │ Suite history (expandível)          │
└──────┴──────────┴─────────────────────────────────────┘
```

| Escolha | Decisão |
|---------|---------|
| Controle | `TListView` (vsReport) **ou** VirtualTreeView se já no repo; TreeView só se history/analytics forem nós expandíveis |
| PASS spam | **Não listar** cada PASS; summary + só Fail/Skip/Error/Analytics/Info de compile |
| Cores/ícones | ImageList alinhado ao tree (verde/vermelho/âmbar/info) |
| Click | Fail → seleciona nó na árvore + abre Test Inspector |
| History / trend | Nó ou card expandível — não ASCII `===` |
| RichEdit | Remover da aba Console (pode ficar só para export/copy raw opcional) |

**Fase:** E1.7 feito (`FConsoleListView`). Filtros All/Errors/Analytics = polish opcional.

---

## 2. Estado geral

| Área | Estado |
|------|--------|
| Package decouple | Feito |
| Winsock Stop | Feito |
| Presenter async | Existe, **não wired** ao form Run All |
| Suite trends | Feito |
| Coverage gutter | Feito (E1.6 + coluna D13) |
| Coverage run (tool + wrap + load + aba) | Feito v1.1 (E1.8 / E1.8b / E1.8c) |
| C++ | Discovery — mesmo BPL + `CPlusPlusBuilder.Personality` (scaffold `.Cpp` removido) |

---

## 3. Débito Passive View

`DockableForm` ainda orquestra compile multi-project, coverage load, telemetria, menus. Meta: Presenter dono de run/stop/refresh; form = view.

---

## 4. Prioridades

### P0 — agora
1. Responsividade Run All — **código feito**; validação humana  
2. Coverage gutter + run — **E1.6/E1.8/E1.8c feito**; demo: Enable Collect → MAP → Run All → gutter / HTML  

### P1
3. Console Log estruturado — **E1.7 feito**  
4. Wire Presenter / migrar paths restantes  
5. Cap. 18b reprodutível  
6. Coverage backlog E1.9 (abaixo) — próximo ciclo  

### Demo E1.8 (checklist)
1. Configurations → *Collect code coverage* (ou Actions → Install / Locate CodeCoverage).  
2. Actions → Apply Debug Trace Options → rebuild (MAP detalhado).  
3. Run All → console: `Coverage: using …` + wrap; ao fim `Coverage loaded: N file(s)`.  
4. Aba **Coverage** → header agregado + Not covered + Instrumented + `%` numérico; double-click abre unit → gutter.  
5. Configurations → *Also generate HTML* (off por default) → Run All → **Open HTML** no contexto da aba **ou** Actions; **Clear Generated Coverage Files** quando houver artefatos.  
5b. Cap. 18b → [roteiro](Dext-Testing-Cap18b-Explorer-Demo.md) com `LegacyCobrancaTests`.  
6. Release / sem MAP → aba `Coverage (!)` âmbar (sem modal); testes seguem.  
7. Coverage off → Run All sem wrap.  
8. Reload Coverage após `dext test --coverage` externo.

### P2
6. AST Play icons · C++ · UIA · Sidecar tabs extras  
7. Coverage: densidade do XML DCC (hoje pode ser esparso)  

### Checkpoint
Branch de trabalho: `feature/testing-explorer-coverage` (2026-10) — Explorer E1 + stack E2 + coverage v1.1 + docs/plans.

---

## 4.1 Coverage — backlog futuro (E1.9+)

Mesma fonte que o [delphi-code-coverage-wizard-plus](https://github.com/MHumm/delphi-code-coverage-wizard-plus): `CodeCoverage.exe`. O Wizard mostra o HTML; nós integramos XML + gutter na IDE. **Não** recriar o viewer HTML — abrir o do DCC (E1.8c). Inspiração .NET: dotCover / VS Coverage / Coverlet+ReportGenerator.

| # | Ideia | Esforço | Nota |
|---|--------|---------|------|
| E1.9a | Owner-draw barra de % colorida (verde) na grid | M | Hoje: só `NN%` (ASCII bar removida) |
| E1.9b | Prev/Next uncovered no editor ativo | M | Como widget do HTML DCC / dotCover |
| E1.9c | Filtro lista (&lt;80%, busca nome) | M | |
| E1.9d | “Stale coverage” se relatório ≠ esta run / config | M | Evita confusão Debug→Release |
| E1.9e | Diff coverage (só linhas do git diff) | G | Alto valor pitch; precisa git + line map |
| E1.9f | Exclude gerado/terceiros melhor no `units.lst` | M | |
| E1.9g | Export Cobertura/LCOV p/ CI + badge | M | Pipeline; ReportGenerator |
| E1.9h | Branch / partial coverage rico | G | Limite do DCC |
| E1.9i | `tests=` / Show Covering Tests com dados reais | G | DCC hoje não emite bem |
| E1.9j | Full-line highlight no editor (opcional) | G | HTML já faz; gutter IDE é o default |
| E1.9k | Open HTML no **contexto da aba Coverage** (+ manter Actions ⋯) | P | **Feito** — menu da ListView; dbl-click continua = `.pas` |
| E1.9l | Open HTML **na IDE via WebView2** (opcional) | G | Default browser. In-IDE só se WebView2 disponível; fallback browser. **Hold** até após DoD; alinhar Sidecar WebView2. |

**UX HTML (acordado 2026-10):** Configurations = só *Generate HTML* (opt-in, default off). Abrir = contexto Coverage + Actions. WebView2 = E1.9l depois do DoD.

**Cap. 18b demo:** [Cap18b-Explorer-Demo](Dext-Testing-Cap18b-Explorer-Demo.md) · sample `Tests/Samples/Cap18b.LegacyDUnitX/`.

**DoD Delphi (Sprint E):** fechado 2026-10 — ver [SprintE-QA-Checklist](Dext-Testing-SprintE-QA-Checklist.md).  
**Hold pós-DoD:** E1.9 restante (Prev/Next, E1.9l WebView2, …) e E4.3 C++ discovery — escolher vs Sidecar E3.5 no Sprint F.

---

## 5. Critérios pitch-ready

1. Run All: IDE editável e Explorer clicável durante compile+run.  
2. Console: falhas/analytics legíveis (structured), sem wall de PASS.  
3. Gutter pós-coverage.  
4. Cap. 18b verde no Explorer.  
