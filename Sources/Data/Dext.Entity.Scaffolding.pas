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
unit Dext.Entity.Scaffolding;

interface

uses
  System.SysUtils,
  System.Character,
  System.Classes,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Collections,
  Dext.Entity.Drivers.Interfaces,
  Dext.Utils;

type
  /// <summary>
  ///   Metadata representing a database table column.
  /// </summary>
  TMetaColumn = record
    Name: string;
    DataType: string; // SQL Type
    Length: Integer;
    Precision: Integer;
    Scale: Integer;
    IsNullable: Boolean;
    IsPrimaryKey: Boolean;
    IsAutoInc: Boolean;
    IsArray: Boolean; // Firebird array columns (e.g. VARCHAR[1:5]) - unsupported by standard SELECT
  end;

  /// <summary>
  ///   Metadata representing a database foreign key constraint.
  /// </summary>
  TMetaForeignKey = record
    Name: string;
    ColumnName: string;
    ReferencedTable: string;
    ReferencedColumn: string;
    OnDelete: string; // CASCADE, SET NULL, etc.
    OnUpdate: string;
  end;

  /// <summary>
  ///   Metadata representing a database table.
  /// </summary>
  TMetaTable = record
    Name: string;
    Columns: TArray<TMetaColumn>;
    ForeignKeys: TArray<TMetaForeignKey>;
  end;

  /// <summary>
  ///   Interface for database schema extraction providers.
  /// </summary>
  ISchemaProvider = interface
    ['{A1B2C3D4-E5F6-7890-1234-567890ABCDEF}']
    function GetTables: TArray<string>;
    function GetTableMetadata(const ATableName: string): TMetaTable;
  end;

  /// <summary>
  ///   Defines the style of ORM mapping to generate (attributes or fluent).
  /// </summary>
  TMappingStyle = (msAttributes, msFluent);
  /// <summary>
  ///   Defines the style of generated properties (POCO or smart types).
  /// </summary>
  TPropertyStyle = (psPOCO, psSmart);

  /// <summary>
  ///   Interface for generating entity code from database metadata.
  /// </summary>
  IEntityGenerator = interface
    ['{B1C2D3E4-F5A6-7890-1234-567890ABCDEF}']
    function GenerateUnit(const AUnitName: string; const ATables: TArray<TMetaTable>; 
      AMappingStyle: TMappingStyle = msAttributes;
      APropertyStyle: TPropertyStyle = psPOCO;
      AGenerateMetadata: Boolean = True): string;
  end;

  // FireDAC Implementation
  /// <summary>
  ///   FireDAC implementation of the schema provider for extracting database metadata.
  /// </summary>
  TFireDACSchemaProvider = class(TInterfacedObject, ISchemaProvider)
  private
    FConnection: IDbConnection;
    FMetaQuery: TFDMetaInfoQuery;
    FCache: Dext.Collections.Dict.IDictionary<string, TMetaTable>;
    FIsCached: Boolean;
    procedure EnsureCache;
    function GetMetaQuery: TFDMetaInfoQuery;
    function ExtractTableMetadataInternal(const ATableName: string): TMetaTable;
  public
    constructor Create(AConnection: IDbConnection);
    destructor Destroy; override;
    function GetTables: TArray<string>;
    function GetTableMetadata(const ATableName: string): TMetaTable;
  end;

  // Delphi Generator Implementation
  /// <summary>
  ///   Generator that produces Delphi entity classes from database metadata.
  /// </summary>
  TDelphiEntityGenerator = class(TInterfacedObject, IEntityGenerator)
  private
    function CleanName(const AName: string): string;
    function EscapeIdentifier(const AIdentifier: string): string;
    function IsKeyword(const AName: string): Boolean;
    function CleanMappingName(const AName: string): string;
  public
    function SQLTypeToDelphiType(const ASQLType: string; APrecision: Integer = 0; AScale: Integer = 0; APropertyStyle: TPropertyStyle = psPOCO): string;
    function GenerateUnit(const AUnitName: string; const ATables: TArray<TMetaTable>; 
      AMappingStyle: TMappingStyle = msAttributes;
      APropertyStyle: TPropertyStyle = psPOCO;
      AGenerateMetadata: Boolean = True): string;
  end;

implementation

uses
  Data.DB,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Intf,
  FireDAC.DApt,
  System.Diagnostics,
  System.StrUtils,
  Dext.Core.Reflection,
  Dext.Entity.Context,
  Dext.Entity.Drivers.FireDAC,
  Dext.Types.Lazy,
  Dext.Types.Nullable;

{ TFireDACSchemaProvider }

constructor TFireDACSchemaProvider.Create(AConnection: IDbConnection);
begin
  inherited Create;
  FConnection := AConnection;
  FCache := TCollections.CreateDictionary<string, TMetaTable>;
  FIsCached := False;
end;

destructor TFireDACSchemaProvider.Destroy;
begin
  FMetaQuery.Free;
  FCache := nil;
  inherited;
end;

function TFireDACSchemaProvider.GetMetaQuery: TFDMetaInfoQuery;
begin
  if FMetaQuery = nil then
  begin
    if not (FConnection is TFireDACConnection) then
      raise Exception.Create('Connection is not a FireDAC connection');
      
    FMetaQuery := TFDMetaInfoQuery.Create(nil);
    FMetaQuery.Connection := TFireDACConnection(FConnection).Connection;
  end;
  Result := FMetaQuery;
end;

function TFireDACSchemaProvider.GetTables: TArray<string>;
var
  FDConn: TFDConnection;
  List: TStringList;
  LCatalog, LSchema: string;
  i: Integer;
begin
  if not (FConnection is TFireDACConnection) then
    raise Exception.Create('Connection is not a FireDAC connection');

  FDConn := TFireDACConnection(FConnection).Connection;
  List := TStringList.Create;
  try
    LCatalog := FDConn.Params.Values['Database'];
    LSchema := FDConn.Params.Values['MetaCurSchema'];
    if LSchema = '' then LSchema := FDConn.Params.Values['Schema'];
    if LSchema = '' then LSchema := FDConn.Params.Values['MetaDefSchema'];

    if (SameText(FDConn.DriverName, 'Ora') or SameText(FDConn.DriverName, 'Oracle')) and (LSchema <> '') then
      LSchema := UpperCase(LSchema);

    if SameText(FDConn.DriverName, 'SQLite') then
    begin
       LCatalog := '';
       LSchema := '';
    end;
      
    FDConn.GetTableNames(LCatalog, LSchema, '', List, [osMy, osOther], [tkTable, tkView], LSchema = '');
    
    for i := List.Count - 1 downto 0 do
    begin
       if List[i].StartsWith('pg_catalog.', True) or 
          List[i].StartsWith('information_schema.', True) or
          List[i].StartsWith('sys.', True) or
          List[i].StartsWith('system.', True) or
          List[i].StartsWith('ctxsys.', True) or
          List[i].StartsWith('mdsys.', True) or
          List[i].StartsWith('xdb.', True) or
          List[i].StartsWith('outln.', True) or
          List[i].StartsWith('dbsnmp.', True) or
          List[i].StartsWith('appqossys.', True) or
          List[i].StartsWith('gsmadmin_internal.', True) or
          List[i].StartsWith('audsys.', True) then
          List.Delete(i);
    end;
    Result := List.ToStringArray;
  finally
    List.Free;
  end;
