unit Dext.Testing.Design.Expert;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Vcl.Menus;

type
  { IDE Notifier to handle Auto-Run after compiles }
  TDextTestRunnerIDENotifier = class(TNotifierObject, IOTAIDENotifier)
  public
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var CanModify: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var CanCompile: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
    procedure BeforeCompile(const Project: IOTAProject; IsCodeInsight: Boolean; var CanCompile: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean; IsCodeInsight: Boolean); overload;
  end;

  { Module Notifier to handle File Save events }
  TDextModuleNotifier = class(TNotifierObject, IOTAModuleNotifier)
  private
    FFileName: string;
  protected
    { IOTANotifier }
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    { IOTAModuleNotifier }
    function CheckOverwrite: Boolean;
    procedure ModuleRenamed(const NewName: string);
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
  end;

  TModuleNotifierInfo = record
    FileName: string;
    NotifierIndex: Integer;
  end;

procedure RegisterExpert;
procedure AttachNotifiersToOpenModules;
procedure ApplyDextTestExplorerEnabledState(AEnabled: Boolean);

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Dext.Testing.Design.ExpertTrace,
  Dext.Testing.Design.Server,
  Dext.Testing.Design.DockableForm,
  Dext.Testing.Design.Gutter,
  Dext.Testing.Design.Coverage;

procedure LogExpert(const AMsg: string);
begin
  ExpertTrace('[Expert] ' + AMsg);
  LogToFile('[Expert] ' + AMsg);
end;

type
  TDextMenuHelper = class
  public
    procedure OnMenuClick(Sender: TObject);
    procedure OnMenuWatchTimer(Sender: TObject);
  end;

var
  FNotifierIndex: Integer = -1;
  FTestExplorerMenu: TMenuItem = nil;
  FMenuHelper: TDextMenuHelper = nil;
  FAttachedNotifiers: TList<TModuleNotifierInfo> = nil;
  FMenuWatchTimer: TTimer = nil;
  FMenuWatchTicks: Integer = 0;

procedure TDextMenuHelper.OnMenuClick(Sender: TObject);
begin
  ShowDextTestExplorer;
end;

function MenuStillAttached: Boolean;
begin
  Result := Assigned(FTestExplorerMenu) and (FTestExplorerMenu.Parent <> nil);
end;

procedure SetupMenus;
var
  LNTAServices: INTAServices;
begin
  { BPL Register runs late — LToolsMenu.Add sticks.
    Expert DLL InitWizard runs early — IDE rebuilds Tools and wipes manual Add.
    Use INTAServices.AddActionMenu (child of ToolsMenu) so the IDE owns the slot. }
  if MenuStillAttached then
  begin
    LogExpert('SetupMenus: already attached under ' + FTestExplorerMenu.Parent.Name);
    Exit;
  end;

  LogExpert('SetupMenus: Creating menu item via AddActionMenu');

  if not Assigned(BorlandIDEServices) then
  begin
    LogExpert('SetupMenus: BorlandIDEServices is nil');
    Exit;
  end;

  if not Supports(BorlandIDEServices, INTAServices, LNTAServices) then
  begin
    LogExpert('SetupMenus: INTAServices not available');
    Exit;
  end;

  if FMenuHelper = nil then
    FMenuHelper := TDextMenuHelper.Create;

  if Assigned(FTestExplorerMenu) then
  begin
    { Orphaned after IDE menu rebuild — do not Free (may already be destroyed). }
    LogExpert('SetupMenus: previous menu orphaned; creating a new item');
    FTestExplorerMenu := nil;
  end;

  FTestExplorerMenu := TMenuItem.Create(nil);
  FTestExplorerMenu.Name := 'DextTestExplorerMenuItem';
  FTestExplorerMenu.Caption := 'Dext Test Explorer';
  FTestExplorerMenu.OnClick := FMenuHelper.OnMenuClick;

  { Name, Action=nil, Item, InsertAdjacent=False, InsertChild=True → under Tools. }
  LNTAServices.AddActionMenu('ToolsMenu', nil, FTestExplorerMenu, False, True);
  LogExpert(Format('SetupMenus: AddActionMenu done; Parent=%s',
    [BoolToStr(Assigned(FTestExplorerMenu.Parent), True)]));
  if Assigned(FTestExplorerMenu.Parent) then
    LogExpert('SetupMenus: parent name=' + FTestExplorerMenu.Parent.Name);
