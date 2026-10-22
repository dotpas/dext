# Dext Dashboard (Sidecar)

O dashboard web **real** é o sidecar em bandeja:

```bash
DextSidecar.exe
```

URL padrão: `http://localhost:3030`

No Windows prefere **http.sys** (SignalR/WebSockets); SSE fica como fallback. Para forçar Indy:

```bash
set DEXT_SIDECAR_INDY=1
DextSidecar.exe
```

## Relação com o Test Explorer

| Superfície | Papel |
|------------|--------|
| **Dext Test Explorer** | Host do dia a dia na RAD Studio (árvore, gutter, histórico) |
| **DextSidecar** | Dashboard de observabilidade / projeto |

## Removido: `dext ui`

Experimento antigo de CLI — **removido** do `dext.exe`. Use apenas `DextSidecar.exe`.
