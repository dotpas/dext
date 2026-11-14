unit EntityDemo.Tests.Base;

interface

{$I Dext.inc}

uses
  Dext.Collections,
  System.Classes,
  System.SysUtils,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  Dext.Entity.Drivers.FireDAC.Links,
  FireDAC.Stan.ExprFuncs,
  FireDAC.ConsoleUI.Wait,
  FireDAC.Comp.Client,
  FireDAC.DApt,
  Dext.Entity,
  Dext.Entity.Context,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Dialects,
  Dext.Entity.Mapping,
  Dext.Entity.Cache,
  EntityDemo.Entities,
  EntityDemo.TypeConverterExample,
  EntityDemo.DbConfig;

type
  TBaseTestClass = class of TBaseTest;

  // Define a specific context for tests to register entities automatically
  TEntityDemoContext = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  end;

  TBaseTest = class
  private
    class var FTotalPassed: Integer;
    class var FTotalFailed: Integer;
    class var FFailedTests: IList<string>;
    class var FCurrentTestName: string;
  protected
    FConn: TFDConnection;
    FContext: TDbContext;

    procedure Log(const Msg: string);
    procedure LogSuccess(const Msg: string);
    procedure LogError(const Msg: string);
    procedure AssertTrue(Condition: Boolean; const SuccessMsg, FailMsg: string); overload;
    procedure AssertTrue(Condition: Boolean; const Msg: string); overload;

    procedure Setup; virtual;
    procedure TearDown; virtual;
  public
    class var DebugSql: Boolean;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure ResetCounters;
    class procedure PrintSummary;
    class procedure ReportFailure(const Msg: string);
    class property TotalPassed: Integer read FTotalPassed;
    class property TotalFailed: Integer read FTotalFailed;
    class property CurrentTestName: string read FCurrentTestName write FCurrentTestName;

    constructor Create;
    destructor Destroy; override;
    procedure Run; virtual; abstract;
  end;

implementation

{ TEntityDemoContext }

procedure TEntityDemoContext.OnModelCreating(Builder: TModelBuilder);
begin
  inherited;
  // Register Entities
  Builder.Entity<TUser>;
  Builder.Entity<TAddress>;
  Builder.Entity<TProduct>;
  Builder.Entity<TOrderItem>;
  Builder.Entity<TConverterTestEntity>;  // TypeConverter example
end;

{ TBaseTest }

constructor TBaseTest.Create;
begin
  inherited;
  Setup;
end;

destructor TBaseTest.Destroy;
begin
  TearDown;
  inherited;
end;

procedure TBaseTest.Setup;
var
  DbConnection: IDbConnection;
  Dialect: ISQLDialect;
  Tables: TStringList;

  procedure DropTableIfExists(const ATableName: string);
  var
    FoundIdx: Integer;
    i: Integer;
    CurrentTable: string;
  begin
    try
      case TDbConfig.GetProvider of
        dpSQLite:
        begin
          // SQLite and PostgreSQL support DROP TABLE IF EXISTS
          FConn.ExecSQL('DROP TABLE IF EXISTS ' + ATableName);
        end;

        dpPostgreSQL:
        begin
          // SQLite and PostgreSQL support DROP TABLE IF EXISTS
          FConn.ExecSQL('DROP TABLE IF EXISTS ' + ATableName + ' CASCADE');
        end;

        dpFirebird, dpInterBase:
        begin
          // Firebird/InterBase: Check if table exists first (case-insensitive search in list)
          Tables := TStringList.Create;
          try
            FConn.GetTableNames('', '', '', Tables, [osMy], [tkTable], True);

            FoundIdx := -1;
            for i := 0 to Tables.Count - 1 do
            begin
              // Firebird stores names in UPPERCASE unless quoted.
              // FireDAC GetTableNames returns them with quotes if they were created with quotes.
              // We check both quoted and unquoted case-insensitively.
              CurrentTable := Tables[i].Replace('"', '');
              if SameText(CurrentTable, ATableName) then
              begin
                FoundIdx := i;
                Break;
              end;
            end;

            if FoundIdx >= 0 then
            begin
              // Use the exact name from the list (it might include quotes already)
              FConn.ExecSQL('DROP TABLE ' + Tables[FoundIdx]);
              WriteLn('  🗑️  Dropped table: ' + ATableName);
            end;
          finally
            Tables.Free;
          end;
        end;

        dpSQLServer:
        begin
          // SQL Server 2016+ supports DROP TABLE IF EXISTS
          FConn.ExecSQL('DROP TABLE IF EXISTS [' + ATableName + ']');
        end;

        dpMySQL:
        begin
          // MySQL/MariaDB supports DROP TABLE IF EXISTS with backticks
          FConn.ExecSQL('DROP TABLE IF EXISTS `' + ATableName + '`');
        end;
      end;
    except
      on E: Exception do
        WriteLn('  ⚠️  Warning dropping ' + ATableName + ': ' + E.Message);
    end;
  end;

