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
  Dext.Collections,
  Dext.Collections.Dict,
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
  // Scenario 5: deletion timestamp configured only through the fluent API
  TGoneFluent = class
  private
    FId: Integer;
    FGoneAt: Nullable<TDateTime>;
  public
    [PK]
    property Id: Integer read FId write FId;
    property GoneAt: Nullable<TDateTime> read FGoneAt write FGoneAt;
  end;

  // Scenario 6: fluent flag plus fluent timestamp (hybrid)
  TGoneHybrid = class
  private
    FId: Integer;
    FRemoved: Boolean;
    FRemovedAt: Nullable<TDateTime>;
  public
    [PK]
    property Id: Integer read FId write FId;
    property Removed: Boolean read FRemoved write FRemoved;
    property RemovedAt: Nullable<TDateTime> read FRemovedAt write FRemovedAt;
  end;
  // Scenario 7: audit rows written by a SaveChanges interceptor
  TAuditRow = class
  private
    FId: Integer;
    FMember: string;
    FOldValue: string;
    FNewValue: string;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Member: string read FMember write FMember;
    property OldValue: string read FOldValue write FOldValue;
    property NewValue: string read FNewValue write FNewValue;
  end;
  {$M-}

  TAuditTestContext = class(TDbContext)
  public
    function Stamps: IDbSet<TStampFluent>;
    function Rows: IDbSet<TAuditRow>;
  end;

  // Writes one audit row per modified member of a TStampFluent, in SavingChanges
  TAuditWriter = class(TSaveChangesInterceptor)
  private
    FDb: TAuditTestContext;
  public
    Saving, Saved, Failed: Integer;
    SavedRows: Integer;
    ResaveInSaved: Boolean;
    constructor Create(ADb: TAuditTestContext);
    procedure SavingChanges(const Context: IDbContext); override;
    procedure SavedChanges(const Context: IDbContext; AffectedRows: Integer); override;
    procedure SaveChangesFailed(const Context: IDbContext; const Error: Exception); override;
  end;

  TSoftDeleteTestContext = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    function Stamps: IDbSet<TStampFluent>;
    function Gone: IDbSet<TGoneFluent>;
    function Hybrids: IDbSet<TGoneHybrid>;
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
    [Test]
    procedure Test_FluentDeletedAt_ShouldActAsSoftDelete;
    [Test]
    procedure Test_FluentFlagAndDeletedAt_ShouldSetBoth;
  end;

  [Fixture]
  [Category('ORM'), Category('Integration'), Category('Audit')]
  TAuditInterceptorTests = class
  private
    FConn: TFDConnection;
    FDb: TAuditTestContext;
    FWriter: TAuditWriter;
    procedure Prepare;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_OriginalValue_And_ModifiedMembers_ShowTheChange;
    [Test]
    procedure Test_Interceptor_Rows_AreWrittenInTheSameSave;
    [Test]
    procedure Test_FailedSave_ReportsFailureAndLeavesNoAuditRow;
    [Test]
    procedure Test_SaveChanges_InsideAnInterceptor_DoesNotRecurse;
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

{ TAuditTestContext }

function TAuditTestContext.Stamps: IDbSet<TStampFluent>;
begin
  Result := Entities<TStampFluent>;
end;

function TAuditTestContext.Rows: IDbSet<TAuditRow>;
begin
  Result := Entities<TAuditRow>;
end;

{ TAuditWriter }

constructor TAuditWriter.Create(ADb: TAuditTestContext);
begin
  inherited Create;
  FDb := ADb;
end;

procedure TAuditWriter.SavingChanges(const Context: IDbContext);
var
  Pair: TPair<TObject, TEntityState>;
  Changed: IList<TObject>;
  Entity: TObject;
  Member: string;
  Row: TAuditRow;
  Entry: IEntityEntry;
begin
  Inc(Saving);
  // Collect first: adding the audit rows changes the tracked set
  Changed := TCollections.CreateList<TObject>;
  for Pair in Context.ChangeTracker.GetTrackedEntities do
    if (Pair.Value = esModified) and (Pair.Key is TStampFluent) then
      Changed.Add(Pair.Key);

  for Entity in Changed do
  begin
    Entry := Context.Entry(Entity);
    for Member in Entry.ModifiedMembers do
    begin
      Row := TAuditRow.Create;
      Row.Member := Member;
      Row.OldValue := TValue(Entry.Member(Member).OriginalValue).ToString;
      Row.NewValue := TValue(Entry.Member(Member).CurrentValue).ToString;
      FDb.Rows.Add(Row);
    end;
  end;
