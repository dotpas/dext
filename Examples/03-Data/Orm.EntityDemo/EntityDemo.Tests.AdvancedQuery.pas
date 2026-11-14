unit EntityDemo.Tests.AdvancedQuery;

interface

uses
  System.SysUtils, Dext.Entity, Dext.Entity.Query,
  Dext.Collections, // Add Collections unit
  Dext.Entity.Grouping, Dext.Entity.Joining,
  Dext.Specifications.Interfaces, Dext.Specifications.Fluent, Dext.Specifications.Types,
  EntityDemo.Entities, EntityDemo.Tests.Base,
  // NEW:
  Dext.Entity.TypeSystem,
  EntityDemo.Entities.Info;

type
  TAdvancedQueryTest = class(TBaseTest)
  public
    procedure Run; override;
    procedure TestAggregations;
    procedure TestDistinct;
    procedure TestPagination;
    procedure TestGroupBy;
    procedure TestJoin;
    procedure TestInclude;
    procedure TestSelectOptimized;
    procedure TestFluentSyntax;
    procedure TestTypeSafeQuery; // New Test
    procedure TestStringExpressions; // Even Newer Test
  end;

implementation

uses
  EntityDemo.DbConfig;

procedure TAdvancedQueryTest.Run;
begin
  Log('🧪 Running Advanced Query Tests...');
  TestAggregations;
  TestDistinct;
  TestPagination;
  TestGroupBy;
  TestJoin;
  TestInclude;
  TestSelectOptimized;
  TestTypeSafeQuery;
  TestStringExpressions;

  Log('');
end;

procedure TAdvancedQueryTest.TestSelectOptimized;
var
  Users: IList<TUser>; // Changed to IList
  Spec: ISpecification<TUser>;
  Builder: TSpecificationBuilder<TUser>;
  U: TUser;
  Addr: TAddress;
begin
  Log('   Testing Select Optimized (Projections)...');
  TearDown;
  Setup;

  // Create dummy address
  Addr := TAddress.Create;
  Addr.Street := 'Proj St';
  Addr.City := 'Proj City';
  FContext.Entities<TAddress>.Add(Addr);
  FContext.SaveChanges;

  // Insert user with Name and Age
  U := TUser.Create;
  U.Name := 'John Doe';
  U.Age := 30;
  U.City := 'New York';
  U.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U);
  FContext.SaveChanges;

  // Select only Name
  Builder := Specification.All<TUser>;
  // Usa class operator TPropExpression.Implicit(const Value: TPropExpression): string
  Spec := Builder.Select(TUserType.Name);

  Users := FContext.Entities<TUser>.ToList(Spec);
  // No try..finally needed for Users, it's ARC managed
  AssertTrue(Users.Count = 1, 'Should find 1 user', Format('Found %d', [Users.Count]));
  AssertTrue(Users[0].Name = 'John Doe', 'Name should be loaded', Format('Found "%s"', [Users[0].Name]));
  // Age should be default (0) because it wasn't selected
  AssertTrue(Users[0].Age = 0, 'Age should be 0 (not loaded)', Format('Found %d', [Users[0].Age]));
  // City should be default ('')
  AssertTrue(Users[0].City = '', 'City should be empty (not loaded)', Format('Found "%s"', [Users[0].City]));
end;

procedure TAdvancedQueryTest.TestAggregations;
var
  UsersQuery: TFluentQuery<TUser>;
  Count: Integer;
  SumAge: Double;
  AvgAge: Double;
  MinAge, MaxAge: Double;
  Addr: TAddress;
  U1, U2, U3: TUser;
