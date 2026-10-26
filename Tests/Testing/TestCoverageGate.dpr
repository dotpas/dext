{***************************************************************************}
{                                                                           }
{           Dext Framework - Coverage gate regressions                      }
{                                                                           }
{  Coverage below test.coverage.threshold must make the CLI exit with a     }
{  non-zero code, so a CI pipeline stops instead of going green.            }
{                                                                           }
{***************************************************************************}
program TestCoverageGate;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Utils,
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  Dext.Hosting.CLI,
  Dext.Hosting.CLI.Args,
  Dext.Hosting.CLI.Tools.Sonar;

type
  TGateCommand = class(TInterfacedObject, IConsoleCommand)
  public
    function GetName: string;
    function GetDescription: string;
    procedure Execute(const Args: TCommandLineArgs);
  end;

var
  Failures: Integer = 0;
  WorkDir: string;

function TGateCommand.GetName: string;
begin
  Result := 'gate';
end;

function TGateCommand.GetDescription: string;
begin
  Result := 'Converts a coverage report with the threshold given in --threshold';
end;

procedure TGateCommand.Execute(const Args: TCommandLineArgs);
begin
  TSonarConverter.Convert(
    TPath.Combine(GetCurrentDir, 'CodeCoverage_Summary.xml'),
    TPath.Combine(GetCurrentDir, 'dext_coverage.xml'),
    GetCurrentDir,
    StrToFloat(Args.GetOption('threshold'), TFormatSettings.Invariant));
end;

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

function RunChild(const Params: string): Cardinal;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CommandLine: string;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  CommandLine := Format('"%s" %s', [ParamStr(0), Params]);
  UniqueString(CommandLine);
  if not CreateProcess(nil, PChar(CommandLine), nil, nil, False, 0, nil, PChar(WorkDir), SI, PI) then
    RaiseLastOSError;
  WaitForSingleObject(PI.hProcess, INFINITE);
  GetExitCodeProcess(PI.hProcess, Result);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
end;

procedure RunAsCli;
var
  CLI: TDextCLI;
begin
  CLI := TDextCLI.Create(nil);
  try
    CLI.AddCommand(TGateCommand.Create);
    CLI.Run;
  finally
    CLI.Free;
  end;
end;

var
  Code: Cardinal;
begin
  if ParamStr(1) = 'gate' then
  begin
    RunAsCli;
    Exit;
  end;

  SetConsoleCharSet;
  WorkDir := TPath.Combine(TPath.GetTempPath, 'dext-gate-' + TPath.GetGUIDFileName);
  TDirectory.CreateDirectory(WorkDir);
  try
    TFile.WriteAllText(TPath.Combine(WorkDir, 'Fatura.pas'), 'unit Fatura;');
    // Two of four lines covered: 50%
    TFile.WriteAllText(TPath.Combine(WorkDir, 'CodeCoverage_Summary.xml'),
      '<?xml version="1.0" encoding="UTF-8"?>' +
      '<report><data><linehits><file name="Fatura.pas">10=1;11=3;12=0;13=0</file></linehits></data></report>');

    Code := RunChild('gate --threshold=80');
    Check(Code <> 0, 'coverage below the threshold exits with a non-zero code', Format('exit code %d', [Code]));

    Code := RunChild('gate --threshold=40');
    Check(Code = 0, 'coverage above the threshold exits with zero', Format('exit code %d', [Code]));
  finally
    TDirectory.Delete(WorkDir, True);
  end;

  WriteLn;
  WriteLn(Format('%d failures', [Failures]));
  if Failures > 0 then
    ExitCode := 1
  else
    ExitCode := 0;
end.
