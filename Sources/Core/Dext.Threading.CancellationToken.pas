{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
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
{  Author:  Cesar Romero                                                    }
{  Created: 2025-12-08                                                      }
{                                                                           }
{  Design notes                                                             }
{                                                                           }
{  The cancellation state (flag, event, callbacks) lives in a reference     }
{  counted object shared by the source and by every token handed out, so a  }
{  token can safely outlive the source that created it. Reading the flag    }
{  is an atomic read. Reset clears the flag AND the event, so polling       }
{  (IsCancellationRequested) and waiting (WaitForCancellation) always       }
{  agree. CancelAfter uses one shared timer thread for the whole process:   }
{  it never costs a thread per call.                                        }
{                                                                           }
{***************************************************************************}
unit Dext.Threading.CancellationToken;

interface

uses
  System.Classes,
  System.Diagnostics,
  System.Generics.Collections,
  System.SyncObjs,
  System.SysUtils;

type
  /// <summary>
  ///   Handle returned by ICancellationToken.Register. Unregister removes the
  ///   callback if it has not run yet. It is idempotent and thread-safe.
  /// </summary>
  ICancellationRegistration = interface
    ['{7C1E5A52-4B7D-4E0F-9D63-2A9C1B8F6E41}']
    procedure Unregister;
  end;

  /// <summary>
  ///   Interface for a cancellation token.
  ///   Represents a token that can be monitored for cancellation.
  ///   Implemented as an interface for automatic memory management via reference counting.
  /// </summary>
  ICancellationToken = interface(IInterface)
    ['{F774136C-B0E3-40A6-A223-9D5C93C39794}']
    /// <summary>
    ///   Indicates whether cancellation has been requested.
    /// </summary>
    function GetIsCancellationRequested: Boolean;
    /// <summary>
    ///   Indicates whether cancellation has been requested.
    /// </summary>
    property IsCancellationRequested: Boolean read GetIsCancellationRequested;

    /// <summary>
    ///   Throws an exception if cancellation has been requested.
    /// </summary>
    /// <exception cref="EOperationCancelled">
    ///   Thrown when cancellation has been requested.
    /// </exception>
    procedure ThrowIfCancellationRequested;

    /// <summary>
    ///   Waits for the cancellation signal.
    ///   Allows a thread to wait passively for the cancellation signal.
    ///   Returns wrSignaled when cancelled, wrTimeout when the time elapsed.
    /// </summary>
    function WaitForCancellation(Timeout: Cardinal = INFINITE): TWaitResult;

    /// <summary>
    ///   Registers a callback that runs once, on the thread that cancels,
    ///   when the token is cancelled. If the token is already cancelled the
    ///   callback runs immediately, before Register returns. Callbacks of one
    ///   token run in reverse order of registration. Keep them short.
    /// </summary>
    function Register(const ACallback: TProc): ICancellationRegistration;
  end;

  /// <summary>
  ///   Shared state behind a source and its tokens. Not meant to be
  ///   implemented outside this unit.
  /// </summary>
  ICancellationState = interface
    ['{2D6B9F34-8A15-4C7E-B0E2-5F3A71C94D08}']
    function IsCancelled: Boolean;
    procedure Cancel;
    procedure Reset;
    function WaitSignaled(ATimeoutMs: Cardinal): TWaitResult;
    function Register(const ACallback: TProc): ICancellationRegistration;
    procedure RemoveCallback(AId: Integer);
    function NextGeneration: Integer;
    function Generation: Integer;
  end;

  TCancellationState = class(TInterfacedObject, ICancellationState)
  strict private
    type
      TCallbackEntry = record
        Id: Integer;
        Callback: TProc;
      end;
  strict private
    FCancelled: Integer;
    FGeneration: Integer;
    FNextId: Integer;
    FEvent: TEvent;
    FLock: TCriticalSection;
    FCallbacks: TList<TCallbackEntry>;
  public
    constructor Create;
    destructor Destroy; override;
    function IsCancelled: Boolean;
    procedure Cancel;
    procedure Reset;
    function WaitSignaled(ATimeoutMs: Cardinal): TWaitResult;
    function Register(const ACallback: TProc): ICancellationRegistration;
    procedure RemoveCallback(AId: Integer);
    function NextGeneration: Integer;
    function Generation: Integer;
  end;

  // Concrete class that implements the ICancellationToken interface.
  TCancellationToken = class(TInterfacedObject, ICancellationToken)
  strict private
    FState: ICancellationState;
  public
    constructor Create(const AState: ICancellationState);

    function GetIsCancellationRequested: Boolean;
    function WaitForCancellation(Timeout: Cardinal): TWaitResult;
    procedure ThrowIfCancellationRequested;
    function Register(const ACallback: TProc): ICancellationRegistration;

    property IsCancellationRequested: Boolean read GetIsCancellationRequested;
  end;

  /// <summary>
  ///   Signals to an ICancellationToken that it should be canceled.
  ///   Destroying the source cancels it. Tokens may outlive the source.
  /// </summary>
  TCancellationTokenSource = class
  strict private
    FState: ICancellationState;
    FToken: ICancellationToken;
    FLinks: TArray<ICancellationRegistration>;
    function GetIsCancellationRequested: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    ///   Creates a source that is cancelled as soon as ANY of the given
    ///   tokens is cancelled (or at once, if one already is). It can also
    ///   be cancelled on its own.
    /// </summary>
    class function CreateLinked(
      const ATokens: array of ICancellationToken): TCancellationTokenSource; static;
    /// <summary>
    ///   Communicates a request for cancellation. Runs the registered
    ///   callbacks; if some raise, all still run and the first exception is
    ///   raised at the end.
    /// </summary>
    procedure Cancel;
    /// <summary>
    ///   Cancels after the given time. A later CancelAfter or a Reset
    ///   replaces the pending one. Zero cancels at once.
    /// </summary>
    procedure CancelAfter(AMilliseconds: Cardinal);
    /// <summary>
    ///   Resets the cancellation state to not-cancelled (flag and event).
    ///   Callbacks that already ran are gone. Must not race with Cancel.
    /// </summary>
    procedure Reset;
    /// <summary>
    ///   Returns the ICancellationToken associated with this source.
    /// </summary>
    function GetToken: ICancellationToken;
    /// <summary>
    ///   Indicates whether cancellation has been requested for this source.
    /// </summary>
    property IsCancellationRequested: Boolean read GetIsCancellationRequested;
    property Token: ICancellationToken read GetToken;
  end;

implementation

type
  TCancellationRegistration = class(TInterfacedObject, ICancellationRegistration)
  strict private
    FState: ICancellationState;
    FId: Integer;
  public
    constructor Create(const AState: ICancellationState; AId: Integer);
    procedure Unregister;
  end;

  TTimerEntry = record
    DueMs: UInt64;
    State: ICancellationState;
    Generation: Integer;
  end;

  /// <summary>One thread serves every pending CancelAfter of the process.</summary>
  TCancellationTimer = class(TThread)
  strict private
    FLock: TCriticalSection;
    FWake: TEvent;
    FEntries: TList<TTimerEntry>;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Schedule(const AState: ICancellationState; ADelayMs: Cardinal;
      AGeneration: Integer);
    procedure Shutdown;
  end;

var
  GTimer: TCancellationTimer = nil;
  GTimerLock: TCriticalSection = nil;

function MonotonicMs: UInt64;
var
  LTicks, LFreq: Int64;
begin
  LTicks := TStopwatch.GetTimeStamp;
  LFreq := TStopwatch.Frequency;
  // Split the division so the product never overflows on a long uptime.
  Result := UInt64((LTicks div LFreq) * 1000 +
    ((LTicks mod LFreq) * 1000) div LFreq);
end;

function Timer: TCancellationTimer;
begin
  GTimerLock.Enter;
  try
    if GTimer = nil then
      GTimer := TCancellationTimer.Create;
    Result := GTimer;
  finally
    GTimerLock.Leave;
  end;
end;

{ TCancellationRegistration }

constructor TCancellationRegistration.Create(const AState: ICancellationState;
  AId: Integer);
begin
  inherited Create;
  FState := AState;
  FId := AId;
end;

procedure TCancellationRegistration.Unregister;
var
  LId: Integer;
begin
  LId := TInterlocked.Exchange(FId, 0);
  if LId <> 0 then
    FState.RemoveCallback(LId);
end;

{ TCancellationState }

constructor TCancellationState.Create;
begin
  inherited Create;
  // Manual reset event, initially non-signaled
  FEvent := TEvent.Create(nil, True, False, '');
  FLock := TCriticalSection.Create;
  FCallbacks := TList<TCallbackEntry>.Create;
end;

destructor TCancellationState.Destroy;
begin
  FCallbacks.Free;
  FLock.Free;
  FEvent.Free;
  inherited;
end;

function TCancellationState.IsCancelled: Boolean;
begin
  // Atomic read with the memory barrier of an interlocked operation.
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) <> 0;
end;

