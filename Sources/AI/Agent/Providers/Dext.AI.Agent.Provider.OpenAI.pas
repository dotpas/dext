{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    ILLMProvider implementation for OpenAI's Chat Completions API.         }
{    POST https://api.openai.com/v1/chat/completions                       }
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
unit Dext.AI.Agent.Provider.OpenAI;

interface

uses
  System.SysUtils,
  System.Classes,
  DextJsonDataObjects,
  Dext.Net.RestClient,
  Dext.AI.Agent.Contracts;

type
  TOpenAIProvider = class(TInterfacedObject, ILLMProvider)
  private
    FApiKey:    string;
    FModel:     string;
    FMaxTokens: Integer;
    FEndpoint:  string;

    function BuildMessageJSON(const AMessage: TLLMMessage): TJsonObject;
    function BuildToolJSON(const ATool: TToolSchema): TJsonObject;
    function MapFinishReason(const AReason: string): TLLMStopReason;
  public
    constructor Create(const AApiKey, AModel: string; AMaxTokens: Integer);

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

{ TOpenAIProvider }

constructor TOpenAIProvider.Create(const AApiKey, AModel: string; AMaxTokens: Integer);
begin
  inherited Create;
  FApiKey    := AApiKey;
  FModel     := AModel;
  FMaxTokens := AMaxTokens;
  FEndpoint  := 'https://api.openai.com/v1/chat/completions';
end;

function TOpenAIProvider.ProviderName: string;
begin
  Result := 'openai';
end;

function TOpenAIProvider.ModelName: string;
begin
  Result := FModel;
end;

function TOpenAIProvider.BuildMessageJSON(const AMessage: TLLMMessage): TJsonObject;
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
      if Length(AMessage.ToolCalls) > 0 then
      begin
        if AMessage.Content <> '' then
          Result.S['content'] := AMessage.Content
        else
          // Objeto nulo explícito (não ausência de chave) — TJsonObject
          // serializa "O[Name] := nil" como "content": null, exigido pela
          // API quando a resposta é só tool_calls, sem texto.
          Result.O['content'] := nil;

        ToolCallsArr := Result.A['tool_calls'];
        for TC in AMessage.ToolCalls do
        begin
          TCObj := ToolCallsArr.AddObject;
          TCObj.S['id'] := TC.Id;
          TCObj.S['type'] := 'function';
          FnObj := TCObj.O['function'];
          FnObj.S['name'] := TC.Name;
          FnObj.S['arguments'] := TC.ArgsJson;
        end;
      end
      else
        Result.S['content'] := AMessage.Content;
    end;
    lrToolResult:
    begin
      Result.S['role'] := 'tool';
      Result.S['tool_call_id'] := AMessage.ToolCallId;
      Result.S['content'] := AMessage.Content;
    end;
  end;
end;

function TOpenAIProvider.BuildToolJSON(const ATool: TToolSchema): TJsonObject;
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

function TOpenAIProvider.BuildRequestBody(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TJsonObject;
var
  MsgsArr, ToolsArr: TJsonArray;
  Msg: TLLMMessage;
  Tool: TToolSchema;
begin
  Result := TJsonObject.Create;
  Result.S['model'] := FModel;
  Result.I['max_tokens'] := FMaxTokens;

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

function TOpenAIProvider.MapFinishReason(const AReason: string): TLLMStopReason;
begin
  if AReason = 'stop' then
    Result := srEndTurn
  else if AReason = 'tool_calls' then
    Result := srToolUse
  else if AReason = 'length' then
    Result := srMaxTokens
  else
    Result := srError;
end;

function TOpenAIProvider.ParseResponse(const ABody: string): TLLMResponse;
var
  Parsed: TJsonBaseObject;
  Root, Choice, Message, Usage, FnObj, TCObj: TJsonObject;
  Choices, ToolCallsArr: TJsonArray;
  FinishReason: string;
  ToolCalls: TArray<TLLMToolCall>;
  I: Integer;
  TC: TLLMToolCall;
begin
  Result := Default(TLLMResponse);

  try
    Parsed := TJsonBaseObject.Parse(ABody);
  except
    on E: Exception do
      raise ELLMProviderError.CreateFmt('OpenAI: resposta inválida: %s', [ABody]);
  end;
  if not (Parsed is TJsonObject) then
  begin
    Parsed.Free;
    raise ELLMProviderError.CreateFmt('OpenAI: resposta inválida: %s', [ABody]);
  end;
  Root := TJsonObject(Parsed);
  try
    if (Root.Types['choices'] <> jdtArray) or (Root.A['choices'].Count = 0) then
      raise ELLMProviderError.CreateFmt('OpenAI: resposta sem choices: %s', [ABody]);
    Choices := Root.A['choices'];

    Choice := Choices.O[0];
    FinishReason := Choice.S['finish_reason'];

    if (Choice.Types['message'] <> jdtObject) or (Choice.O['message'] = nil) then
      raise ELLMProviderError.CreateFmt('OpenAI: choice sem message: %s', [ABody]);
    Message := Choice.O['message'];

    // "content" ausente ou explicitamente null (resposta só com tool_calls) é
    // representado internamente como jdtObject com ponteiro nil pelo parser
    // — TJsonObject.S[] lança EJsonCastException se usado direto num valor
    // desses ("Cannot cast Object into String"), então precisa checar o tipo
    // antes de ler como string.
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
        TC.Id := TCObj.S['id'];
        if TCObj.Types['function'] = jdtObject then
        begin
          FnObj := TCObj.O['function'];
          TC.Name := FnObj.S['name'];
          if FnObj.Types['arguments'] = jdtString then
            TC.ArgsJson := FnObj.S['arguments']
          else
            TC.ArgsJson := '{}';
        end
        else
          TC.ArgsJson := '{}';
        ToolCalls[I] := TC;
      end;
      Result.ToolCalls := ToolCalls;
    end;

    Result.StopReason := MapFinishReason(FinishReason);

    if Root.Types['usage'] = jdtObject then
    begin
      Usage := Root.O['usage'];
      Result.InputTokens  := Usage.I['prompt_tokens'];
      Result.OutputTokens := Usage.I['completion_tokens'];
    end;
  finally
    Root.Free;
  end;
end;

function TOpenAIProvider.Complete(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TLLMResponse;
var
  Body: TJsonObject;
  Response: IRestResponse;
begin
  if FApiKey = '' then
    raise ELLMProviderError.Create('OpenAI: API key não configurada.');

  Body := BuildRequestBody(AMessages, ATools);
  try
    // FEndpoint já é a URL absoluta do endpoint (não um base+path) — passada
    // como BaseUrl com PostJson(payload) de 1 argumento, que faz POST direto
    // nela sem concatenar nada (GetFullUrl só concatena quando o endpoint
    // passado ao PostJson não está vazio).
    Response :=
      TRestClient.Create(FEndpoint)
        .Timeout(120000)
        .Header('Authorization', 'Bearer ' + FApiKey)
        .PostJson(Body.ToJSON)
        .Await;
  finally
    Body.Free;
  end;

  if not Response.IsSuccess then
    raise ELLMProviderError.CreateFmt('OpenAI HTTP %d: %s',
      [Response.StatusCode, Response.ContentString]);

  Result := ParseResponse(Response.ContentString);
end;

end.
