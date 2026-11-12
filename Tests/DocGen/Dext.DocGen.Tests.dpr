program Dext.DocGen.Tests;

// The HTML documentation generator behind "dext doc": parameter names and
// property types must reach the generated page.

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  System.SysUtils,
  System.IOUtils,
  Dext.Testing,
  Dext.Utils,
  Dext.Hosting.CLI.Tools.DocGen in '..\..\Apps\CLI\Tools\Dext.Hosting.CLI.Tools.DocGen.pas';

const
  SOURCE =
    'unit Amostra;' + sLineBreak +
    'interface' + sLineBreak +
    'type' + sLineBreak +
    '  TFatura = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FNumero: Integer;' + sLineBreak +
    '  public' + sLineBreak +
    '    /// <summary>Quita parte da fatura.</summary>' + sLineBreak +
    '    procedure Liquidar(const Valor: Currency; var Saldo: Currency);' + sLineBreak +
    '    function Soma(A, B: Integer): Integer;' + sLineBreak +
    '    property Numero: Integer read FNumero write FNumero;' + sLineBreak +
    '    property Texto: string read FTexto;' + sLineBreak +
    '  end;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

type
  [TestFixture]
  TDocGenTests = class
  private
    FDir: string;
    FPage: string;
  public
    [Setup]
    procedure Generate;
    [TearDown]
    procedure Clean;
    [Test]
    procedure Parameter_Names_Are_Kept_With_Their_Modifier;
    [Test]
    procedure Parameters_Sharing_A_Type_Are_Listed_One_By_One;
    [Test]
    procedure Property_Types_Are_Shown;
    [Test]
    procedure Xml_Summary_Reaches_The_Page;
    [Test]
    procedure Index_Page_Carries_The_Project_Title;
  end;

procedure TDocGenTests.Generate;
var
  G: TDextDocGenerator;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'dext_docgen_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(FDir, 'src'));
  TDirectory.CreateDirectory(TPath.Combine(FDir, 'out'));
  TFile.WriteAllText(TPath.Combine(FDir, 'src\Amostra.pas'), SOURCE);
  G := TDextDocGenerator.Create(
    '<h1>{{TITLE}}</h1>{{PROJECT_TITLE}}{{MAIN_CONTENT}}',
    TPath.Combine(FDir, 'out'), 'Teste');
  try
    G.Generate(TPath.Combine(FDir, 'src'));
  finally
    G.Free;
  end;
  FPage := TFile.ReadAllText(TPath.Combine(FDir, 'out\Amostra.html'));
end;

procedure TDocGenTests.Clean;
begin
  TDirectory.Delete(FDir, True);
end;

procedure TDocGenTests.Parameter_Names_Are_Kept_With_Their_Modifier;
begin
  Should(FPage).Contain(
    'procedure Liquidar(const Valor: Currency; var Saldo: Currency)');
end;

procedure TDocGenTests.Parameters_Sharing_A_Type_Are_Listed_One_By_One;
begin
  Should(FPage).Contain('function Soma(A: Integer; B: Integer): Integer');
end;

procedure TDocGenTests.Property_Types_Are_Shown;
begin
  Should(FPage).Contain('property Numero: Integer');
  Should(FPage).Contain('property Texto: string');
end;

procedure TDocGenTests.Xml_Summary_Reaches_The_Page;
begin
  Should(FPage).Contain('Quita parte da fatura.');
end;

procedure TDocGenTests.Index_Page_Carries_The_Project_Title;
begin
  Should(TFile.ReadAllText(TPath.Combine(FDir, 'out\index.html')))
    .Contain('<h1>Teste</h1><p>Select a unit');
end;

begin
  SetConsoleCharSet;
  RunTests(TTest.Configure.Verbose.RegisterFixtures([TDocGenTests]));
end.
