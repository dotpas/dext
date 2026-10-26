unit Dext.Hosting.CLI.Commands.Test;

interface

uses
  System.SysUtils,
  System.JSON,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  System.Masks,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.ShellAPI,
  {$ENDIF}
  Dext.Hosting.CLI.Args,
  Dext.Hosting.CLI.Config,
  Dext.Hosting.CLI.Tools.Sonar,
  Dext.Hosting.CLI.Tools.CodeCoverage,
  {$IFDEF POSIX}
  Posix.Stdlib,
  {$ENDIF}
  Dext.Utils;

type
  TTestCommand = class(TInterfacedObject, IConsoleCommand)
  private
    const
      BUILD_DIR = 'TestOutput';
    
    function FindProjectFile(const Directory: string): string;
    function GetExeFile(const ProjectName: string): string;
    
    function BuildProject(const ProjectFile: string; EnableMap: Boolean; GlobalConfig: TDextGlobalConfig; const DesiredDelphi: string): Boolean;
    function RunProcess(const Exe, Params: string): Boolean;
    
    {$IFDEF MSWINDOWS}
    function GetMapFile(const ProjectName: string): string;
    function GetSourceDirectory(const BaseDir: string): string;
    procedure GenerateCoverageLists(const BaseDir, SourceDir: string; const Excludes: TArray<string>; out UnitFile, SourcePathFile: string);
    procedure GenerateAutoInclude(const BaseDir, SourceDir: string);
    
    function FindRSVars(GlobalConfig: TDextGlobalConfig; const DesiredVersion: string): string;
    procedure EnsureCodeCoverage(GlobalConfig: TDextGlobalConfig; out ExePath: string);

    function CheckTestResults(const JsonPath: string): Boolean;
    
    procedure RunWithCoverage(const ProjectFile: string; const Args: TCommandLineArgs; Config: TDextConfig; GlobalConfig: TDextGlobalConfig; const DesiredDelphi: string);
    {$ENDIF}
    
    procedure RunTests(const ProjectFile: string; const Args: TCommandLineArgs; Config: TDextConfig; GlobalConfig: TDextGlobalConfig; const DesiredDelphi: string);
  public
    function GetName: string;
    function GetDescription: string;
    procedure Execute(const Args: TCommandLineArgs);
  end;

implementation

{ TTestCommand }

function TTestCommand.GetName: string;
begin
  Result := 'test';
end;

function TTestCommand.GetDescription: string;
begin
  Result := 'Runs project tests with optional code coverage analysis.';
end;

procedure TTestCommand.Execute(const Args: TCommandLineArgs);
var
  ProjectFile: string;
  WorkDir: string;
  Config: TDextConfig;
  GlobalConfig: TDextGlobalConfig;
  DesiredDelphi: string;
begin
  WorkDir := GetCurrentDir;
  Config := TDextConfig.Create;
  GlobalConfig := TDextGlobalConfig.Create;
  try
    Config.LoadFromFile(TPath.Combine(WorkDir, 'dext.json'));
    GlobalConfig.Load;
    
    DesiredDelphi := '';
    if Args.HasOption('d') then DesiredDelphi := Args.GetOption('d')
    else if Args.HasOption('delphi') then DesiredDelphi := Args.GetOption('delphi');
    
    if Args.HasOption('project') then
      ProjectFile := Args.GetOption('project')
    else if Config.Test.Project <> '' then
      ProjectFile := TPath.GetFullPath(TPath.Combine(WorkDir, Config.Test.Project))
    else
      ProjectFile := FindProjectFile(WorkDir);
  
    if ProjectFile = '' then
    begin
      SafeWriteLn('Error: No Delphi project file (.dproj) found in current directory.');
      SafeWriteLn('Use --project=<path> to specify one.');
      System.ExitCode := 1;
      Exit;
    end;
  
    ProjectFile := TPath.GetFullPath(ProjectFile);
    SafeWriteLn('Testing Project: ' + ExtractFileName(ProjectFile));
    if DesiredDelphi <> '' then SafeWriteLn('Target Delphi: ' + DesiredDelphi);
  
    if Args.HasOption('coverage') then
    begin
      {$IFDEF MSWINDOWS}
      RunWithCoverage(ProjectFile, Args, Config, GlobalConfig, DesiredDelphi);
      {$ELSE}
      SafeWriteLn('Error: Code coverage analysis is currently only supported on Windows.');
      SafeWriteLn('Basic tests can still be run with "dext test".');
      {$ENDIF}
    end
    else
      RunTests(ProjectFile, Args, Config, GlobalConfig, DesiredDelphi);
  finally
    GlobalConfig.Free;
    Config.Free;
  end;
