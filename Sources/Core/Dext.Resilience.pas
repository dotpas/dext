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
{                                                                           }
{  Author:  Cesar Romero & Antigravity                                      }
{  Created: 2026-06-05                                                      }
{                                                                           }
{  Design notes                                                             }
{                                                                           }
{  - A pipeline is configured once and then shared by any number of         }
{    threads. Execute takes a snapshot of the policy list and runs outside  }
{    every lock, so concurrent callers never wait for each other.           }
{  - The first policy added is the OUTERMOST one: AddRetry then AddTimeout  }
{    retries the whole timed operation.                                     }
{  - Cancellation is cooperative. Execute accepts an ICancellationToken;    }
{    waits (retry back-off) wake up when it is cancelled, and a timeout     }
{    cancels the token it hands to the action. A running action cannot be   }
{    killed: it stops only if it looks at its token.                        }
{  - The circuit breaker counts CONSECUTIVE failures and lets exactly one   }
{    probe through while half-open.                                         }
{                                                                           }
{***************************************************************************}
unit Dext.Resilience;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  System.Rtti,
  Dext.Threading.CancellationToken;

type
  /// <summary>Base exception for resilience pipeline errors.</summary>
  EDextResilienceException = class(Exception);

  /// <summary>Exception thrown when a circuit breaker is open.</summary>
  ECircuitBrokenException = class(EDextResilienceException);

  /// <summary>Exception thrown when an operation times out.</summary>
  ETimeoutException = class(EDextResilienceException);

  /// <summary>Circuit breaker state representation.</summary>
  TCircuitBreakerState = (cbsClosed, cbsOpen, cbsHalfOpen);

  /// <summary>Called, outside any lock, after each circuit state change.</summary>
  TCircuitStateChanged = reference to procedure(AOld, ANew: TCircuitBreakerState);

  /// <summary>Decides whether a failure is worth another attempt.</summary>
  TRetryPredicate = reference to function(const E: Exception): Boolean;

  /// <summary>
  ///   Retry settings. BackoffMs doubles on every attempt up to MaxDelayMs
  ///   (0 = no cap). With Jitter the real wait is a random value between 0
  ///   and that delay ("full jitter"), so clients that failed together do not
  ///   retry together. ShouldRetry nil means: retry anything except a
  ///   cancellation or an open circuit. A cancellation is never retried.
  /// </summary>
  TRetryOptions = record
    MaxRetries: Integer;
    BackoffMs: Integer;
    MaxDelayMs: Integer;
    Jitter: Boolean;
    ShouldRetry: TRetryPredicate;
    class function Create(AMaxRetries: Integer;
      ABackoffMs: Integer = 100): TRetryOptions; static;
  end;

  /// <summary>Represents a single policy stage inside a resilience pipeline.</summary>
  IResiliencePolicy = interface
    ['{4B8D2C71-3F0A-4E65-A1D9-6C7E52B90F13}']
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue;
  end;

  /// <summary>
  ///   Thread-safe resilience pipeline for fault-handling. Configure it, then
  ///   share it: Execute may be called by many threads at the same time.
  /// </summary>
  IResiliencePipeline = interface
    ['{532E9156-0ACC-4526-8ECA-72D32ADFD59D}']
    function AddRetry(AMaxRetries: Integer; ABackoffMs: Integer = 100): IResiliencePipeline; overload;
    function AddRetry(const AOptions: TRetryOptions): IResiliencePipeline; overload;
    function AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer): IResiliencePipeline; overload;
    function AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer;
      const AOnStateChange: TCircuitStateChanged): IResiliencePipeline; overload;
    /// <summary>
    ///   A value fallback replaces the result of a failed call. A procedure
    ///   fallback handles the failure and swallows it (a value-returning call
    ///   then yields Default(T)). A cancellation is never masked.
    /// </summary>
    function AddFallback(const AFallbackFunc: TFunc<TValue>): IResiliencePipeline; overload;
    function AddFallback(const AFallbackProc: TProc): IResiliencePipeline; overload;
    function AddTimeout(ATimeoutMs: Integer): IResiliencePipeline;

    function Execute(const Action: TFunc<TValue>): TValue; overload;
    procedure Execute(const Action: TProc); overload;
    /// <summary>
    ///   Variants that hand a token to the action: it is cancelled when AToken
    ///   is, and when a timeout expires. AToken may be nil.
    /// </summary>
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue; overload;
    procedure Execute(const Action: TProc<ICancellationToken>;
      const AToken: ICancellationToken); overload;
  end;

  /// <summary>
  ///   Implementation of a Retry policy with exponential backoff.
  /// </summary>
  TRetryPolicy = class(TInterfacedObject, IResiliencePolicy)
  private
    FOptions: TRetryOptions;
    function CanRetry(const E: Exception): Boolean;
    function BackoffDelay(AAttempt: Integer): Integer;
    procedure Pause(ADelayMs: Integer; const AToken: ICancellationToken);
  public
    constructor Create(AMaxRetries: Integer; ADelayMs: Integer = 100); overload;
    constructor Create(const AOptions: TRetryOptions); overload;
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue;
  end;

  /// <summary>
  ///   Implementation of a Circuit Breaker policy: opens after N consecutive
  ///   failures, stays open for the break duration, then lets ONE probe call
  ///   through (half-open). The probe's result closes or reopens the circuit.
  /// </summary>
  TCircuitBreakerPolicy = class(TInterfacedObject, IResiliencePolicy)
  private
    FFailureThreshold: Integer;
    FBreakDurationMs: Integer;
    FState: TCircuitBreakerState;
    FFailures: Integer;
    FOpenedAt: UInt64;
    FProbing: Boolean;
    FLock: TCriticalSection;
    FOnStateChange: TCircuitStateChanged;
    function GetState: TCircuitBreakerState;
    procedure Admit;
    procedure RecordSuccess;
    procedure RecordFailure;
    procedure ReleaseProbe;
    procedure Notify(AOld, ANew: TCircuitBreakerState);
  public
    constructor Create(AFailureThreshold: Integer; ABreakDurationMs: Integer;
      const AOnStateChange: TCircuitStateChanged = nil);
    destructor Destroy; override;
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue;
    property State: TCircuitBreakerState read GetState;
  end;

  /// <summary>
  ///   Implementation of a Fallback policy (value or procedure).
  /// </summary>
  TFallbackPolicy = class(TInterfacedObject, IResiliencePolicy)
  private
    FFallbackFunc: TFunc<TValue>;
    FFallbackProc: TProc;
  public
    constructor Create(const AFallbackFunc: TFunc<TValue>); overload;
    constructor Create(const AFallbackProc: TProc); overload;
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue;
  end;

  /// <summary>
  ///   Implementation of a Timeout policy. On expiry it cancels the token the
  ///   action received and raises ETimeoutException. The action itself
  ///   stops only if it observes that token.
  /// </summary>
  TTimeoutPolicy = class(TInterfacedObject, IResiliencePolicy)
  private
    FTimeoutMs: Integer;
  public
    constructor Create(ATimeoutMs: Integer);
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue;
  end;

  /// <summary>
  ///   Concrete builder and manager of IResiliencePipeline.
  /// </summary>
  TResiliencePipelineImpl = class(TInterfacedObject, IResiliencePipeline)
  private
    FPolicies: TList<IResiliencePolicy>;
    FLock: TCriticalSection;
    function Snapshot: TArray<IResiliencePolicy>;
    function Add(const APolicy: IResiliencePolicy): IResiliencePipeline;
    function Run(const APolicies: TArray<IResiliencePolicy>; AIndex: Integer;
      const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue;
  public
    constructor Create;
    destructor Destroy; override;

    function AddRetry(AMaxRetries: Integer; ABackoffMs: Integer = 100): IResiliencePipeline; overload;
    function AddRetry(const AOptions: TRetryOptions): IResiliencePipeline; overload;
    function AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer): IResiliencePipeline; overload;
    function AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer;
      const AOnStateChange: TCircuitStateChanged): IResiliencePipeline; overload;
    function AddFallback(const AFallbackFunc: TFunc<TValue>): IResiliencePipeline; overload;
    function AddFallback(const AFallbackProc: TProc): IResiliencePipeline; overload;
    function AddTimeout(ATimeoutMs: Integer): IResiliencePipeline;

    function Execute(const Action: TFunc<TValue>): TValue; overload;
    procedure Execute(const Action: TProc); overload;
    function Execute(const Action: TFunc<ICancellationToken, TValue>;
      const AToken: ICancellationToken): TValue; overload;
    procedure Execute(const Action: TProc<ICancellationToken>;
      const AToken: ICancellationToken); overload;
  end;

  /// <summary>
  ///   Fluent wrapper record supporting generic execution and nice configuration API.
  /// </summary>
  TResiliencePipeline = record
  private
    FInstance: IResiliencePipeline;
  public
    class function Create: TResiliencePipeline; static;

    function AddRetry(AMaxRetries: Integer; ABackoffMs: Integer = 100): TResiliencePipeline; overload;
    function AddRetry(const AOptions: TRetryOptions): TResiliencePipeline; overload;
    function AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer): TResiliencePipeline; overload;
    function AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer;
      const AOnStateChange: TCircuitStateChanged): TResiliencePipeline; overload;
    function AddFallback<T>(const AFallbackFunc: TFunc<T>): TResiliencePipeline; overload;
    function AddFallback(const AFallbackFunc: TFunc<TValue>): TResiliencePipeline; overload;
    function AddFallback(const AFallbackProc: TProc): TResiliencePipeline; overload;
    function AddTimeout(ATimeoutMs: Integer): TResiliencePipeline;

    function Execute<T>(const Action: TFunc<T>): T; overload;
    procedure Execute(const Action: TProc); overload;
    function Execute<T>(const Action: TFunc<ICancellationToken, T>;
      const AToken: ICancellationToken): T; overload;
    procedure Execute(const Action: TProc<ICancellationToken>;
      const AToken: ICancellationToken); overload;

    property Instance: IResiliencePipeline read FInstance;
  end;

