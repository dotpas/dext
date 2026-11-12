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

unit Dext.BackgroundJobs.Storage.Sqlite;

interface

uses
  System.Classes,
  System.SysUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DApt,
  Dext.BackgroundJobs.Intf;

type
  TSqliteJobStorage = class(TInterfacedObject, IJobStorageEx, IJobStorage)
  private
    FDbPath: string;
    FConnection: TFDConnection;
    FMutex: TObject;
    procedure EnsureSchema;
    function GetConnection: TFDConnection;
  public
    class constructor Create;
    constructor Create(const ADbPath: string);
    destructor Destroy; override;

    function Enqueue(const AJobType, AMethodName, AParamsJson: string; const AQueue: string = 'default'): string;
    function Schedule(const AJobType, AMethodName, AParamsJson: string; const AQueue: string; const AEnqueueAt: TDateTime): string;
    function GetNextJob(const AQueue: string; out AJob: TJobInfo): Boolean;
    procedure UpdateJobState(const AJobId: string; const AState: TJobState; const AErrorMessage: string = '');
    procedure RecordHeartbeat(const AJobId: string);
    procedure ScheduleRetry(const AJobId: string; const AEnqueueAt: TDateTime; const AErrorMessage: string);
    function RecoverOrphans(const AStaleBefore: TDateTime; AMaxAttempts: Integer): Integer;
  end;

implementation

uses
  Data.DB,
  FireDAC.Stan.Param,
  System.IOUtils,
  Dext.BackgroundJobs.Config;

{ TSqliteJobStorage }

constructor TSqliteJobStorage.Create(const ADbPath: string);
begin
  inherited Create;
  FDbPath := ADbPath;
  FMutex := TObject.Create;
  EnsureSchema;
end;

destructor TSqliteJobStorage.Destroy;
begin
  if Assigned(FConnection) then
  begin
    FConnection.Close;
    FConnection.Free;
  end;
  FMutex.Free;
  inherited;
end;

function TSqliteJobStorage.GetConnection: TFDConnection;
begin
  if not Assigned(FConnection) then
  begin
    FConnection := TFDConnection.Create(nil);
    FConnection.Params.DriverID := 'SQLite';
    FConnection.Params.Database := FDbPath;
    FConnection.Params.Add('LockingMode=Normal');
    FConnection.Params.Add('JournalMode=WAL');
    FConnection.Params.Add('Synchronous=Normal');
    FConnection.LoginPrompt := False;
    FConnection.Open;
  end;
  Result := FConnection;
end;

procedure TSqliteJobStorage.EnsureSchema;
var
  Conn: TFDConnection;
  SQL: string;
begin
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    SQL := 'CREATE TABLE IF NOT EXISTS DextJobs (' +
           '  Id VARCHAR(50) PRIMARY KEY, ' +
           '  JobType VARCHAR(255) NOT NULL, ' +
           '  MethodName VARCHAR(255) NOT NULL, ' +
           '  ParamsJson TEXT, ' +
           '  State INTEGER NOT NULL, ' +
           '  Queue VARCHAR(50) NOT NULL, ' +
           '  CreatedAt DATETIME NOT NULL, ' +
           '  EnqueueAt DATETIME NOT NULL, ' +
           '  AttemptCount INTEGER DEFAULT 0, ' +
           '  LastHeartbeat DATETIME, ' +
           '  ErrorLog TEXT' +
           ');';
    Conn.ExecSQL(SQL);
  finally
    TMonitor.Exit(FMutex);
  end;
end;

function TSqliteJobStorage.Enqueue(const AJobType, AMethodName, AParamsJson: string; const AQueue: string): string;
var
  Conn: TFDConnection;
  Query: TFDQuery;
begin
  Result := TGuid.NewGuid.ToString;
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Conn;
      Query.SQL.Text := 'INSERT INTO DextJobs (Id, JobType, MethodName, ParamsJson, State, Queue, CreatedAt, EnqueueAt, AttemptCount) ' +
                        'VALUES (:Id, :JobType, :MethodName, :ParamsJson, :State, :Queue, :CreatedAt, :EnqueueAt, 0)';
      Query.ParamByName('Id').AsString := Result;
      Query.ParamByName('JobType').AsString := AJobType;
      Query.ParamByName('MethodName').AsString := AMethodName;
      Query.ParamByName('ParamsJson').AsString := AParamsJson;
      Query.ParamByName('State').AsInteger := Ord(jsEnqueued);
      Query.ParamByName('Queue').AsString := AQueue;
      Query.ParamByName('CreatedAt').AsDateTime := Now;
      Query.ParamByName('EnqueueAt').AsDateTime := Now;
      Query.ExecSQL;
    finally
      Query.Free;
    end;
  finally
    TMonitor.Exit(FMutex);
  end;
