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
unit Dext.Specifications.Base;

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Vector,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types;
  
type
  TJoin = class(TInterfacedObject, IJoin)
  private
    FTableName: string;
    FAlias: string;
    FType: TJoinType;
    FCondition: IExpression;
  public
    constructor Create(const ATable, AAlias: string; AType: TJoinType; const ACondition: IExpression);
    function GetTableName: string;
    function GetAlias: string;
    function GetJoinType: TJoinType;
    function GetCondition: IExpression;
  end;

type
  /// <summary>
  ///   Base class for Specifications.
  ///   Inherit from this class to define reusable query logic.
  /// </summary>
  TSpecification<T: class> = class(TInterfacedObject, ISpecification, ISpecification<T>)
  protected
    FExpression: IExpression;
    FIncludes: TVector<string>;
    FSelectedColumns: TVector<string>;
    FOrderBy: TVector<IOrderBy>;
    FSkip: Integer;
    FTake: Integer;
    FIsPagingEnabled: Boolean;
    FIsTracking: Boolean;
    
    FJoins: TVector<IJoin>;
    FGroupBy: TVector<string>;
    FHaving: IExpression;
    FSelectItems: TVector<TSelectItem>;
    FIgnoreQueryFilters: Boolean;
    FOnlyDeleted: Boolean;
    FLockMode: TLockMode;
    
    // Implementation of ISpecification<T>
    function GetExpression: IExpression;
    function GetIncludes: TArray<string>;
    function GetOrderBy: TArray<IOrderBy>;
    function GetSkip: Integer;
    function GetTake: Integer;
    function IsPagingEnabled: Boolean;
    function IsTrackingEnabled: Boolean;

    function GetSelectedColumns: TArray<string>;
    function GetJoins: TArray<IJoin>;
    function GetGroupBy: TArray<string>;
    function GetHaving: IExpression;
    function GetSelectItems: TArray<TSelectItem>;
    function IsIgnoringFilters: Boolean;
    function IsOnlyDeleted: Boolean;
    function GetLockMode: TLockMode;
    function GetSignature: string; virtual;
    function Clone: ISpecification<T>; virtual;
  public
    constructor Create; overload; virtual;
    constructor Create(const AExpression: IExpression); overload; virtual;
    destructor Destroy; override;
    
    // Fluent Builders (public for TSpecificationBuilder)
    procedure Where(const AExpression: IExpression);
    procedure Include(const APath: string); virtual;
    procedure RemoveInclude(const APath: string); virtual;
    procedure OrderBy(const AOrderBy: IOrderBy); virtual;
    procedure Select(const AColumn: string); virtual;
    procedure Join(const ATable: string; const AAlias: string; AType: TJoinType; const ACondition: IExpression); virtual;
    procedure GroupBy(const AColumn: string); virtual;
    procedure Having(const AExpression: IExpression); virtual;
    procedure SelectItem(const AExpression: IExpression;
      const AAlias: string); virtual;
    procedure IgnoreQueryFilters(const AValue: Boolean = True); virtual;
    procedure OnlyDeleted(const AValue: Boolean = True); virtual;
    procedure WithLock(const ALockMode: TLockMode); virtual;

    // Legacy support
    procedure AddInclude(const APath: string);
    procedure AddOrderBy(const AOrderBy: IOrderBy);
    procedure AddSelect(const AColumn: string);

    procedure ApplyPaging(ASkip, ATake: Integer);
    
    // Fluent Helpers
    procedure Take(const ACount: Integer);
    procedure Skip(const ACount: Integer);
    
    procedure EnableTracking(const AValue: Boolean);
    procedure AsNoTracking;

    function AndSpec(const Other: ISpecification<T>): ISpecification<T>; virtual;
    function OrSpec(const Other: ISpecification<T>): ISpecification<T>; virtual;
    function NotSpec: ISpecification<T>; virtual;
    function IsSatisfiedBy(const AEntity: T): Boolean; virtual;
  end;
    
implementation

uses
  Dext.Specifications.Evaluator;

