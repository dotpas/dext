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
  Dext.Collections.Dict,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Query,
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
    FCreatedAt: DateTimeType;
  public
    [PrimaryKey]
    property Id: IntType read FId write FId;
    property CustomerId: IntType read FCustomerId write FCustomerId;
    property Amount: CurrencyType read FAmount write FAmount;
    property Status: StringType read FStatus write FStatus;
    property CreatedAt: DateTimeType read FCreatedAt write FCreatedAt;
  end;

  TDlDb = class(TDbContext)
  private
    function GetCustomers: IDbSet<TDlCustomer>;
    function GetOrders: IDbSet<TDlOrder>;
  public
    property Customers: IDbSet<TDlCustomer> read GetCustomers;
    property Orders: IDbSet<TDlOrder> read GetOrders;
  end;

  TDlStatusTotal = class
  private
    FStatus: string;
    FTotal: Currency;
    FCnt: Integer;
  public
    property Status: string read FStatus write FStatus;
    property Total: Currency read FTotal write FTotal;
    property Cnt: Integer read FCnt write FCnt;
  end;

  TDlTotals = class
  private
    FCnt: Integer;
    FBiggest: Currency;
    FMean: Double;
  public
    property Cnt: Integer read FCnt write FCnt;
    property Biggest: Currency read FBiggest write FBiggest;
    property Mean: Double read FMean write FMean;
  end;

  TDlCityTotal = class
  private
    FCity: string;
    FTotal: Currency;
  public
    property City: string read FCity write FCity;
    property Total: Currency read FTotal write FTotal;
  end;

  TDlDistinct = class
  private
    FCustomers: Integer;
  public
    property Customers: Integer read FCustomers write FCustomers;
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
    [Test]
    procedure Join_With_Prototype_On_Condition_Filters_By_The_Joined_Table;
    [Test]
    procedure Join_With_Prototype_Condition_Without_Filter;
    [Test]
    procedure Join_With_String_Condition_Still_Works;
    [Test]
    procedure Single_Returns_The_Only_Element;
    [Test]
    procedure Single_Raises_When_There_Is_More_Than_One;
    [Test]
    procedure Single_Raises_When_There_Is_None;
    [Test]
    procedure SingleOrDefault_Returns_Nil_When_There_Is_None;
    [Test]
    procedure SingleOrDefault_Raises_When_There_Is_More_Than_One;
    [Test]
    procedure Single_With_Predicate;
    [Test]
    procedure Last_Returns_The_Last_Element;
    [Test]
    procedure Last_With_Predicate_And_OrDefault;
    [Test]
    procedure ElementAt_Returns_The_Element_At_The_Index;
    [Test]
    procedure ElementAt_Raises_Out_Of_Range_And_OrDefault_Returns_Nil;
    [Test]
    procedure All_Checks_Every_Element;
    [Test]
    procedure Contains_Finds_An_Entity_Of_The_Sequence;
    [Test]
    procedure Reverse_Inverts_The_Order;
    [Test]
    procedure TakeWhile_And_SkipWhile_Split_The_Sequence;
    [Test]
    procedure Concat_Appends_The_Other_Sequence;
    [Test]
    procedure Union_Intersect_Except_Work_By_Entity;
    [Test]
    procedure MaxOf_And_MinOf_Work_For_Any_Comparable_Type;
    [Test]
    procedure MaxOf_Raises_On_An_Empty_Sequence;
    [Test]
    procedure Aggregate_Accumulates_From_A_Seed;
    [Test]
    procedure ToDictionary_Keys_By_The_Selector;
    [Test]
    procedure ToDictionary_With_Value_Selector;
    [Test]
    procedure ToDictionary_Raises_On_A_Repeated_Key;
    [Test]
    procedure ThenBy_Accepts_An_Order_Expression;
    [Test]
    procedure OrderBy_Column_Of_The_Joined_Table;
    [Test]
    procedure OrderBy_Prop_Of_The_Joined_Table;
    [Test]
    procedure OrderBy_Base_Column_Still_Works_With_A_Join;
    [Test]
    procedure GroupBy_Projects_Key_And_Aggregates_To_A_Dto;
    [Test]
    procedure Having_Filters_The_Groups;
    [Test]
    procedure Where_Applies_Before_The_Grouping;
    [Test]
    procedure Aggregates_Without_GroupBy_Return_One_Row;
    [Test]
    procedure GroupBy_Column_Of_The_Joined_Table;
    [Test]
    procedure CountDistinct_Counts_Distinct_Values;
    [Test]
    procedure Same_Column_Name_In_Two_Tables_Does_Not_Share_The_Cached_SQL;
    [Test]
    procedure Having_With_Other_Literal_Reuses_The_SQL_And_Refreshes_Params;
    [Test]
    procedure Aggregates_By_Name_Raise_On_An_Empty_Sequence;
    [Test]
    procedure MaxOrDefault_Returns_The_Default_On_An_Empty_Sequence;
    [Test]
    procedure Aggregates_By_Name_With_Take_Use_The_Paged_Rows;
    [Test]
    procedure Aggregates_By_Name_Respect_The_Join_Filter;
    [Test]
    procedure In_Subquery_Filters_By_The_Values_Of_Another_Entity;
    [Test]
    procedure NotIn_Subquery_Is_The_Complement;
    [Test]
    procedure Correlated_Exists_Uses_The_Outer_Row;
    [Test]
    procedure Correlated_NotExists_Is_The_Complement;
    [Test]
    procedure Subquery_Params_Continue_The_Numbering_Of_The_Outer_Query;
    [Test]
    procedure Subquery_With_Other_Literals_Reuses_The_Cache_And_Refreshes;
    [Test]
    procedure Subquery_Works_Inside_A_Query_With_A_Join;
    [Test]
    procedure ToUpper_And_ToLower_Compare_Ignoring_Case;
    [Test]
    procedure Len_Counts_The_Characters;
    [Test]
    procedure Substring_Uses_A_Zero_Based_Index;
    [Test]
    procedure Trim_Removes_The_Blanks_Around;
    [Test]
    procedure Year_Month_Day_Extract_The_Parts_Of_The_Date;
    [Test]
    procedure Function_Result_Can_Be_Combined_With_Other_Conditions;
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
    // 2024-01-15 .. 2024-03-15, then 2025-04-15 .. 2025-06-15
    O.CreatedAt := EncodeDate(2024 + (I - 1) div 3, I, 15);
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

