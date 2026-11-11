unit Dext.Entity.LazyNavigation.Tests;

// Navigation declared as Lazy<TEntity> is the shape the scaffolding generator
// emits. The foreign key attribute carries the COLUMN name of the table
// (cliente_id), which is not the name of the Delphi property (ClienteId).

interface

{$I Dext.inc}

uses
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity,
  Dext.Entity.Core,
  Dext.Entity.Attributes,
  Dext.Types.Lazy,
  System.SysUtils;

type
  {$M+}
  [Table('lz_clientes')]
  TLzCliente = class
  private
    FId: Integer;
    FNome: string;
  public
    [PK, AutoInc, Column('id')]
    property Id: Integer read FId write FId;
    [Column('nome')]
    property Nome: string read FNome write FNome;
  end;

  [Table('lz_faturas')]
  TLzFatura = class
  private
    FNumero: Integer;
    FClienteId: Integer;
    FValor: Currency;
    FCliente: Lazy<TLzCliente>;
  public
    [PK, AutoInc, Column('numero')]
    property Numero: Integer read FNumero write FNumero;
    [Column('cliente_id')]
    property ClienteId: Integer read FClienteId write FClienteId;
    [Column('valor')]
    property Valor: Currency read FValor write FValor;
    [ForeignKey('cliente_id')]
    property Cliente: Lazy<TLzCliente> read FCliente write FCliente;
  end;
  {$M-}

  TLzDb = class(TDbContext)
  private
    function GetClientes: IDbSet<TLzCliente>;
    function GetFaturas: IDbSet<TLzFatura>;
  public
    property Clientes: IDbSet<TLzCliente> read GetClientes;
    property Faturas: IDbSet<TLzFatura> read GetFaturas;
  end;

  [TestFixture]
  TLazyNavigationTests = class
  private
    FDb: TLzDb;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Lazy_Entity_Navigation_Is_Not_Persisted_As_A_Column;
    [Test]
    procedure Lazy_Entity_Navigation_Loads_Through_Column_Named_Foreign_Key;
  end;

implementation

function TLzDb.GetClientes: IDbSet<TLzCliente>;
begin
  Result := Entities<TLzCliente>;
end;

function TLzDb.GetFaturas: IDbSet<TLzFatura>;
begin
  Result := Entities<TLzFatura>;
end;

procedure TLazyNavigationTests.Setup;
begin
  FDb := TLzDb.Create(DbContextOptions.UseSQLite(':memory:'));
  FDb.EnsureCreated;
end;

procedure TLazyNavigationTests.TearDown;
begin
  FDb.Free;
end;

procedure TLazyNavigationTests.Lazy_Entity_Navigation_Is_Not_Persisted_As_A_Column;
var
  Cliente: TLzCliente;
  Fatura: TLzFatura;
begin
  Cliente := TLzCliente.Create;
  Cliente.Nome := 'Ana';
  FDb.Clientes.Add(Cliente);
  FDb.SaveChanges;

  Fatura := TLzFatura.Create;
  Fatura.ClienteId := Cliente.Id;
  Fatura.Valor := 10;
  FDb.Faturas.Add(Fatura);
  FDb.SaveChanges;

  Should(Fatura.Numero).BeGreaterThan(0);
end;

procedure TLazyNavigationTests.Lazy_Entity_Navigation_Loads_Through_Column_Named_Foreign_Key;
var
  Cliente: TLzCliente;
  Fatura: TLzFatura;
  Numero: Integer;
begin
  Cliente := TLzCliente.Create;
  Cliente.Nome := 'Bruno';
  FDb.Clientes.Add(Cliente);
  FDb.SaveChanges;

  Fatura := TLzFatura.Create;
  Fatura.ClienteId := Cliente.Id;
  Fatura.Valor := 20;
  FDb.Faturas.Add(Fatura);
  FDb.SaveChanges;
  Numero := Fatura.Numero;
  FDb.Clear;

  Should(FDb.Faturas.Find(Numero).Cliente.Value.Nome).Be('Bruno');
end;

end.
