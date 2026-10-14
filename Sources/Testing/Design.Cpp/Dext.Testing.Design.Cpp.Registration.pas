{***************************************************************************}
{  Dext Test Explorer — C++Builder personality registration (scaffold)     }
{  Not production-ready: discovery must define runner adapters first.        }
{***************************************************************************}
unit Dext.Testing.Design.Cpp.Registration;

interface

procedure Register;
procedure Unregister;

implementation

uses
  System.SysUtils,
  ToolsAPI;

procedure Register;
begin
  // Placeholder: register Tools menu + dockable form for C++Builder personality
  // after S75 discovery completes. Delphi Expert remains in Design.Expert.pas.
  OutputDebugString(PChar('[Dext.Cpp] Registration scaffold loaded — not active.'));
end;

procedure Unregister;
begin
  OutputDebugString(PChar('[Dext.Cpp] Unregistration scaffold.'));
end;

initialization
finalization
  // Intentionally empty until package is wired.

end.
