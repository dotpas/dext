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
{  Created: 2026-01-03                                                      }
{                                                                           }
{  Dext.Assertions - Fluent assertions inspired by FluentAssertions.        }
{                                                                           }
{  Usage:                                                                   }
{    ShouldString(Value).Be('expected');                                    }
{    ShouldInteger(N).BeGreaterThan(0);                                     }
{    ShouldBoolean(B).BeTrue;                                               }
{    ShouldAction(MyProc).Throw<EInvalidOp>;                                }
{                                                                           }
{***************************************************************************}
unit Dext.Assertions;

interface

uses
  System.DateUtils,
  System.IOUtils,
  System.Rtti,
  System.SysUtils,
  System.Character,
  System.TypInfo,
  System.Variants,
  Dext,
  Dext.Core.SmartTypes,
  Dext.Types.Nullable,
  Dext.Types.UUID,
  Dext.Core.Reflection,
  Dext.Collections.Base;

type
  /// <summary>
  ///   Exception raised when an assertion fails.
  /// </summary>
  EAssertionFailed = class(Exception);

  /// <summary>Static utilities for assertions and test failure control.</summary>
  Assert = record
  public
    /// <summary>
    ///   Executes a block of assertions in "soft" mode (Soft Assert).
    ///   Catches all failures within the block and reports them together at the end, instead of stopping at the first failure.
    /// </summary>
    class procedure Multiple(const Action: TProc); static;
    
    /// <summary>Interrupts the test immediately with a custom failure message.</summary>
    class procedure Fail(const Message: string); static;

    /// <summary>Internal use. Registers a failure respecting the Assert.Multiple context.</summary>
    class procedure RegisterFailure(const Message, Reason: string); static;

    /// <summary>Verifies if the execution of the procedure throws an exception of the specified class.</summary>
    class procedure WillRaise(const Action: TProc; ExceptionClass: ExceptClass = nil; const MessagePart: string = ''); static;
  end;

  /// <summary>Fluent assertions for TDateTime types.</summary>
  ShouldDateTime = record
  private
    FValue: TDateTime;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(Value: TDateTime);
    /// <summary>Verifies if the date/time is exactly equal to the expected.</summary>
    function Be(Expected: TDateTime): ShouldDateTime;
    /// <summary>Verifies if the date/time is within a tolerance margin (default 1s).</summary>
    function BeCloseTo(Expected: TDateTime; PrecisionMS: Int64 = 1000): ShouldDateTime;
    /// <summary>Verifies if the value is after the referenced date.</summary>
    function BeAfter(Expected: TDateTime): ShouldDateTime;
    /// <summary>Verifies if the value is before the referenced date.</summary>
    function BeBefore(Expected: TDateTime): ShouldDateTime;
    /// <summary>Verifies if the date is the same day, ignoring the time part.</summary>
    function BeSameDateAs(Expected: TDateTime): ShouldDateTime;
    /// <summary>Verifies if the value corresponds to the current system date.</summary>
    function BeToday: ShouldDateTime;
    /// <summary>Verifies that the date/time is not the unexpected value, to the millisecond.</summary>
    function NotBe(Unexpected: TDateTime): ShouldDateTime;
    /// <summary>Verifies if the value is within Tolerance days of the expected value.</summary>
    function BeApproximately(Expected: TDateTime; Tolerance: Double): ShouldDateTime;
    /// <summary>Verifies that the value is strictly later than the expected date/time.</summary>
    function BeGreaterThan(Expected: TDateTime): ShouldDateTime;
    /// <summary>Verifies that the value is strictly earlier than the expected date/time.</summary>
    function BeLessThan(Expected: TDateTime): ShouldDateTime;
    /// <summary>Verifies that the value lies between Min and Max, inclusive.</summary>
    function BeInRange(Min, Max: TDateTime): ShouldDateTime;
    /// <summary>Verifies that the value is greater than zero.</summary>
    function BePositive: ShouldDateTime;
    /// <summary>Verifies that the value is less than zero.</summary>
    function BeNegative: ShouldDateTime;
    /// <summary>Verifies that the value is zero.</summary>
    function BeZero: ShouldDateTime;
    /// <summary>Verifies that the date/time satisfies the predicate.</summary>
    function Satisfy(const Predicate: TPredicate<TDateTime>): ShouldDateTime; overload;
    /// <summary>Verifies that the underlying day number satisfies the predicate.</summary>
    function Satisfy(const Predicate: TPredicate<Double>): ShouldDateTime; overload;
    /// <summary>Adds a friendly explanation for the assertion (displayed on error).</summary>
    function Because(const Reason: string): ShouldDateTime;
    function &And: ShouldDateTime;
    function AndAlso: ShouldDateTime;
  end;

  /// <summary>Fluent assertions for strings.</summary>
  ShouldString = record
  private
    FValue: string;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Value: string);
    
    /// <summary>Verifies exact equality (case-sensitive).</summary>
    function Be(const Expected: string): ShouldString;
    /// <summary>Verifies inequality.</summary>
    function NotBe(const Unexpected: string): ShouldString;
    /// <summary>Verifies equality ignoring case.</summary>
    function BeEquivalentTo(const Expected: string): ShouldString;
    function BeEmpty: ShouldString;
    function NotBeEmpty: ShouldString;
    /// <summary>Verifies if the string contains the specified substring.</summary>
    function Contain(const Substring: string): ShouldString;
    function NotContain(const Substring: string): ShouldString;
    function StartWith(const Prefix: string): ShouldString;
    function EndWith(const Suffix: string): ShouldString;
    function HaveLength(Expected: Integer): ShouldString;
    function HaveLengthGreaterThan(Expected: Integer): ShouldString;
    function HaveLengthLessThan(Expected: Integer): ShouldString;
    /// <summary>Validates the string against a regular expression.</summary>
    function MatchRegex(const Pattern: string): ShouldString;
    function BeUpperCase: ShouldString;
    function BeLowerCase: ShouldString;
    function BeOneOf(const Values: TArray<string>): ShouldString;
    /// <summary>
    ///   Compares the current value with a snapshot file saved on disk. 
    ///   Useful for large JSON payloads or complex outputs that change rarely.
    /// </summary>
    function MatchSnapshot(const SnapshotName: string): ShouldString;
    function Satisfy(const Predicate: TPredicate<string>): ShouldString;
    function Because(const Reason: string): ShouldString;
    // Chaining
    function &And: ShouldString;
    function AndAlso: ShouldString; // Alias for fluent chaining
  end;

  /// <summary>
  ///   Integer-specific Should assertions.
  /// </summary>
  ShouldInteger = record
  private
    FValue: Integer;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(Value: Integer);
    
    function Be(Expected: Integer): ShouldInteger;
    function NotBe(Unexpected: Integer): ShouldInteger;
    function BeGreaterThan(Expected: Integer): ShouldInteger;
    function BeGreaterOrEqualTo(Expected: Integer): ShouldInteger;
    function BeLessThan(Expected: Integer): ShouldInteger;
    function BeLessOrEqualTo(Expected: Integer): ShouldInteger;
    function BeInRange(Min, Max: Integer): ShouldInteger;
    function BePositive: ShouldInteger;
    function BeNegative: ShouldInteger;
    function BeZero: ShouldInteger;
    function BeOneOf(const Values: TArray<Integer>): ShouldInteger;
    function Satisfy(const Predicate: TPredicate<Integer>): ShouldInteger;
    function Because(const Reason: string): ShouldInteger;
    function &And: ShouldInteger;
    function AndAlso: ShouldInteger;
  end;

  /// <summary>
  ///   Boolean-specific Should assertions.
  /// </summary>
  ShouldBoolean = record
  private
    FValue: Boolean;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(Value: Boolean);
    
    function BeTrue: ShouldBoolean;
    function BeFalse: ShouldBoolean;
    function Be(Expected: Boolean): ShouldBoolean;
    function NotBe(Unexpected: Boolean): ShouldBoolean;
    function Because(const Reason: string): ShouldBoolean;
    function &And: ShouldBoolean;
    function AndAlso: ShouldBoolean;
  end;

  /// <summary>Fluent assertions for code execution and exception handling.</summary>
  ShouldAction = record
  private
    FAction: TProc;
    FReason: string;
    FExceptionClass: ExceptClass;
    FExceptionMessage: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Action: TProc);
    
    /// <summary>Verifies if the procedure throws an exception of generic type E.</summary>
    function Throw<E: Exception>: ShouldAction; overload;
    /// <summary>Verifies if the procedure throws an exception of the specified class.</summary>
    function Throw(AExceptionClass: ExceptClass): ShouldAction; overload;
    /// <summary>Validates if the message of the thrown exception is exactly equal to the expected one.</summary>
    function ThrowWithMessage(const ExpectedMessage: string): ShouldAction;
    /// <summary>Validates if the exception message contains the specified substring.</summary>
    function ThrowWithMessageContaining(const Substring: string): ShouldAction;
    /// <summary>Verifies if the procedure executes without throwing any exceptions.</summary>
    function NotThrow: ShouldAction;
    function Because(const Reason: string): ShouldAction;
    function &And: ShouldAction;
    function AndAlso: ShouldAction;
  end;

  /// <summary>
  ///   Double/Float-specific Should assertions.
  /// </summary>
  ShouldDouble = record
  private
    FValue: Double;
    FReason: string;
    FPrecision: Double;
    procedure Fail(const Message: string);
  public
    constructor Create(Value: Double);
    
    function Be(Expected: Double): ShouldDouble;
    function NotBe(Unexpected: Double): ShouldDouble;
    function BeApproximately(Expected, Tolerance: Double): ShouldDouble;
    function BeGreaterThan(Expected: Double): ShouldDouble;
    function BeLessThan(Expected: Double): ShouldDouble;
    function BeInRange(Min, Max: Double): ShouldDouble;
    function BePositive: ShouldDouble;
    function BeNegative: ShouldDouble;
    function BeZero: ShouldDouble;
    function Satisfy(const Predicate: TPredicate<Double>): ShouldDouble;
    function Because(const Reason: string): ShouldDouble;
    function &And: ShouldDouble;
    function AndAlso: ShouldDouble;
  end;

  /// <summary>
  ///   Int64-specific Should assertions.
  /// </summary>
  ShouldInt64 = record
  private
    FValue: Int64;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(Value: Int64);
    
    function Be(Expected: Int64): ShouldInt64;
    function NotBe(Unexpected: Int64): ShouldInt64;
    function BeGreaterThan(Expected: Int64): ShouldInt64;
    function BeLessThan(Expected: Int64): ShouldInt64;
    function BeInRange(Min, Max: Int64): ShouldInt64;
    function BePositive: ShouldInt64;
    function BeNegative: ShouldInt64;
    function BeZero: ShouldInt64;
    function BeOneOf(const Values: TArray<Int64>): ShouldInt64;
    function Satisfy(const Predicate: TPredicate<Int64>): ShouldInt64;
    function Because(const Reason: string): ShouldInt64;
    function &And: ShouldInt64;
    function AndAlso: ShouldInt64;
  end;

  /// <summary>
  ///   GUID-specific Should assertions.
  /// </summary>
  ShouldGuid = record
  private
    FValue: TGUID;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Value: TGUID);
    
    function Be(const Expected: TGUID): ShouldGuid;
    function NotBe(const Unexpected: TGUID): ShouldGuid;
    function BeEmpty: ShouldGuid;
    function NotBeEmpty: ShouldGuid;
    function Because(const Reason: string): ShouldGuid;
    function &And: ShouldGuid;
    function AndAlso: ShouldGuid;
  end;

  /// <summary>
  ///   UUID-specific Should assertions (Dext TUUID type).
  /// </summary>
  ShouldUUID = record
  private
    FValue: TUUID;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Value: TUUID);
    
    function Be(const Expected: TUUID): ShouldUUID;
    function NotBe(const Unexpected: TUUID): ShouldUUID;
    function BeEmpty: ShouldUUID;
    function NotBeEmpty: ShouldUUID;
    function Because(const Reason: string): ShouldUUID;
    function &And: ShouldUUID;
    function AndAlso: ShouldUUID;
  end;

  /// <summary>
  ///   Variant-specific Should assertions for legacy code support.
  /// </summary>
  ShouldVariant = record
  private
    FValue: Variant;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Value: Variant);
    
    function Be(const Expected: Variant): ShouldVariant;
    function NotBe(const Unexpected: Variant): ShouldVariant;
    function BeNull: ShouldVariant;
    function NotBeNull: ShouldVariant;
    function BeEmpty: ShouldVariant;
    function NotBeEmpty: ShouldVariant;
    function BeOfType(VarType: TVarType): ShouldVariant;
    function Because(const Reason: string): ShouldVariant;
    function &And: ShouldVariant;
    function AndAlso: ShouldVariant;
  end;

  /// <summary>
  ///   Generic object/interface Should assertions.
  /// </summary>
  ShouldObject = record
  private
    FValue: TObject;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(Value: TObject);
    
    function BeNil: ShouldObject;
    function NotBeNil: ShouldObject;
    function BeNull: ShouldObject; // Alias for BeNil
    function NotBeNull: ShouldObject; // Alias for NotBeNil
    function BeOfType<T: class>: ShouldObject;
    function BeAssignableTo<T: class>: ShouldObject;
    function BeEquivalentTo(Expected: TObject): ShouldObject;
    function Satisfy(const Predicate: TPredicate<TObject>): ShouldObject;
    function MatchSnapshot(const SnapshotName: string): ShouldObject;
    function Because(const Reason: string): ShouldObject;
    function &And: ShouldObject;
    function AndAlso: ShouldObject;
  end;

  /// <summary>
  ///   Property assertion helper for deep navigation.
  /// </summary>
  ShouldProperty = record
  private
    FParent: ShouldObject;
    FValue: TValue;
    FName: string;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Parent: ShouldObject; const Name: string; const Value: TValue);
    
    function Value: TValue;
    
    function WhichString: ShouldString;
    function WhichInteger: ShouldInteger;
    function WhichBoolean: ShouldBoolean;
    function WhichObject: ShouldObject;
    function WhichGuid: ShouldGuid;
    
    function &And: ShouldObject;
    function AndAlso: ShouldObject;
  end;

  /// <summary>
  ///   Property assertions of ShouldObject. They live here because a record
  ///   cannot reference ShouldProperty before it is declared, and a helper
  ///   alias does not activate the helper: a facade unit has to declare its
  ///   own helper and delegate to these methods.
  /// </summary>
  ShouldObjectMembers = record
  public
    class function HaveProperty(const Subject: ShouldObject; const PropertyName: string): ShouldProperty; static;
    class function HavePropertyValue(const Subject: ShouldObject; const PropertyName: string;
      const ExpectedValue: TValue): ShouldObject; static;
    class function HaveValue(const Subject: ShouldObject; const PropertyMetadata: StringType;
      const ExpectedValue: string): ShouldObject; overload; static;
    class function HaveValue(const Subject: ShouldObject; const PropertyMetadata: IntType;
      ExpectedValue: Integer): ShouldObject; overload; static;
    class function HaveValue<T>(const Subject: ShouldObject; const PropertyMetadata: T;
      ExpectedValue: T): ShouldObject; overload; static;
  end;

  ShouldObjectHelper = record helper for ShouldObject
  public
    function HaveProperty(const PropertyName: string): ShouldProperty; overload;
    // function HaveProperty<T>(const PropertyMetadata: Prop<T>): ShouldProperty; overload;
    function HavePropertyValue(const PropertyName: string; const ExpectedValue: TValue): ShouldObject; overload;
    // Strongly-typed methods for SmartTypes (separate name to avoid ambiguity with implicit operators)
    function HaveValue(const PropertyMetadata: StringType; const ExpectedValue: string): ShouldObject; overload;
    function HaveValue(const PropertyMetadata: IntType; ExpectedValue: Integer): ShouldObject; overload;
    function HaveValue<T>(const PropertyMetadata: T; ExpectedValue: T): ShouldObject; overload;
  end;

  /// <summary>
  ///   Interface-specific Should assertions.
  /// </summary>
  ShouldInterface = record
  private
    FValue: IInterface;
    FReason: string;
    procedure Fail(const Message: string);
  public
    constructor Create(const Value: IInterface);
    
    function BeNil: ShouldInterface;
    function NotBeNil: ShouldInterface;
    function BeEquivalentTo(const Expected: IInterface): ShouldInterface;
    function MatchSnapshot(const SnapshotName: string): ShouldInterface;
    function Because(const Reason: string): ShouldInterface;
    function &And: ShouldInterface;
    function AndAlso: ShouldInterface;
  end;

  /// <summary>
  ///   Generic list/enumerable assertions.
  /// </summary>
  ShouldList<T> = record
  private
    FItems: TArray<T>;
    FReason: string;
    procedure Fail(const Message: string);
    function GetCount: Integer;
  public
    constructor Create(const Value: System.IEnumerable<T>); overload;
    constructor Create(const Value: Dext.Collections.Base.IEnumerable<T>); overload;
    constructor Create(const Value: TArray<T>); overload;
    // TODO : add explicit IList<T>

    function BeEmpty: ShouldList<T>;
    function NotBeEmpty: ShouldList<T>;
    function HaveCount(Expected: Integer): ShouldList<T>;
    function HaveCountGreaterThan(Expected: Integer): ShouldList<T>;
    function HaveCountLessThan(Expected: Integer): ShouldList<T>;
    function Contain(const Item: T): ShouldList<T>;
    function NotContain(const Item: T): ShouldList<T>;
    function ContainInOrder(const Items: TArray<T>): ShouldList<T>;
    function BeEquivalentTo(const Expected: TArray<T>): ShouldList<T>; overload;
    function BeEquivalentTo(const Expected: System.IEnumerable<T>): ShouldList<T>; overload;
    function BeEquivalentTo(const Expected: Dext.Collections.Base.IEnumerable<T>): ShouldList<T>; overload;
    function OnlyContain(const Predicate: TFunc<T, Boolean>): ShouldList<T>;
    function AllSatisfy(const Predicate: TFunc<T, Boolean>): ShouldList<T>;
    function AnySatisfy(const Predicate: TFunc<T, Boolean>): ShouldList<T>;
    function Because(const Reason: string): ShouldList<T>;
    function &And: ShouldList<T>;
    function AndAlso: ShouldList<T>;
  end;

  ShouldHelper = record
  public
    function List<T>(const Value: System.IEnumerable<T>): ShouldList<T>; overload;
    function List<T>(const Value: Dext.Collections.Base.IEnumerable<T>): ShouldList<T>; overload;
    function List<T>(const Value: TArray<T>): ShouldList<T>; overload;
  end;

