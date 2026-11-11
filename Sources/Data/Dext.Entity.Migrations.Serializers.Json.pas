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
unit Dext.Entity.Migrations.Serializers.Json;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Collections.Base,
  Dext.Collections,
  Dext.Json,
  Dext.Json.Types,
  Dext.Entity.Migrations.Operations;

type
  TMigrationJsonSerializer = class
  private
    class function SerializeColumn(Column: TColumnDefinition): IDextJsonObject;
    class function DeserializeColumn(Obj: IDextJsonObject): TColumnDefinition;
    
    class function SerializeOperation(Op: TMigrationOperation): IDextJsonObject;
    class function DeserializeOperation(Obj: IDextJsonObject): TMigrationOperation;
  public
    class function Serialize(Operations: IList<TMigrationOperation>): string;
    class function Deserialize(const Json: string): IList<TMigrationOperation>;
  end;

implementation

uses
  System.TypInfo;

{ TMigrationJsonSerializer }

class function TMigrationJsonSerializer.Serialize(Operations: IList<TMigrationOperation>): string;
var
  Arr: IDextJsonArray;
  Op: TMigrationOperation;
  Provider: IDextJsonProvider;
begin
  Provider := TDextJson.Provider;
  Arr := Provider.CreateArray;
  
  for Op in Operations do
  begin
    Arr.Add(SerializeOperation(Op));
  end;
  
  Result := Arr.ToJson(True); // Indented
end;

class function TMigrationJsonSerializer.Deserialize(const Json: string): IList<TMigrationOperation>;
var
  Provider: IDextJsonProvider;
  Node: IDextJsonNode;
  Arr: IDextJsonArray;
  i: Integer;
  OpObj: IDextJsonObject;
begin
  Result := TCollections.CreateList<TMigrationOperation>(True);
  try
    Provider := TDextJson.Provider;
    Node := Provider.Parse(Json);
    
    if Node.GetNodeType <> jntArray then
      raise Exception.Create('Invalid migration JSON: Root must be an array of operations.');
      
    Arr := Node as IDextJsonArray;
    
    for i := 0 to Arr.GetCount - 1 do
    begin
      OpObj := Arr.GetObject(i);
      if OpObj <> nil then
        Result.Add(DeserializeOperation(OpObj));
    end;
  except
    Result := nil;
    raise;
  end;
end;

class function TMigrationJsonSerializer.SerializeColumn(Column: TColumnDefinition): IDextJsonObject;
var
  Provider: IDextJsonProvider;
begin
  Provider := TDextJson.Provider;
  Result := Provider.CreateObject;
  
  Result.SetString('name', Column.Name);
  Result.SetString('type', Column.ColumnType);
  
  if Column.Length > 0 then
    Result.SetInteger('length', Column.Length);
    
  if Column.Precision > 0 then
  begin
    Result.SetInteger('precision', Column.Precision);
    Result.SetInteger('scale', Column.Scale);
  end;
  
  if not Column.IsNullable then
    Result.SetBoolean('nullable', False);
    
  if Column.IsPrimaryKey then
    Result.SetBoolean('pk', True);
    
  if Column.IsIdentity then
    Result.SetBoolean('identity', True);
    
  if not Column.DefaultValue.IsEmpty then
    Result.SetString('default', Column.DefaultValue);
end;

class function TMigrationJsonSerializer.DeserializeColumn(Obj: IDextJsonObject): TColumnDefinition;
begin
  Result := TColumnDefinition.Create(
    Obj.GetString('name'),
    Obj.GetString('type')
  );
  
  if Obj.Contains('length') then
    Result.Length := Obj.GetInteger('length');
    
  if Obj.Contains('precision') then
  begin
    Result.Precision := Obj.GetInteger('precision');
    Result.Scale := Obj.GetInteger('scale');
  end;
  
  if Obj.Contains('nullable') then
    Result.IsNullable := Obj.GetBoolean('nullable')
  else
    Result.IsNullable := True; // Default
    
  if Obj.Contains('pk') then
    Result.IsPrimaryKey := Obj.GetBoolean('pk');
    
  if Obj.Contains('identity') then
    Result.IsIdentity := Obj.GetBoolean('identity');
    
  if Obj.Contains('default') then
    Result.DefaultValue := Obj.GetString('default');
end;

class function TMigrationJsonSerializer.SerializeOperation(Op: TMigrationOperation): IDextJsonObject;
var
  Provider: IDextJsonProvider;
  Cols: IDextJsonArray;
  Col: TColumnDefinition;
  Strs: IDextJsonArray;
  S: string;
