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
- [x] **E1.8b Coverage UX v1** — aba **Coverage** (file/%/Instr.), dbl-click → open; gutter via `RequestGutterColumn` (D13); cores BGR; só linhas instrumentadas (sem var/procedure/blank)  


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
| Coverage run (tool + wrap + load + aba) | Feito v1 (E1.8 / E1.8b) |
| C++ | Planned (package Design.Cpp esboço) |

---

## 3. Débito Passive View

`DockableForm` ainda orquestra compile multi-project, coverage load, telemetria, menus. Meta: Presenter dono de run/stop/refresh; form = view.

---

## 4. Prioridades

### P0 — agora
1. Responsividade Run All — **código feito**; validação humana  
2. Coverage gutter + run — **E1.6/E1.8 feito**; demo: Enable Collect → MAP → Run All → gutter  

### P1
3. Console Log estruturado — **E1.7 feito**  
4. Wire Presenter / migrar paths restantes  
5. Cap. 18b reprodutível  
6. Coverage: `tests=` / Show Covering Tests com dados reais (DCC não emite) — futuro  

### Demo E1.8 (checklist)
1. Configurations → *Collect code coverage* (ou Actions → Install / Locate CodeCoverage).  
2. Actions → Apply Debug Trace Options → rebuild (MAP detalhado).  
3. Run All → console: `Coverage: using …` + wrap; ao fim `Coverage loaded: N file(s)`.  
4. Aba **Coverage** → lista Instr.; double-click abre unit → gutter só em linhas do relatório.  
5. Coverage off → Run All sem wrap (comportamento anterior).  
6. Reload Coverage após `dext test --coverage` externo.

### P2
6. AST Play icons · C++ · UIA · Sidecar tabs extras  
7. Coverage: mais units/linhas no XML DCC (hoje o relatório pode ser muito esparso)  

### Checkpoint
Branch de trabalho: `feature/testing-explorer-coverage` (2026-10) — Explorer E1 + stack E2 + coverage v1 + docs/plans.

---

## 5. Critérios pitch-ready

1. Run All: IDE editável e Explorer clicável durante compile+run.  
2. Console: falhas/analytics legíveis (structured), sem wall de PASS.  
3. Gutter pós-coverage.  
4. Cap. 18b verde no Explorer.  
