unit Dext.Hosting.CLI.Tools.CodeCoverage;

interface

uses
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  System.Net.HttpClient,
  System.SysUtils,
  System.Zip,
  Dext.Hosting.CLI.Config;

type
  TCodeCoverageTool = class
  public
    class function FindPath(GlobalConfig: TDextGlobalConfig; const TargetPlatform: string = 'Win32'): string;
    class procedure InstallLatest(out InstalledPath: string);
  end;

implementation

{ TCodeCoverageTool }

class function TCodeCoverageTool.FindPath(GlobalConfig: TDextGlobalConfig; const TargetPlatform: string): string;
var
  AppDir: string;
  Candidate: string;
  Current: string;
  I: Integer;
  ToolsDir: string;
  SubDirs: TArray<string>;
const
  LIBS_PATH = 'Libs\DelphiCodeCoverage';
begin
  // 1. Check Global Config
  if (GlobalConfig <> nil) and (GlobalConfig.CoveragePath <> '') and FileExists(GlobalConfig.CoveragePath) then
    Exit(GlobalConfig.CoveragePath);

  // 2. App Local
  Result := 'CodeCoverage.exe';

  AppDir := ExtractFileDir(ParamStr(0));

  Candidate := TPath.Combine(AppDir, 'CodeCoverage.exe');
  if FileExists(Candidate) then Exit(Candidate);

  Current := AppDir;
  for I := 1 to 8 do
  begin
    Candidate := TPath.Combine(Current, 'Tools\DelphiCodeCoverage\CodeCoverage.exe');
    if FileExists(Candidate) then Exit(Candidate);

    Candidate := TPath.Combine(Current, Format('%s\%s\CodeCoverage.exe', [LIBS_PATH, TargetPlatform]));
    if FileExists(Candidate) then Exit(Candidate);

    Candidate := TPath.Combine(Current, LIBS_PATH + '\CodeCoverage.exe');
    if FileExists(Candidate) then Exit(Candidate);

    Current := TPath.GetDirectoryName(Current);
    if (Current = '') or (Current = TPath.GetPathRoot(Current)) then Break;
  end;

  // 3. System PATH
  if FileSearch('CodeCoverage.exe', GetEnvironmentVariable('PATH')) <> '' then
     Exit('CodeCoverage.exe');

  // 4. Global Tools (.dext/tools)
  ToolsDir := TPath.Combine(TPath.GetHomePath, '.dext\tools\DelphiCodeCoverage');
  if TDirectory.Exists(ToolsDir) then
  begin
    Candidate := TPath.Combine(ToolsDir, 'CodeCoverage.exe');
    if FileExists(Candidate) then Exit(Candidate);

    Candidate := TPath.Combine(ToolsDir, TargetPlatform + '\CodeCoverage.exe');
    if FileExists(Candidate) then Exit(Candidate);

    SubDirs := TDirectory.GetDirectories(ToolsDir);
    if Length(SubDirs) > 0 then
    begin
       Candidate := TPath.Combine(SubDirs[0], 'CodeCoverage.exe');
       if FileExists(Candidate) then Exit(Candidate);
    end;
  end;

  Result := '';
end;

class procedure TCodeCoverageTool.InstallLatest(out InstalledPath: string);
const
  API_URL = 'https://api.github.com/repos/DelphiCodeCoverage/DelphiCodeCoverage/releases/latest';
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  ZipStream: TMemoryStream;
  ToolsDir: string;
  JsonRoot: TJSONValue;
  Assets: TJSONArray;
  Asset: TJSONValue;
  DownloadUrl: string;
  FileName: string;
  I: Integer;
  Zip: TZipFile;
  SubDirs: TArray<string>;
begin
  InstalledPath := '';
  ToolsDir := TPath.Combine(TPath.GetHomePath, '.dext\tools\DelphiCodeCoverage');

  ForceDirectories(ToolsDir);

  Client := THTTPClient.Create;
  ZipStream := TMemoryStream.Create;
  try
    try
      Client.UserAgent := 'DextCLI';
      Resp := Client.Get(API_URL);

      if Resp.StatusCode <> 200 then
        raise Exception.CreateFmt('Error checking latest version: %s (%d)', [Resp.StatusText, Resp.StatusCode]);

      JsonRoot := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
      try
        if (JsonRoot <> nil) and (JsonRoot.TryGetValue<TJSONArray>('assets', Assets)) then
        begin
             DownloadUrl := '';
             for I := 0 to Assets.Count - 1 do
             begin
               Asset := Assets.Items[I];
               FileName := Asset.GetValue<string>('name', '');
               if FileName.EndsWith('.zip', True) then
               begin
                  DownloadUrl := Asset.GetValue<string>('browser_download_url', '');
                  Break;
               end;
             end;

             if DownloadUrl = '' then
                raise Exception.Create('No ZIP asset found in latest GitHub release.');

             ZipStream.Clear;
             Resp := Client.Get(DownloadUrl, ZipStream);

             if Resp.StatusCode = 200 then
             begin
               ZipStream.Position := 0;

               Zip := TZipFile.Create;
               try
                 Zip.Open(ZipStream, zmRead);
                 Zip.ExtractAll(ToolsDir);
                 Zip.Close;
               finally
                 Zip.Free;
               end;

               InstalledPath := TPath.Combine(ToolsDir, 'CodeCoverage.exe');

               if not FileExists(InstalledPath) then
               begin
                  SubDirs := TDirectory.GetDirectories(ToolsDir);
                  if Length(SubDirs) > 0 then
                     InstalledPath := TPath.Combine(SubDirs[0], 'CodeCoverage.exe');
               end;

               if not FileExists(InstalledPath) then
                  raise Exception.Create('CodeCoverage.exe not found after extraction.');
             end
             else
             begin
                raise Exception.CreateFmt('Download failed: %s', [Resp.StatusText]);
             end;
        end
        else
        begin
           raise Exception.Create('Error parsing GitHub API response.');
        end;
      finally
        JsonRoot.Free;
      end;

    except
      on E: Exception do
        raise Exception.Create('CodeCoverage Install Error: ' + E.Message);
    end;
  finally
    ZipStream.Free;
    Client.Free;
  end;
end;

end.
