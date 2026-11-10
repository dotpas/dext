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
unit Dext.Validation;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Core.Reflection,
  System.RegularExpressions,
  Dext.Core.SmartTypes,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Evaluator,
  Dext.Specifications.Types;

var
  PrototypeFactory: TFunc<PTypeInfo, TObject> = nil;

type
  /// <summary>
  ///   Validation result for a single field or the entire model.
  /// </summary>
  TValidationError = record
    FieldName: string;
    ErrorMessage: string;
  end;

  TValidationResult = class
  private
    FErrors: IList<TValidationError>;
    function GetIsValid: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure AddError(const AFieldName, AMessage: string);
    function GetErrors: TArray<TValidationError>;
    function ErrorMessage(const ADelimiter: string = sLineBreak): string;
    
    property IsValid: Boolean read GetIsValid;
    property Errors: TArray<TValidationError> read GetErrors;
  end;

  /// <summary>
  ///   Base class for validation attributes.
  /// </summary>
  ValidationAttribute = class abstract(TCustomAttribute)
  public
    function IsValid(const AValue: TValue): Boolean; virtual; abstract;
    function GetErrorMessage(const AFieldName: string): string; virtual; abstract;
  end;

  /// <summary>
  ///   Specifies that a field is required (not empty/zero).
  /// </summary>
  RequiredAttribute = class(ValidationAttribute)
  public
    function IsValid(const AValue: TValue): Boolean; override;
    function GetErrorMessage(const AFieldName: string): string; override;
  end;

  /// <summary>
  ///   Specifies string length constraints.
  /// </summary>
  StringLengthAttribute = class(ValidationAttribute)
  private
    FMinLength: Integer;
    FMaxLength: Integer;
  public
    constructor Create(AMinLength, AMaxLength: Integer);
    function IsValid(const AValue: TValue): Boolean; override;
    function GetErrorMessage(const AFieldName: string): string; override;
  end;

  /// <summary>
  ///   Validates that a string is a valid email address.
  /// </summary>
  EmailAddressAttribute = class(ValidationAttribute)
  public
    function IsValid(const AValue: TValue): Boolean; override;
    function GetErrorMessage(const AFieldName: string): string; override;
  end;

  /// <summary>
  ///   Specifies numeric range constraints.
  /// </summary>
  RangeAttribute = class(ValidationAttribute)
  private
    FMin: Double;
    FMax: Double;
  public
    constructor Create(AMin, AMax: Double); overload;
    constructor Create(AMin, AMax: Integer); overload;
    function IsValid(const AValue: TValue): Boolean; override;
    function GetErrorMessage(const AFieldName: string): string; override;
  end;

  TValidationPatterns = class
  private
    class var FPatterns: IDictionary<string, string>;
    class var FDefaultLocale: string;
    class constructor Create;
    class destructor Destroy;
  public
    class procedure Register(const AName, APattern: string; const ALocale: string = ''); static;
    class function Get(const AName: string; const ALocale: string = ''): string; static;
    class function Phone(const ALocale: string = ''): string; static;
    class function ZipCode(const ALocale: string = ''): string; static;
    class function Email: string; static;
    class property DefaultLocale: string read FDefaultLocale write FDefaultLocale;
  end;

  IValidator = interface
    ['{A9B8C7D6-E5F4-3C2B-1A09-8B7C6D5E4F3A}']
    function ValidateInstance(const AValue: TValue): TValidationResult;
  end;

  /// <summary>
  ///   Validates a record using RTTI and validation attributes.
  /// </summary>
  IValidator<T> = interface(IValidator)
    ['{E8F9A2B3-4C5D-6E7F-8A9B-0C1D2E3F4A5B}']
    function Validate(const AValue: T): TValidationResult;
  end;

  TValidator<T> = class(TInterfacedObject, IValidator<T>)
  public
    function Validate(const AValue: T): TValidationResult;
    function ValidateInstance(const AValue: TValue): TValidationResult;
  end;

  IValidationRule<T> = interface
    ['{F4F5E6D7-C8B9-0A1B-2C3D-4E5F6A7B8C9D}']
    function Validate(const AModel: T; const AResult: TValidationResult): Boolean;
  end;

  TValidationRule<T: class> = class(TInterfacedObject, IValidationRule<T>)
  private
    FPropName: string;
    FSelector: TFunc<T, TValue>;
    FRequired: Boolean;
    FMinLength: Integer;
    FMaxLength: Integer;
    FMinRange: Double;
    FMaxRange: Double;
    FHasRange: Boolean;
    FEmailAddress: Boolean;
    FPattern: string;
    FPatternName: string;
    FPatternLocale: string;
    FCustomRule: TFunc<T, TValue, Boolean>;
    FMessage: string;
    FCondition: TFunc<T, Boolean>;
  public
    constructor Create(const APropName: string; const ASelector: TFunc<T, TValue>);
    function Validate(const AModel: T; const AResult: TValidationResult): Boolean;
  end;

  TValidationRuleBuilder<T: class> = record
  private
    FRule: TValidationRule<T>;
  public
    constructor Create(ARule: TValidationRule<T>);
    function Required: TValidationRuleBuilder<T>;
    function Length(AMinLength, AMaxLength: Integer): TValidationRuleBuilder<T>;
    function Range(const AMin, AMax: Double): TValidationRuleBuilder<T>; overload;
    function Range(const AMin, AMax: Integer): TValidationRuleBuilder<T>; overload;
    function EmailAddress: TValidationRuleBuilder<T>;
    function Matches(const APattern: string): TValidationRuleBuilder<T>;
    function MatchesPattern(const APatternName: string; const ALocale: string = ''): TValidationRuleBuilder<T>;
    function Must(const APredicate: TFunc<TValue, Boolean>): TValidationRuleBuilder<T>; overload;
    function Must(const APredicate: TFunc<T, TValue, Boolean>): TValidationRuleBuilder<T>; overload;
    function WithMessage(const AMessage: string): TValidationRuleBuilder<T>;
    function When(const ACondition: TFunc<T, Boolean>): TValidationRuleBuilder<T>; overload;
    function When(const ACondition: BooleanExpression): TValidationRuleBuilder<T>; overload;
  end;

  TAbstractValidator<T: class> = class(TInterfacedObject, IValidator<T>, IValidator)
  private
    FRules: IList<IValidationRule<T>>;
    FModel: T;
    function GetModel: T;
  protected
    property Model: T read GetModel;
    property M: T read GetModel;

    function RuleFor(const APropName: string): TValidationRuleBuilder<T>; overload;
    function RuleFor(const APropName: string; const ASelector: TFunc<T, TValue>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const APropName: string; const AExpression: BooleanExpression): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AExpression: BooleanExpression): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<string>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<Integer>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<Int64>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<Boolean>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<Double>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<Currency>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<TDateTime>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<TDate>): TValidationRuleBuilder<T>; overload;
    function RuleFor(const AProperty: Prop<TTime>): TValidationRuleBuilder<T>; overload;
    function RuleFor<TPropVal>(const AProperty: Prop<TPropVal>): TValidationRuleBuilder<T>; overload;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function Validate(const AValue: T): TValidationResult; virtual;
    function ValidateInstance(const AValue: TValue): TValidationResult; virtual;
  end;

  /// <summary>
  ///   Non-generic validator helper.
  /// </summary>
  TValidator = class
  private
     class function GetFieldValue(const AValue: TValue): TValue;
  public
    class function Validate(const AValue: TValue): TValidationResult;
  end;

