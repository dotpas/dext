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
unit Dext.Entity.Query;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  System.Classes,
  Dext.Collections.Base,
  Dext.Collections,
  Dext.Collections.Comparers,
  Dext.Collections.Dict,
  System.Rtti,
  System.TypInfo,
  System.SysUtils,
  Dext.Specifications.Base,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types,
  Dext.Threading.Async,
  Dext.Entity.Drivers.Interfaces, // Add IDbConnection
  Dext.Entity.Mapping,
  Dext.Core.SmartTypes; // Add SmartTypes

type
  /// <summary>Numeric conversion of property values for the aggregates.</summary>
  TQueryValueHelper = class
  public
    /// <summary>The value of a property as Double: unwraps Smart Properties and
    /// Nullable (an empty value counts as zero) and converts any integer or
    /// floating-point type.</summary>
    class function ToDouble(const AValue: TValue): Double; static;
  end;

  /// <summary>
  ///   Helper class to handle join operations and metadata resolution.
  /// </summary>
  TQueryJoinHelper = class
  public
    class function GetDefaultAlias(ATypeInfo: PTypeInfo): string; static;
    class function GetUniqueAlias(ATypeInfo: PTypeInfo; const AJoins: TArray<IJoin>; const ABaseTableAlias: string): string; static;
    class function GetPKColumnName(AMap: TEntityMap): string; static;
    class function ResolveJoinCondition(AOuterType, AInnerType: PTypeInfo; const AOuterAlias, AInnerAlias: string): IExpression; static;
  end;

  /// <summary>
  ///   Represents the result of a paginated query, containing the items and page metadata.
  /// </summary>
  IPagedResult<T> = interface
    ['{6A8B9C0D-1E2F-3A4B-5C6D-7E8F9A0B1C2D}']
    function GetItems: IList<T>;
    function GetTotalCount: Integer;
    function GetPageNumber: Integer;
    function GetPageSize: Integer;
    function GetPageCount: Integer;
    function GetHasNextPage: Boolean;
    function GetHasPreviousPage: Boolean;
    
    property Items: IList<T> read GetItems;
    property TotalCount: Integer read GetTotalCount;
    property PageNumber: Integer read GetPageNumber;
    property PageSize: Integer read GetPageSize;
    property PageCount: Integer read GetPageCount;
    property HasNextPage: Boolean read GetHasNextPage;
    property HasPreviousPage: Boolean read GetHasPreviousPage;
  end;

  /// <summary>
  ///   Concrete implementation of a paginated query result.
  /// </summary>
  TPagedResult<T> = class(TInterfacedObject, IPagedResult<T>)
  private
    FItems: IList<T>;
    FTotalCount: Integer;
    FPageNumber: Integer;
    FPageSize: Integer;
  public
    constructor Create(AItems: IList<T>; ATotalCount, APageNumber, APageSize: Integer);
    destructor Destroy; override;
    function GetItems: IList<T>;
    function GetTotalCount: Integer;
    function GetPageNumber: Integer;
    function GetPageSize: Integer;
    function GetPageCount: Integer;
    function GetHasNextPage: Boolean;
    function GetHasPreviousPage: Boolean;
  end;

  /// <summary>
  ///   Base iterator for lazy query execution.
  ///   Inherits from TEnumerator<T> to integrate with Delphi's collection system.
  /// </summary>
  TQueryIterator<T> = class(TInterfacedObject, Dext.Collections.Base.IEnumerator<T>)
  protected
    FCurrent: T;
    function MoveNextCore: Boolean; virtual; abstract;
  public
    constructor Create;
    function GetCurrent: T;
    function MoveNext: Boolean;
    property Current: T read GetCurrent;
  end;

  /// <summary>
  ///   Orchestrator for fluent queries (LINQ-like). 
  ///   Implemented as a record for automatic lifecycle management and low overhead.
  /// </summary>
  TFluentQuery<T> = record
  private
    FIteratorFactory: TFunc<TQueryIterator<T>>;
    FSpecification: ISpecification; // Reference to the base specification
    FLastIncludePath: string; // Keeps track for ThenInclude
    FExecuteCount: TFunc<ISpecification, Integer>;
    FExecuteAny: TFunc<ISpecification, Boolean>;
    FExecuteFirstOrDefault: TFunc<ISpecification, T>;
    FConnection: IDbConnection; // Track connection for async safety
    FNoTracking: Boolean;
    FStreamingIteratorFactory: TFunc<IEnumerator<T>>;
    procedure AssignSpecTracking(const AEnable: Boolean);
    function GetSpec: ISpecification;
    function GetConnection: IDbConnection;
    class function CreatePropSelector<TResult>(const AProp: TRttiProperty): TFunc<T, TResult>; static;
    class function CreatePropsSelector(const AProperties: TArray<string>): TFunc<T, T>; static;
    class function CreateSelectFactory<TResult>(const AFactory: TFunc<TQueryIterator<T>>; const ASelector: TFunc<T, TResult>): TFunc<TQueryIterator<TResult>>; static;
    class function JoinStringToEqualsExpression(const ACondition: string): IExpression; static;
  public
    property Connection: IDbConnection read GetConnection;
    property Specification: ISpecification read GetSpec;
    /// <summary>
    ///   Creates a new fluent query.
    /// </summary>
    constructor Create(const AIteratorFactory: TFunc<TQueryIterator<T>>; const AConnection: IDbConnection = nil); overload;
    constructor Create(const AIteratorFactory: TFunc<TQueryIterator<T>>; const ASpec: ISpecification; const AConnection: IDbConnection = nil); overload;
    constructor Create(
      const AIteratorFactory: TFunc<TQueryIterator<T>>; 
      const ASpec: ISpecification;
      const AExecCount: TFunc<ISpecification, Integer>;
      const AExecAny: TFunc<ISpecification, Boolean>;
      const AExecFirstOrDefault: TFunc<ISpecification, T>;
      const AConnection: IDbConnection = nil;
      const AStreamingFactory: TFunc<IEnumerator<T>> = nil
    ); overload;
    
    /// <summary>
    ///   Returns an enumerator for data materialization.
    /// </summary>
    function GetEnumerator: IEnumerator<T>;
    
    /// <summary>
    ///   Returns a specialized high-performance enumerator that reuses object instances.
    /// </summary>
    function GetStreamingEnumerator: IEnumerator<T>;
    
    /// <summary>
    ///   Projects each element of a sequence into a new form.
    /// </summary>
    function Select<TResult>(const ASelector: TFunc<T, TResult>): TFluentQuery<TResult>; overload;
    function Select<TResult>(const AProp: Prop<TResult>): TFluentQuery<TResult>; overload;
    function Select<TResult>(const AProp: TPropExpression): TFluentQuery<TResult>; overload;
    function Select(const AProperties: array of string): TFluentQuery<T>; overload;

    /// <summary>
    ///   Filters a sequence of values based on a predicate.
    /// </summary>
    function Where(const APredicate: TPredicate<T>): TFluentQuery<T>; overload;
    function WherePredicate(const APredicate: TPredicate<T>): TFluentQuery<T>;
    function Where(const APredicate: TQueryPredicate<T>): TFluentQuery<T>; overload;
    function Where(const AValue: BooleanExpression): TFluentQuery<T>; overload;
    function Where(const AExpression: TFluentExpression): TFluentQuery<T>; overload;
    function Where(const AExpression: IExpression): TFluentQuery<T>; overload;

    /// <summary>
    ///   Bypasses a specified number of elements in a sequence and then returns the remaining elements.
    /// </summary>
    function Skip(const ACount: Integer): TFluentQuery<T>;

    /// <summary>
    ///   Returns a specified number of contiguous elements from the start of a sequence.
    /// </summary>
    function Take(const ACount: Integer): TFluentQuery<T>;
    
    /// <summary>
    ///   Sorts the elements of a sequence in a specified order.
    /// </summary>
    function OrderBy(const AOrderBy: IOrderBy): TFluentQuery<T>; overload;
    function OrderBy(const AOrders: array of IOrderBy): TFluentQuery<T>; overload;
    function OrderByDescending(const AOrderBy: IOrderBy): TFluentQuery<T>; overload;
    function OrderBy<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>; overload;
    function OrderByDescending<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>; overload;
    function ThenBy<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;
    function ThenByDescending<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;

    /// <summary>
    ///   Force execution and return materialized list.
    /// </summary>
    function ToList: IList<T>;
    function ToListAsync: TAsyncBuilder<IList<T>>;

    /// <summary>
    ///   Returns distinct elements from a sequence.
    /// </summary>
    function Distinct: TFluentQuery<T>;

    /// <summary>
    ///   Configures the query to not track entities in the IdentityMap.
    ///   Useful for read-only scenarios to improve performance and avoid memory overhead.
    /// </summary>
    function AsNoTracking: TFluentQuery<T>;

    /// <summary>
    ///   Specifies the related objects to include in the query results (Eager Loading).
    /// </summary>
    function Include(const APath: string): TFluentQuery<T>; overload;
    function Include(const AProp: TPropExpression): TFluentQuery<T>; overload; // Legacy TPropExpression
    function Include(const AProps: array of TPropExpression): TFluentQuery<T>; overload;
    
    function Include(const AProp: IPropInfo): TFluentQuery<T>; overload;
    function ThenInclude(const AProp: IPropInfo): TFluentQuery<T>; overload;

    function IgnoreQueryFilters: TFluentQuery<T>;
    function OnlyDeleted: TFluentQuery<T>;
    function WithLock(const ALockMode: TLockMode): TFluentQuery<T>;
    
    // Set operations
    function Join<TInner, TKey, TResult>(
      const AInner: TFluentQuery<TInner>;
      const AOuterKeyProp: string;
      const AInnerKeyProp: string;
      const AResultSelector: TFunc<T, TInner, TResult>
    ): TFluentQuery<TResult>; overload;
    
    // SQL Based Joins (Legacy/Raw)
    function Join(const ATable, AAlias: string; const AType: TJoinType; const ACondition: IExpression): TFluentQuery<T>; overload;
    /// <summary>
    ///   Parses a simple join predicate in the form "left = right".
    ///   Example: Join('addresses', 'a', 'users.address_id = a.id')
    /// </summary>
    function Join(const ATable, AAlias: string; const ACondition: string; const AType: TJoinType = TJoinType.jtInner): TFluentQuery<T>; overload;

    // Automatic ON condition resolution via metadata
    function JoinInner<TInner: class>: TFluentQuery<T>; overload;
    function JoinLeft<TInner: class>: TFluentQuery<T>; overload;
    function JoinRight<TInner: class>: TFluentQuery<T>; overload;
    function JoinFull<TInner: class>: TFluentQuery<T>; overload;

    // Explicit ON conditions
    function JoinInner<TInner: class>(const AOn: IExpression): TFluentQuery<T>; overload;
    function JoinLeft<TInner: class>(const AOn: IExpression): TFluentQuery<T>; overload;
    function JoinRight<TInner: class>(const AOn: IExpression): TFluentQuery<T>; overload;
    function JoinFull<TInner: class>(const AOn: IExpression): TFluentQuery<T>; overload;

    // Alias overrides + Automatic ON resolution
    function JoinInner<TInner: class>(const AAlias: string): TFluentQuery<T>; overload;
    function JoinLeft<TInner: class>(const AAlias: string): TFluentQuery<T>; overload;
    function JoinRight<TInner: class>(const AAlias: string): TFluentQuery<T>; overload;
    function JoinFull<TInner: class>(const AAlias: string): TFluentQuery<T>; overload;

    // Alias overrides + Explicit ON conditions
    function JoinInner<TInner: class>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>; overload;
    function JoinLeft<TInner: class>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>; overload;
    function JoinRight<TInner: class>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>; overload;
    function JoinFull<TInner: class>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>; overload;

    // Cross Joins (No ON condition)
    function JoinCross<TInner: class>: TFluentQuery<T>; overload;
    function JoinCross<TInner: class>(const AAlias: string): TFluentQuery<T>; overload;
    
    // Group By
    function GroupBy(const AColumn: string): TFluentQuery<T>; overload;
    function GroupBy(const AColumns: array of string): TFluentQuery<T>; overload;
    function GroupBy<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>; overload;
    
    // Aggregations
    function Count: Integer; overload;
    function Count(const APredicate: TPredicate<T>): Integer; overload;
    function Any: Boolean; overload;
    function Any(const APredicate: TPredicate<T>): Boolean; overload;
    function First: T; overload;
    function First(const APredicate: TPredicate<T>): T; overload;
    function FirstOrDefault: T; overload;
    function FirstOrDefault(const APredicate: TPredicate<T>): T; overload;
    
    function Sum(const ASelector: TFunc<T, Double>): Double; overload;
    function Sum(const APropertyName: string): Double; overload;

    function Average(const ASelector: TFunc<T, Double>): Double; overload;
    function Average(const APropertyName: string): Double; overload;
    
    function Min(const ASelector: TFunc<T, Double>): Double; overload;
    function Min(const APropertyName: string): Double; overload;
    
    function Max(const ASelector: TFunc<T, Double>): Double; overload;
    function Max(const APropertyName: string): Double; overload;
    function Max(const AProp: IPropInfo): Double; overload;
    function MaxOrDefault(const ASelector: TFunc<T, Double>; const ADefault: Double = 0): Double; overload;
    function MaxOrDefault(const APropertyName: string; const ADefault: Double = 0): Double; overload;
    function MaxOrDefault(const AProp: IPropInfo; const ADefault: Double = 0): Double; overload;

    /// <summary>
    ///   Paginates the query results.
    /// </summary>
    function Paginate(const APageNumber, APageSize: Integer): IPagedResult<T>;
  end;

  /// <summary>
  ///   Iterator that executes a specification-based query.
  /// </summary>
  TSpecificationQueryIterator<T> = class(TQueryIterator<T>)
  private
    FGetList: TFunc<IList<T>>;
    FList: IList<T>;
    FIndex: Integer;
    FExecuted: Boolean;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(const AGetList: TFunc<IList<T>>);
    destructor Destroy; override;
    function Clone: TQueryIterator<T>;
    
    // Allows TFluentQuery to grab the underlying list for optimization
    function GetList: IList<T>;
  end;

  /// <summary>
  ///   Iterator that projects elements into a new form.
  /// </summary>
  TProjectingIterator<TSource, TResult> = class(TQueryIterator<TResult>)
  private
    FEnumerator: IEnumerator<TSource>;
    FSelector: TFunc<TSource, TResult>;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(AEnumerator: IEnumerator<TSource>; const ASelector: TFunc<TSource, TResult>);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that filters elements based on a predicate.
  /// </summary>
  TFilteringIterator<T> = class(TQueryIterator<T>)
  private
    FEnumerator: IEnumerator<T>;
    FPredicate: TPredicate<T>;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(AEnumerator: IEnumerator<T>; const APredicate: TPredicate<T>);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that skips a specified number of elements.
  /// </summary>
  TSkipIterator<T> = class(TQueryIterator<T>)
  private
    FEnumerator: IEnumerator<T>;
    FCount: Integer;
    FIndex: Integer;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(AEnumerator: IEnumerator<T>; const ACount: Integer);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that takes a specified number of elements.
  /// </summary>
  TTakeIterator<T> = class(TQueryIterator<T>)
  private
    FEnumerator: IEnumerator<T>;
    FCount: Integer;
    FIndex: Integer;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(AEnumerator: IEnumerator<T>; const ACount: Integer);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that returns distinct elements.
  /// </summary>
  TDistinctIterator<T> = class(TQueryIterator<T>)
  private
    FEnumerator: IEnumerator<T>;
    FSeen: IDictionary<T, Byte>;
  protected
    function MoveNextCore: Boolean; override;
  public
    constructor Create(AEnumerator: IEnumerator<T>);
    destructor Destroy; override;
  end;

  /// <summary>
  ///   Iterator that returns an empty sequence.
  /// </summary>
  TEmptyIterator<T> = class(TQueryIterator<T>)
  protected
    function MoveNextCore: Boolean; override;
  end;