begin
  WriteLn('🔧 Setting up test with: ' + TDbConfig.GetProviderName);

  // 0. Reset Database (Delete file if exists)
  TDbConfig.ResetDatabase;

  // 1. Create connection using TDbConfig
  DbConnection := TDbConfig.CreateConnection;
  DbConnection.Connect;
  Dialect := TDbConfig.CreateDialect;
  if (TDbConfig.GetProvider = dpMySQL) and (DbConnection.Dialect = ddMariaDB) then
    Dialect := TMariaDBDialect.Create;

  // Get the underlying TFDConnection for raw SQL operations
  FConn := (DbConnection as TFireDACConnection).Connection;

  // Drop tables to ensure clean state
  WriteLn('🗑️  Dropping existing tables...');
  if TDbConfig.GetProvider = dpMySQL then
    FConn.ExecSQL('SET FOREIGN_KEY_CHECKS = 0');
  try
    // Order matters due to FKs - drop child tables first
    DropTableIfExists('order_items');
    DropTableIfExists('products');
    DropTableIfExists('users');
    DropTableIfExists('addresses');
    DropTableIfExists('mixed_keys');
    DropTableIfExists('users_with_profile');
    DropTableIfExists('user_profiles');
    DropTableIfExists('documents');
    DropTableIfExists('articles');
    DropTableIfExists('tasks');
    DropTableIfExists('sequenced_users');
    DropTableIfExists('converter_test');  // TypeConverter example
  finally
    if TDbConfig.GetProvider = dpMySQL then
      FConn.ExecSQL('SET FOREIGN_KEY_CHECKS = 1');
  end;

  // 1.5 Clear SQL Cache to avoid interference between tests
  TSQLCache.Instance.Clear;

  // 2. Initialize Context
  FContext := TDbContext.Create(DbConnection, Dialect);
  if DebugSql then
  begin
    FContext. OnLog :=
      procedure(SQL: string)
      begin
        WriteLn('  🔍 SQL: ' + SQL);
      end;
  end;

  // 3. Register Entities & Create Schema
  WriteLn('📦 Registering entities...');
  FContext.Entities<TAddress>;
  FContext.Entities<TUser>;
  FContext.Entities<TOrderItem>;
  FContext.Entities<TProduct>;
  FContext.Entities<TMixedKeyEntity>;
  FContext.Entities<TDocument>;
  FContext.Entities<TArticle>;
  FContext.Entities<TUserProfile>;
  FContext.Entities<TUserWithProfile>;
  FContext.Entities<TTask>;
  FContext.Entities<TSequencedUser>;
  FContext.Entities<TConverterTestEntity>;  // TypeConverter example

  WriteLn('🏗️  Creating schema...');
  FContext.EnsureCreated;
  WriteLn('✅ Setup complete!');
  WriteLn('');
end;

procedure TBaseTest.TearDown;
begin
  FContext.Free;
  // FConn.Free; OwnConnection default = true
end;

procedure TBaseTest.Log(const Msg: string);
begin
  WriteLn(Msg);
end;

procedure TBaseTest.LogSuccess(const Msg: string);
begin
  WriteLn('   ✅ ' + Msg);
end;

procedure TBaseTest.LogError(const Msg: string);
begin
  WriteLn('   ❌ ' + Msg);
end;

procedure TBaseTest.AssertTrue(Condition: Boolean; const SuccessMsg, FailMsg: string);
begin
  if Condition then
  begin
    LogSuccess(SuccessMsg);
    Inc(FTotalPassed);
  end
  else
  begin
    LogError(FailMsg);
    Inc(FTotalFailed);
    if FFailedTests.IndexOf(FCurrentTestName + ': ' + FailMsg) < 0 then
      FFailedTests.Add(FCurrentTestName + ': ' + FailMsg);
  end;
end;

procedure TBaseTest.AssertTrue(Condition: Boolean; const Msg: string);
begin
  AssertTrue(Condition, Msg, Msg);
end;

class constructor TBaseTest.Create;
begin
  FFailedTests := TCollections.CreateList<string>;
  FTotalPassed := 0;
  FTotalFailed := 0;
end;

class destructor TBaseTest.Destroy;
begin
end;

class procedure TBaseTest.ResetCounters;
begin
  FTotalPassed := 0;
  FTotalFailed := 0;
  FFailedTests.Clear;
end;

class procedure TBaseTest.PrintSummary;
var
  FailMsg: string;
begin
  WriteLn('');
  WriteLn(       '╔════════════════════════════════════════════════════════════════════════════════╗');
  WriteLn(       '║                    TEST SUMMARY                                                ║');
  WriteLn(       '╠════════════════════════════════════════════════════════════════════════════════╣');
  WriteLn(Format('║  ✅ Passed: %-5d                                                              ║', [FTotalPassed]));
  WriteLn(Format('║  ❌ Failed: %-5d                                                              ║', [FTotalFailed]));
  WriteLn(       '╠════════════════════════════════════════════════════════════════════════════════╣');

  if FTotalFailed > 0 then
  begin
    WriteLn(     '║  FAILED TESTS:                                                                 ║');
    for FailMsg in FFailedTests do
      WriteLn(Format('║  • %-76s║', [Copy(FailMsg, 1, 76)]));
  end
  else
    WriteLn(     '║  🎉 ALL TESTS PASSED!                                                          ║');

  WriteLn(       '╚════════════════════════════════════════════════════════════════════════════════╝');
end;

class procedure TBaseTest.ReportFailure(const Msg: string);
begin
  Inc(FTotalFailed);
  if FFailedTests.IndexOf(Msg) < 0 then
    FFailedTests.Add(Msg);
end;

end.

