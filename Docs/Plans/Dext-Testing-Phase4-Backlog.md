# Dext Testing — Fase 4 Backlog

**Correction:** the real dashboard is **`DextSidecar.exe`** (`Apps/Sidecar`), not `dext ui`.  
`dext ui` was the first CLI experiment and has been **removed** from the CLI.

## 1. Logs ricos (Explorer)

| Item | Status |
|------|--------|
| Prefixed console tags | Done |
| RichEdit / theme colors | Superseded by ListView (E1.7) |
| Structured Console ListView | Done (E1.7) |
| ANSI in suite EXE console | Low priority |

## 2. Sidecar dashboard: Indy → http.sys + WebSockets/SignalR

| Task | Notes |
|------|--------|
| Prefer http.sys on Sidecar start | Done (`TSidecarServer` + `DEXT_SIDECAR_INDY=1` escape) |
| SignalR first / SSE fallback in UI | Done (`main.js` `hub()` + `DashboardEvent`) |
| Dual-publish BroadcastSSE → Hub + SSE | Done |
| Stdout capture from test run | Done (`TTestRunner.CaptureStdoutAsync`) |
| Field-validate URLACL / http.sys | Human — recompile Sidecar and run without Indy |
| Remove `dext ui` | Done — unit deleted; was not registered in DextTool.dpr |

## 3. Spike — UI Automation (Delphi 13)

See `Dext-Testing-UIAutomation-Spike.md`. Not blocking.

## 4. WebView Windows shell

**Decision:** only if Sidecar tray + embedded browser proves inadequate. Not started.

## Surface map (canonical)

| Surface | Role |
|---------|------|
| Dext Test Explorer | IDE day-to-day suite host |
| DextSidecar | Observability / project dashboard (true dashboard) |
| `dext ui` | **Removed** from CLI |
| Embedded `TDashboardListener` | Old in-process Indy+SSE; stays off unless revived |

## Exit criteria

- [x] Sidecar prefers http.sys + SignalR path in code
- [x] Docs call Sidecar the dashboard; `dext ui` removed from CLI
- [ ] Human: Sidecar rebuild + browse `localhost:3030` without `DEXT_SIDECAR_INDY`

## Product priority note (2026-10)

Embarcadero / book track: **Test Explorer + coverage IDE polish + non-Dext chapter** first.  
Sidecar = essentials only in parallel. Full dashboard/tabs = later.  
See [Dext-Testing-Embarcadero-Roadmap.md](Dext-Testing-Embarcadero-Roadmap.md).
