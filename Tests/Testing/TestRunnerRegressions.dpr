{***************************************************************************}
{                                                                           }
{           Dext Framework - Test runner regressions                        }
{                                                                           }
{  Runs the runner against small fixtures and checks the outcome from the   }
{  outside: counts, success flag and exit code.                             }
{                                                                           }
{***************************************************************************}
program TestRunnerRegressions;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Utils,
  System.SysUtils,
  System.IOUtils,
  System.TimeSpan,
  System.Diagnostics,
  Winapi.Windows,
  Dext.Testing,
  Dext.Testing.Integration,
  Dext.Testing.Report;

type
  [TestFixture('Liquidação')]
  [Category('unidade')]
  TLiquidacaoTests = class
  public
    [Test]
    procedure Liquidar_Fatura_Emitida;
    [Test]
    [Category('lenta')]
    procedure Liquidar_Lote;
  end;

type
  [TestFixture('Tabela fiscal')]
  [Category('ciclo')]
  TTabelaFiscalTests = class
  private
    class var FTabela: string;
  public
    [BeforeAll]
    class procedure CarregaTabela;
    [AfterAll]
    class procedure LimpaTabela;
    [Test]
    procedure Tabela_Carregada_No_BeforeAll;
  end;

class procedure TTabelaFiscalTests.CarregaTabela;
begin
  FTabela := 'OK';
end;

class procedure TTabelaFiscalTests.LimpaTabela;
begin
  FTabela := '';
end;

procedure TTabelaFiscalTests.Tabela_Carregada_No_BeforeAll;
begin
  Should(FTabela).Be('OK');
end;

type
  [TestFixture('Timeout')]
  [Category('timeout')]
  TTimeoutTests = class
  private
    FRodando: Boolean;
    FContador: Int64;
  public
    [Test]
    [Timeout(200)]
    procedure Laco_Sem_Fim;
    [Test]
    [Timeout(200)]
    procedure Espera_No_Kernel;
    [Test]
    [Timeout(5000)]
    procedure Dentro_Do_Prazo;
  end;

  [TestFixture('Repeat')]
  [Category('repeat')]
  TRepeatTests = class
  private
    class var FExecucoes: Integer;
  public
    [Test]
    [&Repeat(3)]
    procedure Falha_Na_Segunda;
    [Test]
    [RepeatTest(2)]
    procedure Passa_Nas_Duas;
  end;

  [TestFixture('BeforeAll com falha')]
  [Category('beforeall-falha')]
  TBeforeAllFalhaTests = class
  public
    [BeforeAll]
    class procedure Prepara;
    [Test]
    procedure Nunca_Roda;
  end;

type
  TColetorTimeout = class
  public
    Mensagens: string;
    procedure Coleta(const Info: TTestInfo);
  end;

procedure TColetorTimeout.Coleta(const Info: TTestInfo);
begin
  if Info.Result = trTimeout then
    Mensagens := Mensagens + Info.TestName + ': ' + Info.ErrorMessage + sLineBreak;
end;

procedure TTimeoutTests.Laco_Sem_Fim;
begin
  FRodando := True;
  while FRodando do
    Inc(FContador);
end;

procedure TTimeoutTests.Espera_No_Kernel;
begin
  Sleep(900);
end;

procedure TTimeoutTests.Dentro_Do_Prazo;
begin
  Should(2 + 2).Be(4);
end;

procedure TRepeatTests.Falha_Na_Segunda;
begin
  Inc(FExecucoes);
  Should(FExecucoes).NotBe(2);
end;

procedure TRepeatTests.Passa_Nas_Duas;
begin
  Should(1).Be(1);
end;

class procedure TBeforeAllFalhaTests.Prepara;
begin
  raise Exception.Create('banco indisponível');
end;

procedure TBeforeAllFalhaTests.Nunca_Roda;
begin
end;

procedure TLiquidacaoTests.Liquidar_Fatura_Emitida;
begin
  Should(1250).Be(1250);
end;

procedure TLiquidacaoTests.Liquidar_Lote;
begin
  Should(3).Be(3);
end;

var
  Failures: Integer = 0;

procedure Check(Condition: Boolean; const Name, Detail: string);
begin
  if Condition then
    WriteLn('PASS: ', Name)
  else
  begin
    Inc(Failures);
    WriteLn('FAIL: ', Name, ' -> ', Detail);
  end;
end;

function MakeInfo(const TestName: string; Outcome: TTestResult; Seconds: Double;
  const Error: string = ''): TTestInfo;
begin
  Result.FixtureName := 'Liquidação';
  Result.UnitName := 'Testes.Liquidacao';
  Result.ClassName := 'TLiquidacaoTests';
  Result.TestName := TestName;
  Result.DisplayName := TestName;
  Result.Result := Outcome;
  Result.Duration := TTimeSpan.FromMilliseconds(Seconds * 1000);
  Result.ErrorMessage := Error;
end;