begin
  Log('   Testing Aggregations...');

  // Setup Data
  Addr := TAddress.Create;
  Addr.Street := 'Agg St';
  Addr.City := 'Agg City';
  FContext.Entities<TAddress>.Add(Addr);
  FContext.SaveChanges;

  U1 := TUser.Create;
  U1.Name := 'A';
  U1.Age := 10;
  U1.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U1);
  U2 := TUser.Create;
  U2.Name := 'B';
  U2.Age := 20;
  U2.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U2);
  U3 := TUser.Create;
  U3.Name := 'C';
  U3.Age := 30;
  U3.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U3);
  FContext.SaveChanges;

  UsersQuery := FContext.Entities<TUser>.QueryAll;
  // Count
  Count := UsersQuery.Count;
  AssertTrue(Count = 3, 'Count should be 3', Format('Count was %d', [Count]));

  // Sum
  SumAge := UsersQuery
    .Sum(TFunc<TUser, Double>(function(U: TUser): Double
     begin
       Result := U.Age;
     end));
  AssertTrue(Abs(SumAge - 60) < 0.001, 'Sum Age should be 60', Format('Sum was %f', [SumAge]));

  // Average
  AvgAge := UsersQuery.Average(
    TFunc<TUser, Double>(function(U: TUser): Double
    begin
      Result := U.Age;
    end));
  AssertTrue(Abs(AvgAge - 20) < 0.001, 'Avg Age should be 20', Format('Avg was %f', [AvgAge]));

  // Min/Max
  MinAge := UsersQuery.Min(
    TFunc<TUser, Double>(function(U: TUser): Double
    begin
      Result := U.Age;
    end));

  MaxAge := UsersQuery.Max(
    TFunc<TUser, Double>(function(U: TUser): Double
    begin
      Result := U.Age;
    end));

  AssertTrue(Abs(MinAge - 10) < 0.001, 'Min Age should be 10', Format('Min was %f', [MinAge]));
  AssertTrue(Abs(MaxAge - 30) < 0.001, 'Max Age should be 30', Format('Max was %f', [MaxAge]));

  // Any
  AssertTrue(UsersQuery.Any, 'Any should be true', 'Any was false');
  AssertTrue(UsersQuery.Any(
    TPredicate<TUser>(function(U: TUser): Boolean
    begin
      Result := U.Age > 25;
    end)),
    'Any(Age > 25) should be true', 'Any(...) was false');

  AssertTrue(not UsersQuery.Any(
    TPredicate<TUser>(function(U: TUser): Boolean
    begin
      Result := U.Age > 100;
    end)),
    'Any(Age > 100) should be false', 'Any(...) was true');
end;

procedure TAdvancedQueryTest.TestDistinct;
var
  UsersQuery: TFluentQuery<TUser>;
  CitiesQuery: TFluentQuery<string>;
  DistinctCities: IList<string>; // Changed to IList
  Addr: TAddress;
  U4, U5, U6: TUser;
begin
  Log('   Testing Distinct...');

  // Create dummy address
  Addr := TAddress.Create;
  Addr.Street := 'Dist St';
  Addr.City := 'Dist City';
  FContext.Entities<TAddress>.Add(Addr);
  FContext.SaveChanges;

  // Let's add users with duplicate cities
  U4 := TUser.Create;
  U4.Name := 'D';
  U4.City := 'New York';
  U4.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U4);

  U5 := TUser.Create;
  U5.Name := 'E';
  U5.City := 'New York';
  U5.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U5);

  U6 := TUser.Create;
  U6.Name := 'F';
  U6.City := 'London';
  U6.AddressId := Addr.Id;
  FContext.Entities<TUser>.Add(U6);
  FContext.SaveChanges;

  // Project to City then Distinct
  UsersQuery := FContext.Entities<TUser>.QueryAll;
  // Note: Users is passed as parent to the fluent chain, so it will be freed when Cities is freed.

  CitiesQuery := UsersQuery
    .Where(TPredicate<TUser>(function(U: TUser): Boolean
      begin
        Result := U.City <> '';
      end))
    .Select<string>(TFunc<TUser, string>(function(U: TUser): string
      begin
        Result := U.City;
      end))
    .Distinct;

  DistinctCities := CitiesQuery.ToList;
  // No try..finally
  AssertTrue(DistinctCities.Count = 2,
    'Should have 2 distinct cities (New York, London)', Format('Found %d', [DistinctCities.Count]));
  AssertTrue(DistinctCities.Contains('New York'), 'Should contain New York',
    'Missing New York');
  AssertTrue(DistinctCities.Contains('London'), 'Should contain London',
    'Missing London');
end;

procedure TAdvancedQueryTest.TestPagination;
var
  Paged: IPagedResult<TUser>;
  i: Integer;
  Addr: TAddress;
  U: TUser;
  Query: TFluentQuery<TUser>;
begin
  Log('   Testing Pagination...');

  // Create dummy address
  Addr := TAddress.Create;
  Addr.Street := 'Page St';
  Addr.City := 'Page City';
  FContext.Entities<TAddress>.Add(Addr);
  FContext.SaveChanges;

  // We have 6 users now (3 from Aggregations + 3 from Distinct)
  // Let's add 4 more to make 10
  for i := 7 to 10 do
  begin
    U := TUser.Create;
    U.Name := 'User' + i.ToString;
    U.AddressId := Addr.Id;
    FContext.Entities<TUser>.Add(U);
  end;
  FContext.SaveChanges;

  Query := FContext.Entities<TUser>.QueryAll;
  // Page 1 of 3 (Size 3) -> 10 items total -> 4 pages (3, 3, 3, 1)
  Paged := Query.Paginate(1, 3);
  AssertTrue(Paged.TotalCount = 10, 'TotalCount should be 10', Format('TotalCount: %d', [Paged.TotalCount]));
  AssertTrue(Paged.PageCount = 4, 'PageCount should be 4', Format('PageCount: %d', [Paged.PageCount]));
  AssertTrue(Paged.Items.Count = 3, 'Page 1 should have 3 items', Format('Items: %d', [Paged.Items.Count]));
  AssertTrue(Paged.HasNextPage, 'Should have next page', 'No next page');
  AssertTrue(not Paged.HasPreviousPage, 'Should not have prev page', 'Has prev page');

