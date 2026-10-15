# Dext Testing — Discovery C++Builder

**Status:** Fase 0 — discovery (Sprint F)  
**Deep research 1:** [Dext-Testing-CppBuilder-Integration.md](Dext-Testing-CppBuilder-Integration.md)  
**Deep research 2 (produto):** [Dext-Testing-CppBuilder-Discovery.md](Dext-Testing-CppBuilder-Discovery.md) — **decisão abaixo**.

**Decisão de produto (research 2 + Cesar 2026-10):**

| Item | Decisão |
|------|---------|
| O que oferecer | **Só Explorer** (+ adapters). Não portar o framework Dext Testing para C++ |
| Runners C++ | **Google Test** (produto) + **DUnit C++** (legado Embarcadero; poucos usam) |
| DUnitX / Catch / … | **DUnitX não** (RTTI Delphi). Catch/doctest depois, se houver demanda |
| `Dext.Testing` (runtime package) | **Sem** interop C++ — sem gerar `.hpp`, sem build “headers for C++”, sem misturar RTL no exe C++ |
| Design BPL | Mesmo `Dext.Testing.Design.bpl` + `CPlusPlusBuilder.Personality` |
| IPC | Exe C++ puro → protocolo Host (`--port` real; research 2 = *forma*) |
| **Aberto** | Coverage C++ (LLVM?) + relatórios CI (Sonar etc.) — ver § Lacuna |

**Fechado em discovery (2026-10):** produto = Explorer + adapters C++ (GTest/DUnit); sem `Dext.Testing` runtime/interop; ponte C++ própria (HTTP Host), não as units Delphi.

**Objetivo Sprint F (implementação):** smoke DUnit + BPL na personalidade C++; gaps `.cbproj`; spike ponte C++ (GTest + DUnit C++) ↔ Host real.

---

## Síntese do deep research 1 (o que aproveitar)

| Achado | Decisão Dext |
|--------|--------------|
| Mesmo Expert Delphi OTA pode ver `.cbproj` se filtrar personalidade | **Sim** — MVP = `Dext.Testing.Design.bpl` + `CPlusPlusBuilder.Personality` |
| Processo filho + protocolo | **Já é o modelo Delphi** (`--port` + JSON) — C++ fala o **mesmo** contrato |
| **Google Test** = moderno / GetIt / Clang | **Adapter de produto** (após smoke) |
| **DUnit C++** = legado Embarcadero | **Smoke / baseline**, não o destino |
| DUnitX **não** em C++ | Confirmado |
| Dext.Mocks / RTTI Pascal | **Não** portar — C++ usa **gmock** |
| Coverage LLVM | Roadmap depois |
| Header `DextTesting.hpp` + `Should` | **Fora do MVP** — preferir adapters |

### Correções ao research 1

1. OTA: `sCBuilderPersonality` / `'CPlusPlusBuilder.Personality'` — não `sCppBuilderPersonality`.  
2. Protocolo: `--port N -no-wait` + Host — não stdout `[PASSED]` como contrato.  
3. Expert ainda filtra `.dproj` — personalidade sozinha não basta.  
4. Fases “framework C++ próprio / LLVM” = visão longa.

---

## Sprint F — experimentos

| # | Experimento | Porquê |
|---|-------------|--------|
| 1 | Suite **DUnit** mínima (wizard Embarcadero) | Baseline oficial |
| 2 | Mesmo BPL em `CPlusPlusBuilder.Personality` | Sem package `.Cpp` |
| 3 | Anotar gaps Explorer / `.cbproj` / Run | Requisitos |
| 4 | Spike GTest → `--port` (após research 2 + smoke) | Produto |

### Checklist smoke (1) — DUnit

1. New → Unit Tests → Test Project (C++), DUnit.  
2. Um `TTestCase`; anotar Win32/Win64, classic vs Clang.  
3. Rodar `.exe`.  
4. Anotar dores.

