# S75 — C++Builder Test Explorer (mesma BPL + personalidade)

**Status:** Em revisão (22/10/2026). A cobertura de linha no Win64x e a instalação manual do expert estão documentadas. GetIt e uma DLL assinada ficam fora deste fechamento. O suporte C++ não está anunciado como pronto.  
**Depends on:** S36 Expert estável (Delphi)

## Goal

O **mesmo** `Dext.Testing.Design.bpl` instalado também para `CPlusPlusBuilder.Personality`, sem package `.Cpp` separado. Discovery valida o que funciona (menu, dock, `.cbproj`, DUnit) e o que falta (adapters GTest, etc.).

## Architecture (hipótese MVP)

```
RAD Studio (C++Builder personality)
  └─ Dext.Testing.Design.bpl  (mesmo OTA Expert Delphi)
       ├─ InstallIDEPackage(..., "CPlusPlusBuilder.Personality")
       └─ Descoberta / run: TBD após smoke DUnit + deep research
```

## Deliverables (após discovery)

1. Provar install do BPL na personalidade C++.  
2. Smoke DUnit (baseline Embarcadero).  
3. Lista de gaps (descoberta `.cbproj`, runners, compile path).  
4. Só então: adapters / GetIt actions — **sem** BPL `Design.Cpp`.

## Non-goals

- Package `Dext.Testing.Design.Cpp` (scaffold **removido** 2026-10).  
- Anunciar suporte C++ pronto.  
- Substituir GTest/Catch2 APIs.
- Cobertura de linha em Win32, Win64 clássico, `bcc32c` ou `bcc64`.
- Embutir um profiler no Explorer. Uma ferramenta de profile integrada fica só como ideia.

## Removido do repo

`Sources/Testing/Design.Cpp/`, `Packages/*/Dext.Testing.Design.Cpp.*`, `Installers/DextTestExplorer-CppBuilder/`.

## Cobertura de linha (decisão de 22/10/2026)

A cobertura de linha no C++ fica no Win64x (`bcc64x`). O Explorer lê a plataforma ativa do projeto. Num `.cbproj` que não está em Win64x, a caixa de coverage, o menu de coverage e a aba Coverage somem. No Run, o log registra que Win32 e o Win64 clássico não suportam code coverage. Um `.dproj` continua com o DelphiCodeCoverage, em qualquer plataforma Delphi.

No Win64x o MSBuild chama `bcc64x -cc1`. A flag de driver `-fprofile-instr-generate` é desconhecida nesse modo (E8920). As flags que o `-cc1` aceita são `-fprofile-instrument=clang` e `-fcoverage-mapping`. O link é o `ld.lld` e precisa de `-lclang_rt.profile-x86_64`, que está em `Studio\37.0\lib\clang\20\lib\windows`. `CCC_OVERRIDE_OPTIONS` chega no driver (`bcc64x -###`) e não chega na linha `-cc1` do MSBuild. Um Rebuild apaga o `.res` antes do `brcc32`, e o `ld.lld` falha ao abrir o recurso. O caminho que funcionou foi Build, com essas flags no `.cbproj`.

O exe instrumentado grava `default.profraw` no diretório de trabalho. O Explorer junta os `.profraw` com `llvm-profdata` e exporta LCOV com `llvm-cov export -format=lcov`. O LLVM precisa ser o 20, o mesmo major do `bcc64x` (Clang 20.1.7). O `llvm-profdata` 18 recusa o profraw versão 10. O RAD Studio não traz `llvm-cov` nem `llvm-profdata`. Nesta máquina o LLVM 20.1.0 está em `C:\Program Files\LLVM\bin`. O gutter lê o LCOV. O `.map` continua só para a stack.

O que não vale repetir:

O `.map` de C++ não tem a secção "Line numbers for". O mapa do Delphi tem, e é isso que o DelphiCodeCoverage lê. Num exe C++ esse programa não produz linha. Recriar um mapa a partir do PDB para alimentar o DelphiCodeCoverage também não serve: no PDB do `bcc64x` o DIA devolve linha 0.

O OpenCppCoverage 0.9.9.0 (GPL-3.0, último release em 21/05/2020, repositório arquivado em 06/09/2026) abre o exe, segue o diretório de debug do PE até o PDB e usa o DIA (`msdia140.dll`, `IDiaLineNumber`). Não abre `.tds` nem `.map`. No smoke Win64x o PDB carregou, os nomes de arquivo bateram, e toda linha veio 0, com `-g`, debug de linha, full debug e `-gcodeview -debug-info-kind=standalone` já ligados. Não era checkbox faltando. O VTune lê linha nesse PDB. O DIA que o OpenCppCoverage usa não. Chamar o exe de fora continua permitido, e não produz cobertura enquanto a linha for 0. Copiar o fonte para dentro do Dext leva a licença GPL para o produto.

O `.tds` tem a tabela de linha (arquivo, segmento, deslocamento, número). É o debug do C++ Win32. O `TDSToPDB` em `Libs\TDSToPDB` lê esses registros e grava um PDB no estilo LLVM, a mesma família que o DIA já leu com linha 0. Converter TDS em PDB (Josko/tds2pdb, MIT, ou a pasta `tds2pdb` do map2dbg) só interessaria se o DIA passasse a devolver linha diferente de zero. O tds-parser do alexmwillis é Sitecore, não Borland TD32. O StripTDS é da SmartBear e não é código aberto. Um `.dbg` solto não é aberto pelo `loadDataForExe`, que segue o diretório de debug do PE.

O AQTime 8.81 (documentação de 18/01/2022, C++Builder até o 10.4, sem `bcc64x`) não usa o mapa para saber qual linha rodou. O profiler executa o processo e conta o endereço. A coluna de linha vem do debug. No Win32 isso é o `.tds`, gravado com Debug information, Debug line number information e Full debug information no linker. No Win64 clássico a página também pede um mapa, e aceita segmentos, publics ou detailed. Segmentos e publics não têm tabela de linha, então a linha continua no debug. O time de C++ da Embarcadero usa o AQTime porque ele entende TDS. Não vamos embutir esse profiler. Uma ferramenta de profile integrada, fácil de usar, é uma ideia para depois e não faz parte desta entrega.

O `bcc64` (Clang 5) e o `bcc32c` ficam juntos com o clássico, fora da cobertura de linha. O `bcc64x` define `_WIN64` e `__clang_major__` 20. Não define `_WIN64X`. A import lib do Win64 clássico é `.a` (`winhttp.a` no psdk). Win64x e Win32 usam `.lib`.
