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
{***************************************************************************}
{                                                                           }
{  Unit Tests for the OpenAI/Anthropic/Ollama ILLMProvider implementations. }
{  Covers BuildRequestBody (payload shape) and ParseResponse (fixtures with }
{  real response shapes from each API, including tool_calls/tool_use and   }
{  error paths) — no network involved, both are pure functions.            }
{                                                                           }
{***************************************************************************}
unit TestAgent.Providers;

interface

uses
  System.SysUtils,
  Dext.Testing,
  DextJsonDataObjects,
  Dext.AI.Agent.Contracts,
  Dext.AI.Agent.Provider.OpenAI,
  Dext.AI.Agent.Provider.Anthropic,
  Dext.AI.Agent.Provider.Ollama;

type
  [TestFixture('TOpenAIProvider - BuildRequestBody/ParseResponse')]
  TOpenAIProviderTests = class
  public
    [Test]
    procedure BuildRequestBody_IncludesModelMessagesAndTools;
    [Test]
    procedure BuildRequestBody_AssistantWithToolCalls_ContentIsExplicitNull;
    [Test]
    procedure ParseResponse_PlainTextAnswer_ExtractsContentAndUsage;
    [Test]
    procedure ParseResponse_ToolCalls_ExtractsNameAndArgsJson;
    [Test]
    procedure ParseResponse_InvalidJson_Raises;
    [Test]
    procedure ParseResponse_NoChoices_Raises;
  end;

  [TestFixture('TAnthropicProvider - BuildRequestBody/ParseResponse')]
  TAnthropicProviderTests = class
  public
    [Test]
    procedure BuildRequestBody_SystemPromptGoesToTopLevelSystemField;
    [Test]
    procedure BuildRequestBody_CoalescesConsecutiveToolResultsIntoOneUserMessage;
    [Test]
    procedure ParseResponse_PlainTextAnswer_ExtractsContentAndUsage;
    [Test]
    procedure ParseResponse_ToolUse_ExtractsNameAndArgsJson;
    [Test]
    procedure ParseResponse_NoContent_Raises;
  end;

  [TestFixture('TOllamaProvider - BuildRequestBody/ParseResponse')]
  TOllamaProviderTests = class
  public
    [Test]
    procedure BuildRequestBody_SetsStreamFalse;
    [Test]
    procedure ParseResponse_PlainTextAnswer_ExtractsContent;
    [Test]
    procedure ParseResponse_ToolCalls_ArgumentsIsObjectSerializedBackToJson;
    [Test]
    procedure ParseResponse_NoMessage_Raises;
  end;

implementation

{ TOpenAIProviderTests }

procedure TOpenAIProviderTests.BuildRequestBody_IncludesModelMessagesAndTools;
var
  Provider: TOpenAIProvider;
  Body: TJsonObject;
  Tool: TToolSchema;
  Tools: TArray<TToolSchema>;
begin
  Provider := TOpenAIProvider.Create('sk-test', 'gpt-4o', 4096);
  try
    Tool := Default(TToolSchema);
    Tool.Name := 'search';
    Tool.Description := 'Full text search';
    Tool.InputSchema := '{"type":"object","properties":{"q":{"type":"string"}}}';
    Tools := [Tool];

    Body := Provider.BuildRequestBody(
      [TLLMMessage.System('be helpful'), TLLMMessage.User('hi')], Tools);
    try
      Should(Body.S['model']).Be('gpt-4o');
      Should(Body.I['max_tokens']).Be(4096);
      Should(Body.A['messages'].Count).Be(2);
      Should(Body.A['tools'].Count).Be(1);
      Should(Body.A['tools'].O[0].O['function'].S['name']).Be('search');
    finally
      Body.Free;
    end;
  finally
    Provider.Free;
  end;
end;

procedure TOpenAIProviderTests.BuildRequestBody_AssistantWithToolCalls_ContentIsExplicitNull;
var
  Provider: TOpenAIProvider;
  Body: TJsonObject;
  MsgsArr: TJsonArray;
  AssistantMsg: TJsonObject;
  TC: TLLMToolCall;
begin
  Provider := TOpenAIProvider.Create('sk-test', 'gpt-4o', 4096);
  try
    TC.Id := 'call-1';
    TC.Name := 'search';
    TC.ArgsJson := '{"q":"delphi"}';

    Body := Provider.BuildRequestBody(
      [TLLMMessage.Assistant('', [TC])], nil);
    try
      MsgsArr := Body.A['messages'];
      Should(MsgsArr.Count).Be(1);
      AssistantMsg := MsgsArr.O[0];

      // "content" precisa estar presente como null explícito (não ausente) -
      // a API da OpenAI exige isso quando a resposta é só tool_calls. Como a
      // chave já existe (RequireItem foi chamado por "O['content'] := nil"),
      // o getter não recria o objeto - deve devolver nil de verdade.
      Should(AssistantMsg.Contains('content')).BeTrue;
      Should(Ord(AssistantMsg.Types['content'])).Be(Ord(jdtObject));
      Should(AssistantMsg.O['content']).BeNil;
    finally
      Body.Free;
    end;
  finally
    Provider.Free;
  end;
