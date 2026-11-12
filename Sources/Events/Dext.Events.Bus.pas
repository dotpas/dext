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
{  Created: 2026-03-19                                                      }
{                                                                           }
{  Performance & safety design:                                              }
{                                                                           }
{  [1] REGISTRY (TEventHandlerRegistry)                                     }
{      - TMultiReadExclusiveWriteSynchronizer: write-once at startup,       }
{        read-many at runtime - zero write contention after app start.      }
{      - FBehaviors: TList<T> (concrete Dext type) - direct TRawList        }
{        access; for-in uses the record-based TListEnumerator<T>, avoiding  }
{        ARC overhead per iteration (vs. iterating through IList<T>).       }
{      - FHandlers / FEventBehaviors: IDictionary<Pointer, IList<T>> -     }
{        ARC-managed; no manual Free in destructor.                         }
{                                                                           }
{  [2] DISPATCH SNAPSHOT CACHE (TEventBus.FSnapshotCache)                  }
{      - TMultiReadExclusiveWriteSynchronizer guards the cache.             }
{        Hot-path (post-warm-up) takes a read lock - multiple threads read  }
{        concurrently with no contention. Cold-path (first Publish per       }
{        event type) takes a write lock once.                               }
{      - EventTypeName (ShortString→UnicodeString conversion) is cached in  }
{        the snapshot - zero string allocation on the hot-path.             }
{                                                                           }
{  [3] SINGLETON vs SCOPED BUS (FCreateScope flag)                         }
{      - AddEventBus (Singleton): FCreateScope=True. Publish creates a new  }
{        child scope per call - handlers are isolated from each other.      }
{      - AddScopedEventBus (Scoped): FCreateScope=False. Publish uses the   }
{        injected scoped provider directly - handlers share the request     }
{        unit-of-work (DbContext, Identity, etc.).                          }
{      - PublishBackground creates a fresh scope from FServiceProvider      }
{        (when FCreateScope) before TTask.Run. The IServiceScope is captured }
{        by the task closure, which releases it when the task ends, so it   }
{        lives exactly as long as the background dispatch, whether or not   }
{        the original request scope has ended.                              }
{      - A background dispatch has no caller to raise to. A failure (for    }
{        instance EEventDispatchAggregate) is reported to OnBackgroundError }
{        and counted in BackgroundFailureCount / LastBackgroundFailure.     }
{                                                                           }
{  [4] EXCEPTION AGGREGATION                                                }
{      - Each handler invocation is individually wrapped in try/except.     }
{        All handlers always run - a failing handler does not abort the     }
{        remaining ones.                                                     }
{      - Errors are collected lazily (IList<string> allocated only on       }
{        first failure - zero allocation on the happy path).                }
{      - After all handlers: if any failed, raise EEventDispatchAggregate.  }
{                                                                           }
{  [5] PER-EVENT BEHAVIORS                                                  }
{      - AcquireSnapshot merges global + event-specific behavior factories  }
{        into one TArray at cold-path time. Hot-path sees a single flat     }
{        array with zero branching.                                         }
{                                                                           }
{***************************************************************************}
unit Dext.Events.Bus;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Threading,
  System.SyncObjs,
  System.TypInfo,
  System.Rtti,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.DI.Interfaces,
  Dext.Events.Interfaces;

