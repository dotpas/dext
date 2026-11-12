unit Dext.Entity.EnumAsString.Tests;

{***************************************************************************}
{  Regression: [EnumAsString] was declared ("save the enum as a string      }
{  instead of an integer") but no code read it. The enum was stored as its  }
{  ordinal, silently, and the column kept the integer type.                 }
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
  TEnumStatus = (esOpen, esPaid, esCanceled);

  [Table('enum_str_items')]
  TEnumStrItem = class
  private
    FId: Integer;
    FStatus: TEnumStatus;
    FPriority: TEnumStatus;
  public
    [PrimaryKey]
    [AutoInc]
    property Id: Integer read FId write FId;

    [EnumAsString]
    property Status: TEnumStatus read FStatus write FStatus;

    property Priority: TEnumStatus read FPriority write FPriority;
  end;

  TEnumStrDb = class(TDbContext)
  private
    function GetItems: IDbSet<TEnumStrItem>;
  public
    property Items: IDbSet<TEnumStrItem> read GetItems;
  end;

  [TestFixture('[EnumAsString] stores the enum name')]
  TEnumAsStringTests = class
  private
    FDb: TEnumStrDb;
    function Scalar(const ASql: string): string;
  public
    [Setup]
    procedure CreateDb;
    [TearDown]
    procedure FreeDb;

    [Test]
    [Description('The marked property is stored as its name')]
    procedure Marked_Enum_Is_Stored_As_Name;

    [Test]
    [Description('Without the attribute the ordinal is stored')]
    procedure Unmarked_Enum_Is_Stored_As_Ordinal;

    [Test]
    [Description('The name is read back into the enum')]
    procedure Name_Is_Read_Back;

    [Test]
    [Description('The column of a marked enum is text')]
    procedure Marked_Enum_Column_Is_Text;
  end;

implementation

{ TEnumStrDb }

function TEnumStrDb.GetItems: IDbSet<TEnumStrItem>;
begin
  Result := Entities<TEnumStrItem>;
end;

{ TEnumAsStringTests }

procedure TEnumAsStringTests.CreateDb;
begin
  FDb := TEnumStrDb.Create(DbContextOptions.UseSQLite(':memory:'));
  FDb.EnsureCreated;
end;

procedure TEnumAsStringTests.FreeDb;
begin
  FDb.Free;
end;

function TEnumAsStringTests.Scalar(const ASql: string): string;
begin
  Result := FDb.Connection.CreateCommand(ASql).ExecuteScalar.ToString;
end;

procedure TEnumAsStringTests.Marked_Enum_Is_Stored_As_Name;
var
  Item: TEnumStrItem;
begin
  Item := TEnumStrItem.Create;
  Item.Status := esPaid;
  FDb.Items.Add(Item);
  FDb.SaveChanges;

  Should(Scalar('SELECT Status FROM enum_str_items')).Be('esPaid');
end;

procedure TEnumAsStringTests.Unmarked_Enum_Is_Stored_As_Ordinal;
var
  Item: TEnumStrItem;
begin
  Item := TEnumStrItem.Create;
  Item.Priority := esCanceled;
  FDb.Items.Add(Item);
  FDb.SaveChanges;

  Should(Scalar('SELECT Priority FROM enum_str_items')).Be('2');
end;

procedure TEnumAsStringTests.Name_Is_Read_Back;
var
  Item: TEnumStrItem;
  Id: Integer;
begin
  Item := TEnumStrItem.Create;
  Item.Status := esCanceled;
  Item.Priority := esPaid;
  FDb.Items.Add(Item);
  FDb.SaveChanges;
  Id := Item.Id;
  FDb.DetachAll;

  Item := FDb.Items.Find(Id);
  Should(Ord(Item.Status)).Be(Ord(esCanceled));
  Should(Ord(Item.Priority)).Be(Ord(esPaid));
end;

procedure TEnumAsStringTests.Marked_Enum_Column_Is_Text;
var
  Script: string;
begin
  Script := FDb.Items.GenerateCreateTableScript;
  Should(Script).Contain('"Status" VARCHAR');
  Should(Script).NotContain('"Status" INTEGER');
end;

end.
