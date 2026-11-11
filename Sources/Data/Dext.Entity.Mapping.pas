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
unit Dext.Entity.Mapping;

interface

uses
  Dext.Collections,
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Dext.Collections.Dict,
  System.SyncObjs,
  System.TypInfo,
  System.Rtti,
  System.Variants,
  System.Character,
  Data.DB,
  Dext.Entity.Attributes,
  Dext.Entity.TypeConverters,
  Dext.Core.SmartTypes,
  Dext.Core.Reflection,
  Dext.Core.TypeModel,
  Dext.Threading.Sync,
  Dext.Specifications.Interfaces;

type
  /// <summary>
  ///   Raised when a mapping refers to something the entity does not have, such as a
  ///   property name with a typo in the fluent API.
  /// </summary>
  EEntityMappingException = class(Exception);

  /// <summary>
  ///   Defines the cardinality and type of an entity relationship.
  /// </summary>
  TRelationshipType = (rtNone, rtOneToMany, rtManyToOne, rtOneToOne, rtManyToMany);

  // Forward declarations
  IPropertyBuilder<T: class> = interface;
  IRelationshipBuilder<T: class> = interface;

  /// <summary>
  ///   Fluent interface for programmatic configuration of an entity (Code-First).
  /// </summary>
  IEntityTypeBuilder<T: class> = interface
    ['{6DC34AF2-B40E-428F-85B6-94D77209476F}']
    function ToTable(const AName: string): IEntityTypeBuilder<T>; overload;
    function ToTable(const AName, ASchema: string): IEntityTypeBuilder<T>; overload;
    function HasKey(const APropertyName: string): IEntityTypeBuilder<T>; overload;
    function HasKey(const APropertyNames: array of string): IEntityTypeBuilder<T>; overload;
    function HasDiscriminator(const AColumn: string; const AValue: Variant): IEntityTypeBuilder<T>;
    function MapInheritance(AStrategy: TInheritanceStrategy): IEntityTypeBuilder<T>;
    function Prop(const APropertyName: string): IPropertyBuilder<T>; overload;
    function Prop(const AProp: IPropInfo): IPropertyBuilder<T>; overload;
    function ShadowProperty(const APropName: string): IPropertyBuilder<T>;
    function Ignore(const APropertyName: string): IEntityTypeBuilder<T>;
    
    // Relationships
    function HasMany(const APropertyName: string): IRelationshipBuilder<T>;
    function HasOne(const APropertyName: string): IRelationshipBuilder<T>;
    function BelongsTo(const APropertyName: string): IRelationshipBuilder<T>;
    function HasManyToMany(const APropertyName: string): IRelationshipBuilder<T>;
  end;

  /// <summary>
  ///   Fluent interface to configure a relationship.
  /// </summary>
  IRelationshipBuilder<T: class> = interface
    ['{ADF7AC66-198B-4FD2-9E43-9D342A37542C}']
    function WithOne(const AInversePropName: string = ''): IRelationshipBuilder<T>;
    function WithMany(const AInversePropName: string = ''): IRelationshipBuilder<T>;
    function HasForeignKey(const AFKPropertyName: string): IRelationshipBuilder<T>;
    function HasPrincipalKey(const AKeyPropertyName: string): IRelationshipBuilder<T>;
    function OnDelete(AAction: TCascadeAction): IRelationshipBuilder<T>;
    // Many-to-Many specific
    function UsingEntity(const AJoinTableName: string): IRelationshipBuilder<T>; overload;
    function UsingEntity(const AJoinTableName, ALeftKey, ARightKey: string): IRelationshipBuilder<T>; overload;
  end;

  /// <summary>
  ///   Fluent interface for detailed configuration of properties and columns.
  /// </summary>
  IPropertyBuilder<T: class> = interface
    ['{31A85F1F-53AD-4130-85DC-AC6FCC062AE2}']
    function HasColumnName(const AName: string): IPropertyBuilder<T>;
    function HasFieldName(const AName: string): IPropertyBuilder<T>;
    function UseField: IPropertyBuilder<T>;
    function IsRequired(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsAutoInc(AValue: Boolean = True): IPropertyBuilder<T>;
    function HasMaxLength(ALength: Integer): IPropertyBuilder<T>;
    function HasMinLength(ALength: Integer): IPropertyBuilder<T>;
    function HasPrecision(APrecision, AScale: Integer): IPropertyBuilder<T>;
    function HasDbType(ADataType: TFieldType): IPropertyBuilder<T>;
    function HasConverter(AConverterClass: TClass): IPropertyBuilder<T>;
    function IsLazy(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsVersion(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsCreatedAt(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsUpdatedAt(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsDeletedAt(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsShadow(AValue: Boolean = True): IPropertyBuilder<T>;
    function HasDisplayLabel(const AValue: string): IPropertyBuilder<T>;
    function HasDisplayWidth(AValue: Integer): IPropertyBuilder<T>;
    function HasDisplayFormat(const AValue: string): IPropertyBuilder<T>;
    function HasEditMask(const AValue: string): IPropertyBuilder<T>;
    function HasAlignment(AValue: TAlignment): IPropertyBuilder<T>;
    function IsReadOnly(AValue: Boolean = True): IPropertyBuilder<T>;
    /// <summary>
    ///   Configures this property to use a database sequence generator for primary key pre-allocation.
    /// </summary>
    /// <param name="ASequenceName">The name of the database sequence.</param>
    /// <param name="AAllocationSize">The block allocation size for in-memory HiLo pre-allocation (default is 50).</param>
    function UseSequence(const ASequenceName: string; AAllocationSize: Integer = 50): IPropertyBuilder<T>;
  end;

  /// <summary>
  ///   Base interface for user-defined mapping configurations.
  /// </summary>
  IEntityTypeConfiguration<T: class> = interface
    ['{F8D58DC7-8AFC-4EC4-ACE5-6CA95E9978F6}']
    procedure Configure(Builder: IEntityTypeBuilder<T>);
  end;

  /// <summary>
  ///   Factory interface for dynamic creation of generic DbSets.
  /// </summary>
  IDynamicDbSetFactory = interface
    ['{A578C63F-1596-46EE-A9B5-AA86EB5E831B}']
    function CreateDbSet(const AContext: IInterface): IInterface;
  end;

  // ---------------------------------------------------------------------------
  // Internal Model Representation (The result of the mapping)
  // ---------------------------------------------------------------------------

  /// <summary>
  ///   Holds the mapped configuration for a single entity property or column.
  /// </summary>
  TPropertyMap = class
  public
    PropertyName: string;
    ColumnName: string;
    FieldName: string;
    ForeignKeyColumn: string; // Added for FK support
    IsPK: Boolean;
    IsAutoInc: Boolean;
    IsRequired: Boolean;
    MaxLength: Integer;
    MinLength: Integer;
    Precision: Integer;
    Scale: Integer;
    IsIgnored: Boolean;
    IsNavigation: Boolean;
    Relationship: TRelationshipType;
    InverseProperty: string;
    PrincipalKey: string;
    DeleteBehavior: TCascadeAction;
    // Many-to-Many Join Table
    JoinTableName: string;
    LeftKeyColumn: string;
    RightKeyColumn: string;
    Converter: ITypeConverter;
    DataType: TFieldType;
    ConverterClass: TClass;
    // Optimistic Concurrency
    IsVersion: Boolean;
    // Audit Timestamps
    IsCreatedAt: Boolean;
    IsUpdatedAt: Boolean;
    IsDeletedAt: Boolean; // New: Soft Delete Timestamp
    // Sequence Generation (S46)
    IsSequenced: Boolean;
    SequenceName: string;
    SequenceAllocationSize: Integer;
    // Internal engine optimization
    FieldOffset: Integer;      // Offset of Null flag (Boolean) - Used by TEntityDataSet
    MetadataOffset: Integer;   // Offset of FInfo (IPropInfo) - Used by Prototype
    FieldValueOffset: Integer; // Offset of FValue
    PropertyType: PTypeInfo;   // Type of T in Prop<T>
    NativeKind: TDextNativeKind; // Shared S54 scalar classification
    // Shadow Property support
    IsShadow: Boolean;
    // JSON Column Support
    IsJsonColumn: Boolean;
    UseJsonB: Boolean; // PostgreSQL JSONB vs JSON
    IsLazy: Boolean; // New: Support for Auto-Proxies / Explicit Lazy
    IsEnum: Boolean; // New: Flag to identify enumeration types
    Prop: TRttiProperty; // Cached RTTI property
    Visible: Boolean;
    IsReadOnly: Boolean;
    // UI Metadata
    DisplayLabel: string;
    DisplayFormat: string;
    DisplayWidth: Integer;
    EditMask: string;
    Alignment: TAlignment;
    DefaultValue: Variant;
    constructor Create(const APropName: string);
  end;

  /// <summary>
  ///   Represents the final mapping model of an entity, consolidating attributes and fluent configurations.
  /// </summary>
  TEntityMap = class
  private
    FEntityType: PTypeInfo;
    FTableName: string;
    FSchema: string;
    FProperties: IDictionary<string, TPropertyMap>;
    FOrderedProperties: IList<TPropertyMap>;
    FKeys: IList<string>;
    // Soft Delete Configuration
    FIsSoftDelete: Boolean;
    FSoftDeleteProp: string;
    FSoftDeleteDeletedValue: Variant;
    FSoftDeleteNotDeletedValue: Variant;
    // Inheritance Configuration
    FInheritanceStrategy: TInheritanceStrategy;
    FDiscriminatorColumn: string;
    FDiscriminatorValue: Variant;
    // Global Query Filters
    FQueryFilters: IList<IExpression>;
    FIsProxy: Boolean;
    FInheritanceResolved: Boolean;

  public
    constructor Create(AEntityType: PTypeInfo);
    destructor Destroy; override;

    /// <summary>
    ///   Marks a property as the deletion timestamp. A class without another soft delete
    ///   rule becomes a soft delete class filtered by that column being null.
    /// </summary>
    procedure MarkDeletedAt(APropMap: TPropertyMap; AValue: Boolean = True);

    property EntityType: PTypeInfo read FEntityType;
    property TableName: string read FTableName write FTableName;
    property Schema: string read FSchema write FSchema;
    property Properties: IDictionary<string, TPropertyMap> read FProperties;
    property OrderedProperties: IList<TPropertyMap> read FOrderedProperties;
    property Keys: IList<string> read FKeys;
    
    property IsSoftDelete: Boolean read FIsSoftDelete;
    property SoftDeleteProp: string read FSoftDeleteProp;
    property SoftDeleteDeletedValue: Variant read FSoftDeleteDeletedValue;
    property SoftDeleteNotDeletedValue: Variant read FSoftDeleteNotDeletedValue;
    property QueryFilters: IList<IExpression> read FQueryFilters;
    
    property InheritanceStrategy: TInheritanceStrategy read FInheritanceStrategy write FInheritanceStrategy;
    property DiscriminatorColumn: string read FDiscriminatorColumn write FDiscriminatorColumn;
    property DiscriminatorValue: Variant read FDiscriminatorValue write FDiscriminatorValue;
    property IsProxy: Boolean read FIsProxy write FIsProxy;

    procedure DiscoverAttributes;
    procedure ProcessAttribute(APropMap: TPropertyMap; AAttr: TCustomAttribute);
    function GetOrAddProperty(const APropName: string): TPropertyMap;
    function GetOrderedProperties: TArray<TPropertyMap>;
    /// <summary>
    ///   Raises EEntityMappingException when the entity class has no property or field
    ///   with this name. Shadow properties are declared with ShadowProperty, which skips it.
    /// </summary>
    procedure RequireClassProperty(const AName: string);
    /// <summary>
    ///   Table per hierarchy: a subclass takes the table, the key and the configuration of the
    ///   properties it inherits from the root. Called by the model builder, once.
    /// </summary>
    procedure InheritFrom(ARoot: TEntityMap);
    property InheritanceResolved: Boolean read FInheritanceResolved write FInheritanceResolved;
  end;

  // ---------------------------------------------------------------------------
  // Fluent API Records
  // ---------------------------------------------------------------------------

  /// <summary>
  ///   Lightweight, struct-based fluent builder for configuring an entity mapping.
  /// </summary>
  TEntityBuilder<T: class> = record
  private
    FMap: TEntityMap;
    FCurrentProp: TPropertyMap;
    function GetCurrentProp: TPropertyMap;
  public
    constructor Create(AMap: TEntityMap);
    
    // Entity Configuration
    function Table(const AName: string): TEntityBuilder<T>; overload;
    function Table(const AName, ASchema: string): TEntityBuilder<T>; overload;
    function HasKey(const APropertyName: string): TEntityBuilder<T>; overload;
    function HasKey(const APropertyNames: array of string): TEntityBuilder<T>; overload;
    function HasDiscriminator(const AColumn: string; const AValue: Variant): TEntityBuilder<T>;
    function MapInheritance(AStrategy: TInheritanceStrategy): TEntityBuilder<T>;
    
    // Property Selection
    function Prop(const APropertyName: string): TEntityBuilder<T>;
    function ShadowProperty(const APropName: string): TEntityBuilder<T>;
    function HasProperty(const APropertyName: string): TEntityBuilder<T>;
    
    // Property Configuration (Applied to current property)
    function Column(const AName: string): TEntityBuilder<T>;
    function HasForeignKey(const AColumnName: string): TEntityBuilder<T>;
    function IsRequired(AValue: Boolean = True): TEntityBuilder<T>;
    function IsAutoInc(AValue: Boolean = True): TEntityBuilder<T>;
    /// <summary>The key of the current property comes from a database sequence (HiLo).</summary>
    function UseSequence(const ASequenceName: string; AAllocationSize: Integer = 50): TEntityBuilder<T>;
    function MaxLength(ALength: Integer): TEntityBuilder<T>;
    function MinLength(ALength: Integer): TEntityBuilder<T>;
    function Precision(APrecision, AScale: Integer): TEntityBuilder<T>;
    function HasDbType(ADataType: TFieldType): TEntityBuilder<T>;
    function HasConverter(AConverterClass: TClass): TEntityBuilder<T>;
    function IsJson(AUseJsonB: Boolean = True): TEntityBuilder<T>;
    function IsLazy(AValue: Boolean = True): TEntityBuilder<T>;
    function IsVersion(AValue: Boolean = True): TEntityBuilder<T>;
    function IsCreatedAt(AValue: Boolean = True): TEntityBuilder<T>;
    function IsUpdatedAt(AValue: Boolean = True): TEntityBuilder<T>;
    function IsDeletedAt(AValue: Boolean = True): TEntityBuilder<T>;
    function IsShadow(AValue: Boolean = True): TEntityBuilder<T>;
    function DisplayLabel(const AValue: string): TEntityBuilder<T>;
    function DisplayWidth(AValue: Integer): TEntityBuilder<T>;
    function DisplayFormat(const AValue: string): TEntityBuilder<T>;
    function EditMask(const AValue: string): TEntityBuilder<T>;
    function Alignment(AValue: TAlignment): TEntityBuilder<T>;
    function Ignore: TEntityBuilder<T>;
    
    // Relationship Support (Returning IRelationshipBuilder)
    function HasMany(const APropertyName: string): IRelationshipBuilder<T>;
    function HasOne(const APropertyName: string): IRelationshipBuilder<T>;
    function BelongsTo(const APropertyName: string): IRelationshipBuilder<T>;
    function HasManyToMany(const APropertyName: string): IRelationshipBuilder<T>;
    
    // Soft Delete Configuration
    function HasSoftDelete(const APropertyName: string): TEntityBuilder<T>; overload;
    function HasSoftDelete(const APropertyName: string; const ADeletedValue, ANotDeletedValue: Variant): TEntityBuilder<T>; overload;

    // Global Query Filters
    function HasQueryFilter(AFilter: IExpression): TEntityBuilder<T>;
  end;

  // ---------------------------------------------------------------------------
  // Concrete Builders (Legacy / Interface based)
  // ---------------------------------------------------------------------------

  /// <summary>
  ///   Concrete implementation of IEntityTypeBuilder for configuring entity mappings.
  /// </summary>
  TEntityTypeBuilder<T: class> = class(TInterfacedObject, IEntityTypeBuilder<T>)
  private
    FMap: TEntityMap;
  public
    constructor Create(AMap: TEntityMap);
    function ToTable(const AName: string): IEntityTypeBuilder<T>; overload;
    function ToTable(const AName, ASchema: string): IEntityTypeBuilder<T>; overload;
    function HasKey(const APropertyName: string): IEntityTypeBuilder<T>; overload;
    function HasKey(const APropertyNames: array of string): IEntityTypeBuilder<T>; overload;
    function HasDiscriminator(const AColumn: string; const AValue: Variant): IEntityTypeBuilder<T>;
    function MapInheritance(AStrategy: TInheritanceStrategy): IEntityTypeBuilder<T>;
    function Prop(const APropertyName: string): IPropertyBuilder<T>; overload;
    function Prop(const AProp: IPropInfo): IPropertyBuilder<T>; overload;
    function ShadowProperty(const APropName: string): IPropertyBuilder<T>;
    function Ignore(const APropertyName: string): IEntityTypeBuilder<T>;
    function HasMany(const APropertyName: string): IRelationshipBuilder<T>;
    function HasOne(const APropertyName: string): IRelationshipBuilder<T>;
    function BelongsTo(const APropertyName: string): IRelationshipBuilder<T>;
    function HasManyToMany(const APropertyName: string): IRelationshipBuilder<T>;
    function HasSoftDelete(const APropertyName: string): IEntityTypeBuilder<T>; overload;
    function HasSoftDelete(const APropertyName: string; const ADeletedValue, ANotDeletedValue: Variant): IEntityTypeBuilder<T>; overload;
    function HasQueryFilter(AFilter: IExpression): IEntityTypeBuilder<T>;
  end;

  /// <summary>
  ///   Concrete implementation of IPropertyBuilder for configuring property mappings.
  /// </summary>
  TPropertyBuilder<T: class> = class(TInterfacedObject, IPropertyBuilder<T>)
  private
    FPropMap: TPropertyMap;
    FEntityMap: TEntityMap;
  public
    constructor Create(APropMap: TPropertyMap; AEntityMap: TEntityMap = nil);
    function HasColumnName(const AName: string): IPropertyBuilder<T>;
    function IsRequired(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsAutoInc(AValue: Boolean = True): IPropertyBuilder<T>;
    function HasMaxLength(ALength: Integer): IPropertyBuilder<T>;
    function HasMinLength(ALength: Integer): IPropertyBuilder<T>;
    function HasPrecision(APrecision, AScale: Integer): IPropertyBuilder<T>;
    function HasDbType(ADataType: TFieldType): IPropertyBuilder<T>;
    function HasConverter(AConverterClass: TClass): IPropertyBuilder<T>;
    function HasFieldName(const AName: string): IPropertyBuilder<T>;
    function UseField: IPropertyBuilder<T>;
    function IsLazy(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsVersion(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsCreatedAt(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsUpdatedAt(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsDeletedAt(AValue: Boolean = True): IPropertyBuilder<T>;
    function IsShadow(AValue: Boolean = True): IPropertyBuilder<T>;
    function HasDisplayLabel(const AValue: string): IPropertyBuilder<T>;
    function HasDisplayWidth(AValue: Integer): IPropertyBuilder<T>;
    function HasDisplayFormat(const AValue: string): IPropertyBuilder<T>;
    function HasEditMask(const AValue: string): IPropertyBuilder<T>;
    function HasAlignment(AValue: TAlignment): IPropertyBuilder<T>;
    function IsReadOnly(AValue: Boolean = True): IPropertyBuilder<T>;
    /// <summary>
    ///   Configures this property to use a database sequence generator for primary key pre-allocation.
    /// </summary>
    /// <param name="ASequenceName">The name of the database sequence.</param>
    /// <param name="AAllocationSize">The block allocation size for in-memory HiLo pre-allocation (default is 50).</param>
    function UseSequence(const ASequenceName: string; AAllocationSize: Integer = 50): IPropertyBuilder<T>;
  end;

  /// <summary>
  ///   Base class for user configurations (easier to inherit from).
  /// </summary>
  TEntityTypeConfiguration<T: class> = class(TInterfacedObject, IEntityTypeConfiguration<T>)
  public
    procedure Configure(Builder: IEntityTypeBuilder<T>); virtual; abstract;
  end;

  /// <summary>
  ///   Central model builder that stores all framework mapping definitions.
  /// </summary>
  TModelBuilder = class
  private
    class var FInstance: TModelBuilder;
  private var
    FMaps: IDictionary<PTypeInfo, TEntityMap>;
    FDiscoveryNames: IDictionary<PTypeInfo, string>;
    FFactories: IDictionary<PTypeInfo, IDynamicDbSetFactory>;
    FLock: TDextMREW; // For thread safety (D.1)
    class constructor Create;

    class destructor Destroy;
    function LookupMap(AType: PTypeInfo): TEntityMap;
    procedure ResolveInheritance(AMap: TEntityMap);
  public
    constructor Create;
    destructor Destroy; override;
    
    procedure ApplyConfiguration<T: class>(AConfig: IEntityTypeConfiguration<T>);
    function Entity<T: class>: TEntityBuilder<T>;
    
    function GetMap(AType: PTypeInfo): TEntityMap;
    function HasMap(AType: PTypeInfo): Boolean;
    function GetMaps: TArray<TEntityMap>;
    
    procedure RegisterDiscoveryName(AType: PTypeInfo; const AName: string);
    function GetDiscoveryName(AType: PTypeInfo): string;
    
    function FindMapByDiscriminator(ABaseType: PTypeInfo; const AValue: Variant): TEntityMap;
    procedure Clear;
    
    procedure RegisterFactory(AType: PTypeInfo; const AFactory: IDynamicDbSetFactory);
    function GetFactory(AType: PTypeInfo): IDynamicDbSetFactory;
    
    class property Instance: TModelBuilder read FInstance;

  end;

  /// <summary>
  ///   Concrete implementation of IRelationshipBuilder for configuring relationship mappings.
  /// </summary>
  TRelationshipBuilder<T: class> = class(TInterfacedObject, IRelationshipBuilder<T>)
  private
    FMap: TEntityMap;
    FPropMap: TPropertyMap;
  public
    constructor Create(AMap: TEntityMap; APropMap: TPropertyMap);
    function WithOne(const AInversePropName: string = ''): IRelationshipBuilder<T>;
    function WithMany(const AInversePropName: string = ''): IRelationshipBuilder<T>;
    function HasForeignKey(const AFKPropertyName: string): IRelationshipBuilder<T>;
    function HasPrincipalKey(const AKeyPropertyName: string): IRelationshipBuilder<T>;
    function OnDelete(AAction: TCascadeAction): IRelationshipBuilder<T>;
    function UsingEntity(const AJoinTableName: string): IRelationshipBuilder<T>; overload;
    function UsingEntity(const AJoinTableName, ALeftKey, ARightKey: string): IRelationshipBuilder<T>; overload;
  end;

/// <summary>Creates the converter of a class chosen by [TypeConverter] or HasConverter.</summary>
function CreateConverterFromClass(AClass: TClass): ITypeConverter;

implementation

uses
  System.StrUtils,
  Dext.Utils;

// A converter chosen by [TypeConverter] or HasConverter is a class: create it.
function CreateConverterFromClass(AClass: TClass): ITypeConverter;
var
  Obj: TObject;
begin
  Obj := TReflection.CreateInstance(AClass);
  if not Supports(Obj, ITypeConverter, Result) then
  begin
    Obj.Free;
    raise EEntityMappingException.CreateFmt(
      'Class "%s" does not implement ITypeConverter.', [AClass.ClassName]);
  end;
end;

procedure TEntityMap.MarkDeletedAt(APropMap: TPropertyMap; AValue: Boolean);
begin
  APropMap.IsDeletedAt := AValue;
  if not AValue then
    Exit;
  // Only assume the soft delete rule if the class does not define one already
  if not FIsSoftDelete then
  begin
    FIsSoftDelete := True;
    FSoftDeleteProp := APropMap.PropertyName;
    FSoftDeleteDeletedValue := Null;
    FSoftDeleteNotDeletedValue := Null;
  end;
end;

constructor TEntityMap.Create(AEntityType: PTypeInfo);
begin
  FEntityType := AEntityType;
  FProperties := TCollections.CreateDictionaryIgnoreCase<string, TPropertyMap>(True);
  FOrderedProperties := TCollections.CreateList<TPropertyMap>;
  FKeys := TCollections.CreateList<string>;
  FQueryFilters := TCollections.CreateList<IExpression>;
  FIsSoftDelete := False;
  FSoftDeleteProp := '';
  FSoftDeleteDeletedValue := 1;  // Default (1 = Deleted)
  FSoftDeleteNotDeletedValue := 0; // Default (0 = Not Deleted)
  FDiscriminatorColumn := '';
  FDiscriminatorValue := Null;
  FIsProxy := False;

  DiscoverAttributes;
end;

destructor TEntityMap.Destroy;
begin
  FProperties := nil;
  FOrderedProperties := nil;
  FKeys := nil;
  FQueryFilters := nil;
  inherited;
end;

function TypeInfoToFieldType(ATypeInfo: PTypeInfo): TFieldType;
var
  TypeName: string;
begin
  if ATypeInfo = nil then Exit(ftUnknown);
  case ATypeInfo.Kind of
    tkInteger:
    begin
      TypeName := string(ATypeInfo.Name);
      if SameText(TypeName, 'SmallInt') then Result := ftSmallint
      else if SameText(TypeName, 'Byte') then Result := ftByte
      else if SameText(TypeName, 'ShortInt') then Result := ftShortint
      else if SameText(TypeName, 'Word') then Result := ftWord
      else Result := ftInteger;
    end;
    tkChar, tkWChar, tkLString, tkWString, tkUString: Result := ftWideString;
    tkFloat:
    begin
      if (ATypeInfo = TypeInfo(TDateTime)) or SameText(string(ATypeInfo.Name), 'TDateTime') then Result := ftDateTime
      else if (ATypeInfo = TypeInfo(TDate)) or SameText(string(ATypeInfo.Name), 'TDate') then Result := ftDate
      else if (ATypeInfo = TypeInfo(TTime)) or SameText(string(ATypeInfo.Name), 'TTime') then Result := ftTime
      else if (ATypeInfo = TypeInfo(Currency)) or SameText(string(ATypeInfo.Name), 'Currency') then Result := ftCurrency
      else Result := ftFloat;
    end;
    tkInt64: Result := ftLargeint;
    tkEnumeration:
    begin
      if (ATypeInfo = TypeInfo(Boolean)) or SameText(string(ATypeInfo.Name), 'Boolean') then Result := ftBoolean
      else Result := ftInteger;
    end;
  else
    Result := ftUnknown;
  end;
end;

procedure TEntityMap.ProcessAttribute(APropMap: TPropertyMap; AAttr: TCustomAttribute);
begin
  if  (AAttr is ColumnAttribute) or (AAttr is PrimaryKeyAttribute) or (AAttr is AutoIncAttribute) or 
      (AAttr is ForeignKeyAttribute) or (AAttr is NotMappedAttribute) or (AAttr is FieldAttribute) or
      (AAttr is RequiredAttribute) or (AAttr is MaxLengthAttribute) or (AAttr is MinLengthAttribute) or (AAttr is PrecisionAttribute) or
      (AAttr is TypeConverterAttribute) or (AAttr is HasManyAttribute) or (AAttr is BelongsToAttribute) or
      (AAttr is HasOneAttribute) or (AAttr is InversePropertyAttribute) or (AAttr is DeleteBehaviorAttribute) or
      (AAttr is ManyToManyAttribute) or (AAttr is VersionAttribute) or (AAttr is CreatedAtAttribute) or (AAttr is UpdatedAtAttribute) or (AAttr is DeletedAtAttribute) or
      (AAttr is JsonColumnAttribute) or (AAttr is DbTypeAttribute) or
      (AAttr is CaptionAttribute) or (AAttr is DisplayFormatAttribute) or (AAttr is DisplayWidthAttribute) or
      (AAttr is EditMaskAttribute) or (AAttr is AlignmentAttribute) or (AAttr is DefaultValueAttribute) or
      (AAttr is VisibleAttribute) or (AAttr is ReadOnlyAttribute) or
      (AAttr is LazyAttribute) or (AAttr is SequenceAttribute) then
  begin
    if AAttr is SequenceAttribute then
    begin
      APropMap.IsSequenced := True;
      APropMap.SequenceName := SequenceAttribute(AAttr).SequenceName;
      APropMap.SequenceAllocationSize := SequenceAttribute(AAttr).AllocationSize;
    end;
    if AAttr is LazyAttribute then APropMap.IsLazy := True;
    if AAttr is ColumnAttribute then APropMap.ColumnName := ColumnAttribute(AAttr).Name;
    if AAttr is FieldAttribute then 
    begin
      if FieldAttribute(AAttr).Name <> '' then
        APropMap.FieldName := FieldAttribute(AAttr).Name
      else
        APropMap.FieldName := TReflection.NormalizeFieldName(APropMap.PropertyName);
    end;
    if AAttr is PrimaryKeyAttribute then 
    begin
      APropMap.IsPK := True;
      if not FKeys.Contains(APropMap.PropertyName) then FKeys.Add(APropMap.PropertyName);
    end;
    if AAttr is AutoIncAttribute then APropMap.IsAutoInc := True;
    if AAttr is NotMappedAttribute then APropMap.IsIgnored := True;
    if AAttr is ForeignKeyAttribute then APropMap.ForeignKeyColumn := ForeignKeyAttribute(AAttr).ColumnName;
    if AAttr is DbTypeAttribute then APropMap.DataType := DbTypeAttribute(AAttr).DataType;
    if AAttr is TypeConverterAttribute then
  begin
    APropMap.ConverterClass := TypeConverterAttribute(AAttr).ConverterClass;
    APropMap.Converter := CreateConverterFromClass(APropMap.ConverterClass);
  end;

    if AAttr is RequiredAttribute then APropMap.IsRequired := True;
    if AAttr is MaxLengthAttribute then APropMap.MaxLength := MaxLengthAttribute(AAttr).Length;
    if AAttr is MinLengthAttribute then APropMap.MinLength := MinLengthAttribute(AAttr).Length;
    if AAttr is PrecisionAttribute then
    begin
      APropMap.Precision := PrecisionAttribute(AAttr).Precision;
      APropMap.Scale := PrecisionAttribute(AAttr).Scale;
    end;

    // Relationships
    if AAttr is HasManyAttribute then 
    begin
      APropMap.Relationship := rtOneToMany;
      APropMap.IsNavigation := True;
    end;
    if AAttr is BelongsToAttribute then 
    begin
      APropMap.Relationship := rtManyToOne;
      APropMap.IsNavigation := True;
    end;
    if AAttr is HasOneAttribute then 
    begin
      APropMap.Relationship := rtOneToOne;
      APropMap.IsNavigation := True;
    end;
    if AAttr is ManyToManyAttribute then 
    begin
      APropMap.Relationship := rtManyToMany;
      APropMap.IsNavigation := True;
      APropMap.JoinTableName := ManyToManyAttribute(AAttr).JoinTableName;
      APropMap.LeftKeyColumn := ManyToManyAttribute(AAttr).LeftKeyColumn;
      APropMap.RightKeyColumn := ManyToManyAttribute(AAttr).RightKeyColumn;
    end;
    if AAttr is InversePropertyAttribute then 
    begin
      APropMap.InverseProperty := InversePropertyAttribute(AAttr).Name;
      APropMap.IsNavigation := True;
    end;
    if AAttr is DeleteBehaviorAttribute then APropMap.DeleteBehavior := DeleteBehaviorAttribute(AAttr).Behavior;
    
    // Optimistic Concurrency
    if AAttr is VersionAttribute then APropMap.IsVersion := True;
    
    // Audit Timestamps
    if AAttr is CreatedAtAttribute then APropMap.IsCreatedAt := True;
    if AAttr is UpdatedAtAttribute then APropMap.IsUpdatedAt := True;
    if AAttr is DeletedAtAttribute then
      MarkDeletedAt(APropMap);
    
    // JSON Column
    if AAttr is JsonColumnAttribute then
    begin
      APropMap.IsJsonColumn := True;
      APropMap.UseJsonB := JsonColumnAttribute(AAttr).UseJsonB;
      // A class stored as JSON is a column, not a relationship to another entity
      APropMap.IsNavigation := False;
      APropMap.Relationship := rtNone;
    end;
    
    // UI Metadata
    if AAttr is CaptionAttribute then APropMap.DisplayLabel := CaptionAttribute(AAttr).Value;
    if AAttr is DisplayFormatAttribute then APropMap.DisplayFormat := DisplayFormatAttribute(AAttr).Value;
    if AAttr is DisplayWidthAttribute then APropMap.DisplayWidth := DisplayWidthAttribute(AAttr).Value;
    if AAttr is EditMaskAttribute then APropMap.EditMask := EditMaskAttribute(AAttr).Value;
    if AAttr is AlignmentAttribute then APropMap.Alignment := AlignmentAttribute(AAttr).Alignment;
    if AAttr is DefaultValueAttribute then APropMap.DefaultValue := DefaultValueAttribute(AAttr).Value;
    if AAttr is VisibleAttribute then APropMap.Visible := VisibleAttribute(AAttr).Visible;
    if AAttr is ReadOnlyAttribute then APropMap.IsReadOnly := ReadOnlyAttribute(AAttr).ReadOnly;
  end;
end;

procedure TEntityMap.DiscoverAttributes;
var
  Typ: TRttiType;
  BaseTyp: TRttiType;
  BaseTable: TableAttribute;
  BaseIsTPH: Boolean;
  Attr: TCustomAttribute;
  Prop: TRttiProperty;
  PropMap: TPropertyMap;
  Fld: TRttiField;
  Metadata: TTypeMetadata;
  IsSmart: Boolean;
  FldName: string;
  LPropInfo: PPropInfo;
  LTypeConv: ITypeConverter;
  BackingFld: TRttiField;
  Meta: TTypeMetadata;
  LTypeName: string;

  InnerTypeInfo: PTypeInfo;
  IsInnerNullable: Boolean;
  InnerCleanName: string;
  PropMeta: TTypeMetadata;
  InnerMeta2: TTypeMetadata;
  BaseOffset: Integer;
  BackingInnerType: PTypeInfo;
  IsBackingInnerNullable: Boolean;
  BackingCleanName: string;
  InnerMeta: TTypeMetadata;
  BackingInnerCheckType: PTypeInfo;
  IsBackingInnerCheckNullable: Boolean;
  BackingInnerCheckClean: string;

  function CleanTypeName(const AName: string): string;
  var
    LTMark: Integer;
    Prefix: string;
    LastDot: Integer;
  begin
    LTMark := AName.IndexOf('<');
    if LTMark >= 0 then
    begin
      Prefix := AName.Substring(0, LTMark);
      LastDot := Prefix.LastIndexOf('.');
      if LastDot >= 0 then
        Result := Prefix.Substring(LastDot + 1) + AName.Substring(LTMark)
      else
        Result := AName;
    end
    else
    begin
      LastDot := AName.LastIndexOf('.');
      if LastDot >= 0 then
        Result := AName.Substring(LastDot + 1)
      else
        Result := AName;
    end;
  end;

begin
  Typ := TReflection.Context.GetType(FEntityType);
  if Typ = nil then Exit;

  // A subclass in a table-per-hierarchy inherits the strategy and the discriminator
  // column that the root declares with attributes
  BaseTyp := Typ;
  BaseTable := nil;
  BaseIsTPH := False;
  while (BaseTyp is TRttiInstanceType) and (TRttiInstanceType(BaseTyp).BaseType <> nil) do
  begin
    BaseTyp := TRttiInstanceType(BaseTyp).BaseType;
    for Attr in BaseTyp.GetAttributes do
    begin
      if Attr is TableAttribute then
        BaseTable := TableAttribute(Attr);
      if (Attr is InheritanceAttribute) and
         (InheritanceAttribute(Attr).Strategy = TInheritanceStrategy.TablePerHierarchy) then
        BaseIsTPH := True;
      if (Attr is InheritanceAttribute) and (FInheritanceStrategy = TInheritanceStrategy.None) then
        FInheritanceStrategy := InheritanceAttribute(Attr).Strategy;
      if (Attr is DiscriminatorColumnAttribute) and (FDiscriminatorColumn = '') then
        FDiscriminatorColumn := DiscriminatorColumnAttribute(Attr).Name;
    end;
  end;
  // The subclass of a TPH root declared with attributes uses the root's table
  // (its own [Table], if any, is read below and wins)
  if BaseIsTPH and (BaseTable <> nil) then
  begin
    FTableName := BaseTable.Name;
    FSchema := BaseTable.Schema;
  end;

  for Attr in Typ.GetAttributes do
    begin
      if Attr is TableAttribute then
      begin
        FTableName := TableAttribute(Attr).Name;
        FSchema := TableAttribute(Attr).Schema;
      end;
      if Attr is SoftDeleteAttribute then
      begin
        FIsSoftDelete := True;
        FSoftDeleteProp := SoftDeleteAttribute(Attr).ColumnName;
        FSoftDeleteDeletedValue := SoftDeleteAttribute(Attr).DeletedValue;
        FSoftDeleteNotDeletedValue := SoftDeleteAttribute(Attr).NotDeletedValue;
      end;
      if Attr is InheritanceAttribute then FInheritanceStrategy := InheritanceAttribute(Attr).Strategy;
      if Attr is DiscriminatorColumnAttribute then FDiscriminatorColumn := DiscriminatorColumnAttribute(Attr).Name;
      if Attr is DiscriminatorValueAttribute then FDiscriminatorValue := DiscriminatorValueAttribute(Attr).Value;
      if Attr is ProxyAttribute then FIsProxy := True;
    end;
    
    for Fld in Typ.GetFields do
    begin
      // 1. Smart Properties (detected by TReflection which handles attributes, naming and aliases)
      Metadata := TReflection.GetMetadata(Fld.FieldType.Handle);
      IsSmart := Metadata.IsSmartProp or Metadata.IsNullable or Metadata.IsLazy;

      FldName := TReflection.NormalizeFieldName(Fld.Name);

      if IsSmart then
      begin
          
        if Metadata.IsNullable and (Metadata.InnerType <> nil) and TReflection.IsSmartProp(Metadata.InnerType) then
        begin
          DebugLog(Format(
            '[Dext.Orm] WARNING: Field "%s.%s" is declared as legacy "Nullable<Prop<T>>". ' +
            'This pattern is deprecated and causes silent issues in query ordering (OrderBy). ' +
            'Please change its declaration to "Prop<Nullable<%s>>" for full type safety.',
            [Typ.Name, FldName, string(TReflection.GetMetadata(Metadata.InnerType).InnerType^.Name)]
          ));
        end;
          
        PropMap := GetOrAddProperty(FldName);
        PropMap.FieldOffset := -1; // Reset to avoid incorrect null detection for records
        PropMap.FieldValueOffset := -1;
        PropMap.IsLazy := Metadata.IsLazy;

        // Skip fast path for Lazy to force RTTI (which triggers Load)
        if not PropMap.IsLazy then
        begin
          // S22 Composition support: Prop<Nullable<T>>
          InnerTypeInfo := Metadata.InnerType;
          IsInnerNullable := False;
          if InnerTypeInfo <> nil then
          begin
            InnerCleanName := CleanTypeName(string(InnerTypeInfo.Name));
            IsInnerNullable := InnerCleanName.Contains('Nullable');
          end;
          
          if IsInnerNullable then
          begin
            Meta := TReflection.GetMetadata(Metadata.InnerType);
            if Metadata.ValueField <> nil then
            begin
              if Meta.HasValueField <> nil then
              begin
                if Meta.HasValueField.FieldType.Handle = TypeInfo(Boolean) then
                  PropMap.FieldOffset := Fld.Offset + Metadata.ValueField.Offset + Meta.HasValueField.Offset
                else if Meta.HasValueField.FieldType.TypeKind = tkInterface then
                  PropMap.MetadataOffset := Fld.Offset + Metadata.ValueField.Offset + Meta.HasValueField.Offset;
              end;

              if Meta.ValueField <> nil then
              begin
                PropMap.FieldValueOffset := Fld.Offset + Metadata.ValueField.Offset + Meta.ValueField.Offset;
                PropMap.PropertyType := Meta.InnerType;
                PropMap.DataType := TypeInfoToFieldType(Meta.InnerType);
                PropMap.IsEnum := (Meta.InnerType <> nil) and (Meta.InnerType.Kind = tkEnumeration) and (Meta.InnerType <> TypeInfo(Boolean));
              end;
            end;
          end
          else
          begin
            // CRITICAL: We separate NullFlag and MetadataOffset.
            // TEntityDataSet uses FieldOffset to check for NULL via PBoolean (must be boolean).
            // Prototype usage needs FInfo, which is an Interface (must NOT be treated as null flag).
            if Metadata.HasValueField <> nil then
            begin
              if Metadata.HasValueField.FieldType.Handle = TypeInfo(Boolean) then
                PropMap.FieldOffset := Fld.Offset + Metadata.HasValueField.Offset
              else if Metadata.HasValueField.FieldType.TypeKind = tkInterface then
                PropMap.MetadataOffset := Fld.Offset + Metadata.HasValueField.Offset;
            end;

            if Metadata.ValueField <> nil then
            begin
              PropMap.FieldValueOffset := Fld.Offset + Metadata.ValueField.Offset;
              PropMap.PropertyType := Metadata.InnerType;
              PropMap.DataType := TypeInfoToFieldType(Metadata.InnerType);
              PropMap.IsEnum := (Metadata.InnerType <> nil) and (Metadata.InnerType.Kind = tkEnumeration) and (Metadata.InnerType <> TypeInfo(Boolean));
            end;
          end;
        end;
        
        // Processar atributos do campo
        for Attr in Fld.GetAttributes do
          ProcessAttribute(PropMap, Attr);

        if PropMap.PropertyType <> nil then
          PropMap.NativeKind := TDextTypeModel.NativeKindOf(PropMap.PropertyType);
      end
      // 2. Campos normais públicos ou com atributos
      else if (Fld.Visibility in [mvPublic, mvPublished]) or (Length(Fld.GetAttributes) > 0) then
      begin
        FldName := Fld.Name;
        if (FldName.Length > 1) and (FldName[1] = 'F') then
          FldName := FldName.Substring(1);
          
        PropMap := GetOrAddProperty(FldName);
        if PropMap.FieldValueOffset <= 0 then
        begin
           PropMap.FieldValueOffset := Fld.Offset;
           PropMap.PropertyType := Fld.FieldType.Handle;
           PropMap.DataType := TypeInfoToFieldType(Fld.FieldType.Handle);
           PropMap.IsEnum := (Fld.FieldType.TypeKind = tkEnumeration) and (Fld.FieldType.Handle <> TypeInfo(Boolean));
        end;
        
        for Attr in Fld.GetAttributes do
          ProcessAttribute(PropMap, Attr);

        if PropMap.PropertyType <> nil then
          PropMap.NativeKind := TDextTypeModel.NativeKindOf(PropMap.PropertyType);
      end;
    end;

    for Prop in Typ.GetProperties do
    begin
      PropMap := GetOrAddProperty(Prop.Name);
      
      // Basic type info
      if PropMap.PropertyType = nil then
        PropMap.PropertyType := Prop.PropertyType.Handle;
      if PropMap.DataType = ftUnknown then
        PropMap.DataType := TypeInfoToFieldType(Prop.PropertyType.Handle);

      PropMap.IsEnum := (Prop.PropertyType.TypeKind = tkEnumeration) and (Prop.PropertyType.Handle <> TypeInfo(Boolean));
      PropMap.Prop := Prop; // Cache the RTTI property for fast access
      
      // If the property has a getter or setter method, we should not use direct field access (Fast Path)
      // as it might bypass business logic or calculated values.
      if Prop is TRttiInstanceProperty then
      begin
        LPropInfo := TRttiInstanceProperty(Prop).PropInfo;
        if Assigned(LPropInfo) then
        begin
          // If GetProc points to a field (high-byte $FF), it's a direct field access property (e.g., 'read FCurrencyVal').
          // In this case, we extract the actual memory offset of the private field to enable the 'Fast Path' performance boost.
          // Note: We MUST NOT overwrite offsets for SmartProps (Nullable/Lazy) already detected in the Fields loop.
          // PROPSLOT_MASK/PROPSLOT_FIELD (System.TypInfo) are $FF000000 on 32-bit
          // and $FF00000000000000 on 64-bit: a fixed $FF000000 never matched a
          // field getter on Win64.
          if (not PropMap.IsLazy) and
             ((IntPtr(LPropInfo.GetProc) and PROPSLOT_MASK) = PROPSLOT_FIELD) then
          begin
            if PropMap.FieldValueOffset <= 0 then
              PropMap.FieldValueOffset := Integer(IntPtr(LPropInfo.GetProc) and not PROPSLOT_MASK);
          end
          else
          begin
             // It's a method getter - we cannot use direct memory access (Fast Path).
             PropMap.FieldValueOffset := 0;
          end;

          // Double check SetProc to ensure it's also a field mapping or a method
          if (PropMap.FieldValueOffset <> 0) and (NativeInt(LPropInfo.SetProc) <> 0) and
             ((IntPtr(LPropInfo.SetProc) and PROPSLOT_MASK) <> PROPSLOT_FIELD) then
          begin
             PropMap.FieldValueOffset := 0;
          end;
        end;
      end;

      // S22: For Prop<Nullable<T>> properties accessed via direct field accessor,
      // the TRttiInstanceProperty block above set FieldValueOffset to the raw offset
      // of the entire Prop<Nullable<T>> record. We must now decompose it into proper
      // composition offsets: FieldOffset (null flag) and FieldValueOffset (inner T value).
      if (not PropMap.IsLazy) and (PropMap.FieldValueOffset > 0) and
         TReflection.IsSmartProp(Prop.PropertyType.Handle) then
      begin
        PropMeta := TReflection.GetMetadata(Prop.PropertyType.Handle);
        if PropMeta.IsSmartProp and (PropMeta.InnerType <> nil) then
        begin
          InnerCleanName := CleanTypeName(string(PropMeta.InnerType.Name));
          if InnerCleanName.Contains('Nullable') then
          begin
            // This is Prop<Nullable<T>> - decompose composition offsets
            InnerMeta2 := TReflection.GetMetadata(PropMeta.InnerType);
            if (PropMeta.ValueField <> nil) and InnerMeta2.IsNullable then
            begin
              BaseOffset := PropMap.FieldValueOffset; // raw offset of the Prop<Nullable<T>> field
              if InnerMeta2.HasValueField <> nil then
              begin
                if InnerMeta2.HasValueField.FieldType.Handle = TypeInfo(Boolean) then
                  PropMap.FieldOffset := BaseOffset + PropMeta.ValueField.Offset + InnerMeta2.HasValueField.Offset
                else if InnerMeta2.HasValueField.FieldType.TypeKind = tkInterface then
                  PropMap.MetadataOffset := BaseOffset + PropMeta.ValueField.Offset + InnerMeta2.HasValueField.Offset;
              end;
              if InnerMeta2.ValueField <> nil then
              begin
                PropMap.FieldValueOffset := BaseOffset + PropMeta.ValueField.Offset + InnerMeta2.ValueField.Offset;
                PropMap.PropertyType := InnerMeta2.InnerType;
                PropMap.DataType := TypeInfoToFieldType(InnerMeta2.InnerType);
                PropMap.IsEnum := (InnerMeta2.InnerType <> nil) and (InnerMeta2.InnerType.Kind = tkEnumeration) and (InnerMeta2.InnerType <> TypeInfo(Boolean));
              end;
            end;
          end;
        end;
      end;

      if Prop.PropertyType.TypeKind in [tkClass, tkInterface] then
      begin
        // Filter out classes that have a registered converter (e.g. TStrings)
        // These should be treated as columns, not navigation properties.
        LTypeConv := TTypeConverterRegistry.Instance.GetConverter(Prop.PropertyType.Handle);
        
        if LTypeConv = nil then
        begin
          PropMap.IsNavigation := True;
          if Prop.PropertyType.TypeKind = tkInterface then
            PropMap.Relationship := rtOneToMany // Likely IList<T>
          else
            PropMap.Relationship := rtManyToOne; // Likely an entity reference
        end
        else
        begin
            // It's a convertible class (like TStrings). Treat as a normal column.
            PropMap.IsNavigation := False;
            PropMap.Relationship := rtNone;
            PropMap.Converter := LTypeConv;
        end;
      end;

      // Try to find the backing field by convention (FPropName) if offset is not set
      if PropMap.FieldValueOffset <= 0 then
      begin
        BackingFld := Typ.GetField(TReflection.NormalizeFieldName(Prop.Name));
        if BackingFld <> nil then
        begin
           // If the backing field is a SmartProp, we need to extract the inner offset
           if TReflection.IsSmartProp(BackingFld.FieldType.Handle) then
           begin
             Meta := TReflection.GetMetadata(BackingFld.FieldType.Handle);
                 if Meta.IsSmartProp then
                 begin
                   // Detect Lazy
                    if Meta.RttiType.Name.Contains('Lazy<') then
                      PropMap.IsLazy := True;

                  // Lazy types store an interface (ILazy), not the value T directly in the record.
                  // We MUST NOT set FieldValueOffset for them if we want to support direct memory access for T.
                  // Instead, we skip direct offset mapping so the engine falls back to RTTI (which handles ILazy).
                  if not PropMap.IsLazy then
                  begin
                    // S22 Composition support: Prop<Nullable<T>> backing field
                    BackingInnerType := Meta.InnerType;
                    IsBackingInnerNullable := False;
                    if BackingInnerType <> nil then
                    begin
                      BackingCleanName := CleanTypeName(string(BackingInnerType.Name));
                      IsBackingInnerNullable := BackingCleanName.Contains('Nullable');
                    end;
                    
                    if IsBackingInnerNullable then
                    begin
                      InnerMeta := TReflection.GetMetadata(Meta.InnerType);
                      if Meta.ValueField <> nil then
                      begin
                        if InnerMeta.HasValueField <> nil then
                        begin
                          if InnerMeta.HasValueField.FieldType.Handle = TypeInfo(Boolean) then
                            PropMap.FieldOffset := BackingFld.Offset + Meta.ValueField.Offset + InnerMeta.HasValueField.Offset
                          else if InnerMeta.HasValueField.FieldType.TypeKind = tkInterface then
                            PropMap.MetadataOffset := BackingFld.Offset + Meta.ValueField.Offset + InnerMeta.HasValueField.Offset;
                        end;

                        if InnerMeta.ValueField <> nil then
                        begin
                          PropMap.FieldValueOffset := BackingFld.Offset + Meta.ValueField.Offset + InnerMeta.ValueField.Offset;
                          PropMap.PropertyType := InnerMeta.InnerType;
                          PropMap.DataType := TypeInfoToFieldType(InnerMeta.InnerType);
                          PropMap.IsEnum := (InnerMeta.InnerType <> nil) and (InnerMeta.InnerType.Kind = tkEnumeration) and (InnerMeta.InnerType <> TypeInfo(Boolean));
                        end;
                      end;
                    end
                    else
                    begin
                      PropMap.FieldValueOffset := BackingFld.Offset + Meta.ValueField.Offset;

                      // Only use FieldOffset if it's a Boolean (real null flag)
                      if (Meta.HasValueField <> nil) and (Meta.HasValueField.FieldType.Handle = TypeInfo(Boolean)) then
                        PropMap.FieldOffset := BackingFld.Offset + Meta.HasValueField.Offset;
                    end;
                  end;
                  
                  BackingInnerCheckType := Meta.InnerType;
                  IsBackingInnerCheckNullable := False;
                  if BackingInnerCheckType <> nil then
                  begin
                    BackingInnerCheckClean := CleanTypeName(string(BackingInnerCheckType.Name));
                    IsBackingInnerCheckNullable := BackingInnerCheckClean.Contains('Nullable');
                  end;
                  
                  if not IsBackingInnerCheckNullable then
                    PropMap.PropertyType := Meta.InnerType;
                    
                  // Update FieldOffset if not yet set
                  if PropMap.FieldValueOffset <= 0 then
                    PropMap.FieldValueOffset := BackingFld.Offset;

                  PropMap.Prop := Prop;
                end;
           end
           else
           begin
             PropMap.FieldValueOffset := BackingFld.Offset;
           end;
        end;
      end;

      for Attr in Prop.GetAttributes do
        ProcessAttribute(PropMap, Attr);

      if PropMap.PropertyType <> nil then
        PropMap.NativeKind := TDextTypeModel.NativeKindOf(PropMap.PropertyType);
      
      // Resolve Converter (Optimization)
      if PropMap.Converter = nil then
        PropMap.Converter := TTypeConverterRegistry.Instance.GetConverter(Prop.PropertyType.Handle);

      // Automatically mark large types (TStrings, TBytes) as Lazy
      if (PropMap.Converter <> nil) and not PropMap.IsPK and not PropMap.IsNavigation then
      begin
          LTypeName := string(Prop.PropertyType.Handle.Name);
          if (LTypeName = 'TStrings') or (LTypeName = 'TBytes') then
            PropMap.IsLazy := True;
      end;
    end;
end;

function TEntityMap.GetOrAddProperty(const APropName: string): TPropertyMap;
begin
  if not FProperties.TryGetValue(APropName, Result) then
  begin
    Result := TPropertyMap.Create(APropName);
    FProperties.Add(APropName, Result);
    FOrderedProperties.Add(Result);
  end;
end;

function TEntityMap.GetOrderedProperties: TArray<TPropertyMap>;
begin
  Result := FOrderedProperties.ToArray;
end;

procedure TEntityMap.InheritFrom(ARoot: TEntityMap);
var
  RootProp, OwnProp: TPropertyMap;
  Fld: TRttiField;
  Typ: TRttiType;
  Key: string;
begin
  if FTableName = '' then
  begin
    FTableName := ARoot.TableName;
    FSchema := ARoot.Schema;
  end;
  if FDiscriminatorColumn = '' then
    FDiscriminatorColumn := ARoot.DiscriminatorColumn;
  if FKeys.Count = 0 then
    for Key in ARoot.Keys do
      FKeys.Add(Key);
  Typ := TReflection.Context.GetType(TPropertyMap);
  for RootProp in ARoot.OrderedProperties do
  begin
    // Only the properties the subclass inherits
    if not FProperties.TryGetValue(RootProp.PropertyName, OwnProp) then Continue;
    for Fld in Typ.GetFields do
      Fld.SetValue(OwnProp, Fld.GetValue(RootProp));
  end;
end;

procedure TEntityMap.RequireClassProperty(const AName: string);
var
  Typ: TRttiType;
begin
  Typ := TReflection.Context.GetType(FEntityType);
  if (Typ <> nil) and (Typ.GetProperty(AName) = nil) and (Typ.GetField(AName) = nil) then
    raise EEntityMappingException.CreateFmt(
      'Property "%s" does not exist in entity "%s". If it is not part of the class, ' +
      'declare it with ShadowProperty.', [AName, string(FEntityType.Name)]);
end;

{ TPropertyMap }

constructor TPropertyMap.Create(const APropName: string);
begin
  PropertyName := APropName;
  ColumnName := APropName; // Default
  ForeignKeyColumn := '';
  DefaultValue := Null;
  IsPK := False;
  IsAutoInc := False;
  IsRequired := False;
  MaxLength := 0;
  MinLength := 0;
  Precision := 0;
  Scale := 0;
  IsIgnored := False;
  IsNavigation := False;
  Relationship := rtNone;
  InverseProperty := '';
  PrincipalKey := '';
  DeleteBehavior := caNoAction;
  JoinTableName := '';
  LeftKeyColumn := '';
  RightKeyColumn := '';
  DataType := ftUnknown;
  ConverterClass := nil;
  Converter := nil;
  // New fields
  IsVersion := False;
  IsCreatedAt := False;
  IsUpdatedAt := False;
  FieldOffset := -1; 
  MetadataOffset := -1;
  FieldValueOffset := -1;
  PropertyType := nil;
  NativeKind := nkUnknown;
  IsShadow := False;
  IsJsonColumn := False;
  UseJsonB := True; // Default for PostgreSQL
  IsEnum := False;
  DisplayLabel := '';
  DisplayFormat := '';
  DisplayWidth := 0;
  EditMask := '';
  Alignment := taLeftJustify;
  Visible := True;
end;

{ TRelationshipBuilder<T> }

constructor TRelationshipBuilder<T>.Create(AMap: TEntityMap; APropMap: TPropertyMap);
begin
  inherited Create;
  FMap := AMap;
  FPropMap := APropMap;
end;

function TRelationshipBuilder<T>.WithOne(const AInversePropName: string): IRelationshipBuilder<T>;
begin
  FPropMap.InverseProperty := AInversePropName;
  Result := Self;
end;

function TRelationshipBuilder<T>.WithMany(const AInversePropName: string): IRelationshipBuilder<T>;
begin
  FPropMap.InverseProperty := AInversePropName;
  Result := Self;
end;

function TRelationshipBuilder<T>.HasForeignKey(const AFKPropertyName: string): IRelationshipBuilder<T>;
begin
  FPropMap.ForeignKeyColumn := AFKPropertyName;
  Result := Self;
end;

function TRelationshipBuilder<T>.HasPrincipalKey(const AKeyPropertyName: string): IRelationshipBuilder<T>;
begin
  FPropMap.PrincipalKey := AKeyPropertyName;
  Result := Self;
end;

function TRelationshipBuilder<T>.OnDelete(AAction: TCascadeAction): IRelationshipBuilder<T>;
begin
  FPropMap.DeleteBehavior := AAction;
  Result := Self;
end;

function TRelationshipBuilder<T>.UsingEntity(const AJoinTableName: string): IRelationshipBuilder<T>;
begin
  FPropMap.JoinTableName := AJoinTableName;
  Result := Self;
end;

function TRelationshipBuilder<T>.UsingEntity(const AJoinTableName, ALeftKey, ARightKey: string): IRelationshipBuilder<T>;
begin
  FPropMap.JoinTableName := AJoinTableName;
  FPropMap.LeftKeyColumn := ALeftKey;
  FPropMap.RightKeyColumn := ARightKey;
  Result := Self;
end;

{ TEntityBuilder<T> }

constructor TEntityBuilder<T>.Create(AMap: TEntityMap);
begin
  FMap := AMap;
  FCurrentProp := nil;
end;

function TEntityBuilder<T>.GetCurrentProp: TPropertyMap;
begin
  if FCurrentProp = nil then
    raise Exception.Create('No property selected. Call Property() first.');
  Result := FCurrentProp;
end;

function TEntityBuilder<T>.Table(const AName: string): TEntityBuilder<T>;
begin
  FMap.TableName := AName;
  Result := Self;
end;

function TEntityBuilder<T>.Table(const AName, ASchema: string): TEntityBuilder<T>;
begin
  FMap.TableName := AName;
  FMap.Schema := ASchema;
  Result := Self;
end;

function TEntityBuilder<T>.HasKey(const APropertyName: string): TEntityBuilder<T>;
begin
  FMap.Keys.Clear;
  FMap.RequireClassProperty(APropertyName);
  FMap.Keys.Add(APropertyName);
  FMap.GetOrAddProperty(APropertyName).IsPK := True;
  Result := Self;
end;

function TEntityBuilder<T>.HasKey(const APropertyNames: array of string): TEntityBuilder<T>;
var
  Prop: string;
begin
  FMap.Keys.Clear;
  for Prop in APropertyNames do
  begin
    FMap.RequireClassProperty(Prop);
    FMap.Keys.Add(Prop);
    FMap.GetOrAddProperty(Prop).IsPK := True;
  end;
  Result := Self;
end;

function TEntityBuilder<T>.HasDiscriminator(const AColumn: string; const AValue: Variant): TEntityBuilder<T>;
begin
  FMap.DiscriminatorColumn := AColumn;
  FMap.DiscriminatorValue := AValue;
  FMap.InheritanceStrategy := TInheritanceStrategy.TablePerHierarchy; // Default to TPH if Discriminator is set
  Result := Self;
end;

function TEntityBuilder<T>.MapInheritance(AStrategy: TInheritanceStrategy): TEntityBuilder<T>;
begin
  FMap.InheritanceStrategy := AStrategy;
  Result := Self;
end;

function TEntityBuilder<T>.Prop(const APropertyName: string): TEntityBuilder<T>;
begin
  FMap.RequireClassProperty(APropertyName);
  FCurrentProp := FMap.GetOrAddProperty(APropertyName);
  Result := Self;
end;

function TEntityBuilder<T>.ShadowProperty(const APropName: string): TEntityBuilder<T>;
begin
  FCurrentProp := FMap.GetOrAddProperty(APropName);
  FCurrentProp.IsShadow := True;
  Result := Self;
end;

function TEntityBuilder<T>.HasProperty(const APropertyName: string): TEntityBuilder<T>;
begin
  Result := Prop(APropertyName);
end;

function TEntityBuilder<T>.Column(const AName: string): TEntityBuilder<T>;
begin
  GetCurrentProp.ColumnName := AName;
  Result := Self;
end;

function TEntityBuilder<T>.HasForeignKey(const AColumnName: string): TEntityBuilder<T>;
begin
  GetCurrentProp.ForeignKeyColumn := AColumnName;
  Result := Self;
end;

function TEntityBuilder<T>.IsRequired(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsRequired := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.IsAutoInc(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsAutoInc := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.UseSequence(const ASequenceName: string; AAllocationSize: Integer): TEntityBuilder<T>;
begin
  GetCurrentProp.IsSequenced := True;
  GetCurrentProp.SequenceName := ASequenceName;
  GetCurrentProp.SequenceAllocationSize := AAllocationSize;
  Result := Self;
end;

function TEntityBuilder<T>.MaxLength(ALength: Integer): TEntityBuilder<T>;
begin
  GetCurrentProp.MaxLength := ALength;
  Result := Self;
end;

function TEntityBuilder<T>.MinLength(ALength: Integer): TEntityBuilder<T>;
begin
  GetCurrentProp.MinLength := ALength;
  Result := Self;
end;

function TEntityBuilder<T>.Precision(APrecision, AScale: Integer): TEntityBuilder<T>;
begin
  GetCurrentProp.Precision := APrecision;
  GetCurrentProp.Scale := AScale;
  Result := Self;
end;

function TEntityBuilder<T>.HasDbType(ADataType: TFieldType): TEntityBuilder<T>;
begin
  GetCurrentProp.DataType := ADataType;
  Result := Self;
end;

function TEntityBuilder<T>.IsJson(AUseJsonB: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsJsonColumn := True;
  GetCurrentProp.UseJsonB := AUseJsonB;
  // A class stored as JSON is a column, not a relationship to another entity
  GetCurrentProp.IsNavigation := False;
  GetCurrentProp.Relationship := rtNone;
  Result := Self;
end;

function TEntityBuilder<T>.IsLazy(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsLazy := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.IsVersion(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsVersion := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.IsCreatedAt(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsCreatedAt := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.IsDeletedAt(AValue: Boolean): TEntityBuilder<T>;
begin
  FMap.MarkDeletedAt(GetCurrentProp, AValue);
  Result := Self;
end;

function TEntityBuilder<T>.IsUpdatedAt(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsUpdatedAt := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.IsShadow(AValue: Boolean): TEntityBuilder<T>;
begin
  GetCurrentProp.IsShadow := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.DisplayLabel(const AValue: string): TEntityBuilder<T>;
begin
  GetCurrentProp.DisplayLabel := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.DisplayWidth(AValue: Integer): TEntityBuilder<T>;
begin
  GetCurrentProp.DisplayWidth := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.DisplayFormat(const AValue: string): TEntityBuilder<T>;
begin
  GetCurrentProp.DisplayFormat := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.EditMask(const AValue: string): TEntityBuilder<T>;
begin
  GetCurrentProp.EditMask := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.Alignment(AValue: TAlignment): TEntityBuilder<T>;
begin
  GetCurrentProp.Alignment := AValue;
  Result := Self;
end;

function TEntityBuilder<T>.Ignore: TEntityBuilder<T>;
begin
  GetCurrentProp.IsIgnored := True;
  Result := Self;
end;

function TEntityBuilder<T>.HasMany(const APropertyName: string): IRelationshipBuilder<T>;
var
  LProp: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  LProp := FMap.GetOrAddProperty(APropertyName);
  LProp.IsNavigation := True;
  LProp.Relationship := rtOneToMany;
  Result := TRelationshipBuilder<T>.Create(FMap, LProp);
end;

function TEntityBuilder<T>.HasOne(const APropertyName: string): IRelationshipBuilder<T>;
var
  LProp: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  LProp := FMap.GetOrAddProperty(APropertyName);
  LProp.IsNavigation := True;
  LProp.Relationship := rtOneToOne;
  Result := TRelationshipBuilder<T>.Create(FMap, LProp);
end;

function TEntityBuilder<T>.BelongsTo(const APropertyName: string): IRelationshipBuilder<T>;
var
  LProp: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  LProp := FMap.GetOrAddProperty(APropertyName);
  LProp.IsNavigation := True;
  LProp.Relationship := rtManyToOne;
  Result := TRelationshipBuilder<T>.Create(FMap, LProp);
end;

function TEntityBuilder<T>.HasManyToMany(const APropertyName: string): IRelationshipBuilder<T>;
var
  LProp: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  LProp := FMap.GetOrAddProperty(APropertyName);
  LProp.IsNavigation := True;
  LProp.Relationship := rtManyToMany;
  Result := TRelationshipBuilder<T>.Create(FMap, LProp);
end;

function TEntityBuilder<T>.HasSoftDelete(const APropertyName: string): TEntityBuilder<T>;
begin
  Result := HasSoftDelete(APropertyName, True, False);
end;

function TEntityBuilder<T>.HasSoftDelete(const APropertyName: string; const ADeletedValue, ANotDeletedValue: Variant): TEntityBuilder<T>;
begin
  FMap.FIsSoftDelete := True;
  FMap.FSoftDeleteProp := APropertyName;
  FMap.FSoftDeleteDeletedValue := ADeletedValue;
  FMap.FSoftDeleteNotDeletedValue := ANotDeletedValue;
  Result := Self;
end;

function TEntityBuilder<T>.HasQueryFilter(AFilter: IExpression): TEntityBuilder<T>;
begin
  FMap.FQueryFilters.Add(AFilter);
  Result := Self;
end;


{ TEntityTypeBuilder<T> }

constructor TEntityTypeBuilder<T>.Create(AMap: TEntityMap);
begin
  FMap := AMap;
end;

function TEntityTypeBuilder<T>.ToTable(const AName: string): IEntityTypeBuilder<T>;
begin
  FMap.TableName := AName;
  Result := Self;
end;

function TEntityTypeBuilder<T>.ToTable(const AName, ASchema: string): IEntityTypeBuilder<T>;
begin
  FMap.TableName := AName;
  FMap.Schema := ASchema;
  Result := Self;
end;

function TEntityTypeBuilder<T>.HasKey(const APropertyName: string): IEntityTypeBuilder<T>;
begin
  FMap.Keys.Clear;
  FMap.RequireClassProperty(APropertyName);
  FMap.Keys.Add(APropertyName);
  
  // Mark property as PK
  FMap.GetOrAddProperty(APropertyName).IsPK := True;
  Result := Self;
end;

function TEntityTypeBuilder<T>.HasKey(const APropertyNames: array of string): IEntityTypeBuilder<T>;
var
  Prop: string;
begin
  FMap.Keys.Clear;
  for Prop in APropertyNames do
  begin
    FMap.RequireClassProperty(Prop);
    FMap.Keys.Add(Prop);
    FMap.GetOrAddProperty(Prop).IsPK := True;
  end;
  Result := Self;
end;

function TEntityTypeBuilder<T>.HasDiscriminator(const AColumn: string; const AValue: Variant): IEntityTypeBuilder<T>;
begin
  FMap.DiscriminatorColumn := AColumn;
  FMap.DiscriminatorValue := AValue;
  FMap.InheritanceStrategy := TInheritanceStrategy.TablePerHierarchy; // Default to TPH
  Result := Self;
end;

function TEntityTypeBuilder<T>.MapInheritance(AStrategy: TInheritanceStrategy): IEntityTypeBuilder<T>;
begin
  FMap.InheritanceStrategy := AStrategy;
  Result := Self;
end;

function TEntityTypeBuilder<T>.Prop(const APropertyName: string): IPropertyBuilder<T>;
begin
  FMap.RequireClassProperty(APropertyName);
  Result := TPropertyBuilder<T>.Create(FMap.GetOrAddProperty(APropertyName), FMap);
end;

function TEntityTypeBuilder<T>.Prop(const AProp: IPropInfo): IPropertyBuilder<T>;
begin
  Result := Prop(AProp.PropertyName);
end;

function TEntityTypeBuilder<T>.ShadowProperty(const APropName: string): IPropertyBuilder<T>;
begin
  Result := TPropertyBuilder<T>.Create(FMap.GetOrAddProperty(APropName), FMap)
    .IsShadow(True);
end;

function TEntityTypeBuilder<T>.Ignore(const APropertyName: string): IEntityTypeBuilder<T>;
begin
  FMap.RequireClassProperty(APropertyName);
  FMap.GetOrAddProperty(APropertyName).IsIgnored := True;
  Result := Self;
end;

function TEntityTypeBuilder<T>.HasMany(const APropertyName: string): IRelationshipBuilder<T>;
var
  PropMap: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  PropMap := FMap.GetOrAddProperty(APropertyName);
  PropMap.IsNavigation := True;
  PropMap.Relationship := rtOneToMany;
  Result := TRelationshipBuilder<T>.Create(FMap, PropMap);
end;

function TEntityTypeBuilder<T>.HasOne(const APropertyName: string): IRelationshipBuilder<T>;
var
  PropMap: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  PropMap := FMap.GetOrAddProperty(APropertyName);
  PropMap.IsNavigation := True;
  PropMap.Relationship := rtOneToOne;
  Result := TRelationshipBuilder<T>.Create(FMap, PropMap);
end;

function TEntityTypeBuilder<T>.BelongsTo(const APropertyName: string): IRelationshipBuilder<T>;
var
  PropMap: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  PropMap := FMap.GetOrAddProperty(APropertyName);
  PropMap.IsNavigation := True;
  PropMap.Relationship := rtManyToOne;
  Result := TRelationshipBuilder<T>.Create(FMap, PropMap);
end;

function TEntityTypeBuilder<T>.HasManyToMany(const APropertyName: string): IRelationshipBuilder<T>;
var
  PropMap: TPropertyMap;
begin
  FMap.RequireClassProperty(APropertyName);
  PropMap := FMap.GetOrAddProperty(APropertyName);
  PropMap.IsNavigation := True;
  PropMap.Relationship := rtManyToMany;
  Result := TRelationshipBuilder<T>.Create(FMap, PropMap);
end;

function TEntityTypeBuilder<T>.HasSoftDelete(const APropertyName: string): IEntityTypeBuilder<T>;
begin
  Result := HasSoftDelete(APropertyName, True, False);
end;

function TEntityTypeBuilder<T>.HasSoftDelete(const APropertyName: string; const ADeletedValue, ANotDeletedValue: Variant): IEntityTypeBuilder<T>;
begin
  FMap.FIsSoftDelete := True;
  FMap.FSoftDeleteProp := APropertyName;
  FMap.FSoftDeleteDeletedValue := ADeletedValue;
  FMap.FSoftDeleteNotDeletedValue := ANotDeletedValue;
  Result := Self;
end;

function TEntityTypeBuilder<T>.HasQueryFilter(AFilter: IExpression): IEntityTypeBuilder<T>;
begin
  FMap.FQueryFilters.Add(AFilter);
  Result := Self;
end;

function TEntityBuilder<T>.HasConverter(AConverterClass: TClass): TEntityBuilder<T>;
begin
  GetCurrentProp.ConverterClass := AConverterClass;
  GetCurrentProp.Converter := CreateConverterFromClass(AConverterClass);
  Result := Self;
end;

{ TPropertyBuilder<T> }

constructor TPropertyBuilder<T>.Create(APropMap: TPropertyMap; AEntityMap: TEntityMap);
begin
  FPropMap := APropMap;
  FEntityMap := AEntityMap;
end;

function TPropertyBuilder<T>.HasColumnName(const AName: string): IPropertyBuilder<T>;
begin
  FPropMap.ColumnName := AName;
  Result := Self;
end;

function TPropertyBuilder<T>.HasFieldName(const AName: string): IPropertyBuilder<T>;
begin
  FPropMap.FieldName := AName;
  Result := Self;
end;

function TPropertyBuilder<T>.UseField: IPropertyBuilder<T>;
begin
  FPropMap.FieldName := TReflection.NormalizeFieldName(FPropMap.PropertyName);
  Result := Self;
end;

function TPropertyBuilder<T>.IsRequired(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsRequired := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.IsAutoInc(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsAutoInc := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.HasMaxLength(ALength: Integer): IPropertyBuilder<T>;
begin
  FPropMap.MaxLength := ALength;
  Result := Self;
end;

function TPropertyBuilder<T>.HasMinLength(ALength: Integer): IPropertyBuilder<T>;
begin
  FPropMap.MinLength := ALength;
  Result := Self;
end;

function TPropertyBuilder<T>.HasPrecision(APrecision, AScale: Integer): IPropertyBuilder<T>;
begin
  FPropMap.Precision := APrecision;
  FPropMap.Scale := AScale;
  Result := Self;
end;

function TPropertyBuilder<T>.HasDbType(ADataType: TFieldType): IPropertyBuilder<T>;
begin
  FPropMap.DataType := ADataType;
  Result := Self;
end;

function TPropertyBuilder<T>.IsLazy(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsLazy := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.IsVersion(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsVersion := AValue;
  Result := Self;
end;



function TPropertyBuilder<T>.IsCreatedAt(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsCreatedAt := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.IsDeletedAt(AValue: Boolean): IPropertyBuilder<T>;
begin
  if FEntityMap <> nil then
    FEntityMap.MarkDeletedAt(FPropMap, AValue)
  else
    FPropMap.IsDeletedAt := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.IsUpdatedAt(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsUpdatedAt := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.IsShadow(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsShadow := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.HasDisplayLabel(const AValue: string): IPropertyBuilder<T>;
begin
  FPropMap.DisplayLabel := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.HasDisplayWidth(AValue: Integer): IPropertyBuilder<T>;
begin
  FPropMap.DisplayWidth := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.HasDisplayFormat(const AValue: string): IPropertyBuilder<T>;
begin
  FPropMap.DisplayFormat := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.HasEditMask(const AValue: string): IPropertyBuilder<T>;
begin
  FPropMap.EditMask := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.HasAlignment(AValue: TAlignment): IPropertyBuilder<T>;
begin
  FPropMap.Alignment := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.IsReadOnly(AValue: Boolean): IPropertyBuilder<T>;
begin
  FPropMap.IsReadOnly := AValue;
  Result := Self;
end;

function TPropertyBuilder<T>.UseSequence(const ASequenceName: string; AAllocationSize: Integer): IPropertyBuilder<T>;
begin
  FPropMap.IsSequenced := True;
  FPropMap.SequenceName := ASequenceName;
  FPropMap.SequenceAllocationSize := AAllocationSize;
  Result := Self;
end;

function TPropertyBuilder<T>.HasConverter(AConverterClass: TClass): IPropertyBuilder<T>;
begin
  FPropMap.ConverterClass := AConverterClass;
  FPropMap.Converter := CreateConverterFromClass(AConverterClass);
  Result := Self;
end;

{ TModelBuilder }

constructor TModelBuilder.Create;
begin
  FMaps := TCollections.CreateDictionary<PTypeInfo, TEntityMap>(True);
  FDiscoveryNames := TCollections.CreateDictionary<PTypeInfo, string>;
  FFactories := TCollections.CreateDictionary<PTypeInfo, IDynamicDbSetFactory>;
  // TDextMREW is a record and doesn't need explicit allocation
end;

destructor TModelBuilder.Destroy;
begin
  FMaps := nil;
  FDiscoveryNames := nil;
  FFactories := nil;
  inherited;
end;

procedure TModelBuilder.Clear;
begin
  FLock.BeginWrite;
  try
    if Assigned(FMaps) then
      FMaps.Clear;
    if Assigned(FDiscoveryNames) then
      FDiscoveryNames.Clear;
    if Assigned(FFactories) then
      FFactories.Clear;
  finally
    FLock.EndWrite;
  end;
end;

procedure TModelBuilder.RegisterFactory(AType: PTypeInfo; const AFactory: IDynamicDbSetFactory);
begin
  FLock.BeginWrite;
  try
    if not FFactories.ContainsKey(AType) then
      FFactories.Add(AType, AFactory);
  finally
    FLock.EndWrite;
  end;
end;

function TModelBuilder.GetFactory(AType: PTypeInfo): IDynamicDbSetFactory;
begin
  FLock.BeginRead;
  try
    if not FFactories.TryGetValue(AType, Result) then
    begin
      // Fallback to global instance if this is a local/context builder (common in tests)
      if (Self <> FInstance) and (FInstance <> nil) then
      begin
        // Note: FInstance has its own lock which will be called recursively
        Result := FInstance.GetFactory(AType);
      end
      else
        Result := nil;
    end;
  finally
    FLock.EndRead;
  end;
end;

class constructor TModelBuilder.Create;
begin
  FInstance := TModelBuilder.Create;
end;

class destructor TModelBuilder.Destroy;
begin
  FreeAndNil(FInstance);
end;

procedure TModelBuilder.RegisterDiscoveryName(AType: PTypeInfo; const AName: string);
begin
  FLock.BeginWrite;
  try
    FDiscoveryNames.AddOrSetValue(AType, AName);
  finally
    FLock.EndWrite;
  end;
end;

function TModelBuilder.GetDiscoveryName(AType: PTypeInfo): string;
begin
  FLock.BeginRead;
  try
    if not FDiscoveryNames.TryGetValue(AType, Result) then
      Result := '';
  finally
    FLock.EndRead;
  end;
end;

procedure TModelBuilder.ApplyConfiguration<T>(AConfig: IEntityTypeConfiguration<T>);
var
  Map: TEntityMap;
  Builder: IEntityTypeBuilder<T>;
begin
  FLock.BeginWrite;
  try
    if not FMaps.TryGetValue(TypeInfo(T), Map) then
    begin
      Map := TEntityMap.Create(TypeInfo(T));
      FMaps.Add(TypeInfo(T), Map);
    end;
  finally
    FLock.EndWrite;
  end;
  
  Builder := TEntityTypeBuilder<T>.Create(Map);
  AConfig.Configure(Builder);
end;

function TModelBuilder.Entity<T>: TEntityBuilder<T>;
var
  Map: TEntityMap;
begin
  FLock.BeginWrite;
  try
    if not FMaps.TryGetValue(TypeInfo(T), Map) then
    begin
      Map := TEntityMap.Create(TypeInfo(T));
      FMaps.Add(TypeInfo(T), Map);
    end;
  finally
    FLock.EndWrite;
  end;
  
  Result := TEntityBuilder<T>.Create(Map);
end;

procedure TModelBuilder.ResolveInheritance(AMap: TEntityMap);
var
  Cls: TClass;
  Info: PTypeInfo;
  Candidate, Root: TEntityMap;
begin
  if (AMap = nil) or AMap.InheritanceResolved then Exit;
  if (AMap.InheritanceStrategy <> TInheritanceStrategy.TablePerHierarchy) or
     VarIsNull(AMap.DiscriminatorValue) or VarIsEmpty(AMap.DiscriminatorValue) then Exit;
  Root := nil;
  Cls := GetTypeData(AMap.EntityType)^.ClassType.ClassParent;
  while Cls <> nil do
  begin
    Info := Cls.ClassInfo;
    if Info <> nil then
    begin
      FLock.BeginRead;
      try
        if FMaps.TryGetValue(Info, Candidate) and
           (Candidate.InheritanceStrategy = TInheritanceStrategy.TablePerHierarchy) then
          Root := Candidate;
      finally
        FLock.EndRead;
      end;
    end;
    Cls := Cls.ClassParent;
  end;
  // Without a registered root yet, try again on the next lookup
  if Root <> nil then
  begin
    AMap.InheritFrom(Root);
    AMap.InheritanceResolved := True;
  end;
end;

function TModelBuilder.LookupMap(AType: PTypeInfo): TEntityMap;
begin
  FLock.BeginRead;
  try
    if FMaps.TryGetValue(AType, Result) then
      Exit;
  finally
    FLock.EndRead;
  end;

  // Double-check lock pattern
  FLock.BeginWrite;
  try
    if not FMaps.TryGetValue(AType, Result) then
    begin
      // Auto-Discovery: Create and cache the map if it doesn't exist
      Result := TEntityMap.Create(AType);
      FMaps.Add(AType, Result);
    end;
  finally
    FLock.EndWrite;
  end;
end;

function TModelBuilder.GetMap(AType: PTypeInfo): TEntityMap;
begin
  Result := LookupMap(AType);
  ResolveInheritance(Result);
end;

function TModelBuilder.HasMap(AType: PTypeInfo): Boolean;
begin
  FLock.BeginRead;
  try
    Result := FMaps.ContainsKey(AType);
  finally
    FLock.EndRead;
  end;
end;

function TModelBuilder.GetMaps: TArray<TEntityMap>;
var
  Map: TEntityMap;
begin
  FLock.BeginRead;
  try
    Result := FMaps.Values;
  finally
    FLock.EndRead;
  end;
  for Map in Result do
    ResolveInheritance(Map);
end;

function TModelBuilder.FindMapByDiscriminator(ABaseType: PTypeInfo; const AValue: Variant): TEntityMap;
var
  Map: TEntityMap;
  Typ, BaseTyp: TRttiType;
  LList: TArray<TEntityMap>;
begin
  Result := nil;
  LList := GetMaps; // Thread-safe snapshot
  
  BaseTyp := TReflection.Context.GetType(ABaseType);
  if BaseTyp = nil then Exit;
    
  for Map in LList do
  begin
    if (Map.DiscriminatorValue <> Null) and (Map.DiscriminatorValue = AValue) then
    begin
       Typ := TReflection.Context.GetType(Map.EntityType);
       if (Typ <> nil) and (Typ is TRttiInstanceType) and (BaseTyp is TRttiInstanceType) then
       begin
         if TRttiInstanceType(Typ).MetaclassType.InheritsFrom(TRttiInstanceType(BaseTyp).MetaclassType) then
           Exit(Map);
       end;
    end;
  end;
end;

end.


