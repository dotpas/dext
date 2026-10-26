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
{  Dext.Testing.Runner - Attribute-Based Test Discovery and Execution       }
{                                                                           }
{  Provides automatic test discovery via RTTI scanning and execution        }
{  of tests marked with [TestFixture] and [Test] attributes.                }
{                                                                           }
{***************************************************************************}

unit Dext.Testing.Runner;

interface

uses
  System.Classes,
  System.Diagnostics,
  System.Rtti,
  System.SysUtils,
  System.TimeSpan,
  System.TypInfo,
  Dext.Collections,
  Dext.Core.Debug,
  Dext.Testing.Attributes,
  Dext.Testing.Integration;

type
  /// <summary>
  ///   Output verbosity levels for test execution.
  /// </summary>
  TOutputVerbosity = (ovSilent, ovDefault, ovVerbose);

  /// <summary>
  ///   Summary of test run results.
  /// </summary>
  TTestSummary = record
    TotalTests: Integer;
    Passed: Integer;
    Failed: Integer;
    Skipped: Integer;
    Errors: Integer;
    TotalDuration: TTimeSpan;
    procedure Reset;
  end;

  /// <summary>
  ///   Filter options for test discovery and execution.
  /// </summary>
  TTestFilter = record
    Categories: TArray<string>;
    TestNamePattern: string;
    FixtureNamePattern: string;
    IncludeExplicit: Boolean;
    function Matches(const AUnitName, AClassName, AFixtureName, ATestName: string;
      const ACategories: TArray<string>; AIsExplicit: Boolean;
      const ASelectedTests: TArray<string> = []): Boolean;
  end;

  /// <summary>
  ///   Event fired before each test runs.
  /// </summary>
  TTestStartEvent = procedure(const UnitName, Fixture, Test: string) of object;

  /// <summary>
  ///   Event fired after each test completes.
  /// </summary>
  TTestCompleteEvent = procedure(const Info: TTestInfo) of object;

  /// <summary>
  ///   Event fired when a fixture starts.
  /// </summary>
  TFixtureStartEvent = procedure(const FixtureName: string; TestCount: Integer) of object;

  /// <summary>
  ///   Event fired when a fixture completes.
  /// </summary>
  TFixtureCompleteEvent = procedure(const FixtureName: string) of object;

  /// <summary>
  ///   Interface for listening to test execution events.
  /// </summary>
  ITestListener = interface
    ['{88439A1D-F6E2-4D5C-8A9B-1234567890AB}']
    procedure OnRunStart(TotalTests: Integer);
    procedure OnRunComplete(const Summary: TTestSummary);
    procedure OnFixtureStart(const FixtureName: string; TestCount: Integer);
    procedure OnFixtureComplete(const FixtureName: string);
    procedure OnTestStart(const UnitName, Fixture, Test: string);
    procedure OnTestComplete(const Info: TTestInfo);
  end;

  /// <summary>
  ///   Output format for test results.
  /// </summary>
  TOutputFormat = (ofConsole, ofXUnit, ofJUnit);

  /// <summary>
  ///   Discovered test fixture information.
  /// </summary>
  TTestFixtureInfo = class
  private
    FRttiType: TRttiType;
    FFixtureClass: TClass;
    FName: string;
    FDescription: string;
    FSetupMethod: TRttiMethod;
    FTearDownMethod: TRttiMethod;
    FBeforeAllMethod: TRttiMethod;
    FAfterAllMethod: TRttiMethod;
    FTestMethods: IList<TRttiMethod>;
  public
    constructor Create(ARttiType: TRttiType);
    destructor Destroy; override;
    property RttiType: TRttiType read FRttiType;
    property FixtureClass: TClass read FFixtureClass;
    property Name: string read FName;
    property Description: string read FDescription;
    property SetupMethod: TRttiMethod read FSetupMethod;
    property TearDownMethod: TRttiMethod read FTearDownMethod;
    property BeforeAllMethod: TRttiMethod read FBeforeAllMethod;
    property AfterAllMethod: TRttiMethod read FAfterAllMethod;
    property TestMethods: IList<TRttiMethod> read FTestMethods;
  end;

  /// <summary>
  ///   Context object injected into tests that need runtime information.
  /// </summary>
  ITestContext = interface
    ['{F1E2D3C4-B5A6-7890-1234-567890ABCDEF}']
    function GetCurrentTest: string;
    function GetCurrentFixture: string;
    procedure WriteLine(const Msg: string); overload;
    procedure WriteLine(const Fmt: string; const Args: array of const); overload;
    procedure AttachFile(const FilePath: string);
    property CurrentTest: string read GetCurrentTest;
    property CurrentFixture: string read GetCurrentFixture;
  end;

  /// <summary>
  ///   Implementation of ITestContext for runtime test information.
  /// </summary>
  TTestContext = class(TInterfacedObject, ITestContext)
  private
    FCurrentTest: string;
    FCurrentFixture: string;
    FOutput: TStringBuilder;
    FAttachedFiles: IList<string>;
  public
    constructor Create(const AFixture, ATest: string);
    destructor Destroy; override;

    function GetCurrentTest: string;
    function GetCurrentFixture: string;
    procedure WriteLine(const Msg: string); overload;
    procedure WriteLine(const Fmt: string; const Args: array of const); overload;
    procedure AttachFile(const FilePath: string);

    function GetOutput: string;
    function GetAttachedFiles: TArray<string>;
  end;

  /// <summary>
  ///   Main test runner that discovers and executes attribute-based tests.
  /// </summary>
  TTestRunner = class
  private
    class var FFixtures: IList<TTestFixtureInfo>;
    class var FSummary: TTestSummary;
    class var FFilter: TTestFilter;
    class var FVerbosity: TOutputVerbosity;
    class var FDebugDiscovery: Boolean;
    class var FOutputFormat: TOutputFormat;
    class var FReportFileName: string;
    class var FReportFormat: TOutputFormat;
    class var FTestResults: IList<TTestInfo>;
    class var FDiscoveryMode: Boolean;
    class var FSelectedTests: TArray<string>;
    class var FAllowEmptyRun: Boolean;

    // Assembly-level hooks (execute once for entire test suite)
    class var FAssemblyInitMethod: TRttiMethod;
    class var FAssemblyCleanupMethod: TRttiMethod;
    class var FAssemblyHookClass: TClass;

    class var FOnTestStart: TTestStartEvent;
    class var FOnTestComplete: TTestCompleteEvent;
    class var FOnFixtureStart: TFixtureStartEvent;
    class var FOnFixtureComplete: TFixtureCompleteEvent;

    class var FListeners: IList<ITestListener>;
    class var FIsExternalUIActive: Boolean;

    class procedure NotifyRunStart(TotalTests: Integer);
    class procedure NotifyRunComplete(const Summary: TTestSummary);
    class procedure NotifyFixtureStart(const FixtureName: string; TestCount: Integer);
    class procedure NotifyFixtureComplete(const FixtureName: string);
    class procedure NotifyTestStart(const UnitName, Fixture, Test: string);
    class procedure NotifyTestComplete(const Info: TTestInfo);

    class procedure DiscoverFixtures;
    class procedure DiscoverTestMethods(Fixture: TTestFixtureInfo);
    class procedure DiscoverAssemblyHooks;
    class procedure ExecuteAssemblyInit;
    class procedure ExecuteAssemblyCleanup;
    class function HasAttribute<T: TCustomAttribute>(
      const Attrs: TArray<TCustomAttribute>): Boolean; overload;
    class function GetAttribute<T: TCustomAttribute>(
      const Attrs: TArray<TCustomAttribute>): T; overload;
    class function GetAttributes<T: TCustomAttribute>(
      const Attrs: TArray<TCustomAttribute>): TArray<T>;
    class function GetCategories(Method: TRttiMethod; FixtureClass: TClass): TArray<string>;
    class function IsExplicit(Method: TRttiMethod): Boolean;
    class function GetIgnoreReason(Method: TRttiMethod): string;
    class function GetRepeatCount(Method: TRttiMethod): Integer;
    class function GetMaxTime(Method: TRttiMethod): Integer;
    class function GetPriority(Method: TRttiMethod): Integer;
    class function ShouldRunOnPlatform(Method: TRttiMethod): Boolean;
    class procedure ExecuteFixture(Fixture: TTestFixtureInfo);
    class procedure ExecuteTest(Fixture: TTestFixtureInfo;
      Method: TRttiMethod; Instance: TObject;
      const TestCaseValues: TArray<TValue>;
      const TestCaseDisplayName: string);
    class function GetTestCases(Method: TRttiMethod): TArray<TArray<TValue>>;
    class function GetTestCaseDisplayNames(Method: TRttiMethod): TArray<string>;
    class procedure PrintTestResult(const Info: TTestInfo);
    class procedure PrintSummary;
    class procedure PrintResultChar(Result: TTestResult);
  protected
    class function GetTimeout(Method: TRttiMethod): Integer;
    class function GetActiveTestCount(Fixture: TTestFixtureInfo): Integer; overload;
    class procedure ReportFixtureFailure(Fixture: TTestFixtureInfo; const Stage: string; E: Exception);
  public
    /// <summary>
    ///   Discovers all test fixtures in the application.
    /// </summary>
    class procedure Discover;

    /// <summary>
    ///   Runs all discovered tests.
    /// </summary>
    class procedure RunAll;

    /// <summary>
    ///   Registers a listener for test execution events.
    /// </summary>
    class procedure RegisterListener(const Listener: ITestListener);

    /// <summary>
    ///   Unregisters and clears all listeners.
    /// </summary>
    class procedure ClearListeners;

    /// <summary>
    ///   Runs tests matching the specified filter.
    /// </summary>
    class procedure RunFiltered(const AFilter: TTestFilter);

    /// <summary>
    ///   Runs tests in a specific category.
    /// </summary>
    class procedure RunCategory(const Category: string);

    /// <summary>
    ///   Runs a single test fixture by class.
    /// </summary>
    class procedure RunFixture(AFixtureClass: TClass);

    /// <summary>
    ///   Runs a single test by name pattern.
    /// </summary>
    class procedure RunTest(const ATestNamePattern: string);

    /// <summary>
    ///   Returns the test summary after a run.
    /// </summary>
    class function Summary: TTestSummary;

    /// <summary>
    ///   True when no test failed and at least one test ran. A run that
    ///   executes zero tests (non-public [Test] methods, a filter that matches
    ///   nothing) is a failure unless SetAllowEmptyRun(True) was called.
    /// </summary>
    class function Succeeded: Boolean;
    class procedure SetAllowEmptyRun(AValue: Boolean);

    /// <summary>
    ///   Sets verbose output mode.
    /// </summary>
    class procedure SetVerbosity(AValue: TOutputVerbosity);

    /// <summary>
    ///   Sets the output format.
    /// </summary>
    class procedure SetOutputFormat(AFormat: TOutputFormat);

    /// <summary>
    ///   Returns the discovered fixture count.
    /// </summary>
    class function FixtureCount: Integer;

    /// <summary>
    ///   Returns the total discovered test count.
    /// </summary>
    class function TestCount: Integer;
    class function GetActiveTestCount: Integer; overload;

    /// <summary>
    ///   Clears discovered fixtures (for re-discovery).
    /// </summary>
    class procedure Clear;

    /// <summary>
    ///   Registers a test fixture class manually.
    ///   Use this for classes defined in the main program (.dpr)
    ///   where RTTI discovery may not work automatically.
    /// </summary>
    class procedure RegisterFixture(AClass: TClass); overload;

    /// <summary>
    ///   Registers multiple test fixture classes at once.
    /// </summary>
    class procedure RegisterFixture(const AClasses: array of TClass); overload;

    /// <summary>
    ///   Enables debug output during discovery phase.
    /// </summary>
    class procedure SetDebugDiscovery(AValue: Boolean);

    /// <summary>
    ///   Enables or disables discovery mode (skips test execution).
    /// </summary>
    class procedure SetDiscoveryMode(Value: Boolean);

    /// <summary>
    ///   Restricts test execution to a specific list of full names.
    /// </summary>
    class procedure SetSelectedTests(const Tests: TArray<string>);

    /// <summary>
    ///   Returns if the runner is currently in discovery mode.
    /// </summary>
    class function IsDiscoveryMode: Boolean;

    /// <summary>
    ///   Returns the list of currently selected tests for execution.
    /// </summary>
    class function GetSelectedTests: TArray<string>;
    class function GetAllTestPaths: TArray<string>;
    class function IsExternalUIActive: Boolean; static;
    class procedure SetExternalUIActive(Value: Boolean); static;

    /// <summary>
    ///   Configures automatic report file generation after test run.
    /// </summary>
    /// <param name="FileName">Output file path (e.g., 'test-results.xml')</param>
    /// <param name="Format">Report format (ofConsole, ofXUnit, ofJUnit)</param>
    class procedure SetReportFile(const FileName: string; Format: TOutputFormat = ofJUnit);

    /// <summary>
    ///   Saves test results to a JUnit XML file.
    ///   Call this after RunAll or RunFiltered.
    /// </summary>
    class procedure SaveJUnitReport(const FileName: string);

    /// <summary>
    ///   Saves test results to a JSON file.
    ///   Call this after RunAll or RunFiltered.
    /// </summary>
    class procedure SaveJsonReport(const FileName: string);

    /// <summary>
    ///   Saves test results to a xUnit.net v2 XML file.
    /// </summary>
    class procedure SaveXUnitReport(const FileName: string);

    /// <summary>
    ///   Saves test results to a Microsoft TRX file (Azure DevOps compatible).
    /// </summary>
    class procedure SaveTRXReport(const FileName: string);

    /// <summary>
    ///   Saves test results to a SonarQube Generic Test Data XML file.
    /// </summary>
    class procedure SaveSonarQubeReport(const FileName: string);

    /// <summary>
    ///   Saves test results to a beautiful standalone HTML file.
    /// </summary>
    class procedure SaveHTMLReport(const FileName: string);

    // Events
    class property OnTestStart: TTestStartEvent read FOnTestStart write FOnTestStart;
    class property OnTestComplete: TTestCompleteEvent read FOnTestComplete write FOnTestComplete;
    class property OnFixtureStart: TFixtureStartEvent read FOnFixtureStart write FOnFixtureStart;
    class property OnFixtureComplete: TFixtureCompleteEvent read FOnFixtureComplete write FOnFixtureComplete;
    class property Verbosity: TOutputVerbosity read FVerbosity write FVerbosity;
  end;

  /// <summary>
  ///   Console output helpers for test results.
  /// </summary>
  TTestConsole = class
  public
    class procedure WriteColored(const Text: string; Color: Word);
    class procedure WritePass(const Text: string);
    class procedure WriteFail(const Text: string);
    class procedure WriteSkip(const Text: string);
    class procedure WriteInfo(const Text: string);
    class procedure WriteHeader(const Text: string);
  end;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.ActiveX,
  {$ENDIF}
  System.StrUtils,
  System.RegularExpressions,
  System.IOUtils,
  Dext.Logging,
  Dext.Logging.Global,
  Dext.Testing.Report,
  Dext.Testing.StackTrace,
  Dext.Core.Reflection,
  Dext.Utils;

