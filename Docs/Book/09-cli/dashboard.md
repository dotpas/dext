# Dext Dashboard (Sidecar)

The **real** web dashboard is the tray sidecar:

```bash
# build output — name may vary by config
DextSidecar.exe
```

Default URL: `http://localhost:3030`

It hosts live logs, tracing, test runner UI, coverage summaries, and project tools. On Windows it prefers **http.sys** so SignalR can use WebSockets (SSE remains the automatic fallback). To force Indy:

```bash
set DEXT_SIDECAR_INDY=1
DextSidecar.exe
```

## Relationship to the IDE Test Explorer

| Surface | Role |
|---------|------|
| **Dext Test Explorer** | Day-to-day suite host inside RAD Studio (compile/run tree, gutter, history) |
| **DextSidecar** | Observability / project dashboard (logs, telemetry, optional test run UI) |

## Removed: `dext ui`

`dext ui` was an early CLI-only experiment and has been **removed** from `dext.exe`. Use `DextSidecar.exe` only.

## Features (Sidecar)

- Code coverage summaries and project registry
- Real-time logs / telemetry (SignalR preferred, SSE fallback)
- Test discover/run APIs (`/api/tests/...`)
- Streamable sessions (`/sidecar/session`, `/sidecar/events`)

## Theme Toggle

Click the sun/moon icon in the header to switch between dark and light themes. Preference is saved in localStorage.
