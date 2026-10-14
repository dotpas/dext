
unit Dext.Entity.DataSet;

interface

{$POINTERMATH ON}

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.Rtti,
  System.TypInfo,
  System.Math,
  System.DateUtils,
  Data.DB,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Collections.Vector,
  Dext.Core.Activator,
  Dext.Core.DateUtils,
  Dext.Core.Reflection,
  Dext.Core.Span,
  Dext.Entity.Context,
  Dext.Entity.Dialects,
  Dext.Entity.DataProvider,
  Dext.Entity.Mapping,
  Dext.Json.Utf8,
  Dext.Specifications.Interfaces;

type
  PBytes = ^TBytes;
  PObject = ^TObject;

  TEntityRowState = (ersUnchanged, ersInserted, ersModified, ersDeleted);

  TEntityChange = record
    State: TEntityRowState;
    Entity: TObject;
    OriginalIndex: Integer;
    Key: TArray<Dext.Collections.Dict.TPair<string, Variant>>;
    DirtyFields: TArray<string>;
    OriginalValues: TArray<Dext.Collections.Dict.TPair<string, Variant>>;
  end;

  /// <summary>
  ///   Record header for TEntityDataSet's internal buffer.
  ///   Stores row state metadata, bookmarks, and modification masks.
  /// </summary>
  PEntityRecordHeader = ^TEntityRecordHeader;
  TEntityRecordHeader = packed record
    /// <summary>Unique index of the record in the virtual list.</summary>
    BookmarkIndex: Integer;
    /// <summary>Marker state flag (valid, invalid, boe, eof).</summary>
    BookmarkFlag: TBookmarkFlag;
    /// <summary>Current state of the row in the dataset (dsBrowse, dsEdit, dsInsert).</summary>
    RowState: TDataSetState;
    /// <summary>Bitmask indicating which fields were altered in the current buffer.</summary>
    DirtyMask: UInt64;
  end;

  /// <summary>
  ///   Event triggered when a field is being prepared or configured in the dataset.
  /// </summary>
  TPrepareFieldEvent = procedure(Sender: TObject; AField: TField) of object;
  TStringFieldKind = (sfAuto, sfAnsi, sfWide);

  TEntityMasterDataLink = class;

  /// <summary>
  ///   Exception raised during Entity DataSet operations.
  /// </summary>
  EEntityDataSetException = class(Exception);

  /// <summary>
  ///   Specialized high-performance dataset that maps lists of objects and records directly to VCL/FMX.
  ///   Supports Sorting, Filtering, Master-Detail, Streaming Iterators, and Design-Time Preview without compilation.
  /// </summary>
  {$IF CompilerVersion >= 36.0}
  [ComponentPlatformsAttribute(pidWin32 or pidWin64 or pidWin64x)]
  {$ELSE}
  [ComponentPlatformsAttribute(pidWin32 or pidWin64)]
  {$ENDIF}
  TEntityDataSet = class(TDataSet)
  private
    FCalcAreaSize: Integer;
    FCalcOffsets: TDictionary<string, Integer>;
    FCurrentRec: Integer;
    FDataProvider: TEntityDataProvider;
    FDbContext: TDbContext;
    FDetailDataSets: TDictionary<string, TDataSet>;
    FEntityClass: TClass;
    FEntityClassName: string;
    FEntityMap: TEntityMap;
    FHeaderSize: Integer;
    FIncludeShadowProperties: Boolean;
    FIndexFieldNames: string;
    FInsertObj: TObject;
    FInsertObjRef: TObject;
    FInternalCalcStorage: TArray<TBytes>;
    FIsAppending: Boolean;
    FIsApplyingFilter: Boolean;
    FIsCursorOpen: Boolean;
    FIsDesignTimePreview: Boolean;
    FItems: IObjectList;
    FMasterDataSet: TDataSet;
    FMasterFields: string;
    FMasterLink: TEntityMasterDataLink;
    FOwnsEntityMap: Boolean;
    FOwnsItems: Boolean;
    FPositionBeforeAction: Integer;
    FPreviewData: TArray<TDictionary<string, Variant>>;
    FPropertyCache: TDictionary<string, TRttiProperty>;
    FReadOnly: Boolean;
    FRecordSize: Integer;
    FTableName: string;
    FVirtualIndex: TVector<Integer>;
    FOnPrepareField: TPrepareFieldEvent;
    FStringFieldKind: TStringFieldKind;
    FFilterExpression: IExpression;
    FTrackedChanges: IList<TEntityChange>;
    FCurrentDirtyFields: IList<string>;
    // Tracks objects the dataset itself created via Append/Insert
    // so they can be freed on Destroy even when FOwnsItems=False.
    FDataSetCreatedItems: IList<TObject>;
    // True only when FItems is an internal non-owning wrapper (Load<T> path).
    // Indicates that objects added via Append have no external owner.
    FItemsIsNonOwningWrapper: Boolean;
    // Temporarily holds deleted objects to allow local rollback (RejectChanges).
    FDeletedItemsCache: IList<TObject>;

    procedure SetFilterExpression(const Value: IExpression);
    procedure RecordOriginalValue(AEntity: TObject; Field: TField);
    procedure RemoveFromItems(AEntity: TObject; AFreeInstance: Boolean);

    function CompareObjectsInternal(A, B: TObject; const APropNames: TArray<string>; RttiType: TRttiType): Integer;
    function CreateNewEntity: TObject;
    function GetMasterSource: TDataSource;
    function GetProperty(const APropName: string): TRttiProperty;
    function IsActiveStored: Boolean;
    function ResolveTextFieldType: TFieldType;
    function ReadFieldValue(Field: TField; ABuffer: TRecBuf; out Value: Variant): Boolean; overload;
    function ReadFieldValue(Field: TField; out Value: Variant): Boolean; overload;
    function StringToFieldType(const ATypeName: string): TFieldType;

    procedure ApplyAttributesToField(AField: TField; AContainer: TRttiObject);
    procedure ApplyFilterAndSort(AFiltered: Boolean); overload;
    procedure ApplyFilterAndSort(AFiltered: Boolean; ATrackObj: TObject); overload;
    procedure ApplyFilterAndSort; overload;
    procedure ApplyMapMetadataToFields;
    procedure ClearResolvedEntityMetadata;
    procedure EnsureEntityMapResolved;
    procedure ResolveEntityClassFromProvider;
    procedure SetDataProvider(const Value: TEntityDataProvider);
    procedure SetEntityClassName(const Value: string);
    procedure SetIndexFieldNames(const Value: string);
    procedure SetItems(const Value: IObjectList);
    procedure SetMasterFields(const Value: string);
    procedure SetMasterInheritance(AEntity: TObject);
    procedure SetMasterSource(Value: TDataSource);
    procedure SyncMasterDetail;
  protected
    function IsCursorOpen: Boolean; override;

    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure InternalHandleException; override;

    // Filtering Overrides
    procedure SetFiltered(Value: Boolean); override;
    procedure SetFilterText(const Value: string); override;
    procedure SetFilterOptions(Value: TFilterOptions); override;

    // Mandatory TDataSet overrides
    function CreateNestedDataSet(DataSetField: TDataSetField): TDataSet; override;
    procedure InternalClose; override;
    procedure InternalInitFieldDefs; override;
    procedure InternalOpen; override;
    procedure Loaded; override;
    procedure SetActive(Value: Boolean); override;
    procedure SyncDetailData(const AFieldName: string; ADetailDataSet: TDataSet);

    // Buffer Alocations
    function AllocRecordBuffer: TRecordBuffer; override;
    procedure CalculateFields(Buffer: TRecBuf); override;
    procedure FreeRecordBuffer(var Buffer: TRecordBuffer); override;
    procedure InternalInitRecord(Buffer: TRecBuf); override;

    // Bookmark and Navigation
    function GetBookmarkFlag(Buffer: TRecBuf): TBookmarkFlag; override;
    procedure GetBookmarkData(Buffer: TRecBuf; Data: TBookmark); override;
    procedure InternalGotoBookmark(Bookmark: TBookmark); override;
    procedure InternalSetToRecord(Buffer: TRecBuf); override;
    procedure SetBookmarkData(Buffer: TRecBuf; Data: TBookmark); override;
    procedure SetBookmarkFlag(Buffer: TRecBuf; Value: TBookmarkFlag); override;

    function GetRecordSize: Word; override;
    function GetRecordCount: Integer; override;
    function GetRecNo: Integer; override;
    function GetRecord(Buffer: TRecBuf; GetMode: TGetMode; DoCheck: Boolean): TGetResult; override;
    procedure SetRecNo(Value: Integer); override;

    procedure DoAfterScroll; override;
    procedure DoBeforeDelete; override;
    procedure DoBeforeInsert; override;
    procedure DoBeforeScroll; override;
    procedure InternalAddRecord(Buffer: TRecBuf; Append: Boolean); override;
    procedure InternalCancel; override;
    procedure InternalDelete; override;
    procedure InternalEdit; override;
    procedure InternalFirst; override;
    procedure InternalInsert; override;
    procedure InternalLast; override;
    procedure InternalPost; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    function GetChanges: IList<TEntityChange>;
    procedure AcceptChanges;
    procedure RejectChanges;
    procedure ClearChanges;
    function GetEntityKeys(AEntity: TObject):
      TArray<Dext.Collections.Dict.TPair<string, Variant>>;
    function ReadPropertyValue(AEntity: TObject;
      PropMap: TPropertyMap; out AValue: Variant): Boolean;
    property Changes: IList<TEntityChange> read GetChanges;

    function AsJsonArray: string;
    function AsJsonObject: string;
    function BookmarkValid(Bookmark: TBookmark): Boolean; override;
    function CreateBlobStream(Field: TField; Mode: TBlobStreamMode): TStream; override;
    function GetCurrentObject: TObject;
    function GetFieldData(Field: TField; Buffer: Pointer): Boolean; overload; override;
    function GetFieldData(Field: TField; var Buffer: TValueBuffer): Boolean; overload; override;
    function Locate(const KeyFields: string; const KeyValues: Variant; Options: TLocateOptions = []): Boolean; override;

    procedure BuildFieldDefs;
    procedure GenerateFields(AWipeAll: Boolean = False; ARemoveOrphans: Boolean = True; AUpdateExisting: Boolean = True); virtual;
    procedure Load(const AItems: IObjectList; AClass: TClass; AOwns: Boolean = False); overload;
    procedure Load(const AItems: TArray<TObject>; AClass: TClass); overload;
    procedure Load<T: class>(const AItems: IList<T>; AClass: TClass; AOwns: Boolean = False); overload;
    procedure Load<T: class>(const AItems: IList<T>; AOwns: Boolean = False); overload;
    procedure Load<T: class>(const AItems: TArray<T>); overload;
    procedure LoadFromJson(const AJson: string; AClass: TClass); overload;
    procedure LoadFromJson<T: class>(const AJson: string); overload;
    procedure LoadFromUtf8Json(const ASpan: TByteSpan; AClass: TClass); overload;
    procedure LoadFromUtf8Json<T: class>(const ASpan: TByteSpan); overload;
    procedure Refresh;
    procedure RefreshRecord;
    procedure SetFieldData(Field: TField; Buffer: Pointer); overload; override;
    procedure SetFieldData(Field: TField; Buffer: TValueBuffer); overload; override;

    property DbContext: TDbContext read FDbContext write FDbContext;
    property Items: IObjectList read FItems write SetItems;
    property FilterExpression: IExpression read FFilterExpression write SetFilterExpression;
  published
    property Active stored IsActiveStored;
    property DataProvider: TEntityDataProvider read FDataProvider write SetDataProvider;
    property EntityClassName: string read FEntityClassName write SetEntityClassName;
    property FieldDefs;
    property Filter;
    property Filtered;
    property FilterOptions;
    property IncludeShadowProperties: Boolean read FIncludeShadowProperties write FIncludeShadowProperties default False;
    property IndexFieldNames: string read FIndexFieldNames write SetIndexFieldNames;
    property StringFieldKind: TStringFieldKind read FStringFieldKind write FStringFieldKind default sfAuto;
    property MasterFields: string read FMasterFields write SetMasterFields;
    property MasterSource: TDataSource read GetMasterSource write SetMasterSource;
    property ReadOnly: Boolean read FReadOnly write FReadOnly default False;
    property TableName: string read FTableName write FTableName;

    property AfterCancel;
    property AfterClose;
    property AfterDelete;
    property AfterEdit;
    property AfterInsert;
    property AfterOpen;
    property AfterPost;
    property AfterRefresh;
    property AfterScroll;
    property BeforeCancel;
    property BeforeClose;
    property BeforeDelete;
    property BeforeEdit;
    property BeforeInsert;
    property BeforeOpen;
    property BeforePost;
    property BeforeRefresh;
    property BeforeScroll;

    property OnCalcFields;
    property OnDeleteError;
    property OnEditError;
    property OnFilterRecord;
    property OnNewRecord;
    property OnPostError;
    property OnPrepareField: TPrepareFieldEvent read FOnPrepareField write FOnPrepareField;
  end;

  /// <summary>
  ///   Specialized internal data link for master-detail synchronization.
  /// </summary>
  TEntityMasterDataLink = class(TMasterDataLink)
  private
    FEntityDataSet: TEntityDataSet;
  protected
    procedure ActiveChanged; override;
    procedure RecordChanged(Field: TField); override;
  public
    constructor Create(ADataSet: TEntityDataSet);
  end;

function TranslateExpressionToFilterText(const AExpression: IExpression): string;

implementation

uses
  System.StrUtils,
  System.AnsiStrings,
  Dext.Core.ValueConverters,
  Dext.DI.Attributes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Core,
  Dext.Json,
  Dext.Specifications.Evaluator,
  Dext.Specifications.Parser,
  Dext.Specifications.Types;

type
  {$IF CompilerVersion < 36.0}
    {$IF Sizeof(LongInt) <> Sizeof(NativeInt)}
    TNativeCount = NativeInt;
    {$ELSE}
    TNativeCount = Longint;
    {$ENDIF}
  {$IFEND}

  TEntityBlobStream = class(TMemoryStream)
  private
    FDataSet: TEntityDataSet;
    FField: TField;
    FMode: TBlobStreamMode;
    FModified: Boolean;
    FObj: TObject;
  public
    constructor Create(Field: TField; DataSet: TEntityDataSet; Mode: TBlobStreamMode);
    destructor Destroy; override;
    {$IF (CompilerVersion >= 36.0) and (Sizeof(LongInt) <> Sizeof(NativeInt))}
    function Write(const Buffer; Count: Longint): Longint; override;
    {$ENDIF}
    {$IF CompilerVersion >= 36.0}
    function Write(const Buffer; Count: TNativeCount): TNativeCount; override;
    {$ELSE}
    function Write(const Buffer; Count: Longint): Longint; override;
    {$IFEND}
  end;

function TValueBufferToValue(ABuffer: TValueBuffer; ADataType: TFieldType): TValue;
var
  S: string;
