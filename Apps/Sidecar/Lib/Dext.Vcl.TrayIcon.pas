unit Dext.Vcl.TrayIcon;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.Graphics,
  Winapi.Messages,
  Winapi.Windows,
  Winapi.ShellAPI,
  Dext.Vcl.FormDecorator;

const
  WM_TOOLTRAYICON = WM_USER + 1;
  WM_RESETTOOLTIP = WM_USER + 2;

type
  TTrayIconEx = class(TComponent)
  private
    IconData: TNOTIFYICONDATA;
    FWindowHandle: HWND;
    FIcon: TIcon;
    FToolTip: string;
    FActive: Boolean;
    
    // Original TTrayIconEx properties
    FCloseToTray: Boolean;
    FPopupMenuDefault: TPopupMenu;
    FForm: TForm;
    FMinimized: Boolean;
    FMinimizeToTray: Boolean;
    FHideMainFormMenuItem: TMenuItem;
    FRestoreMainFormMenuItem: TMenuItem;
    FMenuItemClose: TMenuItem;
    FStartMinimized: Boolean;
    FOnCloseClick: TNotifyEvent;
    
    FBalloonFlags: Integer; // Dummy field for compatibility
    
    FOnClick: TNotifyEvent;
    FOnDblClick: TNotifyEvent;
    
    // Internal methods from new implementation
    procedure FillDataStructure;
    function AddIcon: Boolean;
    function ModifyIcon: Boolean;
    function DeleteIcon: Boolean;
    procedure SetActive(Value: Boolean);
    procedure SetIcon(Value: TIcon);
    procedure SetToolTip(Value: string);
    procedure WndProc(var Msg: TMessage);
    procedure DoRightClick; // Modified to not take params
    
    // Ex logic
    procedure ActionCloseClick(Sender: TObject);
    procedure ActionDoubleClick(Sender: TObject);
    procedure CreatePopupMenu;
    procedure ShowApplicationTaskbarIcon;
    
  protected
    FWindowProcProxy: IWindowProcProxy;
    FShowMainForm: Boolean;
    FRestoreFormState: TWindowState;

    procedure SetCloseToTray(const Value: Boolean);
    procedure SetMinimizeToTray(const Value: Boolean);
    procedure TrayWindowProc(var Message: TMessage; var Handled: Boolean);
    
  public
    constructor Create(Form: TForm; DoubleClickEvent: TNotifyEvent = nil); reintroduce;
    destructor Destroy; override;
    
    function AddMenuItem(const Caption: string; const MenuClick: TNotifyEvent; const Hint: string = ''): TMenuItem;
    procedure ToggleMinimizeRestore;
    procedure ShowBalloonHint; // Shim for VCL compatibility
    /// <summary>Draws a glyph icon when no .ico/Application icon is available.</summary>
    procedure EnsureDefaultIcon(const Glyph: string = 'D');

    property Icon: TIcon read FIcon write SetIcon;
    property Visible: Boolean read FActive write SetActive;
    property Hint: string read FToolTip write SetToolTip;
    property BalloonHint: string read FToolTip write SetToolTip; // Alias for Hint
    property BalloonFlags: Integer write FBalloonFlags; // Ignored in this simple impl, kept for compat
    
    // Ex properties
    property CloseToTray: Boolean read FCloseToTray write SetCloseToTray;
    property DefaultPopupMenu: TPopupMenu read FPopupMenuDefault write FPopupMenuDefault;
    property MenuItemClose: TMenuItem read FMenuItemClose;
    property Minimized: Boolean read FMinimized;
    property MinimizeToTray: Boolean read FMinimizeToTray write SetMinimizeToTray;
    property StartMinimized: Boolean read FStartMinimized write FStartMinimized;
    property OnCloseClick: TNotifyEvent read FOnCloseClick write FOnCloseClick;
    property OnDblClick: TNotifyEvent read FOnDblClick write FOnDblClick;
  end;

