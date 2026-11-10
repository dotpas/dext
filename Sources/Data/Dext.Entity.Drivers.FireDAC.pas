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
unit Dext.Entity.Drivers.FireDAC;

interface

{$I Dext.inc}

uses
  Data.DB,
  Data.FmtBcd,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.DApt,
  FireDAC.DApt.Intf,
  FireDAC.DatS,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Error,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Param,
  System.Classes,
  System.DateUtils,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  System.Variants,

  Dext.Collections,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC.Links,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.TypeConverters,
  Dext.Types.Nullable,
  Dext.Types.UUID;

type
  TFireDACConnection = class;

  /// <summary>
  ///   FireDAC transaction manager. Ensures all session commands share the same transaction.
  /// </summary>
  TFireDACTransaction = class(TInterfacedObject, IDbTransaction)
  private
    FTransaction: TFDTransaction;
    FOwnsTransaction: Boolean;
  public
    constructor Create(AConnection: TFDConnection);
    destructor Destroy; override;
    procedure Commit;
    procedure Rollback;
  end;

  /// <summary>
  ///   Implementation of IDbReader using FireDAC components for reading data.
  /// </summary>
  TFireDACReader = class(TInterfacedObject, IDbReader)
  private
    FQuery: TFDQuery;
    FOwnsQuery: Boolean;
    FIsFirstMove: Boolean;
    FFields: TArray<TField>;
  public
    constructor Create(AQuery: TFDQuery; AOwnsQuery: Boolean);
    destructor Destroy; override;
    
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

  /// <summary>
  ///   FireDAC SQL command. Supports execution of queries, non-queries, scalars, and batch operations (Batch DML).
  /// </summary>
  TFireDACCommand = class(TInterfacedObject, IDbCommand)
  private
    FQuery: TFDQuery;
    FConnection: TFDConnection;
    FDialect: TDatabaseDialect;
    FOnLog: TProc<string>;
    procedure LogSqlCommand(const ASQL: string; AParams: TFDParams = nil);
    procedure SetParamValue(Param: TFDParam; const AValue: TValue);
    procedure SetParamValueWithType(Param: TFDParam; const AValue: TValue; ADataType: TFieldType);
    function GetDialect: TDatabaseDialect;
  public
    constructor Create(AConnection: TFDConnection; ADialect: TDatabaseDialect);
    destructor Destroy; override;
    
    procedure SetSQL(const ASQL: string);
    procedure AddParam(const AName: string; const AValue: TValue); overload;
    procedure AddParam(const AName: string; const AValue: TValue; ADataType: TFieldType); overload;
    procedure BindSequentialParams(const AValues: TArray<TValue>);
    procedure SetParamType(const AName: string; AType: TParamType);
    function GetParamValue(const AName: string): TValue;
    procedure ClearParams;
    
    procedure Execute;
    function ExecuteQuery: IDbReader;
    function ExecuteNonQuery: Integer;
    function ExecuteScalar: TValue;
    
    procedure SetArraySize(const ASize: Integer);
    procedure SetParamArray(const AName: string; const AValues: TArray<TValue>);
    procedure ExecuteBatch(const ATimes: Integer; const AOffset: Integer = 0);
    property Query: TFDQuery read FQuery;
  end;

  /// <summary>
  ///   Physical FireDAC connection. Manages connection pooling and automatic dialect detection.
  /// </summary>
  TFireDACConnection = class(TInterfacedObject, IDbConnection)
  private
    FConnection: TFDConnection;
    FOwnsConnection: Boolean;
    FOnLog: TProc<string>;
    FDialect: TDatabaseDialect;
    procedure DetectDialect;
    procedure DoAfterConnect(Sender: TObject);
  public
    constructor Create(AConnection: TFDConnection; AOwnsConnection: Boolean = True);
    destructor Destroy; override;
    
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    
    function BeginTransaction: IDbTransaction;
    function CreateCommand(const ASQL: string): IDbCommand;
    function GetLastInsertId: Variant;
    function TableExists(const ATableName: string): Boolean;
    function IsPooled: Boolean;

    function GetConnectionString: string;
    procedure SetConnectionString(const AValue: string);
    property ConnectionString: string read GetConnectionString write SetConnectionString;
    
    function GetDialect: TDatabaseDialect;
    property Dialect: TDatabaseDialect read GetDialect;
    
    procedure SetOnLog(AValue: TProc<string>);
    function GetOnLog: TProc<string>;
    property OnLog: TProc<string> read GetOnLog write SetOnLog;
    
    property Connection: TFDConnection read FConnection;
  end;

  function DextGetActiveDbConnections: Integer;

implementation

uses
  System.SyncObjs,
  System.JSON,
  FireDAC.ConsoleUI.Wait,
  Dext.Core.Reflection,
  Dext.Telemetry.Metrics,
  Dext.Logging.Tracing,
  Dext.Telemetry.Context;

var
  GActiveDbConnections: Integer = 0;

function DextGetActiveDbConnections: Integer;
begin
  Result := TInterlocked.Add(GActiveDbConnections, 0);
end;

// FireDAC moves a TGUID to and from a PostgreSQL uuid with D1, D2 and D3 in network
// byte order. Applying this swap on the way in and on the way out keeps the
// canonical text (the one GUIDToString shows) in the column.
function SwapPgGuid(const AGuid: TGUID): TGUID;
begin
  Result := AGuid;
  Result.D1 := ((AGuid.D1 and $000000FF) shl 24) or ((AGuid.D1 and $0000FF00) shl 8) or
              ((AGuid.D1 and $00FF0000) shr 8) or ((AGuid.D1 and $FF000000) shr 24);
  Result.D2 := Swap(AGuid.D2);
  Result.D3 := Swap(AGuid.D3);
end;

function FireDACFieldToTValue(Field: TField): TValue;
var
  StrVal: string;
  Guid: TGUID;
