{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{***************************************************************************}
unit Dext.Server.BoundedExecutor.Tests;

interface

uses
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Server.BoundedExecutor,
  System.SysUtils,
  System.Classes,
  System.SyncObjs;

type
  [TestFixture('Dext Bounded Executor')]
  TBoundedExecutorTests = class
  public
    [Test]
    procedure Test_Task_Execution;
    [Test]
    procedure Test_Queue_Capacity;
    [Test]
    procedure Test_Executor_Shutdown;
    [Test('Shutdown(True) runs the queued tasks before returning')]
    procedure Shutdown_Drain_Runs_Queued_Tasks;
    [Test('Shutdown without drain reports discarded raw tasks')]
    procedure Shutdown_Discards_And_Reports_Raw_Tasks;
    [Test('Failures are counted even without an OnException handler')]
    procedure Failures_Are_Counted_Without_Handler;
    [Test('A raising OnException handler does not kill the worker')]
    procedure Faulty_Handler_Does_Not_Kill_Worker;
  end;

implementation

{ TBoundedExecutorTests }

procedure TBoundedExecutorTests.Test_Task_Execution;
var
  Executor: TDextBoundedExecutor;
  Counter: Integer;
  Done: TSimpleEvent;
begin
  Counter := 0;
  Done := TSimpleEvent.Create(nil, True, False, '');
  try
    Executor := TDextBoundedExecutor.Create(2, 10);
    try
      Executor.TryEnqueue(
        procedure
        begin
          TInterlocked.Increment(Counter);
          if Counter = 2 then
            Done.SetEvent;
        end);

      Executor.TryEnqueue(
        procedure
        begin
          TInterlocked.Increment(Counter);
          if Counter = 2 then
            Done.SetEvent;
        end);

      Should(Done.WaitFor(1000) = wrSignaled).BeTrue;
      Should(Counter).Be(2);
    finally
      Executor.Free;
    end;
  finally
    Done.Free;
  end;
end;

procedure TBoundedExecutorTests.Test_Queue_Capacity;
var
  Executor: TDextBoundedExecutor;
  Success: Boolean;
begin
  // 0 threads, capacity 2
  Executor := TDextBoundedExecutor.Create(0, 2);
  try
    // Enqueue 1st task
    Success := Executor.TryEnqueue(
      procedure
      begin
      end);
    Should(Success).BeTrue;

    // Enqueue 2nd task
    Success := Executor.TryEnqueue(
      procedure
      begin
      end);
    Should(Success).BeTrue;

    // Enqueue 3rd task: exceeds capacity! Should fail (return False)
    Success := Executor.TryEnqueue(
      procedure
      begin
      end);
    Should(Success).BeFalse;

    Should(Executor.QueueCount).Be(2);
  finally
    Executor.Free;
  end;
end;

procedure TBoundedExecutorTests.Test_Executor_Shutdown;
var
  Executor: TDextBoundedExecutor;
begin
  Executor := TDextBoundedExecutor.Create(2, 5);
  try
    Executor.Shutdown;
  finally
    Executor.Free;
  end;
end;

procedure NoopRawTask(Data: Pointer);
begin
end;

procedure TBoundedExecutorTests.Shutdown_Drain_Runs_Queued_Tasks;
var
  Executor: TDextBoundedExecutor;
  Gate: TSimpleEvent;
  Counter: Integer;
  I: Integer;
begin
  Counter := 0;
  Gate := TSimpleEvent.Create(nil, True, False, '');
  try
    Executor := TDextBoundedExecutor.Create(1, 10);
    try
      // The only worker is busy, so the next three stay queued.
      Executor.TryEnqueue(
        procedure
        begin
          Gate.WaitFor(5000);
          TInterlocked.Increment(Counter);
        end);
      Sleep(50);
      for I := 1 to 3 do
        Executor.TryEnqueue(procedure begin TInterlocked.Increment(Counter); end);

      TThread.CreateAnonymousThread(
        procedure
        begin
          Sleep(100);
          Gate.SetEvent;
        end).Start;

      Executor.Shutdown(True);
      Should(Counter).Be(4); // nothing was thrown away
      Should(Executor.Running).BeFalse;
    finally
      Executor.Free;
    end;
  finally
    Gate.Free;
  end;
end;

procedure TBoundedExecutorTests.Shutdown_Discards_And_Reports_Raw_Tasks;
var
  Executor: TDextBoundedExecutor;
  Discarded: Integer;
begin
  Discarded := 0;
  Executor := TDextBoundedExecutor.Create(0, 4);
  try
    Executor.OnDiscard :=
      procedure(AProc: TDextTaskProc; AData: Pointer)
      begin
        Inc(Discarded);
      end;
    Should(Executor.TryEnqueue(NoopRawTask, nil)).BeTrue;
    Should(Executor.TryEnqueue(NoopRawTask, nil)).BeTrue;
    Executor.Shutdown;
    Should(Discarded).Be(2);
    Should(Executor.QueueCount).Be(0);
    Should(Executor.TryEnqueue(NoopRawTask, nil)).BeFalse; // no longer accepting
  finally
    Executor.Free;
  end;
end;

procedure TBoundedExecutorTests.Failures_Are_Counted_Without_Handler;
var
  Executor: TDextBoundedExecutor;
  Done: TSimpleEvent;
begin
  Done := TSimpleEvent.Create(nil, True, False, '');
  try
    Executor := TDextBoundedExecutor.Create(1, 5);
    try
      Executor.TryEnqueue(procedure begin raise EInvalidOp.Create('task blew up'); end);
      Executor.TryEnqueue(procedure begin Done.SetEvent; end);
      Should(Done.WaitFor(3000) = wrSignaled).BeTrue;
      Should(Executor.FailureCount).Be(1);
      Should(Executor.LastFailure).Contain('task blew up');
    finally
      Executor.Free;
    end;
  finally
    Done.Free;
  end;
end;

procedure TBoundedExecutorTests.Faulty_Handler_Does_Not_Kill_Worker;
var
  Executor: TDextBoundedExecutor;
  Done: TSimpleEvent;
begin
  Done := TSimpleEvent.Create(nil, True, False, '');
  try
    Executor := TDextBoundedExecutor.Create(1, 5);
    try
      Executor.OnException := procedure(E: Exception) begin raise Exception.Create('handler failed'); end;
      Executor.TryEnqueue(procedure begin raise EInvalidOp.Create('x'); end);
      Executor.TryEnqueue(procedure begin Done.SetEvent; end); // needs the same, surviving worker
      Should(Done.WaitFor(3000) = wrSignaled).BeTrue;
    finally
      Executor.Free;
    end;
  finally
    Done.Free;
  end;
end;

end.
