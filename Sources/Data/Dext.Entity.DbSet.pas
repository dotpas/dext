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
unit Dext.Entity.DbSet;

interface

uses
  Data.DB,
  System.Classes,
  System.DateUtils,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  Dext.Collections,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Core.Activator,
  Dext.Core.DirectAccess,
  Dext.Core.Reflection,
  Dext.Core.TypeModel,
  Dext.Core.SmartTypes,
  Dext.Core.ValueConverters,
  Dext.Json,
  Dext.Json.Utf8,
  Dext.Entity.Attributes,
  Dext.Entity.BatchStrategy,
  Dext.Entity.Collections,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.FastQuery,
  Dext.Entity.LazyLoading,
  Dext.Entity.Mapping,
  Dext.Entity.Prototype,
  Dext.Entity.Query,
  Dext.Entity.Tenancy,
  Dext.Entity.TypeConverters,
  Dext.Entity.TypeSystem,
  Dext.MultiTenancy,
  Dext.Specifications.Base,
  Dext.Specifications.Interfaces,
  Dext.Specifications.SQL.Generator,
  Dext.Specifications.Types,
  Dext.Threading.Async,
  Dext.Types.Nullable,
  Dext.Types.UUID,
  Dext.Logging.Tracing,
  System.Diagnostics;

type
  /// <summary>Non-capturing byte sink for direct database JSON projection.</summary>
  TDbProjectionWriteProc = procedure(AContext, AData: Pointer;
    ALength: Integer);

  TColumnHydrationItem = record
    ColumnIndex: Integer;
    Prop: TRttiProperty;
    Field: TRttiField;
    Converter: ITypeConverter;
    DefaultValue: Variant;
    IsMultiMap: Boolean;
    MultiMapPrefix: string;
    ColumnName: string;
    DirectOffset: NativeInt;
    DirectKind: TDextNativeKind;
    DirectDataType: TFieldType;
    UseDirect: Boolean;
  end;

  THydrationPlan = record
    Items: TArray<TColumnHydrationItem>;
    PKColumns: TArray<Integer>;
  end;

  /// <summary>
  ///   Helper class to project raw database query results directly to JSON.
  /// </summary>
  TDbProjectionHelper = class
  private
    class procedure WriteRows(const Reader: IDbReader;
      var Writer: TUtf8JsonWriter); static;
  public
    /// <summary>Writes database rows as JSON to a stream.</summary>
    class procedure ProjectToJson(const Reader: IDbReader;
      AStream: TStream); overload; static;
    /// <summary>Writes database rows as JSON directly to a byte sink.</summary>
    class procedure ProjectToJson(const Reader: IDbReader; AContext: Pointer;
      AWrite: TDbProjectionWriteProc); overload; static;
  end;

  /// <summary>
  ///   Mapping item between database result set column and a DTO property/field.
  /// </summary>
  TDtoColumnMapping = record
    ColumnIndex: Integer;
    Prop: TRttiProperty;
    Field: TRttiField;
    TargetKind: TTypeKind;
    TargetTypeInfo: PTypeInfo;
  end;

  /// <summary>
  ///   Lightweight, high-performance RTTI hydrator for arbitrary DTO and POCO classes.
  /// </summary>
  TDextDtoHydrator = class
  private
    FMappings: TArray<TDtoColumnMapping>;
  public
    constructor Create(ATypeInfo: PTypeInfo; const Reader: IDbReader);
    procedure Hydrate(const Target: TObject; const Reader: IDbReader);
  end;

  /// <summary>
  ///   Concrete implementation of an entity set (DbSet), providing query and persistence operations.
  /// </summary>
  TDbSet<T: class> = class(TInterfacedObject, IDbSet<T>, IDbSet, IDbSetFastStream<T>)
  private
    FColumns: IDictionary<string, string>;
    FContextPtr: Pointer;
    FFields: IDictionary<string, TRttiField>;
    FHydrationPlans: IDictionary<string, THydrationPlan>;
    FIdentityMap: IDictionary<string, T>;
    FIgnoreQueryFilters: Boolean; // Filters control
    FMap: TEntityMap;
    FOnlyDeleted: Boolean;
    FOrphans: IList<T>; // Stores detached objects until DbSet is destroyed
    FPKColumns: IList<string>;
    FProps: IDictionary<string, TRttiProperty>;
    FTableName: string;

    function CreateGenerator: TSqlGenerator<T>;
    function BuildHydrationPlan(const Reader: IDbReader): THydrationPlan;
    function Hydrate(const Reader: IDbReader; const Plan: THydrationPlan; const Tracking: Boolean = True): T;

    procedure ExtractForeignKeys(const AEntities: IList<T>; PropertyToCheck: string; out IDs: IList<TValue>; out FKMap: IDictionary<T, TValue>);
    procedure HandleTimestamps(const AEntity: TObject; AIsInsert: Boolean);
    procedure HydrateTarget(const Reader: IDbReader; Target: T; const Plan: THydrationPlan);
    procedure LoadAndAssign(const AEntities: IList<T>; const NavPropName: string);
    procedure LoadManyToMany(const AEntities: IList<T>; const NavPropName: string; const PropMap: TPropertyMap);
    procedure LoadOneToMany(const AEntities: IList<T>; const NavPropName: string; const PropMap: TPropertyMap);
    procedure MapEntity;
    procedure ResetQueryFlags;
  protected
    function GetEntityId(const AEntity: T): string; overload;
    function GetEntityId(const AEntity: TObject): string; overload;
    function GetPKColumns: TArray<string>;
    function GetRelatedId(const AObject: TObject): TValue;
    function GetItem(Index: Integer): T;

    procedure ApplyTenantFilter(var ASpec: ISpecification<T>);
    procedure StampCurrentTenant(const AEntity: TObject);
    procedure DoLoadIncludes(const AEntities: IList<T>; const AIncludes: TArray<string>);
  public
    constructor Create(const AContext: IDbContext); reintroduce;
    destructor Destroy; override;

    function GetFContext: IDbContext;
    property FContext: IDbContext read GetFContext;

    function GetTableName: string;
    function GetEntityType: PTypeInfo;
    function FindObject(const AId: Variant): TObject; overload;
    function FindObject(const AId: Integer): TObject; overload;
    /// <summary>
    ///   Adds a new entity to the context for later insertion.
    /// </summary>
    function Add(const AEntity: TObject): IDbSet; overload;
    /// <summary>
    ///   Marks an existing entity as modified for later update.
    /// </summary>
    procedure Update(const AEntity: TObject); overload;
    /// <summary>
    ///   Marks an entity for logical or physical deletion.
    /// </summary>
    procedure Remove(const AEntity: TObject); overload;
    function ListObjects(const AExpression: IExpression): IList<TObject>; overload;
    function ListObjects(const ASpec: ISpecification): IList<TObject>; overload;
    procedure PersistAdd(const AEntity: TObject);
    procedure PersistAddRange(const AEntities: TArray<TObject>);
    procedure PersistUpdate(const AEntity: TObject);
    procedure PersistRemove(const AEntity: TObject);
    procedure PersistUpdateRange(const AEntities: TArray<TObject>);
    procedure PersistRemoveRange(const AEntities: TArray<TObject>);
    function IsBulkInsertSafe: Boolean;
    function IsBulkUpdateSafe: Boolean;
    function IsBulkDeleteSafe: Boolean;
    function GenerateCreateTableScript: string;
    procedure Clear;
    procedure DetachAll;
    procedure Detach(const AEntity: TObject); overload;
    procedure LinkManyToMany(const AEntity: TObject; const APropertyName: string; const ARelatedEntity: TObject); overload;
    procedure UnlinkManyToMany(const AEntity: TObject; const APropertyName: string; const ARelatedEntity: TObject); overload;
    
    /// <summary>
    ///   Adds a typed entity to the context.
    /// </summary>
    function Add(const AEntity: T): IDbSet<T>; overload;
    /// <summary>
    ///   Adds an entity using a Fluent Builder for initialization.
    /// </summary>
    function Add(const ABuilder: TFunc<IEntityBuilder<T>, T>): IDbSet<T>; overload;
    /// <summary>
    ///   Marks the typed entity for update.
    /// </summary>
    function Update(const AEntity: T): IDbSet<T>; overload;
    /// <summary>
    ///   Marks the typed entity for deletion.
    /// </summary>
    function Remove(const AEntity: T): IDbSet<T>; overload;
    /// <summary>
    ///   Removes the entity from change tracking without affecting the database.
    /// </summary>
    function Detach(const AEntity: T): IDbSet<T>; overload;
    /// <summary>
    ///   Finds an entity by its primary key (ID), first in cache, then in the database.
    /// </summary>
    function Find(const AId: Variant): T; overload;
    function Find(const AId: Integer): T; overload;
    function Find(const AId: array of Integer): T; overload;
    function Find(const AId: array of Variant): T; overload;

    procedure AddRange(const AEntities: TArray<T>); overload;
    procedure AddRange(const AEntities: IEnumerable<T>); overload;

    procedure UpdateRange(const AEntities: TArray<T>); overload;
    procedure UpdateRange(const AEntities: IEnumerable<T>); overload;

    procedure RemoveRange(const AEntities: TArray<T>); overload;
    procedure RemoveRange(const AEntities: IEnumerable<T>); overload;

    /// <summary>
    ///   Executes the query and returns a list of entities.
    ///   Tracked entities (default) are owned by the DbContext IdentityMap
    ///   and are freed when the DbContext is disposed.
    ///   Use AsNoTracking.ToList to obtain an untracked list owned by the caller.
    /// </summary>
    function ToList: IList<T>; overload;
    function ToList(const ASpec: ISpecification<T>): IList<T>; overload;
    function ToList(const AExpression: IExpression): IList<T>; overload;

    // FastPath Direct Streaming (S57)
    procedure ExecuteToUtf8Proc(const ACallback: TUtf8StreamCallback); overload;
    procedure ExecuteToUtf8Stream(const AStream: TStream); overload;
    function FirstOrDefault(const AExpression: IExpression): T; overload;
    function FirstOrDefault(const ASpec: ISpecification<T>): T; overload;
    function Any(const AExpression: IExpression): Boolean; overload;
    function Any(const ASpec: ISpecification<T>): Boolean; overload;
    function Count(const AExpression: IExpression): Integer; overload;
    function Count(const ASpec: ISpecification<T>): Integer; overload;
    
    // Smart Properties Support
    /// <summary>
    ///   Filters the entity set using a typed boolean expression (LINQ-like).
    ///   Ex: Where(User.Prototype.Name = 'Cesar')
    /// </summary>
    function Where(const APredicate: TQueryPredicate<T>): TFluentQuery<T>; overload;
    function Where(const AValue: BooleanExpression): TFluentQuery<T>; overload;
    function Where(const AExpression: TFluentExpression): TFluentQuery<T>; overload;
    function Where(const AExpression: IExpression): TFluentQuery<T>; overload;

    function Query(const ASpec: ISpecification<T>): TFluentQuery<T>; overload;
    function Query(const AExpression: IExpression): TFluentQuery<T>; overload;
    /// <summary>
    ///   Starts a fluent query over all entities in the set.
    /// </summary>
    function QueryAll: TFluentQuery<T>;
    
    /// <summary>
    ///   Returns a query configured to not track entities.
    ///   Ideal for reports or read-only operations to save memory.
    /// </summary>
    function AsNoTracking: TFluentQuery<T>;

    // Soft Delete Control
    /// <summary>
    ///   Ignores global filters (e.g. Soft Delete) in the current query.
    /// </summary>
    function IgnoreQueryFilters: IDbSet<T>;
    /// <summary>
    ///   Filters only records that suffered logical deletion (Soft Delete).
    /// </summary>
    function OnlyDeleted: IDbSet<T>;
    /// <summary>
    ///   Forces the physical deletion of a record, even if Soft Delete is active.
    /// </summary>
    function HardDelete(const AEntity: T): IDbSet<T>;
    /// <summary>
    ///   Restores a logically deleted entity (Soft Delete).
    /// </summary>
    function Restore(const AEntity: T): IDbSet<T>;

    property Items[Index: Integer]: T read GetItem; default;
    
    /// <summary>
    ///   Returns a "prototype" entity used exclusively for building LINQ expressions.
    ///   The prototype's lifecycle is managed by the DbSet.
    /// </summary>
    function Prototype: T; overload;
    
    /// <summary>
    ///   Returns a prototype of any type for use in complex Joins.
    /// </summary>
    function Prototype<TEntity: class>: TEntity; overload;
    
    /// <summary>
    ///   Links two entities in a Many-to-Many relationship (Intersection Table).
    /// </summary>
    procedure LinkManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntity: TObject); overload;

    /// <summary>
    ///   Removes the link between two entities in a Many-to-Many relationship.
    /// </summary>
    procedure UnlinkManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntity: TObject); overload;
    
    /// <summary>
    ///   Synchronizes a Many-to-Many relationship, replacing existing links with the provided ones.
    /// </summary>
    procedure SyncManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntities: TArray<TObject>);
    
    // New Methods Implementation
    /// <summary>
    ///   Executes the query asynchronously, returning results without blocking the UI thread.
    /// </summary>
    function ToListAsync: TAsyncBuilder<IList<T>>;
    /// <summary>
    ///   Creates a query based on raw SQL, allowing mapping to entities.
    /// </summary>
    function FromSql(const ASql: string; const AParams: array of TValue): TFluentQuery<T>; overload;
    function FromSql(const ASql: string): TFluentQuery<T>; overload;
    function TryLock(const AEntity: T; const AToken: string; ADurationMinutes: Integer = 30): Boolean;
    function Unlock(const AEntity: T): Boolean;

    /// <summary>
    ///   Returns a high-performance iterator that reuses a single object instance (Flyweight pattern).
    ///   Crucial for processing millions of records with low memory footprint (zero GC).
    /// </summary>
    function RequestStreamingIterator(const ASpec: ISpecification<T>): IEnumerator<T>;
    
    class constructor Create;
  end;

  /// <summary>
  ///   Factory for dynamically creating DbSet instances based on RTTI contexts.
  /// </summary>
  TDynamicDbSetFactory<T: class> = class(TInterfacedObject, IDynamicDbSetFactory)
  public
    function CreateDbSet(const AContext: IInterface): IInterface;
  end;

  /// <summary>
  ///   Iterator for traversing query results using raw SQL commands.
  /// </summary>
  TSqlQueryIterator<T: class> = class(TQueryIterator<T>)
  private
    FDbSet: TDbSet<T>;
    FSql: string;
    FParams: TArray<TValue>;
    FReader: IDbReader;
    FInitialized: Boolean;
    FPlan: THydrationPlan;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(ADbSet: TDbSet<T>; const ASql: string; const AParams: array of TValue);
  end;

  /// <summary>
  ///   High-performance "Flyweight" iterator that reuses a single object instance
  ///   during iteration. Optimized for SSR (Server-Side Rendering).
  /// </summary>
  TStreamingViewIterator<T: class> = class(TQueryIterator<T>)
  private
    FDbSet: TDbSet<T>;
    FReader: IDbReader;
    FIteratorObject: T;
    FInitialized: Boolean;
    FSpec: ISpecification<T>;
    FPlan: THydrationPlan;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(ADbSet: TDbSet<T>; const ASpec: ISpecification<T>);
    destructor Destroy; override;
  end;

// Helper function to convert TValue to string for identity map keys
// TValue.ToString does not work correctly for TGUID (returns type name, not value)
function TValueToKeyString(const AValue: TValue): string;
function TValueToVariant(const AValue: TValue): Variant;
function GetFieldType(ATypeInfo: PTypeInfo): TFieldType;

implementation

uses
  System.JSON,
  Dext.Core.DateUtils,
  Dext.Entity.ProxyFactory,
  Dext.Logging.Telemetry,
  Dext.Utils;

