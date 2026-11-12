
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

unit Dext.BackgroundJobs.Server;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.SyncObjs,
  System.Generics.Collections,
  Dext.Threading.CancellationToken,
  Dext.Hosting.BackgroundService,
  Dext.DI.Interfaces,
  Dext.BackgroundJobs.Intf,
  Dext.BackgroundJobs.Config;

type
  /// <summary>
  ///   The job worker pool, run as a hosted service. It starts WorkerCount worker
  ///   threads that poll the configured queues, a heartbeat thread that keeps running
  ///   jobs alive and recovers orphans, and retries failed jobs with exponential backoff
  ///   (when the storage implements IJobStorageEx).
  ///   Each job runs on a fresh instance of its class, created with constructor
  ///   injection and freed by the server after the call.
  ///   Stop lets running jobs finish (up to StopTimeoutMs): a job is not interrupted.
  /// </summary>
  TJobServer = class(TBackgroundService)
  private
    FStorage: IJobStorage;
    FStorageEx: IJobStorageEx;
    // Weak: the container owns this server (a singleton), so a strong reference
    // back to the container would be a cycle that keeps both alive forever.
    [weak] FServiceProvider: IServiceProvider;
    FOptions: TBackgroundJobsOptions;
    FActiveLock: TCriticalSection;
    FActive: TList<string>;
    procedure WorkerLoop(const Token: ICancellationToken);
    procedure HeartbeatLoop(const Token: ICancellationToken);
    function RunNextJob: Boolean;
    function PollIntervalMs: Cardinal;
    function RetryDelayDays(AAttempts: Integer): Double;
    procedure MarkFailed(const Job: TJobInfo; const AMessage: string);
    procedure LogError(const AMsg: string; const AArgs: array of const);
    procedure ProcessJob(const Job: TJobInfo);
    function ResolveJobInstance(const AClassName: string): TObject;
  protected
    procedure Execute(Token: ICancellationToken); override;
  public
    constructor Create(const AStorage: IJobStorage; const AServiceProvider: IServiceProvider; const AOptions: TBackgroundJobsOptions);
    destructor Destroy; override;
  end;

implementation

uses
  Dext.Core.Activator;

type
  /// <summary>A thread running one procedure; owned (and freed) by the server's Execute.</summary>
  TJobHelperThread = class(TThread)
  private
    FBody: TProc;
    FOnError: TProc<string>;
  protected
    procedure Execute; override;
  public
    constructor Create(const ABody: TProc; const AOnError: TProc<string>);
  end;

{ TJobHelperThread }

