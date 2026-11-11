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
unit Dext.Specifications.Types;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.Specifications.Interfaces,
  Dext.Specifications.OrderBy;

type
  TAbstractExpression = class(TInterfacedObject, IExpression)
  public
    destructor Destroy; override;
    function ToString: string; override;
  protected
    procedure BeforePool; virtual;
  end;

  /// <summary>
  ///   Represents a binary operator (Left Op Right).
  ///   e.g., Age > 18, Name = 'John'
  /// </summary>
  TBinaryOperator = (boEqual, boNotEqual, boGreaterThan, boGreaterThanOrEqual, 
    boLessThan, boLessThanOrEqual, boLike, boNotLike, boIn, boNotIn,
    boBitwiseAnd, boBitwiseOr, boBitwiseXor,
    // StartsWith / EndsWith / Contains: the value is matched literally (a %
    // or _ in it is not a wildcard). SQL renders them as LIKE with ESCAPE.
    boStartsWith, boEndsWith, boContains);

  /// <summary>
  ///   Represents an arithmetic operator (+, -, *, /).
  /// </summary>
  TArithmeticOperator = (aoAdd, aoSubtract, aoMultiply, aoDivide, aoModulus, aoIntDivide);

  TBinaryExpression = class(TAbstractExpression)
  private
    FLeft: IExpression;
    FRight: IExpression;
    FOperator: TBinaryOperator;
  public
    constructor Create(const ALeft, ARight: IExpression; AOperator: TBinaryOperator); overload;
    constructor Create(const APropertyName: string; AOperator: TBinaryOperator; const AValue: TValue); overload;
    constructor Create(const APropertyName: string; AOperator: TBinaryOperator; const AValue: string); overload;
    constructor Create(const APropertyName: string; AOperator: TBinaryOperator; const AValue: Integer); overload;
    constructor Create(const APropertyName: string; AOperator: TBinaryOperator; const AValue: Boolean); overload;
    destructor Destroy; override;
    property Left: IExpression read FLeft;
    property Right: IExpression read FRight;
    property BinaryOperator: TBinaryOperator read FOperator;
    function ToString: string; override;
  end;

  /// <summary>
  ///   Represents an arithmetic expression (Left mathOp Right).
  /// </summary>
  TArithmeticExpression = class(TAbstractExpression)
  private
    FLeft: IExpression;
    FRight: IExpression;
    FOperator: TArithmeticOperator;
  public
    constructor Create(const ALeft, ARight: IExpression; AOperator: TArithmeticOperator);
    destructor Destroy; override;
    property Left: IExpression read FLeft;
    property Right: IExpression read FRight;
    property ArithmeticOperator: TArithmeticOperator read FOperator;
    function ToString: string; override;
  end;

  /// <summary>
  ///   Represents a reference to a property/column in an expression.
  /// </summary>
  TPropertyExpression = class(TAbstractExpression)
  private
    FPropertyName: string;
    FOwner: string;
  public
    constructor Create(const APropertyName: string); overload;
    /// <param name="AOwner">The table of the entity that declares the property
    ///   (a prototype property knows it). A query with joins uses it to qualify
    ///   the column with the right table or alias.</param>
    constructor Create(const APropertyName, AOwner: string); overload;
    destructor Destroy; override;
    property PropertyName: string read FPropertyName;
    property Owner: string read FOwner;
    function ToString: string; override;
  end;

  /// <summary>
  ///   The aggregate functions available in a projection or in Having.
  /// </summary>
  TAggregateKind = (akCount, akCountDistinct, akSum, akAvg, akMin, akMax);

  /// <summary>
  ///   An aggregate over a column (COUNT, SUM, AVG, MIN, MAX). With an empty
  ///   property name it is COUNT(*).
  /// </summary>
  TAggregateExpression = class(TAbstractExpression)
  private
    FKind: TAggregateKind;
    FPropertyName: string;
    FOwner: string;
  public
    constructor Create(AKind: TAggregateKind; const APropertyName: string;
      const AOwner: string = '');
    property Kind: TAggregateKind read FKind;
    property PropertyName: string read FPropertyName;
    property Owner: string read FOwner;
    function ToString: string; override;
  end;

  /// <summary>
  ///   Represents a reference to a property inside a JSON column.
  /// </summary>
  TJsonPropertyExpression = class(TAbstractExpression)
  private
    FPropertyName: string;
    FJsonPath: string;
  public
    constructor Create(const APropertyName, AJsonPath: string);
    destructor Destroy; override;
    property PropertyName: string read FPropertyName;
    property JsonPath: string read FJsonPath;
    function ToString: string; override;
  end;

  /// <summary>
  ///   Represents a literal value in an expression.
  /// </summary>
  TLiteralExpression = class(TAbstractExpression)
  private
    FValue: TValue;
  public
    constructor Create(const AValue: TValue);
    destructor Destroy; override;
    property Value: TValue read FValue;
    function ToString: string; override;
  protected
    procedure BeforePool; override;
  end;

  /// <summary>
  ///   Represents a logical operation (AND, OR).
  /// </summary>
  TLogicalOperator = (loAnd, loOr);

  TLogicalExpression = class(TAbstractExpression)
  private
    FLeft: IExpression;
    FRight: IExpression;
    FOperator: TLogicalOperator;
  public
    constructor Create(const ALeft, ARight: IExpression; AOperator: TLogicalOperator);
    destructor Destroy; override;
    property Left: IExpression read FLeft;
    property Right: IExpression read FRight;
    property LogicalOperator: TLogicalOperator read FOperator;
    function ToString: string; override;
  end;

  /// <summary>
  ///   Represents a unary operation (NOT, IsNull, IsNotNull).
  /// </summary>
  TUnaryOperator = (uoNot, uoIsNull, uoIsNotNull);

  TUnaryExpression = class(TAbstractExpression)
  private
    FExpression: IExpression; // For NOT
    FPropertyName: string;  // For IsNull/IsNotNull
    FOperator: TUnaryOperator;
  public
    constructor Create(const AExpression: IExpression); overload; // For NOT
    constructor Create(const APropertyName: string; AOperator: TUnaryOperator); overload; // For IsNull
    constructor Create(const AExpression: IExpression; AOperator: TUnaryOperator); overload; // For IsNull on complex expressions
    
    property Expression: IExpression read FExpression;
    property PropertyName: string read FPropertyName;
    property UnaryOperator: TUnaryOperator read FOperator;
    function ToString: string; override;
  end;

  /// <summary>
  ///   Represents a constant value (True/False) for always matching/not matching.
  /// </summary>
  TConstantExpression = class(TAbstractExpression)
  private
    FValue: Boolean;
  public
    constructor Create(AValue: Boolean);
    property Value: Boolean read FValue;
    function ToString: string; override;
  end;
  /// <summary>
  ///   Represents an intermediate expression in the expression tree.
  ///   Has implicit conversion to IExpression.
  /// </summary>
  TFluentExpression = record
  private
    FExpression: IExpression;
  public
    class function From(const AExpression: IExpression): TFluentExpression; static;
    class operator Implicit(const Value: IExpression): TFluentExpression;
    class operator Implicit(const Value: TFluentExpression): IExpression;
    
    // Logical Operators (AND, OR, NOT)
    class operator LogicalAnd(const Left, Right: TFluentExpression): TFluentExpression;
    class operator LogicalAnd(const Left: TFluentExpression; const Right: IExpression): TFluentExpression;
    class operator LogicalAnd(const Left: IExpression; const Right: TFluentExpression): TFluentExpression;
    
    class operator LogicalOr(const Left, Right: TFluentExpression): TFluentExpression;
    class operator LogicalOr(const Left: TFluentExpression; const Right: IExpression): TFluentExpression;
    class operator LogicalOr(const Left: IExpression; const Right: TFluentExpression): TFluentExpression;
    
    class operator LogicalNot(const Value: TFluentExpression): TFluentExpression;
    
    // Explicit comparison with Boolean for "and (Prop = True)" style
    class operator LogicalAnd(const Left: TFluentExpression; const Right: Boolean): TFluentExpression;
    class operator LogicalAnd(const Left: Boolean; const Right: TFluentExpression): TFluentExpression;

    property Expression: IExpression read FExpression;
  end;

  /// <summary>
  ///   Helper record to build expressions fluently.
  ///   Usage: PropExpression('Age') > 18
  /// </summary>
  TPropExpression = record
  private
    FName: string;
    FJsonPath: string;
    function GetLeftExp: IExpression;
  public
    constructor Create(const AName: string; const AJsonPath: string = '');
    // Comparison Operators
    class operator Equal(const Left: TPropExpression; const Right: TValue): TFluentExpression;
    class operator NotEqual(const Left: TPropExpression; const Right: TValue): TFluentExpression;
    class operator GreaterThan(const Left: TPropExpression; const Right: TValue): TFluentExpression;
    class operator GreaterThanOrEqual(const Left: TPropExpression; const Right: TValue): TFluentExpression;
    class operator LessThan(const Left: TPropExpression; const Right: TValue): TFluentExpression;
    class operator LessThanOrEqual(const Left: TPropExpression; const Right: TValue): TFluentExpression;
    
    class operator Implicit(const Value: TPropExpression): string;
    class operator Implicit(const Value: string): TPropExpression;

    // JSON Support
    function Json(const APath: string): TPropExpression;

    // Special Methods (Like, In, etc)
    function Like(const Pattern: string): TFluentExpression;
    function NotLike(const Pattern: string): TFluentExpression;
    function StartsWith(const Value: string): TFluentExpression;
    function EndsWith(const Value: string): TFluentExpression;
    function Contains(const Value: string): TFluentExpression;
    
    function &In(const Values: TArray<string>): TFluentExpression; overload;
    function &In(const Values: TArray<Integer>): TFluentExpression; overload;
    function &In(const Values: TArray<Variant>): TFluentExpression; overload;
    function NotIn(const Values: TArray<string>): TFluentExpression; overload;
    function NotIn(const Values: TArray<Integer>): TFluentExpression; overload;
    
    function IsNull: TFluentExpression;
    function IsNotNull: TFluentExpression;
    
    // Between as a method (not operator)
    function Between(const Lower, Upper: Variant): TFluentExpression;
    
    // OrderBy support
    function Asc: IOrderBy;
    function Desc: IOrderBy;
    property Name: string read FName;
    property JsonPath: string read FJsonPath;
  end;

  function Prop(const AName: string): TPropExpression;

  /// <summary>
  ///   Evaluates a SQL LIKE pattern in memory: % matches any sequence, _ any
  ///   single character, everything else matches itself. No escape character.
  /// </summary>
  function LikeMatches(const AValue, APattern: string; AIgnoreCase: Boolean): Boolean;

