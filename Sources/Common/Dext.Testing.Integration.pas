{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
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
unit Dext.Testing.Integration;

interface

uses
  System.SysUtils,
  System.Classes,
  System.TimeSpan;

type
  TTestResult = (trNone, trPassed, trFailed, trSkipped, trTimeout, trError);

  TTestInfo = record
    FixtureName: string;
    UnitName: string;
    ClassName: string;
    TestName: string;
    DisplayName: string;
    Result: TTestResult;
    Duration: TTimeSpan;
    ErrorMessage: string;
    ExceptionName: string;
    StackTrace: string;
    CodeAddress: Pointer;
    Categories: TArray<string>;
  end;

type
  ITestRunnerIntegration = interface
    ['{BCB5C2DF-E81D-4A59-BF26-6DF4804FEA97}']
    function GetName: string;
    procedure Execute(const APort: Integer);
  end;

  ITestExecutionHook = interface
    ['{E4B8B67D-89C0-466D-B029-44F43F96245F}']
    function IsActive: Boolean;
    procedure Execute(const ARunProc: TProc);
  end;

  TTestRunnerRegistry = class
  private
    class var FIntegrations: TInterfaceList;
    class var FExecutionHooks: TInterfaceList;
    class function GetIntegrations: TInterfaceList; static;
    class function GetExecutionHooks: TInterfaceList; static;
  public
    class procedure RegisterIntegration(const AIntegration: ITestRunnerIntegration); static;
    class function TryExecuteFromCommandLine: Boolean; static;
    class procedure RegisterExecutionHook(const AHook: ITestExecutionHook); static;
    class function TryExecuteActiveHook(const ARunProc: TProc): Boolean; static;
    class function IsAnyHookActive: Boolean; static;
  end;

implementation

{ TTestRunnerRegistry }

class function TTestRunnerRegistry.GetIntegrations: TInterfaceList;
begin
  if FIntegrations = nil then
    FIntegrations := TInterfaceList.Create;
  Result := FIntegrations;
end;

class procedure TTestRunnerRegistry.RegisterIntegration(const AIntegration: ITestRunnerIntegration);
begin
  GetIntegrations.Add(AIntegration);
end;

class function TTestRunnerRegistry.TryExecuteFromCommandLine: Boolean;
var
  PortStr: string;
  Port: Integer;
  Intf: IInterface;
  Runner: ITestRunnerIntegration;
begin
  Result := False;
  if FindCmdLineSwitch('port', PortStr, True) or FindCmdLineSwitch('-port', PortStr, True) then
  begin
    Port := StrToIntDef(PortStr, 8102);
    if GetIntegrations.Count > 0 then
    begin
      Intf := GetIntegrations[0];
      if Supports(Intf, ITestRunnerIntegration, Runner) then
      begin
        Runner.Execute(Port);
        Result := True;
      end;
    end;
  end;
end;

class function TTestRunnerRegistry.GetExecutionHooks: TInterfaceList;
begin
  if FExecutionHooks = nil then
    FExecutionHooks := TInterfaceList.Create;
  Result := FExecutionHooks;
end;

class procedure TTestRunnerRegistry.RegisterExecutionHook(const AHook: ITestExecutionHook);
begin
  GetExecutionHooks.Add(AHook);
end;

class function TTestRunnerRegistry.TryExecuteActiveHook(const ARunProc: TProc): Boolean;
var
  i: Integer;
  Intf: IInterface;
  Hook: ITestExecutionHook;
begin
  Result := False;
  for i := 0 to GetExecutionHooks.Count - 1 do
  begin
    Intf := GetExecutionHooks[i];
    if Supports(Intf, ITestExecutionHook, Hook) then
    begin
      if Hook.IsActive then
      begin
        Hook.Execute(ARunProc);
        Exit(True);
      end;
    end;
  end;
end;

class function TTestRunnerRegistry.IsAnyHookActive: Boolean;
var
  i: Integer;
  Intf: IInterface;
  Hook: ITestExecutionHook;
begin
  Result := False;
  for i := 0 to GetExecutionHooks.Count - 1 do
  begin
    Intf := GetExecutionHooks[i];
    if Supports(Intf, ITestExecutionHook, Hook) then
    begin
      if Hook.IsActive then
        Exit(True);
    end;
  end;
end;

initialization

finalization
  if TTestRunnerRegistry.FIntegrations <> nil then
    TTestRunnerRegistry.FIntegrations.Free;
  if TTestRunnerRegistry.FExecutionHooks <> nil then
    TTestRunnerRegistry.FExecutionHooks.Free;

end.

