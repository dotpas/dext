unit Dext.Entity;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}

interface

uses
  FireDAC.Comp.Client,
  System.SysUtils,
  System.Classes,
  // Dext,
  Dext.Types.Lazy,
  Dext.DI.Interfaces,
  Dext.DI.Core,
  Dext.Configuration.Interfaces,
  Dext.Logging.Extensions,
  Dext.Collections.Dict,
  Dext.Core.SmartTypes,
  // {BEGIN_DEXT_USES}
  // Generated Uses
  Dext.Entity.Attributes,
  Dext.Entity.BatchStrategy,
  Dext.Entity.Cache,
  Dext.Entity.Context,
  Dext.Entity.Core,
  Dext.Entity.DbSet,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC.Manager,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.FireDAC.Phys,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.FastQuery,
  Dext.Entity.Grouping,
  Dext.Entity.Joining,
  Dext.Entity.LazyLoading,
  Dext.Entity.Mapping,
  Dext.Entity.Migrations.Builder,
  Dext.Entity.Migrations.Differ,
  Dext.Entity.Migrations.Extractor,
  Dext.Entity.Migrations.Generator,
  Dext.Entity.Migrations.Json,
  Dext.Entity.Migrations.Model,
  Dext.Entity.Migrations.Operations,
  Dext.Entity.Migrations,
  Dext.Entity.Migrations.Runner,
  Dext.Entity.Migrations.Serializers.Json,
  Dext.Entity.Naming,
  Dext.Entity.Prototype,
  Dext.Entity.Query,
  Dext.Entity.Scaffolding,
  Dext.Entity.Setup,
  Dext.Entity.Tenancy,
  Dext.Entity.TypeConverters,
  Dext.Entity.TypeSystem,
  Dext.Entity.Validator,
  Dext.Specifications.SQL.Generator
  // {END_DEXT_USES}
  ;

