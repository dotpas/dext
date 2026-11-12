program Dext.Server.HttpSys.Flush.TestsRunner;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dext.Testing,
  Dext.Testing.Runner,
  Dext.Testing.Attributes,
  Dext.Testing.Fluent,
  Dext.Utils,
  Dext.Server.HttpSys.Flush.Tests in 'Dext.Server.HttpSys.Flush.Tests.pas';

begin
  SetConsoleCharSet;
  try
    RunTests(ConfigureTests
      .Verbose
      .RegisterFixtures([
        THttpSysFlushTests
      ]));
  except
    on error: Exception do
    begin
      SafeWriteLn('FATAL ERROR: ' + error.ClassName + ': ' + error.Message);
      ExitCode := 1;
    end;
  end;
end.
