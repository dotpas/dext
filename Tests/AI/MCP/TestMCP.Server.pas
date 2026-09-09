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
{           software distributed under the LICENSE is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Unit Tests for TMCPServer.Dispatch (JSON-RPC id round-trip)              }
{                                                                           }
{  Dispatch is pure string-in/string-out with no HTTP dependency, so it     }
{  can be exercised directly. These tests exist specifically to catch a     }
{  regression in the System.JSON -> DextJsonDataObjects migration of the    }
{  JSON-RPC "id" field (string | number | null), since DextJsonDataObjects  }
{  has no loose polymorphic value type - TJsonRpc represents "id" as a      }
{  standalone TJsonDataValueHelper instead.                                 }
{                                                                           }
{***************************************************************************}
unit TestMCP.Server;

interface

uses
  System.SysUtils,
  DextJsonDataObjects,
  Dext.Testing,
  Dext.AI.MCP.Server,
  Dext.AI.MCP.Tools,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Protocol;

type
  [TestFixture('TMCPServer.Dispatch - JSON-RPC id round-trip')]
  TMCPDispatchTests = class
  private
    function ParseResponse(const AJson: string): TJsonObject;
  public
    [Test]
    procedure NumericId_EchoesAsNumberNotString;
    [Test]
    procedure StringId_EchoesAsString;
    [Test]
    procedure UnknownMethodNotification_NoIdMeansNoResponse;
    [Test]
    procedure UnknownMethodWithId_ReturnsMethodNotFoundError;
    [Test]
    procedure EmptyBody_ReturnsParseError;
    [Test]
    procedure InvalidJson_ReturnsParseError;
    [Test]
    procedure ToolsCall_RoundTripsRegisteredTool;
    [Test]
    procedure Initialize_NegotiatesProtocolVersionAndCreatesSession;
  end;

implementation

function TMCPDispatchTests.ParseResponse(const AJson: string): TJsonObject;
var
  Parsed: TJsonBaseObject;
begin
  Parsed := TJsonBaseObject.Parse(AJson);
  Should(Parsed is TJsonObject).BeTrue;
  Result := TJsonObject(Parsed);
end;

procedure TMCPDispatchTests.NumericId_EchoesAsNumberNotString;
var
  Server: TMCPServer;
  Response: string;
  Root: TJsonObject;
begin
  Server := TMCPServer.Create('test-server');
  try
    Response := Server.Dispatch('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
    Root := ParseResponse(Response);
    try
      Should(Root.Types['id'] = jdtInt).BeTrue;
      Should(Root.I['id']).Be(1);
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.StringId_EchoesAsString;
var
  Server: TMCPServer;
  Response: string;
  Root: TJsonObject;
begin
  Server := TMCPServer.Create('test-server');
  try
    Response := Server.Dispatch('{"jsonrpc":"2.0","id":"abc","method":"ping"}');
    Root := ParseResponse(Response);
    try
      Should(Root.Types['id'] = jdtString).BeTrue;
      Should(Root.S['id']).Be('abc');
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.UnknownMethodNotification_NoIdMeansNoResponse;
var
  Server: TMCPServer;
  Response: string;
begin
  Server := TMCPServer.Create('test-server');
  try
    // No "id" field at all - a JSON-RPC notification. Even for an unknown
    // method, the server must not reply.
    Response := Server.Dispatch('{"jsonrpc":"2.0","method":"notifications/whatever"}');
    Should(Response).Be('');
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.UnknownMethodWithId_ReturnsMethodNotFoundError;
var
  Server: TMCPServer;
  Response: string;
  Root, ErrObj: TJsonObject;
begin
  Server := TMCPServer.Create('test-server');
  try
    Response := Server.Dispatch('{"jsonrpc":"2.0","id":5,"method":"totally/unknown"}');
    Root := ParseResponse(Response);
    try
      Should(Root.Types['id'] = jdtInt).BeTrue;
      Should(Root.I['id']).Be(5);
      Should(Root.Types['error'] = jdtObject).BeTrue;
      ErrObj := Root.O['error'];
      Should(ErrObj.I['code']).Be(JSONRPC_METHOD_NOT_FOUND);
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.EmptyBody_ReturnsParseError;
var
  Server: TMCPServer;
  Response: string;
  Root, ErrObj: TJsonObject;
begin
  Server := TMCPServer.Create('test-server');
  try
    Response := Server.Dispatch('');
    Root := ParseResponse(Response);
    try
      Should(Root.Types['id'] = jdtObject).BeTrue; // explicit null
      Should(Root.O['id'] = nil).BeTrue;
      ErrObj := Root.O['error'];
      Should(ErrObj.I['code']).Be(JSONRPC_INVALID_REQUEST);
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.InvalidJson_ReturnsParseError;
var
  Server: TMCPServer;
  Response: string;
  Root, ErrObj: TJsonObject;
begin
  Server := TMCPServer.Create('test-server');
  try
    Response := Server.Dispatch('{not valid json');
    Root := ParseResponse(Response);
    try
      ErrObj := Root.O['error'];
      Should(ErrObj.I['code']).Be(JSONRPC_PARSE_ERROR);
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.ToolsCall_RoundTripsRegisteredTool;
var
  Server: TMCPServer;
  Response: string;
  Root, ResultObj: TJsonObject;
  ContentArr: TJsonArray;
begin
  Server := TMCPServer.Create('test-server');
  try
    Server.Tool('echo')
      .Description('Echoes text back')
      .Param('text', 'Text to echo', ptString)
      .OnCallResult(function(const Args: TJsonObject): TMCPToolResult
        begin
          Result := TMCPToolResult.Text('echo:' + Args.S['text']);
        end);

    Response := Server.Dispatch(
      '{"jsonrpc":"2.0","id":42,"method":"tools/call",' +
      '"params":{"name":"echo","arguments":{"text":"hi"}}}');
    Root := ParseResponse(Response);
    try
      Should(Root.I['id']).Be(42);
      Should(Root.Types['result'] = jdtObject).BeTrue;
      ResultObj := Root.O['result'];
      Should(ResultObj.Types['content'] = jdtArray).BeTrue;
      ContentArr := ResultObj.A['content'];
      Should(ContentArr.Count).Be(1);
      Should(ContentArr.O[0].S['text']).Be('echo:hi');
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMCPDispatchTests.Initialize_NegotiatesProtocolVersionAndCreatesSession;
var
  Server: TMCPServer;
  Response: string;
  Root, ResultObj: TJsonObject;
begin
  Server := TMCPServer.Create('test-server');
  try
    Response := Server.Dispatch(
      '{"jsonrpc":"2.0","id":1,"method":"initialize",' +
      '"params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"1.0"}}}');
    Root := ParseResponse(Response);
    try
      Should(Root.Types['result'] = jdtObject).BeTrue;
      ResultObj := Root.O['result'];
      Should(ResultObj.S['protocolVersion']).Be('2024-11-05');
    finally
      Root.Free;
    end;
  finally
    Server.Free;
  end;
end;

end.
