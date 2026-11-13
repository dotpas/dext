program Dext.Server.HttpSys.WebSocket.TestsRunner;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dext.Testing,
  Dext.Testing.Runner,
  Dext.Testing.Attributes,
  Dext.Testing.Fluent,
  Dext.Utils,
  Dext.Server.HttpSys.WebSocket.Tests in 'Dext.Server.HttpSys.WebSocket.Tests.pas';

begin
  SetConsoleCharSet;
  try
    RunTests(ConfigureTests
      .Verbose
      .RegisterFixtures([
        THttpSysWebSocketTests
      ]));
  except
    on error: Exception do
    begin
      SafeWriteLn('FATAL ERROR: ' + error.ClassName + ': ' + error.Message);
      ExitCode := 1;
    end;
  end;
end.
