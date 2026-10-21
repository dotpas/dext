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
unit Dext.Core.Json.NextGen;

{$POINTERMATH ON}
{$SCOPEDENUMS ON}

interface

uses
  System.Character,
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  Dext.Collections.Simd,
  Dext.Core.Span,
  Dext.Json.Types;

type
  EJsonException = class(Exception)
  end;

  /// <summary>
  ///   Exception raised when JSON syntax is invalid or maximum nesting depth is exceeded.
  /// </summary>
  EJsonParserException = class(EJsonException)
  end;

  IJSONBufferOwner = interface
    ['{E3C2A1B0-9F8E-7D6C-5B4A-3C2B1A0F9E8D}']
  end;

  TJSONBufferOwner = class(TInterfacedObject, IJSONBufferOwner)
  private
    FBytes: TBytes;
  public
    constructor Create(const ABytes: TBytes);
  end;

  IDextJsonNodeGetter = interface
    ['{E1B2C3D4-E5F6-7890-ABCD-EF1234567895}']
    function GetSelf: TObject;
  end;

  TJsonBaseObject = class(TObject, IInterface, IDextJsonNodeGetter)
  private
    FRefCounted: Boolean;
    FRefCount: Integer;
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    /// <summary>
    /// Switches this node (and nested object/array children) to manual TObject
    /// ownership so TObject.Free destroys the tree instead of returning nodes
    /// to the per-thread pool (pool residency shows up as FastMM leaks on
    /// Indy worker threads at process shutdown).
    /// </summary>
    procedure AdoptManualLifetime; virtual;
  public
    constructor Create(ARefCounted: Boolean = False);
    function GetSelf: TObject;
    class function Parse(const AJson: string): TJsonBaseObject; static;
    function ToJson(Indented: Boolean = False): string; virtual; abstract;
  end;

  TJsonObject = class;
  TJsonArray = class;

  TJsonKey = record
    Span: TByteSpan;
    StrValue: string;
    function ToString: string; inline;
    function EqualsString(const AText: string): Boolean; inline;
  end;

  /// <summary>
  ///   Representação leve e Zero-Allocation de um valor JSON.
  /// </summary>
  TNextGenJsonValue = record
  private
    FType: TDextJsonNodeType;
    FValueSpan: TByteSpan;
    FStrValue: PString;
    FStringDecoded: Boolean;
    FNodeRef: Pointer;
    function GetNodeRef: IDextJsonNode; inline;
    procedure SetNodeRef(const AValue: IDextJsonNode); inline;
  public
    procedure Init(AType: TDextJsonNodeType; const ASpan: TByteSpan);
    property NodeType: TDextJsonNodeType read FType;
    property ValueSpan: TByteSpan read FValueSpan;
    property NodeRef: IDextJsonNode read GetNodeRef write SetNodeRef;

    procedure SetStrValue(const S: string);
    procedure FreeNode; inline;
    function AsString: string;
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsDouble: Double;
    function AsBoolean: Boolean;
    function IsNull: Boolean;
  end;

  TNextGenJsonPair = record
    Key: TJsonKey;
    Value: TNextGenJsonValue;
  end;

  /// <summary>
  ///   Tabela de lookup de 256 bytes para validação léxica rápida.
  /// </summary>
  TJsonLookupTable = record
  public
    class var Structural: array[0..255] of Boolean;
    class var Whitespace: array[0..255] of Boolean;
    class constructor Create;
  end;

  /// <summary>
  ///   Parser JSON NextGen focado em Zero-Allocation e Spans.
  /// </summary>
  TNextGenJsonParser = record
  private
    FData: TByteSpan;
    FStart: PByte;
    FPtr: PByte;
    FEnd: PByte;
    FDepth: Integer;
    FMaxDepth: Integer;
    procedure CheckDepth; inline;
    procedure ScanString(var APtr: PByte); inline;
    class function ParseNumber(const ASpan: TByteSpan): Double; static;
    class function ParseInt64(const ASpan: TByteSpan): Int64; static;
    function ParseValue: TNextGenJsonValue;
    function ParseObject: IDextJsonObject;
    function ParseArray: IDextJsonArray;
  public
    // SIMD (SSE2) scan of a JSON string BODY: returns the (0-based) offset
    // of the first byte that is '"' (0x22), '\' (0x5C) or a control character
    // (< 0x20); returns Len if none of these appear in the first Len bytes.
    // This is the CORRECT stop set for ScanString (structural characters
    // { } [ ] , : are legal inside a string and MUST NOT stop it).
    class function ScanStringBody_SSE2(
      Ptr: PByte;
      Len: Integer
    ): Integer; static;

    class function ScanStructural_SSE42(
      Ptr: PByte;
      Length: Integer
    ): Integer; static;

    class function Parse(
      const AData: TByteSpan;
      const AKeepAlive: IInterface = nil;
      AMaxDepth: Integer = DEFAULT_MAX_JSON_DEPTH
    ): IDextJsonNode; static;
  end;

  /// <summary>
  ///   Objeto JSON baseado em Spans.
  /// </summary>
  TJsonObject = class(TJsonBaseObject, IDextJsonNode, IDextJsonObject)
  private
    FPairs: TArray<TNextGenJsonPair>;
    FCount: Integer;
    FHashTable: TArray<Integer>;
    FHashChain: TArray<Integer>;
    FHashBuilt: Boolean;
    FKeepAlive: IInterface;
    procedure BuildHash;
    function FindKey(const Name: string): Integer;
    procedure AddOrReplacePair(const AKey: string; const AValue: TNextGenJsonValue);
  private
    function GetS(const Name: string): string; inline;
    procedure SetS(const Name: string; const Value: string); inline;
    function GetI(const Name: string): Integer; inline;
    procedure SetI(const Name: string; Value: Integer); inline;
    function GetL(const Name: string): Int64; inline;
    procedure SetL(const Name: string; Value: Int64); inline;
    function GetD(const Name: string): Double; inline;
    procedure SetD(const Name: string; Value: Double); inline;
    function GetB(const Name: string): Boolean; inline;
    procedure SetB(const Name: string; Value: Boolean); inline;
    function GetO(const Name: string): TJsonObject; inline;
    procedure SetO(const Name: string; Value: TJsonObject); inline;
    function GetA(const Name: string): TJsonArray; inline;
    procedure SetA(const Name: string; Value: TJsonArray); inline;
    function GetTypes(const Name: string): TDextJsonNodeType; inline;
  protected
    function _Release: Integer; stdcall;
    procedure AdoptManualLifetime; override;
  public
    constructor Create(ARefCounted: Boolean = False);
    destructor Destroy; override;

    procedure AddPair(const AKey: TByteSpan; const AValue: TNextGenJsonValue); overload;
    procedure AddPair(const AKey: string; const AValue: TNextGenJsonValue); overload;

    // IDextJsonNode
    function GetNodeType: TDextJsonNodeType;
    function AsString: string;
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsDouble: Double;
    function AsBoolean: Boolean;
    function ToJson(Indented: Boolean = False): string; override;
    function IsNull: Boolean;

    // IDextJsonObject
    function Contains(const Name: string): Boolean;
    function GetNode(const Name: string): IDextJsonNode;
    function GetString(const Name: string): string;
    function GetInteger(const Name: string): Integer;
    function GetInt64(const Name: string): Int64;
    function GetDouble(const Name: string): Double;
    function GetBoolean(const Name: string): Boolean;
    function GetObject(const Name: string): IDextJsonObject;
    function GetArray(const Name: string): IDextJsonArray;
    function GetCount: Integer;
    function GetName(Index: Integer): string;

    procedure SetString(const Name, Value: string);
    procedure SetInteger(const Name: string; Value: Integer);
    procedure SetInt64(const Name: string; Value: Int64);
    procedure SetDouble(const Name: string; Value: Double);
    procedure SetBoolean(const Name: string; Value: Boolean);
    procedure SetObject(const Name: string; Value: IDextJsonObject);
    procedure SetArray(const Name: string; Value: IDextJsonArray);
    procedure SetNode(const Name: string; Value: IDextJsonNode);
    procedure SetNull(const Name: string);
    property S[const Name: string]: string read GetS write SetS; default;
    property I[const Name: string]: Integer read GetI write SetI;
    property L[const Name: string]: Int64 read GetL write SetL;
    property D[const Name: string]: Double read GetD write SetD;
    property F[const Name: string]: Double read GetD write SetD;
    property B[const Name: string]: Boolean read GetB write SetB;
    property O[const Name: string]: TJsonObject read GetO write SetO;
    property A[const Name: string]: TJsonArray read GetA write SetA;
    property Types[const Name: string]: TDextJsonNodeType read GetTypes;
    property Count: Integer read GetCount;
    property Names[Index: Integer]: string read GetName;
    property Nodes[const Name: string]: IDextJsonNode read GetNode;
  end;

  /// <summary>
  ///   Array JSON baseado em Spans.
  /// </summary>
  TJsonArray = class(TJsonBaseObject, IDextJsonNode, IDextJsonArray)
  private
    FValues: TArray<TNextGenJsonValue>;
    FCount: Integer;
    FKeepAlive: IInterface;
  private
    function GetS(Index: Integer): string; inline;
    procedure SetS(Index: Integer; const Value: string); inline;
    function GetI(Index: Integer): Integer; inline;
    procedure SetI(Index: Integer; Value: Integer); inline;
    function GetL(Index: Integer): Int64; inline;
    procedure SetL(Index: Integer; Value: Int64); inline;
    function GetD(Index: Integer): Double; inline;
    procedure SetD(Index: Integer; Value: Double); inline;
    function GetB(Index: Integer): Boolean; inline;
    procedure SetB(Index: Integer; Value: Boolean); inline;
    function GetO(Index: Integer): TJsonObject; inline;
    function GetA(Index: Integer): TJsonArray; inline;
    function GetTypes(Index: Integer): TDextJsonNodeType; inline;
  protected
    function _Release: Integer; stdcall;
    procedure AdoptManualLifetime; override;
  public
    constructor Create(ARefCounted: Boolean = False);
    procedure Add(Value: TJsonObject); overload;
    procedure Add(Value: TJsonArray); overload;
    destructor Destroy; override;

    procedure AddValue(const AValue: TNextGenJsonValue);

    // IDextJsonNode
    function GetNodeType: TDextJsonNodeType;
    function AsString: string;
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsDouble: Double;
    function AsBoolean: Boolean;
    function ToJson(Indented: Boolean = False): string; override;
    function IsNull: Boolean;

    // IDextJsonArray
    function GetCount: NativeInt;
    function GetNode(Index: Integer): IDextJsonNode;
    function GetString(Index: Integer): string;
    function GetInteger(Index: Integer): Integer;
    function GetInt64(Index: Integer): Int64;
    function GetDouble(Index: Integer): Double;
    function GetBoolean(Index: Integer): Boolean;
    function GetObject(Index: Integer): IDextJsonObject;
    function GetArray(Index: Integer): IDextJsonArray;

    procedure Add(const Value: string); overload;
    procedure Add(Value: Integer); overload;
    procedure Add(Value: Int64); overload;
    procedure Add(Value: Double); overload;
    procedure Add(Value: Boolean); overload;
    procedure Add(Value: IDextJsonObject); overload;
    procedure Add(Value: IDextJsonArray); overload;
    procedure AddNull;
    property S[Index: Integer]: string read GetS write SetS; default;
    property I[Index: Integer]: Integer read GetI write SetI;
    property L[Index: Integer]: Int64 read GetL write SetL;
    property D[Index: Integer]: Double read GetD write SetD;
    property F[Index: Integer]: Double read GetD write SetD;
    property B[Index: Integer]: Boolean read GetB write SetB;
    property O[Index: Integer]: TJsonObject read GetO;
    property A[Index: Integer]: TJsonArray read GetA;
    property Types[Index: Integer]: TDextJsonNodeType read GetTypes;
    property Count: NativeInt read GetCount;
  end;

  /// <summary>
  ///   Node adaptador para valores primitivos de folha.
  /// </summary>
  TNextGenJsonPrimitive = class(TInterfacedObject, IDextJsonNode)
  private
    FValue: TNextGenJsonValue;
  public
    FKeepAlive: IInterface;
    constructor Create(const AValue: TNextGenJsonValue);
    destructor Destroy; override;
    function GetNodeType: TDextJsonNodeType;
    function AsString: string;
    function AsInteger: Integer;
    function AsInt64: Int64;
    function AsDouble: Double;
    function AsBoolean: Boolean;
    function ToJson(Indented: Boolean = False): string;
    function IsNull: Boolean;
  end;

  /// <summary>
  ///   Pool de Objetos para reciclagem rápida.
  /// </summary>
  // Thin facade: delegates to the calling thread's own node pool (see
  // TThreadNodePool in the implementation). The previous global class-var pool
  // was a data race under concurrent parsing; this per-thread design needs no lock.
  TNextGenJsonPool = class
  public
    class function RentObject: TJsonObject; static;
    class procedure ReturnObject(AnObj: TJsonObject); static;
    class function RentArray: TJsonArray; static;
    class procedure ReturnArray(AnArr: TJsonArray); static;
    class procedure ClearPool; static;
  end;

  /// <summary>
  ///   Record de escrita direta em UTF-8 para JSON de alta performance.
  /// </summary>
  TNextGenJsonWriter = record
  private
    FBuffer: TBytes;
    FLength: Integer;
    FNeedComma: Boolean;
    procedure EnsureCapacity(ANeeded: Integer); inline;
    procedure WriteRawByte(AByte: Byte); inline;
    procedure WriteRawBytes(const ABytes: TBytes); overload; inline;
    procedure WriteRawBytes(APtr: Pointer; ALength: Integer); overload; inline;
    procedure WriteEscapedString(const AValue: string);
    procedure WriteCommaIfNeeded; inline;
  public
    procedure Init(InitialCapacity: Integer = 65536);
    procedure Clear;
    procedure StartObject;
    procedure EndObject;
    procedure StartArray;
    procedure EndArray;
    procedure WritePropertyName(const AName: string); overload;
    procedure WritePropertyName(const AKey: TByteSpan); overload;
    procedure WriteStringValue(const AValue: string); overload;
    procedure WriteStringValue(const AValue: TByteSpan); overload;
    procedure WriteNumber(AValue: Int64); overload;
    procedure WriteNumber(AValue: Double); overload;
    procedure WriteBoolean(AValue: Boolean);
    procedure WriteNull;
    procedure WriteRawValue(const AValue: TByteSpan);
    function ToBytes: TBytes;
    // ... rest unchanged
    function ToString: string;
    procedure SaveToFile(const AFileName: string);
    property Buffer: TBytes read FBuffer;
    property Length: Integer read FLength;
  end;

  /// <summary>
  ///   Provedor padrão de JSON NextGen.
  /// </summary>
  TNextGenJsonProvider = class(TInterfacedObject, IDextJsonProvider)
  private
    FMaxDepth: Integer;
  public
    /// <summary>
    ///   Initializes the NextGen JSON provider with a custom or default maximum nesting depth.
    /// </summary>
    constructor Create(AMaxDepth: Integer = DEFAULT_MAX_JSON_DEPTH);
    /// <summary>
    ///   Gets or sets the maximum nesting depth for JSON parsing.
    /// </summary>
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;

    function CreateObject: IDextJsonObject;
    function CreateArray: IDextJsonArray;
    function Parse(const Json: string): IDextJsonNode;
  end;

