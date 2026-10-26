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
{  Created: 2026-01-04                                                      }
{                                                                           }
{  Dext.Testing.Fluent - Fluent API for Test Configuration                  }
{                                                                           }
{  Provides an intuitive, chainable API for configuring and running tests:  }
{                                                                           }
{    TTest                                                                  }
{      .Configure                                                           }
{        .Verbose                                                           }
{        .ExportToJUnit('results.xml')                                      }
{        .ExportToJson('results.json')                                      }
{        .FilterByCategory('Unit')                                          }
{      .RegisterFixture(TMyTests)                                           }
{      .Run;                                                                }
{                                                                           }
{***************************************************************************}

{$I Dext.inc}

unit Dext.Testing.Fluent;

interface

uses
  System.SysUtils,
  Dext.Testing.Runner;

type
  TTestConfigurator = record
  private
    FVerbosity: TOutputVerbosity;
    FDebugDiscovery: Boolean;
    FUseDashboard: Boolean;
//    FDashboardPort: Integer;
    FWaitDashboard: Boolean;
    FJUnitFile: string;
    FJsonFile: string;
    FSonarQubeFile: string;
    FXUnitFile: string;
    FTRXFile: string;
    FHTMLFile: string;
    FCategories: TArray<string>;
    FTestPattern: string;
    FFixturePattern: string;
    FIncludeExplicit: Boolean;
    FFixtureClasses: TArray<TClass>;
    FUseExternalUI: Boolean;
    FAllowEmptyRun: Boolean;
  public
    /// <summary>
    ///   Enables verbose output with detailed test information.
    /// </summary>
    function Verbose: TTestConfigurator;
    
    /// <summary>
    ///   Enables very verbose output with full stack traces on error.
    /// </summary>
    function VeryVerbose: TTestConfigurator;

    /// <summary>
    ///   Disables verbose output (compact dot notation).
    /// </summary>
    function Compact: TTestConfigurator;

    /// <summary>
    ///   Enables debug discovery logging.
    /// </summary>
    /// <summary>
    ///   Enables debug discovery logging.
    /// </summary>
    function DebugDiscovery: TTestConfigurator;
    
    /// <summary>
    ///   Enables the Live Dashboard Runner.
    /// </summary>
    // function UseDashboard(Port: Integer = 9000; WaitAfterRun: Boolean = True): TTestConfigurator;

    /// <summary>
    ///   Enables integration with external IDE plugins.
    /// </summary>
    function UseExternalUI: TTestConfigurator;
    /// <summary>
    ///   Configures JUnit XML export.
    /// </summary>
    function ExportToJUnit(const FileName: string): TTestConfigurator;

    /// <summary>
    ///   Configures JSON report export.
    /// </summary>
    function ExportToJson(const FileName: string): TTestConfigurator;

    /// <summary>
    ///   Configures SonarQube report export.
    /// </summary>
    function ExportToSonarQube(const FileName: string): TTestConfigurator;

    /// <summary>
    ///   Configures xUnit.net v2 XML report export.
    /// </summary>
    function ExportToXUnit(const FileName: string): TTestConfigurator;

    /// <summary>
    ///   Configures Microsoft TRX report export (Azure DevOps compatible).
    /// </summary>
    function ExportToTRX(const FileName: string): TTestConfigurator;

    /// <summary>
    ///   Configures HTML report export (beautiful standalone report).
    /// </summary>
    function ExportToHtml(const FileName: string): TTestConfigurator;

    /// <summary>
    ///   Filters tests by category.
    /// </summary>
    function FilterByCategory(const Category: string): TTestConfigurator;

    /// <summary>
    ///   Filters tests by multiple categories.
    /// </summary>
    function FilterByCategories(const Categories: array of string): TTestConfigurator;

    /// <summary>
    ///   Filters tests by name pattern.
    /// </summary>
    function FilterByName(const Pattern: string): TTestConfigurator;

    /// <summary>
    ///   Filters fixtures by name pattern.
    /// </summary>
    function FilterByFixture(const Pattern: string): TTestConfigurator;

    /// <summary>
    ///   Includes explicit tests in the run.
    /// </summary>
    function IncludeExplicitTests: TTestConfigurator;

    /// <summary>
    ///   Treats a run that executes zero tests as a success. By default an
    ///   empty run fails, so a filter that matches nothing or [Test] methods
    ///   left out of the public section do not leave the pipeline green.
    ///   Command line: -allow-empty.
    /// </summary>
    function AllowEmptyRun: TTestConfigurator;
    
    /// <summary>
    ///  Filters tests by a manual selection (Unit.Class.Test).
    /// </summary>
    function FilterBySelection(const Tests: TArray<string>): TTestConfigurator;

    /// <summary>
    ///   Registers a fixture class (for classes in .dpr files).
    /// </summary>
    function RegisterFixture(AClass: TClass): TTestConfigurator;

    /// <summary>
    ///   Registers multiple fixture classes.
    /// </summary>
    function RegisterFixtures(const Classes: array of TClass): TTestConfigurator;

    function IsExternalUIActive: Boolean;
    function IsDashboardActive: Boolean;
    function GetFixtureClasses: TArray<TClass>;

    /// <summary>
    ///   Runs all registered/discovered tests with the configured options.
    ///   Returns True if all tests passed.
    /// </summary>
    function Run: Boolean;

    /// <summary>
    ///   Returns the test summary after running.
    /// </summary>
    function GetSummary: TTestSummary;
  end;

  /// <summary>
  ///   Main entry point for fluent test configuration.
  /// </summary>
  TTest = record
  public
    /// <summary>
    ///   Starts the fluent configuration.
    /// </summary>
    class function Configure: TTestConfigurator; static;

    /// <summary>
    ///   Quick run with defaults - discover and execute all tests.
    /// </summary>
    class function RunAll: Boolean; static;

    /// <summary>
    ///   Quick run with verbose output.
    /// </summary>
    class function RunAllVerbose: Boolean; static;

    /// <summary>
    ///   Quick run a specific fixture.
    /// </summary>
    class function RunFixture(AClass: TClass): Boolean; static;

    /// <summary>
    ///   Quick run tests in a category.
    /// </summary>
    class function RunCategory(const Category: string): Boolean; static;
    
    /// <summary>
    ///   Sets the application ExitCode based on boolean success.
    ///   True = 0 (Success), False = 1 (Error).
    /// </summary>
    class procedure SetExitCode(Success: Boolean); static;
    
    /// <summary>
    ///   Sets application ExitCode to 0 (Success).
    /// </summary>
    class procedure SetResultSuccess; static;
    
    /// <summary>
    ///   Sets application ExitCode to 1 (Error).
    /// </summary>
    class procedure SetResultError; static;
    
    /// <summary>
    ///   Checks if we are running in External UI mode
    /// </summary>
    class function IsExternalUI: Boolean; static;
  end;

