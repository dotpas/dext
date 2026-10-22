# Instalar o Dext Test Explorer na mão

22 de outubro de 2026.

O Dext Test Explorer já roda dentro do RAD Studio: descobre a suíte, executa, abre a linha da falha e pinta cobertura de linha quando a plataforma tem de onde ler essa linha. A distribuição que queremos é o GetIt. Quem quiser olhar agora instala a partir do fonte.

Ainda estamos avaliando se publicamos a DLL compilada. O expert não tem assinatura digital. Um certificado de desenvolvimento tem custo, e sem essa assinatura o Windows trata o arquivo como plugin de origem desconhecida. Compile na sua máquina. Não use uma DLL solta.

O passo a passo, com os comandos de build, o script de registro e as flags de cobertura do Win64x, está no livro:

[Dext Test Explorer — instalação manual](../Book.pt-br/08-testes/test-explorer.md)

O mesmo texto em inglês: [manual install](../Book/08-testing/test-explorer.md).

O que já dá para usar: suíte Delphi com mapa detalhado e Delphi Code Coverage; suíte C++ só na plataforma Win64x (`bcc64x`), com `llvm-cov`. Win32 e Win64 clássico não têm cobertura de linha, e o Explorer esconde essas opções para não parecer que têm. Isso não é um recurso oficial da Embarcadero.
