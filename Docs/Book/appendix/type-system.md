# Appendix: Type System Reference

Quick reference for Dext types and ORM mappings.

## Smart Types

| Type | Description | SQL Mapping |
|------|-------------|-------------|
| `Prop<T>` | Smart property wrapper | N/A (compile-time) |
| `Nullable<T>` | Nullable value | `NULL` columns |
| `ILazy<T>` | Lazy-loaded reference | Foreign keys |
| `TUUID` | RFC 9562 UUID | `UUID` / `GUID` |

## Nullable<T>: Local Variable Initialization

> **Warning:** a *local* `Nullable<T>` is not guaranteed to start as null.

Delphi only zero-initializes local variables of records that contain managed
fields (`string`, interfaces, dynamic arrays...). `Nullable<T>` stores its state
in a plain `Boolean`, so for `T` = `Integer`, `Int64`, `Double`, `TDateTime`,
etc. the record has no managed content and a local variable starts with
**whatever was on the stack**. It may report `HasValue = True` with a garbage
value. `Nullable<string>` is safe because the `string` forces initialization.

```pascal
var
  Ean: Nullable<Int64>;   // local: state is undefined!
begin
  Ean.Clear;              // always initialize explicitly
  // or: Ean := Default(Nullable<Int64>);
  if Ean.IsNull then ...
end;
```

- Only **locals** are affected. Class fields, globals and heap-allocated
  objects (including ORM entities) are zero-initialized and are safe.
- Rule: call `Clear` (or assign `Default(...)`) before reading a local
  `Nullable<T>` that was not assigned a value.
- A framework-level fix is planned (spec S76): a `class operator Initialize`
  for Delphi 10.4+. Older compilers will keep needing the explicit `Clear`.

## Entity Attributes

| Attribute | Description |
|-----------|-------------|
| `[Table('name')]` | Map class to table |
| `[Column('name')]` | Map property to column |
| `[PK]` | Primary key |
| `[AutoInc]` | Auto-increment |
| `[ForeignKey('col')]` | Foreign key reference |
| `[NotMapped]` | Exclude from mapping |
| `[SoftDelete]` | Soft delete support |
| `[Version]` | Optimistic concurrency |

## SQL Type Mappings

| Delphi Type | PostgreSQL | SQL Server | SQLite |
|-------------|------------|------------|--------|
| `Integer` | `INTEGER` | `INT` | `INTEGER` |
| `Int64` | `BIGINT` | `BIGINT` | `INTEGER` |
| `Double` | `DOUBLE PRECISION` | `FLOAT` | `REAL` |
| `string` | `VARCHAR/TEXT` | `NVARCHAR` | `TEXT` |
| `TDateTime` | `TIMESTAMP` | `DATETIME2` | `TEXT` |
| `Boolean` | `BOOLEAN` | `BIT` | `INTEGER` |
| `TGUID` | `UUID` | `UNIQUEIDENTIFIER` | `TEXT` |
| `TBytes` | `BYTEA` | `VARBINARY` | `BLOB` |

---

[← Advanced](../10-advanced/README.md)
