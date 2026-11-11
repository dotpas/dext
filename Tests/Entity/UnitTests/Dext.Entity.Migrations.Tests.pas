unit Dext.Entity.Migrations.Tests;

interface

uses
  Dext.Collections,
  Dext.Testing,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  Dext.Entity.Migrations.Extractor,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLiteWrapper.Stat,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Migrations.Model,
  Dext.Entity.Migrations.Differ,
  Dext.Entity.Migrations.Operations,
  Dext.Core.SmartTypes,
  System.Variants,
  Dext.Entity.Migrations.Builder,
  Dext.Entity.Migrations.Runner,
  Dext.Entity.Migrations.Generator,
  Dext.Entity.Migrations.Serializers.Json,
  System.SysUtils;

type
  {$M+}
  [Table('Users'), RenamedFrom('LegacyUsers')]
  TRenamedUser = class
  private
    FId: Integer;
    FName: string;
    FMail: string;
  public
    [PK]
    property Id: Integer read FId write FId;
    [RenamedFrom('Full_Name')]
    property Name: string read FName write FName;
    property Mail: string read FMail write FMail;
  end;
  {$M-}

  TRenamedModelContext = class(TDbContext)
  public
    function Users: IDbSet<TRenamedUser>;
  end;

  {$M+}
  [Table('Typed')]
  TTypedColumns = class
  private
    FId: Integer;
    FCode: string;
    FTitle: StringType;
    FNote: string;
    FQty: IntType;
    FPrice: Currency;
    FPaid: Boolean;
  public
    [PK]
    property Id: Integer read FId write FId;
    [MaxLength(40)]
    property Code: string read FCode write FCode;
    [MaxLength(30)]
    property Title: StringType read FTitle write FTitle;
    property Note: string read FNote write FNote;
    property Qty: IntType read FQty write FQty;
    [Precision(12, 2)]
    property Price: Currency read FPrice write FPrice;
    property Paid: Boolean read FPaid write FPaid;
  end;
  {$M-}

  TTypedModelContext = class(TDbContext)
  public
    function Typed: IDbSet<TTypedColumns>;
  end;

  [TestFixture]
  TMigrationTests = class
  public
    [Test]
    procedure Test_Rename_Table_Detection;
    [Test]
    procedure Test_Rename_Column_Detection;
    [Test]
    procedure Test_Extractor_ReadsRenamedFromAttributes;
    [Test]
    procedure Test_Rename_Column_Emits_Only_The_Rename;
    [Test]
    procedure Test_Leftover_RenamedFrom_Emits_Nothing;
    [Test]
    procedure Test_Extractor_Uses_Bare_Varchar_With_The_Length;
    [Test]
    procedure Test_Extractor_Unwraps_Smart_Types;
    [Test]
    procedure Test_Extractor_Types_Columns_Like_EnsureCreated;
    [Test]
    procedure Test_Seed_Inserts_Every_Row;
    [Test]
    procedure Test_Builder_Seed_And_DeleteData_Operations;
    [Test]
    procedure Test_DeleteData_Removes_Exactly_The_Given_Rows;
    [Test]
    procedure Test_Json_RoundTrip_Seed_And_DeleteData;
    [Test]
    procedure Test_Generator_Seed_Up_Has_DeleteData_Down;
    [Test]
    procedure Test_Context_Exposes_The_Migrator;
    [Test]
    procedure Test_TableBuilder_ForeignKey_Becomes_An_Operation;
    [Test]
    procedure Test_Builder_Rename_Operations;
    [Test]
    procedure Test_Json_RoundTrip_Rename_Operations;
    [Test]
    procedure Test_Generator_Unit_Uses_Builder_And_Writes_Rename;
    [Test]
    procedure Test_Generator_Down_Reverses_The_Operations;
  end;

implementation

{ TRenamedModelContext }

function TRenamedModelContext.Users: IDbSet<TRenamedUser>;
begin
  Result := Entities<TRenamedUser>;
end;

{ TMigrationTests }

procedure TMigrationTests.Test_Extractor_ReadsRenamedFromAttributes;
var
  Db: TRenamedModelContext;
  Model: TSnapshotModel;
  Table: TSnapshotTable;