procedure TDslLinqTests.Join_With_Prototype_On_Condition_Filters_By_The_Joined_Table;
var
  O: TDlOrder;
  C: TDlCustomer;
  Rows: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // Customers 1 and 2 are in SP: orders 1,2,4,5
  Rows := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .Where(C.City = 'SP')
    .ToList;
  Should(Rows.Count).Be(4);
end;

procedure TDslLinqTests.Join_With_Prototype_Condition_Without_Filter;
var
  O: TDlOrder;
  C: TDlCustomer;
  Rows: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .ToList;
  Should(Rows.Count).Be(6);
end;

procedure TDslLinqTests.Join_With_String_Condition_Still_Works;
var
  O: TDlOrder;
  Rows: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .Join('dl_customers', 'c', 'dl_orders.CustomerId = c.Id')
    .ToList;
  Should(Rows.Count).Be(6);
end;

procedure TDslLinqTests.Single_Returns_The_Only_Element;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id = 3).Single.Id).Be(3);
end;

procedure TDslLinqTests.Single_Raises_When_There_Is_More_Than_One;
var
  O: TDlOrder;
  Raised: Boolean;
begin
  O := Prototype.Entity<TDlOrder>;
  Raised := False;
  try
    FDb.Orders.Where(O.Id > 0).Single;
  except
    on Exception do Raised := True;
  end;
  Should(Raised).BeTrue;
end;

procedure TDslLinqTests.Single_Raises_When_There_Is_None;
var
  O: TDlOrder;
  Raised: Boolean;
begin
  O := Prototype.Entity<TDlOrder>;
  Raised := False;
  try
    FDb.Orders.Where(O.Id > 99).Single;
  except
    on Exception do Raised := True;
  end;
  Should(Raised).BeTrue;
