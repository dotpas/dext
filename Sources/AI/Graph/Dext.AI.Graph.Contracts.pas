{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Graph - Orquestração de agentes estilo LangGraph        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    Tipos, constantes e interfaces base do Dext.AI.Graph.                  }
{    Equivalente ao core do LangGraph (StateGraph / CompiledGraph).         }
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
unit Dext.AI.Graph.Contracts;

interface

uses
  System.SysUtils,
  Dext.AI.Agent.Contracts,
  Dext.AI.Graph.State;

const
  GRAPH_END   = '__end__';
  GRAPH_START = '__start__';

type
  TGraphRunStatus = (
    grsRunning,
    grsFinished,
    grsWaitingApproval,
    grsError,
    grsCancelled
  );

  TGraphRunResult = record
    Status:        TGraphRunStatus;
    FinalAnswer:   string;
    ThreadId:      string;
    Iterations:    Integer;
    ErrorMsg:      string;
    PendingNode:   string;
    PendingAction: string;
  end;

  // Contexto de execução compartilhado, injetado em cada nó do grafo.
  TNodeContext = record
    Provider:  ILLMProvider;
    Config:    TAgentConfig;
    Observer:  IAgentObserver;
  end;

  // Handler de nó: recebe o estado atual e devolve o novo estado.
  // Declarado aqui (não em Dext.AI.Graph.Graph) porque ICompiledAgent.AsNode
  // precisa expor esse tipo, e Contracts não pode depender de Graph.
  TNodeHandler = reference to function(
    const AState: TAgentState;
    const ACtx:   TNodeContext
  ): TAgentState;

  ICompiledAgent = interface
    ['{51DC1EAC-E787-40C9-A492-0A921091C6AE}']
    function Run(
      const AInput:    string;
      const AThreadId: string = ''
    ): TGraphRunResult;

    function Resume(const AThreadId: string): TGraphRunResult;
    procedure Cancel(const AThreadId: string);
    function GetState(const AThreadId: string): TAgentState;

    // Adapta este grafo compilado para ser usado como um nó comum de um
    // grafo pai (subgraph-as-node). O estado é passado direto — sem
    // tradução — pois TAgentState já é o mesmo tipo em ambos os grafos.
    // Grafos com RequireApproval/InterruptBefore levantam EGraphCompileError
    // aqui: aprovação humana aninhada não é suportada (v1).
    function AsNode: TNodeHandler;
  end;

  ICheckpointer = interface
    ['{D7F9922F-69E0-442D-84A1-416753A62F8F}']
    procedure Save(const AThreadId: string; const AStateJson: string);
    function  Load(const AThreadId: string): string;
    function  Exists(const AThreadId: string): Boolean;
    procedure Delete(const AThreadId: string);
  end;

  EGraphError          = class(Exception);
  EGraphCompileError   = class(EGraphError);
  EGraphExecutionError = class(EGraphError);
  ENodeNotFound        = class(EGraphError);
  // Levantada quando nenhum caminho do entry point alcança GRAPH_END.
  // Não detecta ciclos em si - um grafo com ciclo mas que também tem uma
  // saída válida para GRAPH_END não dispara isto (ciclos são um padrão
  // normal em StateGraph, ex.: call_llm -> execute_tools -> call_llm).
  ENoPathToEnd         = class(EGraphCompileError);

implementation

end.
