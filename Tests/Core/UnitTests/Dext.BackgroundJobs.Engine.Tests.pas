unit Dext.BackgroundJobs.Engine.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.IOUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.DI.Interfaces,
  Dext.BackgroundJobs.Intf,
  Dext.BackgroundJobs.Config,
  Dext.BackgroundJobs.Storage.InMemory,
  Dext.BackgroundJobs.Storage.Sqlite,
  Dext.BackgroundJobs.Server;

type
  TEngineJob = class
  public
    class var Calls: Integer;
    class var Together: Integer;
    class var Met: Integer;
    class var FailUntil: Integer;
    class var AllIn: TEvent;
    procedure Fail;
    procedure FailTwiceThenWork;
    procedure Meet(const AExpected: Integer);
    procedure Touch;
  end;

  [TestFixture('Background Jobs Engine: workers, retries, recovery')]
  TJobEngineTests = class
  private
    FServices: IServiceCollection;
    FProvider: IServiceProvider;
    FOptions: TBackgroundJobsOptions;
    FStorage: IJobStorage;
    FClient: IJobClient;
    FDbFile: string;
    procedure Boot(const AProvider: string);
    function RunServer(AWaitFor: TFunc<Boolean>; ATimeoutMs: Integer): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test('WorkerCount runs that many jobs at the same time')]
    procedure WorkerCount_Runs_Jobs_In_Parallel;

    [Test('A failing job is retried until MaxAttempts, then stays failed')]
    procedure Failing_Job_Is_Retried_Until_MaxAttempts;

    [Test('MaxAttempts = 1 never retries')]
    procedure MaxAttempts_One_Never_Retries;

    [Test('A job that fails and then works is run to success')]
    procedure Job_Succeeds_After_Retries;

    [Test('Jobs of additional queues are picked up')]
    procedure Additional_Queue_Is_Polled;

    [Test('An idle server stops promptly, without waiting for the poll interval')]
    procedure Idle_Server_Stops_Promptly;

    [Test('The server is registered in the container')]
    procedure Server_Is_Registered_In_Container;

    [Test('InMemory: an orphan job goes back to the queue and counts the attempt')]
    procedure InMemory_Orphan_Is_Requeued;

    [Test('InMemory: an orphan out of attempts becomes failed')]
    procedure InMemory_Orphan_Out_Of_Attempts_Fails;

    [Test('SQLite: an orphan job goes back to the queue')]
    procedure Sqlite_Orphan_Is_Requeued;

    [Test('SQLite: ScheduleRetry delays the job')]
    procedure Sqlite_ScheduleRetry_Delays_The_Job;
  end;

implementation

uses
  Dext,
  Dext.DI.Core;

{ TEngineJob }

procedure TEngineJob.Fail;
begin
  TInterlocked.Increment(Calls);
  raise Exception.Create('always fails');
end;

procedure TEngineJob.FailTwiceThenWork;
begin
  if TInterlocked.Increment(Calls) <= FailUntil then
    raise Exception.Create('not yet');
end;

procedure TEngineJob.Meet(const AExpected: Integer);
begin
  // Every worker must be inside at once for the gate to open.
  if TInterlocked.Increment(Together) = AExpected then
    AllIn.SetEvent;
  if AllIn.WaitFor(5000) = wrSignaled then
    TInterlocked.Increment(Met);
end;

procedure TEngineJob.Touch;
begin
  TInterlocked.Increment(Calls);
end;

{ TJobEngineTests }

procedure TJobEngineTests.Setup;
var
  LServices: TDextServices;
begin
  if (TSqliteJobStorage.ClassName = '') or (TInMemoryJobStorage.ClassName = '') then Exit;
  TEngineJob.Calls := 0;
  TEngineJob.Together := 0;
  TEngineJob.Met := 0;
  TEngineJob.FailUntil := 0;
  TEngineJob.AllIn := TEvent.Create(nil, True, False, '');
  FDbFile := TPath.Combine(TPath.GetTempPath, 'dext_engine_' + TGuid.NewGuid.ToString + '.db');
  FOptions := nil;
  LServices := TDextServices.New;
  LServices.AddTransient<TEngineJob>;
  FServices := LServices.Collection;
end;