const
  TRAY_ICON_NAME_SUFIX = '_ApplicationTrayIcon';

resourcestring
  STrayCloseApplicationCaption = 'Sair';
  STrayHideMainFormCaption     = 'Ocultar';
  STrayShowMainFormCaption     = 'Restaurar';

implementation

uses
  Dext.Vcl.Helpers;

type
  // Winapi.Windows also exports TBitmap (GDI struct). Prefer VCL for drawing.
  TVclBitmap = Vcl.Graphics.TBitmap;

{ TTrayIconEx }

constructor TTrayIconEx.Create(Form: TForm; DoubleClickEvent: TNotifyEvent = nil);
begin
  inherited Create(Form);
  FForm := Form;
  
  FWindowHandle := AllocateHWnd(WndProc);
  FIcon := TIcon.Create;

  if FForm <> nil then
  begin
    FRestoreFormState := FForm.WindowState;
    FWindowProcProxy  := TWindowProcProxy.Create(FForm, TrayWindowProc);
    Self.Name         := FForm.Name + TRAY_ICON_NAME_SUFIX;
  end;

  FMinimized := True;
  FStartMinimized := True;

  if Assigned(DoubleClickEvent) then
    OnDblClick := DoubleClickEvent
  else
    OnDblClick := ActionDoubleClick;

  // Defaults
  FMinimizeToTray := False;
  FCloseToTray := False;
  CreatePopupMenu;

  if FStartMinimized then
  begin
    FShowMainForm := False;
    Application.ShowMainForm := False;
  end
  else
    FShowMainForm := True;
end;

destructor TTrayIconEx.Destroy;
begin
  if FActive then
    DeleteIcon;
    
  FreeAndNil(FIcon);
  System.Classes.DeallocateHWnd(FWindowHandle);
  inherited;
end;

// --- Low Level Implementation ---

procedure TTrayIconEx.FillDataStructure;
begin
  ZeroMemory(@IconData, SizeOf(IconData));
  IconData.cbSize := SizeOf(TNOTIFYICONDATA);
  IconData.Wnd := FWindowHandle;
  IconData.uID := 1;
  IconData.uFlags := NIF_MESSAGE or NIF_ICON or NIF_TIP;
  if (FIcon <> nil) and (FIcon.Handle <> 0) then
    IconData.hIcon := FIcon.Handle
  else
    IconData.hIcon := LoadIcon(0, IDI_APPLICATION);
  IconData.uCallbackMessage := WM_TOOLTRAYICON;
  StrPLCopy(IconData.szTip, FToolTip, Length(IconData.szTip) - 1);
end;

function TTrayIconEx.AddIcon: Boolean;
begin
  if (FIcon = nil) or (FIcon.Handle = 0) then
    EnsureDefaultIcon('D');
  FillDataStructure;
  Result := Shell_NotifyIcon(NIM_ADD, @IconData);
  if FToolTip = '' then
    PostMessage(FWindowHandle, WM_RESETTOOLTIP, 0, 0);
end;

function TTrayIconEx.ModifyIcon: Boolean;
begin
  FillDataStructure;
  if FActive then
    Result := Shell_NotifyIcon(NIM_MODIFY, @IconData)
  else
    Result := True;
end;

function TTrayIconEx.DeleteIcon: Boolean;
begin
   Result := Shell_NotifyIcon(NIM_DELETE, @IconData);
end;

procedure TTrayIconEx.SetActive(Value: Boolean);
begin
  if Value <> FActive then 
  begin
    FActive := Value;
    if not (csDesigning in ComponentState) then
    begin
      if Value then
        AddIcon
      else
        DeleteIcon;
    end;
  end;
end;

procedure TTrayIconEx.SetIcon(Value: TIcon);
begin
  if Value = nil then
    Exit;
  FIcon.Assign(Value);
  if FIcon.Handle = 0 then
    EnsureDefaultIcon('D');
  ModifyIcon;
end;