end;

procedure TOpenAIProviderTests.ParseResponse_PlainTextAnswer_ExtractsContentAndUsage;
const
  BODY =
    '{"choices":[{"message":{"role":"assistant","content":"The answer is 42."},' +
    '"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5}}';
var
  Provider: TOpenAIProvider;
  Resp: TLLMResponse;
begin
  Provider := TOpenAIProvider.Create('sk-test', 'gpt-4o', 4096);
  try
    Resp := Provider.ParseResponse(BODY);
    Should(Resp.Content).Be('The answer is 42.');
    Should(Ord(Resp.StopReason)).Be(Ord(srEndTurn));
    Should(Length(Resp.ToolCalls)).Be(0);
    Should(Resp.InputTokens).Be(10);
    Should(Resp.OutputTokens).Be(5);
  finally
    Provider.Free;
  end;
end;

procedure TOpenAIProviderTests.ParseResponse_ToolCalls_ExtractsNameAndArgsJson;
const
  BODY =
    '{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":' +
    '[{"id":"call_abc","type":"function","function":{"name":"search",' +
    '"arguments":"{\"query\":\"delphi\"}"}}]},"finish_reason":"tool_calls"}]}';
var
  Provider: TOpenAIProvider;
  Resp: TLLMResponse;
begin
  Provider := TOpenAIProvider.Create('sk-test', 'gpt-4o', 4096);
  try
    Resp := Provider.ParseResponse(BODY);
    Should(Ord(Resp.StopReason)).Be(Ord(srToolUse));
    Should(Length(Resp.ToolCalls)).Be(1);
    Should(Resp.ToolCalls[0].Id).Be('call_abc');
    Should(Resp.ToolCalls[0].Name).Be('search');
    Should(Resp.ToolCalls[0].ArgsJson).Be('{"query":"delphi"}');
  finally
    Provider.Free;
  end;
end;

procedure TOpenAIProviderTests.ParseResponse_InvalidJson_Raises;
var
  Provider: TOpenAIProvider;
  Raised: Boolean;
begin
  Provider := TOpenAIProvider.Create('sk-test', 'gpt-4o', 4096);
  try
    Raised := False;
    try
      Provider.ParseResponse('not json at all {{{');
    except
      on E: ELLMProviderError do
        Raised := True;
    end;
    Should(Raised).BeTrue;
  finally
    Provider.Free;
  end;
end;

procedure TOpenAIProviderTests.ParseResponse_NoChoices_Raises;
var
  Provider: TOpenAIProvider;
  Raised: Boolean;
begin
  Provider := TOpenAIProvider.Create('sk-test', 'gpt-4o', 4096);
  try
    Raised := False;
    try
      Provider.ParseResponse('{}');
    except
      on E: ELLMProviderError do
        Raised := True;
    end;
    Should(Raised).BeTrue;
  finally
    Provider.Free;
  end;
end;

{ TAnthropicProviderTests }

procedure TAnthropicProviderTests.BuildRequestBody_SystemPromptGoesToTopLevelSystemField;
var
  Provider: TAnthropicProvider;
  Body: TJsonObject;
begin
  Provider := TAnthropicProvider.Create('sk-ant-test', 'claude-sonnet-4-6', 4096);
  try
    Body := Provider.BuildRequestBody(
      [TLLMMessage.System('be helpful'), TLLMMessage.User('hi')], nil);
    try
      Should(Body.S['system']).Be('be helpful');
      Should(Body.A['messages'].Count).Be(1)
        .Because('a system message não deve virar um item de "messages" - vai no campo "system" separado');
    finally
      Body.Free;
    end;
  finally
    Provider.Free;
  end;
end;

procedure TAnthropicProviderTests.BuildRequestBody_CoalescesConsecutiveToolResultsIntoOneUserMessage;
var
  Provider: TAnthropicProvider;
  Body: TJsonObject;
  MsgsArr: TJsonArray;
  UserMsg: TJsonObject;
begin
  Provider := TAnthropicProvider.Create('sk-ant-test', 'claude-sonnet-4-6', 4096);
  try
    Body := Provider.BuildRequestBody(
      [TLLMMessage.ToolResult('call-1', 'result-1'),
       TLLMMessage.ToolResult('call-2', 'result-2')], nil);
    try
      MsgsArr := Body.A['messages'];
      Should(MsgsArr.Count).Be(1)
        .Because('duas tool_result consecutivas devem virar UMA mensagem user com dois blocos');
      UserMsg := MsgsArr.O[0];
      Should(UserMsg.S['role']).Be('user');
      Should(UserMsg.A['content'].Count).Be(2);
    finally
      Body.Free;
    end;
  finally
    Provider.Free;
  end;
end;

procedure TAnthropicProviderTests.ParseResponse_PlainTextAnswer_ExtractsContentAndUsage;
const
  BODY =
    '{"content":[{"type":"text","text":"The answer is 42."}],' +
    '"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":5}}';
var
  Provider: TAnthropicProvider;
  Resp: TLLMResponse;
