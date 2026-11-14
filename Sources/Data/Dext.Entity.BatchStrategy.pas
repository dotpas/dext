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
{  Created: 2026-07-23                                                      }
{  Summary: Spec S59 - DbSet Dialect-Aware Batch UPDATE & DELETE Strategy   }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.BatchStrategy;

interface

uses
  Data.DB,
  System.Classes,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  Dext.Collections,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Core.Reflection,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Mapping,
  Dext.Entity.TypeConverters,
  Dext.Types.Nullable;

type
  /// <summary>
  ///   Represents a property to column mapping metadata pair for batch operations.
  /// </summary>
  TPropColPair = record
    Prop: TRttiProperty;
    ColName: string;
    DataType: TFieldType;
    Converter: ITypeConverter;
  end;

  /// <summary>
  ///   Dialect-aware execution strategy factory for batch UPDATE and DELETE operations.
  /// </summary>
  TDextBatchStrategyFactory = class
  public
    /// <summary>Executes batch UPDATE operations for entities based on database dialect.</summary>
    class procedure ExecuteUpdateBatch(const AContext: IDbContext;
      const ATableName: string;
      SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;

    /// <summary>Executes batch DELETE operations for entities based on database dialect.</summary>
    class procedure ExecuteDeleteBatch(const AContext: IDbContext;
      const ATableName: string;
      WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;
  end;

  /// <summary>
  ///   PostgreSQL single-statement batch strategy using VALUES(...) table expressions
  ///   and Tuple-IN delete clauses.
  /// </summary>
  TDextPostgresBatchStrategy = class
  public
    /// <summary>Executes single-statement batch UPDATE for PostgreSQL.</summary>
    class procedure ExecuteUpdateBatch(const AContext: IDbContext;
      const ATableName: string;
      SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;

    /// <summary>Executes single-statement batch DELETE for PostgreSQL.</summary>
    class procedure ExecuteDeleteBatch(const AContext: IDbContext;
      const ATableName: string;
      WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;
  end;

  /// <summary>
  ///   MySQL / MariaDB single-statement batch strategy using CASE-WHEN updates
  ///   and Tuple-IN delete clauses.
  /// </summary>
  TDextMySqlBatchStrategy = class
  public
    /// <summary>Executes single-statement batch UPDATE for MySQL / MariaDB.</summary>
    class procedure ExecuteUpdateBatch(const AContext: IDbContext;
      const ATableName: string;
      SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;

    /// <summary>Executes single-statement batch DELETE for MySQL / MariaDB.</summary>
    class procedure ExecuteDeleteBatch(const AContext: IDbContext;
      const ATableName: string;
      WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;
  end;

  /// <summary>
  ///   SQL Server batch DELETE in one statement. The array DML of the driver
  ///   reports the rows it ran, not the rows it deleted, so a key whose row
  ///   was already gone went unnoticed.
  /// </summary>
  TDextSqlServerBatchStrategy = class
  public
    /// <summary>Executes a single-statement batch DELETE for SQL Server.</summary>
    class procedure ExecuteDeleteBatch(const AContext: IDbContext;
      const ATableName: string;
      WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;
  end;

  /// <summary>
  ///   Native Array DML batch strategy for Oracle, Firebird, and fallbacks.
  /// </summary>
  TDextNativeArrayDmlStrategy = class
  public
    /// <summary>Executes native Array DML batch UPDATE.</summary>
    class procedure ExecuteUpdateBatch(const AContext: IDbContext;
      const ATableName: string;
      SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;

    /// <summary>Executes native Array DML batch DELETE.</summary>
    class procedure ExecuteDeleteBatch(const AContext: IDbContext;
      const ATableName: string;
      WhereProps: IList<TPair<TRttiProperty, string>>;
      const AEntities: TArray<TObject>; const ABatchSize: Integer); static;
  end;

implementation

type
  TDEXTBatchHelper = class
  public
    class function GetFieldType(ATypeInfo: PTypeInfo): TFieldType; static;
    class function GetParamType(const AValue: TValue; const AProp: TRttiProperty): TFieldType; static;
    class function ExtractPropValue(const AEntity: TObject;
      const AProp: TRttiProperty; const APropMap: TPropertyMap;
      ADialect: TDatabaseDialect): TValue; static;
  end;

/// <summary>
///   A DELETE that affects fewer rows than it has keys means some row was
///   already gone or changed: SaveChanges raises, as it does for a delete
///   alone (and as EF Core does for every command of a batch). The rows
///   affected come from the driver; -1 means it does not report them.
/// </summary>
procedure CheckDeletedRows(AAffected, AExpected: Integer);
begin
  if (AAffected >= 0) and (AAffected < AExpected) then
    raise EOptimisticConcurrencyException.Create(
      'Concurrency violation: The record has been modified or deleted by another user.');
end;

{ TDEXTBatchHelper }

class function TDEXTBatchHelper.GetFieldType(ATypeInfo: PTypeInfo): TFieldType;
var
  Underlying: PTypeInfo;
begin
  if ATypeInfo = nil then Exit(ftUnknown);
  if IsNullable(ATypeInfo) then
    Underlying := GetUnderlyingType(ATypeInfo)
  else
    Underlying := ATypeInfo;

  if Underlying = nil then Exit(ftUnknown);

  case Underlying.Kind of
    tkInteger: Result := ftInteger;
    tkInt64: Result := ftLargeint;
    tkFloat:
      if Underlying = TypeInfo(TDateTime) then Result := ftDateTime
      else if Underlying = TypeInfo(TDate) then Result := ftDate
      else if Underlying = TypeInfo(TTime) then Result := ftTime
      else Result := ftFloat;
    // Unicode strings must bind as ftWideString, exactly like the single-row path
    // (TFireDACCommand.SetParamValue). ftString makes FireDAC store the value as AnsiString and convert it
    // back with the byte length: on Linux (UTF-8 ANSI) every non-ASCII char leaves a trailing #0 and
    // PostgreSQL rejects the batch with "invalid byte sequence for encoding UTF8: 0x00".
    tkUString, tkWString, tkWChar: Result := ftWideString;
    tkString, tkChar: Result := ftString;
    tkEnumeration:
      if Underlying = TypeInfo(Boolean) then Result := ftBoolean
      else Result := ftInteger;
    else
      Result := ftUnknown;
  end;
end;

class function TDEXTBatchHelper.GetParamType(const AValue: TValue;
  const AProp: TRttiProperty): TFieldType;
begin
  Result := GetFieldType(AValue.TypeInfo);
  // A NULL value carries no type (it is a Variant): FireDAC refuses a
  // parameter without one, so the type comes from the property.
  if (Result = ftUnknown) and (AProp <> nil) then
    Result := GetFieldType(AProp.PropertyType.Handle);
end;

class function TDEXTBatchHelper.ExtractPropValue(const AEntity: TObject;
  const AProp: TRttiProperty; const APropMap: TPropertyMap;
  ADialect: TDatabaseDialect): TValue;
var
  Helper: TNullableHelper;
  Converter: ITypeConverter;
begin
  Result := AProp.GetValue(Pointer(AEntity));
  if IsNullable(Result.TypeInfo) then
  begin
    Helper := TNullableHelper.Create(Result.TypeInfo);
    if Helper.HasValue(Result.GetReferenceToRawData) then
      Result := Helper.GetValue(Result.GetReferenceToRawData)
    else
      Result := TValue.FromVariant(Null);
  end;

  TReflection.TryUnwrapProp(Result, Result);

  Converter := nil;
  if APropMap <> nil then Converter := APropMap.Converter;
  if Converter = nil then
    Converter := TTypeConverterRegistry.Instance.GetConverter(AProp.PropertyType.Handle);
  if (Converter = nil) and (APropMap <> nil) and APropMap.IsJsonColumn then
    Converter := TJsonConverter.Create(APropMap.UseJsonB);

  if Converter <> nil then
    Result := Converter.ToDatabase(Result, ADialect);
end;

{ TDextBatchStrategyFactory }

class procedure TDextBatchStrategyFactory.ExecuteUpdateBatch(
  const AContext: IDbContext; const ATableName: string;
  SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  Dialect: TDatabaseDialect;
begin
  if (Length(AEntities) = 0) or (SetProps.Count = 0) then Exit;
  Dialect := AContext.Dialect.GetDialect;

  case Dialect of
    ddPostgreSQL:
      TDextNativeArrayDmlStrategy.ExecuteUpdateBatch(AContext, ATableName, SetProps, WhereProps, AEntities, ABatchSize);
    ddMySQL, ddMariaDB:
      TDextMySqlBatchStrategy.ExecuteUpdateBatch(AContext, ATableName, SetProps, WhereProps, AEntities, ABatchSize);
    ddOracle, ddFirebird:
      TDextNativeArrayDmlStrategy.ExecuteUpdateBatch(AContext, ATableName, SetProps, WhereProps, AEntities, ABatchSize);
  else
    TDextNativeArrayDmlStrategy.ExecuteUpdateBatch(AContext, ATableName, SetProps, WhereProps, AEntities, ABatchSize);
  end;
end;

class procedure TDextBatchStrategyFactory.ExecuteDeleteBatch(
  const AContext: IDbContext; const ATableName: string;
  WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  Dialect: TDatabaseDialect;
begin
  if (Length(AEntities) = 0) or (WhereProps.Count = 0) then Exit;
  Dialect := AContext.Dialect.GetDialect;

  case Dialect of
    ddPostgreSQL:
      TDextNativeArrayDmlStrategy.ExecuteDeleteBatch(AContext, ATableName, WhereProps, AEntities, ABatchSize);
    ddMySQL, ddMariaDB:
      TDextMySqlBatchStrategy.ExecuteDeleteBatch(AContext, ATableName, WhereProps, AEntities, ABatchSize);
    ddSQLServer:
      TDextSqlServerBatchStrategy.ExecuteDeleteBatch(AContext, ATableName, WhereProps, AEntities, ABatchSize);
  else
    TDextNativeArrayDmlStrategy.ExecuteDeleteBatch(AContext, ATableName, WhereProps, AEntities, ABatchSize);
  end;
end;

{ TDextPostgresBatchStrategy }

class procedure TDextPostgresBatchStrategy.ExecuteUpdateBatch(
  const AContext: IDbContext; const ATableName: string;
  SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  ChunkStart, ChunkCount, TotalCount, EffectiveBatchSize: Integer;
  i, j: Integer;
  Cmd: IDbCommand;
  SB: TStringBuilder;
  Sql: string;
  Prop: TRttiProperty;
  Val: TValue;
  ParamName: string;
  ColName: string;
  DataType: TFieldType;
  Tx: IDbTransaction;
  OwnsTx: Boolean;
begin
  TotalCount := Length(AEntities);
  EffectiveBatchSize := ABatchSize;
  if EffectiveBatchSize <= 0 then EffectiveBatchSize := 100;

  OwnsTx := not AContext.InTransaction;
  if OwnsTx then
    Tx := AContext.Connection.BeginTransaction
  else
    Tx := nil;
  try
    ChunkStart := 0;
    while ChunkStart < TotalCount do
    begin
      if TotalCount - ChunkStart < EffectiveBatchSize then
        ChunkCount := TotalCount - ChunkStart
      else
        ChunkCount := EffectiveBatchSize;

      SB := TStringBuilder.Create;
      try
        // UPDATE "table" AS t SET "c1" = v."c1", "c2" = v."c2"
        SB.Append('UPDATE ').Append(ATableName).Append(' AS t SET ');
        for i := 0 to SetProps.Count - 1 do
        begin
          if i > 0 then SB.Append(', ');
          ColName := AContext.Dialect.QuoteIdentifier(SetProps[i].Value);
          SB.Append(ColName).Append(' = v.').Append(ColName);
        end;

        SB.Append(' FROM (VALUES ');
        for j := 0 to ChunkCount - 1 do
        begin
          if j > 0 then SB.Append(', ');
          SB.Append('(');

          // Append PK values first
          for i := 0 to WhereProps.Count - 1 do
          begin
            if i > 0 then SB.Append(', ');
            SB.Append(':v').Append(IntToStr(j)).Append('_w').Append(IntToStr(i));
          end;

          // Append SET values
          for i := 0 to SetProps.Count - 1 do
          begin
            SB.Append(', ');
            SB.Append(':v').Append(IntToStr(j)).Append('_s').Append(IntToStr(i));
          end;
          SB.Append(')');
        end;

        // AS v("pk1", "pk2", "col1", "col2")
        SB.Append(') AS v(');
        for i := 0 to WhereProps.Count - 1 do
        begin
          if i > 0 then SB.Append(', ');
          SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[i].Value));
        end;
        for i := 0 to SetProps.Count - 1 do
        begin
          SB.Append(', ');
          SB.Append(AContext.Dialect.QuoteIdentifier(SetProps[i].Value));
        end;
        SB.Append(') WHERE ');

        for i := 0 to WhereProps.Count - 1 do
        begin
          if i > 0 then SB.Append(' AND ');
          ColName := AContext.Dialect.QuoteIdentifier(WhereProps[i].Value);
          SB.Append('t.').Append(ColName).Append(' = v.').Append(ColName);
        end;

        Sql := SB.ToString;
      finally
        SB.Free;
      end;

      Cmd := AContext.Connection.CreateCommand(Sql);
      for j := 0 to ChunkCount - 1 do
      begin
        // Add WHERE (PK) params with explicit unwrapped FieldType
        for i := 0 to WhereProps.Count - 1 do
        begin
          Prop := WhereProps[i].Key;
          ParamName := 'v' + IntToStr(j) + '_w' + IntToStr(i);
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          DataType := TDEXTBatchHelper.GetParamType(Val, Prop);
          Cmd.AddParam(ParamName, Val, DataType);
        end;

        // Add SET params with explicit unwrapped FieldType
        for i := 0 to SetProps.Count - 1 do
        begin
          Prop := SetProps[i].Key;
          ParamName := 'v' + IntToStr(j) + '_s' + IntToStr(i);
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          DataType := TDEXTBatchHelper.GetParamType(Val, Prop);
          Cmd.AddParam(ParamName, Val, DataType);
        end;
      end;

      Cmd.ExecuteNonQuery;
      ChunkStart := ChunkStart + ChunkCount;
    end;
    if OwnsTx and (Tx <> nil) then
      Tx.Commit;
  except
    if OwnsTx and (Tx <> nil) then
      Tx.Rollback;
    raise;
  end;
end;

class procedure TDextPostgresBatchStrategy.ExecuteDeleteBatch(
  const AContext: IDbContext; const ATableName: string;
  WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  ChunkStart, ChunkCount, TotalCount, EffectiveBatchSize: Integer;
  i, j: Integer;
  Cmd: IDbCommand;
  SB: TStringBuilder;
  Sql, ParamName: string;
  Prop: TRttiProperty;
  Val: TValue;
  DataType: TFieldType;
  Tx: IDbTransaction;
  OwnsTx: Boolean;
begin
  TotalCount := Length(AEntities);
  EffectiveBatchSize := ABatchSize;
  if EffectiveBatchSize <= 0 then EffectiveBatchSize := 100;

  OwnsTx := not AContext.InTransaction;
  if OwnsTx then
    Tx := AContext.Connection.BeginTransaction
  else
    Tx := nil;
  try
    ChunkStart := 0;
    while ChunkStart < TotalCount do
    begin
      if TotalCount - ChunkStart < EffectiveBatchSize then
        ChunkCount := TotalCount - ChunkStart
      else
        ChunkCount := EffectiveBatchSize;

      SB := TStringBuilder.Create;
      try
        SB.Append('DELETE FROM ').Append(ATableName).Append(' WHERE ');

        if WhereProps.Count = 1 then
        begin
          // Single PK: WHERE "pk" IN (:p0, :p1, ...)
          SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[0].Value)).Append(' IN (');
          for j := 0 to ChunkCount - 1 do
          begin
            if j > 0 then SB.Append(', ');
            SB.Append(':p').Append(IntToStr(j));
          end;
          SB.Append(')');
        end;
        Sql := SB.ToString;
      finally
        SB.Free;
      end;

      Cmd := AContext.Connection.CreateCommand(Sql);
      for j := 0 to ChunkCount - 1 do
      begin
        for i := 0 to WhereProps.Count - 1 do
        begin
          Prop := WhereProps[i].Key;
          ParamName := 'p' + IntToStr(j);
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          DataType := TDEXTBatchHelper.GetParamType(Val, Prop);
          Cmd.AddParam(ParamName, Val, DataType);
        end;
      end;

      CheckDeletedRows(Cmd.ExecuteNonQuery, ChunkCount);
      ChunkStart := ChunkStart + ChunkCount;
    end;
    if OwnsTx and (Tx <> nil) then
      Tx.Commit;
  except
    if OwnsTx and (Tx <> nil) then
      Tx.Rollback;
    raise;
  end;
end;

{ TDextMySqlBatchStrategy }

class procedure TDextMySqlBatchStrategy.ExecuteUpdateBatch(
  const AContext: IDbContext; const ATableName: string;
  SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  ChunkStart, ChunkCount, TotalCount, EffectiveBatchSize: Integer;
  i, j, k: Integer;
  Cmd: IDbCommand;
  SB: TStringBuilder;
  Sql, ParamName, ColName: string;
  Prop: TRttiProperty;
  Val: TValue;
  DataType: TFieldType;
  Tx: IDbTransaction;
  OwnsTx: Boolean;
begin
  TotalCount := Length(AEntities);
  EffectiveBatchSize := ABatchSize;
  if EffectiveBatchSize <= 0 then EffectiveBatchSize := 100;

  OwnsTx := not AContext.InTransaction;
  if OwnsTx then
    Tx := AContext.Connection.BeginTransaction
  else
    Tx := nil;
  try
    ChunkStart := 0;
    while ChunkStart < TotalCount do
    begin
      if TotalCount - ChunkStart < EffectiveBatchSize then
        ChunkCount := TotalCount - ChunkStart
      else
        ChunkCount := EffectiveBatchSize;

      SB := TStringBuilder.Create;
      try
        // UPDATE `table` SET `c1` = CASE WHEN `pk` = :w0 THEN :s0_0 WHEN ... END, ... WHERE `pk` IN (...)
        SB.Append('UPDATE ').Append(ATableName).Append(' SET ');
        for i := 0 to SetProps.Count - 1 do
        begin
          if i > 0 then SB.Append(', ');
          ColName := AContext.Dialect.QuoteIdentifier(SetProps[i].Value);
          SB.Append(ColName).Append(' = CASE ');

          for j := 0 to ChunkCount - 1 do
          begin
            SB.Append('WHEN ');
            for k := 0 to WhereProps.Count - 1 do
            begin
              if k > 0 then SB.Append(' AND ');
              SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[k].Value))
                .Append(' = :w').Append(IntToStr(j)).Append('_').Append(IntToStr(k));
            end;
            SB.Append(' THEN :s').Append(IntToStr(j)).Append('_').Append(IntToStr(i)).Append(' ');
          end;
          SB.Append('END');
        end;

        SB.Append(' WHERE ');
        if WhereProps.Count = 1 then
        begin
          SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[0].Value)).Append(' IN (');
          for j := 0 to ChunkCount - 1 do
          begin
            if j > 0 then SB.Append(', ');
            SB.Append(':w').Append(IntToStr(j)).Append('_0');
          end;
          SB.Append(')');
        end;

        Sql := SB.ToString;
      finally
        SB.Free;
      end;

      Cmd := AContext.Connection.CreateCommand(Sql);
      for j := 0 to ChunkCount - 1 do
      begin
        for k := 0 to WhereProps.Count - 1 do
        begin
          Prop := WhereProps[k].Key;
          ParamName := 'w' + IntToStr(j) + '_' + IntToStr(k);
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          DataType := TDEXTBatchHelper.GetParamType(Val, Prop);
          Cmd.AddParam(ParamName, Val, DataType);
        end;

        for i := 0 to SetProps.Count - 1 do
        begin
          Prop := SetProps[i].Key;
          ParamName := 's' + IntToStr(j) + '_' + IntToStr(i);
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          DataType := TDEXTBatchHelper.GetParamType(Val, Prop);
          Cmd.AddParam(ParamName, Val, DataType);
        end;
      end;

      Cmd.ExecuteNonQuery;
      ChunkStart := ChunkStart + ChunkCount;
    end;
    if OwnsTx and (Tx <> nil) then
      Tx.Commit;
  except
    if OwnsTx and (Tx <> nil) then
      Tx.Rollback;
    raise;
  end;
end;

class procedure TDextMySqlBatchStrategy.ExecuteDeleteBatch(
  const AContext: IDbContext; const ATableName: string;
  WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
begin
  TDextPostgresBatchStrategy.ExecuteDeleteBatch(AContext, ATableName, WhereProps, AEntities, ABatchSize);
end;

{ TDextSqlServerBatchStrategy }

class procedure TDextSqlServerBatchStrategy.ExecuteDeleteBatch(
  const AContext: IDbContext; const ATableName: string;
  WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
const
  // A statement takes at most 2100 parameters.
  MaxParams = 2000;
var
  ChunkStart, ChunkCount, TotalCount, EffectiveBatchSize, i, j: Integer;
  Cmd: IDbCommand;
  SB: TStringBuilder;
  ParamName: string;
  Prop: TRttiProperty;
  Val: TValue;
  Tx: IDbTransaction;
  OwnsTx: Boolean;
begin
  TotalCount := Length(AEntities);
  EffectiveBatchSize := ABatchSize;
  if EffectiveBatchSize <= 0 then EffectiveBatchSize := 100;
  if EffectiveBatchSize * WhereProps.Count > MaxParams then
    EffectiveBatchSize := MaxParams div WhereProps.Count;

  OwnsTx := not AContext.InTransaction;
  if OwnsTx then
    Tx := AContext.Connection.BeginTransaction
  else
    Tx := nil;
  try
    ChunkStart := 0;
    while ChunkStart < TotalCount do
    begin
      if TotalCount - ChunkStart < EffectiveBatchSize then
        ChunkCount := TotalCount - ChunkStart
      else
        ChunkCount := EffectiveBatchSize;

      // WHERE (k1 = :p0_0 AND k2 = :p0_1) OR (k1 = :p1_0 AND k2 = :p1_1) ...
      SB := TStringBuilder.Create;
      try
        SB.Append('DELETE FROM ').Append(ATableName).Append(' WHERE ');
        for j := 0 to ChunkCount - 1 do
        begin
          if j > 0 then SB.Append(' OR ');
          SB.Append('(');
          for i := 0 to WhereProps.Count - 1 do
          begin
            if i > 0 then SB.Append(' AND ');
            SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[i].Value))
              .Append(' = :p').Append(IntToStr(j)).Append('_').Append(IntToStr(i));
          end;
          SB.Append(')');
        end;
        Cmd := AContext.Connection.CreateCommand(SB.ToString);
      finally
        SB.Free;
      end;

      for j := 0 to ChunkCount - 1 do
        for i := 0 to WhereProps.Count - 1 do
        begin
          Prop := WhereProps[i].Key;
          ParamName := 'p' + IntToStr(j) + '_' + IntToStr(i);
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          Cmd.AddParam(ParamName, Val, TDEXTBatchHelper.GetParamType(Val, Prop));
        end;

      CheckDeletedRows(Cmd.ExecuteNonQuery, ChunkCount);
      ChunkStart := ChunkStart + ChunkCount;
    end;
    if OwnsTx and (Tx <> nil) then
      Tx.Commit;
  except
    if OwnsTx and (Tx <> nil) then
      Tx.Rollback;
    raise;
  end;
end;

{ TDextNativeArrayDmlStrategy }

class procedure TDextNativeArrayDmlStrategy.ExecuteUpdateBatch(
  const AContext: IDbContext; const ATableName: string;
  SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  Cmd: IDbCommand;
  ChunkStart, ChunkCount, TotalCount, EffectiveBatchSize, j, i: Integer;
  Prop: TRttiProperty;
  ParamName, Sql: string;
  ParamValues: TArray<TValue>;
  SB: TStringBuilder;
  Tx: IDbTransaction;
  OwnsTx: Boolean;
  Val: TValue;
begin
  TotalCount := Length(AEntities);
  EffectiveBatchSize := ABatchSize;
  if EffectiveBatchSize <= 0 then EffectiveBatchSize := 100;

  OwnsTx := not AContext.InTransaction;
  if OwnsTx then
    Tx := AContext.Connection.BeginTransaction
  else
    Tx := nil;
  try
    ChunkStart := 0;
    while ChunkStart < TotalCount do
    begin
      if TotalCount - ChunkStart < EffectiveBatchSize then
        ChunkCount := TotalCount - ChunkStart
      else
        ChunkCount := EffectiveBatchSize;

      SB := TStringBuilder.Create;
      try
        SB.Append('UPDATE ').Append(ATableName).Append(' SET ');
        for i := 0 to SetProps.Count - 1 do
        begin
          if i > 0 then SB.Append(', ');
          SB.Append(AContext.Dialect.QuoteIdentifier(SetProps[i].Value))
            .Append(' = :s_').Append(IntToStr(i));
        end;
        SB.Append(' WHERE ');
        for i := 0 to WhereProps.Count - 1 do
        begin
          if i > 0 then SB.Append(' AND ');
          SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[i].Value))
            .Append(' = :w_').Append(IntToStr(i));
        end;
        Sql := SB.ToString;
      finally
        SB.Free;
      end;

      Cmd := AContext.Connection.CreateCommand(Sql);

      for i := 0 to SetProps.Count - 1 do
      begin
        Prop := SetProps[i].Key;
        ParamName := 's_' + IntToStr(i);
        Cmd.AddParam(ParamName, TValue.Empty, TDEXTBatchHelper.GetFieldType(Prop.PropertyType.Handle));
      end;
      for i := 0 to WhereProps.Count - 1 do
      begin
        Prop := WhereProps[i].Key;
        ParamName := 'w_' + IntToStr(i);
        Cmd.AddParam(ParamName, TValue.Empty, TDEXTBatchHelper.GetFieldType(Prop.PropertyType.Handle));
      end;

      Cmd.SetArraySize(ChunkCount);

      for i := 0 to SetProps.Count - 1 do
      begin
        Prop := SetProps[i].Key;
        ParamName := 's_' + IntToStr(i);
        SetLength(ParamValues, ChunkCount);
        for j := 0 to ChunkCount - 1 do
        begin
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          ParamValues[j] := Val;
        end;
        Cmd.SetParamArray(ParamName, ParamValues);
      end;

      for i := 0 to WhereProps.Count - 1 do
      begin
        Prop := WhereProps[i].Key;
        ParamName := 'w_' + IntToStr(i);
        SetLength(ParamValues, ChunkCount);
        for j := 0 to ChunkCount - 1 do
        begin
          Val := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
          ParamValues[j] := Val;
        end;
        Cmd.SetParamArray(ParamName, ParamValues);
      end;

      Cmd.ExecuteBatch(ChunkCount);
      ChunkStart := ChunkStart + ChunkCount;
    end;
    if OwnsTx and (Tx <> nil) then
      Tx.Commit;
  except
    if OwnsTx and (Tx <> nil) then
      Tx.Rollback;
    raise;
  end;
end;

class procedure TDextNativeArrayDmlStrategy.ExecuteDeleteBatch(
  const AContext: IDbContext; const ATableName: string;
  WhereProps: IList<TPair<TRttiProperty, string>>;
  const AEntities: TArray<TObject>; const ABatchSize: Integer);
var
  Cmd: IDbCommand;
  ChunkStart, ChunkCount, TotalCount, EffectiveBatchSize, j, i: Integer;
  Prop: TRttiProperty;
  ParamName, Sql: string;
  ParamValues: TArray<TValue>;
  SB: TStringBuilder;
  Tx: IDbTransaction;
  OwnsTx: Boolean;
begin
  TotalCount := Length(AEntities);
  EffectiveBatchSize := ABatchSize;
  if EffectiveBatchSize <= 0 then EffectiveBatchSize := 100;

  OwnsTx := not AContext.InTransaction;
  if OwnsTx then
    Tx := AContext.Connection.BeginTransaction
  else
    Tx := nil;
  try
    ChunkStart := 0;
    while ChunkStart < TotalCount do
    begin
      if TotalCount - ChunkStart < EffectiveBatchSize then
        ChunkCount := TotalCount - ChunkStart
      else
        ChunkCount := EffectiveBatchSize;

      SB := TStringBuilder.Create;
      try
        SB.Append('DELETE FROM ').Append(ATableName).Append(' WHERE ');
        for i := 0 to WhereProps.Count - 1 do
        begin
          if i > 0 then SB.Append(' AND ');
          SB.Append(AContext.Dialect.QuoteIdentifier(WhereProps[i].Value))
            .Append(' = :w_').Append(IntToStr(i));
        end;
        Sql := SB.ToString;
      finally
        SB.Free;
      end;

      Cmd := AContext.Connection.CreateCommand(Sql);
      Cmd.SetArraySize(ChunkCount);

      for i := 0 to WhereProps.Count - 1 do
      begin
        Prop := WhereProps[i].Key;
        ParamName := 'w_' + IntToStr(i);
        SetLength(ParamValues, ChunkCount);
        for j := 0 to ChunkCount - 1 do
          ParamValues[j] := TDEXTBatchHelper.ExtractPropValue(AEntities[ChunkStart + j], Prop, nil, AContext.Dialect.GetDialect);
        Cmd.SetParamArray(ParamName, ParamValues);
      end;

      CheckDeletedRows(Cmd.ExecuteBatch(ChunkCount), ChunkCount);
      ChunkStart := ChunkStart + ChunkCount;
    end;
    if OwnsTx and (Tx <> nil) then
      Tx.Commit;
  except
    if OwnsTx and (Tx <> nil) then
      Tx.Rollback;
    raise;
  end;
end;

end.
