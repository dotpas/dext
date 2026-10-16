unit uIssue447MoraTrunc;

{ Cap. 18b demo fixture — DUnitX style, no Dext Testing attributes.
  Domain stays on Assert.*; the host wires Dext.Testing.DUnitX for the Explorer. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIssue447MoraTrunc = class
  public
    [Test]
    procedure Issue_447_MoraTrunc_KeepsTwoDecimals;
    [Test]
    procedure Issue_447_MoraTrunc_RejectsNegativeDays;
  end;

implementation

procedure TIssue447MoraTrunc.Issue_447_MoraTrunc_KeepsTwoDecimals;
var
  Mora: Double;
begin
  // Stand-in for the 2008 truncation rule from the book narrative.
  Mora := Trunc(12.379 * 100) / 100;
  Assert.AreEqual(12.37, Mora, 0.001);
end;

procedure TIssue447MoraTrunc.Issue_447_MoraTrunc_RejectsNegativeDays;
var
  Days: Integer;
begin
  Days := -1;
  Assert.IsTrue(Days < 0, 'negative days must be rejected by the legacy rule');
end;

initialization
  TDUnitX.RegisterTestFixture(TIssue447MoraTrunc);

end.
