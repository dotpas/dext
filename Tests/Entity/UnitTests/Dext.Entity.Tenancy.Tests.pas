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

end.