implementation

{ TAbstractExpression }

destructor TAbstractExpression.Destroy;
begin
  inherited;
end;

procedure TAbstractExpression.BeforePool;
begin
  // Default: nothing
end;

function TAbstractExpression.ToString: string;
begin
  Result := ClassName;
end;

{ TBinaryExpression }

constructor TBinaryExpression.Create(const ALeft, ARight: IExpression; AOperator: TBinaryOperator);
begin
  inherited Create;
  FLeft := ALeft;
  FRight := ARight;
  FOperator := AOperator;
end;

constructor TBinaryExpression.Create(const APropertyName: string;
  AOperator: TBinaryOperator; const AValue: TValue);
begin
  inherited Create;
  FLeft := TPropertyExpression.Create(APropertyName);
  FRight := TLiteralExpression.Create(AValue);
  FOperator := AOperator;
end;

constructor TBinaryExpression.Create(const APropertyName: string;
  AOperator: TBinaryOperator; const AValue: string);
begin
  inherited Create;
  FLeft := TPropertyExpression.Create(APropertyName);
  FRight := TLiteralExpression.Create(TValue.From<string>(AValue));
  FOperator := AOperator;
end;

constructor TBinaryExpression.Create(const APropertyName: string;
  AOperator: TBinaryOperator; const AValue: Integer);