// Global helper functions for cleaner syntax
function Should(const Value: string): ShouldString; overload;
function Should(Value: Integer): ShouldInteger; overload;
function Should(Value: Int64): ShouldInt64; overload;
function Should(Value: Boolean): ShouldBoolean; overload;
function Should(Value: Double): ShouldDouble; overload;
/// <summary>
///   Exact overload for Single. Without it, a real literal becomes ambiguous
///   once TDateTime has its own Should, and on Win64 it used to fall through
///   to the Variant overload.
/// </summary>
function Should(Value: Single): ShouldDouble; overload;
/// <summary>Exact overload for Extended and for real literals.</summary>
function Should(Value: Extended): ShouldDouble; overload;
/// <summary>Exact overload for Currency.</summary>
function Should(Value: Currency): ShouldDouble; overload;
/// <summary>
///   Compares a date/time with ShouldDateTime. Be uses SameDateTime
///   (millisecond precision).
/// </summary>
function Should(Value: TDateTime): ShouldDateTime; overload;
/// <summary>Compares a date with ShouldDateTime.</summary>
function Should(Value: TDate): ShouldDateTime; overload;
/// <summary>Compares a time with ShouldDateTime.</summary>
function Should(Value: TTime): ShouldDateTime; overload;
function Should(const Action: TProc): ShouldAction; overload;
function Should(const Value: TObject): ShouldObject; overload;
function Should(const Value: IInterface): ShouldInterface; overload;
function Should(const Value: TGUID): ShouldGuid; overload;
function Should(const Value: TUUID): ShouldUUID; overload;
function Should(const Value: Variant): ShouldVariant; overload;
function ShouldDate(Value: TDateTime): ShouldDateTime; overload;
function Should: ShouldHelper; overload;

// Smart Types / Prop<T> Overloads
function Should(const Value: StringType): ShouldString; overload;
function Should(const Value: IntType): ShouldInteger; overload;
function Should(const Value: Int64Type): ShouldInt64; overload;
function Should(const Value: BoolType): ShouldBoolean; overload;
function Should(const Value: FloatType): ShouldDouble; overload;
function Should(const Value: CurrencyType): ShouldDouble; overload;

