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
{  Created: 2026-09-09                                                      }
{                                                                           }
{  HTMX request inspection and HTMX 4 multi-target partial responses.       }
{                                                                           }
{***************************************************************************}
unit Dext.Web.Htmx;

interface

uses
  System.SysUtils,
  Dext.Web.Interfaces;

type
  /// <summary>Describes how HTMX 4 intends to consume an HTTP response.</summary>
  THtmxRequestType = (hrtNone, hrtPartial, hrtFull);

  /// <summary>
  ///   Read-only view of HTMX request headers. Values are resolved once at
  ///   construction to avoid repeated dictionary lookups.
  /// </summary>
  THtmxRequest = record
  private
    FIsHtmx: Boolean;
    FRequestType: THtmxRequestType;
    FSource: string;
    FTarget: string;
    FCurrentUrl: string;
    FIsBoosted: Boolean;
    FIsHistoryRestore: Boolean;
    function GetIsPartial: Boolean;
    function GetIsFull: Boolean;
  public
    constructor Create(const ARequest: IHttpRequest);

    property IsHtmx: Boolean read FIsHtmx;
    property IsPartial: Boolean read GetIsPartial;
    property IsFull: Boolean read GetIsFull;
    property RequestType: THtmxRequestType read FRequestType;
    property Source: string read FSource;
    property Target: string read FTarget;
    property CurrentUrl: string read FCurrentUrl;
    property IsBoosted: Boolean read FIsBoosted;
    property IsHistoryRestore: Boolean read FIsHistoryRestore;
  end;

  /// <summary>Builds one or more HTMX 4 &lt;hx-partial&gt; response elements.</summary>
  IHtmxPartials = interface
    ['{A7C4E91B-3F28-4D6A-9B15-8E2C4F6A1D73}']
    /// <summary>Adds a partial addressed by an hx-target CSS selector.</summary>
    function Target(const ASelector, AHtml: string;
      const ASwap: string = ''): IHtmxPartials;
    /// <summary>Adds a partial addressed by its id shorthand.</summary>
    function Id(const AId, AHtml: string;
      const ASwap: string = ''): IHtmxPartials;
    /// <summary>Returns the generated HTML without changing ownership.</summary>
    function ToHtml: string;
    /// <summary>Returns the generated partial response as Dext's standard HTML result.</summary>
    function AsResult(AStatusCode: Integer = 200): IResult;
  end;

  /// <summary>Factory for HTMX request inspection and multi-target responses.</summary>
  Htmx = class
  public
    class function Request(const AContext: IHttpContext): THtmxRequest; static;
    class function Partials: IHtmxPartials; static;
  end;

implementation

uses
  Dext.Collections.Dict,
  Dext.Web.Results;

type
  THtmxPartials = class(TInterfacedObject, IHtmxPartials)
  private
    FBuilder: TStringBuilder;
    FHasPartials: Boolean;
    procedure AppendEscapedAttribute(const AValue: string);
    procedure AppendPartial(const ATargetAttribute, ATarget, AHtml, ASwap: string);
  public
    constructor Create;
    destructor Destroy; override;
    function Target(const ASelector, AHtml: string;
      const ASwap: string = ''): IHtmxPartials;
    function Id(const AId, AHtml: string;
      const ASwap: string = ''): IHtmxPartials;
    function ToHtml: string;
    function AsResult(AStatusCode: Integer = 200): IResult;
  end;

function HeaderValue(const AHeaders: IStringDictionary; const AName: string): string;
begin
  if AHeaders = nil then
    Exit('');
  Result := AHeaders.GetValue(AName);
end;

{ THtmxRequest }

constructor THtmxRequest.Create(const ARequest: IHttpRequest);
var
  Headers: IStringDictionary;
  RequestTypeHeader: string;
