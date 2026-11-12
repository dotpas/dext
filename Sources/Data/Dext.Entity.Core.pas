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
unit Dext.Entity.Core;

interface

uses
  Dext.Collections.Base,
  Dext.Collections,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Collections.Dict,
  Dext.Entity.TypeSystem,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Dialects,
  Dext.Entity.Naming,
  Dext.Entity.Query,
  Dext.Core.SmartTypes, // Add SmartTypes unit
  Dext.Core.Reflection,
  Dext.Specifications.Base,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types,
  Dext.MultiTenancy,
  Dext.Threading.Async,
  Dext.Entity.Mapping,
  System.Classes;

type
  /// <summary>
  ///   Exception raised when an optimistic concurrency conflict is detected.
  /// </summary>
  EOptimisticConcurrencyException = class(Exception);

  /// <summary>
  ///   The DDL of the join table of a many-to-many relationship.
  /// </summary>
  TJoinTableScript = record
    TableName: string;
    Sql: string;
  end;

  /// <summary>
  ///   Represents the possible states of an entity within the Change Tracker lifecycle.
  /// </summary>
  TEntityState = (esDetached, esUnchanged, esAdded, esDeleted, esModified);

  /// <summary>
  ///   Change tracker responsible for monitoring the state of entities and detecting modifications for persistence.
  /// </summary>
  IChangeTracker = interface
    ['{954BAFF5-3022-4AB8-AE14-A111295B3903}']
    procedure Track(const AEntity: TObject; AState: TEntityState);
    procedure Remove(const AEntity: TObject);
    function GetState(const AEntity: TObject): TEntityState;
    function HasChanges: Boolean;
    procedure AcceptAllChanges;
    procedure Clear;
    function GetTrackedEntities: IDictionary<TObject, TEntityState>;
  end;

  /// <summary>
  ///   Non-generic base interface for DbSets.
  ///   Allows access to DbSet operations without knowing the generic type at compile time.
  /// </summary>
  // RTTI for the IDbSet interfaces lets Mock<IDbSet<T>> intercept them
  // (see Dext.Testing.Entity). Turned off again after IDbSet<T>.
  {$M+}
  IDbSet = interface
    ['{CC8B4D83-96E0-42F7-9B33-D8DD06919316}']
    function FindObject(const AId: Variant): TObject; overload;
    function FindObject(const AId: Integer): TObject; overload;
    function Add(const AEntity: TObject): IDbSet;
    function GetTableName: string;
    function GetEntityType: PTypeInfo;
    function GenerateCreateTableScript: string;
    procedure Clear;
    procedure DetachAll;
    procedure Detach(const AEntity: TObject);
    
    // Non-generic query support
    function ListObjects(const AExpression: IExpression): IList<TObject>; overload;
    function ListObjects(const ASpec: ISpecification): IList<TObject>; overload;

    // Eager loading of Include paths over entities that are already loaded
    procedure LoadIncludesFor(const AEntities: TArray<TObject>; const AIncludes: TArray<string>);

    // Tracking Methods (Consistent with IDbSet<T>)
    procedure Update(const AEntity: TObject);
    procedure Remove(const AEntity: TObject);
    
    // Internal Persistence Methods (called by SaveChanges)
    procedure PersistAdd(const AEntity: TObject);
    procedure PersistAddRange(const AEntities: TArray<TObject>);
    procedure PersistUpdate(const AEntity: TObject);
    procedure PersistRemove(const AEntity: TObject);
    procedure PersistUpdateRange(const AEntities: TArray<TObject>);
    procedure PersistRemoveRange(const AEntities: TArray<TObject>);
    
    function IsBulkInsertSafe: Boolean;
    function IsBulkUpdateSafe: Boolean;
    function IsBulkDeleteSafe: Boolean;
    
    function GetEntityId(const AEntity: TObject): string;
    
    // Many-to-Many link management (non-generic versions for TTrackingList)
    procedure LinkManyToMany(const AEntity: TObject; const APropertyName: string; const ARelatedEntity: TObject);
    procedure UnlinkManyToMany(const AEntity: TObject; const APropertyName: string; const ARelatedEntity: TObject);

    // Many-to-Many join tables: DDL, change detection and persistence.
    // The join rows follow the collections of the entities: SaveChanges
    // compares each collection with the snapshot taken when it was loaded.
    function GetPKColumns: TArray<string>;
    function GenerateJoinTableScripts: TArray<TJoinTableScript>;
    function HasManyToManyChanges(const AEntity: TObject): Boolean;
    function PersistManyToMany(const AEntity: TObject; const ADeleted: Boolean): Integer;
    procedure SnapshotManyToMany(const AEntity: TObject);
    /// <summary>
    ///   The values of the key columns of an entity, in key order. A Smart
    ///   Property is read through its inner value.
    /// </summary>
    function GetKeyParts(const AEntity: TObject): TArray<TValue>;
    /// <summary>The types of the key columns, in key order.</summary>
    function GetKeyTypes: TArray<PTypeInfo>;
    /// <summary>
    ///   Reads the join rows of one many-to-many collection of an entity,
    ///   takes the snapshot that SaveChanges compares the collection with
    ///   and returns the related entities. Used by the lazy loader.
    /// </summary>
    function LoadManyToManyTargets(const AEntity: TObject;
      const APropertyName: string): TArray<TObject>;

    property EntityType: PTypeInfo read GetEntityType;
  end;

  /// <summary>Callback delegate for streaming UTF-8 bytes to HTTP sockets or streams.</summary>
  TUtf8StreamCallback = reference to procedure(const ABuffer: Pointer; const ALength: Integer);

  /// <summary>Callback delegate for writing projections directly into UTF-8 stream.</summary>
  TDbProjectionWriteProc = reference to procedure(const AWriter: Pointer);

  /// <summary>Non-generic base FastPath interface for zero-alloc direct JSON streaming.</summary>
  IDbSetFastStream = interface(IDBSet)
    ['{E4A5C6D7-E8F9-4102-83A4-5B6C7D8E9F0A}']
    procedure ExecuteToUtf8Proc(const ACallback: TUtf8StreamCallback); overload;
    procedure ExecuteToUtf8Stream(const AStream: TStream); overload;
  end;

  /// <summary>FastPath interface extending IDbSet<T> with zero-alloc direct JSON streaming.</summary>
  IDbSetFastStream<T: class> = interface(IDbSetFastStream)
    ['{7E8F9A0B-1C2D-3E4F-5A6B-7C8D9E0F1A2B}']
  end;

  /// <summary>
  ///   Represents a collection of entities mapped to a database table.
  /// </summary>
  IDbSet<T: class> = interface(IDbSetFastStream<T>)
    // CRUD
    function Add(const AEntity: T): IDbSet<T>; overload;
    function Add(const ABuilder: TFunc<IEntityBuilder<T>, T>): IDbSet<T>; overload;
    function Update(const AEntity: T): IDbSet<T>;
    function Remove(const AEntity: T): IDbSet<T>;
    function GetItem(Index: Integer): T;

    property Items[Index: Integer]: T read GetItem; default;

    function IsBulkInsertSafe: Boolean;
    function IsBulkUpdateSafe: Boolean;
    function IsBulkDeleteSafe: Boolean;

    // Bulk Operations
    procedure AddRange(const AEntities: TArray<T>); overload;
    procedure AddRange(const AEntities: IEnumerable<T>); overload;

    procedure UpdateRange(const AEntities: TArray<T>); overload;
    procedure UpdateRange(const AEntities: IEnumerable<T>); overload;
    
    procedure RemoveRange(const AEntities: TArray<T>); overload;
    procedure RemoveRange(const AEntities: IEnumerable<T>); overload;

    // Queries via Specifications
    function Find(const AId: Variant): T; overload;
    function Find(const AId: Integer): T; overload;
    function Find(const AId: array of Integer): T; overload;
    function Find(const AId: array of Variant): T; overload;

    function ToList: IList<T>; overload;
    function ToList(const ASpec: ISpecification<T>): IList<T>;  overload;
    function ToListAsync: TAsyncBuilder<IList<T>>;

    // Inline Queries (aceita IExpression diretamente)
    function ToList(const AExpression: IExpression): IList<T>; overload;
    function FirstOrDefault(const AExpression: IExpression): T; overload;
    function FirstOrDefault(const ASpec: ISpecification<T>): T; overload;
    function Any(const AExpression: IExpression): Boolean; overload;
    function Count(const AExpression: IExpression): Integer; overload;
    function Count(const ASpec: ISpecification<T>): Integer; overload;
    function Any(const ASpec: ISpecification<T>): Boolean; overload;
    
    // Smart Properties Support
    function Where(const APredicate: TQueryPredicate<T>): TFluentQuery<T>; overload;
    function Where(const AValue: BooleanExpression): TFluentQuery<T>; overload;
    function Where(const AExpression: TFluentExpression): TFluentQuery<T>; overload;
    function Where(const AExpression: IExpression): TFluentQuery<T>; overload;
    
    /// <summary>
    ///  Creates a LINQ query based on a raw SQL query.
    ///  If the SQL is a stored procedure, you cannot compose over it (Where, OrderBy won't work).
    ///  If the SQL is a SELECT statement, depending on the provider, you might be able to compose.
    ///  Parameters are bound in declaration order (first placeholder in the SQL matches AParams[0]),
    ///  e.g. <c>WHERE id = :UserId</c> with <c>[TValue.From(42)]</c> - not by names like <c>p0</c>.
    /// </summary>
    function FromSql(const ASql: string; const AParams: array of TValue): TFluentQuery<T>; overload;
    function FromSql(const ASql: string): TFluentQuery<T>; overload;

    // Lazy Queries (Deferred Execution) - Returns TFluentQuery<T>
    /// <summary>
    ///   Returns a lazy query that executes only when enumerated.
    ///   Call .ToList() to force execution and materialize results.
    /// </summary>
    function Query(const ASpec: ISpecification<T>): TFluentQuery<T>; overload;
    function Query(const AExpression: IExpression): TFluentQuery<T>; overload;
    function QueryAll: TFluentQuery<T>;
    
    /// <summary>
    ///   Returns a query configured to not track entities (read-only).
    /// </summary>
    function AsNoTracking: TFluentQuery<T>;

    // Soft Delete Control
    function IgnoreQueryFilters: IDbSet<T>;
    function OnlyDeleted: IDbSet<T>;
    function HardDelete(const AEntity: T): IDbSet<T>;
    function Restore(const AEntity: T): IDbSet<T>;

    // Offline Locking
    function TryLock(const AEntity: T; const AToken: string; ADurationMinutes: Integer = 30): Boolean;
    function Unlock(const AEntity: T): Boolean;

    // Many-to-Many Direct Management
    procedure LinkManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntity: TObject);
    procedure UnlinkManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntity: TObject);
    procedure SyncManyToMany(const AEntity: T; const APropertyName: string; const ARelatedEntities: TArray<TObject>);

    /// <summary>
    ///   Returns a streaming iterator that reuses a single object instance (Flyweight pattern).
    ///   Perfect for high-performance view rendering.
    /// </summary>
    function RequestStreamingIterator(const ASpec: ISpecification<T>): IEnumerator<T>;
  end;
  {$M-}

  /// <summary>
  ///   Provides access to a collection navigation property for an entity.
  /// </summary>
  ICollectionEntry = interface
    ['{A1B2C3D4-E5F6-4789-0123-456789ABCDEF}']
    procedure Load;
  end;

  /// <summary>
  ///   Provides access to a reference navigation property for an entity.
  /// </summary>
  IReferenceEntry = interface
    ['{B2C3D4E5-F6A7-4890-1234-567890BCDEFF}']
    procedure Load;
  end;

  /// <summary>
  ///   Provides access to a scalar property for an entity, allowing read and write operations.
  /// </summary>
  IPropertyEntry = interface
    ['{D4E5F6A7-B8C9-4A12-3456-789012DEF012}']
    function GetCurrentValue: TValue;
    procedure SetCurrentValue(const AValue: TValue);
    function GetIsModified: Boolean;
    procedure SetIsModified(const AValue: Boolean);
    function GetOriginalValue: TValue;
    property CurrentValue: TValue read GetCurrentValue write SetCurrentValue;
    property IsModified: Boolean read GetIsModified write SetIsModified;
    /// <summary>
    ///   The value the property had when the entity was loaded or last saved.
    ///   Empty for an entity that was never persisted (Added) and for shadow
    ///   properties, which keep no separate original.
    /// </summary>
    property OriginalValue: TValue read GetOriginalValue;
  end;

  /// <summary>
  ///   Provides access to information and tracking operations for a specific entity.
  /// </summary>
  IEntityEntry = interface
    ['{C3D4E5F6-A7B8-4901-2345-678901CDEF01}']
    function Collection(const APropName: string): ICollectionEntry;
    function Reference(const APropName: string): IReferenceEntry;
    function Member(const APropName: string): IPropertyEntry;
    function GetState: TEntityState;
    function GetModifiedMembers: TArray<string>;
    /// <summary>
    ///   The tracking state, after detecting the changes made to the properties.
    /// </summary>
    property State: TEntityState read GetState;
    /// <summary>
    ///   The names of the properties whose value differs from the original, in
    ///   alphabetical order.
    /// </summary>
    property ModifiedMembers: TArray<string> read GetModifiedMembers;
  end;

  /// <summary>
  ///   Abstract contract for lazy loading functionality, moving proxy generation out of the core pipeline.
  /// </summary>
  ILazyLoader = interface
    ['{482A3A6E-DF29-45B1-817E-12A4BF01CD33}']
    procedure Load(AEntity: TObject; const APropertyName: string);
    procedure LoadCollection(AEntity: TObject; const APropertyName: string);
  end;

  /// <summary>
  ///   Indicates that an entity is proxy-capable and can receive a lazy loader instance.
  /// </summary>
  ILazyLoaderAware = interface
    ['{E3A201C1-8B41-450F-A924-E84DE19C3BB8}']
    procedure SetLazyLoader(const ALazyLoader: ILazyLoader);
  end;

  /// <summary>
  ///   Represents design-time and runtime metadata for a single entity property/member.
  /// </summary>
  TEntityMemberMetadata = class(TCollectionItem)
  private
    FName: string;
    FMemberType: string;
    FIsPrimaryKey: Boolean;
    FIsRequired: Boolean;
    FIsAutoInc: Boolean;
    FIsReadOnly: Boolean;
    FMaxLength: Integer;
    FPrecision: Integer;
    FScale: Integer;
    FDisplayLabel: string;
    FDisplayFormat: string;
    FAlignment: TAlignment;
    FEditMask: string;
    FDisplayWidth: Integer;
    FVisible: Boolean;
    FIsCurrency: Boolean;
    FDefaultValue: string;
    FHasJoin: Boolean;
    FHasInclude: Boolean;
    FRelationType: string;
    FJoinColumn: string;
    FJoinTargetColumn: string;
    procedure SetName(const Value: string);
    procedure SetMemberType(const Value: string);
  protected
    function GetDisplayName: string; override;
  public
    constructor Create(Collection: TCollection); overload; override;
    constructor Create; reintroduce; overload;
    procedure Assign(Source: TPersistent); override;
  published
    property Name: string read FName write SetName;
    property MemberType: string read FMemberType write SetMemberType;
    property IsPrimaryKey: Boolean read FIsPrimaryKey write FIsPrimaryKey;
    property IsRequired: Boolean read FIsRequired write FIsRequired;
    property IsAutoInc: Boolean read FIsAutoInc write FIsAutoInc;
    property IsReadOnly: Boolean read FIsReadOnly write FIsReadOnly;
    property MaxLength: Integer read FMaxLength write FMaxLength;
    property Precision: Integer read FPrecision write FPrecision;
    property Scale: Integer read FScale write FScale;
    property DisplayLabel: string read FDisplayLabel write FDisplayLabel;
    property DisplayFormat: string read FDisplayFormat write FDisplayFormat;
    property Alignment: TAlignment read FAlignment write FAlignment;
    property EditMask: string read FEditMask write FEditMask;
    property DisplayWidth: Integer read FDisplayWidth write FDisplayWidth;
    property Visible: Boolean read FVisible write FVisible;
    property IsCurrency: Boolean read FIsCurrency write FIsCurrency;
    property DefaultValue: string read FDefaultValue write FDefaultValue;
    property HasJoin: Boolean read FHasJoin write FHasJoin;
    property HasInclude: Boolean read FHasInclude write FHasInclude;
    property RelationType: string read FRelationType write FRelationType;
    property JoinColumn: string read FJoinColumn write FJoinColumn;
    property JoinTargetColumn: string read FJoinTargetColumn write FJoinTargetColumn;
  end;

  /// <summary>
  ///   Collection of entity member metadata.
  /// </summary>
  TEntityMemberCollection = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TEntityMemberMetadata;
    procedure SetItem(Index: Integer; const Value: TEntityMemberMetadata);
  public
    constructor Create(AOwner: TPersistent);
    function Add: TEntityMemberMetadata;
    property Items[Index: Integer]: TEntityMemberMetadata read GetItem write SetItem; default;
  end;

  /// <summary>
  ///   Represents design-time and runtime metadata for an entire entity class.
  /// </summary>
  TEntityClassMetadata = class(TCollectionItem)
  private
    FEntityClassName: string;
    FDisplayName: string;
    FTableName: string;
    FEntityUnitName: string;
    FMembers: TEntityMemberCollection;
    procedure SetMembers(const Value: TEntityMemberCollection);
    procedure SetEntityClassName(const Value: string);
    procedure SetTableName(const Value: string);
  protected
    function GetDisplayName: string; override;
    procedure SetDisplayName(const Value: string); override;
  public
    constructor Create(Collection: TCollection); overload; override;
    constructor Create; reintroduce; overload;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    property EntityClassName: string read FEntityClassName write SetEntityClassName;
    property DisplayName: string read FDisplayName write SetDisplayName;
    property TableName: string read FTableName write SetTableName;
    property EntityUnitName: string read FEntityUnitName write FEntityUnitName;
    property Members: TEntityMemberCollection read FMembers write SetMembers;
  end;

  /// <summary>
  ///   Collection of entity class metadata.
  /// </summary>
  TEntityClassCollection = class(TOwnedCollection)
  private
    function GetItem(Index: Integer): TEntityClassMetadata;
    procedure SetItem(Index: Integer; const Value: TEntityClassMetadata);
  public
    constructor Create(AOwner: TPersistent);
    function Add: TEntityClassMetadata;
    function FindByName(const AClassName: string): TEntityClassMetadata;
    property Items[Index: Integer]: TEntityClassMetadata read GetItem write SetItem; default;
  end;

  /// <summary>
  ///   Provider interface for accessing entity schema metadata and instance generation.
  /// </summary>
  IEntityDataProvider = interface
    ['{884D5514-6F29-4F58-BF76-2244EEF9452A}']
    function GetEntities: TArray<string>;
    function GetEntityMetadata(const AClassName: string): TEntityClassMetadata;
    function GetEntityUnitName(const AClassName: string): string;
    function ResolveEntityClass(const AClassName: string): TClass;
    function BuildPreviewSql(const AClassName: string; AMaxRows: Integer = 50): string;
    function CreatePreviewItems(const AClassName: string; AMaxRows: Integer = 50): IObjectList;
    procedure SyncMetadata(const AEntityClassName: string);
  end;

  /// <summary>
  ///   Represents a session with the database (Unit of Work), allowing to query and save entity instances.
  /// </summary>
  IDbContext = interface
    ['{631803BB-AEDD-4453-B2CC-D44C7AFDD9F1}']
    function Connection: IDbConnection;
    function Dialect: ISQLDialect;
    function NamingStrategy: INamingStrategy;
    function BulkBatchSize: Integer;
    
    // Transaction Management
    procedure BeginTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    
    /// <summary>
    ///   Get a non-generic DbSet for the specified entity type.
    /// </summary>
    function DataSet(AEntityType: PTypeInfo): IDbSet;
    
    /// <summary>
    ///   Ensures that the database schema exists.
    ///   Creates tables for all registered entities if they don't exist.
    ///   Returns True if the schema was created, False if it already existed.
    /// </summary>
    function EnsureCreated: Boolean;

    /// <summary>
    ///   Saves all changes made in this context to the database.
    /// </summary>
    function SaveChanges: Integer;
    function SaveChangesAsync: TAsyncBuilder<Integer>;

    /// <summary>
    ///   Clears the ChangeTracker and IdentityMap of all DbSets.
    ///   Detaches all entities.
    /// </summary>
    procedure Clear;

    /// <summary>
    ///   Detaches all entities from the context: they stop being tracked and
    ///   leave the identity map, but the instances stay valid. The context
    ///   still owns them and frees them when it is destroyed or cleared, so
    ///   the caller must not free them.
    /// </summary>
    procedure DetachAll;

    /// <summary>
    ///   Detaches a specific entity from the context. The instance stays valid
    ///   and the context keeps owning it (see DetachAll).
    /// </summary>
    procedure Detach(const AEntity: TObject);

    /// <summary>
    ///   Executes a stored procedure and maps output parameters and return values
    ///   back to the provided DTO object using [DbParam] attributes.
    /// </summary>
    procedure ExecuteProcedure(const ADto: TObject);

    /// <summary>
    ///   Access the Change Tracker.
    /// </summary>
    function ChangeTracker: IChangeTracker;
    
    /// <summary>
    ///   Retrieves the mapping object for a specific type (TEntityMap).
    ///   Returns nil if no mapping is defined.
    /// </summary>
    function GetMapping(AType: PTypeInfo): TObject;
    
    function Entry(const AEntity: TObject): IEntityEntry;
    
    /// <summary>
    ///  Tracks internal framework objects (like proxy managers) that need to be
    ///  freed when the context is destroyed.
    /// </summary>
    procedure TrackProxy(const AProxy: TObject);
    
    // Tenancy
    function GetTenantProvider: ITenantProvider;
    property TenantProvider: ITenantProvider read GetTenantProvider;

    /// <summary>
    ///   Runs the validation of one entity: the mapping rules and, when one is
    ///   registered, the entity's IValidator. The persistence methods that can
    ///   be called outside SaveChanges (PersistAddRange, PersistUpdateRange) call
    ///   it. It does nothing while SaveChanges runs, which validates every entity
    ///   before it reaches the DbSet.
    /// </summary>
    procedure ValidateForPersist(const AEntity: TObject);

    function GetModelBuilder: TModelBuilder;
    property ModelBuilder: TModelBuilder read GetModelBuilder;

    procedure SetOnLog(const AValue: TProc<string>);
    function GetOnLog: TProc<string>;
    property OnLog: TProc<string> read GetOnLog write SetOnLog;
  end;

  /// <summary>
  ///   Observes SaveChanges, in the spirit of the EF Core SaveChanges interceptors.
  ///   SavingChanges runs before the transaction starts, so the entities it adds
  ///   to the context (an audit row, say) are written in the same SaveChanges and
  ///   the same transaction as the changes that caused them. An exception raised
  ///   there cancels the save. SavedChanges runs after the commit, and
  ///   SaveChangesFailed after the rollback, before the exception reaches the caller.
  ///   A SaveChanges called from inside an interceptor does not trigger it again.
  /// </summary>
  ISaveChangesInterceptor = interface
    ['{3F6B1D52-8A47-4C9E-B0D3-5E71A92C4F18}']
    procedure SavingChanges(const Context: IDbContext);
    procedure SavedChanges(const Context: IDbContext; AffectedRows: Integer);
    procedure SaveChangesFailed(const Context: IDbContext; const Error: Exception);
  end;

  /// <summary>
  ///   Base class with empty methods: override only what the interceptor needs.
  /// </summary>
  TSaveChangesInterceptor = class(TInterfacedObject, ISaveChangesInterceptor)
  public
    procedure SavingChanges(const Context: IDbContext); virtual;
    procedure SavedChanges(const Context: IDbContext; AffectedRows: Integer); virtual;
    procedure SaveChangesFailed(const Context: IDbContext; const Error: Exception); virtual;
  end;

