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
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2026-03-30                                                      }
{                                                                           }
{  Dext.Core.Debug - Stack Trace + MAP File Symbol Resolution               }
{                                                                           }
{  MAP file is loaded lazily on first exception (not at startup).           }
{  Uses pre-allocated ring buffer for zero-allocation exception handling.   }
{                                                                           }
{***************************************************************************}
unit Dext.Core.Debug;

interface

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Winapi.Messages,
{$ENDIF}
  System.SysUtils;

const
  /// <summary>Hard cap for captured frames (buffer size). Use Options.MaxFrames to choose how many.</summary>
  DBG_STACK_LENGTH = 64;

type
  TDbgInfoStack = array[0..DBG_STACK_LENGTH - 1] of Pointer;
  PDbgInfoStack = ^TDbgInfoStack;
  PExceptionRecord = System.PExceptionRecord;

  /// <summary>
  ///   Configuration options for the symbol resolver and stack trace capture.
  /// </summary>
  TDbgOptions = record
    /// <summary>If True, waits for the .map file to be processed before returning the stack trace.</summary>
    WaitOnResolve: Boolean;
    /// <summary>If True, only attempts resolution if the .map file is already loaded (otherwise shows hex).</summary>
    ResolveOnlyIfLoaded: Boolean;
    /// <summary>If True, loads the .map file on a background thread.</summary>
    AsyncLoad: Boolean;
    /// <summary>
    ///   How many frames to capture (1..DBG_STACK_LENGTH). Analogous to FastMM5
    ///   StackDepth. Default 32.
    /// </summary>
    MaxFrames: Integer;
    procedure InitDefaults;
  end;

  /// <summary>
  ///   Provides tools for capturing stack traces and resolving memory addresses to symbols using MAP files.
  /// </summary>
  TStackTrace = record
  public
    class var Options: TDbgOptions;
    /// <summary>Ensures the background loader for the MAP file is started.</summary>
    class procedure EnsureInitialized; static;
    /// <summary>Captures the current call stack as a formatted string.</summary>
    class function Capture(FramesToSkip: Integer = 2): string; static;
    /// <summary>Resolves a memory address to a human-readable symbol (Unit.Procedure + Offset).</summary>
    class function ResolveAddress(Address: Pointer): string; static;
  end;

{$IFDEF MSWINDOWS}
function RtlCaptureStackBackTrace(FramesToSkip: ULONG; FramesToCapture: ULONG;
  BackTrace: Pointer; BackTraceHash: PULONG): USHORT; stdcall; external 'kernel32.dll';
{$ENDIF}

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Threading,
  System.SyncObjs,
  Dext.Threading.Async,
  Dext.Threading.CancellationToken;

const
  STACK_POOL_SIZE = 8;

type
  TMapSymbol = record
    RVA: NativeUInt;
    Name: string;
  end;

  TMapLine = record
    RVA: NativeUInt;
    Line: Integer;
    SourceFile: string;
  end;

var
  StackPool: array[0..STACK_POOL_SIZE - 1] of TDbgInfoStack;
  StackPoolIndex: Integer = 0;

  MapSymbols: TArray<TMapSymbol>;
  MapSymbolCount: Integer = 0;
  MapLines: TArray<TMapLine>;
  MapLineCount: Integer = 0;
  MapLoaded: Boolean = False;
  MapLoadAttempted: Boolean = False; // Lazy: only try once
  MapModuleBase: NativeUInt = 0;
  MapModuleSize: NativeUInt = 0;
  
  MapLoadTask: IAsyncTask = nil;
  MapLoadTokenSource: TCancellationTokenSource = nil;
  MapReadyEvent: TEvent = nil;

{ PE Header Helpers }

{$IFDEF MSWINDOWS}
procedure ReadPEInfo(Module: HMODULE; out ImageBase, SizeOfImage: NativeUInt);
var
  P: PByte;
  PEOff: Integer;
  Magic: Word;
begin
  ImageBase := $400000;
  SizeOfImage := $1000000;
  try
    P := PByte(Module);
    if PWord(P)^ <> $5A4D then Exit;
    PEOff := PInteger(P + $3C)^;
    if PCardinal(P + PEOff)^ <> $4550 then Exit;
    
    Magic := PWord(P + PEOff + 24)^;
    if Magic = $010B then // PE32
    begin
      ImageBase := PCardinal(P + PEOff + 24 + 28)^;
      SizeOfImage := PCardinal(P + PEOff + 24 + 56)^;
    end
    else if Magic = $020B then // PE32+
    begin
      {$IFDEF WIN64}
      ImageBase := PUInt64(P + PEOff + 24 + 24)^;
      {$ELSE}
      ImageBase := PCardinal(P + PEOff + 24 + 24)^; // Just read low 32 bits if on 32-bit (rare for PE32+)
      {$ENDIF}
      SizeOfImage := PCardinal(P + PEOff + 24 + 56)^;
    end;
  except
  end;