end;

function TSqliteJobStorage.Schedule(const AJobType, AMethodName, AParamsJson: string; const AQueue: string; const AEnqueueAt: TDateTime): string;
var
  Conn: TFDConnection;
  Query: TFDQuery;
begin
  Result := TGuid.NewGuid.ToString;
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Conn;
      Query.SQL.Text := 'INSERT INTO DextJobs (Id, JobType, MethodName, ParamsJson, State, Queue, CreatedAt, EnqueueAt, AttemptCount) ' +
                        'VALUES (:Id, :JobType, :MethodName, :ParamsJson, :State, :Queue, :CreatedAt, :EnqueueAt, 0)';
      Query.ParamByName('Id').AsString := Result;
      Query.ParamByName('JobType').AsString := AJobType;
      Query.ParamByName('MethodName').AsString := AMethodName;
      Query.ParamByName('ParamsJson').AsString := AParamsJson;
      Query.ParamByName('State').AsInteger := Ord(jsEnqueued);
      Query.ParamByName('Queue').AsString := AQueue;
      Query.ParamByName('CreatedAt').AsDateTime := Now;
      Query.ParamByName('EnqueueAt').AsDateTime := AEnqueueAt;
      Query.ExecSQL;
    finally
      Query.Free;
    end;
  finally
    TMonitor.Exit(FMutex);
  end;
end;

function TSqliteJobStorage.GetNextJob(const AQueue: string; out AJob: TJobInfo): Boolean;
var
  Conn: TFDConnection;
  Query: TFDQuery;
  LNow: TDateTime;
begin
  Result := False;
  AJob := Default(TJobInfo);
  LNow := Now;
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    Conn.StartTransaction;
    try
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Conn;
        // Simple queue polling for SQLite
        Query.SQL.Text := 'SELECT Id, JobType, MethodName, ParamsJson, State, Queue, CreatedAt, EnqueueAt, AttemptCount, LastHeartbeat, ErrorLog ' +
                          'FROM DextJobs ' +
                          'WHERE Queue = :Queue AND State = :State AND EnqueueAt <= :EnqueueAt ' +
                          'ORDER BY EnqueueAt ASC LIMIT 1';
        Query.ParamByName('Queue').AsString := AQueue;
        Query.ParamByName('State').AsInteger := Ord(jsEnqueued);
        Query.ParamByName('EnqueueAt').AsDateTime := LNow + (1.0 / 86400.0);
        Query.Open;
        
        if not Query.IsEmpty then
        begin
          AJob.Id := Query.FieldByName('Id').AsString;
          AJob.JobType := Query.FieldByName('JobType').AsString;
          AJob.MethodName := Query.FieldByName('MethodName').AsString;
          AJob.ParamsJson := Query.FieldByName('ParamsJson').AsString;
          AJob.State := jsProcessing;
          AJob.Queue := Query.FieldByName('Queue').AsString;
          AJob.CreatedAt := Query.FieldByName('CreatedAt').AsDateTime;
          AJob.EnqueueAt := Query.FieldByName('EnqueueAt').AsDateTime;
          AJob.AttemptCount := Query.FieldByName('AttemptCount').AsInteger;
          AJob.LastHeartbeat := LNow;
          AJob.ErrorLog := Query.FieldByName('ErrorLog').AsString;

          // Lock the job by moving it to processing state
          var UpdateQuery: TFDQuery;
          UpdateQuery := TFDQuery.Create(nil);
          try
            UpdateQuery.Connection := Conn;
            UpdateQuery.SQL.Text := 'UPDATE DextJobs SET State = :State, LastHeartbeat = :Heartbeat WHERE Id = :Id';
            UpdateQuery.ParamByName('State').AsInteger := Ord(jsProcessing);
            UpdateQuery.ParamByName('Heartbeat').AsDateTime := LNow;
            UpdateQuery.ParamByName('Id').AsString := AJob.Id;
            UpdateQuery.ExecSQL;
          finally
            UpdateQuery.Free;
          end;
          Result := True;
        end;
      finally
        Query.Free;
      end;
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end;
  finally
    TMonitor.Exit(FMutex);
  end;
end;

