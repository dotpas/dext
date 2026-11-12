program Dext.Web.Tenancy.Tests;

// Multi-tenancy on the web path: TMultiTenancyMiddleware resolves the tenant
// from a header and fills the scoped ITenantProvider, and the DbContext that
// the container hands to the handler filters by that tenant.

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  System.SysUtils,
  System.IOUtils,
  Dext.Testing,
  Dext.Utils,
  Dext.Collections,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.MultiTenancy,
  Dext.MultiTenancy,
  Dext.DI.Interfaces,
  Dext.Entity,
  Dext.Entity.Core,
  Dext.Entity.Tenancy,
  Dext.Testing.WebApplicationFactory;

type
  [Table('notes')]
  TNote = class(TTenantEntity)
  private
    FId: Integer;
    FText: string;
  public
    [PK, AutoInc, Column('id')]
    property Id: Integer read FId write FId;
    [Column('text')]
    property Text: string read FText write FText;
  end;

  TNotesDb = class(TDbContext)
  public
    function Notes: IDbSet<TNote>;
  end;

  THeaderStrategy = class(TInterfacedObject, ITenantResolutionStrategy)
  public
    function Resolve(const AContext: IHttpContext): string;
  end;

  TMemoryStore = class(TInterfacedObject, ITenantStore)
  public
    function GetTenant(const AId: string): ITenant;
  end;

  [TestFixture]
  TWebTenancyTests = class
  private
    FFile: string;
    FFactory: TDextApplicationFactory<TObject>;
    procedure Seed;
    function NewFactory(ARequireTenant: Boolean): TDextApplicationFactory<TObject>;
  public
    [Setup]
    procedure Start;
    [TearDown]
    procedure Stop;
    [Test]
    procedure Each_Tenant_Sees_Only_Its_Own_Rows;
    [Test]
    procedure Unknown_Tenant_Is_Refused_With_404;
    [Test]
    procedure Missing_Header_Is_Refused_With_400;
    [Test]
    procedure Optional_Tenant_Lets_The_Request_Through;
  end;

function TNotesDb.Notes: IDbSet<TNote>;
begin
  Result := Entities<TNote>;
end;

function THeaderStrategy.Resolve(const AContext: IHttpContext): string;
var
  V: string;
begin
  if AContext.Request.Headers.TryGetValue('X-Tenant-Id', V) then
    Result := V
  else
    Result := '';
end;

function TMemoryStore.GetTenant(const AId: string): ITenant;
begin
  if (AId = 'aurora') or (AId = 'atlas') then
    Result := TTenant.Create(AId, AId, '')
  else
    Result := nil;
end;

procedure TWebTenancyTests.Seed;
var
  Provider: ITenantProvider;
  Db: TNotesDb;
  procedure Add(const Tenant, Text: string);
  var
    N: TNote;
  begin
    Provider.Tenant := TTenant.Create(Tenant, Tenant, '');
    N := TNote.Create;
    N.Text := Text;
    Db.Notes.Add(N);
    Db.SaveChanges;
  end;
begin
  Provider := TTenantProvider.Create;
  Db := TNotesDb.Create(DbContextOptions.UseSQLite(FFile), Provider);
  try
    Db.Notes;
    Db.EnsureCreated;
    Add('aurora', 'a1');
    Add('aurora', 'a2');
    Add('atlas', 't1');
  finally
    Db.Free;
  end;
end;

function TWebTenancyTests.NewFactory(
  ARequireTenant: Boolean): TDextApplicationFactory<TObject>;
begin
  Result := TDextApplicationFactory<TObject>.Create
    .WithTestServices(
      procedure(Services: TDextServices)
      begin
        Services.AddScoped<ITenantProvider, TTenantProvider>;
        Services.AddDbContext<TNotesDb>(
          procedure(Options: TDbContextOptions)
          begin
            Options.UseSQLite(FFile);
          end);
      end)
    .WithConfigure(
      procedure(App: TWebApplication)
      var
        B: IApplicationBuilder;
        Mid: TMultiTenancyMiddleware;
      begin
        B := App.Builder;
        Mid := TMultiTenancyMiddleware.Create(THeaderStrategy.Create,
          TMemoryStore.Create);
        Mid.RequireTenant := ARequireTenant;
        B.UseMiddleware(Mid as IMiddleware);
        B.MapGet('/public',
          procedure(Ctx: IHttpContext)
          begin
            Results.Ok('public').Execute(Ctx);
          end);
        B.MapGet('/notes',
          procedure(Ctx: IHttpContext)
          var
            Db: TNotesDb;
            N: TNote;
            S: string;
          begin
            Db := Ctx.Services.GetService(TServiceType.FromClass(TNotesDb))
              as TNotesDb;
            S := '';
            for N in Db.Notes.ToList do
              S := S + string(N.Text) + ';';
            Results.Ok(S).Execute(Ctx);
          end);
      end);
end;

procedure TWebTenancyTests.Start;
begin
  FFile := TPath.Combine(TPath.GetTempPath, 'dext_web_tenancy.db');
  if TFile.Exists(FFile) then
    TFile.Delete(FFile);
  Seed;
  FFactory := NewFactory(True);
end;

procedure TWebTenancyTests.Stop;
begin
  FFactory.Free;
  if TFile.Exists(FFile) then
    TFile.Delete(FFile);
end;

procedure TWebTenancyTests.Each_Tenant_Sees_Only_Its_Own_Rows;
var
  Resp: IDextTestHttpResponse;
begin
  Resp := FFactory.CreateClient.Header('X-Tenant-Id', 'aurora').Get('/notes');
  Should(Resp.StatusCode).Be(200);
  Should(Resp.Body).Contain('a1;a2;');
  Should(Resp.Body).NotContain('t1');
  Resp := FFactory.CreateClient.Header('X-Tenant-Id', 'atlas').Get('/notes');
  Should(Resp.Body).Contain('t1;');
  Should(Resp.Body).NotContain('a1');
end;

procedure TWebTenancyTests.Unknown_Tenant_Is_Refused_With_404;
var
  Resp: IDextTestHttpResponse;
begin
  Resp := FFactory.CreateClient.Header('X-Tenant-Id', 'zeta').Get('/notes');
  Should(Resp.StatusCode).Be(404);
  Should(Resp.Body).NotContain('a1');
  Should(Resp.Body).NotContain('t1');
end;

procedure TWebTenancyTests.Missing_Header_Is_Refused_With_400;
var
  Resp: IDextTestHttpResponse;
begin
  Resp := FFactory.CreateClient.Get('/notes');
  Should(Resp.StatusCode).Be(400);
  Should(Resp.Body).NotContain('a1');
  Should(Resp.Body).NotContain('t1');
end;

procedure TWebTenancyTests.Optional_Tenant_Lets_The_Request_Through;
var
  Resp: IDextTestHttpResponse;
begin
  FFactory.Free;
  FFactory := NewFactory(False);
  Resp := FFactory.CreateClient.Get('/public');
  Should(Resp.StatusCode).Be(200);
  Should(Resp.Body).Contain('public');
end;

begin
  SetConsoleCharSet;
  RunTests(TTest.Configure.Verbose.RegisterFixtures([TWebTenancyTests]));
end.
