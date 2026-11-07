{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (c) 2024 Dext Framework                               }
{                                                                           }
{           https://github.com/dext-framework/dext                          }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Licensed under the Apache License, Version 2.0 (the "License");          }
{  you may not use this file except in compliance with the License.         }
{  You may obtain a copy of the License at                                  }
{                                                                           }
{      http://www.apache.org/licenses/LICENSE-2.0                           }
{                                                                           }
{  Unless required by applicable law or agreed to in writing, software      }
{  distributed under the License is distributed on an "AS IS" BASIS,        }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. }
{  See the License for the specific language governing permissions and      }
{  limitations under the License.                                           }
{                                                                           }
{***************************************************************************}

unit Dext.Testing.Design.Coverage.Runner;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.UITypes,
  Vcl.Dialogs,
  Dext.Testing.CodeCoverage.Tool;

type
  /// <summary>Delphi Code Coverage paths for one wrapped run.</summary>
  TCoverageRunPrep = record
    ToolExe: string;
    MapFile: string;
    UnitsList: string;
    SourcesList: string;
    ReportDir: string;
    SourceRoot: string;
  end;

  /// <summary>Runs Delphi Code Coverage, and exports Win64x LCOV through LLVM 20.</summary>
  TDextCoverageRunner = class
  public
    /// <summary>Find CodeCoverage.exe; offer GitHub install if missing.</summary>
    class function EnsureTool(const PlatformName: string; out ToolPath: string;
      ALog: TProc<string>): Boolean;
    /// <summary>Folder next to the project where coverage lists and reports are written.</summary>
    class function CoverageWorkDir(const ProjectFile: string): string;
    /// <summary>Write the unit and source lists Delphi Code Coverage expects.</summary>
    class function GenerateLists(const ProjectFile, SourceRoot: string;
      out UnitsList, SourcesList: string; ALog: TProc<string>): Boolean;
    /// <summary>Folders the project compiles from: the .dproj folder, the folders of the
    /// units added to the project and its DCC_UnitSearchPath ($(VAR) expanded).</summary>
    class function ProjectSearchFolders(const ProjectFile: string): TArray<string>;
    /// <summary>Resolve the map, the lists and the report folder before a Delphi coverage run.</summary>
    class function PrepareRun(const ProjectFile, TestExe, PlatformName: string;
      ALog: TProc<string>; out Prep: TCoverageRunPrep; out AFailureHint: string): Boolean;
    /// <summary>Command line that wraps the test exe with CodeCoverage.exe.</summary>
    class function BuildWrappedCommandLine(const Prep: TCoverageRunPrep;
      const TestExe, RunnerArgs: string; AGenerateHtml: Boolean = False): string;
    /// <summary>Merge *.profraw next to the exe and write LCOV via LLVM 20 llvm-cov.</summary>
    class function TryExportLlvmLcov(const TestExe: string; ALog: TProc<string>;
      out ALcovPath: string): Boolean;
  end;

implementation

uses
  System.StrUtils;

function GetUnitNameFromFile(const FileName: string): string;
var
  Lines: TArray<string>;
  Line, Trimmed: string;
  Parts: TArray<string>;
begin
  Result := TPath.GetFileNameWithoutExtension(FileName);
  try
    Lines := TFile.ReadAllLines(FileName);
    for Line in Lines do
    begin
      Trimmed := Line.Trim;
      if Trimmed.ToLower.StartsWith('unit ') then
      begin
        Parts := Trimmed.Split([' ', ';']);
        if Length(Parts) >= 2 then
        begin
          Result := Parts[1];
          Exit;
        end;
      end;
    end;
  except
  end;
end;

/// <summary>Values of every &lt;Tag&gt;...&lt;/Tag&gt; in the .dproj text.</summary>
function ProjectTagValues(const Text, Tag: string): TArray<string>;
var
  OpenTag, CloseTag: string;
  P, Q: Integer;
begin
  Result := nil;
  OpenTag := '<' + Tag + '>';
  CloseTag := '</' + Tag + '>';
  P := Pos(OpenTag, Text);
  while P > 0 do
  begin
    Inc(P, Length(OpenTag));
    Q := PosEx(CloseTag, Text, P);
    if Q = 0 then
      Break;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(Text, P, Q - P);
    P := PosEx(OpenTag, Text, Q);
  end;
end;

/// <summary>Files added to the project: every &lt;DCCReference Include="..."/&gt;.</summary>
function ProjectReferences(const Text: string): TArray<string>;
const
  Marker = '<DCCReference Include="';
var
  P, Q: Integer;
begin
  Result := nil;
  P := Pos(Marker, Text);
  while P > 0 do
  begin
    Inc(P, Length(Marker));
    Q := PosEx('"', Text, P);
    if Q = 0 then
      Break;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Copy(Text, P, Q - P);
    P := PosEx(Marker, Text, Q);
  end;
end;

/// <summary>Expands $(NAME) with the IDE environment. Returns '' when a macro
/// cannot be resolved, so the entry is skipped instead of guessed.</summary>
function ExpandProjectMacros(const Value: string): string;
var
  P, Q: Integer;
  Name, Env: string;
begin
  Result := Value;
  P := Pos('$(', Result);
  while P > 0 do
  begin
    Q := PosEx(')', Result, P);
    if Q = 0 then
      Exit('');
    Name := Copy(Result, P + 2, Q - P - 2);
    Env := GetEnvironmentVariable(Name);
    if Env = '' then
      Exit('');
    Result := Copy(Result, 1, P - 1) + Env + Copy(Result, Q + 1, MaxInt);
    P := Pos('$(', Result);
  end;
end;

/// <summary>True for test code: DUnitX/Dext fixtures and DUnit test cases are
/// not production code and would only inflate the percentage.</summary>
function IsTestUnit(const FileName: string): Boolean;
var
  Text: string;
begin
  try
    Text := LowerCase(TFile.ReadAllText(FileName));
  except
    Exit(False);
  end;
  Result := (Pos('[testfixture', Text) > 0) or (Pos('[fixture', Text) > 0) or
    (Pos('(ttestcase)', Text) > 0);
end;

{ TDextCoverageRunner }

class function TDextCoverageRunner.CoverageWorkDir(const ProjectFile: string): string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ProjectFile), '.dext\testing\coverage');
end;

