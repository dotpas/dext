unit EntityDemo.DbConfig;

interface

{$I Dext.inc}

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  {$IFDEF DEXT_ENABLE_DB_MYSQL} FireDAC.Phys.MySQL, {$ENDIF}
  {$IFDEF DEXT_ENABLE_DB_IB} FireDAC.Phys.IB, {$ENDIF}
  Dext.Entity.Drivers.FireDAC.Links,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Dialects;

type
  /// <summary>
  ///   Database provider enumeration
  /// </summary>
  TDatabaseProvider = (
    dpSQLiteMemory,
    dpSQLite,
    dpPostgreSQL,
    dpFirebird,
    dpMySQL,
    dpSQLServerWindowsAuthetication,
    dpSQLServer,
    dpOracle,
    dpInterBase
  );

  /// <summary>
  ///   Database configuration helper
  ///   Provides easy switching between database providers for testing
  /// </summary>
  TDbConfig = class
  private
    class var FCurrentProvider: TDatabaseProvider;
    class var FSQLiteFile: string;
    class var FPostgreSQLHost: string;
    class var FPostgreSQLPort: Integer;
    class var FPostgreSQLDatabase: string;
    class var FPostgreSQLUsername: string;
    class var FPostgreSQLPassword: string;
    class var FFirebirdFile: string;
    class var FFirebirdUsername: string;
    class var FFirebirdPassword: string;
    class var FInterBaseFile: string;
    class var FInterBaseUsername: string;
    class var FInterBasePassword: string;
    {$IFDEF DEXT_ENABLE_DB_IB}
    class var FInterBaseDriverLink: TFDPhysIBDriverLink;
    {$ENDIF}
    class var FSQLServerHost: string;
    class var FSQLServerDatabase: string;
    class var FSQLServerUsername: string;
    class var FSQLServerPassword: string;
    class var FMySQLHost: string;
    class var FMySQLPort: Integer;
    class var FMySQLDatabase: string;
    class var FMySQLUsername: string;
    class var FMySQLPassword: string;
    class var FMySQLVendorLib: string;
    class var FMySQLVendorHome: string;
    {$IFDEF DEXT_ENABLE_DB_MYSQL}
    class var FMySQLDriverLink: TFDPhysMySQLDriverLink;
    {$ENDIF}
  public
    /// <summary>
    ///   Initialize default configuration
    /// </summary>
    class constructor Create;

    /// <summary>
    ///   Get current database provider
    /// </summary>
    class function GetProvider: TDatabaseProvider; static;

    /// <summary>
    ///   Set current database provider
    /// </summary>
    class procedure SetProvider(AProvider: TDatabaseProvider); static;

    /// <summary>
    ///   Create a connection for the current provider
    /// </summary>
    class function CreateConnection: IDbConnection; static;

    /// <summary>
    ///   Create a dialect for the current provider
    /// </summary>
    class function CreateDialect: ISQLDialect; static;

    /// <summary>
    ///   Get provider name as string
    /// </summary>
    class function GetProviderName: string; static;

    /// <summary>
    ///   Configure SQLite connection
    /// </summary>
    class procedure ConfigureSQLite(const AFileName: string = 'test.db'); static;

    /// <summary>
    ///   Configure SQLite In-Memory connection
    /// </summary>
    class procedure ConfigureSQLiteMemory; static;

    /// <summary>
    ///   Configure PostgreSQL connection
    /// </summary>
    class procedure ConfigurePostgreSQL(
      const AHost: string = 'localhost';
      APort: Integer = 5432;
      const ADatabase: string = 'dext_test';
      const AUsername: string = 'postgres';
      const APassword: string = 'postgres'
    ); static;

    /// <summary>
    ///   Configure Firebird connection
    /// </summary>
    class procedure ConfigureFirebird(
      const AFileName: string = 'test.fdb';
      const AUsername: string = 'SYSDBA';
      const APassword: string = 'masterkey'
    ); static;

    /// <summary>
    ///   Configure InterBase connection (needs DEXT_ENABLE_DB_IB in Dext.inc).
    ///   AVendorLib is the gds32.dll / ibclient64.dll of the same bitness as the exe.
    /// </summary>
    class procedure ConfigureInterBase(
      const AFileName: string = 'test.ib';
      const AUsername: string = 'SYSDBA';
      const APassword: string = 'masterkey';
      const AVendorLib: string = ''
    ); static;

    /// <summary>
    ///   Configure SQL Server connection with SQL Authentication
    /// </summary>
    class procedure ConfigureSQLServer(
      const AHost: string = 'localhost';
      const ADatabase: string = 'dext_test';
      const AUsername: string = 'sa';
      const APassword: string = 'Password123!'
    ); overload; static;

    /// <summary>
    ///   Configure SQL Server connection with Windows Authentication
    /// </summary>
    class procedure ConfigureSQLServerWindowsAuth(
      const AHost: string = 'localhost';
      const ADatabase: string = 'dext_test'
    ); static;

    /// <summary>
    ///   Configure MySQL/MariaDB connection.
    ///   Note: On 64-bit systems with 64-bit libmariadb.dll/libmysql.dll, compile for Win64 platform.
    /// </summary>
    /// <param name="AVendorLib">Path to libmysql.dll or libmariadb.dll (optional if in PATH)</param>
    /// <param name="AVendorHome">Base directory containing lib folder (optional)</param>
    class procedure ConfigureMySQL(
      const AHost: string = 'localhost';
      APort: Integer = 3306;
      const ADatabase: string = 'dext_test';
      const AUsername: string = 'root';
      const APassword: string = '';
      const AVendorLib: string = '';
      const AVendorHome: string = ''
    ); static;

    /// <summary>
    ///   Drop and recreate database (for testing)
    /// </summary>
    class procedure ResetDatabase; static;

    /// <summary>
    ///   Ensures the database exists, creating it if necessary.
    ///   For server-based databases (MySQL, PostgreSQL, SQL Server).
    /// </summary>
    class procedure EnsureDatabaseExists; static;
  end;