// Nullable<T> Overloads
function Should(const Value: Nullable<string>): ShouldString; overload;
function Should(const Value: Nullable<Integer>): ShouldInteger; overload;
function Should(const Value: Nullable<Int64>): ShouldInt64; overload;
function Should(const Value: Nullable<Boolean>): ShouldBoolean; overload;
function Should(const Value: Nullable<Double>): ShouldDouble; overload;
function Should(const Value: Nullable<Currency>): ShouldDouble; overload;
function ShouldDate(const Value: Nullable<TDateTime>): ShouldDateTime; overload;
function ShouldDate(const Value: Prop<TDateTime>): ShouldDateTime; overload;

implementation

uses
  System.RegularExpressions,
  System.Math,
  System.Generics.Defaults,
  System.Generics.Collections,
  Dext.Collections,
  Dext.Collections.Comparers,
  Dext.Json,
  Dext.Json.Types;

threadvar
  GSoftAssertMode: Boolean;
  GSoftAssertErrors: IList<string>;

class procedure Assert.RegisterFailure(const Message, Reason: string);
var
  FullMsg: string;
begin
  if Reason <> '' then
    FullMsg := Message + ' because ' + Reason
  else
    FullMsg := Message;

  // If in Soft Assert mode, collect error and continue
  if GSoftAssertMode and (GSoftAssertErrors <> nil) then
  begin
    GSoftAssertErrors.Add(FullMsg);
  end
  else
  begin
    // Normal mode: raise exception immediately
    raise EAssertionFailed.Create(FullMsg);
  end;
end;

{ Assert }

class procedure Assert.Fail(const Message: string);
begin
  // Direct Assert.Fail should respect soft assertion context too
  Assert.RegisterFailure(Message, '');
end;

class procedure Assert.WillRaise(const Action: TProc; ExceptionClass: ExceptClass; const MessagePart: string);
begin
  if MessagePart = '' then
    Should(Action).Throw(ExceptionClass)
  else
    Should(Action).Throw(ExceptionClass).AndAlso.ThrowWithMessageContaining(MessagePart);
end;

class procedure Assert.Multiple(const Action: TProc);
var
  Errors: IList<string>;
  ErrorMsg: string;
  I: Integer;
begin
  // If already in soft mode (nested call), just execute
  if GSoftAssertMode then
  begin
    Action;
    Exit;
  end;

  Errors := TCollections.CreateList<string>;
  try
    GSoftAssertErrors := Errors;
    GSoftAssertMode := True;
    try
      try
        Action;
      except
        on E: Exception do
        begin
          // If a non-assertion exception occurs, we must stop and propagate it.
          // Assertion failures are already captured in GSoftAssertErrors (if they used Assert.RegisterFailure).
          // If EAssertionFailed escaped (e.g. from code not using Assert.RegisterFailure), we capture it too.
          if E is EAssertionFailed then
             Errors.Add(E.Message)
          else
             raise;
        end;
      end;
    finally
      GSoftAssertMode := False;
      GSoftAssertErrors := nil;
    end;

    // Report aggregated errors
    if Errors.Count > 0 then
    begin
       if Errors.Count = 1 then
         raise EAssertionFailed.Create(Errors[0]);
         
       ErrorMsg := Format('Multiple failures (%d):' + sLineBreak, [Errors.Count]);
       for I := 0 to Errors.Count - 1 do
         ErrorMsg := ErrorMsg + Format('  %d) %s' + sLineBreak, [I + 1, Errors[I]]);
         
       raise EAssertionFailed.Create(ErrorMsg);
    end;
  finally
    // Errors is ARC
  end;
end;

/// <summary>
///   Normalizes a JSON string for comparison: strips insignificant whitespace
///   (spaces, tabs, CR, LF between tokens) while preserving whitespace inside
///   quoted strings. This makes snapshots resilient to formatting changes and
///   pretty-print differences.
/// </summary>
function NormalizeJsonWhitespace(const S: string): string;
var
  SB: TStringBuilder;
  InString, Escaped: Boolean;
  I: Integer;
  C: Char;
begin
  SB := TStringBuilder.Create(Length(S));
  try
    InString := False;
    Escaped := False;
    for I := 1 to Length(S) do
    begin
      C := S[I];
      if Escaped then
      begin
        SB.Append(C);
        Escaped := False;
        Continue;
      end;
      if C = '\' then
      begin
        Escaped := InString; // Only treat as escape inside strings
        SB.Append(C);
        Continue;
      end;
      if C = '"' then
      begin
        InString := not InString;
        SB.Append(C);
        Continue;
      end;
      if InString then
        SB.Append(C)
      else if not C.IsWhiteSpace then
        SB.Append(C);
      // Outside strings, skip all whitespace
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

/// <summary>
///   Checks if a string looks like a JSON document (starts with { or [).
/// </summary>
function LooksLikeJson(const S: string): Boolean;
var
  Trimmed: string;
begin
  Trimmed := TrimLeft(S);
  Result := (Trimmed <> '') and ((Trimmed[1] = '{') or (Trimmed[1] = '['));
end;

function AreJsonNodesEqual(const Node1, Node2: IDextJsonNode): Boolean;
var
  I: Integer;
  Key: string;
  Arr1, Arr2: IDextJsonArray;
  Obj1, Obj2: IDextJsonObject;
begin
  if (Node1 = nil) or (Node2 = nil) then
  begin
    Result := Node1 = Node2;
    Exit;
  end;

  if Node1.NodeType <> Node2.NodeType then
  begin
    Result := False;
    Exit;
  end;

  case Node1.NodeType of
    jntNull: Result := True;
    jntString: Result := Node1.AsString = Node2.AsString;
    jntNumber: Result := Node1.AsDouble = Node2.AsDouble;
    jntBoolean: Result := Node1.AsBoolean = Node2.AsBoolean;
    jntArray:
      begin
        Arr1 := IDextJsonArray(Node1);
        Arr2 := IDextJsonArray(Node2);
        if Arr1.Count <> Arr2.Count then
        begin
          Result := False;
          Exit;
        end;
        for I := 0 to Arr1.Count - 1 do
          if not AreJsonNodesEqual(Arr1.GetNode(I), Arr2.GetNode(I)) then
          begin
            Result := False;
            Exit;
          end;
        Result := True;
      end;
    jntObject:
      begin
        Obj1 := IDextJsonObject(Node1);
        Obj2 := IDextJsonObject(Node2);
        if Obj1.Count <> Obj2.Count then
        begin
          Result := False;
          Exit;
        end;
        for I := 0 to Obj1.Count - 1 do
        begin
          Key := Obj1.GetName(I);
          if not Obj2.Contains(Key) then
          begin
            Result := False;
            Exit;
          end;
          if not AreJsonNodesEqual(Obj1.GetNode(Key), Obj2.GetNode(Key)) then
          begin
            Result := False;
            Exit;
          end;
        end;
        Result := True;
      end;
  else
    Result := False;
  end;
end;

function AreJsonEqual(const Json1, Json2: string): Boolean;
var
  Node1, Node2: IDextJsonNode;
begin
  try
    Node1 := TDextJson.Provider.Parse(Json1);
    Node2 := TDextJson.Provider.Parse(Json2);
    Result := AreJsonNodesEqual(Node1, Node2);
  except
    Result := False;
  end;
end;

procedure VerifySnapshot(const Content, SnapshotName: string);
var
  SnapshotPath: string;
  VerifyPath: string;
  ExistingContent: string;
  BaseDir: string;
  IsMatch: Boolean;
  NormalizedContent, NormalizedExisting: string;
begin
  if SnapshotName = '' then
    raise Exception.Create('Snapshot name cannot be empty');

  // Directory: .\Snapshots relative to EXE
  BaseDir := System.IOUtils.TPath.Combine(ExtractFilePath(ParamStr(0)), 'Snapshots');
  if not System.IOUtils.TDirectory.Exists(BaseDir) then
    System.IOUtils.TDirectory.CreateDirectory(BaseDir);

  SnapshotPath := System.IOUtils.TPath.Combine(BaseDir, SnapshotName + '.json');
  VerifyPath := System.IOUtils.TPath.Combine(BaseDir, SnapshotName + '.received.json');

  // UPDATE SNAPSHOT mode (env var or missing file)
  if (GetEnvironmentVariable('SNAPSHOT_UPDATE') = '1') or (not System.IOUtils.TFile.Exists(SnapshotPath)) then
  begin
    System.IOUtils.TFile.WriteAllText(SnapshotPath, Content);
    // Delete received file if exists
    if System.IOUtils.TFile.Exists(VerifyPath) then
      System.IOUtils.TFile.Delete(VerifyPath);
    Exit;
  end;

  // Compare
  ExistingContent := System.IOUtils.TFile.ReadAllText(SnapshotPath);

  // First try exact match (fast path)
  IsMatch := (Content = ExistingContent);

  // If not exact, try smart comparison for JSON-like content
  if (not IsMatch) and LooksLikeJson(Content) and LooksLikeJson(ExistingContent) then
  begin
    // Normalize: strip insignificant whitespace (formatting differences)
    // AND check for structural equality (order independent)
    IsMatch := AreJsonEqual(Content, ExistingContent);
    // If structured compare failed or not possible, fallback to whitespace normalization
    if not IsMatch then
    begin
      NormalizedContent := NormalizeJsonWhitespace(Content);
      NormalizedExisting := NormalizeJsonWhitespace(ExistingContent);
      IsMatch := (NormalizedContent = NormalizedExisting);
    end;
  end;

  if not IsMatch then
  begin
    // Write received
    System.IOUtils.TFile.WriteAllText(VerifyPath, Content);
    Assert.RegisterFailure(Format(
      'Snapshot mismatch for "%s"!' + sLineBreak +
      'Expected location: %s' + sLineBreak +
      'Received mismatch saved at: %s',
      [SnapshotName, SnapshotPath, VerifyPath]), '');
  end
  else
  begin
    // Cleanup previous failures
    if System.IOUtils.TFile.Exists(VerifyPath) then
      System.IOUtils.TFile.Delete(VerifyPath);
  end;
end;