begin
  if (Field = nil) or Field.IsNull then
    Exit(TValue.Empty);
  case Field.DataType of
    ftUnknown:
      Result := TValue.FromVariant(Field.Value);
    ftString, ftWideString, ftMemo, ftWideMemo, ftFixedChar, ftFixedWideChar:
      Result := TValue.From<string>(Field.AsWideString);
    ftSmallint, ftShortint:
      Result := TValue.From<Integer>(Field.AsInteger);
    ftInteger, ftAutoInc, ftWord:
      Result := TValue.From<Integer>(Field.AsInteger);
    ftLongWord:
      Result := TValue.From<Int64>(Field.AsLargeInt);
    ftLargeint:
      Result := TValue.From<Int64>(Field.AsLargeInt);
    ftFloat, Data.DB.ftSingle:
      Result := TValue.From<Double>(Field.AsFloat);
    Data.DB.ftExtended:
      Result := TValue.From<Double>(Field.AsFloat);
    ftCurrency:
      Result := TValue.From<Currency>(Field.AsCurrency);
    ftBCD, ftFMTBcd:
      Result := TValue.From<TBcd>(Field.AsBcd);
    ftBoolean:
      if Field is TBooleanField then
        Result := TValue.From<Boolean>(TBooleanField(Field).Value)
      else if Field is TNumericField then
        Result := TValue.From<Boolean>(TNumericField(Field).AsInteger <> 0)
      else
      begin
        StrVal := Field.AsString;
        if (StrVal = '1') or SameText(StrVal, 'true') or SameText(StrVal, 't') 
           or SameText(StrVal, 'y') or SameText(StrVal, 's') then
          Result := TValue.From<Boolean>(True)
        else if (StrVal = '0') or SameText(StrVal, 'false') or 
                SameText(StrVal, 'f') or SameText(StrVal, 'n') then
          Result := TValue.From<Boolean>(False)
        else
          Result := TValue.From<Boolean>(StrToBoolDef(StrVal, False));
      end;
    ftDate:
      Result := TValue.From<TDate>(DateOf(Field.AsDateTime));
    ftTime:
      Result := TValue.From<TTime>(TimeOf(Field.AsDateTime));
    ftDateTime, ftTimeStamp, ftOraTimeStamp, ftTimeStampOffset:
      Result := TValue.From<TDateTime>(Field.AsDateTime);
    ftBlob, ftOraBlob, ftGraphic, ftTypedBinary, ftParadoxOle, ftDBaseOle, ftVarBytes, ftBytes:
      try
        Result := TValue.From<TBytes>(Field.AsBytes);
      except
        Result := TValue.FromVariant(Field.Value);
      end;
    ftGuid:
      begin
        Guid := Field.AsGuid;
        // FireDAC reads a PostgreSQL uuid into the TGUID fields in network byte
        // order, so D1, D2 and D3 come swapped: undo it for that driver.
        if (Field.DataSet is TFDRdbmsDataSet) and
           (TFDRdbmsDataSet(Field.DataSet).Connection <> nil) and
           SameText(TFDRdbmsDataSet(Field.DataSet).Connection.DriverName, 'PG') then
          Guid := SwapPgGuid(Guid);
        Result := TValue.From<TGUID>(Guid);
      end;
  else
    Result := TValue.FromVariant(Field.Value);
  end;
end;

{ TFireDACTransaction }

constructor TFireDACTransaction.Create(AConnection: TFDConnection);
begin
  inherited Create;
  FTransaction := TFDTransaction.Create(nil);
  FTransaction.Connection := AConnection;

  // Bind this transaction to the connection so Queries pick it up automatically. 
  // Without this, FireDAC creates implicit auto-commit transactions for each SQL
  // command, ignoring our explicit transaction.
  AConnection.Transaction := FTransaction;
  AConnection.UpdateTransaction := FTransaction;

  FTransaction.StartTransaction;
  FOwnsTransaction := True;
end;

destructor TFireDACTransaction.Destroy;
begin
  if FOwnsTransaction and (FTransaction <> nil) then
  begin
    // Unbind from connection if it is still bound
    if (FTransaction.Connection <> nil) and (FTransaction.Connection.Transaction = FTransaction) then
    begin
      FTransaction.Connection.Transaction := nil;
      FTransaction.Connection.UpdateTransaction := nil;
    end;

    if FTransaction.Active then
      FTransaction.Rollback;
    FTransaction.Free;
  end;
  inherited;
end;

procedure TFireDACTransaction.Commit;
begin
  FTransaction.Commit;
  // Unbind after commit to avoid accidental reuse
  if (FTransaction.Connection <> nil) and (FTransaction.Connection.Transaction = FTransaction) then
  begin
    FTransaction.Connection.Transaction := nil;
    FTransaction.Connection.UpdateTransaction := nil;
  end;
end;

procedure TFireDACTransaction.Rollback;
begin
  FTransaction.Rollback;
  // Unbind after rollback
  if (FTransaction.Connection <> nil) and (FTransaction.Connection.Transaction = FTransaction) then
  begin
    FTransaction.Connection.Transaction := nil;
    FTransaction.Connection.UpdateTransaction := nil;
  end;
end;

{ TFireDACReader }

constructor TFireDACReader.Create(AQuery: TFDQuery; AOwnsQuery: Boolean);
var
  i: Integer;
begin
  inherited Create;
  FQuery := AQuery;
  FOwnsQuery := AOwnsQuery;
  FIsFirstMove := True;
  
  // Cache the fields to avoid FQuery.Fields[Index] property getter overhead
  SetLength(FFields, FQuery.FieldCount);
  for i := 0 to FQuery.FieldCount - 1 do
    FFields[i] := FQuery.Fields[i];
end;

destructor TFireDACReader.Destroy;
begin
  if FOwnsQuery then
    FQuery.Free;
  inherited;
end;

procedure TFireDACReader.Close;
begin
  FQuery.Close;
end;

function TFireDACReader.GetColumnCount: Integer;
begin
  Result := FQuery.FieldCount;
end;

function TFireDACReader.GetColumnName(AIndex: Integer): string;
begin
  Result := FQuery.Fields[AIndex].FieldName;
end;

function TFireDACReader.GetValue(AColumnIndex: Integer): TValue;
begin
  Result := FireDACFieldToTValue(FFields[AColumnIndex]);
end;

function TFireDACReader.GetValue(const AColumnName: string): TValue;
begin
  Result := GetValue(FQuery.FieldByName(AColumnName).Index);
end;

function TFireDACReader.GetInt32(AIndex: Integer): Integer;
begin
  Result := FFields[AIndex].AsInteger;
end;

function TFireDACReader.GetInt64(AIndex: Integer): Int64;
begin
  Result := FFields[AIndex].AsLargeInt;
end;

function TFireDACReader.GetDouble(AIndex: Integer): Double;
begin
  Result := FFields[AIndex].AsFloat;
end;

function TFireDACReader.GetBoolean(AIndex: Integer): Boolean;
var
  Field: TField;
  StrVal: string;
begin
  Field := FFields[AIndex];

  case Field.DataType of
    // 1. Boolean
    ftBoolean:
      Result := Field.AsBoolean;

    // 2. Numeric
    ftInteger, ftSmallint, ftWord, ftLargeint, ftShortint, ftByte, 
    ftFMTBcd, ftBCD, ftFloat, ftCurrency: // Adicionado outros tipos numéricos comuns para blindar o método
      Result := Field.AsInteger <> 0;

    // 3. Fallback
  else
    StrVal := Field.AsString;

    // Short-Circuit
    if (StrVal = '1') or SameText(StrVal, 'true') or SameText(StrVal, 't') or
       SameText(StrVal, 'y') or SameText(StrVal, 's') then
      Result := True
    else if (StrVal = '0') or SameText(StrVal, 'false') or
            SameText(StrVal, 'f') or SameText(StrVal, 'n') then
      Result := False
    else
      Result := StrToBoolDef(StrVal, False);
  end;