function TCancellationState.Generation: Integer;
begin
  Result := TInterlocked.CompareExchange(FGeneration, 0, 0);
end;

function TCancellationState.NextGeneration: Integer;
begin
  Result := TInterlocked.Increment(FGeneration);
end;

procedure TCancellationState.Cancel;
var
  LCallbacks: TArray<TProc>;
  LError: Exception;
  I: Integer;
begin
  if TInterlocked.CompareExchange(FCancelled, 1, 0) <> 0 then
    Exit;
  // Signal the cancellation event for any waiting threads
  FEvent.SetEvent;

  FLock.Enter;
  try
    SetLength(LCallbacks, FCallbacks.Count);
    for I := 0 to FCallbacks.Count - 1 do
      LCallbacks[I] := FCallbacks[I].Callback;
    FCallbacks.Clear;
  finally
    FLock.Leave;
  end;

  LError := nil;
  for I := High(LCallbacks) downto 0 do
  begin
    try
      LCallbacks[I]();
    except
      if LError = nil then
        LError := Exception(AcquireExceptionObject);
    end;
  end;
  if LError <> nil then
    raise LError;
end;

procedure TCancellationState.Reset;
begin
  // Invalidates any pending CancelAfter, then clears both views of the state.
  TInterlocked.Increment(FGeneration);
  FEvent.ResetEvent;
  TInterlocked.Exchange(FCancelled, 0);
