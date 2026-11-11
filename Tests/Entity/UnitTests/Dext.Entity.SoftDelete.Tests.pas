unit Dext.Entity.SoftDelete.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.Variants,
  Dext.Assertions, 
  Dext.Testing,
  Dext.Testing.Attributes,
  Dext.Entity,
  Dext.Entity.Mapping,
  Dext.Entity.Attributes,
  Dext.Specifications.SQL.Generator,
  Dext.Entity.Dialects,
  Dext.Entity.Context,
  Dext.Entity.Setup,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLiteWrapper.Stat,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Core,
  Dext.Types.Nullable,
  Dext.Mocks;

type
  {$M+}
  // Scenario 1: Classic Boolean Soft Delete
  [Table('tasks_bool'), SoftDelete('IsDeleted')]
  TTaskBool = class
  private
    FId: Integer;
    FIsDeleted: Boolean;
  public
    [PK]
    property Id: Integer read FId write FId;
    property IsDeleted: Boolean read FIsDeleted write FIsDeleted;
  end;

  // Scenario 2: Timestamp-based Soft Delete (DeletedAt)
  [Table('tasks_ts')]
  TTaskTimestamp = class
  private
    FId: Integer;
    FDeletedAt: Nullable<TDateTime>;
  public
    [PK] property Id: Integer read FId write FId;
    [DeletedAt]
    property DeletedAt: Nullable<TDateTime> read FDeletedAt write FDeletedAt;
  end;

  // Scenario 3: Hybrid Mode (Boolean + Timestamp)
  [Table('tasks_hybrid'), SoftDelete('IsDeleted')]
  TTaskHybrid = class
  private
    FId: Integer;
    FIsDeleted: Boolean;
    FDeletedAt: Nullable<TDateTime>;
  public
    [PK]
    property Id: Integer read FId write FId;
    property IsDeleted: Boolean read FIsDeleted write FIsDeleted;
    [DeletedAt]
    property DeletedAt: Nullable<TDateTime> read FDeletedAt write FDeletedAt;
  end;
  // Scenario 4: stamps and required name configured only through the fluent API
  [Table('stamps_fluent')]
  TStampFluent = class
  private
    FId: Integer;
    FName: string;
    FCreatedOn: TDateTime;
    FChangedOn: TDateTime;
  public
    [PK]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property CreatedOn: TDateTime read FCreatedOn write FCreatedOn;
    property ChangedOn: TDateTime read FChangedOn write FChangedOn;
  end;
  {$M-}

  TSoftDeleteTestContext = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    function Stamps: IDbSet<TStampFluent>;
    function TasksBool: IDbSet<TTaskBool>;
    function TasksTimestamp: IDbSet<TTaskTimestamp>;
    function TasksHybrid: IDbSet<TTaskHybrid>;
  end;

  [Fixture]
  [Category('ORM'), Category('Integration'), Category('SoftDelete')]
  TSoftDeleteIntegrationTests = class
  private
    FConn: TFDConnection;
    FContext: TSoftDeleteTestContext;
    procedure SetupDatabase;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_FullCycle_Boolean_ShouldUpdateFlagAndHide;
    [Test]
    procedure Test_FullCycle_Timestamp_ShouldUpdateDateAndHide;
    [Test]
    procedure Test_FullCycle_Hybrid_ShouldUpdateBothAndHide;
    [Test]
    procedure Test_FluentTimestamps_ShouldBeStampedOnInsertAndUpdate;
    [Test]
    procedure Test_HardDelete_ThenSaveChanges_ShouldNotRevalidateDeletedEntity;
  end;

  [Fixture]
  [Category('ORM'), Category('Unit'), Category('SoftDelete')]
  TSoftDeleteUnitTests = class
  public
    [Test]
    procedure Test_SQLFilter_Boolean_ShouldUseEquality;

    [Test]
    procedure Test_SQLFilter_Timestamp_ShouldUseIsNull;

    [Test]
    procedure Test_SQLFilter_Hybrid_ShouldPrioritizeBoolean;

    [Test]
    procedure Test_Mapping_DeletedAt_ShouldEnableSoftDeleteAutomatically;

    [Test]
    procedure Test_CreateTable_BooleanSoftDelete_UsesTheDialectLiteral;
  end;

implementation

{ TSoftDeleteIntegrationTests }

procedure TSoftDeleteIntegrationTests.Setup;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  
  SetupDatabase;

  FContext := TSoftDeleteTestContext.Create(TFireDACConnection.Create(FConn, False), TSQLiteDialect.Create);
//  FContext.OnLog := procedure(SQL: string)
//    begin
//      WriteLn('[SQL LOG] ', SQL);
//    end;
end;

procedure TSoftDeleteIntegrationTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

{ TSoftDeleteTestContext }

procedure TSoftDeleteTestContext.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TStampFluent>
    .Prop('Name').IsRequired
    .Prop('CreatedOn').IsCreatedAt
    .Prop('ChangedOn').IsUpdatedAt;