implementation

{ TValidator }

class function TValidator.GetFieldValue(const AValue: TValue): TValue;
var
  RType: TRttiType;
  Field: TRttiField;
begin
  Result := AValue;
  if AValue.Kind = tkRecord then
  begin
    RType := TReflection.Context.GetType(AValue.TypeInfo);
    if (RType <> nil) and (RType is TRttiRecordType) then
    begin
      Field := TRttiRecordType(RType).GetField('FValue');
      if Field <> nil then
        Result := Field.GetValue(AValue.GetReferenceToRawData);
    end;
  end;
end;

{ TValidationResult }

constructor TValidationResult.Create;
begin
  inherited Create;
  FErrors := TCollections.CreateList<TValidationError>;
end;

destructor TValidationResult.Destroy;
begin
  FErrors := nil;
  inherited;
end;

procedure TValidationResult.AddError(const AFieldName, AMessage: string);
var
  Error: TValidationError;
begin
  Error.FieldName := AFieldName;
  Error.ErrorMessage := AMessage;
  FErrors.Add(Error);
end;

function TValidationResult.GetErrors: TArray<TValidationError>;
begin
  Result := FErrors.ToArray;
end;

function TValidationResult.GetIsValid: Boolean;
begin
  Result := FErrors.Count = 0;