end;

procedure TDslLinqTests.SingleOrDefault_Returns_Nil_When_There_Is_None;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id > 99).SingleOrDefault = nil).BeTrue;
  Should(FDb.Orders.Where(O.Id = 2).SingleOrDefault.Id).Be(2);
end;

procedure TDslLinqTests.SingleOrDefault_Raises_When_There_Is_More_Than_One;
var
  O: TDlOrder;
  Raised: Boolean;
begin
  O := Prototype.Entity<TDlOrder>;
  Raised := False;
  try
    FDb.Orders.Where(O.Id > 0).SingleOrDefault;
  except
    on Exception do Raised := True;
  end;
  Should(Raised).BeTrue;
end;

procedure TDslLinqTests.Single_With_Predicate;
var
  O: TDlOrder;
  Item: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Item := FDb.Orders.Where(O.Id > 0).Single(
    function(Ord: TDlOrder): Boolean
    begin
      Result := Ord.Id = 4;
    end);
  Should(Item.Id).Be(4);
end;

procedure TDslLinqTests.Last_Returns_The_Last_Element;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).Last.Id).Be(6);
end;

procedure TDslLinqTests.Last_With_Predicate_And_OrDefault;
var
  O: TDlOrder;
  Item: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Item := FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).Last(
    function(Ord: TDlOrder): Boolean
    begin
      Result := Ord.Id < 4;
    end);
  Should(Item.Id).Be(3);
  Should(FDb.Orders.Where(O.Id > 99).LastOrDefault = nil).BeTrue;
  Should(FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).LastOrDefault.Id).Be(6);
end;

procedure TDslLinqTests.ElementAt_Returns_The_Element_At_The_Index;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).ElementAt(2).Id).Be(3);
end;

procedure TDslLinqTests.ElementAt_Raises_Out_Of_Range_And_OrDefault_Returns_Nil;
var
  O: TDlOrder;
  Raised: Boolean;
begin
  O := Prototype.Entity<TDlOrder>;
  Raised := False;
  try
    FDb.Orders.Where(O.Id > 0).ElementAt(10);
  except
    on Exception do Raised := True;
  end;
  Should(Raised).BeTrue;
  Should(FDb.Orders.Where(O.Id > 0).ElementAtOrDefault(10) = nil).BeTrue;
end;

procedure TDslLinqTests.All_Checks_Every_Element;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id > 0).All(
    function(Ord: TDlOrder): Boolean
    begin
      Result := Ord.Id > 0;
    end)).BeTrue;
  Should(FDb.Orders.Where(O.Id > 0).All(
    function(Ord: TDlOrder): Boolean
    begin
      Result := Ord.Id > 1;
    end)).BeFalse;
  // An empty sequence satisfies any predicate
  Should(FDb.Orders.Where(O.Id > 99).All(
    function(Ord: TDlOrder): Boolean
    begin
      Result := False;
    end)).BeTrue;
end;

procedure TDslLinqTests.Contains_Finds_An_Entity_Of_The_Sequence;
var
  O: TDlOrder;
  Paid, Third: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Third := FDb.Orders.Where(O.Id = 3).Single;
  Paid := FDb.Orders.Where(O.Status = 'Paid').First;
  Should(FDb.Orders.Where(O.Status = 'Open').Contains(Third)).BeTrue;
  Should(FDb.Orders.Where(O.Status = 'Open').Contains(Paid)).BeFalse;
end;

procedure TDslLinqTests.Reverse_Inverts_The_Order;
var
  O: TDlOrder;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Items := FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).Reverse.ToList;
  Should(Items.Count).Be(6);
  Should(Items[0].Id).Be(6);
  Should(Items[5].Id).Be(1);
end;

procedure TDslLinqTests.TakeWhile_And_SkipWhile_Split_The_Sequence;
var
  O: TDlOrder;
  Head, Tail: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Head := FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).TakeWhile(
    function(Ord: TDlOrder): Boolean
    begin
      Result := Ord.Id < 4;
    end).ToList;
  Tail := FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).SkipWhile(
    function(Ord: TDlOrder): Boolean
    begin
      Result := Ord.Id < 4;
    end).ToList;
  Should(Head.Count).Be(3);
  Should(Tail.Count).Be(3);
  Should(Tail[0].Id).Be(4);
