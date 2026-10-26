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
{  Dext.Mocks.Matching - Argument matchers inspired by Moq's It class.      }
{                                                                           }
{  Usage:                                                                   }
{    Mock.Setup.Returns(42).When.Add(Arg.Any<Integer>, Arg.Matches<Integer>(}
{      function(V: Integer): Boolean begin Result := V > 0 end));           }
{                                                                           }
{***************************************************************************}
unit Dext.Mocks.Matching;

interface

uses
  System.Rtti,
  System.SysUtils,
  Dext.Collections,
  Dext.Collections.Comparers,
  System.TypInfo,
  System.RegularExpressions;

type
  /// <summary>
  ///   An argument matcher captured by an Arg method, together with the type
  ///   it was declared for. The type lets the mock place the matcher on the
  ///   right parameter when matchers and literal values are mixed.
  /// </summary>
  TArgMatcher = record
    Predicate: TPredicate<TValue>;
    TypeInfo: PTypeInfo;
  end;

  /// <summary>
  ///   Storage for argument matchers.
  ///   Matchers registered via Arg methods are captured when a method is called
  ///   during setup, allowing the mock to later match actual call arguments.
  /// </summary>
  TMatcherFactory = class
  private class var
    FMatcherStack: IList<TArgMatcher>;
  public
    class constructor Create;
    class destructor Destroy;

    /// <summary>Adds a matcher to the stack and returns its index.</summary>
    class function AddMatcher(const Predicate: TPredicate<TValue>;
      ATypeInfo: PTypeInfo = nil): Integer;

    /// <summary>Gets and clears all matchers from the stack.</summary>
    class function GetMatchers: TArray<TPredicate<TValue>>;

    /// <summary>Gets and clears all matchers from the stack, with their declared types.</summary>
    class function GetMatcherEntries: TArray<TArgMatcher>;

    /// <summary>Clears the matcher stack.</summary>
    class procedure Clear;
  end;

  /// <summary>
  ///   Provides argument matchers for mock setups and verifications.
  ///   Inspired by Moq's It class and Spring4D's Arg.
  /// </summary>
  /// <remarks>
  ///   Note: In Delphi, 'Is' is a reserved keyword, so we use 'Matches' as the
  ///   primary method name. The escaped '&amp;Is' is available as an alias for
  ///   developers who prefer Moq-compatible syntax.
  /// </remarks>
  Arg = record
  private
    class function CreateDefaultValue<T>: T; static;
  public
    /// <summary>Matches any value of type T.</summary>
    class function Any<T>: T; static;

    /// <summary>Matches any value that satisfies the predicate.</summary>
    /// <remarks>Primary method - use this instead of 'Is' which is reserved in Delphi.</remarks>
    class function Matches<T>(const Predicate: TPredicate<T>): T; static;

    /// <summary>Matches any value that satisfies the predicate (Moq-compatible alias).</summary>
    /// <remarks>Alias for Matches - note: requires &amp; prefix due to Delphi reserved word.</remarks>
    class function &Is<T>(const Predicate: TPredicate<T>): T; static;

    /// <summary>Matches any value equal to the specified value.</summary>
    class function IsEqual<T>(const Value: T): T; static;

    /// <summary>Matches any value contained in the specified array.</summary>
    class function IsIn<T>(const Values: TArray<T>): T; static;

    /// <summary>Matches any value in the specified range (inclusive).</summary>
    class function IsInRange<T>(const Min, Max: T): T; static;

    /// <summary>Matches nil/null/empty values.</summary>
    class function IsNil<T>: T; static;

    /// <summary>Matches non-nil/non-null/non-empty values.</summary>
    class function IsNotNil<T>: T; static;

    /// <summary>Matches strings that match the regex pattern.</summary>
    class function IsRegex(const Pattern: string): string; static;

    /// <summary>Matches strings that contain the substring.</summary>
    class function Contains(const Substring: string): string; static;

    /// <summary>Matches strings that start with the prefix.</summary>
    class function StartsWith(const Prefix: string): string; static;

    /// <summary>Matches strings that end with the suffix.</summary>
    class function EndsWith(const Suffix: string): string; static;
  end;

implementation

{ TMatcherFactory }

class constructor TMatcherFactory.Create;
begin
  FMatcherStack := TCollections.CreateList<TArgMatcher>;
end;

class destructor TMatcherFactory.Destroy;
begin
  // ARC will free it
end;

class function TMatcherFactory.AddMatcher(const Predicate: TPredicate<TValue>;
  ATypeInfo: PTypeInfo): Integer;
var
  Entry: TArgMatcher;
begin
  Entry.Predicate := Predicate;
  Entry.TypeInfo := ATypeInfo;
  FMatcherStack.Add(Entry);
  Result := FMatcherStack.Count - 1;
end;

class function TMatcherFactory.GetMatchers: TArray<TPredicate<TValue>>;
var
  Entries: TArray<TArgMatcher>;
  I: Integer;
begin
  Entries := GetMatcherEntries;
  SetLength(Result, Length(Entries));
  for I := 0 to High(Entries) do
    Result[I] := Entries[I].Predicate;
end;

class function TMatcherFactory.GetMatcherEntries: TArray<TArgMatcher>;
begin
  Result := FMatcherStack.ToArray;
  FMatcherStack.Clear;
end;

class procedure TMatcherFactory.Clear;
begin
  FMatcherStack.Clear;
end;

{ Arg }

class function Arg.CreateDefaultValue<T>: T;
begin
  Result := Default(T);
end;

class function Arg.Any<T>: T;
begin
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    begin
      Result := True; // Match anything
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.Matches<T>(const Predicate: TPredicate<T>): T;
begin
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    var
      TypedValue: T;
    begin
      try
        TypedValue := V.AsType<T>;
        Result := Predicate(TypedValue);
      except
        Result := False;
      end;
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.&Is<T>(const Predicate: TPredicate<T>): T;
begin
  // Alias for Matches - delegates to the primary implementation
  Result := Matches<T>(Predicate);
end;


class function Arg.IsEqual<T>(const Value: T): T;
var
  Captured: T;
begin
  Captured := Value;
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    var
      TypedValue: T;
      Comparer: IEqualityComparer<T>;
    begin
      try
        TypedValue := V.AsType<T>;
        Comparer := TEqualityComparer<T>.Default;
        Result := Comparer.Equals(TypedValue, Captured);
      except
        Result := False;
      end;
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.IsIn<T>(const Values: TArray<T>): T;
var
  Captured: TArray<T>;
begin
  Captured := Copy(Values);
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    var
      TypedValue: T;
      Item: T;
      Comparer: IEqualityComparer<T>;
    begin
      try
        TypedValue := V.AsType<T>;
        Comparer := TEqualityComparer<T>.Default;
        for Item in Captured do
          if Comparer.Equals(TypedValue, Item) then
            Exit(True);
        Result := False;
      except
        Result := False;
      end;
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.IsInRange<T>(const Min, Max: T): T;
var
  CapturedMin, CapturedMax: T;
begin
  CapturedMin := Min;
  CapturedMax := Max;
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    var
      TypedValue: T;
      Comparer: IComparer<T>;
    begin
      try
        TypedValue := V.AsType<T>;
        Comparer := TComparer<T>.Default;
        Result := (Comparer.Compare(TypedValue, CapturedMin) >= 0) and
                  (Comparer.Compare(TypedValue, CapturedMax) <= 0);
      except
        Result := False;
      end;
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.IsNil<T>: T;
begin
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    begin
      Result := V.IsEmpty;
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.IsNotNil<T>: T;
begin
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    begin
      Result := not V.IsEmpty;
    end, TypeInfo(T));
  Result := CreateDefaultValue<T>;
