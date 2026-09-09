{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Graph - Orquestração de agentes estilo LangGraph        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    TLLMNode — nó padrão que chama o provider LLM (call_model).            }
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
unit Dext.AI.Graph.Node.LLM;

interface

uses
  Dext.AI.Graph.Contracts,
  Dext.AI.Graph.State,
  Dext.AI.Graph.Graph,
  Dext.AI.Agent.Contracts,
  System.SysUtils;

type
  TLLMNode = class
  private
    FToolSchemas: TArray<TToolSchema>;
  public
    constructor Create(const AToolSchemas: TArray<TToolSchema>);
    function GetAsHandler: TNodeHandler;
    function Execute(
      const AState: TAgentState;
      const ACtx:   TNodeContext
    ): TAgentState;

    property AsHandler: TNodeHandler read GetAsHandler;
  end;

function DefaultShouldContinue(const AState: TAgentState): string;

implementation

function StopReasonToString(AReason: TLLMStopReason): string;
begin
  case AReason of
    srEndTurn:   Result := 'srEndTurn';
    srToolUse:   Result := 'srToolUse';
    srMaxTokens: Result := 'srMaxTokens';
    srError:     Result := 'srError';
  else
    Result := 'unknown';
  end;
end;

{ TLLMNode }

constructor TLLMNode.Create(const AToolSchemas: TArray<TToolSchema>);
begin
  inherited Create;
  FToolSchemas := Copy(AToolSchemas);
end;

function TLLMNode.GetAsHandler: TNodeHandler;
begin
  Result :=
    function(const AState: TAgentState; const ACtx: TNodeContext): TAgentState
    begin
      Result := Self.Execute(AState, ACtx);
    end;
end;

function TLLMNode.Execute(
  const AState: TAgentState;
  const ACtx: TNodeContext
): TAgentState;
var
  Response: TLLMResponse;
  AssistantMsg: TLLMMessage;
  Intermediate: TAgentState;
begin
  if ACtx.Provider = nil then
    raise EGraphExecutionError.Create('Provider LLM ausente no contexto do nó');

  Response := ACtx.Provider.Complete(AState.Messages, FToolSchemas);

  if Assigned(ACtx.Observer) then
    ACtx.Observer.OnLLMResponse(Response.Content, Response.StopReason);

  case Response.StopReason of
    srEndTurn:
    begin
      AssistantMsg := TLLMMessage.Assistant(Response.Content);
      Intermediate := AState.WithMessage(AssistantMsg);
      try
        Result := Intermediate.AsDone(Response.Content);
      finally
        Intermediate.Free;
      end;
    end;
    srToolUse:
    begin
      AssistantMsg := TLLMMessage.Assistant(Response.Content, Response.ToolCalls);
      Intermediate := AState.WithMessage(AssistantMsg);
      try
        Result := Intermediate.WithPendingCalls(Response.ToolCalls);
      finally
        Intermediate.Free;
      end;
    end;
  else
    // srMaxTokens / srError não são um término bem-sucedido do grafo: viravam
    // AsDone(...) e o ExecuteLoop reportava grsFinished, escondendo a falha
    // do chamador. Levantar aqui propaga como grsError via o try/except que
    // o ExecuteLoop já tem em volta de ExecuteNode.
    raise EGraphExecutionError.CreateFmt(
      'LLM não retornou uma resposta utilizável (%s)',
      [StopReasonToString(Response.StopReason)]);
  end;
end;

function DefaultShouldContinue(const AState: TAgentState): string;
begin
  if AState.HasPendingCalls then
    Result := 'execute_tools'
  else
    Result := GRAPH_END;
end;

end.