/// <summary>
///   Unwraps Nullable&lt;T&gt; values and validates if FK is valid (non-zero for integers, non-empty for strings)
/// </summary>
function TryUnwrapAndValidateFK(var AValue: TValue): Boolean;

implementation

{ TSaveChangesInterceptor }

procedure TSaveChangesInterceptor.SavingChanges(const Context: IDbContext);
begin
end;

procedure TSaveChangesInterceptor.SavedChanges(const Context: IDbContext;
  AffectedRows: Integer);
begin
end;

procedure TSaveChangesInterceptor.SaveChangesFailed(const Context: IDbContext;
  const Error: Exception);
begin
end;

function TryUnwrapAndValidateFK(var AValue: TValue): Boolean;
var
  Field: TRttiField;
  Fields: TArray<TRttiField>;
  HasValue: Boolean;
  HasValueField, ValueField: TRttiField;
  HasValueVal: TValue;
  Instance: Pointer;
  RType: TRttiType;
  TypeName: string;
begin
  Result := False;
  
  // Handle Nullable<T> unwrapping
  if AValue.Kind = tkRecord then
  begin
    RType := TReflection.Context.GetType(AValue.TypeInfo);
    if RType <> nil then
    begin
      TypeName := RType.Name;
      
      // Check if it's a Nullable<T> by name
      if TypeName.StartsWith('Nullable<') or TypeName.StartsWith('TNullable') then
      begin
        // Access fields directly since GetProperty won't work for generic records
        Fields := RType.GetFields;
        HasValueField := nil;
        ValueField := nil;
        
        // Find fHasValue and fValue fields
        for Field in Fields do
        begin
          if Field.Name.ToLower.Contains('hasvalue') then
            HasValueField := Field
          else if Field.Name.ToLower = 'fvalue' then
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

  if AValue.IsEmpty then Exit;

  // Validate based on type
  if AValue.Kind in [tkInteger, tkInt64] then
    Result := AValue.AsInt64 <> 0
  else if AValue.Kind in [tkString, tkUString, tkWString, tkLString] then
    Result := AValue.AsString <> ''
  else
    Result := True; // For other types like GUID, assume valid if not empty