end;

procedure TDextMenuHelper.OnMenuWatchTimer(Sender: TObject);
begin
  Inc(FMenuWatchTicks);
  if MenuStillAttached then
  begin
    LogExpert('MenuWatch: still attached (tick ' + IntToStr(FMenuWatchTicks) + ')');
    if FMenuWatchTicks >= 8 then
    begin
      FreeAndNil(FMenuWatchTimer);
      LogExpert('MenuWatch: stopped (menu stable)');
    end;
    Exit;
  end;

  LogExpert('MenuWatch: menu missing — re-adding (tick ' + IntToStr(FMenuWatchTicks) + ')');
  try
    SetupMenus;
  except
    on E: Exception do
      LogExpert('MenuWatch EXCEPTION: ' + E.Message);
  end;

  if FMenuWatchTicks >= 15 then
  begin
    FreeAndNil(FMenuWatchTimer);
    LogExpert('MenuWatch: gave up after 15 ticks');
  end;
end;

procedure StartMenuWatch;
begin
  if Assigned(FMenuWatchTimer) then
    Exit;
  if FMenuHelper = nil then
    FMenuHelper := TDextMenuHelper.Create;
  FMenuWatchTicks := 0;
  FMenuWatchTimer := TTimer.Create(nil);
  FMenuWatchTimer.Interval := 2000;
  FMenuWatchTimer.OnTimer := FMenuHelper.OnMenuWatchTimer;
  FMenuWatchTimer.Enabled := True;
  LogExpert('MenuWatch: started (2s interval)');
end;

procedure RemoveMenus;
begin
  LogExpert('RemoveMenus: Removing menu item');
  FreeAndNil(FMenuWatchTimer);
  if Assigned(FTestExplorerMenu) then
  begin
    try
      FTestExplorerMenu.Free;
    except
    end;
    FTestExplorerMenu := nil;
  end;
  if Assigned(FMenuHelper) then
  begin
    FMenuHelper.Free;
    FMenuHelper := nil;
  end;
end;

function IsSourceModuleForRunOnSave(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AFileName);
  Result := SameText(Ext, '.pas') or SameText(Ext, '.cpp') or SameText(Ext, '.h') or
    SameText(Ext, '.hpp') or SameText(Ext, '.cc') or SameText(Ext, '.cxx') or
    SameText(Ext, '.dpr') or SameText(Ext, '.dpk');
end;

procedure AttachNotifierToModule(const AFileName: string);
var
  LModuleServices: IOTAModuleServices;
  LModule: IOTAModule;
  LIndex: Integer;
  LInfo: TModuleNotifierInfo;
  I: Integer;
begin
  if not IsDextTestExplorerEnabled then
    Exit;
  { Was .pas-only — C++Builder saves never reached AfterSave / Run on Save. Not a DLL limit. }
  if not IsSourceModuleForRunOnSave(AFileName) then Exit;
  if not Assigned(FAttachedNotifiers) then Exit;
  LogExpert('AttachNotifierToModule: ' + AFileName);

  // Check if already attached
  for I := 0 to FAttachedNotifiers.Count - 1 do
    if SameText(FAttachedNotifiers[I].FileName, AFileName) then Exit;
  
  if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
  begin
    LModule := LModuleServices.FindModule(AFileName);
    if Assigned(LModule) then
    begin
      LIndex := LModule.AddNotifier(TDextModuleNotifier.Create(AFileName));
      LInfo.FileName := AFileName;
      LInfo.NotifierIndex := LIndex;
      FAttachedNotifiers.Add(LInfo);
    end;
  end;
end;

procedure AttachNotifiersToOpenModules;
var
  LModuleServices: IOTAModuleServices;
  LModule: IOTAModule;
  I: Integer;
begin
  if not IsDextTestExplorerEnabled then
    Exit;
  if Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then
  begin
    for I := 0 to LModuleServices.ModuleCount - 1 do
    begin
      LModule := LModuleServices.Modules[I];
      if Assigned(LModule) then
        AttachNotifierToModule(LModule.FileName);
    end;
  end;
