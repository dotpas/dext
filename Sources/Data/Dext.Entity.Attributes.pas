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
unit Dext.Entity.Attributes;

interface

uses
  System.Rtti,
  System.Variants,
  System.Classes,
  Data.DB;

type
  TInheritanceStrategy = (None, TablePerHierarchy, TablePerType);

type
  /// <summary>
  ///   Marks a class to be proxied by the ORM for lazy loading or other interceptions.
  /// </summary>
  ProxyAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a class or property as renamed from a previous version.
  ///   Used by the migration engine to generate RENAME operations instead of DROP/ADD.
  /// </summary>
  RenamedFromAttribute = class(TCustomAttribute)
  private
    FOldName: string;
  public
    constructor Create(const AOldName: string);
    property OldName: string read FOldName;
  end;

  /// <summary>
  ///   Marks a property for lazy loading.
  /// </summary>
  LazyAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Specifies the table name and schema in the database for the entity.
  /// </summary>
  TableAttribute = class(TCustomAttribute)
  private
    FName: string;
    FSchema: string;
  public
    constructor Create; overload;
    constructor Create(const AName: string); overload;
    constructor Create(const AName, ASchema: string); overload;
    property Name: string read FName;
    property Schema: string read FSchema;
  end;

  /// <summary>
  ///   Specifies the column name in the database for the property.
  /// </summary>
  ColumnAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Marks a property as a Primary Key.
  /// </summary>
  PrimaryKeyAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property as a Currency field.
  /// </summary>
  CurrencyAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Alias for PrimaryKeyAttribute
  /// </summary>
  PKAttribute = PrimaryKeyAttribute;
  PK = PKAttribute;

  AutoIncAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Specifies that a property value is generated from a database sequence.
  /// </summary>
  SequenceAttribute = class(TCustomAttribute)
  private
    FSequenceName: string;
    FAllocationSize: Integer;
  public
    /// <summary>
    ///   Initializes a new instance of the SequenceAttribute with the sequence name and allocation size.
    /// </summary>
    /// <param name="ASequenceName">The name of the database sequence.</param>
    /// <param name="AAllocationSize">The block allocation size for pre-allocated IDs (default is 50).</param>
    constructor Create(const ASequenceName: string; AAllocationSize: Integer = 50);
    /// <summary>
    ///   The name of the sequence in the database.
    /// </summary>
    property SequenceName: string read FSequenceName;
    /// <summary>
    ///   The allocation size (block size) used by the HiLo pooled range optimizer.
    /// </summary>
    property AllocationSize: Integer read FAllocationSize;
  end;

  /// <summary>
  ///   Marks a property as NOT NULL.
  /// </summary>
  RequiredAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Specifies the maximum length of array/string data allowed in a property.
  /// </summary>
  MaxLengthAttribute = class(TCustomAttribute)
  private
    FLength: Integer;
  public
    constructor Create(ALength: Integer);
    property Length: Integer read FLength;
  end;

  /// <summary>
  ///   Specifies the minimum length of array/string data allowed in a property.
  /// </summary>
  MinLengthAttribute = class(TCustomAttribute)
  private
    FLength: Integer;
  public
    constructor Create(ALength: Integer);
    property Length: Integer read FLength;
  end;

  /// <summary>
  ///   Specifies the precision and scale for numeric columns.
  /// </summary>
  PrecisionAttribute = class(TCustomAttribute)
  private
    FPrecision: Integer;
    FScale: Integer;
  public
    constructor Create(APrecision, AScale: Integer);
    property Precision: Integer read FPrecision;
    property Scale: Integer read FScale;
  end;

  /// <summary>
  ///   Marks a property as not mapped to the database.
  /// </summary>
  NotMappedAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Specifies the name of the stored procedure associated with a class.
  /// </summary>
  StoredProcedureAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Specifies parameter metadata for stored procedure calls.
  /// </summary>
  DbParamAttribute = class(TCustomAttribute)
  private
    FParamType: TParamType;
    FName: string;
  public
    constructor Create(AParamType: TParamType = ptInput; const AName: string = '');
    property ParamType: TParamType read FParamType;
    property Name: string read FName;
  end;

  /// <summary>
  ///   Marks a property to be used as an Offline Locking Token (user/session id).
  /// </summary>
  LockTokenAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property to be used as an Offline Locking Expiration date/time.
  /// </summary>
  LockExpirationAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property as a nested object for multi-mapping hydration.
  ///   Without a prefix the columns are routed by the name of the property
  ///   (Category_Name, Category.Name); with one, by that prefix
  ///   ([Nested('cat_')]: cat_Name). Both forms work for the same property.
  /// </summary>
  NestedAttribute = class(TCustomAttribute)
  private
    FPrefix: string;
  public
    constructor Create; overload;
    constructor Create(const APrefix: string); overload;
    property Prefix: string read FPrefix;
  end;

  /// <summary>
  ///   Specifies the backing field to be used for a property during hydration.
  ///   This avoids triggering property setters during object loading.
  /// </summary>
  FieldAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create; overload;
    constructor Create(const AName: string); overload;
    property Name: string read FName;
  end;

  /// <summary>
  ///   Marks a property as JSON/JSONB column (PostgreSQL).
  /// </summary>
  JsonColumnAttribute = class(TCustomAttribute)
  private
    FUseJsonB: Boolean;
  public
    constructor Create(AUseJsonB: Boolean = True);
    property UseJsonB: Boolean read FUseJsonB;
  end;

  /// <summary>
  ///   Marks a property as a version column for Optimistic Concurrency Control.
  ///   The property must be of an integer type.
  /// </summary>
  VersionAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property as an automatic Creation Timestamp.
  ///   The ORM will set this field to the current date/time on Insert.
  /// </summary>
  CreatedAtAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a property as an automatic Update Timestamp.
  ///   The ORM will set this field to the current date/time on Insert and Update.
  /// </summary>
  UpdatedAtAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Enables soft delete for an entity.
  ///   Instead of physically deleting records, marks them as deleted.
  ///   Usage: [SoftDelete('IsDeleted')] or [SoftDelete('DeletedAt')]
  /// </summary>
  SoftDeleteAttribute = class(TCustomAttribute)
  private
    FColumnName: string;
    FDeletedValue: Variant;
    FNotDeletedValue: Variant;
  public
    /// <summary>
    ///   Creates a soft delete attribute with a boolean column (default: 'IsDeleted')
    /// </summary>
    constructor Create(const AColumnName: string = 'IsDeleted'); overload;
    
    /// <summary>
    ///   Creates a soft delete attribute with custom deleted/not-deleted values
    ///   Useful for timestamp-based soft delete (DeletedAt column)
    /// </summary>
    constructor Create(const AColumnName: string; const ADeletedValue, ANotDeletedValue: Variant); overload;
    
    property ColumnName: string read FColumnName;
    property DeletedValue: Variant read FDeletedValue;
    property NotDeletedValue: Variant read FNotDeletedValue;
  end;

  /// <summary>
  ///   Marks a property as the Soft Delete Timestamp.
  ///   The presence of this attribute enables Soft Delete automatically.
  ///   The ORM will set this field to the current date/time on Delete.
  /// </summary>
  DeletedAtAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Defines the cascade action for foreign key constraints.
  /// </summary>
  TCascadeAction = (
    caNoAction,    // NO ACTION - Default behavior (may fail if references exist)
    caCascade,     // CASCADE - Delete/Update related rows automatically
    caSetNull,     // SET NULL - Set foreign key to NULL when parent is deleted/updated
    caRestrict     // RESTRICT - Prevent delete/update if references exist
  );

  /// <summary>
  ///   Marks a property as a Foreign Key relationship.
  ///   Example: [ForeignKey('UserId', caCascade, caNoAction)]
  /// </summary>
  ForeignKeyAttribute = class(TCustomAttribute)
  private
    FColumnName: string;
    FOnDelete: TCascadeAction;
    FOnUpdate: TCascadeAction;
  public
    constructor Create(const AColumnName: string); overload;
    constructor Create(const AColumnName: string; AOnDelete: TCascadeAction); overload;
    constructor Create(const AColumnName: string; AOnDelete, AOnUpdate: TCascadeAction); overload;
    property ColumnName: string read FColumnName;
    property OnDelete: TCascadeAction read FOnDelete;
    property OnUpdate: TCascadeAction read FOnUpdate;
  end;

  /// <summary>
  ///   Alias for ForeignKeyAttribute
  /// </summary>
  FKAttribute = ForeignKeyAttribute;
  FK = FKAttribute;

  /// <summary>
  ///   Marks a collection property as a One-to-Many relationship.
  /// </summary>
  HasManyAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a reference property as a Many-to-One relationship.
  /// </summary>
  BelongsToAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a reference property as a One-to-One relationship.
  /// </summary>
  HasOneAttribute = class(TCustomAttribute)
  end;

  /// <summary>
  ///   Marks a collection property as a Many-to-Many relationship.
  ///   Requires a join table to link the two entities.
  /// </summary>
  ManyToManyAttribute = class(TCustomAttribute)
  private
    FJoinTableName: string;
    FLeftKeyColumn: string;
    FRightKeyColumn: string;
  public
    /// <summary>
    ///   Creates Many-to-Many with default join table naming convention.
    /// </summary>
    constructor Create; overload;
    
    /// <summary>
    ///   Creates Many-to-Many with explicit join table name.
    /// </summary>
    constructor Create(const AJoinTableName: string); overload;
    
    /// <summary>
    ///   Creates Many-to-Many with explicit join table and key columns.
    /// </summary>
    constructor Create(const AJoinTableName, ALeftKeyColumn, ARightKeyColumn: string); overload;
    
    property JoinTableName: string read FJoinTableName;
    property LeftKeyColumn: string read FLeftKeyColumn;
    property RightKeyColumn: string read FRightKeyColumn;
  end;

  /// <summary>
  ///   Specifies the inverse navigation property on the other end of the relationship.
  /// </summary>
  InversePropertyAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Specifies the delete behavior for the relationship.
  /// </summary>
  DeleteBehaviorAttribute = class(TCustomAttribute)
  private
    FBehavior: TCascadeAction;
  public
    constructor Create(ABehavior: TCascadeAction);
    property Behavior: TCascadeAction read FBehavior;
  end;

  /// <summary>
  ///   Defines the inheritance strategy for the entity hierarchy.
  /// </summary>
  InheritanceAttribute = class(TCustomAttribute)
  private
    FStrategy: TInheritanceStrategy;
  public
    constructor Create(AStrategy: TInheritanceStrategy);
    property Strategy: TInheritanceStrategy read FStrategy;
  end;

  /// <summary>
  ///   Specifies the column used as a discriminator in TPH inheritance.
  /// </summary>
  DiscriminatorColumnAttribute = class(TCustomAttribute)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    property Name: string read FName;
  end;

  /// <summary>
  ///   Specifies the discriminator value for this specific class in the hierarchy.
  /// </summary>
  DiscriminatorValueAttribute = class(TCustomAttribute)
  private
    FValue: Variant;
  public
    constructor Create(const AValue: Variant); overload;
    // Typed overloads: a Variant argument is not reliable in attribute RTTI
    constructor Create(const AValue: string); overload;
    constructor Create(AValue: Integer); overload;
    property Value: Variant read FValue;
  end;

  /// <summary>
  ///   Specifies the database field type for the property.
  ///   Overrides the default type mapping.
  /// </summary>
  DbTypeAttribute = class(TCustomAttribute)
  private
    FDataType: TFieldType;
  public
    constructor Create(ADataType: TFieldType);
    property DataType: TFieldType read FDataType;
  end;

  /// <summary>
  ///   Specifies the display name (caption) for a property.
  /// </summary>
  CaptionAttribute = class(TCustomAttribute)
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    property Value: string read FValue;
  end;

  /// <summary>
  ///   Alias for CaptionAttribute
  /// </summary>
  DisplayLabelAttribute = CaptionAttribute;
  Caption = CaptionAttribute;
  DisplayLabel = CaptionAttribute;

  /// <summary>
  ///   Specifies the display format (e.g., #,##0.00) for a numeric or date property.
  /// </summary>
  DisplayFormatAttribute = class(TCustomAttribute)
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    property Value: string read FValue;
  end;
  DisplayFormat = DisplayFormatAttribute;

  /// <summary>
  ///   Specifies the horizontal alignment for the field's data in UI.
  /// </summary>
  AlignmentAttribute = class(TCustomAttribute)
  private
    FAlignment: TAlignment;
  public
    constructor Create(AAlignment: TAlignment);
    property Alignment: TAlignment read FAlignment;
  end;
  Alignment = AlignmentAttribute;

  /// <summary>
  ///   Specifies an edit mask for the property.
  /// </summary>
  EditMaskAttribute = class(TCustomAttribute)
  private
    FValue: string;
  public
    constructor Create(const AValue: string);
    property Value: string read FValue;
  end;
  EditMask = EditMaskAttribute;

  /// <summary>
  ///   Specifies the display width for the field in UI controls.
  /// </summary>
  DisplayWidthAttribute = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;
  DisplayWidth = DisplayWidthAttribute;

  /// <summary>
  ///   Specifies if the field should be visible in UI controls.
  /// </summary>
  VisibleAttribute = class(TCustomAttribute)
  private
    FVisible: Boolean;
  public
    constructor Create(AVisible: Boolean = True);
    property Visible: Boolean read FVisible;
  end;
  Visible = VisibleAttribute;

  /// <summary>
  ///   Specifies if the field should be read-only in UI controls.
  /// </summary>
  ReadOnlyAttribute = class(TCustomAttribute)
  private
    FReadOnly: Boolean;
  public
    constructor Create(AReadOnly: Boolean = True);
    property ReadOnly: Boolean read FReadOnly;
  end;
  ReadOnly = ReadOnlyAttribute;

  /// <summary>
  ///   Specifies a default value for the property when the database returns NULL.
  /// </summary>
  DefaultValueAttribute = class(TCustomAttribute)
  private
    FValue: Variant;
  public
    constructor Create(const AValue: string); overload;
    constructor Create(AValue: Integer); overload;
    constructor Create(AValue: Double); overload;
    constructor Create(AValue: Boolean); overload;
    property Value: Variant read FValue;
  end;
  DefaultValue = DefaultValueAttribute;

  /// <summary>
  ///   Specifies a custom type converter for the property.
  ///   The converter class must implement ITypeConverter.
  /// </summary>
  TypeConverterAttribute = class(TCustomAttribute)
  private
    FConverterClass: TClass;
  public
    constructor Create(AConverterClass: TClass);
    property ConverterClass: TClass read FConverterClass;
  end;

