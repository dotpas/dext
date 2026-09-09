{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    Console implementation of IAgentObserver - prints ReAct loop progress  }
{    (iterations, tool calls, tool results, LLM responses) to stdout.       }
{                                                                           }
{***************************************************************************}
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
{***************************************************************************}
unit Dext.AI.Agent.Observer;

interface

uses
  Dext.AI.Agent.Contracts;

type
  TConsoleObserver = class(TInterfacedObject, IAgentObserver)
  public
    procedure OnIterationStart(AIteration: Integer);
    procedure OnToolCall(const AToolName, AArgsJson: string);
    procedure OnToolResult(const AToolName, AResult: string);
    procedure OnLLMResponse(const AContent: string; AStopReason: TLLMStopReason);
    procedure OnFinished(const AAnswer: string; AIterations: Integer);
  end;

implementation

uses System.SysUtils;

procedure TConsoleObserver.OnIterationStart(AIteration: Integer);
begin
  Writeln;
  Writeln(Format('[ITERAÇÃO %d] -----------------------------', [AIteration]));
end;

procedure TConsoleObserver.OnToolCall(const AToolName, AArgsJson: string);
var
  Preview: string;
begin
  Preview := AArgsJson;
  if Length(Preview) > 80 then Preview := Preview.Substring(0, 80) + '...';
  Writeln(Format('  ? Tool: %s', [AToolName]));
  Writeln(Format('     Args: %s', [Preview]));
end;

procedure TConsoleObserver.OnToolResult(const AToolName, AResult: string);
var
  Preview: string;
begin
  Preview := AResult;
  if Length(Preview) > 120 then Preview := Preview.Substring(0, 120) + '...';
  Writeln(Format('  ? Resultado: %s', [Preview]));
end;

procedure TConsoleObserver.OnLLMResponse(const AContent: string; AStopReason: TLLMStopReason);
begin
  case AStopReason of
    srToolUse: Writeln('  ? LLM solicitou tool call');
    srEndTurn: Writeln('  ?  LLM finalizou resposta');
    srMaxTokens: Writeln('  ?  Limite de tokens atingido');
    srError: Writeln('  ?  Erro no LLM');
  end;
end;

procedure TConsoleObserver.OnFinished(const AAnswer: string; AIterations: Integer);
begin
  Writeln;
  Writeln(Format('-- RESPOSTA FINAL (%d iterações) ----------', [AIterations]));
  Writeln(AAnswer);
  Writeln('------------------------------------------');
end;

end.
