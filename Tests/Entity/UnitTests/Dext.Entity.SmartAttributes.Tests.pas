unit Dext.Entity.SmartAttributes.Tests;

{***************************************************************************}
{  Regression: [MaxLength] and [Required] on Smart Properties.              }
{                                                                           }
{  The validator read the property as a record (Prop<T>), so a StringType   }
{  property escaped both rules, and the DDL generator ignored [MaxLength]  }
{  for it (VARCHAR(255) instead of VARCHAR(n)). Plain types worked.         }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Entity.Setup,
  Dext.Entity.Validator,
  FireDAC.Phys.SQLite;

type
  [Table('smart_attr_plain')]
  TSmartAttrPlain = class
  private
    FId: Integer;
    FName: string;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    [MaxLength(10), Required]
    property Name: string read FName write FName;
  end;

  [Table('smart_attr_smart')]
  TSmartAttrSmart = class
  private
    FId: IntType;
    FName: StringType;
  public
    [PrimaryKey]
    property Id: IntType read FId write FId;
    [MaxLength(10), Required]
    property Name: StringType read FName write FName;
  end;

  TSmartAttrDb = class(TDbContext)
  private
    function GetPlain: IDbSet<TSmartAttrPlain>;
    function GetSmart: IDbSet<TSmartAttrSmart>;
  public
    property Plain: IDbSet<TSmartAttrPlain> read GetPlain;
    property Smart: IDbSet<TSmartAttrSmart> read GetSmart;
  end;

  [TestFixture('MaxLength and Required with Smart Properties')]
  TSmartAttributesTests = class
  private
    FDb: TSmartAttrDb;
  public
    [Setup]
    procedure CreateDb;
    [TearDown]
    procedure FreeDb;

    [Test]
    [Description('Plain string: DDL uses the [MaxLength]')]
    procedure Plain_String_Ddl_Uses_MaxLength;

    [Test]
    [Description('StringType: DDL uses the [MaxLength]')]
    procedure Smart_String_Ddl_Uses_MaxLength;

    [Test]
    [Description('StringType longer than [MaxLength] fails validation')]
    procedure Smart_String_Longer_Than_MaxLength_Fails_Validation;

    [Test]
    [Description('Empty StringType with [Required] fails validation')]
    procedure Smart_String_Empty_With_Required_Fails_Validation;

    [Test]
    [Description('A valid StringType passes validation')]
    procedure Smart_String_Within_Limits_Passes_Validation;
  end;

implementation

{ TSmartAttrDb }

function TSmartAttrDb.GetPlain: IDbSet<TSmartAttrPlain>;
begin
  Result := Entities<TSmartAttrPlain>;
end;

function TSmartAttrDb.GetSmart: IDbSet<TSmartAttrSmart>;
begin
  Result := Entities<TSmartAttrSmart>;
end;

{ TSmartAttributesTests }

procedure TSmartAttributesTests.CreateDb;
begin
  FDb := TSmartAttrDb.Create(DbContextOptions.UseSQLite(':memory:'));
end;

procedure TSmartAttributesTests.FreeDb;
begin
  FDb.Free;
end;

procedure TSmartAttributesTests.Plain_String_Ddl_Uses_MaxLength;
begin
  Should(FDb.Plain.GenerateCreateTableScript).Contain('"Name" VARCHAR(10)');
end;

procedure TSmartAttributesTests.Smart_String_Ddl_Uses_MaxLength;
begin
  Should(FDb.Smart.GenerateCreateTableScript).Contain('"Name" VARCHAR(10)');
end;

procedure TSmartAttributesTests.Smart_String_Longer_Than_MaxLength_Fails_Validation;
var
  Item: TSmartAttrSmart;
begin
  Item := TSmartAttrSmart.Create;
  try
    Item.Id := 1;
    Item.Name := 'THIS NAME IS TOO LONG';
    Should(
      procedure
      begin
        TEntityValidator.Validate(Item, nil);
      end).Throw<EValidationException>;
  finally
    Item.Free;
  end;
end;

procedure TSmartAttributesTests.Smart_String_Empty_With_Required_Fails_Validation;
var
  Item: TSmartAttrSmart;
begin
  Item := TSmartAttrSmart.Create;
  try
    Item.Id := 1;
    Item.Name := '';
    Should(
      procedure
      begin
        TEntityValidator.Validate(Item, nil);
      end).Throw<EValidationException>;
  finally
    Item.Free;
  end;
end;

procedure TSmartAttributesTests.Smart_String_Within_Limits_Passes_Validation;
var
  Item: TSmartAttrSmart;
begin
  Item := TSmartAttrSmart.Create;
  try
    Item.Id := 1;
    Item.Name := 'OK';
    TEntityValidator.Validate(Item, nil);
    Should(Item.Name = 'OK').BeTrue;
  finally
    Item.Free;
  end;
end;

end.