end;

class function Arg.IsRegex(const Pattern: string): string;
var
  Captured: string;
begin
  Captured := Pattern;
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    var
      Regex: TRegEx;
    begin
      try
        Regex := TRegEx.Create(Captured);
        Result := Regex.IsMatch(V.AsString);
      except
        Result := False;
      end;
    end, TypeInfo(string));
  Result := '';
end;

class function Arg.Contains(const Substring: string): string;
var
  Captured: string;
begin
  Captured := Substring;
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    begin
      try
        Result := V.AsString.Contains(Captured);
      except
        Result := False;
      end;
    end, TypeInfo(string));
  Result := '';
end;

class function Arg.StartsWith(const Prefix: string): string;
var
  Captured: string;
begin
  Captured := Prefix;
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    begin
      try
        Result := V.AsString.StartsWith(Captured);
      except
        Result := False;
      end;
    end, TypeInfo(string));
  Result := '';
end;

class function Arg.EndsWith(const Suffix: string): string;
var
  Captured: string;
begin
  Captured := Suffix;
  TMatcherFactory.AddMatcher(
    function(V: TValue): Boolean
    begin
      try
        Result := V.AsString.EndsWith(Captured);
      except
        Result := False;
      end;
    end, TypeInfo(string));
  Result := '';
end;

end.