implementation

uses
  System.Variants,
  Dext.Core.Reflection,
  Dext.Specifications.Evaluator,
  Dext.Specifications.OrderBy,
  Dext.Entity.Joining,
  Dext.Entity.Prototype; // Add Prototype


class function TQueryValueHelper.ToDouble(const AValue: TValue): Double;
var
  Raw, Converted: TValue;
begin
  TReflection.TryUnwrapProp(AValue, Raw);
  if Raw.IsEmpty then
    Exit(0);
  case Raw.Kind of
    tkInteger, tkInt64, tkEnumeration: Result := Raw.AsInt64;
    tkFloat: Result := Raw.AsExtended;
  else
    if Raw.TryCast(TypeInfo(Double), Converted) then
      Result := Converted.AsType<Double>
    else
      Result := Raw.AsType<Double>;
  end;
end;

class function TQueryJoinHelper.GetDefaultAlias(ATypeInfo: PTypeInfo): string;
var
  S: string;
  I: Integer;
begin
  S := string(ATypeInfo.Name);
  if (S <> '') and (S[1] = 'T') then
    S := Copy(S, 2, MaxInt);
  if S.StartsWith('Test', True) then
    S := Copy(S, 5, MaxInt);
  
  Result := '';
  for I := 1 to Length(S) do
    if CharInSet(S[I], ['A'..'Z']) then
      Result := Result + LowerCase(S[I]);
      
  if Result = '' then
    Result := LowerCase(Copy(S, 1, 3));