function ConfigureTests: TTestConfigurator;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  Dext.Testing.Report,
  //Dext.Testing.Dashboard,

  Dext.Utils;

function ConfigureTests: TTestConfigurator;
begin
  Result := TTest.Configure;
end;

{ TTestConfigurator }

function TTestConfigurator.Verbose: TTestConfigurator;
begin
  FVerbosity := ovDefault;
  Result := Self;
end;

function TTestConfigurator.VeryVerbose: TTestConfigurator;
begin
  FVerbosity := ovVerbose;
  Result := Self;
end;

function TTestConfigurator.Compact: TTestConfigurator;
begin
  FVerbosity := ovSilent;
  Result := Self;
end;

function TTestConfigurator.DebugDiscovery: TTestConfigurator;
begin
  FDebugDiscovery := True;
  Result := Self;
end;

//function TTestConfigurator.UseDashboard(Port: Integer; WaitAfterRun: Boolean): TTestConfigurator;
//begin
//  FUseDashboard := True;
//  FDashboardPort := Port;
//  FWaitDashboard := WaitAfterRun;
//  Result := Self;
//end;

function TTestConfigurator.UseExternalUI: TTestConfigurator;
begin
  FUseExternalUI := True;
  Result := Self;
end;

function TTestConfigurator.ExportToJUnit(const FileName: string): TTestConfigurator;
begin
  FJUnitFile := FileName;
  Result := Self;
end;

function TTestConfigurator.ExportToJson(const FileName: string): TTestConfigurator;
begin
  FJsonFile := FileName;
  Result := Self;
end;

function TTestConfigurator.ExportToSonarQube(const FileName: string): TTestConfigurator;
begin
  FSonarQubeFile := FileName;
  Result := Self;
end;

function TTestConfigurator.ExportToXUnit(const FileName: string): TTestConfigurator;
begin
  FXUnitFile := FileName;
  Result := Self;
end;

function TTestConfigurator.ExportToTRX(const FileName: string): TTestConfigurator;
begin
  FTRXFile := FileName;
  Result := Self;
end;

function TTestConfigurator.ExportToHtml(const FileName: string): TTestConfigurator;
begin
  FHTMLFile := FileName;
  Result := Self;