end;

function TFireDACReader.GetString(AIndex: Integer): string;
begin
  Result := FFields[AIndex].AsWideString;
end;

function TFireDACReader.GetDateTime(AIndex: Integer): TDateTime;
begin
  Result := FFields[AIndex].AsDateTime;
end;

function TFireDACReader.GetColumnType(AIndex: Integer): TFieldType;
begin
  Result := FFields[AIndex].DataType;
end;

function TFireDACReader.IsNull(AIndex: Integer): Boolean;
begin
  Result := FFields[AIndex].IsNull;
end;

function TFireDACReader.Next: Boolean;
begin
  if not FQuery.Active then
    Exit(False);
    
  if FIsFirstMove then
  begin
    FIsFirstMove := False;
    // TDataSet is already at First after Open.
    // If it's empty, Eof is true.
    Result := not FQuery.Eof;
  end
  else
  begin
    FQuery.Next;
    Result := not FQuery.Eof;
  end;
end;

{ TFireDACCommand }

constructor TFireDACCommand.Create(AConnection: TFDConnection; ADialect: TDatabaseDialect);
begin
  inherited Create;
  FConnection := AConnection;
  FDialect := ADialect;
  FQuery := TFDQuery.Create(nil);
  FQuery.Connection := FConnection;
  FQuery.ResourceOptions.ParamCreate := True;
end;

destructor TFireDACCommand.Destroy;
begin
  FQuery.Free;
  inherited;
end;

procedure TFireDACCommand.AddParam(const AName: string; const AValue: TValue);
var
  Param: TFDParam;
begin
  try
    Param := FQuery.ParamByName(AName);
    SetParamValue(Param, AValue);
  except
    on E: Exception do
      raise;
  end;
end;

procedure TFireDACCommand.AddParam(const AName: string; const AValue: TValue; ADataType: TFieldType);
var
  Param: TFDParam;
begin
  Param := FQuery.ParamByName(AName);
  SetParamValueWithType(Param, AValue, ADataType);
end;

procedure TFireDACCommand.BindSequentialParams(const AValues: TArray<TValue>);
var
  i: Integer;
begin
  if Length(AValues) = 0 then
    Exit;

  // ParamCreate=True (constructor) populates Params from SQL.Text immediately,
  // so we can validate the count BEFORE Prepare. Defer Prepare until AFTER values
  // are set so SetParamValue can assign Param.DataType from each TValue first.
  // This avoids PostgreSQL PG-335 "Parameter [X] data type is unknown".
  if FQuery.Params.Count <> Length(AValues) then
    raise Exception.CreateFmt(
      'FromSql parameter count mismatch: SQL has %d parameter(s) but %d value(s) were supplied.',
      [FQuery.Params.Count, Length(AValues)]);

  for i := 0 to High(AValues) do
    SetParamValue(FQuery.Params[i], AValues[i]);

  FQuery.Prepare;
end;

procedure TFireDACCommand.SetParamValueWithType(Param: TFDParam; const AValue: TValue; ADataType: TFieldType);
var
  V: TValue;
  Bytes: TBytes;
  RawStr: RawByteString;
begin
  V := AValue;
  TReflection.TryUnwrapProp(V, V);

  // Force the explicit data type first
  Param.DataType := ADataType;
  
  if V.IsEmpty then
  begin
    Param.Clear;
    Exit;
  end;
  
  // Set value based on the explicit type
  case ADataType of
    ftString, ftWideString, ftMemo, ftWideMemo:
      Param.AsWideString := V.AsString;
    ftSmallint, ftInteger, ftWord, ftShortint:
      if V.Kind = tkEnumeration then
        Param.AsInteger := V.AsOrdinal
      else
        Param.AsInteger := V.AsInteger;
    ftLargeint:
      Param.AsLargeInt := V.AsInt64;
    ftFloat, Data.DB.ftExtended:
      Param.AsFloat := V.AsExtended;
    ftCurrency:
      Param.AsCurrency := V.AsType<Currency>;
    ftBCD, ftFMTBcd:
      if V.TypeInfo = TypeInfo(TBcd) then
        Param.AsFMTBCD := V.AsType<TBcd>
      else
        case V.Kind of
          tkFloat:
            Param.AsFMTBCD := DoubleToBcd(V.AsExtended);
          tkInteger, tkInt64:
            Param.AsFMTBCD := DoubleToBcd(V.AsInt64);
          tkString, tkUString, tkWString, tkLString:
            Param.AsFMTBCD := StrToBcd(V.AsString);
          tkRecord:
            if V.TypeInfo = TypeInfo(TBcd) then
              Param.AsFMTBCD := V.AsType<TBcd>
            else
              Param.AsFMTBCD := DoubleToBcd(V.AsExtended);
        else
          Param.AsFMTBCD := DoubleToBcd(V.AsExtended);
        end;
    ftDate:
      Param.AsDate := V.AsType<TDate>;
    ftTime:
      Param.AsTime := V.AsType<TTime>;
    ftDateTime, ftTimeStamp, ftOraTimeStamp, ftTimeStampOffset:
      Param.AsDateTime := V.AsType<TDateTime>;
    ftBoolean:
      Param.AsBoolean := V.AsBoolean;
    ftBlob, ftGraphic, ftParadoxOle, ftDBaseOle, ftTypedBinary, ftOraBlob:
    begin
      if V.TypeInfo = TypeInfo(TBytes) then
      begin
        Bytes := V.AsType<TBytes>;
        SetLength(RawStr, Length(Bytes));
        if Length(Bytes) > 0 then
          Move(Bytes[0], RawStr[1], Length(Bytes));
        Param.AsBlob := RawStr;
      end
      else
        Param.Value := V.AsVariant;
    end;
    ftGuid:
      Param.AsGUID := StringToGUID(V.AsString);
  else
    // Fallback: use variant conversion
    Param.Value := V.AsVariant;
  end;
end;

function TFireDACCommand.GetDialect: TDatabaseDialect;
begin
  Result := FDialect;
end;


procedure TFireDACCommand.SetParamValue(Param: TFDParam; const AValue: TValue);
var
  Converter: ITypeConverter;
  ConvertedValue: TValue;
  TypeName: string;
  IsByteArray: Boolean;
  Bytes: TBytes;
  RawStr: RawByteString;
  Helper: TNullableHelper;
  InnerVal: TValue;
  Underlying: PTypeInfo;
  V: TValue;