end;

procedure TDslLinqTests.Concat_Appends_The_Other_Sequence;
var
  O: TDlOrder;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  // Amounts <= 100: ids 1, 2; amounts >= 100: ids 2..6
  Items := FDb.Orders.Where(O.Amount <= 100)
    .Concat(FDb.Orders.Where(O.Amount >= 100)).ToList;
  Should(Items.Count).Be(7);
end;

procedure TDslLinqTests.Union_Intersect_Except_Work_By_Entity;
var
  O: TDlOrder;
  A, B: TFluentQuery<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  A := FDb.Orders.Where(O.Amount <= 100);
  B := FDb.Orders.Where(O.Amount >= 100);
  Should(A.Union(B).ToList.Count).Be(6);
  Should(A.Intersect(B).ToList.Count).Be(1);
  Should(A.Intersect(B).Single.Id).Be(2);
  Should(A.&Except(B).ToList.Count).Be(1);
  Should(A.&Except(B).Single.Id).Be(1);
end;

procedure TDslLinqTests.MaxOf_And_MinOf_Work_For_Any_Comparable_Type;
var
  O: TDlOrder;
  Q: TFluentQuery<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Q := FDb.Orders.Where(O.Id > 0);
  Should(Q.MaxOf<Integer>(
    function(Ord: TDlOrder): Integer
    begin
      Result := Ord.CustomerId;
    end)).Be(3);
  Should(Q.MinOf<string>(
    function(Ord: TDlOrder): string
    begin
      Result := Ord.Status;
    end)).Be('Open');
  Should(Q.MaxOf<string>(
    function(Ord: TDlOrder): string
    begin
      Result := Ord.Status;
    end)).Be('Paid');
end;

procedure TDslLinqTests.MaxOf_Raises_On_An_Empty_Sequence;
var
  O: TDlOrder;
  Raised: Boolean;
begin
  O := Prototype.Entity<TDlOrder>;
  Raised := False;
  try
    FDb.Orders.Where(O.Id > 99).MaxOf<Integer>(
      function(Ord: TDlOrder): Integer
      begin
        Result := Ord.Id;
      end);
  except
    on Exception do Raised := True;
  end;
  Should(Raised).BeTrue;
end;

procedure TDslLinqTests.Aggregate_Accumulates_From_A_Seed;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  // 1 + 2 + ... + 6
  Should(FDb.Orders.Where(O.Id > 0).Aggregate<Integer>(0,
    function(Acc: Integer; Ord: TDlOrder): Integer
    begin
      Result := Acc + Ord.Id;
    end)).Be(21);
end;

procedure TDslLinqTests.ToDictionary_Keys_By_The_Selector;
var
  O: TDlOrder;
  Map: IDictionary<Integer, TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Map := FDb.Orders.Where(O.Id > 0).ToDictionary<Integer>(
    function(Ord: TDlOrder): Integer
    begin
      Result := Ord.Id;
    end);
  Should(Map.Count).Be(6);
  Should(Map[3].Id).Be(3);
end;

procedure TDslLinqTests.ToDictionary_With_Value_Selector;
var
  O: TDlOrder;
  Map: IDictionary<Integer, string>;
begin
  O := Prototype.Entity<TDlOrder>;
  Map := FDb.Orders.Where(O.Id > 0).ToDictionary<Integer, string>(
    function(Ord: TDlOrder): Integer
    begin
      Result := Ord.Id;
    end,
    function(Ord: TDlOrder): string
    begin
      Result := Ord.Status;
    end);
  Should(Map[1]).Be('Open');
  Should(Map[2]).Be('Paid');
end;

procedure TDslLinqTests.ToDictionary_Raises_On_A_Repeated_Key;
var
  O: TDlOrder;
  Raised: Boolean;
