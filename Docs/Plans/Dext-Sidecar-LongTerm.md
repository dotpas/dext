# Dext Sidecar — análise completa e projeto de longo prazo

**Status:** living document (2026-10)  
**Produto canônico:** `Apps/Sidecar/DextSidecar.exe` (bandeja) — **não** `dext ui` (removido do CLI).  
**Companheiro IDE:** Dext Test Explorer (S36) + Expert de menu Sidecar (`Dext.EF.Design.Expert`).

---

## 1. O que o Sidecar é hoje

| Camada | Realidade |
|--------|-----------|
| Shell | VCL + tray; janela opcional; browser externo em `localhost:3030` |
| HTTP | `TWebHost` + `TDashboardRoutes` (compartilhado com o antigo `dext ui`) |
| Transporte | Preferência **http.sys** + SignalR; SSE fallback; Indy via `DEXT_SIDECAR_INDY=1` |
| Compat testes | Porta **8102** (`TTestCompatServer`) paralelo ao Expert |
| UI | SPA em `Sources/Dashboard/main-assets` (HTML/JS/CSS embutidos) |

### Mapa de abas → qualidade

| Aba | Deveria ser | Estado real |
|-----|-------------|-------------|
| **Dashboard** | Home: saúde, cobertura, atividade | Parcial — cards vivos; “Recent Activity” cosmético |
| **Projects** | Sessão IDE viva (não “picker de pasta”) | **Quebrada / legado** — ver §8 |
| **Tests** | Descobrir / rodar / coverage / live | Parcial — AST só `[Test]`/`[TestFixture]`; precisa exe já buildado; rota `/api/tests/run` unificada (projects[] \| project) |
| **HTTP** | Cliente `.http` | Funciona para smoke REST; sem auth/cookies/persistência ricos |
| **Traces** | Spans / Gantt leve | Parcial — depende de sinks ricos no app |
| **Logs** | Terminal live filtrável | Funciona bem com sinks Sidecar |
| **Settings** | Config persistente | UI morta (“coming soon”); APIs existem |

### Peças mortas / aspiracionais

- File watcher: só balloon — não reescaneia nem re-roda testes  
- Settings page, ícones help/notifications: chrome morto  
- Parallel workers / flaky analytics no Sidecar: texto S26, runner oficial é Explorer  
- S23 HTMX redesign completo / Redis sessions: spec ≠ SPA atual  

---

## 2. Divisão de papéis (não misturar)

```text
┌─────────────────────┐  opt-in: health → start → sync   ┌──────────────────────┐
│  RAD Studio         │ ───────────────────────────────► │  DextSidecar (tray)  │
│  Test Explorer S36  │ ◄── notificações / live events ─ │  companion vivo      │
│  = host do dia a dia│                                  │  sessão + observab.  │
└─────────────────────┘                                  └──────────────────────┘
```

| Superfície | Responsabilidade |
|------------|------------------|
| **Test Explorer** | Compile/run na IDE, gutter, histórico local, adapters DUnit* |
| **Sidecar** | Companion: espelha sessão IDE, observabilidade, HTTP, coverage viewer, (depois) docs/scaffold |
| **dext test / CLI** | CI, coverage XML, scaffold/doc por linha de comando |

**Prioridade de produto (Embarcadero / livro):** Test Explorer primeiro; Sidecar = **essencial em paralelo** (não bloqueia pitch).  
**Essencial Sidecar:** companion vivo (AutoAttach + sessão IDE + notificações de teste).  
**Depois:** docs/templates/HTTP polish/WebView2/aba containers (`infra/tests`).  
Ver [Dext-Testing-Embarcadero-Roadmap.md](Dext-Testing-Embarcadero-Roadmap.md).

---

## 3. Opinião: Delphi + WebView2

**Concordo — com limites claros.**

### Por que faz sentido

1. **Shell nativo** (tray, startup, single-instance, menu IDE) fica 100% Object Pascal.  
2. **UI rica** continua HTML/CSS/JS (gráficos, editor `.http`, tema) sem reescrever tudo em VCL.  
3. **Ponte Delphi ↔ UI** (`PostWebMessage` / `ExecuteScript` / host objects): Delphi orquestra testes, FS, scaffold; a página só renderiza.  
4. **http.sys + SignalR** podem continuar *dentro* do processo Sidecar; o WebView aponta para `http://localhost:3030` **ou** virtual host — um processo, sem browser externo obrigatório.  
5. Stack Embarcadero já tem `TEdgeBrowser` / WebView2 Runtime evergreen no Win10/11.

