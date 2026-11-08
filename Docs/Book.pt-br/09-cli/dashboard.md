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

## Enviando os logs da aplicação para o Sidecar

O Sidecar vem **desligado por padrão** em toda aplicação Dext: o logger global
não procura por ele. Ligue explicitamente, pela variável de ambiente

```bash
set DEXT_SIDECAR_ENABLED=true
rem opcional: 3030 é o padrão
set DEXT_SIDECAR_PORT=3030
```

ou por `TSidecarOptions` (`Enabled := True`, `Port`) registrado nos serviços da
aplicação. A variável de ambiente vale mais que as opções.

> Versões anteriores testavam `http://localhost:3030` no primeiro log. No
> Windows, uma porta fechada na loopback leva cerca de 2 s para recusar por
> endereço (`::1` e depois `127.0.0.1`), então todo processo sem Sidecar pagava
> ~4 s, inclusive cada execução de testes. O teste foi removido.

## Relação com o Test Explorer

| Superfície | Papel |
|------------|--------|
| **Dext Test Explorer** | Host do dia a dia na RAD Studio (árvore, gutter, histórico) |
| **DextSidecar** | Dashboard de observabilidade / projeto |

## Removido: `dext ui`

Experimento antigo de CLI — **removido** do `dext.exe`. Use apenas `DextSidecar.exe`.
