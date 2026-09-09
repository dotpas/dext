{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Graph - Orquestração de agentes estilo LangGraph        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    TAgentState — estado imutável que flui pelo grafo.                     }
{    Cada With* retorna uma NOVA instância. Nenhum método muta Self.        }
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
unit Dext.AI.Graph.State;

interface

uses
  System.SysUtils,
  DextJsonDataObjects,
  Dext.Collections.Dict,
  Dext.AI.Agent.Contracts;

type
  TAgentState = class
  private
    FMessages:     TArray<TLLMMessage>;
    FPendingCalls: TArray<TLLMToolCall>;
    FCurrentNode:  string;
    FIteration:    Integer;
    FIsDone:       Boolean;
    FFinalAnswer:  string;
    FMetadata:     TDictionary<string, string>;
    FThreadId:     string;

    constructor CreateInternal(
      const AMessages:     TArray<TLLMMessage>;
      const APendingCalls: TArray<TLLMToolCall>;
      const ACurrentNode:  string;
      AIteration:          Integer;
      AIsDone:             Boolean;
      const AFinalAnswer:  string;
      AMetadata:           TDictionary<string, string>;
      const AThreadId:     string
    );
    function CloneMetadata: TDictionary<string, string>;
    function CloneMessages: TArray<TLLMMessage>;
    function ClonePendingCalls: TArray<TLLMToolCall>;
  public
    constructor Create(const AThreadId: string = '');
    destructor Destroy; override;

    function WithMessage(const AMsg: TLLMMessage): TAgentState;
    function WithMessages(const AMsgs: TArray<TLLMMessage>): TAgentState;
    function WithPendingCalls(const ACalls: TArray<TLLMToolCall>): TAgentState;
    function ClearPendingCalls: TAgentState;
    function WithCurrentNode(const ANode: string): TAgentState;
    function WithIteration(AIteration: Integer): TAgentState;
    function NextIteration: TAgentState;
    function AsDone(const AAnswer: string): TAgentState;
    function WithMeta(const AKey, AValue: string): TAgentState;
    function RestartAt(const ANode: string): TAgentState;
    function ClearDone: TAgentState;

    function ToJson: string;
    class function FromJson(const AJson: string): TAgentState; static;

    property Messages:     TArray<TLLMMessage>  read FMessages;
    property PendingCalls: TArray<TLLMToolCall> read FPendingCalls;
    property CurrentNode:  string               read FCurrentNode;
    property Iteration:    Integer              read FIteration;
    property IsDone:       Boolean              read FIsDone;
    property FinalAnswer:  string               read FFinalAnswer;
    property ThreadId:     string               read FThreadId;

    function HasPendingCalls: Boolean;
    function LastMessage: TLLMMessage;
    function GetMeta(const AKey: string; const ADefault: string = ''): string;
  end;

implementation

function RoleToName(ARole: TLLMRole): string;
begin
  case ARole of
    lrSystem:     Result := 'system';
    lrUser:       Result := 'user';
    lrAssistant:  Result := 'assistant';
    lrToolResult: Result := 'tool';
  else
    Result := 'user';
  end;
end;

function NameToRole(const AName: string): TLLMRole;
var
  LName: string;
begin
  LName := AName.ToLower;
  if LName = 'system' then
    Result := lrSystem
  else if LName = 'assistant' then
    Result := lrAssistant
  else if (LName = 'tool') or (LName = 'toolresult') then
    Result := lrToolResult
  else
    Result := lrUser;
end;

function MessageToJson(const AMsg: TLLMMessage): TJsonObject;
var
  JCalls: TJsonArray;
  JCall: TJsonObject;
  TC: TLLMToolCall;
begin
  Result := TJsonObject.Create;
  Result.S['role'] := RoleToName(AMsg.Role);
  Result.S['content'] := AMsg.Content;
  Result.S['toolCallId'] := AMsg.ToolCallId;
  JCalls := Result.A['toolCalls'];
  for TC in AMsg.ToolCalls do
  begin
    JCall := JCalls.AddObject;
    JCall.S['id'] := TC.Id;
    JCall.S['name'] := TC.Name;
    JCall.S['argsJson'] := TC.ArgsJson;
  end;
end;

function JsonToMessage(AObj: TJsonObject): TLLMMessage;
var
  JCalls: TJsonArray;
  JCallObj: TJsonObject;
  TC: TLLMToolCall;
  Calls: TArray<TLLMToolCall>;
  I: Integer;