type
  THandlerFactoryList = IList<TFunc<IServiceProvider, TObject>>;
  THandlerEntryList = IList<THandlerEntry>;

  /// <summary>
  ///   Snapshot for a specific handler.
  ///   Caches the factory and the pre-resolved TRttiMethod ('Handle').
  /// </summary>
  THandlerSnapshot = record
    Factory: TFunc<IServiceProvider, TObject>;
    Method: TRttiMethod;
    Owned: Boolean;
  end;

  /// <summary>
  ///   Frozen dispatch snapshot for one event type.
  ///   BehaviorFactories holds the pre-merged global + per-event behaviors.
  ///   Immutable once built and safe to read concurrently.
  /// </summary>
  TDispatchSnapshot = record
    Handlers: TArray<THandlerSnapshot>;
    BehaviorFactories: TArray<TFunc<IServiceProvider, TObject>>;
    EventTypeName: string;
  end;

  /// <summary>
  ///   Thread-safe registry. Write-once at startup, read-many during dispatch.
  ///   FBehaviors uses the concrete TList<T> type for record-based
  ///   enumeration (TListEnumerator<T> - no ARC per element access).
  /// </summary>
  TEventHandlerRegistry = class(TInterfacedObject, IEventHandlerRegistry)
  private
    FHandlers: IDictionary<Pointer, THandlerEntryList>;
    FEventBehaviors: IDictionary<Pointer, THandlerFactoryList>;
    // Concrete TList<T>: direct TRawList backend, record enumerator on for-in.
    FBehaviors: TList<TFunc<IServiceProvider, TObject>>;
    FLock: TMultiReadExclusiveWriteSynchronizer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure RegisterHandler(AEventType: PTypeInfo; AHandlerClass: TClass;
      const AFactory: TFunc<IServiceProvider, TObject>; AOwned: Boolean);
    procedure RegisterBehavior(
      const AFactory: TFunc<IServiceProvider, TObject>);
    procedure RegisterEventBehavior(AEventType: PTypeInfo;
      const AFactory: TFunc<IServiceProvider, TObject>);
    function GetHandlers(AEventType: PTypeInfo): TArray<THandlerEntry>;
    function GetBehaviorFactories:
      TArray<TFunc<IServiceProvider, TObject>>;
    function GetEventBehaviorFactories(AEventType: PTypeInfo):
      TArray<TFunc<IServiceProvider, TObject>>;
  end;

  /// <summary>
  ///   Lightweight wrapper that binds a specific event type T to an IEventBus
  ///   instance. Created per-injection (transient); delegates synchronously to
  ///   the underlying bus. Thread-safe: all thread-safety is provided by TEventBus.
  ///   Register via Services.AddEventPublisher<TOrderCreatedEvent>.
  /// </summary>
  TEventPublisher<T> = class(TInterfacedObject, IEventPublisher<T>)
  private
    FBus: IEventBus;
  public
    constructor Create(const ABus: IEventBus);
    function Publish(const AEvent: T): TPublishResult;
    procedure PublishBackground(const AEvent: T);
  end;

  /// <summary>
  ///   High-performance event bus. See unit header for full design notes.
  /// </summary>
  TEventBus = class(TInterfacedObject, IEventBus)
    // Interface method resolution: maps IEventBus.Dispatch/DispatchBackground to
    // private implementation methods, avoiding any conflict with the inherited
    // TObject.Dispatch(var Message) virtual method.
    function IEventBus.Dispatch           = BusDispatch;
    procedure IEventBus.DispatchBackground = BusDispatchBackground;
  private
    FServiceProvider: Pointer;
    FRegistry: IEventHandlerRegistry;
    FSnapshotCache: IDictionary<Pointer, TDispatchSnapshot>;
    FSnapshotLock: TMultiReadExclusiveWriteSynchronizer;
    FCreateScope: Boolean;
    FOnBackgroundError: TProc<Exception>;
    FBackgroundFailureCount: Integer;
    FLastBackgroundFailure: string;
    procedure NoteBackgroundFailure(E: Exception);
    function GetLastBackgroundFailure: string;
    function AcquireSnapshot(AEventType: PTypeInfo): TDispatchSnapshot;
    function DoDispatch(AEventType: PTypeInfo; const AEvent: TValue;
      const ASnapshot: TDispatchSnapshot;
      const AScopedProvider: IServiceProvider): TPublishResult;
    // IEventBus implementation (bound via resolution clause above)
    function BusDispatch(AEventType: PTypeInfo;
      const AEvent: TValue): TPublishResult;
    procedure BusDispatchBackground(AEventType: PTypeInfo; const AEvent: TValue);
  public
    constructor Create(const AServiceProvider: IServiceProvider;
      const ARegistry: IEventHandlerRegistry;
      const ACreateScope: Boolean = True);
    destructor Destroy; override;

    // Typed convenience - not on the interface (E2535).
    // For interface-based callers use TEventBusExtensions.Publish<T>.
    function Publish<T>(const AEvent: T): TPublishResult;
    procedure PublishBackground<T>(const AEvent: T);

    /// <summary>
    ///   Called, on the background thread, when a PublishBackground dispatch fails.
    ///   Exceptions raised by the handler itself are contained.
    /// </summary>
    property OnBackgroundError: TProc<Exception>
      read FOnBackgroundError write FOnBackgroundError;
    /// <summary>How many background dispatches failed.</summary>
    property BackgroundFailureCount: Integer read FBackgroundFailureCount;
    /// <summary>Class and message of the most recent background failure.</summary>
    property LastBackgroundFailure: string read GetLastBackgroundFailure;
  end;