begin
  Db := TRenamedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.Users;
    Model := TDbContextModelExtractor.Extract(Db);
    try
      Table := Model.FindTable('Users');
      Should(Table <> nil).BeTrue;
      Should(Table.RenamedFrom).Be('LegacyUsers');
      Should(Table.FindColumn('Name').RenamedFrom).Be('Full_Name');
      Should(Table.FindColumn('Mail').RenamedFrom).Be('');
    finally
      Model.Free;
    end;
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_Rename_Table_Detection;
var
  OldModel, NewModel: TSnapshotModel;
  OldTable, NewTable: TSnapshotTable;
  Differ: TModelDiffer;
  Ops: IList<TMigrationOperation>;
  Found: Boolean;
  Op: TMigrationOperation;
begin
  OldModel := TSnapshotModel.Create;
  OldTable := TSnapshotTable.Create;
  OldTable.Name := 'OldUsers';
  OldModel.Tables.Add(OldTable);

  NewModel := TSnapshotModel.Create;
  NewTable := TSnapshotTable.Create;
  NewTable.Name := 'Users';
  NewTable.RenamedFrom := 'OldUsers'; // Simulate attribute
  NewModel.Tables.Add(NewTable);

  Differ := TModelDiffer.Create;
  try
    Ops := Differ.Diff(NewModel, OldModel);
    
    Found := False;
    for Op in Ops do
      if Op is TRenameTableOperation then
      begin
        Should(TRenameTableOperation(Op).OldName).Be('OldUsers');
        Should(TRenameTableOperation(Op).NewName).Be('Users');
        Found := True;
      end;
      
    Should(Found).BeTrue;
  finally
    Differ.Free;
    OldModel.Free;
    NewModel.Free;
  end;
end;

procedure TMigrationTests.Test_Rename_Column_Detection;
var
  OldModel, NewModel: TSnapshotModel;
  Table, NewTable: TSnapshotTable;
  OldCol, NewCol: TSnapshotColumn;
  Differ: TModelDiffer;
  Ops: IList<TMigrationOperation>;
  Found: Boolean;
  Op: TMigrationOperation;
begin
  OldModel := TSnapshotModel.Create;
  Table := TSnapshotTable.Create;
  Table.Name := 'Users';
  OldCol := TSnapshotColumn.Create;
  OldCol.Name := 'Full_Name';
  Table.Columns.Add(OldCol);
  OldModel.Tables.Add(Table);

  NewModel := TSnapshotModel.Create;
  NewTable := TSnapshotTable.Create;
  NewTable.Name := 'Users';
  NewCol := TSnapshotColumn.Create;
  NewCol.Name := 'Name';
  NewCol.RenamedFrom := 'Full_Name';
  NewTable.Columns.Add(NewCol);
  NewModel.Tables.Add(NewTable);

  Differ := TModelDiffer.Create;
  try
    Ops := Differ.Diff(NewModel, OldModel);
    
    Found := False;
    for Op in Ops do
      if Op is TRenameColumnOperation then
      begin
        Should(TRenameColumnOperation(Op).TableName).Be('Users');
        Should(TRenameColumnOperation(Op).OldName).Be('Full_Name');
        Should(TRenameColumnOperation(Op).NewName).Be('Name');
        Found := True;
      end;
      
    Should(Found).BeTrue;
  finally
    Differ.Free;
    OldModel.Free;
    NewModel.Free;
  end;
end;

procedure TMigrationTests.Test_Rename_Column_Emits_Only_The_Rename;
var
  OldModel, NewModel: TSnapshotModel;
  OldTable, NewTable: TSnapshotTable;
  OldCol, NewCol: TSnapshotColumn;
  Ops: IList<TMigrationOperation>;
begin
  OldModel := TSnapshotModel.Create;
  NewModel := TSnapshotModel.Create;
  try
    OldTable := TSnapshotTable.Create;
    OldTable.Name := 'Users';
    OldCol := TSnapshotColumn.Create;
    OldCol.Name := 'Full_Name';
    OldCol.ColumnType := 'VARCHAR';
    OldCol.Length := 40;
    OldTable.Columns.Add(OldCol);
    OldModel.Tables.Add(OldTable);

    NewTable := TSnapshotTable.Create;
    NewTable.Name := 'Users';
    NewCol := TSnapshotColumn.Create;
    NewCol.Name := 'Name';
    NewCol.ColumnType := 'VARCHAR';
    NewCol.Length := 40;
    NewCol.RenamedFrom := 'Full_Name';
    NewTable.Columns.Add(NewCol);
    NewModel.Tables.Add(NewTable);

    Ops := TModelDiffer.Diff(NewModel, OldModel);

    // A renamed column with the same definition is just a rename: no
    // AlterColumn on top of it.
    Should(Ops.Count).Be(1);
    Should(Ops[0] is TRenameColumnOperation).BeTrue;
  finally
    NewModel.Free;
    OldModel.Free;
  end;
