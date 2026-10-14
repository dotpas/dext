# Dext Testing — Roadmap para contato Embarcadero

**Audience:** Embarcadero / partners / pitch pack  
**Companions:** [Features Catalog](../Dext-Testing-Features-Catalog.md) · [Pitch](Dext-Testing-Embarcadero-Pitch.md) · [Sidecar LongTerm](Dext-Sidecar-LongTerm.md)  
**Goal product:** livro Dext Testing + Expert crédível (Delphi → C++Builder)

---

## North star

| Objetivo | Como medimos |
|----------|----------------|
| **Livro no mercado** | Capítulos de framework + Explorer + legado/não-Dext revisados e publicáveis |
| **Embarcadero abraça** | Catálogo honesto + este roadmap + demos (Explorer, coverage gutter, bridge DUnit*) |
| **Valor agora** | Estabilizar/evoluir **Test Explorer**; C++ no radar oficial; Sidecar só **essencial** em paralelo |

---

## O que já está pronto (pitch)

| Área | Status |
|------|--------|
| Framework (attributes, Should, mocks, snapshots, reports, factory web) | **Stable** |
| `dext test` + **`dext test --coverage`** (HTML/XML/Sonar) | **Stable** |
| Adapters DUnit / DUnitX / DUnit2 → Explorer | **Stable** |
| Dext Test Explorer (S36) + suite trends + gutter + console ListView + stack frames | **Evolving** — código E1/E2 feito; QA manual |
| DextSidecar (tray, http.sys/SignalR) | **Evolving** — essencial Expert on (`DextSidecar.exe` + health poll) |
| Matriz ORM: PG, SQL Server, MySQL, SQLite, Oracle, Firebird, **InterBase** | **Stable** |
| REST client (`Dext.Net.RestClient`) | **Stable** (completo; não é gap de testing) |
| Containers de teste ORM (`infra/tests`) | **Preview** — Docker Compose + scripts; evoluir depois |

---

## Prioridades (ordem de entrega de valor)

### P0 — Agora (livro + pitch)

1. **Test Explorer** — estabilizar UX, coverage **visual** na IDE (gutter/polish), async/cancel, mensagens claras.  
2. **Catálogo + este roadmap** — pacote de contato (já em curso).  
3. **Capítulo livro (bookshelf): Cap. 18b** — `Docs/dext-developer-bookshelf/dext-testing-book-pt/18b_…` (já redigido; polish se preciso).  
4. **Coverage** — CLI já entrega; foco = experiência IDE (não reinventar motor).

### P1 — Em paralelo (não bloqueia livro)

5. **Sidecar essencial** — companion vivo mínimo (health, AutoAttach, sessão IDE, notificações de teste). Sem aba containers / docs / scaffold ainda.  
6. **C++Builder discovery → Expert** — o item que mais chama atenção Embarcadero após Delphi Explorer sólido.  
7. **Infra containers** — endurecer `infra/tests` (todos Stable no README); API Testcontainers-like = roadmap.

### P2 — Roadmap (features grandes — não agora)

| Item | Nota |
|------|------|
| Contract testing (Pact-like) | Microserviços |
| HTTP stub server (WireMock-like) | Complementa RestClient |
| Mutation testing (escopo PR) | Gate além de coverage |
| Property-based / fuzz leve | Parsers, mappers |
| Testcontainers productizado + aba Sidecar | Evolução de `infra/tests` |
| UI Automation VCL (Delphi 13) | Spike separado |
| WebView2 shell completo no Sidecar | Depois do companion útil |
| Dext Aspire / AppHost | Ver [cloud-roadmap](../roadmap/cloud-roadmap.md) — fora do pitch Testing |

---

## Superfícies — o que vender vs o que protelar

| Superfície | Pitch Embarcadero | Trabalho agora |
|------------|-------------------|----------------|
| **Test Explorer** | Sim — host do dia a dia | Estabilizar + evoluir + caminho C++ |
| **Coverage CLI + gutter** | Sim | Polir visual IDE |
| **Legacy / não-Dext chapter** | Sim | Escrever/revisar no livro |
| **Sidecar** | Mencionar como companion (opcional) | Só essencial; evolui em paralelo |
| **Containers / mutation / contracts** | Roadmap slide | Não implementar no ciclo do livro |

---

## Demais docs vivos

| Doc | Papel |
|-----|--------|
| [Dext-Testing-Execution-Plan.md](Dext-Testing-Execution-Plan.md) | **Plano de execução master** (fases E0–E5) |
| [Dext-Testing-Explorer-Plan.md](Dext-Testing-Explorer-Plan.md) | Backlog vivo Test Explorer / Design package |
| [Dext-Sidecar-LongTerm.md](Dext-Sidecar-LongTerm.md) | Detalhe técnico Sidecar (S0.5 essencial) |
| [Dext-Testing-Cpp-Discovery.md](Dext-Testing-Cpp-Discovery.md) | Contatos / requisitos C++ |
| [Dext-Testing-Phase4-Backlog.md](Dext-Testing-Phase4-Backlog.md) | Itens fase 4 já feitos / field-validate |
| [infra/tests/README.md](../../infra/tests/README.md) | Containers ORM (base futura) |

---

## Exit criteria para “podemos contatar”

- [x] Catálogo v1 com maturidade honesta  
- [x] Este roadmap + pitch one-pager  
- [ ] Explorer: coverage gutter usável na demo sem surpresas  
- [x] Cap. 18b no livro de publicação (`dext-testing-book-pt`) — redigido; polish Fase 5 se necessário  

- [ ] C++: discovery notes prontas (Expert = Planned, sem overclaim)  
- [ ] Sidecar: não precisa estar “produto completo” no primeiro contato  