const
  CONSOLE_COLOR_GREEN = 10;
  CONSOLE_COLOR_RED = 12;
  CONSOLE_COLOR_YELLOW = 14;
  CONSOLE_COLOR_CYAN = 11;
  CONSOLE_COLOR_WHITE = 15;
  CONSOLE_COLOR_GRAY = 8;

  // Unicode Emoji Constants (Hex to avoid source encoding issues)
  ICON_ROCKET  = #$D83D#$DE80; // 🚀
  ICON_LIGHT   = #$26A1;       // ⚡
  ICON_PASS    = #$2705;       // ✅
  ICON_FAIL    = #$274C;       // ❌
  ICON_WARN    = #$26A0;       // ⚠️
  ICON_INFO    = #$2139;       // ℹ️
  ICON_CHART   = #$D83D#$DCCA; // 📊
  ICON_TIMER   = #$23F1;       // ⏱️
  ICON_PASS_RT = #$D83D#$DCC8; // 📈
  ICON_CELEBRATE = #$D83C#$DF89; // 🎉
  ICON_CRASH   = #$D83D#$DCA5; // 💥
  ICON_TEST    = #$D83E#$DDEA; // 🧪
  ICON_STOP    = #$26D4;       // ⛔

/// <summary>
///   Lifecycle methods may be declared as class procedures; RTTI then needs
///   the class, not the instance, or it raises "Invalid class typecast".
/// </summary>
procedure InvokeLifecycle(Method: TRttiMethod; Instance: TObject; FixtureClass: TClass);
begin
  if Method.IsClassMethod or Method.IsStatic then
    Method.Invoke(FixtureClass, [])
  else
    Method.Invoke(Instance, []);
end;

type
  ETestTimeout = class(Exception);

  /// <summary>Runs the body of a test that has [Timeout].</summary>
  TTestBodyThread = class(TThread)
  private
    FBody: TProc;
    FError: TObject;
  protected
    procedure Execute; override;
  public
    constructor Create(const ABody: TProc);
    destructor Destroy; override;
  end;

var
  // Set when a timed-out test thread could not be stopped and still uses the fixture
  GFixtureInstanceAbandoned: Boolean;

constructor TTestBodyThread.Create(const ABody: TProc);
begin
  FBody := ABody;
  inherited Create(False);
  FreeOnTerminate := False;
end;

destructor TTestBodyThread.Destroy;
begin
  FError.Free;
  inherited;
end;

procedure TTestBodyThread.Execute;
begin
  NameThreadForDebugging('Dext test body');
  {$IFDEF MSWINDOWS}
  CoInitialize(nil);
  try
  {$ENDIF}
    try
      FBody();
    except
      FError := AcquireExceptionObject;
    end;
  {$IFDEF MSWINDOWS}
  finally
    CoUninitialize;
  end;
  {$ENDIF}
end;

procedure RaiseInterruptedByTimeout;
begin
  raise ETestTimeout.Create('Test thread interrupted by [Timeout]');
end;

{$IFDEF MSWINDOWS}
{$IFDEF CPUX64}
type
  TRuntimeFunction = record
    BeginAddress: Cardinal;
    EndAddress: Cardinal;
    UnwindData: Cardinal;
  end;
  PRuntimeFunction = ^TRuntimeFunction;

function RtlLookupFunctionEntry(ControlPc: UInt64; out ImageBase: UInt64;
  HistoryTable: Pointer): PRuntimeFunction; stdcall; external kernel32;

/// <summary>
///   True when Rip is in a function that never moves Rsp (no unwind info, or
///   unwind info without codes), so [Rsp] holds its return address.
/// </summary>
function IsFramelessCode(Rip: UInt64): Boolean;
const
  UNW_FLAG_CHAININFO = 4;
var
  ImageBase: UInt64;
  Entry: PRuntimeFunction;
  UnwindInfo: PByte;
begin
  Entry := RtlLookupFunctionEntry(Rip, ImageBase, nil);
  if Entry = nil then
    Exit(True);
  UnwindInfo := PByte(ImageBase + Entry.UnwindData);
  // UNWIND_INFO: Version:3 Flags:5 | SizeOfProlog | CountOfCodes | FrameRegister:4 FrameOffset:4
  Result := ((UnwindInfo[0] shr 3) and UNW_FLAG_CHAININFO = 0) and (UnwindInfo[2] = 0) and
    (UnwindInfo[3] and $0F = 0);
end;
{$ENDIF}

/// <summary>
///   Makes the thread raise ETestTimeout where it is, so its finally blocks run.
///   A thread waiting inside the kernel only raises when the wait returns.
/// </summary>
procedure InterruptThread(Handle: THandle);
var
  Buffer: Pointer;
  Ctx: PContext;
  Attempt: Integer;
  Redirected: Boolean;