begin
  V := AValue;
  TReflection.TryUnwrapProp(V, V);

  if V.IsEmpty then
  begin
    Param.Clear;
    Param.Value := Null;
    Underlying := V.TypeInfo;
    if Underlying = nil then
    begin
      if (AValue.TypeInfo <> nil) and IsNullable(AValue.TypeInfo) then
        Underlying := GetUnderlyingType(AValue.TypeInfo)
      else
        Underlying := AValue.TypeInfo;
    end;

    // Set correct DataType for empty values - byte arrays need ftBlob!
    if Underlying <> nil then
    begin
      TypeName := string(Underlying.Name);
      if (TypeName = 'TBytes') or (TypeName = 'TArray<System.Byte>') or (TypeName = 'TArray<Byte>') then
        Param.DataType := ftBlob
      else
      begin
        case Underlying.Kind of
          tkInteger: Param.DataType := ftInteger;
          tkInt64: Param.DataType := ftLargeInt;
          tkFloat: 
            if Underlying = TypeInfo(TDateTime) then Param.DataType := ftDateTime
            else if Underlying = TypeInfo(TDate) then Param.DataType := ftDate
            else if Underlying = TypeInfo(TTime) then Param.DataType := ftTime
            else Param.DataType := ftFloat;
          tkString, tkUString, tkWString, tkChar, tkWChar: Param.DataType := ftString;
          tkEnumeration:
            if Underlying = TypeInfo(Boolean) then Param.DataType := ftBoolean
            else Param.DataType := ftInteger;
          else
            Param.DataType := ftString; // Fallback
        end;
      end;
    end
    else if Param.DataType = ftUnknown then
      Param.DataType := ftString; // Ultimate fallback if no TypeInfo
    Exit;
  end;
  
  // Try to find a type converter
  Converter := TTypeConverterRegistry.Instance.GetConverter(V.TypeInfo);

  if Converter <> nil then
  begin
    // Convert value using converter
    ConvertedValue := Converter.ToDatabase(V, GetDialect);

    // Fix for PostgreSQL UUID "operator does not exist" error
    // Explicitly handle TGUID, TUUID and String-formatted GUIDs
    if (V.TypeInfo = TypeInfo(TGUID)) or (V.TypeInfo = TypeInfo(TUUID)) then
    begin
      Param.DataType := ftGuid;
      Param.AsString := ConvertedValue.AsString;
    end
    // aggressive check for GUID strings to handle cases where TValue lost strict type info
    else if (ConvertedValue.Kind in [tkString, tkUString, tkWString]) and
            ((Length(ConvertedValue.AsString) = 36) or (Length(ConvertedValue.AsString) = 38)) and
            (ConvertedValue.AsString.IndexOf('-') > 0) then // Simple heuristic check
    begin
       // Only force ftGuid if it looks like a GUID. Postgres requires this for = operator.
       // Valid GUID ex: 550e8400-e29b-41d4-a716-446655440000 (36) or {550e8400...} (38)
       Param.DataType := ftGuid;
       Param.AsString := ConvertedValue.AsString;
    end
    else
    // Set param value (converted value is typically a string or integer)
    case ConvertedValue.Kind of
        tkInteger:
        begin
          Param.DataType := ftInteger;
          Param.AsInteger := ConvertedValue.AsInteger;
        end;
        tkInt64:
        begin
          Param.DataType := ftLargeInt;
          Param.AsLargeInt := ConvertedValue.AsInt64;
        end;
        tkFloat:
        begin
          if ConvertedValue.TypeInfo = TypeInfo(TDateTime) then
          begin
            Param.DataType := ftDateTime;
            Param.AsDateTime := ConvertedValue.AsType<TDateTime>;
          end
          else if ConvertedValue.TypeInfo = TypeInfo(TDate) then
          begin
            Param.DataType := ftDate;
            Param.AsDate := ConvertedValue.AsType<TDate>;
          end
          else if ConvertedValue.TypeInfo = TypeInfo(TTime) then
          begin
            Param.DataType := ftTime;
            Param.AsTime := ConvertedValue.AsType<TTime>;
          end
          else
          begin
            Param.DataType := ftFloat;
            Param.AsFloat := ConvertedValue.AsExtended;
          end;
        end;
        tkString, tkUString, tkWString, tkChar, tkWChar:
        begin
          // Use ftWideMemo for large strings to avoid FireDAC size limits
          if Length(ConvertedValue.AsString) > 4000 then
          begin
            Param.DataType := ftWideMemo;
            Param.Size := Length(ConvertedValue.AsString);
            Param.AsWideMemo := ConvertedValue.AsString;
          end
          else
          begin
            Param.DataType := ftWideString;
            Param.AsWideString := ConvertedValue.AsString;
          end;
        end;
        tkDynArray:
        begin
          // Check for byte arrays by name (TBytes / TArray<Byte> / TArray<System.Byte>)
          // TypeInfo(TBytes) may not match TArray<System.Byte> pointer
          IsByteArray := False;
          if ConvertedValue.TypeInfo <> nil then
          begin
            TypeName := string(ConvertedValue.TypeInfo.Name);
            IsByteArray := (TypeName = 'TBytes') or 
                           (TypeName = 'TArray<System.Byte>') or 
                           (TypeName = 'TArray<Byte>');

          end;
          
          if IsByteArray then
          begin
             // Explicitly set ftBlob. FireDAC needs this for Postgres bytea.
             Param.DataType := ftBlob;
             Bytes := ConvertedValue.AsType<TBytes>;
             SetLength(RawStr, Length(Bytes));
             if Length(Bytes) > 0 then
               Move(Bytes[0], RawStr[1], Length(Bytes));
             Param.AsBlob := RawStr;

          end
          else
          begin
            Param.Value := ConvertedValue.AsVariant;

          end;
        end;
        else
          Param.Value := ConvertedValue.AsVariant;
    end;  // end case ConvertedValue.Kind
  end  // end if Converter <> nil
  else
  begin
    case V.Kind of
      tkInteger: 
      begin
        Param.DataType := ftInteger;
        Param.AsInteger := V.AsInteger;
      end;
      tkInt64:
      begin
        Param.DataType := ftLargeInt;
        Param.AsLargeInt := V.AsInt64;
      end;
      tkFloat:
      begin
        if V.TypeInfo = TypeInfo(TDateTime) then
        begin
          Param.DataType := ftDateTime;
          Param.AsDateTime := V.AsType<TDateTime>;
        end
        else if V.TypeInfo = TypeInfo(TDate) then
        begin
          Param.DataType := ftDate;
          Param.AsDate := V.AsType<TDate>;
        end
        else if V.TypeInfo = TypeInfo(TTime) then
        begin
          Param.DataType := ftTime;
          Param.AsTime := V.AsType<TTime>;
        end
        else
        begin
          Param.DataType := ftFloat;
          Param.AsFloat := V.AsExtended;
        end;
      end;
      tkString, tkUString, tkWString, tkChar, tkWChar:
      begin
        // Check if this string is a GUID and force ftGuid for PostgreSQL compatibility
        if (V.Kind in [tkString, tkUString, tkWString]) and
           ((Length(V.AsString) = 36) or (Length(V.AsString) = 38)) and
           (V.AsString.IndexOf('-') > 0) then
        begin
          Param.DataType := ftGuid;
          Param.AsString := V.AsString;
        end
        // Use ftWideMemo for large strings to avoid FireDAC size limits (default is 32767 for ftString)
        else if Length(V.AsString) > 4000 then
        begin
          Param.DataType := ftWideMemo;
          Param.Size := Length(V.AsString);
          Param.AsWideMemo := V.AsString;
        end
        else
        begin
          Param.DataType := ftWideString;
          Param.AsWideString := V.AsString;
        end;
      end;
      tkDynArray:
      begin
        // Check for byte arrays by name (TBytes / TArray<Byte> / TArray<System.Byte>)
        IsByteArray := False;
        if V.TypeInfo <> nil then
        begin
          TypeName := string(V.TypeInfo.Name);
          IsByteArray := (TypeName = 'TBytes') or 
                         (TypeName = 'TArray<System.Byte>') or 
                         (TypeName = 'TArray<Byte>');

        end;
        
        if IsByteArray then
        begin
           // Set ftBlob explicitly for PostgreSQL bytea compatibility
           Param.DataType := ftBlob;
           Bytes := V.AsType<TBytes>;
           SetLength(RawStr, Length(Bytes));
           if Length(Bytes) > 0 then
             Move(Bytes[0], RawStr[1], Length(Bytes));
           Param.AsBlob := RawStr;

        end
        else
        begin
          Param.Value := V.AsVariant;

        end;
      end;
      tkEnumeration:
      begin
        if V.TypeInfo = TypeInfo(Boolean) then
        begin
          Param.DataType := ftBoolean;
          Param.AsBoolean := V.AsBoolean;
        end
        else
        begin
          Param.DataType := ftInteger;
          Param.AsInteger := V.AsOrdinal;
        end;
      end;
      tkRecord:
      begin
        if V.TypeInfo = TypeInfo(TBcd) then
        begin
          Param.DataType := ftFMTBcd;
          Param.AsFMTBCD := V.AsType<TBcd>;
        end
        else if IsNullable(V.TypeInfo) then
        begin
           Helper := TNullableHelper.Create(V.TypeInfo);
           if Helper.HasValue(V.GetReferenceToRawData) then
           begin
             InnerVal := Helper.GetValue(V.GetReferenceToRawData);
             SetParamValue(Param, InnerVal);
           end
           else
           begin
             Param.Clear;
             // Try to set type from underlying type
             Underlying := GetUnderlyingType(V.TypeInfo);
             if Underlying <> nil then
             begin
               if Underlying = TypeInfo(TBcd) then
                 Param.DataType := ftFMTBcd
               else
                 case Underlying.Kind of
                   tkInteger: Param.DataType := ftInteger;
                   tkInt64: Param.DataType := ftLargeInt;
                   tkFloat: Param.DataType := ftFloat;
                   tkString, tkUString, tkWString: Param.DataType := ftString;
                   tkEnumeration:
                     if Underlying = TypeInfo(Boolean) then
                       Param.DataType := ftBoolean
                     else
                       Param.DataType := ftInteger;
                 end;
             end;
           end;
        end
        else
           Param.Value := V.AsVariant;
      end;  // end case V.Kind
    else
      Param.Value := V.AsVariant;
      // If the value is Null and we haven't set a type, default to ftString
      // This prevents "Data type is unknown" errors in FireDAC
      if (VarIsNull(Param.Value) or VarIsEmpty(Param.Value)) and (Param.DataType = ftUnknown) then
        Param.DataType := ftString;
    end;
  end;  // end else (no converter)