function GetTickCount64: UInt64;

implementation

uses
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  System.Threading,
  System.Diagnostics;

function GetTickCount64: UInt64;
begin
  {$IFDEF MSWINDOWS}
  Result := Winapi.Windows.GetTickCount64;
  {$ELSE}
    {$IF CompilerVersion >= 35.0}
    Result := TThread.GetTickCount64;
    {$ELSE}
    Result := TStopwatch.GetTimeStamp * 1000 div TStopwatch.Frequency;
    {$ENDIF}
  {$ENDIF}
end;

var
  GRandomSeed: Integer = 0;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
/// <summary>Thread-safe pseudo random number (SplitMix style, no shared state
/// beyond one atomic counter). Good enough to spread retries; not for crypto.</summary>
function NextRandom: Cardinal;
var
  X: Cardinal;
begin
  X := Cardinal(TInterlocked.Add(GRandomSeed, -1640531527)); // $9E3779B9
  X := (X xor (X shr 16)) * $85EBCA6B;
  X := (X xor (X shr 13)) * $C2B2AE35;
  Result := X xor (X shr 16);
end;
{$OVERFLOWCHECKS ON}
{$RANGECHECKS ON}

function CancelledError: Exception;
begin
  Result := EOperationCancelled.Create('Operation cancelled!');
