{***************************************************************************}
{           Dext Framework                                                  }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{***************************************************************************}
unit Dext.Logging.Global;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Logging,
  Dext.Logging.Async,
  Dext.Logging.Sinks,
  Dext.Logging.Sinks.Sidecar,
  Dext.Logging.Telemetry,
  Dext.Options;

type
  /// <summary>
  ///   Provides a static entry point for application-wide logging.
  /// </summary>
  Log = class
  private
    class var FLogger: ILogger;
    class var FFactory: TAsyncLoggerFactory;
    class var FMetricsExporter: TThread;
    class var FMetricsObserver: ITelemetryObserver;
    class function GetLogger: ILogger; static;
  public
    class constructor Create;
    class destructor Destroy;
    
    /// <summary>
    ///   Initializes the global logger with default sinks (Console, File).
    ///   Calling this is optional; if not called, default config is used on first access.
    /// </summary>
    class procedure Initialize;
    
    /// <summary>
    ///   Adds a custom sink to the global logging pipeline.
    /// </summary>
    class procedure AddSink(const ASink: ILogSink);

    /// <summary>
    ///   True when the global logger has at least one sink. Callers on hot
    ///   paths (the test runner) skip scopes and formatting when nothing
    ///   would receive them. Does not initialize the logger.
    /// </summary>
    class function HasSinks: Boolean;
    
    /// <summary>
    ///   Access the global logger instance.
    /// </summary>
    class property Logger: ILogger read GetLogger;
    
    // Convenience proxies (optional, but requested "Static Registry")
    
    class procedure Trace(const AMessage: string); overload;
    class procedure Trace(const AMessage: string; const AArgs: array of const); overload;
    
    class procedure Debug(const AMessage: string); overload;
    class procedure Debug(const AMessage: string; const AArgs: array of const); overload;
    
    class procedure Info(const AMessage: string); overload;
    class procedure Info(const AMessage: string; const AArgs: array of const); overload;
    
    class procedure Warn(const AMessage: string); overload;
    class procedure Warn(const AMessage: string; const AArgs: array of const); overload;
    
    class procedure Error(const AMessage: string); overload;
    class procedure Error(const AMessage: string; const AArgs: array of const); overload;
    class procedure Error(const AException: Exception; const AMessage: string; const AArgs: array of const); overload;
    
    class procedure Critical(const AMessage: string); overload;
    class procedure Critical(const AMessage: string; const AArgs: array of const); overload;
    class procedure Critical(const AException: Exception; const AMessage: string; const AArgs: array of const); overload;
    
    class procedure LogGeneric(ALevel: TLogLevel; const AMessage: string; const AArgs: array of const); overload;
    class procedure LogGeneric(ALevel: TLogLevel; const AException: Exception; const AMessage: string; const AArgs: array of const); overload;
    // ... add more as needed
  end;

implementation

uses
  Dext.Utils,
  Dext;

{ Log }

class constructor Log.Create;
begin
  FLogger := nil;
  FFactory := nil;
end;

class destructor Log.Destroy;
begin
  FLogger := nil;
  
  if FMetricsExporter <> nil then
  begin
    FMetricsExporter.Terminate;
    FMetricsExporter.WaitFor;
    FMetricsExporter.Free;
    FMetricsExporter := nil;
  end;
  
  if FMetricsObserver <> nil then
  begin
    if TDiagnosticSource.Instance <> nil then
      TDiagnosticSource.Instance.Unsubscribe(FMetricsObserver);
    FMetricsObserver := nil;
  end;

  if FFactory <> nil then
  begin
    FFactory.Dispose;
    FFactory.Free;
  end;
end;

class procedure Log.Initialize;
var
  PortStr: string;
  EnabledStr: string;
  Port: Integer;
  IsTestMode: Boolean;
  SidecarUrl: string;
  Options: IOptions<TSidecarOptions>;
  Enabled: Boolean;
