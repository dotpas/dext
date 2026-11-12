unit Dext.Resilience.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.Rtti,
  Dext.Threading.CancellationToken,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Resilience;

type
  [TestFixture('Resilience Pipeline & Fault Handling Tests')]
  TResilienceTests = class
  public
    [Test('Should retry failed operations and succeed or fail accordingly')]
    procedure TestResilienceRetry;

    [Test('Should trip circuit breaker and block requests when failure threshold is reached')]
    procedure TestResilienceCircuitBreaker;

    [Test('Should execute fallback when an exception is thrown')]
    procedure TestResilienceFallback;

    [Test('Should timeout when operations exceed maximum duration')]
    procedure TestResilienceTimeout;

    [Test('Concurrent callers must not serialize on the pipeline')]
    procedure Concurrent_Callers_Do_Not_Serialize;

    [Test('Breaker counts consecutive failures: a success resets the count')]
    procedure Breaker_Counts_Consecutive_Failures;

    [Test('Half-open breaker admits exactly one probe')]
    procedure HalfOpen_Admits_Single_Probe;

    [Test('Breaker reports state changes')]
    procedure Breaker_Reports_State_Changes;

    [Test('Procedure fallback handles a value-returning call')]
    procedure Proc_Fallback_Handles_Func_Call;

    [Test('Value fallback handles a procedure call')]
    procedure Func_Fallback_Handles_Proc_Call;

    [Test('Retry wait wakes up when the token is cancelled')]
    procedure Retry_Wait_Is_Cancellable;

    [Test('Retry honours the ShouldRetry predicate')]
    procedure Retry_Honours_Predicate;

    [Test('Timeout cancels the token given to the action')]
    procedure Timeout_Cancels_Action_Token;

    [Test('Timeout rethrows the action exception with its own class')]
    procedure Timeout_Rethrows_Action_Exception;
  end;

implementation

procedure TResilienceTests.TestResilienceRetry;
var
  Counter: Integer;
  Pipeline: TResiliencePipeline;
  Res: Integer;
  LFunc: TFunc<Integer>;
begin
  Counter := 0;
  Pipeline := TResiliencePipeline.Create.AddRetry(3, 10);
  LFunc := function: Integer
    begin
      Inc(Counter);
      if Counter < 3 then
        raise Exception.Create('Fail');
      Result := 42;
    end;
  Res := Pipeline.Execute<Integer>(LFunc);
  Should(Res).Be(42);
  Should(Counter).Be(3);
end;

procedure TResilienceTests.TestResilienceCircuitBreaker;
var
  Pipeline: TResiliencePipeline;
  CBExceptionCaught: Boolean;
  I: Integer;
begin
  Pipeline := TResiliencePipeline.Create.AddCircuitBreaker(2, 1000);
  
  // Fail first 2 times
  for I := 1 to 2 do
  begin
    try
      Pipeline.Execute(
        procedure
        begin
          raise Exception.Create('Fail');
        end
      );
    except
      on E: Exception do; // expected
    end;
  end;

  // 3rd call should throw ECircuitBrokenException immediately
  CBExceptionCaught := False;
  try
    Pipeline.Execute(
      procedure
      begin
        // shouldn't even execute
      end
    );
  except
    on E: ECircuitBrokenException do
      CBExceptionCaught := True;
  end;

  Should(CBExceptionCaught).BeTrue;
end;

procedure TResilienceTests.TestResilienceFallback;
var
  Pipeline: TResiliencePipeline;
  Res: string;
  LFallback: TFunc<string>;
  LFunc: TFunc<string>;
begin
  LFallback := function: string
    begin
      Result := 'fallback-value';
    end;
  Pipeline := TResiliencePipeline.Create.AddFallback<string>(LFallback);
      
  LFunc := function: string
    begin
      raise Exception.Create('Force Error');
    end;

  Res := Pipeline.Execute<string>(LFunc);
  Should(Res).Be('fallback-value');
end;

procedure TResilienceTests.TestResilienceTimeout;
var
  Pipeline: TResiliencePipeline;
  TimeoutCaught: Boolean;
begin
  Pipeline := TResiliencePipeline.Create.AddTimeout(50);
  TimeoutCaught := False;
  try
    Pipeline.Execute(
      procedure
      begin
        Sleep(200);
      end
    );
  except
    on E: ETimeoutException do
      TimeoutCaught := True;
  end;
  Should(TimeoutCaught).BeTrue;
