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
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    MCP Prompt registry and fluent builder.                                }
{                                                                           }
{    Prompts are reusable message templates that LLMs can invoke by name.   }
{    They may accept arguments to customise the generated messages.         }
{                                                                           }
{  Fluent registration:                                                     }
{    Server.Prompt('code-review', 'Reviews Delphi code for quality issues') }
{      .Arg('code',     'Delphi source code to review')                     }
{      .Arg('language', 'Language hint', False)                             }
{      .OnGet(function(Args: TJsonObject): TMCPPromptResult                 }
{        var Code: string;                                                  }
{        begin                                                              }
{          Code := Args.S['code'];                                          }
{          Result := TMCPPromptResult.Create('Code review prompt');         }
{          Result.AddMessage(TMCPPromptMessage.User(                        }
{            'Review this Delphi code:' + sLineBreak + Code));              }
{        end);                                                              }
{                                                                           }
{  RTTI provider (via MCPPrompt attribute on TMCPToolProvider subclass):    }
{    [MCPPrompt('code-review', 'Reviews Delphi code')]                      }
{    [MCPPromptArg('code', 'Source code to review')]                        }
{    function CodeReview(const Args: TJsonObject):                          }
{      TMCPPromptResult; virtual;                                           }
{                                                                           }
{***************************************************************************}
unit Dext.AI.MCP.Prompts;

interface

uses
  System.SysUtils,
  DextJsonDataObjects,
  System.RTTI,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Core.Reflection,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Attributes;

type
  /// <summary>Describes one argument of a prompt template.</summary>
  TMCPPromptArgDef = record
    Name: string;
    Description: string;
    Required: Boolean;
  end;

  /// <summary>Internal representation of a registered MCP prompt.</summary>
  TMCPPromptDef = record
    Name: string;
    Description: string;
    Args: TArray<TMCPPromptArgDef>;
    GetCallback: TMCPPromptGetCallback;
  end;

  TMCPPromptRegistry = class;

  /// <summary>
  /// Fluent builder for configuring an MCP prompt template.
  /// Chain: .Arg / .OnGet to complete registration.
  /// </summary>
  IMCPPromptBuilder = interface
    ['{EAF6AD97-3600-42BB-87DE-F377BE7A3CA4}']
    function Arg(const AName, ADescription: string;
      ARequired: Boolean = True): IMCPPromptBuilder;
    function OnGet(ACallback: TMCPPromptGetCallback): IMCPPromptBuilder;
  end;

  TMCPPromptBuilder = class(TInterfacedObject, IMCPPromptBuilder)
  private
    FDef: TMCPPromptDef;
    FRegistry: TMCPPromptRegistry; // weak ref
  public
    constructor Create(const AName, ADescription: string;
      ARegistry: TMCPPromptRegistry);

    function Arg(const AName, ADescription: string;
      ARequired: Boolean = True): IMCPPromptBuilder;
    function OnGet(ACallback: TMCPPromptGetCallback): IMCPPromptBuilder;
  end;

  /// <summary>
  /// Central registry for MCP prompt templates.
  /// Supports fluent registration and RTTI-based provider scanning.
  /// </summary>
  TMCPPromptRegistry = class
  private
    FPrompts: TDictionary<string, TMCPPromptDef>;

    function MakeProviderCallback(AProvider: TObject;
      AMethod: TRttiMethod): TMCPPromptGetCallback;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Fluent builder for a new prompt template.</summary>
    function Register(const AName,
      ADescription: string): IMCPPromptBuilder;

    /// <summary>
    /// Scans AProvider for [MCPPrompt]-annotated methods and registers each.
    /// Does NOT take ownership of AProvider.
    /// </summary>
    procedure ScanProvider(AProvider: TObject);

    /// <summary>Internal: commits a fully configured prompt def.</summary>
    procedure Commit(const ADef: TMCPPromptDef);

    /// <summary>Executes a prompt by name. Returns False if not found.</summary>
    function TryGet(const AName: string; const Args: TJsonObject;
      out AResult: TMCPPromptResult): Boolean;

    /// <summary>
    /// Builds the JSON array for the prompts/list response.
    /// Caller owns the returned TJsonArray.
    /// </summary>
    function BuildPromptsArray: TJsonArray;

    function Count: Integer;
  end;

implementation

{ TMCPPromptBuilder }

constructor TMCPPromptBuilder.Create(const AName, ADescription: string;
  ARegistry: TMCPPromptRegistry);
begin
  inherited Create;
  FDef.Name        := AName;
  FDef.Description := ADescription;
  FRegistry        := ARegistry;
end;

function TMCPPromptBuilder.Arg(const AName, ADescription: string;
  ARequired: Boolean): IMCPPromptBuilder;
var
  ArgDef: TMCPPromptArgDef;
