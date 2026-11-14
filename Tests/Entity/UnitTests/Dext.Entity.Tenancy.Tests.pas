unit Dext.Entity.Tenancy.Tests;

interface

uses
  System.SysUtils,
  System.IOUtils,
  Dext.Testing,
  Dext.Testing.Attributes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  Dext.Entity.Tenancy,
  Dext.MultiTenancy,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLiteWrapper.Stat,
  Dext.Entity.Drivers.FireDAC;

type
  {$M+}
  [Table('tenant_notes')]
  TTenantNote = class(TTenantEntity)
  private
    FId: Integer;
    FText: string;
  public
    [PK]
    property Id: Integer read FId write FId;
    property Text: string read FText write FText;
  end;
  {$M-}

  TTenantNotesContext = class(TDbContext)
  public
    function Notes: IDbSet<TTenantNote>;
  end;

  [Fixture]
  [Category('ORM'), Category('Integration'), Category('Tenancy')]
  TTenancyConnectionSwitchTests = class
  private
    FFileA: string;
    FFileB: string;
    function TenantFor(const AId, AFile: string): ITenant;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_ReadAfterTenantSwitch_ShouldUseTheTenantDatabase;
    [Test]
    procedure Test_SwitchWithTheConnectionAlreadyOpen_ShouldReconnect;
  end;

  [Fixture]
  [Category('ORM'), Category('Integration'), Category('Tenancy')]
  TTenancyWriteTests = class
  private
    FProvider: ITenantProvider;
    FDb: TTenantNotesContext;
    FTenantA: ITenant;
    FTenantB: ITenant;
    function RowCount: Integer;
    function ErrorClassOf(const AAction: TProc): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Update_OfAnotherTenantsRow_ShouldRaiseConcurrencyError;
    [Test]
    procedure Test_Delete_OfAnotherTenantsRow_ShouldRaiseConcurrencyError;
    [Test]
    procedure Test_Delete_OfARowAlreadyGone_ShouldRaiseConcurrencyError;
  end;

implementation

{ TTenantNotesContext }

function TTenantNotesContext.Notes: IDbSet<TTenantNote>;
begin
  Result := Entities<TTenantNote>;
end;

{ TTenancyConnectionSwitchTests }

procedure TTenancyConnectionSwitchTests.Setup;
begin
  FFileA := TPath.Combine(TPath.GetTempPath, 'dext_tenancy_a.db');
  FFileB := TPath.Combine(TPath.GetTempPath, 'dext_tenancy_b.db');
  System.SysUtils.DeleteFile(FFileA);
  System.SysUtils.DeleteFile(FFileB);
end;

procedure TTenancyConnectionSwitchTests.TearDown;
begin
  System.SysUtils.DeleteFile(FFileA);
  System.SysUtils.DeleteFile(FFileB);
end;

function TTenancyConnectionSwitchTests.TenantFor(const AId, AFile: string): ITenant;
begin
  Result := TTenant.Create(AId, AId, 'DriverID=SQLite;Database=' + AFile);
end;

procedure TTenancyConnectionSwitchTests.Test_ReadAfterTenantSwitch_ShouldUseTheTenantDatabase;
var
  Provider: ITenantProvider;
  Db: TTenantNotesContext;
  Note: TTenantNote;
begin
  Provider := TTenantProvider.Create;
  Db := TTenantNotesContext.Create(DbContextOptions.UseSQLite(FFileA), Provider);
  try
    Db.Notes;

    Provider.Tenant := TenantFor('a', FFileA);
    Db.EnsureCreated;
    Note := TTenantNote.Create;
    Note.Id := 1;
    Note.Text := 'from A';
    Db.Notes.Add(Note);
    Db.SaveChanges;
    // A new tenant starts from a clean tracker.
    Db.Clear;

    Provider.Tenant := TenantFor('b', FFileB);
    Db.EnsureCreated;
    Note := TTenantNote.Create;
    Note.Id := 1;
    Note.Text := 'from B';
    Db.Notes.Add(Note);
    Db.SaveChanges;
    Db.Clear;

  finally
    Db.Free;
  end;
end;