begin
  // CONTEXT must be 16-byte aligned on Win64
  GetMem(Buffer, SizeOf(TContext) + 16);
  try
    Ctx := PContext((NativeUInt(Buffer) + 15) and not NativeUInt(15));
    for Attempt := 1 to 50 do
    begin
      if SuspendThread(Handle) = DWORD(-1) then
        Exit;
      Redirected := False;
      try
        FillChar(Ctx^, SizeOf(TContext), 0);
        Ctx.ContextFlags := CONTEXT_CONTROL;
        if not GetThreadContext(Handle, Ctx^) then
          Exit;
        {$IFDEF CPUX64}
        if Ctx.Rsp mod 16 = 0 then
        begin
          // Inside a function body: push the interrupted address, as a call would
          Dec(Ctx.Rsp, SizeOf(UInt64));
          PUInt64(Ctx.Rsp)^ := Ctx.Rip;
          Ctx.Rip := UInt64(@RaiseInterruptedByTimeout);
          Redirected := True;
        end
        else if IsFramelessCode(Ctx.Rip) then
        begin
          // Leaf function (or syscall stub): [Rsp] is its return address, so
          // raise as if it had already returned; the stack stays aligned
          Ctx.Rip := UInt64(@RaiseInterruptedByTimeout);
          Redirected := True;
        end;
        // Otherwise it is in the middle of a prologue or epilogue: try again
        {$ELSE}
        Dec(Ctx.Esp, SizeOf(Cardinal));
        PCardinal(Ctx.Esp)^ := Ctx.Eip;
        Ctx.Eip := Cardinal(@RaiseInterruptedByTimeout);
        Redirected := True;
        {$ENDIF}
        if Redirected then
          SetThreadContext(Handle, Ctx^);
      finally
        ResumeThread(Handle);
      end;
      if Redirected then
        Exit;
      Sleep(1);
    end;
  finally
    FreeMem(Buffer);
  end;
end;
{$ENDIF}

/// <summary>
///   Runs Body on a worker thread and raises ETestTimeout when it does not end
///   within TimeoutMs. Abandoned is True when the thread could not be stopped.
/// </summary>
procedure RunWithTimeout(const Body: TProc; TimeoutMs: Integer; out Abandoned: Boolean);
var
  Worker: TTestBodyThread;
  Error: TObject;

  function WaitWorker(Milliseconds: Int64): Boolean;
  var
    Watch: TStopwatch;
  begin
    Watch := TStopwatch.StartNew;
    while not Worker.Finished do
    begin
      if Watch.ElapsedMilliseconds >= Milliseconds then
        Exit(False);
      // Keep serving TThread.Synchronize/Queue calls made by the test body
      if TThread.CurrentThread.ThreadID = MainThreadID then
        CheckSynchronize(5)
      else
        Sleep(5);
    end;
    Result := True;
  end;

begin
  Abandoned := False;
  Worker := TTestBodyThread.Create(Body);
  if WaitWorker(TimeoutMs) then
  begin
    Worker.WaitFor;
    Error := Worker.FError;
    Worker.FError := nil;
    Worker.Free;
    if Error <> nil then
      raise Error;
    Exit;
  end;

  {$IFDEF MSWINDOWS}
  InterruptThread(Worker.Handle);
  {$ENDIF}
  if WaitWorker(1000) then
  begin
    Worker.WaitFor;
    Worker.Free;
  end
  else
  begin
    Abandoned := True;
    Worker.FreeOnTerminate := True;
  end;
  raise ETestTimeout.CreateFmt('Test exceeded [Timeout] of %d ms', [TimeoutMs]);
end;

{ TTestSummary }

procedure TTestSummary.Reset;
begin
  TotalTests := 0;
  Passed := 0;
  Failed := 0;
  Skipped := 0;
  Errors := 0;
  TotalDuration := TTimeSpan.Zero;
end;

{ TTestFilter }

function TTestFilter.Matches(const AUnitName, AClassName, AFixtureName, ATestName: string;
  const ACategories: TArray<string>; AIsExplicit: Boolean;
  const ASelectedTests: TArray<string>): Boolean;
var
  Cat, FilterCat, FullName, FullNameAlt, Selected, CleanSelected: string;
  CategoryMatch: Boolean;
  ParenIdx: Integer;
begin
  // If we have selected tests, only run those
  if Length(ASelectedTests) > 0 then
  begin
    // ExternalUI and IDEs usually send: Unit.Class.Method OR Class.Method
    FullName := AUnitName + '.' + AClassName + '.' + ATestName;
    FullNameAlt := AClassName + '.' + ATestName;

    for Selected in ASelectedTests do
    begin
      CleanSelected := Selected;
      ParenIdx := CleanSelected.IndexOf('(');
      if ParenIdx > 0 then
        CleanSelected := CleanSelected.Substring(0, ParenIdx);

      if SameText(FullName, CleanSelected) or 
         SameText(FullNameAlt, CleanSelected) or
         SameText(AClassName, CleanSelected) or
         SameText(AUnitName + '.' + AClassName, CleanSelected) or
         (CleanSelected.EndsWith('.' + ATestName, True) and CleanSelected.Contains(AClassName)) then
      begin
        Exit(True);
      end;
    end;
    Exit(False);
  end;
  // Explicit tests only run when explicitly requested
  if AIsExplicit and not IncludeExplicit then
    Exit(False);

  // Check fixture name pattern
  if (FixtureNamePattern <> '') and
     not ContainsText(AFixtureName, FixtureNamePattern) then
    Exit(False);

  // Check test name pattern
  if (TestNamePattern <> '') and
     not ContainsText(ATestName, TestNamePattern) then
    Exit(False);

  // Check categories
  if Length(Categories) > 0 then
  begin
    CategoryMatch := False;
    for FilterCat in Categories do
    begin
      for Cat in ACategories do
      begin
        if SameText(Cat, FilterCat) then
        begin
          CategoryMatch := True;
          Break;
        end;
      end;
      if CategoryMatch then
        Break;
    end;
    if not CategoryMatch then
      Exit(False);
  end;

  Result := True;
end;

{ TTestContext }

constructor TTestContext.Create(const AFixture, ATest: string);
begin
  inherited Create;
  FCurrentFixture := AFixture;
  FCurrentTest := ATest;
  FOutput := TStringBuilder.Create;
  FAttachedFiles := TCollections.CreateList<string>;
end;

destructor TTestContext.Destroy;
begin
  FOutput.Free;
  inherited;
end;

function TTestContext.GetCurrentTest: string;
begin
  Result := FCurrentTest;
end;

function TTestContext.GetCurrentFixture: string;
begin
  Result := FCurrentFixture;
end;

procedure TTestContext.WriteLine(const Msg: string);
begin
  FOutput.AppendLine(Msg);
  // Also write to console in verbose mode
  SafeWriteLn('      📝 ' + Msg);
end;

procedure TTestContext.WriteLine(const Fmt: string; const Args: array of const);
begin
  WriteLine(Format(Fmt, Args));
end;

procedure TTestContext.AttachFile(const FilePath: string);
begin
  FAttachedFiles.Add(FilePath);
  SafeWriteLn('      📎 Attached: ' + FilePath);
end;

function TTestContext.GetOutput: string;
begin
  Result := FOutput.ToString;
end;

function TTestContext.GetAttachedFiles: TArray<string>;
begin
  Result := FAttachedFiles.ToArray;
end;

{ TTestFixtureInfo }

constructor TTestFixtureInfo.Create(ARttiType: TRttiType);
var
  Attr: TCustomAttribute;
begin
  inherited Create;
  FRttiType := ARttiType;
  FFixtureClass := ARttiType.AsInstance.MetaclassType;
  FName := ARttiType.Name;
  FTestMethods := TCollections.CreateList<TRttiMethod>;

  // Get description from attribute
  for Attr in ARttiType.GetAttributes do
  begin
    if Attr is TestFixtureAttribute then
    begin
      FDescription := TestFixtureAttribute(Attr).Description;
      Break;
    end;
  end;
end;

destructor TTestFixtureInfo.Destroy;
begin
  inherited;
end;

{ TTestRunner }

class procedure TTestRunner.Discover;
begin
  if FFixtures = nil then
    FFixtures := TCollections.CreateObjectList<TTestFixtureInfo>(True);

  FFixtures.Clear;
  FSummary.Reset;

  DiscoverFixtures;
end;

class procedure TTestRunner.DiscoverFixtures;
var
  RttiType: TRttiType;
  Attr: TCustomAttribute;
  Fixture: TTestFixtureInfo;
begin
  for RttiType in TReflection.Context.GetTypes do
  begin
    if not (RttiType is TRttiInstanceType) then
      Continue;

    for Attr in RttiType.GetAttributes do
    begin
      if (Attr is TestFixtureAttribute) then
      begin
        Fixture := TTestFixtureInfo.Create(RttiType);
        DiscoverTestMethods(Fixture);
        if Fixture.TestMethods.Count > 0 then
          FFixtures.Add(Fixture)
        else
          Fixture.Free;
        Break;
      end;
    end;
  end;
end;

class procedure TTestRunner.DiscoverTestMethods(Fixture: TTestFixtureInfo);
var
  Method: TRttiMethod;
  Attr: TCustomAttribute;
  I, J: Integer;
  TempMethod: TRttiMethod;
  Methods: TArray<TRttiMethod>;
  AttrName: string;