end;
{$ENDIF}

{ MAP File Parser - Optimized bulk read }

procedure LoadMapFile;
var
  MapPath: string;
  Stream: TFileStream;
  Buf: TBytes;
  BufLen: Integer;
  Pos, LineStart, I: Integer;
  InPublics, InLines: Boolean;
  CurrentSource: string;
  {$IFDEF MSWINDOWS}
  ImageBase: NativeUInt;
  {$ENDIF}

  function GetLine(out S: string): Boolean;
  begin
    if Pos > BufLen then Exit(False);
    LineStart := Pos;
    while (Pos <= BufLen) and (Buf[Pos - 1] <> 10) do Inc(Pos);
    // Remove CR+LF
    I := Pos - 1;
    if (I >= LineStart) and (Buf[I - 1] = 13) then Dec(I);
    
    if I >= LineStart then
      SetString(S, PAnsiChar(@Buf[LineStart - 1]), I - LineStart + 1)
    else
      S := '';
      
    Inc(Pos); // skip LF
    Result := True;
  end;

  function ParseHex8(Idx: Integer): Int64;
  var
    J: Integer;
    C: Byte;
    V: Int64;
  begin
    // Fast hex parse of 8 chars at position Idx (1-based in string)
    V := 0;
    for J := Idx to Idx + 7 do
    begin
      C := Byte(Buf[LineStart - 1 + J - 1]);
      if (C >= Byte('0')) and (C <= Byte('9')) then
        V := (V shl 4) or (C - Byte('0'))
      else if (C >= Byte('A')) and (C <= Byte('F')) then
        V := (V shl 4) or (C - Byte('A') + 10)
      else if (C >= Byte('a')) and (C <= Byte('f')) then
        V := (V shl 4) or (C - Byte('a') + 10)
      else
        Exit(-1);
    end;
    Result := V;
  end;

  procedure GrowSymbols; inline;
  begin
    if MapSymbolCount >= Length(MapSymbols) then
      SetLength(MapSymbols, Length(MapSymbols) * 2);
  end;

  procedure GrowLines; inline;
  begin
    if MapLineCount >= Length(MapLines) then
      SetLength(MapLines, Length(MapLines) * 2);
  end;

  procedure ParsePublicLine(const S: string);
  var
    Off: Int64;
    SymName: string;
  begin
    // Format: " 0001:XXXXXXXX       SymbolName"
    if Length(S) < 14 then Exit;
    if S[5] <> ':' then Exit;
    if Copy(S, 1, 4) <> '0001' then Exit; // CODE segment only

    Off := StrToInt64Def('$' + Copy(S, 6, 8), -1);
    if Off < 0 then Exit;

    SymName := TrimLeft(Copy(S, 14, Length(S)));
    if (SymName = '') or SymName.StartsWith('..') then Exit;

    GrowSymbols;
    // Map offsets for 0001: (CODE) are already RVAs (they match Address - MapModuleBase)
    MapSymbols[MapSymbolCount].RVA := NativeUInt(Off);
    MapSymbols[MapSymbolCount].Name := SymName;
    Inc(MapSymbolCount);
  end;

  procedure ParseLineNumbers(const S: string; const Source: string);
  var
    P, PLen, NumStart, LN: Integer;
    Off: Int64;
  begin
    P := 1;
    PLen := Length(S);
    while P <= PLen do
    begin
      while (P <= PLen) and (S[P] <= ' ') do Inc(P);
      if P > PLen then Break;

      NumStart := P;
      while (P <= PLen) and (S[P] >= '0') and (S[P] <= '9') do Inc(P);
      if P = NumStart then Break;
      LN := StrToIntDef(Copy(S, NumStart, P - NumStart), 0);
      if LN = 0 then Break;

      while (P <= PLen) and (S[P] <= ' ') do Inc(P);
      if P + 12 > PLen + 1 then Break;
      if Copy(S, P, 4) <> '0001' then
      begin
        while (P <= PLen) and (S[P] > ' ') do Inc(P);
        Continue;
      end;
      if S[P + 4] <> ':' then Break;

      Off := StrToInt64Def('$' + Copy(S, P + 5, 8), -1);
      if Off >= 0 then
      begin
        GrowLines;
        // Map offsets for 0001: (CODE) are already RVAs
        MapLines[MapLineCount].RVA := NativeUInt(Off);
        MapLines[MapLineCount].Line := LN;
        MapLines[MapLineCount].SourceFile := Source;
        Inc(MapLineCount);
      end;
      P := P + 13;
    end;
  end;

