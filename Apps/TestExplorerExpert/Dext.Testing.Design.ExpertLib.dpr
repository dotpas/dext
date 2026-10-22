{***************************************************************************}
{  Dext Test Explorer — ship as IDE Expert DLL (INITWIZARD0001)             }
{  Pattern aligned with GExperts: IOTAWizardServices.AddWizard + delayed UI }
{  Trace: %TEMP%\DextExpertLib.log                                          }
{***************************************************************************}
library Dext.Testing.Design.ExpertLib;

{$E dll}
{ Win32 keeps the registered name. Win64 gets a platform suffix so the two DLLs can sit side by side. }
{$IFDEF WIN64}
{$LIBSUFFIX 'x64'}
{$ENDIF}

uses
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Dialogs,
  ToolsApi,
  Dext.Testing.Design.ExpertTrace in '..\..\Sources\Testing\Design\Dext.Testing.Design.ExpertTrace.pas',
  Dext.Testing.Design.Registration in '..\..\Sources\Testing\Design\Dext.Testing.Design.Registration.pas',
  Dext.Testing.Design.Expert in '..\..\Sources\Testing\Design\Dext.Testing.Design.Expert.pas';

const
  InvalidWizardIndex = -1;

type
  TDextExpertWizard = class(TNotifierObject, IOTAWizard)
  private
    FInitTimer: TTimer;
    procedure OnInitTimer(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

var
  GWizardIndex: Integer = InvalidWizardIndex;

constructor TDextExpertWizard.Create;
begin
  inherited Create;
  ExpertTrace('TDextExpertWizard.Create');
  FInitTimer := TTimer.Create(nil);
  FInitTimer.Interval := 1200;
  FInitTimer.OnTimer := OnInitTimer;
  FInitTimer.Enabled := True;
  ExpertTrace('TDextExpertWizard: init timer armed (1200 ms)');
end;

destructor TDextExpertWizard.Destroy;
begin
  ExpertTrace('TDextExpertWizard.Destroy');
  FreeAndNil(FInitTimer);
  inherited;
end;

procedure TDextExpertWizard.OnInitTimer(Sender: TObject);
begin
  ExpertTrace('OnInitTimer: fired');
  FreeAndNil(FInitTimer);
  try
    ExpertTrace(Format('OnInitTimer: BorlandIDEServices assigned=%s',
      [BoolToStr(Assigned(BorlandIDEServices), True)]));
    if Supports(BorlandIDEServices, IOTAServices) then
    begin
      Application.Handle := (BorlandIDEServices as IOTAServices).GetParentHandle;
      ExpertTrace(Format('OnInitTimer: Application.Handle=$%x', [Application.Handle]));
    end
    else
      ExpertTrace('OnInitTimer: IOTAServices not supported');

    ExpertTrace('OnInitTimer: calling Registration.Register');
    Dext.Testing.Design.Registration.Register;
    ExpertTrace('OnInitTimer: Registration.Register returned OK');
  except
    on E: Exception do
    begin
      ExpertTrace('OnInitTimer EXCEPTION: ' + E.ClassName + ': ' + E.Message);
      MessageDlg('Dext Test Explorer failed to register:' + sLineBreak + E.Message +
        sLineBreak + sLineBreak + 'See %TEMP%\DextExpertLib.log',
        mtError, [mbOK], 0);
    end;
  end;
end;

function TDextExpertWizard.GetIDString: string;
begin
  Result := 'Dext.Testing.Design.ExpertLib';
end;

function TDextExpertWizard.GetName: string;
begin
  Result := 'Dext Test Explorer';
end;

function TDextExpertWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TDextExpertWizard.Execute;
begin
  ExpertTrace('TDextExpertWizard.Execute (no-op; use Tools menu)');
end;

procedure FinalizeWizard;
var
  WizardServices: IOTAWizardServices;
begin
  ExpertTrace('FinalizeWizard: index=' + IntToStr(GWizardIndex));
  if GWizardIndex <> InvalidWizardIndex then
  begin
    if Assigned(BorlandIDEServices) then
    begin
      WizardServices := BorlandIDEServices as IOTAWizardServices;
      WizardServices.RemoveWizard(GWizardIndex);
    end;
    GWizardIndex := InvalidWizardIndex;
  end;
end;

function InitWizard(const BorlandIDEServices: IBorlandIDEServices;
  RegisterProc: TWizardRegisterProc;
  var Terminate: TWizardTerminateProc): Boolean; stdcall;
var
  WizardServices: IOTAWizardServices;
begin
  ExpertTrace('InitWizard: enter');
  ExpertTrace(Format('InitWizard: param Assigned=%s RegisterProc Assigned=%s',
    [BoolToStr(Assigned(BorlandIDEServices), True),
     BoolToStr(Assigned(RegisterProc), True)]));
  ExpertTrace(Format('InitWizard: ToolsAPI.BorlandIDEServices Assigned=%s same=%s',
    [BoolToStr(Assigned(ToolsAPI.BorlandIDEServices), True),
     BoolToStr(ToolsAPI.BorlandIDEServices = BorlandIDEServices, True)]));

  Result := Assigned(BorlandIDEServices);
  if not Result then
  begin
    ExpertTrace('InitWizard: FAIL — BorlandIDEServices is nil');
    Exit;
  end;

  { Ensure global is set (GExperts asserts equality; assign if missing). }
  if not Assigned(ToolsAPI.BorlandIDEServices) then
  begin
    ToolsAPI.BorlandIDEServices := BorlandIDEServices;
    ExpertTrace('InitWizard: assigned ToolsAPI.BorlandIDEServices from param');
  end;

  Terminate := FinalizeWizard;
  try
    WizardServices := BorlandIDEServices as IOTAWizardServices;
    ExpertTrace('InitWizard: calling AddWizard');
    GWizardIndex := WizardServices.AddWizard(TDextExpertWizard.Create as IOTAWizard);
    ExpertTrace('InitWizard: AddWizard returned index=' + IntToStr(GWizardIndex));
    Result := GWizardIndex >= 0;
    if not Result then
      ExpertTrace('InitWizard: FAIL — AddWizard returned negative index');
  except
    on E: Exception do
    begin
      ExpertTrace('InitWizard EXCEPTION: ' + E.ClassName + ': ' + E.Message);
      Result := False;
    end;
  end;
  ExpertTrace('InitWizard: leave Result=' + BoolToStr(Result, True));
end;

exports
  InitWizard name WizardEntryPoint;

begin
  ExpertTrace('=== library Dext.Testing.Design.ExpertLib loaded ===');
  ExpertTrace('Module: ' + GetModuleName(HInstance));
end.