end;

{ TRetryOptions }

class function TRetryOptions.Create(AMaxRetries, ABackoffMs: Integer): TRetryOptions;
begin
  Result.MaxRetries := AMaxRetries;
  Result.BackoffMs := ABackoffMs;
  Result.MaxDelayMs := 0;
  Result.Jitter := False;
  Result.ShouldRetry := nil;
end;

{ TRetryPolicy }

constructor TRetryPolicy.Create(AMaxRetries: Integer; ADelayMs: Integer);
begin
  Create(TRetryOptions.Create(AMaxRetries, ADelayMs));
end;

constructor TRetryPolicy.Create(const AOptions: TRetryOptions);
begin
  inherited Create;
  FOptions := AOptions;
end;

function TRetryPolicy.CanRetry(const E: Exception): Boolean;
begin
  if E is EOperationCancelled then
    Exit(False);
  if Assigned(FOptions.ShouldRetry) then
    Result := FOptions.ShouldRetry(E)
  else
    Result := not (E is ECircuitBrokenException);
end;

function TRetryPolicy.BackoffDelay(AAttempt: Integer): Integer;
var
  LDelay, LCap: Int64;
  I: Integer;
begin
  LDelay := FOptions.BackoffMs;
  if LDelay < 0 then
    LDelay := 0;
  LCap := FOptions.MaxDelayMs;
  if LCap <= 0 then
    LCap := High(Integer);
  // Doubles per attempt, never overflowing: it stops at the cap.
  for I := 2 to AAttempt do
  begin
    LDelay := LDelay * 2;
    if LDelay >= LCap then
      Break;
  end;
  if LDelay > LCap then
    LDelay := LCap;
  if FOptions.Jitter and (LDelay > 0) then
    LDelay := NextRandom mod (LDelay + 1);
  Result := Integer(LDelay);
