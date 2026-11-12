{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
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

unit Dext.BackgroundJobs.Config;

interface

uses
  System.Generics.Collections,
  System.JSON,
  System.Rtti,
  System.SysUtils,
  System.TimeSpan,
  System.TypInfo,
  Dext.DI.Interfaces,
  Dext.BackgroundJobs.Intf;

type
  TJobStorageFactory = reference to function(const AConnectionString: string): TObject;

  TJobStorageRegistry = class
  private
    class var FFactories: TDictionary<string, TJobStorageFactory>;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure RegisterProvider(const AName: string; const AFactory: TJobStorageFactory);
    class function CreateStorage(const AName: string; const AConnectionString: string): TObject;
  end;

  TBackgroundJobsOptions = class
  public
    Provider: string; // SQLite, InMemory
    ConnectionString: string; // Database path for SQLite
    /// <summary>Number of jobs that can run at the same time (worker threads).</summary>
    WorkerCount: Integer;
    PollIntervalInSeconds: Integer;
    /// <summary>Total tries of a job, the first one included (1 = never retry).</summary>
    MaxAttempts: Integer;
    /// <summary>Wait before the first retry; it doubles on each further retry (max 1 hour).</summary>
    RetryBackoffSeconds: Integer;
    /// <summary>How often a running job reports that its worker is alive.</summary>
    HeartbeatSeconds: Integer;
    /// <summary>A Processing job silent for this long is considered orphan and is recovered.</summary>
    OrphanTimeoutSeconds: Integer;
    /// <summary>Queues the server polls, in priority order.</summary>
    Queues: TArray<string>;
    constructor Create;
    function UseSQLite(const AConnectionString: string = 'dext_jobs.db'): TBackgroundJobsOptions;
    function UseInMemory: TBackgroundJobsOptions;
    function Workers(Value: Integer): TBackgroundJobsOptions;
    function PollInterval(Seconds: Integer): TBackgroundJobsOptions;
    function Retries(AMaxAttempts: Integer; ABackoffSeconds: Integer = 5): TBackgroundJobsOptions;
    function Recovery(AHeartbeatSeconds, AOrphanTimeoutSeconds: Integer): TBackgroundJobsOptions;
    function UseQueues(const ANames: array of string): TBackgroundJobsOptions;
  end;

  /// <summary>
  ///   Fluent builder for configuring background jobs runtime and storage options.
  /// </summary>
  TBackgroundJobsOptionsBuilder = record
  private
    FProvider: string;
    FConnectionString: string;
    FWorkerCount: Integer;
    FPollIntervalInSeconds: Integer;
    FMaxAttempts: Integer;
    FRetryBackoffSeconds: Integer;
    FHeartbeatSeconds: Integer;
    FOrphanTimeoutSeconds: Integer;
    FQueues: TArray<string>;
  public
    class function Create: TBackgroundJobsOptionsBuilder; static;
    function Provider(const Value: string): TBackgroundJobsOptionsBuilder;
    function ConnectionString(const Value: string): TBackgroundJobsOptionsBuilder;
    function UseSQLite(const AConnectionString: string = 'dext_jobs.db'): TBackgroundJobsOptionsBuilder;
    function UseInMemory: TBackgroundJobsOptionsBuilder;
    function Workers(Value: Integer): TBackgroundJobsOptionsBuilder;
    function WorkerCount(Value: Integer): TBackgroundJobsOptionsBuilder;
    function PollInterval(Seconds: Integer): TBackgroundJobsOptionsBuilder;
    function PollIntervalInSeconds(Seconds: Integer): TBackgroundJobsOptionsBuilder;
    function Retries(AMaxAttempts: Integer; ABackoffSeconds: Integer = 5): TBackgroundJobsOptionsBuilder;
    function Recovery(AHeartbeatSeconds, AOrphanTimeoutSeconds: Integer): TBackgroundJobsOptionsBuilder;
    function UseQueues(const ANames: array of string): TBackgroundJobsOptionsBuilder;

    function Build: TBackgroundJobsOptions;
    class operator Implicit(const ABuilder: TBackgroundJobsOptionsBuilder): TBackgroundJobsOptions;
  end;

  /// <summary>
  ///   Converts TValue arrays to JSON arrays and vice versa.
  /// </summary>
  TJobParamSerializer = class
  public
    class function Serialize(const AParams: array of TValue): string;
    class function Deserialize(const AJson: string): TArray<TValue>;
  end;

  TJobClient = class(TInterfacedObject, IJobClient)
  private
    FStorage: IJobStorage;
  public
    constructor Create(const AStorage: IJobStorage);
    function Enqueue(const AJobType, AMethodName: string; const AParams: array of TValue; const AQueue: string = 'default'): string;
    function Schedule(const AJobType, AMethodName: string; const AParams: array of TValue; const ADelay: TTimeSpan; const AQueue: string = 'default'): string;
  end;

  TDextBackgroundJobsServiceExtensions = class
  public
    class procedure AddBackgroundJobs(const Services: IServiceCollection; const AOptions: TBackgroundJobsOptions); overload;
    class procedure AddBackgroundJobs(const Services: IServiceCollection; const ABuilder: TBackgroundJobsOptionsBuilder); overload;
    class procedure AddBackgroundJobs(const Services: IServiceCollection; AConfigurator: TProc<TBackgroundJobsOptionsBuilder>); overload;
    class procedure AddBackgroundJobs(const Services: IServiceCollection; AConfigurator: TProc<TBackgroundJobsOptions>); overload;
  end;

  TDextBackgroundJobsServicesHelper = record helper for TDextServices
    function AddBackgroundJobs(const AOptions: TBackgroundJobsOptions): TDextServices; overload;
    function AddBackgroundJobs(const ABuilder: TBackgroundJobsOptionsBuilder): TDextServices; overload;
    function AddBackgroundJobs(AConfigurator: TProc<TBackgroundJobsOptionsBuilder>): TDextServices; overload;
    function AddBackgroundJobs(AConfigurator: TProc<TBackgroundJobsOptions>): TDextServices; overload;
  end;

/// <summary>
///   Factory function returning a fluent builder for TBackgroundJobsOptions.
/// </summary>
function BackgroundJobsOptions: TBackgroundJobsOptionsBuilder; overload;
function BackgroundJobsOptions(const AProvider: string; const AConnectionString: string = ''): TBackgroundJobsOptionsBuilder; overload;

implementation

uses
  System.Generics.Defaults,
  Dext.BackgroundJobs.Server;

class constructor TJobStorageRegistry.Create;
begin
end;

class destructor TJobStorageRegistry.Destroy;
begin
  FFactories.Free;
end;

class procedure TJobStorageRegistry.RegisterProvider(const AName: string; const AFactory: TJobStorageFactory);
begin
  if not Assigned(FFactories) then
  begin
    FFactories := TDictionary<string, TJobStorageFactory>.Create;
  end;
  FFactories.AddOrSetValue(UpperCase(AName), AFactory);
end;

class function TJobStorageRegistry.CreateStorage(const AName: string; const AConnectionString: string): TObject;
var
  Factory: TJobStorageFactory;
begin
  if not Assigned(FFactories) or not FFactories.TryGetValue(UpperCase(AName), Factory) then
    raise Exception.CreateFmt('Background Job Storage provider "%s" is not registered. Make sure the package containing it is loaded.', [AName]);
  Result := Factory(AConnectionString);
end;

{ TBackgroundJobsOptions }

constructor TBackgroundJobsOptions.Create;
begin
  inherited Create;
  Provider := 'InMemory';
  ConnectionString := '';
  WorkerCount := 4;
  PollIntervalInSeconds := 5;
  MaxAttempts := 3;
  RetryBackoffSeconds := 5;
  HeartbeatSeconds := 15;
  OrphanTimeoutSeconds := 120;
  Queues := ['default'];
end;

function TBackgroundJobsOptions.Retries(AMaxAttempts, ABackoffSeconds: Integer): TBackgroundJobsOptions;
begin
  Result := Self;
  MaxAttempts := AMaxAttempts;
  RetryBackoffSeconds := ABackoffSeconds;
end;

function TBackgroundJobsOptions.Recovery(AHeartbeatSeconds, AOrphanTimeoutSeconds: Integer): TBackgroundJobsOptions;
begin
  Result := Self;
  HeartbeatSeconds := AHeartbeatSeconds;
  OrphanTimeoutSeconds := AOrphanTimeoutSeconds;
end;

function TBackgroundJobsOptions.UseQueues(const ANames: array of string): TBackgroundJobsOptions;
var
  I: Integer;
begin
  Result := Self;
  SetLength(Queues, Length(ANames));
  for I := 0 to High(ANames) do
    Queues[I] := ANames[I];
end;

function TBackgroundJobsOptions.UseSQLite(const AConnectionString: string): TBackgroundJobsOptions;
begin
  Result := Self;
  Provider := 'SQLite';
  ConnectionString := AConnectionString;
end;

function TBackgroundJobsOptions.UseInMemory: TBackgroundJobsOptions;
begin
  Result := Self;
  Provider := 'InMemory';
  ConnectionString := '';
end;

function TBackgroundJobsOptions.Workers(Value: Integer): TBackgroundJobsOptions;
begin
  Result := Self;
  WorkerCount := Value;
end;

function TBackgroundJobsOptions.PollInterval(Seconds: Integer): TBackgroundJobsOptions;
begin
  Result := Self;
  PollIntervalInSeconds := Seconds;
end;

{ TBackgroundJobsOptionsBuilder }

class function TBackgroundJobsOptionsBuilder.Create: TBackgroundJobsOptionsBuilder;
begin
  Result.FProvider := 'InMemory';
  Result.FConnectionString := '';
  Result.FWorkerCount := 4;
  Result.FPollIntervalInSeconds := 5;
  Result.FMaxAttempts := 3;
  Result.FRetryBackoffSeconds := 5;
  Result.FHeartbeatSeconds := 15;
  Result.FOrphanTimeoutSeconds := 120;
  Result.FQueues := ['default'];
end;

function TBackgroundJobsOptionsBuilder.Retries(AMaxAttempts, ABackoffSeconds: Integer): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FMaxAttempts := AMaxAttempts;
  Result.FRetryBackoffSeconds := ABackoffSeconds;
end;

function TBackgroundJobsOptionsBuilder.Recovery(AHeartbeatSeconds, AOrphanTimeoutSeconds: Integer): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FHeartbeatSeconds := AHeartbeatSeconds;
  Result.FOrphanTimeoutSeconds := AOrphanTimeoutSeconds;
end;

function TBackgroundJobsOptionsBuilder.UseQueues(const ANames: array of string): TBackgroundJobsOptionsBuilder;
var
  I: Integer;
begin
  Result := Self;
  SetLength(Result.FQueues, Length(ANames));
  for I := 0 to High(ANames) do
    Result.FQueues[I] := ANames[I];
end;

function TBackgroundJobsOptionsBuilder.Provider(const Value: string): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FProvider := Value;
end;

function TBackgroundJobsOptionsBuilder.ConnectionString(const Value: string): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FConnectionString := Value;
end;

function TBackgroundJobsOptionsBuilder.UseSQLite(const AConnectionString: string): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FProvider := 'SQLite';
  Result.FConnectionString := AConnectionString;
end;

function TBackgroundJobsOptionsBuilder.UseInMemory: TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FProvider := 'InMemory';
  Result.FConnectionString := '';
end;

function TBackgroundJobsOptionsBuilder.Workers(Value: Integer): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FWorkerCount := Value;
end;

function TBackgroundJobsOptionsBuilder.WorkerCount(Value: Integer): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FWorkerCount := Value;
end;

function TBackgroundJobsOptionsBuilder.PollInterval(Seconds: Integer): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FPollIntervalInSeconds := Seconds;
end;

function TBackgroundJobsOptionsBuilder.PollIntervalInSeconds(Seconds: Integer): TBackgroundJobsOptionsBuilder;
begin
  Result := Self;
  Result.FPollIntervalInSeconds := Seconds;
end;

function TBackgroundJobsOptionsBuilder.Build: TBackgroundJobsOptions;
begin
  Result := TBackgroundJobsOptions.Create;
  Result.Provider := FProvider;
  Result.ConnectionString := FConnectionString;
  Result.WorkerCount := FWorkerCount;
  Result.PollIntervalInSeconds := FPollIntervalInSeconds;
  Result.MaxAttempts := FMaxAttempts;
  Result.RetryBackoffSeconds := FRetryBackoffSeconds;
  Result.HeartbeatSeconds := FHeartbeatSeconds;
  Result.OrphanTimeoutSeconds := FOrphanTimeoutSeconds;
  Result.Queues := Copy(FQueues);
end;

class operator TBackgroundJobsOptionsBuilder.Implicit(const ABuilder: TBackgroundJobsOptionsBuilder): TBackgroundJobsOptions;
begin
  Result := ABuilder.Build;
end;

function BackgroundJobsOptions: TBackgroundJobsOptionsBuilder;
begin
  Result := TBackgroundJobsOptionsBuilder.Create;
end;

function BackgroundJobsOptions(const AProvider: string; const AConnectionString: string): TBackgroundJobsOptionsBuilder;
begin
  Result := TBackgroundJobsOptionsBuilder.Create;
  Result.FProvider := AProvider;
  Result.FConnectionString := AConnectionString;
end;

{ TJobParamSerializer }

class function TJobParamSerializer.Serialize(const AParams: array of TValue): string;
var
  JArr: TJSONArray;
  JObj: TJSONObject;
  Val: TValue;
begin
  JArr := TJSONArray.Create;
  try
    for Val in AParams do
    begin
      JObj := TJSONObject.Create;
      JObj.AddPair('Type', string(Val.TypeInfo.Name));
      
      case Val.Kind of
        tkInteger, tkInt64:
          JObj.AddPair('Value', TJSONNumber.Create(Val.AsInteger));
        tkFloat:
          JObj.AddPair('Value', TJSONNumber.Create(Val.AsExtended));
        tkEnumeration:
          if Val.TypeInfo = TypeInfo(Boolean) then
            JObj.AddPair('Value', TJSONBool.Create(Val.AsBoolean))
          else
            JObj.AddPair('Value', TJSONNumber.Create(Val.AsOrdinal));
        else
          JObj.AddPair('Value', Val.AsString);
      end;
      
      JArr.AddElement(JObj);
    end;
    Result := JArr.ToJSON;
  finally
    JArr.Free;
  end;
end;

class function TJobParamSerializer.Deserialize(const AJson: string): TArray<TValue>;
var
  JArr: TJSONArray;
  JObj: TJSONObject;
  JVal: TJSONValue;
  I: Integer;
  TypeName: string;
  ValObj: TJSONValue;
begin
  if AJson = '' then
    Exit(nil);
    
  JVal := TJSONObject.ParseJSONValue(AJson);
  if not Assigned(JVal) or (not (JVal is TJSONArray)) then
  begin
    JVal.Free;
    Exit(nil);
  end;
  
  JArr := JVal as TJSONArray;
  try
    SetLength(Result, JArr.Count);
    for I := 0 to JArr.Count - 1 do
    begin
      JObj := JArr.Items[I] as TJSONObject;
      TypeName := JObj.GetValue('Type').Value;
      ValObj := JObj.GetValue('Value');
      
      if TypeName = 'Boolean' then
        Result[I] := TValue.From<Boolean>((ValObj as TJSONBool).AsBoolean)
      else if TypeName = 'Integer' then
        Result[I] := TValue.From<Integer>((ValObj as TJSONNumber).AsInt64)
      else if TypeName = 'Int64' then
        Result[I] := TValue.From<Int64>((ValObj as TJSONNumber).AsInt64)
      else if (TypeName = 'Double') or (TypeName = 'Extended') or (TypeName = 'Single') then
        Result[I] := TValue.From<Double>((ValObj as TJSONNumber).AsDouble)
      else
        Result[I] := TValue.From<string>(ValObj.Value);
    end;
  finally
    JArr.Free;
  end;
end;

{ TJobClient }

constructor TJobClient.Create(const AStorage: IJobStorage);
begin
  inherited Create;
  FStorage := AStorage;
end;

// Enqueue
function TJobClient.Enqueue(const AJobType, AMethodName: string; const AParams: array of TValue; const AQueue: string): string;
begin
  Result := FStorage.Enqueue(AJobType, AMethodName, TJobParamSerializer.Serialize(AParams), AQueue);
end;

// Schedule
function TJobClient.Schedule(const AJobType, AMethodName: string; const AParams: array of TValue; const ADelay: TTimeSpan; const AQueue: string): string;
begin
  Result := FStorage.Schedule(AJobType, AMethodName, TJobParamSerializer.Serialize(AParams), AQueue, Now + ADelay.TotalDays);
end;

{ TDextBackgroundJobsServiceExtensions }

class procedure TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(
  const Services: IServiceCollection; const AOptions: TBackgroundJobsOptions);
begin
  // Register options instance
  Services.AddSingleton(TServiceType.FromClass(TBackgroundJobsOptions), AOptions);

  // Register Storage dynamically resolved from registry
  Services.AddSingleton(
    TServiceType.FromInterface(TypeInfo(IJobStorage)),
    TClass(nil),
    function(Provider: IServiceProvider): TObject
    begin
      Result := TJobStorageRegistry.CreateStorage(AOptions.Provider, AOptions.ConnectionString);
    end
  );

  // Register Client
  Services.AddSingleton(
    TServiceType.FromInterface(TypeInfo(IJobClient)),
    TJobClient,
    function(Provider: IServiceProvider): TObject
    var
      Storage: IJobStorage;
      Intf: IInterface;
    begin
      Intf := Provider.GetServiceAsInterface(TypeInfo(IJobStorage));
      Supports(Intf, IJobStorage, Storage);
      Result := TJobClient.Create(Storage);
    end
  );

  // Register the job server (the worker pool). It runs as a hosted service: add it with
  // Services.AddBackgroundServices.AddHostedService(TJobServer).Build
  Services.AddSingleton(
    TServiceType.FromClass(TJobServer),
    TJobServer,
    function(Provider: IServiceProvider): TObject
    var
      Storage: IJobStorage;
      Intf: IInterface;
    begin
      Intf := Provider.GetServiceAsInterface(TypeInfo(IJobStorage));
      Supports(Intf, IJobStorage, Storage);
      Result := TJobServer.Create(Storage, Provider, AOptions);
    end
  );
end;

class procedure TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(
  const Services: IServiceCollection; const ABuilder: TBackgroundJobsOptionsBuilder);
begin
  AddBackgroundJobs(Services, ABuilder.Build);
end;

class procedure TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(
  const Services: IServiceCollection; AConfigurator: TProc<TBackgroundJobsOptionsBuilder>);
var
  Builder: TBackgroundJobsOptionsBuilder;
begin
  Builder := TBackgroundJobsOptionsBuilder.Create;
  if Assigned(AConfigurator) then
    AConfigurator(Builder);
  AddBackgroundJobs(Services, Builder.Build);
end;

class procedure TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(
  const Services: IServiceCollection; AConfigurator: TProc<TBackgroundJobsOptions>);
var
  Options: TBackgroundJobsOptions;
begin
  Options := TBackgroundJobsOptions.Create;
  if Assigned(AConfigurator) then
    AConfigurator(Options);
  AddBackgroundJobs(Services, Options);
end;

{ TDextBackgroundJobsServicesHelper }

function TDextBackgroundJobsServicesHelper.AddBackgroundJobs(const AOptions: TBackgroundJobsOptions): TDextServices;
begin
  TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(Self.Unwrap, AOptions);
  Result := Self;
end;

function TDextBackgroundJobsServicesHelper.AddBackgroundJobs(const ABuilder: TBackgroundJobsOptionsBuilder): TDextServices;
begin
  TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(Self.Unwrap, ABuilder);
  Result := Self;
end;

function TDextBackgroundJobsServicesHelper.AddBackgroundJobs(AConfigurator: TProc<TBackgroundJobsOptionsBuilder>): TDextServices;
begin
  TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(Self.Unwrap, AConfigurator);
  Result := Self;
end;

function TDextBackgroundJobsServicesHelper.AddBackgroundJobs(AConfigurator: TProc<TBackgroundJobsOptions>): TDextServices;
begin
  TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(Self.Unwrap, AConfigurator);
  Result := Self;
end;

end.
