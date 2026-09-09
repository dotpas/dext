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
{    MCP Tool registry, fluent builder, and RTTI-based provider support.    }
{                                                                           }
{  Fluent builder (quick, anonymous):                                       }
{    Server.Tool('my-tool')                                                 }
{      .Description('Does something useful')                                }
{      .Param('query', 'Search term', ptString)                             }
{      .OnCall(function(Args: TJsonObject): string                          }
(*        begin Result := '{"ok":true}'; end);                             *)
{                                                                           }
{  Rich result builder (preferred for new tools):                           }
{    Server.Tool('my-tool')                                                 }
{      .Description('Returns an image')                                     }
{      .Param('id', 'Item ID', ptString)                                    }
{      .OnCallResult(function(Args: TJsonObject): TMCPToolResult            }
{        begin                                                              }
{          Result := TMCPToolResult.Image(GetBase64(Args), 'image/png');    }
{        end);                                                              }
{                                                                           }
{  RTTI provider (recommended for class-based organisation):                }
{    type                                                                   }
{      TMyTools = class(TMCPToolProvider)                                   }
{        [MCPTool('search', 'Full-text search')]                            }
{        [MCPParam('query', 'Search term', ptString)]                       }
{        function Search(const Args: TJsonObject): TMCPToolResult; virtual; }
{      end;                                                                 }
{    Server.RegisterProvider(TMyTools.Create);                              }
{                                                                           }
{***************************************************************************}
unit Dext.AI.MCP.Tools;

interface

uses
  System.SysUtils,
  DextJsonDataObjects,
  System.Rtti,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Protocol,
  Dext.AI.MCP.Attributes,
  Dext.Core.Reflection;

type
  TMCPToolRegistry = class;

  // ---------------------------------------------------------------------------
  // TMCPToolProvider - base class for RTTI-based tool registration
  // ---------------------------------------------------------------------------

  /// <summary>
  /// Base class for class-based MCP tool providers.
  /// Subclass, annotate public virtual methods with [MCPTool] + [MCPParam],
  /// then call Server.RegisterProvider(TMyProvider.Create).
  ///
  /// The registry takes ownership of the provider instance.
  /// </summary>
  TMCPToolProvider = class
  public
    /// <summary>Called before each tool invocation. Override for logging/auth.</summary>
    procedure BeforeCall(const AToolName: string; const Args: TJsonObject); virtual;
    /// <summary>Called after each successful tool invocation.</summary>
    procedure AfterCall(const AToolName: string); virtual;
  end;

  // ---------------------------------------------------------------------------
  // IMCPToolBuilder - fluent configuration interface
  // ---------------------------------------------------------------------------

  /// <summary>
  /// Fluent builder for configuring an MCP tool before registering it.
  /// Chain: .Description / .Param / .OnCall (or .OnCallResult).
  /// The tool is committed to the registry when OnCall / OnCallResult is invoked.
  /// </summary>
  IMCPToolBuilder = interface
    ['{47B27953-8614-46D1-BE60-2B50C44CD4BF}']
    function Description(const AText: string): IMCPToolBuilder;
    function Param(const AName, ADesc: string;
      AType: TMCPParamType = ptString;
      ARequired: Boolean = True): IMCPToolBuilder;

    /// <summary>Registers a legacy string callback. Use OnCallResult for new tools.</summary>
    function OnCall(ACallback: TMCPToolCallback): IMCPToolBuilder;

    /// <summary>Registers a rich-result callback. Preferred over OnCall.</summary>
    function OnCallResult(ACallback: TMCPToolResultCallback): IMCPToolBuilder;
  end;

  TMCPToolBuilder = class(TInterfacedObject, IMCPToolBuilder)
  private
    FDef: TMCPToolDef;
    FRegistry: TMCPToolRegistry; // weak ref
  public
    constructor Create(const AName: string; ARegistry: TMCPToolRegistry);

    function Description(const AText: string): IMCPToolBuilder;
    function Param(const AName, ADesc: string;
      AType: TMCPParamType = ptString;
      ARequired: Boolean = True): IMCPToolBuilder;
    function OnCall(ACallback: TMCPToolCallback): IMCPToolBuilder;
    function OnCallResult(ACallback: TMCPToolResultCallback): IMCPToolBuilder;
  end;

  // ---------------------------------------------------------------------------
  // TMCPToolRegistry - holds all registered tools + RTTI provider scan
  // ---------------------------------------------------------------------------

  /// <summary>
  /// Central registry for all MCP tools.
  /// Supports both fluent registration and RTTI-based provider classes.
  /// </summary>
  TMCPToolRegistry = class
  private
    FTools: TDictionary<string, TMCPToolDef>;
    FProviders: TList<TMCPToolProvider>;
    FCachedTools: TJsonArray;

    procedure InvalidateCache;
    function BuildInputSchema(const Def: TMCPToolDef): TJsonObject;

    function MakeProviderCallback(AProvider: TMCPToolProvider;
      AMethod: TRttiMethod; const AName: string): TMCPToolResultCallback;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Returns a fluent builder for a new tool with the given name.</summary>
    function Register(const AName: string): IMCPToolBuilder;

    /// <summary>
    /// Scans AProvider for [MCPTool]-annotated methods and registers each one.
    /// The registry takes ownership of AProvider (frees it on Destroy).
    /// </summary>
    procedure RegisterProvider(AProvider: TMCPToolProvider);

    /// <summary>Internal: called by TMCPToolBuilder to commit the tool def.</summary>
    procedure Commit(const ADef: TMCPToolDef);

    /// <summary>Tries to find a tool by name. Returns False if not found.</summary>
    function TryGetTool(const AName: string; out ADef: TMCPToolDef): Boolean;

    /// <summary>
    /// Builds the JSON array for the tools/list response.
    /// Caller owns the returned TJsonArray.
    /// </summary>
    function BuildToolsArray: TJsonArray;

    function Count: Integer;
  end;

