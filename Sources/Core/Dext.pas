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
{  Created: 2025-12-11                                                      }
{                                                                           }
{***************************************************************************}
unit Dext;

interface

uses
  System.SysUtils,
  // {BEGIN_DEXT_USES}
  // Generated Uses
  Dext.Collections.Extensions,
  Dext.Collections,
  Dext.Collections.Pool,
  Dext.Configuration.Binder,
  Dext.Configuration.CommandLine,
  Dext.Configuration.Core,
  Dext.Configuration.EnvironmentVariables,
  Dext.Configuration.Interfaces,
  Dext.Configuration.Json,
  Dext.Configuration.UserSecrets,
  Dext.Configuration.Yaml,
  Dext.Core.SmartTypes,
  Dext.DI.Attributes,
  Dext.DI.Comparers,
  Dext.DI.Core,
//{$WARN UNIT_DEPRECATED OFF}
//  Dext.DI.Extensions,
//{$WARN UNIT_DEPRECATED ON}
  Dext.DI.Interfaces,
  Dext.Hosting.ApplicationLifetime,
  Dext.Hosting.AppState,
  Dext.Hosting.BackgroundService,
  Dext.Json,
  Dext.Json.Types,
  Dext.Logging.Console,
  Dext.Logging.Extensions,
  Dext.Logging,
  Dext.Mapper,
  Dext.MultiTenancy,
  Dext.Options.Extensions,
  Dext.Options,
  Dext.Specifications.Base,
  Dext.Specifications.Evaluator,
  Dext.Specifications.Fluent,
  Dext.Specifications.Interfaces,
  Dext.Specifications.OrderBy,
  Dext.Specifications.Types,
  Dext.Threading.Async,
  Dext.Types.UUID,
  Dext.Validation,
  Dext.Yaml,
  Dext.Core.Activator,
  Dext.Threading.CancellationToken,
  Dext.Core.Memory,
  Dext.Core.Span,
  Dext.Core.ValueConverters,
  Dext.Types.Lazy,
  Dext.Types.Nullable,
  Dext.Json.Driver.SystemJson,
  Dext.Json.Utf8,
  Dext.Json.Utf8.Serializer,
  Dext.Core.Json.NextGen
  // {END_DEXT_USES}
  ;