{ TSpecification<T> }

constructor TSpecification<T>.Create;
begin
  inherited;
  FLockMode := lmNone;
  FExpression := nil; // Empty expression matches all
  FIsTracking := True; // Tracking enabled by default
  FIgnoreQueryFilters := False;
  FOnlyDeleted := False;
end;

constructor TSpecification<T>.Create(const AExpression: IExpression);
begin
  Create;
  FExpression := AExpression;
end;

destructor TSpecification<T>.Destroy;
begin
  FExpression := nil;
  FIncludes.Clear;
  FSelectedColumns.Clear;
  FOrderBy.Clear;
  FJoins.Clear;
  FGroupBy.Clear;
  FHaving := nil;
  FSelectItems.Clear;
  inherited;
end;

procedure TSpecification<T>.Where(const AExpression: IExpression);
begin
  if FExpression = nil then
    FExpression := AExpression
  else
    // Combine with AND
    FExpression := TLogicalExpression.Create(FExpression, AExpression, loAnd);
end;

procedure TSpecification<T>.Include(const APath: string);
begin
  FIncludes.Add(APath);
end;

procedure TSpecification<T>.RemoveInclude(const APath: string);
begin
  FIncludes.Remove(APath);
end;

procedure TSpecification<T>.AddInclude(const APath: string);
begin
  Include(APath);
end;

procedure TSpecification<T>.ApplyPaging(ASkip, ATake: Integer);
begin
  FSkip := ASkip;
  FTake := ATake;
  FIsPagingEnabled := True;
end;

function TSpecification<T>.GetExpression: IExpression;
begin
  Result := FExpression;
end;

function TSpecification<T>.GetIncludes: TArray<string>;
begin
  Result := FIncludes.ToArray;
end;

function TSpecification<T>.GetOrderBy: TArray<IOrderBy>;
begin
  Result := FOrderBy.ToArray;
end;

function TSpecification<T>.GetSkip: Integer;
begin
  Result := FSkip;
end;

function TSpecification<T>.GetTake: Integer;
begin
  Result := FTake;
end;

function TSpecification<T>.IsPagingEnabled: Boolean;
begin
  Result := FIsPagingEnabled;
end;

procedure TSpecification<T>.OrderBy(const AOrderBy: IOrderBy);
begin
  FOrderBy.Add(AOrderBy);
end;

procedure TSpecification<T>.AddOrderBy(const AOrderBy: IOrderBy);
begin
  OrderBy(AOrderBy);
end;

function TSpecification<T>.GetSelectedColumns: TArray<string>;
begin
  Result := FSelectedColumns.ToArray;
end;

procedure TSpecification<T>.Select(const AColumn: string);
begin
  FSelectedColumns.Add(AColumn);
end;

procedure TSpecification<T>.AddSelect(const AColumn: string);
begin
  Select(AColumn);
end;

procedure TSpecification<T>.Take(const ACount: Integer);
begin
  FTake := ACount;
  FIsPagingEnabled := True;
end;

procedure TSpecification<T>.Skip(const ACount: Integer);
begin
  FSkip := ACount;
  FIsPagingEnabled := True;
end;

function TSpecification<T>.IsTrackingEnabled: Boolean;
begin
  Result := FIsTracking;
end;

function TSpecification<T>.GetLockMode: TLockMode;
begin
  Result := FLockMode;
end;

procedure TSpecification<T>.WithLock(const ALockMode: TLockMode);
begin
  FLockMode := ALockMode;
end;

procedure TSpecification<T>.EnableTracking(const AValue: Boolean);
begin
  FIsTracking := AValue;
end;

procedure TSpecification<T>.AsNoTracking;
begin
  FIsTracking := False;
end;

procedure TSpecification<T>.Join(const ATable: string; const AAlias: string; AType: TJoinType; const ACondition: IExpression);
begin
  FJoins.Add(TJoin.Create(ATable, AAlias, AType, ACondition));
end;

