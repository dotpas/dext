unit Dext.Testing.CategoryFilter.Tests;

// Excluding a category: a run for a server that lacks a feature leaves out the
// tests tagged for the one that has it, without tagging every other test.

interface

uses
  System.SysUtils,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Testing.Runner;

type
  [TestFixture('Test filter: excluded categories')]
  TCategoryFilterTests = class
  private
    function Passes(const AFilter: TTestFilter;
      const ACategories: array of string): Boolean;
  public
    [Test]
    [Description('Without exclusions every test passes')]
    procedure No_Exclusion_Lets_Everything_Through;

    [Test]
    [Description('A test of an excluded category is left out')]
    procedure Excluded_Category_Is_Left_Out;

    [Test]
    [Description('A test with no excluded category stays')]
    procedure Other_Categories_Stay;

    [Test]
    [Description('One excluded category among several is enough')]
    procedure One_Excluded_Among_Several_Is_Enough;

    [Test]
    [Description('The comparison ignores case, like the inclusion filter')]
    procedure Exclusion_Ignores_Case;

    [Test]
    [Description('Exclusion wins over inclusion when both name the category')]
    procedure Exclusion_Wins_Over_Inclusion;
  end;

implementation

function TCategoryFilterTests.Passes(const AFilter: TTestFilter;
  const ACategories: array of string): Boolean;
var
  Cats: TArray<string>;
  I: Integer;
begin
  SetLength(Cats, Length(ACategories));
  for I := 0 to High(ACategories) do
    Cats[I] := ACategories[I];
  Result := AFilter.Matches('U', 'C', 'F', 'T', Cats, False);
end;

procedure TCategoryFilterTests.No_Exclusion_Lets_Everything_Through;
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Should(Passes(Filter, ['PostgreSQL'])).BeTrue;
  Should(Passes(Filter, [])).BeTrue;
end;

procedure TCategoryFilterTests.Excluded_Category_Is_Left_Out;
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Filter.ExcludedCategories := ['SoPostgreSQL'];
  Should(Passes(Filter, ['SoPostgreSQL'])).BeFalse;
end;

procedure TCategoryFilterTests.Other_Categories_Stay;
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Filter.ExcludedCategories := ['SoPostgreSQL'];
  Should(Passes(Filter, ['Integracao'])).BeTrue;
  Should(Passes(Filter, [])).BeTrue;
end;

procedure TCategoryFilterTests.One_Excluded_Among_Several_Is_Enough;
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Filter.ExcludedCategories := ['SoPostgreSQL', 'Lento'];
  Should(Passes(Filter, ['Integracao', 'Lento'])).BeFalse;
end;

procedure TCategoryFilterTests.Exclusion_Ignores_Case;
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Filter.ExcludedCategories := ['sopostgresql'];
  Should(Passes(Filter, ['SoPostgreSQL'])).BeFalse;
end;

procedure TCategoryFilterTests.Exclusion_Wins_Over_Inclusion;
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Filter.Categories := ['Integracao'];
  Filter.ExcludedCategories := ['SoPostgreSQL'];
  Should(Passes(Filter, ['Integracao'])).BeTrue;
  Should(Passes(Filter, ['Integracao', 'SoPostgreSQL'])).BeFalse;
end;

end.