end;

class function TQueryJoinHelper.GetUniqueAlias(ATypeInfo: PTypeInfo; const AJoins: TArray<IJoin>; const ABaseTableAlias: string): string;
var
  BaseAlias: string;
  Candidate: string;
  Suffix: Integer;
  Collision: Boolean;
  J: IJoin;
begin
  BaseAlias := GetDefaultAlias(ATypeInfo);
  Candidate := BaseAlias;
  Suffix := 1;
  while True do
  begin
    Collision := SameText(Candidate, ABaseTableAlias);
    if not Collision then
    begin
      for J in AJoins do
        if SameText(J.GetAlias, Candidate) or SameText(J.GetTableName, Candidate) then
        begin
          Collision := True;
          Break;
        end;
    end;
    if not Collision then
      Exit(Candidate);
      
    Inc(Suffix);
    Candidate := BaseAlias + IntToStr(Suffix);
  end;
end;

class function TQueryJoinHelper.GetPKColumnName(AMap: TEntityMap): string;
var
  PKPropName: string;
  PKProp: TPropertyMap;
begin
  if AMap.Keys.Count > 0 then
  begin
    PKPropName := AMap.Keys[0];
    if AMap.Properties.TryGetValue(PKPropName, PKProp) then
    begin
      if PKProp.ColumnName <> '' then Exit(PKProp.ColumnName);
      Exit(PKProp.PropertyName);
    end;
  end;
  Result := 'Id'; // Default fallback
end;

class function TQueryJoinHelper.ResolveJoinCondition(AOuterType, AInnerType: PTypeInfo; const AOuterAlias, AInnerAlias: string): IExpression;
var
  OuterMap, InnerMap: TEntityMap;
  PropMap: TPropertyMap;
  FKCol, PKCol: string;
  RelationFound: Boolean;
  CandidateFK, CandidatePK: string;
  InnerNameClean, OuterNameClean, FallbackFKName: string;
  FallbackFKProp: TPropertyMap;
  FKProp: TPropertyMap;
begin
  OuterMap := TModelBuilder.Instance.GetMap(AOuterType);
  InnerMap := TModelBuilder.Instance.GetMap(AInnerType);
  if (OuterMap = nil) or (InnerMap = nil) then
    raise Exception.Create('Metadata maps not found for Join types.');

  RelationFound := False;

  // Direction 1: Outer has ForeignKey referencing Inner
  for PropMap in OuterMap.Properties.Values do
  begin
    if (PropMap.PropertyType = AInnerType) or 
       ((PropMap.PropertyType <> nil) and SameText(string(PropMap.PropertyType.Name), string(PTypeInfo(AInnerType).Name))) then
    begin
      if PropMap.ForeignKeyColumn <> '' then
      begin
        CandidateFK := PropMap.ForeignKeyColumn;
        if OuterMap.Properties.TryGetValue(CandidateFK, FKProp) then
        begin
          if FKProp.ColumnName <> '' then CandidateFK := FKProp.ColumnName;
        end;
        
        CandidatePK := GetPKColumnName(InnerMap);
        FKCol := AOuterAlias + '.' + CandidateFK;
        PKCol := AInnerAlias + '.' + CandidatePK;
        RelationFound := True;
        Break;
      end;
    end;
  end;

  // Direction 2: Inner has ForeignKey referencing Outer
  if not RelationFound then
  begin
    for PropMap in InnerMap.Properties.Values do
    begin
      if (PropMap.PropertyType = AOuterType) or 
         ((PropMap.PropertyType <> nil) and SameText(string(PropMap.PropertyType.Name), string(PTypeInfo(AOuterType).Name))) then
      begin
        if PropMap.ForeignKeyColumn <> '' then
        begin
          CandidateFK := PropMap.ForeignKeyColumn;
          if InnerMap.Properties.TryGetValue(CandidateFK, FKProp) then
          begin
            if FKProp.ColumnName <> '' then CandidateFK := FKProp.ColumnName;
          end;
          
          CandidatePK := GetPKColumnName(OuterMap);
          FKCol := AInnerAlias + '.' + CandidateFK;
          PKCol := AOuterAlias + '.' + CandidatePK;
          RelationFound := True;
          Break;
        end;
      end;
    end;
  end;

  // Fallback 1: Naming convention Outer -> Inner (e.g. customer_id or CustomerId)
  if not RelationFound then
  begin
    InnerNameClean := string(AInnerType.Name);
    if InnerNameClean.StartsWith('T') then InnerNameClean := Copy(InnerNameClean, 2, MaxInt);
    if InnerNameClean.StartsWith('Test') then InnerNameClean := Copy(InnerNameClean, 5, MaxInt);
    FallbackFKName := InnerNameClean + 'Id';
    if OuterMap.Properties.TryGetValue(FallbackFKName, FallbackFKProp) then
    begin
      CandidateFK := FallbackFKProp.ColumnName;
      if CandidateFK = '' then CandidateFK := FallbackFKProp.PropertyName;
      CandidatePK := GetPKColumnName(InnerMap);
      FKCol := AOuterAlias + '.' + CandidateFK;
      PKCol := AInnerAlias + '.' + CandidatePK;
      RelationFound := True;
    end;
  end;

  // Fallback 2: Naming convention Inner -> Outer (e.g. order_id or OrderId)
  if not RelationFound then
  begin
    OuterNameClean := string(AOuterType.Name);
    if OuterNameClean.StartsWith('T') then OuterNameClean := Copy(OuterNameClean, 2, MaxInt);
    if OuterNameClean.StartsWith('Test') then OuterNameClean := Copy(OuterNameClean, 5, MaxInt);
    FallbackFKName := OuterNameClean + 'Id';
    if InnerMap.Properties.TryGetValue(FallbackFKName, FallbackFKProp) then
    begin
      CandidateFK := FallbackFKProp.ColumnName;
      if CandidateFK = '' then CandidateFK := FallbackFKProp.PropertyName;
      CandidatePK := GetPKColumnName(OuterMap);
      FKCol := AInnerAlias + '.' + CandidateFK;
      PKCol := AOuterAlias + '.' + CandidatePK;
      RelationFound := True;
    end;
  end;

  if not RelationFound then
    raise Exception.CreateFmt('No mapped relationship found between %s and %s to automatically resolve join condition.',
      [PTypeInfo(AOuterType).Name, PTypeInfo(AInnerType).Name]);

  Result := TBinaryExpression.Create(
    TPropertyExpression.Create(FKCol),
    TPropertyExpression.Create(PKCol),
    boEqual);
end;

{ TEmptyIterator<T> }

function TEmptyIterator<T>.MoveNextCore: Boolean;
begin
  Result := False;
end;

{ TPagedResult<T> }

constructor TPagedResult<T>.Create(AItems: IList<T>; ATotalCount, APageNumber, APageSize: Integer);
begin
  inherited Create;
  FItems := AItems;
  FTotalCount := ATotalCount;
  FPageNumber := APageNumber;
  FPageSize := APageSize;
end;

destructor TPagedResult<T>.Destroy;
begin
  inherited;
end;

function TPagedResult<T>.GetItems: IList<T>;
begin
  Result := FItems;
end;

function TPagedResult<T>.GetTotalCount: Integer;
begin
  Result := FTotalCount;
end;

function TPagedResult<T>.GetPageNumber: Integer;
begin
  Result := FPageNumber;
end;

function TPagedResult<T>.GetPageSize: Integer;
begin
  Result := FPageSize;
end;

function TPagedResult<T>.GetPageCount: Integer;
begin
  if FPageSize <= 0 then Exit(0);
  Result := (FTotalCount + FPageSize - 1) div FPageSize;
end;

function TPagedResult<T>.GetHasNextPage: Boolean;
begin
  Result := FPageNumber < GetPageCount;
end;

function TPagedResult<T>.GetHasPreviousPage: Boolean;
begin
  Result := FPageNumber > 1;
end;

{ TQueryIterator<T> }