procedure TSpecification<T>.GroupBy(const AColumn: string);
begin
  FGroupBy.Add(AColumn);
end;

procedure TSpecification<T>.Having(const AExpression: IExpression);
begin
  if FHaving = nil then
    FHaving := AExpression
  else
    FHaving := TLogicalExpression.Create(FHaving, AExpression, loAnd);
end;

procedure TSpecification<T>.SelectItem(const AExpression: IExpression;
  const AAlias: string);
var
  Item: TSelectItem;
begin
  Item.Expression := AExpression;
  Item.Alias := AAlias;
  FSelectItems.Add(Item);
end;

function TSpecification<T>.GetHaving: IExpression;
begin
  Result := FHaving;
end;

function TSpecification<T>.GetSelectItems: TArray<TSelectItem>;
begin
  Result := FSelectItems.ToArray;
end;

procedure TSpecification<T>.IgnoreQueryFilters(const AValue: Boolean);
begin
  FIgnoreQueryFilters := AValue;
end;

procedure TSpecification<T>.OnlyDeleted(const AValue: Boolean);
begin
  FOnlyDeleted := AValue;
end;

function TSpecification<T>.GetJoins: TArray<IJoin>;
begin
  Result := FJoins.ToArray;
end;

function TSpecification<T>.GetGroupBy: TArray<string>;
begin
  Result := FGroupBy.ToArray;
end;

function TSpecification<T>.IsIgnoringFilters: Boolean;
begin
  Result := FIgnoreQueryFilters;
end;

function TSpecification<T>.IsOnlyDeleted: Boolean;
begin
  Result := FOnlyDeleted;
end;

function TSpecification<T>.GetSignature: string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    // 1. Entity Type
    SB.Append(PTypeInfo(TypeInfo(T)).Name);
    
    // 2. Select Columns
    if FSelectedColumns.Count > 0 then
    begin
      SB.Append(':SELECT[');
      for I := 0 to FSelectedColumns.Count - 1 do
        SB.Append(FSelectedColumns[I]).Append(',');
      SB.Append(']');
    end;
    
    // 3. Includes
    if FIncludes.Count > 0 then
    begin
      SB.Append(':INC[');
      for I := 0 to FIncludes.Count - 1 do
        SB.Append(FIncludes[I]).Append(',');
      SB.Append(']');
    end;
    
    // 4. Expression
    if FExpression <> nil then
      SB.Append(':WHERE[').Append(FExpression.ToString).Append(']');
      
    // 5. OrderBy
    if FOrderBy.Count > 0 then
    begin
      SB.Append(':ORD[');
      for I := 0 to FOrderBy.Count - 1 do
      begin
        SB.Append(FOrderBy[I].GetPropertyName);
        if FOrderBy[I].GetAscending then SB.Append('+') else SB.Append('-');
        SB.Append(',');
      end;
      SB.Append(']');
    end;
    
    // 6. Joins
    if FJoins.Count > 0 then
    begin
      SB.Append(':JOIN[');
      for I := 0 to FJoins.Count - 1 do
      begin
        SB.Append(FJoins[I].GetTableName).Append('|').Append(FJoins[I].GetAlias);
        // Note: Condition might be complex, currently ToString assumed consistent
        SB.Append(',');
      end;
      SB.Append(']');
    end;
    
    // 7. Paging
    if FIsPagingEnabled then
      SB.Append(':P[').Append(FSkip).Append(',').Append(FTake).Append(']')
    else
      SB.Append(':P[OFF]');
      
    // 8. GroupBy
    if FGroupBy.Count > 0 then
    begin
      SB.Append(':GRP[');
      for I := 0 to FGroupBy.Count - 1 do
        SB.Append(FGroupBy[I]).Append(',');
      SB.Append(']');
    end;

    // 8b. Projection items and Having
    if FSelectItems.Count > 0 then
    begin
      SB.Append(':SEL[');
      for I := 0 to FSelectItems.Count - 1 do
        SB.Append(FSelectItems[I].Expression.ToString).Append(' AS ')
          .Append(FSelectItems[I].Alias).Append(',');
      SB.Append(']');
    end;
    if FHaving <> nil then
      SB.Append(':HAV[').Append(FHaving.ToString).Append(']');

    // 9. Tracking & Filters
    SB.Append(':TRK[').Append(Ord(FIsTracking)).Append(']');
    SB.Append(':IGN[').Append(Ord(FIgnoreQueryFilters)).Append(']');
    SB.Append(':DEL[').Append(Ord(FOnlyDeleted)).Append(']');
    SB.Append(':LCK[').Append(Ord(FLockMode)).Append(']');
    
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TJoin }

