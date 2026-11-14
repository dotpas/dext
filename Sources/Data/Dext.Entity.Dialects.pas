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
unit Dext.Entity.Dialects;

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Collections,
  Data.DB,
  Data.FmtBcd,
  Dext.Types.UUID,
  Dext.Entity.Attributes,
  System.Variants,
  Dext.Entity.Migrations.Operations,
  Dext.Specifications.Interfaces;

type
  /// <summary>
  ///   Database dialect enumeration for type converters.
  /// </summary>
  TDatabaseDialect = (
    ddUnknown,
    ddSQLite,
    ddPostgreSQL,
    ddMySQL,
    ddMariaDB,
    ddSQLServer,
    ddFirebird,
    ddInterbase,
    ddOracle
  );

  TReturningPosition = (rpAtEnd, rpBeforeValues);
  {$M+}
  /// <summary>
  ///   Abstracts database-specific SQL syntax differences.
  /// </summary>
  /// <summary>
  ///   Abstraction of SQL syntax differences across different databases.
  /// </summary>
  ISQLDialect = interface
    ['{20000000-0000-0000-0000-000000000001}']
    function QuoteIdentifier(const AName: string): string;
    function GetParamPrefix: string;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
    function BooleanToSQL(AValue: Boolean): string;
    function VariantToSQL(const AValue: Variant): string;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string;
    function GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string;
    function GetCascadeActionSQL(AAction: TCascadeAction): string;
    function GetLastInsertIdSQL: string;
    function GetCreateTableSQL(const ATableName, ABody: string): string;
    /// <summary>
    ///   INSERT for a row that has no column to write (an entity whose only
    ///   mapped column is the auto-increment key). The table arrives quoted.
    /// </summary>
    function GetInsertDefaultValuesSQL(const ATableName: string): string;
    
    // New methods for RETURNING clause support
    function SupportsInsertReturning: Boolean;
    function GetReturningSQL(const AColumnName: string): string;
    function GetReturningPosition: TReturningPosition;

    // Paging support
    function RequiresOrderByForPaging: Boolean;
    
    // Migration Support
    function GenerateMigration(AOperation: TMigrationOperation): string;
    function GenerateColumnDefinition(AColumn: TColumnDefinition): string;

    // Multi-Tenancy Support
    function GetSetSchemaSQL(const ASchemaName: string): string;
    function GetCreateSchemaSQL(const ASchemaName: string): string;
    function UseSchemaPrefix: Boolean;

    // Explicit Dialect Identification
    function GetDialect: TDatabaseDialect;

    // JSON Support
    function GetJsonValueSQL(const AColumn, APath: string): string;

    // Stored Procedure Support
    function GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string;

    // Locking Support
    function GetLockingSQL(ALockMode: TLockMode): string;

    // Seed Data Support
    function GenerateSeedData(AOp: TSeedDataOperation): string;

    // Sequence Support (S46)
    /// <summary>
    ///   Generates the SQL statement to fetch the next value from a database sequence.
    /// </summary>
    /// <param name="ASequenceName">The name of the sequence in the database.</param>
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string;
    function GetSequenceExistsSQL(const ASequenceName: string): string;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string;
  end;
  {$M-}

  /// <summary>
  ///   Factory for creating ISQLDialect instances from TDatabaseDialect enum.
  /// </summary>
  /// <summary>
  ///   Factory for creating and automatically detecting SQL dialects based on the connection driver.
  /// </summary>
  TDialectFactory = class
  public
    class function CreateDialect(const ADialect: TDatabaseDialect): ISQLDialect;
    class function DetectDialect(const ADriverName: string): TDatabaseDialect;
  end;

  /// <summary>
  ///   Base class for dialects.
  /// </summary>
  TBaseDialect = class(TInterfacedObject, ISQLDialect)
  protected
    function GenerateCreateTable(AOp: TCreateTableOperation): string; virtual;
    function GenerateDropTable(AOp: TDropTableOperation): string; virtual;
    function GenerateAddColumn(AOp: TAddColumnOperation): string; virtual;
    function GenerateDropColumn(AOp: TDropColumnOperation): string; virtual;
    function GenerateAlterColumn(AOp: TAlterColumnOperation): string; virtual;
    function GenerateAddForeignKey(AOp: TAddForeignKeyOperation): string; virtual;
    function GenerateDropForeignKey(AOp: TDropForeignKeyOperation): string; virtual;
    function GenerateCreateIndex(AOp: TCreateIndexOperation): string; virtual;
    function GenerateDropIndex(AOp: TDropIndexOperation): string; virtual;
    function GenerateRenameTable(AOp: TRenameTableOperation): string; virtual;
    function GenerateRenameColumn(AOp: TRenameColumnOperation): string; virtual;
    function GenerateSeedData(AOp: TSeedDataOperation): string; virtual;
    function GenerateDeleteData(AOp: TDeleteDataOperation): string; virtual;
  public
    function GetSetSchemaSQL(const ASchemaName: string): string; virtual;
    function GetCreateSchemaSQL(const ASchemaName: string): string; virtual;
    function UseSchemaPrefix: Boolean; virtual;
    function QuoteIdentifier(const AName: string): string; virtual;
    function GetParamPrefix: string; virtual;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; virtual; abstract;
    function BooleanToSQL(AValue: Boolean): string; virtual;
    function VariantToSQL(const AValue: Variant): string; virtual;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; virtual; abstract;
    function GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; virtual;
    function GetCascadeActionSQL(AAction: TCascadeAction): string; virtual;
    function GetLastInsertIdSQL: string; virtual; abstract;
    function GetCreateTableSQL(const ATableName, ABody: string): string; virtual;
    function GetInsertDefaultValuesSQL(const ATableName: string): string; virtual;
    
    function SupportsInsertReturning: Boolean; virtual;
    function GetReturningSQL(const AColumnName: string): string; virtual;
    function GetReturningPosition: TReturningPosition; virtual;

    function RequiresOrderByForPaging: Boolean; virtual;
    
    // Migration Support
    function GenerateMigration(AOperation: TMigrationOperation): string; virtual;
    
    function GenerateColumnDefinition(AColumn: TColumnDefinition): string; virtual;
    function GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string; virtual;

    function GetLockingSQL(ALockMode: TLockMode): string; virtual;

    function GetDialect: TDatabaseDialect; virtual;
    function GetJsonValueSQL(const AColumn, APath: string): string; virtual;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; virtual;
    function GetSequenceExistsSQL(const ASequenceName: string): string; virtual;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; virtual;
  end;

  /// <summary>
  ///   SQLite Dialect implementation.
  /// </summary>
  /// <summary>
  ///   SQL dialect implementation for SQLite.
  /// </summary>
  TSQLiteDialect = class(TBaseDialect)
  public
    function QuoteIdentifier(const AName: string): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function BooleanToSQL(AValue: Boolean): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetLastInsertIdSQL: string; override;
    function GetCreateTableSQL(const ATableName, ABody: string): string; override;
    function GetDialect: TDatabaseDialect; override;
    function GetJsonValueSQL(const AColumn, APath: string): string; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetLockingSQL(ALockMode: TLockMode): string; override;
  end;

  /// <summary>
  ///   PostgreSQL Dialect implementation.
  /// </summary>
  /// <summary>
  ///   SQL dialect implementation for PostgreSQL, with support for JSONB and native UUID.
  /// </summary>
  TPostgreSQLDialect = class(TBaseDialect)
  public
    function QuoteIdentifier(const AName: string): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function BooleanToSQL(AValue: Boolean): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetLastInsertIdSQL: string; override;
    function GetCreateTableSQL(const ATableName, ABody: string): string; override;
    
    function SupportsInsertReturning: Boolean; override;
    function GetReturningSQL(const AColumnName: string): string; override;
    function GetSetSchemaSQL(const ASchemaName: string): string; override;
    function GetCreateSchemaSQL(const ASchemaName: string): string; override;
    function GetDialect: TDatabaseDialect; override;
    function GetJsonValueSQL(const AColumn, APath: string): string; override;
    function GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string; override;
    function GetLockingSQL(ALockMode: TLockMode): string; override;
    function UseSchemaPrefix: Boolean; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetSequenceExistsSQL(const ASequenceName: string): string; override;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
  end;

  /// <summary>
  ///   Firebird 3.0+ Dialect implementation.
  /// </summary>
  TFirebirdDialect = class(TBaseDialect)
  public
    function QuoteIdentifier(const AName: string): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function BooleanToSQL(AValue: Boolean): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetLastInsertIdSQL: string; override;
    function GetCreateTableSQL(const ATableName, ABody: string): string; override;
    
    function SupportsInsertReturning: Boolean; override;
    function GetReturningSQL(const AColumnName: string): string; override;
    function GetDialect: TDatabaseDialect; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetSequenceExistsSQL(const ASequenceName: string): string; override;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetLockingSQL(ALockMode: TLockMode): string; override;
    function GenerateRenameColumn(AOp: TRenameColumnOperation): string; override;
    function GenerateRenameTable(AOp: TRenameTableOperation): string; override;
    function GenerateDropColumn(AOp: TDropColumnOperation): string; override;
    function GenerateAlterColumn(AOp: TAlterColumnOperation): string; override;
  end;

  /// <summary>
  ///   SQL Server (2012+) Dialect implementation.
  /// </summary>
  TSQLServerDialect = class(TBaseDialect)
  public
    function QuoteIdentifier(const AName: string): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function BooleanToSQL(AValue: Boolean): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetLastInsertIdSQL: string; override;
    function GetCreateTableSQL(const ATableName, ABody: string): string; override;
    
    function SupportsInsertReturning: Boolean; override;
    function GetReturningSQL(const AColumnName: string): string; override;
    function GetReturningPosition: TReturningPosition; override;
    function RequiresOrderByForPaging: Boolean; override;
    function UseSchemaPrefix: Boolean; override;
    function GetCreateSchemaSQL(const ASchemaName: string): string; override;
    function GetSetSchemaSQL(const ASchemaName: string): string; override;
    function GetDialect: TDatabaseDialect; override;
    function GetJsonValueSQL(const AColumn, APath: string): string; override;
    function GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string; override;
    function GetLockingSQL(ALockMode: TLockMode): string; override;
    function GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetSequenceExistsSQL(const ASequenceName: string): string; override;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GenerateDropIndex(AOp: TDropIndexOperation): string; override;
    function GenerateRenameTable(AOp: TRenameTableOperation): string; override;
    function GenerateRenameColumn(AOp: TRenameColumnOperation): string; override;
  end;

  /// <summary>
  ///   MySQL / MariaDB Dialect implementation.
  /// </summary>
  TMySQLDialect = class(TBaseDialect)
  public
    function QuoteIdentifier(const AName: string): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function BooleanToSQL(AValue: Boolean): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetLastInsertIdSQL: string; override;
    function GetCreateTableSQL(const ATableName, ABody: string): string; override;
    function GetInsertDefaultValuesSQL(const ATableName: string): string; override;
    
    
    function GenerateAlterColumn(AOp: TAlterColumnOperation): string; override;
    function GenerateDropIndex(AOp: TDropIndexOperation): string; override;
    function GetSetSchemaSQL(const ASchemaName: string): string; override;
    function GetDialect: TDatabaseDialect; override;
    function GetJsonValueSQL(const AColumn, APath: string): string; override;
    function GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
  end;

  /// <summary>
  ///   MariaDB (10.3+) Dialect implementation.
  /// </summary>
  TMariaDBDialect = class(TMySQLDialect)
  public
    function GetDialect: TDatabaseDialect; override;
    function GetSequenceExistsSQL(const ASequenceName: string): string; override;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
  end;

  /// <summary>
  ///   Oracle (12c+) Dialect implementation.
  /// </summary>
  TOracleDialect = class(TBaseDialect)
  public
    function QuoteIdentifier(const AName: string): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function BooleanToSQL(AValue: Boolean): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function GetLastInsertIdSQL: string; override;
    function GetCreateTableSQL(const ATableName, ABody: string): string; override;
    function GetInsertDefaultValuesSQL(const ATableName: string): string; override;
    
    function SupportsInsertReturning: Boolean; override;
    function GetReturningSQL(const AColumnName: string): string; override;
    function GetDialect: TDatabaseDialect; override;
    function GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string; override;
    function GetLockingSQL(ALockMode: TLockMode): string; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetSequenceExistsSQL(const ASequenceName: string): string; override;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
  end;

  /// <summary>
  ///   InterBase (2020+) Dialect implementation. It shares the quoting and
  ///   most types with Firebird, but InterBase has no BIGINT, no identity
  ///   column, no INSERT ... RETURNING, no OFFSET/FETCH and no CREATE
  ///   SEQUENCE: those are written the InterBase way (checked on InterBase 15).
  /// </summary>
  TInterBaseDialect = class(TFirebirdDialect)
  public
    function BooleanToSQL(AValue: Boolean): string; override;
    function GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string; override;
    function GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean = False; APrecision: Integer = 0; AScale: Integer = 0): string; override;
    function SupportsInsertReturning: Boolean; override;
    function GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer = 1): string; override;
    function GetLockingSQL(ALockMode: TLockMode): string; override;
    function GenerateCreateTable(AOp: TCreateTableOperation): string; override;
    function GetDialect: TDatabaseDialect; override;
  end;