end;

function TFireDACSchemaProvider.GetTableMetadata(const ATableName: string): TMetaTable;
begin
  EnsureCache;
  if not FCache.TryGetValue(ATableName.Trim, Result) then
    Result := ExtractTableMetadataInternal(ATableName);
end;

procedure TFireDACSchemaProvider.EnsureCache;
var
  LTable: TMetaTable;
  LCol: TMetaColumn;
  LFK: TMetaForeignKey;
  LTableName: string;
  LDriver: string;
  LSchema: string;
  SWTotal: TStopwatch;
  TableList: TArray<string>;
  FDConn: TFDConnection;
  Qry: TFDQuery;
  LFullTableName, LColName, LTrimmedName, TName: string;
  ExistingFK: TMetaForeignKey;
  i: Integer;
  LLookupName: string;
  LFound: Boolean;
begin
  if FIsCached then Exit;
  FIsCached := True;

  if FCache = nil then
    FCache := TCollections.CreateDictionaryIgnoreCase<string, TMetaTable>;

  FDConn := TFireDACConnection(FConnection).Connection;
  LDriver := FDConn.DriverName;
  
  LSchema := FDConn.Params.Values['MetaCurSchema'];
  if LSchema = '' then LSchema := FDConn.Params.Values['Schema'];
  if LSchema = '' then LSchema := FDConn.Params.Values['MetaDefSchema'];

  if Assigned(FConnection.OnLog) then
    FConnection.OnLog('Starting bulk metadata extraction for schema: ' + LSchema + ' (Driver: ' + LDriver + ')');

  SWTotal := TStopwatch.StartNew;
  TableList := GetTables;

  if SameText(LDriver, 'PG') then
  begin
    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := FDConn;
      Qry.SQL.Text := 
        'SELECT table_name, column_name, data_type, character_maximum_length, ' +
        '       numeric_precision, numeric_scale, is_nullable, column_default, ' +
        '       is_identity ' +
        'FROM information_schema.columns ' +
        'WHERE table_schema = :schema ' +
        'ORDER BY table_name, ordinal_position';
      Qry.ParamByName('schema').AsString := LSchema;
      Qry.Open;
      
      while not Qry.Eof do
      begin
        LTableName := Qry.FieldByName('table_name').AsString;
        LFullTableName := LTableName;

        if not (FCache.TryGetValue(LFullTableName, LTable)) then
        begin
          LTable.Name := LFullTableName;
          LTable.Columns := [];
          LTable.ForeignKeys := [];
        end;

        LCol.Name := Qry.FieldByName('column_name').AsString;
        LCol.DataType := Qry.FieldByName('data_type').AsString;
        LCol.Length := Qry.FieldByName('character_maximum_length').AsInteger;
        LCol.Precision := Qry.FieldByName('numeric_precision').AsInteger;
        LCol.Scale := Qry.FieldByName('numeric_scale').AsInteger;
        LCol.IsNullable := SameText(Qry.FieldByName('is_nullable').AsString, 'YES');
        LCol.IsPrimaryKey := False;
        // SERIAL columns default to nextval(...); GENERATED AS IDENTITY
        // columns have no default and are flagged by is_identity.
        LCol.IsAutoInc := Qry.FieldByName('column_default').AsString.Contains('nextval') or
          SameText(Qry.FieldByName('is_identity').AsString, 'YES');

        LTable.Columns := LTable.Columns + [LCol];
        FCache.AddOrSetValue(LFullTableName, LTable);
        Qry.Next;
      end;
      Qry.Close;

      Qry.SQL.Text := 
        'SELECT rel.relname AS table_name, att.attname AS column_name ' +
        'FROM pg_index idx ' +
        'JOIN pg_class rel ON rel.oid = idx.indrelid ' +
        'JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = ANY(idx.indkey) ' +
        'JOIN pg_namespace ns ON ns.oid = rel.relnamespace ' +
        'WHERE ns.nspname = :schema AND idx.indisprimary';
      Qry.ParamByName('schema').AsString := LSchema;
      Qry.Open;
      while not Qry.Eof do
      begin
        LTableName := Qry.FieldByName('table_name').AsString;
        LFullTableName := LTableName;

        LColName := Qry.FieldByName('column_name').AsString;
        LTable := Default(TMetaTable);
        if (FCache.TryGetValue(LFullTableName, LTable)) then
        begin
          for i := 0 to High(LTable.Columns) do
            if SameText(LTable.Columns[i].Name, LColName) then
            begin
              LTable.Columns[i].IsPrimaryKey := True;
              FCache.AddOrSetValue(LFullTableName, LTable);
              Break;
            end;
        end;
        Qry.Next;
      end;
      Qry.Close;

      Qry.SQL.Text := 
        'SELECT con.conname AS constraint_name, rel.relname AS table_name, att.attname AS column_name, ' +
        '       frel.relname AS foreign_table_name, fatt.attname AS foreign_column_name ' +
        'FROM pg_constraint con ' +
        'JOIN pg_class rel ON rel.oid = con.conrelid ' +
        'JOIN pg_class frel ON frel.oid = con.confrelid ' +
        'JOIN pg_attribute att ON att.attrelid = rel.oid AND att.attnum = ANY(con.conkey) ' +
        'JOIN pg_attribute fatt ON fatt.attrelid = frel.oid AND fatt.attnum = ANY(con.confkey) ' +
        'JOIN pg_namespace ns ON ns.oid = rel.relnamespace ' +
        'WHERE ns.nspname = :schema AND con.contype = ''f''';
      Qry.ParamByName('schema').AsString := LSchema;
      Qry.Open;
      while not Qry.Eof do
      begin
        LTableName := Qry.FieldByName('table_name').AsString;
        LFullTableName := LTableName;

        LTable := Default(TMetaTable);
        if (FCache.TryGetValue(LFullTableName, LTable)) then
        begin
          LFK := Default(TMetaForeignKey);
          LFK.Name := Qry.FieldByName('constraint_name').AsString;
          LFK.ColumnName := Qry.FieldByName('column_name').AsString;
          LFK.ReferencedTable := Qry.FieldByName('foreign_table_name').AsString;
          LFK.ReferencedColumn := Qry.FieldByName('foreign_column_name').AsString;
          LTable.ForeignKeys := LTable.ForeignKeys + [LFK];
          FCache.AddOrSetValue(LFullTableName, LTable);
        end;
        Qry.Next;
      end;
    finally
      Qry.Free;
    end;
  end
  else if SameText(LDriver, 'FB') then
  begin
    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := FDConn;
      // PASSO 1: Carrega colunas e PKs de cada tabela via ExtractTableMetadataInternal.
      // As FKs carregadas aqui serão descartadas em seguida para evitar duplicação
      // com a query global abaixo, que é a fonte definitiva para o Firebird.
      for TName in TableList do
      begin
         LTrimmedName := TName.Trim;
         if not FCache.TryGetValue(LTrimmedName, LTable) then
         begin
            LTable := ExtractTableMetadataInternal(TName);
            LTable.Name := LTrimmedName;
            FCache.AddOrSetValue(LTrimmedName, LTable);
         end;
      end;

      // PASSO 1b: Zerar as FKs carregadas individualmente. A query global abaixo
      // será a única fonte de verdade para FKs no Firebird, evitando duplicação.
      for TName in TableList do
      begin
        LTrimmedName := TName.Trim;
        if FCache.TryGetValue(LTrimmedName, LTable) then
        begin
          LTable.ForeignKeys := [];
          FCache.AddOrSetValue(LTrimmedName, LTable);
        end;
      end;

      // PASSO 2: Query global para carregar todas as FKs do banco de uma vez.
      Qry.SQL.Text :=
        'SELECT RC.RDB$CONSTRAINT_NAME AS constraint_name, ' +
        '       TRIM(RC.RDB$RELATION_NAME) AS table_name, ' +
        '       TRIM(ISE.RDB$FIELD_NAME) AS column_name, ' +
        '       TRIM(REF_RC.RDB$RELATION_NAME) AS foreign_table_name, ' +
        '       TRIM(REF_ISE.RDB$FIELD_NAME) AS foreign_column_name ' +
        'FROM RDB$RELATION_CONSTRAINTS RC ' +
        'JOIN RDB$REF_CONSTRAINTS REFC ON RC.RDB$CONSTRAINT_NAME = REFC.RDB$CONSTRAINT_NAME ' +
        'JOIN RDB$INDEX_SEGMENTS ISE ON RC.RDB$INDEX_NAME = ISE.RDB$INDEX_NAME ' +
        'JOIN RDB$RELATION_CONSTRAINTS REF_RC ON REFC.RDB$CONST_NAME_UQ = REF_RC.RDB$CONSTRAINT_NAME ' +
        'JOIN RDB$INDEX_SEGMENTS REF_ISE ON REF_RC.RDB$INDEX_NAME = REF_ISE.RDB$INDEX_NAME AND ISE.RDB$FIELD_POSITION = REF_ISE.RDB$FIELD_POSITION ' +
        'WHERE RC.RDB$CONSTRAINT_TYPE = ''FOREIGN KEY'' ' +
        'ORDER BY RC.RDB$RELATION_NAME, RC.RDB$CONSTRAINT_NAME, ISE.RDB$FIELD_POSITION';

      try
        Qry.Open;
        while not Qry.Eof do
        begin
          LTableName := Qry.FieldByName('table_name').AsString.Trim;
          LLookupName := LTableName;
          LTable := Default(TMetaTable);
          if not FCache.TryGetValue(LLookupName, LTable) then
          begin
            LLookupName := LTableName.Replace('"', '');
            FCache.TryGetValue(LLookupName, LTable);
          end;

          if LTable.Name <> '' then
          begin
            LFK := Default(TMetaForeignKey);
            LFK.Name := Qry.FieldByName('constraint_name').AsString.Trim;
            LFK.ColumnName := Qry.FieldByName('column_name').AsString.Trim;
            LFK.ReferencedTable := Qry.FieldByName('foreign_table_name').AsString.Trim;
            LFK.ReferencedColumn := Qry.FieldByName('foreign_column_name').AsString.Trim;

            // Validação básica + deduplicação para evitar FKs duplicadas
            // (o Firebird pode retornar múltiplas linhas para a mesma FK em índices compostos)
            if (LFK.ColumnName <> '') and (LFK.ReferencedTable <> '') then
            begin
              LFound := False;
              for ExistingFK in LTable.ForeignKeys do
                // Group by Constraint Name to avoid duplicates in composite keys
                if SameText(ExistingFK.Name, LFK.Name) or
                   (SameText(ExistingFK.ColumnName, LFK.ColumnName) and
                    SameText(ExistingFK.ReferencedTable, LFK.ReferencedTable)) then
                begin
                  LFound := True;
                  Break;
                end;

              if not LFound then
              begin
                LTable.ForeignKeys := LTable.ForeignKeys + [LFK];
                FCache.AddOrSetValue(LTableName, LTable);
                if LLookupName <> LTableName then
                  FCache.AddOrSetValue(LLookupName, LTable);
              end;
            end;
          end;
          Qry.Next;
        end;
      except
      end;
    finally
      Qry.Free;
    end;
  end
  else
  begin
    for TName in TableList do
    begin
      LTrimmedName := TName.Trim;
      if not FCache.TryGetValue(LTrimmedName, LTable) then
      begin
        LTable := ExtractTableMetadataInternal(TName);
        FCache.AddOrSetValue(LTrimmedName, LTable);
      end;
    end;
  end;

  if Assigned(FConnection.OnLog) then
    FConnection.OnLog(Format('Bulk metadata extraction completed in %d ms for %d tables', 
      [SWTotal.ElapsedMilliseconds, FCache.Count]));
