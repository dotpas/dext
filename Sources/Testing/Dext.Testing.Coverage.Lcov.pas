{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (c) 2024 Dext Framework                               }
{                                                                           }
{           https://github.com/dext-framework/dext                          }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Licensed under the Apache License, Version 2.0 (the "License");          }
{  you may not use this file except in compliance with the License.         }
{  You may obtain a copy of the License at                                  }
{                                                                           }
{      http://www.apache.org/licenses/LICENSE-2.0                           }
{                                                                           }
{  Unless required by applicable law or agreed to in writing, software      }
{  distributed under the License is distributed on an "AS IS" BASIS,        }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. }
{  See the License for the specific language governing permissions and      }
{  limitations under the License.                                           }
{                                                                           }
{***************************************************************************}

unit Dext.Testing.Coverage.Lcov;

interface

uses
  System.SysUtils;

type
  /// <summary>One DA record: a source line and how many times it was hit.</summary>
  TLcovLine = record
    Line: Integer;
    Hits: Integer;
  end;

  /// <summary>One SF record and the DA lines that belong to it.</summary>
  TLcovFile = record
    Path: string;
    Lines: TArray<TLcovLine>;
  end;

/// <summary>
///   Reads an LCOV trace. The slow part of Win64x coverage is llvm-cov writing
///   this file. The scan keeps the source string and grows only the result.
/// </summary>
function ParseLcov(const AText: string): TArray<TLcovFile>;

/// <summary>Reads APath as UTF-8 LCOV. A missing file returns an empty array.</summary>
function ParseLcovFile(const APath: string): TArray<TLcovFile>;

implementation

uses
  System.IOUtils;

function ParseLcov(const AText: string): TArray<TLcovFile>;
var
  PosIdx: Integer;
  Row: string;
  FileCount: Integer;
  Open: Boolean;
  BuildPath: string;
  BuildLines: TArray<TLcovLine>;
  BuildCount: Integer;
  Body: string;
  Comma: Integer;
  LineNum: Integer;
  Hits: Integer;

  function NextRow: Boolean;
  var
    StartPos: Integer;
    EndPos: Integer;
    TextLen: Integer;
  begin
    TextLen := Length(AText);
    if PosIdx > TextLen then
      Exit(False);
    StartPos := PosIdx;
    while (PosIdx <= TextLen) and (AText[PosIdx] <> #10) and (AText[PosIdx] <> #13) do
      Inc(PosIdx);
    EndPos := PosIdx;
    if (PosIdx <= TextLen) and (AText[PosIdx] = #13) then
      Inc(PosIdx);
    if (PosIdx <= TextLen) and (AText[PosIdx] = #10) then
      Inc(PosIdx);
    Row := Trim(Copy(AText, StartPos, EndPos - StartPos));
    Result := True;
  end;

  procedure AppendFile;
  begin
    if BuildPath = '' then
      Exit;
    if FileCount = Length(Result) then
    begin
      if FileCount = 0 then
        SetLength(Result, 4)
      else
        SetLength(Result, FileCount * 2);
    end;
    SetLength(BuildLines, BuildCount);
    Result[FileCount].Path := BuildPath;
    Result[FileCount].Lines := BuildLines;
    Inc(FileCount);
  end;

  procedure CloseFile;
  begin
    if not Open then
      Exit;
    AppendFile;
    Open := False;
    BuildPath := '';
    BuildCount := 0;
    BuildLines := nil;
  end;

  procedure AppendLine(ALine, AHits: Integer);
  begin
    if BuildCount = Length(BuildLines) then
    begin
      if BuildCount = 0 then
        SetLength(BuildLines, 16)
      else
        SetLength(BuildLines, BuildCount * 2);
    end;
    BuildLines[BuildCount].Line := ALine;
    BuildLines[BuildCount].Hits := AHits;
    Inc(BuildCount);
  end;

begin
  Result := nil;
  FileCount := 0;
  Open := False;
  BuildCount := 0;
  PosIdx := 1;
  while NextRow do
  begin
    if Row = '' then
      Continue;
    if Row.StartsWith('SF:') then
    begin
      CloseFile;
      BuildPath := Row.Substring(3).Trim;
      Open := BuildPath <> '';
    end
    else if SameText(Row, 'end_of_record') then
      CloseFile
    else if Open and Row.StartsWith('DA:') then
    begin
      Body := Row.Substring(3);
      Comma := Body.IndexOf(',');
      if Comma < 1 then
        Continue;
      LineNum := StrToIntDef(Body.Substring(0, Comma).Trim, 0);
      Hits := StrToIntDef(Body.Substring(Comma + 1).Trim, 0);
      if LineNum <= 0 then
        Continue;
      AppendLine(LineNum, Hits);
    end;
  end;
  CloseFile;
  SetLength(Result, FileCount);
end;

function ParseLcovFile(const APath: string): TArray<TLcovFile>;
begin
  if (APath = '') or not FileExists(APath) then
    Exit(nil);
  Result := ParseLcov(TFile.ReadAllText(APath));
end;

end.