end;

procedure TRetryPolicy.Pause(ADelayMs: Integer; const AToken: ICancellationToken);
begin
  if ADelayMs <= 0 then
    Exit;
  if AToken <> nil then
  begin
    // The wait belongs to the token: a cancellation wakes it up at once.
    if AToken.WaitForCancellation(Cardinal(ADelayMs)) = wrSignaled then
      raise CancelledError;
  end
  else
    Sleep(ADelayMs);
end;

function TRetryPolicy.Execute(const Action: TFunc<ICancellationToken, TValue>;
  const AToken: ICancellationToken): TValue;
var
  LAttempt: Integer;
begin
  LAttempt := 0;
  while True do
  begin
    if AToken <> nil then
      AToken.ThrowIfCancellationRequested;
    try
      Exit(Action(AToken));
    except
      on E: Exception do
      begin
        if not CanRetry(E) then
          raise;
        Inc(LAttempt);
        if LAttempt > FOptions.MaxRetries then
          raise;
        Pause(BackoffDelay(LAttempt), AToken);
      end;
    end;
  end;
end;

{ TCircuitBreakerPolicy }

constructor TCircuitBreakerPolicy.Create(AFailureThreshold: Integer;
  ABreakDurationMs: Integer; const AOnStateChange: TCircuitStateChanged);
begin
  inherited Create;
  if AFailureThreshold < 1 then
    AFailureThreshold := 1;
  FFailureThreshold := AFailureThreshold;
  FBreakDurationMs := ABreakDurationMs;
  FOnStateChange := AOnStateChange;
  FState := cbsClosed;
  FFailures := 0;
  FOpenedAt := 0;
  FProbing := False;
  FLock := TCriticalSection.Create;
end;

destructor TCircuitBreakerPolicy.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TCircuitBreakerPolicy.GetState: TCircuitBreakerState;
begin
  FLock.Enter;
  try
    Result := FState;
  finally
    FLock.Leave;
  end;
end;

procedure TCircuitBreakerPolicy.Notify(AOld, ANew: TCircuitBreakerState);
begin
  if Assigned(FOnStateChange) and (AOld <> ANew) then
    FOnStateChange(AOld, ANew);
end;

procedure TCircuitBreakerPolicy.Admit;
var
  LOld, LNew: TCircuitBreakerState;
  LElapsed: Int64;