end;

{ TEntityMemberMetadata }

constructor TEntityMemberMetadata.Create(Collection: TCollection);
begin
  inherited Create(Collection);
end;

function TEntityMemberMetadata.GetDisplayName: string;
begin
  if FName <> '' then
    Result := FName + ': ' + FMemberType
  else
    Result := inherited GetDisplayName;
end;

procedure TEntityMemberMetadata.SetName(const Value: string);
begin
  if FName <> Value then
  begin
    FName := Value;
    Changed(False);
  end;
end;

procedure TEntityMemberMetadata.SetMemberType(const Value: string);
begin
  if FMemberType <> Value then
  begin
    FMemberType := Value;
    Changed(False);
  end;
end;

constructor TEntityMemberMetadata.Create;
begin
  Create(nil);
end;

procedure TEntityMemberMetadata.Assign(Source: TPersistent);
begin
  if Source is TEntityMemberMetadata then
  begin
    FName := TEntityMemberMetadata(Source).Name;
    FMemberType := TEntityMemberMetadata(Source).MemberType;
    FIsPrimaryKey := TEntityMemberMetadata(Source).IsPrimaryKey;
    FIsRequired := TEntityMemberMetadata(Source).IsRequired;
    FIsAutoInc := TEntityMemberMetadata(Source).IsAutoInc;
    FIsReadOnly := TEntityMemberMetadata(Source).IsReadOnly;
    FMaxLength := TEntityMemberMetadata(Source).MaxLength;
    FPrecision := TEntityMemberMetadata(Source).Precision;
    FScale := TEntityMemberMetadata(Source).Scale;
    FDisplayLabel := TEntityMemberMetadata(Source).DisplayLabel;
    FDisplayFormat := TEntityMemberMetadata(Source).DisplayFormat;
    FAlignment := TEntityMemberMetadata(Source).Alignment;
    FEditMask := TEntityMemberMetadata(Source).EditMask;
    FDisplayWidth := TEntityMemberMetadata(Source).DisplayWidth;
    FVisible := TEntityMemberMetadata(Source).Visible;
    FIsCurrency := TEntityMemberMetadata(Source).IsCurrency;
    FDefaultValue := TEntityMemberMetadata(Source).DefaultValue; // Added this
    FHasJoin := TEntityMemberMetadata(Source).HasJoin;
    FHasInclude := TEntityMemberMetadata(Source).HasInclude;
    FRelationType := TEntityMemberMetadata(Source).RelationType;
  end
  else
    inherited Assign(Source);