begin
  if FFactory <> nil then Exit; // Already initialized

  FFactory := TAsyncLoggerFactory.Create;
  
  // Default Sinks (Disable console sink in test mode to keep runner output clean)
  IsTestMode := (Pos('.tests', LowerCase(ExtractFileName(ParamStr(0)))) > 0) or
    (GetEnvironmentVariable('DEXT_PROJECT_TYPE') = 'Tests') or
    FindCmdLineSwitch('no-wait');

  if not IsTestMode then
    FFactory.AddSink(TConsoleSink.Create);

  // Sidecar: off unless configured explicitly (DEXT_SIDECAR_ENABLED=true or
  // TSidecarOptions.Enabled). There is no auto-detection: probing a closed
  // port on Windows loopback takes ~2 s per address (::1, then 127.0.0.1), so
  // every process without a Sidecar paid ~4 s on its first log call.
  Port := 3030;
  Enabled := False;

  // 1. Environment Variable
  PortStr := GetEnvironmentVariable('DEXT_SIDECAR_PORT');
  if PortStr <> '' then
    Port := StrToIntDef(PortStr, 3030);

  EnabledStr := GetEnvironmentVariable('DEXT_SIDECAR_ENABLED');
  if EnabledStr <> '' then
    Enabled := SameText(EnabledStr, 'true');

  // 2. IOptions (if available via Default Provider)
  try
    Options := TDextServices.GetService<IOptions<TSidecarOptions>>(TDextServices.DefaultProvider);
    if (Options <> nil) and (Options.Value <> nil) then
    begin
      if Options.Value.Port <> 0 then
        Port := Options.Value.Port;
        
      if EnabledStr = '' then
        Enabled := Options.Value.Enabled;
    end;
  except
    // Provider might not be ready or Options not registered, ignore
  end;

  if Enabled then
  begin
    SidecarUrl := 'http://localhost:' + Port.ToString;
    SafeWriteLn('>> [Log] Initializing Sidecar Sink at ' + SidecarUrl);
    FFactory.AddSink(TSidecarSink.Create(SidecarUrl));
    TDiagnosticSource.Instance.Subscribe(TSidecarTelemetryObserver.Create(SidecarUrl));
    
    // Subscribe metrics aggregator observer to DiagnosticSource
    FMetricsObserver := TMetricsTelemetryObserver.Create;
    TDiagnosticSource.Instance.Subscribe(FMetricsObserver);
    
    // Launch periodic background metrics exporter
    FMetricsExporter := TSidecarMetricsExporter.Create(SidecarUrl);
  end;
  
  // Create the Logger instance
  FLogger := FFactory.CreateLogger('App');
  if Enabled then
    SafeWriteLn('>> [Log] Logger initialized (Sidecar enabled)')
  else
    SafeWriteLn('>> [Log] Logger initialized (Sidecar disabled)');
end;

class procedure Log.AddSink(const ASink: ILogSink);
begin
  if FFactory = nil then
    Initialize;
  FFactory.AddSink(ASink);
end;

class function Log.HasSinks: Boolean;
begin
  Result := (FFactory <> nil) and FFactory.HasSinks;
end;

class function Log.GetLogger: ILogger;
begin
  if FLogger = nil then
    Initialize;
  Result := FLogger;
end;

class procedure Log.Trace(const AMessage: string);
begin
  Logger.Trace(AMessage, []);
end;

class procedure Log.Trace(const AMessage: string; const AArgs: array of const);
begin
  Logger.Trace(AMessage, AArgs);
end;

class procedure Log.Debug(const AMessage: string);
begin
  Logger.Debug(AMessage, []);
end;

class procedure Log.Debug(const AMessage: string; const AArgs: array of const);
begin
  Logger.Debug(AMessage, AArgs);
end;

class procedure Log.Info(const AMessage: string);
begin
  Logger.Info(AMessage, []);
end;

class procedure Log.Info(const AMessage: string; const AArgs: array of const);
begin
  Logger.Info(AMessage, AArgs);
end;

class procedure Log.Warn(const AMessage: string);
begin
  Logger.Warn(AMessage, []);
end;

class procedure Log.Warn(const AMessage: string; const AArgs: array of const);
begin
  Logger.Warn(AMessage, AArgs);
end;

class procedure Log.Error(const AMessage: string);
begin
  Logger.Error(AMessage, []);
end;

class procedure Log.Error(const AMessage: string; const AArgs: array of const);
begin
  Logger.Error(AMessage, AArgs);
end;

class procedure Log.Error(const AException: Exception; const AMessage: string; const AArgs: array of const);
begin
  Logger.Error(AException, AMessage, AArgs);
end;

class procedure Log.Critical(const AMessage: string);
begin
  Logger.Critical(AMessage, []);
end;

class procedure Log.Critical(const AMessage: string; const AArgs: array of const);
begin
  Logger.Critical(AMessage, AArgs);
end;

class procedure Log.Critical(const AException: Exception; const AMessage: string; const AArgs: array of const);
begin
  Logger.Critical(AException, AMessage, AArgs);
end;

class procedure Log.LogGeneric(ALevel: TLogLevel; const AMessage: string; const AArgs: array of const);
begin
  Logger.Log(ALevel, AMessage, AArgs);
end;

class procedure Log.LogGeneric(ALevel: TLogLevel; const AException: Exception; const AMessage: string; const AArgs: array of const);
begin
  Logger.Log(ALevel, AException, AMessage, AArgs);
end;

end.
