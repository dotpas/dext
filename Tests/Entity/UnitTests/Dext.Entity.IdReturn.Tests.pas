unit Dext.Entity.IdReturn.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Specifications.SQL.Generator,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Mocks,
  Dext.Mocks.Matching,
  Dext.Core.SmartTypes,
  Dext.Types.UUID,
  Dext.Interception,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.DbSet,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Dialects,
  Dext.Entity.Naming,
  Dext.Entity.Setup,
  Dext.Entity.Core;

type
  { --- Test Entities --- }

  [Table('int_table')]
  TIntEntity = class
  private
    FId: Integer;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
  end;

  [Table('int64_table')]
  TInt64Entity = class
  private
    FId: Int64;
  public
    [PK, AutoInc]
    property Id: Int64 read FId write FId;
  end;

  [Table('inttype_table')]
  TIntTypeEntity = class
  private
    FId: IntType;
  public
    [PK, AutoInc]
    property Id: IntType read FId write FId;
  end;

  [Table('guid_table')]
  TGuidEntity = class
  private
    FId: TGUID;
  public
    [PK, AutoInc]
    property Id: TGUID read FId write FId;
  end;

  [Table('propguid_table')]
  TPropGuidEntity = class
  private
    FId: Prop<TGUID>;
  public
    [PK, AutoInc]
    property Id: Prop<TGUID> read FId write FId;
  end;

  [Table('uuid_table')]
  TUUIDEntity = class
  private
    FId: TUUID;
  public
    [PK, AutoInc]
    property Id: TUUID read FId write FId;
  end;

  [Table('propuuid_table')]
  TPropUUIDEntity = class
  private
    FId: Prop<TUUID>;
  public
    [PK, AutoInc]
    property Id: Prop<TUUID> read FId write FId;
  end;

  [Table('string_table')]
  TStringEntity = class
  private
    FId: string;
  public
    [PK, AutoInc]
    property Id: string read FId write FId;
  end;

  { --- Test Fixture --- }

  [TestFixture('Entity ID Return/Assignment Tests')]
  TEntityIdReturnTests = class
  private
    procedure TestIdAssignment<T: class, constructor>(const AReturnValue: TValue; ACheck: TProc<T>);
  public
    [Test]
    procedure Test_Integer_Id_Return;
    
    [Test]
    procedure Test_Int64_Id_Return;
    
    [Test]
    procedure Test_IntType_Id_Return;
    
    [Test]
    procedure Test_TGUID_Id_Return;
    
    [Test]
    procedure Test_PropTGUID_Id_Return;
    
    [Test]
    procedure Test_TUUID_Id_Return;
    
    [Test]
    procedure Test_PropTUUID_Id_Return;

    [Test]
    procedure Test_String_Id_Return;

    [Test]
    procedure Test_Integer_Id_With_NamingStrategy;
  end;

  { --- Entity with no column to write: INSERT ... DEFAULT VALUES --- }

  [TestFixture('INSERT of an entity whose only column is the auto-increment key')]
  TInsertDefaultValuesTests = class
  private
    function InsertOf(const ADialect: ISQLDialect): string;
    function TemplateOf(const ADialect: ISQLDialect): string;
  public
    [Test]
    procedure Test_SQLite_Uses_Default_Values;

    [Test]
    procedure Test_PostgreSQL_Uses_Default_Values;

    [Test]
    procedure Test_SQLServer_Uses_Default_Values;

    [Test]
    procedure Test_Firebird_Uses_Default_Values;

    [Test]
    procedure Test_MySQL_Uses_Empty_Column_List;

    [Test]
    procedure Test_MariaDB_Uses_Empty_Column_List;

    [Test]
    procedure Test_Oracle_Uses_Default_Keyword;

    [Test]
    procedure Test_Array_Dml_Template_Follows_The_Single_Insert;

    [Test]
    procedure Test_SQLServer_Output_Goes_Before_Default_Values;

    [Test]
    procedure Test_SQLite_Inserts_Rows_And_Assigns_Ids;
  end;

implementation

{ TEntityIdReturnTests }

procedure TEntityIdReturnTests.TestIdAssignment<T>(const AReturnValue: TValue; ACheck: TProc<T>);
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Dialect: Mock<ISQLDialect>;
  Ctx: TDbContext;
  Entity: T;
  DbSet: IDbSet<T>;