implementation

uses
  System.IOUtils,
  System.Variants,
  Data.DB;

{ TDbConfig }

class constructor TDbConfig.Create;
begin
  // Default to SQLite for compatibility
  FCurrentProvider := dpSQLite;

  // Default SQLite configuration
  FSQLiteFile := TPath.Combine(ExtractFilePath(ParamStr(0)), 'test.db');

  // Default PostgreSQL configuration
  FPostgreSQLHost := 'localhost';
  FPostgreSQLPort := 5432;
  FPostgreSQLDatabase := 'dext_test';
  FPostgreSQLUsername := 'postgres';
  FPostgreSQLPassword := 'postgres';

  // Default Firebird configuration
  FFirebirdFile := TPath.Combine(ExtractFilePath(ParamStr(0)), 'test.fdb');
  FFirebirdUsername := 'SYSDBA';
  FFirebirdPassword := 'masterkey';

  // Default InterBase configuration
  FInterBaseFile := TPath.Combine(ExtractFilePath(ParamStr(0)), 'test.ib');
  FInterBaseUsername := 'SYSDBA';
  FInterBasePassword := 'masterkey';

  // Default SQL Server configuration
  FSQLServerHost := 'localhost';
  FSQLServerDatabase := 'dext_test';
  FSQLServerUsername := 'sa';
  FSQLServerPassword := 'Password123!';

  // Default MySQL/MariaDB configuration
  FMySQLHost := 'localhost';
  FMySQLPort := 3306;
  FMySQLDatabase := 'dext_test';
  FMySQLUsername := 'root';
  FMySQLPassword := '';
end;

class function TDbConfig.GetProvider: TDatabaseProvider;
begin
  Result := FCurrentProvider;
end;

class procedure TDbConfig.SetProvider(AProvider: TDatabaseProvider);
begin
  FCurrentProvider := AProvider;
  WriteLn('🔄 Database Provider changed to: ' + GetProviderName);
end;

class function TDbConfig.CreateConnection: IDbConnection;
var
  FDConn: TFDConnection;
