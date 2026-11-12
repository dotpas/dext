unit Dext.Events.Background.Tests;

{***************************************************************************}
{  PublishBackground has no caller to raise to: failures must be observable. }
{***************************************************************************}

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Dext.DI.Core,
  Dext.DI.Interfaces,
  Dext.Events.Interfaces,
  Dext.Events.Bus,
  Dext.Events.Extensions,
  Dext.Testing;

type
  TBgEvent = record
    Id: Integer;
  end;

  TBgFailingHandler = class(TInterfacedObject, IEventHandler<TBgEvent>)
  public
    procedure Handle(const AEvent: TBgEvent);
  end;

  TBgOkHandler = class(TInterfacedObject, IEventHandler<TBgEvent>)
  public
    class var Handled: Integer;
    procedure Handle(const AEvent: TBgEvent);
  end;

  [TestFixture('Event bus: background dispatch')]
  TEventsBackgroundTests = class
  public
    [Test('A failing background handler is reported and counted')]
    procedure Failure_Is_Reported_And_Counted;

    [Test('Every handler still runs when another one fails in the background')]
    procedure Other_Handlers_Still_Run;
  end;

implementation

{ TBgFailingHandler }

procedure TBgFailingHandler.Handle(const AEvent: TBgEvent);
begin
  raise EInvalidOp.Create('handler exploded');
end;

{ TBgOkHandler }

procedure TBgOkHandler.Handle(const AEvent: TBgEvent);
begin
  TInterlocked.Increment(Handled);
end;

function WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Integer): Boolean;
var
  LWatch: TStopwatch;
begin
  LWatch := TStopwatch.StartNew;
  Result := ACondition();
  while (not Result) and (LWatch.ElapsedMilliseconds < ATimeoutMs) do
  begin
    Sleep(10);
    Result := ACondition();
  end;
end;

{ TEventsBackgroundTests }

procedure TEventsBackgroundTests.Failure_Is_Reported_And_Counted;
var
  Services: TDextServices;
  Provider: IServiceProvider;
  Bus: TEventBus;
  BusIntf: IEventBus;
  Event: TBgEvent;
  Reported: Integer;
begin
  Services := TDextServices.New;
  Services.AddEventBus;
  Services.AddEventHandler<TBgEvent, TBgFailingHandler>;
  Provider := Services.BuildServiceProvider;
  BusIntf := Provider.GetServiceAsInterface(TypeInfo(IEventBus)) as IEventBus;
  Bus := BusIntf as TEventBus;

  Reported := 0;
  Bus.OnBackgroundError :=
    procedure(E: Exception)
    begin
      TInterlocked.Increment(Reported);
    end;

  Event.Id := 1;
  Bus.PublishBackground<TBgEvent>(Event);

  Should(WaitUntil(function: Boolean begin Result := Bus.BackgroundFailureCount = 1; end, 5000)).BeTrue;
  Should(WaitUntil(function: Boolean begin Result := Reported = 1; end, 5000)).BeTrue;
  Should(Bus.LastBackgroundFailure).Contain('1 of 1 handler(s) failed');
end;

procedure TEventsBackgroundTests.Other_Handlers_Still_Run;
var
  Services: TDextServices;
  Provider: IServiceProvider;
  Bus: TEventBus;
  BusIntf: IEventBus;
  Event: TBgEvent;
begin
  TBgOkHandler.Handled := 0;
  Services := TDextServices.New;
  Services.AddEventBus;
  Services.AddEventHandler<TBgEvent, TBgFailingHandler>;
  Services.AddEventHandler<TBgEvent, TBgOkHandler>;
  Provider := Services.BuildServiceProvider;
  BusIntf := Provider.GetServiceAsInterface(TypeInfo(IEventBus)) as IEventBus;
  Bus := BusIntf as TEventBus;

  Event.Id := 2;
  Bus.PublishBackground<TBgEvent>(Event);

  Should(WaitUntil(function: Boolean begin Result := Bus.BackgroundFailureCount = 1; end, 5000)).BeTrue;
  Should(TBgOkHandler.Handled).Be(1);
end;

end.
