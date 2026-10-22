# 9. Ferramenta CLI

O CLI `dext` fornece comandos para migrations, testes, scaffolding e mais.

## Capítulos

1. [Comandos](comandos.md) - Visão geral de todos os comandos
2. [Migrations](migrations.md) - Gerenciamento de schema de banco
3. [Scaffolding](scaffolding.md) - Gerar entidades a partir do BD
4. [Testes](testes.md) - Executar testes com cobertura
5. [Dashboard](dashboard.md) - Interface web para monitoramento
6. [Documentação](documentacao.md) - Gerar documentação da API

## Referência Rápida

```bash
# Ajuda
dext help

# Migrations
dext migrate:up
dext migrate:down
dext migrate:list
dext migrate:generate

# Testes
dext test
dext test --coverage
dext test --html

# Scaffolding
dext scaffold -c "meubanco.db" -d sqlite -o Entities.pas

# Dashboard — DextSidecar.exe (bandeja), não dext ui

# Documentação
dext doc
dext doc --output ./Docs

# Mapa de Símbolos
dext index
dext index --path ./Sources --format json
```

## Instalação e Compilação

O CLI do Dext pode ser utilizado de duas formas:

### 1. Ferramenta Global (dext.exe)
O framework inclui um projeto chamado **DextTool.dpr** localizado em `Apps\CLI`.
- Este projeto possui um **script de pós-build** que copia e renomeia automaticamente o executável gerado para `$(DEXT)\Apps\dext.exe`.
- Para utilizá-lo globalmente, adicione a pasta `$(DEXT)\Apps` à variável de ambiente **PATH** do Windows.
- Você pode compilá-lo usando a IDE do Delphi ou via linha de comando:
  ```bash
  msbuild Apps\CLI\DextTool.dproj /p:Configuration=Release
  ```

### 2. Embutido na sua aplicação
Você também pode embutir o CLI diretamente na sua aplicação. Adicione `Dext.Hosting.CLI` aos seus uses:

```pascal
uses
  Dext.Hosting.CLI;

begin
  var CLI := TDextCLI.Create(
    function: IDbContext
    begin
      Result := TAppDbContext.Create(Connection, Dialect);
    end
  );
  
  if CLI.Run then
    Exit; // Comando CLI executado
    
  // Início normal da aplicação...
end.
```

---

[← Testes](../08-testes/README.md) | [Próximo: Comandos →](comandos.md)