type
  // External Aliases
  TFDConnection = FireDAC.Comp.Client.TFDConnection;

  // {BEGIN_DEXT_ALIASES}
  // Generated Aliases

  // Dext.Entity.Attributes
  TInheritanceStrategy = Dext.Entity.Attributes.TInheritanceStrategy;
  TableAttribute = Dext.Entity.Attributes.TableAttribute;
  LazyAttribute = Dext.Entity.Attributes.LazyAttribute;
  Lazy = Dext.Entity.Attributes.LazyAttribute;
  ColumnAttribute = Dext.Entity.Attributes.ColumnAttribute;
  PrimaryKeyAttribute = Dext.Entity.Attributes.PrimaryKeyAttribute;
  PKAttribute = Dext.Entity.Attributes.PKAttribute;
  AutoIncAttribute = Dext.Entity.Attributes.AutoIncAttribute;
  RequiredAttribute = Dext.Entity.Attributes.RequiredAttribute;
  MaxLengthAttribute = Dext.Entity.Attributes.MaxLengthAttribute;
  MinLengthAttribute = Dext.Entity.Attributes.MinLengthAttribute;
  PrecisionAttribute = Dext.Entity.Attributes.PrecisionAttribute;
  NotMappedAttribute = Dext.Entity.Attributes.NotMappedAttribute;
  FieldAttribute = Dext.Entity.Attributes.FieldAttribute;
  JsonColumnAttribute = Dext.Entity.Attributes.JsonColumnAttribute;
  VersionAttribute = Dext.Entity.Attributes.VersionAttribute;
  CreatedAtAttribute = Dext.Entity.Attributes.CreatedAtAttribute;
  UpdatedAtAttribute = Dext.Entity.Attributes.UpdatedAtAttribute;
  SoftDeleteAttribute = Dext.Entity.Attributes.SoftDeleteAttribute;
  TCascadeAction = Dext.Entity.Attributes.TCascadeAction;
  ForeignKeyAttribute = Dext.Entity.Attributes.ForeignKeyAttribute;
  FKAttribute = Dext.Entity.Attributes.FKAttribute;
  HasManyAttribute = Dext.Entity.Attributes.HasManyAttribute;
  BelongsToAttribute = Dext.Entity.Attributes.BelongsToAttribute;
  HasOneAttribute = Dext.Entity.Attributes.HasOneAttribute;
  ManyToManyAttribute = Dext.Entity.Attributes.ManyToManyAttribute;
  InversePropertyAttribute = Dext.Entity.Attributes.InversePropertyAttribute;
  DeleteBehaviorAttribute = Dext.Entity.Attributes.DeleteBehaviorAttribute;
  InheritanceAttribute = Dext.Entity.Attributes.InheritanceAttribute;
  DiscriminatorColumnAttribute = Dext.Entity.Attributes.DiscriminatorColumnAttribute;
  DiscriminatorValueAttribute = Dext.Entity.Attributes.DiscriminatorValueAttribute;
  DbTypeAttribute = Dext.Entity.Attributes.DbTypeAttribute;
  TypeConverterAttribute = Dext.Entity.Attributes.TypeConverterAttribute;
  StoredProcedureAttribute = Dext.Entity.Attributes.StoredProcedureAttribute;
  DbParamAttribute = Dext.Entity.Attributes.DbParamAttribute;
  CurrencyAttribute = Dext.Entity.Attributes.CurrencyAttribute;
  CaptionAttribute = Dext.Entity.Attributes.CaptionAttribute;
  DisplayLabelAttribute = Dext.Entity.Attributes.DisplayLabelAttribute;
  DisplayFormatAttribute = Dext.Entity.Attributes.DisplayFormatAttribute;
  AlignmentAttribute = Dext.Entity.Attributes.AlignmentAttribute;
  EditMaskAttribute = Dext.Entity.Attributes.EditMaskAttribute;
  DisplayWidthAttribute = Dext.Entity.Attributes.DisplayWidthAttribute;
  LockTokenAttribute = Dext.Entity.Attributes.LockTokenAttribute;
  LockExpirationAttribute = Dext.Entity.Attributes.LockExpirationAttribute;  
  VisibleAttribute = Dext.Entity.Attributes.VisibleAttribute;
  ReadOnlyAttribute = Dext.Entity.Attributes.ReadOnlyAttribute;
  DefaultValueAttribute = Dext.Entity.Attributes.DefaultValueAttribute;
  SequenceAttribute = Dext.Entity.Attributes.SequenceAttribute;

  // Short Aliases
  PK = Dext.Entity.Attributes.PK;
  FK = Dext.Entity.Attributes.FK;

  Caption = Dext.Entity.Attributes.Caption;
  DisplayLabel = Dext.Entity.Attributes.DisplayLabel;
  DisplayFormat = Dext.Entity.Attributes.DisplayFormat;
  DisplayWidth = Dext.Entity.Attributes.DisplayWidth;
  DefaultValue = Dext.Entity.Attributes.DefaultValue;
  EditMask = Dext.Entity.Attributes.EditMask;
  Alignment = Dext.Entity.Attributes.Alignment;
  ReadOnly = Dext.Entity.Attributes.ReadOnly;
  Visible = Dext.Entity.Attributes.Visible;

  // Dext.Entity.Cache
  TSQLCache = Dext.Entity.Cache.TSQLCache;

  // Dext.Entity.Context
  TFluentExpression = Dext.Entity.Context.TFluentExpression;
  TPropertyInfo = Dext.Entity.Context.TPropertyInfo;
  TChangeTracker = Dext.Entity.Context.TChangeTracker;
  TDbContext = Dext.Entity.Context.TDbContext;
  TCollectionEntry = Dext.Entity.Context.TCollectionEntry;
  TReferenceEntry = Dext.Entity.Context.TReferenceEntry;
  TEntityEntry = Dext.Entity.Context.TEntityEntry;

  // Dext.Entity.FastQuery
  IDextFastQuery = Dext.Entity.FastQuery.IDextFastQuery;
  TDextFastQuery = Dext.Entity.FastQuery.TDextFastQuery;

  // Dext.Entity.Core
  EOptimisticConcurrencyException = Dext.Entity.Core.EOptimisticConcurrencyException;
  TEntityState = Dext.Entity.Core.TEntityState;
  IChangeTracker = Dext.Entity.Core.IChangeTracker;
  IDbSet = Dext.Entity.Core.IDbSet;
  ICollectionEntry = Dext.Entity.Core.ICollectionEntry;
  IReferenceEntry = Dext.Entity.Core.IReferenceEntry;
  IEntityEntry = Dext.Entity.Core.IEntityEntry;
  IDbContext = Dext.Entity.Core.IDbContext;
  // IDbSet<T: class> = Dext.Entity.Core.IDbSet<T>;
  // Generic aliases not supported on all Delphi versions

  // Dext.Entity.BatchStrategy
  TDextBatchStrategyFactory = Dext.Entity.BatchStrategy.TDextBatchStrategyFactory;
  TDextPostgresBatchStrategy = Dext.Entity.BatchStrategy.TDextPostgresBatchStrategy;
  TDextMySqlBatchStrategy = Dext.Entity.BatchStrategy.TDextMySqlBatchStrategy;
  TDextNativeArrayDmlStrategy = Dext.Entity.BatchStrategy.TDextNativeArrayDmlStrategy;

  // Dext.Entity.DbSet
  // TDbSet<T: class> = Dext.Entity.DbSet.TDbSet<T>;

  // Dext.Entity.Dialects
  TDatabaseDialect = Dext.Entity.Dialects.TDatabaseDialect;
  TReturningPosition = Dext.Entity.Dialects.TReturningPosition;
  ISQLDialect = Dext.Entity.Dialects.ISQLDialect;
  TDialectFactory = Dext.Entity.Dialects.TDialectFactory;
  TBaseDialect = Dext.Entity.Dialects.TBaseDialect;
  TSQLiteDialect = Dext.Entity.Dialects.TSQLiteDialect;
  TPostgreSQLDialect = Dext.Entity.Dialects.TPostgreSQLDialect;
  TFirebirdDialect = Dext.Entity.Dialects.TFirebirdDialect;
  TSQLServerDialect = Dext.Entity.Dialects.TSQLServerDialect;
  TMySQLDialect = Dext.Entity.Dialects.TMySQLDialect;
  TMariaDBDialect = Dext.Entity.Dialects.TMariaDBDialect;
  TOracleDialect = Dext.Entity.Dialects.TOracleDialect;
  TInterBaseDialect = Dext.Entity.Dialects.TInterBaseDialect;

  // Dext.Entity.Drivers.FireDAC
  TFireDACConnection = Dext.Entity.Drivers.FireDAC.TFireDACConnection;
  TFireDACTransaction = Dext.Entity.Drivers.FireDAC.TFireDACTransaction;
  TFireDACReader = Dext.Entity.Drivers.FireDAC.TFireDACReader;
  TFireDACCommand = Dext.Entity.Drivers.FireDAC.TFireDACCommand;

  // Dext.Entity.Drivers.FireDAC.Manager
  TComponentHelper = Dext.Entity.Drivers.FireDAC.Manager.TComponentHelper;
  TFireDACOptimization = Dext.Entity.Drivers.FireDAC.Manager.TFireDACOptimization;
  TFireDACOptimizations = Dext.Entity.Drivers.FireDAC.Manager.TFireDACOptimizations;
  TDextFireDACManager = Dext.Entity.Drivers.FireDAC.Manager.TDextFireDACManager;

  // Dext.Entity.Drivers.FireDAC.Phys
  TFireDACPhysTransaction = Dext.Entity.Drivers.FireDAC.Phys.TFireDACPhysTransaction;
  TFireDACPhysReader = Dext.Entity.Drivers.FireDAC.Phys.TFireDACPhysReader;
  TFireDACPhysCommand = Dext.Entity.Drivers.FireDAC.Phys.TFireDACPhysCommand;
  TFireDACPhysConnection = Dext.Entity.Drivers.FireDAC.Phys.TFireDACPhysConnection;

  // Dext.Entity.Drivers.Interfaces
  IDbReader = Dext.Entity.Drivers.Interfaces.IDbReader;
  IDbTransaction = Dext.Entity.Drivers.Interfaces.IDbTransaction;
  IDbCommand = Dext.Entity.Drivers.Interfaces.IDbCommand;
  IDbConnection = Dext.Entity.Drivers.Interfaces.IDbConnection;

  // Dext.Entity.Grouping
  TQuery = Dext.Entity.Grouping.TQuery;
  // IGrouping<T> = Dext.Entity.Grouping.IGrouping<T>;
  // TGrouping<T> = Dext.Entity.Grouping.TGrouping<T>;
  // TGroupByIterator<T> = Dext.Entity.Grouping.TGroupByIterator<T>;

  // Dext.Entity.Joining
  TJoining = Dext.Entity.Joining.TJoining;
  // TJoinIterator<T> = Dext.Entity.Joining.TJoinIterator<T>;

  // Dext.Entity.LazyLoading
  TLazyInjector = Dext.Entity.LazyLoading.TLazyInjector;
  TLazyLoader = Dext.Entity.LazyLoading.TLazyLoader;

  // Dext.Entity.Mapping
  TPropertyMap = Dext.Entity.Mapping.TPropertyMap;
  TEntityMap = Dext.Entity.Mapping.TEntityMap;
  TModelBuilder = Dext.Entity.Mapping.TModelBuilder;
  // IPropertyBuilder<T> = Dext.Entity.Mapping.IPropertyBuilder<T>;
  // IEntityTypeBuilder<T> = Dext.Entity.Mapping.IEntityTypeBuilder<T>;
  // IPropertyBuilder<T> = Dext.Entity.Mapping.IPropertyBuilder<T>;
  // IEntityTypeConfiguration<T> = Dext.Entity.Mapping.IEntityTypeConfiguration<T>;
  // TEntityBuilder<T> = Dext.Entity.Mapping.TEntityBuilder<T>;
  // TEntityTypeBuilder<T> = Dext.Entity.Mapping.TEntityTypeBuilder<T>;
  // TPropertyBuilder<T> = Dext.Entity.Mapping.TPropertyBuilder<T>;
  // TEntityTypeConfiguration<T> = Dext.Entity.Mapping.TEntityTypeConfiguration<T>;

  // Dext.Entity.Migrations
  IMigration = Dext.Entity.Migrations.IMigration;
  TMigrationRegistry = Dext.Entity.Migrations.TMigrationRegistry;

  // Dext.Entity.Migrations.Builder
  TSchemaBuilder = Dext.Entity.Migrations.Builder.TSchemaBuilder;
  TTableBuilder = Dext.Entity.Migrations.Builder.TTableBuilder;
  TColumnBuilder = Dext.Entity.Migrations.Builder.TColumnBuilder;
  IColumnBuilder = Dext.Entity.Migrations.Builder.IColumnBuilder;

  // Dext.Entity.Migrations.Differ
  TModelDiffer = Dext.Entity.Migrations.Differ.TModelDiffer;

  // Dext.Entity.Migrations.Extractor
  TDbContextModelExtractor = Dext.Entity.Migrations.Extractor.TDbContextModelExtractor;

  // Dext.Entity.Migrations.Generator
  TMigrationGenerator = Dext.Entity.Migrations.Generator.TMigrationGenerator;

  // Dext.Entity.Migrations.Json
  TJsonMigration = Dext.Entity.Migrations.Json.TJsonMigration;
  TJsonMigrationLoader = Dext.Entity.Migrations.Json.TJsonMigrationLoader;

  // Dext.Entity.Migrations.Model
  TSnapshotColumn = Dext.Entity.Migrations.Model.TSnapshotColumn;
  TSnapshotForeignKey = Dext.Entity.Migrations.Model.TSnapshotForeignKey;
  TSnapshotTable = Dext.Entity.Migrations.Model.TSnapshotTable;
  TSnapshotModel = Dext.Entity.Migrations.Model.TSnapshotModel;

  // Dext.Entity.Migrations.Operations
  TOperationType = Dext.Entity.Migrations.Operations.TOperationType;
  TMigrationOperation = Dext.Entity.Migrations.Operations.TMigrationOperation;
  TColumnDefinition = Dext.Entity.Migrations.Operations.TColumnDefinition;
  TCreateTableOperation = Dext.Entity.Migrations.Operations.TCreateTableOperation;
  TDropTableOperation = Dext.Entity.Migrations.Operations.TDropTableOperation;
  TAddColumnOperation = Dext.Entity.Migrations.Operations.TAddColumnOperation;
  TDropColumnOperation = Dext.Entity.Migrations.Operations.TDropColumnOperation;
  TAlterColumnOperation = Dext.Entity.Migrations.Operations.TAlterColumnOperation;
  TAddForeignKeyOperation = Dext.Entity.Migrations.Operations.TAddForeignKeyOperation;
  TDropForeignKeyOperation = Dext.Entity.Migrations.Operations.TDropForeignKeyOperation;
  TCreateIndexOperation = Dext.Entity.Migrations.Operations.TCreateIndexOperation;
  TDropIndexOperation = Dext.Entity.Migrations.Operations.TDropIndexOperation;
  TSqlOperation = Dext.Entity.Migrations.Operations.TSqlOperation;

  // Dext.Entity.Migrations.Runner
  TMigrator = Dext.Entity.Migrations.Runner.TMigrator;

  // Dext.Entity.Migrations.Serializers.Json
  TMigrationJsonSerializer = Dext.Entity.Migrations.Serializers.Json.TMigrationJsonSerializer;

  // Dext.Entity.Naming
  INamingStrategy = Dext.Entity.Naming.INamingStrategy;
  TDefaultNamingStrategy = Dext.Entity.Naming.TDefaultNamingStrategy;
  TSnakeCaseNamingStrategy = Dext.Entity.Naming.TSnakeCaseNamingStrategy;
  TLowerCaseNamingStrategy = Dext.Entity.Naming.TLowerCaseNamingStrategy;
  TUppercaseNamingStrategy = Dext.Entity.Naming.TUppercaseNamingStrategy;

  // Dext.Entity.Prototype
  Prototype = Dext.Entity.Prototype.Prototype;
  Build = Dext.Entity.Prototype.Build;

  // Dext.Entity.Query
  // IPagedResult<T> = Dext.Entity.Query.IPagedResult<T>;
  // TPagedResult<T> = Dext.Entity.Query.TPagedResult<T>;
  // TQueryIterator<T> = Dext.Entity.Query.TQueryIterator<T>;
  // TFluentQuery<T> = Dext.Entity.Query.TFluentQuery<T>;
  // TSpecificationQueryIterator<T> = Dext.Entity.Query.TSpecificationQueryIterator<T>;
  // TProjectingIterator<T> = Dext.Entity.Query.TProjectingIterator<T>;
  // TFilteringIterator<T> = Dext.Entity.Query.TFilteringIterator<T>;
  // TSkipIterator<T> = Dext.Entity.Query.TSkipIterator<T>;
  // TTakeIterator<T> = Dext.Entity.Query.TTakeIterator<T>;
  // TDistinctIterator<T> = Dext.Entity.Query.TDistinctIterator<T>;
  // TEmptyIterator<T> = Dext.Entity.Query.TEmptyIterator<T>;

  // Dext.Entity.Scaffolding
  TMetaColumn = Dext.Entity.Scaffolding.TMetaColumn;
  TMetaForeignKey = Dext.Entity.Scaffolding.TMetaForeignKey;
  TMetaTable = Dext.Entity.Scaffolding.TMetaTable;
  ISchemaProvider = Dext.Entity.Scaffolding.ISchemaProvider;
  TMappingStyle = Dext.Entity.Scaffolding.TMappingStyle;
  IEntityGenerator = Dext.Entity.Scaffolding.IEntityGenerator;
  TFireDACSchemaProvider = Dext.Entity.Scaffolding.TFireDACSchemaProvider;
  TDelphiEntityGenerator = Dext.Entity.Scaffolding.TDelphiEntityGenerator;

  // Dext.Entity.Setup
  TDbContextOptions = Dext.Entity.Setup.TDbContextOptions;
  TDbContextOptionsBuilder = Dext.Entity.Setup.TDbContextOptionsBuilder;

  // Dext.Entity.Tenancy
  ITenantAware = Dext.Entity.Tenancy.ITenantAware;
  TTenantEntity = Dext.Entity.Tenancy.TTenantEntity;

  // Dext.Entity.TypeConverters
  EnumAsStringAttribute = Dext.Entity.TypeConverters.EnumAsStringAttribute;
  ArrayColumnAttribute = Dext.Entity.TypeConverters.ArrayColumnAttribute;
  ColumnTypeAttribute = Dext.Entity.TypeConverters.ColumnTypeAttribute;
  ITypeConverter = Dext.Entity.TypeConverters.ITypeConverter;
  TTypeConverterBase = Dext.Entity.TypeConverters.TTypeConverterBase;
  TGuidConverter = Dext.Entity.TypeConverters.TGuidConverter;
  TUuidConverter = Dext.Entity.TypeConverters.TUuidConverter;
  TEnumConverter = Dext.Entity.TypeConverters.TEnumConverter;
  TJsonConverter = Dext.Entity.TypeConverters.TJsonConverter;
  TArrayConverter = Dext.Entity.TypeConverters.TArrayConverter;
  TDateTimeConverter = Dext.Entity.TypeConverters.TDateTimeConverter;
  TDateConverter = Dext.Entity.TypeConverters.TDateConverter;
  TTimeConverter = Dext.Entity.TypeConverters.TTimeConverter;
  TBytesConverter = Dext.Entity.TypeConverters.TBytesConverter;
  TPropConverter = Dext.Entity.TypeConverters.TPropConverter;
  TStringsConverter = Dext.Entity.TypeConverters.TStringsConverter;
  TTypeConverterRegistry = Dext.Entity.TypeConverters.TTypeConverterRegistry;

  // Dext.Entity.TypeSystem
  BcdType = Dext.Core.SmartTypes.BcdType;
  FmtBcdType = Dext.Core.SmartTypes.FmtBcdType;
  // TProp<T> = Dext.Entity.TypeSystem.TProp<T>;
  // IEntityBuilder<T> = Dext.Entity.TypeSystem.IEntityBuilder<T>;
  // TEntityBuilder<T> = Dext.Entity.TypeSystem.TEntityBuilder<T>;
  // TEntityType<T> = Dext.Entity.TypeSystem.TEntityType<T>;

  // Dext.Entity.Validator
  TEntityValidator = Dext.Entity.Validator.TEntityValidator;

  // Dext.Specifications.SQL.Generator
  ISQLColumnMapper = Dext.Specifications.SQL.Generator.ISQLColumnMapper;
  TSQLWhereGenerator = Dext.Specifications.SQL.Generator.TSQLWhereGenerator;
  TSQLGeneratorHelper = Dext.Specifications.SQL.Generator.TSQLGeneratorHelper;
  TJoinTableSQLHelper = Dext.Specifications.SQL.Generator.TJoinTableSQLHelper;
  TSQLParamCollector = Dext.Specifications.SQL.Generator.TSQLParamCollector;
  // TSQLColumnMapper<T> = Dext.Specifications.SQL.Generator.TSQLColumnMapper<T>;
  // TSQLGenerator<T> = Dext.Specifications.SQL.Generator.TSQLGenerator<T>;

