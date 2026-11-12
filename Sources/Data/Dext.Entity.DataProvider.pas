unit Dext.Entity.DataProvider;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.TypInfo,
  Data.DB,
  Dext.Collections,
  Dext.Collections.Dict,
  FireDAC.Comp.Client,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Mapping,
  Dext.Entity.Metadata,
  Dext.Core.Reflection,
  Dext.Utils;

type
  /// <summary>
  ///   Event triggered when a unit source file is refreshed by the data provider.
  /// </summary>
  TRefreshUnitEvent = procedure(AProvider: TComponent; const AFileName: string) of object;
  
  /// <summary>
  ///   Event to request source code content for a given filename during metadata synchronization.
  /// </summary>
  TGetSourceContentEvent = function(const AFileName: string): string;

  /// <summary>
  ///   Provider component that discovers, parses, and provides runtime entity metadata and preview capabilities.
  /// </summary>
  TEntityDataProvider = class(TComponent, IEntityDataProvider)
  private
    FModelUnits: TStrings;
    FMetadataCache: IDictionary<string, TEntityClassMetadata>;
    FDatabaseConnection: TFDCustomConnection;
    FPreviewMaxRows: Integer;
    FDialect: TDatabaseDialect;
    FDebugMode: Boolean;
    FLastRefreshSummary: string;
    FLastPreviewError: string;
    FEntitiesMetadata: TEntityClassCollection;
    FOnRefreshUnit: TRefreshUnitEvent;
    FDataSets: IList<TComponent>;
    FOldAfterDisconnect: TNotifyEvent;
    FOldAfterConnect: TNotifyEvent;
    procedure SetEntitiesMetadata(const Value: TEntityClassCollection);
    procedure NotifyConnectionClosed(Sender: TObject);
    procedure ApplySessionSchema(Sender: TObject);
    function BuildEntityMap(AClass: TClass): TEntityMap;
    function BuildColumnList(AClass: TClass; const AClassName: string): string;
    function GetEntityCount: Integer;
    function GetResolvedDialect: TDatabaseDialect;
    function GetDialectName: string;
    procedure SetDialect(const Value: TDatabaseDialect);
    procedure SetModelUnits(const Value: TStrings);
    procedure OnModelUnitsChange(Sender: TObject);
    procedure SetDatabaseConnection(const Value: TFDCustomConnection);
    procedure SetLastRefreshSummary(const Value: string);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ClearMetadata;
    procedure AddOrSetMetadata(const AMetadata: TEntityClassMetadata);
    procedure UpdateRefreshSummary; overload;
    /// <summary>
    ///   Same summary, naming the units that could not be read, so a stale
    ///   entry in ModelUnits does not look like a unit without entities.
    /// </summary>
    procedure UpdateRefreshSummary(const AMissingUnits: TArray<string>); overload;
    procedure RefreshMetadata;
    procedure RefreshUnit(const AFileName: string);
    function GetEntities: TArray<string>;
    function GetEntityMetadata(const AClassName: string): TEntityClassMetadata;
    function GetEntityUnitName(const AClassName: string): string;
    function ResolveEntityClass(const AClassName: string): TClass;
    function BuildPreviewSql(const AClassName: string; AMaxRows: Integer = 50): string;
    function CreatePreviewItems(const AClassName: string; AMaxRows: Integer = 50): IObjectList;
    function GetPreviewData(const AClassName: string; AMaxRows: Integer = 50): IList<IDictionary<string, Variant>>;
    /// <summary>
    ///   Forces a design-time synchronization of metadata from source code for a specific entity.
    /// </summary>
    procedure SyncMetadata(const AEntityClassName: string);
    procedure RegisterDataSet(ADataSet: TComponent);
    procedure UnregisterDataSet(ADataSet: TComponent);
    /// <summary>
    ///   Why the last GetPreviewData returned no rows (no connection, an
    ///   unknown entity, or the error of the query); empty when it worked.
    /// </summary>
    property LastPreviewError: string read FLastPreviewError;
  published
    property DatabaseConnection: TFDCustomConnection read FDatabaseConnection write SetDatabaseConnection;
    property ModelUnits: TStrings read FModelUnits write SetModelUnits;
    property Dialect: TDatabaseDialect read FDialect write SetDialect default ddUnknown;
    property DialectName: string read GetDialectName;
    property PreviewMaxRows: Integer read FPreviewMaxRows write FPreviewMaxRows default 50;
    property DebugMode: Boolean read FDebugMode write FDebugMode default False;
    property EntityCount: Integer read GetEntityCount stored False;
    property LastRefreshSummary: string read FLastRefreshSummary write SetLastRefreshSummary stored False;
    property OnRefreshUnit: TRefreshUnitEvent read FOnRefreshUnit write FOnRefreshUnit;
    property EntitiesMetadata: TEntityClassCollection read FEntitiesMetadata write SetEntitiesMetadata;
  end;

