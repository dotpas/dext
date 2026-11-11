# Operações em Lote Conscientes do Dialeto (Spec S59)

O `Dext.Entity` envia `INSERT`, `UPDATE` e `DELETE` em lote quando o `SaveChanges` encontra várias entidades do mesmo tipo no mesmo estado. `AddRange`, `UpdateRange` e `RemoveRange` são apenas laços sobre `Add`, `Update` e `Remove`: nada chega ao banco antes do `SaveChanges`, e o lote é decidido ali.

## O Que o `SaveChanges` Envia

| Entidades na unidade de trabalho | Comando enviado |
| :--- | :--- |
| Novas, chave informada pelo programa (atribuída, GUID, sequence) | Um `INSERT` com Array DML do FireDAC, todas as linhas de uma vez. O `BulkBatchSize` não o divide. |
| Novas, chave `[AutoInc]` | Um `INSERT` por linha (o novo Id é lido de volta para cada uma). |
| Modificadas | Em blocos de `BulkBatchSize` linhas (padrão 100), um comando por bloco. |
| Modificadas, com coluna `[Version]` | Um `UPDATE ... WHERE pk AND versao` por linha. |
| Removidas | Em blocos de `BulkBatchSize` linhas, um comando por bloco. |
| Removidas, com exclusão lógica ou com coluna `[Version]` | Um comando por linha (`UPDATE` na exclusão lógica, `DELETE ... AND versao` nas demais). |
| Novas ou modificadas, com propriedades de sombra | Um comando por linha. |
: {tbl-colwidths="[40, 60]"}

As linhas das entidades removidas com coluna `[Version]` e das propriedades de sombra vêm da leitura das verificações `IsBulk*Safe` do `TDbSet`; as demais foram executadas no SQLite e no PostgreSQL 18.

O `SaveChanges` inteiro roda numa transação: se um comando de um lote falha, nada daquele `SaveChanges` é mantido.

## Estratégias por Dialeto

O `TDextBatchStrategyFactory` escolhe como um `UPDATE` ou `DELETE` em lote é enviado:

- **MySQL / MariaDB**: `TDextMySqlBatchStrategy` reescreve o lote num único comando (`UPDATE table SET col = CASE WHEN pk = x THEN y END WHERE pk IN (...)`).
- **PostgreSQL, SQLite, Oracle, Firebird e os demais**: `TDextNativeArrayDmlStrategy`, Array DML do FireDAC com o mesmo comando parametrizado e um jogo de parâmetros por linha. Verificado no SQLite e no PostgreSQL 18: o comando registrado é `UPDATE "t" SET ... WHERE "Id" = :w_0 (Batch size: N, Offset: 0)`.

A `TDextPostgresBatchStrategy`, que reescreve o `UPDATE` em lote como `UPDATE ... FROM (VALUES ...)`, existe em `Dext.Entity.BatchStrategy`, mas a fábrica não a seleciona para o PostgreSQL hoje; a estratégia do MySQL a reutiliza no `DELETE` em lote.

Nenhum número de latência é publicado aqui: o tempo por linha depende do driver, da rede e do servidor, e precisa ser medido no seu ambiente (conte os comandos enviados com `Db.OnLog` e cronometre o `SaveChanges`).

## Uso Prático

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

  // Marca as 500 como modificadas; no SaveChanges sai um UPDATE a cada 100
  Ctx.Users.UpdateRange(Users);
  Ctx.SaveChanges;

  // Marca as 500 como removidas; no SaveChanges sai um DELETE a cada 100
  Ctx.Users.RemoveRange(Users);
  Ctx.SaveChanges;
end;
```