### Checklist smoke (2) — BPL

1. Install Packages → `Dext.Testing.Design.bpl`.  
2. Ou `InstallIDEPackage(..., "CPlusPlusBuilder.Personality")`.  
3. Explorer no modo C++?  
4. `.cbproj` lista/roda?

## Requisitos mínimos

- [ ] BPL na personalidade C++  
- [ ] Smoke DUnit C++  
- [ ] GTest + protocolo Host  
- [ ] `.cbproj` discover/compile/run  
- [ ] gmock documentado (não Dext.Mocks)  
- [ ] **Lacuna:** coverage C++ + export Sonar/CI — research dedicada após Explorer básico

## Lacuna — coverage e relatórios CI (C++)

No Delphi: DCC + `.map` → XML → gutter / `dext` CLI / Sonar.  
No C++: research 2 aponta LLVM (`-fprofile-instr-generate` / `llvm-cov`) no Clang Win64; classic incerto.

**Perguntas em aberto (não bloquear MVP Explorer):**

1. Pipeline mínimo Clang Win64 → artefato que o Explorer/gutter ou o `dext` CLI consiga consumir (LCOV? XML?).  
2. SonarQube C++: o que o scanner espera vs o que GTest/llvm-cov já emitem — a bridge Dext precisa converter ou só orquestrar?  
3. Relatórios JUnit/HTML: basta GTest nativo + CLI, ou o Host deve unificar como no Delphi?

Prompt curto para deep research 3 (quando for a hora):

```text
Contexto: Dext no C++Builder = só Test Explorer + adapters GTest/DUnit. Sem portar Dext.Testing runtime. Coverage Delphi hoje = Delphi Code Coverage + .map. Queremos o análogo C++ no RAD Studio 12/13 Clang (bcc64x) e o caminho até SonarQube / relatórios CI.

Objetivo: (1) flags e ferramentas LLVM na instalação Embarcadero; (2) artefato intermediário recomendado; (3) o que GTest já exporta (XML/JUnit) vs o que falta para Sonar; (4) o que o Expert/CLI Dext deve fazer vs só documentar “rode llvm-cov / sonar-scanner”; (5) o que falha no compilador classic. Fato vs hipótese; checklist de validação no RAD Studio. Fora de escopo: reinventar asserts C++.
```

## Contatos

| Pessoa | Status |
|--------|--------|
| Thiago (Embarcadero BR) | Pendente |
| David Millington | Pendente |
| Leonardo (MVP, UFPR) | Pendente |

## Próxima ação

1. Disparar **deep research 2** (prompt único abaixo).  
2. Em paralelo: smokes DUnit + BPL.  
3. Decidir MVP: só Explorer vs Explorer + bridge mínima.

---

## Prompt único — deep research 2 (copiar/colar)