function GetFieldType(ATypeInfo: PTypeInfo): TFieldType;
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
    // Unicode strings bind as ftWideString (same as the single-row path); ftString corrupts non-ASCII text
    // in Array DML (see TDEXTBatchHelper.GetFieldType).
    tkUString, tkWString, tkWChar: Result := ftWideString;
    tkString, tkChar: Result := ftString;
    tkEnumeration:
      if Underlying = TypeInfo(Boolean) then Result := ftBoolean
      else Result := ftInteger;
    else
      Result := ftUnknown;
  end;
end;

function TValueToKeyString(const AValue: TValue): string;
var
  V: Variant;
begin
  if AValue.IsEmpty then
    Exit('');

  case AValue.Kind of
    tkInteger:
      Exit(IntToStr(AValue.AsInteger));
    tkInt64:
      Exit(IntToStr(AValue.AsInt64));
    tkUString, tkString, tkWString:
      Exit(AValue.AsString);
  end;

  // Fallback for GUIDs, Nullables, Records, etc.
  V := TValueToVariant(AValue);
  if VarIsNull(V) or VarIsEmpty(V) then
    Exit('');
    
  Result := VarToStr(V);
  
  // Normalize GUIDs to lowercase matches for consistency
  if Result.StartsWith('{') and (Length(Result) = 38) then
    Result := LowerCase(Result);
end;

function TValueToVariant(const AValue: TValue): Variant;
var
  G: TGUID;
  TypeName: string;
  U: TUUID;
  Unwrapped: TValue;
  VTypeName: string;
begin
  if AValue.TypeInfo <> nil then VTypeName := string(AValue.TypeInfo.Name) else VTypeName := 'nil';
  
  if AValue.IsEmpty or ((AValue.Kind = tkUnknown) and (AValue.TypeInfo = nil)) then
    Exit(Null);

  // Use the central reflection utility to unwrap Prop<T>, Nullable<T> and variants
  if TReflection.TryUnwrapProp(AValue, Unwrapped) then
  begin
     // ONLY recurse if the TypeInfo pointer changed 
     if (Unwrapped.TypeInfo <> AValue.TypeInfo) then
        Exit(TValueToVariant(Unwrapped))
     else
        Exit(Unwrapped.AsVariant);
  end;

  if (AValue.Kind = tkVariant) then
    Exit(AValue.AsVariant);

  // Handle explicit types that don't convert to Variant automatically
  if (AValue.Kind = tkRecord) and (AValue.TypeInfo <> nil) then
  begin
    TypeName := string(AValue.TypeInfo.Name);

    if TypeName = 'TGUID' then 
    begin
      AValue.ExtractRawData(@G);
      Exit(GUIDToString(G));
    end;

    if TypeName = 'TUUID' then
    begin
      AValue.ExtractRawData(@U);
      Exit(U.ToString);
    end;
  end;
  
  // Fallback to variant conversion
  try
    Result := AValue.AsVariant;
  except
    on E: Exception do
      Result := AValue.ToString;
  end;
end;

{ TDextDtoHydrator }

constructor TDextDtoHydrator.Create(ATypeInfo: PTypeInfo; const Reader: IDbReader);
var
  RttiCtx: TRttiContext;
  RttiType: TRttiType;
  Props: TArray<TRttiProperty>;
  Fields: TArray<TRttiField>;
  ColCount, i, j: Integer;
  ColName, NormColName, NormMemberName: string;
  Found: Boolean;
  Mapping: TDtoColumnMapping;
  MappingsList: TList<TDtoColumnMapping>;

  function NormalizeName(const S: string): string;
  begin
    Result := StringReplace(LowerCase(S), '_', '', [rfReplaceAll]);
  end;

begin
  RttiCtx := TRttiContext.Create;
  RttiType := RttiCtx.GetType(ATypeInfo);
  if RttiType = nil then Exit;

  Props := RttiType.GetProperties;
  Fields := RttiType.GetFields;
  ColCount := Reader.GetColumnCount;

  MappingsList := TList<TDtoColumnMapping>.Create;
  try
    for i := 0 to ColCount - 1 do
    begin
      ColName := Reader.GetColumnName(i);
      NormColName := NormalizeName(ColName);
      Found := False;

      // 1. Match Properties (case-insensitive & snake_case agnostic)
      for j := 0 to Length(Props) - 1 do
      begin
        if not Props[j].IsWritable then Continue;
        NormMemberName := NormalizeName(Props[j].Name);
        if NormMemberName = NormColName then
        begin
          Mapping.ColumnIndex := i;
          Mapping.Prop := Props[j];
          Mapping.Field := nil;
          Mapping.TargetKind := Props[j].PropertyType.TypeKind;
          Mapping.TargetTypeInfo := Props[j].PropertyType.Handle;
          MappingsList.Add(Mapping);
          Found := True;
          Break;
        end;
      end;

      if Found then Continue;

      // 2. Match Fields (e.g. FValor -> valor, valor_total -> FValorTotal)
      for j := 0 to Length(Fields) - 1 do
      begin
        NormMemberName := NormalizeName(Fields[j].Name);
        if (NormMemberName.Length > 1) and (NormMemberName[1] = 'f') then
          NormMemberName := Copy(NormMemberName, 2, MaxInt);

        if NormMemberName = NormColName then
        begin
          Mapping.ColumnIndex := i;
          Mapping.Prop := nil;
          Mapping.Field := Fields[j];
          Mapping.TargetKind := Fields[j].FieldType.TypeKind;
          Mapping.TargetTypeInfo := Fields[j].FieldType.Handle;
          MappingsList.Add(Mapping);
          Break;
        end;
      end;
    end;

    FMappings := MappingsList.ToArray;
  finally
    MappingsList.Free;
  end;
end;

procedure TDextDtoHydrator.Hydrate(const Target: TObject; const Reader: IDbReader);
var
  i: Integer;
  Mapping: TDtoColumnMapping;
  RawVal, Val: TValue;
begin
  for i := 0 to Length(FMappings) - 1 do
  begin
    Mapping := FMappings[i];
    if Reader.IsNull(Mapping.ColumnIndex) then
      Continue;

    RawVal := Reader.GetValue(Mapping.ColumnIndex);
    if RawVal.IsEmpty then
      Continue;

    case Mapping.TargetKind of
      tkInteger:
        Val := TValue.From<Integer>(RawVal.AsInteger);
      tkInt64:
        Val := TValue.From<Int64>(RawVal.AsInt64);
      tkFloat:
        begin
          if Mapping.TargetTypeInfo = TypeInfo(Currency) then
            Val := TValue.From<Currency>(Currency(RawVal.AsExtended))
          else if (Mapping.TargetTypeInfo = TypeInfo(TDateTime)) or
                  (Mapping.TargetTypeInfo = TypeInfo(TDate)) or
                  (Mapping.TargetTypeInfo = TypeInfo(TTime)) then
            Val := TValue.From<TDateTime>(TDateTime(RawVal.AsExtended))
          else
            Val := TValue.From<Double>(RawVal.AsExtended);
        end;
      tkUString, tkString, tkWString, tkLString:
        Val := TValue.From<string>(RawVal.AsString);
      tkEnumeration:
        begin
          if Mapping.TargetTypeInfo = TypeInfo(Boolean) then
            Val := TValue.From<Boolean>(RawVal.AsBoolean)
          else
            Val := RawVal;
        end;
    else
      Val := RawVal;
    end;

    if Mapping.Prop <> nil then
    begin
      try
        Mapping.Prop.SetValue(Target, Val);
      except
      end;
    end
    else if Mapping.Field <> nil then
    begin
      try
        Mapping.Field.SetValue(Target, Val);
      except
      end;
    end;
  end;
end;

{ TSqlQueryIterator<T> }

constructor TSqlQueryIterator<T>.Create(ADbSet: TDbSet<T>; const ASql: string; const AParams: array of TValue);
var
  I: Integer;
begin
  inherited Create;
  FDbSet := ADbSet;
  FSql := ASql;
  SetLength(FParams, Length(AParams));
  for I := 0 to Length(AParams) - 1 do
    FParams[I] := AParams[I];
end;

function TSqlQueryIterator<T>.MoveNextCore: Boolean;
var
  Cmd: IDbCommand;
  SW: TStopwatch;
begin
  Result := False;
  if not FInitialized then
  begin
    SW := TStopwatch.StartNew;
    try
      Cmd := FDbSet.FContext.Connection.CreateCommand(FSql);
      Cmd.BindSequentialParams(FParams);
      FReader := Cmd.ExecuteQuery;
      FPlan := FDbSet.BuildHydrationPlan(FReader);
      FInitialized := True;
      TDiagnosticSource.Instance.Write('SQL.Query', TJSONObject.Create(TJSONPair.Create('sql', FSql)), 'SQL', SW.ElapsedMilliseconds);
    except
      on E: Exception do
      begin
        TDiagnosticSource.Instance.Write('SQL.Query', TJSONObject.Create(TJSONPair.Create('sql', FSql)), 'SQL', SW.ElapsedMilliseconds, 'Error', E.Message);
        raise;
      end;
    end;
  end;
  
  if FReader.Next then
  begin
    FCurrent := FDbSet.Hydrate(FReader, FPlan, False); // Default to NoTracking for raw SQL for now
    Result := True;
  end;
end;

{ TStreamingViewIterator<T> }

constructor TStreamingViewIterator<T>.Create(ADbSet: TDbSet<T>; const ASpec: ISpecification<T>);
begin
  inherited Create;
  FDbSet := ADbSet;
  FSpec := ASpec;
  // Create the single shared instance for this iterator
  FIteratorObject := TEntityProxyFactory.CreateInstance<T>(FDbSet.FContext);
  FCurrent := FIteratorObject;
end;

destructor TStreamingViewIterator<T>.Destroy;
begin
  FReader := nil;
  // Shared object is managed by the iterator
  FIteratorObject.Free;
  inherited;
end;

function TStreamingViewIterator<T>.MoveNextCore: Boolean;
var
  Cmd: IDbCommand;
  Gen: TSqlGenerator<T>;
  LParamPair: TPair<string, TValue>;
  ParamType: TFieldType;
  SQL: string;
begin
  if not FInitialized then
  begin
    Gen := FDbSet.CreateGenerator;
    try
      SQL := Gen.GenerateSelect(FSpec);
      Cmd := FDbSet.FContext.Connection.CreateCommand(SQL);
      
      for LParamPair in Gen.Params do
      begin
        if Gen.ParamTypes.TryGetValue(LParamPair.Key, ParamType) then
          Cmd.AddParam(LParamPair.Key, LParamPair.Value, ParamType)
        else
          Cmd.AddParam(LParamPair.Key, LParamPair.Value);
      end;
        
      FReader := Cmd.ExecuteQuery;
      FPlan := FDbSet.BuildHydrationPlan(FReader);
    finally
      Gen.Free;
    end;
    FInitialized := True;
  end;
  
  if FReader.Next then
  begin
    FDbSet.HydrateTarget(FReader, FIteratorObject, FPlan);
    Result := True;
  end
  else
    Result := False;
end;

{ TDbSet<T> }

class constructor TDbSet<T>.Create;
begin
  TModelBuilder.Instance.RegisterFactory(TypeInfo(T), TDynamicDbSetFactory<T>.Create);
end;

function TDbSet<T>.GetFContext: IDbContext;
begin
  Result := IDbContext(FContextPtr);
end;

constructor TDbSet<T>.Create(const AContext: IDbContext);
begin
  inherited Create;
  FContextPtr := Pointer(AContext);
  FProps := TCollections.CreateDictionary<string, TRttiProperty>;
  FFields := TCollections.CreateDictionary<string, TRttiField>;
  FHydrationPlans := TCollections.CreateDictionary<string, THydrationPlan>;
  FColumns := TCollections.CreateDictionary<string, string>;
  FPKColumns := TCollections.CreateList<string>;
  FIdentityMap := TCollections.CreateDictionary<string, T>(True);
  FOrphans := TCollections.CreateList<T>(True);
  FIgnoreQueryFilters := False;
  FOnlyDeleted := False;
  MapEntity;
end;

destructor TDbSet<T>.Destroy;
begin
  FIdentityMap := nil;
  FOrphans := nil;
  FProps := nil;
  FFields := nil;
  FHydrationPlans := nil;
  FColumns := nil;
  FPKColumns := nil;
  inherited;
end;

procedure TDbSet<T>.MapEntity;
var
  Attr: TCustomAttribute;
  ColName, FieldName, KeyProp: string;
  Field: TRttiField;
  Handler: IPropertyHandler;
  IsMapped: Boolean;
  Meta: TTypeMetadata;
  PropMap: TPropertyMap;
  SpecTable: TableAttribute;
begin
  Meta := TReflection.GetMetadata(TypeInfo(T));
  FMap := TEntityMap(FContext.GetMapping(TypeInfo(T)));
  FTableName := '';
  if (FMap <> nil) and (FMap.TableName <> '') then
    FTableName := FMap.TableName;
  if FTableName = '' then
  begin
    SpecTable := nil;
    for Attr in Meta.RttiType.GetAttributes do
      if Attr is TableAttribute then
      begin
        SpecTable := TableAttribute(Attr);
        Break;
      end;
      
    if (SpecTable <> nil) and (SpecTable.Name <> '') then
      FTableName := SpecTable.Name;
  end;
  
  if FTableName = '' then
    FTableName := TModelBuilder.Instance.GetDiscoveryName(TypeInfo(T));

  if FTableName = '' then
    FTableName := FContext.NamingStrategy.GetTableName(T);

  for Handler in Meta.GetPropertyHandlers() do
  begin
    IsMapped := True;
    PropMap := nil;
    if FMap <> nil then
    begin
      if FMap.Properties.TryGetValue(Handler.GetName(), PropMap) then
      begin
        if PropMap.IsIgnored then IsMapped := False;
        if PropMap.IsNavigation and not PropMap.IsJsonColumn then IsMapped := False;
      end;
    end;

    if IsMapped and (PropMap = nil) and (Handler.GetMember() is TRttiProperty) and 
       (TRttiProperty(Handler.GetMember()).PropertyType.TypeKind in [tkClass, tkInterface]) then
      IsMapped := False;

    if IsMapped and Handler.GetMember().HasAttribute(NotMappedAttribute) then IsMapped := False;
    
    if not IsMapped then Continue;

    ColName := '';
    if (PropMap <> nil) and (PropMap.ColumnName <> '') then
      ColName := PropMap.ColumnName;
    
    if ColName = '' then
      ColName := Handler.GetColumnName();

    // If ColName matches Property Name, it means it's the default name. 
    // We should apply Naming Strategy (e.g. SnakeCase) if available.
    if (ColName = Handler.GetName()) and (FContext.NamingStrategy <> nil) and (Handler.GetMember() is TRttiProperty) then
      ColName := FContext.NamingStrategy.GetColumnName(TRttiProperty(Handler.GetMember()));

    if ((PropMap <> nil) and PropMap.IsPK) or Handler.GetIsPK() then
    begin
      if not FPKColumns.Contains(ColName) then
        FPKColumns.Add(ColName);
    end;

    if not Handler.GetName().StartsWith('Lazy<') then
      FProps.Add(ColName.ToLower, TRttiProperty(Handler.GetMember()));
      
    FColumns.Add(Handler.GetName(), ColName);
    
    if (PropMap <> nil) and (PropMap.FieldName <> '') then
    begin
      Field := Meta.RttiType.GetField(PropMap.FieldName);
      if Field <> nil then
        FFields.Add(ColName.ToLower, Field);
    end
    else if Handler.GetMember() is TRttiProperty then
    begin
      FieldName := TReflection.NormalizeFieldName(Handler.GetName());
      Field := Meta.RttiType.GetField(FieldName);
      if Field <> nil then
        FFields.Add(ColName.ToLower, Field);
    end;
  end;

  if FPKColumns.Count = 0 then
  begin
    if (FMap <> nil) and (FMap.Keys.Count > 0) then
    begin
      for KeyProp in FMap.Keys do
        if FColumns.ContainsKey(KeyProp) then
          FPKColumns.Add(FColumns[KeyProp]);
    end;
    if FPKColumns.Count = 0 then
    begin
      if FColumns.ContainsKey('Id') then
        FPKColumns.Add(FColumns['Id'])
      else if FColumns.ContainsKey('ID') then
        FPKColumns.Add(FColumns['ID']);
    end;
  end;