implementation
  
{ TDialectFactory }

class function TDialectFactory.CreateDialect(const ADialect: TDatabaseDialect): ISQLDialect;
begin
  case ADialect of
    ddSQLite: Result := TSQLiteDialect.Create;
    ddPostgreSQL: Result := TPostgreSQLDialect.Create;
    ddMySQL: Result := TMySQLDialect.Create;
    ddMariaDB: Result := TMariaDBDialect.Create;
    ddSQLServer: Result := TSQLServerDialect.Create;
    ddFirebird: Result := TFirebirdDialect.Create;
    ddInterbase: Result := TInterBaseDialect.Create;
    ddOracle: Result := TOracleDialect.Create;
    else
      // ddUnknown or fallback
      Result := nil;
  end;
end;

class function TDialectFactory.DetectDialect(const ADriverName: string): TDatabaseDialect;
var
  LDriver: string;
begin
  LDriver := ADriverName.ToLower;
  
  if LDriver.Contains('pg') or LDriver.Contains('postgres') then
    Result := ddPostgreSQL
  else if LDriver.Contains('fb') or LDriver.Contains('firebird') then
    Result := ddFirebird
  else if LDriver.Contains('sqlite') then
    Result := ddSQLite
  else if LDriver.Contains('mssql') or LDriver.Contains('sqlserver') then
    Result := ddSQLServer
  else if LDriver.Contains('ora') or LDriver.Contains('oracle') then
    Result := ddOracle
  else if LDriver.Contains('maria') then
    Result := ddMariaDB
  else if LDriver.Contains('mysql') then
    Result := ddMySQL
  else if LDriver.Contains('ib') or LDriver.Contains('interbase') then
    Result := ddInterbase
  else
    Result := ddUnknown;
end;

{ TBaseDialect }

function TBaseDialect.GetSetSchemaSQL(const ASchemaName: string): string;
begin
  Result := '';
end;

function TBaseDialect.GetCreateSchemaSQL(const ASchemaName: string): string;
begin
  Result := '';
end;


function TBaseDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddUnknown;
end;

function TBaseDialect.SupportsInsertReturning: Boolean;
begin
  Result := False;
end;

function TBaseDialect.GetReturningSQL(const AColumnName: string): string;
begin
  Result := '';
end;

function TBaseDialect.GetReturningPosition: TReturningPosition;
begin
  Result := rpAtEnd;
end;

function TBaseDialect.RequiresOrderByForPaging: Boolean;
begin
  Result := False;
end;

function TBaseDialect.GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string;
var
  i: Integer;
  Params: string;
begin
  Params := '';
  for i := 0 to High(AParamNames) do
  begin
    if i > 0 then Params := Params + ', ';
    Params := Params + GetParamPrefix + AParamNames[i];
  end;
  Result := Format('CALL %s(%s)', [AProcName, Params]);
end;

function TBaseDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  case ALockMode of
    lmShared: Result := 'FOR SHARE';
    lmExclusive: Result := 'FOR UPDATE';
    lmExclusiveNoWait: Result := 'FOR UPDATE NOWAIT';
    else Result := '';
  end;
end;

function TBaseDialect.GetJsonValueSQL(const AColumn, APath: string): string;
begin
  raise Exception.Create('JSON queries not supported by this dialect');
end;

function TBaseDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  raise ENotSupportedException.Create('Sequences are not supported by this dialect');
end;

function TBaseDialect.GetSequenceExistsSQL(const ASequenceName: string): string;
begin
  Result := '';
end;

function TBaseDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := '';
end;

