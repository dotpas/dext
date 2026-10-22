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

/// <summary>
///   Splits "Method @ File.cpp" / legacy "Method (File.cpp)" into columns.
///   AMethod is never a path; AFileName is a leaf like SmokeDeep.cpp (may be '').
/// </summary>
procedure SplitStackMethodAndFile(const ARaw: string; out AMethod, AFileName: string);

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

  // [0] Unit.Method + $XX (File.cpp) — C++ MAP: file without line
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*\(([^:\)]+\.(?:cpp|h|hpp|pas|cc|cxx))\)\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := Trim(Match.Groups[1].Value);
    AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    Exit(True);
  end;

  // [0] Class::Method @ File.cpp — C++ MAP (optional :line from GTest fallback)
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*@\s*([^@:\r\n]+\.(?:cpp|h|hpp|pas|cc|cxx))(?::(\d+))?\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(Trim(Match.Groups[1].Value));
    AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    if Match.Groups.Count >= 4 then
      AFrame.Line := StrToIntDef(Match.Groups[3].Value, 0);
    MarkResolved(AFrame);
    Exit(True);
  end;

  // [0] Class::Method (File.cpp) — legacy C++ MAP format
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*\(([^:\)]+\.(?:cpp|h|hpp|pas|cc|cxx))\)\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(Trim(Match.Groups[1].Value));
    AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    Exit(True);
  end;

  // [0] Unit.Method + $XX  — symbol+offset, no (file:line) from MAP
  Match := TRegEx.Match(ALine,
    '\[\s*\d+\s*\]\s*(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(Trim(Match.Groups[1].Value));
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

function TryParseBareSymbolFrame(const ALine: string; out AFrame: TDextStackFrame): Boolean;
var
  Match: TMatch;
  MethodPart, FilePart: string;
begin
  Result := False;
  // C++ MAP: "TFoo::Bar @ SmokeTestCase.cpp" (optional :line)
  Match := TRegEx.Match(ALine,
    '^(.+?)\s*@\s*([^@:\r\n]+\.(?:cpp|h|hpp|pas|cc|cxx))(?::(\d+))?\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(Trim(Match.Groups[1].Value));
    AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    if Match.Groups.Count >= 4 then
      AFrame.Line := StrToIntDef(Match.Groups[3].Value, 0);
    MarkResolved(AFrame);
    Exit(True);
  end;

  // Legacy: "TFoo::Bar + $83 (SmokeTestCase.cpp)" or "TFoo::Bar (SmokeTestCase.cpp)"
  Match := TRegEx.Match(ALine,
    '^(.+?)\s*(?:\+\s*\$[0-9A-Fa-f]+\s*)?\(([^:\)]+\.(?:cpp|h|hpp|pas|cc|cxx))\)\s*$',
    [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    MethodPart := Trim(Match.Groups[1].Value);
    FilePart := Trim(Match.Groups[2].Value);
    AFrame.MethodName := CleanStackMethodName(MethodPart);
    AFrame.FileName := TPath.GetFileName(FilePart);
    Exit(True);
  end;

  // "TFoo::Bar + $83" or Delphi-style "Unit.Method + $4BE"
  Match := TRegEx.Match(ALine,
    '^(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*$', [roIgnoreCase]);
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(Trim(Match.Groups[1].Value));
    Exit(True);
  end;

  // Bare "$XXXXXXXX" address (unresolved AddressInfo)
  Match := TRegEx.Match(ALine, '^\$[0-9A-Fa-f]{4,16}$');
  if Match.Success then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := ALine;
    Exit(True);
  end;

  // C++ qualified name without file hint
  if ALine.Contains('::') then
  begin
    InitFrame(AFrame, ALine);
    AFrame.MethodName := CleanStackMethodName(ALine);
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

/// <summary>GTest / compiler: "SmokeGTestDeep.cpp:24" or "Foo.cpp(24)" — location only.</summary>
function TryParseCppFileLineFrame(const ALine: string; out AFrame: TDextStackFrame): Boolean;
var
  Match: TMatch;
begin
  Result := False;
  Match := TRegEx.Match(ALine,
    '^([^:\(\r\n]+\.(?:cpp|h|hpp|cc|cxx)):(\d+)\s*$', [roIgnoreCase]);
  if not Match.Success then
    Match := TRegEx.Match(ALine,
      '^([^:\(\r\n]+\.(?:cpp|h|hpp|cc|cxx))\((\d+)\)\s*$', [roIgnoreCase]);
  if not Match.Success then
    Exit;
  InitFrame(AFrame, ALine);
  AFrame.FileName := TPath.GetFileName(Trim(Match.Groups[1].Value));
  AFrame.Line := StrToIntDef(Match.Groups[2].Value, 0);
  AFrame.MethodName := ''; { caller fills from test name }
  MarkResolved(AFrame);
  Result := True;
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
         TryParsePasColonFrame(Line, Frame) or
         TryParseCppFileLineFrame(Line, Frame) or
         TryParseBareSymbolFrame(Line, Frame) then
        List.Add(Frame)
      else
      begin
        InitFrame(Frame, Line);
        Frame.MethodName := Line;
        List.Add(Frame);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ CleanStackMethodName }

procedure SplitStackMethodAndFile(const ARaw: string; out AMethod, AFileName: string);
var
  Match: TMatch;
  S: string;
  AtPos: Integer;
  FileHint: string;
begin
  AMethod := '';
  AFileName := '';
  S := Trim(ARaw);
  if S = '' then
    Exit;
  // Drop leading "[n] "
  Match := TRegEx.Match(S, '^\[\s*\d+\s*\]\s*(.*)$');
  if Match.Success then
    S := Trim(Match.Groups[1].Value);

  // Preferred C++ MAP: "TFoo::Bar @ SmokeDeep.cpp" / "... @ File.cpp:24"
  AtPos := Pos(' @ ', S);
  if AtPos > 0 then
  begin
    AMethod := Trim(Copy(S, 1, AtPos - 1));
    FileHint := Trim(Copy(S, AtPos + 3, MaxInt));
    { Do NOT use TPath.GetFileName / ExtractFileName on "File.cpp:24" — Windows
      treats the colon as a drive separator and returns "24". }
    Match := TRegEx.Match(FileHint,
      '^(.*\.(?:cpp|h|hpp|pas|cc|cxx|c))(?::\d+)?$', [roIgnoreCase]);
    if Match.Success then
      FileHint := Trim(Match.Groups[1].Value);
    AtPos := FileHint.LastDelimiter('/\');
    if AtPos >= 0 then
      AFileName := FileHint.Substring(AtPos + 1)
    else
      AFileName := FileHint;
  end
  else
  begin
    // Legacy: "... (File.cpp)" at end
    Match := TRegEx.Match(S,
      '^(.+?)\s*\(([^:\)]+\.(?:cpp|h|hpp|pas|cc|cxx))\)\s*$', [roIgnoreCase]);
    if Match.Success then
    begin
      AMethod := Trim(Match.Groups[1].Value);
      AFileName := TPath.GetFileName(Trim(Match.Groups[2].Value));
    end
    else
      AMethod := S;
  end;

  AMethod := CleanStackMethodName(AMethod);
end;

function CleanStackMethodName(const AMethodName: string): string;
var
  Match: TMatch;
  AtPos, ParenPos: Integer;
begin
  Result := Trim(AMethodName);
  if Result = '' then
    Exit;
  // "TFoo::Bar @ File.cpp" (Pos is 1-based)
  AtPos := Pos(' @ ', Result);
  if AtPos > 0 then
    Result := Trim(Copy(Result, 1, AtPos - 1));
  // "TFoo::Bar + $83 (File.cpp)" / "Unit.Method + $4BE (Unit.pas)" → method only
  Match := TRegEx.Match(Result,
    '^(.+?)\s*\+\s*\$[0-9A-Fa-f]+\s*(?:\([^)]+\))?\s*$', [roIgnoreCase]);
  if Match.Success then
    Result := Trim(Match.Groups[1].Value);
  // "TFoo::Bar (File.cpp)" trailing file hint (legacy)
  Match := TRegEx.Match(Result, '^(.+?)\s*\([^)]+\.(?:cpp|h|hpp|pas|cc|cxx)\)\s*$', [roIgnoreCase]);
  if Match.Success then
    Result := Trim(Match.Groups[1].Value);
  // C++ args: "TFoo::Bar(int, char*)" → "TFoo::Bar"
  ParenPos := Pos('(', Result);
  if ParenPos > 0 then
    Result := Trim(Copy(Result, 1, ParenPos - 1));
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
