program Orm.EntityDemo;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Utils,
  Dext,
  System.SysUtils,
  FireDAC.Comp.Client,
  EntityDemo.DbConfig in 'EntityDemo.DbConfig.pas',
  EntityDemo.Tests.AdvancedQuery in 'EntityDemo.Tests.AdvancedQuery.pas',
  EntityDemo.Tests.Bulk in 'EntityDemo.Tests.Bulk.pas',
  EntityDemo.Tests.CompositeKeys in 'EntityDemo.Tests.CompositeKeys.pas',
  EntityDemo.Tests.Concurrency in 'EntityDemo.Tests.Concurrency.pas',
  EntityDemo.Tests.CRUD in 'EntityDemo.Tests.CRUD.pas',
  EntityDemo.Tests.ExplicitLoading in 'EntityDemo.Tests.ExplicitLoading.pas',
  EntityDemo.Tests.FluentAPI in 'EntityDemo.Tests.FluentAPI.pas',
  EntityDemo.Tests.LazyExecution in 'EntityDemo.Tests.LazyExecution.pas',
  EntityDemo.Tests.LazyLoading in 'EntityDemo.Tests.LazyLoading.pas',
  EntityDemo.Tests.Relationships in 'EntityDemo.Tests.Relationships.pas',
  EntityDemo.Tests.Scaffolding in 'EntityDemo.Tests.Scaffolding.pas',
  EntityDemo.Tests.FluentMappingSyntax in 'EntityDemo.Tests.FluentMappingSyntax.pas',
  EntityDemo.Entities in 'EntityDemo.Entities.pas',
  EntityDemo.Tests.Migrations in 'EntityDemo.Tests.Migrations.pas',
  EntityDemo.Tests.Collections in 'EntityDemo.Tests.Collections.pas',
  EntityDemo.Tests.NoTracking in 'EntityDemo.Tests.NoTracking.pas',
  EntityDemo.Tests.MixedCompositeKeys in 'EntityDemo.Tests.MixedCompositeKeys.pas',
  EntityDemo.Tests.SoftDelete in 'EntityDemo.Tests.SoftDelete.pas',
  EntityDemo.Tests.Async in 'EntityDemo.Tests.Async.pas',
  EntityDemo.Tests.TypeSystem in 'EntityDemo.Tests.TypeSystem.pas',
  EntityDemo.Tests.TypeConverter in 'EntityDemo.Tests.TypeConverter.pas',
  EntityDemo.Tests.Dialect in 'EntityDemo.Tests.Dialect.pas',
  EntityDemo.TypeConverterExample in 'EntityDemo.TypeConverterExample.pas',
  EntityDemo.Entities.Info in 'EntityDemo.Entities.Info.pas',
  EntityDemo.Tests.Base in 'EntityDemo.Tests.Base.pas',
  EntityDemo.Tests.SQLCache in 'EntityDemo.Tests.SQLCache.pas',
  EntityDemo.Tests.CustomDialect in 'EntityDemo.Tests.CustomDialect.pas',
  EntityDemo.CustomDialect in 'EntityDemo.CustomDialect.pas',
  EntityDemo.Tests.Join in 'EntityDemo.Tests.Join.pas';