function TBaseDialect.GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
     // Fallback to integer logic (will be overridden by GetColumnType(PTypeInfo) usually, or specific dialects need to override this)
     Exit('INTEGER');

  case AFieldType of
    ftString, ftFixedChar, ftWideString, ftFixedWideChar: Result := 'VARCHAR(255)';
    ftSmallint, ftWord: Result := 'SMALLINT';
    ftInteger, ftLongWord, ftAutoInc: Result := 'INTEGER';
    ftLargeint: Result := 'BIGINT';
    ftFloat, ftSingle, ftExtended: Result := 'FLOAT';
    ftCurrency, ftBCD, ftFMTBcd:
      begin
        if APrecision > 0 then
          Result := Format('DECIMAL(%d,%d)', [APrecision, AScale])
        else
          Result := 'DECIMAL(18,4)';
      end;
    ftBoolean: Result := 'BOOLEAN'; // Some DBs override this
    ftDate: Result := 'DATE';
    ftTime: Result := 'TIME';
    ftDateTime, ftTimeStamp: Result := 'TIMESTAMP';
    ftBytes, ftVarBytes, ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary, ftCursor, ftOraBlob: Result := 'BLOB';
    ftMemo, ftFmtMemo, ftWideMemo: Result := 'TEXT';
    ftGuid: Result := 'CHAR(36)';
  else
    Result := 'VARCHAR(255)';
  end;
end;

function TBaseDialect.UseSchemaPrefix: Boolean;
begin
  Result := False;
end;

function TBaseDialect.BooleanToSQL(AValue: Boolean): string;
begin
  if AValue then Result := '1' else Result := '0';
end;

function TBaseDialect.VariantToSQL(const AValue: Variant): string;
begin
  if VarIsNull(AValue) or VarIsClear(AValue) then
    Result := 'NULL'
  else
  case VarType(AValue) of
    varSmallint, varInteger, varByte, varShortInt, varWord, varLongWord, varInt64:
      Result := IntToStr(AValue);
    varSingle, varDouble, varCurrency:
      Result := FloatToStr(AValue, TFormatSettings.Invariant);
    varDate:
      Result := QuotedStr(FormatDateTime('yyyy-mm-dd hh:nn:ss', AValue));
    varBoolean:
      Result := BooleanToSQL(AValue);
    varUString, varString, varOleStr:
      Result := QuotedStr(AValue);
  else
    Result := QuotedStr(VarToStr(AValue));
  end;
end;

function TBaseDialect.GetParamPrefix: string;
begin
  Result := ':'; // Standard for FireDAC
end;

function TBaseDialect.QuoteIdentifier(const AName: string): string;
begin
  Result := '"' + AName + '"';
end;

function TBaseDialect.GetCascadeActionSQL(AAction: TCascadeAction): string;
begin
  case AAction of
    caNoAction: Result := 'NO ACTION';
    caCascade:  Result := 'CASCADE';
    caSetNull:  Result := 'SET NULL';
    caRestrict: Result := 'RESTRICT';
  else
    Result := 'NO ACTION';
  end;
end;

function TBaseDialect.GetInsertDefaultValuesSQL(const ATableName: string): string;
begin
  // SQLite, PostgreSQL, SQL Server and Firebird accept this form.
  Result := 'INSERT INTO ' + ATableName + ' DEFAULT VALUES';
end;

function TBaseDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  // Default implementation (Standard SQL)
  Result := Format('CREATE TABLE %s (%s);', [ATableName, ABody]);
end;

function TBaseDialect.GenerateMigration(AOperation: TMigrationOperation): string;
begin
  case AOperation.OperationType of
    otCreateTable: Result := GenerateCreateTable(TCreateTableOperation(AOperation));
    otDropTable: Result := GenerateDropTable(TDropTableOperation(AOperation));
    otAddColumn: Result := GenerateAddColumn(TAddColumnOperation(AOperation));
    otDropColumn: Result := GenerateDropColumn(TDropColumnOperation(AOperation));
    otAlterColumn: Result := GenerateAlterColumn(TAlterColumnOperation(AOperation));
    otAddForeignKey: Result := GenerateAddForeignKey(TAddForeignKeyOperation(AOperation));
    otDropForeignKey: Result := GenerateDropForeignKey(TDropForeignKeyOperation(AOperation));
    otCreateIndex: Result := GenerateCreateIndex(TCreateIndexOperation(AOperation));
    otDropIndex: Result := GenerateDropIndex(TDropIndexOperation(AOperation));
    otRenameTable: Result := GenerateRenameTable(TRenameTableOperation(AOperation));
    otRenameColumn: Result := GenerateRenameColumn(TRenameColumnOperation(AOperation));
    otSeedData: Result := GenerateSeedData(TSeedDataOperation(AOperation));
      otDeleteData: Result := GenerateDeleteData(TDeleteDataOperation(AOperation));
    otSql: Result := TSqlOperation(AOperation).Sql;
  else
    Result := '-- Unknown operation';
  end;
end;

function TBaseDialect.GenerateColumnDefinition(AColumn: TColumnDefinition): string;
var
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append(QuoteIdentifier(AColumn.Name));
    SB.Append(' ');
    
    // Type
    SB.Append(AColumn.ColumnType);
    if AColumn.Length > 0 then
    begin
      SB.Append('(');
      SB.Append(AColumn.Length);
      if AColumn.Scale > 0 then
      begin
        SB.Append(',');
        SB.Append(AColumn.Scale); // Actually Precision, Scale usually goes together
      end;
      SB.Append(')');
    end
    else if (AColumn.Precision > 0) then
    begin
      SB.Append('(');
      SB.Append(AColumn.Precision);
      if AColumn.Scale > 0 then
      begin
        SB.Append(',');
        SB.Append(AColumn.Scale);
      end;
      SB.Append(')');
    end;
    
    // Nullable
    if not AColumn.IsNullable then
      SB.Append(' NOT NULL');
      
    // Identity - Note: Some DBs handle this in Type (SERIAL), others here
    if AColumn.IsIdentity then
    begin
      // Basic standard SQL identity, might need override in specific dialects
      // For now, assume the Type handles it (e.g. SERIAL) or we append generated
      // This is tricky for base dialect.
      // Let's assume the user set the correct Type for Identity if it's type-based (SERIAL)
      // Or we append 'GENERATED BY DEFAULT AS IDENTITY' for standard SQL
      // But TSQLiteDialect uses INTEGER PRIMARY KEY for autoinc.
      // Let's leave it to specific dialects or assume the Type string is correct for now.
    end;
    
    // Default
    if AColumn.DefaultValue <> '' then
    begin
      SB.Append(' DEFAULT ');
      SB.Append(AColumn.DefaultValue);
    end;
    
    // Primary Key (Inline)
    if AColumn.IsPrimaryKey then
      SB.Append(' PRIMARY KEY');
      
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TBaseDialect.GenerateCreateTable(AOp: TCreateTableOperation): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to AOp.Columns.Count - 1 do
    begin
      if i > 0 then SB.Append(', ');
      SB.Append(GenerateColumnDefinition(AOp.Columns[i]));
    end;
    
    // Composite PKs (if not inline)
    if (Length(AOp.PrimaryKey) > 1) then
    begin
      SB.Append(', PRIMARY KEY (');
      for i := 0 to High(AOp.PrimaryKey) do
      begin
        if i > 0 then SB.Append(', ');
        SB.Append(QuoteIdentifier(AOp.PrimaryKey[i]));
      end;
      SB.Append(')');
    end;
    
    Result := GetCreateTableSQL(QuoteIdentifier(AOp.Name), SB.ToString);
  finally
    SB.Free;
  end;
end;

function TBaseDialect.GenerateDropTable(AOp: TDropTableOperation): string;
begin
  Result := 'DROP TABLE ' + QuoteIdentifier(AOp.Name);
end;

function TBaseDialect.GenerateAddColumn(AOp: TAddColumnOperation): string;
begin
  Result := Format('ALTER TABLE %s ADD %s', [QuoteIdentifier(AOp.TableName), GenerateColumnDefinition(AOp.Column)]);
end;

function TBaseDialect.GenerateDropColumn(AOp: TDropColumnOperation): string;
begin
  Result := Format('ALTER TABLE %s DROP COLUMN %s', [QuoteIdentifier(AOp.TableName), QuoteIdentifier(AOp.Name)]);
end;

function TBaseDialect.GenerateAlterColumn(AOp: TAlterColumnOperation): string;
begin
  // Standard SQL often uses ALTER COLUMN or MODIFY COLUMN.
  // This is highly dialect specific.
  // Base implementation: ALTER COLUMN
  Result := Format('ALTER TABLE %s ALTER COLUMN %s', [QuoteIdentifier(AOp.TableName), GenerateColumnDefinition(AOp.Column)]);
end;

function TBaseDialect.GenerateAddForeignKey(AOp: TAddForeignKeyOperation): string;
var
  Cols, RefCols: string;
  i: Integer;