begin
  O := Prototype.Entity<TDlOrder>;
  Raised := False;
  try
    // Three customers for six orders: the key repeats
    FDb.Orders.Where(O.Id > 0).ToDictionary<Integer>(
      function(Ord: TDlOrder): Integer
      begin
        Result := Ord.CustomerId;
      end);
  except
    on Exception do Raised := True;
  end;
  Should(Raised).BeTrue;
end;

procedure TDslLinqTests.ThenBy_Accepts_An_Order_Expression;
var
  O: TDlOrder;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  // Open first (ids 5, 3, 1 by descending id), then Paid (6, 4, 2)
  Items := FDb.Orders.Where(O.Id > 0).OrderBy(O.Status.Asc)
    .ThenBy(O.Id.Desc).ToList;
  Should(Items[0].Id).Be(5);
  Should(Items[2].Id).Be(1);
  Should(Items[3].Id).Be(6);
  // ThenByDescending forces the descending direction
  Items := FDb.Orders.Where(O.Id > 0).OrderBy(O.Status.Asc)
    .ThenByDescending(O.Id.Asc).ToList;
  Should(Items[0].Id).Be(5);
  Should(Items[5].Id).Be(2);
end;

procedure TDslLinqTests.OrderBy_Column_Of_The_Joined_Table;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // Customer 3 first (orders 3, 6), then 2 (2, 5), then 1 (1, 4)
  Items := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .OrderBy(C.Name.Desc)
    .ThenBy(O.Id.Asc)
    .ToList;
  Should(Items.Count).Be(6);
  Should(Items[0].Id).Be(3);
  Should(Items[1].Id).Be(6);
  Should(Items[2].Id).Be(2);
  Should(Items[5].Id).Be(4);
end;

procedure TDslLinqTests.OrderBy_Prop_Of_The_Joined_Table;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Items := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .OrderBy<string>(C.Name)
    .ThenByDescending<Integer>(O.Id)
    .ToList;
  // Customer 1: orders 4 then 1 (id descending)
  Should(Items[0].Id).Be(4);
  Should(Items[1].Id).Be(1);
end;

procedure TDslLinqTests.OrderBy_Base_Column_Still_Works_With_A_Join;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Items := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .OrderBy(O.Id.Desc)
    .ToList;
  Should(Items[0].Id).Be(6);
  Should(Items[5].Id).Be(1);
end;

procedure TDslLinqTests.GroupBy_Projects_Key_And_Aggregates_To_A_Dto;
var
  O: TDlOrder;
  Rows: IList<TDlStatusTotal>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .GroupBy(O.Status)
    .OrderBy(O.Status.Asc)
    .Select<TDlStatusTotal>([
      O.Status.&As('Status'),
      Agg.Sum<Currency>(O.Amount).&As('Total'),
      Agg.Count.&As('Cnt')])
    .ToList;
  Should(Rows.Count).Be(2);
  Should(Rows[0].Status).Be('Open');
  Should(Rows[0].Cnt).Be(3);
  Should(Rows[0].Total = 450).BeTrue;
  Should(Rows[1].Status).Be('Paid');
  Should(Rows[1].Cnt).Be(3);
  Should(Rows[1].Total = 600).BeTrue;
end;

procedure TDslLinqTests.Having_Filters_The_Groups;
var
  O: TDlOrder;
  Rows: IList<TDlStatusTotal>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .GroupBy(O.Status)
    .Having(Agg.Sum<Currency>(O.Amount) > 500)
    .Select<TDlStatusTotal>([
      O.Status.&As('Status'),
      Agg.Sum<Currency>(O.Amount).&As('Total'),
      Agg.Count.&As('Cnt')])
    .ToList;
  Should(Rows.Count).Be(1);
  Should(Rows[0].Status).Be('Paid');
  Should(Rows[0].Total = 600).BeTrue;
end;

procedure TDslLinqTests.Where_Applies_Before_The_Grouping;
var
  O: TDlOrder;
  Rows: IList<TDlStatusTotal>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Amount >= 100)
    .GroupBy(O.Status)
    .OrderBy(O.Status.Asc)
    .Select<TDlStatusTotal>([
      O.Status.&As('Status'),
      Agg.Sum<Currency>(O.Amount).&As('Total'),
      Agg.Count.&As('Cnt')])
    .ToList;
  Should(Rows.Count).Be(2);
  Should(Rows[0].Status).Be('Open');
  Should(Rows[0].Cnt).Be(2);
  Should(Rows[0].Total = 400).BeTrue;
  Should(Rows[1].Cnt).Be(3);
  Should(Rows[1].Total = 600).BeTrue;
