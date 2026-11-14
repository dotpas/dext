unit Dext.Entity.SQLServerDialect.Tests;

// What EnsureCreated writes for SQL Server was run against SQL Server 2025
// Developer: BOOLEAN and TIMESTAMP are not what the server needs (it has no
// BOOLEAN, and its TIMESTAMP is a row version that holds no date). These tests
// pin the types the server accepts.

interface

uses
  System.SysUtils,
  Data.DB,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Entity.Dialects,
  Dext.Entity.Migrations.Operations;

type
  [TestFixture('SQL Server dialect')]
  TSQLServerDialectTests = class
  private
    FDialect: ISQLDialect;
  public
    [Setup]
    procedure CreateDialect;

    [Test]
    [Description('A Boolean field is a BIT: SQL Server has no BOOLEAN type')]
    procedure Boolean_Field_Is_Bit;

    [Test]
    [Description('A date-time field is DATETIME2: TIMESTAMP in SQL Server is a row version')]
    procedure DateTime_Field_Is_DateTime2;

    [Test]
    [Description('Binary and memo fields use the MAX types, not BLOB and TEXT')]
    procedure Binary_And_Memo_Fields_Use_Max_Types;

    [Test]
    [Description('Date, time, guid and numbers keep their types')]
    procedure Other_Field_Types_Are_Kept;

    [Test]
    [Description('DROP INDEX names the table: SQL Server refuses it alone')]
    procedure Drop_Index_Names_The_Table;

    [Test]
    [Description('Renames go through sp_rename: there is no RENAME in SQL Server')]
    procedure Renames_Use_Sp_Rename;
  end;

implementation

procedure TSQLServerDialectTests.CreateDialect;
begin
  FDialect := TSQLServerDialect.Create;
end;

procedure TSQLServerDialectTests.Boolean_Field_Is_Bit;
begin
  Should(FDialect.GetColumnTypeForField(ftBoolean)).Be('BIT');
end;

procedure TSQLServerDialectTests.DateTime_Field_Is_DateTime2;
begin
  Should(FDialect.GetColumnTypeForField(ftDateTime)).Be('DATETIME2');
  Should(FDialect.GetColumnTypeForField(ftTimeStamp)).Be('DATETIME2');
end;

procedure TSQLServerDialectTests.Binary_And_Memo_Fields_Use_Max_Types;
begin
  Should(FDialect.GetColumnTypeForField(ftBlob)).Be('VARBINARY(MAX)');
  Should(FDialect.GetColumnTypeForField(ftVarBytes)).Be('VARBINARY(MAX)');
  Should(FDialect.GetColumnTypeForField(ftMemo)).Be('NVARCHAR(MAX)');
  Should(FDialect.GetColumnTypeForField(ftWideMemo)).Be('NVARCHAR(MAX)');
end;

procedure TSQLServerDialectTests.Other_Field_Types_Are_Kept;
begin
  Should(FDialect.GetColumnTypeForField(ftDate)).Be('DATE');
  Should(FDialect.GetColumnTypeForField(ftTime)).Be('TIME');
  Should(FDialect.GetColumnTypeForField(ftGuid)).Be('UNIQUEIDENTIFIER');
  Should(FDialect.GetColumnTypeForField(ftInteger)).Be('INTEGER');
  Should(FDialect.GetColumnTypeForField(ftLargeint)).Be('BIGINT');
  Should(FDialect.GetColumnTypeForField(ftCurrency)).Be('DECIMAL(18,4)');
end;

procedure TSQLServerDialectTests.Drop_Index_Names_The_Table;
var
  Op: TDropIndexOperation;
begin
  Op := TDropIndexOperation.Create('clientes', 'ux_nome');
  try
    Should(FDialect.GenerateMigration(Op)).Be('DROP INDEX [ux_nome] ON [clientes]');
  finally
    Op.Free;
  end;
end;

procedure TSQLServerDialectTests.Renames_Use_Sp_Rename;
var
  Tabela: TRenameTableOperation;
  Coluna: TRenameColumnOperation;
begin
  Tabela := TRenameTableOperation.Create('clientes', 'clientes2');
  Coluna := TRenameColumnOperation.Create('clientes', 'Cidade', 'Municipio');
  try
    Should(FDialect.GenerateMigration(Tabela))
      .Be('EXEC sp_rename N''[clientes]'', N''clientes2''');
    // O nome novo vai sem colchetes: sp_rename o toma literalmente.
    Should(FDialect.GenerateMigration(Coluna))
      .Be('EXEC sp_rename N''[clientes].[Cidade]'', N''Municipio'', N''COLUMN''');
  finally
    Tabela.Free;
    Coluna.Free;
  end;
end;

end.
