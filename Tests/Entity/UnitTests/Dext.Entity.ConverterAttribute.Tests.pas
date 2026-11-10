unit Dext.Entity.ConverterAttribute.Tests;

{***************************************************************************}
{  Regression: [TypeConverter(...)] and HasConverter(...) stored the        }
{  converter class in the property map, but nothing ever created it. The    }
{  property was then written and read as if it had no converter, and a     }
{  value object (a record) failed with an invalid cast.                     }
{***************************************************************************}

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Data.DB,
  Data.FmtBcd,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Collections,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Mapping,
  Dext.Entity.Setup,
  Dext.Entity.TypeConverters,
  Dext.Entity.Drivers.Interfaces,
  FireDAC.Phys.SQLite;

type
  // A value object: money as a record, stored in one numeric column.
  TMoney = record
  private
    FAmount: Currency;
  public
    class function Of_(const AAmount: Currency): TMoney; static;
    property Amount: Currency read FAmount;
  end;

  TMoneyConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue;
      ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue;
      ATypeInfo: PTypeInfo): TValue; override;
  end;

  [Table('conv_attr')]
  TConvByAttribute = class
  private
    FId: Integer;
    FTotal: TMoney;
  public
    [PrimaryKey, AutoInc]
    property Id: Integer read FId write FId;
    [TypeConverter(TMoneyConverter), DbType(ftCurrency), Precision(18, 2)]
    property Total: TMoney read FTotal write FTotal;
  end;

  TConvByFluent = class
  private
    FId: Integer;
    FTotal: TMoney;
  public
    property Id: Integer read FId write FId;
    property Total: TMoney read FTotal write FTotal;
  end;

  TConvAttrDb = class(TDbContext)
  private
    function GetItems: IDbSet<TConvByAttribute>;
  public
    property Items: IDbSet<TConvByAttribute> read GetItems;
  end;

  TConvFluentDb = class(TDbContext)
  private
    function GetItems: IDbSet<TConvByFluent>;
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  public
    property Items: IDbSet<TConvByFluent> read GetItems;
  end;

  [TestFixture('Converter chosen by attribute or fluent mapping')]
  TConverterAttributeTests = class
  public
    [Test]
    procedure Attribute_Converter_Writes_And_Reads_A_Value_Object;
    [Test]
    procedure Fluent_Converter_Writes_And_Reads_A_Value_Object;
  end;

implementation

{ TMoney }

class function TMoney.Of_(const AAmount: Currency): TMoney;
begin
  Result.FAmount := AAmount;
end;

{ TMoneyConverter }

function TMoneyConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TMoney);
end;

function TMoneyConverter.ToDatabase(const AValue: TValue;
  ADialect: TDatabaseDialect): TValue;
begin
  Result := TValue.From<Currency>(AValue.AsType<TMoney>.Amount);
end;

function TMoneyConverter.FromDatabase(const AValue: TValue;
  ATypeInfo: PTypeInfo): TValue;
var
  Amount: Currency;
begin
  // A DECIMAL column reaches the converter as a TBcd, not as a float.
  if AValue.TypeInfo = TypeInfo(TBcd) then
    Amount := BcdToCurrency(AValue.AsType<TBcd>)
  else
    Amount := AValue.AsExtended;
  Result := TValue.From<TMoney>(TMoney.Of_(Amount));
end;

{ TConvAttrDb }

function TConvAttrDb.GetItems: IDbSet<TConvByAttribute>;
begin
  Result := Entities<TConvByAttribute>;
end;

{ TConvFluentDb }

function TConvFluentDb.GetItems: IDbSet<TConvByFluent>;
begin
  Result := Entities<TConvByFluent>;
end;

procedure TConvFluentDb.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TConvByFluent>
    .Table('conv_fluent')
    .HasKey('Id')
    .Prop('Id').IsAutoInc
    .Prop('Total').HasConverter(TMoneyConverter).HasDbType(ftCurrency)
    .Precision(18, 2);
end;

{ TConverterAttributeTests }

procedure TConverterAttributeTests.Attribute_Converter_Writes_And_Reads_A_Value_Object;
var
  Db: TConvAttrDb;
  Item: TConvByAttribute;
  Items: IList<TConvByAttribute>;
begin
  Db := TConvAttrDb.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.EnsureCreated;
    Item := TConvByAttribute.Create;
    Item.Total := TMoney.Of_(1234.56);
    Db.Items.Add(Item);
    Db.SaveChanges;
    Db.Clear;

    Items := Db.Items.ToList;
    Should(Items.Count).Be(1);
    Should(Items[0].Total.Amount).Be(1234.56);
  finally
    Db.Free;
  end;
end;

procedure TConverterAttributeTests.Fluent_Converter_Writes_And_Reads_A_Value_Object;
var
  Db: TConvFluentDb;
  Item: TConvByFluent;
  Items: IList<TConvByFluent>;
begin
  Db := TConvFluentDb.Create(DbContextOptions.UseSQLite(':memory:'));
  try
    Db.EnsureCreated;
    Item := TConvByFluent.Create;
    Item.Total := TMoney.Of_(99.9);
    Db.Items.Add(Item);
    Db.SaveChanges;
    Db.Clear;

    Items := Db.Items.ToList;
    Should(Items.Count).Be(1);
    Should(Items[0].Total.Amount).Be(99.9);
  finally
    Db.Free;
  end;
end;

end.