end;

procedure TResilienceTests.Concurrent_Callers_Do_Not_Serialize;
var
  LPipeline: IResiliencePipeline;
  LA, LB: TEvent;
  LOkA, LOkB: Boolean;
  LDoneA, LDoneB: TEvent;
begin
  LPipeline := TResiliencePipelineImpl.Create.AddRetry(0, 0);
  LA := TEvent.Create(nil, True, False, '');
  LB := TEvent.Create(nil, True, False, '');
  LDoneA := TEvent.Create(nil, True, False, '');
  LDoneB := TEvent.Create(nil, True, False, '');
  try
    LOkA := False;
    LOkB := False;
    // Each action waits for the other one: only possible if both run at once.
    TThread.CreateAnonymousThread(
      procedure
      begin
        LPipeline.Execute(
          procedure
          begin
            LA.SetEvent;
            LOkA := LB.WaitFor(3000) = wrSignaled;
          end);
        LDoneA.SetEvent;
      end).Start;
    TThread.CreateAnonymousThread(
      procedure
      begin
        LPipeline.Execute(
          procedure
          begin
            LB.SetEvent;
            LOkB := LA.WaitFor(3000) = wrSignaled;
          end);
        LDoneB.SetEvent;
      end).Start;
    LDoneA.WaitFor(6000);
    LDoneB.WaitFor(6000);
    Should(LOkA).BeTrue;
    Should(LOkB).BeTrue;
  finally
    LA.Free;
    LB.Free;
    LDoneA.Free;
    LDoneB.Free;
  end;
end;

procedure TResilienceTests.Breaker_Counts_Consecutive_Failures;
var
  LPipeline: IResiliencePipeline;
  LRan: Boolean;
  procedure Fail;
  begin
    try
      LPipeline.Execute(procedure begin raise Exception.Create('x'); end);
    except
      on E: ECircuitBrokenException do raise;
      on E: Exception do ;
    end;
  end;
begin
  LPipeline := TResiliencePipelineImpl.Create.AddCircuitBreaker(2, 60000);
  Fail;
  LPipeline.Execute(procedure begin end); // success: the count restarts
  Fail;                                   // one failure, not two in a row
  LRan := False;
  LPipeline.Execute(procedure begin LRan := True; end);
  Should(LRan).BeTrue;
end;

procedure TResilienceTests.HalfOpen_Admits_Single_Probe;
var
  LPipeline: IResiliencePipeline;
  LInProbe, LRelease, LDone: TEvent;
  LBlocked: Boolean;
begin
  LPipeline := TResiliencePipelineImpl.Create.AddCircuitBreaker(1, 40);
  try
    LPipeline.Execute(procedure begin raise Exception.Create('x'); end);
  except
    on E: Exception do ;
  end;
  Sleep(120);

  LInProbe := TEvent.Create(nil, True, False, '');
  LRelease := TEvent.Create(nil, True, False, '');
  LDone := TEvent.Create(nil, True, False, '');
  try
    TThread.CreateAnonymousThread(
      procedure
      begin
        try
          LPipeline.Execute(
            procedure
            begin
              LInProbe.SetEvent;
              LRelease.WaitFor(5000);
            end);
        finally
          LDone.SetEvent;
        end;
      end).Start;
    Should(LInProbe.WaitFor(3000) = wrSignaled).BeTrue;

    LBlocked := False;
    try
      LPipeline.Execute(procedure begin end);
    except
      on E: ECircuitBrokenException do LBlocked := True;
    end;
    Should(LBlocked).BeTrue;

    LRelease.SetEvent;
    LDone.WaitFor(5000);
    // The probe succeeded: the circuit is closed again.
    LPipeline.Execute(procedure begin end);
  finally
    LInProbe.Free;
    LRelease.Free;
    LDone.Free;
  end;
end;

procedure TResilienceTests.Breaker_Reports_State_Changes;
var
  LPipeline: IResiliencePipeline;
  LLog: string;
begin
  LLog := '';
  LPipeline := TResiliencePipelineImpl.Create.AddCircuitBreaker(1, 30,
    procedure(AOld, ANew: TCircuitBreakerState)
    begin
      LLog := LLog + Format('%d>%d;', [Ord(AOld), Ord(ANew)]);
    end);
  try
    LPipeline.Execute(procedure begin raise Exception.Create('x'); end);
  except
    on E: Exception do ;
  end;
  Sleep(100);
  LPipeline.Execute(procedure begin end);
  // closed>open, open>half-open, half-open>closed
  Should(LLog).Be('0>1;1>2;2>0;');