begin
  Result := Default(TLLMMessage);
  // AObj.S['role'] returns '' when absent, and NameToRole('') already falls
  // through to lrUser (its else branch) - same effective default as the
  // original GetValue<string>('role', 'user').
  Result.Role       := NameToRole(AObj.S['role']);
  Result.Content    := AObj.S['content'];
  Result.ToolCallId := AObj.S['toolCallId'];
  if AObj.Types['toolCalls'] <> jdtArray then
    Exit;
  JCalls := AObj.A['toolCalls'];
  SetLength(Calls, JCalls.Count);
  for I := 0 to JCalls.Count - 1 do
  begin
    JCallObj := JCalls.O[I];
    TC := Default(TLLMToolCall);
    TC.Id       := JCallObj.S['id'];
    TC.Name     := JCallObj.S['name'];
    TC.ArgsJson := JCallObj.S['argsJson'];
    Calls[I] := TC;
  end;
  Result.ToolCalls := Calls;
end;

function ToolCallToJson(const ATC: TLLMToolCall): TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['id'] := ATC.Id;
  Result.S['name'] := ATC.Name;
  Result.S['argsJson'] := ATC.ArgsJson;
end;

function JsonToToolCall(AObj: TJsonObject): TLLMToolCall;
begin
  Result := Default(TLLMToolCall);
  Result.Id       := AObj.S['id'];
  Result.Name     := AObj.S['name'];
  Result.ArgsJson := AObj.S['argsJson'];
end;

{ TAgentState }

constructor TAgentState.Create(const AThreadId: string);
begin
  inherited Create;
  FThreadId := AThreadId;
  FMetadata := TDictionary<string, string>.Create;
end;

constructor TAgentState.CreateInternal(
  const AMessages:     TArray<TLLMMessage>;
  const APendingCalls: TArray<TLLMToolCall>;
  const ACurrentNode:  string;
  AIteration:          Integer;
  AIsDone:             Boolean;
  const AFinalAnswer:  string;
  AMetadata:           TDictionary<string, string>;
  const AThreadId:     string
);
begin
  inherited Create;
  FMessages     := AMessages;
  FPendingCalls := APendingCalls;
  FCurrentNode  := ACurrentNode;
  FIteration    := AIteration;
  FIsDone       := AIsDone;
  FFinalAnswer  := AFinalAnswer;
  FThreadId     := AThreadId;
  if AMetadata <> nil then
    FMetadata := AMetadata
  else
    FMetadata := TDictionary<string, string>.Create;
end;

destructor TAgentState.Destroy;
begin
  FMetadata.Free;
  inherited;
end;

function TAgentState.CloneMetadata: TDictionary<string, string>;
var
  Pair: TPair<string, string>;
begin
  Result := TDictionary<string, string>.Create;
  if FMetadata = nil then
    Exit;
  for Pair in FMetadata do
    Result.AddOrSetValue(Pair.Key, Pair.Value);
end;

function TAgentState.CloneMessages: TArray<TLLMMessage>;
begin
  Result := Copy(FMessages);
end;

function TAgentState.ClonePendingCalls: TArray<TLLMToolCall>;
begin
  Result := Copy(FPendingCalls);
end;

function TAgentState.WithMessage(const AMsg: TLLMMessage): TAgentState;
var
  Msgs: TArray<TLLMMessage>;
