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
{  Created: 2026-01-04                                                      }
{                                                                           }
{  Dext.Testing.Attributes - Attribute-Based Test Framework                 }
{                                                                           }
{  Provides MSTest/xUnit/NUnit-inspired attributes for defining tests       }
{  without requiring base class inheritance.                                }
{                                                                           }
{  Features:                                                                }
{    - [TestFixture] marks any class as a test container                    }
{    - [Test] marks methods as executable tests                             }
{    - [Setup]/[TearDown] for per-test lifecycle                            }
{    - [BeforeAll]/[AfterAll] for per-class lifecycle                       }
{    - [TestCase] for inline parameterized tests                            }
{    - [TestCaseSource] for external data providers                         }
{    - [Ignore] for skipping tests                                          }
{    - [Category] for grouping and filtering tests                          }
{                                                                           }
{***************************************************************************}

unit Dext.Testing.Attributes;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo;

type
  // =========================================================================
  // Test Container Attributes
  // =========================================================================

  /// <summary>
  ///   Marks a class as a test fixture (test container).
  ///   Classes with this attribute will be discovered by the test runner.
  /// </summary>
  TestFixtureAttribute = class(TCustomAttribute)
  private
    FDescription: string;
  public
    constructor Create; overload;
    constructor Create(const ADescription: string); overload;
    property Description: string read FDescription;
  end;

  FixtureAttribute = TestFixtureAttribute;

  /// <summary>
  ///   Alias for TestFixture (MSTest naming convention).
  /// </summary>
  TestClassAttribute = class(TestFixtureAttribute);

  // =========================================================================
  // Test Method Attributes
  // =========================================================================

  /// <summary>
  ///   Marks a method as an executable test.
  /// </summary>
  TestAttribute = class(TCustomAttribute)
  private
    FDescription: string;
  public
    constructor Create; overload;
    constructor Create(const ADescription: string); overload;
    property Description: string read FDescription;
  end;

  /// <summary>
  ///   Alias for Test (xUnit naming convention).
  /// </summary>
  FactAttribute = class(TestAttribute);

  // =========================================================================
  // Lifecycle Attributes
  // =========================================================================

  /// <summary>
  ///   Method runs before EACH test in the fixture.
  /// </summary>
  SetupAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Method runs after EACH test in the fixture.
  /// </summary>
  TearDownAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Method runs ONCE before all tests in the fixture.
  ///   Must be a class method (static).
  /// </summary>
  BeforeAllAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Alias for BeforeAll (MSTest naming convention).
  /// </summary>
  ClassInitializeAttribute = class(BeforeAllAttribute);

  /// <summary>
  ///   Method runs ONCE after all tests in the fixture.
  ///   Must be a class method (static).
  /// </summary>
  AfterAllAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Alias for AfterAll (MSTest naming convention).
  /// </summary>
  ClassCleanupAttribute = class(AfterAllAttribute);

  /// <summary>
  ///   Method runs ONCE before ALL fixtures in the assembly.
  ///   Must be a class method (static) in any [TestFixture] class.
  ///   Only one method per assembly should have this attribute.
  /// </summary>
  /// <example>
  ///   [TestFixture]
  ///   TGlobalSetup = class
  ///   public
  ///     [AssemblyInitialize]
  ///     class procedure GlobalSetup;
  ///   end;
  /// </example>
  AssemblyInitializeAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Alias for AssemblyInitialize (NUnit naming convention).
  /// </summary>
  OneTimeSetUpAttribute = class(AssemblyInitializeAttribute);

  /// <summary>
  ///   Method runs ONCE after ALL fixtures in the assembly complete.
  ///   Must be a class method (static) in any [TestFixture] class.
  ///   Only one method per assembly should have this attribute.
  /// </summary>
  AssemblyCleanupAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Alias for AssemblyCleanup (NUnit naming convention).
  /// </summary>
  OneTimeTearDownAttribute = class(AssemblyCleanupAttribute);

  // =========================================================================
  // Data-Driven Testing Attributes
  // =========================================================================

  /// <summary>
  ///   Provides inline test data for parameterized tests.
  ///   Multiple [TestCase] attributes can be applied to the same method.
  /// </summary>
  /// <example>
  ///   [TestCase(1, 2, 3)]      // Add(1, 2) should equal 3
  ///   [TestCase(0, 0, 0)]      // Add(0, 0) should equal 0
  ///   [TestCase(-1, 1, 0)]     // Add(-1, 1) should equal 0
  ///   procedure TestAdd(A, B, Expected: Integer);
  /// </example>
  TestCaseAttribute = class(TCustomAttribute)
  private
    FValues: TArray<TValue>;
    FDisplayName: string;
  public
    constructor Create(const AValues: array of const); overload;
    constructor Create(const ADisplayName: string; const AValues: array of const); overload;
    // Overloads for common types (1-6 parameters)
    constructor Create(V1: Integer); overload;
    constructor Create(V1, V2: Integer); overload;
    constructor Create(V1, V2, V3: Integer); overload;
    constructor Create(V1, V2, V3, V4: Integer); overload;
    constructor Create(V1, V2, V3, V4, V5: Integer); overload;
    constructor Create(V1, V2, V3, V4, V5, V6: Integer); overload;
    constructor Create(const V1: string); overload;
    constructor Create(const V1, V2: string); overload;
    constructor Create(const V1, V2, V3: string); overload;
    constructor Create(V1: Boolean); overload;
    constructor Create(V1, V2: Boolean); overload;
    constructor Create(V1: Double); overload;
    constructor Create(V1, V2: Double); overload;
    constructor Create(V1, V2, V3: Double); overload;
    property Values: TArray<TValue> read FValues;
    property DisplayName: string read FDisplayName;
  end;

  /// <summary>
  ///   Specifies a method or class that provides test case data.
  /// </summary>
  /// <example>
  ///   [TestCaseSource('GetTestData')]
  ///   procedure TestWithDynamicData(Value: Integer; Expected: string);
  ///
  ///   class function GetTestData: TArray<TArray<TValue>>; static;
  /// </example>
  TestCaseSourceAttribute = class(TCustomAttribute)
  private
    FSourceMethodName: string;
    FSourceType: TClass;
  public
    constructor Create(const AMethodName: string); overload;
    constructor Create(ASourceType: TClass; const AMethodName: string); overload;
    property SourceMethodName: string read FSourceMethodName;
    property SourceType: TClass read FSourceType;
  end;

  // =========================================================================
  // Execution Control Attributes
  // =========================================================================

  /// <summary>
  ///   Marks a test to be skipped with an optional reason.
  /// </summary>
  IgnoreAttribute = class(TCustomAttribute)
  private
    FReason: string;
  public
    constructor Create; overload;
    constructor Create(const AReason: string); overload;
    property Reason: string read FReason;
  end;

  /// <summary>
  ///   Alias for Ignore (xUnit naming convention).
  /// </summary>
  SkipAttribute = class(IgnoreAttribute);

  /// <summary>
  ///   Sets a timeout for test execution in milliseconds.
  ///   The test fails if it exceeds this limit.
  /// </summary>
  TimeoutAttribute = class(TCustomAttribute)
  private
    FMilliseconds: Integer;
  public
    constructor Create(AMilliseconds: Integer);
    property Milliseconds: Integer read FMilliseconds;
  end;

  /// <summary>
  ///   Runs the test multiple times (useful for detecting flaky tests).
  /// </summary>
  RepeatAttribute = class(TCustomAttribute)
  private
    FCount: Integer;
  public
    constructor Create(ACount: Integer);
    property Count: Integer read FCount;
  end;

  /// <summary>
  ///   Alias for Repeat. Repeat is a Pascal reserved word, so the
  ///   .NET spelling needs an ampersand. RepeatTest is the name you
  ///   write in Delphi, and it is the same attribute. DUnitX already
  ///   calls it RepeatTest.
  /// </summary>
  RepeatTestAttribute = class(RepeatAttribute);

  /// <summary>
  ///   Sets a maximum expected execution time.
  ///   Test passes but emits a warning if exceeded.
  /// </summary>
  MaxTimeAttribute = class(TCustomAttribute)
  private
    FMilliseconds: Integer;
  public
    constructor Create(AMilliseconds: Integer);
    property Milliseconds: Integer read FMilliseconds;
  end;

  /// <summary>
  ///   Test is only run when explicitly requested, not in "Run All".
  /// </summary>
  ExplicitAttribute = class(TCustomAttribute)
  private
    FReason: string;
  public
    constructor Create; overload;
    constructor Create(const AReason: string); overload;
    property Reason: string read FReason;
  end;

  // =========================================================================
  // Categorization Attributes
  // =========================================================================

  /// <summary>
  ///   Assigns a category/tag to tests for filtering.
  /// </summary>
  /// <example>
  ///   [Category('Integration')]
  ///   [Category('Database')]
  ///   procedure TestDatabaseConnection;
  /// </example>
  CategoryAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Alias for Category (xUnit naming convention).
  /// </summary>
  TraitAttribute = class(TCustomAttribute)
  private
    FName: string;
    FValue: string;
  public
    constructor Create(const AName, AValue: string);
    property Name: string read FName;
    property Value: string read FValue;
  end;

  /// <summary>
  ///   Adds a rich description for test reports.
  /// </summary>
  DescriptionAttribute = class(TCustomAttribute)
  private
    FText: string;
  public
    constructor Create(const AText: string);
    property Text: string read FText;
  end;

  /// <summary>
  ///   Sets test execution priority (lower = runs first).
  /// </summary>
  PriorityAttribute = class(TCustomAttribute)
  private
    FPriority: Integer;
  public
    constructor Create(APriority: Integer);
    property Priority: Integer read FPriority;
  end;

  /// <summary>
  ///   Limits test execution to specific platforms.
  /// </summary>
  PlatformAttribute = class(TCustomAttribute)
  private
    FPlatforms: string;
  public
    constructor Create(const APlatforms: string);
    property Platforms: string read FPlatforms;
    function ShouldRun: Boolean;
  end;

  // =========================================================================
  // Parameter Generation Attributes (NUnit-inspired)
  // =========================================================================

  /// <summary>
  ///   Generates combinatorial test cases from discrete values.
  /// </summary>
  ValuesAttribute = class(TCustomAttribute)
  private
    FValues: TArray<TValue>;
  public
    constructor Create(const AValues: array of const); overload;
    constructor Create(V1, V2: Integer); overload;
    constructor Create(V1, V2, V3: Integer); overload;
    constructor Create(V1, V2, V3, V4: Integer); overload;
    constructor Create(const V1, V2: string); overload;
    constructor Create(const V1, V2, V3: string); overload;
    property Values: TArray<TValue> read FValues;
  end;

  /// <summary>
  ///   Generates numeric range for combinatorial testing.
  /// </summary>
  RangeAttribute = class(TCustomAttribute)
  private
    FStart: Integer;
    FStop: Integer;
    FStep: Integer;
  public
    constructor Create(AStart, AStop: Integer; AStep: Integer = 1);
    property Start: Integer read FStart;
    property Stop: Integer read FStop;
    property Step: Integer read FStep;
    function GetValues: TArray<Integer>;
  end;

  /// <summary>
  ///   Generates random values for fuzz testing.
  /// </summary>
  RandomAttribute = class(TCustomAttribute)
  private
    FMin: Integer;
    FMax: Integer;
    FCount: Integer;
  public
    constructor Create(AMin, AMax, ACount: Integer);
    property Min: Integer read FMin;
    property Max: Integer read FMax;
    property Count: Integer read FCount;
    function GetValues: TArray<Integer>;
  end;

  /// <summary>
  ///   Marks a test as combinatorial (all parameter combinations).
  /// </summary>
  CombinatorialAttribute = class(TCustomAttribute);

