unit Dext.Entity.Inheritance.Tests;

{***************************************************************************}
{  Regression: table-per-hierarchy (TPH).                                   }
{                                                                           }
{  Before: with attributes each subclass got its own table and the         }
{  discriminator was ignored. With the fluent API the INSERT wrote the     }
{  discriminator, but CREATE TABLE had neither the column nor the columns  }
{  of the subclasses, a query on the root set returned nothing, a query    }
{  on a subclass set failed with "Field 'Tipo' not found", and queries on   }
{  two types of the hierarchy shared one cached SQL text.                  }
{***************************************************************************}

interface

uses
  System.SysUtils,
  System.Variants,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Collections,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Mapping,
  Dext.Entity.Setup,
  Dext.Entity.Drivers.Interfaces,
  FireDAC.Phys.SQLite;

type
  // Hierarchy mapped with attributes
  [Table('docs_attr'), Inheritance(TInheritanceStrategy.TablePerHierarchy),
   DiscriminatorColumn('Kind')]
  TDocA = class
  private
    FId: Integer;
    FNumber: StringType;
  public
    [PrimaryKey, AutoInc]
    property Id: Integer read FId write FId;
    property Number: StringType read FNumber write FNumber;
  end;

  [DiscriminatorValue('SERVICE')]
  TDocServiceA = class(TDocA)
  private
    FServiceCode: StringType;
  public
    property ServiceCode: StringType read FServiceCode write FServiceCode;
  end;

  [DiscriminatorValue('PRODUCT')]
  TDocProductA = class(TDocA)
  private
    FWeight: Double;
  public
    property Weight: Double read FWeight write FWeight;
  end;

  TDocAttrDb = class(TDbContext)
  private
    function GetDocs: IDbSet<TDocA>;
    function GetServices: IDbSet<TDocServiceA>;
    function GetProducts: IDbSet<TDocProductA>;
  public
    property Docs: IDbSet<TDocA> read GetDocs;
    property Services: IDbSet<TDocServiceA> read GetServices;
    property Products: IDbSet<TDocProductA> read GetProducts;
  end;

  // The same hierarchy mapped with the fluent API
  TDocF = class
  private
    FId: Integer;
    FNumber: StringType;
  public
    property Id: Integer read FId write FId;
    property Number: StringType read FNumber write FNumber;
  end;

  TDocServiceF = class(TDocF)
  private
    FServiceCode: StringType;
  public
    property ServiceCode: StringType read FServiceCode write FServiceCode;
  end;

  TDocProductF = class(TDocF)
  private
    FWeight: Double;
  public
    property Weight: Double read FWeight write FWeight;
  end;

  TDocFluentDb = class(TDbContext)
  private
    function GetDocs: IDbSet<TDocF>;
    function GetServices: IDbSet<TDocServiceF>;
    function GetProducts: IDbSet<TDocProductF>;
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    property Docs: IDbSet<TDocF> read GetDocs;
    property Services: IDbSet<TDocServiceF> read GetServices;
    property Products: IDbSet<TDocProductF> read GetProducts;
  end;

  [TestFixture('Table per hierarchy')]
  TInheritanceTests = class
  public
    [Test]
    procedure Fluent_Create_Table_Has_Discriminator_And_Subclass_Columns;
    [Test]
    procedure Attributes_Create_One_Table_For_The_Hierarchy;
    [Test]
    procedure Fluent_Subclass_Insert_Writes_The_Discriminator;
    [Test]
    procedure Fluent_Root_Query_Returns_Subclasses_With_Their_Properties;
    [Test]
    procedure Fluent_Subclass_Query_Returns_Only_Its_Type;
    [Test]
    procedure Attributes_Root_Query_Returns_Subclasses_With_Their_Properties;
    [Test]
    procedure Attributes_Subclass_Query_Returns_Only_Its_Type;
    [Test]
    procedure Queries_Of_Two_Types_Do_Not_Share_The_Cached_Sql;
    [Test]
    procedure Subclass_Update_Changes_Only_Its_Row;
  end;

implementation

{ TDocAttrDb }