begin
  Provider := TDextJson.Provider;
  Result := Provider.CreateObject;
  
  case Op.OperationType of
    otCreateTable:
      begin
        Result.SetString('op', 'create_table');
        Result.SetString('name', TCreateTableOperation(Op).Name);
        
        Cols := Provider.CreateArray;
        for Col in TCreateTableOperation(Op).Columns do
          Cols.Add(SerializeColumn(Col));
        Result.SetArray('columns', Cols);
        
        if Length(TCreateTableOperation(Op).PrimaryKey) > 0 then
        begin
          Strs := Provider.CreateArray;
          for S in TCreateTableOperation(Op).PrimaryKey do
            Strs.Add(S);
          Result.SetArray('pk', Strs);
        end;
      end;
      
    otDropTable:
      begin
        Result.SetString('op', 'drop_table');
        Result.SetString('name', TDropTableOperation(Op).Name);
      end;
      
    otAddColumn:
      begin
        Result.SetString('op', 'add_column');
        Result.SetString('table', TAddColumnOperation(Op).TableName);
        Result.SetObject('column', SerializeColumn(TAddColumnOperation(Op).Column));
      end;
      
    otDropColumn:
      begin
        Result.SetString('op', 'drop_column');
        Result.SetString('table', TDropColumnOperation(Op).TableName);
        Result.SetString('name', TDropColumnOperation(Op).Name);
      end;
      
    otAlterColumn:
      begin
        Result.SetString('op', 'alter_column');
        Result.SetString('table', TAlterColumnOperation(Op).TableName);
        Result.SetObject('column', SerializeColumn(TAlterColumnOperation(Op).Column));
      end;
      
    otAddForeignKey:
      begin
        Result.SetString('op', 'add_fk');
        Result.SetString('table', TAddForeignKeyOperation(Op).Table);
        Result.SetString('name', TAddForeignKeyOperation(Op).Name);
        Result.SetString('ref_table', TAddForeignKeyOperation(Op).ReferencedTable);
        
        Strs := Provider.CreateArray;
        for S in TAddForeignKeyOperation(Op).Columns do
          Strs.Add(S);
        Result.SetArray('columns', Strs);
        
        Strs := Provider.CreateArray;
        for S in TAddForeignKeyOperation(Op).ReferencedColumns do
          Strs.Add(S);
        Result.SetArray('ref_columns', Strs);
        
        if not TAddForeignKeyOperation(Op).OnDelete.IsEmpty then
          Result.SetString('on_delete', TAddForeignKeyOperation(Op).OnDelete);
          
        if not TAddForeignKeyOperation(Op).OnUpdate.IsEmpty then
          Result.SetString('on_update', TAddForeignKeyOperation(Op).OnUpdate);
      end;
      
    otDropForeignKey:
      begin
        Result.SetString('op', 'drop_fk');
        Result.SetString('table', TDropForeignKeyOperation(Op).Table);
        Result.SetString('name', TDropForeignKeyOperation(Op).Name);
      end;
      
    otCreateIndex:
      begin
        Result.SetString('op', 'create_index');
        Result.SetString('table', TCreateIndexOperation(Op).Table);
        Result.SetString('name', TCreateIndexOperation(Op).Name);
        
        Strs := Provider.CreateArray;
        for S in TCreateIndexOperation(Op).Columns do
          Strs.Add(S);
        Result.SetArray('columns', Strs);
        
        if TCreateIndexOperation(Op).IsUnique then
          Result.SetBoolean('unique', True);
      end;
      
    otDropIndex:
      begin
        Result.SetString('op', 'drop_index');
        Result.SetString('table', TDropIndexOperation(Op).Table);
        Result.SetString('name', TDropIndexOperation(Op).Name);
      end;
      
    otRenameTable:
      begin
        Result.SetString('op', 'rename_table');
        Result.SetString('old_name', TRenameTableOperation(Op).OldName);
        Result.SetString('new_name', TRenameTableOperation(Op).NewName);
      end;

    otRenameColumn:
      begin
        Result.SetString('op', 'rename_column');
        Result.SetString('table', TRenameColumnOperation(Op).TableName);
        Result.SetString('old_name', TRenameColumnOperation(Op).OldName);
        Result.SetString('new_name', TRenameColumnOperation(Op).NewName);
      end;

    otSql:
      begin
        Result.SetString('op', 'sql');
        Result.SetString('sql', TSqlOperation(Op).Sql);
      end;
  end;