implementation

{ TMCPToolProvider }

procedure TMCPToolProvider.BeforeCall(const AToolName: string;
  const Args: TJsonObject);
begin
  // Default: no-op. Override for logging, auth checks, etc.
end;

procedure TMCPToolProvider.AfterCall(const AToolName: string);
begin
  // Default: no-op. Override for logging, metrics, etc.
end;

{ TMCPToolBuilder }

constructor TMCPToolBuilder.Create(const AName: string;
  ARegistry: TMCPToolRegistry);
begin
  inherited Create;
  FDef.Name := AName;
  FRegistry := ARegistry;
end;

function TMCPToolBuilder.Description(const AText: string): IMCPToolBuilder;
begin
  FDef.Description := AText;
  Result := Self;
end;

function TMCPToolBuilder.Param(const AName, ADesc: string;
  AType: TMCPParamType; ARequired: Boolean): IMCPToolBuilder;
var
  P: TMCPToolParam;
begin
  P := TMCPToolParam.Create(AName, ADesc, AType, ARequired);
  SetLength(FDef.Params, Length(FDef.Params) + 1);
  FDef.Params[High(FDef.Params)] := P;
  Result := Self;
end;

function TMCPToolBuilder.OnCall(ACallback: TMCPToolCallback): IMCPToolBuilder;
begin
  FDef.Callback := ACallback;
  FRegistry.Commit(FDef);
  Result := Self;
end;

function TMCPToolBuilder.OnCallResult(
  ACallback: TMCPToolResultCallback): IMCPToolBuilder;
begin
  FDef.ResultCallback := ACallback;
  FRegistry.Commit(FDef);
  Result := Self;
end;

{ TMCPToolRegistry }

constructor TMCPToolRegistry.Create;
begin
  inherited Create;
  FTools       := TDictionary<string, TMCPToolDef>.Create;
  FProviders   := TList<TMCPToolProvider>.Create(True); // owns items
  FCachedTools := nil;
end;

destructor TMCPToolRegistry.Destroy;
begin
  InvalidateCache;
  FTools.Free;
  FProviders.Free;
  inherited;
end;

procedure TMCPToolRegistry.InvalidateCache;
begin
  FreeAndNil(FCachedTools);
end;

function TMCPToolRegistry.Register(const AName: string): IMCPToolBuilder;
begin
  Result := TMCPToolBuilder.Create(AName, Self);
