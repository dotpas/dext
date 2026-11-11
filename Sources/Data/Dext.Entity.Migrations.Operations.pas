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
unit Dext.Entity.Migrations.Operations;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Collections;

type
  TOperationType = (
    otCreateTable,
    otDropTable,
    otAddColumn,
    otDropColumn,
    otAlterColumn,
    otAddPrimaryKey,
    otDropPrimaryKey,
    otAddForeignKey,
    otDropForeignKey,
    otCreateIndex,
    otDropIndex,
    otRenameTable,
    otRenameColumn,
    otSeedData,
    otDeleteData,
    otSql // Raw SQL fallback
  );

  /// <summary>
  ///   Base class for all migration operations.
  /// </summary>
  TMigrationOperation = class
  private
    FOperationType: TOperationType;
  public
    constructor Create(AOperationType: TOperationType);
    property OperationType: TOperationType read FOperationType;
  end;

  // --- Column Definitions ---

  TColumnDefinition = class
  public
    Name: string;
    ColumnType: string; // e.g. 'VARCHAR', 'INTEGER' - Or use an Enum? Enum is better for abstraction.
    // Let's use a string for now to allow flexibility, but ideally mapped from a standard Enum.
    // Actually, let's define a TDbType enum in Dext.Entity.Core or here.
    // For now, string is safer for raw passthrough, but we need abstraction.
    // Let's stick to string for the prototype, or TFieldType from Data.DB?
    // Better: TLogicalType (ltInteger, ltString, ltGuid, etc.)
    
    Length: Integer;
    Precision: Integer;
    Scale: Integer;
    IsNullable: Boolean;
    IsPrimaryKey: Boolean;
    IsIdentity: Boolean; // AutoInc
    DefaultValue: string;
    
    constructor Create(const AName: string; const AType: string);
  end;

  // --- Table Operations ---

  TCreateTableOperation = class(TMigrationOperation)
  private
    FName: string;
    FColumns: IList<TColumnDefinition>;
    FPrimaryKey: TArray<string>; // List of column names
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    
    property Name: string read FName;
    property Columns: IList<TColumnDefinition> read FColumns;
    property PrimaryKey: TArray<string> read FPrimaryKey write FPrimaryKey;
  end;

  TDropTableOperation = class(TMigrationOperation)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  // --- Column Operations ---

  TAddColumnOperation = class(TMigrationOperation)
  private
    FTableName: string;
    FColumn: TColumnDefinition;
  public
    constructor Create(const ATableName: string; AColumn: TColumnDefinition);
    destructor Destroy; override;
    
    property TableName: string read FTableName;
    property Column: TColumnDefinition read FColumn;
  end;

  TDropColumnOperation = class(TMigrationOperation)
  private
    FTableName: string;
    FName: string;
  public
    constructor Create(const ATableName, AName: string);
    property TableName: string read FTableName;
    property Name: string read FName;
  end;

  TAlterColumnOperation = class(TMigrationOperation)
  private
    FTableName: string;
    FColumn: TColumnDefinition;
  public
    constructor Create(const ATableName: string; AColumn: TColumnDefinition);
    destructor Destroy; override;
    
    property TableName: string read FTableName;
    property Column: TColumnDefinition read FColumn;
  end;

  // --- Constraint Operations ---

  TAddForeignKeyOperation = class(TMigrationOperation)
  private
    FTable: string;
    FName: string;
    FColumns: TArray<string>;
    FReferencedTable: string;
    FReferencedColumns: TArray<string>;
    FOnDelete: string; // CASCADE, SET NULL, NO ACTION
    FOnUpdate: string;
  public
    constructor Create(const ATable, AName: string; const AColumns: TArray<string>; 
      const ARefTable: string; const ARefColumns: TArray<string>);
      
    property Table: string read FTable;
    property Name: string read FName;
    property Columns: TArray<string> read FColumns;
    property ReferencedTable: string read FReferencedTable;
    property ReferencedColumns: TArray<string> read FReferencedColumns;
    property OnDelete: string read FOnDelete write FOnDelete;
    property OnUpdate: string read FOnUpdate write FOnUpdate;
  end;

  TDropForeignKeyOperation = class(TMigrationOperation)
  private
    FTable: string;
    FName: string;
  public
    constructor Create(const ATable, AName: string);
    property Table: string read FTable;
    property Name: string read FName;
  end;

  TCreateIndexOperation = class(TMigrationOperation)
  private
    FTable: string;
    FName: string;
    FColumns: TArray<string>;
    FIsUnique: Boolean;
  public
    constructor Create(const ATable, AName: string; const AColumns: TArray<string>; AIsUnique: Boolean = False);
    property Table: string read FTable;
    property Name: string read FName;
    property Columns: TArray<string> read FColumns;
    property IsUnique: Boolean read FIsUnique;
  end;

  TDropIndexOperation = class(TMigrationOperation)
  private
    FTable: string;
    FName: string;
  public
    constructor Create(const ATable, AName: string);
    property Table: string read FTable;
    property Name: string read FName;
  end;
  
  TRenameTableOperation = class(TMigrationOperation)
  private
    FOldName: string;
    FNewName: string;
  public
    constructor Create(const AOldName, ANewName: string);
    property OldName: string read FOldName;
    property NewName: string read FNewName;
  end;

  TRenameColumnOperation = class(TMigrationOperation)
  private
    FTableName: string;
    FOldName: string;
    FNewName: string;
  public
    constructor Create(const ATableName, AOldName, ANewName: string);
    property TableName: string read FTableName;
    property OldName: string read FOldName;
    property NewName: string read FNewName;
  end;

  TSeedDataOperation = class(TMigrationOperation)
  private
    FTableName: string;
    FData: TArray<TArray<Variant>>;
    FColumns: TArray<string>;
  public
    constructor Create(const ATableName: string; const AColumns: TArray<string>; const AData: TArray<TArray<Variant>>);
    property TableName: string read FTableName;
    property Columns: TArray<string> read FColumns;
    property Data: TArray<TArray<Variant>> read FData;
  end;

  /// <summary>
  ///   Deletes the rows that match the given values (the inverse of a seed). A row
  ///   is matched by every column it names; a null value matches with IS NULL.
  /// </summary>
  TDeleteDataOperation = class(TMigrationOperation)
  private
    FTableName: string;
    FData: TArray<TArray<Variant>>;
    FColumns: TArray<string>;
  public
    constructor Create(const ATableName: string; const AColumns: TArray<string>; const AData: TArray<TArray<Variant>>);
    property TableName: string read FTableName;
    property Columns: TArray<string> read FColumns;
    property Data: TArray<TArray<Variant>> read FData;
  end;

  TSqlOperation = class(TMigrationOperation)
  private
    FSql: string;
  public
    constructor Create(const ASql: string);
    property Sql: string read FSql;
  end;