end;

procedure TDslLinqTests.Aggregates_Without_GroupBy_Return_One_Row;
var
  O: TDlOrder;
  Rows: IList<TDlTotals>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .Select<TDlTotals>([
      Agg.Count.&As('Cnt'),
      Agg.Max<Currency>(O.Amount).&As('Biggest'),
      Agg.Avg<Currency>(O.Amount).&As('Mean')])
    .ToList;
  Should(Rows.Count).Be(1);
  Should(Rows[0].Cnt).Be(6);
  Should(Rows[0].Biggest = 300).BeTrue;
  Should(Rows[0].Mean = 175).BeTrue;
end;

procedure TDslLinqTests.GroupBy_Column_Of_The_Joined_Table;
var
  O: TDlOrder;
  C: TDlCustomer;
  Rows: IList<TDlCityTotal>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .GroupBy(C.City)
    .OrderBy(C.City.Asc)
    .Select<TDlCityTotal>([
      C.City.&As('City'),
      Agg.Sum<Currency>(O.Amount).&As('Total')])
    .ToList;
  Should(Rows.Count).Be(2);
  Should(Rows[0].City).Be('RJ');
  Should(Rows[0].Total = 450).BeTrue;
  Should(Rows[1].City).Be('SP');
  Should(Rows[1].Total = 600).BeTrue;
end;

procedure TDslLinqTests.CountDistinct_Counts_Distinct_Values;
var
  O: TDlOrder;
  Rows: IList<TDlDistinct>;
begin
  O := Prototype.Entity<TDlOrder>;
  Rows := FDb.Orders.Where(O.Id > 0)
    .Select<TDlDistinct>([
      Agg.CountDistinct<Integer>(O.CustomerId).&As('Customers')])
    .ToList;
  Should(Rows.Count).Be(1);
  Should(Rows[0].Customers).Be(3);
end;

procedure TDslLinqTests.Same_Column_Name_In_Two_Tables_Does_Not_Share_The_Cached_SQL;
var
  O: TDlOrder;
  C: TDlCustomer;
  A, B: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // Same shape, same column name (Id) on different tables.
  A := FDb.Orders.Where(C.Id = 1)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id).ToList;
  B := FDb.Orders.Where(O.Id = 1)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id).ToList;
  Should(A.Count).Be(2);
  Should(B.Count).Be(1);
end;

procedure TDslLinqTests.Having_With_Other_Literal_Reuses_The_SQL_And_Refreshes_Params;
var
  O: TDlOrder;
  A, B: IList<TDlStatusTotal>;
begin
  O := Prototype.Entity<TDlOrder>;
  A := FDb.Orders.Where(O.Id > 0).GroupBy(O.Status)
    .Having(Agg.Sum<Currency>(O.Amount) > 500)
    .Select<TDlStatusTotal>([O.Status.&As('Status'),
      Agg.Count.&As('Cnt')]).ToList;
  B := FDb.Orders.Where(O.Id > 0).GroupBy(O.Status)
    .Having(Agg.Sum<Currency>(O.Amount) > 100)
    .Select<TDlStatusTotal>([O.Status.&As('Status'),
      Agg.Count.&As('Cnt')]).ToList;
  Should(A.Count).Be(1);
  Should(B.Count).Be(2);
end;

procedure TDslLinqTests.Aggregates_By_Name_Raise_On_An_Empty_Sequence;
var
  O: TDlOrder;
  Q: TFluentQuery<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  Q := FDb.Orders.Where(O.Id > 999);
  Should(Q.Sum('Amount') = 0).BeTrue;
  Should(
    procedure begin Q.Average('Amount'); end).Throw<Exception>;
  Should(
    procedure begin Q.Min('Amount'); end).Throw<Exception>;
  Should(
    procedure begin Q.Max('Amount'); end).Throw<Exception>;
