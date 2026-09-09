{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    Core contracts for the Dext.AI.Agent framework: message/response       }
{    types, the ILLMProvider strategy interface, agent configuration and    }
{    the observer interface used to report ReAct loop progress.             }
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
unit Dext.AI.Agent.Contracts;

interface

uses
  System.SysUtils;

type
  TLLMRole = (lrSystem, lrUser, lrAssistant, lrToolResult);
  TLLMStopReason = (srEndTurn, srToolUse, srMaxTokens, srError);

  TLLMToolCall = record
    Id:       string;
    Name:     string;
    ArgsJson: string;
  end;

  TLLMMessage = record
    Role:       TLLMRole;
    Content:    string;
    ToolCallId: string;
    ToolCalls:  TArray<TLLMToolCall>;
  public
    class function User(const AContent: string): TLLMMessage; static;
    class function System(const AContent: string): TLLMMessage; static;
    class function Assistant(const AContent: string;
      const AToolCalls: TArray<TLLMToolCall> = nil): TLLMMessage; static;
    class function ToolResult(const AToolCallId, AContent: string): TLLMMessage; static;
  end;

  TLLMResponse = record
    Content:      string;
    StopReason:   TLLMStopReason;
    ToolCalls:    TArray<TLLMToolCall>;
    InputTokens:  Integer;
    OutputTokens: Integer;
  end;

  TToolSchema = record
    Name:        string;
    Description: string;
    InputSchema: string; // JSON Schema serializado
  end;

  // Interface �nica � o Strategy
  ILLMProvider = interface
    ['{4D3AA7B5-B79F-4D02-BE3A-817337BD87E0}']
    function Complete(
      const AMessages: TArray<TLLMMessage>;
      const ATools:    TArray<TToolSchema>
    ): TLLMResponse;
    function ProviderName: string;
    function ModelName: string;
  end;

  TAgentConfig = record
    ProviderString: string;  // ex: 'openai:gpt-4o' ou 'anthropic:claude-sonnet-4-6'
    ApiKey:         string;
    BaseUrl:        string;  // para Ollama: 'http://localhost:11434'
    MaxTokens:      Integer;
    MaxIterations:  Integer;
    SystemPrompt:   string;
  public
    class function OpenAI(const AModel: string = 'gpt-4o'): TAgentConfig; static;
    class function Anthropic(const AModel: string = 'claude-sonnet-4-6'): TAgentConfig; static;
    class function Ollama(const AModel: string = 'llama3.2'): TAgentConfig; static;
  end;

  TAgentResult = record
    FinalAnswer: string;
    Iterations:  Integer;
    Success:     Boolean;
    ErrorMsg:    string;
  end;

  IAgentObserver = interface
    ['{4F08B7DA-FFED-4F9C-893B-6C90BD45B08F}']
    procedure OnIterationStart(AIteration: Integer);
    procedure OnToolCall(const AToolName, AArgsJson: string);
    procedure OnToolResult(const AToolName, AResult: string);
    procedure OnLLMResponse(const AContent: string; AStopReason: TLLMStopReason);
    procedure OnFinished(const AAnswer: string; AIterations: Integer);
  end;

  ELLMProviderError = class(Exception);

implementation

const
  DEFAULT_SYSTEM_PROMPT =
    'You are a helpful assistant. Use the available tools to answer accurately. ' +
    'Never invent data � only use what the tools return.';

{ TLLMMessage }

class function TLLMMessage.User(const AContent: string): TLLMMessage;
begin
  Result := Default(TLLMMessage);
  Result.Role    := lrUser;
  Result.Content := AContent;
end;

class function TLLMMessage.System(const AContent: string): TLLMMessage;
begin
  Result := Default(TLLMMessage);
  Result.Role    := lrSystem;
  Result.Content := AContent;
end;

class function TLLMMessage.Assistant(const AContent: string;
  const AToolCalls: TArray<TLLMToolCall>): TLLMMessage;
begin
  Result := Default(TLLMMessage);
  Result.Role      := lrAssistant;
  Result.Content   := AContent;
  Result.ToolCalls := AToolCalls;
end;

class function TLLMMessage.ToolResult(const AToolCallId, AContent: string): TLLMMessage;
begin
  Result := Default(TLLMMessage);
  Result.Role       := lrToolResult;
  Result.Content    := AContent;
  Result.ToolCallId := AToolCallId;
end;

{ TAgentConfig }

class function TAgentConfig.OpenAI(const AModel: string): TAgentConfig;
begin
  Result := Default(TAgentConfig);
  Result.ProviderString := 'openai:' + AModel;
  Result.MaxTokens      := 4096;
  Result.MaxIterations  := 15;
  Result.SystemPrompt   := DEFAULT_SYSTEM_PROMPT;
end;

class function TAgentConfig.Anthropic(const AModel: string): TAgentConfig;
begin
  Result := Default(TAgentConfig);
  Result.ProviderString := 'anthropic:' + AModel;
  Result.MaxTokens      := 4096;
  Result.MaxIterations  := 15;
  Result.SystemPrompt   := DEFAULT_SYSTEM_PROMPT;
end;

class function TAgentConfig.Ollama(const AModel: string): TAgentConfig;
begin
  Result := Default(TAgentConfig);
  Result.ProviderString := 'ollama:' + AModel;
  Result.BaseUrl        := 'http://localhost:11434';
  Result.MaxTokens      := 4096;
  Result.MaxIterations  := 15;
  Result.SystemPrompt   := DEFAULT_SYSTEM_PROMPT;
end;

end.