implementation
 
uses
  Dext.Core.Reflection;

// Standalone pipeline builder - each call creates a new stack frame so the
// anonymous function captures its OWN copies of ABehavior and ANext.
// Inline vars inside a for-loop share one stack slot in some Delphi versions,
// causing all closures to alias the final iteration value (→ infinite recursion).

function WrapBehavior(const ABehavior: IEventBehavior;
  AEventType: PTypeInfo; const AEvent: TValue;
  const ANext: TEventNextDelegate): TEventNextDelegate;
begin
  Result :=
    procedure
    begin
      ABehavior.Intercept(AEventType, AEvent, ANext);
    end;
end;

{ TEventPublisher<T> }

constructor TEventPublisher<T>.Create(const ABus: IEventBus);
begin
  inherited Create;
  FBus := ABus;
end;

function TEventPublisher<T>.Publish(const AEvent: T): TPublishResult;
var
  V: TValue;
begin
  TValue.Make(@AEvent, TypeInfo(T), V);
  Result := FBus.Dispatch(TypeInfo(T), V);
end;

procedure TEventPublisher<T>.PublishBackground(const AEvent: T);
var
  V: TValue;
begin
  TValue.Make(@AEvent, TypeInfo(T), V);
  FBus.DispatchBackground(TypeInfo(T), V);
end;

{ TEventHandlerRegistry }

constructor TEventHandlerRegistry.Create;
begin
  inherited Create;
  FHandlers      := TCollections.CreateDictionary<Pointer, THandlerEntryList>;
  FEventBehaviors := TCollections.CreateDictionary<Pointer, THandlerFactoryList>;
  FBehaviors     := TList<TFunc<IServiceProvider, TObject>>.Create(False);
  FLock          := TMultiReadExclusiveWriteSynchronizer.Create;
end;

destructor TEventHandlerRegistry.Destroy;
begin
  FLock.Free;
  FBehaviors.Free; // concrete TList - explicit free
  FEventBehaviors := nil;
  FHandlers := nil;
  inherited;
end;

procedure TEventHandlerRegistry.RegisterHandler(AEventType: PTypeInfo;
  AHandlerClass: TClass; const AFactory: TFunc<IServiceProvider, TObject>;
  AOwned: Boolean);
var
  List: THandlerEntryList;
  Entry: THandlerEntry;
begin
  FLock.BeginWrite;
  try
    if not FHandlers.TryGetValue(AEventType, List) then
    begin
      List := TCollections.CreateList<THandlerEntry>;
      FHandlers.Add(AEventType, List);
    end;
    Entry.Factory      := AFactory;
    Entry.HandlerClass := AHandlerClass;
    Entry.Owned        := AOwned;
    List.Add(Entry);
  finally
    FLock.EndWrite;
  end;
end;

procedure TEventHandlerRegistry.RegisterBehavior(
  const AFactory: TFunc<IServiceProvider, TObject>);
begin
  FLock.BeginWrite;
  try
    FBehaviors.Add(AFactory);
  finally
    FLock.EndWrite;
  end;
end;

procedure TEventHandlerRegistry.RegisterEventBehavior(AEventType: PTypeInfo;
  const AFactory: TFunc<IServiceProvider, TObject>);
var
  List: THandlerFactoryList;
begin
  FLock.BeginWrite;
  try
    if not FEventBehaviors.TryGetValue(AEventType, List) then
    begin
      List := TCollections.CreateList<TFunc<IServiceProvider, TObject>>;
      FEventBehaviors.Add(AEventType, List);
    end;
    List.Add(AFactory);
  finally
    FLock.EndWrite;
  end;
end;

function TEventHandlerRegistry.GetHandlers(
  AEventType: PTypeInfo): TArray<THandlerEntry>;
var
  List: THandlerEntryList;
begin
  FLock.BeginRead;
  try
    if FHandlers.TryGetValue(AEventType, List) then
      Result := List.ToArray
    else
      Result := [];
  finally
    FLock.EndRead;
  end;