end;

function TDbSet<T>.CreateGenerator: TSqlGenerator<T>;
begin
  Result := TSqlGenerator<T>.Create(FContext, FMap, FContext.GetTenantProvider);
  Result.NamingStrategy := FContext.NamingStrategy;
  Result.IgnoreQueryFilters := FIgnoreQueryFilters;
  Result.OnlyDeleted := FOnlyDeleted;
  
  if (FContext.GetTenantProvider <> nil) and (FContext.GetTenantProvider.Tenant <> nil) then
    Result.Schema := FContext.GetTenantProvider.Tenant.Schema;
end;

function TDbSet<T>.GetTableName: string;
var
  Schema: string;
begin
  Result := FContext.Dialect.QuoteIdentifier(FTableName);
  if (FContext.GetTenantProvider <> nil) and (FContext.GetTenantProvider.Tenant <> nil) then
  begin
    Schema := FContext.GetTenantProvider.Tenant.Schema;
    if (Schema <> '') and FContext.Dialect.UseSchemaPrefix then
       Result := FContext.Dialect.QuoteIdentifier(Schema) + '.' + Result;
  end;
end;

function TDbSet<T>.GetEntityType: PTypeInfo;
begin
  Result := TypeInfo(T);
end;

function TDbSet<T>.GetPKColumns: TArray<string>;
begin
  Result := FPKColumns.ToArray;
end;

function TDbSet<T>.GetEntityId(const AEntity: T): string;
var
  i: Integer;
  Prop: TRttiProperty;
  SB: TStringBuilder;
  Val: TValue;
begin
  if FPKColumns.Count = 0 then
    raise Exception.Create('No Primary Key defined for entity ' + FTableName);
  if FPKColumns.Count = 1 then
  begin
    if not FProps.TryGetValue(FPKColumns[0].ToLower, Prop) then
      raise Exception.Create('Primary Key property not found: ' + FPKColumns[0]);
    Val := Prop.GetValue(Pointer(AEntity));
    Result := GetSmartValue(Val, Prop.PropertyType.Name);
  end
  else
  begin
    SB := TStringBuilder.Create;
    try
      for i := 0 to FPKColumns.Count - 1 do
      begin
        if i > 0 then SB.Append('|');
        if not FProps.TryGetValue(FPKColumns[i].ToLower, Prop) then
          raise Exception.Create('Primary Key property not found: ' + FPKColumns[i]);
        Val := Prop.GetValue(Pointer(AEntity));
        SB.Append(GetSmartValue(Val, Prop.PropertyType.Name));
      end;
      Result := SB.ToString;
    finally
      SB.Free;
    end;
  end;
end;

function TDbSet<T>.GetEntityId(const AEntity: TObject): string;
begin
  Result := GetEntityId(T(AEntity));
end;

function TDbSet<T>.GetRelatedId(const AObject: TObject): TValue;
var
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
begin
  Meta := TReflection.GetMetadata(AObject.ClassInfo);
  for Handler in Meta.GetPropertyHandlers do
  begin
    if Handler.GetIsPK then
      Exit(Handler.GetValue(AObject));
  end;
  
  // Fallback to 'Id'
  Handler := Meta.GetHandler('Id');
  if Handler <> nil then
    Exit(Handler.GetValue(AObject));
    
  raise Exception.Create('Could not determine Primary Key for related entity ' + AObject.ClassName);
end;

function TDbSet<T>.BuildHydrationPlan(const Reader: IDbReader): THydrationPlan;
var
  i: Integer;
  ColCount: Integer;
  ColName, ColNameLower: string;
  Prop: TRttiProperty;
  Field: TRttiField;
  PropMap: TPropertyMap;
  Converter: ITypeConverter;
  DefValue: Variant;
  SeparatorIdx: Integer;
  PKCol: string;
  Item: TColumnHydrationItem;
  ItemIdx, PKIdx: Integer;
  Signature: string;
  SignatureBuilder: TStringBuilder;
