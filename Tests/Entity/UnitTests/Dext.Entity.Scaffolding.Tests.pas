unit Dext.Entity.Scaffolding.Tests;

interface

{$I Dext.inc}

uses
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Scaffolding,
  Dext.Scaffolding.Models,
  Dext.Entity.TemplatedScaffolding,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Dext.Collections;

type
  [TestFixture]
  TScaffoldingTests = class
  private
    FConn: TFDConnection;
    FDbConn: IDbConnection;
    FSchema: ISchemaProvider;
    FDatabasePath: string;
    procedure SetupSQLite;
    procedure TeardownSQLite;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_JoinTable_Detection;
    
    [Test]
    procedure Test_ManyToMany_Property_Generation;

    [Test]
    procedure Test_SQLite_Reports_NotNull_And_AutoInc;

    [Test]
    procedure Test_Generated_Entity_Has_Required_And_AutoInc;

    [Test]
    procedure Test_Nullable_Decimal_Keeps_Precision_Attribute;
  end;

implementation

{ TScaffoldingTests }

procedure TScaffoldingTests.SetupSQLite;
begin
  FDatabasePath := TPath.Combine(TPath.GetTempPath, 'test_scaffold_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.db');
  // No need to delete, it's a new unique name

  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=' + FDatabasePath);
  FConn.LoginPrompt := False;
  FConn.Connected := True;

  // Create Schema: Users <-> UserRoles <-> Roles
  FConn.ExecSQL('CREATE TABLE Users (Id INTEGER PRIMARY KEY AUTOINCREMENT, Name TEXT)');
  FConn.ExecSQL('CREATE TABLE Roles (Id INTEGER PRIMARY KEY AUTOINCREMENT, Name TEXT)');
  FConn.ExecSQL('CREATE TABLE UserRoles (' +
    'UserId INTEGER, ' +
    'RoleId INTEGER, ' +
    'PRIMARY KEY (UserId, RoleId), ' +
    'FOREIGN KEY (UserId) REFERENCES Users(Id), ' +
    'FOREIGN KEY (RoleId) REFERENCES Roles(Id))');

  // Wrap connection and provider
  FDbConn := TFireDACConnection.Create(FConn, False);
  FSchema := TFireDACSchemaProvider.Create(FDbConn);
end;

procedure TScaffoldingTests.TeardownSQLite;
begin
  FSchema := nil;
  FDbConn := nil;
  FConn.Connected := False;
  FConn.Free;
  if TFile.Exists(FDatabasePath) then TFile.Delete(FDatabasePath);
end;

procedure TScaffoldingTests.Setup;
begin
  SetupSQLite;
end;

procedure TScaffoldingTests.TearDown;
begin
  TeardownSQLite;
end;

procedure TScaffoldingTests.Test_JoinTable_Detection;
var
  Tables: TArray<string>;
  Meta: TMetaTable;
begin
  Tables := FSchema.GetTables;
  Should(Length(Tables)).BeGreaterThan(0);
  
  Meta := FSchema.GetTableMetadata('UserRoles');
  Should(Length(Meta.Columns)).Be(2);
  Should(Length(Meta.ForeignKeys)).Be(2);
  Should(Meta.Columns[0].IsPrimaryKey).BeTrue;
  Should(Meta.Columns[1].IsPrimaryKey).BeTrue;

  end;

procedure TScaffoldingTests.Test_ManyToMany_Property_Generation;
var
  Generator: TTemplatedEntityGenerator;
  OutputDir: string;
  UserFile, RoleFile, UserRoleFile: string;
  Content: string;
  LTemplatePath: string;
begin
  Generator := TTemplatedEntityGenerator.Create;
  OutputDir := TPath.Combine(TPath.GetTempPath, 'dext_scaffold_test_out_' + TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(OutputDir);
  try
    // Run generation
    LTemplatePath := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)), '..\..\Templates\Basic\entity.pas.template'));
    Generator.Generate(FSchema, LTemplatePath, OutputDir);

    UserFile := TPath.Combine(OutputDir, 'Users.pas');
    RoleFile := TPath.Combine(OutputDir, 'Roles.pas');
    UserRoleFile := TPath.Combine(OutputDir, 'UserRoles.pas');

    // Assert files exist for main tables
    Should(TFile.Exists(UserFile)).Because('Users.pas should be generated').BeTrue;
    Should(TFile.Exists(RoleFile)).Because('Roles.pas should be generated').BeTrue;
    
    // Assert UserRole (join table) was SKIPPED
    Should(TFile.Exists(UserRoleFile)).Because('UserRole.pas (join table) should NOT be generated').BeFalse;

    // Verify User.pas content
    Content := TFile.ReadAllText(UserFile);
    Should(Content).Contain('property Roles: IList<TRole>');
    Should(Content).Contain('[ManyToMany(''UserRoles'', ''UserId'', ''RoleId'')]');
    Should(Content).Contain('FRoles := TCollections.CreateList<TRole>(False);');

    // Verify Role.pas content (Bidirectional)
    Content := TFile.ReadAllText(RoleFile);
    Should(Content).Contain('property Users: IList<TUser>');
    Should(Content).Contain('[ManyToMany(''UserRoles'', ''RoleId'', ''UserId'')]');
  finally
    Generator.Free;
    if TDirectory.Exists(OutputDir) then
      TDirectory.Delete(OutputDir, True);
  end;