var
  GOnGetSourceContent: TGetSourceContentEvent = nil;

implementation

constructor TEntityDataProvider.Create(AOwner: TComponent);
begin
  inherited;
  FModelUnits := TStringList.Create;
  TStringList(FModelUnits).OnChange := OnModelUnitsChange;
  FEntitiesMetadata := TEntityClassCollection.Create(Self);
  FMetadataCache := TCollections.CreateDictionary<string, TEntityClassMetadata>(False);
  FDataSets := TCollections.CreateList<TComponent>;
  FPreviewMaxRows := 50;
  FDialect := ddUnknown;
end;

destructor TEntityDataProvider.Destroy;
begin
  FDataSets := nil;
  FMetadataCache := nil;
  FEntitiesMetadata.Free;
  FModelUnits.Free;
  inherited;
end;

procedure TEntityDataProvider.RegisterDataSet(ADataSet: TComponent);
begin
  if FDataSets.IndexOf(ADataSet) < 0 then
    FDataSets.Add(ADataSet);
end;

procedure TEntityDataProvider.UnregisterDataSet(ADataSet: TComponent);
begin
  FDataSets.Remove(ADataSet);
end;

procedure TEntityDataProvider.NotifyConnectionClosed(Sender: TObject);
var
  i: Integer;
  DS: TComponent;
begin
  if Assigned(FOldAfterDisconnect) then
    FOldAfterDisconnect(Sender);

  for i := FDataSets.Count - 1 downto 0 do
  begin
    DS := FDataSets[i];
    if DS is TDataSet then
      TDataSet(DS).Active := False;
  end;
end;

procedure TEntityDataProvider.ApplySessionSchema(Sender: TObject);
var
  LSchema: string;
  LDialect: ISQLDialect;
  LSQL: string;
begin
  if Assigned(FOldAfterConnect) then
    FOldAfterConnect(Sender);

  if FDatabaseConnection = nil then Exit;

  LSchema := FDatabaseConnection.Params.Values['Schema'];
  if LSchema = '' then LSchema := FDatabaseConnection.Params.Values['MetaCurSchema'];
  if LSchema = '' then LSchema := FDatabaseConnection.Params.Values['MetaDefSchema'];

  if LSchema <> '' then
  begin
    LDialect := TDialectFactory.CreateDialect(GetResolvedDialect);
    if LDialect <> nil then
    begin
      LSQL := LDialect.GetSetSchemaSQL(LSchema);
      if LSQL <> '' then
      begin
        try
          FDatabaseConnection.ExecSQL(LSQL);
        except
          // Silently ignore errors in design-time session switching
        end;
      end;
    end;
  end;
end;
type
  TEntityMapEnricher = class
  public
    class procedure Enrich(AMap: TEntityMap; AMetadata: TEntityClassMetadata);
  end;

function TEntityDataProvider.BuildEntityMap(AClass: TClass): TEntityMap;
var
  Metadata: TEntityClassMetadata;
begin
  Result := TEntityMap.Create(AClass.ClassInfo);
  Result.DiscoverAttributes;
  
  // Enrich with parser metadata if available (Design-Time or Runtime cached)
  Metadata := GetEntityMetadata(AClass.ClassName);
  if Metadata <> nil then
    TEntityMapEnricher.Enrich(Result, Metadata);
end;

function TEntityDataProvider.BuildColumnList(AClass: TClass; const AClassName: string): string;
var
  EntityMap: TEntityMap;
  Columns: IList<string>;
  PropMap: TPropertyMap;
