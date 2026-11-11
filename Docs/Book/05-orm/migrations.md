# Migrations

Version control for your database schema. Dext supports both **Pascal-based** (compiled) and **JSON-based** (external) migrations.

## Automated Rename Detection
Starting with version 2.1, Dext supports non-destructive renames via the `[RenamedFrom]` attribute.

```pascal
[Table('Users')]
[RenamedFrom('LegacyUsers')] // Tells the migrator this was previously 'LegacyUsers'
TUser = class
private
  [RenamedFrom('FullName')] // Tells the migrator this was 'FullName'
  FName: string;
...
```

When you add a migration, Dext will generate a `Rename` operation instead of a `Drop` and `Add` pair, preserving your data.

## Creating a Pascal Migration

Pascal migrations are units that implement the `IMigration` interface and are registered at initialization.

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

## JSON Migrations (External)

For CI/CD environments where you don't want DDL permissions in the main app, you can use JSON migrations executed by `dext.exe`.

**Example (`20251205_CreateUsers.json`):**
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

## CLI Commands

The Dext CLI (`dext.exe`) is the primary tool for managing migrations.

```bash
# Apply pending migrations
dext migrate:up

# Rollback last migration
dext migrate:down

# Check status
dext migrate:list

# Generate skeleton (Pascal)
dext migrate:generate --name AddOrdersTable
```

## Schema Builder API

### Columns

Inside `Up` or `Down`, use the `Builder` object:

```pascal
// Within CreateTable proc
T.Column('id', 'INTEGER').PrimaryKey.Identity;
T.Column('name', 'VARCHAR').Length(100).NotNull;
T.Column('price', 'DECIMAL').Precision(18, 2).Default('0.00');
T.Column('is_active', 'BOOLEAN').Default('1');
```

### Table Operations

```pascal
// Add a new column
Builder.AddColumn('users', 'phone', 'VARCHAR', 20);

// Drop a column
Builder.DropColumn('users', 'legacy_field');

// Create an Index
Builder.CreateIndex('users', 'IX_Users_Email', ['Email'], True);

// Rename a table (v2.1+)
Builder.RenameTable('old_name', 'new_name');

// Rename a column (v2.1+)
Builder.RenameColumn('users', 'old_col', 'new_col');

// Reference data: one INSERT per row; DeleteData is the inverse
Builder.Seed('settings', ['Key', 'Value'],
  [['theme', 'dark'], ['lang', 'pt-BR']]);
Builder.DeleteData('settings', ['Key', 'Value'],
  [['theme', 'dark'], ['lang', 'pt-BR']]);
```

### Execution (Safety Handshake)

You can validate schema compatibility at startup without running migrations:

```pascal
if not Context.Migrator.ValidateSchemaCompatibility('20251205_CreateUsers') then
  raise Exception.Create('Database schema is outdated!');
```

---

[← Relationships](relationships.md) | [Next: Scaffolding →](scaffolding.md)
