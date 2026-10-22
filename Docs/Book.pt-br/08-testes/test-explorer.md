# Dext Test Explorer — instalação manual

O Dext Test Explorer é o expert que mostra a árvore de testes dentro do RAD Studio. Ele descobre a suíte, executa, abre a linha da falha e, quando a plataforma permite, pinta a cobertura de linha no editor.

A distribuição que queremos para esse expert é o GetIt. Enquanto isso não fecha, quem quiser experimentar instala a partir do código-fonte.

> [!IMPORTANT]
> Ainda estamos avaliando se publicamos a DLL já compilada. O expert não tem assinatura digital. Um certificado de desenvolvimento tem custo, e sem essa assinatura o Windows trata o arquivo como um plugin de origem desconhecida. Por isso este guia pede que você compile a DLL no seu RAD Studio e registre o caminho com o script de instalação. Não baixe uma DLL solta de um anexo.

## O que você precisa

- RAD Studio com o Delphi instalado. O script de exemplo usa o Studio 37.0 (RAD Studio 13). Troque `37.0` pela pasta da sua versão em `HKCU\Software\Embarcadero\BDS`.
- O repositório do Dext clonado na sua máquina.
- A IDE fechada no momento de copiar a DLL. O `bds.exe` trava o arquivo registrado.

## Compilar o expert

Abra um prompt em que o `rsvars.bat` da sua versão exista e compile o pacote de design em Release.

IDE de 32 bits:

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Apps\TestExplorerExpert\Dext.Testing.Design.ExpertLib.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal
```

IDE de 64 bits: o mesmo comando com `/p:Platform=Win64`. O nome da DLL leva o sufixo `x64`.

A saída fica em `Output\<versão>\<Win32|Win64>\Release\`. O script de instalação copia esse arquivo para `Apps\TestExplorerExpert\bin`, porque a IDE trava a cópia registrada e o rebuild precisa continuar livre para gravar em `Output`.

## Registrar o expert

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

## Cobertura de linha no Delphi

No projeto `.dproj`, ligue o mapa detalhado (Debug Trace / MAP Detailed). No Explorer, marque **Collect code coverage on Run All / Selected** e rode a suíte. O expert chama o Delphi Code Coverage, lê o XML e pinta o gutter. O mesmo relatório sai pela linha de comando com `dext test --coverage`.

## Cobertura de linha no C++Builder

A cobertura de linha no C++ fica na plataforma **Win64x** (`bcc64x`). Se o `.cbproj` ativo estiver em Win32, Win64 clássico ou outra plataforma, o Explorer esconde a caixa, o menu e a aba de coverage. No Run, o log registra que Win32 e o Win64 clássico não suportam code coverage.

No grupo de opções do Win64x, o compilador e o linker precisam destas duas linhas. O MSBuild chama `bcc64x -cc1`. A flag de driver `-fprofile-instr-generate` não chega nesse modo.

```xml
<BCC_UserSuppliedOptions>-fprofile-instrument=clang -fcoverage-mapping $(BCC_UserSuppliedOptions)</BCC_UserSuppliedOptions>
<ILINK_AdditionalOptions>-lclang_rt.profile-x86_64 $(ILINK_AdditionalOptions)</ILINK_AdditionalOptions>
```

A biblioteca `libclang_rt.profile-x86_64.a` já vem no RAD Studio, em `lib\clang\20\lib\windows`. O teste instrumentado grava `default.profraw` ao lado do exe. O Explorer junta esse arquivo com `llvm-profdata` e pede o LCOV ao `llvm-cov`. Os dois programas são o LLVM 20, instalado à parte. O RAD Studio não traz `llvm-cov` nem `llvm-profdata`. O LLVM 18 não lê o profraw que o `bcc64x` grava.

O mapa do C++ continua servindo para a stack. Ele não tem a tabela de linha que o Delphi Code Coverage lê, então não use esse programa num exe C++.

O exemplo que usamos está em `Tests\Samples\Cpp.GTestSmoke`.

## O que este guia não promete

O expert de C++ não está anunciado como suporte pronto, e não é um recurso oficial da Embarcadero. Win32, Win64 clássico, `bcc32c` e `bcc64` ficam sem cobertura de linha. Não embutimos um profiler para essas plataformas. Uma ferramenta de profile integrada é uma ideia para depois.

---

[← Testes](README.md)
