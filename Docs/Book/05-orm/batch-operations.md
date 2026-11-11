# Dialect-Aware Batch Operations (Spec S59)

`Dext.Entity` runs batch `INSERT`, `UPDATE` and `DELETE` statements when `SaveChanges` finds several entities of the same type in the same state. `AddRange`, `UpdateRange` and `RemoveRange` are plain loops over `Add`, `Update` and `Remove`: nothing reaches the database until `SaveChanges`, and the batch is decided there.

## What `SaveChanges` Sends

| Entities in the unit of work | Statement sent |
| :--- | :--- |
| New, key supplied by the program (assigned, GUID, sequence) | One `INSERT` with FireDAC Array DML, all rows at once. `BulkBatchSize` does not split it. |
| New, `[AutoInc]` key | One `INSERT` per row (the new Id is read back for each one). |
| Modified | In batches of `BulkBatchSize` rows (default 100), one statement per batch. |
| Modified, with a `[Version]` column | One `UPDATE ... WHERE pk AND version` per row. |
| Removed | In batches of `BulkBatchSize` rows, one statement per batch. |
| Removed, with soft delete, or with a `[Version]` column | One statement per row (`UPDATE` for soft delete, `DELETE ... AND version` otherwise). |
| New or modified, with shadow properties | One statement per row. |
: {tbl-colwidths="[40, 60]"}

The rows for removed entities with a `[Version]` column and for shadow properties come from reading the `IsBulk*Safe` checks of `TDbSet`; the others were executed on SQLite and PostgreSQL 18.

The whole `SaveChanges` runs in one transaction: if a statement of a batch fails, nothing of that `SaveChanges` is kept.

## Per-Dialect Strategies

`TDextBatchStrategyFactory` chooses how a batch `UPDATE` or `DELETE` is sent:

- **MySQL / MariaDB**: `TDextMySqlBatchStrategy` rewrites the batch into a single statement (`UPDATE table SET col = CASE WHEN pk = x THEN y END WHERE pk IN (...)`).
- **PostgreSQL, SQLite, Oracle, Firebird and the others**: `TDextNativeArrayDmlStrategy`, FireDAC Array DML with the same parameterized statement and one set of parameters per row. Verified on SQLite and PostgreSQL 18: the statement logged is `UPDATE "t" SET ... WHERE "Id" = :w_0 (Batch size: N, Offset: 0)`.

`TDextPostgresBatchStrategy`, which rewrites a batch `UPDATE` into `UPDATE ... FROM (VALUES ...)`, exists in `Dext.Entity.BatchStrategy` but the factory does not select it for PostgreSQL today; the MySQL strategy reuses it for batch `DELETE`.

No latency figure is published here: the time per row depends on the driver, the network and the server, and has to be measured in your environment (count the statements sent with `Db.OnLog` and time the `SaveChanges`).

## Usage Example

```pascal
var
  Users: TArray<TUser>;
  i: Integer;
begin
  SetLength(Users, 500);
  for i := 0 to 499 do
  begin
    Users[i] := Ctx.Users.Find(i + 1);
    Users[i].Status := 'Active';
  end;

  // Marks the 500 as modified; one UPDATE per 100 rows is sent on SaveChanges
  Ctx.Users.UpdateRange(Users);
  Ctx.SaveChanges;

  // Marks the 500 as removed; one DELETE per 100 rows is sent on SaveChanges
  Ctx.Users.RemoveRange(Users);
  Ctx.SaveChanges;
end;
```