procedure TJobEngineTests.TearDown;
begin
  FClient := nil;
  FStorage := nil;
  FProvider := nil;
  FServices := nil;
  FOptions.Free;
  FOptions := nil;
  TEngineJob.AllIn.Free;
  TEngineJob.AllIn := nil;
  if TFile.Exists(FDbFile) then
  begin
    try
      TFile.Delete(FDbFile);
    except
      // sharing violation: ignore
    end;
  end;
end;

procedure TJobEngineTests.Boot(const AProvider: string);
var
  LIntf: IInterface;
begin
  FOptions.Provider := AProvider;
  if SameText(AProvider, 'SQLite') then
    FOptions.ConnectionString := FDbFile;
  TDextBackgroundJobsServiceExtensions.AddBackgroundJobs(FServices, FOptions);
  FProvider := FServices.BuildServiceProvider;
  LIntf := FProvider.GetServiceAsInterface(TypeInfo(IJobStorage));
  Supports(LIntf, IJobStorage, FStorage);
  LIntf := FProvider.GetServiceAsInterface(TypeInfo(IJobClient));
  Supports(LIntf, IJobClient, FClient);
  TDextJobs.Initialize(FClient);
end;

function TJobEngineTests.RunServer(AWaitFor: TFunc<Boolean>; ATimeoutMs: Integer): Boolean;
var
  LServer: TJobServer;
  LWatch: TStopwatch;
begin
  LServer := TJobServer.Create(FStorage, FProvider, FOptions);
  try
    LServer.Start;
    LWatch := TStopwatch.StartNew;
    Result := AWaitFor();
    while (not Result) and (LWatch.ElapsedMilliseconds < ATimeoutMs) do
    begin
      Sleep(20);
      Result := AWaitFor();
    end;
    LServer.Stop;
  finally
    LServer.Free;
  end;
end;

procedure TJobEngineTests.WorkerCount_Runs_Jobs_In_Parallel;
var
  I: Integer;
begin
  FOptions := TBackgroundJobsOptions.Create;
  FOptions.Workers(3).PollInterval(1);
  Boot('InMemory');
  for I := 1 to 3 do
    TDextJobs.Enqueue<TEngineJob>('Meet', [3]);

  Should(RunServer(function: Boolean begin Result := TEngineJob.Met = 3; end, 15000)).BeTrue;
  Should(TEngineJob.Met).Be(3);
end;

procedure TJobEngineTests.Failing_Job_Is_Retried_Until_MaxAttempts;
var
  LJob: TJobInfo;
begin
  FOptions := TBackgroundJobsOptions.Create;
  FOptions.Workers(1).PollInterval(1).Retries(3, 0);
  Boot('InMemory');
  TDextJobs.Enqueue<TEngineJob>('Fail', []);

  Should(RunServer(function: Boolean begin Result := TEngineJob.Calls >= 3; end, 15000)).BeTrue;
  Sleep(300); // a 4th attempt would have started by now
  Should(TEngineJob.Calls).Be(3);
  Should(FStorage.GetNextJob('default', LJob)).BeFalse; // failed for good
end;

procedure TJobEngineTests.MaxAttempts_One_Never_Retries;
begin
  FOptions := TBackgroundJobsOptions.Create;
  FOptions.Workers(1).PollInterval(1).Retries(1, 0);
  Boot('InMemory');
  TDextJobs.Enqueue<TEngineJob>('Fail', []);

  Should(RunServer(function: Boolean begin Result := TEngineJob.Calls >= 1; end, 15000)).BeTrue;
  Sleep(300);
  Should(TEngineJob.Calls).Be(1);
end;

procedure TJobEngineTests.Job_Succeeds_After_Retries;
var
  LJob: TJobInfo;
begin
  TEngineJob.FailUntil := 2;
  FOptions := TBackgroundJobsOptions.Create;
  FOptions.Workers(1).PollInterval(1).Retries(5, 0);
  Boot('InMemory');
  TDextJobs.Enqueue<TEngineJob>('FailTwiceThenWork', []);

  Should(RunServer(function: Boolean begin Result := TEngineJob.Calls >= 3; end, 15000)).BeTrue;
  Sleep(300);
  Should(TEngineJob.Calls).Be(3); // 2 failures + 1 success, then nothing more
  Should(FStorage.GetNextJob('default', LJob)).BeFalse;
end;

