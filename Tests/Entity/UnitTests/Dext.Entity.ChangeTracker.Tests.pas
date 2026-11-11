unit Dext.Entity.ChangeTracker.Tests;

{***************************************************************************}
{  Regression: SaveChanges must refresh the change-tracker snapshot.        }
{                                                                           }
{  An entity saved with Add (or modified and saved) kept an empty/stale     }
{  snapshot after AcceptAllChanges. The next DetectChanges then saw every   }
{  property as modified, so a second SaveChanges with nothing changed      }
{  issued an UPDATE for the entity again, returned a wrong count, and could }
{  overwrite a change committed meanwhile by another context (lost update). }
{***************************************************************************}

interface

uses
  System.SysUtils,
  System.IOUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Mapping,
  Dext.Entity.Setup,
  FireDAC.Phys.SQLite;

type
  TSnapshotConta = class
  private
    FId: Integer;
    FSaldo: Currency;
    FStatus: string;
    FEtiqueta: string;
  public
    property Id: Integer read FId write FId;
    property Saldo: Currency read FSaldo write FSaldo;
    property Status: string read FStatus write FStatus;
    [NotMapped]
    property Etiqueta: string read FEtiqueta write FEtiqueta;
  end;

  TSnapshotContaSmart = class
  private
    FId: IntType;
    FSaldo: CurrencyType;
    FStatus: StringType;
  public
    property Id: IntType read FId write FId;
    property Saldo: CurrencyType read FSaldo write FSaldo;
    property Status: StringType read FStatus write FStatus;
  end;

  TSnapshotLinha = class
  private
    FId: Integer;
    FNome: string;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Nome: string read FNome write FNome;
  end;

  TSnapshotContaDb = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    function Contas: IDbSet<TSnapshotConta>;
    function ContasSmart: IDbSet<TSnapshotContaSmart>;
    function Linhas: IDbSet<TSnapshotLinha>;
  end;

  [TestFixture('ChangeTracker snapshot is refreshed by SaveChanges')]
  TChangeTrackerSnapshotTests = class
  private
    function NewDb(const AFile: string = ':memory:'): TSnapshotContaDb;
  public
    [Test]
    [Description('A second SaveChanges after Add has nothing to write')]
    procedure Add_Then_SaveChanges_Again_Writes_Nothing;

    [Test]
    [Description('Same as above with Smart Properties')]
    procedure Add_Then_SaveChanges_Again_Writes_Nothing_SmartProperties;

    [Test]
    [Description('A second SaveChanges after an update has nothing to write')]
    procedure Update_Then_SaveChanges_Again_Writes_Nothing;

    [Test]
    [Description('A change made after a save is still detected')]
    procedure Change_After_A_Save_Is_Detected_Again;

    [Test]
    [Description('Entities are inserted in the order they were added')]
    procedure Entities_Are_Inserted_In_The_Order_They_Were_Added;

    [Test]
    [Description('A change to a [NotMapped] property writes nothing and is not an invalid UPDATE')]
    procedure Change_To_A_NotMapped_Property_Writes_Nothing;

    [Test]
    [Description('An unchanged context must not overwrite another context''s update')]
    procedure Unchanged_Context_Does_Not_Overwrite_A_Concurrent_Update;

    [Test]
    [Description('Removing an entity that was only added writes nothing')]
    procedure Remove_Of_An_Added_Entity_Writes_Nothing;

    [Test]
    [Description('Removing an added entity must not delete another row with the same key')]
    procedure Remove_Of_An_Added_Entity_Keeps_The_Row_With_The_Same_Key;
  end;

implementation

{ TSnapshotContaDb }

procedure TSnapshotContaDb.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TSnapshotConta>.Table('snapshot_contas').HasKey('Id');
  Builder.Entity<TSnapshotContaSmart>.Table('snapshot_contas_smart').HasKey('Id');
  Builder.Entity<TSnapshotLinha>.Table('snapshot_linhas');
end;

function TSnapshotContaDb.Contas: IDbSet<TSnapshotConta>;
begin
  Result := Entities<TSnapshotConta>;
end;

function TSnapshotContaDb.ContasSmart: IDbSet<TSnapshotContaSmart>;
begin
  Result := Entities<TSnapshotContaSmart>;
end;

function TSnapshotContaDb.Linhas: IDbSet<TSnapshotLinha>;
begin
  Result := Entities<TSnapshotLinha>;
end;

{ TChangeTrackerSnapshotTests }

function TChangeTrackerSnapshotTests.NewDb(const AFile: string): TSnapshotContaDb;
begin
  Result := TSnapshotContaDb.Create(DbContextOptions.UseSQLite(AFile));
end;

procedure TChangeTrackerSnapshotTests.Add_Then_SaveChanges_Again_Writes_Nothing;
var
  Db: TSnapshotContaDb;
  Conta: TSnapshotConta;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Conta := TSnapshotConta.Create;
    Conta.Id := 1;
    Conta.Saldo := 1000;
    Conta.Status := 'ABERTA';
    Db.Contas.Add(Conta);

    Should(Db.SaveChanges).Be(1);
    Should(Db.SaveChanges).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Add_Then_SaveChanges_Again_Writes_Nothing_SmartProperties;
