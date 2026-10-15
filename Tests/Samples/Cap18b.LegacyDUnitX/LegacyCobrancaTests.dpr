program LegacyCobrancaTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

{ Cap. 18b — legacy DUnitX host + Dext Explorer adapter (no [Fact] rewrite).
  See Docs/Plans/Dext-Testing-Cap18b-Explorer-Demo.md }

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  Dext.Testing.Integration,
  Dext.Testing.DUnitX,
  uIssue447MoraTrunc in 'uIssue447MoraTrunc.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
begin
  try
    // Explorer / CLI: --port N → adapter runs the suite and streams results.
    if TTestRunnerRegistry.TryExecuteFromCommandLine then
      Exit;

    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    Results := Runner.Execute;
    if not Results.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