end;

function TValidationResult.ErrorMessage(const ADelimiter: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to FErrors.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ADelimiter;
    Result := Result + FErrors[I].ErrorMessage;
  end;
end;

{ RequiredAttribute }

function RequiredAttribute.IsValid(const AValue: TValue): Boolean;
var
  Val: TValue;
begin
  Val := TValidator.GetFieldValue(AValue);
  if Val.IsEmpty then
    Exit(False);

  case Val.Kind of
    tkString, tkLString, tkWString, tkUString:
      Result := Val.AsString.Trim <> '';
    tkInteger, tkInt64:
      Result := True; // Integers are always "present"
    tkFloat:
      Result := True;
    else
      Result := not AValue.IsEmpty;
  end;
end;

function RequiredAttribute.GetErrorMessage(const AFieldName: string): string;
begin
  Result := Format('The field "%s" is required.', [AFieldName]);
end;

{ StringLengthAttribute }

constructor StringLengthAttribute.Create(AMinLength, AMaxLength: Integer);
begin
  inherited Create;
  FMinLength := AMinLength;
  FMaxLength := AMaxLength;
end;

function StringLengthAttribute.IsValid(const AValue: TValue): Boolean;
var
  Len: Integer;
  Val: TValue;
begin
  Val := TValidator.GetFieldValue(AValue);
  if not (Val.Kind in [tkString, tkLString, tkWString, tkUString]) then
    Exit(True); // Not a string, skip validation

  Len := Val.AsString.Length;
  Result := (Len >= FMinLength) and (Len <= FMaxLength);
end;

function StringLengthAttribute.GetErrorMessage(const AFieldName: string): string;
begin
  Result := Format('The field "%s" must be between %d and %d characters.', 
    [AFieldName, FMinLength, FMaxLength]);
end;

{ EmailAddressAttribute }

function EmailAddressAttribute.IsValid(const AValue: TValue): Boolean;
var
  Email: string;
  Regex: TRegEx;
  Val: TValue;
begin
  Val := TValidator.GetFieldValue(AValue);
  if not (Val.Kind in [tkString, tkLString, tkWString, tkUString]) then
    Exit(True);

  Email := Val.AsString.Trim;
  if Email = '' then
    Exit(True); // Empty is valid (use Required for mandatory)

  // Simple email regex
  Regex := TRegEx.Create('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  Result := Regex.IsMatch(Email);
end;

function EmailAddressAttribute.GetErrorMessage(const AFieldName: string): string;
begin
  Result := Format('The field "%s" must be a valid email address.', [AFieldName]);
end;

{ RangeAttribute }

constructor RangeAttribute.Create(AMin, AMax: Double);
begin
  inherited Create;
  FMin := AMin;
  FMax := AMax;
end;

constructor RangeAttribute.Create(AMin, AMax: Integer);
begin
  Create(Double(AMin), Double(AMax));
end;

function RangeAttribute.IsValid(const AValue: TValue): Boolean;
var
  NumValue: Double;
  Val: TValue;
begin
  Val := TValidator.GetFieldValue(AValue);
  case Val.Kind of
    tkInteger:
      NumValue := Val.AsInteger;
    tkInt64:
      NumValue := Val.AsInt64;
    tkFloat:
      NumValue := Val.AsExtended;
    else
      Exit(True); // Not a number, skip
  end;

  Result := (NumValue >= FMin) and (NumValue <= FMax);
end;

function RangeAttribute.GetErrorMessage(const AFieldName: string): string;
begin
  Result := Format('The field "%s" must be between %.0f and %.0f.', 
    [AFieldName, FMin, FMax]);
end;

{ TValidationRule<T> }

constructor TValidationRule<T>.Create(const APropName: string; const ASelector: TFunc<T, TValue>);
begin
  inherited Create;
  FPropName := APropName;
  FSelector := ASelector;
  FRequired := False;
  FMinLength := -1;
  FMaxLength := -1;
  FHasRange := False;
  FEmailAddress := False;
  FPattern := '';
  FPatternName := '';
  FPatternLocale := '';
  FCustomRule := nil;
  FMessage := '';
  FCondition := nil;
end;

function TValidationRule<T>.Validate(const AModel: T; const AResult: TValidationResult): Boolean;
var
  Val, RawVal: TValue;
  ErrorMessage: string;
  Regex: TRegEx;
  Len: Integer;
  NumValue: Double;
  Valid, IsReqValid, IsNum: Boolean;
  Email, Text: string;
begin
  Result := True;
  if Assigned(FCondition) and not FCondition(AModel) then
    Exit;

  Val := FSelector(AModel);
  Valid := True;
  ErrorMessage := '';

  // Required
  if FRequired then
  begin
    RawVal := TValidator.GetFieldValue(Val);
    IsReqValid := True;
    if RawVal.IsEmpty then
      IsReqValid := False
    else
    begin
      case RawVal.Kind of
        tkString, tkLString, tkWString, tkUString:
          IsReqValid := RawVal.AsString.Trim <> '';
      end;
    end;
    if not IsReqValid then
    begin
      Valid := False;
      if FMessage <> '' then ErrorMessage := FMessage else ErrorMessage := Format('The field "%s" is required.', [FPropName]);
    end;
  end;

  // Length
  if Valid and ((FMinLength >= 0) or (FMaxLength >= 0)) then
  begin
    RawVal := TValidator.GetFieldValue(Val);
    if RawVal.Kind in [tkString, tkLString, tkWString, tkUString] then
    begin
      Len := RawVal.AsString.Length;
      if (FMinLength >= 0) and (Len < FMinLength) then Valid := False;
      if (FMaxLength >= 0) and (Len > FMaxLength) then Valid := False;
      if not Valid then
      begin
        if FMessage <> '' then ErrorMessage := FMessage else ErrorMessage := Format('The field "%s" must be between %d and %d characters.', [FPropName, FMinLength, FMaxLength]);
      end;
    end;
  end;

  // Range
  if Valid and FHasRange then
  begin
    RawVal := TValidator.GetFieldValue(Val);
    IsNum := False;
    NumValue := 0.0;
    case RawVal.Kind of
      tkInteger: begin NumValue := RawVal.AsInteger; IsNum := True; end;
      tkInt64: begin NumValue := RawVal.AsInt64; IsNum := True; end;
      tkFloat: begin NumValue := RawVal.AsExtended; IsNum := True; end;
    end;
    if IsNum then
    begin
      if (NumValue < FMinRange) or (NumValue > FMaxRange) then
      begin
        Valid := False;
        if FMessage <> '' then ErrorMessage := FMessage else ErrorMessage := Format('The field "%s" must be between %.0f and %.0f.', [FPropName, FMinRange, FMaxRange]);
      end;
    end;
  end;

  // Email
  if Valid and FEmailAddress then
  begin
    RawVal := TValidator.GetFieldValue(Val);
    if RawVal.Kind in [tkString, tkLString, tkWString, tkUString] then
    begin
      Email := RawVal.AsString.Trim;
      if Email <> '' then
      begin
        Regex := TRegEx.Create('^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
        if not Regex.IsMatch(Email) then
        begin
          Valid := False;
          if FMessage <> '' then ErrorMessage := FMessage else ErrorMessage := Format('The field "%s" must be a valid email address.', [FPropName]);
        end;
      end;
    end;
  end;

  // Pattern (Regex)
  if Valid and ((FPattern <> '') or (FPatternName <> '')) then
  begin
    RawVal := TValidator.GetFieldValue(Val);
    if RawVal.Kind in [tkString, tkLString, tkWString, tkUString] then
    begin
      Text := RawVal.AsString;
      if Text <> '' then
      begin
        if FPattern <> '' then
          Regex := TRegEx.Create(FPattern)
        else
          Regex := TRegEx.Create(TValidationPatterns.Get(FPatternName, FPatternLocale));

        if not Regex.IsMatch(Text) then
        begin
          Valid := False;
          if FMessage <> '' then ErrorMessage := FMessage else ErrorMessage := Format('The field "%s" format is invalid.', [FPropName]);
        end;
      end;
    end;
  end;

  // Custom rule (Must)
  if Valid and Assigned(FCustomRule) then
  begin
    if not FCustomRule(AModel, Val) then
    begin
      Valid := False;
      if FMessage <> '' then ErrorMessage := FMessage else ErrorMessage := Format('The field "%s" is invalid.', [FPropName]);
    end;
  end;

  if not Valid then
  begin
    AResult.AddError(FPropName, ErrorMessage);
    Result := False;
  end;
end;

{ TValidationRuleBuilder<T> }

constructor TValidationRuleBuilder<T>.Create(ARule: TValidationRule<T>);
begin
  FRule := ARule;
end;

function TValidationRuleBuilder<T>.Required: TValidationRuleBuilder<T>;
begin
  FRule.FRequired := True;
  Result := Self;
end;

function TValidationRuleBuilder<T>.Length(AMinLength, AMaxLength: Integer): TValidationRuleBuilder<T>;
begin
  FRule.FMinLength := AMinLength;
  FRule.FMaxLength := AMaxLength;
  Result := Self;
end;

function TValidationRuleBuilder<T>.Range(const AMin, AMax: Double): TValidationRuleBuilder<T>;
begin
  FRule.FMinRange := AMin;
  FRule.FMaxRange := AMax;
  FRule.FHasRange := True;
  Result := Self;
end;

function TValidationRuleBuilder<T>.Range(const AMin, AMax: Integer): TValidationRuleBuilder<T>;
begin
  Result := Range(Double(AMin), Double(AMax));
end;

function TValidationRuleBuilder<T>.EmailAddress: TValidationRuleBuilder<T>;
begin
  FRule.FEmailAddress := True;
  Result := Self;
end;

function TValidationRuleBuilder<T>.Matches(const APattern: string): TValidationRuleBuilder<T>;
begin
  FRule.FPattern := APattern;
  Result := Self;
end;

function TValidationRuleBuilder<T>.MatchesPattern(const APatternName: string; const ALocale: string = ''): TValidationRuleBuilder<T>;
begin
  FRule.FPatternName := APatternName;
  FRule.FPatternLocale := ALocale;
  Result := Self;
end;

function TValidationRuleBuilder<T>.Must(const APredicate: TFunc<TValue, Boolean>): TValidationRuleBuilder<T>;
begin
  FRule.FCustomRule := function(AModel: T; AVal: TValue): Boolean
    begin
      Result := APredicate(AVal);
    end;
  Result := Self;
end;

function TValidationRuleBuilder<T>.Must(const APredicate: TFunc<T, TValue, Boolean>): TValidationRuleBuilder<T>;
begin
  FRule.FCustomRule := APredicate;
  Result := Self;
end;

function TValidationRuleBuilder<T>.WithMessage(const AMessage: string): TValidationRuleBuilder<T>;
begin
  FRule.FMessage := AMessage;
  Result := Self;
end;

function TValidationRuleBuilder<T>.When(const ACondition: TFunc<T, Boolean>): TValidationRuleBuilder<T>;
begin
  FRule.FCondition := ACondition;
  Result := Self;
end;

function TValidationRuleBuilder<T>.When(const ACondition: BooleanExpression): TValidationRuleBuilder<T>;
var
  Expr: IExpression;
  LRuntimeVal: Boolean;
begin
  Expr := ACondition.Expression;
  LRuntimeVal := ACondition.RuntimeValue;
  FRule.FCondition := function(AModel: T): Boolean
    begin
      if Expr <> nil then
        Result := TExpressionEvaluator.Evaluate(Expr, AModel)
      else
        Result := LRuntimeVal;
    end;
  Result := Self;
end;

{ TAbstractValidator<T> }

function TAbstractValidator<T>.GetModel: T;
var
  Obj: TObject;
begin
  if FModel = nil then
  begin
    try
      // Dext.Entity registers its ORM factory; without it, the Core
      // prototype (RTTI only) is enough for typed validation rules.
      if Assigned(PrototypeFactory) then
        Obj := PrototypeFactory(TypeInfo(T))
      else
        Obj := Dext.Core.SmartTypes.Prototype.Entity(TypeInfo(T));
      FModel := T(Pointer(@Obj)^);
    except
      on E: Exception do
      begin
        raise Exception.CreateFmt(
          'Failed to retrieve type-safe validation Model helper for "%s". ' +
          'Details: %s. ' +
          'If this class does not use Smart Properties, please use the string-based/anonymous method RuleFor overloads.',
          [TClass(T).ClassName, E.Message]);
      end;
    end;
  end;
  Result := FModel;
end;

constructor TAbstractValidator<T>.Create;
begin
  inherited Create;
  FRules := TCollections.CreateList<IValidationRule<T>>;
  FModel := nil;
end;

destructor TAbstractValidator<T>.Destroy;
begin
  FRules := nil;
  FModel := nil;
  inherited;
end;

function TAbstractValidator<T>.RuleFor(const APropName: string): TValidationRuleBuilder<T>;
var
  LPropName: string;
begin
  LPropName := APropName;
  Result := RuleFor(APropName,
    function(AModel: T): TValue
    var
      RttiType: TRttiType;
      Prop: TRttiProperty;
      Field: TRttiField;
    begin
      RttiType := TReflection.Context.GetType(TypeInfo(T));
      Prop := RttiType.GetProperty(LPropName);
      if Prop <> nil then
        Exit(Prop.GetValue(Pointer(AModel)));

      Field := RttiType.GetField(LPropName);
      if Field <> nil then
        Exit(Field.GetValue(Pointer(AModel)));

      Result := TValue.Empty;
    end);
end;

function TAbstractValidator<T>.RuleFor(const APropName: string; const ASelector: TFunc<T, TValue>): TValidationRuleBuilder<T>;
var
  Rule: TValidationRule<T>;
begin
  Rule := TValidationRule<T>.Create(APropName, ASelector);
  FRules.Add(Rule);
  Result := TValidationRuleBuilder<T>.Create(Rule);
end;

function TAbstractValidator<T>.RuleFor(const APropName: string; const AExpression: BooleanExpression): TValidationRuleBuilder<T>;
var
  Expr: IExpression;
  LRuntimeVal: Boolean;
begin
  Expr := AExpression.Expression;
  LRuntimeVal := AExpression.RuntimeValue;
  Result := RuleFor(APropName,
    function(AModel: T): TValue
    begin
      if Expr <> nil then
        Result := TExpressionEvaluator.Evaluate(Expr, AModel)
      else
        Result := LRuntimeVal;
    end);
  Result.Must(function(Val: TValue): Boolean
    begin
      Result := Val.AsBoolean = True;
    end);
end;

function TAbstractValidator<T>.RuleFor(const AExpression: BooleanExpression): TValidationRuleBuilder<T>;
var
  PropName: string;
  Binary: TBinaryExpression;
begin
  PropName := '';
  if AExpression.Expression <> nil then
  begin
    if AExpression.Expression is TBinaryExpression then
    begin
      Binary := TBinaryExpression(AExpression.Expression);
      if Binary.Left is TPropertyExpression then
        PropName := TPropertyExpression(Binary.Left).PropertyName;
    end;
  end;

  if PropName = '' then
    raise Exception.Create('Cannot extract property name from expression. Please specify property name using string or Prop overload.');

  Result := RuleFor(PropName, AExpression);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<string>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<Integer>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<Int64>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<Boolean>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<Double>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<Currency>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<TDateTime>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<TDate>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor(const AProperty: Prop<TTime>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.RuleFor<TPropVal>(const AProperty: Prop<TPropVal>): TValidationRuleBuilder<T>;
begin
  Result := RuleFor(AProperty.Name);
end;

function TAbstractValidator<T>.Validate(const AValue: T): TValidationResult;
var
  Rule: IValidationRule<T>;
begin
  Result := TValidationResult.Create;
  for Rule in FRules do
  begin
    Rule.Validate(AValue, Result);
  end;
end;

function TAbstractValidator<T>.ValidateInstance(const AValue: TValue): TValidationResult;
begin
  Result := Validate(AValue.AsType<T>);
end;

{ TValidator<T> }

function TValidator<T>.Validate(const AValue: T): TValidationResult;
begin
  Result := TValidator.Validate(TValue.From<T>(AValue));
end;

function TValidator<T>.ValidateInstance(const AValue: TValue): TValidationResult;
begin
  Result := Validate(AValue.AsType<T>);
end;

{ TValidationPatterns }

class constructor TValidationPatterns.Create;
begin
  FPatterns := TCollections.CreateDictionary<string, string>;
  FDefaultLocale := 'en-US';

  // Register standard defaults
  Register('Email', '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  Register('Phone', '^\+\d{2}\s\d{2}\s\d{9}$', 'pt-BR');
  Register('Phone', '^\+1\s\(\d{3}\)\s\d{3}-\d{4}$', 'en-US');
  Register('ZipCode', '^\d{5}-\d{3}$', 'pt-BR');
  Register('ZipCode', '^\d{5}(-\d{4})?$', 'en-US');
end;

class destructor TValidationPatterns.Destroy;
begin
  FPatterns := nil;
end;

class procedure TValidationPatterns.Register(const AName, APattern: string; const ALocale: string);
var
  Key: string;
begin
  if ALocale <> '' then
    Key := ALocale + ':' + AName
  else
    Key := AName;
  FPatterns.AddOrSetValue(Key, APattern);
end;

class function TValidationPatterns.Get(const AName: string; const ALocale: string): string;
var
  Loc: string;
  Key: string;
begin
  if ALocale <> '' then
    Loc := ALocale
  else
    Loc := FDefaultLocale;

  Key := Loc + ':' + AName;
  if FPatterns.TryGetValue(Key, Result) then
    Exit;

  // Fallback to name as key (locale-neutral)
  if FPatterns.TryGetValue(AName, Result) then
    Exit;

  // If still not found, check default locale
  Key := FDefaultLocale + ':' + AName;
  if FPatterns.TryGetValue(Key, Result) then
    Exit;

  Result := '';
end;

class function TValidationPatterns.Phone(const ALocale: string): string;
begin
  Result := Get('Phone', ALocale);
end;

class function TValidationPatterns.ZipCode(const ALocale: string): string;
begin
  Result := Get('ZipCode', ALocale);
end;

class function TValidationPatterns.Email: string;
begin
  Result := Get('Email');
end;

{ TValidator (Non-generic) }

class function TValidator.Validate(const AValue: TValue): TValidationResult;
var
  RttiType: TRttiType;
  Field: TRttiField;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  FieldValue: TValue;
  Instance: Pointer;
  ValidationAttr: ValidationAttribute;
begin
  Result := TValidationResult.Create;
  
  if AValue.IsEmpty then
    Exit;

  RttiType := TReflection.Context.GetType(AValue.TypeInfo);
  if RttiType = nil then Exit;

  if RttiType.IsInstance then
    Instance := AValue.AsObject
  else
    Instance := AValue.GetReferenceToRawData;

  // Validate Fields
  for Field in RttiType.GetFields do
  begin
    FieldValue := Field.GetValue(Instance);
    
    for Attr in Field.GetAttributes do
    begin
      if Attr is ValidationAttribute then
      begin
        ValidationAttr := ValidationAttribute(Attr);
        if not ValidationAttr.IsValid(FieldValue) then
        begin
          Result.AddError(Field.Name, ValidationAttr.GetErrorMessage(Field.Name));
        end;
      end;
    end;
  end;

  // Validate Properties
  for Prop in RttiType.GetProperties do
  begin
    FieldValue := Prop.GetValue(Instance);
    
    for Attr in Prop.GetAttributes do
    begin
      if Attr is ValidationAttribute then
      begin
        ValidationAttr := ValidationAttribute(Attr);
        if not ValidationAttr.IsValid(FieldValue) then
        begin
          Result.AddError(Prop.Name, ValidationAttr.GetErrorMessage(Prop.Name));
        end;
      end;
    end;
  end;
end;

initialization

finalization
  // Clear the global interface pointer raw (without calling @IntfClear / _Release)
  // because the package hosting the actual closure object might have already been unloaded.
  PPointer(@PrototypeFactory)^ := nil;

end.