procedure TSqliteJobStorage.UpdateJobState(const AJobId: string; const AState: TJobState; const AErrorMessage: string);
var
  Conn: TFDConnection;
  SQL: string;
begin
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    if AState = jsFailed then
    begin
      SQL := Format('UPDATE DextJobs SET State = %d, AttemptCount = AttemptCount + 1, ErrorLog = %s WHERE Id = %s',
        [Ord(AState), QuotedStr(AErrorMessage), QuotedStr(AJobId)]);
    end
    else
    begin
      SQL := Format('UPDATE DextJobs SET State = %d WHERE Id = %s', [Ord(AState), QuotedStr(AJobId)]);
    end;
    Conn.ExecSQL(SQL);
  finally
    TMonitor.Exit(FMutex);
  end;
end;

procedure TSqliteJobStorage.RecordHeartbeat(const AJobId: string);
var
  Conn: TFDConnection;
  Query: TFDQuery;
begin
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Conn;
      Query.SQL.Text := 'UPDATE DextJobs SET LastHeartbeat = :Heartbeat WHERE Id = :Id';
      Query.ParamByName('Heartbeat').AsDateTime := Now;
      Query.ParamByName('Id').AsString := AJobId;
      Query.ExecSQL;
    finally
      Query.Free;
    end;
  finally
    TMonitor.Exit(FMutex);
  end;
end;

procedure TSqliteJobStorage.ScheduleRetry(const AJobId: string;
  const AEnqueueAt: TDateTime; const AErrorMessage: string);
var
  Query: TFDQuery;
begin
  TMonitor.Enter(FMutex);
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := GetConnection;
      Query.SQL.Text := 'UPDATE DextJobs SET State = :State, EnqueueAt = :EnqueueAt, ' +
                        'AttemptCount = AttemptCount + 1, ErrorLog = :ErrorLog WHERE Id = :Id';
      Query.ParamByName('State').AsInteger := Ord(jsEnqueued);
      Query.ParamByName('EnqueueAt').AsDateTime := AEnqueueAt;
      Query.ParamByName('ErrorLog').AsString := AErrorMessage;
      Query.ParamByName('Id').AsString := AJobId;
      Query.ExecSQL;
    finally
      Query.Free;
    end;
  finally
    TMonitor.Exit(FMutex);
  end;
end;

function TSqliteJobStorage.RecoverOrphans(const AStaleBefore: TDateTime;
  AMaxAttempts: Integer): Integer;
var
  Conn: TFDConnection;
  Query: TFDQuery;
begin
  Result := 0;
  TMonitor.Enter(FMutex);
  try
    Conn := GetConnection;
    Conn.StartTransaction;
    try
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Conn;
        // Exhausted jobs become Failed ...
        Query.SQL.Text := 'UPDATE DextJobs SET State = :Failed, AttemptCount = AttemptCount + 1, ' +
                          'ErrorLog = ''Worker lost: no heartbeat.'' ' +
                          'WHERE State = :Processing AND LastHeartbeat < :Stale AND AttemptCount + 1 >= :Max';
        Query.ParamByName('Failed').AsInteger := Ord(jsFailed);
        Query.ParamByName('Processing').AsInteger := Ord(jsProcessing);
        Query.ParamByName('Stale').AsDateTime := AStaleBefore;
        Query.ParamByName('Max').AsInteger := AMaxAttempts;
        Query.ExecSQL;
        Inc(Result, Query.RowsAffected);

        // ... the others go back to the queue.
        Query.SQL.Text := 'UPDATE DextJobs SET State = :Enqueued, EnqueueAt = :Now, ' +
                          'AttemptCount = AttemptCount + 1, ErrorLog = ''Worker lost: no heartbeat.'' ' +
                          'WHERE State = :Processing AND LastHeartbeat < :Stale';
        Query.ParamByName('Enqueued').AsInteger := Ord(jsEnqueued);
        Query.ParamByName('Now').AsDateTime := Now;
        Query.ParamByName('Processing').AsInteger := Ord(jsProcessing);
        Query.ParamByName('Stale').AsDateTime := AStaleBefore;
        Query.ExecSQL;
        Inc(Result, Query.RowsAffected);
      finally
        Query.Free;
      end;
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end;
  finally
    TMonitor.Exit(FMutex);
  end;
end;

class constructor TSqliteJobStorage.Create;
begin
  TJobStorageRegistry.RegisterProvider('SQLite',
    function(const AConnectionString: string): TObject
    begin
      Result := TSqliteJobStorage.Create(AConnectionString);
    end);
end;

end.
