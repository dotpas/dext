# Comandos CLI

Visão geral de todos os comandos disponíveis no CLI `dext`.

## Comandos Gerais

### Help
Mostra ajuda para o CLI ou um comando específico.
```bash
dext help
dext help migrate:up
```

### Version
Mostra a versão atual do framework e do CLI.
```bash
dext --version
```

## Migrations (`migrate:`)

| Comando | Descrição |
|---------|-----------|
| `migrate:up` | Aplica todas as migrations pendentes. |
| `migrate:down` | Reverte a última migration aplicada. |
| `migrate:list` | Lista todas as migrations e seu status (aplicada/pendente). |
| `migrate:generate` | Cria um arquivo unit de migration vazio com timestamp. |

## Testes (`test`)

Executa a suíte de testes do projeto.

| Opção | Descrição |
|-------|-----------|
| `--coverage` | Gera relatório de cobertura de código. |
| `--html` | Gera relatório visual em HTML. |
| `--xml` | Saída em formato JUnit XML (para CI/CD). |
| `--filter` | Filtra testes por nome ou categoria. |

```bash
dext test --coverage --html
```

## Scaffolding (`scaffold`)

Gera classes de entidade a partir de um banco de dados existente.

```bash
dext scaffold -c "Server=localhost;Database=Vendas" -d mssql
```

## Facade (`facade`)
 
Gera uma "Unit Facade" (unit coringa) que re-exporta tipos e constantes de um conjunto de units de origem. Isso simplifica a cláusula `uses` para os usuários finais.
 
```bash
dext facade -p Sources\Data -t Sources\Data\Dext.Entity.pas -x Dext.Entity
```
 
Opções:
- `-p, --path` - Diretório de origem para escanear units Pascal.
- `-t, --target` - Arquivo de saída de destino (arquivo Pas).
- `-x, --target-unit` - O nome da unit de destino (ex: `Dext.Entity`).
- `--verbose` - Habilita logs detalhados.

## Index (`index`)

Gera um mapa/índice completo de todos os símbolos públicos (classes, records, interfaces, métodos, propriedades, constantes, enums, etc.) em diversos formatos com seus números exatos de linhas. Ideal para agentes de IA (como Antigravity/Codex) e ferramentas como NotebookLM.

```bash
dext index -p Sources -f markdown -o dext-symbols.md
```

Opções:
- `-p, --path` - Diretório de origem a ser escaneado recursivamente (Padrão: diretório atual).
- `-o, --output` - Caminho do arquivo de saída gerado.
- `-f, --format` - Formato do mapa de símbolos: `markdown` (padrão), `json` ou `csv`.
- `-x, --exclude` - Lista de pastas ou units a serem ignoradas separadas por vírgula (ex: `External,__recovery`).
 
## Dashboard

Use o **DextSidecar** (bandeja). O comando `dext ui` foi removido do CLI.

```text
DextSidecar.exe   →  http://localhost:3030
```

## Gerenciamento de Certificados SSL (`dev-certs`)

Gera e gerencia certificados SSL/TLS autoassinados de desenvolvimento locais para `localhost` e `127.0.0.1` (similar ao `dotnet dev-certs https`), incluindo a automação do binding no Kernel do Windows (`http.sys`).

```bash
dext dev-certs https [--trust] [--force] [--out-cert <path>]
```

| Opção | Descrição |
|-------|-----------|
| `https` | Subcomando para gerar certificado autoassinado X.509 de desenvolvimento com extensão SAN (`localhost`, `127.0.0.1`). |
| `--trust` | Importa o certificado no Repositório de Raízes Confiáveis (`Root`), no Repositório Pessoal (`My`) e vincula a porta 8080 no Kernel (`http.sys`). |
| `--force` | Força a sobrescrita de certificados e chaves já existentes no diretório. |
| `--out-cert` | Caminho do arquivo de certificado gerado (padrão: `server.crt`). |

### Exemplo de uso:

```bash
# Gera o certificado server.crt, chave server.key, pacote server.pfx e instala no repositório do Windows
dext dev-certs https --trust
```

O comando gera:
- `server.crt`: Certificado X.509 em formato PEM.
- `server.key`: Chave privada RSA em formato PEM.
- `server.pfx`: Pacote PKCS#12 com chave privada vinculada para o Windows Schannel.
- Instalação no repositório `LocalMachine\My` e execução do binding Kernel: `netsh http add sslcert ipport=0.0.0.0:8080 certhash=<THUMBPRINT> appid={4f3b2c10-8a9b-4d7e-8f12-3456789abcde}`.

---

[← CLI](README.md) | [Próximo: Migrations →](migrations.md)