var
  S: string;
  L: TStringList;
begin
  try
    if MapLoadAttempted then Exit;
    MapLoadAttempted := True;
    
    try
      MapPath := ChangeFileExt(ParamStr(0), '.map');
    if not FileExists(MapPath) then
    begin
      // Check Output directory (common in Dext build layout)
      MapPath := System.IOUtils.TPath.GetDirectoryName(ParamStr(0));
      MapPath := System.IOUtils.TPath.Combine(System.IOUtils.TPath.GetDirectoryName(MapPath), 'Output');
      MapPath := System.IOUtils.TPath.Combine(MapPath, ChangeFileExt(ExtractFileName(ParamStr(0)), '.map'));
      if not FileExists(MapPath) then Exit;
    end;

    {$IFDEF MSWINDOWS}
    MapModuleBase := NativeUInt(GetModuleHandle(nil));
    ReadPEInfo(HMODULE(MapModuleBase), ImageBase, MapModuleSize);
    {$ELSE}
    MapModuleBase := 0;
    MapModuleSize := 0;
    {$ENDIF}

  // Read entire file into memory for fast parsing
  Stream := TFileStream.Create(MapPath, fmOpenRead or fmShareDenyNone);
  try
    BufLen := Stream.Size;
    SetLength(Buf, BufLen);
    Stream.ReadBuffer(Buf[0], BufLen);
  finally
    Stream.Free;
  end;

  SetLength(MapSymbols, 8192);
  SetLength(MapLines, 32768);
  InPublics := False;
  InLines := False;
  CurrentSource := '';
  Pos := 1;

  while GetLine(S) do
  begin
    if System.Pos('Publics by Value', S) > 0 then
    begin
      InPublics := True;
      InLines := False;
      Continue;
    end;

    if System.Pos('Line numbers for ', S) > 0 then
    begin
      InPublics := False;
      InLines := True;
      // Extract source filename from "Line numbers for Unit(File.pas) segment .text"
      I := System.Pos('(', S);
      if I > 0 then
      begin
        CurrentSource := Copy(S, I + 1, Length(S));
        I := System.Pos(')', CurrentSource);
        if I > 0 then CurrentSource := Copy(CurrentSource, 1, I - 1);
      end
      else
      begin
        CurrentSource := Copy(S, 18, Length(S));
        I := System.Pos(' segment', CurrentSource);
        if I > 0 then CurrentSource := Copy(CurrentSource, 1, I - 1);
      end;
      CurrentSource := Trim(CurrentSource);
      Continue;
    end;

    if System.Pos('Bound resource', S) > 0 then
    begin
      InPublics := False;
      InLines := False;
      Continue;
    end;

    if InPublics then
      ParsePublicLine(TrimLeft(S))
    else if InLines and (Length(S) > 5) and (S[1] <= ' ') then
      ParseLineNumbers(S, CurrentSource);
  end;

    // Free raw buffer
    SetLength(Buf, 0);

    SetLength(MapSymbols, MapSymbolCount);
    SetLength(MapLines, MapLineCount);
    MapLoaded := (MapSymbolCount > 0);
    except
      on E: Exception do
      begin
        L := TStringList.Create;
        try
          L.Add('Dext MAP Error: ' + E.ClassName + ' - ' + E.Message);
          L.SaveToFile('C:\dev\MapException.txt');
        finally
          L.Free;
        end;
      end;
    end;
  finally
    if Assigned(MapReadyEvent) then
      MapReadyEvent.SetEvent;
  end;
end;

procedure EnsureMapLoaded; inline;
begin
  if not MapLoadAttempted then
    LoadMapFile;
    
  if Assigned(MapReadyEvent) and TStackTrace.Options.WaitOnResolve then
    MapReadyEvent.WaitFor(60000); // Aguarda até 60s o processamento do .map para não mostrar hex "inútil"
end;

{ Binary Search }

function FindNearestSymbol(RVA: NativeUInt; out Name: string; out Delta, SymRVA, NextSymRVA: NativeUInt): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  Result := False;
  SymRVA := 0;
  NextSymRVA := High(NativeUInt);
  if MapSymbolCount = 0 then Exit;
  Lo := 0;
  Hi := MapSymbolCount - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if MapSymbols[Mid].RVA <= RVA then Lo := Mid + 1
    else Hi := Mid - 1;
  end;
  if Hi >= 0 then
  begin
    Name := MapSymbols[Hi].Name;
    SymRVA := MapSymbols[Hi].RVA;
    Delta := RVA - SymRVA;
    if Hi + 1 < MapSymbolCount then
      NextSymRVA := MapSymbols[Hi + 1].RVA
    else
      NextSymRVA := High(NativeUInt);
    Result := True;
  end;