implementation

{ TJsonBaseObject }

constructor TJsonBaseObject.Create(ARefCounted: Boolean);
begin
  inherited Create;
  FRefCounted := ARefCounted;
  FRefCount := 0;
end;

function TJsonBaseObject.GetSelf: TObject;
begin
  Result := Self;
end;

function TJsonBaseObject.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := S_OK
  else
    Result := E_NOINTERFACE;
end;

function TJsonBaseObject._AddRef: Integer;
begin
  if FRefCounted then
    Result := AtomicIncrement(FRefCount)
  else
    Result := -1;
end;

function TJsonBaseObject._Release: Integer;
begin
  Result := -1;
end;

procedure TJsonBaseObject.AdoptManualLifetime;
begin
  FRefCounted := False;
end;

class function TJsonBaseObject.Parse(const AJson: string): TJsonBaseObject;
var
  Bytes: TBytes;
  Span: TByteSpan;
  Node: IDextJsonNode;
  KeepAlive: IInterface;
  Getter: IDextJsonNodeGetter;
  Obj: TJsonBaseObject;
begin
  if AJson.IsEmpty then
    Exit(nil);
  Bytes := TEncoding.UTF8.GetBytes(AJson);
  Span := TByteSpan.FromBytes(Bytes);
  KeepAlive := TJSONBufferOwner.Create(Bytes);
  Node := TNextGenJsonParser.Parse(Span, KeepAlive);
  if Node = nil then
    Exit(nil);
  if Supports(Node, IDextJsonNodeGetter, Getter) then
  begin
    Obj := TJsonBaseObject(Getter.GetSelf);
    { Own the whole tree with TObject.Free — nested rented nodes must not be
      returned to the Indy worker thread pool (FastMM reports those as leaks). }
    Obj.AdoptManualLifetime;
    Result := Obj;
  end
  else
    Result := nil;
end;

var
  GWhitespace: array[0..255] of Byte;
  GStructural: array[0..255] of Byte;

{ TJsonKey }

function TJsonKey.ToString: string;
begin
  if StrValue <> '' then
    Result := StrValue
  else
    Result := Span.ToString;
end;

function TJsonKey.EqualsString(const AText: string): Boolean;
begin
  if StrValue <> '' then
    Result := StrValue = AText
  else
    Result := Span.EqualsString(AText);
end;

{ TNextGenJsonValue }

function TNextGenJsonValue.GetNodeRef: IDextJsonNode;
begin
  Result := IDextJsonNode(FNodeRef);
end;

procedure TNextGenJsonValue.SetNodeRef(const AValue: IDextJsonNode);
begin
  if FNodeRef <> nil then
  begin
    FreeNode;
  end;
  if AValue <> nil then
  begin
    FNodeRef := Pointer(AValue);
    AValue._AddRef;
  end;
end;

procedure TNextGenJsonValue.FreeNode;
var
  P: Pointer;
  Temp: IDextJsonNode;
  Getter: IDextJsonNodeGetter;
  Obj: TObject;
begin
  { FNodeRef owns exactly one reference (taken in SetNodeRef). Release it with a
    direct vcall — do NOT assign to an interface first (that would AddRef and
    mismatch ownership). When _Release returns -1 the target is a non-refcounted
    TJsonObject/TJsonArray (Create default); the parent must Free it. Clear any
    temporary interface with Pointer(...) := nil so _IntfClear does not run
    after Free (that was the 0x80808088 AV). }
  if FNodeRef = nil then
    Exit;

  P := FNodeRef;
  FNodeRef := nil;

  if IDextJsonNode(P)._Release <> -1 then
    Exit;

  Pointer(Temp) := P;
  try
    if Supports(Temp, IDextJsonNodeGetter, Getter) then
    begin
      Obj := Getter.GetSelf;
      Getter := nil;
      Pointer(Temp) := nil;
      Obj.Free;
    end;
  finally
    Pointer(Temp) := nil;
  end;
end;

procedure TNextGenJsonValue.SetStrValue(const S: string);
begin
  if S <> '' then
  begin
    if FStrValue = nil then New(FStrValue);
    FStrValue^ := S;
    FStringDecoded := True;
  end;
end;

procedure TNextGenJsonValue.Init(
  AType: TDextJsonNodeType;
  const ASpan: TByteSpan
);
begin
  FType := AType;
  FValueSpan := ASpan;
  FStrValue := nil;
  FStringDecoded := False;
  FNodeRef := nil;
end;

function TNextGenJsonValue.AsString: string;
var
  Raw: string;
  Builder: TStringBuilder;
  I: Integer;
  Start: Integer;
  Code: Integer;
  Hex: Integer;
  C: Char;