begin
  Columns := TCollections.CreateList<string>;

  if AClass <> nil then
  begin
    EntityMap := BuildEntityMap(AClass);
    try
      for PropMap in EntityMap.Properties.Values do
      begin
        if PropMap.IsIgnored or PropMap.IsNavigation or PropMap.IsShadow then
          Continue;

        if PropMap.ColumnName <> '' then
          Columns.Add(PropMap.ColumnName)
        else
          Columns.Add(PropMap.PropertyName);
      end;
    finally
      EntityMap.Free;
    end;
  end
  else
  begin
    // DESIGN-TIME: We cannot reliably distinguish between primitive DB columns 
    // and navigation properties (e.g. TStock, IList<TObject>) from raw string metadata 
    // without full RTTI, so it's safer to just SELECT * and let the DB return the actual physical columns.
    Exit('*');
  end;

  if Columns.Count = 0 then
    Exit('*');

  Result := string.Join(', ', Columns.ToArray);
end;

function TEntityDataProvider.GetEntityCount: Integer;
begin
  Result := FMetadataCache.Count;
end;

function TEntityDataProvider.GetResolvedDialect: TDatabaseDialect;
begin
  if FDialect <> ddUnknown then
    Exit(FDialect);

  if FDatabaseConnection <> nil then
    Exit(TDialectFactory.DetectDialect(FDatabaseConnection.DriverName));

  Result := ddUnknown;
end;

function TEntityDataProvider.GetDialectName: string;
begin
  Result := GetEnumName(TypeInfo(TDatabaseDialect), Ord(GetResolvedDialect));
end;

procedure TEntityDataProvider.SetDialect(const Value: TDatabaseDialect);
begin
  FDialect := Value;
end;

function TEntityDataProvider.GetEntities: TArray<string>;
var
  List: IList<string>;
  i: Integer;
begin
  List := TCollections.CreateList<string>;
  for i := 0 to FEntitiesMetadata.Count - 1 do
    List.Add(FEntitiesMetadata[i].EntityClassName);
  Result := List.ToArray;
end;

function TEntityDataProvider.GetEntityMetadata(const AClassName: string): TEntityClassMetadata;
begin
  if not FMetadataCache.TryGetValue(AClassName, Result) then
    Result := nil;
end;

function TEntityDataProvider.GetEntityUnitName(const AClassName: string): string;
var
  Metadata: TEntityClassMetadata;
begin
  Metadata := GetEntityMetadata(AClassName);
  if Metadata <> nil then
    Result := Metadata.EntityUnitName
  else
    Result := '';
end;

procedure TEntityDataProvider.SyncMetadata(const AEntityClassName: string);
var
  FileName, UnitName, Content: string;
  Parser: TEntityMetadataParser;
  ParsedList: IList<TEntityClassMetadata>;
  MD: TEntityClassMetadata;
  Found: Boolean;
  I: Integer;
begin
  if not (csDesigning in ComponentState) then
    Exit;

  UnitName := GetEntityUnitName(AEntityClassName);
  // Log critical state

  if UnitName = '' then
    Exit;

  // Find the full path in ModelUnits
  FileName := '';
  for I := 0 to FModelUnits.Count - 1 do
  begin
    if SameText(ChangeFileExt(ExtractFileName(FModelUnits[I]), ''), UnitName) then
    begin
      FileName := FModelUnits[I];
      Break;
    end;
  end;

  if FileName = '' then
  begin
    Exit;
  end;

  Content := '';
  if Assigned(GOnGetSourceContent) then
    Content := GOnGetSourceContent(FileName);

  Parser := TEntityMetadataParser.Create;
  try
    ParsedList := Parser.ParseUnit(FileName, Content);
    Found := False;
    
    for MD in ParsedList do
      if SameText(MD.EntityClassName, AEntityClassName) then
      begin
        AddOrSetMetadata(MD);
        Found := True;
        Break;
      end;
      
    if not Found then
       
  finally
    Parser.Free;
  end;
end;

function TEntityDataProvider.ResolveEntityClass(const AClassName: string): TClass;
var
  Metadata: TEntityClassMetadata;
  RttiType: TRttiType;