begin
  Msgs := CloneMessages;
  SetLength(Msgs, Length(Msgs) + 1);
  Msgs[High(Msgs)] := AMsg;
  Result := TAgentState.CreateInternal(
    Msgs, ClonePendingCalls, FCurrentNode, FIteration, FIsDone,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.WithMessages(const AMsgs: TArray<TLLMMessage>): TAgentState;
begin
  Result := TAgentState.CreateInternal(
    Copy(AMsgs), ClonePendingCalls, FCurrentNode, FIteration, FIsDone,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.WithPendingCalls(const ACalls: TArray<TLLMToolCall>): TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, Copy(ACalls), FCurrentNode, FIteration, FIsDone,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.ClearPendingCalls: TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, nil, FCurrentNode, FIteration, FIsDone,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.WithCurrentNode(const ANode: string): TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, ClonePendingCalls, ANode, FIteration, FIsDone,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.WithIteration(AIteration: Integer): TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, ClonePendingCalls, FCurrentNode, AIteration, FIsDone,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.NextIteration: TAgentState;
begin
  Result := WithIteration(FIteration + 1);
end;

function TAgentState.AsDone(const AAnswer: string): TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, ClonePendingCalls, FCurrentNode, FIteration, True,
    AAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.WithMeta(const AKey, AValue: string): TAgentState;
var
  Meta: TDictionary<string, string>;
begin
  Meta := CloneMetadata;
  Meta.AddOrSetValue(AKey, AValue);
  Result := TAgentState.CreateInternal(
    CloneMessages, ClonePendingCalls, FCurrentNode, FIteration, FIsDone,
    FFinalAnswer, Meta, FThreadId);
end;

function TAgentState.RestartAt(const ANode: string): TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, nil, ANode, 0, False, '', CloneMetadata, FThreadId);
end;

function TAgentState.ClearDone: TAgentState;
begin
  Result := TAgentState.CreateInternal(
    CloneMessages, ClonePendingCalls, FCurrentNode, FIteration, False,
    FFinalAnswer, CloneMetadata, FThreadId);
end;

function TAgentState.HasPendingCalls: Boolean;
begin
  Result := Length(FPendingCalls) > 0;
end;

function TAgentState.LastMessage: TLLMMessage;
begin
  if Length(FMessages) = 0 then
    Result := Default(TLLMMessage)
  else
    Result := FMessages[High(FMessages)];
end;

function TAgentState.GetMeta(const AKey: string; const ADefault: string): string;
begin
  if (FMetadata = nil) or not FMetadata.TryGetValue(AKey, Result) then
    Result := ADefault;
end;

function TAgentState.ToJson: string;
var
  Root: TJsonObject;
  JMsgs, JCalls: TJsonArray;
  JMeta: TJsonObject;
  Msg: TLLMMessage;
  TC: TLLMToolCall;
  Pair: TPair<string, string>;
begin
  Root := TJsonObject.Create;
  try
    Root.S['threadId'] := FThreadId;
    Root.S['currentNode'] := FCurrentNode;
    Root.I['iteration'] := FIteration;
    Root.B['isDone'] := FIsDone;
    Root.S['finalAnswer'] := FFinalAnswer;

    JMsgs := Root.A['messages'];
    for Msg in FMessages do
      JMsgs.Add(MessageToJson(Msg));

    JCalls := Root.A['pendingCalls'];
    for TC in FPendingCalls do
      JCalls.Add(ToolCallToJson(TC));

    JMeta := Root.O['metadata'];
    if FMetadata <> nil then
      for Pair in FMetadata do
        JMeta.S[Pair.Key] := Pair.Value;

    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

class function TAgentState.FromJson(const AJson: string): TAgentState;
var
  Parsed: TJsonBaseObject;
  Root: TJsonObject;
  JMsgs, JCalls: TJsonArray;
  JMeta: TJsonObject;
  Msgs: TArray<TLLMMessage>;
  Calls: TArray<TLLMToolCall>;
  Meta: TDictionary<string, string>;
  I: Integer;
begin
  try
    Parsed := TJsonBaseObject.Parse(AJson);
  except
    Parsed := nil;
  end;
  if not (Parsed is TJsonObject) then
  begin
    Parsed.Free;
    raise EArgumentException.Create('JSON de estado inválido');
  end;
  Root := TJsonObject(Parsed);
  try
    if Root.Types['messages'] = jdtArray then
    begin
      JMsgs := Root.A['messages'];
      SetLength(Msgs, JMsgs.Count);
      for I := 0 to JMsgs.Count - 1 do
        Msgs[I] := JsonToMessage(JMsgs.O[I]);
    end;

    if Root.Types['pendingCalls'] = jdtArray then
    begin
      JCalls := Root.A['pendingCalls'];
      SetLength(Calls, JCalls.Count);
      for I := 0 to JCalls.Count - 1 do
        Calls[I] := JsonToToolCall(JCalls.O[I]);
    end;

    Meta := TDictionary<string, string>.Create;
    if Root.Types['metadata'] = jdtObject then
    begin
      JMeta := Root.O['metadata'];
      if JMeta <> nil then
        for I := 0 to JMeta.Count - 1 do
          Meta.AddOrSetValue(JMeta.Names[I], JMeta.Items[I].Value);
    end;

    Result := TAgentState.CreateInternal(
      Msgs,
      Calls,
      Root.S['currentNode'],
      Root.I['iteration'],
      Root.B['isDone'],
      Root.S['finalAnswer'],
      Meta,
      Root.S['threadId']
    );
  finally
    Root.Free;
  end;
end;

end.