begin
  FDConn := TFDConnection.Create(nil);

  case FCurrentProvider of
    dpSQLite:
    begin
      FDConn.DriverName := 'SQLite';
      FDConn.Params.Values['Database'] := FSQLiteFile;
      FDConn.Params.Values['LockingMode'] := 'Normal';
    end;

    dpPostgreSQL:
    begin
      FDConn.DriverName := 'PG';
      FDConn.Params.Values['Server'] := FPostgreSQLHost;
      FDConn.Params.Values['Port'] := FPostgreSQLPort.ToString;
      FDConn.Params.Values['Database'] := FPostgreSQLDatabase;
      FDConn.Params.Values['User_Name'] := FPostgreSQLUsername;
      FDConn.Params.Values['Password'] := FPostgreSQLPassword;
    end;

    dpFirebird:
    begin
      FDConn.DriverName := 'FB';
      FDConn.Params.Values['Database'] := FFirebirdFile;
      FDConn.Params.Values['User_Name'] := FFirebirdUsername;
      FDConn.Params.Values['Password'] := FFirebirdPassword;
      FDConn.Params.Values['CharacterSet'] := 'UTF8';
      FDConn.Params.Values['Protocol'] := 'Local';  // Use local protocol for embedded/local server
      FDConn.Params.Values['OpenMode'] := 'OpenOrCreate';  // Create database if it doesn't exist
      FDConn.Params.Values['PageSize'] := '16384';  // 16KB page size (recommended)
      FDConn.Params.Values['SQLDialect'] := '3';  // SQL Dialect 3
    end;

    dpInterBase:
    begin
      FDConn.DriverName := 'IB';
      FDConn.Params.Values['Database'] := FInterBaseFile;
      FDConn.Params.Values['User_Name'] := FInterBaseUsername;
      FDConn.Params.Values['Password'] := FInterBasePassword;
      FDConn.Params.Values['CharacterSet'] := 'UTF8';
      FDConn.Params.Values['OpenMode'] := 'OpenOrCreate';
    end;

    dpSQLServer:
    begin
      FDConn.DriverName := 'MSSQL';
      FDConn.Params.Values['Server'] := FSQLServerHost;
      FDConn.Params.Values['Database'] := FSQLServerDatabase;

      // Fix for ODBC Driver 18: Trust server certificate to avoid SSL errors
      FDConn.Params.Values['ODBCAdvanced'] := 'TrustServerCertificate=yes';

      // Check if using Windows Authentication (empty username)
      if FSQLServerUsername = '' then
      begin
        FDConn.Params.Values['OSAuthent'] := 'Yes';
        FDConn.Params.Values['MetaDefSchema'] := 'dbo';
        FDConn.Params.Values['MetaCurSchema'] := 'dbo';
      end
      else
      begin
        FDConn.Params.Values['User_Name'] := FSQLServerUsername;
        FDConn.Params.Values['Password'] := FSQLServerPassword;
        FDConn.Params.Values['MetaDefSchema'] := FSQLServerUsername;
        FDConn.Params.Values['MetaCurSchema'] := FSQLServerUsername;
      end;
    end;

    dpMySQL:
    begin
      FDConn.DriverName := 'MySQL';
      FDConn.Params.Values['Server'] := FMySQLHost;
      FDConn.Params.Values['Port'] := FMySQLPort.ToString;
      FDConn.Params.Values['Database'] := FMySQLDatabase;
      FDConn.Params.Values['User_Name'] := FMySQLUsername;
      FDConn.Params.Values['Password'] := FMySQLPassword;
      FDConn.Params.Values['CharacterSet'] := 'utf8mb4';

      // VendorLib/Home are now handled by TFDPhysMySQLDriverLink in ConfigureMySQL
      // to avoid caching issues and ensure correct driver loading.
    end;

    else
      raise Exception.CreateFmt('Database provider %s not yet implemented', [GetProviderName]);
  end;

  Result := TFireDACConnection.Create(FDConn);
end;

