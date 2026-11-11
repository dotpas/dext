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
unit Dext.Entity.Migrations.Builder;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Collections.Base,
  Dext.Collections,
  Dext.Entity.Migrations.Operations;

type
  // Forward declarations
  TSchemaBuilder = class;
  TTableBuilder = class;
  TColumnBuilder = class;

  /// <summary>
  ///   Fluent API for defining a column in a CreateTable operation.
  /// </summary>
  IColumnBuilder = interface
    ['{4A8D6C5B-1E2F-4A3B-9C8D-7E6F5A4B3C2D}']
    function NotNull: IColumnBuilder;
    function Nullable: IColumnBuilder;
    function PrimaryKey: IColumnBuilder;
    function Identity: IColumnBuilder;
    function Default(const AValue: string): IColumnBuilder;
    function Length(ALength: Integer): IColumnBuilder;
    function Precision(APrecision, AScale: Integer): IColumnBuilder;
  end;

  /// <summary>
  ///   Fluent API for defining a column in a CreateTable operation.
  /// </summary>
  TColumnBuilder = class(TInterfacedObject, IColumnBuilder)
  private
    FDef: TColumnDefinition;
  public
    constructor Create(ADef: TColumnDefinition);
    
    function NotNull: IColumnBuilder;
    function Nullable: IColumnBuilder;
    function PrimaryKey: IColumnBuilder;
    function Identity: IColumnBuilder;
    function Default(const AValue: string): IColumnBuilder;
    function Length(ALength: Integer): IColumnBuilder;
    function Precision(APrecision, AScale: Integer): IColumnBuilder;
  end;

  /// <summary>
  ///   Fluent API for defining a table structure.
  /// </summary>
  TTableBuilder = class
  private
    FOp: TCreateTableOperation;
  public
    constructor Create(AOp: TCreateTableOperation);
    
    function Column(const AName: string; const AType: string): IColumnBuilder; overload;
    function Column(const AName: string; const AType: string; ALength: Integer): IColumnBuilder; overload;
    function Column(const AName: string; const AType: string; APrecision, AScale: Integer): IColumnBuilder; overload;
    
    function PrimaryKey(const AColumns: array of string): TTableBuilder;
    function ForeignKey(const AName: string; const AColumn: string; const ARefTable, ARefColumn: string): TTableBuilder; overload;
    // TODO: Composite FKs
  end;

  /// <summary>
  ///   Main entry point for defining schema changes.
  /// </summary>
  TSchemaBuilder = class
  private
    FOperations: IList<TMigrationOperation>;
  public
    constructor Create;
    destructor Destroy; override;
    
    // Operations
    function CreateTable(const AName: string; const ABuildProc: TProc<TTableBuilder>): TSchemaBuilder;
    function DropTable(const AName: string): TSchemaBuilder;
    
    function AddColumn(const ATable, AName, AType: string; ALength: Integer = 0; AIsNullable: Boolean = True): TSchemaBuilder;
    function DropColumn(const ATable, AName: string): TSchemaBuilder;
    function AlterColumn(const ATable, AName, AType: string): TSchemaBuilder; // Simplified
    
    function AddForeignKey(const ATable, AName, AColumn, ARefTable, ARefColumn: string): TSchemaBuilder;
    function DropForeignKey(const ATable, AName: string): TSchemaBuilder;
    
    function CreateIndex(const ATable, AName: string; const AColumns: array of string; AUnique: Boolean = False): TSchemaBuilder;
    function DropIndex(const ATable, AName: string): TSchemaBuilder;
    function RenameTable(const AOldName, ANewName: string): TSchemaBuilder;
    function RenameColumn(const ATable, AOldName, ANewName: string): TSchemaBuilder;
    
    function Sql(const ASql: string): TSchemaBuilder;
    
    property Operations: IList<TMigrationOperation> read FOperations;
  end;

implementation

{ TColumnBuilder }

constructor TColumnBuilder.Create(ADef: TColumnDefinition);
begin
  FDef := ADef;
end;

function TColumnBuilder.Default(const AValue: string): IColumnBuilder;
begin
  FDef.DefaultValue := AValue;
  Result := Self;
end;

function TColumnBuilder.Identity: IColumnBuilder;
begin
  FDef.IsIdentity := True;
  Result := Self;
end;

function TColumnBuilder.Length(ALength: Integer): IColumnBuilder;
begin
  FDef.Length := ALength;
  Result := Self;
end;

function TColumnBuilder.NotNull: IColumnBuilder;
begin
  FDef.IsNullable := False;
  Result := Self;
end;

function TColumnBuilder.Nullable: IColumnBuilder;
begin
  FDef.IsNullable := True;
  Result := Self;
end;

function TColumnBuilder.Precision(APrecision, AScale: Integer): IColumnBuilder;
begin
  FDef.Precision := APrecision;
  FDef.Scale := AScale;
  Result := Self;
end;

function TColumnBuilder.PrimaryKey: IColumnBuilder;
begin
  FDef.IsPrimaryKey := True;
  Result := Self;
end;

{ TTableBuilder }

constructor TTableBuilder.Create(AOp: TCreateTableOperation);
begin
  FOp := AOp;
end;

function TTableBuilder.Column(const AName, AType: string): IColumnBuilder;
var
  Def: TColumnDefinition;
