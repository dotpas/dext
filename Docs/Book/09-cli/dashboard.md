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

## Sending an application's logs to the Sidecar

The Sidecar is **off by default** in every Dext application: the global logger
does not look for it. Turn it on explicitly, with the environment variable

```bash
set DEXT_SIDECAR_ENABLED=true
rem optional: 3030 is the default
set DEXT_SIDECAR_PORT=3030
```

or with `TSidecarOptions` (`Enabled := True`, `Port`) registered in the
application's services. The environment variable wins over the options.

> Earlier versions probed `http://localhost:3030` on the first log call. On
> Windows a closed loopback port takes about 2 s to refuse per address
> (`::1`, then `127.0.0.1`), so every process without a Sidecar paid ~4 s,
> including each test run. The probe was removed.

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