class function TDbConfig.CreateDialect: ISQLDialect;
begin
  case FCurrentProvider of
    dpSQLite:     Result := TSQLiteDialect.Create;
    dpPostgreSQL: Result := TPostgreSQLDialect.Create;
    dpFirebird:   Result := TFirebirdDialect.Create;
    dpInterBase:  Result := TInterBaseDialect.Create;
    dpSQLServer:  Result := TSQLServerDialect.Create;
    dpMySQL:      Result := TMySQLDialect.Create;
    else
      raise Exception.CreateFmt('Dialect for %s not yet implemented', [GetProviderName]);
  end;
end;

class function TDbConfig.GetProviderName: string;
begin
  case FCurrentProvider of
    dpSQLite:     Result := 'SQLite';
    dpPostgreSQL: Result := 'PostgreSQL';
    dpFirebird:   Result := 'Firebird';
    dpInterBase:  Result := 'InterBase';
    dpMySQL:      Result := 'MySQL';
    dpSQLServer:  Result := 'SQL Server';
    dpOracle:     Result := 'Oracle';
    else          Result := 'Unknown';
  end;
end;

class procedure TDbConfig.ConfigureSQLite(const AFileName: string);
begin
  TDbConfig.SetProvider(dpSQLite);
  FSQLiteFile := AFileName;
  WriteLn('✅ SQLite configured: ' + AFileName);
end;

class procedure TDbConfig.ConfigureSQLiteMemory;
begin
  TDbConfig.SetProvider(dpSQLite);
  FSQLiteFile := ':memory:';
  WriteLn('✅ SQLite configured: In-Memory');
end;

class procedure TDbConfig.ConfigurePostgreSQL(
  const AHost: string;
  APort: Integer;
  const ADatabase: string;
  const AUsername: string;
  const APassword: string
);
begin
  TDbConfig.SetProvider(dpPostgreSQL);
  FPostgreSQLHost := AHost;
  FPostgreSQLPort := APort;
  FPostgreSQLDatabase := ADatabase;
  FPostgreSQLUsername := AUsername;
  FPostgreSQLPassword := APassword;
  WriteLn(Format('✅ PostgreSQL configured: %s:%d/%s', [AHost, APort, ADatabase]));
end;

class procedure TDbConfig.ConfigureFirebird(
  const AFileName: string;
  const AUsername: string;
  const APassword: string
);
begin
  TDbConfig.SetProvider(dpFirebird);
  FFirebirdFile := AFileName;
  FFirebirdUsername := AUsername;
  FFirebirdPassword := APassword;
  WriteLn('✅ Firebird configured: ' + AFileName);
end;

class procedure TDbConfig.ConfigureInterBase(
  const AFileName: string;
  const AUsername: string;
  const APassword: string;
  const AVendorLib: string
);
begin
  TDbConfig.SetProvider(dpInterBase);
  FInterBaseFile := AFileName;
  FInterBaseUsername := AUsername;
  FInterBasePassword := APassword;
  {$IFDEF DEXT_ENABLE_DB_IB}
  if (AVendorLib <> '') and (FInterBaseDriverLink = nil) then
  begin
    FInterBaseDriverLink := TFDPhysIBDriverLink.Create(nil);
    FInterBaseDriverLink.VendorLib := AVendorLib;
  end;
  {$ELSE}
  WriteLn('Warning: InterBase needs DEXT_ENABLE_DB_IB defined in Dext.inc; the driver is not linked.');
  {$ENDIF}
  WriteLn('InterBase configured: ' + AFileName);
  // The demo entities map their keys with [AutoInc], and InterBase has no identity
  // column: EnsureCreated raises ENotSupportedException asking for [Sequence].
  WriteLn('Note: the demo entities use [AutoInc]; InterBase needs [Sequence] (no identity column).');
end;

class procedure TDbConfig.ConfigureSQLServer(
  const AHost: string;
  const ADatabase: string;
  const AUsername: string;
  const APassword: string
);
begin
  TDbConfig.SetProvider(dpSQLServer);
  FSQLServerHost := AHost;
  FSQLServerDatabase := ADatabase;
  FSQLServerUsername := AUsername;
  FSQLServerPassword := APassword;
  WriteLn(Format('✅ SQL Server configured: %s/%s (SQL Auth: %s)', [AHost, ADatabase, AUsername]));
