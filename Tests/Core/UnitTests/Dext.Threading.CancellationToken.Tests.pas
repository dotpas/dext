unit Dext.Threading.CancellationToken.Tests;

interface

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Threading.CancellationToken;

type
  [TestFixture('Cancellation token, registration, timer and link')]
  TCancellationTokenTests = class
  public
    [Test('A token must stay valid after its source is destroyed')]
    procedure Token_Outlives_Source;

    [Test('Reset must clear the flag and the wait event together')]
    procedure Reset_Clears_Flag_And_Event;

    [Test('A callback must run once, and at once when already cancelled')]
    procedure Register_Runs_Once_And_Inline_When_Cancelled;

    [Test('Unregister must prevent the callback')]
    procedure Unregister_Prevents_Callback;

    [Test('Callbacks must run in reverse order and all of them must run')]
    procedure Callbacks_Run_In_Reverse_Order_Despite_Errors;

    [Test('CancelAfter must cancel and wake a waiting thread')]
    procedure CancelAfter_Wakes_Waiter;

    [Test('Reset must drop a pending CancelAfter')]
    procedure Reset_Drops_Pending_CancelAfter;

    [Test('A later CancelAfter must replace the earlier one')]
    procedure Later_CancelAfter_Replaces_Earlier;

    [Test('A linked source must follow any of its parents')]
    procedure Linked_Follows_Any_Parent;

    [Test('A linked source must be cancelled at once by a cancelled parent')]
    procedure Linked_With_Cancelled_Parent_Is_Cancelled;

    [Test('Cancelling the child must not cancel the parent')]
    procedure Linked_Child_Does_Not_Cancel_Parent;

    [Test('Many threads registering while one cancels must lose no callback')]
    procedure Concurrent_Register_And_Cancel_Loses_Nothing;
  end;

implementation

procedure TCancellationTokenTests.Token_Outlives_Source;
var
  Source: TCancellationTokenSource;
  Token: ICancellationToken;
begin
  Source := TCancellationTokenSource.Create;
  Token := Source.Token;
  Source.Free;
  // Destroying the source cancels it; the token must still answer.
  Should(Token.IsCancellationRequested).BeTrue;
  Should(Token.WaitForCancellation(0) = wrSignaled).BeTrue;
end;

procedure TCancellationTokenTests.Reset_Clears_Flag_And_Event;
var
  Source: TCancellationTokenSource;
begin
  Source := TCancellationTokenSource.Create;
  try
    Source.Cancel;
    Should(Source.Token.WaitForCancellation(0) = wrSignaled).BeTrue;
    Source.Reset;
    Should(Source.Token.IsCancellationRequested).BeFalse;
    Should(Source.Token.WaitForCancellation(0) = wrTimeout).BeTrue;
    Source.Cancel;
    Should(Source.Token.IsCancellationRequested).BeTrue;
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.Register_Runs_Once_And_Inline_When_Cancelled;
var
  Source: TCancellationTokenSource;
  Calls: Integer;
begin
  Source := TCancellationTokenSource.Create;
  try
    Calls := 0;
    Source.Token.Register(procedure begin Inc(Calls); end);
    Should(Calls).Be(0);
    Source.Cancel;
    Source.Cancel;
    Should(Calls).Be(1);
    // Already cancelled: runs before Register returns.
    Source.Token.Register(procedure begin Inc(Calls); end);
    Should(Calls).Be(2);
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.Unregister_Prevents_Callback;
var
  Source: TCancellationTokenSource;
  Calls: Integer;
  Reg: ICancellationRegistration;
begin
  Source := TCancellationTokenSource.Create;
  try
    Calls := 0;
    Reg := Source.Token.Register(procedure begin Inc(Calls); end);
    Reg.Unregister;
    Reg.Unregister; // idempotent
    Source.Cancel;
    Should(Calls).Be(0);
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.Callbacks_Run_In_Reverse_Order_Despite_Errors;
var
  Source: TCancellationTokenSource;
  Order: string;
  Raised: string;
begin
  Source := TCancellationTokenSource.Create;
  try
    Order := '';
    Source.Token.Register(procedure begin Order := Order + 'A'; end);
    Source.Token.Register(
      procedure
      begin
        Order := Order + 'B';
        raise EInvalidOperation.Create('falha-B');
      end);
    Source.Token.Register(procedure begin Order := Order + 'C'; end);
    Raised := '';
    try
      Source.Cancel;
    except
      on E: EInvalidOperation do
        Raised := E.Message;
    end;
    Should(Order).Be('CBA');
    Should(Raised).Be('falha-B');
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.CancelAfter_Wakes_Waiter;
var
  Source: TCancellationTokenSource;
  WaitResult: TWaitResult;
