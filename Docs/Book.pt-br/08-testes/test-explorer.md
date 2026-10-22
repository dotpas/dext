# Dext Test Explorer — compilar e instalar

O Dext Test Explorer é o expert que mostra a árvore de testes dentro do RAD Studio. Ele descobre a suíte, executa, abre a linha da falha e, quando a plataforma tem de onde ler a linha, pinta a cobertura no editor.

> [!IMPORTANT]
> Em breve vamos disponibilizar uma forma mais simples de instalar o expert direto na IDE, possivelmente pelo GetIt. Até lá, o caminho é este: você compila a DLL no seu RAD Studio e registra com o script. Isso ainda não é um recurso oficial da Embarcadero.

> [!IMPORTANT]
> Ainda estamos avaliando se publicamos a DLL já compilada. O expert não tem assinatura digital. Um certificado de desenvolvimento tem custo, e sem essa assinatura o Windows trata o arquivo como um plugin de origem desconhecida. Compile na sua máquina. Não baixe uma DLL solta de um anexo.

## O que você precisa

- RAD Studio com o Delphi instalado. O script de exemplo usa o Studio 37.0 (RAD Studio 13). Troque `37.0` pela pasta da sua versão em `HKCU\Software\Embarcadero\BDS`.
- O repositório do Dext clonado na sua máquina.
- A IDE fechada no momento de copiar a DLL. O `bds.exe` trava o arquivo registrado.

## 1. Compilar a DLL

Abra um prompt na raiz do repositório, chame o `rsvars.bat` da sua versão e compile o expert em Release.

IDE de 32 bits:

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Apps\TestExplorerExpert\Dext.Testing.Design.ExpertLib.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal
```

IDE de 64 bits: o mesmo comando com `/p:Platform=Win64`. O nome da DLL leva o sufixo `x64` (`Dext.Testing.Design.ExpertLibx64.dll`).

A saída fica em `Output\<versão>\<Win32|Win64>\Release\`. O script de instalação copia esse arquivo para `Apps\TestExplorerExpert\bin`, porque a IDE trava a cópia registrada e o rebuild precisa continuar livre para gravar em `Output`.

## 2. Instalar

Feche o RAD Studio. Na pasta `Installers\DextTestExplorer`:

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0
```

Para a IDE de 64 bits:

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Ide64
```

Abra o RAD Studio. No menu View, abra o **Dext Test Explorer**. A janela ancora como o Project Manager.

Para tirar o registro sem apagar a DLL:

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Uninstall
```

Depois de mudar o fonte: compile de novo (a IDE pode ficar aberta, porque o build grava em `Output`), feche a IDE, rode o script outra vez e abra de novo.

## 3. Abrir um projeto de teste

O combo do Explorer lista o projeto aberto quando o arquivo é `.dproj` ou `.cbproj` e o nome do arquivo contém `test`. Pacote Delphi (`.dpk`) fica de fora.

| O que você quer ver | Projeto |
|---|---|
| DUnit no C++Builder | `Tests\Samples\Cpp.DUnitSmoke\DextDUnitSmokeTestsP.cbproj` |
| Google Test no C++Builder | `Tests\Samples\Cpp.GTestSmoke\DextGTestSmokeTests.cbproj` |
| Suíte Delphi com `Dext.Testing` | um `.dproj` cujo nome contém `test`, por exemplo `Tests\Core\UnitTests\Dext.Core.UnitTests.dproj` |

Abra o `.cbproj` sozinho. O sample de DUnit pede o Win32 Clang (`BCC_UseClassicCompiler=false`). O de Google Test pede o pacote Google Test 1.17 no GetIt do RAD Studio (`GoogleTest-13-cb`). Esse GetIt é o da biblioteca de testes. A instalação do expert continua sendo o script desta página.

Os dois samples são manuais. `IntentionalFail` e `DeepCallFail` falham de propósito, para a árvore mostrar a falha e a stack abrir o `.cpp`. O exe do Google Test termina com código diferente de zero. Por isso ele não entra em `Scripts\run_examples.ps1`.

## O que cada recurso aceita

| Recurso | Projeto | Onde funciona |
|---|---|---|
| Descobrir a suíte, executar, abrir a linha da falha | `.dproj` com `Dext.Testing` | As plataformas do projeto Delphi |
| Descobrir a suíte, executar, abrir a linha da falha | `.cbproj` DUnit ou Google Test | O projeto C++ que você compilou. O sample DUnit desta página está no Win32 Clang |
| Cobertura de linha | `.dproj` | Delphi Code Coverage, com o mapa detalhado (Debug Trace / MAP Detailed) |
| Cobertura de linha | `.cbproj` | Somente a plataforma **Win64x** (`bcc64x`) |
| Stack a partir do mapa | `.cbproj` | O mapa detalhado. Esse mapa não tem a tabela de linha |

No `.cbproj`, se a plataforma ativa for Win32, Win64 clássico, `bcc32c` ou `bcc64`, o Explorer esconde a caixa de coverage, o menu e a aba Coverage. No Run, o log registra que Win32 e o Win64 clássico não suportam code coverage. Um `.dproj` continua com o Delphi Code Coverage.

## Cobertura de linha no Delphi

No projeto `.dproj`, ligue o mapa detalhado (Debug Trace / MAP Detailed). No Explorer, marque **Collect code coverage on Run All / Selected** e rode a suíte. O expert chama o Delphi Code Coverage, lê o XML e pinta o gutter. O mesmo relatório sai pela linha de comando com `dext test --coverage`.

## Cobertura de linha no C++Builder (só Win64x)

No grupo de opções do Win64x, o compilador e o linker precisam destas duas linhas. O MSBuild chama `bcc64x -cc1`. A flag de driver `-fprofile-instr-generate` não chega nesse modo.

```xml
<BCC_UserSuppliedOptions>-fprofile-instrument=clang -fcoverage-mapping $(BCC_UserSuppliedOptions)</BCC_UserSuppliedOptions>
<ILINK_AdditionalOptions>-lclang_rt.profile-x86_64 $(ILINK_AdditionalOptions)</ILINK_AdditionalOptions>
```

A biblioteca `libclang_rt.profile-x86_64.a` já vem no RAD Studio, em `lib\clang\20\lib\windows`. O teste instrumentado grava `default.profraw` ao lado do exe. O Explorer junta esse arquivo com `llvm-profdata` e pede o LCOV ao `llvm-cov`. Os dois programas são o LLVM 20, instalado à parte. O RAD Studio não traz `llvm-cov` nem `llvm-profdata`. O LLVM 18 não lê o profraw que o `bcc64x` grava.

O grupo Win64x de `Tests\Samples\Cpp.GTestSmoke\DextGTestSmokeTests.cbproj` já leva essas duas opções. Você marca Collect coverage, seleciona Win64x e roda.

O mapa do C++ continua servindo para a stack. Ele não tem a tabela de linha que o Delphi Code Coverage lê, então esse programa fica no `.dproj`.

## O que este guia não promete

O suporte C++ do expert está em revisão. Win32, Win64 clássico, `bcc32c` e `bcc64` ficam sem cobertura de linha. Não embutimos um profiler para essas plataformas. Uma ferramenta de profile integrada é uma ideia para depois.

---

[← Testes](README.md)
