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
{    Rich content types for MCP tools, resources, and prompts.              }
{                                                                           }
{    TMCPToolResult supports multiple content items (text, image, audio,    }
{    embedded resource) and the isError flag, matching the MCP spec.        }
{                                                                           }
{  Usage:                                                                   }
{    // Simple text result                                                  }
{    Result := TMCPToolResult.Text('Hello, world!');                        }
{                                                                           }
{    // Error result                                                        }
{    Result := TMCPToolResult.Error('Item not found');                      }
{                                                                           }
{    // Multi-content result                                                }
{    var R := TMCPToolResult.Text('Here is the chart:');                    }
{    R.AddContent(TMCPContent.Image(Base64Data, 'image/png'));              }
{    Result := R;                                                           }
{                                                                           }
{***************************************************************************}
unit Dext.AI.MCP.Types;

interface

uses
  System.SysUtils,
  DextJsonDataObjects;

type
  /// <summary>Discriminated type tag for MCP content items.</summary>
  TMCPContentType = (mctText, mctImage, mctAudio, mctResource);

  /// <summary>
  /// A single content item - used inside TMCPToolResult and TMCPPromptMessage.
  ///
  /// Use the class factory methods to construct:
  ///   TMCPContent.Text('hello')
  ///   TMCPContent.Image(base64, 'image/png')
  ///   TMCPContent.Audio(base64, 'audio/mpeg')
  ///   TMCPContent.Resource('file:///doc.txt', 'contents...')
  /// </summary>
  TMCPContent = record
  private
    FContentType: TMCPContentType;
    // text
    FTextValue: string;
    // image / audio
    FData: string;
    FMimeType: string;
    // resource
    FResourceUri: string;
    FResourceText: string;
    FResourceBlob: string;
    FResourceMimeType: string;
  public
    class function Text(const AText: string): TMCPContent; static;
    class function Image(const ABase64Data, AMimeType: string): TMCPContent; static;
    class function Audio(const ABase64Data, AMimeType: string): TMCPContent; static;
    class function Resource(const AUri, AText: string;
      const AMimeType: string = ''): TMCPContent; static;
    class function ResourceBlob(const AUri, ABase64Blob: string;
      const AMimeType: string = 'application/octet-stream'): TMCPContent; static;

    function ToJSON: TJsonObject;

    property ContentType: TMCPContentType read FContentType;
    property TextValue: string read FTextValue;
    property Data: string read FData;
    property MimeType: string read FMimeType;
    property ResourceUri: string read FResourceUri;
    property ResourceText: string read FResourceText;
  end;

  /// <summary>
  /// Result returned by MCP tool callbacks.
  ///
  /// Factory methods:
  ///   TMCPToolResult.Text('plain text')          - success, one text item
  ///   TMCPToolResult.Error('something failed')   - error result
  ///   TMCPToolResult.Image(b64, 'image/png')     - success, one image item
  ///   TMCPToolResult.Audio(b64, 'audio/mpeg')    - success, one audio item
  ///   TMCPToolResult.Resource(uri, text)         - success, embedded resource
  ///
  /// Multiple content items:
  ///   var R := TMCPToolResult.Text('caption');
  ///   R.AddContent(TMCPContent.Image(b64, 'image/png'));
  /// </summary>
  TMCPToolResult = record
    Content: TArray<TMCPContent>;
    IsError: Boolean;

    class function Text(const AText: string): TMCPToolResult; static;
    class function Error(const AMessage: string): TMCPToolResult; static;
    class function Image(const ABase64Data, AMimeType: string): TMCPToolResult; static;
    class function Audio(const ABase64Data, AMimeType: string): TMCPToolResult; static;
    class function Resource(const AUri, AText: string;
      const AMimeType: string = ''): TMCPToolResult; static;

    /// <summary>Appends an additional content item to this result.</summary>
    procedure AddContent(const AContent: TMCPContent);

    /// <summary>Serialises to the MCP tools/call result JSON object.</summary>
    function ToJSON: TJsonObject;
  end;

  /// <summary>
  /// Rich tool callback - return TMCPToolResult instead of a plain string.
  /// Preferred over TMCPToolCallback for multi-content and error signalling.
  /// </summary>
  TMCPToolResultCallback = reference to function(
    const Args: TJsonObject): TMCPToolResult;

  // ---------------------------------------------------------------------------
  // Resource types
  // ---------------------------------------------------------------------------

  /// <summary>Contents returned by a resources/read call.</summary>
  TMCPResourceContents = record
    Uri: string;
    MimeType: string;
    TextContent: string;  // populated for text resources
    BlobContent: string;  // base64, populated for binary resources
    IsText: Boolean;

    class function TextResource(const AUri, AText: string;
      const AMimeType: string = 'text/plain'): TMCPResourceContents; static;
    class function BlobResource(const AUri, ABase64Blob: string;
      const AMimeType: string = 'application/octet-stream'): TMCPResourceContents; static;

    function ToJSON: TJsonObject;
  end;

  /// <summary>Callback invoked on resources/read - receives URI, returns contents.</summary>
  TMCPResourceReadCallback = reference to function(
    const AUri: string): TMCPResourceContents;

  // ---------------------------------------------------------------------------
  // Prompt types
  // ---------------------------------------------------------------------------

  /// <summary>A single message in a prompt template result.</summary>
  TMCPPromptMessage = record
    Role: string;          // 'user' | 'assistant'
    Content: TMCPContent;

    class function User(const AText: string): TMCPPromptMessage; static;
    class function Assistant(const AText: string): TMCPPromptMessage; static;
    class function UserImage(const ABase64Data, AMimeType: string): TMCPPromptMessage; static;

    function ToJSON: TJsonObject;
  end;

  /// <summary>Full result from a prompts/get call.</summary>
  TMCPPromptResult = record
    Description: string;
    Messages: TArray<TMCPPromptMessage>;

    class function Create(const ADescription: string = ''): TMCPPromptResult; static;
    procedure AddMessage(const AMessage: TMCPPromptMessage);
    function ToJSON: TJsonObject;
  end;

  /// <summary>Callback invoked on prompts/get - receives template arguments.</summary>
  TMCPPromptGetCallback = reference to function(
    const Args: TJsonObject): TMCPPromptResult;

implementation

{ TMCPContent }

class function TMCPContent.Text(const AText: string): TMCPContent;
begin
  Result := Default(TMCPContent);
  Result.FContentType := mctText;
  Result.FTextValue   := AText;
end;

class function TMCPContent.Image(const ABase64Data, AMimeType: string): TMCPContent;
begin
  Result := Default(TMCPContent);
  Result.FContentType := mctImage;
  Result.FData        := ABase64Data;
  Result.FMimeType    := AMimeType;
end;

class function TMCPContent.Audio(const ABase64Data, AMimeType: string): TMCPContent;
begin
  Result := Default(TMCPContent);
  Result.FContentType := mctAudio;
  Result.FData        := ABase64Data;
  Result.FMimeType    := AMimeType;
end;

class function TMCPContent.Resource(const AUri, AText: string;
  const AMimeType: string): TMCPContent;
begin
  Result := Default(TMCPContent);
  Result.FContentType    := mctResource;
  Result.FResourceUri    := AUri;
  Result.FResourceText   := AText;
  Result.FResourceMimeType := AMimeType;
end;

class function TMCPContent.ResourceBlob(const AUri, ABase64Blob: string;
  const AMimeType: string): TMCPContent;
begin
  Result := Default(TMCPContent);
  Result.FContentType    := mctResource;
  Result.FResourceUri    := AUri;
  Result.FResourceBlob   := ABase64Blob;
  Result.FResourceMimeType := AMimeType;
end;

function TMCPContent.ToJSON: TJsonObject;
var
  Res: TJsonObject;
  ResObj: TJsonObject;
begin
  Res := TJsonObject.Create;
  case FContentType of
    mctText:
    begin
      Res.S['type'] := 'text';
      Res.S['text'] := FTextValue;
    end;
    mctImage:
    begin
      Res.S['type'] := 'image';
      Res.S['data'] := FData;
      Res.S['mimeType'] := FMimeType;
    end;
    mctAudio:
    begin
      Res.S['type'] := 'audio';
      Res.S['data'] := FData;
      Res.S['mimeType'] := FMimeType;
    end;
    mctResource:
    begin
      Res.S['type'] := 'resource';
      // Res.O['resource'] auto-cria e já anexa o objeto vazio a Res — não
      // precisa de atribuição separada como em System.JSON's AddPair.
      ResObj := Res.O['resource'];
      ResObj.S['uri'] := FResourceUri;
      if FResourceMimeType <> '' then
        ResObj.S['mimeType'] := FResourceMimeType;
      if FResourceBlob <> '' then
        ResObj.S['blob'] := FResourceBlob
      else
        ResObj.S['text'] := FResourceText;
    end;
  end;
  Result := Res;
end;

{ TMCPToolResult }

class function TMCPToolResult.Text(const AText: string): TMCPToolResult;
begin
  Result := Default(TMCPToolResult);
  Result.IsError := False;
  SetLength(Result.Content, 1);
  Result.Content[0] := TMCPContent.Text(AText);
end;

class function TMCPToolResult.Error(const AMessage: string): TMCPToolResult;
begin
  Result := Default(TMCPToolResult);
  Result.IsError := True;
  SetLength(Result.Content, 1);
  Result.Content[0] := TMCPContent.Text(AMessage);
end;

class function TMCPToolResult.Image(const ABase64Data, AMimeType: string): TMCPToolResult;
begin
  Result := Default(TMCPToolResult);
  Result.IsError := False;
  SetLength(Result.Content, 1);
  Result.Content[0] := TMCPContent.Image(ABase64Data, AMimeType);
end;

class function TMCPToolResult.Audio(const ABase64Data, AMimeType: string): TMCPToolResult;
begin
  Result := Default(TMCPToolResult);
  Result.IsError := False;
  SetLength(Result.Content, 1);
  Result.Content[0] := TMCPContent.Audio(ABase64Data, AMimeType);
end;

class function TMCPToolResult.Resource(const AUri, AText: string;
  const AMimeType: string): TMCPToolResult;
begin
  Result := Default(TMCPToolResult);
  Result.IsError := False;
  SetLength(Result.Content, 1);
  Result.Content[0] := TMCPContent.Resource(AUri, AText, AMimeType);
end;

procedure TMCPToolResult.AddContent(const AContent: TMCPContent);
begin
  SetLength(Content, Length(Content) + 1);
  Content[High(Content)] := AContent;
end;

function TMCPToolResult.ToJSON: TJsonObject;
var
  ContentArr: TJsonArray;
  Item: TMCPContent;
begin
  Result := TJsonObject.Create;
  ContentArr := Result.A['content'];
  for Item in Content do
    ContentArr.Add(Item.ToJSON);
  if IsError then
    Result.B['isError'] := True;
end;

{ TMCPResourceContents }

class function TMCPResourceContents.TextResource(const AUri, AText: string;
  const AMimeType: string): TMCPResourceContents;
begin
  Result := Default(TMCPResourceContents);
  Result.Uri         := AUri;
  Result.TextContent := AText;
  Result.MimeType    := AMimeType;
  Result.IsText      := True;
end;

class function TMCPResourceContents.BlobResource(const AUri, ABase64Blob: string;
  const AMimeType: string): TMCPResourceContents;
begin
  Result := Default(TMCPResourceContents);
  Result.Uri         := AUri;
  Result.BlobContent := ABase64Blob;
  Result.MimeType    := AMimeType;
  Result.IsText      := False;
end;

function TMCPResourceContents.ToJSON: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['uri'] := Uri;
  if MimeType <> '' then
    Result.S['mimeType'] := MimeType;
  if IsText then
    Result.S['text'] := TextContent
  else
    Result.S['blob'] := BlobContent;
end;

{ TMCPPromptMessage }

class function TMCPPromptMessage.User(const AText: string): TMCPPromptMessage;
begin
  Result := Default(TMCPPromptMessage);
  Result.Role    := 'user';
  Result.Content := TMCPContent.Text(AText);
end;

class function TMCPPromptMessage.Assistant(const AText: string): TMCPPromptMessage;
begin
  Result := Default(TMCPPromptMessage);
  Result.Role    := 'assistant';
  Result.Content := TMCPContent.Text(AText);
end;

class function TMCPPromptMessage.UserImage(const ABase64Data,
  AMimeType: string): TMCPPromptMessage;
begin
  Result := Default(TMCPPromptMessage);
  Result.Role    := 'user';
  Result.Content := TMCPContent.Image(ABase64Data, AMimeType);
end;

function TMCPPromptMessage.ToJSON: TJsonObject;
begin
  Result := TJsonObject.Create;
  Result.S['role'] := Role;
  Result.O['content'] := Content.ToJSON;
end;

{ TMCPPromptResult }

class function TMCPPromptResult.Create(const ADescription: string): TMCPPromptResult;
begin
  Result := Default(TMCPPromptResult);
  Result.Description := ADescription;
end;

procedure TMCPPromptResult.AddMessage(const AMessage: TMCPPromptMessage);
begin
  SetLength(Messages, Length(Messages) + 1);
  Messages[High(Messages)] := AMessage;
end;

function TMCPPromptResult.ToJSON: TJsonObject;
var
  MsgsArr: TJsonArray;
  Msg: TMCPPromptMessage;
begin
  Result := TJsonObject.Create;
  if Description <> '' then
    Result.S['description'] := Description;
  MsgsArr := Result.A['messages'];
  for Msg in Messages do
    MsgsArr.Add(Msg.ToJSON);
end;

end.