begin
  Methods := Fixture.RttiType.GetMethods;

  for Method in Methods do
  begin
    for Attr in Method.GetAttributes do
    begin
      AttrName := Attr.ClassName;

      // Test methods
      if (Attr is TestAttribute) or (AttrName = 'TestAttribute') then
      begin
        Fixture.TestMethods.Add(Method);
        Break;
      end
      // Setup
      else if (Attr is SetupAttribute) or (AttrName = 'SetupAttribute') then
        Fixture.FSetupMethod := Method
      // TearDown
      else if (Attr is TearDownAttribute) or (AttrName = 'TearDownAttribute') then
        Fixture.FTearDownMethod := Method
      // BeforeAll
      else if (Attr is BeforeAllAttribute) or (AttrName = 'BeforeAllAttribute') then
        Fixture.FBeforeAllMethod := Method
      // AfterAll
      else if (Attr is AfterAllAttribute) or (AttrName = 'AfterAllAttribute') then
        Fixture.FAfterAllMethod := Method;
    end;
  end;

  // Sort tests by priority (simple bubble sort)
  for I := 0 to Fixture.TestMethods.Count - 2 do
  begin
    for J := I + 1 to Fixture.TestMethods.Count - 1 do
    begin
      if GetPriority(Fixture.TestMethods[J]) < GetPriority(Fixture.TestMethods[I]) then
      begin
        TempMethod := Fixture.TestMethods[I];
        Fixture.TestMethods[I] := Fixture.TestMethods[J];
        Fixture.TestMethods[J] := TempMethod;
      end;
    end;
  end;
end;

class procedure TTestRunner.DiscoverAssemblyHooks;
var
  Fixture: TTestFixtureInfo;
  Method: TRttiMethod;
  Attr: TCustomAttribute;
begin
  FAssemblyInitMethod := nil;
  FAssemblyCleanupMethod := nil;
  FAssemblyHookClass := nil;

  // Scan all fixtures for assembly-level hooks
  for Fixture in FFixtures do
  begin
    for Method in Fixture.RttiType.GetMethods do
    begin
      for Attr in Method.GetAttributes do
      begin
        if Attr is AssemblyInitializeAttribute then
        begin
          if FAssemblyInitMethod <> nil then
            raise Exception.Create('[AssemblyInitialize] can only be applied to ONE method across all fixtures.');
          FAssemblyInitMethod := Method;
          FAssemblyHookClass := Fixture.FixtureClass;
        end
        else if Attr is AssemblyCleanupAttribute then
        begin
          if FAssemblyCleanupMethod <> nil then
            raise Exception.Create('[AssemblyCleanup] can only be applied to ONE method across all fixtures.');
          FAssemblyCleanupMethod := Method;
          if FAssemblyHookClass = nil then
            FAssemblyHookClass := Fixture.FixtureClass;
        end;
      end;
    end;
  end;
end;

class procedure TTestRunner.ExecuteAssemblyInit;
var
  Instance: TObject;
begin
  if FAssemblyInitMethod = nil then
    Exit;

  if FVerbosity > ovSilent then
  begin
    SafeWriteLn;
    TTestConsole.WriteInfo('🌐 [AssemblyInitialize] Running global setup...');
  end;

  try
    // Create instance and invoke (or invoke as class method if static)
    if FAssemblyInitMethod.IsClassMethod then
    begin
      FAssemblyInitMethod.Invoke(FAssemblyHookClass, []);
    end
    else
    begin
      Instance := FAssemblyHookClass.Create;
      try
        FAssemblyInitMethod.Invoke(Instance, []);
      finally
        Instance.Free;
      end;
    end;

    if FVerbosity > ovSilent then
      SafeWriteLn('    ✅ Global setup complete.');
  except
    on E: Exception do
    begin
      TTestConsole.WriteFail('    ❌ [AssemblyInitialize] failed: ' + E.Message);
      raise; // Stop test execution if global setup fails
    end;
  end;
end;

class procedure TTestRunner.ExecuteAssemblyCleanup;
var
  Instance: TObject;
begin
  if FAssemblyCleanupMethod = nil then
    Exit;

  if FVerbosity > ovSilent then
  begin
    SafeWriteLn;
    TTestConsole.WriteInfo('🌐 [AssemblyCleanup] Running global cleanup...');
  end;

  try
    if FAssemblyCleanupMethod.IsClassMethod then
    begin
      FAssemblyCleanupMethod.Invoke(FAssemblyHookClass, []);
    end
    else
    begin
      Instance := FAssemblyHookClass.Create;
      try
        FAssemblyCleanupMethod.Invoke(Instance, []);
      finally
        Instance.Free;
      end;
    end;

    if FVerbosity > ovSilent then
      SafeWriteLn('    ✅ Global cleanup complete.');
  except
    on E: Exception do
      TTestConsole.WriteFail('    ⚠️ [AssemblyCleanup] failed: ' + E.Message);
      // Don't re-raise - we want test results to be reported even if cleanup fails
  end;
end;

class function TTestRunner.HasAttribute<T>(
  const Attrs: TArray<TCustomAttribute>): Boolean;
var
  Attr: TCustomAttribute;
begin
  for Attr in Attrs do
    if Attr is T then
      Exit(True);
  Result := False;
end;

class function TTestRunner.GetAttribute<T>(
  const Attrs: TArray<TCustomAttribute>): T;
var
  Attr: TCustomAttribute;
begin
  for Attr in Attrs do
    if Attr is T then
      Exit(T(Attr));
  Result := nil;
end;

class function TTestRunner.GetAttributes<T>(
  const Attrs: TArray<TCustomAttribute>): TArray<T>;
var
  Attr: TCustomAttribute;
  List: IList<T>;
begin
  List := TCollections.CreateList<T>;
  try
    for Attr in Attrs do
      if Attr is T then
        List.Add(T(Attr));
    Result := List.ToArray;
  finally
    // List is ARC
  end;
end;

class function TTestRunner.GetCategories(Method: TRttiMethod; FixtureClass: TClass): TArray<string>;
var
  Categories: IList<string>;

  procedure AddFrom(const Attrs: TArray<TCustomAttribute>);
  var
    Attr: TCustomAttribute;
    Name: string;
  begin
    for Attr in Attrs do
    begin
      if Attr is CategoryAttribute then
        Name := CategoryAttribute(Attr).Name
      else if Attr is TraitAttribute then
        Name := TraitAttribute(Attr).Name + '=' + TraitAttribute(Attr).Value
      else
        Continue;
      if not Categories.Contains(Name) then
        Categories.Add(Name);
    end;
  end;

var
  RttiType: TRttiType;
begin
  Categories := TCollections.CreateList<string>;
  AddFrom(Method.GetAttributes);

  // [Category] and [Trait] on the fixture class (and its ancestors) apply to every test in it
  if FixtureClass <> nil then
  begin
    RttiType := TReflection.Context.GetType(FixtureClass);
    while (RttiType <> nil) and (RttiType.Handle <> TypeInfo(TObject)) do
    begin
      AddFrom(RttiType.GetAttributes);
      RttiType := RttiType.BaseType;
    end;
  end;

  Result := Categories.ToArray;
end;

class function TTestRunner.IsExplicit(Method: TRttiMethod): Boolean;
begin
  Result := HasAttribute<ExplicitAttribute>(Method.GetAttributes);
end;

class function TTestRunner.GetIgnoreReason(Method: TRttiMethod): string;
var
  IgnoreAttr: IgnoreAttribute;
begin
  IgnoreAttr := GetAttribute<IgnoreAttribute>(Method.GetAttributes);
  if Assigned(IgnoreAttr) then
    Result := IgnoreAttr.Reason
  else
    Result := '';
end;

class function TTestRunner.GetTimeout(Method: TRttiMethod): Integer;
var
  TimeoutAttr: TimeoutAttribute;
begin
  TimeoutAttr := GetAttribute<TimeoutAttribute>(Method.GetAttributes);
  if Assigned(TimeoutAttr) then
    Result := TimeoutAttr.Milliseconds
  else
    Result := 0; // No timeout
end;

class function TTestRunner.GetRepeatCount(Method: TRttiMethod): Integer;
var
  RepeatAttr: RepeatAttribute;
begin
  RepeatAttr := GetAttribute<RepeatAttribute>(Method.GetAttributes);
  if Assigned(RepeatAttr) then
    Result := RepeatAttr.Count
  else
    Result := 1;
end;

class function TTestRunner.GetMaxTime(Method: TRttiMethod): Integer;
var
  MaxTimeAttr: MaxTimeAttribute;
begin
  MaxTimeAttr := GetAttribute<MaxTimeAttribute>(Method.GetAttributes);
  if Assigned(MaxTimeAttr) then
    Result := MaxTimeAttr.Milliseconds
  else
    Result := 0;
end;

class function TTestRunner.GetPriority(Method: TRttiMethod): Integer;
var
  PriorityAttr: PriorityAttribute;
begin
  PriorityAttr := GetAttribute<PriorityAttribute>(Method.GetAttributes);
  if Assigned(PriorityAttr) then
    Result := PriorityAttr.Priority
  else
    Result := 999; // Default low priority
end;

class function TTestRunner.ShouldRunOnPlatform(Method: TRttiMethod): Boolean;
var
  PlatformAttr: PlatformAttribute;
begin
  PlatformAttr := GetAttribute<PlatformAttribute>(Method.GetAttributes);
  if Assigned(PlatformAttr) then
    Result := PlatformAttr.ShouldRun
  else
    Result := True; // No platform restriction
end;

class function TTestRunner.GetTestCases(Method: TRttiMethod): TArray<TArray<TValue>>;
var
  TestCaseAttrs: TArray<TestCaseAttribute>;
  SourceAttrs: TArray<TestCaseSourceAttribute>;
  Attr: TestCaseAttribute;
  SourceAttr: TestCaseSourceAttribute;
  List: IList<TArray<TValue>>;
  SourceType: TRttiType;
  SourceMethod: TRttiMethod;
  SourceResult: TValue;
  SourceValues: TArray<TArray<TValue>>;
  V: TArray<TValue>;