class function TDextCoverageRunner.EnsureTool(const PlatformName: string; out ToolPath: string;
  ALog: TProc<string>): Boolean;
var
  PlatformFolder: string;
begin
  ToolPath := '';
  PlatformFolder := PlatformName;
  if PlatformFolder = '' then
    PlatformFolder := 'Win32';

  ToolPath := TDextCodeCoverageTool.FindPath(PlatformFolder);
  if (ToolPath <> '') and (FileExists(ToolPath) or (ExtractFilePath(ToolPath) = '')) then
  begin
    if Assigned(ALog) then
      ALog('Coverage: using ' + ToolPath);
    Exit(True);
  end;

  if Assigned(ALog) then
    ALog('Coverage: CodeCoverage.exe not found.');

  if MessageDlg(
    'Delphi Code Coverage was not found.' + sLineBreak + sLineBreak +
    'Download the latest release from GitHub into %HOME%\.dext\tools\DelphiCodeCoverage?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit(False);

  try
    if Assigned(ALog) then
      ALog('Coverage: downloading latest release…');
    TDextCodeCoverageTool.InstallLatest(ToolPath);
    if Assigned(ALog) then
      ALog('Coverage: installed to ' + ToolPath);
    Result := (ToolPath <> '') and FileExists(ToolPath);
  except
    on E: Exception do
    begin
      if Assigned(ALog) then
        ALog('Coverage install failed: ' + E.Message);
      MessageDlg('Could not install CodeCoverage.exe: ' + E.Message, mtError, [mbOK], 0);
      Result := False;
    end;
  end;
end;

class function TDextCoverageRunner.GenerateLists(const ProjectFile, SourceRoot: string;
  out UnitsList, SourcesList: string; ALog: TProc<string>): Boolean;
// Units to measure: the units added to the project (DCCReference), resolved from
// the .dproj folder, without test units. Where to find sources: the .dproj folder,
// the folders of those units and the project's own DCC_UnitSearchPath.
// SourceRoot is kept for compatibility and is not used.
var
  Units, Paths: TStringList;
  ProjectDir, Text, Ref, FileName, Entry, Dir, WorkDir: string;
  SearchPath: string;
  Skipped: Integer;

  procedure AddPath(const APath: string);
  var
    Full: string;
  begin
    if APath = '' then
      Exit;
    Full := IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ProjectDir, APath)));
    if TDirectory.Exists(Full) and (Paths.IndexOf(Full) < 0) then
      Paths.Add(Full);
  end;

