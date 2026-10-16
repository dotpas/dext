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

unit Dext.Core.DateUtils;

interface

uses
  System.SysUtils,
  System.DateUtils;

/// <summary>
///   Tries to parse an ISO 8601 date/time string. The standard forms are read
///   by TryParseJsonDateTime (a UTC offset or 'Z' is converted to local time);
///   other forms as before.
/// </summary>
function TryParseISODateTime(const Value: string; out DateTime: TDateTime): Boolean;

/// <summary>
///   Tries to parse a date/time string using common formats (ISO, dd/mm/yyyy, etc).
///   Uses the system's default FormatSettings.
/// </summary>
function TryParseCommonDate(const Value: string; out DateTime: TDateTime): Boolean; overload;

/// <summary>
///   Tries to parse a date/time string using the provided FormatSettings.
/// </summary>
function TryParseCommonDate(const Value: string; out DateTime: TDateTime; const AFormatSettings: TFormatSettings): Boolean; overload;

const
  /// <summary>The room FormatJsonDateTimeBuffer needs, in characters.</summary>
  JsonDateTimeMaxChars = 29;
  /// <summary>The characters FormatJsonDateBuffer writes: "yyyy-mm-dd".</summary>
  JsonDateChars = 10;
  /// <summary>The characters FormatJsonTimeBuffer writes: "hh:nn:ss.zzz".</summary>
  JsonTimeChars = 12;

/// <summary>
///   A TDateTime as JSON text, RFC 3339 / ISO 8601: the LOCAL time with its
///   offset from UTC, "2026-07-15T10:30:00.000+02:00" ("Z" when the offset is
///   zero). The digits are the wall clock, so a reader that ignores the offset
///   still shows 10:30; the offset gives the instant, also in the hour that
///   repeats when daylight saving time ends.
///   The offset is taken in whole minutes and kept per calendar year (per
///   thread): the system is asked about 25 times for a year, to find the
///   days the offset changes on, not for each value, however far apart the
///   values are. On the two days around a change, and before 1900, it is
///   asked for each value. A local time that does not exist (in the hour
///   skipped when daylight saving time starts) takes the offset the system
///   gives it.
/// </summary>
function FormatJsonDateTime(const AValue: TDateTime): string;

/// <summary>
///   FormatJsonDateTime written into ABuffer, which must hold at least
///   JsonDateTimeMaxChars characters. Returns the number of characters.
/// </summary>
function FormatJsonDateTimeBuffer(const AValue: TDateTime; ABuffer: PChar): Integer;

/// <summary>A TDate as JSON text: the calendar day, "2026-07-15".</summary>
function FormatJsonDate(const AValue: TDateTime): string;

/// <summary>
///   FormatJsonDate written into ABuffer, which must hold at least
///   JsonDateChars characters. Returns JsonDateChars.
/// </summary>
function FormatJsonDateBuffer(const AValue: TDateTime; ABuffer: PChar): Integer;

/// <summary>A TTime as JSON text: the wall clock, "10:30:00.000".</summary>
function FormatJsonTime(const AValue: TDateTime): string;

/// <summary>
///   FormatJsonTime written into ABuffer, which must hold at least
///   JsonTimeChars characters. Returns JsonTimeChars.
/// </summary>
function FormatJsonTimeBuffer(const AValue: TDateTime; ABuffer: PChar): Integer;

/// <summary>
///   The offset of a LOCAL date and time from UTC, in whole minutes (local
///   minus UTC: +120 in Rome in July). False if the system cannot tell.
/// </summary>
function TryGetLocalUtcOffset(const AValue: TDateTime; out AMinutes: Integer): Boolean;

/// <summary>
///   Reads a JSON date and time as LOCAL time. Accepted: "yyyy-mm-dd", and
///   "yyyy-mm-ddThh:nn[:ss[.fff]]" (also with a space instead of 'T') with an
///   optional zone: 'Z' or an offset (+hh:mm, +hhmm, +hh) is converted to the
///   local time of this machine; no zone is local time already. False for
///   anything else.
/// </summary>
function TryParseJsonDateTime(const AText: string; out AValue: TDateTime): Boolean;

