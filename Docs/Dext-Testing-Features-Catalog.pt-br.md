# Catálogo de Features — Dext Testing (v1)

Resumo em português do [catálogo EN](Dext-Testing-Features-Catalog.md).

## Separação honesta

- **Framework de testes** — Stable (atributos, asserts, mocks, snapshots, reports, adapters DUnit*).
- **Coverage CLI** — Stable (`dext test --coverage`).
- **Coverage na IDE (gutter)** — Evolving (polir visual / demo).
- **IDE / Test Explorer** — Evolving — **prioridade #1** (estabilizar, evoluir, caminho C++).
- **DextSidecar** — Evolving — só **essencial** em paralelo (não bloqueia livro/pitch).
- **`dext ui`** — Removido do CLI.
- **Containers de teste** (`infra/tests`) — Preview; evoluir depois (± aba Sidecar).
- **C++Builder / UI Automation** — C++ Explorer em revisão (cobertura de linha só no Win64x; GetIt e DLL assinada ainda abertos). UIA continua Planned.
- **ORM DBs** — PG, SQL Server, MySQL, SQLite, Oracle, Firebird, **InterBase** — todos Stable.
- **REST client** — Stable (completo; não é gap de testing).

## Mapa rápido .NET → Dext

xUnit/NUnit → Attributes · Moq → Mocks · FluentAssertions → Should · Coverlet → `dext test --coverage` · Test Explorer → Dext Test Explorer · Dashboard → **DextSidecar** · JUnit/TRX/Sonar → Reports · WebApplicationFactory → Factory in-process · Testcontainers → `infra/tests` (Preview).

## Gaps explícitos

Gutter de coverage a polir; Expert C++ ainda não anunciado como pronto; cobertura de linha C++ só no Win64x (`bcc64x`, llvm-cov), e o Explorer esconde essas opções nas outras plataformas do `.cbproj` — ver S75; UIA só spike; Sidecar companion essencial em paralelo. Features grandes (mutation, contracts, WireMock, Testcontainers productizado) = roadmap P2.