begin
  inherited Create;
  FLeft := TPropertyExpression.Create(APropertyName);
  FRight := TLiteralExpression.Create(AValue); // Implicit conversion
  FOperator := AOperator;
end;

constructor TBinaryExpression.Create(const APropertyName: string;
  AOperator: TBinaryOperator; const AValue: Boolean);
begin
  inherited Create;
  FLeft := TPropertyExpression.Create(APropertyName);
  FRight := TLiteralExpression.Create(AValue); // Implicit conversion
  FOperator := AOperator;
end;

destructor TBinaryExpression.Destroy;
begin
  FLeft := nil;
  FRight := nil;
  inherited;
end;

function TBinaryExpression.ToString: string;
var
  Lit: TLiteralExpression;
  ArrayLen: Integer;
  I: Integer;
  ArraySig: string;
begin
  // Special handling for IN/NOT IN operators to ensure unique cache signatures
  // The array length MUST be part of the signature to avoid cache collisions
  if (FOperator = boIn) or (FOperator = boNotIn) then
  begin
    if FRight is TLiteralExpression then
    begin
      Lit := TLiteralExpression(FRight);
      // Force array length extraction - works even when TValue.IsArray returns false
      try
        ArrayLen := Lit.Value.GetArrayLength;
        ArraySig := '[#' + IntToStr(ArrayLen) + ':';
        for I := 0 to ArrayLen - 1 do
        begin
          if I > 0 then ArraySig := ArraySig + ',';
          ArraySig := ArraySig + Lit.Value.GetArrayElement(I).ToString;
        end;
        ArraySig := ArraySig + ']';
        Result := Format('(%s %d %s)', [FLeft.ToString, Ord(FOperator), ArraySig]);
        Exit;
      except
        // Fall through to default behavior if array extraction fails
      end;
    end;
  end;
  
  Result := Format('(%s %d %s)', [FLeft.ToString, Ord(FOperator), FRight.ToString]);
