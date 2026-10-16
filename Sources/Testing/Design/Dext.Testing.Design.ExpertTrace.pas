unit Dext.Testing.Design.ExpertTrace;

{ Always-on file trace for Expert DLL diagnosis. Log: %TEMP%\DextExpertLib.log }

interface

procedure ExpertTrace(const AMsg: string);
function ExpertTraceLogPath: string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.SyncObjs,
  Winapi.Windows;

var
  GLock: TCriticalSection = nil;

function ExpertTraceLogPath: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'DextExpertLib.log');
end;

procedure ExpertTrace(const AMsg: string);
var
  Path: string;
  Line: string;
  F: TextFile;
begin
  Line := Format('[%s] [pid=%d] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), GetCurrentProcessId, AMsg]);
  OutputDebugString(PChar('[DextExpertLib] ' + AMsg));

  if GLock = nil then
    Exit;
  GLock.Enter;
  try
    try
      Path := ExpertTraceLogPath;
      AssignFile(F, Path);
      if TFile.Exists(Path) then
        Append(F)
      else
        Rewrite(F);
      try
        WriteLn(F, Line);
      finally
        CloseFile(F);
      end;
    except
      { never break the IDE because of logging }
    end;
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  ExpertTrace('=== ExpertTrace unit initialized ===');
  ExpertTrace('Log file: ' + ExpertTraceLogPath);

finalization
  ExpertTrace('=== ExpertTrace unit finalizing ===');
  FreeAndNil(GLock);

end.