constructor TJoin.Create(const ATable, AAlias: string; AType: TJoinType; const ACondition: IExpression);
begin
  FTableName := ATable;
  FAlias := AAlias;
  FType := AType;
  FCondition := ACondition;
end;

function TJoin.GetTableName: string;
begin
  Result := FTableName;
end;

function TJoin.GetAlias: string;
begin
  Result := FAlias;
end;

function TJoin.GetJoinType: TJoinType;
begin
  Result := FType;
end;

function TJoin.GetCondition: IExpression;
begin
  Result := FCondition;
end;

function TSpecification<T>.Clone: ISpecification<T>;
var
  NewSpec: TSpecification<T>;
begin
  NewSpec := TSpecification<T>.Create(FExpression);
  NewSpec.FIncludes := FIncludes;
  NewSpec.FSelectedColumns := FSelectedColumns;
  NewSpec.FOrderBy := FOrderBy;
  NewSpec.FJoins := FJoins;
  NewSpec.FGroupBy := FGroupBy;
  NewSpec.FHaving := FHaving;
  NewSpec.FSelectItems := FSelectItems;
  NewSpec.FSkip := FSkip;
  NewSpec.FTake := FTake;
  NewSpec.FIsPagingEnabled := FIsPagingEnabled;
  NewSpec.FIsTracking := FIsTracking;
  NewSpec.FIgnoreQueryFilters := FIgnoreQueryFilters;
  NewSpec.FOnlyDeleted := FOnlyDeleted;
  NewSpec.FLockMode := FLockMode;
  Result := NewSpec;
end;

function TSpecification<T>.AndSpec(const Other: ISpecification<T>): ISpecification<T>;
var
  NewSpec: TSpecification<T>;
  NewExpr: IExpression;
begin
  if (FExpression = nil) and (Other = nil) then
    Exit(Self);
  if FExpression = nil then
    Exit(Other);
  if (Other = nil) or (Other.GetExpression = nil) then
    Exit(Self);

  NewExpr := TLogicalExpression.Create(FExpression, Other.GetExpression, loAnd);
  NewSpec := TSpecification<T>.Create(NewExpr);
  Result := NewSpec;
end;

function TSpecification<T>.OrSpec(const Other: ISpecification<T>): ISpecification<T>;
var
  NewSpec: TSpecification<T>;
  NewExpr: IExpression;
begin
  if (FExpression = nil) and (Other = nil) then
    Exit(Self);
  if FExpression = nil then
    Exit(Other);
  if (Other = nil) or (Other.GetExpression = nil) then
    Exit(Self);

  NewExpr := TLogicalExpression.Create(FExpression, Other.GetExpression, loOr);
  NewSpec := TSpecification<T>.Create(NewExpr);
  Result := NewSpec;
end;

function TSpecification<T>.NotSpec: ISpecification<T>;
var
  NewSpec: TSpecification<T>;
  NewExpr: IExpression;
begin
  if FExpression = nil then
    Exit(Self);

  NewExpr := TUnaryExpression.Create(FExpression);
  NewSpec := TSpecification<T>.Create(NewExpr);
  Result := NewSpec;
end;

function TSpecification<T>.IsSatisfiedBy(const AEntity: T): Boolean;
begin
  if FExpression = nil then
    Exit(True);
  Result := TExpressionEvaluator.Evaluate(FExpression, AEntity);
end;

end.