implementation

{ TMigrationOperation }

constructor TMigrationOperation.Create(AOperationType: TOperationType);
begin
  FOperationType := AOperationType;
end;

{ TColumnDefinition }

constructor TColumnDefinition.Create(const AName, AType: string);
begin
  Name := AName;
  ColumnType := AType;
  IsNullable := True; // Default
end;

{ TCreateTableOperation }

constructor TCreateTableOperation.Create(const AName: string);
begin
  inherited Create(otCreateTable);
  FName := AName;
  FColumns := TCollections.CreateList<TColumnDefinition>(True);
end;

destructor TCreateTableOperation.Destroy;
begin
  FColumns := nil;
  inherited;
end;

{ TDropTableOperation }

constructor TDropTableOperation.Create(const AName: string);
begin
  inherited Create(otDropTable);
  FName := AName;
end;

{ TAddColumnOperation }

constructor TAddColumnOperation.Create(const ATableName: string; AColumn: TColumnDefinition);
begin
  inherited Create(otAddColumn);
  FTableName := ATableName;
  FColumn := AColumn;
end;

destructor TAddColumnOperation.Destroy;
begin
  FColumn.Free;
  inherited;
end;

{ TDropColumnOperation }

constructor TDropColumnOperation.Create(const ATableName, AName: string);
begin
  inherited Create(otDropColumn);
  FTableName := ATableName;
  FName := AName;
end;

{ TAlterColumnOperation }

constructor TAlterColumnOperation.Create(const ATableName: string; AColumn: TColumnDefinition);
begin
  inherited Create(otAlterColumn);
  FTableName := ATableName;
  FColumn := AColumn;
end;

destructor TAlterColumnOperation.Destroy;
begin
  FColumn.Free;
  inherited;
end;

{ TAddForeignKeyOperation }

constructor TAddForeignKeyOperation.Create(const ATable, AName: string;
  const AColumns: TArray<string>; const ARefTable: string;
  const ARefColumns: TArray<string>);
begin
  inherited Create(otAddForeignKey);
  FTable := ATable;
  FName := AName;
  FColumns := AColumns;
  FReferencedTable := ARefTable;
  FReferencedColumns := ARefColumns;
end;

{ TDropForeignKeyOperation }

constructor TDropForeignKeyOperation.Create(const ATable, AName: string);
begin
  inherited Create(otDropForeignKey);
  FTable := ATable;
  FName := AName;
end;

{ TCreateIndexOperation }

constructor TCreateIndexOperation.Create(const ATable, AName: string;
  const AColumns: TArray<string>; AIsUnique: Boolean);
begin
  inherited Create(otCreateIndex);
  FTable := ATable;
  FName := AName;
  FColumns := AColumns;
  FIsUnique := AIsUnique;
end;

{ TDropIndexOperation }

constructor TDropIndexOperation.Create(const ATable, AName: string);
begin
  inherited Create(otDropIndex);
  FTable := ATable;
  FName := AName;
end;

{ TRenameTableOperation }

constructor TRenameTableOperation.Create(const AOldName, ANewName: string);
begin
  inherited Create(otRenameTable);
  FOldName := AOldName;
  FNewName := ANewName;
end;

{ TRenameColumnOperation }

constructor TRenameColumnOperation.Create(const ATableName, AOldName, ANewName: string);
begin
  inherited Create(otRenameColumn);
  FTableName := ATableName;
  FOldName := AOldName;
  FNewName := ANewName;
end;

{ TSeedDataOperation }

constructor TSeedDataOperation.Create(const ATableName: string; const AColumns: TArray<string>; const AData: TArray<TArray<Variant>>);
begin
  inherited Create(otSeedData);
  FTableName := ATableName;
  FColumns := AColumns;
  FData := AData;
end;

{ TDeleteDataOperation }

constructor TDeleteDataOperation.Create(const ATableName: string; const AColumns: TArray<string>; const AData: TArray<TArray<Variant>>);
begin
  inherited Create(otDeleteData);
  FTableName := ATableName;
  FColumns := AColumns;
  FData := AData;
end;

{ TSqlOperation }

constructor TSqlOperation.Create(const ASql: string);
begin
  inherited Create(otSql);
  FSql := ASql;
end;

end.

