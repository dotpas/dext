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
{  Created: 2026-01-07                                                      }
{                                                                           }
{  Dext.Testing - Wildcard unit for all testing features.                    }
{$I Dext.inc}

unit Dext.Testing;

interface

uses
  System.SysUtils,
  System.Rtti,
  Dext,
  // {BEGIN_DEXT_USES}
  // Generated Uses
  Dext.Assertions,
  Dext.Interception.ClassProxy,
  Dext.Interception,
  Dext.Interception.Proxy,
  Dext.Mocks.Auto,
  Dext.Mocks.Interceptor,
  Dext.Mocks.Matching,
  Dext.Mocks,
  Dext.Testing.Attributes,
  Dext.Testing.Console,
  //Dext.Testing.Dashboard,
  Dext.Testing.DI,
  Dext.Testing.Fluent,
  Dext.Testing.History,
  Dext.Testing.Report,
  Dext.Testing.Runner,
  Dext.Testing.Integration,

  Dext.Testing.Host,
  Dext.Testing.Coverage.Lcov
  // {END_DEXT_USES}
  ;

type
  // {BEGIN_DEXT_ALIASES}
  // Generated Aliases

  // Dext.Assertions
  EAssertionFailed = Dext.Assertions.EAssertionFailed;
  Assert = Dext.Assertions.Assert;
  ShouldDateTime = Dext.Assertions.ShouldDateTime;
  ShouldString = Dext.Assertions.ShouldString;
  ShouldInteger = Dext.Assertions.ShouldInteger;
  ShouldBoolean = Dext.Assertions.ShouldBoolean;
  ShouldAction = Dext.Assertions.ShouldAction;
  ShouldDouble = Dext.Assertions.ShouldDouble;
  ShouldInt64 = Dext.Assertions.ShouldInt64;
  ShouldGuid = Dext.Assertions.ShouldGuid;
  ShouldUUID = Dext.Assertions.ShouldUUID;
  ShouldVariant = Dext.Assertions.ShouldVariant;
  ShouldObject = Dext.Assertions.ShouldObject;
  ShouldProperty = Dext.Assertions.ShouldProperty;
  ShouldObjectMembers = Dext.Assertions.ShouldObjectMembers;
  // ShouldObjectHelper is a helper: an alias would not activate it, declare a delegating helper in this unit
  ShouldInterface = Dext.Assertions.ShouldInterface;
  ShouldHelper = Dext.Assertions.ShouldHelper;
  // ShouldList<T> is used via TShould or directly from Dext.Assertions

  // Dext.Interception
  EInterceptionException = Dext.Interception.EInterceptionException;
  IInvocation = Dext.Interception.IInvocation;
  IInterceptor = Dext.Interception.IInterceptor;
  IProxyTargetAccessor = Dext.Interception.IProxyTargetAccessor;
  TProxy = Dext.Interception.TProxy;

  // Dext.Interception.ClassProxy
  TClassProxy = Dext.Interception.ClassProxy.TClassProxy;

  // Dext.Interception.Proxy
  TInvocation = Dext.Interception.Proxy.TInvocation;
  TInterfaceProxy = Dext.Interception.Proxy.TInterfaceProxy;

  // Dext.Mocks
  EMockException = Dext.Mocks.EMockException;
  TMockBehavior = Dext.Mocks.TMockBehavior;
  Times = Dext.Mocks.Times;
  IMock = Dext.Mocks.IMock;
  // ISetup<T> = Dext.Mocks.ISetup<T>;
  // IWhen<T> = Dext.Mocks.IWhen<T>;
  // IMock<T> = Dext.Mocks.IMock<T>;
  // ISetup<T> = Dext.Mocks.ISetup<T>;
  // IWhen<T> = Dext.Mocks.IWhen<T>;
  // Mock<T> = Dext.Mocks.Mock<T>;

  // Dext.Mocks.Auto
  TAutoMocker = Dext.Mocks.Auto.TAutoMocker;

  // Dext.Mocks.Interceptor
  TMockState = Dext.Mocks.Interceptor.TMockState;
  TMethodSetup = Dext.Mocks.Interceptor.TMethodSetup;
  TMethodCall = Dext.Mocks.Interceptor.TMethodCall;
  TMockInterceptor = Dext.Mocks.Interceptor.TMockInterceptor;
  // TSetup<T> = Dext.Mocks.Interceptor.TSetup<T>;
  // TWhen<T> = Dext.Mocks.Interceptor.TWhen<T>;
  // TMock<T> = Dext.Mocks.Interceptor.TMock<T>;

  // Dext.Mocks.Matching
  TMatcherFactory = Dext.Mocks.Matching.TMatcherFactory;
  Arg = Dext.Mocks.Matching.Arg;

  // Dext.Testing.Attributes
  TestFixtureAttribute = Dext.Testing.Attributes.TestFixtureAttribute;
  TestClassAttribute = Dext.Testing.Attributes.TestClassAttribute;
  TestAttribute = Dext.Testing.Attributes.TestAttribute;
  FactAttribute = Dext.Testing.Attributes.FactAttribute;
  SetupAttribute = Dext.Testing.Attributes.SetupAttribute;
  TearDownAttribute = Dext.Testing.Attributes.TearDownAttribute;
  BeforeAllAttribute = Dext.Testing.Attributes.BeforeAllAttribute;
  ClassInitializeAttribute = Dext.Testing.Attributes.ClassInitializeAttribute;
  AfterAllAttribute = Dext.Testing.Attributes.AfterAllAttribute;
  ClassCleanupAttribute = Dext.Testing.Attributes.ClassCleanupAttribute;
  AssemblyInitializeAttribute = Dext.Testing.Attributes.AssemblyInitializeAttribute;
  OneTimeSetUpAttribute = Dext.Testing.Attributes.OneTimeSetUpAttribute;
  AssemblyCleanupAttribute = Dext.Testing.Attributes.AssemblyCleanupAttribute;
  OneTimeTearDownAttribute = Dext.Testing.Attributes.OneTimeTearDownAttribute;
  TestCaseAttribute = Dext.Testing.Attributes.TestCaseAttribute;
  TestCaseSourceAttribute = Dext.Testing.Attributes.TestCaseSourceAttribute;
  IgnoreAttribute = Dext.Testing.Attributes.IgnoreAttribute;
  SkipAttribute = Dext.Testing.Attributes.SkipAttribute;
  TimeoutAttribute = Dext.Testing.Attributes.TimeoutAttribute;
  RepeatAttribute = Dext.Testing.Attributes.RepeatAttribute;
  RepeatTestAttribute = Dext.Testing.Attributes.RepeatTestAttribute;
  MaxTimeAttribute = Dext.Testing.Attributes.MaxTimeAttribute;
  ExplicitAttribute = Dext.Testing.Attributes.ExplicitAttribute;
  CategoryAttribute = Dext.Testing.Attributes.CategoryAttribute;
  TraitAttribute = Dext.Testing.Attributes.TraitAttribute;
  DescriptionAttribute = Dext.Testing.Attributes.DescriptionAttribute;
  PriorityAttribute = Dext.Testing.Attributes.PriorityAttribute;
  PlatformAttribute = Dext.Testing.Attributes.PlatformAttribute;
  ValuesAttribute = Dext.Testing.Attributes.ValuesAttribute;
  RangeAttribute = Dext.Testing.Attributes.RangeAttribute;
  RandomAttribute = Dext.Testing.Attributes.RandomAttribute;
  CombinatorialAttribute = Dext.Testing.Attributes.CombinatorialAttribute;

  // Dext.Testing.Console
  TTestRunner = Dext.Testing.Runner.TTestRunner;

  // Dext.Testing.Dashboard
  // TDashboardListener = Dext.Testing.Dashboard.TDashboardListener;



  // Dext.Testing.Host
  TTestHost = Dext.Testing.Host.TTestHost;

  // Dext.Testing.Coverage.Lcov
  TLcovLine = Dext.Testing.Coverage.Lcov.TLcovLine;
  TLcovFile = Dext.Testing.Coverage.Lcov.TLcovFile;

  // Dext.Testing.DI
  TTestServiceProvider = Dext.Testing.DI.TTestServiceProvider;

  // Dext.Testing.Fluent
  TTestConfigurator = Dext.Testing.Fluent.TTestConfigurator;
  TTest = Dext.Testing.Fluent.TTest;

  // Dext.Testing.History
  TTestHistoryManager = Dext.Testing.History.TTestHistoryManager;

  // Dext.Testing.Report
  TReportFormat = Dext.Testing.Report.TReportFormat;
  TTestCaseReport = Dext.Testing.Report.TTestCaseReport;
  TTestSuiteReport = Dext.Testing.Report.TTestSuiteReport;
  TJUnitReporter = Dext.Testing.Report.TJUnitReporter;
  TJsonReporter = Dext.Testing.Report.TJsonReporter;
  TSonarQubeReporter = Dext.Testing.Report.TSonarQubeReporter;
  TXUnitReporter = Dext.Testing.Report.TXUnitReporter;
  TTRXReporter = Dext.Testing.Report.TTRXReporter;
  THTMLReporter = Dext.Testing.Report.THTMLReporter;

  // Dext.Testing.Runner
  TTestResult = Dext.Testing.Integration.TTestResult;
  TTestInfo = Dext.Testing.Integration.TTestInfo;
  TTestSummary = Dext.Testing.Runner.TTestSummary;
  TTestFilter = Dext.Testing.Runner.TTestFilter;
  TTestStartEvent = Dext.Testing.Runner.TTestStartEvent;
  TTestCompleteEvent = Dext.Testing.Runner.TTestCompleteEvent;
  TFixtureStartEvent = Dext.Testing.Runner.TFixtureStartEvent;
  TFixtureCompleteEvent = Dext.Testing.Runner.TFixtureCompleteEvent;
  ITestListener = Dext.Testing.Runner.ITestListener;
  TOutputFormat = Dext.Testing.Runner.TOutputFormat;
  TTestFixtureInfo = Dext.Testing.Runner.TTestFixtureInfo;
  ITestContext = Dext.Testing.Runner.ITestContext;
  TTestContext = Dext.Testing.Runner.TTestContext;
  TTestConsole = Dext.Testing.Runner.TTestConsole;

