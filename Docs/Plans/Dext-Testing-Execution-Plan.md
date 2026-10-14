# Dext Testing — Plano de execução (master)

**North star:** livro no mercado + pitch Embarcadero crédível.  
**Ordem de valor:** Explorer → Stack/Coverage → Sidecar essencial // → C++ / features grandes.

Docs satélites (detalhe):  
[Explorer](Dext-Testing-Explorer-Plan.md) · [StackTrace](Dext-Testing-StackTrace-Plan.md) · [Sidecar](Dext-Sidecar-LongTerm.md) · [Embarcadero Roadmap](Dext-Testing-Embarcadero-Roadmap.md) · [Pitch](Dext-Testing-Embarcadero-Pitch.md) · [Catalog](../Dext-Testing-Features-Catalog.md)

---

## Fase E0 — Fundação docs / pitch (quase fechada)

| # | Item | Status |
|---|------|--------|
| E0.1 | Catálogo Testing v1 + PT | Feito |
| E0.2 | Embarcadero Roadmap + Pitch | Feito |
| E0.3 | Cap. 18b livro bookshelf | Redigido (polish Fase 5 livro depois) |
| E0.4 | `dext ui` removido; Sidecar canônico | Feito |

---

## Fase E1 — Test Explorer (prioridade #1)

| # | Item | Status | Notas |
|---|------|--------|-------|
| E1.1 | IDE responsiva no Run All (Wait=False, coalesce, budget UI, history buffer) | Feito | Validar OnIdle/OnSave no uso |
| E1.2 | FAIL no console; PASS silencioso | Feito | |
| E1.3 | Inspector: stack legível (`raw` → linhas) | Feito | |
| E1.4 | Inspector: aviso Debug Trace Options se sem stack | Feito | |
| E1.5 | **Apply Debug Trace Options** (menu OTA no projeto ativo) | Feito | Actions ⋯ → Apply Debug Trace Options |
| E1.6 | Coverage gutter polish (demo Embarcadero) | Feito | Path match; Reload Coverage; `LoadedFileCount` |
| E1.7 | Console Log estruturado (ListView/ícones) | Feito | `FConsoleListView` Time/Kind/Message; dbl-click FAIL→Inspector |
| E1.8 | Coverage run + aba Coverage + gutter column | Feito (v1) | Collect → DCC wrap; dual XML; aba file list; `RequestGutterColumn` (D13); só linhas instrumentadas |
| E1.9 | Passive View: migrar paths restantes → Presenter | Débito | Contínuo, não bloqueia pitch |

**Package:** `Packages/d13/Dext.Testing.Design.dproj` — build verificado (Core → Net → Testing.Core → Testing.Design).

---

## Fase E2 — Stack trace (coleta)

| # | Item | Status | Fontes |
|---|------|--------|--------|
| E2.1 | `IDextStackTraceProvider` + default `Dext.Core.Debug` | Feito | `Dext.Testing.StackTrace` + Runner |
| E2.2 | Capture × format separados; filtro frames RTL/Testing | Feito | `FilterStackTrace` / `ParseStackFrames` / `FormatStackTraceForDisplay` |
| E2.3 | Inspector frames + click → abrir unit:linha | Feito | `FStackFramesListView` + `OpenSourceFileAtLine` |
| E2.4 | Daofy VEH/MAPDATA | Roadmap | Só se E2.1–2.3 insuficientes |

---

## Fase E3 — Sidecar essencial (paralelo, não bloqueia)

| # | Item | Status |
|---|------|--------|
| E3.1 | AutoAttach + start `DextSidecar.exe` + poll `/health` | Feito | `DEXT_ENABLE_SIDECAR_EXPERT` on; `FindSidecarExe`; poll 10× |
| E3.2 | Sessão IDE (paths) + sync; redesign Projects legado | Feito (essencial) | POST `/api/ide/projects` (não `/sidecar/session`) |
| E3.3 | Notificações suite / Sidecar down | Feito (essencial) | LogToIDE + MessageDlg em falha start/health |
| E3.4 | WebView2 / docs / containers tab | Depois | Fora do essencial |

---

## Fase E4 — Embarcadero / livro / C++

| # | Item | Status |
|---|------|--------|
| E4.1 | Demo pitch-ready (Explorer + coverage + 18b) | Pronto para QA manual |
| E4.2 | Polish manuscrito `dext-testing-book-pt` | Contínuo |
| E4.3 | C++ discovery → Expert | Planned | [Cpp-Discovery](Dext-Testing-Cpp-Discovery.md) |

---

## Fase E5 — Roadmap (não iniciar agora)

Contract tests · WireMock-like · Mutation PR · Testcontainers productizado · UIA · Aspire/AppHost · WebView2 full

---

## Ordem de implementação (sprints)

```text
Sprint A:  E1.5 Apply Debug Trace → E1.6 Coverage polish     ✅
Sprint B:  E2.1–E2.2 provider/coleta → E1.7 console          ✅
Sprint C:  E2.3 frames clicáveis → E3.1–E3.3 Sidecar         ✅
Sprint D:  E1.8 Coverage run/tab/gutter v1                   ✅ (checkpoint)
Sprint E:  QA manual E4.1 + Cap. 18b; C++ discovery paralelo  ← agora
```

---

## Definition of Done — “podemos contatar Embarcadero”

- [ ] Explorer Run All sem travar a IDE (validado no uso diário)  
- [ ] Failed + stack (ou aviso Debug Trace + menu Apply)  
- [x] Coverage gutter na demo (v1 — aba Coverage + coluna gutter D13)  
- [x] Cap. 18b + catálogo + pitch anexáveis  
- [x] Sem claim de C++/Sidecar completo / mutation / Testcontainers  

*(Itens de IDE/stack ficam abertos até validação manual prolongada.)*

---

## Checklist QA manual (próximo)

1. Rebuild packages Design + Expert; reiniciar IDE.  
2. Run All — IDE editável; console ListView sem wall de PASS; FAIL com dbl-click → Inspector.  
3. Failed + Debug Trace Mode — frames no Inspector; dbl-click → unit:linha.  
4. Sem stack — checklist + Actions → Apply Debug Trace Options.  
5. Coverage — Collect → Run All → aba **Coverage** (Instr. lines) → dbl-click → gutter só em linhas instrumentadas.  
6. Sidecar — menu Tools → Dext Sidecar → Start; `/health`; Sync IDE Projects.  

---

## Próximas prioridades (após checkpoint)

| Prioridade | Item | Porquê |
|------------|------|--------|
| 1 | QA manual DoD Embarcadero (lista acima) | Fecha E4.1 |
| 2 | Cap. 18b reprodutível no Explorer | Pitch / livro |
| 3 | DCC: mais units no relatório (MAP/filtros) | Coverage “Total 3” em units grandes |
| 4 | E1.9 Passive View (débito) | Manutenção, não bloqueia pitch |
| 5 | E4.3 C++ discovery | Paralelo, não bloqueia Delphi demo |

## Próxima ação

**QA manual** (checklist). Em paralelo opcional: investigar por que DCC só emite poucas linhas em algumas units.
