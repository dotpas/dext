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
{  Created: 2026-06-17                                                      }
{                                                                           }
{  Zero-allocation incremental HTTP/1.1 parser.                             }
{                                                                           }
{***************************************************************************}
unit Dext.Server.Iocp.HttpParser;

interface

uses
  System.Classes,
  System.SysUtils,
  Dext.Collections.Dict,
  Dext.Server.Engine.Types;

type
  /// <summary>
  ///   Represents a header segment parsed from the raw receive buffer.
  /// </summary>
  THeaderSegment = record
    KeyStart: Integer;
    KeyLen: Integer;
    ValueStart: Integer;
    ValueLen: Integer;
  end;

  THeaderSegments = TArray<THeaderSegment>;

  /// <summary>
  ///   Outcome of TDextIocpHttpParser.TryParseRequestEx.
  /// </summary>
  TDextHttpParseResult = (
    hprIncomplete,            // more bytes are needed for the header block
    hprOk,
    hprBadRequest,            // 400: malformed request line, header or Content-Length
    hprHeadersTooLarge,       // 431: the header block exceeds the limit
    hprVersionNotSupported,   // 505: not HTTP/1.0 or HTTP/1.1
    hprNotImplemented         // 501: Transfer-Encoding (chunked bodies are not supported)
  );

  /// <summary>
  ///   What the connection handling needs to know about a parsed request.
  /// </summary>
  TDextHttpRequestInfo = record
    Http10: Boolean;
    ConnectionClose: Boolean;
    ConnectionKeepAlive: Boolean;
    ExpectContinue: Boolean;
  end;

  /// <summary>
  ///   Zero-allocation (on structural parsing) incremental HTTP/1.1 parser.
  /// </summary>
  TDextIocpHttpParser = record
  private
    class function FindByte(const ABuffer: TBytes; AStart, AEnd: Integer; AByte: Byte): Integer; static; inline;
    class function FindCRLF(const ABuffer: TBytes; AStart, AEnd: Integer): Integer; static; inline;
    class function GetMethodString(const ABuffer: TBytes; AStart, ALen: Integer): string; static; inline;
  public
    /// <summary>
    ///   Attempts to parse HTTP/1.1 request headers from a byte buffer.
    ///   Returns True if headers are complete and parsed successfully.
    ///   On success, returns the index where the body begins (ABodyOffset).
    /// </summary>
    class function TryParseRequest(
      const ABuffer: TBytes; 
      ALength: Integer;
      out AMethod: string;
      out APath: string;
      out AQuery: string;
      out AHeaderSegments: THeaderSegments;
      out ABodyOffset: Integer;
      out AContentLength: Int64
    ): Boolean; static;

    /// <summary>
    ///   Like TryParseRequest, with the checks a server facing the network needs
    ///   (RFC 9112): a malformed request line or header line, whitespace before
    ///   the colon, a Content-Length that is not digits only or repeated with a
    ///   different value, both Content-Length and Transfer-Encoding: rejected,
    ///   never "incomplete forever". AMaxHeaderSize (0 = no limit) bounds the
    ///   header block. AInfo carries the version and the Connection and Expect
    ///   headers.
    /// </summary>
    class function TryParseRequestEx(
      const ABuffer: TBytes;
      ALength: Integer;
      AMaxHeaderSize: Integer;
      out AMethod: string;
      out APath: string;
      out AQuery: string;
      out AHeaderSegments: THeaderSegments;
      out ABodyOffset: Integer;
      out AContentLength: Int64;
      out AInfo: TDextHttpRequestInfo
    ): TDextHttpParseResult; static;

    class function CompareBytesCI(const ABuffer: TBytes; AStart, ALen: Integer; const AStr: string): Boolean; static; inline;
  end;

implementation

{ TDextIocpHttpParser }

class function TDextIocpHttpParser.FindByte(const ABuffer: TBytes; AStart, AEnd: Integer; AByte: Byte): Integer;
begin
  Result := TDextHttpParserCommon.FindByte(ABuffer, AStart, AEnd, AByte);
end;

