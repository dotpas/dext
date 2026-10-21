{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
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
{  Author:  Cesar Romero                                                    }
{  Created: 2025-12-08                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Web.Versioning;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Web.Interfaces;

type
  /// <summary>
  ///   Contract for reading the API version from an HTTP request.
  /// </summary>
  IApiVersionReader = Dext.Web.Interfaces.IApiVersionReader;

  /// <summary>
  ///   Version reader via Query String (e.g. ?api-version=1.0).
  /// </summary>
  TQueryStringApiVersionReader = class(TInterfacedObject, IApiVersionReader)
  private
    FParameterName: string;
  public
    constructor Create(const ParameterName: string = 'api-version');
    function Read(const Context: IHttpContext): string;
  end;

  /// <summary>
  ///   Version reader via HTTP Header (e.g. X-Version: 1.0).
  /// </summary>
  THeaderApiVersionReader = class(TInterfacedObject, IApiVersionReader)
  private
    FHeaderName: string;
  public
    constructor Create(const HeaderName: string = 'X-Version');
    function Read(const Context: IHttpContext): string;
  end;

  /// <summary>
  ///   Version reader via URL path prefix (e.g. /v1/api/users extracts "1").
  ///   Examines the first segment of the request path for a version prefix.
  /// </summary>
  /// <remarks>
  ///   The default prefix is "v", so paths like /v1/..., /v2.1/... are recognized.
  ///   Only the first path segment is examined to avoid false positives with
  ///   segments deeper in the URL (e.g. /api/v1/... would NOT match by default).
  ///   Use a TCompositeApiVersionReader to combine with other readers.
  /// </remarks>
  TPathApiVersionReader = class(TInterfacedObject, IApiVersionReader)
  private
    FPrefix: string;
  public
    /// <summary>Creates a path version reader with the specified prefix (default: "v").</summary>
    /// <param name="APrefix">
    ///   The case-insensitive prefix that identifies a version segment (e.g. "v" matches "v1", "v2.1").
    /// </param>
    constructor Create(const APrefix: string = 'v');
    function Read(const Context: IHttpContext): string;
  end;

  /// <summary>
  ///   Composite reader that attempts to extract the version from multiple sources in sequence.
  ///   Returns the first non-empty result found.
  /// </summary>
  TCompositeApiVersionReader = class(TInterfacedObject, IApiVersionReader)
  private
    FReaders: TArray<IApiVersionReader>;
  public
    constructor Create(const Readers: TArray<IApiVersionReader>);
    function Read(const Context: IHttpContext): string;
  end;

implementation

{ TQueryStringApiVersionReader }

constructor TQueryStringApiVersionReader.Create(const ParameterName: string);
begin
  inherited Create;
  FParameterName := ParameterName;
end;

function TQueryStringApiVersionReader.Read(const Context: IHttpContext): string;
begin
  if not Context.Request.Query.TryGetValue(FParameterName, Result) then
    Result := '';
end;

{ THeaderApiVersionReader }

constructor THeaderApiVersionReader.Create(const HeaderName: string);
begin
  inherited Create;
  FHeaderName := HeaderName;
end;

function THeaderApiVersionReader.Read(const Context: IHttpContext): string;
begin
  if Context.Request.Headers.ContainsKey(FHeaderName) then
    Result := Context.Request.Headers[FHeaderName]
  else
    Result := '';
end;

{ TPathApiVersionReader }

constructor TPathApiVersionReader.Create(const APrefix: string);
begin
  inherited Create;
  FPrefix := APrefix;
end;

function TPathApiVersionReader.Read(const Context: IHttpContext): string;
var
  Path, Segment: string;
  SlashPos: Integer;
begin
  Result := '';
  Path := Context.Request.Path;

  // Strip leading slash to get the first segment
  if (Path <> '') and (Path[1] = '/') then
    Path := Copy(Path, 2, Length(Path) - 1);

  if Path = '' then
    Exit;

  // Extract first segment (up to the next slash or end of string)
  SlashPos := Pos('/', Path);
  if SlashPos > 0 then
    Segment := Copy(Path, 1, SlashPos - 1)
  else
    Segment := Path;

  // Check if the segment starts with the configured prefix (case-insensitive)
  if (Length(Segment) > Length(FPrefix)) and
     SameText(Copy(Segment, 1, Length(FPrefix)), FPrefix) then
    Result := Copy(Segment, Length(FPrefix) + 1, Length(Segment) - Length(FPrefix));
end;

{ TCompositeApiVersionReader }

constructor TCompositeApiVersionReader.Create(const Readers: TArray<IApiVersionReader>);
begin
  inherited Create;
  FReaders := Readers;
end;

function TCompositeApiVersionReader.Read(const Context: IHttpContext): string;
var
  Reader: IApiVersionReader;
begin
  Result := '';
  for Reader in FReaders do
  begin
    Result := Reader.Read(Context);
    if Result <> '' then Exit;
  end;
end;

end.