// Page 4 (Last page)
  Paged := Query.Paginate(4, 3);
  AssertTrue(Paged.Items.Count = 1, 'Page 4 should have 1 item', Format('Items: %d', [Paged.Items.Count]));
  AssertTrue(not Paged.HasNextPage, 'Should not have next page', 'Has next page');
  AssertTrue(Paged.HasPreviousPage, 'Should have prev page', 'No prev page');
end;

procedure TAdvancedQueryTest.TestGroupBy;
var
  Grouped: TFluentQuery<IGrouping<string, TUser>>;
  GroupsList: IList<IGrouping<string, TUser>>; // Changed to IList
  Group: IGrouping<string, TUser>;
  UsersQuery: TFluentQuery<TUser>;
  Count: Integer;
  U: TUser;
begin
  Log('   Testing GroupBy...');

  // We have users with cities: New York (2), London (1), and others empty/null.
  // U4, U5 -> New York
  // U6 -> London

  UsersQuery := FContext.Entities<TUser>.QueryAll;

  // Use the TQuery.GroupBy function
  Grouped := TQuery.GroupBy<TUser, string>(UsersQuery.Where(
    TPredicate<TUser>(function(U: TUser): Boolean
    begin
      Result := U.City <> '';
    end)),
    TFunc<TUser, string>(function(U: TUser): string
    begin
      Result := U.City;
    end));

  GroupsList := Grouped.ToList;
  // No try..finally
  AssertTrue(GroupsList.Count = 2, 'Should have 2 groups', Format('Found %d',
    [GroupsList.Count]));

  for Group in GroupsList do
  begin
    if Group.Key = 'New York' then
    begin
     // Count items in group
      Count := 0;
      for U in Group do
        Inc(Count);
      AssertTrue(Count = 2, 'New York group should have 2 users', Format('Found %d', [Count]));
    end
    else if Group.Key = 'London' then
    begin
      Count := 0;
      for U in Group do
        Inc(Count);
      AssertTrue(Count = 1, 'London group should have 1 user', Format('Found %d',
        [Count]));
    end
    else
      AssertTrue(False, 'Unexpected group key', Group.Key);
  end;
end;

procedure TAdvancedQueryTest.TestJoin;
begin
  Log('   Testing Join... (SKIPPED)');
end;

procedure TAdvancedQueryTest.TestInclude;
var
  Users: IList<TUser>; // Changed to IList
  U1, U2: TUser;
  A1, A2: TAddress;
  Spec: ISpecification<TUser>;
  Builder: TSpecificationBuilder<TUser>;
  Streets: string;
begin
  Log('   Testing Include (Eager Loading)...');

  // Reset context
  TearDown;
  Setup;

  // Setup data: Create addresses first
  A1 := TAddress.Create;
  A1.Street := 'Main Street';
  A1.City := 'New York';
  FContext.Entities<TAddress>.Add(A1);

  A2 := TAddress.Create;
  A2.Street := 'Second Avenue';
  A2.City := 'Los Angeles';
  FContext.Entities<TAddress>.Add(A2);
  FContext.SaveChanges;

  // Create users with addresses
  U1 := TUser.Create;
  U1.Name := 'John';
  U1.AddressId := A1.Id;
  FContext.Entities<TUser>.Add(U1);

  U2 := TUser.Create;
  U2.Name := 'Jane';
  U2.AddressId := A2.Id;
  FContext.Entities<TUser>.Add(U2);
  FContext.SaveChanges;

  // Test: Load users with Include('Address') and OrderBy to ensure stable results
  Builder := Specification.All<TUser>;
  Spec := Builder.Include(TUserType.Address)
                 .OrderBy(TUserType.Id);
  Users := FContext.Entities<TUser>.ToList(Spec);

  // No try..finally
  AssertTrue(Users.Count = 2, 'Should have 2 users', Format('Found %d', [Users.Count]));

  // Verify that Address navigation property is loaded for both users.
  // Do not assume deterministic row order from provider.
  if Users.Count >= 2 then
  begin
    AssertTrue(Users[0].Address <> nil, 'User 1 Address should be loaded',
      'User 1 Address is nil');
    AssertTrue(Users[1].Address <> nil, 'User 2 Address should be loaded',
      'User 2 Address is nil');

    Streets := '';
    if Users[0].Address <> nil then
      Streets := Streets + '|' + Users[0].Address.Street + '|';
    if Users[1].Address <> nil then
      Streets := Streets + '|' + Users[1].Address.Street + '|';

    AssertTrue(
      Streets.Contains('|Main Street|') and Streets.Contains('|Second Avenue|'),
      'Both expected streets should be present',
      Format('Found: %s', [Streets]));
  end;