end;

procedure TScaffoldingTests.Test_SQLite_Reports_NotNull_And_AutoInc;
var
  Meta: TMetaTable;
  Col: TMetaColumn;
begin
  FConn.ExecSQL('CREATE TABLE ScItens (Id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'Nome TEXT NOT NULL, Nota TEXT)');
  FConn.ExecSQL('CREATE TABLE ScChave (A INTEGER, B INTEGER, PRIMARY KEY (A, B))');
  FConn.ExecSQL('CREATE TABLE ScCodigo (Cod TEXT PRIMARY KEY, N INTEGER)');
  // The provider caches the schema on first use: use a fresh one.
  FSchema := TFireDACSchemaProvider.Create(FDbConn);

  Meta := FSchema.GetTableMetadata('ScItens');
  Col := Meta.Columns[0];
  Should(Col.Name).Be('Id');
  Should(Col.IsPrimaryKey).BeTrue;
  Should(Col.IsAutoInc).Because('INTEGER PRIMARY KEY is the SQLite rowid alias').BeTrue;
  Should(Col.IsNullable).Because('a primary key is never null').BeFalse;
  Should(Meta.Columns[1].IsNullable).Because('Nome is NOT NULL').BeFalse;
  Should(Meta.Columns[2].IsNullable).Because('Nota has no NOT NULL').BeTrue;

  // A composite key is not a rowid alias.
  Meta := FSchema.GetTableMetadata('ScChave');
  Should(Meta.Columns[0].IsAutoInc).BeFalse;
  Should(Meta.Columns[1].IsAutoInc).BeFalse;

  // A text key is not generated by the database.
  Meta := FSchema.GetTableMetadata('ScCodigo');
  Should(Meta.Columns[0].IsPrimaryKey).BeTrue;
  Should(Meta.Columns[0].IsAutoInc).BeFalse;
end;

procedure TScaffoldingTests.Test_Generated_Entity_Has_Required_And_AutoInc;
var
  Generator: TDelphiEntityGenerator;
  Metas: TArray<TMetaTable>;
  Code: string;
begin
  FConn.ExecSQL('CREATE TABLE ScItens (Id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'Nome TEXT NOT NULL, Nota TEXT)');
  FSchema := TFireDACSchemaProvider.Create(FDbConn);
  Metas := [FSchema.GetTableMetadata('ScItens')];

  Generator := TDelphiEntityGenerator.Create;
  try
    Code := Generator.GenerateUnit('Gerado', Metas, msAttributes, psPOCO, False);
  finally
    Generator.Free;
  end;

  Should(Code).Contain('[PK, AutoInc, Required]');
  Should(Code).Contain('property Id: Integer read FId write FId;');
  Should(Code).Contain('[Required]' + sLineBreak + '    property Nome: string');
  Should(Code).Contain('    property Nota: string');
  Should(Code).NotContain('[Required]' + sLineBreak + '    property Nota');
end;

procedure TScaffoldingTests.Test_Nullable_Decimal_Keeps_Precision_Attribute;
var
  Generator: TDelphiEntityGenerator;
  Metas: TArray<TMetaTable>;
  Code: string;
begin
  FConn.ExecSQL('CREATE TABLE ScPrecos (Id INTEGER PRIMARY KEY, ' +
    'Obrigatorio NUMERIC(10,2) NOT NULL, Opcional NUMERIC(12,3))');
  FSchema := TFireDACSchemaProvider.Create(FDbConn);
  Metas := [FSchema.GetTableMetadata('ScPrecos')];

  Generator := TDelphiEntityGenerator.Create;
  try
    Code := Generator.GenerateUnit('Gerado', Metas, msAttributes, psPOCO, False);
    Should(Code).Contain('Precision(10, 2)');
    // The column that accepts NULL is wrapped in Nullable<>; its precision
    // must not be lost on the way.
    Should(Code).Contain('Precision(12, 3)');

    Code := Generator.GenerateUnit('Gerado', Metas, msAttributes, psSmart, False);
    Should(Code).Contain('Precision(10, 2)');
    Should(Code).Contain('Precision(12, 3)');
  finally
    Generator.Free;
  end;
end;

end.
