unit Dext.Events.Ownership.Tests;

{***************************************************************************}
{  Who frees what: Transient event handlers (owned by the dispatch) and      }
{  pre-created singletons (owned by the container, resolved or not).         }
{***************************************************************************}

interface

uses
  System.SysUtils,
  Dext.DI.Core,
  Dext.DI.Interfaces,
  Dext.Events.Interfaces,
  Dext.Events.Extensions,
  Dext.Testing;

type
  TOwnEvent = record
    Id: Integer;
  end;

  // A Transient handler: the DI default for AddEventHandler.
  TTransientOwnHandler = class(TInterfacedObject, IEventHandler<TOwnEvent>)
  public
    class var Alive: Integer;
    class var Handled: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(const AEvent: TOwnEvent);
  end;

  // A handler the application registers as a singleton instance.
  TSingletonOwnHandler = class(TObject, IEventHandler<TOwnEvent>)
  public
    class var Alive: Integer;
    class var Handled: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Handle(const AEvent: TOwnEvent);
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  end;

  TOwnedByContainer = class
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  [TestFixture]
  TEventsOwnershipTests = class
  public
    [Test]
    procedure Transient_Handler_Is_Freed_After_Each_Publish;
    [Test]
    procedure Singleton_Handler_Instance_Is_Not_Freed_By_The_Bus;
    [Test]
    procedure Singleton_Instance_Never_Resolved_Is_Freed_With_The_Provider;
    [Test]
    procedure Singleton_Instance_Resolved_Is_Freed_Once;
  end;

implementation

{ TTransientOwnHandler }

constructor TTransientOwnHandler.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TTransientOwnHandler.Destroy;
begin
  Dec(Alive);
  inherited;
end;

procedure TTransientOwnHandler.Handle(const AEvent: TOwnEvent);
begin
  Inc(Handled);
end;

{ TSingletonOwnHandler }

constructor TSingletonOwnHandler.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TSingletonOwnHandler.Destroy;
begin
  Dec(Alive);
  inherited;
end;

procedure TSingletonOwnHandler.Handle(const AEvent: TOwnEvent);
begin
  Inc(Handled);
end;

function TSingletonOwnHandler.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TSingletonOwnHandler._AddRef: Integer;
begin
  Result := -1;
end;

function TSingletonOwnHandler._Release: Integer;
begin
  Result := -1;
end;

{ TOwnedByContainer }

constructor TOwnedByContainer.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TOwnedByContainer.Destroy;
begin
  Dec(Alive);
  inherited;
end;

{ TEventsOwnershipTests }

procedure TEventsOwnershipTests.Transient_Handler_Is_Freed_After_Each_Publish;
var
  Services: TDextServices;
  Provider: IServiceProvider;
  Bus: IEventBus;
  Event: TOwnEvent;
  I: Integer;
begin
  TTransientOwnHandler.Alive := 0;
  TTransientOwnHandler.Handled := 0;
  Services := TDextServices.New;
  Services.AddEventBus;
  Services.AddEventHandler<TOwnEvent, TTransientOwnHandler>;
  Provider := Services.BuildServiceProvider;
  Bus := Provider.GetServiceAsInterface(TypeInfo(IEventBus)) as IEventBus;

  Event.Id := 1;
  for I := 1 to 3 do
    TEventBusExtensions.Publish<TOwnEvent>(Bus, Event);

  Should(TTransientOwnHandler.Handled).Be(3);
  Should(TTransientOwnHandler.Alive).Be(0);
end;

procedure TEventsOwnershipTests.Singleton_Handler_Instance_Is_Not_Freed_By_The_Bus;
var
  Services: TDextServices;
  Provider: IServiceProvider;
  Bus: IEventBus;
  Event: TOwnEvent;
begin
  TSingletonOwnHandler.Alive := 0;
  TSingletonOwnHandler.Handled := 0;
  Services := TDextServices.New;
  Services.AddEventBus;
  Services.AddSingletonInstance<TSingletonOwnHandler>(TSingletonOwnHandler.Create);
  Services.AddEventHandler<TOwnEvent, TSingletonOwnHandler>;
  Provider := Services.BuildServiceProvider;
  Bus := Provider.GetServiceAsInterface(TypeInfo(IEventBus)) as IEventBus;

  Event.Id := 1;
  TEventBusExtensions.Publish<TOwnEvent>(Bus, Event);
  TEventBusExtensions.Publish<TOwnEvent>(Bus, Event);

  // The container owns it: still alive after two dispatches.
  Should(TSingletonOwnHandler.Handled).Be(2);
  Should(TSingletonOwnHandler.Alive).Be(1);

  Bus := nil;
  Provider := nil;
  Should(TSingletonOwnHandler.Alive).Be(0);
end;

procedure TEventsOwnershipTests.Singleton_Instance_Never_Resolved_Is_Freed_With_The_Provider;
var
  Services: TDextServices;
  Provider: IServiceProvider;
begin
  TOwnedByContainer.Alive := 0;
  Services := TDextServices.New;
  Services.AddSingletonInstance<TOwnedByContainer>(TOwnedByContainer.Create);
  Provider := Services.BuildServiceProvider;
  Should(TOwnedByContainer.Alive).Be(1);

  Provider := nil;
  Should(TOwnedByContainer.Alive).Be(0);
end;

procedure TEventsOwnershipTests.Singleton_Instance_Resolved_Is_Freed_Once;
var
  Services: TDextServices;
  Provider: IServiceProvider;
  Instance: TObject;
begin
  TOwnedByContainer.Alive := 0;
  Services := TDextServices.New;
  Services.AddSingletonInstance<TOwnedByContainer>(TOwnedByContainer.Create);
  Provider := Services.BuildServiceProvider;
  Instance := Provider.GetService(TServiceType.FromClass(TOwnedByContainer));
  Should(Instance <> nil).BeTrue;

  Provider := nil;
  Should(TOwnedByContainer.Alive).Be(0);
end;

end.