end;

procedure TAuditWriter.SavedChanges(const Context: IDbContext; AffectedRows: Integer);
var
  Row: TAuditRow;
begin
  Inc(Saved);
  SavedRows := AffectedRows;
  if ResaveInSaved then
  begin
    Row := TAuditRow.Create;
    Row.Member := 'after-commit';
    FDb.Rows.Add(Row);
    FDb.SaveChanges;
  end;
end;

procedure TAuditWriter.SaveChangesFailed(const Context: IDbContext; const Error: Exception);
begin
  Inc(Failed);
end;

{ TAuditInterceptorTests }

procedure TAuditInterceptorTests.Setup;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE stamps_fluent (Id INTEGER PRIMARY KEY, Name TEXT, CreatedOn DATETIME, ChangedOn DATETIME)');
  FConn.ExecSQL('CREATE TABLE AuditRow (Id INTEGER PRIMARY KEY AUTOINCREMENT, Member TEXT, OldValue TEXT, NewValue TEXT)');

  FDb := TAuditTestContext.Create(TFireDACConnection.Create(FConn, False), TSQLiteDialect.Create);
  FWriter := TAuditWriter.Create(FDb);
  FDb.AddInterceptor(FWriter);
end;

procedure TAuditInterceptorTests.TearDown;
begin
  FreeAndNil(FDb);
  FreeAndNil(FConn);
end;

procedure TAuditInterceptorTests.Prepare;
var
  Item: TStampFluent;
begin
  Item := TStampFluent.Create;
  Item.Id := 601;
  Item.Name := 'a';
  FDb.Stamps.Add(Item);
  FDb.SaveChanges;
  FDb.Clear;
  FWriter.Saving := 0;
  FWriter.Saved := 0;
end;

procedure TAuditInterceptorTests.Test_OriginalValue_And_ModifiedMembers_ShowTheChange;
var
  Item: TStampFluent;
  Entry: IEntityEntry;
  Members: TArray<string>;
  Original, Current: TValue;
  Text: string;
begin
  Prepare;
  Item := FDb.Stamps.Find(601);
  Entry := FDb.Entry(Item);
  Dext.Assertions.Should(Entry.State = esUnchanged).BeTrue;
  Dext.Assertions.Should(Length(Entry.ModifiedMembers)).Be(0);

  Item.Name := 'b';

  Members := Entry.ModifiedMembers;
  Dext.Assertions.Should(Entry.State = esModified).BeTrue;
  Dext.Assertions.Should(Length(Members)).Be(1);
  Dext.Assertions.Should(Members[0]).Be('Name');
  Original := Entry.Member('Name').OriginalValue;
  Current := Entry.Member('Name').CurrentValue;
  Text := Original.ToString;
  Dext.Assertions.Should(Text).Be('a');
  Text := Current.ToString;
  Dext.Assertions.Should(Text).Be('b');

  // After the save the new value is the original
  FDb.SaveChanges;
  Original := Entry.Member('Name').OriginalValue;
  Text := Original.ToString;
  Dext.Assertions.Should(Text).Be('b');
end;

procedure TAuditInterceptorTests.Test_Interceptor_Rows_AreWrittenInTheSameSave;
var
  Item: TStampFluent;
begin
  Prepare;
  Item := FDb.Stamps.Find(601);
  Item.Name := 'b';

  FDb.SaveChanges;

  Dext.Assertions.Should(FWriter.Saving).Be(1);
  Dext.Assertions.Should(FWriter.Saved).Be(1);
  // The row of the change and the audit row, both counted
  Dext.Assertions.Should(FWriter.SavedRows).Be(2);
  Dext.Assertions.Should(Double(FConn.ExecSQLScalar(
    'SELECT COUNT(*) FROM AuditRow WHERE Member = ''Name'' AND OldValue = ''a'' AND NewValue = ''b'''))).Be(1);