constructor TQueryIterator<T>.Create;
begin
  inherited Create;
end;

function TQueryIterator<T>.GetCurrent: T;
begin
  Result := FCurrent;
end;

function TQueryIterator<T>.MoveNext: Boolean;
begin
  Result := MoveNextCore;
end;

{ TFluentQuery<T> }

constructor TFluentQuery<T>.Create(const AIteratorFactory: TFunc<TQueryIterator<T>>; const AConnection: IDbConnection);
begin
  FIteratorFactory := AIteratorFactory;
  FSpecification := nil;
  FConnection := AConnection;
  FNoTracking := False;
  FStreamingIteratorFactory := nil;
end;

constructor TFluentQuery<T>.Create(const AIteratorFactory: TFunc<TQueryIterator<T>>; const ASpec: ISpecification; const AConnection: IDbConnection);
begin
  FIteratorFactory := AIteratorFactory;
  FSpecification := ASpec;
  FExecuteCount := nil;
  FExecuteAny := nil;
  FExecuteFirstOrDefault := nil;
  FConnection := AConnection;
  FLastIncludePath := '';
  FNoTracking := False;
  FStreamingIteratorFactory := nil;
end;

constructor TFluentQuery<T>.Create(
  const AIteratorFactory: TFunc<TQueryIterator<T>>; 
  const ASpec: ISpecification;
  const AExecCount: TFunc<ISpecification, Integer>;
  const AExecAny: TFunc<ISpecification, Boolean>;
  const AExecFirstOrDefault: TFunc<ISpecification, T>;
  const AConnection: IDbConnection;
  const AStreamingFactory: TFunc<IEnumerator<T>>
);
begin
  FIteratorFactory := AIteratorFactory;
  FSpecification := ASpec;
  FExecuteCount := AExecCount;
  FExecuteAny := AExecAny;
  FExecuteFirstOrDefault := AExecFirstOrDefault;
  FConnection := AConnection;
  FLastIncludePath := '';
  FNoTracking := False;
  FStreamingIteratorFactory := AStreamingFactory;
end;

procedure TFluentQuery<T>.AssignSpecTracking(const AEnable: Boolean);
var
  LSpec: ISpecification;
begin
  LSpec := GetSpec;
  if LSpec <> nil then
    LSpec.EnableTracking(AEnable);
end;

function TFluentQuery<T>.GetSpec: ISpecification;
begin
  Result := FSpecification;
end;

function TFluentQuery<T>.GetConnection: IDbConnection;
begin
  Result := FConnection;
end;

function TFluentQuery<T>.GetEnumerator: IEnumerator<T>;
begin
  Result := nil;
  if Assigned(FIteratorFactory) then
     Result := FIteratorFactory();
     
  if Result = nil then
     Result := TEmptyIterator<T>.Create;
end;

function TFluentQuery<T>.GetStreamingEnumerator: IEnumerator<T>;
begin
  if Assigned(FStreamingIteratorFactory) then
     Result := FStreamingIteratorFactory()
  else
     Result := GetEnumerator;
end;

function TFluentQuery<T>.AsNoTracking: TFluentQuery<T>;
begin
  // Set the flag on the specification if available
  AssignSpecTracking(False);
  
  // Return self (record copy) with the modified state
  // Since Specification is a reference type (interface/object), the change persists
  Result := Self;
  Result.FNoTracking := True;
end;

function TFluentQuery<T>.Include(const APath: string): TFluentQuery<T>;
begin
  if FSpecification <> nil then
    FSpecification.Include(APath);
  Result := Self;
  Result.FLastIncludePath := APath;
end;

function TFluentQuery<T>.Include(const AProp: TPropExpression): TFluentQuery<T>;
begin
  if FSpecification <> nil then
    FSpecification.Include(AProp.Name);
  Result := Self;
end;

function TFluentQuery<T>.Include(const AProps: array of TPropExpression): TFluentQuery<T>;
var
  Prop: TPropExpression;
begin
  if FSpecification <> nil then
  begin
    for Prop in AProps do
      FSpecification.Include(Prop.Name);
  end;
  Result := Self;
  Result.FLastIncludePath := ''; // Reset last path because we included multiple
end;

function TFluentQuery<T>.Include(const AProp: IPropInfo): TFluentQuery<T>;
var
  LName: string;
begin
  if AProp = nil then Exit(Self);
  LName := AProp.GetPropertyName;
  Result := Include(LName);
  Result.FLastIncludePath := LName;
end;

function TFluentQuery<T>.ThenInclude(const AProp: IPropInfo): TFluentQuery<T>;
var
  NewPath: string;
  LSpec: ISpecification;
begin
  if AProp = nil then Exit(Self);
  if FLastIncludePath = '' then
    raise Exception.Create('ThenInclude must be called after an Include or another ThenInclude');
    
  NewPath := FLastIncludePath + '.' + AProp.GetPropertyName;
  
  LSpec := GetSpec;
  if LSpec <> nil then
    LSpec.RemoveInclude(FLastIncludePath);
    
  Result := Include(NewPath);
  Result.FLastIncludePath := NewPath;
end;

function TFluentQuery<T>.IgnoreQueryFilters: TFluentQuery<T>;
begin
  if FSpecification <> nil then
     FSpecification.IgnoreQueryFilters;
  Result := Self;
end;

function TFluentQuery<T>.OnlyDeleted: TFluentQuery<T>;
begin
  if FSpecification <> nil then
     FSpecification.OnlyDeleted;
  Result := Self;
end;

function TFluentQuery<T>.WithLock(const ALockMode: TLockMode): TFluentQuery<T>;
begin
  if FSpecification <> nil then
     FSpecification.WithLock(ALockMode);
  Result := Self;
end;

function TFluentQuery<T>.Select<TResult>(const ASelector: TFunc<T, TResult>): TFluentQuery<TResult>;
begin
  Result := TFluentQuery<TResult>.Create(
    CreateSelectFactory<TResult>(FIteratorFactory, ASelector),
    FConnection
  );
end;

class function TFluentQuery<T>.CreateSelectFactory<TResult>(const AFactory: TFunc<TQueryIterator<T>>; const ASelector: TFunc<T, TResult>): TFunc<TQueryIterator<TResult>>;
begin
  Result := TFunc<TQueryIterator<TResult>>(function: TQueryIterator<TResult>
    begin
      Result := TProjectingIterator<T, TResult>.Create(AFactory(), ASelector);
    end);
end;

function TFluentQuery<T>.Select<TResult>(const AProp: Prop<TResult>): TFluentQuery<TResult>;
begin
  Result := Select<TResult>(TPropExpression.Create(AProp.Name));
end;

function TFluentQuery<T>.Select<TResult>(const AProp: TPropExpression): TFluentQuery<TResult>;
var
  LPropName: string;
  LTyp: TRttiType;
  LProp: TRttiProperty;
begin
  LPropName := AProp.Name;

  if FSpecification <> nil then
    FSpecification.Select(LPropName);

  LTyp := TReflection.Context.GetType(TypeInfo(T));
  if LTyp = nil then raise Exception.Create('Could not get RTTI for type');
  LProp := LTyp.GetProperty(LPropName);
  if LProp = nil then
    raise Exception.CreateFmt('Property "%s" not found on class', [LPropName]);

  if LProp = nil then exit(Default(TFluentQuery<TResult>));

  Result := Select<TResult>(CreatePropSelector<TResult>(LProp));
end;

class function TFluentQuery<T>.CreatePropSelector<TResult>(const AProp: TRttiProperty): TFunc<T, TResult>;
begin
  Result := TFunc<T, TResult>(function(const Item: T): TResult
    var
      Instance: TObject;
      Raw, Converted: TValue;
    begin
      Instance := TValue.From<T>(Item).AsObject;
      if Instance = nil then 
        Exit(Default(TResult));
      // A Smart Property (IntType, StringType...) holds the value in a record
      // (TryUnwrapProp returns the value as it came when it is not wrapped)
      TReflection.TryUnwrapProp(AProp.GetValue(Instance), Raw);
      if Raw.IsEmpty then
        Exit(Default(TResult));
      if Raw.TypeInfo = TypeInfo(TResult) then
        Exit(Raw.AsType<TResult>);
      if Raw.TryCast(TypeInfo(TResult), Converted) then
        Result := Converted.AsType<TResult>
      else
        Result := Raw.AsType<TResult>;
    end);
end;