implementation

{ TestFixtureAttribute }

constructor TestFixtureAttribute.Create;
begin
  inherited Create;
  FDescription := '';
end;

constructor TestFixtureAttribute.Create(const ADescription: string);
begin
  inherited Create;
  FDescription := ADescription;
end;

{ TestAttribute }

constructor TestAttribute.Create;
begin
  inherited Create;
  FDescription := '';
end;

constructor TestAttribute.Create(const ADescription: string);
begin
  inherited Create;
  FDescription := ADescription;
end;

{ TestCaseAttribute }

constructor TestCaseAttribute.Create(const AValues: array of const);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FValues, Length(AValues));
  for I := 0 to High(AValues) do
  begin
    case AValues[I].VType of
      vtInteger:
        FValues[I] := TValue.From<Integer>(AValues[I].VInteger);
      vtBoolean:
        FValues[I] := TValue.From<Boolean>(AValues[I].VBoolean);
      vtExtended:
        FValues[I] := TValue.From<Double>(AValues[I].VExtended^);
      vtString:
        FValues[I] := TValue.From<string>(string(AValues[I].VString^));
      vtAnsiString:
        FValues[I] := TValue.From<string>(string(AnsiString(AValues[I].VAnsiString)));
      vtWideString:
        FValues[I] := TValue.From<string>(string(WideString(AValues[I].VWideString)));
      vtUnicodeString:
        FValues[I] := TValue.From<string>(string(AValues[I].VUnicodeString));
      vtInt64:
        FValues[I] := TValue.From<Int64>(AValues[I].VInt64^);
      vtChar:
        FValues[I] := TValue.From<Char>(Char(AValues[I].VChar));
      vtWideChar:
        FValues[I] := TValue.From<Char>(AValues[I].VWideChar);
    else
      FValues[I] := TValue.Empty;
    end;
  end;
  FDisplayName := '';
