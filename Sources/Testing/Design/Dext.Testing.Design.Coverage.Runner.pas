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

function GuessSourceRoot(const ProjectFile: string): string;
var
  Current: string;
  Candidate: string;
  i: Integer;
begin
  // Walk up from the .dproj (e.g. Tests\Core\UnitTests) until we find Sources/
  // — same idea as CLI GetSourceDirectory (../../Sources from repo root).
  Current := TPath.GetDirectoryName(ProjectFile);
  for i := 1 to 10 do
  begin
    if SameText(TPath.GetFileName(Current), 'Sources') or
       SameText(TPath.GetFileName(Current), 'Source') or
       SameText(TPath.GetFileName(Current), 'src') then
      Exit(Current);

    Candidate := TPath.Combine(Current, 'Sources');
    if TDirectory.Exists(Candidate) then
      Exit(Candidate);
    Candidate := TPath.Combine(Current, 'Source');
    if TDirectory.Exists(Candidate) then
      Exit(Candidate);
    Candidate := TPath.Combine(Current, 'src');
    if TDirectory.Exists(Candidate) then
      Exit(Candidate);

    Current := TPath.GetDirectoryName(Current);
    if (Current = '') or (Current = TPath.GetPathRoot(Current)) then
      Break;
  end;
  // Last resort: project folder (may be under Tests\ — GenerateLists still skips \tests\)
  Result := TPath.GetDirectoryName(ProjectFile);
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
var
  Units, Paths: TStringList;
  Files: TArray<string>;
  FileName, UnitName, Dir, WorkDir: string;
  Root: string;
begin
  Result := False;
  UnitsList := '';
  SourcesList := '';
  Root := SourceRoot;
  if (Root = '') or not TDirectory.Exists(Root) then
    Root := GuessSourceRoot(ProjectFile);
  if not TDirectory.Exists(Root) then
  begin
    if Assigned(ALog) then
      ALog('Coverage: source root not found.');
    Exit;
  end;

  WorkDir := CoverageWorkDir(ProjectFile);
  ForceDirectories(WorkDir);
  Units := TStringList.Create;
  Paths := TStringList.Create;
  try
    if Assigned(ALog) then
      ALog('Coverage: scanning source root ' + Root);
    Files := TDirectory.GetFiles(Root, '*.pas', TSearchOption.soAllDirectories);
    for FileName in Files do
    begin
      // Skip test trees and IDE junk — only when they appear as path segments.
      if FileName.ToLower.Contains('\tests\') then
        Continue;
      if FileName.ToLower.Contains('\test\') then
        Continue;
      if FileName.ToLower.Contains('\__history\') then
        Continue;
      if FileName.ToLower.Contains('\__recovery\') then
        Continue;
      UnitName := GetUnitNameFromFile(FileName);
      Units.Add(UnitName + ExtractFileExt(FileName));
      Dir := ExtractFilePath(FileName);
      if Paths.IndexOf(Dir) < 0 then
        Paths.Add(Dir);
    end;
    UnitsList := TPath.Combine(WorkDir, 'units.lst');
    SourcesList := TPath.Combine(WorkDir, 'sources.lst');
    Units.SaveToFile(UnitsList);
    Paths.SaveToFile(SourcesList);
    if Assigned(ALog) then
      ALog(Format('Coverage: lists ready (%d units, %d paths) under %s',
        [Units.Count, Paths.Count, WorkDir]));
    Result := Units.Count > 0;
    if not Result and Assigned(ALog) then
      ALog('Coverage: no production units found under ' + Root +
        ' (check Sources folder).');
  finally
    Units.Free;
    Paths.Free;
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
  Prep.SourceRoot := GuessSourceRoot(ProjectFile);
  if Assigned(ALog) then
    ALog('Coverage: source root = ' + Prep.SourceRoot);
  if not GenerateLists(ProjectFile, Prep.SourceRoot, Prep.UnitsList, Prep.SourcesList, ALog) then
  begin
    AFailureHint :=
      'Coverage skipped: no instrumentable units under Sources. Check the project layout.';
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