end;

function TCancellationState.WaitSignaled(ATimeoutMs: Cardinal): TWaitResult;
begin
  Result := FEvent.WaitFor(ATimeoutMs);
end;

function TCancellationState.Register(
  const ACallback: TProc): ICancellationRegistration;
var
  LEntry: TCallbackEntry;
  LRunNow: Boolean;
begin
  if not Assigned(ACallback) then
    raise EArgumentNilException.Create('ACallback');
  LRunNow := False;
  FLock.Enter;
  try
    // The flag is set before Cancel collects the list under this same lock,
    // so a callback is either run here or collected there, never both.
    if IsCancelled then
      LRunNow := True
    else
    begin
      Inc(FNextId);
      LEntry.Id := FNextId;
      LEntry.Callback := ACallback;
      FCallbacks.Add(LEntry);
      Result := TCancellationRegistration.Create(Self, LEntry.Id);
    end;
  finally
    FLock.Leave;
  end;
  if LRunNow then
  begin
    ACallback();
    Result := TCancellationRegistration.Create(Self, 0);
  end;
end;

procedure TCancellationState.RemoveCallback(AId: Integer);
var
  I: Integer;
begin
  FLock.Enter;
  try
    for I := 0 to FCallbacks.Count - 1 do
      if FCallbacks[I].Id = AId then
      begin
        FCallbacks.Delete(I);
        Break;
      end;
  finally
    FLock.Leave;
  end;
end;

{ TCancellationToken }

constructor TCancellationToken.Create(const AState: ICancellationState);
begin
  inherited Create;
  FState := AState;
end;

function TCancellationToken.GetIsCancellationRequested: Boolean;
begin
  Result := FState.IsCancelled;
end;

procedure TCancellationToken.ThrowIfCancellationRequested;
begin
  if FState.IsCancelled then
    raise EOperationCancelled.Create('Operation cancelled!');
end;

function TCancellationToken.WaitForCancellation(Timeout: Cardinal): TWaitResult;
begin
  Result := FState.WaitSignaled(Timeout);
end;

function TCancellationToken.Register(
  const ACallback: TProc): ICancellationRegistration;
begin
  Result := FState.Register(ACallback);
end;

{ TCancellationTokenSource }

constructor TCancellationTokenSource.Create;
begin
  inherited Create;
  FState := TCancellationState.Create;
  FToken := TCancellationToken.Create(FState);
end;

destructor TCancellationTokenSource.Destroy;
var
  LLink: ICancellationRegistration;
begin
  for LLink in FLinks do
    LLink.Unregister;
  FLinks := nil;
  try
    FState.Cancel;
  except
    // A destructor must not raise; callback errors are lost on purpose here.
  end;
  // FState stays alive while any token or pending timer still refers to it.
  inherited;
