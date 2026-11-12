{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2025-12-08                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Hosting.BackgroundService;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Dext.Collections,
  Dext.DI.Interfaces,
  Dext.Logging,
  Dext.Threading.CancellationToken;

type
  /// <summary>Defines the contract for services managed by the application host.</summary>
  IHostedService = interface
    ['{8D4F5E6A-1B2C-4D3E-9F0A-7B8C9D0E1F2A}']
    /// <summary>Starts service execution.</summary>
    procedure Start;
    /// <summary>Requests graceful service shutdown.</summary>
    procedure Stop;
  end;

  // ✅ Interface for THostedServiceManager to enable ARC management
  /// <summary>Orchestrator responsible for managing startup and shutdown of all hosted services.</summary>
  IHostedServiceManager = interface
    ['{F1E2D3C4-B5A6-7890-1234-567890ABCDEF}']
    /// <summary>Registers a new service to be managed.</summary>
    procedure RegisterService(Service: IHostedService);
    /// <summary>Starts all registered services asynchronously.</summary>
    procedure StartAsync(Token: ICancellationToken = nil);
    /// <summary>
    ///   Stops all registered services in reverse order. A TBackgroundService gets at
    ///   most its StopTimeoutMs to finish; when Token is cancelled the wait ends at
    ///   once (the service is still told to stop, but is not waited for).
    /// </summary>
    procedure StopAsync(Token: ICancellationToken = nil);
  end;

  TBackgroundService = class;

  /// <summary>
  ///   Thread execution wrapper for background services.
  /// </summary>
  TBackgroundServiceThread = class(TThread)
  private
    FService: TBackgroundService;
    FToken: ICancellationToken;
    FLogger: ILogger;
    FDone: TEvent;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(Service: TBackgroundService; Token: ICancellationToken; Logger: ILogger = nil);
    destructor Destroy; override;
    /// <summary>Signaled when Execute has returned (normally or by an exception).</summary>
    property Done: TEvent read FDone;
    /// <summary>Message of the exception that ended Execute, if any.</summary>
    property Error: string read FError;
  end;

  /// <summary>
  ///   Base class for implementing long-running services (Workers).
  ///   Automatically manages thread creation and cancellation signal (CancellationToken).
  /// </summary>
  TBackgroundService = class(TInterfacedObject, IHostedService)
  private
    const DEFAULT_STOP_TIMEOUT_MS = 30000;
  private
    FThread: TBackgroundServiceThread;
    FCancellationTokenSource: TCancellationTokenSource;
    FStopTimeoutMs: Cardinal;
    FStopTimeoutSet: Boolean;
    FLastError: string;
    function GetStopTimeoutMs: Cardinal;
    procedure SetStopTimeoutMs(const Value: Cardinal);
    function GetIsRunning: Boolean;
  protected
    /// <summary>
    ///   Abstract method where worker logic should be implemented. 
    ///   Must monitor <paramref name="Token"/> to terminate execution loop.
    /// </summary>
    procedure Execute(Token: ICancellationToken); virtual; abstract;
  public
    FLogger: ILogger; // Used by thread if assigned
    /// <summary>
    ///   Starts the background thread and cancellation management. Calling it while the
    ///   service is already running does nothing.
    /// </summary>
    procedure Start; virtual;
    /// <summary>
    ///   Triggers the cancellation signal and waits up to StopTimeoutMs for the thread to
    ///   finish (Graceful Shutdown). A thread that does not finish in time is detached: it
    ///   frees itself when Execute eventually returns, so the service object must outlive it.
    /// </summary>
    procedure Stop; virtual;
    /// <summary>
    ///   Like Stop, with an explicit deadline and an optional token that ends the wait early.
    ///   Returns True when the thread finished, False when it had to be abandoned.
    /// </summary>
    function Shutdown(ATimeoutMs: Cardinal; const AToken: ICancellationToken = nil): Boolean;
    /// <summary>Maximum wait of Stop (default 30000 ms; INFINITE waits forever).</summary>
    property StopTimeoutMs: Cardinal read GetStopTimeoutMs write SetStopTimeoutMs;
    /// <summary>True while the service thread is executing.</summary>
    property IsRunning: Boolean read GetIsRunning;
    /// <summary>Message of the exception that ended the last run, if it failed.</summary>
    property LastError: string read FLastError;
  end;

  /// <summary>
  ///   Manager that starts and stops all registered hosted services.
  /// </summary>
  THostedServiceManager = class(TInterfacedObject, IHostedServiceManager)
  private
    FServices: IList<IHostedService>;
    FLogger: ILogger;
  protected
    procedure LogInfo(const AMsg: string);
    procedure LogError(const AMsg: string);
  public
    constructor Create(ALogger: ILogger = nil);
    destructor Destroy; override;

    procedure RegisterService(Service: IHostedService);
    procedure StartAsync(Token: ICancellationToken = nil);
    procedure StopAsync(Token: ICancellationToken = nil);
  end;

  /// <summary>Builder used to register Background Services in the Dependency Injection container.</summary>
  TBackgroundServiceBuilder = record
    FServices: IServiceCollection;
    FHostedServices: IList<TClass>;
    FLoggerClass: TClass;
  public
    constructor Create(Services: IServiceCollection);
    function AddHostedService<T: class, constructor>: TBackgroundServiceBuilder; overload;
    function AddHostedService(AServiceClass: TClass): TBackgroundServiceBuilder; overload;
    /// <summary>Consolidates registrations and injects the Service Manager into the DI container.</summary>
    procedure Build;
  end;

  /// <summary>
  ///   Core extension methods for IServiceCollection.
  /// </summary>
  TDextServiceCollectionExtensions = class
  public
    /// <summary>
    ///   Adds background service infrastructure to the DI container.
    ///   Returns a builder for registering hosted services.
    /// </summary>
    class function AddBackgroundServices(Services: IServiceCollection): TBackgroundServiceBuilder;
  end;

  /// <summary>
  ///   Fluent extensions for TDextServices core features.
  /// </summary>
  TDextServiceExtensions = record helper for TDextServices
  public
    /// <summary>
    ///   Starts the Background Service builder chain.
    /// </summary>
    function AddBackgroundServices: TBackgroundServiceBuilder;
  end;

implementation

uses
  System.Diagnostics,
  Dext.Utils;

{ TBackgroundServiceThread }

constructor TBackgroundServiceThread.Create(Service: TBackgroundService; Token: ICancellationToken; Logger: ILogger);
begin
  inherited Create(True); // Create suspended
  FService := Service;
  FToken := Token;
  FLogger := Logger;
  FDone := TEvent.Create(nil, True, False, '');
  FreeOnTerminate := False;
end;

destructor TBackgroundServiceThread.Destroy;
begin
  FDone.Free;
  inherited;
end;

procedure TBackgroundServiceThread.Execute;
begin
  try
    try
      FService.Execute(FToken);
    except
      on E: Exception do
      begin
        FError := E.Message;
        if FLogger <> nil then
          FLogger.LogError('BackgroundService thread error: {0}', [E.Message])
        else
          SafeWriteLn(Format('❌ Error in BackgroundService thread: %s', [E.Message]));
      end;
    end;
  finally
    FDone.SetEvent;
  end;
end;

{ TBackgroundService }

function TBackgroundService.GetStopTimeoutMs: Cardinal;
begin
  if FStopTimeoutSet then
    Result := FStopTimeoutMs
  else
    Result := DEFAULT_STOP_TIMEOUT_MS;
end;

procedure TBackgroundService.SetStopTimeoutMs(const Value: Cardinal);
begin
  FStopTimeoutMs := Value;
  FStopTimeoutSet := True;
end;

function TBackgroundService.GetIsRunning: Boolean;
begin
  Result := (FThread <> nil) and (FThread.Done.WaitFor(0) <> wrSignaled);
end;

procedure TBackgroundService.Start;
begin
  if FThread <> nil then
  begin
    if GetIsRunning then
      Exit; // already running: a second Start must not leak a second thread
    // The previous run ended by itself: collect it before starting again.
    Shutdown(0);
  end;
  FLastError := '';
  FCancellationTokenSource := TCancellationTokenSource.Create;
  FThread := TBackgroundServiceThread.Create(Self, FCancellationTokenSource.Token, FLogger);
  FThread.Start;
end;

procedure TBackgroundService.Stop;
begin
  Shutdown(GetStopTimeoutMs);
end;

function TBackgroundService.Shutdown(ATimeoutMs: Cardinal;
  const AToken: ICancellationToken): Boolean;
var
  LWatch: TStopwatch;
  LSlice: Cardinal;
  LElapsed: Int64;
  LFinished: Boolean;
begin
  Result := True;
  if Assigned(FCancellationTokenSource) then
    FCancellationTokenSource.Cancel;

  if Assigned(FThread) then
  begin
    // The thread is never terminated abruptly: Execute must observe its token and
    // return. We wait for it, but not forever.
    LWatch := TStopwatch.StartNew;
    LFinished := False;
    while True do
    begin
      LSlice := 50;
      if ATimeoutMs <> INFINITE then
      begin
        LElapsed := LWatch.ElapsedMilliseconds;
        if LElapsed >= ATimeoutMs then
        begin
          LFinished := FThread.Done.WaitFor(0) = wrSignaled;
          Break;
        end;
        if Int64(ATimeoutMs) - LElapsed < LSlice then
          LSlice := Cardinal(Int64(ATimeoutMs) - LElapsed);
      end
      else if AToken = nil then
        LSlice := INFINITE;
      if FThread.Done.WaitFor(LSlice) = wrSignaled then
      begin
        LFinished := True;
        Break;
      end;
      if (AToken <> nil) and AToken.IsCancellationRequested then
      begin
        LFinished := FThread.Done.WaitFor(0) = wrSignaled;
        Break;
      end;
    end;

    if LFinished then
    begin
      FLastError := FThread.Error;
      FThread.WaitFor;
      FThread.Free;
    end
    else
    begin
      // Still running: let it free itself when Execute finally returns.
      FThread.FreeOnTerminate := True;
      Result := False;
      if FLogger <> nil then
        FLogger.LogError('BackgroundService did not stop in time; the thread was detached.');
    end;
    FThread := nil;
  end;

  // Safe even when the thread was detached: a token outlives its source.
  if Assigned(FCancellationTokenSource) then
  begin
    FCancellationTokenSource.Free;
    FCancellationTokenSource := nil;
  end;
end;

{ THostedServiceManager }

constructor THostedServiceManager.Create(ALogger: ILogger);
begin
  inherited Create;
  FServices := TCollections.CreateList<IHostedService>;
  FLogger := ALogger;
end;

procedure THostedServiceManager.LogInfo(const AMsg: string);
begin
  if FLogger <> nil then
    FLogger.LogInformation(AMsg)
  else
    SafeWriteLn(AMsg);
end;

procedure THostedServiceManager.LogError(const AMsg: string);
begin
  if FLogger <> nil then
    FLogger.LogError(AMsg)
  else
    SafeWriteLn('❌ ' + AMsg);
end;

destructor THostedServiceManager.Destroy;
begin
  FServices := nil;
  inherited;
end;

procedure THostedServiceManager.RegisterService(Service: IHostedService);
begin
  FServices.Add(Service);
end;

procedure THostedServiceManager.StartAsync(Token: ICancellationToken);
var
  Service: IHostedService;
  LObj: TObject;
begin
  if (Token <> nil) and Token.IsCancellationRequested then
    Exit;
  for Service in FServices do
  begin
    if not Assigned(Service) then Continue;

    try
      LObj := Service as TObject;
      // If the service is TBackgroundService, we can inject our logger into it
      if (LObj <> nil) and (LObj is TBackgroundService) then
        TBackgroundService(LObj).FLogger := FLogger;
         
      Service.Start;
    except
      on E: Exception do
        LogError(Format('Failed to start service: %s', [E.Message]));
    end;
  end;
end;

procedure THostedServiceManager.StopAsync(Token: ICancellationToken);
var
  Service: IHostedService;
  LObj: TObject;
  I: Integer;
begin
  // Stop services in reverse order
  for I := FServices.Count - 1 downto 0 do
  begin
    Service := FServices[I];
    if not Assigned(Service) then Continue;

    try
      LObj := Service as TObject;
      if (LObj <> nil) and (LObj is TBackgroundService) then
      begin
        if not TBackgroundService(LObj).Shutdown(
          TBackgroundService(LObj).StopTimeoutMs, Token) then
          LogError(Format('Service %s did not stop in time.', [LObj.ClassName]));
      end
      else
        Service.Stop;
    except
      on E: Exception do
        LogError(Format('Failed to stop service: %s', [E.Message]));
    end;
  end;
end;

{ TBackgroundServiceBuilder }

constructor TBackgroundServiceBuilder.Create(Services: IServiceCollection);
begin
  FServices := Services;
  FHostedServices := TCollections.CreateList<TClass>;
  FLoggerClass := nil;
end;

function TBackgroundServiceBuilder.AddHostedService<T>: TBackgroundServiceBuilder;
begin
  // Register as singleton
  FServices.AddSingleton(TServiceType.FromClass(T), T);
  
  if not FHostedServices.Contains(T) then
    FHostedServices.Add(T);
    
  Result := Self;
end;

function TBackgroundServiceBuilder.AddHostedService(AServiceClass: TClass): TBackgroundServiceBuilder;
begin
  if not FHostedServices.Contains(AServiceClass) then
    FHostedServices.Add(AServiceClass);
  Result := Self;
end;

procedure TBackgroundServiceBuilder.Build;
var
  LServices: IServiceCollection;
  LHostedClasses: TArray<TClass>;
  LLoggerClass: TClass;
begin
  LServices := FServices;
  LHostedClasses := FHostedServices.ToArray;
  LLoggerClass := FLoggerClass;

  LServices.AddSingleton(
    TServiceType.FromInterface(TypeInfo(IHostedServiceManager)),
    THostedServiceManager,
    function(Provider: IServiceProvider): TObject
    var
      Manager: THostedServiceManager;
      SvcClass: TClass;
      ServiceObj: TObject;
      HostedService: IHostedService;
      Logger: ILogger;
      Intf: IInterface;
    begin
       // 1. Resolve Logger
       Logger := nil;
       if Assigned(LLoggerClass) then
       begin
         ServiceObj := Provider.GetService(TServiceType.FromClass(LLoggerClass));
         if Assigned(ServiceObj) then
           Supports(ServiceObj, ILogger, Logger);
       end
       else
       begin
         Intf := Provider.GetServiceAsInterface(TypeInfo(ILogger));
         if Assigned(Intf) then
           Supports(Intf, ILogger, Logger);
       end;

       // 2. Create Manager
       Manager := THostedServiceManager.Create(Logger);
       
       // 3. Resolve and Register Services from our CAPTURED array
       for SvcClass in LHostedClasses do
       begin
         ServiceObj := Provider.GetService(TServiceType.FromClass(SvcClass));
         if Assigned(ServiceObj) and Supports(ServiceObj, IHostedService, HostedService) then
           Manager.RegisterService(HostedService);
       end;
       
       Result := Manager;
    end
  );
end;

{ TDextServiceExtensions }

function TDextServiceExtensions.AddBackgroundServices: TBackgroundServiceBuilder;
begin
  Result := TDextServiceCollectionExtensions.AddBackgroundServices(Self.Collection);
end;

{ TDextServiceCollectionExtensions }

class function TDextServiceCollectionExtensions.AddBackgroundServices(
  Services: IServiceCollection): TBackgroundServiceBuilder;
begin
  Result := TBackgroundServiceBuilder.Create(Services);
end;

end.