end;

procedure TDslLinqTests.MaxOrDefault_Returns_The_Default_On_An_Empty_Sequence;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.Id > 999).MaxOrDefault('Amount', -1) = -1).BeTrue;
  Should(FDb.Orders.Where(O.Id > 0).MaxOrDefault('Amount', -1) = 300).BeTrue;
end;

procedure TDslLinqTests.Aggregates_By_Name_With_Take_Use_The_Paged_Rows;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  // LINQ: Orders.Take(2).Sum(...) adds the two rows, not the whole table
  Should(FDb.Orders.Where(O.Id > 0).OrderBy(O.Id.Asc).Take(2)
    .Sum('Amount') = 150).BeTrue;
end;

procedure TDslLinqTests.Aggregates_By_Name_Respect_The_Join_Filter;
var
  O: TDlOrder;
  C: TDlCustomer;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // Customers 1 and 2 live in SP: orders 1,2,4,5 = 50+100+200+250
  Should(FDb.Orders.Where(C.City = 'SP')
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .Sum('Amount') = 600).BeTrue;
end;

procedure TDslLinqTests.In_Subquery_Filters_By_The_Values_Of_Another_Entity;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // LINQ: customers.Where(c => c.City == "SP").Select(c => c.Id)
  //         .Contains(o.CustomerId)
  Items := FDb.Orders.Where(
    O.CustomerId.&In(FDb.Customers.Where(C.City = 'SP').Subquery(C.Id)))
    .OrderBy(O.Id.Asc).ToList;
  Should(Items.Count).Be(4);
  Should(Items[0].Id).Be(1);
  Should(Items[3].Id).Be(5);
end;

procedure TDslLinqTests.NotIn_Subquery_Is_The_Complement;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Items := FDb.Orders.Where(
    O.CustomerId.NotIn(FDb.Customers.Where(C.City = 'SP').Subquery(C.Id)))
    .ToList;
  Should(Items.Count).Be(2);
end;

procedure TDslLinqTests.Correlated_Exists_Uses_The_Outer_Row;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlCustomer>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // LINQ: customers.Where(c => orders.Any(o => o.CustomerId == c.Id
  //                                            && o.Amount > 250))
  Items := FDb.Customers.Where(
    FDb.Orders.Where((O.CustomerId = C.Id) and (O.Amount > 250)).Exists)
    .ToList;
  Should(Items.Count).Be(1);
  Should(Items[0].Id).Be(3);
end;

procedure TDslLinqTests.Correlated_NotExists_Is_The_Complement;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlCustomer>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Items := FDb.Customers.Where(
    FDb.Orders.Where((O.CustomerId = C.Id) and (O.Amount > 250)).NotExists)
    .ToList;
  Should(Items.Count).Be(2);
end;

procedure TDslLinqTests.Subquery_Params_Continue_The_Numbering_Of_The_Outer_Query;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  // outer literal (100) + subquery literal ('SP'): orders 2, 4 and 5
  Items := FDb.Orders.Where((O.Amount >= 100) and
    O.CustomerId.&In(FDb.Customers.Where(C.City = 'SP').Subquery(C.Id)))
    .ToList;
  Should(Items.Count).Be(3);
end;

procedure TDslLinqTests.Subquery_With_Other_Literals_Reuses_The_Cache_And_Refreshes;
var
  O: TDlOrder;
  C: TDlCustomer;
  A, B: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  A := FDb.Orders.Where((O.Amount >= 100) and
    O.CustomerId.&In(FDb.Customers.Where(C.City = 'SP').Subquery(C.Id)))
    .ToList;
  B := FDb.Orders.Where((O.Amount >= 250) and
    O.CustomerId.&In(FDb.Customers.Where(C.City = 'RJ').Subquery(C.Id)))
    .ToList;
  Should(A.Count).Be(3);
  // customer 3 (RJ): orders 3 (150) and 6 (300); only 6 is >= 250
  Should(B.Count).Be(1);
  Should(B[0].Id).Be(6);
end;