begin
  TestCaseAttrs := GetAttributes<TestCaseAttribute>(Method.GetAttributes);
  SourceAttrs := GetAttributes<TestCaseSourceAttribute>(Method.GetAttributes);

  if (Length(TestCaseAttrs) = 0) and (Length(SourceAttrs) = 0) then
  begin
    // No test cases, return single empty array for parameterless execution
    SetLength(Result, 1);
    SetLength(Result[0], 0);
    Exit;
  end;

  List := TCollections.CreateList<TArray<TValue>>;
  try
    // 1. [TestCase]
    for Attr in TestCaseAttrs do
      List.Add(Attr.Values);

    // 2. [TestCaseSource]
    for SourceAttr in SourceAttrs do
    begin
      if SourceAttr.SourceType <> nil then
        SourceType := TReflection.Context.GetType(SourceAttr.SourceType)
      else
        SourceType := Method.Parent;

      if SourceType = nil then Continue;

      SourceMethod := SourceType.GetMethod(SourceAttr.SourceMethodName);
      if Assigned(SourceMethod) and SourceMethod.IsClassMethod then
      begin
        // Invoke static method
        if SourceType is TRttiInstanceType then
          SourceResult := SourceMethod.Invoke(TRttiInstanceType(SourceType).MetaclassType, [])
        else
          Continue;

        if SourceResult.TryAsType<TArray<TArray<TValue>>>(SourceValues) then
        begin
          for V in SourceValues do
            List.Add(V);
        end;
      end;
    end;

    Result := List.ToArray;
  finally
    // List is ARC
  end;
end;

class function TTestRunner.GetTestCaseDisplayNames(Method: TRttiMethod): TArray<string>;
var
  TestCaseAttrs: TArray<TestCaseAttribute>;
  SourceAttrs: TArray<TestCaseSourceAttribute>;
  Attr: TestCaseAttribute;
  SourceAttr: TestCaseSourceAttribute;
  List: IList<string>;
  I: Integer;
  Values: string;
  V: TValue;
  SourceType: TRttiType;
  SourceMethod: TRttiMethod;
  SourceResult: TValue;
  SourceValues: TArray<TArray<TValue>>;
  CaseVals: TArray<TValue>;
begin
  TestCaseAttrs := GetAttributes<TestCaseAttribute>(Method.GetAttributes);
  SourceAttrs := GetAttributes<TestCaseSourceAttribute>(Method.GetAttributes);

  if (Length(TestCaseAttrs) = 0) and (Length(SourceAttrs) = 0) then
  begin
    SetLength(Result, 1);
    Result[0] := '';
    Exit;
  end;

  List := TCollections.CreateList<string>;
  try
    // 1. [TestCase] - Legacy handling
    for I := 0 to High(TestCaseAttrs) do
    begin
      Attr := TestCaseAttrs[I];
      if Attr.DisplayName <> '' then
        List.Add(Attr.DisplayName)
      else
      begin
        // Generate display name from values
        Values := '';
        for V in Attr.Values do
        begin
          if Values <> '' then
            Values := Values + ', ';
          Values := Values + V.ToString;
        end;
        List.Add('(' + Values + ')');
      end;
    end;

    // 2. [TestCaseSource] - Generate names from values
    for SourceAttr in SourceAttrs do
    begin
      if SourceAttr.SourceType <> nil then
        SourceType := TReflection.Context.GetType(SourceAttr.SourceType)
      else
        SourceType := Method.Parent;

      if SourceType = nil then Continue;

      SourceMethod := SourceType.GetMethod(SourceAttr.SourceMethodName);
      if Assigned(SourceMethod) and SourceMethod.IsClassMethod then
      begin
        if SourceType is TRttiInstanceType then
          SourceResult := SourceMethod.Invoke(TRttiInstanceType(SourceType).MetaclassType, [])
        else
          Continue;

        if SourceResult.TryAsType<TArray<TArray<TValue>>>(SourceValues) then
        begin
          for CaseVals in SourceValues do
          begin
            Values := '';
            for V in CaseVals do
            begin
              if Values <> '' then
                Values := Values + ', ';
              Values := Values + V.ToString;
            end;
            List.Add('(' + Values + ')');
          end;
        end;
      end;
    end;

    Result := List.ToArray;
  finally
    // List is ARC
  end;
end;

class procedure TTestRunner.RunAll;
var
  Fixture: TTestFixtureInfo;
  Stopwatch: TStopwatch;
  ActiveCount: Integer;
begin
{$IFDEF CONSOLE}
  // Enable UTF-8 for Unicode symbols in console
  SetConsoleCharSet(CP_UTF8);
{$ENDIF}

  if FFixtures = nil then
    Discover;

  // Discover assembly-level hooks
  DiscoverAssemblyHooks;

  FSummary.Reset;
  FFilter := Default(TTestFilter);
  FFilter.IncludeExplicit := False;

  ActiveCount := GetActiveTestCount;
  NotifyRunStart(ActiveCount);
  TTestConsole.WriteHeader('DEXT TEST RUNNER');
  TTestConsole.WriteInfo(Format('Discovered %d fixtures with %d tests (Running %d)', [FixtureCount, TestCount, ActiveCount]));
  SafeWriteLn;

  // Execute global setup (if defined)
  ExecuteAssemblyInit;

  Stopwatch := TStopwatch.StartNew;
  try
    for Fixture in FFixtures do
      ExecuteFixture(Fixture);
  finally
    // Execute global cleanup (if defined) - always runs
    ExecuteAssemblyCleanup;
  end;

  Stopwatch.Stop;
  FSummary.TotalDuration := Stopwatch.Elapsed;

  PrintSummary;

  // Log.Info('Run Completed: %d Tests, %d Passed, %d Failed, %d Skipped. Duration: %.3fs',
  //  [FSummary.TotalTests, FSummary.Passed, FSummary.Failed, FSummary.Skipped, FSummary.TotalDuration.TotalSeconds]);

  NotifyRunComplete(FSummary);
end;

class procedure TTestRunner.RunFiltered(const AFilter: TTestFilter);
var
  Fixture: TTestFixtureInfo;
  Stopwatch: TStopwatch;
  ActiveCount: Integer;
begin
  if FFixtures = nil then
    Discover;

  // Discover assembly-level hooks
  DiscoverAssemblyHooks;

  FSummary.Reset;
  FFilter := AFilter;

  ActiveCount := GetActiveTestCount;
  DiagnosticLog(Format('[Runner.RunFiltered] ActiveCount=%d, SelectedTests=%d', 
    [ActiveCount, Length(FSelectedTests)]));

  NotifyRunStart(ActiveCount);
  
  { Unselected tests are not pre-reported to keep the IDE tree clean and sessions fast. }

  DiagnosticLog('[Runner.RunFiltered] Execution Started');
  if FVerbosity > ovSilent then
  begin
    TTestConsole.WriteHeader('Dext Test Runner (Filtered)');
    SafeWriteLn;
  end;

  // Execute global setup (if defined)
  ExecuteAssemblyInit;

  Stopwatch := TStopwatch.StartNew;
  try
    for Fixture in FFixtures do
      ExecuteFixture(Fixture);
  finally
    // Execute global cleanup (if defined) - always runs
    ExecuteAssemblyCleanup;
  end;

  Stopwatch.Stop;
  FSummary.TotalDuration := Stopwatch.Elapsed;

  PrintSummary;
  NotifyRunComplete(FSummary);
end;

class procedure TTestRunner.RunCategory(const Category: string);
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  SetLength(Filter.Categories, 1);
  Filter.Categories[0] := Category;
  RunFiltered(Filter);
end;

class procedure TTestRunner.RunFixture(AFixtureClass: TClass);
var
  Fixture: TTestFixtureInfo;
  Stopwatch: TStopwatch;
begin
  if FFixtures = nil then
    Discover;

  FSummary.Reset;
  Stopwatch := TStopwatch.StartNew;

  for Fixture in FFixtures do
  begin
    if Fixture.FixtureClass = AFixtureClass then
    begin
      ExecuteFixture(Fixture);
      Break;
    end;
  end;

  Stopwatch.Stop;
  FSummary.TotalDuration := Stopwatch.Elapsed;

  PrintSummary;
end;

class procedure TTestRunner.RunTest(const ATestNamePattern: string);
var
  Filter: TTestFilter;
begin
  Filter := Default(TTestFilter);
  Filter.TestNamePattern := ATestNamePattern;
  RunFiltered(Filter);
end;

class procedure TTestRunner.ExecuteFixture(Fixture: TTestFixtureInfo);
var
  Instance: TObject;
  Method: TRttiMethod;
  TestCases: TArray<TArray<TValue>>;
  DisplayNames: TArray<string>;
  I: Integer;
  Scope: IDisposable;
begin
  // Start Scope for Fixture
  Scope := Log.Logger.BeginScope('Fixture {Fixture}', [Fixture.Name]);
  try
    NotifyFixtureStart(Fixture.Name, Fixture.TestMethods.Count);
    if Assigned(FOnFixtureStart) then
      FOnFixtureStart(Fixture.Name, Fixture.TestMethods.Count);

    if FVerbosity > ovSilent then
    begin
      SafeWriteLn;
      TTestConsole.WriteInfo('Fixture: ' + Fixture.Name);
      if Fixture.Description <> '' then
        SafeWrite('  ' + Fixture.Description);
      SafeWriteLn;
    end;

    // Handle Discovery Mode: skip instantiation and execution
    if FDiscoveryMode then
    begin
      for Method in Fixture.TestMethods do
      begin
        TestCases := GetTestCases(Method);
        DisplayNames := GetTestCaseDisplayNames(Method);
        for I := 0 to High(TestCases) do
          ExecuteTest(Fixture, Method, nil, TestCases[I], DisplayNames[I]);
      end;
      Exit;
    end;

    // A fixture with no test left by the filter is not created: its
    // [BeforeAll] must not run (nor fail the run)
    if GetActiveTestCount(Fixture) = 0 then
      Exit;

    // Create fixture instance
    GFixtureInstanceAbandoned := False;
    Instance := Fixture.FixtureClass.Create;
    try
      // BeforeAll (class-level setup)
      if Assigned(Fixture.BeforeAllMethod) then
      begin
        try
          InvokeLifecycle(Fixture.BeforeAllMethod, Instance, Fixture.FixtureClass);
        except
          on E: Exception do
          begin
            Log.Error('BeforeAll failed for %s: %s', [Fixture.Name, E.Message]);
            TTestConsole.WriteFail('BeforeAll failed: ' + E.Message);
            ReportFixtureFailure(Fixture, 'BeforeAll', E);
            Exit;
          end;
        end;
      end;

      // Execute each test method
      for Method in Fixture.TestMethods do
      begin
        TestCases := GetTestCases(Method);
        DisplayNames := GetTestCaseDisplayNames(Method);
        for I := 0 to High(TestCases) do
          ExecuteTest(Fixture, Method, Instance, TestCases[I], DisplayNames[I]);
      end;

      // AfterAll (class-level cleanup)
      if Assigned(Fixture.AfterAllMethod) then
      begin
        try
          InvokeLifecycle(Fixture.AfterAllMethod, Instance, Fixture.FixtureClass);
        except
          on E: Exception do
          begin
            Log.Error('AfterAll failed for %s: %s', [Fixture.Name, E.Message]);
            TTestConsole.WriteFail('AfterAll failed: ' + E.Message);
            ReportFixtureFailure(Fixture, 'AfterAll', E);
          end;
        end;
      end;
    finally
      if GFixtureInstanceAbandoned then
        Log.Warn('Fixture %s is not freed: a timed-out test thread still uses it', [Fixture.Name])
      else
        Instance.Free;
    end;

    NotifyFixtureComplete(Fixture.Name);
    if Assigned(FOnFixtureComplete) then
      FOnFixtureComplete(Fixture.Name);

  finally
    Scope.Dispose;
  end;
