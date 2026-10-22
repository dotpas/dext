unit Dext.Sidecar.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  System.JSON,
  System.Types,
  System.SyncObjs,
  Winapi.Windows,
  Dext.DI.Core,
  Dext.DI.Interfaces,
  Dext.Hosting.CLI.Logger,
  Dext.Hosting.CLI.Registry,
  Dext.Logging,
  Dext.Hosting.ApplicationLifetime,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.Hubs.Extensions,
  Dext.WebHost,
  Dext.Dashboard.Routes,
  Dext.Sidecar.LogStreamer,
  Dext.Sidecar.TestCompat;

type
  TSidecarServer = class
  private
    FHost: IWebHost;
    FPort: Integer;
    FRunning: Boolean;
    FTestingServer: TTestCompatServer;
  public
    constructor Create(APort: Integer = 3030);
    destructor Destroy; override;

    procedure Start;
    procedure Stop;

    function GetUrl: string;
    property Port: Integer read FPort;
    property Running: Boolean read FRunning;
  end;

implementation

{ TSidecarServer }

constructor TSidecarServer.Create(APort: Integer);
begin
  inherited Create;
  FPort := APort;
  FRunning := False;
end;

destructor TSidecarServer.Destroy;
begin
  Stop;
  inherited;
end;

function TSidecarServer.GetUrl: string;
begin
  Result := Format('http://localhost:%d', [FPort]);
end;

procedure TSidecarServer.Start;
begin
  if FRunning then Exit;
  FRunning := True;

  // Start external server compatibility server on port 8102
  FTestingServer := TTestCompatServer.Create(8102);
  FTestingServer.Start;

  // Build the host in the main thread
  // Using Start (non-blocking) allows us to run on Main Thread without freezing UI
  FHost := TWebHostBuilder.CreateDefault(nil)
    .UseUrls(Format('http://localhost:%d', [FPort]))
    .ConfigureServices(procedure(Services: IServiceCollection)
      var
        RegistryType: TServiceType;
        LoggerType: TServiceType;
        FactoryFunc: TFunc<IServiceProvider, TObject>;
      begin
        RegistryType := TServiceType.FromClass(TProjectRegistry);
        Services.AddSingleton(RegistryType, TProjectRegistry, nil);

        LoggerType := TServiceType.FromInterface(TypeInfo(ILoggerFactory));
        FactoryFunc := function(Provider: IServiceProvider): TObject
           begin
              Result := TLoggerFactory.Create; // Silent logger for Sidecar
           end;
        Services.AddSingleton(LoggerType, TClass(nil), FactoryFunc);

        // S23: Register Streamable Session Manager (IStreamableSessionManager)
        TDextServices.Create(Services).AddStreamableSessions;

        // Register Event Streamer
        Services.AddSingleton(TServiceType.FromInterface(TypeInfo(IEventStreamer)), TClass(nil),
          function(Provider: IServiceProvider): TObject
          var
            Mgr: IStreamableSessionManager;
          begin
            Mgr := TDextServices.GetService<IStreamableSessionManager>(Provider);
            Result := TEventStreamer.Create(Mgr) as TObject;
          end);
      end)


    .Configure(procedure(App: IApplicationBuilder)
      begin
        // S23: Start the Scavenger GC (checks every 60s, evicts after 30min idle)
        TAppBuilder.Create(App).UseStreamableSessions(60, 30);
        TDashboardRoutes.Configure(App);
      end)
    .Build;

  // This is the real Dext Dashboard host (tray sidecar). Prefer http.sys so
  // SignalR can negotiate WebSockets; SSE remains the client fallback.
  // Opt-out for locked-down machines: set env DEXT_SIDECAR_INDY=1
{$IFDEF MSWINDOWS}
  if GetEnvironmentVariable('DEXT_SIDECAR_INDY') <> '1' then
  begin
    var WebApp: IWebApplication;
    if Supports(FHost, IWebApplication, WebApp) then
      WebApp.UseNativeServer;
  end;
{$ENDIF}

  try
    FHost.Start;
  except
    on E: Exception do
      OutputDebugString(PChar('DextSidecar: Run Exception: ' + E.Message));
  end;
end;

procedure TSidecarServer.Stop;
var
  WebHost: IWebHost;
begin
  if not FRunning then Exit;

  // Signal the SSE and background threads to stop immediately
  TDashboardRoutes.StopServer;

  // 1. First, shutdown Hub connections (SSE/WS loops must exit before the host stops)
  THubExtensions.ShutdownHubs;

  // 2. Stop and free compatibility server
  if FTestingServer <> nil then
  begin
    FTestingServer.Stop;
    FTestingServer.Free;
    FTestingServer := nil;
  end;

  // 3. Capture local reference and clear field
  WebHost := FHost;
  FHost := nil;

  // 4. Signal stop on the local reference
  // This now triggers StopApplication inside TDextApplication
  if WebHost <> nil then
  begin
    try
      WebHost.Stop;
    except
      on E: Exception do
        OutputDebugString(PChar('DextSidecar: Stop Signal Error: ' + E.Message));
    end;
  end;

  // 5. Finally release the interface
  WebHost := nil;
  FRunning := False;
end;

end.