begin
  LOld := cbsClosed;
  LNew := cbsClosed;
  FLock.Enter;
  try
    LOld := FState;
    LNew := FState;
    case FState of
      cbsOpen:
        begin
          LElapsed := Int64(GetTickCount64 - FOpenedAt);
          if LElapsed >= FBreakDurationMs then
          begin
            // The break is over: this caller is the one probe.
            FState := cbsHalfOpen;
            FProbing := True;
            LNew := cbsHalfOpen;
          end
          else
            raise ECircuitBrokenException.CreateFmt(
              'Circuit is open. Re-trying blocked for another %d ms.',
              [FBreakDurationMs - LElapsed]);
        end;
      cbsHalfOpen:
        begin
          if FProbing then
            raise ECircuitBrokenException.Create(
              'Circuit is half-open: a probe call is already running.');
          FProbing := True;
        end;
    end;
  finally
    FLock.Leave;
  end;
  Notify(LOld, LNew);
end;

procedure TCircuitBreakerPolicy.RecordSuccess;
var
  LOld, LNew: TCircuitBreakerState;
begin
  FLock.Enter;
  try
    LOld := FState;
    // A success ends the run of failures: the count is of CONSECUTIVE ones.
    FFailures := 0;
    if FState = cbsHalfOpen then
    begin
      FState := cbsClosed;
      FProbing := False;
    end;
    LNew := FState;
  finally
    FLock.Leave;
  end;
  Notify(LOld, LNew);
end;

procedure TCircuitBreakerPolicy.RecordFailure;
var
  LOld, LNew: TCircuitBreakerState;
begin
  FLock.Enter;
  try
    LOld := FState;
    case FState of
      cbsHalfOpen:
        begin
          // The probe failed: back to open, with a fresh break period.
          FState := cbsOpen;
          FOpenedAt := GetTickCount64;
          FProbing := False;
        end;
      cbsClosed:
        begin
          Inc(FFailures);
          if FFailures >= FFailureThreshold then
          begin
            FState := cbsOpen;
            FOpenedAt := GetTickCount64;
          end;
        end;
      // cbsOpen: a call admitted before the circuit opened finished late.
    end;
    LNew := FState;
  finally
    FLock.Leave;
  end;
  Notify(LOld, LNew);
end;

procedure TCircuitBreakerPolicy.ReleaseProbe;
begin
  // The probe was cancelled: no verdict. The next caller probes again.
  FLock.Enter;
  try
    if FState = cbsHalfOpen then
      FProbing := False;
  finally
    FLock.Leave;
  end;
end;

function TCircuitBreakerPolicy.Execute(
  const Action: TFunc<ICancellationToken, TValue>;
  const AToken: ICancellationToken): TValue;
begin
  Admit;
  try
    Result := Action(AToken);
  except
    on E: Exception do
    begin
      if E is EOperationCancelled then
        ReleaseProbe
      else
        RecordFailure;
      raise;
    end;
  end;
  RecordSuccess;
end;

{ TFallbackPolicy }

constructor TFallbackPolicy.Create(const AFallbackFunc: TFunc<TValue>);
begin
  inherited Create;
  FFallbackFunc := AFallbackFunc;
end;

constructor TFallbackPolicy.Create(const AFallbackProc: TProc);
begin
  inherited Create;
  FFallbackProc := AFallbackProc;
end;

function TFallbackPolicy.Execute(const Action: TFunc<ICancellationToken, TValue>;
  const AToken: ICancellationToken): TValue;
begin
  try
    Result := Action(AToken);
  except
    on E: Exception do
    begin
      // A cancellation is the caller's decision: never replace it.
      if E is EOperationCancelled then
        raise;
      if Assigned(FFallbackFunc) then
        Result := FFallbackFunc()
      else if Assigned(FFallbackProc) then
      begin
        FFallbackProc();
        Result := TValue.Empty;
      end
      else
        raise;
    end;
  end;