implementation

{ RenamedFromAttribute }

constructor RenamedFromAttribute.Create(const AOldName: string);
begin
  FOldName := AOldName;
end;

{ TableAttribute }

constructor TableAttribute.Create;
begin
  FName := '';
end;

constructor TableAttribute.Create(const AName: string);
begin
  FName := AName;
  FSchema := '';
end;

constructor TableAttribute.Create(const AName, ASchema: string);
begin
  FName := AName;
  FSchema := ASchema;
end;

{ ColumnAttribute }

constructor ColumnAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ NestedAttribute }

constructor NestedAttribute.Create;
begin
  inherited Create;
  FPrefix := '';
end;

constructor NestedAttribute.Create(const APrefix: string);
begin
  inherited Create;
  FPrefix := APrefix;
end;

{ FieldAttribute }

constructor FieldAttribute.Create;
begin
  FName := '';
end;

constructor FieldAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ JsonColumnAttribute }

constructor JsonColumnAttribute.Create(AUseJsonB: Boolean);
begin
  inherited Create;
  FUseJsonB := AUseJsonB;
end;

{ ForeignKeyAttribute }

constructor ForeignKeyAttribute.Create(const AColumnName: string);
begin
  FColumnName := AColumnName;
  FOnDelete := caNoAction;
  FOnUpdate := caNoAction;
