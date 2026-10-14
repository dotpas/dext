{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{***************************************************************************}
unit Dext.Web.EntityDataSetApi;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.Rtti,
  Data.DB,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Entity,
  Dext.Entity.Context,
  Dext.Entity.Mapping,
  Dext.Json,
  Dext.Json.Types,
  Dext.Web.Interfaces,
  Dext.Web.Routing;

type
  /// <summary>
  /// Represents the result of applying a single change item.
  /// </summary>
  TApplyItemResult = record
    /// <summary>The index of the change in the incoming list.</summary>
    Index: Integer;
    /// <summary>True if the change was applied successfully.</summary>
    Success: Boolean;
    /// <summary>Detailed error message in case of failure.</summary>
    ErrorMessage: string;
    /// <summary>Database keys (e.g. autoincrement ID).</summary>
    Keys: IDictionary<string, Variant>;
  end;

  /// <summary>
  /// Interface for processing and persisting entity change logs.
  /// </summary>
  IEntityDataSetStore = interface
    ['{F1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D}']
    /// <summary>
    /// Persists a batch of entity changes.
    /// </summary>
    function ApplyChanges(AEntityClass: TClass;
      const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
  end;

  /// <summary>
  /// DBContext-based store engine for persisting change logs.
  /// </summary>
  TDbContextEntityDataSetStore = class(TInterfacedObject, IEntityDataSetStore)
  private
    FContinueOnError: Boolean;
    function GetEntityKeys(AEntity: TObject;
      Map: TEntityMap): IDictionary<string, Variant>;
    function ReadPropertyValue(AEntity: TObject;
      PropMap: TPropertyMap; out Value: Variant): Boolean;
    procedure SetPropertyValue(AEntity: TObject;
      PropMap: TPropertyMap; const Value: Variant);
    function StageChange(AEntityClass: TClass; Map: TEntityMap;
      const AChange: IDextJsonObject; ADbContext: TDbContext): TObject;
    function ApplyAtomic(AEntityClass: TClass; const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
    function ApplyEachItem(AEntityClass: TClass; const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
  public
    /// <summary>
    /// Creates the store. By default a batch is applied all-or-nothing.
    /// </summary>
    /// <param name="AContinueOnError">See ContinueOnError.</param>
    constructor Create(AContinueOnError: Boolean = False);
    /// <summary>
    /// Persists changes using the ORM DbContext SaveChanges.
    /// By default the whole batch is staged and saved with a single
    /// SaveChanges, in one transaction (the context's own, or the caller's if
    /// one is open): if any item fails, nothing is applied and every item is
    /// reported as failed. With ContinueOnError each item is saved on its own.
    /// </summary>
    function ApplyChanges(AEntityClass: TClass;
      const AChanges: IDextJsonArray;
      ADbContext: TDbContext): IList<TApplyItemResult>;
    /// <summary>
    /// Opt-in partial success: each item is saved with its own SaveChanges,
    /// and a failing item is detached so that later items do not retry it.
    /// Items applied before a failure stay committed. Default: False.
    /// </summary>
    property ContinueOnError: Boolean read FContinueOnError write FContinueOnError;
  end;

  /// <summary>
  /// Exposes REST endpoints to load and persist datasets.
  /// </summary>
  TEntityDataSetApi = class
  public
    /// <summary>
    /// Maps GET and POST endpoints for a remote dataset.
    /// </summary>
    class procedure Map<T: class, constructor>(
      const ABuilder: IApplicationBuilder;
      const APath: string;
      ADbContextClass: TClass;
      AStore: IEntityDataSetStore = nil);
  end;

implementation

uses
  System.TypInfo,
  System.DateUtils,
  Dext.Core.DateUtils,
  Dext.Core.Reflection;

/// <summary>
///   The value of a JSON member as a Variant: null stays Null, a boolean stays
///   a Boolean, and a string or a number arrives as its text, to be converted
///   by ConvertToPropertyType. A missing member is Null too.
/// </summary>
function JsonMemberValue(const AObject: IDextJsonObject;
  const AName: string): Variant;
var
  Node: IDextJsonNode;
begin
  Node := AObject.GetNode(AName);
  if (Node = nil) or Node.IsNull then
    Exit(Null);
  case Node.NodeType of
    TDextJsonNodeType.jntBoolean:
      Result := Node.AsBoolean;
    TDextJsonNodeType.jntString, TDextJsonNodeType.jntNumber:
      Result := Node.AsString;
  else
    Result := Node.ToJson;
  end;
end;

/// <summary>
///   Converts the text of a JSON value to the Variant type of the property.
///   Numbers and dates are read with the invariant format (JSON always uses a
///   dot, whatever the machine locale), dates as ISO 8601. A value that cannot
///   be converted raises EConvertError naming the property, instead of
///   becoming 0. Null and non-string values are returned unchanged.
/// </summary>
function ConvertToPropertyType(const AValue: Variant; ATypeInfo: PTypeInfo;
  const APropertyName: string): Variant;
var
  S: string;
  I64: Int64;
  F: Double;
  C: Currency;
  D: TDateTime;
  B: Boolean;
  Ordinal: Integer;

  procedure Fail;
  begin
    raise EConvertError.CreateFmt('Cannot convert "%s" to %s for property "%s"',
      [S, string(ATypeInfo^.Name), APropertyName]);
  end;

begin
  Result := AValue;
  if (ATypeInfo = nil) or VarIsNull(AValue) or VarIsEmpty(AValue) or
    not VarIsStr(AValue) then
    Exit;

  S := VarToStr(AValue);
  case ATypeInfo^.Kind of
    tkInteger, tkInt64:
      begin
        if not TryStrToInt64(S, I64) then
          Fail;
        Result := I64;
      end;
    tkEnumeration:
      if ATypeInfo = TypeInfo(Boolean) then
      begin
        if not TryStrToBool(S, B) then
          Fail;
        Result := B;
      end
      else
      begin
        if not TryStrToInt(S, Ordinal) then
        begin
          Ordinal := GetEnumValue(ATypeInfo, S);
          if Ordinal < 0 then
            Fail;
        end;
        Result := Ordinal;
      end;
    tkFloat:
      if (ATypeInfo = TypeInfo(TDateTime)) or (ATypeInfo = TypeInfo(TDate)) or
        (ATypeInfo = TypeInfo(TTime)) then
      begin
        // The JSON forms (Dext.Core.DateUtils): no zone is local time, a 'Z'
        // or an offset is converted to local time; a TTime is a time of day.
        if (ATypeInfo = TypeInfo(TTime)) and TryParseJsonTime(S, D) then
          Result := VarFromDateTime(D)
        else if (ATypeInfo <> TypeInfo(TTime)) and TryParseJsonDateTime(S, D) then
          Result := VarFromDateTime(D)
        else if TryStrToFloat(S, F, TFormatSettings.Invariant) then
          Result := VarFromDateTime(F)
        else
          Fail;
      end
      else if GetTypeData(ATypeInfo)^.FloatType = ftCurr then
      begin
        if not TryStrToCurr(S, C, TFormatSettings.Invariant) then
          Fail;
        Result := C;
      end
      else
      begin
        if not TryStrToFloat(S, F, TFormatSettings.Invariant) then
          Fail;
        Result := F;
      end;
  end;
end;

{ TDbContextEntityDataSetStore }

function TDbContextEntityDataSetStore.ReadPropertyValue(AEntity: TObject;
  PropMap: TPropertyMap; out Value: Variant): Boolean;
var
  PValue: Pointer;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  V: TValue;
begin
  Result := False;
  if (AEntity = nil) or (PropMap = nil) then Exit;

  if PropMap.FieldValueOffset > 0 then
  begin
    if (PropMap.FieldOffset > 0) and not
      PBoolean(Pointer(PByte(AEntity) + PropMap.FieldOffset))^ then
    begin
      Value := Null;
      Exit(True);
    end;

    PValue := Pointer(PByte(AEntity) + PropMap.FieldValueOffset);
    case PropMap.DataType of
      ftInteger, ftAutoInc: Value := PInteger(PValue)^;
      ftSmallint: Value := PSmallInt(PValue)^;
      ftShortint: Value := PShortInt(PValue)^;
      ftByte: Value := PByte(PValue)^;
      ftWord: Value := PWord(PValue)^;
      ftLargeint: Value := PInt64(PValue)^;
      ftString, ftWideString: Value := PString(PValue)^;
      ftFloat: Value := PDouble(PValue)^;
      ftCurrency: Value := PCurrency(PValue)^;
      ftBoolean: Value := PBoolean(PValue)^;
      ftDateTime, ftDate, ftTime: Value := PDateTime(PValue)^;
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
        V := RttiProp.GetValue(AEntity);
        Value := V.AsVariant;
        Result := True;
      end;
    end;
  end;
end;

procedure TDbContextEntityDataSetStore.SetPropertyValue(AEntity: TObject;
  PropMap: TPropertyMap; const Value: Variant);
var
  Typed: Variant;
  PValue: Pointer;
  RttiType: TRttiType;
  RttiProp: TRttiProperty;
  Cleared: TValue;
begin
  if (AEntity = nil) or (PropMap = nil) then Exit;

  // The JSON value arrives as text: convert it to the property's type first,
  // with the invariant format. PropertyType is the inner type for Nullable
  // and smart properties.
  Typed := ConvertToPropertyType(Value, PropMap.PropertyType,
    PropMap.PropertyName);

  if PropMap.FieldValueOffset > 0 then
  begin
    if PropMap.FieldOffset > 0 then
      PBoolean(Pointer(PByte(AEntity) + PropMap.FieldOffset))^ :=
        not VarIsNull(Typed);

    if not VarIsNull(Typed) then
    begin
      PValue := Pointer(PByte(AEntity) + PropMap.FieldValueOffset);
      case PropMap.DataType of
        ftInteger, ftAutoInc: PInteger(PValue)^ := Typed;
        ftSmallint: PSmallInt(PValue)^ := Typed;
        ftShortint: PShortInt(PValue)^ := Typed;
        ftByte: PByte(PValue)^ := Typed;
        ftWord: PWord(PValue)^ := Typed;
        ftLargeint: PInt64(PValue)^ := Typed;
        ftString, ftWideString: PString(PValue)^ := string(Typed);
        ftFloat: PDouble(PValue)^ := Double(Typed);
        ftCurrency: PCurrency(PValue)^ := Currency(Typed);
        ftBoolean: PBoolean(PValue)^ := Boolean(Typed);
        ftDateTime, ftDate, ftTime: PDateTime(PValue)^ := TDateTime(Typed);
      end;
    end;
    // The field is written: assigning it again through RTTI would be
    // redundant, and that second assignment is what failed (#213).
    Exit;
  end;

  // No direct offset (a getter/setter method, or a property the mapping could
  // not resolve to a field): go through RTTI, with the value already typed.
  RttiType := TReflection.Context.GetType(AEntity.ClassType);
  if RttiType = nil then
    Exit;
  RttiProp := RttiType.GetProperty(PropMap.PropertyName);
  if RttiProp = nil then
    Exit;
  if VarIsNull(Typed) then
  begin
    // The zero value of the property's own type: 0 / '' for a plain
    // property, "no value" for a Nullable.
    TValue.Make(nil, RttiProp.PropertyType.Handle, Cleared);
    RttiProp.SetValue(AEntity, Cleared);
  end
  else
    TReflection.SetValue(AEntity, RttiProp, TValue.FromVariant(Typed));
end;

function TDbContextEntityDataSetStore.GetEntityKeys(AEntity: TObject;
  Map: TEntityMap): IDictionary<string, Variant>;
var
  Pair: TPair<string, TPropertyMap>;
  Val: Variant;
begin
  Result := TCollections.CreateDictionary<string, Variant>;
  if (AEntity <> nil) and (Map <> nil) then
  begin
    for Pair in Map.Properties do
    begin
      if Pair.Value.IsPK then
      begin
        if ReadPropertyValue(AEntity, Pair.Value, Val) then
          Result.Add(Pair.Key, Val);
      end;
    end;
  end;
end;

constructor TDbContextEntityDataSetStore.Create(AContinueOnError: Boolean);
begin
  inherited Create;
  FContinueOnError := AContinueOnError;
end;

function TDbContextEntityDataSetStore.StageChange(AEntityClass: TClass;
  Map: TEntityMap; const AChange: IDextJsonObject;
  ADbContext: TDbContext): TObject;
var
  StateStr: string;
  KeysObj: IDextJsonObject;
  ValuesObj: IDextJsonObject;
  EntityObj: TObject;
  Pair: TPair<string, TPropertyMap>;
begin
  Result := nil;
  StateStr := AChange.GetString('state');
  if not (SameText(StateStr, 'inserted') or SameText(StateStr, 'modified') or
    SameText(StateStr, 'deleted')) then
    Exit;

  KeysObj := nil;
  if AChange.Contains('key') then
    KeysObj := AChange.GetObject('key');
  ValuesObj := nil;
  if AChange.Contains('values') then
    ValuesObj := AChange.GetObject('values');

  EntityObj := AEntityClass.Create;
  try
    if SameText(StateStr, 'inserted') then
    begin
      if (ValuesObj <> nil) and (Map <> nil) then
      begin
        for Pair in Map.Properties do
        begin
          if ValuesObj.Contains(Pair.Key) then
            SetPropertyValue(EntityObj, Pair.Value,
              JsonMemberValue(ValuesObj, Pair.Key));
        end;
      end;

      ADbContext.ChangeTracker.Track(EntityObj, esAdded);
    end
    else
    begin
      if (KeysObj <> nil) and (Map <> nil) then
      begin
        for Pair in Map.Properties do
        begin
          if Pair.Value.IsPK and KeysObj.Contains(Pair.Key) then
            SetPropertyValue(EntityObj, Pair.Value,
              JsonMemberValue(KeysObj, Pair.Key));
        end;
      end;

      if SameText(StateStr, 'modified') then
      begin
        ADbContext.ChangeTracker.Track(EntityObj, esUnchanged);

        if (ValuesObj <> nil) and (Map <> nil) then
        begin
          for Pair in Map.Properties do
          begin
            if ValuesObj.Contains(Pair.Key) then
            begin
              SetPropertyValue(EntityObj, Pair.Value,
                JsonMemberValue(ValuesObj, Pair.Key));
              ADbContext.Entry(EntityObj).Member(Pair.Key).IsModified := True;
            end;
          end;
        end;
      end
      else
        ADbContext.ChangeTracker.Track(EntityObj, esDeleted);
    end;
  except
    // Not saved yet, so nothing else references it.
    ADbContext.ChangeTracker.Remove(EntityObj);
    EntityObj.Free;
    raise;
  end;
  Result := EntityObj;
end;

function TDbContextEntityDataSetStore.ApplyAtomic(AEntityClass: TClass;
  const AChanges: IDextJsonArray;
  ADbContext: TDbContext): IList<TApplyItemResult>;
var
  Results: IList<TApplyItemResult>;
  ItemResult: TApplyItemResult;
  Entities: IList<TObject>;
  Entity: TObject;
  Map: TEntityMap;
  FailedIndex: Integer;
  ErrorMessage: string;
  i: Integer;
begin
  Results := TCollections.CreateList<TApplyItemResult>;
  Entities := TCollections.CreateList<TObject>;
  Map := ADbContext.ModelBuilder.GetMap(AEntityClass.ClassInfo);

  // Stage every item first, then save the whole batch with one SaveChanges:
  // it runs in a single transaction (its own, or the caller's when one is
  // open) and rolls back its own transaction if any statement fails.
  FailedIndex := -1;
  ErrorMessage := '';
  try
    for i := 0 to AChanges.Count - 1 do
    begin
      FailedIndex := i;
      Entities.Add(StageChange(AEntityClass, Map, AChanges.GetObject(i),
        ADbContext));
    end;
    FailedIndex := -1;
    ADbContext.SaveChanges;
  except
    on E: Exception do
    begin
      ErrorMessage := E.Message;
      // A failed SaveChanges leaves the batch tracked: detach it, so that a
      // later SaveChanges on this context does not try to save it again.
      for Entity in Entities do
      begin
        if Entity <> nil then
          ADbContext.Detach(Entity);
      end;
    end;
  end;

  for i := 0 to AChanges.Count - 1 do
  begin
    ItemResult.Index := i;
    ItemResult.Keys := nil;
    if ErrorMessage = '' then
    begin
      ItemResult.Success := True;
      ItemResult.ErrorMessage := '';
      if (Entities[i] <> nil) and
        SameText(AChanges.GetObject(i).GetString('state'), 'inserted') then
        ItemResult.Keys := GetEntityKeys(Entities[i], Map);
    end
    else
    begin
      ItemResult.Success := False;
      if FailedIndex < 0 then
        ItemResult.ErrorMessage := 'Batch not applied: ' + ErrorMessage
      else if i = FailedIndex then
        ItemResult.ErrorMessage := ErrorMessage
      else
        ItemResult.ErrorMessage := Format('Batch not applied: item %d failed (%s)',
          [FailedIndex, ErrorMessage]);
    end;
    Results.Add(ItemResult);
  end;

  Result := Results;
end;

function TDbContextEntityDataSetStore.ApplyEachItem(AEntityClass: TClass;
  const AChanges: IDextJsonArray;
  ADbContext: TDbContext): IList<TApplyItemResult>;
var
  Results: IList<TApplyItemResult>;
  ItemResult: TApplyItemResult;
  EntityObj: TObject;
  Map: TEntityMap;
  i: Integer;
begin
  Results := TCollections.CreateList<TApplyItemResult>;
  Map := ADbContext.ModelBuilder.GetMap(AEntityClass.ClassInfo);

  for i := 0 to AChanges.Count - 1 do
  begin
    ItemResult.Index := i;
    ItemResult.Success := True;
    ItemResult.ErrorMessage := '';
    ItemResult.Keys := nil;

    EntityObj := nil;
    try
      EntityObj := StageChange(AEntityClass, Map, AChanges.GetObject(i),
        ADbContext);
      if EntityObj <> nil then
      begin
        ADbContext.SaveChanges;
        if SameText(AChanges.GetObject(i).GetString('state'), 'inserted') then
          ItemResult.Keys := GetEntityKeys(EntityObj, Map);
      end;
    except
      on E: Exception do
      begin
        ItemResult.Success := False;
        ItemResult.ErrorMessage := E.Message;
        // The failed entity is still tracked: detach it, or the next item's
        // SaveChanges would try to save it again.
        if EntityObj <> nil then
          ADbContext.Detach(EntityObj);
      end;
    end;

    Results.Add(ItemResult);
  end;

  Result := Results;
end;

function TDbContextEntityDataSetStore.ApplyChanges(AEntityClass: TClass;
  const AChanges: IDextJsonArray;
  ADbContext: TDbContext): IList<TApplyItemResult>;
begin
  if FContinueOnError then
    Result := ApplyEachItem(AEntityClass, AChanges, ADbContext)
  else
    Result := ApplyAtomic(AEntityClass, AChanges, ADbContext);
end;

{ TEntityDataSetApi }

class procedure TEntityDataSetApi.Map<T>(
  const ABuilder: IApplicationBuilder;
  const APath: string;
  ADbContextClass: TClass;
  AStore: IEntityDataSetStore);
var
  Store: IEntityDataSetStore;
begin
  if AStore <> nil then
    Store := AStore
  else
    Store := TDbContextEntityDataSetStore.Create;

  ABuilder.MapGet(APath,
    procedure(Context: IHttpContext)
    var
      Ctx: TDbContext;
      List: IList<T>;
      JsonBytes: TBytes;
    begin
      Ctx := TDbContext(ADbContextClass.Create);
      try
        List := Ctx.Entities<T>.ToList;
        JsonBytes := TDextJson.SerializeUtf8(List);
        Context.Response.SetContentType('application/json');
        Context.Response.Write(JsonBytes);
      finally
        Ctx.Free;
      end;
    end);

  ABuilder.MapPost(APath + '/apply',
    procedure(Context: IHttpContext)
    var
      Ctx: TDbContext;
      RequestBody: string;
      JO: IDextJsonObject;
      ChangesArray: IDextJsonArray;
      ApplyResults: IList<TApplyItemResult>;
      ResJson: TBytes;
      Reader: TStreamReader;
    begin
      Reader := TStreamReader.Create(Context.Request.Body, TEncoding.UTF8);
      try
        RequestBody := Reader.ReadToEnd;
      finally
        Reader.Free;
      end;

      JO := TDextJson.Provider.Parse(RequestBody) as IDextJsonObject;
      if (JO <> nil) and JO.Contains('changes') then
      begin
        ChangesArray := JO.GetArray('changes');
        Ctx := TDbContext(ADbContextClass.Create);
        try
          ApplyResults := Store.ApplyChanges(T, ChangesArray, Ctx);
          ResJson := TDextJson.SerializeUtf8(ApplyResults);
          Context.Response.SetContentType('application/json');
          Context.Response.Write(ResJson);
        finally
          Ctx.Free;
        end;
      end;
    end);
end;

end.
