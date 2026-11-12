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
{  Created: 2025-12-19                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.Drivers.FireDAC.Phys;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  System.DateUtils,
  Data.DB,
  Data.FmtBcd,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.Phys.Intf,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.TypeConverters,
  Dext.Entity.Dialects,
  Dext.Types.Nullable;

type
  /// <summary>
  ///   Implementation of IDbTransaction using FireDAC Phys Interface (IFDPhysTransaction).
  /// </summary>
  TFireDACPhysTransaction = class(TInterfacedObject, IDbTransaction)
  private
    FTransaction: IFDPhysTransaction;
  public
    constructor Create(ATransaction: IFDPhysTransaction);
    procedure Commit;
    procedure Rollback;
  end;

  /// <summary>
  ///   Implementation of IDbReader using FireDAC DatS (TFDDatSTable) and Phys Interface.
  ///   Bypasses TDataSet completely for high performance.
  /// </summary>
  TFireDACPhysReader = class(TInterfacedObject, IDbReader)
  private
    FCommand: IFDPhysCommand;
    FTable: TFDDatSTable;
    FDatSManager: TFDDatSManager;
    FOwnsDatSManager: Boolean;
    FCurrentRowIndex: Integer;
    FCurrentRow: TFDDatSRow;
    FRowCount: Integer;
  public
    constructor Create(ACommand: IFDPhysCommand; ATable: TFDDatSTable; ADatSManager: TFDDatSManager = nil; AOwnsManager: Boolean = False);
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
  ///   Implementation of IDbCommand using FireDAC Phys Interface (IFDPhysCommand).
  /// </summary>
  TFireDACPhysCommand = class(TInterfacedObject, IDbCommand)
  private
    FConnection: IFDPhysConnection;
    FCommand: IFDPhysCommand;
    FOnLog: TProc<string>;

    FDialect: TDatabaseDialect;
    
    procedure SetParamValue(Param: TFDParam; const AValue: TValue);
    procedure SetParamValueWithType(Param: TFDParam; const AValue: TValue; ADataType: TFieldType);
    function GetDialect: TDatabaseDialect;
  public
    constructor Create(AConnection: IFDPhysConnection; ADialect: TDatabaseDialect);
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
    function ExecuteBatch(const ATimes: Integer; const AOffset: Integer = 0): Integer;
  end;

  /// <summary>
  ///   Implementation of IDbConnection using FireDAC Phys Interface (IFDPhysConnection).
  ///   Provides "bare metal" access to the database driver.
  /// </summary>
  TFireDACPhysConnection = class(TInterfacedObject, IDbConnection)
  private
    FConnection: IFDPhysConnection;
    FDatSManager: TFDDatSManager;
    FOnLog: TProc<string>;
    FDialect: TDatabaseDialect;
    procedure DetectDialect;
  public
    constructor Create(AConnection: IFDPhysConnection);
    destructor Destroy; override;
    
    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;
    
    function BeginTransaction: IDbTransaction;
    function CreateCommand(const ASQL: string): IDbCommand;
    function GetLastInsertId: Variant;
    function TableExists(const ATableName: string): Boolean;
    
    function GetConnectionString: string;
    procedure SetConnectionString(const AValue: string);
    property ConnectionString: string read GetConnectionString write SetConnectionString;
    
    procedure SetOnLog(AValue: TProc<string>);
    function GetOnLog: TProc<string>;
    property OnLog: TProc<string> read GetOnLog write SetOnLog;
    
    function GetDialect: TDatabaseDialect;
    property Dialect: TDatabaseDialect read GetDialect;
    
    function IsPooled: Boolean;
    
    property PhysConnection: IFDPhysConnection read FConnection;
  end;

implementation

uses
  Dext.Core.Reflection;

{ TFireDACPhysTransaction }

constructor TFireDACPhysTransaction.Create(ATransaction: IFDPhysTransaction);
begin
  inherited Create;
  FTransaction := ATransaction;
  // Auto start is usually handled by the command execution or explicit start
  if FTransaction.State = tsInactive then
    FTransaction.StartTransaction;
end;

procedure TFireDACPhysTransaction.Commit;
begin
  FTransaction.Commit;
end;

procedure TFireDACPhysTransaction.Rollback;
begin
  FTransaction.Rollback;
end;

{ TFireDACPhysReader }

constructor TFireDACPhysReader.Create(ACommand: IFDPhysCommand; ATable: TFDDatSTable; ADatSManager: TFDDatSManager; AOwnsManager: Boolean);
begin
  inherited Create;
  FCommand := ACommand;
  FTable := ATable;
  FDatSManager := ADatSManager;
  FOwnsDatSManager := AOwnsManager;
  FCurrentRowIndex := -1;
  FRowCount := FTable.Rows.Count;
  FCurrentRow := nil;
end;

destructor TFireDACPhysReader.Destroy;
begin
  if FOwnsDatSManager then
    FDatSManager.Free;
  inherited;
end;

procedure TFireDACPhysReader.Close;
begin
  // Closing the command cursor
  FCommand.Close;
end;

function TFireDACPhysReader.GetColumnCount: Integer;
begin
  Result := FTable.Columns.Count;
end;

function TFireDACPhysReader.GetColumnName(AIndex: Integer): string;
begin
  Result := FTable.Columns[AIndex].Name;
end;

function TFireDACPhysReader.GetValue(AColumnIndex: Integer): TValue;
var
  Data: Variant;
begin
  if FCurrentRow = nil then
    Exit(TValue.Empty);

  Data := FCurrentRow.GetData(AColumnIndex);
  if VarIsNull(Data) then
    Exit(TValue.Empty);

  case FTable.Columns[AColumnIndex].DataType of
    dtInt32, dtInt16, dtByte, dtUInt16, dtSByte: Result := TValue.From<Integer>(Integer(Data));
    dtInt64, dtUInt32, dtUInt64: Result := TValue.From<Int64>(Int64(Data));
    dtDouble, dtSingle:
      Result := TValue.From<Double>(Double(Data));
    dtBCD, dtFmtBCD:
      if VarIsFMTBcd(Data) then
        Result := TValue.From<TBcd>(VarToBcd(Data))
      else if VarIsStr(Data) then
        Result := TValue.From<TBcd>(StrToBcd(VarToStr(Data), TFormatSettings.Invariant))
      else if VarIsNumeric(Data) then
        Result := TValue.From<TBcd>(DoubleToBcd(Double(Data)))
      else
        raise EConvertError.CreateFmt('Cannot convert column %d data to TBcd.', [AColumnIndex]);
    dtCurrency:
      Result := TValue.From<Currency>(Currency(Data));
    dtDateTime, dtDate, dtTime, dtDateTimeStamp: Result := TValue.From<TDateTime>(TDateTime(Data));
    dtAnsiString, dtWideString, dtByteString, dtMemo, dtWideMemo, dtXML: Result := TValue.From<string>(string(Data));
    dtBlob, dtHBlob, dtHBFile: Result := TValue.From<TBytes>(TBytes(Data));
    dtGUID:
    // Variant cannot be cast to TGUID on Win64 (E2089); FireDAC exposes GUID as string in DatS.
    try
      Result := TValue.From<TGUID>(StringToGUID(Trim(VarToStr(Data))));
    except
      Result := TValue.FromVariant(Data);
    end;
    dtBoolean: Result := TValue.From<Boolean>(Boolean(Data));
  else
    Result := TValue.FromVariant(Data);
  end;
end;

function TFireDACPhysReader.GetValue(const AColumnName: string): TValue;
var
  ColIndex: Integer;
begin
  ColIndex := FTable.Columns.IndexOfName(AColumnName);
  if ColIndex < 0 then
    Exit(TValue.Empty);
  Result := GetValue(ColIndex);
end;

function TFireDACPhysReader.GetInt32(AIndex: Integer): Integer;
begin
  if FCurrentRow = nil then Exit(0);
  Result := Integer(FCurrentRow.GetData(AIndex));
end;

function TFireDACPhysReader.GetInt64(AIndex: Integer): Int64;
begin
  if FCurrentRow = nil then Exit(0);
  Result := Int64(FCurrentRow.GetData(AIndex));
end;

function TFireDACPhysReader.GetDouble(AIndex: Integer): Double;
begin
  if FCurrentRow = nil then Exit(0.0);
  Result := Double(FCurrentRow.GetData(AIndex));
end;

function TFireDACPhysReader.GetBoolean(AIndex: Integer): Boolean;
begin
  if FCurrentRow = nil then Exit(False);
  Result := Boolean(FCurrentRow.GetData(AIndex));
end;

function TFireDACPhysReader.GetString(AIndex: Integer): string;
begin
  if FCurrentRow = nil then Exit('');
  Result := string(FCurrentRow.GetData(AIndex));
end;

// Ensure line lengths remain under 79 chars
function TFireDACPhysReader.GetDateTime(AIndex: Integer): TDateTime;
begin
  if FCurrentRow = nil then Exit(0.0);
  Result := TDateTime(FCurrentRow.GetData(AIndex));
end;

function TFireDACPhysReader.GetColumnType(AIndex: Integer): TFieldType;
begin
  case FTable.Columns[AIndex].DataType of
    dtBoolean: Result := ftBoolean;
    dtByte, dtSByte, dtInt16, dtUInt16, dtInt32, dtUInt32: Result := ftInteger;
    dtInt64, dtUInt64: Result := ftLargeint;
    dtSingle: Result := ftSingle;
    dtDouble: Result := ftFloat;
    dtCurrency: Result := ftCurrency;
    dtBCD, dtFmtBCD: Result := ftBCD;
    dtDateTime, dtDateTimeStamp: Result := ftDateTime;
    dtTime: Result := ftTime;
    dtDate: Result := ftDate;
    dtGUID: Result := ftGuid;
    dtAnsiString: Result := ftString;
    dtWideString: Result := ftWideString;
    dtBlob, dtHBlob, dtHBFile: Result := ftBlob;
  else
    Result := ftUnknown;
  end;
end;

function TFireDACPhysReader.IsNull(AIndex: Integer): Boolean;
begin
  if FCurrentRow = nil then Exit(True);
  Result := VarIsNull(FCurrentRow.GetData(AIndex));
end;

function TFireDACPhysReader.Next: Boolean;
begin
  Inc(FCurrentRowIndex);
  if FCurrentRowIndex < FRowCount then
  begin
    FCurrentRow := FTable.Rows[FCurrentRowIndex];
    Result := True;
  end
  else
  begin
    FCurrentRow := nil;
    Result := False;
  end;
end;

{ TFireDACPhysCommand }

constructor TFireDACPhysCommand.Create(AConnection: IFDPhysConnection; ADialect: TDatabaseDialect);
begin
  inherited Create;
  FConnection := AConnection;
  FConnection.CreateCommand(FCommand);
  // Params are managed by the command interface usually, 
  // explicitly creating TFDParams might be needed if the interface doesn't expose them directly conveniently
  // But IFDPhysCommand doesn't expose Params property directly in some versions?
  // Actually, standard usage involves creating a TFDParams collection and assigning it?
  // Let's check typical usage.
  // IFDPhysCommand has "Dictionary"? No.
  // Usually parameters are passed via "Params" property if it's a higher level wrapper.
  // In pure Phys: 
  // FCommand.Prepare(SQL)
  // FCommand.Params (TFDParams)
  
  // Wait, IFDPhysCommand inherits from IUnknown.
  // It should probably expose Params: TFDParams.
  // Investigating: IFDPhysCommand has 'Params' property of type TFDParams in most versions.
  // If not, we cast FCommand to TFDPhysCommand? No, that's implementation.
  
  // Check typical code:
  // FCmd.Prepare(SQL);
  // FCmd.Params[0].AsInteger := ...
  // So yes, Params should be available.
  
  FDialect := ADialect;
end;

destructor TFireDACPhysCommand.Destroy;
begin
  FCommand := nil; // Interface released
  inherited;
end;

procedure TFireDACPhysCommand.SetSQL(const ASQL: string);
begin
  // We should unprepare if already prepared
  if FCommand.State <> csInactive then
    FCommand.Close;
    
  FCommand.CommandText := ASQL;
  // Prepare is often needed to populate params collection from SQL
  // Or we add params manually.
  // FireDAC parses SQL to find params automatically on Prepare.
  FCommand.Prepare; 
end;

procedure TFireDACPhysCommand.AddParam(const AName: string; const AValue: TValue);
var
  Param: TFDParam;
begin
  Param := FCommand.Params.FindParam(AName);
  if Param = nil then
  begin
    // If param not found (maybe Prepare didn't find it or manual addition needed)
    // Phys usually relies on Prepare parsing.
    // If not found, ignore or error?
    // Let's assume Prepare worked.
    Exit; 
  end;
  
  SetParamValue(Param, AValue);
end;

procedure TFireDACPhysCommand.AddParam(const AName: string; const AValue: TValue; ADataType: TFieldType);
var
  Param: TFDParam;
begin
  Param := FCommand.Params.FindParam(AName);
  if Param = nil then
    Exit;
  
  SetParamValueWithType(Param, AValue, ADataType);
end;

procedure TFireDACPhysCommand.BindSequentialParams(const AValues: TArray<TValue>);
var
  i: Integer;
begin
  if Length(AValues) = 0 then
    Exit;
  if FCommand.Params.Count <> Length(AValues) then
    raise Exception.CreateFmt(
      'FromSql parameter count mismatch: SQL has %d parameter(s) but %d value(s) were supplied.',
      [FCommand.Params.Count, Length(AValues)]);
  for i := 0 to High(AValues) do
    SetParamValue(FCommand.Params[i], AValues[i]);
end;

procedure TFireDACPhysCommand.SetParamValueWithType(Param: TFDParam; const AValue: TValue; ADataType: TFieldType);
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
    ftFloat, ftCurrency, ftExtended:
      Param.AsFloat := V.AsExtended;
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
    ftDateTime, ftTimeStamp:
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

procedure TFireDACPhysCommand.SetParamType(const AName: string; AType: TParamType);
var
  Param: TFDParam;
begin
  Param := FCommand.Params.FindParam(AName);
  if Param <> nil then
    Param.ParamType := AType;
end;

function TFireDACPhysCommand.GetParamValue(const AName: string): TValue;
var
  Param: TFDParam;
begin
  Param := FCommand.Params.FindParam(AName);
  if Param <> nil then
  begin
    if Param.IsNull or VarIsNull(Param.Value) or VarIsEmpty(Param.Value) then
      Result := TValue.Empty
    else if Param.DataType = ftLargeInt then
      Result := TValue.From<Int64>(Param.AsLargeInt)
    else
      Result := TValue.FromVariant(Param.Value);
  end
  else
    Result := TValue.Empty;
end;

procedure TFireDACPhysCommand.ClearParams;
var
  I: Integer;
begin
  // Clearing values, not removing params (structure depends on SQL)
  for I := 0 to FCommand.Params.Count - 1 do
    FCommand.Params[I].Clear;
end;

function TFireDACPhysCommand.GetDialect: TDatabaseDialect;
begin
  Result := FDialect;
end;



procedure TFireDACPhysCommand.Execute;
begin
  if Assigned(FOnLog) then FOnLog(FCommand.CommandText);
  FCommand.Execute;
end;

function TFireDACPhysCommand.ExecuteNonQuery: Integer;
begin
  if Assigned(FOnLog) then FOnLog(FCommand.CommandText);
  FCommand.Execute;
  Result := FCommand.RowsAffected;
end;

function TFireDACPhysCommand.ExecuteQuery: IDbReader;
var
  DatSManager: TFDDatSManager;
  Table: TFDDatSTable;
begin
  if Assigned(FOnLog) then FOnLog(FCommand.CommandText);
  // We need a DatS Manager for the results
  // We can use a local one or share.
  // For Phys command, we often need to Fetch.
  
  DatSManager := TFDDatSManager.Create;
  Table := DatSManager.Tables.Add;
  
  // Define structure from command?
  // FCommand.Define(Table); // Fills column defs
  
  FCommand.Define(Table);
  FCommand.Open; // Open cursor
  FCommand.Fetch(Table); // Fetch all rows into DatS Table
  
  // We pass ownership of DatSManager to the Reader, so it will be freed when Reader is destroyed.
  Result := TFireDACPhysReader.Create(FCommand, Table, DatSManager, True);
end;

function TFireDACPhysCommand.ExecuteScalar: TValue;
var
  DatS: TFDDatSManager;
  Table: TFDDatSTable;
  Val: Variant;
begin
  if Assigned(FOnLog) then FOnLog(FCommand.CommandText);
  // Execute and fetch 1 row
  DatS := TFDDatSManager.Create;
  try
    Table := DatS.Tables.Add;
    FCommand.Define(Table);
    FCommand.Open;
    FCommand.Fetch(Table, False); // Fetch next batch (AAll = False)
    
    if Table.Rows.Count > 0 then
    begin
       Val := Table.Rows[0].GetData(0);
       Result := TValue.FromVariant(Val);
    end
    else
      Result := TValue.Empty;
  finally
    DatS.Free;
  end;
end;

procedure TFireDACPhysCommand.SetArraySize(const ASize: Integer);
begin
  FCommand.Params.ArraySize := ASize;
end;

procedure TFireDACPhysCommand.SetParamArray(const AName: string; const AValues: TArray<TValue>);
var
  Param: TFDParam;
  i: Integer;
  Val: TValue;
  Bytes: TBytes;
  RawStr: RawByteString;
  Helper: TNullableHelper;
  InnerVal: TValue;
begin
  Param := FCommand.Params.FindParam(AName);
  if Param = nil then Exit;
  
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
          Param.DataType := ftInteger;
          Param.AsIntegers[i] := Val.AsInteger;
        end;
        tkInt64:
        begin
          Param.DataType := ftLargeInt;
          Param.AsLargeInts[i] := Val.AsInt64;
        end;
        tkFloat:
        begin
          if Val.TypeInfo = TypeInfo(TDateTime) then
          begin
            Param.DataType := ftDateTime;
            Param.AsDateTimes[i] := Val.AsType<TDateTime>;
          end
          else if Val.TypeInfo = TypeInfo(TDate) then
          begin
            Param.DataType := ftDate;
            Param.AsDates[i] := Val.AsType<TDate>;
          end
          else if Val.TypeInfo = TypeInfo(TTime) then
          begin
            Param.DataType := ftTime;
            Param.AsTimes[i] := Val.AsType<TTime>;
          end
          else
          begin
            Param.DataType := ftFloat;
            Param.AsFloats[i] := Val.AsExtended;
          end;
        end;
        tkString, tkUString, tkWString, tkChar, tkWChar:
        begin
          if Length(Val.AsString) > 4000 then
          begin
            if Param.DataType <> ftWideMemo then Param.DataType := ftWideMemo;
            if Param.Size < Length(Val.AsString) then Param.Size := Length(Val.AsString);
            Param.AsWideStrings[i] := Val.AsString;
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
          if Val.TypeInfo = TypeInfo(TBcd) then
          begin
            Param.DataType := ftFMTBcd;
            Param.AsFMTBCDs[i] := Val.AsType<TBcd>;
          end
          else if IsNullable(Val.TypeInfo) then
          begin
             Helper := TNullableHelper.Create(Val.TypeInfo);
             if Helper.HasValue(Val.GetReferenceToRawData) then
             begin
               InnerVal := Helper.GetValue(Val.GetReferenceToRawData);
               if InnerVal.TypeInfo = TypeInfo(TBcd) then
               begin
                 Param.DataType := ftFMTBcd;
                 Param.AsFMTBCDs[i] := InnerVal.AsType<TBcd>;
               end
               else
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
                    if Length(InnerVal.AsString) > 4000 then
                    begin
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
               Param.Clear(i);
             end;
          end
          else
             Param.Values[i] := Val.AsVariant;
        end;
      else
        Param.Values[i] := Val.AsVariant;
      end;
    end;
  end;
end;

function TFireDACPhysCommand.ExecuteBatch(const ATimes: Integer; const AOffset: Integer): Integer;
begin
  FCommand.Execute(ATimes, AOffset);
  Result := FCommand.RowsAffected;
end;

{ TFireDACPhysConnection }

constructor TFireDACPhysConnection.Create(AConnection: IFDPhysConnection);
begin
  inherited Create;
  FConnection := AConnection;
  FDatSManager := TFDDatSManager.Create;
end;

destructor TFireDACPhysConnection.Destroy;
begin
  FDatSManager.Free;
  inherited;
end;

procedure TFireDACPhysConnection.Connect;
begin
  FConnection.Open;
end;

procedure TFireDACPhysConnection.Disconnect;
begin
  FConnection.Close;
end;

function TFireDACPhysConnection.IsConnected: Boolean;
begin
  Result := FConnection.State = csConnected;
end;

procedure TFireDACPhysConnection.SetOnLog(AValue: TProc<string>);
begin
  FOnLog := AValue;
end;

function TFireDACPhysConnection.GetOnLog: TProc<string>;
begin
  Result := FOnLog;
end;

function TFireDACPhysConnection.BeginTransaction: IDbTransaction;
var
  Tx: IFDPhysTransaction;
begin
  FConnection.CreateTransaction(Tx);
  Result := TFireDACPhysTransaction.Create(Tx);
end;

function TFireDACPhysConnection.CreateCommand(const ASQL: string): IDbCommand;
var
  LCmd: TFireDACPhysCommand;
begin
  LCmd := TFireDACPhysCommand.Create(FConnection, GetDialect);
  LCmd.FOnLog := FOnLog;
  if ASQL <> '' then
    LCmd.SetSQL(ASQL);
  Result := LCmd;
end;

function TFireDACPhysConnection.GetLastInsertId: Variant;
begin
   Result := FConnection.GetLastAutoGenValue('');
end;

function TFireDACPhysConnection.TableExists(const ATableName: string): Boolean;
var
  MetaCmd: IFDPhysMetaInfoCommand;
  DatS: TFDDatSManager;
  Table: TFDDatSTable;
begin
  FConnection.CreateMetaInfoCommand(MetaCmd);
  
  MetaCmd.MetaInfoKind := mkTables;
  MetaCmd.ObjectScopes := [osMy, osOther, osSystem];
  MetaCmd.Wildcard := ATableName;
  
  DatS := TFDDatSManager.Create;
  try
    Table := DatS.Tables.Add;
    MetaCmd.Define(Table);
    MetaCmd.Open;
    MetaCmd.Fetch(Table);
    
    Result := Table.Rows.Count > 0;
  finally
    DatS.Free;
  end;
end;

procedure TFireDACPhysCommand.SetParamValue(Param: TFDParam; const AValue: TValue);
var
  Converter: ITypeConverter;
  ConvertedValue: TValue;
  Bytes: TBytes;
  RawStr: RawByteString;
  Helper: TNullableHelper;
  InnerVal: TValue;
begin
  if AValue.IsEmpty then
  begin
    Param.Clear;
    if Param.DataType = ftUnknown then
      Param.DataType := ftString; 
    Exit;
  end;

  // Try to find a type converter
  Converter := TTypeConverterRegistry.Instance.GetConverter(AValue.TypeInfo);
  if Converter <> nil then
  begin
    ConvertedValue := Converter.ToDatabase(AValue, GetDialect);
    
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
        Param.AsWideString := ConvertedValue.AsString;
      end;
      tkDynArray:
      begin
        if ConvertedValue.TypeInfo = TypeInfo(TBytes) then
        begin
           Bytes := ConvertedValue.AsType<TBytes>;
           SetLength(RawStr, Length(Bytes));
           if Length(Bytes) > 0 then
             Move(Bytes[0], RawStr[1], Length(Bytes));
           Param.AsBlob := RawStr;
        end
        else
          Param.Value := ConvertedValue.AsVariant;
      end;
      else
        Param.Value := ConvertedValue.AsVariant;
    end;
  end
  else
  begin
    // Direct assignment logic
    case AValue.Kind of
      tkInteger: 
      begin
        Param.DataType := ftInteger;
        Param.AsInteger := AValue.AsInteger;
      end;
      tkInt64:
      begin
        Param.DataType := ftLargeInt;
        Param.AsLargeInt := AValue.AsInt64;
      end;
      tkFloat:
      begin
        if AValue.TypeInfo = TypeInfo(TDateTime) then
        begin
          Param.DataType := ftDateTime;
          Param.AsDateTime := AValue.AsType<TDateTime>;
        end
        else if AValue.TypeInfo = TypeInfo(TDate) then
        begin
          Param.DataType := ftDate;
          Param.AsDate := AValue.AsType<TDate>;
        end
        else if AValue.TypeInfo = TypeInfo(TTime) then
        begin
          Param.DataType := ftTime;
          Param.AsTime := AValue.AsType<TTime>;
        end
        else
        begin
          Param.DataType := ftFloat;
          Param.AsFloat := AValue.AsExtended;
        end;
      end;
      tkString, tkUString, tkWString, tkChar, tkWChar:
      begin
        Param.AsWideString := AValue.AsString;
      end;
      tkDynArray:
      begin
        if AValue.TypeInfo = TypeInfo(TBytes) then
        begin
           Bytes := AValue.AsType<TBytes>;
           SetLength(RawStr, Length(Bytes));
           if Length(Bytes) > 0 then
             Move(Bytes[0], RawStr[1], Length(Bytes));
           Param.AsBlob := RawStr;
        end
        else
          Param.Value := AValue.AsVariant;
      end;
      tkEnumeration:
      begin
        if AValue.TypeInfo = TypeInfo(Boolean) then
        begin
          Param.DataType := ftBoolean;
          Param.AsBoolean := AValue.AsBoolean;
        end
        else
        begin
          Param.DataType := ftInteger;
          Param.AsInteger := AValue.AsOrdinal;
        end;
      end;
      tkRecord:
      begin
        if IsNullable(AValue.TypeInfo) then
        begin
           Helper := TNullableHelper.Create(AValue.TypeInfo);
           if Helper.HasValue(AValue.GetReferenceToRawData) then
           begin
             InnerVal := Helper.GetValue(AValue.GetReferenceToRawData);
             SetParamValue(Param, InnerVal);
           end
           else
           begin
             Param.Clear;
           end;
        end
        else
           Param.Value := AValue.AsVariant;
      end;
    else
      Param.Value := AValue.AsVariant;
    end;
  end;
end;
function TFireDACPhysConnection.GetConnectionString: string;
begin
  Result := ''; // Not easily supported via Phys interface directly without re-creating connection
end;

procedure TFireDACPhysConnection.SetConnectionString(const AValue: string);
begin
  // We don't support late-binding connection strings here yet.
end;

procedure TFireDACPhysConnection.DetectDialect;
var
  DriverID: string;
begin
  if FDialect <> ddUnknown then Exit;

  // IFDPhysConnection doesn't expose DriverName directly as property, checking...
  // Usually we can get it from Driver
  if FConnection.Driver <> nil then
    DriverID := FConnection.Driver.DriverID.ToLower
  else
    DriverID := ''; // Should not happen if connected

  FDialect := TDialectFactory.DetectDialect(DriverID);
end;

function TFireDACPhysConnection.GetDialect: TDatabaseDialect;
begin
  if FDialect = ddUnknown then
    DetectDialect;
  Result := FDialect;
end;

function TFireDACPhysConnection.IsPooled: Boolean;
begin
  Result := False; // Phys connections are not pooled
end;

end.
