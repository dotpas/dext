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
{***************************************************************************}
unit Dext.Events.Extensions;

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Collections,
  Dext,
  Dext.DI.Interfaces,
  Dext.Core.Activator,
  Dext.Events.Interfaces,
  Dext.Events.Bus,
  Dext.Hosting.BackgroundService;

type
  // --- Internal registration records (required by generic methods below) ------
  // Not part of the public API - do not use in application code.

  THandlerRegistration = record
    EventType: PTypeInfo;
    HandlerClass: TClass;
    Owned: Boolean;  // Transient created per dispatch: the bus frees it
  end;

  TEventBehaviorRegistration = record
    EventType: PTypeInfo;   // nil = global behavior (applies to all events)
    BehaviorClass: TClass;
  end;

  TEventHandlerAccumulator = class
  public
    Handlers: IList<THandlerRegistration>;
    Behaviors: IList<TEventBehaviorRegistration>;
    constructor Create;
  end;

  /// <summary>
  ///   Fluent DI extensions for the Dext Event Bus.
  ///
  ///   Choose the bus lifetime that fits your scenario:
  ///   <code>
  ///     // Singleton: each Publish creates a fresh DI scope.
  ///     // Best for background services, CLI apps.
  ///     Services.AddEventBus;
  ///
  ///     // Scoped: Publish reuses the current DI scope (e.g. HTTP request).
  ///     // Handlers share DbContext, Identity, etc. with the controller.
  ///     // Best for web API controllers.
  ///     Services.AddScopedEventBus;
  ///   </code>
  ///
  ///   Registration:
  ///   <code>
  ///     Services
  ///       .AddEventBus                    // or AddScopedEventBus
  ///       .AddEventHandler<TOrderCreatedEvent, TOrderCreatedHandler>
  ///       .AddEventHandler<TOrderCreatedEvent, TOrderAuditHandler>
  ///       .AddEventBehavior<TEventExceptionBehavior>     // global
  ///       .AddEventBehavior<TEventTimingBehavior>        // global
  ///       .AddEventBehavior<TOrderCreatedEvent, TOrderValidationBehavior> // per-event
  ///   </code>
  /// </summary>
  // Named TEventBusDIExtensions (not TEventBusExtensions) to avoid a naming
  // conflict with TEventBusExtensions in Dext.Events.Interfaces, which holds
  // the static Publish<T>/PublishBackground<T> helpers. Users always call
  // these methods through a TDextServices instance (e.g. Services.AddEventBus)
  // so the type name is never written in application code.
  TEventBusDIExtensions = record helper for TDextServices
    /// <summary>
    ///   Registers IEventBus as a SINGLETON. Each Publish call creates a fresh
    ///   DI scope, isolating handlers from each other and from the caller.
    ///   Call before AddEventHandler / AddEventBehavior.
    /// </summary>
    function AddEventBus: TDextServices;

    /// <summary>
    ///   Registers IEventBus as a SCOPED service. Publish uses the current DI
    ///   scope (injected at construction time) so handlers share the same
    ///   unit-of-work as the code that published the event.
    ///   Ideal for HTTP request handlers where you want handlers to participate
    ///   in the same DbContext transaction.
    ///   Call before AddEventHandler / AddEventBehavior.
    /// </summary>
    function AddScopedEventBus: TDextServices;

    /// <summary>
    ///   Registers THandler as a handler for event type TEvent.
    ///   Multiple handlers per event type are supported - they run in order.
    ///   THandler is resolved from the DI scope per Publish call.
    /// </summary>
    function AddEventHandler<TEvent; THandler: class>: TDextServices;

    /// <summary>
    ///   Registers TBehavior as a GLOBAL pipeline behavior (all event types).
    ///   First registered = outermost in the pipeline.
    ///   TBehavior is resolved from the DI scope per Publish call.
    /// </summary>
    function AddEventBehavior<TBehavior: class>: TDextServices;

    /// <summary>
    ///   Registers TBehavior as a PER-EVENT pipeline behavior for TEvent only.
    ///   Per-event behaviors run INSIDE global behaviors (closer to the handler).
    ///   TBehavior is resolved from the DI scope per Publish call.
    ///
    ///   Note: named AddEventBehaviorFor (not AddEventBehavior) to avoid an
    ///   "Ambiguous overloaded call" error in Delphi 11/12 - the compiler
    ///   cannot disambiguate generic overloads that differ only in type-
    ///   parameter count on record helpers.
    /// </summary>
    function AddEventBehaviorFor<TEvent; TBehavior: class>: TDextServices;

    /// <summary>
    ///   Registers IEventPublisher<T> as a transient service.
    ///   Components that only ever publish one event type can inject the narrow
    ///   IEventPublisher<T> instead of IEventBus - clearer intent and
    ///   easier to mock in unit tests.
    ///
    ///   Usage:
    ///   <code>
    ///     Services
    ///       .AddEventBus
    ///       .AddEventHandler<TOrderCreatedEvent, TOrderCreatedHandler>
    ///       .AddEventPublisher<TOrderCreatedEvent>;
    ///     // Then inject:
    ///     constructor TOrderService.Create(
    ///       const APublisher: IEventPublisher<TOrderCreatedEvent>);
    ///   </code>
    /// </summary>
    function AddEventPublisher<T>: TDextServices;

    /// <summary>
    ///   Registers TEventBusLifecycleService as a singleton IHostedService and
    ///   sets up a IHostedServiceManager to start/stop it automatically.
    ///
    ///   Prerequisites:
    ///   - IEventBus must already be registered (call AddEventBus or
    ///     AddScopedEventBus first).
    ///   - IHostApplicationLifetime must be registered (the web host registers
    ///     it automatically; for console apps use AddHostApplicationLifetime).
    ///
    ///   Note: if your application already calls AddBackgroundServices/Build,
    ///   add TEventBusLifecycleService to that builder and skip this method to
    ///   avoid registering a second IHostedServiceManager.
    /// </summary>
    function AddEventBusLifecycle: TDextServices;
    /// <summary>
    ///  Starts the Background Service builder chain.
    /// </summary>
    function AddBackgroundServices: TBackgroundServiceBuilder;
  private
    function FindAccumulator: TEventHandlerAccumulator;
    function RegisterEventBus(const ACreateScope: Boolean): TDextServices;
  end;

  /// <summary>
  ///   Bridge extensions for TBackgroundServiceBuilder.
  /// </summary>
  THostingEventsExtensions = record helper for TBackgroundServiceBuilder
  public
    /// <summary>
    ///   Enables Host lifecycle events mapping to Event Bus.
    /// </summary>
    function AddLifecycleEvents: TBackgroundServiceBuilder;
  end;