end;

function TEventHandlerRegistry.GetBehaviorFactories:
  TArray<TFunc<IServiceProvider, TObject>>;
var
  I: Integer;
  F: TFunc<IServiceProvider, TObject>; // record enumerator via concrete TList<T>
begin
  FLock.BeginRead;
  try
    SetLength(Result, FBehaviors.Count);
    I := 0;
    for F in FBehaviors do // uses TListEnumerator<T> - zero ARC overhead
    begin
      Result[I] := F;
      Inc(I);
    end;
  finally
    FLock.EndRead;
  end;
end;

function TEventHandlerRegistry.GetEventBehaviorFactories(
  AEventType: PTypeInfo): TArray<TFunc<IServiceProvider, TObject>>;
var
  List: THandlerFactoryList;
begin
  FLock.BeginRead;
  try
    if FEventBehaviors.TryGetValue(AEventType, List) then
      Result := List.ToArray
    else
      Result := [];
  finally
    FLock.EndRead;
  end;
end;

{ TEventBus }

constructor TEventBus.Create(const AServiceProvider: IServiceProvider;
  const ARegistry: IEventHandlerRegistry; const ACreateScope: Boolean);
begin
  inherited Create;
  FServiceProvider := Pointer(AServiceProvider);
  FRegistry        := ARegistry;
  FCreateScope     := ACreateScope;
  FSnapshotCache   := TCollections.CreateDictionary<Pointer, TDispatchSnapshot>;
  FSnapshotLock    := TMultiReadExclusiveWriteSynchronizer.Create;
end;

destructor TEventBus.Destroy;
begin
  FSnapshotLock.Free;
  FSnapshotCache   := nil;
  FRegistry        := nil;
  FServiceProvider := nil;
  inherited;
end;

function TEventBus.AcquireSnapshot(AEventType: PTypeInfo): TDispatchSnapshot;
var
  GlobalBeh, EventBeh: TArray<TFunc<IServiceProvider, TObject>>;
  RAWHandlers: TArray<THandlerEntry>;
  GlobalLen: Integer;
  I: Integer;
  Method, LMethod: TRttiMethod;
begin
  // Hot-path: read lock - multiple threads can read concurrently post-warm-up.
  FSnapshotLock.BeginRead;
  try
    if FSnapshotCache.TryGetValue(AEventType, Result) then
      Exit;
  finally
    FSnapshotLock.EndRead;
  end;
 
  // Cold-path: first Publish for this event type - build and store snapshot.
  FSnapshotLock.BeginWrite;
  try
    if not FSnapshotCache.TryGetValue(AEventType, Result) then
    begin
      Result.EventTypeName    := string(AEventType.Name);
 
      // Resolve handlers and their 'Handle' methods once.
      RAWHandlers := FRegistry.GetHandlers(AEventType);
      SetLength(Result.Handlers, Length(RAWHandlers));
      for I := 0 to High(RAWHandlers) do
      begin
        Result.Handlers[I].Factory := RAWHandlers[I].Factory;
        Result.Handlers[I].Owned   := RAWHandlers[I].Owned;
 
        // Cache the TRttiMethod. E2555: generic instantiation might hide 'Handle'
        // in virtual method tables, so we use RTTI to find it by name.
        // We use the same persistent FRttiCtx to ensure objects stay valid.
        Method := nil;
        for LMethod in TReflection.Context.GetType(RAWHandlers[I].HandlerClass).GetMethods do
        begin
          if (LMethod.Name = 'Handle') and (Length(LMethod.GetParameters) = 1) then
          begin
            // Resilient matching: compare by pointer OR by name to handle duplicate TypeInfo
            if (LMethod.GetParameters[0].ParamType.Handle = AEventType) or
               (string(LMethod.GetParameters[0].ParamType.Name) = string(AEventType.Name)) then
            begin
              Method := LMethod;
              Break;
            end;
          end;
        end;

        if not Assigned(Method) then
          raise EEventBusException.CreateFmt(
            'Handler class "%s" does not have a "Handle" method matching event "%s"',
            [RAWHandlers[I].HandlerClass.ClassName, string(AEventType.Name)]);
 
        Result.Handlers[I].Method := Method;
      end;
 
      GlobalBeh := FRegistry.GetBehaviorFactories;
      EventBeh  := FRegistry.GetEventBehaviorFactories(AEventType);
      GlobalLen := Length(GlobalBeh);
 
      SetLength(Result.BehaviorFactories, GlobalLen + Length(EventBeh));
      for I := 0 to GlobalLen - 1 do
        Result.BehaviorFactories[I] := GlobalBeh[I];
      for I := 0 to High(EventBeh) do
        Result.BehaviorFactories[GlobalLen + I] := EventBeh[I];
 
      FSnapshotCache.AddOrSetValue(AEventType, Result);
    end;
  finally
    FSnapshotLock.EndWrite;
  end;
