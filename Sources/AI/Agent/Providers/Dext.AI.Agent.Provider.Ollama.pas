{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    ILLMProvider implementation for a local Ollama server (OpenAI-style    }
{    chat endpoint, no API key required).                                   }
{    POST <BaseUrl>/api/chat                                                }
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
unit Dext.AI.Agent.Provider.Ollama;

interface

uses
  System.SysUtils,
  System.Classes,
  DextJsonDataObjects,
  Dext.Net.RestClient,
  Dext.AI.Agent.Contracts;

type
  TOllamaProvider = class(TInterfacedObject, ILLMProvider)
  private
    FBaseUrl:   string;
    FModel:     string;
    FMaxTokens: Integer;

    function BuildMessageJSON(const AMessage: TLLMMessage): TJsonObject;
    function BuildToolJSON(const ATool: TToolSchema): TJsonObject;
    function MapDoneReason(const AReason: string): TLLMStopReason;
  public
    constructor Create(const ABaseUrl, AModel: string; AMaxTokens: Integer);

    function Complete(
      const AMessages: TArray<TLLMMessage>;
      const ATools:    TArray<TToolSchema>
    ): TLLMResponse;
    function ProviderName: string;
    function ModelName: string;

    // Públicos (não usados fora deste provider hoje) para permitir testar o
    // request/response JSON diretamente, sem depender de rede.
    function BuildRequestBody(const AMessages: TArray<TLLMMessage>;
      const ATools: TArray<TToolSchema>): TJsonObject;
    function ParseResponse(const ABody: string): TLLMResponse;
  end;

implementation

{ TOllamaProvider }

constructor TOllamaProvider.Create(const ABaseUrl, AModel: string; AMaxTokens: Integer);
begin
  inherited Create;
  FBaseUrl   := ABaseUrl.TrimRight(['/']);
  FModel     := AModel;
  FMaxTokens := AMaxTokens;
end;

function TOllamaProvider.ProviderName: string;
begin
  Result := 'ollama';
end;

function TOllamaProvider.ModelName: string;
begin
  Result := FModel;
end;

function TOllamaProvider.BuildMessageJSON(const AMessage: TLLMMessage): TJsonObject;
var
  ToolCallsArr: TJsonArray;
  TC: TLLMToolCall;
  TCObj, FnObj: TJsonObject;
begin
  Result := TJsonObject.Create;
  case AMessage.Role of
    lrSystem:
    begin
      Result.S['role'] := 'system';
      Result.S['content'] := AMessage.Content;
    end;
    lrUser:
    begin
      Result.S['role'] := 'user';
      Result.S['content'] := AMessage.Content;
    end;
    lrAssistant:
    begin
      Result.S['role'] := 'assistant';
      Result.S['content'] := AMessage.Content;

      if Length(AMessage.ToolCalls) > 0 then
      begin
        ToolCallsArr := Result.A['tool_calls'];
        for TC in AMessage.ToolCalls do
        begin
          TCObj := ToolCallsArr.AddObject;
          FnObj := TCObj.O['function'];
          FnObj.S['name'] := TC.Name;
          FnObj.S['arguments'] := TC.ArgsJson;
        end;
      end;
    end;
    lrToolResult:
    begin
      Result.S['role'] := 'tool';
      Result.S['tool_call_id'] := AMessage.ToolCallId;
      Result.S['content'] := AMessage.Content;
    end;
  end;
end;

function TOllamaProvider.BuildToolJSON(const ATool: TToolSchema): TJsonObject;
var
  FnObj: TJsonObject;
  Params: TJsonBaseObject;
begin
  Result := TJsonObject.Create;
  Result.S['type'] := 'function';

  FnObj := Result.O['function'];
  FnObj.S['name'] := ATool.Name;
  FnObj.S['description'] := ATool.Description;

  Params := TJsonBaseObject.Parse(ATool.InputSchema);
  if Params is TJsonObject then
    FnObj.O['parameters'] := TJsonObject(Params)
  else
  begin
    Params.Free;
    FnObj.O['parameters'] := TJsonObject.Create;
  end;
end;