end;

class procedure TDbConfig.ConfigureSQLServerWindowsAuth(
  const AHost: string;
  const ADatabase: string
);
begin
  TDbConfig.SetProvider(dpSQLServer);
  FSQLServerHost := AHost;
  FSQLServerDatabase := ADatabase;
  FSQLServerUsername := '';  // Empty username triggers Windows Authentication
  FSQLServerPassword := '';
  WriteLn(Format('✅ SQL Server configured: %s/%s (Windows Authentication)', [AHost, ADatabase]));
end;

class procedure TDbConfig.ConfigureMySQL(
  const AHost: string;
  APort: Integer;
  const ADatabase: string;
  const AUsername: string;
  const APassword: string;
  const AVendorLib: string;
  const AVendorHome: string
);
begin
  TDbConfig.SetProvider(dpMySQL);
  FMySQLHost := AHost;
  FMySQLPort := APort;
  FMySQLDatabase := ADatabase;
  FMySQLUsername := AUsername;
  FMySQLPassword := APassword;
  FMySQLVendorLib := AVendorLib;
  FMySQLVendorHome := AVendorHome;

  // Configure Driver Link globally for MySQL
  {$IFDEF DEXT_ENABLE_DB_MYSQL}
  if FMySQLDriverLink = nil then
    FMySQLDriverLink := TFDPhysMySQLDriverLink.Create(nil);

  if (AVendorLib <> '') or (AVendorHome <> '') then
  begin
    FMySQLDriverLink.Release;
    if AVendorLib <> '' then
      FMySQLDriverLink.VendorLib := AVendorLib;

    if AVendorHome <> '' then
      FMySQLDriverLink.VendorHome := AVendorHome;
  end;
  {$ELSE}
  if (AVendorLib <> '') or (AVendorHome <> '') then
    WriteLn('⚠️  Warning: MySQL VendorLib/Home config ignored because DEXT_ENABLE_DB_MYSQL is not defined.');
  {$ENDIF}

  WriteLn(Format('✅ MySQL/MariaDB configured: %s:%d/%s', [AHost, APort, ADatabase]));
  if AVendorLib <> '' then
    WriteLn('   VendorLib (DriverLink): ' + AVendorLib);
  if AVendorHome <> '' then
    WriteLn('   VendorHome (DriverLink): ' + AVendorHome);
end;

class procedure TDbConfig.ResetDatabase;
begin
  case FCurrentProvider of
    dpSQLite:
    begin
      // Delete SQLite file if exists
      if TFile.Exists(FSQLiteFile) then
      begin
        TFile.Delete(FSQLiteFile);
        WriteLn('🗑️  Deleted SQLite database: ' + FSQLiteFile);
      end;
    end;

    dpPostgreSQL:
    begin
      // PostgreSQL: Drop all tables (handled by EnsureCreated)
      WriteLn('⚠️  PostgreSQL: Tables will be recreated by EnsureCreated');
    end;

    dpFirebird:
    begin
      // Delete Firebird file if exists
      if TFile.Exists(FFirebirdFile) then
      begin
        TFile.Delete(FFirebirdFile);
        WriteLn('🗑️  Deleted Firebird database: ' + FFirebirdFile);
      end;
    end;

    dpInterBase:
    begin
      // Delete InterBase file if exists
      if TFile.Exists(FInterBaseFile) then
      begin
        TFile.Delete(FInterBaseFile);
        WriteLn('Deleted InterBase database: ' + FInterBaseFile);
      end;
    end;

    dpSQLServer:
    begin
      // SQL Server: Tables will be recreated by EnsureCreated
      WriteLn('⚠️  SQL Server: Tables will be recreated by EnsureCreated');
    end;
  end;
end;

class procedure TDbConfig.EnsureDatabaseExists;
var
  FDConn: TFDConnection;
  SQL: string;
  Query: Variant;