const
  // Dext.Entity.Attributes
  None = Dext.Entity.Attributes.None;
  TablePerHierarchy = Dext.Entity.Attributes.TablePerHierarchy;
  TablePerType = Dext.Entity.Attributes.TablePerType;
  caNoAction = Dext.Entity.Attributes.caNoAction;
  caCascade = Dext.Entity.Attributes.caCascade;
  caSetNull = Dext.Entity.Attributes.caSetNull;
  caRestrict = Dext.Entity.Attributes.caRestrict;
  // Dext.Entity.Core
  esDetached = Dext.Entity.Core.esDetached;
  esUnchanged = Dext.Entity.Core.esUnchanged;
  esAdded = Dext.Entity.Core.esAdded;
  esDeleted = Dext.Entity.Core.esDeleted;
  esModified = Dext.Entity.Core.esModified;
  // Dext.Entity.Dialects
  ddUnknown = Dext.Entity.Dialects.ddUnknown;
  ddSQLite = Dext.Entity.Dialects.ddSQLite;
  ddPostgreSQL = Dext.Entity.Dialects.ddPostgreSQL;
  ddMySQL = Dext.Entity.Dialects.ddMySQL;
  ddMariaDB = Dext.Entity.Dialects.ddMariaDB;
  ddSQLServer = Dext.Entity.Dialects.ddSQLServer;
  ddFirebird = Dext.Entity.Dialects.ddFirebird;
  ddInterbase = Dext.Entity.Dialects.ddInterbase;
  ddOracle = Dext.Entity.Dialects.ddOracle;
  rpAtEnd = Dext.Entity.Dialects.rpAtEnd;
  rpBeforeValues = Dext.Entity.Dialects.rpBeforeValues;
  // Dext.Entity.Drivers.FireDAC.Manager
  optDisableMacros = Dext.Entity.Drivers.FireDAC.Manager.optDisableMacros;
  optDisableEscapes = Dext.Entity.Drivers.FireDAC.Manager.optDisableEscapes;
  optDirectExecute = Dext.Entity.Drivers.FireDAC.Manager.optDirectExecute;
  // Dext.Entity.Migrations.Operations
  otCreateTable = Dext.Entity.Migrations.Operations.otCreateTable;
  otDropTable = Dext.Entity.Migrations.Operations.otDropTable;
  otAddColumn = Dext.Entity.Migrations.Operations.otAddColumn;
  otDropColumn = Dext.Entity.Migrations.Operations.otDropColumn;
  otAlterColumn = Dext.Entity.Migrations.Operations.otAlterColumn;
  otAddPrimaryKey = Dext.Entity.Migrations.Operations.otAddPrimaryKey;
  otDropPrimaryKey = Dext.Entity.Migrations.Operations.otDropPrimaryKey;
  otAddForeignKey = Dext.Entity.Migrations.Operations.otAddForeignKey;
  otDropForeignKey = Dext.Entity.Migrations.Operations.otDropForeignKey;
  otCreateIndex = Dext.Entity.Migrations.Operations.otCreateIndex;
  otDropIndex = Dext.Entity.Migrations.Operations.otDropIndex;
  otSql = Dext.Entity.Migrations.Operations.otSql;
  // Dext.Entity.Scaffolding
  msAttributes = Dext.Entity.Scaffolding.msAttributes;
  msFluent = Dext.Entity.Scaffolding.msFluent;
  // {END_DEXT_ALIASES}

  // ===========================================================================
  // ⚡ Local Types & Helpers
  // ===========================================================================
