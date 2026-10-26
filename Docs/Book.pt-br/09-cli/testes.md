# CLI: Testes

O Dext CLI possui um test runner sofisticado integrado.

## Executando Testes

```bash
dext test
```
Isso buscará todos os `[TestFixture]` na sua aplicação e executará as units de teste.

## Cobertura de Código (Code Coverage)

O Dext integra-se com o DelphiCodeCoverage para gerar métricas precisas:

```bash
dext test --coverage
```

### Opções de Relatório

- **HTML**: Relatório visual para humanos.
- **XML**: Para integração com SonarQube ou Azure DevOps.
- **JSON**: Para processamento customizado.

```bash
# Gerar HTML num diretório específico
dext test --coverage --html --output-dir .\relatorios
```

## Filtragem de Testes

Execute apenas os testes que você está alterando no momento:

```bash
# Filtra pelo nome da classe ou do método
dext test --filter TUserServiceTests
```

## Quality Gates (Thresholds)

Você pode falhar o build caso a cobertura de código seja menor que o esperado:

```bash
# Falha se a cobertura for menor que 80%
dext test --coverage --threshold 80
```

Abaixo do limiar, e também quando a suíte falha, o processo termina com código de saída 1.

---

[← Scaffolding](scaffolding.md) | [Próximo: Dashboard →](dashboard.md)
