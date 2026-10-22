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

unit Dext.Testing.Design.KnownEditors;

interface

/// <summary>
///   Asks every editor the IDE already knows about to repaint.
///   Returns False when the IDE does not expose INTACodeEditorServices.
/// </summary>
function InvalidateKnownCodeEditors: Boolean;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.Controls,
  ToolsAPI,
  ToolsAPI.Editor;

function InvalidateKnownCodeEditors: Boolean;
var
  Services: INTACodeEditorServices;
  Editors: TList<TWinControl>;
  Editor: TWinControl;
begin
  Result := Supports(BorlandIDEServices, INTACodeEditorServices, Services);
  if not Result then
    Exit;
  Editors := Services.GetKnownEditors;
  try
    if Assigned(Editors) then
      for Editor in Editors do
        Services.InvalidateEditor(Editor);
  finally
    Editors.Free;
  end;
end;

end.