type
  /// <summary>
  ///   Persistence Setup Helper
  /// </summary>
  TDbContextClass = class of TDbContext;
  
  /// <summary>
  ///   Helper for TDextServices to add Persistence features.
  /// </summary>
  TDextPersistenceServicesHelper = record helper for TDextServices
  public
    /// <summary>
    ///   Registers a DbContext with the dependency injection container using an options instance.
    /// </summary>
    function AddDbContext<T: TDbContext>(const AOptions: TDbContextOptions): TDextServices; overload;

    /// <summary>
    ///   Registers a DbContext with the dependency injection container using a fluent options builder.
    /// </summary>
    function AddDbContext<T: TDbContext>(const ABuilder: TDbContextOptionsBuilder): TDextServices; overload;

    /// <summary>
    ///   Registers a DbContext with the dependency injection container using a fluent builder callback.
    /// </summary>
    function AddDbContext<T: TDbContext>(AConfigurator: TProc<TDbContextOptionsBuilder>): TDextServices; overload;

    /// <summary>
    ///   Registers a DbContext with the dependency injection container.
    /// </summary>
    function AddDbContext<T: TDbContext>(Config: TProc<TDbContextOptions>): TDextServices; overload;
    
    /// <summary>
    ///   Registers a DbContext using configuration section.
    /// </summary>
    function AddDbContext<T: TDbContext>(const Configuration: IConfigurationSection): TDextServices; overload;

    /// <summary>
    ///   Adds logging services to the application.
    /// </summary>
    function AddLogging(const AConfigure: TProc<ILoggingBuilder> = nil): TDextServices;
  end;

  /// <summary>
  ///   Helper class for DbContext dependency injection registration.
  /// </summary>
  TPersistence = class
  public
    /// <summary>
    ///   Registers a DbContext with the dependency injection container using an options instance.
    /// </summary>
    class procedure AddDbContext<T: TDbContext>(Services: IServiceCollection; const AOptions: TDbContextOptions); overload;

    /// <summary>
    ///   Registers a DbContext with the dependency injection container using a fluent options builder.
    /// </summary>
    class procedure AddDbContext<T: TDbContext>(Services: IServiceCollection; const ABuilder: TDbContextOptionsBuilder); overload;

    /// <summary>
    ///   Registers a DbContext with the dependency injection container using a fluent builder callback.
    /// </summary>
    class procedure AddDbContext<T: TDbContext>(Services: IServiceCollection; AConfigurator: TProc<TDbContextOptionsBuilder>); overload;

    /// <summary>
    ///   Registers a DbContext with the dependency injection container.
    /// </summary>
    class procedure AddDbContext<T: TDbContext>(Services: IServiceCollection; Config: TProc<TDbContextOptions>); overload;
  end;