end;

function TMCPToolRegistry.MakeProviderCallback(AProvider: TMCPToolProvider;
  AMethod: TRttiMethod; const AName: string): TMCPToolResultCallback;
begin
  // AMethod and AProvider are parameters - each call creates a distinct
  // activation record, so the closure captures the right values per tool.
  Result := function(const Args: TJsonObject): TMCPToolResult
  var
    InvokeResult: TValue;
  begin
    try
      AProvider.BeforeCall(AName, Args);
      InvokeResult := AMethod.Invoke(AProvider,
        [TValue.From<TJsonObject>(Args)]);
      AProvider.AfterCall(AName);
      Result := InvokeResult.AsType<TMCPToolResult>;
    except
      on E: Exception do
        Result := TMCPToolResult.Error(E.Message);
    end;
  end;
end;

procedure TMCPToolRegistry.RegisterProvider(AProvider: TMCPToolProvider);
var
  RttiType: TRttiType;
  Method: TRttiMethod;
  ToolAttr: MCPToolAttribute;
  ParamAttr: MCPParamAttribute;
  Attr: TCustomAttribute;
  Def: TMCPToolDef;
begin
  InvalidateCache;
  FProviders.Add(AProvider); // registry owns it

  RttiType := TReflection.Context.GetType(AProvider.ClassType);

  for Method in RttiType.GetMethods do
  begin
    ToolAttr := Method.GetAttribute<MCPToolAttribute>;
    if ToolAttr = nil then Continue;

    Def := Default(TMCPToolDef);
    Def.Name        := ToolAttr.Name;
    Def.Description := ToolAttr.Description;

    for Attr in Method.GetAttributes do
      if Attr is MCPParamAttribute then
      begin
        ParamAttr := MCPParamAttribute(Attr);
        SetLength(Def.Params, Length(Def.Params) + 1);
        Def.Params[High(Def.Params)] := TMCPToolParam.Create(
          ParamAttr.Name, ParamAttr.Description,
          ParamAttr.ParamType, ParamAttr.Required);
      end;

    Def.ResultCallback := MakeProviderCallback(AProvider, Method, Def.Name);
    FTools.AddOrSetValue(Def.Name, Def);
  end;
end;

procedure TMCPToolRegistry.Commit(const ADef: TMCPToolDef);
begin
  InvalidateCache;
  FTools.AddOrSetValue(ADef.Name, ADef);
end;

function TMCPToolRegistry.TryGetTool(const AName: string;
  out ADef: TMCPToolDef): Boolean;
begin
  Result := FTools.TryGetValue(AName, ADef);
end;

function TMCPToolRegistry.Count: Integer;
begin
  Result := FTools.Count;
end;

function TMCPToolRegistry.BuildInputSchema(const Def: TMCPToolDef): TJsonObject;
var
  Schema, Props, PropObj: TJsonObject;
  Required: TJsonArray;
  P: TMCPToolParam;
begin
  Schema := TJsonObject.Create;
  Schema.S['type'] := 'object';

  Props    := Schema.O['properties'];
  Required := TJsonArray.Create;

  for P in Def.Params do
  begin
    PropObj := Props.O[P.Name];
    PropObj.S['type'] := P.TypeName;
    if P.Description <> '' then
      PropObj.S['description'] := P.Description;

    if P.Required then
      Required.Add(P.Name);
  end;

  if Required.Count > 0 then
    Schema.A['required'] := Required
  else
    Required.Free;

  Result := Schema;
end;

function TMCPToolRegistry.BuildToolsArray: TJsonArray;
var
  Def: TMCPToolDef;
  ToolObj: TJsonObject;
begin
  if FCachedTools <> nil then
    Exit(FCachedTools.Clone as TJsonArray);

  FCachedTools := TJsonArray.Create;

  for Def in FTools.Values do
  begin
    ToolObj := FCachedTools.AddObject;
    ToolObj.S['name'] := Def.Name;
    ToolObj.S['description'] := Def.Description;
    ToolObj.O['inputSchema'] := BuildInputSchema(Def);
  end;

  Result := FCachedTools.Clone as TJsonArray;
end;

end.