class function TFluentQuery<T>.CreatePropsSelector(const AProperties: TArray<string>): TFunc<T, T>;
begin
  Result := TFunc<T, T>(function(const Source: T): T
    var
      Typ: TRttiType;
      Prop: TRttiProperty;
      Val: TValue;
      ObjSource, ObjDest: TObject;
      PropName: string;
    begin
      Typ := TReflection.Context.GetType(TypeInfo(T));
      if Typ.IsInstance then
      begin
        ObjDest := Typ.AsInstance.MetaclassType.Create;
        try
          ObjSource := TValue.From<T>(Source).AsObject;
          for PropName in AProperties do
          begin
            Prop := Typ.GetProperty(PropName);
            if Prop <> nil then
            begin
              Val := Prop.GetValue(ObjSource);
              if Prop.IsWritable then
                Prop.SetValue(ObjDest, Val);
            end;
          end;
          Result := TValue.From<TObject>(ObjDest).AsType<T>;
        except
          ObjDest.Free;
          raise;
        end;
      end
      else
        Result := Source;
    end);
end;

function TFluentQuery<T>.Select(const AProperties: array of string): TFluentQuery<T>;
var
  Properties: TArray<string>;
  PropName: string;
  Index: Integer;
begin
  Result := Self;
  if FSpecification <> nil then
  begin
    for PropName in AProperties do
      FSpecification.Select(PropName);
    Exit;
  end;

  SetLength(Properties, Length(AProperties));
  for Index := 0 to High(AProperties) do
    Properties[Index] := AProperties[Index];

  Result := Select<T>(CreatePropsSelector(Properties));
end;

function TFluentQuery<T>.WherePredicate(const APredicate: TPredicate<T>): TFluentQuery<T>;
var
  LFactory: TFunc<TQueryIterator<T>>;
  LConn: IDbConnection;
  LPredicate: TPredicate<T>;
begin
  LFactory := FIteratorFactory;
  LConn := FConnection;
  LPredicate := APredicate;
  Result := TFluentQuery<T>.Create(
    TFunc<TQueryIterator<T>>(function: TQueryIterator<T>
    begin
      Result := TFilteringIterator<T>.Create(LFactory(), LPredicate);
    end),
    LConn
  );
end;

function TFluentQuery<T>.Where(const APredicate: TPredicate<T>): TFluentQuery<T>;
begin
  Result := WherePredicate(APredicate);
end;

function TFluentQuery<T>.Where(const APredicate: TQueryPredicate<T>): TFluentQuery<T>;
var
  SmartRes: BooleanExpression;
begin
  SmartRes := APredicate(Dext.Entity.Prototype.Prototype.Entity<T>);
  Result := Where(SmartRes); // Call BooleanExpression overload
end;

function TFluentQuery<T>.Where(const AExpression: TFluentExpression): TFluentQuery<T>;
begin
  Result := Where(AExpression.Expression);
end;

function TFluentQuery<T>.Where(const AValue: BooleanExpression): TFluentQuery<T>;
begin
  Result := Where(AValue.Expression);
end;

function TFluentQuery<T>.Where(const AExpression: IExpression): TFluentQuery<T>;
begin
  if FSpecification <> nil then
  begin
    FSpecification.Where(AExpression);
    Result := Self;
  end
  else
    Result := WherePredicate(
      TPredicate<T>(function(const Item: T): Boolean
      begin
        if PTypeInfo(TypeInfo(T))^.Kind = tkClass then
           Result := TExpressionEvaluator.Evaluate(AExpression, TValue.From<T>(Item).AsObject)
        else
          Result := False;
      end));
end;

function TFluentQuery<T>.Skip(const ACount: Integer): TFluentQuery<T>;
var
  LFactory: TFunc<TQueryIterator<T>>;
  LInnerFactory: TFunc<TQueryIterator<T>>;
  LConn: IDbConnection;
begin
  Result := Self; 
  if FSpecification <> nil then
  begin
    FSpecification.Skip(ACount);
    Exit;
  end;
    
  LInnerFactory := FIteratorFactory;
  LConn := FConnection;
  LFactory := function: TQueryIterator<T>
    begin
      Result := TSkipIterator<T>.Create(LInnerFactory(), ACount);
    end;
  Result := TFluentQuery<T>.Create(LFactory, FSpecification, LConn);
  Result.FNoTracking := FNoTracking;
end;

function TFluentQuery<T>.Take(const ACount: Integer): TFluentQuery<T>;
var
  LFactory: TFunc<TQueryIterator<T>>;
  LInnerFactory: TFunc<TQueryIterator<T>>;
  LConn: IDbConnection;
begin
  Result := Self;
  if FSpecification <> nil then
  begin
    FSpecification.Take(ACount);
    Exit;
  end;

  LInnerFactory := FIteratorFactory;
  LConn := FConnection;
  LFactory := function: TQueryIterator<T>
    begin
      Result := TTakeIterator<T>.Create(LInnerFactory(), ACount);
    end;
  Result := TFluentQuery<T>.Create(LFactory, FSpecification, LConn);
  Result.FNoTracking := FNoTracking;
end;

function TFluentQuery<T>.OrderBy(const AOrderBy: IOrderBy): TFluentQuery<T>;
begin
  if FSpecification <> nil then
    FSpecification.OrderBy(AOrderBy);
  Result := Self;
end;

function TFluentQuery<T>.OrderBy(const AOrders: array of IOrderBy): TFluentQuery<T>;
var
  LOrder: IOrderBy;
begin
  if FSpecification <> nil then
  begin
    for LOrder in AOrders do
      FSpecification.OrderBy(LOrder);
  end;
  Result := Self;
end;

function TFluentQuery<T>.OrderByDescending(const AOrderBy: IOrderBy): TFluentQuery<T>;
begin
  // IOrderBy implementation already has Ascending/Descending flag, 
  // but if we want to force descending on an existing one:
  if FSpecification <> nil then
    FSpecification.OrderBy(TOrderBy.Create(AOrderBy.GetPropertyName, False));
  Result := Self;
end;

function TFluentQuery<T>.OrderBy<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;
begin
  Result := OrderBy(TOrderBy.Create(AProp.Name, True));
end;

function TFluentQuery<T>.OrderByDescending<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;
begin
  Result := OrderBy(TOrderBy.Create(AProp.Name, False));
end;

function TFluentQuery<T>.ThenBy<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;
begin
  Result := OrderBy<TProp>(AProp);
end;

function TFluentQuery<T>.ThenByDescending<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;
begin
  Result := OrderByDescending<TProp>(AProp);
end;

function TFluentQuery<T>.ToList: IList<T>;
var
  Enumerator: IEnumerator<T>;
  OwnsObjects: Boolean;
  LList: TList<T>;
begin
  // DEFAULT BEHAVIOR:
  // Usually, objects are owned by IdentityMap (Tracking=True), so List should NOT own them (OwnsObjects=False).
  // IF AsNoTracking is enabled, entities are NOT in IdentityMap.
  // Therefore, the List MUST own them to avoid memory leaks.
  
  // Checking implicit ownership requirement
  OwnsObjects := FNoTracking;
  if (FSpecification <> nil) and (not FSpecification.IsTrackingEnabled) then
    OwnsObjects := True;

  // Optimization: If the iterator is a TSpecificationQueryIterator, 
  // we can just steal the list it produced (which already has correct ownership settings).
  // This avoids a copy AND solves the double-free issue where iterator frees the list which frees objects.
  Enumerator := GetEnumerator;
  try
    if TObject(Enumerator) is TSpecificationQueryIterator<T> then
    begin
      Result := TSpecificationQueryIterator<T>(TObject(Enumerator)).GetList;
      Exit;
    end;
    
    // Fallback for filtered/projected queries
    LList := TList<T>.Create(OwnsObjects);
    if (FSpecification <> nil) and (FSpecification.GetTake > 0) then
      LList.Capacity := FSpecification.GetTake
    else
      LList.Capacity := 64; // Default sensible initial capacity to avoid early resizing
    Result := LList;
    if Enumerator = nil then Exit;

    try
      while Enumerator.MoveNext do
        LList.Add(Enumerator.Current);

    except
      // If exception happens, result list is freed. 
      // If OwnsObjects=True, it frees *its copy* of references. 
      // The Enumerator also holds references. Lifecycle is complex here but standard exception handling applies.
      Result := nil;
      raise;
    end;
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.ToListAsync: TAsyncBuilder<IList<T>>;
var
  LSpec: ISpecification;
  LConn: IDbConnection;
  LFactory: TFunc<TQueryIterator<T>>;
  LWork: TFunc<IList<T>>;
