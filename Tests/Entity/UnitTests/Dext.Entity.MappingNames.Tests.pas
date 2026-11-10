unit Dext.Entity.MappingNames.Tests;

{***************************************************************************}
{  Regression: the fluent API ignored property names that the entity does   }
{  not have. HasKey('Idd') left the table without a primary key and         }
{  Prop('Nmae').HasMaxLength(5) was never applied, with no error. The       }
{  builders now raise EEntityMappingException; shadow properties are        }
{  declared with ShadowProperty.                                            }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity.Mapping;

type
  TMappedThing = class
  private
    FId: Integer;
    FName: string;
  public
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  TMappedThingConfig = class(TEntityTypeConfiguration<TMappedThing>)
  public
    procedure Configure(Builder: IEntityTypeBuilder<TMappedThing>); override;
  end;

  TMappedThingBadConfig = class(TEntityTypeConfiguration<TMappedThing>)
  public
    procedure Configure(Builder: IEntityTypeBuilder<TMappedThing>); override;
  end;

  TMappedThingIgnoreConfig = class(TEntityTypeConfiguration<TMappedThing>)
  public
    procedure Configure(Builder: IEntityTypeBuilder<TMappedThing>); override;
  end;

  [TestFixture('Fluent mapping rejects unknown property names')]
  TMappingNamesTests = class
  public
    [Test]
    procedure HasKey_With_Unknown_Name_Raises;

    [Test]
    procedure Prop_With_Unknown_Name_Raises;

    [Test]
    procedure Ignore_With_Unknown_Name_Raises;

    [Test]
    procedure Configuration_With_Unknown_Name_Raises;

    [Test]
    procedure Known_Names_Are_Accepted;

    [Test]
    procedure ShadowProperty_Accepts_A_Name_The_Class_Does_Not_Have;

    [Test]
    procedure The_Message_Names_The_Property_And_The_Entity;
  end;

implementation

{ TMappedThingConfig }

procedure TMappedThingConfig.Configure(Builder: IEntityTypeBuilder<TMappedThing>);
begin
  Builder.ToTable('things');
  Builder.HasKey('Id');
  Builder.Prop('Name').HasColumnName('thing_name').HasMaxLength(20);
end;

{ TMappedThingBadConfig }

procedure TMappedThingBadConfig.Configure(Builder: IEntityTypeBuilder<TMappedThing>);
begin
  Builder.Prop('Nmae').HasMaxLength(5);
end;

{ TMappedThingIgnoreConfig }

procedure TMappedThingIgnoreConfig.Configure(Builder: IEntityTypeBuilder<TMappedThing>);
begin
  Builder.Ignore('Nothing');
end;

{ TMappingNamesTests }

procedure TMappingNamesTests.HasKey_With_Unknown_Name_Raises;
var
  Model: TModelBuilder;
begin
  Model := TModelBuilder.Create;
  try
    Should(
      procedure
      begin
        Model.Entity<TMappedThing>.HasKey('Idd');
      end).Throw<EEntityMappingException>;
  finally
    Model.Free;
  end;
end;

procedure TMappingNamesTests.Prop_With_Unknown_Name_Raises;
var
  Model: TModelBuilder;
begin
  Model := TModelBuilder.Create;
  try
    Should(
      procedure
      begin
        Model.Entity<TMappedThing>.Prop('Nmae').MaxLength(5);
      end).Throw<EEntityMappingException>;
  finally
    Model.Free;
  end;
end;

procedure TMappingNamesTests.Ignore_With_Unknown_Name_Raises;
var
  Model: TModelBuilder;
begin
  Model := TModelBuilder.Create;
  try
    Should(
      procedure
      begin
        Model.ApplyConfiguration<TMappedThing>(TMappedThingIgnoreConfig.Create);
      end).Throw<EEntityMappingException>;
  finally
    Model.Free;
  end;
end;

procedure TMappingNamesTests.Configuration_With_Unknown_Name_Raises;
var
  Model: TModelBuilder;
begin
  Model := TModelBuilder.Create;
  try
    Should(
      procedure
      begin
        Model.ApplyConfiguration<TMappedThing>(TMappedThingBadConfig.Create);
      end).Throw<EEntityMappingException>;
  finally
    Model.Free;
  end;
end;

procedure TMappingNamesTests.Known_Names_Are_Accepted;
var
  Model: TModelBuilder;
begin
  Model := TModelBuilder.Create;
  try
    Model.ApplyConfiguration<TMappedThing>(TMappedThingConfig.Create);
    Model.Entity<TMappedThing>.Prop('Name').MaxLength(30);
    Should(Model.GetMap(TypeInfo(TMappedThing)).Keys.Count).Be(1);
  finally
    Model.Free;
  end;
end;

procedure TMappingNamesTests.ShadowProperty_Accepts_A_Name_The_Class_Does_Not_Have;
var
  Model: TModelBuilder;
  Map: TEntityMap;
begin
  Model := TModelBuilder.Create;
  try
    Model.Entity<TMappedThing>.ShadowProperty('CreatedBy');
    Map := Model.GetMap(TypeInfo(TMappedThing));
    Should(Map.Properties.ContainsKey('CreatedBy')).BeTrue;
    Should(Map.Properties['CreatedBy'].IsShadow).BeTrue;
  finally
    Model.Free;
  end;
end;

procedure TMappingNamesTests.The_Message_Names_The_Property_And_The_Entity;
var
  Model: TModelBuilder;
  Msg: string;
begin
  Model := TModelBuilder.Create;
  try
    Msg := '';
    try
      Model.Entity<TMappedThing>.HasKey('Idd');
    except
      on E: EEntityMappingException do
        Msg := E.Message;
    end;
    Should(Msg).Contain('Idd');
    Should(Msg).Contain('TMappedThing');
  finally
    Model.Free;
  end;
end;

end.
