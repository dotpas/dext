unit EntityDemo.Tests.TypeSystem;

interface

uses
  System.SysUtils, Dext.Entity, Dext.Entity.Query,
  Dext.Collections, Dext.Entity.TypeSystem,
  Dext.Specifications.Interfaces, Dext.Specifications.Types, Dext.Specifications.Fluent,
  EntityDemo.Entities, EntityDemo.Tests.Base, EntityDemo.Entities.Info;

type
  TTypeSystemTest = class(TBaseTest)
  public
    procedure Run; override;
    procedure TestComplexQueries;
    procedure TestPropertyMetaAccess;
    procedure TestChicFluentAdd;
    procedure TestCollectionIntegration;
  end;

implementation

uses
  EntityDemo.DbConfig;

procedure TTypeSystemTest.Run;
begin
  Log('🧪 Running TypeSystem Core Tests...');
  TestPropertyMetaAccess;
  TestComplexQueries;
  TestChicFluentAdd;
  TestCollectionIntegration;
  Log('');
end;

procedure TTypeSystemTest.TestPropertyMetaAccess;
var
  U: TUser;
  Meta: TPropertyInfo;
begin
  Log('   Testing RTTI Access via TPropertyInfo...');
  U := TUser.Create;
  try
    U.Name := 'Test User';
    U.Age := 42;

    // TUserType.Name is TProp<string>, and Meta is TPropertyInfo
    Meta := TUserType.Name.Info;
    AssertTrue(Meta.GetValue(U).AsString = 'Test User', 'RTTI GetValue(Name) working');

    Meta := TUserType.Age.Info;
    AssertTrue(Meta.GetValue(U).AsInteger = 42, 'RTTI GetValue(Age) working');

    Meta.SetValue(U, 50);
    AssertTrue(U.Age = 50, 'RTTI SetValue(Age) working');
  finally
    U.Free;
  end;
end;

procedure TTypeSystemTest.TestComplexQueries;
var
  Users: IList<TUser>;
begin
  Log('   Testing Complex Query Combinations...');
  TearDown;
  Setup;

  // Setup Data
  FContext.Entities<TUser>
    .Add(TUser.Create('Alice', 20)) // NY
    .Add(TEntityType<TUser>.Construct(procedure(B: IEntityBuilder<TUser>) begin B.Prop(TUserType.Name, 'Bob').Prop(TUserType.Age, 30).Prop(TUserType.City, 'NY'); end))
    .Add(TUser.Create('Charlie', 40)); // LA (default)
  FContext.SaveChanges;
  FContext.Entities<TUser>[2].City := 'LA'; // Fix Charlie's city
  FContext.SaveChanges;

  // Test 1: Multiple AND conditions (Strongly Typed)
  Users := FContext.Entities<TUser>.QueryAll
    .Where((TUserType.Age > 25) and (TUserType.City = 'NY'))
    .ToList;
  AssertTrue(Users.Count = 1, 'Only Bob should match');
  AssertTrue(Users[0].Name = 'Bob', 'Expected Bob');

  // Test 2: OR condition
  Users := FContext.Entities<TUser>.QueryAll
    .Where((TUserType.Name = 'Alice') or (TUserType.Name = 'Charlie'))
    .ToList;
  AssertTrue(Users.Count = 2, 'Alice and Charlie should match');

  // Test 3: Like and StartsWith
  Users := FContext.Entities<TUser>.QueryAll
    .Where(TUserType.Name.StartsWith('Ali'))
    .ToList;
  AssertTrue(Users.Count = 1, 'Alice matches');

  // Test 4: IsNull / IsNotNull (City check)
  Users := FContext.Entities<TUser>.QueryAll
    .Where(TUserType.City.IsNotNull)
    .ToList;
  // Oracle stores an empty string as NULL: Alice (no city) has none there.
  if TDbConfig.GetProvider = dpOracle then
    AssertTrue(Users.Count = 2, 'Bob and Charlie have a city (Oracle: empty = NULL)')
  else
    AssertTrue(Users.Count >= 3, 'All users have city');

  // Test 5: OrderBy via TypeSystem
  Users := FContext.Entities<TUser>.QueryAll
    .OrderBy(TUserType.Age.Desc)
    .ToList;
  AssertTrue(Users[0].Age = 40, 'Charlie should be first (desc)');
end;

procedure TTypeSystemTest.TestChicFluentAdd;
var
  SimpleUserBuilder: TFunc<string, Integer, TUser>;
  MetaUserBuilder: TFunc<string, Integer, TUser>;
begin
  Log('   Testing "Chic" Fluent Add syntax...');
  TearDown;
  Setup;

  // Syntax 1: Fluent Chaining (Using conventional objects)
  FContext.Entities<TUser>
    .Add(TUser.Create('Alice', 20))
    .Add(TUser.Create('Bob', 30));

  // Syntax 2: Functional Builder (Using .Prop rename and static Create)
  FContext.Entities<TUser>
    .Add(TEntityType<TUser>.Construct(procedure(B: IEntityBuilder<TUser>)
      begin
        B.Prop(TUserType.Name, 'Charlie').Prop(TUserType.Age, 40);
      end))
    .Add(function(B: IEntityBuilder<TUser>): TUser
      begin
        // Cast-free option using New
        Result := TEntityType<TUser>.New
          .Prop(TUserType.Name, 'David')
          .Prop(TUserType.Age, 50)
          .Build;
      end);

  // Syntax 3: "Local Factory" Pattern (Manual version)
  SimpleUserBuilder := function(AName: string; AAge: Integer): TUser
    begin
       Result := TUser.Create;
       Result.Name := AName;
       Result.Age := AAge;
    end;

  // Syntax 4: "Metadata Factory" (Power version using TypeSystem)
  MetaUserBuilder := function(AName: string; AAge: Integer): TUser
    begin
       Result := TEntityType<TUser>.Construct(procedure(B: IEntityBuilder<TUser>)
         begin
           B.Prop(TUserType.Name, AName).Prop(TUserType.Age, AAge);
         end);
    end;

  FContext.Entities<TUser>
    .Add(SimpleUserBuilder('Eve', 60))
    .Add(MetaUserBuilder('Frank', 70));

  FContext.SaveChanges;

  AssertTrue(FContext.Entities<TUser>.Count(Specification.All<TUser>.Expression) = 6, 'Should have 6 users');
end;

procedure TTypeSystemTest.TestCollectionIntegration;
var
  List: IList<TUser>;
  Filtered: IList<TUser>;
begin
  Log('   Testing Chic Expressions on in-memory IList<T>...');
  List := TCollections.CreateList<TUser>(True); // List owns objects
  try
    List.Add(TUser.Create('Alice', 20));
    List.Add(TUser.Create('Bob', 30));
    List.Add(TUser.Create('Charlie', 40));

    // Using the same "Chic" syntax on in-memory list!
    Filtered := List.Where((TUserType.Age > 25) and (TUserType.Name.StartsWith('B')));

    AssertTrue(Filtered.Count = 1, 'Should find only Bob');
    AssertTrue(Filtered[0].Name = 'Bob', 'Expected Bob from list');

    // Test Any/All on list
    AssertTrue(List.Any(TUserType.Age = 40), 'Charlie should be there');
    AssertTrue(not List.All(TUserType.Age < 30), 'Not everyone is under 30');
  finally
    List := nil; // Free list and all objects
  end;
end;

end.