begin
  if FType = TDextJsonNodeType.jntNull then Exit('');
  if FStrValue <> nil then Exit(FStrValue^);
  Raw := FValueSpan.ToString;
  if Pos('\', Raw) = 0 then Exit(Raw);
  Builder := TStringBuilder.Create(Length(Raw));
  try
    I := 1; Start := 1;
    while I <= Length(Raw) do
    begin
      if Raw[I] <> '\' then begin Inc(I); Continue; end;
      if I > Start then Builder.Append(Copy(Raw, Start, I - Start));
      Inc(I);
      if I > Length(Raw) then raise EJsonException.Create('Unterminated string escape');
      C := Raw[I];
      case C of
        '"', '\', '/': Builder.Append(C);
        'b': Builder.Append(#8); 'f': Builder.Append(#12); 'n': Builder.Append(#10);
        'r': Builder.Append(#13); 't': Builder.Append(#9);
        'u': begin
          if I + 4 > Length(Raw) then raise EJsonException.Create('Invalid unicode escape sequence');
          Code := 0;
          for Hex := 1 to 4 do begin
            C := Raw[I + Hex];
            if CharInSet(C, ['0'..'9']) then
              Code := (Code shl 4) + Ord(C) - Ord('0')
            else if CharInSet(C, ['a'..'f']) then
              Code := (Code shl 4) + Ord(C) - Ord('a') + 10
            else if CharInSet(C, ['A'..'F']) then
              Code := (Code shl 4) + Ord(C) - Ord('A') + 10
            else raise EJsonException.Create('Invalid unicode escape sequence');
          end;
          Builder.Append(Char(Code)); Inc(I, 4);
        end;
      else raise EJsonException.Create('Invalid escape character: ' + C);
      end;
      Inc(I); Start := I;
    end;
    if Start <= Length(Raw) then Builder.Append(Copy(Raw, Start, Length(Raw) - Start + 1));
    Result := Builder.ToString;
  finally Builder.Free; end;
end;

function TNextGenJsonValue.AsInteger: Integer;
begin
  if (FStrValue <> nil) and (FStrValue^ <> '') then
    Result := StrToIntDef(FStrValue^, 0)
  else
    Result := Integer(AsInt64);
end;

function TNextGenJsonValue.AsInt64: Int64;
begin
  if (FStrValue <> nil) and (FStrValue^ <> '') then
    Result := StrToInt64Def(FStrValue^, 0)
  else
    Result := TNextGenJsonParser.ParseInt64(FValueSpan);
end;

function TNextGenJsonValue.AsDouble: Double;
begin
  if (FStrValue <> nil) and (FStrValue^ <> '') then
    Result := StrToFloatDef(FStrValue^, 0.0, TFormatSettings.Invariant)
  else
    Result := TNextGenJsonParser.ParseNumber(FValueSpan);
end;

function TNextGenJsonValue.AsBoolean: Boolean;
begin
  if FType = TDextJsonNodeType.jntBoolean then
  begin
    if (FStrValue <> nil) and (FStrValue^ <> '') then
      Result := FStrValue^.ToLower = 'true'
    else
      Result := FValueSpan.EqualsString('true');
  end
  else
    Result := False;
end;

function TNextGenJsonValue.IsNull: Boolean;
begin
  Result := FType = TDextJsonNodeType.jntNull;
end;

{ TJsonLookupTable }

class constructor TJsonLookupTable.Create;
begin
  FillChar(Structural, SizeOf(Structural), 0);
  FillChar(Whitespace, SizeOf(Whitespace), 0);

  Structural[Ord('{')] := True;
  Structural[Ord('}')] := True;
  Structural[Ord('[')] := True;
  Structural[Ord(']')] := True;
  Structural[Ord(':')] := True;
  Structural[Ord(',')] := True;
  Structural[Ord('"')] := True;
  Structural[Ord('\')] := True;

  Whitespace[Ord(' ')] := True;
  Whitespace[Ord(#9)] := True;
  Whitespace[Ord(#10)] := True;
  Whitespace[Ord(#13)] := True;
end;

{ TNextGenJsonParser }

procedure TNextGenJsonParser.ScanString(var APtr: PByte);
var
  B: Byte;
  HexIdx: Integer;
  HexByte: Byte;
  Rem: NativeInt;
begin
  while APtr < FEnd do
  begin
    // String body scan: for long chunks (>= 16 bytes) use SIMD (SSE2),
    // otherwise use the scalar loop for short remainders (typical DTOs).
    Rem := FEnd - APtr;
    if Rem >= 16 then
      Inc(APtr, ScanStringBody_SSE2(APtr, Integer(Rem)))
    else
      while (APtr < FEnd) and (APtr^ >= 32) and
            (APtr^ <> Ord('"')) and (APtr^ <> Ord('\')) do
        Inc(APtr);

    if APtr >= FEnd then
      Break;

    B := APtr^;
    if B = Ord('"') then
      Exit;

    if B < 32 then
    begin
      if (B = 10) or (B = 13) then
        raise EJsonException.Create(
          'Raw line break not allowed in string'
        )
      else
        raise EJsonException.Create(
          'Control character not allowed in string'
        );
    end;

    if B = Ord('\') then
    begin
      Inc(APtr);
      if APtr >= FEnd then
        raise EJsonException.Create('Unterminated string escape');
      B := APtr^;
      case B of
        Ord('"'), Ord('\'), Ord('/'), Ord('b'), Ord('f'), Ord('n'),
        Ord('r'), Ord('t'): ;
        Ord('u'):
          begin
            if APtr + 4 >= FEnd then
              raise EJsonException.Create(
                'Invalid unicode escape sequence'
              );
            for HexIdx := 1 to 4 do
            begin
              HexByte := (APtr + HexIdx)^;
              if not (
                ((HexByte >= 48) and (HexByte <= 57)) or // '0'..'9'
                ((HexByte >= 97) and (HexByte <= 102)) or // 'a'..'f'
                ((HexByte >= 65) and (HexByte <= 70)) // 'A'..'F'
              ) then
                raise EJsonException.Create(
                  'Invalid unicode escape sequence'
                );
            end;
            Inc(APtr, 4);
          end;
      else
        raise EJsonException.Create(
          'Invalid escape character: \' + Char(B)
        );
      end;
    end;
    Inc(APtr);
  end;
  raise EJsonException.Create('String not closed');
end;

class function TNextGenJsonParser.ParseNumber(
  const ASpan: TByteSpan
): Double;
var
  I: Integer;
  Val: Double;
  Divisor: Double;
  Sign: Double;
  B: Byte;
  IsFraction: Boolean;
begin
  if ASpan.Length = 0 then
    Exit(0.0);
  Val := 0.0;
  Divisor := 1.0;
  Sign := 1.0;
  IsFraction := False;
  I := 0;
  if ASpan.Data[0] = Ord('-') then
  begin
    Sign := -1.0;
    Inc(I);
  end
  else if ASpan.Data[0] = Ord('+') then
  begin
    Inc(I);
  end;

  while I < ASpan.Length do
  begin
    B := ASpan.Data[I];
    if (B >= Ord('0')) and (B <= Ord('9')) then
    begin
      if IsFraction then
      begin
        Divisor := Divisor * 10.0;
        Val := Val + (B - Ord('0')) / Divisor;
      end
      else
      begin
        Val := Val * 10.0 + (B - Ord('0'));
      end;
    end
    else if B = Ord('.') then
    begin
      IsFraction := True;
    end
    else
    begin
      Exit(StrToFloatDef(ASpan.ToString, 0.0, TFormatSettings.Invariant));
    end;
    Inc(I);
  end;
  Result := Val * Sign;
end;

class function TNextGenJsonParser.ParseInt64(
  const ASpan: TByteSpan
): Int64;
var
  I: Integer;
  Val: Int64;
  Sign: Int64;
  B: Byte;
begin
  if ASpan.Length = 0 then
    Exit(0);
  Val := 0;
  Sign := 1;
  I := 0;
  if ASpan.Data[0] = Ord('-') then
  begin
    Sign := -1;
    Inc(I);
  end
  else if ASpan.Data[0] = Ord('+') then
  begin
    Inc(I);
  end;

  while I < ASpan.Length do
  begin
    B := ASpan.Data[I];
    if (B >= Ord('0')) and (B <= Ord('9')) then
      Val := Val * 10 + (B - Ord('0'))
    else
      Break;
    Inc(I);
  end;
  Result := Val * Sign;
end;

class function TNextGenJsonParser.ScanStringBody_SSE2(
  Ptr: PByte;
  Len: Integer
): Integer;
{$IF defined(CPUX64) and defined(MSWINDOWS)}
asm
  // Win64: RCX = Ptr, EDX = Len. Return in EAX = offset of the first stop byte
  // ('"' / '\' / <0x20), or Len if none appears. Pure SSE2 (baseline on x64):
  // no pcmpistri (implicit NUL termination makes control char handling subtle).
  // No over-read: 16-byte blocks start only when >= 16 bytes remain, the rest is scalar.
  mov     r8, rcx              // r8 = base ptr
  movsxd  r9, edx              // r9 = Len
  xor     r10, r10             // r10 = i = 0

  // Broadcast constants to all 16 lanes: 0x22 ('"'), 0x5C ('\'), 0x1F.
  mov     eax, $22222222
  movd    xmm1, eax
  pshufd  xmm1, xmm1, 0
  mov     eax, $5C5C5C5C
  movd    xmm2, eax
  pshufd  xmm2, xmm2, 0
  mov     eax, $1F1F1F1F
  movd    xmm3, eax
  pshufd  xmm3, xmm3, 0

@Loop16:
  mov     rax, r9
  sub     rax, r10
  cmp     rax, 16
  jl      @Tail
  movdqu  xmm0, [r8 + r10]     // 16 bytes
  movdqa  xmm4, xmm0
  pcmpeqb xmm4, xmm1           // == '"'
  movdqa  xmm5, xmm0
  pcmpeqb xmm5, xmm2           // == '\'
  por     xmm4, xmm5
  movdqa  xmm5, xmm0
  pminub  xmm5, xmm3           // min(v, 0x1F)
  pcmpeqb xmm5, xmm0           // == v  -> byte <= 0x1F (control)
  por     xmm4, xmm5
  pmovmskb eax, xmm4
  test    eax, eax
  jnz     @FoundVec
  add     r10, 16
  jmp     @Loop16

@FoundVec:
  bsf     eax, eax             // index of first set bit -> 0..15
  add     r10, rax
  mov     rax, r10
  ret

@Tail:
  cmp     r10, r9
  jge     @NotFound
  movzx   eax, byte ptr [r8 + r10]
  cmp     al, $22
  je      @FoundScalar
  cmp     al, $5C
  je      @FoundScalar
  cmp     al, $20
  jb      @FoundScalar         // < 0x20 (unsigned)
  inc     r10
  jmp     @Tail

@FoundScalar:
  mov     rax, r10
  ret

@NotFound:
  mov     rax, r9              // = Len (no stop char in first Len bytes)
end;
{$ELSE}
var
  I: Integer;
  B: Byte;
begin
  I := 0;
  while I < Len do
  begin
    B := Ptr[I];
    if (B = Ord('"')) or (B = Ord('\')) or (B < 32) then
      Exit(I);
    Inc(I);
  end;
  Result := Len;
end;
{$ENDIF}

class function TNextGenJsonParser.ScanStructural_SSE42(
  Ptr: PByte;
  Length: Integer
): Integer;
{$IF defined(CPUX64) and defined(MSWINDOWS)}
asm
  // RCX = Ptr, RDX = Length
  // Return value: EAX (offset of found char, or -1)
  mov r8, rcx
  mov r9, rcx

  cmp rdx, 16
  jl @Scalar

  // Load the 8 search characters into XMM0: "{}[],:\"
  mov rax, $5C222C3A5D5B7D7B
  movq xmm0, rax

@Loop:
  cmp rdx, 16
  jl @Scalar
  pcmpistri xmm0, [r9], 0
  jc @Found
  add r9, 16
  sub rdx, 16
  jmp @Loop

@Found:
  add r9, rcx
  sub r9, r8
  mov rax, r9
  ret

@Scalar:
  xor r10, r10
@ScalarLoop:
  cmp r10, rdx
  jge @NotFound
  mov al, [r9 + r10]
  cmp al, '{'
  je @ScalarFound
  cmp al, '}'
  je @ScalarFound
  cmp al, '['
  je @ScalarFound
  cmp al, ']'
  je @ScalarFound
  cmp al, ':'
  je @ScalarFound
  cmp al, ','
  je @ScalarFound
  cmp al, '"'
  je @ScalarFound
  cmp al, '\'
  je @ScalarFound
  inc r10
  jmp @ScalarLoop

@ScalarFound:
  add r9, r10
  sub r9, r8
  mov rax, r9
  ret

@NotFound:
  mov rax, -1
  ret
end;
{$ELSE}
begin
  Result := 0;
  while Result < Length do
  begin
    if TJsonLookupTable.Structural[Ptr[Result]] then
      Exit;
    Inc(Result);
  end;
  Result := -1;
end;
{$ENDIF}

procedure TNextGenJsonParser.CheckDepth;
begin
  if (FMaxDepth > 0) and (FDepth >= FMaxDepth) then
    raise EJsonParserException.CreateFmt('JSON max nesting depth of %d exceeded', [FMaxDepth]);
  Inc(FDepth);
end;

function TNextGenJsonParser.ParseObject: IDextJsonObject;
var
  Obj: IDextJsonObject;
  ObjClass: TJsonObject;
  KeySpan: TByteSpan;
  Val: TNextGenJsonValue;
  StartKey: PByte;
begin
  CheckDepth;
  try
    Obj := TNextGenJsonPool.RentObject;
    ObjClass := TJsonObject(Obj);
    Inc(FPtr); // Pula '{'

    while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
      Inc(FPtr);

    if (FPtr < FEnd) and (FPtr^ = Ord('}')) then
    begin
      Inc(FPtr);
      Exit(Obj);
    end;

    while FPtr < FEnd do
    begin
      while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
        Inc(FPtr);

      if FPtr >= FEnd then
        raise EJsonException.Create('Expected key string or "}"');

      if FPtr^ <> Ord('"') then
        raise EJsonException.Create('Key string must be quoted');

      Inc(FPtr); // skip '"'
      StartKey := FPtr;
      ScanString(FPtr);
      KeySpan := TByteSpan.Create(StartKey, FPtr - StartKey);
      Inc(FPtr); // skip '"'

      while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
        Inc(FPtr);

      if FPtr >= FEnd then
        raise EJsonException.Create('Expected ":" after key');

      if FPtr^ <> Ord(':') then
        raise EJsonException.Create('Expected ":" after key, found ' +
          Char(FPtr^));

      Inc(FPtr); // skip ':'

      Val := ParseValue;
      ObjClass.AddPair(KeySpan, Val);

      while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
        Inc(FPtr);

      if FPtr >= FEnd then
        raise EJsonException.Create('Expected "," or "}"');

      if FPtr^ = Ord(',') then
      begin
        Inc(FPtr); // skip ','
        while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
          Inc(FPtr);
        if (FPtr < FEnd) and (FPtr^ = Ord('}')) then
          raise EJsonException.Create('Trailing comma in object');
      end
      else if FPtr^ = Ord('}') then
      begin
        Inc(FPtr); // skip '}'
        if ObjClass.FCount < Length(ObjClass.FPairs) then
          SetLength(ObjClass.FPairs, ObjClass.FCount);
        Exit(Obj);
      end
      else
      begin
        raise EJsonException.Create('Expected "," or "}"');
      end;
    end;
    raise EJsonException.Create('Unclosed object');
  finally
    Dec(FDepth);
  end;
end;

function TNextGenJsonParser.ParseArray: IDextJsonArray;
var
  Arr: IDextJsonArray;
  ArrClass: TJsonArray;
  Val: TNextGenJsonValue;
begin
  CheckDepth;
  try
    Arr := TNextGenJsonPool.RentArray;
    ArrClass := TJsonArray(Arr);
    Inc(FPtr); // Pula '['

    while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
      Inc(FPtr);

    if (FPtr < FEnd) and (FPtr^ = Ord(']')) then
    begin
      Inc(FPtr);
      Exit(Arr);
    end;

    while FPtr < FEnd do
    begin
      if FPtr^ = Ord(',') then
        raise EJsonException.Create('Expected value, found ","');

      Val := ParseValue;
      ArrClass.AddValue(Val);

      while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
        Inc(FPtr);

      if FPtr >= FEnd then
        raise EJsonException.Create('Expected "," or "]"');

      if FPtr^ = Ord(',') then
      begin
        Inc(FPtr); // skip ','
        while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
          Inc(FPtr);
        if (FPtr < FEnd) and (FPtr^ = Ord(']')) then
          raise EJsonException.Create('Trailing comma in array');
      end
      else if FPtr^ = Ord(']') then
      begin
        Inc(FPtr); // skip ']'
        if ArrClass.FCount < Length(ArrClass.FValues) then
          SetLength(ArrClass.FValues, ArrClass.FCount);
        Exit(Arr);
      end
      else
      begin
        raise EJsonException.Create('Expected "," or "]"');
      end;
    end;
    raise EJsonException.Create('Unclosed array');
  finally
    Dec(FDepth);
  end;
end;

function TNextGenJsonParser.ParseValue: TNextGenJsonValue;
var
  StartPos: PByte;
  Val: TNextGenJsonValue;
  B: Byte;
  ValSpan: TByteSpan;
  P: PByte;
begin
  while (FPtr < FEnd) and (GWhitespace[FPtr^] <> 0) do
    Inc(FPtr);

  if FPtr >= FEnd then
    raise EJsonException.Create('Unexpected end of JSON');

  B := FPtr^;
  if B = Ord('{') then
  begin
    Val.Init(
      TDextJsonNodeType.jntObject,
      TByteSpan.Create(FPtr, 0)
    );
    Val.NodeRef := ParseObject;
    Exit(Val);
  end;

  if B = Ord('[') then
  begin
    Val.Init(
      TDextJsonNodeType.jntArray,
      TByteSpan.Create(FPtr, 0)
    );
    Val.NodeRef := ParseArray;
    Exit(Val);
  end;

  if B = Ord('"') then
  begin
    Inc(FPtr); // skip '"'
    StartPos := FPtr;
    ScanString(FPtr);
    Val.Init(
      TDextJsonNodeType.jntString,
      TByteSpan.Create(StartPos, FPtr - StartPos)
    );
    Inc(FPtr); // skip '"'
    Exit(Val);
  end;

  StartPos := FPtr;
  while (FPtr < FEnd) and (GWhitespace[FPtr^] = 0)
    and (FPtr^ <> Ord(','))
    and (FPtr^ <> Ord('}'))
    and (FPtr^ <> Ord(']')) do
  begin
    Inc(FPtr);
  end;

  if StartPos = FPtr then
    raise EJsonException.Create('Expected value');

  ValSpan := TByteSpan.Create(StartPos, FPtr - StartPos);
  // Dispatch on the FIRST byte: only 't'/'f'/'n' can be true/false/null.
  // For numbers (first byte digit or '-'), skip literal comparisons entirely
  // -- EqualsString re-scans each literal for the ASCII check and was called
  // up to 3 times for EVERY value. Semantics unchanged: a non-numeric bareword
  // that is not exactly true/false/null still falls through to the number branch
  // (where validation fails), exactly as before.
  if (StartPos^ = Ord('t')) and ValSpan.EqualsString('true') then
    Val.Init(TDextJsonNodeType.jntBoolean, ValSpan)
  else if (StartPos^ = Ord('f')) and ValSpan.EqualsString('false') then
    Val.Init(TDextJsonNodeType.jntBoolean, ValSpan)
  else if (StartPos^ = Ord('n')) and ValSpan.EqualsString('null') then
    Val.Init(TDextJsonNodeType.jntNull, ValSpan)
  else
  begin
    if ValSpan.Length = 0 then
      raise EJsonException.Create('Invalid number');

    P := ValSpan.Data;
    if (P^ = Ord('-')) or (P^ = Ord('+')) then
    begin
      if P^ = Ord('+') then
        raise EJsonException.Create('Number cannot start with +');
      Inc(P);
      if P >= ValSpan.Data + ValSpan.Length then
        raise EJsonException.Create('Invalid number: sign only');
    end;

    if P^ = Ord('.') then
      raise EJsonException.Create('Decimal needs digit before dot');

    if P^ = Ord('0') then
    begin
      if (P + 1 < ValSpan.Data + ValSpan.Length) and
         (P[1] >= Ord('0')) and
         (P[1] <= Ord('9')) then
        raise EJsonException.Create('Leading zeroes not allowed');
    end;

    while (P < ValSpan.Data + ValSpan.Length) and
          (P^ >= Ord('0')) and
          (P^ <= Ord('9')) do
      Inc(P);

    if (P < ValSpan.Data + ValSpan.Length) and (P^ = Ord('.')) then
    begin
      Inc(P);
      if (P >= ValSpan.Data + ValSpan.Length) or
         (P^ < Ord('0')) or
         (P^ > Ord('9')) then
        raise EJsonException.Create('Expected digit after decimal point');
      while (P < ValSpan.Data + ValSpan.Length) and
            (P^ >= Ord('0')) and
            (P^ <= Ord('9')) do
        Inc(P);
    end;

    if (P < ValSpan.Data + ValSpan.Length) and
       ((P^ = Ord('e')) or (P^ = Ord('E'))) then
    begin
      Inc(P);
      if P >= ValSpan.Data + ValSpan.Length then
        raise EJsonException.Create('Exponent requires value');
      if (P^ = Ord('+')) or (P^ = Ord('-')) then
      begin
        Inc(P);
        if P >= ValSpan.Data + ValSpan.Length then
          raise EJsonException.Create('Exponent requires value');
      end;
      if (P^ < Ord('0')) or (P^ > Ord('9')) then
        raise EJsonException.Create('Expected digit in exponent');
      while (P < ValSpan.Data + ValSpan.Length) and
            (P^ >= Ord('0')) and
            (P^ <= Ord('9')) do
        Inc(P);
    end;

    if P < ValSpan.Data + ValSpan.Length then
      raise EJsonException.Create('Invalid character in number');

    Val.Init(TDextJsonNodeType.jntNumber, ValSpan);
  end;

  Result := Val;
end;

class function TNextGenJsonParser.Parse(
  const AData: TByteSpan;
  const AKeepAlive: IInterface;
  AMaxDepth: Integer
): IDextJsonNode;
var
  Parser: TNextGenJsonParser;
begin
  Parser.FData := AData;
  Parser.FStart := AData.Data;
  Parser.FPtr := AData.Data;
  Parser.FEnd := AData.Data + AData.Length;
  Parser.FDepth := 0;
  Parser.FMaxDepth := AMaxDepth;

  while (Parser.FPtr < Parser.FEnd) and (GWhitespace[Parser.FPtr^] <> 0) do
    Inc(Parser.FPtr);

  if Parser.FPtr >= Parser.FEnd then
    raise EJsonException.Create('Empty JSON string');

  if Parser.FPtr^ = Ord('{') then
  begin
    Result := Parser.ParseObject;
    if Assigned(AKeepAlive) then
      (Result as TJsonObject).FKeepAlive := AKeepAlive;
  end
  else if Parser.FPtr^ = Ord('[') then
  begin
    Result := Parser.ParseArray;
    if Assigned(AKeepAlive) then
      (Result as TJsonArray).FKeepAlive := AKeepAlive;
  end
  else
  begin
    Result := TNextGenJsonPrimitive.Create(Parser.ParseValue);
    if Assigned(AKeepAlive) then
      (Result as TNextGenJsonPrimitive).FKeepAlive := AKeepAlive;
  end;

  while (Parser.FPtr < Parser.FEnd) and (GWhitespace[Parser.FPtr^] <> 0) do
    Inc(Parser.FPtr);

  if Parser.FPtr < Parser.FEnd then
    raise EJsonException.Create('Extra trailing data after JSON root');
end;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
function GetKeyHash(const K: TJsonKey): Cardinal;
var
  I: Integer;
begin
  Result := 2166136261;
  if K.StrValue <> '' then
  begin
    for I := 1 to System.Length(K.StrValue) do
      Result := (Result xor Ord(K.StrValue[I])) * 16777619;
  end
  else
  begin
    for I := 0 to K.Span.Length - 1 do
      Result := (Result xor K.Span.Data[I]) * 16777619;
  end;
end;

function GetStringHash(const S: string): Cardinal;
var
  I: Integer;
begin
  Result := 2166136261;
  for I := 1 to System.Length(S) do
    Result := (Result xor Ord(S[I])) * 16777619;
end;

{ TJsonObject }

function TJsonObject._Release: Integer;
begin
  if FRefCounted then
  begin
    Result := AtomicDecrement(FRefCount);
    if Result = 0 then
      TNextGenJsonPool.ReturnObject(Self);
  end
  else
    Result := -1;
end;

procedure TJsonObject.AdoptManualLifetime;
var
  I: Integer;
  P: Pointer;
  Temp: IDextJsonNode;
  Getter: IDextJsonNodeGetter;
  Child: TJsonBaseObject;
begin
  FRefCounted := False;
  for I := 0 to FCount - 1 do
  begin
    P := FPairs[I].Value.FNodeRef;
    if P = nil then
      Continue;
    Pointer(Temp) := P;
    try
      if Supports(Temp, IDextJsonNodeGetter, Getter) then
      begin
        Child := TJsonBaseObject(Getter.GetSelf);
        Getter := nil;
        Child.AdoptManualLifetime;
      end;
    finally
      Pointer(Temp) := nil;
    end;
  end;
end;

constructor TJsonObject.Create(ARefCounted: Boolean);
begin
  inherited Create(ARefCounted);
  SetLength(FPairs, 0);
  FCount := 0;
  SetLength(FHashTable, 0);
  SetLength(FHashChain, 0);
  FHashBuilt := False;
end;

destructor TJsonObject.Destroy;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
  begin
    if FPairs[I].Value.FStrValue <> nil then
      Dispose(FPairs[I].Value.FStrValue);
    FPairs[I].Value.FreeNode;
  end;
  inherited Destroy;
end;

procedure TJsonObject.BuildHash;
var
  I: Integer;
  H: Cardinal;
  Bucket: Integer;
  BucketCount: Integer;
begin
  if FHashBuilt then Exit;
  BucketCount := 65536;
  while BucketCount < FCount * 2 do
    BucketCount := BucketCount * 2;

  SetLength(FHashTable, BucketCount);
  for I := 0 to BucketCount - 1 do
    FHashTable[I] := -1;

  SetLength(FHashChain, FCount);
  for I := 0 to FCount - 1 do
  begin
    H := GetKeyHash(FPairs[I].Key);
    Bucket := H and (BucketCount - 1);
    FHashChain[I] := FHashTable[Bucket];
    FHashTable[Bucket] := I;
  end;
  FHashBuilt := True;
end;

function TJsonObject.FindKey(const Name: string): Integer;
var
  I: Integer;
  Len: Integer;
  SearchSpan: TByteSpan;
  U8: TBytes;
  IsAscii: Boolean;
  H: Cardinal;
  Bucket: Integer;
  Idx: Integer;
  BucketCount: Integer;
  K: Integer;
  Matched: Boolean;
  KeyData: PByte;
begin
  Len := System.Length(Name);
  if Len = 0 then Exit(-1);

  if FCount > 64 then
  begin
    BuildHash;
    H := GetStringHash(Name);
    BucketCount := System.Length(FHashTable);
    Bucket := H and (BucketCount - 1);
    Idx := FHashTable[Bucket];
    while Idx >= 0 do
    begin
      if FPairs[Idx].Key.StrValue <> '' then
      begin
        if FPairs[Idx].Key.StrValue = Name then
          Exit(Idx);
      end
      else if FPairs[Idx].Key.Span.EqualsString(Name) then
        Exit(Idx);
      Idx := FHashChain[Idx];
    end;
    Exit(-1);
  end;

  IsAscii := True;
  for I := 1 to Len do
    if Ord(Name[I]) > 127 then
    begin
      IsAscii := False;
      Break;
    end;

  if IsAscii then
  begin
    // Hot path: keys are short ASCII field names. A length-gated inline scalar
    // compare (early-exit on first differing byte) beats calling the SIMD
    // EqualsBytes per key -- for 2..15 byte names the call/dispatch overhead
    // dominates the actual comparison.
    for I := 0 to FCount - 1 do
    begin
      if FPairs[I].Key.StrValue <> '' then
      begin
        if FPairs[I].Key.StrValue = Name then
          Exit(I);
      end
      else if FPairs[I].Key.Span.Length = Len then
      begin
        KeyData := FPairs[I].Key.Span.Data;
        Matched := True;
        for K := 0 to Len - 1 do
          if KeyData[K] <> Byte(Name[K + 1]) then
          begin
            Matched := False;
            Break;
          end;
        if Matched then
          Exit(I);
      end;
    end;
  end
  else
  begin
    U8 := TEncoding.UTF8.GetBytes(Name);
    if System.Length(U8) > 0 then
      SearchSpan := TByteSpan.Create(@U8[0], System.Length(U8))
    else
      SearchSpan := TByteSpan.Create(nil, 0);

    for I := 0 to FCount - 1 do
    begin
      if FPairs[I].Key.StrValue <> '' then
      begin
        if FPairs[I].Key.StrValue = Name then
          Exit(I);
      end
      else if FPairs[I].Key.Span.Equals(SearchSpan) then
        Exit(I);
    end;
  end;
  Result := -1;
end;

procedure TJsonObject.AddPair(
  const AKey: TByteSpan;
  const AValue: TNextGenJsonValue
);
var
  NewCap: Integer;
begin
  if FCount >= Length(FPairs) then
  begin
    NewCap := Length(FPairs) * 2;
    if NewCap < 8 then NewCap := 8;
    SetLength(FPairs, NewCap);
  end;
  FPairs[FCount].Key.Span := AKey;
  FPairs[FCount].Key.StrValue := '';
  FPairs[FCount].Value := AValue;
  Inc(FCount);
  FHashBuilt := False;
end;

procedure TJsonObject.AddPair(
  const AKey: string;
  const AValue: TNextGenJsonValue
);
var
  NewCap: Integer;
begin
  if FCount >= Length(FPairs) then
  begin
    NewCap := Length(FPairs) * 2;
    if NewCap < 8 then NewCap := 8;
    SetLength(FPairs, NewCap);
  end;
  FPairs[FCount].Key.Span := TByteSpan.Create(nil, 0);
  FPairs[FCount].Key.StrValue := AKey;
  FPairs[FCount].Value := AValue;
  Inc(FCount);
  FHashBuilt := False;
end;

procedure TJsonObject.AddOrReplacePair(
  const AKey: string;
  const AValue: TNextGenJsonValue
);
var
  Idx: Integer;
begin
  Idx := FindKey(AKey);
  if Idx >= 0 then
  begin
    if FPairs[Idx].Value.FStrValue <> nil then
      Dispose(FPairs[Idx].Value.FStrValue);
    FPairs[Idx].Value.FreeNode;
    FPairs[Idx].Value := AValue;
  end
  else
  begin
    AddPair(AKey, AValue);
  end;
end;

function TJsonObject.GetNodeType: TDextJsonNodeType;
begin
  Result := TDextJsonNodeType.jntObject;
end;

function TJsonObject.AsString: string;
begin
  Result := ToJson;
end;

function TJsonObject.AsInteger: Integer;
begin
  Result := 0;
end;

function TJsonObject.AsInt64: Int64;
begin
  Result := 0;
end;

function TJsonObject.AsDouble: Double;
begin
  Result := 0.0;
end;

function TJsonObject.AsBoolean: Boolean;
begin
  Result := False;
end;

procedure NodeToWriter(
  const ANode: IDextJsonNode;
  var AWriter: TNextGenJsonWriter
);
var
  Obj: TJsonObject;
  Arr: TJsonArray;
  ObjIntf: IDextJsonObject;
  ArrIntf: IDextJsonArray;
  I: Integer;
  PropName: string;
  Val: TNextGenJsonValue;
  U8: TBytes;
begin
  if ANode = nil then
  begin
    AWriter.WriteNull;
    Exit;
  end;

  if ANode is TJsonObject then
  begin
    Obj := TJsonObject(ANode);
    AWriter.StartObject;
    for I := 0 to Obj.FCount - 1 do
    begin
      if Obj.FPairs[I].Key.StrValue <> '' then
        AWriter.WritePropertyName(Obj.FPairs[I].Key.StrValue)
      else
        AWriter.WritePropertyName(Obj.FPairs[I].Key.Span);

      Val := Obj.FPairs[I].Value;
      case Val.FType of
        TDextJsonNodeType.jntObject, TDextJsonNodeType.jntArray:
          NodeToWriter(Val.NodeRef, AWriter);
        TDextJsonNodeType.jntString:
          if (Val.FStrValue <> nil) and (Val.FStrValue^ <> '') then
            AWriter.WriteStringValue(Val.FStrValue^)
          else
            AWriter.WriteStringValue(Val.FValueSpan);
        TDextJsonNodeType.jntNull:
          AWriter.WriteNull;
        TDextJsonNodeType.jntNumber, TDextJsonNodeType.jntBoolean:
          if (Val.FStrValue <> nil) and (Val.FStrValue^ <> '') then
          begin
            if Val.FType = TDextJsonNodeType.jntBoolean then
              AWriter.WriteBoolean(Val.FStrValue^ = 'true')
            else
            begin
              U8 := TEncoding.UTF8.GetBytes(Val.FStrValue^);
              AWriter.WriteRawValue(TByteSpan.FromBytes(U8));
            end;
          end
          else
            AWriter.WriteRawValue(Val.FValueSpan);
      end;
    end;
    AWriter.EndObject;
  end
  else if ANode is TJsonArray then
  begin
    Arr := TJsonArray(ANode);
    AWriter.StartArray;
    for I := 0 to Arr.FCount - 1 do
    begin
      Val := Arr.FValues[I];
      case Val.FType of
        TDextJsonNodeType.jntObject, TDextJsonNodeType.jntArray:
          NodeToWriter(Val.NodeRef, AWriter);
        TDextJsonNodeType.jntString:
          if (Val.FStrValue <> nil) and (Val.FStrValue^ <> '') then
            AWriter.WriteStringValue(Val.FStrValue^)
          else
            AWriter.WriteStringValue(Val.FValueSpan);
        TDextJsonNodeType.jntNull:
          AWriter.WriteNull;
        TDextJsonNodeType.jntNumber, TDextJsonNodeType.jntBoolean:
          if (Val.FStrValue <> nil) and (Val.FStrValue^ <> '') then
          begin
            if Val.FType = TDextJsonNodeType.jntBoolean then
              AWriter.WriteBoolean(Val.FStrValue^ = 'true')
            else
            begin
              U8 := TEncoding.UTF8.GetBytes(Val.FStrValue^);
              AWriter.WriteRawValue(TByteSpan.FromBytes(U8));
            end;
          end
          else
            AWriter.WriteRawValue(Val.FValueSpan);
      end;
    end;
    AWriter.EndArray;
  end
  else
  begin
    case ANode.GetNodeType of
      TDextJsonNodeType.jntObject:
        begin
          ObjIntf := ANode as IDextJsonObject;
          AWriter.StartObject;
          for I := 0 to ObjIntf.GetCount - 1 do
          begin
            PropName := ObjIntf.GetName(I);
            AWriter.WritePropertyName(PropName);
            NodeToWriter(ObjIntf.GetNode(PropName), AWriter);
          end;
          AWriter.EndObject;
        end;
      TDextJsonNodeType.jntArray:
        begin
          ArrIntf := ANode as IDextJsonArray;
          AWriter.StartArray;
          for I := 0 to ArrIntf.GetCount - 1 do
            NodeToWriter(ArrIntf.GetNode(I), AWriter);
          AWriter.EndArray;
        end;
      TDextJsonNodeType.jntString:
        AWriter.WriteStringValue(ANode.AsString);
      TDextJsonNodeType.jntNumber:
        AWriter.WriteNumber(ANode.AsDouble);
      TDextJsonNodeType.jntBoolean:
        AWriter.WriteBoolean(ANode.AsBoolean);
      TDextJsonNodeType.jntNull:
        AWriter.WriteNull;
    end;
  end;
end;

function FormatJson(const AJson: string): string;
var
  I: Integer;
  Indent: Integer;
  InString: Boolean;
  C: Char;
  Len: Integer;
  SB: TStringBuilder;
  J: Integer;
begin
  Len := Length(AJson);
  if Len = 0 then Exit('');

  SB := TStringBuilder.Create(Len * 2);
  try
    Indent := 0;
    InString := False;
    I := 1;
    while I <= Len do
    begin
      C := AJson[I];
      if C = '"' then
      begin
        if (I > 1) and (AJson[I - 1] = '\') then
        begin
          // escaped quote
        end
        else
          InString := not InString;

        SB.Append(C);
      end
      else if InString then
      begin
        SB.Append(C);
      end
      else
      begin
        case C of
          '{', '[':
            begin
              SB.Append(C).Append(#13#10);
              Inc(Indent);
              for J := 1 to Indent * 2 do
                SB.Append(' ');
            end;
          '}', ']':
            begin
              SB.Append(#13#10);
              Dec(Indent);
              for J := 1 to Indent * 2 do
                SB.Append(' ');
              SB.Append(C);
            end;
          ',':
            begin
              SB.Append(C).Append(#13#10);
              for J := 1 to Indent * 2 do
                SB.Append(' ');
            end;
          ':':
            begin
              SB.Append(': ');
            end;
          ' ', #13, #10, #9:
            ; // skip extra whitespace
          else
            SB.Append(C);
        end;
      end;
      Inc(I);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TJsonObject.ToJson(Indented: Boolean): string;
var
  Writer: TNextGenJsonWriter;
begin
  Writer.Init(4096);
  try
    NodeToWriter(Self, Writer);
    Result := Writer.ToString;
    if Indented then
      Result := FormatJson(Result);
  finally
    Writer.Clear;
  end;
end;

function TJsonObject.IsNull: Boolean;
begin
  Result := False;
end;

function TJsonObject.Contains(const Name: string): Boolean;
begin
  Result := FindKey(Name) >= 0;
end;

// IDextJsonObject GetNode implementation
function TJsonObject.GetNode(const Name: string): IDextJsonNode;
var
  Idx: Integer;
begin
  Idx := FindKey(Name);
  if Idx >= 0 then
  begin
    if (FPairs[Idx].Value.NodeType = TDextJsonNodeType.jntObject) or
       (FPairs[Idx].Value.NodeType = TDextJsonNodeType.jntArray) then
      Result := FPairs[Idx].Value.NodeRef
    else
      Result := TNextGenJsonPrimitive.Create(FPairs[Idx].Value);
  end
  else
    Result := nil;
end;

function TJsonObject.GetString(const Name: string): string;
var
  Idx: Integer;
begin
  Idx := FindKey(Name);
  if Idx >= 0 then
    Result := FPairs[Idx].Value.AsString
  else
    Result := '';
end;

function TJsonObject.GetInteger(const Name: string): Integer;
var
  Idx: Integer;
begin
  Idx := FindKey(Name);
  if Idx >= 0 then
    Result := FPairs[Idx].Value.AsInteger
  else
    Result := 0;
end;

function TJsonObject.GetInt64(const Name: string): Int64;
var
  Idx: Integer;
begin
  Idx := FindKey(Name);
  if Idx >= 0 then
    Result := FPairs[Idx].Value.AsInt64
  else
    Result := 0;
end;

function TJsonObject.GetDouble(const Name: string): Double;
var
  Idx: Integer;
begin
  Idx := FindKey(Name);
  if Idx >= 0 then
    Result := FPairs[Idx].Value.AsDouble
  else
    Result := 0.0;
end;

function TJsonObject.GetBoolean(const Name: string): Boolean;
var
  Idx: Integer;
begin
  Idx := FindKey(Name);
  if Idx >= 0 then
    Result := FPairs[Idx].Value.AsBoolean
  else
    Result := False;
end;

function TJsonObject.GetObject(const Name: string): IDextJsonObject;
begin
  Result := GetNode(Name) as IDextJsonObject;
end;

function TJsonObject.GetArray(const Name: string): IDextJsonArray;
begin
  Result := GetNode(Name) as IDextJsonArray;
end;

function TJsonObject.GetCount: Integer;
begin
  Result := FCount;
end;

function TJsonObject.GetName(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FPairs[Index].Key.ToString
  else
    Result := '';
end;

procedure TJsonObject.SetString(const Name, Value: string);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntString, TByteSpan.Create(nil, 0));
  Val.SetStrValue(Value);
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetInteger(const Name: string; Value: Integer);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNumber, TByteSpan.Create(nil, 0));
  Val.SetStrValue(IntToStr(Value));
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetInt64(const Name: string; Value: Int64);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNumber, TByteSpan.Create(nil, 0));
  Val.SetStrValue(IntToStr(Value));
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetDouble(const Name: string; Value: Double);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNumber, TByteSpan.Create(nil, 0));
  Val.SetStrValue(FloatToStr(Value, TFormatSettings.Invariant));
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetBoolean(const Name: string; Value: Boolean);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntBoolean, TByteSpan.Create(nil, 0));
  if Value then Val.SetStrValue('true') else Val.SetStrValue('false');
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetObject(
  const Name: string;
  Value: IDextJsonObject
);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntObject, TByteSpan.Create(nil, 0));
  Val.NodeRef := Value;
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetArray(
  const Name: string;
  Value: IDextJsonArray
);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntArray, TByteSpan.Create(nil, 0));
  Val.NodeRef := Value;
  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetNode(const Name: string; Value: IDextJsonNode);
var
  Val: TNextGenJsonValue;
begin
  if Value = nil then
  begin
    SetNull(Name);
    Exit;
  end;

  Val.Init(Value.GetNodeType, TByteSpan.Create(nil, 0));

  case Val.FType of
    TDextJsonNodeType.jntString: Val.SetStrValue(Value.AsString);
    TDextJsonNodeType.jntNumber: Val.SetStrValue(
      FloatToStr(Value.AsDouble, TFormatSettings.Invariant));
    TDextJsonNodeType.jntBoolean:
      if Value.AsBoolean then Val.SetStrValue('true') else Val.SetStrValue('false');
    TDextJsonNodeType.jntObject, TDextJsonNodeType.jntArray:
      Val.NodeRef := Value;
  end;

  AddOrReplacePair(Name, Val);
end;

procedure TJsonObject.SetNull(const Name: string);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNull, TByteSpan.Create(nil, 0));
  AddOrReplacePair(Name, Val);
end;

function TJsonObject.GetS(const Name: string): string;
begin
  Result := GetString(Name);
end;

procedure TJsonObject.SetS(const Name: string; const Value: string);
begin
  SetString(Name, Value);
end;

function TJsonObject.GetI(const Name: string): Integer;
begin
  Result := GetInteger(Name);
end;

procedure TJsonObject.SetI(const Name: string; Value: Integer);
begin
  SetInteger(Name, Value);
end;

function TJsonObject.GetL(const Name: string): Int64;
begin
  Result := GetInt64(Name);
end;

procedure TJsonObject.SetL(const Name: string; Value: Int64);
begin
  SetInt64(Name, Value);
end;

function TJsonObject.GetD(const Name: string): Double;
begin
  Result := GetDouble(Name);
end;

procedure TJsonObject.SetD(const Name: string; Value: Double);
begin
  SetDouble(Name, Value);
end;

function TJsonObject.GetB(const Name: string): Boolean;
begin
  Result := GetBoolean(Name);
end;

procedure TJsonObject.SetB(const Name: string; Value: Boolean);
begin
  SetBoolean(Name, Value);
end;

function TJsonObject.GetO(const Name: string): TJsonObject;
var
  Node: IDextJsonObject;
  Getter: IDextJsonNodeGetter;
begin
  Node := GetObject(Name);
  if (Node <> nil) and Supports(Node, IDextJsonNodeGetter, Getter) then
    Result := TJsonObject(Getter.GetSelf)
  else
    Result := nil;
end;

procedure TJsonObject.SetO(const Name: string; Value: TJsonObject);
begin
  SetObject(Name, Value);
end;

function TJsonObject.GetA(const Name: string): TJsonArray;
var
  Node: IDextJsonArray;
  Getter: IDextJsonNodeGetter;
begin
  Node := GetArray(Name);
  if (Node <> nil) and Supports(Node, IDextJsonNodeGetter, Getter) then
    Result := TJsonArray(Getter.GetSelf)
  else
    Result := nil;
end;

procedure TJsonObject.SetA(const Name: string; Value: TJsonArray);
begin
  SetArray(Name, Value);
end;

function TJsonObject.GetTypes(const Name: string): TDextJsonNodeType;
var
  Node: IDextJsonNode;
begin
  Node := GetNode(Name);
  if Node <> nil then
    Result := Node.NodeType
  else
    Result := TDextJsonNodeType.jntNull;
end;

{ TJsonArray }

function TJsonArray._Release: Integer;
begin
  if FRefCounted then
  begin
    Result := AtomicDecrement(FRefCount);
    if Result = 0 then
      TNextGenJsonPool.ReturnArray(Self);
  end
  else
    Result := -1;
end;

procedure TJsonArray.AdoptManualLifetime;
var
  I: Integer;
  P: Pointer;
  Temp: IDextJsonNode;
  Getter: IDextJsonNodeGetter;
  Child: TJsonBaseObject;
begin
  FRefCounted := False;
  for I := 0 to FCount - 1 do
  begin
    P := FValues[I].FNodeRef;
    if P = nil then
      Continue;
    Pointer(Temp) := P;
    try
      if Supports(Temp, IDextJsonNodeGetter, Getter) then
      begin
        Child := TJsonBaseObject(Getter.GetSelf);
        Getter := nil;
        Child.AdoptManualLifetime;
      end;
    finally
      Pointer(Temp) := nil;
    end;
  end;
end;

constructor TJsonArray.Create(ARefCounted: Boolean);
begin
  inherited Create(ARefCounted);
  SetLength(FValues, 0);
  FCount := 0;
end;

destructor TJsonArray.Destroy;
var
  I: Integer;
begin
  for I := 0 to FCount - 1 do
  begin
    if FValues[I].FStrValue <> nil then
      Dispose(FValues[I].FStrValue);
    FValues[I].FreeNode;
  end;
  inherited Destroy;
end;

procedure TJsonArray.AddValue(const AValue: TNextGenJsonValue);
var
  NewCap: Integer;
begin
  if FCount >= Length(FValues) then
  begin
    NewCap := Length(FValues) * 2;
    if NewCap < 8 then NewCap := 8;
    SetLength(FValues, NewCap);
  end;
  FValues[FCount] := AValue;
  Inc(FCount);
end;

function TJsonArray.GetNodeType: TDextJsonNodeType;
begin
  Result := TDextJsonNodeType.jntArray;
end;

function TJsonArray.AsString: string;
begin
  Result := ToJson;
end;

// Array getters
function TJsonArray.AsInteger: Integer;
begin
  Result := 0;
end;

function TJsonArray.AsInt64: Int64;
begin
  Result := 0;
end;

function TJsonArray.AsDouble: Double;
begin
  Result := 0.0;
end;

function TJsonArray.AsBoolean: Boolean;
begin
  Result := False;
end;

function TJsonArray.ToJson(Indented: Boolean): string;
var
  Writer: TNextGenJsonWriter;
begin
  Writer.Init(4096);
  try
    NodeToWriter(Self, Writer);
    Result := Writer.ToString;
    if Indented then
      Result := FormatJson(Result);
  finally
    Writer.Clear;
  end;
end;

function TJsonArray.IsNull: Boolean;
begin
  Result := False;
end;

function TJsonArray.GetCount: NativeInt;
begin
  Result := FCount;
end;

function TJsonArray.GetNode(Index: Integer): IDextJsonNode;
begin
  if (Index >= 0) and (Index < FCount) then
  begin
    if (FValues[Index].NodeType = TDextJsonNodeType.jntObject) or
       (FValues[Index].NodeType = TDextJsonNodeType.jntArray) then
      Result := FValues[Index].NodeRef
    else
      Result := TNextGenJsonPrimitive.Create(FValues[Index]);
  end
  else
    Result := nil;
end;

function TJsonArray.GetString(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FValues[Index].AsString
  else
    Result := '';
end;

function TJsonArray.GetInteger(Index: Integer): Integer;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FValues[Index].AsInteger
  else
    Result := 0;
end;

function TJsonArray.GetInt64(Index: Integer): Int64;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FValues[Index].AsInt64
  else
    Result := 0;
end;

function TJsonArray.GetDouble(Index: Integer): Double;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FValues[Index].AsDouble
  else
    Result := 0.0;
end;

function TJsonArray.GetBoolean(Index: Integer): Boolean;
begin
  if (Index >= 0) and (Index < FCount) then
    Result := FValues[Index].AsBoolean
  else
    Result := False;
end;

function TJsonArray.GetObject(Index: Integer): IDextJsonObject;
begin
  Result := GetNode(Index) as IDextJsonObject;
end;

function TJsonArray.GetArray(Index: Integer): IDextJsonArray;
begin
  Result := GetNode(Index) as IDextJsonArray;
end;

procedure TJsonArray.Add(const Value: string);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntString, TByteSpan.Create(nil, 0));
  Val.SetStrValue(Value);
  AddValue(Val);
end;

procedure TJsonArray.Add(Value: Integer);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNumber, TByteSpan.Create(nil, 0));
  Val.SetStrValue(IntToStr(Value));
  AddValue(Val);
end;

procedure TJsonArray.Add(Value: Int64);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNumber, TByteSpan.Create(nil, 0));
  Val.SetStrValue(IntToStr(Value));
  AddValue(Val);
end;

procedure TJsonArray.Add(Value: Double);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNumber, TByteSpan.Create(nil, 0));
  Val.SetStrValue(FloatToStr(Value, TFormatSettings.Invariant));
  AddValue(Val);
end;

procedure TJsonArray.Add(Value: Boolean);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntBoolean, TByteSpan.Create(nil, 0));
  if Value then Val.SetStrValue('true') else Val.SetStrValue('false');
  AddValue(Val);
end;

procedure TJsonArray.Add(Value: IDextJsonObject);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntObject, TByteSpan.Create(nil, 0));
  Val.NodeRef := Value;
  AddValue(Val);
end;

procedure TJsonArray.Add(Value: IDextJsonArray);
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntArray, TByteSpan.Create(nil, 0));
  Val.NodeRef := Value;
  AddValue(Val);
end;

procedure TJsonArray.AddNull;
var
  Val: TNextGenJsonValue;
begin
  Val.Init(TDextJsonNodeType.jntNull, TByteSpan.Create(nil, 0));
  AddValue(Val);
end;

function TJsonArray.GetS(Index: Integer): string;
begin
  Result := GetString(Index);
end;

procedure TJsonArray.SetS(Index: Integer; const Value: string);
begin
end;

function TJsonArray.GetI(Index: Integer): Integer;
begin
  Result := GetInteger(Index);
end;

procedure TJsonArray.SetI(Index: Integer; Value: Integer);
begin
end;

function TJsonArray.GetL(Index: Integer): Int64;
begin
  Result := GetInt64(Index);
end;

procedure TJsonArray.SetL(Index: Integer; Value: Int64);
begin
end;

function TJsonArray.GetD(Index: Integer): Double;
begin
  Result := GetDouble(Index);
end;

procedure TJsonArray.SetD(Index: Integer; Value: Double);
begin
end;

function TJsonArray.GetB(Index: Integer): Boolean;
begin
  Result := GetBoolean(Index);
end;

procedure TJsonArray.SetB(Index: Integer; Value: Boolean);
begin
end;

function TJsonArray.GetO(Index: Integer): TJsonObject;
var
  Node: IDextJsonObject;
  Getter: IDextJsonNodeGetter;
begin
  Node := GetObject(Index);
  if (Node <> nil) and Supports(Node, IDextJsonNodeGetter, Getter) then
    Result := TJsonObject(Getter.GetSelf)
  else
    Result := nil;
end;

function TJsonArray.GetA(Index: Integer): TJsonArray;
var
  Node: IDextJsonArray;
  Getter: IDextJsonNodeGetter;
begin
  Node := GetArray(Index);
  if (Node <> nil) and Supports(Node, IDextJsonNodeGetter, Getter) then
    Result := TJsonArray(Getter.GetSelf)
  else
    Result := nil;
end;

function TJsonArray.GetTypes(Index: Integer): TDextJsonNodeType;
var
  Node: IDextJsonNode;
begin
  Node := GetNode(Index);
  if Node <> nil then
    Result := Node.NodeType
  else
    Result := TDextJsonNodeType.jntNull;
end;

procedure TJsonArray.Add(Value: TJsonObject);
begin
  Add(Value as IDextJsonObject);
end;

procedure TJsonArray.Add(Value: TJsonArray);
begin
  Add(Value as IDextJsonArray);
end;

{ TNextGenJsonPrimitive }

constructor TNextGenJsonPrimitive.Create(const AValue: TNextGenJsonValue);
begin
  inherited Create;
  { Deep-copy primitives so the wrapper does not alias FStrValue/FValueSpan from
    a parent TJsonObject (GetNode/GetId must remain valid independently, and must
    not double-Dispose the parent's PString). }
  FValue.Init(AValue.NodeType, TByteSpan.Create(nil, 0));
  case AValue.NodeType of
    TDextJsonNodeType.jntString,
    TDextJsonNodeType.jntNumber,
    TDextJsonNodeType.jntBoolean:
      FValue.SetStrValue(AValue.AsString);
    TDextJsonNodeType.jntNull:
      ;
  else
    { Object/array must not go through Primitive; treat as null. }
    FValue.Init(TDextJsonNodeType.jntNull, TByteSpan.Create(nil, 0));
  end;
end;

destructor TNextGenJsonPrimitive.Destroy;
begin
  if FValue.FStrValue <> nil then
  begin
    Dispose(FValue.FStrValue);
    FValue.FStrValue := nil;
  end;
  FValue.FreeNode;
  inherited Destroy;
end;

function TNextGenJsonPrimitive.GetNodeType: TDextJsonNodeType;
begin
  Result := FValue.NodeType;
end;

function TNextGenJsonPrimitive.AsString: string;
begin
  Result := FValue.AsString;
end;

function TNextGenJsonPrimitive.AsInteger: Integer;
begin
  Result := FValue.AsInteger;
end;

function TNextGenJsonPrimitive.AsInt64: Int64;
begin
  Result := FValue.AsInt64;
end;

function TNextGenJsonPrimitive.AsDouble: Double;
begin
  Result := FValue.AsDouble;
end;

function TNextGenJsonPrimitive.AsBoolean: Boolean;
begin
  Result := FValue.AsBoolean;
end;

function TNextGenJsonPrimitive.ToJson(Indented: Boolean): string;
var
  Writer: TNextGenJsonWriter;
begin
  Writer.Init(128);
  try
    NodeToWriter(Self, Writer);
    Result := Writer.ToString;
    if Indented then
      Result := FormatJson(Result);
  finally
    Writer.Clear;
  end;
end;

function TNextGenJsonPrimitive.IsNull: Boolean;
begin
  Result := FValue.IsNull;
end;

{ TThreadNodePool -- per-thread node pool. Fixes the data race of the previous }
{ global class-var pool: each thread recycles ONLY its own TJsonObject/TJsonArray }
{ instances, so Rent/Return need no lock. The pool is held by a threadvar        }
{ interface (GNodePoolKeeper) so it is freed automatically when the owning thread }
{ terminates (RTL threadvar finalization). GNodePool is a raw ref for fast access }
{ on the hot path (no per-call AddRef/Release).                                   }

type
  TThreadNodePool = class
  strict private
    FObjectPool: array[0..1023] of TJsonObject;
    FObjectCount: Integer;
    FArrayPool: array[0..1023] of TJsonArray;
    FArrayCount: Integer;
  private
    FNext: TThreadNodePool;
  public
    destructor Destroy; override;
    function RentObject: TJsonObject;
    procedure ReturnObject(AnObj: TJsonObject);
    function RentArray: TJsonArray;
    procedure ReturnArray(AnArr: TJsonArray);
    procedure Clear;
  end;

var
  GNodePoolHead: TThreadNodePool = nil;
  GNodePoolLock: TSpinLock;
  GFinalized: Boolean = False;

threadvar
  GNodePool: TThreadNodePool;

function CurrentNodePool: TThreadNodePool; inline;
begin
  if GFinalized then
    Exit(nil);
  Result := GNodePool;
  if Result = nil then
  begin
    Result := TThreadNodePool.Create;
    GNodePool := Result;
    
    GNodePoolLock.Enter;
    try
      Result.FNext := GNodePoolHead;
      GNodePoolHead := Result;
    finally
      GNodePoolLock.Exit;
    end;
  end;
end;

destructor TThreadNodePool.Destroy;
var
  Prev, Curr: TThreadNodePool;
begin
  if not GFinalized then
  begin
    GNodePoolLock.Enter;
    try
      Prev := nil;
      Curr := GNodePoolHead;
      while Curr <> nil do
      begin
        if Curr = Self then
        begin
          if Prev <> nil then
            Prev.FNext := FNext
          else
            GNodePoolHead := FNext;
          Break;
        end;
        Prev := Curr;
        Curr := Curr.FNext;
      end;
    finally
      GNodePoolLock.Exit;
    end;
  end;

  Clear;
  inherited;
end;

function TThreadNodePool.RentObject: TJsonObject;
begin
  if FObjectCount > 0 then
  begin
    Dec(FObjectCount);
    Result := FObjectPool[FObjectCount];
    Result.FRefCounted := True;
    Result.FRefCount := 0;
  end
  else
    Result := TJsonObject.Create(True);
end;

procedure TThreadNodePool.ReturnObject(AnObj: TJsonObject);
var
  I: Integer;
begin
  for I := 0 to AnObj.FCount - 1 do
  begin
    if AnObj.FPairs[I].Value.FStrValue <> nil then
    begin
      Dispose(AnObj.FPairs[I].Value.FStrValue);
      AnObj.FPairs[I].Value.FStrValue := nil;
    end;
    AnObj.FPairs[I].Value.FreeNode;
  end;
  AnObj.FCount := 0;
  AnObj.FKeepAlive := nil;

  if FObjectCount < 1024 then
  begin
    FObjectPool[FObjectCount] := AnObj;
    Inc(FObjectCount);
  end
  else
    AnObj.Free;
end;

function TThreadNodePool.RentArray: TJsonArray;
begin
  if FArrayCount > 0 then
  begin
    Dec(FArrayCount);
    Result := FArrayPool[FArrayCount];
    Result.FRefCounted := True;
    Result.FRefCount := 0;
  end
  else
    Result := TJsonArray.Create(True);
end;

procedure TThreadNodePool.ReturnArray(AnArr: TJsonArray);
var
  I: Integer;
begin
  for I := 0 to AnArr.FCount - 1 do
  begin
    if AnArr.FValues[I].FStrValue <> nil then
    begin
      Dispose(AnArr.FValues[I].FStrValue);
      AnArr.FValues[I].FStrValue := nil;
    end;
    AnArr.FValues[I].FreeNode;
  end;
  AnArr.FCount := 0;
  AnArr.FKeepAlive := nil;

  if FArrayCount < 1024 then
  begin
    FArrayPool[FArrayCount] := AnArr;
    Inc(FArrayCount);
  end
  else
    AnArr.Free;
end;

procedure TThreadNodePool.Clear;
var
  I: Integer;
begin
  for I := 0 to FObjectCount - 1 do
    FObjectPool[I].Free;
  FObjectCount := 0;
  for I := 0 to FArrayCount - 1 do
    FArrayPool[I].Free;
  FArrayCount := 0;
end;

{ TNextGenJsonPool -- thin facade delegating to the current thread's pool }

class function TNextGenJsonPool.RentObject: TJsonObject;
var
  Pool: TThreadNodePool;
begin
  Pool := CurrentNodePool;
  if Pool <> nil then
    Result := Pool.RentObject
  else
    Result := TJsonObject.Create(True);
end;

class procedure TNextGenJsonPool.ReturnObject(AnObj: TJsonObject);
var
  Pool: TThreadNodePool;
begin
  if AnObj = nil then Exit;
  Pool := CurrentNodePool;
  if Pool <> nil then
    Pool.ReturnObject(AnObj)
  else
    AnObj.Free;
end;

class function TNextGenJsonPool.RentArray: TJsonArray;
var
  Pool: TThreadNodePool;
begin
  Pool := CurrentNodePool;
  if Pool <> nil then
    Result := Pool.RentArray
  else
    Result := TJsonArray.Create(True);
end;

class procedure TNextGenJsonPool.ReturnArray(AnArr: TJsonArray);
var
  Pool: TThreadNodePool;
begin
  if AnArr = nil then Exit;
  Pool := CurrentNodePool;
  if Pool <> nil then
    Pool.ReturnArray(AnArr)
  else
    AnArr.Free;
end;

class procedure TNextGenJsonPool.ClearPool;
begin
  CurrentNodePool.Clear;
end;

{ TJSONBufferOwner }

constructor TJSONBufferOwner.Create(const ABytes: TBytes);
begin
  inherited Create;
  FBytes := ABytes;
end;

{ TNextGenJsonProvider }

constructor TNextGenJsonProvider.Create(AMaxDepth: Integer);
begin
  inherited Create;
  FMaxDepth := AMaxDepth;
end;

function TNextGenJsonProvider.CreateObject: IDextJsonObject;
begin
  Result := TNextGenJsonPool.RentObject;
end;

function TNextGenJsonProvider.CreateArray: IDextJsonArray;
begin
  Result := TNextGenJsonPool.RentArray;
end;

function TNextGenJsonProvider.Parse(const Json: string): IDextJsonNode;
var
  Bytes: TBytes;
  Span: TByteSpan;
  Owner: IJSONBufferOwner;
begin
  if Json = '' then
    raise EJsonException.Create('Empty JSON string');
  Bytes := TEncoding.UTF8.GetBytes(Json);
  Span := TByteSpan.FromBytes(Bytes);
  Owner := TJSONBufferOwner.Create(Bytes);
  Result := TNextGenJsonParser.Parse(Span, Owner, FMaxDepth);
end;

const
  GHex: array[0..15] of Char = '0123456789abcdef';

{ TNextGenJsonWriter }

procedure TNextGenJsonWriter.Init(InitialCapacity: Integer);
begin
  SetLength(FBuffer, InitialCapacity);
  FLength := 0;
  FNeedComma := False;
end;

procedure TNextGenJsonWriter.Clear;
begin
  FLength := 0;
  FNeedComma := False;
end;

procedure TNextGenJsonWriter.EnsureCapacity(ANeeded: Integer);
var
  NewCap: Integer;
  BufferLen: Integer;
begin
  BufferLen := System.Length(FBuffer);
  if FLength + ANeeded > BufferLen then
  begin
    NewCap := BufferLen * 2;
    if NewCap < FLength + ANeeded then
      NewCap := FLength + ANeeded + 65536;
    if NewCap < 512 then
      NewCap := 512;
    SetLength(FBuffer, NewCap);
  end;
end;

procedure TNextGenJsonWriter.WriteRawByte(AByte: Byte);
begin
  EnsureCapacity(1);
  FBuffer[FLength] := AByte;
  Inc(FLength);
end;

procedure TNextGenJsonWriter.WriteRawBytes(const ABytes: TBytes);
var
  Len: Integer;
begin
  Len := System.Length(ABytes);
  if Len > 0 then
  begin
    EnsureCapacity(Len);
    Move(ABytes[0], FBuffer[FLength], Len);
    Inc(FLength, Len);
  end;
end;

procedure TNextGenJsonWriter.WriteRawBytes(APtr: Pointer; ALength: Integer);
begin
  if ALength > 0 then
  begin
    EnsureCapacity(ALength);
    Move(APtr^, FBuffer[FLength], ALength);
    Inc(FLength, ALength);
  end;
end;

procedure TNextGenJsonWriter.WriteCommaIfNeeded;
begin
  if FNeedComma then
  begin
    WriteRawByte(Ord(','));
    FNeedComma := False;
  end;
end;

procedure TNextGenJsonWriter.StartObject;
begin
  if FNeedComma then
    WriteRawByte(Ord(','));
  WriteRawByte(Ord('{'));
  FNeedComma := False;
end;

procedure TNextGenJsonWriter.EndObject;
begin
  WriteRawByte(Ord('}'));
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.StartArray;
begin
  if FNeedComma then
    WriteRawByte(Ord(','));
  WriteRawByte(Ord('['));
  FNeedComma := False;
end;

procedure TNextGenJsonWriter.EndArray;
begin
  WriteRawByte(Ord(']'));
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WritePropertyName(const AName: string);
begin
  if FNeedComma then
    WriteRawByte(Ord(','));
  WriteEscapedString(AName);
  WriteRawByte(Ord(':'));
  FNeedComma := False;
end;

procedure TNextGenJsonWriter.WritePropertyName(const AKey: TByteSpan);
begin
  if FNeedComma then
    WriteRawByte(Ord(','));
  WriteRawByte(Ord('"'));
  WriteRawBytes(AKey.Data, AKey.Length);
  WriteRawByte(Ord('"'));
  WriteRawByte(Ord(':'));
  FNeedComma := False;
end;

procedure TNextGenJsonWriter.WriteStringValue(const AValue: string);
begin
  WriteCommaIfNeeded;
  WriteEscapedString(AValue);
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteStringValue(const AValue: TByteSpan);
begin
  WriteCommaIfNeeded;
  WriteRawByte(Ord('"'));
  WriteRawBytes(AValue.Data, AValue.Length);
  WriteRawByte(Ord('"'));
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteRawValue(const AValue: TByteSpan);
begin
  WriteCommaIfNeeded;
  WriteRawBytes(AValue.Data, AValue.Length);
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteNumber(AValue: Int64);
var
  S: string;
  U8: TBytes;
begin
  WriteCommaIfNeeded;
  S := IntToStr(AValue);
  U8 := TEncoding.UTF8.GetBytes(S);
  WriteRawBytes(U8);
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteNumber(AValue: Double);
var
  S: string;
  U8: TBytes;
begin
  WriteCommaIfNeeded;
  S := FloatToStr(AValue, TFormatSettings.Invariant);
  U8 := TEncoding.UTF8.GetBytes(S);
  WriteRawBytes(U8);
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteBoolean(AValue: Boolean);
begin
  WriteCommaIfNeeded;
  if AValue then
  begin
    EnsureCapacity(4);
    FBuffer[FLength] := Ord('t');
    FBuffer[FLength+1] := Ord('r');
    FBuffer[FLength+2] := Ord('u');
    FBuffer[FLength+3] := Ord('e');
    Inc(FLength, 4);
  end
  else
  begin
    EnsureCapacity(5);
    FBuffer[FLength] := Ord('f');
    FBuffer[FLength+1] := Ord('a');
    FBuffer[FLength+2] := Ord('l');
    FBuffer[FLength+3] := Ord('s');
    FBuffer[FLength+4] := Ord('e');
    Inc(FLength, 5);
  end;
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteNull;
begin
  WriteCommaIfNeeded;
  EnsureCapacity(4);
  FBuffer[FLength] := Ord('n');
  FBuffer[FLength+1] := Ord('u');
  FBuffer[FLength+2] := Ord('l');
  FBuffer[FLength+3] := Ord('l');
  Inc(FLength, 4);
  FNeedComma := True;
end;

procedure TNextGenJsonWriter.WriteEscapedString(const AValue: string);
var
  P: PChar;
  C: Char;
  C2: Word;
  Val: Cardinal;
begin
  WriteRawByte(Ord('"'));
  if AValue <> '' then
  begin
    P := PChar(AValue);
    while P^ <> #0 do
    begin
      C := P^;
      if (C >= ' ') and (C <= '~') and (C <> '"') and (C <> '\') then
      begin
        WriteRawByte(Byte(C));
      end
      else
      begin
        case C of
          '"': begin WriteRawByte(Ord('\')); WriteRawByte(Ord('"')); end;
          '\': begin WriteRawByte(Ord('\')); WriteRawByte(Ord('\')); end;
          #8: begin WriteRawByte(Ord('\')); WriteRawByte(Ord('b')); end;
          #9: begin WriteRawByte(Ord('\')); WriteRawByte(Ord('t')); end;
          #10: begin WriteRawByte(Ord('\')); WriteRawByte(Ord('n')); end;
          #12: begin WriteRawByte(Ord('\')); WriteRawByte(Ord('f')); end;
          #13: begin WriteRawByte(Ord('\')); WriteRawByte(Ord('r')); end;
        else
          if C < ' ' then
          begin
            WriteRawByte(Ord('\'));
            WriteRawByte(Ord('u'));
            WriteRawByte(Ord('0'));
            WriteRawByte(Ord('0'));
            WriteRawByte(Byte(GHex[Ord(C) shr 4]));
            WriteRawByte(Byte(GHex[Ord(C) and $F]));
          end
          else
          begin
            Val := Ord(C);
            // A high surrogate is combined only with a real low surrogate.
            // The next char is always readable: at the end of the string it
            // is the #0 terminator, which is not a low surrogate.
            C2 := Ord((P + 1)^);
            if (Val >= $D800) and (Val <= $DBFF) and
              (C2 >= $DC00) and (C2 <= $DFFF) then
            begin
              Inc(P);
              Val := ((Val - Cardinal($D800)) shl 10) +
                (Cardinal(C2) - Cardinal($DC00)) + Cardinal($10000);
            end
            else if (Val >= $D800) and (Val <= $DFFF) then
              Val := $FFFD; // unpaired surrogate: U+FFFD, as Dext.Json.Utf8 does

            if Val <= $7F then
            begin
              WriteRawByte(Val);
            end
            else if Val <= $7FF then
            begin
              WriteRawByte($C0 or (Val shr 6));
              WriteRawByte($80 or (Val and $3F));
            end
            else if Val <= $FFFF then
            begin
              WriteRawByte($E0 or (Val shr 12));
              WriteRawByte($80 or ((Val shr 6) and $3F));
              WriteRawByte($80 or (Val and $3F));
            end
            else
            begin
              WriteRawByte($F0 or (Val shr 18));
              WriteRawByte($80 or ((Val shr 12) and $3F));
              WriteRawByte($80 or ((Val shr 6) and $3F));
              WriteRawByte($80 or (Val and $3F));
            end;
          end;
        end;
      end;
      Inc(P);
    end;
  end;
  WriteRawByte(Ord('"'));
end;

function TNextGenJsonWriter.ToBytes: TBytes;
begin
  SetLength(Result, FLength);
  if FLength > 0 then
    Move(FBuffer[0], Result[0], FLength);
end;

function TNextGenJsonWriter.ToString: string;
begin
  if FLength > 0 then
    Result := TEncoding.UTF8.GetString(FBuffer, 0, FLength)
  else
    Result := '';
end;

procedure TNextGenJsonWriter.SaveToFile(const AFileName: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    if FLength > 0 then
      FS.WriteBuffer(FBuffer[0], FLength);
  finally
    FS.Free;
  end;
end;

initialization
  GFinalized := False;
  GNodePoolLock := TSpinLock.Create(False);

  FillChar(GWhitespace, SizeOf(GWhitespace), 0);
  GWhitespace[9] := 1;
  GWhitespace[10] := 1;
  GWhitespace[13] := 1;
  GWhitespace[32] := 1;

  FillChar(GStructural, SizeOf(GStructural), 0);
  GStructural[Ord('{')] := 1;
  GStructural[Ord('}')] := 1;
  GStructural[Ord('[')] := 1;
  GStructural[Ord(']')] := 1;
  GStructural[Ord(':')] := 1;
  GStructural[Ord(',')] := 1;
  GStructural[Ord('"')] := 1;
  GStructural[Ord('\')] := 1;

finalization
  GFinalized := True;
  GNodePoolLock.Enter;
  try
    while GNodePoolHead <> nil do
    begin
      var Temp := GNodePoolHead;
      GNodePoolHead := Temp.FNext;
      Temp.Free;
    end;
  finally
    GNodePoolLock.Exit;
  end;

  GNodePool := nil;

end.