function TDocAttrDb.GetDocs: IDbSet<TDocA>;
begin
  Result := Entities<TDocA>;
end;

function TDocAttrDb.GetServices: IDbSet<TDocServiceA>;
begin
  Result := Entities<TDocServiceA>;
end;

function TDocAttrDb.GetProducts: IDbSet<TDocProductA>;
begin
  Result := Entities<TDocProductA>;
end;

{ TDocFluentDb }

procedure TDocFluentDb.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TDocF>
    .Table('docs_fluent')
    .HasKey('Id')
    .Prop('Id').IsAutoInc
    .MapInheritance(TInheritanceStrategy.TablePerHierarchy)
    .HasDiscriminator('Kind', Null);
  Builder.Entity<TDocServiceF>
    .Table('docs_fluent')
    .HasDiscriminator('Kind', 'SERVICE');
  Builder.Entity<TDocProductF>
    .Table('docs_fluent')
    .HasDiscriminator('Kind', 'PRODUCT');
end;

function TDocFluentDb.GetDocs: IDbSet<TDocF>;
begin
  Result := Entities<TDocF>;
end;

function TDocFluentDb.GetServices: IDbSet<TDocServiceF>;
begin
  Result := Entities<TDocServiceF>;
end;

function TDocFluentDb.GetProducts: IDbSet<TDocProductF>;
begin
  Result := Entities<TDocProductF>;
end;

{ Helpers }

function NewFluent: TDocFluentDb;
begin
  Result := TDocFluentDb.Create(DbContextOptions.UseSQLite(':memory:'));
  Result.EnsureCreated;
end;

function NewAttr: TDocAttrDb;
begin
  Result := TDocAttrDb.Create(DbContextOptions.UseSQLite(':memory:'));
  Result.EnsureCreated;
end;

procedure AddFluentSamples(Db: TDocFluentDb);
var
  S: TDocServiceF;
  P: TDocProductF;
begin
  S := TDocServiceF.Create;
  S.Number := 'S1';
  S.ServiceCode := 'X9';
  P := TDocProductF.Create;
  P.Number := 'P1';
  P.Weight := 2.5;
  Db.Services.Add(S);
  Db.Products.Add(P);
  Db.SaveChanges;
end;

procedure AddAttrSamples(Db: TDocAttrDb);
var
  S: TDocServiceA;
  P: TDocProductA;
begin
  S := TDocServiceA.Create;
  S.Number := 'S1';
  S.ServiceCode := 'X9';
  P := TDocProductA.Create;
  P.Number := 'P1';
  P.Weight := 2.5;
  Db.Services.Add(S);
  Db.Products.Add(P);
  Db.SaveChanges;
end;

{ TInheritanceTests }

procedure TInheritanceTests.Fluent_Create_Table_Has_Discriminator_And_Subclass_Columns;
var
  Db: TDocFluentDb;
  FromRoot, FromSub: string;
begin
  Db := NewFluent;
  try
    FromRoot := Db.Docs.GenerateCreateTableScript;
    FromSub := Db.Services.GenerateCreateTableScript;
    Should(FromRoot).Contain('"Kind"');
    Should(FromRoot).Contain('"ServiceCode"');
    Should(FromRoot).Contain('"Weight"');
    // The same table, whichever set asks for it
    Should(FromSub).Be(FromRoot);
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Attributes_Create_One_Table_For_The_Hierarchy;
var
  Db: TDocAttrDb;
  Script: string;
begin
  Db := NewAttr;
  try
    Script := Db.Docs.GenerateCreateTableScript;
    Should(Script).Contain('"docs_attr"');
    Should(Script).Contain('"Kind"');
    Should(Script).Contain('"ServiceCode"');
    Should(Script).Contain('"Weight"');
    Should(Db.Products.GenerateCreateTableScript).Be(Script);
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Fluent_Subclass_Insert_Writes_The_Discriminator;
var
  Db: TDocFluentDb;
  Reader: IDbReader;
