# Cpp.GTestSmoke

Este projeto existe para exercitar o Dext Test Explorer com Google Test, na mão. Ele não faz parte da suíte do framework e não deve ser disparado por CI.

Dois testes falham de propósito. `IntentionalFail` e `DeepCallFail` existem para a árvore mostrar falha e para a stack abrir o `.cpp`. `DeepCallFail` espera saldo 2 e `Ledger::Balance` devolve 3. Por isso `DextGTestSmokeTests.exe` termina com código diferente de zero. Isso é o exemplo, não um defeito do build.

`Scripts\run_examples.ps1` descobre só `.dproj` dentro de `Examples` e ainda recusa o nome `DextGTestSmokeTests` e qualquer caminho em `Tests\Samples`. Este arquivo é um `.cbproj` em `Tests\Samples`. Quem for automatizar examples não inclui esta pasta.

## Como rodar

Abra só este `.cbproj` no RAD Studio (não o grupo do Google Test do GetIt). Build, e rode pelo Explorer ou pelo exe em `Win32\Debug` ou `Win64x\Debug`.

```text
Win32\Debug\DextGTestSmokeTests.exe
Win32\Debug\DextGTestSmokeTests.exe --port 8102 --discover
```

No Explorer, Refresh pede `--port N --discover -no-wait`. Run All pede `--port N -no-wait`.

## O que cada fonte faz

O projeto se chama `DextGTestSmokeTests.cbproj` porque o nome contém `test` e assim aparece no combo do Explorer.

- `SmokeGTestMain.cpp` é o MainSource. Só tem `main`. Não tem `TEST`.
- `SmokeGTestSuite.cpp` tem `OnePlusOne` e `IntentionalFail`.
- `SmokeGTestDeep.cpp` tem a cadeia `Gateway` → `Auditor` → `NoteFailureStack` e o `EXPECT` de `DeepCallFail`.

A linha do `EXPECT_EQ` é a mensagem do Google Test. Os frames da stack vêm dos `FailureStackScope` em Gateway, Auditor e no teste. No Win32 Clang o `CaptureStackBackTrace` costuma voltar vazio, e por isso o smoke grava essa trilha na mão.

## Pré-requisito

Tools → GetIt → Google Test 1.17 (`GoogleTest-13-cb`). As libs ficam em `$(BDSCOMMONDIR)\CatalogRepository\GoogleTest-13-cb\1.17\`.

No `.cbproj`: include de `Sources\Testing\Cpp` e do `googletest\include`; library path do GetIt em `cbuilder\lib\$(Platform)\Release`. Win32 Clang usa o compilador clássico desligado. Link with Dynamic RTL fica ligado, para o `gtest.lib` achar `locale`. Link with Delphi Runtime Library fica desligado. O `#pragma` em `SmokeGTestMain.cpp` puxa `gtest.lib` no Win32 e no Win64x, e `gtest.a` no Win64 clássico.

Cobertura de linha, quando for o caso, é só Win64x. O grupo dessa plataforma já leva `-fprofile-instrument=clang`, `-fcoverage-mapping` e `-lclang_rt.profile-x86_64`.

## MainSource no editor

Neste console, com a RTL do Delphi desligada, o duplo clique no MainSource não abre o arquivo. Os outros `.cpp` abrem. O clique do Explorer vai para `SmokeGTestSuite.cpp` e `SmokeGTestDeep.cpp`. Para editar o `main`, use Project → View Source.

Depois de mudar header: Project → Clean, depois Build.