begin
  Def := TColumnDefinition.Create(AName, AType);
  FOp.Columns.Add(Def);
  Result := TColumnBuilder.Create(Def);
end;

function TTableBuilder.Column(const AName, AType: string; ALength: Integer): IColumnBuilder;
begin
  Result := Column(AName, AType).Length(ALength);
end;

function TTableBuilder.Column(const AName, AType: string; APrecision, AScale: Integer): IColumnBuilder;
begin
  Result := Column(AName, AType).Precision(APrecision, AScale);
end;

function TTableBuilder.ForeignKey(const AName, AColumn, ARefTable,
  ARefColumn: string): TTableBuilder;
begin
  // Note: CreateTableOperation doesn't hold FKs directly in this model yet,
  // usually FKs are added as separate operations or inline constraints.
  // For simplicity, let's assume we add a separate AddForeignKeyOperation to the schema builder?
  // But TTableBuilder is scoped to CreateTableOperation.
  // We should add FK definition to CreateTableOperation or allow it to register a side-effect.
  // For now, let's ignore or store it in CreateTableOperation if we update it to support inline FKs.
  
  // Let's update TCreateTableOperation later to support inline constraints.
  // For now, this is a placeholder.
  Result := Self;
end;

function TTableBuilder.PrimaryKey(const AColumns: array of string): TTableBuilder;
var
  Arr: TArray<string>;
  i: Integer;
begin
  SetLength(Arr, Length(AColumns));
  for i := 0 to High(AColumns) do
    Arr[i] := AColumns[i];
  FOp.PrimaryKey := Arr;
  Result := Self;
end;

{ TSchemaBuilder }

constructor TSchemaBuilder.Create;
begin
  FOperations := TCollections.CreateList<TMigrationOperation>(True);
end;

destructor TSchemaBuilder.Destroy;
begin
  inherited;
end;

function TSchemaBuilder.AddColumn(const ATable, AName, AType: string;
  ALength: Integer; AIsNullable: Boolean): TSchemaBuilder;
var
  Col: TColumnDefinition;
begin
  Col := TColumnDefinition.Create(AName, AType);
  Col.Length := ALength;
  Col.IsNullable := AIsNullable;
  FOperations.Add(TAddColumnOperation.Create(ATable, Col));
  Result := Self;
end;

function TSchemaBuilder.AddForeignKey(const ATable, AName, AColumn, ARefTable,
  ARefColumn: string): TSchemaBuilder;
begin
  FOperations.Add(TAddForeignKeyOperation.Create(ATable, AName, [AColumn], ARefTable, [ARefColumn]));
  Result := Self;
end;

function TSchemaBuilder.AlterColumn(const ATable, AName, AType: string): TSchemaBuilder;
var
  Col: TColumnDefinition;
begin
  Col := TColumnDefinition.Create(AName, AType);
  FOperations.Add(TAlterColumnOperation.Create(ATable, Col));
  Result := Self;
end;

function TSchemaBuilder.CreateIndex(const ATable, AName: string;
  const AColumns: array of string; AUnique: Boolean): TSchemaBuilder;
var
  Arr: TArray<string>;
  i: Integer;
begin
  SetLength(Arr, Length(AColumns));
  for i := 0 to High(AColumns) do
    Arr[i] := AColumns[i];
    
  FOperations.Add(TCreateIndexOperation.Create(ATable, AName, Arr, AUnique));
  Result := Self;
end;

function TSchemaBuilder.CreateTable(const AName: string;
  const ABuildProc: TProc<TTableBuilder>): TSchemaBuilder;
var
  Op: TCreateTableOperation;
  Builder: TTableBuilder;
begin
  Op := TCreateTableOperation.Create(AName);
  Builder := TTableBuilder.Create(Op);
  try
    ABuildProc(Builder);
  finally
    Builder.Free;
  end;
  FOperations.Add(Op);
  Result := Self;
end;

function TSchemaBuilder.DropColumn(const ATable, AName: string): TSchemaBuilder;
begin
  FOperations.Add(TDropColumnOperation.Create(ATable, AName));
  Result := Self;
end;

function TSchemaBuilder.DropForeignKey(const ATable, AName: string): TSchemaBuilder;
begin
  FOperations.Add(TDropForeignKeyOperation.Create(ATable, AName));
  Result := Self;
end;

function TSchemaBuilder.DropIndex(const ATable, AName: string): TSchemaBuilder;
begin
  FOperations.Add(TDropIndexOperation.Create(ATable, AName));
  Result := Self;
end;

function TSchemaBuilder.RenameTable(const AOldName, ANewName: string): TSchemaBuilder;
begin
  FOperations.Add(TRenameTableOperation.Create(AOldName, ANewName));
  Result := Self;
end;

function TSchemaBuilder.RenameColumn(const ATable, AOldName, ANewName: string): TSchemaBuilder;
begin
  FOperations.Add(TRenameColumnOperation.Create(ATable, AOldName, ANewName));
  Result := Self;
end;

function TSchemaBuilder.DropTable(const AName: string): TSchemaBuilder;
begin
  FOperations.Add(TDropTableOperation.Create(AName));
  Result := Self;
end;

function TSchemaBuilder.Sql(const ASql: string): TSchemaBuilder;
begin
  FOperations.Add(TSqlOperation.Create(ASql));
  Result := Self;
end;

end.