class function TDextIocpHttpParser.FindCRLF(const ABuffer: TBytes; AStart, AEnd: Integer): Integer;
begin
  Result := TDextHttpParserCommon.FindCRLF(ABuffer, AStart, AEnd);
end;

class function TDextIocpHttpParser.CompareBytesCI(const ABuffer: TBytes; AStart, ALen: Integer; const AStr: string): Boolean;
begin
  Result := TDextHttpParserCommon.CompareBytesCI(ABuffer, AStart, ALen, AStr);
end;

class function TDextIocpHttpParser.GetMethodString(const ABuffer: TBytes; AStart, ALen: Integer): string;
begin
  case ALen of
    3:
      if (ABuffer[AStart] = 71) and (ABuffer[AStart+1] = 69) and (ABuffer[AStart+2] = 84) then
        Exit('GET')
      else if (ABuffer[AStart] = 80) and (ABuffer[AStart+1] = 85) and (ABuffer[AStart+2] = 84) then
        Exit('PUT');
    4:
      if (ABuffer[AStart] = 80) and (ABuffer[AStart+1] = 79) and (ABuffer[AStart+2] = 83) and (ABuffer[AStart+3] = 84) then
        Exit('POST')
      else if (ABuffer[AStart] = 72) and (ABuffer[AStart+1] = 69) and (ABuffer[AStart+2] = 65) and (ABuffer[AStart+3] = 68) then
        Exit('HEAD');
    5:
      if (ABuffer[AStart] = 80) and (ABuffer[AStart+1] = 65) and (ABuffer[AStart+2] = 84) and (ABuffer[AStart+3] = 67) and (ABuffer[AStart+4] = 72) then
        Exit('PATCH');
    6:
      if (ABuffer[AStart] = 68) and (ABuffer[AStart+1] = 69) and (ABuffer[AStart+2] = 76) and (ABuffer[AStart+3] = 69) and (ABuffer[AStart+4] = 84) and (ABuffer[AStart+5] = 69) then
        Exit('DELETE');
    7:
      if (ABuffer[AStart] = 79) and (ABuffer[AStart+1] = 80) and (ABuffer[AStart+2] = 84) and (ABuffer[AStart+3] = 73) and (ABuffer[AStart+4] = 79) and (ABuffer[AStart+5] = 78) and (ABuffer[AStart+6] = 83) then
        Exit('OPTIONS');
  end;
  Result := TEncoding.UTF8.GetString(ABuffer, AStart, ALen);
end;

// True if the bytes are exactly AStr (ASCII, case-sensitive).
function SameBytes(const ABuffer: TBytes; AStart, ALen: Integer; const AStr: string): Boolean;
var
  I: Integer;
begin
  if ALen <> Length(AStr) then
    Exit(False);
  for I := 0 to ALen - 1 do
    if ABuffer[AStart + I] <> Ord(AStr[I + 1]) then
      Exit(False);
  Result := True;
end;

// True if the comma-separated header value contains AToken (case-insensitive).
function HasToken(const ABuffer: TBytes; AStart, ALen: Integer; const AToken: string): Boolean;
var
  I, TokStart, TokEnd, Stop: Integer;
begin
  Result := False;
  I := AStart;
  Stop := AStart + ALen;
  while I < Stop do
  begin
    while (I < Stop) and ((ABuffer[I] = 32) or (ABuffer[I] = 9) or (ABuffer[I] = 44)) do
      Inc(I);
    TokStart := I;
    while (I < Stop) and (ABuffer[I] <> 44) do
      Inc(I);
    TokEnd := I;
    while (TokEnd > TokStart) and ((ABuffer[TokEnd - 1] = 32) or (ABuffer[TokEnd - 1] = 9)) do
      Dec(TokEnd);
    if (TokEnd > TokStart) and
      TDextHttpParserCommon.CompareBytesCI(ABuffer, TokStart, TokEnd - TokStart, AToken) then
      Exit(True);
  end;
end;

