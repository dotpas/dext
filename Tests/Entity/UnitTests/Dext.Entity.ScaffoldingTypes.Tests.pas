unit Dext.Entity.ScaffoldingTypes.Tests;

{***************************************************************************}
{  Regression: SQLTypeToDelphiType matched integer types with Contains      }
{  ('INT'), so INTERVAL and POINT (PostgreSQL) were scaffolded as Integer.  }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity.Scaffolding;

type
  [TestFixture]
  TScaffoldingTypesTests = class
  private
    FGenerator: TDelphiEntityGenerator;
    FOwner: IEntityGenerator;
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure Interval_Is_Not_An_Integer;
    [Test]
    procedure Point_Is_Not_An_Integer;
    [Test]
    procedure Integer_Types_Keep_Working;
    [Test]
    procedure SqlServer_UniqueIdentifier_Is_A_Guid;
    [Test]
    procedure Firebird_Text_Blob_Is_A_String_And_Binary_Blob_Is_Bytes;
    [Test]
    procedure Tinyint_One_Is_A_Boolean;
    [Test]
    procedure Unbounded_Text_Declares_No_MaxLength;
  end;

implementation

procedure TScaffoldingTypesTests.Setup;
begin
  FGenerator := TDelphiEntityGenerator.Create;
  FOwner := FGenerator;
end;

procedure TScaffoldingTypesTests.Interval_Is_Not_An_Integer;
begin
  Should(FGenerator.SQLTypeToDelphiType('INTERVAL')).Be('string');
  Should(FGenerator.SQLTypeToDelphiType('INTERVAL DAY TO SECOND'))
    .Be('string');
end;

procedure TScaffoldingTypesTests.Point_Is_Not_An_Integer;
begin
  Should(FGenerator.SQLTypeToDelphiType('POINT')).Be('string');
end;

procedure TScaffoldingTypesTests.Integer_Types_Keep_Working;
begin
  Should(FGenerator.SQLTypeToDelphiType('INT')).Be('Integer');
  Should(FGenerator.SQLTypeToDelphiType('INTEGER')).Be('Integer');
  Should(FGenerator.SQLTypeToDelphiType('BIGINT')).Be('Int64');
  Should(FGenerator.SQLTypeToDelphiType('SMALLINT')).Be('SmallInt');
  Should(FGenerator.SQLTypeToDelphiType('TINYINT')).Be('Integer');
  Should(FGenerator.SQLTypeToDelphiType('SERIAL')).Be('Integer');
end;

procedure TScaffoldingTypesTests.SqlServer_UniqueIdentifier_Is_A_Guid;
begin
  // FireDAC reports the SQL Server type as "uniqueidentifier".
  Should(FGenerator.SQLTypeToDelphiType('uniqueidentifier')).Be('TGUID');
end;

procedure TScaffoldingTypesTests.Firebird_Text_Blob_Is_A_String_And_Binary_Blob_Is_Bytes;
begin
  Should(FGenerator.SQLTypeToDelphiType('BLOB SUB_TYPE 1')).Be('string');
  Should(FGenerator.SQLTypeToDelphiType('BLOB SUB_TYPE TEXT')).Be('string');
  Should(FGenerator.SQLTypeToDelphiType('BLOB SUB_TYPE 0')).Be('TBytes');
  Should(FGenerator.SQLTypeToDelphiType('BLOB')).Be('TBytes');
end;

procedure TScaffoldingTypesTests.Tinyint_One_Is_A_Boolean;
begin
  // MySQL and MariaDB have no BOOLEAN: it is a TINYINT(1).
  Should(FGenerator.SQLTypeToDelphiType('TINYINT', 1)).Be('Boolean');
  Should(FGenerator.SQLTypeToDelphiType('TINYINT', 4)).Be('Integer');
end;

procedure TScaffoldingTypesTests.Unbounded_Text_Declares_No_MaxLength;
var
  Tabela: TMetaTable;
  Col: TMetaColumn;
  Codigo: string;
begin
  // NVARCHAR(MAX) comes with a length of MaxInt: there is no limit to declare.
  Tabela.Name := 'notas';
  Tabela.ForeignKeys := [];
  Col := Default(TMetaColumn);
  Col.Name := 'texto';
  Col.DataType := 'nvarchar';
  Col.Length := MaxInt;
  Col.IsNullable := True;
  Tabela.Columns := [Col];

  Codigo := FGenerator.GenerateUnit('Gerado', [Tabela], msAttributes, psPOCO, False);

  Should(Codigo).Contain('property Texto: string');
  Should(Codigo.Contains('MaxLength')).BeFalse;
end;

end.
