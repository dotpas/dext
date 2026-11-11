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
unit Dext.Entity.Migrations.Model;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Collections.Base,
  Dext.Collections;

type
  /// <summary>
  ///   Represents a column definition within a database snapshot.
  /// </summary>
  TSnapshotColumn = class
  public
    Name: string;
    ColumnType: string;
    Length: Integer;
    Precision: Integer;
    Scale: Integer;
    IsNullable: Boolean;
    IsPrimaryKey: Boolean;
    IsIdentity: Boolean;
    DefaultValue: string;
    RenamedFrom: string;
    
    function Equals(Obj: TObject): Boolean; override;
    /// <summary>
    ///   Compares only the column definition (type, size, nullability, key,
    ///   identity and default). Name and RenamedFrom are left out: the first
    ///   is the identity the differ already matched, the second is a mapping
    ///   hint, not part of the schema.
    /// </summary>
    function SameDefinition(Other: TSnapshotColumn): Boolean;
    function Clone: TSnapshotColumn;
  end;

  /// <summary>
  ///   Represents a foreign key constraint within a database snapshot.
  /// </summary>
  TSnapshotForeignKey = class
  public
    Name: string;
    Columns: TArray<string>;
    ReferencedTable: string;
    ReferencedColumns: TArray<string>;
    OnDelete: string;
    OnUpdate: string;
    
    function Equals(Obj: TObject): Boolean; override;
  end;

  /// <summary>
  ///   Represents a table structure within a database snapshot.
  /// </summary>
  TSnapshotTable = class
  public
    Name: string;
    Columns: IList<TSnapshotColumn>;
    ForeignKeys: IList<TSnapshotForeignKey>;
    RenamedFrom: string;
    
    constructor Create;
    destructor Destroy; override;
    
    function FindColumn(const AName: string): TSnapshotColumn;
  end;

  /// <summary>
  ///   Represents the complete database schema snapshot at a specific point in time.
  /// </summary>
  TSnapshotModel = class
  public
    Tables: IList<TSnapshotTable>;
    
    constructor Create;
    destructor Destroy; override;
    
    function FindTable(const AName: string): TSnapshotTable;
  end;

implementation

{ TSnapshotColumn }

function TSnapshotColumn.Clone: TSnapshotColumn;
begin
  Result := TSnapshotColumn.Create;
  Result.Name := Name;
  Result.ColumnType := ColumnType;
  Result.Length := Length;
  Result.Precision := Precision;
  Result.Scale := Scale;
  Result.IsNullable := IsNullable;
  Result.IsPrimaryKey := IsPrimaryKey;
  Result.IsIdentity := IsIdentity;
  Result.DefaultValue := DefaultValue;
  Result.RenamedFrom := RenamedFrom;
end;

function TSnapshotColumn.Equals(Obj: TObject): Boolean;
var
  Other: TSnapshotColumn;
begin
  if Obj = Self then Exit(True);
  if not (Obj is TSnapshotColumn) then Exit(False);
  
  Other := TSnapshotColumn(Obj);
  
  // Compare structural properties
  Result := (Name = Other.Name) and
            (ColumnType = Other.ColumnType) and
            (Length = Other.Length) and
            (Precision = Other.Precision) and
            (Scale = Other.Scale) and
            (IsNullable = Other.IsNullable) and
            (IsPrimaryKey = Other.IsPrimaryKey) and
            (IsIdentity = Other.IsIdentity) and
            (DefaultValue = Other.DefaultValue) and
            (RenamedFrom = Other.RenamedFrom);
end;

function TSnapshotColumn.SameDefinition(Other: TSnapshotColumn): Boolean;
begin
  Result := (Other <> nil) and
            (ColumnType = Other.ColumnType) and
            (Length = Other.Length) and
            (Precision = Other.Precision) and
            (Scale = Other.Scale) and
            (IsNullable = Other.IsNullable) and
            (IsPrimaryKey = Other.IsPrimaryKey) and
            (IsIdentity = Other.IsIdentity) and
            (DefaultValue = Other.DefaultValue);
end;

{ TSnapshotForeignKey }

function TSnapshotForeignKey.Equals(Obj: TObject): Boolean;
var
  Other: TSnapshotForeignKey;
  i: Integer;
begin
  if Obj = Self then Exit(True);
  if not (Obj is TSnapshotForeignKey) then Exit(False);
  
  Other := TSnapshotForeignKey(Obj);
  
  if (Name <> Other.Name) or
     (ReferencedTable <> Other.ReferencedTable) or
     (OnDelete <> Other.OnDelete) or
     (OnUpdate <> Other.OnUpdate) then
    Exit(False);
    
  // Compare arrays
  if Length(Columns) <> Length(Other.Columns) then Exit(False);
  for i := 0 to High(Columns) do
    if Columns[i] <> Other.Columns[i] then Exit(False);
    
  if Length(ReferencedColumns) <> Length(Other.ReferencedColumns) then Exit(False);
  for i := 0 to High(ReferencedColumns) do
    if ReferencedColumns[i] <> Other.ReferencedColumns[i] then Exit(False);
    
  Result := True;
end;

{ TSnapshotTable }

constructor TSnapshotTable.Create;
begin
  Columns := TCollections.CreateList<TSnapshotColumn>(True);
  ForeignKeys := TCollections.CreateList<TSnapshotForeignKey>(True);
end;

destructor TSnapshotTable.Destroy;
begin
  Columns := nil;
  ForeignKeys := nil;
  inherited;
end;

function TSnapshotTable.FindColumn(const AName: string): TSnapshotColumn;
var
  Col: TSnapshotColumn;
begin
  for Col in Columns do
    if SameText(Col.Name, AName) then
      Exit(Col);
  Result := nil;
end;

{ TSnapshotModel }

constructor TSnapshotModel.Create;
begin
  Tables := TCollections.CreateList<TSnapshotTable>(True);
end;

destructor TSnapshotModel.Destroy;
begin
  Tables := nil;
  inherited;
end;

function TSnapshotModel.FindTable(const AName: string): TSnapshotTable;
var
  Tab: TSnapshotTable;
begin
  for Tab in Tables do
    if SameText(Tab.Name, AName) then
      Exit(Tab);
  Result := nil;
end;

end.