begin
  Cols := '';
  for i := 0 to High(AOp.Columns) do
  begin
    if i > 0 then Cols := Cols + ', ';
    Cols := Cols + QuoteIdentifier(AOp.Columns[i]);
  end;
  
  RefCols := '';
  for i := 0 to High(AOp.ReferencedColumns) do
  begin
    if i > 0 then RefCols := RefCols + ', ';
    RefCols := RefCols + QuoteIdentifier(AOp.ReferencedColumns[i]);
  end;

  Result := Format('ALTER TABLE %s ADD CONSTRAINT %s FOREIGN KEY (%s) REFERENCES %s (%s)',
    [QuoteIdentifier(AOp.Table), QuoteIdentifier(AOp.Name), Cols, QuoteIdentifier(AOp.ReferencedTable), RefCols]);
    
  if AOp.OnDelete <> '' then
    Result := Result + ' ON DELETE ' + AOp.OnDelete;
    
  if AOp.OnUpdate <> '' then
    Result := Result + ' ON UPDATE ' + AOp.OnUpdate;
end;

function TBaseDialect.GenerateDropForeignKey(AOp: TDropForeignKeyOperation): string;
begin
  Result := Format('ALTER TABLE %s DROP CONSTRAINT %s', [QuoteIdentifier(AOp.Table), QuoteIdentifier(AOp.Name)]);
end;

function TBaseDialect.GenerateCreateIndex(AOp: TCreateIndexOperation): string;
var
  Cols: string;
  i: Integer;
  UniqueStr: string;
begin
  Cols := '';
  for i := 0 to High(AOp.Columns) do
  begin
    if i > 0 then Cols := Cols + ', ';
    Cols := Cols + QuoteIdentifier(AOp.Columns[i]);
  end;
  
  if AOp.IsUnique then UniqueStr := 'UNIQUE ' else UniqueStr := '';
  
  Result := Format('CREATE %sINDEX %s ON %s (%s)', [UniqueStr, QuoteIdentifier(AOp.Name), QuoteIdentifier(AOp.Table), Cols]);
end;

function TBaseDialect.GenerateDropIndex(AOp: TDropIndexOperation): string;
begin
  Result := 'DROP INDEX ' + QuoteIdentifier(AOp.Name);
end;

function TBaseDialect.GenerateRenameTable(AOp: TRenameTableOperation): string;
begin
  Result := Format('ALTER TABLE %s RENAME TO %s', [QuoteIdentifier(AOp.OldName), QuoteIdentifier(AOp.NewName)]);
end;

function TBaseDialect.GenerateRenameColumn(AOp: TRenameColumnOperation): string;
begin
  // Standard SQL: ALTER TABLE x RENAME COLUMN y TO z
  Result := Format('ALTER TABLE %s RENAME COLUMN %s TO %s',
    [QuoteIdentifier(AOp.TableName), QuoteIdentifier(AOp.OldName), QuoteIdentifier(AOp.NewName)]);
end;

function TBaseDialect.GenerateSeedData(AOp: TSeedDataOperation): string;
var
  Cols, Values, SQL: string;
  i, j: Integer;
begin
  Cols := '';
  for i := 0 to High(AOp.Columns) do
  begin
    if i > 0 then Cols := Cols + ', ';
    Cols := Cols + QuoteIdentifier(AOp.Columns[i]);
  end;

  SQL := '';
  for i := 0 to High(AOp.Data) do
  begin
    Values := '';
    for j := 0 to High(AOp.Data[i]) do
    begin
      if j > 0 then Values := Values + ', ';
      Values := Values + VariantToSQL(AOp.Data[i][j]);
    end;
    SQL := SQL + Format('INSERT INTO %s (%s) VALUES (%s);' + sLineBreak,
      [QuoteIdentifier(AOp.TableName), Cols, Values]);
  end;
  Result := SQL;
end;

function TBaseDialect.GenerateDeleteData(AOp: TDeleteDataOperation): string;
var
  Cond: string;
  i, j: Integer;
begin
  Result := '';
  for i := 0 to High(AOp.Data) do
  begin
    Cond := '';
    for j := 0 to High(AOp.Columns) do
    begin
      if j > 0 then Cond := Cond + ' AND ';
      if VarIsNull(AOp.Data[i][j]) or VarIsClear(AOp.Data[i][j]) then
        Cond := Cond + QuoteIdentifier(AOp.Columns[j]) + ' IS NULL'
      else
        Cond := Cond + QuoteIdentifier(AOp.Columns[j]) + ' = ' + VariantToSQL(AOp.Data[i][j]);
    end;
    Result := Result + Format('DELETE FROM %s WHERE %s;' + sLineBreak,
      [QuoteIdentifier(AOp.TableName), Cond]);
  end;
end;

{ TSQLiteDialect }

function TSQLiteDialect.BooleanToSQL(AValue: Boolean): string;
begin
  // SQLite uses 1/0 for boolean
  if AValue then Result := '1' else Result := '0';
end;

function TSQLiteDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  // LIMIT <count> OFFSET <skip>
  Result := ASQL + ' ' + Format('LIMIT %d OFFSET %d', [ATake, ASkip]);
end;

function TSQLiteDialect.QuoteIdentifier(const AName: string): string;
begin
  if AName = '' then Exit('');
  if AName.Contains('.') then
    Result := '"' + AName.Replace('.', '"."') + '"'
  else
    Result := '"' + AName + '"';
end;

function TSQLiteDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit('INTEGER'); // SQLite AutoInc must be INTEGER PRIMARY KEY

  case ATypeInfo.Kind of
    tkInteger: Result := 'INTEGER';
    tkInt64: Result := 'INTEGER';
    tkFloat: 
      begin
        if ATypeInfo = TypeInfo(TDateTime) then Result := 'DATETIME'
        else if ATypeInfo = TypeInfo(TDate) then Result := 'DATE'
        else if ATypeInfo = TypeInfo(TTime) then Result := 'TIME'
        else Result := 'REAL';
      end;
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString: Result := 'TEXT';
    tkEnumeration:
      begin
        if ATypeInfo = TypeInfo(Boolean) then Result := 'INTEGER'
        else Result := 'INTEGER';
      end;
    tkDynArray:
      begin
        if ATypeInfo = TypeInfo(TBytes) then Result := 'BLOB'
        else Result := 'TEXT';
      end;
    tkVariant: Result := 'BLOB';
    tkClass:
      begin
        if string(ATypeInfo.Name).Contains('TStrings') or string(ATypeInfo.Name).Contains('TStringList') then
          Result := 'TEXT'
        else
          Result := 'TEXT';
      end;
    tkRecord:
      begin
        if ATypeInfo = TypeInfo(TBcd) then
        begin
          if APrecision > 0 then
            Result := Format('NUMERIC(%d,%d)', [APrecision, AScale])
          else
            Result := 'NUMERIC';
        end
        else if string(ATypeInfo.Name).Equals('TUUID') then
          Result := 'VARCHAR(36)'
        else
          Result := 'TEXT';
      end;
  else
    Result := 'TEXT';
  end;
end;

function TSQLiteDialect.GetLastInsertIdSQL: string;
begin
  Result := 'SELECT last_insert_rowid()';
end;

function TSQLiteDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  // SQLite supports IF NOT EXISTS
  Result := Format('CREATE TABLE IF NOT EXISTS %s (%s)', [ATableName, ABody]);
end;

function TSQLiteDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddSQLite;
end;

function TSQLiteDialect.GetJsonValueSQL(const AColumn, APath: string): string;
begin
  // Using json_extract for maximum compatibility. 
  // Redundant identifier quoting is avoided as AColumn is already quoted.
  Result := Format('json_extract(%s, ''$.%s'')', [AColumn, APath]);
end;

// SQLite has no row locks (a write transaction locks the whole file), and
// FOR UPDATE / FOR SHARE are syntax errors there.
function TSQLiteDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  Result := '';
end;

function TSQLiteDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('SELECT nextval FROM dext_sequences WHERE name = ''%s''', [ASequenceName]);
end;

{ TPostgreSQLDialect }

function TPostgreSQLDialect.BooleanToSQL(AValue: Boolean): string;
begin
  // Postgres uses TRUE/FALSE
  if AValue then Result := 'TRUE' else Result := 'FALSE';
end;

function TPostgreSQLDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  // LIMIT <count> OFFSET <skip>
  Result := ASQL + ' ' + Format('LIMIT %d OFFSET %d', [ATake, ASkip]);
end;

function TPostgreSQLDialect.QuoteIdentifier(const AName: string): string;
begin
  if AName = '' then Exit('');
  if AName.Contains('.') then
    Result := '"' + AName.Replace('.', '"."') + '"'
  else
    Result := '"' + AName + '"';
end;

function TPostgreSQLDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit('SERIAL');

  case ATypeInfo.Kind of
    tkInteger: Result := 'INTEGER';
    tkInt64: Result := 'BIGINT';
    tkFloat: 
      begin
        if ATypeInfo = TypeInfo(Double) then Result := 'DOUBLE PRECISION'
        else if ATypeInfo = TypeInfo(Single) then Result := 'REAL'
        else if ATypeInfo = TypeInfo(Currency) then Result := 'MONEY'
        else if ATypeInfo = TypeInfo(TDateTime) then Result := 'TIMESTAMP'
        else if ATypeInfo = TypeInfo(TDate) then Result := 'DATE'
        else if ATypeInfo = TypeInfo(TTime) then Result := 'TIME'
        else Result := 'DOUBLE PRECISION';
      end;
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString: Result := 'VARCHAR(255)';
    tkEnumeration:
      begin
        if ATypeInfo = TypeInfo(Boolean) then Result := 'BOOLEAN'
        else Result := 'INTEGER';
      end;
    tkDynArray:
      begin
        if ATypeInfo = TypeInfo(TBytes) then Result := 'BYTEA'
        else Result := 'JSONB'; // Arrays as JSONB
      end;
    tkRecord:
      begin
        if ATypeInfo = TypeInfo(TBcd) then
        begin
          if APrecision > 0 then
            Result := Format('NUMERIC(%d,%d)', [APrecision, AScale])
          else
            Result := 'NUMERIC';
        end
        else if ATypeInfo = TypeInfo(TGUID) then Result := 'UUID'
        else if ATypeInfo = TypeInfo(TUUID) then Result := 'UUID'
        else Result := 'JSONB'; // Records as JSONB
      end;
    tkClass:
      begin
        if string(ATypeInfo.Name).Contains('TStrings') or string(ATypeInfo.Name).Contains('TStringList') then
          Result := 'TEXT'
        else
          Result := 'JSONB';
      end;
  else
    Result := 'TEXT';
  end;
end;

function TPostgreSQLDialect.GetLastInsertIdSQL: string;
begin
  Result := 'SELECT lastval()';
end;

function TPostgreSQLDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  // PostgreSQL supports IF NOT EXISTS
  Result := Format('CREATE TABLE IF NOT EXISTS %s (%s);', [ATableName, ABody]);
end;

function TPostgreSQLDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddPostgreSQL;
end;

function TPostgreSQLDialect.GetJsonValueSQL(const AColumn, APath: string): string;
begin
  Result := Format('%s #>> ''{%s}''', [AColumn, APath.Replace('.', ',')]);
end;

function TPostgreSQLDialect.SupportsInsertReturning: Boolean;
begin
  Result := True;
end;

function TPostgreSQLDialect.GetReturningSQL(const AColumnName: string): string;
begin
  Result := 'RETURNING ' + QuoteIdentifier(AColumnName);
end;

function TPostgreSQLDialect.GetSetSchemaSQL(const ASchemaName: string): string;
begin
  if ASchemaName <> '' then
    Result := Format('SET search_path TO %s, public;', [QuoteIdentifier(ASchemaName)])
  else
    Result := 'SET search_path TO public;';
end;

function TPostgreSQLDialect.GetCreateSchemaSQL(const ASchemaName: string): string;
begin
  Result := Format('CREATE SCHEMA IF NOT EXISTS %s;', [QuoteIdentifier(ASchemaName)]);
end;

function TPostgreSQLDialect.GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string;
var
  i: Integer;
  Params: string;
begin
  Params := '';
  for i := 0 to High(AParamNames) do
  begin
    if i > 0 then Params := Params + ', ';
    Params := Params + GetParamPrefix + AParamNames[i];
  end;
  // PostgreSQL: CALL ProcName(p1, p2)
  Result := Format('CALL %s(%s)', [AProcName, Params]);
end;

function TPostgreSQLDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  case ALockMode of
    lmShared: Result := 'FOR SHARE';
    lmExclusive: Result := 'FOR UPDATE';
    lmExclusiveNoWait: Result := 'FOR UPDATE NOWAIT';
    else Result := '';
  end;
end;

function TPostgreSQLDialect.UseSchemaPrefix: Boolean;
begin
  // PostgreSQL is better used with SET search_path, so we avoid prefixing
  // tables with schema names to allow session-level multitenancy.
  Result := False;
end;

function TPostgreSQLDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('SELECT nextval(''%s'')', [ASequenceName]);
end;

function TPostgreSQLDialect.GetSequenceExistsSQL(const ASequenceName: string): string;
begin
  Result := Format('SELECT 1 FROM pg_class WHERE relkind = ''S'' AND relname = LOWER(''%s'')', [ASequenceName]);
end;

function TPostgreSQLDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  if AAllocationSize > 1 then
    Result := Format('CREATE SEQUENCE %s INCREMENT BY %d START WITH %d', [ASequenceName, AAllocationSize, AAllocationSize])
  else
    Result := Format('CREATE SEQUENCE %s', [ASequenceName]);
end;

{ TInterBaseDialect }

function TInterBaseDialect.BooleanToSQL(AValue: Boolean): string;
begin
  // InterBase uses 0/1 for boolean (SMALLINT)
  if AValue then Result := '1' else Result := '0';
end;

function TInterBaseDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  // InterBase: ROWS <first> TO <last>, counted from 1
  Result := ASQL + Format(' ROWS %d TO %d', [ASkip + 1, ASkip + ATake]);
end;

function TInterBaseDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    raise ENotSupportedException.Create(
      'InterBase has no identity column. Map the key with [Sequence(''name'')] ' +
      'instead of [AutoInc]: the Dext then takes the id from a generator.');
  // InterBase has no BIGINT keyword
  if ATypeInfo = TypeInfo(Int64) then
    Exit('NUMERIC(18,0)');
  Result := inherited GetColumnType(ATypeInfo, AIsAutoInc, APrecision, AScale);
end;

function TInterBaseDialect.SupportsInsertReturning: Boolean;
begin
  Result := False;
end;

function TInterBaseDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  // InterBase has no NEXT VALUE FOR: GEN_ID with the step
  Result := Format('SELECT GEN_ID(%s, %d) FROM rdb$database', [ASequenceName, AAllocationSize]);
end;

function TInterBaseDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('CREATE GENERATOR %s', [ASequenceName]);
end;

function TInterBaseDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  raise ENotSupportedException.Create('InterBase has no row lock clause in SELECT ' +
    '(no FOR UPDATE WITH LOCK, no FOR SHARE).');
end;

function TInterBaseDialect.GenerateCreateTable(AOp: TCreateTableOperation): string;
var
  Column: TColumnDefinition;
  Name: string;
begin
  // InterBase refuses a primary key column that is not NOT NULL.
  for Column in AOp.Columns do
  begin
    if Column.IsPrimaryKey then
      Column.IsNullable := False;
    for Name in AOp.PrimaryKey do
      if SameText(Name, Column.Name) then
        Column.IsNullable := False;
  end;
  Result := inherited GenerateCreateTable(AOp);
end;

function TInterBaseDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddInterbase;
end;

{ TFirebirdDialect }

function TFirebirdDialect.BooleanToSQL(AValue: Boolean): string;
begin
  // Firebird 3.0+ supports BOOLEAN type (TRUE/FALSE)
  if AValue then Result := 'TRUE' else Result := 'FALSE';
end;

function TFirebirdDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  // Firebird 3.0+: OFFSET x ROWS FETCH NEXT y ROWS ONLY
  Result := ASQL + ' ' + Format('OFFSET %d ROWS FETCH NEXT %d ROWS ONLY', [ASkip, ATake]);
end;

function TFirebirdDialect.QuoteIdentifier(const AName: string): string;
begin
  Result := '"' + AName + '"';
end;

function TFirebirdDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit('BIGINT GENERATED BY DEFAULT AS IDENTITY'); // Firebird 3.0+ Identity

  case ATypeInfo.Kind of
    tkInteger: Result := 'INTEGER';
    tkInt64: Result := 'BIGINT';
    tkFloat: 
      begin
        if ATypeInfo = TypeInfo(Double) then Result := 'DOUBLE PRECISION'
        else if ATypeInfo = TypeInfo(Single) then Result := 'FLOAT'
        else if ATypeInfo = TypeInfo(Currency) then Result := 'DECIMAL(18,4)'
        else if ATypeInfo = TypeInfo(TDateTime) then Result := 'TIMESTAMP'
        else if ATypeInfo = TypeInfo(TDate) then Result := 'DATE'
        else if ATypeInfo = TypeInfo(TTime) then Result := 'TIME'
        else Result := 'DOUBLE PRECISION';
      end;
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString: Result := 'VARCHAR(255)';
    tkEnumeration:
      begin
        if ATypeInfo = TypeInfo(Boolean) then Result := 'BOOLEAN'
        else Result := 'INTEGER';
      end;
    tkDynArray:
      begin
        if ATypeInfo = TypeInfo(TBytes) then Result := 'BLOB'
        else Result := 'BLOB SUB_TYPE TEXT';
      end;
    tkRecord:
      begin
        if ATypeInfo = TypeInfo(TBcd) then
        begin
          if APrecision > 0 then
            Result := Format('DECIMAL(%d,%d)', [APrecision, AScale])
          else
            Result := 'DECIMAL(18,4)';
        end
        else if ATypeInfo = TypeInfo(TGUID) then Result := 'CHAR(36)'
        else if ATypeInfo = TypeInfo(TUUID) then Result := 'CHAR(36)'
        else Result := 'VARCHAR(255)';
      end;
    tkClass:
      begin
        if string(ATypeInfo.Name).Contains('TStrings') or string(ATypeInfo.Name).Contains('TStringList') then
          Result := 'BLOB SUB_TYPE TEXT'
        else
          Result := 'VARCHAR(255)';
      end;
  else
    Result := 'VARCHAR(255)';
  end;
end;

function TFirebirdDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  // Firebird: SELECT ... FOR UPDATE WITH LOCK locks row by row as they are
  // fetched. There is no shared lock and no per-statement NOWAIT.
  case ALockMode of
    lmExclusive: Result := 'FOR UPDATE WITH LOCK';
    lmShared:
      raise ENotSupportedException.Create('Firebird has no shared row lock (FOR SHARE).');
    lmExclusiveNoWait:
      raise ENotSupportedException.Create('Firebird has no NOWAIT per statement: ' +
        'set the transaction to NO WAIT instead.');
  else
    Result := '';
  end;
end;

function TFirebirdDialect.GenerateRenameColumn(AOp: TRenameColumnOperation): string;
begin
  Result := Format('ALTER TABLE %s ALTER COLUMN %s TO %s',
    [QuoteIdentifier(AOp.TableName), QuoteIdentifier(AOp.OldName), QuoteIdentifier(AOp.NewName)]);
end;

function TFirebirdDialect.GenerateRenameTable(AOp: TRenameTableOperation): string;
begin
  raise ENotSupportedException.Create('Firebird and InterBase cannot rename a table. ' +
    'Create the new table, copy the rows and drop the old one.');
end;

function TFirebirdDialect.GenerateDropColumn(AOp: TDropColumnOperation): string;
begin
  // No COLUMN keyword: ALTER TABLE t DROP c
  Result := Format('ALTER TABLE %s DROP %s', [QuoteIdentifier(AOp.TableName), QuoteIdentifier(AOp.Name)]);
end;

function TFirebirdDialect.GenerateAlterColumn(AOp: TAlterColumnOperation): string;
var
  TypeSQL: string;
begin
  // The type is changed with TYPE, and only the type: nullability and
  // defaults have their own statements.
  TypeSQL := AOp.Column.ColumnType;
  if AOp.Column.Length > 0 then
    TypeSQL := TypeSQL + '(' + IntToStr(AOp.Column.Length) + ')'
  else if AOp.Column.Precision > 0 then
    TypeSQL := TypeSQL + '(' + IntToStr(AOp.Column.Precision) + ',' + IntToStr(AOp.Column.Scale) + ')';
  Result := Format('ALTER TABLE %s ALTER COLUMN %s TYPE %s',
    [QuoteIdentifier(AOp.TableName), QuoteIdentifier(AOp.Column.Name), TypeSQL]);
end;

function TFirebirdDialect.GetLastInsertIdSQL: string;
begin
  // Firebird usually requires RETURNING clause in INSERT
  // There is no safe global "last insert id" function without RETURNING
  Result := ''; 
end;

function TFirebirdDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  // Firebird doesn't support IF NOT EXISTS in CREATE TABLE directly in all versions,
  // but we can use RECREATE TABLE or EXECUTE BLOCK.
  // For simplicity in ORM generation, we stick to standard CREATE TABLE.
  // User should handle existence check or use EnsureCreated carefully.
  Result := Format('CREATE TABLE %s (%s)', [ATableName, ABody]);
end;

function TFirebirdDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddFirebird;
end;

function TFirebirdDialect.SupportsInsertReturning: Boolean;
begin
  Result := True;
end;

function TFirebirdDialect.GetReturningSQL(const AColumnName: string): string;
begin
  Result := 'RETURNING ' + QuoteIdentifier(AColumnName);
end;

function TFirebirdDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  if AAllocationSize > 1 then
    Result := Format('SELECT GEN_ID(%s, %d) FROM rdb$database', [ASequenceName, AAllocationSize])
  else
    Result := Format('SELECT NEXT VALUE FOR %s FROM rdb$database', [ASequenceName]);
end;

function TFirebirdDialect.GetSequenceExistsSQL(const ASequenceName: string): string;
begin
  Result := Format('SELECT 1 FROM rdb$generators WHERE rdb$generator_name = UPPER(''%s'')', [ASequenceName]);
end;

function TFirebirdDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('CREATE SEQUENCE %s', [ASequenceName]);
end;

{ TSQLServerDialect }

function TSQLServerDialect.BooleanToSQL(AValue: Boolean): string;
begin
  if AValue then Result := '1' else Result := '0';
end;

function TSQLServerDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  // SQL Server 2012+: OFFSET x ROWS FETCH NEXT y ROWS ONLY
  // Requires ORDER BY clause in the query!
  Result := ASQL + ' ' + Format('OFFSET %d ROWS FETCH NEXT %d ROWS ONLY', [ASkip, ATake]);
end;

function TSQLServerDialect.QuoteIdentifier(const AName: string): string;
var
  i, Len: Integer;
  SB: TStringBuilder;
begin
  Len := Length(AName);
  if Len = 0 then Exit('');

  // Avoid double quoting if already bracketed
  if (AName[1] = '[') and (AName[Len] = ']') then Exit(AName);

  // Optimization for identifiers without dots (most common cases)
  if Pos('.', AName) = 0 then
    Exit('[' + AName + ']');

  // Use TStringBuilder for identifiers with dots (schema.table) to avoid multiple string allocations
  SB := TStringBuilder.Create(Len + 4);
  try
    SB.Append('[');
    for i := 1 to Len do
    begin
      if AName[i] = '.' then
        SB.Append('].[')
      else
        SB.Append(AName[i]);
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TSQLServerDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit('INT IDENTITY(1,1)');

  case ATypeInfo.Kind of
    tkInteger: Result := 'INT';
    tkInt64: Result := 'BIGINT';
    tkFloat: 
      begin
        if ATypeInfo = TypeInfo(Double) then Result := 'FLOAT'
        else if ATypeInfo = TypeInfo(Single) then Result := 'REAL'
        else if ATypeInfo = TypeInfo(Currency) then Result := 'MONEY'
        else if ATypeInfo = TypeInfo(TDateTime) then Result := 'DATETIME2'
        else if ATypeInfo = TypeInfo(TDate) then Result := 'DATE'
        else if ATypeInfo = TypeInfo(TTime) then Result := 'TIME'
        else Result := 'FLOAT';
      end;
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString: Result := 'VARCHAR(255)';
    tkEnumeration:
      begin
        if ATypeInfo = TypeInfo(Boolean) then Result := 'BIT'
        else Result := 'INT';
      end;
    tkDynArray:
      begin
        if ATypeInfo = TypeInfo(TBytes) then Result := 'VARBINARY(MAX)'
        else Result := 'NVARCHAR(MAX)';
      end;
    tkRecord:
      begin
        if ATypeInfo = TypeInfo(TBcd) then
        begin
          if APrecision > 0 then
            Result := Format('DECIMAL(%d,%d)', [APrecision, AScale])
          else
            Result := 'DECIMAL(18,4)';
        end
        else if ATypeInfo = TypeInfo(TGUID) then Result := 'UNIQUEIDENTIFIER'
        else if ATypeInfo = TypeInfo(TUUID) then Result := 'UNIQUEIDENTIFIER'
        else Result := 'NVARCHAR(MAX)';
      end;
    tkClass:
      begin
        if string(ATypeInfo.Name).Contains('TStrings') or string(ATypeInfo.Name).Contains('TStringList') then
          Result := 'NVARCHAR(MAX)'
        else
          Result := 'NVARCHAR(MAX)';
      end;
  else
    Result := 'NVARCHAR(MAX)';
  end;
end;