end;

procedure TResilienceTests.Proc_Fallback_Handles_Func_Call;
var
  LPipeline: IResiliencePipeline;
  LHandled: Boolean;
  LValue: TValue;
begin
  LHandled := False;
  LPipeline := TResiliencePipelineImpl.Create.AddFallback(
    TProc(procedure begin LHandled := True; end));
  LValue := LPipeline.Execute(
    TFunc<TValue>(function: TValue begin raise Exception.Create('x'); end));
  Should(LHandled).BeTrue;
  Should(LValue.IsEmpty).BeTrue;
end;

procedure TResilienceTests.Func_Fallback_Handles_Proc_Call;
var
  LPipeline: IResiliencePipeline;
  LUsed: Boolean;
begin
  LUsed := False;
  LPipeline := TResiliencePipelineImpl.Create.AddFallback(
    TFunc<TValue>(function: TValue begin LUsed := True; Result := 1; end));
  LPipeline.Execute(TProc(procedure begin raise Exception.Create('x'); end));
  Should(LUsed).BeTrue;
end;

procedure TResilienceTests.Retry_Wait_Is_Cancellable;
var
  LPipeline: IResiliencePipeline;
  LSource: TCancellationTokenSource;
  LWatch: TStopwatch;
  LCancelled: Boolean;
begin
  LPipeline := TResiliencePipelineImpl.Create.AddRetry(5, 10000);
  LSource := TCancellationTokenSource.Create;
  try
    LSource.CancelAfter(100);
    LCancelled := False;
    LWatch := TStopwatch.StartNew;
    try
      LPipeline.Execute(
        TProc<ICancellationToken>(
          procedure(T: ICancellationToken)
          begin
            raise Exception.Create('x');
          end),
        LSource.Token);
    except
      on E: EOperationCancelled do LCancelled := True;
    end;
    Should(LCancelled).BeTrue;
    // The first back-off would last 10 s; the token cut it short.
    Should(LWatch.ElapsedMilliseconds < 5000).BeTrue;
  finally
    LSource.Free;
  end;
end;

procedure TResilienceTests.Retry_Honours_Predicate;
var
  LPipeline: IResiliencePipeline;
  LOptions: TRetryOptions;
  LCalls: Integer;
begin
  LOptions := TRetryOptions.Create(5, 1);
  LOptions.ShouldRetry :=
    function(const E: Exception): Boolean
    begin
      Result := E is EInvalidOp;
    end;
  LPipeline := TResiliencePipelineImpl.Create.AddRetry(LOptions);
  LCalls := 0;
  try
    LPipeline.Execute(
      procedure
      begin
        Inc(LCalls);
        raise EArgumentException.Create('not retried');
      end);
  except
    on E: EArgumentException do ;
  end;
  Should(LCalls).Be(1);
end;

procedure TResilienceTests.Timeout_Cancels_Action_Token;
var
  LPipeline: IResiliencePipeline;
  LStopped: TEvent;
  LTimedOut: Boolean;
begin
  LPipeline := TResiliencePipelineImpl.Create.AddTimeout(50);
  LStopped := TEvent.Create(nil, True, False, '');
  try
    LTimedOut := False;
    try
      LPipeline.Execute(
        TProc<ICancellationToken>(
          procedure(T: ICancellationToken)
          begin
            T.WaitForCancellation(10000);
            LStopped.SetEvent;
          end),
        nil);
    except
      on E: ETimeoutException do LTimedOut := True;
    end;
    Should(LTimedOut).BeTrue;
    // The action saw the cancellation and stopped by itself.
    Should(LStopped.WaitFor(3000) = wrSignaled).BeTrue;
  finally
    LStopped.Free;
  end;
end;

procedure TResilienceTests.Timeout_Rethrows_Action_Exception;
var
  LPipeline: IResiliencePipeline;
  LMessage: string;
begin
  LPipeline := TResiliencePipelineImpl.Create.AddTimeout(5000);
  LMessage := '';
  try
    LPipeline.Execute(procedure begin raise EInvalidOp.Create('boom'); end);
  except
    on E: EInvalidOp do LMessage := E.Message;
  end;
  Should(LMessage).Be('boom');
end;

end.