procedure TTrayIconEx.EnsureDefaultIcon(const Glyph: string);
var
  Bmp: TVclBitmap;
  Mask: TVclBitmap;
  Ix: TIconInfo;
  NewIcon: HICON;
begin
  Bmp := TVclBitmap.Create;
  Mask := TVclBitmap.Create;
  try
    Bmp.SetSize(16, 16);
    Bmp.PixelFormat := pf32bit;
    Bmp.Canvas.Brush.Color := RGB(30, 64, 175);
    Bmp.Canvas.FillRect(System.Types.Rect(0, 0, 16, 16));
    Bmp.Canvas.Font.Name := 'Segoe UI';
    Bmp.Canvas.Font.Size := 9;
    Bmp.Canvas.Font.Style := [fsBold];
    Bmp.Canvas.Font.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsClear;
    Bmp.Canvas.TextOut(3, 0, Glyph);

    Mask.SetSize(16, 16);
    Mask.Canvas.Brush.Color := clWhite;
    Mask.Canvas.FillRect(System.Types.Rect(0, 0, 16, 16));

    ZeroMemory(@Ix, SizeOf(Ix));
    Ix.fIcon := True;
    Ix.hbmColor := Bmp.Handle;
    Ix.hbmMask := Mask.Handle;
    NewIcon := CreateIconIndirect(Ix);
    if NewIcon <> 0 then
      FIcon.Handle := NewIcon;
  finally
    Mask.Free;
    Bmp.Free;
  end;
end;

procedure TTrayIconEx.SetToolTip(Value: string);
begin
  // Hack from original code: truncate to 62 chars
  if Length(Value) > 62 then
    Value := Copy(Value, 1, 62);
  FToolTip := Value;
  ModifyIcon;
end;

procedure TTrayIconEx.ShowBalloonHint;
begin
  // Not implemented in this simple version, but kept for compatibility.
  // Standard Shell_NotifyIcon v1/v2 doesn't support balloons easily without 
  // checking shell version. For Sidecar this is less critical than the icon appearing.
end;

procedure TTrayIconEx.DoRightClick;
var
  MouseCo: TPoint;
begin
  GetCursorPos(MouseCo);

  if Assigned(FPopupMenuDefault) then begin
    SetForegroundWindow(Application.Handle); // Needed for popup menu to close correctly
    Application.ProcessMessages;
    FPopupMenuDefault.Popup(MouseCo.X, MouseCo.Y);
  end;
end;

procedure TTrayIconEx.WndProc(var Msg: TMessage);
begin
  with Msg do
    if (Msg = WM_RESETTOOLTIP) then
      SetToolTip(FToolTip)
    else if (Msg = WM_TOOLTRAYICON) then begin
      case lParam of
        WM_LBUTTONDBLCLK: if Assigned(FOnDblClick) then FOnDblClick(Self);
        WM_LBUTTONUP    : if Assigned(FOnClick) then FOnClick(Self);
        WM_RBUTTONUP    : DoRightClick;
      end;
    end
    else
      Result := DefWindowProc(FWindowHandle, Msg, wParam, lParam);
end;

// --- Ex Logic ---

procedure TTrayIconEx.ActionCloseClick(Sender: TObject);
begin
  if Assigned(FOnCloseClick) then
  begin
    FOnCloseClick(Sender);
  end;

  Visible := False;
  FWindowProcProxy := nil;

  if (Application <> nil) and (Application.MainForm <> nil) then
  begin
    Application.MainForm.Close;
  end;

  Application.Terminate;
end;

procedure TTrayIconEx.ActionDoubleClick(Sender: TObject);
begin
  ToggleMinimizeRestore;
end;

procedure TTrayIconEx.SetCloseToTray(const Value: Boolean);
begin
  FCloseToTray := Value;
end;

procedure TTrayIconEx.SetMinimizeToTray(const Value: Boolean);
begin
  FMinimizeToTray := Value;
end;