end;

function TSoftDeleteTestContext.Stamps: IDbSet<TStampFluent>;
begin
  Result := Entities<TStampFluent>;
end;

function TSoftDeleteTestContext.TasksBool: IDbSet<TTaskBool>;
begin
  Result := Entities<TTaskBool>;
end;

function TSoftDeleteTestContext.TasksHybrid: IDbSet<TTaskHybrid>;
begin
  Result := Entities<TTaskHybrid>;
end;

function TSoftDeleteTestContext.TasksTimestamp: IDbSet<TTaskTimestamp>;
begin
  Result := Entities<TTaskTimestamp>;
end;

procedure TSoftDeleteIntegrationTests.SetupDatabase;
begin
  FConn.ExecSQL('CREATE TABLE tasks_bool (Id INTEGER PRIMARY KEY, IsDeleted BOOLEAN)');
  FConn.ExecSQL('CREATE TABLE tasks_ts (Id INTEGER PRIMARY KEY, DeletedAt DATETIME)');
  FConn.ExecSQL('CREATE TABLE tasks_hybrid (Id INTEGER PRIMARY KEY, IsDeleted BOOLEAN, DeletedAt DATETIME)');
  FConn.ExecSQL('CREATE TABLE stamps_fluent (Id INTEGER PRIMARY KEY, Name TEXT, CreatedOn DATETIME, ChangedOn DATETIME)');
end;

procedure TSoftDeleteIntegrationTests.Test_FluentTimestamps_ShouldBeStampedOnInsertAndUpdate;
var
  Item: TStampFluent;
begin
  Item := TStampFluent.Create;
  Item.Id := 401;
  Item.Name := 'a';
  FContext.Stamps.Add(Item);
  FContext.SaveChanges;

  // Both stamps are filled on insert (an update stamp starts at creation)
  FContext.Clear;
  Item := FContext.Stamps.Find(401);
  Dext.Assertions.Should(Item.CreatedOn > EncodeDate(2020, 1, 1)).BeTrue;
  Dext.Assertions.Should(Item.ChangedOn > EncodeDate(2020, 1, 1)).BeTrue;

  // The update stamp overrides whatever the code assigned
  Item.ChangedOn := EncodeDate(2000, 1, 1);
  Item.Name := 'b';
  FContext.SaveChanges;
  FContext.Clear;
  Item := FContext.Stamps.Find(401);
  Dext.Assertions.Should(Item.ChangedOn > EncodeDate(2020, 1, 1)).BeTrue;
end;

procedure TSoftDeleteIntegrationTests.Test_HardDelete_ThenSaveChanges_ShouldNotRevalidateDeletedEntity;
var
  Item: TStampFluent;
begin
  Item := TStampFluent.Create;
  Item.Id := 402;
  Item.Name := 'x';
  FContext.Stamps.Add(Item);
  FContext.SaveChanges;
  FContext.Clear;

  FContext.Stamps.HardDelete(FContext.Stamps.Find(402));
  FContext.SaveChanges;

  Dext.Assertions.Should(Double(FConn.ExecSQLScalar(
    'SELECT COUNT(*) FROM stamps_fluent'))).Be(0);
end;

procedure TSoftDeleteIntegrationTests.Test_FullCycle_Boolean_ShouldUpdateFlagAndHide;
var
  Task: TTaskBool;
  Id: Integer;
begin
  // 1. Insert
  Task := TTaskBool.Create;
  Task.Id := 101;
  Task.IsDeleted := False;
  FContext.TasksBool.Add(Task);
  FContext.SaveChanges;
  FContext.Clear;

  // 2. Verify exists
  Task := FContext.TasksBool.Find(101);
  Dext.Assertions.Should(Task).NotBeNil;
  
  // 3. Remove (Soft Delete)
  FContext.TasksBool.Remove(Task);
  FContext.SaveChanges;
  FContext.Clear;

  // 4. Verify hidden from ORM
  Task := FContext.TasksBool.Find(101);
  Dext.Assertions.Should(Task).BeNil;

  // 5. Verify still exists in DB via raw SQL
  Id := FConn.ExecSQLScalar('SELECT Id FROM tasks_bool WHERE Id = 101 AND IsDeleted = 1');
  Dext.Assertions.Should(Id).Be(101);
end;

procedure TSoftDeleteIntegrationTests.Test_FullCycle_Timestamp_ShouldUpdateDateAndHide;
var
  Task: TTaskTimestamp;
  Count: Integer;
