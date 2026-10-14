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

implementation

uses
  Winapi.Windows,
  Vcl.Forms,
  Dext.Testing.Design.Server,
  Dext.Testing.Design.DockableForm,
  Dext.Testing.Design.Gutter,
  Dext.Testing.Design.Coverage;

procedure LogExpert(const AMsg: string);
begin
  LogToFile('[Expert] ' + AMsg);
  Winapi.Windows.OutputDebugString(PChar('[Dext.Expert] ' + AMsg));
end;

type
  TDextMenuHelper = class
  public
    procedure OnMenuClick(Sender: TObject);
  end;

var
  FNotifierIndex: Integer = -1;
  FTestExplorerMenu: TMenuItem = nil;
  FMenuHelper: TDextMenuHelper = nil;
  FAttachedNotifiers: TList<TModuleNotifierInfo> = nil;

procedure TDextMenuHelper.OnMenuClick(Sender: TObject);
begin
  ShowDextTestExplorer;
end;

procedure SetupMenus;
var
  LNTAServices: INTAServices;
  LMainMenu: TMainMenu;
  LToolsMenu: TMenuItem;
  I: Integer;
begin
  if Assigned(FTestExplorerMenu) then Exit;
  LogExpert('SetupMenus: Creating menu item');
  
  if Supports(BorlandIDEServices, INTAServices, LNTAServices) then
  begin
    LMainMenu := LNTAServices.MainMenu;
    if LMainMenu <> nil then
    begin
      LToolsMenu := nil;
      for I := 0 to LMainMenu.Items.Count - 1 do
      begin
        if SameText(LMainMenu.Items[I].Name, 'ToolsMenu') or 
           (LMainMenu.Items[I].Caption.Contains('Tools')) or
           (LMainMenu.Items[I].Caption.Contains('Ferramentas')) then
        begin
          LToolsMenu := LMainMenu.Items[I];
          Break;
        end;
      end;
  
      if LToolsMenu = nil then 
        LToolsMenu := LMainMenu.Items[LMainMenu.Items.Count - 1];

      if FMenuHelper = nil then
        FMenuHelper := TDextMenuHelper.Create;

      FTestExplorerMenu := TMenuItem.Create(LMainMenu);
      FTestExplorerMenu.Caption := 'Dext Test Explorer';
      FTestExplorerMenu.OnClick := FMenuHelper.OnMenuClick;
      LToolsMenu.Add(FTestExplorerMenu);
    end;
  end;
end;

procedure RemoveMenus;
begin
  LogExpert('RemoveMenus: Removing menu item');
  if Assigned(FTestExplorerMenu) then
  begin
    FTestExplorerMenu.Free;
    FTestExplorerMenu := nil;
  end;
  if Assigned(FMenuHelper) then
  begin
    FMenuHelper.Free;
    FMenuHelper := nil;
  end;
end;

procedure AttachNotifierToModule(const AFileName: string);
var
  LModuleServices: IOTAModuleServices;
  LModule: IOTAModule;
  LIndex: Integer;
  LInfo: TModuleNotifierInfo;
  I: Integer;
begin
  if not SameText(ExtractFileExt(AFileName), '.pas') then Exit;
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

procedure RegisterExpert;
var
  LOTAServices: IOTAServices;
begin
  LogExpert('RegisterExpert: Registering expert plugins');
  if FNotifierIndex = -1 then
  begin
    if Supports(BorlandIDEServices, IOTAServices, LOTAServices) then
      FNotifierIndex := LOTAServices.AddNotifier(TDextTestRunnerIDENotifier.Create);
  end;

  SetupMenus;
  RegisterDockableForm;
  RegisterGutterVisualizer;
  AttachNotifiersToOpenModules;
end;

{ TDextTestRunnerIDENotifier }

procedure TDextTestRunnerIDENotifier.AfterCompile(Succeeded: Boolean);
begin
  LogExpert('AfterCompile: Compilation finished. Success = ' + BoolToStr(Succeeded, True));
  if Assigned(FormDextTestRunner) then
    FormDextTestRunner.NotifyCompileComplete(Succeeded);
end;

procedure TDextTestRunnerIDENotifier.AfterCompile(Succeeded, IsCodeInsight: Boolean);
begin
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
  if NotifyCode = ofnFileOpened then
  begin
    LogExpert('FileNotification: File Opened = ' + FileName);
    TCoverageManager.GetInstance.RefreshActiveViews;
    AttachNotifierToModule(FileName);
  end;

  if Assigned(FormDextTestRunner) then
  begin
    if (NotifyCode = ofnActiveProjectChanged) or 
       ((NotifyCode in [ofnFileOpened, ofnFileClosing, ofnEndProjectGroupOpen, ofnEndProjectGroupClose]) and 
        (SameText(ExtractFileExt(FileName), '.dproj') or SameText(ExtractFileExt(FileName), '.groupproj'))) then
    begin
      LogExpert('FileNotification: Project change/event for ' + FileName);
      if IsTestingDesignShuttingDown then
        Exit;
      TThread.ForceQueue(nil, TThreadProcedure(procedure
        begin
          if IsTestingDesignShuttingDown then
            Exit;
          if Assigned(FormDextTestRunner) and not (csDestroying in FormDextTestRunner.ComponentState) then
            FormDextTestRunner.RefreshProjects;
          AttachNotifiersToOpenModules;
        end));
    end;
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
  if Assigned(FormDextTestRunner) then
    FormDextTestRunner.HandleFileSaved(FFileName);
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