begin
  Result := nil;
  if AClassName = '' then
    Exit;

  Metadata := GetEntityMetadata(AClassName);
  if Metadata <> nil then
  begin
    if Metadata.EntityUnitName <> '' then
    begin
      RttiType := TReflection.Context.FindType(Metadata.EntityUnitName + '.' + Metadata.EntityClassName);
      if RttiType is TRttiInstanceType then
        Exit(TRttiInstanceType(RttiType).MetaclassType);
    end;

    RttiType := TReflection.Context.FindType(Metadata.ClassName);
    if RttiType is TRttiInstanceType then
      Exit(TRttiInstanceType(RttiType).MetaclassType);
  end;

  Result := GetClass(AClassName);
end;

function TEntityDataProvider.BuildPreviewSql(const AClassName: string; AMaxRows: Integer): string;
var
  Metadata: TEntityClassMetadata;
  EntityClass: TClass;
  Columns: string;
  BaseSql: string;
  DialectSvc: ISQLDialect;
begin
  Metadata := GetEntityMetadata(AClassName);
  if Metadata = nil then
    Exit('');

  if AMaxRows <= 0 then
    AMaxRows := FPreviewMaxRows;

  EntityClass := ResolveEntityClass(AClassName);
  Columns := BuildColumnList(EntityClass, AClassName);
  DialectSvc := TDialectFactory.CreateDialect(GetResolvedDialect);

  if DialectSvc <> nil then
    BaseSql := Format('SELECT %s FROM %s',
      [Columns, DialectSvc.QuoteIdentifier(Metadata.TableName)])
  else
    BaseSql := Format('SELECT %s FROM %s', [Columns, Metadata.TableName]);

  if DialectSvc <> nil then
    Result := DialectSvc.GeneratePaging(BaseSql, 0, AMaxRows)
  else
    Result := BaseSql;
end;

function TEntityDataProvider.CreatePreviewItems(const AClassName: string; AMaxRows: Integer): IObjectList;
var
  EntityClass: TClass;
  EntityMap: TEntityMap;
  Query: TFDQuery;
  SqlText: string;
  ColumnMap: IDictionary<string, TPropertyMap>;
  Obj: TObject;
  PropMap: TPropertyMap;
  FieldValue: TValue;
  CurrentPropMap: TPropertyMap;
  I: Integer;
begin
  Result := nil;

  if FDatabaseConnection = nil then
    Exit;

  EntityClass := ResolveEntityClass(AClassName);
  if EntityClass = nil then
    Exit;

  SqlText := BuildPreviewSql(AClassName, AMaxRows);
  if SqlText = '' then
    Exit;

  EntityMap := BuildEntityMap(EntityClass);
  try
    ColumnMap := TCollections.CreateDictionaryIgnoreCase<string, TPropertyMap>;
    for CurrentPropMap in EntityMap.Properties.Values do
    begin
      if CurrentPropMap.IsIgnored or CurrentPropMap.IsNavigation or CurrentPropMap.IsShadow then
        Continue;

      if CurrentPropMap.ColumnName <> '' then
        ColumnMap.AddOrSetValue(CurrentPropMap.ColumnName, CurrentPropMap);

      ColumnMap.AddOrSetValue(CurrentPropMap.PropertyName, CurrentPropMap);

      if CurrentPropMap.FieldName <> '' then
        ColumnMap.AddOrSetValue(CurrentPropMap.FieldName, CurrentPropMap);
    end;

    Result := TCollections.CreateObjectList<TObject>(True) as IObjectList;

    Query := TFDQuery.Create(nil);
    try
      Query.Connection := FDatabaseConnection;
      Query.SQL.Text := SqlText;
      Query.Open;

      while not Query.Eof do
      begin
        Obj := TReflection.CreateInstance(EntityClass);
        if Obj <> nil then
        begin
          for I := 0 to Query.Fields.Count - 1 do
          begin
            if not ColumnMap.TryGetValue(Query.Fields[I].FieldName, PropMap) then
              Continue;

            if PropMap.Prop = nil then
              PropMap.Prop := TReflection.Context.GetType(EntityClass.ClassInfo).GetProperty(PropMap.PropertyName);

            if PropMap.Prop = nil then
              Continue;

            if Query.Fields[I].IsNull then
              Continue;

            case Query.Fields[I].DataType of
              ftBlob, ftOraBlob:
                FieldValue := TValue.From<TBytes>(Query.Fields[I].AsBytes);
              ftMemo, ftWideMemo, ftOraClob:
                FieldValue := TValue.From<string>(Query.Fields[I].AsString);
            else
              FieldValue := TValue.FromVariant(Query.Fields[I].Value);
            end;
            TReflection.SetValue(Pointer(Obj), PropMap.Prop, FieldValue);
          end;

          Result.Add(Obj);
        end;

        Query.Next;
      end;
    finally
      Query.Free;
    end;
  finally
    EntityMap.Free;
  end;
