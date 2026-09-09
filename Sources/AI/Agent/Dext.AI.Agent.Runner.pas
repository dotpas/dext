{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Dext.AI.Agent - Multi-Provider LLM Agent                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    The ReAct loop. Provider-agnostic - talks only to ILLMProvider and to  }
{    TMCPToolProvider subclasses, both already part of the Dext framework.  }
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
unit Dext.AI.Agent.Runner;

interface

uses
  Dext.AI.Agent.Contracts,
  Dext.AI.MCP.Tools,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Protocol,
  Dext.Collections,
  System.SysUtils,
  DextJsonDataObjects;

type
  TAgentRunner = class
  private
    FProvider:  ILLMProvider;
    FConfig:    TAgentConfig;
    FObserver:  IAgentObserver;
    // TMCPToolRegistry já faz o scan RTTI de [MCPTool]/[MCPParam] e assume a
    // ownership dos providers registrados — mesma lógica que o MCP Server
    // usa, sem uma segunda cópia divergente aqui.
    FRegistry:  TMCPToolRegistry;

    function BuildToolSchemas: TArray<TToolSchema>;
    function ExecuteTool(const AToolName, AArgsJson: string): string;
    function ToolResultToText(const AResult: TMCPToolResult): string;
  public
    constructor Create(
      AProvider: ILLMProvider;
      const AConfig: TAgentConfig;
      AObserver: IAgentObserver = nil
    );
    destructor Destroy; override;
    procedure RegisterProvider(AProvider: TMCPToolProvider);
    function Run(const AUserInput: string): TAgentResult;
  end;

implementation

{ TAgentRunner }

constructor TAgentRunner.Create(AProvider: ILLMProvider;
  const AConfig: TAgentConfig; AObserver: IAgentObserver);
begin
  inherited Create;
  FProvider  := AProvider;
  FConfig    := AConfig;
  FObserver  := AObserver;
  FRegistry  := TMCPToolRegistry.Create;
end;

destructor TAgentRunner.Destroy;
begin
  FRegistry.Free;
  inherited;
end;

procedure TAgentRunner.RegisterProvider(AProvider: TMCPToolProvider);
begin
  if AProvider <> nil then
    FRegistry.RegisterProvider(AProvider);
end;

function TAgentRunner.BuildToolSchemas: TArray<TToolSchema>;
var
  Arr: TJsonArray;
  Item: TJsonObject;
  Schema: TToolSchema;
  List: TArray<TToolSchema>;
  I: Integer;
begin
  Arr := FRegistry.BuildToolsArray;
  try
    SetLength(List, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      Item := Arr.O[I];
      Schema := Default(TToolSchema);
      Schema.Name        := Item.S['name'];
      Schema.Description := Item.S['description'];
      if Item.Types['inputSchema'] = jdtObject then
        Schema.InputSchema := Item.O['inputSchema'].ToJSON
      else
        Schema.InputSchema := '{}';
      List[I] := Schema;
    end;
    Result := List;
  finally
    Arr.Free;
  end;
end;

function TAgentRunner.ToolResultToText(const AResult: TMCPToolResult): string;
var
  Item: TMCPContent;
  Parts: TStringBuilder;
begin
  Parts := TStringBuilder.Create;
  try
    for Item in AResult.Content do
      if Item.ContentType = mctText then
      begin
        if Parts.Length > 0 then
          Parts.Append(sLineBreak);
        Parts.Append(Item.TextValue);
      end;

    Result := Parts.ToString;
    if AResult.IsError then
      Result := '[Error] ' + Result;
  finally
    Parts.Free;
  end;
end;

function TAgentRunner.ExecuteTool(const AToolName, AArgsJson: string): string;
var
  Def: TMCPToolDef;
  Parsed: TJsonBaseObject;
  JArgs: TJsonObject;
begin
  if not FRegistry.TryGetTool(AToolName, Def) then
    Exit('[Error: Tool not found: ' + AToolName + ']');

  try
    Parsed := TJsonBaseObject.Parse(AArgsJson);
  except
    Parsed := nil;
  end;
  if Parsed is TJsonObject then
    JArgs := TJsonObject(Parsed)
  else
  begin
    Parsed.Free;
    JArgs := TJsonObject.Create;
  end;
  try
    try
      // ResultCallback (rico) tem precedência sobre o Callback legado
      // (string) — mesma ordem usada em TMCPServer.HandleToolsCall.
      if Assigned(Def.ResultCallback) then
        Exit(ToolResultToText(Def.ResultCallback(JArgs)))
      else if Assigned(Def.Callback) then
        Exit(Def.Callback(JArgs))
      else
        Exit('[Error: Tool "' + AToolName + '" has no callback]');
    except
      on E: Exception do
        Exit('[Error] ' + E.Message);
    end;
  finally
    JArgs.Free;
  end;
end;

function TAgentRunner.Run(const AUserInput: string): TAgentResult;
var
  Messages: TList<TLLMMessage>;
  Schemas: TArray<TToolSchema>;
  Response: TLLMResponse;
  Iteration: Integer;
  TC: TLLMToolCall;
  ToolResultText: string;
begin
  Result := Default(TAgentResult);

  Messages := TList<TLLMMessage>.Create;
  try
    if FConfig.SystemPrompt <> '' then
      Messages.Add(TLLMMessage.System(FConfig.SystemPrompt));
    Messages.Add(TLLMMessage.User(AUserInput));

    Schemas := BuildToolSchemas;

    for Iteration := 1 to FConfig.MaxIterations do
    begin
      if Assigned(FObserver) then
        FObserver.OnIterationStart(Iteration);

      try
        Response := FProvider.Complete(Messages.ToArray, Schemas);
      except
        on E: Exception do
        begin
          Result.Success    := False;
          Result.Iterations := Iteration;
          Result.ErrorMsg   := E.Message;
          Exit;
        end;
      end;

      if Assigned(FObserver) then
        FObserver.OnLLMResponse(Response.Content, Response.StopReason);

      case Response.StopReason of
        srEndTurn:
        begin
          if Assigned(FObserver) then
            FObserver.OnFinished(Response.Content, Iteration);
          Result.FinalAnswer := Response.Content;
          Result.Success     := True;
          Result.Iterations  := Iteration;
          Exit;
        end;

        srToolUse:
        begin
          Messages.Add(TLLMMessage.Assistant(Response.Content, Response.ToolCalls));

          for TC in Response.ToolCalls do
          begin
            if Assigned(FObserver) then
              FObserver.OnToolCall(TC.Name, TC.ArgsJson);

            ToolResultText := ExecuteTool(TC.Name, TC.ArgsJson);

            if Assigned(FObserver) then
              FObserver.OnToolResult(TC.Name, ToolResultText);

            Messages.Add(TLLMMessage.ToolResult(TC.Id, ToolResultText));
          end;
        end;

        srMaxTokens:
        begin
          Result.FinalAnswer := Response.Content;
          Result.Success     := False;
          Result.Iterations  := Iteration;
          Result.ErrorMsg    := 'Limite de tokens atingido';
          Exit;
        end;
      else
        begin
          Result.Success  := False;
          Result.ErrorMsg := 'Erro reportado pelo provider (srError)';
          Exit;
        end;
      end;
    end;

    Result.Success  := False;
    Result.ErrorMsg := 'Limite de itera��es atingido';
  finally
    Messages.Free;
  end;
end;

end.
