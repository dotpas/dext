program Dext.Web.UnitTests;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Dext.MM,
  System.SysUtils,
  Dext.Testing.Runner,
  Dext.Testing.Attributes,
  Dext.Testing.Fluent,
  Dext.Testing,
  Dext.Utils,
  Dext.Web.DataApi.Resolver.Tests in 'Dext.Web.DataApi.Resolver.Tests.pas',
  Dext.Web.DataApi.Tests in 'Dext.Web.DataApi.Tests.pas',
  Dext.Web.Json.Tests in 'Dext.Web.Json.Tests.pas',
  Dext.Web.Binding.Tests in 'Dext.Web.Binding.Tests.pas',
  Dext.Web.RecordBinding.Tests in 'Dext.Web.RecordBinding.Tests.pas',
  Dext.Web.Features.Tests in 'Dext.Web.Features.Tests.pas',
  Dext.Web.DataApi.Utils.Tests in 'Dext.Web.DataApi.Utils.Tests.pas',
  Dext.Web.Hosting.Tests in 'Dext.Web.Hosting.Tests.pas',
  Dext.Web.Lifecycle.Tests in 'Dext.Web.Lifecycle.Tests.pas',
  Dext.Web.Htmx.Tests in 'Dext.Web.Htmx.Tests.pas',
  Dext.Web.EntityDataSetStore.Tests in 'Dext.Web.EntityDataSetStore.Tests.pas',
  Dext.Logging.Sinks.APM.Tests in 'Dext.Logging.Sinks.APM.Tests.pas',
  Dext.WebSocket.Tests in 'Dext.WebSocket.Tests.pas',
  Dext.Server.HttpSys.SslBinding.Tests in 'Dext.Server.HttpSys.SslBinding.Tests.pas',
  Dext.Web.PathBase.Tests in 'Dext.Web.PathBase.Tests.pas',
  Dext.Web.StaticFiles.Security.Tests in 'Dext.Web.StaticFiles.Security.Tests.pas',
  Dext.Server.HttpSys.Address.Tests in 'Dext.Server.HttpSys.Address.Tests.pas',
  Dext.Server.HttpSys.ResponseReuse.Tests in 'Dext.Server.HttpSys.ResponseReuse.Tests.pas',
  Dext.Server.Native.Request.Tests in 'Dext.Server.Native.Request.Tests.pas',
  Dext.Server.HttpSys.LargeBody.Tests in 'Dext.Server.HttpSys.LargeBody.Tests.pas',
  Dext.Web.HandlerExceptions.Tests in 'Dext.Web.HandlerExceptions.Tests.pas',
  Dext.Web.Mocks in '..\Common\Dext.Web.Mocks.pas',
  Test_Dext.Http2.Connection in 'Test_Dext.Http2.Connection.pas',
  Test_Dext.Http2.Framing in 'Test_Dext.Http2.Framing.pas',
  Test_Dext.Http2.Hpack in 'Test_Dext.Http2.Hpack.pas',
  Test_Dext.Http2.Stream in 'Test_Dext.Http2.Stream.pas',
  Dext.Testing.WebApplicationFactory in '..\..\Sources\Testing\Dext.Testing.WebApplicationFactory.pas',
  Dext.Testing.WebApplicationFactory.Tests in '..\Testing\Dext.Testing.WebApplicationFactory.Tests.pas',
  Dext.Web.Validation.Tests in 'Dext.Web.Validation.Tests.pas',
  Dext.Web.S68.Tests in 'Dext.Web.S68.Tests.pas',
  Dext.Web.NewFeatures.Tests in 'Dext.Web.NewFeatures.Tests.pas';

begin
  SetConsoleCharSet();
  try
    SafeWriteLn;
    SafeWriteLn('🧪 Dext Web Unit Tests');
    SafeWriteLn('======================');
    SafeWriteLn;

    RunTests(TTest
      .Configure
      .Verbose
      .RegisterFixtures([
        TWebBindingTests,
        TRecordBindingTests,
        TEntityIdResolverTests,
        TJsonNullableTests,
        TWebFeaturesTests,
        TDataApiNamingTests,
        TWebHostingTests,
        TWebApplicationLifecycleTests,
        TDataApiConventionTests,
        TDataApiSerializationTests,
        THtmxResponseTests,
        TEntityDataSetStoreTests,
        TEntityDataSetStoreTypesTests,
        TAPMSinksTests,
        TWebSocketTests,
        THttpSysSslBindingTests,
        TPathBaseTests,
        TStaticFilesSecurityTests,
        THttpSysAddressTests,
        THttpSysResponseReuseTests,
        TNativeRequestTests,
        THttpSysLargeBodyTests,
        THandlerExceptionsTests,
        TDextNewFeaturesTests,
        TWebApplicationFactoryTests,
        TWebValidationTests,
        TS68FrameworkGapTests,
        // HTTP/2 and HPACK Tests
        THpackStaticTableTests,
        THpackDynTableTests,
        THpackHuffmanTests,
        THpackDecoderTests,
        THpackEncoderTests,
        TFrameReadTests,
        TFrameSettingsTests,
        TFramePingTests,
        TFrameControlTests,
        TFrameDataHeadersTests,
        TStreamStateTests,
        TStreamAccumulationTests,
        TStreamFlowControlTests,
        TStreamMapTests,
        TConnectionPrefaceTests,
        TConnectionSettingsTests,
        TConnectionPingTests,
        TConnectionRequestTests
      ]));
  except
    on E: Exception do
    begin
      SafeWriteLn('FATAL ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