end;

procedure TFireDACCommand.SetParamType(const AName: string; AType: TParamType);
begin
  FQuery.ParamByName(AName).ParamType := AType;
end;

function TFireDACCommand.GetParamValue(const AName: string): TValue;
var
  Param: TFDParam;
begin
  Param := FQuery.ParamByName(AName);
  if Param.IsNull or VarIsNull(Param.Value) or VarIsEmpty(Param.Value) then
    Result := TValue.Empty
  else if Param.DataType = ftLargeInt then
    Result := TValue.From<Int64>(Param.AsLargeInt)
  else
    Result := TValue.FromVariant(Param.Value);
end;

procedure TFireDACCommand.ClearParams;
begin
  FQuery.Params.Clear;
end;

procedure TFireDACCommand.Execute;
begin
  ExecuteNonQuery;
end;

procedure TFireDACCommand.LogSqlCommand(const ASQL: string; AParams: TFDParams);
var
  i: Integer;
begin
  if not Assigned(FOnLog) then Exit;

  FOnLog('SQL: ' + ASQL);
  if (AParams <> nil) and (AParams.Count > 0) then
  begin
    for i := 0 to AParams.Count - 1 do
    begin
      FOnLog(Format('  Param[%s]: Type=%s, Value=%s',
        [AParams[i].Name, GetEnumName(TypeInfo(TFieldType), Integer(AParams[i].DataType)), VarToStr(AParams[i].Value)]));
    end;
  end;
end;

function TFireDACCommand.ExecuteNonQuery: Integer;
var
  LSpan: TSpan;
  LParamObj: TJSONObject;
  i: Integer;
begin
  LogSqlCommand(FQuery.SQL.Text, FQuery.Params);
  LSpan := TTracer.BeginSpan('SQL Exec', 'SQL');
  LSpan.SetAttribute('db.statement', FQuery.SQL.Text);
  if (FQuery.Params <> nil) and (FQuery.Params.Count > 0) then
  begin
    LParamObj := TJSONObject.Create;
    try
      for i := 0 to FQuery.Params.Count - 1 do
        LParamObj.AddPair(FQuery.Params[i].Name, VarToStr(FQuery.Params[i].Value));
      LSpan.SetAttribute('db.params', LParamObj.ToString);
    finally
      LParamObj.Free;
    end;
  end;

  try
    FQuery.ExecSQL;
    Result := FQuery.RowsAffected;
    LSpan.SetStatus('Success');
  except
    on E: Exception do
    begin
      LSpan.SetStatus('Error', E.Message);
      if Assigned(FOnLog) then
        FOnLog('  ❌ Error: ' + E.Message);
      raise;
    end;
  end;
  LSpan.Finish;
end;

function TFireDACCommand.ExecuteQuery: IDbReader;
var
  Q: TFDQuery;
  i: Integer;
  Src, Dest: TFDParam;
  LSpan: TSpan;
  LParamObj: TJSONObject;