begin
  // Setup Mock Command
  Cmd := Mock<IDbCommand>.Create;
  Cmd.Setup.Returns(AReturnValue).When.ExecuteScalar;
  
  // Setup Mock Dialect (Force RETURNING support to trigger ExecuteScalar in PersistAdd)
  Dialect := Mock<ISQLDialect>.Create;
  Dialect.Setup.Returns(True).When.SupportsInsertReturning;
  Dialect.Setup.Returns('RETURNING id').When.GetReturningSQL(Arg.Any<string>);
  Dialect.Setup.Returns(ddPostgreSQL).When.GetDialect;
  Dialect.Setup.Returns(':').When.GetParamPrefix;
  Dialect.Setup.Executes(procedure(Invocation: IInvocation) begin Invocation.Result := '"' + Invocation.Arguments[0].AsString + '"'; end).When.QuoteIdentifier(Arg.Any<string>);

  // Setup Mock Connection
  Conn := Mock<IDbConnection>.Create;
  Conn.Setup.Returns(Cmd.Instance).When.CreateCommand(Arg.Any<string>);
  
  Ctx := TDbContext.Create(Conn.Instance, Dialect.Instance);
  try
    DbSet := Ctx.Entities<T>;
    Entity := T.Create;
    
    DbSet.Add(Entity);
    Ctx.SaveChanges;
    
    if Assigned(ACheck) then
      ACheck(Entity);

    DbSet := nil; // CRITICAL: Release interface reference before Freeing Ctx
  finally
    Ctx.Free;
  end;
end;

procedure TEntityIdReturnTests.Test_Integer_Id_Return;
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Dialect: Mock<ISQLDialect>;
  Ctx: TDbContext;
  Entity: TIntEntity;
begin
  // Setup Mock Command
  Cmd := Mock<IDbCommand>.Create;
  Cmd.Setup.Returns(TValue.From<Integer>(123)).When.ExecuteScalar;
  
  // Setup Mock Dialect
  Dialect := Mock<ISQLDialect>.Create;
  Dialect.Setup.Returns(True).When.SupportsInsertReturning;
  Dialect.Setup.Returns('RETURNING id').When.GetReturningSQL(Arg.Any<string>);
  Dialect.Setup.Returns(ddPostgreSQL).When.GetDialect;
  Dialect.Setup.Returns(':').When.GetParamPrefix;
  Dialect.Setup.Executes(procedure(Invocation: IInvocation) begin Invocation.Result := '"' + Invocation.Arguments[0].AsString + '"'; end).When.QuoteIdentifier(Arg.Any<string>);

  // Setup Mock Connection
  Conn := Mock<IDbConnection>.Create;
  Conn.Setup.Returns(Cmd.Instance).When.CreateCommand(Arg.Any<string>);
  
  Ctx := TDbContext.Create(Conn.Instance, Dialect.Instance);
  try
    Entity := TIntEntity.Create;
    Ctx.Entities<TIntEntity>.Add(Entity);
    Ctx.SaveChanges;
    Should(Entity.Id).Be(123);
  finally
    Ctx.Free;
  end;
end;

procedure TEntityIdReturnTests.Test_Int64_Id_Return;
begin
  TestIdAssignment<TInt64Entity>(Int64(9223372036854775807), 
    procedure(E: TInt64Entity)
    begin
      Should(E.Id).Be(9223372036854775807);
    end);
end;

procedure TEntityIdReturnTests.Test_IntType_Id_Return;
begin
  TestIdAssignment<TIntTypeEntity>(456, 
    procedure(E: TIntTypeEntity)
    begin
      Should(Integer(E.Id)).Be(456);
    end);
end;

procedure TEntityIdReturnTests.Test_TGUID_Id_Return;
var
  G: TGUID;
begin
  G := TGuid.Create('{D6A5D5A1-949B-4B7C-9F8A-E7C1D1B1B1B1}');
  TestIdAssignment<TGuidEntity>(TValue.From<TGUID>(G), 
    procedure(E: TGuidEntity)
    begin
      Should(IsEqualGUID(E.Id, G)).BeTrue;
    end);
end;

procedure TEntityIdReturnTests.Test_PropTGUID_Id_Return;
var
  G: TGUID;
begin
  G := TGuid.Create('{A1A1A1A1-B2B2-C3C3-D4D4-E5E5E5E5E5E5}');
  TestIdAssignment<TPropGuidEntity>(TValue.From<TGUID>(G), 
    procedure(E: TPropGuidEntity)
    begin
      Should(IsEqualGUID(E.Id.Value, G)).BeTrue;
    end);
end;

procedure TEntityIdReturnTests.Test_TUUID_Id_Return;
var
  G: TGUID;
  U: TUUID;