/// <summary>
///   Factory function returning a fluent TDbContextOptionsBuilder.
/// </summary>
function DbContextOptions: TDbContextOptionsBuilder;

implementation

uses
  System.Rtti,
  Dext.MultiTenancy,
  Dext.Configuration.Binder,
  Dext.Specifications.OrderBy; // Added for IServiceProvider, TServiceType

function DbContextOptions: TDbContextOptionsBuilder;
begin
  Result := Dext.Entity.Setup.DbContextOptions;
end;

{ TDextPersistenceServicesHelper }

function TDextPersistenceServicesHelper.AddDbContext<T>(const AOptions: TDbContextOptions): TDextServices;
begin
  TPersistence.AddDbContext<T>(Self.Unwrap, AOptions);
  Result := Self;
end;

function TDextPersistenceServicesHelper.AddDbContext<T>(const ABuilder: TDbContextOptionsBuilder): TDextServices;
begin
  TPersistence.AddDbContext<T>(Self.Unwrap, ABuilder);
  Result := Self;
end;

function TDextPersistenceServicesHelper.AddDbContext<T>(AConfigurator: TProc<TDbContextOptionsBuilder>): TDextServices;
begin
  TPersistence.AddDbContext<T>(Self.Unwrap, AConfigurator);
  Result := Self;