begin
  Result := False;
  UnitsList := '';
  SourcesList := '';
  ProjectDir := TPath.GetDirectoryName(ProjectFile);
  try
    Text := TFile.ReadAllText(ProjectFile);
  except
    on E: Exception do
    begin
      if Assigned(ALog) then
        ALog('Coverage: cannot read ' + ProjectFile + ': ' + E.Message);
      Exit;
    end;
  end;

  WorkDir := CoverageWorkDir(ProjectFile);
  ForceDirectories(WorkDir);
  Units := TStringList.Create;
  Paths := TStringList.Create;
  try
    Paths.CaseSensitive := False;
    Units.CaseSensitive := False;
    AddPath('.');
    Skipped := 0;
    for Ref in ProjectReferences(Text) do
    begin
      if not SameText(ExtractFileExt(Ref), '.pas') then
        Continue;
      FileName := TPath.GetFullPath(TPath.Combine(ProjectDir, Ref));
      if not FileExists(FileName) then
        Continue;
      AddPath(ExtractFilePath(FileName));
      if IsTestUnit(FileName) then
      begin
        Inc(Skipped);
        Continue;
      end;
      Entry := GetUnitNameFromFile(FileName) + ExtractFileExt(FileName);
      if Units.IndexOf(Entry) < 0 then
        Units.Add(Entry);
    end;

    for SearchPath in ProjectTagValues(Text, 'DCC_UnitSearchPath') do
      for Dir in SearchPath.Split([';']) do
        if (Dir.Trim <> '') and (Pos('$(DCC_UnitSearchPath)', Dir) = 0) then
          AddPath(ExpandProjectMacros(Dir.Trim));

    UnitsList := TPath.Combine(WorkDir, 'units.lst');
    SourcesList := TPath.Combine(WorkDir, 'sources.lst');
    Units.SaveToFile(UnitsList);
    Paths.SaveToFile(SourcesList);
    if Assigned(ALog) then
      ALog(Format('Coverage: %d project unit(s) to measure (%d test unit(s) skipped), %d source path(s); lists under %s',
        [Units.Count, Skipped, Paths.Count, WorkDir]));
    Result := Units.Count > 0;
    if not Result and Assigned(ALog) then
      ALog('Coverage: the .dproj has no production unit added (DCCReference). ' +
        'Add the units under test to the project.');
  finally
    Units.Free;
    Paths.Free;
  end;
end;

class function TDextCoverageRunner.ProjectSearchFolders(const ProjectFile: string): TArray<string>;
var
  Folders: TStringList;
  ProjectDir, Text, Ref, SearchPath, Dir: string;

  procedure AddFolder(const APath: string);
  var
    Full: string;
  begin
    if APath = '' then
      Exit;
    try
      Full := ExcludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ProjectDir, APath)));
    except
      Exit;
    end;
    if TDirectory.Exists(Full) and (Folders.IndexOf(Full) < 0) then
      Folders.Add(Full);
  end;

begin
  Result := nil;
  if (ProjectFile = '') or not FileExists(ProjectFile) then
    Exit;
  ProjectDir := TPath.GetDirectoryName(ProjectFile);
  try
    Text := TFile.ReadAllText(ProjectFile);
  except
    Exit;
  end;
  Folders := TStringList.Create;
  try
    Folders.CaseSensitive := False;
    AddFolder('.');
    for Ref in ProjectReferences(Text) do
      AddFolder(ExtractFilePath(Ref));
    for SearchPath in ProjectTagValues(Text, 'DCC_UnitSearchPath') do
      for Dir in SearchPath.Split([';']) do
        if (Dir.Trim <> '') and (Pos('$(DCC_UnitSearchPath)', Dir) = 0) then
          AddFolder(ExpandProjectMacros(Dir.Trim));
    Result := Folders.ToStringArray;
  finally
    Folders.Free;
  end;
