# Migrações

Controle de versão para o seu esquema de banco de dados. O Dext suporta migrações baseadas em **Pascal** (compiladas) e **JSON** (externas).

## Detecção Automática de Renomeação
A partir da versão 2.1, o Dext suporta renomeações não destrutivas através do atributo `[RenamedFrom]`.

```pascal
[Table('Users')]
[RenamedFrom('LegacyUsers')] // Informa ao migrador que anteriormente era 'LegacyUsers'
TUser = class
private
  [RenamedFrom('FullName')] // Informa ao migrador que era 'FullName'
  FName: string;
...
```

Ao adicionar uma migração, o Dext gerará uma operação de `Rename` em vez de um par `Drop` e `Add`, preservando seus dados.

## Criando uma Migration Pascal

Migrations Pascal são units que implementam a interface `IMigration` e são registradas na inicialização.

```pascal
unit Migrations.M20251205_CreateUsers;

interface

uses
  Dext.Entity.Migrations,
  Dext.Entity.Migrations.Builder;

type
  TMigration_20251205_CreateUsers = class(TInterfacedObject, IMigration)
  public
    function GetId: string;
    procedure Up(Builder: TSchemaBuilder);
    procedure Down(Builder: TSchemaBuilder);
  end;

implementation

function TMigration_20251205_CreateUsers.GetId: string;
begin
  Result := '20251205_CreateUsers';
end;

procedure TMigration_20251205_CreateUsers.Up(Builder: TSchemaBuilder);
begin
  Builder.CreateTable('users', procedure(T: TTableBuilder)
    begin
      T.Column('id', 'INTEGER').PrimaryKey.Identity;
      T.Column('name', 'VARCHAR').Length(100).NotNull;
      T.Column('email', 'VARCHAR').Length(255).NotNull;
      T.Column('created_at', 'TIMESTAMP').Default('CURRENT_TIMESTAMP');
    end);
end;

procedure TMigration_20251205_CreateUsers.Down(Builder: TSchemaBuilder);
begin
  Builder.DropTable('users');
end;

initialization
  RegisterMigration(TMigration_20251205_CreateUsers.Create);

end.
```

## Migrations JSON (Externas)

Para ambientes de CI/CD onde você não quer permissões de DDL no app principal, você pode usar migrations JSON executadas pelo `dext.exe`.

**Exemplo (`20251205_CreateUsers.json`):**
```json
{
  "id": "20251205060000",
  "description": "Create Users Table",
  "operations": [
    {
      "op": "create_table",
      "name": "Users",
      "columns": [
        { "name": "Id", "type": "INTEGER", "pk": true },
        { "name": "Email", "type": "VARCHAR", "length": 255, "nullable": false }
      ]
    }
  ]
}
```

## Comandos CLI

A Dext CLI (`dext.exe`) é a ferramenta principal para gerenciar migrations.

```bash
# Aplica migrations pendentes
dext migrate:up

# Reverte a última migration
dext migrate:down

# Lista o status
dext migrate:list

# Gera o esqueleto (Pascal)
dext migrate:generate --name AddOrdersTable
```

## Schema Builder API

### Colunas

Dentro de `Up` ou `Down`, use o objeto `Builder`:

```pascal
// Dentro do proc CreateTable
T.Column('id', 'INTEGER').PrimaryKey.Identity;
T.Column('name', 'VARCHAR').Length(100).NotNull;
T.Column('price', 'DECIMAL').Precision(18, 2).Default('0.00');
T.Column('is_active', 'BOOLEAN').Default('1');
```

### Operações de Tabela

```pascal
// Adiciona uma nova coluna
Builder.AddColumn('users', 'phone', 'VARCHAR', 20);

// Remove uma coluna
Builder.DropColumn('users', 'legacy_field');

// Criar um Índice
Builder.CreateIndex('users', 'IX_Users_Email', ['Email'], True);

// Renomear uma tabela (v2.1+)
Builder.RenameTable('nome_antigo', 'nome_novo');

// Renomear uma coluna (v2.1+)
Builder.RenameColumn('users', 'col_antiga', 'col_nova');

// Dados de referência: um INSERT por linha; DeleteData é o inverso
Builder.Seed('settings', ['Key', 'Value'],
  [['theme', 'dark'], ['lang', 'pt-BR']]);
Builder.DeleteData('settings', ['Key', 'Value'],
  [['theme', 'dark'], ['lang', 'pt-BR']]);
```

### Execução (Safety Handshake)

Você pode validar a compatibilidade do schema no startup sem rodar migrations:

```pascal
if not Context.Migrator.ValidateSchemaCompatibility('20251205_CreateUsers') then
  raise Exception.Create('O schema do banco está desatualizado!');
```

---

[← Relacionamentos](relacionamentos.md) | [Próximo: Scaffolding →](scaffolding.md)