end;

procedure TMigrationTests.Test_Leftover_RenamedFrom_Emits_Nothing;
var
  OldModel, NewModel: TSnapshotModel;
  OldTable, NewTable: TSnapshotTable;
  OldCol, NewCol: TSnapshotColumn;
  Ops: IList<TMigrationOperation>;
begin
  OldModel := TSnapshotModel.Create;
  NewModel := TSnapshotModel.Create;
  try
    OldTable := TSnapshotTable.Create;
    OldTable.Name := 'Users';
    OldCol := TSnapshotColumn.Create;
    OldCol.Name := 'Name';
    OldCol.ColumnType := 'VARCHAR';
    OldCol.Length := 40;
    OldCol.RenamedFrom := 'Full_Name';
    OldTable.Columns.Add(OldCol);
    OldModel.Tables.Add(OldTable);

    NewTable := TSnapshotTable.Create;
    NewTable.Name := 'Users';
    NewCol := TSnapshotColumn.Create;
    NewCol.Name := 'Name';
    NewCol.ColumnType := 'VARCHAR';
    NewCol.Length := 40;
    NewTable.Columns.Add(NewCol);
    NewModel.Tables.Add(NewTable);

    Ops := TModelDiffer.Diff(NewModel, OldModel);

    // RenamedFrom is a mapping hint, not part of the column definition:
    // dropping the attribute after the rename was applied changes nothing.
    Should(Ops.Count).Be(0);
  finally
    NewModel.Free;
    OldModel.Free;
  end;
end;

function TTypedModelContext.Typed: IDbSet<TTypedColumns>;
begin
  Result := Entities<TTypedColumns>;
end;

procedure TMigrationTests.Test_Extractor_Uses_Bare_Varchar_With_The_Length;
var
  Db: TTypedModelContext;
  Model: TSnapshotModel;
  Table: TSnapshotTable;
begin
  Db := TTypedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.Typed;
    Model := TDbContextModelExtractor.Extract(Db);
    try
      Table := Model.FindTable('Typed');
      // The size lives in Length: the DDL appends "(40)" itself, so a type
      // such as TEXT or VARCHAR(255) here would produce invalid SQL.
      Should(Table.FindColumn('Code').ColumnType).Be('VARCHAR');
      Should(Table.FindColumn('Code').Length).Be(40);
      // Without MaxLength the column keeps what EnsureCreated writes for it.
      Should(Table.FindColumn('Note').ColumnType).Be('VARCHAR(255)');
      Should(Table.FindColumn('Note').Length).Be(0);
    finally
      Model.Free;
    end;
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_Extractor_Unwraps_Smart_Types;
var
  Db: TTypedModelContext;
  Model: TSnapshotModel;
  Table: TSnapshotTable;
begin
  Db := TTypedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.Typed;
    Model := TDbContextModelExtractor.Extract(Db);
    try
      Table := Model.FindTable('Typed');
      // StringType and IntType are records around the value; the column is
      // the type of the value, as in EnsureCreated.
      Should(Table.FindColumn('Title').ColumnType).Be('VARCHAR');
      Should(Table.FindColumn('Title').Length).Be(30);
      Should(Table.FindColumn('Qty').ColumnType).Be('INTEGER');
    finally
      Model.Free;
    end;
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_Extractor_Types_Columns_Like_EnsureCreated;
var
  Db: TTypedModelContext;
  Model: TSnapshotModel;
  Table: TSnapshotTable;
  Reader: IDbReader;
  Declared: string;