begin
  Db := NewFluent;
  try
    AddFluentSamples(Db);
    Reader := Db.Connection.CreateCommand(
      'SELECT Kind FROM docs_fluent WHERE Number = ''P1''').ExecuteQuery;
    Should(Reader.Next).BeTrue;
    Should(Reader.GetString(0)).Be('PRODUCT');
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Fluent_Root_Query_Returns_Subclasses_With_Their_Properties;
var
  Db: TDocFluentDb;
  Items: IList<TDocF>;
  Item: TDocF;
  Services, Products: Integer;
begin
  Db := NewFluent;
  try
    AddFluentSamples(Db);
    Db.Clear;
    Items := Db.Docs.ToList;
    Should(Items.Count).Be(2);
    Services := 0;
    Products := 0;
    for Item in Items do
    begin
      if Item is TDocServiceF then
      begin
        Inc(Services);
        Should(TDocServiceF(Item).ServiceCode = 'X9').BeTrue;
      end
      else if Item is TDocProductF then
      begin
        Inc(Products);
        Should(TDocProductF(Item).Weight).Be(2.5);
      end;
    end;
    Should(Services).Be(1);
    Should(Products).Be(1);
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Fluent_Subclass_Query_Returns_Only_Its_Type;
var
  Db: TDocFluentDb;
begin
  Db := NewFluent;
  try
    AddFluentSamples(Db);
    Db.Clear;
    Should(Db.Services.ToList.Count).Be(1);
    Should(Db.Products.ToList.Count).Be(1);
    Should(Db.Services.ToList[0].ServiceCode = 'X9').BeTrue;
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Attributes_Root_Query_Returns_Subclasses_With_Their_Properties;
var
  Db: TDocAttrDb;
  Items: IList<TDocA>;
  Item: TDocA;
  Services, Products: Integer;
begin
  Db := NewAttr;
  try
    AddAttrSamples(Db);
    Db.Clear;
    Items := Db.Docs.ToList;
    Should(Items.Count).Be(2);
    Services := 0;
    Products := 0;
    for Item in Items do
    begin
      if Item is TDocServiceA then
      begin
        Inc(Services);
        Should(TDocServiceA(Item).ServiceCode = 'X9').BeTrue;
      end
      else if Item is TDocProductA then
      begin
        Inc(Products);
        Should(TDocProductA(Item).Weight).Be(2.5);
      end;
    end;
    Should(Services).Be(1);
    Should(Products).Be(1);
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Attributes_Subclass_Query_Returns_Only_Its_Type;
var
  Db: TDocAttrDb;
begin
  Db := NewAttr;
  try
    AddAttrSamples(Db);
    Db.Clear;
    Should(Db.Services.ToList.Count).Be(1);
    Should(Db.Products.ToList.Count).Be(1);
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Queries_Of_Two_Types_Do_Not_Share_The_Cached_Sql;
var
  Db: TDocFluentDb;
  Root: TDocF;
  Sub: TDocServiceF;
begin
  Db := NewFluent;
  try
    AddFluentSamples(Db);
    Db.Clear;
    Root := Prototype.Entity<TDocF>;
    Sub := Prototype.Entity<TDocServiceF>;
    // Same shape of condition on two types of one table
    Should(Db.Docs.Where(Root.Number = 'P1').ToList.Count).Be(1);
    Should(Db.Services.Where(Sub.Number = 'P1').ToList.Count).Be(0);
    Should(Db.Docs.Where(Root.Number = 'P1').ToList.Count).Be(1);
  finally
    Db.Free;
  end;
end;

procedure TInheritanceTests.Subclass_Update_Changes_Only_Its_Row;
var
  Db: TDocFluentDb;
  Service: TDocServiceF;
  Reader: IDbReader;
begin
  Db := NewFluent;
  try
    AddFluentSamples(Db);
    Db.Clear;
    Service := Db.Services.ToList[0];
    Service.ServiceCode := 'Z1';
    Should(Db.SaveChanges).Be(1);

    Reader := Db.Connection.CreateCommand(
      'SELECT ServiceCode FROM docs_fluent WHERE Kind = ''SERVICE''').ExecuteQuery;
    Should(Reader.Next).BeTrue;
    Should(Reader.GetString(0)).Be('Z1');
  finally
    Db.Free;
  end;
end;

end.