procedure ConfigureDatabase(Provider: TDatabaseProvider);
begin
  // ========================================
  // Database Configuration
  // ========================================
  // Uncomment the provider you want to test:
  case Provider of
    // Option 1: SQLite (Default - Memory, good for development)
    dpSQLiteMemory: TDbConfig.ConfigureSQLiteMemory;
    // Option 2: SQLite (File-based, good for development)
    dpSQLite: TDbConfig.ConfigureSQLite('test.db');
    // Option 2: PostgreSQL (Server-based, production-ready)
    dpPostgreSQL: TDbConfig.ConfigurePostgreSQL('localhost', 5432, 'postgres', 'postgres', 'root');
    // Option 3: Firebird
    dpFirebird: TDbConfig.ConfigureFirebird('C:\temp\dext_test.fdb', 'SYSDBA', 'masterkey');
    // Option 3b: InterBase (needs DEXT_ENABLE_DB_IB in Dext.inc)
    dpInterBase: TDbConfig.ConfigureInterBase('C:\temp\dext_test.ib', 'SYSDBA', 'masterkey');
    // Option 4: SQL Server with Windows Authentication (Recommended)
    dpSQLServerWindowsAuthetication: TDbConfig.ConfigureSQLServerWindowsAuth('localhost', 'dext_test');
    // Option 5: SQL Server with SQL Authentication
    dpSQLServer: TDbConfig.ConfigureSQLServer('localhost', 'dext_test', 'sa', 'SQL@d3veloper');
    // Option 6: MySQL / MariaDB
    dpMySQL: TDbConfig.ConfigureMySQL('localhost', 3306, 'dext_test', 'root', 'root',
      'libmariadb.dll', 'C:\Program Files\MariaDB 12.1\');
  else
    raise Exception.Create('Database not supported');
  end;


  if Provider in [dpSQLite, dpSQLiteMemory] then
  begin
    //RegisterExpectedMemoryLeak(Unknown)
  end;

  WriteLn('📊 Database Provider: ' + TDbConfig.GetProviderName);
  WriteLn('');
end;

procedure RunTest(const TestClass: TBaseTestClass);
var
  Test: TBaseTest;
begin
  WriteLn('Running Test: ', TestClass.ClassName);
  TBaseTest.CurrentTestName := TestClass.ClassName;
  Test := TestClass.Create;
  try
    try
      Test.Run;
    except
      on E: Exception do
      begin
        WriteLn('❌ Error running test ', TestClass.ClassName, ': ', E.Message);
        TBaseTest.ReportFailure(TestClass.ClassName + ': ' + E.Message);
      end;
    end;
  finally
    Test.Free;
  end;
end;

procedure RunAllTests;
begin
  // 1. CRUD Tests
  RunTest(TCRUDTest);
  // 2. Relationships Tests
  RunTest(TRelationshipTest);
  // 3. Advanced Query Tests
  RunTest(TAdvancedQueryTest);
  // 4. Composite Keys Tests
  RunTest(TCompositeKeyTest);
  // 5. Explicit Loading Tests
  RunTest(TExplicitLoadingTest);
  // 6. Lazy Loading Tests
  RunTest(TLazyLoadingTest);
  // 7. Fluent API Tests
  RunTest(TFluentAPITest);
  // 8. Lazy Execution Tests
  RunTest(TLazyExecutionTest);
  // 9. Bulk Operations Tests
  RunTest(TBulkTest);
  // 10. Concurrency Tests
  RunTest(TConcurrencyTest);
  // 11. Scaffolding Tests
  RunTest(TScaffoldingTest);
  // 12. Migrations Builder Tests
  RunTest(TMigrationsTest);
  // 13. Collections Tests
  RunTest(TCollectionsTest);
  // 14. No Tracking Tests
  RunTest(TNoTrackingTest);
  // 15. Mixed Composite Keys
  RunTest(TMixedCompositeKeyTest);
  // 16. Soft Delete Tests
  RunTest(TSoftDeleteTest);
  // 17. Async Tests
  RunTest(TAsyncTest);
  // 18. TypeSystem Tests
  RunTest(TTypeSystemTest);
  // 19. TypeConverter Tests
  RunTest(TTypeConverterTest);
  // 20. Dialect Tests
  RunTest(TDialectTest);
  // 21. Custom Dialect Tests
  RunTest(TCustomDialectTest);
  // 22. SQL Cache Tests
  RunTest(TSQLCacheTest);
  // 23. Join Pattern Tests
  RunTest(TJoinPatternsTest);
  // Print summary at the end

  TBaseTest.PrintSummary;
end;

var
  Provider: TDatabaseProvider;
  Arg: string;
begin
  SetConsoleCharSet;
  try
    WriteLn('🚀 Dext Entity ORM Demo Suite');
    WriteLn('=============================');
    WriteLn('');

    Provider := dpSQLiteMemory; // Default
    if ParamCount > 0 then
    begin
      Arg := ParamStr(1).ToLower;
      if Arg = 'sqlite' then Provider := dpSQLite
      else if Arg = 'sqlitememory' then Provider := dpSQLiteMemory
      else if Arg = 'postgresql' then Provider := dpPostgreSQL
      else if Arg = 'firebird' then Provider := dpFirebird
      else if Arg = 'interbase' then Provider := dpInterBase
      else if Arg = 'mysql' then Provider := dpMySQL
      else if Arg = 'mariadb' then Provider := dpMySQL
      else if Arg = 'sqlserver' then Provider := dpSQLServer
      else if Arg = 'sqlserverauth' then Provider := dpSQLServerWindowsAuthetication;
    end;
    ConfigureDatabase(Provider);
    TDbConfig.EnsureDatabaseExists; // Create database if not exists
    TBaseTest.DebugSql := False;
    RunAllTests;
  except
    on E: Exception do
      Writeln('❌ Critical Error: ', E.ClassName, ': ', E.Message);
  end;

  // Only pause if not running in automated mode
  if ParamCount = 0 then
    ConsolePause;
end.