```text
# Deep research: o que o Dext Testing pode (e não pode) oferecer ao C++Builder

## Quem somos / o que já temos (Delphi)

O Dext Testing (framework Delphi) inclui, entre outras coisas:
- runner por atributos RTTI (`[Test]`, `[TestFixture]`, …), asserções fluentes (`Should`), mocks (`Dext.Mocks`), snapshots, relatórios CI (JUnit/xUnit/TRX/Sonar/HTML);
- adapters para suítes legadas Delphi (DUnit / DUnitX / DUnit2) via unidade de integração + interceptação de linha de comando;
- **Dext Test Explorer**: Expert OTA em Delphi (design package BPL) no RAD Studio — árvore de testes, Run All / selected, inspetor de falhas, stack, coverage gutter (hoje via Delphi Code Coverage + .map).

Arquitetura do Explorer (já em produção no Delphi): a IDE **não** executa testes no processo `bds.exe`. Compila o projeto de teste, sobe o `.exe` filho com algo como `--port N -no-wait`, e recebe eventos JSON num servidor local embutido no Expert. Isolamento contra crash da suíte.

Hipótese de produto para C++Builder: **não** criar um segundo BPL “só C++”. Instalar o **mesmo** `Dext.Testing.Design.bpl` também na personalidade `CPlusPlusBuilder.Personality` (`sCBuilderPersonality` / GetIt `InstallIDEPackage(..., "CPlusPlusBuilder.Personality")`). Scaffold de package `.Cpp` separado foi descartado.

Trabalho paralelo nosso: smoke DUnit C++ (wizard Embarcadero) + instalar o BPL na personalidade C++. Esta research deve orientar a **estratégia de produto**, não só um adapter pontual.

## Minha situação (autor da pergunta)

Sou autor do Dext, forte em Delphi, **muito pouco uso recente de C++ / C++Builder**. Preciso de explicações claras, com fatos vs hipóteses, e sem assumir que eu já sei o modelo mental C++ moderno (Clang, headers, ABI, GetIt).

## Pergunta central de produto

Para um desenvolvedor C++Builder no RAD Studio 12/13, o que do ecossistema Dext Testing faz sentido oferecer?

1. **Só o Expert (Test Explorer)** — descobrir / compilar / rodar / ver falhas / (depois) coverage, falando com Google Test, DUnit C++, Catch2, etc. via adapters; o usuário continua escrevendo asserts no framework C++ que já usa.
2. **Explorer + uma “ponte” mínima** (header/lib que só fala o protocolo `--port` / JSON do Host Dext), sem reinventar um framework de asserts.
3. **Um “Dext Testing para C++” completo** (atributos/macros estilo `[Test]`, `Should`, mocks próprios, snapshots…) — só se for realista e desejável; diga honestamente se isso é armadilha de escopo.

Compare com o que a Embarcadero já recomenda (DUnit C++ legado vs Google Test via GetIt) e com o que o Visual Studio Test Explorer faz no mundo C++ (descoberta + runner externo, sem reinventar GTest).

## Bloco 1 — Limitações Delphi ↔ C++Builder (interop e tooling)

Explique, para o RAD Studio atual (cite versões quando importar: 10.4 / 12 / 13):

1. O que significa “mesma IDE, duas personalidades”? O Expert Delphi OTA enxerga projetos `.cbproj` naturalmente? Quais APIs (`IOTAProject.Personality`, compile, lista de arquivos) e quais pegadinhas?
2. Limitações de **misturar código Delphi e C++ no mesmo projeto / group**:
   - chamar units Delphi a partir de C++ e o contrário (headers gerados, packages runtime, mangling, RTL compartilhada);
   - o que é trivial, o que é frágil, o que a Embarcadero desencoraja;
   - isso é necessário para o Test Explorer C++, ou o modelo “exe C++ puro + protocolo” evita quase toda a interop binária?
3. Compiladores: classic (bcc32) vs Clang (bcc64x / Win64). O que muda para testes, GetIt (GTest), e Expert?
4. Constantes corretas: confirme `sCBuilderPersonality` / `CPlusPlusBuilder.Personality` e corrija nomes inventados tipo `sCppBuilderPersonality` se aparecerem em material popular.

## Bloco 2 — “Attributes” e metaprogramação em C++ (vs Delphi RTTI)

No Delphi, o Dext Testing depende fortemente de **atributos RTTI** e reflexão em runtime para achar fixtures/métodos.

Responda de forma didática:

1. Existe equivalente a **attributes** no C++ padrão / no C++Builder? (C++11 `[[attributes]]`, macros, reflection TS, RTTI C++ limitado, libclang, etc.)
2. O que o Google Test / Catch2 / doctest usam na prática para “descobrir” testes (macros, registro estático, listeners) — e por que isso **não** é o mesmo que `[Test]` do Delphi?
3. DUnitX usa recursos Delphi (atributos, genéricos, anonymous methods) — confirme por que **não** há DUnitX nativo em C++Builder e o que isso implica para nós.
4. Conclusão prática: faz sentido o Dext tentar portar discovery por RTTI para C++, ou o caminho certo é **sempre** adapter sobre GTest/DUnit/Catch (macros + event listener)?

## Bloco 3 — O que reutilizar do Dext Testing vs o que deixar de fora

Para cada capacidade, diga: **útil no C++Builder / só via Explorer / não portar / substituir por X**:

| Capacidade Delphi | Pergunta |
|-------------------|----------|
| Test Explorer (OTA, árvore, run, inspector, stack) | É o núcleo do valor C++? |
| Protocolo Host (`--port`, JSON) | Dá para um `.exe` C++ falar o mesmo contrato? Esboce requisitos (sem inventar stdout `[PASSED]` como protocolo oficial). |
| Adapters DUnit/DUnitX/DUnit2 (padrão) | Analogia C++: GTest listener, DUnit C++ intercept — viabilidade |
| Runner nativo por `[Test]` / Should / fluent | Vale a pena um `DextTesting.hpp` com macros `DEXT_TEST` + `Should`, ou é reinventar GTest mal? |
| Dext.Mocks | Portável? Ou só documentar **Google Mock**? |
| Snapshots | Viável com lib JSON C++ ou adiar? |
| Relatórios CI (JUnit/Sonar/HTML) | Quem gera: GTest nativo, bridge, ou `dext` CLI? |
| Coverage gutter | Delphi = Code Coverage + .map. C++ Clang = llvm-cov / `.profraw`? Classic? O Explorer consegue unificar depois? |
| WebApplicationFactory / HTTP in-process | Relevante para usuário C++ típico do C++Builder ou fora de escopo? |

## Bloco 4 — Recomendação de MVP e anti-objetivos

Entregue uma recomendação explícita em 3 horizontes:

1. **MVP (semanas):** o mínimo crédível para um usuário C++Builder (provavelmente: Explorer na personalidade C++ + um runner — GTest ou DUnit smoke).
2. **Próximo:** adapters adicionais, coverage LLVM, polish.
3. **Não fazer:** lista curta de armadilhas (ex.: segundo framework de asserts C++ “compatível com Should”; BPL separado sem necessidade; misturar RTL Delphi no exe de teste C++ sem necessidade).

Inclua um **diagrama textual** da arquitetura recomendada (IDE Expert Delphi → compile `.cbproj` → exe C++ → protocolo → UI).

## Bloco 5 — Adapter Google Test (nível engenharia, se a recomendação for “Explorer + adapter”)

Se o MVP incluir GTest, especifique:

1. Como plugar um `EmptyTestEventListener` (ou equivalente) no C++Builder + GetIt Google Test.
2. Como mapear discovery + execução para o **mesmo espírito** do Host Dext (processo filho, porta, eventos). Se o protocolo exato do Dext não estiver público nesta research, descreva a **forma** dos eventos (start suite, start test, pass/fail, message, stack, end) e o que a bridge precisa saber — sem fingir payloads inventados como oficiais.
3. Limitações Win32/Win64, Clang vs classic, death tests, filtros `--gtest_filter`.
4. Esqueleto mínimo de código C++ (listener + `main`) — curto.

## Formato da resposta

- Português, seções claras.
- **Fato** vs **hipótese** vs **precisa validar no RAD Studio** (checklist de experimentos).
- Citar DocWiki Embarcadero, GetIt, blogs oficiais, Delphi Praxis / SO quando forem a fonte; desconfiar de material genérico C++ que ignore o C++Builder.
- Não propor package Expert separado em C++ a menos que o mesmo BPL Delphi seja impossível — e nesse caso explicar por quê.
- Não assumir paths de máquina nem pastas fora de um repositório git hipotético do Dext.

## Fora de escopo

- Reescrever o Dext Web/ORM em C++.
- Pitch de marketing; foque engenharia e decisão de produto.
```