end;

class function TCancellationTokenSource.CreateLinked(
  const ATokens: array of ICancellationToken): TCancellationTokenSource;
var
  LToken: ICancellationToken;
  LChild: ICancellationState;
begin
  Result := TCancellationTokenSource.Create;
  try
    LChild := Result.FState;
    for LToken in ATokens do
    begin
      if LToken = nil then
        Continue;
      // The callback holds the child STATE, never the source object.
      Result.FLinks := Result.FLinks + [LToken.Register(
        procedure
        begin
          LChild.Cancel;
        end)];
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCancellationTokenSource.GetIsCancellationRequested: Boolean;
begin
  Result := FState.IsCancelled;
end;

procedure TCancellationTokenSource.Reset;
begin
  FState.Reset;
end;

procedure TCancellationTokenSource.Cancel;
begin
  FState.Cancel;
end;

procedure TCancellationTokenSource.CancelAfter(AMilliseconds: Cardinal);
var
  LGeneration: Integer;
begin
  LGeneration := FState.NextGeneration;
  if AMilliseconds = 0 then
    FState.Cancel
  else
    Timer.Schedule(FState, AMilliseconds, LGeneration);
end;

function TCancellationTokenSource.GetToken: ICancellationToken;
begin
  // Return the unique instance of the token's interface
  Result := FToken;
end;

{ TCancellationTimer }

constructor TCancellationTimer.Create;
begin
  FLock := TCriticalSection.Create;
  // Auto reset: a signal sent before the wait is not lost.
  FWake := TEvent.Create(nil, False, False, '');
  FEntries := TList<TTimerEntry>.Create;
  inherited Create(False);
end;

destructor TCancellationTimer.Destroy;
begin
  FEntries.Free;
  FWake.Free;
  FLock.Free;
  inherited;
end;

procedure TCancellationTimer.Schedule(const AState: ICancellationState;
  ADelayMs: Cardinal; AGeneration: Integer);
var
  LEntry: TTimerEntry;
  LLow, LHigh, LMid: Integer;
begin
  LEntry.DueMs := MonotonicMs + ADelayMs;
  LEntry.State := AState;
  LEntry.Generation := AGeneration;
  FLock.Enter;
  try
    // Sorted by due time; equal times keep the order of arrival.
    LLow := 0;
    LHigh := FEntries.Count;
    while LLow < LHigh do
    begin
      LMid := (LLow + LHigh) div 2;
      if FEntries[LMid].DueMs <= LEntry.DueMs then
        LLow := LMid + 1
      else
        LHigh := LMid;
    end;
    FEntries.Insert(LLow, LEntry);
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

procedure TCancellationTimer.Execute;
var
  LFired: TArray<TTimerEntry>;
  LCount, I: Integer;
  LNow, LDelta: UInt64;
  LWait: Cardinal;
begin
  while not Terminated do
  begin
    LCount := 0;
    LWait := INFINITE;
    FLock.Enter;
    try
      LNow := MonotonicMs;
      while (FEntries.Count > 0) and (FEntries[0].DueMs <= LNow) do
      begin
        if Length(LFired) = LCount then
          SetLength(LFired, LCount + 8);
        LFired[LCount] := FEntries[0];
        Inc(LCount);
        FEntries.Delete(0);
      end;
      if FEntries.Count > 0 then
      begin
        LDelta := FEntries[0].DueMs - LNow;
        if LDelta > $7FFFFFFF then
          LDelta := $7FFFFFFF;
        LWait := Cardinal(LDelta);
      end;
    finally
      FLock.Leave;
    end;

    for I := 0 to LCount - 1 do
    begin
      if LFired[I].State.Generation = LFired[I].Generation then
      begin
        try
          LFired[I].State.Cancel;
        except
          // The timer thread must survive a failing callback.
        end;
      end;
      LFired[I] := Default(TTimerEntry);
    end;

    // Fired entries may have taken time: look at the list again before waiting.
    if (LCount = 0) and (not Terminated) then
      FWake.WaitFor(LWait);
  end;
end;

procedure TCancellationTimer.Shutdown;
begin
  Terminate;
  FWake.SetEvent;
  WaitFor;
end;

initialization
  GTimerLock := TCriticalSection.Create;

finalization
  if GTimer <> nil then
  begin
    GTimer.Shutdown;
    GTimer.Free;
    GTimer := nil;
  end;
  GTimerLock.Free;

end.