/// <summary>
///   Reads a JSON time of day: "hh:nn[:ss[.fff]]" (a zone after it is
///   ignored: a time of day has none), or a whole date and time, of which the
///   local time of day is taken. False for anything else.
/// </summary>
function TryParseJsonTime(const AText: string; out AValue: TDateTime): Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.Classes;

const
  Digits: array[0..9] of Char = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9');
  YearSlots = 128;     // calendar years kept per thread (~8 KB)
  MaxYearChanges = 6;  // offset changes kept per year; with more, the system is asked for each value
  NoOffset = MaxInt;   // the system gave no answer

type
  // The offsets of one calendar year: the year is cut by the days on which
  // the offset changes, and between two of them the offset is one.
  TYearOffsets = record
    Year: Integer;  // 0: empty slot
    Count: Integer; // changes in the year; -1: ask the system for every value
    // The offset changes between the noon of Changes[I] and the noon of the
    // next day: on those two days the system is asked for each value.
    Changes: array[0..MaxYearChanges - 1] of Integer;
    // Minutes, local - UTC: Offsets[I] before Changes[I], Offsets[Count]
    // after the last change.
    Offsets: array[0..MaxYearChanges] of Integer;
  end;

threadvar
  GYearOffsets: array[0..YearSlots - 1] of TYearOffsets;
  GYearOffsetsBorn: Cardinal;

// Minutes from the start of Delphi's calendar, whole: EncodeDate is linear
// for whole days also before 1899-12-30, where a TDateTime is negative and
// the subtraction of two values is not the time between them.
function MinutesOf(Y, M, D, H, N: Word): Int64;
begin
  Result := Int64(Trunc(EncodeDate(Y, M, D))) * 1440 + H * 60 + N;
end;

// The offset of a local time, asked to the system.
function SystemOffset(const AValue: TDateTime; out AMinutes: Integer): Boolean;
{$IFDEF MSWINDOWS}
var
  Loc, Utc: TSystemTime;
begin
  DateTimeToSystemTime(AValue, Loc);
  Result := TzSpecificLocalTimeToSystemTime(nil, Loc, Utc);
  if Result then
    AMinutes := MinutesOf(Loc.wYear, Loc.wMonth, Loc.wDay, Loc.wHour, Loc.wMinute) -
      MinutesOf(Utc.wYear, Utc.wMonth, Utc.wDay, Utc.wHour, Utc.wMinute);
end;
{$ELSE}
begin
  // Not run by the author: TTimeZone, in whole minutes. A local time that
  // does not exist (the skipped hour) takes the offset after the change.
  try
    AMinutes := Round(TTimeZone.Local.GetUtcOffset(AValue).TotalMinutes);
  except
    AMinutes := Round(TTimeZone.Local.GetUtcOffset(AValue + 1 / 24).TotalMinutes);
  end;
  Result := True;
end;
{$ENDIF}

// The offset at noon of a day, asked to the system.
function NoonOffset(ADay: Integer): Integer;
begin
  if not SystemOffset(ADay + 0.5, Result) then
    Result := NoOffset;
end;

// The changes of offset between the noon of ADay1 and the noon of ADay2
// (offsets AOffset1 and AOffset2), in order, by bisection. Equal offsets at
// the two ends are taken as no change in between.
procedure FindChanges(var AYear: TYearOffsets; ADay1, ADay2, AOffset1, AOffset2: Integer);
var
  Middle, MiddleOffset: Integer;
begin
  if (AOffset1 = AOffset2) or (AYear.Count < 0) then
    Exit;
  if ADay2 - ADay1 = 1 then
  begin
    if AYear.Count = MaxYearChanges then
    begin
      AYear.Count := -1;
      Exit;
    end;
    AYear.Changes[AYear.Count] := ADay1;
    Inc(AYear.Count);
    AYear.Offsets[AYear.Count] := AOffset2;
    Exit;
  end;
  Middle := (ADay1 + ADay2) div 2;
  MiddleOffset := NoonOffset(Middle);
  FindChanges(AYear, ADay1, Middle, AOffset1, MiddleOffset);
  FindChanges(AYear, Middle, ADay2, MiddleOffset, AOffset2);
end;

// The offsets of a year: asked at noon of December 31 of the year before, of
// the first day of every month and of January 1 of the year after; where two
// of them differ, the day of the change is found by bisection. About 25
// questions to the system per year. Assumed: the offset does not change and
// change back within one month (Windows describes a year with at most two
// changes).
procedure BuildYear(var AYear: TYearOffsets; AYearNumber: Integer);
var
  Month, Day, NextDay, Offset, NextOffset: Integer;