end;

function TDextPersistenceServicesHelper.AddDbContext<T>(Config: TProc<TDbContextOptions>): TDextServices;
begin
  TPersistence.AddDbContext<T>(Self.Unwrap, Config);
  Result := Self;
end;

function TDextPersistenceServicesHelper.AddDbContext<T>(const Configuration: IConfigurationSection): TDextServices;
begin
  Result := AddDbContext<T>(
    TProc<TDbContextOptions>(
      procedure(Options: TDbContextOptions)
      begin
        TConfigurationBinder.Bind(Configuration, Options);
      end));
end;

function TDextPersistenceServicesHelper.AddLogging(const AConfigure: TProc<ILoggingBuilder>): TDextServices;
begin
  TServiceCollectionLoggingExtensions.AddLogging(Self.Unwrap, AConfigure);
  Result := Self;
end;

{ TPersistence }

class procedure TPersistence.AddDbContext<T>(Services: IServiceCollection; const AOptions: TDbContextOptions);
begin
  AddDbContext<T>(Services,
    procedure(Options: TDbContextOptions)
    var
      Pair: TPair<string, string>;
    begin
      Options.DriverName := AOptions.DriverName;
      Options.ConnectionString := AOptions.ConnectionString;
      Options.ConnectionDefName := AOptions.ConnectionDefName;
      Options.ConnectionDefString := AOptions.ConnectionDefString;
      for Pair in AOptions.Params do
        Options.Params.AddOrSetValue(Pair.Key, Pair.Value);
      Options.Pooling := AOptions.Pooling;
      Options.PoolMax := AOptions.PoolMax;
      Options.Optimizations := AOptions.Optimizations;
      Options.Dialect := AOptions.Dialect;
      Options.CustomConnection := AOptions.CustomConnection;
      Options.NamingStrategy := AOptions.NamingStrategy;
      Options.Naming := AOptions.Naming;
      Options.OnLog := AOptions.OnLog;
      Options.BulkBatchSize := AOptions.BulkBatchSize;
    end);
