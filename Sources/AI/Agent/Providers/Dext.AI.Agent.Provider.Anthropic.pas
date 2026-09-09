{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    ILLMProvider implementation for the Anthropic Messages API.            }
{    POST https://api.anthropic.com/v1/messages                            }
{                                                                           }
{    Anthropic requires every tool_result produced in reaction to a single  }
{    assistant turn to be sent back as ONE user message whose content is    }
{    an array of tool_result blocks. The Runner appends one lrToolResult    }
{    TLLMMessage per tool call, so this provider coalesces any run of       }
{    consecutive lrToolResult messages into a single user message when      }
{    building the request body.                                            }
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
unit Dext.AI.Agent.Provider.Anthropic;

interface

uses
  System.SysUtils,
  System.Classes,
  DextJsonDataObjects,
  Dext.Collections,
  Dext.Net.RestClient,
  Dext.AI.Agent.Contracts;

type
  TAnthropicProvider = class(TInterfacedObject, ILLMProvider)
  private
    FApiKey:    string;
    FModel:     string;
    FMaxTokens: Integer;
    FEndpoint:  string;

    function BuildToolJSON(const ATool: TToolSchema): TJsonObject;
    function MapStopReason(const AReason: string): TLLMStopReason;
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

{ TAnthropicProvider }

constructor TAnthropicProvider.Create(const AApiKey, AModel: string; AMaxTokens: Integer);
begin
  inherited Create;
  FApiKey    := AApiKey;
  FModel     := AModel;
  FMaxTokens := AMaxTokens;
  FEndpoint  := 'https://api.anthropic.com/v1/messages';
end;

function TAnthropicProvider.ProviderName: string;
begin
  Result := 'anthropic';
end;

function TAnthropicProvider.ModelName: string;
begin
  Result := FModel;
end;

function TAnthropicProvider.BuildToolJSON(const ATool: TToolSchema): TJsonObject;
var
  Schema: TJsonBaseObject;
begin
  Result := TJsonObject.Create;
  Result.S['name'] := ATool.Name;
  Result.S['description'] := ATool.Description;

  Schema := TJsonBaseObject.Parse(ATool.InputSchema);
  if Schema is TJsonObject then
    Result.O['input_schema'] := TJsonObject(Schema)
  else
  begin
    Schema.Free;
    Result.O['input_schema'] := TJsonObject.Create;
  end;
end;

function TAnthropicProvider.BuildRequestBody(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TJsonObject;
var
  MsgsArr, ToolsArr: TJsonArray;
  ContentArr: TJsonArray;
  MsgObj, ContentBlock: TJsonObject;
  I, J: Integer;
  Msg: TLLMMessage;
  TC: TLLMToolCall;
  Tool: TToolSchema;
  ArgsVal: TJsonBaseObject;
begin
  Result := TJsonObject.Create;
  Result.S['model'] := FModel;
  Result.I['max_tokens'] := FMaxTokens;

  MsgsArr := Result.A['messages'];

  I := 0;
  while I < Length(AMessages) do
  begin
    Msg := AMessages[I];

    case Msg.Role of
      lrSystem:
      begin
        Result.S['system'] := Msg.Content;
        Inc(I);
      end;

      lrUser:
      begin
        MsgObj := MsgsArr.AddObject;
        MsgObj.S['role'] := 'user';
        MsgObj.S['content'] := Msg.Content;
        Inc(I);
      end;

      lrAssistant:
      begin
        MsgObj := MsgsArr.AddObject;
        MsgObj.S['role'] := 'assistant';
        ContentArr := MsgObj.A['content'];

        if Msg.Content <> '' then
        begin
          ContentBlock := ContentArr.AddObject;
          ContentBlock.S['type'] := 'text';
          ContentBlock.S['text'] := Msg.Content;
        end;

        for TC in Msg.ToolCalls do
        begin
          ContentBlock := ContentArr.AddObject;
          ContentBlock.S['type'] := 'tool_use';
          ContentBlock.S['id'] := TC.Id;
          ContentBlock.S['name'] := TC.Name;

          ArgsVal := TJsonBaseObject.Parse(TC.ArgsJson);
          if ArgsVal is TJsonObject then
            ContentBlock.O['input'] := TJsonObject(ArgsVal)
          else
          begin
            ArgsVal.Free;
            ContentBlock.O['input'] := TJsonObject.Create;
          end;
        end;

        Inc(I);
      end;

      lrToolResult:
      begin
        // Coalesce this run of consecutive tool-result messages into a
        // single {"role":"user","content":[tool_result, tool_result, ...]}
        MsgObj := MsgsArr.AddObject;
        MsgObj.S['role'] := 'user';
        ContentArr := MsgObj.A['content'];

        J := I;
        while (J < Length(AMessages)) and (AMessages[J].Role = lrToolResult) do
        begin
          ContentBlock := ContentArr.AddObject;
          ContentBlock.S['type'] := 'tool_result';
          ContentBlock.S['tool_use_id'] := AMessages[J].ToolCallId;
          ContentBlock.S['content'] := AMessages[J].Content;
          Inc(J);
        end;

        I := J;
      end;
    else
      Inc(I);
    end;
  end;

  if Length(ATools) > 0 then
  begin
    ToolsArr := Result.A['tools'];
    for Tool in ATools do
      ToolsArr.Add(BuildToolJSON(Tool));
  end;
end;

function TAnthropicProvider.MapStopReason(const AReason: string): TLLMStopReason;
begin
  if AReason = 'end_turn' then
    Result := srEndTurn
  else if AReason = 'tool_use' then
    Result := srToolUse
  else if AReason = 'max_tokens' then
    Result := srMaxTokens
  else
    Result := srError;
end;

function TAnthropicProvider.ParseResponse(const ABody: string): TLLMResponse;
var
  Parsed: TJsonBaseObject;
  Root, Usage, Block: TJsonObject;
  ContentArr: TJsonArray;
  I: Integer;
  BlockType: string;
  TextBuf: TStringBuilder;
  ToolCalls: TList<TLLMToolCall>;
  TC: TLLMToolCall;
begin
  Result := Default(TLLMResponse);

  try
    Parsed := TJsonBaseObject.Parse(ABody);
  except
    on E: Exception do
      raise ELLMProviderError.CreateFmt('Anthropic: resposta inválida: %s', [ABody]);
  end;
  if not (Parsed is TJsonObject) then
  begin
    Parsed.Free;
    raise ELLMProviderError.CreateFmt('Anthropic: resposta inválida: %s', [ABody]);
  end;
  Root := TJsonObject(Parsed);
  try
    if Root.Types['content'] <> jdtArray then
      raise ELLMProviderError.CreateFmt('Anthropic: resposta sem content: %s', [ABody]);
    ContentArr := Root.A['content'];

    TextBuf   := TStringBuilder.Create;
    ToolCalls := TList<TLLMToolCall>.Create;
    try
      for I := 0 to ContentArr.Count - 1 do
      begin
        Block := ContentArr.O[I];
        BlockType := Block.S['type'];

        if BlockType = 'text' then
          TextBuf.Append(Block.S['text'])
        else if BlockType = 'tool_use' then
        begin
          TC := Default(TLLMToolCall);
          TC.Id   := Block.S['id'];
          TC.Name := Block.S['name'];
          if Block.Types['input'] = jdtObject then
            TC.ArgsJson := Block.O['input'].ToJSON
          else
            TC.ArgsJson := '{}';
          ToolCalls.Add(TC);
        end;
      end;

      Result.Content   := TextBuf.ToString;
      Result.ToolCalls := ToolCalls.ToArray;
    finally
      TextBuf.Free;
      ToolCalls.Free;
    end;

    Result.StopReason := MapStopReason(Root.S['stop_reason']);

    if Root.Types['usage'] = jdtObject then
    begin
      Usage := Root.O['usage'];
      Result.InputTokens  := Usage.I['input_tokens'];
      Result.OutputTokens := Usage.I['output_tokens'];
    end;
  finally
    Root.Free;
  end;
end;

function TAnthropicProvider.Complete(const AMessages: TArray<TLLMMessage>;
  const ATools: TArray<TToolSchema>): TLLMResponse;
var
  Body: TJsonObject;
  Response: IRestResponse;
begin
  if FApiKey = '' then
    raise ELLMProviderError.Create('Anthropic: API key não configurada.');

  Body := BuildRequestBody(AMessages, ATools);
  try
    Response :=
      TRestClient.Create(FEndpoint)
        .Timeout(120000)
        .Header('x-api-key', FApiKey)
        .Header('anthropic-version', '2023-06-01')
        .PostJson(Body.ToJSON)
        .Await;
  finally
    Body.Free;
  end;

  if not Response.IsSuccess then
    raise ELLMProviderError.CreateFmt('Anthropic HTTP %d: %s',
      [Response.StatusCode, Response.ContentString]);

  Result := ParseResponse(Response.ContentString);
end;

end.