end;

constructor TArithmeticExpression.Create(const ALeft, ARight: IExpression; AOperator: TArithmeticOperator);
begin
  inherited Create;
  FLeft := ALeft;
  FRight := ARight;
  FOperator := AOperator;
end;

destructor TArithmeticExpression.Destroy;
begin
  FLeft := nil;
  FRight := nil;
  inherited;
end;

function TArithmeticExpression.ToString: string;
begin
  Result := Format('(%s %d %s)', [FLeft.ToString, Ord(FOperator), FRight.ToString]);
end;

{ TPropertyExpression }

constructor TPropertyExpression.Create(const APropertyName: string);
begin
  inherited Create;
  FPropertyName := APropertyName;
end;

constructor TPropertyExpression.Create(const APropertyName, AOwner: string);
begin
  inherited Create;
  FPropertyName := APropertyName;
  FOwner := AOwner;
end;

destructor TPropertyExpression.Destroy;
begin
  FPropertyName := '';
  FOwner := '';
  inherited;
end;

function TPropertyExpression.ToString: string;
begin
  // The owner is part of the text: two tables can have a column with the
  // same name and the SQL cache signature must tell them apart.
  if FOwner <> '' then
    Result := FOwner + '.' + FPropertyName
  else
    Result := FPropertyName;
end;

{ TAggregateExpression }

constructor TAggregateExpression.Create(AKind: TAggregateKind;
  const APropertyName, AOwner: string);
begin
  inherited Create;
  FKind := AKind;
  FPropertyName := APropertyName;
  FOwner := AOwner;
end;

function TAggregateExpression.ToString: string;
const
  Names: array[TAggregateKind] of string =
    ('COUNT', 'COUNT_DISTINCT', 'SUM', 'AVG', 'MIN', 'MAX');
begin
  if FOwner <> '' then
    Result := Names[FKind] + '(' + FOwner + '.' + FPropertyName + ')'
  else
    Result := Names[FKind] + '(' + FPropertyName + ')';
end;

{ TJsonPropertyExpression }