end;

function TEventBus.DoDispatch(AEventType: PTypeInfo; const AEvent: TValue;
  const ASnapshot: TDispatchSnapshot;
  const AScopedProvider: IServiceProvider): TPublishResult;
var
  Behaviors: TArray<IEventBehavior>;
  Pipeline: TEventNextDelegate;
  I, J: Integer;
  Errors: IList<string>;
  BehaviorObj: TObject;
  HandlerObj: TObject;
  Method: TRttiMethod;
  LocalEvent: TValue;
  LTargetType: PTypeInfo;
  LData: Pointer;
  LocalHandlerObj: TObject;
  LocalMethod: TRttiMethod;
  LocalEventVal: TValue;
  Params: TArray<TRttiParameter>;
  TargetType: PTypeInfo;
begin
  Result.EventTypeName   := ASnapshot.EventTypeName;
  Result.HandlersInvoked := 0;
  Result.HandlersFailed  := 0;
 
  SetLength(Behaviors, Length(ASnapshot.BehaviorFactories));
  for I := 0 to High(ASnapshot.BehaviorFactories) do
  begin
    BehaviorObj := ASnapshot.BehaviorFactories[I](AScopedProvider);
    if not Supports(BehaviorObj, IEventBehavior, Behaviors[I]) then
      raise EEventBusException.CreateFmt(
        'Behavior "%s" does not implement IEventBehavior', [BehaviorObj.ClassName]);
  end;
 
  for I := 0 to High(ASnapshot.Handlers) do
  begin
    Inc(Result.HandlersInvoked);
    HandlerObj := nil;
    try
      // Resolve handler instance from DI
      HandlerObj := ASnapshot.Handlers[I].Factory(AScopedProvider);
      Method := ASnapshot.Handlers[I].Method;
 
      // Parameter validation & re-boxing (canonical vs synthetic TypeInfo)
      // Safety: pointer mismatch but name match = same record type from different units.
      LocalEvent := AEvent;
      Params := Method.GetParameters;
      if (Length(Params) = 1) and (Params[0].ParamType <> nil) then
      begin
        TargetType := Params[0].ParamType.Handle;
        if (LocalEvent.TypeInfo <> TargetType) then
        begin
          if string(LocalEvent.TypeInfo.Name) <> Params[0].ParamType.Name then
            raise EEventBusException.CreateFmt(
              'Handler "%s" expects "%s" but received "%s"',
              [HandlerObj.ClassName, Params[0].ParamType.Name,
               string(LocalEvent.TypeInfo.Name)]);

          // Re-box into the target TypeInfo to satisfy RTTI Invoke strictness.
          // Directly using the target TypeInfo from the method parameter to ensure absolute compatibility.
          LTargetType := Method.GetParameters[0].ParamType.Handle;
          LData := AEvent.GetReferenceToRawData;
          TValue.Make(LData, LTargetType, LocalEvent);
        end;
      end;
 
      if Length(Behaviors) = 0 then
      begin
        // Fast-path: direct RTTI call - no closure allocation.
        Method.Invoke(HandlerObj, [LocalEvent]);
      end
      else
      begin
        // Pipeline path: build behavior chain inside-out.
        LocalHandlerObj := HandlerObj;
        LocalMethod := Method;
        LocalEventVal := LocalEvent;
        Pipeline :=
          procedure
          begin
            LocalMethod.Invoke(LocalHandlerObj, [LocalEventVal]);
          end;
 
        // Wrap in behaviors - reverse order so first-registered runs outermost.
        for J := High(Behaviors) downto 0 do
          Pipeline := WrapBehavior(Behaviors[J], AEventType, LocalEventVal, Pipeline);
 
        Pipeline();
      end;
 
    except
      on E: Exception do
      begin
        Inc(Result.HandlersFailed);
        if not Assigned(Errors) then
          Errors := TCollections.CreateList<string>;
        Errors.Add(Format('[%s] %s', [E.ClassName, E.Message]));
      end;
    end;

    // A Transient handler belongs to this dispatch: nobody else frees it.
    if ASnapshot.Handlers[I].Owned and Assigned(HandlerObj) then
      HandlerObj.Free;
  end;
 
  if Assigned(Errors) and (Errors.Count > 0) then
    raise EEventDispatchAggregate.Create(
      Format('%d of %d handler(s) failed for event "%s"',
        [Result.HandlersFailed, Result.HandlersInvoked, Result.EventTypeName]),
      Errors.ToArray);