end;

{ TEntityMemberCollection }

constructor TEntityMemberCollection.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TEntityMemberMetadata);
end;

function TEntityMemberCollection.Add: TEntityMemberMetadata;
begin
  Result := TEntityMemberMetadata(inherited Add);
end;

function TEntityMemberCollection.GetItem(Index: Integer): TEntityMemberMetadata;
begin
  Result := TEntityMemberMetadata(inherited GetItem(Index));
end;

procedure TEntityMemberCollection.SetItem(Index: Integer; const Value: TEntityMemberMetadata);
begin
  inherited SetItem(Index, Value);
end;

{ TEntityClassMetadata }

constructor TEntityClassMetadata.Create(Collection: TCollection);
begin
  inherited Create(Collection);
  FMembers := TEntityMemberCollection.Create(Self);
end;

constructor TEntityClassMetadata.Create;
begin
  Create(nil);
end;

procedure TEntityClassMetadata.Assign(Source: TPersistent);
begin
  if Source is TEntityClassMetadata then
  begin
    FEntityClassName := TEntityClassMetadata(Source).EntityClassName;
    FDisplayName := TEntityClassMetadata(Source).DisplayName;
    FTableName := TEntityClassMetadata(Source).TableName;
    FEntityUnitName := TEntityClassMetadata(Source).EntityUnitName;
    FMembers.Assign(TEntityClassMetadata(Source).Members);
  end
  else
    inherited Assign(Source);