function TSQLServerDialect.GetLastInsertIdSQL: string;
begin
  Result := 'SELECT SCOPE_IDENTITY()';
end;

function TSQLServerDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  // SQL Server uses IF NOT EXISTS with OBJECT_ID check
  Result := Format('IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''%s'') AND type = ''U'') ' +
                   'CREATE TABLE %s (%s)', [ATableName, ATableName, ABody]);
end;

function TSQLServerDialect.SupportsInsertReturning: Boolean;
begin
  Result := True; // SQL Server supports OUTPUT INSERTED
end;

function TSQLServerDialect.GetReturningSQL(const AColumnName: string): string;
begin
  // SQL Server uses OUTPUT INSERTED.column_name instead of RETURNING
  Result := 'OUTPUT INSERTED.' + QuoteIdentifier(AColumnName);
end;

function TSQLServerDialect.GetReturningPosition: TReturningPosition;
begin
  Result := rpBeforeValues;
end;

function TSQLServerDialect.RequiresOrderByForPaging: Boolean;
begin
  Result := True;
end;

function TSQLServerDialect.UseSchemaPrefix: Boolean;
begin
  Result := True;
end;

function TSQLServerDialect.GetCreateSchemaSQL(const ASchemaName: string): string;
begin
  Result := Format('IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = %s) ' +
                   'EXEC(''CREATE SCHEMA %s'')', [QuotedStr(ASchemaName), QuoteIdentifier(ASchemaName)]);
end;

function TSQLServerDialect.GetSetSchemaSQL(const ASchemaName: string): string;
begin
  // In SQL Server, "Schema" usually refers to the database if used for tenancy, 
  // or actual schemas within a database. 
  // If it's a database change:
  if SameText(ASchemaName, 'dbo') then
    Exit('');
  Result := Format('USE %s;', [QuoteIdentifier(ASchemaName)]);
  // Note: For actual schema switching within a DB, SQL Server doesn't have a 
  // session-level SET SCHEMA. Prefixing is required.
end;

function TSQLServerDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddSQLServer;
end;

function TSQLServerDialect.GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string;
var
  i: Integer;
  Params: string;
begin
  Params := '';
  for i := 0 to High(AParamNames) do
  begin
    if i > 0 then Params := Params + ', ';
    Params := Params + GetParamPrefix + AParamNames[i];
  end;
  // SQL Server: EXEC ProcName p1, p2
  Result := Format('EXEC %s %s', [AProcName, Params]);
end;

function TSQLServerDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  case ALockMode of
    lmShared: Result := 'WITH (HOLDLOCK)';
    lmExclusive: Result := 'WITH (UPDLOCK, ROWLOCK)';
    lmExclusiveNoWait: Result := 'WITH (UPDLOCK, ROWLOCK, NOWAIT)';
    else Result := '';
  end;
end;

function TSQLServerDialect.GetJsonValueSQL(const AColumn, APath: string): string;
begin
  Result := Format('JSON_VALUE(%s, ''$.%s'')', [AColumn, APath]);
end;

function TSQLServerDialect.GenerateDropIndex(AOp: TDropIndexOperation): string;
begin
  // SQL Server: the index belongs to a table, and DROP INDEX must name it.
  Result := Format('DROP INDEX %s ON %s', [QuoteIdentifier(AOp.Name), QuoteIdentifier(AOp.Table)]);
end;

