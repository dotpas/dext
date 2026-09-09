{***************************************************************************}
{                                                                                   }
{           Dext Framework                                                          }
{                                                                                   }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors                     }
{                                                                                   }
{           Licensed under the Apache License, Version 2.0 (the "License");         }
{           you may not use this file except in compliance with the License.        }
{           You may obtain a copy of the License at                                 }
{                                                                                   }
{               http://www.apache.org/licenses/LICENSE-2.0                          }
{                                                                                   }
{           Unless required by applicable law or agreed to in writing,              }
{           software distributed under the License is distributed on an             }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,            }
{           either express or implied. See the License for the specific             }
{           language governing permissions and limitations under the                }
{           License.                                                                }
{                                                                                   }
{***************************************************************************}
{                                                                           }
{  Description:                                                             }
{    MCP Resource registry and fluent builder.                              }
{                                                                           }
{    Resources are read-only data sources that LLMs can fetch by URI.       }
{    Think of them as "files" or "documents" the model can read.           }
{                                                                           }
{  Fluent registration:                                                     }
{    Server.Resource('file:///config', 'App Config', 'text/json')           }
{      .Description('Returns the current application configuration')        }
{      .OnRead(function(const AUri: string): TMCPResourceContents           }
{        begin                                                              }
{          Result := TMCPResourceContents.TextResource(AUri, LoadConfig);   }
{        end);                                                              }
{                                                                           }
{  RTTI provider (via MCPResource attribute on TMCPToolProvider subclass):  }
{    [MCPResource('file:///logs', 'App Logs', 'Recent application logs')]   }
{    function ReadLogs(const AUri: string): TMCPResourceContents; virtual;  }
{                                                                           }
{***************************************************************************}
unit Dext.AI.MCP.Resources;

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
  /// <summary>Internal representation of a registered MCP resource.</summary>
  TMCPResourceDef = record
    Uri: string;
    Name: string;
    Description: string;
    MimeType: string;
    ReadCallback: TMCPResourceReadCallback;
  end;

  TMCPResourceRegistry = class;

  /// <summary>
  /// Fluent builder for configuring an MCP resource.
  /// Chain: .Description / .MimeType / .OnRead to complete registration.
  /// </summary>
  IMCPResourceBuilder = interface
    ['{F1DE3F88-E828-4793-9E4B-0F22E6C03752}']
    function Description(const AText: string): IMCPResourceBuilder;
    function MimeType(const AMimeType: string): IMCPResourceBuilder;
    function OnRead(ACallback: TMCPResourceReadCallback): IMCPResourceBuilder;
  end;

  TMCPResourceBuilder = class(TInterfacedObject, IMCPResourceBuilder)
  private
    FDef: TMCPResourceDef;
    FRegistry: TMCPResourceRegistry; // weak ref
  public
    constructor Create(const AUri, AName: string;
      ARegistry: TMCPResourceRegistry);

    function Description(const AText: string): IMCPResourceBuilder;
    function MimeType(const AMimeType: string): IMCPResourceBuilder;
    function OnRead(ACallback: TMCPResourceReadCallback): IMCPResourceBuilder;
  end;

  /// <summary>
  /// Central registry for MCP resources.
  /// Supports fluent registration and RTTI-based provider scanning.
  /// </summary>
  TMCPResourceRegistry = class
  private
    FResources: TDictionary<string, TMCPResourceDef>;

    function MakeProviderCallback(AProvider: TObject;
      AMethod: TRttiMethod): TMCPResourceReadCallback;
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Fluent builder for a new resource identified by AUri.</summary>
    function Register(const AUri, AName: string): IMCPResourceBuilder;

    /// <summary>
    /// Scans AProvider for [MCPResource]-annotated methods and registers each.
    /// Does NOT take ownership of AProvider (caller or tool registry owns it).
    /// </summary>
    procedure ScanProvider(AProvider: TObject);

    /// <summary>Internal: commits a fully configured resource def.</summary>
    procedure Commit(const ADef: TMCPResourceDef);

    /// <summary>Reads a resource by URI. Returns False if not found.</summary>
    function TryRead(const AUri: string;
      out AContents: TMCPResourceContents): Boolean;

    /// <summary>Returns True if any resource URI starts with the given pattern.</summary>
    function HasUri(const AUri: string): Boolean;

    /// <summary>
    /// Builds the JSON array for the resources/list response.
    /// Caller owns the returned TJsonArray.
    /// </summary>
    function BuildResourcesArray: TJsonArray;

    function Count: Integer;
  end;

