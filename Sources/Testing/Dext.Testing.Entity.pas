{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
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
{  Author:  Cesar Romero & Antigravity                                      }
{  Created: 2026-08-10                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Testing.Entity;

// Unit-test helpers for code that queries a Dext Entity context.
//
// Like Dext.Testing.WebApplicationFactory, this unit is not part of the
// Dext.Testing.Core package (it depends on Dext.Entity): add
// $(DEXT)\Sources\Testing to the project search path.

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.Generics.Defaults,
  System.Generics.Collections,
  Dext.Core.Reflection,
  Dext.Collections,
  Dext.Specifications.Interfaces,
  Dext.Core.SmartTypes,
  Dext.Interception,
  Dext.Entity.Core,
  Dext.Entity.Query,
  Dext.Mocks,
  Dext.Mocks.Matching;

type
  /// <summary>
  ///   Builds a Mock&lt;IDbSet&lt;T&gt;&gt; whose queries are answered from an
  ///   in-memory list. The real expression or specification is evaluated
  ///   against the list, so the test exercises the business rule and not a
  ///   copy of it. What is not exercised is the translation to SQL: keep an
  ///   integration test (for example SQLite in memory) for that.
  /// </summary>
  /// <remarks>
  ///   Answered: Where (IExpression and BooleanExpression), Query, QueryAll,
  ///   AsNoTracking, ToList, FirstOrDefault, Any, Count and Add (which appends
  ///   to the list). A specification applies its criterion, ordering, Skip and
  ///   Take. The TFluentQuery returned is in memory: Where, Skip, Take, Count
  ///   and First work on it, but OrderBy chained on it is ignored. Every other
  ///   member keeps the loose-mock default and can be set up as usual.
  /// </remarks>
  MockDbSet<T: class> = record
  private type
    // Shared by the setups; held by an interface so it lives as long as they do.
    TData = class(TInterfacedObject)
    private
      FItems: IList<T>;
    public
      constructor Create(const AItems: IList<T>);
      function Filter(const Expression: IExpression): IList<T>;
      function Apply(const Spec: ISpecification): IList<T>;
      function AsQuery(const Items: IList<T>): TFluentQuery<T>;
      property Items: IList<T> read FItems;
    end;
  public
    /// <summary>The entities become owned by the mock, as they would be owned by the context.</summary>
    class function From(const Entities: array of T): Mock<IDbSet<T>>; overload; static;
    /// <summary>Uses the given list; ownership stays with the list.</summary>
    class function From(const Entities: IList<T>): Mock<IDbSet<T>>; overload; static;
  end;

  /// <summary>Support routines for MockDbSet&lt;T&gt;; not meant for direct use.</summary>
  TMockDbSetSupport = class
  public
    class function UnwrapSmartValue(const Value: TValue): TValue; static;
    class function ReadMember(const Instance: TObject; const Name: string): TValue; static;
    class function CompareValues(const A, B: TValue): Integer; static;
  end;

implementation

{ TMockDbSetSupport }

class function TMockDbSetSupport.UnwrapSmartValue(const Value: TValue): TValue;
var
  RecType: TRttiRecordType;
  ValueField: TRttiField;
begin
  Result := Value;
  if (Value.Kind = tkRecord) and (Value.TypeInfo <> nil) and
    string(Value.TypeInfo.Name).StartsWith('Prop<') then
  begin
    RecType := TReflection.Context.GetType(Value.TypeInfo).AsRecord;
    ValueField := RecType.GetField('FValue');
    if ValueField <> nil then
      Result := ValueField.GetValue(Value.GetReferenceToRawData);
  end;
end;

class function TMockDbSetSupport.ReadMember(const Instance: TObject; const Name: string): TValue;
var
  RttiType: TRttiType;
  Prop: TRttiProperty;
begin
  RttiType := TReflection.Context.GetType(Instance.ClassType);
  Prop := RttiType.GetProperty(Name);
  if Prop = nil then
    raise ENotSupportedException.CreateFmt(
      'MockDbSet: %s has no property "%s" to order by', [Instance.ClassName, Name]);
  Result := UnwrapSmartValue(Prop.GetValue(Instance));
end;

class function TMockDbSetSupport.CompareValues(const A, B: TValue): Integer;
begin
  if A.IsEmpty or B.IsEmpty then
    Exit(Ord(not A.IsEmpty) - Ord(not B.IsEmpty));
  case A.Kind of
    tkInteger, tkInt64, tkEnumeration, tkChar, tkWChar:
      if A.AsOrdinal < B.AsOrdinal then Result := -1
      else if A.AsOrdinal > B.AsOrdinal then Result := 1
      else Result := 0;
    tkFloat:
      if A.AsExtended < B.AsExtended then Result := -1
      else if A.AsExtended > B.AsExtended then Result := 1
      else Result := 0;
  else
    Result := CompareStr(A.ToString, B.ToString);
  end;
end;

{ MockDbSet<T>.TData }

constructor MockDbSet<T>.TData.Create(const AItems: IList<T>);
begin
  inherited Create;
  FItems := AItems;
end;

function MockDbSet<T>.TData.Filter(const Expression: IExpression): IList<T>;
var
  I: Integer;
begin
  if Expression <> nil then
    Exit(FItems.Where(Expression));
  Result := TCollections.CreateList<T>(False);
  for I := 0 to FItems.Count - 1 do
    Result.Add(FItems[I]);
end;

function MockDbSet<T>.TData.Apply(const Spec: ISpecification): IList<T>;
var
  Filtered: IList<T>;
  Arr: TArray<T>;
  Orders: TArray<IOrderBy>;
  I, First, Last: Integer;
begin
  if Spec = nil then
    Exit(Filter(nil));
  Filtered := Filter(Spec.GetExpression);
  SetLength(Arr, Filtered.Count);
  for I := 0 to Filtered.Count - 1 do
    Arr[I] := Filtered[I];

  Orders := Spec.GetOrderBy;
  if Length(Orders) > 0 then
    TArray.Sort<T>(Arr, TComparer<T>.Construct(
      function(const Left, Right: T): Integer
      var
        Order: IOrderBy;
      begin
        Result := 0;
        for Order in Orders do
        begin
          Result := TMockDbSetSupport.CompareValues(
            TMockDbSetSupport.ReadMember(TObject(PPointer(@Left)^), Order.GetPropertyName),
            TMockDbSetSupport.ReadMember(TObject(PPointer(@Right)^), Order.GetPropertyName));
          if not Order.GetAscending then
            Result := -Result;
          if Result <> 0 then
            Exit;
        end;
      end));

  First := 0;
  Last := High(Arr);
  if Spec.GetSkip > 0 then
    First := Spec.GetSkip;
  if Spec.GetTake > 0 then
    if First + Spec.GetTake - 1 < Last then
      Last := First + Spec.GetTake - 1;

  Result := TCollections.CreateList<T>(False);
  for I := First to Last do
    Result.Add(Arr[I]);
end;

function MockDbSet<T>.TData.AsQuery(const Items: IList<T>): TFluentQuery<T>;
var
  Captured: IList<T>;
begin
  Captured := Items;
  Result := TFluentQuery<T>.Create(
    function: TQueryIterator<T>
    begin
      Result := TSpecificationQueryIterator<T>.Create(
        function: IList<T>
        var
          Copy: IList<T>;
          I: Integer;
        begin
          // A fresh list per enumeration: ToList hands this list to the caller.
          Copy := TCollections.CreateList<T>(False);
          for I := 0 to Captured.Count - 1 do
            Copy.Add(Captured[I]);
          Result := Copy;
        end);
    end);
end;

{ MockDbSet<T> }

class function MockDbSet<T>.From(const Entities: array of T): Mock<IDbSet<T>>;
var
  Items: IList<T>;
  Entity: T;
begin
  Items := TCollections.CreateList<T>(True);
  for Entity in Entities do
    Items.Add(Entity);
  Result := From(Items);
end;

class function MockDbSet<T>.From(const Entities: IList<T>): Mock<IDbSet<T>>;
var
  Data: TData;
  Owner: IInterface;
  Self_: Pointer;
begin
  Data := MockDbSet<T>.TData.Create(Entities);
  // Every setup below tests Owner, so the closures keep the data alive.
  Owner := Data;
  Result := Mock<IDbSet<T>>.Create;
  // Weak reference: capturing the instance itself would keep the mock alive forever.
  Self_ := Pointer(Result.Instance);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<TFluentQuery<T>>(
        Data.AsQuery(Data.Filter(Inv.Arguments[0].AsType<IExpression>)));
    end).When.Where(Arg.Any<IExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    var
      Condition: BooleanExpression;
      Expression: IExpression;
    begin
      if Owner = nil then Exit;
      Condition := Inv.Arguments[0].AsType<BooleanExpression>;
      Expression := Condition;
      Inv.Result := TValue.From<TFluentQuery<T>>(
        Data.AsQuery(Data.Filter(Expression)));
    end).When.Where(Arg.Any<BooleanExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<TFluentQuery<T>>(
        Data.AsQuery(Data.Filter(Inv.Arguments[0].AsType<IExpression>)));
    end).When.Query(Arg.Any<IExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<TFluentQuery<T>>(
        Data.AsQuery(Data.Apply(Inv.Arguments[0].AsType<ISpecification<T>>)));
    end).When.Query(Arg.Any<ISpecification<T>>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<TFluentQuery<T>>(Data.AsQuery(Data.Filter(nil)));
    end).When.QueryAll;

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<TFluentQuery<T>>(Data.AsQuery(Data.Filter(nil)));
    end).When.AsNoTracking;

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<IList<T>>(Data.Filter(nil));
    end).When.ToList;

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<IList<T>>(
        Data.Filter(Inv.Arguments[0].AsType<IExpression>));
    end).When.ToList(Arg.Any<IExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<IList<T>>(
        Data.Apply(Inv.Arguments[0].AsType<ISpecification<T>>));
    end).When.ToList(Arg.Any<ISpecification<T>>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    var
      Found: IList<T>;
    begin
      if Owner = nil then Exit;
      Found := Data.Filter(Inv.Arguments[0].AsType<IExpression>);
      if Found.Count > 0 then
        Inv.Result := TValue.From<T>(Found[0])
      else
        Inv.Result := TValue.From<T>(Default(T));
    end).When.FirstOrDefault(Arg.Any<IExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    var
      Found: IList<T>;
    begin
      if Owner = nil then Exit;
      Found := Data.Apply(Inv.Arguments[0].AsType<ISpecification<T>>);
      if Found.Count > 0 then
        Inv.Result := TValue.From<T>(Found[0])
      else
        Inv.Result := TValue.From<T>(Default(T));
    end).When.FirstOrDefault(Arg.Any<ISpecification<T>>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<Boolean>(
        Data.Filter(Inv.Arguments[0].AsType<IExpression>).Count > 0);
    end).When.Any(Arg.Any<IExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<Boolean>(
        Data.Apply(Inv.Arguments[0].AsType<ISpecification<T>>).Count > 0);
    end).When.Any(Arg.Any<ISpecification<T>>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<Integer>(
        Data.Filter(Inv.Arguments[0].AsType<IExpression>).Count);
    end).When.Count(Arg.Any<IExpression>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Inv.Result := TValue.From<Integer>(
        Data.Apply(Inv.Arguments[0].AsType<ISpecification<T>>).Count);
    end).When.Count(Arg.Any<ISpecification<T>>);

  Result.Setup.Executes(
    procedure(Inv: IInvocation)
    begin
      if Owner = nil then Exit;
      Data.Items.Add(Inv.Arguments[0].AsType<T>);
      Inv.Result := TValue.From<IDbSet<T>>(IDbSet<T>(Self_));
    end).When.Add(Arg.Any<T>);
end;

end.