end;

function FindNearestLine(RVA, SymRVA, NextSymRVA: NativeUInt; out SourceFile: string; out LineNum: Integer): Boolean;
var
  Lo, Hi, Mid: Integer;
begin
  // Nearest line with LineRVA <= address is NOT enough: units without line
  // numbers inherit the previous unit's last line (often System.Generics.*).
  // Only accept a line that falls inside the current public symbol's RVA span.
  Result := False;
  if MapLineCount = 0 then Exit;
  Lo := 0;
  Hi := MapLineCount - 1;
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if MapLines[Mid].RVA <= RVA then Lo := Mid + 1
    else Hi := Mid - 1;
  end;
  if (Hi >= 0) and (MapLines[Hi].RVA >= SymRVA) and (MapLines[Hi].RVA < NextSymRVA) then
  begin
    SourceFile := MapLines[Hi].SourceFile;
    LineNum := MapLines[Hi].Line;
    Result := True;
  end;
end;

{ Module Resolution }

{$IFDEF MSWINDOWS}
function GetModuleFromAddress(Address: Pointer): HMODULE;
var
  MemInfo: TMemoryBasicInformation;
begin
  Result := 0;
  try
    if VirtualQuery(Address, MemInfo, SizeOf(MemInfo)) = SizeOf(MemInfo) then
      Result := HMODULE(MemInfo.AllocationBase);
  except
    Result := 0;
  end;
end;

function GetModuleNameFromHandle(Module: HMODULE): string;
var
  Buf: array[0..MAX_PATH] of Char;
begin
  try
    if GetModuleFileName(Module, Buf, MAX_PATH) > 0 then
      Result := ExtractFileName(Buf)
    else
      Result := '???';
  except
    Result := '???';
  end;
end;
{$ENDIF}

{ Address Resolution }

function ResolveAddr(Address: Pointer): string;
label
  Fallback;
var
  Offset: NativeUInt;
  SymName, SourceFile: string;
  SymDelta, SymRVA, NextSymRVA: NativeUInt;
  LineNum: Integer;
  {$IFDEF MSWINDOWS}
  Module: HMODULE;
  {$ENDIF}
begin
  if TStackTrace.Options.ResolveOnlyIfLoaded and not MapLoaded then
    goto Fallback;

  if MapLoaded and (MapModuleBase <> 0) and
     (NativeUInt(Address) >= MapModuleBase) and
     (NativeUInt(Address) < MapModuleBase + MapModuleSize) then
  begin
    Offset := NativeUInt(Address) - MapModuleBase;
    
    // In PE32/PE64, Delphi's 0001: CODE segment maps to RVA $1000.
    // So the offsets in the .map file are $1000 less than the execution RVA.
    if Offset >= $1000 then
      Offset := Offset - $1000;

    if FindNearestSymbol(Offset, SymName, SymDelta, SymRVA, NextSymRVA) then
    begin
      if SymDelta = 0 then
        Result := SymName
      else
        Result := Format('%s + $%x', [SymName, SymDelta]);

      // Line lookup is clamped to [SymRVA, NextSymRVA) so we never attribute
      // this frame to a previous unit's last line (e.g. Generics.Defaults).
      if FindNearestLine(Offset, SymRVA, NextSymRVA, SourceFile, LineNum) then
        Result := Result + Format(' (%s:%d)', [SourceFile, LineNum]);
      Exit;
    end;
  end;

Fallback:
  // Fallback: module + offset
  {$IFDEF MSWINDOWS}
  Module := GetModuleFromAddress(Address);
  if Module <> 0 then
  begin
    Offset := NativeUInt(Address) - NativeUInt(Module);
    Result := Format('%s + $%x', [GetModuleNameFromHandle(Module), Offset]);
  end
  else
    Result := Format('$%p', [Address]);
  {$ELSE}
  Result := Format('$%p', [Address]);
  {$ENDIF}
end;

{ Stack Capture & Formatting }

function EffectiveMaxFrames: Integer; inline;
begin
  Result := TStackTrace.Options.MaxFrames;
  if Result < 1 then
    Result := 32;
  if Result > DBG_STACK_LENGTH then
    Result := DBG_STACK_LENGTH;
end;

