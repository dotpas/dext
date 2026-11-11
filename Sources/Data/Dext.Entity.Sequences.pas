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
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2026-06-19                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.Sequences;

interface

uses
  System.Classes,
  System.Rtti,
  System.SyncObjs,
  System.SysUtils,
  System.Variants,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.Interfaces;

type
  /// <summary>
  ///   Tracks the low, high and current boundaries of a pre-allocated sequence range (HiLo).
  /// </summary>
  TSequenceRange = class
  public
    Low: Int64;
    High: Int64;
    Current: Int64;
    constructor Create(ALow, AHigh: Int64);
    function NextId(out AId: Int64): Boolean;
  end;

  TSequenceRangeRecord = record
    SequenceName: string;
    Range: TSequenceRange;
  end;

  /// <summary>
  ///   Thread-safe manager for DB sequence HiLo/Pooled allocation ranges.
  /// </summary>
  TSequenceManager = class
  private
    class var FInstance: TSequenceManager;
  private
    FCurrentRanges: TArray<TSequenceRangeRecord>;
    FLock: TCriticalSection;
    procedure EnsureSQLiteTable(const AConnection: IDbConnection);
    function FetchNextRangeFromDb(const ASeqName: string; AAllocSize: Integer; const AConnection: IDbConnection; const ADialect: ISQLDialect): TSequenceRange;
    function FindRangeIndex(const ASeqName: string): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>
    ///   Thread-safe entry point to generate a new sequential ID from a sequence.
    /// </summary>
    function GenerateId(const ASequenceName: string; AAllocationSize: Integer; const AConnection: IDbConnection; const ADialect: ISQLDialect): Int64;
    
    class property Instance: TSequenceManager read FInstance;
  end;

implementation

{ TSequenceRange }

constructor TSequenceRange.Create(ALow, AHigh: Int64);
begin
  inherited Create;
  Low := ALow;
  High := AHigh;
  Current := ALow;
end;

function TSequenceRange.NextId(out AId: Int64): Boolean;
begin
  if Current <= High then
  begin
    AId := Current;
    Inc(Current);
    Result := True;
  end
  else
    Result := False;
end;

{ TSequenceManager }

constructor TSequenceManager.Create;
begin
  inherited Create;
  FCurrentRanges := nil;
  FLock := TCriticalSection.Create;
end;

destructor TSequenceManager.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FCurrentRanges) do
    FCurrentRanges[i].Range.Free;
  FCurrentRanges := nil;
  FreeAndNil(FLock);
  inherited;
end;

function TSequenceManager.FindRangeIndex(const ASeqName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(FCurrentRanges) do
  begin
    if SameText(FCurrentRanges[i].SequenceName, ASeqName) then
    begin
      Result := i;
      Break;
    end;
  end;
end;

procedure TSequenceManager.EnsureSQLiteTable(const AConnection: IDbConnection);
var
  Cmd: IDbCommand;
begin
  // Emulate sequence table for SQLite. The table belongs to the connection
  // (a new in-memory database has none), so it is created on every fetch.
  Cmd := AConnection.CreateCommand(
    'CREATE TABLE IF NOT EXISTS dext_sequences (name VARCHAR(255) PRIMARY KEY, nextval BIGINT);'
  );
  try
    Cmd.ExecuteNonQuery;
  finally
    Cmd := nil;
  end;
end;

function TSequenceManager.FetchNextRangeFromDb(const ASeqName: string; AAllocSize: Integer;
  const AConnection: IDbConnection; const ADialect: ISQLDialect): TSequenceRange;
var
  Cmd: IDbCommand;
  Reader: IDbReader;
  NextVal: Int64;
  SQL: string;
  Val: TValue;
begin
  if ADialect.GetDialect = ddSQLite then
  begin
    EnsureSQLiteTable(AConnection);
    
    // Seed sequence if not present
    Cmd := AConnection.CreateCommand(
      'INSERT OR IGNORE INTO dext_sequences (name, nextval) VALUES (:name, 0);'
    );
    try
      Cmd.AddParam('name', ASeqName);
      Cmd.ExecuteNonQuery;
    finally
      Cmd := nil;
    end;

    // Increment sequence by allocation size
    Cmd := AConnection.CreateCommand(
      'UPDATE dext_sequences SET nextval = nextval + :allocSize WHERE name = :name;'
    );
    try
      Cmd.AddParam('allocSize', AAllocSize);
      Cmd.AddParam('name', ASeqName);
      Cmd.ExecuteNonQuery;
    finally
      Cmd := nil;
    end;
  end;

  SQL := ADialect.GetSequenceNextValSQL(ASeqName, AAllocSize);
  Cmd := AConnection.CreateCommand(SQL);
  try
    Reader := Cmd.ExecuteQuery;
    try
      if Reader.Next then
      begin
        Val := Reader.GetValue(0);
        NextVal := Val.AsInt64;
      end
      else
        raise Exception.CreateFmt('Failed to fetch next value for sequence %s', [ASeqName]);
    finally
      Reader.Close;
      Reader := nil;
    end;
  finally
    Cmd := nil;
  end;

  // Pooled-lo allocation:
  // NextVal is the new high-boundary returned by the sequence.
  // The range is [NextVal - AAllocSize + 1, NextVal]
  Result := TSequenceRange.Create(NextVal - AAllocSize + 1, NextVal);
end;

function TSequenceManager.GenerateId(const ASequenceName: string; AAllocationSize: Integer;
  const AConnection: IDbConnection; const ADialect: ISQLDialect): Int64;
var
  Range: TSequenceRange;
  OldRange: TSequenceRange;
  GotId: Boolean;
  Idx: Integer;
begin
  FLock.Acquire;
  try
    Idx := FindRangeIndex(ASequenceName);
    if Idx < 0 then
    begin
      Range := FetchNextRangeFromDb(ASequenceName, AAllocationSize, AConnection, ADialect);
      SetLength(FCurrentRanges, Length(FCurrentRanges) + 1);
      FCurrentRanges[High(FCurrentRanges)].SequenceName := ASequenceName;
      FCurrentRanges[High(FCurrentRanges)].Range := Range;
    end
    else
    begin
      Range := FCurrentRanges[Idx].Range;
    end;

    GotId := Range.NextId(Result);
    if not GotId then
    begin
      // Range exhausted, fetch next block
      OldRange := Range;
      Range := FetchNextRangeFromDb(ASequenceName, AAllocationSize, AConnection, ADialect);
      
      Idx := FindRangeIndex(ASequenceName);
      if Idx >= 0 then
        FCurrentRanges[Idx].Range := Range;
        
      OldRange.Free;
      if not Range.NextId(Result) then
        raise Exception.CreateFmt('Failed to generate next ID for sequence %s', [ASequenceName]);
    end;
  finally
    FLock.Release;
  end;
end;

initialization
  TSequenceManager.FInstance := TSequenceManager.Create;

finalization
  FreeAndNil(TSequenceManager.FInstance);

end.