end;

{ TTimeoutPolicy }

type
  /// <summary>
  ///   Meeting point between the thread that waits and the task that works.
  ///   Reference counted: whoever lets go last frees it, so a task that
  ///   finishes after its caller gave up leaks nothing (not even its exception).
  /// </summary>
  ITimeoutRun = interface
    ['{9A31D5E8-60C2-4F7B-8E14-B2D0A7C35F66}']
    procedure Complete(const AValue: TValue; AError: TObject);
    function IsCompleted: Boolean;
    function Value: TValue;
    function TakeError: Exception;
    procedure Wake;
    function WaitSignal(ATimeoutMs: Cardinal): TWaitResult;
  end;

  TTimeoutRun = class(TInterfacedObject, ITimeoutRun)
  strict private
    FSignal: TEvent;
    FCompleted: Integer;
    FValue: TValue;
    FError: TObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Complete(const AValue: TValue; AError: TObject);
    function IsCompleted: Boolean;
    function Value: TValue;
    function TakeError: Exception;
    procedure Wake;
    function WaitSignal(ATimeoutMs: Cardinal): TWaitResult;
  end;

constructor TTimeoutRun.Create;
begin
  inherited Create;
  FSignal := TEvent.Create(nil, True, False, '');
end;

destructor TTimeoutRun.Destroy;
begin
  FError.Free;
  FSignal.Free;
  inherited;
end;

procedure TTimeoutRun.Complete(const AValue: TValue; AError: TObject);
begin
  FValue := AValue;
  FError := AError;
  TInterlocked.Exchange(FCompleted, 1);
  FSignal.SetEvent;
end;

function TTimeoutRun.IsCompleted: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCompleted, 0, 0) <> 0;
end;

function TTimeoutRun.Value: TValue;
begin
  Result := FValue;
end;

function TTimeoutRun.TakeError: Exception;
begin
  Result := Exception(FError);
  FError := nil;
end;

procedure TTimeoutRun.Wake;
begin
  FSignal.SetEvent;
end;

function TTimeoutRun.WaitSignal(ATimeoutMs: Cardinal): TWaitResult;
begin
  Result := FSignal.WaitFor(ATimeoutMs);
end;

constructor TTimeoutPolicy.Create(ATimeoutMs: Integer);
begin
  inherited Create;
  if ATimeoutMs < 0 then
    ATimeoutMs := 0;
  FTimeoutMs := ATimeoutMs;
end;

function TTimeoutPolicy.Execute(const Action: TFunc<ICancellationToken, TValue>;
  const AToken: ICancellationToken): TValue;
var
  LSource: TCancellationTokenSource;
  LToken: ICancellationToken;
  LRun: ITimeoutRun;
  LReg: ICancellationRegistration;
  LError: Exception;
begin
  if AToken <> nil then
    AToken.ThrowIfCancellationRequested;

  // The action receives a token that follows the caller's token AND is
  // cancelled by this policy when the time is up.
  LSource := TCancellationTokenSource.CreateLinked([AToken]);
  try
    LToken := LSource.Token;
    LRun := TTimeoutRun.Create;

    TTask.Run(
      procedure
      var
        LValue: TValue;
        LFailure: TObject;
      begin
        LFailure := nil;
        try
          LValue := Action(LToken);
        except
          // Ownership passes to the run object: it frees the exception if
          // the caller already gave up.
          LFailure := AcquireExceptionObject;
        end;
        LRun.Complete(LValue, LFailure);
      end);

    // A cancellation of the caller's token wakes the wait below.
    LReg := LToken.Register(
      procedure
      begin
        LRun.Wake;
      end);
    try
      LRun.WaitSignal(Cardinal(FTimeoutMs));
    finally
      LReg.Unregister;
    end;

    if LRun.IsCompleted then
    begin
      LError := LRun.TakeError;
      if LError <> nil then
        raise LError;
      Exit(LRun.Value);
    end;

    // Time is up (or the caller cancelled): ask the action to stop. It may
    // keep running until it looks at its token.
    LSource.Cancel;
    if (AToken <> nil) and AToken.IsCancellationRequested then
      raise CancelledError
    else
      raise ETimeoutException.Create('Operation timed out.');
  finally
    LSource.Free;
  end;