begin
  ColCount := Reader.GetColumnCount;
  SignatureBuilder := TStringBuilder.Create(ColCount * 24);
  try
    for i := 0 to ColCount - 1 do
    begin
      SignatureBuilder.Append(Reader.GetColumnName(i).ToLower);
      SignatureBuilder.Append(Char(Ord(Reader.GetColumnType(i))));
      SignatureBuilder.Append(#1);
    end;
    Signature := SignatureBuilder.ToString;
  finally
    SignatureBuilder.Free;
  end;

  if FHydrationPlans.TryGetValue(Signature, Result) then
    Exit;

  SetLength(Result.Items, ColCount);
  SetLength(Result.PKColumns, ColCount);
  ItemIdx := 0;
  PKIdx := 0;

  for i := 0 to ColCount - 1 do
  begin
    ColName := Reader.GetColumnName(i);
    ColNameLower := ColName.ToLower;

    // 1. Check if it's a primary key column
    for PKCol in FPKColumns do
    begin
      if SameText(PKCol, ColName) then
      begin
        Result.PKColumns[PKIdx] := i;
        Inc(PKIdx);
        Break;
      end;
    end;

    // 2. Resolve properties / mapping
    if FProps.TryGetValue(ColNameLower, Prop) then
    begin
      PropMap := nil;
      if FMap <> nil then 
        FMap.Properties.TryGetValue(Prop.Name, PropMap);

      DefValue := Null;
      if PropMap <> nil then
        DefValue := PropMap.DefaultValue;

      Converter := nil;
      if PropMap <> nil then 
        Converter := PropMap.Converter;
      if Converter = nil then 
        Converter := TTypeConverterRegistry.Instance.GetConverter(Prop.PropertyType.Handle);
      if (Converter = nil) and (PropMap <> nil) and PropMap.IsJsonColumn then
        Converter := TJsonConverter.Create(PropMap.UseJsonB);

      Field := nil;
      FFields.TryGetValue(ColNameLower, Field);

      Item.ColumnIndex := i;
      Item.Prop := Prop;
      Item.Field := Field;
      Item.Converter := Converter;
      Item.DefaultValue := DefValue;
      Item.IsMultiMap := False;
      Item.MultiMapPrefix := '';
      Item.ColumnName := ColName;
      Item.DirectOffset := -1;
      Item.DirectKind := nkUnknown;
      Item.DirectDataType := ftUnknown;
      Item.UseDirect := False;
      if (PropMap <> nil) and (Converter = nil) and (PropMap.FieldValueOffset > 0) and
         (PropMap.FieldOffset < 0) and (not PropMap.IsLazy) and
         (TDextTypeModel.IsDirectKind(PropMap.NativeKind)) then
      begin
        Item.DirectOffset := PropMap.FieldValueOffset;
        Item.DirectKind := PropMap.NativeKind;
        Item.DirectDataType := PropMap.DataType;
        Item.UseDirect := True;
      end;

      Result.Items[ItemIdx] := Item;
      Inc(ItemIdx);
    end
    else
    begin
      // Multi-Mapping check
      SeparatorIdx := ColName.IndexOf('_');
      if SeparatorIdx < 0 then 
        SeparatorIdx := ColName.IndexOf('.');

      if SeparatorIdx > 0 then
      begin
        Item.ColumnIndex := i;
        Item.Prop := nil;
        Item.Field := nil;
        Item.Converter := nil;
        Item.DefaultValue := Null;
        Item.IsMultiMap := True;
        Item.MultiMapPrefix := ColName.Substring(0, SeparatorIdx);
        Item.ColumnName := ColName;
        Item.DirectOffset := -1;
        Item.DirectKind := nkUnknown;
        Item.UseDirect := False;
        
        // Let's resolve the target class property to make sure it exists
        if FProps.TryGetValue(Item.MultiMapPrefix.ToLower, Prop) and (Prop.PropertyType.TypeKind = tkClass) then
        begin
          Item.Prop := Prop;
          Result.Items[ItemIdx] := Item;
          Inc(ItemIdx);
        end;
      end;
    end;
  end;

  SetLength(Result.Items, ItemIdx);
  SetLength(Result.PKColumns, PKIdx);
  FHydrationPlans.AddOrSetValue(Signature, Result);
end;


function TDbSet<T>.Hydrate(const Reader: IDbReader; const Plan: THydrationPlan; const Tracking: Boolean): T;
var
  DiscVal: Variant;
  PKVal: string;
  SB: TStringBuilder;
  SubMap: TEntityMap;
  i: Integer;
begin
  PKVal := '';
  
  if Length(Plan.PKColumns) > 0 then
  begin
    if Length(Plan.PKColumns) = 1 then
    begin
      PKVal := TValueToKeyString(Reader.GetValue(Plan.PKColumns[0]));
    end
    else
    begin
      SB := TStringBuilder.Create;
      try
        for i := 0 to Length(Plan.PKColumns) - 1 do
        begin
          if i > 0 then SB.Append('|');
          SB.Append(TValueToKeyString(Reader.GetValue(Plan.PKColumns[i])));
        end;
        PKVal := SB.ToString;
      finally
        SB.Free;
      end;
    end;
  end;
  
  // Check IdentityMap
  if Tracking and (PKVal <> '') and FIdentityMap.TryGetValue(PKVal, Result) then
  begin
    TLazyInjector.Inject(FContext, Result);
    Exit;
  end;
  
  // Create new instance with Discriminator support
  if (FMap <> nil) and (FMap.InheritanceStrategy = TInheritanceStrategy.TablePerHierarchy) and 
     (FMap.DiscriminatorColumn <> '') then
  begin
     DiscVal := Reader.GetValue(FMap.DiscriminatorColumn).AsVariant;
     SubMap := FContext.ModelBuilder.FindMapByDiscriminator(TypeInfo(T), DiscVal);
     if (SubMap <> nil) and (SubMap.EntityType <> TypeInfo(T)) then
        Result := T(TActivator.CreateInstance(GetTypeData(SubMap.EntityType)^.ClassType, []))
     else
        Result := TEntityProxyFactory.CreateInstance<T>(FContext);
  end
  else
  begin
    Result := TEntityProxyFactory.CreateInstance<T>(FContext);
  end;

  try
    if Tracking and (PKVal <> '') then
      FIdentityMap.Add(PKVal, Result);
    
    HydrateTarget(Reader, Result, Plan);

    if Tracking and (PKVal <> '') then
    begin
      if (FContext <> nil) and (FContext.ChangeTracker <> nil) then
        FContext.ChangeTracker.Track(Result, esUnchanged);
    end;
  except
    on E: Exception do
    begin
      if not Tracking or (PKVal = '') then
        Result.Free;
      raise;
    end;
  end;
end;


procedure TDbSet<T>.HydrateTarget(const Reader: IDbReader; Target: T; const Plan: THydrationPlan);
var
  i: Integer;
  Val: TValue;
  Item: TColumnHydrationItem;
  PropTypeName: string;
begin
  TLazyInjector.Inject(FContext, Target);
  
  for i := 0 to Length(Plan.Items) - 1 do
  begin
    Item := Plan.Items[i];
    
    if not Item.IsMultiMap then
    begin
      try
        if Item.UseDirect then
        begin
          if not Reader.IsNull(Item.ColumnIndex) then
          begin
            case Item.DirectKind of
              nkInt32:
                TDextDirectAccess.WriteInt32(
                  Target, Item.DirectOffset,
                  Reader.GetInt32(Item.ColumnIndex));
              nkInt64:
                TDextDirectAccess.WriteInt64(
                  Target, Item.DirectOffset,
                  Reader.GetInt64(Item.ColumnIndex));
              nkBoolean:
                TDextDirectAccess.WriteBoolean(
                  Target, Item.DirectOffset,
                  Reader.GetBoolean(Item.ColumnIndex));
              nkSingle:
                TDextDirectAccess.WriteSingle(
                  Target, Item.DirectOffset,
                  Single(Reader.GetDouble(Item.ColumnIndex)));
              nkCurrency:
                TDextDirectAccess.WriteCurrency(
                  Target, Item.DirectOffset,
                  Currency(Reader.GetDouble(Item.ColumnIndex)));
              nkDouble:
                TDextDirectAccess.WriteDouble(
                  Target, Item.DirectOffset,
                  Reader.GetDouble(Item.ColumnIndex));
              nkDateTime:
                TDextDirectAccess.WriteDouble(
                  Target, Item.DirectOffset,
                  Reader.GetDateTime(Item.ColumnIndex));
              nkString:
                TDextDirectAccess.WriteString(
                  Target, Item.DirectOffset,
                  Reader.GetString(Item.ColumnIndex));
            end;
          end
          else
          begin
            if not VarIsNull(Item.DefaultValue) then
            begin
              Val := TValue.FromVariant(Item.DefaultValue);
              case Item.DirectKind of
                nkInt32:
                  TDextDirectAccess.WriteInt32(
                    Target, Item.DirectOffset, Val.AsInteger);
                nkInt64:
                  TDextDirectAccess.WriteInt64(
                    Target, Item.DirectOffset, Val.AsInt64);
                nkBoolean:
                  TDextDirectAccess.WriteBoolean(
                    Target, Item.DirectOffset, Val.AsBoolean);
                nkSingle:
                  TDextDirectAccess.WriteSingle(
                    Target, Item.DirectOffset,
                    Single(Val.AsExtended));
                nkCurrency:
                  TDextDirectAccess.WriteCurrency(
                    Target, Item.DirectOffset, Val.AsCurrency);
                nkDouble:
                  TDextDirectAccess.WriteDouble(
                    Target, Item.DirectOffset, Val.AsExtended);
                nkDateTime:
                  TDextDirectAccess.WriteDouble(
                    Target, Item.DirectOffset, Val.AsExtended);
                nkString:
                  TDextDirectAccess.WriteString(
                    Target, Item.DirectOffset, Val.AsString);
              end;
            end
            else
            begin
              case Item.DirectKind of
                nkInt32:
                  TDextDirectAccess.WriteInt32(
                    Target, Item.DirectOffset, 0);
                nkInt64:
                  TDextDirectAccess.WriteInt64(
                    Target, Item.DirectOffset, 0);
                nkBoolean:
                  TDextDirectAccess.WriteBoolean(
                    Target, Item.DirectOffset, False);
                nkSingle:
                  TDextDirectAccess.WriteSingle(
                    Target, Item.DirectOffset, 0);
                nkCurrency:
                  TDextDirectAccess.WriteCurrency(
                    Target, Item.DirectOffset, 0);
                nkDouble:
                  TDextDirectAccess.WriteDouble(
                    Target, Item.DirectOffset, 0);
                nkDateTime:
                  TDextDirectAccess.WriteDouble(
                    Target, Item.DirectOffset, 0);
                nkString:
                  TDextDirectAccess.WriteString(
                    Target, Item.DirectOffset, '');
              end;
            end;
          end;
          Continue;
        end;

        Val := Reader.GetValue(Item.ColumnIndex);
        if Val.IsEmpty and not VarIsNull(Item.DefaultValue) then
          Val := TValue.FromVariant(Item.DefaultValue);

        if Item.Converter <> nil then
          Val := Item.Converter.FromDatabase(Val, Item.Prop.PropertyType.Handle);
        if Item.Field <> nil then
          TReflection.SetValue(Pointer(Target), Item.Field, Val)
        else
          TReflection.SetValue(Pointer(Target), Item.Prop, Val);
      except
        on E: Exception do
        begin
          PropTypeName := '';
          if (Item.Prop <> nil) and (Item.Prop.PropertyType <> nil) then
            PropTypeName := Item.Prop.PropertyType.Name;
          raise Exception.CreateFmt(
            'Error hydrating %s.%s (property type %s) from column "%s": %s',
            [Target.ClassName, Item.Prop.Name, PropTypeName, Item.ColumnName, E.Message]);
        end;
      end;
    end
    else
    begin
      // Multi-Mapping
      TReflection.SetValueByPath(TObject(Target), Item.ColumnName, Val);
    end;
  end;
end;

function TDbSet<T>.FindObject(const AId: Variant): TObject;
begin
  Result := Find(AId);
end;

function TDbSet<T>.FindObject(const AId: Integer): TObject;
begin
  Result := Find(AId);
end;

function TDbSet<T>.Add(const AEntity: TObject): IDbSet;
begin
  Add(T(AEntity));
  Result := Self;
end;

procedure TDbSet<T>.Update(const AEntity: TObject);
begin
  Update(T(AEntity));
end;

procedure TDbSet<T>.Remove(const AEntity: TObject);
begin
  Remove(T(AEntity));
end;

procedure TDbSet<T>.Detach(const AEntity: TObject);
begin
  Detach(T(AEntity));
end;

function TDbSet<T>.GetItem(Index: Integer): T;
begin
  Result := ToList[Index];
end;

function TDbSet<T>.Add(const AEntity: T): IDbSet<T>;
var
  Id: string;
begin
  FContext.ChangeTracker.Track(AEntity, esAdded);
  
  // Ensure the DbSet owns this entity if it's not already tracked
  Id := GetEntityId(AEntity);
  if (Id = '') or (not FIdentityMap.ContainsKey(Id)) then
  begin
    if not FOrphans.Contains(AEntity) then
      FOrphans.Add(AEntity);
  end;
  
  Result := Self;
end;

function TDbSet<T>.Add(const ABuilder: TFunc<IEntityBuilder<T>, T>): IDbSet<T>;
begin
  if Assigned(ABuilder) then
    Add(ABuilder(TEntityType<T>.New));
  Result := Self;
end;

function TDbSet<T>.Update(const AEntity: T): IDbSet<T>;
var
  Id: string;
  Tracked: T;
begin
  FContext.ChangeTracker.Track(AEntity, esModified);
  
  // Ensure the DbSet owns this entity if it's not already the instance in the identity map
  Id := GetEntityId(AEntity);
  if not (FIdentityMap.TryGetValue(Id, Tracked) and (TObject(Tracked) = TObject(AEntity))) then
  begin
    if not FOrphans.Contains(AEntity) then
      FOrphans.Add(AEntity);
  end;
  
  Result := Self;
end;

function TDbSet<T>.Remove(const AEntity: T): IDbSet<T>;
begin
  FContext.ChangeTracker.Track(AEntity, esDeleted);
  Result := Self;
end;

function TDbSet<T>.Detach(const AEntity: T): IDbSet<T>;
var
  Id: string;
begin
  Id := GetEntityId(AEntity);
  if FIdentityMap.ContainsKey(Id) then
    FOrphans.Add(FIdentityMap.Extract(Id));
  FContext.ChangeTracker.Remove(AEntity);
  Result := Self;
end;

procedure TDbSet<T>.AddRange(const AEntities: TArray<T>);
var
  Entity: T;
begin
  for Entity in AEntities do
    Add(Entity);
end;

procedure TDbSet<T>.AddRange(const AEntities: IEnumerable<T>);
var
  Entity: T;
begin
  for Entity in AEntities do
    Add(Entity);
end;

procedure TDbSet<T>.UpdateRange(const AEntities: TArray<T>);
var
  Entity: T;
begin
  for Entity in AEntities do
    Update(Entity);
end;

procedure TDbSet<T>.UpdateRange(const AEntities: IEnumerable<T>);
var
  Entity: T;
begin
  for Entity in AEntities do
    Update(Entity);
end;

procedure TDbSet<T>.RemoveRange(const AEntities: TArray<T>);
var
  Entity: T;
begin
  for Entity in AEntities do
    Remove(Entity);
end;

procedure TDbSet<T>.RemoveRange(const AEntities: IEnumerable<T>);
var
  Entity: T;
begin
  for Entity in AEntities do
    Remove(Entity);
end;

procedure TDbSet<T>.HandleTimestamps(const AEntity: TObject; AIsInsert: Boolean);
var
  Attr: TCustomAttribute;
  NowVal: TDateTime;
  Prop: TRttiProperty;
  Typ: TRttiType;
begin
  NowVal := Now;
  Typ := TReflection.Context.GetType(T);
  for Prop in Typ.GetProperties do
  begin
    for Attr in Prop.GetAttributes do
    begin
      if (Attr is CreatedAtAttribute) and AIsInsert then
      begin
        TReflection.SetValue(Pointer(AEntity), Prop, NowVal);
      end
      else if (Attr is UpdatedAtAttribute) then
      begin
        TReflection.SetValue(Pointer(AEntity), Prop, NowVal);
      end;
    end;
  end;
end;

procedure TDbSet<T>.PersistAdd(const AEntity: TObject);
var
  Attr, ColAttr: TCustomAttribute;
  AutoIncColumn: string;
  Cmd: IDbCommand;
  Converter: ITypeConverter;
  Generator: TSqlGenerator<T>;
  IdCmd: IDbCommand;
  IdVal: TValue;
  LastIdSQL: string;
  NewId: string;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  PKConvert: TValue;
  PKVal: Variant;
  Prop, AutoIncProp: TRttiProperty;
  PropMap: TPropertyMap;
  ReturningClause: string;
  RetVal, RawPKVal: TValue;
  Sql: string;
  Span: TSpan;
  UseReturning: Boolean;
  ValuesPos: Integer;
begin
  Span := TTracer.BeginSpan('DbSet.Add', 'SQL');
  Span.SetAttribute('entity', string(PTypeInfo(TypeInfo(T)).Name));
  HandleTimestamps(AEntity, True);
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateInsert(T(AEntity));
    // Find AutoInc property and column
    AutoIncColumn := '';
    AutoIncProp := nil;
    for Prop in TReflection.Context.GetType(T).GetProperties do
    begin
      // Check Fluent Mapping first
      PropMap := nil;
      if FMap <> nil then
        FMap.Properties.TryGetValue(Prop.Name, PropMap);
        
      if (PropMap <> nil) and PropMap.IsAutoInc then
      begin
        AutoIncProp := Prop;
        if PropMap.ColumnName <> '' then
          AutoIncColumn := PropMap.ColumnName
        else
          AutoIncColumn := Prop.Name;
        Break;
      end;
      
      // Check Attribute
      for Attr in Prop.GetAttributes do
      begin
        if Attr is AutoIncAttribute then
        begin
          AutoIncProp := Prop;
          AutoIncColumn := Prop.Name;
          // Check for Column attribute
          for ColAttr in Prop.GetAttributes do
            if ColAttr is ColumnAttribute then
              AutoIncColumn := ColumnAttribute(ColAttr).Name;
          Break;
        end;
      end;
      if AutoIncProp <> nil then Break;
    end;

    // Mirror GenerateInsert: apply naming strategy when no explicit column name was mapped
    if (AutoIncProp <> nil) and (AutoIncColumn = AutoIncProp.Name) and (Generator.NamingStrategy <> nil) then
      AutoIncColumn := Generator.NamingStrategy.GetColumnName(AutoIncProp);

    UseReturning := (AutoIncColumn <> '') and FContext.Dialect.SupportsInsertReturning;
    if UseReturning then
    begin
      ReturningClause := FContext.Dialect.GetReturningSQL(AutoIncColumn);
      if FContext.Dialect.GetReturningPosition = rpBeforeValues then
      begin
        ValuesPos := Pos(' VALUES ', UpperCase(Sql));
        if ValuesPos > 0 then
          Insert(' ' + ReturningClause + ' ', Sql, ValuesPos)
        else
          Sql := Sql + ' ' + ReturningClause;
      end
      else
        Sql := Sql + ' ' + ReturningClause;
    end;
    Cmd := FContext.Connection.CreateCommand(Sql);
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    if UseReturning then
    begin
      try
        RetVal := Cmd.ExecuteScalar;
        Span.SetAttribute('sql', Sql);
      except
        on E: Exception do
        begin
          Span.SetStatus('Error', E.Message);
          raise;
        end;
      end;
      RawPKVal := RetVal;
    end
    else
    begin
      try
        Cmd.ExecuteNonQuery;
        Span.SetAttribute('sql', Sql);
      except
        on E: Exception do
        begin
          Span.SetStatus('Error', E.Message);
          raise;
        end;
      end;
      if AutoIncColumn <> '' then
      begin
         LastIdSQL := FContext.Dialect.GetLastInsertIdSQL;
         if LastIdSQL <> '' then
         begin
           IdCmd := FContext.Connection.CreateCommand(LastIdSQL);
           IdVal := IdCmd.ExecuteScalar;
           RawPKVal := IdVal;
         end
         else
         begin
           PKVal := FContext.Connection.GetLastInsertId;
           RawPKVal := TValue.FromVariant(PKVal);
         end;
      end;
    end;
     if (AutoIncProp <> nil) and (AutoIncColumn <> '') then
     begin
       if RawPKVal.IsEmpty and (VarIsNull(PKVal) or VarIsEmpty(PKVal)) then
         raise Exception.Create('Failed to retrieve AutoInc ID for ' + GetTableName + '.');
       
        // Convert raw value using specific type converters BEFORE Reflection assigns it
        PKConvert := RawPKVal;
        Converter := TTypeConverterRegistry.Instance.GetConverter(AutoIncProp.PropertyType.Handle);
        if Converter <> nil then
          PKConvert := Converter.FromDatabase(PKConvert, AutoIncProp.PropertyType.Handle);
          
        // Use centralized reflection helper that handles conversion and Smart Types accurately
        TReflection.SetValue(Pointer(AEntity), AutoIncProp, PKConvert);
      end;
     
     // Add to identity map using full entity ID
     NewId := GetEntityId(T(AEntity)); 
     if not FIdentityMap.ContainsKey(NewId) then
     begin
       if FOrphans.Contains(T(AEntity)) then
         FIdentityMap.Add(NewId, FOrphans.Extract(T(AEntity)))
       else
         FIdentityMap.Add(NewId, T(AEntity));
     end;
  finally
    Generator.Free;
  end;
end;

procedure TDbSet<T>.PersistAddRange(const AEntities: TArray<TObject>);
var
  Cmd: IDbCommand;
  Converter: ITypeConverter;
  DataType: TFieldType;
  EntitiesT: TArray<T>;
  Generator: TSqlGenerator<T>;
  Helper: TNullableHelper;
  i: Integer;
  Pair: TPair<TRttiProperty, string>;
  ParamName: string;
  ParamValues: TArray<TValue>;
  Prop: TRttiProperty;
  PropMap: TPropertyMap;
  Props: IList<TPair<TRttiProperty, string>>;
  Sql: string;
  Val: TValue;
begin
  if Length(AEntities) = 0 then Exit;
  SetLength(EntitiesT, Length(AEntities));
  for i := 0 to High(AEntities) do
  begin
    EntitiesT[i] := T(AEntities[i]);
    HandleTimestamps(AEntities[i], True);
  end;
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateInsertTemplate(Props);
    try
      if Sql = '' then Exit;
      Cmd := FContext.Connection.CreateCommand(Sql) as IDbCommand;
      
      // Pre-initialize parameter types to prevent PostgreSQL typing errors (Bulk operations)
      for Pair in Props do
      begin
        Prop := Pair.Key;
        ParamName := Pair.Value;
        PropMap := nil;
        if FMap <> nil then FMap.Properties.TryGetValue(Prop.Name, PropMap);
        
        if (PropMap <> nil) and (PropMap.DataType <> ftUnknown) then
          DataType := PropMap.DataType
        else
          DataType := GetFieldType(Prop.PropertyType.Handle);

        if DataType <> ftUnknown then
          Cmd.AddParam(ParamName, TValue.Empty, DataType);
      end;
      
      Cmd.SetArraySize(Length(EntitiesT));
      SetLength(ParamValues, Length(EntitiesT));
      for Pair in Props do
      begin
        Prop := Pair.Key;
        ParamName := Pair.Value;
        
        PropMap := nil;
        if FMap <> nil then FMap.Properties.TryGetValue(Prop.Name, PropMap);
        
        Converter := nil;
        if PropMap <> nil then Converter := PropMap.Converter;
        if Converter = nil then Converter := TTypeConverterRegistry.Instance.GetConverter(Prop.PropertyType.Handle);
        if (Converter = nil) and (PropMap <> nil) and PropMap.IsJsonColumn then
          Converter := TJsonConverter.Create(PropMap.UseJsonB);

        for i := 0 to High(EntitiesT) do
        begin
          Val := Prop.GetValue(TObject(EntitiesT[i]));
          if IsNullable(Val.TypeInfo) then
          begin
             Helper := TNullableHelper.Create(Val.TypeInfo);
             if Helper.HasValue(Val.GetReferenceToRawData) then
               ParamValues[i] := Helper.GetValue(Val.GetReferenceToRawData)
             else
               ParamValues[i] := TValue.Empty;
          end
          else
             ParamValues[i] := Val;

          TReflection.TryUnwrapProp(ParamValues[i], ParamValues[i]);

          if Converter <> nil then
            ParamValues[i] := Converter.ToDatabase(ParamValues[i], Generator.GetDialectEnum);
        end;
        Cmd.SetParamArray(ParamName, ParamValues);
      end;
      Cmd.ExecuteBatch(Length(EntitiesT));
    finally
      Props := nil;
    end;
  finally
    Generator.Free;
  end;
end;

procedure TDbSet<T>.PersistUpdateRange(const AEntities: TArray<TObject>);
var
  EntitiesT: TArray<T>;
  Generator: TSqlGenerator<T>;
  i: Integer;
  SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
  Sql: string;
  ChunkSize: Integer;
  TotalCount: Integer;
  EntityIdStr: string;
begin
  if Length(AEntities) = 0 then Exit;
  ChunkSize := FContext.BulkBatchSize;
  if ChunkSize <= 0 then ChunkSize := 100;
  TotalCount := Length(AEntities);
  SetLength(EntitiesT, TotalCount);
  for i := 0 to High(AEntities) do
  begin
    EntitiesT[i] := T(Pointer(AEntities[i]));
    HandleTimestamps(AEntities[i], False);
    StampCurrentTenant(AEntities[i]);
  end;
  
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateUpdateTemplate(SetProps, WhereProps);
    try
      if Sql = '' then Exit;
      
      TDextBatchStrategyFactory.ExecuteUpdateBatch(FContext, GetTableName, SetProps, WhereProps, AEntities, ChunkSize);
      
      for i := 0 to High(EntitiesT) do
      begin
        EntityIdStr := GetEntityId(EntitiesT[i]);
        if not FIdentityMap.ContainsKey(EntityIdStr) then
        begin
           if FOrphans.Contains(EntitiesT[i]) then
             FIdentityMap.Add(EntityIdStr, FOrphans.Extract(EntitiesT[i]))
           else
             FIdentityMap.Add(EntityIdStr, EntitiesT[i]);
        end;
      end;
    finally
      SetProps := nil;
      WhereProps := nil;
    end;
  finally
    Generator.Free;
  end;
end;

procedure TDbSet<T>.PersistRemoveRange(const AEntities: TArray<TObject>);
var
  EntitiesT: TArray<T>;
  Generator: TSqlGenerator<T>;
  i: Integer;
  WhereProps: IList<TPair<TRttiProperty, string>>;
  Sql: string;
  ChunkSize: Integer;
  TotalCount: Integer;
begin
  if Length(AEntities) = 0 then Exit;
  ChunkSize := FContext.BulkBatchSize;
  if ChunkSize <= 0 then ChunkSize := 100;
  TotalCount := Length(AEntities);
  SetLength(EntitiesT, TotalCount);
  for i := 0 to High(AEntities) do
  begin
    EntitiesT[i] := T(Pointer(AEntities[i]));
    StampCurrentTenant(AEntities[i]);
  end;
    
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateDeleteTemplate(WhereProps);
    try
      if Sql = '' then Exit;
      
      TDextBatchStrategyFactory.ExecuteDeleteBatch(FContext, GetTableName, WhereProps, AEntities, ChunkSize);
      
      for i := 0 to High(EntitiesT) do
        FIdentityMap.Remove(GetEntityId(EntitiesT[i]));
    finally
      WhereProps := nil;
    end;
  finally
    Generator.Free;
  end;
end;

function TDbSet<T>.IsBulkInsertSafe: Boolean;
var
  Handler: IPropertyHandler;
  Meta: TTypeMetadata;
  PropMap: TPropertyMap;
  IsAutoInc: Boolean;
begin
  Result := True;
  
  // Check mapping for shadow properties
  if FMap <> nil then
  begin
    for PropMap in FMap.Properties.Values do
    begin
      if PropMap.IsShadow then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

  Meta := TReflection.GetMetadata(TypeInfo(T));
  for Handler in Meta.GetPropertyHandlers() do
  begin
    IsAutoInc := Handler.GetIsAutoInc();
    if FMap <> nil then
    begin
      if FMap.Properties.TryGetValue(Handler.GetName(), PropMap) then
      begin
        if PropMap.IsAutoInc then IsAutoInc := True;
        if PropMap.IsSequenced then IsAutoInc := False;
      end;
    end;
    if IsAutoInc then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function TDbSet<T>.IsBulkUpdateSafe: Boolean;
var
  Handler: IPropertyHandler;
  Meta: TTypeMetadata;
  PropMap: TPropertyMap;
begin
  Result := True;
  
  // Check mapping for shadow properties
  if FMap <> nil then
  begin
    for PropMap in FMap.Properties.Values do
    begin
      if PropMap.IsShadow then
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

  Meta := TReflection.GetMetadata(TypeInfo(T));
  for Handler in Meta.GetPropertyHandlers() do
  begin
    if Handler.GetMember().HasAttribute(VersionAttribute) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

function TDbSet<T>.IsBulkDeleteSafe: Boolean;
var
  Attr: TCustomAttribute;
  RType: TRttiType;
  PropMap: TPropertyMap;
begin
  Result := True;
  
  // 1. Check Fluent Mapping for soft delete
  if (FMap <> nil) and FMap.IsSoftDelete then
  begin
    Exit(False);
  end;
  
  if FMap <> nil then
  begin
    for PropMap in FMap.Properties.Values do
    begin
      if PropMap.IsDeletedAt then
        Exit(False);
    end;
  end;
  
  // 2. Check Attribute for soft delete
  RType := TReflection.Context.GetType(T);
  if RType <> nil then
  begin
    for Attr in RType.GetAttributes do
    begin
      if Attr is SoftDeleteAttribute then
        Exit(False);
    end;
  end;
end;

procedure TDbSet<T>.PersistUpdate(const AEntity: TObject);
var
  Cmd: IDbCommand;
  Generator: TSqlGenerator<T>;
  Handler: IPropertyHandler;
  Meta: TTypeMetadata;
  NewVer: Integer;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  Prop: TRttiProperty;
  RowsAffected: Integer;
  Sql, Id: string;
  Val: TValue;
  Span: TSpan;
begin
  Span := TTracer.BeginSpan('DbSet.Update', 'SQL');
  Span.SetAttribute('entity', string(PTypeInfo(TypeInfo(T)).Name));
  HandleTimestamps(AEntity, False);
  StampCurrentTenant(AEntity);
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateUpdate(T(AEntity));
    Cmd := FContext.Connection.CreateCommand(Sql);
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    try
      RowsAffected := Cmd.ExecuteNonQuery;
      Span.SetAttribute('sql', Sql);
      Span.SetAttribute('rows', RowsAffected);
    except
      on E: Exception do
      begin
        Span.SetStatus('Error', E.Message);
        raise;
      end;
    end;
    
    if RowsAffected = 0 then
      raise EOptimisticConcurrencyException.Create('Concurrency violation: The record has been modified or deleted by another user.');
    
    Meta := TReflection.GetMetadata(TypeInfo(T));
    for Handler in Meta.GetPropertyHandlers() do
    begin
      if Handler.GetMember().HasAttribute(VersionAttribute) then
      begin
        Prop := TRttiProperty(Handler.GetMember());
        Val := Prop.GetValue(Pointer(AEntity));
        if Val.IsEmpty then NewVer := 1 else NewVer := Val.AsInteger + 1;
        TReflection.SetValue(Pointer(AEntity), Prop, NewVer);
        Break;
      end;
    end;

    // After successful update, ensure it's in the Identity Map and not in Orphans
    Id := GetEntityId(T(AEntity));
    if not FIdentityMap.ContainsKey(Id) then
    begin
       if FOrphans.Contains(T(AEntity)) then
         FIdentityMap.Add(Id, FOrphans.Extract(T(AEntity)))
       else
         FIdentityMap.Add(Id, T(AEntity));
    end;
  finally
    Generator.Free;
  end;
end;

procedure TDbSet<T>.PersistRemove(const AEntity: TObject);
var
  Attr: TCustomAttribute;
  Cmd: IDbCommand;
  DeletedVal: Variant;
  Generator: TSqlGenerator<T>;
  IsSoftDelete: Boolean;
  Key: string;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  Prop: TRttiProperty;
  PropName: string;
  PropMap: TPropertyMap;
  RowsAffected: Integer;
  RType: TRttiType;
  SoftDeleteAttr: SoftDeleteAttribute;
  Sql: string;
  ValToSet: TValue;
  Span: TSpan;
  NowVal: TDateTime;
  HasChanged: Boolean;
begin
  Span := TTracer.BeginSpan('DbSet.Delete', 'SQL');
  Span.SetAttribute('entity', string(PTypeInfo(TypeInfo(T)).Name));
  IsSoftDelete := False;
  PropName := '';
  
  // 1. Check Fluent Mapping
  if (FMap <> nil) and FMap.IsSoftDelete then
  begin
    IsSoftDelete := True;
    PropName := FMap.SoftDeleteProp;
    DeletedVal := FMap.SoftDeleteDeletedValue;
  end
  // 2. Check Attribute
  else
  begin
    RType := TReflection.Context.GetType(T);
    if RType <> nil then
    begin
      for Attr in RType.GetAttributes do
      begin
        if Attr is SoftDeleteAttribute then
        begin
          SoftDeleteAttr := SoftDeleteAttribute(Attr);
          IsSoftDelete := True;
          PropName := SoftDeleteAttr.ColumnName;
          DeletedVal := SoftDeleteAttr.DeletedValue;
          Break;
        end;
      end;
    end;
  end;
  
  NowVal := Now;
  HasChanged := False;
  
  // Check if any property in Fluent Mapping is marked as DeletedAt
  if (not IsSoftDelete) and (FMap <> nil) then
  begin
    for PropMap in FMap.Properties.Values do
    begin
      if PropMap.IsDeletedAt then
      begin
        IsSoftDelete := True; // If we have DeletedAt, it IS a soft delete
        Break;
      end;
    end;
  end;
  
  if IsSoftDelete then
  begin
    // Soft Delete: UPDATE entity to mark as deleted
    RType := TReflection.Context.GetType(T);
    if RType <> nil then
    begin
      for Prop in RType.GetProperties do
      begin
        PropMap := nil;
        if (FMap <> nil) then FMap.Properties.TryGetValue(Prop.Name, PropMap);
        
        // Priority 1: Check if it's a [DeletedAt] field (Fluent or Attribute)
        if (PropMap <> nil) and PropMap.IsDeletedAt then
        begin
          ValToSet := TValue.From<TDateTime>(NowVal);
          TReflection.SetValue(Pointer(AEntity), Prop, ValToSet);
          HasChanged := True;
        end;

        // Priority 2: Check if it's the specific SoftDelete filter property
        if (PropName <> '') and not ((PropMap <> nil) and PropMap.IsDeletedAt) then
        begin
          if SameText(Prop.Name, PropName) then
          begin
            if Prop.PropertyType.Handle = TypeInfo(Boolean) then
              ValToSet := TValue.From(Boolean(DeletedVal))
            else
              ValToSet := TValue.FromVariant(DeletedVal);
              
            TReflection.SetValue(Pointer(AEntity), Prop, ValToSet);
            HasChanged := True;
          end;
        end;
      end;
      
      if HasChanged then
      begin
        // Use PersistUpdate to save the change
        PersistUpdate(T(AEntity));
          
        // Remove from identity map (entity is "deleted" from context perspective)
        Key := GetEntityId(T(AEntity));
        if FIdentityMap.ContainsKey(Key) then
          FIdentityMap.Remove(Key)
        else
          AEntity.Free;
        Exit;
      end;
    end;
  end;
  
  // Hard Delete: Physical DELETE from database
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateDelete(T(AEntity));
    Cmd := FContext.Connection.CreateCommand(Sql);
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    try
      RowsAffected := Cmd.ExecuteNonQuery;
      Span.SetAttribute('sql', Sql);
      Span.SetAttribute('rows', RowsAffected);
    except
      on E: Exception do
      begin
        Span.SetStatus('Error', E.Message);
        raise;
      end;
    end;
    FIdentityMap.Remove(GetEntityId(T(AEntity)));
  finally
    Generator.Free;
  end;
end;

function TDbSet<T>.TryLock(const AEntity: T; const AToken: string; ADurationMinutes: Integer): Boolean;
var
  Cmd: IDbCommand;
  CurCol: string;
  Done: Boolean;
  i: Integer;
  PKCols: TArray<string>;
  PMap: TPropertyMap;
  Prop, TokenProp, ExpiryProp: TRttiProperty;
  Sql: string;
  TokenCol, ExpiryCol: string;
  Typ: TRttiType;
begin
  Result := False;
  TokenProp := nil;
  ExpiryProp := nil;
  TokenCol := '';
  ExpiryCol := '';

  Typ := TReflection.Context.GetType(T);
  for Prop in Typ.GetProperties do
  begin
    if Prop.HasAttribute<LockTokenAttribute> then TokenProp := Prop;
    if Prop.HasAttribute<LockExpirationAttribute> then ExpiryProp := Prop;
  end;

  if (TokenProp = nil) or (ExpiryProp = nil) then
    raise Exception.Create('Entity ' + Typ.Name + ' does not have [LockToken] and [LockExpiration] attributes.');

  // Find Column Names
  TokenCol := TokenProp.Name;
  ExpiryCol := ExpiryProp.Name;
  if FMap <> nil then
  begin
    if FMap.Properties.TryGetValue(TokenProp.Name, PMap) and (PMap.ColumnName <> '') then TokenCol := PMap.ColumnName;
    if FMap.Properties.TryGetValue(ExpiryProp.Name, PMap) and (PMap.ColumnName <> '') then ExpiryCol := PMap.ColumnName;
  end;

  // Build atomic update
  // UPDATE Table SET Token = :me, Expiry = :future 
  // WHERE PK = :id AND (Token IS NULL OR Token = :me OR Expiry < :now)
  PKCols := GetPKColumns;
  if Length(PKCols) = 0 then raise Exception.Create('Entity must have a primary key for locking.');

  Sql := Format('UPDATE %s SET %s = :token, %s = :expiry WHERE ', 
    [GetTableName, FContext.Dialect.QuoteIdentifier(TokenCol), FContext.Dialect.QuoteIdentifier(ExpiryCol)]);

  for i := 0 to High(PKCols) do
  begin
    if i > 0 then Sql := Sql + ' AND ';
    Sql := Sql + FContext.Dialect.QuoteIdentifier(PKCols[i]) + ' = :pk' + IntToStr(i);
  end;

  Sql := Sql + Format(' AND (%s IS NULL OR %s = :token OR %s < :now)', 
    [FContext.Dialect.QuoteIdentifier(TokenCol), FContext.Dialect.QuoteIdentifier(TokenCol), FContext.Dialect.QuoteIdentifier(ExpiryCol)]);

  Cmd := FContext.Connection.CreateCommand(Sql);
  Cmd.AddParam('token', AToken);
  Cmd.AddParam('expiry', Now + (ADurationMinutes / 1440.0));
  Cmd.AddParam('now', Now);

  // Add PK Params
  // Extract PK values from entity
  for i := 0 to High(PKCols) do
  begin
    // Simple lookup: Find property matching PK column or name
    Done := False;
    for Prop in Typ.GetProperties do
    begin
       CurCol := Prop.Name;
       if FMap <> nil then
       begin
         if FMap.Properties.TryGetValue(Prop.Name, PMap) and (PMap.ColumnName <> '') then CurCol := PMap.ColumnName;
       end;
       if SameText(CurCol, PKCols[i]) then
       begin
         Cmd.AddParam('pk' + IntToStr(i), Prop.GetValue(Pointer(AEntity)));
         Done := True;
         Break;
       end;
    end;
    if not Done then raise Exception.Create('Could not find PK property for ' + PKCols[i]);
  end;

  if Cmd.ExecuteNonQuery = 1 then
  begin
    // Update local entity
    TokenProp.SetValue(Pointer(AEntity), AToken);
    ExpiryProp.SetValue(Pointer(AEntity), Now + (ADurationMinutes / 1440.0));
    Result := True;
  end;
end;

function TDbSet<T>.Unlock(const AEntity: T): Boolean;
var
  Cmd: IDbCommand;
  CurCol: string;
  i: Integer;
  PKCols: TArray<string>;
  PMap: TPropertyMap;
  Prop, TokenProp, ExpiryProp: TRttiProperty;
  Sql: string;
  TokenCol, ExpiryCol: string;
  Typ: TRttiType;
begin
  Result := False;
  TokenProp := nil;
  ExpiryProp := nil;

  Typ := TReflection.Context.GetType(T);
  for Prop in Typ.GetProperties do
  begin
    if Prop.HasAttribute<LockTokenAttribute> then TokenProp := Prop;
    if Prop.HasAttribute<LockExpirationAttribute> then ExpiryProp := Prop;
  end;

  if (TokenProp = nil) or (ExpiryProp = nil) then Exit;

  // Find Column Names
  TokenCol := TokenProp.Name;
  ExpiryCol := ExpiryProp.Name;
  if FMap <> nil then
  begin
    if FMap.Properties.TryGetValue(TokenProp.Name, PMap) and (PMap.ColumnName <> '') then TokenCol := PMap.ColumnName;
    if FMap.Properties.TryGetValue(ExpiryProp.Name, PMap) and (PMap.ColumnName <> '') then ExpiryCol := PMap.ColumnName;
  end;

  PKCols := GetPKColumns;
  Sql := Format('UPDATE %s SET %s = NULL, %s = NULL WHERE ', 
    [GetTableName, FContext.Dialect.QuoteIdentifier(TokenCol), FContext.Dialect.QuoteIdentifier(ExpiryCol)]);

  for i := 0 to High(PKCols) do
  begin
    if i > 0 then Sql := Sql + ' AND ';
    Sql := Sql + FContext.Dialect.QuoteIdentifier(PKCols[i]) + ' = :pk' + IntToStr(i);
  end;

  Cmd := FContext.Connection.CreateCommand(Sql);
  for i := 0 to High(PKCols) do
  begin
    for Prop in Typ.GetProperties do
    begin
       CurCol := Prop.Name;
       if FMap <> nil then
       begin
         if FMap.Properties.TryGetValue(Prop.Name, PMap) and (PMap.ColumnName <> '') then CurCol := PMap.ColumnName;
       end;
       if SameText(CurCol, PKCols[i]) then
       begin
         Cmd.AddParam('pk' + IntToStr(i), Prop.GetValue(Pointer(AEntity)));
         Break;
       end;
    end;
  end;

  if Cmd.ExecuteNonQuery = 1 then
  begin
    TokenProp.SetValue(Pointer(AEntity), TValue.Empty);
    ExpiryProp.SetValue(Pointer(AEntity), TValue.Empty);
    Result := True;
  end;
end;

function TDbSet<T>.GenerateCreateTableScript: string;
var
  Generator: TSqlGenerator<T>;
begin
  Generator := CreateGenerator;
  try
    Result := Generator.GenerateCreateTable(GetTableName);
  finally
    Generator.Free;
  end;
end;

procedure TDbSet<T>.Clear;
begin
  FIdentityMap.Clear;
  FOrphans.Clear;
end;

procedure TDbSet<T>.DetachAll;
var
  Key: string;
  Keys: TArray<string>;
  Val: T;
begin
  Keys := FIdentityMap.Keys;
  for Key in Keys do
  begin
    if FIdentityMap.ContainsKey(Key) then
    begin
      Val := FIdentityMap.Extract(Key);
      if Val <> nil then
        FOrphans.Add(Val);
    end;
  end;
end;

function TDbSet<T>.ListObjects(const AExpression: Dext.Specifications.Interfaces.IExpression): IList<TObject>;
var
  i: Integer;
  Items: IList<T>;
begin
  Items := ToList(AExpression);
  Result := TCollections.CreateList<TObject>;
  for i := 0 to Items.Count - 1 do
    Result.Add(TObject(Items[i]));
end;

function TDbSet<T>.ListObjects(const ASpec: Dext.Specifications.Interfaces.ISpecification): IList<TObject>;
var
  i: Integer;
  Incl: string;
  Items: IList<T>;
  Order: IOrderBy;
  TypedSpec: ISpecification<T>;
begin
  if ASpec = nil then
    Exit(ListObjects(IExpression(nil)));

  Result := TCollections.CreateList<TObject>;
  
  if Supports(ASpec, ISpecification<T>, TypedSpec) then
  begin
    Items := ToList(TypedSpec);
  end
  else
  begin
    TypedSpec := TSpecification<T>.Create;
    if ASpec.Expression <> nil then
       TypedSpec.Where(ASpec.Expression);
       
    if ASpec.IsPagingEnabled then
    begin
      TypedSpec.Skip(ASpec.GetSkip);
      TypedSpec.Take(ASpec.GetTake);
    end;
    
    for Order in ASpec.GetOrderBy do
      TypedSpec.OrderBy(Order);
      
    for Incl in ASpec.GetIncludes do
      TypedSpec.Include(Incl);
      
    Items := ToList(TypedSpec);
  end;

  for i := 0 to Items.Count - 1 do
    Result.Add(TObject(Items[i]));
end;

function TDbSet<T>.ToList: IList<T>;
begin
  Result := ToList(ISpecification<T>(nil));
end;

procedure TDbSet<T>.ExecuteToUtf8Proc(const ACallback: TUtf8StreamCallback);
var
  Generator: TSqlGenerator<T>;
  Sql: string;
  FastQuery: TDextFastQuery;
begin
  if not Assigned(ACallback) then Exit;
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateSelect;
    FastQuery := TDextFastQuery.Create(FContext.Connection, Sql);
    try
      FastQuery.ExecuteToUtf8Proc(
        procedure(Buffer: Pointer; Length: Integer)
        begin
          ACallback(Buffer, Length);
        end
      );
    finally
      FastQuery.Free;
    end;
  finally
    Generator.Free;
  end;
end;

procedure TDbSet<T>.ExecuteToUtf8Stream(const AStream: TStream);
var
  Generator: TSqlGenerator<T>;
  Sql: string;
  FastQuery: TDextFastQuery;
begin
  if AStream = nil then Exit;
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateSelect;
    FastQuery := TDextFastQuery.Create(FContext.Connection, Sql);
    try
      FastQuery.ExecuteToUtf8Stream(AStream);
    finally
      FastQuery.Free;
    end;
  finally
    Generator.Free;
  end;
end;

function TDbSet<T>.ToListAsync: TAsyncBuilder<IList<T>>;
begin
  if not FContext.Connection.Pooled then
    raise Exception.Create('ToListAsync requires a pooled connection to ensure thread safety.');

  Result := TAsyncTask.Run<IList<T>>(
    TFunc<IList<T>>(function: IList<T>
      begin
        Result := Self.ToList;
      end));
end;

function TDbSet<T>.ToList(const AExpression: IExpression): IList<T>;
var
  Spec: ISpecification<T>;
begin
  Spec := TSpecification<T>.Create(AExpression);
  Result := ToList(Spec);
end;

function TDbSet<T>.ToList(const ASpec: ISpecification<T>): IList<T>;
var
  Cmd: IDbCommand;
  Entity: T;
  Generator: TSqlGenerator<T>;
  IsProjection: Boolean;
  LSpec: ISpecification<T>;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  Reader: IDbReader;
  RowCount: Integer;
  Sql: string;
  Tracking: Boolean;
  Span: TSpan;
  LPlan: THydrationPlan;
  SW: TStopwatch;
  PlanTime, HydrationTime: Int64;
  LList: TList<T>;
begin
  LSpec := ASpec;
 
  // Propagate spec-level filter flags to DbSet state for this query execution.
  // ResetQueryFlags in the finally block ensures these do not leak between calls.
  if (LSpec <> nil) and LSpec.IsIgnoringFilters then
    FIgnoreQueryFilters := True;
  if (LSpec <> nil) and LSpec.IsOnlyDeleted then
    FOnlyDeleted := True;
 
  ApplyTenantFilter(LSpec);
 
  Span := TTracer.BeginSpan('DbSet.ToList', 'SQL');
  Span.SetAttribute('entity', string(PTypeInfo(TypeInfo(T)).Name));
 
  IsProjection := (LSpec <> nil) and (Length(LSpec.GetSelectedColumns) > 0);
  
  // Tracking defaults to True
  // If Spec is provided, respect its setting
  if LSpec <> nil then
    Tracking := LSpec.IsTrackingEnabled
  else
    Tracking := True;
 
  // Projections FORCE tracking off regardless of Spec setting
  if IsProjection then
    Tracking := False;
 
  if PTypeInfo(TypeInfo(T)).Kind = tkClass then
    LList := TList<T>.Create(not Tracking)
  else
    LList := TList<T>.Create;
    
  if (LSpec <> nil) and (LSpec.GetTake > 0) then
    LList.Capacity := LSpec.GetTake
  else
    LList.Capacity := 64; // Default initial capacity to avoid early resizing
    
  Result := LList;
 
  Generator := CreateGenerator;
  try
    if LSpec <> nil then
      Sql := Generator.GenerateSelect(LSpec)
    else
      Sql := Generator.GenerateSelect;
      
    Cmd := FContext.Connection.CreateCommand(Sql);
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    
    try
      Reader := Cmd.ExecuteQuery;
      RowCount := 0;
      
      SW := TStopwatch.StartNew;
      LPlan := BuildHydrationPlan(Reader);
      PlanTime := SW.ElapsedMilliseconds;
      
      SW := TStopwatch.StartNew;
      while Reader.Next do
      begin
        Inc(RowCount);
        Entity := Hydrate(Reader, LPlan, Tracking);
        LList.Add(Entity);
      end;
      HydrationTime := SW.ElapsedMilliseconds;
      
      Span.SetAttribute('rows', RowCount);
      Span.SetAttribute('sql', Sql);
      Span.SetAttribute('plan_build_ms', PlanTime);
      Span.SetAttribute('hydration_loop_ms', HydrationTime);
    except
      on E: Exception do
      begin
        Span.SetStatus('Error', E.Message);
        raise;
      end;
    end;
 
    if (LSpec <> nil) and (Length(LSpec.GetIncludes) > 0) then
      DoLoadIncludes(Result, LSpec.GetIncludes);
  finally
    Generator.Free;
    ResetQueryFlags;
  end;
end;

function TDbSet<T>.FromSql(const ASql: string; const AParams: array of TValue): TFluentQuery<T>;
var
  i: Integer;
  LParams: TArray<TValue>;
begin
  SetLength(LParams, Length(AParams));
  for i := 0 to Length(AParams) - 1 do
    LParams[i] := AParams[i];

  Result := TFluentQuery<T>.Create(
    TFunc<TQueryIterator<T>>(function: TQueryIterator<T>
      begin
        Result := TSqlQueryIterator<T>.Create(Self, ASql, LParams);
      end),
      FContext.Connection);
end;

function TDbSet<T>.FromSql(const ASql: string): TFluentQuery<T>;
begin
  Result := FromSql(ASql, []);
end;

procedure TDbSet<T>.ApplyTenantFilter(var ASpec: ISpecification<T>);
var
  Provider: ITenantProvider;
begin
  if FIgnoreQueryFilters then Exit;

  // Check if T implements ITenantAware using RTTI
  if GetTypeData(TypeInfo(T))^.ClassType.GetInterfaceEntry(ITenantAware) = nil then Exit;

  Provider := FContext.TenantProvider;

  if (Provider = nil) or (Provider.Tenant = nil) then Exit;

  if ASpec = nil then
    ASpec := TSpecification<T>.Create;
    
  // Append TenantId filter
  ASpec.Where(TBinaryExpression.Create('TenantId', boEqual, Provider.Tenant.Id));
end;

procedure TDbSet<T>.StampCurrentTenant(const AEntity: TObject);
var
  Aware: ITenantAware;
  Provider: ITenantProvider;
begin
  if FIgnoreQueryFilters then
    Exit;
  if AEntity = nil then
    Exit;
  if not Supports(AEntity, ITenantAware, Aware) then
    Exit;
  Provider := FContext.TenantProvider;
  if (Provider = nil) or (Provider.Tenant = nil) then
    Exit;
  Aware.TenantId := Provider.Tenant.Id;
end;

procedure TDbSet<T>.ExtractForeignKeys(const AEntities: IList<T>; PropertyToCheck: string;
  out IDs: IList<TValue>; out FKMap: IDictionary<T, TValue>);
var
  Attr: TCustomAttribute;
  Ent: T;
  FKAttr: ForeignKeyAttribute;
  FKProp: TRttiProperty;
  FoundFK: string;
  NavProp: TRttiProperty;
  Pair: TPair<string, string>;
  Typ: TRttiType;
  Val: TValue;
begin
  IDs := TCollections.CreateList<TValue>;
  FKMap := TCollections.CreateDictionary<T, TValue>;
  Typ := TReflection.Context.GetType(T);
  NavProp := Typ.GetProperty(PropertyToCheck);
  if NavProp = nil then Exit;
  FoundFK := '';
  FKAttr := nil;
  for Attr in NavProp.GetAttributes do
    if Attr is ForeignKeyAttribute then
    begin
      FKAttr := ForeignKeyAttribute(Attr);
      Break;
    end;

  if FKAttr <> nil then
  begin
    for Pair in FColumns do
    begin
      if SameText(Pair.Value, FKAttr.ColumnName) then
      begin
        FoundFK := Pair.Key;
        Break;
      end;
    end;
  end;
  if FoundFK = '' then
    FoundFK := PropertyToCheck + 'Id';
  FKProp := Typ.GetProperty(FoundFK);
  if FKProp = nil then Exit;
  for Ent in AEntities do
  begin
    Val := FKProp.GetValue(Pointer(Ent));
    if TryUnwrapAndValidateFK(Val) then
    begin
      if not IDs.Contains(Val) then
        IDs.Add(Val);
      FKMap.Add(Ent, Val);
    end;
  end;
end;

procedure TDbSet<T>.LoadAndAssign(const AEntities: IList<T>; const NavPropName: string);
var
  Expr: IExpression;
  FKMap: IDictionary<T, TValue>;
  FkVal: string;
  IDs: IList<TValue>;
  IdValues: TArray<Variant>;
  k: Integer;
  KeyStr: string;
  LoadedMap: IDictionary<string, TObject>;
  NavProp: TRttiProperty;
  Obj: TObject;
  Pair: TPair<T, TValue>;
  Parent: T;
  TargetDbSet: IDbSet;
  TargetList: IList<TObject>;
  TargetRefId: string;
  TargetType: TRttiType;
begin
  IDs := nil;
  FKMap := nil;
  LoadedMap := nil;
  try
    ExtractForeignKeys(AEntities, NavPropName, IDs, FKMap);
    if (IDs = nil) or (IDs.Count = 0) then Exit;
    NavProp := TReflection.Context.GetType(T).GetProperty(NavPropName);
    if NavProp = nil then Exit;
    TargetType := NavProp.PropertyType;
    if TargetType.TypeKind <> tkClass then Exit;
    TargetDbSet := FContext.DataSet(TargetType.Handle);

    // Use Variant array to preserve types (Integer, String, GUID) for correct parameter binding
    // Ensure we handle Nullable types correctly before converting to variant
    SetLength(IdValues, IDs.Count);
    for k := 0 to IDs.Count - 1 do
      IdValues[k] := TValueToVariant(IDs[k]);

    // Use Variant array to preserve types (Integer, String, GUID) for correct parameter binding
    Expr := TPropExpression.Create('Id').&In(IdValues);
    TargetList := TargetDbSet.ListObjects(Expr);
    LoadedMap := TCollections.CreateDictionary<string, TObject>;
    for Obj in TargetList do
    begin
      TargetRefId := TargetDbSet.GetEntityId(Obj);
      KeyStr := TValueToKeyString(TargetRefId);
      LoadedMap.AddOrSetValue(KeyStr, Obj);
    end;
    
    for Pair in FKMap do
    begin
      Parent := Pair.Key;
      FkVal := TValueToKeyString(Pair.Value);
      try
        if LoadedMap.ContainsKey(FkVal) then
        begin
          TReflection.SetValue(Pointer(Parent), NavProp, LoadedMap[FkVal]);
        end;
      except
        on E: Exception do
        begin
          raise;
        end;
      end;
    end;

  finally
    IDs := nil;
    FKMap := nil;
    LoadedMap := nil;
  end;
end;

procedure TDbSet<T>.DoLoadIncludes(const AEntities: IList<T>; const AIncludes: TArray<string>);
var
  IncludePath: string;
  PropMap: TPropertyMap;
begin
  if (AEntities = nil) or (AEntities.Count = 0) then Exit;
  for IncludePath in AIncludes do
  begin
    // Check if this is a Many-to-Many relationship
    PropMap := nil;
    if (FMap <> nil) and FMap.Properties.TryGetValue(IncludePath, PropMap) then
    begin
      if PropMap.Relationship = rtManyToMany then
      begin
        LoadManyToMany(AEntities, IncludePath, PropMap);
        Continue;
      end;
      if PropMap.Relationship = rtOneToMany then
      begin
        LoadOneToMany(AEntities, IncludePath, PropMap);
        Continue;
      end;
    end;
    // Standard One-to-Many / Many-to-One loading
    LoadAndAssign(AEntities, IncludePath);
  end;
end;

procedure TDbSet<T>.LoadOneToMany(const AEntities: IList<T>; const NavPropName: string; const PropMap: TPropertyMap);
var
  AddMethod: TRttiMethod;
  ClassName: string;
  Ent: T;
  EntId: TValue;
  Expr: IExpression;
  GenericTypeName: string;
  i: Integer;
  IdValues: TArray<Variant>;
  IntfTyp: TRttiType;
  InversePropMap: TPropertyMap;
  KeyStr: string;
  ListIntf: IInterface;
  NavProp: TRttiProperty;
  NewList: TObject;
  Obj: TObject;
  ObjProp: TRttiProperty;
  P: TPair<string, TPropertyMap>;
  Parent: T;
  ParentClassName: string;
  ParentIds: IList<TValue>;
  ParentMap: IDictionary<string, T>;
  PropType: TRttiType;
  StartPos, EndPos: Integer;
  TargetDbSet: IDbSet;
  TargetFKPropName: string;
  TargetFKStr: string;
  TargetFKValue: TValue;
  TargetList: IList<TObject>;
  TargetMap: TEntityMap;
  TargetPropName: string;
  TargetType: TRttiType;
  TypeName: string;
  Val: TValue;
begin
  NavProp := TReflection.Context.GetType(T).GetProperty(NavPropName);
  if NavProp = nil then Exit;

  // 1. Collect Parent IDs and build map
  ParentIds := TCollections.CreateList<TValue>;
  ParentMap := TCollections.CreateDictionary<string, T>;
  try
    for Ent in AEntities do
    begin
      EntId := GetRelatedId(Ent);
      if not EntId.IsEmpty then
      begin
        // Ensure ID is unwrapped if it is a Smart Type (Prop<T>)
        KeyStr := TValueToKeyString(EntId);
        if not ParentIds.Contains(EntId) then
          ParentIds.Add(EntId);
        ParentMap.AddOrSetValue(KeyStr, Ent);
      end;
    end;
    if ParentIds.Count = 0 then Exit;

    // 2. Identify Target Type (from IList<TTarget>)
    TargetType := nil;
    PropType := NavProp.PropertyType;
    if PropType.TypeKind = tkInterface then
    begin
      TypeName := PropType.Name;
      StartPos := Pos('<', TypeName);
      EndPos := Pos('>', TypeName);
      if (StartPos > 0) and (EndPos > StartPos) then
      begin
        GenericTypeName := Copy(TypeName, StartPos + 1, EndPos - StartPos - 1);
        TargetType := TReflection.Context.FindType(GenericTypeName);
      end;
    end;
    
    if TargetType = nil then Exit;
    TargetDbSet := FContext.DataSet(TargetType.Handle);
    TargetMap := TModelBuilder.Instance.GetMap(TargetType.Handle);

    // 3. Identification of FK
    TargetFKPropName := PropMap.ForeignKeyColumn;
    
    // If we have an InverseProperty, look it up in the target map to find the FK
    if (TargetFKPropName = '') and (PropMap.InverseProperty <> '') and (TargetMap <> nil) then
    begin
       if TargetMap.Properties.TryGetValue(PropMap.InverseProperty, InversePropMap) then
         TargetFKPropName := InversePropMap.ForeignKeyColumn;
    end;
    
    // If still empty, scan target properties for any ForeignKey attribute pointing to our class name
    if (TargetFKPropName = '') and (TargetMap <> nil) then
    begin
       ParentClassName := T.ClassName;
       if ParentClassName.StartsWith('T') then ParentClassName := Copy(ParentClassName, 2, MaxInt);
       
       for P in TargetMap.Properties do
       begin
          if SameText(P.Key, ParentClassName) or SameText(P.Key, ParentClassName + 'Id') then
          begin
             if P.Value.ForeignKeyColumn <> '' then
             begin
                TargetFKPropName := P.Value.ForeignKeyColumn;
                Break;
             end;
          end;
       end;
    end;

    // Fallback guess
    if TargetFKPropName = '' then
    begin
       ClassName := T.ClassName;
       if ClassName.StartsWith('T') then ClassName := Copy(ClassName, 2, MaxInt);
       TargetFKPropName := ClassName + 'Id';
    end;

    TargetPropName := TargetFKPropName;
    if TargetMap <> nil then
    begin
       for P in TargetMap.Properties do
       begin
          if SameText(P.Key, TargetFKPropName) or SameText(P.Value.ColumnName, TargetFKPropName) then
          begin
             TargetPropName := P.Key;
             Break;
          end;
       end;
    end;

    SetLength(IdValues, ParentIds.Count);
    for i := 0 to ParentIds.Count - 1 do
      IdValues[i] := TValueToVariant(ParentIds[i]);

    // Query targets using Property Name
    Expr := TPropExpression.Create(TargetPropName).&In(IdValues);
    
    TargetList := TargetDbSet.ListObjects(Expr);

    // 4. Assign children to parents
    for Obj in TargetList do
    begin
       ObjProp := TReflection.Context.GetType(Obj.ClassType).GetProperty(TargetPropName);
       if ObjProp <> nil then
       begin
          TargetFKValue := ObjProp.GetValue(Obj);
          
          // CRITICAL: Must unwrap if it is Prop<T> or Nullable
          if not TryUnwrapAndValidateFK(TargetFKValue) then Continue;

          TargetFKStr := TValueToKeyString(TargetFKValue);
          
          if ParentMap.ContainsKey(TargetFKStr) then
          begin
             Parent := ParentMap[TargetFKStr];
             Val := NavProp.GetValue(Pointer(Parent));

             // Ensure List is initialized
             if Val.IsEmpty or ((Val.Kind = tkInterface) and (Val.AsInterface = nil)) then
             begin
                  NewList := TTrackingListFactory.CreateList(TargetType.Handle, FContext, TObject(Parent), NavProp.Name);
                  TReflection.SetValue(Pointer(Parent), NavProp, TValue.From<TObject>(NewList));
                 Val := NavProp.GetValue(Pointer(Parent));
             end;

             if Val.Kind = tkInterface then
             begin
                ListIntf := Val.AsInterface;
                if ListIntf <> nil then
                begin
                   IntfTyp := TReflection.Context.GetType(Val.TypeInfo);
                   AddMethod := IntfTyp.GetMethod('Add');
                   if AddMethod <> nil then
                   begin
                      AddMethod.Invoke(Val, [Obj]);
                   end;
                end;
             end;
          end;
       end;
    end;
  finally
    ParentIds := nil;
    ParentMap := nil;
  end;
end;

procedure TDbSet<T>.LoadManyToMany(const AEntities: IList<T>; const NavPropName: string; const PropMap: TPropertyMap);
var
  AllRelatedIds: IList<TValue>;
  Cmd: IDbCommand;
  CollValue: TValue;
  Ent: T;
  EntId: TValue;
  EntityIds: IList<TValue>;
  i: Integer;
  IdValues: TArray<Variant>;
  LeftKey: string;
  LEntIdStr, LObjId, LRelIdStr, LTypeName, LGenericTypeName: string;
  LoadedList: IList<TObject>;
  LStartPos, LEndPos: Integer;
  LTargetType: TRttiType;
  NavProp: TRttiProperty;
  NewList: IList<TObject>;
  Obj: TObject;
  PropType: TRttiType;
  Reader: IDbReader;
  RelatedDbSet: IDbSet;
  RelatedExpr: IExpression;
  RelatedObjects: IDictionary<string, TObject>; // RelatedId -> Object
  RelId: TValue;
  RightKey: TValue;
  SB: TStringBuilder;
  SQL: string;
  TargetIds: IDictionary<string, IList<TValue>>; // EntityId -> List of RelatedIds
  TheList: IList<TObject>;
begin
  if PropMap.JoinTableName = '' then Exit;

  NavProp := TReflection.Context.GetType(T).GetProperty(NavPropName);
  if NavProp = nil then Exit;

  // Collect all entity IDs
  EntityIds := TCollections.CreateList<TValue>;
  try
    for Ent in AEntities do
    begin
      EntId := GetRelatedId(Ent);
      if not EntityIds.Contains(EntId) then
        EntityIds.Add(EntId);
    end;
    if EntityIds.Count = 0 then Exit;

    // Build SQL to query join table
    SB := TStringBuilder.Create;
    try
      SB.Append('SELECT ');
      SB.Append(FContext.Dialect.QuoteIdentifier(PropMap.LeftKeyColumn));
      SB.Append(', ');
      SB.Append(FContext.Dialect.QuoteIdentifier(PropMap.RightKeyColumn));
      SB.Append(' FROM ');
      SB.Append(FContext.Dialect.QuoteIdentifier(PropMap.JoinTableName));
      SB.Append(' WHERE ');
      SB.Append(FContext.Dialect.QuoteIdentifier(PropMap.LeftKeyColumn));
      SB.Append(' IN (');
      for i := 0 to EntityIds.Count - 1 do
      begin
        if i > 0 then SB.Append(', ');
        SB.Append(':p' + IntToStr(i + 1));
      end;
      SB.Append(')');
      SQL := SB.ToString;
    finally
      SB.Free;
    end;

    Cmd := FContext.Connection.CreateCommand(SQL);
    for i := 0 to EntityIds.Count - 1 do
      Cmd.AddParam('p' + IntToStr(i + 1), EntityIds[i]);

    Reader := Cmd.ExecuteQuery;

    TargetIds := TCollections.CreateDictionary<string, IList<TValue>>(True);
    AllRelatedIds := TCollections.CreateList<TValue>;
    try
      while Reader.Next do
      begin
        LeftKey := Reader.GetValue(0).ToString;
        RightKey := Reader.GetValue(1);

        if not TargetIds.ContainsKey(LeftKey) then
          TargetIds.Add(LeftKey, TCollections.CreateList<TValue>);
        TargetIds[LeftKey].Add(RightKey);

        if not AllRelatedIds.Contains(RightKey) then
          AllRelatedIds.Add(RightKey);
      end;

      if AllRelatedIds.Count = 0 then Exit;

        LTargetType := nil;
        PropType := NavProp.PropertyType;
        if PropType.TypeKind = tkInterface then
        begin
          // IList<TRelated> - extract TRelated
          LTypeName := PropType.Name;
          // Parse generic: IList<TRelated>
          LStartPos := Pos('<', LTypeName);
          LEndPos := Pos('>', LTypeName);
          if (LStartPos > 0) and (LEndPos > LStartPos) then
          begin
            LGenericTypeName := Copy(LTypeName, LStartPos + 1, LEndPos - LStartPos - 1);
            LTargetType := TReflection.Context.FindType(LGenericTypeName);
          end;
        end;

        if LTargetType = nil then Exit;

        RelatedDbSet := FContext.DataSet(LTargetType.Handle);
        SetLength(IdValues, AllRelatedIds.Count);
        for i := 0 to AllRelatedIds.Count - 1 do
          IdValues[i] := TValueToVariant(AllRelatedIds[i]);

        RelatedExpr := TPropExpression.Create('Id').&In(IdValues);
        LoadedList := RelatedDbSet.ListObjects(RelatedExpr);

        RelatedObjects := TCollections.CreateDictionary<string, TObject>;
        try
          for Obj in LoadedList do
          begin
            LObjId := RelatedDbSet.GetEntityId(Obj);
            RelatedObjects.AddOrSetValue(LObjId, Obj);
          end;

          for Ent in AEntities do
          begin
            EntId := GetRelatedId(Ent);
            LEntIdStr := EntId.ToString;

            CollValue := NavProp.GetValue(Pointer(Ent));
            if CollValue.IsEmpty or (CollValue.Kind <> tkInterface) or (CollValue.AsType<IInterface> = nil) then
            begin
              NewList := TCollections.CreateList<TObject>;
              NavProp.SetValue(Pointer(Ent), TValue.From<IList<TObject>>(NewList));
              CollValue := NavProp.GetValue(Pointer(Ent));
            end;

            if Supports(CollValue.AsType<IInterface>, IList<TObject>, TheList) then
            begin
              if TargetIds.ContainsKey(LEntIdStr) then
              begin
                for RelId in TargetIds[LEntIdStr] do
                begin
                  LRelIdStr := RelId.ToString;
                  if RelatedObjects.ContainsKey(LRelIdStr) then
                    TheList.Add(RelatedObjects[LRelIdStr]);
                end;
              end;
            end;
          end;
        finally
          RelatedObjects := nil;
        end;
      finally
        TargetIds := nil;
        AllRelatedIds := nil;
      end;
  finally
    EntityIds := nil;
  end;
end;

procedure TDbSet<T>.LinkManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntity: TObject);
var
  Cmd: IDbCommand;
  EntityId, RelatedId: TValue;
  PropMap: TPropertyMap;
  SQL: string;