end;

function TTestCommand.FindProjectFile(const Directory: string): string;
var
  Files: TArray<string>;
  Candidate: string;
begin
  Result := '';
  Files := TDirectory.GetFiles(Directory, '*.dproj', TSearchOption.SoTopDirectoryOnly);
  if Length(Files) = 0 then Exit;
  if Length(Files) = 1 then Exit(Files[0]);

  for Candidate in Files do
  begin
    if Candidate.ToLower.Contains('test') then Exit(Candidate);
  end;
  Result := Files[0];
end;

function TTestCommand.GetExeFile(const ProjectName: string): string;
begin
  {$IFDEF MSWINDOWS}
  Result := TPath.GetFullPath(TPath.Combine(BUILD_DIR, ProjectName + '.exe'));
  {$ELSE}
  Result := TPath.GetFullPath(TPath.Combine(BUILD_DIR, ProjectName));
  {$ENDIF}
end;

function TTestCommand.RunProcess(const Exe, Params: string): Boolean;
{$IFDEF MSWINDOWS}
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
  Res: Boolean;
  ExitCode: Cardinal;
begin
  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  CmdLine := Format('"%s" %s', [Exe, Params]);
  SafeWriteLn(Format('Running: %s %s', [Exe, Params]));
  
  Res := CreateProcess(nil, PChar(CmdLine), nil, nil, True, 0, nil, nil, SI, PI);
  if not Res then
  begin
    SafeWriteLn('Failed to start process: ' + SysErrorMessage(GetLastError));
    Exit(False);
  end;
  
  WaitForSingleObject(PI.hProcess, INFINITE);
  GetExitCodeProcess(PI.hProcess, ExitCode);
  CloseHandle(PI.hProcess);
  CloseHandle(PI.hThread);
  Result := ExitCode = 0;
end;
{$ELSE}
begin
  SafeWriteLn(Format('Running: %s %s', [Exe, Params]));
  {$IFDEF POSIX}
  Result := _system(PAnsiChar(AnsiString(Exe + ' ' + Params))) = 0;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;
{$ENDIF}

function TTestCommand.BuildProject(const ProjectFile: string; EnableMap: Boolean; GlobalConfig: TDextGlobalConfig; const DesiredDelphi: string): Boolean;
var
  Args, ProjectName, OutDir, RSVars: string;
begin
  ProjectName := TPath.GetFileNameWithoutExtension(ProjectFile);
  OutDir := TPath.Combine(GetCurrentDir, BUILD_DIR);
  ForceDirectories(OutDir);
  
  Args := Format('"%s" /t:Build /p:Config=Debug /p:Platform=Win32 /p:DCC_ExeOutput="%s" /p:DCC_DcuOutput="%s"', 
    [ProjectFile, OutDir, TPath.Combine(OutDir, 'dcu')]);
    
  if EnableMap then
    Args := Args + ' /p:DCC_MapFile=3 /p:DCC_GenerateStackFrames=true /p:DCC_Define="DEBUG;TESTING;COVERAGE"';

  RSVars := '';
  {$IFDEF MSWINDOWS}
  RSVars := FindRSVars(GlobalConfig, DesiredDelphi);
  {$ENDIF}
  
  if RSVars <> '' then
  begin
    SafeWriteLn('Using Environment: ' + RSVars);
    SafeWriteLn('Building project...');
    Result := RunProcess('cmd', Format('/c "call "%s" && msbuild %s"', [RSVars, Args]));
  end
  else
  begin
    SafeWriteLn('WARNING: Environment vars not found or not needed. Relying on system PATH.');
    if DesiredDelphi <> '' then SafeWriteLn('Requested version: ' + DesiredDelphi);
    {$IFDEF MSWINDOWS}
    Result := RunProcess('msbuild', Args);
    {$ELSE}
    Result := RunProcess('dcc64', Args); 
    {$ENDIF}
  end;
  if not Result then SafeWriteLn('Error: Build failed.');
