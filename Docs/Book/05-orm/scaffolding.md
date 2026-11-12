# Scaffolding

The Dext ORM Scaffolding tool allows you to automatically generate Delphi Entity classes from an existing database schema. It supports both **Attribute-based Mapping** and **Fluent Mapping**.

## Features

- **Database First**: Connects to your existing database (via FireDAC) and extracts schema information.
- **Table & Column Mapping**: Generates classes for tables and properties for columns.
- **Type Mapping**: Automatically maps SQL types (INT, VARCHAR, DATE, etc.) to Delphi types (Integer, string, TDateTime, etc.).
- **Nullable Support**: Uses `Nullable<T>` for nullable database columns.
- **Relationships**: Detects Foreign Keys and generates navigation properties for lazy loading.
- **Many-to-Many Detection**: Automatically identifies junction tables and generates bidirectional `[ManyToMany]` properties.
- **Naming Conventions**: Automatically converts `snake_case` database names to `PascalCase` Delphi names (Singularized Classes, Pluralized Collections).
- **SQLite Precision**: Since Version 1.1, uses `PRAGMA` to accurately detect Composite Primary Keys and Foreign Keys in SQLite, bypassing standard FireDAC metadata limitations.

## CLI Usage (Recommended)

The easiest way to use scaffolding is via the Dext CLI:

```bash
dext scaffold --connection <string> --driver <driver> [options]
```

### Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--connection` | `-c` | FireDAC connection string or database file path |
| `--driver` | `-d` | Database driver: `sqlite`, `pg`, `mssql`, `firebird` |
| `--output` | `-o` | Output file path (default: `Entities.pas`) |
| `--fluent` | | Use Fluent Mapping instead of Attributes |
| `--tables` | `-t` | Comma-separated table names to include (default: all) |

### Examples

**SQLite**:
```bash
dext scaffold -c "myapp.db" -d sqlite -o Models/Entities.pas
```

**PostgreSQL**:
```bash
dext scaffold -c "host=localhost;database=myapp;user=postgres;password=secret" -d pg --fluent
```

## Programmatic Usage

You can use the scaffolding API directly in your Delphi code. The logic is encapsulated in the `Dext.Entity.Scaffolding` unit.

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
  
  Tables := Provider.GetTables;
  SetLength(MetaList, Length(Tables));
  for var i := 0 to High(Tables) do
    MetaList[i] := Provider.GetTableMetadata(Tables[i]);
    
  Generator := TDelphiEntityGenerator.Create;
  Code := Generator.GenerateUnit('MyEntities', MetaList);
  TFile.WriteAllText('MyEntities.pas', Code);
end;
```

### Templated Scaffolding (Advanced)

Since Version 1.0, Dext uses a **Templated Engine** (`TTemplatedEntityGenerator`) for code generation. This allows you to customize the output by modifying `.template` files.

The templated engine automatically handles:
- **Join Table Detection**: Tables that only link two other tables are identified as junction tables and are not generated as separate entities.
- **ManyToMany Attribute**: Bidirectional properties are added to the related entities using the `[ManyToMany]` attribute.
- **Dext.Collections**: Generated properties use `IEntityCollection<T>` (based on `IList<T>`) for relationship management.

Single-file mode (`gmSingleFile`) writes one `Entities` unit. Every class is declared forward (`TUser = class;`) at the top of the `interface` section, so entities that reference each other compile without `uses` between units. Class names are singularized (`users` becomes `TUser`), unlike the CLI generator, which keeps the table name (`TUsers`).

To use the templated generator programmatically:

```pascal
uses
  Dext.Entity.TemplatedScaffolding;

procedure GenerateTemplated;
var
  Generator: TTemplatedEntityGenerator;
begin
  Generator := TTemplatedEntityGenerator.Create;
  // Metadata is processed and rendered using razor-style templates
  Generator.Generate(MetaList, 'Templates/entity.pas.template', 'Output/');
end;
```

## Generated Code Structure

### Attribute-Based Mapping (Default)

```pascal
unit Entities;

interface

uses
  Dext.Entity, Dext.Types.Nullable, Dext.Types.Lazy;

type
  [Table('users')]
  TUser = class
  private
    FId: Integer;
    FName: string;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    
    [Column('name')]
    property Name: string read FName write FName;
  end;

implementation

end.
```

## Supported Databases

- SQLite
- PostgreSQL
- SQL Server
- Firebird
- MySQL (Experimental)

---

[← Migrations](migrations.md) | [Next: Multi-Tenancy →](multi-tenancy.md)
