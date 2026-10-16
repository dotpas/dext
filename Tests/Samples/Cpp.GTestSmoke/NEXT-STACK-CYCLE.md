# Próximo ciclo — stack DeepCallFail (1 linha)

## Status (2026-10-15 console rebuild)

Breadcrumbs **funcionam** no exe novo (`pendingChars=160`, 3 crumbs). Log console:

```text
NoteFailureStack: END path=breadcrumb pendingChars=160
[0] Auditor… [1] Gateway… [2] DeepCallFail…
```

Sem `--port` o listener Host **não** sobe → não aparece `USING PENDING` / `OnTestEnd`. Próximo passo: **Run DeepCallFail no Explorer** e colar o trecho do log com `OnTestPartResult` / `USING …`.

## Sintoma (ciclo anterior)

Host JSON:

```text
"stacktrace":"[0] DeepCallFail @ SmokeGTestDeep.cpp:21"
```

Isso é o **fallback gtest** (arquivo:linha do `EXPECT`), **não** o capture MAP/breadcrumb.

As mensagens:

- `Ledger::Balance()` / `1 + 2` → só texto da **expressão** do `EXPECT_EQ`, não são frames.
- `intentional fail` / `deep chain fail` → `<<` message do assert.

## O que foi feito

1. `FailureStackScope` + `NoteFailureStack()` em Gateway → Auditor → TEST.
2. Unwind WinAPI / `__builtin_return_address` (Clang Win32 costuma falhar).
3. **Diag log:** `%TEMP%\DextStackCapture.log` (+ OutputDebugString `[DextStack]`).

## Depois do Rebuild (obrigatório)

```text
Project → Clean → Build  (Cpp.GTestSmoke)
apagar %TEMP%\DextStackCapture.log (opcional — fica mais fácil)
Run DeepCallFail / Run All no Explorer
```

Abrir:

```text
%TEMP%\DextStackCapture.log
```

Cada execução começa com:

```text
======== DextStack RUN START ========
banner where=RunDextGTest/host-run
banner exe=…\Cpp.GTestSmoke.exe
banner mapExists=0|1
```

### Se breadcrumbs funcionarem

Procure (nessa ordem):

```text
FailureStackScope PUSH depth=1 … DeepCallFail
FailureStackScope PUSH depth=2 … Gateway
FailureStackScope PUSH depth=3 … Auditor
NoteFailureStack: END path=breadcrumb pendingChars=… (>0)
OnTestPartResult: … crumbs=3
GTestFailureStackOrLocation: USING PENDING
OnTestEnd: POST Failed … stack posted=
  [0] Auditor…
  [1] Gateway…
  [2] DeepCallFail…
```

Stack no Explorer deve ter 3 linhas.

### Se ainda cair no fallback

Procure nesta ordem:

| Log | Significado | Próximo passo |
|-----|-------------|----------------|
| Sem `RUN START` / sem `[DextStack]` | Exe antigo (não rebuildou adapter) | Clean + Build; conferir timestamp do `.exe` |
| `banner mapExists=0` | `.map` fora do dir do exe | Detailed map; copiar/link ao lado do exe |
| Nenhum `PUSH` antes do assert | `FailureStackScope` não no binary / TU velho | Rebuild `SmokeGTestDeep.cpp`; strings no MAP |
| `PUSH depth=3` + `pendingChars>0` mas `USING GTEST FALLBACK` | `TakePending` no `OnTestStart` limpou cedo demais, ou 2º part-result | Ordem dos logs: `clear pending` entre Note e PartResult? |
| `USING PENDING` + `OnTestEnd: stack posted=` multi-linha, UI 1 linha | Bug no Expert (JSON/`\n`) | Olhar Host JSON bruto vs log |
| `CaptureStackBackTrace n=0` | Unwind morto no Clang Win32 | Ignorar WinAPI; confiar em breadcrumbs |

## Checklist próximo ciclo

- [ ] Colar trecho relevante de `DextStackCapture.log` (DeepCallFail completo)
- [ ] Confirmar `SmokeGTestDeep.obj` / `.exe` timestamps pós-Clean
- [ ] Se `depth=0` no NoteFailureStack: inspecionar se `FailureStackScope` está no binary (MAP / strings)
- [ ] Se `USING PENDING` mas UI 1 linha: bug no Expert (parse de `\n` no stacktrace JSON)