function TTrayIconEx.AddMenuItem(const Caption: string; const MenuClick: TNotifyEvent; const Hint: string = ''): TMenuItem;
begin
  Result := FPopupMenuDefault.Add(Caption, MenuClick);
  Result.Hint := Hint;
end;

procedure TTrayIconEx.CreatePopupMenu;
begin
  FPopupMenuDefault := TPopupMenu.Create(Self);

  if FForm <> nil then
  begin
    FHideMainFormMenuItem := AddMenuItem(STrayHideMainFormCaption, ActionDoubleClick,
      STrayHideMainFormCaption + ' ' + Application.Title);

    FHideMainFormMenuItem.Enabled := False;

    FRestoreMainFormMenuItem := AddMenuItem(STrayShowMainFormCaption, ActionDoubleClick,
      STrayShowMainFormCaption + ' ' + Application.Title);

    AddMenuItem('-', nil);
  end;

  FMenuItemClose := AddMenuItem(STrayCloseApplicationCaption, ActionCloseClick);
  // Do not assign PopupMenu property as we handle popup manually in DoRightClick
end;

procedure TTrayIconEx.ShowApplicationTaskbarIcon;
begin
  if not IsWindowVisible(Application.Handle) then
  begin
    ShowWindow(Application.Handle, SW_SHOW);
  end;
end;

procedure TTrayIconEx.ToggleMinimizeRestore;
begin
  if FForm = nil then
  begin
    Exit;
  end;

  if FMinimized then
  begin
    ShowApplicationTaskbarIcon;
    Application.Restore;
    Application.BringToFront;
    if Application.MainForm <> nil then
    begin
      if not FShowMainForm then
      begin
        FShowMainForm := True;
        Application.MainForm.Show;
      end;

      if FRestoreFormState = wsMaximized then
        ShowWindow(Application.MainForm.Handle, SW_SHOWMAXIMIZED)
      else
        ShowWindow(Application.MainForm.Handle, SW_RESTORE);
    end;

    FHideMainFormMenuItem   .Enabled := True;
    FRestoreMainFormMenuItem.Enabled := False;
    Application.ShowMainForm         := True;
  end
  else
  begin
    Application.Minimize;
    ShowWindow(Application.Handle, SW_HIDE);

    if Application.MainForm <> nil then
    begin
      FRestoreFormState := Application.MainForm.WindowState;
      Application.MainForm.WindowState := wsMinimized;
      ShowWindow(Application.MainForm.Handle, SW_HIDE);
    end;

    FHideMainFormMenuItem.Enabled := False;
    FRestoreMainFormMenuItem.Enabled := True;
    Application.ShowMainForm := False;
  end;
  FMinimized := not FMinimized;
end;

procedure TTrayIconEx.TrayWindowProc(var Message: TMessage; var Handled: Boolean);

  procedure MinimizeToTrayOnClose;
  begin
    if CloseToTray then
    begin
      FMinimized := False;
      ToggleMinimizeRestore;
      Message.Msg    := WM_SYSCOMMAND;
      Message.wParam := SC_MINIMIZE;
    end;
  end;

var
  Shutdown: Boolean;
begin
  Shutdown := False;
  case Message.Msg of
    WM_SYSCOMMAND:
      begin
        if (Message.lParam <> WM_RBUTTONDOWN) then
        begin
          case (Message.wParam and $FFF0) of
            SC_MINIMIZE:
              if MinimizeToTray then
              begin
                FMinimized := False;
                ToggleMinimizeRestore;
              end;

            SC_CLOSE:
              MinimizeToTrayOnClose;
          end;
        end;
      end;

    WM_CLOSE:
      MinimizeToTrayOnClose;

    WM_QUERYENDSESSION:
      Shutdown := True;

    WM_ENDSESSION:
      /// TWMEndSession.EndSession
      Shutdown := LongBool(Message.LParam);
  end;

  if Shutdown then
  begin
    ActionCloseClick(FMenuItemClose);
  end;
end;

end.