begin
  if FMap = nil then Exit;
  if not FMap.Properties.TryGetValue(APropertyName, PropMap) then Exit;
  if PropMap.Relationship <> rtManyToMany then Exit;
  if PropMap.JoinTableName = '' then Exit;
  
  EntityId := GetRelatedId(AEntity);
  RelatedId := GetRelatedId(ARelatedEntity);
  
  SQL := TJoinTableSQLHelper.GenerateInsert(FContext.Dialect,
    PropMap.JoinTableName, PropMap.LeftKeyColumn, PropMap.RightKeyColumn);
    
  Cmd := FContext.Connection.CreateCommand(SQL);
  Cmd.AddParam('p1', EntityId);
  Cmd.AddParam('p2', RelatedId);
  Cmd.Execute;
end;

procedure TDbSet<T>.UnlinkManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntity: TObject);
var
  Cmd: IDbCommand;
  EntityId, RelatedId: TValue;
  PropMap: TPropertyMap;
  SQL: string;
begin
  if FMap = nil then Exit;
  if not FMap.Properties.TryGetValue(APropertyName, PropMap) then Exit;
  if PropMap.Relationship <> rtManyToMany then Exit;
  if PropMap.JoinTableName = '' then Exit;
  
  EntityId := GetRelatedId(AEntity);
  RelatedId := GetRelatedId(ARelatedEntity);
  
  SQL := TJoinTableSQLHelper.GenerateDelete(FContext.Dialect,
    PropMap.JoinTableName, PropMap.LeftKeyColumn, PropMap.RightKeyColumn);
    
  Cmd := FContext.Connection.CreateCommand(SQL);
  Cmd.AddParam('p1', EntityId);
  Cmd.AddParam('p2', RelatedId);
  Cmd.Execute;