end;

class function TDextCoverageRunner.PrepareRun(const ProjectFile, TestExe, PlatformName: string;
  ALog: TProc<string>; out Prep: TCoverageRunPrep; out AFailureHint: string): Boolean;
var
  MapFile: string;
  ExeDir: string;
begin
  Result := False;
  AFailureHint := '';
  FillChar(Prep, SizeOf(Prep), 0);

  { DelphiCodeCoverage is Delphi/MAP only. Wrapping a .cbproj exe exits in ms
    without posting Host results — Run All looks empty. Soft-skip and run bare. }
  if SameText(ExtractFileExt(ProjectFile), '.cbproj') then
  begin
    AFailureHint :=
      'Coverage skipped: DelphiCodeCoverage does not support C++Builder yet. Tests run without wrap.';
    if Assigned(ALog) then
      ALog(AFailureHint);
    Exit;
  end;

  if not EnsureTool(PlatformName, Prep.ToolExe, ALog) then
  begin
    AFailureHint :=
      'Coverage skipped: CodeCoverage.exe not available. Use Actions → Install CodeCoverage…';
    Exit;
  end;

  MapFile := ChangeFileExt(TestExe, '.map');
  if not FileExists(MapFile) then
  begin
    // Soft fail only — never modal. Suite must keep running without wrap.
    AFailureHint :=
      'Coverage skipped: Detailed MAP not found after build. ' +
      'Actions → Apply Debug Trace Options, rebuild, then Run All again.';
    if Assigned(ALog) then
      ALog('Coverage: MAP missing at ' + MapFile +
        ' — running tests without coverage wrap. ' +
        'Apply Debug Trace Options, rebuild, Run All again.');
    Exit;
  end;
  Prep.MapFile := MapFile;
  Prep.SourceRoot := TPath.GetDirectoryName(ProjectFile);
  if Assigned(ALog) then
    ALog('Coverage: project folder = ' + Prep.SourceRoot);
  if not GenerateLists(ProjectFile, Prep.SourceRoot, Prep.UnitsList, Prep.SourcesList, ALog) then
  begin
    AFailureHint :=
      'Coverage skipped: the project has no production unit added. Add the units under test to the .dproj.';
    Exit;
  end;

  ExeDir := ExtractFilePath(TestExe);
  Prep.ReportDir := TPath.Combine(CoverageWorkDir(ProjectFile), 'report');
  // Prefer report next to exe (CLI layout) when writable
  if ExeDir <> '' then
    Prep.ReportDir := TPath.Combine(ExeDir, 'report');
  ForceDirectories(Prep.ReportDir);
  Result := True;
end;

class function TDextCoverageRunner.BuildWrappedCommandLine(const Prep: TCoverageRunPrep;
  const TestExe, RunnerArgs: string; AGenerateHtml: Boolean): string;
var
  EscapedArgs: string;
  HtmlSwitch: string;
begin
  // Quote runner args and escape " for CodeCoverage's -a parser (^"…^").
  EscapedArgs := '^"' + RunnerArgs.Replace('"', '', [rfReplaceAll]) + '^"';
  // -html is opt-in (default off): CodeCoverage_Summary.html + per-unit HTML.
  if AGenerateHtml then
    HtmlSwitch := ' -html'
  else
    HtmlSwitch := '';
  Result := Format(
    '"%s" -e "%s" -m "%s" -uf "%s" -spf "%s" -od "%s" -xml -xmllines%s -ife -tec -twd -a %s',
    [Prep.ToolExe, TestExe, Prep.MapFile, Prep.UnitsList, Prep.SourcesList,
     Prep.ReportDir, HtmlSwitch, EscapedArgs]);
end;

function FindLlvmTool(const AFileName: string): string;
var
  PathEnv, Folder: string;
  Parts: TArray<string>;
begin
  Result := TPath.Combine('C:\Program Files\LLVM\bin', AFileName);
  if FileExists(Result) then
    Exit;
  Result := '';
  PathEnv := GetEnvironmentVariable('PATH');
  Parts := PathEnv.Split([';']);
  for Folder in Parts do
  begin
    if Folder.Trim = '' then
      Continue;
    Result := TPath.Combine(Folder.Trim, AFileName);
    if FileExists(Result) then
      Exit;
  end;
  Result := '';