end;

destructor TEntityClassMetadata.Destroy;
begin
  FMembers.Free;
  inherited;
end;

procedure TEntityClassMetadata.SetMembers(const Value: TEntityMemberCollection);
begin
  FMembers.Assign(Value);
end;

function TEntityClassMetadata.GetDisplayName: string;
begin
  if FDisplayName <> '' then
    Result := FDisplayName
  else if FEntityClassName <> '' then
    Result := FEntityClassName + ' (' + FTableName + ')'
  else
    Result := inherited GetDisplayName;
end;

procedure TEntityClassMetadata.SetDisplayName(const Value: string);
begin
  if FDisplayName <> Value then
  begin
    FDisplayName := Value;
    Changed(False);
  end;
end;

procedure TEntityClassMetadata.SetEntityClassName(const Value: string);
begin
  if FEntityClassName <> Value then
  begin
    FEntityClassName := Value;
    Changed(False);
  end;
end;

procedure TEntityClassMetadata.SetTableName(const Value: string);
begin
  if FTableName <> Value then
  begin
    FTableName := Value;
    Changed(False);
  end;
end;

{ TEntityClassCollection }

constructor TEntityClassCollection.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TEntityClassMetadata);
end;

function TEntityClassCollection.Add: TEntityClassMetadata;
begin
  Result := TEntityClassMetadata(inherited Add);
end;

function TEntityClassCollection.FindByName(const AClassName: string): TEntityClassMetadata;
var
  i: integer;
begin
  for i := 0 to Count - 1 do
  begin
    if SameText(Items[i].EntityClassName, AClassName) then
      Exit(Items[i]);
  end;
  Result := nil;
end;

function TEntityClassCollection.GetItem(Index: Integer): TEntityClassMetadata;
begin
  Result := TEntityClassMetadata(inherited GetItem(Index));
end;

procedure TEntityClassCollection.SetItem(Index: Integer; const Value: TEntityClassMetadata);
begin
  inherited SetItem(Index, Value);
end;

end.