### Riscos / como não errar

| Risco | Mitigação |
|-------|-----------|
| Lógica de negócio no JS | Regra: JS só apresentação + eventos; Delphi é fonte da verdade |
| Dois “servidores mentais” | Um host http.sys; WebView é cliente embutido |
| Runtime WebView2 | Documentar evergreen; ship `WebView2Loader.dll` |
| Debug difícil | Dev mode: abrir também no Chrome; source maps |
| “Rewrite total” engole o essencial | Fase A: host+ponte testes; Fase B: embutir WebView; não bloquear observability |

### Alternativa rejeitada por enquanto

App 100% VCL sem HTML — custo alto para logs/charts/editor HTTP.  
Manter só browser externo — ok curto prazo; WebView melhora “app de bandeja” e conversa Delphi↔UI.

**Veredito:** projeto de longo prazo = **Sidecar VCL + WebView2 + http.sys/SignalR**, com Explorer como runner IDE. Não é opcional filosófico; é a forma correta de um tooling Windows moderno em Delphi.

---

## 4. Visão por capacidade (como *deveria* ser)

### 4.1 Logging / métricas / traces (essencial)

**Objetivo:** qualquer projeto Dext (ou Delphi) pluga em 3 linhas e vê no Sidecar.

| Peça | Contrato desejado |
|------|-------------------|
| Sink | Já existe `Dext.Logging.Sinks.Sidecar` — documentar como default DX |
| API | `POST /api/telemetry/logs|events|metrics` estável + schema versionado |
| UI | Logs filtráveis por app/nível; métricas com janela de tempo; traces com lista + detalhe |
| Zero config | Sidecar em `localhost:3030`; app detecta `/health` |

**Fora do essencial agora:** Gantt DataDog-completo, virtual scroll infinito, Redis.

### 4.2 Testes + coverage (essencial — ponte IDE)

**Como deve ser:**

1. Expert/Explorer **já** synca projetos (`/api/ide/projects`) — reforçar e tornar a aba Tests consumidora disso como fonte primária.  
2. Sidecar **não** compete no compile OTA; dispara o mesmo canal do Explorer **ou** recebe eventos live (pass/fail) via hub.  
3. Coverage: visualizar HTML/XML já gerado por `dext test --coverage` / Explorer.  
4. Notificações: hub `DashboardEvent` / balloon quando suite termina.

**Bugs a matar primeiro:** descoberta além de `[Test]`/`[TestFixture]`; não exigir path mágico do exe sem feedback claro. (`/api/tests/run` duplicado — corrigido.)

### 4.3 HTTP client (melhorar, não reinventar)

Manter `.http` (compat VS Code/Rider). Próximos passos úteis: variáveis de ambiente, histórico em disco, cookies de sessão, auth bearer simples. Não virar Postman completo no essencial.

### 4.4 Documentação HTML (fase seguinte)

CLI já tem `dext doc` / DocGen. Sidecar = **abrir/gerar/preview** no workspace, não reimplementar o gerador na SPA.

### 4.5 Scaffolding + templates (fase seguinte)

CLI `dext scaffold` / `new` já existem. Sidecar = UI wizard que chama as mesmas engines Pascal. Templates = catálogo versionado (como `dotnet new`).

### 4.6 Mercado (o que copiar / superar)

| Referência | Lição para o Sidecar |
|------------|----------------------|
| **.NET Aspire Dashboard** | Observabilidade local first-class, um processo |
| **Seq / Grafana Loki** | Logs structured + filtro rápido |
| **VS / Rider Test Explorer** | Explorer IDE; Sidecar não substitui |
| **Bruno / REST Client** | `.http` como arquivo de verdade |
| **Swagger UI / Scalar** | Preview de docs gerados |
| **dotnet new / Yeoman** | Templates com metadados |

Dext diferenciação: **Object Pascal nativo + IDE Embarcadero + um sidecar Windows** — não um dashboard web genérico na nuvem.

---

## 5. Roadmap essencial (fases)

### Fase S0 — Plataforma (agora)

- [x] Tray icon estável  
- [x] http.sys preferido no Sidecar  
- [x] Remover `dext ui` do CLI  
- [ ] Validar URLACL / SignalR no campo  
- [x] Corrigir `/api/tests/run` duplicado  
- [ ] Documentar sinks Sidecar como “hello observability”

### Fase S0.5 — Companion vivo + Projects (§8)  ← prioridade imediata