begin
  case FCurrentProvider of
    dpMySQL:
    begin
      // Connect without specifying database, then CREATE DATABASE
      FDConn := TFDConnection.Create(nil);
      try
        FDConn.DriverName := 'MySQL';
        FDConn.Params.Values['Server'] := FMySQLHost;
        FDConn.Params.Values['Port'] := FMySQLPort.ToString;
        FDConn.Params.Values['User_Name'] := FMySQLUsername;
        FDConn.Params.Values['Password'] := FMySQLPassword;
        FDConn.Params.Values['CharacterSet'] := 'utf8mb4';

        // Don't specify database - we're creating it
        // FDConn.Params.Values['Database'] := ...

        if FMySQLVendorLib <> '' then
          FDConn.Params.Values['VendorLib'] := FMySQLVendorLib;
        if FMySQLVendorHome <> '' then
          FDConn.Params.Values['VendorHome'] := FMySQLVendorHome;

        FDConn.Connected := True;

        SQL := Format('CREATE DATABASE IF NOT EXISTS `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci',
          [FMySQLDatabase]);
        FDConn.ExecSQL(SQL);
        WriteLn('✅ Database created or already exists: ' + FMySQLDatabase);

        FDConn.Connected := False;
      finally
        FDConn.Free;
      end;
    end;

    dpPostgreSQL:
    begin
      // For PostgreSQL, CREATE DATABASE doesn't support IF NOT EXISTS
      // We need to check first
      FDConn := TFDConnection.Create(nil);
      try
        FDConn.DriverName := 'PG';
        FDConn.Params.Values['Server'] := FPostgreSQLHost;
        FDConn.Params.Values['Port'] := FPostgreSQLPort.ToString;
        FDConn.Params.Values['Database'] := 'postgres';  // Connect to default db
        FDConn.Params.Values['User_Name'] := FPostgreSQLUsername;
        FDConn.Params.Values['Password'] := FPostgreSQLPassword;

        FDConn.Connected := True;

        // PostgreSQL doesn't have CREATE DATABASE IF NOT EXISTS, so we check and create
        SQL := Format('SELECT 1 FROM pg_database WHERE datname = ''%s''', [FPostgreSQLDatabase]);
        Query := FDConn.ExecSQLScalar(SQL);
        if VarIsNull(Query) then
        begin
          SQL := Format('CREATE DATABASE %s', [FPostgreSQLDatabase]);
          FDConn.ExecSQL(SQL);
          WriteLn('✅ Database created: ' + FPostgreSQLDatabase);
        end
        else
          WriteLn('✅ Database already exists: ' + FPostgreSQLDatabase);

        FDConn.Connected := False;
      finally
        FDConn.Free;
      end;
    end;

    dpSQLServer:
    begin
      FDConn := TFDConnection.Create(nil);
      try
        FDConn.DriverName := 'MSSQL';
        FDConn.Params.Values['Server'] := FSQLServerHost;
        FDConn.Params.Values['Database'] := 'master';  // Connect to master db
        FDConn.Params.Values['ODBCAdvanced'] := 'TrustServerCertificate=yes';

        if FSQLServerUsername = '' then
        begin
          FDConn.Params.Values['OSAuthent'] := 'Yes';
        end
        else
        begin
          FDConn.Params.Values['User_Name'] := FSQLServerUsername;
          FDConn.Params.Values['Password'] := FSQLServerPassword;
        end;

        FDConn.Connected := True;

        SQL := Format('IF NOT EXISTS (SELECT name FROM master.sys.databases WHERE name = ''%s'') ' +
                       'CREATE DATABASE [%s]', [FSQLServerDatabase, FSQLServerDatabase]);
        FDConn.ExecSQL(SQL);
        WriteLn('✅ Database created or already exists: ' + FSQLServerDatabase);

        FDConn.Connected := False;
      finally
        FDConn.Free;
      end;
    end;

  else
    // SQLite, Firebird, InterBase - database file is created automatically
    WriteLn('ℹ️  Database file will be created automatically for ' + GetProviderName);
  end;
end;

end.
