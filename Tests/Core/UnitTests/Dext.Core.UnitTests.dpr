program Dext.Core.UnitTests;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Core.Debug,
  System.SysUtils,
  Dext.Testing.Runner,
  Dext.Testing.Attributes,
  Dext.Testing.Fluent,
  Dext.Testing,
  Dext.Utils,
  Dext.Hosting.CLI.Args in '..\..\..\Sources\Hosting\CLI\Dext.Hosting.CLI.Args.pas',
  Dext.Hosting.CLI.Commands.Codecs in '..\..\..\Apps\CLI\Commands\Dext.Hosting.CLI.Commands.Codecs.pas',
  Dext.Codecs.S54.Tests in 'Dext.Codecs.S54.Tests.pas',
  Dext.Json.Refactored.Tests in 'Dext.Json.Refactored.Tests.pas',
  Dext.Configuration.Features.Tests in 'Dext.Configuration.Features.Tests.pas',
  Dext.Configuration.Hashing.Tests in 'Dext.Configuration.Hashing.Tests.pas',
  Dext.Logging.Telemetry.Tests in 'Dext.Logging.Telemetry.Tests.pas',
  Dext.Performance.Allocator.Tests in 'Dext.Performance.Allocator.Tests.pas',
  Dext.Performance.Allocator in '..\..\..\Sources\Performance\Dext.Performance.Allocator.pas',
  Dext.Web.Utf8 in '..\..\..\Sources\Web\Dext.Web.Utf8.pas',
  Dext.Web.Utf8.Tests in 'Dext.Web.Utf8.Tests.pas',
  Dext.Web.ResponseWriter in '..\..\..\Sources\Web\Dext.Web.ResponseWriter.pas',
  Dext.Web.ResponseWriter.Tests in 'Dext.Web.ResponseWriter.Tests.pas',
  Dext.Server.BoundedExecutor in '..\..\..\Sources\Server\Dext.Server.BoundedExecutor.pas',
  Dext.Server.BoundedExecutor.Tests in 'Dext.Server.BoundedExecutor.Tests.pas',
  Dext.Json.Utf8.Serializer.Tests in 'Dext.Json.Utf8.Serializer.Tests.pas',
  Dext.Json.Utf8.Writer.Tests in 'Dext.Json.Utf8.Writer.Tests.pas',
  Dext.Json.Regression.Tests in 'Dext.Json.Regression.Tests.pas',
  Dext.Json.Defaults.Tests in 'Dext.Json.Defaults.Tests.pas',
  Dext.Json.EnumStyle.Tests in 'Dext.Json.EnumStyle.Tests.pas',
  Dext.Json.Ignore.Tests in 'Dext.Json.Ignore.Tests.pas',
  Dext.Json.CaseStyle.Tests in 'Dext.Json.CaseStyle.Tests.pas',
  Dext.Json.NotMapped.Tests in 'Dext.Json.NotMapped.Tests.pas',
  Dext.Json.Bytes.Tests in 'Dext.Json.Bytes.Tests.pas',
  Dext.Json.FormatAttributes.Tests in 'Dext.Json.FormatAttributes.Tests.pas',
  Dext.Json.RecordFieldNames.Tests in 'Dext.Json.RecordFieldNames.Tests.pas',
  Dext.MM.Tests in 'Dext.MM.Tests.pas',
  Dext.Json.Nullable.Tests in 'Dext.Json.Nullable.Tests.pas',
  Dext.Json.Dates.Tests in 'Dext.Json.Dates.Tests.pas',
  Dext.Json.NoDate.Tests in 'Dext.Json.NoDate.Tests.pas',
  Dext.Json.NullDates.Tests in 'Dext.Json.NullDates.Tests.pas',
  Dext.RecordDefaults.Tests in 'Dext.RecordDefaults.Tests.pas',
  Dext.Json.RecordProperties.Tests in 'Dext.Json.RecordProperties.Tests.pas',
  Dext.Resilience.Tests in 'Dext.Resilience.Tests.pas',
  Dext.Validation.Fluent.Tests in 'Dext.Validation.Fluent.Tests.pas',
  Dext.BackgroundJobs.Tests in 'Dext.BackgroundJobs.Tests.pas',
  Dext.Json.NextGen.Tests in 'Dext.Json.NextGen.Tests.pas',
  Dext.BackgroundJobs.Storage.Sqlite in '..\..\..\Sources\Data\Dext.BackgroundJobs.Storage.Sqlite.pas',
  Dext.Core.SmartTypes.Combinatorial.Tests in 'Dext.Core.SmartTypes.Combinatorial.Tests.pas',
  Dext.Collections.Pool in '..\..\..\Sources\Core\Dext.Collections.Pool.pas',
  Dext.Collections.Pool.Tests in 'Dext.Collections.Pool.Tests.pas',
  Dext.Bcd.Tests in 'Dext.Bcd.Tests.pas',
  Dext.FeatureFlags.Tests in '..\Dext.FeatureFlags.Tests.pas',
  Dext.Configuration.CommandLine.Tests in 'Dext.Configuration.CommandLine.Tests.pas',
  Dext.Configuration.UserSecrets.Tests in 'Dext.Configuration.UserSecrets.Tests.pas';

begin
  SetConsoleCharSet();
  try
    SafeWriteLn;
    SafeWriteLn('🧪 Dext Core Unit Tests');
    SafeWriteLn('=======================');
    SafeWriteLn;

    RunTests(ConfigureTests
      .Verbose
      .RegisterFixtures([
        TConfigFeaturesTests,
        TConfigurationHashingTests,
        TCommandLineConfigurationTests,
        TUserSecretsConfigurationTests,
        TEntityMappingWarningTests,
        TJsonBugReproTests,
        TJsonDefaultsTests,
        TJsonEnumStyleTests,
        TJsonIgnoreTests,
        TJsonCaseStyleTests,
        TJsonNotMappedTests,
        TJsonBytesTests,
        TJsonFormatAttributesTests,
        TJsonRecordFieldNamesTests,
        TDextMMTests,
        TJsonNullableTests,
        TJsonDatesTests,
        TJsonNoDateTests,
        TJsonNullDatesTests,
        TRecordDefaultsTests,
        TJsonInterfaceListTests,
        TJsonIssue108RegressionTests,
        TJsonIssue127RegressionTests,
        TJsonRecordPropertiesTests,
        TJsonRegressionTests,
        TJsonNextGenTests,
        TResilienceTests,
        TTelemetryTests,
        TAllocatorTests,
        TUtf8SerializerCurrencyTests,
        TUtf8JsonWriterTests,
        TValidationFluentTests,
        TBackgroundJobsTests,
        TSmartTypesCombinatorialTests,
        TTypeModelTests,
        TDirectAccessTests,
        TArrayConverterTests,
        TTypeConverterRegistryTests,
        TCodecsCommandTests,
        TWebUtf8Tests,
        TResponseWriterTests,
        TBoundedExecutorTests,
        TDextPoolTests,
        TBcdSupportTests,
        TDextFeatureFlagsTests
      ]));
  except
    on E: Exception do
    begin
      SafeWriteLn('FATAL ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
