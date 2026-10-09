program DextRestTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dext.Testing,
  Dext.Testing.Runner,
  Dext.Testing.Attributes,
  Dext.Testing.Fluent,
  Dext.Utils,
  Dext.Net.Download in '..\..\Sources\Net\Dext.Net.Download.pas',
  Dext.Net.Engine in '..\..\Sources\Net\Dext.Net.Engine.pas',
  Dext.Net.RestClient in '..\..\Sources\Net\Dext.Net.RestClient.pas',
  Dext.Net.RestRequest in '..\..\Sources\Net\Dext.Net.RestRequest.pas',
  TRestClient_Streaming_Tests in 'TRestClient_Streaming_Tests.pas',
  TRestClient_Certificate_Tests in 'TRestClient_Certificate_Tests.pas',
  TRestClient_IntoBody_Tests in 'TRestClient_IntoBody_Tests.pas',
  TRestClient_Timeout_Tests in 'TRestClient_Timeout_Tests.pas';

begin
  SetConsoleCharSet;
  try
    RunTests(ConfigureTests
      .Verbose
      .RegisterFixtures([
        TDextDownloadGateTests,
        TRestClientStreamingTests,
        TRestClientCertificateTests,
        TRestClientIntoBodyTests,
        TRestClientTimeoutTests
      ]));
  except
    on error: Exception do
    begin
      SafeWriteLn('FATAL ERROR: ' + error.ClassName + ': ' + error.Message);
      ExitCode := 1;
    end;
  end;
end.