end;

class procedure TTestRunner.ExecuteTest(Fixture: TTestFixtureInfo;
  Method: TRttiMethod; Instance: TObject;
  const TestCaseValues: TArray<TValue>;
  const TestCaseDisplayName: string);
var
  Info: TTestInfo;
  Stopwatch: TStopwatch;
  IgnoreReason: string;
  RepeatCount, I: Integer;
  Categories: TArray<string>;
  MaxTime: Integer;
  TimeoutMs: Integer;
  Abandoned: Boolean;
  Body: TProc;
  TestContext: ITestContext;
  InvokeArgs: TArray<TValue>;
  Params: TArray<TRttiParameter>;
  P: Integer;
  NeedsContext: Boolean;
  Scope: IDisposable;
begin
  Info.FixtureName := Fixture.Name;
  Info.UnitName := Fixture.FixtureClass.UnitName;
  Info.ClassName := Fixture.FixtureClass.ClassName;
  Info.TestName := Method.Name;
  Info.DisplayName := Method.Name;
  if TestCaseDisplayName <> '' then
    Info.DisplayName := Info.DisplayName + TestCaseDisplayName;
  Info.Categories := GetCategories(Method, Fixture.FixtureClass);
  Info.CodeAddress := Method.CodeAddress;
  Categories := Info.Categories;

  // Logging Instrumentation
  Scope := Log.Logger.BeginScope('Test {Test}', [Info.DisplayName]);
  try
    // Check if test matches filter
    if not FFilter.Matches(Fixture.FixtureClass.UnitName, Fixture.FixtureClass.ClassName, Fixture.Name, Method.Name, Categories, IsExplicit(Method), FSelectedTests) then
    begin
      // Skip reporting for speed. The IDE will count these as 'not run' or 'skipped' based on NotifyRunStart(ActiveCount).
      Exit;
    end;

    FSummary.TotalTests := FSummary.TotalTests + 1;

    // Check ignore
    IgnoreReason := GetIgnoreReason(Method);
    if IgnoreReason <> '' then
    begin
      Info.Result := trSkipped;
      Info.ErrorMessage := IgnoreReason;
      FSummary.Skipped := FSummary.Skipped + 1;
      PrintResultChar(trSkipped);
      PrintTestResult(Info);
      NotifyTestComplete(Info);
      if Assigned(FOnTestComplete) then
        FOnTestComplete(Info);
      Exit;
    end;

    // Handle Discovery Mode
    if FDiscoveryMode then
    begin
      Info.Result := trNone;
      Info.ErrorMessage := 'Discovery Mode';
      FSummary.Skipped := FSummary.Skipped + 1;

      NotifyTestStart(Info.UnitName, Info.ClassName, Info.DisplayName);
      if Assigned(FOnTestStart) then
        FOnTestStart(Info.UnitName, Info.ClassName, Info.DisplayName);

      NotifyTestComplete(Info);
      if Assigned(FOnTestComplete) then
        FOnTestComplete(Info);
      Exit;
    end;

    NotifyTestStart(Info.UnitName, Info.ClassName, Info.DisplayName);
    if Assigned(FOnTestStart) then
      FOnTestStart(Info.UnitName, Info.ClassName, Info.DisplayName);

    // Check platform
    if not ShouldRunOnPlatform(Method) then
    begin
      Info.Result := trSkipped;
      Info.ErrorMessage := 'Platform not supported';
      FSummary.Skipped := FSummary.Skipped + 1;
      PrintResultChar(trSkipped);
      PrintTestResult(Info);
      NotifyTestComplete(Info);
      if Assigned(FOnTestComplete) then
        FOnTestComplete(Info);
      Exit;
    end;

    // Repeat count
    RepeatCount := GetRepeatCount(Method);
    TimeoutMs := GetTimeout(Method);

    for I := 1 to RepeatCount do
    begin
      // Each repetition is reported as a test of its own
      if I > 1 then
        FSummary.TotalTests := FSummary.TotalTests + 1;
      Info.Result := trNone;
      Info.ErrorMessage := '';
      Info.ExceptionName := '';
      Info.StackTrace := '';
      Abandoned := False;

      Stopwatch := TStopwatch.StartNew;
      try
        // Setup
        if Assigned(Fixture.SetupMethod) then
          InvokeLifecycle(Fixture.SetupMethod, Instance, Fixture.FixtureClass);

        try
          // Check if method needs ITestContext injection
          Params := Method.GetParameters;
          NeedsContext := False;
          for P := 0 to High(Params) do
          begin
            if (Params[P].ParamType <> nil) and
               (Params[P].ParamType.TypeKind = tkInterface) and
               (Params[P].ParamType.Name = 'ITestContext') then
            begin
              NeedsContext := True;
              Break;
            end;
          end;

          // Build invoke arguments
          if NeedsContext then
          begin
            TestContext := TTestContext.Create(Fixture.Name, Info.DisplayName);
            SetLength(InvokeArgs, Length(TestCaseValues) + 1);
            InvokeArgs[0] := TValue.From<ITestContext>(TestContext);
            for P := 0 to High(TestCaseValues) do
              InvokeArgs[P + 1] := TestCaseValues[P];
          end
          else
            InvokeArgs := TestCaseValues;

          if TimeoutMs > 0 then
          begin
            Body := procedure
              begin
                Method.Invoke(Instance, InvokeArgs);
              end;
            RunWithTimeout(Body, TimeoutMs, Abandoned);
          end
          else
            Method.Invoke(Instance, InvokeArgs);

          Info.Result := trPassed;

          // Check MaxTime warning
          MaxTime := GetMaxTime(Method);
          if (MaxTime > 0) and (Stopwatch.ElapsedMilliseconds > MaxTime) then
          begin
            Info.ErrorMessage := Format('Test passed but exceeded MaxTime (%dms > %dms)',
              [Stopwatch.ElapsedMilliseconds, MaxTime]);
            Log.Warn('Test exceeded MaxTime: %s', [Info.ErrorMessage]);
          end;
        finally
          // TearDown must not run while an abandoned test thread still uses the fixture
          if Abandoned then
            GFixtureInstanceAbandoned := True
          else if Assigned(Fixture.TearDownMethod) then
            InvokeLifecycle(Fixture.TearDownMethod, Instance, Fixture.FixtureClass);
        end;

        if Info.Result = trPassed then
          FSummary.Passed := FSummary.Passed + 1;
      except
        on E: ETestTimeout do
        begin
          Info.Result := trTimeout;
          Info.ExceptionName := E.ClassName;
          Info.ErrorMessage := E.Message;
          if Abandoned then
            Info.ErrorMessage := Info.ErrorMessage +
              '. The test thread is blocked and keeps running; [TearDown] was skipped and the fixture instance is not freed.';
          FSummary.Failed := FSummary.Failed + 1;
        end;
        on E: Exception do
        begin
          Info.Result := trFailed;
          Info.ExceptionName := E.ClassName;
          Info.ErrorMessage := E.Message;
          Info.StackTrace := FilterStackTrace(TDextStackTrace.GetProvider.GetStackTrace(E));
          FSummary.Failed := FSummary.Failed + 1;
        end;
      end;

      Stopwatch.Stop;
      Info.Duration := Stopwatch.Elapsed;

      PrintResultChar(Info.Result);
      PrintTestResult(Info);

      // Store result for report generation
      if FTestResults = nil then
        FTestResults := TCollections.CreateList<TTestInfo>;
      FTestResults.Add(Info);

      NotifyTestComplete(Info);
      if Assigned(FOnTestComplete) then
        FOnTestComplete(Info);
    end;
  finally
    Scope.Dispose;
  end;
end;

class procedure TTestRunner.PrintResultChar(Result: TTestResult);
begin
  if FVerbosity > ovSilent then
    Exit;

  case Result of
    trPassed:  TTestConsole.WritePass(ICON_PASS);
    trFailed:  TTestConsole.WriteFail(ICON_FAIL);
    trSkipped: TTestConsole.WriteSkip(ICON_WARN);
    trTimeout: TTestConsole.WriteFail(ICON_TIMER);
    trError:   TTestConsole.WriteFail(ICON_STOP);
  end;
end;