const
  // Dext.Mocks
  Loose = Dext.Mocks.Loose;
  Strict = Dext.Mocks.Strict;
  // Dext.Mocks.Interceptor
  Acting = Dext.Mocks.Interceptor.Acting;
  Arranging = Dext.Mocks.Interceptor.Arranging;
  Asserting = Dext.Mocks.Interceptor.Asserting;
  // Dext.Testing.Report
  rfJUnit = Dext.Testing.Report.rfJUnit;
  rfXUnit = Dext.Testing.Report.rfXUnit;
  rfJSON = Dext.Testing.Report.rfJSON;
  rfSonarQube = Dext.Testing.Report.rfSonarQube;
  rfTRX = Dext.Testing.Report.rfTRX;
  // Dext.Testing.Runner
  trPassed = Dext.Testing.Integration.trPassed;
  trFailed = Dext.Testing.Integration.trFailed;
  trSkipped = Dext.Testing.Integration.trSkipped;
  trTimeout = Dext.Testing.Integration.trTimeout;
  trError = Dext.Testing.Integration.trError;
  ofConsole = Dext.Testing.Runner.ofConsole;
  ofXUnit = Dext.Testing.Runner.ofXUnit;
  ofJUnit = Dext.Testing.Runner.ofJUnit;
  // {END_DEXT_ALIASES}