begin
  Provider := TAnthropicProvider.Create('sk-ant-test', 'claude-sonnet-4-6', 4096);
  try
    Resp := Provider.ParseResponse(BODY);
    Should(Resp.Content).Be('The answer is 42.');
    Should(Ord(Resp.StopReason)).Be(Ord(srEndTurn));
    Should(Resp.InputTokens).Be(10);
    Should(Resp.OutputTokens).Be(5);
  finally
    Provider.Free;
  end;
end;

procedure TAnthropicProviderTests.ParseResponse_ToolUse_ExtractsNameAndArgsJson;
const
  BODY =
    '{"content":[{"type":"text","text":"Let me search."},' +
    '{"type":"tool_use","id":"toolu_abc","name":"search","input":{"query":"delphi"}}],' +
    '"stop_reason":"tool_use"}';
var
  Provider: TAnthropicProvider;
  Resp: TLLMResponse;
begin
  Provider := TAnthropicProvider.Create('sk-ant-test', 'claude-sonnet-4-6', 4096);
  try
    Resp := Provider.ParseResponse(BODY);
    Should(Resp.Content).Be('Let me search.');
    Should(Ord(Resp.StopReason)).Be(Ord(srToolUse));
    Should(Length(Resp.ToolCalls)).Be(1);
    Should(Resp.ToolCalls[0].Id).Be('toolu_abc');
    Should(Resp.ToolCalls[0].Name).Be('search');
    Should(Resp.ToolCalls[0].ArgsJson).Contain('"query"').Because('input deve ser reserializado como JSON string');
  finally
    Provider.Free;
  end;
end;

procedure TAnthropicProviderTests.ParseResponse_NoContent_Raises;
var
  Provider: TAnthropicProvider;
  Raised: Boolean;
begin
  Provider := TAnthropicProvider.Create('sk-ant-test', 'claude-sonnet-4-6', 4096);
  try
    Raised := False;
    try
      Provider.ParseResponse('{}');
    except
      on E: ELLMProviderError do
        Raised := True;
    end;
    Should(Raised).BeTrue;
  finally
    Provider.Free;
  end;
end;

{ TOllamaProviderTests }

procedure TOllamaProviderTests.BuildRequestBody_SetsStreamFalse;
var
  Provider: TOllamaProvider;
  Body: TJsonObject;
begin
  Provider := TOllamaProvider.Create('http://localhost:11434', 'llama3.2', 4096);
  try
    Body := Provider.BuildRequestBody([TLLMMessage.User('hi')], nil);
    try
      Should(Body.B['stream']).BeFalse
        .Because('o parser de ParseResponse assume resposta não-streaming (um JSON só)');
    finally
      Body.Free;
    end;
  finally
    Provider.Free;
  end;
end;

procedure TOllamaProviderTests.ParseResponse_PlainTextAnswer_ExtractsContent;
const
  BODY =
    '{"message":{"role":"assistant","content":"The answer is 42."},' +
    '"done_reason":"stop"}';
var
  Provider: TOllamaProvider;
  Resp: TLLMResponse;
begin
  Provider := TOllamaProvider.Create('http://localhost:11434', 'llama3.2', 4096);
  try
    Resp := Provider.ParseResponse(BODY);
    Should(Resp.Content).Be('The answer is 42.');
    Should(Ord(Resp.StopReason)).Be(Ord(srEndTurn));
  finally
    Provider.Free;
  end;
end;

procedure TOllamaProviderTests.ParseResponse_ToolCalls_ArgumentsIsObjectSerializedBackToJson;
const
  BODY =
    '{"message":{"role":"assistant","content":"",' +
    '"tool_calls":[{"function":{"name":"search","arguments":{"query":"delphi"}}}]},' +
    '"done_reason":"tool_calls"}';
var
  Provider: TOllamaProvider;
  Resp: TLLMResponse;
begin
  Provider := TOllamaProvider.Create('http://localhost:11434', 'llama3.2', 4096);
  try
    Resp := Provider.ParseResponse(BODY);
    Should(Ord(Resp.StopReason)).Be(Ord(srToolUse));
    Should(Length(Resp.ToolCalls)).Be(1);
    Should(Resp.ToolCalls[0].Id).Be('ollama-call-0');
    Should(Resp.ToolCalls[0].Name).Be('search');
    Should(Resp.ToolCalls[0].ArgsJson).Contain('"query"')
      .Because('Ollama manda "arguments" como objeto JSON de verdade, não string - precisa ser reserializado');
  finally
    Provider.Free;
  end;
end;

procedure TOllamaProviderTests.ParseResponse_NoMessage_Raises;
var
  Provider: TOllamaProvider;
  Raised: Boolean;
begin
  Provider := TOllamaProvider.Create('http://localhost:11434', 'llama3.2', 4096);
  try
    Raised := False;
    try
      Provider.ParseResponse('{}');
    except
      on E: ELLMProviderError do
        Raised := True;
    end;
    Should(Raised).BeTrue;
  finally
    Provider.Free;
  end;
end;

end.