- [ ] Config **runtime** `Sidecar.AutoAttach` (não só ifdef)  
- [ ] Expert: health → start **`DextSidecar.exe`** → poll → sync  
- [ ] `POST /shutdown` + stop correto; paths completos no sync  
- [ ] Redesign aba Projects = sessão IDE (não folder picker first)  
- [ ] Notificações: sync / suite / Sidecar down (IDE + tray + hub)  
- [ ] Settings mínimos: AutoAttach + path do exe + porta  

### Fase S1 — Observability MVP

- Pacote “plug and play”: log + métrica + span mínimos  
- UI Logs/Traces/Dashboard sem Settings mortos  
- Apps detectam Sidecar via `/health` (mesmo contrato do Expert)

### Fase S2 — Tests bridge

- Aba Tests alimentada pela **sessão** (§8), não por scan solto  
- Live results (Explorer → Sidecar hub **ou** TestCompat unificado)  
- Coverage viewer confiável  
- Mensagens claras quando exe não existe

### Fase S3 — WebView2 shell

- Form principal = `TEdgeBrowser` / WebView4Delphi apontando ao host local  
- Bridge: Delphi commands (`RunTests`, `OpenFile`, `Scaffold`)  
- Browser externo vira fallback Dev

### Fase S4 — DX expandido

- HTTP client polish  
- Docs HTML preview  
- Scaffold/templates UI  
- File watcher útil (re-scan / watch mode opcional)

---

## 6. Decisões explícitas

| Decisão | Escolha |
|---------|---------|
| Dashboard canônico | **DextSidecar** |
| `dext ui` | **Removido** (unit deletada; não estava no `DextTool.dpr`) |
| Runner dia a dia | **Test Explorer** |
| Shell longo prazo | **VCL + WebView2** |
| Transporte | **http.sys + SignalR**, SSE fallback |
| Escopo imediato | **S0.5 essencial** em paralelo ao Explorer/livro — não S4 |
| Projects | Sessão IDE (§8), não registry YAML solto + picker |
| Auto-start | Opt-in runtime; binário = `DextSidecar.exe` |

---

## 7. Próximo passo de implementação sugerido

1. ~~Fix `MapPost('/api/tests/run')` duplicado~~ (feito).  
2. **S0.5:** corrigir Expert (`FindSidecarExe` → `DextSidecar.exe`, poll `/health`, stop graceful) + config `AutoAttach`.  
3. **S0.5 UI:** redesign mínimo da aba Projects (§8.2) + sync com paths.  
4. Spec curta **S-Sidecar-Tests-Bridge** em cima da sessão.  
5. Spike WebView2 depois que o companion estiver útil sem browser embutido.

---

## 8. Projects quebrada — redesenho + companion vivo

### 8.1 Por que está quebrada (auditoria)

A aba nasceu como **browser de pasta + scan de disco**, não como espelho do trabalho na IDE.

| Problema | Evidência |
|----------|-----------|
| Dois mundos | Home usa `GET /api/projects` (`~/.dext/projects.yaml`); aba Projects usa `GET /api/workspace/scan` + `localStorage` |
| IDE sync não persiste | `POST /api/ide/projects` só faz SSE `workspace_sync` — **não** chama `TProjectRegistry.RegisterProject` |
| Paths incompletos | Scan devolve **nomes** de `.dproj`; header/select perdem path absoluto |
| Docs sempre vazios | `docs: []` hardcoded no scan e no sync |
| Expert desligado | `DEXT_ENABLE_SIDECAR_EXPERT` comentado em `Dext.inc` |
| Auto-start morto | `StartSidecar` lança `"dext.exe" sidecar` — **não existe** no CLI; canônico é `DextSidecar.exe` |
| Stop destrutivo | `taskkill /f /im dext.exe` — mata o CLI, não o tray |
| Watcher teatro | `TDextFileWatcher` no CWD do Sidecar → só balloon |
| Gate compile-time | Usuário não liga “Sidecar vivo” sem rebuild do package |

Arquivos: `main-assets/main.js`, `Dext.Dashboard.Routes.pas`, `Dext.EF.Design.Expert.pas`, `Dext.inc`, `Main.Form.pas` (watcher).

### 8.2 O que Projects **deve** ser

Renomear conceitualmente para **Sessão** (UI pode continuar “Projects” no curto prazo).

**Fonte da verdade = grupo de projetos abertos na RAD Studio** (quando companion ativo).  
Pasta manual vira ação secundária: “Abrir pasta…” para quem não está na IDE.