class procedure TTestRunner.PrintTestResult(const Info: TTestInfo);
begin
  if FVerbosity <= ovSilent then
    Exit;

  case Info.Result of
    trPassed:
      begin
        TTestConsole.WritePass('  ' + ICON_PASS + '  ');
        SafeWriteLn(Format('%s (%dms)', [Info.DisplayName, Round(Info.Duration.TotalMilliseconds)]));
        if Info.ErrorMessage <> '' then
        begin
          TTestConsole.WriteSkip('      ' + ICON_WARN + '   Warning: ' + Info.ErrorMessage);
          SafeWriteLn;
        end;
      end;
    trFailed:
      begin
        TTestConsole.WriteFail('  ' + ICON_FAIL + '  ');
        SafeWriteLn(Info.DisplayName);
        SafeWrite('      ');
        if Info.ExceptionName <> '' then
          TTestConsole.WriteFail(Info.ExceptionName + ': ');
        TTestConsole.WriteFail(Info.ErrorMessage);
        SafeWriteLn;

        if (FVerbosity = ovVerbose) and (Info.StackTrace <> '') then
        begin
          TTestConsole.WriteInfo('      Stack Trace:');
          SafeWriteLn;
          SafeWriteLn(Info.StackTrace);
          SafeWriteLn;
        end;
      end;
    trSkipped:
      begin
        TTestConsole.WriteSkip('  ' + ICON_WARN + '   ');
        SafeWrite(Info.DisplayName);
        if Info.ErrorMessage <> '' then
          SafeWrite('  [' + Info.ErrorMessage + ']');
        SafeWriteLn;
      end;
    trTimeout:
      begin
        TTestConsole.WriteFail('  ' + ICON_TIMER + '   ');
        SafeWriteLn(Info.DisplayName + ' (TIMEOUT)');
      end;
    trError:
      begin
        TTestConsole.WriteFail('  ' + ICON_STOP + '  ');
        SafeWriteLn(Info.DisplayName);
        SafeWrite('      ');
        if Info.ExceptionName <> '' then
          TTestConsole.WriteFail(Info.ExceptionName + ': ');
        TTestConsole.WriteFail(Info.ErrorMessage);
        SafeWriteLn;

        if (FVerbosity = ovVerbose) and (Info.StackTrace <> '') then
        begin
          TTestConsole.WriteInfo('      Stack Trace:');
          SafeWriteLn;
          SafeWriteLn(Info.StackTrace);
          SafeWriteLn;
        end;
      end;
  end;
end;

class procedure TTestRunner.PrintSummary;
var
  PassPercent: Double;
begin
  SafeWriteLn;
  SafeWriteLn;
  TTestConsole.WriteHeader('Test Summary');
  SafeWriteLn;

  // Calculate pass percentage
  if FSummary.TotalTests > 0 then
    PassPercent := (FSummary.Passed / FSummary.TotalTests) * 100
  else
    PassPercent := 100;

  SafeWrite(Format('  ' + ICON_CHART + '  Total:     %d', [FSummary.TotalTests])); SafeWriteLn;
  SafeWrite('  ' + ICON_PASS + '  Passed:    '); TTestConsole.WritePass(IntToStr(FSummary.Passed)); SafeWriteLn;
  SafeWrite('  ' + ICON_FAIL + '  Failed:    '); TTestConsole.WriteFail(IntToStr(FSummary.Failed)); SafeWriteLn;
  SafeWrite('  ' + ICON_WARN + '   Skipped:   '); TTestConsole.WriteSkip(IntToStr(FSummary.Skipped)); SafeWriteLn;
  SafeWriteLn;

  if FSummary.TotalDuration.TotalSeconds < 1 then
    SafeWriteLn(Format('  ' + ICON_TIMER + '   Duration:  %dms', [Round(FSummary.TotalDuration.TotalMilliseconds)]))
  else
    SafeWriteLn(Format('  ' + ICON_TIMER + '   Duration:  %.3fs', [FSummary.TotalDuration.TotalSeconds]));

  SafeWrite('  ' + ICON_PASS_RT + '  Pass Rate: ');
  if PassPercent = 100 then
    TTestConsole.WritePass(Format('%.1f%%', [PassPercent]))
  else if PassPercent >= 80 then
    TTestConsole.WriteSkip(Format('%.1f%%', [PassPercent]))
  else
    TTestConsole.WriteFail(Format('%.1f%%', [PassPercent]));
  SafeWriteLn;
  SafeWriteLn;

  if (FSummary.TotalTests = 0) and not FAllowEmptyRun then
  begin
    SafeWrite('  ' + ICON_CRASH + '  ');
    TTestConsole.WriteFail('No tests were run. Check that [Test] methods are public and that the filters match.');
  end
  else if FSummary.Failed = 0 then
    TTestConsole.WritePass('  ' + ICON_CELEBRATE + '  All tests passed!')
  else
  begin
    SafeWrite('  ' + ICON_CRASH + '  ');
    TTestConsole.WriteFail(Format('%d test(s) failed!', [FSummary.Failed]));
  end;
  SafeWriteLn;
end;

class function TTestRunner.GetActiveTestCount: Integer;
var
  Fixture: TTestFixtureInfo;
begin
  Result := 0;
  if FFixtures = nil then Exit;

  for Fixture in FFixtures do
    Inc(Result, GetActiveTestCount(Fixture));
end;

class function TTestRunner.GetActiveTestCount(Fixture: TTestFixtureInfo): Integer;
var
  Method: TRttiMethod;
begin
  Result := 0;
  for Method in Fixture.TestMethods do
  begin
    if FFilter.Matches(Fixture.FixtureClass.UnitName, Fixture.FixtureClass.ClassName, 
       Fixture.Name, Method.Name, GetCategories(Method, Fixture.FixtureClass), IsExplicit(Method), FSelectedTests) then
      Inc(Result);
  end;
end;

class procedure TTestRunner.ReportFixtureFailure(Fixture: TTestFixtureInfo; const Stage: string; E: Exception);
var
  Info: TTestInfo;
begin
  Info := Default(TTestInfo);
  Info.FixtureName := Fixture.Name;
  Info.UnitName := Fixture.FixtureClass.UnitName;
  Info.ClassName := Fixture.FixtureClass.ClassName;
  Info.TestName := Stage;
  Info.DisplayName := Stage;
  Info.Result := trError;
  Info.ExceptionName := E.ClassName;
  Info.ErrorMessage := Stage + ' failed: ' + E.Message;
  FSummary.TotalTests := FSummary.TotalTests + 1;
  FSummary.Failed := FSummary.Failed + 1;
  if FTestResults = nil then
    FTestResults := TCollections.CreateList<TTestInfo>;
  FTestResults.Add(Info);
end;

class function TTestRunner.Summary: TTestSummary;
begin
  Result := FSummary;
end;

class function TTestRunner.Succeeded: Boolean;
begin
  Result := (FSummary.Failed = 0) and ((FSummary.TotalTests > 0) or FAllowEmptyRun);
end;

class procedure TTestRunner.SetAllowEmptyRun(AValue: Boolean);
begin
  FAllowEmptyRun := AValue;
end;

class procedure TTestRunner.SetVerbosity(AValue: TOutputVerbosity);
begin
  FVerbosity := AValue;
end;

class procedure TTestRunner.SetOutputFormat(AFormat: TOutputFormat);
begin
  FOutputFormat := AFormat;
end;

class function TTestRunner.FixtureCount: Integer;
begin
  if FFixtures = nil then
    Result := 0
  else
    Result := FFixtures.Count;
end;

class function TTestRunner.TestCount: Integer;
var
  Fixture: TTestFixtureInfo;
begin
  Result := 0;
  if FFixtures = nil then
    Exit;
  for Fixture in FFixtures do
    Inc(Result, Fixture.TestMethods.Count);
end;

class procedure TTestRunner.Clear;
begin
  if FFixtures <> nil then
  begin
    FFixtures := nil;
  end;

  // Free test results list
  if FTestResults <> nil then
  begin
    FTestResults := nil;
  end;

  FListeners := nil;
  FDiscoveryMode := False;
  FSelectedTests := nil;
end;

class procedure TTestRunner.RegisterFixture(AClass: TClass);
var
  RttiType: TRttiType;
  Fixture: TTestFixtureInfo;
begin
  if FFixtures = nil then
    FFixtures := TCollections.CreateObjectList<TTestFixtureInfo>(True);

  // Check if already registered
  for Fixture in FFixtures do
    if Fixture.FixtureClass = AClass then
      Exit;

  RttiType := TReflection.Context.GetType(AClass);

  if RttiType = nil then
  begin
    Exit;
  end;

  Fixture := TTestFixtureInfo.Create(RttiType);
  DiscoverTestMethods(Fixture);

  if Fixture.TestMethods.Count > 0 then
  begin
    FFixtures.Add(Fixture);
  end
  else
  begin
    Fixture.Free;
  end;
end;

class procedure TTestRunner.RegisterFixture(const AClasses: array of TClass);
var
  FixtureClass: TClass;
begin
  for FixtureClass in AClasses do
    RegisterFixture(FixtureClass);
end;

class procedure TTestRunner.SetDebugDiscovery(AValue: Boolean);
begin
  FDebugDiscovery := AValue;
end;

class procedure TTestRunner.SetReportFile(const FileName: string; Format: TOutputFormat);
begin
  FReportFileName := FileName;
  FReportFormat := Format;
end;

class procedure TTestRunner.SaveJUnitReport(const FileName: string);
var
  Reporter: TJUnitReporter;
  Fixture: TTestFixtureInfo;
  TestInfo: TTestInfo;
begin
  if FTestResults = nil then
  begin
    SafeWriteLn('Warning: No test results available. Run tests first.');
    Exit;
  end;

  Reporter := TJUnitReporter.Create;
  try
    // Group results by fixture
    for Fixture in FFixtures do
    begin
      Reporter.BeginSuite(Fixture.Name);
      for TestInfo in FTestResults do
      begin
        if TestInfo.FixtureName = Fixture.Name then
          Reporter.AddTestCase(TestInfo);
      end;
      Reporter.EndSuite;
    end;

    Reporter.SaveToFile(FileName);

    if FVerbosity > ovSilent then
      SafeWriteLn('📄 JUnit report saved: ' + FileName);
  finally
    Reporter.Free;
  end;
end;