end;

{ Non-generic IDbSet implementations }

procedure TDbSet<T>.LinkManyToMany(const AEntity: TObject; const APropertyName: string; const ARelatedEntity: TObject);
begin
  LinkManyToMany(T(AEntity), APropertyName, ARelatedEntity);
end;

procedure TDbSet<T>.UnlinkManyToMany(const AEntity: TObject; const APropertyName: string; const ARelatedEntity: TObject);
begin
  UnlinkManyToMany(T(AEntity), APropertyName, ARelatedEntity);
end;

procedure TDbSet<T>.SyncManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntities: TArray<TObject>);
var
  Cmd, CmdLoop: IDbCommand;
  EntityId, RelatedId: TValue;
  PropMap: TPropertyMap;
  RelEnt: TObject;
  SQL: string;
begin
  if FMap = nil then Exit;
  if not FMap.Properties.TryGetValue(APropertyName, PropMap) then Exit;
  if PropMap.Relationship <> rtManyToMany then Exit;
  if PropMap.JoinTableName = '' then Exit;
  
  EntityId := GetRelatedId(AEntity);
  
  // First, delete all existing links for this entity
  SQL := TJoinTableSQLHelper.GenerateDeleteByLeft(FContext.Dialect,
    PropMap.JoinTableName, PropMap.LeftKeyColumn);
    
  Cmd := FContext.Connection.CreateCommand(SQL);
  Cmd.AddParam('p1', EntityId);
  Cmd.Execute;
  
  // Then, insert new links
  SQL := TJoinTableSQLHelper.GenerateInsert(FContext.Dialect,
    PropMap.JoinTableName, PropMap.LeftKeyColumn, PropMap.RightKeyColumn);
    
  for RelEnt in ARelatedEntities do
  begin
    RelatedId := GetRelatedId(RelEnt);
    CmdLoop := FContext.Connection.CreateCommand(SQL);
    CmdLoop.AddParam('p1', EntityId);
    CmdLoop.AddParam('p2', RelatedId);
    CmdLoop.Execute;
  end;