var
  Db: TSnapshotContaDb;
  Conta: TSnapshotContaSmart;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Conta := TSnapshotContaSmart.Create;
    Conta.Id := 1;
    Conta.Saldo := 1000;
    Conta.Status := 'ABERTA';
    Db.ContasSmart.Add(Conta);

    Should(Db.SaveChanges).Be(1);
    Should(Db.SaveChanges).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Update_Then_SaveChanges_Again_Writes_Nothing;
var
  Db: TSnapshotContaDb;
  Conta: TSnapshotConta;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Conta := TSnapshotConta.Create;
    Conta.Id := 1;
    Conta.Saldo := 1000;
    Conta.Status := 'ABERTA';
    Db.Contas.Add(Conta);
    Db.SaveChanges;

    Conta.Saldo := 600;
    Should(Db.SaveChanges).Be(1);
    Should(Db.SaveChanges).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Change_After_A_Save_Is_Detected_Again;
var
  Db: TSnapshotContaDb;
  Conta: TSnapshotConta;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Conta := TSnapshotConta.Create;
    Conta.Id := 1;
    Conta.Saldo := 1000;
    Conta.Status := 'ABERTA';
    Db.Contas.Add(Conta);
    Should(Db.SaveChanges).Be(1);

    Conta.Saldo := 600;
    Should(Db.SaveChanges).Be(1);

    Conta.Saldo := 100;
    Conta.Status := 'QUITADA';
    Should(Db.SaveChanges).Be(1);
    Should(Db.SaveChanges).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Entities_Are_Inserted_In_The_Order_They_Were_Added;
var
  Db: TSnapshotContaDb;
  Linhas: array[1..30] of TSnapshotLinha;
  I: Integer;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    for I := 1 to 30 do
    begin
      Linhas[I] := TSnapshotLinha.Create;
      Linhas[I].Nome := 'Linha ' + IntToStr(I);
      Db.Linhas.Add(Linhas[I]);
    end;
    Should(Db.SaveChanges).Be(30);

    // The generated Ids follow the Add order.
    for I := 2 to 30 do
      Should(Linhas[I].Id).BeGreaterThan(Linhas[I - 1].Id);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Change_To_A_NotMapped_Property_Writes_Nothing;
var
  Db: TSnapshotContaDb;
  Conta: TSnapshotConta;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Conta := TSnapshotConta.Create;
    Conta.Id := 1;
    Conta.Saldo := 1000;
    Conta.Status := 'ABERTA';
    Db.Contas.Add(Conta);
    Should(Db.SaveChanges).Be(1);

    // Only a property that is not a column changes: there is nothing to UPDATE.
    Conta.Etiqueta := 'urgente';
    Should(Db.SaveChanges).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Remove_Of_An_Added_Entity_Writes_Nothing;
var
  Db: TSnapshotContaDb;
  Conta: TSnapshotConta;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Conta := TSnapshotConta.Create;
    Conta.Id := 1;
    Conta.Saldo := 10;
    Db.Contas.Add(Conta);
    Db.Contas.Remove(Conta);

    // The row never existed: there is nothing to delete
    Should(Ord(Db.ChangeTracker.GetState(Conta))).Be(Ord(esDetached));
    Should(Db.SaveChanges).Be(0);
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Remove_Of_An_Added_Entity_Keeps_The_Row_With_The_Same_Key;
var
  Db: TSnapshotContaDb;
  Existente, Repetida: TSnapshotConta;
begin
  Db := NewDb;
  try
    Db.EnsureCreated;
    Existente := TSnapshotConta.Create;
    Existente.Id := 1;
    Existente.Saldo := 10;
    Db.Contas.Add(Existente);
    Db.SaveChanges;
    Db.Clear;

    // A second instance with the same key is added and then given up
    Repetida := TSnapshotConta.Create;
    Repetida.Id := 1;
    Repetida.Saldo := 99;
    Db.Contas.Add(Repetida);
    Db.Contas.Remove(Repetida);
    Should(Db.SaveChanges).Be(0);

    Db.Clear;
    Should(Db.Contas.Find(1) <> nil).BeTrue;
  finally
    Db.Free;
  end;
end;

procedure TChangeTrackerSnapshotTests.Unchanged_Context_Does_Not_Overwrite_A_Concurrent_Update;
var
  FileName: string;
  Db1, Db2, Db3: TSnapshotContaDb;
  Conta, Other: TSnapshotConta;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'dext_changetracker_lost_update.db');
  if TFile.Exists(FileName) then
    TFile.Delete(FileName);

  Db1 := NewDb(FileName);
  Db2 := NewDb(FileName);
  Db3 := NewDb(FileName);
  try
    Db1.EnsureCreated;
    Conta := TSnapshotConta.Create;
    Conta.Id := 1;
    Conta.Saldo := 1000;
    Conta.Status := 'ABERTA';
    Db1.Contas.Add(Conta);
    Db1.SaveChanges;

    // Another context reads the row, changes it and commits.
    Other := Db2.Contas.Find(1);
    Other.Saldo := 600;
    Should(Db2.SaveChanges).Be(1);

    // The first context changed nothing since its own save.
    Should(Db1.SaveChanges).Be(0);

    Should(Db3.Contas.Find(1).Saldo).Be(600);
  finally
    Db1.Free;
    Db2.Free;
    Db3.Free;
    if TFile.Exists(FileName) then
      TFile.Delete(FileName);
  end;
end;

end.
