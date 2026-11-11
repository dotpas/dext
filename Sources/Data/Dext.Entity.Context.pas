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
unit Dext.Entity.Context;

interface

uses
  System.SysUtils,
  System.SyncObjs,
  Data.DB,
  System.TypInfo,
  System.Rtti,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Collections,
  Dext.Collections.Pool,
  Dext.Entity.Naming,
  Dext.Entity.Mapping,
  Dext.Entity.Core,
  Dext.Entity.DbSet,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Dialects,
  Dext.Entity.Setup,
  Dext.Entity.Sequences,
  Dext.Entity.Tenancy,
  Dext.MultiTenancy,
  Dext.Entity.Attributes,
  Dext.Entity.LazyLoading,
  Dext.Specifications.Interfaces,
  Dext,
  Dext.Entity.TypeSystem,
  Dext.Specifications.Fluent,
  Dext.Specifications.Types,
  Dext.Core.Reflection,
  Dext.Threading.Sync,
  Dext.Threading.Async,
  Dext.Logging.Tracing,
  Dext.Entity.FastQuery;

type
  TFluentExpression = Dext.Specifications.Types.TFluentExpression;
  // TypeSystem
  TPropertyInfo = Dext.Entity.TypeSystem.TPropertyInfo;
  TDbContext = class;

  /// <summary>
  ///   Represents the shadow state of an entity containing properties not mapped to the class structure.
  /// </summary>
  TEntityShadowState = class
  private
    FShadowValues: IDictionary<string, TValue>;
    FModifiedProperties: IDictionary<string, Boolean>;
    FExplicitlyModified: IDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    property ShadowValues: IDictionary<string, TValue> read FShadowValues;
    property ModifiedProperties: IDictionary<string, Boolean> read FModifiedProperties;
    /// <summary>
    ///   Properties marked with Entry(...).Member(...).IsModified := True.
    ///   DetectChanges keeps them modified even when the current value equals
    ///   the snapshot: setting a value back to its default (0, '', False,
    ///   null) on an entity attached for update is still a change to write.
    /// </summary>
    property ExplicitlyModified: IDictionary<string, Boolean> read FExplicitlyModified;
  end;

  /// <summary>
  ///   Manages the tracking of entity changes within the context.
  /// </summary>
  TChangeTracker = class(TInterfacedObject, IChangeTracker)
  private
    FTrackedEntities: IDictionary<TObject, TEntityState>;
    FShadowStates: IDictionary<TObject, TEntityShadowState>;
    FMapProvider: TFunc<PTypeInfo, TEntityMap>;
    function MapOf(const AEntity: TObject): TEntityMap;
    function IsPersisted(const AHandler: IPropertyHandler; const AMap: TEntityMap): Boolean;
    procedure TakeSnapshot(const AEntity: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure DetectChanges;
    /// <summary>
    ///   Starts tracking an entity with a specific state.
    /// </summary>
    procedure Track(const AEntity: TObject; AState: TEntityState);
    
    /// <summary>
    ///   Removes the entity from tracking.
    /// </summary>
    procedure Remove(const AEntity: TObject);
    
    /// <summary>
    ///   Gets the current state (Added, Modified, Deleted, Unchanged) of the entity.
    /// </summary>
    function GetState(const AEntity: TObject): TEntityState;
    
    /// <summary>
    ///   Checks if there are pending changes in the context.
    /// </summary>
    function HasChanges: Boolean;
    
    /// <summary>
    ///   Accepts all pending changes and synchronizes the tracker with the database.
    /// </summary>
    procedure AcceptAllChanges;
    
    /// <summary>
    ///   Clears all tracked entities.
    /// </summary>
    procedure Clear;
    function GetTrackedEntities: IDictionary<TObject, TEntityState>;
    
    // Shadow Property Methods
    /// <summary>
    ///   Gets the values of "Shadow Properties" (infrastructure properties that do not exist in the class).
    /// </summary>
    function GetShadowState(const AEntity: TObject): TEntityShadowState;

    /// <summary>
    ///   Resolves the entity map of a type. The context sets it, so DetectChanges and the
    ///   snapshots only consider the properties that are persisted as columns.
    /// </summary>
    property MapProvider: TFunc<PTypeInfo, TEntityMap> read FMapProvider write FMapProvider;
  end;

  /// <summary>
  ///   Provides tracking and state access for a single scalar property of an entity.
  /// </summary>
  TPropertyEntry = class(TInterfacedObject, IPropertyEntry)
  private
    FContext: TDbContext;
    FEntity: TObject;
    FPropName: string;
    FIsShadow: Boolean;
  public
    constructor Create(const AContext: TDbContext; const AEntity: TObject; const APropName: string);
    function GetCurrentValue: TValue;
    procedure SetCurrentValue(const AValue: TValue);
    function GetIsModified: Boolean;
    procedure SetIsModified(const AValue: Boolean);
  end;

  /// <summary>
  ///   Provides tracking and operations for a collection navigation property (One-to-Many / Many-to-Many).
  /// </summary>
  TCollectionEntry = class(TInterfacedObject, ICollectionEntry)
  private
    FContext: TDbContext;
    FParent: TObject;
    FPropName: string;
  public
    constructor Create(const AContext: TDbContext; const AParent: TObject; const APropName: string);
    procedure Load;
  end;

  /// <summary>
  ///   Provides tracking and operations for a reference navigation property (Many-to-One / One-to-One).
  /// </summary>
  TReferenceEntry = class(TInterfacedObject, IReferenceEntry)
  private
    FContext: TDbContext;
    FParent: TObject;
    FPropName: string;
  public
    constructor Create(const AContext: TDbContext; const AParent: TObject; const APropName: string);
    procedure Load;
  end;

  /// <summary>
  ///   Provides tracking metadata and member navigation for an entity.
  /// </summary>
  TEntityEntry = class(TInterfacedObject, IEntityEntry)
  private
    FContext: TDbContext;
    FEntity: TObject;
  public
    constructor Create(const AContext: TDbContext; const AEntity: TObject);
    function Collection(const APropName: string): ICollectionEntry;
    function Reference(const APropName: string): IReferenceEntry;
    function Member(const APropName: string): IPropertyEntry;
  end;

  /// <summary>
  ///   TDbContext is the heart of the Dext ORM, implementing the Unit of Work pattern.
  ///   It manages the database connection, transactions, change tracking, and 
  ///   repository exposure (DbSets).
  /// </summary>
  /// <remarks>
  ///   This class disables reference counting (RefCounting) to facilitate integration 
  ///   with Dependency Injection and avoid destruction conflicts. The lifecycle should be 
  ///   managed by the DI Container or manually via Free/Destroy.
  /// </remarks>
  TDbContext = class(TObject, IDbContext, IPoolable)
  private
    FConnection: IDbConnection;
    FDialect: ISQLDialect;
    FNamingStrategy: INamingStrategy;
    FModelBuilder: TModelBuilder; // Model Builder
    FOwnsModelBuilder: Boolean;
    FTransaction: IDbTransaction;
    FCache: IDictionary<PTypeInfo, IInterface>; // Cache for DbSets
    FChangeTracker: IChangeTracker;
    FTenantProvider: ITenantProvider;
    FTenantConfigApplied: Boolean;
    FLastAppliedTenantId: string;
    FOnLog: TProc<string>;
    FProxies: IList<TObject>;
    FBulkBatchSize: Integer;
    procedure SetOnLog(const AValue: TProc<string>);
    function GetOnLog: TProc<string>;
    procedure ApplyTenantConfig(ACreateSchema: Boolean = False);
    function GetModelBuilder: TModelBuilder;
    procedure EnsureSequence(const ASequenceName: string; AAllocationSize: Integer = 1);
    function GetSortedTypes(const ATypes: TArray<PTypeInfo>): IList<PTypeInfo>;
  protected
    // IDbContext Implementation
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
    
    /// <summary>
    ///   Override this method to configure fluent mapping (Fluent API).
    /// </summary>
    procedure OnModelCreating(Builder: TModelBuilder); virtual;
    
    /// <summary>
    ///   Override to configure context options (Connection String, Dialects, etc.) 
    ///   at runtime.
    /// </summary>
    procedure OnConfiguring(Options: TDbContextOptions); virtual;
    function CreateDynamicDbSet(AEntityType: PTypeInfo): IDbSet; virtual;
    
  public
    class var FModelCache: IDictionary<TClass, TModelBuilder>;
    class var FModelLock: TDextMREW; // For thread safety (D.1)
    
    constructor Create(const AConnection: IDbConnection; const ADialect: ISQLDialect = nil; const ANamingStrategy: INamingStrategy = nil; const ATenantProvider: ITenantProvider = nil); overload;
    /// <summary>
    ///   Initializes the context based on a configurable options object.
    /// </summary>
    constructor Create(const AOptions: TDbContextOptions; const ATenantProvider: ITenantProvider = nil); overload;
    /// <summary>
    ///   Initializes the context based on a fluent options builder.
    /// </summary>
    constructor Create(const ABuilder: TDbContextOptionsBuilder; const ATenantProvider: ITenantProvider = nil); overload;
    destructor Destroy; override;
    
    class constructor Create;
    class destructor Destroy;
    
    /// <summary>
    ///   Returns the current database connection.
    /// </summary>
    function Connection: IDbConnection;
    
    /// <summary>
    ///   Returns the configured SQL dialect (PostgreSQL, SQL Server, etc.).
    /// </summary>
    function Dialect: ISQLDialect;
    function NamingStrategy: INamingStrategy;
    function ModelBuilder: TModelBuilder; // Expose ModelBuilder
    function GetTenantProvider: ITenantProvider;
    function BulkBatchSize: Integer;
    procedure SetBulkBatchSize(const AValue: Integer);
    
    /// <summary>
    ///   Starts an explicit transaction on the current connection.
    /// </summary>
    procedure BeginTransaction;
    
    /// <summary>
    ///   Commits the changes of the current transaction.
    /// </summary>
    procedure Commit;
    
    /// <summary>
    ///   Discards the changes of the current transaction.
    /// </summary>
    procedure Rollback;
    function InTransaction: Boolean;
    
    /// <summary>
    ///   Resets pending transactions and clears ChangeTracker state for object pooling (S58).
    /// </summary>
    procedure ResetState;
    
    /// <summary>
    ///   Gets the weakly typed interface of a DbSet for the provided entity type.
    /// </summary>
    function DataSet(AEntityType: PTypeInfo): IDbSet;

    /// <summary>
    ///   Creates a fast SQL query execution pipeline directly streaming UTF-8 JSON output.
    /// </summary>
    function UseSql(const ASql: string): IDextFastQuery;

    /// <summary>
    ///   Executes a raw SQL query and hydrates the results into a typed list of DTOs/POCO objects.
    /// </summary>
    function SqlQuery<T: class, constructor>(const ASql: string; const AParams: array of TValue): IList<T>; overload;
    function SqlQuery<T: class, constructor>(const ASql: string): IList<T>; overload;

    /// <summary>
    ///   Executes a raw SQL query and returns the first hydrated result, or nil if no records match.
    /// </summary>
    function SqlQueryFirst<T: class, constructor>(const ASql: string; const AParams: array of TValue): T; overload;
    function SqlQueryFirst<T: class, constructor>(const ASql: string): T; overload;

    /// <summary>
    ///   Preloads the DbSet cache to optimize future resolutions.
    /// </summary>
    procedure PreloadDbSets;
    
    /// <summary>
    ///   Ensures that the database and tables exist (Code-First Evolution).
    /// </summary>
    function EnsureCreated: Boolean;
    procedure ExecuteSchemaSetup;
    
    /// <summary>
    ///   Synchronizes all changes in tracked entities (Added, Modified, Deleted) 
    ///   with the database in an atomic transaction.
    /// </summary>
    /// <returns>The number of affected rows in the database.</returns>
    function SaveChanges: Integer;
    /// <summary>
    ///   Asynchronous version of SaveChanges for non-blocking operations.
    /// </summary>
    function SaveChangesAsync: TAsyncBuilder<Integer>;
    
    /// <summary>
    ///   Clears the tracker and the context's local cache.
    /// </summary>
    procedure Clear;
    
    /// <summary>
    ///   Unbinds all entities from change tracking.
    /// </summary>
    procedure DetachAll;
    procedure Detach(const AEntity: TObject);
    procedure ExecuteProcedure(const ADto: TObject);
    /// <summary>
    ///   Access to the context's Change Tracker.
    /// </summary>
    function ChangeTracker: IChangeTracker;
    
    function GetMapping(AType: PTypeInfo): TObject;
    
    /// <summary>
    ///   Gets the typed repository (DbSet) for the entity class T.
    /// </summary>
    function Entities<T: class>: IDbSet<T>;
    
    /// <summary>
    ///   Provides access to metadata and state control for a specific instance.
    /// </summary>
    function Entry(const AEntity: TObject): IEntityEntry;
    procedure TrackProxy(const AProxy: TObject);
    
    /// <summary>
    ///   Event to intercept and log SQL and internal commands (Observability).
    /// </summary>
    property OnLog: TProc<string> read GetOnLog write SetOnLog;
  end;

implementation

uses
  System.Variants,
  System.IOUtils,
  Dext.Utils,
  Dext.Validation,
  Dext.Entity.Validator,
  Dext.DI.Core,
  Dext.DI.Interfaces;

{ Helper Functions }

/// <summary>
///   Unwraps Nullable&lt;T&gt; values and validates if FK is valid (non-zero for integers, non-empty for strings).
/// </summary>
function TryUnwrapAndValidateFK(var AValue: TValue): Boolean;
var
  RType: TRttiType;
  TypeName: string;
  Fields: TArray<TRttiField>;
  HasValueField, ValueField: TRttiField;
  HasValue: Boolean;
  Instance: Pointer;
  Field: TRttiField;
  HasValueVal: TValue;
begin
  Result := False;
  
  // Handle Nullable<T> unwrapping
  if AValue.Kind = tkRecord then
  begin
    RType := TReflection.Context.GetType(AValue.TypeInfo);
    if RType <> nil then
    begin
      TypeName := RType.Name;
      
      // Check if it's a Nullable<T> by name (Delphi doesn't generate RTTI for generic record properties)
      if TypeName.StartsWith('Nullable<') or TypeName.StartsWith('TNullable') then
      begin
        // Access fields directly since GetProperty won't work for generic records
        Fields := RType.GetFields;
        HasValueField := nil;
        ValueField := nil;
        
        // Find fHasValue and fValue fields
        for Field in Fields do
        begin
          if Pos('hasvalue', LowerCase(Field.Name)) > 0 then
            HasValueField := Field
          else if SameText(Field.Name, 'fvalue') then
            ValueField := Field;
        end;
        
        if (HasValueField <> nil) and (ValueField <> nil) then
        begin
          Instance := AValue.GetReferenceToRawData;
          
          // Check HasValue - it can be a string (Spring4D) or Boolean
          HasValueVal := HasValueField.GetValue(Instance);
          if HasValueVal.Kind = tkUString then
            HasValue := HasValueVal.AsString <> ''
          else if HasValueVal.Kind = tkEnumeration then
            HasValue := HasValueVal.AsBoolean
          else
            HasValue := False;
            
          if not HasValue then Exit; // Null, nothing to load
          
          // Get the actual value
          AValue := ValueField.GetValue(Instance);
        end
        else
          Exit; // Couldn't find fields, treat as invalid
      end;
    end;
  end;

  // Smart Properties (IntType, StringType...) are records that wrap the value
  TReflection.TryUnwrapProp(AValue, AValue);

  if AValue.IsEmpty then Exit;

  // Validate based on type
  if AValue.Kind in [tkInteger, tkInt64] then
    Result := AValue.AsInt64 <> 0
  else if AValue.Kind in [tkString, tkUString, tkWString, tkLString] then
    Result := AValue.AsString <> ''
  else
    Result := True; // For other types like GUID, assume valid if not empty
end;

{ TDbContext }

type
  TEntityNode = class
  public
    TypeInfo: PTypeInfo;
    DbSet: IDbSet;
    Dependencies: IList<PTypeInfo>;
    constructor Create;
    destructor Destroy; override;
  end;

const
  // Key for caching based on class type
  CACHE_KEY = 'Model';

class constructor TDbContext.Create;
begin
  FModelCache := TCollections.CreateDictionary<TClass, TModelBuilder>(True);
  // TDextMREW is a record
end;

 class destructor TDbContext.Destroy;
begin
  FModelCache := nil;
end;

constructor TDbContext.Create(const AConnection: IDbConnection; const ADialect: ISQLDialect; const ANamingStrategy: INamingStrategy; const ATenantProvider: ITenantProvider);
var
  Tracker: TChangeTracker;
begin
  inherited Create;
  FConnection := AConnection;
  
  if ADialect <> nil then
    FDialect := ADialect
  else if (FConnection <> nil) and (FConnection.Dialect <> ddUnknown) then
    FDialect := TDialectFactory.CreateDialect(FConnection.Dialect)
  else
    FDialect := nil; // Will likely cause issues if query generation is attempted without dialect

  if FDialect = nil then
  begin
     // Optional: Raise warning or default to generic?
     // We leave it nil, it might be set later or cause runtime error if used.
  end;
  
  if ANamingStrategy <> nil then
    FNamingStrategy := ANamingStrategy
  else
    FNamingStrategy := TDefaultNamingStrategy.Create; // Default
    
  FCache := TCollections.CreateDictionary<PTypeInfo, IInterface>;
  Tracker := TChangeTracker.Create;
  Tracker.MapProvider :=
    function(AType: PTypeInfo): TEntityMap
    begin
      if FModelBuilder <> nil then
        Result := FModelBuilder.GetMap(AType)
      else
        Result := nil;
    end;
  FChangeTracker := Tracker;
  FTenantProvider := ATenantProvider;
  FTenantConfigApplied := False;
  FProxies := TCollections.CreateList<TObject>(True);
  FBulkBatchSize := 100;
  
  // Model Caching Logic
  FModelLock.BeginRead;
  try
    if FModelCache.TryGetValue(Self.ClassType, FModelBuilder) then
    begin
       FOwnsModelBuilder := False;
       Exit; // FAST PATH
    end;
  finally
    FModelLock.EndRead;
  end;

  FModelLock.BeginWrite;
  try
    if not FModelCache.TryGetValue(Self.ClassType, FModelBuilder) then
    begin
      FModelBuilder := TModelBuilder.Create;
      // Initialize Model. If the model is invalid (for example, an unknown property
      // name), the builder is not cached and nobody owns it yet: free it here.
      try
        OnModelCreating(FModelBuilder);
        // Prototype.Entity<T> and the join helpers read the global builder,
        // not this context's one. Apply the same model there once, so a
        // fluent-only mapping (no [Table]) reaches them too.
        if FModelBuilder <> TModelBuilder.Instance then
          OnModelCreating(TModelBuilder.Instance);
      except
        FModelBuilder.Free;
        FModelBuilder := nil;
        raise;
      end;
      
      FModelCache.Add(Self.ClassType, FModelBuilder);
    end;
    // We reuse the cached builder. Do NOT own it.
    FOwnsModelBuilder := False;
  finally
    FModelLock.EndWrite;
  end;

  PreloadDbSets;
end;

constructor TDbContext.Create(const AOptions: TDbContextOptions;
  const ATenantProvider: ITenantProvider);
begin
  // Allow derived classes to configure options (e.g. Naming Strategy)
  OnConfiguring(AOptions);
  
  Self.Create(AOptions.BuildConnection, AOptions.BuildDialect, AOptions.BuildNamingStrategy, ATenantProvider);
  Self.OnLog := AOptions.OnLog;
  Self.FBulkBatchSize := AOptions.BulkBatchSize;
end;

constructor TDbContext.Create(const ABuilder: TDbContextOptionsBuilder;
  const ATenantProvider: ITenantProvider);
var
  Options: TDbContextOptions;
begin
  Options := ABuilder.Build;
  try
    Create(Options, ATenantProvider);
  finally
    Options.Free;
  end;
end;

procedure TDbContext.OnConfiguring(Options: TDbContextOptions);
begin
  // Virtual method implies do nothing by default
end;

destructor TDbContext.Destroy;
begin
  // Clear ChangeTracker before freeing DbSets (which free entities).
  // This prevents ChangeTracker from holding dangling pointers during its destruction.
  if FChangeTracker <> nil then
    FChangeTracker.Clear;
    
  if FConnection <> nil then
    FConnection.Disconnect;
    
  // 1. Clear Proxies first. This restores original VMTs while entity instances
  // are still held by IdentityMaps in DbSets.
  FProxies := nil; 
  
  // 2. Clear DbSets second. This will call Free on entity instances.
  // Since proxies were unproxified in step 1, they will destroy as normal objects.
  FCache := nil;   
  
  if FOwnsModelBuilder then
    FModelBuilder.Free;
  inherited;
end;

procedure TDbContext.SetOnLog(const AValue: TProc<string>);
begin
  FOnLog := AValue;
  if FConnection <> nil then
    FConnection.OnLog := AValue;
end;

function TDbContext.GetOnLog: TProc<string>;
begin
  Result := FOnLog;
end;

function TDbContext.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    Result := 0
  else
    Result := E_NOINTERFACE;
end;

function TDbContext._AddRef: Integer;
begin
  Result := -1; // Disable ref counting
end;

function TDbContext._Release: Integer;
begin
  Result := -1; // Disable ref counting
end;

function TDbContext.Connection: IDbConnection;
begin
  Result := FConnection;
end;

function TDbContext.Dialect: ISQLDialect;
begin
  Result := FDialect;
end;

function TDbContext.NamingStrategy: INamingStrategy;
begin
  Result := FNamingStrategy;
end;

function TDbContext.GetModelBuilder: TModelBuilder;
begin
  Result := FModelBuilder;
end;

function TDbContext.ModelBuilder: TModelBuilder;
begin
  Result := FModelBuilder;
end;

function TDbContext.GetTenantProvider: ITenantProvider;
begin
  Result := FTenantProvider;
end;

function TDbContext.BulkBatchSize: Integer;
begin
  Result := FBulkBatchSize;
end;

procedure TDbContext.SetBulkBatchSize(const AValue: Integer);
begin
  FBulkBatchSize := AValue;
end;

procedure TDbContext.OnModelCreating(Builder: TModelBuilder);
begin
  // Default implementation does nothing.
  // Override this in your derived context to configure mappings.
end;

procedure TDbContext.TrackProxy(const AProxy: TObject);
begin
  if AProxy <> nil then
    FProxies.Add(AProxy);
end;

procedure TDbContext.PreloadDbSets;
var
  typ : TRttiType;
  props :  TArray<TRttiProperty>;
  Prop : TRttiProperty;
  IntfType: TRttiType;
  Val: TValue;
  DbSet: IDbSet;
begin
   Typ := TReflection.Context.GetType(self.classtype);
   Props := Typ.GetProperties;
     for Prop in Props do
     begin
       // ignore any properties that are [NotMapped].
       if Prop.HasAttribute<NotMappedAttribute> then
         continue;

       // assume that properties that hold an interface are likely models (IDbSet<T>)
       if Prop.IsReadable and (Prop.PropertyType.TypeKind = tkInterface) then
       begin
         // Capture the property name for naming discovery (e.g. "Customers" -> "customers")
         // We need to find the generic type T from IDbSet<T>
         IntfType := Prop.PropertyType;
         if IntfType.Name.StartsWith('IDbSet<') then
         begin
            // This is a simple heuristic. Better: check GUID or use RTTI to find the entity type.
            // But usually, the property name is exactly what we want as a table name placeholder.
            
            // Try to extract T from IDbSet<T> RTTI if possible, 
            // but even simpler: when the getter is called by Prop.GetValue(Self), 
            // Entities<T> is called, which registers the type. 
            // We just need to associate this specific property name with the type T.
            
             Val := Prop.GetValue(Self);
             try
               if (not Val.IsEmpty) and Supports(Val.AsInterface, IDbSet, DbSet) then
               begin
                 // Register this property name as the "Discovery Name" for this entity type
                 TModelBuilder.Instance.RegisterDiscoveryName(DbSet.EntityType, Prop.Name);
               end;
             finally
               Val := TValue.Empty;
             end;
         end;
       end;
     end;
end;

function TDbContext.GetMapping(AType: PTypeInfo): TObject;
begin
  Result := FModelBuilder.GetMap(AType);
end;

procedure TDbContext.ApplyTenantConfig(ACreateSchema: Boolean);
var
  Sql: string;
  CurrentTenantId: string;
  Cmd: IDbCommand;
begin
  CurrentTenantId := '';
  if (FTenantProvider <> nil) and (FTenantProvider.Tenant <> nil) then
    CurrentTenantId := FTenantProvider.Tenant.Id;

  if (FLastAppliedTenantId = CurrentTenantId) and FTenantConfigApplied and (not ACreateSchema) then Exit;
  
  if (FTenantProvider <> nil) and (FTenantProvider.Tenant <> nil) then
  begin
    // 1. Handle Schema-based tenancy
    if FTenantProvider.Tenant.Schema <> '' then
    begin
      if ACreateSchema then
      begin
        Sql := FDialect.GetCreateSchemaSQL(FTenantProvider.Tenant.Schema);
        if Sql <> '' then
        begin
          Cmd := FConnection.CreateCommand(Sql);
          Cmd.ExecuteNonQuery;
        end;
      end;

      Sql := FDialect.GetSetSchemaSQL(FTenantProvider.Tenant.Schema);
      if Sql <> '' then
      begin
        Cmd := FConnection.CreateCommand(Sql);
        Cmd.ExecuteNonQuery;
      end;
    end;

    // 2. Handle Connection-based tenancy (Tenant per Database)
    if FTenantProvider.Tenant.ConnectionString <> '' then
    begin
      if FConnection.ConnectionString <> FTenantProvider.Tenant.ConnectionString then
      begin
        FConnection.ConnectionString := FTenantProvider.Tenant.ConnectionString;
        // If we are already connected, we need to reconnect with the new string
        if FConnection.IsConnected then
        begin
          FConnection.Disconnect;
          FConnection.Connect;
        end;
      end;
    end;
  end;
  
  FLastAppliedTenantId := CurrentTenantId;
  FTenantConfigApplied := True;
end;

procedure TDbContext.ExecuteSchemaSetup;
begin
  ApplyTenantConfig(False);
end;

procedure TDbContext.BeginTransaction;
begin
  ApplyTenantConfig(False);
  FTransaction := FConnection.BeginTransaction;
end;

procedure TDbContext.Commit;
begin
  if FTransaction <> nil then
  begin
    FTransaction.Commit;
    FTransaction := nil;
  end;
end;

procedure TDbContext.Rollback;
begin
  if FTransaction <> nil then
  begin
    FTransaction.Rollback;
    FTransaction := nil;
  end;
end;

procedure TDbContext.ResetState;
begin
  if InTransaction then
    Rollback;
  if FChangeTracker <> nil then
    FChangeTracker.Clear;
end;

function TDbContext.InTransaction: Boolean;
begin
  Result := FTransaction <> nil;
end;

function TDbContext.DataSet(AEntityType: PTypeInfo): IDbSet;
begin
  ApplyTenantConfig;
  if FCache.ContainsKey(AEntityType) then
    Exit(FCache[AEntityType] as IDbSet);

  // Create the DbSet instance dynamically for this type.
  // This is required when we discover types from ModelBuilder (fluent) 
  // that haven't been accessed via generic Entities<T> properties yet.
  Result := CreateDynamicDbSet(AEntityType);
  if Result <> nil then
    FCache.Add(AEntityType, Result);
end;

function TDbContext.CreateDynamicDbSet(AEntityType: PTypeInfo): IDbSet;
var
  Factory: IDynamicDbSetFactory;
begin
  Factory := ModelBuilder.GetFactory(AEntityType);
  if Factory <> nil then
    Exit(Factory.CreateDbSet(IDbContext(Self)) as IDbSet);

  raise Exception.CreateFmt('Could not create DbSet for type %s. Please ensure TDbSet<%s> is instantiated somewhere or call Entities<%s> to register it.', [AEntityType.Name, AEntityType.Name, AEntityType.Name]);
end;

function TDbContext.Entities<T>: IDbSet<T>;
var
  TypeInfo: PTypeInfo;
  NewSet: IDbSet<T>;
begin
  TypeInfo := System.TypeInfo(T);
  
  if not FCache.ContainsKey(TypeInfo) then
  begin
    // Create the DbSet instance.
    NewSet := TDbSet<T>.Create(IDbContext(Self));
    FCache.Add(TypeInfo, NewSet);
  end;
  
  Result := IDbSet<T>(FCache[TypeInfo]);
end;

procedure TDbContext.EnsureSequence(const ASequenceName: string; AAllocationSize: Integer);
var
  ExistsSQL, CreateSQL: string;
  Cmd: IDbCommand;
  Reader: IDbReader;
  Exists: Boolean;
begin
  if (FDialect = nil) or (FConnection = nil) or (ASequenceName = '') then Exit;
  
  ExistsSQL := FDialect.GetSequenceExistsSQL(ASequenceName);
  Exists := False;
  if ExistsSQL <> '' then
  begin
    try
      Cmd := FConnection.CreateCommand(ExistsSQL);
      Reader := Cmd.ExecuteQuery;
      try
        if Reader <> nil then
          Exists := Reader.Next;
      finally
        if Reader <> nil then
          Reader.Close;
        Reader := nil;
        Cmd := nil;
      end;
    except
      // If the query fails, assume it doesn't exist
    end;
  end;

  if not Exists then
  begin
    CreateSQL := FDialect.GetCreateSequenceSQL(ASequenceName, AAllocationSize);
    if CreateSQL <> '' then
    begin
      try
        Cmd := FConnection.CreateCommand(CreateSQL);
        Cmd.ExecuteNonQuery;
      except
        // Ignore errors (e.g., if it already exists but we couldn't detect it)
      end;
    end;
  end;
end;

function TDbContext.EnsureCreated: Boolean;
var
  Nodes: IList<TEntityNode>;
  Created: IList<PTypeInfo>;
  Typ: TRttiType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  Node: TEntityNode;
  Pair: TPair<PTypeInfo, IInterface>;
  DbSet: IDbSet;
  SQL: string;
  Cmd: IDbCommand;
  CmdIntf: IInterface;
  HasProgress, CanCreate: Boolean;
  i: Integer;
  Map: TEntityMap;
  LMeta: TTypeMetadata;
  DepType: PTypeInfo;
  Dep: PTypeInfo;
  TableName, MapTableName: string;
  Mapping: TObject;
  RType: TRttiType;
  TableAttr: TableAttribute;
  PropMap: TPropertyMap;
begin
  Result := False;
  ApplyTenantConfig(True);
  Nodes := TCollections.CreateList<TEntityNode>(True);
  Created := TCollections.CreateList<PTypeInfo>;
  try
    if FCache.Count = 0 then
      PreloadDBSets;
    
  // Ensure all entities registered in the ModelBuilder (via Fluent API or attributes) 
  // are also present in the cache for schema creation.
  for Map in ModelBuilder.GetMaps do
    DataSet(Map.EntityType);
  // 1. Build Dependency Graph
  for Pair in FCache do
  begin
    if not Supports(Pair.Value, IDbSet, DbSet) then Continue;
    
    Node := TEntityNode.Create;
    Node.TypeInfo := Pair.Key;
    Node.DbSet := DbSet;
    Nodes.Add(Node);
    
    // Analyze Dependencies
    Typ := TReflection.Context.GetType(Pair.Key);
      if Typ = nil then Continue;
      
      for Prop in Typ.GetProperties do
      begin
        for Attr in Prop.GetAttributes do
        begin
          if Attr is ForeignKeyAttribute then
          begin
            // Found a FK. Check if the property type is a class we manage.
            if True then
            begin
               DepType := nil;
               if Prop.PropertyType.TypeKind = tkClass then
                 DepType := Prop.PropertyType.Handle
               else if Prop.PropertyType.TypeKind = tkRecord then
               begin
                 LMeta := TReflection.GetMetadata(Prop.PropertyType.Handle);
                 if (LMeta <> nil) and (LMeta.InnerType <> nil) then
                   DepType := LMeta.InnerType;
               end;
               // Only add dependency if it's in our Cache (managed entity)
               if FCache.ContainsKey(DepType) and (DepType <> Pair.Key) then // Avoid self-dependency
               begin
                 if not Node.Dependencies.Contains(DepType) then
                   Node.Dependencies.Add(DepType);
               end;
            end;
          end;
        end;
      end;
    end;
    
    // 2. Topological Sort / Execution
    while Nodes.Count > 0 do
    begin
      HasProgress := False;
      
      for i := Nodes.Count - 1 downto 0 do
      begin
        Node := Nodes[i];
        CanCreate := True;
        
        // Check if all dependencies are created
        for Dep in Node.Dependencies do
        begin
          if not Created.Contains(Dep) then
          begin
            CanCreate := False;
            Break;
          end;
        end;
        
        if CanCreate then
        begin
          Mapping := GetMapping(Node.TypeInfo);
          // Execute Creation
          SQL := Node.DbSet.GenerateCreateTableScript;
          if SQL <> '' then
          begin
            // Check if table exists first (to support databases without IF NOT EXISTS like Firebird)
            // Note: GenerateCreateTableScript returns "CREATE TABLE Name ...". We need to extract the name.
            // But we already have the name in the Node/DbSet metadata.
            // Actually, we can just use FConnection.TableExists(TableName)
            
            TableName := '';
            MapTableName := '';
            
            if Mapping <> nil then
              MapTableName := Dext.Entity.Mapping.TEntityMap(Mapping).TableName;
              
            if MapTableName <> '' then
            begin
              TableName := MapTableName;
            end
            else
            begin
              // Fallback to Attribute or Naming Strategy if Mapping doesn't specify TableName
              RType := TReflection.Context.GetType(Node.TypeInfo);
              if RType <> nil then
              begin
                TableAttr := RType.GetAttribute<TableAttribute>;
                if TableAttr <> nil then
                  TableName := TableAttr.Name;
              end;
              
              if TableName = '' then
                TableName := FNamingStrategy.GetTableName(Node.TypeInfo.TypeData.ClassType);
            end;
            
            // Quote identifier if needed (Dialect specific)
            // But TableExists expects the name as is (or handles quotes internally)
            // Let's pass the raw name first.
            
            if not FConnection.TableExists(TableName) then
            begin
              if Assigned(FOnLog) then
                FOnLog(SQL);

              try
                CmdIntf := FConnection.CreateCommand(SQL);
                Cmd := IDbCommand(CmdIntf);
                Cmd.ExecuteNonQuery;
                Result := True;
              except
                 on E: Exception do
                 begin
                   if Assigned(FOnLog) then
                     FOnLog('FAILED SQL: ' + SQL);
                   raise; // Propagate the error so the developer knows why it failed
                 end;
              end;
            end;
          end;

          // Ensure sequences are created
          if Mapping <> nil then
          begin
            for PropMap in TEntityMap(Mapping).OrderedProperties do
            begin
              if PropMap.SequenceName <> '' then
                EnsureSequence(PropMap.SequenceName, PropMap.SequenceAllocationSize);
            end;
          end;
          
          Created.Add(Node.TypeInfo);
          Nodes.Delete(i); // Remove from pending
          HasProgress := True;
        end;
      end;
      
      if not HasProgress then
      begin
        // Cycle detected or missing dependency.
        // For now, force create the remaining ones (might fail on FKs, but better than hanging)

        for i := Nodes.Count - 1 downto 0 do
        begin
           Node := Nodes[i];
           SQL := Node.DbSet.GenerateCreateTableScript;
            if SQL <> '' then
            begin
              try
                CmdIntf := FConnection.CreateCommand(SQL);
                Cmd := IDbCommand(CmdIntf);
                Cmd.ExecuteNonQuery;
              except
                 on E: Exception do; // Ignore errors in forced creation
              end;
            end;
           Nodes.Delete(i);
        end;
        Break;
      end;
    end;
    
  finally
    Created := nil;
    Nodes := nil;
  end;
end;

{ TEntityNode }

{ TEntityNode }

constructor TEntityNode.Create;
begin
  Dependencies := TCollections.CreateList<PTypeInfo>;
end;

destructor TEntityNode.Destroy;
begin
  Dependencies := nil;
  inherited;
end;

function TDbContext.GetSortedTypes(const ATypes: TArray<PTypeInfo>): IList<PTypeInfo>;
var
  Nodes: IList<TEntityNode>;
  Node: TEntityNode;
  Created: IList<PTypeInfo>;
  T: PTypeInfo;
  Typ: TRttiType;
  Prop: TRttiProperty;
  Attr: TCustomAttribute;
  DepType: PTypeInfo;
  LMeta: TTypeMetadata;
  HasProgress, CanCreate: Boolean;
  i: Integer;
  Dep: PTypeInfo;
  LTypesList: IList<PTypeInfo>;
begin
  Result := TCollections.CreateList<PTypeInfo>;
  Nodes := TCollections.CreateList<TEntityNode>(True);
  Created := TCollections.CreateList<PTypeInfo>;
  LTypesList := TCollections.CreateList<PTypeInfo>;
  try
    for T in ATypes do
      LTypesList.Add(T);

    for T in LTypesList do
    begin
      Node := TEntityNode.Create;
      Node.TypeInfo := T;
      Nodes.Add(Node);

      Typ := TReflection.Context.GetType(T);
      if Typ = nil then Continue;

      for Prop in Typ.GetProperties do
      begin
        for Attr in Prop.GetAttributes do
        begin
          if Attr is ForeignKeyAttribute then
          begin
            DepType := nil;
            if Prop.PropertyType.TypeKind = tkClass then
              DepType := Prop.PropertyType.Handle
            else if Prop.PropertyType.TypeKind = tkRecord then
            begin
              LMeta := TReflection.GetMetadata(Prop.PropertyType.Handle);
              if (LMeta <> nil) and (LMeta.InnerType <> nil) then
                DepType := LMeta.InnerType;
            end;

            if (DepType <> nil) and (DepType <> T) and
               LTypesList.Contains(DepType) then
            begin
              if not Node.Dependencies.Contains(DepType) then
                Node.Dependencies.Add(DepType);
            end;
          end;
        end;
      end;
    end;

    while Nodes.Count > 0 do
    begin
      HasProgress := False;
      for i := Nodes.Count - 1 downto 0 do
      begin
        Node := Nodes[i];
        CanCreate := True;

        for Dep in Node.Dependencies do
        begin
          if not Created.Contains(Dep) then
          begin
            CanCreate := False;
            Break;
          end;
        end;

        if CanCreate then
        begin
          Created.Add(Node.TypeInfo);
          Result.Add(Node.TypeInfo);
          Nodes.Delete(i);
          HasProgress := True;
        end;
      end;

      if not HasProgress then
      begin
        for i := Nodes.Count - 1 downto 0 do
        begin
          Node := Nodes[i];
          Result.Add(Node.TypeInfo);
          Nodes.Delete(i);
        end;
        Break;
      end;
    end;
  finally
    Created := nil;
    Nodes := nil;
    LTypesList := nil;
  end;
end;

function TDbContext.SaveChanges: Integer;
var
  AddedGroups: IDictionary<PTypeInfo, IList<TObject>>;
  DbSet: IDbSet;
  DeletedGroups: IDictionary<PTypeInfo, IList<TObject>>;
  DIProvider: IServiceProvider;
  Entity: TObject;
  i: Integer;
  Item: TObject;
  ItemType: PTypeInfo;
  List: IList<TObject>;
  Map: TEntityMap;
  Meta: TTypeMetadata;
  ModifiedGroups: IDictionary<PTypeInfo, IList<TObject>>;
  OwnsTransaction: Boolean;
  Pair: TPair<TObject, TEntityState>;
  PropMap: TPropertyMap;
  SeqId: Int64;
  SortedDeletes: IList<PTypeInfo>;
  Span: TSpan;
  TenantAware: ITenantAware;
  Validator: IValidator;
  ValidatorIntf: IInterface;
  ValRes: TValidationResult;
  ValToSet: TValue;
begin
  Span := TTracer.BeginSpan('DbContext.SaveChanges', 'SQL');
  ApplyTenantConfig(False);
  Result := 0;
  if not FChangeTracker.HasChanges then Exit;
 
  OwnsTransaction := not InTransaction;
  if OwnsTransaction then BeginTransaction;
  try
    // 1. Process Inserts (Bulk Optimized)
    AddedGroups := TCollections.CreateDictionary<PTypeInfo, IList<TObject>>;
    try
      for Pair in FChangeTracker.GetTrackedEntities do
      begin
        if Pair.Value = esAdded then
        begin
          Entity := Pair.Key;
          if not AddedGroups.ContainsKey(Entity.ClassInfo) then
            AddedGroups.Add(Entity.ClassInfo, TCollections.CreateList<TObject>);
          
           // Auto-populate TenantId if applicable (Security & Convenience)
           if (FTenantProvider <> nil) and (FTenantProvider.Tenant <> nil) then
           begin
             if Supports(Entity, ITenantAware, TenantAware) then
             begin
                // Always enforce current tenant ID on insert
                TenantAware.TenantId := FTenantProvider.Tenant.Id;
             end;
           end;
 
           // Validate Entity
           Map := nil;
           if FModelBuilder <> nil then
             Map := FModelBuilder.GetMap(Entity.ClassInfo);
 
           // Auto-populate Sequence keys if applicable (S46)
           if Map <> nil then
           begin
             for PropMap in Map.OrderedProperties do
             begin
               if PropMap.IsSequenced then
               begin
                 SeqId := TSequenceManager.Instance.GenerateId(
                   PropMap.SequenceName, PropMap.SequenceAllocationSize,
                   FConnection, FDialect);
                 if PropMap.PropertyType = TypeInfo(Integer) then
                   ValToSet := TValue.From<Integer>(Integer(SeqId))
                 else
                   ValToSet := TValue.From<Int64>(SeqId);
                 TReflection.SetValue(Pointer(Entity), PropMap.Prop, ValToSet);
               end;
             end;
           end;
             
           Meta := TReflection.GetMetadata(Entity.ClassInfo);
           ValidatorIntf := nil;
           if Meta.ValidatorInterfaceType <> nil then
           begin
             DIProvider := TDextServices.DefaultProvider;
             if DIProvider <> nil then
             begin
               try
                 ValidatorIntf := DIProvider.GetServiceAsInterface(
                   TServiceType.FromInterface(Meta.ValidatorInterfaceType));
               except
               end;
             end;
           end;
           
           if (ValidatorIntf <> nil) and 
              Supports(ValidatorIntf, IValidator, Validator) then
           begin
             ValRes := Validator.ValidateInstance(TValue.From<TObject>(Entity));
             try
               if not ValRes.IsValid then
                 raise EValidationException.Create(
                   'Validation failed: ' + ValRes.Errors[0].ErrorMessage);
             finally
               ValRes.Free;
             end;
           end
           else
             TEntityValidator.Validate(Entity, Map);
 
           AddedGroups[Entity.ClassInfo].Add(Entity);
        end;
      end;
 
      for ItemType in GetSortedTypes(AddedGroups.Keys) do
      begin
        List := AddedGroups[ItemType];
        DbSet := DataSet(ItemType);

        if DbSet.IsBulkInsertSafe and (List.Count > 1) then
        begin
          DbSet.PersistAddRange(List.ToArray);
        end
        else
        begin
          for Item in List do
            DbSet.PersistAdd(Item);
        end;
          
        Inc(Result, List.Count);
      end;
    finally
      AddedGroups := nil;
    end;
     
    // 2. Process Updates
    ModifiedGroups := TCollections.CreateDictionary<PTypeInfo, IList<TObject>>;
    try
      for Pair in FChangeTracker.GetTrackedEntities do
      begin
        if Pair.Value = esModified then
        begin
          Entity := Pair.Key;
          
          // Validate Entity
          Map := nil;
          if FModelBuilder <> nil then
            Map := FModelBuilder.GetMap(Entity.ClassInfo);
             
          Meta := TReflection.GetMetadata(Entity.ClassInfo);
          ValidatorIntf := nil;
          if Meta.ValidatorInterfaceType <> nil then
          begin
            DIProvider := TDextServices.DefaultProvider;
            if DIProvider <> nil then
            begin
              try
                ValidatorIntf := DIProvider.GetServiceAsInterface(
                  TServiceType.FromInterface(Meta.ValidatorInterfaceType));
              except
              end;
            end;
          end;
          
          Validator := nil;
          if (ValidatorIntf <> nil) and 
             Supports(ValidatorIntf, IValidator, Validator) then
          begin
            ValRes := Validator.ValidateInstance(TValue.From<TObject>(Entity));
            try
              if not ValRes.IsValid then
                raise EValidationException.Create(
                  'Validation failed: ' + ValRes.Errors[0].ErrorMessage);
            finally
              ValRes.Free;
            end;
          end
          else
            TEntityValidator.Validate(Entity, Map);
 
          if not ModifiedGroups.ContainsKey(Entity.ClassInfo) then
            ModifiedGroups.Add(Entity.ClassInfo, TCollections.CreateList<TObject>);
          ModifiedGroups[Entity.ClassInfo].Add(Entity);
        end;
      end;
 
      for ItemType in GetSortedTypes(ModifiedGroups.Keys) do
      begin
        List := ModifiedGroups[ItemType];
        DbSet := DataSet(ItemType);
        if DbSet.IsBulkUpdateSafe and (List.Count > 1) then
        begin
          DbSet.PersistUpdateRange(List.ToArray);
        end
        else
        begin
          for Item in List do
            DbSet.PersistUpdate(Item);
        end;
        Inc(Result, List.Count);
      end;
    finally
      ModifiedGroups := nil;
    end;
    
    // 3. Process Deletes
    DeletedGroups := TCollections.CreateDictionary<PTypeInfo, IList<TObject>>;
    try
      for Pair in FChangeTracker.GetTrackedEntities do
      begin
        if Pair.Value = esDeleted then
        begin
          Entity := Pair.Key;
          if not DeletedGroups.ContainsKey(Entity.ClassInfo) then
            DeletedGroups.Add(Entity.ClassInfo, TCollections.CreateList<TObject>);
          DeletedGroups[Entity.ClassInfo].Add(Entity);
        end;
      end;
 
      SortedDeletes := GetSortedTypes(DeletedGroups.Keys);
      for i := SortedDeletes.Count - 1 downto 0 do
      begin
        ItemType := SortedDeletes[i];
        List := DeletedGroups[ItemType];
        DbSet := DataSet(ItemType);

        for Item in List do
          FChangeTracker.Remove(Item);
 
        if DbSet.IsBulkDeleteSafe and (List.Count > 1) then
        begin
          DbSet.PersistRemoveRange(List.ToArray);
        end
        else
        begin
          for Item in List do
            DbSet.PersistRemove(Item);
        end;
        Inc(Result, List.Count);
      end;
    finally
      DeletedGroups := nil;
      SortedDeletes := nil;
    end;
    
    if OwnsTransaction then Commit;
    FChangeTracker.AcceptAllChanges;
    Span.SetStatus('Success');
    Span.SetAttribute('affected_rows', Result);
  except
    if OwnsTransaction then Rollback;
    Span.SetStatus('Error', Exception(ExceptObject).Message);
     raise;
   end;
end;

function TDbContext.UseSql(const ASql: string): IDextFastQuery;
begin
  Result := TDextFastQuery.Create(Connection, ASql);
end;

function TDbContext.SqlQuery<T>(const ASql: string; const AParams: array of TValue): IList<T>;
var
  Cmd: IDbCommand;
  Reader: IDbReader;
  List: TList<T>;
  Item: T;
  Hydrator: TDextDtoHydrator;
  I: Integer;
  ParamsArray: TArray<TValue>;
begin
  List := TList<T>.Create(True);
  try
    Cmd := Connection.CreateCommand(ASql);
    if Length(AParams) > 0 then
    begin
      SetLength(ParamsArray, Length(AParams));
      for I := 0 to Length(AParams) - 1 do
        ParamsArray[I] := AParams[I];
      Cmd.BindSequentialParams(ParamsArray);
    end;

    Reader := Cmd.ExecuteQuery;
    Hydrator := TDextDtoHydrator.Create(TypeInfo(T), Reader);
    try
      while Reader.Next do
      begin
        Item := T.Create;
        try
          Hydrator.Hydrate(Item, Reader);
          List.Add(Item);
        except
          Item.Free;
          raise;
        end;
      end;
    finally
      Hydrator.Free;
    end;

    Result := List;
  except
    List.Free;
    raise;
  end;
end;

function TDbContext.SqlQuery<T>(const ASql: string): IList<T>;
begin
  Result := SqlQuery<T>(ASql, []);
end;

function TDbContext.SqlQueryFirst<T>(const ASql: string; const AParams: array of TValue): T;
var
  Cmd: IDbCommand;
  Reader: IDbReader;
  Hydrator: TDextDtoHydrator;
  I: Integer;
  ParamsArray: TArray<TValue>;
begin
  Result := nil;
  Cmd := Connection.CreateCommand(ASql);
  if Length(AParams) > 0 then
  begin
    SetLength(ParamsArray, Length(AParams));
    for I := 0 to Length(AParams) - 1 do
      ParamsArray[I] := AParams[I];
    Cmd.BindSequentialParams(ParamsArray);
  end;

  Reader := Cmd.ExecuteQuery;
  if Reader.Next then
  begin
    Hydrator := TDextDtoHydrator.Create(TypeInfo(T), Reader);
    try
      Result := T.Create;
      try
        Hydrator.Hydrate(Result, Reader);
      except
        Result.Free;
        raise;
      end;
    finally
      Hydrator.Free;
    end;
  end;
end;

function TDbContext.SqlQueryFirst<T>(const ASql: string): T;
begin
  Result := SqlQueryFirst<T>(ASql, []);
end;

function TDbContext.SaveChangesAsync: TAsyncBuilder<Integer>;
begin
  if (FConnection <> nil) and not FConnection.Pooled then
    raise Exception.Create('SaveChangesAsync requires a pooled connection to ensure thread safety.');

  Result := TAsyncTask.Run<Integer>(
    TFunc<Integer>(
      function: Integer
      begin
        Result := SaveChanges;
      end
    )
  );
end;

procedure TDbContext.Clear;
var
  SetIntf: IInterface;
  DbSet: IDbSet;
begin
  // Clear Change Tracker
  FChangeTracker.Clear;
  
  // Clear Identity Map of all cached DbSets
  for SetIntf in FCache.Values do
  begin
    if Supports(SetIntf, IDbSet, DbSet) then
    begin
      DbSet.Clear;
    end;
  end;
end;

procedure TDbContext.DetachAll;
var
  SetIntf: IInterface;
  DbSet: IDbSet;
begin
  // Clear Change Tracker (Stop tracking everything)
  FChangeTracker.Clear;
  
  // Detach all entities in all DbSets
  for SetIntf in FCache.Values do
  begin
    if Supports(SetIntf, IDbSet, DbSet) then
    begin
      DbSet.DetachAll;
    end;
  end;
end;

procedure TDbContext.Detach(const AEntity: TObject);
begin
  DataSet(AEntity.ClassInfo).Detach(AEntity);
end;

procedure TDbContext.ExecuteProcedure(const ADto: TObject);
var
  Typ: TRttiType;
  ProcAttr: StoredProcedureAttribute;
  ProcName: string;
  Prop: TRttiProperty;
  ParamAttr: DbParamAttribute;
  Cmd: IDbCommand;
  ParamNames: IList<string>;
  PropList: IList<TRttiProperty>;
  i: Integer;
  ParamName: string;
begin
  ParamNames := TCollections.CreateList<string>;
  PropList := TCollections.CreateList<TRttiProperty>;
  try
    Typ := TReflection.Context.GetType(ADto.ClassType);
    ProcAttr := Typ.GetAttribute<StoredProcedureAttribute>;
    if ProcAttr <> nil then
      ProcName := ProcAttr.Name
    else
      ProcName := ADto.ClassName;

    for Prop in Typ.GetProperties do
    begin
      ParamAttr := Prop.GetAttribute<DbParamAttribute>;
      if ParamAttr <> nil then
      begin
        if ParamAttr.Name <> '' then
          ParamNames.Add(ParamAttr.Name)
        else
          ParamNames.Add(Prop.Name);
          
        PropList.Add(Prop);
      end;
    end;

    Cmd := FConnection.CreateCommand(FDialect.GenerateProcedureCallSQL(ProcName, ParamNames.ToArray));
    for i := 0 to PropList.Count - 1 do
    begin
      Prop := PropList[i];
      ParamAttr := Prop.GetAttribute<DbParamAttribute>;
      ParamName := ParamNames[i];
      
      Cmd.AddParam(ParamName, Prop.GetValue(Pointer(ADto)));
      if ParamAttr.ParamType <> ptInput then
        Cmd.SetParamType(ParamName, ParamAttr.ParamType);
    end;

    Cmd.Execute;

    // Map back output parameters
    for i := 0 to PropList.Count - 1 do
    begin
      Prop := PropList[i];
      ParamAttr := Prop.GetAttribute<DbParamAttribute>;
      if ParamAttr.ParamType in [ptOutput, ptInputOutput, ptResult] then
      begin
        Prop.SetValue(Pointer(ADto), Cmd.GetParamValue(ParamNames[i]));
      end;
    end;
  finally
    ParamNames := nil;
    PropList := nil;
  end;
end;

function TDbContext.ChangeTracker: IChangeTracker;
begin
  Result := FChangeTracker;
end;

function TDbContext.Entry(const AEntity: TObject): IEntityEntry;
begin
  Result := TEntityEntry.Create(Self, AEntity);
end;

{ TEntityShadowState }

constructor TEntityShadowState.Create;
begin
  FShadowValues := TCollections.CreateDictionary<string, TValue>;
  FModifiedProperties := TCollections.CreateDictionary<string, Boolean>;
  FExplicitlyModified := TCollections.CreateDictionary<string, Boolean>;
end;
 
 destructor TEntityShadowState.Destroy;
 begin
   FShadowValues := nil;
   FModifiedProperties := nil;
   FExplicitlyModified := nil;
   inherited;
 end;

{ TChangeTracker }

constructor TChangeTracker.Create;
begin
  inherited Create;
  // Insertion-ordered: SaveChanges writes the entities in the order they were
  // tracked (Add order), not in the arbitrary order of a pointer-keyed hash.
  FTrackedEntities := TCollections.CreateOrderedDictionary<TObject, TEntityState>;
  FShadowStates := TCollections.CreateDictionary<TObject, TEntityShadowState>(True);
end;

destructor TChangeTracker.Destroy;
begin
  FTrackedEntities := nil;
  FShadowStates := nil;
  inherited;
end;

procedure TChangeTracker.Track(const AEntity: TObject; AState: TEntityState);
var
  State: TEntityShadowState;
begin
  if AEntity = nil then Exit;
  FTrackedEntities.AddOrSetValue(AEntity, AState);
  
  if AState = esUnchanged then
  begin
    State := GetShadowState(AEntity);
    if State.ShadowValues.Count = 0 then
      TakeSnapshot(AEntity);
  end;
end;

procedure TChangeTracker.Remove(const AEntity: TObject);
begin
  FTrackedEntities.Remove(AEntity);
  FShadowStates.Remove(AEntity);
end;

function TChangeTracker.GetState(const AEntity: TObject): TEntityState;
begin
  if not FTrackedEntities.TryGetValue(AEntity, Result) then
    Result := esDetached;
end;

procedure TChangeTracker.DetectChanges;
var
  Entity: TObject;
  State: TEntityShadowState;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
  CurrentVal, OriginalVal: TValue;
  IsModifiedProp: Boolean;
  HasAnyModified: Boolean;
  CurrentState: TEntityState;
  KeysList: IList<TObject>;
  Map: TEntityMap;
  i: Integer;
begin
  KeysList := TCollections.CreateList<TObject>;
  KeysList.AddRange(FTrackedEntities.Keys);
  for i := 0 to KeysList.Count - 1 do
  begin
    Entity := KeysList[i];
    CurrentState := FTrackedEntities[Entity];
    if CurrentState in [esUnchanged, esModified] then
    begin
      State := GetShadowState(Entity);
      Meta := TReflection.GetMetadata(Entity.ClassInfo);
      Map := MapOf(Entity);
      HasAnyModified := False;
      
      for Handler in Meta.GetPropertyHandlers() do
      begin
        // Navigation, lazy and [NotMapped] properties are not columns: a change
        // there writes nothing, and reading them would trigger lazy loads.
        if not IsPersisted(Handler, Map) then
          Continue;

        CurrentVal := Handler.GetValue(Pointer(Entity));
        if not State.ShadowValues.TryGetValue(
          Handler.Name, OriginalVal) then
          OriginalVal := TValue.Empty;

        TReflection.TryUnwrapProp(CurrentVal, CurrentVal);
        TReflection.TryUnwrapProp(OriginalVal, OriginalVal);
          
        IsModifiedProp := False;
        if CurrentVal.TypeInfo <> OriginalVal.TypeInfo then
        begin
          if not (CurrentVal.IsEmpty and OriginalVal.IsEmpty) then
            IsModifiedProp := True;
        end
        else if not CurrentVal.IsEmpty then
        begin
          case CurrentVal.Kind of
            tkInteger, tkInt64, tkEnumeration:
              IsModifiedProp := CurrentVal.AsOrdinal <> OriginalVal.AsOrdinal;
            tkFloat:
              IsModifiedProp := CurrentVal.AsExtended <> OriginalVal.AsExtended;
            tkString, tkLString, tkWString, tkUString:
              IsModifiedProp := CurrentVal.AsString <> OriginalVal.AsString;
            tkVariant:
              IsModifiedProp := CurrentVal.AsVariant <> OriginalVal.AsVariant;
            tkClass:
              IsModifiedProp := CurrentVal.AsObject <> OriginalVal.AsObject;
            tkInterface:
              IsModifiedProp := CurrentVal.AsInterface <> OriginalVal.AsInterface;
            else
              IsModifiedProp := CurrentVal.ToString <> OriginalVal.ToString;
          end;
        end
        else
          IsModifiedProp := not OriginalVal.IsEmpty;
          
        // A property marked explicitly stays modified even when its value
        // equals the snapshot (see TEntityShadowState.ExplicitlyModified).
        if not IsModifiedProp then
          IsModifiedProp := State.ExplicitlyModified.ContainsKey(Handler.Name);

        if IsModifiedProp then
        begin
          State.ModifiedProperties.AddOrSetValue(Handler.Name, True);
          HasAnyModified := True;
        end
        else
          State.ModifiedProperties.Remove(Handler.Name);
      end;
      
      if HasAnyModified then
      begin
        if CurrentState = esUnchanged then
          FTrackedEntities[Entity] := esModified;
      end
      else
      begin
        if CurrentState = esModified then
          FTrackedEntities[Entity] := esUnchanged;
      end;
    end;
  end;
end;

function TChangeTracker.HasChanges: Boolean;
var
  LPair: TPair<TObject, TEntityState>;
begin
  DetectChanges;
  Result := False;
  for LPair in FTrackedEntities do
  begin
    if LPair.Value in [esAdded, esModified, esDeleted] then
      Exit(True);
  end;
end;

function TChangeTracker.MapOf(const AEntity: TObject): TEntityMap;
begin
  if Assigned(FMapProvider) then
    Result := FMapProvider(AEntity.ClassInfo)
  else
    Result := nil;
end;

// Same rule the SQL generator uses to decide which properties are columns.
function TChangeTracker.IsPersisted(const AHandler: IPropertyHandler;
  const AMap: TEntityMap): Boolean;
var
  PropMap: TPropertyMap;
  Member: TRttiMember;
begin
  Result := True;
  Member := AHandler.GetMember;
  if Member.HasAttribute(JsonColumnAttribute) then
    Exit(True);

  PropMap := nil;
  if AMap <> nil then
    AMap.Properties.TryGetValue(AHandler.GetName, PropMap);

  if PropMap <> nil then
  begin
    if PropMap.IsIgnored then
      Exit(False);
    if PropMap.IsNavigation and not PropMap.IsJsonColumn then
      Exit(False);
  end
  else if (Member is TRttiProperty) and
    (TRttiProperty(Member).PropertyType.TypeKind in [tkClass, tkInterface]) then
    Exit(False);

  if Member.HasAttribute(NotMappedAttribute) or
     Member.HasAttribute(HasManyAttribute) or
     Member.HasAttribute(BelongsToAttribute) or
     Member.HasAttribute(HasOneAttribute) or
     Member.HasAttribute(ManyToManyAttribute) then
    Exit(False);
end;

procedure TChangeTracker.TakeSnapshot(const AEntity: TObject);
var
  State: TEntityShadowState;
  Meta: TTypeMetadata;
  Handler: IPropertyHandler;
  Map: TEntityMap;
begin
  State := GetShadowState(AEntity);
  Meta := TReflection.GetMetadata(AEntity.ClassInfo);
  Map := MapOf(AEntity);
  for Handler in Meta.GetPropertyHandlers() do
    if IsPersisted(Handler, Map) then
      State.ShadowValues.AddOrSetValue(Handler.Name, Handler.GetValue(Pointer(AEntity)));
end;

procedure TChangeTracker.AcceptAllChanges;
var
  LKey: TObject;
  LPair: TPair<TObject, TEntityShadowState>;
  LKeys: IList<TObject>;
begin
  LKeys := TCollections.CreateList<TObject>;
  for LKey in FTrackedEntities.Keys do
  begin
    if FTrackedEntities[LKey] = esDeleted then
      FTrackedEntities.Remove(LKey)
    else
    begin
      if FTrackedEntities[LKey] in [esAdded, esModified] then
        LKeys.Add(LKey);
      FTrackedEntities[LKey] := esUnchanged;
    end;
  end;
    
  for LPair in FShadowStates do
  begin
    LPair.Value.ModifiedProperties.Clear;
    LPair.Value.ExplicitlyModified.Clear;
  end;

  // The values just saved are the new baseline for DetectChanges. Without a
  // fresh snapshot, an entity saved with Add has none and one saved after a
  // change keeps the old one, so the next SaveChanges would see every
  // property as modified and write the entity again. Only the entities that
  // were written now are refreshed; the others keep the snapshot they have.
  for LKey in LKeys do
    TakeSnapshot(LKey);
end;

procedure TChangeTracker.Clear;
begin
  FTrackedEntities.Clear;
  FShadowStates.Clear;
end;

function TChangeTracker.GetTrackedEntities: IDictionary<TObject, TEntityState>;
begin
  DetectChanges;
  Result := FTrackedEntities;
end;

function TChangeTracker.GetShadowState(const AEntity: TObject): TEntityShadowState;
begin
  if not FShadowStates.TryGetValue(AEntity, Result) then
  begin
    Result := TEntityShadowState.Create;
    FShadowStates.Add(AEntity, Result);
  end;
end;

{ TPropertyEntry }

constructor TPropertyEntry.Create(const AContext: TDbContext; const AEntity: TObject;
  const APropName: string);
var
  Map: TEntityMap;
  PropMap: TPropertyMap;
begin
  inherited Create;
  FContext := AContext;
  FEntity := AEntity;
  FPropName := APropName;
  
  Map := FContext.ModelBuilder.GetMap(FEntity.ClassInfo);
  if (Map <> nil) and Map.Properties.TryGetValue(FPropName, PropMap) then
    FIsShadow := PropMap.IsShadow
  else
    FIsShadow := False;
end;

function TPropertyEntry.GetCurrentValue: TValue;
var
  Tracker: TChangeTracker;
  State: TEntityShadowState;
  Typ: TRttiType;
  Prop: TRttiProperty;
begin
  if FIsShadow then
  begin
    Tracker := TChangeTracker(FContext.ChangeTracker);
    State := Tracker.GetShadowState(FEntity);
    if not State.ShadowValues.TryGetValue(FPropName, Result) then
      Result := TValue.Empty;
  end
  else
  begin
    Typ := TReflection.Context.GetType(FEntity.ClassType);
    Prop := Typ.GetProperty(FPropName);
    if Prop <> nil then
      Result := Prop.GetValue(Pointer(FEntity))
    else
      Result := TValue.Empty;
  end;
end;

procedure TPropertyEntry.SetCurrentValue(const AValue: TValue);
var
  Tracker: TChangeTracker;
  State: TEntityShadowState;
  Typ: TRttiType;
  Prop: TRttiProperty;
begin
  if FIsShadow then
  begin
    Tracker := TChangeTracker(FContext.ChangeTracker);
    State := Tracker.GetShadowState(FEntity);
    State.ShadowValues.AddOrSetValue(FPropName, AValue);
    SetIsModified(True);
  end
  else
  begin
    Typ := TReflection.Context.GetType(FEntity.ClassType);
    Prop := Typ.GetProperty(FPropName);
    if Prop <> nil then
    begin
      Prop.SetValue(Pointer(FEntity), AValue);
      SetIsModified(True);
    end;
  end;
end;

function TPropertyEntry.GetIsModified: Boolean;
var
  Tracker: TChangeTracker;
  State: TEntityShadowState;
begin
  Tracker := TChangeTracker(FContext.ChangeTracker);
  State := Tracker.GetShadowState(FEntity);
  Result := State.ModifiedProperties.ContainsKey(FPropName);
end;

procedure TPropertyEntry.SetIsModified(const AValue: Boolean);
var
  Tracker: TChangeTracker;
  State: TEntityShadowState;
begin
  Tracker := TChangeTracker(FContext.ChangeTracker);
  State := Tracker.GetShadowState(FEntity);
  if AValue then
  begin
    State.ModifiedProperties.AddOrSetValue(FPropName, True);
    State.ExplicitlyModified.AddOrSetValue(FPropName, True);
    if Tracker.GetState(FEntity) = esUnchanged then
      Tracker.Track(FEntity, esModified);
  end
  else
  begin
    State.ModifiedProperties.Remove(FPropName);
    State.ExplicitlyModified.Remove(FPropName);
  end;
end;

{ TCollectionEntry }

constructor TCollectionEntry.Create(const AContext: TDbContext; const AParent: TObject; const APropName: string);
begin
  inherited Create;
  FContext := AContext;
  FParent := AParent;
  FPropName := APropName;
end;

procedure TCollectionEntry.Load;
var
  ListType: TRttiType;
  AddMethod: TRttiMethod;
  ChildType: TRttiType;
  ChildClass: TClass;
  DbSet: IDbSet;
  ParentPKProp: TRttiProperty;
  ParentPKVal: TValue;
  FKName: string;
  ChildTyp: TRttiType;
  Candidate: string;
  FKProp: TRttiProperty;
  ClearMethod: TRttiMethod;
  Expr: IExpression;
  Results: IList<TObject>;
  ChildObj: TObject;
  Typ: TRttiType;
  Prop: TRttiProperty;
  Val: TValue;
  IsInterface: Boolean;
  ListIntf: IInterface;
  ListObj: TObject;
  CProp: TRttiProperty;
  Attr: TCustomAttribute;
  ParentMap: TEntityMap;
  NavMap: TPropertyMap;
begin
  ListIntf := nil;
  ListObj := nil;
  Typ := TReflection.Context.GetType(FParent.ClassType);
  Prop := Typ.GetProperty(FPropName);
  if Prop = nil then
    raise Exception.CreateFmt('Property %s not found on %s', [FPropName, Typ.Name]);

  Val := Prop.GetValue(Pointer(FParent));
  if Val.IsEmpty then
    raise Exception.Create('Collection must be initialized before loading.');
  
  // Detect if property is Interface or Class
  IsInterface := Prop.PropertyType.TypeKind = tkInterface;

  if IsInterface then
  begin
    // Handle IList<T> (interface)
    ListIntf := Val.AsInterface;
    if ListIntf = nil then
      raise Exception.Create('Collection interface is nil and must be initialized before loading.');
    
    // Get the interface type to find Add method
    ListType := Prop.PropertyType;
  end
  else
  begin
    // Handle TList<T> or TObjectList<T> (class)
    ListObj := Val.AsObject;
    if ListObj = nil then
      raise Exception.Create('Collection must be initialized before loading.');
    
    ListType := TReflection.Context.GetType(ListObj.ClassType);
  end;
  
  // Find Add method
  AddMethod := ListType.GetMethod('Add');
  if AddMethod = nil then
    raise Exception.Create('Collection does not have Add method');
    
  ChildType := AddMethod.GetParameters[0].ParamType;
  ChildClass := ChildType.AsInstance.MetaclassType;
  
  // Find DbSet for ChildClass
  DbSet := FContext.DataSet(ChildClass.ClassInfo);
  
  // Find Parent PK
  ParentPKProp := Typ.GetProperty('Id'); // Simplified
  if ParentPKProp = nil then raise Exception.Create('PK Id not found on parent');
  ParentPKVal := ParentPKProp.GetValue(Pointer(FParent));
  TReflection.TryUnwrapProp(ParentPKVal, ParentPKVal);
  
  // Find FK on Child pointing to Parent
  FKName := '';
  ChildTyp := TReflection.Context.GetType(ChildClass);

  // The relationship declared on the collection (HasMany(...).HasForeignKey)
  ParentMap := TModelBuilder.Instance.GetMap(Typ.Handle);
  if (ParentMap <> nil) and ParentMap.Properties.TryGetValue(FPropName, NavMap) then
    FKName := NavMap.ForeignKeyColumn;

  for CProp in ChildTyp.GetProperties do
  begin
    if FKName <> '' then Break;
    if CProp.PropertyType.Handle = Typ.Handle then // Found property of Parent type
    begin
       // Check for ForeignKey attribute
       for Attr in CProp.GetAttributes do
         if Attr is ForeignKeyAttribute then
         begin
           FKName := ForeignKeyAttribute(Attr).ColumnName;
           Break;
         end;
       if FKName <> '' then Break;
    end;
  end;
  
  // If not found via attribute, try convention 'ParentClassNameId'
  if FKName = '' then
  begin
    // Try 'UserId' if parent is TUser
    Candidate := Copy(Typ.Name, 2, MaxInt) + 'Id'; // TUser -> User + Id
    if ChildTyp.GetProperty(Candidate) <> nil then
      FKName := Candidate;
  end;
  
  if FKName = '' then
    raise Exception.CreateFmt('Could not determine Foreign Key for collection %s', [FPropName]);
  
  // IMPORTANT: FKName is the property name, we need to convert to column name!
  FKProp := ChildTyp.GetProperty(FKName);
  if FKProp <> nil then
  begin
    // Check if property has [Column] attribute
    for Attr in FKProp.GetAttributes do
    begin
      if Attr is ColumnAttribute then
      begin
        FKName := ColumnAttribute(Attr).Name;
        Break;
      end;
    end;
  end;
  
  // Clear the collection before loading to ensure it reflects current DB state
  ClearMethod := ListType.GetMethod('Clear');
  if ClearMethod <> nil then
  begin
    if IsInterface then
      ClearMethod.Invoke(Val, [])
    else
      ClearMethod.Invoke(ListObj, []);
  end;
    
  // Build Query: Child.FK = Parent.Id
  Expr := TBinaryExpression.Create(
    FKName,
    boEqual,
    ParentPKVal
  );
  
  Results := DbSet.ListObjects(Expr);
    // Add results to collection
    for ChildObj in Results do
    begin
      if IsInterface then
        AddMethod.Invoke(Val, [ChildObj])
      else
        AddMethod.Invoke(ListObj, [ChildObj]);
    end;
  end;

{ TReferenceEntry }

constructor TReferenceEntry.Create(const AContext: TDbContext; const AParent: TObject; const APropName: string);
begin
  inherited Create;
  FContext := AContext;
  FParent := AParent;
  FPropName := APropName;
end;

procedure TReferenceEntry.Load;
var
  Typ: TRttiType;
  Prop: TRttiProperty;
  ChildType: TRttiType;
  ChildClass: TClass;
  DbSet: IDbSet;
  FKProp: TRttiProperty;
  FKVal: TValue;
  FKName: string;
  ChildObj: TObject;
  Attr: TCustomAttribute;
begin
  Typ := TReflection.Context.GetType(FParent.ClassType);
  Prop := Typ.GetProperty(FPropName);
  if Prop = nil then
    raise Exception.CreateFmt('Property %s not found on %s', [FPropName, Typ.Name]);

  ChildType := Prop.PropertyType;
  if ChildType.TypeKind <> tkClass then
    raise Exception.Create('Reference property must be a class');
    
  ChildClass := ChildType.AsInstance.MetaclassType;
  DbSet := FContext.DataSet(ChildClass.ClassInfo);
  
  // Find FK Property on Parent
  // Look for [ForeignKey] on Prop
  FKName := '';
  for Attr in Prop.GetAttributes do
    if Attr is ForeignKeyAttribute then
    begin
      FKName := ForeignKeyAttribute(Attr).ColumnName;
      Break;
    end;
    
  if FKName = '' then
  begin
    // Convention: PropName + 'Id'
    FKName := FPropName + 'Id';
  end;
  
  FKProp := Typ.GetProperty(FKName);
  if FKProp = nil then
    raise Exception.CreateFmt('Foreign Key property %s not found for reference %s', [FKName, FPropName]);
    
  FKVal := FKProp.GetValue(Pointer(FParent));
  
  // Unwrap Nullable<T> and validate FK value
  if not TryUnwrapAndValidateFK(FKVal) then Exit;

  
  // Find Child
  ChildObj := DbSet.FindObject(FKVal.AsVariant);
  if ChildObj <> nil then
  begin
    // The TClassToClassConverter will handle the conversion from TObject to TAddress
    Prop.SetValue(Pointer(FParent), ChildObj);
  end;
end;

{ TEntityEntry }

constructor TEntityEntry.Create(const AContext: TDbContext; const AEntity: TObject);
begin
  inherited Create;
  FContext := AContext;
  FEntity := AEntity;
end;

function TEntityEntry.Collection(const APropName: string): ICollectionEntry;
begin
  Result := TCollectionEntry.Create(FContext, FEntity, APropName);
end;

function TEntityEntry.Reference(const APropName: string): IReferenceEntry;
begin
  Result := TReferenceEntry.Create(FContext, FEntity, APropName);
end;

function TEntityEntry.Member(const APropName: string): IPropertyEntry;
begin
  Result := TPropertyEntry.Create(FContext, FEntity, APropName);
end;

end.