function EscapeJsonString(const S: string): string;
begin
  Result := S.Replace('\', '\\', [rfReplaceAll])
             .Replace('"', '\"', [rfReplaceAll])
             .Replace(#13, '\r', [rfReplaceAll])
             .Replace(#10, '\n', [rfReplaceAll])
             .Replace(#9, '\t', [rfReplaceAll]);
end;

{ ShouldString }

constructor ShouldString.Create(const Value: string);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldString.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldString.Be(const Expected: string): ShouldString;
begin
  if FValue <> Expected then
    Fail(Format('Expected "%s" but was "%s"', [Expected, FValue]));
  Result := Self;
end;

function ShouldString.BeEquivalentTo(const Expected: string): ShouldString;
begin
  if not SameText(FValue, Expected) then
    Fail(Format('Expected "%s" (case insensitive) but was "%s"', [Expected, FValue]));
  Result := Self;
end;

function ShouldString.BeEmpty: ShouldString;
begin
  if FValue <> '' then
    Fail(Format('Expected empty string but was "%s"', [FValue]));
  Result := Self;
end;

function ShouldString.NotBeEmpty: ShouldString;
begin
  if FValue = '' then
    Fail('Expected non-empty string but was empty');
  Result := Self;
end;

function ShouldString.Contain(const Substring: string): ShouldString;
begin
  if not FValue.Contains(Substring) then
    Fail(Format('Expected "%s" to contain "%s"', [FValue, Substring]));
  Result := Self;
end;

function ShouldString.NotContain(const Substring: string): ShouldString;
begin
  if FValue.Contains(Substring) then
    Fail(Format('Expected "%s" to not contain "%s"', [FValue, Substring]));
  Result := Self;
end;

function ShouldString.StartWith(const Prefix: string): ShouldString;
begin
  if not FValue.StartsWith(Prefix) then
    Fail(Format('Expected "%s" to start with "%s"', [FValue, Prefix]));
  Result := Self;
end;

function ShouldString.EndWith(const Suffix: string): ShouldString;
begin
  if not FValue.EndsWith(Suffix) then
    Fail(Format('Expected "%s" to end with "%s"', [FValue, Suffix]));
  Result := Self;
end;

function ShouldString.MatchSnapshot(const SnapshotName: string): ShouldString;
begin
  VerifySnapshot(FValue, SnapshotName);
  Result := Self;
end;

function ShouldString.HaveLength(Expected: Integer): ShouldString;
begin
  if Length(FValue) <> Expected then
    Fail(Format('Expected length %d but was %d', [Expected, Length(FValue)]));
  Result := Self;
end;

function ShouldString.Because(const Reason: string): ShouldString;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldString.NotBe(const Unexpected: string): ShouldString;
begin
  if FValue = Unexpected then
    Fail(Format('Did not expect "%s"', [FValue]));
  Result := Self;
end;

function ShouldString.HaveLengthGreaterThan(Expected: Integer): ShouldString;
begin
  if Length(FValue) <= Expected then
    Fail(Format('Expected length greater than %d but was %d', [Expected, Length(FValue)]));
  Result := Self;
end;

function ShouldString.HaveLengthLessThan(Expected: Integer): ShouldString;
begin
  if Length(FValue) >= Expected then
    Fail(Format('Expected length less than %d but was %d', [Expected, Length(FValue)]));
  Result := Self;
end;

function ShouldString.MatchRegex(const Pattern: string): ShouldString;
begin
  if not TRegEx.IsMatch(FValue, Pattern) then
    Fail(Format('Expected "%s" to match pattern "%s"', [FValue, Pattern]));
  Result := Self;
end;

function ShouldString.BeUpperCase: ShouldString;
begin
  if FValue <> FValue.ToUpper then
    Fail(Format('Expected "%s" to be uppercase', [FValue]));
  Result := Self;
end;

function ShouldString.BeLowerCase: ShouldString;
begin
  if FValue <> FValue.ToLower then
    Fail(Format('Expected "%s" to be lowercase', [FValue]));
  Result := Self;
end;

function ShouldString.BeOneOf(const Values: TArray<string>): ShouldString;
var
  S: string;
  Found: Boolean;
begin
  Found := False;
  for S in Values do
    if FValue = S then
    begin
      Found := True;
      Break;
    end;
  if not Found then
    Fail(Format('Expected "%s" to be one of [%s]', [FValue, string.Join(', ', Values)]));
  Result := Self;
end;

function ShouldString.Satisfy(const Predicate: TPredicate<string>): ShouldString;
begin
  if not Predicate(FValue) then
    Fail(Format('Value "%s" did not satisfy the predicate', [FValue]));
  Result := Self;
end;

function ShouldString.&And: ShouldString;
begin
  Result := Self;
end;

{ ShouldInteger }

constructor ShouldInteger.Create(Value: Integer);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldInteger.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldInteger.Be(Expected: Integer): ShouldInteger;
begin
  if FValue <> Expected then
    Fail(Format('Expected %d but was %d', [Expected, FValue]));
  Result := Self;
end;

function ShouldInteger.NotBe(Unexpected: Integer): ShouldInteger;
begin
  if FValue = Unexpected then
    Fail(Format('Did not expect %d', [FValue]));
  Result := Self;
end;

function ShouldInteger.BeGreaterThan(Expected: Integer): ShouldInteger;
begin
  if FValue <= Expected then
    Fail(Format('Expected %d to be greater than %d', [FValue, Expected]));
  Result := Self;
end;

function ShouldInteger.BeGreaterOrEqualTo(Expected: Integer): ShouldInteger;
begin
  if FValue < Expected then
    Fail(Format('Expected %d to be greater than or equal to %d', [FValue, Expected]));
  Result := Self;
end;

function ShouldInteger.BeLessThan(Expected: Integer): ShouldInteger;
begin
  if FValue >= Expected then
    Fail(Format('Expected %d to be less than %d', [FValue, Expected]));
  Result := Self;
end;

function ShouldInteger.BeLessOrEqualTo(Expected: Integer): ShouldInteger;
begin
  if FValue > Expected then
    Fail(Format('Expected %d to be less than or equal to %d', [FValue, Expected]));
  Result := Self;
end;

function ShouldInteger.BeInRange(Min, Max: Integer): ShouldInteger;
begin
  if (FValue < Min) or (FValue > Max) then
    Fail(Format('Expected %d to be in range [%d, %d]', [FValue, Min, Max]));
  Result := Self;
end;

function ShouldInteger.BePositive: ShouldInteger;
begin
  if FValue <= 0 then
    Fail(Format('Expected positive value but was %d', [FValue]));
  Result := Self;
end;

function ShouldInteger.BeNegative: ShouldInteger;
begin
  if FValue >= 0 then
    Fail(Format('Expected negative value but was %d', [FValue]));
  Result := Self;
end;

function ShouldInteger.BeZero: ShouldInteger;
begin
  if FValue <> 0 then
    Fail(Format('Expected zero but was %d', [FValue]));
  Result := Self;
end;

function ShouldInteger.Because(const Reason: string): ShouldInteger;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldInteger.BeOneOf(const Values: TArray<Integer>): ShouldInteger;
var
  V: Integer;
  Found: Boolean;
begin
  Found := False;
  for V in Values do
    if FValue = V then
    begin
      Found := True;
      Break;
    end;
  if not Found then
    Fail(Format('Expected %d to be one of the specified values', [FValue]));
  Result := Self;
end;

function ShouldInteger.Satisfy(const Predicate: TPredicate<Integer>): ShouldInteger;
begin
  if not Predicate(FValue) then
    Fail(Format('Value %d did not satisfy the predicate', [FValue]));
  Result := Self;
end;

function ShouldInteger.&And: ShouldInteger;
begin
  Result := Self;
end;

{ ShouldBoolean }

constructor ShouldBoolean.Create(Value: Boolean);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldBoolean.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldBoolean.BeTrue: ShouldBoolean;
begin
  if not FValue then
    Fail('Expected True but was False');
  Result := Self;
end;

function ShouldBoolean.BeFalse: ShouldBoolean;
begin
  if FValue then
    Fail('Expected False but was True');
  Result := Self;
end;

function ShouldBoolean.Be(Expected: Boolean): ShouldBoolean;
begin
  if FValue <> Expected then
    Fail(Format('Expected %s but was %s', [BoolToStr(Expected, True), BoolToStr(FValue, True)]));
  Result := Self;
end;

function ShouldBoolean.Because(const Reason: string): ShouldBoolean;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldBoolean.NotBe(Unexpected: Boolean): ShouldBoolean;
begin
  if FValue = Unexpected then
    Fail(Format('Did not expect %s', [BoolToStr(FValue, True)]));
  Result := Self;
end;

function ShouldBoolean.&And: ShouldBoolean;
begin
  Result := Self;
end;

{ ShouldAction }

constructor ShouldAction.Create(const Action: TProc);
begin
  FAction := Action;
  FReason := '';
  FExceptionClass := nil;
  FExceptionMessage := '';
end;

procedure ShouldAction.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldAction.Throw<E>: ShouldAction;
begin
  Result := Throw(ExceptClass(E));
end;

function ShouldAction.Throw(AExceptionClass: ExceptClass): ShouldAction;
var
  ThrewException: Boolean;
  ActualClassName: string;
  ActualMessage: string;
  Ex: Exception;
begin
  ThrewException := False;
  ActualClassName := '';
  ActualMessage := '';
  FExceptionClass := nil;
  FExceptionMessage := '';

  try
    FAction();
  except
    on E: Exception do
    begin
      Ex := E;
      ThrewException := True;
      ActualClassName := Ex.ClassName;
      ActualMessage := Ex.Message;
      FExceptionClass := ExceptClass(Ex.ClassType);
      FExceptionMessage := Ex.Message;

      if (AExceptionClass <> nil) and (not Ex.InheritsFrom(AExceptionClass)) then
        Fail(Format('Expected exception %s but %s was thrown: %s',
          [AExceptionClass.ClassName, ActualClassName, ActualMessage]));
    end;
  end;

  if not ThrewException then
  begin
    if AExceptionClass = nil then
      Fail('Expected an exception but none was thrown')
    else
      Fail(Format('Expected exception %s but none was thrown', [AExceptionClass.ClassName]));
  end;

  Result := Self;
end;

function ShouldAction.ThrowWithMessage(const ExpectedMessage: string): ShouldAction;
begin
  if FExceptionMessage <> ExpectedMessage then
    Fail(Format('Expected exception message "%s" but was "%s"',
      [ExpectedMessage, FExceptionMessage]));
  Result := Self;
end;

function ShouldAction.ThrowWithMessageContaining(const Substring: string): ShouldAction;
begin
  if not FExceptionMessage.Contains(Substring) then
    Fail(Format('Expected exception message to contain "%s" but was "%s"',
      [Substring, FExceptionMessage]));
  Result := Self;
end;

function ShouldAction.NotThrow: ShouldAction;
begin
  try
    FAction();
  except
    on E: Exception do
      Fail(Format('Expected no exception but got %s: %s', [E.ClassName, E.Message]));
  end;
  Result := Self;
end;

function ShouldAction.Because(const Reason: string): ShouldAction;
begin
  Result := Self;
  Result.FReason := Reason;
end;

{ ShouldDouble }

constructor ShouldDouble.Create(Value: Double);
begin
  FValue := Value;
  FReason := '';
  FPrecision := 0.0001; // Default precision
end;

procedure ShouldDouble.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldDouble.Be(Expected: Double): ShouldDouble;
begin
  if Abs(FValue - Expected) > FPrecision then
    Fail(Format('Expected %g but was %g', [Expected, FValue]));
  Result := Self;
end;

function ShouldDouble.BeApproximately(Expected, Tolerance: Double): ShouldDouble;
begin
  if Abs(FValue - Expected) > Tolerance then
    Fail(Format('Expected %g to be approximately %g (tolerance: %g)', [FValue, Expected, Tolerance]));
  Result := Self;
end;

function ShouldDouble.BeGreaterThan(Expected: Double): ShouldDouble;
begin
  if FValue <= Expected then
    Fail(Format('Expected %g to be greater than %g', [FValue, Expected]));
  Result := Self;
end;

function ShouldDouble.BeLessThan(Expected: Double): ShouldDouble;
begin
  if FValue >= Expected then
    Fail(Format('Expected %g to be less than %g', [FValue, Expected]));
  Result := Self;
end;

function ShouldDouble.BeInRange(Min, Max: Double): ShouldDouble;
begin
  if (FValue < Min) or (FValue > Max) then
    Fail(Format('Expected %g to be in range [%g, %g]', [FValue, Min, Max]));
  Result := Self;
end;

function ShouldDouble.BePositive: ShouldDouble;
begin
  if FValue <= 0 then
    Fail(Format('Expected positive value but was %g', [FValue]));
  Result := Self;
end;

function ShouldDouble.BeNegative: ShouldDouble;
begin
  if FValue >= 0 then
    Fail(Format('Expected negative value but was %g', [FValue]));
  Result := Self;
end;

function ShouldDouble.Because(const Reason: string): ShouldDouble;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldDouble.NotBe(Unexpected: Double): ShouldDouble;
begin
  if Abs(FValue - Unexpected) <= FPrecision then
    Fail(Format('Did not expect %g', [FValue]));
  Result := Self;
end;

function ShouldDouble.BeZero: ShouldDouble;
begin
  if Abs(FValue) > FPrecision then
    Fail(Format('Expected zero but was %g', [FValue]));
  Result := Self;
end;

function ShouldDouble.Satisfy(const Predicate: TPredicate<Double>): ShouldDouble;
begin
  if not Predicate(FValue) then
    Fail(Format('Value %g did not satisfy the predicate', [FValue]));
  Result := Self;
end;

function ShouldDouble.&And: ShouldDouble;
begin
  Result := Self;
end;

{ ShouldObject }

constructor ShouldObject.Create(Value: TObject);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldObject.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldObject.BeNil: ShouldObject;
begin
  if FValue <> nil then
    Fail(Format('Expected nil but was %s', [FValue.ClassName]));
  Result := Self;
end;

function ShouldObject.NotBeNil: ShouldObject;
begin
  if FValue = nil then
    Fail('Expected a value but was nil');
  Result := Self;
end;

function ShouldObject.BeOfType<T>: ShouldObject;
begin
  if FValue = nil then
    Fail(Format('Expected %s but was nil', [T.ClassName]))
  else if not (FValue is T) then
    Fail(Format('Expected %s but was %s', [T.ClassName, FValue.ClassName]));
  Result := Self;
end;

function ShouldObject.BeAssignableTo<T>: ShouldObject;
begin
  if FValue = nil then
    Fail(Format('Expected assignable to %s but was nil', [T.ClassName]))
  else if not (FValue is T) then
    Fail(Format('Expected assignable to %s but was %s', [T.ClassName, FValue.ClassName]));
  Result := Self;
end;

function ShouldObject.BeEquivalentTo(Expected: TObject): ShouldObject;
var
  JsonA, JsonB: string;
begin
  if FValue = Expected then Exit(Self);
  
  if (FValue = nil) and (Expected <> nil) then
    Fail('Expected object to be equivalent but found nil')
  else if (FValue <> nil) and (Expected = nil) then
    Fail('Expected object to be nil but found instance');
    
  // Serialize both to JSON for deep comparison
  JsonA := TDextJson.Serialize(FValue);
  JsonB := TDextJson.Serialize(Expected);
  
  if JsonA <> JsonB then
    Fail('Expected objects to be equivalent but found differences.' + sLineBreak +
         'Expected: ' + JsonB + sLineBreak +
         'Found:    ' + JsonA);
         
  Result := Self;
end;

function ShouldObject.MatchSnapshot(const SnapshotName: string): ShouldObject;
begin
  if FValue = nil then
    VerifySnapshot('null', SnapshotName)
  else
    VerifySnapshot(TDextJson.Serialize(FValue), SnapshotName);
  Result := Self;
end;

function ShouldObject.Because(const Reason: string): ShouldObject;
begin
  FReason := Reason;
  Result := Self;
end;

function ShouldObject.BeNull: ShouldObject;
begin
  Result := BeNil; // Alias
end;

function ShouldObject.NotBeNull: ShouldObject;
begin
  Result := NotBeNil; // Alias
end;

function ShouldObject.Satisfy(const Predicate: TPredicate<TObject>): ShouldObject;
begin
  if not Predicate(FValue) then
    Fail('Object did not satisfy the predicate');
  Result := Self;
end;

function ShouldObject.&And: ShouldObject;
begin
  Result := Self;
end;

{ ShouldObjectHelper }

function ShouldObjectHelper.HaveProperty(const PropertyName: string): ShouldProperty;
begin
  Result := ShouldObjectMembers.HaveProperty(Self, PropertyName);
end;

function ShouldObjectHelper.HavePropertyValue(const PropertyName: string; const ExpectedValue: TValue): ShouldObject;
begin
  Result := ShouldObjectMembers.HavePropertyValue(Self, PropertyName, ExpectedValue);
end;

function ShouldObjectHelper.HaveValue(const PropertyMetadata: StringType; const ExpectedValue: string): ShouldObject;
begin
  Result := ShouldObjectMembers.HaveValue(Self, PropertyMetadata, ExpectedValue);
end;

function ShouldObjectHelper.HaveValue(const PropertyMetadata: IntType; ExpectedValue: Integer): ShouldObject;
begin
  Result := ShouldObjectMembers.HaveValue(Self, PropertyMetadata, ExpectedValue);
end;

function ShouldObjectHelper.HaveValue<T>(const PropertyMetadata: T; ExpectedValue: T): ShouldObject;
begin
  Result := ShouldObjectMembers.HaveValue<T>(Self, PropertyMetadata, ExpectedValue);
end;

{ ShouldObjectMembers }

class function ShouldObjectMembers.HaveProperty(const Subject: ShouldObject; const PropertyName: string): ShouldProperty;
var
  RttiType: TRttiType;
  Prop: TRttiProperty;
  Val: TValue;
begin
  if Subject.FValue = nil then
  begin
    Subject.Fail(Format('Cannot check property "%s" on nil object', [PropertyName]));
    Exit(ShouldProperty.Create(Subject, PropertyName, TValue.Empty));
  end;
    
  RttiType := TReflection.Context.GetType(Subject.FValue.ClassType);
  Prop := RttiType.GetProperty(PropertyName);
  if Prop = nil then
  begin
    Subject.Fail(Format('Object of type %s does not have property "%s"', [Subject.FValue.ClassName, PropertyName]));
    Exit(ShouldProperty.Create(Subject, PropertyName, TValue.Empty));
  end;

  Val := Prop.GetValue(Subject.FValue);
  Result := ShouldProperty.Create(Subject, PropertyName, Val);
end;

(*
function ShouldObjectHelper.HaveProperty<T>(const PropertyMetadata: Prop<T>): ShouldProperty;
begin
  if not PropertyMetadata.IsQueryMode then
    Self.Fail('HaveProperty<T> requires a Smart Property prototype (e.g. u.Name), not a value.');
    
  Result := HaveProperty(PropertyMetadata.Name);
end;
*)

class function ShouldObjectMembers.HavePropertyValue(const Subject: ShouldObject; const PropertyName: string;
  const ExpectedValue: TValue): ShouldObject;
var
  RttiType: TRttiType;
  Prop: TRttiProperty;
  Field: TRttiField;
  ActualValue: TValue;
  ActualStr, ExpectedStr: string;
  RecType: TRttiRecordType;
  ValueField: TRttiField;
begin
  Result := Subject;
  if Subject.FValue = nil then
  begin
    Subject.Fail(Format('Cannot check property "%s" on nil object', [PropertyName]));
    Exit;
  end;
    
  RttiType := TReflection.Context.GetType(Subject.FValue.ClassType);
  
  // Try property first
  Prop := RttiType.GetProperty(PropertyName);
  if Prop <> nil then
  begin
    ActualValue := Prop.GetValue(Subject.FValue);
  end
  else
  begin
    // Try field with F prefix (for SmartTypes like FName, FAge)
    Field := RttiType.GetField('F' + PropertyName);
    if Field = nil then
      Field := RttiType.GetField(PropertyName); // Try without prefix
      
    if Field = nil then
    begin
      Subject.Fail(Format('Object of type %s does not have property or field "%s"', 
        [Subject.FValue.ClassName, PropertyName]));
      Exit;
    end;
        
    ActualValue := Field.GetValue(Subject.FValue);
    
    // If it's a Prop<T> Smart Type, extract the inner FValue
    if (ActualValue.Kind = tkRecord) and string(ActualValue.TypeInfo.Name).StartsWith('Prop<') then
    begin
      RecType := TReflection.Context.GetType(ActualValue.TypeInfo).AsRecord;
      ValueField := RecType.GetField('FValue');
      if ValueField <> nil then
        ActualValue := ValueField.GetValue(ActualValue.GetReferenceToRawData);
    end;
  end;
  
  // Compare values using extracted strings
  ActualStr := ActualValue.ToString;
  ExpectedStr := ExpectedValue.ToString;
  
  if ActualStr <> ExpectedStr then
    Subject.Fail(Format('Property "%s" expected value "%s" but was "%s"', 
      [PropertyName, ExpectedStr, ActualStr]));
end;

class function ShouldObjectMembers.HaveValue(const Subject: ShouldObject; const PropertyMetadata: StringType;
  const ExpectedValue: string): ShouldObject;
begin
  if not PropertyMetadata.IsQueryMode then
    Subject.Fail('HaveValue requires a Smart Property prototype (use Prototype.Entity<T>).');

  Result := HavePropertyValue(Subject, PropertyMetadata.Name, TValue.From<string>(ExpectedValue));
end;

class function ShouldObjectMembers.HaveValue(const Subject: ShouldObject; const PropertyMetadata: IntType;
  ExpectedValue: Integer): ShouldObject;
begin
  if not PropertyMetadata.IsQueryMode then
    Subject.Fail('HaveValue requires a Smart Property prototype (use Prototype.Entity<T>).');

  Result := HavePropertyValue(Subject, PropertyMetadata.Name, TValue.From<Integer>(ExpectedValue));
end;

class function ShouldObjectMembers.HaveValue<T>(const Subject: ShouldObject; const PropertyMetadata: T;
  ExpectedValue: T): ShouldObject;
var
  RecType: TRttiRecordType;
  InfoField: TRttiField;
  MetaValue, InfoValue: TValue;
  PropInfo: IPropInfo;
  PropName: string;
begin
  // Use RTTI to extract property name from any Prop<T> SmartType
  MetaValue := TValue.From<T>(PropertyMetadata);
  
  // Verify it's a Prop<T> record
  Result := Subject;
  if not string(MetaValue.TypeInfo.Name).StartsWith('Prop<') then
  begin
    Subject.Fail('HaveValue<T> requires a Smart Property type (Prop<T>).');
    Exit;
  end;
  
  RecType := TReflection.Context.GetType(MetaValue.TypeInfo).AsRecord;
  InfoField := RecType.GetField('FInfo');
  
  if InfoField = nil then
  begin
    Subject.Fail('HaveValue<T>: Could not find FInfo field in SmartType.');
    Exit;
  end;
  
  InfoValue := InfoField.GetValue(MetaValue.GetReferenceToRawData);
  
  if InfoValue.IsEmpty or (InfoValue.AsInterface = nil) then
  begin
    Subject.Fail('HaveValue<T> requires a Smart Property prototype (use Prototype.Entity<T>).');
    Exit;
  end;
  
  PropInfo := InfoValue.AsType<IPropInfo>;
  PropName := PropInfo.PropertyName;
  
  Result := HavePropertyValue(Subject, PropName, TValue.From<T>(ExpectedValue));
end;

{ ShouldProperty }

constructor ShouldProperty.Create(const Parent: ShouldObject; const Name: string; const Value: TValue);
begin
  FParent := Parent;
  FName := Name;
  FValue := Value;
  FReason := '';
end;

procedure ShouldProperty.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldProperty.Value: TValue;
begin
  Result := FValue;
end;

function ShouldProperty.WhichString: ShouldString;
begin
  Result := ShouldString.Create(FValue.ToString);
end;

function ShouldProperty.WhichInteger: ShouldInteger;
begin
  try
    if FValue.TypeInfo = TypeInfo(Integer) then
      Result := ShouldInteger.Create(FValue.AsInteger)
    else
      Result := ShouldInteger.Create(StrToIntDef(FValue.ToString, 0)); // Simple conversion
  except
    Fail(Format('Property "%s" is not a valid Integer', [FName]));
  end;
end;

function ShouldProperty.WhichBoolean: ShouldBoolean;
begin
  try
    if FValue.TypeInfo = TypeInfo(Boolean) then
      Result := ShouldBoolean.Create(FValue.AsBoolean)
    else
      Result := ShouldBoolean.Create(StrToBoolDef(FValue.ToString, False));
  except
    Fail(Format('Property "%s" is not a valid Boolean', [FName]));
  end;
end;

function ShouldProperty.WhichObject: ShouldObject;
begin
  if FValue.IsEmpty then
    Exit(ShouldObject.Create(nil));
    
  if FValue.Kind = tkClass then
    Result := ShouldObject.Create(FValue.AsObject)
  else
    Fail(Format('Property "%s" is not an object', [FName]));
end;

function ShouldProperty.WhichGuid: ShouldGuid;
var
  G: TGUID;
begin
  if FValue.TypeInfo = TypeInfo(TGUID) then
  begin
    FValue.ExtractRawData(@G);
    Result := ShouldGuid.Create(G);
  end
  else
  begin
    try
      Result := ShouldGuid.Create(StringToGUID(FValue.ToString));
    except
      Fail('Property is not a GUID');
    end;
  end;
end;

function ShouldProperty.&And: ShouldObject;
begin
  Result := FParent;
end;

function ShouldProperty.AndAlso: ShouldObject;
begin
  Result := FParent;
end;

{ ShouldInterface }

constructor ShouldInterface.Create(const Value: IInterface);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldInterface.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldInterface.BeNil: ShouldInterface;
begin
  if FValue <> nil then
    Fail('Expected nil interface but was not nil');
  Result := Self;
end;

function ShouldInterface.NotBeNil: ShouldInterface;
begin
  if FValue = nil then
    Fail('Expected non-nil interface but was nil');
  Result := Self;
end;

function ShouldInterface.BeEquivalentTo(const Expected: IInterface): ShouldInterface;
var
  JsonA, JsonB: string;
begin
  if FValue = Expected then Exit(Self);
  
  if (FValue = nil) and (Expected <> nil) then
    Fail('Expected interface to be equivalent but found nil')
  else if (FValue <> nil) and (Expected = nil) then
    Fail('Expected interface to be nil but found instance');
    
  JsonA := TDextJson.Serialize(TValue.From(FValue));
  JsonB := TDextJson.Serialize(TValue.From(Expected));
  
  if JsonA <> JsonB then
    Fail('Expected interfaces to be equivalent but found differences.' + sLineBreak +
         'Expected: ' + JsonB + sLineBreak +
         'Found:    ' + JsonA);
         
  Result := Self;
end;

function ShouldInterface.MatchSnapshot(const SnapshotName: string): ShouldInterface;
begin
  if FValue = nil then
    VerifySnapshot('null', SnapshotName)
  else
    VerifySnapshot(TDextJson.Serialize(TValue.From(FValue)), SnapshotName);
  Result := Self;
end;

function ShouldInterface.Because(const Reason: string): ShouldInterface;
begin
  FReason := Reason;
  Result := Self;
end;

{ ShouldList<T> }

constructor ShouldList<T>.Create(const Value: System.IEnumerable<T>);
var
  LEnumRTL: System.IEnumerator<T>;
begin
  FItems := [];
  if Value <> nil then
  begin
    LEnumRTL := Value.GetEnumerator;
    while LEnumRTL.MoveNext do
    begin
      SetLength(FItems, Length(FItems) + 1);
      FItems[High(FItems)] := LEnumRTL.Current;
    end;
  end;
  FReason := '';
end;

constructor ShouldList<T>.Create(const Value: Dext.Collections.Base.IEnumerable<T>);
var
  LEnumDext: Dext.Collections.Base.IEnumerator<T>;
begin
  FItems := [];
  if Value <> nil then
  begin
    LEnumDext := Value.GetEnumerator;
    while LEnumDext.MoveNext do
    begin
      SetLength(FItems, Length(FItems) + 1);
      FItems[High(FItems)] := LEnumDext.Current;
    end;
  end;
  FReason := '';
end;

constructor ShouldList<T>.Create(const Value: TArray<T>);
begin
  FItems := Value;
  FReason := '';
end;

procedure ShouldList<T>.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldList<T>.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function ShouldList<T>.BeEmpty: ShouldList<T>;
var
  C: Integer;
begin
  C := GetCount;
  if C > 0 then
    Fail(Format('Expected empty list but found %d items', [C]));
  Result := Self;
end;

function ShouldList<T>.NotBeEmpty: ShouldList<T>;
begin
  if GetCount = 0 then
    Fail('Expected non-empty list but was empty');
  Result := Self;
end;

function ShouldList<T>.HaveCount(Expected: Integer): ShouldList<T>;
var
  C: Integer;
begin
  C := GetCount;
  if C <> Expected then
    Fail(Format('Expected count %d but was %d', [Expected, C]));
  Result := Self;
end;

function ShouldList<T>.HaveCountGreaterThan(Expected: Integer): ShouldList<T>;
var
  C: Integer;
begin
  C := GetCount;
  if C <= Expected then
    Fail(Format('Expected count greater than %d but was %d', [Expected, C]));
  Result := Self;
end;

function ShouldList<T>.Contain(const Item: T): ShouldList<T>;
var
  Found: Boolean;
  Comparer: System.Generics.Defaults.IEqualityComparer<T>;
  LItem: T;
begin
  Found := False;
  Comparer := System.Generics.Defaults.TEqualityComparer<T>.Default;
  
  for LItem in FItems do
    if Comparer.Equals(LItem, Item) then
    begin
      Found := True;
      Break;
    end;
  
  if not Found then
    Fail('Expected list to contain item but it did not');
  Result := Self;
end;

function ShouldList<T>.NotContain(const Item: T): ShouldList<T>;
var
  Found: Boolean;
  Comparer: System.Generics.Defaults.IEqualityComparer<T>;
  LItem: T;
begin
  Found := False;
  Comparer := System.Generics.Defaults.TEqualityComparer<T>.Default;
  
  for LItem in FItems do
    if Comparer.Equals(LItem, Item) then
    begin
      Found := True;
      Break;
    end;
  
  if Found then
    Fail('Expected list to NOT contain item but it did');
  Result := Self;
end;

function ShouldList<T>.AllSatisfy(const Predicate: TFunc<T, Boolean>): ShouldList<T>;
var
  AllMatch: Boolean;
  LItem: T;
begin
  AllMatch := True;
  
  for LItem in FItems do
    if not Predicate(LItem) then
    begin
      AllMatch := False;
      Break;
    end;
  
  if not AllMatch then
    Fail('Expected all items to satisfy predicate but some did not');
  Result := Self;
end;

function ShouldList<T>.AnySatisfy(const Predicate: TFunc<T, Boolean>): ShouldList<T>;
var
  AnyMatch: Boolean;
  LItem: T;
begin
  AnyMatch := False;
  
  for LItem in FItems do
    if Predicate(LItem) then
    begin
      AnyMatch := True;
      Break;
    end;
  
  if not AnyMatch then
    Fail('Expected at least one item to satisfy predicate but none did');
  Result := Self;
end;

function ShouldList<T>.Because(const Reason: string): ShouldList<T>;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldList<T>.HaveCountLessThan(Expected: Integer): ShouldList<T>;
var
  C: Integer;
begin
  C := GetCount;
  if C >= Expected then
    Fail(Format('Expected count less than %d but was %d', [Expected, C]));
  Result := Self;
end;

function ShouldList<T>.ContainInOrder(const Items: TArray<T>): ShouldList<T>;
var
  Comparer: System.Generics.Defaults.IEqualityComparer<T>;
  I, J: Integer;
begin
  Comparer := System.Generics.Defaults.TEqualityComparer<T>.Default;
  
  J := 0;
  for I := 0 to High(FItems) do
  begin
    if (J <= High(Items)) and Comparer.Equals(FItems[I], Items[J]) then
      Inc(J);
  end;
  
  if J <> Length(Items) then
    Fail('Expected list to contain items in specified order');
  Result := Self;
end;

function ShouldList<T>.BeEquivalentTo(const Expected: TArray<T>): ShouldList<T>;
var
  Comparer: System.Generics.Defaults.IEqualityComparer<T>;
  ExpItem: T;
  Found: Boolean;
  I: Integer;
  Used: TArray<Boolean>;
begin
  Comparer := System.Generics.Defaults.TEqualityComparer<T>.Default;
  
  if Length(FItems) <> Length(Expected) then
    Fail(Format('Expected %d items but found %d', [Length(Expected), Length(FItems)]));
    
  SetLength(Used, Length(FItems));
  for I := 0 to High(Used) do Used[I] := False;

  // Check all expected items are in actual (order-independent)
  for ExpItem in Expected do
  begin
    Found := False;
    for I := 0 to High(FItems) do
    begin
      if (not Used[I]) and Comparer.Equals(FItems[I], ExpItem) then
      begin
        Used[I] := True;
        Found := True;
        Break;
      end;
    end;
    
    if not Found then
      Fail('Expected list to be equivalent but found differences');
  end;
  
  Result := Self;
end;

function ShouldList<T>.OnlyContain(const Predicate: TFunc<T, Boolean>): ShouldList<T>;
begin
  Result := AllSatisfy(Predicate); // Alias with different semantic meaning
end;

function ShouldList<T>.BeEquivalentTo(const Expected: System.IEnumerable<T>): ShouldList<T>;
var
  Arr: TArray<T>;
  LEnumRTL: System.IEnumerator<T>;
begin
  if Expected = nil then
    Exit(BeEquivalentTo(TArray<T>(nil)));

  Arr := [];
  LEnumRTL := Expected.GetEnumerator;
  while LEnumRTL.MoveNext do
  begin
    SetLength(Arr, Length(Arr) + 1);
    Arr[High(Arr)] := LEnumRTL.Current;
  end;
  Result := BeEquivalentTo(Arr);
end;

function ShouldList<T>.BeEquivalentTo(const Expected: Dext.Collections.Base.IEnumerable<T>): ShouldList<T>;
var
  Arr: TArray<T>;
  LEnumDext: Dext.Collections.Base.IEnumerator<T>;
begin
  if Expected = nil then
    Exit(BeEquivalentTo(TArray<T>(nil)));

  Arr := [];
  LEnumDext := Expected.GetEnumerator;
  while LEnumDext.MoveNext do
  begin
    SetLength(Arr, Length(Arr) + 1);
    Arr[High(Arr)] := LEnumDext.Current;
  end;
  Result := BeEquivalentTo(Arr);
end;

function ShouldList<T>.&And: ShouldList<T>;
begin
  Result := Self;
end;

function ShouldList<T>.AndAlso: ShouldList<T>;
begin
  Result := Self;
end;

{ ShouldDateTime }

constructor ShouldDateTime.Create(Value: TDateTime);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldDateTime.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldDateTime.Be(Expected: TDateTime): ShouldDateTime;
begin
  if not SameDateTime(FValue, Expected) then
    Fail(Format('Expected %s but found %s', [DateTimeToStr(Expected), DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeCloseTo(Expected: TDateTime; PrecisionMS: Int64): ShouldDateTime;
var
  Diff: Int64;
begin
  Diff := MilliSecondsBetween(FValue, Expected);
  if Diff > PrecisionMS then
    Fail(Format('Expected date to be close to %s (within %dms) but found %s (diff %dms)',
      [DateTimeToStr(Expected), PrecisionMS, DateTimeToStr(FValue), Diff]));
  Result := Self;
end;

function ShouldDateTime.BeAfter(Expected: TDateTime): ShouldDateTime;
begin
  if not (FValue > Expected) then
    Fail(Format('Expected date to be after %s but found %s', [DateTimeToStr(Expected), DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeBefore(Expected: TDateTime): ShouldDateTime;
begin
  if not (FValue < Expected) then
    Fail(Format('Expected date to be before %s but found %s', [DateTimeToStr(Expected), DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeSameDateAs(Expected: TDateTime): ShouldDateTime;
begin
  if not SameDate(FValue, Expected) then
    Fail(Format('Expected date to be %s but found %s (ignoring time)',
      [DateToStr(Expected), DateToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeToday: ShouldDateTime;
begin
  if not SameDate(FValue, Now) then
    Fail(Format('Expected today (%s) but found %s', [DateToStr(Now), DateToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.NotBe(Unexpected: TDateTime): ShouldDateTime;
begin
  if SameDateTime(FValue, Unexpected) then
    Fail(Format('Expected date to differ from %s', [DateTimeToStr(Unexpected)]));
  Result := Self;
end;

function ShouldDateTime.BeApproximately(Expected: TDateTime; Tolerance: Double): ShouldDateTime;
begin
  if Abs(FValue - Expected) > Tolerance then
    Fail(Format('Expected %s ± %g days but found %s',
      [DateTimeToStr(Expected), Tolerance, DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeGreaterThan(Expected: TDateTime): ShouldDateTime;
begin
  if not (FValue > Expected) then
    Fail(Format('Expected date to be after %s but found %s', [DateTimeToStr(Expected), DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeLessThan(Expected: TDateTime): ShouldDateTime;
begin
  if not (FValue < Expected) then
    Fail(Format('Expected date to be before %s but found %s', [DateTimeToStr(Expected), DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeInRange(Min, Max: TDateTime): ShouldDateTime;
begin
  if (FValue < Min) or (FValue > Max) then
    Fail(Format('Expected date between %s and %s but found %s',
      [DateTimeToStr(Min), DateTimeToStr(Max), DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BePositive: ShouldDateTime;
begin
  if not (FValue > 0) then
    Fail(Format('Expected a date after 30/12/1899 but found %s', [DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeNegative: ShouldDateTime;
begin
  if not (FValue < 0) then
    Fail(Format('Expected a date before 30/12/1899 but found %s', [DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.BeZero: ShouldDateTime;
begin
  if FValue <> 0 then
    Fail(Format('Expected an empty date (0) but found %s', [DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.Satisfy(const Predicate: TPredicate<TDateTime>): ShouldDateTime;
begin
  if not Predicate(FValue) then
    Fail(Format('Expected %s to satisfy the predicate', [DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.Satisfy(const Predicate: TPredicate<Double>): ShouldDateTime;
begin
  if not Predicate(FValue) then
    Fail(Format('Expected %s to satisfy the predicate', [DateTimeToStr(FValue)]));
  Result := Self;
end;

function ShouldDateTime.Because(const Reason: string): ShouldDateTime;
begin
  FReason := Reason;
  Result := Self;
end;

function ShouldDateTime.&And: ShouldDateTime;
begin
  Result := Self;
end;

function ShouldDateTime.AndAlso: ShouldDateTime;
begin
  Result := Self;
end;


{ Global Helper Functions }


function Should(const Value: string): ShouldString; overload;
begin
  Result := ShouldString.Create(Value);
end;

function Should(Value: Integer): ShouldInteger; overload;
begin
  Result := ShouldInteger.Create(Value);
end;

function Should(Value: Int64): ShouldInt64; overload;
begin
  Result := ShouldInt64.Create(Value);
end;

function Should(Value: Boolean): ShouldBoolean; overload;
begin
  Result := ShouldBoolean.Create(Value);
end;

function Should(Value: Double): ShouldDouble; overload;
begin
  Result := ShouldDouble.Create(Value);
end;

function Should(Value: Single): ShouldDouble; overload;
begin
  Result := ShouldDouble.Create(Value);
end;

function Should(Value: Extended): ShouldDouble; overload;
begin
  Result := ShouldDouble.Create(Value);
end;

function Should(Value: Currency): ShouldDouble; overload;
begin
  Result := ShouldDouble.Create(Value);
end;

function Should(Value: TDateTime): ShouldDateTime; overload;
begin
  Result := ShouldDateTime.Create(Value);
end;

function Should(Value: TDate): ShouldDateTime; overload;
begin
  Result := ShouldDateTime.Create(Value);
end;

function Should(Value: TTime): ShouldDateTime; overload;
begin
  Result := ShouldDateTime.Create(Value);
end;

function Should(const Action: TProc): ShouldAction; overload;
begin
  Result := ShouldAction.Create(Action);
end;

function Should(const Value: TObject): ShouldObject; overload;
begin
  Result := ShouldObject.Create(Value);
end;

function Should(const Value: IInterface): ShouldInterface; overload;
begin
  Result := ShouldInterface.Create(Value);
end;

function Should(const Value: TGUID): ShouldGuid; overload;
begin
  Result := ShouldGuid.Create(Value);
end;

function Should(const Value: TUUID): ShouldUUID; overload;
begin
  Result := ShouldUUID.Create(Value);
end;

function Should(const Value: Variant): ShouldVariant; overload;
begin
  Result := ShouldVariant.Create(Value);
end;



function ShouldDate(Value: TDateTime): ShouldDateTime; overload;
begin
  Result := ShouldDateTime.Create(Value);
end;

{ Smart Types / Prop<T> Implementations }

function Should(const Value: StringType): ShouldString; overload;
begin
  Result := ShouldString.Create(Value.Value);
end;

function Should(const Value: IntType): ShouldInteger; overload;
begin
  Result := ShouldInteger.Create(Value.Value);
end;

function Should(const Value: Int64Type): ShouldInt64; overload;
begin
  Result := ShouldInt64.Create(Value.Value);
end;

function Should(const Value: BoolType): ShouldBoolean; overload;
begin
  Result := ShouldBoolean.Create(Value.Value);
end;

function Should(const Value: FloatType): ShouldDouble; overload;
begin
  Result := ShouldDouble.Create(Value.Value);
end;

function Should(const Value: CurrencyType): ShouldDouble; overload;
begin
  Result := ShouldDouble.Create(Value.Value);
end;

{ Nullable<T> Implementations }

function Should(const Value: Nullable<string>): ShouldString; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<string> to have a value, but it was Null');
  Result := ShouldString.Create(Value.Value);
end;

function Should(const Value: Nullable<Integer>): ShouldInteger; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<Integer> to have a value, but it was Null');
  Result := ShouldInteger.Create(Value.Value);
end;

function Should(const Value: Nullable<Int64>): ShouldInt64; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<Int64> to have a value, but it was Null');
  Result := ShouldInt64.Create(Value.Value);
end;

function Should(const Value: Nullable<Boolean>): ShouldBoolean; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<Boolean> to have a value, but it was Null');
  Result := ShouldBoolean.Create(Value.Value);
end;

function Should(const Value: Nullable<Double>): ShouldDouble; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<Double> to have a value, but it was Null');
  Result := ShouldDouble.Create(Value.Value);
end;

function Should(const Value: Nullable<Currency>): ShouldDouble; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<Currency> to have a value, but it was Null');
  Result := ShouldDouble.Create(Value.Value);
end;

function ShouldDate(const Value: Nullable<TDateTime>): ShouldDateTime; overload;
begin
  if not Value.HasValue then
    Assert.Fail('Expected Nullable<TDateTime> to have a value, but it was Null');
  Result := ShouldDateTime.Create(Value.Value);
end;

function ShouldDate(const Value: Prop<TDateTime>): ShouldDateTime; overload;
begin
  Result := ShouldDateTime.Create(Value.Value);
end;

{ ShouldInt64 }

constructor ShouldInt64.Create(Value: Int64);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldInt64.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldInt64.Be(Expected: Int64): ShouldInt64;
begin
  if FValue <> Expected then
    Fail(Format('Expected %d but was %d', [Expected, FValue]));
  Result := Self;
end;

function ShouldInt64.NotBe(Unexpected: Int64): ShouldInt64;
begin
  if FValue = Unexpected then
    Fail(Format('Did not expect %d', [FValue]));
  Result := Self;
end;

function ShouldInt64.BeGreaterThan(Expected: Int64): ShouldInt64;
begin
  if FValue <= Expected then
    Fail(Format('Expected %d to be greater than %d', [FValue, Expected]));
  Result := Self;
end;

function ShouldInt64.BeLessThan(Expected: Int64): ShouldInt64;
begin
  if FValue >= Expected then
    Fail(Format('Expected %d to be less than %d', [FValue, Expected]));
  Result := Self;
end;

function ShouldInt64.BeInRange(Min, Max: Int64): ShouldInt64;
begin
  if (FValue < Min) or (FValue > Max) then
    Fail(Format('Expected %d to be in range [%d, %d]', [FValue, Min, Max]));
  Result := Self;
end;

function ShouldInt64.BePositive: ShouldInt64;
begin
  if FValue <= 0 then
    Fail(Format('Expected positive value but was %d', [FValue]));
  Result := Self;
end;

function ShouldInt64.BeNegative: ShouldInt64;
begin
  if FValue >= 0 then
    Fail(Format('Expected negative value but was %d', [FValue]));
  Result := Self;
end;

function ShouldInt64.BeZero: ShouldInt64;
begin
  if FValue <> 0 then
    Fail(Format('Expected zero but was %d', [FValue]));
  Result := Self;
end;

function ShouldInt64.BeOneOf(const Values: TArray<Int64>): ShouldInt64;
var
  V: Int64;
  Found: Boolean;
begin
  Found := False;
  for V in Values do
    if FValue = V then
    begin
      Found := True;
      Break;
    end;
  if not Found then
    Fail(Format('Expected %d to be one of the specified values', [FValue]));
  Result := Self;
end;

function ShouldInt64.Satisfy(const Predicate: TPredicate<Int64>): ShouldInt64;
begin
  if not Predicate(FValue) then
    Fail(Format('Value %d did not satisfy the predicate', [FValue]));
  Result := Self;
end;

function ShouldInt64.Because(const Reason: string): ShouldInt64;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldInt64.&And: ShouldInt64;
begin
  Result := Self;
end;

{ ShouldGuid }

constructor ShouldGuid.Create(const Value: TGUID);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldGuid.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldGuid.Be(const Expected: TGUID): ShouldGuid;
begin
  if not IsEqualGUID(FValue, Expected) then
    Fail(Format('Expected %s but was %s', [GUIDToString(Expected), GUIDToString(FValue)]));
  Result := Self;
end;

function ShouldGuid.NotBe(const Unexpected: TGUID): ShouldGuid;
begin
  if IsEqualGUID(FValue, Unexpected) then
    Fail(Format('Did not expect %s', [GUIDToString(FValue)]));
  Result := Self;
end;

function ShouldGuid.BeEmpty: ShouldGuid;
begin
  if not IsEqualGUID(FValue, TGUID.Empty) then
    Fail(Format('Expected empty GUID but was %s', [GUIDToString(FValue)]));
  Result := Self;
end;

function ShouldGuid.NotBeEmpty: ShouldGuid;
begin
  if IsEqualGUID(FValue, TGUID.Empty) then
    Fail('Expected non-empty GUID but was empty');
  Result := Self;
end;

function ShouldGuid.Because(const Reason: string): ShouldGuid;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldGuid.&And: ShouldGuid;
begin
  Result := Self;
end;

{ ShouldUUID }

constructor ShouldUUID.Create(const Value: TUUID);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldUUID.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldUUID.Be(const Expected: TUUID): ShouldUUID;
begin
  if FValue <> Expected then
    Fail(Format('Expected %s but was %s', [Expected.ToString, FValue.ToString]));
  Result := Self;
end;

function ShouldUUID.NotBe(const Unexpected: TUUID): ShouldUUID;
begin
  if FValue = Unexpected then
    Fail(Format('Did not expect %s', [FValue.ToString]));
  Result := Self;
end;

function ShouldUUID.BeEmpty: ShouldUUID;
begin
  if not FValue.IsEmpty then
    Fail(Format('Expected empty UUID but was %s', [FValue.ToString]));
  Result := Self;
end;

function ShouldUUID.NotBeEmpty: ShouldUUID;
begin
  if FValue.IsEmpty then
    Fail('Expected non-empty UUID but was empty');
  Result := Self;
end;

function ShouldUUID.Because(const Reason: string): ShouldUUID;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldUUID.&And: ShouldUUID;
begin
  Result := Self;
end;

{ ShouldVariant }

constructor ShouldVariant.Create(const Value: Variant);
begin
  FValue := Value;
  FReason := '';
end;

procedure ShouldVariant.Fail(const Message: string);
begin
  Assert.RegisterFailure(Message, FReason);
end;

function ShouldVariant.Be(const Expected: Variant): ShouldVariant;
begin
  if FValue <> Expected then
    Fail(Format('Expected %s but was %s', [VarToStr(Expected), VarToStr(FValue)]));
  Result := Self;
end;

function ShouldVariant.NotBe(const Unexpected: Variant): ShouldVariant;
begin
  if FValue = Unexpected then
    Fail(Format('Did not expect %s', [VarToStr(FValue)]));
  Result := Self;
end;

function ShouldVariant.BeNull: ShouldVariant;
begin
  if not VarIsNull(FValue) then
    Fail(Format('Expected Null but was %s', [VarToStr(FValue)]));
  Result := Self;
end;

function ShouldVariant.NotBeNull: ShouldVariant;
begin
  if VarIsNull(FValue) then
    Fail('Expected non-Null variant but was Null');
  Result := Self;
end;

function ShouldVariant.BeEmpty: ShouldVariant;
begin
  if not VarIsEmpty(FValue) then
    Fail(Format('Expected Empty but was %s', [VarToStr(FValue)]));
  Result := Self;
end;

function ShouldVariant.NotBeEmpty: ShouldVariant;
begin
  if VarIsEmpty(FValue) then
    Fail('Expected non-Empty variant but was Empty');
  Result := Self;
end;

function ShouldVariant.BeOfType(VarType: TVarType): ShouldVariant;
var
  ActualType: TVarType;
begin
  ActualType := System.Variants.VarType(FValue);
  if ActualType <> VarType then
    Fail(Format('Expected variant type %d but was %d', [VarType, ActualType]));
  Result := Self;
end;

function ShouldVariant.Because(const Reason: string): ShouldVariant;
begin
  Result := Self;
  Result.FReason := Reason;
end;

function ShouldVariant.&And: ShouldVariant;
begin
  Result := Self;
end;

function ShouldVariant.AndAlso: ShouldVariant;
begin
  Result := Self;
end;

// Implementations for AndAlso for other types (appended here to keep unit clean)



function ShouldString.AndAlso: ShouldString;
begin
  Result := Self;
end;



function ShouldInteger.AndAlso: ShouldInteger;
begin
  Result := Self;
end;



function ShouldInt64.AndAlso: ShouldInt64;
begin
  Result := Self;
end;



function ShouldDouble.AndAlso: ShouldDouble;
begin
  Result := Self;
end;



function ShouldBoolean.AndAlso: ShouldBoolean;
begin
  Result := Self;
end;



function ShouldGuid.AndAlso: ShouldGuid;
begin
  Result := Self;
end;



function ShouldUUID.AndAlso: ShouldUUID;
begin
  Result := Self;
end;





function ShouldAction.&And: ShouldAction;
begin
  Result := Self;
end;

function ShouldAction.AndAlso: ShouldAction;
begin
  Result := Self;
end;



function ShouldObject.AndAlso: ShouldObject;
begin
  Result := Self;
end;


function ShouldInterface.&And: ShouldInterface;
begin
  Result := Self;
end;

function ShouldInterface.AndAlso: ShouldInterface;
begin
  Result := Self;
end;

{ ShouldHelper }

function ShouldHelper.List<T>(const Value: TArray<T>): ShouldList<T>;
begin
  Result := ShouldList<T>.Create(Value);
end;

function ShouldHelper.List<T>(const Value: System.IEnumerable<T>): ShouldList<T>;
begin
  Result := ShouldList<T>.Create(Value);
end;

function ShouldHelper.List<T>(const Value: Dext.Collections.Base.IEnumerable<T>): ShouldList<T>;
begin
  Result := ShouldList<T>.Create(Value);
end;

function Should: ShouldHelper; overload;
begin
end;

end.