end;

{ TResiliencePipelineImpl }

constructor TResiliencePipelineImpl.Create;
begin
  inherited Create;
  FPolicies := TList<IResiliencePolicy>.Create;
  FLock := TCriticalSection.Create;
end;

destructor TResiliencePipelineImpl.Destroy;
begin
  FPolicies.Free;
  FLock.Free;
  inherited;
end;

function TResiliencePipelineImpl.Snapshot: TArray<IResiliencePolicy>;
begin
  FLock.Enter;
  try
    Result := FPolicies.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TResiliencePipelineImpl.Add(
  const APolicy: IResiliencePolicy): IResiliencePipeline;
begin
  FLock.Enter;
  try
    FPolicies.Add(APolicy);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

function TResiliencePipelineImpl.AddRetry(AMaxRetries: Integer;
  ABackoffMs: Integer): IResiliencePipeline;
begin
  Result := Add(TRetryPolicy.Create(AMaxRetries, ABackoffMs));
end;

function TResiliencePipelineImpl.AddRetry(
  const AOptions: TRetryOptions): IResiliencePipeline;
begin
  Result := Add(TRetryPolicy.Create(AOptions));
end;

function TResiliencePipelineImpl.AddCircuitBreaker(AFailureThreshold: Integer;
  ABreakDurationMs: Integer): IResiliencePipeline;
begin
  Result := Add(TCircuitBreakerPolicy.Create(AFailureThreshold, ABreakDurationMs));
end;

function TResiliencePipelineImpl.AddCircuitBreaker(AFailureThreshold: Integer;
  ABreakDurationMs: Integer;
  const AOnStateChange: TCircuitStateChanged): IResiliencePipeline;
begin
  Result := Add(TCircuitBreakerPolicy.Create(AFailureThreshold,
    ABreakDurationMs, AOnStateChange));
end;

function TResiliencePipelineImpl.AddFallback(
  const AFallbackFunc: TFunc<TValue>): IResiliencePipeline;
begin
  Result := Add(TFallbackPolicy.Create(AFallbackFunc));
end;

function TResiliencePipelineImpl.AddFallback(
  const AFallbackProc: TProc): IResiliencePipeline;
begin
  Result := Add(TFallbackPolicy.Create(AFallbackProc));
end;

function TResiliencePipelineImpl.AddTimeout(ATimeoutMs: Integer): IResiliencePipeline;
begin
  Result := Add(TTimeoutPolicy.Create(ATimeoutMs));
end;

function TResiliencePipelineImpl.Run(const APolicies: TArray<IResiliencePolicy>;
  AIndex: Integer; const Action: TFunc<ICancellationToken, TValue>;
  const AToken: ICancellationToken): TValue;
begin
  if AIndex >= Length(APolicies) then
    Result := Action(AToken)
  else
    Result := APolicies[AIndex].Execute(
      function(Token: ICancellationToken): TValue
      begin
        Result := Run(APolicies, AIndex + 1, Action, Token);
      end,
      AToken);
end;

function TResiliencePipelineImpl.Execute(
  const Action: TFunc<ICancellationToken, TValue>;
  const AToken: ICancellationToken): TValue;
begin
  // No lock is held while the policies run: callers never wait for each other.
  Result := Run(Snapshot, 0, Action, AToken);
end;

function TResiliencePipelineImpl.Execute(const Action: TFunc<TValue>): TValue;
begin
  Result := Execute(
    function(Token: ICancellationToken): TValue
    begin
      Result := Action();
    end,
    nil);
end;