end;

class procedure TPersistence.AddDbContext<T>(Services: IServiceCollection; const ABuilder: TDbContextOptionsBuilder);
var
  Options: TDbContextOptions;
begin
  Options := ABuilder.Build;
  try
    AddDbContext<T>(Services, Options);
  finally
    Options.Free;
  end;
end;

class procedure TPersistence.AddDbContext<T>(Services: IServiceCollection; AConfigurator: TProc<TDbContextOptionsBuilder>);
var
  Builder: TDbContextOptionsBuilder;
begin
  Builder := TDbContextOptionsBuilder.Create;
  if Assigned(AConfigurator) then
    AConfigurator(Builder);
  AddDbContext<T>(Services, Builder);
end;

class procedure TPersistence.AddDbContext<T>(Services: IServiceCollection; Config: TProc<TDbContextOptions>);
var
  TemplateOptions: TDbContextOptions;
  DriverName: string;
  ConnectionString: string;
  ConnectionDefName: string;
  ConnectionDefString: string;
  Pooling: Boolean;
  PoolMax: Integer;
  Optimizations: TFireDACOptimizations;
  DialectOverride: ISQLDialect;
  NamingStrategy: INamingStrategy;
  ParamsText: string;
  SL: TStringList;
  Pair: TPair<string, string>;