constructor TJsonPropertyExpression.Create(const APropertyName, AJsonPath: string);
begin
  inherited Create;
  FPropertyName := APropertyName;
  FJsonPath := AJsonPath;
end;

destructor TJsonPropertyExpression.Destroy;
begin
  FPropertyName := '';
  FJsonPath := '';
  inherited;
end;

function TJsonPropertyExpression.ToString: string;
begin
  Result := FPropertyName + '->' + FJsonPath;
end;

{ TLiteralExpression }

constructor TLiteralExpression.Create(const AValue: TValue);
begin
  inherited Create;
  FValue := AValue;
end;

destructor TLiteralExpression.Destroy;
begin
  FValue := TValue.Empty;
  inherited;
end;

procedure TLiteralExpression.BeforePool;
begin
  FValue := TValue.Empty;
end;

function TLiteralExpression.ToString: string;
var
  I: Integer;
  Len: Integer;
begin
  // Check for arrays using Kind instead of IsArray for Delphi 10.4 compatibility
  // TValue.IsArray returns False for TArray<Variant> in older Delphi versions
  if (FValue.Kind = tkDynArray) or (FValue.Kind = tkArray) or FValue.IsArray then
  begin
    Len := FValue.GetArrayLength;
    // Include array length prefix to ensure unique cache signatures for IN queries
    // This prevents cache collisions when same query structure has different param counts
    // e.g., IN [1] -> "[#1:1]" vs IN [1,2] -> "[#2:1,2]"
    Result := '[#' + IntToStr(Len) + ':';
    for I := 0 to Len - 1 do
    begin
      if I > 0 then Result := Result + ',';
      Result := Result + FValue.GetArrayElement(I).ToString;
    end;
    Result := Result + ']';
  end
  else
    Result := FValue.ToString;
end;

{ TLogicalExpression }

constructor TLogicalExpression.Create(const ALeft, ARight: IExpression;
  AOperator: TLogicalOperator);
begin
  inherited Create;
  FLeft := ALeft;
  FRight := ARight;
  FOperator := AOperator;
end;

destructor TLogicalExpression.Destroy;
begin
  FLeft := nil;
  FRight := nil;
  inherited;
end;

function TLogicalExpression.ToString: string;
var
  OpStr: string;
begin
  if FOperator = loAnd then OpStr := 'AND' else OpStr := 'OR';
  Result := Format('(%s %s %s)', [FLeft.ToString, OpStr, FRight.ToString]);
end;

{ TUnaryExpression }

constructor TUnaryExpression.Create(const AExpression: IExpression);
begin
  inherited Create;
  FOperator := uoNot;
  FExpression := AExpression;
end;

constructor TUnaryExpression.Create(const APropertyName: string;
  AOperator: TUnaryOperator);
begin
  inherited Create;
  FPropertyName := APropertyName;
  FOperator := AOperator;
end;

constructor TUnaryExpression.Create(const AExpression: IExpression;
  AOperator: TUnaryOperator);
begin
  inherited Create;
  FExpression := AExpression;
  FOperator := AOperator;
end;

function TUnaryExpression.ToString: string;
begin
  if FOperator = uoNot then
    Result := Format('(NOT %s)', [FExpression.ToString])
  else if FOperator = uoIsNull then
  begin
    if FExpression <> nil then
      Result := Format('(%s IS NULL)', [FExpression.ToString])
    else
      Result := Format('(%s IS NULL)', [FPropertyName]);
  end
  else
  begin
    if FExpression <> nil then
      Result := Format('(%s IS NOT NULL)', [FExpression.ToString])
    else
      Result := Format('(%s IS NOT NULL)', [FPropertyName]);
  end;
end;

{ TConstantExpression }

constructor TConstantExpression.Create(AValue: Boolean);
begin
  inherited Create;
  FValue := AValue;
end;

function TConstantExpression.ToString: string;
begin
  Result := BoolToStr(FValue, True);
end;

{ TFluentExpression }

class function TFluentExpression.From(const AExpression: IExpression): TFluentExpression;
begin
  Result.FExpression := AExpression;