end;

function TFireDACSchemaProvider.ExtractTableMetadataInternal(const ATableName: string): TMetaTable;
var
  Meta: TFDMetaInfoQuery;
  LCol: TMetaColumn;
  LFK: TMetaForeignKey;
  LDotPos, i, FkIndex: Integer;
  FDConn: TFDConnection;
  LSchema, LColName, LArrColName: string;
  ArrQry, Qry: TFDQuery;
  ExistingFK: TMetaForeignKey;
  LActualSchema, LActualTable: string;
  LFound: Boolean;
  LPkCount: Integer;
  LRowIdName: string;
begin
  FDConn := TFireDACConnection(FConnection).Connection;
  LSchema := FDConn.Params.Values['MetaCurSchema'];
  if LSchema = '' then LSchema := FDConn.Params.Values['Schema'];
  if LSchema = '' then LSchema := FDConn.Params.Values['MetaDefSchema'];

  Result.Name := ATableName;
  Result.Columns := [];
  Result.ForeignKeys := [];

  LActualSchema := LSchema;
  LActualTable := ATableName;
  LDotPos := ATableName.IndexOf('.');
  if LDotPos >= 0 then
  begin
    LActualSchema := ATableName.Substring(0, LDotPos);
    LActualTable := ATableName.Substring(LDotPos + 1);
  end;
  
  Meta := GetMetaQuery;
  try
    Meta.Close;
    Meta.MetaInfoKind := mkTableFields;
    Meta.CatalogName := '';
    Meta.SchemaName := LActualSchema;
    Meta.ObjectName := LActualTable;
    Meta.Open;
    while not Meta.Eof do
    begin
      LCol.Name := Meta.FieldByName('COLUMN_NAME').AsString;
      LCol.DataType := Meta.FieldByName('COLUMN_TYPENAME').AsString;
      LCol.Length := Meta.FieldByName('COLUMN_LENGTH').AsInteger;
      LCol.Precision := Meta.FieldByName('COLUMN_PRECISION').AsInteger;
      LCol.Scale := Meta.FieldByName('COLUMN_SCALE').AsInteger;
      LCol.IsNullable := True;
      if Meta.FindField('IS_NULLABLE') <> nil then LCol.IsNullable := Meta.FieldByName('IS_NULLABLE').AsString = 'YES'
      else if Meta.FindField('NULLABLE') <> nil then LCol.IsNullable := Meta.FieldByName('NULLABLE').AsInteger = 1;
      LCol.IsPrimaryKey := False;
      if Meta.FindField('PRIMARY_KEY') <> nil then LCol.IsPrimaryKey := Meta.FieldByName('PRIMARY_KEY').AsBoolean;
      LCol.IsAutoInc := False;
      LCol.IsArray := False;
      Result.Columns := Result.Columns + [LCol];
      Meta.Next;
    end;

    // Detect Firebird array columns (RDB$DIMENSIONS > 0)
    // These columns cannot be selected as scalar values and must be excluded from entities
    if SameText(FDConn.DriverName, 'FB') then
    begin
      ArrQry := TFDQuery.Create(nil);
      try
        ArrQry.Connection := FDConn;
        ArrQry.SQL.Text :=
          'SELECT TRIM(rf.RDB$FIELD_NAME) AS FIELD_NAME ' +
          'FROM RDB$RELATION_FIELDS rf ' +
          'JOIN RDB$FIELDS f ON rf.RDB$FIELD_SOURCE = f.RDB$FIELD_NAME ' +
          'WHERE TRIM(rf.RDB$RELATION_NAME) = :tablename AND COALESCE(f.RDB$DIMENSIONS, 0) > 0';
        ArrQry.ParamByName('tablename').AsString := LActualTable;
        ArrQry.Open;
        while not ArrQry.Eof do
        begin
          LArrColName := ArrQry.FieldByName('FIELD_NAME').AsString.Trim;
          for i := 0 to High(Result.Columns) do
            if SameText(Result.Columns[i].Name, LArrColName) then
            begin
              Result.Columns[i].IsArray := True;
              if Assigned(FConnection.OnLog) then
                FConnection.OnLog(Format('  [Scaffolding] Skipping array column: %s.%s', [LActualTable, LArrColName]));
              Break;
            end;
          ArrQry.Next;
        end;
      finally
        ArrQry.Free;
      end;
    end;
    
    Meta.Close;
    Meta.MetaInfoKind := mkPrimaryKeyFields;
    Meta.CatalogName := '';
    Meta.SchemaName := LActualSchema;
    Meta.BaseObjectName := LActualTable;
    Meta.ObjectName := '';
    try
      Meta.Open;
      while not Meta.Eof do
      begin
        LColName := Meta.FieldByName('COLUMN_NAME').AsString;
        for i := 0 to High(Result.Columns) do
          if SameText(Result.Columns[i].Name, LColName) then
          begin
            Result.Columns[i].IsPrimaryKey := True;
            Break;
          end;
        Meta.Next;
      end;
    except
    end;

    if SameText(FDConn.DriverName, 'SQLite') then
    begin
      Qry := TFDQuery.Create(nil);
      try
        Qry.Connection := FDConn;
        Qry.SQL.Text := 'PRAGMA table_info(''' + LActualTable + ''')';
        Qry.Open;
        LPkCount := 0;
        LRowIdName := '';
        while not Qry.Eof do
        begin
          LColName := Qry.FieldByName('name').AsString;
          for i := 0 to High(Result.Columns) do
            if SameText(Result.Columns[i].Name, LColName) then
            begin
              // FireDAC reports every SQLite column as nullable: the pragma
              // knows NOT NULL, and a primary key is never null.
              Result.Columns[i].IsNullable :=
                (Qry.FieldByName('notnull').AsInteger = 0) and
                (Qry.FieldByName('pk').AsInteger = 0);
              if Qry.FieldByName('pk').AsInteger > 0 then
              begin
                Result.Columns[i].IsPrimaryKey := True;
                Inc(LPkCount);
                // A lone INTEGER primary key is the rowid alias: the
                // database generates it.
                if SameText(Qry.FieldByName('type').AsString.Trim, 'INTEGER') then
                  LRowIdName := LColName;
              end;
              Break;
            end;
          Qry.Next;
        end;
        if (LPkCount = 1) and (LRowIdName <> '') then
          for i := 0 to High(Result.Columns) do
            if SameText(Result.Columns[i].Name, LRowIdName) then
              Result.Columns[i].IsAutoInc := True;
      finally
        Qry.Free;
      end;
    end;
    
    Meta.Close;
    Meta.MetaInfoKind := mkForeignKeys;
    Meta.CatalogName := '';
    Meta.SchemaName := LActualSchema;
    Meta.BaseObjectName := '';
    Meta.ObjectName := LActualTable;
    if not SameText(FDConn.DriverName, 'FB') then
    try
      Meta.Open;
      if Meta.Eof then
      begin
         Meta.Close;
         Meta.ObjectName := '';
         Meta.BaseObjectName := LActualTable;
         Meta.Open;
      end;

      while not Meta.Eof do
      begin
        LFK := Default(TMetaForeignKey);
        if Meta.FindField('CONSTRAINT_NAME') <> nil then LFK.Name := Meta.FieldByName('CONSTRAINT_NAME').AsString.Trim
        else if Meta.FindField('FKEY_NAME') <> nil then LFK.Name := Meta.FieldByName('FKEY_NAME').AsString.Trim
        else LFK.Name := 'FK_' + LActualTable + '_' + (Length(Result.ForeignKeys) + 1).ToString;

        if Meta.FindField('COLUMN_NAME') <> nil then LFK.ColumnName := Meta.FieldByName('COLUMN_NAME').AsString.Trim
        else if Meta.FindField('FK_COLUMN_NAME') <> nil then LFK.ColumnName := Meta.FieldByName('FK_COLUMN_NAME').AsString.Trim;

        if Meta.FindField('REF_TABLE_NAME') <> nil then LFK.ReferencedTable := Meta.FieldByName('REF_TABLE_NAME').AsString.Trim
        else if Meta.FindField('PK_TABLE_NAME') <> nil then LFK.ReferencedTable := Meta.FieldByName('PK_TABLE_NAME').AsString.Trim;

        if Meta.FindField('REF_COLUMN_NAME') <> nil then LFK.ReferencedColumn := Meta.FieldByName('REF_COLUMN_NAME').AsString.Trim
        else if Meta.FindField('PK_COLUMN_NAME') <> nil then LFK.ReferencedColumn := Meta.FieldByName('PK_COLUMN_NAME').AsString.Trim;

        LFound := False;
        for ExistingFK in Result.ForeignKeys do
          if SameText(ExistingFK.ColumnName, LFK.ColumnName) and 
             SameText(ExistingFK.ReferencedTable, LFK.ReferencedTable) then
          begin
            LFound := True;
            Break;
          end;

        if not LFound then
          Result.ForeignKeys := Result.ForeignKeys + [LFK];
        Meta.Next;
      end;
    except
    end;

    if SameText(FDConn.DriverName, 'SQLite') or SameText(FDConn.DriverName, 'FB') then
    begin
      Result.ForeignKeys := [];
      if SameText(FDConn.DriverName, 'SQLite') then
      begin
        Qry := TFDQuery.Create(nil);
        try
          Qry.Connection := FDConn;
          Qry.SQL.Text := 'PRAGMA foreign_key_list(''' + LActualTable + ''')';
          try
            Qry.Open;
            FkIndex := 0;
            while not Qry.Eof do
            begin
              LFK := Default(TMetaForeignKey);
              LFK.Name := 'FK_' + ATableName + '_' + IntToStr(FkIndex);
              LFK.ReferencedTable := Qry.FieldByName('table').AsString;
              LFK.ColumnName := Qry.FieldByName('from').AsString;
              LFK.ReferencedColumn := Qry.FieldByName('to').AsString;

              LFound := False;
              for ExistingFK in Result.ForeignKeys do
                if SameText(ExistingFK.ColumnName, LFK.ColumnName) and 
                   SameText(ExistingFK.ReferencedTable, LFK.ReferencedTable) then
                begin
                  LFound := True;
                  Break;
                end;

              if not LFound then
                Result.ForeignKeys := Result.ForeignKeys + [LFK];
              Inc(FkIndex);
              Qry.Next;
            end;
          except
          end;
        finally
          Qry.Free;
        end;
      end
      else if SameText(FDConn.DriverName, 'FB') then
      begin
        Qry := TFDQuery.Create(nil);
        try
          Qry.Connection := FDConn;
          Qry.SQL.Text := 
            'SELECT ' +
            '    TRIM(R.RDB$CONSTRAINT_NAME) AS CONSTRAINT_NAME, ' +
            '    TRIM(IS2.RDB$FIELD_NAME) AS COLUMN_NAME, ' +
            '    TRIM(R2.RDB$RELATION_NAME) AS REF_TABLE_NAME, ' +
            '    TRIM(IS3.RDB$FIELD_NAME) AS REF_COLUMN_NAME ' +
            'FROM RDB$RELATION_CONSTRAINTS R ' +
            'JOIN RDB$REF_CONSTRAINTS RC ON R.RDB$CONSTRAINT_NAME = RC.RDB$CONSTRAINT_NAME ' +
            'JOIN RDB$RELATION_CONSTRAINTS R2 ON RC.RDB$CONST_NAME_UQ = R2.RDB$CONSTRAINT_NAME ' +
            'JOIN RDB$INDEX_SEGMENTS IS2 ON R.RDB$INDEX_NAME = IS2.RDB$INDEX_NAME ' +
            'JOIN RDB$INDEX_SEGMENTS IS3 ON R2.RDB$INDEX_NAME = IS3.RDB$INDEX_NAME ' +
            'WHERE R.RDB$CONSTRAINT_TYPE = ''FOREIGN KEY'' ' +
            '  AND R.RDB$RELATION_NAME = :TABLE_NAME';
          Qry.ParamByName('TABLE_NAME').AsString := UpperCase(LActualTable);
          try
            Qry.Open;
            while not Qry.Eof do
            begin
              LFK := Default(TMetaForeignKey);
              LFK.Name := Qry.FieldByName('CONSTRAINT_NAME').AsString;
              LFK.ColumnName := Qry.FieldByName('COLUMN_NAME').AsString;
              LFK.ReferencedTable := Qry.FieldByName('REF_TABLE_NAME').AsString;
              LFK.ReferencedColumn := Qry.FieldByName('REF_COLUMN_NAME').AsString;

              LFound := False;
              for ExistingFK in Result.ForeignKeys do
                if SameText(ExistingFK.ColumnName, LFK.ColumnName) and 
                   SameText(ExistingFK.ReferencedTable, LFK.ReferencedTable) then
                begin
                  LFound := True;
                  Break;
                end;

              if not LFound then
                Result.ForeignKeys := Result.ForeignKeys + [LFK];
              Qry.Next;
            end;
          except
          end;
        finally
          Qry.Free;
        end;
      end;
    end;
  finally
  end;
end;

{ TDelphiEntityGenerator }

function TDelphiEntityGenerator.IsKeyword(const AName: string): Boolean;
const
  KEYWORDS: array[0..68] of string = (
    'AND', 'ARRAY', 'AS', 'ASM', 'BEGIN', 'CASE', 'CLASS', 'CONST', 'CONSTRUCTOR',
    'DESTRUCTOR', 'DIV', 'DO', 'DOWNTO', 'ELSE', 'END', 'EXCEPT', 'FILE', 'FOR',
    'FUNCTION', 'GOTO', 'IF', 'IMPLEMENTATION', 'IN', 'INHERITED', 'INITIALIZATION',
    'INTERFACE', 'IS', 'LABEL', 'LIBRARY', 'MOD', 'NIL', 'NOT', 'OBJECT', 'OF',
    'OR', 'OUT', 'PACKED', 'PROCEDURE', 'PROGRAM', 'PROPERTY', 'RAISE', 'RECORD',
    'REPEAT', 'SET', 'SHL', 'SHR', 'STRING', 'THEN', 'THREADVAR', 'TO', 'TRY',
    'TYPE', 'UNIT', 'UNTIL', 'USES', 'VAR', 'WHILE', 'WITH', 'XOR', 'PRIVATE',
    'PROTECTED', 'PUBLIC', 'PUBLISHED', 'STRICT', 'HELPER', 'SEALED', 'FINAL',
    'VIRTUAL', 'OVERRIDE'
  );
var
  K: string;
begin
  Result := False;
  for K in KEYWORDS do
    if SameText(AName, K) then Exit(True);
end;

function TDelphiEntityGenerator.CleanName(const AName: string): string;
var
  CleanedName: string;
  i: Integer;
  Parts: TArray<string>;
  S: string;
begin
  Result := '';
  CleanedName := AName.Replace('"', '').Replace('''', '').Replace('[', '').Replace(']', '');
  if CleanedName.Contains('.') then
  begin
    Parts := CleanedName.Split(['.']);
    if Length(Parts) > 0 then CleanedName := Parts[High(Parts)];
  end;
  Parts := CleanedName.Split(['_', '-', ' '], TStringSplitOptions.ExcludeEmpty);
  for S in Parts do
  begin
    if S.Length > 0 then
    begin
      Result := Result + UpperCase(S.Chars[0]);
      for i := 1 to S.Length - 1 do
      begin
        // If current is uppercase and previous was also uppercase, lowercase it (acronym handling)
        // e.g., EmployeeID -> EmployeeId, HTTP -> Http
        if (S.Chars[i] >= 'A') and (S.Chars[i] <= 'Z') and
           (S.Chars[i-1] >= 'A') and (S.Chars[i-1] <= 'Z') then
          Result := Result + S.Chars[i].ToLower
        else
          Result := Result + S.Chars[i];
      end;
    end;
  end;