begin
  G := TGuid.Create('{B2B2B2B2-C3C3-D4D4-E5E5-F6F6F6F6F6F6}');
  U := G;
  
  // Test passing TGUID (common from DB driver) to TUUID property
  TestIdAssignment<TUUIDEntity>(TValue.From<string>(G.ToString), 
    procedure(E: TUUIDEntity)
    begin
      Should(E.Id.ToString).BeEquivalentTo(U.ToString);
    end);
end;

procedure TEntityIdReturnTests.Test_PropTUUID_Id_Return;
var
  G: TGUID;
  U: TUUID;
begin
  G := TGuid.Create('{C3C3C3C3-D4D4-E5E5-F6F6-A1A1A1A1A1A1}');
  U := G;
  
  TestIdAssignment<TPropUUIDEntity>(TValue.From<string>(G.ToString), 
    procedure(E: TPropUUIDEntity)
    begin
      Should(E.Id.Value.ToString).BeEquivalentTo(U.ToString);
    end);
end;

procedure TEntityIdReturnTests.Test_String_Id_Return;
begin
  TestIdAssignment<TStringEntity>('some-uuid-string', 
    procedure(E: TStringEntity)
    begin
      Should(E.Id).Be('some-uuid-string');
    end);
end;

procedure TEntityIdReturnTests.Test_Integer_Id_With_NamingStrategy;
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Dialect: Mock<ISQLDialect>;
  Ctx: TDbContext;
  Entity: TIntEntity;
  CapturedColumn: string;
begin
  // Verifies that PersistAdd passes the naming-strategy-transformed column name
  // to GetReturningSQL â€” regression test for the a0ac0de naming strategy fix.
  CapturedColumn := '';

  Cmd := Mock<IDbCommand>.Create;
  Cmd.Setup.Returns(TValue.From<Integer>(42)).When.ExecuteScalar;

  Dialect := Mock<ISQLDialect>.Create;
  Dialect.Setup.Returns(True).When.SupportsInsertReturning;
  Dialect.Setup.Executes(
    procedure(Invocation: IInvocation)
    begin
      CapturedColumn := Invocation.Arguments[0].AsString;
      Invocation.Result := 'RETURNING ' + CapturedColumn;
    end).When.GetReturningSQL(Arg.Any<string>);
  Dialect.Setup.Returns(ddPostgreSQL).When.GetDialect;
  Dialect.Setup.Returns(':').When.GetParamPrefix;
  Dialect.Setup.Executes(
    procedure(Invocation: IInvocation)
    begin
      Invocation.Result := '"' + Invocation.Arguments[0].AsString + '"';
    end).When.QuoteIdentifier(Arg.Any<string>);

  Conn := Mock<IDbConnection>.Create;
  Conn.Setup.Returns(Cmd.Instance).When.CreateCommand(Arg.Any<string>);

  // Use snake_case naming strategy â€” 'Id' should become 'id'
  Ctx := TDbContext.Create(Conn.Instance, Dialect.Instance, TSnakeCaseNamingStrategy.Create);
  try
    Entity := TIntEntity.Create;
    Ctx.Entities<TIntEntity>.Add(Entity);
    Ctx.SaveChanges;

    // The column name passed to GetReturningSQL must be the renamed column, not the Delphi property name
    Should(CapturedColumn).Be('id');
    Should(Entity.Id).Be(42);
  finally
    Ctx.Free;
  end;
end;

{ TInsertDefaultValuesTests }

function TInsertDefaultValuesTests.InsertOf(const ADialect: ISQLDialect): string;
var
  Gen: TSqlGenerator<TIntEntity>;
  Entity: TIntEntity;
begin
  Gen := TSqlGenerator<TIntEntity>.Create(ADialect, nil);
  Entity := TIntEntity.Create;
  try
    Result := Gen.GenerateInsert(Entity);
  finally
    Entity.Free;
    Gen.Free;
  end;
end;

function TInsertDefaultValuesTests.TemplateOf(const ADialect: ISQLDialect): string;
var
  Gen: TSqlGenerator<TIntEntity>;
  Props: IList<TPair<TRttiProperty, string>>;
begin
  Gen := TSqlGenerator<TIntEntity>.Create(ADialect, nil);
  try
    Result := Gen.GenerateInsertTemplate(Props);
  finally
    Gen.Free;
  end;
end;

procedure TInsertDefaultValuesTests.Test_SQLite_Uses_Default_Values;
var
  Sql: string;