type
  // {BEGIN_DEXT_ALIASES}
  // Generated Aliases

  // Dext.Collections
  TCollections = Dext.Collections.TCollections;
  IPoolable = Dext.Collections.Pool.IPoolable;
  TDextPoolConfig = Dext.Collections.Pool.TDextPoolConfig;
  // IEnumerator<T> = Dext.Collections.IEnumerator<T>;
  // IEnumerable<T> = Dext.Collections.IEnumerable<T>;
  // IList<T> = Dext.Collections.IList<T>;
  // TSmartEnumerator<T> = Dext.Collections.TSmartEnumerator<T>;
  // TSmartList<T> = Dext.Collections.TSmartList<T>;

  // Dext.Collections.Extensions
  TListExtensions = Dext.Collections.Extensions.TListExtensions;

  // Dext.Configuration.Binder
  TConfigurationBinder = Dext.Configuration.Binder.TConfigurationBinder;

  // Dext.Configuration.CommandLine
  TCommandLineConfigurationProvider = Dext.Configuration.CommandLine.TCommandLineConfigurationProvider;
  TCommandLineConfigurationSource = Dext.Configuration.CommandLine.TCommandLineConfigurationSource;

  // Dext.Configuration.Core
  TConfigurationProvider = Dext.Configuration.Core.TConfigurationProvider;
  TConfigurationSection = Dext.Configuration.Core.TConfigurationSection;
  TConfigurationRoot = Dext.Configuration.Core.TConfigurationRoot;
  TConfigurationBuilder = Dext.Configuration.Core.TConfigurationBuilder;
  TConfigurationPath = Dext.Configuration.Core.TConfigurationPath;
  TDextConfiguration = Dext.Configuration.Core.TDextConfiguration;
  TMemoryConfigurationSource = Dext.Configuration.Core.TMemoryConfigurationSource;
  TMemoryConfigurationProvider = Dext.Configuration.Core.TMemoryConfigurationProvider;

  // Dext.Configuration.EnvironmentVariables
  TEnvironmentVariablesConfigurationProvider = Dext.Configuration.EnvironmentVariables.TEnvironmentVariablesConfigurationProvider;
  TEnvironmentVariablesConfigurationSource = Dext.Configuration.EnvironmentVariables.TEnvironmentVariablesConfigurationSource;

  // Dext.Configuration.Interfaces
  EConfigurationException = Dext.Configuration.Interfaces.EConfigurationException;
  IConfigurationSection = Dext.Configuration.Interfaces.IConfigurationSection;
  IConfigurationBuilder = Dext.Configuration.Interfaces.IConfigurationBuilder;
  IConfiguration = Dext.Configuration.Interfaces.IConfiguration;
  IConfigurationRoot = Dext.Configuration.Interfaces.IConfigurationRoot;
  IConfigurationProvider = Dext.Configuration.Interfaces.IConfigurationProvider;
  IConfigurationSource = Dext.Configuration.Interfaces.IConfigurationSource;

  // Dext.Configuration.Json
  TJsonConfigurationBuilder = Dext.Configuration.Json.TJsonConfigurationBuilder;
  TJsonConfigurationProvider = Dext.Configuration.Json.TJsonConfigurationProvider;
  TJsonConfigurationSource = Dext.Configuration.Json.TJsonConfigurationSource;

  // Dext.Configuration.UserSecrets
  TUserSecretsConfigurationProvider = Dext.Configuration.UserSecrets.TUserSecretsConfigurationProvider;
  TUserSecretsConfigurationSource = Dext.Configuration.UserSecrets.TUserSecretsConfigurationSource;

  // Dext.Configuration.Yaml
  TYamlConfigurationBuilder = Dext.Configuration.Yaml.TYamlConfigurationBuilder;
  TYamlConfigurationProvider = Dext.Configuration.Yaml.TYamlConfigurationProvider;
  TYamlConfigurationSource = Dext.Configuration.Yaml.TYamlConfigurationSource;

  // Dext.Core.Activator
  TActivator = Dext.Core.Activator.TActivator;

  // Dext.Threading.CancellationToken
  ICancellationToken = Dext.Threading.CancellationToken.ICancellationToken;
  TCancellationToken = Dext.Threading.CancellationToken.TCancellationToken;
  TCancellationTokenSource = Dext.Threading.CancellationToken.TCancellationTokenSource;

  // Dext.Core.Memory
  IDeferred = Dext.Core.Memory.IDeferred;
  TDeferredAction = Dext.Core.Memory.TDeferredAction;
  // ILifetime<T> = Dext.Core.Memory.ILifetime<T>;
  // TLifetime<T> = Dext.Core.Memory.TLifetime<T>;

  // Dext.Core.SmartTypes
  IPropInfo = Dext.Core.SmartTypes.IPropInfo;
  BooleanExpression = Dext.Core.SmartTypes.BooleanExpression;
  TPropInfo = Dext.Core.SmartTypes.TPropInfo;
  StringType = Dext.Core.SmartTypes.StringType;
  IntType = Dext.Core.SmartTypes.IntType;
  Int64Type = Dext.Core.SmartTypes.Int64Type;
  BoolType = Dext.Core.SmartTypes.BoolType;
  FloatType = Dext.Core.SmartTypes.FloatType;
  CurrencyType = Dext.Core.SmartTypes.CurrencyType;
  BcdType = Dext.Core.SmartTypes.BcdType;
  FmtBcdType = Dext.Core.SmartTypes.FmtBcdType;
  DateTimeType = Dext.Core.SmartTypes.DateTimeType;
  DateType = Dext.Core.SmartTypes.DateType;
  TimeType = Dext.Core.SmartTypes.TimeType;
  BoolExpr = Dext.Core.SmartTypes.BoolExpr;
  // Prop<T> = Dext.Core.SmartTypes.Prop<T>;
  // TQueryPredicate<T> = Dext.Core.SmartTypes.TQueryPredicate<T>;

  // Dext.Core.Span
  TByteSpan = Dext.Core.Span.TByteSpan;
  // TSpan<T> = Dext.Core.Span.TSpan<T>;

  // Dext.Core.ValueConverters
  IValueConverter = Dext.Core.ValueConverters.IValueConverter;
  TValueConverterRegistry = Dext.Core.ValueConverters.TValueConverterRegistry;
  TValueConverter = Dext.Core.ValueConverters.TValueConverter;
  TBaseConverter = Dext.Core.ValueConverters.TBaseConverter;
  TBcdToCurrencyConverter = Dext.Core.ValueConverters.TBcdToCurrencyConverter;
  TBcdToDoubleConverter = Dext.Core.ValueConverters.TBcdToDoubleConverter;
  TBcdToStringConverter = Dext.Core.ValueConverters.TBcdToStringConverter;
  TBcdToIntegerConverter = Dext.Core.ValueConverters.TBcdToIntegerConverter;
  TVariantToBcdConverter = Dext.Core.ValueConverters.TVariantToBcdConverter;
  TStringToBcdConverter = Dext.Core.ValueConverters.TStringToBcdConverter;
  TFloatToBcdConverter = Dext.Core.ValueConverters.TFloatToBcdConverter;
  TIntegerToBcdConverter = Dext.Core.ValueConverters.TIntegerToBcdConverter;
  TCurrencyToBcdConverter = Dext.Core.ValueConverters.TCurrencyToBcdConverter;
  TVariantToIntegerConverter = Dext.Core.ValueConverters.TVariantToIntegerConverter;
  TVariantToStringConverter = Dext.Core.ValueConverters.TVariantToStringConverter;
  TVariantToBooleanConverter = Dext.Core.ValueConverters.TVariantToBooleanConverter;
  TVariantToFloatConverter = Dext.Core.ValueConverters.TVariantToFloatConverter;
  TVariantToDateTimeConverter = Dext.Core.ValueConverters.TVariantToDateTimeConverter;
  TVariantToDateConverter = Dext.Core.ValueConverters.TVariantToDateConverter;
  TVariantToTimeConverter = Dext.Core.ValueConverters.TVariantToTimeConverter;
  TVariantToEnumConverter = Dext.Core.ValueConverters.TVariantToEnumConverter;
  TVariantToGuidConverter = Dext.Core.ValueConverters.TVariantToGuidConverter;
  TVariantToClassConverter = Dext.Core.ValueConverters.TVariantToClassConverter;
  TIntegerToEnumConverter = Dext.Core.ValueConverters.TIntegerToEnumConverter;
  TStringToGuidConverter = Dext.Core.ValueConverters.TStringToGuidConverter;
  TVariantToBytesConverter = Dext.Core.ValueConverters.TVariantToBytesConverter;
  TStringToBytesConverter = Dext.Core.ValueConverters.TStringToBytesConverter;
  TClassToClassConverter = Dext.Core.ValueConverters.TClassToClassConverter;

  // Dext.DI.Attributes
  ServiceConstructorAttribute = Dext.DI.Attributes.ServiceConstructorAttribute;

  // Dext.DI.Comparers
  TServiceTypeComparer = Dext.DI.Comparers.TServiceTypeComparer;

  // Dext.DI.Core
  TServiceDescriptor = Dext.DI.Interfaces.TServiceDescriptor;
  TDextServiceScope = Dext.DI.Core.TDextServiceScope;
  TDextServiceProvider = Dext.DI.Core.TDextServiceProvider;
  TDextServiceCollection = Dext.DI.Core.TDextServiceCollection;

  // Dext.DI.Extensions - Deprecated