begin
  if (FConnection <> nil) and not FConnection.Pooled then
    raise Exception.Create('ToListAsync requires a pooled connection to ensure thread safety.');

  LSpec := GetSpec;
  LConn := FConnection;
  LFactory := FIteratorFactory;

  LWork := function: IList<T>
    var
      LTempQuery: TFluentQuery<T>;
    begin
      LTempQuery := TFluentQuery<T>.Create(LFactory, LSpec, LConn);
      Result := LTempQuery.ToList;
    end;
    
  Result := TAsyncTask.Run<IList<T>>(LWork);
end;

function TFluentQuery<T>.Distinct: TFluentQuery<T>;
var
  LFactory: TFunc<TQueryIterator<T>>;
  LInnerFactory: TFunc<TQueryIterator<T>>;
  LConn: IDbConnection;
begin
  LInnerFactory := FIteratorFactory;
  LConn := FConnection;
  LFactory := function: TQueryIterator<T>
    begin
      Result := TDistinctIterator<T>.Create(LInnerFactory());
    end;
  Result := TFluentQuery<T>.Create(LFactory, FSpecification, LConn);
end;

function TFluentQuery<T>.Join<TInner, TKey, TResult>(
  const AInner: TFluentQuery<TInner>;
  const AOuterKeyProp: string;
  const AInnerKeyProp: string;
  const AResultSelector: TFunc<T, TInner, TResult>): TFluentQuery<TResult>;
var
  OuterSelector: TFunc<T, TKey>;
  InnerSelector: TFunc<TInner, TKey>;
begin
  OuterSelector := TFunc<T, TKey>(function(const Item: T): TKey
    var
      Obj: TObject;
      Prop: TRttiProperty;
    begin
      Obj := TValue.From<T>(Item).AsObject;
      Prop := TReflection.Context.GetType(Obj.ClassType).GetProperty(AOuterKeyProp);
      if Prop = nil then
        raise Exception.CreateFmt('Property "%s" not found on outer type', [AOuterKeyProp]);
      Result := Prop.GetValue(Obj).AsType<TKey>;
    end);
    
  InnerSelector := TFunc<TInner, TKey>(function(const Item: TInner): TKey
    var
      Obj: TObject;
      Prop: TRttiProperty;
    begin
      Obj := TValue.From<TInner>(Item).AsObject;
      Prop := TReflection.Context.GetType(Obj.ClassType).GetProperty(AInnerKeyProp);
      if Prop = nil then
        raise Exception.CreateFmt('Property "%s" not found on inner type', [AInnerKeyProp]);
      Result := Prop.GetValue(Obj).AsType<TKey>;
    end);

  Result := TJoining.Join<T, TInner, TKey, TResult>(
    Self, AInner, OuterSelector, InnerSelector, AResultSelector);
end;

function TFluentQuery<T>.Join(const ATable, AAlias: string; const AType: TJoinType; const ACondition: IExpression): TFluentQuery<T>;
begin
  if FSpecification <> nil then
    FSpecification.Join(ATable, AAlias, AType, ACondition);
  Result := Self;
end;

function TFluentQuery<T>.Join(const ATable, AAlias: string; const ACondition: string;
  const AType: TJoinType): TFluentQuery<T>;
begin
  Result := Join(ATable, AAlias, AType, JoinStringToEqualsExpression(ACondition));
end;

function TFluentQuery<T>.JoinInner<TInner>: TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinInner<TInner>(LAlias);
end;

function TFluentQuery<T>.JoinInner<TInner>(const AAlias: string): TFluentQuery<T>;
var
  LOuterMap: TEntityMap;
  LOuterAlias: string;
  LCond: IExpression;
begin
  LOuterMap := TModelBuilder.Instance.GetMap(TypeInfo(T));
  LOuterAlias := LOuterMap.TableName;
  LCond := TQueryJoinHelper.ResolveJoinCondition(TypeInfo(T), TypeInfo(TInner), LOuterAlias, AAlias);
  Result := JoinInner<TInner>(AAlias, LCond);
end;

