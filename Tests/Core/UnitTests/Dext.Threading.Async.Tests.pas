unit Dext.Threading.Async.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Threading.CancellationToken,
  Dext.Threading.Async;

type
  [TestFixture('Async Tasks - callbacks, cancellation and failures')]
  TAsyncTaskTests = class
  public
    [Test('OnComplete runs on the main thread only when its queue is pumped')]
    procedure OnComplete_Runs_When_Queue_Is_Pumped;

    [Test('OnException receives the failure on the main thread')]
    procedure OnException_Receives_Failure;

    [Test('A failure with no handler is raised by Wait, not swallowed')]
    procedure Failure_Without_Handler_Is_Raised_By_Wait;

    [Test('OnCancelled runs when the token was cancelled before the start')]
    procedure OnCancelled_Runs_For_Cancelled_Token;

    [Test('OnCancelled replaces OnException for a cancellation')]
    procedure OnCancelled_Replaces_OnException;

    [Test('A cancellation with no handler ends quietly')]
    procedure Cancellation_Without_Handler_Is_Quiet;

    [Test('Async callbacks run on the worker thread without pumping')]
    procedure Async_Callbacks_Need_No_Pumping;

    [Test('Await runs on the calling thread and skips the callbacks')]
    procedure Await_Is_Synchronous_And_Skips_Callbacks;

    [Test('WaitPumping reports a timeout')]
    procedure WaitPumping_Reports_Timeout;
  end;

implementation

procedure TAsyncTaskTests.OnComplete_Runs_When_Queue_Is_Pumped;
var
  LTask: IAsyncTask;
  LResult: Integer;
  LThread: TThreadID;
begin
  LResult := 0;
  LThread := 0;
  LTask := TAsyncTask.Run<Integer>(function: Integer begin Result := 42; end)
    .OnComplete(
      procedure(V: Integer)
      begin
        LResult := V;
        LThread := TThread.CurrentThread.ThreadID;
      end)
    .Start;
  Should(TAsyncTask.WaitPumping(LTask, 5000)).BeTrue;
  Should(LResult).Be(42);
  Should(LThread = MainThreadID).BeTrue;
end;

procedure TAsyncTaskTests.OnException_Receives_Failure;
var
  LTask: IAsyncTask;
  LMessage: string;
begin
  LMessage := '';
  LTask := TAsyncTask.Run<Integer>(
    function: Integer
    begin
      raise EInvalidOp.Create('boom');
    end)
    .OnException(procedure(E: Exception) begin LMessage := E.Message; end)
    .Start;
  Should(TAsyncTask.WaitPumping(LTask, 5000)).BeTrue;
  Should(LMessage).Be('boom');
end;

procedure TAsyncTaskTests.Failure_Without_Handler_Is_Raised_By_Wait;
var
  LTask: IAsyncTask;
  LRaised: Boolean;
begin
  LTask := TAsyncTask.Run<Integer>(
    function: Integer
    begin
      raise EInvalidOp.Create('lost?');
    end).Start;
  LRaised := False;
  try
    LTask.Wait;
  except
    on E: EAggregateException do LRaised := True;
  end;
  Should(LRaised).BeTrue;
end;

procedure TAsyncTaskTests.OnCancelled_Runs_For_Cancelled_Token;
var
  LSource: TCancellationTokenSource;
  LTask: IAsyncTask;
  LCancelled: Boolean;
  LWorkRan: Boolean;
begin
  LSource := TCancellationTokenSource.Create;
  try
    LSource.Cancel;
    LCancelled := False;
    LWorkRan := False;
    LTask := TAsyncTask.Run<Integer>(
      function: Integer
      begin
        LWorkRan := True;
        Result := 1;
      end)
      .WithCancellation(LSource.Token)
      .OnCancelled(procedure begin LCancelled := True; end)
      .Start;
    Should(TAsyncTask.WaitPumping(LTask, 5000)).BeTrue;
    Should(LCancelled).BeTrue;
    Should(LWorkRan).BeFalse;
  finally
    LSource.Free;
  end;
end;

procedure TAsyncTaskTests.OnCancelled_Replaces_OnException;
var
  LSource: TCancellationTokenSource;
  LTask: IAsyncTask;
  LCancelled, LFailed: Boolean;
begin
  LSource := TCancellationTokenSource.Create;
  try
    LSource.Cancel;
    LCancelled := False;
    LFailed := False;
    LTask := TAsyncTask.Run<Integer>(function: Integer begin Result := 1; end)
      .WithCancellation(LSource.Token)
      .OnCancelled(procedure begin LCancelled := True; end)
      .OnException(procedure(E: Exception) begin LFailed := True; end)
      .Start;
    TAsyncTask.WaitPumping(LTask, 5000);
    Should(LCancelled).BeTrue;
    Should(LFailed).BeFalse;
  finally
    LSource.Free;
  end;
end;

procedure TAsyncTaskTests.Cancellation_Without_Handler_Is_Quiet;
var
  LSource: TCancellationTokenSource;
  LTask: IAsyncTask;
  LRaised: Boolean;
begin
  LSource := TCancellationTokenSource.Create;
  try
    LSource.Cancel;
    LTask := TAsyncTask.Run<Integer>(function: Integer begin Result := 1; end)
      .WithCancellation(LSource.Token)
      .Start;
    LRaised := False;
    try
      LTask.Wait;
    except
      on E: Exception do LRaised := True;
    end;
    Should(LRaised).BeFalse;
  finally
    LSource.Free;
  end;
end;

procedure TAsyncTaskTests.Async_Callbacks_Need_No_Pumping;
var
  LTask: IAsyncTask;
  LResult: Integer;
begin
  LResult := 0;
  LTask := TAsyncTask.Run<Integer>(function: Integer begin Result := 7; end)
    .OnCompleteAsync(procedure(V: Integer) begin LResult := V; end)
    .Start;
  LTask.Wait; // no CheckSynchronize anywhere
  Should(LResult).Be(7);
end;

procedure TAsyncTaskTests.Await_Is_Synchronous_And_Skips_Callbacks;
var
  LCalled: Boolean;
  LThread: TThreadID;
  LValue: Integer;
begin
  LCalled := False;
  LThread := 0;
  LValue := TAsyncTask.Run<Integer>(
    function: Integer
    begin
      LThread := TThread.CurrentThread.ThreadID;
      Result := 5;
    end)
    .OnCompleteAsync(procedure(V: Integer) begin LCalled := True; end)
    .Await;
  Should(LValue).Be(5);
  Should(LThread = TThread.CurrentThread.ThreadID).BeTrue;
  Should(LCalled).BeFalse;
end;

procedure TAsyncTaskTests.WaitPumping_Reports_Timeout;
var
  LTask: IAsyncTask;
begin
  LTask := TAsyncTask.Run<Integer>(
    function: Integer
    begin
      Sleep(600);
      Result := 1;
    end).Start;
  Should(TAsyncTask.WaitPumping(LTask, 30)).BeFalse;
  LTask.Wait;
end;

end.
