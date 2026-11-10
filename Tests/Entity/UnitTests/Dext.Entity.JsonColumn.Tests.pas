unit Dext.Entity.JsonColumn.Tests;

{***************************************************************************}
{  Regression: a class property stored as JSON.                             }
{                                                                           }
{  - IsJson (fluent) did not clear the "navigation" flag the discovery set  }
{    for every class property, so CREATE TABLE left the column out.         }
{  - Prototype.Entity<T> tried to build a prototype of the JSON class and   }
{    raised "does not contain any Smart Properties", which broke every      }
{    Where on the entity.                                                    }
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
  Dext.Entity.Mapping,
  Dext.Entity.Setup,
  FireDAC.Phys.SQLite;

type
  TJsonSettings = class
  private
    FChannel: string;
    FAttempts: Integer;
  public
    property Channel: string read FChannel write FChannel;
    property Attempts: Integer read FAttempts write FAttempts;
  end;

  TJsonByFluent = class
  private
    FId: IntType;
    FName: StringType;
    FSettings: TJsonSettings;
  public
    destructor Destroy; override;
    property Id: IntType read FId write FId;
    property Name: StringType read FName write FName;
    property Settings: TJsonSettings read FSettings write FSettings;
  end;

  [Table('json_attr')]
  TJsonByAttribute = class
  private
    FId: IntType;
    FName: StringType;
    FSettings: TJsonSettings;
  public
    destructor Destroy; override;
    [PrimaryKey]
    property Id: IntType read FId write FId;
    property Name: StringType read FName write FName;
    [JsonColumn]
    property Settings: TJsonSettings read FSettings write FSettings;
  end;

  TJsonFluentDb = class(TDbContext)
  private
    function GetItems: IDbSet<TJsonByFluent>;
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    property Items: IDbSet<TJsonByFluent> read GetItems;
  end;

  TJsonAttrDb = class(TDbContext)
  private
    function GetItems: IDbSet<TJsonByAttribute>;
  public
    property Items: IDbSet<TJsonByAttribute> read GetItems;
  end;

  [TestFixture('JSON column')]
  TJsonColumnTests = class
  public
    [Test]
    procedure Fluent_IsJson_Creates_The_Column;
    [Test]
    procedure Fluent_Json_Entity_Can_Be_Queried_With_A_Prototype;
    [Test]
    procedure Attribute_Json_Entity_Can_Be_Queried_With_A_Prototype;
  end;

implementation

{ TJsonByFluent }

destructor TJsonByFluent.Destroy;
begin
  FSettings.Free;
  inherited;
end;

{ TJsonByAttribute }

destructor TJsonByAttribute.Destroy;
begin
  FSettings.Free;
  inherited;
end;

{ TJsonFluentDb }

function TJsonFluentDb.GetItems: IDbSet<TJsonByFluent>;
begin
  Result := Entities<TJsonByFluent>;
end;

procedure TJsonFluentDb.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TJsonByFluent>
    .Table('json_fluent')
    .HasKey('Id')
    .Prop('Settings').IsJson;
end;

{ TJsonAttrDb }

function TJsonAttrDb.GetItems: IDbSet<TJsonByAttribute>;
begin
  Result := Entities<TJsonByAttribute>;
end;

{ TJsonColumnTests }

procedure TJsonColumnTests.Fluent_IsJson_Creates_The_Column;
var
  Db: TJsonFluentDb;
begin
  Db := TJsonFluentDb.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Should(Db.Items.GenerateCreateTableScript).Contain('"Settings"');
  finally
    Db.Free;
  end;
end;

procedure TJsonColumnTests.Fluent_Json_Entity_Can_Be_Queried_With_A_Prototype;
var
  Db: TJsonFluentDb;
  Item: TJsonByFluent;
  P: TJsonByFluent;
  Found: IList<TJsonByFluent>;
begin
  Db := TJsonFluentDb.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.EnsureCreated;
    Item := TJsonByFluent.Create;
    Item.Id := 1;
    Item.Name := 'one';
    Item.Settings := TJsonSettings.Create;
    Item.Settings.Channel := 'portal';
    Item.Settings.Attempts := 3;
    Db.Items.Add(Item);
    Db.SaveChanges;
    Db.Clear;

    P := Prototype.Entity<TJsonByFluent>;
    Found := Db.Items.Where(P.Name = 'one').ToList;
    Should(Found.Count).Be(1);
    Should(Found[0].Settings <> nil).BeTrue;
    Should(Found[0].Settings.Channel).Be('portal');
    Should(Found[0].Settings.Attempts).Be(3);
  finally
    Db.Free;
  end;
end;

procedure TJsonColumnTests.Attribute_Json_Entity_Can_Be_Queried_With_A_Prototype;
var
  Db: TJsonAttrDb;
  Item: TJsonByAttribute;
  P: TJsonByAttribute;
  Found: IList<TJsonByAttribute>;
begin
  Db := TJsonAttrDb.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.EnsureCreated;
    Item := TJsonByAttribute.Create;
    Item.Id := 1;
    Item.Name := 'one';
    Item.Settings := TJsonSettings.Create;
    Item.Settings.Channel := 'portal';
    Db.Items.Add(Item);
    Db.SaveChanges;
    Db.Clear;

    P := Prototype.Entity<TJsonByAttribute>;
    Found := Db.Items.Where(P.Name = 'one').ToList;
    Should(Found.Count).Be(1);
    Should(Found[0].Settings.Channel).Be('portal');
  finally
    Db.Free;
  end;
end;

end.