function TSQLServerDialect.GenerateRenameTable(AOp: TRenameTableOperation): string;
begin
  // There is no RENAME in SQL Server: sp_rename takes the current name as an
  // object name and the new one as a plain name (no brackets).
  Result := Format('EXEC sp_rename N''%s'', N''%s''',
    [StringReplace(QuoteIdentifier(AOp.OldName), '''', '''''', [rfReplaceAll]),
     StringReplace(AOp.NewName, '''', '''''', [rfReplaceAll])]);
end;

function TSQLServerDialect.GenerateRenameColumn(AOp: TRenameColumnOperation): string;
begin
  Result := Format('EXEC sp_rename N''%s.%s'', N''%s'', N''COLUMN''',
    [StringReplace(QuoteIdentifier(AOp.TableName), '''', '''''', [rfReplaceAll]),
     StringReplace(QuoteIdentifier(AOp.OldName), '''', '''''', [rfReplaceAll]),
     StringReplace(AOp.NewName, '''', '''''', [rfReplaceAll])]);
end;

function TSQLServerDialect.GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit(inherited GetColumnTypeForField(AFieldType, AIsAutoInc, APrecision, AScale));

  // SQL Server has no BOOLEAN, its TIMESTAMP is a row version that holds no
  // date, and BLOB/TEXT do not exist (TEXT is deprecated): the base names
  // would make CREATE TABLE fail or store the wrong thing.
  case AFieldType of
    ftGuid: Result := 'UNIQUEIDENTIFIER';
    ftBoolean: Result := 'BIT';
    ftDateTime, ftTimeStamp: Result := 'DATETIME2';
    ftBytes, ftVarBytes, ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary:
      Result := 'VARBINARY(MAX)';
    ftMemo, ftFmtMemo, ftWideMemo: Result := 'NVARCHAR(MAX)';
  else
    Result := inherited GetColumnTypeForField(AFieldType, AIsAutoInc, APrecision, AScale);
  end;
end;

function TSQLServerDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('SELECT NEXT VALUE FOR %s', [ASequenceName]);
end;

function TSQLServerDialect.GetSequenceExistsSQL(const ASequenceName: string): string;
begin
  Result := Format('SELECT 1 FROM sys.sequences WHERE name = ''%s''', [ASequenceName]);
end;

function TSQLServerDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  if AAllocationSize > 1 then
    Result := Format('CREATE SEQUENCE %s INCREMENT BY %d START WITH %d', [ASequenceName, AAllocationSize, AAllocationSize])
  else
    Result := Format('CREATE SEQUENCE %s', [ASequenceName]);
end;

{ TMySQLDialect }

function TMySQLDialect.BooleanToSQL(AValue: Boolean): string;
begin
  if AValue then Result := '1' else Result := '0';
end;

function TMySQLDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  Result := ASQL + ' ' + Format('LIMIT %d OFFSET %d', [ATake, ASkip]);
end;

function TMySQLDialect.QuoteIdentifier(const AName: string): string;
begin
  if AName = '' then Exit('');
  if AName.Contains('.') then
    Result := '`' + AName.Replace('.', '`.`') + '`'
  else
    Result := '`' + AName + '`';
end;

function TMySQLDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit('INT AUTO_INCREMENT');

  case ATypeInfo.Kind of
    tkInteger: Result := 'INT';
    tkInt64: Result := 'BIGINT';
    tkFloat: 
      begin
        if ATypeInfo = TypeInfo(Double) then Result := 'DOUBLE'
        else if ATypeInfo = TypeInfo(Single) then Result := 'FLOAT'
        else if ATypeInfo = TypeInfo(Currency) then Result := 'DECIMAL(18,4)'
        else if ATypeInfo = TypeInfo(TDateTime) then Result := 'DATETIME'
        else if ATypeInfo = TypeInfo(TDate) then Result := 'DATE'
        else if ATypeInfo = TypeInfo(TTime) then Result := 'TIME'
        else Result := 'DOUBLE';
      end;
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString: Result := 'VARCHAR(255)';
    tkEnumeration:
      begin
        if ATypeInfo = TypeInfo(Boolean) then Result := 'TINYINT(1)'
        else Result := 'INT';
      end;
    tkDynArray:
      begin
        if ATypeInfo = TypeInfo(TBytes) then Result := 'LONGBLOB'
        else Result := 'JSON';
      end;
    tkRecord:
      begin
        if ATypeInfo = TypeInfo(TBcd) then
        begin
          if APrecision > 0 then
            Result := Format('DECIMAL(%d,%d)', [APrecision, AScale])
          else
            Result := 'DECIMAL(18,4)';
        end
        else if ATypeInfo = TypeInfo(TGUID) then Result := 'CHAR(36)'
        else if ATypeInfo = TypeInfo(TUUID) then Result := 'CHAR(36)'
        else Result := 'JSON';
      end;
    tkClass:
      begin
        if string(ATypeInfo.Name).Contains('TStrings') or string(ATypeInfo.Name).Contains('TStringList') then
          Result := 'LONGTEXT'
        else
          Result := 'JSON';
      end;
  else
    Result := 'TEXT';
  end;
end;

function TMySQLDialect.GetLastInsertIdSQL: string;
begin
  Result := 'SELECT LAST_INSERT_ID()';
end;

function TMySQLDialect.GetInsertDefaultValuesSQL(const ATableName: string): string;
begin
  // MySQL and MariaDB have no DEFAULT VALUES: an empty column list does it.
  Result := 'INSERT INTO ' + ATableName + ' () VALUES ()';
end;

function TMySQLDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  Result := Format('CREATE TABLE IF NOT EXISTS %s (%s)', [ATableName, ABody]);
end;

function TMySQLDialect.GenerateDropIndex(AOp: TDropIndexOperation): string;
begin
  // MySQL and MariaDB: the index name is only unique inside its table.
  Result := Format('DROP INDEX %s ON %s', [QuoteIdentifier(AOp.Name), QuoteIdentifier(AOp.Table)]);
end;

function TMySQLDialect.GenerateAlterColumn(AOp: TAlterColumnOperation): string;
begin
  // MySQL uses MODIFY COLUMN
  Result := Format('ALTER TABLE %s MODIFY COLUMN %s', [QuoteIdentifier(AOp.TableName), GenerateColumnDefinition(AOp.Column)]);
end;

function TMySQLDialect.GetSetSchemaSQL(const ASchemaName: string): string;
begin
  if ASchemaName <> '' then
    Result := Format('USE %s;', [QuoteIdentifier(ASchemaName)])
  else
    Result := '';
end;

function TMySQLDialect.GetColumnTypeForField(AFieldType: TFieldType; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AFieldType = ftBoolean then
    Result := 'TINYINT(1)'
  else
    Result := inherited GetColumnTypeForField(AFieldType, AIsAutoInc, APrecision, AScale);
end;

function TMySQLDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddMySQL;
end;

function TMySQLDialect.GetJsonValueSQL(const AColumn, APath: string): string;
begin
  Result := Format('JSON_UNQUOTE(JSON_EXTRACT(%s, ''$.%s''))', [AColumn, APath]);
end;

function TMySQLDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('SELECT NEXTVAL(%s)', [ASequenceName]);
end;

{ TMariaDBDialect }

function TMariaDBDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddMariaDB;
end;

function TMariaDBDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  if AAllocationSize > 1 then
    Result := Format('CREATE SEQUENCE %s INCREMENT BY %d START WITH %d',
      [ASequenceName, AAllocationSize, AAllocationSize])
  else
    Result := Format('CREATE SEQUENCE %s', [ASequenceName]);
end;

function TMariaDBDialect.GetSequenceExistsSQL(const ASequenceName: string): string;
begin
  Result := Format(
    'SELECT 1 FROM information_schema.TABLES ' +
    'WHERE TABLE_SCHEMA = DATABASE() AND LOWER(TABLE_NAME) = LOWER(''%s'') ' +
    'AND TABLE_TYPE = ''SEQUENCE''', [ASequenceName]);
end;

{ TOracleDialect }

function TOracleDialect.BooleanToSQL(AValue: Boolean): string;
begin
  // Oracle doesn't have BOOLEAN type in SQL (only PL/SQL).
  // Standard practice is NUMBER(1) check (0/1) or CHAR(1) ('Y'/'N').
  // We use 1/0.
  if AValue then Result := '1' else Result := '0';
end;

function TOracleDialect.GeneratePaging(const ASQL: string; ASkip, ATake: Integer): string;
begin
  if ASkip = 0 then
    Result := Format('SELECT * FROM (%s) WHERE ROWNUM <= %d', [ASQL, ATake])
  else
    Result := Format('SELECT * FROM (SELECT a.*, ROWNUM rnum FROM (%s) a WHERE ROWNUM <= %d) WHERE rnum > %d',
      [ASQL, ASkip + ATake, ASkip]);
end;

function TOracleDialect.QuoteIdentifier(const AName: string): string;
begin
  // Oracle uses double quotes for case sensitivity.
  // Unquoted identifiers are UPPERCASE.
  Result := '"' + AName + '"';
end;

function TOracleDialect.GetColumnType(ATypeInfo: PTypeInfo; AIsAutoInc: Boolean; APrecision, AScale: Integer): string;
begin
  if AIsAutoInc then
    Exit('NUMBER(10) GENERATED BY DEFAULT AS IDENTITY'); // Oracle 12c+

  case ATypeInfo.Kind of
    tkInteger: Result := 'NUMBER(10)';
    tkInt64: Result := 'NUMBER(19)';
    tkFloat: 
      begin
        if ATypeInfo = TypeInfo(Double) then Result := 'BINARY_DOUBLE'
        else if ATypeInfo = TypeInfo(Single) then Result := 'BINARY_FLOAT'
        else if ATypeInfo = TypeInfo(Currency) then Result := 'NUMBER(19,4)'
        else if ATypeInfo = TypeInfo(TDateTime) then Result := 'TIMESTAMP'
        else if ATypeInfo = TypeInfo(TDate) then Result := 'DATE'
        else if ATypeInfo = TypeInfo(TTime) then Result := 'TIMESTAMP' // Oracle TIME? usually TIMESTAMP or DATE
        else Result := 'BINARY_DOUBLE';
      end;
    tkChar, tkString, tkWChar, tkLString, tkWString, tkUString: Result := 'VARCHAR2(255)';
    tkEnumeration:
      begin
        if ATypeInfo = TypeInfo(Boolean) then Result := 'NUMBER(1)'
        else Result := 'NUMBER(10)';
      end;
    tkDynArray:
      begin
        if ATypeInfo = TypeInfo(TBytes) then Result := 'BLOB'
        else Result := 'CLOB';
      end;
    tkRecord:
      begin
        if ATypeInfo = TypeInfo(TBcd) then
        begin
          if APrecision > 0 then
            Result := Format('NUMBER(%d,%d)', [APrecision, AScale])
          else
            Result := 'NUMBER(28,10)';
        end
        else if ATypeInfo = TypeInfo(TGUID) then Result := 'VARCHAR2(36)'
        else Result := 'VARCHAR2(4000)';
      end;
  else
    Result := 'VARCHAR2(255)';
  end;
end;

function TOracleDialect.GetInsertDefaultValuesSQL(const ATableName: string): string;
begin
  // Oracle has no DEFAULT VALUES: the DEFAULT keyword takes the key's place.
  Result := 'INSERT INTO ' + ATableName + ' VALUES (DEFAULT)';
end;

function TOracleDialect.GetLastInsertIdSQL: string;
begin
  // Oracle requires RETURNING INTO clause.
  // No global scalar function like SCOPE_IDENTITY available easily without PL/SQL context.
  Result := ''; 
end;

function TOracleDialect.GetCreateTableSQL(const ATableName, ABody: string): string;
begin
  // Oracle doesn't support IF NOT EXISTS.
  Result := Format('CREATE TABLE %s (%s)', [ATableName, ABody]);
end;

function TOracleDialect.SupportsInsertReturning: Boolean;
begin
  Result := True;
end;

function TOracleDialect.GetReturningSQL(const AColumnName: string): string;
begin
  Result := 'RETURNING ' + QuoteIdentifier(AColumnName) + ' INTO :RET_VAL';
end;

function TOracleDialect.GetDialect: TDatabaseDialect;
begin
  Result := ddOracle;
end;

function TOracleDialect.GenerateProcedureCallSQL(const AProcName: string; const AParamNames: TArray<string>): string;
var
  i: Integer;
  Params: string;
begin
  Params := '';
  for i := 0 to High(AParamNames) do
  begin
    if i > 0 then Params := Params + ', ';
    Params := Params + GetParamPrefix + AParamNames[i];
  end;
  // Oracle: BEGIN ProcName(p1, p2); END;
  Result := Format('BEGIN %s(%s); END;', [AProcName, Params]);
end;

function TOracleDialect.GetLockingSQL(ALockMode: TLockMode): string;
begin
  case ALockMode of
    lmShared: Result := 'FOR SHARE';
    lmExclusive: Result := 'FOR UPDATE';
    lmExclusiveNoWait: Result := 'FOR UPDATE NOWAIT';
    else Result := '';
  end;
end;

function TOracleDialect.GetSequenceNextValSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  Result := Format('SELECT %s.NEXTVAL FROM dual', [ASequenceName]);
end;

function TOracleDialect.GetSequenceExistsSQL(const ASequenceName: string): string;
begin
  Result := Format('SELECT 1 FROM user_sequences WHERE sequence_name = UPPER(''%s'')', [ASequenceName]);
end;

function TOracleDialect.GetCreateSequenceSQL(const ASequenceName: string; AAllocationSize: Integer): string;
begin
  if AAllocationSize > 1 then
    Result := Format('CREATE SEQUENCE %s INCREMENT BY %d START WITH %d', [ASequenceName, AAllocationSize, AAllocationSize])
  else
    Result := Format('CREATE SEQUENCE %s', [ASequenceName]);
end;

end.