begin
  AYear.Year := AYearNumber;
  AYear.Count := 0;
  Day := Trunc(EncodeDate(AYearNumber, 1, 1)) - 1;
  Offset := NoonOffset(Day);
  AYear.Offsets[0] := Offset;
  for Month := 2 to 13 do
  begin
    if Month <= 12 then
      NextDay := Trunc(EncodeDate(AYearNumber, Month, 1))
    else if AYearNumber < 9999 then
      NextDay := Trunc(EncodeDate(AYearNumber + 1, 1, 1))
    else
      NextDay := Trunc(EncodeDate(9999, 12, 31));
    NextOffset := NoonOffset(NextDay);
    FindChanges(AYear, Day, NextDay, Offset, NextOffset);
    Day := NextDay;
    Offset := NextOffset;
  end;
end;

// The offset of a calendar day from its year: False on the two days around a
// change, where the system is asked for each value.
function OffsetInYear(const AYear: TYearOffsets; ADay: Integer; out AMinutes: Integer): Boolean; inline;
var
  I: Integer;
begin
  Result := False;
  if AYear.Count < 0 then
    Exit;
  I := 0;
  while (I < AYear.Count) and (ADay > AYear.Changes[I] + 1) do
    Inc(I);
  if (I < AYear.Count) and (ADay >= AYear.Changes[I]) then
    Exit;
  AMinutes := AYear.Offsets[I];
  Result := AMinutes <> NoOffset;
end;

// The offset of a day of the year AYearNumber, from the per-thread cache.
// The cache is emptied every minute, so a change of the machine's time zone
// is seen within a minute.
function CachedOffset(AYearNumber, ADay: Integer; out AMinutes: Integer): Boolean;
var
  Slot: ^TYearOffsets;
  Ticks: Cardinal;
begin
  if AYearNumber < 1900 then
    Exit(False);
  Ticks := TThread.GetTickCount;
  if Cardinal(Ticks - GYearOffsetsBorn) > 60000 then
  begin
    FillChar(GYearOffsets, SizeOf(GYearOffsets), 0);
    GYearOffsetsBorn := Ticks;
  end;
  Slot := @GYearOffsets[AYearNumber and (YearSlots - 1)];
  if Slot.Year <> AYearNumber then
    BuildYear(Slot^, AYearNumber);
  Result := OffsetInYear(Slot^, ADay, AMinutes);
end;

// The offset of AValue, whose year is AYearNumber.
function OffsetOf(const AValue: TDateTime; AYearNumber: Integer; out AMinutes: Integer): Boolean;
begin
  Result := (AValue >= 1) and CachedOffset(AYearNumber, Trunc(AValue), AMinutes);
  if not Result then
    Result := SystemOffset(AValue, AMinutes);
end;

function TryGetLocalUtcOffset(const AValue: TDateTime; out AMinutes: Integer): Boolean;
begin
  Result := OffsetOf(AValue, YearOf(AValue), AMinutes);
end;

procedure Put2(P: PChar; V: Cardinal); inline;
begin
  P[0] := Digits[V div 10 mod 10];
  P[1] := Digits[V mod 10];
end;

// "yyyy-mm-dd" in P[0..9]; Y is the year
procedure PutDate(const AValue: TDateTime; P: PChar; out Y: Word);
var
  M, D: Word;
begin
  DecodeDate(AValue, Y, M, D);
  Put2(P, Y div 100);
  Put2(P + 2, Y mod 100);
  P[4] := '-';
  Put2(P + 5, M);
  P[7] := '-';
  Put2(P + 8, D);
end;

// "hh:nn:ss.zzz" in P[0..11]
procedure PutTime(const AValue: TDateTime; P: PChar);
var
  H, N, S, Ms: Word;
begin
  DecodeTime(AValue, H, N, S, Ms);
  Put2(P, H);
  P[2] := ':';
  Put2(P + 3, N);
  P[5] := ':';
  Put2(P + 6, S);
  P[8] := '.';
  P[9] := Digits[Ms div 100];
  Put2(P + 10, Ms mod 100);
end;