begin
  FIsHtmx := False;
  FRequestType := hrtNone;
  FSource := '';
  FTarget := '';
  FCurrentUrl := '';
  FIsBoosted := False;
  FIsHistoryRestore := False;

  if ARequest = nil then
    Exit;

  Headers := ARequest.Headers;
  FIsHtmx := SameText(HeaderValue(Headers, 'HX-Request'), 'true');
  FSource := HeaderValue(Headers, 'HX-Source');
  FTarget := HeaderValue(Headers, 'HX-Target');
  FCurrentUrl := HeaderValue(Headers, 'HX-Current-URL');
  FIsBoosted := SameText(HeaderValue(Headers, 'HX-Boosted'), 'true');
  FIsHistoryRestore := SameText(HeaderValue(Headers, 'HX-History-Restore-Request'), 'true');

  if not FIsHtmx then
    Exit;

  RequestTypeHeader := HeaderValue(Headers, 'HX-Request-Type');
  if SameText(RequestTypeHeader, 'partial') then
    FRequestType := hrtPartial
  else if SameText(RequestTypeHeader, 'full') then
    FRequestType := hrtFull;
end;

function THtmxRequest.GetIsPartial: Boolean;
begin
  Result := FRequestType = hrtPartial;
end;

function THtmxRequest.GetIsFull: Boolean;
begin
  Result := FRequestType = hrtFull;
end;

{ THtmxPartials }

constructor THtmxPartials.Create;
begin
  inherited Create;
  FBuilder := TStringBuilder.Create;
end;

destructor THtmxPartials.Destroy;
begin
  FBuilder.Free;
  inherited Destroy;
end;

procedure THtmxPartials.AppendEscapedAttribute(const AValue: string);
var
  I: Integer;
  C: Char;
begin
  for I := 1 to Length(AValue) do
  begin
    C := AValue[I];
    case C of
      '&': FBuilder.Append('&amp;');
      '"': FBuilder.Append('&quot;');
      '<': FBuilder.Append('&lt;');
      '>': FBuilder.Append('&gt;');
    else
      FBuilder.Append(C);
    end;
  end;
end;

procedure THtmxPartials.AppendPartial(const ATargetAttribute, ATarget, AHtml,
  ASwap: string);
begin
  if ATarget = '' then
    raise EArgumentException.Create('An HTMX partial target cannot be empty.');

  if FHasPartials then
    FBuilder.Append(sLineBreak);

  FBuilder.Append('<hx-partial ');
  FBuilder.Append(ATargetAttribute);
  FBuilder.Append('="');
  AppendEscapedAttribute(ATarget);
  FBuilder.Append('"');

  if ASwap <> '' then
  begin
    FBuilder.Append(' hx-swap="');
    AppendEscapedAttribute(ASwap);
    FBuilder.Append('"');
  end;

  FBuilder.Append('>');
  FBuilder.Append(AHtml);
  FBuilder.Append('</hx-partial>');
  FHasPartials := True;
end;

function THtmxPartials.Target(const ASelector, AHtml, ASwap: string): IHtmxPartials;
begin
  AppendPartial('hx-target', ASelector, AHtml, ASwap);
  Result := Self;
end;

function THtmxPartials.Id(const AId, AHtml, ASwap: string): IHtmxPartials;
begin
  AppendPartial('id', AId, AHtml, ASwap);
  Result := Self;
end;

function THtmxPartials.ToHtml: string;
begin
  Result := FBuilder.ToString;
end;

function THtmxPartials.AsResult(AStatusCode: Integer): IResult;
begin
  Result := Results.Html(ToHtml, AStatusCode);
end;

{ Htmx }

class function Htmx.Request(const AContext: IHttpContext): THtmxRequest;
begin
  if AContext = nil then
    Exit(THtmxRequest.Create(nil));

  Result := THtmxRequest.Create(AContext.Request);
end;

class function Htmx.Partials: IHtmxPartials;
begin
  Result := THtmxPartials.Create;
end;

end.