begin
  // Create a new Query for the Reader to allow independent iteration
  Q := TFDQuery.Create(nil);
  LSpan := TTracer.BeginSpan('SQL Query', 'SQL');
  LSpan.SetAttribute('db.statement', FQuery.SQL.Text);
  if (FQuery.Params <> nil) and (FQuery.Params.Count > 0) then
  begin
    LParamObj := TJSONObject.Create;
    try
      for i := 0 to FQuery.Params.Count - 1 do
        LParamObj.AddPair(FQuery.Params[i].Name, VarToStr(FQuery.Params[i].Value));
      LSpan.SetAttribute('db.params', LParamObj.ToString);
    finally
      LParamObj.Free;
    end;
  end;

  try
    Q.Connection := FConnection;
    Q.SQL.Text := FQuery.SQL.Text;
    
    LogSqlCommand(Q.SQL.Text, FQuery.Params);

    // Copy params
    for i := 0 to FQuery.Params.Count - 1 do
    begin
      Src := FQuery.Params[i];
      Dest := Q.Params.FindParam(Src.Name);
      if Dest <> nil then
      begin
        Dest.DataType := Src.DataType;
        Dest.Value := Src.Value;
      end;
    end;
    
    Q.Open;
    Result := TFireDACReader.Create(Q, True); // Reader now owns this new query
    LSpan.SetStatus('Success');
  except
    on E: Exception do
    begin
      LSpan.SetStatus('Error', E.Message);
      if Assigned(FOnLog) then
        FOnLog(Format('ERROR executing SQL: %s', [E.Message]));
      Q.Free;
      raise;
    end;
  end;
  LSpan.Finish;
end;

function TFireDACCommand.ExecuteScalar: TValue;
var
  LSpan: TSpan;
  LParamObj: TJSONObject;
  i: Integer;
begin
  LogSqlCommand(FQuery.SQL.Text, FQuery.Params);
  LSpan := TTracer.BeginSpan('SQL Scalar', 'SQL');
  LSpan.SetAttribute('db.statement', FQuery.SQL.Text);
  if (FQuery.Params <> nil) and (FQuery.Params.Count > 0) then
  begin
    LParamObj := TJSONObject.Create;
    try
      for i := 0 to FQuery.Params.Count - 1 do
        LParamObj.AddPair(FQuery.Params[i].Name, VarToStr(FQuery.Params[i].Value));
      LSpan.SetAttribute('db.params', LParamObj.ToString);
    finally
      LParamObj.Free;
    end;
  end;

  try
    FQuery.Open;
    try
      if not FQuery.Eof then
        Result := FireDACFieldToTValue(FQuery.Fields[0])
      else
        Result := TValue.Empty;
      LSpan.SetStatus('Success');
    finally
      FQuery.Close;
    end;
  except
    on E: Exception do
    begin
      LSpan.SetStatus('Error', E.Message);
      if Assigned(FOnLog) then
        FOnLog('  ❌ Error: ' + E.Message);
      raise;
    end;
  end;
  LSpan.Finish;
end;

procedure TFireDACCommand.SetSQL(const ASQL: string);
begin
  FQuery.Params.Clear;
  FQuery.SQL.Text := ASQL;
end;

procedure TFireDACCommand.SetArraySize(const ASize: Integer);
begin
  FQuery.Params.ArraySize := ASize;
end;

procedure TFireDACCommand.SetParamArray(const AName: string; const AValues: TArray<TValue>);
var
  Param: TFDParam;
  i: Integer;
  Val: TValue;
  Bytes: TBytes;
  RawStr: RawByteString;
  Helper: TNullableHelper;
  InnerVal: TValue;
