unit Dext.EF.Design.Scaffolding.Helpers;

interface

uses
  Data.DB,
  FireDAC.Comp.Client,
  System.Classes,
  System.SysUtils,
  System.Rtti,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Scaffolding;

type
  TScaffoldingHelper = class
  private
    class function GetFieldProperty(AField: TField; const APropName: string): Integer;
  public
    class function DataSetToMetaTable(ADataSet: TDataSet): TMetaTable;
    class function GetTablesFromConnection(AConnection: TFDConnection): TArray<string>;
    class function GetTableMetadata(AConnection: TFDConnection; const ATableName: string): TMetaTable;
  end;

implementation

{ TScaffoldingHelper }

class function TScaffoldingHelper.GetFieldProperty(AField: TField;
  const APropName: string): Integer;
var
  Ctx: TRttiContext;
  RType: TRttiType;
  Prop: TRttiProperty;
  Val: TValue;
begin
  Result := 0;
  Ctx := TRttiContext.Create;
  try
    RType := Ctx.GetType(AField.ClassType);
    Prop := RType.GetProperty(APropName);
    if (Prop <> nil) and Prop.IsReadable then
    begin
      Val := Prop.GetValue(AField);
      if not Val.IsEmpty then
      begin
        if Val.Kind in [tkInteger, tkInt64, tkEnumeration] then
          Result := Val.AsOrdinal
        else if Val.Kind = tkFloat then
          Result := Round(Val.AsType<Extended>);
      end;
    end;
  finally
    Ctx.Free;
  end;
end;

class function TScaffoldingHelper.DataSetToMetaTable(ADataSet: TDataSet): TMetaTable;
var
  I: Integer;
  Field: TField;
  Col: TMetaColumn;
begin
  Result.Name := ADataSet.Name;
  if Result.Name = '' then
    Result.Name := 'GeneratedEntity';
    
  Result.Columns := [];
  Result.ForeignKeys := [];

  for I := 0 to ADataSet.FieldCount - 1 do
  begin
    Field := ADataSet.Fields[I];
    
    Col.Name := Field.FieldName;
    Col.DataType := Field.ClassName; // Placeholder, might need more mapping
    Col.Length := Field.Size;
    Col.Precision := GetFieldProperty(Field, 'Precision');
    Col.Scale := GetFieldProperty(Field, 'Scale');
    
    Col.IsNullable := not Field.Required;
    Col.IsPrimaryKey := pfInKey in Field.ProviderFlags;
    // AutoInc detection: check DataType or AutoGenerateValue (FireDAC)
    Col.IsAutoInc := (Field.DataType = ftAutoInc) or (GetFieldProperty(Field, 'AutoGenerateValue') = 1); // 1 = arAutoInc
    Col.IsArray := False;
    
    // Better DataType mapping
    case Field.DataType of
      ftString, ftWideString: Col.DataType := 'VARCHAR';
      ftSmallint, ftShortint, ftByte: Col.DataType := 'SMALLINT';
      // A Word (0..65535) does not fit a SmallInt.
      ftWord, ftInteger, ftAutoInc: Col.DataType := 'INTEGER';
      ftLargeint: Col.DataType := 'BIGINT';
      // A Float has no fixed scale: it must not be read as NUMERIC(15,0),
      // which the generator turns into an integer property.
      ftFloat: Col.DataType := 'DOUBLE';
      ftCurrency:
        begin
          Col.DataType := 'NUMERIC';
          Col.Precision := 18;
          Col.Scale := 4;
        end;
      ftBCD, ftFMTBcd:
        begin
          Col.DataType := 'NUMERIC';
          if Col.Precision <= 0 then
            Col.Precision := 18;
          // For a BCD field, Size is the number of decimals.
          Col.Scale := Field.Size;
        end;
      ftTime: Col.DataType := 'TIME';
      ftDate, ftDateTime, ftTimeStamp: Col.DataType := 'TIMESTAMP';
      ftBoolean: Col.DataType := 'BOOLEAN';
      ftBlob, ftGraphic: Col.DataType := 'BLOB';
      ftGuid: Col.DataType := 'GUID';
    else
      Col.DataType := 'VARCHAR';
    end;

    Result.Columns := Result.Columns + [Col];
  end;
end;

class function TScaffoldingHelper.GetTableMetadata(AConnection: TFDConnection;
  const ATableName: string): TMetaTable;
var
  DextConn: IDbConnection;
  Provider: ISchemaProvider;
begin
  DextConn := TFireDACConnection.Create(AConnection, False);
  Provider := TFireDACSchemaProvider.Create(DextConn);
  Result := Provider.GetTableMetadata(ATableName);
end;

class function TScaffoldingHelper.GetTablesFromConnection(
  AConnection: TFDConnection): TArray<string>;
var
  DextConn: IDbConnection;
  Provider: ISchemaProvider;
begin
  DextConn := TFireDACConnection.Create(AConnection, False);
  Provider := TFireDACSchemaProvider.Create(DextConn);
  Result := Provider.GetTables;
end;

end.