end;

constructor TestCaseAttribute.Create(const ADisplayName: string;
  const AValues: array of const);
begin
  Create(AValues);
  FDisplayName := ADisplayName;
end;

constructor TestCaseAttribute.Create(V1: Integer);
begin
  Create([V1]);
end;

constructor TestCaseAttribute.Create(V1, V2: Integer);
begin
  Create([V1, V2]);
end;

constructor TestCaseAttribute.Create(V1, V2, V3: Integer);
begin
  Create([V1, V2, V3]);
end;

constructor TestCaseAttribute.Create(V1, V2, V3, V4: Integer);
begin
  Create([V1, V2, V3, V4]);
end;

constructor TestCaseAttribute.Create(V1, V2, V3, V4, V5: Integer);
begin
  Create([V1, V2, V3, V4, V5]);
end;

constructor TestCaseAttribute.Create(V1, V2, V3, V4, V5, V6: Integer);
begin
  Create([V1, V2, V3, V4, V5, V6]);
end;

constructor TestCaseAttribute.Create(const V1: string);
begin
  Create([V1]);
end;

constructor TestCaseAttribute.Create(const V1, V2: string);
begin
  Create([V1, V2]);
end;

constructor TestCaseAttribute.Create(const V1, V2, V3: string);
begin
  Create([V1, V2, V3]);