type
  /// <summary>
  ///   Property assertions for ShouldObject. A helper alias is not active in
  ///   Delphi, so the facade declares its own helper and delegates to
  ///   Dext.Assertions.ShouldObjectMembers.
  /// </summary>
  ShouldObjectHelper = record helper for ShouldObject
  public
    function HaveProperty(const PropertyName: string): ShouldProperty;
    function HavePropertyValue(const PropertyName: string; const ExpectedValue: TValue): ShouldObject;
    function HaveValue(const PropertyMetadata: StringType; const ExpectedValue: string): ShouldObject; overload;
    function HaveValue(const PropertyMetadata: IntType; ExpectedValue: Integer): ShouldObject; overload;
    function HaveValue<T>(const PropertyMetadata: T; ExpectedValue: T): ShouldObject; overload;
  end;

// Global helper functions for cleaner syntax
/// <summary>Initiates a fluent assertion for strings.</summary>
function Should(const Value: string): ShouldString; overload;
/// <summary>Initiates a fluent assertion for 32-bit integers.</summary>
function Should(Value: Integer): ShouldInteger; overload;
/// <summary>Initiates a fluent assertion for 64-bit integers.</summary>
function Should(Value: Int64): ShouldInt64; overload;
/// <summary>Initiates a fluent assertion for Boolean values.</summary>
function Should(Value: Boolean): ShouldBoolean; overload;
/// <summary>Initiates a fluent assertion for floating-point numbers (Double).</summary>
function Should(Value: Double): ShouldDouble; overload;
/// <summary>Initiates a fluent assertion for Single values.</summary>
function Should(Value: Single): ShouldDouble; overload;
/// <summary>Initiates a fluent assertion for Extended values and real literals.</summary>
function Should(Value: Extended): ShouldDouble; overload;
/// <summary>Initiates a fluent assertion for Currency values.</summary>
function Should(Value: Currency): ShouldDouble; overload;
/// <summary>Initiates a fluent assertion for dates and times.</summary>
function Should(Value: TDateTime): ShouldDateTime; overload;
/// <summary>Initiates a fluent assertion for dates.</summary>
function Should(Value: TDate): ShouldDateTime; overload;
/// <summary>Initiates a fluent assertion for times.</summary>
function Should(Value: TTime): ShouldDateTime; overload;
/// <summary>Initiates a fluent assertion to intercept exceptions in anonymous procedures.</summary>
function Should(const Action: TProc): ShouldAction; overload;
/// <summary>Initiates a fluent assertion for objects, allowing null and type checks.</summary>
function Should(const Value: TObject): ShouldObject; overload;
/// <summary>Initiates a fluent assertion for interfaces.</summary>
function Should(const Value: IInterface): ShouldInterface; overload;
/// <summary>Initiates a fluent assertion for globally unique identifiers (GUID).</summary>
function Should(const Value: TGUID): ShouldGuid; overload;
/// <summary>Initiates a fluent assertion for native Dext UUIDs.</summary>
function Should(const Value: TUUID): ShouldUUID; overload;
/// <summary>Initiates a fluent assertion for Variant types.</summary>
function Should(const Value: Variant): ShouldVariant; overload;
/// <summary>Initiates a specialized fluent assertion for dates and times.</summary>
function ShouldDate(Value: TDateTime): ShouldDateTime; overload;
/// <summary>Generic helper for other specialized fluent assertions.</summary>
function Should: ShouldHelper; overload;