class procedure TTestRunner.SaveJsonReport(const FileName: string);
var
  Reporter: TJsonReporter;
  Fixture: TTestFixtureInfo;
  TestInfo: TTestInfo;
begin
  if FTestResults = nil then
  begin
    SafeWriteLn('Warning: No test results available. Run tests first.');
    Exit;
  end;

  Reporter := TJsonReporter.Create;
  try
    // Group results by fixture
    for Fixture in FFixtures do
    begin
      Reporter.BeginSuite(Fixture.Name);
      for TestInfo in FTestResults do
      begin
        if TestInfo.FixtureName = Fixture.Name then
          Reporter.AddTestCase(TestInfo);
      end;
      Reporter.EndSuite;
    end;

    Reporter.SaveToFile(FileName);

    if FVerbosity > ovSilent then
      SafeWriteLn('📄 JSON report saved: ' + FileName);
  finally
    Reporter.Free;
  end;
end;

class procedure TTestRunner.SaveXUnitReport(const FileName: string);
var
  Reporter: TXUnitReporter;
  Fixture: TTestFixtureInfo;
  TestInfo: TTestInfo;
begin
  if FTestResults = nil then
  begin
    SafeWriteLn('Warning: No test results available. Run tests first.');
    Exit;
  end;

  Reporter := TXUnitReporter.Create;
  try
    for Fixture in FFixtures do
    begin
      Reporter.BeginSuite(Fixture.Name);
      for TestInfo in FTestResults do
      begin
        if TestInfo.FixtureName = Fixture.Name then
          Reporter.AddTestCase(TestInfo);
      end;
      Reporter.EndSuite;
    end;

    Reporter.SaveToFile(FileName);

    if FVerbosity > ovSilent then
      SafeWriteLn('📄 xUnit report saved: ' + FileName);
  finally
    Reporter.Free;
  end;
end;

class procedure TTestRunner.SaveTRXReport(const FileName: string);
var
  Reporter: TTRXReporter;
  Fixture: TTestFixtureInfo;
  TestInfo: TTestInfo;
begin
  if FTestResults = nil then
  begin
    SafeWriteLn('Warning: No test results available. Run tests first.');
    Exit;
  end;

  Reporter := TTRXReporter.Create;
  try
    Reporter.BeginRun('Dext Test Run');

    for Fixture in FFixtures do
    begin
      Reporter.BeginSuite(Fixture.Name);
      for TestInfo in FTestResults do
      begin
        if TestInfo.FixtureName = Fixture.Name then
          Reporter.AddTestCase(TestInfo);
      end;
      Reporter.EndSuite;
    end;

    Reporter.SaveToFile(FileName);

    if FVerbosity > ovSilent then
      SafeWriteLn('📄 TRX report saved: ' + FileName);
  finally
    Reporter.Free;
  end;
end;

class procedure TTestRunner.SaveSonarQubeReport(const FileName: string);
var
  Reporter: TSonarQubeReporter;
  Fixture: TTestFixtureInfo;
  TestInfo: TTestInfo;
begin
  if FTestResults = nil then
  begin
    SafeWriteLn('Warning: No test results available. Run tests first.');
    Exit;
  end;

  Reporter := TSonarQubeReporter.Create;
  try
    for Fixture in FFixtures do
    begin
      Reporter.SetCurrentClassName(Fixture.Name);
      for TestInfo in FTestResults do
      begin
        if TestInfo.FixtureName = Fixture.Name then
          Reporter.AddTestCase(TestInfo);
      end;
    end;

    Reporter.SaveToFile(FileName);

    if FVerbosity > ovSilent then
      SafeWriteLn('📄 SonarQube report saved: ' + FileName);
  finally
    Reporter.Free;
  end;
end;

class procedure TTestRunner.SaveHTMLReport(const FileName: string);
var
  Reporter: THTMLReporter;
  Fixture: TTestFixtureInfo;
  TestInfo: TTestInfo;
begin
  if FTestResults = nil then
  begin
    SafeWriteLn('Warning: No test results available. Run tests first.');
    Exit;
  end;

  Reporter := THTMLReporter.Create;
  try
    Reporter.SetTitle('Dext Test Report');

    for Fixture in FFixtures do
    begin
      Reporter.BeginSuite(Fixture.Name);
      for TestInfo in FTestResults do
      begin
        if TestInfo.FixtureName = Fixture.Name then
          Reporter.AddTestCase(TestInfo);
      end;
      Reporter.EndSuite;
    end;

    Reporter.SaveToFile(FileName);

    if FVerbosity > ovSilent then
      SafeWriteLn('📄  HTML report saved: ' + FileName);
  finally
    Reporter.Free;
  end;
end;

{ TTestConsole }

class procedure TTestConsole.WriteColored(const Text: string; Color: Word);
{$IFDEF MSWINDOWS}
var
  Handle: THandle;
  Info: TConsoleScreenBufferInfo;
begin
  if IsConsoleAvailable then
  begin
    Handle := GetStdHandle(STD_OUTPUT_HANDLE);
    if GetConsoleScreenBufferInfo(Handle, Info) then
    begin
      SetConsoleTextAttribute(Handle, Color);
      SafeWrite(Text);
      SetConsoleTextAttribute(Handle, Info.wAttributes);
      Exit;
    end;
  end;
  SafeWrite(Text);
end;
{$ELSE}
begin
  SafeWrite(Text);
end;
{$ENDIF}

class procedure TTestConsole.WritePass(const Text: string);
begin
  WriteColored(Text, CONSOLE_COLOR_GREEN);
end;

class procedure TTestConsole.WriteFail(const Text: string);
begin
  WriteColored(Text, CONSOLE_COLOR_RED);
end;

class procedure TTestConsole.WriteSkip(const Text: string);
begin
  WriteColored(Text, CONSOLE_COLOR_YELLOW);
end;

class procedure TTestConsole.WriteInfo(const Text: string);
begin
  WriteColored(Text, CONSOLE_COLOR_CYAN);
end;

class procedure TTestConsole.WriteHeader(const Text: string);
begin
  SafeWriteLn;
  WriteColored('-----------------------------------------------------------', CONSOLE_COLOR_CYAN);
  SafeWriteLn;
  WriteColored('  ' + Text, CONSOLE_COLOR_WHITE);
  SafeWriteLn;
  WriteColored('-----------------------------------------------------------', CONSOLE_COLOR_CYAN);
  SafeWriteLn;
end;

class procedure TTestRunner.ClearListeners;
begin
  if FListeners <> nil then
  begin
    FListeners := nil;
  end;
end;

class procedure TTestRunner.RegisterListener(const Listener: ITestListener);
begin
  if FListeners = nil then
    FListeners := TCollections.CreateList<ITestListener>;
  FListeners.Add(Listener);
end;

class procedure TTestRunner.NotifyRunStart(TotalTests: Integer);
var
  Listener: ITestListener;
begin
  if FListeners <> nil then
    for Listener in FListeners do Listener.OnRunStart(TotalTests);
end;

class procedure TTestRunner.NotifyRunComplete(const Summary: TTestSummary);
var
  Listener: ITestListener;
begin
  if FListeners <> nil then
    for Listener in FListeners do Listener.OnRunComplete(Summary);
end;

class procedure TTestRunner.NotifyFixtureStart(const FixtureName: string; TestCount: Integer);
var
  Listener: ITestListener;
begin
  if FListeners <> nil then
    for Listener in FListeners do Listener.OnFixtureStart(FixtureName, TestCount);
end;

class procedure TTestRunner.NotifyFixtureComplete(const FixtureName: string);
var
  Listener: ITestListener;
begin
  if FListeners <> nil then
    for Listener in FListeners do Listener.OnFixtureComplete(FixtureName);
end;

class procedure TTestRunner.NotifyTestStart(const UnitName, Fixture, Test: string);
var
  Listener: ITestListener;
begin
  if FListeners <> nil then
    for Listener in FListeners do Listener.OnTestStart(UnitName, Fixture, Test);
end;

class procedure TTestRunner.NotifyTestComplete(const Info: TTestInfo);
var
  Listener: ITestListener;
begin
  if Assigned(FOnTestComplete) then FOnTestComplete(Info);
  if FListeners <> nil then
    for Listener in FListeners do
      Listener.OnTestComplete(Info);
end;

class procedure TTestRunner.SetDiscoveryMode(Value: Boolean);
begin
  FDiscoveryMode := Value;
end;

class procedure TTestRunner.SetSelectedTests(const Tests: TArray<string>);
begin
  FSelectedTests := Tests;
end;

class function TTestRunner.IsDiscoveryMode: Boolean;
begin
  Result := FDiscoveryMode;
end;

class function TTestRunner.GetSelectedTests: TArray<string>;
begin
  Result := FSelectedTests;
end;

class function TTestRunner.GetAllTestPaths: TArray<string>;
var
  Fixture: TTestFixtureInfo;
  Method: TRttiMethod;
  Count: Integer;
begin
  Result := [];
  if FFixtures = nil then Exit;

  Count := 0;
  for Fixture in FFixtures do
    Inc(Count, Fixture.TestMethods.Count);

  SetLength(Result, Count);
  Count := 0;

  for Fixture in FFixtures do
  begin
    for Method in Fixture.TestMethods do
    begin
      // Full path: Unit.Class.Method
      Result[Count] := Fixture.FixtureClass.UnitName + '.' +
                       Fixture.FixtureClass.ClassName + '.' +
                       Method.Name;
      Inc(Count);
    end;
  end;
end;

class function TTestRunner.IsExternalUIActive: Boolean;
begin
  Result := FIsExternalUIActive;
end;

class procedure TTestRunner.SetExternalUIActive(Value: Boolean);
begin
  FIsExternalUIActive := Value;
end;

initialization
  TTestRunner.FVerbosity := ovDefault;

finalization
  // Only call Clear if we haven't already manually cleaned up
  // to prevent AVs if reference-counted objects are already gone.
  try
    TTestRunner.Clear;
  except
    // Silent fail in finalization to prevent Runtime Error 217
  end;

end.
