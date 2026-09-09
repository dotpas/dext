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
{    MCP (Model Context Protocol) core types and JSON-RPC 2.0 helpers.      }
{                                                                           }
{    The MCP protocol uses JSON-RPC 2.0 as its message format.              }
{    Supports: initialize, ping, tools/list, tools/call                     }
{                                                                           }
{  Reference: https://spec.modelcontextprotocol.io                          }
{                                                                           }
{***************************************************************************}
unit Dext.AI.MCP.Protocol;

interface

uses
  System.SysUtils,
  DextJsonDataObjects,
  Dext.AI.MCP.Types;

const
  MCP_JSONRPC_VERSION  = '2.0';
  MCP_PROTOCOL_VERSION = '2025-03-26';

  // JSON-RPC 2.0 standard error codes
  JSONRPC_PARSE_ERROR      = -32700;
  JSONRPC_INVALID_REQUEST  = -32600;
  JSONRPC_METHOD_NOT_FOUND = -32601;
  JSONRPC_INVALID_PARAMS   = -32602;
  JSONRPC_INTERNAL_ERROR   = -32603;

  // MCP-specific error codes
  MCP_ERROR_TOOL_NOT_FOUND     = -32000;
  MCP_ERROR_TOOL_EXEC_FAILED   = -32001;
  MCP_ERROR_RESOURCE_NOT_FOUND = -32002;
  MCP_ERROR_PROMPT_NOT_FOUND   = -32003;
  MCP_ERROR_SESSION_NOT_FOUND  = -32004;

type
  /// <summary>
  /// Supported JSON schema types for tool parameters.
  /// </summary>
  TMCPParamType = (
    ptString,
    ptInteger,
    ptNumber,
    ptBoolean,
    ptObject,
    ptArray
  );

  /// <summary>
  /// Describes a single input parameter for an MCP tool.
  /// </summary>
  TMCPToolParam = record
    Name: string;
    Description: string;
    ParamType: TMCPParamType;
    Required: Boolean;

    class function Create(
      const AName, ADescription: string;
      AType: TMCPParamType = ptString;
      ARequired: Boolean = True): TMCPToolParam; static;

    /// <summary>Returns the JSON Schema type string.</summary>
    function TypeName: string;
  end;

  /// <summary>
  /// Legacy tool handler callback - returns a plain string.
  /// The string can be plain text or a JSON payload; it is sent as text content.
  /// New code should prefer TMCPToolResultCallback (rich content + error flag).
  /// </summary>
  TMCPToolCallback = reference to function(const Args: TJsonObject): string;

  /// <summary>
  /// Full definition of an MCP tool (name, description, params, handlers).
  ///
  /// ResultCallback takes precedence over Callback when both are set.
  /// Use ResultCallback for rich content (image, audio, embedded resource)
  /// or for explicit isError signalling.
  /// </summary>
  TMCPToolDef = record
    Name: string;
    Description: string;
    Params: TArray<TMCPToolParam>;
    Callback: TMCPToolCallback;            // legacy string callback
    ResultCallback: TMCPToolResultCallback; // rich result callback (preferred)
  end;

  /// <summary>
  /// JSON-RPC 2.0 response builder.
  /// All methods produce a self-contained JSON string ready to send.
  ///
  /// The JSON-RPC "id" (string | number | null) is represented as a
  /// standalone TJsonDataValueHelper instead of a class hierarchy (unlike
  /// System.JSON's TJSONValue, DextJsonDataObjects has no loose polymorphic
  /// value type outside TJsonObject/TJsonArray). Pass a literal "nil" for a
  /// missing/absent id - it resolves via the Pointer Implicit operator into
  /// a value whose IsNull is True, same as an id that came back explicitly
  /// null (the parser represents both the same way; see GetId below).
  /// </summary>
  TJsonRpc = class
  public
    /// <summary>
    /// Builds a success response.
    /// ResultJson is a raw JSON string that will be embedded as the "result" value.
    /// </summary>
    class function Success(const Id: TJsonDataValueHelper; const ResultJson: string): string; overload;

    /// <summary>
    /// Builds a success response from an already-built TJsonObject.
    /// Ownership of ResultObj is NOT taken - caller still frees it.
    /// </summary>
    class function Success(const Id: TJsonDataValueHelper; const ResultObj: TJsonObject): string; overload;

    /// <summary>
    /// Builds an error response.
    /// </summary>
    class function Error(const Id: TJsonDataValueHelper; Code: Integer; const Msg: string): string;

    /// <summary>
    /// Extracts the "id" field from a JSON-RPC request object.
    /// Returns a value whose IsNull is True if the "id" key is absent
    /// (i.e. it is a notification) - the same as if "id" were present but
    /// explicitly null, since DextJsonDataObjects' parser represents a
    /// literal JSON null the same way it represents "nothing stored here".
    /// </summary>
    class function GetId(const Req: TJsonObject): TJsonDataValueHelper;
  end;

implementation

{ TMCPToolParam }

class function TMCPToolParam.Create(const AName, ADescription: string;
  AType: TMCPParamType; ARequired: Boolean): TMCPToolParam;
begin
  Result.Name        := AName;
  Result.Description := ADescription;
  Result.ParamType   := AType;
  Result.Required    := ARequired;
end;

function TMCPToolParam.TypeName: string;
begin
  case ParamType of
    ptString:  Result := 'string';
    ptInteger: Result := 'integer';
    ptNumber:  Result := 'number';
    ptBoolean: Result := 'boolean';
    ptObject:  Result := 'object';
    ptArray:   Result := 'array';
  else
    Result := 'string';
  end;
end;

{ TJsonRpc }

class function TJsonRpc.Success(const Id: TJsonDataValueHelper; const ResultJson: string): string;
var
  Parsed: TJsonBaseObject;
  Obj: TJsonObject;
begin
  // TJsonBaseObject.Parse raises on syntactically invalid input instead of
  // returning nil (unlike System.JSON's ParseJSONValue) - swallow it the
  // same way the original fallback treated "not parseable" (embed the raw
  // string as-is).
  try
    Parsed := TJsonBaseObject.Parse(ResultJson);
  except
    Parsed := nil;
  end;

  Obj := TJsonObject.Create;
  try
    Obj.S['jsonrpc'] := MCP_JSONRPC_VERSION;
    // Values[Name] := Id clones the value (or copies the primitive) rather
    // than aliasing it, even when Id is a live reference into a request
    // object that outlives or outlasts this call - see SetInternValue.
    Obj.Values['id'] := Id;

    if Parsed = nil then
      Obj.S['result'] := ResultJson
    else if Parsed is TJsonObject then
      // Transfers ownership of Parsed into Obj - no separate Free needed.
      Obj.Values['result'] := TJsonObject(Parsed)
    else if Parsed is TJsonArray then
      Obj.Values['result'] := TJsonArray(Parsed)
    else
      Parsed.Free;

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TJsonRpc.Success(const Id: TJsonDataValueHelper; const ResultObj: TJsonObject): string;
var
  Obj: TJsonObject;
begin
  Obj := TJsonObject.Create;
  try
    Obj.S['jsonrpc'] := MCP_JSONRPC_VERSION;
    Obj.Values['id'] := Id;

    if ResultObj <> nil then
      // Clones ResultObj (Values[] copies rather than transfers when the
      // source is a standalone/foreign object) - caller retains ownership,
      // matching the original TJSONValue.Clone contract.
      Obj.O['result'] := ResultObj.Clone as TJsonObject
    else
      Obj.O['result'] := TJsonObject.Create;

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TJsonRpc.Error(const Id: TJsonDataValueHelper; Code: Integer; const Msg: string): string;
var
  Obj, ErrObj: TJsonObject;
begin
  Obj := TJsonObject.Create;
  try
    Obj.S['jsonrpc'] := MCP_JSONRPC_VERSION;
    Obj.Values['id'] := Id;

    ErrObj := Obj.O['error'];
    ErrObj.I['code']    := Code;
    ErrObj.S['message'] := Msg;

    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

class function TJsonRpc.GetId(const Req: TJsonObject): TJsonDataValueHelper;
begin
  if (Req = nil) or not Req.Contains('id') then
    Result := nil
  else
    Result := Req.Values['id'];
end;

end.
