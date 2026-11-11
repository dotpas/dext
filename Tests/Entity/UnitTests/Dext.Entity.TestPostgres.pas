unit Dext.Entity.TestPostgres;

{***************************************************************************}
{  Access to a real PostgreSQL server for the tests that can run on it.     }
{                                                                           }
{  DEXT_TEST_PG           FireDAC connection string (with Database=...).    }
{                         Not set: the tests use SQLite in memory.          }
{  DEXT_TEST_PG_VENDORLIB Optional path of the libpq.dll to load.           }
{***************************************************************************}

interface

/// <summary>The connection string of the test server ('' when none).</summary>
function TestPgConnection: string;

/// <summary>Registers the FireDAC driver once, with the configured libpq.</summary>
procedure TestPgEnsureDriver;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  FireDAC.Stan.Intf,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef;

var
  GLink: TFDPhysPgDriverLink;

function TestPgConnection: string;
begin
  Result := GetEnvironmentVariable('DEXT_TEST_PG');
end;

procedure TestPgEnsureDriver;
var
  Lib: string;
begin
  if GLink <> nil then
    Exit;
  GLink := TFDPhysPgDriverLink.Create(nil);
  Lib := GetEnvironmentVariable('DEXT_TEST_PG_VENDORLIB');
  if Lib <> '' then
  begin
    SetEnvironmentVariable('PATH', PChar(ExtractFilePath(Lib) + ';' +
      GetEnvironmentVariable('PATH')));
    GLink.VendorLib := Lib;
  end;
end;

initialization

finalization
  FreeAndNil(GLink);

end.