end;

constructor TestCaseAttribute.Create(V1: Boolean);
begin
  Create([V1]);
end;

constructor TestCaseAttribute.Create(V1, V2: Boolean);
begin
  Create([V1, V2]);
end;

constructor TestCaseAttribute.Create(V1: Double);
begin
  inherited Create;
  SetLength(FValues, 1);
  FValues[0] := TValue.From<Double>(V1);
  FDisplayName := '';
end;

constructor TestCaseAttribute.Create(V1, V2: Double);
begin
  inherited Create;
  SetLength(FValues, 2);
  FValues[0] := TValue.From<Double>(V1);
  FValues[1] := TValue.From<Double>(V2);
  FDisplayName := '';
end;

constructor TestCaseAttribute.Create(V1, V2, V3: Double);
begin
  inherited Create;
  SetLength(FValues, 3);
  FValues[0] := TValue.From<Double>(V1);
  FValues[1] := TValue.From<Double>(V2);
  FValues[2] := TValue.From<Double>(V3);
  FDisplayName := '';
end;

{ TestCaseSourceAttribute }

constructor TestCaseSourceAttribute.Create(const AMethodName: string);
begin
  inherited Create;
  FSourceMethodName := AMethodName;
  FSourceType := nil;
end;

constructor TestCaseSourceAttribute.Create(ASourceType: TClass; const AMethodName: string);
begin
  inherited Create;
  FSourceType := ASourceType;
  FSourceMethodName := AMethodName;
end;

{ IgnoreAttribute }

constructor IgnoreAttribute.Create;
begin
  inherited Create;
  FReason := '';
end;

constructor IgnoreAttribute.Create(const AReason: string);
begin
  inherited Create;
  FReason := AReason;
end;

{ TimeoutAttribute }

constructor TimeoutAttribute.Create(AMilliseconds: Integer);
begin
  inherited Create;
  FMilliseconds := AMilliseconds;
end;

{ RepeatAttribute }

constructor RepeatAttribute.Create(ACount: Integer);
begin
  inherited Create;
  FCount := ACount;
end;

{ MaxTimeAttribute }

constructor MaxTimeAttribute.Create(AMilliseconds: Integer);
begin
  inherited Create;
  FMilliseconds := AMilliseconds;
end;

{ ExplicitAttribute }

constructor ExplicitAttribute.Create;
begin
  inherited Create;
  FReason := '';
