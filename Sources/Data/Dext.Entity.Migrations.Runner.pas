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
{  Created: 2025-12-08                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.Migrations.Runner;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Collections,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Migrations,
  Dext.Entity.Migrations.Builder,
  Dext.Entity.Migrations.Operations,
  Dext.Logging,
  Dext.Entity.Drivers.Interfaces;

type
  TMigrator = class
  private
    FContext: IDbContext;
    FLogger: ILogger;
    procedure EnsureHistoryTable;
    procedure ApplyMigration(AMigration: IMigration);
    procedure DownMigration(AMigration: IMigration);
    procedure LogInfo(const AMsg: string);
    procedure BeginDdlTransaction;
    procedure CommitDdlTransaction;
    procedure RollbackDdlTransaction;
  public
    constructor Create(AContext: IDbContext; ALogger: ILogger = nil);

    /// <summary>
    ///   True where a transaction can undo DDL. MySQL and MariaDB commit on
    ///   every DDL statement, so a transaction around a migration ends under
    ///   it and its Commit fails: there the statements run one by one.
    /// </summary>
    class function RunsDdlInTransaction(const ADialect: ISQLDialect): Boolean; static;
    function GetAppliedMigrations: IList<string>;
    procedure Migrate;
    procedure Rollback(const ATargetId: string = '');

    /// <summary>
    ///   Checks if the database schema is compatible with the expected version.
    ///   Returns True if the last applied migration is equal to or greater than the ExpectedVersion.
    ///   If ExpectedVersion is empty, returns True (no check).
    /// </summary>
    function ValidateSchemaCompatibility(const ExpectedVersion: string): Boolean;
  end;

implementation

uses
  Dext.Utils;

{ TMigrator }

class function TMigrator.RunsDdlInTransaction(const ADialect: ISQLDialect): Boolean;
begin
  Result := not (ADialect.GetDialect in [ddMySQL, ddMariaDB]);
end;

procedure TMigrator.BeginDdlTransaction;
begin
  if RunsDdlInTransaction(FContext.Dialect) then
    FContext.BeginTransaction;
end;

procedure TMigrator.CommitDdlTransaction;
begin
  if RunsDdlInTransaction(FContext.Dialect) then
    FContext.Commit;
end;

procedure TMigrator.RollbackDdlTransaction;
begin
  if RunsDdlInTransaction(FContext.Dialect) then
    FContext.Rollback;
end;

constructor TMigrator.Create(AContext: IDbContext; ALogger: ILogger);
begin
  FContext := AContext;
  FLogger := ALogger;
end;

procedure TMigrator.LogInfo(const AMsg: string);
begin
  if FLogger <> nil then
    FLogger.LogInformation(AMsg)
  else
    SafeWriteLn(AMsg);
end;


procedure TMigrator.EnsureHistoryTable;
var
  Builder: TSchemaBuilder;
  Op: TMigrationOperation;
  SQL: string;
  CmdIntf: IInterface;
  Cmd: IDbCommand;
begin
  if FContext.Connection.TableExists('__DextMigrations') then
    Exit;

  Builder := TSchemaBuilder.Create;
  try
    Builder.CreateTable('__DextMigrations', procedure(T: TTableBuilder)
    begin
      T.Column('Id', 'VARCHAR', 255).PrimaryKey;
      T.Column('AppliedAt', 'TIMESTAMP').Default('CURRENT_TIMESTAMP');
    end);

    // Generate SQL
    Op := Builder.Operations[0];
    SQL := FContext.Dialect.GenerateMigration(Op);

    // Execute
    CmdIntf := FContext.Connection.CreateCommand(SQL);
    Cmd := CmdIntf as IDbCommand;
    Cmd.ExecuteNonQuery;
  finally
    Builder.Free;
  end;
end;

function TMigrator.GetAppliedMigrations: IList<string>;
var
  CmdIntf: IInterface;
  Cmd: IDbCommand;
  Reader: IDbReader;
begin
  Result := TCollections.CreateList<string>;
  try
    EnsureHistoryTable;

    CmdIntf := FContext.Connection.CreateCommand('SELECT ' + FContext.Dialect.QuoteIdentifier('Id') +
                                               ' FROM ' + FContext.Dialect.QuoteIdentifier('__DextMigrations'));
    Cmd := CmdIntf as IDbCommand;
    Reader := Cmd.ExecuteQuery;
    try
      while Reader.Next do
      begin
        Result.Add(Reader.GetValue(0).AsString);
      end;
    finally
      Reader.Close;
    end;
  except
    // Result is ARC
    raise;
  end;
end;

procedure TMigrator.ApplyMigration(AMigration: IMigration);
var
  Builder: TSchemaBuilder;
  Op: TMigrationOperation;
  SQL: string;
  CmdIntf: IInterface;
  Cmd: IDbCommand;
begin
  LogInfo('   → Applying migration: ' + AMigration.GetId);

  BeginDdlTransaction;
  try
    Builder := TSchemaBuilder.Create;
    try
      AMigration.Up(Builder);

      for Op in Builder.Operations do
      begin
        SQL := FContext.Dialect.GenerateMigration(Op);
        if SQL <> '' then
        begin
          CmdIntf := FContext.Connection.CreateCommand(SQL);
          Cmd := CmdIntf as IDbCommand;
          Cmd.ExecuteNonQuery;
        end;
      end;

      // Record in History
      SQL := 'INSERT INTO ' + FContext.Dialect.QuoteIdentifier('__DextMigrations') +
             ' (' + FContext.Dialect.QuoteIdentifier('Id') + ', ' + FContext.Dialect.QuoteIdentifier('AppliedAt') + ') VALUES (' +
             FContext.Dialect.GetParamPrefix + 'Id, ' +
             FContext.Dialect.GetParamPrefix + 'AppliedAt)';

      CmdIntf := FContext.Connection.CreateCommand(SQL);
      Cmd := CmdIntf as IDbCommand;
      Cmd.AddParam('Id', AMigration.GetId);
      Cmd.AddParam('AppliedAt', Now);
      Cmd.ExecuteNonQuery;

    finally
      Builder.Free;
    end;

    CommitDdlTransaction;
  except
    RollbackDdlTransaction;
    raise;
  end;
end;

procedure TMigrator.DownMigration(AMigration: IMigration);
var
  Builder: TSchemaBuilder;
  Op: TMigrationOperation;
  SQL: string;
  CmdIntf: IInterface;
  Cmd: IDbCommand;
begin
  LogInfo('   ↩ Rolling back migration: ' + AMigration.GetId);

  BeginDdlTransaction;
  try
    Builder := TSchemaBuilder.Create;
    try
      AMigration.Down(Builder);

      for Op in Builder.Operations do
      begin
        SQL := FContext.Dialect.GenerateMigration(Op);
        if SQL <> '' then
        begin
          CmdIntf := FContext.Connection.CreateCommand(SQL);
          Cmd := CmdIntf as IDbCommand;
          Cmd.ExecuteNonQuery;
        end;
      end;

      // Remove from History
      SQL := 'DELETE FROM ' + FContext.Dialect.QuoteIdentifier('__DextMigrations') +
             ' WHERE ' + FContext.Dialect.QuoteIdentifier('Id') + ' = ' +
             FContext.Dialect.GetParamPrefix + 'Id';

      CmdIntf := FContext.Connection.CreateCommand(SQL);
      Cmd := CmdIntf as IDbCommand;
      Cmd.AddParam('Id', AMigration.GetId);
      Cmd.ExecuteNonQuery;

    finally
      Builder.Free;
    end;

    CommitDdlTransaction;
  except
    RollbackDdlTransaction;
    raise;
  end;
end;

procedure TMigrator.Rollback(const ATargetId: string);
var
  Applied: IList<string>;
  Available: TArray<IMigration>;
  Migration: IMigration;
  i: Integer;
begin
  Applied := GetAppliedMigrations;
  try
    Available := TMigrationRegistry.Instance.GetMigrations;

    // Reverse order for rollback
    for i := High(Available) downto Low(Available) do
    begin
      Migration := Available[i];
      if Applied.Contains(Migration.GetId) then
      begin
        if (ATargetId <> '') and (CompareText(Migration.GetId, ATargetId) < 0) then
          Break;

        DownMigration(Migration);

        // If target ID not specified, rollback only one
        if ATargetId = '' then
          Exit;
      end;
    end;
  finally
    // Applied is ARC
  end;
end;

procedure TMigrator.Migrate;
var
  Applied: IList<string>;
  Available: TArray<IMigration>;
  Migration: IMigration;
begin
  Applied := GetAppliedMigrations;
  try
    Available := TMigrationRegistry.Instance.GetMigrations;

    if Length(Available) = 0 then
      LogInfo('   ℹ No migrations found in registry.')
    else
      LogInfo('   🔍 Found ' + Length(Available).ToString + ' migrations in registry.');

    for Migration in Available do
    begin
      if not Applied.Contains(Migration.GetId) then
      begin
        ApplyMigration(Migration);
      end;
    end;
  finally
    // Applied is ARC
  end;
end;

function TMigrator.ValidateSchemaCompatibility(const ExpectedVersion: string): Boolean;
var
  Applied: IList<string>;
  LastApplied: string;
begin
  if ExpectedVersion.IsEmpty then
    Exit(True);

  Applied := GetAppliedMigrations;
  try
    if Applied.Count = 0 then
      Exit(False); // No migrations applied, definitely not compatible if we expect something

    Applied.Sort; // Sort lexicographically (timestamps work well)
    LastApplied := Applied.Last;

    // Check if LastApplied >= ExpectedVersion
    Result := CompareText(LastApplied, ExpectedVersion) >= 0;
  finally
    // Applied is ARC
  end;
end;

end.