begin
  // 1. Insert
  Task := TTaskTimestamp.Create;
  Task.Id := 201;
  FContext.TasksTimestamp.Add(Task);
  FContext.SaveChanges;
  FContext.Clear;

  // 2. Soft Delete
  Task := FContext.TasksTimestamp.Find(201);
  Dext.Assertions.Should(Task).NotBeNil;
  FContext.TasksTimestamp.Remove(Task);
  FContext.SaveChanges;
  FContext.Clear;

  // 3. Verify hidden
  Task := FContext.TasksTimestamp.Find(201);
  Dext.Assertions.Should(Task).BeNil;

  // 4. Verify DB has timestamp
  Count := FConn.ExecSQLScalar('SELECT COUNT(*) FROM tasks_ts WHERE Id = 201 AND DeletedAt IS NOT NULL');
  Dext.Assertions.Should(Count).Be(1);
end;

procedure TSoftDeleteIntegrationTests.Test_FullCycle_Hybrid_ShouldUpdateBothAndHide;
var
  Task: TTaskHybrid;
  Exists: Boolean;
begin
  // 1. Insert
  Task := TTaskHybrid.Create;
  Task.Id := 301;
  Task.IsDeleted := False;
  FContext.TasksHybrid.Add(Task);
  FContext.SaveChanges;
  FContext.Clear;

  // 2. Soft Delete
  Task := FContext.TasksHybrid.Find(301);
  FContext.TasksHybrid.Remove(Task);
  FContext.SaveChanges;
  FContext.Clear;

  // 3. Verify DB has both flag and timestamp
  Exists := FConn.ExecSQLScalar('SELECT COUNT(*) FROM tasks_hybrid WHERE Id = 301 AND IsDeleted = 1 AND DeletedAt IS NOT NULL') > 0;
  Dext.Assertions.Should(Exists).BeTrue;
end;

type
  TSqlGeneratorCracker<T: class> = class(TSqlGenerator<T>);

{ TSoftDeleteUnitTests }

procedure TSoftDeleteUnitTests.Test_Mapping_DeletedAt_ShouldEnableSoftDeleteAutomatically;
var
  Map: TEntityMap;
begin
  Map := TModelBuilder.Instance.GetMap(TypeInfo(TTaskTimestamp));
  Dext.Assertions.Should(Map.IsSoftDelete).BeTrue;
  Dext.Assertions.Should(Map.SoftDeleteProp).Be('DeletedAt');
end;

procedure TSoftDeleteUnitTests.Test_CreateTable_BooleanSoftDelete_UsesTheDialectLiteral;
var
  Gen: TSqlGenerator<TTaskBool>;
  Sql: string;
begin
  // PostgreSQL has a real BOOLEAN: DEFAULT 0 is rejected by the server
  Gen := TSqlGenerator<TTaskBool>.Create(TPostgreSQLDialect.Create, nil);
  try
    Sql := Gen.GenerateCreateTable('tasks_bool');
    Dext.Assertions.Should(Sql).Contain('DEFAULT FALSE');
    Dext.Assertions.Should(Sql).NotContain('DEFAULT 0');
  finally
    Gen.Free;
  end;

  Gen := TSqlGenerator<TTaskBool>.Create(TSQLiteDialect.Create, nil);
  try
    Dext.Assertions.Should(Gen.GenerateCreateTable('tasks_bool')).Contain('DEFAULT 0');
  finally
    Gen.Free;
  end;
end;

procedure TSoftDeleteUnitTests.Test_SQLFilter_Boolean_ShouldUseEquality;
var
  Gen: TSqlGenerator<TTaskBool>;
begin
  Gen := TSqlGenerator<TTaskBool>.Create(TSQLServerDialect.Create, nil);
  try
    Dext.Assertions.Should(TSqlGeneratorCracker<TTaskBool>(Gen).GetSoftDeleteFilter).Contain('= 0');
    Dext.Assertions.Should(TSqlGeneratorCracker<TTaskBool>(Gen).GetSoftDeleteFilter).Contain('[IsDeleted]');
  finally
    Gen.Free;
  end;
end;

procedure TSoftDeleteUnitTests.Test_SQLFilter_Hybrid_ShouldPrioritizeBoolean;
var
  Gen: TSqlGenerator<TTaskHybrid>;
begin
  Gen := TSqlGenerator<TTaskHybrid>.Create(TSQLServerDialect.Create, nil);
  try
    Dext.Assertions.Should(TSqlGeneratorCracker<TTaskHybrid>(Gen).GetSoftDeleteFilter).Contain('= 0');
    Dext.Assertions.Should(TSqlGeneratorCracker<TTaskHybrid>(Gen).GetSoftDeleteFilter).NotContain('IS NULL');
  finally
    Gen.Free;
  end;
end;

procedure TSoftDeleteUnitTests.Test_SQLFilter_Timestamp_ShouldUseIsNull;
var
  Gen: TSqlGenerator<TTaskTimestamp>;
begin
  Gen := TSqlGenerator<TTaskTimestamp>.Create(TSQLServerDialect.Create, nil);
  try
    Dext.Assertions.Should(TSqlGeneratorCracker<TTaskTimestamp>(Gen).GetSoftDeleteFilter).Contain('[DeletedAt] IS NULL');
  finally
    Gen.Free;
  end;
end;

end.
