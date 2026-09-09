{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Graph - Orquestração de agentes estilo LangGraph        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    TAgentGraph — o StateGraph do Delphi. Define nós, edges e compila      }
{    em ICompiledAgent.                                                     }
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
unit Dext.AI.Graph.Graph;

interface

uses
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Collections.Queue,
  Dext.AI.Graph.Contracts,
  Dext.AI.Graph.State,
  Dext.AI.Graph.Edge,
  Dext.AI.Agent.Contracts;

type
  // TNodeContext e TNodeHandler agora vivem em Dext.AI.Graph.Contracts
  // (ICompiledAgent.AsNode precisa do tipo, e Contracts não pode depender
  // desta unit). Ficam visíveis aqui via o uses acima.

  TGraphNode = record
    Name:             string;
    Handler:          TNodeHandler;
    RequiresApproval: Boolean;
  end;

  TAgentGraph = class
  private
    FNodes:           TDictionary<string, TGraphNode>;
    FEdges:           TList<TEdge>;
    FEntryPoint:      string;
    FInterruptBefore: TArray<string>;

    procedure ValidateEntryPoint;
    procedure ValidateNodesExist;
    procedure ValidateReachability;
    procedure ValidateNoEdgeFrom(const ASource: string);
    function  FindNode(const AName: string): TGraphNode;
    function  CollectInterrupts: TArray<string>;
    function  IsSpecialNode(const AName: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function AddNode(
      const AName:    string;
      AHandler:       TNodeHandler;
      ARequiresApproval: Boolean = False
    ): TAgentGraph;

    function SetEntryPoint(const ANode: string): TAgentGraph;

    function AddEdge(
      const AFrom, ATo: string
    ): TAgentGraph;

    function AddConditionalEdge(
      const AFrom:    string;
      ACondition:     TEdgeCondition;
      const ARoutes:  TArray<TEdgeRoute>
    ): TAgentGraph;

    function Compile(
      AProvider:        ILLMProvider;
      const AConfig:    TAgentConfig;
      AObserver:        IAgentObserver = nil;
      ACheckpointer:    ICheckpointer  = nil
    ): ICompiledAgent;

    function InterruptBefore(const ANodes: TArray<string>): TAgentGraph;
    function RequireApproval(const ANode: string): TAgentGraph;
  end;

implementation

uses
  Dext.AI.Graph.Compiled,
  Dext.AI.Graph.Checkpointer;

{ TAgentGraph }

constructor TAgentGraph.Create;
begin
  inherited Create;
  FNodes := TDictionary<string, TGraphNode>.Create;
  FEdges := TList<TEdge>.Create;
end;

destructor TAgentGraph.Destroy;
begin
  FEdges.Free;
  FNodes.Free;
  inherited;
end;

function TAgentGraph.IsSpecialNode(const AName: string): Boolean;
begin
  Result := (AName = GRAPH_END) or (AName = GRAPH_START);
end;

function TAgentGraph.FindNode(const AName: string): TGraphNode;
begin
  if not FNodes.TryGetValue(AName, Result) then
    raise ENodeNotFound.CreateFmt('Nó não encontrado: %s', [AName]);
end;

function TAgentGraph.AddNode(
  const AName: string;
  AHandler: TNodeHandler;
  ARequiresApproval: Boolean
): TAgentGraph;
var
  Node: TGraphNode;
begin
  if AName.Trim = '' then
    raise EGraphCompileError.Create('Nome de nó vazio');
  if IsSpecialNode(AName) then
    raise EGraphCompileError.CreateFmt('Nome reservado: %s', [AName]);
  if not Assigned(AHandler) then
    raise EGraphCompileError.CreateFmt('Handler ausente para o nó "%s"', [AName]);
  if FNodes.ContainsKey(AName) then
    raise EGraphCompileError.CreateFmt('Nó duplicado: %s', [AName]);

  Node.Name := AName;
  Node.Handler := AHandler;
  Node.RequiresApproval := ARequiresApproval;
  FNodes.Add(AName, Node);
  Result := Self;
end;

function TAgentGraph.SetEntryPoint(const ANode: string): TAgentGraph;
begin
  FEntryPoint := ANode;
  Result := Self;
end;

procedure TAgentGraph.ValidateNoEdgeFrom(const ASource: string);
var
  Edge: TEdge;
begin
  // ResolveNextNode usa a PRIMEIRA edge cujo SourceNode casa com o nó
  // atual — uma segunda AddEdge/AddConditionalEdge do mesmo nó seria
  // silenciosamente ignorada em runtime em vez de sinalizar o erro de
  // configuração aqui, em tempo de definição do grafo.
  for Edge in FEdges do
    if Edge.SourceNode = ASource then
      raise EGraphCompileError.CreateFmt(
        'Já existe uma edge de saída definida para o nó "%s" - apenas ' +
        'uma AddEdge ou AddConditionalEdge é suportada por nó de origem ' +
        '(o roteamento em runtime usa a primeira que casar, então uma ' +
        'segunda seria ignorada silenciosamente)', [ASource]);
end;

function TAgentGraph.AddEdge(const AFrom, ATo: string): TAgentGraph;
begin
  ValidateNoEdgeFrom(AFrom);
  FEdges.Add(TEdge.Fixed(AFrom, ATo));
  Result := Self;
end;

function TAgentGraph.AddConditionalEdge(
  const AFrom: string;
  ACondition: TEdgeCondition;
  const ARoutes: TArray<TEdgeRoute>
): TAgentGraph;
begin
  if not Assigned(ACondition) then
    raise EGraphCompileError.CreateFmt(
      'Condição ausente na edge condicional de "%s"', [AFrom]);
  ValidateNoEdgeFrom(AFrom);
  FEdges.Add(TEdge.Conditional(AFrom, ACondition, ARoutes));
  Result := Self;
end;

function TAgentGraph.InterruptBefore(const ANodes: TArray<string>): TAgentGraph;
begin
  FInterruptBefore := Copy(ANodes);
  Result := Self;
end;

function TAgentGraph.RequireApproval(const ANode: string): TAgentGraph;
var
  Node: TGraphNode;
begin
  Node := FindNode(ANode);
  Node.RequiresApproval := True;
  FNodes.AddOrSetValue(ANode, Node);
  Result := Self;
end;

procedure TAgentGraph.ValidateEntryPoint;
begin
  if FEntryPoint.Trim = '' then
    raise EGraphCompileError.Create('Ponto de entrada não definido. Use SetEntryPoint.');
  if not FNodes.ContainsKey(FEntryPoint) then
    raise ENodeNotFound.CreateFmt('Ponto de entrada inexistente: %s', [FEntryPoint]);
end;

procedure TAgentGraph.ValidateNodesExist;
var
  Edge: TEdge;
  Route: TEdgeRoute;
begin
  for Edge in FEdges do
  begin
    if not IsSpecialNode(Edge.SourceNode) and not FNodes.ContainsKey(Edge.SourceNode) then
      raise ENodeNotFound.CreateFmt(
        'Edge referencia nó de origem inexistente: %s', [Edge.SourceNode]);

    if Edge.Kind = ekFixed then
    begin
      if not IsSpecialNode(Edge.TargetNode) and not FNodes.ContainsKey(Edge.TargetNode) then
        raise ENodeNotFound.CreateFmt(
          'Edge referencia nó de destino inexistente: %s', [Edge.TargetNode]);
    end
    else
      for Route in Edge.Routes do
        if not IsSpecialNode(Route.TargetNode) and not FNodes.ContainsKey(Route.TargetNode) then
          raise ENodeNotFound.CreateFmt(
            'Rota condicional referencia nó inexistente: %s', [Route.TargetNode]);
  end;
end;

procedure TAgentGraph.ValidateReachability;
var
  Reachable: TDictionary<string, Boolean>;
  Queue: TQueue<string>;
  Current: string;
  Edge: TEdge;
  Route: TEdgeRoute;
  ReachedEnd: Boolean;
  HasOutgoing: Boolean;

  procedure Visit(const ANode: string);
  begin
    if ANode = GRAPH_END then
    begin
      ReachedEnd := True;
      Exit;
    end;
    if IsSpecialNode(ANode) then
      Exit;
    if Reachable.ContainsKey(ANode) then
      Exit;
    Reachable.Add(ANode, True);
    Queue.Enqueue(ANode);
  end;

begin
  if FNodes.Count = 0 then
    raise EGraphCompileError.Create('Grafo sem nós');

  Reachable := TDictionary<string, Boolean>.Create;
  Queue := TQueue<string>.Create;
  try
    ReachedEnd := False;
    Visit(FEntryPoint);

    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      HasOutgoing := False;
      for Edge in FEdges do
      begin
        if Edge.SourceNode <> Current then
          Continue;
        HasOutgoing := True;
        if Edge.Kind = ekFixed then
          Visit(Edge.TargetNode)
        else
          for Route in Edge.Routes do
            Visit(Route.TargetNode);
      end;
      // Um nó sem nenhuma edge de saída termina implicitamente em
      // GRAPH_END em runtime (ResolveNextNode faz esse fallback) — a
      // validação precisa refletir o mesmo comportamento, senão rejeita
      // grafos mínimos válidos de um único nó terminal.
      if not HasOutgoing then
        ReachedEnd := True;
    end;

    if not ReachedEnd then
      raise ENoPathToEnd.Create(
        'Nenhum caminho do ponto de entrada até GRAPH_END');
  finally
    Queue.Free;
    Reachable.Free;
  end;
end;

function TAgentGraph.CollectInterrupts: TArray<string>;
var
  List: TList<string>;
  Pair: TPair<string, TGraphNode>;
  S: string;
begin
  List := TList<string>.Create;
  try
    for S in FInterruptBefore do
      if (S <> '') and (List.IndexOf(S) < 0) then
        List.Add(S);
    for Pair in FNodes do
      if Pair.Value.RequiresApproval and (List.IndexOf(Pair.Key) < 0) then
        List.Add(Pair.Key);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TAgentGraph.Compile(
  AProvider: ILLMProvider;
  const AConfig: TAgentConfig;
  AObserver: IAgentObserver;
  ACheckpointer: ICheckpointer
): ICompiledAgent;
var
  Ctx: TNodeContext;
  MaxIter: Integer;
begin
  if AProvider = nil then
    raise EGraphCompileError.Create('Provider LLM é obrigatório');

  ValidateEntryPoint;
  ValidateNodesExist;
  ValidateReachability;

  Ctx.Provider := AProvider;
  Ctx.Config   := AConfig;
  Ctx.Observer := AObserver;

  if ACheckpointer = nil then
    ACheckpointer := TMemoryCheckpointer.Create;

  MaxIter := AConfig.MaxIterations;
  if MaxIter <= 0 then
    MaxIter := 15;

  Result := TCompiledAgent.Create(
    FNodes, FEdges, FEntryPoint, CollectInterrupts, Ctx, ACheckpointer, MaxIter);
end;

end.
