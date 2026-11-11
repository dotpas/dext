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
unit Dext.Entity.Migrations.Differ;

interface

uses
  System.SysUtils,
  Dext.Collections.Base,
  Dext.Collections,
  Dext.Entity.Migrations.Model,
  Dext.Entity.Migrations.Operations;

type
  TModelDiffer = class
  public
    /// <summary>
    ///   Compares Current model with Previous model and returns a list of operations
    ///   to transform Previous into Current.
    /// </summary>
    class function Diff(Current, Previous: TSnapshotModel): IList<TMigrationOperation>;
  end;

implementation

{ TModelDiffer }

class function TModelDiffer.Diff(Current, Previous: TSnapshotModel): IList<TMigrationOperation>;
var
  Ops: IList<TMigrationOperation>;
  CurrTable, PrevTable: TSnapshotTable;
  CurrCol, PrevCol: TSnapshotColumn;
  CurrFK: TSnapshotForeignKey;
  CreateOp: TCreateTableOperation;
  PKs: IList<string>;
  C: TSnapshotColumn;
  StillExists: Boolean;
  T: TSnapshotTable;
  
  // Helper to convert Snapshot Column to Operation Column Definition
  function ToDef(C: TSnapshotColumn): TColumnDefinition;
  begin
    Result := TColumnDefinition.Create(C.Name, C.ColumnType);
    Result.Length := C.Length;
    Result.Precision := C.Precision;
    Result.Scale := C.Scale;
    Result.IsNullable := C.IsNullable;
    Result.IsPrimaryKey := C.IsPrimaryKey;
    Result.IsIdentity := C.IsIdentity;
    Result.DefaultValue := C.DefaultValue;
  end;
  
begin
  Ops := TCollections.CreateList<TMigrationOperation>(True);
  
  // 1. Check for New Tables
  if Current <> nil then
  begin
    for CurrTable in Current.Tables do
    begin
      PrevTable := nil;
      if (Previous <> nil) then
      begin
        PrevTable := Previous.FindTable(CurrTable.Name);
        
        // Check for Table Rename
        if (PrevTable = nil) and (CurrTable.RenamedFrom <> '') then
        begin
          PrevTable := Previous.FindTable(CurrTable.RenamedFrom);
          if PrevTable <> nil then
          begin
            // Verify the old table name is NOT used by another table in current model
            if (Current.FindTable(CurrTable.RenamedFrom) = nil) then
            begin
              Ops.Add(TRenameTableOperation.Create(CurrTable.RenamedFrom, CurrTable.Name));
              // Now we can continue diffing CurrTable against PrevTable as if they were the same entity
            end
            else
              PrevTable := nil; // Collision: Old name reused for a new table, treat as New Table
          end;
        end;
      end;
        
      if PrevTable = nil then
      begin
        // Table Added
        CreateOp := TCreateTableOperation.Create(CurrTable.Name);
        
        // Add Columns
        for CurrCol in CurrTable.Columns do
          CreateOp.Columns.Add(ToDef(CurrCol));
          
        // Add PKs (if not inline, but we usually put them inline or separate)
        // For simplicity, let's assume PKs are marked in columns for now, 
        // or we extract them.
        // TCreateTableOperation has a PrimaryKey array property.
        PKs := TCollections.CreateList<string>;
        try
          for CurrCol in CurrTable.Columns do
            if CurrCol.IsPrimaryKey then
              PKs.Add(CurrCol.Name);
          CreateOp.PrimaryKey := PKs.ToArray;
        finally
          PKs := nil;
        end;
        
        Ops.Add(CreateOp);
        
        // Add FKs (as separate operations usually, to avoid circular deps)
        for CurrFK in CurrTable.ForeignKeys do
        begin
          Ops.Add(TAddForeignKeyOperation.Create(
            CurrTable.Name, CurrFK.Name, CurrFK.Columns, 
            CurrFK.ReferencedTable, CurrFK.ReferencedColumns));
        end;
      end
      else
      begin
        // Table Exists - Check for Column Changes
        
        // A. New Columns
        for CurrCol in CurrTable.Columns do
        begin
          PrevCol := PrevTable.FindColumn(CurrCol.Name);
          
          // Check for Column Rename
          if (PrevCol = nil) and (CurrCol.RenamedFrom <> '') then
          begin
            PrevCol := PrevTable.FindColumn(CurrCol.RenamedFrom);
            if PrevCol <> nil then
            begin
               // Verify old name not used in current table
               if (CurrTable.FindColumn(CurrCol.RenamedFrom) = nil) then
               begin
                 Ops.Add(TRenameColumnOperation.Create(CurrTable.Name, CurrCol.RenamedFrom, CurrCol.Name));
               end
               else
                 PrevCol := nil;
            end;
          end;

          if PrevCol = nil then
          begin
            Ops.Add(TAddColumnOperation.Create(CurrTable.Name, ToDef(CurrCol)));
          end
          else
          begin
            // B. Changed Columns (or potentially changed after rename)
            if not CurrCol.SameDefinition(PrevCol) then
            begin
              Ops.Add(TAlterColumnOperation.Create(CurrTable.Name, ToDef(CurrCol)));
            end;
          end;
        end;
        
        // C. Dropped Columns
        for PrevCol in PrevTable.Columns do
        begin
          // Check if column was dropped (not renamed)
          StillExists := False;
          for C in CurrTable.Columns do
            if SameText(C.Name, PrevCol.Name) or SameText(C.RenamedFrom, PrevCol.Name) then
            begin
              StillExists := True;
              Break;
            end;

          if not StillExists then
          begin
            Ops.Add(TDropColumnOperation.Create(CurrTable.Name, PrevCol.Name));
          end;
        end;
        
        // D. FK Changes (Simplified: Add/Drop)
        // TODO: Implement FK diffing logic
      end;
    end;
  end;
  
  // 2. Check for Dropped Tables
  if Previous <> nil then
  begin
    for PrevTable in Previous.Tables do
    begin
      StillExists := False;
      if Current <> nil then
      begin
        for T in Current.Tables do
          if SameText(T.Name, PrevTable.Name) or SameText(T.RenamedFrom, PrevTable.Name) then
          begin
            StillExists := True;
            Break;
          end;
      end;

      if not StillExists then
      begin
        Ops.Add(TDropTableOperation.Create(PrevTable.Name));
      end;
    end;
  end;
  
  Result := Ops;
end;

end.