begin
  Param := FQuery.ParamByName(AName);
  for i := 0 to High(AValues) do
  begin
    Val := AValues[i];
    
    if Val.IsEmpty then
    begin
      Param.Clear(i);
      if Param.DataType = ftUnknown then Param.DataType := ftString;
    end
    else
    begin
      case Val.Kind of
        tkInteger: 
        begin
          if Param.DataType = ftUnknown then Param.DataType := ftInteger;
          Param.AsIntegers[i] := Val.AsInteger;
        end;
        tkInt64:
        begin
          if Param.DataType = ftUnknown then Param.DataType := ftLargeInt;
          Param.AsLargeInts[i] := Val.AsInt64;
        end;
        tkFloat:
        begin
          if Val.TypeInfo = TypeInfo(TDateTime) then
          begin
            if Param.DataType = ftUnknown then Param.DataType := ftDateTime;
            Param.AsDateTimes[i] := Val.AsType<TDateTime>;
          end
          else if Val.TypeInfo = TypeInfo(TDate) then
          begin
            if Param.DataType = ftUnknown then Param.DataType := ftDate;
            Param.AsDates[i] := Val.AsType<TDate>;
          end
          else if Val.TypeInfo = TypeInfo(TTime) then
          begin
            if Param.DataType = ftUnknown then Param.DataType := ftTime;
            Param.AsTimes[i] := Val.AsType<TTime>;
          end
          else
          begin
            if Param.DataType = ftUnknown then Param.DataType := ftFloat;
            Param.AsFloats[i] := Val.AsExtended;
          end;
        end;
        tkString, tkUString, tkWString, tkChar, tkWChar:
        begin
          if Length(Val.AsString) > 4000 then
          begin
            if Param.DataType <> ftWideMemo then Param.DataType := ftWideMemo;
            if Param.Size < Length(Val.AsString) then Param.Size := Length(Val.AsString);
            Param.AsWideStrings[i] := Val.AsString; // Arrays use AsWideStrings, no AsWideMemos array prop usually
          end
          // A GUID written as text must reach PostgreSQL as a uuid, as in the
          // single-row path (SetParamValue)
          else if ((Length(Val.AsString) = 36) or (Length(Val.AsString) = 38)) and
                  (Val.AsString.IndexOf('-') > 0) and (GetDialect = ddPostgreSQL) then
          begin
            Param.DataType := ftGuid;
            if Val.AsString.StartsWith('{') then
              Param.AsGUIDs[i] := SwapPgGuid(StringToGUID(Val.AsString))
            else
              Param.AsGUIDs[i] := SwapPgGuid(StringToGUID('{' + Val.AsString + '}'));
          end
          else
            Param.AsWideStrings[i] := Val.AsString;
        end;
        tkDynArray:
        begin
          if Val.TypeInfo = TypeInfo(TBytes) then
          begin
            Bytes := Val.AsType<TBytes>;
            SetLength(RawStr, Length(Bytes));
            if Length(Bytes) > 0 then
              Move(Bytes[0], RawStr[1], Length(Bytes));
            Param.AsBlobs[i] := RawStr;
          end
          else
            Param.Values[i] := Val.AsVariant;
        end;
        tkEnumeration:
        begin
          if Val.TypeInfo = TypeInfo(Boolean) then
          begin
            Param.DataType := ftBoolean;
            Param.AsBooleans[i] := Val.AsBoolean;
          end
          else
          begin
            Param.DataType := ftInteger;
            Param.AsIntegers[i] := Val.AsOrdinal;
          end;
        end;
        tkRecord:
        begin
          if IsNullable(Val.TypeInfo) then
          begin
             Helper := TNullableHelper.Create(Val.TypeInfo);
             if Helper.HasValue(Val.GetReferenceToRawData) then
             begin
               InnerVal := Helper.GetValue(Val.GetReferenceToRawData);
               // Recursive call for inner value? No, just handle it here or duplicate logic.
               // Duplicating logic for simplicity to avoid recursion with index passing
               case InnerVal.Kind of
                 tkInteger:
                   begin
                     Param.DataType := ftInteger;
                     Param.AsIntegers[i] := InnerVal.AsInteger;
                   end;
                 tkInt64:
                   begin
                     Param.DataType := ftLargeInt;
                     Param.AsLargeInts[i] := InnerVal.AsInt64;
                   end;
                 tkFloat:
                  begin
                    if InnerVal.TypeInfo = TypeInfo(TDateTime) then
                    begin
                      Param.DataType := ftDateTime;
                      Param.AsDateTimes[i] := InnerVal.AsType<TDateTime>;
                    end
                    else if InnerVal.TypeInfo = TypeInfo(TDate) then
                    begin
                      Param.DataType := ftDate;
                      Param.AsDates[i] := InnerVal.AsType<TDate>;
                    end
                    else if InnerVal.TypeInfo = TypeInfo(TTime) then
                    begin
                      Param.DataType := ftTime;
                      Param.AsTimes[i] := InnerVal.AsType<TTime>;
                    end
                    else
                    begin
                      Param.DataType := ftFloat;
                      Param.AsFloats[i] := InnerVal.AsExtended;
                    end;
                  end;
                  tkString, tkUString, tkWString:
                  begin
                    // Check for large strings in array param
                    if Length(InnerVal.AsString) > 4000 then
                    begin
                       // Array DML with mixed sizes is tricky. FireDAC usually expects consistent types.
                       // For safety, if we detect large strings, we might want to force the whole column to be WideMemo?
                       // But SetParamArray sets values for one param name (an array of values).
                       // We can set DataType on the Param once.
                       if Param.DataType <> ftWideMemo then Param.DataType := ftWideMemo;
                       if Param.Size < Length(InnerVal.AsString) then Param.Size := Length(InnerVal.AsString);
                    end;
                    Param.AsWideStrings[i] := InnerVal.AsString;
                  end;
                  tkDynArray:
                  begin
                    if InnerVal.TypeInfo = TypeInfo(TBytes) then
                    begin
                      Bytes := InnerVal.AsType<TBytes>;
                      SetLength(RawStr, Length(Bytes));
                      if Length(Bytes) > 0 then
                        Move(Bytes[0], RawStr[1], Length(Bytes));
                      Param.AsBlobs[i] := RawStr;
                    end
                    else
                      Param.Values[i] := InnerVal.AsVariant;
                  end;
                  tkEnumeration:
                   if InnerVal.TypeInfo = TypeInfo(Boolean) then
                   begin
                     Param.DataType := ftBoolean;
                     Param.AsBooleans[i] := InnerVal.AsBoolean;
                   end
                   else
                   begin
                     Param.DataType := ftInteger;
                     Param.AsIntegers[i] := InnerVal.AsOrdinal;
                   end;
               end;
             end
             else
             begin
               // Null Nullable<T>: clear the slot and ensure DataType
               // is set from the underlying inner type so FireDAC array
               // DML does not report "parameter data type is unknown".
               Param.Clear(i);
                if Param.DataType = ftUnknown then
                begin
                  var Underlying := GetUnderlyingType(Val.TypeInfo);
                  if Underlying <> nil then
                  begin
                    case Underlying.Kind of
                      tkInteger: Param.DataType := ftInteger;
                      tkInt64: Param.DataType := ftLargeInt;
                      tkFloat:
                        if Underlying = TypeInfo(TDateTime) then
                          Param.DataType := ftDateTime
                        else if Underlying = TypeInfo(TDate) then
                          Param.DataType := ftDate
                        else if Underlying = TypeInfo(TTime) then
                          Param.DataType := ftTime
                        else
                          Param.DataType := ftFloat;
                      tkString, tkUString, tkWString, tkChar, tkWChar:
                        Param.DataType := ftString;
                      tkEnumeration:
                        if Underlying = TypeInfo(Boolean) then
                          Param.DataType := ftBoolean
                        else
                          Param.DataType := ftInteger;
                    else
                      Param.DataType := ftString;
                    end;
                  end
                  else
                    Param.DataType := ftString;
                end;
             end;
          end
          else
             Param.Values[i] := Val.AsVariant;
        end;
      else
      begin
        Param.Values[i] := Val.AsVariant;
        // If we just assigned a Null/Empty variant and the param type is
        // still unknown, SQLite will refuse to execute. Use ftString as
        // a safe default so FireDAC can bind the NULL correctly.
        if (Param.DataType = ftUnknown) and VarIsNull(Val.AsVariant)
        then
          Param.DataType := ftString;
      end;
      end;
    end;
  end;
end;

procedure TFireDACCommand.ExecuteBatch(const ATimes: Integer; const AOffset: Integer);
begin
  LogSqlCommand(FQuery.SQL.Text + Format(' (Batch size: %d, Offset: %d)', [ATimes, AOffset]), FQuery.Params);
  try
    FQuery.Execute(ATimes, AOffset);
  except
    on E: Exception do
    begin
      if Assigned(FOnLog) then
        FOnLog('  ❌ Error in batch execution: ' + E.Message);
      raise;
    end;
  end;
end;

{ TFireDACConnection }

constructor TFireDACConnection.Create(AConnection: TFDConnection; AOwnsConnection: Boolean);
begin
  inherited Create;
  FConnection := AConnection;
  FOwnsConnection := AOwnsConnection;
  
  // Register AfterConnect to apply session settings (like search_path)
  FConnection.AfterConnect := DoAfterConnect;
  
  TInterlocked.Increment(GActiveDbConnections);
end;

destructor TFireDACConnection.Destroy;
begin
  TInterlocked.Decrement(GActiveDbConnections);
  
  if FOwnsConnection then
    FConnection.Free;
  inherited;
end;

function TFireDACConnection.BeginTransaction: IDbTransaction;
begin
  Result := TFireDACTransaction.Create(FConnection);
end;

procedure TFireDACConnection.Connect;
begin
  // Performance optimization for metadata discovery
  FConnection.FetchOptions.Cache := FConnection.FetchOptions.Cache - [fiMeta];
  FConnection.ResourceOptions.AutoConnect := False;
  FConnection.Connected := True;
end;

procedure TFireDACConnection.DoAfterConnect(Sender: TObject);
var
  DatabaseSchema: string;
  SqlDialect: ISQLDialect;
  Sql: string;
