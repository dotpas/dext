unit EntityDemo.Tests.ExplicitLoading;

interface

uses
  EntityDemo.Tests.Base,
  System.SysUtils;

type
  TExplicitLoadingTest = class(TBaseTest)
  public
    procedure Run; override;
    procedure TestReferenceLoading;
    procedure TestCollectionLoading;
  end;

implementation

uses
  EntityDemo.Entities;

procedure TExplicitLoadingTest.Run;
begin
  Log('🧪 Running Explicit Loading Tests...');
  TestReferenceLoading;
  TestCollectionLoading;
  Log('');
end;

procedure TExplicitLoadingTest.TestReferenceLoading;
var
  U: TUser;
  A: TAddress;
begin
  Log('   Testing Reference Loading (User.Address)...');
  TearDown;
  Setup;

  // Create Address
  A := TAddress.Create;
  A.Street := 'Main St';
  FContext.Entities<TAddress>.Add(A);
  FContext.SaveChanges;

  // Create User linked to Address
  U := TUser.Create;
  U.Name := 'John';
  U.AddressId := A.Id;
  FContext.Entities<TUser>.Add(U);
  FContext.SaveChanges;

  // U was created in code and is tracked: its Address is a Lazy reference,
  // so reading it would also load it. Explicit Load does it on demand.
  FContext.Entry(U).Reference('Address').Load;

  AssertTrue(U.Address <> nil, 'Address should be loaded', 'Address is nil');
  if U.Address <> nil then
    AssertTrue(U.Address.Street = 'Main St', 'Address Street match', Format('Found %s', [U.Address.Street]));
end;

procedure TExplicitLoadingTest.TestCollectionLoading;
var
  A: TAddress;
  U1, U2: TUser;
begin
  Log('   Testing Collection Loading (Address.Users)...');
  TearDown;
  Setup;

  // Create Address
  A := TAddress.Create;
  A.Street := 'Broadway';
  FContext.Entities<TAddress>.Add(A);
  FContext.SaveChanges;

  // Create Users linked to Address
  U1 := TUser.Create; U1.Name := 'User 1'; U1.AddressId := A.Id; FContext.Entities<TUser>.Add(U1);
  U2 := TUser.Create; U2.Name := 'User 2'; U2.AddressId := A.Id; FContext.Entities<TUser>.Add(U2);
  FContext.SaveChanges;

  // A.Users should be empty
  AssertTrue(A.Users.Count = 0, 'Users list should be empty initially', Format('Count: %d', [A.Users.Count]));

  // Explicit Load
  FContext.Entry(A).Collection('Users').Load;

  AssertTrue(A.Users.Count = 2, 'Should load 2 users', Format('Count: %d', [A.Users.Count]));
  // Order is not guaranteed, but usually insertion order
  // We can check contains or just count for now.
end;

end.