end;

function TEventBus.BusDispatch(AEventType: PTypeInfo;
  const AEvent: TValue): TPublishResult;
var
  Snapshot: TDispatchSnapshot;
  Scope: IServiceScope;
  ScopedProvider: IServiceProvider;
begin
  Snapshot := AcquireSnapshot(AEventType);

  if Length(Snapshot.Handlers) = 0 then
  begin
    Result.EventTypeName   := Snapshot.EventTypeName;
    Result.HandlersInvoked := 0;
    Result.HandlersFailed  := 0;
    Exit;
  end;

  if FCreateScope then
  begin
    Scope          := IServiceProvider(FServiceProvider).CreateScope;
    ScopedProvider := Scope.ServiceProvider;
  end
  else
    ScopedProvider := IServiceProvider(FServiceProvider);

  Result := DoDispatch(AEventType, AEvent, Snapshot, ScopedProvider);
end;

procedure TEventBus.NoteBackgroundFailure(E: Exception);
var
  LHandler: TProc<Exception>;
begin
  TInterlocked.Increment(FBackgroundFailureCount);
  TMonitor.Enter(Self);
  try
    FLastBackgroundFailure := E.ClassName + ': ' + E.Message;
    LHandler := FOnBackgroundError;
  finally
    TMonitor.Exit(Self);
  end;
  if Assigned(LHandler) then
  begin
    try
      LHandler(E);
    except
      // A faulty handler must not escape into the thread pool.
    end;
  end;
end;

function TEventBus.GetLastBackgroundFailure: string;
begin
  TMonitor.Enter(Self);
  try
    Result := FLastBackgroundFailure;
  finally
    TMonitor.Exit(Self);
  end;
end;

procedure TEventBus.BusDispatchBackground(AEventType: PTypeInfo;
  const AEvent: TValue);
var
  EventCopy: TValue;
  BackgroundScope: IServiceScope;
  Snapshot: TDispatchSnapshot;
  ScopedProvider: IServiceProvider;
begin
  Snapshot := AcquireSnapshot(AEventType);

  if FCreateScope then
  begin
    BackgroundScope := IServiceProvider(FServiceProvider).CreateScope;
    ScopedProvider  := BackgroundScope.ServiceProvider;
  end
  else
    ScopedProvider := IServiceProvider(FServiceProvider);

  EventCopy := AEvent;
  TTask.Run(TProc(
    procedure
    begin
      // Background threads need their own scoped provider for thread-safe
      // handler resolution (especially for database context reuse).
      try
        try
          DoDispatch(AEventType, EventCopy, Snapshot, ScopedProvider);
        except
          on E: Exception do
            NoteBackgroundFailure(E);
        end;
      finally
        // Captured by this closure: it is the task that owns the scope, and
        // the scope ends together with the dispatch.
        BackgroundScope := nil;
      end;
    end
  ));
end;

function TEventBus.Publish<T>(const AEvent: T): TPublishResult;
var
  V: TValue;
begin
  // Box to TValue and delegate - keeps the generic method body trivial,
  // avoiding a Delphi 11/12 compiler bug (E2018) with generic methods
  // returning record types on classes with interface method resolution clauses.
  V := TValue.From<T>(AEvent);
  Result := BusDispatch(TypeInfo(T), V);
end;

procedure TEventBus.PublishBackground<T>(const AEvent: T);
var
  V: TValue;
begin
  V := TValue.From<T>(AEvent);
  BusDispatchBackground(TypeInfo(T), V);
end;

end.
