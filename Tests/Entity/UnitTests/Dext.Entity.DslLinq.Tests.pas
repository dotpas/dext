unit Dext.Entity.DslLinq.Tests;

{***************************************************************************}
{  The fluent query DSL measured against LINQ.                              }
{                                                                           }
{  - Select<T>(Prop) read a Smart Property record as if it were the value:  }
{    "Invalid class typecast" when the rows came back.                      }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Collections,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  FireDAC.Phys.SQLite;

type
  [Table('dl_customers')]
  TDlCustomer = class
  private
    FId: IntType;
    FName: StringType;
    FCity: StringType;
  public
    [PrimaryKey]
    property Id: IntType read FId write FId;
    property Name: StringType read FName write FName;
    property City: StringType read FCity write FCity;
  end;

  [Table('dl_orders')]
  TDlOrder = class
  private
    FId: IntType;
    FCustomerId: IntType;
    FAmount: CurrencyType;
    FStatus: StringType;
  public
    [PrimaryKey]
    property Id: IntType read FId write FId;
    property CustomerId: IntType read FCustomerId write FCustomerId;
    property Amount: CurrencyType read FAmount write FAmount;
    property Status: StringType read FStatus write FStatus;
  end;

  TDlDb = class(TDbContext)
  private
    function GetCustomers: IDbSet<TDlCustomer>;
    function GetOrders: IDbSet<TDlOrder>;
  public
    property Customers: IDbSet<TDlCustomer> read GetCustomers;
    property Orders: IDbSet<TDlOrder> read GetOrders;
  end;

  [TestFixture('DSL x LINQ')]
  TDslLinqTests = class
  private
    FDb: TDlDb;
    procedure Seed;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // Select
    [Test]
    procedure Select_Currency_Property_Returns_The_Values;
    [Test]
    procedure Select_String_Property_With_Distinct;
    [Test]
    procedure Select_Integer_Property_Returns_The_Values;
    [Test]
    procedure Aggregates_By_Name_Work_With_Smart_Properties;
    [Test]
    procedure Aggregates_By_Name_Respect_The_Filter;
    [Test]
    procedure Aggregates_By_Name_Work_With_Integer_Property;
    [Test]
    procedure GroupBy_String_Prototype_Groups_By_The_Column;
    [Test]
    procedure GroupBy_Integer_Prototype_Groups_By_The_Column;
    [Test]
    procedure GroupBy_Column_Name_Still_Works;
  end;

implementation

{ TDlDb }

function TDlDb.GetCustomers: IDbSet<TDlCustomer>;
begin
  Result := Entities<TDlCustomer>;
end;

function TDlDb.GetOrders: IDbSet<TDlOrder>;
begin
  Result := Entities<TDlOrder>;
end;

{ TDslLinqTests }

procedure TDslLinqTests.Setup;
begin
  FDb := TDlDb.Create(DbContextOptions.UseSQLite(':memory:'));
  FDb.Customers;
  FDb.Orders;
  FDb.EnsureCreated;
  Seed;
end;

procedure TDslLinqTests.TearDown;
begin
  FreeAndNil(FDb);
end;

procedure TDslLinqTests.Seed;
var
  C: TDlCustomer;
  O: TDlOrder;
  I: Integer;
begin
  for I := 1 to 3 do
  begin
    C := TDlCustomer.Create;
    C.Id := I;
    C.Name := 'Customer ' + I.ToString;
    if I = 3 then C.City := 'RJ' else C.City := 'SP';
    FDb.Customers.Add(C);
  end;
  // Amounts 50..300; customers 1,2,3,1,2,3; status Open/Paid alternating
  for I := 1 to 6 do
  begin
    O := TDlOrder.Create;
    O.Id := I;
    O.CustomerId := ((I - 1) mod 3) + 1;
    O.Amount := I * 50;
    if I mod 2 = 0 then O.Status := 'Paid' else O.Status := 'Open';
    FDb.Orders.Add(O);
  end;
  FDb.SaveChanges;
end;

procedure TDslLinqTests.Select_Currency_Property_Returns_The_Values;
var
  O: TDlOrder;
  Values: IList<Currency>;
begin
  O := Prototype.Entity<TDlOrder>;
  Values := FDb.Orders.Where(O.Amount > 0).OrderBy(O.Id.Asc)
    .Select<Currency>(O.Amount).ToList;
  Should(Values.Count).Be(6);
  Should(Values[0] = 50).BeTrue;
  Should(Values[5] = 300).BeTrue;
end;

procedure TDslLinqTests.Select_String_Property_With_Distinct;
var
  O: TDlOrder;
  Values: IList<string>;
begin
  O := Prototype.Entity<TDlOrder>;
  Values := FDb.Orders.Where(O.Amount > 0).Select<string>(O.Status)
    .Distinct.ToList;
  Should(Values.Count).Be(2);
end;

procedure TDslLinqTests.Select_Integer_Property_Returns_The_Values;
var
  O: TDlOrder;
  Values: IList<Integer>;
begin
  O := Prototype.Entity<TDlOrder>;
  Values := FDb.Orders.Where(O.Amount > 250).OrderBy(O.Id.Asc)
    .Select<Integer>(O.CustomerId).ToList;
  Should(Values.Count).Be(1);
  Should(Values[0]).Be(3);
end;

procedure TDslLinqTests.Aggregates_By_Name_Work_With_Smart_Properties;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id > 0).Sum('Amount')).Be(1050);
  Should(FDb.Orders.Where(O.Id > 0).Average('Amount')).Be(175);
  Should(FDb.Orders.Where(O.Id > 0).Min('Amount')).Be(50);
  Should(FDb.Orders.Where(O.Id > 0).Max('Amount')).Be(300);
end;

procedure TDslLinqTests.Aggregates_By_Name_Respect_The_Filter;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  // Paid orders: 100 + 200 + 300
  Should(FDb.Orders.Where(O.Status = 'Paid').Sum('Amount')).Be(600);
  Should(FDb.Orders.Where(O.Status = 'Paid').Max('Amount')).Be(300);
end;

procedure TDslLinqTests.Aggregates_By_Name_Work_With_Integer_Property;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  // Customers 1,2,3,1,2,3
  Should(FDb.Orders.Where(O.Id > 0).Sum('CustomerId')).Be(12);
  Should(FDb.Orders.Where(O.Id > 0).Max('CustomerId')).Be(3);
end;

procedure TDslLinqTests.GroupBy_String_Prototype_Groups_By_The_Column;
var
  O: TDlOrder;
  Rows: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  // Two statuses (Open, Paid) -> two groups
  Rows := FDb.Orders.Where(O.Id > 0).GroupBy(O.Status).ToList;
  Should(Rows.Count).Be(2);
end;

procedure TDslLinqTests.GroupBy_Integer_Prototype_Groups_By_The_Column;
var
  O: TDlOrder;
  Rows: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  // Three customers -> three groups
  Rows := FDb.Orders.Where(O.Id > 0).GroupBy(O.CustomerId).ToList;
  Should(Rows.Count).Be(3);
end;

procedure TDslLinqTests.GroupBy_Column_Name_Still_Works;
var
  O: TDlOrder;
  Rows: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Id > 0).GroupBy('Status').ToList;
  Should(Rows.Count).Be(2);
end;

end.
