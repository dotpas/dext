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
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2026-10-13                                                      }
{                                                                           }
{  Dext.Testing.StackTrace - Stack Trace Capture, Filter and Parse          }
{                                                                           }
{  Provides a pluggable stack-trace provider for the testing framework,     }
{  plus helpers to filter noisy frames and parse common Delphi formats.     }
{                                                                           }
{***************************************************************************}

unit Dext.Testing.StackTrace;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.RegularExpressions,
  System.IOUtils,
  Dext.Core.Debug;

type
  /// <summary>
  ///   Supplies a stack trace string for a raised exception.
  /// </summary>
  IDextStackTraceProvider = interface
    ['{C9E532C9-C8F5-42E4-844C-DF3F8479A9CD}']
    function GetStackTrace(const E: Exception): string;
  end;

  /// <summary>
  ///   Default provider: uses Exception.StackTrace (Dext.Core.Debug hooks),
  ///   falling back to TStackTrace.Capture when empty.
  /// </summary>
  TDextDefaultStackTraceProvider = class(TInterfacedObject, IDextStackTraceProvider)
  public
    function GetStackTrace(const E: Exception): string;
  end;

  /// <summary>
  ///   One parsed frame from a multi-line stack dump.
  /// </summary>
  TDextStackFrame = record
    RawText: string;
    FileName: string;
    MethodName: string;
    Line: Integer;
    Resolved: Boolean;
  end;

  /// <summary>
  ///   Access to the current stack-trace provider used by the test runner.
  /// </summary>
  TDextStackTrace = class
  private
    class var FProvider: IDextStackTraceProvider;
  public
    class function GetProvider: IDextStackTraceProvider; static;
    class procedure SetProvider(const AProvider: IDextStackTraceProvider); static;
  end;

/// <summary>
///   Removes noisy frames (SysUtils, Rtti, Runner, Attributes, Dext.MM, FastMM).
///   If filtering would remove every line, returns the original stack.
/// </summary>
function FilterStackTrace(const AStack: string): string;

/// <summary>
///   Parses common Delphi stack-trace line formats into structured frames.
/// </summary>
function ParseStackFrames(const AStack: string; AMaxFrames: Integer = 100): TArray<TDextStackFrame>;

/// <summary>
///   Normalizes a stack string for display: unwraps {"raw":"..."} JSON and
///   turns escaped \r\n into real line breaks.
/// </summary>
function FormatStackTraceForDisplay(const AStack: string): string;

/// <summary>
///   Strips MAP offsets like " + $9" / " + $4BE" from a method/symbol name.
/// </summary>
function CleanStackMethodName(const AMethodName: string): string;

implementation

uses
  System.JSON;

const
  NoisyFrameTokens: array[0..5] of string = (
    'System.SysUtils',
    'System.Rtti',
    'Dext.Testing.Runner',
    'Dext.Testing.Attributes',
    'Dext.MM',
    'FastMM'
  );

{ Helpers }

function IsNoisyFrame(const ALine: string): Boolean;
var
  Token: string;
  Lower: string;
begin
  Result := False;
  if ALine = '' then
    Exit;
  Lower := ALine.ToLower;
  for Token in NoisyFrameTokens do
    if Lower.Contains(Token.ToLower) then
      Exit(True);
end;

procedure InitFrame(out AFrame: TDextStackFrame; const ARaw: string);
begin
  AFrame.RawText := ARaw;
  AFrame.FileName := '';
  AFrame.MethodName := '';
  AFrame.Line := 0;
  AFrame.Resolved := False;
end;

procedure MarkResolved(var AFrame: TDextStackFrame);
begin
  AFrame.Resolved := (AFrame.FileName <> '') and (AFrame.Line > 0);
end;

function TryParseIndexedFrame(const ALine: string; out AFrame: TDextStackFrame): Boolean;
var
  Match: TMatch;
begin
  Result := False;
  // [0] Unit.Method + $XX (File.pas:123)
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*\(([^:\)]+):(\d+)\)',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := Trim(Match.Groups[1].Value);
    AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    AFrame.Line := StrToIntDef(Match.Groups[3].Value, 0);
    MarkResolved(AFrame);
    Exit(True);
  end;

  // [0] Unit.Method (File.pas:123)  — without offset
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*\(([^:\)]+):(\d+)\)',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := Trim(Match.Groups[1].Value);
    AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    AFrame.Line := StrToIntDef(Match.Groups[3].Value, 0);
    MarkResolved(AFrame);
    Exit(True);
  end;

  // [0] Unit.Method + $XX  — symbol+offset, no (file:line) from MAP
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := Trim(Match.Groups[1].Value);
    Exit(True);
  end;

  // [0] Symbol  — unresolved / bare
  Match := TRegEx.Match(ALine, '\[\s*\d+\s*\]\s*(.+)$');
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(Trim(Match.Groups[1].Value));
    Exit(True);
  end;
end;

function TryParsePasParenFrame(const ALine: string; out AFrame: TDextStackFrame): Boolean;
var
  Match: TMatch;