end;

procedure TAdvancedQueryTest.TestFluentSyntax;
begin
  Log('   Testing Fluent Syntax Overloads... (SKIPPED)');
end;

procedure TAdvancedQueryTest.TestTypeSafeQuery;
var
  Users: IList<TUser>;
  U: TUser;
  Query: TFluentQuery<TUser>;
begin
  Log('   Testing Type-Safe Query (TUserType)...');
  TearDown;
  Setup;

  U := TUser.Create;
  U.Name := 'TypeSafe User';
  U.Age := 25;
  FContext.Entities<TUser>.Add(U);
  FContext.SaveChanges;

  // Syntax Goal: Where(TUserType.Age > 18)
  // TUserType.Age is TProp<Integer>
  // > 18 invokes TProp<Integer>.GreaterThan(..., 18) -> TExpression
  // Where(...) takes ISpecification or IExpression (via implicit?)
  // TFluentQuery.Where(Expression) exists.

  Query := FContext.Entities<TUser>.QueryAll
    .Where(TUserType.Age > 18);
  // Oracle has no empty string (it is NULL): Name <> '' is never true there,
  // so the test asks for a name with IS NOT NULL instead.
  if TDbConfig.GetProvider = dpOracle then
    Query := Query.Where(TUserType.Name.IsNotNull)
  else
    Query := Query.Where(TUserType.Name <> '');
    //.Where(TUserType.Age > 18)
    //.Where(TUserType.Name <> '');

    // Note: TProp<string> operators need to support <> ''
    // And implicit convert TProp<T> expression result (TPropExpression.TExpression) to IExpression interface

  Users := Query.ToList;

  AssertTrue(Users.Count = 1, 'Should find 1 user', Format('Found %d', [Users.Count]));
  AssertTrue(Users[0].Age = 25, 'Age should be 25', Format('Found %d', [Users[0].Age]));
end;

procedure TAdvancedQueryTest.TestStringExpressions;
var
  Users: IList<TUser>;
begin
  Log('   Testing String-Based Expressions (".Where(''Age'' > 18)")...');
  // NOTE: This uses the new TPropExpression.Implicit(string) operator

  TearDown;
  Setup;

  FContext.Entities<TUser>
    .Add(TUser.Create('Kid', 10))
    .Add(TUser.Create('Adult', 25));
  FContext.SaveChanges;

  // Test 1: Basic string literal comparison
  Users := FContext.Entities<TUser>.QueryAll
    .Where(Prop('Age') > 18)
    .ToList;

  AssertTrue(Users.Count = 1, 'String expression Age > 18 passed', Format('Found %d', [Users.Count]));
  AssertTrue(Users[0].Name = 'Adult', 'Expected Adult', Users[0].Name);

  // Test 2: Complex string literal comparison
  Users := FContext.Entities<TUser>.QueryAll
    .Where((Prop('Age') > 10) and (Prop('Name') = 'Adult'))
    .ToList;

  AssertTrue(Users.Count = 1, 'Complex string expression passed', Format('Found %d', [Users.Count]));

  // Test 3: String literal with LIKE
  Users := FContext.Entities<TUser>.QueryAll
    .Where(Prop('Name').StartsWith('Ad'))
    .ToList;
  AssertTrue(Users.Count = 1, 'TPropExpression.Create passed', Format('Found %d', [Users.Count]));

  // Test 4: Implicit string with property name verification
  // The framework should map 'Name' to 'full_name' column automatically because of RTTI
  Users := FContext.Entities<TUser>.QueryAll
    .Where(Prop('Name') = 'Kid')
    .ToList;
  AssertTrue(Users.Count = 1, 'Mapping "Name" string to "full_name" column passed', Format('Found %d', [Users.Count]));

  LogSuccess('   ✓ String-based expressions working correctly!');
end;

end.