end;

function TTestConfigurator.FilterByCategory(const Category: string): TTestConfigurator;
begin
  SetLength(FCategories, Length(FCategories) + 1);
  FCategories[High(FCategories)] := Category;
  Result := Self;
end;

function TTestConfigurator.FilterByCategories(const Categories: array of string): TTestConfigurator;
var
  I, Start: Integer;
begin
  Start := Length(FCategories);
  SetLength(FCategories, Start + Length(Categories));
  for I := 0 to High(Categories) do
    FCategories[Start + I] := Categories[I];
  Result := Self;
end;

function TTestConfigurator.FilterByName(const Pattern: string): TTestConfigurator;
begin
  FTestPattern := Pattern;
  Result := Self;
end;

function TTestConfigurator.FilterByFixture(const Pattern: string): TTestConfigurator;
begin
  FFixturePattern := Pattern;
  Result := Self;
end;

function TTestConfigurator.IncludeExplicitTests: TTestConfigurator;
begin
  FIncludeExplicit := True;
  Result := Self;
end;

function TTestConfigurator.AllowEmptyRun: TTestConfigurator;
begin
  FAllowEmptyRun := True;
  Result := Self;
end;

function TTestConfigurator.FilterBySelection(const Tests: TArray<string>): TTestConfigurator;
begin
  TTestRunner.SetSelectedTests(Tests);
  Result := Self;
end;

function TTestConfigurator.RegisterFixture(AClass: TClass): TTestConfigurator;
begin
  SetLength(FFixtureClasses, Length(FFixtureClasses) + 1);
  FFixtureClasses[High(FFixtureClasses)] := AClass;
  Result := Self;
end;

function TTestConfigurator.RegisterFixtures(const Classes: array of TClass): TTestConfigurator;
var
  I, Start: Integer;
begin
  Start := Length(FFixtureClasses);
  SetLength(FFixtureClasses, Start + Length(Classes));
  for I := 0 to High(Classes) do
    FFixtureClasses[Start + I] := Classes[I];
  Result := Self;
end;

function TTestConfigurator.Run: Boolean;
var
  Filter: TTestFilter;
  Cls: TClass;
  I: Integer;
  P: string;
