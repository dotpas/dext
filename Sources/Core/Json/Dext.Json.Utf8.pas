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
{  Created: 2025-12-19                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Json.Utf8;

interface

uses
  System.Classes,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Core.Span,
  Dext.Json.Types;

type
  /// <summary>Non-capturing byte sink used by the direct UTF-8 writer.</summary>
  TUtf8WriteProc = procedure(AContext, AData: Pointer; ALength: Integer);

  /// <summary>
  ///   Exception type for JSON parsing and processing errors.
  /// </summary>
  EJsonException = class(Exception);

  /// <summary>
  ///   Defines the various JSON token types encountered during parsing.
  /// </summary>
  TJsonTokenType = (
    None,
    StartObject,    // {
    EndObject,      // }
    StartArray,     // [
    EndArray,       // ]
    PropertyName,   // "key": ...
    StringValue,    // "value"
    Number,         // 123.45
    TrueValue,      // true
    FalseValue,     // false
    NullValue,      // null
    Comment         // // or /* ... */ (if supported later)
  );

  /// <summary>
  ///   High-performance, forward-only, zero-allocation JSON reader for UTF-8 text.
  ///   Operates directly on a TByteSpan (ReadOnlySpan of bytes), avoiding string allocations during parsing.
  /// </summary>
  TUtf8JsonReader = record
  private
    FData: TByteSpan;
    FPtr: PByte;
    FEnd: PByte;
    FStart: PByte;
    FCurrentToken: TJsonTokenType;
    FValueSpan: TByteSpan;
    FHasValue: Boolean;

    procedure SkipWhitespace;
    function ConsumeString: TByteSpan;
    function ConsumeNumber: TByteSpan;
    function ConsumeLiteral(const ALiteral: string): Boolean;
    procedure ThrowJsonError(const AMessage: string);
  public
    /// <summary>
    ///   Initializes the reader with the JSON data.
    /// </summary>
    constructor Create(const AData: TByteSpan);

    /// <summary>Reads the next token from the JSON source. Returns True if a token was read, False if end of data.</summary>
    function Read: Boolean;

    /// <summary>
    ///   Skips the children of the current token (e.g., skips an entire object or array).
    /// </summary>
    procedure Skip;

    /// <summary>Type of the current token (StartObject, PropertyName, String, etc.).</summary>
    property TokenType: TJsonTokenType read FCurrentToken;

    /// <summary>
    ///   Span of raw bytes representing the current token value.
    ///   For strings, returns the inner content (without quotes).
    /// </summary>
    property ValueSpan: TByteSpan read FValueSpan;

    // --- Typed Getters (Perform conversion on demand) ---

    /// <summary>
    ///   Gets the value as a Delphi string (UTF-16). Allocates memory.
    /// </summary>
    function GetString: string;

    function GetInt32: Integer;
    function GetInt64: Int64;
    function GetDouble: Double;
    function GetBoolean: Boolean;
    
    /// <summary>
    ///   Checks if the current PropertyName matches the specified string (case-sensitive by default).
    ///   Optimized to compare against bytes without converting key to string.
    /// </summary>
    function ValueSpanEquals(const AText: string): Boolean;
  end;

  /// <summary>
  ///   High-performance, forward-only JSON writer that records UTF-8 text directly to a Stream.
  ///   Minimizes memory usage by avoiding the creation of large intermediate string buffers.
  /// </summary>
  TUtf8JsonWriter = record
  private
    FStream: TStream;
    FSinkContext: Pointer;
    FSinkWrite: TUtf8WriteProc;
    FIndented: Boolean;
    FSettings: TJsonSettings;
    FNeedComma: array[0..63] of Boolean; // Max depth of 64
    FDepth: Integer;
    procedure WriteRaw(const S: string); inline;
    procedure WriteRawByte(B: Byte); inline;
    procedure WriteBytes(AData: Pointer; ALength: Integer); inline;
    procedure WriteEscapedStringContent(const AValue: string);
    procedure WriteIndent;
    procedure CheckComma;
  public
    constructor Create(AStream: TStream; AIndented: Boolean = False); overload;
    /// <summary>Creates a writer over a non-capturing direct byte sink.</summary>
    constructor Create(AContext: Pointer; AWrite: TUtf8WriteProc;
      AIndented: Boolean = False); overload;
    
    property Settings: TJsonSettings read FSettings write FSettings;
    
    procedure WriteStartObject;
    procedure WriteEndObject;
    procedure WriteStartArray;
    procedure WriteEndArray;
    
    procedure WritePropertyName(const AName: string);
    procedure WriteString(const AValue: string);
    procedure WriteNumber(AValue: Int64); overload;
    procedure WriteNumber(AValue: Double); overload;
    procedure WriteBoolean(AValue: Boolean);
    procedure WriteNull;
    
    /// <summary>Writes a raw TValue. Handles basic types.</summary>
    procedure WriteValue(const AValue: TValue);
  end;

function EscapeJsonString(const S: string): string;
function UnescapeJsonString(const S: string): string;
function GetJsonVal(const AVal: TValue): string; overload;
function GetJsonVal(const AVal: TValue; const ASettings: TJsonSettings): string; overload;

implementation

uses
  System.DateUtils,
  Dext.Core.Reflection,
  Dext.Json;

function EscapeJsonString(const S: string): string;
var
  I, Len, NeededEscapes, ResIndex: Integer;
  C: Char;
  PStr: PChar;
  PRes: PChar;
  HexStr: string;
begin
  Len := Length(S);
  if Len = 0 then
    Exit('');

  NeededEscapes := 0;
  PStr := PChar(S);
  for I := 0 to Len - 1 do
  begin
    C := PStr[I];
    if (C = '"') or (C = '\') or (C = '/') or (Ord(C) < 32) then
      Inc(NeededEscapes);
  end;

  if NeededEscapes = 0 then
    Exit(S);

  SetLength(Result, Len + NeededEscapes * 5);
  PRes := PChar(Result);
  ResIndex := 0;

  for I := 0 to Len - 1 do
  begin
    C := PStr[I];
    case C of
      '"':
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := '"';
          Inc(ResIndex, 2);
        end;
      '\':
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := '\';
          Inc(ResIndex, 2);
        end;
      '/':
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := '/';
          Inc(ResIndex, 2);
        end;
      #8:
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := 'b';
          Inc(ResIndex, 2);
        end;
      #9:
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := 't';
          Inc(ResIndex, 2);
        end;
      #10:
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := 'n';
          Inc(ResIndex, 2);
        end;
      #12:
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := 'f';
          Inc(ResIndex, 2);
        end;
      #13:
        begin
          PRes[ResIndex] := '\';
          PRes[ResIndex + 1] := 'r';
          Inc(ResIndex, 2);
        end;
    else
      if Ord(C) < 32 then
      begin
        PRes[ResIndex] := '\';
        PRes[ResIndex + 1] := 'u';
        PRes[ResIndex + 2] := '0';
        PRes[ResIndex + 3] := '0';
        HexStr := Format('%.2x', [Ord(C)]);
        PRes[ResIndex + 4] := HexStr[1];
        PRes[ResIndex + 5] := HexStr[2];
        Inc(ResIndex, 6);
      end
      else
      begin
        PRes[ResIndex] := C;
        Inc(ResIndex);
      end;
    end;
  end;

  SetLength(Result, ResIndex);
end;

function UnescapeJsonString(const S: string): string;
var
  i: Integer;
  c: Char;
  IsEscaped: Boolean;
begin
  if Pos('\', S) = 0 then
    Exit(S);

  Result := '';
  IsEscaped := False;
  i := 1;
  while i <= Length(S) do
  begin
    c := S[i];
    if IsEscaped then
    begin
      case c of
        '"': Result := Result + '"';
        '\': Result := Result + '\';
        '/': Result := Result + '/';
        'b': Result := Result + #8;
        't': Result := Result + #9;
        'n': Result := Result + #10;
        'f': Result := Result + #12;
        'r': Result := Result + #13;
        'u':
          begin
            if i + 4 <= Length(S) then
            begin
              Result := Result + Char(StrToInt('$' + Copy(S, i + 1, 4)));
              Inc(i, 4);
            end;
          end;
      end;
      IsEscaped := False;
    end
    else if c = '\' then
      IsEscaped := True
    else
      Result := Result + c;
    Inc(i);
  end;
end;

function GetJsonVal(const AVal: TValue; const ASettings: TJsonSettings): string;
var
  Unwrapped: TValue;
begin
   if AVal.IsEmpty then Exit('null');

   // Handle Smart Properties (Prop<T>, Nullable<T>, etc.)
   if TReflection.TryUnwrapProp(AVal, Unwrapped) then
   begin
     Result := GetJsonVal(Unwrapped, ASettings);
     Exit;
   end;

   // Try to use framework serializer for other complex types (objects/arrays/interfaces)
   if AVal.Kind in [tkRecord, tkMRecord, tkDynArray, tkArray, tkClass, tkInterface] then
   begin
     // For normal records/objects, delegate to Dext.Json
     Result := TDextJson.Serialize(AVal, ASettings);
     Exit;
   end;

   case AVal.Kind of
     tkInteger, tkInt64: Result := IntToStr(AVal.AsInt64);
     tkFloat:
     begin
       // A date as in Dext.Json: DateToISO8601 with its defaults put a 'Z' on
       // the local time
       if TJsonUtils.IsDateType(AVal.TypeInfo) then
       begin
         if TJsonUtils.IsNoDate(AVal.AsExtended, AVal.TypeInfo, ASettings) then
           Result := 'null'
         else
           Result := '"' + TJsonUtils.DateToJsonText(AVal.AsExtended, AVal.TypeInfo, ASettings) + '"';
       end
       else
         Result := FloatToStr(AVal.AsExtended, TFormatSettings.Invariant);
     end;
     tkString, tkUString, tkWString, tkChar, tkWChar: Result := '"' + EscapeJsonString(AVal.AsString) + '"';
     tkEnumeration:
       if AVal.TypeInfo = TypeInfo(Boolean) then
       begin
         if AVal.AsBoolean then
           Result := 'true'
         else
           Result := 'false';
       end
       else
       begin
         if ASettings.EnumStyle = TEnumStyle.AsNumber then
           Result := IntToStr(AVal.AsOrdinal)
         else
           Result := '"' + GetEnumName(AVal.TypeInfo, AVal.AsOrdinal) + '"';
       end;
   else
     Result := '"' + EscapeJsonString(AVal.ToString) + '"';
   end;
end;

function GetJsonVal(const AVal: TValue): string;
begin
  Result := GetJsonVal(AVal, TDextJson.GetDefaultSettings);
end;

{ TUtf8JsonReader }

constructor TUtf8JsonReader.Create(const AData: TByteSpan);
begin
  FData := AData;
  FStart := AData.Data;
  FPtr := AData.Data;
  FEnd := AData.Data + AData.Length;
  FCurrentToken := TJsonTokenType.None;
  FValueSpan := TByteSpan.Create(nil, 0);
  FHasValue := False;
end;

procedure TUtf8JsonReader.ThrowJsonError(const AMessage: string);
begin
  raise EJsonException.CreateFmt(
    '%s at position %d',
    [AMessage, FPtr - FStart]
  );
end;

procedure TUtf8JsonReader.SkipWhitespace;
begin
  while FPtr < FEnd do
  begin
    if (FPtr^ = $20) or (FPtr^ = $09) or (FPtr^ = $0A) or (FPtr^ = $0D) then
      Inc(FPtr)
    else
      Break;
  end;
end;

function TUtf8JsonReader.Read: Boolean;
var
  B: Byte;
  StrSpan: TByteSpan;
begin
  if FPtr >= FEnd then
  begin
    FCurrentToken := TJsonTokenType.None;
    Exit(False);
  end;

  SkipWhitespace;

  if FPtr >= FEnd then
  begin
    FCurrentToken := TJsonTokenType.None;
    Exit(False);
  end;

  B := FPtr^;

  // Handle separators that might appear before a token
  if (B = Ord(',')) or (B = Ord(':')) then
  begin
    Inc(FPtr);
    SkipWhitespace;
    if FPtr >= FEnd then
      ThrowJsonError('Unexpected end of JSON after separator');
    B := FPtr^;
  end;

  case Chr(B) of
    '{':
      begin
        FCurrentToken := TJsonTokenType.StartObject;
        FValueSpan := TByteSpan.Create(FPtr, 1);
        Inc(FPtr);
      end;
    '}':
      begin
        FCurrentToken := TJsonTokenType.EndObject;
        FValueSpan := TByteSpan.Create(FPtr, 1);
        Inc(FPtr);
      end;
    '[':
      begin
        FCurrentToken := TJsonTokenType.StartArray;
        FValueSpan := TByteSpan.Create(FPtr, 1);
        Inc(FPtr);
      end;
    ']':
      begin
        FCurrentToken := TJsonTokenType.EndArray;
        FValueSpan := TByteSpan.Create(FPtr, 1);
        Inc(FPtr);
      end;
    '"':
      begin
        StrSpan := ConsumeString;

        SkipWhitespace;
        // Check for colon
        if (FPtr < FEnd) and (FPtr^ = Ord(':')) then
        begin
          FCurrentToken := TJsonTokenType.PropertyName;
        end
        else
        begin
          FCurrentToken := TJsonTokenType.StringValue;
        end;

        FValueSpan := StrSpan;
      end;
    '-', '0'..'9':
      begin
        FCurrentToken := TJsonTokenType.Number;
        FValueSpan := ConsumeNumber;
      end;
    't':
      begin
        if ConsumeLiteral('true') then
        begin
          FCurrentToken := TJsonTokenType.TrueValue;
          FValueSpan := TByteSpan.Create(FPtr - 4, 4);
        end
        else
          ThrowJsonError('Invalid token (expected true)');
      end;
    'f':
      begin
        if ConsumeLiteral('false') then
        begin
          FCurrentToken := TJsonTokenType.FalseValue;
          FValueSpan := TByteSpan.Create(FPtr - 5, 5);
        end
        else
           ThrowJsonError('Invalid token (expected false)');
      end;
    'n':
      begin
        if ConsumeLiteral('null') then
        begin
          FCurrentToken := TJsonTokenType.NullValue;
          FValueSpan := TByteSpan.Create(FPtr - 4, 4);
        end
        else
           ThrowJsonError('Invalid token (expected null)');
      end;
    else
      ThrowJsonError('Invalid character: ' + Char(B));
  end;

  Result := True;
end;

function TUtf8JsonReader.ConsumeString: TByteSpan;
var
  StartPos: PByte;
  IsEscaped: Boolean;
  B: Byte;
begin
  Inc(FPtr); // Skip opening quote
  StartPos := FPtr;
  IsEscaped := False;

  while FPtr < FEnd do
  begin
    B := FPtr^;

    if IsEscaped then
    begin
      IsEscaped := False;
      Inc(FPtr);
      Continue;
    end;

    if B = Ord('\') then
    begin
      IsEscaped := True;
      Inc(FPtr);
      Continue;
    end;

    if B = Ord('"') then
    begin
      Result := TByteSpan.Create(StartPos, FPtr - StartPos);
      Inc(FPtr); // Skip closing quote
      Exit;
    end;

    Inc(FPtr);
  end;

  ThrowJsonError('Unterminated string');
end;

function TUtf8JsonReader.ConsumeNumber: TByteSpan;
var
  StartPos: PByte;
  B: Byte;
begin
  StartPos := FPtr;
  while FPtr < FEnd do
  begin
    B := FPtr^;
    if (B >= Ord('0')) and (B <= Ord('9')) or
       (B = Ord('.')) or (B = Ord('-')) or (B = Ord('+')) or
       (B = Ord('e')) or (B = Ord('E')) then
      Inc(FPtr)
    else
      Break;
  end;
  Result := TByteSpan.Create(StartPos, FPtr - StartPos);
end;

function TUtf8JsonReader.ConsumeLiteral(const ALiteral: string): Boolean;
var
  SpanToCheck: TByteSpan;
begin
  if FPtr + ALiteral.Length > FEnd then
    Exit(False);

  SpanToCheck := TByteSpan.Create(FPtr, ALiteral.Length);
  if SpanToCheck.EqualsString(ALiteral) then
  begin
    Inc(FPtr, ALiteral.Length);
    Result := True;
  end
  else
    Result := False;
end;

procedure TUtf8JsonReader.Skip;
var
  Depth: Integer;
begin
  if (FCurrentToken = TJsonTokenType.StartObject) or (FCurrentToken = TJsonTokenType.StartArray) then
  begin
    Depth := 1;
    while (Depth > 0) and Read do
    begin
      case FCurrentToken of
        TJsonTokenType.StartObject, TJsonTokenType.StartArray:
          Inc(Depth);
        TJsonTokenType.EndObject, TJsonTokenType.EndArray:
          Dec(Depth);
      end;
    end;
  end;
end;

function TUtf8JsonReader.GetString: string;
begin
  // Handle JSON escapes (\n, \", \uXXXX, etc.)
  Result := UnescapeJsonString(FValueSpan.ToString);
end;

function TUtf8JsonReader.GetInt32: Integer;
begin
  // Use Val or StrToInt on string representation? 
  // Optimization: Parse bytes directly
  // For now, convert to string then Int to be safe
  Result := StrToIntDef(FValueSpan.ToString, 0); 
end;

function TUtf8JsonReader.GetInt64: Int64;
begin
  Result := StrToInt64Def(FValueSpan.ToString, 0);
end;

function TUtf8JsonReader.GetDouble: Double;
var
  S: string;
  V: Double;
begin
  S := FValueSpan.ToString;
  if TryStrToFloat(S, V, TFormatSettings.Invariant) then
    Result := V
  else
    Result := 0.0;
end;

function TUtf8JsonReader.GetBoolean: Boolean;
begin
  Result := (FCurrentToken = TJsonTokenType.TrueValue);
end;

function TUtf8JsonReader.ValueSpanEquals(const AText: string): Boolean;
begin
  Result := FValueSpan.EqualsString(AText);
end;

{ TUtf8JsonWriter }

procedure WriteUtf8ToStream(AContext, AData: Pointer; ALength: Integer);
begin
  if ALength > 0 then
    TStream(AContext).WriteBuffer(AData^, ALength);
end;

constructor TUtf8JsonWriter.Create(AStream: TStream; AIndented: Boolean);
begin
  FStream := AStream;
  FSinkContext := AStream;
  FSinkWrite := WriteUtf8ToStream;
  FIndented := AIndented;
  // The global default (JsonDefaultSettings), like TDextJson.Serialize.
  FSettings := TDextJson.GetDefaultSettings;
  if AIndented then 
    FSettings.Formatting := TJsonFormatting.Indented;
  FDepth := 0;
  FillChar(FNeedComma, SizeOf(FNeedComma), 0);
end;

constructor TUtf8JsonWriter.Create(AContext: Pointer; AWrite: TUtf8WriteProc;
  AIndented: Boolean);
begin
  if not Assigned(AWrite) then
    raise EArgumentNilException.Create('AWrite');
  FStream := nil;
  FSinkContext := AContext;
  FSinkWrite := AWrite;
  FIndented := AIndented;
  // The global default (JsonDefaultSettings), like TDextJson.Serialize.
  FSettings := TDextJson.GetDefaultSettings;
  if AIndented then
    FSettings.Formatting := TJsonFormatting.Indented;
  FDepth := 0;
  FillChar(FNeedComma, SizeOf(FNeedComma), 0);
end;

procedure TUtf8JsonWriter.WriteBytes(AData: Pointer; ALength: Integer);
begin
  if ALength > 0 then
    FSinkWrite(FSinkContext, AData, ALength);
end;

procedure TUtf8JsonWriter.CheckComma;
begin
  if (FDepth > 0) and FNeedComma[FDepth - 1] then
    WriteRawByte(Ord(','));
  
  if FDepth > 0 then
    FNeedComma[FDepth - 1] := True;
end;

procedure TUtf8JsonWriter.WriteIndent;
var
  i: Integer;
begin
  if not FIndented then Exit;
  WriteRawByte(10); // LF
  for i := 0 to FDepth - 1 do
    WriteRaw('  ');
end;

procedure TUtf8JsonWriter.WriteRaw(const S: string);
var
  B: TBytes;
begin
  B := TEncoding.UTF8.GetBytes(S);
  if Length(B) > 0 then
    WriteBytes(@B[0], Length(B));
end;

procedure TUtf8JsonWriter.WriteRawByte(B: Byte);
begin
  WriteBytes(@B, 1);
end;

procedure TUtf8JsonWriter.WriteEscapedStringContent(const AValue: string);
var
  i: Integer;
  Character: Char;
  ByteValue: Byte;
  CodePoint: Cardinal;
  Utf8: array[0..3] of Byte;
  Utf8Length: Integer;
  OutputBuffer: array[0..255] of Byte;
  OutputCount: Integer;

  procedure FlushOutput;
  begin
    if OutputCount > 0 then
    begin
      WriteBytes(@OutputBuffer[0], OutputCount);
      OutputCount := 0;
    end;
  end;

  procedure AppendByte(AByte: Byte);
  begin
    if OutputCount = Length(OutputBuffer) then
      FlushOutput;
    OutputBuffer[OutputCount] := AByte;
    Inc(OutputCount);
  end;
begin
  OutputCount := 0;
  i := 1;
  while i <= Length(AValue) do
  begin
    Character := AValue[i];
    case Character of
      '"', '\':
        begin
          AppendByte(Ord('\'));
          AppendByte(Ord(Character));
        end;
      #8:
        begin
          AppendByte(Ord('\'));
          AppendByte(Ord('b'));
        end;
      #9:
        begin
          AppendByte(Ord('\'));
          AppendByte(Ord('t'));
        end;
      #10:
        begin
          AppendByte(Ord('\'));
          AppendByte(Ord('n'));
        end;
      #12:
        begin
          AppendByte(Ord('\'));
          AppendByte(Ord('f'));
        end;
      #13:
        begin
          AppendByte(Ord('\'));
          AppendByte(Ord('r'));
        end;
    else
      if Ord(Character) < 32 then
      begin
        AppendByte(Ord('\'));
        AppendByte(Ord('u'));
        AppendByte(Ord('0'));
        AppendByte(Ord('0'));
        ByteValue := Byte(Ord(Character) shr 4);
        if ByteValue < 10 then
          AppendByte(Ord('0') + ByteValue)
        else
          AppendByte(Ord('a') + ByteValue - 10);
        ByteValue := Byte(Ord(Character) and $0F);
        if ByteValue < 10 then
          AppendByte(Ord('0') + ByteValue)
        else
          AppendByte(Ord('a') + ByteValue - 10);
      end
      else
      begin
        CodePoint := Ord(Character);
        if CodePoint <= $7F then
          AppendByte(Byte(CodePoint))
        else
        begin
          if (CodePoint >= $D800) and (CodePoint <= $DBFF) and
             (i < Length(AValue)) and
             (Ord(AValue[i + 1]) >= $DC00) and
             (Ord(AValue[i + 1]) <= $DFFF) then
          begin
            CodePoint := $10000 + ((CodePoint - $D800) shl 10) +
              (Cardinal(Ord(AValue[i + 1])) - $DC00);
            Inc(i);
          end
          else if (CodePoint >= $D800) and (CodePoint <= $DFFF) then
            CodePoint := $FFFD;

          if CodePoint <= $7FF then
          begin
            Utf8[0] := $C0 or Byte(CodePoint shr 6);
            Utf8[1] := $80 or Byte(CodePoint and $3F);
            Utf8Length := 2;
          end
          else if CodePoint <= $FFFF then
          begin
            Utf8[0] := $E0 or Byte(CodePoint shr 12);
            Utf8[1] := $80 or Byte((CodePoint shr 6) and $3F);
            Utf8[2] := $80 or Byte(CodePoint and $3F);
            Utf8Length := 3;
          end
          else
          begin
            Utf8[0] := $F0 or Byte(CodePoint shr 18);
            Utf8[1] := $80 or Byte((CodePoint shr 12) and $3F);
            Utf8[2] := $80 or Byte((CodePoint shr 6) and $3F);
            Utf8[3] := $80 or Byte(CodePoint and $3F);
            Utf8Length := 4;
          end;
          for ByteValue := 0 to Utf8Length - 1 do
            AppendByte(Utf8[ByteValue]);
        end;
      end;
    end;
    Inc(i);
  end;
  FlushOutput;
end;

procedure TUtf8JsonWriter.WriteStartObject;
begin
  CheckComma;
  WriteIndent;
  WriteRawByte(Ord('{'));
  Inc(FDepth);
  FNeedComma[FDepth - 1] := False;
end;

procedure TUtf8JsonWriter.WriteEndObject;
begin
  Dec(FDepth);
  WriteIndent;
  WriteRawByte(Ord('}'));
  if FDepth > 0 then FNeedComma[FDepth - 1] := True;
end;

procedure TUtf8JsonWriter.WriteStartArray;
begin
  CheckComma;
  WriteIndent;
  WriteRawByte(Ord('['));
  Inc(FDepth);
  FNeedComma[FDepth - 1] := False;
end;

procedure TUtf8JsonWriter.WriteEndArray;
begin
  Dec(FDepth);
  WriteIndent;
  WriteRawByte(Ord(']'));
  if FDepth > 0 then FNeedComma[FDepth - 1] := True;
end;

procedure TUtf8JsonWriter.WritePropertyName(const AName: string);
begin
  CheckComma;
  WriteIndent;
  WriteRawByte(Ord('"'));
  WriteEscapedStringContent(AName);
  WriteRawByte(Ord('"'));
  WriteRawByte(Ord(':'));
  FNeedComma[FDepth - 1] := False; // Property written, next is value (no comma)
end;

procedure TUtf8JsonWriter.WriteString(const AValue: string);
begin
  CheckComma;
  WriteRawByte(Ord('"'));
  WriteEscapedStringContent(AValue);
  WriteRawByte(Ord('"'));
end;

procedure TUtf8JsonWriter.WriteNumber(AValue: Int64);
var
  Buffer: array[0..20] of Byte;
  Index: Integer;
  Magnitude: UInt64;
begin
  CheckComma;
  Index := Length(Buffer);
  if AValue < 0 then
    Magnitude := UInt64(-(AValue + 1)) + 1
  else
    Magnitude := UInt64(AValue);

  repeat
    Dec(Index);
    Buffer[Index] := Ord('0') + Byte(Magnitude mod 10);
    Magnitude := Magnitude div 10;
  until Magnitude = 0;

  if AValue < 0 then
  begin
    Dec(Index);
    Buffer[Index] := Ord('-');
  end;
  WriteBytes(@Buffer[Index], Length(Buffer) - Index);
end;

procedure TUtf8JsonWriter.WriteNumber(AValue: Double);
begin
  CheckComma;
  WriteRaw(FloatToStr(AValue, TFormatSettings.Invariant));
end;

procedure TUtf8JsonWriter.WriteBoolean(AValue: Boolean);
begin
  CheckComma;
  if AValue then
  begin
    WriteRawByte(Ord('t'));
    WriteRawByte(Ord('r'));
    WriteRawByte(Ord('u'));
    WriteRawByte(Ord('e'));
  end
  else
  begin
    WriteRawByte(Ord('f'));
    WriteRawByte(Ord('a'));
    WriteRawByte(Ord('l'));
    WriteRawByte(Ord('s'));
    WriteRawByte(Ord('e'));
  end;
end;

procedure TUtf8JsonWriter.WriteNull;
begin
  CheckComma;
  WriteRawByte(Ord('n'));
  WriteRawByte(Ord('u'));
  WriteRawByte(Ord('l'));
  WriteRawByte(Ord('l'));
end;

procedure TUtf8JsonWriter.WriteValue(const AValue: TValue);
var
  Unwrapped: TValue;
begin
  if AValue.IsEmpty then
  begin
    WriteNull;
    Exit;
  end;

  // Handle Smart Properties (Prop<T>, Nullable<T>, etc.)
  if TReflection.TryUnwrapProp(AValue, Unwrapped) then
  begin
    WriteValue(Unwrapped);
    Exit;
  end;

  case AValue.Kind of
    tkInteger, tkInt64: WriteNumber(AValue.AsInt64);
    tkFloat: 
      begin
        // A date as in Dext.Json: DateToISO8601 with its defaults put a 'Z'
        // on the local time
        if TJsonUtils.IsDateType(AValue.TypeInfo) then
        begin
          if TJsonUtils.IsNoDate(AValue.AsExtended, AValue.TypeInfo, FSettings) then
            WriteNull
          else
            WriteString(TJsonUtils.DateToJsonText(AValue.AsExtended, AValue.TypeInfo, FSettings));
        end
        else
          WriteNumber(AValue.AsType<Double>);
      end;
    tkString, tkUString, tkWString, tkLString, tkChar, tkWChar:
      WriteString(AValue.AsString);
    tkEnumeration:
      if AValue.TypeInfo = TypeInfo(Boolean) then
        WriteBoolean(AValue.AsBoolean)
      else
      begin
        if FSettings.EnumStyle = TEnumStyle.AsNumber then
          WriteNumber(AValue.AsOrdinal)
        else
          WriteString(GetEnumName(AValue.TypeInfo, AValue.AsOrdinal));
      end;
    tkDynArray:
      // A byte array: Base64. Any other array (and a byte array with
      // BytesAsBase64 off) through the full serializer, as for records below:
      // it was written as the text "(dynamic array [0..N] of T)".
      if FSettings.FBytesAsBase64 and TJsonUtils.IsBytesType(AValue.TypeInfo) then
        WriteString(TJsonUtils.BytesToBase64(PPointer(AValue.GetReferenceToRawData)^,
          DynArraySize(PPointer(AValue.GetReferenceToRawData)^)))
      else
      begin
        CheckComma;
        WriteRaw(TDextJson.Serialize(AValue, FSettings));
        if FDepth > 0 then
          FNeedComma[FDepth - 1] := True;
      end;
    tkClass, tkInterface:
      begin
        CheckComma;
        WriteIndent;
        // Delegate to full framework serializer to handle attributes, mapping and complex types
        WriteRaw(TDextJson.Serialize(AValue, FSettings));
      end;
    tkRecord, tkMRecord:
      begin
        CheckComma;
        // For normal records that are not SmartProps, use the full serializer
        // with this writer's settings, as for classes above
        WriteRaw(TDextJson.Serialize(AValue, FSettings));
        if FDepth > 0 then
          FNeedComma[FDepth - 1] := True;
      end;
  else
    WriteString(AValue.ToString);
  end;
end;

end.
