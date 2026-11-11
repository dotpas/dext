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
unit Dext.Entity.Migrations.Extractor;

interface

uses
  Data.DB,
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  Dext.Entity.Context, // Add concrete TDbContext
  Dext.Entity.Core,
  Dext.Entity.Mapping,
  Dext.Entity.Attributes,
  Dext.Entity.Migrations.Model,
  Dext.Entity.Dialects,
  Dext.Types.Nullable,
  Dext.Core.Reflection;

type
  /// <summary>
  ///   Extracts a snapshot model representing the current state of a DbContext.
  /// </summary>
  TDbContextModelExtractor = class
  public
    class function Extract(AContext: IDbContext): TSnapshotModel;
  end;

implementation

{ TDbContextModelExtractor }

class function TDbContextModelExtractor.Extract(AContext: IDbContext): TSnapshotModel;
var
  Ctx: TDbContext; // Cast to concrete class to access ModelBuilder
  ModelBuilder: TModelBuilder;
  Map: TEntityMap;
  Table: TSnapshotTable;
  PropMap: TPropertyMap;
  Col: TSnapshotColumn;
  RType: TRttiType;
  RProp: TRttiProperty;
  Attr: TableAttribute;
  Maps: TArray<TEntityMap>; 
  RenamedAttr: RenamedFromAttribute;
  RField: TRttiField;
  PropType, Underlying: PTypeInfo;
  ValueField: TRttiField;
begin
  Result := TSnapshotModel.Create;
  
  if not (AContext is TDbContext) then
    Exit; // Should not happen
    
  Ctx := TDbContext(AContext);
  ModelBuilder := Ctx.ModelBuilder;
  
  // We need to iterate over all maps in ModelBuilder.
  // I will add `GetMaps` to TModelBuilder.
  Maps := ModelBuilder.GetMaps; 
  
  for Map in Maps do
  begin
    Table := TSnapshotTable.Create;
    Table.Name := Map.TableName;
    
    RType := TReflection.Context.GetType(Map.EntityType);
    
    // If TableName is empty, check Attribute
    if Table.Name = '' then
    begin
       Attr := RType.GetAttribute<TableAttribute>;
       if Attr <> nil then
         Table.Name := Attr.Name;
    end;

    // If still empty, derive from Class Name
    if Table.Name = '' then
    begin
      // Simple pluralization or just class name
      Table.Name := String(Map.EntityType.Name).Substring(1); // Remove 'T'
    end;
    
    // [RenamedFrom] on the class: the table was renamed
    RenamedAttr := RType.GetAttribute<RenamedFromAttribute>;
    if RenamedAttr <> nil then
      Table.RenamedFrom := RenamedAttr.OldName;

    // Iterate Properties
    for RProp in RType.GetProperties do
    begin
      // Skip non-mapped properties?
      // We need to check if it's mapped.
      // If Fluent Mapping exists, use it.
      // If Attributes exist, use them.
      // Default convention: Map all public read/write properties.
      
      if (RProp.Visibility < mvPublic) then Continue;
      
      // Check for [NotMapped] or Ignore()
      if Map.Properties.TryGetValue(RProp.Name, PropMap) then
      begin
        if PropMap.IsIgnored then Continue;
      end;
      
      // Create Column
      Col := TSnapshotColumn.Create;
      Col.Name := RProp.Name;
      
      // Apply Mapping Overrides
      if PropMap <> nil then
      begin
        if PropMap.ColumnName <> '' then Col.Name := PropMap.ColumnName;
        Col.IsPrimaryKey := PropMap.IsPK;
        Col.IsIdentity := PropMap.IsAutoInc;
        Col.IsNullable := not PropMap.IsRequired;
        Col.Length := PropMap.MaxLength;
        Col.Precision := PropMap.Precision;
        Col.Scale := PropMap.Scale;
      end;
      
      // Apply Attributes (if not overridden by Fluent)
      // Note: TEntityMap usually aggregates attributes during building, 
      // but if it doesn't, we check here.
      // Let's assume TEntityMap is the source of truth.
      
      // Determine the type the way EnsureCreated does: unwrap Nullable<T> and
      // Smart Properties (Prop<T> is a record around the value), and pass the
      // precision on to the dialect.
      PropType := RProp.PropertyType.Handle;
      if IsNullable(PropType) then
      begin
        Underlying := GetUnderlyingType(PropType);
        if Underlying <> nil then
          PropType := Underlying;
      end
      else if RProp.PropertyType.TypeKind = tkRecord then
      begin
        ValueField := RProp.PropertyType.GetField('FValue');
        if (ValueField <> nil) and
           (RProp.PropertyType.Name.Contains('Prop<') or
            (RProp.PropertyType.GetProperty('Value') <> nil)) then
          PropType := ValueField.FieldType.Handle;
      end;

      // EnsureCreated asks the dialect by the field type of the mapping, and
      // by the Delphi type only for an identity column or an unmapped type.
      // The two answers differ (Currency is DECIMAL(p,s) by field type, but
      // REAL on SQLite and MONEY on PostgreSQL by Delphi type), so the
      // snapshot must ask the same way or a migration builds another schema.
      if (PropMap <> nil) and (PropMap.DataType <> ftUnknown) and
         (not Col.IsIdentity) then
        Col.ColumnType := AContext.Dialect.GetColumnTypeForField(
          PropMap.DataType, False, Col.Precision, Col.Scale)
      else
        Col.ColumnType := AContext.Dialect.GetColumnType(PropType,
          Col.IsIdentity, Col.Precision, Col.Scale);

      // The size lives in Length/Precision, and the DDL appends it to the type.
      // A text column with a MaxLength is a bare VARCHAR; a type that already
      // carries its size ("VARCHAR(255)", "NUMERIC(18,2)") loses it when the
      // column has its own.
      if (Col.Length > 0) and
         (PropType.Kind in [tkString, tkUString, tkWString, tkChar, tkWChar]) then
      begin
        case AContext.Dialect.GetDialect of
          ddSQLServer: Col.ColumnType := 'NVARCHAR';
          ddOracle: Col.ColumnType := 'VARCHAR2';
        else
          Col.ColumnType := 'VARCHAR';
        end;
      end
      else if (Pos('(', Col.ColumnType) > 0) and
              ((Col.Length > 0) or (Col.Precision > 0)) then
        Col.ColumnType := Copy(Col.ColumnType, 1, Pos('(', Col.ColumnType) - 1);

      // [RenamedFrom] on the property, or on its backing field FName
      RenamedAttr := RProp.GetAttribute<RenamedFromAttribute>;
      if RenamedAttr = nil then
      begin
        RField := RType.GetField('F' + RProp.Name);
        if RField <> nil then
          RenamedAttr := RField.GetAttribute<RenamedFromAttribute>;
      end;
      if RenamedAttr <> nil then
        Col.RenamedFrom := RenamedAttr.OldName;
      
      Table.Columns.Add(Col);
    end;
    
    Result.Tables.Add(Table);
  end;
end;

end.