function FormatJsonDateTimeBuffer(const AValue: TDateTime; ABuffer: PChar): Integer;
var
  Offset: Integer;
  Year: Word;
begin
  PutDate(AValue, ABuffer, Year);
  ABuffer[10] := 'T';
  PutTime(AValue, ABuffer + 11);
  Result := 23;
  if not OffsetOf(AValue, Year, Offset) then
    Exit;
  if Offset = 0 then
  begin
    ABuffer[23] := 'Z';
    Exit(24);
  end;
  if Offset > 0 then
    ABuffer[23] := '+'
  else
    ABuffer[23] := '-';
  Offset := Abs(Offset);
  Put2(ABuffer + 24, Offset div 60);
  ABuffer[26] := ':';
  Put2(ABuffer + 27, Offset mod 60);
  Result := 29;
end;

function FormatJsonDateTime(const AValue: TDateTime): string;
var
  Buffer: array[0..JsonDateTimeMaxChars - 1] of Char;
begin
  SetString(Result, PChar(@Buffer[0]), FormatJsonDateTimeBuffer(AValue, @Buffer[0]));
end;

function FormatJsonDateBuffer(const AValue: TDateTime; ABuffer: PChar): Integer;
var
  Year: Word;
begin
  PutDate(AValue, ABuffer, Year);
  Result := JsonDateChars;
end;

function FormatJsonDate(const AValue: TDateTime): string;
begin
  SetLength(Result, JsonDateChars);
  FormatJsonDateBuffer(AValue, PChar(Result));
end;

function FormatJsonTimeBuffer(const AValue: TDateTime; ABuffer: PChar): Integer;
begin
  PutTime(AValue, ABuffer);
  Result := JsonTimeChars;
end;

function FormatJsonTime(const AValue: TDateTime): string;
begin
  SetLength(Result, JsonTimeChars);
  FormatJsonTimeBuffer(AValue, PChar(Result));
end;

function ReadDigits(const S: string; AStart, ACount: Integer; out AValue: Integer): Boolean;
var
  I: Integer;
begin
  AValue := 0;
  Result := AStart + ACount - 1 <= Length(S);
  if not Result then
    Exit;
  for I := AStart to AStart + ACount - 1 do
  begin
    if (S[I] < '0') or (S[I] > '9') then
      Exit(False);
    AValue := AValue * 10 + Ord(S[I]) - Ord('0');
  end;
end;

// "hh:nn[:ss[.fff]]" from position P; on return P is after it. The fraction
// keeps its first three digits (fewer are tenths or hundredths).
function ReadClock(const S: string; var P: Integer; out ATime: TDateTime): Boolean;
var
  H, N, Sec, Ms, Count: Integer;
begin
  Result := False;
  if not ReadDigits(S, P, 2, H) or (P + 2 > Length(S)) or (S[P + 2] <> ':') or
     not ReadDigits(S, P + 3, 2, N) then
    Exit;
  Inc(P, 5);
  Sec := 0;
  Ms := 0;
  if (P <= Length(S)) and (S[P] = ':') then
  begin
    if not ReadDigits(S, P + 1, 2, Sec) then
      Exit;
    Inc(P, 3);
    if (P <= Length(S)) and ((S[P] = '.') or (S[P] = ',')) then
    begin
      Inc(P);
      Count := 0;
      while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') do
      begin
        if Count < 3 then
        begin
          Ms := Ms * 10 + Ord(S[P]) - Ord('0');
          Inc(Count);
        end;
        Inc(P);
      end;
      if Count = 0 then
        Exit;
      while Count < 3 do
      begin
        Ms := Ms * 10;
        Inc(Count);
      end;
    end;
  end;
  Result := TryEncodeTime(H, N, Sec, Ms, ATime);
end;

// The zone from position P to the end: none, 'Z', +hh:mm, +hhmm, +hh.
// AHasZone False when there is none; AOffset in minutes, local - UTC.
function ReadZone(const S: string; P: Integer; out AHasZone: Boolean;
  out AOffset: Integer): Boolean;
var
  Hh, Mm: Integer;
  Sign: Char;