begin
  // File.pas(123): Method
  Match := TRegEx.Match(ALine, '^(.+?\.pas)\((\d+)\):\s*(.*)$', [roIgnoreCase]);
  Result := Match.Success;
  if not Result then
    Exit;
  InitFrame(AFrame, ALine);
  AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[1].Value));
  AFrame.Line := StrToIntDef(Match.Groups[2].Value, 0);
  AFrame.MethodName := Trim(Match.Groups[3].Value);
  MarkResolved(AFrame);
end;

function TryParsePasColonFrame(const ALine: string; out AFrame: TDextStackFrame): Boolean;
var
  Match: TMatch;
begin
  // File.pas:123 Method
  Match := TRegEx.Match(ALine, '^(.+?\.pas):(\d+)\s+(.*)$', [roIgnoreCase]);
  Result := Match.Success;
  if not Result then
    Exit;
  InitFrame(AFrame, ALine);
  AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[1].Value));
  AFrame.Line := StrToIntDef(Match.Groups[2].Value, 0);
  AFrame.MethodName := Trim(Match.Groups[3].Value);
  MarkResolved(AFrame);
end;

{ TDextDefaultStackTraceProvider }

function TDextDefaultStackTraceProvider.GetStackTrace(const E: Exception): string;
begin
  Result := '';
  if E <> nil then
    Result := E.StackTrace;
  if Trim(Result) = '' then
    Result := TStackTrace.Capture;
end;

{ TDextStackTrace }

class function TDextStackTrace.GetProvider: IDextStackTraceProvider;
begin
  if FProvider = nil then
    FProvider := TDextDefaultStackTraceProvider.Create;
  Result := FProvider;
end;

class procedure TDextStackTrace.SetProvider(const AProvider: IDextStackTraceProvider);
begin
  FProvider := AProvider;
end;

{ FilterStackTrace }

function FilterStackTrace(const AStack: string): string;
var
  Lines, Kept: TArray<string>;
  Line: string;
  I, Count: Integer;
  SB: TStringBuilder;
begin
  Result := AStack;
  if Trim(AStack) = '' then
    Exit;

  Lines := AStack.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  SetLength(Kept, Length(Lines));
  Count := 0;
  for I := 0 to High(Lines) do
  begin
    Line := Lines[I];
    if Trim(Line) = '' then
      Continue;
    if IsNoisyFrame(Line) then
      Continue;
    Kept[Count] := Line;
    Inc(Count);
  end;

  if Count = 0 then
    Exit(AStack);

  SB := TStringBuilder.Create;
  try
    for I := 0 to Count - 1 do
    begin
      if I > 0 then
        SB.AppendLine;
      SB.Append(Kept[I]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ParseStackFrames }

function ParseStackFrames(const AStack: string; AMaxFrames: Integer): TArray<TDextStackFrame>;
var
  Lines: TArray<string>;
  Line: string;
  Frame: TDextStackFrame;
  List: TList<TDextStackFrame>;
  I: Integer;
  Normalized: string;
begin
  Result := nil;
  if AMaxFrames <= 0 then
    AMaxFrames := 100;

  Normalized := FormatStackTraceForDisplay(AStack);
  if Trim(Normalized) = '' then
    Exit;

  List := TList<TDextStackFrame>.Create;
  try
    Lines := Normalized.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    for I := 0 to High(Lines) do
    begin
      if List.Count >= AMaxFrames then
        Break;
      Line := Trim(Lines[I]);
      if Line = '' then
        Continue;

      if TryParseIndexedFrame(Line, Frame) or
         TryParsePasParenFrame(Line, Frame) or
         TryParsePasColonFrame(Line, Frame) then
        List.Add(Frame)
      else
      begin
        InitFrame(Frame, Line);
        List.Add(Frame);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ CleanStackMethodName }

function CleanStackMethodName(const AMethodName: string): string;
var
  Match: TMatch;
begin
  Result := Trim(AMethodName);
  if Result = '' then
    Exit;
  // "Unit.Method + $4BE" → "Unit.Method"
  Match := TRegEx.Match(Result, '^(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*$', [roIgnoreCase]);
  if Match.Success then
    Result := Trim(Match.Groups[1].Value);
end;

{ FormatStackTraceForDisplay }

function FormatStackTraceForDisplay(const AStack: string): string;
var
  JsonVal: TJSONValue;
  S: string;
begin
  Result := Trim(AStack);
  if Result = '' then
    Exit;

  S := Result;
  if S.StartsWith('{') and S.Contains('"raw"') then
  begin
    JsonVal := TJSONObject.ParseJSONValue(S);
    try
      if (JsonVal <> nil) and (JsonVal is TJSONObject) then
        if TJSONObject(JsonVal).TryGetValue<string>('raw', S) then
          Result := S;
    finally
      JsonVal.Free;
    end;
  end;

  Result := Result.Replace('\r\n', sLineBreak).Replace('\n', sLineBreak).Replace('\r', sLineBreak);
end;

initialization

finalization
  TDextStackTrace.SetProvider(nil);

end.