end;

constructor ForeignKeyAttribute.Create(const AColumnName: string; AOnDelete: TCascadeAction);
begin
  FColumnName := AColumnName;
  FOnDelete := AOnDelete;
  FOnUpdate := caNoAction;
end;

constructor ForeignKeyAttribute.Create(const AColumnName: string; AOnDelete, AOnUpdate: TCascadeAction);
begin
  FColumnName := AColumnName;
  FOnDelete := AOnDelete;
  FOnUpdate := AOnUpdate;
end;

{ InversePropertyAttribute }

constructor InversePropertyAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ DeleteBehaviorAttribute }

constructor DeleteBehaviorAttribute.Create(ABehavior: TCascadeAction);
begin
  FBehavior := ABehavior;
end;

{ ManyToManyAttribute }

constructor ManyToManyAttribute.Create;
begin
  FJoinTableName := '';
  FLeftKeyColumn := '';
  FRightKeyColumn := '';
end;

constructor ManyToManyAttribute.Create(const AJoinTableName: string);
begin
  FJoinTableName := AJoinTableName;
  FLeftKeyColumn := '';
  FRightKeyColumn := '';
end;

constructor ManyToManyAttribute.Create(const AJoinTableName, ALeftKeyColumn, ARightKeyColumn: string);
begin
  FJoinTableName := AJoinTableName;
  FLeftKeyColumn := ALeftKeyColumn;
  FRightKeyColumn := ARightKeyColumn;