{$IFDEF MSWINDOWS}
procedure GetCallStackOS(var Stack: TDbgInfoStack; FramesToSkip: Integer);
begin
  FillChar(Stack, SizeOf(Stack), 0);
  RtlCaptureStackBackTrace(FramesToSkip, ULONG(EffectiveMaxFrames), @Stack[0], nil);
end;
{$ENDIF}

function CallStackToStr(const Stack: TDbgInfoStack): string;
var
  SB: TStringBuilder;
  I, MaxFrames: Integer;
begin
  EnsureMapLoaded;
  MaxFrames := EffectiveMaxFrames;
  SB := TStringBuilder.Create(MaxFrames * 80);
  try
    for I := 0 to MaxFrames - 1 do
    begin
      if Stack[I] = nil then Break;
      if I > 0 then SB.AppendLine;
      SB.AppendFormat('  [%2d] %s', [I, ResolveAddr(Stack[I])]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TDbgOptions }

procedure TDbgOptions.InitDefaults;
begin
  WaitOnResolve := True;        // Por padrão espera para garantir stacktrace útil
  ResolveOnlyIfLoaded := False;
  AsyncLoad := True;
  MaxFrames := 32;              // Like FastMM StackDepth; hard cap DBG_STACK_LENGTH
end;

{ TStackTrace }

class procedure TStackTrace.EnsureInitialized;
begin
  if MapLoaded or MapLoadAttempted then
    Exit;

  if Options.AsyncLoad then
  begin
    MapLoadTokenSource := TCancellationTokenSource.Create;
    MapLoadTask := TAsyncTask.Run(TProc(
      procedure
      begin
        // Let LoadMapFile handle the parsing.
        LoadMapFile;
      end)).Start;
  end
  else
    LoadMapFile;
end;

class function TStackTrace.ResolveAddress(Address: Pointer): string;
begin
  Result := ResolveAddr(Address);
end;

class function TStackTrace.Capture(FramesToSkip: Integer): string;
{$IFDEF MSWINDOWS}
var
  Stack: TDbgInfoStack;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  GetCallStackOS(Stack, FramesToSkip);
  Result := CallStackToStr(Stack);
  {$ELSE}
  Result := '(stack trace not available)';
  {$ENDIF}
end;

{ Exception Hook Callbacks }

function GetExceptionStackInfo(P: PExceptionRecord): Pointer;
var
  Slot: Integer;
begin
  Slot := StackPoolIndex;
  StackPoolIndex := (StackPoolIndex + 1) mod STACK_POOL_SIZE;
  FillChar(StackPool[Slot], SizeOf(TDbgInfoStack), 0);
  {$IFDEF MSWINDOWS}
  try
    RtlCaptureStackBackTrace(1, ULONG(EffectiveMaxFrames), @StackPool[Slot][0], nil);
  except
  end;
  {$ENDIF}
  Result := @StackPool[Slot];
end;

function GetStackInfoStringProc(Info: Pointer): string;
{$IFDEF MSWINDOWS}
var
  Stack: TDbgInfoStack;
{$ENDIF}
begin
  if Info <> nil then
  begin
    try
      Result := CallStackToStr(PDbgInfoStack(Info)^);
    except
      Result := '(error formatting stack trace)';
    end;
    Exit;
  end;
  {$IFDEF MSWINDOWS}
  try
    GetCallStackOS(Stack, 3);
    Result := CallStackToStr(Stack);
  except
    Result := '(error capturing stack trace)';
  end;
  {$ELSE}
  Result := '';
  {$ENDIF}
end;

procedure CleanUpStackInfoProc(Info: Pointer);
begin
  // Pre-allocated ring buffer - nothing to free
end;

procedure InstallExceptionCallStack;
begin
  FillChar(StackPool, SizeOf(StackPool), 0);
  StackPoolIndex := 0;
  System.SysUtils.Exception.GetExceptionStackInfoProc := GetExceptionStackInfo;
  System.SysUtils.Exception.GetStackInfoStringProc := GetStackInfoStringProc;
  System.SysUtils.Exception.CleanUpStackInfoProc := CleanUpStackInfoProc;
end;

procedure UninstallExceptionCallStack;
begin
  System.SysUtils.Exception.GetExceptionStackInfoProc := nil;
  System.SysUtils.Exception.GetStackInfoStringProc := nil;
  System.SysUtils.Exception.CleanUpStackInfoProc := nil;
end;

initialization
  TStackTrace.Options.InitDefaults;
  MapReadyEvent := TEvent.Create(nil, True, False, '');
  InstallExceptionCallStack;
  {$IFDEF DEBUG}TStackTrace.EnsureInitialized;{$ENDIF}

finalization
  UninstallExceptionCallStack;
  MapLoadTokenSource.Free;
  MapReadyEvent.Free;

end.
