unit Dext.Entity.TestServer;

{***************************************************************************}
{  The database of the tests that can run on a real server.                 }
{                                                                           }
{  No variable set: SQLite in memory.                                       }
{                                                                           }
{  DEXT_TEST_SERVER   postgresql (default when DEXT_TEST_PG is set),        }
{                     mariadb, firebird, interbase or sqlserver.            }
{                     When it names a server whose connection is missing,   }
{                     the tests fail instead of falling back to SQLite.     }
{                                                                           }
{  Connection of each server (FireDAC parameters; the PostgreSQL one has    }
{  Database=..., the others do not: each test creates its own database):   }
{    DEXT_TEST_PG, DEXT_TEST_MARIADB, DEXT_TEST_FIREBIRD,                   }
{    DEXT_TEST_INTERBASE, DEXT_TEST_SQLSERVER                               }
{  DEXT_TEST_<SERVER>_VENDORLIB  the client library, of the same bitness    }
{                                as the executable (optional)               }
{  DEXT_TEST_FIREBIRD_DIR / DEXT_TEST_INTERBASE_DIR                         }
{                                folder of the .fdb / .ib files of the      }
{                                server                                     }
{***************************************************************************}

interface

uses
  Dext.Entity;

type
  TTestServer = (tsSQLite, tsPostgreSQL, tsMariaDB, tsFirebird, tsInterBase,
    tsSQLServer);

/// <summary>The server the tests run on (tsSQLite when none is configured).</summary>
function TestServer: TTestServer;

/// <summary>True when the tests run on a server and not on SQLite in memory.</summary>
function TestServerActive: Boolean;

/// <summary>
///   Options of a context on an empty database named AName: SQLite in memory,
///   a schema of the PostgreSQL database (see TestDbPrepare), or a database
///   (a file, on Firebird and InterBase) created for the test.
/// </summary>
function TestDbOptions(const AName: string): TDbContextOptionsBuilder;

/// <summary>Makes the context's schema empty (PostgreSQL only; the others start empty).</summary>
procedure TestDbPrepare(const ACtx: TDbContext; const AName: string);

/// <summary>Frees the context and drops what TestDbOptions created.</summary>
procedure TestDbRelease(var ACtx: TDbContext; const AName: string);

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.StrUtils,
  System.SysUtils,
  Dext.Entity.Setup,
  Dext.Entity.TestPostgres,
  FireDAC.Comp.Client,
  FireDAC.Stan.Intf,
  FireDAC.Phys.MySQL,
  FireDAC.Phys.MySQLDef,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.IB,
  FireDAC.Phys.IBDef,
  FireDAC.Phys.MSSQL,
  FireDAC.Phys.MSSQLDef;

var
  GLinkMy: TFDPhysMySQLDriverLink;
  GLinkFB: TFDPhysFBDriverLink;
  GLinkIB: TFDPhysIBDriverLink;
  GLinkMS: TFDPhysMSSQLDriverLink;

function Prefix(AServer: TTestServer): string;
begin
  case AServer of
    tsMariaDB: Result := 'DEXT_TEST_MARIADB';
    tsFirebird: Result := 'DEXT_TEST_FIREBIRD';
    tsInterBase: Result := 'DEXT_TEST_INTERBASE';
    tsSQLServer: Result := 'DEXT_TEST_SQLSERVER';
  else
    Result := 'DEXT_TEST_PG';
  end;
end;

function Connection(AServer: TTestServer): string;
begin
  Result := GetEnvironmentVariable(Prefix(AServer));
end;

function TestServer: TTestServer;
var
  Name: string;
