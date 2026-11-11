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

end.