procedure TResiliencePipelineImpl.Execute(const Action: TProc);
begin
  Execute(
    function(Token: ICancellationToken): TValue
    begin
      Action();
      Result := TValue.Empty;
    end,
    nil);
end;

procedure TResiliencePipelineImpl.Execute(const Action: TProc<ICancellationToken>;
  const AToken: ICancellationToken);
begin
  Execute(
    function(Token: ICancellationToken): TValue
    begin
      Action(Token);
      Result := TValue.Empty;
    end,
    AToken);
end;

{ TResiliencePipeline }

class function TResiliencePipeline.Create: TResiliencePipeline;
begin
  Result.FInstance := TResiliencePipelineImpl.Create;
end;

function TResiliencePipeline.AddRetry(AMaxRetries: Integer; ABackoffMs: Integer): TResiliencePipeline;
begin
  FInstance.AddRetry(AMaxRetries, ABackoffMs);
  Result := Self;
end;

function TResiliencePipeline.AddRetry(const AOptions: TRetryOptions): TResiliencePipeline;
begin
  FInstance.AddRetry(AOptions);
  Result := Self;
end;

function TResiliencePipeline.AddCircuitBreaker(AFailureThreshold: Integer; ABreakDurationMs: Integer): TResiliencePipeline;
begin
  FInstance.AddCircuitBreaker(AFailureThreshold, ABreakDurationMs);
  Result := Self;
end;

function TResiliencePipeline.AddCircuitBreaker(AFailureThreshold: Integer;
  ABreakDurationMs: Integer;
  const AOnStateChange: TCircuitStateChanged): TResiliencePipeline;
begin
  FInstance.AddCircuitBreaker(AFailureThreshold, ABreakDurationMs, AOnStateChange);
  Result := Self;
end;

function TResiliencePipeline.AddFallback<T>(const AFallbackFunc: TFunc<T>): TResiliencePipeline;
begin
  FInstance.AddFallback(
    TFunc<TValue>(
      function: TValue
      begin
        Result := TValue.From<T>(AFallbackFunc());
      end
    )
  );
  Result := Self;
end;

function TResiliencePipeline.AddFallback(const AFallbackFunc: TFunc<TValue>): TResiliencePipeline;
begin
  FInstance.AddFallback(AFallbackFunc);
  Result := Self;
end;

function TResiliencePipeline.AddFallback(const AFallbackProc: TProc): TResiliencePipeline;
begin
  FInstance.AddFallback(AFallbackProc);
  Result := Self;
end;

function TResiliencePipeline.AddTimeout(ATimeoutMs: Integer): TResiliencePipeline;
begin
  FInstance.AddTimeout(ATimeoutMs);
  Result := Self;
end;

function TResiliencePipeline.Execute<T>(const Action: TFunc<T>): T;
var
  LVal: TValue;
begin
  LVal := FInstance.Execute(
    TFunc<TValue>(
      function: TValue
      begin
        Result := TValue.From<T>(Action());
      end
    )
  );
  // An empty value comes from a procedure fallback that swallowed the failure.
  if LVal.IsEmpty then
    Result := Default(T)
  else
    Result := LVal.AsType<T>;
end;

procedure TResiliencePipeline.Execute(const Action: TProc);
begin
  FInstance.Execute(Action);
end;

function TResiliencePipeline.Execute<T>(const Action: TFunc<ICancellationToken, T>;
  const AToken: ICancellationToken): T;
var
  LVal: TValue;
begin
  LVal := FInstance.Execute(
    TFunc<ICancellationToken, TValue>(
      function(Token: ICancellationToken): TValue
      begin
        Result := TValue.From<T>(Action(Token));
      end
    ),
    AToken);
  if LVal.IsEmpty then
    Result := Default(T)
  else
    Result := LVal.AsType<T>;
end;

procedure TResiliencePipeline.Execute(const Action: TProc<ICancellationToken>;
  const AToken: ICancellationToken);
begin
  FInstance.Execute(Action, AToken);
end;

end.
