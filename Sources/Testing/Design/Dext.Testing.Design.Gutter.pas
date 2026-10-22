unit Dext.Testing.Design.Gutter;

interface

procedure RegisterGutterVisualizer;
procedure UnregisterGutterVisualizer;

implementation

uses
  System.SysUtils, ToolsAPI, Dext.Testing.Design.Coverage;

var
  FKeyboardBindingIndex: Integer = -1;

procedure RegisterGutterVisualizer;
var
  LKeyboardServices: IOTAKeyboardServices;
begin
  RegisterCoverageEditorPainting;

  if Supports(BorlandIDEServices, IOTAKeyboardServices, LKeyboardServices) then
  begin
    FKeyboardBindingIndex := LKeyboardServices.AddKeyboardBinding(TDextKeyboardBinding.Create);
  end;
  { No RefreshActiveViews at register — keep IDE file-open path clean. }
end;

procedure UnregisterGutterVisualizer;
var
  LKeyboardServices: IOTAKeyboardServices;
begin
  UnregisterCoverageEditorPainting;

  if FKeyboardBindingIndex <> -1 then
  begin
    if Supports(BorlandIDEServices, IOTAKeyboardServices, LKeyboardServices) then
      LKeyboardServices.RemoveKeyboardBinding(FKeyboardBindingIndex);
    FKeyboardBindingIndex := -1;
  end;
end;

end.