end;

procedure TEntityDataProvider.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = FDatabaseConnection) then
    FDatabaseConnection := nil;
end;

procedure TEntityDataProvider.Loaded;
var
  i: Integer;
begin
  inherited;
  FMetadataCache.Clear;
  for i := 0 to FEntitiesMetadata.Count - 1 do
    FMetadataCache.AddOrSetValue(FEntitiesMetadata[i].EntityClassName, FEntitiesMetadata[i]);
end;

procedure TEntityDataProvider.OnModelUnitsChange(Sender: TObject);
begin
end;

procedure TEntityDataProvider.ClearMetadata;
begin
  FMetadataCache.Clear;
  FEntitiesMetadata.Clear;
end;


procedure TEntityDataProvider.AddOrSetMetadata(const AMetadata: TEntityClassMetadata);
var
  NewMD: TEntityClassMetadata;
begin
  if AMetadata = nil then
    Exit;


  NewMD := FEntitiesMetadata.FindByName(AMetadata.EntityClassName);
  if NewMD = nil then
    NewMD := FEntitiesMetadata.Add;

  NewMD.EntityClassName := AMetadata.EntityClassName;
  NewMD.DisplayName := AMetadata.DisplayName;
  NewMD.TableName := AMetadata.TableName;
  NewMD.EntityUnitName := AMetadata.EntityUnitName;

  // Purge any stale members to ensure the new sync is clean
  NewMD.Members.Clear;
  NewMD.Members.Assign(AMetadata.Members);

  FMetadataCache.AddOrSetValue(NewMD.EntityClassName, NewMD);
  
end;

procedure TEntityDataProvider.SetEntitiesMetadata(const Value: TEntityClassCollection);
begin
  FEntitiesMetadata.Assign(Value);
end;

procedure TEntityDataProvider.UpdateRefreshSummary;
begin
  UpdateRefreshSummary(nil);
end;

procedure TEntityDataProvider.UpdateRefreshSummary(
  const AMissingUnits: TArray<string>);
var
  Names: TArray<string>;
  I: Integer;
begin
  FLastRefreshSummary := Format('%d entity(ies) found in %d unit(s).',
    [FMetadataCache.Count, FModelUnits.Count]);
  if Length(AMissingUnits) > 0 then
  begin
    SetLength(Names, Length(AMissingUnits));
    for I := 0 to High(AMissingUnits) do
      Names[I] := ExtractFileName(AMissingUnits[I]);
    FLastRefreshSummary := FLastRefreshSummary + Format(
      ' Could not read %d unit(s): %s.', [Length(Names), string.Join(', ', Names)]);
  end;
end;

procedure TEntityDataProvider.RefreshMetadata;
begin
  ClearMetadata;
  UpdateRefreshSummary;
end;

procedure TEntityDataProvider.RefreshUnit(const AFileName: string);
begin
  if Assigned(FOnRefreshUnit) then
    FOnRefreshUnit(Self, AFileName)
  else
end;

procedure TEntityDataProvider.SetLastRefreshSummary(const Value: string);
begin
  FLastRefreshSummary := Value;
end;

