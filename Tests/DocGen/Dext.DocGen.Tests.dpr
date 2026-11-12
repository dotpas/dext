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
  Dext.Hosting.CLI.Args,
  Dext.Hosting.CLI.Tools.DocGen in '..\..\Apps\CLI\Tools\Dext.Hosting.CLI.Tools.DocGen.pas',
  Dext.Hosting.CLI.Commands.Doc in '..\..\Apps\CLI\Commands\Dext.Hosting.CLI.Commands.Doc.pas';

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

type
  [TestFixture]
  TDocCommandTests = class
  private
    FDir: string;
    FOldDir: string;
    procedure Run(const AArgs: TArray<string>);
  public
    [Setup]
    procedure Prepare;
    [TearDown]
    procedure Clean;
    [Test]
    procedure Relative_Output_Without_Dot_Slash_Is_Created;
    [Test]
    procedure Nested_Relative_Output_Is_Created;
  end;

procedure TDocCommandTests.Prepare;
begin
  FOldDir := GetCurrentDir;
  FDir := TPath.Combine(TPath.GetTempPath, 'dext_doccmd_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(TPath.Combine(FDir, 'src'));
  TFile.WriteAllText(TPath.Combine(FDir, 'src\Amostra.pas'), SOURCE);
  SetCurrentDir(FDir);
end;

procedure TDocCommandTests.Clean;
begin
  SetCurrentDir(FOldDir);
  TDirectory.Delete(FDir, True);
end;

procedure TDocCommandTests.Run(const AArgs: TArray<string>);
var
  Args: TCommandLineArgs;
  Cmd: IConsoleCommand;
begin
  Args := TCommandLineArgs.Create;
  try
    Args.Parse(AArgs);
    Cmd := TDocCommand.Create;
    Cmd.Execute(Args);
  finally
    Args.Free;
  end;
end;

procedure TDocCommandTests.Relative_Output_Without_Dot_Slash_Is_Created;
begin
  Run(['doc', '--input', 'src', '--output', 'saida', '--title', 'T']);
  Should(TFile.Exists(TPath.Combine(FDir, 'saida\index.html'))).BeTrue;
end;

procedure TDocCommandTests.Nested_Relative_Output_Is_Created;
begin
  Run(['doc', '--input', 'src', '--output', 'a\b', '--title', 'T']);
  Should(TFile.Exists(TPath.Combine(FDir, 'a\b\Amostra.html'))).BeTrue;
end;

begin
  SetConsoleCharSet;
  RunTests(TTest.Configure.Verbose.RegisterFixtures([TDocGenTests, TDocCommandTests]));
end.