class function TDextIocpHttpParser.TryParseRequestEx(
  const ABuffer: TBytes;
  ALength: Integer;
  AMaxHeaderSize: Integer;
  out AMethod: string;
  out APath: string;
  out AQuery: string;
  out AHeaderSegments: THeaderSegments;
  out ABodyOffset: Integer;
  out AContentLength: Int64;
  out AInfo: TDextHttpRequestInfo
): TDextHttpParseResult;
var
  HeaderEnd: Integer;
  I: Integer;
  LineStart: Integer;
  LineEnd: Integer;
  Space1: Integer;
  Space2: Integer;
  QueryStart: Integer;
  Colon: Integer;
  Seg: THeaderSegment;
  SegCount: Integer;
  PathStart, PathLen: Integer;
  HasLength: Boolean;
  HasTransferEncoding: Boolean;
  Len: Int64;
begin
  AMethod := '';
  APath := '';
  AQuery := '';
  ABodyOffset := -1;
  AContentLength := 0;
  AHeaderSegments := nil;
  AInfo := Default(TDextHttpRequestInfo);

  // 1. The end of the header block, within the limit
  HeaderEnd := -1;
  for I := 0 to ALength - 4 do
  begin
    if (ABuffer[I] = 13) and (ABuffer[I+1] = 10) and (ABuffer[I+2] = 13) and (ABuffer[I+3] = 10) then
    begin
      HeaderEnd := I;
      Break;
    end;
  end;
  if HeaderEnd = -1 then
  begin
    if (AMaxHeaderSize > 0) and (ALength > AMaxHeaderSize) then
      Exit(hprHeadersTooLarge);
    Exit(hprIncomplete);
  end;
  if (AMaxHeaderSize > 0) and (HeaderEnd + 4 > AMaxHeaderSize) then
    Exit(hprHeadersTooLarge);

  // 2. Request line: method SP target SP HTTP-version (the CRLF at HeaderEnd
  //    counts, so a request with no header lines is complete too)
  LineEnd := FindCRLF(ABuffer, 0, HeaderEnd + 2);
  if LineEnd = -1 then
    Exit(hprBadRequest);
  Space1 := FindByte(ABuffer, 0, LineEnd, 32);
  if Space1 <= 0 then
    Exit(hprBadRequest);
  Space2 := FindByte(ABuffer, Space1 + 1, LineEnd, 32);
  if (Space2 = -1) or (Space2 = Space1 + 1) then
    Exit(hprBadRequest);
  if FindByte(ABuffer, Space2 + 1, LineEnd, 32) <> -1 then
    Exit(hprBadRequest);
  if SameBytes(ABuffer, Space2 + 1, LineEnd - Space2 - 1, 'HTTP/1.1') then
    AInfo.Http10 := False
  else if SameBytes(ABuffer, Space2 + 1, LineEnd - Space2 - 1, 'HTTP/1.0') then
    AInfo.Http10 := True
  else if (LineEnd - Space2 - 1 >= 5) and SameBytes(ABuffer, Space2 + 1, 5, 'HTTP/') then
    Exit(hprVersionNotSupported)
  else
    Exit(hprBadRequest);

  AMethod := GetMethodString(ABuffer, 0, Space1);
  QueryStart := FindByte(ABuffer, Space1 + 1, Space2, 63); // '?'
  PathStart := Space1 + 1;
  if QueryStart <> -1 then
    PathLen := QueryStart - PathStart
  else
    PathLen := Space2 - PathStart;
  if (PathLen = 1) and (ABuffer[PathStart] = 47) then
    APath := '/'
  else
    APath := TEncoding.UTF8.GetString(ABuffer, PathStart, PathLen);
  if QueryStart <> -1 then
    AQuery := TEncoding.UTF8.GetString(ABuffer, QueryStart, Space2 - QueryStart);

  // 3. Header lines
  SegCount := 0;
  SetLength(AHeaderSegments, 16);
  HasLength := False;
  HasTransferEncoding := False;
  LineStart := LineEnd + 2;
  while LineStart < HeaderEnd do
  begin
    LineEnd := FindCRLF(ABuffer, LineStart, HeaderEnd + 2);
    if LineEnd = -1 then
      LineEnd := HeaderEnd;
    // obs-fold (a line starting with whitespace) is rejected (RFC 9112 5.2)
    if (ABuffer[LineStart] = 32) or (ABuffer[LineStart] = 9) then
      Exit(hprBadRequest);
    Colon := FindByte(ABuffer, LineStart, LineEnd, 58); // ':'
    if Colon <= LineStart then
      Exit(hprBadRequest);
    // no whitespace between the field name and the colon (RFC 9112 5.1)
    if (ABuffer[Colon - 1] = 32) or (ABuffer[Colon - 1] = 9) then
      Exit(hprBadRequest);

    Seg.KeyStart := LineStart;
    Seg.KeyLen := Colon - LineStart;
    Seg.ValueStart := Colon + 1;
    Seg.ValueLen := LineEnd - (Colon + 1);
    while (Seg.ValueLen > 0) and ((ABuffer[Seg.ValueStart] = 32) or (ABuffer[Seg.ValueStart] = 9)) do
    begin
      Inc(Seg.ValueStart);
      Dec(Seg.ValueLen);
    end;
    while (Seg.ValueLen > 0) and
      ((ABuffer[Seg.ValueStart + Seg.ValueLen - 1] = 32) or (ABuffer[Seg.ValueStart + Seg.ValueLen - 1] = 9)) do
      Dec(Seg.ValueLen);

    if SegCount >= Length(AHeaderSegments) then
      SetLength(AHeaderSegments, SegCount + 8);
    AHeaderSegments[SegCount] := Seg;
    Inc(SegCount);

    if CompareBytesCI(ABuffer, Seg.KeyStart, Seg.KeyLen, 'content-length') then
    begin
      // digits only, at most 18 of them; a repeat must carry the same value
      if (Seg.ValueLen = 0) or (Seg.ValueLen > 18) then
        Exit(hprBadRequest);
      Len := 0;
      for I := 0 to Seg.ValueLen - 1 do
      begin
        if (ABuffer[Seg.ValueStart + I] < 48) or (ABuffer[Seg.ValueStart + I] > 57) then
          Exit(hprBadRequest);
        Len := Len * 10 + (ABuffer[Seg.ValueStart + I] - 48);
      end;
      if HasLength and (Len <> AContentLength) then
        Exit(hprBadRequest);
      HasLength := True;
      AContentLength := Len;
    end
    else if CompareBytesCI(ABuffer, Seg.KeyStart, Seg.KeyLen, 'transfer-encoding') then
      HasTransferEncoding := True
    else if CompareBytesCI(ABuffer, Seg.KeyStart, Seg.KeyLen, 'connection') then
    begin
      if HasToken(ABuffer, Seg.ValueStart, Seg.ValueLen, 'close') then
        AInfo.ConnectionClose := True;
      if HasToken(ABuffer, Seg.ValueStart, Seg.ValueLen, 'keep-alive') then
        AInfo.ConnectionKeepAlive := True;
    end
    else if CompareBytesCI(ABuffer, Seg.KeyStart, Seg.KeyLen, 'expect') then
    begin
      if CompareBytesCI(ABuffer, Seg.ValueStart, Seg.ValueLen, '100-continue') then
        AInfo.ExpectContinue := True;
    end;

    LineStart := LineEnd + 2;
  end;

  // 4. Framing: a body with Transfer-Encoding is not supported here; with
  //    Content-Length too it is a smuggling attempt (RFC 9112 6.1)
  if HasTransferEncoding then
  begin
    if HasLength then
      Exit(hprBadRequest);
    Exit(hprNotImplemented);
  end;

  SetLength(AHeaderSegments, SegCount);
  ABodyOffset := HeaderEnd + 4;
  Result := hprOk;