end;

procedure RemoveAllModuleNotifiers;
var
  LModuleServices: IOTAModuleServices;
  LModule: IOTAModule;
  I: Integer;
begin
  if not Assigned(FAttachedNotifiers) then Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, LModuleServices) then Exit;
  LogExpert('RemoveAllModuleNotifiers: Removing ' + FAttachedNotifiers.Count.ToString + ' notifiers');
  
  for I := FAttachedNotifiers.Count - 1 downto 0 do
  begin
    try
      LModule := LModuleServices.FindModule(FAttachedNotifiers[I].FileName);
      if Assigned(LModule) then
        LModule.RemoveNotifier(FAttachedNotifiers[I].NotifierIndex);
    except
      // Ignore exceptions on cleanup
    end;
  end;
  FAttachedNotifiers.Clear;
end;

procedure OnDextEnabledChanged(AEnabled: Boolean);
begin
  if AEnabled then
  begin
    LogExpert('ApplyEnabled: ON — gutter + module notifiers');
    try
      RegisterGutterVisualizer;
    except
    end;
    AttachNotifiersToOpenModules;
  end
  else
  begin
    LogExpert('ApplyEnabled: OFF — remove module notifiers + gutter');
    RemoveAllModuleNotifiers;
    try
      UnregisterGutterVisualizer;
    except
    end;
  end;
end;

procedure ApplyDextTestExplorerEnabledState(AEnabled: Boolean);
begin
  SetDextTestExplorerEnabled(AEnabled);
end;

procedure RegisterExpert;
var
  LOTAServices: IOTAServices;
begin
  LoadDextTestExplorerEnabledFromIni;
  SetDextEnabledChangedHook(OnDextEnabledChanged);
  LogExpert('RegisterExpert: begin');
  LogExpert(Format('RegisterExpert: Enabled=%s BorlandIDEServices=%s',
    [BoolToStr(IsDextTestExplorerEnabled, True),
     BoolToStr(Assigned(BorlandIDEServices), True)]));
  if FNotifierIndex = -1 then
  begin
    if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
    begin
      FNotifierIndex := LOTAServices.AddNotifier(TDextTestRunnerIDENotifier.Create);
      LogExpert('RegisterExpert: IDE notifier index=' + IntToStr(FNotifierIndex));
    end
    else
      LogExpert('RegisterExpert: IOTAServices not available');
  end
  else
    LogExpert('RegisterExpert: notifier already registered');

  LogExpert('RegisterExpert: SetupMenus');
  SetupMenus;
  StartMenuWatch;
  LogExpert('RegisterExpert: RegisterDockableForm');
  RegisterDockableForm;
  { Gutter / module notifiers only when enabled — disabled must be inert for IDE open. }
  if IsDextTestExplorerEnabled then
  begin
    LogExpert('RegisterExpert: RegisterGutterVisualizer');
    RegisterGutterVisualizer;
    LogExpert('RegisterExpert: AttachNotifiersToOpenModules');
    AttachNotifiersToOpenModules;
  end
  else
    LogExpert('RegisterExpert: skipped gutter/notifiers (disabled in ini)');
  LogExpert('RegisterExpert: done');
end;

{ TDextTestRunnerIDENotifier }

procedure TDextTestRunnerIDENotifier.AfterCompile(Succeeded: Boolean);
begin
  if not IsDextTestExplorerEnabled then
    Exit;
  LogExpert('AfterCompile: Compilation finished. Success = ' + BoolToStr(Succeeded, True));
  if Assigned(FormDextTestRunner) then
    FormDextTestRunner.NotifyCompileComplete(Succeeded);
end;

procedure TDextTestRunnerIDENotifier.AfterCompile(Succeeded, IsCodeInsight: Boolean);
begin
  { Code Insight / background parse must not drive Run All — it clears FWaitingForCompile
    before the real project build finishes (common with C++Builder). }
  if IsCodeInsight then
  begin
    LogExpert('AfterCompile: ignored (CodeInsight)');
    Exit;
  end;
  AfterCompile(Succeeded);
end;

procedure TDextTestRunnerIDENotifier.BeforeCompile(const Project: IOTAProject; var CanCompile: Boolean);
begin
end;