begin
  Source := TCancellationTokenSource.Create;
  try
    Source.CancelAfter(50);
    Should(Source.IsCancellationRequested).BeFalse;
    WaitResult := Source.Token.WaitForCancellation(10000);
    Should(WaitResult = wrSignaled).BeTrue;
    Should(Source.IsCancellationRequested).BeTrue;
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.Reset_Drops_Pending_CancelAfter;
var
  Source: TCancellationTokenSource;
begin
  Source := TCancellationTokenSource.Create;
  try
    Source.CancelAfter(60);
    Source.Reset;
    // Far beyond the pending deadline: it must not fire.
    Should(Source.Token.WaitForCancellation(400) = wrTimeout).BeTrue;
    Should(Source.IsCancellationRequested).BeFalse;
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.Later_CancelAfter_Replaces_Earlier;
var
  Source: TCancellationTokenSource;
begin
  Source := TCancellationTokenSource.Create;
  try
    Source.CancelAfter(60);
    Source.CancelAfter(100000);
    Should(Source.Token.WaitForCancellation(400) = wrTimeout).BeTrue;
    Should(Source.IsCancellationRequested).BeFalse;
  finally
    Source.Free;
  end;
end;

procedure TCancellationTokenTests.Linked_Follows_Any_Parent;
var
  A, B: TCancellationTokenSource;
  Linked: TCancellationTokenSource;
begin
  A := TCancellationTokenSource.Create;
  B := TCancellationTokenSource.Create;
  try
    Linked := TCancellationTokenSource.CreateLinked([A.Token, B.Token]);
    try
      Should(Linked.IsCancellationRequested).BeFalse;
      B.Cancel;
      Should(Linked.IsCancellationRequested).BeTrue;
      Should(A.IsCancellationRequested).BeFalse;
    finally
      Linked.Free;
    end;
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TCancellationTokenTests.Linked_With_Cancelled_Parent_Is_Cancelled;
var
  A: TCancellationTokenSource;
  Linked: TCancellationTokenSource;
begin
  A := TCancellationTokenSource.Create;
  try
    A.Cancel;
    Linked := TCancellationTokenSource.CreateLinked([A.Token]);
    try
      Should(Linked.IsCancellationRequested).BeTrue;
    finally
      Linked.Free;
    end;
  finally
    A.Free;
  end;
end;

procedure TCancellationTokenTests.Linked_Child_Does_Not_Cancel_Parent;
var
  A: TCancellationTokenSource;
  Linked: TCancellationTokenSource;
begin
  A := TCancellationTokenSource.Create;
  try
    Linked := TCancellationTokenSource.CreateLinked([A.Token]);
    Linked.Cancel;
    Linked.Free;
    Should(A.IsCancellationRequested).BeFalse;
    // The parent can still be cancelled after the child is gone.
    A.Cancel;
    Should(A.IsCancellationRequested).BeTrue;
  finally
    A.Free;
  end;
end;

procedure TCancellationTokenTests.Concurrent_Register_And_Cancel_Loses_Nothing;
const
  THREADS = 8;
  PER_THREAD = 500;
var
  Source: TCancellationTokenSource;
  Calls: Integer;
  Go: TEvent;
  Done: TCountdownEvent;
  I: Integer;
begin
  Source := TCancellationTokenSource.Create;
  Go := TEvent.Create(nil, True, False, '');
  Done := TCountdownEvent.Create(THREADS);
  try
    Calls := 0;
    for I := 1 to THREADS do
      TThread.CreateAnonymousThread(
        procedure
        var
          J: Integer;
        begin
          Go.WaitFor(INFINITE);
          for J := 1 to PER_THREAD do
            Source.Token.Register(
              procedure
              begin
                TInterlocked.Increment(Calls);
              end);
          Done.Signal;
        end).Start;
    Go.SetEvent;
    // Cancel while the threads are still registering.
    Source.Cancel;
    Done.WaitFor(30000);
    // Every callback ran exactly once: collected by Cancel or run inline.
    Should(Calls).Be(THREADS * PER_THREAD);
  finally
    Done.Free;
    Go.Free;
    Source.Free;
  end;
end;

end.