begin
  case ADataType of
    ftString:
    begin
      S := TEncoding.Default.GetString(ABuffer);
      Result := TValue.From<string>(S.TrimRight([#0]));
    end;
    ftWideString, ftMemo, ftWideMemo:
    begin
      S := TEncoding.Unicode.GetString(ABuffer);
      Result := TValue.From<string>(S.TrimRight([#0]));
    end;
    ftInteger, ftSmallint, ftAutoInc:
      Result := TValue.From<Integer>(PInteger(@ABuffer[0])^);
    ftLargeint:
      Result := TValue.From<Int64>(PInt64(@ABuffer[0])^);
    ftFloat, ftCurrency:
      Result := TValue.From<Double>(PDouble(@ABuffer[0])^);
    ftBoolean:
      Result := TValue.From<Boolean>(PBoolean(@ABuffer[0])^);
    ftDateTime, ftDate, ftTime:
      Result := TValue.From<TDateTime>(PDouble(@ABuffer[0])^);
  else
    Result := TValue.Empty;
  end;
end;

{ TEntityDataSet }

procedure TEntityDataSet.Refresh;
begin
  if Active then
  begin
    ApplyFilterAndSort(Filtered);
    Resync([]);
  end;
end;

procedure TEntityDataSet.RefreshRecord;
begin
  if Active and (FCurrentRec >= 0) then
    Resync([]);
end;

function TEntityDataSet.GetProperty(const APropName: string): TRttiProperty;
var
  EntityType: TRttiType;
begin
  Result := nil;
  if (FEntityClass = nil) then Exit;
  if not FPropertyCache.TryGetValue(APropName, Result) then
  begin
    EntityType := TReflection.Context.GetType(FEntityClass);
    if EntityType <> nil then
      Result := EntityType.GetProperty(APropName);
    FPropertyCache.Add(APropName, Result);
  end;
end;

procedure TEntityDataSet.ClearResolvedEntityMetadata;
begin
  FEntityClass := nil;
  FPropertyCache.Clear;

  if Assigned(FEntityMap) and FOwnsEntityMap then
    FreeAndNil(FEntityMap)
  else
    FEntityMap := nil;

  FOwnsEntityMap := False;
end;

procedure TEntityDataSet.ResolveEntityClassFromProvider;
var
  DP: IEntityDataProvider;
  ResolvedClass: TClass;
begin
  // Em runtime, o design-time não deve interferir se a classe já foi definida (ex: via Load)
  if (FEntityClass <> nil) and not (csDesigning in ComponentState) then
    Exit;

  if (FEntityClassName = '') or (not Assigned(FDataProvider)) then
  begin
    // Só limpamos em design-time para manter o Object Inspector sincronizado
    if csDesigning in ComponentState then
      ClearResolvedEntityMetadata;
    Exit;
  end;

  if not FDataProvider.GetInterface(IEntityDataProvider, DP) then
  begin
    if csDesigning in ComponentState then
      ClearResolvedEntityMetadata;
    Exit;
  end;

  ResolvedClass := DP.ResolveEntityClass(FEntityClassName);
  if ResolvedClass = nil then
  begin
    if csDesigning in ComponentState then
      ClearResolvedEntityMetadata;
    Exit;
  end;

  if FEntityClass <> ResolvedClass then
  begin
    ClearResolvedEntityMetadata;
    FEntityClass := ResolvedClass;
  end;
end;

function TEntityDataSet.IsActiveStored: Boolean;
begin
  Result := not (csDesigning in ComponentState);
end;

function TEntityDataSet.ResolveTextFieldType: TFieldType;
var
  LDialect: TDatabaseDialect;
begin
  case FStringFieldKind of
    sfAnsi: Exit(ftString);
    sfWide: Exit(ftWideString);
  end;

  // Auto: infer from provider/dialect. PostgreSQL defaults to Unicode text.
  LDialect := ddUnknown;
  if Assigned(FDataProvider) then
  begin
    LDialect := FDataProvider.Dialect;
    if (LDialect = ddUnknown) and (FDataProvider.DatabaseConnection <> nil) then
      LDialect := TDialectFactory.DetectDialect(FDataProvider.DatabaseConnection.DriverName);
  end;

  if LDialect = ddPostgreSQL then
    Result := ftWideString
  else
    Result := ftString;
end;

procedure TEntityDataSet.Loaded;
begin
  inherited Loaded;
  if (csDesigning in ComponentState) and Active then
    Active := False;
end;

function TEntityDataSet.StringToFieldType(const ATypeName: string): TFieldType;
begin
  if SameText(ATypeName, 'string') or SameText(ATypeName, 'StringType') then Result := ResolveTextFieldType
  else if SameText(ATypeName, 'Integer') or SameText(ATypeName, 'Int32') or SameText(ATypeName, 'IntType') then Result := ftInteger
  else if SameText(ATypeName, 'SmallInt') then Result := ftSmallint
  else if SameText(ATypeName, 'Byte') then Result := ftByte
  else if SameText(ATypeName, 'ShortInt') then Result := ftShortint
  else if SameText(ATypeName, 'Word') then Result := ftWord
  else if SameText(ATypeName, 'LargeInt') or SameText(ATypeName, 'Int64') or SameText(ATypeName, 'Int64Type') or SameText(ATypeName, 'LargeIntType') then Result := ftLargeint
  else if SameText(ATypeName, 'Double') or SameText(ATypeName, 'Float') or SameText(ATypeName, 'FloatType') then Result := ftFloat
  else if SameText(ATypeName, 'Currency') or SameText(ATypeName, 'Money') or SameText(ATypeName, 'CurrencyType') then Result := ftCurrency
  else if SameText(ATypeName, 'TDateTime') or SameText(ATypeName, 'DateTime') or SameText(ATypeName, 'DateTimeType') then Result := ftDateTime
  else if SameText(ATypeName, 'TDate') or SameText(ATypeName, 'Date') or SameText(ATypeName, 'DateType') then Result := ftDate
  else if SameText(ATypeName, 'TTime') or SameText(ATypeName, 'Time') or SameText(ATypeName, 'TimeType') then Result := ftTime
  else if SameText(ATypeName, 'Boolean') or SameText(ATypeName, 'BoolType') or SameText(ATypeName, 'BooleanType') then Result := ftBoolean
  else if SameText(ATypeName, 'TBytes') or SameText(ATypeName, 'Blob') then Result := ftBlob
  else if SameText(ATypeName, 'TGUID') then Result := ftGuid
  else if ATypeName.StartsWith('I', True) or ATypeName.StartsWith('TList<', True) or ATypeName.StartsWith('TObjectList<', True) then Result := ftUnknown
  else if ATypeName.StartsWith('T', True) then Result := ftUnknown // Likely a Navigation property (e.g. TStock, TCategory)
  else Result := ftString;
end;

procedure TEntityDataSet.EnsureEntityMapResolved;
var
  DP: IEntityDataProvider;
  i: Integer;
  MD: TEntityClassMetadata;
  Member: TEntityMemberMetadata;
  LPropMap: TPropertyMap;
begin
  if FEntityMap <> nil then
    Exit;

  // Se não estamos em design, precisamos da classe
  if (FEntityClass = nil) and (not (csDesigning in ComponentState)) then
    Exit;

  // Try to resolve from DBContext first
  if Assigned(FDbContext) and (FEntityClass <> nil) then
  begin
    FEntityMap := FDbContext.ModelBuilder.GetMap(FEntityClass.ClassInfo);
    FOwnsEntityMap := FEntityMap = nil;
  end;

  // DESIGN-TIME RECOVERY: If RTTI is missing (FEntityClass = nil), try to build EntityMap from DataProvider (Parser)
  if (FEntityMap = nil) and (csDesigning in ComponentState) and Assigned(FDataProvider) then
  begin
    if FDataProvider.GetInterface(IEntityDataProvider, DP) then
    begin
      MD := DP.GetEntityMetadata(FEntityClassName);
      
      // CRITICAL: Only synchronize metadata from source files if not already present
      // to avoid overwriting manual design-time changes in the component.
      if (MD = nil) or (MD.Members.Count = 0) then
      begin
        DP.SyncMetadata(FEntityClassName);
        MD := DP.GetEntityMetadata(FEntityClassName);
      end;

      if MD <> nil then
      begin
        FEntityMap := TEntityMap.Create(nil);
        FOwnsEntityMap := True;
        FEntityMap.TableName := MD.TableName;
        if MD <> nil then
          FTableName := MD.TableName;

        for i := 0 to MD.Members.Count - 1 do
        begin
          Member := MD.Members[i];
          LPropMap := FEntityMap.GetOrAddProperty(Member.Name);
          LPropMap.ColumnName := Member.Name;
          LPropMap.DataType := StringToFieldType(Member.MemberType);
          LPropMap.IsPK := Member.IsPrimaryKey;
          LPropMap.IsRequired := Member.IsRequired;
          LPropMap.IsAutoInc := Member.IsAutoInc;
          LPropMap.Visible := Member.Visible;
          LPropMap.IsReadOnly := Member.IsReadOnly;
          LPropMap.MaxLength := Member.MaxLength;
          LPropMap.DisplayLabel := Member.DisplayLabel;
          LPropMap.DisplayFormat := Member.DisplayFormat;
          LPropMap.DisplayWidth := Member.DisplayWidth;
          LPropMap.Alignment := Member.Alignment;
          LPropMap.EditMask := Member.EditMask;

          // Resolve navigation primarily from relationship metadata.
          // Type-based detection is only a fallback when relation metadata is missing.
          if SameText(Member.RelationType, 'OneToMany') or SameText(Member.RelationType, 'HasMany') then
          begin
            LPropMap.IsNavigation := True;
            LPropMap.Relationship := rtOneToMany;
          end
          else if SameText(Member.RelationType, 'ManyToOne') or SameText(Member.RelationType, 'BelongsTo') then
          begin
            LPropMap.IsNavigation := True;
            LPropMap.Relationship := rtManyToOne;
          end
          else if SameText(Member.RelationType, 'OneToOne') or SameText(Member.RelationType, 'HasOne') then
          begin
            LPropMap.IsNavigation := True;
            LPropMap.Relationship := rtOneToOne;
          end
          else if SameText(Member.RelationType, 'ManyToMany') then
          begin
            LPropMap.IsNavigation := True;
            LPropMap.Relationship := rtManyToMany;
          end
          // No type-based fallback here: relation metadata is the source of truth.
        end;
      end;
    end;
  end;

  if FEntityMap = nil then
  begin
    if FEntityClass <> nil then
      FEntityMap := TEntityMap.Create(FEntityClass.ClassInfo)
    else
      FEntityMap := TEntityMap.Create(nil);

    FEntityMap.DiscoverAttributes;
    FOwnsEntityMap := True;
  end;

  // Sync TableName with Mapped TableName
  if (FEntityMap <> nil) then
  begin
    if (csDesigning in ComponentState) or (FTableName = '') then
      FTableName := FEntityMap.TableName;
  end;
end;

constructor TEntityDataSet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRecordSize := SizeOf(TEntityRecordHeader);
  FHeaderSize := SizeOf(TEntityRecordHeader);
  FReadOnly := False;
  BookmarkSize := SizeOf(Integer);
  FPositionBeforeAction := -2;
  FCalcOffsets := TDictionary<string, Integer>.Create;
  FPropertyCache := TDictionary<string, TRttiProperty>.Create;
  FDetailDataSets := TDictionary<string, TDataSet>.Create;
  FStringFieldKind := sfAuto;
  FTrackedChanges := TCollections.CreateList<TEntityChange>;
  FCurrentDirtyFields := TCollections.CreateList<string>;
  FDataSetCreatedItems := TCollections.CreateList<TObject>(True);
  FDeletedItemsCache := TCollections.CreateList<TObject>(True);
end;

destructor TEntityDataSet.Destroy;
var
  Dict: TDictionary<string, Variant>;
begin
  Close; // Garante que InternalClose rode enquanto as estruturas estao vivas

  if Assigned(FDataProvider) then
    FDataProvider.UnregisterDataSet(Self);

  FreeAndNil(FPropertyCache);
  FreeAndNil(FCalcOffsets);
  FreeAndNil(FDetailDataSets);
  FreeAndNil(FInsertObj);

  for Dict in FPreviewData do
    Dict.Free;
  SetLength(FPreviewData, 0);

  // FDataSetCreatedItems holds objects created by the dataset via Append/Insert.
  // Freeing this list releases those objects regardless of FOwnsItems.
  FDataSetCreatedItems := nil;
  // Freeing this list releases all deleted objects that were cached.
  FDeletedItemsCache := nil;

  FItems := nil;
  FTrackedChanges := nil;
  FCurrentDirtyFields := nil;

  if Assigned(FEntityMap) and FOwnsEntityMap then
    FreeAndNil(FEntityMap);

  FreeAndNil(FMasterLink);

  inherited Destroy;
end;

function TEntityDataSet.GetCurrentObject: TObject;
var
  Header: PEntityRecordHeader;
begin
  Result := nil;
  if not Active then Exit;
  
  Header := PEntityRecordHeader(ActiveBuffer);
  if (Header <> nil) then
  begin
    if (Header.BookmarkIndex = -2) then
      Exit(FInsertObj)
    else if (Header.BookmarkIndex >= 0) and (Header.BookmarkIndex < FVirtualIndex.Count) then
      Exit(FItems[FVirtualIndex[Header.BookmarkIndex]]);
  end;

  if (FCurrentRec >= 0) and (FCurrentRec < FVirtualIndex.Count) then
    Result := FItems[FVirtualIndex[FCurrentRec]];
end;

procedure TEntityDataSet.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;

  if (Operation = opRemove) and (AComponent = FDataProvider) then
  begin
    FDataProvider := nil;
    ResolveEntityClassFromProvider;
  end;
end;

function TEntityDataSet.CreateBlobStream(Field: TField; Mode: TBlobStreamMode): TStream;
begin
  Result := TEntityBlobStream.Create(Field, Self, Mode);
end;

{ TEntityBlobStream }

constructor TEntityBlobStream.Create(Field: TField; DataSet: TEntityDataSet; Mode: TBlobStreamMode);
var
  B: TBytes;
  S: string;
  Val: TValue;
begin
  inherited Create;
  FField := Field;
  FDataSet := DataSet;
  FMode := Mode;
  FModified := False;
  FObj := FDataSet.GetCurrentObject;
  
  if (FMode <> bmWrite) and Assigned(FObj) then
  begin
    Val := TReflection.GetValue(FObj, FField.FieldName);
    if not Val.IsEmpty then
    begin
      if FField.DataType in [ftMemo, ftWideMemo] then
      begin
        S := Val.AsString;
        if S <> '' then
        begin
          B := TEncoding.Unicode.GetBytes(S);
          Write(B[0], Length(B));
        end;
      end
      else if FField.DataType = ftBlob then
      begin
        B := Val.AsType<TBytes>;
        if Length(B) > 0 then
          Write(B[0], Length(B));
      end;
      Position := 0;
    end;
  end;
end;

destructor TEntityBlobStream.Destroy;
var
  B: TBytes;
  S: string;
begin
  if FModified and (FMode <> bmRead) and Assigned(FObj) then
  begin
    Position := 0;
    SetLength(B, Size);
    if Size > 0 then
      Read(B[0], Size);

    if FField.DataType in [ftMemo, ftWideMemo] then
    begin
      // Detect and strip Unicode BOM ($FF $FE) if present
      if (Size >= 2) and (B[0] = $FF) and (B[1] = $FE) then
        S := TEncoding.Unicode.GetString(B, 2, Size - 2)
      else
        S := TEncoding.Unicode.GetString(B);
        
      TReflection.SetValueByPath(FObj, FField.FieldName, S);
    end
    else
      TReflection.SetValueByPath(FObj, FField.FieldName, TValue.From<TBytes>(B));
  end;
  inherited Destroy;
end;

{$IF (CompilerVersion >= 36.0) and (Sizeof(LongInt) <> Sizeof(NativeInt))}
function TEntityBlobStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := inherited Write(Buffer, Count);
  FModified := True;
end;
{$ENDIF}

{$IF CompilerVersion >= 36.0}
function TEntityBlobStream.Write(const Buffer; Count: TNativeCount): TNativeCount;
begin
  Result := inherited Write(Buffer, Count);
  FModified := True;
end;
{$ELSE}
function TEntityBlobStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := inherited Write(Buffer, Count);
  FModified := True;
end;
{$IFEND}

procedure TEntityDataSet.Load(const AItems: IObjectList; AClass: TClass; AOwns: Boolean = False);
begin
  if FOwnsItems and Assigned(FItems) and (FItems <> AItems) then
    FItems := nil;

  if FEntityClass <> AClass then
    ClearResolvedEntityMetadata;

  FItems := AItems;
  FEntityClass := AClass;
  FOwnsItems := AOwns;
  // Direct load via IObjectList: external list manages object lifetime.
  FItemsIsNonOwningWrapper := False;
  EnsureEntityMapResolved;
  
  if Active then
    Refresh
  else
    Active := True;
end;

procedure TEntityDataSet.Load(const AItems: TArray<TObject>; AClass: TClass);
var
  List: IList<TObject>;
begin
  List := TCollections.CreateList<TObject>(False);
  List.AddRange(AItems);
  Load(List as IObjectList, AClass, True); // Owns the wrapper list but not the objects
end;

function TEntityDataSet.AsJsonArray: string;
var
  I: Integer;
  Stream: TStringStream;
  Writer: TUtf8JsonWriter;
begin
  if (FItems = nil) or (FVirtualIndex.Count = 0) then
    Exit('[]');

  // Refinado para respeitar filtros e ordenação e usar pipeline de streaming (Otimizado)
  Stream := TStringStream.Create('', TEncoding.UTF8);
  try
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteStartArray;
    for I := 0 to FVirtualIndex.Count - 1 do
    begin
      Writer.WriteValue(FItems[FVirtualIndex[I]]);
    end;
    Writer.WriteEndArray;
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

function TEntityDataSet.AsJsonObject: string;
var
  Obj: TObject;
begin
  Obj := GetCurrentObject;
  if Obj = nil then
    Exit('{}');
  Result := TDextJson.Serialize(Obj);
end;

procedure TEntityDataSet.Load<T>(const AItems: TArray<T>);
var
  i: Integer;
  ItemClass: TClass;
  ObjArray: TArray<TObject>;
begin
  ItemClass := TClass(Pointer(GetTypeData(TypeInfo(T))^.ClassType));
  SetLength(ObjArray, Length(AItems));
  for i := 0 to High(AItems) do
    ObjArray[i] := TObject(AItems[i]);
  Load(ObjArray, ItemClass);
end;

procedure TEntityDataSet.Load<T>(const AItems: IList<T>; AOwns: Boolean);
begin
  Load<T>(AItems, TClass(Pointer(GetTypeData(TypeInfo(T))^.ClassType)), AOwns);
end;

procedure TEntityDataSet.Load<T>(const AItems: IList<T>; AClass: TClass; AOwns: Boolean);
var
  i: Integer;
  ListObj: IList<TObject>;
begin
  ListObj := TCollections.CreateList<TObject>(AOwns);
  for i := 0 to AItems.Count - 1 do
    ListObj.Add(TObject(AItems[i]));
  Load(ListObj as IObjectList, AClass, AOwns);
  // Set AFTER Load() call — Load() resets this flag to False.
  // When AOwns=False, the wrapper is non-owning: Append-created objects
  // have no external owner and must be tracked in FDataSetCreatedItems.
  FItemsIsNonOwningWrapper := not AOwns;
end;

procedure TEntityDataSet.LoadFromJson(const AJson: string; AClass: TClass);
var
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AJson);
  LoadFromUtf8Json(TByteSpan.FromBytes(Bytes), AClass);
end;

procedure TEntityDataSet.LoadFromJson<T>(const AJson: string);
begin
  LoadFromJson(AJson, TClass(Pointer(GetTypeData(TypeInfo(T))^.ClassType)));
end;

procedure TEntityDataSet.LoadFromUtf8Json<T>(const ASpan: TByteSpan);
begin
  LoadFromUtf8Json(ASpan, TClass(Pointer(GetTypeData(TypeInfo(T))^.ClassType)));
end;

procedure TEntityDataSet.LoadFromUtf8Json(const ASpan: TByteSpan; AClass: TClass);
var
  CurrentObj: TObject;
  DateValue: TDateTime;
  PropMap: TPropertyMap;
  PropName: string;
  PValue: Pointer;
  Reader: TUtf8JsonReader;
  RttiProp: TRttiProperty;
  RttiType: TRttiType;
begin
  if FEntityClass <> AClass then
    ClearResolvedEntityMetadata;

  FEntityClass := AClass;
  EnsureEntityMapResolved;

  Reader := TUtf8JsonReader.Create(ASpan);

  // Limpar itens anteriores
  if not Assigned(FItems) then
    FItems := TCollections.CreateList<TObject>(True) as IObjectList;

  if FOwnsItems then
    FItems.Clear;
  FOwnsItems := True;

  if not Reader.Read then Exit;

  // Use centralized RTTI context
  RttiType := TReflection.Context.GetType(FEntityClass);

    if Reader.TokenType = TJsonTokenType.StartArray then
    begin
      while Reader.Read and (Reader.TokenType <> TJsonTokenType.EndArray) do
      begin
        if Reader.TokenType = TJsonTokenType.StartObject then
        begin
          CurrentObj := FEntityClass.Create;

          FItems.Add(CurrentObj);

          while Reader.Read and (Reader.TokenType <> TJsonTokenType.EndObject) do
          begin
            if Reader.TokenType = TJsonTokenType.PropertyName then
            begin
              PropName := Reader.GetString;
              Reader.Read; // Avance para o valor

              if FEntityMap.Properties.TryGetValue(PropName, PropMap) then
              begin
                // Se o FieldValueOffset é válido (> 0), escrita direta por offset (fast-path)
                // Caso contrário, fallback via RTTI SetValue
                if PropMap.FieldValueOffset > 0 then
                begin
                  PValue := Pointer(PByte(CurrentObj) + PropMap.FieldValueOffset);
                  
                  // Ativar flag de nulo se definido (SmartProp, Nullable, Lazy)
                  if PropMap.FieldOffset > 0 then
                    PBoolean(Pointer(PByte(CurrentObj) + PropMap.FieldOffset))^ := True;

                  case PropMap.DataType of
                    ftString, ftWideString:
                      PString(PValue)^ := Reader.GetString;
                    ftInteger:
                      PInteger(PValue)^ := Reader.GetInt32;
                    ftSmallint:
                      PSmallInt(PValue)^ := SmallInt(Reader.GetInt32);
                    ftShortint:
                      PShortInt(PValue)^ := ShortInt(Reader.GetInt32);
                    ftByte:
                      PByte(PValue)^ := Byte(Reader.GetInt32);
                    ftWord:
                      PWord(PValue)^ := Word(Reader.GetInt32);
                    ftLargeint:
                      PInt64(PValue)^ := Reader.GetInt64;
                    ftFloat:
                      PDouble(PValue)^ := Reader.GetDouble;
                    ftCurrency:
                      PCurrency(PValue)^ := Reader.GetDouble;
                    ftBoolean:
                      PBoolean(PValue)^ := Reader.GetBoolean;
                    ftDateTime, ftDate:
                    begin
                      if TryParseISODateTime(Reader.GetString, DateValue) then
                        PDateTime(PValue)^ := DateValue;
                    end;
                    ftTime:
                    begin
                      // A time of day ("10:30:00.000") or a whole date and time
                      if TryParseJsonTime(Reader.GetString, DateValue) then
                        PDateTime(PValue)^ := DateValue;
                    end;
                  end;
                end
                else if RttiType <> nil then
                begin
                  RttiProp := PropMap.Prop;
                  if RttiProp = nil then
                    RttiProp := RttiType.GetProperty(PropMap.PropertyName);
                  if RttiProp <> nil then
                  begin
                    case Reader.TokenType of
                      TJsonTokenType.StringValue:
                      begin
                        if RttiProp.PropertyType.Handle =
                           TypeInfo(TDateTime) then
                        begin
                          if TryParseISODateTime(Reader.GetString,
                                                 DateValue) then
                            RttiProp.SetValue(CurrentObj, DateValue);
                        end
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(TDate) then
                        begin
                          if TryParseISODateTime(Reader.GetString,
                                                 DateValue) then
                            RttiProp.SetValue(CurrentObj,
                                              Trunc(DateValue));
                        end
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(TTime) then
                        begin
                          if TryParseISODateTime(Reader.GetString,
                                                 DateValue) then
                            RttiProp.SetValue(CurrentObj,
                                              Frac(DateValue));
                        end
                        else
                          RttiProp.SetValue(CurrentObj, Reader.GetString);
                      end;
                      TJsonTokenType.Number:
                      begin
                        if RttiProp.PropertyType.Handle =
                           TypeInfo(Integer) then
                          RttiProp.SetValue(CurrentObj, Reader.GetInt32)
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(Int64) then
                          RttiProp.SetValue(CurrentObj, Reader.GetInt64)
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(SmallInt) then
                          RttiProp.SetValue(CurrentObj,
                            SmallInt(Reader.GetInt32))
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(Byte) then
                          RttiProp.SetValue(CurrentObj,
                            Byte(Reader.GetInt32))
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(ShortInt) then
                          RttiProp.SetValue(CurrentObj,
                            ShortInt(Reader.GetInt32))
                        else if RttiProp.PropertyType.Handle =
                                TypeInfo(Word) then
                          RttiProp.SetValue(CurrentObj,
                            Word(Reader.GetInt32))
                        else
                          RttiProp.SetValue(CurrentObj,
                            TValue.From<Double>(Reader.GetDouble));
                      end;
                      TJsonTokenType.TrueValue, TJsonTokenType.FalseValue:
                        RttiProp.SetValue(CurrentObj, Reader.GetBoolean);
                    end;
                  end;
                end;
              end
              else if RttiType <> nil then
              begin
                // RTTI fallback para classes que usam campos privados padrao
                RttiProp := RttiType.GetProperty(PropName);
                if RttiProp <> nil then
                begin
                  case Reader.TokenType of
                    TJsonTokenType.StringValue:
                    begin
                      if RttiProp.PropertyType.Handle = TypeInfo(TDateTime) then
                      begin
                        if TryParseISODateTime(Reader.GetString, DateValue) then
                          RttiProp.SetValue(CurrentObj, DateValue);
                      end
                      else if RttiProp.PropertyType.Handle = TypeInfo(TDate) then
                      begin
                        if TryParseISODateTime(Reader.GetString, DateValue) then
                          RttiProp.SetValue(CurrentObj, Trunc(DateValue));
                      end
                      else if RttiProp.PropertyType.Handle = TypeInfo(TTime) then
                      begin
                        // A time of day ("10:30:00.000") or a whole date and time
                        if TryParseJsonTime(Reader.GetString, DateValue) then
                          RttiProp.SetValue(CurrentObj, Frac(DateValue));
                      end
                      else
                        RttiProp.SetValue(CurrentObj, Reader.GetString);
                    end;
                    TJsonTokenType.Number:
                    begin
                      if RttiProp.PropertyType.Handle = TypeInfo(Integer) then
                        RttiProp.SetValue(CurrentObj, Reader.GetInt32)
                      else if RttiProp.PropertyType.Handle = TypeInfo(Int64) then
                        RttiProp.SetValue(CurrentObj, Reader.GetInt64)
                      else if RttiProp.PropertyType.Handle =
                        TypeInfo(SmallInt) then
                        RttiProp.SetValue(CurrentObj,
                          SmallInt(Reader.GetInt32))
                      else if RttiProp.PropertyType.Handle =
                        TypeInfo(Byte) then
                        RttiProp.SetValue(CurrentObj,
                          Byte(Reader.GetInt32))
                      else if RttiProp.PropertyType.Handle =
                        TypeInfo(ShortInt) then
                        RttiProp.SetValue(CurrentObj,
                          ShortInt(Reader.GetInt32))
                      else if RttiProp.PropertyType.Handle =
                        TypeInfo(Word) then
                        RttiProp.SetValue(CurrentObj,
                          Word(Reader.GetInt32))
                      else
                        RttiProp.SetValue(CurrentObj,
                          TValue.From<Double>(Reader.GetDouble));
                    end;
                    TJsonTokenType.TrueValue, TJsonTokenType.FalseValue:
                      RttiProp.SetValue(CurrentObj, Reader.GetBoolean);
                  end;
                end;
              end;
            end
            else
              Reader.Skip; // propriedade nao mapeada, pula valor/objeto
          end;
        end;
      end;
    end;

  // Ativar o dataset e reconstruirvisao virtual
  Load(FItems, AClass, True);
end;

procedure TEntityDataSet.SetIndexFieldNames(const Value: string);
begin
  if FIndexFieldNames <> Value then
  begin
    FIndexFieldNames := Value;
    SyncMasterDetail;
    if Active then
    begin
      ApplyFilterAndSort;
      Resync([]);
    end;
  end;
end;

procedure TEntityDataSet.SetFiltered(Value: Boolean);
begin
  if Filtered <> Value then
  begin
    inherited SetFiltered(Value);
    if Active then 
    begin
       if Assigned(FMasterLink) and (FMasterLink.DataSource <> nil) then
         SyncMasterDetail;
       ApplyFilterAndSort(Value);
    end;
  end;
end;

procedure TEntityDataSet.SetFilterText(const Value: string);
begin
  if Filter <> Value then
  begin
     inherited SetFilterText(Value);
     if Active then 
     begin
        if Assigned(FMasterLink) and (FMasterLink.DataSource <> nil) then
          SyncMasterDetail;
        ApplyFilterAndSort(Filtered);
     end;
  end;
end;

procedure TEntityDataSet.SetFilterOptions(Value: TFilterOptions);
begin
  if FilterOptions <> Value then
  begin
     inherited SetFilterOptions(Value);
     if Active then ApplyFilterAndSort(Filtered);
  end;
end;

procedure TEntityDataSet.ApplyFilterAndSort;
begin
  ApplyFilterAndSort(Filtered);
end;

procedure TEntityDataSet.ApplyFilterAndSort(AFiltered: Boolean);
begin
  ApplyFilterAndSort(AFiltered, nil);
end;

procedure TEntityDataSet.ApplyFilterAndSort(AFiltered: Boolean; ATrackObj: TObject);
var
  CurrentObj: TObject;
  EntityType: TRttiType;
  Expr: IExpression;
  i: Integer;
  ItemsCount: Integer;
  Names: TArray<string>;
  NewPhysicalIdx: Integer;
  Passing: Boolean;
begin
  if FIsApplyingFilter then Exit;
  FIsApplyingFilter := True;
  try
    if not Assigned(FItems) and not FIsDesignTimePreview then Exit;

    // Sync Master-Detail filter if linked
    if Assigned(FMasterLink) and (FMasterLink.DataSource <> nil) then
      SyncMasterDetail;

    // Salvar objeto p/ restaurar cursor
    CurrentObj := ATrackObj;
    if Assigned(FItems) and (CurrentObj = nil) and (FCurrentRec >= 0) and (FCurrentRec < FVirtualIndex.Count) then
      CurrentObj := FItems[FVirtualIndex[FCurrentRec]];

    FVirtualIndex.Clear;
    FCurrentRec := -1;

    if Assigned(FItems) and (FItems.Count > 0) then 
      ItemsCount := FItems.Count
    else if FIsDesignTimePreview then 
      ItemsCount := Length(FPreviewData)
    else 
      ItemsCount := 0;

    try
      Expr := FFilterExpression;
      if (Expr = nil) and AFiltered and (Filter <> '') then
        Expr := TStringExpressionParser.Parse(Filter);
    except
      if csDesigning in ComponentState then
      begin
        FVirtualIndex.Clear;
        for i := 0 to ItemsCount - 1 do
          FVirtualIndex.Add(i);
        Exit;
      end
      else raise;
    end;

    for i := 0 to ItemsCount - 1 do
    begin
      Passing := True;
      if AFiltered then
      begin
        if Expr <> nil then
        begin
          try
            if Assigned(FItems) then
              Passing := TExpressionEvaluator.Evaluate(Expr, FItems[I])
            else
              Passing := TExpressionEvaluator.Evaluate(Expr, FPreviewData[I]);
          except
            if csDesigning in ComponentState then Passing := False
            else raise;
          end;
        end
        else if Assigned(OnFilterRecord) then
          OnFilterRecord(Self, Passing);
      end;
      if Passing then
        FVirtualIndex.Add(I);
    end;

    // Ordenação (Apenas runtime ou se FItems existe no preview)
    if (FIndexFieldNames <> '') and (FVirtualIndex.Count > 1) and Assigned(FItems) then
    begin
      Names := FIndexFieldNames.Split([';']);
      // Use centralized RTTI context
      EntityType := TReflection.Context.GetType(FEntityClass);
      FVirtualIndex.Sort(Dext.Collections.Comparers.TComparer<Integer>.Construct(
        function(const A, B: Integer): Integer
        begin
          Result := CompareObjectsInternal(FItems[A], FItems[B], Names, EntityType);
        end));
    end;

    // Restaurar a posição do cursor na visão virtual
    if CurrentObj <> nil then
    begin
      NewPhysicalIdx := FItems.IndexOf(CurrentObj);
      if (NewPhysicalIdx >= 0) then
        FCurrentRec := FVirtualIndex.IndexOf(NewPhysicalIdx)
      else
        FCurrentRec := -1;
    end
    else
      FCurrentRec := -1;
      
  finally
    FIsApplyingFilter := False;
  end;
end;

function TEntityDataSet.Locate(const KeyFields: string; const KeyValues: Variant; Options: TLocateOptions): Boolean;
var
  FieldNames: TArray<string>;
  FieldVal: Variant;
  I, J: Integer;
  LFields: TArray<TField>;
  LValBuf: TValueBuffer;
  Match: Boolean;
  Offset: Integer;
  P: PByte;
  PropMap: TPropertyMap;
  PValue: Pointer;
  SaveRec: Integer;
  TempBuf: TRecordBuffer;

  function CompareValues(const V1, V2: Variant): Boolean;
  begin
    if (loPartialKey in Options) and (VarIsStr(V1) and VarIsStr(V2)) then
      Result := StartsText(V2, V1)
    else if (loCaseInsensitive in Options) and (VarIsStr(V1) and VarIsStr(V2)) then
      Result := SameText(V1, V2)
    else
      Result := (V1 = V2);
  end;

begin
  Result := False;
  if (KeyFields = '') or (FVirtualIndex.Count = 0) then Exit;

  FieldNames := KeyFields.Split([';']);
  SetLength(LFields, Length(FieldNames));
  for I := 0 to High(FieldNames) do
  begin
    LFields[I] := FindField(FieldNames[I]);
    if LFields[I] = nil then Exit(False);
  end;

  SaveRec := FCurrentRec;
  TempBuf := AllocRecordBuffer;
  try
    for I := 0 to FVirtualIndex.Count - 1 do
    begin
      FCurrentRec := I;
      Match := True;

      for J := 0 to High(LFields) do
      begin
        FieldVal := Unassigned;
        
        if FEntityMap.Properties.TryGetValue(LFields[J].FieldName, PropMap) and (PropMap.FieldValueOffset > 0) then
        begin
          // Check for Null flag first
          if (PropMap.FieldOffset > 0) and not PBoolean(Pointer(PByte(FItems[FVirtualIndex[I]]) + PropMap.FieldOffset))^ then
            FieldVal := Null
          else
          begin
            PValue := Pointer(PByte(FItems[FVirtualIndex[I]]) + PropMap.FieldValueOffset);
            case PropMap.DataType of
              ftInteger, ftSmallint, ftAutoInc: FieldVal := PInteger(PValue)^;
              ftLargeint: FieldVal := PInt64(PValue)^;
              ftString, ftWideString: FieldVal := PString(PValue)^;
              ftFloat: FieldVal := PDouble(PValue)^;
              ftCurrency: FieldVal := PCurrency(PValue)^;
              ftBoolean: FieldVal := PBoolean(PValue)^;
              ftDateTime, ftDate, ftTime: FieldVal := PDateTime(PValue)^;
            end;
          end;
        end;

        // 2. Fallback para campos calculados ou sem offset (lê do objeto via RTTI ou evento OnCalcFields)
        if VarIsEmpty(FieldVal) then
        begin
          if LFields[J].FieldKind in [fkCalculated, fkLookup, fkInternalCalc] then
          begin
            // Recalcular campos para este registro no buffer temporário
            PEntityRecordHeader(TempBuf).BookmarkIndex := I;
            CalculateFields(TRecBuf(TempBuf));
            
            // Extrair valor do buffer de calculados
            if FCalcOffsets.TryGetValue(LFields[J].FieldName, Offset) then
            begin
              P := PByte(TempBuf);
              Inc(P, Offset - 1);
              if P^ = 0 then // Null Flag
                FieldVal := Null
              else
              begin
                Inc(P);
                // Usamos um buffer de valor genérico para extrair
                SetLength(LValBuf, LFields[J].DataSize);
                Move(P^, LValBuf[0], LFields[J].DataSize);
                FieldVal := TValueBufferToValue(LValBuf, LFields[J].DataType).AsVariant;
              end;
            end;
          end
          else
          begin
            // RTTI Fallback (via ReadFieldValue que já usa FCurrentRec)
            ReadFieldValue(LFields[J], TRecBuf(TempBuf), FieldVal);
          end;
        end;

        if Length(LFields) = 1 then
          Match := CompareValues(FieldVal, KeyValues)
        else
          Match := CompareValues(FieldVal, KeyValues[J]);

        if not Match then Break;
      end;

      if Match then
      begin
        FCurrentRec := I;
        Resync([]);
        Result := True;
        Break;
      end;
    end;
  finally
    FreeRecordBuffer(TempBuf);
    if not Result then
      FCurrentRec := SaveRec;
  end;
end;

function TEntityDataSet.CompareObjectsInternal(A, B: TObject; const APropNames: TArray<string>; RttiType: TRttiType): Integer;
var
  f: TRttiField;
  i: Integer;
  IdA: Integer;
  IdB: Integer;
  IsDesc: Boolean;
  Matched: Boolean;
  p: TRttiProperty;
  PropMap: TPropertyMap;
  PropName: string;
  RttiField: TRttiField;
  RttiProp: TRttiProperty;
  Token: string;
  ValA, ValB: Variant;
begin
  Result := 0;
  PropName := '';
  for i := 0 to High(APropNames) do
  begin
    Token := APropNames[i].Trim;
    if Token = '' then Continue;
    IsDesc := Token.EndsWith(' DESC', True);
    PropName := Token;
    if IsDesc then
      PropName := Token.Substring(0, Token.Length - 5).Trim;

    ValA := Unassigned;
    ValB := Unassigned;
    Matched := False;

    // 1. Try Fast-Path via Mapper (Value Extraction)
    PropMap := nil;
    if FEntityMap.Properties.TryGetValue(PropName, PropMap) then
    begin
      if PropMap.FieldValueOffset > 0 then
      begin
        case PropMap.DataType of
          ftInteger, ftAutoInc, ftShortint, ftWord:
            begin
              ValA := PInteger(Pointer(PByte(A) + PropMap.FieldValueOffset))^;
              ValB := PInteger(Pointer(PByte(B) + PropMap.FieldValueOffset))^;
              Matched := True;
            end;
          ftBoolean:
            begin
              // Use PByte for Boolean as it's typically 1 byte in memory
              ValA := PByte(Pointer(PByte(A) + PropMap.FieldValueOffset))^;
              ValB := PByte(Pointer(PByte(B) + PropMap.FieldValueOffset))^;
              Matched := True;
            end;
          ftFloat:
            begin
              ValA := PDouble(Pointer(PByte(A) + PropMap.FieldValueOffset))^;
              ValB := PDouble(Pointer(PByte(B) + PropMap.FieldValueOffset))^;
              Matched := True;
            end;
          ftCurrency:
            begin
              ValA := PCurrency(Pointer(PByte(A) + PropMap.FieldValueOffset))^;
              ValB := PCurrency(Pointer(PByte(B) + PropMap.FieldValueOffset))^;
              Matched := True;
            end;
        end;
      end;
    end;

    // 2. Try RTTI Fallback
    if (not Matched) and (RttiType <> nil) then
    begin
      RttiProp := nil;
      for p in RttiType.GetProperties do
        if SameText(p.Name, PropName) then
        begin
          RttiProp := p;
          Break;
        end;

      if RttiProp <> nil then
      begin
        ValA := RttiProp.GetValue(A).AsVariant;
        ValB := RttiProp.GetValue(B).AsVariant;
      end
      else
      begin
        RttiField := nil;
        for f in RttiType.GetFields do
          if SameText(f.Name, PropName) or SameText(f.Name, TReflection.NormalizeFieldName(PropName)) then
          begin
            RttiField := f;
            Break;
          end;

        if RttiField <> nil then
        begin
          ValA := RttiField.GetValue(A).AsVariant;
          ValB := RttiField.GetValue(B).AsVariant;
        end;
      end;
    end;

    // Compare Variants obtained either via Fast-Path or RTTI
    if (not VarIsEmpty(ValA)) and (not VarIsEmpty(ValB)) then
    begin
      if ValA < ValB then Result := -1 else if ValA > ValB then Result := 1;
    end;

    if Result <> 0 then
    begin
      if IsDesc then Result := -Result;
      Break;
    end;
  end;

  // Stable sort tie-breaker (important for tests)
  if (Result = 0) and (not SameText(PropName, 'Id')) then
  begin
    PropMap := nil;
    if FEntityMap.Properties.TryGetValue('Id', PropMap) then
    begin
      if PropMap.FieldValueOffset > 0 then
      begin
        IdA := PInteger(Pointer(PByte(A) + PropMap.FieldValueOffset))^;
        IdB := PInteger(Pointer(PByte(B) + PropMap.FieldValueOffset))^;
        if IdA < IdB then Result := -1 else if IdA > IdB then Result := 1;
      end;
    end
    else if RttiType <> nil then
    begin
      // Last-resort RTTI tie-breaker
      RttiProp := nil;
      for p in RttiType.GetProperties do
        if SameText(p.Name, 'Id') then
        begin
          RttiProp := p;
          Break;
        end;
      if RttiProp <> nil then
      begin
        ValA := RttiProp.GetValue(A).AsVariant;
        ValB := RttiProp.GetValue(B).AsVariant;
        if ValA < ValB then Result := -1 else if ValA > ValB then Result := 1;
      end;
    end;
  end;
end;

procedure TEntityDataSet.SetItems(const Value: IObjectList);
begin
  if FItems <> Value then
  begin
    if FOwnsItems then
      FItems := nil;
    
    FItems := Value;
    FOwnsItems := False; // Por padrão não somos donos de uma lista injetada via property

    if Active then
    begin
      ApplyFilterAndSort;
      Resync([]);
    end;
  end;
end;

function TranslateExpressionToFilterText(const AExpression: IExpression): string;
var
  Obj: TObject;
  Bin: TBinaryExpression;
  LogExpr: TLogicalExpression;
  Un: TUnaryExpression;
  Val: TValue;
  OpStr: string;
  Pattern: string;
begin
  Result := '';
  if AExpression = nil then
    Exit;

  Obj := AExpression as TObject;
  if Obj = nil then
    Exit;

  if Obj is TPropertyExpression then
  begin
    Result := TPropertyExpression(Obj).PropertyName;
  end
  else if Obj is TLiteralExpression then
  begin
    Val := TLiteralExpression(Obj).Value;
    if Val.Kind in [tkChar, tkString, tkWChar, tkLString, tkUString] then
      Result := QuotedStr(Val.ToString)
    else
      // Garante o uso do ponto como separador decimal para compatibilidade com o parser de filtros do TDataSet
      Result := Val.ToString.Replace(',', '.');
  end
  else if (Obj is TBinaryExpression) and
    (TBinaryExpression(Obj).BinaryOperator in [boStartsWith, boEndsWith, boContains]) and
    (TBinaryExpression(Obj).Right is TLiteralExpression) then
  begin
    // The same LIKE text as before these operators existed. TDataSet filters
    // have no ESCAPE clause, so a % or _ in the value stays a wildcard here.
    Bin := TBinaryExpression(Obj);
    Pattern := TLiteralExpression(Bin.Right).Value.ToString;
    case Bin.BinaryOperator of
      boStartsWith: Pattern := Pattern + '%';
      boEndsWith: Pattern := '%' + Pattern;
    else
      Pattern := '%' + Pattern + '%';
    end;
    Result := Format('(%s LIKE %s)', [TranslateExpressionToFilterText(Bin.Left), QuotedStr(Pattern)]);
  end
  else if Obj is TBinaryExpression then
  begin
    Bin := TBinaryExpression(Obj);
    case Bin.BinaryOperator of
      boEqual: OpStr := '=';
      boNotEqual: OpStr := '<>';
      boGreaterThan: OpStr := '>';
      boGreaterThanOrEqual: OpStr := '>=';
      boLessThan: OpStr := '<';
      boLessThanOrEqual: OpStr := '<=';
      boLike: OpStr := 'LIKE';
      else OpStr := '=';
    end;
    Result := Format('(%s %s %s)', [TranslateExpressionToFilterText(Bin.Left), OpStr, TranslateExpressionToFilterText(Bin.Right)]);
  end
  else if Obj is TLogicalExpression then
  begin
    LogExpr := TLogicalExpression(Obj);
    case LogExpr.LogicalOperator of
      loAnd: OpStr := 'AND';
      loOr: OpStr := 'OR';
      else OpStr := 'AND';
    end;
    Result := Format('(%s %s %s)', [TranslateExpressionToFilterText(LogExpr.Left), OpStr, TranslateExpressionToFilterText(LogExpr.Right)]);
  end
  else if Obj is TUnaryExpression then
  begin
    Un := TUnaryExpression(Obj);
    case Un.UnaryOperator of
      uoNot:
        Result := 'NOT (' + TranslateExpressionToFilterText(Un.Expression) + ')';
      uoIsNull:
        Result := Un.PropertyName + ' IS NULL';
      uoIsNotNull:
        Result := Un.PropertyName + ' IS NOT NULL';
    end;
  end;
end;

procedure TEntityDataSet.SetFilterExpression(const Value: IExpression);
begin
  if FFilterExpression <> Value then
  begin
    FFilterExpression := Value;
    
    // Automatically translate the expression to standard Filter text 
    if FFilterExpression <> nil then
      Filter := TranslateExpressionToFilterText(FFilterExpression)
    else
      Filter := '';
      
    Filtered := (FFilterExpression <> nil) or (Filter <> '');
    
    if Active then
    begin
      ApplyFilterAndSort;
      Resync([]);
    end;
  end;
end;

procedure TEntityDataSet.SetDataProvider(const Value: TEntityDataProvider);
begin
  if FDataProvider <> Value then
  begin
    if FDataProvider <> nil then
    begin
      FDataProvider.RemoveFreeNotification(Self);
      FDataProvider.UnregisterDataSet(Self);
    end;

    FDataProvider := Value;

    if FDataProvider <> nil then
    begin
      FDataProvider.FreeNotification(Self);
      FDataProvider.RegisterDataSet(Self);
    end;
    
    if csDesigning in ComponentState then
      ClearResolvedEntityMetadata;
      
    ResolveEntityClassFromProvider;
  end;
end;

procedure TEntityDataSet.SetEntityClassName(const Value: string);
var
  Dict: TDictionary<string, Variant>;
begin
  if FEntityClassName <> Value then
  begin
    FEntityClassName := Value;
    
    if csDesigning in ComponentState then
    begin
      ClearResolvedEntityMetadata;
      FTableName := ''; // Força o preenchimento do TableName da nova classe
      FItems := nil;    // Explode o cache de preview antigo
      
      // Delegated to GenerateFields(ARemoveOrphans = True) to safely manage Fields list
      // without ripping underlying persistent fields prematurely.

      Active := False;  // Fecha o dataset para resetar buffers
      FieldDefs.Clear;
      FEntityClass := nil;

      // Clear preview data from previous entity
      for Dict in FPreviewData do
        Dict.Free;
      SetLength(FPreviewData, 0);
      FIsDesignTimePreview := False;
    end;
      
    ResolveEntityClassFromProvider;

    if csDesigning in ComponentState then
    begin
      EnsureEntityMapResolved;
      if (FEntityMap <> nil) and (FTableName = '') then
        FTableName := FEntityMap.TableName;
      GenerateFields(True, True, True); // AWipeAll=True, ARemoveOrphans=True, AUpdateExisting=True

      // Note: Auto-activation removed to satisfy design-time stability and prevent DFM pollution.
      // Users should manually activate to see design-time data.
    end;
  end;
end;

function TEntityDataSet.GetMasterSource: TDataSource;
begin
  if FMasterLink <> nil then
    Result := FMasterLink.DataSource
  else
    Result := nil;
end;

procedure TEntityDataSet.SetMasterSource(Value: TDataSource);
begin
  if GetMasterSource <> Value then
  begin
    if Value = nil then
    begin
      if FMasterLink <> nil then
        FMasterLink.DataSource := nil;
    end
    else
    begin
      if FMasterLink = nil then
        FMasterLink := TEntityMasterDataLink.Create(Self);
      FMasterLink.DataSource := Value;
      FMasterLink.FieldNames := FMasterFields;
    end;
    SyncMasterDetail;
  end;
end;

procedure TEntityDataSet.SetMasterFields(const Value: string);
begin
  if FMasterFields <> Value then
  begin
    FMasterFields := Value;
    if FMasterLink <> nil then
      FMasterLink.FieldNames := Value;
    SyncMasterDetail;
  end;
end;

procedure TEntityDataSet.SyncMasterDetail;
var
  FilterStr: string;
  i: Integer;
  MasterField: TField;
  MasterFieldsList, DetailFieldsList: TArray<string>;
  Val: Variant;
  ValStr, S: string;
begin
  if not (Active or FIsCursorOpen or FIsDesignTimePreview) or (FMasterLink = nil) or (FMasterLink.DataSource = nil) or
     (FMasterLink.DataSource.DataSet = nil) or (FMasterFields = '') or (FIndexFieldNames = '') then
  begin
    if csDesigning in ComponentState then
      Filter := '';
    Exit;
  end;

  if (not FMasterLink.DataSource.DataSet.Active) or FMasterLink.DataSource.DataSet.IsEmpty then
  begin
    if csDesigning in ComponentState then
      Filter := ''
    else
    begin
       Filter := '1=0';
       Filtered := True;
    end;
    Exit;
  end;

  MasterFieldsList := FMasterFields.Split([';']);
  DetailFieldsList := FIndexFieldNames.Split([';']);
  FilterStr := '';
  
  for i := 0 to High(MasterFieldsList) do
  begin
    if i > High(DetailFieldsList) then Break;
    
    MasterField := FMasterLink.DataSource.DataSet.FindField(MasterFieldsList[i].Trim);
    if MasterField = nil then Continue;
    
    if FilterStr <> '' then FilterStr := FilterStr + ' AND ';
    
    Val := MasterField.Value;
    
    if VarIsNull(Val) then
      ValStr := 'NULL'
    // PROTEÇÃO MÁXIMA: Força ISO se campo é data, se valor é varDate ou se o nome do campo sugere data
    else if (MasterField.DataType in [ftDate, ftTime, ftDateTime]) or 
            (VarType(Val) = varDate) or 
            (SameText(MasterFieldsList[i].Trim, 'Date') or SameText(MasterFieldsList[i].Trim, 'DateTime')) then
    begin
      ValStr := '''' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Val) + '''';
    end
    else if (VarType(Val) = varString) or (VarType(Val) = varUString) or (VarType(Val) = varOleStr) then
    begin
      S := VarToStr(Val);
      S := S.Replace('''', '''''');
      ValStr := '''' + S + '''';
    end
    else if (VarType(Val) = varBoolean) then
      ValStr := BoolToStr(Val, True)
    else
      // Usa o separador decimal do sistema para garantir que o filtro 
      // use sempre o ponto como separador universal de máquina
      ValStr := VarToStr(Val).Replace(FormatSettings.DecimalSeparator, '.');
      
    FilterStr := FilterStr + DetailFieldsList[i].Trim + ' = ' + ValStr;
  end;
  
  if FilterStr <> '' then
  begin
    Filter := FilterStr;
    Filtered := True;
  end
  else
  begin
    Filter := '';
    Filtered := False;
  end;
end;

{ TEntityDataSet }

procedure TEntityDataSet.SetActive(Value: Boolean);
begin
  // Prevent grid flicker during design-time preview activation
  if (Value <> Active) and (csDesigning in ComponentState) then
  begin
    DisableControls;
    try
      inherited SetActive(Value);
    finally
      EnableControls;
    end;
  end
  else
    inherited SetActive(Value);
end;

procedure TEntityDataSet.InternalOpen;
var
  CalcSize: Integer;
  Dict: IDictionary<string, Variant>;
  i: Integer;
  ItemCount: Integer;
  LDef: TFieldDef;
  Offset: Integer;
  Pair: TPair<string, Variant>;
  PreviewList: IList<IDictionary<string, Variant>>;
  Row: TDictionary<string, Variant>;
  NestedField: TDataSetField;
begin
  FIsCursorOpen := True;
  FIsDesignTimePreview := False;

  if (FEntityClass = nil) or (csDesigning in ComponentState) then
    ResolveEntityClassFromProvider;

  if (FEntityClassName <> '') and (csDesigning in ComponentState) then
    EnsureEntityMapResolved;

  if Assigned(FDataProvider) and (FDataProvider.DatabaseConnection <> nil) then
  begin
    // We allow FireDAC to handle AutoConnect if configured
  end;

  // Design-time preview: load data for grid display
  if (csDesigning in ComponentState) and
     ((FItems = nil) or (FItems.Count = 0)) and
     Assigned(FDataProvider) then
  begin
      // Limpar se for ownership
      if FOwnsItems and (FItems <> nil) then
        FItems := nil;

      // Try RTTI path first (works when entity class is compiled in the IDE)
      FItems := FDataProvider.CreatePreviewItems(FEntityClassName, 50);
      FOwnsItems := True;

      // If RTTI path failed, fall back to direct SQL dictionary approach
      // This enables preview even without the entity class compiled
      if (FItems = nil) or (FItems.Count = 0) then
      begin
        for Row in FPreviewData do
           Row.Free;
        SetLength(FPreviewData, 0);

        PreviewList := FDataProvider.GetPreviewData(FEntityClassName, 50);
        if (PreviewList <> nil) and (PreviewList.Count > 0) then
        begin
          FIsDesignTimePreview := True;
          SetLength(FPreviewData, PreviewList.Count);
          for i := 0 to PreviewList.Count - 1 do
          begin
             Dict := PreviewList[i];
             Row := TDictionary<string, Variant>.Create(True, False, 0);
             for Pair in Dict do
               Row.Add(Pair.Key, Pair.Value);
             FPreviewData[i] := Row;
          end;
        end;
      end;
  end;

  if (FEntityClass = nil) and (not (csDesigning in ComponentState)) then
    raise Exception.Create('EntityClass must be defined before opening TEntityDataSet.');

  // Build FieldDefs and create Fields
  if FieldDefs.Count = 0 then
    BuildFieldDefs;

  // Synchronize only calculated/lookup persistent fields.
  // Data fields must come from EntityMap metadata.
  for i := 0 to Fields.Count - 1 do
  begin
    if (FieldDefs.IndexOf(Fields[i].FieldName) < 0) and
       (Fields[i].FieldKind in [fkCalculated, fkLookup, fkInternalCalc]) then
    begin
      LDef := FieldDefs.AddFieldDef;
      LDef.Name := Fields[i].FieldName;
      LDef.DataType := Fields[i].DataType;
      LDef.Size := Fields[i].Size;
    end;
  end;

  // Remove stale persistent data fields not present in current metadata
  // (e.g. old navigation fields created in prior versions).
  i := 0;
  while i < Fields.Count do
  begin
    if (Fields[i].FieldKind = fkData) and (FieldDefs.IndexOf(Fields[i].FieldName) < 0) and
       (Fields[i].Owner = Owner) then
    begin
      Fields[i].DataSet := nil;
      Fields[i].Free;
      Continue;
    end;
    Inc(i);
  end;

  if FieldCount = 0 then
    CreateFields;

  // IMPORTANT: Delphi's CreateFields skips ftDataSet FieldDefs when ChildDefs.Count = 0
  // (ObjectFieldTypes rule in Data.DB.pas). We must create TDataSetField explicitly
  // for collection navigation properties ([HasMany], [ManyToMany]).
  for i := 0 to FieldDefs.Count - 1 do
  begin
    if (FieldDefs[i].DataType = ftDataSet) and (FindField(FieldDefs[i].Name) = nil) then
    begin
      LDef := FieldDefs[i];
      NestedField := TDataSetField.Create(Self);
      NestedField.FieldName := LDef.Name;
      NestedField.DataSet := Self;
    end;
  end;

  // Apply metadata (labels, formats, etc) to fields (persistent or dynamic)
  ApplyMapMetadataToFields;

  // Design-time preview: populate virtual index from preview data
  // Calcular tamanho necessário para campos calculados
  CalcSize := 0;
  FCalcOffsets.Clear;
  for i := 0 to Fields.Count - 1 do
  begin
    if Fields[i].FieldKind in [fkCalculated, fkLookup, fkInternalCalc] then
    begin
       Offset := SizeOf(TEntityRecordHeader) + CalcSize + 1;
       FCalcOffsets.Add(Fields[i].FieldName, Offset);
       Inc(CalcSize, Fields[i].DataSize + 1);
    end;
  end;

  FCalcAreaSize := CalcSize;
  FRecordSize := SizeOf(TEntityRecordHeader) + FCalcAreaSize;
  
  ItemCount := 0;
  if FIsDesignTimePreview then
    ItemCount := Length(FPreviewData)
  else if Assigned(FItems) then
    ItemCount := FItems.Count;

  SetLength(FInternalCalcStorage, Max(0, ItemCount));
  for i := 0 to High(FInternalCalcStorage) do FInternalCalcStorage[i] := nil;

  FCurrentRec := -1;
  BindFields(True);
  ApplyMapMetadataToFields;

  // Now that fields are bound and ready, sync and filter
  SyncMasterDetail;
  ApplyFilterAndSort;
end;


procedure TEntityDataSet.InternalClose;
var
  Dict: TDictionary<string, Variant>;
  Pair: TPair<string, TDataSet>;
begin
  if Assigned(FInsertObj) then
  begin
    FInsertObj.Free;
    FInsertObj := nil;
  end;
  FIsCursorOpen := False;
  FVirtualIndex.Clear;

  // Clear design-time preview data
  FIsDesignTimePreview := False;
  for Dict in FPreviewData do
    Dict.Free;
  SetLength(FPreviewData, 0);
  
  if (FDetailDataSets <> nil) then
  begin
    for Pair in FDetailDataSets do
      Pair.Value.Close;
    FDetailDataSets.Clear;
  end;
  
  SetLength(FInternalCalcStorage, 0);
end;

procedure TEntityDataSet.InternalDelete;
var
  ActualRow: Integer;
  TargetIdx: Integer;
  TargetObj: TObject;
  IsTrackedInsert: Boolean;
  NewChange: TEntityChange;
  i: Integer;
  Collection: Dext.Collections.Base.ICollection;
  IsOwnedByList: Boolean;
begin
  if not Assigned(FItems) then Exit;

  // 1. Usar exclusivamente a posição capturada no DoBeforeDelete (GetRecNo é 1-based)
  TargetIdx := FPositionBeforeAction - 1; 

  if (TargetIdx >= 0) and (TargetIdx < FVirtualIndex.Count) then
  begin
    // 2. Identificar o índice real na lista física
    ActualRow := FVirtualIndex[TargetIdx];
    
    TargetObj := FItems[ActualRow];
    IsTrackedInsert := False;
    if FTrackedChanges <> nil then
    begin
      for i := FTrackedChanges.Count - 1 downto 0 do
      begin
        if FTrackedChanges[i].Entity = TargetObj then
        begin
          if FTrackedChanges[i].State = ersInserted then
            IsTrackedInsert := True;
          FTrackedChanges.Delete(i);
        end;
      end;

      if not IsTrackedInsert then
      begin
        NewChange.State := ersDeleted;
        NewChange.Entity := TargetObj;
        NewChange.OriginalIndex := ActualRow;
        NewChange.Key := GetEntityKeys(TargetObj);
        NewChange.DirtyFields := nil;
        NewChange.OriginalValues := nil;
        FTrackedChanges.Add(NewChange);
      end;
    end;

    // 3. Remover das listas
    FVirtualIndex.RemoveAt(TargetIdx);

    // If it was created by the dataset, remove from created tracking
    if (FDataSetCreatedItems <> nil) and (TargetObj <> nil) then
      FDataSetCreatedItems.Extract(TargetObj);

    // Determine if the backing physical list owns its elements
    IsOwnedByList := False;
    if Supports(FItems, Dext.Collections.Base.ICollection, Collection) then
      IsOwnedByList := Collection.OwnsObjects;

    if TargetObj <> nil then
    begin
      // If the backing list owns its elements, extracting avoids freeing the instance immediately.
      // We store it in FDeletedItemsCache so it can be restored on RejectChanges,
      // or freed on AcceptChanges / Destroy.
      if IsOwnedByList and (not IsTrackedInsert) then
      begin
        RemoveFromItems(TargetObj, False);
        if FDeletedItemsCache <> nil then
          FDeletedItemsCache.Add(TargetObj);
      end
      else if IsOwnedByList and IsTrackedInsert then
      begin
        // Inserted then deleted: free immediately
        RemoveFromItems(TargetObj, True);
      end
      else
      begin
        // Backing list does not own objects.
        // Just remove from list (lifetime is managed by the external caller).
        RemoveFromItems(TargetObj, False);
      end;
    end;

    // 4. Reconstruir a visão virtual (necessário se houver filtros ou sorteio ativos)
    ApplyFilterAndSort;

    // 5. Estratégia de Reposicionamento para o Delphi TDataSet:
    // O TDataSet executa UpdateCursorPos e Resync nativamente após o InternalDelete.
    // Setando FCurrentRec em TargetIdx - 1, o framework fará o Next para TargetIdx.
    // Como os registros subiram para ocupar a vaga deletada, o sucessor agora é o novo TargetIdx.
    if FVirtualIndex.Count = 0 then
      FCurrentRec := -1
    else
    if TargetIdx <= FVirtualIndex.Count then
      FCurrentRec := TargetIdx
    else
      FCurrentRec := FVirtualIndex.Count;
    // NOTE: We do NOT call Resync([]); here. The base TDataSet manages this event
    // immediately after InternalDelete, ensuring the cursor lands on the correct record.
  end;
end;

procedure TEntityDataSet.InternalPost;
var
  Header: PEntityRecordHeader;
  NewIdx: Integer;
  PhysicalIdx: Integer;
  TargetIdx: Integer;
  TargetPos: Integer;
  NewChange: TEntityChange;
  CurrentObj: TObject;
  AlreadyTracked: Boolean;
  ExistingChange: TEntityChange;
  FieldName: string;
  FieldExists: Boolean;
  i: Integer;
  j: Integer;
begin
  if State = dsInsert then
  begin
    if Assigned(FInsertObj) then
    begin
      // 1. Decide between Add (Append) or Insert at position (Insert)
      if FIsAppending then
      begin
        FItems.Add(FInsertObj);
        NewIdx := FItems.Count -1;
      end
      else
      begin
        // Adjust 1-based RecNo to 0-based index or use the current virtual position
        TargetPos := FPositionBeforeAction;

        if (TargetPos < 0) or (FVirtualIndex.Count = 0) then
          TargetIdx := 0
        else if (TargetPos >= FVirtualIndex.Count) then
          TargetIdx := FItems.Count
        else
          // In Insert mode, use the physical index pointed by the virtual view at the position stored in DoBeforeInsert
          TargetIdx := FVirtualIndex[TargetPos];

        if TargetIdx > FItems.Count then
        begin
          FItems.Add(FInsertObj);
          NewIdx := FItems.Count - 1;
        end
        else
        begin
          FItems.Insert(TargetIdx, FInsertObj);
          NewIdx := TargetIdx;
        end;
      end;

      if (FCalcAreaSize > 0) and (NewIdx >= 0) and (NewIdx < FItems.Count) then
      begin
        if NewIdx >= Length(FInternalCalcStorage) then 
          SetLength(FInternalCalcStorage, FItems.Count + 10);
        SetLength(FInternalCalcStorage[NewIdx], FCalcAreaSize);
        Move(PByte(NativeInt(ActiveBuffer) + SizeOf(TEntityRecordHeader))^, FInternalCalcStorage[NewIdx][0], FCalcAreaSize);
      end;

      FInsertObjRef := FInsertObj;
      FInsertObj := nil;
      FIsAppending := False;
      FPositionBeforeAction := -2;

      // Track dataset-created objects so they are freed on Destroy
      // even when FOwnsItems=False (external list does not own new items).
      if (FDataSetCreatedItems <> nil) and FItemsIsNonOwningWrapper then
        FDataSetCreatedItems.Add(FInsertObjRef);

      // 2. Update Virtual View and track new object
      if FTrackedChanges <> nil then
      begin
        NewChange.State := ersInserted;
        NewChange.Entity := FInsertObjRef;
        NewChange.Key := nil;
        NewChange.DirtyFields := nil;
        FTrackedChanges.Add(NewChange);
      end;
      ApplyFilterAndSort(Filtered, FInsertObjRef);
      FInsertObjRef := nil;

      // 3. Position cursor on the new item
      // 4. Reset tracking state if context is present
      if FDbContext <> nil then
        FDbContext.ChangeTracker.Track(FInsertObj, esUnchanged);

      // 5. Notificar mudança
      DataEvent(deDataSetChange, 0);
    end;
  end
  else if State = dsEdit then
  begin
    Header := PEntityRecordHeader(ActiveBuffer);
    if (Header <> nil) and (Header.BookmarkIndex >= 0) and
      (Header.BookmarkIndex < FVirtualIndex.Count) then
    begin
      PhysicalIdx := FVirtualIndex[Header.BookmarkIndex];
      if FCalcAreaSize > 0 then
      begin
        if PhysicalIdx >= Length(FInternalCalcStorage) then 
          SetLength(FInternalCalcStorage, PhysicalIdx + 10);
        SetLength(FInternalCalcStorage[PhysicalIdx], FCalcAreaSize);
        Move(PByte(NativeInt(ActiveBuffer) + SizeOf(TEntityRecordHeader))^,
          FInternalCalcStorage[PhysicalIdx][0], FCalcAreaSize);
      end;

      CurrentObj := FItems[PhysicalIdx];
      if (FTrackedChanges <> nil) and (FCurrentDirtyFields.Count > 0) then
      begin
        AlreadyTracked := False;
        for i := 0 to FTrackedChanges.Count - 1 do
        begin
          if FTrackedChanges[i].Entity = CurrentObj then
          begin
            AlreadyTracked := True;
            if FTrackedChanges[i].State = ersModified then
            begin
              ExistingChange := FTrackedChanges[i];
              for FieldName in FCurrentDirtyFields do
              begin
                FieldExists := False;
                for j := 0 to High(ExistingChange.DirtyFields) do
                begin
                  if SameText(ExistingChange.DirtyFields[j], FieldName) then
                  begin
                    FieldExists := True;
                    Break;
                  end;
                end;
                if not FieldExists then
                begin
                  SetLength(ExistingChange.DirtyFields,
                    Length(ExistingChange.DirtyFields) + 1);
                  ExistingChange.DirtyFields[
                    High(ExistingChange.DirtyFields)] := FieldName;
                end;
              end;
              FTrackedChanges[i] := ExistingChange;
            end;
            Break;
          end;
        end;

        if not AlreadyTracked then
        begin
          NewChange.State := ersModified;
          NewChange.Entity := CurrentObj;
          NewChange.Key := GetEntityKeys(CurrentObj);
          SetLength(NewChange.DirtyFields, FCurrentDirtyFields.Count);
          for i := 0 to FCurrentDirtyFields.Count - 1 do
            NewChange.DirtyFields[i] := FCurrentDirtyFields[i];
          FTrackedChanges.Add(NewChange);
        end;
      end;
      FCurrentDirtyFields.Clear;
    end;
    ApplyFilterAndSort;
  end;
end;

procedure TEntityDataSet.InternalCancel;
begin
  if (State = dsInsert) and (FInsertObj <> nil) then
  begin
    FInsertObj.Free;
    FInsertObj := nil;
  end;
end;

procedure TEntityDataSet.InternalEdit;
begin
  // No-op.
end;

procedure TEntityDataSet.DoBeforeScroll;
begin
  inherited DoBeforeScroll;
end;

procedure TEntityDataSet.DoAfterScroll;
var
  Pair: TPair<string, TDataSet>;
begin
  inherited DoAfterScroll;
  
  if (FDetailDataSets <> nil) and (FDetailDataSets.Count > 0) then
  begin
    for Pair in FDetailDataSets do
    begin
        // Only refresh if the detail dataset exists and we logic can update it.
        SyncDetailData(Pair.Key, Pair.Value);
    end;
  end;
end;

procedure TEntityDataSet.DoBeforeInsert;
begin
  FPositionBeforeAction := GetRecNo - 1;
  inherited DoBeforeInsert;
end;

procedure TEntityDataSet.DoBeforeDelete;
begin
  FPositionBeforeAction := GetRecNo;
  inherited DoBeforeDelete;
end;

procedure TEntityDataSet.InternalInsert;
var
  Attr: TCustomAttribute;
  Context: TRttiContext;
  DetailField: TField;
  DetailFieldsList: TArray<string>;
  EntityType: TRttiType;
  i: Integer;
  MasterDS: TDataSet;
  MasterField: TField;
  MasterFieldsList: TArray<string>;
  NewList: TValue;
  NewObj: TObject;
  Prop: TRttiProperty;
  TargetType: PTypeInfo;
  Value: TValue;
begin
  inherited InternalInsert;
  if FInsertObj <> nil then
  begin
    FInsertObj.Free;
    FInsertObj := nil;
  end;
  
  NewObj := CreateNewEntity;
  if NewObj = nil then
    raise Exception.Create('Auto-append needs a parameterless constructor for ' + FEntityClass.ClassName);

  try
    // 1. Tenta herdar o ID do mestre se houver MasterLink
    if FMasterDataSet <> nil then
      SetMasterInheritance(NewObj);

    // 2. Garantir que listas internas estejam inicializadas para não quebrar o Nested DataSet
    Context := TReflection.Context;
    EntityType := Context.GetType(FEntityClass);
    if EntityType <> nil then
    begin
      for Prop in EntityType.GetProperties do
      begin
        if TActivator.IsListType(Prop.PropertyType.Handle) then
        begin
          Value := Prop.GetValue(NewObj);
          if Value.IsEmpty or (Value.Kind = tkUnknown) then
          begin
            TargetType := Prop.PropertyType.Handle;
            for Attr in Prop.GetAttributes do
              if Attr is InjectAttribute then
              begin
                if InjectAttribute(Attr).TargetTypeInfo <> nil then
                  TargetType := PTypeInfo(InjectAttribute(Attr).TargetTypeInfo);
                Break;
              end;
            
            try
              NewList := TActivator.CreateInstance(nil, TargetType);
              if not NewList.IsEmpty then
                Prop.SetValue(NewObj, NewList);
            except
              on E: Exception do
              begin
                raise EEntityDataSetException.Create(E.Message + sLineBreak +
                  'Tip: Register the implementation for this interface using TActivator.RegisterDefault ' +
                  'or in your Application Service DataProvider (DI Container) for property ' +
                  FEntityClass.ClassName + '.' + Prop.Name);
              end;
            end;
          end;
        end;
      end;
    end;
    
    // Sucesso
    FInsertObj := NewObj;
  except
    on E: Exception do
    begin
      NewObj.Free;
      raise;
    end;
  end;

  if (Pointer(ActiveBuffer) <> nil) then
  begin
    // Set virtual control flags for the new insertion buffer
    PEntityRecordHeader(Pointer(ActiveBuffer)).BookmarkIndex := -2; 
    PEntityRecordHeader(Pointer(ActiveBuffer)).BookmarkFlag := bfInserted;

    // NOVO: No mestre-detalhe (CLÁSSICO ou ANINHADO), herdar valores do mestre agora mesmo
    MasterDS := nil;
    if (FMasterLink <> nil) and (FMasterLink.DataSource <> nil) then
      MasterDS := FMasterLink.DataSource.DataSet
    else if FMasterDataSet <> nil then
      MasterDS := FMasterDataSet;

    if (MasterDS <> nil) and (MasterDS.Active) and
       (FMasterFields <> '') and (FIndexFieldNames <> '') then
    begin
      MasterFieldsList := FMasterFields.Split([';']);
      DetailFieldsList := FIndexFieldNames.Split([';']);
      for i := 0 to High(MasterFieldsList) do
      begin
        if i > High(DetailFieldsList) then Break;
        MasterField := MasterDS.FindField(MasterFieldsList[i].Trim);
        DetailField := FindField(DetailFieldsList[i].Trim);
        if (MasterField <> nil) and (DetailField <> nil) then
          DetailField.Value := MasterField.Value;
      end;
    end;
  end;
end;

procedure TEntityDataSet.InternalAddRecord(Buffer: TRecBuf; Append: Boolean);
begin
  FIsAppending := Append;
  InternalPost;
end;

procedure TEntityDataSet.InternalFirst;
begin
  FCurrentRec := -1;
end;

procedure TEntityDataSet.InternalLast;
begin
  FCurrentRec := FVirtualIndex.Count;
end;

procedure TEntityDataSet.GenerateFields(AWipeAll: Boolean = False; ARemoveOrphans: Boolean = True; AUpdateExisting: Boolean = True);
var
  i, j, k, Idx: Integer;
  Field, ExistingField, CurrentField: TField;
  Existing: TComponent;
  LPropMap: TPropertyMap;
  TargetName: string;
  EntityType: TFieldType;
  ProcessedFields: TStringList;
  IsNewField: Boolean;
begin
  ClearResolvedEntityMetadata;
  EnsureEntityMapResolved;
  if FEntityMap = nil then Exit;

  ProcessedFields := TStringList.Create;
  try
    ProcessedFields.CaseSensitive := False;
    ProcessedFields.Sorted := True;
    ProcessedFields.Duplicates := dupIgnore;

    DisableControls;
    try
      if Active then
        Close;

      if AWipeAll then
      begin
        while FieldCount > 0 do
        begin
          Field := Fields[0];
          Field.DataSet := nil;
          Field.Free;
        end;
      end;

      for i := 0 to FEntityMap.OrderedProperties.Count - 1 do
      begin
        LPropMap := FEntityMap.OrderedProperties[i];
        if LPropMap.IsIgnored then Continue;
        
        // Skip navigation properties that are not collections
        if LPropMap.IsNavigation and (LPropMap.Relationship in [rtManyToOne, rtOneToOne]) then
          Continue;

        EntityType := LPropMap.DataType;
        if (EntityType = ftUnknown) and LPropMap.IsNavigation then
          EntityType := ftDataSet;

        if EntityType = ftUnknown then Continue;

        ProcessedFields.Add(LPropMap.PropertyName);
        
        // 1. Try to find the field in the dataset's current field list
        Field := FindField(LPropMap.PropertyName);

        // 2. If not found in dataset, search owner's components for a field with same FieldName
        if (Field = nil) and (Owner <> nil) then
        begin
          for j := 0 to Owner.ComponentCount - 1 do
          begin
            if (Owner.Components[j] is TField) and (TField(Owner.Components[j]).FieldName = LPropMap.PropertyName) then
            begin
              if (TField(Owner.Components[j]).DataSet = nil) or (TField(Owner.Components[j]).DataSet = Self) then
              begin
                Field := TField(Owner.Components[j]);
                Field.DataSet := Self;
                Break;
              end;
            end;
          end;
        end;

        if (Field <> nil) and (Field.ClassType <> DefaultFieldClasses[EntityType]) then
        begin
          Field.DataSet := nil;
          Field.Free;
          Field := nil;
        end;

        IsNewField := False;
        if Field = nil then
        begin
          IsNewField := True;
          Field := DefaultFieldClasses[EntityType].Create(Owner);
          Field.FieldName := LPropMap.PropertyName;
          
          ExistingField := FindField(LPropMap.PropertyName);
          if ExistingField <> nil then
          begin
             Field.Free;
             Field := ExistingField;
             IsNewField := False;
          end
          else
            Field.DataSet := Self;

          if Self.Name <> '' then
          begin
            TargetName := Self.Name + LPropMap.PropertyName;
            if Owner <> nil then
            begin
              Existing := Owner.FindComponent(TargetName);
              if (Existing <> nil) and (Existing <> Field) then
              begin
                if (Existing is TField) and (TField(Existing).DataSet = nil) then
                   Existing.Free 
                else
                   Existing.Name := ''; 
              end;
            end;
            try
              Field.Name := TargetName;
            except
              Field.Name := '';
            end;
          end;
        end;

        // Apply metadata updates
        if IsNewField or AUpdateExisting then
        begin
          Field.Index := i;

          if LPropMap.DisplayLabel <> '' then
            Field.DisplayLabel := LPropMap.DisplayLabel
          else if IsNewField then
            Field.DisplayLabel := LPropMap.PropertyName;

          if LPropMap.DisplayWidth > 0 then
            Field.DisplayWidth := LPropMap.DisplayWidth;

          // Navigation members should not pollute the main tabular grid by default.
          // Keep them in the dataset model, but hidden unless explicitly surfaced by custom code.
          if LPropMap.IsNavigation then
            Field.Visible := False
          else
            Field.Visible := LPropMap.Visible;
          Field.ReadOnly := LPropMap.IsReadOnly;
          Field.Required := LPropMap.IsRequired and (not LPropMap.IsAutoInc);

          if (Field is TNumericField) then
          begin
            if (LPropMap.DisplayFormat <> '') then
              TNumericField(Field).DisplayFormat := LPropMap.DisplayFormat;

            if LPropMap.Alignment = taLeftJustify then
              Field.Alignment := taRightJustify
            else
              Field.Alignment := LPropMap.Alignment;
          end
          else if (Field is TDateTimeField) and (LPropMap.DisplayFormat <> '') then
            TDateTimeField(Field).DisplayFormat := LPropMap.DisplayFormat
          else
            Field.Alignment := LPropMap.Alignment;

          if LPropMap.EditMask <> '' then
            Field.EditMask := LPropMap.EditMask;
            
          if (LPropMap.DataType in [ftString, ftWideString]) and (LPropMap.MaxLength > 0) then
            Field.Size := LPropMap.MaxLength;
        end;
      end;

      if ARemoveOrphans then
      begin
        k := 0;
        while k < FieldCount do
        begin
          CurrentField := Fields[k];
          if (CurrentField.Owner = Owner) and (not ProcessedFields.Find(CurrentField.FieldName, Idx)) then
          begin
            CurrentField.DataSet := nil;
            CurrentField.Free;
          end
          else
            Inc(k);
        end;
      end;
    finally
      EnableControls;
    end;
  finally
    ProcessedFields.Free;
  end;
end;

procedure TEntityDataSet.InternalInitFieldDefs;

  function MapTypeToFieldType(ATypeInfo: PTypeInfo; ADepth: Integer = 0): TFieldType;
  var
    InnerInfo: PTypeInfo;
    TypeName: string;
  begin
    if (ATypeInfo = nil) or (ADepth > 10) then Exit(ftUnknown);
    
    // Check for Proxy<T>, Lazy<T>, etc using centralized Reflection
    if TReflection.IsSmartProp(ATypeInfo) then
    begin
      InnerInfo := TReflection.GetUnderlyingType(ATypeInfo);
      if (InnerInfo <> nil) and (InnerInfo <> ATypeInfo) then
        Exit(MapTypeToFieldType(InnerInfo, ADepth + 1));
    end;

    case ATypeInfo^.Kind of
      tkInteger, tkEnumeration:
      begin
        TypeName := string(ATypeInfo^.Name);
        if (ATypeInfo = TypeInfo(Boolean)) or (TypeName = 'Boolean') or (TypeName = 'WordBool') or (TypeName = 'ByteBool') or (TypeName = 'LongBool') then
          Exit(ftBoolean)
        else if SameText(TypeName, 'SmallInt') then
          Exit(ftSmallint)
        else if SameText(TypeName, 'Byte') then
          Exit(ftByte)
        else if SameText(TypeName, 'ShortInt') then
          Exit(ftShortint)
        else if SameText(TypeName, 'Word') then
          Exit(ftWord)
        else
          Exit(ftInteger);
      end;
      tkFloat:
      begin
        TypeName := string(ATypeInfo^.Name);
        if (ATypeInfo = TypeInfo(TDateTime)) or SameText(TypeName, 'TDateTime') or SameText(TypeName, 'TDate') or SameText(TypeName, 'TTime') then
          Exit(ftDateTime)
        else if (ATypeInfo = TypeInfo(Currency)) or SameText(TypeName, 'Currency') then
          Exit(ftCurrency)
        else
        begin
          Exit(ftFloat);
        end;
      end;
      tkString, tkLString, tkWString, tkUString, tkChar, tkWChar:
        Exit(ResolveTextFieldType);
      tkInt64:
        Exit(ftLargeint);
      tkVariant:
        Exit(ftVariant);
      tkRecord, tkInterface:
      begin
        InnerInfo := TReflection.GetUnderlyingType(ATypeInfo);
        if (InnerInfo <> nil) and (InnerInfo <> ATypeInfo) then
          Exit(MapTypeToFieldType(InnerInfo, ADepth + 1))
        else
        begin
          TypeName := string(ATypeInfo^.Name);
          if (TypeName.StartsWith('IList<') or TypeName.StartsWith('IEnumerable<')) then
            Exit(ftDataSet);
            
          Exit(ftUnknown);
        end;
      end;
    else
      Exit(ftUnknown);
    end;
  end;

  function IsTBytesType(ATypeInfo: PTypeInfo): Boolean;
  begin
    Result := (ATypeInfo <> nil) and (ATypeInfo.Kind = tkDynArray) and
              (ATypeInfo = TypeInfo(TBytes));
  end;

var
  FieldDef: TFieldDef;
  Prop: TRttiProperty;
  LPropMap: TPropertyMap;
  ResolvedType: TFieldType;
  RttiField: TRttiField;
  RttiType: TRttiType;
  i: Integer;
begin
  EnsureEntityMapResolved;
  if (FEntityMap = nil) then Exit;

  // Em runtime precisamos da classe, em design o EntityMap (do Parser) basta
  if (FEntityClass = nil) and (not (csDesigning in ComponentState)) then Exit;

  FieldDefs.Clear;

  // Use centralized RTTI context
  RttiType := nil;
  if FEntityClass <> nil then
    RttiType := TReflection.Context.GetType(FEntityClass);

    for i := 0 to FEntityMap.OrderedProperties.Count - 1 do
    begin
      LPropMap := FEntityMap.OrderedProperties[i];
      if LPropMap.IsIgnored then Continue;
      
      // Skip navigation properties that are not collections (BelongsTo/OneToOne) 
      // as they are handled by references, not direct columns in the dataset
      if LPropMap.IsNavigation and (LPropMap.Relationship in [rtManyToOne, rtOneToOne]) then Continue;
      
      // Shadow property check
      if LPropMap.IsShadow and (not FIncludeShadowProperties) then Continue;

      // Calcular resolved type dinamicamente
      ResolvedType := LPropMap.DataType;

      // Always try to resolve RTTI Prop/Field for attribute discovery and type fallback
      if (RttiType <> nil) then
      begin
        Prop := RttiType.GetProperty(LPropMap.PropertyName);
        if (Prop <> nil) and (ResolvedType = ftUnknown) then
        begin
          if IsTBytesType(Prop.PropertyType.Handle) then
            ResolvedType := ftBlob
          else
            ResolvedType := MapTypeToFieldType(Prop.PropertyType.Handle);
        end;

        if (Prop = nil) or (ResolvedType = ftUnknown) or
           (LPropMap.FieldValueOffset <= 0) then
        begin
           // Search for field directly, then with F prefix, then normalized, then normalized with F
           RttiField := RttiType.GetField(LPropMap.PropertyName);
           if RttiField = nil then RttiField := RttiType.GetField('F' + LPropMap.PropertyName);
           if RttiField = nil then RttiField := RttiType.GetField(TReflection.NormalizeFieldName(LPropMap.PropertyName));
           if RttiField = nil then RttiField := RttiType.GetField('F' + TReflection.NormalizeFieldName(LPropMap.PropertyName));

           // NEW: Special case for Lazy fields that might not have the F prefix in the map but have it in the class
           if (RttiField = nil) and (not LPropMap.PropertyName.StartsWith('F', True)) then
             RttiField := RttiType.GetField('F' + LPropMap.PropertyName);

           if RttiField <> nil then
           begin
              if ResolvedType = ftUnknown then
              begin
                if IsTBytesType(RttiField.FieldType.Handle) then
                  ResolvedType := ftBlob
                else
                  ResolvedType := MapTypeToFieldType(RttiField.FieldType.Handle);
              end;

              // Update FieldOffset if not yet set
              if LPropMap.FieldValueOffset <= 0 then
                LPropMap.FieldValueOffset := RttiField.Offset;
           end;
        end;
      end;

      // Se ainda for desconhecido e houver PTypeInfo no map
      if (ResolvedType = ftUnknown) and Assigned(LPropMap.PropertyType) then
        ResolvedType := MapTypeToFieldType(LPropMap.PropertyType);

      // CRITICAL: Persist resolved type back into PropMap
      if (ResolvedType in [ftString, ftWideString]) and (LPropMap.MaxLength > 255) then
        ResolvedType := ftMemo;

      if (LPropMap.DataType = ftUnknown) and (ResolvedType <> ftUnknown) then
        LPropMap.DataType := ResolvedType;

      // Habilita suporte a ftDataSet para coleções de navegação
      if LPropMap.IsNavigation and (LPropMap.Relationship in [rtOneToMany, rtManyToMany]) then
        ResolvedType := ftDataSet;

      if (ResolvedType = ftUnknown) and LPropMap.IsNavigation then
        ResolvedType := ftDataSet;

      // Ensure shadow property has a type if unknown (default to string)
      if (LPropMap.IsShadow) and (ResolvedType = ftUnknown) then
        ResolvedType := ftWideString;

      if ResolvedType = ftUnknown then Continue;

      // 1. Popular FieldDefs para metadados
      FieldDef := FieldDefs.AddFieldDef;
      FieldDef.Name := LPropMap.PropertyName;
      FieldDef.DataType := ResolvedType;
      if LPropMap.MaxLength > 0 then
        FieldDef.Size := LPropMap.MaxLength;
    end;
end;

procedure TEntityDataSet.SyncDetailData(const AFieldName: string; ADetailDataSet: TDataSet);
var
  Attr: TCustomAttribute;
  Intf: IInterface;
  ItemClass: TClass;
  List: IObjectList;
  NewListVal: TValue;
  Obj: TObject;
  Prop: TRttiProperty;
  TargetType: PTypeInfo;
  Val: TValue;
begin
  if not (ADetailDataSet is TEntityDataSet) then Exit;

  // DESIGN-TIME SAFETY: Em design não tentamos sincronizar RTTI/Instâncias se não houver classe compilada
  if (csDesigning in ComponentState) and (FEntityClass = nil) then Exit;

  // Now populate it with data from the current record
  List := nil;
  Obj := GetCurrentObject;
    if Obj <> nil then
  begin
    Val := TReflection.GetValue(Obj, AFieldName);
    if Val.IsEmpty or (Val.Kind = tkUnknown) then
    begin
       // Se a lista no mestre está nula (mestre novo), vamos instanciá-la agora!
       Prop := GetProperty(AFieldName);
       if (Prop <> nil) and TActivator.IsListType(Prop.PropertyType.Handle) then
       begin
         try
           TargetType := Prop.PropertyType.Handle;
           for Attr in Prop.GetAttributes do
             if Attr is InjectAttribute then
             begin
               if InjectAttribute(Attr).TargetTypeInfo <> nil then
                 TargetType := PTypeInfo(InjectAttribute(Attr).TargetTypeInfo);
               Break;
             end;

           NewListVal := TActivator.CreateInstance(nil, TargetType);
           if not NewListVal.IsEmpty then
           begin
             Prop.SetValue(Obj, NewListVal);
             Val := NewListVal;
           end;
         except
           on E: Exception do
             raise Exception.Create(E.Message + sLineBreak + sLineBreak +
               'Tip: Register the implementation for this interface using TActivator.RegisterDefault ' +
               'or in your Application Service DataProvider (DI Container).');
         end;
       end;
    end;

    if not Val.IsEmpty then
    begin
      if Val.IsType<IObjectList> then
        List := Val.AsType<IObjectList>
      else if Val.Kind = tkInterface then
      begin
        // Try to cast to IObjectList (compatible with TList<T>)
        Intf := Val.AsInterface;
        if Intf <> nil then
           Intf.QueryInterface(IObjectList, List);
      end;
    end;
  end;

  // Sempre carrega a lista (mesmo que nil ou vazia, mas agora instanciada se mestre presente)
  ItemClass := TEntityDataSet(ADetailDataSet).FEntityClass;
  if ItemClass = nil then
  begin
    Prop := GetProperty(AFieldName);
    if Prop <> nil then
      ItemClass := TReflection.GetCollectionItemType(Prop.PropertyType.Handle);
  end;

  TEntityDataSet(ADetailDataSet).Load(List, ItemClass, False);
end;

function TEntityDataSet.CreateNestedDataSet(DataSetField: TDataSetField): TDataSet;
begin
  Result := nil;
  if DataSetField = nil then Exit;

  // We need a detail dataset instance.
  // Check our cache first.
  if not FDetailDataSets.TryGetValue(DataSetField.FieldName, Result) then
  begin
    Result := TEntityDataSet.Create(Self);
    TEntityDataSet(Result).DbContext := FDbContext;
    TEntityDataSet(Result).IncludeShadowProperties := FIncludeShadowProperties;
    TEntityDataSet(Result).FMasterDataSet := Self;
    // Herdando mapeamentos de campos mestre se possível
    TEntityDataSet(Result).FIndexFieldNames := Self.FIndexFieldNames;
    TEntityDataSet(Result).FMasterFields := Self.FMasterFields;
    
    FDetailDataSets.Add(DataSetField.FieldName, Result);
  end;

  // Sync data
  SyncDetailData(DataSetField.FieldName, Result);
end;

procedure TEntityDataSet.ApplyAttributesToField(AField: TField; AContainer: TRttiObject);
var
  Attr: TCustomAttribute;
begin
  if (AField = nil) or (AContainer = nil) then Exit;
  for Attr in AContainer.GetAttributes do
  begin
    if Attr is CaptionAttribute then
      AField.DisplayLabel := CaptionAttribute(Attr).Value
    else if Attr is DisplayFormatAttribute then
    begin
      if AField is TNumericField then TNumericField(AField).DisplayFormat := DisplayFormatAttribute(Attr).Value
      else if AField is TDateTimeField then TDateTimeField(AField).DisplayFormat := DisplayFormatAttribute(Attr).Value;
    end
    else if Attr is AlignmentAttribute then
      AField.Alignment := AlignmentAttribute(Attr).Alignment
    else if Attr is EditMaskAttribute then
      AField.EditMask := EditMaskAttribute(Attr).Value
    else if Attr is DisplayWidthAttribute then
      AField.DisplayWidth := DisplayWidthAttribute(Attr).Value
    else if Attr is VisibleAttribute then
      AField.Visible := VisibleAttribute(Attr).Visible;
  end;
end;

procedure TEntityDataSet.ApplyMapMetadataToFields;
var
  Field: TField;
  LPropMap: TPropertyMap;
  RttiType: TRttiType;
  Prop: TRttiProperty;
  RttiField: TRttiField;
  i: Integer;
begin
  if FEntityMap = nil then Exit;
  if Fields.Count = 0 then Exit;

  RttiType := nil;
  if FEntityClass <> nil then
    RttiType := TReflection.Context.GetType(FEntityClass);

  for i := 0 to FEntityMap.OrderedProperties.Count - 1 do
  begin
    LPropMap := FEntityMap.OrderedProperties[i];
    if LPropMap.IsIgnored then Continue;
    
    Field := FindField(LPropMap.PropertyName);
    if Field = nil then Continue;

    // DisplayLabel / Caption
    if LPropMap.DisplayLabel <> '' then
      Field.DisplayLabel := LPropMap.DisplayLabel
    else
      Field.DisplayLabel := LPropMap.PropertyName;

    // Index (Order)
    Field.Index := i;

    // DisplayWidth
    if LPropMap.DisplayWidth > 0 then
      Field.DisplayWidth := LPropMap.DisplayWidth;

    // Keep string field length aligned with metadata (e.g. [MaxLength]).
    if (Field.DataType in [ftString, ftWideString]) and (LPropMap.MaxLength > 0) then
      Field.Size := LPropMap.MaxLength;

    // DisplayFormat (Numeric and DateTime)
    if LPropMap.DisplayFormat <> '' then
    begin
      if Field is TNumericField then
        TNumericField(Field).DisplayFormat := LPropMap.DisplayFormat
      else if Field is TDateTimeField then
        TDateTimeField(Field).DisplayFormat := LPropMap.DisplayFormat;
    end;
    // Do not force default numeric/currency DisplayFormat here.
    // FireDAC-like behavior relies on field type + locale (FormatSettings),
    // unless an explicit DisplayFormat is configured in metadata/attributes.

    // EditMask
    if LPropMap.EditMask <> '' then
      Field.EditMask := LPropMap.EditMask;

    // Alignment
    if LPropMap.Alignment <> taLeftJustify then
      Field.Alignment := LPropMap.Alignment;

    // Visible
    // Keep navigation properties hidden by default in the master grid.
    if LPropMap.IsNavigation then
      Field.Visible := False
    else
      Field.Visible := LPropMap.Visible;

    // Required / ReadOnly
    Field.Required := LPropMap.IsRequired and (not LPropMap.IsAutoInc);
    Field.ReadOnly := LPropMap.IsReadOnly or LPropMap.IsAutoInc;

    // Apply Attributes (if RTTI is available)
    if RttiType <> nil then
    begin
      Prop := RttiType.GetProperty(LPropMap.PropertyName);
      ApplyAttributesToField(Field, Prop);

      RttiField := RttiType.GetField(LPropMap.PropertyName);
      if RttiField = nil then RttiField := RttiType.GetField('F' + LPropMap.PropertyName);
      ApplyAttributesToField(Field, RttiField);
    end;

    // User-defined preparation (highest precedence)
    if Assigned(FOnPrepareField) then
      FOnPrepareField(Self, Field);
  end;
end;

procedure TEntityDataSet.BuildFieldDefs;
begin
  InternalInitFieldDefs;
end;

function TEntityDataSet.AllocRecordBuffer: TRecordBuffer;
begin
  Result := TRecordBuffer(AllocMem(FRecordSize));
  InternalInitRecord(TRecBuf(Result));
end;

procedure TEntityDataSet.FreeRecordBuffer(var Buffer: TRecordBuffer);
begin
  FreeMem(Pointer(Buffer));
  Buffer := nil;
end;

function TEntityDataSet.CreateNewEntity: TObject;
var
  RttiMethod: TRttiMethod;
  RttiType: TRttiType;
begin
  Result := nil;
  RttiType := TReflection.Context.GetType(FEntityClass);
  if RttiType <> nil then
  begin
    for RttiMethod in RttiType.GetMethods do
    begin
      // Busca constructor sem parâmetros
      if RttiMethod.IsConstructor and (Length(RttiMethod.GetParameters) = 0) then
      begin
        Result := RttiMethod.Invoke(FEntityClass, []).AsObject;
        Break;
      end;
    end;
  end;
end;

procedure TEntityDataSet.InternalInitRecord(Buffer: TRecBuf);
begin
  FillChar(Pointer(Buffer)^, FRecordSize, 0);
  PEntityRecordHeader(Pointer(Buffer)).BookmarkIndex := -2;
end;

procedure TEntityDataSet.CalculateFields(Buffer: TRecBuf);
var
  SaveState: TDataSetState;
begin
  SaveState := State;
  SetState(dsCalcFields);
  try
    inherited CalculateFields(Buffer);
  finally
    SetState(SaveState);
  end;
end;

procedure TEntityDataSet.GetBookmarkData(Buffer: TRecBuf; Data: TBookmark);
begin
  if Length(Data) < SizeOf(Integer) then
    SetLength(Data, SizeOf(Integer));
  PInteger(@Data[0])^ := PEntityRecordHeader(Pointer(Buffer)).BookmarkIndex;
end;

procedure TEntityDataSet.SetBookmarkData(Buffer: TRecBuf; Data: TBookmark);
begin
  if Length(Data) >= SizeOf(Integer) then
    PEntityRecordHeader(Pointer(Buffer)).BookmarkIndex := PInteger(@Data[0])^;
end;

procedure TEntityDataSet.InternalGotoBookmark(Bookmark: TBookmark);
begin
  if Length(Bookmark) >= SizeOf(Integer) then
    FCurrentRec := PInteger(@Bookmark[0])^;
end;

function TEntityDataSet.GetBookmarkFlag(Buffer: TRecBuf): TBookmarkFlag;
begin
  Result := PEntityRecordHeader(Pointer(Buffer)).BookmarkFlag;
end;

procedure TEntityDataSet.SetBookmarkFlag(Buffer: TRecBuf; Value: TBookmarkFlag);
begin
  PEntityRecordHeader(Pointer(Buffer)).BookmarkFlag := Value;
end;

procedure TEntityDataSet.InternalSetToRecord(Buffer: TRecBuf);
begin
  FCurrentRec := PEntityRecordHeader(Pointer(Buffer)).BookmarkIndex;
end;

function TEntityDataSet.GetRecordSize: Word;
begin
  Result := FRecordSize;
end;

function TEntityDataSet.GetRecordCount: Integer;
begin
  Result := FVirtualIndex.Count;
end;

function TEntityDataSet.GetRecNo: Integer;
begin
  CheckActive;
  if Pointer(ActiveBuffer) <> nil then
    Result := PEntityRecordHeader(Pointer(ActiveBuffer)).BookmarkIndex + 1
  else
    Result := FCurrentRec + 1;
end;

procedure TEntityDataSet.SetRecNo(Value: Integer);
begin
  CheckBrowseMode;
  Value := System.Math.Min(System.Math.Max(Value, 1), RecordCount);
  if RecNo <> Value then
  begin
    DoBeforeScroll;
    FCurrentRec := Value - 1;
    Resync([rmCenter]);
    DoAfterScroll;
  end;
end;

function TEntityDataSet.BookmarkValid(Bookmark: TBookmark): Boolean;
var
  Idx: Integer;
begin
  Result := False;
  if (Pointer(Bookmark) = nil) or (FVirtualIndex.Count = 0) then
    Exit;

  // In virtual datasets, the bookmark stores the logical index.
  Idx := PInteger(Pointer(Bookmark))^;
  Result := (Idx >= 0) and (Idx < FVirtualIndex.Count);
end;

function TEntityDataSet.GetRecord(Buffer: TRecBuf; GetMode: TGetMode; DoCheck: Boolean): TGetResult;
var
  Header: PEntityRecordHeader;
  PhysicalIdx: Integer;
begin
  if (csDesigning in ComponentState) and Active and Assigned(FDataProvider) then
  begin
    if (FDataProvider.DatabaseConnection <> nil) and (not FDataProvider.DatabaseConnection.Connected) then
    begin
       Active := False;
       Exit(grError);
    end;
  end;

  Header := PEntityRecordHeader(Pointer(Buffer));

  case GetMode of
    gmNext:
      begin
        if FCurrentRec < FVirtualIndex.Count - 1 then
        begin
          Inc(FCurrentRec);
          Result := grOK;
        end
        else
          Result := grEOF;
      end;
      
    gmPrior:
      begin
        if FCurrentRec >= 0 then
          Dec(FCurrentRec);
        if FCurrentRec < 0 then
          Result := grBOF
        else
          Result := grOK;
      end;
      
    gmCurrent:
      begin
        if (FCurrentRec < 0) or (FCurrentRec >= FVirtualIndex.Count) then
          Result := grError
        else
          Result := grOK;
      end;
  else
    Result := grError;
  end;

  if Result = grOK then
  begin
    Header.BookmarkIndex := FCurrentRec;
    Header.BookmarkFlag := bfCurrent;

    if (FCalcAreaSize > 0) and (FCurrentRec >= 0) and (FCurrentRec < FVirtualIndex.Count) then
    begin
      PhysicalIdx := FVirtualIndex[FCurrentRec];
      if (PhysicalIdx >= 0) and (PhysicalIdx < Length(FInternalCalcStorage)) and (Length(FInternalCalcStorage[PhysicalIdx]) > 0) then
         Move(FInternalCalcStorage[PhysicalIdx][0], PByte(NativeInt(Buffer) + SizeOf(TEntityRecordHeader))^, FCalcAreaSize);
    end;

    CalculateFields(TRecBuf(Buffer));
  end
  else if Result = grEOF then
  begin
    Header.BookmarkFlag := bfEOF;
  end
  else if Result = grBOF then
  begin
    Header.BookmarkFlag := bfBOF;
  end;
end;

// ---------------------------------------------------------------------------
//  ReadFieldValue - Core universal method: reads a property from the entity
// ---------------------------------------------------------------------------
function TEntityDataSet.ReadFieldValue(Field: TField; out Value: Variant): Boolean;
begin
  Result := ReadFieldValue(Field, ActiveBuffer, Value);
end;

function TEntityDataSet.ReadFieldValue(Field: TField; ABuffer: TRecBuf; out Value: Variant): Boolean;
var
  BlobData: TArray<Byte>;
  CurrentObj: TObject;
  Entry: IEntityEntry;
  FieldVal, LUnwrappedField: TValue;
  Header: PEntityRecordHeader;
  LP: PByte;
  Prop: TRttiProperty;
  LPropMap: TPropertyMap;
  PValue: Pointer;
  Row: TDictionary<string, Variant>;
  RowIdx: Integer;
  RttiField: TRttiField;
  RttiType: TRttiType;
  TempValue: TValue;
  Unwrapped: TValue;
  Val: TValue;
begin
  Result := False;
  Value := Unassigned;

  if not Active then Exit;
  Header := PEntityRecordHeader(Pointer(ABuffer));

  // DESIGN-TIME PREVIEW: Read from dictionary instead of object memory
  if FIsDesignTimePreview and (csDesigning in ComponentState) then
  begin
    RowIdx := -1;
    if (Header <> nil) and (Header.BookmarkIndex >= 0) and
       (Header.BookmarkIndex < Length(FPreviewData)) then
      RowIdx := Header.BookmarkIndex
    else if (FCurrentRec >= 0) and (FCurrentRec < Length(FPreviewData)) then
      RowIdx := FCurrentRec;

    if RowIdx >= 0 then
    begin
      Row := FPreviewData[RowIdx];
      if Row.TryGetValue(Field.FieldName, Value) then
        Result := not VarIsNull(Value)
      else
        Result := False;
    end;
    Exit;
  end;

  // 1. Identify target object
  CurrentObj := nil;
  
  if (Header <> nil) then
  begin
    if (Header.BookmarkIndex = -2) then
      CurrentObj := FInsertObj
    else if (Header.BookmarkIndex >= 0) and (Header.BookmarkIndex < FVirtualIndex.Count) then
      CurrentObj := FItems[FVirtualIndex[Header.BookmarkIndex]];
  end;

  // 2. Fallback to global cursor (programmatic Field.Value access or navigation outside the painting loop)
  if (CurrentObj = nil) and (FCurrentRec >= 0) and (FCurrentRec < FVirtualIndex.Count) then
  begin
     CurrentObj := FItems[FVirtualIndex[FCurrentRec]];
  end;

  if (CurrentObj = nil) or (FEntityMap = nil) then Exit;

  if not FEntityMap.Properties.TryGetValue(Field.FieldName, LPropMap) then
    Exit;

  // 3. Shadow Property support
  if LPropMap.IsShadow and (FDbContext <> nil) then
  begin
    Entry := FDbContext.Entry(CurrentObj);
    Value := Entry.Member(Field.FieldName).GetCurrentValue.AsVariant;
    Result := True;
    Exit;
  end;

  // 4. RTTI Fallback if field offset is not defined or is Lazy
  if (LPropMap.FieldValueOffset <= 0) or LPropMap.IsLazy then
  begin
    Prop := GetProperty(Field.FieldName);
    if Prop <> nil then
    begin
      TempValue := Prop.GetValue(CurrentObj);
      if TReflection.TryUnwrapProp(TempValue, Unwrapped) then
      begin
        if not Unwrapped.IsEmpty then
        begin
          if (Field.DataType in [ftDate, ftTime, ftDateTime]) then
             Value := VarAsType(Unwrapped.AsType<TDateTime>, varDate)
          else if (Field.DataType = ftCurrency) then
             Value := Unwrapped.AsCurrency
          else
             Value := Unwrapped.AsVariant;
        end;
      end
      else
      begin
        if (Field.DataType in [ftDate, ftTime, ftDateTime]) then
           Value := VarAsType(TempValue.AsType<TDateTime>, varDate)
        else if (Field.DataType = ftCurrency) then
           Value := TempValue.AsCurrency
        else
           Value := TempValue.AsVariant;
      end;
      Result := not VarIsEmpty(Value);
      Exit;
    end;

    // Last resort: RTTI Field
    RttiType := TReflection.Context.GetType(CurrentObj.ClassType);
    if RttiType <> nil then
    begin
      RttiField := RttiType.GetField(Field.FieldName);
      if RttiField <> nil then
      begin
        FieldVal := RttiField.GetValue(CurrentObj);
        if TReflection.TryUnwrapProp(FieldVal, LUnwrappedField) then
        begin
          if not LUnwrappedField.IsEmpty then
          begin
            if (Field.DataType in [ftDate, ftTime, ftDateTime]) then
               Value := VarAsType(LUnwrappedField.AsType<TDateTime>, varDate)
            else if (Field.DataType = ftCurrency) then
               Value := LUnwrappedField.AsCurrency
            else
               Value := LUnwrappedField.AsVariant;
          end;
        end
        else
        begin
          if (Field.DataType in [ftDate, ftTime, ftDateTime]) then
             Value := VarAsType(FieldVal.AsType<TDateTime>, varDate)
          else if (Field.DataType = ftCurrency) then
             Value := FieldVal.AsCurrency
          else
             Value := FieldVal.AsVariant;
        end;
        Result := not VarIsEmpty(Value);
        Exit;
      end;
    end;
  end;

  // 5. Direct value extraction (Fast Path)
  if (LPropMap.FieldOffset > 0) then
  begin
    LP := PByte(CurrentObj);
    Inc(LP, LPropMap.FieldOffset);
    if not PBoolean(LP)^ then
    begin
      Value := Null;
      Result := True;
      Exit;
    end;
  end;

  // Determine the pointer to the actual value
  // CRITICAL: Ensure we have a valid non-zero offset before direct memory access
  if LPropMap.FieldValueOffset > 0 then
  begin
    LP := PByte(CurrentObj);
    Inc(LP, LPropMap.FieldValueOffset);
    PValue := LP;
  end
  else if LPropMap.FieldOffset > 0 then
  begin
    LP := PByte(CurrentObj);
    Inc(LP, LPropMap.FieldOffset);
    PValue := LP;
  end
  else
    Exit(False); // Cannot read without offset or RTTI (handled before)

  if PValue = nil then Exit;

  case LPropMap.DataType of
    ftString, ftWideString, ftMemo, ftWideMemo:
      Value := PString(PValue)^;
    ftInteger:
      Value := PInteger(PValue)^;
    ftSmallint:
      Value := PSmallInt(PValue)^;
    ftShortint:
      Value := PShortInt(PValue)^;
    ftByte:
      Value := PByte(PValue)^;
    ftWord:
      Value := PWord(PValue)^;
    ftLargeint:
      Value := PInt64(PValue)^;
    ftDataSet:
    begin

       Value := TValue.From<TObject>(PObject(PValue)^).AsVariant;
    end;
    ftFloat, ftCurrency:
    begin
      // CRITICAL: We must use TValue.Make with the original PropertyType (PTypeInfo)
      // because types like 'Currency' have a unique 8-byte binary layout (scaled Int64)
      // that differs from standard 'Double' (IEEE 754). Using TValue ensures safe 
      // extraction from the object memory and correct conversion to a Variant type.
      if LPropMap.PropertyType <> nil then
      begin
        TValue.Make(PValue, LPropMap.PropertyType, Val);
        Value := Val.AsVariant;
      end
      else
      begin
        // Fallback to raw bit reading if TypeInfo is missing
        if LPropMap.DataType = ftCurrency then
          Value := PCurrency(PValue)^
        else
          Value := PDouble(PValue)^;
      end;
    end;
    ftBoolean:
      Value := PBoolean(PValue)^;
    ftDateTime, ftDate, ftTime:
      Value := VarAsType(PDateTime(PValue)^, varDate);
    ftBlob:
    begin
      try
        // PValue is Pointer, we need to cast to PBytes to dereference properly
        BlobData := PBytes(PValue)^;
        if Length(BlobData) > 0 then
        begin
          Value := True;
          Result := True;
          Exit;
        end;
      except
        // Safety for invalid pointers during stress/navigation
      end;
      Result := False;
      Exit;
    end;
  else
    Exit; // Type not directly mapped
  end;

  Result := not VarIsEmpty(Value);
end;

// ---------------------------------------------------------------------------
//  GetFieldData - Override with TValueBuffer (TArray<Byte>) for modern Delphi
//  This is the method TField.GetData actually calls (XE3+).
// ---------------------------------------------------------------------------
function TEntityDataSet.GetFieldData(Field: TField; Buffer: Pointer): Boolean;
var
  BufferPtr: Pointer;
  DateTimeValue: TDateTime;
  DoubleValue: Double;
  FloatValue: Double;
  Int64Value: Int64;
  Offset: Integer;
  P: PByte;
  V: Variant;
begin
  Result := False;
  if not Assigned(Field) then Exit;
  
  if Field.FieldKind in [fkCalculated, fkLookup, fkInternalCalc] then
  begin
    if Field.FieldKind = fkCalculated then
      BufferPtr := Pointer(CalcBuffer)
    else
      BufferPtr := Pointer(ActiveBuffer);

    if BufferPtr = nil then Exit;
    if not FCalcOffsets.TryGetValue(Field.FieldName, Offset) then Exit;
    
    // Check Null Flag (1 byte before data)
    P := PByte(BufferPtr);
    Inc(P, Offset - 1);
    
    if P^ = 0 then
    begin
       Result := False; // Null
       Exit;
    end;
    
    // Not Null
    if Buffer = nil then
    begin
       Result := True; // IsNull check -> I have data
       Exit;
    end;
    
    Inc(P);
    Move(P^, Buffer^, Field.DataSize);
    Result := True;
    Exit;
  end;

  if ReadFieldValue(Field, V) then
  begin
    if VarIsNull(V) or VarIsClear(V) then
    begin
       Result := False;
       Exit;
    end;

    // If Buffer is nil, just check for data existence (IsNull test)
    if Buffer = nil then
    begin
      Result := True;
      Exit;
    end;

    case Field.DataType of
      ftString, ftFixedChar:
        System.AnsiStrings.StrPLCopy(PAnsiChar(Buffer), AnsiString(string(V)), Field.Size);
      ftWideString, ftFixedWideChar:
        System.SysUtils.StrPLCopy(PWideChar(Buffer), string(V), Field.Size);
      ftShortint: PShortint(Buffer)^ := V;
      ftByte: PByte(Buffer)^ := V;
      ftSmallint: PSmallint(Buffer)^ := V;
      ftWord: PWord(Buffer)^ := V;
      ftInteger, ftAutoInc: PInteger(Buffer)^ := V;
      ftLongWord: PLongWord(Buffer)^ := V;
      ftFloat:
      begin
        FloatValue := V;
        PDouble(Buffer)^ := FloatValue;
      end;
      ftBoolean: PWordBool(Buffer)^ := V;
      ftDateTime, ftDate, ftTime:
      begin
        if VarIsStr(V) then
          DateTimeValue := VarToDateTime(V)
        else
          DateTimeValue := V;
        // Delphi's Data.DB expects ftDateTime/ftDate/ftTime fields to be stored as 
        // a 8-byte COMP (Int64 with floating point behavior) representing MILLISECONDS since year 0001.
        // We MUST convert our TDateTime (days) using the RTL's expected conversion.
        PDouble(Buffer)^ := TimeStampToMSecs(DateTimeToTimeStamp(DateTimeValue));
      end;
      ftLargeint:
      begin
        Int64Value := V;
        PInt64(Buffer)^ := Int64Value;
      end;
      ftCurrency:
      begin
        // IMPORTANT: TCurrencyField and TFloatField in Delphi's TDataSet framework (Data.DB)
        // internally store values as an 8-byte DOUBLE (IEEE 754) in their record buffers.
        // Attempting to write a raw 8-byte binary 'Currency' (scaled Int64) pattern directly 
        // to the buffer would result in corrupted values (e.g., 4.87E-317) when the 
        // field's GetAsCurrency or GetValue methods are called. 
        // Therefore, we MUST convert the value to a Double before writing to the buffer.
        DoubleValue := V;
        PDouble(Buffer)^ := DoubleValue;
      end;
      ftVariant: PVariant(Buffer)^ := V;
    else
      Result := False;
      Exit;
    end;
    Result := True;
  end;
end;

function TEntityDataSet.GetFieldData(Field: TField; var Buffer: TValueBuffer): Boolean;
begin
  Result := False;
  if not Assigned(Field) then Exit;

  if Length(Buffer) = 0 then
    Exit(GetFieldData(Field, nil));

  if Length(Buffer) < Field.DataSize then
    SetLength(Buffer, Field.DataSize);

  Result := GetFieldData(Field, @Buffer[0]);
end;

procedure TEntityDataSet.RemoveFromItems(AEntity: TObject; AFreeInstance: Boolean);
var
  Idx: Integer;
  Collection: Dext.Collections.Base.ICollection;
  WasOwns: Boolean;
begin
  if (FItems = nil) or (AEntity = nil) then Exit;

  Idx := FItems.IndexOf(AEntity);
  if Idx >= 0 then
  begin
    if Supports(FItems, Dext.Collections.Base.ICollection, Collection) then
    begin
      WasOwns := Collection.OwnsObjects;
      try
        Collection.OwnsObjects := AFreeInstance;
        FItems.Delete(Idx);
      finally
        Collection.OwnsObjects := WasOwns;
      end;
    end
    else
    begin
      FItems.Delete(Idx);
      if AFreeInstance then
        AEntity.Free;
    end;
  end;
end;

procedure TEntityDataSet.RecordOriginalValue(AEntity: TObject; Field: TField);
var
  i: Integer;
  j: Integer;
  Change: TEntityChange;
  Found: Boolean;
  OriginalVal: Variant;
  ValPair: Dext.Collections.Dict.TPair<string, Variant>;
begin
  if (FTrackedChanges = nil) or (AEntity = nil) or (Field = nil) then Exit;

  Found := False;
  for i := 0 to FTrackedChanges.Count - 1 do
  begin
    if FTrackedChanges[i].Entity = AEntity then
    begin
      Change := FTrackedChanges[i];
      Found := True;
      Break;
    end;
  end;

  if not Found then
  begin
    Change.State := ersModified;
    Change.Entity := AEntity;
    Change.OriginalIndex := -1;
    Change.Key := GetEntityKeys(AEntity);
    Change.DirtyFields := nil;
    Change.OriginalValues := nil;
  end;

  Found := False;
  if Change.OriginalValues <> nil then
  begin
    for j := 0 to High(Change.OriginalValues) do
    begin
      if SameText(Change.OriginalValues[j].Key, Field.FieldName) then
      begin
        Found := True;
        Break;
      end;
    end;
  end;

  if not Found then
  begin
    if ReadFieldValue(Field, OriginalVal) then
    begin
      SetLength(Change.OriginalValues, Length(Change.OriginalValues) + 1);
      ValPair.Key := Field.FieldName;
      ValPair.Value := OriginalVal;
      Change.OriginalValues[High(Change.OriginalValues)] := ValPair;

      Found := False;
      for i := 0 to FTrackedChanges.Count - 1 do
      begin
        if FTrackedChanges[i].Entity = AEntity then
        begin
          FTrackedChanges[i] := Change;
          Found := True;
          Break;
        end;
      end;
      if not Found then
        FTrackedChanges.Add(Change);
    end;
  end;
end;

procedure TEntityDataSet.SetFieldData(Field: TField; Buffer: Pointer);
var
  BufferPtr: Pointer;
  CurrentObj: TObject;
  Header: PEntityRecordHeader;
  Offset: Integer;
  P: PByte;
  LPropMap: TPropertyMap;
  RttiProp: TRttiProperty;
  RttiType: TRttiType;
  V: TValue;
  FieldExists: Boolean;
  i: Integer;
begin
  if not Assigned(Field) then
    Exit;
  if Field.ReadOnly or (State = dsBrowse) then
    Exit;

  if Field.FieldKind in [fkCalculated, fkLookup, fkInternalCalc] then
  begin
    if Field.FieldKind = fkCalculated then
      BufferPtr := Pointer(CalcBuffer)
    else
      BufferPtr := Pointer(ActiveBuffer);

    if BufferPtr = nil then
      Exit;
    if not FCalcOffsets.TryGetValue(Field.FieldName, Offset) then
      Exit;

    P := PByte(BufferPtr);
    Inc(P, Offset - 1);

    if Buffer = nil then
    begin
      P^ := 0; // Null
    end
    else
    begin
      P^ := 1; // Not Null
      Inc(P);
      Move(Buffer^, P^, Field.DataSize);
    end;
    DataEvent(deFieldChange, NativeInt(Field));
    Exit;
  end;

  CurrentObj := nil;
  Header := nil;
  if Pointer(ActiveBuffer) <> nil then
    Header := PEntityRecordHeader(ActiveBuffer);

  // Identifica o objeto de destino (Insert ou registro existente)
  if (Header <> nil) and (Header.BookmarkIndex = -2) then
    CurrentObj := FInsertObj
  else if (Header <> nil) and (Header.BookmarkIndex >= 0)
      and (Header.BookmarkIndex < FVirtualIndex.Count) then
    CurrentObj := FItems[FVirtualIndex[Header.BookmarkIndex]]
  else if (State = dsInsert) then
    CurrentObj := FInsertObj
  else if (FCurrentRec >= 0) and (FCurrentRec < FVirtualIndex.Count) then
    CurrentObj := FItems[FVirtualIndex[FCurrentRec]];

  if (CurrentObj = nil) or (FEntityMap = nil) then
    Exit;

  // Record original value for modified tracking if in dsEdit state
  if State = dsEdit then
    RecordOriginalValue(CurrentObj, Field);

  if not FEntityMap.Properties.TryGetValue(Field.FieldName, LPropMap) then
    Exit;

  // 1. Shadow Property support
  if LPropMap.IsShadow and (FDbContext <> nil) then
  begin
    if Buffer = nil then
      FDbContext.Entry(CurrentObj).Member(Field.FieldName)
        .SetCurrentValue(TValue.Empty)
    else
    begin
      case Field.DataType of
        ftString, ftWideString:
          V := string(PWideChar(Buffer));
        ftInteger:
          V := PInteger(Buffer)^;
        ftFloat:
          V := PDouble(Buffer)^;
        ftBoolean:
          V := PBoolean(Buffer)^;
      else
        V := TValue.Empty;
      end;
      FDbContext.Entry(CurrentObj).Member(Field.FieldName).SetCurrentValue(V);
    end;
    SetModified(True);
    if (State = dsEdit) and (FCurrentDirtyFields <> nil) then
    begin
      FieldExists := False;
      for i := 0 to FCurrentDirtyFields.Count - 1 do
      begin
        if SameText(FCurrentDirtyFields[i], Field.FieldName) then
        begin
          FieldExists := True;
          Break;
        end;
      end;
      if not FieldExists then
        FCurrentDirtyFields.Add(Field.FieldName);
    end;
    DataEvent(deFieldChange, NativeInt(Field));
    Exit;
  end;

  // 2. Direct RTTI/Offset writing
  if LPropMap.FieldValueOffset > 0 then
  begin
    P := PByte(CurrentObj);
    Inc(P, LPropMap.FieldValueOffset);
    if Buffer <> nil then
    begin
      case Field.DataType of
        ftString, ftWideString:
          PString(P)^ := string(PWideChar(Buffer));
        ftBoolean:
          PBoolean(P)^ := PBoolean(Buffer)^;
        ftDateTime, ftDate, ftTime:
          PDateTime(P)^ := TimeStampToDateTime(
            MSecsToTimeStamp(Trunc(PDouble(Buffer)^)));
        ftCurrency:
          PCurrency(P)^ := PDouble(Buffer)^;
        ftShortint: PShortint(P)^ := PShortint(Buffer)^;
        ftByte: PByte(P)^ := PByte(Buffer)^;
        ftSmallint: PSmallint(P)^ := PSmallint(Buffer)^;
        ftWord: PWord(P)^ := PWord(Buffer)^;
        ftInteger: PInteger(P)^ := PInteger(Buffer)^;
      else
        Move(Buffer^, P^, Field.DataSize);
      end;
    end;

    // Set HasValue flag if available
    if LPropMap.FieldOffset > 0 then
    begin
      P := PByte(CurrentObj);
      Inc(P, LPropMap.FieldOffset);
      PBoolean(P)^ := (Buffer <> nil);
    end;
    SetModified(True);
    if (State = dsEdit) and (FCurrentDirtyFields <> nil) then
    begin
      FieldExists := False;
      for i := 0 to FCurrentDirtyFields.Count - 1 do
      begin
        if SameText(FCurrentDirtyFields[i], Field.FieldName) then
        begin
          FieldExists := True;
          Break;
        end;
      end;
      if not FieldExists then
        FCurrentDirtyFields.Add(Field.FieldName);
    end;
    DataEvent(deFieldChange, NativeInt(Field));
  end
  else if (CurrentObj <> nil) then
  begin
    // RTTI Fallback for properties without direct FieldOffset
    V := TValue.Empty;
    if Buffer <> nil then
    begin
      case Field.DataType of
        ftString, ftWideString:
          V := string(PWideChar(Buffer));
        ftInteger, ftSmallint, ftAutoInc:
          V := PInteger(Buffer)^;
        ftLargeint:
          V := PInt64(Buffer)^;
        ftFloat:
          V := PDouble(Buffer)^;
        ftCurrency:
          V := Currency(PDouble(Buffer)^);
        ftBoolean:
          V := PBoolean(Buffer)^;
        ftDateTime, ftDate, ftTime:
          V := TimeStampToDateTime(MSecsToTimeStamp(Trunc(PDouble(Buffer)^)));
      end;
    end;

    RttiType := TReflection.Context.GetType(CurrentObj.ClassType);
    if RttiType <> nil then
    begin
      RttiProp := RttiType.GetProperty(Field.FieldName);
      if RttiProp <> nil then
        RttiProp.SetValue(CurrentObj, V);
    end;

    SetModified(True);
    DataEvent(deFieldChange, NativeInt(Field));
  end;
end;

procedure TEntityDataSet.SetFieldData(Field: TField; Buffer: TValueBuffer);
begin
  if Length(Buffer) = 0 then
    SetFieldData(Field, nil)
  else
    SetFieldData(Field, @Buffer[0]);
end;

procedure TEntityDataSet.InternalHandleException;
begin
  // No-op. Exceções em memória não exigem buffer rollback ou handle físico de database.
end;

function TEntityDataSet.IsCursorOpen: Boolean;
begin
  Result := FIsCursorOpen;
end;

{ TEntityMasterDataLink }

constructor TEntityMasterDataLink.Create(ADataSet: TEntityDataSet);
begin
  inherited Create(ADataSet);
  FEntityDataSet := ADataSet;
end;

procedure TEntityMasterDataLink.ActiveChanged;
begin
  if FEntityDataSet <> nil then
  begin
    FEntityDataSet.SyncMasterDetail;
    FEntityDataSet.ApplyFilterAndSort;
    FEntityDataSet.Resync([]);
  end;
end;

procedure TEntityMasterDataLink.RecordChanged(Field: TField);
begin
  // Field = nil significa que o cursor mudou de posiÃ§Ã£o no mestre
  if (FEntityDataSet <> nil) and (Field = nil) then
  begin
    FEntityDataSet.SyncMasterDetail;
    FEntityDataSet.ApplyFilterAndSort;
    FEntityDataSet.Resync([]);
  end;
end;

procedure TEntityDataSet.SetMasterInheritance(AEntity: TObject);
var
  DetailProp: TRttiProperty;
  DetailType: TRttiType;
  I: Integer;
  MasterField: TField;
  MasterLinkFields, DetailLinkFields: TArray<string>;
  MasterVal: Variant;
  Parts: TArray<string>;
begin
  if (FMasterDataSet = nil) or (FMasterFields = '') or (AEntity = nil) then Exit;
  
  // Parse linkage
  // New format: MasterField=DetailField
  // Legacy format: MasterField (DetailField comes from IndexFieldNames)
  Parts := FMasterFields.Split(['=']);
  MasterLinkFields := Parts[0].Split([';', ',']);
  
  if Length(Parts) > 1 then
    DetailLinkFields := Parts[1].Split([';', ','])
  else
    DetailLinkFields := FIndexFieldNames.Split([';', ',']); // TDataSet standard

  if Length(DetailLinkFields) = 0 then
    DetailLinkFields := MasterLinkFields; // Fallback to same names

  for I := 0 to High(MasterLinkFields) do
  begin
    if I > High(DetailLinkFields) then Break;
    
    MasterField := FMasterDataSet.FindField(MasterLinkFields[I].Trim);
    if MasterField <> nil then
    begin
      MasterVal := MasterField.Value;
      DetailType := TReflection.Context.GetType(AEntity.ClassType);
      if (DetailType <> nil) and (not VarIsNull(MasterVal)) then
      begin
        DetailProp := DetailType.GetProperty(DetailLinkFields[I].Trim);
        if DetailProp <> nil then
          DetailProp.SetValue(AEntity, TValue.FromVariant(MasterVal));
      end;
    end;
  end;
end;

function TEntityDataSet.GetChanges: IList<TEntityChange>;
begin
  Result := FTrackedChanges;
end;

procedure TEntityDataSet.AcceptChanges;
begin
  if FTrackedChanges <> nil then
    FTrackedChanges.Clear;
  if FDeletedItemsCache <> nil then
    FDeletedItemsCache.Clear;
end;

procedure TEntityDataSet.RejectChanges;
var
  i: Integer;
  j: Integer;
  Change: TEntityChange;
  Prop: TRttiProperty;
  RttiType: TRttiType;
begin
  if FTrackedChanges = nil then Exit;

  // Process in reverse to maintain index correctness for insertions/deletions
  for i := FTrackedChanges.Count - 1 downto 0 do
  begin
    Change := FTrackedChanges[i];
    case Change.State of
      ersInserted:
        begin
          if Change.Entity <> nil then
          begin
            if FItems <> nil then
              RemoveFromItems(Change.Entity, False);
            if FDataSetCreatedItems <> nil then
            begin
              FDataSetCreatedItems.Extract(Change.Entity);
              Change.Entity.Free;
            end;
          end;
        end;

      ersDeleted:
        begin
          if (Change.Entity <> nil) and (FItems <> nil) and (Change.OriginalIndex >= 0) then
          begin
            if FDeletedItemsCache <> nil then
              FDeletedItemsCache.Extract(Change.Entity);

            if Change.OriginalIndex >= FItems.Count then
              FItems.Add(Change.Entity)
            else
              FItems.Insert(Change.OriginalIndex, Change.Entity);
          end;
        end;

      ersModified:
        begin
          if (Change.Entity <> nil) and (Change.OriginalValues <> nil) then
          begin
            RttiType := TReflection.Context.GetType(Change.Entity.ClassType);
            if RttiType <> nil then
            begin
              for j := 0 to High(Change.OriginalValues) do
              begin
                Prop := RttiType.GetProperty(Change.OriginalValues[j].Key);
                if Prop <> nil then
                  Prop.SetValue(Change.Entity, TValue.FromVariant(Change.OriginalValues[j].Value));
              end;
            end;
          end;
        end;
    end;
  end;

  FTrackedChanges.Clear;
  if FDeletedItemsCache <> nil then
    FDeletedItemsCache.Clear;
  ApplyFilterAndSort;
  Resync([]);
end;

procedure TEntityDataSet.ClearChanges;
begin
  if FTrackedChanges <> nil then
    FTrackedChanges.Clear;
end;

function TEntityDataSet.GetEntityKeys(AEntity: TObject):
  TArray<Dext.Collections.Dict.TPair<string, Variant>>;
var
  Pair: Dext.Collections.Dict.TPair<string, TPropertyMap>;
  Val: Variant;
  KeysList: IList<Dext.Collections.Dict.TPair<string, Variant>>;
begin
  KeysList := TCollections.CreateList<
    Dext.Collections.Dict.TPair<string, Variant>>;
  if (AEntity <> nil) and (FEntityMap <> nil) then
  begin
    for Pair in FEntityMap.Properties do
    begin
      if Pair.Value.IsPK then
      begin
        if ReadPropertyValue(AEntity, Pair.Value, Val) then
          KeysList.Add(
            Dext.Collections.Dict.TPair<string, Variant>.Create(
              Pair.Key, Val));
      end;
    end;
  end;
  Result := KeysList.ToArray;
end;

function TEntityDataSet.ReadPropertyValue(AEntity: TObject;
  PropMap: TPropertyMap; out AValue: Variant): Boolean;
var
  PValue: Pointer;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  Val: TValue;
begin
  Result := False;
  if (AEntity = nil) or (PropMap = nil) then Exit;

  if PropMap.FieldValueOffset > 0 then
  begin
    if (PropMap.FieldOffset > 0) and not
      PBoolean(Pointer(PByte(AEntity) + PropMap.FieldOffset))^ then
    begin
      AValue := Null;
      Exit(True);
    end;

    PValue := Pointer(PByte(AEntity) + PropMap.FieldValueOffset);
    case PropMap.DataType of
      ftInteger, ftAutoInc: AValue := PInteger(PValue)^;
      ftSmallint: AValue := PSmallInt(PValue)^;
      ftShortint: AValue := PShortInt(PValue)^;
      ftByte: AValue := PByte(PValue)^;
      ftWord: AValue := PWord(PValue)^;
      ftLargeint: AValue := PInt64(PValue)^;
      ftString, ftWideString: AValue := PString(PValue)^;
      ftFloat: AValue := PDouble(PValue)^;
      ftCurrency: AValue := PCurrency(PValue)^;
      ftBoolean: AValue := PBoolean(PValue)^;
      ftDateTime, ftDate, ftTime: AValue := PDateTime(PValue)^;
    else
      Exit(False);
    end;
    Result := True;
  end
  else
  begin
    RttiType := TReflection.Context.GetType(AEntity.ClassType);
    if RttiType <> nil then
    begin
      RttiProp := RttiType.GetProperty(PropMap.PropertyName);
      if RttiProp <> nil then
      begin
        Val := RttiProp.GetValue(AEntity);
        AValue := Val.AsVariant;
        Result := True;
      end;
    end;
  end;
end;

end.