end;

class function TMigrationJsonSerializer.DeserializeOperation(Obj: IDextJsonObject): TMigrationOperation;
var
  OpType: string;
  ColsArr, StrsArr: IDextJsonArray;
  i: Integer;
  Cols: TArray<string>;
  RefCols: TArray<string>;
  Op: TCreateTableOperation;
begin
  OpType := Obj.GetString('op');
  
  if OpType = 'create_table' then
  begin
    Op := TCreateTableOperation.Create(Obj.GetString('name'));
    
    ColsArr := Obj.GetArray('columns');
    if ColsArr <> nil then
    begin
      for i := 0 to ColsArr.GetCount - 1 do
        Op.Columns.Add(DeserializeColumn(ColsArr.GetObject(i)));
    end;
    
    StrsArr := Obj.GetArray('pk');
    if StrsArr <> nil then
    begin
      SetLength(Cols, StrsArr.GetCount);
      for i := 0 to StrsArr.GetCount - 1 do
        Cols[i] := StrsArr.GetString(i);
      Op.PrimaryKey := Cols;
    end;
    
    Result := Op;
  end
  else if OpType = 'drop_table' then
  begin
    Result := TDropTableOperation.Create(Obj.GetString('name'));
  end
  else if OpType = 'add_column' then
  begin
    Result := TAddColumnOperation.Create(
      Obj.GetString('table'),
      DeserializeColumn(Obj.GetObject('column'))
    );
  end
  else if OpType = 'drop_column' then
  begin
    Result := TDropColumnOperation.Create(
      Obj.GetString('table'),
      Obj.GetString('name')
    );
  end
  else if OpType = 'alter_column' then
  begin
    Result := TAlterColumnOperation.Create(
      Obj.GetString('table'),
      DeserializeColumn(Obj.GetObject('column'))
    );
  end
  else if OpType = 'add_fk' then
  begin
    StrsArr := Obj.GetArray('columns');
    SetLength(Cols, StrsArr.GetCount);
    for i := 0 to StrsArr.GetCount - 1 do
      Cols[i] := StrsArr.GetString(i);
      
    StrsArr := Obj.GetArray('ref_columns');
    SetLength(RefCols, StrsArr.GetCount);
    for i := 0 to StrsArr.GetCount - 1 do
      RefCols[i] := StrsArr.GetString(i);
      
    Result := TAddForeignKeyOperation.Create(
      Obj.GetString('table'),
      Obj.GetString('name'),
      Cols,
      Obj.GetString('ref_table'),
      RefCols
    );
    
    if Obj.Contains('on_delete') then
      TAddForeignKeyOperation(Result).OnDelete := Obj.GetString('on_delete');
      
    if Obj.Contains('on_update') then
      TAddForeignKeyOperation(Result).OnUpdate := Obj.GetString('on_update');
  end
  else if OpType = 'drop_fk' then
  begin
    Result := TDropForeignKeyOperation.Create(
      Obj.GetString('table'),
      Obj.GetString('name')
    );
  end
  else if OpType = 'create_index' then
  begin
    StrsArr := Obj.GetArray('columns');
    SetLength(Cols, StrsArr.GetCount);
    for i := 0 to StrsArr.GetCount - 1 do
      Cols[i] := StrsArr.GetString(i);
      
    Result := TCreateIndexOperation.Create(
      Obj.GetString('table'),
      Obj.GetString('name'),
      Cols,
      Obj.Contains('unique') and Obj.GetBoolean('unique')
    );
  end
  else if OpType = 'drop_index' then
  begin
    Result := TDropIndexOperation.Create(
      Obj.GetString('table'),
      Obj.GetString('name')
    );
  end
  else if OpType = 'rename_table' then
  begin
    Result := TRenameTableOperation.Create(
      Obj.GetString('old_name'),
      Obj.GetString('new_name')
    );
  end
  else if OpType = 'rename_column' then
  begin
    Result := TRenameColumnOperation.Create(
      Obj.GetString('table'),
      Obj.GetString('old_name'),
      Obj.GetString('new_name')
    );
  end
  else if OpType = 'sql' then
  begin
    Result := TSqlOperation.Create(Obj.GetString('sql'));
  end
  else
    raise Exception.Create('Unknown migration operation type: ' + OpType);
end;

end.