begin
  // Apply configuration
  TTestRunner.SetVerbosity(FVerbosity);
  TTestRunner.SetDebugDiscovery(FDebugDiscovery);

  // Check for CI/Headless override
  if FindCmdLineSwitch('dext-headless', ['-', '/'], True) or 
     (GetEnvironmentVariable('DEXT_HEADLESS') = '1') then
  begin
    FUseDashboard := False;
    FWaitDashboard := False;
  end;

  // Check for Overrides via Command Line
  for I := 1 to ParamCount do
  begin
    P := ParamStr(I);
    if P.StartsWith('-junit:', True) or P.StartsWith('/junit:', True) then
      FJUnitFile := P.Substring(7).DeQuotedString('"')
    else if P.StartsWith('-html:', True) or P.StartsWith('/html:', True) then
      FHTMLFile := P.Substring(6).DeQuotedString('"')
    else if P.StartsWith('-json:', True) or P.StartsWith('/json:', True) then
      FJsonFile := P.Substring(6).DeQuotedString('"')
      
    // Filter overrides
    else if P.StartsWith('-filter:', True) or P.StartsWith('/filter:', True) then
      FTestPattern := P.Substring(8).DeQuotedString('"')
    else if P.StartsWith('-fixture:', True) or P.StartsWith('/fixture:', True) then
      FFixturePattern := P.Substring(9).DeQuotedString('"')
    else if P.StartsWith('-category:', True) or P.StartsWith('/category:', True) then
      FilterByCategory(P.Substring(10).DeQuotedString('"'))
      
    // Behavior overrides
    else if  (P = '-no-wait') or (P = '/no-wait') then
      FWaitDashboard := False
    else if (P = '-no-dashboard') or (P = '/no-dashboard') then
      FUseDashboard := False
    else if (P = '-externalui') or (P = '/externalui') then
      FUseExternalUI := True
    else if (P = '-allow-empty') or (P = '/allow-empty') then
      FAllowEmptyRun := True;
  end;
  TTestRunner.SetAllowEmptyRun(FAllowEmptyRun);

  // Start External UI
  if FUseExternalUI and not TTestRunner.IsExternalUIActive then
  begin
    // Since the framework no longer directly depends on External UI
    // the integration should be registered externally via uses clause.
    if not TTestRunner.IsExternalUIActive then
      SafeWriteLn('Warning: External UI integration is not active. Please add Dext\Sources\Common\Dext.Testing.* to your uses clause.');
  end;

  // Start Dashboard
  if FUseDashboard then
  begin
    // TDashboardListener auto-registers itself with TTestRunner in Start.
    // The instance is kept alive by TTestRunner's interface list.
    // TDashboardListener.Create(FDashboardPort).Start;
  end;

  // Register fixtures
  for Cls in FFixtureClasses do
  begin
    TTestRunner.RegisterFixture(Cls);
  end;

  // If no fixtures registered, discover automatically
  if (Length(FFixtureClasses) = 0) and (TTestRunner.FixtureCount = 0) then
  begin
    TTestRunner.Discover;
  end;

  // Build filter
  Filter := Default(TTestFilter);
  Filter.Categories := FCategories;
  Filter.TestNamePattern := FTestPattern;
  Filter.FixtureNamePattern := FFixturePattern;
  Filter.IncludeExplicit := FIncludeExplicit;

  // Run tests
  if (Length(FCategories) > 0) or (FTestPattern <> '') or 
     (FFixturePattern <> '') or FIncludeExplicit then
    TTestRunner.RunFiltered(Filter)
  else
    TTestRunner.RunAll;

  // Export reports
  if FJUnitFile <> '' then
    TTestRunner.SaveJUnitReport(FJUnitFile);
  if FJsonFile <> '' then
    TTestRunner.SaveJsonReport(FJsonFile);
  if FXUnitFile <> '' then
    TTestRunner.SaveXUnitReport(FXUnitFile);
  if FTRXFile <> '' then
    TTestRunner.SaveTRXReport(FTRXFile);
  if FSonarQubeFile <> '' then
    TTestRunner.SaveSonarQubeReport(FSonarQubeFile);
  if FHTMLFile <> '' then
    TTestRunner.SaveHTMLReport(FHTMLFile);

  // Return success status
  Result := TTestRunner.Succeeded;

  // Let Sidecar Sinks (Logging) and External UI REST posts flush properly
  // This avoids premature process kill before all data is sent.
  if FUseExternalUI or FUseDashboard then
    Sleep(500);

  if FUseDashboard and FWaitDashboard then
  begin
    {$IFDEF MSWINDOWS}
    if (GetStdHandle(STD_OUTPUT_HANDLE) <> 0) and (GetStdHandle(STD_OUTPUT_HANDLE) <> INVALID_HANDLE_VALUE) then
    begin
      SafeWriteLn;
      SafeWriteLn('Press ENTER to close dashboard and exit...');
      ReadLn;
    end;
    {$ENDIF}
  end;

  // Clean up listeners to prevent memory leaks from late finalization
  TTestRunner.ClearListeners;
end;

function TTestConfigurator.IsExternalUIActive: Boolean;
begin
  Result := FUseExternalUI;
end;

function TTestConfigurator.IsDashboardActive: Boolean;
begin
  Result := FUseDashboard;
end;

function TTestConfigurator.GetFixtureClasses: TArray<TClass>;
begin
  Result := FFixtureClasses;
end;

function TTestConfigurator.GetSummary: TTestSummary;
begin
  Result := TTestRunner.Summary;
end;

{ TTest }

class function TTest.Configure: TTestConfigurator;
begin
  Result := Default(TTestConfigurator);
  Result.FVerbosity := ovSilent;  // Default to compact (dot) mode
end;

class function TTest.RunAll: Boolean;
begin
  TTestRunner.Discover;
  TTestRunner.RunAll;
  Result := TTestRunner.Succeeded;
end;

class function TTest.RunAllVerbose: Boolean;
begin
  Result := TTest.Configure
    .Verbose
    .Run;
end;

class function TTest.RunFixture(AClass: TClass): Boolean;
begin
  Result := TTest.Configure
    .RegisterFixture(AClass)
    .Run;
end;

class function TTest.RunCategory(const Category: string): Boolean;
begin
  Result := TTest.Configure
    .FilterByCategory(Category)
    .Run;
end;

class procedure TTest.SetExitCode(Success: Boolean);
begin
  if Success then
    ExitCode := 0
  else
    ExitCode := 1;
end;

class procedure TTest.SetResultSuccess;
begin
  ExitCode := 0;
end;

class procedure TTest.SetResultError;
begin
  ExitCode := 1;
end;

class function TTest.IsExternalUI: Boolean;
begin
  Result := TTestRunner.IsExternalUIActive;
end;

initialization

finalization
  TTestRunner.Clear;
  
end.