end;

class function TDextIocpHttpParser.TryParseRequest(
  const ABuffer: TBytes; 
  ALength: Integer;
  out AMethod: string;
  out APath: string;
  out AQuery: string;
  out AHeaderSegments: THeaderSegments;
  out ABodyOffset: Integer;
  out AContentLength: Int64
): Boolean;
var
  HeaderEnd: Integer;
  I: Integer;
  LineStart: Integer;
  LineEnd: Integer;
  Space1: Integer;
  Space2: Integer;
  QueryStart: Integer;
  Colon: Integer;
  Seg: THeaderSegment;
  SegCount: Integer;
  PathStart, PathLen: Integer;
begin
  AMethod := '';
  APath := '';
  AQuery := '';
  ABodyOffset := -1;
  AContentLength := 0;
  SetLength(AHeaderSegments, 0);

  // 1. Locate the end of the headers (\r\n\r\n)
  HeaderEnd := -1;
  for I := 0 to ALength - 4 do
  begin
    if (ABuffer[I] = 13) and (ABuffer[I+1] = 10) and (ABuffer[I+2] = 13) and (ABuffer[I+3] = 10) then
    begin
      HeaderEnd := I;
      Break;
    end;
  end;

  if HeaderEnd = -1 then
    Exit(False); // Headers are incomplete

  // 2. Parse request line (first line)
  LineEnd := FindCRLF(ABuffer, 0, HeaderEnd);
  if LineEnd = -1 then Exit(False);

  Space1 := FindByte(ABuffer, 0, LineEnd, 32); // Space character
  if Space1 = -1 then Exit(False);

  Space2 := FindByte(ABuffer, Space1 + 1, LineEnd, 32);
  if Space2 = -1 then Exit(False);

  // Method (cached)
  AMethod := GetMethodString(ABuffer, 0, Space1);

  // URL / Path & Query
  QueryStart := FindByte(ABuffer, Space1 + 1, Space2, 63); // '?' character
  
  PathStart := Space1 + 1;
  if QueryStart <> -1 then
    PathLen := QueryStart - PathStart
  else
    PathLen := Space2 - PathStart;

  // Path raiz otimizado
  if (PathLen = 1) and (ABuffer[PathStart] = 47) then
    APath := '/'
  else
    APath := TEncoding.UTF8.GetString(ABuffer, PathStart, PathLen);

  if QueryStart <> -1 then
    AQuery := TEncoding.UTF8.GetString(ABuffer, QueryStart, Space2 - QueryStart)
  else
    AQuery := '';

  SegCount := 0;
  SetLength(AHeaderSegments, 16);

  // 3. Parse headers line by line
  LineStart := LineEnd + 2;
  while LineStart < HeaderEnd do
  begin
    LineEnd := FindCRLF(ABuffer, LineStart, HeaderEnd);
    if LineEnd = -1 then LineEnd := HeaderEnd;

    if LineEnd > LineStart then
    begin
      Colon := FindByte(ABuffer, LineStart, LineEnd, 58); // ':' character
      if Colon <> -1 then
      begin
        Seg.KeyStart := LineStart;
        Seg.KeyLen := Colon - LineStart;
        Seg.ValueStart := Colon + 1;
        Seg.ValueLen := LineEnd - (Colon + 1);

        // Skip leading space of value
        while (Seg.ValueLen > 0) and (ABuffer[Seg.ValueStart] = 32) do
        begin
          Inc(Seg.ValueStart);
          Dec(Seg.ValueLen);
        end;

        if SegCount >= Length(AHeaderSegments) then
          SetLength(AHeaderSegments, SegCount + 8);

        AHeaderSegments[SegCount] := Seg;
        Inc(SegCount);

        if CompareBytesCI(ABuffer, Seg.KeyStart, Seg.KeyLen, 'content-length') then
        begin
          AContentLength := 0;
          for I := 0 to Seg.ValueLen - 1 do
          begin
            if (ABuffer[Seg.ValueStart + I] >= 48) and (ABuffer[Seg.ValueStart + I] <= 57) then
              AContentLength := AContentLength * 10 + (ABuffer[Seg.ValueStart + I] - 48);
          end;
        end;
      end;
    end;

    LineStart := LineEnd + 2;
  end;

  SetLength(AHeaderSegments, SegCount);
  ABodyOffset := HeaderEnd + 4;
  Result := True;
end;

end.
