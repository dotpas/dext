# Dext Testing — Discovery C++Builder

**Status:** Fase 0 — discovery (não beta de produto)  
**Objetivo:** entender como desenvolvedores C++Builder testam hoje e quais requisitos mínimos um Expert OTA separado deveria atender.  
**Não fazer nesta fase:** anunciar suporte C++ pronto; pedir “teste o instalador” (ainda não existe).

## Contatos

| Pessoa | Papel | Status do contato | Notas |
|--------|--------|-------------------|--------|
| Thiago (Embarcadero Brasil) | Embarcadero / C++Builder | Pendente | Canal produto/região BR |
| David Millington | Ex-Embarcadero, área C++ | Pendente | Visão histórica IDE / tooling |
| Leonardo (MVP, UFPR) | MVP / academia | Pendente | Fluxo real de ensino e projetos |

## Roteiro de conversa (15–25 min)

Abrir com: *“Estamos desenhando suporte C++Builder para o Dext Test Explorer. Ainda não há binário — queremos aprender o fluxo de vocês antes de construir.”*

1. **Como rodam testes hoje?**
   - Google Test, Catch2, Boost.Test, DUnit (mixed), outro?
   - Na IDE, linha de comando, CI (qual)?
2. **O que falta na IDE C++Builder vs Visual Studio Test Explorer?**
   - Árvore de testes, rerun failed, gutter, coverage, filtros?
3. **Aceitariam um Expert OTA com instalador próprio** (não acoplado ao pacote Delphi Dext) que descubra/execute suites e mostre árvore + falhas?
4. **Restrições técnicas**
   - Personalidades BDS / versões RAD Studio
   - Win32 vs Win64
   - Clang vs classic compiler
   - Packaging (GetIt vs setup MSI/EXE)
5. **Formato de saída** que já usam (JUnit XML, console GTest, TRX)?
6. **Beta futuro:** topariam validar um preview quando o DLL/instalador existir?

## Template de notas (1 página por pessoa)

```
Data:
Pessoa:
Canal (email/call/mensagem):

Runners atuais:
IDE gaps citados:
Formato de report preferido:
Win32/Win64 / Clang/classic:
Aceita Expert instalador separado? (S/N/talvez)
Interesse em beta? (S/N)
Requisitos mínimos mencionados:
Citações úteis:
Follow-up:
```

## Requisitos mínimos do Expert C++ (preencher após as conversas)

Lista viva — atualizar com o que os três contatos convergirem:

- [ ] Runner alvo MVP (ex.: Google Test com `--gtest_output=xml:`)
- [ ] Personalidade / versões RAD Studio alvo
- [ ] Descoberta de projetos (`.cbproj` / executável de teste)
- [ ] IPC com o Expert (mesmo protocolo JSON do Explorer Delphi, se possível)
- [ ] Instalador dedicado (sem exigir BPLs Delphi do framework)
- [ ] Outros: …

## Próximo passo após discovery

Alimentar a **Fase 3** (Expert DLL + instalador C++ + beta fechado) com esta lista — não inverter a ordem.