end;

function TDbSet<T>.Find(const AId: Integer): T;
begin
  Result := Find(Variant(AId));
end;

function TDbSet<T>.Find(const AId: Variant): T;
var
  Expr: IExpression;
  i: Integer;
  L: IList<T>;
  PKProp: TRttiProperty;
  PropName: string;
  Spec: ISpecification<T>;
  Val: TValue;
  VariantArray: TArray<Variant>;
  Span: TSpan;
begin
  Span := TTracer.BeginSpan('DbSet.Find', 'SQL');
  Span.SetAttribute('entity', string(PTypeInfo(TypeInfo(T)).Name));

  // Check if AId is a VarArray (composite key)
  if VarIsArray(AId) then
  begin
    // Convert VarArray to array of Variant
    SetLength(VariantArray, VarArrayHighBound(AId, 1) - VarArrayLowBound(AId, 1) + 1);
    for i := 0 to High(VariantArray) do
      VariantArray[i] := AId[VarArrayLowBound(AId, 1) + i];
    
    // Call the array overload
    Result := Find(VariantArray);
    Exit;
  end;

  // Single key lookup
  PropName := 'Id';
  Val := TValue.Empty;
  
  if FPKColumns.Count > 0 then
  begin
    // FProps keys are lowercased in MapEntity
    if FProps.TryGetValue(FPKColumns[0].ToLower, PKProp) then
    begin
       PropName := PKProp.Name;
       // Coerce GUIDs and UUIDs if necessary
       if (PKProp.PropertyType.Handle = TypeInfo(TGUID)) and VarIsStr(AId) then
         Val := TValue.From<TGUID>(StringToGUID(VarToStr(AId)))
       else if (PKProp.PropertyType.Handle = TypeInfo(TUUID)) and VarIsStr(AId) then
         Val := TValue.From<TUUID>(TUUID.FromString(VarToStr(AId)))
       else
         Val := TValue.FromVariant(AId);
    end;
  end;
  
  if Val.IsEmpty then
    Val := TValue.FromVariant(AId);

  Expr := TPropExpression.Create(PropName) = Val;
  Spec := TSpecification<T>.Create(Expr);
  
  try
    L := ToList(Spec);
    if L.Count > 0 then
    begin
      Result := L[0];
      L.Extract(Result);
    end
    else
      Result := nil;
  except
    on E: Exception do
    begin
      Span.SetStatus('Error', E.Message);
      raise;
    end;
  end;
