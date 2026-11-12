unit Dext.Hosting.Service.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Threading.CancellationToken,
  Dext.Hosting.BackgroundService;

type
  /// <summary>Runs until its token is cancelled (a well-behaved service).</summary>
  TPoliteService = class(TBackgroundService)
  protected
    procedure Execute(Token: ICancellationToken); override;
  public
    Runs: Integer;
  end;

  /// <summary>Ignores its token until Release is signaled (a stubborn service).</summary>
  TStubbornService = class(TBackgroundService)
  protected
    procedure Execute(Token: ICancellationToken); override;
  public
    Release: TEvent;
    Finished: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TFailingService = class(TBackgroundService)
  protected
    procedure Execute(Token: ICancellationToken); override;
  end;

  [TestFixture('Hosted services: start, stop and failures')]
  THostedServiceTests = class
  public
    [Test('Start twice keeps a single thread')]
    procedure Start_Twice_Runs_One_Thread;

    [Test('A service can be started again after Stop')]
    procedure Restart_After_Stop;

    [Test('Stop gives up after StopTimeoutMs and detaches the thread')]
    procedure Stop_Has_A_Deadline;

    [Test('A cancelled token ends the manager wait at once')]
    procedure Manager_Stop_Honours_Token;

    [Test('A failure of Execute is kept in LastError')]
    procedure Failure_Is_Kept;
  end;

implementation

{ TPoliteService }

procedure TPoliteService.Execute(Token: ICancellationToken);
begin
  TInterlocked.Increment(Runs);
  Token.WaitForCancellation(INFINITE);
end;

{ TStubbornService }

constructor TStubbornService.Create;
begin
  inherited Create;
  Release := TEvent.Create(nil, True, False, '');
end;

destructor TStubbornService.Destroy;
begin
  Release.Free;
  inherited;
end;

procedure TStubbornService.Execute(Token: ICancellationToken);
begin
  Release.WaitFor(30000);
  TInterlocked.Exchange(Finished, 1);
end;

{ TFailingService }

procedure TFailingService.Execute(Token: ICancellationToken);
begin
  raise EInvalidOp.Create('worker exploded');
end;

{ THostedServiceTests }

procedure THostedServiceTests.Start_Twice_Runs_One_Thread;
var
  LSvc: TPoliteService;
begin
  LSvc := TPoliteService.Create;
  try
    LSvc.Start;
    LSvc.Start; // must not start a second thread
    Sleep(150);
    Should(LSvc.IsRunning).BeTrue;
    Should(LSvc.Runs).Be(1);
    LSvc.Stop;
    Should(LSvc.IsRunning).BeFalse;
  finally
    LSvc.Free;
  end;
end;

procedure THostedServiceTests.Restart_After_Stop;
var
  LSvc: TPoliteService;
begin
  LSvc := TPoliteService.Create;
  try
    LSvc.Start;
    Sleep(100);
    LSvc.Stop;
    LSvc.Start;
    Sleep(100);
    LSvc.Stop;
    Should(LSvc.Runs).Be(2);
  finally
    LSvc.Free;
  end;
end;

procedure THostedServiceTests.Stop_Has_A_Deadline;
var
  LSvc: TStubbornService;
  LWatch: TStopwatch;
  LWait: TStopwatch;
begin
  LSvc := TStubbornService.Create;
  try
    LSvc.StopTimeoutMs := 100;
    LSvc.Start;
    Sleep(100);
    LWatch := TStopwatch.StartNew;
    LSvc.Stop; // the service ignores its token: Stop must still return
    Should(LWatch.ElapsedMilliseconds < 5000).BeTrue;
    Should(LSvc.Finished).Be(0); // it is still running, detached

    // Let it finish; the detached thread frees itself.
    LSvc.Release.SetEvent;
    LWait := TStopwatch.StartNew;
    while (LSvc.Finished = 0) and (LWait.ElapsedMilliseconds < 5000) do
      Sleep(10);
    Should(LSvc.Finished).Be(1);
    Sleep(100);
  finally
    LSvc.Free;
  end;
end;

procedure THostedServiceTests.Manager_Stop_Honours_Token;
var
  LSvc: TStubbornService;
  LManager: THostedServiceManager;
  LSource: TCancellationTokenSource;
  LWatch: TStopwatch;
  LWait: TStopwatch;
begin
  LSvc := TStubbornService.Create;
  LSvc._AddRef; // owned by the manager's interface list from here on
  LManager := THostedServiceManager.Create;
  LSource := TCancellationTokenSource.Create;
  try
    LManager.RegisterService(LSvc);
    LManager.StartAsync;
    Sleep(100);

    LSource.Cancel; // the caller has no patience at all
    LWatch := TStopwatch.StartNew;
    LManager.StopAsync(LSource.Token);
    Should(LWatch.ElapsedMilliseconds < 5000).BeTrue;

    LSvc.Release.SetEvent;
    LWait := TStopwatch.StartNew;
    while (LSvc.Finished = 0) and (LWait.ElapsedMilliseconds < 5000) do
      Sleep(10);
    Sleep(100);
  finally
    LSource.Free;
    LManager.Free;
    LSvc._Release;
  end;
end;

procedure THostedServiceTests.Failure_Is_Kept;
var
  LSvc: TFailingService;
  LWait: TStopwatch;
begin
  LSvc := TFailingService.Create;
  try
    LSvc.Start;
    LWait := TStopwatch.StartNew;
    while LSvc.IsRunning and (LWait.ElapsedMilliseconds < 5000) do
      Sleep(10);
    LSvc.Stop;
    Should(LSvc.LastError).Be('worker exploded');
  finally
    LSvc.Free;
  end;
end;

end.
