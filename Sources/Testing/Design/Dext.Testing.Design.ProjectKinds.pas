{***************************************************************************}
{  Helpers: Delphi (.dproj) and C++Builder (.cbproj) test projects           }
{***************************************************************************}
unit Dext.Testing.Design.ProjectKinds;

interface

uses
  System.SysUtils,
  ToolsAPI;

/// <summary>True for Delphi or C++Builder project extensions.</summary>
function IsIdeProjectExt(const AFileName: string): Boolean;

/// <summary>True if the path looks like a unit-test project (name contains test).</summary>
function IsLikelyTestProjectFile(const AFileName: string): Boolean;

/// <summary>True for Delphi personality or C++Builder personality.</summary>
function IsSupportedProjectPersonality(const AProject: IOTAProject): Boolean;

/// <summary>Compile via IOTAProjectBuilder (works for .dproj and .cbproj).</summary>
function CompileProjectViaOTA(const AProjFile: string): Boolean;

implementation

uses
  System.IOUtils;

function IsIdeProjectExt(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := ExtractFileExt(AFileName);
  Result := SameText(Ext, '.dproj') or SameText(Ext, '.cbproj');
end;

function IsLikelyTestProjectFile(const AFileName: string): Boolean;
var
  Lower: string;
begin
  if not IsIdeProjectExt(AFileName) then
    Exit(False);
  { Only the project file name — folder names like ...\CppProjectsTests\ would
    otherwise mark every .cbproj/.dproj in the group as a test project. }
  Lower := ChangeFileExt(ExtractFileName(AFileName), '').ToLower;
  Result := Lower.Contains('test') or Lower.Contains('tests');
end;

function IsSupportedProjectPersonality(const AProject: IOTAProject): Boolean;
begin
  Result := Assigned(AProject) and
    (SameText(AProject.Personality, sDelphiPersonality) or
     SameText(AProject.Personality, sCBuilderPersonality));
end;

function CompileProjectViaOTA(const AProjFile: string): Boolean;
var
  ModServices: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Proj: IOTAProject;
  Builder: IOTAProjectBuilder;
  i: Integer;
begin
  Result := False;
  if (AProjFile = '') or not FileExists(AProjFile) then
    Exit;
  if not Supports(BorlandIDEServices, IOTAModuleServices, ModServices) then
    Exit;
  Group := ModServices.MainProjectGroup;
  if not Assigned(Group) then
    Exit;
  Proj := nil;
  for i := 0 to Group.ProjectCount - 1 do
    if Assigned(Group.Projects[i]) and SameText(Group.Projects[i].FileName, AProjFile) then
    begin
      Proj := Group.Projects[i];
      Break;
    end;
  if not Assigned(Proj) then
    Exit;
  if not Supports(Proj.ProjectBuilder, IOTAProjectBuilder, Builder) then
    Exit;
  // Wait=True so Run All can launch the exe after a successful build.
  Result := Builder.BuildProject(cmOTABuild, True);
end;

end.
