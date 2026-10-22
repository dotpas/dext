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

unit Dext.Testing.Design.DockableForm;

{ Always write %TEMP%\DextExpert.log while diagnosing C++ Run All / Host. }
{$DEFINE DEXT_TEST_EXPLORER_LOG_FILE_ENABLED}

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Buttons, Vcl.Clipbrd, DockForm, ToolsAPI, Dext.Testing.Design.Server, Dext.Testing.Design.AST,
  System.JSON, System.Generics.Collections, System.IOUtils, System.Threading,
  System.ImageList, Vcl.ImgList, Vcl.Menus, System.Math, System.Diagnostics, System.TimeSpan,
  System.DateUtils, System.RegularExpressions;

type
  TFormDextTestRunner = class;

  TTestDetailInfo = record
    TestName: string;
    Status: string;
    FileName: string;
    Line: Integer;
    DurationMs: Double;
    ErrorMessage: string;
    StackTrace: string;
  end;

  TGroupSummaryInfo = record
    TotalCount: Integer;
    PassedCount: Integer;
    FailedCount: Integer;
    DurationMs: Double;
  end;

  TTestTreeNodeInfo = class
  public
    FullTestName: string;
    TestIndex: Integer;
    Status: string;
    DurationMs: Double;
    IsGroup: Boolean;
    GroupTestCount: Integer;
    GroupPassedCount: Integer;
    GroupFailedCount: Integer;
    GroupDurationMs: Double;
    constructor Create;
  end;

  TDextProjectInfo = class
  public
    FileName: string;
    constructor Create(const AFileName: string);
  end;

  TDextProjectNotifier = class(TNotifierObject, IOTAModuleNotifier, IOTAProjectNotifier)
  private
    FForm: TFormDextTestRunner;
    FProjectFile: string;
  public
    constructor Create(AForm: TFormDextTestRunner; const AProjectFile: string);
    // IOTAModuleNotifier
    function CheckOverwrite: Boolean;
    procedure ModuleRenamed(const NewName: string); overload;
    // IOTAProjectNotifier
    procedure ModuleAdded(const AFileName: string);
    procedure ModuleRemoved(const AFileName: string);
    procedure ModuleRenamed(const AOldFileName, ANewFileName: string); overload;
  end;

  TTestSession = class
  private
    FOwnsTabSheet: Boolean;
    FOwnsTestLocations: Boolean;
  public
    TabSheet: TTabSheet;
    TreeView: TTreeView;
    TestLocations: TList<TTestLocation>;
    ActiveProjectFile: string;
    FilterEdit: TEdit;
    ClearFilterButton: TSpeedButton;
    constructor Create(APageControl: TPageControl; const AName: string); overload;
    constructor CreateFromExisting(ATabSheet: TTabSheet; ATreeView: TTreeView; ALocations: TList<TTestLocation>; const AProjFile: string); overload;
    destructor Destroy; override;
  end;

  TFileScanCache = class
  public
    Timestamp: TDateTime;
    Tests: TList<TTestLocation>;
    constructor Create(ATimestamp: TDateTime; ATests: TList<TTestLocation>);
    destructor Destroy; override;
  end;

  TPendingTestResult = record
    ProjectFile: string;
    TestName: string;
    Status: string;
    DurationMs: Integer;
  end;

  TTelemetryTracker = class
  private
    class var FPendingResults: TList<TPendingTestResult>;
    class procedure EnsurePending;
    class procedure FlushPendingResults;
  public
    class procedure RecordTestResult(const AProjectFile, ATestName, AStatus: string; ADurationMs: Integer);
    class procedure AnalyzeHistory(const AProjectFile: string; ALines: TStrings);
    /// <summary>S75 F-10: persist suite-total run history (passed/failed/skipped/duration).</summary>
    class procedure RecordSuiteRun(const AProjectFile: string; APassed, AFailed, ASkipped, ATotal: Integer; ADurationMs: Double);
    class procedure AnalyzeSuiteHistory(const AProjectFile: string; ALines: TStrings);
  end;

  TTestExplorerLayout = (telCompact, telSplitBottom, telSplitRight);
  TTestGroupingMode = (tgmCodeStructure, tgmStatus);
  /// <summary>Console Kind column. dckAuto only for live runner messages; analytics must pass explicit kind.</summary>
  TDextConsoleKind = (dckAuto, dckLog, dckPass, dckFail, dckSkip, dckWarn);

  TFormDextTestRunner = class(TDockableForm)
    ActionsButton: TButton;
    ActionsPopupMenu: TPopupMenu;
    ButtonsPanel: TPanel;
    ClearMenuItem: TMenuItem;
    ClearSeparator: TMenuItem;
    ConfigScroll: TScrollBox;
    ConfigTab: TTabSheet;
    ConsoleTab: TTabSheet;
    CreateaNewSessionMenuItem: TMenuItem;
    CustomParamsEdit: TEdit;
    CustomParamsLabel: TLabel;
    DefaultSessionTabSheet: TTabSheet;
    DetailsMemo: TRichEdit;
    DetailsPageControl: TPageControl;
    DetailsPanel: TPanel;
    DurationLabel: TLabel;
    EnabledCheckBox: TCheckBox;
    EnableDisableTestExplorerMenuItem: TMenuItem;
    ErrorHeaderLabel: TLabel;
    ErrorMemo: TMemo;
    ExportSeparator: TMenuItem;
    ExportToHtmlReportMenuItem: TMenuItem;
    ExportToJsonMenutem: TMenuItem;
    ExportToJUnitXmlMenutem: TMenuItem;
    ExportToSonarQubeXmlMenutem: TMenuItem;
    ExportToXUnitXMLMenutem: TMenuItem;
    GroupByClassMenuItem: TMenuItem;
    GroupByTestStatusMenuItem: TMenuItem;
    InfoPanel: TPanel;
    InspectorScroll: TScrollBox;
    InspectorTab: TTabSheet;
    LayoutSeparator: TMenuItem;
    LocationLabel: TLabel;
    NameSplitter: TSplitter;
    ProgressBar: TProgressBar;
    ProgressLabel: TLabel;
    ProgressPanel: TPanel;
    ProjectsComboBox: TComboBox;
    RefreshButton: TButton;
    RunAllButton: TButton;
    RunOnIdleCheckBox: TCheckBox;
    RunOnSaveCheckBox: TCheckBox;
    RunSelectedButton: TButton;
    SessionsPageControl: TPageControl;
    SplitBottomLayoutMenuItem: TMenuItem;
    SplitRightLayoutMenuItem: TMenuItem;
    StatusLabel: TLabel;
    StopButton: TButton;
    SummaryFailedLabel: TLabel;
    SummaryPanel: TPanel;
    SummarySelectedLabel: TLabel;
    SummarySkippedLabel: TLabel;
    SummarySuccessLabel: TLabel;
    SummaryTimeLabel: TLabel;
    SummaryTotalLabel: TLabel;
    SummaryTotalTimeLabel: TLabel;
    TabbedLayoutMenuItem: TMenuItem;
    TestNameLabel: TLabel;
    TestsTreeView: TTreeView;
    procedure ActionsButtonClick(Sender: TObject);
    procedure ProjectsComboBoxChange(Sender: TObject);
    procedure RunAllButtonClick(Sender: TObject);
    procedure RunSelectedButtonClick(Sender: TObject);
    procedure StopButtonClick(Sender: TObject);
    procedure TestsTreeViewDblClick(Sender: TObject);
    procedure RefreshButtonClick(Sender: TObject);
    procedure ExpandAllMenuItemClick(Sender: TObject);
    procedure CollapseAllMenuItemClick(Sender: TObject);
  private
    FServer: TTestRunnerServer;
    FTestLocations: TList<TTestLocation>;
    FFormOwnedTestLocations: TList<TTestLocation>;
    FActiveProjectFile: string;
    FScanGeneration: Integer;
    FHoverNode: TTreeNode;
    FCoverageCheckBox: TCheckBox;
    FGenerateHtmlCheckBox: TCheckBox;
    FCollectCoverageMenuItem: TMenuItem;
    FGenerateHtmlMenuItem: TMenuItem;
    FInstallCoverageMenuItem: TMenuItem;
    FReloadCoverageMenuItem: TMenuItem;
    FOpenCoverageHtmlMenuItem: TMenuItem;
    FOpenCoverageHtmlContextMenuItem: TMenuItem;
    FClearCoverageArtifactsMenuItem: TMenuItem;
    FLastCoverageReportDir: string;
    FLastCoverageSourceRoot: string;
    FCoverageWrapActive: Boolean;
    /// <summary>C++ Run All with coverage: read llvm-cov after the process exits.</summary>
    FCppLlvmCoverage: Boolean;
    /// <summary>True while a C++ --discover Host launch is in flight (Refresh).</summary>
    FDiscoverMode: Boolean;
    FDiscoverAfterCompile: Boolean;

    // Process handling
    FRunningProcessHandle: THandle;

    // Project changes notification
    FActiveProjectNotifierIndex: Integer;
    FActiveProjectForNotifier: IOTAProject;

    // Sessions
    FSessions: TObjectList<TTestSession>;
    FActiveSession: TTestSession;
    FGroupNodes: TDictionary<string, TTreeNode>;

    // Test Inspector components
    FTestDetails: TDictionary<string, TTestDetailInfo>;
    FGroupSummaries: TDictionary<string, TGroupSummaryInfo>;
    // Progress tracking
    FTotalTests: Integer;
    FCompletedTests: Integer;
    FInspectorSplitter: TSplitter;
    FCurrentLayout: TTestExplorerLayout;
    //LayoutButton: TButton;
    // Async compile state
    FPendingTestFilter: string;
    FWaitingForCompile: Boolean;
    FPendingProject: IOTAProject;
    FThemeNotifierIndex: Integer;
    FGroupingMode: TTestGroupingMode;
    FRunningTests: Boolean;

    // Disabled/Enabled Mode
    FEnabled: Boolean;
    FDisabledPanel: TPanel;
    FDisabledContainer: TPanel;

    // Configurations/Startup Tab
    FIdleTimer: TTimer;
    FSaveTimer: TTimer;
    FCoveragePlatformTimer: TTimer;
    FLastCoveragePlatformKey: string;
    FPendingSaveFiles: TStringList;
    { Ignore spurious edit-view AfterSave while the IDE opens modules (Run on Save). }
    FIgnoreSaveUntil: TDateTime;
    { Desktop restore can flash the form undocked for about a second.
      Refresh stays pending until the window is actually on screen: docked, left floating
      on purpose, or opened from the menu. }
    FRefreshWhenShown: Boolean;
    FUserOpenedExplorer: Boolean;
    FSurfaceSettled: Boolean;
    FSurfaceSettleTimer: TTimer;

    // Execution Stopwatch & Counts
    FStopwatch: TStopwatch;
    FTestExecutionDurationMs: Double;
    FPassedCount: Integer;
    FFailedCount: Integer;
    FSkippedCount: Integer;

    // File scan AST cache (thread-safe performance optimization)
    FScanCache: TObjectDictionary<string, TFileScanCache>;

    // UI responsiveness during suite run: coalesce + time-slice painting
    FPendingResultJson: TStringList;
    FUiFlushScheduled: Boolean;
    FNodeByName: TDictionary<string, TTreeNode>;
    FBatchingUi: Boolean;

    // E1.7: structured console log (replaces color-coded RichEdit dump)
    FConsoleListView: TListView;
    FCoverageTab: TTabSheet;
    FCoverageListView: TListView;
    FCoverageSummaryLabel: TLabel;
    // E2.3: clickable stack frames under the Test Inspector
    FStackPanel: TPanel;
    FStackFramesListView: TListView;
    FStackFrameNavs: TObjectList<TObject>;
    FStackHintLabel: TLabel;

    function ActiveFilterEdit: TEdit;
    function CompileCppProject(const AProjFile: string): Boolean;
    function CompileProjectDirect(const AProjFile: string): Boolean;
    function FindMethodImplementationLine(const AFileName, AClassName, AMethodName: string; ADefaultLine: Integer): Integer;
    function FindNodeByPath(const APath: string): TTreeNode;
    function GetCheckedTests: TArray<string>;
    function GetNodeFullTestName(ANode: TTreeNode): string;
    function GetRunButtonRect(ANode: TTreeNode): TRect;

    procedure AddSessionButtonClick(Sender: TObject);
    procedure ApplyIDETheme;
    procedure ApplyLayout(ALayout: TTestExplorerLayout);
    procedure ClearLogsClick(Sender: TObject);
    procedure ClearTestStatus;
    procedure ConsoleListViewDblClick(Sender: TObject);
    procedure StackFramesListViewDblClick(Sender: TObject);
    procedure StackFramesListViewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure OpenStackFrame(const AMethodName, AFileName: string; ALine: Integer);
    procedure LayoutInspectorDetails(AHasErrorMemo: Boolean; AFrameCount: Integer);
    function ResolveStackFrameFile(const AMethodName, AFileName: string): string;
    function FindUnitFileByName(const AUnitFileName: string): string;
    function IsUnreliableMapLocation(const AFileName: string): Boolean;
    function UnitHintFromMethodName(const AMethodName: string): string;
    procedure ClearStackFrameNavs;
    procedure LogAnalyticsLines(ALines: TStrings);
    procedure ReloadCoverageClick(Sender: TObject);
    procedure EnsureCoverageToolClick(Sender: TObject);
    procedure CollectCoverageMenuClick(Sender: TObject);
    procedure UpdateCoverageUiState;
    procedure ApplyCoverageForActivePlatform;
    function IsCodeCoverageToolAvailable(out AToolPath: string): Boolean;
    procedure SetupListViewClipboard(AListView: TListView);
    procedure ListViewCopySelectedClick(Sender: TObject);
    procedure ListViewCopyAllClick(Sender: TObject);
    procedure ListViewClipboardKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function FormatListViewRow(AItem: TListItem): string;
    function CopyListViewLines(AListView: TListView; ASelectedOnly: Boolean): string;
    procedure CloseActiveSessionClick(Sender: TObject);
    procedure CloseSession(ASession: TTestSession);
    procedure CollapseSuccessAndFocusFailures;
    procedure ConfigChangeHandler(Sender: TObject);
    procedure CreateNewSession(const AName: string);
    procedure DebugSelectedClick(Sender: TObject);
    procedure EnableBtnClick(Sender: TObject);
    procedure ExpandTestsTreeView;
    procedure ExportMenuClick(Sender: TObject);
    procedure ExportResults(const ExportFormat, FileName: string);
    procedure ApplyDebugTraceOptionsClick(Sender: TObject);
    function ApplyDebugTraceOptionsToProject(const AProject: IOTAProject; out AConfigName: string): Boolean;
    procedure FilterEditChange(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure GroupingMenuClick(Sender: TObject);
    procedure IdleTimerTimer(Sender: TObject);
    procedure CoveragePlatformTimerTimer(Sender: TObject);
    procedure InitializeGroupSummaries;
    procedure InvalidateGroupNode(const ATestName: string);
    procedure LaunchTestExe(const ATestFilter: string);
    procedure LaunchDiscoverExe;
    /// <summary>Host --discover when exe exists; else AST-only. Never auto-builds.</summary>
    procedure DiscoverCppProjectTests;
    procedure PopulateCppTestsFromAstOnly;
    procedure EnrichCppLocationsFromSources;
    function ResolveActiveProjectExe(out AExeFile: string): Boolean;
    function IsLikelyBinaryTestName(const AName: string): Boolean;
    procedure LayoutMenuClick(Sender: TObject);
    procedure LogMsg(const AMsg: string; AKind: TDextConsoleKind = dckAuto);
    procedure LogPerformance(const AMessage: string);
    procedure NotifyProcessExited;
    procedure OnTestResultReceived(const AJSONData: string);
    procedure ScheduleUiResultFlush;
    procedure FlushPendingResultsUi;
    procedure ProcessResultPayload(const AJSONData: string);
    procedure BuildNodeIndex;
    procedure ClearNodeIndex;
    procedure SyncProgressAndSummaryLabels;
    function NormalizeStackTraceText(const ARaw: string): string;
    function ExtractStackTraceFromErrorJson(ErrorObj: TJSONObject): string;
    procedure RebuildStatusImages;
    procedure RefreshTreeView;
    procedure RunAllProjectsClick(Sender: TObject);
    procedure RunAllProjectsTests;
    procedure RunFailedTestsClick(Sender: TObject);
    procedure SaveTimerTimer(Sender: TObject);
    procedure SessionsPageControlChange(Sender: TObject);
    procedure SessionTabContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure SetActiveSession(ASession: TTestSession);
    procedure SetEnabledState(AValue: Boolean);
    procedure TestsTreeViewAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
    procedure TestsTreeViewChange(Sender: TObject; Node: TTreeNode);
    procedure TestsTreeViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure TestsTreeViewMouseLeave(Sender: TObject);
    procedure TestsTreeViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure TestsTreeViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ToggleEnabledClick(Sender: TObject);
    procedure TryLoadCoverage(AReportExpected: Boolean = False);
    procedure RefreshCoverageReportTab;
    /// <summary>Explicit Coverage-tab failure (tab mark + amber summary); clears stale list/gutter.</summary>
    procedure SetCoverageProblem(const AMessage: string);
    procedure ClearCoverageProblemStyle;
    procedure EnsureCoverageListColumns;
    function FormatCoveragePercentBar(APercent: Double): string;
    function FindCoverageHtmlReport: string;
    function CoverageArtifactsPresent: Boolean;
    procedure OpenCoverageHtmlClick(Sender: TObject);
    procedure ClearCoverageArtifactsClick(Sender: TObject);
    procedure GenerateHtmlMenuClick(Sender: TObject);
    procedure CoverageListViewDblClick(Sender: TObject);
    procedure OpenSourceFileAtLine(const AFileName: string; ALine: Integer);
    procedure UpdateGroupSummary(const ATestName, AStatus: string; ADurationMs: Double);
    procedure UpdateNodeResultCache(const ATestName, AStatus: string; ADurationMs: Double);
    procedure UpdateSummaryCounts;
    procedure UpdateTabVisibility;
    procedure UpdateTestInspector(const ATestName: string);
    procedure UpdateTestNode(const ATestName, AStatus, AMessage, AStackTrace: string);
    function EnsureRuntimeTestNode(const ATestName: string): TTreeNode;
    procedure UpdateTimingLabels;
    procedure UpdateTotalTimeLabel;
    procedure ApplyDpiScaling;
    function ScalePx(ADesignPx: Integer): Integer;
    procedure ClearFilterButtonClick(Sender: TObject);
    /// <summary>Drop AutoSave/desktop debris named _1, _2, … before recreating runtime UI.</summary>
    procedure FreeDesktopNameCollisions;
    function IsDfmNonVisual(AComponent: TComponent): Boolean;

    // Process handling
    function GetProjectByFileName(const AFileName: string): IOTAProject;
    procedure RefreshActiveProjectTestsList;
    procedure ResetSummaryLabels;
  protected
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
    procedure DoShow; override;
    procedure DoHide; override;
    procedure DoDock(NewDockSite: TWinControl; var ARect: TRect); override;
    procedure Resize; override;
    function ExplorerSurfaceReady: Boolean;
    procedure LogExplorerSurface(const AWhere: string);
    procedure FlushRefreshWhenShown;
    procedure ArmSurfaceSettle;
    procedure CancelSurfaceSettle;
    procedure SurfaceSettleTimerFired(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure GetChildren(Proc: TGetChildProc; Root: TComponent); override;
    procedure HandleFileSaved(const AFileName: string);
    procedure RunActiveProjectTests(const TestFilter: string = ''; AutoSave: Boolean = True);
    procedure RunImpactedTests(const ATests: TArray<string>);
    // Called by the IDE AfterCompile notifier
    procedure NotifyCompileComplete(ASucceeded: Boolean);
    procedure RefreshProjects;
  end;

procedure ShowDextTestExplorer;
procedure RegisterDockableForm;
procedure UnregisterDockableForm;
procedure LogToFile(const AMsg: string);

var
  FormDextTestRunner: TFormDextTestRunner = nil;

implementation

{$R *.dfm}

{.$DEFINE DEXT_TEST_EXPLORER_PERF_LOG}

uses
  DeskUtil, Dext.Utils, System.Actions, Vcl.ActnList, Dext.Testing.Design.Coverage,
  Dext.Testing.Design.Coverage.Runner, Dext.Testing.Design.ProjectKinds,
  Dext.Testing.Design.ExpertTrace, Dext.Testing.CodeCoverage.Tool, System.IniFiles,
  Winapi.CommCtrl, Dext.Testing.Report, Dext.Testing.Runner, Dext.Testing.Integration,
  Dext.Testing.StackTrace;

type
  /// <summary>Navigation payload stored in stack-frame ListItem.Data.</summary>
  TStackFrameNav = class
  public
    FileName: string;
    MethodName: string;
    Line: Integer;
  end;

function IsSafePathLeaf(const ALeaf: string): Boolean; forward;

{ Windows ExtractFileName('Foo.cpp:24') → '24' (colon = drive). Strip :line first. }
procedure SplitSourceFileAndLine(const AHint: string; out AFileLeaf: string; out ALine: Integer);
var
  Match: TMatch;
  S: string;
  Slash: Integer;
begin
  AFileLeaf := '';
  ALine := 0;
  S := Trim(AHint);
  if S = '' then
    Exit;
  Match := TRegEx.Match(S,
    '^(.*\.(?:cpp|h|hpp|pas|cc|cxx|c))(?::(\d+))?$', [roIgnoreCase]);
  if Match.Success then
  begin
    S := Trim(Match.Groups[1].Value);
    if Match.Groups.Count >= 3 then
      ALine := StrToIntDef(Match.Groups[2].Value, 0);
  end;
  Slash := S.LastDelimiter('/\');
  if Slash >= 0 then
    AFileLeaf := S.Substring(Slash + 1)
  else
    AFileLeaf := S;
end;

{ Block Run-on-Save / AfterSave side-effects while we open a source file. }
procedure BeginSourceNavigationQuiet(AForm: TFormDextTestRunner);
begin
  if AForm = nil then
    Exit;
  AForm.FIgnoreSaveUntil := Now + (3 / SecsPerDay);
  if Assigned(AForm.FPendingSaveFiles) then
    AForm.FPendingSaveFiles.Clear;
  if Assigned(AForm.FSaveTimer) then
    AForm.FSaveTimer.Enabled := False;
end;

function SameSourcePath(const A, B: string): Boolean;
var
  EA, EB: string;
begin
  Result := False;
  if (A = '') or (B = '') then
    Exit;
  try
    EA := ExpandFileName(A);
    EB := ExpandFileName(B);
  except
    EA := A;
    EB := B;
  end;
  Result := SameText(EA, EB) or SameText(ExtractFileName(EA), ExtractFileName(EB));
end;

{ Find an edit view for AFile without GetEditView(0) on an empty list. }
function FindEditViewForFile(const AFile: string): IOTAEditView;
var
  EditorServices: IOTAEditorServices;
  Iterator: IOTAEditBufferIterator;
  Buffer: IOTAEditBuffer;
  B, V: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorServices) then
    Exit;
  if EditorServices.TopView <> nil then
  begin
    try
      if SameSourcePath(EditorServices.TopView.Buffer.FileName, AFile) then
        Exit(EditorServices.TopView);
    except
    end;
  end;
  if not EditorServices.GetEditBufferIterator(Iterator) then
    Exit;
  for B := 0 to Iterator.Count - 1 do
  begin
    Buffer := Iterator.EditBuffers[B];
    if Buffer = nil then
      Continue;
    try
      if not SameSourcePath(Buffer.FileName, AFile) then
        Continue;
    except
      Continue;
    end;
    for V := 0 to Buffer.EditViewCount - 1 do
    begin
      Result := Buffer.EditViews[V];
      if Result <> nil then
        Exit;
    end;
  end;
end;

{ C++ MainSource lives on the IOTAProject module as IOTASourceEditor — not a
  separate FindModule. OpenModule(path) creates a ghost module (no edit view)
  that then blocks IDE open / Explorer drag-drop for that file. }
function TryShowSourceEditorOnModule(const AModule: IOTAModule; const AFile: string;
  out AEditView: IOTAEditView): Boolean;
var
  i, v: Integer;
  Editor: IOTAEditor;
  SourceEditor: IOTASourceEditor;
begin
  Result := False;
  AEditView := nil;
  if AModule = nil then
    Exit;
  for i := 0 to AModule.ModuleFileCount - 1 do
  begin
    try
      Editor := AModule.ModuleFileEditors[i];
    except
      Continue;
    end;
    if Editor = nil then
      Continue;
    try
      if not SameSourcePath(Editor.FileName, AFile) then
        Continue;
    except
      Continue;
    end;
    if not Supports(Editor, IOTASourceEditor, SourceEditor) then
      Continue;
    try
      SourceEditor.Show; { creates EditView when count was 0 }
    except
    end;
    for v := 0 to SourceEditor.EditViewCount - 1 do
    begin
      try
        AEditView := SourceEditor.GetEditView(v);
      except
        AEditView := nil;
      end;
      if AEditView <> nil then
        Exit(True);
    end;
  end;
end;

procedure LogProjectEditorDump(const AFile: string);
var
  ModuleServices: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
  ProjMod: IOTAModule;
  Editor: IOTAEditor;
  p, i: Integer;
begin
  if FormDextTestRunner = nil then
    Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Group := ModuleServices.MainProjectGroup;
  if Group = nil then
    Exit;
  FormDextTestRunner.LogMsg('OpenSource: dump editors for target=' + AFile);
  for p := 0 to Group.ProjectCount - 1 do
  begin
    Project := Group.Projects[p];
    if (Project = nil) or not Supports(Project, IOTAModule, ProjMod) then
      Continue;
    FormDextTestRunner.LogMsg(Format('OpenSource: project[%d]=%s ModuleFileCount=%d',
      [p, Project.FileName, ProjMod.ModuleFileCount]));
    for i := 0 to ProjMod.ModuleFileCount - 1 do
    begin
      try
        Editor := ProjMod.ModuleFileEditors[i];
        if Editor <> nil then
          FormDextTestRunner.LogMsg(Format('OpenSource:   editor[%d]=%s same=%s',
            [i, Editor.FileName, BoolToStr(SameSourcePath(Editor.FileName, AFile), True)]));
      except
        on E: Exception do
          FormDextTestRunner.LogMsg(Format('OpenSource:   editor[%d] ERR %s', [i, E.Message]));
      end;
    end;
  end;
end;

function TryShowSourceEditorInProjects(const AFile: string;
  out AEditView: IOTAEditView): Boolean;
var
  ModuleServices: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
  ProjMod: IOTAModule;
  p: Integer;
begin
  Result := False;
  AEditView := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Group := ModuleServices.MainProjectGroup;
  if Group = nil then
    Exit;
  for p := 0 to Group.ProjectCount - 1 do
  begin
    Project := Group.Projects[p];
    if Project = nil then
      Continue;
    if Supports(Project, IOTAModule, ProjMod) then
    begin
      if TryShowSourceEditorOnModule(ProjMod, AFile, AEditView) then
        Exit(True);
    end;
  end;
end;

procedure CloseGhostSourceModule(const AFile: string);
var
  ModuleServices: IOTAModuleServices;
  Ghost: IOTAModule;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  Ghost := ModuleServices.FindModule(AFile);
  if Ghost = nil then
    Exit;
  { Never close the project module itself. }
  if Supports(Ghost, IOTAProject) then
    Exit;
  if FindEditViewForFile(AFile) <> nil then
    Exit;
  try
    Ghost.CloseModule(True);
  except
  end;
end;

function OpenProjectModuleFile(const AFile: string): IOTAModule;
var
  ModuleServices: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Project: IOTAProject;
  Info: IOTAModuleInfo;
  View: IOTAEditView;
  p, m: Integer;
begin
  Result := nil;
  View := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;

  { 1) Show editor attached to the .cbproj / .dproj module (MainSource case). }
  if TryShowSourceEditorInProjects(AFile, View) then
  begin
    Result := ModuleServices.FindModule(AFile);
    if Result = nil then
    begin
      Group := ModuleServices.MainProjectGroup;
      if (Group <> nil) and (Group.ActiveProject <> nil) then
        Supports(Group.ActiveProject, IOTAModule, Result);
    end;
    Exit;
  end;

  { 2) Ghost from a prior OpenModule — drop it so OpenFile/drag-drop can work. }
  CloseGhostSourceModule(AFile);

  Result := ModuleServices.FindModule(AFile);
  if Result <> nil then
  begin
    if TryShowSourceEditorOnModule(Result, AFile, View) then
      Exit;
    try
      Result.Show;
    except
    end;
    if FindEditViewForFile(AFile) <> nil then
      Exit;
    Result := nil;
  end;

  { 3) Non-main project units: OpenModule via IOTAModuleInfo. }
  Group := ModuleServices.MainProjectGroup;
  if Group <> nil then
  begin
    for p := 0 to Group.ProjectCount - 1 do
    begin
      Project := Group.Projects[p];
      if Project = nil then
        Continue;
      for m := 0 to Project.GetModuleCount - 1 do
      begin
        Info := Project.GetModule(m);
        if (Info = nil) or not SameSourcePath(Info.FileName, AFile) then
          Continue;
        try
          Result := Info.OpenModule;
        except
          Result := nil;
        end;
        if Result <> nil then
        begin
          if TryShowSourceEditorOnModule(Result, AFile, View) then
            Exit;
          try
            Result.Show;
          except
          end;
          if FindEditViewForFile(AFile) <> nil then
            Exit;
        end;
      end;
    end;
  end;
  { Do NOT call ModuleServices.OpenModule(AFile) — creates MainSource ghosts. }
end;

function TrySourceEditView(const AModule: IOTAModule; const AFile: string;
  out AEditView: IOTAEditView): Boolean;
begin
  Result := TryShowSourceEditorOnModule(AModule, AFile, AEditView);
  if Result then
    Exit;
  AEditView := FindEditViewForFile(AFile);
  Result := AEditView <> nil;
end;

function CleanStackMethodName(const AMethodName: string): string;
var
  PlusAt, AtPos, ParenPos: Integer;
begin
  { Local helper — Design often resolves a stale Testing DCU under Output\37.0. }
  Result := Trim(AMethodName);
  AtPos := Pos(' @ ', Result);
  if AtPos > 0 then
    Result := Trim(Copy(Result, 1, AtPos - 1));
  PlusAt := Pos(' + $', Result);
  if PlusAt > 0 then
    Result := Trim(Copy(Result, 1, PlusAt - 1));
  ParenPos := Pos('(', Result);
  if ParenPos > 0 then
    Result := Trim(Copy(Result, 1, ParenPos - 1));
end;

{ Local — same stale-DCU reason; keeps Method vs Location columns apart. }
procedure SplitStackMethodAndFile(const ARaw: string; out AMethod, AFileName: string);
var
  S: string;
  AtPos, BracketEnd, DummyLine: Integer;
  FileHint: string;
begin
  AMethod := '';
  AFileName := '';
  S := Trim(ARaw);
  if S = '' then
    Exit;
  if (Length(S) > 0) and (S[1] = '[') then
  begin
    BracketEnd := Pos(']', S);
    if BracketEnd > 0 then
      S := Trim(Copy(S, BracketEnd + 1, MaxInt));
  end;
  AtPos := Pos(' @ ', S);
  if AtPos > 0 then
  begin
    AMethod := CleanStackMethodName(Copy(S, 1, AtPos - 1));
    FileHint := Trim(Copy(S, AtPos + 3, MaxInt));
    SplitSourceFileAndLine(FileHint, AFileName, DummyLine);
  end
  else
  begin
    AMethod := CleanStackMethodName(S);
    AFileName := '';
  end;
end;

{$IFDEF DEXT_TEST_EXPLORER_PERF_LOG}
var
  PerfLogLock: TObject;
{$ENDIF}

{$IF CompilerVersion < 35.0}
type
  TTreeViewHelper = class helper for TTreeView
  private
    function GetCheckboxes: Boolean;
    procedure SetCheckboxes(Value: Boolean);
  public
    property Checkboxes: Boolean read GetCheckboxes write SetCheckboxes;
  end;

  TTreeNodeHelper = class helper for TTreeNode
  private
    function GetChecked: Boolean;
    procedure SetChecked(Value: Boolean);
  public
    property Checked: Boolean read GetChecked write SetChecked;
  end;

function TTreeViewHelper.GetCheckboxes: Boolean;
begin
  Result := (GetWindowLong(Handle, GWL_STYLE) and TVS_CHECKBOXES) <> 0;
end;

procedure TTreeViewHelper.SetCheckboxes(Value: Boolean);
var
  Style: Longint;
begin
  Style := GetWindowLong(Handle, GWL_STYLE);
  if Value then
    Style := Style or TVS_CHECKBOXES
  else
    Style := Style and not TVS_CHECKBOXES;
  SetWindowLong(Handle, GWL_STYLE, Style);
end;

function TTreeNodeHelper.GetChecked: Boolean;
var
  TVItem: TTVItem;
begin
  Result := False;
  if (TreeView <> nil) and (TreeView.HandleAllocated) then
  begin
    TVItem.mask := TVIF_STATE or TVIF_HANDLE;
    TVItem.hItem := ItemId;
    TVItem.stateMask := TVIS_STATEIMAGEMASK;
    if TreeView_GetItem(TreeView.Handle, TVItem) then
      Result := ((TVItem.state and TVIS_STATEIMAGEMASK) shr 12) = 2;
  end;
end;

procedure TTreeNodeHelper.SetChecked(Value: Boolean);
var
  TVItem: TTVItem;
begin
  if (TreeView <> nil) and (TreeView.HandleAllocated) then
  begin
    TVItem.mask := TVIF_STATE or TVIF_HANDLE;
    TVItem.hItem := ItemId;
    TVItem.stateMask := TVIS_STATEIMAGEMASK;
    if Value then
      TVItem.state := 2 shl 12
    else
      TVItem.state := 1 shl 12;
    TreeView_SetItem(TreeView.Handle, TVItem);
  end;
end;
{$ENDIF}

type
  TDextThemeNotifier = class(TNotifierObject, INTAIDEThemingServicesNotifier)
  private
    FForm: TFormDextTestRunner;
  public
    constructor Create(AForm: TFormDextTestRunner);
    // INTAIDEThemingServicesNotifier
    procedure ChangingTheme;
    procedure ChangedTheme;
  end;

constructor TDextThemeNotifier.Create(AForm: TFormDextTestRunner);
begin
  inherited Create;
  FForm := AForm;
end;

procedure TDextThemeNotifier.ChangingTheme;
begin
end;

procedure TDextThemeNotifier.ChangedTheme;
begin
  if IsTestingDesignShuttingDown or not Assigned(FForm) then
    Exit;
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
        FormDextTestRunner.ApplyIDETheme;
    end));
end;

procedure ShowDextTestExplorer;
begin
  if not Assigned(FormDextTestRunner) then
    FormDextTestRunner := TFormDextTestRunner.Create(nil);
  FormDextTestRunner.FUserOpenedExplorer := True;
  FormDextTestRunner.LogExplorerSurface('ShowDextTestExplorer');
  ShowDockableForm(FormDextTestRunner);
end;

procedure RegisterDockableForm;
var
  ThemingServices: IOTAIDEThemingServices;
begin
  if @RegisterFieldAddress <> nil then
    RegisterFieldAddress('FormDextTestRunner', @FormDextTestRunner);
  RegisterDesktopFormClass(TFormDextTestRunner, 'FormDextTestRunner', 'FormDextTestRunner');

  if Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) then
    ThemingServices.RegisterFormClass(TFormDextTestRunner);
end;

procedure UnregisterDockableForm;
var
  Form: TFormDextTestRunner;
begin
  BeginTestingDesignShutdown;
  if @UnRegisterFieldAddress <> nil then
  try
    UnRegisterFieldAddress(@FormDextTestRunner);
  except
  end;
  Form := FormDextTestRunner;
  FormDextTestRunner := nil;
  if Assigned(Form) then
  try
    Form.Free;
  except
  end;
end;

function GetModuleBuildTime: string;
var
  FilePath: array[0..MAX_PATH] of Char;
  FileTime: TFileTime;
  SystemTime: TSystemTime;
  LocalTime: TSystemTime;
  Handle: THandle;
begin
  Result := '';
  if GetModuleFileName(HInstance, FilePath, Length(FilePath)) > 0 then
  begin
    Handle := CreateFile(FilePath, GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
    if Handle <> INVALID_HANDLE_VALUE then
    begin
      try
        if GetFileTime(Handle, nil, nil, @FileTime) then
        begin
          if FileTimeToSystemTime(FileTime, SystemTime) then
          begin
            if SystemTimeToTzSpecificLocalTime(nil, SystemTime, LocalTime) then
            begin
              Result := Format('%.4d-%.2d-%.2d %.2d:%.2d:%.2d',
                [LocalTime.wYear, LocalTime.wMonth, LocalTime.wDay,
                 LocalTime.wHour, LocalTime.wMinute, LocalTime.wSecond]);
            end;
          end;
        end;
      finally
        CloseHandle(Handle);
      end;
    end;
  end;
end;

{ TDextProjectInfo }

constructor TDextProjectInfo.Create(const AFileName: string);
begin
  inherited Create;
  FileName := AFileName;
end;

constructor TTestTreeNodeInfo.Create;
begin
  inherited Create;
  TestIndex := -1;
end;

{ TDextProjectNotifier }

constructor TDextProjectNotifier.Create(AForm: TFormDextTestRunner; const AProjectFile: string);
begin
  inherited Create;
  FForm := AForm;
  FProjectFile := AProjectFile;
end;

function TDextProjectNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

procedure TDextProjectNotifier.ModuleRenamed(const NewName: string);
begin
end;

procedure TDextProjectNotifier.ModuleAdded(const AFileName: string);
begin
  if IsTestingDesignShuttingDown or not Assigned(FForm) then
    Exit;
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
        FormDextTestRunner.RefreshActiveProjectTestsList;
    end));
end;

procedure TDextProjectNotifier.ModuleRemoved(const AFileName: string);
begin
  if IsTestingDesignShuttingDown or not Assigned(FForm) then
    Exit;
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
        FormDextTestRunner.RefreshActiveProjectTestsList;
    end));
end;

procedure TDextProjectNotifier.ModuleRenamed(const AOldFileName, ANewFileName: string);
begin
end;

{ TTestSession }

constructor TTestSession.Create(APageControl: TPageControl; const AName: string);
var
  PPI: Integer;
  FilterPanel: TPanel;
begin
  inherited Create;
  FOwnsTabSheet := True;
  FOwnsTestLocations := True;
  TestLocations := TList<TTestLocation>.Create;

  TabSheet := TTabSheet.Create(APageControl.Owner);
  TabSheet.Name := ''; // avoid "_1 already exists" after desktop layout restore
  TabSheet.PageControl := APageControl;
  TabSheet.Caption := AName;

  PPI := 96;
  if APageControl.Owner is TFormDextTestRunner then
    PPI := TFormDextTestRunner(APageControl.Owner).CurrentPPI;

  FilterPanel := TPanel.Create(TabSheet);
  FilterPanel.Name := '';
  FilterPanel.Parent := TabSheet;
  FilterPanel.Align := alTop;
  FilterPanel.Height := MulDiv(28, PPI, 96);
  FilterPanel.BevelOuter := bvNone;

  ClearFilterButton := TSpeedButton.Create(TabSheet);
  ClearFilterButton.Name := '';
  ClearFilterButton.Parent := FilterPanel;
  ClearFilterButton.Align := alRight;
  ClearFilterButton.Width := MulDiv(22, PPI, 96);
  ClearFilterButton.Caption := 'X';
  ClearFilterButton.Flat := True;
  ClearFilterButton.Hint := 'Clear filter';
  ClearFilterButton.ShowHint := True;
  ClearFilterButton.Visible := False;
  if APageControl.Owner is TFormDextTestRunner then
    ClearFilterButton.OnClick := TFormDextTestRunner(APageControl.Owner).ClearFilterButtonClick;

  FilterEdit := TEdit.Create(TabSheet);
  FilterEdit.Name := '';
  FilterEdit.Parent := FilterPanel;
  FilterEdit.Align := alClient;
  FilterEdit.AlignWithMargins := True;
  FilterEdit.Margins.Left := 0;
  FilterEdit.Margins.Right := 2;
  FilterEdit.Margins.Top := 3;
  FilterEdit.Margins.Bottom := 3;
  FilterEdit.TextHint := 'Filter tests (Ctrl+F)...';
  if APageControl.Owner is TFormDextTestRunner then
    FilterEdit.OnChange := TFormDextTestRunner(APageControl.Owner).FilterEditChange;

  TreeView := TTreeView.Create(TabSheet);
  TreeView.Name := '';
  TreeView.Parent := TabSheet;
  TreeView.Align := alClient;
  TreeView.ReadOnly := True;
  TreeView.HideSelection := False;
  TreeView.Checkboxes := True;
  TreeView.DoubleBuffered := True;
  TreeView.StyleElements := [];
end;

constructor TTestSession.CreateFromExisting(ATabSheet: TTabSheet; ATreeView: TTreeView; ALocations: TList<TTestLocation>; const AProjFile: string);
var
  FilterPanel: TPanel;
  PPI: Integer;
begin
  inherited Create;
  // Form owns the DFM tab / tree / locations list — do not free in session Destroy.
  FOwnsTabSheet := False;
  FOwnsTestLocations := False;
  TabSheet := ATabSheet;
  TreeView := ATreeView;
  TestLocations := ALocations;
  ActiveProjectFile := AProjFile;

  PPI := 96;
  if ATabSheet.Owner is TFormDextTestRunner then
    PPI := TFormDextTestRunner(ATabSheet.Owner).CurrentPPI;

  FilterPanel := TPanel.Create(ATabSheet);
  FilterPanel.Name := '';
  FilterPanel.Parent := ATabSheet;
  FilterPanel.Align := alTop;
  FilterPanel.Height := MulDiv(28, PPI, 96);
  FilterPanel.BevelOuter := bvNone;

  ClearFilterButton := TSpeedButton.Create(ATabSheet);
  ClearFilterButton.Name := '';
  ClearFilterButton.Parent := FilterPanel;
  ClearFilterButton.Align := alRight;
  ClearFilterButton.Width := MulDiv(22, PPI, 96);
  ClearFilterButton.Caption := 'X';
  ClearFilterButton.Flat := True;
  ClearFilterButton.Hint := 'Clear filter';
  ClearFilterButton.ShowHint := True;
  ClearFilterButton.Visible := False;
  if ATabSheet.Owner is TFormDextTestRunner then
    ClearFilterButton.OnClick := TFormDextTestRunner(ATabSheet.Owner).ClearFilterButtonClick;

  FilterEdit := TEdit.Create(ATabSheet);
  FilterEdit.Name := '';
  FilterEdit.Parent := FilterPanel;
  FilterEdit.Align := alClient;
  FilterEdit.AlignWithMargins := True;
  FilterEdit.Margins.Left := 0;
  FilterEdit.Margins.Right := 2;
  FilterEdit.Margins.Top := 3;
  FilterEdit.Margins.Bottom := 3;
  FilterEdit.TextHint := 'Filter tests (Ctrl+F)...';
  if ATabSheet.Owner is TFormDextTestRunner then
    FilterEdit.OnChange := TFormDextTestRunner(ATabSheet.Owner).FilterEditChange;
end;

destructor TTestSession.Destroy;
begin
  if FOwnsTabSheet and Assigned(TabSheet) and not (csDestroying in TabSheet.ComponentState) then
    TabSheet.Free;
  TabSheet := nil;
  TreeView := nil;
  if FOwnsTestLocations then
    FreeAndNil(TestLocations)
  else
    TestLocations := nil;
  inherited;
end;

procedure TFormDextTestRunner.RebuildStatusImages;
var
  BgColor: TColor;
  Bitmap: TBitmap;
  i: Integer;
  ImageList: TImageList;
  OldImages: TCustomImageList;

  procedure DrawSmoothCircle(AColor: TColor; ADest: TBitmap);
  var
    LargeBmp: TBitmap;
  begin
    LargeBmp := TBitmap.Create;
    try
      LargeBmp.SetSize(64, 64);
      LargeBmp.Canvas.Brush.Color := BgColor;
      LargeBmp.Canvas.FillRect(Rect(0, 0, 64, 64));

      LargeBmp.Canvas.Pen.Color := AColor;
      LargeBmp.Canvas.Brush.Color := AColor;
      LargeBmp.Canvas.Ellipse(16, 16, 48, 48);

      ADest.Canvas.Brush.Color := BgColor;
      ADest.Canvas.FillRect(Rect(0, 0, 16, 16));

      SetStretchBltMode(ADest.Canvas.Handle, HALFTONE);
      SetBrushOrgEx(ADest.Canvas.Handle, 0, 0, nil);
      StretchBlt(ADest.Canvas.Handle, 0, 0, 16, 16, LargeBmp.Canvas.Handle, 0, 0, 64, 64, SRCCOPY);
    finally
      LargeBmp.Free;
    end;
  end;

begin
  if TestsTreeView <> nil then
    BgColor := TestsTreeView.Color
  else
    BgColor := clWindow;

  ImageList := TImageList.Create(Self);
  ImageList.Name := '';
  ImageList.Width := 16;
  ImageList.Height := 16;

  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(16, 16);

    // 0: Idle (Gray circle)
    DrawSmoothCircle(clGray, Bitmap);
    ImageList.AddMasked(Bitmap, BgColor);

    // 1: Pass (Green circle)
    DrawSmoothCircle(TColor($5EC522), Bitmap);
    ImageList.AddMasked(Bitmap, BgColor);

    // 2: Fail (Red circle)
    DrawSmoothCircle(TColor($4444EF), Bitmap);
    ImageList.AddMasked(Bitmap, BgColor);

    // 3: Fixture (Blue circle)
    DrawSmoothCircle(TColor($F6823B), Bitmap);
    ImageList.AddMasked(Bitmap, BgColor);
  finally
    Bitmap.Free;
  end;

  OldImages := TestsTreeView.Images;
  TestsTreeView.Images := ImageList;

  if Assigned(FSessions) then
  begin
    for i := 0 to FSessions.Count - 1 do
      if Assigned(FSessions[i].TreeView) then
        FSessions[i].TreeView.Images := ImageList;
  end;

  if Assigned(FConsoleListView) then
    FConsoleListView.SmallImages := ImageList;

  if Assigned(OldImages) then
    OldImages.Free;
end;

{ TFileScanCache }

constructor TFileScanCache.Create(ATimestamp: TDateTime; ATests: TList<TTestLocation>);
begin
  inherited Create;
  Timestamp := ATimestamp;
  Tests := ATests;
end;

destructor TFileScanCache.Destroy;
begin
  Tests.Free;
  inherited Destroy;
end;

{ TFormDextTestRunner }

constructor TFormDextTestRunner.Create(AOwner: TComponent);
var
  DisabledMsgLabel: TLabel;
  EnableButton: TButton;
  GroupingMode: Integer;
  Ini: TMemIniFile;
  IniFile: string;
  LayoutMode: Integer;
  MenuItem: TMenuItem;
  Page: TTabSheet;
  PageIdx: Integer;
  PopupMenu: TPopupMenu;
  RunAllItem1, RunAllItem2, RunAllItem3: TMenuItem;
  RunAllMenu: TPopupMenu;
  ThemingServices: IOTAIDEThemingServices;
begin
  FormDextTestRunner := Self;
  FRunningProcessHandle := 0;
  FActiveProjectNotifierIndex := -1;
  FActiveProjectForNotifier := nil;
  FStopwatch := TStopwatch.Create;
  FScanCache := TObjectDictionary<string, TFileScanCache>.Create([doOwnsValues]);
  FGroupNodes := TDictionary<string, TTreeNode>.Create;

  inherited Create(AOwner);
  Caption := 'Test Explorer' {$IFDEF DEBUG} + '(Compiled: ' + GetModuleBuildTime + ')'{$ENDIF};
  Name := 'FormDextTestRunner';
  DeskSection := 'FormDextTestRunner';
  AutoSave := True;
  SaveStateNecessary := True;

  // 10.4 AutoSave can resurrect runtime controls as "_1". Scrub before Create again.
  FreeDesktopNameCollisions;

  // Set button captions with elegant symbols and hints
  RefreshButton.Caption := #$21BB + ' Refresh';
  RefreshButton.Hint := 'Rescan tests (C++: Host --discover if exe built; else source scan)';
  RefreshButton.ShowHint := True;

  RunAllButton.Caption := #$25B6 + ' Run All';
  RunAllButton.Hint := 'Run all tests in the selected project (Click dropdown arrow for more options)';
  RunAllButton.ShowHint := True;

  RunAllMenu := TPopupMenu.Create(Self);
  RunAllMenu.Name := '';
  RunAllItem1 := TMenuItem.Create(RunAllMenu);
  RunAllItem1.Caption := 'Run Selected Project';
  RunAllItem1.OnClick := RunAllButtonClick;
  RunAllMenu.Items.Add(RunAllItem1);

  RunAllItem2 := TMenuItem.Create(RunAllMenu);
  RunAllItem2.Caption := 'Run All Test Projects';
  RunAllItem2.OnClick := RunAllProjectsClick;
  RunAllMenu.Items.Add(RunAllItem2);

  RunAllItem3 := TMenuItem.Create(RunAllMenu);
  RunAllItem3.Caption := 'Run Failed Tests';
  RunAllItem3.OnClick := RunFailedTestsClick;
  RunAllMenu.Items.Add(RunAllItem3);

  RunAllButton.Style := bsSplitButton;
  RunAllButton.DropDownMenu := RunAllMenu;

  RunSelectedButton.Caption := #$25B6 + ' Selected';
  RunSelectedButton.Hint := 'Run checked tests only';
  RunSelectedButton.ShowHint := True;

  StopButton.Caption := #$25A0 + ' Stop';
  StopButton.Hint := 'Cancel current test execution';
  StopButton.ShowHint := True;

  RebuildStatusImages;

  // E1.7 / E1.8: stable names so desktop restore is idempotent (empty Name became "_1" on 10.4).
  FConsoleListView := FindComponent('DextConsoleListView') as TListView;
  if not Assigned(FConsoleListView) then
  begin
    FConsoleListView := TListView.Create(Self);
    FConsoleListView.Name := 'DextConsoleListView';
    FConsoleListView.Parent := ConsoleTab;
    FConsoleListView.Align := alClient;
    FConsoleListView.ViewStyle := vsReport;
    FConsoleListView.ReadOnly := True;
    FConsoleListView.RowSelect := True;
    FConsoleListView.MultiSelect := True;
    FConsoleListView.GridLines := False;
    FConsoleListView.HideSelection := False;
    FConsoleListView.Columns.Add.Caption := 'Time';
    FConsoleListView.Columns[0].Width := 70;
    FConsoleListView.Columns.Add.Caption := 'Kind';
    FConsoleListView.Columns[1].Width := 55;
    FConsoleListView.Columns.Add.Caption := 'Message';
    FConsoleListView.Columns[2].Width := 420;
  end;
  FConsoleListView.Parent := ConsoleTab;
  FConsoleListView.SmallImages := TestsTreeView.Images;
  FConsoleListView.OnDblClick := ConsoleListViewDblClick;
  SetupListViewClipboard(FConsoleListView);

  FCoverageTab := FindComponent('DextCoverageTab') as TTabSheet;
  if not Assigned(FCoverageTab) then
  begin
    for PageIdx := DetailsPageControl.PageCount - 1 downto 0 do
    begin
      Page := DetailsPageControl.Pages[PageIdx];
      if (Page <> InspectorTab) and (Page <> ConfigTab) and (Page <> ConsoleTab) and
         (SameText(Page.Caption, 'Coverage') or
          ((Length(Page.Name) >= 2) and (Page.Name[1] = '_') and
           CharInSet(Page.Name[2], ['0'..'9']))) then
        Page.Free;
    end;

    FCoverageTab := TTabSheet.Create(Self);
    FCoverageTab.Name := 'DextCoverageTab';
    FCoverageTab.PageControl := DetailsPageControl;
    FCoverageTab.Caption := 'Coverage';
  end
  else if FCoverageTab.PageControl = nil then
    FCoverageTab.PageControl := DetailsPageControl;

  FCoverageSummaryLabel := FindComponent('DextCoverageSummary') as TLabel;
  if not Assigned(FCoverageSummaryLabel) then
  begin
    FCoverageSummaryLabel := TLabel.Create(Self);
    FCoverageSummaryLabel.Name := 'DextCoverageSummary';
  end;
  FCoverageSummaryLabel.Parent := FCoverageTab;
  FCoverageSummaryLabel.Align := alTop;
  FCoverageSummaryLabel.Caption := 'No coverage loaded. Enable Collect Code Coverage and Run All.';
  FCoverageSummaryLabel.AlignWithMargins := True;
  FCoverageSummaryLabel.Margins.Left := 6;
  FCoverageSummaryLabel.Margins.Top := 4;
  FCoverageSummaryLabel.Margins.Right := 6;
  FCoverageSummaryLabel.Margins.Bottom := 2;

  FCoverageListView := FindComponent('DextCoverageListView') as TListView;
  if not Assigned(FCoverageListView) then
  begin
    FCoverageListView := TListView.Create(Self);
    FCoverageListView.Name := 'DextCoverageListView';
  end;
  FCoverageListView.Parent := FCoverageTab;
  FCoverageListView.Align := alClient;
  FCoverageListView.ViewStyle := vsReport;
  FCoverageListView.ReadOnly := True;
  FCoverageListView.RowSelect := True;
  FCoverageListView.MultiSelect := True;
  FCoverageListView.HideSelection := False;
  FCoverageListView.OnDblClick := CoverageListViewDblClick;
  EnsureCoverageListColumns;
  SetupListViewClipboard(FCoverageListView);

  DetailsMemo.Visible := False;

  TestsTreeView.Checkboxes := True;
  TestsTreeView.DoubleBuffered := True;
  TestsTreeView.StyleElements := [];

  // Assign advanced dynamic event handlers
  TestsTreeView.OnMouseMove := TestsTreeViewMouseMove;
  TestsTreeView.OnMouseLeave := TestsTreeViewMouseLeave;
  TestsTreeView.OnMouseDown := TestsTreeViewMouseDown;
  TestsTreeView.OnMouseUp := TestsTreeViewMouseUp;
  TestsTreeView.OnAdvancedCustomDrawItem := TestsTreeViewAdvancedCustomDrawItem;
  TestsTreeView.OnChange := TestsTreeViewChange;

  // Build context menu for TreeView
  PopupMenu := TPopupMenu.Create(Self);
  PopupMenu.Name := '';
  MenuItem := TMenuItem.Create(PopupMenu);
  MenuItem.Caption := #$25B6 + ' Run';
  MenuItem.OnClick := RunSelectedButtonClick;
  PopupMenu.Items.Add(MenuItem);

  MenuItem := TMenuItem.Create(PopupMenu);
  MenuItem.Caption := 'Debug';
  MenuItem.OnClick := DebugSelectedClick;
  PopupMenu.Items.Add(MenuItem);

  MenuItem := TMenuItem.Create(PopupMenu);
  MenuItem.Caption := '-';
  PopupMenu.Items.Add(MenuItem);

  MenuItem := TMenuItem.Create(PopupMenu);
  MenuItem.Caption := 'Expand All';
  MenuItem.OnClick := ExpandAllMenuItemClick;
  PopupMenu.Items.Add(MenuItem);

  MenuItem := TMenuItem.Create(PopupMenu);
  MenuItem.Caption := 'Collapse All';
  MenuItem.OnClick := CollapseAllMenuItemClick;
  PopupMenu.Items.Add(MenuItem);

  MenuItem := TMenuItem.Create(PopupMenu);
  MenuItem.Caption := 'Go to Source';
  MenuItem.OnClick := TestsTreeViewDblClick;
  PopupMenu.Items.Add(MenuItem);

  TestsTreeView.PopupMenu := PopupMenu;

  FFormOwnedTestLocations := TList<TTestLocation>.Create;
  FTestLocations := FFormOwnedTestLocations;
  FSessions := TObjectList<TTestSession>.Create(True);
  FActiveSession := TTestSession.CreateFromExisting(DefaultSessionTabSheet, TestsTreeView, FTestLocations, FActiveProjectFile);
  FSessions.Add(FActiveSession);

  SessionsPageControl.OnChange := SessionsPageControlChange;
  SessionsPageControl.OnContextPopup := SessionTabContextPopup;

  FServer := TTestRunnerServer.Create(8102);

  // Initialize Inspector UI dynamically
  FTestDetails := TDictionary<string, TTestDetailInfo>.Create;
  FGroupSummaries := TDictionary<string, TGroupSummaryInfo>.Create;
  FTotalTests := 0;
  FCompletedTests := 0;

  // Setup event handlers and non-design property values
  ProgressPanel.Visible := False;
  ProgressPanel.BringToFront;

  ResetSummaryLabels;

  EnableDisableTestExplorerMenuItem.OnClick := ToggleEnabledClick;
  ClearMenuItem.OnClick := ClearLogsClick;

  CustomParamsEdit.TextHint := 'e.g. --filter mytest* --verbose';
  CustomParamsEdit.OnChange := ConfigChangeHandler;

  RunOnSaveCheckBox.OnClick := ConfigChangeHandler;
  RunOnIdleCheckBox.OnClick := ConfigChangeHandler;
  EnabledCheckBox.OnClick := ToggleEnabledClick;

  ExportToJUnitXmlMenutem.OnClick := ExportMenuClick;
  ExportToXUnitXMLMenutem.OnClick := ExportMenuClick;
  ExportToJsonMenutem.OnClick := ExportMenuClick;
  ExportToSonarQubeXmlMenutem.OnClick := ExportMenuClick;
  ExportToHtmlReportMenuItem.OnClick := ExportMenuClick;

  // Actions menu: Apply Debug Trace Options (stack symbols for failed tests)
  MenuItem := TMenuItem.Create(ActionsPopupMenu);
  MenuItem.Caption := '-';
  ActionsPopupMenu.Items.Add(MenuItem);
  MenuItem := TMenuItem.Create(ActionsPopupMenu);
  MenuItem.Caption := 'Apply Debug Trace Options to Active Project';
  MenuItem.OnClick := ApplyDebugTraceOptionsClick;
  ActionsPopupMenu.Items.Add(MenuItem);

  // E1.6 / E1.8: coverage — visible in Actions; state refreshed on each open
  FCollectCoverageMenuItem := TMenuItem.Create(ActionsPopupMenu);
  FCollectCoverageMenuItem.Caption := 'Collect Code Coverage on Run';
  FCollectCoverageMenuItem.AutoCheck := True;
  FCollectCoverageMenuItem.OnClick := CollectCoverageMenuClick;
  ActionsPopupMenu.Items.Add(FCollectCoverageMenuItem);

  FInstallCoverageMenuItem := TMenuItem.Create(ActionsPopupMenu);
  FInstallCoverageMenuItem.Caption := 'Install CodeCoverage…';
  FInstallCoverageMenuItem.OnClick := EnsureCoverageToolClick;
  ActionsPopupMenu.Items.Add(FInstallCoverageMenuItem);

  FReloadCoverageMenuItem := TMenuItem.Create(ActionsPopupMenu);
  FReloadCoverageMenuItem.Caption := 'Reload Coverage Report';
  FReloadCoverageMenuItem.OnClick := ReloadCoverageClick;
  ActionsPopupMenu.Items.Add(FReloadCoverageMenuItem);

  FGenerateHtmlMenuItem := TMenuItem.Create(ActionsPopupMenu);
  FGenerateHtmlMenuItem.Caption := 'Generate Coverage HTML Report on Run';
  FGenerateHtmlMenuItem.AutoCheck := True;
  FGenerateHtmlMenuItem.Checked := False;
  FGenerateHtmlMenuItem.OnClick := GenerateHtmlMenuClick;
  ActionsPopupMenu.Items.Add(FGenerateHtmlMenuItem);

  FOpenCoverageHtmlMenuItem := TMenuItem.Create(ActionsPopupMenu);
  FOpenCoverageHtmlMenuItem.Caption := 'Open Coverage HTML Report';
  FOpenCoverageHtmlMenuItem.OnClick := OpenCoverageHtmlClick;
  ActionsPopupMenu.Items.Add(FOpenCoverageHtmlMenuItem);

  FClearCoverageArtifactsMenuItem := TMenuItem.Create(ActionsPopupMenu);
  FClearCoverageArtifactsMenuItem.Caption := 'Clear Generated Coverage Files…';
  FClearCoverageArtifactsMenuItem.OnClick := ClearCoverageArtifactsClick;
  ActionsPopupMenu.Items.Add(FClearCoverageArtifactsMenuItem);

  FCoverageCheckBox := FindComponent('DextCoverageCheckBox') as TCheckBox;
  if not Assigned(FCoverageCheckBox) then
  begin
    FCoverageCheckBox := TCheckBox.Create(Self);
    FCoverageCheckBox.Name := 'DextCoverageCheckBox';
  end;
  FCoverageCheckBox.Parent := ConfigScroll;
  FCoverageCheckBox.Caption := 'Collect code coverage on Run All / Selected';
  FCoverageCheckBox.Hint := 'Wraps the test exe with Delphi Code Coverage (⋯ Actions). Requires MAP (Debug Trace) and CodeCoverage.exe.';
  FCoverageCheckBox.ShowHint := True;
  FCoverageCheckBox.Left := EnabledCheckBox.Left;
  FCoverageCheckBox.Top := EnabledCheckBox.Top + 25;
  FCoverageCheckBox.Width := 320;
  FCoverageCheckBox.Height := 17;
  FCoverageCheckBox.TabOrder := 4;
  FCoverageCheckBox.OnClick := ConfigChangeHandler;

  FGenerateHtmlCheckBox := FindComponent('DextGenerateHtmlCheckBox') as TCheckBox;
  if not Assigned(FGenerateHtmlCheckBox) then
  begin
    FGenerateHtmlCheckBox := TCheckBox.Create(Self);
    FGenerateHtmlCheckBox.Name := 'DextGenerateHtmlCheckBox';
  end;
  FGenerateHtmlCheckBox.Parent := ConfigScroll;
  FGenerateHtmlCheckBox.Caption := 'Also generate HTML report (CodeCoverage_Summary.html)';
  FGenerateHtmlCheckBox.Hint := 'Optional. Adds -html to the coverage wrap. Open via Actions → Open Coverage HTML Report.';
  FGenerateHtmlCheckBox.ShowHint := True;
  FGenerateHtmlCheckBox.Left := EnabledCheckBox.Left;
  FGenerateHtmlCheckBox.Top := FCoverageCheckBox.Top + 25;
  FGenerateHtmlCheckBox.Width := 360;
  FGenerateHtmlCheckBox.Height := 17;
  FGenerateHtmlCheckBox.TabOrder := 5;
  FGenerateHtmlCheckBox.Checked := False;
  FGenerateHtmlCheckBox.OnClick := ConfigChangeHandler;

  if Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) then
  begin
    if ThemingServices.IDEThemingEnabled then
      ThemingServices.ApplyTheme(Self);
  end;

  // Reposition layout & session buttons
  RefreshButton.Left   := 2;
  RefreshButton.Top    := 5;
  RefreshButton.Width  := 75;
  RefreshButton.Height := 25;

  RunAllButton.Left   := 80;
  RunAllButton.Top    := 5;
  RunAllButton.Width  := 85;
  RunAllButton.Height := 25;

  RunSelectedButton.Left   := 168;
  RunSelectedButton.Top    := 5;
  RunSelectedButton.Width  := 75;
  RunSelectedButton.Height := 25;

  StopButton.Left   := 246;
  StopButton.Top    := 5;
  StopButton.Width  := 50;
  StopButton.Height := 25;

  CreateaNewSessionMenuItem.OnClick := AddSessionButtonClick;

  TabbedLayoutMenuItem.Tag := Ord(telCompact);
  TabbedLayoutMenuItem.OnClick := LayoutMenuClick;
  TabbedLayoutMenuItem.Checked := True;
  SplitBottomLayoutMenuItem.Tag := Ord(telSplitBottom);
  SplitBottomLayoutMenuItem.OnClick := LayoutMenuClick;
  SplitBottomLayoutMenuItem.Checked := True;
  SplitRightLayoutMenuItem.Tag := Ord(telSplitRight);
  SplitRightLayoutMenuItem.OnClick := LayoutMenuClick;
  SplitRightLayoutMenuItem.Checked := True;

  GroupByClassMenuItem.Tag := 100 + Ord(tgmCodeStructure);
  GroupByClassMenuItem.OnClick := GroupingMenuClick;
  GroupByClassMenuItem.Checked := True;
  GroupbyTestStatusMenuItem.Tag := 100 + Ord(tgmStatus);
  GroupbyTestStatusMenuItem.OnClick := GroupingMenuClick;
  GroupbyTestStatusMenuItem.Checked := False;

  FInspectorSplitter := FindComponent('DextInspectorSplitter') as TSplitter;
  if not Assigned(FInspectorSplitter) then
  begin
    FInspectorSplitter := TSplitter.Create(Self);
    FInspectorSplitter.Name := 'DextInspectorSplitter';
  end;
  FInspectorSplitter.Parent := DetailsPanel;
  FInspectorSplitter.Visible := False;
  FCurrentLayout := telCompact;

  // E2.3: stack block = panel (hint glued above list). Keeps hint from drifting
  // between Error label and ErrorMemo when alTop children re-order.
  FStackFrameNavs := TObjectList<TObject>.Create(True);

  FStackPanel := FindComponent('DextStackPanel') as TPanel;
  if not Assigned(FStackPanel) then
  begin
    FStackPanel := TPanel.Create(Self);
    FStackPanel.Name := 'DextStackPanel';
  end;
  FStackPanel.Parent := InspectorScroll;
  FStackPanel.BevelOuter := bvNone;
  FStackPanel.Caption := '';
  FStackPanel.ParentBackground := True;
  FStackPanel.Align := alClient;
  FStackPanel.Visible := False;

  FStackHintLabel := FindComponent('DextStackHint') as TLabel;
  if not Assigned(FStackHintLabel) then
  begin
    FStackHintLabel := TLabel.Create(Self);
    FStackHintLabel.Name := 'DextStackHint';
  end;
  FStackHintLabel.Parent := FStackPanel;
  FStackHintLabel.Align := alTop;
  FStackHintLabel.Caption := 'Stack Trace — double-click a frame to open source';
  FStackHintLabel.Height := ScalePx(18);
  FStackHintLabel.AlignWithMargins := True;
  FStackHintLabel.Margins.Left := ScalePx(6);
  FStackHintLabel.Margins.Top := ScalePx(4);
  FStackHintLabel.Margins.Bottom := 0;

  FStackFramesListView := FindComponent('DextStackFramesListView') as TListView;
  if not Assigned(FStackFramesListView) then
  begin
    FStackFramesListView := TListView.Create(Self);
    FStackFramesListView.Name := 'DextStackFramesListView';
    FStackFramesListView.Columns.Add.Caption := '#';
    FStackFramesListView.Columns[0].Width := ScalePx(30);
    FStackFramesListView.Columns.Add.Caption := 'Method';
    FStackFramesListView.Columns[1].Width := ScalePx(260);
    FStackFramesListView.Columns.Add.Caption := 'Location';
    FStackFramesListView.Columns[2].Width := ScalePx(180);
  end;
  FStackFramesListView.Parent := FStackPanel;
  FStackFramesListView.Align := alClient;
  FStackFramesListView.ViewStyle := vsReport;
  FStackFramesListView.ReadOnly := True;
  FStackFramesListView.RowSelect := True;
  FStackFramesListView.MultiSelect := True;
  FStackFramesListView.GridLines := False;
  FStackFramesListView.HideSelection := False;
  FStackFramesListView.HotTrack := True;
  FStackFramesListView.OnDblClick := StackFramesListViewDblClick;
  FStackFramesListView.OnKeyDown := StackFramesListViewKeyDown;
  SetupListViewClipboard(FStackFramesListView);

  // Disabled overlay banner/panel
  FDisabledPanel := FindComponent('DextDisabledPanel') as TPanel;
  if not Assigned(FDisabledPanel) then
  begin
    FDisabledPanel := TPanel.Create(Self);
    FDisabledPanel.Name := 'DextDisabledPanel';
  end;
  FDisabledPanel.Parent := Self;
  FDisabledPanel.Align := alClient;
  FDisabledPanel.BevelOuter := bvNone;
  FDisabledPanel.Visible := False;
  FDisabledPanel.Color := clWindow;
  FDisabledPanel.ParentBackground := False;

  FDisabledContainer := FindComponent('DextDisabledContainer') as TPanel;
  if not Assigned(FDisabledContainer) then
  begin
    FDisabledContainer := TPanel.Create(Self);
    FDisabledContainer.Name := 'DextDisabledContainer';
  end;
  FDisabledContainer.Parent := FDisabledPanel;
  FDisabledContainer.Width := 300;
  FDisabledContainer.Height := 100;
  FDisabledContainer.BevelOuter := bvNone;
  FDisabledContainer.ParentBackground := True;

  DisabledMsgLabel := FindComponent('DextDisabledMsg') as TLabel;
  if not Assigned(DisabledMsgLabel) then
  begin
    DisabledMsgLabel := TLabel.Create(Self);
    DisabledMsgLabel.Name := 'DextDisabledMsg';
  end;
  DisabledMsgLabel.Parent := FDisabledContainer;
  DisabledMsgLabel.Align := alTop;
  DisabledMsgLabel.Alignment := taCenter;
  DisabledMsgLabel.Caption := 'Dext Test Explorer is currently disabled.' + #13#10 + 'Enable it to load projects and run tests.';
  DisabledMsgLabel.Font.Size := 10;
  DisabledMsgLabel.Height := 40;

  EnableButton := FindComponent('DextEnableButton') as TButton;
  if not Assigned(EnableButton) then
  begin
    EnableButton := TButton.Create(Self);
    EnableButton.Name := 'DextEnableButton';
  end;
  EnableButton.Parent := FDisabledContainer;
  EnableButton.Left := (FDisabledContainer.Width - 120) div 2;
  EnableButton.Top := 50;
  EnableButton.Width := 120;
  EnableButton.Height := 30;
  EnableButton.Caption := 'Enable';
  EnableButton.OnClick := EnableBtnClick;
  EnableDisableTestExplorerMenuItem.OnClick := ToggleEnabledClick;
  EnableDisableTestExplorerMenuItem.Visible := True;

  // Initialize Idle Timer
  FIdleTimer := FindComponent('DextIdleTimer') as TTimer;
  if not Assigned(FIdleTimer) then
  begin
    FIdleTimer := TTimer.Create(Self);
    FIdleTimer.Name := 'DextIdleTimer';
  end;
  FIdleTimer.Interval := 2500; // 2.5 seconds debounce
  FIdleTimer.Enabled := False;
  FIdleTimer.OnTimer := IdleTimerTimer;

  // Initialize Save Timer and list
  FSaveTimer := FindComponent('DextSaveTimer') as TTimer;
  if not Assigned(FSaveTimer) then
  begin
    FSaveTimer := TTimer.Create(Self);
    FSaveTimer.Name := 'DextSaveTimer';
  end;
  FSaveTimer.Interval := 250; // 250ms debounce
  FSaveTimer.Enabled := False;
  FSaveTimer.OnTimer := SaveTimerTimer;

  FCoveragePlatformTimer := TTimer.Create(Self);
  FCoveragePlatformTimer.Interval := 1500;
  FCoveragePlatformTimer.Enabled := True;
  FCoveragePlatformTimer.OnTimer := CoveragePlatformTimerTimer;

  FPendingSaveFiles := TStringList.Create;
  FPendingSaveFiles.Sorted := True;
  FPendingSaveFiles.Duplicates := dupIgnore;

  FPendingResultJson := TStringList.Create;
  FUiFlushScheduled := False;
  FBatchingUi := False;
  FNodeByName := TDictionary<string, TTreeNode>.Create;

  // Load layout and configs from ini file
  LayoutMode := Ord(telCompact);
  GroupingMode := Ord(tgmCodeStructure);
  IniFile := TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini');
  try
    Ini := TMemIniFile.Create(IniFile);
    try
      FEnabled := Ini.ReadBool('General', 'Enabled', True);
      LayoutMode := Ini.ReadInteger('Layout', 'Mode', Ord(telCompact));
      GroupingMode := Ini.ReadInteger('Grouping', 'Mode', Ord(tgmCodeStructure));
      CustomParamsEdit.Text := Ini.ReadString('General', 'CustomParams', '');
      RunOnSaveCheckBox.Checked := Ini.ReadBool('General', 'RunOnSave', False);
      RunOnIdleCheckBox.Checked := Ini.ReadBool('General', 'RunOnIdle', False);
      if Assigned(FCoverageCheckBox) then
        FCoverageCheckBox.Checked := Ini.ReadBool('Coverage', 'Enabled', False);
      if Assigned(FGenerateHtmlCheckBox) then
        FGenerateHtmlCheckBox.Checked := Ini.ReadBool('Coverage', 'GenerateHtml', False);
    finally
      Ini.Free;
    end;
  except
    FEnabled := True;
  end;

  UpdateCoverageUiState;
  SetEnabledState(FEnabled);
  ApplyLayout(TTestExplorerLayout(LayoutMode));
  FGroupingMode := TTestGroupingMode(GroupingMode);
  FIdleTimer.Enabled := RunOnIdleCheckBox.Checked;

  // Sync menu Checked states based on loaded configurations
  TabbedLayoutMenuItem.Checked := TTestExplorerLayout(LayoutMode) = telCompact;
  SplitBottomLayoutMenuItem.Checked := TTestExplorerLayout(LayoutMode) = telSplitBottom;
  SplitRightLayoutMenuItem.Checked := TTestExplorerLayout(LayoutMode) = telSplitRight;

  GroupByClassMenuItem.Checked := TTestGroupingMode(GroupingMode) = tgmCodeStructure;
  GroupByTestStatusMenuItem.Checked := TTestGroupingMode(GroupingMode) = tgmStatus;

  Self.KeyPreview := True;
  Self.OnKeyDown := FormKeyDown;

  FThemeNotifierIndex := -1;
  ApplyIDETheme;

  if Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) then
  begin
    FThemeNotifierIndex := ThemingServices.AddNotifier(TDextThemeNotifier.Create(Self) as INTAIDEThemingServicesNotifier);
  end;

  LogExplorerSurface('Create end');
  if FEnabled then
  begin
    { Paint the combo only after the window stays on screen (docked or floating). }
    FRefreshWhenShown := True;
    LogExplorerSurface('Create: RefreshProjects deferred');
    FServer.Start(OnTestResultReceived);
  end;
  UpdateTabVisibility;
  FDiscoverMode := False;
  FDiscoverAfterCompile := False;
end;

destructor TFormDextTestRunner.Destroy;
var
  LThemingServices: IOTAIDEThemingServices;
  I: Integer;
begin
  // Drop global alias immediately so queued UI work bails out.
  if FormDextTestRunner = Self then
    FormDextTestRunner := nil;

  FUiFlushScheduled := False;
  Inc(FScanGeneration); // invalidate in-flight scan Queue callbacks

  if Assigned(FIdleTimer) then
  begin
    FIdleTimer.Enabled := False;
    FreeAndNil(FIdleTimer);
  end;
  if Assigned(FSurfaceSettleTimer) then
  begin
    FSurfaceSettleTimer.Enabled := False;
    FreeAndNil(FSurfaceSettleTimer);
  end;
  if Assigned(FSaveTimer) then
  begin
    FSaveTimer.Enabled := False;
    FreeAndNil(FSaveTimer);
  end;
  if Assigned(FCoveragePlatformTimer) then
  begin
    FCoveragePlatformTimer.Enabled := False;
    FreeAndNil(FCoveragePlatformTimer);
  end;

  if (FActiveProjectNotifierIndex <> -1) and Assigned(FActiveProjectForNotifier) then
  begin
    try
      FActiveProjectForNotifier.RemoveNotifier(FActiveProjectNotifierIndex);
    except
    end;
    FActiveProjectNotifierIndex := -1;
    FActiveProjectForNotifier := nil;
  end;

  if FRunningProcessHandle <> 0 then
  begin
    TerminateProcess(FRunningProcessHandle, 0);
    CloseHandle(FRunningProcessHandle);
    FRunningProcessHandle := 0;
  end;

  if FThemeNotifierIndex <> -1 then
  begin
    try
      if Supports(BorlandIDEServices, IOTAIDEThemingServices, LThemingServices) then
        LThemingServices.RemoveNotifier(FThemeNotifierIndex);
    except
    end;
    FThemeNotifierIndex := -1;
  end;

  if Assigned(FServer) then
  begin
    try
      FServer.Stop;
    except
    end;
    FreeAndNil(FServer);
  end;

  // Drop aliases into session data before freeing the session list.
  FActiveSession := nil;
  FTestLocations := nil;
  FreeAndNil(FSessions);
  FreeAndNil(FFormOwnedTestLocations);

  FreeAndNil(FTestDetails);
  FreeAndNil(FGroupSummaries);
  FreeAndNil(FGroupNodes);
  FreeAndNil(FPendingSaveFiles);
  FreeAndNil(FPendingResultJson);
  FreeAndNil(FNodeByName);
  FreeAndNil(FScanCache);
  FreeAndNil(FStackFrameNavs);

  if Assigned(ProjectsComboBox) then
  begin
    for I := 0 to ProjectsComboBox.Items.Count - 1 do
      ProjectsComboBox.Items.Objects[I].Free;
  end;

  try
    inherited Destroy;
  except
  end;
end;

function TFormDextTestRunner.ScalePx(ADesignPx: Integer): Integer;
var
  Ppi: Integer;
begin
  // Design pixels are authored at 96 DPI; scale for 100% / 150% / 200% monitors.
  Ppi := CurrentPPI;
  if Ppi <= 0 then
    Ppi := 96;
  Result := MulDiv(ADesignPx, Ppi, 96);
end;

procedure TFormDextTestRunner.ApplyDpiScaling;
var
  i: Integer;
  Session: TTestSession;
begin
  ButtonsPanel.Height := ScalePx(31);

  RefreshButton.Height := ScalePx(25);
  RefreshButton.Width := ScalePx(90);

  RunAllButton.Height := ScalePx(25);
  RunAllButton.Width := ScalePx(95);

  RunSelectedButton.Height := ScalePx(25);
  RunSelectedButton.Width := ScalePx(95);

  StopButton.Height := ScalePx(25);
  StopButton.Width := ScalePx(65);

  ActionsButton.Height := ScalePx(25);
  ActionsButton.Width := ScalePx(30);

  if Assigned(InfoPanel) then
    InfoPanel.Height := ScalePx(98);

  if Assigned(FStackHintLabel) then
  begin
    FStackHintLabel.Margins.Left := ScalePx(6);
    FStackHintLabel.Margins.Top := ScalePx(4);
    FStackHintLabel.Height := ScalePx(18);
  end;

  if Assigned(FStackFramesListView) and (FStackFramesListView.Columns.Count >= 3) then
  begin
    FStackFramesListView.Columns[0].Width := ScalePx(30);
    FStackFramesListView.Columns[1].Width := ScalePx(260);
    FStackFramesListView.Columns[2].Width := ScalePx(180);
  end;

  if Assigned(FSessions) then
  begin
    for i := 0 to FSessions.Count - 1 do
    begin
      Session := FSessions[i];
      if Assigned(Session.FilterEdit) and Assigned(Session.FilterEdit.Parent) then
        TPanel(Session.FilterEdit.Parent).Height := ScalePx(28);
      if Assigned(Session.ClearFilterButton) then
        Session.ClearFilterButton.Width := ScalePx(22);
    end;
  end;

  // Re-apply inspector heights (Error memo / stack panel) for the new PPI.
  if Assigned(ErrorMemo) and ErrorMemo.Visible then
    LayoutInspectorDetails(True, IfThen(Assigned(FStackFramesListView), FStackFramesListView.Items.Count, 0))
  else if Assigned(FStackPanel) and FStackPanel.Visible then
    LayoutInspectorDetails(False, IfThen(Assigned(FStackFramesListView), FStackFramesListView.Items.Count, 0));
end;

function TFormDextTestRunner.IsDfmNonVisual(AComponent: TComponent): Boolean;
begin
  // ActionsPopupMenu owns its TMenuItems; writing the menu streams the items.
  Result := AComponent = ActionsPopupMenu;
end;

procedure TFormDextTestRunner.FreeDesktopNameCollisions;
var
  I: Integer;
  Comp: TComponent;
  CompName: string;
begin
  for I := ComponentCount - 1 downto 0 do
  begin
    Comp := Components[I];
    CompName := Comp.Name;
    // ReadRootComponent FindUniqueName('') → "_1"; old Coverage Create(PageControl) debris.
    if (Length(CompName) >= 2) and (CompName[1] = '_') and CharInSet(CompName[2], ['0'..'9']) then
      Comp.Free;
  end;
end;

procedure TFormDextTestRunner.GetChildren(Proc: TGetChildProc; Root: TComponent);
var
  I: Integer;
  Comp: TComponent;
begin
  // Visual children only (TWinControl). Do not stream runtime timers/menus/dynamic
  // helpers — 10.4 AutoSave resurrected them as "_1 already exists".
  for I := 0 to ControlCount - 1 do
    if Controls[I].Owner = Root then
      Proc(Controls[I]);

  if Root <> Self then
    Exit;

  for I := 0 to ComponentCount - 1 do
  begin
    Comp := Components[I];
    if Comp.HasParent then
      Continue;
    if Comp is TControl then
      Continue;
    if IsDfmNonVisual(Comp) then
      Proc(Comp);
  end;
end;

function TFormDextTestRunner.ExplorerSurfaceReady: Boolean;
begin
  if csDestroying in ComponentState then
    Exit(False);
  if not (Visible and Showing) then
    Exit(False);
  { Menu open is intentional. A restored window counts after it stays up,
    docked or floating. }
  Result := FUserOpenedExplorer or FSurfaceSettled;
end;

procedure TFormDextTestRunner.CancelSurfaceSettle;
begin
  if Assigned(FSurfaceSettleTimer) then
    FSurfaceSettleTimer.Enabled := False;
end;

procedure TFormDextTestRunner.ArmSurfaceSettle;
begin
  if FSurfaceSettleTimer = nil then
  begin
    FSurfaceSettleTimer := TTimer.Create(Self);
    FSurfaceSettleTimer.Name := 'DextSurfaceSettleTimer';
    FSurfaceSettleTimer.Interval := 1500;
    FSurfaceSettleTimer.OnTimer := SurfaceSettleTimerFired;
  end;
  FSurfaceSettleTimer.Enabled := False;
  FSurfaceSettleTimer.Enabled := True;
end;

procedure TFormDextTestRunner.SurfaceSettleTimerFired(Sender: TObject);
begin
  CancelSurfaceSettle;
  if csDestroying in ComponentState then
    Exit;
  if not (Visible and Showing) then
  begin
    LogExplorerSurface('settle elapsed but hidden');
    Exit;
  end;
  FSurfaceSettled := True;
  LogExplorerSurface('settle elapsed — window stayed (docked or floating)');
  FlushRefreshWhenShown;
end;

procedure TFormDextTestRunner.LogExplorerSurface(const AWhere: string);
var
  DockName: string;
begin
  if HostDockSite <> nil then
    DockName := HostDockSite.Name
  else
    DockName := '-';
  ExpertTrace(Format(
    '[Explorer] %s ready=%s visible=%s showing=%s floating=%s dock=%s userOpen=%s bounds=%d,%d %dx%d',
    [AWhere,
     BoolToStr(ExplorerSurfaceReady, True),
     BoolToStr(Visible, True),
     BoolToStr(Showing, True),
     BoolToStr(Floating, True),
     DockName,
     BoolToStr(FUserOpenedExplorer, True),
     Left, Top, Width, Height]));
end;

procedure TFormDextTestRunner.FlushRefreshWhenShown;
begin
  if not FRefreshWhenShown then
    Exit;
  if not ExplorerSurfaceReady then
  begin
    LogExplorerSurface('FlushRefresh deferred');
    Exit;
  end;
  if not FEnabled then
  begin
    FRefreshWhenShown := False;
    Exit;
  end;
  FRefreshWhenShown := False;
  LogExplorerSurface('FlushRefresh -> RefreshProjects');
  RefreshProjects;
end;

procedure TFormDextTestRunner.DoShow;
begin
  LogExplorerSurface('DoShow enter');
  inherited DoShow;
  ApplyDpiScaling;
  ApplyIDETheme;
  LogExplorerSurface('DoShow leave');
  if FUserOpenedExplorer or ((HostDockSite <> nil) and not Floating) then
  begin
    CancelSurfaceSettle;
    FSurfaceSettled := True;
    FlushRefreshWhenShown;
  end
  else
  begin
    FSurfaceSettled := False;
    ArmSurfaceSettle;
    LogExplorerSurface('DoShow floating — refresh waits 1.5s to see if it stays');
  end;
end;

procedure TFormDextTestRunner.DoHide;
begin
  if not (csDestroying in ComponentState) then
  begin
    CancelSurfaceSettle;
    FSurfaceSettled := False;
    FUserOpenedExplorer := False;
    LogExplorerSurface('DoHide');
  end;
  inherited DoHide;
end;

procedure TFormDextTestRunner.DoDock(NewDockSite: TWinControl; var ARect: TRect);
begin
  inherited DoDock(NewDockSite, ARect);
  if csDestroying in ComponentState then
    Exit;
  if NewDockSite <> nil then
    LogExplorerSurface('DoDock ' + NewDockSite.ClassName + '.' + NewDockSite.Name)
  else
    LogExplorerSurface('DoDock undock');
  if not (Visible and Showing) then
    Exit;
  { Undock while the window stays open is a real layout, same as docked. }
  CancelSurfaceSettle;
  FSurfaceSettled := True;
  FlushRefreshWhenShown;
end;

function TFormDextTestRunner.GetProjectByFileName(const AFileName: string): IOTAProject;
var
  i: Integer;
  ModuleServices: IOTAModuleServices;
  ProjectGroup: IOTAProjectGroup;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;
  ProjectGroup := ModuleServices.MainProjectGroup;
  if Assigned(ProjectGroup) then
  begin
    for i := 0 to ProjectGroup.ProjectCount - 1 do
    begin
      if Assigned(ProjectGroup.Projects[i]) and SameText(ProjectGroup.Projects[i].FileName, AFileName) then
      begin
        Result := ProjectGroup.Projects[i];
        Exit;
      end;
    end;
  end;
end;

procedure TFormDextTestRunner.RefreshActiveProjectTestsList;
var
  Cache: TFileScanCache;
  CacheDict: TObjectDictionary<string, TFileScanCache>;
  FileName: string;
  Files: TArray<string>;
  FilesToScan: TList<string>;
  FilesToScanArray: TArray<string>;
  FileTime: TDateTime;
  Generation: Integer;
  i: Integer;
  ModifiedTimes: TArray<TDateTime>;
  Project: IOTAProject;
  Stopwatch: TStopwatch;
  Tests: TList<TTestLocation>;
begin
  if not FEnabled then Exit;
  Stopwatch := TStopwatch.StartNew;
  LogPerformance('RefreshActiveProjectTestsList: begin');
  Project := GetProjectByFileName(FActiveProjectFile);
  if not Assigned(Project) then
  begin
    TestsTreeView.Items.BeginUpdate;
    try
      TestsTreeView.Items.Clear;
      FTestLocations.Clear;
      ResetSummaryLabels;
    finally
      TestsTreeView.Items.EndUpdate;
    end;
    LogPerformance(Format('RefreshActiveProjectTestsList: no project %.2f ms', [Stopwatch.Elapsed.TotalMilliseconds]));
    Exit;
  end;

  { C++: never Host --discover just because the project was selected / opened.
    Opening a .cbproj used to launch (or even build) before the user saw the IDE.
    List tests from source here; Refresh button runs DiscoverCppProjectTests. }
  if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
  begin
    PopulateCppTestsFromAstOnly;
    LogPerformance(Format('RefreshActiveProjectTestsList: cpp AST-only %.2f ms',
      [Stopwatch.Elapsed.TotalMilliseconds]));
    Exit;
  end;

  SetLength(Files, Project.GetModuleCount);
  for i := 0 to Project.GetModuleCount - 1 do
    Files[i] := Project.GetModule(i).FileName;

  TestsTreeView.Items.BeginUpdate;
  try
    TestsTreeView.Items.Clear;
    FTestLocations.Clear;
    TestsTreeView.Items.AddChild(nil, 'Loading tests asynchronously...');
  finally
    TestsTreeView.Items.EndUpdate;
  end;

  Inc(FScanGeneration);
  Generation := FScanGeneration;

  // Query modified times and determine what needs to be scanned
  CacheDict := TObjectDictionary<string, TFileScanCache>(FScanCache);
  FilesToScan := TList<string>.Create;
  try
    for FileName in Files do
    begin
      if FileExists(FileName) and (
           SameText(ExtractFileExt(FileName), '.pas') or
           SameText(ExtractFileExt(FileName), '.cpp') or
           SameText(ExtractFileExt(FileName), '.h') or
           SameText(ExtractFileExt(FileName), '.hpp') or
           SameText(ExtractFileExt(FileName), '.cc')) then
      begin
        Cache := nil;
        FileTime := TFile.GetLastWriteTime(FileName);
        if CacheDict.TryGetValue(FileName, Cache) then
        begin
          if Cache.Timestamp <> FileTime then
            FilesToScan.Add(FileName);
        end
        else
          FilesToScan.Add(FileName);
      end;
    end;
    FilesToScanArray := FilesToScan.ToArray;
  finally
    FilesToScan.Free;
  end;

  SetLength(ModifiedTimes, Length(FilesToScanArray));
  for i := 0 to Length(FilesToScanArray) - 1 do
    ModifiedTimes[i] := TFile.GetLastWriteTime(FilesToScanArray[i]);

  TTask.Run(TProc(procedure
    var
      LScannedLists: TArray<TList<TTestLocation>>;
      i: Integer;
    begin
      SetLength(LScannedLists, Length(FilesToScanArray));
      LogPerformance(Format('RefreshActiveProjectTestsList: scan start (%d files)', [Length(FilesToScanArray)]));

      for i := 0 to Length(FilesToScanArray) - 1 do
      begin
        Tests := nil;
        if TTestASTScanner.ScanFile(FilesToScanArray[i], Tests) then
          LScannedLists[i] := Tests
        else
          LScannedLists[i] := nil;
      end;
      LogPerformance('RefreshActiveProjectTestsList: scan end');

      TThread.Queue(nil, TThreadProcedure(procedure
        var
          FileName: string;
          i: Integer;
          TestLoc: TTestLocation;
          UiStopwatch: TStopwatch;
        begin
          if IsTestingDesignShuttingDown or (FormDextTestRunner <> Self) or
             (csDestroying in ComponentState) then
          begin
            for i := 0 to Length(LScannedLists) - 1 do
              if Assigned(LScannedLists[i]) then
                LScannedLists[i].Free;
            Exit;
          end;

          UiStopwatch := TStopwatch.StartNew;
          if Generation <> FScanGeneration then
          begin
            for i := 0 to Length(LScannedLists) - 1 do
              if Assigned(LScannedLists[i]) then
                LScannedLists[i].Free;
            Exit;
          end;

          for i := 0 to Length(FilesToScanArray) - 1 do
          begin
            FileName := FilesToScanArray[i];
            Tests := LScannedLists[i];
            if Tests = nil then
              Tests := TList<TTestLocation>.Create;
            CacheDict.AddOrSetValue(FileName, TFileScanCache.Create(ModifiedTimes[i], Tests));
          end;

          TestsTreeView.Items.BeginUpdate;
          try
            TestsTreeView.Items.Clear;
            FTestLocations.Clear;

            for FileName in Files do
            begin
              Cache := nil;
              if CacheDict.TryGetValue(FileName, Cache) then
              begin
                for TestLoc in Cache.Tests do
                  FTestLocations.Add(TestLoc);
              end;
            end;

            RefreshTreeView;
          finally
            TestsTreeView.Items.EndUpdate;
          end;
          if not IsTestingDesignShuttingDown then
            TThread.ForceQueue(nil, TThreadProcedure(procedure
              begin
                if IsTestingDesignShuttingDown then
                  Exit;
                if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
                  FormDextTestRunner.ExpandTestsTreeView;
              end));
          LogPerformance(Format('RefreshActiveProjectTestsList: ui rebuild %.2f ms, total %.2f ms', [UiStopwatch.Elapsed.TotalMilliseconds, Stopwatch.Elapsed.TotalMilliseconds]));
        end));
    end));
end;

procedure TFormDextTestRunner.ApplyIDETheme;
var
  BgColor, FgColor: TColor;
  i: Integer;
  Session: TTestSession;
  ThemingServices: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) then
  begin
    if ThemingServices.IDEThemingEnabled then
    begin
      BgColor := ThemingServices.StyleServices.GetSystemColor(clWindow);
      FgColor := ThemingServices.StyleServices.GetSystemColor(clWindowText);

      // 1. Update the active TestsTreeView
      if Assigned(TestsTreeView) then
      begin
        TestsTreeView.Color := BgColor;
        TestsTreeView.Font.Color := FgColor;
        TestsTreeView.Font.Size := 9;
        TestsTreeView.Invalidate;
      end;

      // 2. Loop through all sessions to update all TreeViews
      if Assigned(FSessions) then
      begin
        for i := 0 to FSessions.Count - 1 do
        begin
          Session := FSessions[i];
          if Assigned(Session.TreeView) then
          begin
            Session.TreeView.Color := BgColor;
            Session.TreeView.Font.Color := FgColor;
            Session.TreeView.Font.Size := 9;
            Session.TreeView.Invalidate;
          end;
        end;
      end;

      // 3. Details Memo (hidden) + structured console log list view
      if Assigned(DetailsMemo) then
      begin
        DetailsMemo.Color := BgColor;
        DetailsMemo.Font.Color := FgColor;
      end;

      if Assigned(FConsoleListView) then
      begin
        FConsoleListView.Color := BgColor;
        FConsoleListView.Font.Color := FgColor;
        FConsoleListView.Invalidate;
      end;

      if Assigned(FStackFramesListView) then
      begin
        FStackFramesListView.Color := BgColor;
        FStackFramesListView.Font.Color := FgColor;
        FStackFramesListView.Invalidate;
      end;

      // 4. Test Inspector (Scrollbox & Labels)
      if Assigned(InspectorScroll) then
      begin
        InspectorScroll.ParentColor := False;
        InspectorScroll.Color := BgColor;
      end;

      if Assigned(TestNameLabel) then TestNameLabel.Font.Color := FgColor;
      if Assigned(StatusLabel) then
      begin
        if (not string(StatusLabel.Caption).Contains('Passed')) and (not string(StatusLabel.Caption).Contains('Failed')) then
          StatusLabel.Font.Color := FgColor;
      end;
      if Assigned(LocationLabel) then LocationLabel.Font.Color := FgColor;
      if Assigned(DurationLabel) then DurationLabel.Font.Color := FgColor;
      if Assigned(ErrorHeaderLabel) then ErrorHeaderLabel.Font.Color := FgColor;

      if Assigned(ErrorMemo) then
      begin
        ErrorMemo.Color := BgColor;
        ErrorMemo.Font.Color := FgColor;
      end;

      if Assigned(SummaryTotalLabel) then SummaryTotalLabel.Font.Color := FgColor;
      if Assigned(SummarySelectedLabel) then SummarySelectedLabel.Font.Color := FgColor;
      if Assigned(SummaryTimeLabel) then SummaryTimeLabel.Font.Color := FgColor;

      // 5. Form background color
      Self.Color := ThemingServices.StyleServices.GetSystemColor(clBtnFace);

      RebuildStatusImages;
    end;
  end;
end;

procedure TFormDextTestRunner.CMStyleChanged(var Message: TMessage);
begin
  inherited;
  if IsTestingDesignShuttingDown then
    Exit;
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
        FormDextTestRunner.ApplyIDETheme;
    end));
end;

procedure TFormDextTestRunner.Resize;
begin
  inherited;
  if Assigned(FDisabledContainer) and Assigned(FDisabledPanel) then
  begin
    FDisabledContainer.Left := (FDisabledPanel.ClientWidth - FDisabledContainer.Width) div 2;
    FDisabledContainer.Top := (FDisabledPanel.ClientHeight - FDisabledContainer.Height) div 2;
  end;
end;

procedure TFormDextTestRunner.SetEnabledState(AValue: Boolean);
var
  Handler: TNotifyEvent;
begin
  FEnabled := AValue;
  { Tear down / restore IDE hooks (FileNotification side-effects, gutter, module notifiers). }
  SetDextTestExplorerEnabled(AValue);

  FDisabledPanel.Visible := not AValue;

  if Assigned(EnabledCheckBox) then
  begin
    Handler := EnabledCheckBox.OnClick;
    EnabledCheckBox.OnClick := nil;
    try
      EnabledCheckBox.Checked := AValue;
    finally
      EnabledCheckBox.OnClick := Handler;
    end;
  end;

  ProjectsComboBox.Enabled := AValue;
  ButtonsPanel.Enabled := AValue;
  SessionsPageControl.Enabled := AValue;
  DetailsPanel.Enabled := AValue;

  if AValue then
  begin
    if Assigned(FServer) then
      FServer.Start(OnTestResultReceived);
    if ProjectsComboBox.Items.Count = 0 then
      RefreshProjects
    else if FActiveProjectFile <> '' then
      RefreshActiveProjectTestsList;
  end
  else
  begin
    if Assigned(FServer) then
    try
      FServer.Stop;
    except
    end;
    if Assigned(TestsTreeView) then
      TestsTreeView.Items.Clear;
    if Assigned(FTestLocations) then
      FTestLocations.Clear;
  end;

  if Assigned(EnableDisableTestExplorerMenuItem) then
  begin
    if AValue then
      EnableDisableTestExplorerMenuItem.Caption := 'Disable Test Explorer'
    else
      EnableDisableTestExplorerMenuItem.Caption := 'Enable Test Explorer';
  end;
end;

procedure TFormDextTestRunner.ToggleEnabledClick(Sender: TObject);
var
  IniFile: TMemIniFile;
begin
  SetEnabledState(not FEnabled);
  IniFile := TMemIniFile.Create(TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini'));
  try
    IniFile.WriteBool('General', 'Enabled', FEnabled);
    IniFile.UpdateFile;
  finally
    IniFile.Free;
  end;
end;

procedure TFormDextTestRunner.EnableBtnClick(Sender: TObject);
var
  IniFile : TMemIniFile;
begin
  SetEnabledState(True);
  IniFile := TMemIniFile.Create(TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini'));
  try
    IniFile.WriteBool('General', 'Enabled', True);
    IniFile.UpdateFile;
  finally
    IniFile.Free;
  end;
end;

procedure TFormDextTestRunner.ClearLogsClick(Sender: TObject);
begin
  if Assigned(FConsoleListView) then
    FConsoleListView.Items.Clear;
  DetailsMemo.Clear; // kept for safety even though it is hidden (E1.7)
  ClearTestStatus;
  ResetSummaryLabels;
end;

procedure TFormDextTestRunner.RunFailedTestsClick(Sender: TObject);
var
  FailedTests: TList<string>;
  Info: TTestDetailInfo;
  Key: string;
begin
  FailedTests := TList<string>.Create;
  try
    for Key in FTestDetails.Keys do
    begin
      Info := FTestDetails[Key];
      if SameText(Info.Status, 'Failed') or SameText(Info.Status, 'Error') then
      begin
        FailedTests.Add(Key);
      end;
    end;

    if FailedTests.Count > 0 then
    begin
      LogMsg(Format('Running %d failed tests...', [FailedTests.Count]));
      RunImpactedTests(FailedTests.ToArray);
    end
    else
    begin
      LogMsg('No failed tests to run.');
    end;
  finally
    FailedTests.Free;
  end;
end;

function TFormDextTestRunner.ApplyDebugTraceOptionsToProject(const AProject: IOTAProject;
  out AConfigName: string): Boolean;
var
  Configs: IOTAProjectOptionsConfigurations;
  Cfg: IOTABuildConfiguration;
  IsCpp: Boolean;
  Opts: IOTAProjectOptions;
begin
  Result := False;
  AConfigName := '';
  if not Assigned(AProject) then
    Exit;
  IsCpp := SameText(ExtractFileExt(AProject.FileName), '.cbproj');

  if Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) and
     Assigned(Configs.ActiveConfiguration) then
  begin
    Cfg := Configs.ActiveConfiguration;
    AConfigName := Cfg.Name;
    if IsCpp then
    begin
      { C++Builder Clang/classic — BCC_* / ILINK_*, not Delphi DCC_*. }
      Cfg.Value['BCC_DisableOptimizations'] := 'true';
      Cfg.Value['BCC_OptimizeForSpeed'] := 'false';
      Cfg.Value['BCC_DebugLineNumbers'] := 'true';
      Cfg.Value['BCC_SourceDebuggingOn'] := 'true';
      Cfg.Value['BCC_StackFrames'] := 'true';
      Cfg.Value['BCC_EnableCPPExceptions'] := 'true';
      Cfg.Value['ILINK_FullDebugInfo'] := 'true';
      { Project → Options → C++ Linker → Output → Map file type = Detailed segment map.
        Value must be DetailedSegments — plain "Detailed" is passed to ilink as DETAILED.OBJ. }
      try
        Cfg.Value['ILINK_MapFileType'] := 'DetailedSegments';
      except
      end;
      try
        Cfg.Value['CLANG_UnwindTables'] := 'true';
      except
      end;
    end
    else
    begin
      Cfg.Value['DCC_Optimization'] := 'false';
      Cfg.Value['DCC_DebugInformation'] := '2'; // Full debug information
      Cfg.Value['DCC_UseDebugDCUs'] := 'true';
      Cfg.Value['DCC_MapFile'] := '3'; // Detailed
      try
        Cfg.Value['DCC_DebugInfoInExe'] := 'true';
      except
      end;
    end;
    Result := True;
  end
  else if Supports(AProject.ProjectOptions, IOTAProjectOptions, Opts) then
  begin
    AConfigName := '(legacy options)';
    Opts.Values['Optimization'] := False;
    Opts.Values['DebugInformation'] := True;
    if not IsCpp then
      Opts.Values['UseDebugDCUs'] := True;
    Result := True;
  end;

  if Result then
  begin
    try
      (AProject as IOTAModule).MarkModified;
    except
    end;
  end;
end;

procedure TFormDextTestRunner.ApplyDebugTraceOptionsClick(Sender: TObject);
var
  ConfigName: string;
  IsCpp: Boolean;
  Proj: IOTAProject;
begin
  Proj := GetProjectByFileName(FActiveProjectFile);
  if not Assigned(Proj) then
  begin
    LogMsg('Apply Debug Trace Options: no active test project selected.');
    MessageDlg('Select a test project in the Explorer combo box first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  IsCpp := SameText(ExtractFileExt(FActiveProjectFile), '.cbproj');

  if ApplyDebugTraceOptionsToProject(Proj, ConfigName) then
  begin
    if IsCpp then
    begin
      LogMsg(Format('Applied C++ Debug Trace to %s [%s]: BCC no-opt + line numbers, ILINK FullDebugInfo.',
        [ExtractFileName(FActiveProjectFile), ConfigName]));
      MessageDlg(
        'C++ Debug Trace Options applied to "' + ConfigName + '".' + sLineBreak + sLineBreak +
        'Save the .cbproj if asked, then Clean + Build.' + sLineBreak + sLineBreak +
        'Sets: C++ debug line numbers / stack frames, ILINK Full Debug Information,' + sLineBreak +
        'and Linker Map file type = DetailedSegments (-s).' + sLineBreak + sLineBreak +
        'Verify: Project → Options → C++ Linker → Output → Map file type = Detailed segment map.' + sLineBreak +
        'After rebuild, Win32\Debug\*.map should be large (not ~200 bytes).' + sLineBreak + sLineBreak +
        'Note: DUnit StackTrace() stays empty in stock dunitrtl without JCL/madExcept.' + sLineBreak +
        'With DetailedSegments .map, the C++ adapter resolves AddressInfo to Class::Method (ASLR-safe).',
        mtInformation, [mbOK], 0);
    end
    else
    begin
      LogMsg(Format('Applied Debug Trace Mode to %s [%s]: Optimization=False, DebugInfo=Full, UseDebugDCUs=True, MapFile=Detailed.',
        [ExtractFileName(FActiveProjectFile), ConfigName]));
      LogMsg('Save the project if prompted, then rebuild. For coverage: ⋯ → Collect Code Coverage on Run → Run All.');
      MessageDlg(
        'Debug Trace Options applied to configuration "' + ConfigName + '".' + sLineBreak + sLineBreak +
        'Save the .dproj if the IDE asks, then rebuild.' + sLineBreak + sLineBreak +
        'Stack traces: Run All as usual.' + sLineBreak +
        'Code coverage: ⋯ Actions → enable "Collect Code Coverage on Run", then Run All.',
        mtInformation, [mbOK], 0);
    end;
  end
  else
  begin
    LogMsg('Apply Debug Trace Options failed: could not access project build configuration.');
    MessageDlg('Could not update project options. Set Debug Trace Mode manually (see Test Inspector hint).',
      mtWarning, [mbOK], 0);
  end;
end;

procedure TFormDextTestRunner.ExportMenuClick(Sender: TObject);
var
  DefaultExtension: string;
  ExportFormat: string;
  Filter: string;
  SaveDialog: TSaveDialog;
  Item: TMenuItem;
begin
  if not (Sender is TMenuItem) then Exit;
  Item := TMenuItem(Sender);

  // Match by menu object — Caption string breaks if accelerators/localization change.
  if Item = ExportToJUnitXmlMenutem then
  begin
    ExportFormat := 'junit';
    DefaultExtension := 'xml';
    Filter := 'XML Files (*.xml)|*.xml';
  end
  else if Item = ExportToXUnitXMLMenutem then
  begin
    ExportFormat := 'xunit';
    DefaultExtension := 'xml';
    Filter := 'XML Files (*.xml)|*.xml';
  end
  else if Item = ExportToJsonMenutem then
  begin
    ExportFormat := 'json';
    DefaultExtension := 'json';
    Filter := 'JSON Files (*.json)|*.json';
  end
  else if Item = ExportToSonarQubeXmlMenutem then
  begin
    ExportFormat := 'sonar';
    DefaultExtension := 'xml';
    Filter := 'XML Files (*.xml)|*.xml';
  end
  else if Item = ExportToHtmlReportMenuItem then
  begin
    ExportFormat := 'html';
    DefaultExtension := 'html';
    Filter := 'HTML Files (*.html)|*.html';
  end
  else
    Exit;

  SaveDialog := TSaveDialog.Create(nil);
  try
    SaveDialog.DefaultExt := DefaultExtension;
    SaveDialog.Filter := Filter;
    SaveDialog.Title := 'Export Test Report';
    if SaveDialog.Execute then
    begin
      ExportResults(ExportFormat, SaveDialog.FileName);
    end;
  finally
    SaveDialog.Free;
  end;
end;

procedure TFormDextTestRunner.ExportResults(const ExportFormat, FileName: string);
var
  HTMLReporter: THTMLReporter;
  JsonReporter: TJsonReporter;
  JUnitReporter: TJUnitReporter;
  Key: string;
  Parts: TArray<string>;
  SonarReporter: TSonarQubeReporter;
  ResolvedPath: string;
  SuiteName: string;
  TestDetailInfo: TTestDetailInfo;
  TestInfo: Dext.Testing.Integration.TTestInfo;
  XUnitReporter: TXUnitReporter;
begin
  SuiteName := ExtractFileName(ChangeFileExt(FActiveProjectFile, ''));
  if SuiteName = '' then SuiteName := 'DextTests';

  if SameText(ExportFormat, 'junit') then
  begin
    JUnitReporter := TJUnitReporter.Create;
    try
      JUnitReporter.BeginSuite(SuiteName);
      for Key in FTestDetails.Keys do
      begin
        TestDetailInfo := FTestDetails[Key];
        FillChar(TestInfo, SizeOf(TestInfo), 0);
        Parts := TestDetailInfo.TestName.Split(['.']);
        if Length(Parts) >= 2 then
        begin
          TestInfo.FixtureName := Parts[0];
          TestInfo.TestName := Parts[1];
        end
        else
        begin
          TestInfo.FixtureName := 'Default';
          TestInfo.TestName := TestDetailInfo.TestName;
        end;
        TestInfo.DisplayName := TestDetailInfo.TestName;
        if SameText(TestDetailInfo.Status, 'Passed') then TestInfo.Result := TTestResult.trPassed
        else if SameText(TestDetailInfo.Status, 'Failed') or SameText(TestDetailInfo.Status, 'Error') then TestInfo.Result := TTestResult.trFailed
        else if SameText(TestDetailInfo.Status, 'Skipped') then TestInfo.Result := TTestResult.trSkipped
        else TestInfo.Result := TTestResult.trNone;
        TestInfo.Duration := TTimeSpan.FromMilliseconds(TestDetailInfo.DurationMs);
        TestInfo.ErrorMessage := TestDetailInfo.ErrorMessage;
        TestInfo.StackTrace := TestDetailInfo.StackTrace;
        JUnitReporter.AddTestCase(TestInfo);
      end;
      JUnitReporter.EndSuite;
      JUnitReporter.SaveToFile(FileName);
      LogMsg('Results exported to JUnit format: ' + FileName);
    finally
      JUnitReporter.Free;
    end;
  end
  else if SameText(ExportFormat, 'xunit') then
  begin
    XUnitReporter := TXUnitReporter.Create;
    try
      XUnitReporter.BeginSuite(SuiteName);
      for Key in FTestDetails.Keys do
      begin
        TestDetailInfo := FTestDetails[Key];
        FillChar(TestInfo, SizeOf(TestInfo), 0);
        Parts := TestDetailInfo.TestName.Split(['.']);
        if Length(Parts) >= 2 then
        begin
          TestInfo.FixtureName := Parts[0];
          TestInfo.TestName := Parts[1];
        end
        else
        begin
          TestInfo.FixtureName := 'Default';
          TestInfo.TestName := TestDetailInfo.TestName;
        end;
        TestInfo.DisplayName := TestDetailInfo.TestName;
        if SameText(TestDetailInfo.Status, 'Passed') then TestInfo.Result := TTestResult.trPassed
        else if SameText(TestDetailInfo.Status, 'Failed') or SameText(TestDetailInfo.Status, 'Error') then TestInfo.Result := TTestResult.trFailed
        else if SameText(TestDetailInfo.Status, 'Skipped') then TestInfo.Result := TTestResult.trSkipped
        else TestInfo.Result := TTestResult.trNone;
        TestInfo.Duration := TTimeSpan.FromMilliseconds(TestDetailInfo.DurationMs);
        TestInfo.ErrorMessage := TestDetailInfo.ErrorMessage;
        TestInfo.StackTrace := TestDetailInfo.StackTrace;
        XUnitReporter.AddTestCase(TestInfo);
      end;
      XUnitReporter.EndSuite;
      XUnitReporter.SaveToFile(FileName);
      LogMsg('Results exported to XUnit format: ' + FileName);
    finally
      XUnitReporter.Free;
    end;
  end;
  if SameText(ExportFormat, 'json') then
  begin
    JsonReporter := TJsonReporter.Create;
    try
      JsonReporter.BeginSuite(SuiteName);
      for Key in FTestDetails.Keys do
      begin
        TestDetailInfo := FTestDetails[Key];
        FillChar(TestInfo, SizeOf(TestInfo), 0);
        Parts := TestDetailInfo.TestName.Split(['.']);
        if Length(Parts) >= 2 then
        begin
          TestInfo.FixtureName := Parts[0];
          TestInfo.TestName := Parts[1];
        end
        else
        begin
          TestInfo.FixtureName := 'Default';
          TestInfo.TestName := TestDetailInfo.TestName;
        end;
        TestInfo.DisplayName := TestDetailInfo.TestName;
        if SameText(TestDetailInfo.Status, 'Passed') then TestInfo.Result := TTestResult.trPassed
        else if SameText(TestDetailInfo.Status, 'Failed') or SameText(TestDetailInfo.Status, 'Error') then TestInfo.Result := TTestResult.trFailed
        else if SameText(TestDetailInfo.Status, 'Skipped') then TestInfo.Result := TTestResult.trSkipped
        else TestInfo.Result := TTestResult.trNone;
        TestInfo.Duration := TTimeSpan.FromMilliseconds(TestDetailInfo.DurationMs);
        TestInfo.ErrorMessage := TestDetailInfo.ErrorMessage;
        TestInfo.StackTrace := TestDetailInfo.StackTrace;
        JsonReporter.AddTestCase(TestInfo);
      end;
      JsonReporter.EndSuite;
      JsonReporter.SaveToFile(FileName);
      LogMsg('Results exported to JSON format: ' + FileName);
    finally
      JsonReporter.Free;
    end;
  end
  else if SameText(ExportFormat, 'sonar') then
  begin
    SonarReporter := TSonarQubeReporter.Create;
    try
      for Key in FTestDetails.Keys do
      begin
        TestDetailInfo := FTestDetails[Key];
        FillChar(TestInfo, SizeOf(TestInfo), 0);
        Parts := TestDetailInfo.TestName.Split(['.']);
        if Length(Parts) >= 2 then
        begin
          TestInfo.FixtureName := Parts[0];
          TestInfo.TestName := Parts[1];
        end
        else
        begin
          TestInfo.FixtureName := 'Default';
          TestInfo.TestName := TestDetailInfo.TestName;
        end;
        TestInfo.DisplayName := TestDetailInfo.TestName;
        TestInfo.UnitName := TestDetailInfo.FileName;
        if (TestInfo.UnitName <> '') and not TPath.IsPathRooted(TestInfo.UnitName) then
        begin
          ResolvedPath := FindUnitFileByName(TestInfo.UnitName);
          if ResolvedPath <> '' then
            TestInfo.UnitName := ResolvedPath;
        end;
        if SameText(TestDetailInfo.Status, 'Passed') then TestInfo.Result := trPassed
        else if SameText(TestDetailInfo.Status, 'Failed') or SameText(TestDetailInfo.Status, 'Error') then TestInfo.Result := trFailed
        else if SameText(TestDetailInfo.Status, 'Skipped') then TestInfo.Result := trSkipped
        else TestInfo.Result := trNone;
        TestInfo.Duration := TTimeSpan.FromMilliseconds(TestDetailInfo.DurationMs);
        TestInfo.ErrorMessage := TestDetailInfo.ErrorMessage;
        TestInfo.StackTrace := TestDetailInfo.StackTrace;
        SonarReporter.AddTestCase(TestInfo);
      end;
      SonarReporter.SaveToFile(FileName);
      LogMsg('Results exported to SonarQube format: ' + FileName);
    finally
      SonarReporter.Free;
    end;
  end
  else if SameText(ExportFormat, 'html') then
  begin
    HTMLReporter := THTMLReporter.Create;
    try
      HTMLReporter.SetTitle(SuiteName);
      HTMLReporter.BeginSuite(SuiteName);
      for Key in FTestDetails.Keys do
      begin
        TestDetailInfo := FTestDetails[Key];
        FillChar(TestInfo, SizeOf(TestInfo), 0);
        Parts := TestDetailInfo.TestName.Split(['.']);
        if Length(Parts) >= 2 then
        begin
          TestInfo.FixtureName := Parts[0];
          TestInfo.TestName := Parts[1];
        end
        else
        begin
          TestInfo.FixtureName := 'Default';
          TestInfo.TestName := TestDetailInfo.TestName;
        end;
        TestInfo.DisplayName := TestDetailInfo.TestName;
        if SameText(TestDetailInfo.Status, 'Passed') then TestInfo.Result := TTestResult.trPassed
        else if SameText(TestDetailInfo.Status, 'Failed') or SameText(TestDetailInfo.Status, 'Error') then TestInfo.Result := TTestResult.trFailed
        else if SameText(TestDetailInfo.Status, 'Skipped') then TestInfo.Result := TTestResult.trSkipped
        else TestInfo.Result := TTestResult.trNone;
        TestInfo.Duration := TTimeSpan.FromMilliseconds(TestDetailInfo.DurationMs);
        TestInfo.ErrorMessage := TestDetailInfo.ErrorMessage;
        TestInfo.StackTrace := TestDetailInfo.StackTrace;
        HTMLReporter.AddTestCase(TestInfo);
      end;
      HTMLReporter.EndSuite;
      HTMLReporter.SaveToFile(FileName);
      LogMsg('Results exported to HTML format: ' + FileName);
    finally
      HTMLReporter.Free;
    end;
  end;
end;

procedure TFormDextTestRunner.IdleTimerTimer(Sender: TObject);
begin
  FIdleTimer.Enabled := False;
  if FEnabled and RunOnIdleCheckBox.Checked and (FActiveProjectFile <> '') then
  begin
    LogMsg('Idle auto-run triggered.');
    RunActiveProjectTests;
  end;
end;

procedure TFormDextTestRunner.ConfigChangeHandler(Sender: TObject);
var
  Ini: TMemIniFile;
begin
  Ini := TMemIniFile.Create(TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini'));
  try
    Ini.WriteString('General', 'CustomParams', CustomParamsEdit.Text);
    Ini.WriteBool('General', 'RunOnSave', RunOnSaveCheckBox.Checked);
    Ini.WriteBool('General', 'RunOnIdle', RunOnIdleCheckBox.Checked);
    if Assigned(FCoverageCheckBox) then
      Ini.WriteBool('Coverage', 'Enabled', FCoverageCheckBox.Checked and FCoverageCheckBox.Enabled);
    if Assigned(FGenerateHtmlCheckBox) then
      Ini.WriteBool('Coverage', 'GenerateHtml', FGenerateHtmlCheckBox.Checked);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;

  if Assigned(FCollectCoverageMenuItem) and Assigned(FCoverageCheckBox) then
    FCollectCoverageMenuItem.Checked := FCoverageCheckBox.Checked and FCoverageCheckBox.Enabled;
  if Assigned(FGenerateHtmlMenuItem) and Assigned(FGenerateHtmlCheckBox) then
    FGenerateHtmlMenuItem.Checked := FGenerateHtmlCheckBox.Checked;

  UpdateCoverageUiState;

  if Assigned(FIdleTimer) then
    FIdleTimer.Enabled := RunOnIdleCheckBox.Checked;
end;

function ReadProjectOutDirTag(const AGroup, ATagOpen, ATagClose: string): string;
var
  OutStart, OutEnd: Integer;
begin
  Result := '';
  OutStart := AGroup.IndexOf(ATagOpen);
  if OutStart < 0 then
    Exit;
  Inc(OutStart, Length(ATagOpen));
  OutEnd := AGroup.IndexOf(ATagClose, OutStart);
  if OutEnd > OutStart then
    Result := AGroup.Substring(OutStart, OutEnd - OutStart).Trim;
end;

function ReadProjectOutDirFromGroup(const AGroup: string; APreferCpp: Boolean): string;
begin
  if APreferCpp then
  begin
    Result := ReadProjectOutDirTag(AGroup, '<FinalOutputDir>', '</FinalOutputDir>');
    if Result = '' then
      Result := ReadProjectOutDirTag(AGroup, '<DCC_ExeOutput>', '</DCC_ExeOutput>');
  end
  else
  begin
    Result := ReadProjectOutDirTag(AGroup, '<DCC_ExeOutput>', '</DCC_ExeOutput>');
    if Result = '' then
      Result := ReadProjectOutDirTag(AGroup, '<FinalOutputDir>', '</FinalOutputDir>');
  end;
end;

function GetProjectTargetInfo(const ADprojPath: string; out AIsPackage: Boolean; out AExeOutput: string; const APlatform: string = 'Win32'; const AConfig: string = 'Debug'): Boolean;
var
  BaseGroup: string;
  BaseGroupStart, BaseGroupEnd: Integer;
  Content: string;
  IsCpp: Boolean;
  MainSource: string;
  MainSourceStart, MainSourceEnd: Integer;
  PlatformGroup: string;
  PlatformGroupStart, PlatformGroupEnd: Integer;
  PlatformTag: string;
begin
  Result := False;
  AIsPackage := False;
  AExeOutput := '';
  if not FileExists(ADprojPath) then Exit;
  IsCpp := SameText(ExtractFileExt(ADprojPath), '.cbproj');

  try
    Content := TFile.ReadAllText(ADprojPath);

    // Check MainSource
    MainSourceStart := Content.IndexOf('<MainSource>');
    if MainSourceStart >= 0 then
    begin
      Inc(MainSourceStart, Length('<MainSource>'));
      MainSourceEnd := Content.IndexOf('</MainSource>', MainSourceStart);
      if MainSourceEnd > MainSourceStart then
      begin
        MainSource := Content.Substring(MainSourceStart, MainSourceEnd - MainSourceStart).Trim;
        if MainSource.EndsWith('.dpk', True) then
          AIsPackage := True;
      end;
    end;

    // Check ProjectType
    if not AIsPackage then
    begin
      if Content.Contains('<Borland.ProjectType>Package</Borland.ProjectType>') then
        AIsPackage := True;
    end;

    // 1. Try platform-specific base property group, e.g., Base_Win32
    PlatformTag := 'Base_' + APlatform;
    PlatformGroupStart := Content.IndexOf('Condition="''$(' + PlatformTag + ')''!=''''"');
    if PlatformGroupStart < 0 then
      PlatformGroupStart := Content.IndexOf('Condition="''$(Platform)''==''' + APlatform + '''"');

    if PlatformGroupStart >= 0 then
    begin
      PlatformGroupStart := Content.LastIndexOf('<PropertyGroup', PlatformGroupStart);
      if PlatformGroupStart >= 0 then
      begin
        PlatformGroupEnd := Content.IndexOf('</PropertyGroup>', PlatformGroupStart);
        if PlatformGroupEnd > PlatformGroupStart then
        begin
          PlatformGroup := Content.Substring(PlatformGroupStart, PlatformGroupEnd - PlatformGroupStart);
          AExeOutput := ReadProjectOutDirFromGroup(PlatformGroup, IsCpp);
        end;
      end;
    end;

    // 2. Try base configurations
    if AExeOutput = '' then
    begin
      BaseGroupStart := Content.IndexOf('Condition="''$(Base)''!=''''"');
      if BaseGroupStart >= 0 then
      begin
        BaseGroupStart := Content.LastIndexOf('<PropertyGroup', BaseGroupStart);
        if BaseGroupStart >= 0 then
        begin
          BaseGroupEnd := Content.IndexOf('</PropertyGroup>', BaseGroupStart);
          if BaseGroupEnd > BaseGroupStart then
          begin
            BaseGroup := Content.Substring(BaseGroupStart, BaseGroupEnd - BaseGroupStart);
            AExeOutput := ReadProjectOutDirFromGroup(BaseGroup, IsCpp);
          end;
        end;
      end;
    end;

    // 3. Fallback tags anywhere
    if AExeOutput = '' then
    begin
      if IsCpp then
      begin
        AExeOutput := ReadProjectOutDirTag(Content, '<FinalOutputDir>', '</FinalOutputDir>');
        if AExeOutput = '' then
          AExeOutput := ReadProjectOutDirTag(Content, '<DCC_ExeOutput>', '</DCC_ExeOutput>');
      end
      else
      begin
        AExeOutput := ReadProjectOutDirTag(Content, '<DCC_ExeOutput>', '</DCC_ExeOutput>');
        if AExeOutput = '' then
          AExeOutput := ReadProjectOutDirTag(Content, '<FinalOutputDir>', '</FinalOutputDir>');
      end;
    end;

    Result := True;
  except
    // ignore
  end;
end;

function ResolveExePath(const ADprojPath, AExeOutput: string; const APlatform: string = 'Win32'; const AConfig: string = 'Debug'): string;
var
  ProjectDir: string;
  OutputDir: string;
  ProjectName: string;
begin
  ProjectDir := ExtractFilePath(ADprojPath);
  ProjectName := ChangeFileExt(ExtractFileName(ADprojPath), '');

  if AExeOutput <> '' then
  begin
    OutputDir := AExeOutput.Replace('$(Platform)', APlatform).Replace('$(Config)', AConfig);
    if TPath.IsRelativePath(OutputDir) then
      OutputDir := TPath.GetFullPath(TPath.Combine(ProjectDir, OutputDir))
    else
      OutputDir := OutputDir;
  end
  else
  begin
    OutputDir := TPath.Combine(ProjectDir, TPath.Combine(APlatform, AConfig));
  end;

  Result := TPath.Combine(OutputDir, ProjectName + '.exe');
end;

procedure TFormDextTestRunner.RefreshProjects;
var
  FoundIndex: Integer;
  Group: IOTAProjectGroup;
  i: Integer;
  IsPackage: Boolean;
  ModuleServices: IOTAModuleServices;
  Output: string;
  PrevSelectedFile: string;
  Proj: IOTAProject;
  ProjFile: string;
  ProjInfo: TDextProjectInfo;
begin
  if not ExplorerSurfaceReady then
  begin
    FRefreshWhenShown := True;
    LogExplorerSurface('RefreshProjects skipped');
    Exit;
  end;
  LogExplorerSurface('RefreshProjects begin');
  PrevSelectedFile := FActiveProjectFile;

  // Clear existing items and free their TDextProjectInfo objects
  for i := 0 to ProjectsComboBox.Items.Count - 1 do
    ProjectsComboBox.Items.Objects[i].Free;
  ProjectsComboBox.Items.Clear;

  if not Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    Exit;

  Group := ModuleServices.MainProjectGroup;
  if Assigned(Group) then
  begin
    for i := 0 to Group.ProjectCount - 1 do
    begin
      Proj := Group.Projects[i];
      if Assigned(Proj) then
      begin
        ProjFile := Proj.FileName;
        if IsLikelyTestProjectFile(ProjFile) and IsSupportedProjectPersonality(Proj) then
        begin
          IsPackage := False;
          Output := '';
          // Package check is Delphi-oriented; skip for .cbproj
          if SameText(ExtractFileExt(ProjFile), '.dproj') and
             GetProjectTargetInfo(ProjFile, IsPackage, Output) and IsPackage then
            Continue;

          ProjectsComboBox.Items.AddObject(ExtractFileName(ProjFile), TDextProjectInfo.Create(ProjFile));
        end;
      end;
    end;
  end;

  FoundIndex := -1;
  if PrevSelectedFile <> '' then
  begin
    for i := 0 to ProjectsComboBox.Items.Count - 1 do
    begin
      ProjInfo := TDextProjectInfo(ProjectsComboBox.Items.Objects[i]);
      if Assigned(ProjInfo) and SameText(ProjInfo.FileName, PrevSelectedFile) then
      begin
        FoundIndex := i;
        Break;
      end;
    end;
  end;

  if FoundIndex <> -1 then
  begin
    ProjectsComboBox.ItemIndex := FoundIndex;
    ProjectsComboBoxChange(ProjectsComboBox);
  end
  else if ProjectsComboBox.Items.Count > 0 then
  begin
    ProjectsComboBox.ItemIndex := 0;
    ProjectsComboBoxChange(ProjectsComboBox);
  end
  else
  begin
    ProjectsComboBox.ItemIndex := -1;
    FActiveProjectFile := '';
    if FActiveSession <> nil then
      FActiveSession.ActiveProjectFile := '';
    TestsTreeView.Items.Clear;
    FTestLocations.Clear;
    ResetSummaryLabels;
  end;
end;

procedure TFormDextTestRunner.ProjectsComboBoxChange(Sender: TObject);
var
  Proj: IOTAProject;
  ProjInfo: TDextProjectInfo;
begin
  UpdateSummaryCounts;
  if ProjectsComboBox.ItemIndex = -1 then Exit;

  ProjInfo := TDextProjectInfo(ProjectsComboBox.Items.Objects[ProjectsComboBox.ItemIndex]);
  if not Assigned(ProjInfo) then Exit;

  Proj := GetProjectByFileName(ProjInfo.FileName);
  if not Assigned(Proj) then Exit;

  FActiveProjectFile := Proj.FileName;
  if FActiveSession <> nil then
    FActiveSession.ActiveProjectFile := FActiveProjectFile;
  ApplyCoverageForActivePlatform;

  // Unregister old project notifier
  if (FActiveProjectNotifierIndex <> -1) and Assigned(FActiveProjectForNotifier) then
  begin
    try
      FActiveProjectForNotifier.RemoveNotifier(FActiveProjectNotifierIndex);
    except
      // ignore in case project was already destroyed
    end;
    FActiveProjectNotifierIndex := -1;
    FActiveProjectForNotifier := nil;
  end;

  { Defer project AddNotifier + AST refresh — sync AddNotifier during .cbproj select
    can race C++ MainSource editor open. }
  FIgnoreSaveUntil := Now + (2 / SecsPerDay);
  if Assigned(FPendingSaveFiles) then
    FPendingSaveFiles.Clear;
  if Assigned(FSaveTimer) then
    FSaveTimer.Enabled := False;

  FActiveProjectForNotifier := Proj;
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    var
      P: IOTAProject;
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if (FormDextTestRunner = nil) or (csDestroying in FormDextTestRunner.ComponentState) then
        Exit;
      if not IsDextTestExplorerEnabled then
        Exit;
      P := FormDextTestRunner.FActiveProjectForNotifier;
      if P = nil then
        Exit;
      try
        FormDextTestRunner.FActiveProjectNotifierIndex :=
          P.AddNotifier(TDextProjectNotifier.Create(FormDextTestRunner, P.FileName));
      except
        FormDextTestRunner.FActiveProjectNotifierIndex := -1;
        FormDextTestRunner.FActiveProjectForNotifier := nil;
      end;

      FormDextTestRunner.FLastCoverageReportDir := '';
      FormDextTestRunner.FLastCoverageSourceRoot := '';
      FormDextTestRunner.FCoverageWrapActive := False;
      FormDextTestRunner.FCppLlvmCoverage := False;
      TCoverageManager.GetInstance.Clear;
      if Assigned(FormDextTestRunner.FCoverageListView) then
        FormDextTestRunner.FCoverageListView.Items.Clear;
      FormDextTestRunner.ClearCoverageProblemStyle;
      if Assigned(FormDextTestRunner.FCoverageSummaryLabel) then
        FormDextTestRunner.FCoverageSummaryLabel.Caption :=
          'Coverage for current project (none loaded yet).';
      if Assigned(FormDextTestRunner.FCoverageTab) then
        FormDextTestRunner.FCoverageTab.Caption := 'Coverage';
      FormDextTestRunner.TryLoadCoverage(False);
      FormDextTestRunner.ApplyCoverageForActivePlatform;
      FormDextTestRunner.RefreshActiveProjectTestsList;
    end));
end;

function TFormDextTestRunner.FindNodeByPath(const APath: string): TTreeNode;
var
  i, j: Integer;
  Node: TTreeNode;
  Split: TArray<string>;

  function GetNodeClassName(const ANodeText: string): string;
  var
    Pos: Integer;
  begin
    Pos := ANodeText.IndexOf(' (');
    if Pos > 0 then
      Result := ANodeText.Substring(0, Pos)
    else
      Result := ANodeText;
  end;
begin
  Result := nil;

  if FGroupingMode = tgmStatus then
  begin
    // In status mode, child nodes are named exactly 'ClassName.MethodName'. Root nodes are 'Failed', 'Passed', 'Skipped', 'Idle'.
    for i := 0 to TestsTreeView.Items.Count - 1 do
    begin
      Node := TestsTreeView.Items[i];
      if (Node.Parent <> nil) and SameText(Node.Text, APath) then
      begin
        Result := Node;
        Exit;
      end;
    end;

    // If not found, check if searching for a status category node itself
    for i := 0 to TestsTreeView.Items.Count - 1 do
    begin
      Node := TestsTreeView.Items[i];
      if (Node.Parent = nil) and SameText(Node.Text, APath) then
      begin
        Result := Node;
        Exit;
      end;
    end;

    Exit;
  end;

  // If APath contains a dot, try to find the child node via ClassName.MethodName
  if APath.Contains('.') then
  begin
    Split := APath.Split(['.'], 2);
    if Length(Split) = 2 then
    begin
      for i := 0 to TestsTreeView.Items.Count - 1 do
      begin
        Node := TestsTreeView.Items[i];
        if (Node.Parent = nil) and SameText(GetNodeClassName(Node.Text), Split[0]) then
        begin
          for j := 0 to Node.Count - 1 do
          begin
            if SameText(Node.Item[j].Text, Split[1]) then
            begin
              Result := Node.Item[j];
              Exit;
            end;
          end;
        end;
      end;
    end;
  end;

  // Fallback: search all nodes by ClassName prefix
  for i := 0 to TestsTreeView.Items.Count - 1 do
  begin
    Node := TestsTreeView.Items[i];
    if (Node.Parent = nil) and SameText(GetNodeClassName(Node.Text), APath) then
    begin
      Result := Node;
      Exit;
    end;
  end;
end;

procedure TFormDextTestRunner.ClearNodeIndex;
begin
  if Assigned(FNodeByName) then
    FNodeByName.Clear;
end;

procedure TFormDextTestRunner.BuildNodeIndex;
var
  Node: TTreeNode;
  Key: string;
begin
  ClearNodeIndex;
  if (TestsTreeView = nil) or (FNodeByName = nil) then
    Exit;
  Node := TestsTreeView.Items.GetFirstNode;
  while Assigned(Node) do
  begin
    if Node.Parent <> nil then
    begin
      Key := GetNodeFullTestName(Node);
      if Key <> '' then
        FNodeByName.AddOrSetValue(Key, Node);
    end;
    Node := Node.GetNext;
  end;
end;

procedure TFormDextTestRunner.SyncProgressAndSummaryLabels;
begin
  SummarySuccessLabel.Caption := 'Passed: ' + FPassedCount.ToString;
  SummaryFailedLabel.Caption := 'Failed: ' + FFailedCount.ToString;
  SummarySkippedLabel.Caption := 'Skipped: ' + FSkippedCount.ToString;
  UpdateTotalTimeLabel;
  if Assigned(ProgressPanel) and ProgressPanel.Visible then
  begin
    if ProgressBar.Style = pbstMarquee then
      ProgressBar.Style := pbstNormal;
    ProgressBar.Max := Max(ProgressBar.Max, Max(1, FTotalTests));
    ProgressBar.Position := Min(FCompletedTests, ProgressBar.Max);
    ProgressLabel.Caption := Format('%d/%d', [FCompletedTests, Max(FTotalTests, FCompletedTests)]);
  end;
end;

procedure TFormDextTestRunner.ScheduleUiResultFlush;
begin
  if IsTestingDesignShuttingDown or FUiFlushScheduled then
    Exit;
  FUiFlushScheduled := True;
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
        FormDextTestRunner.FlushPendingResultsUi;
    end));
end;

procedure TFormDextTestRunner.OnTestResultReceived(const AJSONData: string);
begin
  // Cheap enqueue on the UI thread; painting is time-sliced in FlushPendingResultsUi
  // so the IDE message loop can process editor/input between bursts.
  if FPendingResultJson = nil then
    Exit;
  FPendingResultJson.Add(AJSONData);
  ScheduleUiResultFlush;
end;

procedure TFormDextTestRunner.FlushPendingResultsUi;
const
  BudgetMs = 12;
var
  Sw: TStopwatch;
  Payload: string;
begin
  if (FPendingResultJson = nil) or (FPendingResultJson.Count = 0) then
  begin
    FUiFlushScheduled := False;
    Exit;
  end;

  FBatchingUi := True;
  Sw := TStopwatch.StartNew;
  if Assigned(TestsTreeView) then
    TestsTreeView.Items.BeginUpdate;
  try
    while FPendingResultJson.Count > 0 do
    begin
      Payload := FPendingResultJson[0];
      FPendingResultJson.Delete(0);
      ProcessResultPayload(Payload);
      if Sw.ElapsedMilliseconds >= BudgetMs then
        Break;
    end;
  finally
    if Assigned(TestsTreeView) then
      TestsTreeView.Items.EndUpdate;
    FBatchingUi := False;
  end;

  SyncProgressAndSummaryLabels;
  if Assigned(TestsTreeView) then
    TestsTreeView.Invalidate;

  if FPendingResultJson.Count > 0 then
  begin
    // Yield to the IDE, then continue.
    FUiFlushScheduled := False;
    ScheduleUiResultFlush;
  end
  else
    FUiFlushScheduled := False;
end;

procedure TFormDextTestRunner.ProcessResultPayload(const AJSONData: string);
var
  i: Integer;
  JSONArray: TJSONArray;
  Value: TJSONValue;

  procedure ProcessSingleResult(ItemJson: TJSONObject);
  var
    DetailInfo: TTestDetailInfo;
    DurationMs: Double;
    ErrorObj: TJSONObject;
    Event: string;
    FullTestName: string;
    i: Integer;
    Node: TTreeNode;
    Passed, Failed, Ignored: Integer;
    TestLocation: TTestLocation;
    TestName, Status, Msg, StackTrace: string;
    Checked: TArray<string>;
    SelectedCount: Integer;
    Fixture: string;
    TempDur: Double;
    AnalyticsLines: TStringList;
    UnitName: string;
    LineNum: Integer;
  begin
    if ItemJson.TryGetValue<string>('event', Event) and SameText(Event, 'RunComplete') then
    begin
      Passed := ItemJson.GetValue<Integer>('passed');
      Failed := ItemJson.GetValue<Integer>('failed');
      Ignored := ItemJson.GetValue<Integer>('ignored');
      { C++ /tests/finished posts empty body → Server synthesizes zeros. Prefer live counters. }
      if (Passed = 0) and (Failed = 0) and (Ignored = 0) and (FCompletedTests > 0) then
      begin
        Passed := FPassedCount;
        Failed := FFailedCount;
        Ignored := FSkippedCount;
      end;
      LogMsg('');
      LogMsg('========================================');
      LogMsg(Format('Testing Completed. Passed: %d, Failed: %d, Ignored: %d', [Passed, Failed, Ignored]));
      LogMsg('========================================');

      // Stop the stopwatch
      TStopwatch(FStopwatch).Stop;
      UpdateTimingLabels;

      { Only mark Idle→Skipped when the Host sent real suite totals (not synthetic zeros). }
      if (ItemJson.GetValue<Integer>('passed') > 0) or (ItemJson.GetValue<Integer>('failed') > 0) or
         (ItemJson.GetValue<Integer>('ignored') > 0) or (FTotalTests > 0) then
      for i := 0 to FTestLocations.Count - 1 do
      begin
        TestLocation := FTestLocations[i];
        FullTestName := TestLocation.ClassName + '.' + TestLocation.MethodName;
        if FTestDetails.TryGetValue(FullTestName, DetailInfo) then
        begin
          if SameText(DetailInfo.Status, 'Idle') or (DetailInfo.Status = '') then
          begin
            DetailInfo.Status := 'Skipped';
            FTestDetails.AddOrSetValue(FullTestName, DetailInfo);
            Inc(FSkippedCount);
          end;
        end
        else
        begin
          DetailInfo.TestName := FullTestName;
          DetailInfo.Status := 'Skipped';
          DetailInfo.DurationMs := 0;
          DetailInfo.ErrorMessage := 'Not executed';
          DetailInfo.StackTrace := '';
          DetailInfo.FileName := TestLocation.FileName;
          DetailInfo.Line := TestLocation.Line;
          FTestDetails.AddOrSetValue(FullTestName, DetailInfo);
          Inc(FSkippedCount);
        end;
      end;

      // Update final labels
      SummarySuccessLabel.Caption := 'Passed: ' + FPassedCount.ToString;
      SummaryFailedLabel.Caption := 'Failed: ' + FFailedCount.ToString;
      SummarySkippedLabel.Caption := 'Skipped: ' + FSkippedCount.ToString;

      // Complete and then hide the progress panel
      if Assigned(ProgressPanel) then
      begin
        ProgressBar.Position := ProgressBar.Max;
        ProgressLabel.Caption := Format('%d/%d', [FCompletedTests, Max(FCompletedTests, FTotalTests)]);
        // Hide after a short delay so user can see 100%
        if not IsTestingDesignShuttingDown then
          TThread.ForceQueue(nil, TThreadProcedure(procedure
            begin
              if IsTestingDesignShuttingDown then
                Exit;
              if Assigned(FormDextTestRunner) and Assigned(FormDextTestRunner.ProgressPanel) and
                 not (csDestroying in FormDextTestRunner.ComponentState) then
                FormDextTestRunner.ProgressPanel.Visible := False;
            end));
      end;
      // Under CodeCoverage.exe the report is written AFTER the test process exits.
      // Keep the process handle so NotifyProcessExited can load the XML.
      if not FCoverageWrapActive then
      begin
        if FRunningProcessHandle <> 0 then
        begin
          CloseHandle(FRunningProcessHandle);
          FRunningProcessHandle := 0;
        end;
      end;
      FRunningTests := False;
      TTelemetryTracker.RecordSuiteRun(FActiveProjectFile, FPassedCount, FFailedCount,
        FSkippedCount, Max(FCompletedTests, FTotalTests), FTestExecutionDurationMs);
      AnalyticsLines := TStringList.Create;
      try
        TTelemetryTracker.AnalyzeSuiteHistory(FActiveProjectFile, AnalyticsLines);
        TTelemetryTracker.AnalyzeHistory(FActiveProjectFile, AnalyticsLines);
        LogAnalyticsLines(AnalyticsLines);
      finally
        AnalyticsLines.Free;
      end;
      CollapseSuccessAndFocusFailures;
      if FCoverageWrapActive then
        LogMsg('Coverage: waiting for CodeCoverage.exe to finish writing the report…')
      else
        TryLoadCoverage;
      Exit;
    end;

    if ItemJson.TryGetValue<string>('event', Event) and SameText(Event, 'RunStart') then
    begin
      FTotalTests := ItemJson.GetValue<Integer>('totalTests');
      FCompletedTests := 0;
      FPassedCount := 0;
      FFailedCount := 0;
      FSkippedCount := 0;
      FTestExecutionDurationMs := 0;
      InitializeGroupSummaries;

      // Ensure all test locations exist in FTestDetails as Idle
      for i := 0 to FTestLocations.Count - 1 do
      begin
        TestLocation := FTestLocations[i];
        FullTestName := TestLocation.ClassName + '.' + TestLocation.MethodName;
        DetailInfo.TestName := FullTestName;
        DetailInfo.Status := 'Idle';
        DetailInfo.DurationMs := 0;
        DetailInfo.ErrorMessage := '';
        DetailInfo.StackTrace := '';
        DetailInfo.FileName := TestLocation.FileName;
        DetailInfo.Line := TestLocation.Line;
        FTestDetails.AddOrSetValue(FullTestName, DetailInfo);
      end;

      if Assigned(ProgressPanel) then
      begin
        ProgressBar.Max := Max(1, FTotalTests);
        ProgressBar.Position := 0;
        ProgressLabel.Caption := Format('0/%d', [FTotalTests]);
        ProgressPanel.Visible := True;
      end;

      // Update summary counts
      Checked := GetCheckedTests;
      SelectedCount := Length(Checked);
      if SelectedCount = 0 then
        SelectedCount := FTestLocations.Count;
      SummarySelectedLabel.Caption := 'Selected: ' + SelectedCount.ToString;
      SummaryTotalLabel.Caption := 'Total: ' + FTestLocations.Count.ToString;
      SummarySuccessLabel.Caption := 'Passed: 0';
      SummaryFailedLabel.Caption := 'Failed: 0';
      SummarySkippedLabel.Caption := 'Skipped: 0';
      UpdateTotalTimeLabel;

      BuildNodeIndex;
      if FGroupingMode = tgmStatus then
        RefreshTreeView;
      Exit;
    end;

    // Detect if this is a standard result
    TestName := '';
    Status := '';
    Msg := '';
    StackTrace := '';
    DurationMs := 0;
    UnitName := '';
    LineNum := 0;
    ItemJson.TryGetValue<string>('unitname', UnitName);
    if not ItemJson.TryGetValue<Integer>('linenumber', LineNum) then
    begin
      TempDur := 0;
      if ItemJson.TryGetValue<Double>('linenumber', TempDur) then
        LineNum := Trunc(TempDur);
    end;

    if ItemJson.TryGetValue<string>('testName', TestName) then
    begin
      // Standard Dext result format
      ItemJson.TryGetValue<string>('status', Status);
      ItemJson.TryGetValue<Double>('durationMs', DurationMs);
      if ItemJson.TryGetValue<TJSONObject>('error', ErrorObj) and Assigned(ErrorObj) then
      begin
        Msg := ErrorObj.GetValue<string>('message');
        StackTrace := ExtractStackTraceFromErrorJson(ErrorObj);
      end;
    end
    else if ItemJson.TryGetValue<string>('testname', TestName) then
    begin
      // External tests compatibility result format
      ItemJson.TryGetValue<string>('resulttype', Status);

      // Map external tests status to Dext status standard values
      if SameText(Status, 'Passed') then Status := 'Passed'
      else if SameText(Status, 'Failed') then Status := 'Failed'
      else if SameText(Status, 'Error') then Status := 'Error'
      else if SameText(Status, 'Skipped') then Status := 'Skipped'
      else if SameText(Status, 'Idle') then Status := 'Idle'
      else if SameText(Status, 'Running') then Status := 'Running';

      Fixture := '';
      if ItemJson.TryGetValue<string>('fixturename', Fixture) and (Fixture <> '') then
      begin
        TestName := Fixture + '.' + TestName;
      end;

      TempDur := 0;
      if ItemJson.TryGetValue<Double>('duration', TempDur) then
        DurationMs := TempDur;

      ItemJson.TryGetValue<string>('exceptionmessage', Msg);
      if not ItemJson.TryGetValue<string>('stacktrace', StackTrace) then
        StackTrace := '';
    end;

    if TestName = '' then
    begin
      LogMsg('[Host] ignored result payload (no testname): ' + ItemJson.ToString);
      Exit;
    end;

    { DUnit registry root is often Project.exe — never a real test. }
    if IsLikelyBinaryTestName(TestName) then
    begin
      LogToFile('[Host] ignored binary-like test name: ' + TestName);
      Exit;
    end;

    if SameText(Status, 'Idle') then
      LogToFile('[Host] Idle ' + TestName)
    else
      LogMsg(Format('[Host] %s %s (%.0f ms)', [Status, TestName, DurationMs]));

    if not SameText(Status, 'Running') and not SameText(Status, 'Idle') then
    begin
      Inc(FCompletedTests);
      if SameText(Status, 'Passed') then
        Inc(FPassedCount)
      else if SameText(Status, 'Failed') or SameText(Status, 'Error') then
        Inc(FFailedCount)
      else if SameText(Status, 'Skipped') then
        Inc(FSkippedCount);

      FTestExecutionDurationMs := FTestExecutionDurationMs + DurationMs;
      // Caption/progress updates happen once per UI flush slice (SyncProgressAndSummaryLabels).
    end;

    // Failures/errors always hit the console with detail.
    if SameText(Status, 'Failed') or SameText(Status, 'Error') then
    begin
      LogMsg('FAILED: ' + TestName);
      if Msg <> '' then
        LogMsg('Error: ' + Msg);
      if StackTrace <> '' then
      begin
        LogMsg('Stack Trace:');
        LogMsg(StackTrace);
      end;
      LogMsg('----------------------------------------');
    end
    else if SameText(Status, 'Skipped') then
      LogMsg('SKIPPED: ' + TestName);

    if not SameText(Status, 'Idle') and not SameText(Status, 'Running') then
      TTelemetryTracker.RecordTestResult(FActiveProjectFile, TestName, Status, Round(DurationMs));
    if not SameText(Status, 'Idle') then
      UpdateNodeResultCache(TestName, Status, DurationMs);

    UpdateTestNode(TestName, Status, Msg, StackTrace);

    // Cache test details
    DetailInfo.TestName := TestName;
    DetailInfo.Status := Status;
    DetailInfo.DurationMs := DurationMs;
    DetailInfo.ErrorMessage := Msg;
    DetailInfo.StackTrace := StackTrace;

    Node := nil;
    if (FNodeByName = nil) or not FNodeByName.TryGetValue(TestName, Node) then
      Node := FindNodeByPath(TestName);
    if Assigned(Node) and (Node.Data <> nil) then
    begin
      i := Integer(Node.Data) - 1;
      if (i >= 0) and (i < FTestLocations.Count) then
      begin
        { Host unitname/linenumber — fill empty; on Failed refresh assert line. }
        TestLocation := FTestLocations[i];
        if (UnitName <> '') and
           ((TestLocation.FileName = '') or SameText(Status, 'Failed') or SameText(Status, 'Error')) then
          TestLocation.FileName := UnitName;
        if (LineNum > 0) and
           ((TestLocation.Line <= 0) or SameText(Status, 'Failed') or SameText(Status, 'Error')) then
          TestLocation.Line := LineNum;
        FTestLocations[i] := TestLocation;
        DetailInfo.FileName := TestLocation.FileName;
        DetailInfo.Line := TestLocation.Line;
      end;
    end;

    FTestDetails.AddOrSetValue(TestName, DetailInfo);

    // Inspector refresh is expensive — skip while batching; user selection still works via Change.
    if (not FBatchingUi) and (TestsTreeView.Selected <> nil) and
       (SameText(TestsTreeView.Selected.Text, TestName) or
        SameText(GetNodeFullTestName(TestsTreeView.Selected), TestName)) then
    begin
      UpdateTestInspector(TestName);
    end;
  end;

begin
  LogToFile('[HostPayload] ' + AJSONData);

  Value := TJSONObject.ParseJSONValue(AJSONData);
  if not Assigned(Value) then
  begin
    LogMsg('[Host] JSON parse failed: ' + Copy(AJSONData, 1, 200));
    Exit;
  end;

  try
    if Value is TJSONArray then
    begin
      JSONArray := TJSONArray(Value);
      for i := 0 to JsonArray.Count - 1 do
      begin
        if JSONArray.Items[i] is TJSONObject then
          ProcessSingleResult(TJSONObject(JSONArray.Items[i]));
      end;
    end
    else if Value is TJSONObject then
    begin
      ProcessSingleResult(TJSONObject(Value));
    end;
  finally
    Value.Free;
  end;
end;

procedure TFormDextTestRunner.CollapseSuccessAndFocusFailures;
var
  Child: TTreeNode;
  FirstFailedNode: TTreeNode;
  HasFailures: Boolean;
  Node: TTreeNode;
begin
  if TestsTreeView = nil then Exit;

  if FGroupingMode = tgmStatus then
    RefreshTreeView;

  TestsTreeView.Items.BeginUpdate;
  try
    FirstFailedNode := nil;

    Node := TestsTreeView.Items.GetFirstNode;
    while Assigned(Node) do
    begin
      // We only care about root nodes that have children
      if (Node.Parent = nil) and (Node.Count > 0) then
      begin
        if FGroupingMode = tgmStatus then
        begin
          if SameText(Node.Text, 'Failed') then
          begin
            Node.Expanded := True;
            Child := Node.GetFirstChild;
            if Assigned(Child) and not Assigned(FirstFailedNode) then
              FirstFailedNode := Child;
          end
          else
          begin
            Node.Expanded := False;
          end;
        end
        else
        begin
          HasFailures := False;

          Child := Node.GetFirstChild;
          while Assigned(Child) do
          begin
            if Child.ImageIndex = 2 then
            begin
              HasFailures := True;
              if not Assigned(FirstFailedNode) then
                FirstFailedNode := Child;
            end;

            Child := Child.GetNextSibling;
          end;

          if HasFailures then
            Node.Expanded := True;
        end;
      end;
      Node := Node.GetNext;
    end;

    // Focus the first failure if found
    if Assigned(FirstFailedNode) then
    begin
      TestsTreeView.Selected := FirstFailedNode;
      FirstFailedNode.MakeVisible;
    end;
  finally
    TestsTreeView.Items.EndUpdate;
  end;
end;

procedure TFormDextTestRunner.NotifyProcessExited;
var
  AnalyticsLines: TStringList;
  WasDiscover: Boolean;
begin
  WasDiscover := FDiscoverMode;
  FDiscoverMode := False;
  FRunningTests := False;
  if FRunningProcessHandle <> 0 then
  begin
    LogMsg('');
    LogMsg('========================================');
    if WasDiscover then
    begin
      if Assigned(FTestLocations) then
      begin
        LogMsg(Format('Discover completed — %d test(s) in tree', [FTestLocations.Count]));
        SummaryTotalLabel.Caption := 'Total: ' + IntToStr(FTestLocations.Count);
      end
      else
      begin
        LogMsg('Discover completed — 0 test(s) in tree');
        SummaryTotalLabel.Caption := 'Total: 0';
      end;
    end
    else
      LogMsg(Format('Testing Completed (Process Exited) passed=%d failed=%d skipped=%d completed=%d',
        [FPassedCount, FFailedCount, FSkippedCount, FCompletedTests]));
    LogMsg('========================================');

    if Assigned(ProgressPanel) then
    begin
      ProgressBar.Position := ProgressBar.Max;
      ProgressLabel.Caption := Format('%d/%d', [FCompletedTests, Max(FCompletedTests, FTotalTests)]);
      if not IsTestingDesignShuttingDown then
        TThread.Queue(nil, TThreadProcedure(procedure
          begin
            if IsTestingDesignShuttingDown then
              Exit;
            if Assigned(FormDextTestRunner) and Assigned(FormDextTestRunner.ProgressPanel) and
               not (csDestroying in FormDextTestRunner.ComponentState) then
              FormDextTestRunner.ProgressPanel.Visible := False;
          end));
    end;

    CloseHandle(FRunningProcessHandle);
    FRunningProcessHandle := 0;
    TStopwatch(FStopwatch).Stop;
    UpdateTimingLabels;

    if WasDiscover then
    begin
      EnrichCppLocationsFromSources;
      BuildNodeIndex;
      ExpandTestsTreeView;
      Exit;
    end;

    if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
      EnrichCppLocationsFromSources;

    AnalyticsLines := TStringList.Create;
    try
      TTelemetryTracker.AnalyzeHistory(FActiveProjectFile, AnalyticsLines);
      LogAnalyticsLines(AnalyticsLines);
    finally
      AnalyticsLines.Free;
    end;
    CollapseSuccessAndFocusFailures;
    if FCppLlvmCoverage then
    begin
      LogMsg('Coverage: reading .profraw with llvm-cov…');
      FCppLlvmCoverage := False;
      TryLoadCoverage(True);
    end
    else if FCoverageWrapActive then
    begin
      LogMsg('Coverage: CodeCoverage.exe exited — loading report…');
      FCoverageWrapActive := False;
      TryLoadCoverage(True);
    end
    else
      TryLoadCoverage(False);
  end;
end;

function TFormDextTestRunner.EnsureRuntimeTestNode(const ATestName: string): TTreeNode;
var
  Dot: Integer;
  Fixture: string;
  FixtureNode: TTreeNode;
  Loc: TTestLocation;
  Method: string;
  Node: TTreeNode;
begin
  Result := nil;
  if (TestsTreeView = nil) or (ATestName = '') then
    Exit;

  if Assigned(FNodeByName) and FNodeByName.TryGetValue(ATestName, Node) and Assigned(Node) then
    Exit(Node);

  if IsLikelyBinaryTestName(ATestName) then
    Exit;

  { TStringHelper.LastDelimiter is 0-based; never mix with 1-based Copy (was: Smok + .Method). }
  Dot := ATestName.LastDelimiter('.');
  if Dot >= 0 then
  begin
    Fixture := ATestName.Substring(0, Dot);
    Method := ATestName.Substring(Dot + 1);
  end
  else
  begin
    Fixture := 'Runtime';
    Method := ATestName;
  end;
  if (Fixture = '') or (Method = '') then
    Exit;
  if IsLikelyBinaryTestName(Fixture) or IsLikelyBinaryTestName(Method) then
    Exit;

  FixtureNode := FindNodeByPath(Fixture);
  if not Assigned(FixtureNode) then
  begin
    FixtureNode := TestsTreeView.Items.AddChild(nil, Fixture);
    FixtureNode.ImageIndex := 3;
    FixtureNode.SelectedIndex := 3;
  end;

  Node := TestsTreeView.Items.AddChild(FixtureNode, Method);
  if Assigned(FTestLocations) then
  begin
    Loc.ClassName := Fixture;
    Loc.MethodName := Method;
    Loc.Line := 0;
    Loc.FileName := '';
    FTestLocations.Add(Loc);
    Node.Data := Pointer(FTestLocations.Count);
  end;
  FixtureNode.Expanded := True;
  if Assigned(FNodeByName) then
    FNodeByName.AddOrSetValue(ATestName, Node);
  LogMsg('[Host] registered runtime test node: ' + ATestName);
  Result := Node;
end;

procedure TFormDextTestRunner.UpdateTestNode(const ATestName, AStatus, AMessage, AStackTrace: string);
var
  Node: TTreeNode;
  NodeRect: TRect;
  Text: string;
begin
  Node := nil;
  if (FNodeByName = nil) or not FNodeByName.TryGetValue(ATestName, Node) then
  begin
    Node := FindNodeByPath(ATestName);
    if not Assigned(Node) then
    begin
      Text := ATestName;
      if Text.Contains('.') then
        Text := Text.Split(['.'])[1];
      Node := FindNodeByPath(Text);
    end;
    if Assigned(Node) and Assigned(FNodeByName) then
      FNodeByName.AddOrSetValue(ATestName, Node);
  end;

  { C++ / external Host: no AST tree yet — create nodes from live results. }
  if not Assigned(Node) then
    Node := EnsureRuntimeTestNode(ATestName);

  if Assigned(Node) then
  begin
    if SameText(AStatus, 'Passed') then
    begin
      Node.ImageIndex := 1;
      Node.SelectedIndex := 1;
    end
    else if SameText(AStatus, 'Failed') or SameText(AStatus, 'Error') then
    begin
      Node.ImageIndex := 2;
      Node.SelectedIndex := 2;
      // Console detail for failures is logged in ProcessResultPayload (once).
    end
    else if SameText(AStatus, 'Skipped') then
    begin
      Node.ImageIndex := 0; // Gray
      Node.SelectedIndex := 0;
    end
    else if SameText(AStatus, 'Running') or SameText(AStatus, 'Idle') then
    begin
      Node.ImageIndex := 0;
      Node.SelectedIndex := 0;
    end;
    // Per-node InvalidateRect during a 200+ result burst starves the IDE.
    // While batching, FlushPendingResultsUi invalidates the tree once.
    if not FBatchingUi then
    begin
      NodeRect := Node.DisplayRect(False);
      InvalidateRect(TestsTreeView.Handle, @NodeRect, True);
    end;
  end;
end;

procedure TFormDextTestRunner.TestsTreeViewChange(Sender: TObject; Node: TTreeNode);
var
  Key: string;
  Stopwatch: TStopwatch;
  Rect: TRect;
begin
  if not Assigned(Node) then Exit;
  Stopwatch := TStopwatch.StartNew;

  Key := GetNodeFullTestName(Node);
  UpdateTestInspector(Key);
  if (Node.Parent <> nil) and FTestDetails.ContainsKey(Key) then
  begin
    if DetailsPageControl.Visible then
      DetailsPageControl.ActivePage := InspectorTab;
  end;
  Rect := Node.DisplayRect(True);
  Rect.Right := TestsTreeView.ClientWidth;
  InvalidateRect(TestsTreeView.Handle, @Rect, True);
  if Stopwatch.Elapsed.TotalMilliseconds > 5 then
    LogPerformance(Format('TestsTreeViewChange slow %.2f ms: %s', [Stopwatch.Elapsed.TotalMilliseconds, Key]));
end;

function TFormDextTestRunner.NormalizeStackTraceText(const ARaw: string): string;
var
  JsonVal: TJSONValue;
  S: string;
begin
  Result := Trim(ARaw);
  if Result = '' then
    Exit;

  // Host sends {"raw":"line1\r\nline2"}; old Explorer dumped ToJSON literally.
  S := Result;
  if S.StartsWith('{') and S.Contains('"raw"') then
  begin
    JsonVal := TJSONObject.ParseJSONValue(S);
    try
      if (JsonVal <> nil) and (JsonVal is TJSONObject) then
        if TJSONObject(JsonVal).TryGetValue<string>('raw', S) then
          Result := S;
    finally
      JsonVal.Free;
    end;
  end;

  Result := Result.Replace('\r\n', sLineBreak).Replace('\n', sLineBreak).Replace('\r', sLineBreak);
end;

function TFormDextTestRunner.ExtractStackTraceFromErrorJson(ErrorObj: TJSONObject): string;
var
  StackObj: TJSONObject;
  Raw: string;
begin
  Result := '';
  if ErrorObj = nil then
    Exit;
  if ErrorObj.TryGetValue<string>('stackTrace', Result) and (Result <> '') then
  begin
    Result := NormalizeStackTraceText(Result);
    Exit;
  end;
  if ErrorObj.TryGetValue<TJSONObject>('stackTrace', StackObj) and Assigned(StackObj) then
  begin
    if StackObj.TryGetValue<string>('raw', Raw) then
      Result := NormalizeStackTraceText(Raw)
    else
      Result := NormalizeStackTraceText(StackObj.ToJSON);
  end;
end;

procedure TFormDextTestRunner.UpdateTestInspector(const ATestName: string);
var
  DetailInfo: TTestDetailInfo;
  ClassName: string;
  CleanMethod: string;
  FileLeaf: string;
  Frame: TDextStackFrame;
  Frames: TArray<TDextStackFrame>;
  FrameItem: TListItem;
  HasError: Boolean;
  i: Integer;
  Line: string;
  LocHint: string;
  MethodOnly: string;
  Nav: TStackFrameNav;
  Node: TTreeNode;
  Parts: TArray<string>;
  RealLine: Integer;
  ResolvedLine: Integer;
  ResolvedPath: string;
  StackText: string;
  StatusText: string;
  Stopwatch: TStopwatch;
  TestLocation: TTestLocation;
begin
  Stopwatch := TStopwatch.StartNew;
  if not Assigned(TestNameLabel) then Exit;
  TestNameLabel.Caption := 'Test Name: ' + ATestName;
  ErrorMemo.Clear;
  DetailInfo := Default(TTestDetailInfo);
  TestLocation := Default(TTestLocation);
  HasError := False;
  Frames := nil;
  StatusText := '';

  // Set default Location
  LocationLabel.Caption := 'Location: Unknown';
  Node := nil;
  if Assigned(TestsTreeView) and Assigned(TestsTreeView.Selected) and
    SameText(GetNodeFullTestName(TestsTreeView.Selected), ATestName) then
    Node := TestsTreeView.Selected;

  if not Assigned(Node) then
    Node := FindNodeByPath(ATestName);

  if Assigned(Node) and (Node.Data <> nil) then
  begin
    i := Integer(Node.Data) - 1;
    if (i >= 0) and (i < FTestLocations.Count) then
    begin
      TestLocation := FTestLocations[i];
      if ((TestLocation.FileName = '') or (TestLocation.Line <= 0)) and
         SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
      begin
        EnrichCppLocationsFromSources;
        TestLocation := FTestLocations[i];
      end;
      if TestLocation.FileName <> '' then
      begin
        RealLine := FindMethodImplementationLine(TestLocation.FileName, TestLocation.ClassName,
          TestLocation.MethodName, TestLocation.Line);
        if RealLine <= 0 then
          RealLine := TestLocation.Line;
        if RealLine > 0 then
          LocationLabel.Caption := Format('Location: %s (Line %d)',
            [ExtractFileName(TestLocation.FileName), RealLine])
        else
          LocationLabel.Caption := 'Location: ' + ExtractFileName(TestLocation.FileName);
      end;
    end;
  end;

  if FTestDetails.TryGetValue(ATestName, DetailInfo) then
  begin
    StatusText := DetailInfo.Status;
    StatusLabel.Caption := 'Status: ' + StatusText;
    StatusLabel.ParentColor := False;
    if SameText(StatusText, 'Passed') then
      StatusLabel.Font.Color := TColor($5EC522) // Green BGR
    else if SameText(StatusText, 'Failed') or SameText(StatusText, 'Error') then
      StatusLabel.Font.Color := TColor($4444EF) // Red BGR
    else
    begin
      StatusLabel.Font.Color := clWindowText;
      StatusLabel.ParentColor := True;
    end;

    // Format duration intelligently: show sub-ms precision when needed
    if DetailInfo.DurationMs < 1.0 then
      DurationLabel.Caption := Format('Duration: %.3f ms', [DetailInfo.DurationMs])
    else if DetailInfo.DurationMs < 100.0 then
      DurationLabel.Caption := Format('Duration: %.2f ms', [DetailInfo.DurationMs])
    else
      DurationLabel.Caption := Format('Duration: %.0f ms', [DetailInfo.DurationMs]);

    if DetailInfo.ErrorMessage <> '' then
    begin
      HasError := True;
      // Label above already says "Error" — memo is only the message body.
      ErrorMemo.Lines.Add(DetailInfo.ErrorMessage);
    end;

    // E2.3: parse the stack into structured frames for FStackFramesListView.
    StackText := FormatStackTraceForDisplay(DetailInfo.StackTrace);
    Frames := ParseStackFrames(StackText);
    if Length(Frames) > 0 then
      HasError := True
    else if StackText <> '' then
    begin
      HasError := True;
      if ErrorMemo.Lines.Count > 0 then
        ErrorMemo.Lines.Add('');
      for Line in StackText.Split([sLineBreak], TStringSplitOptions.ExcludeEmpty) do
        ErrorMemo.Lines.Add(Line.Trim);
    end
    else if SameText(StatusText, 'Failed') or SameText(StatusText, 'Error') then
    begin
      HasError := True;
      if ErrorMemo.Lines.Count > 0 then
        ErrorMemo.Lines.Add('');
      if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
      begin
        { Stock dunitrtl CaptureStackTrace is '' unless built with JCL/madExcept.
          Adapter resolves AddressInfo via EXE .map + ASLR; without a large map you get hex only. }
        ErrorMemo.Lines.Add('(no call stack frames)');
        ErrorMemo.Lines.Add('');
        ErrorMemo.Lines.Add('DUnit StackTrace() is empty in stock dunitrtl (needs JCL/madExcept in that RTL).');
        ErrorMemo.Lines.Add('Enable Detailed segment map so AddressInfo can resolve to Class::Method:');
        ErrorMemo.Lines.Add('  Project → Options → C++ Linker → Output → Map file type = Detailed segment map');
        ErrorMemo.Lines.Add('  (⋯ → Apply Debug Trace sets ILINK_MapFileType=DetailedSegments)');
        ErrorMemo.Lines.Add('After Clean+Build, *.map next to the exe should be ~MB — not ~200 bytes.');
        ErrorMemo.Lines.Add('Rebuild the test EXE after pulling adapter changes (DextMapResolve).');
        ErrorMemo.Lines.Add('');
        ErrorMemo.Lines.Add('Double-click the test to open Location (source scan of .cpp / .h).');
      end
      else
      begin
        ErrorMemo.Lines.Add('(stack not available)');
        ErrorMemo.Lines.Add('');
        ErrorMemo.Lines.Add('Enable Debug Trace Mode on the test project, then rebuild:');
        ErrorMemo.Lines.Add('');
        ErrorMemo.Lines.Add('Quick: Actions (⋯) → Apply Debug Trace Options to Active Project');
        ErrorMemo.Lines.Add('');
        ErrorMemo.Lines.Add('Or manually — Project → Options → Building → Delphi Compiler:');
        ErrorMemo.Lines.Add('  Compiling → Optimization = False');
        ErrorMemo.Lines.Add('  Compiling → Debug information = Debug information');
        ErrorMemo.Lines.Add('  Compiling → Use debug .dcus = True');
        ErrorMemo.Lines.Add('  Linking → Debug information = True (+ Detailed map recommended)');
        ErrorMemo.Lines.Add('');
        ErrorMemo.Lines.Add('Tip: use the Debug configuration for the suite EXE; Release often strips symbols.');
      end;
    end;
  end
  else
  begin
    StatusLabel.Caption := 'Status: Idle';
    StatusLabel.Font.Color := clWindowText;
    DurationLabel.Caption := 'Duration: N/A';
  end;

  ErrorHeaderLabel.Visible := HasError and (ErrorMemo.Lines.Count > 0);
  ErrorMemo.Visible := HasError and (ErrorMemo.Lines.Count > 0);
  if ErrorHeaderLabel.Visible then
  begin
    if Length(Frames) > 0 then
      ErrorHeaderLabel.Caption := 'Error'
    else if SameText(StatusText, 'Failed') or SameText(StatusText, 'Error') then
      ErrorHeaderLabel.Caption := 'Error / Stack Trace'
    else
      ErrorHeaderLabel.Caption := 'Error';
  end;

  ClearStackFrameNavs;
  if Assigned(FStackFramesListView) then
  begin
    FStackFramesListView.Items.BeginUpdate;
    try
      for i := 0 to High(Frames) do
      begin
        Frame := Frames[i];
        { Always split Method vs file — never show "Method @ File" in either column. }
        SplitStackMethodAndFile(Frame.RawText, CleanMethod, FileLeaf);
        if CleanMethod = '' then
          SplitStackMethodAndFile(Frame.MethodName, CleanMethod, FileLeaf);

        { Normalize Frame.FileName / Line — never ExtractFileName on "File.cpp:24". }
        if Frame.FileName <> '' then
        begin
          SplitSourceFileAndLine(Frame.FileName, FileLeaf, RealLine);
          Frame.FileName := FileLeaf;
          if (Frame.Line <= 0) and (RealLine > 0) then
            Frame.Line := RealLine;
        end
        else if FileLeaf <> '' then
        begin
          SplitSourceFileAndLine(FileLeaf, FileLeaf, RealLine);
          Frame.FileName := FileLeaf;
          if (Frame.Line <= 0) and (RealLine > 0) then
            Frame.Line := RealLine;
        end;

        { Also pull :line from RawText "@ File.cpp:24" when parser left Line=0. }
        if (Frame.Line <= 0) and (Pos(' @ ', Frame.RawText) > 0) then
        begin
          SplitSourceFileAndLine(Trim(Copy(Frame.RawText, Pos(' @ ', Frame.RawText) + 3, MaxInt)),
            FileLeaf, RealLine);
          if FileLeaf <> '' then
            Frame.FileName := FileLeaf;
          if RealLine > 0 then
            Frame.Line := RealLine;
        end;

        if (CleanMethod = '') and (TestLocation.MethodName <> '') then
          CleanMethod := TestLocation.MethodName;
        { Mis-parsed bare "File.cpp:24" as Method. }
        if (Frame.FileName = '') and TRegEx.IsMatch(CleanMethod,
          '^.+\.(?:cpp|h|hpp|cc|cxx):\d+$', [roIgnoreCase]) then
        begin
          SplitSourceFileAndLine(CleanMethod, FileLeaf, RealLine);
          Frame.FileName := FileLeaf;
          Frame.Line := RealLine;
          Frame.Resolved := Frame.Line > 0;
          if TestLocation.MethodName <> '' then
            CleanMethod := TestLocation.MethodName
          else
            CleanMethod := '(assert)';
        end;

        FrameItem := FStackFramesListView.Items.Add;
        FrameItem.Caption := IntToStr(i + 1);
        if CleanMethod <> '' then
          FrameItem.SubItems.Add(CleanMethod)
        else
          FrameItem.SubItems.Add('(unknown)');

        // Location = file:line only (never method text / never invent .pas from C++).
        LocHint := '(unresolved)';
        ResolvedLine := 0;
        if (Frame.FileName <> '') and (Frame.Line > 0) and
           not IsUnreliableMapLocation(Frame.FileName) then
        begin
          LocHint := Format('%s:%d', [Frame.FileName, Frame.Line]);
          ResolvedLine := Frame.Line;
        end
        else
        begin
          ResolvedPath := ResolveStackFrameFile(CleanMethod, Frame.FileName);
          if ResolvedPath <> '' then
          begin
            if CleanMethod.Contains('::') then
              Parts := CleanMethod.Split(['::'])
            else
              Parts := CleanMethod.Split(['.']);
            MethodOnly := '';
            ClassName := '';
            if Length(Parts) >= 1 then
            begin
              MethodOnly := Parts[High(Parts)];
              if Pos('(', MethodOnly) > 0 then
                MethodOnly := Trim(Copy(MethodOnly, 1, Pos('(', MethodOnly) - 1));
              if Length(Parts) >= 2 then
                ClassName := Parts[High(Parts) - 1];
            end;
            ResolvedLine := FindMethodImplementationLine(ResolvedPath, ClassName, MethodOnly, Frame.Line);
            SplitSourceFileAndLine(ResolvedPath, FileLeaf, RealLine);
            if ResolvedLine > 0 then
              LocHint := Format('%s:%d', [FileLeaf, ResolvedLine])
            else
              LocHint := FileLeaf;
          end
          else if (Frame.FileName <> '') and IsSafePathLeaf(Frame.FileName) then
            LocHint := Frame.FileName
          else if CleanMethod.Contains('::') then
            LocHint := '(unresolved)'
          else
          begin
            LocHint := UnitHintFromMethodName(CleanMethod);
            if LocHint = '' then
              LocHint := '(unresolved)';
          end;
        end;

        { Fallback: test Location label (same failing test) — also fills Nav for click. }
        if ((LocHint = '(unresolved)') or (LocHint = '') or (Frame.FileName = '')) and
           (TestLocation.FileName <> '') then
        begin
          SplitSourceFileAndLine(TestLocation.FileName, FileLeaf, RealLine);
          RealLine := FindMethodImplementationLine(TestLocation.FileName, TestLocation.ClassName,
            TestLocation.MethodName, TestLocation.Line);
          if RealLine <= 0 then
            RealLine := TestLocation.Line;
          if Frame.FileName = '' then
            Frame.FileName := FileLeaf;
          if RealLine > 0 then
          begin
            LocHint := Format('%s:%d', [Frame.FileName, RealLine]);
            if ResolvedLine <= 0 then
              ResolvedLine := RealLine;
          end
          else
            LocHint := Frame.FileName;
        end;
        FrameItem.SubItems.Add(LocHint);

        Nav := TStackFrameNav.Create;
        Nav.FileName := Frame.FileName;
        if Nav.FileName = '' then
        begin
          SplitSourceFileAndLine(TestLocation.FileName, FileLeaf, RealLine);
          Nav.FileName := FileLeaf;
        end;
        Nav.MethodName := CleanMethod;
        if ResolvedLine > 0 then
          Nav.Line := ResolvedLine
        else if Frame.Line > 0 then
          Nav.Line := Frame.Line
        else
          Nav.Line := TestLocation.Line;
        FStackFrameNavs.Add(Nav);
        FrameItem.Data := Nav;
      end;
    finally
      FStackFramesListView.Items.EndUpdate;
    end;
  end;

  LayoutInspectorDetails(ErrorMemo.Visible, Length(Frames));

  if Stopwatch.Elapsed.TotalMilliseconds > 5 then
    LogPerformance(Format('UpdateTestInspector slow %.2f ms: %s', [Stopwatch.Elapsed.TotalMilliseconds, ATestName]));
end;

procedure TFormDextTestRunner.ClearTestStatus;
var
  i: Integer;
  Node: TTreeNode;
begin
  if Assigned(FTestDetails) then
    FTestDetails.Clear;
  if Assigned(FGroupSummaries) then
    FGroupSummaries.Clear;
  if Assigned(FGroupNodes) then
    FGroupNodes.Clear;
  if Assigned(TestNameLabel) then
  begin
    TestNameLabel.Caption := 'Test Name: Select a test...';
    StatusLabel.Caption := 'Status: Idle';
    StatusLabel.Font.Color := clWindowText;
    LocationLabel.Caption := 'Location: N/A';
    DurationLabel.Caption := 'Duration: N/A';
    ErrorMemo.Clear;
  end;

  ClearStackFrameNavs;
  LayoutInspectorDetails(False, 0);

  TestsTreeView.Items.BeginUpdate;
  try
    for i := 0 to TestsTreeView.Items.Count - 1 do
    begin
      Node := TestsTreeView.Items[i];
      if Node.ImageIndex in [1, 2] then
      begin
        Node.ImageIndex := 0;
        Node.SelectedIndex := 0;
      end;
    end;
  finally
    TestsTreeView.Items.EndUpdate;
  end;
end;

procedure TFormDextTestRunner.RunActiveProjectTests(const TestFilter: string = ''; AutoSave: Boolean = True);
var
  Group: IOTAProjectGroup;
  ModuleServices: IOTAModuleServices;
  Project: IOTAProject;
  SaveServices: IOTAModuleServices;
begin
  if ProjectsComboBox.ItemIndex = -1 then Exit;
  Project := GetProjectByFileName(FActiveProjectFile);
  if not Assigned(Project) then Exit;

  FRunningTests := True;

  // Synchronize IDE Active Project
  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) and Assigned(ModuleServices) then
  begin
    Group := ModuleServices.MainProjectGroup;
    if Assigned(Group) and (Group.ActiveProject <> Project) then
      Group.ActiveProject := Project;
  end;

  ClearTestStatus;
  DetailsMemo.Clear;
  if Assigned(FConsoleListView) then
    FConsoleListView.Items.Clear;
  FTotalTests := 0;
  FCompletedTests := 0;
  FPassedCount := 0;
  FFailedCount := 0;
  FSkippedCount := 0;
  FTestExecutionDurationMs := 0;
  LogPerformance(Format('RunActiveProjectTests: start filter="%s" autoSave=%s', [TestFilter, BoolToStr(AutoSave, True)]));

  // Start stopwatch
  TStopwatch(FStopwatch).Reset;
  TStopwatch(FStopwatch).Start;
  UpdateTotalTimeLabel;

  // Show progress immediately so the user knows something is happening
  if Assigned(ProgressPanel) then
  begin
    ProgressBar.Style := pbstMarquee;
    ProgressBar.Position := 0;
    ProgressBar.Max := 100;
    ProgressLabel.Caption := 'Saving files...';
    ProgressPanel.Visible := True;
    ProgressPanel.Update;
  end;

  if Assigned(DetailsPageControl) and Assigned(ConsoleTab) then
    DetailsPageControl.ActivePage := ConsoleTab;

  LogMsg('--- Dext Test Runner ---');
  LogMsg('Project: ' + ExtractFileName(FActiveProjectFile));

  // Step 1: Save all editor buffers so IDE's make sees up-to-date timestamps
  if AutoSave and Supports(BorlandIDEServices, IOTAModuleServices, SaveServices) then
  begin
    LogMsg('[1/3] Saving all modified files...');
    SaveServices.SaveAll;
  end;

  // Step 2: Trigger the IDE's incremental make (async).
  //   The IDE knows exactly which files changed in the editor.
  //   Test launch happens in NotifyCompileComplete → AfterCompile notifier.
  FPendingTestFilter  := TestFilter;
  FPendingProject     := Project;
  FDiscoverAfterCompile := False;
  FDiscoverMode := False;
  FWaitingForCompile  := True;

  if Assigned(ProgressPanel) then
  begin
    ProgressLabel.Caption := '[2/3] Compiling...';
    ProgressPanel.Update;
  end;
  LogMsg('[2/3] Starting incremental compile (IDE make)...');
  LogPerformance('RunActiveProjectTests: before build');

  // Wait=False: must not block the IDE UI thread. AfterCompile → NotifyCompileComplete.
  Project.ProjectBuilder.BuildProject(cmOTAMake, False, False);
end;

function TFormDextTestRunner.IsLikelyBinaryTestName(const AName: string): Boolean;
var
  Lower: string;
begin
  Lower := AnsiLowerCase(AName);
  Result := Lower.EndsWith('.exe') or Lower.EndsWith('.dll') or Lower.EndsWith('.bpl')
    or Lower.Contains('\') or Lower.Contains('/');
end;

function TFormDextTestRunner.ResolveActiveProjectExe(out AExeFile: string): Boolean;
var
  Config: string;
  Configs: IOTAProjectOptionsConfigurations;
  IsPackage: Boolean;
  Output: string;
  PlatformVal: string;
  Proj: IOTAProject;
begin
  AExeFile := '';
  Output := '';
  PlatformVal := 'Win32';
  Config := 'Debug';
  Proj := GetProjectByFileName(FActiveProjectFile);
  if Assigned(Proj) then
  begin
    try
      Output := VarToStr(Proj.ProjectOptions.Values['OutputDir']);
    except
      Output := '';
    end;
    if Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    begin
      PlatformVal := Configs.ActivePlatformName;
      if Assigned(Configs.ActiveConfiguration) then
        Config := Configs.ActiveConfiguration.Name;
    end;
  end;
  if (Output = '') or (Output = '.') or (Output = '.\') or (Output = './') then
    GetProjectTargetInfo(FActiveProjectFile, IsPackage, Output, PlatformVal, Config);
  AExeFile := ResolveExePath(FActiveProjectFile, Output, PlatformVal, Config);
  Result := FileExists(AExeFile);
end;

procedure TFormDextTestRunner.LaunchDiscoverExe;
var
  CmdLine: string;
  ExeFile: string;
  PI: TProcessInformation;
  ProcessHandle: THandle;
  SI: TStartupInfo;
begin
  if not ResolveActiveProjectExe(ExeFile) then
  begin
    LogMsg('[Discover] Executable not found — build the project first.');
    FDiscoverMode := False;
    Exit;
  end;

  FDiscoverMode := True;
  FCoverageWrapActive := False;
  FCppLlvmCoverage := False;
  FServer.SelectedTestsJSON := '[]';
  FTotalTests := 0;
  FCompletedTests := 0;
  FPassedCount := 0;
  FFailedCount := 0;
  FSkippedCount := 0;

  TestsTreeView.Items.BeginUpdate;
  try
    TestsTreeView.Items.Clear;
    if Assigned(FTestLocations) then
      FTestLocations.Clear;
    if Assigned(FTestDetails) then
      FTestDetails.Clear;
    if Assigned(FNodeByName) then
      FNodeByName.Clear;
  finally
    TestsTreeView.Items.EndUpdate;
  end;
  ResetSummaryLabels;

  CmdLine := Format('"%s" --port %d --discover -no-wait', [ExeFile, FServer.Port]);
  LogMsg('[Discover] ' + CmdLine);
  UniqueString(CmdLine);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  ZeroMemory(@PI, SizeOf(PI));

  if FRunningProcessHandle <> 0 then
  begin
    TerminateProcess(FRunningProcessHandle, 0);
    CloseHandle(FRunningProcessHandle);
    FRunningProcessHandle := 0;
  end;

  if CreateProcess(nil, PChar(CmdLine), nil, nil, False, CREATE_NO_WINDOW, nil,
    PChar(ExtractFilePath(ExeFile)), SI, PI) then
  begin
    LogMsg(Format('[Discover] CreateProcess OK pid=%d', [PI.dwProcessId]));
    FRunningProcessHandle := PI.hProcess;
    CloseHandle(PI.hThread);
    ProcessHandle := PI.hProcess;
    TThread.CreateAnonymousThread(procedure
      begin
        WaitForSingleObject(ProcessHandle, 120000);
        TThread.Queue(nil, TThreadProcedure(procedure
          begin
            if IsTestingDesignShuttingDown then
              Exit;
            if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
              FormDextTestRunner.NotifyProcessExited;
          end));
      end).Start;
  end
  else
  begin
    LogMsg(Format('[Discover] CreateProcess FAILED GetLastError=%d', [GetLastError]));
    FDiscoverMode := False;
  end;
end;

procedure TFormDextTestRunner.EnrichCppLocationsFromSources;
var
  Candidate: string;
  Ext: string;
  FileName: string;
  FilesToScan: TStringList;
  i, j: Integer;
  Loc: TTestLocation;
  Project: IOTAProject;
  Scanned: TTestLocation;
  Tests: TList<TTestLocation>;

  procedure Consider(const APath: string);
  begin
    if (APath <> '') and FileExists(APath) and (FilesToScan.IndexOf(APath) < 0) then
      FilesToScan.Add(APath);
  end;

begin
  if not Assigned(FTestLocations) or (FTestLocations.Count = 0) then
    Exit;
  Project := GetProjectByFileName(FActiveProjectFile);
  if not Assigned(Project) then
    Exit;

  FilesToScan := TStringList.Create;
  try
    FilesToScan.CaseSensitive := False;
    for i := 0 to Project.GetModuleCount - 1 do
    begin
      FileName := Project.GetModule(i).FileName;
      Ext := ExtractFileExt(FileName);
      if SameText(Ext, '.cpp') or SameText(Ext, '.cc') or SameText(Ext, '.c') then
      begin
        Consider(FileName);
        { Headers are often not OTA modules — scan siblings next to the .cpp. }
        Consider(ChangeFileExt(FileName, '.h'));
        Consider(ChangeFileExt(FileName, '.hpp'));
      end
      else if SameText(Ext, '.h') or SameText(Ext, '.hpp') then
        Consider(FileName);
    end;

    for i := 0 to FilesToScan.Count - 1 do
    begin
      Candidate := FilesToScan[i];
      Tests := nil;
      if not TTestASTScanner.ScanFile(Candidate, Tests) then
      begin
        if Assigned(Tests) then
          Tests.Free;
        Continue;
      end;
      try
        for Scanned in Tests do
          for j := 0 to FTestLocations.Count - 1 do
          begin
            Loc := FTestLocations[j];
            if SameText(Loc.ClassName, Scanned.ClassName) and
               SameText(Loc.MethodName, Scanned.MethodName) then
            begin
              { Prefer .cpp implementation over .h declaration. }
              if (Loc.FileName = '') or SameText(ExtractFileExt(Candidate), '.cpp') or
                 SameText(ExtractFileExt(Candidate), '.cc') or (Loc.Line <= 0) then
              begin
                Loc.FileName := Scanned.FileName;
                Loc.Line := Scanned.Line;
                FTestLocations[j] := Loc;
              end;
            end;
          end;
      finally
        Tests.Free;
      end;
    end;
  finally
    FilesToScan.Free;
  end;
end;

procedure TFormDextTestRunner.PopulateCppTestsFromAstOnly;
var
  Candidate: string;
  Ext: string;
  FileName: string;
  i, j: Integer;
  Loc: TTestLocation;
  Project: IOTAProject;
  Tests: TList<TTestLocation>;
  FixtureNode, MethodNode: TTreeNode;
begin
  Project := GetProjectByFileName(FActiveProjectFile);
  if not Assigned(Project) then
    Exit;

  TestsTreeView.Items.BeginUpdate;
  try
    TestsTreeView.Items.Clear;
    if Assigned(FTestLocations) then
      FTestLocations.Clear;
    if Assigned(FNodeByName) then
      FNodeByName.Clear;

    for i := 0 to Project.GetModuleCount - 1 do
    begin
      FileName := Project.GetModule(i).FileName;
      Ext := ExtractFileExt(FileName);
      if not (SameText(Ext, '.cpp') or SameText(Ext, '.cc') or SameText(Ext, '.c') or
              SameText(Ext, '.h') or SameText(Ext, '.hpp')) then
        Continue;
      Candidate := FileName;
      Tests := nil;
      if not TTestASTScanner.ScanFile(Candidate, Tests) then
      begin
        if Assigned(Tests) then
          Tests.Free;
        Continue;
      end;
      try
        for j := 0 to Tests.Count - 1 do
        begin
          Loc := Tests[j];
          if Loc.FileName = '' then
            Loc.FileName := Candidate;
          FTestLocations.Add(Loc);
          FixtureNode := FindNodeByPath(Loc.ClassName);
          if not Assigned(FixtureNode) then
          begin
            FixtureNode := TestsTreeView.Items.AddChild(nil, Loc.ClassName);
            FixtureNode.ImageIndex := 3;
            FixtureNode.SelectedIndex := 3;
          end;
          MethodNode := TestsTreeView.Items.AddChild(FixtureNode, Loc.MethodName);
          MethodNode.Data := Pointer(FTestLocations.Count);
          MethodNode.ImageIndex := 0;
          MethodNode.SelectedIndex := 0;
          if Assigned(FNodeByName) then
            FNodeByName.AddOrSetValue(Loc.ClassName + '.' + Loc.MethodName, MethodNode);
        end;
      finally
        Tests.Free;
      end;
    end;
    ExpandTestsTreeView;
    SummaryTotalLabel.Caption := 'Total: ' + IntToStr(FTestLocations.Count);
  finally
    TestsTreeView.Items.EndUpdate;
  end;
end;

procedure TFormDextTestRunner.DiscoverCppProjectTests;
var
  ExeFile: string;
  Project: IOTAProject;
begin
  Project := GetProjectByFileName(FActiveProjectFile);
  if not Assigned(Project) then
    Exit;

  LogMsg('--- Discover (C++ Host / AST) ---');
  LogMsg('Project: ' + ExtractFileName(FActiveProjectFile));

  { Never auto-BuildProject here — opening a .cbproj used to compile with Run on Save off.
    Run All / Selected still build when the user asks to execute. }
  if ResolveActiveProjectExe(ExeFile) then
  begin
    LaunchDiscoverExe;
    Exit;
  end;

  LogMsg('[Discover] Exe not found — listing tests from source (TEST / TTestCase). Build or Run All when ready.');
  FDiscoverAfterCompile := False;
  FWaitingForCompile := False;
  FRunningTests := False;
  PopulateCppTestsFromAstOnly;
end;

procedure TFormDextTestRunner.LaunchTestExe(const ATestFilter: string);
var
  Checked: TArray<string>;
  CmdLine: string;
  Config: string;
  Configs: IOTAProjectOptionsConfigurations;
  CoverageFailHint: string;
  CoveragePrep: TCoverageRunPrep;
  CustomParams: string;
  ExeFile: string;
  i: Integer;
  IsPackage: Boolean;
  Json: string;
  Output: string;
  Params: string;
  PI: TProcessInformation;
  PlatformVal: string;
  ProcessHandle: THandle;
  ProfFile: string;
  ProfFiles: TArray<string>;
  Proj: IOTAProject;
  SI: TStartupInfo;
  UseCoverage: Boolean;
begin
  FDiscoverMode := False;
  FDiscoverAfterCompile := False;
  CoverageFailHint := '';
  IsPackage := False;
  Output := '';
  PlatformVal := 'Win32';
  Config := 'Debug';
  Proj := GetProjectByFileName(FActiveProjectFile);
  LogMsg(Format('[Launch] ActiveProject=%s', [FActiveProjectFile]));
  if Assigned(Proj) then
  begin
    try
      Output := VarToStr(Proj.ProjectOptions.Values['OutputDir']);
    except
      Output := '';
    end;
    LogMsg(Format('[Launch] OTA OutputDir="%s"', [Output]));
    if Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    begin
      PlatformVal := Configs.ActivePlatformName;
      if Assigned(Configs.ActiveConfiguration) then
        Config := Configs.ActiveConfiguration.Name;
    end;
    LogMsg(Format('[Launch] OTA Platform=%s Config=%s', [PlatformVal, Config]));
  end
  else
    LogMsg('[Launch] WARNING: IOTAProject not found for active file');

  if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') and
     not SameText(PlatformVal, 'Win64x') then
    LogMsg(Format(
      'Coverage: Win32 and classic Win64 do not support code coverage. Active platform is %s.',
      [PlatformVal]));
  ApplyCoverageForActivePlatform;

  { OTA often returns "." for C++ FinalOutputDir — treat as empty and read .cbproj tags. }
  if (Output = '') or (Output = '.') or (Output = '.\') or (Output = './') then
  begin
    GetProjectTargetInfo(FActiveProjectFile, IsPackage, Output, PlatformVal, Config);
    LogMsg(Format('[Launch] GetProjectTargetInfo Final/DCC out="%s" isPackage=%s',
      [Output, BoolToStr(IsPackage, True)]));
  end;

  ExeFile := ResolveExePath(FActiveProjectFile, Output, PlatformVal, Config);
  LogMsg(Format('[Launch] Resolved exe=%s exists=%s',
    [ExeFile, BoolToStr(FileExists(ExeFile), True)]));
  LogMsg(Format('[Launch] Host port=%d', [FServer.Port]));

  if not FileExists(ExeFile) then
  begin
    LogMsg('Error: Executable not found at ' + ExeFile);
    LogMsg('[Launch] Hint: for .cbproj expect FinalOutputDir e.g. .\Win32\Debug\Project.exe');
    TStopwatch(FStopwatch).Stop;
    UpdateTimingLabels;
    if Assigned(ProgressPanel) then ProgressPanel.Visible := False;
    Exit;
  end;

  // Apply test filter to server selection Json
  if ATestFilter <> '' then
    FServer.SelectedTestsJSON := '["' + ATestFilter + '"]'
  else
  begin
    Checked := GetCheckedTests;
    if Length(Checked) > 0 then
    begin
      Json := '[';
      for i := 0 to Length(Checked) - 1 do
      begin
        if i > 0 then Json := Json + ',';
        Json := Json + '"' + Checked[i] + '"';
      end;
      Json := Json + ']';
      FServer.SelectedTestsJSON := Json;
    end
    else
      FServer.SelectedTestsJSON := '[]';
  end;

  LogMsg('Selected tests filter: ' + FServer.SelectedTestsJSON);

  // Update progress to 'Executing'
  if Assigned(ProgressPanel) then
  begin
    ProgressLabel.Caption := '⏳ Executing tests...';
    ProgressBar.Style := pbstMarquee;
    ProgressPanel.Visible := True;
    ProgressPanel.Update;
  end;
  // DetailsMemo is hidden and no longer painted synchronously here (E1.7).

  Params := Format('--port %d -no-wait', [FServer.Port]);
  CustomParams := CustomParamsEdit.Text;
  if CustomParams <> '' then
    Params := Params + ' ' + CustomParams;

  if ATestFilter <> '' then
  begin
    FServer.SelectedTestsJSON := '["' + ATestFilter + '"]';
  end;

  UseCoverage := Assigned(FCoverageCheckBox) and FCoverageCheckBox.Checked;
  FCppLlvmCoverage := False;
  if UseCoverage and SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') and
     SameText(PlatformVal, 'Win64x') then
  begin
    FCoverageWrapActive := False;
    FCppLlvmCoverage := True;
    CmdLine := Format('"%s" %s', [ExeFile, Params]);
    LogMsg('Coverage: C++ line hits come from llvm-cov after this run.');
    try
      ProfFiles := TDirectory.GetFiles(ExtractFilePath(ExeFile), '*.profraw');
      for ProfFile in ProfFiles do
        TFile.Delete(ProfFile);
    except
    end;
  end
  else if UseCoverage and SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
  begin
    FCoverageWrapActive := False;
    CmdLine := Format('"%s" %s', [ExeFile, Params]);
  end
  else if UseCoverage then
  begin
    FCoverageWrapActive := False;
    if TDextCoverageRunner.PrepareRun(FActiveProjectFile, ExeFile, PlatformVal,
      procedure(AMsg: string)
      begin
        LogMsg(AMsg);
      end,
      CoveragePrep, CoverageFailHint) then
    begin
      FLastCoverageReportDir := CoveragePrep.ReportDir;
      FLastCoverageSourceRoot := CoveragePrep.SourceRoot;
      FCoverageWrapActive := True;
      CmdLine := TDextCoverageRunner.BuildWrappedCommandLine(CoveragePrep, ExeFile, Params,
        Assigned(FGenerateHtmlCheckBox) and FGenerateHtmlCheckBox.Checked);
      LogMsg('Coverage wrap: ' + CmdLine);
      LogMsg('Coverage: report dir = ' + CoveragePrep.ReportDir);
      if Assigned(FGenerateHtmlCheckBox) and FGenerateHtmlCheckBox.Checked then
        LogMsg('Coverage: HTML report enabled (-html).')
      else
        LogMsg('Coverage: HTML report off (enable in Configurations or Actions).');
    end
    else
    begin
      // Never block compile/suite: soft-fail coverage (log + Coverage tab), keep running tests.
      // FCoverageWrapActive stays False — gates CodeCoverage wait / TryLoadCoverage after exit.
      if CoverageFailHint = '' then
        CoverageFailHint := 'Coverage skipped for this run — see Console. Tests continue without wrap.';
      SetCoverageProblem(CoverageFailHint);
      CmdLine := Format('"%s" %s', [ExeFile, Params]);
    end;
  end
  else
  begin
    FCoverageWrapActive := False;
    CmdLine := Format('"%s" %s', [ExeFile, Params]);
  end;

  LogMsg('Command Line: ' + CmdLine);
  UniqueString(CmdLine);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  ZeroMemory(@PI, SizeOf(PI));

  if FRunningProcessHandle <> 0 then
  begin
    TerminateProcess(FRunningProcessHandle, 0);
    CloseHandle(FRunningProcessHandle);
    FRunningProcessHandle := 0;
  end;

  if CreateProcess(nil, PChar(CmdLine), nil, nil, False, CREATE_NO_WINDOW, nil, PChar(ExtractFilePath(ExeFile)), SI, PI) then
  begin
    LogMsg(Format('[Launch] CreateProcess OK pid=%d cwd=%s',
      [PI.dwProcessId, ExtractFilePath(ExeFile)]));
    FRunningProcessHandle := PI.hProcess;
    CloseHandle(PI.hThread);

    ProcessHandle := PI.hProcess;
    TThread.CreateAnonymousThread(procedure
      begin
        WaitForSingleObject(ProcessHandle, 120000); // 120s timeout max
        TThread.Queue(nil, TThreadProcedure(procedure
          begin
            if IsTestingDesignShuttingDown then
              Exit;
            if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
              FormDextTestRunner.NotifyProcessExited;
          end));
      end).Start;
  end
  else
    LogMsg(Format('[Launch] CreateProcess FAILED GetLastError=%d exe=%s',
      [GetLastError, ExeFile]));
end;

{$IFDEF DEXT_TEST_EXPLORER_LOG_FILE_ENABLED}
var
  LogLock: TObject = nil;

procedure LogToFile(const AMsg: string);
var
  Path: string;
  Writer: TStreamWriter;
begin
  if LogLock = nil then Exit;
  System.TMonitor.Enter(LogLock);
  try
    try
      Path := TPath.Combine(TPath.GetTempPath, 'DextExpert.log');
      Writer := TFile.AppendText(Path);
      try
        Writer.WriteLine(Format('[%s] %s', [FormatDateTime('yyyy-MM-dd hh:nn:ss.zzz', Now), AMsg]));
      finally
        Writer.Free;
      end;
    except
    end;
  finally
    System.TMonitor.Exit(LogLock);
  end;
end;
{$ELSE}
procedure LogToFile(const AMsg: string);
begin
// log to file disabled, define DEXT_TEST_EXPLORER_LOG_FILE_ENABLED to enable
end;
{$ENDIF}

procedure TFormDextTestRunner.LogMsg(const AMsg: string; AKind: TDextConsoleKind);
const
  MaxConsoleItems = 2000;
var
  Stamp: string;
  Upper: string;
  TrimmedUpper: string;
  Tag: string;
  ImgIndex: Integer;
  Item: TListItem;
  Kind: TDextConsoleKind;
begin
  LogToFile('[UI] ' + AMsg);
  Winapi.Windows.OutputDebugString(PChar('[Dext.UI] ' + AMsg));
  if not Assigned(FConsoleListView) then
    Exit;

  Stamp := FormatDateTime('hh:nn:ss', Now);
  Kind := AKind;
  if Kind = dckAuto then
  begin
    Upper := AnsiUpperCase(AMsg);
    TrimmedUpper := Trim(Upper);
    // Trend / suite sparkline: never FAIL (legend contains the word "fail").
    if TrimmedUpper.StartsWith('TREND:') or TrimmedUpper.Contains(' TREND:') then
      Kind := dckLog
    // Prefer outcome prefixes from the runner over substring matches.
    else if TrimmedUpper.StartsWith('FAILED') or TrimmedUpper.StartsWith('FAIL:') or
            TrimmedUpper.StartsWith('ERROR:') or TrimmedUpper.StartsWith('ERROR ') or
            TrimmedUpper.Contains('COMPILE FAILED') then
      Kind := dckFail
    else if TrimmedUpper.StartsWith('PASSED') or TrimmedUpper.StartsWith('PASS:') or
            TrimmedUpper.StartsWith('SUCCESS') or TrimmedUpper.Contains('COMPILE SUCCEEDED') or
            TrimmedUpper.StartsWith('✔') then
      Kind := dckPass
    else if TrimmedUpper.StartsWith('SKIPPED') or TrimmedUpper.StartsWith('SKIP:') then
      Kind := dckSkip
    else if TrimmedUpper.StartsWith('WARN') or TrimmedUpper.Contains('[WARN]') then
      Kind := dckWarn
    else
      Kind := dckLog;
  end;

  case Kind of
    dckPass:
      begin
        Tag := 'PASS';
        ImgIndex := 1;
      end;
    dckFail:
      begin
        Tag := 'FAIL';
        ImgIndex := 2;
      end;
    dckSkip:
      begin
        Tag := 'SKIP';
        ImgIndex := 0;
      end;
    dckWarn:
      begin
        Tag := 'WARN';
        ImgIndex := 0;
      end;
  else
    begin
      Tag := 'LOG';
      ImgIndex := 0;
    end;
  end;

  Item := FConsoleListView.Items.Add;
  Item.Caption := Stamp;
  Item.ImageIndex := ImgIndex;
  Item.SubItems.Add(Tag);
  Item.SubItems.Add(AMsg);

  // Cap the console at a reasonable size so a long session doesn't grow unbounded.
  while FConsoleListView.Items.Count > MaxConsoleItems do
    FConsoleListView.Items.Delete(0);

  // Do not call Update/Repaint here — it forces synchronous paint and
  // freezes the IDE when hundreds of results arrive on the UI thread.
  Item.MakeVisible(False);
end;

procedure TFormDextTestRunner.LogAnalyticsLines(ALines: TStrings);
var
  i: Integer;
  Trimmed: string;
  Upper: string;
  Kind: TDextConsoleKind;
begin
  if not Assigned(ALines) then
    Exit;
  for i := 0 to ALines.Count - 1 do
  begin
    Trimmed := Trim(ALines[i]);
    if Trimmed = '' then
      Continue;
    Upper := AnsiUpperCase(Trimmed);
    // Analytics is historical commentary — never auto-classify via "fail" substrings.
    if Upper.Contains('[FLAKY]') or Upper.Contains('[PERF REGRESSION]') then
      Kind := dckWarn
    else
      Kind := dckLog;
    LogMsg(ALines[i], Kind);
  end;
end;

procedure TFormDextTestRunner.LogPerformance(const AMessage: string);
{$IFDEF DEXT_TEST_EXPLORER_PERF_LOG}
var
  Line: string;
  LogFile: string;
{$ENDIF}
begin
{$IFDEF DEXT_TEST_EXPLORER_PERF_LOG}
  Line := Format('[%s] %s', [FormatDateTime('hh:nn:ss.zzz', Now), AMessage]);
  LogFile := TPath.Combine(TPath.GetTempPath, 'DextTestExplorer.perf.log');
  try
    System.TMonitor.Enter(PerfLogLock);
    try
      TFile.AppendAllText(LogFile, Line + sLineBreak, TEncoding.UTF8);
    finally
      System.TMonitor.Exit(PerfLogLock);
    end;
  except
    // ignore logging failures
  end;
{$ELSE}
  if AMessage = '' then;
{$ENDIF}
end;

procedure TFormDextTestRunner.InitializeGroupSummaries;
var
  i: Integer;
  Info: TGroupSummaryInfo;
  Key: string;
  Test: TTestLocation;
begin
  if not Assigned(FGroupSummaries) then Exit;
  FGroupSummaries.Clear;
  for i := 0 to FTestLocations.Count - 1 do
  begin
    Test := FTestLocations[i];
    Key := Test.ClassName;
    if not FGroupSummaries.TryGetValue(Key, Info) then
    begin
      Info.TotalCount := 0;
      Info.PassedCount := 0;
      Info.FailedCount := 0;
      Info.DurationMs := 0;
    end;
    Inc(Info.TotalCount);
    FGroupSummaries.AddOrSetValue(Key, Info);
  end;
end;

procedure TFormDextTestRunner.UpdateGroupSummary(const ATestName, AStatus: string; ADurationMs: Double);
var
  ClassName: string;
  DotPos: Integer;
  i: Integer;
  Info: TGroupSummaryInfo;
  TestLocation: TTestLocation;
begin
  if not Assigned(FGroupSummaries) then Exit;
  DotPos := ATestName.IndexOf('.');
  if DotPos <= 0 then Exit;
  ClassName := ATestName.Substring(0, DotPos);
  if not FGroupSummaries.TryGetValue(ClassName, Info) then
  begin
    Info.TotalCount := 0;
    Info.PassedCount := 0;
    Info.FailedCount := 0;
    Info.DurationMs := 0;

    for i := 0 to FTestLocations.Count - 1 do
    begin
      TestLocation := FTestLocations[i];
      if SameText(TestLocation.ClassName, ClassName) then
        Inc(Info.TotalCount);
    end;
  end;

  if SameText(AStatus, 'Passed') then
    Inc(Info.PassedCount)
  else if SameText(AStatus, 'Failed') or SameText(AStatus, 'Error') then
    Inc(Info.FailedCount);
  Info.DurationMs := Info.DurationMs + ADurationMs;
  FGroupSummaries.AddOrSetValue(ClassName, Info);
end;

procedure TFormDextTestRunner.InvalidateGroupNode(const ATestName: string);
var
  DotPos: Integer;
  Node: TTreeNode;
  NodeRect: TRect;
  TestClassName: string;
begin
  if FBatchingUi then Exit; // tree Invalidate once per flush slice
  if not Assigned(TestsTreeView) then Exit;
  DotPos := ATestName.IndexOf('.');
  if DotPos <= 0 then Exit;
  TestClassName := ATestName.Substring(0, DotPos);
  Node := FindNodeByPath(TestClassName);
  if Assigned(Node) then
  begin
    NodeRect := Node.DisplayRect(True);
    NodeRect.Right := TestsTreeView.ClientWidth;
    InvalidateRect(TestsTreeView.Handle, @NodeRect, True);
  end;
end;

procedure TFormDextTestRunner.UpdateNodeResultCache(const ATestName, AStatus: string; ADurationMs: Double);
begin
  UpdateGroupSummary(ATestName, AStatus, ADurationMs);
  InvalidateGroupNode(ATestName);
end;

procedure TFormDextTestRunner.UpdateTotalTimeLabel;
begin
  SummaryTotalTimeLabel.Caption := Format('Total: %.2fs', [TStopwatch(FStopwatch).Elapsed.TotalSeconds]);
end;

procedure TFormDextTestRunner.UpdateSummaryCounts;
var
  CheckedTests: TArray<string>;
  SelectedCount: Integer;
begin
  ResetSummaryLabels;
  SummaryTotalLabel.Caption := 'Total: ' + FTestLocations.Count.ToString;
  CheckedTests := GetCheckedTests;
  SelectedCount := Length(CheckedTests);
  SummarySelectedLabel.Caption := 'Selected: ' + SelectedCount.ToString;
end;

procedure TFormDextTestRunner.UpdateTimingLabels;
begin
  SummaryTimeLabel.Caption := Format('Tests: %.2fs', [FTestExecutionDurationMs / 1000]);
  UpdateTotalTimeLabel;
end;

procedure TFormDextTestRunner.NotifyCompileComplete(ASucceeded: Boolean);
var
  WantDiscover: Boolean;
begin
  if not FWaitingForCompile then
  begin
    LogMsg(Format('[Compile] AfterCompile ignored (not waiting) succeeded=%s',
      [BoolToStr(ASucceeded, True)]));
    Exit;
  end;
  FWaitingForCompile := False;
  WantDiscover := FDiscoverAfterCompile;
  FDiscoverAfterCompile := False;

  if not ASucceeded then
  begin
    FRunningTests := False;
    FDiscoverMode := False;
    LogMsg('❌ Compile failed - tests not executed.');
    TStopwatch(FStopwatch).Stop;
    UpdateTimingLabels;
    if Assigned(ProgressPanel) then
    begin
      ProgressLabel.Caption := 'Compile failed';
      ProgressPanel.Visible := False;
    end;
    Exit;
  end;

  if WantDiscover then
  begin
    LogMsg('✔ Compile succeeded — discovering tests…');
    LaunchDiscoverExe;
  end
  else
  begin
    LogMsg('✔ Compile succeeded — launching test exe…');
    LaunchTestExe(FPendingTestFilter);
  end;
end;

procedure TFormDextTestRunner.RunAllButtonClick(Sender: TObject);
begin
  RunActiveProjectTests;
end;

procedure TFormDextTestRunner.RunAllProjectsClick(Sender: TObject);
begin
  RunAllProjectsTests;
end;

procedure TFormDextTestRunner.RunAllProjectsTests;
var
  CmdLine: string;
  Config: string;
  Configs: IOTAProjectOptionsConfigurations;
  ExeFile: string;
  i: Integer;
  IsPackage: Boolean;
  Output: string;
  Params: string;
  PI: TProcessInformation;
  PlatformVal: string;
  Proj: IOTAProject;
  ProjFile: string;
  ProjInfo: TDextProjectInfo;
  SaveServices: IOTAModuleServices;
  SI: TStartupInfo;
begin
  FRunningTests := True;
  ClearTestStatus;
  DetailsMemo.Clear;
  if Assigned(FConsoleListView) then
    FConsoleListView.Items.Clear;
  FTotalTests := 0;
  FCompletedTests := 0;
  if Assigned(ProgressPanel) then
  begin
    ProgressBar.Style := pbstMarquee;
    ProgressBar.Position := 0;
    ProgressBar.Max := 100;
    ProgressLabel.Caption := '...';
    ProgressPanel.Visible := True;
  end;
  // Focus Console Log
  if Assigned(DetailsPageControl) and Assigned(ConsoleTab) then
    DetailsPageControl.ActivePage := ConsoleTab;
  LogMsg('=== Running All Test Projects ===');

  // Save all modified IDE files once before the loop.
  if Supports(BorlandIDEServices, IOTAModuleServices, SaveServices) then
  begin
    LogMsg('Saving all modified files...');
    SaveServices.SaveAll;
  end;

  for i := 0 to ProjectsComboBox.Items.Count - 1 do
  begin
    ProjInfo := TDextProjectInfo(ProjectsComboBox.Items.Objects[i]);
    if Assigned(ProjInfo) then
    begin
      Proj := GetProjectByFileName(ProjInfo.FileName);
      if Assigned(Proj) then
      begin
        ProjFile := Proj.FileName;
        LogMsg('');
        LogMsg('----------------------------------------');
        LogMsg('Compiling ' + ExtractFileName(ProjFile) + '...');
        if not CompileProjectDirect(ProjFile) then
        begin
          LogMsg('Direct DCC compile failed, building via IDE make...');
          Proj.ProjectBuilder.BuildProject(cmOTAMake, False, False);
        end;

        IsPackage := False;
        Output := '';
        PlatformVal := 'Win32';
        Config := 'Debug';
        if Assigned(Proj) then
        begin
          try
            Output := VarToStr(Proj.ProjectOptions.Values['OutputDir']);
          except
            Output := '';
          end;
          if Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
          begin
            PlatformVal := Configs.ActivePlatformName;
            if Assigned(Configs.ActiveConfiguration) then
              Config := Configs.ActiveConfiguration.Name;
          end;
        end;
        if (Output = '') or (Output = '.') or (Output = '.\') or (Output = './') then
          GetProjectTargetInfo(ProjFile, IsPackage, Output, PlatformVal, Config);
        ExeFile := ResolveExePath(ProjFile, Output, PlatformVal, Config);
        LogMsg(Format('[LaunchAll] %s -> %s (exists=%s)',
          [ExtractFileName(ProjFile), ExeFile, BoolToStr(FileExists(ExeFile), True)]));

        if FileExists(ExeFile) then
        begin
          LogMsg('Executing ' + ExtractFileName(ExeFile) + '...');
          FServer.SelectedTestsJSON := '[]';
          Params := Format('--port %d -no-wait', [FServer.Port]);
          CmdLine := Format('"%s" %s', [ExeFile, Params]);
          UniqueString(CmdLine);

          FillChar(SI, SizeOf(SI), 0);
          SI.cb := SizeOf(TStartupInfo);
          FillChar(PI, SizeOf(PI), 0);
          if CreateProcess(nil, PChar(CmdLine), nil, nil, False, CREATE_NO_WINDOW, nil, PChar(ExtractFilePath(ExeFile)), SI, PI) then
          begin
            CloseHandle(PI.hProcess);
            CloseHandle(PI.hThread);
          end
          else
          begin
            LogMsg(Format('[LaunchAll] CreateProcess FAILED GetLastError=%d exe=%s',
              [GetLastError, ExeFile]));
            TStopwatch(FStopwatch).Stop;
            UpdateTimingLabels;
          end;
        end
        else
          LogMsg('[LaunchAll] Executable not found: ' + ExeFile);
      end;
    end;
  end;
  FRunningTests := False;
end;

procedure TFormDextTestRunner.RunSelectedButtonClick(Sender: TObject);
var
  Checked: TArray<string>;
begin
  Checked := GetCheckedTests;
  if (Sender = RunSelectedButton) and (Length(Checked) > 0) then
  begin
    RunActiveProjectTests('');
  end
  else if Assigned(TestsTreeView.Selected) then
  begin
    RunActiveProjectTests(GetNodeFullTestName(TestsTreeView.Selected));
  end
  else
    RunActiveProjectTests;
end;

procedure TFormDextTestRunner.ExpandAllMenuItemClick(Sender: TObject);
begin
  ExpandTestsTreeView;
end;

procedure TFormDextTestRunner.CollapseAllMenuItemClick(Sender: TObject);
begin
  TestsTreeView.Items.BeginUpdate;
  TestsTreeView.FullCollapse;
  TestsTreeView.Items.EndUpdate;
end;

procedure TFormDextTestRunner.StopButtonClick(Sender: TObject);
begin
  FRunningTests := False;
  LogMsg('Stop clicked. Terminating running test runner process...');
  if FRunningProcessHandle <> 0 then
  begin
    TerminateProcess(FRunningProcessHandle, 0);
    CloseHandle(FRunningProcessHandle);
    FRunningProcessHandle := 0;
  end;

  FWaitingForCompile := False;

  if Assigned(ProgressPanel) then
  begin
    ProgressBar.Style := pbstNormal;
    ProgressBar.Position := 0;
    ProgressPanel.Visible := False;
  end;
  TStopwatch(FStopwatch).Stop;
  UpdateTimingLabels;

  LogMsg('Test execution stopped.');
end;

function TFormDextTestRunner.FindMethodImplementationLine(const AFileName, AClassName, AMethodName: string; ADefaultLine: Integer): Integer;
var
  Strings: TStringList;
  i: Integer;
  Line: string;
  CppQualified: string;
  QualifiedProc, QualifiedFunc, BareProc, BareFunc, Dotted: string;

  function Matches(const ALine, ANeedle: string): Boolean;
  begin
    Result := (ANeedle <> '') and (ALine.StartsWith(ANeedle) or ALine.Contains(' ' + ANeedle));
  end;

begin
  // 0 = not found — callers decide fallback (never use a bogus MAP line past EOF).
  Result := 0;
  if (AMethodName = '') or not FileExists(AFileName) then
  begin
    if ADefaultLine > 0 then
      Result := ADefaultLine;
    Exit;
  end;

  Strings := TStringList.Create;
  try
    Strings.LoadFromFile(AFileName);
    if AClassName <> '' then
    begin
      QualifiedProc := ('procedure ' + AClassName + '.' + AMethodName).ToLower;
      QualifiedFunc := ('function ' + AClassName + '.' + AMethodName).ToLower;
      Dotted := (AClassName + '.' + AMethodName).ToLower;
      CppQualified := (AClassName + '::' + AMethodName).ToLower;
    end
    else
    begin
      QualifiedProc := '';
      QualifiedFunc := '';
      Dotted := '';
      CppQualified := '';
    end;
    BareProc := ('procedure ' + AMethodName).ToLower;
    BareFunc := ('function ' + AMethodName).ToLower;

    { C++: void __fastcall TFoo::TestBar()  /  TFoo::TestBar( }
    if CppQualified <> '' then
      for i := 0 to Strings.Count - 1 do
      begin
        Line := Strings[i].ToLower.Trim;
        if Line.StartsWith('//') then
          Continue;
        if Line.Contains(CppQualified) then
          Exit(i + 1);
      end;

    { Google Test: TEST(Suite, Name) / TEST_F / TEST_P }
    if (AClassName <> '') and (AMethodName <> '') then
      for i := 0 to Strings.Count - 1 do
      begin
        Line := Strings[i].Trim;
        if Line.StartsWith('//') then
          Continue;
        if TRegEx.IsMatch(Line,
          '^\s*TEST(?:_F|_P)?\s*\(\s*' + TRegEx.Escape(AClassName) +
          '\s*,\s*' + TRegEx.Escape(AMethodName) + '\s*\)') then
          Exit(i + 1);
      end;

    for i := 0 to Strings.Count - 1 do
    begin
      Line := Strings[i].ToLower.Trim;
      if Line.StartsWith('//') or Line.StartsWith('{') then
        Continue;
      if Matches(Line, QualifiedProc) or Matches(Line, QualifiedFunc) then
        Exit(i + 1);
    end;

    // Standalone procedure/function in the unit (e.g. Dext.Testing.Host.RunTests).
    for i := 0 to Strings.Count - 1 do
    begin
      Line := Strings[i].ToLower.Trim;
      if Line.StartsWith(BareProc) or Line.StartsWith(BareFunc) then
        Exit(i + 1);
    end;

    // Last resort: Class.Method token anywhere (nested / class methods).
    if Dotted <> '' then
      for i := 0 to Strings.Count - 1 do
      begin
        Line := Strings[i].ToLower;
        if Line.Contains(Dotted) and (Line.Contains('procedure') or Line.Contains('function')) then
          Exit(i + 1);
      end;

    if ADefaultLine > 0 then
      Result := ADefaultLine;
  finally
    Strings.Free;
  end;
end;

procedure TFormDextTestRunner.TestsTreeViewDblClick(Sender: TObject);
var
  Node: TTreeNode;
  i: Integer;
  TestLocation: TTestLocation;
  Detail: TTestDetailInfo;
  Frames: TArray<TDextStackFrame>;
  FileLeaf: string;
  FullName: string;
  HintLine: Integer;
  TargetLine: Integer;
  Resolved: string;
begin
  Node := TestsTreeView.Selected;
  if not Assigned(Node) or (Node.Data = nil) then Exit;

  i := Integer(Node.Data) - 1;
  if (i < 0) or (i >= FTestLocations.Count) then Exit;

  TestLocation := FTestLocations[i];
  FullName := TestLocation.ClassName + '.' + TestLocation.MethodName;
  if (TestLocation.FileName = '') or (TestLocation.Line <= 0) then
  begin
    if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
    begin
      EnrichCppLocationsFromSources;
      TestLocation := FTestLocations[i];
    end;
  end;
  if TestLocation.FileName = '' then
  begin
    LogMsg('Cannot open source: no file mapped for ' + FullName);
    Exit;
  end;

  SplitSourceFileAndLine(TestLocation.FileName, FileLeaf, HintLine);
  if FileLeaf <> '' then
    TestLocation.FileName := FileLeaf;
  if (TestLocation.Line <= 0) and (HintLine > 0) then
    TestLocation.Line := HintLine;

  Resolved := TestLocation.FileName;
  if not FileExists(Resolved) then
    Resolved := FindUnitFileByName(TestLocation.FileName);
  if (Resolved = '') or not FileExists(Resolved) then
  begin
    if FActiveProjectFile <> '' then
      Resolved := TPath.Combine(ExtractFilePath(FActiveProjectFile), TestLocation.FileName);
  end;
  if (Resolved = '') or not FileExists(Resolved) then
  begin
    LogMsg('Cannot open source (file not found): ' + TestLocation.FileName);
    Exit;
  end;

  { Failed GTest: prefer assert line from stack (e.g. :21), not TEST(...) line (:31). }
  TargetLine := 0;
  if Assigned(FTestDetails) and FTestDetails.TryGetValue(FullName, Detail) and
     (Detail.StackTrace <> '') then
  begin
    Frames := ParseStackFrames(Detail.StackTrace);
    if (Length(Frames) > 0) and (Frames[0].Line > 0) then
      TargetLine := Frames[0].Line;
    if (Length(Frames) > 0) and (Frames[0].FileName <> '') then
    begin
      FileLeaf := Frames[0].FileName;
      if FindUnitFileByName(FileLeaf) <> '' then
        Resolved := FindUnitFileByName(FileLeaf)
      else if FileExists(TPath.Combine(ExtractFilePath(FActiveProjectFile), FileLeaf)) then
        Resolved := TPath.Combine(ExtractFilePath(FActiveProjectFile), FileLeaf);
    end;
  end;
  if TargetLine <= 0 then
    TargetLine := TestLocation.Line;
  if TargetLine <= 0 then
    TargetLine := FindMethodImplementationLine(Resolved, TestLocation.ClassName,
      TestLocation.MethodName, TestLocation.Line);
  if TargetLine <= 0 then
    TargetLine := 1;

  OpenSourceFileAtLine(Resolved, TargetLine);
end;

procedure TFormDextTestRunner.ClearStackFrameNavs;
begin
  // Clear list items before freeing nav objects (Item.Data pointers).
  if Assigned(FStackFramesListView) then
    FStackFramesListView.Items.Clear;
  if Assigned(FStackFrameNavs) then
    FStackFrameNavs.Clear;
end;

procedure TFormDextTestRunner.LayoutInspectorDetails(AHasErrorMemo: Boolean; AFrameCount: Integer);
var
  ErrorLines: Integer;
  LinePx: Integer;
  MinErrorPx: Integer;
  MaxErrorPx: Integer;
  ScrollChromePx: Integer;
begin
  // Order: InfoPanel → ErrorMemo → FStackPanel(hint+list).
  // No frames: ErrorMemo fills remaining client area (alClient).
  if Assigned(InfoPanel) then
  begin
    InfoPanel.Align := alTop;
    InfoPanel.Height := ScalePx(98);
    InfoPanel.Top := 0;
  end;

  LinePx := ScalePx(18);
  MinErrorPx := ScalePx(56);
  MaxErrorPx := ScalePx(140);
  ScrollChromePx := ScalePx(40);

  if Assigned(FStackPanel) then
  begin
    FStackPanel.Parent := InspectorScroll;
    FStackPanel.Visible := AFrameCount > 0;
    if AFrameCount > 0 then
      FStackPanel.Align := alClient
    else
    begin
      FStackPanel.Align := alNone;
      FStackPanel.Height := 0;
    end;
  end;

  if Assigned(ErrorMemo) then
  begin
    ErrorMemo.AlignWithMargins := True;
    ErrorMemo.Margins.Left := 0;
    ErrorMemo.Margins.Top := 0;
    ErrorMemo.Margins.Right := 0;
    ErrorMemo.Margins.Bottom := ScalePx(4);
    if AHasErrorMemo then
    begin
      ErrorMemo.Visible := True;
      if AFrameCount > 0 then
      begin
        { Share vertical space with stack list. }
        ErrorMemo.Align := alTop;
        ErrorLines := Max(1, ErrorMemo.Lines.Count);
        ErrorMemo.Height := Max(MinErrorPx, Min(MaxErrorPx, ErrorLines * LinePx + ScrollChromePx));
      end
      else
      begin
        { Fill remaining inspector — avoids floating short memo. }
        ErrorMemo.Align := alClient;
      end;
    end
    else
    begin
      ErrorMemo.Align := alTop;
      ErrorMemo.Height := 0;
      ErrorMemo.Visible := False;
    end;
  end;

  if Assigned(FStackHintLabel) then
  begin
    FStackHintLabel.Parent := FStackPanel;
    FStackHintLabel.Align := alTop;
    FStackHintLabel.Margins.Left := ScalePx(6);
    FStackHintLabel.Margins.Top := ScalePx(4);
    FStackHintLabel.Height := ScalePx(18);
    if AFrameCount > 0 then
      FStackHintLabel.Caption := 'Stack Trace — double-click a frame to open source';
  end;

  if Assigned(FStackFramesListView) then
  begin
    FStackFramesListView.Parent := FStackPanel;
    FStackFramesListView.Align := alClient;
  end;

  if Assigned(InfoPanel) then
    InfoPanel.Top := 0;
end;

function IsSafePathLeaf(const ALeaf: string): Boolean;
var
  C: Char;
begin
  Result := False;
  if (ALeaf = '') or (Length(ALeaf) > 180) then
    Exit;
  for C in ALeaf do
    if CharInSet(C, ['<', '>', '|', '*', '?', '"', #0..#31, '(', ')', ':', ';']) then
      Exit;
  // "ITest> (PROGRAM.pas" / C++ signature fragments must never reach TPath.Combine.
  if ALeaf.Contains('::') or ALeaf.Contains(' ') then
    Exit;
  Result := True;
end;

function TFormDextTestRunner.FindUnitFileByName(const AUnitFileName: string): string;
var
  Candidate: string;
  Dir: string;
  Files: TArray<string>;
  Group: IOTAProjectGroup;
  i, p: Integer;
  ModuleServices: IOTAModuleServices;
  Project: IOTAProject;
  Roots: TList<string>;
  Target: string;

  procedure AddRoot(const APath: string);
  var
    Full: string;
  begin
    if (Roots = nil) or (APath = '') then
      Exit;
    try
      Full := ExcludeTrailingPathDelimiter(TPath.GetFullPath(APath));
    except
      Full := ExcludeTrailingPathDelimiter(APath);
    end;
    if Full = '' then
      Exit;
    if TDirectory.Exists(Full) and (Roots.IndexOf(Full) < 0) then
      Roots.Add(Full);
  end;

begin
  Result := '';
  Target := ExtractFileName(AUnitFileName);
  if (Target = '') or Target.EndsWith('.dll', True) then
    Exit;
  if not IsSafePathLeaf(Target) then
    Exit;

  if (AUnitFileName <> '') and IsSafePathLeaf(ExtractFileName(AUnitFileName)) and
     FileExists(AUnitFileName) then
    Exit(AUnitFileName);

  // Open modules + project modules (no disk walk yet)
  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
  begin
    for i := 0 to ModuleServices.ModuleCount - 1 do
      if SameText(ExtractFileName(ModuleServices.Modules[i].FileName), Target) then
        Exit(ModuleServices.Modules[i].FileName);

    Group := ModuleServices.MainProjectGroup;
    if Assigned(Group) then
      for p := 0 to Group.ProjectCount - 1 do
      begin
        Project := Group.Projects[p];
        if not Assigned(Project) then
          Continue;
        for i := 0 to Project.GetModuleCount - 1 do
          if SameText(ExtractFileName(Project.GetModule(i).FileName), Target) then
            Exit(Project.GetModule(i).FileName);
      end;
  end;

  if Assigned(FTestLocations) then
    for i := 0 to FTestLocations.Count - 1 do
      if SameText(ExtractFileName(FTestLocations[i].FileName), Target) then
        Exit(FTestLocations[i].FileName);

  Roots := TList<string>.Create;
  try
    if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    begin
      Group := ModuleServices.MainProjectGroup;
      if Assigned(Group) then
        for p := 0 to Group.ProjectCount - 1 do
          if Assigned(Group.Projects[p]) then
            AddRoot(ExtractFilePath(Group.Projects[p].FileName));
    end;

    AddRoot(ExtractFilePath(FActiveProjectFile));
    Dir := ExtractFilePath(FActiveProjectFile);
    for i := 0 to 6 do
    begin
      if Dir = '' then
        Break;
      AddRoot(TPath.Combine(Dir, 'Sources'));
      AddRoot(TPath.Combine(Dir, 'Tests'));
      if TDirectory.Exists(TPath.Combine(Dir, 'Sources')) then
        Break;
      Dir := TPath.GetDirectoryName(ExcludeTrailingPathDelimiter(Dir));
    end;

    for Dir in Roots do
    begin
      Candidate := TPath.Combine(Dir, Target);
      if FileExists(Candidate) then
        Exit(Candidate);
      try
        Files := TDirectory.GetFiles(Dir, Target, TSearchOption.soAllDirectories);
        if Length(Files) > 0 then
          Exit(Files[0]);
      except
        // ignore access errors while walking
      end;
    end;
  finally
    Roots.Free;
  end;
end;

function TFormDextTestRunner.IsUnreliableMapLocation(const AFileName: string): Boolean;
var
  Leaf: string;
  Line: Integer;
begin
  SplitSourceFileAndLine(AFileName, Leaf, Line);
  Result := (Leaf = '') or
    Leaf.StartsWith('System.', True) or
    Leaf.StartsWith('Winapi.', True) or
    Leaf.StartsWith('Vcl.', True) or
    Leaf.StartsWith('Data.', True) or
    Leaf.StartsWith('FMX.', True) or
    Leaf.EndsWith('.dll', True);
end;

function TFormDextTestRunner.UnitHintFromMethodName(const AMethodName: string): string;
var
  Acc: string;
  i, j: Integer;
  Parts: TArray<string>;
  Resolved: string;
begin
  Result := '';
  Acc := CleanStackMethodName(AMethodName);
  if (Acc = '') or Acc.ToLower.Contains('.dll') or
     Acc.StartsWith('KERNEL', True) or Acc.StartsWith('ntdll', True) then
    Exit;
  // C++ / mangled / file:line frames are not Delphi Unit.Method — do not invent ".pas".
  if Acc.Contains('::') or Acc.Contains('<') or Acc.Contains('(') or Acc.Contains(':') then
    Exit;
  if Acc.EndsWith('.cpp', True) or Acc.EndsWith('.h', True) or Acc.EndsWith('.hpp', True) or
     Acc.EndsWith('.cc', True) or Acc.EndsWith('.cxx', True) or Acc.EndsWith('.c', True) then
    Exit;
  Parts := Acc.Split(['.']);
  if Length(Parts) < 2 then
    Exit;
  { "Foo.cpp:24" split → ["Foo","cpp:24"] — never invent Foo.pas }
  if Parts[High(Parts)].Contains(':') or
     SameText(Parts[High(Parts)], 'cpp') or SameText(Parts[High(Parts)], 'h') or
     SameText(Parts[High(Parts)], 'hpp') or SameText(Parts[High(Parts)], 'pas') then
    Exit;
  // Prefer a unit that exists on disk; else show the longest dotted prefix + .pas
  for i := High(Parts) - 1 downto 0 do
  begin
    Acc := Parts[0];
    for j := 1 to i do
      Acc := Acc + '.' + Parts[j];
    Resolved := FindUnitFileByName(Acc + '.pas');
    if Resolved <> '' then
      Exit(ExtractFileName(Resolved));
  end;
  if Length(Parts) >= 2 then
  begin
    Acc := Parts[0];
    for j := 1 to High(Parts) - 1 do
      Acc := Acc + '.' + Parts[j];
    Result := Acc + '.pas';
  end;
end;

function TFormDextTestRunner.ResolveStackFrameFile(const AMethodName, AFileName: string): string;
var
  Acc: string;
  AtPos: Integer;
  CleanMethod: string;
  FileHint: string;
  FileLeaf: string;
  HintLine: Integer;
  i, j: Integer;
  Parts: TArray<string>;
  PreferMethod: Boolean;
  Raw: string;
  SafeName: string;
begin
  Result := '';
  Raw := Trim(AMethodName);
  CleanMethod := CleanStackMethodName(AMethodName);
  SplitSourceFileAndLine(AFileName, SafeName, HintLine);
  PreferMethod := IsUnreliableMapLocation(SafeName);

  { Adapter: "Method @ SmokeTestCase.cpp" (preferred) or legacy " (File.cpp)". }
  AtPos := Raw.LastIndexOf(' @ ');
  if AtPos >= 0 then
  begin
    FileHint := Trim(Raw.Substring(AtPos + 3));
    if FileHint.EndsWith(')') then
      FileHint := Trim(FileHint.Substring(0, FileHint.Length - 1));
    SplitSourceFileAndLine(FileHint, FileLeaf, HintLine);
    Result := FindUnitFileByName(FileLeaf);
    if Result <> '' then
      Exit;
  end;

  if not PreferMethod then
  begin
    Result := FindUnitFileByName(SafeName);
    if Result <> '' then
      Exit;
  end;

  // C++ Class::Method → Class.cpp / Class.h (class token only — never signatures)
  if CleanMethod.Contains('::') then
  begin
    Parts := CleanMethod.Split(['::']);
    if Length(Parts) >= 1 then
    begin
      Acc := Parts[0];
      if Acc.Contains('(') then
        Acc := Trim(Acc.Substring(0, Acc.IndexOf('(')));
      if IsSafePathLeaf(Acc + '.cpp') then
      begin
        Result := FindUnitFileByName(Acc + '.cpp');
        if Result <> '' then
          Exit;
        Result := FindUnitFileByName(Acc + '.h');
        if Result <> '' then
          Exit;
      end;
    end;
  end;

  // Delphi Unit.Method only (no :: / < / ()).
  if (not CleanMethod.Contains('::')) and (not CleanMethod.Contains('<')) then
  begin
    Parts := CleanMethod.Split(['.']);
    if Length(Parts) >= 2 then
    begin
      for i := High(Parts) - 1 downto 0 do
      begin
        Acc := Parts[0];
        for j := 1 to i do
          Acc := Acc + '.' + Parts[j];
        if not IsSafePathLeaf(Acc + '.pas') then
          Continue;
        Result := FindUnitFileByName(Acc + '.pas');
        if Result <> '' then
          Exit;
      end;
    end;
  end;

  if SafeName <> '' then
    Result := FindUnitFileByName(SafeName);
end;

procedure TFormDextTestRunner.OpenStackFrame(const AMethodName, AFileName: string; ALine: Integer);
var
  ClassName: string;
  CleanMethod: string;
  FileLeaf: string;
  FoundLine: Integer;
  HintLine: Integer;
  MethodLeaf: string;
  Parts: TArray<string>;
  ResolvedFile: string;
  TargetLine: Integer;
begin
  CleanMethod := CleanStackMethodName(AMethodName);
  if (CleanMethod.ToLower.Contains('.dll')) or
     CleanMethod.StartsWith('KERNEL', True) or
     CleanMethod.StartsWith('ntdll', True) then
  begin
    if Assigned(FStackHintLabel) then
      FStackHintLabel.Caption := 'Stack Trace — no source for OS/runtime frames';
    MessageBeep(MB_ICONWARNING);
    Exit;
  end;

  SplitSourceFileAndLine(AFileName, FileLeaf, HintLine);
  if (ALine <= 0) and (HintLine > 0) then
    ALine := HintLine;

  ResolvedFile := ResolveStackFrameFile(CleanMethod, FileLeaf);
  if (ResolvedFile = '') and (FileLeaf <> '') then
    ResolvedFile := FindUnitFileByName(FileLeaf);
  if ((ResolvedFile = '') or not FileExists(ResolvedFile)) and (FileLeaf <> '') and
     (FActiveProjectFile <> '') then
  begin
    ResolvedFile := TPath.Combine(ExtractFilePath(FActiveProjectFile), FileLeaf);
    if not FileExists(ResolvedFile) then
      ResolvedFile := '';
  end;
  if (ResolvedFile = '') or not FileExists(ResolvedFile) then
  begin
    LogMsg(Format('Could not open stack frame: method=%s file=%s leaf=%s',
      [CleanMethod, AFileName, FileLeaf]));
    if Assigned(FStackHintLabel) then
      FStackHintLabel.Caption := 'Stack Trace — could not resolve source for that frame';
    MessageBeep(MB_ICONWARNING);
    Exit;
  end;

  { Trust the Location column line — do not remap to TEST(...) via AST. }
  if ALine > 0 then
    TargetLine := ALine
  else
  begin
    TargetLine := 1;
    if CleanMethod.Contains('::') then
      Parts := CleanMethod.Split(['::'])
    else
      Parts := CleanMethod.Split(['.']);
    if Length(Parts) >= 1 then
    begin
      MethodLeaf := Parts[High(Parts)];
      if MethodLeaf.Contains('(') then
        MethodLeaf := Trim(MethodLeaf.Substring(0, MethodLeaf.IndexOf('(')));
      if Length(Parts) >= 2 then
        ClassName := Parts[High(Parts) - 1]
      else
        ClassName := '';
      FoundLine := FindMethodImplementationLine(ResolvedFile, ClassName, MethodLeaf, 0);
      if FoundLine > 0 then
        TargetLine := FoundLine;
    end;
  end;

  OpenSourceFileAtLine(ResolvedFile, TargetLine);
  if Assigned(FStackHintLabel) then
    FStackHintLabel.Caption := Format('Stack Trace — opened %s:%d',
      [ExtractFileName(ResolvedFile), TargetLine]);
end;

procedure TFormDextTestRunner.StackFramesListViewDblClick(Sender: TObject);
var
  Item: TListItem;
  Nav: TStackFrameNav;
begin
  if not Assigned(FStackFramesListView) then Exit;
  Item := FStackFramesListView.Selected;
  if not Assigned(Item) then Exit;

  Nav := nil;
  if Item.Data <> nil then
    Nav := TStackFrameNav(Item.Data);
  if not Assigned(Nav) then Exit;

  OpenStackFrame(Nav.MethodName, Nav.FileName, Nav.Line);
end;

function TFormDextTestRunner.FormatListViewRow(AItem: TListItem): string;
var
  i: Integer;
begin
  Result := '';
  if not Assigned(AItem) then
    Exit;
  Result := AItem.Caption;
  for i := 0 to AItem.SubItems.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + #9;
    Result := Result + AItem.SubItems[i];
  end;
end;

function TFormDextTestRunner.CopyListViewLines(AListView: TListView; ASelectedOnly: Boolean): string;
var
  i: Integer;
  Lines: TStringList;
  Item: TListItem;
begin
  Result := '';
  if not Assigned(AListView) then
    Exit;
  Lines := TStringList.Create;
  try
    for i := 0 to AListView.Items.Count - 1 do
    begin
      Item := AListView.Items[i];
      if ASelectedOnly and not Item.Selected then
        Continue;
      Lines.Add(FormatListViewRow(Item));
    end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

procedure TFormDextTestRunner.SetupListViewClipboard(AListView: TListView);
var
  Popup: TPopupMenu;
  Item: TMenuItem;
begin
  if not Assigned(AListView) then
    Exit;
  AListView.MultiSelect := True;
  Popup := TPopupMenu.Create(AListView);
  Item := TMenuItem.Create(Popup);
  Item.Caption := 'Copy'#9'Ctrl+C';
  Item.Tag := NativeInt(AListView);
  Item.OnClick := ListViewCopySelectedClick;
  Popup.Items.Add(Item);
  Item := TMenuItem.Create(Popup);
  Item.Caption := 'Copy All';
  Item.Tag := NativeInt(AListView);
  Item.OnClick := ListViewCopyAllClick;
  Popup.Items.Add(Item);

  // E1.9k: Coverage tab — Open HTML where the user looks at results (Actions ⋯ remains too).
  if AListView = FCoverageListView then
  begin
    Item := TMenuItem.Create(Popup);
    Item.Caption := '-';
    Popup.Items.Add(Item);
    FOpenCoverageHtmlContextMenuItem := TMenuItem.Create(Popup);
    FOpenCoverageHtmlContextMenuItem.Caption := 'Open HTML Report';
    FOpenCoverageHtmlContextMenuItem.OnClick := OpenCoverageHtmlClick;
    FOpenCoverageHtmlContextMenuItem.Enabled := False;
    Popup.Items.Add(FOpenCoverageHtmlContextMenuItem);
  end;

  AListView.PopupMenu := Popup;
  AListView.OnKeyDown := ListViewClipboardKeyDown;
end;

procedure TFormDextTestRunner.ListViewCopySelectedClick(Sender: TObject);
var
  LV: TListView;
  Text: string;
begin
  if not (Sender is TMenuItem) then Exit;
  LV := TListView(TMenuItem(Sender).Tag);
  if not Assigned(LV) then Exit;
  Text := CopyListViewLines(LV, True);
  if Text = '' then
    Text := CopyListViewLines(LV, False);
  if Text <> '' then
    Clipboard.AsText := Text;
end;

procedure TFormDextTestRunner.ListViewCopyAllClick(Sender: TObject);
var
  LV: TListView;
  Text: string;
begin
  if not (Sender is TMenuItem) then Exit;
  LV := TListView(TMenuItem(Sender).Tag);
  if not Assigned(LV) then Exit;
  Text := CopyListViewLines(LV, False);
  if Text <> '' then
    Clipboard.AsText := Text;
end;

procedure TFormDextTestRunner.ListViewClipboardKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  LV: TListView;
  Text: string;
begin
  if not (Sender is TListView) then Exit;
  LV := TListView(Sender);

  if (Key = VK_RETURN) and (LV = FStackFramesListView) then
  begin
    Key := 0;
    StackFramesListViewDblClick(Sender);
    Exit;
  end;

  if (ssCtrl in Shift) and ((Key = Ord('C')) or (Key = Ord('c'))) then
  begin
    Key := 0;
    Text := CopyListViewLines(LV, True);
    if Text = '' then
      Text := CopyListViewLines(LV, False);
    if Text <> '' then
      Clipboard.AsText := Text;
  end;
end;

procedure TFormDextTestRunner.StackFramesListViewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  ListViewClipboardKeyDown(Sender, Key, Shift);
  if Key = VK_RETURN then
  begin
    Key := 0;
    StackFramesListViewDblClick(Sender);
  end;
end;

procedure TFormDextTestRunner.ConsoleListViewDblClick(Sender: TObject);
const
  FailedPrefix = 'FAILED: ';
  SkippedPrefix = 'SKIPPED: ';
var
  Item: TListItem;
  Msg: string;
  Node: TTreeNode;
  TestName: string;
begin
  if not Assigned(FConsoleListView) then Exit;
  Item := FConsoleListView.Selected;
  if not Assigned(Item) or (Item.SubItems.Count < 2) then Exit;

  Msg := Item.SubItems[1];
  TestName := '';
  if Msg.StartsWith(FailedPrefix) then
    TestName := Msg.Substring(Length(FailedPrefix))
  else if Msg.StartsWith(SkippedPrefix) then
    TestName := Msg.Substring(Length(SkippedPrefix));

  if TestName = '' then Exit;

  Node := FindNodeByPath(TestName);
  if not Assigned(Node) then Exit;

  TestsTreeView.Selected := Node;
  Node.MakeVisible;
  UpdateTestInspector(GetNodeFullTestName(Node));
  if Assigned(DetailsPageControl) and Assigned(InspectorTab) then
    DetailsPageControl.ActivePage := InspectorTab;
end;

function TFormDextTestRunner.GetCheckedTests: TArray<string>;
var
  i: Integer;
  Node: TTreeNode;
  List: TList<string>;
begin
  List := TList<string>.Create;
  try
    for i := 0 to TestsTreeView.Items.Count - 1 do
    begin
      Node := TestsTreeView.Items[i];
      if (Node.Parent <> nil) and Node.Checked then
      begin
        List.Add(GetNodeFullTestName(Node));
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TFormDextTestRunner.GetRunButtonRect(ANode: TTreeNode): TRect;
var
  TextRect: TRect;
  PPI: Integer;
  ButtonWidth, ButtonHeight, Offset: Integer;
begin
  PPI := Self.CurrentPPI;
  if PPI = 0 then
    PPI := 96;

  ButtonWidth := MulDiv(20, PPI, 96);
  ButtonHeight := MulDiv(13, PPI, 96);
  Offset := MulDiv(8, PPI, 96);

  TextRect := ANode.DisplayRect(True);
  Result.Left := TextRect.Right + Offset;
  Result.Top := TextRect.Top + (TextRect.Height - ButtonHeight) div 2;
  Result.Right := Result.Left + ButtonWidth;
  Result.Bottom := Result.Top + ButtonHeight;
end;

procedure TFormDextTestRunner.TestsTreeViewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  TreeView: TTreeView;
  Node: TTreeNode;
  OldNode: TTreeNode;
  ButtonRect: TRect;
  Rect: TRect;
begin
  TreeView := Sender as TTreeView;
  Node := TreeView.GetNodeAt(X, Y);

  if Node <> FHoverNode then
  begin
    OldNode := FHoverNode;
    FHoverNode := Node;

    if Assigned(OldNode) then
    begin
      Rect := OldNode.DisplayRect(False);
      Rect.Right := TreeView.ClientWidth;
      InvalidateRect(TreeView.Handle, @Rect, True);
    end;

    if Assigned(FHoverNode) then
    begin
      Rect := FHoverNode.DisplayRect(False);
      Rect.Right := TreeView.ClientWidth;
      InvalidateRect(TreeView.Handle, @Rect, True);
    end;
  end;

  if Assigned(FHoverNode) and (FHoverNode.Parent <> nil) then
  begin
    ButtonRect := GetRunButtonRect(FHoverNode);
    if PtInRect(ButtonRect, Point(X, Y)) then
    begin
      TreeView.Cursor := crHandPoint;
      Exit;
    end;
  end;

  TreeView.Cursor := crDefault;
end;

procedure TFormDextTestRunner.TestsTreeViewMouseLeave(Sender: TObject);
var
  TreeView: TTreeView;
  OldNode: TTreeNode;
  Rect: TRect;
begin
  TreeView := Sender as TTreeView;
  if Assigned(FHoverNode) then
  begin
    OldNode := FHoverNode;
    FHoverNode := nil;
    Rect := OldNode.DisplayRect(False);
    Rect.Right := TreeView.ClientWidth;
    InvalidateRect(TreeView.Handle, @Rect, True);
  end;
end;

procedure TFormDextTestRunner.TestsTreeViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Node: TTreeNode;
  ButtonRect: TRect;
  HitInfo: THitTests;
  i: Integer;
begin
  if Button = mbLeft then
  begin
    Node := TestsTreeView.GetNodeAt(X, Y);
    if Assigned(Node) then
    begin
      HitInfo := TestsTreeView.GetHitTestInfoAt(X, Y);
      if htOnStateIcon in HitInfo then
      begin
        if not IsTestingDesignShuttingDown then
        TThread.ForceQueue(nil, TThreadProcedure(procedure
          var
            i: Integer;
            NodeChecked: Boolean;
            ParentNode: TTreeNode;
            AnyChecked: Boolean;
          begin
            if IsTestingDesignShuttingDown then
              Exit;
            if not Assigned(FormDextTestRunner) or (csDestroying in FormDextTestRunner.ComponentState) then
              Exit;
            if not Assigned(Node) or not Assigned(TestsTreeView) then Exit;
            NodeChecked := Node.Checked;
            if Node.Parent = nil then
            begin
              TestsTreeView.Items.BeginUpdate;
              try
                for i := 0 to Node.Count - 1 do
                  Node.Item[i].Checked := NodeChecked;
              finally
                TestsTreeView.Items.EndUpdate;
              end;
            end
            else
            begin
              ParentNode := Node.Parent;
              AnyChecked := False;
              for i := 0 to ParentNode.Count - 1 do
              begin
                if ParentNode.Item[i].Checked then
                begin
                  AnyChecked := True;
                  Break;
                end;
              end;
              ParentNode.Checked := AnyChecked;
            end;
            UpdateSummaryCounts;
            TestsTreeView.Invalidate;
          end));
      end;

      if Node.Parent <> nil then
      begin
        ButtonRect := GetRunButtonRect(Node);
        if PtInRect(ButtonRect, Point(X, Y)) then
        begin
          TestsTreeView.Selected := Node;
          
          TestsTreeView.Items.BeginUpdate;
          try
            for i := 0 to TestsTreeView.Items.Count - 1 do
              TestsTreeView.Items[i].Checked := False;
            Node.Checked := True;
            if Node.Parent <> nil then
              Node.Parent.Checked := True;
          finally
            TestsTreeView.Items.EndUpdate;
          end;
          UpdateSummaryCounts;
          TestsTreeView.Invalidate;

          RunActiveProjectTests(GetNodeFullTestName(Node));
        end;
      end;
    end;
  end;
end;

procedure TFormDextTestRunner.TestsTreeViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Node: TTreeNode;
  HitInfo: THitTests;
begin
  if Button = mbLeft then
  begin
    Node := TestsTreeView.GetNodeAt(X, Y);
    if Assigned(Node) then
    begin
      HitInfo := TestsTreeView.GetHitTestInfoAt(X, Y);
      if htOnStateIcon in HitInfo then
      begin
        if not IsTestingDesignShuttingDown then
        TThread.ForceQueue(nil, TThreadProcedure(procedure
          var
            i: Integer;
            LState: Boolean;
            ParentNode: TTreeNode;
            AnyChecked: Boolean;
          begin
            if IsTestingDesignShuttingDown then
              Exit;
            if not Assigned(FormDextTestRunner) or (csDestroying in FormDextTestRunner.ComponentState) then
              Exit;
            if not Assigned(Node) or not Assigned(TestsTreeView) then Exit;
            LState := Node.Checked;
            if Node.Parent = nil then
            begin
              TestsTreeView.Items.BeginUpdate;
              try
                for i := 0 to Node.Count - 1 do
                  Node.Item[i].Checked := LState;
              finally
                TestsTreeView.Items.EndUpdate;
              end;
            end
            else
            begin
              ParentNode := Node.Parent;
              AnyChecked := False;
              for i := 0 to ParentNode.Count - 1 do
              begin
                if ParentNode.Item[i].Checked then
                begin
                  AnyChecked := True;
                  Break;
                end;
              end;
              ParentNode.Checked := AnyChecked;
            end;
            UpdateSummaryCounts;
            TestsTreeView.Invalidate;
          end));
      end;
    end;
  end;
end;

function TFormDextTestRunner.GetNodeFullTestName(ANode: TTreeNode): string;
var
  ParentText: string;
  SpaceIndex: Integer;
  TestIndex: Integer;
  TestLocation: TTestLocation;
begin
  Result := '';
  if not Assigned(ANode) then Exit;

  if (ANode.Data <> nil) and Assigned(FTestLocations) then
  begin
    TestIndex := Integer(ANode.Data) - 1;
    if (TestIndex >= 0) and (TestIndex < FTestLocations.Count) then
    begin
      TestLocation := FTestLocations[TestIndex];
      Result := TestLocation.ClassName + '.' + TestLocation.MethodName;
      Exit;
    end;
  end;

  if FGroupingMode = tgmStatus then
  begin
    if ANode.Parent <> nil then
      Result := ANode.Text // Under status grouping, leaf nodes hold 'ClassName.MethodName'
    else
      Result := '';
    Exit;
  end;

  if ANode.Parent = nil then
  begin
    ParentText := ANode.Text;
    SpaceIndex := ParentText.IndexOf(' (');
    if SpaceIndex > 0 then
      Result := ParentText.Substring(0, SpaceIndex)
    else
      Result := ParentText;
  end
  else
  begin
    ParentText := ANode.Parent.Text;
    SpaceIndex := ParentText.IndexOf(' (');
    if SpaceIndex > 0 then
      ParentText := ParentText.Substring(0, SpaceIndex);
    Result := ParentText + '.' + ANode.Text;
  end;
end;

procedure TFormDextTestRunner.FilterEditChange(Sender: TObject);
begin
  if (FActiveSession <> nil) and (FActiveSession.ClearFilterButton <> nil) then
    FActiveSession.ClearFilterButton.Visible := Trim(ActiveFilterEdit.Text) <> '';
  RefreshTreeView;
end;

procedure TFormDextTestRunner.LayoutMenuClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    TabbedLayoutMenuItem.Checked := Sender = TabbedLayoutMenuItem;
    SplitBottomLayoutMenuItem.Checked := Sender = SplitBottomLayoutMenuItem;
    SplitRightLayoutMenuItem.Checked := Sender = SplitRightLayoutMenuItem;
    ApplyLayout(TTestExplorerLayout(TMenuItem(Sender).Tag));
  end;
end;

procedure TFormDextTestRunner.GroupingMenuClick(Sender: TObject);
var
  IniFile: TMemIniFile;
begin
  if Sender is TMenuItem then
  begin
    GroupByClassMenuItem.Checked := Sender = GroupByClassMenuItem;
    GroupByTestStatusMenuItem.Checked := Sender = GroupByTestStatusMenuItem;

    FGroupingMode := TTestGroupingMode(TMenuItem(Sender).Tag - 100);

    // Save grouping mode to ini file
    try
      IniFile := TMemIniFile.Create(TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini'));
      try
        IniFile.WriteInteger('Grouping', 'Mode', Ord(FGroupingMode));
        IniFile.UpdateFile;
      finally
        IniFile.Free;
      end;
    except
    end;

    RefreshTreeView;
  end;
end;

function TFormDextTestRunner.ActiveFilterEdit: TEdit;
begin
  if FActiveSession <> nil then
    Result := FActiveSession.FilterEdit
  else
    Result := nil;
end;

procedure TFormDextTestRunner.ClearFilterButtonClick(Sender: TObject);
var
  ActiveFilter: TEdit;
begin
  ActiveFilter := ActiveFilterEdit;
  if Assigned(ActiveFilter) then
  begin
    ActiveFilter.Text := '';
    ActiveFilter.SetFocus;
  end;
end;

procedure TFormDextTestRunner.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  ActiveFilter: TEdit;
begin
  if (Key = Ord('F')) and (ssCtrl in Shift) then
  begin
    ActiveFilter := ActiveFilterEdit;
    if Assigned(ActiveFilter) then
    begin
      ActiveFilter.SetFocus;
      Key := 0;
    end;
  end
  else if Key = VK_ESCAPE then
  begin
    ActiveFilter := ActiveFilterEdit;
    if Assigned(ActiveFilter) and (ActiveFilter.Text <> '') then
    begin
      ActiveFilter.Text := '';
      Key := 0;
    end;
  end;
end;

procedure TFormDextTestRunner.ApplyLayout(ALayout: TTestExplorerLayout);
var
  IniFile: TMemIniFile;
begin
  FCurrentLayout := ALayout;

  try
    IniFile := TMemIniFile.Create(TPath.Combine(TPath.GetHomePath, 'DextTestExplorer.ini'));
    try
      IniFile.WriteInteger('Layout', 'Mode', Ord(ALayout));
      IniFile.UpdateFile;
    finally
      IniFile.Free;
    end;
  except
    // ignore
  end;

  DetailsMemo.Align := alNone;
  if Assigned(FConsoleListView) then
    FConsoleListView.Align := alNone;
  InspectorScroll.Align := alNone;
  FInspectorSplitter.Visible := False;

  case ALayout of
    telCompact:
    begin
      NameSplitter.Align := alBottom;
      NameSplitter.Cursor := crVSplit;
      DetailsPanel.Align := alBottom;
      DetailsPanel.Height := 320;

      DetailsPageControl.Visible := True;
      DetailsMemo.Parent := ConsoleTab;
      DetailsMemo.Align := alClient;
      DetailsMemo.AlignWithMargins := False;
      DetailsMemo.Visible := False; // E1.7: FConsoleListView is the visible console surface
      if Assigned(FConsoleListView) then
      begin
        FConsoleListView.Parent := ConsoleTab;
        FConsoleListView.Align := alClient;
        FConsoleListView.AlignWithMargins := False;
        FConsoleListView.Visible := True;
      end;
      InspectorScroll.Parent := InspectorTab;
      InspectorScroll.Align := alClient;
      InspectorScroll.AlignWithMargins := False;
      // Stack frames stay inside InspectorScroll (see LayoutInspectorDetails).
      NameSplitter.Top := InspectorScroll.Top - NameSplitter.Height;
    end;

    telSplitBottom:
    begin
      NameSplitter.Align := alBottom;
      NameSplitter.Cursor := crVSplit;
      DetailsPanel.Align := alBottom;
      DetailsPanel.Height := 150;

      DetailsPageControl.Visible := False;

      DetailsMemo.Parent := DetailsPanel;
      DetailsMemo.Align := alLeft;
      DetailsMemo.Width := DetailsPanel.Width div 2;
      DetailsMemo.AlignWithMargins := True;
      DetailsMemo.Margins.Left := 6;
      DetailsMemo.Margins.Right := 0;
      DetailsMemo.Margins.Top := 6;
      DetailsMemo.Margins.Bottom := 6;
      DetailsMemo.Visible := False; // E1.7: FConsoleListView is the visible console surface

      if Assigned(FConsoleListView) then
      begin
        FConsoleListView.Parent := DetailsPanel;
        FConsoleListView.Align := alLeft;
        FConsoleListView.Width := DetailsPanel.Width div 2;
        FConsoleListView.AlignWithMargins := True;
        FConsoleListView.Margins.Left := 6;
        FConsoleListView.Margins.Right := 0;
        FConsoleListView.Margins.Top := 6;
        FConsoleListView.Margins.Bottom := 6;
        FConsoleListView.Visible := True;
      end;

      FInspectorSplitter.Parent := DetailsPanel;
      FInspectorSplitter.Align := alLeft;
      FInspectorSplitter.Cursor := crHSplit;
      FInspectorSplitter.Width := 6;
      FInspectorSplitter.Visible := True;

      InspectorScroll.Parent := DetailsPanel;
      InspectorScroll.Align := alClient;
      InspectorScroll.AlignWithMargins := True;
      InspectorScroll.Margins.Left := 0;
      InspectorScroll.Margins.Right := 6;
      InspectorScroll.Margins.Top := 6;
      InspectorScroll.Margins.Bottom := 6;
      NameSplitter.Top := InspectorScroll.Top - NameSplitter.Height;
    end;

    telSplitRight:
    begin
      NameSplitter.Align := alRight;
      NameSplitter.Cursor := crHSplit;
      DetailsPanel.Align := alRight;
      DetailsPanel.Width := 320;

      DetailsPageControl.Visible := False;

      DetailsMemo.Parent := DetailsPanel;
      DetailsMemo.Align := alBottom;
      DetailsMemo.Height := DetailsPanel.Height div 2;
      DetailsMemo.AlignWithMargins := True;
      DetailsMemo.Margins.Left := 6;
      DetailsMemo.Margins.Right := 6;
      DetailsMemo.Margins.Top := 0;
      DetailsMemo.Margins.Bottom := 6;
      DetailsMemo.Visible := False; // E1.7: FConsoleListView is the visible console surface

      if Assigned(FConsoleListView) then
      begin
        FConsoleListView.Parent := DetailsPanel;
        FConsoleListView.Align := alBottom;
        FConsoleListView.Height := DetailsPanel.Height div 2;
        FConsoleListView.AlignWithMargins := True;
        FConsoleListView.Margins.Left := 6;
        FConsoleListView.Margins.Right := 6;
        FConsoleListView.Margins.Top := 0;
        FConsoleListView.Margins.Bottom := 6;
        FConsoleListView.Visible := True;
      end;

      FInspectorSplitter.Parent := DetailsPanel;
      FInspectorSplitter.Align := alBottom;
      FInspectorSplitter.Cursor := crVSplit;
      FInspectorSplitter.Height := 6;
      FInspectorSplitter.Visible := True;

      InspectorScroll.Parent := DetailsPanel;
      InspectorScroll.Align := alClient;
      InspectorScroll.AlignWithMargins := True;
      InspectorScroll.Margins.Left := 0;
      InspectorScroll.Margins.Right := 0;
      InspectorScroll.Margins.Top := 6;
      InspectorScroll.Margins.Bottom := 0;
    end;
  end;

  // Ensure correct Z-order of aligned controls to make Splitter work correctly
  DetailsPanel.SendToBack;
  NameSplitter.SendToBack;
end;

procedure TFormDextTestRunner.RefreshTreeView;
var
  ActiveFilterEdit: TEdit;
  ClassMatches: Boolean;
  DetailInfo: TTestDetailInfo;
  FailedNode, PassedNode, SkippedNode, IdleNode: TTreeNode;
  Filter: string;
  FixtureNode, MethodNode: TTreeNode;
  FixtureNodeCache: TDictionary<string, TTreeNode>;
  FixtureTestsCount: TDictionary<string, Integer>;
  FullTestName: string;
  i: Integer;
  MethodMatches: Boolean;
  Status: string;
  TargetRoot: TTreeNode;
  TestLocation: TTestLocation;
begin
  ClearNodeIndex;
  TestsTreeView.Items.BeginUpdate;
  try
    TestsTreeView.Items.Clear;
    InitializeGroupSummaries;
    FixtureNodeCache := TDictionary<string, TTreeNode>.Create;
    try
    Filter := '';
    ActiveFilterEdit := Self.ActiveFilterEdit;
    if Assigned(ActiveFilterEdit) then
      Filter := Trim(ActiveFilterEdit.Text);

    if FGroupingMode = tgmStatus then
    begin
      FailedNode := nil;
      PassedNode := nil;
      SkippedNode := nil;
      IdleNode := nil;

      for i := 0 to FTestLocations.Count - 1 do
      begin
        TestLocation := FTestLocations[i];
        ClassMatches := (Filter = '') or TestLocation.ClassName.ToLower.Contains(Filter.ToLower);
        MethodMatches := (Filter = '') or TestLocation.MethodName.ToLower.Contains(Filter.ToLower);

        if ClassMatches or MethodMatches then
        begin
          FullTestName := TestLocation.ClassName + '.' + TestLocation.MethodName;
          Status := 'Idle';
          if FTestDetails.TryGetValue(FullTestName, DetailInfo) then
            Status := DetailInfo.Status;

          if SameText(Status, 'Failed') or SameText(Status, 'Error') then
          begin
            if not Assigned(FailedNode) then
            begin
              FailedNode := TestsTreeView.Items.AddChild(nil, 'Failed');
              FailedNode.ImageIndex := 2;
              FailedNode.SelectedIndex := 2;
              if Filter <> '' then FailedNode.Expanded := True;
            end;
            TargetRoot := FailedNode;
          end
          else if SameText(Status, 'Passed') or SameText(Status, 'Success') then
          begin
            if not Assigned(PassedNode) then
            begin
              PassedNode := TestsTreeView.Items.AddChild(nil, 'Passed');
              PassedNode.ImageIndex := 1;
              PassedNode.SelectedIndex := 1;
              if Filter <> '' then PassedNode.Expanded := True;
            end;
            TargetRoot := PassedNode;
          end
          else if SameText(Status, 'Skipped') then
          begin
            if not Assigned(SkippedNode) then
            begin
              SkippedNode := TestsTreeView.Items.AddChild(nil, 'Skipped');
              SkippedNode.ImageIndex := 0;
              SkippedNode.SelectedIndex := 0;
              if Filter <> '' then SkippedNode.Expanded := True;
            end;
            TargetRoot := SkippedNode;
          end
          else
          begin
            if not Assigned(IdleNode) then
            begin
              IdleNode := TestsTreeView.Items.AddChild(nil, 'Idle');
              IdleNode.ImageIndex := 0;
              IdleNode.SelectedIndex := 0;
              if Filter <> '' then IdleNode.Expanded := True;
            end;
            TargetRoot := IdleNode;
          end;

          MethodNode := TestsTreeView.Items.AddChild(TargetRoot, TestLocation.ClassName + '.' + TestLocation.MethodName);
          MethodNode.Data := Pointer(i + 1);

          if SameText(Status, 'Failed') or SameText(Status, 'Error') then
          begin
            MethodNode.ImageIndex := 2;
            MethodNode.SelectedIndex := 2;
          end
          else if SameText(Status, 'Passed') or SameText(Status, 'Success') then
          begin
            MethodNode.ImageIndex := 1;
            MethodNode.SelectedIndex := 1;
          end;
        end;
      end;
    end
    else
    begin
      FixtureTestsCount := TDictionary<string, Integer>.Create;
      try
        for i := 0 to FTestLocations.Count - 1 do
        begin
          TestLocation := FTestLocations[i];
          ClassMatches := (Filter = '') or TestLocation.ClassName.ToLower.Contains(Filter.ToLower);
          MethodMatches := (Filter = '') or TestLocation.MethodName.ToLower.Contains(Filter.ToLower);

          if ClassMatches or MethodMatches then
          begin
            if FixtureTestsCount.ContainsKey(TestLocation.ClassName) then
              FixtureTestsCount[TestLocation.ClassName] := FixtureTestsCount[TestLocation.ClassName] + 1
            else
              FixtureTestsCount.Add(TestLocation.ClassName, 1);
          end;
        end;

        for i := 0 to FTestLocations.Count - 1 do
        begin
          TestLocation := FTestLocations[i];
          ClassMatches := (Filter = '') or TestLocation.ClassName.ToLower.Contains(Filter.ToLower);
          MethodMatches := (Filter = '') or TestLocation.MethodName.ToLower.Contains(Filter.ToLower);

          if ClassMatches or MethodMatches then
          begin
            if not FixtureNodeCache.TryGetValue(TestLocation.ClassName, FixtureNode) then
            begin
              FixtureNode := TestsTreeView.Items.AddChild(nil, TestLocation.ClassName);
              FixtureNode.ImageIndex := 3;
              FixtureNode.SelectedIndex := 3;
              FixtureNodeCache.Add(TestLocation.ClassName, FixtureNode);
              if Filter <> '' then FixtureNode.Expanded := True;
            end;

            MethodNode := TestsTreeView.Items.AddChild(FixtureNode, TestLocation.MethodName);
            MethodNode.Data := Pointer(i + 1);

            FullTestName := TestLocation.ClassName + '.' + TestLocation.MethodName;
            Status := 'Idle';
            if FTestDetails.TryGetValue(FullTestName, DetailInfo) then
              Status := DetailInfo.Status;

            if SameText(Status, 'Failed') or SameText(Status, 'Error') then
            begin
              MethodNode.ImageIndex := 2;
              MethodNode.SelectedIndex := 2;
            end
            else if SameText(Status, 'Passed') or SameText(Status, 'Success') then
            begin
              MethodNode.ImageIndex := 1;
              MethodNode.SelectedIndex := 1;
            end
            else if SameText(Status, 'Skipped') then
            begin
              MethodNode.ImageIndex := 0;
              MethodNode.SelectedIndex := 0;
            end
            else
            begin
              MethodNode.ImageIndex := 0;
              MethodNode.SelectedIndex := 0;
            end;
          end;
        end;
      finally
        FixtureTestsCount.Free;
      end;
    end;

    finally
      FixtureNodeCache.Free;
    end;
  finally
    TestsTreeView.Items.EndUpdate;
  end;
  BuildNodeIndex;
end;

procedure TFormDextTestRunner.TestsTreeViewAdvancedCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState; Stage: TCustomDrawStage; var PaintImages, DefaultDraw: Boolean);
var
  ButtonRect: TRect;
  Rect: TRect;
  TextX, TextY: Integer;
  ClassName: string;
  CountText: string;
  FailedCount: Integer;
  PassedCount: Integer;
  TotalDuration: Double;
  HasDuration: Boolean;
  FullTestName: string;
  Info: TTestDetailInfo;
  DurText: string;
  ErrText: string;
  Summary: TGroupSummaryInfo;
begin
  DefaultDraw := True;

  if (Stage = cdPrePaint) and (Node <> nil) then
  begin
    if not (cdsSelected in State) then
    begin
      Sender.Canvas.Brush.Color := TTreeView(Sender).Color;
      Sender.Canvas.Font.Color := TTreeView(Sender).Font.Color;
    end;

    if Node.Parent = nil then
      Sender.Canvas.Font.Style := [fsBold]
    else
      Sender.Canvas.Font.Style := [];
  end;

  if (Stage = cdPostPaint) and (Node <> nil) then
  begin
    Sender.Canvas.Brush.Style := bsClear;
    Rect := Node.DisplayRect(True);
    TextX := Rect.Right + 6;
    TextY := Rect.Top + (Rect.Height - Sender.Canvas.TextHeight('W')) div 2;

    if Node.Parent = nil then
    begin
      ClassName := Node.Text;
      FailedCount := 0;
      PassedCount := 0;
      TotalDuration := 0;
      HasDuration := False;
      if Assigned(FGroupSummaries) and FGroupSummaries.TryGetValue(ClassName, Summary) then
      begin
        FailedCount := Summary.FailedCount;
        PassedCount := Summary.PassedCount;
        TotalDuration := Summary.DurationMs;
        HasDuration := Summary.DurationMs > 0;
      end;

      // Draw (N Tests in X ms) and execution status
      Sender.Canvas.Font.Color := clGrayText;
      Sender.Canvas.Font.Style := [];

      if HasDuration then
        CountText := ' (' + Node.Count.ToString + ' Tests in ' + Format('%.4f ms', [TotalDuration]) + ')'
      else
        CountText := ' (' + Node.Count.ToString + ' Tests)';
      Sender.Canvas.TextOut(TextX, TextY, CountText);
      TextX := TextX + Sender.Canvas.TextWidth(CountText) + 6;

      if FailedCount > 0 then
      begin
        Sender.Canvas.Font.Color := TColor($4444EF); // Red BGR
        Sender.Canvas.TextOut(TextX, TextY, 'Failed: ' + FailedCount.ToString + ' tests failed');
      end
      else if (PassedCount > 0) and (PassedCount = Node.Count) then
      begin
        Sender.Canvas.Font.Color := TColor($5EC522); // Green BGR
        Sender.Canvas.TextOut(TextX, TextY, 'Success');
      end;
    end
    else
    begin
      FullTestName := GetNodeFullTestName(Node);
      if FTestDetails.TryGetValue(FullTestName, Info) then
      begin
        if (Info.Status <> '') and not SameText(Info.Status, 'Idle') then
        begin
          if Info.DurationMs < 1.0 then
            DurText := Format('[%.3f ms]', [Info.DurationMs])
          else
            DurText := Format('[%.2f ms]', [Info.DurationMs]);

          Sender.Canvas.Font.Color := clGrayText;
          Sender.Canvas.Font.Style := [];
          Sender.Canvas.TextOut(TextX, TextY, DurText);
          TextX := TextX + Sender.Canvas.TextWidth(DurText) + 6;

          if SameText(Info.Status, 'Passed') then
          begin
            Sender.Canvas.Font.Color := TColor($5EC522); // Green BGR
            Sender.Canvas.TextOut(TextX, TextY, 'Success');
          end
          else if SameText(Info.Status, 'Failed') or SameText(Info.Status, 'Error') then
          begin
            Sender.Canvas.Font.Color := TColor($4444EF); // Red BGR
            ErrText := 'Failed';
            if Info.ErrorMessage <> '' then
              ErrText := 'Failed: ' + Info.ErrorMessage.Replace(#13, '').Replace(#10, ' ');
            if Length(ErrText) > 60 then
              ErrText := Copy(ErrText, 1, 57) + '...';
            Sender.Canvas.TextOut(TextX, TextY, ErrText);
          end;
        end;
      end;

      if Node = FHoverNode then
      begin
        ButtonRect := GetRunButtonRect(Node);
        Sender.Canvas.Brush.Color := TColor($E7FCDC); // Light Green BGR
        Sender.Canvas.Pen.Color := TColor($5EC522); // Green BGR
        Sender.Canvas.RoundRect(ButtonRect.Left, ButtonRect.Top, ButtonRect.Right, ButtonRect.Bottom, 4, 4);
        Sender.Canvas.Font.Color := TColor($3D8015); // Dark Green BGR
        Sender.Canvas.Font.Size := 7;
        Sender.Canvas.Font.Style := [fsBold];
        Sender.Canvas.Brush.Style := bsClear;
        DrawText(Sender.Canvas.Handle, #$25B6, -1, ButtonRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
      end;
    end;
  end;
end;

procedure TFormDextTestRunner.DebugSelectedClick(Sender: TObject);
var
  Node: TTreeNode;
  Proj: IOTAProject;
  NTAServices: INTAServices;
  FoundAction: TContainedAction;
  Params: string;
  IsPackage: Boolean;
  Output: string;
  ExeFile: string;
  ModuleServices: IOTAModuleServices;
  Group: IOTAProjectGroup;
  ProjInfo: TDextProjectInfo;
  SaveServices: IOTAModuleServices;
  i: Integer;
  Act: TContainedAction;
begin
  Node := TestsTreeView.Selected;
  if not Assigned(Node) then Exit;

  ProjInfo := TDextProjectInfo(ProjectsComboBox.Items.Objects[ProjectsComboBox.ItemIndex]);
  if not Assigned(ProjInfo) then Exit;
  Proj := GetProjectByFileName(ProjInfo.FileName);
  if not Assigned(Proj) then Exit;

  // Synchronize IDE Active Project
  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) and Assigned(ModuleServices) then
  begin
    Group := ModuleServices.MainProjectGroup;
    if Assigned(Group) and (Group.ActiveProject <> Proj) then
    begin
      Group.ActiveProject := Proj;
    end;
  end;

  ClearTestStatus;
  DetailsMemo.Clear;
  if Assigned(FConsoleListView) then
    FConsoleListView.Items.Clear;
  FTotalTests := 0;
  FCompletedTests := 0;
  if Assigned(ProgressPanel) then
  begin
    ProgressBar.Position := 0;
    ProgressBar.Max := 100;
    ProgressLabel.Caption := '...';
    ProgressPanel.Visible := True;
  end;
  // Focus Console Log
  if Assigned(DetailsPageControl) and Assigned(ConsoleTab) then
    DetailsPageControl.ActivePage := ConsoleTab;
  LogMsg('Compiling project (Debug): ' + ExtractFileName(FActiveProjectFile));

  // Save all modified IDE files before compiling.
  if Supports(BorlandIDEServices, IOTAModuleServices, SaveServices) then
  begin
    LogMsg('Saving all modified files...');
    SaveServices.SaveAll;
  end;

  IsPackage := False;
  Output := '';
  GetProjectTargetInfo(FActiveProjectFile, IsPackage, Output);
  ExeFile := ResolveExePath(FActiveProjectFile, Output);

  if not CompileProjectDirect(FActiveProjectFile) then
  begin
    LogMsg('Direct DCC compile failed or bypassed. Falling back to IDE make...');
    Proj.ProjectBuilder.BuildProject(cmOTAMake, False, False);
  end;

  if not FileExists(ExeFile) then
  begin
    LogMsg('Error: Executable not found at ' + ExeFile);
    Exit;
  end;

  Params := Format('--port %d -no-wait', [FServer.Port]);
  FServer.SelectedTestsJSON := '["' + GetNodeFullTestName(Node) + '"]';

  LogMsg('Starting debugger with parameters: ' + Params);
  Proj.ProjectOptions.Values['RunParams'] := Params;

  FoundAction := nil;
  if Supports(BorlandIDEServices, INTAServices, NTAServices) then
  begin
    if NTAServices.ActionList <> nil then
    begin
      for i := 0 to NTAServices.ActionList.ActionCount - 1 do
      begin
        Act := NTAServices.ActionList.Actions[i];
        if SameText(Act.Name, 'actRun') or SameText(Act.Name, 'actRunRun') or
           SameText(Act.Name, 'actRunProgram') or (Act.ShortCut = ShortCut(VK_F9, [])) then
        begin
          FoundAction := Act;
          Break;
        end;
      end;
    end;
  end;

  if FoundAction <> nil then
  begin
    if not IsTestingDesignShuttingDown then
      TThread.Queue(nil, TThreadProcedure(procedure
        begin
          if IsTestingDesignShuttingDown then
            Exit;
          if Assigned(FoundAction) then
            FoundAction.Execute;
        end));
  end
  else
  begin
    LogMsg('Warning: Could not trigger debugger automatically.');
    LogMsg('Please press F9 (Run) manually in the IDE to start debugging.');
  end;
end;

procedure TFormDextTestRunner.RefreshButtonClick(Sender: TObject);
begin
  RefreshProjects;
  if FActiveProjectFile = '' then
    Exit;
  LogMsg('Refresh: ' + ExtractFileName(FActiveProjectFile));
  if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
    DiscoverCppProjectTests { Host --discover if exe exists; else AST — never auto-build }
  else
    RefreshActiveProjectTestsList;
end;

procedure TFormDextTestRunner.SetActiveSession(ASession: TTestSession);
var
  ThemingServices: IOTAIDEThemingServices;
  ActiveIndex: Integer;
  i: Integer;
  ProjInfo: TDextProjectInfo;
begin
  if ASession = nil then Exit;
  FActiveSession := ASession;

  TestsTreeView := ASession.TreeView;
  FTestLocations := ASession.TestLocations;
  FActiveProjectFile := ASession.ActiveProjectFile;

  if ProjectsComboBox.Items.Count > 0 then
  begin
    ActiveIndex := -1;
    for i := 0 to ProjectsComboBox.Items.Count - 1 do
    begin
      ProjInfo := TDextProjectInfo(ProjectsComboBox.Items.Objects[i]);
      if Assigned(ProjInfo) and (ProjInfo.FileName = FActiveProjectFile) then
      begin
        ActiveIndex := i;
        Break;
      end;
    end;
    ProjectsComboBox.ItemIndex := ActiveIndex;
  end;

  if Supports(BorlandIDEServices, IOTAIDEThemingServices, ThemingServices) then
  begin
    if ThemingServices.IDEThemingEnabled then
    begin
      TestsTreeView.Color := ThemingServices.StyleServices.GetSystemColor(clWindow);
      TestsTreeView.Font.Color := ThemingServices.StyleServices.GetSystemColor(clWindowText);
    end;
  end;
end;

procedure TFormDextTestRunner.SessionsPageControlChange(Sender: TObject);
var
  i: Integer;
begin
  if SessionsPageControl.ActivePage = nil then Exit;

  for i := 0 to FSessions.Count - 1 do
  begin
    if FSessions[i].TabSheet = SessionsPageControl.ActivePage then
    begin
      SetActiveSession(FSessions[i]);
      Break;
    end;
  end;
end;

procedure TFormDextTestRunner.CreateNewSession(const AName: string);
var
  Session: TTestSession;
begin
  Session := TTestSession.Create(SessionsPageControl, AName);

  Session.TreeView.Images := TestsTreeView.Images;
  Session.TreeView.Checkboxes := True;
  Session.TreeView.PopupMenu := TestsTreeView.PopupMenu;
  Session.TreeView.OnMouseMove := TestsTreeViewMouseMove;
  Session.TreeView.OnMouseLeave := TestsTreeViewMouseLeave;
  Session.TreeView.OnMouseDown := TestsTreeViewMouseDown;
  Session.TreeView.OnMouseUp := TestsTreeViewMouseUp;
  Session.TreeView.OnAdvancedCustomDrawItem := TestsTreeViewAdvancedCustomDrawItem;
  Session.TreeView.OnDblClick := TestsTreeViewDblClick;
  Session.TreeView.OnChange := TestsTreeViewChange;

  FSessions.Add(Session);

  SessionsPageControl.ActivePage := Session.TabSheet;
  SetActiveSession(Session);

  RefreshProjects;
  UpdateTabVisibility;
end;

procedure TFormDextTestRunner.CloseSession(ASession: TTestSession);
var
  ActiveIndex: Integer;
  NextIndex: Integer;
begin
  if FSessions.Count <= 1 then Exit;

  ActiveIndex := FSessions.IndexOf(ASession);

  if FActiveSession = ASession then
  begin
    NextIndex := ActiveIndex - 1;
    if NextIndex < 0 then NextIndex := 1;
    SetActiveSession(FSessions[NextIndex]);
    SessionsPageControl.ActivePage := FActiveSession.TabSheet;
  end;

  FSessions.Remove(ASession);
  UpdateTabVisibility;
end;

procedure TFormDextTestRunner.SessionTabContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  PageControl: TPageControl;
  TabIndex: Integer;
  Pos: TPoint;
  Menu: TPopupMenu;
  Item: TMenuItem;
begin
  PageControl := Sender as TPageControl;
  Pos := MousePos;

  TabIndex := PageControl.IndexOfTabAt(Pos.X, Pos.Y);
  if TabIndex >= 0 then
  begin
    PageControl.ActivePage := PageControl.Pages[TabIndex];
    SessionsPageControlChange(PageControl);

    // nil owner: do not accumulate PopupMenus on the dock form (10.4 "_1" / leaks).
    Menu := TPopupMenu.Create(nil);
    try
      Item := TMenuItem.Create(Menu);
      Item.Caption := 'Close Session';
      Item.OnClick := CloseActiveSessionClick;
      Menu.Items.Add(Item);

      Pos := PageControl.ClientToScreen(Pos);
      Menu.Popup(Pos.X, Pos.Y);
      Handled := True;
    finally
      Menu.Free;
    end;
  end;
end;

procedure TFormDextTestRunner.CloseActiveSessionClick(Sender: TObject);
begin
  CloseSession(FActiveSession);
end;

function ExtractTagValue(const AContent, ATagName: string): string;
var
  TagStart, TagEnd: Integer;
begin
  Result := '';
  TagStart := AContent.LastIndexOf('<' + ATagName + '>');
  if TagStart >= 0 then
  begin
    Inc(TagStart, Length(ATagName) + 2);
    TagEnd := AContent.IndexOf('</' + ATagName + '>', TagStart);
    if TagEnd > TagStart then
      Result := AContent.Substring(TagStart, TagEnd - TagStart).Trim;
  end;
end;

function GetDelphiProductVersion: string;
var
  BinDir: string;
  Split: TArray<string>;
  i: Integer;
begin
  BinDir := ExtractFilePath(ParamStr(0));
  Split := BinDir.Split(['\']);
  for i := 0 to Length(Split) - 1 do
  begin
    if SameText(Split[i], 'Studio') and (i < Length(Split) - 1) then
      Exit(Split[i + 1]);
  end;
  Result := '23.0';
end;

function ExecuteAndCapture(const ACommandLine, AWorkDir: string; out AOutput: string): Boolean;
var
  SecurityAttributes: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  StartUpInfo: TStartUpInfo;
  ProcessInfo: TProcessInformation;
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  Success: Boolean;
  CmdLine: string;
  ExitCode: DWORD;
begin
  Result := False;
  AOutput := '';

  SecurityAttributes.nLength := SizeOf(TSecurityAttributes);
  SecurityAttributes.bInheritHandle := True;
  SecurityAttributes.lpSecurityDescriptor := nil;

  if not CreatePipe(ReadPipe, WritePipe, @SecurityAttributes, 0) then Exit;

  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

    ZeroMemory(@StartUpInfo, SizeOf(TStartUpInfo));
    StartUpInfo.cb := SizeOf(TStartUpInfo);
    StartUpInfo.hStdOutput := WritePipe;
    StartUpInfo.hStdError := WritePipe;
    StartUpInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartUpInfo.wShowWindow := SW_HIDE;

    CmdLine := ACommandLine;
    UniqueString(CmdLine);

    if CreateProcess(nil, PChar(CmdLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      Pointer(AWorkDir), StartUpInfo, ProcessInfo) then
    begin
      CloseHandle(WritePipe);
      WritePipe := 0;

      repeat
        Success := ReadFile(ReadPipe, Buffer[0], SizeOf(Buffer) - 1, BytesRead, nil);
        if BytesRead > 0 then
        begin
          Buffer[BytesRead] := #0;
          AOutput := AOutput + string(AnsiString(Buffer));
        end;
      until not Success or (BytesRead = 0);

      WaitForSingleObject(ProcessInfo.hProcess, INFINITE);

      ExitCode := 0;
      GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);
      Result := (ExitCode = 0);

      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end;
  finally
    if ReadPipe <> 0 then CloseHandle(ReadPipe);
    if WritePipe <> 0 then CloseHandle(WritePipe);
  end;
end;

function TFormDextTestRunner.CompileCppProject(const AProjFile: string): Boolean;
const
  ProfileCc1 = '-fprofile-instrument=clang -fcoverage-mapping';
  ProfileLib = '-lclang_rt.profile-x86_64';
var
  ApplyLlvm: Boolean;
  Configs: IOTAProjectOptionsConfigurations;
  LinkOpts: string;
  PlatformName: string;
  Proj: IOTAProject;
  UserOpts: string;
begin
  PlatformName := 'Win32';
  Proj := GetProjectByFileName(AProjFile);
  if Assigned(Proj) and Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    PlatformName := Configs.ActivePlatformName;
  ApplyLlvm := SameText(PlatformName, 'Win64x') and Assigned(FCoverageCheckBox) and
    FCoverageCheckBox.Checked;
  if ApplyLlvm and Assigned(Proj) then
  begin
    { The IDE calls bcc64x -cc1, so the driver flag -fprofile-instr-generate is rejected.
      -fprofile-instrument=clang is the cc1 form. The profile runtime is an lld library. }
    try
      UserOpts := VarToStr(Proj.ProjectOptions.Values['BCC_UserSuppliedOptions']);
      if not UserOpts.Contains('-fprofile-instrument=clang') then
        Proj.ProjectOptions.Values['BCC_UserSuppliedOptions'] :=
          Trim(ProfileCc1 + ' ' + UserOpts);
      LinkOpts := VarToStr(Proj.ProjectOptions.Values['ILINK_AdditionalOptions']);
      if not LinkOpts.Contains('clang_rt.profile') then
        Proj.ProjectOptions.Values['ILINK_AdditionalOptions'] :=
          Trim(ProfileLib + ' ' + LinkOpts);
      LogMsg('Coverage: Win64x compile uses -fprofile-instrument=clang and -fcoverage-mapping.');
    except
      on E: Exception do
        LogMsg('Coverage: could not set the Win64x profile options. ' + E.Message, dckWarn);
    end;
  end;
  Result := CompileProjectViaOTA(AProjFile);
end;

function TFormDextTestRunner.CompileProjectDirect(const AProjFile: string): Boolean;
var
  DccExe: string;
  Content: string;
  SearchPath, Defines, Namespaces, DcuOutput, ExeOutput: string;
  WorkDir: string;
  ProductVer: string;
  BDS: string;
  CommonDir: string;
  CmdLine: string;
  Output: string;
  ProjName: string;
  DprFile: string;

  function ResolvePaths(const APaths: string): string;
  var
    Parts: TArray<string>;
    i: Integer;
    Resolved: string;
    Part: string;
  begin
    Parts := APaths.Split([';']);
    for i := 0 to Length(Parts) - 1 do
    begin
      Part := Parts[i].Trim;
      if Part = '' then Continue;
      if not TPath.IsPathRooted(Part) then
        Part := TPath.Combine(WorkDir, Part);
      Part := TPath.GetFullPath(Part);
      if Resolved <> '' then Resolved := Resolved + ';';
      Resolved := Resolved + Part;
    end;
    Result := Resolved;
  end;
begin
  Result := False;
  if not FileExists(AProjFile) then Exit;

  // C++Builder (.cbproj): use IDE/MSBuild via OTA — dcc32 path is Delphi-only.
  if SameText(ExtractFileExt(AProjFile), '.cbproj') then
  begin
    LogMsg('Compiling C++Builder project via IDE: ' + ExtractFileName(AProjFile));
    Result := CompileCppProject(AProjFile);
    if not Result then
      LogMsg('Error: C++Builder compile failed (IOTAProjectBuilder).');
    Exit;
  end;

  WorkDir := ExtractFilePath(AProjFile);
  ProjName := TPath.GetFileNameWithoutExtension(AProjFile);
  DprFile := TPath.Combine(WorkDir, ProjName + '.dpr');
  if not FileExists(DprFile) then
    DprFile := TPath.Combine(WorkDir, ProjName + '.dpk');

  if not FileExists(DprFile) then
  begin
    LogMsg('Error: DPR/DPK file not found: ' + DprFile);
    Exit;
  end;

  DccExe := ExtractFilePath(ParamStr(0)) + 'dcc32.exe';
  if not FileExists(DccExe) then
  begin
    LogMsg('Error: Compiler not found: ' + DccExe);
    Exit;
  end;

  try
    Content := TFile.ReadAllText(AProjFile);
  except
    on E: Exception do
    begin
      LogMsg('Error reading project file: ' + E.Message);
      Exit;
    end;
  end;

  SearchPath := ExtractTagValue(Content, 'DCC_UnitSearchPath');
  Defines := ExtractTagValue(Content, 'DCC_Define');
  Namespaces := ExtractTagValue(Content, 'DCC_Namespace');
  DcuOutput := ExtractTagValue(Content, 'DCC_DcuOutput');
  ExeOutput := ExtractTagValue(Content, 'DCC_ExeOutput');

  ProductVer := GetDelphiProductVersion;
  BDS := ExcludeTrailingPathDelimiter(ExtractFileDir(ExtractFileDir(ParamStr(0))));
  CommonDir := 'C:\Users\Public\Documents\Embarcadero\Studio\' + ProductVer;

  SearchPath := SearchPath.Replace('$(ProductVersion)', ProductVer)
                           .Replace('$(Platform)', 'Win32')
                           .Replace('$(Config)', 'Debug')
                           .Replace('$(BDS)', BDS)
                           .Replace('$(BDSCOMMONDIR)', CommonDir)
                           .Replace('$(DCC_UnitSearchPath)', '');

  Defines := Defines.Replace('$(DCC_Define)', '').Trim;
  if Defines.EndsWith(';') then
    Defines := Defines.Substring(0, Defines.Length - 1).Trim;

  Namespaces := Namespaces.Replace('$(DCC_Namespace)', '').Trim;
  if Namespaces.EndsWith(';') then
    Namespaces := Namespaces.Substring(0, Namespaces.Length - 1).Trim;

  DcuOutput := DcuOutput.Replace('$(ProductVersion)', ProductVer)
                          .Replace('$(Platform)', 'Win32')
                          .Replace('$(Config)', 'Debug');
  ExeOutput := ExeOutput.Replace('$(ProductVersion)', ProductVer)
                          .Replace('$(Platform)', 'Win32')
                          .Replace('$(Config)', 'Debug');

  SearchPath := ResolvePaths(SearchPath);
  if DcuOutput <> '' then
  begin
    if not TPath.IsPathRooted(DcuOutput) then
      DcuOutput := TPath.Combine(WorkDir, DcuOutput);
    DcuOutput := TPath.GetFullPath(DcuOutput);
    ForceDirectories(DcuOutput);
  end;
  if ExeOutput <> '' then
  begin
    if not TPath.IsPathRooted(ExeOutput) then
      ExeOutput := TPath.Combine(WorkDir, ExeOutput);
    ExeOutput := TPath.GetFullPath(ExeOutput);
    ForceDirectories(ExeOutput);
  end;

  if SearchPath <> '' then SearchPath := SearchPath + ';';
  SearchPath := SearchPath + WorkDir;

  CmdLine := Format('"%s" -Q -M -U"%s"', [DccExe, SearchPath]);
  if Defines <> '' then CmdLine := CmdLine + ' -D' + Defines;
  if Namespaces <> '' then CmdLine := CmdLine + ' -NS' + Namespaces;
  if DcuOutput <> '' then CmdLine := CmdLine + ' -N0"' + DcuOutput + '"';
  if ExeOutput <> '' then CmdLine := CmdLine + ' -E"' + ExeOutput + '"';
  CmdLine := CmdLine + ' "' + DprFile + '"';

  LogMsg('DCC Command: ' + CmdLine);

  if ExecuteAndCapture(CmdLine, WorkDir, Output) then
  begin
    LogMsg(Output);
    LogMsg('Direct compilation successful.');
    Result := True;
  end
  else
  begin
    LogMsg(Output);
    LogMsg('Direct compilation failed.');
  end;
end;

procedure TFormDextTestRunner.TryLoadCoverage(AReportExpected: Boolean);
var
  CovPath: string;
  Candidates: TArray<string>;
  Candidate: string;
  WorkDir: string;
  SourceRoot: string;
  ProjDir: string;
  ExeFile: string;
  ExeReportDir: string;
  XmlFile: string;
  XmlFiles: TArray<string>;
  ScanDirs: TArray<string>;
  Attempt: Integer;
  LcovPath: string;
  PlatformName: string;
  Proj: IOTAProject;
  Configs: IOTAProjectOptionsConfigurations;

  function LooksLikeCoverageXml(const APath: string): Boolean;
  var
    Stream: TFileStream;
    Buf: TBytes;
    Head: string;
    N: Integer;
    Leaf: string;
  begin
    Result := False;
    if not FileExists(APath) then
      Exit;
    // Fast name match for the canonical DCC report.
    Leaf := TPath.GetFileName(APath);
    if SameText(Leaf, 'CodeCoverage_Summary.xml') or
       SameText(Leaf, 'dext_coverage.xml') then
      Exit(True);
    try
      Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
      try
        N := Min(4096, Stream.Size);
        if N <= 0 then Exit;
        SetLength(Buf, N);
        Stream.ReadBuffer(Buf[0], N);
        Head := TEncoding.ANSI.GetString(Buf);
        Result := Head.Contains('<report') or Head.Contains('<coverage') or
                  Head.Contains('<linehits') or Head.Contains('<lineToCover');
      finally
        Stream.Free;
      end;
    except
    end;
  end;

begin
  if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
  begin
    if not AReportExpected then
      Exit;
    PlatformName := 'Win32';
    Proj := GetProjectByFileName(FActiveProjectFile);
    if Assigned(Proj) and Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
      PlatformName := Configs.ActivePlatformName;
    if not SameText(PlatformName, 'Win64x') then
    begin
      LogMsg('Coverage: C++ line coverage is Win64x (bcc64x).');
      Exit;
    end;
    if ResolveActiveProjectExe(ExeFile) and
       TDextCoverageRunner.TryExportLlvmLcov(ExeFile,
         procedure(AMsg: string)
         begin
           LogMsg(AMsg);
         end, LcovPath) then
    begin
      TCoverageManager.GetInstance.LoadCoverageFromLcov(LcovPath);
      LogMsg(Format('Coverage loaded: %s (%d file(s))',
        [LcovPath, TCoverageManager.GetInstance.LoadedFileCount]));
      LogMsg('Coverage: open the Coverage tab (or one of the listed units) to see gutter colors.');
      RefreshCoverageReportTab;
      if Assigned(DetailsPageControl) and Assigned(FCoverageTab) then
        DetailsPageControl.ActivePage := FCoverageTab;
    end
    else
      SetCoverageProblem(
        'Coverage unavailable: llvm-cov did not produce a report. ' +
        'The Win64x build needs -fprofile-instrument=clang, -fcoverage-mapping and -lclang_rt.profile-x86_64, then Run All.');
    Exit;
  end;

  CovPath := '';
  ProjDir := ExtractFilePath(FActiveProjectFile);
  WorkDir := TDextCoverageRunner.CoverageWorkDir(FActiveProjectFile);
  SourceRoot := FLastCoverageSourceRoot;
  if SourceRoot = '' then
    SourceRoot := TPath.GetDirectoryName(ProjDir);

  ExeReportDir := '';
  if ResolveActiveProjectExe(ExeFile) then
    ExeReportDir := TPath.Combine(ExtractFilePath(ExeFile), 'report');

  { Report next to the exe (Tests\Output\report) is this project's wrap output.
    Also keep the project-local report folders. Do not scan a foreign tree. }
  Candidates := [
    TPath.Combine(FLastCoverageReportDir, 'CodeCoverage_Summary.xml'),
    TPath.Combine(FLastCoverageReportDir, 'dext_coverage.xml'),
    TPath.Combine(ExeReportDir, 'CodeCoverage_Summary.xml'),
    TPath.Combine(ExeReportDir, 'dext_coverage.xml'),
    TPath.Combine(TPath.Combine(WorkDir, 'report'), 'CodeCoverage_Summary.xml'),
    TPath.Combine(TPath.Combine(WorkDir, 'report'), 'dext_coverage.xml'),
    TPath.Combine(TPath.Combine(ProjDir, 'report'), 'CodeCoverage_Summary.xml'),
    TPath.Combine(ProjDir, 'dext_coverage.xml'),
    TPath.Combine(TPath.Combine(ProjDir, 'Win32\Debug\report'), 'CodeCoverage_Summary.xml'),
    TPath.Combine(TPath.Combine(ProjDir, 'Win64\Debug\report'), 'CodeCoverage_Summary.xml')
  ];

  // CodeCoverage writes linehits last — retry briefly if wrap just finished.
  for Attempt := 1 to 15 do
  begin
    for Candidate in Candidates do
    begin
      if (Candidate <> '') and LooksLikeCoverageXml(Candidate) then
      begin
        CovPath := Candidate;
        Break;
      end;
    end;
    if CovPath <> '' then
      Break;

    ScanDirs := [
      FLastCoverageReportDir,
      ExeReportDir,
      TPath.Combine(WorkDir, 'report'),
      TPath.Combine(ProjDir, 'report')
    ];
    for Candidate in ScanDirs do
    begin
      if (Candidate = '') or not TDirectory.Exists(Candidate) then
        Continue;
      if (ProjDir <> '') and not Candidate.ToLower.StartsWith(ProjDir.ToLower) and
         not Candidate.ToLower.StartsWith(WorkDir.ToLower) and
         not SameText(Candidate, FLastCoverageReportDir) and
         not SameText(Candidate, ExeReportDir) then
        Continue;
      try
        XmlFiles := TDirectory.GetFiles(Candidate, '*.xml');
        for XmlFile in XmlFiles do
          if LooksLikeCoverageXml(XmlFile) then
          begin
            CovPath := XmlFile;
            Break;
          end;
      except
      end;
      if CovPath <> '' then
        Break;
    end;
    if CovPath <> '' then
      Break;
    if not FCoverageWrapActive and (Attempt > 3) then
      Break;
    Sleep(100);
  end;

  if CovPath <> '' then
  begin
    LogMsg('Loading code coverage from: ' + CovPath);
    if not IsTestingDesignShuttingDown then
      TThread.Queue(nil, TThreadProcedure(procedure
        var
          LoadedCount: Integer;
          LocalPath: string;
          LocalRoot: string;
          ExpectReport: Boolean;
        begin
          LocalPath := CovPath;
          LocalRoot := SourceRoot;
          ExpectReport := AReportExpected;
          if IsTestingDesignShuttingDown then
            Exit;
          if not Assigned(FormDextTestRunner) or (csDestroying in FormDextTestRunner.ComponentState) then
            Exit;
          TCoverageManager.GetInstance.LoadCoverageFromXML(LocalPath, LocalRoot);
          LoadedCount := TCoverageManager.GetInstance.LoadedFileCount;
          FormDextTestRunner.LogMsg(Format('Coverage loaded: %s (%d file(s))', [LocalPath, LoadedCount]));
          if LoadedCount = 0 then
          begin
            // LoadCoverageFromXML already wiped memory; never leave the old grid on screen.
            if ExpectReport then
              FormDextTestRunner.SetCoverageProblem(
                'Coverage unavailable: report XML has no file entries. ' +
                'Often Release without Detailed MAP — use Debug + Actions → Apply Debug Trace Options, rebuild, Run All.')
            else
            begin
              FormDextTestRunner.RefreshCoverageReportTab;
              FormDextTestRunner.LogMsg(
                'Coverage XML had no file entries — check the report path/format.', dckWarn);
            end;
          end
          else
          begin
            FormDextTestRunner.LogMsg(
              'Coverage: open the Coverage tab (or one of the listed units) to see gutter colors. ' +
              'Units not exercised by this run have no gutter.');
            FormDextTestRunner.RefreshCoverageReportTab;
            if Assigned(FormDextTestRunner.DetailsPageControl) and Assigned(FormDextTestRunner.FCoverageTab) then
              FormDextTestRunner.DetailsPageControl.ActivePage := FormDextTestRunner.FCoverageTab;
          end;
        end));
  end
  else if AReportExpected then
  begin
    SetCoverageProblem(
      'Coverage unavailable: no report found after the run. ' +
      'Check Collect Code Coverage, Detailed MAP (Debug Trace), then rebuild and Run All.');
    if FLastCoverageReportDir <> '' then
      LogMsg('Coverage: looked in ' + FLastCoverageReportDir, dckWarn);
  end;
end;

procedure TFormDextTestRunner.SetCoverageProblem(const AMessage: string);
begin
  // Empty/failed load already cleared the manager via LoadCoverageFromXML; prep-fail has not.
  if TCoverageManager.GetInstance.LoadedFileCount > 0 then
    TCoverageManager.GetInstance.Clear
  else
    TCoverageManager.GetInstance.RefreshActiveViews;

  if Assigned(FCoverageListView) then
    FCoverageListView.Items.Clear;

  if Assigned(FCoverageSummaryLabel) then
  begin
    // Keep amber readable under IDE theming.
    FCoverageSummaryLabel.StyleElements := FCoverageSummaryLabel.StyleElements - [seFont];
    FCoverageSummaryLabel.Font.Color := $00008CFF; // amber (BGR)
    FCoverageSummaryLabel.Font.Style := [fsBold];
    FCoverageSummaryLabel.Caption := AMessage;
  end;

  if Assigned(FCoverageTab) then
  begin
    FCoverageTab.Caption := 'Coverage (!)';
    if Assigned(DetailsPageControl) then
      DetailsPageControl.ActivePage := FCoverageTab;
  end;

  LogMsg(AMessage, dckWarn);
end;

procedure TFormDextTestRunner.ClearCoverageProblemStyle;
begin
  if Assigned(FCoverageTab) and (FCoverageTab.Caption <> 'Coverage') then
    FCoverageTab.Caption := 'Coverage';

  if Assigned(FCoverageSummaryLabel) then
  begin
    FCoverageSummaryLabel.Font.Style := [];
    FCoverageSummaryLabel.StyleElements := FCoverageSummaryLabel.StyleElements + [seFont];
    FCoverageSummaryLabel.Font.Color := clWindowText;
  end;
end;

procedure TFormDextTestRunner.EnsureCoverageListColumns;
begin
  if not Assigned(FCoverageListView) then
    Exit;
  // Recreate when upgrading from older abbreviated / 4-column layouts.
  if (FCoverageListView.Columns.Count = 5) and
     SameText(FCoverageListView.Columns[2].Caption, 'Not covered') and
     SameText(FCoverageListView.Columns[3].Caption, 'Instrumented') then
  begin
    FCoverageListView.Columns[0].Width := ScalePx(50);
    Exit;
  end;

  FCoverageListView.Columns.BeginUpdate;
  try
    FCoverageListView.Columns.Clear;
    FCoverageListView.Columns.Add.Caption := '%';
    FCoverageListView.Columns[0].Width := ScalePx(50);
    FCoverageListView.Columns.Add.Caption := 'Covered';
    FCoverageListView.Columns[1].Width := ScalePx(70);
    FCoverageListView.Columns.Add.Caption := 'Not covered';
    FCoverageListView.Columns[2].Width := ScalePx(90);
    FCoverageListView.Columns.Add.Caption := 'Instrumented';
    FCoverageListView.Columns[3].Width := ScalePx(90);
    FCoverageListView.Columns.Add.Caption := 'File';
    FCoverageListView.Columns[4].Width := ScalePx(240);
  finally
    FCoverageListView.Columns.EndUpdate;
  end;
end;

function TFormDextTestRunner.FormatCoveragePercentBar(APercent: Double): string;
begin
  // Numeric only until owner-draw progress (E1.9a); ASCII bars were unreadable.
  Result := Format('%.0f%%', [APercent]);
end;

function TFormDextTestRunner.FindCoverageHtmlReport: string;
var
  Candidates: TArray<string>;
  Candidate: string;
  WorkDir: string;
begin
  Result := '';
  Candidates := [
    TPath.Combine(FLastCoverageReportDir, 'CodeCoverage_Summary.html'),
    TPath.Combine(FLastCoverageReportDir, 'CodeCoverage_summary.html'),
    TPath.Combine(FLastCoverageReportDir, 'codecoverage_summary.html')
  ];
  for Candidate in Candidates do
    if (Candidate <> '') and FileExists(Candidate) then
      Exit(Candidate);

  if FActiveProjectFile <> '' then
  begin
    WorkDir := TPath.Combine(TDextCoverageRunner.CoverageWorkDir(FActiveProjectFile), 'report');
    Candidate := TPath.Combine(WorkDir, 'CodeCoverage_Summary.html');
    if FileExists(Candidate) then
      Exit(Candidate);
  end;
end;

function TFormDextTestRunner.CoverageArtifactsPresent: Boolean;
var
  WorkDir: string;
  Files: TArray<string>;
begin
  Result := FindCoverageHtmlReport <> '';
  if Result then
    Exit;

  if (FLastCoverageReportDir <> '') and TDirectory.Exists(FLastCoverageReportDir) then
  try
    Files := TDirectory.GetFiles(FLastCoverageReportDir, '*.*', TSearchOption.soAllDirectories);
    if Length(Files) > 0 then
      Exit(True);
  except
  end;

  if FActiveProjectFile <> '' then
  begin
    WorkDir := TDextCoverageRunner.CoverageWorkDir(FActiveProjectFile);
    if TDirectory.Exists(WorkDir) then
    try
      Files := TDirectory.GetFiles(WorkDir, '*.*', TSearchOption.soAllDirectories);
      Exit(Length(Files) > 0);
    except
    end;
  end;
end;

procedure TFormDextTestRunner.OpenCoverageHtmlClick(Sender: TObject);
var
  HtmlPath: string;
begin
  HtmlPath := FindCoverageHtmlReport;
  if HtmlPath = '' then
  begin
    LogMsg(
      'Coverage HTML not found. Enable Collect + Generate HTML, Run All, then try again.',
      dckWarn);
    Exit;
  end;
  LogMsg('Opening coverage HTML: ' + HtmlPath);
  ShellExecute(Handle, 'open', PChar(HtmlPath), nil, nil, SW_SHOWNORMAL);
end;

procedure TFormDextTestRunner.GenerateHtmlMenuClick(Sender: TObject);
begin
  if not Assigned(FGenerateHtmlMenuItem) or not Assigned(FGenerateHtmlCheckBox) then
    Exit;
  FGenerateHtmlCheckBox.OnClick := nil;
  try
    FGenerateHtmlCheckBox.Checked := FGenerateHtmlMenuItem.Checked;
  finally
    FGenerateHtmlCheckBox.OnClick := ConfigChangeHandler;
  end;
  ConfigChangeHandler(FGenerateHtmlCheckBox);
  if FGenerateHtmlCheckBox.Checked then
    LogMsg('Coverage: HTML report ON for next Run All (with Collect coverage).')
  else
    LogMsg('Coverage: HTML report OFF.');
end;

procedure TFormDextTestRunner.ClearCoverageArtifactsClick(Sender: TObject);
var
  Removed: Integer;

  procedure TryDeleteTree(const ADir: string);
  begin
    if (ADir = '') or not TDirectory.Exists(ADir) then
      Exit;
    try
      TDirectory.Delete(ADir, True);
      Inc(Removed);
      LogMsg('Coverage: deleted ' + ADir);
    except
      on E: Exception do
        LogMsg('Coverage: could not delete ' + ADir + ' — ' + E.Message, dckWarn);
    end;
  end;

begin
  if not CoverageArtifactsPresent then
  begin
    LogMsg('Coverage: nothing to clear.', dckWarn);
    Exit;
  end;

  if MessageDlg(
    'Delete generated coverage files (XML, HTML, unit lists) for the active project?' + sLineBreak +
    'In-memory coverage and gutter will be cleared too.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  Removed := 0;
  // Report may sit next to the exe (…\report) and/or under .dext\testing\coverage.
  TryDeleteTree(FLastCoverageReportDir);
  if FActiveProjectFile <> '' then
    TryDeleteTree(TDextCoverageRunner.CoverageWorkDir(FActiveProjectFile));

  FLastCoverageReportDir := '';
  FLastCoverageSourceRoot := '';
  TCoverageManager.GetInstance.Clear;
  if Assigned(FCoverageListView) then
    FCoverageListView.Items.Clear;
  ClearCoverageProblemStyle;
  if Assigned(FCoverageSummaryLabel) then
    FCoverageSummaryLabel.Caption := 'No coverage loaded. Enable Collect Code Coverage and Run All.';
  if Assigned(FCoverageTab) then
    FCoverageTab.Caption := 'Coverage';

  LogMsg(Format('Coverage: cleared artifacts (%d folder(s)).', [Removed]));
  UpdateCoverageUiState;
end;

procedure TFormDextTestRunner.RefreshCoverageReportTab;
var
  Summaries: TArray<TCoverageFileSummary>;
  Summary: TCoverageFileSummary;
  Item: TListItem;
  TotalCovered, TotalNotCovered, TotalLines: Integer;
  DisplayName: string;
begin
  if not Assigned(FCoverageListView) then
    Exit;

  EnsureCoverageListColumns;
  Summaries := TCoverageManager.GetInstance.GetFileSummaries;
  TotalCovered := 0;
  TotalLines := 0;

  FCoverageListView.Items.BeginUpdate;
  try
    FCoverageListView.Items.Clear;
    for Summary in Summaries do
    begin
      Inc(TotalCovered, Summary.CoveredLines);
      Inc(TotalLines, Summary.TotalLines);
      DisplayName := ExtractFileName(Summary.FilePath);
      if DisplayName = '' then
        DisplayName := Summary.FilePath;
      Item := FCoverageListView.Items.Add;
      Item.Caption := FormatCoveragePercentBar(Summary.Percent);
      Item.SubItems.Add(IntToStr(Summary.CoveredLines));
      Item.SubItems.Add(IntToStr(Max(0, Summary.TotalLines - Summary.CoveredLines)));
      Item.SubItems.Add(IntToStr(Summary.TotalLines));
      Item.SubItems.Add(DisplayName);
      Item.SubItems.Add(Summary.FilePath); // full path for open (no column)
    end;
  finally
    FCoverageListView.Items.EndUpdate;
  end;

  TotalNotCovered := Max(0, TotalLines - TotalCovered);

  if Length(Summaries) = 0 then
  begin
    // Idle empty state (not a failed run) — keep neutral caption unless already marked.
    if Assigned(FCoverageSummaryLabel) and
       ((FCoverageTab = nil) or (FCoverageTab.Caption = 'Coverage')) then
    begin
      ClearCoverageProblemStyle;
      FCoverageSummaryLabel.Caption := 'No coverage loaded. Enable Collect Code Coverage and Run All.';
    end;
  end
  else
  begin
    ClearCoverageProblemStyle;
    if Assigned(FCoverageSummaryLabel) then
      if FindCoverageHtmlReport <> '' then
        FCoverageSummaryLabel.Caption := Format(
          '%d file(s) · %d covered · %d not covered · %d instrumented (%.1f%%) · ' +
          'MAP hits · double-click file · Actions → Open HTML report',
          [Length(Summaries), TotalCovered, TotalNotCovered, TotalLines,
           (TotalCovered / Max(TotalLines, 1)) * 100.0])
      else
        FCoverageSummaryLabel.Caption := Format(
          '%d file(s) · %d covered · %d not covered · %d instrumented (%.1f%%) · ' +
          'MAP hits · double-click file · (HTML off — enable Generate HTML to produce report)',
          [Length(Summaries), TotalCovered, TotalNotCovered, TotalLines,
           (TotalCovered / Max(TotalLines, 1)) * 100.0]);
  end;

  UpdateCoverageUiState;
end;

procedure TFormDextTestRunner.CoverageListViewDblClick(Sender: TObject);
var
  Item: TListItem;
  FilePath: string;
  Line: Integer;
  DisplayName: string;
begin
  if not Assigned(FCoverageListView) then
    Exit;
  Item := FCoverageListView.Selected;
  if not Assigned(Item) or (Item.SubItems.Count < 4) then
    Exit;

  FilePath := '';
  if Item.SubItems.Count >= 5 then
    FilePath := Item.SubItems[4];
  DisplayName := Item.SubItems[3];
  if (FilePath = '') or not FileExists(FilePath) then
    FilePath := FindUnitFileByName(DisplayName);
  if FilePath = '' then
  begin
    LogMsg('Coverage: could not locate ' + DisplayName);
    Exit;
  end;

  Line := TCoverageManager.GetInstance.FirstLineOfInterest(FilePath, True);
  OpenSourceFileAtLine(FilePath, Line);
end;

procedure TFormDextTestRunner.OpenSourceFileAtLine(const AFileName: string; ALine: Integer);
var
  ActionServices: IOTAActionServices;
  FullPath: string;
  Module: IOTAModule;
  EditView: IOTAEditView;
  TargetLine: Integer;
  CapturedPath: string;
  CapturedLine: Integer;
begin
  if AFileName = '' then
    Exit;
  try
    FullPath := ExpandFileName(AFileName);
  except
    FullPath := AFileName;
  end;
  if not FileExists(FullPath) then
  begin
    LogMsg('OpenSource: file not found: ' + AFileName);
    Exit;
  end;

  BeginSourceNavigationQuiet(Self);

  TargetLine := ALine;
  if TargetLine < 1 then
    TargetLine := 1;

  { 1) Prefer IOTASourceEditor.Show on the project module (C++ MainSource). }
  if TryShowSourceEditorInProjects(FullPath, EditView) then
    LogMsg('OpenSource: project SourceEditor.Show OK ' + ExtractFileName(FullPath));

  if EditView = nil then
  begin
    Module := OpenProjectModuleFile(FullPath);
    if Module <> nil then
      LogMsg('OpenSource: OpenProjectModuleFile OK ' + ExtractFileName(FullPath))
    else
      LogMsg('OpenSource: OpenProjectModuleFile miss ' + ExtractFileName(FullPath));
    EditView := FindEditViewForFile(FullPath);
    if (EditView = nil) and (Module <> nil) then
      TrySourceEditView(Module, FullPath, EditView);
  end;

  { 2) Clear ghost then ActionServices.OpenFile. }
  if EditView = nil then
  begin
    CloseGhostSourceModule(FullPath);
    if Supports(BorlandIDEServices, IOTAActionServices, ActionServices) then
    begin
      try
        ActionServices.OpenFile(FullPath);
        LogMsg('OpenSource: ActionServices.OpenFile called');
      except
        on E: Exception do
          LogMsg('OpenFile failed: ' + E.Message);
      end;
      EditView := FindEditViewForFile(FullPath);
      if EditView = nil then
        TryShowSourceEditorInProjects(FullPath, EditView);
    end;
  end;

  if EditView <> nil then
  begin
    EditView.Position.Move(TargetLine, 1);
    try
      TCoverageManager.GetInstance.RegisterView(EditView);
    except
    end;
    EditView.Paint;
    LogMsg(Format('Opened %s:%d', [ExtractFileName(FullPath), TargetLine]));
    Exit;
  end;

  { 3) Editor often appears one message-pump later — retry open + view. }
  CapturedPath := FullPath;
  CapturedLine := TargetLine;
  LogMsg('OpenSource: deferring edit-view lookup for ' + ExtractFileName(FullPath));
  TThread.ForceQueue(nil, TThreadProcedure(procedure
    var
      V: IOTAEditView;
      M: IOTAModule;
      AS2: IOTAActionServices;
    begin
      if IsTestingDesignShuttingDown then
        Exit;
      if FormDextTestRunner = nil then
        Exit;
      if not TryShowSourceEditorInProjects(CapturedPath, V) then
        V := nil;
      if V = nil then
      begin
        CloseGhostSourceModule(CapturedPath);
        M := OpenProjectModuleFile(CapturedPath);
        V := FindEditViewForFile(CapturedPath);
        if (V = nil) and (M <> nil) then
          TrySourceEditView(M, CapturedPath, V);
      end;
      if (V = nil) and Supports(BorlandIDEServices, IOTAActionServices, AS2) then
      begin
        try
          AS2.OpenFile(CapturedPath);
        except
        end;
        V := FindEditViewForFile(CapturedPath);
        if V = nil then
          TryShowSourceEditorInProjects(CapturedPath, V);
      end;
      if V = nil then
      begin
        LogProjectEditorDump(CapturedPath);
        FormDextTestRunner.LogMsg('OpenSource: no edit view for ' + CapturedPath);
        Exit;
      end;
      V.Position.Move(CapturedLine, 1);
      try
        TCoverageManager.GetInstance.RegisterView(V);
      except
      end;
      V.Paint;
      FormDextTestRunner.LogMsg(Format('Opened (deferred) %s:%d',
        [ExtractFileName(CapturedPath), CapturedLine]));
    end));
end;

function TFormDextTestRunner.IsCodeCoverageToolAvailable(out AToolPath: string): Boolean;
var
  PlatformVal: string;
  Configs: IOTAProjectOptionsConfigurations;
  Proj: IOTAProject;
begin
  PlatformVal := 'Win32';
  Proj := GetProjectByFileName(FActiveProjectFile);
  if Assigned(Proj) and Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    PlatformVal := Configs.ActivePlatformName;
  AToolPath := TDextCodeCoverageTool.FindPath(PlatformVal);
  Result := (AToolPath <> '') and (FileExists(AToolPath) or (ExtractFilePath(AToolPath) = ''));
end;

procedure TFormDextTestRunner.CoveragePlatformTimerTimer(Sender: TObject);
begin
  if csDestroying in ComponentState then
    Exit;
  ApplyCoverageForActivePlatform;
end;

procedure TFormDextTestRunner.ApplyCoverageForActivePlatform;
var
  CppProject, Win64x, ShowConfig, ShowDelphiOnly: Boolean;
  Configs: IOTAProjectOptionsConfigurations;
  i: Integer;
  PlatformName, Key: string;
  Proj: IOTAProject;

  procedure ShowItem(AItem: TMenuItem; AVisible: Boolean);
  begin
    if Assigned(AItem) then
      AItem.Visible := AVisible;
  end;

begin
  CppProject := SameText(ExtractFileExt(FActiveProjectFile), '.cbproj');
  PlatformName := 'Win32';
  Proj := GetProjectByFileName(FActiveProjectFile);
  if Assigned(Proj) and Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    PlatformName := Configs.ActivePlatformName;
  Win64x := CppProject and SameText(PlatformName, 'Win64x');
  Key := FActiveProjectFile + '|' + PlatformName + '|' + BoolToStr(Win64x, True);
  if Key = FLastCoveragePlatformKey then
    Exit;
  FLastCoveragePlatformKey := Key;

  { Delphi keeps coverage. C++ shows it only on Win64x. }
  ShowConfig := (not CppProject) or Win64x;
  ShowDelphiOnly := ShowConfig and not CppProject;

  if Assigned(FCoverageCheckBox) then
  begin
    FCoverageCheckBox.Visible := ShowConfig;
    if Win64x then
    begin
      FCoverageCheckBox.Enabled := True;
      FCoverageCheckBox.Hint :=
        'Win64x only. After the run, llvm-cov reads the .profraw next to the exe.';
    end
    else if ShowConfig then
      FCoverageCheckBox.Hint :=
        'Wraps the test exe with Delphi Code Coverage (⋯ Actions). Requires MAP (Debug Trace) and CodeCoverage.exe.';
  end;
  if Assigned(FGenerateHtmlCheckBox) then
    FGenerateHtmlCheckBox.Visible := ShowDelphiOnly;
  if Assigned(FCoverageTab) and Assigned(DetailsPageControl) then
  begin
    if not ShowConfig and (DetailsPageControl.ActivePage = FCoverageTab) then
      for i := 0 to DetailsPageControl.PageCount - 1 do
        if DetailsPageControl.Pages[i] <> FCoverageTab then
        begin
          DetailsPageControl.ActivePageIndex := I;
          Break;
        end;
    FCoverageTab.TabVisible := ShowConfig;
  end;

  ShowItem(FCollectCoverageMenuItem, ShowConfig);
  ShowItem(FReloadCoverageMenuItem, ShowConfig);
  ShowItem(FClearCoverageArtifactsMenuItem, ShowConfig);
  ShowItem(FInstallCoverageMenuItem, ShowDelphiOnly);
  ShowItem(FGenerateHtmlMenuItem, ShowDelphiOnly);
  ShowItem(FOpenCoverageHtmlMenuItem, ShowDelphiOnly);
  ShowItem(FOpenCoverageHtmlContextMenuItem, ShowDelphiOnly);

  if Win64x and Assigned(FCollectCoverageMenuItem) then
    FCollectCoverageMenuItem.Enabled := True;
end;

procedure TFormDextTestRunner.UpdateCoverageUiState;
var
  ToolPath: string;
  Available: Boolean;
  HasHtml: Boolean;
  HasArtifacts: Boolean;
begin
  ApplyCoverageForActivePlatform;
  if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
  begin
    if Assigned(FCollectCoverageMenuItem) and Assigned(FCoverageCheckBox) then
    begin
      FCollectCoverageMenuItem.Enabled := FCoverageCheckBox.Visible;
      FCollectCoverageMenuItem.Checked := FCoverageCheckBox.Checked and FCoverageCheckBox.Visible;
    end;
    Exit;
  end;

  Available := IsCodeCoverageToolAvailable(ToolPath);
  HasHtml := FindCoverageHtmlReport <> '';
  HasArtifacts := CoverageArtifactsPresent;

  if Assigned(FInstallCoverageMenuItem) then
  begin
    if Available then
      FInstallCoverageMenuItem.Caption := 'CodeCoverage ready — Locate / Reinstall…'
    else
      FInstallCoverageMenuItem.Caption := 'Install CodeCoverage…';
    FInstallCoverageMenuItem.Enabled := True;
  end;

  if Assigned(FCollectCoverageMenuItem) then
  begin
    FCollectCoverageMenuItem.Enabled := Available;
    if Assigned(FCoverageCheckBox) then
      FCollectCoverageMenuItem.Checked := FCoverageCheckBox.Checked and Available;
    if not Available then
      FCollectCoverageMenuItem.Checked := False;
  end;

  if Assigned(FGenerateHtmlMenuItem) then
  begin
    FGenerateHtmlMenuItem.Enabled := Available;
    if Assigned(FGenerateHtmlCheckBox) then
      FGenerateHtmlMenuItem.Checked := FGenerateHtmlCheckBox.Checked;
  end;

  if Assigned(FReloadCoverageMenuItem) then
    FReloadCoverageMenuItem.Enabled := Available;

  if Assigned(FOpenCoverageHtmlMenuItem) then
    FOpenCoverageHtmlMenuItem.Enabled := HasHtml;
  if Assigned(FOpenCoverageHtmlContextMenuItem) then
    FOpenCoverageHtmlContextMenuItem.Enabled := HasHtml;

  if Assigned(FClearCoverageArtifactsMenuItem) then
    FClearCoverageArtifactsMenuItem.Enabled := HasArtifacts;

  if Assigned(FCoverageCheckBox) then
  begin
    FCoverageCheckBox.Enabled := Available;
    if not Available then
      FCoverageCheckBox.Checked := False;
  end;

  if Assigned(FGenerateHtmlCheckBox) then
  begin
    FGenerateHtmlCheckBox.Enabled := Available;
    if not Available then
      FGenerateHtmlCheckBox.Checked := False;
  end;
end;

procedure TFormDextTestRunner.CollectCoverageMenuClick(Sender: TObject);
var
  ToolPath: string;
begin
  if not Assigned(FCollectCoverageMenuItem) or not Assigned(FCoverageCheckBox) then
    Exit;

  if SameText(ExtractFileExt(FActiveProjectFile), '.cbproj') then
  begin
    FCoverageCheckBox.OnClick := nil;
    try
      FCoverageCheckBox.Checked := FCollectCoverageMenuItem.Checked;
    finally
      FCoverageCheckBox.OnClick := ConfigChangeHandler;
    end;
    ConfigChangeHandler(FCoverageCheckBox);
    if FCoverageCheckBox.Checked then
      LogMsg('Coverage: ON — next Run All on Win64x reads line hits with llvm-cov.')
    else
      LogMsg('Coverage: OFF — Run All launches the test exe directly.');
    Exit;
  end;

  if FCollectCoverageMenuItem.Checked and not IsCodeCoverageToolAvailable(ToolPath) then
  begin
    FCollectCoverageMenuItem.Checked := False;
    EnsureCoverageToolClick(Sender);
    UpdateCoverageUiState;
    if not IsCodeCoverageToolAvailable(ToolPath) then
      Exit;
    FCollectCoverageMenuItem.Checked := True;
  end;

  FCoverageCheckBox.OnClick := nil;
  try
    FCoverageCheckBox.Checked := FCollectCoverageMenuItem.Checked;
  finally
    FCoverageCheckBox.OnClick := ConfigChangeHandler;
  end;
  ConfigChangeHandler(FCoverageCheckBox);

  if FCoverageCheckBox.Checked then
    LogMsg('Coverage: ON — next Run All / Selected wraps CodeCoverage.exe (MAP required).')
  else
    LogMsg('Coverage: OFF — Run All launches the test exe directly.');
end;

procedure TFormDextTestRunner.EnsureCoverageToolClick(Sender: TObject);
var
  ToolPath: string;
  PlatformVal: string;
  Configs: IOTAProjectOptionsConfigurations;
  Proj: IOTAProject;
begin
  PlatformVal := 'Win32';
  Proj := GetProjectByFileName(FActiveProjectFile);
  if Assigned(Proj) and Supports(Proj.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    PlatformVal := Configs.ActivePlatformName;

  if TDextCoverageRunner.EnsureTool(PlatformVal, ToolPath,
    procedure(AMsg: string)
    begin
      LogMsg(AMsg);
    end) then
  begin
    MessageDlg(
      'CodeCoverage ready:' + sLineBreak + ToolPath + sLineBreak + sLineBreak +
      'Next: ⋯ → enable "Collect Code Coverage on Run", Apply Debug Trace if needed, rebuild, then Run All.',
      mtInformation, [mbOK], 0);
  end;
  UpdateCoverageUiState;
end;

procedure TFormDextTestRunner.ReloadCoverageClick(Sender: TObject);
begin
  LogMsg('Reloading code coverage report...');
  TryLoadCoverage(True);
end;

procedure TFormDextTestRunner.RunImpactedTests(const ATests: TArray<string>);
var
  Json: string;
  i: Integer;
begin
  if Length(ATests) = 0 then Exit;

  Json := '[';
  for i := 0 to Length(ATests) - 1 do
  begin
    if i > 0 then Json := Json + ',';
    Json := Json + '"' + ATests[i] + '"';
  end;
  Json := Json + ']';

  FServer.SelectedTestsJSON := Json;
  RunActiveProjectTests('');
end;

function IsSourceFileForRunOnSave(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AFileName);
  Result := SameText(Ext, '.pas') or SameText(Ext, '.cpp') or SameText(Ext, '.h') or
    SameText(Ext, '.hpp') or SameText(Ext, '.cc') or SameText(Ext, '.cxx') or
    SameText(Ext, '.dpr') or SameText(Ext, '.dpk');
end;

procedure TFormDextTestRunner.HandleFileSaved(const AFileName: string);
begin
  { Was .pas-only — blocked C++Builder Run on Save even when module AfterSave fired. }
  if not IsSourceFileForRunOnSave(AFileName) then Exit;
  if not Assigned(FPendingSaveFiles) then Exit;
  { Opening .cbproj / OpenFile often fires AfterSave with no user save. }
  if (FIgnoreSaveUntil > 0) and (Now < FIgnoreSaveUntil) then
  begin
    LogMsg('HandleFileSaved ignored (navigation/open grace): ' + AFileName);
    Exit;
  end;
  { Idle rescans are fine; Run on Save is gated below. Still skip if Explorer disabled. }
  if not FEnabled then
    Exit;

  LogMsg('HandleFileSaved: ' + AFileName);
  if FPendingSaveFiles.IndexOf(AFileName) < 0 then
    FPendingSaveFiles.Add(AFileName);

  if Assigned(FSaveTimer) then
  begin
    FSaveTimer.Enabled := False;
    FSaveTimer.Enabled := True;
  end;
end;

procedure TFormDextTestRunner.SaveTimerTimer(Sender: TObject);
var
  CoverageFile: string;
  FixtureNode: TTreeNode;
  i, j: Integer;
  MethodNode: TTreeNode;
  Node: TTreeNode;
  ParentNode: TTreeNode;
  TestLocation: TTestLocation;
  Tests: TList<TTestLocation>;
begin
  if not Assigned(FSaveTimer) then Exit;
  FSaveTimer.Enabled := False;

  if not Assigned(FPendingSaveFiles) or (FPendingSaveFiles.Count = 0) then Exit;

  TestsTreeView.Items.BeginUpdate;
  try
    for i := 0 to FPendingSaveFiles.Count - 1 do
    begin
      CoverageFile := FPendingSaveFiles[i];
      Tests := nil;
      if TTestASTScanner.ScanFile(CoverageFile, Tests) then
      begin
        try
          // Remove existing tests in this file from our list and TreeView
          for j := FTestLocations.Count - 1 downto 0 do
          begin
            if SameText(FTestLocations[j].FileName, CoverageFile) then
            begin
              Node := FindNodeByPath(FTestLocations[j].ClassName + '.' + FTestLocations[j].MethodName);
              if not Assigned(Node) then
                Node := FindNodeByPath(FTestLocations[j].MethodName);

              if Assigned(Node) then
              begin
                ParentNode := Node.Parent;
                Node.Free;
                if Assigned(ParentNode) and (ParentNode.Count = 0) then
                  ParentNode.Free;
              end;
              FTestLocations.Delete(j);
            end;
          end;

          // Add newly discovered tests
          for TestLocation in Tests do
          begin
            FTestLocations.Add(TestLocation);

            FixtureNode := FindNodeByPath(TestLocation.ClassName);
            if not Assigned(FixtureNode) then
            begin
              FixtureNode := TestsTreeView.Items.AddChild(nil, TestLocation.ClassName);
              FixtureNode.ImageIndex := 3;
              FixtureNode.SelectedIndex := 3;
            end;

            MethodNode := TestsTreeView.Items.AddChild(FixtureNode, TestLocation.MethodName);
            MethodNode.Data := Pointer(FTestLocations.Count);
            MethodNode.ImageIndex := 0;
            MethodNode.SelectedIndex := 0;
          end;
        finally
          Tests.Free;
        end;
      end;
    end;

    if FPendingSaveFiles.Count > 0 then
      ExpandTestsTreeView;
  finally
    TestsTreeView.Items.EndUpdate;
    FPendingSaveFiles.Clear;
  end;

  // Reset/Debounce the Idle timer upon saving a file
  if RunOnIdleCheckBox.Checked and Assigned(FIdleTimer) then
  begin
    FIdleTimer.Enabled := False;
    FIdleTimer.Enabled := True;
  end;

  if FEnabled and RunOnSaveCheckBox.Checked and not FRunningTests and not FWaitingForCompile and
     (FRunningProcessHandle = 0) then
  begin
    LogMsg('Run on Save: launching tests');
    RunActiveProjectTests('', False);
  end;
end;

{ TTelemetryTracker }

class procedure TTelemetryTracker.EnsurePending;
begin
  if FPendingResults = nil then
    FPendingResults := TList<TPendingTestResult>.Create;
end;

class procedure TTelemetryTracker.FlushPendingResults;
var
  Dir, HistoryFile, ProjectFile, Text: string;
  JsonArray: TJSONArray;
  Obj: TJSONObject;
  i: Integer;
  Item: TPendingTestResult;
begin
  if (FPendingResults = nil) or (FPendingResults.Count = 0) then
    Exit;

  ProjectFile := FPendingResults[0].ProjectFile;
  if ProjectFile = '' then
  begin
    FPendingResults.Clear;
    Exit;
  end;

  Dir := TPath.Combine(TPath.GetDirectoryName(ProjectFile), '.dext\testing');
  try
    ForceDirectories(Dir);
    HistoryFile := TPath.Combine(Dir, 'history.json');

    JsonArray := nil;
    if FileExists(HistoryFile) then
    begin
      try
        Text := TFile.ReadAllText(HistoryFile, TEncoding.UTF8);
        JsonArray := TJSONObject.ParseJSONValue(Text) as TJSONArray;
      except
      end;
    end;
    if JsonArray = nil then
      JsonArray := TJSONArray.Create;

    for i := 0 to FPendingResults.Count - 1 do
    begin
      Item := FPendingResults[i];
      Obj := TJSONObject.Create;
      Obj.AddPair('testName', Item.TestName);
      Obj.AddPair('status', Item.Status);
      Obj.AddPair('durationMs', TJSONNumber.Create(Item.DurationMs));
      Obj.AddPair('timestamp', DateTimeToStr(Now));
      JsonArray.AddElement(Obj);
    end;

    while JsonArray.Count > 1000 do
      JsonArray.Remove(0).Free;

    TFile.WriteAllText(HistoryFile, JsonArray.ToJSON, TEncoding.UTF8);
    JsonArray.Free;
  except
  end;
  FPendingResults.Clear;
end;

class procedure TTelemetryTracker.RecordTestResult(const AProjectFile, ATestName, AStatus: string; ADurationMs: Integer);
var
  Item: TPendingTestResult;
begin
  // Buffer only — never read/write history.json per test on the UI thread.
  if AProjectFile = '' then Exit;
  EnsurePending;
  Item.ProjectFile := AProjectFile;
  Item.TestName := ATestName;
  Item.Status := AStatus;
  Item.DurationMs := ADurationMs;
  FPendingResults.Add(Item);
end;

class procedure TTelemetryTracker.RecordSuiteRun(const AProjectFile: string; APassed, AFailed, ASkipped, ATotal: Integer; ADurationMs: Double);
var
  Dir, HistoryFile: string;
  JsonArray: TJSONArray;
  Obj: TJSONObject;
  Text: string;
begin
  FlushPendingResults;
  if AProjectFile = '' then Exit;
  Dir := TPath.Combine(TPath.GetDirectoryName(AProjectFile), '.dext\testing');
  try
    ForceDirectories(Dir);
    HistoryFile := TPath.Combine(Dir, 'suite_history.json');

    JsonArray := nil;
    if FileExists(HistoryFile) then
    begin
      try
        Text := TFile.ReadAllText(HistoryFile, TEncoding.UTF8);
        JsonArray := TJSONObject.ParseJSONValue(Text) as TJSONArray;
      except
      end;
    end;
    if JsonArray = nil then
      JsonArray := TJSONArray.Create;

    Obj := TJSONObject.Create;
    Obj.AddPair('date', DateToISO8601(Now, False));
    Obj.AddPair('total', TJSONNumber.Create(ATotal));
    Obj.AddPair('passed', TJSONNumber.Create(APassed));
    Obj.AddPair('failed', TJSONNumber.Create(AFailed));
    Obj.AddPair('skipped', TJSONNumber.Create(ASkipped));
    Obj.AddPair('duration', TJSONNumber.Create(Round(ADurationMs)));
    JsonArray.AddElement(Obj);

    while JsonArray.Count > 50 do
      JsonArray.Remove(0).Free;

    TFile.WriteAllText(HistoryFile, JsonArray.ToJSON, TEncoding.UTF8);
    JsonArray.Free;
  except
  end;
end;

class procedure TTelemetryTracker.AnalyzeSuiteHistory(const AProjectFile: string; ALines: TStrings);
var
  Directory, FileName, Text: string;
  JsonArray: TJSONArray;
  JsonObj: TJSONObject;
  i, Passed, Failed, Skipped, Total, Duration: Integer;
  Spark: string;
begin
  if (AProjectFile = '') or (ALines = nil) then Exit;
  Directory := TPath.Combine(TPath.GetDirectoryName(AProjectFile), '.dext\testing');
  FileName := TPath.Combine(Directory, 'suite_history.json');
  if not FileExists(FileName) then Exit;

  try
    Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
    JsonArray := TJSONObject.ParseJSONValue(Text) as TJSONArray;
    if JsonArray = nil then Exit;
    try
      ALines.Add('');
      ALines.Add('=== Suite run history (last ' + JsonArray.Count.ToString + ' runs) ===');
      Spark := '';
      for i := 0 to JsonArray.Count - 1 do
      begin
        if not (JsonArray.Items[i] is TJSONObject) then Continue;
        JsonObj := TJSONObject(JsonArray.Items[i]);
        JsonObj.TryGetValue<Integer>('passed', Passed);
        JsonObj.TryGetValue<Integer>('failed', Failed);
        JsonObj.TryGetValue<Integer>('skipped', Skipped);
        JsonObj.TryGetValue<Integer>('total', Total);
        JsonObj.TryGetValue<Integer>('duration', Duration);
        if Failed > 0 then
          Spark := Spark + 'F'
        else if Skipped > 0 then
          Spark := Spark + 's'
        else
          Spark := Spark + '.';
        if i >= JsonArray.Count - 8 then
          ALines.Add(Format('  #%d  pass=%d fail=%d skip=%d total=%d  %d ms',
            [i + 1, Passed, Failed, Skipped, Total, Duration]));
      end;
      ALines.Add('  Trend: ' + Spark + '  (. pass  s skip  F fail)');
    finally
      JsonArray.Free;
    end;
  except
  end;
end;

class procedure TTelemetryTracker.AnalyzeHistory(const AProjectFile: string; ALines: TStrings);
var
  AvgDuration: Double;
  Directory, FileName: string;
  DurationMs: Integer;
  DurList: TList<Integer>;
  HasHeader: Boolean;
  i: Integer;
  IntPair: TPair<string, TList<Integer>>;
  IsFlaky: Boolean;
  IsRegression: Boolean;
  JsonArray: TJSONArray;
  JsonObj: TJSONObject;
  LastDuration: Integer;
  LastStatus: string;
  NameKey: string;
  Pair: TPair<string, TList<string>>;
  StatList: TList<string>;
  StatusesList: TList<string>;
  Sum: Integer;
  TestDurations: TDictionary<string, TList<Integer>>;
  TestName, Status: string;
  TestStatuses: TDictionary<string, TList<string>>;
  Text: string;
  Value: TJSONValue;
begin
  FlushPendingResults;
  if (AProjectFile = '') or (ALines = nil) then Exit;

  Directory := TPath.Combine(TPath.GetDirectoryName(AProjectFile), '.dext\testing');
  FileName := TPath.Combine(Directory, 'history.json');
  if not FileExists(FileName) then Exit;

  TestDurations := TDictionary<string, TList<Integer>>.Create;
  TestStatuses := TDictionary<string, TList<string>>.Create;
  try
    try
      Text := TFile.ReadAllText(FileName, TEncoding.UTF8);
      JsonArray := TJSONObject.ParseJSONValue(Text) as TJSONArray;
      if JsonArray = nil then Exit;

      try
        // 1. Group values by test name
        for i := 0 to JsonArray.Count - 1 do
        begin
          Value := JsonArray.Items[i];
          if Value is TJSONObject then
          begin
            JsonObj := TJSONObject(Value);
            if JsonObj.TryGetValue<string>('testName', TestName) then
            begin
              JsonObj.TryGetValue<string>('status', Status);
              JsonObj.TryGetValue<Integer>('durationMs', DurationMs);

              if not TestDurations.TryGetValue(TestName, DurList) then
              begin
                DurList := TList<Integer>.Create;
                TestDurations.Add(TestName, DurList);
              end;
              DurList.Add(DurationMs);

              StatList := nil;
              if not TestStatuses.TryGetValue(TestName, StatList) then
              begin
                StatList := TList<string>.Create;
                TestStatuses.Add(TestName, StatList);
              end;
              StatList.Add(Status);
            end;
          end;
        end;

        // 2. Perform regression and flakiness analysis
        HasHeader := False;
        for Pair in TestStatuses do
        begin
          NameKey := Pair.Key;
          StatusesList := Pair.Value;
          DurList := TestDurations[NameKey];

          IsFlaky := False;
          if StatusesList.Count >= 2 then
          begin
            LastStatus := StatusesList[0];
            for i := 1 to StatusesList.Count - 1 do
            begin
              if StatusesList[i] <> LastStatus then
              begin
                IsFlaky := True;
                Break;
              end;
            end;
          end;

          IsRegression := False;
          AvgDuration := 0.0;
          LastDuration := 0;
          if DurList.Count >= 3 then
          begin
            LastDuration := DurList[DurList.Count - 1];
            Sum := 0;
            for i := 0 to DurList.Count - 2 do
              Inc(Sum, DurList[i]);
            AvgDuration := Sum / (DurList.Count - 1);

            if (AvgDuration > 10) and (LastDuration > AvgDuration * 1.5) then
              IsRegression := True;
          end;

          if IsFlaky or IsRegression then
          begin
            if not HasHeader then
            begin
              ALines.Add('');
              ALines.Add('[ANALYTICS] --- TEST ANALYTICS ENGINE REPORT ---');
              HasHeader := True;
            end;

            if IsFlaky then
              ALines.Add('   [FLAKY] TEST DETECTED: ' + NameKey + ' (status changes between Pass and Fail)');
            if IsRegression then
              ALines.Add(Format('   [PERF REGRESSION] %s (Last: %dms, Avg: %.1fms)', [NameKey, LastDuration, AvgDuration]));
          end;
        end;

        if HasHeader then
          ALines.Add('========================================');
      finally
        JsonArray.Free;
      end;
    except
      // ignore errors during analysis
    end;
  finally
    for IntPair in TestDurations do IntPair.Value.Free;
    TestDurations.Free;
    for Pair in TestStatuses do Pair.Value.Free;
    TestStatuses.Free;
  end;
end;

procedure TFormDextTestRunner.ActionsButtonClick(Sender: TObject);
var
  ClickPoint: TPoint;
begin
  UpdateCoverageUiState;
  ClickPoint := ActionsButton.ClientToScreen(Point(0, ActionsButton.Height));
  ActionsPopupMenu.Popup(ClickPoint.X, ClickPoint.Y);
end;

procedure TFormDextTestRunner.UpdateTabVisibility;
begin
  SessionsPageControl.Pages[0].TabVisible := SessionsPageControl.PageCount > 1;
  if not SessionsPageControl.Pages[0].TabVisible then
    SessionsPageControl.ActivePageIndex := 0;
end;

procedure TFormDextTestRunner.AddSessionButtonClick(Sender: TObject);
begin
  CreateNewSession('Session ' + (FSessions.Count + 1).ToString);
end;

procedure TFormDextTestRunner.ExpandTestsTreeView;
begin
  if Assigned(TestsTreeView) then
  begin
    if TestsTreeView.Items.Count > 0 then
    begin
      TestsTreeView.Selected := TestsTreeView.Items[0];
      TestsTreeView.Items[0].MakeVisible;
      TestsTreeView.Invalidate;
    end;
    TestsTreeView.FullExpand;
    TestsTreeView.Invalidate;
  end;
end;

procedure TFormDextTestRunner.ResetSummaryLabels;
begin
  SummaryTotalLabel.Caption := 'Total: 0';
  SummarySelectedLabel.Caption := 'Selected: 0';
  SummarySuccessLabel.Caption := 'Passed: 0';
  SummaryFailedLabel.Caption := 'Failed: 0';
  SummarySkippedLabel.Caption := 'Skipped: 0';
  SummaryTimeLabel.Caption := 'Tests: 0.00 s';
  SummaryTotalTimeLabel.Caption := 'Total: 0.00 s';
  FTestExecutionDurationMs := 0;
end;

initialization
{$IFDEF DEXT_TEST_EXPLORER_LOG_FILE_ENABLED}
  LogLock := TObject.Create;
{$ENDIF}
{$IFDEF DEXT_TEST_EXPLORER_PERF_LOG}
  PerfLogLock := TObject.Create;
{$ENDIF}
  RegisterDockableForm;

finalization
{$IFDEF DEXT_TEST_EXPLORER_LOG_FILE_ENABLED}
  FreeAndNil(LogLock);
{$ENDIF}
{$IFDEF DEXT_TEST_EXPLORER_PERF_LOG}
  PerfLogLock.Free;
{$ENDIF}
  FreeAndNil(TTelemetryTracker.FPendingResults);
  UnregisterDockableForm;

end.