begin
  Db := TTypedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.EnsureCreated;
    // What EnsureCreated wrote for the same columns.
    Reader := Db.Connection.CreateCommand(
      'SELECT type FROM pragma_table_info(''Typed'') WHERE name = ''Price''')
      .ExecuteQuery;
    Reader.Next;
    Declared := Reader.GetValue(0).ToString;
    Should(Declared).Be('DECIMAL(12,2)');

    Model := TDbContextModelExtractor.Extract(Db);
    try
      Table := Model.FindTable('Typed');
      // A Currency with Precision is a DECIMAL(12,2) for the migration as
      // well (the size lives in Precision/Scale), not a floating REAL.
      Should(Table.FindColumn('Price').ColumnType).Be('DECIMAL');
      Should(Table.FindColumn('Price').Precision).Be(12);
      Should(Table.FindColumn('Price').Scale).Be(2);
      Should(Table.FindColumn('Paid').ColumnType).Be('BOOLEAN');
    finally
      Model.Free;
    end;
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_Seed_Inserts_Every_Row;
var
  Db: TRenamedModelContext;
  Op: TSeedDataOperation;
  Reader: IDbReader;
  Total: string;
begin
  Db := TRenamedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.Connection.CreateCommand(
      'CREATE TABLE "Seeds" ("Id" INTEGER, "Name" TEXT)').ExecuteNonQuery;
    Op := TSeedDataOperation.Create('Seeds', ['Id', 'Name'],
      [[1, 'Ana'], [2, 'O''Neil'], [3, Null]]);
    try
      Db.Connection.CreateCommand(
        Db.Dialect.GenerateMigration(Op)).ExecuteNonQuery;
    finally
      Op.Free;
    end;

    Reader := Db.Connection.CreateCommand(
      'SELECT COUNT(*) FROM "Seeds"').ExecuteQuery;
    Reader.Next;
    Total := Reader.GetValue(0).ToString;
    Should(Total).Be('3');
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_Builder_Seed_And_DeleteData_Operations;
var
  Builder: TSchemaBuilder;
  Seed: TSeedDataOperation;
  Del: TDeleteDataOperation;
begin
  Builder := TSchemaBuilder.Create;
  try
    Builder
      .Seed('Users', ['Id', 'Name'], [[1, 'Ana'], [2, 'Bia']])
      .DeleteData('Users', ['Id', 'Name'], [[1, 'Ana']]);

    Should(Builder.Operations.Count).Be(2);
    Should(Builder.Operations[0] is TSeedDataOperation).BeTrue;
    Seed := TSeedDataOperation(Builder.Operations[0]);
    Should(Seed.TableName).Be('Users');
    Should(Length(Seed.Columns)).Be(2);
    Should(Length(Seed.Data)).Be(2);
    Should(VarToStr(Seed.Data[1][1])).Be('Bia');
    Should(Builder.Operations[1] is TDeleteDataOperation).BeTrue;
    Del := TDeleteDataOperation(Builder.Operations[1]);
    Should(Del.TableName).Be('Users');
    Should(Length(Del.Data)).Be(1);
  finally
    Builder.Free;
  end;
end;

procedure TMigrationTests.Test_DeleteData_Removes_Exactly_The_Given_Rows;
var
  Db: TRenamedModelContext;
  Op: TDeleteDataOperation;
  Reader: IDbReader;
  Total: string;
