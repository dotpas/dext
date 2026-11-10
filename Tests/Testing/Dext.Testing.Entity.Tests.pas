unit Dext.Testing.Entity.Tests;

// MockDbSet<T>: an IDbSet<T> mock answered from an in-memory list, with the
// real expression evaluated; and a context mocked by the auto mocker.

interface

uses
  System.SysUtils,
  System.Rtti,
  Dext.Testing,
  Dext.Mocks,
  Dext.Mocks.Matching,
  Dext.Mocks.Auto,
  Dext.Collections,
  Dext.Core.SmartTypes,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Base,
  Dext.Specifications.OrderBy,
  Dext.Entity,
  Dext.Entity.Core,
  Dext.Testing.Entity;

type
  TMockPedido = class
  private
    FNumero: IntType;
    FStatus: StringType;
    FValor: CurrencyType;
  public
    class function Novo(ANumero: Integer; const AStatus: string; AValor: Currency): TMockPedido; static;
    property Numero: IntType read FNumero write FNumero;
    property Status: StringType read FStatus write FStatus;
    property Valor: CurrencyType read FValor write FValor;
  end;

  TPedidosAbertosPorValor = class(TSpecification<TMockPedido>)
  public
    constructor CreateTop(Quantos: Integer);
  end;

  TMockPedidosDb = class(TDbContext)
  public
    function Pedidos: IDbSet<TMockPedido>; virtual;
  end;

  TServicoPedidos = class
  private
    FDb: TMockPedidosDb;
  public
    constructor Create(Db: TMockPedidosDb);
    function TotalEmAberto: Currency;
  end;

  [TestFixture('MockDbSet<T> and context mocks')]
  TMockDbSetTests = class
  public
    [Test]
    procedure Where_Evaluates_The_Real_Expression;
    [Test]
    procedure ToList_With_Specification_Applies_Order_And_Take;
    [Test]
    procedure FirstOrDefault_Any_And_Count_Use_The_List;
    [Test]
    procedure Add_Appends_And_Can_Be_Verified;
    [Test]
    procedure AutoMocker_Mocks_A_Context_With_Virtual_DbSet;
  end;

implementation

{ TMockPedido }

class function TMockPedido.Novo(ANumero: Integer; const AStatus: string; AValor: Currency): TMockPedido;
begin
  Result := TMockPedido.Create;
  Result.Numero := ANumero;
  Result.Status := AStatus;
  Result.Valor := AValor;
end;

{ TPedidosAbertosPorValor }

constructor TPedidosAbertosPorValor.CreateTop(Quantos: Integer);
var
  P: TMockPedido;
begin
  inherited Create;
  P := Prototype.Entity<TMockPedido>;
  Where(P.Status = 'ABERTO');
  OrderBy(TOrderBy.Create('Valor', False));
  Take(Quantos);
end;

{ TMockPedidosDb }

function TMockPedidosDb.Pedidos: IDbSet<TMockPedido>;
begin
  Result := Entities<TMockPedido>;
end;

{ TServicoPedidos }

constructor TServicoPedidos.Create(Db: TMockPedidosDb);
begin
  inherited Create;
  FDb := Db;
end;

function TServicoPedidos.TotalEmAberto: Currency;
var
  P: TMockPedido;
  Abertos: IList<TMockPedido>;
  I: Integer;
begin
  P := Prototype.Entity<TMockPedido>;
  Abertos := FDb.Pedidos.Where(P.Status = 'ABERTO').ToList;
  Result := 0;
  for I := 0 to Abertos.Count - 1 do
    Result := Result + Abertos[I].Valor;
end;

{ TMockDbSetTests }

procedure TMockDbSetTests.Where_Evaluates_The_Real_Expression;
var
  Pedidos: Mock<IDbSet<TMockPedido>>;
  P: TMockPedido;
  Abertos: IList<TMockPedido>;
  Caros: IExpression;