implementation

uses
  Dext.Events.Lifecycle,          // TEventBusLifecycleService
  Dext.Hosting.Events.Bridge;

{ TEventHandlerAccumulator }

constructor TEventHandlerAccumulator.Create;
begin
  inherited Create;
  Handlers := TCollections.CreateList<THandlerRegistration>;
  Behaviors := TCollections.CreateList<TEventBehaviorRegistration>;
end;

// Standalone factory builder - each call creates a new stack frame so the
// anonymous function captures its OWN copy of AClass.  Inline vars inside a
// for-loop share one stack slot in some Delphi versions, causing all closures
// to alias the final iteration value.

function MakeActivatorFactory(AClass: TClass): TFunc<IServiceProvider, TObject>;
begin
  Result :=
    function(P: IServiceProvider): TObject
    begin
      // Try to resolve from DI first (respects singletons/overrides)
      Result := P.GetService(TServiceType.FromClass(AClass));
      if Result = nil then
        Result := TActivator.CreateInstance(P, AClass);
    end;
end;

{ TEventBusDIExtensions }

function TEventBusDIExtensions.FindAccumulator: TEventHandlerAccumulator;
var
  Desc: TServiceDescriptor;
begin
  for Desc in Unwrap.GetDescriptors do
    if Desc.Instance is TEventHandlerAccumulator then
      Exit(TEventHandlerAccumulator(Desc.Instance));

  raise EEventBusException.Create(
    'EventBus not configured. Call Services.AddEventBus() or ' +
    'Services.AddScopedEventBus() before AddEventHandler() / AddEventBehavior().');