end;

class operator TFluentExpression.Implicit(const Value: IExpression): TFluentExpression;
begin
  Result.FExpression := Value;
end;

class operator TFluentExpression.Implicit(const Value: TFluentExpression): IExpression;
begin
  Result := Value.FExpression;
end;

class operator TFluentExpression.LogicalAnd(const Left, Right: TFluentExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left.FExpression, Right.FExpression, loAnd);
end;

class operator TFluentExpression.LogicalAnd(const Left: TFluentExpression; const Right: IExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left.FExpression, Right, loAnd);
end;

class operator TFluentExpression.LogicalAnd(const Left: IExpression; const Right: TFluentExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left, Right.FExpression, loAnd);
end;

class operator TFluentExpression.LogicalOr(const Left, Right: TFluentExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left.FExpression, Right.FExpression, loOr);
end;

class operator TFluentExpression.LogicalOr(const Left: TFluentExpression; const Right: IExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left.FExpression, Right, loOr);
end;

class operator TFluentExpression.LogicalOr(const Left: IExpression; const Right: TFluentExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left, Right.FExpression, loOr);
end;

class operator TFluentExpression.LogicalNot(const Value: TFluentExpression): TFluentExpression;
begin
  Result.FExpression := TUnaryExpression.Create(Value.FExpression);
end;

class operator TFluentExpression.LogicalAnd(const Left: TFluentExpression; const Right: Boolean): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(Left.FExpression, TConstantExpression.Create(Right), loAnd);
end;

class operator TFluentExpression.LogicalAnd(const Left: Boolean; const Right: TFluentExpression): TFluentExpression;
begin
  Result.FExpression := TLogicalExpression.Create(TConstantExpression.Create(Left), Right.FExpression, loAnd);
end;

function Prop(const AName: string): TPropExpression;
begin
  Result := TPropExpression.Create(AName);
end;

function LikeMatches(const AValue, APattern: string; AIgnoreCase: Boolean): Boolean;
var
  S, P: string;
  SI, PI, StarP, StarS: Integer;
begin
  if AIgnoreCase then
  begin
    S := AValue.ToLower;
    P := APattern.ToLower;
  end
  else
  begin
    S := AValue;
    P := APattern;
  end;

  // Greedy match with backtracking to the last %.
  SI := 1;
  PI := 1;
  StarP := 0;
  StarS := 0;
  while SI <= Length(S) do
  begin
    if (PI <= Length(P)) and (P[PI] <> '%') and ((P[PI] = '_') or (P[PI] = S[SI])) then
    begin
      Inc(SI);
      Inc(PI);
    end
    else if (PI <= Length(P)) and (P[PI] = '%') then
    begin
      StarP := PI;
      StarS := SI;
      Inc(PI);
    end
    else if StarP > 0 then
    begin
      PI := StarP + 1;
      Inc(StarS);
      SI := StarS;
    end
    else
      Exit(False);
  end;
  while (PI <= Length(P)) and (P[PI] = '%') do
    Inc(PI);
  Result := PI > Length(P);
end;

{ TPropExpression }

constructor TPropExpression.Create(const AName: string; const AJsonPath: string);
begin
  FName := AName;
  FJsonPath := AJsonPath;
end;

function TPropExpression.Json(const APath: string): TPropExpression;
var
  NewPath: string;
begin
  if FJsonPath <> '' then
    NewPath := FJsonPath + '.' + APath
  else
    NewPath := APath;
    
  Result := TPropExpression.Create(FName, NewPath);
end;

function TPropExpression.GetLeftExp: IExpression;
begin
  if FJsonPath <> '' then
    Result := TJsonPropertyExpression.Create(FName, FJsonPath)
  else
    Result := TPropertyExpression.Create(FName);
end;

class operator TPropExpression.Equal(const Left: TPropExpression; const Right: TValue): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(Left.GetLeftExp, TLiteralExpression.Create(Right), boEqual);
end;

class operator TPropExpression.NotEqual(const Left: TPropExpression; const Right: TValue): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(Left.GetLeftExp, TLiteralExpression.Create(Right), boNotEqual);
end;

