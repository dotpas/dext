unit Dext.Testing.Design.Coverage.Runner;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.UITypes,
  Vcl.Dialogs,
  Dext.Testing.CodeCoverage.Tool;

type
  TCoverageRunPrep = record
    ToolExe: string;
    MapFile: string;
    UnitsList: string;
    SourcesList: string;
    ReportDir: string;
    SourceRoot: string;
  end;

  TDextCoverageRunner = class
  public
    /// <summary>Find CodeCoverage.exe; offer GitHub install if missing.</summary>
    class function EnsureTool(const PlatformName: string; out ToolPath: string;
      ALog: TProc<string>): Boolean;
    class function CoverageWorkDir(const ProjectFile: string): string;
    class function GenerateLists(const ProjectFile, SourceRoot: string;
      out UnitsList, SourcesList: string; ALog: TProc<string>): Boolean;
    class function PrepareRun(const ProjectFile, TestExe, PlatformName: string;
      ALog: TProc<string>; out Prep: TCoverageRunPrep): Boolean;
    class function BuildWrappedCommandLine(const Prep: TCoverageRunPrep;
      const TestExe, RunnerArgs: string): string;
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
  I: Integer;
begin
  // Walk up from the .dproj (e.g. Tests\Core\UnitTests) until we find Sources/
  // — same idea as CLI GetSourceDirectory (../../Sources from repo root).
  Current := TPath.GetDirectoryName(ProjectFile);
  for I := 1 to 10 do
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
  ALog: TProc<string>; out Prep: TCoverageRunPrep): Boolean;
var
  MapFile: string;
  ExeDir: string;
begin
  Result := False;
  FillChar(Prep, SizeOf(Prep), 0);
  if not EnsureTool(PlatformName, Prep.ToolExe, ALog) then
    Exit;

  MapFile := ChangeFileExt(TestExe, '.map');
  if not FileExists(MapFile) then
  begin
    if Assigned(ALog) then
      ALog('Coverage: MAP missing at ' + MapFile +
        '. Use Actions → Apply Debug Trace Options, then rebuild.');
    MessageDlg(
      'Detailed MAP file not found:' + sLineBreak + MapFile + sLineBreak + sLineBreak +
      'Apply Debug Trace Options to the active project, rebuild, then run again.',
      mtWarning, [mbOK], 0);
    Exit;
  end;
  Prep.MapFile := MapFile;
  Prep.SourceRoot := GuessSourceRoot(ProjectFile);
  if Assigned(ALog) then
    ALog('Coverage: source root = ' + Prep.SourceRoot);
  if not GenerateLists(ProjectFile, Prep.SourceRoot, Prep.UnitsList, Prep.SourcesList, ALog) then
    Exit;

  ExeDir := ExtractFilePath(TestExe);
  Prep.ReportDir := TPath.Combine(CoverageWorkDir(ProjectFile), 'report');
  // Prefer report next to exe (CLI layout) when writable
  if ExeDir <> '' then
    Prep.ReportDir := TPath.Combine(ExeDir, 'report');
  ForceDirectories(Prep.ReportDir);
  Result := True;
end;

class function TDextCoverageRunner.BuildWrappedCommandLine(const Prep: TCoverageRunPrep;
  const TestExe, RunnerArgs: string): string;
var
  EscapedArgs: string;
begin
  // Quote runner args and escape " for CodeCoverage's -a parser (^"…^").
  EscapedArgs := '^"' + RunnerArgs.Replace('"', '', [rfReplaceAll]) + '^"';
  Result := Format(
    '"%s" -e "%s" -m "%s" -uf "%s" -spf "%s" -od "%s" -xml -xmllines -ife -tec -twd -a %s',
    [Prep.ToolExe, TestExe, Prep.MapFile, Prep.UnitsList, Prep.SourcesList,
     Prep.ReportDir, EscapedArgs]);
end;

end.