begin
  AHasZone := False;
  AOffset := 0;
  if P > Length(S) then
    Exit(True);
  AHasZone := True;
  if ((S[P] = 'Z') or (S[P] = 'z')) and (P = Length(S)) then
    Exit(True);
  Result := False;
  Sign := S[P];
  if ((Sign <> '+') and (Sign <> '-')) or not ReadDigits(S, P + 1, 2, Hh) then
    Exit;
  Mm := 0;
  if P + 2 = Length(S) then
    // +hh
  else if (S[P + 3] = ':') and (P + 5 = Length(S)) then
  begin
    if not ReadDigits(S, P + 4, 2, Mm) then
      Exit;
  end
  else if P + 4 = Length(S) then
  begin
    if not ReadDigits(S, P + 3, 2, Mm) then
      Exit;
  end
  else
    Exit;
  if (Hh > 23) or (Mm > 59) then
    Exit;
  AOffset := Hh * 60 + Mm;
  if Sign = '-' then
    AOffset := -AOffset;
  Result := True;
end;

// A date and time written with the offset AOffset (minutes, local - UTC), as
// the local time of this machine; AYearNumber is the year of the digits.
// The offset of the local time comes from the per-year cache, away from the
// days it changes: the offset at the digits, checked on the local day the
// value lands on. It is the same whether AOffset is the local one (a value
// written here) or another ('Z', a client elsewhere). Otherwise TTimeZone
// works it out, as before. Either way the offset is added to the instant in
// UTC with IncMinute, the arithmetic of TTimeZone.ToLocalTime (IncSecond):
// the same value, to the last bit.
function ZoneToLocal(const ADigits: TDateTime; AYearNumber, AOffset: Integer): TDateTime;
var
  Utc: TDateTime;
  Local, Landed: Integer;
begin
  Utc := ADigits - AOffset / MinsPerDay;
  if (ADigits >= 1) and CachedOffset(AYearNumber, Trunc(ADigits), Local) then
  begin
    Result := IncMinute(Utc, Local);
    // With the local offset the value lands on the day of the digits
    if Local = AOffset then
      Exit;
    if (Result >= 1) and CachedOffset(YearOf(Result), Trunc(Result), Landed) and (Landed = Local) then
      Exit;
  end;
  Result := TTimeZone.Local.ToLocalTime(Utc);
end;

function TryParseJsonDateTime(const AText: string; out AValue: TDateTime): Boolean;
var
  S: string;
  Y, M, D, P, Offset: Integer;
  Day, Clock: TDateTime;
  HasZone: Boolean;
begin
  Result := False;
  S := Trim(AText);
  if (Length(S) < 10) or (S[5] <> '-') or (S[8] <> '-') or
     not ReadDigits(S, 1, 4, Y) or not ReadDigits(S, 6, 2, M) or
     not ReadDigits(S, 9, 2, D) or not TryEncodeDate(Y, M, D, Day) then
    Exit;
  if Length(S) = 10 then
  begin
    AValue := Day;
    Exit(True);
  end;
  if (S[11] <> 'T') and (S[11] <> 't') and (S[11] <> ' ') then
    Exit;
  P := 12;
  if not ReadClock(S, P, Clock) or not ReadZone(S, P, HasZone, Offset) then
    Exit;
  AValue := Day + Clock;
  if HasZone then
    AValue := ZoneToLocal(AValue, Y, Offset);
  Result := True;
end;

function TryParseJsonTime(const AText: string; out AValue: TDateTime): Boolean;
var
  S: string;
  P: Integer;
begin
  S := Trim(AText);
  P := 1;
  if (Length(S) >= 5) and (S[3] = ':') then
  begin
    Result := ReadClock(S, P, AValue);
    // A zone after a time of day is ignored; anything else is not a time
    if Result and (P <= Length(S)) then
      Result := CharInSet(S[P], ['Z', 'z', '+', '-']);
    Exit;
  end;
  Result := TryParseJsonDateTime(S, AValue);
  if Result then
    AValue := Frac(AValue);
end;

var
  GlobalFormatSettings: TFormatSettings;

function TryParseISODateTime(const Value: string; out DateTime: TDateTime): Boolean;
var
  Year, Month, Day, Hour, Min, Sec, MSec: Word;
  Parts: TArray<string>;
  DatePart, TimePart: string;
