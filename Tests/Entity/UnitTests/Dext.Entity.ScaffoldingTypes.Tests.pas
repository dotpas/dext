unit Dext.Entity.ScaffoldingTypes.Tests;

{***************************************************************************}
{  Regression: SQLTypeToDelphiType matched integer types with Contains      }
{  ('INT'), so INTERVAL and POINT (PostgreSQL) were scaffolded as Integer.  }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity.Scaffolding;

type
  [TestFixture]
  TScaffoldingTypesTests = class
  private
    FGenerator: TDelphiEntityGenerator;
    FOwner: IEntityGenerator;
  public
    [Setup]
    procedure Setup;
    [Test]
    procedure Interval_Is_Not_An_Integer;
    [Test]
    procedure Point_Is_Not_An_Integer;
    [Test]
    procedure Integer_Types_Keep_Working;
  end;

implementation

procedure TScaffoldingTypesTests.Setup;
begin
  FGenerator := TDelphiEntityGenerator.Create;
  FOwner := FGenerator;
end;

procedure TScaffoldingTypesTests.Interval_Is_Not_An_Integer;
begin
  Should(FGenerator.SQLTypeToDelphiType('INTERVAL')).Be('string');
  Should(FGenerator.SQLTypeToDelphiType('INTERVAL DAY TO SECOND'))
    .Be('string');
end;

procedure TScaffoldingTypesTests.Point_Is_Not_An_Integer;
begin
  Should(FGenerator.SQLTypeToDelphiType('POINT')).Be('string');
end;

procedure TScaffoldingTypesTests.Integer_Types_Keep_Working;
begin
  Should(FGenerator.SQLTypeToDelphiType('INT')).Be('Integer');
  Should(FGenerator.SQLTypeToDelphiType('INTEGER')).Be('Integer');
  Should(FGenerator.SQLTypeToDelphiType('BIGINT')).Be('Int64');
  Should(FGenerator.SQLTypeToDelphiType('SMALLINT')).Be('SmallInt');
  Should(FGenerator.SQLTypeToDelphiType('TINYINT')).Be('Integer');
  Should(FGenerator.SQLTypeToDelphiType('SERIAL')).Be('Integer');
end;

end.