implementation

{ TMCPResourceBuilder }

constructor TMCPResourceBuilder.Create(const AUri, AName: string;
  ARegistry: TMCPResourceRegistry);
begin
  inherited Create;
  FDef.Uri      := AUri;
  FDef.Name     := AName;
  FRegistry     := ARegistry;
end;

function TMCPResourceBuilder.Description(const AText: string): IMCPResourceBuilder;
begin
  FDef.Description := AText;
  Result := Self;
end;

function TMCPResourceBuilder.MimeType(const AMimeType: string): IMCPResourceBuilder;
begin
  FDef.MimeType := AMimeType;
  Result := Self;
end;

function TMCPResourceBuilder.OnRead(
  ACallback: TMCPResourceReadCallback): IMCPResourceBuilder;
begin
  FDef.ReadCallback := ACallback;
  FRegistry.Commit(FDef);
  Result := Self;
end;

{ TMCPResourceRegistry }

constructor TMCPResourceRegistry.Create;
begin
  inherited Create;
  FResources := TDictionary<string, TMCPResourceDef>.Create;
end;

destructor TMCPResourceRegistry.Destroy;
begin
  FResources.Free;
  inherited;
end;

function TMCPResourceRegistry.Register(const AUri,
  AName: string): IMCPResourceBuilder;
begin
  Result := TMCPResourceBuilder.Create(AUri, AName, Self);
end;

function TMCPResourceRegistry.MakeProviderCallback(AProvider: TObject;
  AMethod: TRttiMethod): TMCPResourceReadCallback;
begin
  Result := function(const AUri: string): TMCPResourceContents
  var
    InvokeResult: TValue;
  begin
    try
      InvokeResult := AMethod.Invoke(AProvider, [TValue.From<string>(AUri)]);
      Result := InvokeResult.AsType<TMCPResourceContents>;
    except
      on E: Exception do
        Result := TMCPResourceContents.TextResource(AUri,
          'Error reading resource: ' + E.Message, 'text/plain');
    end;
  end;
end;

procedure TMCPResourceRegistry.ScanProvider(AProvider: TObject);
var
  RttiType: TRttiType;
  Method: TRttiMethod;
  ResAttr: MCPResourceAttribute;
  Attr: TCustomAttribute;
  Def: TMCPResourceDef;
begin
  RttiType := TReflection.Context.GetType(AProvider.ClassType);

  for Method in RttiType.GetMethods do
  begin
    ResAttr := nil;
    for Attr in Method.GetAttributes do
      if Attr is MCPResourceAttribute then
      begin
        ResAttr := MCPResourceAttribute(Attr);
        Break;
      end;

    if ResAttr = nil then Continue;

    Def := Default(TMCPResourceDef);
    Def.Uri          := ResAttr.Uri;
    Def.Name         := ResAttr.Name;
    Def.Description  := ResAttr.Description;
    Def.MimeType     := ResAttr.MimeType;
    Def.ReadCallback := MakeProviderCallback(AProvider, Method);

    FResources.AddOrSetValue(Def.Uri, Def);
  end;
end;

procedure TMCPResourceRegistry.Commit(const ADef: TMCPResourceDef);
begin
  FResources.AddOrSetValue(ADef.Uri, ADef);
end;

function TMCPResourceRegistry.TryRead(const AUri: string;
  out AContents: TMCPResourceContents): Boolean;
var
  Def: TMCPResourceDef;
begin
  if not FResources.TryGetValue(AUri, Def) then
    Exit(False);

  if not Assigned(Def.ReadCallback) then
    Exit(False);

  AContents := Def.ReadCallback(AUri);
  Result := True;
end;

function TMCPResourceRegistry.HasUri(const AUri: string): Boolean;
begin
  Result := FResources.ContainsKey(AUri);
end;

function TMCPResourceRegistry.Count: Integer;
begin
  Result := FResources.Count;
end;

function TMCPResourceRegistry.BuildResourcesArray: TJsonArray;
var
  Arr: TJsonArray;
  Def: TMCPResourceDef;
  ResObj: TJsonObject;
begin
  Arr := TJsonArray.Create;

  for Def in FResources.Values do
  begin
    ResObj := Arr.AddObject;
    ResObj.S['uri'] := Def.Uri;
    ResObj.S['name'] := Def.Name;
    if Def.Description <> '' then
      ResObj.S['description'] := Def.Description;
    if Def.MimeType <> '' then
      ResObj.S['mimeType'] := Def.MimeType;
  end;

  Result := Arr;
end;

end.
