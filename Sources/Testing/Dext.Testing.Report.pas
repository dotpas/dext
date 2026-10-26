{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}

unit Dext.Testing.Report;

interface

uses
  System.Classes,
  System.DateUtils,
  System.IOUtils,
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Text.Escaping,
  Dext.Testing.Integration;

type
  TReportFormat = (rfJUnit, rfXUnit, rfJSON, rfSonarQube, rfTRX);

  TTestCaseReport = class
  public
    ClassName: string;
    FilePath: string;
    TestName: string;
    Duration: Double;
    Status: TTestResult;
    ErrorMessage: string;
    StackTrace: string;
  end;

  TTestSuiteReport = class
  public
    Name: string;
    Tests: Integer;
    Failures: Integer;
    Errors: Integer;
    Skipped: Integer;
    Duration: Double;
    Timestamp: TDateTime;
    TestCases: TArray<TTestCaseReport>;
    destructor Destroy; override;
  end;

  TJUnitReporter = class
  private
    FTestSuites: IList<TTestSuiteReport>;
    FCurrentSuite: TTestSuiteReport;
    FCurrentTestCases: IList<TTestCaseReport>;
    function FormatDuration(Seconds: Double): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginSuite(const Name: string);
    procedure AddTestCase(const Info: TTestInfo);
    procedure EndSuite;
    function GenerateXml: string;
    procedure SaveToFile(const FileName: string);
    procedure Clear;
  end;

  TJsonReporter = class
  private
    FTestSuites: IList<TTestSuiteReport>;
    FCurrentSuite: TTestSuiteReport;
    FCurrentTestCases: IList<TTestCaseReport>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginSuite(const Name: string);
    procedure AddTestCase(const Info: TTestInfo);
    procedure EndSuite;
    function GenerateJson: string;
    procedure SaveToFile(const FileName: string);
    procedure Clear;
  end;

  TSonarQubeReporter = class
  private
    FTestCases: IList<TTestCaseReport>;
    FCurrentClassName: string;
    FSourceRoot: string;
    function ResolveSourcePath(const AUnitName: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetCurrentClassName(const Name: string);
    /// <summary>
    ///   Directory the file paths are made relative to (sonar.projectBaseDir).
    ///   Defaults to the current directory.
    /// </summary>
    property SourceRoot: string read FSourceRoot write FSourceRoot;
    procedure AddTestCase(const Info: TTestInfo);
    function GenerateXml: string;
    procedure SaveToFile(const FileName: string);
    procedure Clear;
  end;

  TXUnitReporter = class
  private
    FTestSuites: IList<TTestSuiteReport>;
    FCurrentSuite: TTestSuiteReport;
    FCurrentTestCases: IList<TTestCaseReport>;
    function FormatDuration(Seconds: Double): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginSuite(const Name: string);
    procedure AddTestCase(const Info: TTestInfo);
    procedure EndSuite;
    function GenerateXml: string;
    procedure SaveToFile(const FileName: string);
    procedure Clear;
  end;

  TTRXReporter = class
  private
    FTestSuites: IList<TTestSuiteReport>;
    FCurrentSuite: TTestSuiteReport;
    FCurrentTestCases: IList<TTestCaseReport>;
    FRunId: TGUID;
    FRunName: string;
    FStartTime: TDateTime;
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginRun(const RunName: string);
    procedure BeginSuite(const Name: string);
    procedure AddTestCase(const Info: TTestInfo);
    procedure EndSuite;
    function GenerateXml: string;
    procedure SaveToFile(const FileName: string);
    procedure Clear;
  end;

  THTMLReporter = class
  private
    FTestSuites: IList<TTestSuiteReport>;
    FCurrentSuite: TTestSuiteReport;
    FCurrentTestCases: IList<TTestCaseReport>;
    FReportTitle: string;
    function GetStatusClass(Status: TTestResult): string;
    function GetStatusIcon(Status: TTestResult): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetTitle(const Title: string);
    procedure BeginSuite(const Name: string);
    procedure AddTestCase(const Info: TTestInfo);
    procedure EndSuite;
    function GenerateHtml: string;
    procedure SaveToFile(const FileName: string);
    procedure Clear;
  end;

implementation

uses
  System.NetEncoding,
  System.StrUtils;

/// <summary>Formats with '.' as decimal separator whatever the machine locale.</summary>
function InvariantFormat(const Fmt: string; const Args: array of const): string;
begin
  Result := Format(Fmt, Args, TFormatSettings.Invariant);
end;

{ TTestSuiteReport }

destructor TTestSuiteReport.Destroy;
var
  Item: TTestCaseReport;
begin
  for Item in TestCases do
    Item.Free;
  inherited;
end;

{ TJUnitReporter }

constructor TJUnitReporter.Create;
begin
  inherited Create;
  FTestSuites := TCollections.CreateList<TTestSuiteReport>(True);
  FCurrentTestCases := TCollections.CreateList<TTestCaseReport>(False);
end;

destructor TJUnitReporter.Destroy;
begin
  inherited;
end;

function TJUnitReporter.FormatDuration(Seconds: Double): string;
begin
  Result := FormatFloat('0.000', Seconds).Replace(',', '.');
end;

procedure TJUnitReporter.BeginSuite(const Name: string);
begin
  FCurrentSuite := TTestSuiteReport.Create;
  FCurrentSuite.Name := Name;
  FCurrentSuite.Timestamp := Now;
  FCurrentTestCases.Clear;
end;

procedure TJUnitReporter.AddTestCase(const Info: TTestInfo);
var
  TC: TTestCaseReport;
begin
  TC := TTestCaseReport.Create;
  TC.ClassName := Info.FixtureName;
  TC.TestName := Info.DisplayName;
  TC.Duration := Info.Duration.TotalSeconds;
  TC.Status := Info.Result;
  TC.ErrorMessage := Info.ErrorMessage;
  TC.StackTrace := Info.StackTrace;

  FCurrentTestCases.Add(TC);

  Inc(FCurrentSuite.Tests);
  case Info.Result of
    trFailed: Inc(FCurrentSuite.Failures);
    trError, trTimeout: Inc(FCurrentSuite.Errors);
    trSkipped: Inc(FCurrentSuite.Skipped);
  end;
  FCurrentSuite.Duration := FCurrentSuite.Duration + TC.Duration;
end;

procedure TJUnitReporter.EndSuite;
begin
  FCurrentSuite.TestCases := FCurrentTestCases.ToArray;
  FCurrentTestCases.Clear;
  FTestSuites.Add(FCurrentSuite);
end;

function TJUnitReporter.GenerateXml: string;
var
  SB: TStringBuilder;
  Suite: TTestSuiteReport;
  TC: TTestCaseReport;
  TotalTests, TotalFailures, TotalErrors, TotalSkipped: Integer;
  TotalTime: Double;
begin
  SB := TStringBuilder.Create;
  try
    TotalTests := 0; TotalFailures := 0; TotalErrors := 0; TotalSkipped := 0; TotalTime := 0;
    for Suite in FTestSuites do
    begin
      Inc(TotalTests, Suite.Tests);
      Inc(TotalFailures, Suite.Failures);
      Inc(TotalErrors, Suite.Errors);
      Inc(TotalSkipped, Suite.Skipped);
      TotalTime := TotalTime + Suite.Duration;
    end;

    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    SB.AppendFormat('<testsuites tests="%d" failures="%d" errors="%d" skipped="%d" time="%s">',
      [TotalTests, TotalFailures, TotalErrors, TotalSkipped, FormatDuration(TotalTime)]);
    SB.AppendLine;

    for Suite in FTestSuites do
    begin
      SB.AppendFormat('  <testsuite name="%s" tests="%d" failures="%d" errors="%d" skipped="%d" time="%s" timestamp="%s">',
        [TDextEscaping.Xml(Suite.Name), Suite.Tests, Suite.Failures, Suite.Errors, Suite.Skipped,
         FormatDuration(Suite.Duration), FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Suite.Timestamp)]);
      SB.AppendLine;

      for TC in Suite.TestCases do
      begin
        SB.AppendFormat('    <testcase classname="%s" name="%s" time="%s"',
          [TDextEscaping.Xml(TC.ClassName), TDextEscaping.Xml(TC.TestName), FormatDuration(TC.Duration)]);

        case TC.Status of
          trPassed: SB.AppendLine('/>');
          trFailed, trError, trTimeout:
            begin
              SB.AppendLine('>');
              SB.AppendFormat('      <%s message="%s">%s</%s>',
                [IfThen(TC.Status = trError, 'error', 'failure'), TDextEscaping.Xml(TC.ErrorMessage), 
                 TDextEscaping.Xml(TC.StackTrace), IfThen(TC.Status = trError, 'error', 'failure')]);
              SB.AppendLine;
              SB.AppendLine('    </testcase>');
            end;
          trSkipped:
            begin
              SB.AppendLine('>');
              SB.AppendFormat('      <skipped message="%s"/>', [TDextEscaping.Xml(TC.ErrorMessage)]);
              SB.AppendLine;
              SB.AppendLine('    </testcase>');
            end;
        end;
      end;
      SB.AppendLine('  </testsuite>');
    end;
    SB.AppendLine('</testsuites>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TJUnitReporter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, GenerateXml, TEncoding.UTF8);
end;

procedure TJUnitReporter.Clear;
begin
  FTestSuites.Clear;
  FCurrentTestCases.Clear;
end;

{ TJsonReporter }

constructor TJsonReporter.Create;
begin
  inherited Create;
  FTestSuites := TCollections.CreateList<TTestSuiteReport>(True);
  FCurrentTestCases := TCollections.CreateList<TTestCaseReport>(False);
end;

destructor TJsonReporter.Destroy;
begin
  inherited;
end;

procedure TJsonReporter.BeginSuite(const Name: string);
begin
  FCurrentSuite := TTestSuiteReport.Create;
  FCurrentSuite.Name := Name;
  FCurrentSuite.Timestamp := Now;
  FCurrentTestCases.Clear;
end;

procedure TJsonReporter.AddTestCase(const Info: TTestInfo);
var
  TC: TTestCaseReport;
begin
  TC := TTestCaseReport.Create;
  TC.ClassName := Info.FixtureName;
  TC.TestName := Info.DisplayName;
  TC.Duration := Info.Duration.TotalSeconds;
  TC.Status := Info.Result;
  TC.ErrorMessage := Info.ErrorMessage;
  TC.StackTrace := Info.StackTrace;
  FCurrentTestCases.Add(TC);
  Inc(FCurrentSuite.Tests);
  case Info.Result of
    trFailed: Inc(FCurrentSuite.Failures);
    trError, trTimeout: Inc(FCurrentSuite.Errors);
    trSkipped: Inc(FCurrentSuite.Skipped);
  end;
  FCurrentSuite.Duration := FCurrentSuite.Duration + TC.Duration;
end;

procedure TJsonReporter.EndSuite;
begin
  FCurrentSuite.TestCases := FCurrentTestCases.ToArray;
  FCurrentTestCases.Clear;
  FTestSuites.Add(FCurrentSuite);
end;

function TJsonReporter.GenerateJson: string;
var
  SB: TStringBuilder;
  Suite: TTestSuiteReport;
  TC: TTestCaseReport;
  I, J: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('{ "testSuites": [');
    for I := 0 to FTestSuites.Count - 1 do
    begin
      Suite := FTestSuites[I];
      if I > 0 then SB.AppendLine(',');
      SB.AppendLine('  {');
      SB.Append(InvariantFormat('    "name": "%s", "tests": %d, "failures": %d, "errors": %d, "skipped": %d, "duration": %.3f, "timestamp": "%s", "testCases": [',
        [TDextEscaping.Json(Suite.Name), Suite.Tests, Suite.Failures, Suite.Errors, Suite.Skipped, Suite.Duration, 
         FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', Suite.Timestamp)])).AppendLine;
      for J := 0 to High(Suite.TestCases) do
      begin
        TC := Suite.TestCases[J];
        if J > 0 then SB.AppendLine(',');
        SB.Append(InvariantFormat('      { "className": "%s", "testName": "%s", "duration": %.3f, "status": "%d", "errorMessage": "%s" }',
          [TDextEscaping.Json(TC.ClassName), TDextEscaping.Json(TC.TestName), TC.Duration, Ord(TC.Status), TDextEscaping.Json(TC.ErrorMessage)]));
      end;
      SB.AppendLine(' ] }');
    end;
    SB.AppendLine('] }');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TJsonReporter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, GenerateJson, TEncoding.UTF8);
end;

procedure TJsonReporter.Clear;
begin
  FTestSuites.Clear;
  FCurrentTestCases.Clear;
end;

{ TSonarQubeReporter }

constructor TSonarQubeReporter.Create;
begin
  inherited Create;
  FTestCases := TCollections.CreateList<TTestCaseReport>(True);
  FSourceRoot := GetCurrentDir;
end;

function TSonarQubeReporter.ResolveSourcePath(const AUnitName: string): string;
var
  FileName, Base, Candidate: string;
  Level: Integer;

  function TryBase(const ADir: string): Boolean;
  begin
    Candidate := TPath.Combine(ADir, FileName);
    Result := FileExists(Candidate);
  end;

begin
  // Sonar needs the test file path relative to the project base directory
  FileName := AUnitName + '.pas';
  if TryBase(FSourceRoot) then
    Exit(ExtractRelativePath(IncludeTrailingPathDelimiter(FSourceRoot), Candidate).Replace('\', '/'));

  // Test executables usually live a few levels below the project (Win32\Debug)
  Base := ExtractFileDir(ParamStr(0));
  for Level := 0 to 3 do
  begin
    if TryBase(Base) then
      Exit(ExtractRelativePath(IncludeTrailingPathDelimiter(FSourceRoot), Candidate).Replace('\', '/'));
    Base := ExtractFileDir(Base);
  end;

  Result := FileName;
end;

destructor TSonarQubeReporter.Destroy;
begin
  inherited;
end;

procedure TSonarQubeReporter.SetCurrentClassName(const Name: string);
begin
  FCurrentClassName := Name;
end;

procedure TSonarQubeReporter.AddTestCase(const Info: TTestInfo);
var
  TC: TTestCaseReport;
begin
  TC := TTestCaseReport.Create;
  TC.ClassName := FCurrentClassName;
  if TC.ClassName = '' then TC.ClassName := Info.FixtureName;
  if Info.UnitName <> '' then
    TC.FilePath := ResolveSourcePath(Info.UnitName)
  else
    TC.FilePath := ResolveSourcePath(TC.ClassName);
  TC.TestName := Info.DisplayName;
  TC.Duration := Info.Duration.TotalMilliseconds;
  TC.Status := Info.Result;
  TC.ErrorMessage := Info.ErrorMessage;
  TC.StackTrace := Info.StackTrace;
  FTestCases.Add(TC);
end;

function TSonarQubeReporter.GenerateXml: string;
var
  SB: TStringBuilder;
  TC: TTestCaseReport;
  Paths: TStringList;
  Path: string;
  Tag: string;
begin
  SB := TStringBuilder.Create;
  Paths := TStringList.Create;
  try
    Paths.Duplicates := dupIgnore;
    Paths.CaseSensitive := False;
    for TC in FTestCases do
      if Paths.IndexOf(TC.FilePath) < 0 then
        Paths.Add(TC.FilePath);

    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    SB.AppendLine('<testExecutions version="1">');
    for Path in Paths do
    begin
      SB.AppendFormat('  <file path="%s">', [TDextEscaping.Xml(Path)]);
      SB.AppendLine;
      for TC in FTestCases do
      begin
        if not SameText(TC.FilePath, Path) then
          Continue;
        SB.AppendFormat('    <testCase name="%s" duration="%d"',
          [TDextEscaping.Xml(TC.TestName), Round(TC.Duration)]);
        if TC.Status = trPassed then
          SB.AppendLine('/>')
        else
        begin
          SB.AppendLine('>');
          if TC.Status = trSkipped then
            Tag := 'skipped'
          else if TC.Status = trError then
            Tag := 'error'
          else
            Tag := 'failure';
          SB.AppendFormat('      <%s message="%s">%s</%s>',
            [Tag, TDextEscaping.Xml(TC.ErrorMessage), TDextEscaping.Xml(TC.StackTrace), Tag]);
          SB.AppendLine;
          SB.AppendLine('    </testCase>');
        end;
      end;
      SB.AppendLine('  </file>');
    end;
    SB.AppendLine('</testExecutions>');
    Result := SB.ToString;
  finally
    Paths.Free;
    SB.Free;
  end;
end;

procedure TSonarQubeReporter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, GenerateXml, TEncoding.UTF8);
end;

procedure TSonarQubeReporter.Clear;
begin
  FTestCases.Clear;
end;

{ TXUnitReporter }

constructor TXUnitReporter.Create;
begin
  inherited Create;
  FTestSuites := TCollections.CreateList<TTestSuiteReport>(True);
  FCurrentTestCases := TCollections.CreateList<TTestCaseReport>(False);
end;

destructor TXUnitReporter.Destroy;
begin
  inherited;
end;

function TXUnitReporter.FormatDuration(Seconds: Double): string;
begin
  Result := FormatFloat('0.000000', Seconds).Replace(',', '.');
end;

procedure TXUnitReporter.BeginSuite(const Name: string);
begin
  FCurrentSuite := TTestSuiteReport.Create;
  FCurrentSuite.Name := Name;
  FCurrentSuite.Timestamp := Now;
  FCurrentTestCases.Clear;
end;

procedure TXUnitReporter.AddTestCase(const Info: TTestInfo);
var
  TC: TTestCaseReport;
begin
  TC := TTestCaseReport.Create;
  TC.ClassName := Info.FixtureName;
  TC.TestName := Info.DisplayName;
  TC.Duration := Info.Duration.TotalSeconds;
  TC.Status := Info.Result;
  TC.ErrorMessage := Info.ErrorMessage;
  TC.StackTrace := Info.StackTrace;
  FCurrentTestCases.Add(TC);
  Inc(FCurrentSuite.Tests);
  case Info.Result of
    trFailed: Inc(FCurrentSuite.Failures);
    trError, trTimeout: Inc(FCurrentSuite.Errors);
    trSkipped: Inc(FCurrentSuite.Skipped);
  end;
  FCurrentSuite.Duration := FCurrentSuite.Duration + TC.Duration;
end;

procedure TXUnitReporter.EndSuite;
begin
  FCurrentSuite.TestCases := FCurrentTestCases.ToArray;
  FCurrentTestCases.Clear;
  FTestSuites.Add(FCurrentSuite);
end;

function TXUnitReporter.GenerateXml: string;
var
  SB: TStringBuilder;
  Suite: TTestSuiteReport;
  TC: TTestCaseReport;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?><assemblies>');
    for Suite in FTestSuites do
    begin
      SB.AppendFormat('  <assembly name="%s" time="%s" total="%d" passed="%d" failed="%d" skipped="%d">',
        [TDextEscaping.Xml(Suite.Name), FormatDuration(Suite.Duration), Suite.Tests,
         Suite.Tests - Suite.Failures - Suite.Errors - Suite.Skipped, Suite.Failures + Suite.Errors, Suite.Skipped]);
      for TC in Suite.TestCases do
      begin
        SB.AppendFormat('    <test name="%s" time="%s" result="%s"', [TDextEscaping.Xml(TC.TestName), FormatDuration(TC.Duration),
          IfThen(TC.Status = trPassed, 'Pass', IfThen(TC.Status = trSkipped, 'Skip', 'Fail'))]);
        if TC.Status = trPassed then SB.AppendLine('/>')
        else if TC.Status = trSkipped then
          SB.AppendLine('><reason>' + TDextEscaping.Xml(TC.ErrorMessage) + '</reason></test>')
        else
        begin
          SB.AppendLine('><failure><message>' + TDextEscaping.Xml(TC.ErrorMessage) + '</message></failure></test>');
        end;
      end;
      SB.AppendLine('  </assembly>');
    end;
    SB.AppendLine('</assemblies>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TXUnitReporter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, GenerateXml, TEncoding.UTF8);
end;

procedure TXUnitReporter.Clear;
begin
  FTestSuites.Clear;
  FCurrentTestCases.Clear;
end;

{ TTRXReporter }

constructor TTRXReporter.Create;
begin
  inherited Create;
  FTestSuites := TCollections.CreateList<TTestSuiteReport>(True);
  FCurrentTestCases := TCollections.CreateList<TTestCaseReport>(False);
  System.SysUtils.CreateGUID(FRunId);
  FStartTime := Now;
  FRunName := 'Dext Test Run';
end;

destructor TTRXReporter.Destroy;
begin
  inherited;
end;

procedure TTRXReporter.BeginRun(const RunName: string);
begin
  FRunName := RunName;
end;

procedure TTRXReporter.BeginSuite(const Name: string);
begin
  FCurrentSuite := TTestSuiteReport.Create;
  FCurrentSuite.Name := Name;
  FCurrentSuite.Timestamp := Now;
  FCurrentTestCases.Clear;
end;

procedure TTRXReporter.AddTestCase(const Info: TTestInfo);
var
  TC: TTestCaseReport;
begin
  TC := TTestCaseReport.Create;
  if Info.ClassName = '' then
    TC.ClassName := Info.FixtureName
  else if Info.UnitName <> '' then
    TC.ClassName := Info.UnitName + '.' + Info.ClassName
  else
    TC.ClassName := Info.ClassName;
  TC.TestName := Info.DisplayName;
  if TC.TestName = '' then TC.TestName := Info.TestName;
  TC.Duration := Info.Duration.TotalSeconds;
  TC.Status := Info.Result;
  TC.ErrorMessage := Info.ErrorMessage;
  TC.StackTrace := Info.StackTrace;
  FCurrentTestCases.Add(TC);
  Inc(FCurrentSuite.Tests);
  case Info.Result of
    trFailed: Inc(FCurrentSuite.Failures);
    trError, trTimeout: Inc(FCurrentSuite.Errors);
    trSkipped: Inc(FCurrentSuite.Skipped);
  end;
  FCurrentSuite.Duration := FCurrentSuite.Duration + TC.Duration;
end;

procedure TTRXReporter.EndSuite;
begin
  FCurrentSuite.TestCases := FCurrentTestCases.ToArray;
  FCurrentTestCases.Clear;
  FTestSuites.Add(FCurrentSuite);
end;

function TrxGuid: string;
var
  G: TGUID;
begin
  System.SysUtils.CreateGUID(G);
  Result := G.ToString.Substring(1, 36).ToLower;
end;

function TrxDateTime(const Value: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Value, TFormatSettings.Invariant);
end;

function TrxDuration(Seconds: Double): string;
var
  Ticks: Int64;
begin
  if Seconds < 0 then Seconds := 0;
  Ticks := Round(Seconds * 10000000);
  Result := InvariantFormat('%.2d:%.2d:%.2d.%.7d',
    [Ticks div 36000000000, (Ticks div 600000000) mod 60, (Ticks div 10000000) mod 60, Ticks mod 10000000]);
end;

function TrxOutcome(Status: TTestResult): string;
begin
  case Status of
    trPassed: Result := 'Passed';
    trSkipped: Result := 'NotExecuted';
    trTimeout: Result := 'Timeout';
    trNone: Result := 'NotExecuted';
  else
    Result := 'Failed';
  end;
end;

function TTRXReporter.GenerateXml: string;
const
  UnitTestType = '13cdc9d9-ddb5-4fa4-a97d-d965ccfc6d4b';
  ResultsNotInAList = '8c84fa94-04c1-424b-9868-57a2d4851a1d';
  AllLoadedResults = '19431567-8539-422a-85d7-44ee4e166bda';
type
  TTrxEntry = record
    Test: TTestCaseReport;
    TestId: string;
    ExecutionId: string;
    StartTime: TDateTime;
  end;
var
  SB: TStringBuilder;
  Entries: TArray<TTrxEntry>;
  Entry: TTrxEntry;
  Suite: TTestSuiteReport;
  TC: TTestCaseReport;
  Clock: TDateTime;
  CodeBase, Computer, Storage: string;
  Total, Passed, Failed, NotExecuted, Timeouts: Integer;
begin
  Clock := FStartTime;
  Total := 0; Passed := 0; Failed := 0; NotExecuted := 0; Timeouts := 0;
  for Suite in FTestSuites do
    for TC in Suite.TestCases do
    begin
      Entry.Test := TC;
      Entry.TestId := TrxGuid;
      Entry.ExecutionId := TrxGuid;
      Entry.StartTime := Clock;
      Clock := Clock + TC.Duration / SecsPerDay;
      Entries := Entries + [Entry];
      Inc(Total);
      case TC.Status of
        trPassed: Inc(Passed);
        trSkipped, trNone: Inc(NotExecuted);
        trTimeout: Inc(Timeouts);
      else
        Inc(Failed);
      end;
    end;

  CodeBase := TDextEscaping.Xml(ParamStr(0));
  Storage := TDextEscaping.Xml(ExtractFileName(ParamStr(0)).ToLower);
  Computer := TDextEscaping.Xml(GetEnvironmentVariable('COMPUTERNAME'));

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('<?xml version="1.0" encoding="UTF-8"?>');
    SB.AppendFormat('<TestRun id="%s" name="%s" runUser="%s" xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010">',
      [FRunId.ToString.Substring(1, 36).ToLower, TDextEscaping.Xml(FRunName),
       TDextEscaping.Xml(GetEnvironmentVariable('USERNAME'))]).AppendLine;
    SB.AppendFormat('  <Times creation="%0:s" queuing="%0:s" start="%0:s" finish="%1:s" />',
      [TrxDateTime(FStartTime), TrxDateTime(Clock)]).AppendLine;

    SB.AppendLine('  <Results>');
    for Entry in Entries do
    begin
      TC := Entry.Test;
      SB.AppendFormat('    <UnitTestResult executionId="%s" testId="%s" testName="%s" computerName="%s" ' +
        'duration="%s" startTime="%s" endTime="%s" testType="%s" outcome="%s" testListId="%s"',
        [Entry.ExecutionId, Entry.TestId, TDextEscaping.Xml(TC.TestName), Computer,
         TrxDuration(TC.Duration), TrxDateTime(Entry.StartTime),
         TrxDateTime(Entry.StartTime + TC.Duration / SecsPerDay), UnitTestType,
         TrxOutcome(TC.Status), ResultsNotInAList]);
      if (TC.ErrorMessage = '') and (TC.StackTrace = '') then
        SB.AppendLine(' />')
      else
      begin
        SB.AppendLine('>');
        SB.AppendLine('      <Output>');
        if TC.Status = trSkipped then
          SB.AppendFormat('        <StdOut>%s</StdOut>', [TDextEscaping.Xml(TC.ErrorMessage)]).AppendLine
        else
        begin
          SB.AppendLine('        <ErrorInfo>');
          SB.AppendFormat('          <Message>%s</Message>', [TDextEscaping.Xml(TC.ErrorMessage)]).AppendLine;
          if TC.StackTrace <> '' then
            SB.AppendFormat('          <StackTrace>%s</StackTrace>', [TDextEscaping.Xml(TC.StackTrace)]).AppendLine;
          SB.AppendLine('        </ErrorInfo>');
        end;
        SB.AppendLine('      </Output>');
        SB.AppendLine('    </UnitTestResult>');
      end;
    end;
    SB.AppendLine('  </Results>');

    SB.AppendLine('  <TestDefinitions>');
    for Entry in Entries do
    begin
      TC := Entry.Test;
      SB.AppendFormat('    <UnitTest name="%s" storage="%s" id="%s">',
        [TDextEscaping.Xml(TC.TestName), Storage, Entry.TestId]).AppendLine;
      SB.AppendFormat('      <Execution id="%s" />', [Entry.ExecutionId]).AppendLine;
      SB.AppendFormat('      <TestMethod codeBase="%s" adapterTypeName="executor://dext/testing" className="%s" name="%s" />',
        [CodeBase, TDextEscaping.Xml(TC.ClassName), TDextEscaping.Xml(TC.TestName)]).AppendLine;
      SB.AppendLine('    </UnitTest>');
    end;
    SB.AppendLine('  </TestDefinitions>');

    SB.AppendLine('  <TestEntries>');
    for Entry in Entries do
      SB.AppendFormat('    <TestEntry testId="%s" executionId="%s" testListId="%s" />',
        [Entry.TestId, Entry.ExecutionId, ResultsNotInAList]).AppendLine;
    SB.AppendLine('  </TestEntries>');

    SB.AppendLine('  <TestLists>');
    SB.AppendFormat('    <TestList name="Results Not in a List" id="%s" />', [ResultsNotInAList]).AppendLine;
    SB.AppendFormat('    <TestList name="All Loaded Results" id="%s" />', [AllLoadedResults]).AppendLine;
    SB.AppendLine('  </TestLists>');

    SB.AppendFormat('  <ResultSummary outcome="%s">', [IfThen((Failed + Timeouts) > 0, 'Failed', 'Completed')]).AppendLine;
    SB.AppendFormat('    <Counters total="%d" executed="%d" passed="%d" failed="%d" error="0" timeout="%d" ' +
      'aborted="0" inconclusive="0" passedButRunAborted="0" notRunnable="0" notExecuted="%d" ' +
      'disconnected="0" warning="0" completed="0" inProgress="0" pending="0" />',
      [Total, Total - NotExecuted, Passed, Failed, Timeouts, NotExecuted]).AppendLine;
    SB.AppendLine('  </ResultSummary>');
    SB.AppendLine('</TestRun>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TTRXReporter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, GenerateXml, TEncoding.UTF8);
end;

procedure TTRXReporter.Clear;
begin
  FCurrentTestCases.Clear;
  FTestSuites.Clear;
end;

{ THTMLReporter }

constructor THTMLReporter.Create;
begin
  inherited Create;
  FTestSuites := TCollections.CreateList<TTestSuiteReport>(True);
  FCurrentTestCases := TCollections.CreateList<TTestCaseReport>(False);
  FReportTitle := 'Dext Test Report';
end;

destructor THTMLReporter.Destroy;
begin
  inherited;
end;

function THTMLReporter.GetStatusClass(Status: TTestResult): string;
begin
  case Status of
    trPassed: Result := 'passed';
    trFailed, trError, trTimeout: Result := 'failed';
    trSkipped: Result := 'skipped';
  else Result := 'unknown';
  end;
end;

function THTMLReporter.GetStatusIcon(Status: TTestResult): string;
begin
  case Status of
    trPassed: Result := '&#10004;';
    trFailed, trError, trTimeout: Result := '&#10008;';
  else Result := '&#63;';
  end;
end;

procedure THTMLReporter.SetTitle(const Title: string);
begin
  FReportTitle := Title;
end;

procedure THTMLReporter.BeginSuite(const Name: string);
begin
  FCurrentSuite := TTestSuiteReport.Create;
  FCurrentSuite.Name := Name;
  FCurrentSuite.Timestamp := Now;
  FCurrentTestCases.Clear;
end;

procedure THTMLReporter.AddTestCase(const Info: TTestInfo);
var
  TC: TTestCaseReport;
begin
  TC := TTestCaseReport.Create;
  TC.ClassName := Info.FixtureName; TC.TestName := Info.DisplayName;
  TC.Duration := Info.Duration.TotalSeconds; TC.Status := Info.Result;
  TC.ErrorMessage := Info.ErrorMessage; TC.StackTrace := Info.StackTrace;
  FCurrentTestCases.Add(TC);
  Inc(FCurrentSuite.Tests);
  case Info.Result of
    trFailed, trTimeout: Inc(FCurrentSuite.Failures);
    trError: Inc(FCurrentSuite.Errors);
    trSkipped: Inc(FCurrentSuite.Skipped);
  end;
  FCurrentSuite.Duration := FCurrentSuite.Duration + TC.Duration;
end;

procedure THTMLReporter.EndSuite;
begin
  FCurrentSuite.TestCases := FCurrentTestCases.ToArray;
  FCurrentTestCases.Clear;
  FTestSuites.Add(FCurrentSuite);
end;

function THTMLReporter.GenerateHtml: string;
const
  HTML_HEAD =
    '<!DOCTYPE html>' + #13#10 +
    '<html lang="en">' + #13#10 +
    '<head>' + #13#10 +
    '  <meta charset="UTF-8">' + #13#10 +
    '  <meta name="viewport" content="width=device-width, initial-scale=1.0">' + #13#10 +
    '  <title>%s</title>' + #13#10 +
    '  <style>' + #13#10 +
    '    :root { --bg: #0f172a; --card: #1e293b; --accent: #3b82f6; --success: #22c55e; --fail: #ef4444; --warn: #f59e0b; --text: #f8fafc; }' + #13#10 +
    '    * { box-sizing: border-box; margin: 0; padding: 0; }' + #13#10 +
    '    body { font-family: "Inter", system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; padding: 2rem; }' + #13#10 +
    '    .container { max-width: 1100px; margin: 0 auto; }' + #13#10 +
    '    header { margin-bottom: 3rem; text-align: center; }' + #13#10 +
    '    h1 { font-size: 3rem; font-weight: 800; background: linear-gradient(to right, #60a5fa, #a855f7); -webkit-background-clip: text; -webkit-text-fill-color: transparent; margin-bottom: 0.5rem; }' + #13#10 +
    '    .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1.5rem; margin-bottom: 3rem; }' + #13#10 +
    '    .stat-card { background: var(--card); border-radius: 16px; padding: 1.5rem; text-align: center; border: 1px solid rgba(255,255,255,0.05); box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); }' + #13#10 +
    '    .stat-value { font-size: 2.5rem; font-weight: 700; display: block; }' + #13#10 +
    '    .stat-label { color: #94a3b8; text-transform: uppercase; font-size: 0.75rem; font-weight: 600; letter-spacing: 0.05em; }' + #13#10 +
    '    .progress-container { background: #334155; border-radius: 999px; height: 12px; margin-bottom: 4rem; overflow: hidden; }' + #13#10 +
    '    .progress-bar { height: 100%; background: linear-gradient(90deg, #22c55e, #10b981); transition: width 0.8s cubic-bezier(0.4, 0, 0.2, 1); }' + #13#10 +
    '    .suite { background: var(--card); border-radius: 16px; margin-bottom: 2rem; border: 1px solid rgba(255,255,255,0.05); overflow: hidden; }' + #13#10 +
    '    .suite-header { background: rgba(255,255,255,0.03); padding: 1.25rem 2rem; border-bottom: 1px solid rgba(255,255,255,0.05); display: flex; justify-content: space-between; align-items: center; }' + #13#10 +
    '    .test-item { padding: 1rem 2rem; border-bottom: 1px solid rgba(255,255,255,0.03); display: flex; flex-direction: column; }' + #13#10 +
    '    .status-icon { width: 24px; height: 24px; display: flex; align-items: center; justify-content: center; border-radius: 50%; font-size: 14px; }' + #13#10 +
    '    .status-passed { color: var(--success); }' + #13#10 +
    '    .status-failed { color: var(--fail); }' + #13#10 +
    '    .status-skipped { color: var(--warn); }' + #13#10 +
    '    .test-name { font-weight: 500; color: #f1f5f9; }' + #13#10 +
    '    .error-box { margin-top: 1rem; padding: 1rem; background: rgba(239, 68, 68, 0.05); border-radius: 8px; border-left: 4px solid var(--fail); }' + #13#10 +
    '    .error-message { white-space: pre-wrap; font-family: ui-monospace, Consolas, monospace; font-size: 0.85rem; }' + #13#10 +
    '    .footer { text-align: center; margin-top: 4rem; padding-bottom: 2rem; color: #475569; font-size: 0.875rem; }' + #13#10 +
    '  </style>' + #13#10 +
    '</head>' + #13#10;
var
  SB: TStringBuilder;
  Suite: TTestSuiteReport;
  TC: TTestCaseReport;
  TotalTests, TotalPassed, TotalFailed, TotalSkipped: Integer;
  TotalTime: Double;
  PassRate: Double;
  Detail: string;

  function SecondsText(Seconds: Double): string;
  begin
    Result := FormatFloat('0.000', Seconds).Replace(',', '.');
  end;

begin
  TotalTests := 0;
  TotalFailed := 0;
  TotalSkipped := 0;
  TotalTime := 0;
  for Suite in FTestSuites do
  begin
    Inc(TotalTests, Suite.Tests);
    Inc(TotalFailed, Suite.Failures + Suite.Errors);
    Inc(TotalSkipped, Suite.Skipped);
    TotalTime := TotalTime + Suite.Duration;
  end;
  TotalPassed := TotalTests - TotalFailed - TotalSkipped;
  if TotalTests > 0 then
    PassRate := (TotalPassed / TotalTests) * 100
  else
    PassRate := 0;

  SB := TStringBuilder.Create;
  try
    SB.Append(HTML_HEAD.Replace('%s', TDextEscaping.Html(FReportTitle)));
    SB.AppendLine('<body>');
    SB.AppendLine('  <div class="container">');
    SB.AppendLine('    <header>');
    SB.AppendFormat('      <h1>%s</h1>' + #13#10, [TDextEscaping.Html(FReportTitle)]);
    SB.AppendLine('      <p style="color: #64748b">Generated by Dext Testing Framework</p>');
    SB.AppendLine('    </header>');
    SB.AppendLine('    <div class="stats">');
    SB.AppendFormat('      <div class="stat-card"><span class="stat-value">%d</span><span class="stat-label">Total</span></div>' + #13#10, [TotalTests]);
    SB.AppendFormat('      <div class="stat-card" style="border-bottom: 3px solid var(--success)"><span class="stat-value" style="color: var(--success)">%d</span><span class="stat-label">Passed</span></div>' + #13#10, [TotalPassed]);
    SB.AppendFormat('      <div class="stat-card" style="border-bottom: 3px solid var(--fail)"><span class="stat-value" style="color: var(--fail)">%d</span><span class="stat-label">Failed</span></div>' + #13#10, [TotalFailed]);
    SB.AppendFormat('      <div class="stat-card" style="border-bottom: 3px solid var(--warn)"><span class="stat-value" style="color: var(--warn)">%d</span><span class="stat-label">Skipped</span></div>' + #13#10, [TotalSkipped]);
    SB.AppendFormat('      <div class="stat-card"><span class="stat-value">%ss</span><span class="stat-label">Time</span></div>' + #13#10, [SecondsText(TotalTime)]);
    SB.AppendLine('    </div>');
    SB.AppendLine('    <div class="progress-container">');
    SB.AppendFormat('      <div class="progress-bar" style="width: %s%%"></div>' + #13#10,
      [FormatFloat('0.0', PassRate).Replace(',', '.')]);
    SB.AppendLine('    </div>');
    for Suite in FTestSuites do
    begin
      SB.AppendLine('    <div class="suite">');
      SB.AppendFormat('      <div class="suite-header"><span class="suite-title">%s</span>' + #13#10 +
        '        <span class="suite-stats">%ss</span>' + #13#10 +
        '      </div>' + #13#10,
        [TDextEscaping.Html(Suite.Name), SecondsText(Suite.Duration)]);
      for TC in Suite.TestCases do
      begin
        SB.AppendLine('      <div class="test-item">');
        SB.AppendLine('        <div style="display: flex; justify-content: space-between;">');
        SB.AppendFormat('          <span><span class="status-icon status-%s">%s</span> %s</span>' + #13#10,
          [GetStatusClass(TC.Status), GetStatusIcon(TC.Status), TDextEscaping.Html(TC.TestName)]);
        SB.AppendFormat('          <span>%ss</span>' + #13#10, [SecondsText(TC.Duration)]);
        SB.AppendLine('        </div>');
        Detail := TC.ErrorMessage;
        if TC.StackTrace <> '' then
        begin
          if Detail <> '' then
            Detail := Detail + #13#10;
          Detail := Detail + TC.StackTrace;
        end;
        if Detail <> '' then
          SB.AppendFormat('        <div class="error-box"><div class="error-message">%s</div></div>' + #13#10,
            [TDextEscaping.Html(Detail)]);
        SB.AppendLine('      </div>');
      end;
      SB.AppendLine('    </div>');
    end;
    SB.AppendFormat('    <div class="footer">&copy; %s Dext Framework &bull; %s</div>' + #13#10,
      [FormatDateTime('yyyy', Now), TDextEscaping.Html(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now))]);
    SB.AppendLine('  </div>');
    SB.AppendLine('</body></html>');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure THTMLReporter.SaveToFile(const FileName: string);
begin
  TFile.WriteAllText(FileName, GenerateHtml, TEncoding.UTF8);
end;

procedure THTMLReporter.Clear;
begin
  FTestSuites.Clear;
  FCurrentTestCases.Clear;
end;

end.