procedure TJobEngineTests.Additional_Queue_Is_Polled;
begin
  FOptions := TBackgroundJobsOptions.Create;
  FOptions.Workers(1).PollInterval(1).UseQueues(['default', 'emails']);
  Boot('InMemory');
  TDextJobs.Enqueue<TEngineJob>('Touch', [], 'emails');

  Should(RunServer(function: Boolean begin Result := TEngineJob.Calls = 1; end, 15000)).BeTrue;
end;

procedure TJobEngineTests.Idle_Server_Stops_Promptly;
var
  LServer: TJobServer;
  LWatch: TStopwatch;
begin
  FOptions := TBackgroundJobsOptions.Create;
  FOptions.Workers(2).PollInterval(60);
  Boot('InMemory');
  LServer := TJobServer.Create(FStorage, FProvider, FOptions);
  try
    LServer.Start;
    Sleep(150);
    LWatch := TStopwatch.StartNew;
    LServer.Stop;
    // The poll interval is 60 s: only a wake-up on cancellation can be this fast.
    Should(LWatch.ElapsedMilliseconds < 5000).BeTrue;
  finally
    LServer.Free;
  end;
end;

procedure TJobEngineTests.Server_Is_Registered_In_Container;
var
  LObj: TObject;
begin
  FOptions := TBackgroundJobsOptions.Create;
  Boot('InMemory');
  LObj := FProvider.GetService(TServiceType.FromClass(TJobServer));
  Should(LObj <> nil).BeTrue;
  Should(LObj is TJobServer).BeTrue;
end;

procedure TJobEngineTests.InMemory_Orphan_Is_Requeued;
var
  LEx: IJobStorageEx;
  LJob: TJobInfo;
begin
  FOptions := TBackgroundJobsOptions.Create;
  Boot('InMemory');
  Should(Supports(FStorage, IJobStorageEx, LEx)).BeTrue;
  TDextJobs.Enqueue<TEngineJob>('Touch', []);
  Should(FStorage.GetNextJob('default', LJob)).BeTrue; // now Processing, worker "dies"
  Should(FStorage.GetNextJob('default', LJob)).BeFalse;

  Should(LEx.RecoverOrphans(Now + 1, 3)).Be(1);
  Should(FStorage.GetNextJob('default', LJob)).BeTrue;
  Should(LJob.AttemptCount).Be(1);
end;

procedure TJobEngineTests.InMemory_Orphan_Out_Of_Attempts_Fails;
var
  LEx: IJobStorageEx;
  LJob: TJobInfo;
begin
  FOptions := TBackgroundJobsOptions.Create;
  Boot('InMemory');
  Supports(FStorage, IJobStorageEx, LEx);
  TDextJobs.Enqueue<TEngineJob>('Touch', []);
  FStorage.GetNextJob('default', LJob);

  Should(LEx.RecoverOrphans(Now + 1, 1)).Be(1);
  Should(FStorage.GetNextJob('default', LJob)).BeFalse; // failed, not requeued
end;

procedure TJobEngineTests.Sqlite_Orphan_Is_Requeued;
var
  LEx: IJobStorageEx;
  LJob: TJobInfo;
begin
  FOptions := TBackgroundJobsOptions.Create;
  Boot('SQLite');
  Should(Supports(FStorage, IJobStorageEx, LEx)).BeTrue;
  TDextJobs.Enqueue<TEngineJob>('Touch', []);
  Should(FStorage.GetNextJob('default', LJob)).BeTrue;

  Should(LEx.RecoverOrphans(Now + 1, 3)).Be(1);
  Should(FStorage.GetNextJob('default', LJob)).BeTrue;
  Should(LJob.AttemptCount).Be(1);
end;

procedure TJobEngineTests.Sqlite_ScheduleRetry_Delays_The_Job;
var
  LEx: IJobStorageEx;
  LJob: TJobInfo;
  LId: string;
begin
  FOptions := TBackgroundJobsOptions.Create;
  Boot('SQLite');
  Supports(FStorage, IJobStorageEx, LEx);
  TDextJobs.Enqueue<TEngineJob>('Touch', []);
  FStorage.GetNextJob('default', LJob);

  LId := LJob.Id;
  LEx.ScheduleRetry(LId, Now + 1, 'later'); // a day from now
  Should(FStorage.GetNextJob('default', LJob)).BeFalse;
  LEx.ScheduleRetry(LId, Now - 1, 'now');
  Should(FStorage.GetNextJob('default', LJob)).BeTrue;
  Should(LJob.AttemptCount).Be(2);
  Should(LJob.ErrorLog).Be('now');
end;

end.