end;

function TEventBusDIExtensions.RegisterEventBus(
  const ACreateScope: Boolean): TDextServices;
var
  Accumulator: TEventHandlerAccumulator;
begin
  Accumulator := TEventHandlerAccumulator.Create;

  // Pre-created singleton - DI container owns and frees the accumulator.
  AddSingletonInstance<TEventHandlerAccumulator>(Accumulator);

  // IEventHandlerRegistry: populated lazily on first resolution.
  Collection.AddSingleton(TServiceType.FromInterface(IEventHandlerRegistry), TEventHandlerRegistry,
    function(AProvider: IServiceProvider): TObject
    var
      Acc: TEventHandlerAccumulator;
      Registry: TEventHandlerRegistry;
      HEntry: THandlerRegistration;
      BEntry: TEventBehaviorRegistration;
    begin
      Acc := TDextServices.GetServiceObject<TEventHandlerAccumulator>(AProvider);
      Registry := TEventHandlerRegistry.Create;

      for HEntry in Acc.Handlers do
        Registry.RegisterHandler(HEntry.EventType, HEntry.HandlerClass,
          MakeActivatorFactory(HEntry.HandlerClass), HEntry.Owned);

      for BEntry in Acc.Behaviors do
      begin
        if BEntry.EventType = nil then
          Registry.RegisterBehavior(MakeActivatorFactory(BEntry.BehaviorClass))
        else
          Registry.RegisterEventBehavior(BEntry.EventType,
            MakeActivatorFactory(BEntry.BehaviorClass));
      end;

      Result := Registry;
    end
  );

  // IEventBus: Singleton or Scoped, determined by ACreateScope flag.
  if ACreateScope then
    // Singleton bus
    Collection.AddSingleton(TServiceType.FromInterface(IEventBus), TEventBus,
      function(P: IServiceProvider): TObject
      var
        Registry: IEventHandlerRegistry;
      begin
        Registry := TDextServices.GetRequiredService<IEventHandlerRegistry>(P);
        Result := TEventBus.Create(P, Registry, True);
      end
    )
  else
    // Scoped bus: factory receives the request-scoped provider; FCreateScope=False
    // tells the bus to use it directly instead of creating another child scope.
    Collection.AddScoped(TServiceType.FromInterface(IEventBus), TEventBus,
      function(P: IServiceProvider): TObject
      var
        Registry: IEventHandlerRegistry;
      begin
        Registry := TDextServices.GetRequiredService<IEventHandlerRegistry>(P);
        Result := TEventBus.Create(P, Registry, False);
      end
    );

  Result := Self;
end;

function TEventBusDIExtensions.AddEventBus: TDextServices;
begin
  Result := RegisterEventBus(True);
end;

function TEventBusDIExtensions.AddScopedEventBus: TDextServices;
begin
  Result := RegisterEventBus(False);
end;

function TEventBusDIExtensions.AddEventHandler<TEvent, THandler>: TDextServices;
var
  Acc: TEventHandlerAccumulator;
  Entry: THandlerRegistration;
  Desc: TServiceDescriptor;
  AlreadyRegistered: Boolean;
  TargetServiceType: TServiceType;
begin
  Acc := FindAccumulator;
  Entry.EventType    := TypeInfo(TEvent);
  Entry.HandlerClass := THandler;
  Entry.Owned        := False;

  // Only add a default Transient registration if the handler class is not
  // already registered in DI (e.g., as a Singleton via AddSingletonInstance).
  // Without this check, the Transient descriptor added here would shadow the
  // existing Singleton (FindDescriptor iterates backwards), causing the EventBus
  // to create a new instance instead of using the pre-registered one.
  AlreadyRegistered := False;
  TargetServiceType := TServiceType.FromClass(THandler);
  for Desc in Unwrap.GetDescriptors do
    if Desc.ServiceType = TargetServiceType then
    begin
      AlreadyRegistered := True;
      // The last registration is the one DI resolves. A Transient created from
      // the class is owned by the dispatch: DI does not track it.
      Entry.Owned := (Desc.Lifetime = TServiceLifetime.Transient) and
        (Desc.Instance = nil);
    end;

  if not AlreadyRegistered then
  begin
    Collection.AddTransient(TServiceType.FromClass(THandler), THandler, nil);
    Entry.Owned := True;
  end;

  Acc.Handlers.Add(Entry);
  Result := Self;