end;

function TDbSet<T>.Find(const AId: array of Variant): T;
var
  Expr: IExpression;
  i: Integer;
  KeyExpr: IExpression;
  L: IList<T>;
  Pair: TPair<string, string>;
  PropName: string;
  Spec: ISpecification<T>;
begin
  if Length(AId) = 1 then
  begin
    Result := Find(AId[0]);
    Exit;
  end;

  // Validate that we have the correct number of keys
  if Length(AId) <> FPKColumns.Count then
    raise Exception.CreateFmt('Expected %d key values but got %d', [FPKColumns.Count, Length(AId)]);

  // Build composite key expression: (Col1 = Val1) AND (Col2 = Val2) AND ...
  Expr := nil;
  for i := 0 to FPKColumns.Count - 1 do
  begin
    // Find the property name for this PK column
    PropName := '';
    for Pair in FColumns do
    begin
      if SameText(Pair.Value, FPKColumns[i]) then
      begin
        PropName := Pair.Key;
        Break;
      end;
    end;

    // If we couldn't find the property name, use the column name as fallback
    if PropName = '' then
      PropName := FPKColumns[i];

    // Create the equality expression for this key component
    KeyExpr := TBinaryExpression.Create(PropName, boEqual, TValue.FromVariant(AId[i]));

    // Combine with AND
    if Expr = nil then
      Expr := KeyExpr
    else
      Expr := TLogicalExpression.Create(Expr, KeyExpr, loAnd);
  end;

  // Execute the query
  Spec := TSpecification<T>.Create(Expr);
  L := ToList(Spec);
  
  if L.Count > 0 then
    Result := L[0]
  else
    Result := nil;
end;

function TDbSet<T>.Find(const AId: array of Integer): T;
var
  i: Integer;
  VarArray: TArray<Variant>;
begin
  SetLength(VarArray, Length(AId));
  for i := 0 to High(AId) do
    VarArray[i] := AId[i];
  Result := Find(VarArray);
end;

function TDbSet<T>.Query(const ASpec: ISpecification<T>): TFluentQuery<T>;
var
  Factory: TFunc<TQueryIterator<T>>;
  SelfDbSet: IDbSet<T>;
  Spec: ISpecification<T>;
begin
  Spec := ASpec;
  SelfDbSet := Self; 
  Factory := function: TQueryIterator<T>
    begin
      Result := TSpecificationQueryIterator<T>.Create(
        function: IList<T>
        begin
          Result := SelfDbSet.ToList(Spec);
        end);
    end;

  Result := TFluentQuery<T>.Create(
    Factory,
    Spec as ISpecification,
    TFunc<ISpecification, Integer>(
      function(S: ISpecification): Integer
      begin
        Result := SelfDbSet.Count(S as ISpecification<T>);
      end),
    TFunc<ISpecification, Boolean>(
      function(S: ISpecification): Boolean
      begin
        Result := SelfDbSet.Any(S as ISpecification<T>);
      end),
    TFunc<ISpecification, T>(
      function(S: ISpecification): T
      begin
        Result := SelfDbSet.FirstOrDefault(S as ISpecification<T>);
      end),
    FContext.Connection,
    TFunc<IEnumerator<T>>(
      function: IEnumerator<T>
      begin
        Result := SelfDbSet.RequestStreamingIterator(Spec);
      end));
end;

function TDbSet<T>.Query(const AExpression: IExpression): TFluentQuery<T>;
var
  Spec: ISpecification<T>;
begin
  Spec := TSpecification<T>.Create(AExpression);
  Result := Query(Spec);
end;

function TDbSet<T>.QueryAll: TFluentQuery<T>;
var
  Spec: ISpecification<T>;
begin
  // Create spec explicitly and assign to interface variable to ensure correct ref counting
  Spec := TSpecification<T>.Create;
  Result := Query(Spec);
end;

function TDbSet<T>.AsNoTracking: TFluentQuery<T>;
begin
  Result := QueryAll.AsNoTracking;
end;

function TDbSet<T>.FirstOrDefault(const AExpression: IExpression): T;
var
  L: IList<T>;
  Spec: ISpecification<T>;
begin
  Spec := TSpecification<T>.Create(AExpression);
  Spec.Take(1);
  L := ToList(Spec);
  if L.Count > 0 then
    Result := L[0]
  else
    Result := nil;
end;

function TDbSet<T>.Any(const AExpression: IExpression): Boolean;
var
  Cmd: IDbCommand;
  Generator: TSqlGenerator<T>;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  Reader: IDbReader;
  Spec: ISpecification<T>;
  Sql: string;
begin
  Generator := CreateGenerator;
  try
    Spec := TSpecification<T>.Create(AExpression);
    ApplyTenantFilter(Spec);
    Spec.Take(1);
    
    Sql := Generator.GenerateSelect(Spec); 
    
    Cmd := FContext.Connection.CreateCommand(Sql) as IDbCommand;
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    
    Reader := Cmd.ExecuteQuery;
    Result := Reader.Next;
  finally
    Generator.Free;
    ResetQueryFlags;
  end;
end;

function TDbSet<T>.Where(const APredicate: TQueryPredicate<T>): TFluentQuery<T>;
var
  SmartRes: BooleanExpression;
begin
  SmartRes := APredicate(Dext.Entity.Prototype.Prototype.Entity<T>);
  Result := Query(TFluentExpression(SmartRes));
end;

function TDbSet<T>.Where(const AValue: BooleanExpression): TFluentQuery<T>;
begin
  Result := Query(AValue.Expression);
end;

function TDbSet<T>.Where(const AExpression: TFluentExpression): TFluentQuery<T>;
begin
  Result := Query(AExpression.Expression);
end;

function TDbSet<T>.Where(const AExpression: IExpression): TFluentQuery<T>;
begin
  Result := Query(AExpression);
end;

function TDbSet<T>.Count(const AExpression: IExpression): Integer;
begin
  Result := Count(TSpecification<T>.Create(AExpression));
end;

function TDbSet<T>.Count(const ASpec: ISpecification<T>): Integer;
var
  Cmd: IDbCommand;
  Generator: TSqlGenerator<T>;
  LSpec: ISpecification<T>;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  Sql: string;
  Val: TValue;
begin
  Generator := CreateGenerator;
  try
    LSpec := ASpec;
    ApplyTenantFilter(LSpec);
    Sql := Generator.GenerateCount(LSpec);
    
    Cmd := FContext.Connection.CreateCommand(Sql);
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    Val := Cmd.ExecuteScalar;
    if Val.IsEmpty then Result := 0 else Result := Val.AsInteger;
  finally
    Generator.Free;
    ResetQueryFlags;
  end;
end;

function TDbSet<T>.Any(const ASpec: ISpecification<T>): Boolean;
begin
  Result := Count(ASpec) > 0;
end;

function TDbSet<T>.FirstOrDefault(const ASpec: ISpecification<T>): T;
var
  L: IList<T>;
begin
  // Optimization: Apply Take(1) to the spec if it doesn't have it
  if (ASpec <> nil) and (ASpec.GetTake <= 0) then
    ASpec.Take(1);
    
  L := ToList(ASpec);
  if L.Count > 0 then
    Result := L[0]
  else
    Result := nil;
end;

function TDbSet<T>.IgnoreQueryFilters: IDbSet<T>;
begin
  FIgnoreQueryFilters := True;
  Result := Self;
end;

function TDbSet<T>.OnlyDeleted: IDbSet<T>;
begin
  FOnlyDeleted := True;
  Result := Self;
end;

procedure TDbSet<T>.ResetQueryFlags;
begin
  FIgnoreQueryFilters := False;
  FOnlyDeleted := False;
end;

function TDbSet<T>.HardDelete(const AEntity: T): IDbSet<T>;
var
  Cmd: IDbCommand;
  Generator: TSqlGenerator<T>;
  Pair: TPair<string, TValue>;
  ParamType: TFieldType;
  Sql: string;
begin
  Generator := CreateGenerator;
  try
    Sql := Generator.GenerateDelete(AEntity);
    Cmd := FContext.Connection.CreateCommand(Sql);
    for Pair in Generator.Params do
    begin
      if Generator.ParamTypes.TryGetValue(Pair.Key, ParamType) then
        Cmd.AddParam(Pair.Key, Pair.Value, ParamType)
      else
        Cmd.AddParam(Pair.Key, Pair.Value);
    end;
    Cmd.ExecuteNonQuery;
    FIdentityMap.Remove(GetEntityId(AEntity));
  finally
    Generator.Free;
  end;
  Result := Self;
end;

function TDbSet<T>.RequestStreamingIterator(const ASpec: ISpecification<T>): IEnumerator<T>;
begin
  Result := TStreamingViewIterator<T>.Create(Self, ASpec);
end;

function TDbSet<T>.Restore(const AEntity: T): IDbSet<T>;
var
  Attr: TCustomAttribute;
  ColumnName: string;
  IsSoftDelete: Boolean;
  NotDeletedVal: Variant;
  P: TRttiProperty;
  Prop: TRttiProperty;
  PropName: string;
  RType: TRttiType;
  SoftDeleteAttr: SoftDeleteAttribute;
  ValToSet: TValue;
begin
  IsSoftDelete := False;
  PropName := '';
  
  // 1. Check Fluent Mapping
  if (FMap <> nil) and FMap.IsSoftDelete then
  begin
    IsSoftDelete := True;
    PropName := FMap.SoftDeleteProp;
    NotDeletedVal := FMap.SoftDeleteNotDeletedValue;
  end
  // 2. Check Attribute
  else
  begin
    RType := TReflection.Context.GetType(T);
    if RType <> nil then
    begin
      for Attr in RType.GetAttributes do
      begin
        if Attr is SoftDeleteAttribute then
        begin
          SoftDeleteAttr := SoftDeleteAttribute(Attr);
          IsSoftDelete := True;
          PropName := SoftDeleteAttr.ColumnName;
          NotDeletedVal := SoftDeleteAttr.NotDeletedValue;
          Break;
        end;
      end;
    end;
  end;
  
  if IsSoftDelete then
  begin
    RType := TReflection.Context.GetType(T);
    if RType <> nil then
    begin
        // Find the soft delete column property
        Prop := nil;
        ColumnName := PropName;
        
        for P in RType.GetProperties do
        begin
           if SameText(P.Name, ColumnName) then
           begin
             Prop := P;
             Break;
           end;
           
           for Attr in P.GetAttributes do
           begin
             if Attr is ColumnAttribute then
             begin
               if SameText(ColumnAttribute(Attr).Name, ColumnName) then
               begin
                 Prop := P;
                 Break;
               end;
             end;
           end;
           if Prop <> nil then Break;
        end;
        
        if Prop <> nil then
        begin
          if Prop.PropertyType.Handle = TypeInfo(Boolean) then
            ValToSet := TValue.From(Boolean(NotDeletedVal))
          else 
            ValToSet := TValue.FromVariant(NotDeletedVal);
 
          TReflection.SetValue(Pointer(AEntity), Prop, ValToSet);
          PersistUpdate(AEntity);
        end;
      end;
  end;
  Result := Self;
end;

function TDbSet<T>.Prototype: T;
begin
  Result := Dext.Entity.Prototype.Prototype.Entity<T>;
end;

function TDbSet<T>.Prototype<TEntity>: TEntity;
begin
  Result := Dext.Entity.Prototype.Prototype.Entity<TEntity>;
end;

{ TDynamicDbSetFactory<T> }

function TDynamicDbSetFactory<T>.CreateDbSet(const AContext: IInterface): IInterface;
begin
  Result := TDbSet<T>.Create(AContext as IDbContext);
end;

{ TDbProjectionHelper }

class procedure TDbProjectionHelper.ProjectToJson(const Reader: IDbReader;
  AStream: TStream);
var
  Writer: TUtf8JsonWriter;
begin
  Writer := TUtf8JsonWriter.Create(AStream, False);
  WriteRows(Reader, Writer);
end;

class procedure TDbProjectionHelper.ProjectToJson(const Reader: IDbReader;
  AContext: Pointer; AWrite: TDbProjectionWriteProc);
var
  Writer: TUtf8JsonWriter;
begin
  Writer := TUtf8JsonWriter.Create(AContext, TUtf8WriteProc(AWrite), False);
  WriteRows(Reader, Writer);
end;

class procedure TDbProjectionHelper.WriteRows(const Reader: IDbReader;
  var Writer: TUtf8JsonWriter);
var
  ColCount: Integer;
  ColNames: TArray<string>;
  ColTypes: TArray<TFieldType>;
  i: Integer;
begin
  if Reader = nil then
    Exit;

  ColCount := Reader.GetColumnCount;
  SetLength(ColNames, ColCount);
  SetLength(ColTypes, ColCount);
  for i := 0 to ColCount - 1 do
  begin
    ColNames[i] := Reader.GetColumnName(i);
    ColTypes[i] := Reader.GetColumnType(i);
  end;

  Writer.WriteStartArray;

  while Reader.Next do
  begin
    Writer.WriteStartObject;
    for i := 0 to ColCount - 1 do
    begin
      Writer.WritePropertyName(ColNames[i]);
      if Reader.IsNull(i) then
      begin
        Writer.WriteNull;
      end
      else
      begin
        case ColTypes[i] of
          Data.DB.ftBoolean:
            Writer.WriteBoolean(Reader.GetBoolean(i));
          Data.DB.ftSmallint, Data.DB.ftShortint, Data.DB.ftInteger,
          Data.DB.ftWord, Data.DB.ftAutoInc:
            Writer.WriteNumber(Reader.GetInt32(i));
          Data.DB.ftLargeint, Data.DB.ftLongWord:
            Writer.WriteNumber(Reader.GetInt64(i));
          Data.DB.ftSingle, Data.DB.ftFloat, Data.DB.ftCurrency,
          Data.DB.ftBCD, Data.DB.ftFMTBcd:
            Writer.WriteNumber(Reader.GetDouble(i));
          // The JSON forms of Dext.Json: a date, a time of day, a local
          // date and time with its offset
          Data.DB.ftDate:
            Writer.WriteString(FormatJsonDate(Reader.GetDateTime(i)));
          Data.DB.ftTime:
            Writer.WriteString(FormatJsonTime(Reader.GetDateTime(i)));
          Data.DB.ftDateTime, Data.DB.ftTimeStamp:
            Writer.WriteString(FormatJsonDateTime(Reader.GetDateTime(i)));
          Data.DB.ftGuid:
            Writer.WriteString(Reader.GetString(i));
        else
          Writer.WriteString(Reader.GetString(i));
        end;
      end;
    end;
    Writer.WriteEndObject;
  end;

  Writer.WriteEndArray;
end;

end.