procedure CheckReports;
var
  Infos: TArray<TTestInfo>;
  Info: TTestInfo;
  Json: TJsonReporter;
  Trx: TTRXReporter;
  Sonar: TSonarQubeReporter;
  XUnit: TXUnitReporter;
  Text, Root: string;
  Saved: TFormatSettings;
begin
  Infos := [
    MakeInfo('Liquidar_Fatura_Emitida', trPassed, 1.5),
    MakeInfo('Liquidar_Fatura_Cancelada', trFailed, 0.25, 'Expected 0 but was 1250'),
    MakeInfo('Liquidar_Lote', trSkipped, 0)];

  Saved := FormatSettings;
  FormatSettings.DecimalSeparator := ',';
  FormatSettings.ThousandSeparator := '.';
  try
    Json := TJsonReporter.Create;
    try
      Json.BeginSuite('Liquidação');
      for Info in Infos do Json.AddTestCase(Info);
      Json.EndSuite;
      Text := Json.GenerateJson;
    finally
      Json.Free;
    end;
    Check(Text.Contains('"duration": 1.500') and not Text.Contains('1,500'),
      'JSON report uses "." as decimal separator under a pt-BR locale', Text);

    Trx := TTRXReporter.Create;
    try
      Trx.BeginRun('Dext Test Run');
      Trx.BeginSuite('Liquidação');
      for Info in Infos do Trx.AddTestCase(Info);
      Trx.EndSuite;
      Text := Trx.GenerateXml;
    finally
      Trx.Free;
    end;
    Check(Text.Contains('<TestRun ') and Text.Contains('<UnitTestResult ') and
      Text.Contains('outcome="Failed"') and Text.Contains('outcome="NotExecuted"') and
      Text.Contains('duration="00:00:01.5000000"') and
      Text.Contains('className="Testes.Liquidacao.TLiquidacaoTests"') and
      Text.Contains('<Message>Expected 0 but was 1250</Message>') and
      Text.Contains('total="3" executed="2" passed="1" failed="1"'),
      'TRX report is a real VS TestRun with results, definitions and counters', Text);

    XUnit := TXUnitReporter.Create;
    try
      XUnit.BeginSuite('Liquidação');
      for Info in Infos do XUnit.AddTestCase(Info);
      XUnit.EndSuite;
      Text := XUnit.GenerateXml;
    finally
      XUnit.Free;
    end;
    Check(Text.Contains('total="3" passed="1" failed="1" skipped="1"') and Text.Contains('result="Skip"'),
      'xUnit report does not count skipped tests as passed', Text);
  finally
    FormatSettings := Saved;
  end;

  Root := TPath.Combine(TPath.GetTempPath, 'dext-sonar-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(TPath.Combine(Root, 'Tests'));
  try
    TFile.WriteAllText(TPath.Combine(Root, 'Tests\Testes.Liquidacao.pas'), 'unit Testes.Liquidacao;');
    Sonar := TSonarQubeReporter.Create;
    try
      Sonar.SourceRoot := TPath.Combine(Root, 'Tests');
      Sonar.SetCurrentClassName('Liquidação');
      for Info in Infos do Sonar.AddTestCase(Info);
      Text := Sonar.GenerateXml;
    finally
      Sonar.Free;
    end;
    Check(Text.Contains('<file path="Testes.Liquidacao.pas">'),
      'SonarQube report points to the .pas file of the test unit', Text);
  finally
    TDirectory.Delete(Root, True);
  end;
end;

type
  TFaturaResumo = class
  private
    FStatus: string;
    FEmissao: TDateTime;
  published
    property Status: string read FStatus write FStatus;
    property Emissao: TDateTime read FEmissao write FEmissao;
  end;

procedure CheckFacadeAssertions;
var
  Fatura: TFaturaResumo;
  Message: string;
begin
  Fatura := TFaturaResumo.Create;
  try
    Fatura.Status := 'EMITIDA';
    Fatura.Emissao := Now;
    Message := '';
    try
      Should(TObject(Fatura)).HaveProperty('Status').WhichString.Be('EMITIDA');
      Should(Fatura.Emissao).BeToday;
      Should(Fatura.Emissao).BeSameDateAs(Date).BeAfter(Date - 1).BeGreaterThan(0);
      Should(1.5).Be(1.5);
      Should(Date - 1).BeLessThan(Date);
    except
      on E: Exception do
        Message := E.ClassName + ': ' + E.Message;
    end;
    Check(Message = '', 'HaveProperty and Should(TDateTime) work through the Dext.Testing facade', Message);

    Message := '';
    try
      Should(Fatura.Emissao).Be(EncodeDate(2000, 1, 1));
    except
      on E: Exception do
        Message := E.Message;
    end;
    Check(Message.Contains(DateTimeToStr(EncodeDate(2000, 1, 1))),
      'Should(TDateTime) failure message shows dates, not floating-point numbers', Message);
  finally
    Fatura.Free;
  end;
end;

procedure CheckWillRaiseWithoutClass;
var
  Message: string;
begin
  Message := '';
  try
    Assert.WillRaise(procedure begin end);
  except
    on E: Exception do
      Message := E.ClassName + ': ' + E.Message;
  end;
  Check(Message.StartsWith('EAssertionFailed') and Message.Contains('Expected an exception but none was thrown'),
    'Assert.WillRaise without a class reports a missing exception instead of an access violation', Message);
end;

var
  Ok: Boolean;
  Watch: TStopwatch;
  Coletor: TColetorTimeout;
begin
  SetConsoleCharSet;

  CheckReports;
  CheckWillRaiseWithoutClass;
  CheckFacadeAssertions;

  Ok := TTest.Configure
    .RegisterFixture(TTabelaFiscalTests)
    .RegisterFixture(TBeforeAllFalhaTests)
    .FilterByCategory('ciclo')
    .Run;
  Check(Ok and (TTestRunner.Summary.TotalTests = 1) and (TTestRunner.Summary.Passed = 1),
    '[BeforeAll] and [AfterAll] declared as class procedure run',
    Format('ok=%s total=%d passed=%d', [BoolToStr(Ok, True), TTestRunner.Summary.TotalTests, TTestRunner.Summary.Passed]));

  Ok := TTest.Configure
    .RegisterFixture(TLiquidacaoTests)
    .FilterByCategory('unidade')
    .Run;
  Check(Ok and (TTestRunner.Summary.TotalTests = 2),
    '[Category] on the fixture class applies to its tests',
    Format('ok=%s total=%d', [BoolToStr(Ok, True), TTestRunner.Summary.TotalTests]));

  Ok := TTest.Configure
    .FilterByCategory('lenta')
    .Run;
  Check(Ok and (TTestRunner.Summary.TotalTests = 1),
    '[Category] on the method still filters',
    Format('ok=%s total=%d', [BoolToStr(Ok, True), TTestRunner.Summary.TotalTests]));

  Ok := TTest.Configure
    .FilterByCategory('inexistente')
    .Run;
  Check(not Ok and (TTestRunner.Summary.TotalTests = 0),
    'a run that executes zero tests fails',
    Format('ok=%s total=%d', [BoolToStr(Ok, True), TTestRunner.Summary.TotalTests]));

  Ok := TTest.Configure
    .FilterByCategory('inexistente')
    .AllowEmptyRun
    .Run;
  Check(Ok, 'AllowEmptyRun accepts an empty run', Format('ok=%s', [BoolToStr(Ok, True)]));

  Ok := TTest.Configure
    .FilterByCategory('beforeall-falha')
    .Run;
  Check(not Ok and (TTestRunner.Summary.Failed = 1),
    'a failing [BeforeAll] fails the run',
    Format('ok=%s failed=%d', [BoolToStr(Ok, True), TTestRunner.Summary.Failed]));

  Ok := TTest.Configure
    .RegisterFixture(TRepeatTests)
    .FilterByCategory('repeat')
    .Run;
  Check(not Ok and (TTestRunner.Summary.TotalTests = 5) and (TTestRunner.Summary.Passed = 4) and
    (TTestRunner.Summary.Failed = 1),
    '[RepeatTest] and [&Repeat] count every repetition in the total',
    Format('total=%d passed=%d failed=%d', [TTestRunner.Summary.TotalTests,
      TTestRunner.Summary.Passed, TTestRunner.Summary.Failed]));

  Coletor := TColetorTimeout.Create;
  try
    TTestRunner.OnTestComplete := Coletor.Coleta;
    Watch := TStopwatch.StartNew;
    Ok := TTest.Configure
      .RegisterFixture(TTimeoutTests)
      .FilterByCategory('timeout')
      .Run;
    Watch.Stop;
    TTestRunner.OnTestComplete := nil;
    Check(Coletor.Mensagens.Contains('Laco_Sem_Fim') and Coletor.Mensagens.Contains('Espera_No_Kernel') and
      not Coletor.Mensagens.Contains('keeps running'),
      '[Timeout] interrupts the test thread instead of abandoning it', Coletor.Mensagens);
  finally
    Coletor.Free;
  end;
  Check(not Ok and (TTestRunner.Summary.TotalTests = 3) and (TTestRunner.Summary.Passed = 1) and
    (TTestRunner.Summary.Failed = 2) and (Watch.ElapsedMilliseconds < 4000),
    '[Timeout] stops a test that runs too long and fails it',
    Format('total=%d passed=%d failed=%d elapsed=%dms', [TTestRunner.Summary.TotalTests,
      TTestRunner.Summary.Passed, TTestRunner.Summary.Failed, Watch.ElapsedMilliseconds]));

  WriteLn;
  WriteLn(Format('%d failures', [Failures]));
  if Failures > 0 then
    ExitCode := 1
  else
    ExitCode := 0;
end.