procedure TTenancyConnectionSwitchTests.Test_SwitchWithTheConnectionAlreadyOpen_ShouldReconnect;
var
  Provider: ITenantProvider;
  Db: TTenantNotesContext;
  Note: TTenantNote;
begin
  Provider := TTenantProvider.Create;
  Db := TTenantNotesContext.Create(DbContextOptions.UseSQLite(FFileA), Provider);
  try
    Db.Notes;
    // The connection is open before the first tenant is applied.
    Db.Connection.Connect;

    Provider.Tenant := TenantFor('a', FFileA);
    Db.EnsureCreated;
    Note := TTenantNote.Create;
    Note.Id := 1;
    Note.Text := 'from A';
    Db.Notes.Add(Note);
    Db.SaveChanges;
    Db.Clear;

    Provider.Tenant := TenantFor('b', FFileB);
    Db.EnsureCreated;
    Note := TTenantNote.Create;
    Note.Id := 1;
    Note.Text := 'from B';
    Db.Notes.Add(Note);
    Db.SaveChanges;
    Db.Clear;

    Should(Db.Notes.Find(1).Text).Be('from B');
    Provider.Tenant := TenantFor('a', FFileA);
    Db.Clear;
    Should(Db.Notes.Find(1).Text).Be('from A');
  finally
    Db.Free;
  end;
end;

{ TTenancyWriteTests }

procedure TTenancyWriteTests.Setup;
var
  Note: TTenantNote;
begin
  FProvider := TTenantProvider.Create;
  FTenantA := TTenant.Create('a', 'A', '');
  FTenantB := TTenant.Create('b', 'B', '');
  FDb := TTenantNotesContext.Create(DbContextOptions.UseSQLite(':memory:'), FProvider);
  FDb.Notes;
  FDb.EnsureCreated;
  FProvider.Tenant := FTenantA;
  Note := TTenantNote.Create;
  Note.Id := 1;
  Note.Text := 'from A';
  FDb.Notes.Add(Note);
  FDb.SaveChanges;
  FDb.Clear;
end;

procedure TTenancyWriteTests.TearDown;
begin
  FDb.Free;
  FProvider := nil;
end;

function TTenancyWriteTests.RowCount: Integer;
var
  Reader: IDbReader;
begin
  Reader := FDb.Connection.CreateCommand('SELECT COUNT(*) FROM tenant_notes').ExecuteQuery;
  Reader.Next;
  Result := Reader.GetValue(0).AsInteger;
end;

function TTenancyWriteTests.ErrorClassOf(const AAction: TProc): string;
begin
  Result := '';
  try
    AAction();
  except
    on E: Exception do
      Result := E.ClassName;
  end;
end;

procedure TTenancyWriteTests.Test_Update_OfAnotherTenantsRow_ShouldRaiseConcurrencyError;
var
  Note: TTenantNote;
begin
  Note := FDb.Notes.Find(1);
  FProvider.Tenant := FTenantB;
  Note.Text := 'changed by B';

  Should(ErrorClassOf(
    procedure
    begin
      FDb.SaveChanges;
    end)).Be('EOptimisticConcurrencyException');
end;

procedure TTenancyWriteTests.Test_Delete_OfAnotherTenantsRow_ShouldRaiseConcurrencyError;
var
  Note: TTenantNote;
begin
  Note := FDb.Notes.Find(1);
  FProvider.Tenant := FTenantB;
  FDb.Notes.Remove(Note);

  Should(ErrorClassOf(
    procedure
    begin
      FDb.SaveChanges;
    end)).Be('EOptimisticConcurrencyException');
  // The row of tenant A is untouched.
  Should(RowCount).Be(1);
end;

procedure TTenancyWriteTests.Test_Delete_OfARowAlreadyGone_ShouldRaiseConcurrencyError;
var
  Note: TTenantNote;
begin
  Note := FDb.Notes.Find(1);
  FDb.Connection.CreateCommand('DELETE FROM tenant_notes WHERE Id = 1').ExecuteNonQuery;
  FDb.Notes.Remove(Note);

  Should(ErrorClassOf(
    procedure
    begin
      FDb.SaveChanges;
    end)).Be('EOptimisticConcurrencyException');
end;

end.