end;

constructor ExplicitAttribute.Create(const AReason: string);
begin
  inherited Create;
  FReason := AReason;
end;

{ CategoryAttribute }

constructor CategoryAttribute.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

{ TraitAttribute }

constructor TraitAttribute.Create(const AName, AValue: string);
begin
  inherited Create;
  FName := AName;
  FValue := AValue;
end;

{ DescriptionAttribute }

constructor DescriptionAttribute.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
end;

{ PriorityAttribute }

constructor PriorityAttribute.Create(APriority: Integer);
begin
  inherited Create;
  FPriority := APriority;
end;

{ PlatformAttribute }

constructor PlatformAttribute.Create(const APlatforms: string);
begin
  inherited Create;
  FPlatforms := APlatforms;
end;

function PlatformAttribute.ShouldRun: Boolean;
var
  Platforms: TArray<string>;
  P: string;
begin
  Platforms := FPlatforms.Split([',', ';', ' ']);
  for P in Platforms do
  begin
    {$IFDEF MSWINDOWS}
    if SameText(Trim(P), 'Windows') or SameText(Trim(P), 'Win32') or SameText(Trim(P), 'Win64') then
      Exit(True);
    {$ENDIF}
    {$IFDEF LINUX}
    if SameText(Trim(P), 'Linux') then
      Exit(True);
    {$ENDIF}
    {$IFDEF MACOS}
    if SameText(Trim(P), 'MacOS') or SameText(Trim(P), 'OSX') then
      Exit(True);
    {$ENDIF}
    {$IFDEF ANDROID}
    if SameText(Trim(P), 'Android') then
      Exit(True);
    {$ENDIF}
    {$IFDEF IOS}
    if SameText(Trim(P), 'iOS') then
      Exit(True);
    {$ENDIF}
  end;
  Result := False;
end;

{ ValuesAttribute }

constructor ValuesAttribute.Create(const AValues: array of const);
var
  I: Integer;
begin
  inherited Create;
  SetLength(FValues, Length(AValues));
  for I := 0 to High(AValues) do
  begin
    case AValues[I].VType of
      vtInteger:
        FValues[I] := TValue.From<Integer>(AValues[I].VInteger);
      vtBoolean:
        FValues[I] := TValue.From<Boolean>(AValues[I].VBoolean);
      vtExtended:
        FValues[I] := TValue.From<Double>(AValues[I].VExtended^);
      vtString:
        FValues[I] := TValue.From<string>(string(AValues[I].VString^));
      vtUnicodeString:
        FValues[I] := TValue.From<string>(string(AValues[I].VUnicodeString));
    else
      FValues[I] := TValue.Empty;
    end;
  end;
end;

constructor ValuesAttribute.Create(V1, V2: Integer);
begin
  Create([V1, V2]);
end;

constructor ValuesAttribute.Create(V1, V2, V3: Integer);
begin
  Create([V1, V2, V3]);
end;

constructor ValuesAttribute.Create(V1, V2, V3, V4: Integer);
begin
  Create([V1, V2, V3, V4]);
end;

constructor ValuesAttribute.Create(const V1, V2: string);
begin
  Create([V1, V2]);
end;

constructor ValuesAttribute.Create(const V1, V2, V3: string);
begin
  Create([V1, V2, V3]);
end;

{ RangeAttribute }

constructor RangeAttribute.Create(AStart, AStop: Integer; AStep: Integer);
begin
  inherited Create;
  FStart := AStart;
  FStop := AStop;
  FStep := AStep;
end;

function RangeAttribute.GetValues: TArray<Integer>;
var
  Count, I, V: Integer;
begin
  if FStep = 0 then
    FStep := 1;

  Count := ((FStop - FStart) div FStep) + 1;
  if Count < 0 then
    Count := 0;

  SetLength(Result, Count);
  V := FStart;
  for I := 0 to Count - 1 do
  begin
    Result[I] := V;
    Inc(V, FStep);
  end;
end;

{ RandomAttribute }

constructor RandomAttribute.Create(AMin, AMax, ACount: Integer);
begin
  inherited Create;
  FMin := AMin;
  FMax := AMax;
  FCount := ACount;
end;

function RandomAttribute.GetValues: TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, FCount);
  Randomize;
  for I := 0 to FCount - 1 do
    Result[I] := FMin + Random(FMax - FMin + 1);
end;

end.