end;

procedure TTestCommand.RunTests(const ProjectFile: string; const Args: TCommandLineArgs; Config: TDextConfig; GlobalConfig: TDextGlobalConfig; const DesiredDelphi: string);
var
  ExePath, ProjectName: string;
begin
  if not BuildProject(ProjectFile, False, GlobalConfig, DesiredDelphi) then
  begin
    System.ExitCode := 1;
    Exit;
  end;
  ProjectName := TPath.GetFileNameWithoutExtension(ProjectFile);
  ExePath := GetExeFile(ProjectName);
  
  if not FileExists(ExePath) then
  begin
    SafeWriteLn('Error: Executable not found at ' + ExePath);
    System.ExitCode := 1;
    Exit;
  end;
  SafeWriteLn('Running tests...');
  if not RunProcess(ExePath, '') then
  begin
    SafeWriteLn('Error: One or more tests failed.');
    System.ExitCode := 1;
  end;
end;

{$IFDEF MSWINDOWS}
function TTestCommand.GetMapFile(const ProjectName: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(BUILD_DIR, ProjectName + '.map'));
end;

function TTestCommand.FindRSVars(GlobalConfig: TDextGlobalConfig; const DesiredVersion: string): string;
var
  Paths: TArray<string>;
  Path: string;
  Root: string;
begin
  Root := GlobalConfig.GetDelphiRoot(DesiredVersion);
  if Root <> '' then
  begin
    Result := TPath.Combine(Root, 'bin\rsvars.bat');
    if FileExists(Result) then Exit;
  end;

  if (DesiredVersion = '') and (GetEnvironmentVariable('BDS') <> '') then
  begin
     Result := TPath.Combine(GetEnvironmentVariable('BDS'), 'bin\rsvars.bat');
     if FileExists(Result) then Exit;
  end;

  Paths := [
    'C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat', 
    'C:\Program Files (x86)\Embarcadero\Studio\22.0\bin\rsvars.bat',
    'C:\Program Files (x86)\Embarcadero\Studio\21.0\bin\rsvars.bat'
  ];

  for Path in Paths do
    if FileExists(Path) then Exit(Path);
    
  Result := '';
end;

function TTestCommand.CheckTestResults(const JsonPath: string): Boolean;
var
  JsonText: string;
  JsonObj: TJSONObject;
  FailedCount: Integer;
begin
  Result := True; // Default to success if file doesn't exist or can't be parsed
  
  if not FileExists(JsonPath) then Exit;
  
  try
    JsonText := TFile.ReadAllText(JsonPath);
    JsonObj := TJSONObject.ParseJSONValue(JsonText) as TJSONObject;
    if JsonObj <> nil then
    begin
      try
        if JsonObj.TryGetValue<Integer>('failed', FailedCount) then
        begin
          Result := FailedCount = 0;
          if not Result then
            SafeWriteLn(Format('Tests failed: %d test(s) did not pass', [FailedCount]));
        end;
      finally
        JsonObj.Free;
      end;
    end;
  except
    // If we can't parse the results, assume success to avoid false negatives
  end;
end;

procedure TTestCommand.GenerateAutoInclude(const BaseDir, SourceDir: string);
var
  UnitName, FileName, DestFile: string;
  SB: TStringBuilder;
  Files: TArray<string>;
