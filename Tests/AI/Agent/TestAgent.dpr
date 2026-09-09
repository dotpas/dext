{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the LICENSE is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{  Unit Tests for Dext.AI.Agent (LLM provider request/response parsing)     }
{                                                                           }
{***************************************************************************}
program TestAgent;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Dext.Utils,
  Dext.Testing,
  TestAgent.Providers in 'TestAgent.Providers.pas';

begin
  SetConsoleCharSet;
  try
    WriteLn;
    WriteLn('=== Dext.AI.Agent Unit Tests ===');
    WriteLn;

    RunTests(
      TTest.Configure
        .Verbose
        .RegisterFixtures([
          TOpenAIProviderTests,
          TAnthropicProviderTests,
          TOllamaProviderTests
        ]));
  except
    on E: Exception do
    begin
      WriteLn('FATAL ERROR: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
