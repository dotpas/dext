unit Dext.Entity.DdlAttributes.Tests;

{***************************************************************************}
{  Regression: attributes that the DDL generator ignored.                   }
{                                                                           }
{  [ColumnType('...')] was documented as "custom database type" but no code }
{  read it: the column kept the type derived from the Delphi type.          }
{  [DeleteBehavior] next to [ForeignKey] was stored in the map and never    }
{  reached the constraint: ON DELETE stayed out of the CREATE TABLE.        }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  Dext.Entity.TypeConverters,
  FireDAC.Phys.SQLite;

type
  [Table('ddl_attr_clients')]
  TDdlAttrClient = class
  private
    FId: Integer;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
  end;

  [Table('ddl_attr_orders')]
  TDdlAttrOrder = class
  private
    FId: Integer;
    FNumber: string;
    FClientId: Integer;
    FClient: TDdlAttrClient;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;

    [ColumnType('VARCHAR(20)')]
    property Number: string read FNumber write FNumber;

    property ClientId: Integer read FClientId write FClientId;

    [ForeignKey('ClientId'), DeleteBehavior(caCascade)]
    property Client: TDdlAttrClient read FClient write FClient;
  end;

  [Table('ddl_attr_items')]
  TDdlAttrItem = class
  private
    FId: Integer;
    FOrderId: Integer;
    FOrder: TDdlAttrOrder;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property OrderId: Integer read FOrderId write FOrderId;

    // The action given to [ForeignKey] itself wins over [DeleteBehavior]
    [ForeignKey('OrderId', caRestrict), DeleteBehavior(caCascade)]
    property Order: TDdlAttrOrder read FOrder write FOrder;
  end;

  TDdlAttrDb = class(TDbContext)
  private
    function GetOrders: IDbSet<TDdlAttrOrder>;
    function GetItems: IDbSet<TDdlAttrItem>;
  public
    property Orders: IDbSet<TDdlAttrOrder> read GetOrders;
    property Items: IDbSet<TDdlAttrItem> read GetItems;
  end;

  [TestFixture('DDL honors ColumnType and DeleteBehavior')]
  TDdlAttributesTests = class
  private
    FDb: TDdlAttrDb;
  public
    [Setup]
    procedure CreateDb;
    [TearDown]
    procedure FreeDb;

    [Test]
    [Description('[ColumnType] sets the type of the column')]
    procedure ColumnType_Sets_The_Column_Type;

    [Test]
    [Description('[DeleteBehavior] next to [ForeignKey] reaches the constraint')]
    procedure DeleteBehavior_Reaches_The_Constraint;

    [Test]
    [Description('The action given to [ForeignKey] wins over [DeleteBehavior]')]
    procedure ForeignKey_Action_Wins_Over_DeleteBehavior;
  end;

implementation

{ TDdlAttrDb }

function TDdlAttrDb.GetOrders: IDbSet<TDdlAttrOrder>;
begin
  Result := Entities<TDdlAttrOrder>;
end;

function TDdlAttrDb.GetItems: IDbSet<TDdlAttrItem>;
begin
  Result := Entities<TDdlAttrItem>;
end;

{ TDdlAttributesTests }

procedure TDdlAttributesTests.CreateDb;
begin
  FDb := TDdlAttrDb.Create(DbContextOptions.UseSQLite(':memory:'));
end;

procedure TDdlAttributesTests.FreeDb;
begin
  FDb.Free;
end;

procedure TDdlAttributesTests.ColumnType_Sets_The_Column_Type;
begin
  Should(FDb.Orders.GenerateCreateTableScript).Contain('"Number" VARCHAR(20)');
end;

procedure TDdlAttributesTests.DeleteBehavior_Reaches_The_Constraint;
begin
  Should(FDb.Orders.GenerateCreateTableScript).Contain('ON DELETE CASCADE');
end;

procedure TDdlAttributesTests.ForeignKey_Action_Wins_Over_DeleteBehavior;
var
  Script: string;
begin
  Script := FDb.Items.GenerateCreateTableScript;
  Should(Script).Contain('ON DELETE RESTRICT');
  Should(Script).NotContain('ON DELETE CASCADE');
end;

end.
