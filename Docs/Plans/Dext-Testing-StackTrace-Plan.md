# Stack Trace — coleta e UX (4 fontes → melhorias Dext)

**Goal:** traces legíveis no Explorer + coleta confiável no suite EXE, sem depender de madExcept/Eureka no default.

**Nota:** fontes externas (Daofy, RadIA, DUnitX, LeakCheck) vivem **fora** deste repositório (workspace / clones). Aqui só nomes e ideias — sem paths para árvores irmãs.

---

## 1. Quatro fontes

| # | Projeto | Onde (conceito) | O que roubar |
|---|---------|-----------------|--------------|
| 1 | **Dext.Core.Debug** (atual) | `Sources/Debug/Dext.Core.Debug.pas` (neste repo) | Hook RTL + `.map` + `E.StackTrace` — **baseline a evoluir** |
| 2 | **Daofy StackTrace** | projeto Daofy (externo) | VEH, MAPDATA tokenizado, exception.log, callgraph |
| 3 | **RadIA** | plugin RadIA (externo) | **Parse de frames** multi-formato + resolve unit + confiança — ver §1.1 |
| 4 | **DUnitX** | DUnitX (GetIt / clone externo) | **Provider pluggable**; JCL/madExcept/Eureka adapters |
| 5 | **delphi-leakcheck** | LeakCheck (externo) | Separar **captura** × **formatação**; formatters MAP/JCL |

### 1.1 RadIA — o que os commits novos mudam para o Dext

Commits relevantes no plugin (ex.: `3f0d0fea` *cross-unit stack trace diagnostics*, `a667970f` *semantic symbol reference navigation*):

| Capacidade nova / reforçada | Uso no Dext Explorer |
|-----------------------------|----------------------|
| `AnalyzeProjectStackTrace` tool | Modelo para API interna do Inspector |
| DetectFormat: `delphi` / `madexcept` / `eurekalog` | Aceitar traces de suítes que usem esses formatos |
| `ParseFrame` → file + line + method + **Resolved** + **Confidence** | ListView de frames (P2) |
| Resolve unit no workspace / por método (semantic) | Double-click → OTA open file:line |
| Testes `RadIA.Tests.StackTraceAnalysis` | Espelhar casos de parse nos testes Dext |

**Não** linkar o package RadIA no Design nem paths de clones externos: **copiar o padrão** (regex + frame record + resolve), não a dependência IDE/AI.

---

*(Tabela com 4 externos + baseline Dext = 5 linhas de comparação.)*

### Matriz rápida

| Capacidade | Dext hoje | Daofy | RadIA | DUnitX | LeakCheck |
|------------|-----------|-------|-------|--------|-----------|
| Hook `E.StackTrace` | Sim | Sim (rico) | Não (consome texto) | Via provider | Captura própria |
| Resolve `.map` | Sim (lazy) | MAPDATA avançado | N/A | JCL/me/Eureka | Map formatter |
| Provider pluggable | Não | — | — | **Sim** | Proc + formatter |
| Frames estruturados / IDE jump | Não | Parcial | **Sim** | LocationInfo | FormatLine |
| Aviso “ative debug” | **Agora (UX)** | — | — | — | — |

---

## 2. Melhorias a implementar no Dext (priorizadas)

### P0 — UX Explorer (feito / imediato)

- [x] Extrair `stackTrace.raw` + linhas reais no Inspector  
- [x] Se falhou e **não há stack**: mostrar checklist de opções de projeto (Debug mode)  
- [x] Menu Expert: **“Apply Debug Trace Options to Active Project”** (Actions ⋯) — OTA set Optimization/DebugInfo/UseDebugDCUs/MapFile

**Opções de projeto (Debug Trace Mode):**

```
Project → Options → Building → Delphi Compiler → Compiling
  Code generation → Optimization = False
  Debugging → Debug information = Debug information
  Debugging → Use debug .dcus = True
Project → Options → Building → Delphi Compiler → Linking
  Debug information = True
```

(Ideal: também garantir geração de `.map` / Detailed map no linking se o resolver Dext depender disso.)

### P1 — Coleta no runner

1. **Garantir hook** no host de testes (`Dext.Core.Debug` já instala no `initialization` — validar suite EXE linka a unit; se Release strippar, documentar).  
2. ~~**`IDextStackTraceProvider`**~~ — Feito (`Dext.Testing.StackTrace` + Runner).  
3. **Separar capture vs format** (inspirado LeakCheck): capturar `array of Pointer` no except; formatar com `.map` fora do caminho quente — parcial (hoje string + filter/parse).  
4. ~~**Filtrar frames**~~ — Feito (`FilterStackTrace`).

### P2 — Inspector rico

5. ~~Parser de frames estilo RadIA~~ — Feito (`ParseStackFrames` / `TDextStackFrame`).  
6. ~~Double-click → abre unit:linha~~ — Feito (`OpenSourceFileAtLine` no group inteiro).  
7. ~~Console estruturado~~ — Feito (E1.7).

### P3 — Roadmap (não agora)

8. Absorver ideias Daofy (VEH / MAPDATA) só após gaps P1 medidos  
9. Adapters madExcept/Eureka como providers opcionais (nunca default)

---

## 3. Critério de pronto (stack “bom o bastante” para pitch)

1. Failed com Debug Trace Mode → Inspector mostra frames com unit/método (não só hex).  
2. Failed **sem** debug info → mensagem clara + checklist (não silêncio).  
3. Um clique/menu aplica as 4 opções no `.dproj` ativo de testes.  
4. Sem dependência de JCL/madExcept no package Design.

---

## 4. Bug MAP → `System.Generics.Defaults:2013` em tudo

**Causa (não era o .map “mentindo” sozinho):** `FindNearestLine` pegava a maior linha com RVA ≤ endereço **sem limitar ao símbolo atual**. Units sem “Line numbers for …” no map herdavam a última linha da unit anterior (típico: RTL/`System.Generics.Defaults`).

**Fix:** `Dext.Core.Debug.ResolveAddr` — line lookup só aceita entradas com `SymRVA <= LineRVA < NextSymRVA`. Sem match → só o nome do símbolo (o Explorer pode completar unit:linha via método).

## 5. Profundidade do stack (como FastMM)

```pascal
TStackTrace.Options.MaxFrames := 48; // 1..64 (DBG_STACK_LENGTH); default 32
```

Definir **antes** de rodar os testes (ex.: no `initialization` do host / suite DPR). Vale para captura na exception e para `TStackTrace.Capture`.

## 6. Próximo passo

**QA manual:** rebuild suite + `.map` Detailed; failed frames devem mostrar `Dext.*.pas:N` distintos (ou só símbolo se a unit não tiver line numbers). P3 Daofy só se ainda faltar resolução.