begin
  // 1. Process configuration ONCE during registration to capture stable values
  TemplateOptions := TDbContextOptions.Create;
  try
    if Assigned(Config) then
      Config(TemplateOptions);
      
    // 2. Capture stable values into local variables for the closure
    DriverName := TemplateOptions.DriverName;
    ConnectionString := TemplateOptions.ConnectionString;
    ConnectionDefName := TemplateOptions.ConnectionDefName;
    ConnectionDefString := TemplateOptions.ConnectionDefString;
    Pooling := TemplateOptions.Pooling;
    PoolMax := TemplateOptions.PoolMax;
    Optimizations := TemplateOptions.Optimizations;
    DialectOverride := TemplateOptions.Dialect;
    NamingStrategy := TemplateOptions.BuildNamingStrategy;
    
    // Convert dictionary to local copy for capture (capturing strings for automatic lifecycle)
    SL := TStringList.Create;
    try
      for Pair in TemplateOptions.Params do
        SL.Values[Pair.Key] := Pair.Value;
      ParamsText := SL.Text;
    finally
      SL.Free;
    end;

    Services.AddScoped(
      TServiceType.FromClass(T),
      T,
      function(Provider: IServiceProvider): TObject
      var
        Connection: IDbConnection;
        FDConn: TFDConnection;
        Dialect: ISQLDialect;
        DetectedDialect: TDatabaseDialect;
        DefName: string;
        LocalParams: TStringList;
        TenantProvider: ITenantProvider;
      begin
        // Factory execution: use captured values ONLY (avoids EInvalidPointer in multi-threaded closures)
        FDConn := TFDConnection.Create(nil);
        try
          if ConnectionDefString <> '' then
          begin
            DefName := ConnectionDefName;
            if DefName = '' then DefName := 'DextMemoryDef_' + IntToHex(ConnectionDefString.GetHashCode, 8);
            TDextFireDACManager.Instance.RegisterConnectionDefFromString(DefName, ConnectionDefString);
            FDConn.ConnectionDefName := DefName;
          end
          else if ConnectionDefName <> '' then
          begin
            FDConn.ConnectionDefName := ConnectionDefName;
          end
          else if Pooling then
          begin
             LocalParams := TStringList.Create;
             try
               LocalParams.Text := ParamsText;
               DefName := TDextFireDACManager.Instance.RegisterConnectionDef(
                 DriverName, 
                 LocalParams, 
                 PoolMax
               );
               FDConn.ConnectionDefName := DefName;
             finally
               LocalParams.Free;
             end;
             TDextFireDACManager.Instance.ApplyResourceOptions(FDConn, Optimizations);
          end
          else
          begin
            if ConnectionString <> '' then
              FDConn.ConnectionString := ConnectionString
            else if DriverName <> '' then
              FDConn.DriverName := DriverName;

            if ParamsText <> '' then
              FDConn.Params.Text := FDConn.Params.Text + ParamsText;

            TDextFireDACManager.Instance.ApplyResourceOptions(FDConn, Optimizations);
          end;
          
          FDConn.Open; 
        except
           FDConn.Free;
           raise;
        end;

        Connection := TFireDACConnection.Create(FDConn, True); // Owns FDConn

        // Dialect Resolution
        Dialect := DialectOverride;
        if Dialect = nil then
        begin
          DetectedDialect := TDialectFactory.DetectDialect(DriverName);
          if DetectedDialect <> ddUnknown then
             Dialect := TDialectFactory.CreateDialect(DetectedDialect)
          else
             Dialect := TSQLiteDialect.Create;
        end;

        // The tenant provider of this scope, when the application registered one
        // (TMultiTenancyMiddleware fills it per request). Without it the context
        // would never filter by tenant.
        TenantProvider := nil;
        Supports(Provider.GetServiceAsInterface(
          TServiceType.FromInterface(TypeInfo(ITenantProvider))),
          ITenantProvider, TenantProvider);

        // Create Context instance
        Result := TDbContextClass(T).Create(Connection, Dialect, NamingStrategy,
          TenantProvider);
      end
    );
  finally
    TemplateOptions.Free;
  end;
end;


end.