function TFluentQuery<T>.JoinInner<TInner>(const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinInner<TInner>(LAlias, AOn);
end;

function TFluentQuery<T>.JoinInner<TInner>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  Result := Join(LInnerMap.TableName, AAlias, jtInner, AOn);
end;

function TFluentQuery<T>.JoinLeft<TInner>: TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinLeft<TInner>(LAlias);
end;

function TFluentQuery<T>.JoinLeft<TInner>(const AAlias: string): TFluentQuery<T>;
var
  LOuterMap: TEntityMap;
  LOuterAlias: string;
  LCond: IExpression;
begin
  LOuterMap := TModelBuilder.Instance.GetMap(TypeInfo(T));
  LOuterAlias := LOuterMap.TableName;
  LCond := TQueryJoinHelper.ResolveJoinCondition(TypeInfo(T), TypeInfo(TInner), LOuterAlias, AAlias);
  Result := JoinLeft<TInner>(AAlias, LCond);
end;

function TFluentQuery<T>.JoinLeft<TInner>(const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinLeft<TInner>(LAlias, AOn);
end;

function TFluentQuery<T>.JoinLeft<TInner>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  Result := Join(LInnerMap.TableName, AAlias, jtLeft, AOn);
end;

function TFluentQuery<T>.JoinRight<TInner>: TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinRight<TInner>(LAlias);
end;

function TFluentQuery<T>.JoinRight<TInner>(const AAlias: string): TFluentQuery<T>;
var
  LOuterMap: TEntityMap;
  LOuterAlias: string;
  LCond: IExpression;
begin
  LOuterMap := TModelBuilder.Instance.GetMap(TypeInfo(T));
  LOuterAlias := LOuterMap.TableName;
  LCond := TQueryJoinHelper.ResolveJoinCondition(TypeInfo(T), TypeInfo(TInner), LOuterAlias, AAlias);
  Result := JoinRight<TInner>(AAlias, LCond);
end;

function TFluentQuery<T>.JoinRight<TInner>(const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinRight<TInner>(LAlias, AOn);
end;

function TFluentQuery<T>.JoinRight<TInner>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  Result := Join(LInnerMap.TableName, AAlias, jtRight, AOn);
end;

function TFluentQuery<T>.JoinFull<TInner>: TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinFull<TInner>(LAlias);
end;

// Alias + Auto ON
function TFluentQuery<T>.JoinFull<TInner>(const AAlias: string): TFluentQuery<T>;
var
  LOuterMap: TEntityMap;
  LOuterAlias: string;
  LCond: IExpression;
begin
  LOuterMap := TModelBuilder.Instance.GetMap(TypeInfo(T));
  LOuterAlias := LOuterMap.TableName;
  LCond := TQueryJoinHelper.ResolveJoinCondition(TypeInfo(T), TypeInfo(TInner), LOuterAlias, AAlias);
  Result := JoinFull<TInner>(AAlias, LCond);
end;

function TFluentQuery<T>.JoinFull<TInner>(const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinFull<TInner>(LAlias, AOn);
end;

function TFluentQuery<T>.JoinFull<TInner>(const AAlias: string; const AOn: IExpression): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  Result := Join(LInnerMap.TableName, AAlias, jtFull, AOn);
end;

function TFluentQuery<T>.JoinCross<TInner>: TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
  LAlias: string;
  LJoins: TArray<IJoin>;
  LOuterAlias: string;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  LJoins := [];
  if FSpecification <> nil then LJoins := FSpecification.GetJoins;
  LOuterAlias := TModelBuilder.Instance.GetMap(TypeInfo(T)).TableName;
  LAlias := TQueryJoinHelper.GetUniqueAlias(TypeInfo(TInner), LJoins, LOuterAlias);
  Result := JoinCross<TInner>(LAlias);
end;

function TFluentQuery<T>.JoinCross<TInner>(const AAlias: string): TFluentQuery<T>;
var
  LInnerMap: TEntityMap;
begin
  LInnerMap := TModelBuilder.Instance.GetMap(TypeInfo(TInner));
  if LInnerMap = nil then raise Exception.Create('Inner type not mapped');
  Result := Join(LInnerMap.TableName, AAlias, jtCross, nil);
end;

class function TFluentQuery<T>.JoinStringToEqualsExpression(const ACondition: string): IExpression;
var
  EqPos: Integer;
  L, R, S: string;
begin
  S := Trim(ACondition);
  if S = '' then
    raise EArgumentException.Create('Join condition cannot be empty.');

  EqPos := Pos('=', S);
  if (EqPos <= 0) or (EqPos = Length(S)) then
    raise EArgumentException.CreateFmt(
      'Join condition must look like "left = right", got "%s".', [ACondition]);

  L := Trim(Copy(S, 1, EqPos - 1));
  R := Trim(Copy(S, EqPos + 1, MaxInt));
  if (L = '') or (R = '') then
    raise EArgumentException.CreateFmt('Invalid join condition "%s".', [ACondition]);

  Result := TBinaryExpression.Create(
    TPropertyExpression.Create(L),
    TPropertyExpression.Create(R),
    boEqual);
end;

function TFluentQuery<T>.GroupBy(const AColumn: string): TFluentQuery<T>;
begin
  if FSpecification <> nil then
    FSpecification.GroupBy(AColumn);
  Result := Self;
end;

function TFluentQuery<T>.GroupBy(const AColumns: array of string): TFluentQuery<T>;
var
  Col: string;
begin
  if FSpecification <> nil then
  begin
    for Col in AColumns do
      FSpecification.GroupBy(Col);
  end;
  Result := Self;
end;

function TFluentQuery<T>.GroupBy<TProp>(const AProp: Prop<TProp>): TFluentQuery<T>;
begin
  Result := GroupBy(AProp.Name);
end;

function TFluentQuery<T>.Count: Integer;
var
  Enumerator: IEnumerator<T>;
begin
  if Assigned(FExecuteCount) and (FSpecification <> nil) then
    Exit(FExecuteCount(FSpecification));

  Result := 0;
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
      Inc(Result);
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.Count(const APredicate: TPredicate<T>): Integer;
var
  Enumerator: IEnumerator<T>;
begin
  Result := 0;
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
      if APredicate(Enumerator.Current) then
        Inc(Result);
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.Any: Boolean;
var
  Enumerator: IEnumerator<T>;
begin
  if Assigned(FExecuteAny) and (FSpecification <> nil) then
    Exit(FExecuteAny(FSpecification));

  Enumerator := GetEnumerator;
  try
    Result := Enumerator.MoveNext;
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.Any(const APredicate: TPredicate<T>): Boolean;
var
  Enumerator: IEnumerator<T>;
begin
  Result := False;
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
      if APredicate(Enumerator.Current) then
      begin
        Result := True;
        Break;
      end;
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.First: T;
var
  Enumerator: IEnumerator<T>;
begin
  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
      Result := Enumerator.Current
    else
      raise Exception.Create('Sequence contains no elements');
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.First(const APredicate: TPredicate<T>): T;
var
  Enumerator: IEnumerator<T>;
begin
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
      if APredicate(Enumerator.Current) then
        Exit(Enumerator.Current);
  finally
    Enumerator := nil;
  end;
  raise Exception.Create('Sequence contains no matching element');
end;

function TFluentQuery<T>.FirstOrDefault: T;
var
  Enumerator: IEnumerator<T>;
begin
  if Assigned(FExecuteFirstOrDefault) and (FSpecification <> nil) then
    Exit(FExecuteFirstOrDefault(FSpecification));

  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
      Result := Enumerator.Current
    else
      Result := Default(T);
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.FirstOrDefault(const APredicate: TPredicate<T>): T;
var
  Enumerator: IEnumerator<T>;
begin
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
      if APredicate(Enumerator.Current) then
        Exit(Enumerator.Current);
  finally
    Enumerator := nil;
  end;
  Result := Default(T);
end;

function TFluentQuery<T>.Sum(const ASelector: TFunc<T, Double>): Double;
var
  Enumerator: IEnumerator<T>;
begin
  Result := 0;
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
      Result := Result + ASelector(Enumerator.Current);
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.Sum(const APropertyName: string): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  Obj: TObject;
  Prop: TRttiProperty;
  Map: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
begin
  Result := 0;
  Prop := nil;
  
  // Use cached Map for Property lookup (Fastest path)
  Map := TModelBuilder.Instance.GetMap(TypeInfo(T));
  if (Map <> nil) and Map.Properties.TryGetValue(APropertyName, PropMap) then
    Prop := PropMap.Prop;
  
  if Prop = nil then
  begin
    Typ := TReflection.Context.GetType(TypeInfo(T));
    if Typ <> nil then
      Prop := Typ.GetProperty(APropertyName);
  end;
  
  if Prop = nil then
    raise Exception.CreateFmt('Property "%s" not found on type "%s"', [APropertyName, PTypeInfo(TypeInfo(T)).Name]);

  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
    begin
      Obj := TValue.From<T>(Enumerator.Current).AsObject;
      if Obj <> nil then
      begin
        Val := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
        Result := Result + Val;
      end;
    end;
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.Average(const ASelector: TFunc<T, Double>): Double;
var
  Enumerator: IEnumerator<T>;
  SumVal: Double;
  CountVal: Integer;
begin
  SumVal := 0;
  CountVal := 0;
  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
    begin
      SumVal := SumVal + ASelector(Enumerator.Current);
      Inc(CountVal);
    end;
  finally
    Enumerator := nil;
  end;
  
  if CountVal = 0 then
    raise Exception.Create('Sequence contains no elements');
    
  Result := SumVal / CountVal;
end;

function TFluentQuery<T>.Average(const APropertyName: string): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  SumVal: Double;
  CountVal: Integer;
  Obj: TObject;
  Prop: TRttiProperty;
  Map: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
begin
  SumVal := 0;
  CountVal := 0;
  Prop := nil;
  
  Map := TModelBuilder.Instance.GetMap(TypeInfo(T));
  if (Map <> nil) and Map.Properties.TryGetValue(APropertyName, PropMap) then
    Prop := PropMap.Prop;
    
  if Prop = nil then
  begin
    Typ := TReflection.Context.GetType(TypeInfo(T));
    if Typ <> nil then
      Prop := Typ.GetProperty(APropertyName);
  end;

  if Prop = nil then
    raise Exception.CreateFmt('Property "%s" not found on type "%s"', [APropertyName, PTypeInfo(TypeInfo(T)).Name]);

  Enumerator := GetEnumerator;
  try
    while Enumerator.MoveNext do
    begin
      Obj := TValue.From<T>(Enumerator.Current).AsObject;
      if Obj <> nil then
      begin
        Val := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
        SumVal := SumVal + Val;
        Inc(CountVal);
      end;
    end;
  finally
    Enumerator := nil;
  end;
  
  if CountVal = 0 then
    raise Exception.Create('Sequence contains no elements');
    
  Result := SumVal / CountVal;
end;

function TFluentQuery<T>.Min(const ASelector: TFunc<T, Double>): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  HasValue: Boolean;
begin
  HasValue := False;
  Result := 0;
  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
    begin
      Result := ASelector(Enumerator.Current);
      HasValue := True;
      
      while Enumerator.MoveNext do
      begin
        Val := ASelector(Enumerator.Current);
        if Val < Result then Result := Val;
      end;
    end;
  finally
    Enumerator := nil;
  end;
  
  if not HasValue then
    raise Exception.Create('Sequence contains no elements');
end;

function TFluentQuery<T>.Min(const APropertyName: string): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  HasValue: Boolean;
  Obj: TObject;
  Prop: TRttiProperty;
  Map: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
begin
  HasValue := False;
  Result := 0;
  Prop := nil;
  
  Map := TModelBuilder.Instance.GetMap(TypeInfo(T));
  if (Map <> nil) and Map.Properties.TryGetValue(APropertyName, PropMap) then
    Prop := PropMap.Prop;
  
  if Prop = nil then
  begin
    Typ := TReflection.Context.GetType(TypeInfo(T));
    if Typ <> nil then
      Prop := Typ.GetProperty(APropertyName);
  end;

  if Prop = nil then
    raise Exception.CreateFmt('Property "%s" not found on type "%s"', [APropertyName, PTypeInfo(TypeInfo(T)).Name]);

  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
    begin
      Obj := TValue.From<T>(Enumerator.Current).AsObject;
      if Obj <> nil then
      begin
        Result := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
        HasValue := True;
        
        while Enumerator.MoveNext do
        begin
          Obj := TValue.From<T>(Enumerator.Current).AsObject;
          if Obj <> nil then
          begin
            Val := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
            if Val < Result then Result := Val;
          end;
        end;
      end;
    end;
  finally
    Enumerator := nil;
  end;
  
  if not HasValue then
    raise Exception.Create('Sequence contains no elements');
end;

function TFluentQuery<T>.Max(const ASelector: TFunc<T, Double>): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  HasValue: Boolean;
begin
  HasValue := False;
  Result := 0;
  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
    begin
      Result := ASelector(Enumerator.Current);
      HasValue := True;
      
      while Enumerator.MoveNext do
      begin
        Val := ASelector(Enumerator.Current);
        if Val > Result then Result := Val;
      end;
    end;
  finally
    Enumerator := nil;
  end;
  
  if not HasValue then
    raise Exception.Create('Sequence contains no elements');
end;

function TFluentQuery<T>.Max(const APropertyName: string): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  HasValue: Boolean;
  Obj: TObject;
  Prop: TRttiProperty;
  Map: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
begin
  HasValue := False;
  Result := 0;
  Prop := nil;
  
  Map := TModelBuilder.Instance.GetMap(TypeInfo(T));
  if (Map <> nil) and Map.Properties.TryGetValue(APropertyName, PropMap) then
    Prop := PropMap.Prop;
  
  if Prop = nil then
  begin
    Typ := TReflection.Context.GetType(TypeInfo(T));
    if Typ <> nil then
      Prop := Typ.GetProperty(APropertyName);
  end;

  if Prop = nil then
    raise Exception.CreateFmt('Property "%s" not found on type "%s"', [APropertyName, PTypeInfo(TypeInfo(T)).Name]);

  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
    begin
      Obj := TValue.From<T>(Enumerator.Current).AsObject;
      if Obj <> nil then
      begin
        Result := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
        HasValue := True;
        
        while Enumerator.MoveNext do
        begin
          Obj := TValue.From<T>(Enumerator.Current).AsObject;
          if Obj <> nil then
          begin
            Val := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
            if Val > Result then Result := Val;
          end;
        end;
      end;
    end;
  finally
    Enumerator := nil;
  end;
  
  if not HasValue then
    raise Exception.Create('Sequence contains no elements');
end;

function TFluentQuery<T>.Max(const AProp: IPropInfo): Double;
begin
  Result := Max(AProp.PropertyName);
end;

function TFluentQuery<T>.MaxOrDefault(const AProp: IPropInfo; const ADefault: Double): Double;
begin
  Result := MaxOrDefault(AProp.PropertyName, ADefault);
end;

function TFluentQuery<T>.MaxOrDefault(const ASelector: TFunc<T, Double>; const ADefault: Double): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
begin
  Result := ADefault;
  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
    begin
      Result := ASelector(Enumerator.Current);
      while Enumerator.MoveNext do
      begin
        Val := ASelector(Enumerator.Current);
        if Val > Result then Result := Val;
      end;
    end;
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.MaxOrDefault(const APropertyName: string; const ADefault: Double): Double;
var
  Enumerator: IEnumerator<T>;
  Val: Double;
  Obj: TObject;
  Prop: TRttiProperty;
  Map: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
begin
  Result := ADefault;
  Prop := nil;
  
  Map := TModelBuilder.Instance.GetMap(TypeInfo(T));
  if (Map <> nil) and Map.Properties.TryGetValue(APropertyName, PropMap) then
    Prop := PropMap.Prop;
    
  if Prop = nil then
  begin
    Typ := TReflection.Context.GetType(TypeInfo(T));
    if Typ <> nil then
      Prop := Typ.GetProperty(APropertyName);
  end;

  if Prop = nil then Exit;

  Enumerator := GetEnumerator;
  try
    if Enumerator.MoveNext then
    begin
      Obj := TValue.From<T>(Enumerator.Current).AsObject;
      if Obj <> nil then
      begin
        Result := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
        while Enumerator.MoveNext do
        begin
          Obj := TValue.From<T>(Enumerator.Current).AsObject;
          if Obj <> nil then
          begin
            Val := TQueryValueHelper.ToDouble(Prop.GetValue(Obj));
            if Val > Result then Result := Val;
          end;
        end;
      end;
    end;
  finally
    Enumerator := nil;
  end;
end;

function TFluentQuery<T>.Paginate(const APageNumber, APageSize: Integer): IPagedResult<T>;
var
  SkipCount: Integer;
  Total: Integer;
  Items: IList<T>;
begin
  if APageNumber < 1 then raise Exception.Create('PageNumber must be >= 1');
  if APageSize < 1 then raise Exception.Create('PageSize must be >= 1');
  
  Total := Self.Count;
  SkipCount := (APageNumber - 1) * APageSize;
  
  Items := Self.Skip(SkipCount).Take(APageSize).ToList;
  
  Result := TPagedResult<T>.Create(Items, Total, APageNumber, APageSize);
end;

{ TSpecificationQueryIterator<T> }

constructor TSpecificationQueryIterator<T>.Create(const AGetList: TFunc<IList<T>>);
begin
  inherited Create;
  FGetList := AGetList;
  FIndex := -1;
  FExecuted := False;
  FList := nil; 
end;

destructor TSpecificationQueryIterator<T>.Destroy;
begin
  inherited;
end;

function TSpecificationQueryIterator<T>.Clone: TQueryIterator<T>;
begin
  Result := TSpecificationQueryIterator<T>.Create(FGetList);
end;

function TSpecificationQueryIterator<T>.GetList: IList<T>;
begin
  if not FExecuted then
  begin
    FList := FGetList();
    FExecuted := True;
    FIndex := -1;
  end;
  Result := FList;
end;

function TSpecificationQueryIterator<T>.MoveNextCore: Boolean;
begin
  if not FExecuted then
  begin
    // Trigger execution
    GetList;
  end;
  
  Inc(FIndex);
  if (FList <> nil) and (FIndex < FList.Count) then
  begin
    FCurrent := FList[FIndex];
    Result := True;
  end
  else
    Result := False;
end;

constructor TProjectingIterator<TSource, TResult>.Create(AEnumerator: IEnumerator<TSource>; const ASelector: TFunc<TSource, TResult>);
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FSelector := ASelector;
end;

destructor TProjectingIterator<TSource, TResult>.Destroy;
begin
  FEnumerator := nil;
  inherited;
end;

function TProjectingIterator<TSource, TResult>.MoveNextCore: Boolean;
begin
  if FEnumerator.MoveNext then
  begin
    FCurrent := FSelector(FEnumerator.Current);
    Result := True;
  end
  else
    Result := False;
end;

{ TFilteringIterator<T> }

constructor TFilteringIterator<T>.Create(AEnumerator: IEnumerator<T>; const APredicate: TPredicate<T>);
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FPredicate := APredicate;
end;

destructor TFilteringIterator<T>.Destroy;
begin
  FEnumerator := nil;
  inherited;
end;

function TFilteringIterator<T>.MoveNextCore: Boolean;
begin
  while FEnumerator.MoveNext do
  begin
    if FPredicate(FEnumerator.Current) then
    begin
      FCurrent := FEnumerator.Current;
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TSkipIterator<T> }

constructor TSkipIterator<T>.Create(AEnumerator: IEnumerator<T>; const ACount: Integer);
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FCount := ACount;
  FIndex := 0;
end;

destructor TSkipIterator<T>.Destroy;
begin
  FEnumerator := nil;
  inherited;
end;

function TSkipIterator<T>.MoveNextCore: Boolean;
begin
  // First time filtering
  while FIndex < FCount do
  begin
    if not FEnumerator.MoveNext then Exit(False);
    Inc(FIndex);
  end;
  
  if FEnumerator.MoveNext then
  begin
    FCurrent := FEnumerator.Current;
    Result := True;
  end
  else
    Result := False;
end;

{ TTakeIterator<T> }

constructor TTakeIterator<T>.Create(AEnumerator: IEnumerator<T>; const ACount: Integer);
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FCount := ACount;
  FIndex := 0;
end;

destructor TTakeIterator<T>.Destroy;
begin
  FEnumerator := nil;
  inherited;
end;

function TTakeIterator<T>.MoveNextCore: Boolean;
begin
  if FIndex >= FCount then Exit(False);
  
  if FEnumerator.MoveNext then
  begin
    FCurrent := FEnumerator.Current;
    Inc(FIndex);
    Result := True;
  end
  else
    Result := False;
end;

{ TDistinctIterator<T> }

constructor TDistinctIterator<T>.Create(AEnumerator: IEnumerator<T>);
begin
  inherited Create;
  FEnumerator := AEnumerator;
  FSeen := TCollections.CreateDictionary<T, Byte>;
end;

destructor TDistinctIterator<T>.Destroy;
begin
  FSeen := nil;
  FEnumerator := nil;
  inherited;
end;

function TDistinctIterator<T>.MoveNextCore: Boolean;
begin
  while FEnumerator.MoveNext do
  begin
    if not FSeen.ContainsKey(FEnumerator.Current) then
    begin
      FSeen.Add(FEnumerator.Current, 0);
      FCurrent := FEnumerator.Current;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.