class operator TPropExpression.GreaterThan(const Left: TPropExpression; const Right: TValue): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(Left.GetLeftExp, TLiteralExpression.Create(Right), boGreaterThan);
end;

class operator TPropExpression.GreaterThanOrEqual(const Left: TPropExpression; const Right: TValue): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(Left.GetLeftExp, TLiteralExpression.Create(Right), boGreaterThanOrEqual);
end;

class operator TPropExpression.LessThan(const Left: TPropExpression; const Right: TValue): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(Left.GetLeftExp, TLiteralExpression.Create(Right), boLessThan);
end;

class operator TPropExpression.LessThanOrEqual(const Left: TPropExpression; const Right: TValue): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(Left.GetLeftExp, TLiteralExpression.Create(Right), boLessThanOrEqual);
end;

function TPropExpression.Like(const Pattern: string): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Pattern), boLike);
end;

function TPropExpression.NotLike(const Pattern: string): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Pattern), boNotLike);
end;

function TPropExpression.StartsWith(const Value: string): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Value), boStartsWith);
end;

function TPropExpression.EndsWith(const Value: string): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Value), boEndsWith);
end;

function TPropExpression.Contains(const Value: string): TFluentExpression;
begin
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Value), boContains);
end;

function TPropExpression.&In(const Values: TArray<string>): TFluentExpression;
var
  Val: TValue;
begin
  Val := TValue.From<TArray<string>>(Values);
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Val), boIn);
end;

class operator TPropExpression.Implicit(const Value: TPropExpression): string;
begin
  Result := Value.Name;
end;

class operator TPropExpression.Implicit(const Value: string): TPropExpression;
begin
  Result := TPropExpression.Create(Value);
end;

function TPropExpression.&In(const Values: TArray<Integer>): TFluentExpression;
var
  Val: TValue;
begin
  Val := TValue.From<TArray<Integer>>(Values);
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Val), boIn);
end;

function TPropExpression.&In(const Values: TArray<Variant>): TFluentExpression;
var
  Val: TValue;
begin
  Val := TValue.From<TArray<Variant>>(Values);
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Val), boIn);
end;

function TPropExpression.NotIn(const Values: TArray<string>): TFluentExpression;
var
  Val: TValue;
begin
  Val := TValue.From<TArray<string>>(Values);
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Val), boNotIn);
end;

function TPropExpression.NotIn(const Values: TArray<Integer>): TFluentExpression;
var
  Val: TValue;
begin
  Val := TValue.From<TArray<Integer>>(Values);
  Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(Val), boNotIn);
end;

function TPropExpression.IsNull: TFluentExpression;
begin
  if FJsonPath <> '' then
    Result.FExpression := TUnaryExpression.Create(GetLeftExp, uoIsNull)
  else
    Result.FExpression := TUnaryExpression.Create(FName, uoIsNull);
end;

function TPropExpression.IsNotNull: TFluentExpression;
begin
  if FJsonPath <> '' then
     // Same for IsNotNull
     Result.FExpression := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(nil), boNotEqual)
  else
    Result.FExpression := TUnaryExpression.Create(FName, uoIsNotNull);
end;

function TPropExpression.Between(const Lower, Upper: Variant): TFluentExpression;
var
  LowerCrit, UpperCrit: IExpression;
begin
  // (Prop >= Lower) AND (Prop <= Upper)
  LowerCrit := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(TValue.FromVariant(Lower)), boGreaterThanOrEqual);
  UpperCrit := TBinaryExpression.Create(GetLeftExp, TLiteralExpression.Create(TValue.FromVariant(Upper)), boLessThanOrEqual);
  Result.FExpression := TLogicalExpression.Create(LowerCrit, UpperCrit, loAnd);
end;

function TPropExpression.Asc: IOrderBy;
begin
  Result := TOrderBy.Create(FName, True);
end;

function TPropExpression.Desc: IOrderBy;
begin
  Result := TOrderBy.Create(FName, False);
end;

end.


