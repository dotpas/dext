unit Dext.Entity.NestedDto.Tests;

{***************************************************************************}
{  Regression: [Nested] on a DTO used with SqlQuery<T>.                     }
{                                                                           }
{  The DTO hydrator matched a column only with a property or field of the   }
{  DTO itself. [Nested] was declared but never read, so a column such as    }
{  "Category_Name" was dropped and the nested object stayed nil.            }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Collections,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  FireDAC.Phys.SQLite;

type
  [Table('nd_categories')]
  TNdCategory = class
  private
    FId: Integer;
    FName: string;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  [Table('nd_items')]
  TNdItem = class
  private
    FId: Integer;
    FName: string;
    FCategoryId: Integer;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property CategoryId: Integer read FCategoryId write FCategoryId;
  end;

  TNdCategoryDto = class
  private
    FName: string;
    FParent: TNdCategoryDto;
  public
    destructor Destroy; override;
    property Name: string read FName write FName;
    [Nested]
    property Parent: TNdCategoryDto read FParent write FParent;
  end;

  TNdItemDto = class
  private
    FId: Integer;
    FName: string;
    FCategory: TNdCategoryDto;
    FNotNested: TNdCategoryDto;
  public
    destructor Destroy; override;
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    [Nested]
    property Category: TNdCategoryDto read FCategory write FCategory;
    // No [Nested]: its columns are not routed into it
    property NotNested: TNdCategoryDto read FNotNested write FNotNested;
  end;

  TNdDb = class(TDbContext)
  private
    function GetCategories: IDbSet<TNdCategory>;
    function GetItems: IDbSet<TNdItem>;
  public
    property Categories: IDbSet<TNdCategory> read GetCategories;
    property Items: IDbSet<TNdItem> read GetItems;
  end;

  [TestFixture('Nested DTO')]
  TNestedDtoTests = class
  private
    FDb: TNdDb;
    procedure Seed;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Nested_Columns_Fill_The_Nested_Object;
    [Test]
    procedure Flat_Columns_Still_Fill_The_Dto;
    [Test]
    procedure Nested_Object_Stays_Nil_When_All_Its_Columns_Are_Null;
    [Test]
    procedure Nested_Works_Over_Two_Levels;
    [Test]
    procedure Property_Without_Nested_Attribute_Is_Not_Filled;
    [Test]
    procedure SqlQueryFirst_Fills_The_Nested_Object;
    [Test]
    procedure Dot_Separator_Is_Accepted;
  end;

implementation

{ TNdCategoryDto }

destructor TNdCategoryDto.Destroy;
begin
  FParent.Free;
  inherited;
end;

{ TNdItemDto }

destructor TNdItemDto.Destroy;
begin
  FCategory.Free;
  FNotNested.Free;
  inherited;
end;

{ TNdDb }

function TNdDb.GetCategories: IDbSet<TNdCategory>;
begin
  Result := Entities<TNdCategory>;
end;

function TNdDb.GetItems: IDbSet<TNdItem>;
begin
  Result := Entities<TNdItem>;
end;

{ TNestedDtoTests }

procedure TNestedDtoTests.Setup;
begin
  FDb := TNdDb.Create(DbContextOptions.UseSQLite(':memory:'));
  FDb.Categories;
  FDb.Items;
  FDb.EnsureCreated;
  Seed;
end;

procedure TNestedDtoTests.TearDown;
begin
  FreeAndNil(FDb);
end;

procedure TNestedDtoTests.Seed;
var
  C: TNdCategory;
  I: TNdItem;
begin
  C := TNdCategory.Create;
  C.Id := 1;
  C.Name := 'Hardware';
  FDb.Categories.Add(C);

  I := TNdItem.Create;
  I.Id := 10;
  I.Name := 'Keyboard';
  I.CategoryId := 1;
  FDb.Items.Add(I);

  // An item whose category does not exist (used by the LEFT JOIN test)
  I := TNdItem.Create;
  I.Id := 11;
  I.Name := 'Orphan';
  I.CategoryId := 99;
  FDb.Items.Add(I);

  FDb.SaveChanges;
end;

procedure TNestedDtoTests.Nested_Columns_Fill_The_Nested_Object;
var
  List: IList<TNdItemDto>;
begin
  List := FDb.SqlQuery<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS Category_Name ' +
    'FROM nd_items i JOIN nd_categories c ON c.Id = i.CategoryId');
  Should(List.Count).Be(1);
  Should(List[0].Category <> nil).BeTrue;
  Should(List[0].Category.Name).Be('Hardware');
end;

procedure TNestedDtoTests.Flat_Columns_Still_Fill_The_Dto;
var
  List: IList<TNdItemDto>;
begin
  List := FDb.SqlQuery<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS Category_Name ' +
    'FROM nd_items i JOIN nd_categories c ON c.Id = i.CategoryId');
  Should(List[0].Id).Be(10);
  Should(List[0].Name).Be('Keyboard');
end;

procedure TNestedDtoTests.Nested_Object_Stays_Nil_When_All_Its_Columns_Are_Null;
var
  List: IList<TNdItemDto>;
begin
  List := FDb.SqlQuery<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS Category_Name ' +
    'FROM nd_items i LEFT JOIN nd_categories c ON c.Id = i.CategoryId ' +
    'ORDER BY i.Id');
  Should(List.Count).Be(2);
  Should(List[0].Category <> nil).BeTrue;
  Should(List[1].Name).Be('Orphan');
  Should(List[1].Category = nil).BeTrue;
end;

procedure TNestedDtoTests.Nested_Works_Over_Two_Levels;
var
  List: IList<TNdItemDto>;
begin
  List := FDb.SqlQuery<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS Category_Name, ' +
    '''Root'' AS Category_Parent_Name ' +
    'FROM nd_items i JOIN nd_categories c ON c.Id = i.CategoryId');
  Should(List[0].Category.Name).Be('Hardware');
  Should(List[0].Category.Parent <> nil).BeTrue;
  Should(List[0].Category.Parent.Name).Be('Root');
end;

procedure TNestedDtoTests.Property_Without_Nested_Attribute_Is_Not_Filled;
var
  List: IList<TNdItemDto>;
begin
  List := FDb.SqlQuery<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS NotNested_Name ' +
    'FROM nd_items i JOIN nd_categories c ON c.Id = i.CategoryId');
  Should(List[0].NotNested = nil).BeTrue;
end;

procedure TNestedDtoTests.SqlQueryFirst_Fills_The_Nested_Object;
var
  Item: TNdItemDto;
begin
  Item := FDb.SqlQueryFirst<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS Category_Name ' +
    'FROM nd_items i JOIN nd_categories c ON c.Id = i.CategoryId ' +
    'WHERE i.Id = :Id', [10]);
  try
    Should(Item <> nil).BeTrue;
    Should(Item.Category.Name).Be('Hardware');
  finally
    Item.Free;
  end;
end;

procedure TNestedDtoTests.Dot_Separator_Is_Accepted;
var
  List: IList<TNdItemDto>;
begin
  List := FDb.SqlQuery<TNdItemDto>(
    'SELECT i.Id, i.Name, c.Name AS "Category.Name" ' +
    'FROM nd_items i JOIN nd_categories c ON c.Id = i.CategoryId');
  Should(List[0].Category.Name).Be('Hardware');
end;

end.
