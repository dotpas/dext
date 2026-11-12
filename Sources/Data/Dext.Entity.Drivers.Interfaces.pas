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
unit Dext.Entity.Drivers.Interfaces;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  Dext.Collections,
  Data.DB,
  Dext.Entity.Dialects;

type
  {$M+}
  IDbReader = interface;
  IDbTransaction = interface;
  IDbCommand = interface;

  /// <summary>
  ///   Represents a database connection.
  /// </summary>
  /// <summary>
  ///   Represents a connection with the database.
  /// </summary>
  IDbConnection = interface
    ['{20000000-0000-0000-0000-000000000002}']
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    
    function BeginTransaction: IDbTransaction;
    
    // Factory methods
    function CreateCommand(const ASQL: string): IDbCommand; 
    
    function GetLastInsertId: Variant;
    
    function GetConnectionString: string;
    procedure SetConnectionString(const AValue: string);
    property ConnectionString: string read GetConnectionString write SetConnectionString;

    function GetDialect: TDatabaseDialect;
    property Dialect: TDatabaseDialect read GetDialect;

    function TableExists(const ATableName: string): Boolean;
    
    function IsPooled: Boolean;
    property Pooled: Boolean read IsPooled;

    procedure SetOnLog(AValue: TProc<string>);
    function GetOnLog: TProc<string>;
    property OnLog: TProc<string> read GetOnLog write SetOnLog;
  end;

  /// <summary>
  ///   Represents a database transaction.
  /// </summary>
  IDbTransaction = interface
    ['{20000000-0000-0000-0000-000000000003}']
    procedure Commit;
    procedure Rollback;
  end;

  /// <summary>
  ///   Represents a command to execute against the database.
  /// </summary>
  /// <summary>
  ///   Representa um comando SQL a ser executado contra o banco de dados.
  /// </summary>
  IDbCommand = interface
    ['{20000000-0000-0000-0000-000000000004}']
    procedure SetSQL(const ASQL: string);
    procedure AddParam(const AName: string; const AValue: TValue); overload;
    /// <summary>
    ///   Adds a parameter with explicit data type. Use when [DbType] attribute
    ///   specifies a different type than what would be inferred from TValue.
    /// </summary>
    procedure AddParam(const AName: string; const AValue: TValue; ADataType: TFieldType); overload;
    /// <summary>
    ///   Binds values to parameters in SQL declaration order (first placeholder = index 0).
    ///   Use with raw SQL that uses named placeholders (:id, :name) after Prepare has built the param list.
    /// </summary>
    procedure BindSequentialParams(const AValues: TArray<TValue>);
    procedure SetParamType(const AName: string; AType: TParamType);
    function GetParamValue(const AName: string): TValue;
    procedure ClearParams;
    
    procedure Execute;
    function ExecuteQuery: IDbReader;
    function ExecuteNonQuery: Integer;
    function ExecuteScalar: TValue;
    
    // Array DML Support
    procedure SetArraySize(const ASize: Integer);
    procedure SetParamArray(const AName: string; const AValues: TArray<TValue>);
    /// <summary>
    ///   Runs the command once per array element. Returns the total of rows
    ///   affected, or -1 when the driver does not report it.
    /// </summary>
    function ExecuteBatch(const ATimes: Integer; const AOffset: Integer = 0): Integer;
  end;

  /// <summary>
  ///   Represents a forward-only stream of rows from a data source.
  /// </summary>
  /// <summary>
  ///   Representa um fluxo de dados unidirecional vindo do banco de dados (Cursor).
  /// </summary>
  IDbReader = interface
    ['{20000000-0000-0000-0000-000000000005}']
    function Next: Boolean;
    
    function GetValue(const AColumnName: string): TValue; overload;
    function GetValue(AColumnIndex: Integer): TValue; overload;
    
    function GetColumnCount: Integer;
    function GetColumnName(AIndex: Integer): string;
    
    function GetInt32(AIndex: Integer): Integer;
    function GetInt64(AIndex: Integer): Int64;
    function GetDouble(AIndex: Integer): Double;
    function GetBoolean(AIndex: Integer): Boolean;
    function GetString(AIndex: Integer): string;
    function GetDateTime(AIndex: Integer): TDateTime;
    function GetColumnType(AIndex: Integer): TFieldType;
    function IsNull(AIndex: Integer): Boolean;

    procedure Close;
  end;
  {$M-}

implementation

end.