function TOllamaProvider.BuildRequestBody(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TJsonObject;
var
  MsgsArr, ToolsArr: TJsonArray;
  Msg: TLLMMessage;
  Tool: TToolSchema;
begin
  Result := TJsonObject.Create;
  Result.S['model'] := FModel;
  Result.B['stream'] := False;

  MsgsArr := Result.A['messages'];
  for Msg in AMessages do
    MsgsArr.Add(BuildMessageJSON(Msg));

  if Length(ATools) > 0 then
  begin
    ToolsArr := Result.A['tools'];
    for Tool in ATools do
      ToolsArr.Add(BuildToolJSON(Tool));
  end;
end;

function TOllamaProvider.MapDoneReason(const AReason: string): TLLMStopReason;
begin
  if AReason = 'stop' then
    Result := srEndTurn
  else if AReason = 'tool_calls' then
    Result := srToolUse
  else
    Result := srError;
end;

function TOllamaProvider.ParseResponse(const ABody: string): TLLMResponse;
var
  Parsed: TJsonBaseObject;
  Root, Message, TCObj, FnObj: TJsonObject;
  ToolCallsArr: TJsonArray;
  ToolCalls: TArray<TLLMToolCall>;
  I: Integer;
  TC: TLLMToolCall;
begin
  Result := Default(TLLMResponse);

  try
    Parsed := TJsonBaseObject.Parse(ABody);
  except
    on E: Exception do
      raise ELLMProviderError.CreateFmt('Ollama: resposta inválida: %s', [ABody]);
  end;
  if not (Parsed is TJsonObject) then
  begin
    Parsed.Free;
    raise ELLMProviderError.CreateFmt('Ollama: resposta inválida: %s', [ABody]);
  end;
  Root := TJsonObject(Parsed);
  try
    if (Root.Types['message'] <> jdtObject) or (Root.O['message'] = nil) then
      raise ELLMProviderError.CreateFmt('Ollama: resposta sem message: %s', [ABody]);
    Message := Root.O['message'];

    // "content" pode vir null em vez de "" — mesmo cuidado do provider
    // OpenAI: o parser representa null como jdtObject(nil), e ler isso via
    // S[] lançaria EJsonCastException.
    if Message.Types['content'] = jdtString then
      Result.Content := Message.S['content']
    else
      Result.Content := '';

    if Message.Types['tool_calls'] = jdtArray then
    begin
      ToolCallsArr := Message.A['tool_calls'];
      SetLength(ToolCalls, ToolCallsArr.Count);
      for I := 0 to ToolCallsArr.Count - 1 do
      begin
        TCObj := ToolCallsArr.O[I];
        TC := Default(TLLMToolCall);
        TC.Id := 'ollama-call-' + IntToStr(I);
        TC.ArgsJson := '{}';

        if TCObj.Types['function'] = jdtObject then
        begin
          FnObj := TCObj.O['function'];
          TC.Name := FnObj.S['name'];
          // Ollama devolve "arguments" como objeto JSON de verdade (não como
          // string escapada, ao contrário da OpenAI) — serializa de volta
          // para string para caber em TLLMToolCall.ArgsJson.
          if FnObj.Types['arguments'] = jdtObject then
            TC.ArgsJson := FnObj.O['arguments'].ToJSON;
        end;

        ToolCalls[I] := TC;
      end;
      Result.ToolCalls := ToolCalls;
    end;

    Result.StopReason := MapDoneReason(Root.S['done_reason']);
    Result.InputTokens  := 0;
    Result.OutputTokens := 0;
  finally
    Root.Free;
  end;
end;

function TOllamaProvider.Complete(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TLLMResponse;
var
  Body: TJsonObject;
  Response: IRestResponse;
begin
  Body := BuildRequestBody(AMessages, ATools);
  try
    // FBaseUrl é só a origem (ex.: http://localhost:11434) — o path
    // '/api/chat' vai no PostJson(endpoint, payload) de 2 argumentos, que
    // concatena via GetFullUrl sem duplicar a barra (FBaseUrl já chega sem
    // '/' final pelo TrimRight do construtor, e '/api/chat' já começa com
    // '/').
    Response :=
      TRestClient.Create(FBaseUrl)
        .Timeout(120000)
        .PostJson('/api/chat', Body.ToJSON)
        .Await;
  finally
    Body.Free;
  end;

  if not Response.IsSuccess then
    raise ELLMProviderError.CreateFmt('Ollama HTTP %d: %s',
      [Response.StatusCode, Response.ContentString]);

  Result := ParseResponse(Response.ContentString);
end;

end.