end;

function QuoteArg(const AValue: string): string;
begin
  Result := '"' + AValue.Replace('"', '\"', [rfReplaceAll]) + '"';
end;

function RunHidden(const ACommandLine, AWorkDir: string; out AExitCode: Cardinal): Boolean;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  Cmd: string;
begin
  AExitCode := $FFFFFFFF;
  Cmd := ACommandLine;
  UniqueString(Cmd);
  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  Result := CreateProcess(nil, PChar(Cmd), nil, nil, False, CREATE_NO_WINDOW, nil,
    PChar(AWorkDir), SI, PI);
  if not Result then
    Exit;
  CloseHandle(PI.hThread);
  if WaitForSingleObject(PI.hProcess, 120000) <> WAIT_OBJECT_0 then
  begin
    TerminateProcess(PI.hProcess, 1);
    CloseHandle(PI.hProcess);
    Result := False;
    Exit;
  end;
  GetExitCodeProcess(PI.hProcess, AExitCode);
  CloseHandle(PI.hProcess);
end;

class function TDextCoverageRunner.TryExportLlvmLcov(const TestExe: string;
  ALog: TProc<string>; out ALcovPath: string): Boolean;
var
  ExeDir, ProfData, Profraws, MergeCmd, ExportCmd, Lcov: string;
  ProfFiles: TArray<string>;
  ProfdataExe, CovExe: string;
  ExitCode: Cardinal;
  i: Integer;
begin
  Result := False;
  ALcovPath := '';
  if (TestExe = '') or not FileExists(TestExe) then
    Exit;

  ProfdataExe := FindLlvmTool('llvm-profdata.exe');
  CovExe := FindLlvmTool('llvm-cov.exe');
  if (ProfdataExe = '') or (CovExe = '') then
  begin
    if Assigned(ALog) then
      ALog('Coverage: LLVM 20 not found. Install llvm-profdata and llvm-cov (C:\Program Files\LLVM\bin).');
    Exit;
  end;

  ExeDir := ExtractFilePath(TestExe);
  try
    ProfFiles := TDirectory.GetFiles(ExeDir, '*.profraw');
  except
    SetLength(ProfFiles, 0);
  end;
  if Length(ProfFiles) = 0 then
  begin
    if Assigned(ALog) then
      ALog('Coverage: no .profraw next to the exe. The Win64x build needs -fprofile-instrument=clang and -fcoverage-mapping, then Run All again.');
    Exit;
  end;

  Profraws := '';
  for i := 0 to High(ProfFiles) do
    Profraws := Profraws + ' ' + QuoteArg(ProfFiles[i]);

  ProfData := TPath.Combine(ExeDir, 'dext-llvm.profdata');
  Lcov := TPath.Combine(ExeDir, 'dext-llvm.lcov');
  MergeCmd := Format('%s merge -sparse%s -o %s',
    [QuoteArg(ProfdataExe), Profraws, QuoteArg(ProfData)]);
  if not RunHidden(MergeCmd, ExeDir, ExitCode) or (ExitCode <> 0) or not FileExists(ProfData) then
  begin
    if Assigned(ALog) then
      ALog(Format('Coverage: llvm-profdata merge failed (exit %d).', [ExitCode]));
    Exit;
  end;

  ExportCmd := 'cmd.exe /S /C "' + QuoteArg(CovExe) + ' export ' + QuoteArg(TestExe) +
    ' -instr-profile=' + QuoteArg(ProfData) +
    ' -format=lcov -ignore-filename-regex=gtest^|windows\\sdk^|x86_64-w64 > ' + QuoteArg(Lcov) + '"';
  if not RunHidden(ExportCmd, ExeDir, ExitCode) or not FileExists(Lcov) then
  begin
    if Assigned(ALog) then
      ALog(Format('Coverage: llvm-cov export failed (exit %d).', [ExitCode]));
    Exit;
  end;

  ALcovPath := Lcov;
  Result := True;
  if Assigned(ALog) then
    ALog('Coverage: llvm-cov wrote ' + Lcov);
end;

end.