procedure TDslLinqTests.Subquery_Works_Inside_A_Query_With_A_Join;
var
  O: TDlOrder;
  C: TDlCustomer;
  Items: IList<TDlOrder>;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Items := FDb.Orders.Where(O.Id > 0)
    .JoinInner<TDlCustomer>('c', O.CustomerId = C.Id)
    .Where(O.CustomerId.&In(FDb.Customers.Where(C.City = 'RJ').Subquery(C.Id)))
    .ToList;
  Should(Items.Count).Be(2);
end;

procedure TDslLinqTests.ToUpper_And_ToLower_Compare_Ignoring_Case;
var
  C: TDlCustomer;
begin
  C := Prototype.Entity<TDlCustomer>;
  Should(FDb.Customers.Where(C.Name.ToUpper = 'CUSTOMER 1').Count).Be(1);
  Should(FDb.Customers.Where(C.City.ToLower = 'sp').Count).Be(2);
  Should(FDb.Customers.Where(C.City.ToLower = 'SP').Count).Be(0);
end;

procedure TDslLinqTests.Len_Counts_The_Characters;
var
  C: TDlCustomer;
begin
  C := Prototype.Entity<TDlCustomer>;
  Should(FDb.Customers.Where(C.Name.Len = 10).Count).Be(3);
  Should(FDb.Customers.Where(C.City.Len = 2).Count).Be(3);
  Should(FDb.Customers.Where(C.Name.Len > 10).Count).Be(0);
end;

procedure TDslLinqTests.Substring_Uses_A_Zero_Based_Index;
var
  C: TDlCustomer;
begin
  C := Prototype.Entity<TDlCustomer>;
  // LINQ: c.Name.Substring(0, 8) == "Customer"
  Should(FDb.Customers.Where(C.Name.Substring(0, 8) = 'Customer').Count).Be(3);
  // "Customer 3": index 9 is the digit
  Should(FDb.Customers.Where(C.Name.Substring(9, 1) = '3').Count).Be(1);
  Should(FDb.Customers.Where(C.Name.Substring(0, 4) = 'Cust').Count).Be(3);
end;

procedure TDslLinqTests.Trim_Removes_The_Blanks_Around;
var
  C: TDlCustomer;
  X: TDlCustomer;
begin
  X := TDlCustomer.Create;
  X.Id := 9;
  X.Name := '  Zed  ';
  X.City := 'SP';
  FDb.Customers.Add(X);
  FDb.SaveChanges;
  C := Prototype.Entity<TDlCustomer>;
  Should(FDb.Customers.Where(C.Name.Trim = 'Zed').Count).Be(1);
  Should(FDb.Customers.Where(C.Name = 'Zed').Count).Be(0);
end;

procedure TDslLinqTests.Year_Month_Day_Extract_The_Parts_Of_The_Date;
var
  O: TDlOrder;
begin
  O := Prototype.Entity<TDlOrder>;
  Should(FDb.Orders.Where(O.CreatedAt.Year = 2025).Count).Be(3);
  Should(FDb.Orders.Where(O.CreatedAt.Month = 2).Count).Be(1);
  Should(FDb.Orders.Where(O.CreatedAt.Day = 15).Count).Be(6);
  Should(FDb.Orders.Where(O.CreatedAt.Year = 2024).Count).Be(3);
end;

procedure TDslLinqTests.Function_Result_Can_Be_Combined_With_Other_Conditions;
var
  O: TDlOrder;
  C: TDlCustomer;
begin
  O := Prototype.Entity<TDlOrder>;
  C := Prototype.Entity<TDlCustomer>;
  Should(FDb.Orders.Where((O.CreatedAt.Year = 2024) and
    (O.CreatedAt.Month >= 2)).Count).Be(2);
  // inside a subquery too: customers with an order in 2025
  Should(FDb.Customers.Where(FDb.Orders.Where(
    (O.CustomerId = C.Id) and (O.CreatedAt.Year = 2025)).Exists).Count).Be(3);
  Should(FDb.Customers.Where(FDb.Orders.Where(
    (O.CustomerId = C.Id) and (O.CreatedAt.Month = 6)).Exists).Count).Be(1);
end;

end.
