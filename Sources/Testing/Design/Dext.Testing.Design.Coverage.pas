unit Dext.Testing.Design.Coverage;

{$I Dext.inc}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  System.Math, Vcl.Graphics, Vcl.Controls, Vcl.Forms, ToolsAPI, System.IOUtils, Vcl.Menus;

{$IFDEF DEXT_DELPHI13_UP}
  {$DEFINE DEXT_COVERAGE_GUTTER_COLUMN}
{$ENDIF}

type
  TCoverageLineState = (clsNone, clsCovered, clsUncovered, clsPartiallyCovered);

  TCoverageFileSummary = record
    FilePath: string;
    CoveredLines: Integer;
    TotalLines: Integer;
    function Percent: Double;
  end;

  TCoverageManager = class
  private
    class var FInstance: TCoverageManager;
  var
    FFileCoverage: TDictionary<string, TDictionary<Integer, TCoverageLineState>>;
    FLineCoveringTests: TDictionary<string, TDictionary<Integer, TList<string>>>;
    FNotifiers: TDictionary<IOTAEditView, Integer>;
    FLastLoadedPath: string;
    function NormalizePathKey(const AFileName: string): string;
    function FindFileCoverage(const AFileName: string; out ADict: TDictionary<Integer, TCoverageLineState>): Boolean;
    function FindLineCovering(const AFileName: string; out ADict: TDictionary<Integer, TList<string>>): Boolean;
    procedure ClearCoverage;
  public
    constructor Create;
    destructor Destroy; override;
    class function GetInstance: TCoverageManager;
    procedure LoadCoverageFromXML(const AXmlPath: string; const ASourceRoot: string = '');
    function GetLineState(const AFileName: string; ALineNumber: Integer): TCoverageLineState;
    /// <summary>
    /// Like GetLineState, but fills begin/end gaps: when a line has no hit data but
    /// nearby instrumented lines share the same status, that status is used for painting.
    /// Blank lines (between methods) are never filled — pass the line text to enforce that.
    /// </summary>
    function GetDisplayLineState(const AFileName: string; ALineNumber: Integer;
      const ALineText: string = ''): TCoverageLineState;
    function GetCoveringTests(const AFileName: string; ALineNumber: Integer): TArray<string>;
    function GetTestsCoveringFile(const AFileName: string): TList<string>;
    function GetFileSummaries: TArray<TCoverageFileSummary>;
    function FirstLineOfInterest(const AFileName: string; PreferUncovered: Boolean = True): Integer;
    function LoadedFileCount: Integer;
    /// <summary>Drop in-memory coverage and refresh editor gutters (failed/empty load).</summary>
    procedure Clear;
    procedure RegisterView(const AView: IOTAEditView);
    procedure UnregisterView(const AView: IOTAEditView);
    procedure RefreshActiveViews;
    procedure ShowCoveringTestsPopup(const AView: IOTAEditView; const ATests: TArray<string>);
    property LastLoadedPath: string read FLastLoadedPath;
  end;

  TEditorViewNotifier = class(TInterfacedObject, IOTANotifier, INTAEditViewNotifier)
  private
    FView: IOTAEditView;
  public
    constructor Create(const AView: IOTAEditView);
    // IOTANotifier
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    // INTAEditViewNotifier
    procedure EditorDestroyed(const View: IOTAEditView);
    procedure FrameFormCreated(const FrameForm: TCustomFrame);
    procedure PaintLine(const View: IOTAEditView; LineNumber: Integer;
      const LineText: PAnsiChar; const TextWidth: Word;
      const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
      const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
    procedure EditorIdle(const View: IOTAEditView);
    procedure BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean);
    procedure EndPaint(const View: IOTAEditView);
  end;

  TDextKeyboardBinding = class(TInterfacedObject, IOTANotifier, IOTAKeyboardBinding)
  public
    // IOTANotifier
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    // IOTAKeyboardBinding
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
    procedure ShowCoveringTestsProc(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
  end;

/// <summary>Reserve IDE gutter column (D13+) so coverage is not painted over by the editor.</summary>
procedure RegisterCoverageEditorPainting;
procedure UnregisterCoverageEditorPainting;

implementation

uses
  Dext.Testing.Design.DockableForm,
  Dext.Testing.Design.Server
{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
  , ToolsAPI.Editor
{$ENDIF}
  ;

type
  TPopupMenuHelper = class(TComponent)
  private
    FTestName: string;
  public
    constructor CreateHelper(AOwner: TComponent; const ATestName: string);
    procedure OnClick(Sender: TObject);
  end;

{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
  /// <summary>Paints coverage in a reserved gutter column (after line numbers).</summary>
  TDextCoverageCodeEditorNotifier = class(TNotifierObject, INTACodeEditorEvents)
  public
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
    procedure EditorResized(const Editor: TWinControl);
    procedure EditorElided(const Editor: TWinControl; const LogicalLineNum: Integer);
    procedure EditorUnElided(const Editor: TWinControl; const LogicalLineNum: Integer);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    procedure EditorMouseUp(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure EndPaint(const Editor: TWinControl);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
      const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
      const Context: INTACodeEditorPaintContext);
    procedure PaintGutter(const Rect: TRect; const Stage: TPaintGutterStage;
      const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
      const Context: INTACodeEditorPaintContext);
    procedure PaintText(const Rect: TRect; const ColNum: SmallInt; const Text: string;
      const SyntaxCode: TOTASyntaxCode; const Hilight, BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    function AllowedEvents: TCodeEditorEvents;
    function AllowedGutterStages: TPaintGutterStages;
    function AllowedLineStages: TPaintLineStages;
    function UIOptions: TCodeEditorUIOptions;
  end;

var
  FCoverageEditorEventsIndex: Integer = -1;
  FCoverageGutterColumnIndex: Integer = -1;
{$ENDIF}

{ TPopupMenuHelper }

constructor TPopupMenuHelper.CreateHelper(AOwner: TComponent; const ATestName: string);
begin
  inherited Create(AOwner);
  // Avoid auto-name collisions ("_1 already exists") when many helpers share an owner.
  Name := '';
  FTestName := ATestName;
end;

procedure TPopupMenuHelper.OnClick(Sender: TObject);
begin
  if Assigned(FormDextTestRunner) then
  begin
    FormDextTestRunner.Show;
    FormDextTestRunner.RunActiveProjectTests(FTestName);
  end;
end;

function CoverageBrushColor(AState: TCoverageLineState): TColor;
begin
  // TColor is BGR ($BBGGRR), not CSS RGB.
  case AState of
    clsCovered:
      Result := TColor($5EC522);       // #22C55E green
    clsPartiallyCovered:
      Result := TColor($08B3EA);       // #EAB308 amber
  else
    Result := TColor($8A8AFF);         // #FF8A8A light red (uncovered)
  end;
end;

{ TCoverageFileSummary }

function TCoverageFileSummary.Percent: Double;
begin
  if TotalLines <= 0 then
    Result := 0
  else
    Result := (CoveredLines / TotalLines) * 100.0;
end;

{ TCoverageManager }

constructor TCoverageManager.Create;
begin
  inherited Create;
  FFileCoverage := TDictionary<string, TDictionary<Integer, TCoverageLineState>>.Create;
  FLineCoveringTests := TDictionary<string, TDictionary<Integer, TList<string>>>.Create;
  FNotifiers := TDictionary<IOTAEditView, Integer>.Create;
  FLastLoadedPath := '';
end;

function TCoverageManager.NormalizePathKey(const AFileName: string): string;
begin
  Result := Trim(AFileName);
  if Result = '' then
    Exit;
  try
    Result := TPath.GetFullPath(Result);
  except
    // keep as-is
  end;
  Result := AnsiLowerCase(Result);
end;

function TCoverageManager.FindFileCoverage(const AFileName: string;
  out ADict: TDictionary<Integer, TCoverageLineState>): Boolean;
var
  Key, Leaf: string;
  Pair: TPair<string, TDictionary<Integer, TCoverageLineState>>;
begin
  ADict := nil;
  Result := False;
  Key := NormalizePathKey(AFileName);
  if Key = '' then
    Exit;
  if FFileCoverage.TryGetValue(Key, ADict) then
    Exit(True);

  // Fallback: match by file name when full paths differ (symlink / drive letter).
  Leaf := AnsiLowerCase(ExtractFileName(AFileName));
  if Leaf = '' then
    Exit;
  for Pair in FFileCoverage do
    if AnsiLowerCase(ExtractFileName(Pair.Key)) = Leaf then
    begin
      ADict := Pair.Value;
      Exit(True);
    end;
end;

function TCoverageManager.FindLineCovering(const AFileName: string;
  out ADict: TDictionary<Integer, TList<string>>): Boolean;
var
  Key, Leaf: string;
  Pair: TPair<string, TDictionary<Integer, TList<string>>>;
begin
  ADict := nil;
  Result := False;
  Key := NormalizePathKey(AFileName);
  if Key = '' then
    Exit;
  if FLineCoveringTests.TryGetValue(Key, ADict) then
    Exit(True);

  Leaf := AnsiLowerCase(ExtractFileName(AFileName));
  if Leaf = '' then
    Exit;
  for Pair in FLineCoveringTests do
    if AnsiLowerCase(ExtractFileName(Pair.Key)) = Leaf then
    begin
      ADict := Pair.Value;
      Exit(True);
    end;
end;

function TCoverageManager.LoadedFileCount: Integer;
begin
  Result := FFileCoverage.Count;
end;

procedure TCoverageManager.Clear;
begin
  ClearCoverage;
  FLastLoadedPath := '';
  RefreshActiveViews;
end;

function TCoverageManager.GetFileSummaries: TArray<TCoverageFileSummary>;
var
  Pair: TPair<string, TDictionary<Integer, TCoverageLineState>>;
  LinePair: TPair<Integer, TCoverageLineState>;
  Summary: TCoverageFileSummary;
  List: TList<TCoverageFileSummary>;
  i, j: Integer;
  Tmp: TCoverageFileSummary;
begin
  List := TList<TCoverageFileSummary>.Create;
  try
    for Pair in FFileCoverage do
    begin
      Summary.FilePath := Pair.Key;
      Summary.CoveredLines := 0;
      Summary.TotalLines := 0;
      for LinePair in Pair.Value do
      begin
        Inc(Summary.TotalLines);
        if LinePair.Value in [clsCovered, clsPartiallyCovered] then
          Inc(Summary.CoveredLines);
      end;
      List.Add(Summary);
    end;
    // Sort by percent ascending (worst coverage first — ReSharper-like focus)
    for i := 0 to List.Count - 2 do
      for j := i + 1 to List.Count - 1 do
        if List[j].Percent < List[i].Percent then
        begin
          Tmp := List[i];
          List[i] := List[j];
          List[j] := Tmp;
        end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TCoverageManager.FirstLineOfInterest(const AFileName: string; PreferUncovered: Boolean): Integer;
var
  Dict: TDictionary<Integer, TCoverageLineState>;
  Pair: TPair<Integer, TCoverageLineState>;
  Best: Integer;
begin
  Result := 1;
  if not FindFileCoverage(AFileName, Dict) then
    Exit;
  Best := MaxInt;
  for Pair in Dict do
  begin
    if PreferUncovered and (Pair.Value = clsUncovered) and (Pair.Key < Best) then
      Best := Pair.Key
    else if (not PreferUncovered) and (Pair.Value <> clsNone) and (Pair.Key < Best) then
      Best := Pair.Key;
  end;
  if Best = MaxInt then
  begin
    for Pair in Dict do
      if Pair.Key < Best then
        Best := Pair.Key;
  end;
  if Best <> MaxInt then
    Result := Best;
end;

class function TCoverageManager.GetInstance: TCoverageManager;
begin
  if FInstance = nil then
    FInstance := TCoverageManager.Create;
  Result := FInstance;
end;

procedure TCoverageManager.ClearCoverage;
var
  pair: TPair<string, TDictionary<Integer, TCoverageLineState>>;
  pairCovering: TPair<string, TDictionary<Integer, TList<string>>>;
  innerPair: TPair<Integer, TList<string>>;
begin
  for pair in FFileCoverage do
    pair.Value.Free;
  FFileCoverage.Clear;

  for pairCovering in FLineCoveringTests do
  begin
    for innerPair in pairCovering.Value do
      innerPair.Value.Free;
    pairCovering.Value.Free;
  end;
  FLineCoveringTests.Clear;
end;

procedure TCoverageManager.LoadCoverageFromXML(const AXmlPath: string; const ASourceRoot: string = '');
var
  Content: string;
  PosIdx: Integer;
  EndPos: Integer;
  FilePos: Integer;
  FileEndPos: Integer;
  FileBlock: string;
  FilePath: string;
  State: TCoverageLineState;
  LineNum: Integer;
  IsCovered: Boolean;
  FileLines: TDictionary<Integer, TCoverageLineState>;
  LinePos: Integer;
  LineEnd: Integer;
  Tag: string;
  NumStart: Integer;
  NumEnd: Integer;
  CovStart: Integer;
  CovEnd: Integer;
  BranchStart: Integer;
  BranchEnd: Integer;
  BranchesToCover: Integer;
  BranchCovStart: Integer;
  BranchCovEnd: Integer;
  BranchesCovered: Integer;
  TestsStart: Integer;
  TestsEnd: Integer;
  TestsStr: string;
  TestsList: TList<string>;
  SplitTests: TArray<string>;
  TestName: string;
  LineDict: TDictionary<Integer, TList<string>>;
  UnitMap: TDictionary<string, string>;
  UnitKey: string;
  NameAttr: string;
  LineHitsPos: Integer;
  HitsBlock: string;
  HitsStr: string;
  Pairs: TArray<string>;
  Pair: string;
  EqPos: Integer;
  Hits: Integer;
  Resolved: string;
  CloseTag: Integer;

  procedure EnsureUnitMap;
  var
    LocalFiles: TArray<string>;
    LocalFile: string;
    LocalKey: string;
  begin
    if UnitMap <> nil then
      Exit;
    UnitMap := TDictionary<string, string>.Create;
    if (ASourceRoot = '') or not TDirectory.Exists(ASourceRoot) then
      Exit;
    try
      LocalFiles := TDirectory.GetFiles(ASourceRoot, '*.pas', TSearchOption.soAllDirectories);
      for LocalFile in LocalFiles do
      begin
        LocalKey := AnsiLowerCase(TPath.GetFileNameWithoutExtension(LocalFile));
        if not UnitMap.ContainsKey(LocalKey) then
          UnitMap.Add(LocalKey, LocalFile);
      end;
    except
    end;
  end;

  function ResolveFileKey(const AName: string): string;
  var
    Full: string;
  begin
    Result := '';
    if AName = '' then
      Exit;
    if TPath.IsPathRooted(AName) and FileExists(AName) then
      Exit(NormalizePathKey(AName));
    EnsureUnitMap;
    UnitKey := AnsiLowerCase(TPath.GetFileNameWithoutExtension(AName));
    if (UnitMap <> nil) and UnitMap.TryGetValue(UnitKey, Full) then
      Exit(NormalizePathKey(Full));
    // Fall back to leaf name so gutter can match open buffers by filename.
    Result := NormalizePathKey(AName);
    if Result = '' then
      Result := AnsiLowerCase(ExtractFileName(AName));
  end;

begin
  ClearCoverage;
  FLastLoadedPath := '';
  UnitMap := nil;
  if not FileExists(AXmlPath) then Exit;

  try
    Content := TFile.ReadAllText(AXmlPath, TEncoding.UTF8);
    FLastLoadedPath := AXmlPath;

    // --- Format A: Sonar generic (<file path="…"><lineToCover …/>) ---
    PosIdx := 1;
    while True do
    begin
      FilePos := Content.IndexOf('<file path="', PosIdx - 1);
      if FilePos < 0 then Break;

      Inc(FilePos, 12);
      FileEndPos := Content.IndexOf('"', FilePos);
      if FileEndPos < 0 then Break;

      FilePath := ResolveFileKey(Content.Substring(FilePos, FileEndPos - FilePos));
      if FilePath = '' then
      begin
        PosIdx := FileEndPos + 1;
        Continue;
      end;

      FileLines := TDictionary<Integer, TCoverageLineState>.Create;
      if FFileCoverage.ContainsKey(FilePath) then
        FFileCoverage[FilePath].Free;
      FFileCoverage.AddOrSetValue(FilePath, FileLines);

      EndPos := Content.IndexOf('</file>', FileEndPos);
      if EndPos < 0 then EndPos := Length(Content);

      FileBlock := Content.Substring(FileEndPos, EndPos - FileEndPos);

      LinePos := 0;
      while True do
      begin
        LinePos := FileBlock.IndexOf('<lineToCover', LinePos);
        if LinePos < 0 then Break;

        LineEnd := FileBlock.IndexOf('/>', LinePos);
        if LineEnd < 0 then Break;

        Tag := FileBlock.Substring(LinePos, LineEnd - LinePos);

        NumStart := Tag.IndexOf('lineNumber="');
        if NumStart >= 0 then
        begin
          Inc(NumStart, 12);
          NumEnd := Tag.IndexOf('"', NumStart);
          LineNum := StrToIntDef(Tag.Substring(NumStart, NumEnd - NumStart), 0);

          State := clsNone;
          CovStart := Tag.IndexOf('covered="');
          if CovStart >= 0 then
          begin
            Inc(CovStart, 9);
            CovEnd := Tag.IndexOf('"', CovStart);
            IsCovered := SameText(Tag.Substring(CovStart, CovEnd - CovStart), 'true');
            if IsCovered then
              State := clsCovered
            else
              State := clsUncovered;
          end;

          BranchStart := Tag.IndexOf('branchesToCover="');
          if BranchStart >= 0 then
          begin
            Inc(BranchStart, 17);
            BranchEnd := Tag.IndexOf('"', BranchStart);
            BranchesToCover := StrToIntDef(Tag.Substring(BranchStart, BranchEnd - BranchStart), 0);

            BranchCovStart := Tag.IndexOf('branchesCovered="');
            if BranchCovStart >= 0 then
            begin
              Inc(BranchCovStart, 17);
              BranchCovEnd := Tag.IndexOf('"', BranchCovStart);
              BranchesCovered := StrToIntDef(Tag.Substring(BranchCovStart, BranchCovEnd - BranchCovStart), 0);

              if (BranchesToCover > 0) and (BranchesCovered < BranchesToCover) and (BranchesCovered > 0) then
                State := clsPartiallyCovered;
            end;
          end;

          if LineNum > 0 then
            FileLines.AddOrSetValue(LineNum, State);

          TestsStart := Tag.IndexOf('tests="');
          if (TestsStart >= 0) and (LineNum > 0) then
          begin
            Inc(TestsStart, 7);
            TestsEnd := Tag.IndexOf('"', TestsStart);
            TestsStr := Tag.Substring(TestsStart, TestsEnd - TestsStart).Trim;
            if TestsStr <> '' then
            begin
              TestsList := TList<string>.Create;
              SplitTests := TestsStr.Split([',']);
              for TestName in SplitTests do
                TestsList.Add(TestName.Trim);

              LineDict := nil;
              if not FLineCoveringTests.TryGetValue(FilePath, LineDict) then
              begin
                LineDict := TDictionary<Integer, TList<string>>.Create;
                FLineCoveringTests.Add(FilePath, LineDict);
              end;
              LineDict.AddOrSetValue(LineNum, TestsList);
            end;
          end;
        end;

        Inc(LinePos);
      end;

      PosIdx := EndPos + 7;
    end;

    // --- Format B: DelphiCodeCoverage native (<linehits><file name="Unit.pas">123=1;…</file>) ---
    if FFileCoverage.Count = 0 then
    begin
      LineHitsPos := Content.IndexOf('<linehits>', 0);
      if LineHitsPos >= 0 then
      begin
        CloseTag := Content.IndexOf('</linehits>', LineHitsPos);
        if CloseTag < 0 then
          HitsBlock := Content.Substring(LineHitsPos)
        else
          HitsBlock := Content.Substring(LineHitsPos, CloseTag - LineHitsPos);

        PosIdx := 0;
        while True do
        begin
          FilePos := HitsBlock.IndexOf('<file name="', PosIdx);
          if FilePos < 0 then Break;
          Inc(FilePos, 12);
          FileEndPos := HitsBlock.IndexOf('"', FilePos);
          if FileEndPos < 0 then Break;
          NameAttr := HitsBlock.Substring(FilePos, FileEndPos - FilePos);
          Resolved := ResolveFileKey(NameAttr);
          EndPos := HitsBlock.IndexOf('</file>', FileEndPos);
          if EndPos < 0 then Break;
          HitsStr := HitsBlock.Substring(FileEndPos + 1, EndPos - FileEndPos - 1).Trim;
          // Strip optional '>' after attributes if present
          if HitsStr.StartsWith('>') then
            HitsStr := HitsStr.Substring(1).Trim;

          if Resolved <> '' then
          begin
            FileLines := TDictionary<Integer, TCoverageLineState>.Create;
            if FFileCoverage.ContainsKey(Resolved) then
              FFileCoverage[Resolved].Free;
            FFileCoverage.AddOrSetValue(Resolved, FileLines);

            Pairs := HitsStr.Split([';']);
            for Pair in Pairs do
            begin
              if Pair.Trim = '' then Continue;
              EqPos := Pair.IndexOf('=');
              if EqPos < 0 then Continue;
              LineNum := StrToIntDef(Pair.Substring(0, EqPos).Trim, 0);
              Hits := StrToIntDef(Pair.Substring(EqPos + 1).Trim, 0);
              if LineNum <= 0 then Continue;
              if Hits > 0 then
                FileLines.AddOrSetValue(LineNum, clsCovered)
              else
                FileLines.AddOrSetValue(LineNum, clsUncovered);
            end;
          end;
          PosIdx := EndPos + 7;
        end;
      end;
    end;
  except
    // ignore parsing errors
  end;

  FreeAndNil(UnitMap);
  RefreshActiveViews;
end;

function TCoverageManager.GetLineState(const AFileName: string; ALineNumber: Integer): TCoverageLineState;
var
  Dict: TDictionary<Integer, TCoverageLineState>;
begin
  Result := clsNone;
  if FindFileCoverage(AFileName, Dict) then
    Dict.TryGetValue(ALineNumber, Result);
end;

function IsStructuralCoverageLine(const ALineText: string): Boolean;
var
  T: string;
begin
  T := Trim(ALineText).ToLower;
  // Nested begin/end only — not procedure/var/blank (those stay unmarked, like dotCover).
  Result := (T = 'begin') or T.StartsWith('end');
end;

function TCoverageManager.GetDisplayLineState(const AFileName: string;
  ALineNumber: Integer; const ALineText: string): TCoverageLineState;
const
  MaxGap = 2; // only tight begin/end between instrumented stmts (not method headers)
var
  PrevState, NextState: TCoverageLineState;
  PrevDist, NextDist, D: Integer;
begin
  // Raw MAP hit wins — same idea as ReSharper/dotCover/VS: only executable lines.
  Result := GetLineState(AFileName, ALineNumber);
  if Result <> clsNone then
    Exit;

  // Without line text, do not invent coverage (avoids painting var/procedure).
  if ALineText = '' then
    Exit;
  if not IsStructuralCoverageLine(ALineText) then
    Exit;

  PrevState := clsNone;
  NextState := clsNone;
  PrevDist := MaxGap + 1;
  NextDist := MaxGap + 1;

  for D := 1 to MaxGap do
  begin
    if PrevState = clsNone then
    begin
      PrevState := GetLineState(AFileName, ALineNumber - D);
      if PrevState <> clsNone then
        PrevDist := D;
    end;
    if NextState = clsNone then
    begin
      NextState := GetLineState(AFileName, ALineNumber + D);
      if NextState <> clsNone then
        NextDist := D;
    end;
    if (PrevState <> clsNone) and (NextState <> clsNone) then
      Break;
  end;

  // Fill begin/end only when tightly flanked by the same instrumented status
  // (if/while body). Method begin sits above the first stmt with declarations
  // in between → PrevDist is large → stays unmarked.
  if (PrevState <> clsNone) and (PrevState = NextState) and
     (PrevDist <= MaxGap) and (NextDist <= MaxGap) then
    Result := PrevState;
end;

function TCoverageManager.GetCoveringTests(const AFileName: string; ALineNumber: Integer): TArray<string>;
var
  Dict: TDictionary<Integer, TList<string>>;
  List: TList<string>;
begin
  Result := [];
  if FindLineCovering(AFileName, Dict) then
    if Dict.TryGetValue(ALineNumber, List) then
      Result := List.ToArray;
end;

function TCoverageManager.GetTestsCoveringFile(const AFileName: string): TList<string>;
var
  Dict: TDictionary<Integer, TList<string>>;
  TestName: string;
  Pair: TPair<Integer, TList<string>>;
begin
  Result := TList<string>.Create;
  if FindLineCovering(AFileName, Dict) then
  begin
    for Pair in Dict do
    begin
      for TestName in Pair.Value do
      begin
        if not Result.Contains(TestName) then
          Result.Add(TestName);
      end;
    end;
  end;
end;

procedure TCoverageManager.RegisterView(const AView: IOTAEditView);
var
  Index: Integer;
begin
  if AView = nil then
    Exit;
  if FNotifiers.ContainsKey(AView) then
    Exit;
  // AddNotifier keeps the notifier alive; we only store the index for RemoveNotifier.
  Index := AView.AddNotifier(TEditorViewNotifier.Create(AView));
  if Index >= 0 then
    FNotifiers.AddOrSetValue(AView, Index);
end;

procedure TCoverageManager.UnregisterView(const AView: IOTAEditView);
var
  Index: Integer;
begin
  if AView = nil then
    Exit;
  if FNotifiers.TryGetValue(AView, Index) then
  begin
    try
      if Index >= 0 then
        AView.RemoveNotifier(Index);
    except
      // View may already be tearing down; ignore OTA errors.
    end;
    FNotifiers.Remove(AView);
  end;
end;

procedure TCoverageManager.RefreshActiveViews;
var
  EditorServices: IOTAEditorServices;
  Iterator: IOTAEditBufferIterator;
  EditBuffer: IOTAEditBuffer;
  View: IOTAEditView;
  I, B: Integer;
{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
  CodeEditorServices: INTACodeEditorServices;
  Editors: TList<TWinControl>;
  Editor: TWinControl;
{$ENDIF}
begin
{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
  if (FCoverageGutterColumnIndex >= 0) and
     Supports(BorlandIDEServices, INTACodeEditorServices, CodeEditorServices) then
  begin
    Editors := CodeEditorServices.GetKnownEditors;
    try
      if Assigned(Editors) then
        for Editor in Editors do
          CodeEditorServices.InvalidateEditor(Editor);
    finally
      Editors.Free;
    end;
    Exit;
  end;
{$ENDIF}

  if not Supports(BorlandIDEServices, IOTAEditorServices, EditorServices) then
    Exit;

  if not EditorServices.GetEditBufferIterator(Iterator) then
    Exit;

  for B := 0 to Iterator.Count - 1 do
  begin
    EditBuffer := Iterator.EditBuffers[B];
    if (EditBuffer = nil) or (EditBuffer.EditViewCount = 0) then
      Continue;
    for I := 0 to EditBuffer.EditViewCount - 1 do
    begin
      View := EditBuffer.EditViews[I];
      RegisterView(View);
      try
        View.Paint;
      except
      end;
    end;
  end;
end;

procedure TCoverageManager.ShowCoveringTestsPopup(const AView: IOTAEditView; const ATests: TArray<string>);
var
  PopupMenu: TPopupMenu;
  Item: TMenuItem;
  ScreenPos: TPoint;
  Test: string;
  PopupMenuHelper: TPopupMenuHelper;
begin
  if Length(ATests) = 0 then
  begin
    MessageBox(0, 'No covering tests found for this line.', 'Dext Coverage', MB_OK or MB_ICONINFORMATION);
    Exit;
  end;

  PopupMenu := TPopupMenu.Create(nil);
  try
    for Test in ATests do
    begin
      PopupMenuHelper := TPopupMenuHelper.CreateHelper(PopupMenu, Test);
      Item := TMenuItem.Create(PopupMenu);
      Item.Caption := Test;
      Item.OnClick := PopupMenuHelper.OnClick;
      PopupMenu.Items.Add(Item);
    end;
    
    ScreenPos := Mouse.CursorPos;
    PopupMenu.Popup(ScreenPos.X, ScreenPos.Y);
  finally
    if IsTestingDesignShuttingDown then
      PopupMenu.Free
    else
      TThread.ForceQueue(nil, TThreadProcedure(procedure
        begin
          PopupMenu.Free;
        end));
  end;
end;

{ TEditorViewNotifier }

constructor TEditorViewNotifier.Create(const AView: IOTAEditView);
begin
  inherited Create;
  FView := AView;
end;

procedure TEditorViewNotifier.AfterSave;
begin
end;

procedure TEditorViewNotifier.BeforeSave; begin end;

procedure TEditorViewNotifier.Destroyed;
begin
  // IDE is destroying the view; remove our notifier index before the view dies.
  if FView <> nil then
  begin
    TCoverageManager.GetInstance.UnregisterView(FView);
    FView := nil;
  end;
end;

procedure TEditorViewNotifier.Modified; begin end;

procedure TEditorViewNotifier.EditorDestroyed(const View: IOTAEditView);
begin
  TCoverageManager.GetInstance.UnregisterView(View);
  if FView = View then
    FView := nil;
end;

procedure TEditorViewNotifier.FrameFormCreated(const FrameForm: TCustomFrame); begin end;

procedure TEditorViewNotifier.PaintLine(const View: IOTAEditView; LineNumber: Integer;
  const LineText: PAnsiChar; const TextWidth: Word;
  const LineAttributes: TOTAAttributeArray; const Canvas: TCanvas;
  const TextRect: TRect; const LineRect: TRect; const CellSize: TSize);
const
  StripeW = 4;
var
  FileName: string;
  State: TCoverageLineState;
  GutterRect: TRect;
  GutterW, InsetFromText: Integer;
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenStyle: TPenStyle;
begin
{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
  // D13+: reserved gutter column paints via INTACodeEditorEvents — avoid editor overwrite.
  if FCoverageGutterColumnIndex >= 0 then
    Exit;
{$ENDIF}

  FileName := View.Buffer.FileName;
  State := TCoverageManager.GetInstance.GetDisplayLineState(FileName, LineNumber,
    string(LineText));
  if State = clsNone then
    Exit;

  // PaintLine gutter width = code origin − line origin (varies by IDE/version/DPI).
  GutterW := TextRect.Left - LineRect.Left;
  if GutterW < StripeW + 2 then
    Exit; // rects unreliable — do not paint into the editor

  // Version-specific inset: 10.4 TextRect sits flush on the divider (2px still looks
  // "in the editor"); 11+ PaintLine fallback only needs a hairline inset.
  // Never stretch Left to LineRect (that painted over line numbers).
{$IFDEF DEXT_DELPHI11_UP}
  InsetFromText := 2;
{$ELSE}
  // 10.4 and older: ~1 cell into the gutter, capped so we stay near the code edge.
  InsetFromText := Max(4, CellSize.cx);
  if InsetFromText + StripeW + 2 > GutterW then
    InsetFromText := Max(2, GutterW - StripeW - 2);
{$ENDIF}
  GutterRect.Right := TextRect.Left - InsetFromText;
  GutterRect.Left := GutterRect.Right - StripeW;
  if (GutterRect.Left < LineRect.Left) or (GutterRect.Right > TextRect.Left) then
    Exit;
  GutterRect.Top := LineRect.Top;
  GutterRect.Bottom := LineRect.Bottom + 1; // FillRect bottom exclusive
  if TCoverageManager.GetInstance.GetLineState(FileName, LineNumber - 1) = State then
    Dec(GutterRect.Top, Max(2, CellSize.cy div 4));
  if TCoverageManager.GetInstance.GetLineState(FileName, LineNumber + 1) = State then
    Inc(GutterRect.Bottom, Max(2, CellSize.cy div 4));
  if GutterRect.Right <= GutterRect.Left then
    Exit;

  OldBrushColor := Canvas.Brush.Color;
  OldBrushStyle := Canvas.Brush.Style;
  OldPenStyle := Canvas.Pen.Style;
  try
    Canvas.Pen.Style := psClear;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := CoverageBrushColor(State);
    Canvas.FillRect(GutterRect);
  finally
    Canvas.Brush.Color := OldBrushColor;
    Canvas.Brush.Style := OldBrushStyle;
    Canvas.Pen.Style := OldPenStyle;
  end;
end;

procedure TEditorViewNotifier.EditorIdle(const View: IOTAEditView); begin end;

procedure TEditorViewNotifier.BeginPaint(const View: IOTAEditView; var FullRepaint: Boolean);
begin
end;

procedure TEditorViewNotifier.EndPaint(const View: IOTAEditView);
begin
end;

{ TDextKeyboardBinding }

procedure TDextKeyboardBinding.AfterSave; begin end;
procedure TDextKeyboardBinding.BeforeSave; begin end;
procedure TDextKeyboardBinding.Destroyed; begin end;
procedure TDextKeyboardBinding.Modified; begin end;

function TDextKeyboardBinding.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TDextKeyboardBinding.GetDisplayName: string;
begin
  Result := 'Dext Show Covering Tests Binding';
end;

function TDextKeyboardBinding.GetName: string;
begin
  Result := 'Dext.ShowCoveringTests.Binding';
end;

procedure TDextKeyboardBinding.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding([ShortCut(Ord('C'), [ssCtrl, ssAlt])], ShowCoveringTestsProc, nil);
end;

procedure TDextKeyboardBinding.ShowCoveringTestsProc(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
var
  EditView: IOTAEditView;
  FileName: string;
  Line: Integer;
  Tests: TArray<string>;
begin
  BindingResult := krHandled;
  if Context.EditBuffer = nil then Exit;
  
  EditView := Context.EditBuffer.EditViews[0];
  if EditView = nil then Exit;
  
  FileName := EditView.Buffer.FileName;
  Line := EditView.CursorPos.Line;
  
  Tests := TCoverageManager.GetInstance.GetCoveringTests(FileName, Line);
  TCoverageManager.GetInstance.ShowCoveringTestsPopup(EditView, Tests);
end;

destructor TCoverageManager.Destroy;
var
  Pair: TPair<IOTAEditView, Integer>;
  Pairs: TArray<TPair<IOTAEditView, Integer>>;
begin
  // Unregister all edit-view notifiers before freeing maps (avoids NotifyDestroyed crash).
  Pairs := FNotifiers.ToArray;
  for Pair in Pairs do
    UnregisterView(Pair.Key);
  ClearCoverage;
  FFileCoverage.Free;
  FLineCoveringTests.Free;
  FNotifiers.Free;
  inherited;
end;

procedure RegisterCoverageEditorPainting;
{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
var
  Services: INTACodeEditorServices;
begin
  if FCoverageEditorEventsIndex >= 0 then
    Exit;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Exit;
  FCoverageEditorEventsIndex := Services.AddEditorEventsNotifier(TDextCoverageCodeEditorNotifier.Create);
  if FCoverageEditorEventsIndex >= 0 then
    // 3px @ 96 DPI — IDE scales; after line numbers (right edge of gutter).
    FCoverageGutterColumnIndex := Services.RequestGutterColumn(
      FCoverageEditorEventsIndex, 6, gclAfterLineNumbers);
end;
{$ELSE}
begin
end;
{$ENDIF}

procedure UnregisterCoverageEditorPainting;
{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
var
  Services: INTACodeEditorServices;
begin
  if not Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    FCoverageEditorEventsIndex := -1;
    FCoverageGutterColumnIndex := -1;
    Exit;
  end;
  if FCoverageGutterColumnIndex >= 0 then
  begin
    Services.RemoveGutterColumn(FCoverageGutterColumnIndex);
    FCoverageGutterColumnIndex := -1;
  end;
  if FCoverageEditorEventsIndex >= 0 then
  begin
    Services.RemoveEditorEventsNotifier(FCoverageEditorEventsIndex);
    FCoverageEditorEventsIndex := -1;
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

{$IFDEF DEXT_COVERAGE_GUTTER_COLUMN}
{ TDextCoverageCodeEditorNotifier }

procedure TDextCoverageCodeEditorNotifier.EditorScrolled(const Editor: TWinControl;
  const Direction: TCodeEditorScrollDirection);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EditorResized(const Editor: TWinControl);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EditorElided(const Editor: TWinControl;
  const LogicalLineNum: Integer);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EditorUnElided(const Editor: TWinControl;
  const LogicalLineNum: Integer);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EditorMouseDown(const Editor: TWinControl;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EditorMouseMove(const Editor: TWinControl;
  Shift: TShiftState; X, Y: Integer);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EditorMouseUp(const Editor: TWinControl;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
end;

procedure TDextCoverageCodeEditorNotifier.BeginPaint(const Editor: TWinControl;
  const ForceFullRepaint: Boolean);
begin
end;

procedure TDextCoverageCodeEditorNotifier.EndPaint(const Editor: TWinControl);
begin
end;

procedure TDextCoverageCodeEditorNotifier.PaintLine(const Rect: TRect;
  const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
begin
end;

procedure TDextCoverageCodeEditorNotifier.PaintText(const Rect: TRect;
  const ColNum: SmallInt; const Text: string; const SyntaxCode: TOTASyntaxCode;
  const Hilight, BeforeEvent: Boolean; var AllowDefaultPainting: Boolean;
  const Context: INTACodeEditorPaintContext);
begin
end;

function TDextCoverageCodeEditorNotifier.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents];
end;

function TDextCoverageCodeEditorNotifier.AllowedGutterStages: TPaintGutterStages;
begin
  // After IDE finishes the line's gutter so our reserved column is not wiped.
  Result := [pgsEndPaint];
end;

function TDextCoverageCodeEditorNotifier.AllowedLineStages: TPaintLineStages;
begin
  Result := [];
end;

function TDextCoverageCodeEditorNotifier.UIOptions: TCodeEditorUIOptions;
begin
  Result := [];
end;

procedure TDextCoverageCodeEditorNotifier.PaintGutter(const Rect: TRect;
  const Stage: TPaintGutterStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  ColRect, Stripe: TRect;
  State: TCoverageLineState;
  OldBrushColor: TColor;
  OldBrushStyle: TBrushStyle;
  OldPenStyle: TPenStyle;
  LineNum: Integer;
  Bridge: Integer;
  FileName, LineText: string;
begin
  if BeforeEvent or (Stage <> pgsEndPaint) then
    Exit;
  if (Context = nil) or (FCoverageGutterColumnIndex < 0) then
    Exit;
  if Context.EditorState = nil then
    Exit;

  LineNum := Context.LogicalLineNum;
  if LineNum < 1 then
    LineNum := Context.EditorLineNum;

  LineText := '';
  if Context.LineState <> nil then
    LineText := Context.LineState.Text;

  FileName := Context.FileName;
  State := TCoverageManager.GetInstance.GetDisplayLineState(FileName, LineNum, LineText);
  if State = clsNone then
    Exit;

  ColRect := Context.EditorState.GetGutterColumnRect(
    Context.EditControl, Context.EditorLineNum, FCoverageGutterColumnIndex);
  if (ColRect.Right <= ColRect.Left) or (ColRect.Bottom <= ColRect.Top) then
    Exit;

  // Anchor to the code left edge (not ColRect.Left) so we never paint over line numbers
  // if GetGutterColumnRect is wider/misaligned on some IDE builds.
  Stripe.Top := ColRect.Top;
  Stripe.Bottom := ColRect.Bottom + 1; // FillRect bottom exclusive
  Stripe.Right := Context.EditorState.CodeLeftEdge - 2;
  if Stripe.Right > ColRect.Right then
    Stripe.Right := ColRect.Right - 1;
  if Stripe.Right > Context.EditorState.CodeLeftEdge then
    Stripe.Right := Context.EditorState.CodeLeftEdge - 2;
  Stripe.Left := Stripe.Right - 4;
  if Stripe.Left < ColRect.Left then
    Exit; // reserved column too far left / too narrow — skip rather than cover numbers

  // Bridge only to neighbouring lines that also paint (not through blank/var/procedure).
  Bridge := Max(2, Context.CellSize.cy div 4);
  if TCoverageManager.GetInstance.GetLineState(FileName, LineNum - 1) = State then
    Dec(Stripe.Top, Bridge);
  if TCoverageManager.GetInstance.GetLineState(FileName, LineNum + 1) = State then
    Inc(Stripe.Bottom, Bridge);

  OldBrushColor := Context.Canvas.Brush.Color;
  OldBrushStyle := Context.Canvas.Brush.Style;
  OldPenStyle := Context.Canvas.Pen.Style;
  try
    Context.Canvas.Pen.Style := psClear;
    Context.Canvas.Brush.Style := bsSolid;
    Context.Canvas.Brush.Color := CoverageBrushColor(State);
    Context.Canvas.FillRect(Stripe);
  finally
    Context.Canvas.Brush.Color := OldBrushColor;
    Context.Canvas.Brush.Style := OldBrushStyle;
    Context.Canvas.Pen.Style := OldPenStyle;
  end;
end;
{$ENDIF}

initialization
  TCoverageManager.FInstance := nil;

finalization
  UnregisterCoverageEditorPainting;
  if TCoverageManager.FInstance <> nil then
  begin
    TCoverageManager.FInstance.Free;
    TCoverageManager.FInstance := nil;
  end;

end.