end;

{ InheritanceAttribute }

constructor InheritanceAttribute.Create(AStrategy: TInheritanceStrategy);
begin
  FStrategy := AStrategy;
end;

{ DiscriminatorColumnAttribute }

constructor DiscriminatorColumnAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ DiscriminatorValueAttribute }

constructor DiscriminatorValueAttribute.Create(const AValue: Variant);
begin
  FValue := AValue;
end;

constructor DiscriminatorValueAttribute.Create(const AValue: string);
begin
  FValue := AValue;
end;

constructor DiscriminatorValueAttribute.Create(AValue: Integer);
begin
  FValue := AValue;
end;

{ SoftDeleteAttribute }

constructor SoftDeleteAttribute.Create(const AColumnName: string);
begin
  FColumnName := AColumnName;
  // Default: Boolean soft delete (IsDeleted = 1 means deleted, 0 means not deleted)
  FDeletedValue := 1;
  FNotDeletedValue := 0;
end;

constructor SoftDeleteAttribute.Create(const AColumnName: string; const ADeletedValue, ANotDeletedValue: Variant);
begin
  FColumnName := AColumnName;
  FDeletedValue := ADeletedValue;
  FNotDeletedValue := ANotDeletedValue;
end;

{ DbTypeAttribute }

constructor DbTypeAttribute.Create(ADataType: TFieldType);
begin
  FDataType := ADataType;
