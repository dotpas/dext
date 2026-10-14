unit Dext.Testing.CodeCoverage.Tool;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Net.HttpClient,
  System.Zip;

type
  /// <summary>
  ///   Locate / install DelphiCodeCoverage.exe for CLI and IDE Test Explorer.
  /// </summary>
  TDextCodeCoverageTool = class
  public
    /// <summary>
    ///   Search order: ConfiguredPath → next to app → walk-up Libs\DelphiCodeCoverage\{Platform}
    ///   → PATH → %HOME%\.dext\tools\DelphiCodeCoverage.
    /// </summary>
    class function FindPath(const TargetPlatform: string = 'Win32';
      const ConfiguredPath: string = ''): string;
    class procedure InstallLatest(out InstalledPath: string);
    class function ToolsHomeDir: string;
  end;

implementation

const
  LIBS_PATH = 'Libs\DelphiCodeCoverage';
  GITHUB_LATEST = 'https://api.github.com/repos/DelphiCodeCoverage/DelphiCodeCoverage/releases/latest';

{ TDextCodeCoverageTool }

class function TDextCodeCoverageTool.ToolsHomeDir: string;
begin
  Result := TPath.Combine(TPath.GetHomePath, '.dext\tools\DelphiCodeCoverage');
end;

class function TDextCodeCoverageTool.FindPath(const TargetPlatform, ConfiguredPath: string): string;
var
  AppDir: string;
  Candidate: string;
  Current: string;
  I: Integer;
  ToolsDir: string;
  SubDirs: TArray<string>;
  PlatformFolder: string;
begin
  if (ConfiguredPath <> '') and FileExists(ConfiguredPath) then
    Exit(ConfiguredPath);

  PlatformFolder := TargetPlatform;
  if PlatformFolder = '' then
    PlatformFolder := 'Win32';

  AppDir := ExtractFileDir(ParamStr(0));

  Candidate := TPath.Combine(AppDir, 'CodeCoverage.exe');
  if FileExists(Candidate) then
    Exit(Candidate);

  Current := AppDir;
  for I := 1 to 8 do
  begin
    Candidate := TPath.Combine(Current, 'Tools\DelphiCodeCoverage\CodeCoverage.exe');
    if FileExists(Candidate) then
      Exit(Candidate);

    Candidate := TPath.Combine(Current,
      Format('%s\%s\CodeCoverage.exe', [LIBS_PATH, PlatformFolder]));
    if FileExists(Candidate) then
      Exit(Candidate);

    // Flat layout without platform subfolder
    Candidate := TPath.Combine(Current, LIBS_PATH + '\CodeCoverage.exe');
    if FileExists(Candidate) then
      Exit(Candidate);

    Current := TPath.GetDirectoryName(Current);
    if (Current = '') or (Current = TPath.GetPathRoot(Current)) then
      Break;
  end;

  if FileSearch('CodeCoverage.exe', GetEnvironmentVariable('PATH')) <> '' then
    Exit('CodeCoverage.exe');

  ToolsDir := ToolsHomeDir;
  if TDirectory.Exists(ToolsDir) then
  begin
    Candidate := TPath.Combine(ToolsDir, 'CodeCoverage.exe');
    if FileExists(Candidate) then
      Exit(Candidate);

    Candidate := TPath.Combine(ToolsDir, PlatformFolder + '\CodeCoverage.exe');
    if FileExists(Candidate) then
      Exit(Candidate);

    SubDirs := TDirectory.GetDirectories(ToolsDir);
    if Length(SubDirs) > 0 then
    begin
      Candidate := TPath.Combine(SubDirs[0], 'CodeCoverage.exe');
      if FileExists(Candidate) then
        Exit(Candidate);
    end;
  end;

  Result := '';
end;

class procedure TDextCodeCoverageTool.InstallLatest(out InstalledPath: string);
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
  ToolsDir := ToolsHomeDir;
  ForceDirectories(ToolsDir);

  Client := THTTPClient.Create;
  ZipStream := TMemoryStream.Create;
  try
    try
      Client.UserAgent := 'Dext';
      Resp := Client.Get(GITHUB_LATEST);

      if Resp.StatusCode <> 200 then
        raise Exception.CreateFmt('Error checking latest version: %s (%d)',
          [Resp.StatusText, Resp.StatusCode]);

      JsonRoot := TJSONObject.ParseJSONValue(Resp.ContentAsString(TEncoding.UTF8));
      try
        if (JsonRoot = nil) or (not JsonRoot.TryGetValue<TJSONArray>('assets', Assets)) then
          raise Exception.Create('Error parsing GitHub API response.');

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
        if Resp.StatusCode <> 200 then
          raise Exception.CreateFmt('Download failed: %s', [Resp.StatusText]);

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