end;

function TDelphiEntityGenerator.CleanMappingName(const AName: string): string;
begin
  Result := AName.Replace('"', '').Replace('''', '').Replace('[', '').Replace(']', '');
end;

function TDelphiEntityGenerator.EscapeIdentifier(const AIdentifier: string): string;
begin
  if IsKeyword(AIdentifier) then Result := '&' + AIdentifier
  else Result := AIdentifier;
end;

function TDelphiEntityGenerator.SQLTypeToDelphiType(const ASQLType: string; APrecision: Integer; AScale: Integer; APropertyStyle: TPropertyStyle): string;
var
  LType: string;
begin
  LType := ASQLType.Trim.ToUpper;

  // JSON
  if LType.Contains('JSON') then
  begin
    if APropertyStyle = psSmart then Exit('JsonType');
    Exit('string');
  end;

  // GUID / UUID / RAW(16)
  if LType.Contains('RAW') or LType.Contains('GUID') or LType.Contains('UUID') then
  begin
    if (APrecision = 16) or (LType = 'RAW(16)') or LType.Contains('GUID') or LType.Contains('UUID') then
    begin
      if APropertyStyle = psSmart then Exit('GuidType');
      Exit('TGUID');
    end;
    Exit('TBytes');
  end;

  // NUMBER / NUMERIC / DECIMAL (Oracle / PostgreSQL / Firebird)
  if LType.Contains('NUMBER') or LType.Contains('NUMERIC') or LType.Contains('DECIMAL') then
  begin
    // Unconstrained NUMBER (e.g. NUMBER in Oracle without precision/scale -> Double / FloatType)
    if (APrecision <= 0) and (AScale < 0) then
    begin
      if APropertyStyle = psSmart then Exit('FloatType') else Exit('Double');
    end;

    if AScale = 0 then
    begin
      if APrecision = 1 then
      begin
        if APropertyStyle = psSmart then Exit('BoolType') else Exit('Boolean');
      end
      else if (APrecision > 0) and (APrecision <= 4) then
      begin
        if APropertyStyle = psSmart then Exit('Int16Type') else Exit('SmallInt');
      end
      else if (APrecision > 4) and (APrecision <= 9) then
      begin
        if APropertyStyle = psSmart then Exit('IntType') else Exit('Integer');
      end
      else
      begin
        // APrecision > 9 or unspecified precision with scale 0
        if APropertyStyle = psSmart then Exit('Int64Type') else Exit('Int64');
      end;
    end
    else if AScale > 0 then
    begin
      if (AScale <= 4) and (APrecision <= 18) then
      begin
        if APropertyStyle = psSmart then Exit('CurrencyType') else Exit('Currency');
      end
      else
      begin
        if APropertyStyle = psSmart then Exit('FloatType') else Exit('Double');
      end;
    end;
  end;

  // INTEGERS / ROWID / COUNTERS
  if LType.Contains('INT') or LType.Contains('SERIAL') or LType.Contains('COUNTER') or LType.Contains('ROWID') then
  begin
    if LType.Contains('64') or LType.Contains('BIG') then
    begin
      if APropertyStyle = psSmart then Exit('Int64Type') else Exit('Int64');
    end;
    if LType.Contains('SMALL') or LType.Contains('SHORT') then
    begin
      if APropertyStyle = psSmart then Exit('Int16Type') else Exit('SmallInt');
    end;
    if APropertyStyle = psSmart then Exit('IntType') else Exit('Integer');
  end;

  // FLOATING POINT
  if LType.Contains('FLOAT') or LType.Contains('DOUBLE') or LType.Contains('REAL') then
  begin
    if APropertyStyle = psSmart then Exit('FloatType') else Exit('Double');
  end;

  // BOOLEANS
  if LType.Contains('BOOL') or LType.Contains('BIT') or LType.Contains('LOGICAL') then
  begin
    if APropertyStyle = psSmart then Exit('BoolType') else Exit('Boolean');
  end;

  // DATES & TIMESTAMPS (Oracle DATE contains time)
  if LType.Contains('TIMESTAMP') or (LType = 'DATE') or (LType.Contains('DATE') and LType.Contains('TIME')) then
  begin
    if APropertyStyle = psSmart then Exit('DateTimeType') else Exit('TDateTime');
  end;

  if LType.Contains('DATE') then
  begin
    if APropertyStyle = psSmart then Exit('DateType') else Exit('TDate');
  end;

  if LType.Contains('TIME') then
  begin
    if APropertyStyle = psSmart then Exit('TimeType') else Exit('TTime');
  end;

  // BINARY / BLOBS
  if LType.Contains('BLOB') or LType.Contains('BYTEA') or LType.Contains('BINARY') or
     LType.Contains('IMAGE') or LType.Contains('BFILE') then
  begin
    Exit('TBytes');
  end;

  // STRINGS / TEXT / CLOB
  if LType.Contains('CHAR') or LType.Contains('TEXT') or LType.Contains('STRING') or
     LType.Contains('CLOB') or LType.Contains('NCLOB') or LType.Contains('VARCHAR') then
  begin
    if APropertyStyle = psSmart then Exit('StringType') else Exit('string');
  end;

  if APropertyStyle = psSmart then Exit('StringType') else Exit('string');
end;

function TDelphiEntityGenerator.GenerateUnit(const AUnitName: string; const ATables: TArray<TMetaTable>; 
  AMappingStyle: TMappingStyle; APropertyStyle: TPropertyStyle; AGenerateMetadata: Boolean): string;
var
  KnownClasses: Dext.Collections.Dict.IDictionary<string, Boolean>;
  TableNavMap: IDictionary<string, IList<TPair<TMetaForeignKey, string>>>;
  ClassUsedNames: IDictionary<string, Boolean>;
  NavInfoList: IList<TPair<TMetaForeignKey, string>>;
  NavInfo: TPair<TMetaForeignKey, string>;
  Suffix: Integer;
  Attrs: IList<string>;
  EscapedPropName, EscapedNavName, EntityClassName: string;
  Table: TMetaTable;
  Col: TMetaColumn;
  FK: TMetaForeignKey;
  SB: TStringBuilder;
  LActualUnitName, PropName, FieldName, DelphiType, ClassName: string;
  RefClass, NavPropName, FinalNavName: string;
  IsDecimalType: Boolean;
begin
  LActualUnitName := ExtractFileName(AUnitName);
  if SameText(ExtractFileExt(LActualUnitName), '.pas') then LActualUnitName := ChangeFileExt(LActualUnitName, '');
  LActualUnitName := LActualUnitName.Replace(' ', '_');
  if LActualUnitName = '' then LActualUnitName := 'Dext.Entities';

  KnownClasses := TCollections.CreateDictionary<string, Boolean>;
  for Table in ATables do KnownClasses.AddOrSetValue('T' + CleanName(Table.Name), True);

  SB := TStringBuilder.Create;
  try
    SB.AppendLine('unit ' + LActualUnitName + ';');
    SB.AppendLine('');
    SB.AppendLine('interface');
    SB.AppendLine('');
    SB.AppendLine('uses');
    SB.AppendLine('  Dext.Entity,');
    SB.AppendLine('  Dext.Entity.Mapping,');
    if APropertyStyle = psSmart then SB.AppendLine('  Dext.Core.SmartTypes,');
    SB.AppendLine('  Dext.Types.Nullable,');
    SB.AppendLine('  Dext.Types.Lazy,');
    if AGenerateMetadata then
    begin
      if APropertyStyle = psPOCO then
        SB.AppendLine('  Dext.Entity.TypeSystem,');
      SB.AppendLine('  Dext.Specifications.Types,');
    end;
    SB.AppendLine('  System.SysUtils,');
    SB.AppendLine('  System.Classes;');
    SB.AppendLine('');
    SB.AppendLine('type');
    SB.AppendLine('');

    for Table in ATables do SB.AppendLine('  T' + CleanName(Table.Name) + ' = class;');
    SB.AppendLine('');
    TableNavMap := TCollections.CreateDictionary<string, IList<TPair<TMetaForeignKey, string>>>;
    try
      for Table in ATables do
      begin
        ClassName := 'T' + CleanName(Table.Name);
        if AMappingStyle = msAttributes then SB.AppendLine('  [Table(''' + CleanMappingName(Table.Name) + ''')]');
        SB.AppendLine('  ' + ClassName + ' = class');
        SB.AppendLine('  private');
        ClassUsedNames := TCollections.CreateDictionary<string, Boolean>;
        NavInfoList := TCollections.CreateList<TPair<TMetaForeignKey, string>>;
        TableNavMap.Add(Table.Name, NavInfoList);

        for Col in Table.Columns do
        begin
          if Col.IsArray then Continue; // Skip Firebird array columns (unsupported by scalar SELECT)
          PropName := CleanName(Col.Name);
          FieldName := 'F' + PropName;
          DelphiType := SQLTypeToDelphiType(Col.DataType, Col.Precision, Col.Scale, APropertyStyle);
          if (APropertyStyle = psPOCO) and Col.IsNullable and (DelphiType <> 'string') and (DelphiType <> 'TBytes') then DelphiType := 'Nullable<' + DelphiType + '>';
          SB.AppendLine('    ' + FieldName + ': ' + DelphiType + ';');
          ClassUsedNames.AddOrSetValue(PropName.ToUpper, True);
          ClassUsedNames.AddOrSetValue(FieldName.ToUpper, True);
        end;
        
        for FK in Table.ForeignKeys do
        begin
          RefClass := 'T' + CleanName(FK.ReferencedTable);
          if RefClass = 'T' then Continue;

          NavPropName := CleanName(FK.ColumnName);
          if NavPropName.EndsWith('Id', True) then NavPropName := NavPropName.Substring(0, NavPropName.Length - 2);
          if (NavPropName = '') or SameText(NavPropName, 'Id') then NavPropName := CleanName(FK.ReferencedTable);

          if NavPropName = '' then Continue;

          // Step 1: Try the base name directly (no collision with columns or other navs)
          FinalNavName := NavPropName;
          if ClassUsedNames.ContainsKey(FinalNavName.ToUpper) or
             ClassUsedNames.ContainsKey(('F' + FinalNavName).ToUpper) then
          begin
            // Step 2: EF Core convention - append 'Navigation' suffix on collision
            FinalNavName := NavPropName + 'Navigation';
            // Step 3: Numeric fallback if 'Navigation' also collides (edge case)
            Suffix := 1;
            while ClassUsedNames.ContainsKey(FinalNavName.ToUpper) or
                  ClassUsedNames.ContainsKey(('F' + FinalNavName).ToUpper) do
            begin
              Inc(Suffix);
              FinalNavName := NavPropName + 'Navigation' + IntToStr(Suffix);
            end;
          end;

          ClassUsedNames.AddOrSetValue(FinalNavName.ToUpper, True);
          ClassUsedNames.AddOrSetValue(('F' + FinalNavName).ToUpper, True);
          NavInfoList.Add(TPair<TMetaForeignKey, string>.Create(FK, FinalNavName));
          SB.AppendLine('    F' + FinalNavName + ': Lazy<' + RefClass + '>;');
        end;
        
        SB.AppendLine('  public');
        for Col in Table.Columns do
        begin
          if Col.IsArray then Continue; // Skip Firebird array columns (unsupported by scalar SELECT)
          PropName := CleanName(Col.Name);
          EscapedPropName := EscapeIdentifier(PropName);
          FieldName := 'F' + PropName;
          DelphiType := SQLTypeToDelphiType(Col.DataType, Col.Precision, Col.Scale, APropertyStyle);
          // Decided before the Nullable<> wrapper hides the base type.
          IsDecimalType := SameText(DelphiType, 'Double') or SameText(DelphiType, 'Currency') or
            SameText(DelphiType, 'FloatType') or SameText(DelphiType, 'CurrencyType');
          if (APropertyStyle = psPOCO) and Col.IsNullable and (DelphiType <> 'string') and (DelphiType <> 'TBytes') then DelphiType := 'Nullable<' + DelphiType + '>';
          if AMappingStyle = msAttributes then
          begin
              Attrs := TCollections.CreateList<string>;
              if Col.IsPrimaryKey then Attrs.Add('PK');
              if Col.IsAutoInc then Attrs.Add('AutoInc');
              if not Col.IsNullable then Attrs.Add('Required');
              if (Col.Length > 0) and
                 (SameText(DelphiType, 'string') or SameText(DelphiType, 'StringType')) then
                Attrs.Add('MaxLength(' + Col.Length.ToString + ')');
              if (Col.Precision > 0) and IsDecimalType then Attrs.Add(Format('Precision(%d, %d)', [Col.Precision, Col.Scale]));
              if Col.Name <> PropName then Attrs.Add('Column(''' + Col.Name + ''')');
              if Attrs.Count > 0 then SB.AppendLine('    [' + string.Join(', ', Attrs.ToArray) + ']');
          end;
          SB.AppendLine('    property ' + EscapedPropName + ': ' + DelphiType + ' read ' + FieldName + ' write ' + FieldName + ';');
        end;
        
        for NavInfo in NavInfoList do
        begin
          RefClass := 'T' + CleanName(NavInfo.Key.ReferencedTable);
          FinalNavName := NavInfo.Value;
           EscapedNavName := EscapeIdentifier(FinalNavName);
           if AMappingStyle = msAttributes then SB.AppendLine('    [ForeignKey(''' + NavInfo.Key.ColumnName + ''')]');
           SB.AppendLine('    property ' + EscapedNavName + ': Lazy<' + RefClass + '> read F' + FinalNavName + ' write F' + FinalNavName + ';');
        end;
        SB.AppendLine('  end;');
        SB.AppendLine('');
      end;
      
      if AGenerateMetadata and (APropertyStyle = psPOCO) then
      begin
        for Table in ATables do
        begin
           EntityClassName := CleanName(Table.Name) + 'Entity';
           SB.AppendLine('  ' + EntityClassName + ' = class(TEntityType<T' + CleanName(Table.Name) + '>)');
           SB.AppendLine('  public');
           for Col in Table.Columns do
             if not Col.IsArray then
               SB.AppendLine('    class var ' + EscapeIdentifier(CleanName(Col.Name)) + ': TPropExpression;');
           if TableNavMap.ContainsKey(Table.Name) then
           begin
             for NavInfo in TableNavMap[Table.Name] do SB.AppendLine('    class var ' + EscapeIdentifier(NavInfo.Value) + ': TPropExpression;');
           end;
           SB.AppendLine('');
           SB.AppendLine('    class constructor Create;');
           SB.AppendLine('  end;');
           SB.AppendLine('');
        end;
      end;

      if (AMappingStyle = msFluent) then SB.AppendLine('procedure RegisterMappings(ModelBuilder: TModelBuilder);' + sLineBreak);
      SB.AppendLine('implementation' + sLineBreak);
      
      if (AMappingStyle = msFluent) then
      begin
         SB.AppendLine('procedure RegisterMappings(ModelBuilder: TModelBuilder);' + sLineBreak + 'begin');
         for Table in ATables do
         begin
            ClassName := 'T' + CleanName(Table.Name);
            SB.AppendLine('  ModelBuilder.Entity<' + ClassName + '>.Table(''' + CleanMappingName(Table.Name) + ''')');
            for Col in Table.Columns do
            begin
               if Col.IsArray then Continue;
               PropName := CleanName(Col.Name);
               if Col.IsPrimaryKey then SB.AppendLine('    .HasKey(''' + PropName + ''')');
               if not SameText(Col.Name, PropName) then SB.AppendLine('    .Prop(''' + PropName + ''').Column(''' + Col.Name + ''')');
               if not Col.IsNullable then SB.AppendLine('    .Prop(''' + PropName + ''').IsRequired');
               if (Col.Length > 0) and (CleanName(Col.DataType).Contains('CHAR') or CleanName(Col.DataType).Contains('TEXT')) then SB.AppendLine('    .Prop(''' + PropName + ''').MaxLength(' + Col.Length.ToString + ')');
               if (Col.Precision > 0) then SB.AppendLine(Format('    .Prop(''%s'').Precision(%d, %d)', [PropName, Col.Precision, Col.Scale]));
            end;
            if TableNavMap.ContainsKey(Table.Name) then
            begin
              for NavInfo in TableNavMap[Table.Name] do SB.AppendLine('    .Prop(''' + NavInfo.Value + ''').HasForeignKey(''' + NavInfo.Key.ColumnName + ''')');
            end;
            SB.AppendLine('    ;');
         end;
         SB.AppendLine('end;' + sLineBreak);
      end;
      
      if AGenerateMetadata and (APropertyStyle = psPOCO) then
      begin
        for Table in ATables do
        begin
           EntityClassName := CleanName(Table.Name) + 'Entity';
           SB.AppendLine('class constructor ' + EntityClassName + '.Create;' + sLineBreak + 'begin');
           for Col in Table.Columns do
             if not Col.IsArray then
               SB.AppendLine('  ' + EscapeIdentifier(CleanName(Col.Name)) + ' := TPropExpression.Create(''' + CleanName(Col.Name) + ''');');
           if TableNavMap.ContainsKey(Table.Name) then
           begin
             for NavInfo in TableNavMap[Table.Name] do SB.AppendLine('  ' + EscapeIdentifier(NavInfo.Value) + ' := TPropExpression.Create(''' + NavInfo.Value + ''');');
           end;
           SB.AppendLine('end;');
           SB.AppendLine('');
        end;
      end;
      SB.AppendLine('end.');
      Result := SB.ToString;
    finally
      TableNavMap := nil;
    end;
  finally
    SB.Free;
  end;
end;

end.