// Fluent Builders
/// <summary>Initiates the fluent configuration builder for test execution.</summary>
function ConfigureTests: TTestConfigurator;
/// <summary>Executes the tests using a custom configuration.</summary>
procedure RunTests(const Config: TTestConfigurator); overload;
/// <summary>Executes all registered tests in the application using default settings.</summary>
procedure RunTests; overload;

implementation

function Should(const Value: string): ShouldString; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Integer): ShouldInteger; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Int64): ShouldInt64; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Boolean): ShouldBoolean; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Double): ShouldDouble; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Single): ShouldDouble; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Extended): ShouldDouble; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: Currency): ShouldDouble; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: TDateTime): ShouldDateTime; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: TDate): ShouldDateTime; begin Result := Dext.Assertions.Should(Value); end;
function Should(Value: TTime): ShouldDateTime; begin Result := Dext.Assertions.Should(Value); end;
function Should(const Action: TProc): ShouldAction; begin Result := Dext.Assertions.Should(Action); end;
function Should(const Value: TObject): ShouldObject; begin Result := Dext.Assertions.Should(Value); end;
function Should(const Value: IInterface): ShouldInterface; begin Result := Dext.Assertions.Should(Value); end;
function Should(const Value: TGUID): ShouldGuid; begin Result := Dext.Assertions.Should(Value); end;
function Should(const Value: TUUID): ShouldUUID; begin Result := Dext.Assertions.Should(Value); end;
function Should(const Value: Variant): ShouldVariant; begin Result := Dext.Assertions.Should(Value); end;
function ShouldDate(Value: TDateTime): ShouldDateTime; begin Result := Dext.Assertions.ShouldDate(Value); end;
function Should: ShouldHelper; begin end;

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

function ConfigureTests: TTestConfigurator; begin Result := Dext.Testing.Fluent.ConfigureTests; end;
procedure RunTests(const Config: TTestConfigurator); begin Dext.Testing.Host.RunTests(Config); end;
procedure RunTests; begin Dext.Testing.Host.RunTests; end;

end.