//  TServiceCollectionExtensions = Dext.DI.Extensions.TServiceCollectionExtensions;
//  TServiceProviderExtensions = Dext.DI.Extensions.TServiceProviderExtensions;

  // Dext.DI.Interfaces
  IServiceCollection = Dext.DI.Interfaces.IServiceCollection;
  IServiceProvider = Dext.DI.Interfaces.IServiceProvider;
  TServiceLifetime = Dext.DI.Interfaces.TServiceLifetime;
  EDextDIException = Dext.DI.Interfaces.EDextDIException;
  TServiceType = Dext.DI.Interfaces.TServiceType;
  IServiceScope = Dext.DI.Interfaces.IServiceScope;
  TDextServices = Dext.DI.Interfaces.TDextServices;
  TDextDIFactory = Dext.DI.Interfaces.TDextDIFactory;

  /// <summary>
  ///   Core Helper for TDextServices.
  /// </summary>
  TDextCoreServicesHelper = record helper for TDextServices
  public
    /// <summary>
    ///   Adds logging services to the application.
    /// </summary>
    function AddLogging(const AConfigure: TProc<ILoggingBuilder> = nil): TDextServices;
  end;

  // Dext.Hosting.ApplicationLifetime
  IHostApplicationLifetime = Dext.Hosting.ApplicationLifetime.IHostApplicationLifetime;
  THostApplicationLifetime = Dext.Hosting.ApplicationLifetime.THostApplicationLifetime;

  // Dext.Hosting.AppState
  TApplicationState = Dext.Hosting.AppState.TApplicationState;
  IAppStateObserver = Dext.Hosting.AppState.IAppStateObserver;
  IAppStateControl = Dext.Hosting.AppState.IAppStateControl;
  TApplicationStateManager = Dext.Hosting.AppState.TApplicationStateManager;

  // Dext.Hosting.BackgroundService
  IHostedService = Dext.Hosting.BackgroundService.IHostedService;
  IHostedServiceManager = Dext.Hosting.BackgroundService.IHostedServiceManager;
  TBackgroundService = Dext.Hosting.BackgroundService.TBackgroundService;
  TBackgroundServiceThread = Dext.Hosting.BackgroundService.TBackgroundServiceThread;
  THostedServiceManager = Dext.Hosting.BackgroundService.THostedServiceManager;
  TBackgroundServiceBuilder = Dext.Hosting.BackgroundService.TBackgroundServiceBuilder;

  // Dext.Json
  EDextJsonException = Dext.Json.EDextJsonException;
  DextJsonAttribute = Dext.Json.DextJsonAttribute;
  JsonNameAttribute = Dext.Json.JsonNameAttribute;
  JsonIgnoreAttribute = Dext.Json.JsonIgnoreAttribute;
  TJsonIgnoreMode = Dext.Json.TJsonIgnoreMode;
  JsonFormatAttribute = Dext.Json.JsonFormatAttribute;
  JsonStringAttribute = Dext.Json.JsonStringAttribute;
  JsonNumberAttribute = Dext.Json.JsonNumberAttribute;
  JsonBooleanAttribute = Dext.Json.JsonBooleanAttribute;
  // New types (preferred)
  TCaseStyle = Dext.Json.Types.TCaseStyle;
  TEnumStyle = Dext.Json.Types.TEnumStyle;
  TJsonFormatting = Dext.Json.Types.TJsonFormatting;
  TDateFormat = Dext.Json.Types.TDateFormat;
  TJsonSettings = Dext.Json.Types.TJsonSettings;
  // Deprecated aliases (for backward compatibility)
{$WARNINGS OFF}
  TDextCaseStyle = Dext.Json.TDextCaseStyle;
  TDextEnumStyle = Dext.Json.TDextEnumStyle;
  TDextFormatting = Dext.Json.TDextFormatting;
  TDextDateFormat = Dext.Json.TDextDateFormat;
  TDextSettings = Dext.Json.TDextSettings;
  // Core classes
  TJsonUtils = Dext.Json.TJsonUtils;
  TDextJson = Dext.Json.TDextJson;
  TDextSerializer = Dext.Json.TDextSerializer;
  TJsonBuilder = Dext.Json.TJsonBuilder;
{$WARNINGS ON}

  TJsonDataObjectsProvider = Dext.Core.Json.NextGen.TNextGenJsonProvider;

  // Dext.Json.Driver.SystemJson
  TSystemJsonWrapper = Dext.Json.Driver.SystemJson.TSystemJsonWrapper;
  TSystemJsonObjectAdapter = Dext.Json.Driver.SystemJson.TSystemJsonObjectAdapter;
  TSystemJsonArrayAdapter = Dext.Json.Driver.SystemJson.TSystemJsonArrayAdapter;
  TSystemJsonPrimitiveAdapter = Dext.Json.Driver.SystemJson.TSystemJsonPrimitiveAdapter;
  TSystemJsonProvider = Dext.Json.Driver.SystemJson.TSystemJsonProvider;

  // Dext.Json.Types
  TDextJsonNodeType = Dext.Json.Types.TDextJsonNodeType;
  IDextJsonNode = Dext.Json.Types.IDextJsonNode;
  IDextJsonArray = Dext.Json.Types.IDextJsonArray;
  IDextJsonObject = Dext.Json.Types.IDextJsonObject;
  IDextJsonProvider = Dext.Json.Types.IDextJsonProvider;

  // Dext.Json.Utf8
  EJsonException = Dext.Json.Utf8.EJsonException;
  TJsonTokenType = Dext.Json.Utf8.TJsonTokenType;
  TUtf8JsonReader = Dext.Json.Utf8.TUtf8JsonReader;

  // Dext.Json.Utf8.Serializer
  EUtf8SerializationException = Dext.Json.Utf8.Serializer.EUtf8SerializationException;
  TUtf8JsonSerializer = Dext.Json.Utf8.Serializer.TUtf8JsonSerializer;

  // Dext.Logging
  TLogLevel = Dext.Logging.TLogLevel;
  ILogger = Dext.Logging.ILogger;
  ILoggerProvider = Dext.Logging.ILoggerProvider;
  ILoggerFactory = Dext.Logging.ILoggerFactory;
  TAbstractLogger = Dext.Logging.TAbstractLogger;
  TAggregateLogger = Dext.Logging.TAggregateLogger;
  TLoggerFactory = Dext.Logging.TLoggerFactory;

  // Dext.Logging.Console
  TConsoleLogger = Dext.Logging.Console.TConsoleLogger;
  TConsoleLoggerProvider = Dext.Logging.Console.TConsoleLoggerProvider;

  // Dext.Logging.Extensions
  ILoggingBuilder = Dext.Logging.Extensions.ILoggingBuilder;
  TServiceCollectionLoggingExtensions = Dext.Logging.Extensions.TServiceCollectionLoggingExtensions;

  // Dext.Mapper
  TMemberMapping = Dext.Mapper.TMemberMapping;
  TTypeMapConfigBase = Dext.Mapper.TTypeMapConfigBase;
  TMapper = Dext.Mapper.TMapper;
  // TMemberMapFunc<T> = Dext.Mapper.TMemberMapFunc<T>;
  // TTypeMapConfig<T> = Dext.Mapper.TTypeMapConfig<T>;

  // Dext.MultiTenancy
  ITenant = Dext.MultiTenancy.ITenant;
  ITenantProvider = Dext.MultiTenancy.ITenantProvider;
  TTenant = Dext.MultiTenancy.TTenant;
  TTenantProvider = Dext.MultiTenancy.TTenantProvider;

  // Dext.Options
  TOptionsFactory = Dext.Options.TOptionsFactory;
  // IOptions<T> = Dext.Options.IOptions<T>;
  // TOptions<T> = Dext.Options.TOptions<T>;

  // Dext.Options.Extensions
  TOptionsServiceCollectionExtensions = Dext.Options.Extensions.TOptionsServiceCollectionExtensions;

  // Dext.Specifications.Base
  TJoin = Dext.Specifications.Base.TJoin;
  // TSpecification<T> = Dext.Specifications.Base.TSpecification<T>;

  // Dext.Specifications.Evaluator
  TExpressionEvaluator = Dext.Specifications.Evaluator.TExpressionEvaluator;

  // Dext.Specifications.Fluent
  Specification = Dext.Specifications.Fluent.Specification;
  // TSpecificationBuilder<T> = Dext.Specifications.Fluent.TSpecificationBuilder<T>;

  // Dext.Specifications.Interfaces
  TMatchMode = Dext.Specifications.Interfaces.TMatchMode;
  TJoinType = Dext.Specifications.Interfaces.TJoinType;
  IExpression = Dext.Specifications.Interfaces.IExpression;
  IOrderBy = Dext.Specifications.Interfaces.IOrderBy;
  IJoin = Dext.Specifications.Interfaces.IJoin;
  IExpressionVisitor = Dext.Specifications.Interfaces.IExpressionVisitor;
  // ISpecification<T> = Dext.Specifications.Interfaces.ISpecification<T>;

  // Dext.Specifications.OrderBy
  TOrderBy = Dext.Specifications.OrderBy.TOrderBy;

  // Dext.Specifications.Types
  TAbstractExpression = Dext.Specifications.Types.TAbstractExpression;
  TBinaryOperator = Dext.Specifications.Types.TBinaryOperator;
  TArithmeticOperator = Dext.Specifications.Types.TArithmeticOperator;
  TBinaryExpression = Dext.Specifications.Types.TBinaryExpression;
  TArithmeticExpression = Dext.Specifications.Types.TArithmeticExpression;
  TPropertyExpression = Dext.Specifications.Types.TPropertyExpression;
  TLiteralExpression = Dext.Specifications.Types.TLiteralExpression;
  TLogicalOperator = Dext.Specifications.Types.TLogicalOperator;
  TLogicalExpression = Dext.Specifications.Types.TLogicalExpression;
  TUnaryOperator = Dext.Specifications.Types.TUnaryOperator;
  TUnaryExpression = Dext.Specifications.Types.TUnaryExpression;
  TConstantExpression = Dext.Specifications.Types.TConstantExpression;
  TFluentExpression = Dext.Specifications.Types.TFluentExpression;
  TPropExpression = Dext.Specifications.Types.TPropExpression;

  // Dext.Threading.Async
  IAsyncTask = Dext.Threading.Async.IAsyncTask;
  TAsyncTask = Dext.Threading.Async.TAsyncTask;
  // TAsyncTask<T> = Dext.Threading.Async.TAsyncTask<T>;
  // TAsyncBuilder<T> = Dext.Threading.Async.TAsyncBuilder<T>;

  // Dext.Types.Lazy
  ILazy = Dext.Types.Lazy.ILazy;
  // ILazy<T> = Dext.Types.Lazy.ILazy<T>;
  // TLazy<T> = Dext.Types.Lazy.TLazy<T>;
  // TValueLazy<T> = Dext.Types.Lazy.TValueLazy<T>;
  // TLazy<T> = Dext.Types.Lazy.TLazy<T>;
  // TValueLazy<T> = Dext.Types.Lazy.TValueLazy<T>;

  // Dext.Types.Nullable
  TNullableHelper = Dext.Types.Nullable.TNullableHelper;
  // Nullable<T> = Dext.Types.Nullable.Nullable<T>;

  // Dext.Types.UUID
  TUUID = Dext.Types.UUID.TUUID;

  // Dext.Validation
  TValidationError = Dext.Validation.TValidationError;
  TValidationResult = Dext.Validation.TValidationResult;
  ValidationAttribute = Dext.Validation.ValidationAttribute;
  RequiredAttribute = Dext.Validation.RequiredAttribute;
  StringLengthAttribute = Dext.Validation.StringLengthAttribute;
  EmailAddressAttribute = Dext.Validation.EmailAddressAttribute;
  RangeAttribute = Dext.Validation.RangeAttribute;
  TValidator = Dext.Validation.TValidator;
  // IValidator<T> = Dext.Validation.IValidator<T>;
  // TValidator<T> = Dext.Validation.TValidator<T>;
  // IValidationRule<T> = Dext.Validation.IValidationRule<T>;
  // TValidationRule<T> = Dext.Validation.TValidationRule<T>;
  // TValidationRuleBuilder<T> = Dext.Validation.TValidationRuleBuilder<T>;
  // TAbstractValidator<T> = Dext.Validation.TAbstractValidator<T>;

  // Dext.Yaml
  EYamlException = Dext.Yaml.EYamlException;
  TYamlNodeType = Dext.Yaml.TYamlNodeType;
  TYamlNode = Dext.Yaml.TYamlNode;
  TYamlScalar = Dext.Yaml.TYamlScalar;
  TYamlMapping = Dext.Yaml.TYamlMapping;
  TYamlSequence = Dext.Yaml.TYamlSequence;
  TYamlDocument = Dext.Yaml.TYamlDocument;
  TYamlParser = Dext.Yaml.TYamlParser;

  // Dext.Core.Json.NextGen (DOM mappings)
  TJsonBaseObject = Dext.Core.Json.NextGen.TJsonBaseObject;
  TJsonObject = Dext.Core.Json.NextGen.TJsonObject;
  TJsonArray = Dext.Core.Json.NextGen.TJsonArray;
  EJsonCastException = Dext.Core.Json.NextGen.EJsonException;
  EJsonPathException = Dext.Core.Json.NextGen.EJsonException;
  EJsonParserException = Dext.Core.Json.NextGen.EJsonParserException;
  TJsonSerializationConfig = Dext.Json.Types.TJsonSettings;
  TJsonDataType = Dext.Json.Types.TDextJsonNodeType;

