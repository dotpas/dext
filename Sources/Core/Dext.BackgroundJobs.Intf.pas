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

unit Dext.BackgroundJobs.Intf;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TimeSpan;

type
  TJobState = (jsEnqueued, jsProcessing, jsSucceeded, jsFailed);

  TJobInfo = record
    Id: string;
    JobType: string;
    MethodName: string;
    ParamsJson: string;
    State: TJobState;
    Queue: string;
    CreatedAt: TDateTime;
    EnqueueAt: TDateTime;
    AttemptCount: Integer;
    LastHeartbeat: TDateTime;
    ErrorLog: string;
  end;

  /// <summary>
  ///   Interface for background job storage providers.
  /// </summary>
  IJobStorage = interface
    ['{84B0F7C7-93C2-4E56-BE3F-13481234E5D1}']
    /// <summary>Enqueues a new background job immediately.</summary>
    function Enqueue(const AJobType, AMethodName, AParamsJson: string; const AQueue: string = 'default'): string;
    /// <summary>Schedules a background job to be executed at a specific date and time.</summary>
    function Schedule(const AJobType, AMethodName, AParamsJson: string; const AQueue: string; const AEnqueueAt: TDateTime): string;
    /// <summary>Fetches the next available job for processing, marking it as Processing.</summary>
    function GetNextJob(const AQueue: string; out AJob: TJobInfo): Boolean;
    /// <summary>Updates the state of an existing job.</summary>
    procedure UpdateJobState(const AJobId: string; const AState: TJobState; const AErrorMessage: string = '');
    /// <summary>Records a heartbeat for a processing job to indicate the worker is alive.</summary>
    procedure RecordHeartbeat(const AJobId: string);
  end;

  /// <summary>
  ///   Optional storage capabilities used by the job server for retries and for
  ///   recovering jobs whose worker died. Both built-in providers implement it; a
  ///   custom IJobStorage without it still works, but its failed jobs are final.
  /// </summary>
  IJobStorageEx = interface(IJobStorage)
    ['{C2E7A4B1-5D38-4F96-8A0E-71B9D3F2C645}']
    /// <summary>
    ///   Puts a failed job back in the queue to run again at AEnqueueAt. The failed attempt
    ///   is counted and AErrorMessage is kept in the error log.
    /// </summary>
    procedure ScheduleRetry(const AJobId: string; const AEnqueueAt: TDateTime;
      const AErrorMessage: string);
    /// <summary>
    ///   Recovers orphan jobs: Processing jobs whose last heartbeat is older than
    ///   AStaleBefore. The lost attempt is counted; the job goes back to the queue, or
    ///   becomes Failed when AMaxAttempts is reached. Returns how many jobs were touched.
    /// </summary>
    function RecoverOrphans(const AStaleBefore: TDateTime; AMaxAttempts: Integer): Integer;
  end;

  /// <summary>
  ///   Client interface used to register background tasks.
  /// </summary>
  IJobClient = interface
    ['{3A970425-2C5E-4B07-A595-AE2D3C4A5E82}']
    /// <summary>Enqueues a job for immediate execution.</summary>
    function Enqueue(const AJobType, AMethodName: string; const AParams: array of TValue; const AQueue: string = 'default'): string;
    /// <summary>Schedules a job for delayed execution.</summary>
    function Schedule(const AJobType, AMethodName: string; const AParams: array of TValue; const ADelay: TTimeSpan; const AQueue: string = 'default'): string;
  end;

  /// <summary>
  ///   Static class serving as the entry point for Background Jobs enqueuing.
  /// </summary>
  TDextJobs = class
  private
    class var FClient: IJobClient;
  public
    class procedure Initialize(const AClient: IJobClient);
    class function Enqueue<T: class>(const AMethodName: string; const AParams: array of TValue; const AQueue: string = 'default'): string; overload;
    class function Schedule<T: class>(const AMethodName: string; const AParams: array of TValue; const ADelay: TTimeSpan; const AQueue: string = 'default'): string; overload;
  end;

implementation

{ TDextJobs }

class procedure TDextJobs.Initialize(const AClient: IJobClient);
begin
  FClient := AClient;
end;

class function TDextJobs.Enqueue<T>(const AMethodName: string; const AParams: array of TValue; const AQueue: string): string;
begin
  if not Assigned(FClient) then
    raise EInvalidOpException.Create('TDextJobs is not initialized. Register background jobs first.');
  Result := FClient.Enqueue(T.ClassName, AMethodName, AParams, AQueue);
end;

class function TDextJobs.Schedule<T>(const AMethodName: string; const AParams: array of TValue; const ADelay: TTimeSpan; const AQueue: string): string;
begin
  if not Assigned(FClient) then
    raise EInvalidOpException.Create('TDextJobs is not initialized. Register background jobs first.');
  Result := FClient.Schedule(T.ClassName, AMethodName, AParams, ADelay, AQueue);
end;

end.