begin
  Db := TRenamedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.Connection.CreateCommand(
      'CREATE TABLE "Seeds" ("Id" INTEGER, "Name" TEXT)').ExecuteNonQuery;
    Db.Connection.CreateCommand(
      'INSERT INTO "Seeds" VALUES (1, ''Ana''), (2, ''O''''Neil''), ' +
      '(3, NULL), (4, ''Dani'')').ExecuteNonQuery;

    // A row is matched by every column it names; NULL needs IS NULL.
    Op := TDeleteDataOperation.Create('Seeds', ['Id', 'Name'],
      [[2, 'O''Neil'], [3, Null]]);
    try
      Db.Connection.CreateCommand(
        Db.Dialect.GenerateMigration(Op)).ExecuteNonQuery;
    finally
      Op.Free;
    end;

    Reader := Db.Connection.CreateCommand(
      'SELECT GROUP_CONCAT("Id") FROM "Seeds"').ExecuteQuery;
    Reader.Next;
    Total := Reader.GetValue(0).ToString;
    Should(Total).Be('1,4');
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_Json_RoundTrip_Seed_And_DeleteData;
var
  Ops, Back: IList<TMigrationOperation>;
  Seed: TSeedDataOperation;
begin
  Ops := TCollections.CreateList<TMigrationOperation>(True);
  Ops.Add(TSeedDataOperation.Create('Users', ['Id', 'Name', 'Active'],
    [[1, 'Ana', True], [2, Null, False]]));
  Ops.Add(TDeleteDataOperation.Create('Users', ['Id'], [[1], [2]]));

  Back := TMigrationJsonSerializer.Deserialize(
    TMigrationJsonSerializer.Serialize(Ops));

  Should(Back.Count).Be(2);
  Should(Back[0] is TSeedDataOperation).BeTrue;
  Seed := TSeedDataOperation(Back[0]);
  Should(Seed.TableName).Be('Users');
  Should(Seed.Columns[2]).Be('Active');
  Should(VarToStr(Seed.Data[0][0])).Be('1');
  Should(VarToStr(Seed.Data[0][1])).Be('Ana');
  Should(VarType(Seed.Data[0][2]) = varBoolean).BeTrue;
  Should(Boolean(Seed.Data[0][2])).BeTrue;
  Should(VarIsNull(Seed.Data[1][1])).BeTrue;
  Should(Back[1] is TDeleteDataOperation).BeTrue;
  Should(Length(TDeleteDataOperation(Back[1]).Data)).Be(2);
end;

procedure TMigrationTests.Test_Generator_Seed_Up_Has_DeleteData_Down;
var
  Ops: IList<TMigrationOperation>;
  Code, Down: string;
begin
  Ops := TCollections.CreateList<TMigrationOperation>(True);
  Ops.Add(TSeedDataOperation.Create('Users', ['Id', 'Name', 'Active'],
    [[1, 'O''Neil', True], [2, Null, False]]));

  Code := TMigrationGenerator.GenerateUnit('Migrations.Sample',
    'TMigration_20260101_Seed', Ops);
  Down := Code.Substring(Code.IndexOf('.Down(Builder'));

  Should(Code.Contains('Builder.Seed(''Users'', [''Id'', ''Name'', ''Active''], ' +
    '[[1, ''O''''Neil'', True], [2, Null, False]]);')).BeTrue;
  // The inverse of a seed deletes exactly the rows it inserted.
  Should(Down.Contains('Builder.DeleteData(''Users'', [''Id'', ''Name'', ''Active''], ' +
    '[[1, ''O''''Neil'', True], [2, Null, False]]);')).BeTrue;
end;

procedure TMigrationTests.Test_Context_Exposes_The_Migrator;
var
  Db: TRenamedModelContext;
begin
  Db := TRenamedModelContext.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    // One migrator per context, created on first use and owned by it.
    Should(Db.Migrator <> nil).BeTrue;
    Should(Db.Migrator = Db.Migrator).BeTrue;
    Should(Db.Migrator.GetAppliedMigrations.Count).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TMigrationTests.Test_TableBuilder_ForeignKey_Becomes_An_Operation;
var
  Builder: TSchemaBuilder;
  Fk: TAddForeignKeyOperation;
begin
  Builder := TSchemaBuilder.Create;
  try
    Builder.CreateTable('Orders',
      procedure(T: TTableBuilder)
      begin
        T.Column('Id', 'INTEGER').PrimaryKey;
        T.Column('UserId', 'INTEGER').NotNull;
        T.ForeignKey('FK_Orders_Users', 'UserId', 'Users', 'Id');
      end);

    // The foreign key was silently dropped: it must follow the CREATE TABLE
    // as its own operation.
    Should(Builder.Operations.Count).Be(2);
    Should(Builder.Operations[0] is TCreateTableOperation).BeTrue;
    Should(Builder.Operations[1] is TAddForeignKeyOperation).BeTrue;
    Fk := TAddForeignKeyOperation(Builder.Operations[1]);
    Should(Fk.Table).Be('Orders');
    Should(Fk.Name).Be('FK_Orders_Users');
    Should(Fk.Columns[0]).Be('UserId');
    Should(Fk.ReferencedTable).Be('Users');
    Should(Fk.ReferencedColumns[0]).Be('Id');
  finally
    Builder.Free;
  end;
end;

procedure TMigrationTests.Test_Builder_Rename_Operations;
var
  Builder: TSchemaBuilder;
begin
  Builder := TSchemaBuilder.Create;
  try
    Builder.RenameTable('OldUsers', 'Users').RenameColumn('Users', 'Full_Name', 'Name');

    Should(Builder.Operations.Count).Be(2);
    Should(Builder.Operations[0] is TRenameTableOperation).BeTrue;
    Should(TRenameTableOperation(Builder.Operations[0]).OldName).Be('OldUsers');
    Should(TRenameTableOperation(Builder.Operations[0]).NewName).Be('Users');
    Should(Builder.Operations[1] is TRenameColumnOperation).BeTrue;
    Should(TRenameColumnOperation(Builder.Operations[1]).TableName).Be('Users');
    Should(TRenameColumnOperation(Builder.Operations[1]).OldName).Be('Full_Name');
    Should(TRenameColumnOperation(Builder.Operations[1]).NewName).Be('Name');
  finally
    Builder.Free;
  end;
end;

procedure TMigrationTests.Test_Json_RoundTrip_Rename_Operations;
var
  Ops, Back: IList<TMigrationOperation>;
begin
  Ops := TCollections.CreateList<TMigrationOperation>(True);
  Ops.Add(TRenameTableOperation.Create('OldUsers', 'Users'));
  Ops.Add(TRenameColumnOperation.Create('Users', 'Full_Name', 'Name'));

  Back := TMigrationJsonSerializer.Deserialize(
    TMigrationJsonSerializer.Serialize(Ops));

  Should(Back.Count).Be(2);
  Should(TRenameTableOperation(Back[0]).OldName).Be('OldUsers');
  Should(TRenameTableOperation(Back[0]).NewName).Be('Users');
  Should(TRenameColumnOperation(Back[1]).TableName).Be('Users');
  Should(TRenameColumnOperation(Back[1]).OldName).Be('Full_Name');
  Should(TRenameColumnOperation(Back[1]).NewName).Be('Name');
end;

procedure TMigrationTests.Test_Generator_Unit_Uses_Builder_And_Writes_Rename;
var
  Ops: IList<TMigrationOperation>;
  Code: string;
begin
  Ops := TCollections.CreateList<TMigrationOperation>(True);
  Ops.Add(TRenameColumnOperation.Create('Users', 'Full_Name', 'Name'));

  Code := TMigrationGenerator.GenerateUnit('Migrations.Sample',
    'TMigration_20260101_Rename', Ops);

  // TSchemaBuilder lives in the Builder unit: without it in the uses clause
  // the generated unit does not compile.
  Should(Code.Contains('Dext.Entity.Migrations.Builder')).BeTrue;
  Should(Code.Contains(
    'Builder.RenameColumn(''Users'', ''Full_Name'', ''Name'');')).BeTrue;
  Should(Code.Contains('Unsupported')).BeFalse;
end;

procedure TMigrationTests.Test_Generator_Down_Reverses_The_Operations;
var
  Ops: IList<TMigrationOperation>;
  Code, Down: string;
  Col: TColumnDefinition;
  P1, P2: Integer;
begin
  Ops := TCollections.CreateList<TMigrationOperation>(True);
  Col := TColumnDefinition.Create('Email', 'VARCHAR');
  Col.Length := 120;
  Ops.Add(TAddColumnOperation.Create('Users', Col));
  Ops.Add(TRenameColumnOperation.Create('Users', 'Full_Name', 'Name'));
  Ops.Add(TCreateIndexOperation.Create('Users', 'ix_users_name', ['Name']));
  Ops.Add(TDropColumnOperation.Create('Users', 'Legacy'));

  Code := TMigrationGenerator.GenerateUnit('Migrations.Sample',
    'TMigration_20260101_Evolution', Ops);
  Down := Code.Substring(Code.IndexOf('.Down(Builder'));

  Should(Down.Contains('TODO: Implement Down')).BeFalse;
  // Reverse order: index first, then the rename back, then the column.
  P1 := Down.IndexOf('Builder.DropIndex(''Users'', ''ix_users_name'');');
  P2 := Down.IndexOf('Builder.RenameColumn(''Users'', ''Name'', ''Full_Name'');');
  Should(P1 >= 0).BeTrue;
  Should(P2 > P1).BeTrue;
  Should(Down.IndexOf('Builder.DropColumn(''Users'', ''Email'');') > P2).BeTrue;
  // What cannot be inverted without the old definition is flagged, not lost.
  Should(Down.Contains('Irreversible')).BeTrue;
  Should(Down.Contains('Legacy')).BeTrue;
end;

end.