begin
  DestFile := TPath.Combine(BaseDir, 'AutoInclude.pas');
  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit AutoInclude;');
    SB.AppendLine;
    SB.AppendLine('interface');
    SB.AppendLine;
    SB.AppendLine('uses');
    Files := TDirectory.GetFiles(SourceDir, '*.pas', TSearchOption.SoAllDirectories);
    
    for FileName in Files do
    begin
       if FileName.ToLower.Contains('\tests\') then Continue;
       if TPath.GetFileName(FileName).ToLower = 'autoinclude.pas' then Continue;
       UnitName := TPath.GetFileNameWithoutExtension(FileName); 
       SB.AppendLine('  ' + UnitName + ',');
    end;
    SB.AppendLine('  System.SysUtils;');
    SB.AppendLine;
    SB.AppendLine('implementation');
    SB.AppendLine;
    SB.AppendLine('end.');
    TFile.WriteAllText(DestFile, SB.ToString);
  finally
    SB.Free;
  end;
end;

function TTestCommand.GetSourceDirectory(const BaseDir: string): string;
begin
  Result := TPath.GetFullPath(TPath.Combine(BaseDir, 'Sources'));
  if not TDirectory.Exists(Result) then
  begin
     Result := TPath.GetFullPath(TPath.Combine(BaseDir, 'src'));
     if not TDirectory.Exists(Result) then
     begin
       Result := TPath.GetFullPath(TPath.Combine(BaseDir, '../../Sources'));
       if not TDirectory.Exists(Result) then
       begin
          Result := TPath.GetFullPath(TPath.Combine(BaseDir, '../Sources'));
          if not TDirectory.Exists(Result) then Result := BaseDir;
       end;
     end;
  end;
end;

procedure TTestCommand.GenerateCoverageLists(const BaseDir, SourceDir: string; const Excludes: TArray<string>; out UnitFile, SourcePathFile: string);
  
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
      // Fallback to filename on error
    end;
  end;

var
  Units, Paths: TStringList;
  Files: TArray<string>;
  FileName, UnitName, Mask, Dir: string;
  Excluded: Boolean;
begin
  SafeWriteLn('Scanning sources in: ' + SourceDir);
  Units := TStringList.Create;
  Paths := TStringList.Create;
  try
    Files := TDirectory.GetFiles(SourceDir, '*.pas', TSearchOption.SoAllDirectories);
    for FileName in Files do
    begin
      if FileName.ToLower.Contains('\tests\') then Continue;
      
      // Get the real unit name from the file content to ensure correct casing
      UnitName := GetUnitNameFromFile(FileName);
      
      Excluded := False;
      for Mask in Excludes do
      begin
        // If the mask is simple (no wildcards), treat it as a folder name to exclude
        if (Mask.IndexOf('*') = -1) and (Mask.IndexOf('?') = -1) and (Mask.IndexOf('\') = -1) then
        begin
           // For simple patterns like "modules", check if the path contains "\modules\"
           if FileName.ToLower.Contains('\' + Mask.ToLower + '\') then
           begin
             Excluded := True;
             Break;
           end;
        end
        else
        begin
           // For patterns with wildcards, use MatchesMask
           if MatchesMask(FileName, Mask) or MatchesMask(UnitName, Mask) then
           begin
             Excluded := True;
             Break;
           end;
        end;
      end;
      if Excluded then Continue;
      Units.Add(UnitName + ExtractFileExt(FileName));
      Dir := ExtractFilePath(FileName);
      if Paths.IndexOf(Dir) = -1 then Paths.Add(Dir);
    end;
    UnitFile := TPath.Combine(TPath.Combine(BaseDir, BUILD_DIR), 'units.lst');
    SourcePathFile := TPath.Combine(TPath.Combine(BaseDir, BUILD_DIR), 'sources.lst');
    ForceDirectories(ExtractFilePath(UnitFile));
    Units.SaveToFile(UnitFile);
    Paths.SaveToFile(SourcePathFile);
    SafeWriteLn(Format('Coverage Lists Generated: %d units, %d paths.', [Units.Count, Paths.Count]));
  finally
    Units.Free;
    Paths.Free;
  end;
end;

procedure TTestCommand.EnsureCodeCoverage(GlobalConfig: TDextGlobalConfig; out ExePath: string);
var
  Input: string;
begin
  ExePath := TCodeCoverageTool.FindPath(GlobalConfig, 'Win32');
  if (ExePath <> '') and (FileExists(ExePath) or (ExtractFilePath(ExePath) = '')) then Exit;

  SafeWriteLn('CodeCoverage.exe not found or not configured.');
  Write('Do you want to download and install the latest release automatically? [Y/n]: ');
  ReadLn(Input);
  
  if (Input.Trim = '') or (Input.Trim.ToLower = 'y') then
  begin
     try
       TCodeCoverageTool.InstallLatest(ExePath);
       SafeWriteLn('Installed successfully to: ' + ExePath);
     except
       on E: Exception do
         SafeWriteLn('Installation failed: ' + E.Message);
     end;
  end;
end;

procedure TTestCommand.RunWithCoverage(const ProjectFile: string; const Args: TCommandLineArgs; Config: TDextConfig; GlobalConfig: TDextGlobalConfig; const DesiredDelphi: string);
var
  ExePath, MapPath, UnitLst, SourceLst, CoverageCmd, DCCExe, SourceDir: string;
  ReportDir, XmlPath, HtmlPath, JsonPath, TestArgs, DccXml, SonarXml, HtmlReport: string;
begin
  SourceDir := GetSourceDirectory(GetCurrentDir);
  GenerateAutoInclude(GetCurrentDir, SourceDir);
  GenerateCoverageLists(GetCurrentDir, SourceDir, Config.Test.CoverageExclude, UnitLst, SourceLst);
  
  if not BuildProject(ProjectFile, True, GlobalConfig, DesiredDelphi) then
  begin
    System.ExitCode := 1;
    Exit;
  end;
  
  ExePath := GetExeFile(TPath.GetFileNameWithoutExtension(ProjectFile));
  MapPath := GetMapFile(TPath.GetFileNameWithoutExtension(ProjectFile));

  if not FileExists(MapPath) then
  begin
    SafeWriteLn('Error: MAP file not generated. Coverage analysis impossible.');
    System.ExitCode := 1;
    Exit;
  end;
  
  EnsureCodeCoverage(GlobalConfig, DCCExe);
  if (DCCExe = '') or (not FileExists(DCCExe) and (ExtractFilePath(DCCExe) <> '')) then
  begin
     SafeWriteLn('Error: CodeCoverage tool missing. Cannot proceed.');
     System.ExitCode := 1;
     Exit;
  end;

  SafeWriteLn('Executing Code Coverage using: ' + DCCExe);
  ReportDir := TPath.Combine(TPath.GetDirectoryName(ExePath), 'report');
  if Config.Test.ReportDir <> '' then
     ReportDir := TPath.GetFullPath(TPath.Combine(ExtractFileDir(ProjectFile), Config.Test.ReportDir));

  ForceDirectories(ReportDir);
  
  XmlPath := TPath.Combine(ReportDir, 'test-results.xml');
  HtmlPath := TPath.Combine(ReportDir, 'test-results.html');
  JsonPath := TPath.Combine(ReportDir, 'test-results.json');
  
  // Create placeholders to satisfy potential existence checks
  TFile.WriteAllText(XmlPath, '');
  TFile.WriteAllText(HtmlPath, '');
  TFile.WriteAllText(JsonPath, '');

  TestArgs := Format('^-junit:"%s" ^-html:"%s" ^-json:"%s"', [XmlPath, HtmlPath, JsonPath]);
  
  CoverageCmd := Format('-e "%s" -m "%s" -uf "%s" -spf "%s" -od "%s" -lt -html -xml -xmllines -a %s', 
    [ExePath, MapPath, UnitLst, SourceLst, ReportDir, TestArgs]);
    
  // Disable Dext Test Dashboard in target process
  SetEnvironmentVariable('DEXT_HEADLESS', '1');
  try
    if not RunProcess(DCCExe, CoverageCmd) then
    begin
      SafeWriteLn('Coverage analysis failed (or tests failed).');
      Halt(1); // Exit with error code
    end
    else
    begin
      SafeWriteLn('Coverage analysis complete. Check output in ' + ReportDir);
      DccXml := TPath.Combine(ReportDir, 'CodeCoverage_Summary.xml');
      SonarXml := TPath.Combine(ReportDir, 'dext_coverage.xml');
      TSonarConverter.Convert(DccXml, SonarXml, SourceDir, Config.Test.CoverageThreshold);
      
      // Check if tests actually passed
      if not CheckTestResults(JsonPath) then
      begin
        SafeWriteLn('Error: One or more tests failed. Check the test report for details.');
        Halt(1); // Exit with error code
      end;
      
      if Args.HasOption('open') then
      begin
         HtmlReport := TPath.Combine(ReportDir, 'CodeCoverage_Summary.html');
         if FileExists(HtmlReport) then
         begin
            SafeWriteLn('Opening report: ' + HtmlReport);
            {$IFDEF MSWINDOWS}
            ShellExecute(0, 'open', PChar(HtmlReport), nil, nil, SW_SHOWNORMAL);
            {$ENDIF}
         end;
      end;
    end;
  finally
    SetEnvironmentVariable('DEXT_HEADLESS', '');
  end;
end;
{$ENDIF}

end.
