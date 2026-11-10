unit Dext.Entity.PostgreSQL.Tests;

{***************************************************************************}
{  Tests that need a real PostgreSQL server. They run only when the         }
{  environment variable DEXT_TEST_PG is set to a FireDAC connection string  }
{  (including Database=...); otherwise each test returns at once.           }
{  DEXT_TEST_PG_VENDORLIB optionally points to the libpq.dll to load.       }
{                                                                           }
{  Regression: EnsureCreated used the metadata listing of FireDAC to decide }
{  whether a table exists, and that listing includes the other schemas. A   }
{  table with the same name in another schema made EnsureCreated skip the   }
{  CREATE TABLE, so the current schema stayed without the table.            }
{***************************************************************************}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  Dext.Entity.Drivers.Interfaces,
  FireDAC.Stan.Intf,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef;

type
  [Table('pg_schema_thing')]
  TPgSchemaThing = class
  private
    FId: Integer;
    FName: string;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  TPgSchemaDb = class(TDbContext)
  private
    function GetThings: IDbSet<TPgSchemaThing>;
  public
    property Things: IDbSet<TPgSchemaThing> read GetThings;
  end;

  [TestFixture('PostgreSQL: tables and schemas')]
  TPostgreSQLSchemaTests = class
  private
    function Connection: string;
    function NewDb: TPgSchemaDb;
    function RelationExists(Db: TPgSchemaDb; const ASchema: string): Boolean;
  public
    [Test]
    [Description('EnsureCreated creates the table in the current schema even when another schema has one with the same name')]
    procedure EnsureCreated_Ignores_A_Table_Of_Another_Schema;
  end;

implementation

var
  GLink: TFDPhysPgDriverLink;

function TPgSchemaDb.GetThings: IDbSet<TPgSchemaThing>;
begin
  Result := Entities<TPgSchemaThing>;
end;

function TPostgreSQLSchemaTests.Connection: string;
begin
  Result := GetEnvironmentVariable('DEXT_TEST_PG');
end;

function TPostgreSQLSchemaTests.NewDb: TPgSchemaDb;
var
  Lib: string;
begin
  if GLink = nil then
  begin
    GLink := TFDPhysPgDriverLink.Create(nil);
    Lib := GetEnvironmentVariable('DEXT_TEST_PG_VENDORLIB');
    if Lib <> '' then
    begin
      SetEnvironmentVariable('PATH', PChar(ExtractFilePath(Lib) + ';' +
        GetEnvironmentVariable('PATH')));
      GLink.VendorLib := Lib;
    end;
  end;
  Result := TPgSchemaDb.Create(DbContextOptions.UsePostgreSQL(Connection));
end;

function TPostgreSQLSchemaTests.RelationExists(Db: TPgSchemaDb;
  const ASchema: string): Boolean;
var
  Reader: IDbReader;
begin
  Reader := Db.Connection.CreateCommand(
    'SELECT COUNT(*) FROM information_schema.tables ' +
    'WHERE table_schema = ''' + ASchema + ''' ' +
    'AND table_name = ''pg_schema_thing''').ExecuteQuery;
  Reader.Next;
  Result := Reader.GetInt32(0) = 1;
end;

procedure TPostgreSQLSchemaTests.EnsureCreated_Ignores_A_Table_Of_Another_Schema;
var
  DbA, DbB: TPgSchemaDb;
begin
  if Connection = '' then
    Exit; // no server configured

  DbA := NewDb;
  DbB := NewDb;
  try
    DbA.Connection.CreateCommand('DROP SCHEMA IF EXISTS dext_ut_a CASCADE').Execute;
    DbA.Connection.CreateCommand('DROP SCHEMA IF EXISTS dext_ut_b CASCADE').Execute;
    DbA.Connection.CreateCommand('CREATE SCHEMA dext_ut_a').Execute;
    DbA.Connection.CreateCommand('CREATE SCHEMA dext_ut_b').Execute;

    DbA.Connection.CreateCommand('SET search_path TO dext_ut_a').Execute;
    DbA.EnsureCreated;
    Should(RelationExists(DbA, 'dext_ut_a')).BeTrue;

    // The same table name already exists in schema A: schema B still needs it.
    DbB.Connection.CreateCommand('SET search_path TO dext_ut_b').Execute;
    DbB.EnsureCreated;
    Should(RelationExists(DbB, 'dext_ut_b')).BeTrue;

    DbA.Connection.CreateCommand('DROP SCHEMA dext_ut_a CASCADE').Execute;
    DbA.Connection.CreateCommand('DROP SCHEMA dext_ut_b CASCADE').Execute;
  finally
    DbA.Free;
    DbB.Free;
  end;
end;

initialization

finalization
  GLink.Free;

end.
