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
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2026-04-07                                                      }
{                                                                           }
{  Dext.Testing.Host - Application Host for Test Execution (GUI/Console)    }
{***************************************************************************}
{$I Dext.inc}

unit Dext.Testing.Host;

interface

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  Dext.Testing.Fluent,
  Dext.Testing.Runner,
  Dext.Testing.Integration;

type
  /// <summary>Manages the lifecycle and execution environment during tests (Console, IDE, or CI).</summary>
  TTestHost = class
  public
    /// <summary>Executes the test suite with a specific configuration.</summary>
    class procedure Execute(const Config: TTestConfigurator); overload;
    /// <summary>Executes the tests using the detected default settings.</summary>
    class procedure Execute; overload;
  end;

procedure RunTests(const Config: TTestConfigurator); overload;
procedure RunTests; overload;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  System.IOUtils,
  Dext.Utils,

  Dext.Core.Writers,
  System.Net.HttpClient,
  System.Net.Mime,
  System.Net.URLClient;

type
  TDextTestExplorerListener = class(TInterfacedObject, ITestListener)
  private
    FPort: Integer;
    FClient: THTTPClient;
  public
    constructor Create(APort: Integer);
    destructor Destroy; override;
    procedure OnRunStart(TotalTests: Integer);
    procedure OnRunComplete(const Summary: TTestSummary);
    procedure OnFixtureStart(const FixtureName: string; TestCount: Integer);
    procedure OnFixtureComplete(const FixtureName: string);
    procedure OnTestStart(const UnitName, Fixture, Test: string);
    procedure OnTestComplete(const Info: TTestInfo);
  end;

{ TDextTestExplorerListener }

constructor TDextTestExplorerListener.Create(APort: Integer);
begin
  inherited Create;
  FPort := APort;
  FClient := THTTPClient.Create;
end;

destructor TDextTestExplorerListener.Destroy;
begin
  FClient.Free;
  inherited;
end;

procedure TDextTestExplorerListener.OnRunStart(TotalTests: Integer);
var
  LJSON: string;
  LStream: TStringStream;
  LHeaders: TNetHeaders;