```text
Sessão ativa
├── Origem: IDE | Pasta local
├── Projetos (path completo, ativo marcado)
├── Testes relacionados (descobertos / last run)
├── Artefatos: .http, coverage HTML/XML, docs gerados
├── Estado Sidecar: linked · last sync · health
└── Ações: Abrir no Explorer IDE · Rodar testes · Abrir coverage · Sync agora
```

| Manter | Remover / rebaixar | Adicionar |
|--------|-------------------|-----------|
| Sync IDE + SSE | Grids “scan 8 itens” como UX principal | Badge “ligado à IDE” |
| Abrir pasta (avançado) | Contagem home ≠ sessão | Last sync / projeto ativo |
| Descoberta de testes a partir dos roots | Docs card vazio sem gerador | Links para Tests/HTTP/Logs da sessão |
| | Drag-drop que não entrega path | Watcher nos roots da sessão (opcional) |

Contrato API desejado (evoluir, não scrapear tudo de uma vez):

```json
POST /api/ide/session
{
  "source": "ide",
  "activeProject": "C:\\...\\App.dproj",
  "projects": ["C:\\...\\App.dproj", "C:\\...\\Tests.dproj"],
  "groupFile": "C:\\...\\Group.groupproj"
}
→ registra paths, define sessão, BroadcastSSE("session_sync", ...)
```

Compat: manter `POST /api/ide/projects` como alias fino até a UI migrar.

### 8.3 Companion vivo (a ideia certa)

Modelo de mercado (Aspire Dashboard + host IDE): o dashboard **não compete** com o Test Explorer; a IDE **opta** por anexar um processo local e o fluxo de eventos começa.

**Config (runtime, opt-in):**

| Chave | Default | Onde |
|-------|---------|------|
| `Sidecar.AutoAttach` | `false` | Options do Expert / `config.yaml` / Tools → Dext |
| `Sidecar.ExePath` | auto-discover | instalador + fallbacks (não hardcode `C:\dev\...`) |
| `Sidecar.Port` | `3030` | alinhado a sinks de log |
| `Sidecar.NotifyIde` | `true` | `IOTAMessageServices` + balloon |
| `Sidecar.NotifyTray` | `true` | balloon / futuro toast WebView |

**Loop (quando AutoAttach = true):**

1. Idle pós-load IDE (~1s) e em `ofnActiveProjectChanged` / open group.  
2. `GET /health` — se 200 → sync sessão.  
3. Se down → `CreateProcess(DextSidecar.exe)` (minimizado/tray) → poll `/health` (ex.: 10× 300ms) → sync.  
4. Falha → mensagem IDE clara (path / URLACL), **sem** matar outros processos.  
5. Stop = `POST /api/sidecar/shutdown` (graceful) — nunca `taskkill dext.exe`.

**Notificações (o “começa a notificação”):**

| Evento | IDE | Tray | Hub UI |
|--------|-----|------|--------|
| Sidecar up + sessão sync | `[Dext] Sidecar linked · N projects` | opcional | `session_sync` |
| Sidecar down / falha start | aviso | balloon | badge offline |
| Suite terminou (Explorer) | título / opcional | balloon | `test_complete` |
| Coverage pronto | link path | — | card Dashboard |

Regra: Expert **garante o processo**; Explorer **continua** o runner; Sidecar **mostra e notifica**.

### 8.4 ifdef → runtime

`DEXT_ENABLE_SIDECAR_EXPERT` pode permanecer como kill-switch de build, mas o produto precisa de **AutoAttach em config**. Com AutoAttach off: menus manuais (Start / Open / Sync) bastam. Com on: loop §8.3 sem o usuário lembrar de abrir o tray.

### 8.5 Oportunidades (sem sair do essencial)

Depois que a sessão for real:

- “Projeto ativo” alimenta Tests/HTTP/Logs (um contexto).  
- Coverage do last run no card da sessão.  
- Abrir arquivo/teste na IDE via deep-link Expert (`IOTAModuleServices`).  
- Diff de projetos: adicionou/removeu `.dproj` no group → toast.  
- Modo offline pasta: mesmo modelo de sessão, `source: folder`.

Fora do essencial ainda: templates, docs gen UI, Postman-completo, flaky analytics.

### 8.6 Critério de pronto (S0.5)

1. Com AutoAttach on, abrir a IDE com Sidecar fechado → tray sobe sozinho → aba Projects mostra os `.dproj` do group com **paths**.  
2. Trocar projeto ativo → sessão atualiza sem Refresh manual.  
3. Rodar testes no Explorer → Sidecar notifica (hub e/ou balloon).  
4. AutoAttach off → zero processo fantasma; menus manuais funcionam com `DextSidecar.exe`.