procedure TEntityDataProvider.SetDatabaseConnection(const Value: TFDCustomConnection);
begin
  if FDatabaseConnection <> Value then
  begin
    if FDatabaseConnection <> nil then
      FDatabaseConnection.RemoveFreeNotification(Self);

    FDatabaseConnection := Value;

    if FDatabaseConnection <> nil then
    begin
      FDatabaseConnection.FreeNotification(Self);
      
      FOldAfterDisconnect := FDatabaseConnection.AfterDisconnect;
      FDatabaseConnection.AfterDisconnect := NotifyConnectionClosed;
      
      FOldAfterConnect := FDatabaseConnection.AfterConnect;
      FDatabaseConnection.AfterConnect := ApplySessionSchema;

      // Auto-infer dialect from connection if not manually set
      if (FDialect = ddUnknown) and (FDatabaseConnection.DriverName <> '') then
        FDialect := TDialectFactory.DetectDialect(FDatabaseConnection.DriverName);

      // If already connected, apply schema immediately
      if FDatabaseConnection.Connected then
        ApplySessionSchema(FDatabaseConnection);
    end;
  end;
end;

procedure TEntityDataProvider.SetModelUnits(const Value: TStrings);
begin
  FModelUnits.Assign(Value);
end;

function TEntityDataProvider.GetPreviewData(const AClassName: string; AMaxRows: Integer): IList<IDictionary<string, Variant>>;
var
  Sql: string;
  Query: TFDQuery;
  Row: IDictionary<string, Variant>;
  i: Integer;
begin
  Result := TCollections.CreateList<IDictionary<string, Variant>>;
  FLastPreviewError := '';
  Sql := BuildPreviewSql(AClassName, AMaxRows);
  if Sql = '' then
  begin
    FLastPreviewError := Format('Unknown entity "%s".', [AClassName]);
    Exit;
  end;
  if FDatabaseConnection = nil then
  begin
    FLastPreviewError := 'The provider has no DatabaseConnection.';
    Exit;
  end;
  if not FDatabaseConnection.Connected then
  begin
    FLastPreviewError := 'The DatabaseConnection is not connected.';
    Exit;
  end;

  Query := TFDQuery.Create(nil);
  try
    Query.Connection := FDatabaseConnection;
    Query.SQL.Text := Sql;
    try
      Query.Open;
      while not Query.Eof do
      begin
        Row := TCollections.CreateDictionary<string, Variant>;
        for i := 0 to Query.Fields.Count - 1 do
          Row.Add(Query.Fields[i].FieldName, Query.Fields[i].Value);
        Result.Add(Row);
        Query.Next;
      end;
    except
      // A failed preview query must not break the designer, but the reason
      // stays available instead of an empty grid with no explanation.
      on E: Exception do
      begin
        Result.Clear;
        FLastPreviewError := E.Message;
      end;
    end;
  finally
    Query.Free;
  end;
end;

class procedure TEntityMapEnricher.Enrich(AMap: TEntityMap; AMetadata: TEntityClassMetadata);
var
  i: Integer;
  MemberMD: TEntityMemberMetadata;
  PropMap: TPropertyMap;
begin
  if (AMap = nil) or (AMetadata = nil) then Exit;
  
  if AMetadata.TableName <> '' then
    AMap.TableName := AMetadata.TableName;

  for i := 0 to AMetadata.Members.Count - 1 do
  begin
    MemberMD := AMetadata.Members[i];
    PropMap := AMap.GetOrAddProperty(MemberMD.Name);
    
    if MemberMD.DisplayLabel <> '' then
      PropMap.DisplayLabel := MemberMD.DisplayLabel;
      
    if MemberMD.DisplayWidth > 0 then
      PropMap.DisplayWidth := MemberMD.DisplayWidth;
      
    if MemberMD.DisplayFormat <> '' then
      PropMap.DisplayFormat := MemberMD.DisplayFormat;
      
    if MemberMD.EditMask <> '' then
      PropMap.EditMask := MemberMD.EditMask;
      
    if MemberMD.Alignment <> taLeftJustify then
      PropMap.Alignment := MemberMD.Alignment;
      
    PropMap.IsReadOnly := MemberMD.IsReadOnly;
    PropMap.Visible := MemberMD.Visible;
    PropMap.IsRequired := MemberMD.IsRequired;
    PropMap.IsPK := MemberMD.IsPrimaryKey;
    PropMap.IsAutoInc := MemberMD.IsAutoInc;
    
    if MemberMD.MaxLength > 0 then
      PropMap.MaxLength := MemberMD.MaxLength;
  end;
end;

end.
