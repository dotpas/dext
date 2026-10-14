unit Dext.Dashboard.TestRunner;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  Dext.Json,
  Dext.Json.Types,
  Dext.Hosting.CLI.Config,
  Dext.Hosting.CLI.Tools.CodeCoverage,
  {$IFDEF MSWINDOWS}
  WinApi.Windows,
  WinApi.ShellAPI
  {$ENDIF}
  {$IFDEF POSIX}
  Posix.Stdlib
  {$ENDIF};

type
  TTestRunner = class
  private
    class function FindExecutable(const AProjectPath: string): string;
    class function ExecuteProcess(const AExePath, AParams: string): Boolean;
    {$IFDEF MSWINDOWS}
    class procedure CaptureStdoutAsync(AProcess, AReadPipe: THandle);
    {$ENDIF}
  public
    class function RunProject(const AProjectPath: string; ACoverage: Boolean = False): IDextJsonObject;
  end;

implementation

uses
  Dext.Dashboard.Routes;

function JsonQuote(const S: string): string;
var
  J: TJSONString;
begin
  J := TJSONString.Create(S);
  try
    Result := J.ToJSON;
  finally
    J.Free;
  end;
end;

{ TTestRunner }

{$IFDEF MSWINDOWS}
class procedure TTestRunner.CaptureStdoutAsync(AProcess, AReadPipe: THandle);
begin
  // Fire-and-forget reader: pipe stdout/stderr lines into dashboard live events.
  TThread.CreateAnonymousThread(
    procedure
    var
      Buffer: array[0..4095] of AnsiChar;
      BytesRead: DWORD;
      Chunk, Pending, Line: string;
      P: Integer;
      WaitResult: DWORD;
    begin
      Pending := '';
      try
        repeat
          BytesRead := 0;
          if not ReadFile(AReadPipe, Buffer[0], SizeOf(Buffer) - 1, BytesRead, nil) then
            Break;
          if BytesRead = 0 then
            Break;
          Buffer[BytesRead] := #0;
          Chunk := string(AnsiString(PAnsiChar(@Buffer[0])));
          Pending := Pending + Chunk;
          while True do
          begin
            P := Pos(#10, Pending);
            if P = 0 then
              Break;
            Line := Copy(Pending, 1, P - 1).Trim([#13, #10, ' ']);
            Delete(Pending, 1, P);
            if Line <> '' then
              TDashboardRoutes.BroadcastSSE('log',
                Format('{"lvl":"Info","msg":%s,"app":"TestRunner"}', [JsonQuote(Line)]));
          end;
          WaitResult := WaitForSingleObject(AProcess, 0);
        until WaitResult <> WAIT_TIMEOUT;

        if Pending.Trim <> '' then
          TDashboardRoutes.BroadcastSSE('log',
            Format('{"lvl":"Info","msg":%s,"app":"TestRunner"}', [JsonQuote(Pending.Trim)]));
      finally
        CloseHandle(AReadPipe);
        CloseHandle(AProcess);
      end;
    end).Start;
end;
{$ENDIF}

class function TTestRunner.ExecuteProcess(const AExePath, AParams: string): Boolean;
{$IFDEF MSWINDOWS}
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine: string;
  Sa: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
begin
  Result := False;
  Sa.nLength := SizeOf(TSecurityAttributes);
  Sa.bInheritHandle := True;
  Sa.lpSecurityDescriptor := nil;
  ReadPipe := 0;
  WritePipe := 0;
  if not CreatePipe(ReadPipe, WritePipe, @Sa, 0) then
    Exit;
  SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

  FillChar(SI, SizeOf(SI), 0);
  SI.cb := SizeOf(SI);
  SI.dwFlags := STARTF_USESHOWWINDOW or STARTF_USESTDHANDLES;
  SI.wShowWindow := SW_HIDE;
  SI.hStdOutput := WritePipe;
  SI.hStdError := WritePipe;
  SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

  CmdLine := Format('"%s" %s', [AExePath, AParams]);
  UniqueString(CmdLine);

  if CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
    PChar(TPath.GetDirectoryName(AExePath)), SI, PI) then
  begin
    CloseHandle(WritePipe);
    CloseHandle(PI.hThread);
    // Do NOT wait on the request thread — capture stdout asynchronously.
    CaptureStdoutAsync(PI.hProcess, ReadPipe);
    TDashboardRoutes.BroadcastSSE('run_start',
      Format('{"event":"RunStart","exe":%s}', [JsonQuote(AExePath)]));
    Result := True;
  end
  else
  begin
    CloseHandle(WritePipe);
    CloseHandle(ReadPipe);
  end;
end;
{$ELSE}
begin
  {$IFDEF POSIX}
  Result := _system(PAnsiChar(AnsiString(AExePath + ' ' + AParams + ' &'))) = 0;
  {$ELSE}
  Result := False;
  {$ENDIF}
end;
{$ENDIF}

class function TTestRunner.FindExecutable(const AProjectPath: string): string;
var
  BaseName, ProjectDir, ExeExt: string;
  Candidates: TArray<string>;
  Path: string;
begin
  Result := '';
  BaseName := TPath.GetFileNameWithoutExtension(AProjectPath);
  ProjectDir := TPath.GetDirectoryName(AProjectPath);
  
  {$IFDEF MSWINDOWS}
  ExeExt := '.exe';
  {$ELSE}
  ExeExt := '';
  {$ENDIF}
  
  Candidates := [
    TPath.Combine(ProjectDir, BaseName + ExeExt),
    TPath.Combine(TPath.Combine(ProjectDir, 'TestOutput'), BaseName + ExeExt),
    TPath.Combine(TPath.Combine(ProjectDir, 'Output'), BaseName + ExeExt),
    TPath.Combine(TPath.GetFullPath(TPath.Combine(ProjectDir, '..\..\Output')), BaseName + ExeExt),
    TPath.Combine(TPath.Combine(ProjectDir, 'Win32\Debug'), BaseName + ExeExt),
    TPath.Combine(TPath.Combine(ProjectDir, '..\Output'), BaseName + ExeExt)
  ];
  
  for Path in Candidates do
  begin
    if FileExists(Path) then Exit(Path);
  end;
end;

class function TTestRunner.RunProject(const AProjectPath: string; ACoverage: Boolean = False): IDextJsonObject;
var
  ExePath: string;
  ResultsFile: string;
  CoverageExe: string;
  CoverageParams: string;
  Config: TDextGlobalConfig;
begin
  ExePath := FindExecutable(AProjectPath);

  if ExePath = '' then
  begin
    Result := TDextJson.Provider.CreateObject;
    Result.SetString('error', 'Test executable not found. Please build the project first.');
    Exit;
  end;
  
  ResultsFile := TPath.Combine(TPath.GetDirectoryName(ExePath), 'test-results.json');
  if FileExists(ResultsFile) then TFile.Delete(ResultsFile);
  
  if ACoverage then
  begin
     Config := TDextGlobalConfig.Create;
     try
       Config.Load;
       CoverageExe := TCodeCoverageTool.FindPath(Config);
     finally
       Config.Free;
     end;

     if (CoverageExe <> '') and FileExists(CoverageExe) then
     begin
       CoverageParams := Format('-e "%s" -o "TestOutput\report" -v -html -xml -x "%s"', [ExePath, ExePath]);
       if ExecuteProcess(CoverageExe, CoverageParams) then
       begin
         Result := TDextJson.Provider.CreateObject;
         Result.SetString('status', 'started');
         Result.SetString('message', 'Tests with Coverage are running in background.');
         Exit;
       end;
     end;
  end;

  if ExecuteProcess(ExePath, '-no-wait') then
  begin
      Result := TDextJson.Provider.CreateObject;
      Result.SetString('status', 'started');
      Result.SetString('message', 'Tests are running in background. Check dashboard for real-time progress.');
  end
  else
  begin
      Result := TDextJson.Provider.CreateObject;
      Result.SetString('error', 'Failed to execute test process.');
  end;
end;

end.