begin
  LJSON := '{"event":"RunStart","totalTests":' + TotalTests.ToString + '}';
  LStream := TStringStream.Create(LJSON, TEncoding.UTF8);
  try
    try
      SetLength(LHeaders, 1);
      LHeaders[0] := TNetHeader.Create('Content-Type', 'application/json');
      FClient.Post('http://localhost:' + FPort.ToString + '/', LStream, nil, LHeaders);
    except
      on E: Exception do
        SafeWriteLn('TDextTestExplorerListener.OnRunStart: POST failed: ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    LStream.Free;
  end;
end;

procedure TDextTestExplorerListener.OnRunComplete(const Summary: TTestSummary);
var
  LJSON: string;
  LStream: TStringStream;
  LHeaders: TNetHeaders;
begin
  LJSON := '{' +
    '"event":"RunComplete",' +
    '"passed":' + Summary.Passed.ToString + ',' +
    '"failed":' + Summary.Failed.ToString + ',' +
    '"ignored":' + Summary.Skipped.ToString +
    '}';

  LStream := TStringStream.Create(LJSON, TEncoding.UTF8);
  try
    try
      SetLength(LHeaders, 1);
      LHeaders[0] := TNetHeader.Create('Content-Type', 'application/json');
      FClient.Post('http://localhost:' + FPort.ToString + '/', LStream, nil, LHeaders);
    except
      on E: Exception do
        SafeWriteLn('TDextTestExplorerListener.OnRunComplete: POST failed: ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    LStream.Free;
  end;
end;

procedure TDextTestExplorerListener.OnFixtureStart(const FixtureName: string; TestCount: Integer);
begin
  SafeWriteLn('TDextTestExplorerListener.OnFixtureStart: ' + FixtureName + ' (Tests: ' + TestCount.ToString + ')');
end;

procedure TDextTestExplorerListener.OnFixtureComplete(const FixtureName: string);
begin
  SafeWriteLn('TDextTestExplorerListener.OnFixtureComplete: ' + FixtureName);
end;

procedure TDextTestExplorerListener.OnTestStart(const UnitName, Fixture, Test: string);
begin
  SafeWriteLn('TDextTestExplorerListener.OnTestStart: ' + Fixture + '.' + Test);
end;

procedure TDextTestExplorerListener.OnTestComplete(const Info: TTestInfo);
var
  LJSON: string;
  LStatus: string;
  LStream: TStringStream;
  LHeaders: TNetHeaders;
begin
  case Info.Result of
    trPassed: LStatus := 'Passed';
    trFailed: LStatus := 'Failed';
    trError: LStatus := 'Error';
    trSkipped: LStatus := 'Skipped';
    trTimeout: LStatus := 'Error';
  else
    LStatus := 'Skipped';
  end;

  SafeWriteLn('TDextTestExplorerListener.OnTestComplete: ' + Info.ClassName + '.' + Info.TestName + ' - ' + LStatus);

  LJSON := '{' +
    '"testName":"' + Info.ClassName + '.' + Info.TestName + '",' +
    '"status":"' + LStatus + '",' +
    '"durationMs":' + FormatFloat('0.####', Info.Duration.TotalMilliseconds, TFormatSettings.Invariant);
    
  if Info.Result in [trFailed, trError, trTimeout] then
  begin
    LJSON := LJSON + ',"error":{' +
      '"message":"' + Info.ErrorMessage.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '",' +
      '"stackTrace":{"raw":"' + Info.StackTrace.Replace('\', '\\').Replace('"', '\"').Replace(#13, '\r').Replace(#10, '\n') + '"}' +
      '}';
  end;
  
  LJSON := LJSON + '}';

  LStream := TStringStream.Create(LJSON, TEncoding.UTF8);
  try
    try
      SetLength(LHeaders, 1);
      LHeaders[0] := TNetHeader.Create('Content-Type', 'application/json');
      FClient.Post('http://localhost:' + FPort.ToString + '/', LStream, nil, LHeaders);
    except
      on E: Exception do
        SafeWriteLn('TDextTestExplorerListener.OnTestComplete: POST failed: ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    LStream.Free;
  end;
end;

procedure RunTests(const Config: TTestConfigurator);
begin
  TTestHost.Execute(Config);
end;

procedure RunTests; overload;
begin
  TTestHost.Execute;
end;

{ TTestHost }

class procedure TTestHost.Execute;
begin
  Execute(TTest.Configure);
end;

class procedure TTestHost.Execute(const Config: TTestConfigurator);
var
  CommandLine: string;
  Index: Integer;
  LogFile: string;
  LogStrings: TStringList;
  IsLogEnabled: Boolean;
  ParentProcess: string;
  P: string;
  LPort: Integer;
  {$IFDEF MSWINDOWS}
  IsUI: Boolean;
  {$ENDIF}
  {$IFNDEF MSWINDOWS}
  i: Integer;
  {$ENDIF}
  Client: THTTPClient;
  Resp: IHTTPResponse;
  JSONStr: string;
  Start: Integer;
  EndPos: Integer;
  TestsList: TStringList;
  Inner: string;
  Parts: TArray<string>;
  Part: string;
  Cleaned: string;
  SelectedArr: TArray<string>;
  Idx: Integer;

begin
  ParentProcess := GetParentProcessName;
  // 1. Detect parameters first
  IsLogEnabled := False;
  LogFile := '';
  LPort := 0;
  {$IFDEF MSWINDOWS}
  IsUI := False;
  {$ENDIF}
  for Index := 1 to ParamCount do
  begin
    P := ParamStr(Index);
    // Detect Log
    if (CompareText(P, '/log') = 0) or (CompareText(P, '-log') = 0) then
    begin
      IsLogEnabled := True;
      LogFile := ChangeFileExt(ParamStr(0), '.log');
    end
    else if P.StartsWith('--port', True) or P.StartsWith('-port', True) then
    begin
      if (Index < ParamCount) and (not ParamStr(Index + 1).StartsWith('-')) then
        LPort := StrToIntDef(ParamStr(Index + 1), 0);
    end;

  end;


  // 2. Decide if we need UI or Console and Setup Environment
  {$IFDEF MSWINDOWS}
  // Auto-detect UI if any execution hook is active
  if (not IsUI) and TTestRunnerRegistry.IsAnyHookActive then
  begin
    IsUI := True;
  end;

  if not IsUI then
    SafeAttachConsole;
  {$ENDIF}

  // 3. Setup Logging if requested
  LogStrings := TStringList.Create;
  try
    if IsLogEnabled then
    begin
      InitializeDextWriter(TStringsWriter.Create(LogStrings));
      SafeWriteLn('--- DEXT TEST HOST LOG STARTED: ' + DateTimeToStr(Now) + ' ---');
      {$IFDEF MSWINDOWS}
      CommandLine := GetCommandLine;
      {$ELSE}
      // TODO : move to Dext.Utils.pas
      CommandLine := ParamStr(0);
      for i := 1 to ParamCount do
        CommandLine := CommandLine + ' ' + ParamStr(i);
      {$ENDIF}
      SafeWriteLn('CmdLine: ' +  CommandLine);
    end;
    
    {$IFDEF MSWINDOWS}
    if IsUI then
    begin
      if not TTestRunnerRegistry.TryExecuteActiveHook(procedure begin Config.Run; end) then
      begin
        SafeWriteLn('Warning: No UI test hook is active or registered.');
        SafeAttachConsole;
        Config.Run;
      end;
    end
    else
    {$ENDIF}
    begin
      SafeWriteLn('Dext Test Host - Console Mode');
      if LPort > 0 then
      begin
        TTestRunner.RegisterListener(TDextTestExplorerListener.Create(LPort));
        
        Client := THTTPClient.Create;
        try
          try
            Resp := Client.Get('http://localhost:' + LPort.ToString + '/tests');
            if Resp.StatusCode = 200 then
            begin
              JSONStr := Resp.ContentAsString(TEncoding.UTF8).Trim;
              if JSONStr.StartsWith('{') then
              begin
                Start := JSONStr.IndexOf('[');
                EndPos := JSONStr.LastIndexOf(']');
                if (Start >= 0) and (EndPos > Start) then
                  JSONStr := JSONStr.Substring(Start, EndPos - Start + 1);
              end;
              if JSONStr.StartsWith('[') and JSONStr.EndsWith(']') then
              begin
                TestsList := TStringList.Create;
                try
                  Inner := JSONStr.Substring(1, JSONStr.Length - 2).Trim;
                  if Inner <> '' then
                  begin
                    Parts := Inner.Split([',']);
                    for Part in Parts do
                    begin
                      Cleaned := Part.Trim;
                      if Cleaned.StartsWith('"') and Cleaned.EndsWith('"') then
                        Cleaned := Cleaned.Substring(1, Cleaned.Length - 2);
                      if Cleaned <> '' then
                        TestsList.Add(Cleaned);
                    end;
                  end;
                  if TestsList.Count > 0 then
                  begin
                    SetLength(SelectedArr, TestsList.Count);
                    for Idx := 0 to TestsList.Count - 1 do
                      SelectedArr[Idx] := TestsList[Idx];
                    TTestRunner.SetSelectedTests(SelectedArr);
                  end;
                finally
                  TestsList.Free;
                end;
              end;
            end;
          except
            on E: Exception do
              SafeWriteLn('TTestHost.Execute: Failed to fetch selected tests: ' + E.Message);
          end;
        finally
          Client.Free;
        end;
      end;
      Config.Run;
    end;
    
    // Set exit code based on failure
    if not TTestRunner.Succeeded then
      ExitCode := 1
    else
      ExitCode := 0;

    if IsLogEnabled and (LogFile <> '') then
    begin
      SafeWriteLn('--- DEXT TEST HOST LOG FINISHED (Summary: Fixtures=' + 
        TTestRunner.FixtureCount.ToString + ', Tests=' + TTestRunner.TestCount.ToString + ') ---');
      try
        LogStrings.SaveToFile(LogFile, TEncoding.UTF8);
      except
      end;
    end;
  finally
    // Pause if not CI/No-Wait
    if IsConsoleAvailable and not FindCmdLineSwitch('no-wait', ['-', '\'], True) then
    begin
      ConsolePause;
    end;
    
    // Crucial: Set writer to Nil before freeing the memory it points to!
    InitializeDextWriter(Nil);
    LogStrings.Free;
  end;
end;

end.