begin
  ArgDef.Name        := AName;
  ArgDef.Description := ADescription;
  ArgDef.Required    := ARequired;
  SetLength(FDef.Args, Length(FDef.Args) + 1);
  FDef.Args[High(FDef.Args)] := ArgDef;
  Result := Self;
end;

function TMCPPromptBuilder.OnGet(
  ACallback: TMCPPromptGetCallback): IMCPPromptBuilder;
begin
  FDef.GetCallback := ACallback;
  FRegistry.Commit(FDef);
  Result := Self;
end;

{ TMCPPromptRegistry }

constructor TMCPPromptRegistry.Create;
begin
  inherited Create;
  FPrompts := TDictionary<string, TMCPPromptDef>.Create;
end;

destructor TMCPPromptRegistry.Destroy;
begin
  FPrompts.Free;
  inherited;
end;

function TMCPPromptRegistry.Register(const AName,
  ADescription: string): IMCPPromptBuilder;
begin
  Result := TMCPPromptBuilder.Create(AName, ADescription, Self);
end;

function TMCPPromptRegistry.MakeProviderCallback(AProvider: TObject;
  AMethod: TRttiMethod): TMCPPromptGetCallback;
begin
  Result := function(const Args: TJsonObject): TMCPPromptResult
  var
    InvokeResult: TValue;
  begin
    try
      InvokeResult := AMethod.Invoke(AProvider,
        [TValue.From<TJsonObject>(Args)]);
      Result := InvokeResult.AsType<TMCPPromptResult>;
    except
      on E: Exception do
      begin
        Result := TMCPPromptResult.Create('Error');
        Result.AddMessage(TMCPPromptMessage.User(
          'Prompt generation failed: ' + E.Message));
      end;
    end;
  end;
end;

procedure TMCPPromptRegistry.ScanProvider(AProvider: TObject);
var
  RttiType: TRttiType;
  Method: TRttiMethod;
  PromptAttr: MCPPromptAttribute;
  ArgAttr: MCPPromptArgAttribute;
  Attr: TCustomAttribute;
  Def: TMCPPromptDef;
  ArgDef: TMCPPromptArgDef;
begin
  RttiType := TReflection.Context.GetType(AProvider.ClassType);

  for Method in RttiType.GetMethods do
  begin
    PromptAttr := nil;
    for Attr in Method.GetAttributes do
      if Attr is MCPPromptAttribute then
      begin
        PromptAttr := MCPPromptAttribute(Attr);
        Break;
      end;

    if PromptAttr = nil then Continue;

    Def := Default(TMCPPromptDef);
    Def.Name        := PromptAttr.Name;
    Def.Description := PromptAttr.Description;

    for Attr in Method.GetAttributes do
      if Attr is MCPPromptArgAttribute then
      begin
        ArgAttr := MCPPromptArgAttribute(Attr);
        ArgDef.Name        := ArgAttr.Name;
        ArgDef.Description := ArgAttr.Description;
        ArgDef.Required    := ArgAttr.Required;
        SetLength(Def.Args, Length(Def.Args) + 1);
        Def.Args[High(Def.Args)] := ArgDef;
      end;

    Def.GetCallback := MakeProviderCallback(AProvider, Method);
    FPrompts.AddOrSetValue(Def.Name, Def);
  end;
end;

procedure TMCPPromptRegistry.Commit(const ADef: TMCPPromptDef);
begin
  FPrompts.AddOrSetValue(ADef.Name, ADef);
end;

function TMCPPromptRegistry.TryGet(const AName: string;
  const Args: TJsonObject; out AResult: TMCPPromptResult): Boolean;
var
  Def: TMCPPromptDef;
begin
  if not FPrompts.TryGetValue(AName, Def) then
    Exit(False);

  if not Assigned(Def.GetCallback) then
    Exit(False);

  AResult := Def.GetCallback(Args);
  Result := True;
end;

function TMCPPromptRegistry.Count: Integer;
begin
  Result := FPrompts.Count;
end;

function TMCPPromptRegistry.BuildPromptsArray: TJsonArray;
var
  Arr: TJsonArray;
  Def: TMCPPromptDef;
  PromptObj, ArgObj: TJsonObject;
  ArgsArr: TJsonArray;
  ArgDef: TMCPPromptArgDef;
begin
  Arr := TJsonArray.Create;

  for Def in FPrompts.Values do
  begin
    PromptObj := Arr.AddObject;
    PromptObj.S['name'] := Def.Name;
    if Def.Description <> '' then
      PromptObj.S['description'] := Def.Description;

    if Length(Def.Args) > 0 then
    begin
      ArgsArr := PromptObj.A['arguments'];
      for ArgDef in Def.Args do
      begin
        ArgObj := ArgsArr.AddObject;
        ArgObj.S['name'] := ArgDef.Name;
        if ArgDef.Description <> '' then
          ArgObj.S['description'] := ArgDef.Description;
        ArgObj.B['required'] := ArgDef.Required;
      end;
    end;
  end;

  Result := Arr;
end;

end.
