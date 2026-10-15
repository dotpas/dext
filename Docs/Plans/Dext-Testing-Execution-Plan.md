# Dext Testing — Plano de execução (master)

**North star:** livro no mercado + pitch Embarcadero crédível.  
**Ordem de valor:** Explorer → Stack/Coverage → Sidecar essencial // → C++ / features grandes.

Docs satélites (detalhe):  
[Explorer](Dext-Testing-Explorer-Plan.md) · [StackTrace](Dext-Testing-StackTrace-Plan.md) · [Sidecar](Dext-Sidecar-LongTerm.md) · [Embarcadero Roadmap](Dext-Testing-Embarcadero-Roadmap.md) · [Pitch](Dext-Testing-Embarcadero-Pitch.md) · [Catalog](../Dext-Testing-Features-Catalog.md) · [Sprint E QA](Dext-Testing-SprintE-QA-Checklist.md) · [Cap. 18b demo](Dext-Testing-Cap18b-Explorer-Demo.md)

---

## Fase E0 — Fundação docs / pitch (quase fechada)

| # | Item | Status |
|---|------|--------|
| E0.1 | Catálogo Testing v1 + PT | Feito |
| E0.2 | Embarcadero Roadmap + Pitch | Feito |
| E0.3 | Demo não-Dext (sample Cap18b) | Feito — `Tests/Samples/Cap18b.LegacyDUnitX` |
| E0.4 | `dext ui` removido; Sidecar canônico | Feito |

---

## Fase E1 — Test Explorer (prioridade #1)

| # | Item | Status | Notas |
|---|------|--------|-------|
| E1.1 | IDE responsiva no Run All | Feito | Validado Sprint E QA |
| E1.2 | FAIL no console; PASS silencioso | Feito | |
| E1.3–E1.5 | Stack + Apply Debug Trace | Feito | |
| E1.6–E1.8c | Coverage gutter + aba + UX v1.1 | Feito | 10.4 + 13.2 |
| E1.9k | Open HTML no contexto da aba Coverage | Feito | |
| E1.9 | Coverage backlog restante | Planejado | **Após** pitch — Explorer-Plan §4.1 |
| E1.10 | Passive View → Presenter | Débito | Não bloqueia pitch |

---

## Fase E2 — Stack trace (coleta)

| # | Item | Status |
|---|------|--------|
| E2.1–E2.3 | Provider + frames clicáveis | Feito |
| E2.4 | Daofy VEH/MAPDATA | Roadmap |

---

## Fase E3 — Sidecar

| # | Item | Status |
|---|------|--------|
| E3.1 | AutoAttach + start + `/health` | Feito (smoke) |
| E3.2–E3.3 | Sessão IDE + notificações | Feito (essencial mínimo) |
| E3.4 | WebView2 / docs / containers | Depois |
| E3.5 | **SPA Testes: run não apaga árvore** | **Aberto** — QA 2026-10; ver [Sidecar §1.1](Dext-Sidecar-LongTerm.md) |
| E3.6 | Settings UI real; polish Painel/Projetos/HTTP/Traces/Logs | Depois |

**Pitch:** Sidecar = companion (health/sync). Runner do dia a dia = **Test Explorer IDE**. Não vender aba Testes da SPA até E3.5.

---

## Fase E4 — Embarcadero / livro / C++

| # | Item | Status |
|---|------|--------|
| E4.1 | Demo pitch-ready (Explorer + coverage + 18b) | **Feito** — Sprint E QA humano OK |
| E4.2 | Polish manuscrito livro | Contínuo |
| E4.3 | C++ discovery → Expert | **Hold** — [Cpp-Discovery](Dext-Testing-Cpp-Discovery.md) |

---

## Fase E5 — Roadmap (não iniciar agora)

Contract tests · WireMock-like · Mutation · Testcontainers productizado · UIA · Aspire · WebView2 full

---

## Ordem de implementação (sprints)

```text
Sprint A–D2: Explorer + Coverage v1.1                         ✅
Sprint E:    QA DoD + Cap. 18b sample + E1.9k                 ✅ (2026-10)
Sprint F:    E4.3 C++ — smoke DUnit (doc Embarcadero) → package Cpp  ← escolhido
Sprint G:    E1.9 restante coverage polish  |  Sidecar E3.5           depois
```

---

## Definition of Done — “podemos contatar Embarcadero”

- [x] Explorer Run All sem travar a IDE (validado Sprint E)  
- [x] Failed + stack / Apply Debug Trace (validado Sprint E)  
- [x] Coverage gutter + aba (v1.1, 10.4 + 13.2)  
- [x] Cap. 18b + sample `Tests/Samples/Cap18b.LegacyDUnitX` + catálogo + pitch  
- [x] Sem claim de C++ completo / Sidecar Testes SPA / mutation / Testcontainers  

---

## Próximas prioridades (pós-DoD)

| Prioridade | Item | Porquê |
|------------|------|--------|
| 1 | **E4.3 C++** — ver próximos passos abaixo | Sprint F escolhido |
| 2 | E1.9 coverage polish (Prev/Next, E1.9l WebView…) | Não urgente |
| 3 | E3.5 Sidecar Testes run (árvore some) | Companion; depois do smoke C++ |
| 4 | E1.10 Passive View | Débito |

## Hold

- E1.9l WebView2 coverage in-IDE — depois  
- Não exagerar claims Sidecar / C++ “pronto” na conversa Embarcadero  
- Expert Sidecar (`DEXT_ENABLE_SIDECAR_EXPERT`) off até SPA estável  

## Próxima ação (Sprint F)

Discovery C++ **fechado** (estratégia). Ver [Cpp-Discovery](Dext-Testing-Cpp-Discovery.md).

Quando retomar implementação: (1) smoke DUnit + BPL personalidade C++; (2) ponte C++ HTTP (GTest + DUnit C++); (3) depois coverage/Sonar C++.
