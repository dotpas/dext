# Scaffolding

A ferramenta de Scaffolding do Dext ORM permite gerar automaticamente classes de Entidade Delphi a partir de um esquema de banco de dados existente. Suporta tanto **Mapeamento via Atributos** quanto **Mapeamento Fluente**.

## Recursos

- **Database First**: Conecta ao seu banco de dados (via FireDAC) e extrai informações do esquema.
- **Mapeamento de Tabelas e Colunas**: Gera classes para tabelas e propriedades para colunas.
- **Mapeamento de Tipos**: Mapeia automaticamente tipos SQL para tipos Delphi (Integer, string, TDateTime, etc.).
- **Suporte a Nullable**: Utiliza `Nullable<T>` para colunas de banco que permitem nulo.
- **Relacionamentos**: Detecta Chaves Estrangeiras e gera propriedades de navegação para lazy loading.
- **Detecção Many-to-Many**: Identifica automaticamente tabelas de junção e gera propriedades bidirecionais com o atributo `[ManyToMany]`.
- **Convenções de Nomenclatura**: Converte automaticamente nomes `snake_case` do banco para `PascalCase` em Delphi (Classes no singular, Coleções no plural).
- **Precisão SQLite**: A partir da Versão 1.1, utiliza `PRAGMA` para detectar com precisão Chaves Primárias Compostas e Chaves Estrangeiras no SQLite, contornando limitações padrão do FireDAC.

## Uso via CLI (Recomendado)

A forma mais fácil de usar o scaffolding é através da CLI do Dext:

```bash
dext scaffold --connection <string> --driver <driver> [options]
```

### Opções

| Opção | Alias | Descrição |
|--------|-------|-----------|
| `--connection` | `-c` | String de conexão FireDAC ou caminho do arquivo do banco |
| `--driver` | `-d` | Driver do banco: `sqlite`, `pg`, `mssql`, `firebird`, `mysql`, `oracle` |
| `--output` | `-o` | Caminho do arquivo de saída (padrão: `Entities.pas`) |
| `--fluent` | | Usa Mapeamento Fluente em vez de Atributos |
| `--tables` | `-t` | Nomes das tabelas (separados por vírgula) para incluir |
| `--unit` | `-u` | Nome da unit (a unit sempre leva o nome do arquivo de saída) |
| `--schema` | `-s` | *Schema* / *search path* do banco |
| `--smart` | | Smart Properties (`IntType`, `StringType`...). **É o padrão** |
| `--poco` | | Tipos nativos do Delphi (`Nullable<Integer>`, `string`) e classes de metadados `TEntityType` |
| `--no-metadata` | | Não gera as classes `TEntityType` |
| `--with-metadata` | | Gera as classes `TEntityType` |

Sem `--smart` nem `--poco`, o gerador escreve Smart Properties e nenhuma classe de metadados. `--poco` troca para tipos nativos e liga as classes de metadados; `--no-metadata` e `--with-metadata` sobrepõem essa escolha.

### Exemplos

**SQLite**:
```bash
dext scaffold -c "meuapp.db" -d sqlite -o Models/Entities.pas
```

**PostgreSQL**:
```bash
dext scaffold -c "host=localhost;database=meuapp;user=postgres;password=secret" -d pg --fluent
```

## Uso Programático

Para cenários avançados, você pode usar a API de scaffolding diretamente:

```pascal
uses
  Dext.Entity.Scaffolding,
  Dext.Entity.Drivers.FireDAC;

procedure GenerateEntities;
var
  Connection: IDbConnection;
  Provider: ISchemaProvider;
  Generator: IEntityGenerator;
  Tables: TArray<string>;
  MetaList: TArray<TMetaTable>;
  Code: string;
begin
  Connection := TFireDACConnection.Create(FDConnection1);
  Provider := TFireDACSchemaProvider.Create(Connection);
  
  // Extrai Metadados
  Tables := Provider.GetTables;
  for var i := 0 to High(Tables) do
    AddTableToMetaList(Provider.GetTableMetadata(Tables[i]));
    
  // Gera o Código
  Generator := TDelphiEntityGenerator.Create;
  Code := Generator.GenerateUnit('MinhasEntidades', MetaList);
  
  TFile.WriteAllText('MinhasEntidades.pas', Code);
end;
```

### Scaffolding via Templates (Avançado)

A partir da versão 1.0, o Dext utiliza um **Motor de Templates** (`TTemplatedEntityGenerator`) para a geração de código. Isso permite customizar a saída alterando arquivos `.template`.

O motor baseado em templates lida automaticamente com:
- **Detecção de Tabelas de Junção**: Tabelas que apenas ligam outras duas tabelas são identificadas como junções e não são geradas como entidades separadas.
- **Atributo ManyToMany**: Propriedades bidirecionais são adicionadas às entidades relacionadas usando o atributo `[ManyToMany]`.
- **Dext.Collections**: As propriedades geradas utilizam `IEntityCollection<T>` (baseado em `IList<T>`) para o gerenciamento de relacionamentos.

O modo de arquivo único (`gmSingleFile`) escreve uma unit `Entities`. Todas as classes são declaradas adiante (`TUser = class;`) no início da seção `interface`, então entidades que se referenciam compilam sem `uses` entre units. Os nomes das classes vão para o singular (`users` vira `TUser`), diferente do gerador do CLI, que mantém o nome da tabela (`TUsers`).

Para usar o gerador por templates programaticamente:

```pascal
uses
  Dext.Entity.TemplatedScaffolding;

procedure GenerateTemplated;
var
  Generator: TTemplatedEntityGenerator;
begin
  Generator := TTemplatedEntityGenerator.Create;
  // Os metadados são processados e renderizados usando templates estilo razor
  Generator.Generate(MetaList, 'Templates/entity.pas.template', 'Output/');
end;
```

## Exemplo de Código Gerado

```pascal
[Table('users')]
TUser = class
private
  FId: Integer;
  FName: string;
public
  [PK] [AutoInc] 
  property Id: Integer read FId write FId;
  
  [Column('name')] 
  property Name: string read FName write FName;
end;
```

---

[← Migrations](migrations.md) | [Próximo: Multi-Tenancy →](multi-tenancy.md)