begin
  Sql := InsertOf(TSQLiteDialect.Create);
  Should(Sql).Contain('INSERT INTO');
  Should(Sql).Contain(' DEFAULT VALUES');
  Should(Pos('()', Sql)).Be(0);
end;

procedure TInsertDefaultValuesTests.Test_PostgreSQL_Uses_Default_Values;
var
  Sql: string;
begin
  Sql := InsertOf(TPostgreSQLDialect.Create);
  Should(Sql).Contain(' DEFAULT VALUES');
  Should(Pos('()', Sql)).Be(0);
end;

procedure TInsertDefaultValuesTests.Test_SQLServer_Uses_Default_Values;
var
  Sql: string;
begin
  Sql := InsertOf(TSQLServerDialect.Create);
  Should(Sql).Contain(' DEFAULT VALUES');
  Should(Pos('()', Sql)).Be(0);
end;

procedure TInsertDefaultValuesTests.Test_Firebird_Uses_Default_Values;
var
  Sql: string;
begin
  Sql := InsertOf(TFirebirdDialect.Create);
  Should(Sql).Contain(' DEFAULT VALUES');
  Should(Pos('()', Sql)).Be(0);
end;

procedure TInsertDefaultValuesTests.Test_MySQL_Uses_Empty_Column_List;
begin
  Should(InsertOf(TMySQLDialect.Create)).Contain(' () VALUES ()');
end;

procedure TInsertDefaultValuesTests.Test_MariaDB_Uses_Empty_Column_List;
begin
  Should(InsertOf(TMariaDBDialect.Create)).Contain(' () VALUES ()');
end;

procedure TInsertDefaultValuesTests.Test_Oracle_Uses_Default_Keyword;
var
  Sql: string;
begin
  Sql := InsertOf(TOracleDialect.Create);
  Should(Sql).Contain(' VALUES (DEFAULT)');
  Should(Pos('()', Sql)).Be(0);
end;

procedure TInsertDefaultValuesTests.Test_Array_Dml_Template_Follows_The_Single_Insert;
begin
  Should(TemplateOf(TSQLiteDialect.Create)).Contain(' DEFAULT VALUES');
  Should(TemplateOf(TMySQLDialect.Create)).Contain(' () VALUES ()');
  Should(TemplateOf(TOracleDialect.Create)).Contain(' VALUES (DEFAULT)');
end;

procedure TInsertDefaultValuesTests.Test_SQLServer_Output_Goes_Before_Default_Values;
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Ctx: TDbContext;
  Entity: TIntEntity;
  Captured: string;
begin
  Cmd := Mock<IDbCommand>.Create;
  Cmd.Setup.Returns(TValue.From<Integer>(7)).When.ExecuteScalar;

  Captured := '';
  Conn := Mock<IDbConnection>.Create;
  Conn.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Inv.Arguments[0].AsString.StartsWith('INSERT') then
        Captured := Inv.Arguments[0].AsString;
      Inv.Result := TValue.From<IDbCommand>(Cmd.Instance);
    end).When.CreateCommand(Arg.Any<string>);

  Ctx := TDbContext.Create(Conn.Instance, TSQLServerDialect.Create);
  try
    Entity := TIntEntity.Create;
    Ctx.Entities<TIntEntity>.Add(Entity);
    Ctx.SaveChanges;

    // INSERT INTO [t] OUTPUT INSERTED.[Id] DEFAULT VALUES
    Should(Captured).Contain('OUTPUT');
    Should(Captured).Contain('DEFAULT VALUES');
    Should(Pos('OUTPUT', Captured) < Pos('DEFAULT VALUES', Captured)).BeTrue;
    Should(Entity.Id).Be(7);
  finally
    Ctx.Free;
  end;
end;

procedure TInsertDefaultValuesTests.Test_SQLite_Inserts_Rows_And_Assigns_Ids;
var
  Options: TDbContextOptions;
  Ctx: TDbContext;
  A, B: TIntEntity;
begin
  Options := TDbContextOptions.Create;
  try
    Options.UseSQLite(':memory:');
    Ctx := TDbContext.Create(Options, nil);
    try
      Ctx.ModelBuilder.Entity<TIntEntity>();
      Ctx.EnsureCreated;

      A := TIntEntity.Create;
      B := TIntEntity.Create;
      Ctx.Entities<TIntEntity>.Add(A);
      Ctx.Entities<TIntEntity>.Add(B);
      Ctx.SaveChanges;

      Should(A.Id).Be(1);
      Should(B.Id).Be(2);
    finally
      Ctx.Free;
    end;
  finally
    Options.Free;
  end;
end;

end.
