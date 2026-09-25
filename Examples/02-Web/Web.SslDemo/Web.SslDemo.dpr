program Web.SslDemo;

{$APPTYPE CONSOLE}

{ ==============================================================================
  CONFIGURAÇÃO DO DEMO DE SSL/HTTPS
  Descomente uma opção para Server Engine e uma opção para SSL Provider
  ============================================================================== }

// --- 1. SELEÇÃO DO SERVER ENGINE ---
{$DEFINE USE_NATIVE_SERVER}  // Usar Server Engine Nativo (.UseNativeServer: http.sys no Windows / epoll no Linux)
{.$DEFINE USE_INDY_SERVER}     // Usar Indy Server Engine (Padrão para Demo sem registro admin no http.sys)

// --- 2. SELEÇÃO DO PROVEDOR SSL / TLS ---
{$DEFINE SSL_PROVIDER_OPENSSL}  // OpenSSL 3.x / 1.1.x
{.$DEFINE SSL_PROVIDER_TAURUS}
{.$DEFINE SSL_PROVIDER_OPENSSL}  // OpenSSL 1.0.2 / 1.1.x
{$IFDEF MSWINDOWS}
  {$DEFINE SSL_PROVIDER_HTTPSYS} // Windows Kernel Schannel (http.sys)
{$ELSE}
  {$DEFINE SSL_PROVIDER_OPENSSL} // Linux native OpenSSL (epoll)
{$ENDIF}

uses
  Dext.MM,
  System.SysUtils,
  System.IOUtils,
  Dext,
  Dext.Utils,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Configuration.Interfaces;

procedure EnsureAppSettings;
const
  {$IFDEF SSL_PROVIDER_HTTPSYS}
  SELECTED_PROVIDER = 'HttpSys';
  {$ELSE}
    {$IFDEF SSL_PROVIDER_OPENSSL}
    SELECTED_PROVIDER = 'OpenSSL';
    {$ELSE}
    SELECTED_PROVIDER = 'Taurus';
    {$ENDIF}
  {$ENDIF}

  DEFAULT_SETTINGS =
    '{' + sLineBreak +
    '    "Server": {' + sLineBreak +
    '        "Port": 8080,' + sLineBreak +
    '        "UseHttps": "true",' + sLineBreak +
    '        "SslProvider": "' + SELECTED_PROVIDER + '",' + sLineBreak +
    '        "SslCertHash": "BE93CEF4B0A4727477B432A801B3F2DC000AAC34",' + sLineBreak +
    '        "SslCert": "server.crt",' + sLineBreak +
    '        "SslKey": "server.key",' + sLineBreak +
    '        "SslRootCert": ""' + sLineBreak +
    '    },' + sLineBreak +
    '    "Logging": {' + sLineBreak +
    '        "LogLevel": "Information"' + sLineBreak +
    '    }' + sLineBreak +
    '}';
begin
  if FileExists('appsettings.json') then
    Exit;
  Writeln('Creating/Updating default appsettings.json...');
  TFile.WriteAllText('appsettings.json', DEFAULT_SETTINGS);
end;

procedure EnsureCertificates;
var
  SourcePath: string;
  Paths: TArray<string>;
  Path: string;
  CheckPath: string;
begin
  if FileExists('server.crt') and FileExists('server.key') then
    Exit;

  Writeln('Certificates not found in output directory.');

  Paths := [
    '..\02-Web\Web.SslDemo',
    '..\..\02-Web\Web.SslDemo',
    '..\Examples\Web.SslDemo',
    '..\..\Examples\Web.SslDemo',
    '..\..\..\Examples\Web.SslDemo',
    '..\..\..\..\Examples\Web.SslDemo'
  ];

  SourcePath := '';
  for Path in Paths do
  begin
    CheckPath := TPath.GetFullPath(Path);
    if FileExists(TPath.Combine(CheckPath, 'server.crt')) then
    begin
      SourcePath := CheckPath;
      Break;
    end;
  end;

  if (SourcePath <> '') and FileExists(TPath.Combine(SourcePath, 'server.crt')) then
  begin
    Writeln('Copying certificates from source directory: ', SourcePath);
    TFile.Copy(TPath.Combine(SourcePath, 'server.crt'), 'server.crt', True);
    TFile.Copy(TPath.Combine(SourcePath, 'server.key'), 'server.key', True);
    Exit;
  end;

  Writeln('[WARNING] Certificates not found! Run "dext dev-certs https" to generate.');
end;

var
  App: IWebApplication;
  Config: IConfigurationSection;
  Port: Integer;
  UseHttps: Boolean;
begin
  try
    SetConsoleCharSet;
    Writeln('🔒 Dext SSL/HTTPS Enforced Demo');
    Writeln('-------------------------------');

    EnsureAppSettings;
    EnsureCertificates;

    App := TDextApplication.Create;

    Config := App.Configuration.GetSection('Server');
    Port := 8080;
    UseHttps := True;

    if (Config <> nil) and (Config['Port'] <> '') then
      Port := StrToIntDef(Config['Port'], 8080);

    if (Config <> nil) and (Config['UseHttps'] <> '') then
      UseHttps := SameText(Config['UseHttps'], 'true');

    {$IFDEF USE_NATIVE_SERVER}
    App.UseNativeServer;
    Writeln('⚙️ Server Engine: NATIVE (.UseNativeServer -> http.sys on Windows / epoll on Linux)');
    {$ELSE}
    Writeln('⚙️ Server Engine: INDY (Default)');
    {$ENDIF}

    if not UseHttps then
      raise Exception.Create('SSL is REQUIRED for this demo. Please set "UseHttps": "true" in appsettings.json.');

    Writeln('🚀 Configuration Loaded (HTTPS Enforced):');
    Writeln('   Port:     ', Port);
    if (Config <> nil) and (Config['SslProvider'] <> '') then
      Writeln('   Provider: ', Config['SslProvider'])
    else
      Writeln('   Provider: Taurus');

    if (Config <> nil) and (Config['SslCert'] <> '') then
      Writeln('   Cert:     ', Config['SslCert'])
    else
      Writeln('   Cert:     server.crt');

    if (Config <> nil) and (Config['SslKey'] <> '') then
      Writeln('   Key:      ', Config['SslKey'])
    else
      Writeln('   Key:      server.key');

    if not SameText(Config['SslProvider'], 'HttpSys') then
    begin
      if not FileExists(Config['SslCert']) then
        raise Exception.Create('Certificate file not found: ' + Config['SslCert']);
      if not FileExists(Config['SslKey']) then
        raise Exception.Create('Key file not found: ' + Config['SslKey']);
    end;

    Writeln('');

    App.Builder.UseHttpLogging;
    App.Builder.UseDeveloperExceptionPage;
    App.Builder
      .MapGet('/',
        procedure(Context: IHttpContext)
        begin
          Context.Response.SetStatusCode(200);
          Context.Response.SetContentType('text/html; charset=utf-8');
          Context.Response.Write('<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>' +
            '<h1>🔒 Dext SSL Demo</h1>' +
            '<p>This server is strictly enforced to run over HTTPS.</p>' +
            '<p>Address: <a href="https://localhost:' + Port.ToString + '">https://localhost:' + Port.ToString + '</a></p>' +
            '</body></html>');
        end);

    App.Run(Port);
  except
    on E: Exception do
    begin
      Writeln('❌ Fatal Error: ', E.Message);
      Sleep(3000);
    end;
  end;
  ConsolePause;
end.