begin
  Pedidos := MockDbSet<TMockPedido>.From([
    TMockPedido.Novo(1, 'ABERTO', 100),
    TMockPedido.Novo(2, 'PAGO', 200),
    TMockPedido.Novo(3, 'ABERTO', 300)]);
  P := Prototype.Entity<TMockPedido>;
  Caros := P.Valor > 150;

  Abertos := Pedidos.Instance.Where(P.Status = 'ABERTO').ToList;
  Should(Abertos.Count).Be(2);

  Abertos := Pedidos.Instance.Where(Caros).ToList;
  Should(Abertos.Count).Be(2);
  Should(Abertos[0].Numero).Be(2);
end;

procedure TMockDbSetTests.ToList_With_Specification_Applies_Order_And_Take;
var
  Pedidos: Mock<IDbSet<TMockPedido>>;
  Top: IList<TMockPedido>;
  Spec: ISpecification<TMockPedido>;
begin
  Pedidos := MockDbSet<TMockPedido>.From([
    TMockPedido.Novo(1, 'ABERTO', 100),
    TMockPedido.Novo(2, 'PAGO', 900),
    TMockPedido.Novo(3, 'ABERTO', 300),
    TMockPedido.Novo(4, 'ABERTO', 200)]);

  Spec := TPedidosAbertosPorValor.CreateTop(2);
  Top := Pedidos.Instance.ToList(Spec);

  Should(Top.Count).Be(2);
  Should(Top[0].Numero).Be(3);
  Should(Top[1].Numero).Be(4);
end;

procedure TMockDbSetTests.FirstOrDefault_Any_And_Count_Use_The_List;
var
  Pedidos: Mock<IDbSet<TMockPedido>>;
  P: TMockPedido;
begin
  Pedidos := MockDbSet<TMockPedido>.From([
    TMockPedido.Novo(1, 'ABERTO', 100),
    TMockPedido.Novo(2, 'PAGO', 200)]);
  P := Prototype.Entity<TMockPedido>;

  Should(Pedidos.Instance.FirstOrDefault(P.Status = 'PAGO').Numero).Be(2);
  Should(TObject(Pedidos.Instance.FirstOrDefault(P.Status = 'CANCELADO'))).BeNil;
  Should(Pedidos.Instance.Any(P.Status = 'PAGO')).BeTrue;
  Should(Pedidos.Instance.Count(P.Status = 'ABERTO')).Be(1);
end;

procedure TMockDbSetTests.Add_Appends_And_Can_Be_Verified;
var
  Pedidos: Mock<IDbSet<TMockPedido>>;
  P: TMockPedido;
begin
  Pedidos := MockDbSet<TMockPedido>.From([TMockPedido.Novo(1, 'ABERTO', 100)]);
  P := Prototype.Entity<TMockPedido>;

  Pedidos.Instance.Add(TMockPedido.Novo(2, 'ABERTO', 50));

  Should(Pedidos.Instance.Count(P.Status = 'ABERTO')).Be(2);
  Pedidos.Received(Times.Once).Add(Arg.Any<TMockPedido>);
end;

procedure TMockDbSetTests.AutoMocker_Mocks_A_Context_With_Virtual_DbSet;
var
  Mocker: TAutoMocker;
  Pedidos: Mock<IDbSet<TMockPedido>>;
  Servico: TServicoPedidos;
begin
  Pedidos := MockDbSet<TMockPedido>.From([
    TMockPedido.Novo(1, 'ABERTO', 100),
    TMockPedido.Novo(2, 'PAGO', 200),
    TMockPedido.Novo(3, 'ABERTO', 300)]);
  Mocker := TAutoMocker.Create;
  try
    Servico := Mocker.CreateInstance<TServicoPedidos>;
    try
      Mocker.GetMock<TMockPedidosDb>.Setup
        .Returns(TValue.From<IDbSet<TMockPedido>>(Pedidos.Instance))
        .When.Pedidos;

      Should(Servico.TotalEmAberto).Be(400);
    finally
      Servico.Free;
    end;
  finally
    Mocker.Free;
  end;
end;

end.