begin
  // Try to find the schema in connection parameters
  DatabaseSchema := FConnection.Params.Values['Schema'];
  if DatabaseSchema = '' then
    DatabaseSchema := FConnection.Params.Values['MetaCurSchema']; // FireDAC standard for current schema
  if DatabaseSchema = '' then
    DatabaseSchema := FConnection.Params.Values['MetaDefSchema']; // Fallback
    
  if DatabaseSchema <> '' then
  begin
    // Create dialect instance to get the correct SQL command
    SqlDialect := TDialectFactory.CreateDialect(GetDialect);
    if SqlDialect <> nil then
    begin
      Sql := SqlDialect.GetSetSchemaSQL(DatabaseSchema);
      if Sql <> '' then
      begin
        if Assigned(FOnLog) then
          FOnLog('Applying session schema: ' + Sql);
        try
          // Execute the command to switch the session context (e.g., SET search_path, USE [db], etc.)
          FConnection.ExecSQL(Sql);
        except
          on E: Exception do
            if Assigned(FOnLog) then
              FOnLog('Error applying schema: ' + E.Message);
        end;
      end;
    end;
  end;
end;

function TFireDACConnection.CreateCommand(const ASQL: string): IDbCommand;
var
  LCmd: TFireDACCommand;
begin
  LCmd := TFireDACCommand.Create(FConnection, GetDialect);
  LCmd.FOnLog := FOnLog;
  if ASQL <> '' then
    LCmd.SetSQL(ASQL);
  Result := LCmd;
end;

function TFireDACConnection.GetLastInsertId: Variant;
begin
  Result := FConnection.GetLastAutoGenValue('');
end;

procedure TFireDACConnection.Disconnect;
begin
  FConnection.Connected := False;
end;

function TFireDACConnection.IsConnected: Boolean;
begin
  Result := FConnection.Connected;
end;

function TFireDACConnection.IsPooled: Boolean;
var
  Def: IFDStanConnectionDef;
begin
  // First check if the connection is assigned to a manager/pool
  if FConnection.ConnectionDefName <> '' then
  begin
     // We assume if it has a DefName AND it was registered through our manager, it is pooled.
     // FireDAC pooling is usually defined at the definition level.
     if FConnection.Params.Pooled then
       Result := True
     else
     begin
       Def := TFDManager(FireDAC.Comp.Client.FDManager).ConnectionDefs.FindConnectionDef(FConnection.ConnectionDefName);
       if Def <> nil then
         Result := Def.Params.Pooled
       else
         Result := False;
     end;
  end
  else
    Result := False;
end;

procedure TFireDACConnection.SetOnLog(AValue: TProc<string>);
begin
  FOnLog := AValue;
end;

function TFireDACConnection.GetOnLog: TProc<string>;
begin
  Result := FOnLog;
end;

function TFireDACConnection.TableExists(const ATableName: string): Boolean;
var
  List: TStringList;
  LSchema: string;
  Table: string;
  Relation: string;
  DotPos: Integer;
begin
  // PostgreSQL: ask the server, which resolves the name through the search_path.
  // GetTableNames lists the tables of other schemas as well, so a table with the
  // same name in another schema would hide a missing one in the current schema.
  if GetDialect = ddPostgreSQL then
  begin
    try
      Relation := ATableName.Replace('"', '');
      DotPos := Relation.IndexOf('.');
      if DotPos > 0 then
        Relation := '"' + Relation.Substring(0, DotPos) + '"."' +
          Relation.Substring(DotPos + 1) + '"'
      else
        Relation := '"' + Relation + '"';
      Exit(Boolean(FConnection.ExecSQLScalar(
        'SELECT to_regclass(:n) IS NOT NULL', [Relation])));
    except
      // Fall back to the metadata listing below
    end;
  end;

  List := TStringList.Create;
  try
    try
      // Get list of tables
      // Try to get schema from params
      LSchema := FConnection.Params.Values['Schema'];
      if LSchema = '' then
        LSchema := FConnection.Params.Values['MetaDefSchema'];

      FConnection.GetTableNames('', LSchema, '', List, [osMy, osOther], [tkTable], False);
      
      // Check for existence
      // 1. Exact match
      if List.IndexOf(ATableName) >= 0 then
        Exit(True);
        
      // 2. Quoted match (if ATableName is not quoted but DB returns quoted)
      if List.IndexOf('"' + ATableName + '"') >= 0 then
        Exit(True);
        
      // 3. Unquoted match (if ATableName is quoted but DB returns unquoted)
      if List.IndexOf(ATableName.Replace('"', '')) >= 0 then
        Exit(True);
        
      // 4. Case insensitive match (fallback)
      for Table in List do
      begin
        if SameText(Table, ATableName) or 
           SameText(Table, '"' + ATableName + '"') or
           SameText(Table, ATableName.Replace('"', '')) then
          Exit(True);
      end;
      
      Result := False;
    except
      Result := False; // If metadata query fails, assume false or handle error?
    end;
  finally
    List.Free;
  end;
end;

function TFireDACConnection.GetConnectionString: string;
begin
  Result := FConnection.ConnectionString;
end;

procedure TFireDACConnection.SetConnectionString(const AValue: string);
begin
  if FConnection.Connected then
    FConnection.Connected := False;
  FConnection.ConnectionString := AValue;
end;

procedure TFireDACConnection.DetectDialect;
var
  DriverID: string;
  Def: IFDStanConnectionDef;
  Query: TFDQuery;
  VerStr: string;
begin
  if FDialect <> ddUnknown then Exit;

  DriverID := FConnection.DriverName;
  if DriverID = '' then
    DriverID := FConnection.Params.DriverID;
    
  if (DriverID = '') and (FConnection.ConnectionDefName <> '') then
  begin
    Def := TFDManager(FireDAC.Comp.Client.FDManager).ConnectionDefs.FindConnectionDef(FConnection.ConnectionDefName);
    if Def <> nil then
      DriverID := Def.Params.DriverID;
  end;
     
  FDialect := TDialectFactory.DetectDialect(DriverID.ToLower);
  
  if (FDialect = ddMySQL) and FConnection.Connected then
  begin
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FConnection;
      Query.SQL.Text := 'SELECT VERSION()';
      Query.Open;
      if not Query.IsEmpty then
      begin
        VerStr := Query.Fields[0].AsString;
        if VerStr.ToLower.Contains('mariadb') then
          FDialect := ddMariaDB;
      end;
    finally
      Query.Free;
    end;
  end;
end;

function TFireDACConnection.GetDialect: TDatabaseDialect;
begin
  if FDialect = ddUnknown then
    DetectDialect
  else if (FDialect = ddMySQL) and FConnection.Connected then
  begin
    FDialect := ddUnknown;
    DetectDialect;
  end;
  Result := FDialect;
end;

initialization
  Dext.Telemetry.Metrics.GActiveDbConnectionsFunc := DextGetActiveDbConnections;

end.