end;

function TEventBusDIExtensions.AddEventBehavior<TBehavior>: TDextServices;
var
  Acc: TEventHandlerAccumulator;
  Entry: TEventBehaviorRegistration;
begin
  Acc := FindAccumulator;
  Entry.EventType    := nil; // nil = global
  Entry.BehaviorClass := TBehavior;
  Acc.Behaviors.Add(Entry);
  Collection.AddTransient(TServiceType.FromClass(TBehavior), TBehavior, nil);
  Result := Self;
end;

function TEventBusDIExtensions.AddEventBehaviorFor<TEvent, TBehavior>: TDextServices;
var
  Acc: TEventHandlerAccumulator;
  Entry: TEventBehaviorRegistration;
begin
  Acc := FindAccumulator;
  Entry.EventType    := TypeInfo(TEvent);
  Entry.BehaviorClass := TBehavior;
  Acc.Behaviors.Add(Entry);
  Collection.AddTransient(TServiceType.FromClass(TBehavior), TBehavior, nil);
  Result := Self;
end;

function TEventBusDIExtensions.AddEventPublisher<T>: TDextServices;
begin
  Collection.AddTransient(
    TServiceType.FromInterface(TypeInfo(IEventPublisher<T>)),
    TEventPublisher<T>,
    function(P: IServiceProvider): TObject
    var
      Bus: IEventBus;
    begin
      Bus := TDextServices.GetRequiredService<IEventBus>(P);
      Result := TEventPublisher<T>.Create(Bus);
    end
  );
  Result := Self;
end;

function TEventBusDIExtensions.AddEventBusLifecycle: TDextServices;
begin
  Collection.AddSingleton(TServiceType.FromClass(TEventBusLifecycleService), TEventBusLifecycleService,
    function(P: IServiceProvider): TObject
    begin
      Result := TActivator.CreateInstance(P, TEventBusLifecycleService);
    end
  );

  Collection.AddSingleton(TServiceType.FromInterface(IHostedServiceManager), THostedServiceManager,
    function(P: IServiceProvider): TObject
    var
      Manager: THostedServiceManager;
      ServiceObj: TObject;
      HostedSvc: IHostedService;
    begin
      Manager := THostedServiceManager.Create;
      ServiceObj := TDextServices.GetRequiredServiceObject<TEventBusLifecycleService>(P);
      if Supports(ServiceObj, IHostedService, HostedSvc) then
        Manager.RegisterService(HostedSvc);
      Result := Manager;
    end
  );

  Result := Self;
end;

function TEventBusDIExtensions.AddBackgroundServices: TBackgroundServiceBuilder;
begin
  // Call the base implementation from Dext.Hosting.BackgroundService
  Result := TDextServiceCollectionExtensions.AddBackgroundServices(Self.Collection);
end;

{ THostingEventsExtensions }

function THostingEventsExtensions.AddLifecycleEvents: TBackgroundServiceBuilder;
begin
  // Register the bridge with an explicit factory to avoid Activator 
  // doing implicit interface resolution that causes ARC conflicts
  FServices.AddSingleton(TServiceType.FromClass(THostingLifecycleEventBridge), THostingLifecycleEventBridge,
    function(P: IServiceProvider): TObject
    var
      Bus: IEventBus;
    begin
      Bus := TDextServices.GetService<IEventBus>(P);
      Result := THostingLifecycleEventBridge.Create(Bus);
    end
  );
  
  // Add to the host's background services list
  Result := AddHostedService(THostingLifecycleEventBridge);
end;

end.
