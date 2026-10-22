# Instalar o Dext Test Explorer na mão

22 de outubro de 2026.

O Dext Test Explorer já roda dentro do RAD Studio: descobre a suíte, executa, abre a linha da falha e pinta cobertura de linha quando a plataforma tem de onde ler essa linha. Em breve vamos disponibilizar uma forma mais simples de instalar o expert direto na IDE, possivelmente pelo GetIt. Quem quiser olhar agora compila a DLL e registra com o script.

Ainda estamos avaliando se publicamos a DLL compilada. O expert não tem assinatura digital. Um certificado de desenvolvimento tem custo, e sem essa assinatura o Windows trata o arquivo como plugin de origem desconhecida. Compile na sua máquina. Não use uma DLL solta.

O passo a passo, com os comandos de build, o script de registro e as flags de cobertura do Win64x, está no livro:

[Dext Test Explorer — instalação manual](../Book.pt-br/08-testes/test-explorer.md)

O mesmo texto em inglês: [manual install](../Book/08-testing/test-explorer.md).

O que já dá para usar: descobrir e executar um `.dproj` com `Dext.Testing`, um `.cbproj` DUnit (`Tests\Samples\Cpp.DUnitSmoke\DextDUnitSmokeTestsP.cbproj`) e um `.cbproj` Google Test (`Tests\Samples\Cpp.GTestSmoke\DextGTestSmokeTests.cbproj`). Cobertura de linha no Delphi pede o mapa detalhado e o Delphi Code Coverage. No C++Builder a cobertura de linha fica só no Win64x (`bcc64x`), com `llvm-cov`. Nas outras plataformas do `.cbproj` o Explorer esconde essas opções. Isso não é um recurso oficial da Embarcadero.