end;

{ SequenceAttribute }

constructor SequenceAttribute.Create(const ASequenceName: string; AAllocationSize: Integer);
begin
  FSequenceName := ASequenceName;
  FAllocationSize := AAllocationSize;
end;

{ TypeConverterAttribute }

constructor TypeConverterAttribute.Create(AConverterClass: TClass);
begin
  FConverterClass := AConverterClass;
end;

{ MaxLengthAttribute }

constructor MaxLengthAttribute.Create(ALength: Integer);
begin
  FLength := ALength;
end;

{ MinLengthAttribute }

constructor MinLengthAttribute.Create(ALength: Integer);
begin
  FLength := ALength;
end;

{ PrecisionAttribute }

constructor PrecisionAttribute.Create(APrecision, AScale: Integer);
begin
  FPrecision := APrecision;
  FScale := AScale;
end;

{ StoredProcedureAttribute }

constructor StoredProcedureAttribute.Create(const AName: string);
begin
  FName := AName;
end;

{ DbParamAttribute }

constructor DbParamAttribute.Create(AParamType: TParamType; const AName: string);
begin
  FParamType := AParamType;
  FName := AName;
end;

{ CaptionAttribute }

constructor CaptionAttribute.Create(const AValue: string);
begin
  FValue := AValue;
end;

{ DisplayFormatAttribute }

constructor DisplayFormatAttribute.Create(const AValue: string);
begin
  FValue := AValue;
end;

{ AlignmentAttribute }

constructor AlignmentAttribute.Create(AAlignment: TAlignment);
begin
  FAlignment := AAlignment;
end;

{ EditMaskAttribute }

constructor EditMaskAttribute.Create(const AValue: string);
begin
  FValue := AValue;
end;

{ DisplayWidthAttribute }

constructor DisplayWidthAttribute.Create(AValue: Integer);
begin
  FValue := AValue;
end;

{ VisibleAttribute }

constructor VisibleAttribute.Create(AVisible: Boolean);
begin
  FVisible := AVisible;
end;

{ ReadOnlyAttribute }

constructor ReadOnlyAttribute.Create(AReadOnly: Boolean);
begin
  FReadOnly := AReadOnly;
end;

{ DefaultValueAttribute }

constructor DefaultValueAttribute.Create(const AValue: string);
begin
  FValue := AValue;
end;

constructor DefaultValueAttribute.Create(AValue: Integer);
begin
  FValue := AValue;
end;

constructor DefaultValueAttribute.Create(AValue: Double);
begin
  FValue := AValue;
end;

constructor DefaultValueAttribute.Create(AValue: Boolean);
begin
  FValue := AValue;
end;

end.