procedure TDextTestRunnerIDENotifier.BeforeCompile(const Project: IOTAProject; IsCodeInsight: Boolean; var CanCompile: Boolean);
begin
end;

procedure TDextTestRunnerIDENotifier.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var CanModify: Boolean);
begin
  { Do not assign CanModify — never veto IDE open. }
  if not IsDextTestExplorerEnabled then
    Exit;

  { Do not AttachNotifier on ofnFileOpened — C++ MainSource open is aborted when
    experts touch modules during Opening/Opened. Run-on-Save uses edit-view AfterSave. }

  if not Assigned(FormDextTestRunner) then
    Exit;

  { Refresh project combo only after the group finishes — never on ofnFileOpened(.cbproj). }
  if (NotifyCode = ofnActiveProjectChanged) or
     (NotifyCode = ofnEndProjectGroupOpen) or
     (NotifyCode = ofnEndProjectGroupClose) then
  begin
    LogExpert('FileNotification: Project change/event for ' + FileName);
    if IsTestingDesignShuttingDown then
      Exit;
    TThread.ForceQueue(nil, TThreadProcedure(procedure
      begin
        if IsTestingDesignShuttingDown or not IsDextTestExplorerEnabled then
          Exit;
        if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
          FormDextTestRunner.RefreshProjects;
      end));
  end;
end;

{ TDextModuleNotifier }

constructor TDextModuleNotifier.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
end;

destructor TDextModuleNotifier.Destroy;
begin
  inherited Destroy;
end;

procedure TDextModuleNotifier.AfterSave;
begin
  if not IsDextTestExplorerEnabled then
    Exit;
  LogExpert('AfterSave: ' + FFileName);
  if Assigned(FormDextTestRunner) then
    FormDextTestRunner.HandleFileSaved(FFileName)
  else
    LogExpert('AfterSave: FormDextTestRunner is nil (open Test Explorer once)');
end;

procedure TDextModuleNotifier.BeforeSave;
begin
end;

procedure TDextModuleNotifier.Destroyed;
begin
  // The module is being destroyed, so we don't need to call RemoveNotifier anymore.
  // We just remove it from our FAttachedNotifiers tracking list.
  if Assigned(FAttachedNotifiers) then
  begin
    var I: Integer;
    for I := FAttachedNotifiers.Count - 1 downto 0 do
    begin
      if SameText(FAttachedNotifiers[I].FileName, FFileName) then
      begin
        FAttachedNotifiers.Delete(I);
        Break;
      end;
    end;
  end;
end;

procedure TDextModuleNotifier.Modified;
begin
end;

function TDextModuleNotifier.CheckOverwrite: Boolean;
begin
  Result := True;
end;

procedure TDextModuleNotifier.ModuleRenamed(const NewName: string);
var
  i: Integer;
  Info: TModuleNotifierInfo;
begin
  if Assigned(FAttachedNotifiers) then
  begin
    for i := 0 to FAttachedNotifiers.Count - 1 do
    begin
      if SameText(FAttachedNotifiers[i].FileName, FFileName) then
      begin
        Info := FAttachedNotifiers[i];
        Info.FileName := NewName;
        FAttachedNotifiers[I] := Info;
        Break;
      end;
    end;
  end;
  FFileName := NewName;
end;

initialization
  LogExpert('Unit initialization: creating notifiers list');
  FAttachedNotifiers := TList<TModuleNotifierInfo>.Create;

finalization
  LogExpert('Unit finalization: package unloading/uninstalling');
  BeginTestingDesignShutdown;
  if Assigned(BorlandIDEServices) then
  begin
    RemoveAllModuleNotifiers;
    if FNotifierIndex <> -1 then
    begin
      LogExpert('Unit finalization: removing IDE notifier');
      try
        (BorlandIDEServices as IOTAServices).RemoveNotifier(FNotifierIndex);
      except
      end;
      FNotifierIndex := -1;
    end;
  end;
  RemoveMenus;
  LogExpert('Unit finalization: unregistering dockable form');
  UnregisterDockableForm;
  LogExpert('Unit finalization: unregistering gutter visualizer');
  UnregisterGutterVisualizer;
  FAttachedNotifiers.Free;
  LogExpert('Unit finalization: complete');

end.