constructor TJobHelperThread.Create(const ABody: TProc; const AOnError: TProc<string>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FBody := ABody;
  FOnError := AOnError;
end;

procedure TJobHelperThread.Execute;
begin
  try
    FBody();
  except
    on E: Exception do
      if Assigned(FOnError) then
        FOnError(E.Message);
  end;
end;

{ TJobServer }

constructor TJobServer.Create(const AStorage: IJobStorage; const AServiceProvider: IServiceProvider; const AOptions: TBackgroundJobsOptions);
begin
  inherited Create;
  FStorage := AStorage;
  Supports(AStorage, IJobStorageEx, FStorageEx);
  FServiceProvider := AServiceProvider;
  FOptions := AOptions;
  FActiveLock := TCriticalSection.Create;
  FActive := TList<string>.Create;
end;

destructor TJobServer.Destroy;
begin
  // A server destroyed while running must not leave its threads behind.
  Stop;
  FActive.Free;
  FActiveLock.Free;
  inherited;
end;

procedure TJobServer.LogError(const AMsg: string; const AArgs: array of const);
begin
  if Assigned(FLogger) then
    FLogger.LogError(AMsg, AArgs);
end;

function TJobServer.PollIntervalMs: Cardinal;
begin
  if FOptions.PollIntervalInSeconds <= 0 then
    Result := 500
  else
    Result := Cardinal(FOptions.PollIntervalInSeconds) * 1000;
end;

function TJobServer.RetryDelayDays(AAttempts: Integer): Double;
var
  LSeconds: Double;
  I: Integer;
begin
  // Delay before retry number AAttempts: backoff, 2x backoff, 4x ... capped at 1 hour.
  LSeconds := FOptions.RetryBackoffSeconds;
  if LSeconds < 0 then
    LSeconds := 0;
  for I := 2 to AAttempts do
  begin
    LSeconds := LSeconds * 2;
    if LSeconds >= 3600 then
      Break;
  end;
  if LSeconds > 3600 then
    LSeconds := 3600;
  Result := LSeconds / 86400.0;
end;

procedure TJobServer.Execute(Token: ICancellationToken);
var
  LHelpers: TObjectList<TJobHelperThread>;
  LThread: TJobHelperThread;
  LToken: ICancellationToken;
  LOnError: TProc<string>;
  I: Integer;
begin
  LToken := Token;
  LOnError :=
    procedure(AMessage: string)
    begin
      LogError('Background job helper thread failed: {0}', [AMessage]);
    end;

  LHelpers := TObjectList<TJobHelperThread>.Create(True);
  try
    // WorkerCount - 1 extra workers; this thread is the last worker.
    for I := 2 to FOptions.WorkerCount do
    begin
      LThread := TJobHelperThread.Create(
        procedure
        begin
          WorkerLoop(LToken);
        end, LOnError);
      LHelpers.Add(LThread);
    end;
    LHelpers.Add(TJobHelperThread.Create(
      procedure
      begin
        HeartbeatLoop(LToken);
      end, LOnError));

    for LThread in LHelpers do
      LThread.Start;

    try
      WorkerLoop(LToken);
    finally
      // The token is cancelled: every helper leaves its loop after its current job.
      for LThread in LHelpers do
        LThread.WaitFor;
    end;
  finally
    LHelpers.Free;
  end;
end;

procedure TJobServer.WorkerLoop(const Token: ICancellationToken);
begin
  while not Token.IsCancellationRequested do
  begin
    try
      if not RunNextJob then
        // Idle: wait for the poll interval, but wake up at once on cancellation.
        Token.WaitForCancellation(PollIntervalMs);
    except
      on E: Exception do
      begin
        LogError('Error in background job server execution loop: {0}', [E.Message]);
        Token.WaitForCancellation(1000);
      end;
    end;
  end;
end;

function TJobServer.RunNextJob: Boolean;
var
  Job: TJobInfo;
  LQueue: string;
begin
  for LQueue in FOptions.Queues do
  begin
    if FStorage.GetNextJob(LQueue, Job) then
    begin
      ProcessJob(Job);
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TJobServer.HeartbeatLoop(const Token: ICancellationToken);
var
  LIds: TArray<string>;
  LId: string;
  LHeartbeatMs: Cardinal;
  LTimeoutDays: Double;
  LHeartbeatSec, LOrphanSec: Integer;
begin
  LHeartbeatSec := FOptions.HeartbeatSeconds;
  if LHeartbeatSec < 1 then
    LHeartbeatSec := 15;
  LOrphanSec := FOptions.OrphanTimeoutSeconds;
  // The timeout must leave room for at least two missed beats.
  if LOrphanSec < LHeartbeatSec * 2 then
    LOrphanSec := LHeartbeatSec * 2;
  LHeartbeatMs := Cardinal(LHeartbeatSec) * 1000;
  LTimeoutDays := LOrphanSec / 86400.0;

  while not Token.IsCancellationRequested do
  begin
    try
      FActiveLock.Enter;
      try
        LIds := FActive.ToArray;
      finally
        FActiveLock.Leave;
      end;
      for LId in LIds do
        FStorage.RecordHeartbeat(LId);

      if Assigned(FStorageEx) then
        FStorageEx.RecoverOrphans(Now - LTimeoutDays, FOptions.MaxAttempts);
    except
      on E: Exception do
        LogError('Background job heartbeat failed: {0}', [E.Message]);
    end;
    Token.WaitForCancellation(LHeartbeatMs);
  end;
end;

function TJobServer.ResolveJobInstance(const AClassName: string): TObject;
var
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  ClassType: TClass;
begin
  RttiContext := TRttiContext.Create;
  try
    RttiType := RttiContext.FindType(AClassName);
    if not Assigned(RttiType) or (not (RttiType is TRttiInstanceType)) then
    begin
      // Try searching through loaded packages/units using class name
      for RttiType in RttiContext.GetTypes do
      begin
        if SameText(RttiType.Name, AClassName) and (RttiType is TRttiInstanceType) then
        begin
          ClassType := TRttiInstanceType(RttiType).MetaclassType;
          Result := TActivator.CreateInstance(FServiceProvider, ClassType);
          Exit;
        end;
      end;
      raise EClassNotFound.CreateFmt('Class %s not found in RTTI context.', [AClassName]);
    end;
    ClassType := TRttiInstanceType(RttiType).MetaclassType;
    Result := TActivator.CreateInstance(FServiceProvider, ClassType);
  finally
    RttiContext.Free;
  end;
end;

procedure TJobServer.MarkFailed(const Job: TJobInfo; const AMessage: string);
var
  LAttempts: Integer;
begin
  // Whatever happens here, it must not escape: the worker has to keep working.
  try
    LAttempts := Job.AttemptCount + 1; // this run included
    if Assigned(FStorageEx) and (LAttempts < FOptions.MaxAttempts) then
      FStorageEx.ScheduleRetry(Job.Id, Now + RetryDelayDays(LAttempts), AMessage)
    else
      FStorage.UpdateJobState(Job.Id, jsFailed, AMessage);
  except
    on E: Exception do
      LogError('Could not record the failure of job {0}: {1}', [Job.Id, E.Message]);
  end;
end;

procedure TJobServer.ProcessJob(const Job: TJobInfo);
var
  Instance: TObject;
  RttiContext: TRttiContext;
  RttiType: TRttiType;
  RttiMethod: TRttiMethod;
  Params: TArray<TValue>;
  LSucceeded: Boolean;
  LMessage: string;
begin
  Instance := nil;
  LSucceeded := False;
  LMessage := '';

  FActiveLock.Enter;
  try
    FActive.Add(Job.Id);
  finally
    FActiveLock.Leave;
  end;

  RttiContext := TRttiContext.Create;
  try
    try
      Instance := ResolveJobInstance(Job.JobType);
      if not Assigned(Instance) then
        raise EClassNotFound.CreateFmt('Could not instantiate job class: %s', [Job.JobType]);

      RttiType := RttiContext.GetType(Instance.ClassType);
      RttiMethod := RttiType.GetMethod(Job.MethodName);
      if not Assigned(RttiMethod) then
        raise Exception.CreateFmt('Method %s not found on class %s', [Job.MethodName, Job.JobType]);

      Params := TJobParamSerializer.Deserialize(Job.ParamsJson);

      // Invoke the method
      RttiMethod.Invoke(Instance, Params);
      LSucceeded := True;
    except
      on E: Exception do
      begin
        LMessage := E.Message;
        LogError('Failed to process job {0}: {1}', [Job.Id, E.Message]);
      end;
    end;
  finally
    Instance.Free;
    RttiContext.Free;
    FActiveLock.Enter;
    try
      FActive.Remove(Job.Id);
    finally
      FActiveLock.Leave;
    end;
  end;

  if LSucceeded then
  begin
    try
      FStorage.UpdateJobState(Job.Id, jsSucceeded);
    except
      on E: Exception do
        LogError('Could not record the success of job {0}: {1}', [Job.Id, E.Message]);
    end;
  end
  else
    MarkFailed(Job, LMessage);
end;

end.