const
  // Dext.DI.Interfaces
  Singleton = Dext.DI.Interfaces.Singleton;
  Transient = Dext.DI.Interfaces.Transient;
  Scoped = Dext.DI.Interfaces.Scoped;
  // Dext.Hosting.AppState
  asStarting = Dext.Hosting.AppState.asStarting;
  asMigrating = Dext.Hosting.AppState.asMigrating;
  asSeeding = Dext.Hosting.AppState.asSeeding;
  asRunning = Dext.Hosting.AppState.asRunning;
  asStopping = Dext.Hosting.AppState.asStopping;
  asStopped = Dext.Hosting.AppState.asStopped;
  // Dext.Json
  CaseInherit = Dext.Json.Types.CaseInherit;
  Unchanged = Dext.Json.Types.Unchanged;
  CamelCase = Dext.Json.Types.CamelCase;
  PascalCase = Dext.Json.Types.PascalCase;
  SnakeCase = Dext.Json.Types.SnakeCase;
  EnumInherit = Dext.Json.Types.EnumInherit;
  AsNumber = Dext.Json.Types.AsNumber;
  AsString = Dext.Json.Types.AsString;
  None = Dext.Json.Types.None;
  Indented = Dext.Json.Types.Indented;
  ISO8601 = Dext.Json.Types.ISO8601;
  UnixTimestamp = Dext.Json.Types.UnixTimestamp;
  DEFAULT_MAX_JSON_DEPTH = Dext.Json.Types.DEFAULT_MAX_JSON_DEPTH;
  UNLIMITED_JSON_DEPTH = Dext.Json.Types.UNLIMITED_JSON_DEPTH;
  CustomFormat = Dext.Json.Types.CustomFormat;
  // Dext.Json.Types
  jntNull = Dext.Json.Types.jntNull;
  jntString = Dext.Json.Types.jntString;
  jntNumber = Dext.Json.Types.jntNumber;
  jntBoolean = Dext.Json.Types.jntBoolean;
  jntObject = Dext.Json.Types.jntObject;
  jntArray = Dext.Json.Types.jntArray;
  // Dext.Json.Utf8
  StartObject = Dext.Json.Utf8.StartObject;
  EndObject = Dext.Json.Utf8.EndObject;
  StartArray = Dext.Json.Utf8.StartArray;
  EndArray = Dext.Json.Utf8.EndArray;
  PropertyName = Dext.Json.Utf8.PropertyName;
  StringValue = Dext.Json.Utf8.StringValue;
  Number = Dext.Json.Utf8.Number;
  TrueValue = Dext.Json.Utf8.TrueValue;
  FalseValue = Dext.Json.Utf8.FalseValue;
  NullValue = Dext.Json.Utf8.NullValue;
  Comment = Dext.Json.Utf8.Comment;
  // Dext.Logging
  Trace = Dext.Logging.Trace;
  Debug = Dext.Logging.Debug;
  Information = Dext.Logging.Information;
  Warning = Dext.Logging.Warning;
  Error = Dext.Logging.Error;
  Critical = Dext.Logging.Critical;
  // Dext.Specifications.Interfaces
  mmExact = Dext.Specifications.Interfaces.mmExact;
  mmStart = Dext.Specifications.Interfaces.mmStart;
  mmEnd = Dext.Specifications.Interfaces.mmEnd;
  mmAnywhere = Dext.Specifications.Interfaces.mmAnywhere;
  jtInner = Dext.Specifications.Interfaces.jtInner;
  jtLeft = Dext.Specifications.Interfaces.jtLeft;
  jtRight = Dext.Specifications.Interfaces.jtRight;
  jtFull = Dext.Specifications.Interfaces.jtFull;
  // Dext.Specifications.Types
  boEqual = Dext.Specifications.Types.boEqual;
  boNotEqual = Dext.Specifications.Types.boNotEqual;
  boGreaterThan = Dext.Specifications.Types.boGreaterThan;
  boGreaterThanOrEqual = Dext.Specifications.Types.boGreaterThanOrEqual;
  boLessThan = Dext.Specifications.Types.boLessThan;
  boLessThanOrEqual = Dext.Specifications.Types.boLessThanOrEqual;
  boLike = Dext.Specifications.Types.boLike;
  boNotLike = Dext.Specifications.Types.boNotLike;
  boIn = Dext.Specifications.Types.boIn;
  boNotIn = Dext.Specifications.Types.boNotIn;
  boBitwiseAnd = Dext.Specifications.Types.boBitwiseAnd;
  boBitwiseOr = Dext.Specifications.Types.boBitwiseOr;
  boBitwiseXor = Dext.Specifications.Types.boBitwiseXor;
  boStartsWith = Dext.Specifications.Types.boStartsWith;
  boEndsWith = Dext.Specifications.Types.boEndsWith;
  boContains = Dext.Specifications.Types.boContains;
  aoAdd = Dext.Specifications.Types.aoAdd;
  aoSubtract = Dext.Specifications.Types.aoSubtract;
  aoMultiply = Dext.Specifications.Types.aoMultiply;
  aoDivide = Dext.Specifications.Types.aoDivide;
  aoModulus = Dext.Specifications.Types.aoModulus;
  aoIntDivide = Dext.Specifications.Types.aoIntDivide;
  loAnd = Dext.Specifications.Types.loAnd;
  loOr = Dext.Specifications.Types.loOr;
  uoNot = Dext.Specifications.Types.uoNot;
  uoIsNull = Dext.Specifications.Types.uoIsNull;
  uoIsNotNull = Dext.Specifications.Types.uoIsNotNull;
  // Dext.Yaml
  yntScalar = Dext.Yaml.yntScalar;
  yntMapping = Dext.Yaml.yntMapping;
  yntSequence = Dext.Yaml.yntSequence;
  jdtNone = Dext.Json.Types.TDextJsonNodeType.jntNull;
  jdtString = Dext.Json.Types.TDextJsonNodeType.jntString;
  jdtInt = Dext.Json.Types.TDextJsonNodeType.jntNumber;
  jdtLong = Dext.Json.Types.TDextJsonNodeType.jntNumber;
  jdtULong = Dext.Json.Types.TDextJsonNodeType.jntNumber;
  jdtFloat = Dext.Json.Types.TDextJsonNodeType.jntNumber;
  jdtDateTime = Dext.Json.Types.TDextJsonNodeType.jntString;
  jdtUtcDateTime = Dext.Json.Types.TDextJsonNodeType.jntString;
  jdtBool = Dext.Json.Types.TDextJsonNodeType.jntBoolean;
  jdtArray = Dext.Json.Types.TDextJsonNodeType.jntArray;
  jdtObject = Dext.Json.Types.TDextJsonNodeType.jntObject;
  // {END_DEXT_ALIASES}

/// <summary>
///   Creates a property expression for use in query and specification engines.
///   Ex: Prop('Name').Equal('Cezar')
/// </summary>
function Prop(const Name: string): TPropExpression;

/// <summary>
///   Gets the global Dext JSON serialization settings.
/// </summary>
function JsonSettings: TJsonSettings;

/// <summary>
///   Defines the global default settings for the Dext JSON engine.
/// </summary>
procedure JsonDefaultSettings(const Settings: TJsonSettings);

implementation

function Prop(const Name: string): TPropExpression;
begin
  Result := TPropExpression.Create(Name);
end;

procedure JsonDefaultSettings(const Settings: TJsonSettings);
begin
  TDextJson.SetDefaultSettings(Settings);
end;

function JsonSettings: TJsonSettings;
begin
  Result := Dext.Json.JsonSettings;
end;

{ TDextCoreServicesHelper }

function TDextCoreServicesHelper.AddLogging(const AConfigure: TProc<ILoggingBuilder>): TDextServices;
begin
  TServiceCollectionLoggingExtensions.AddLogging(Self.Unwrap, AConfigure);
  Result := Self;
end;

end.