program Dext.Entity.UnitTests;

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
  Dext.Entity.SmartTypes.Tests in 'Dext.Entity.SmartTypes.Tests.pas',
  Dext.Entity.FluentQuery.Tests in 'Dext.Entity.FluentQuery.Tests.pas',
  Dext.Entity.DataSet.Tests in 'Dext.Entity.DataSet.Tests.pas',
  Dext.Entity.Async.Tests in 'Dext.Entity.Async.Tests.pas',
  Dext.Entity.SqlGenerator.Tests in 'Dext.Entity.SqlGenerator.Tests.pas',
  Dext.Entity.FluentMapping.Tests in 'Dext.Entity.FluentMapping.Tests.pas',
  Dext.Entity.DataSet.NewFeatures.Tests in 'Dext.Entity.DataSet.NewFeatures.Tests.pas',
  Dext.Entity.IdReturn.Tests in 'Dext.Entity.IdReturn.Tests.pas',
  Dext.Entity.NullableHydration.Tests in 'Dext.Entity.NullableHydration.Tests.pas',
  Dext.Entity.DataSet.Export.Tests in 'Dext.Entity.DataSet.Export.Tests.pas',
  Dext.Entity.DefaultValue.Tests in 'Dext.Entity.DefaultValue.Tests.pas',
  Dext.Entity.Design.Metadata.Tests in 'Dext.Entity.Design.Metadata.Tests.pas',
  Dext.Entity.Architecture.Tests in 'Dext.Entity.Architecture.Tests.pas',
  Dext.Entity.ReportedIssues.Tests in 'Dext.Entity.ReportedIssues.Tests.pas',
  Dext.Entity.Scaffolding.Tests in 'Dext.Entity.Scaffolding.Tests.pas',
  Dext.Entity.Migrations.Tests in 'Dext.Entity.Migrations.Tests.pas',
  Dext.Entity.SnakeCaseFk.Tests in 'Dext.Entity.SnakeCaseFk.Tests.pas',
  Dext.Entity.FormatSettings.Tests in 'Dext.Entity.FormatSettings.Tests.pas',
  Dext.Entity.SoftDelete.Tests in 'Dext.Entity.SoftDelete.Tests.pas',
  Dext.Entity.Validation.Tests in 'Dext.Entity.Validation.Tests.pas',
  Dext.Entity.BulkBatchSize.Tests in 'Dext.Entity.BulkBatchSize.Tests.pas',
  Dext.Entity.DynamicQueryFilter.Tests in 'Dext.Entity.DynamicQueryFilter.Tests.pas',
  Dext.Entity.LikeLiteral.Tests in 'Dext.Entity.LikeLiteral.Tests.pas',
  Dext.Entity.Sequences.Tests in 'Dext.Entity.Sequences.Tests.pas',
  Dext.Entity.SaveChanges.Tests in 'Dext.Entity.SaveChanges.Tests.pas',
  Dext.Entity.PersistOwnership.Tests in 'Dext.Entity.PersistOwnership.Tests.pas',
  Dext.Grpc.Tests in 'Dext.Grpc.Tests.pas';

begin
  SetConsoleCharSet();
  try
    SafeWriteLn;
    SafeWriteLn('🧪 Dext Entity Unit Tests');
    SafeWriteLn('=========================');
    SafeWriteLn;

    RunTests(ConfigureTests
      .VeryVerbose
      .RegisterFixtures([
        TBulkBatchSizeTests,
        TCalculatedFieldsTests,
        TDataSetSmartTypesTests,
        TEntityDataSetAutomationTests,
        TEntityDataSetCRUDTests,
        TEntityDataSetExportTests,
        TEntityDataSetFeaturesTests,
        TEntityDataSetStressTests,
        TEntityDataSetTests,
        TEntityDesignMetadataTests,
        TEntityIdReturnTests,
        TEntityNullableHydrationTests,
        TEntityDefaultValueTests,
        TFloatingPointDataSetTests,
        TMasterDetailDataSetTests,
        TNativeMasterDetailTests,
        TProductDataSetTests,
        TShadowDataSetTests,
        TSmartPropertyDataSetTests,
        TSmartTypesMatrixTests,
        TSmartTypesTests,
        TEntityReportedIssuesTests,
        TEntityArchitectureTests,
        TScaffoldingTests,
        TMigrationTests,
        TEntityFormatSettingsTests,
        TSoftDeleteUnitTests,
        TSoftDeleteIntegrationTests,
        TEntityValidationTests,
        TFluentQueryTests,
        TDynamicQueryFilterUnitTests,
        TDynamicQueryFilterIntegrationTests,
        TLikeLiteralSqlTests,
        TLikeLiteralMemoryTests,
        TLikeLiteralDbTests,
        TEntitySequencesTests,
        TSaveChangesTests,
        TPersistUpdateOwnershipTests,
        TGrpcTests
      ]));
  except
    on E: Exception do
    begin
      SafeWriteLn('FATAL ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.