begin
  // The standard forms, with the zone converted to local time
  if TryParseJsonDateTime(Value, DateTime) then
    Exit(True);

  Result := False;
  if Value = '' then
    Exit;

  try
    // Handle YYYY-MM-DD HH:NN:SS... formats
    if (Length(Value) >= 10) and (Value[5] = '-') and (Value[8] = '-') then
    begin
      Parts := Value.Split([' ', 'T']);
      DatePart := Parts[0];
      if Length(Parts) > 1 then 
        TimePart := Parts[1]
      else
        TimePart := '';

      Parts := DatePart.Split(['-']);
      if Length(Parts) = 3 then
      begin
        Year := StrToInt(Parts[0]);
        Month := StrToInt(Parts[1]);
        Day := StrToInt(Parts[2]);

        Hour := 0; Min := 0; Sec := 0; MSec := 0;
        
        if TimePart <> '' then
        begin
          Parts := TimePart.Split([':', '.']);
          if Length(Parts) >= 3 then
          begin
            Hour := StrToInt(Parts[0]);
            Min := StrToInt(Parts[1]);
            Sec := StrToInt(Parts[2]);
            if Length(Parts) > 3 then
              MSec := StrToIntDef(Copy(Parts[3], 1, 3), 0);
          end;
        end;

        DateTime := EncodeDateTime(Year, Month, Day, Hour, Min, Sec, MSec);
        Result := True;
        Exit;
      end;
    end;

    if Length(Value) = 10 then
    begin
      Parts := Value.Split(['-']);
      if Length(Parts) = 3 then
      begin
        Year := StrToInt(Parts[0]);
        Month := StrToInt(Parts[1]);
        Day := StrToInt(Parts[2]);
        DateTime := EncodeDate(Year, Month, Day);
        Result := True;
        Exit;
      end;
    end;

    if TryISO8601ToDate(Value, DateTime, False) then
      Result := True
    else
      Result := False;
  except
    Result := False;
  end;
end;

function TryParseCommonDate(const Value: string; out DateTime: TDateTime): Boolean;
begin
  Result := TryParseCommonDate(Value, DateTime, GlobalFormatSettings);
end;

function TryParseCommonDate(const Value: string; out DateTime: TDateTime; const AFormatSettings: TFormatSettings): Boolean;
var
  FormatSettings: TFormatSettings;
  Parts: TArray<string>;
  Year, Month, Day: Word;
begin
  if TryParseISODateTime(Value, DateTime) then
    Exit(True);

  FormatSettings := AFormatSettings;

  // Try System native format first (handles OS locales like German dd.mm.yyyy)
  if TryStrToDateTime(Value, DateTime, FormatSettings) then
    Exit(True);
  if TryStrToTime(Value, DateTime, FormatSettings) then
    Exit(True);
  if TryStrToDate(Value, DateTime, FormatSettings) then
    Exit(True);

  FormatSettings.DateSeparator := '/';
  FormatSettings.ShortDateFormat := 'dd/mm/yyyy';
  if TryStrToDateTime(Value, DateTime, FormatSettings) then
    Exit(True);

  FormatSettings.ShortDateFormat := 'mm/dd/yyyy';
  if TryStrToDateTime(Value, DateTime, FormatSettings) then
    Exit(True);

  FormatSettings.ShortDateFormat := 'yyyy/mm/dd';
  if TryStrToDateTime(Value, DateTime, FormatSettings) then
    Exit(True);

  Parts := Value.Split(['/', '-', '.']);
  if Length(Parts) = 3 then
  begin
    try
      Day := StrToInt(Parts[0]);
      Month := StrToInt(Parts[1]);
      Year := StrToInt(Parts[2]);
      if (Year > 1900) and (Year < 2100) and (Month >= 1) and (Month <= 12) and (Day >= 1) and (Day <= 31) then
      begin
        DateTime := EncodeDate(Year, Month, Day);
        Exit(True);
      end;

      Month := StrToInt(Parts[0]);
      Day := StrToInt(Parts[1]);
      Year := StrToInt(Parts[2]);
      if (Year > 1900) and (Year < 2100) and (Month >= 1) and (Month <= 12) and (Day >= 1) and (Day <= 31) then
      begin
        DateTime := EncodeDate(Year, Month, Day);
        Exit(True);
      end;
    except
    end;
  end;

  Result := False;
end;

initialization
  GlobalFormatSettings := TFormatSettings.Create;

end.