begin
  Name := LowerCase(GetEnvironmentVariable('DEXT_TEST_SERVER'));
  if Name = '' then
  begin
    if TestPgConnection <> '' then
      Exit(tsPostgreSQL);
    Exit(tsSQLite);
  end;
  if Name = 'postgresql' then Result := tsPostgreSQL
  else if Name = 'mariadb' then Result := tsMariaDB
  else if Name = 'firebird' then Result := tsFirebird
  else if Name = 'interbase' then Result := tsInterBase
  else if Name = 'sqlserver' then Result := tsSQLServer
  else
    raise Exception.CreateFmt('DEXT_TEST_SERVER=%s: unknown server', [Name]);

  if Connection(Result) = '' then
    raise Exception.CreateFmt('DEXT_TEST_SERVER=%s, but %s is not set',
      [Name, Prefix(Result)]);
end;

function TestServerActive: Boolean;
begin
  Result := TestServer <> tsSQLite;
end;

procedure PrepareLink(AServer: TTestServer);
var
  Lib: string;
begin
  Lib := GetEnvironmentVariable(Prefix(AServer) + '_VENDORLIB');
  if Lib <> '' then
    // The DLLs the client library needs are in the same folder.
    SetEnvironmentVariable('PATH', PChar(ExtractFilePath(Lib) + ';' +
      GetEnvironmentVariable('PATH')));
  case AServer of
    tsPostgreSQL:
      TestPgEnsureDriver;
    tsMariaDB:
      if GLinkMy = nil then
      begin
        GLinkMy := TFDPhysMySQLDriverLink.Create(nil);
        GLinkMy.VendorLib := Lib;
      end;
    tsFirebird:
      if GLinkFB = nil then
      begin
        GLinkFB := TFDPhysFBDriverLink.Create(nil);
        GLinkFB.VendorLib := Lib;
      end;
    tsInterBase:
      if GLinkIB = nil then
      begin
        GLinkIB := TFDPhysIBDriverLink.Create(nil);
        GLinkIB.VendorLib := Lib;
      end;
    tsSQLServer:
      if GLinkMS = nil then
        GLinkMS := TFDPhysMSSQLDriverLink.Create(nil);
  end;
end;

function DatabaseFile(AServer: TTestServer; const AName: string): string;
begin
  Result := GetEnvironmentVariable(Prefix(AServer) + '_DIR');
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result);
  Result := Result + AName + IfThen(AServer = tsFirebird, '.fdb', '.ib');
end;