end;

procedure TAuditInterceptorTests.Test_FailedSave_ReportsFailureAndLeavesNoAuditRow;
var
  Item: TStampFluent;
  Raised: Boolean;
begin
  Prepare;
  Item := FDb.Stamps.Find(601);
  Item.Name := 'b';
  // Another session removes the row: the UPDATE of the save finds nothing
  FConn.ExecSQL('DELETE FROM stamps_fluent');

  Raised := False;
  try
    FDb.SaveChanges;
  except
    Raised := True;
  end;

  Dext.Assertions.Should(Raised).BeTrue;
  Dext.Assertions.Should(FWriter.Failed).Be(1);
  Dext.Assertions.Should(FWriter.Saved).Be(0);
  Dext.Assertions.Should(Double(FConn.ExecSQLScalar('SELECT COUNT(*) FROM AuditRow'))).Be(0);
end;

procedure TAuditInterceptorTests.Test_SaveChanges_InsideAnInterceptor_DoesNotRecurse;
begin
  Prepare;
  FWriter.ResaveInSaved := True;
  FDb.Stamps.Find(601).Name := 'b';

  FDb.SaveChanges;

  // The nested SaveChanges wrote its row without running the interceptor again
  Dext.Assertions.Should(FWriter.Saving).Be(1);
  Dext.Assertions.Should(FWriter.Saved).Be(1);
  Dext.Assertions.Should(Double(FConn.ExecSQLScalar(
    'SELECT COUNT(*) FROM AuditRow WHERE Member = ''after-commit'''))).Be(1);
end;

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

  Builder.Entity<TGoneFluent>
    .Table('gone_fluent')
    .Prop('GoneAt').IsDeletedAt;

  Builder.Entity<TGoneHybrid>
    .Table('gone_hybrid')
    .HasSoftDelete('Removed')
    .Prop('RemovedAt').IsDeletedAt;
end;

function TSoftDeleteTestContext.Gone: IDbSet<TGoneFluent>;
begin
  Result := Entities<TGoneFluent>;
end;

function TSoftDeleteTestContext.Hybrids: IDbSet<TGoneHybrid>;
begin
  Result := Entities<TGoneHybrid>;
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
  FConn.ExecSQL('CREATE TABLE gone_fluent (Id INTEGER PRIMARY KEY, GoneAt DATETIME)');
  FConn.ExecSQL('CREATE TABLE gone_hybrid (Id INTEGER PRIMARY KEY, Removed BOOLEAN, RemovedAt DATETIME)');
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

procedure TSoftDeleteIntegrationTests.Test_FluentDeletedAt_ShouldActAsSoftDelete;
var
  Item: TGoneFluent;
begin
  Item := TGoneFluent.Create;
  Item.Id := 501;
  FContext.Gone.Add(Item);
  FContext.SaveChanges;
  FContext.Clear;

  FContext.Gone.Remove(FContext.Gone.Find(501));
  FContext.SaveChanges;
  FContext.Clear;

  // The row stays, with the date filled, and the query hides it
  Dext.Assertions.Should(Double(FConn.ExecSQLScalar(
    'SELECT COUNT(*) FROM gone_fluent WHERE GoneAt IS NOT NULL'))).Be(1);
  Dext.Assertions.Should(FContext.Gone.Find(501)).BeNil;
  Dext.Assertions.Should(FContext.Gone.OnlyDeleted.ToList.Count).Be(1);
end;

procedure TSoftDeleteIntegrationTests.Test_FluentFlagAndDeletedAt_ShouldSetBoth;
var
  Item: TGoneHybrid;
begin
  Item := TGoneHybrid.Create;
  Item.Id := 502;
  FContext.Hybrids.Add(Item);
  FContext.SaveChanges;
  FContext.Clear;

  FContext.Hybrids.Remove(FContext.Hybrids.Find(502));
  FContext.SaveChanges;
  FContext.Clear;

  Dext.Assertions.Should(Double(FConn.ExecSQLScalar(
    'SELECT COUNT(*) FROM gone_hybrid WHERE Removed = 1 AND RemovedAt IS NOT NULL'))).Be(1);
  Dext.Assertions.Should(FContext.Hybrids.ToList.Count).Be(0);
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
