unit Dext.Server.HttpSys.Receives.Tests;

interface

uses
  Dext.Testing.Attributes;

type
  /// <summary>
  ///   OutstandingReceives sets the total number of http.sys receives kept
  ///   posted, independently of the worker count. A worker posts a
  ///   replacement receive as soon as one completes, so fewer receives than
  ///   workers must still let every worker serve a request at the same time
  ///   (the extra workers are there for handlers that block on a database or
  ///   a remote call). Each test starts a real HTTP.sys listener on 127.0.0.1
  ///   whose handler blocks until the test releases it, and counts how many
  ///   requests are inside the handler at once.
  /// </summary>
  [TestFixture('HTTP.sys - outstanding receives independent of the workers')]
  THttpSysReceivesTests = class
  private
    procedure ServeBlocked(AWorkers, AReceives, ARequests,
      AExpectedAtOnce: Integer);
  public
    [Test('OutstandingReceives defaults to 0 (workers x depth) and can be set')]
    procedure TestOptionDefaultAndSetter;
    [Test('Four workers with ONE receive serve four blocked requests at once')]
    procedure TestFourWorkersOneReceive;
    [Test('Two workers with eight receives serve every request, two at a time')]
    procedure TestTwoWorkersEightReceives;
  end;

implementation

uses
  System.Classes,
  System.SyncObjs,
  System.SysUtils,
  System.Net.HttpClient,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Server.Engine.Types;

const
  TestPort = 9221;
  WaitMs = 10000;

{ THttpSysReceivesTests }

procedure THttpSysReceivesTests.TestOptionDefaultAndSetter;
var
  Options: TServerEngineOptions;
begin
  Options := TServerEngineOptions.Default;
  Should(Options.OutstandingReceives).Be(0);
  Options := Options.WithOutstandingReceives(8);
  Should(Options.OutstandingReceives).Be(8);
end;

procedure THttpSysReceivesTests.ServeBlocked(AWorkers, AReceives, ARequests,
  AExpectedAtOnce: Integer);
var
  App: IWebApplication;
  Options: TServerEngineOptions;
  Release, AllIn: TEvent;
  InFlight, MaxInFlight, Ok: Integer;
  Clients: array of TThread;
  I: Integer;
  ReachedExpected: Boolean;
begin
  InFlight := 0;
  MaxInFlight := 0;
  Ok := 0;
  Release := TEvent.Create(nil, True, False, '');
  AllIn := TEvent.Create(nil, True, False, '');
  App := WebApplication;
  try
    App.GetApplicationBuilder.Use(
      procedure(Ctx: IHttpContext; Next: TRequestDelegate)
      var
        Now, Seen: Integer;
      begin
        Now := TInterlocked.Increment(InFlight);
        repeat
          Seen := MaxInFlight;
        until (Now <= Seen) or
          (TInterlocked.CompareExchange(MaxInFlight, Now, Seen) = Seen);
        if Now >= AExpectedAtOnce then
          AllIn.SetEvent;
        Release.WaitFor(WaitMs);
        TInterlocked.Decrement(InFlight);
        Ctx.Response.Write('ok');
      end);
    Options := TServerEngineOptions.Default.WithBindAddress('127.0.0.1')
      .WithIoThreads(AWorkers).WithOutstandingReceiveDepth(1)
      .WithOutstandingReceives(AReceives);
    App.UseNativeServer(Options);
    App.Start(TestPort);
    try
      SetLength(Clients, ARequests);
      for I := 0 to ARequests - 1 do
      begin
        Clients[I] := TThread.CreateAnonymousThread(
          procedure
          var
            Client: THTTPClient;
          begin
            Client := THTTPClient.Create;
            try
              Client.ConnectionTimeout := WaitMs;
              Client.ResponseTimeout := WaitMs * 3;
              if Client.Get('http://127.0.0.1:' + IntToStr(TestPort) +
                '/blocked').StatusCode = 200 then
                TInterlocked.Increment(Ok);
            finally
              Client.Free;
            end;
          end);
        Clients[I].FreeOnTerminate := False;
        Clients[I].Start;
      end;
      // Every worker busy at once before anyone is released.
      ReachedExpected := AllIn.WaitFor(WaitMs) = wrSignaled;
      Release.SetEvent;
      for I := 0 to ARequests - 1 do
      begin
        Clients[I].WaitFor;
        Clients[I].Free;
      end;
      Should(ReachedExpected).BeTrue;
      Should(MaxInFlight).Be(AExpectedAtOnce);
      Should(Ok).Be(ARequests);
    finally
      App.Stop;
    end;
  finally
    App := nil;
    AllIn.Free;
    Release.Free;
  end;
end;

procedure THttpSysReceivesTests.TestFourWorkersOneReceive;
begin
  ServeBlocked(4, 1, 4, 4);
end;

procedure THttpSysReceivesTests.TestTwoWorkersEightReceives;
begin
  ServeBlocked(2, 8, 6, 2);
end;

end.