function AdminConnection(AServer: TTestServer; const AExtra: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.Params.Delimiter := ';';
    Result.Params.StrictDelimiter := True;
    Result.Params.DelimitedText := Connection(AServer) + AExtra;
    case AServer of
      tsMariaDB: Result.DriverName := 'MySQL';
      tsSQLServer: Result.DriverName := 'MSSQL';
      tsFirebird: Result.DriverName := 'FB';
      tsInterBase: Result.DriverName := 'IB';
    end;
  except
    Result.Free;
    raise;
  end;
end;

procedure DropDatabase(AServer: TTestServer; const AName: string);
var
  Conn: TFDConnection;
begin
  PrepareLink(AServer);
  case AServer of
    tsMariaDB:
      begin
        Conn := AdminConnection(AServer, '');
        try
          Conn.Open;
          Conn.ExecSQL('DROP DATABASE IF EXISTS ' + AName);
        finally
          Conn.Free;
        end;
      end;
    tsSQLServer:
      begin
        Conn := AdminConnection(AServer, '');
        try
          Conn.Open;
          Conn.ExecSQL('IF DB_ID(''' + AName + ''') IS NOT NULL BEGIN ' +
            'ALTER DATABASE [' + AName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; ' +
            'DROP DATABASE [' + AName + '] END');
        finally
          Conn.Free;
        end;
      end;
    tsFirebird, tsInterBase:
      if FileExists(DatabaseFile(AServer, AName)) then
      begin
        // DropDatabase=Yes removes the file when the connection closes.
        Conn := AdminConnection(AServer, ';Database=' +
          DatabaseFile(AServer, AName) + ';OpenMode=Open;DropDatabase=Yes');
        try
          Conn.Open;
        finally
          Conn.Free;
        end;
      end;
  end;
end;

procedure CreateDatabase(AServer: TTestServer; const AName: string);
var
  Conn: TFDConnection;
begin
  if not (AServer in [tsMariaDB, tsSQLServer]) then
    Exit; // OpenMode=OpenOrCreate creates the file on the first connection
  Conn := AdminConnection(AServer, '');
  try
    Conn.Open;
    if AServer = tsSQLServer then
      Conn.ExecSQL('CREATE DATABASE [' + AName + ']')
    else
      Conn.ExecSQL('CREATE DATABASE ' + AName + ' CHARACTER SET utf8mb4');
  finally
    Conn.Free;
  end;
end;

function TestDbOptions(const AName: string): TDbContextOptionsBuilder;
var
  Server: TTestServer;
  Parts: TStringList;
  I: Integer;
begin
  Server := TestServer;
  if Server = tsSQLite then
    Exit(DbContextOptions.UseSQLite(':memory:'));

  PrepareLink(Server);
  if Server <> tsPostgreSQL then
  begin
    DropDatabase(Server, AName);
    CreateDatabase(Server, AName);
  end;

  case Server of
    tsPostgreSQL:
      Result := DbContextOptions.UsePostgreSQL(TestPgConnection);
    tsMariaDB:
      Result := DbContextOptions.UseMySQL(Connection(Server) + ';Database=' + AName);
    tsSQLServer:
      Result := DbContextOptions.UseSQLServer(Connection(Server) + ';Database=' + AName);
    tsFirebird:
      Result := DbContextOptions.UseFirebird(Connection(Server) + ';Database=' +
        DatabaseFile(Server, AName) + ';CharacterSet=UTF8;OpenMode=OpenOrCreate;PageSize=16384');
  else
    begin
      // InterBase has no Use method of its own: pick the driver, pass the parameters.
      Result := DbContextOptions.UseDriver('IB');
      Parts := TStringList.Create;
      try
        Parts.Delimiter := ';';
        Parts.StrictDelimiter := True;
        Parts.DelimitedText := Connection(Server) + ';Database=' +
          DatabaseFile(Server, AName) + ';CharacterSet=UTF8;OpenMode=OpenOrCreate;PageSize=16384';
        for I := 0 to Parts.Count - 1 do
          Result := Result.AddParam(Parts.Names[I], Parts.ValueFromIndex[I]);
      finally
        Parts.Free;
      end;
    end;
  end;
end;

procedure TestDbPrepare(const ACtx: TDbContext; const AName: string);
begin
  if TestServer = tsMariaDB then
    // Tests that write SQL by hand quote the names the standard way.
    ACtx.Connection.CreateCommand(
      'SET SESSION sql_mode = CONCAT(@@sql_mode, '',ANSI_QUOTES'')').Execute;
  if TestServer <> tsPostgreSQL then
    Exit;
  ACtx.Connection.CreateCommand('DROP SCHEMA IF EXISTS ' + AName + ' CASCADE').Execute;
  ACtx.Connection.CreateCommand('CREATE SCHEMA ' + AName).Execute;
  ACtx.Connection.CreateCommand('SET search_path TO ' + AName).Execute;
end;

procedure TestDbRelease(var ACtx: TDbContext; const AName: string);
begin
  case TestServer of
    tsSQLite:
      FreeAndNil(ACtx);
    tsPostgreSQL:
      begin
        if ACtx <> nil then
          ACtx.Connection.CreateCommand('DROP SCHEMA IF EXISTS ' + AName +
            ' CASCADE').Execute;
        FreeAndNil(ACtx);
      end;
  else
    begin
      FreeAndNil(ACtx);
      DropDatabase(TestServer, AName);
    end;
  end;
end;

initialization

finalization
  FreeAndNil(GLinkMy);
  FreeAndNil(GLinkFB);
  FreeAndNil(GLinkIB);
  FreeAndNil(GLinkMS);

end.
