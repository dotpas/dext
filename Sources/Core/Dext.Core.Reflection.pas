unit Dext.Core.Reflection;

interface

uses
  System.Character,
  System.NetEncoding,
  System.Rtti,
  System.StrUtils,
  System.SyncObjs,
  System.SysUtils,
  System.TypInfo,
  System.Variants,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Types.Lazy,
  Dext.Types.UUID;

type
  /// <summary>Metaclass for custom attributes.</summary>
  TCustomAttributeClass = class of TCustomAttribute;
  
  /// <summary>
  ///   Abstraction for property access to minimize RTTI overhead.
  /// </summary>
  IPropertyHandler = interface
    ['{6A8B9B0D-1E2F-3A4B-5C6D-7E8F9A0B1C2D}']
    function GetValue(Instance: Pointer): TValue;
    procedure SetValue(Instance: Pointer; const Value: TValue);
    function GetMember: TRttiMember;
    function GetName: string;
    function GetIsPK: Boolean;
    function GetIsAutoInc: Boolean;
    function GetColumnName: string;
    property Member: TRttiMember read GetMember;
    property Name: string read GetName;
    property IsPK: Boolean read GetIsPK;
    property IsAutoInc: Boolean read GetIsAutoInc;
    property ColumnName: string read GetColumnName;
  end;

  /// <summary>
  ///   Indicates that a record type is a Dext Smart Property.
  /// </summary>
  SmartPropAttribute = class(TCustomAttribute);

  /// <summary>
  ///   Helper to facilitate access to attributes on RTTI objects.
  /// </summary>
  TRttiObjectHelper = class helper for TRttiObject
  public
    function GetAttribute<T: TCustomAttribute>: T; overload;
    function GetAttribute(AClass: TCustomAttributeClass): TCustomAttribute; overload;
    function HasAttribute<T: TCustomAttribute>: Boolean; overload;
    function HasAttribute(AClass: TCustomAttributeClass): Boolean; overload;
  end;

  /// <summary>
  ///   Cache of structural information about a type. 
  ///   Resolves whether the type is a Smart Property (Prop, Nullable, Lazy) and identifies the encapsulated inner type.
  /// </summary>
  TTypeMetadata = class
  private
    FValidatorInterfaceType: PTypeInfo;
    FValidatorReady: Integer;
    function GetValidatorInterfaceType: PTypeInfo;
  public
    /// <summary>Encapsulated base type (e.g., T from Prop of T).</summary>
    InnerType: PTypeInfo;
    /// <summary>Indicates if the type is loaded on demand (Lazy).</summary>
    IsLazy: Boolean;
    /// <summary>Indicates if the type supports null values (Nullable).</summary>
    IsNullable: Boolean;
    /// <summary>Indicates if the type is a Dext Smart Type (Prop, Nullable, or Proxy).</summary>
    IsSmartProp: Boolean;
    /// <summary>RTTI field that controls the 'HasValue' state in Nullables.</summary>
    HasValueField: TRttiField;
    /// <summary>Original RTTI reference of the type.</summary>
    RttiType: TRttiType;
    /// <summary>RTTI field that stores the raw value (FValue).</summary>
    ValueField: TRttiField;
    /// <summary>Indicates if the type is a collection (List).</summary>
    IsList: Boolean;
    /// <summary>Indicates if the type is a dictionary.</summary>
    IsDictionary: Boolean;
    /// <summary>The type of elements in the collection.</summary>
    ElementType: PTypeInfo;
    /// <summary>Normalized name of the type (no 'T' prefix).</summary>
    NormalizedName: string;
    constructor Create;
    procedure Initialize(AType: PTypeInfo);
    destructor Destroy; override;
    property ValidatorInterfaceType: PTypeInfo read GetValidatorInterfaceType;
  private
    FHandlers: IDictionary<string, IPropertyHandler>;
    FSnakeMap: IDictionary<string, IPropertyHandler>;
    /// <summary>Multi-read exclusive-write lock for thread-safe lazy init of FHandlers and FSnakeMap.</summary>
    FLock: TMREWSync;
    /// <summary>Set to 1 (via TInterlocked) once FHandlers is fully populated. Enables lock-free reads.</summary>
    FHandlersReady: Integer;
    /// <summary>Set to 1 (via TInterlocked) once FSnakeMap is fully populated. Enables lock-free reads.</summary>
    FSnakeReady: Integer;
    function GetHandlers: IDictionary<string, IPropertyHandler>;
    function GetSnakeMap: IDictionary<string, IPropertyHandler>;
  public
    function GetHandler(const APropName: string): IPropertyHandler;
    function GetHandlerBySnakeCase(const ASnakeName: string): IPropertyHandler;
    function GetPropertyHandlers: TArray<IPropertyHandler>;
    property Handlers: IDictionary<string, IPropertyHandler> read GetHandlers;
    property SnakeMap: IDictionary<string, IPropertyHandler> read GetSnakeMap;
    property PropertyHandlers: TArray<IPropertyHandler> read GetPropertyHandlers;
  end;

  /// <summary>
  ///   High-performance reflection utilities with integrated caching. 
  ///   Optimized for generic record manipulation and value injection.
  /// </summary>
  TReflection = class
  private
    class var FCache: IDictionary<PTypeInfo, TTypeMetadata>;
    class var FContext: TRttiContext;
    class var FLock: TCriticalSection;
    class constructor Create;
    class destructor Destroy;
  public
    /// <summary>Gets or creates cached metadata for the specified type (Thread-Safe).</summary>
    class function GetMetadata(AType: PTypeInfo): TTypeMetadata; static;
    class function GetHandler(AType: PTypeInfo; const APropName: string): IPropertyHandler; static;
    /// <summary>Gets the value of a property or field from an instance using RTTI (supports SmartProps).</summary>
    class function GetValue(AInstance: TObject; const APropertyName: string): TValue; static;
    /// <summary>Sets the value of a RTTI member in an instance (supports SmartProps and auto-conversion).</summary>
    class procedure SetValue(AInstance: Pointer; AMember: TRttiMember; const AValue: TValue); static;
    /// <summary>Sets the value of a property using a path (e.g., 'Address.Street').</summary>
    class procedure SetValueByPath(AInstance: TObject; const APath: string; const AValue: TValue); static;
    /// <summary>Checks if a type represents a Dext Smart Property.</summary>
    class function IsSmartProp(AType: PTypeInfo): Boolean; static;
    /// <summary>Gets the underlying base type for a SmartProp (e.g., string for Prop of string).</summary>
    class function GetUnderlyingType(AType: PTypeInfo): PTypeInfo; overload; static;
    /// <summary>Gets the underlying base type for a TValue containing a SmartProp.</summary>
    class function GetUnderlyingType(const AValue: TValue): PTypeInfo; overload; static;
    /// <summary>Attempts to extract the raw value from a SmartProp or ILazy.</summary>
    class function TryUnwrapProp(const ASource: TValue; var ADest: TValue): Boolean; static;
    /// <summary>Attempts to wrap a raw value into a SmartProp container.</summary>
    class function TryWrapProp(var ADest: TValue; const ASource: TValue): Boolean; static;
    /// <summary>Instantiates a class using its default constructor.</summary>
    class function CreateInstance(AClass: TClass): TObject; static;
    /// <summary>Gets a raw pointer to a field inside an instance.</summary>
    class function GetFieldPtr(Instance: TObject; const FieldName: string): Pointer; static;
    /// <summary>Normalizes a field name by removing prefixes like 'F' or '_'.</summary>
    class function NormalizeFieldName(const AFieldName: string): string; static;
    /// <summary>Detects if a type represents a collection.</summary>
    class function IsListType(AType: PTypeInfo): Boolean; static;
    /// <summary>Gets the element type of a generic list.</summary>
    class function GetListElementType(AType: PTypeInfo): PTypeInfo; static;
    /// <summary>Legacy helper for collection item class types.</summary>
    class function GetCollectionItemType(AType: PTypeInfo): TClass; static;
    /// <summary>Enables detection of generic dictionary types.</summary>
    class function IsDictionaryType(AType: PTypeInfo): Boolean; static;
    /// <summary>Gets the key type of a generic dictionary.</summary>
    class function GetDictionaryKeyType(AType: PTypeInfo): PTypeInfo; static;
    /// <summary>Gets the value type of a generic dictionary.</summary>
    class function GetDictionaryValueType(AType: PTypeInfo): PTypeInfo; static;
    /// <summary>Robustly converts a string value to the specified native type.</summary>
    class function CastFromString(const AValue: string; AType: PTypeInfo): TValue; static;
    /// <summary>Gets the default value for a member, checking for [DefaultValue] attribute.</summary>
    class function GetDefaultValue(AMember: TRttiObject; AType: PTypeInfo): TValue; static;
    class property Context: TRttiContext read FContext;
  end;

  /// <summary>
  ///   Default implementation for IPropertyHandler.
  /// </summary>
  TPropertyHandler = class(TInterfacedObject, IPropertyHandler)
  private
    FMember: TRttiMember;
    FName: string;
    FIsPK: Boolean;
    FIsAutoInc: Boolean;
    FColumnName: string;
    procedure DiscoverMetadata;
  protected
    function GetMember: TRttiMember;
    function GetName: string;
    function GetIsPK: Boolean;
    function GetIsAutoInc: Boolean;
    function GetColumnName: string;
  public
    constructor Create(AMember: TRttiMember);
    function GetValue(Instance: Pointer): TValue;
    procedure SetValue(Instance: Pointer; const Value: TValue);
    property Member: TRttiMember read GetMember;
    property Name: string read GetName;
    property IsPK: Boolean read GetIsPK;
    property IsAutoInc: Boolean read GetIsAutoInc;
    property ColumnName: string read GetColumnName;
  end;

implementation

uses
  Dext.Core.Activator,
  Dext.Core.DateUtils,
  Dext.Core.ValueConverters,
  Dext.DI.Core;

{ TPropertyHandler }
 
constructor TPropertyHandler.Create(AMember: TRttiMember);
begin
  inherited Create;
  FMember := AMember;
  FName := AMember.Name;
  DiscoverMetadata;
end;
 
procedure TPropertyHandler.DiscoverMetadata;
var
  Attr: TCustomAttribute;
  AttrName: string;
  Prop: TRttiProperty;
  Val: string;
begin
  FIsPK := False;
  FIsAutoInc := False;
  FColumnName := FName;

  for Attr in FMember.GetAttributes do
  begin
    AttrName := Attr.ClassName;
    if SameText(AttrName, 'PrimaryKeyAttribute') or SameText(AttrName, 'PKAttribute') or SameText(AttrName, 'PK') then
      FIsPK := True
    else if SameText(AttrName, 'AutoIncAttribute') or SameText(AttrName, 'AutoInc') then
      FIsAutoInc := True
    else if SameText(AttrName, 'ColumnAttribute') then
    begin
      // Use RTTI to get the 'Name' property of the ColumnAttribute without depending on its unit
      Prop := TReflection.Context.GetType(Attr.ClassType).GetProperty('Name');
      if Prop <> nil then
      begin
        Val := Prop.GetValue(Attr).AsString;
        if Val <> '' then
          FColumnName := Val;
      end;
    end;
  end;
end;

function TPropertyHandler.GetMember: TRttiMember;
begin
  Result := FMember;
end;

function TPropertyHandler.GetName: string;
begin
  Result := FName;
end;

function TPropertyHandler.GetIsPK: Boolean;
begin
  Result := FIsPK;
end;

function TPropertyHandler.GetIsAutoInc: Boolean;
begin
  Result := FIsAutoInc;
end;

function TPropertyHandler.GetColumnName: string;
begin
  Result := FColumnName;
end;
 
function TPropertyHandler.GetValue(Instance: Pointer): TValue;
begin
  if FMember is TRttiProperty then
    Result := TRttiProperty(FMember).GetValue(Instance)
  else if FMember is TRttiField then
    Result := TRttiField(FMember).GetValue(Instance)
  else
    Result := TValue.Empty;
end;
 
procedure TPropertyHandler.SetValue(Instance: Pointer; const Value: TValue);
var
  TargetType: PTypeInfo;
  Converted: TValue;
begin
  TargetType := nil;
  if FMember is TRttiProperty then
    TargetType := TRttiProperty(FMember).PropertyType.Handle
  else if FMember is TRttiField then
    TargetType := TRttiField(FMember).FieldType.Handle;

  Converted := TValueConverter.Convert(Value, TargetType);
  
  // Align TypeInfo pointers for identical record types across DCU boundaries
  if (Converted.TypeInfo <> TargetType) and (Converted.TypeInfo <> nil) and (TargetType <> nil) and
     (Converted.TypeInfo.Kind = tkRecord) and (TargetType.Kind = tkRecord) and
     SameText(string(Converted.TypeInfo.Name), string(TargetType.Name)) then
  begin
    TValue.Make(Converted.GetReferenceToRawData, TargetType, Converted);
  end;

  if FMember is TRttiProperty then
    TRttiProperty(FMember).SetValue(Instance, Converted)
  else if FMember is TRttiField then
    TRttiField(FMember).SetValue(Instance, Converted);
end;
 
{ TRttiObjectHelper }

function TRttiObjectHelper.GetAttribute<T>: T;
var
  Attr: TCustomAttribute;
begin
  Result := nil;
  for Attr in GetAttributes do if Attr is T then Exit(T(Attr));
end;

function TRttiObjectHelper.GetAttribute(AClass: TCustomAttributeClass): TCustomAttribute;
var
  Attr: TCustomAttribute;
begin
  Result := nil;
  for Attr in GetAttributes do if Attr.InheritsFrom(AClass) then Exit(Attr);
end;

function TRttiObjectHelper.HasAttribute<T>: Boolean;
begin
  Result := GetAttribute<T> <> nil;
end;

function TRttiObjectHelper.HasAttribute(AClass: TCustomAttributeClass): Boolean;
begin
  Result := GetAttribute(AClass) <> nil;
end;

{ TTypeMetadata }

constructor TTypeMetadata.Create;
begin
  inherited Create;
  FLock := TMREWSync.Create;
  FValidatorReady := 0;
  FValidatorInterfaceType := nil;
end;

procedure TTypeMetadata.Initialize(AType: PTypeInfo);
var
  TypeName: string;
  LGenParts: TArray<string>;
  LTMark: Integer;
  Field: TRttiField;
  LFieldName: string;
  LInnerName: string;
  LInnerRtti: TRttiType;
  TempType: TRttiType;
  ImplIntf: TRttiInterfaceType;
  ValProp: TRttiProperty;
  LElementName: string;
  LElementRtti: TRttiType;
  AddM: TRttiMethod;
  Intf: TRttiInterfaceType;
  OuterName: string;
  CleanName: string;
  CleanedInner: string;
  CleanedTempName: string;
  CleanedTempQual: string;

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
  RttiType := TReflection.FContext.GetType(AType);
  IsSmartProp := False;
  IsLazy := False;
  IsNullable := False;
  ValueField := nil;
  HasValueField := nil;
  InnerType := nil;
  IsList := False;
  IsDictionary := False;
  ElementType := nil;
  NormalizedName := '';

  if RttiType = nil then Exit;

  TypeName := RttiType.Name;
  NormalizedName := TReflection.NormalizeFieldName(TypeName);
  if (RttiType.TypeKind = tkRecord) then
  begin
    CleanName := CleanTypeName(TypeName);
    OuterName := CleanName;
    LTMark := CleanName.IndexOf('<');
    if LTMark > 0 then
      OuterName := CleanName.Substring(0, LTMark);

    IsNullable := OuterName.Contains('Nullable');
    IsSmartProp := RttiType.HasAttribute(SmartPropAttribute);

    for Field in RttiType.GetFields do
    begin
      LFieldName := Field.Name;
      if SameText(LFieldName, 'FValue') or SameText(LFieldName, 'Value') then
      begin
        ValueField := Field;
        if (Field.FieldType <> nil) then
          InnerType := Field.FieldType.Handle;
        IsSmartProp := True;
      end
      else if LFieldName.ToLower.Contains('hasvalue') or SameText(LFieldName, 'FInfo') or SameText(LFieldName, 'Info') then
        HasValueField := Field
      else if SameText(LFieldName, 'FInstance') or ((Field.FieldType <> nil) and string(Field.FieldType.Handle.Name).Contains('ILazy')) then
      begin
        IsLazy := True;
        ValueField := Field;
        if (InnerType = nil) and (Field.FieldType <> nil) then
          InnerType := Field.FieldType.Handle;
      end;
    end;

    // Fallback for generic records without explicit attributes
    if not (IsSmartProp or IsLazy) then
    begin
       if (OuterName.Contains('Prop') or OuterName.Contains('Nullable') or
           OuterName.Contains('Proxy') or OuterName.Contains('TProxy')) then
       begin
         IsSmartProp := True;
         if ValueField = nil then ValueField := RttiType.GetField('FValue');
         if ValueField = nil then ValueField := RttiType.GetField('FProxy');
         if ValueField = nil then ValueField := RttiType.GetField('Value');
       end
       else if OuterName.Contains('Lazy') then
       begin
         IsLazy := True;
         if ValueField = nil then ValueField := RttiType.GetField('FInstance');
       end;
    end;
    
     // Extraction of InnerType for generic records (Prop<T>, Lazy<T>, Nullable<T>)
     if (InnerType = nil) or (string(InnerType.Name).Contains('ILazy')) then
     begin
       LTMark := TypeName.IndexOf('<');
       if (LTMark > 0) and TypeName.EndsWith('>') then
       begin
         LInnerName := TypeName.Substring(LTMark + 1, TypeName.Length - LTMark - 2).Trim;
         CleanedInner := CleanTypeName(LInnerName).Replace(' ', '');
          
         // First attempt exact find using LInnerName (which might have unit name namespaces)
         LInnerRtti := TReflection.FContext.FindType(LInnerName);
         if LInnerRtti = nil then
           LInnerRtti := TReflection.FContext.FindType(CleanedInner);
         if LInnerRtti = nil then
           LInnerRtti := TReflection.FContext.FindType('System.' + CleanedInner);
         if LInnerRtti = nil then
         begin
           for TempType in TReflection.FContext.GetTypes do
           begin
             CleanedTempName := CleanTypeName(TempType.Name).Replace(' ', '');
             CleanedTempQual := CleanTypeName(TempType.QualifiedName).Replace(' ', '');
             if SameText(CleanedTempName, CleanedInner) or
                SameText(CleanedTempQual, CleanedInner) then
             begin
               LInnerRtti := TempType;
               Break;
             end;
           end;
         end;
         if LInnerRtti <> nil then
           InnerType := LInnerRtti.Handle;
       end;
     end;

    if (InnerType = nil) and (ValueField <> nil) and (ValueField.FieldType <> nil) then
      InnerType := ValueField.FieldType.Handle;
  end;

  // 2. Detect Collections (Inheritance and Methods)
  if (RttiType.TypeKind in [tkClass, tkInterface]) then
  begin
    // Check for List patterns
    if (TypeName.Contains('List<') or TypeName.Contains('Collection<') or
        TypeName.Contains('IEnumerable<') or TypeName.Contains('IList<') or
        TypeName.Contains('TList<') or TypeName.Contains('TSmartList<') or
        TypeName.EndsWith('List') or
        (TypeName.Contains('<') and (RttiType.GetMethod('Add') <> nil))) then
    begin
      IsList := True;
    end;

    // Check for Dictionary patterns
    if TypeName.Contains('IDictionary<') or TypeName.Contains('TDictionary<') then
    begin
      IsDictionary := True;
    end;

    // Deep scanning for interfaces if name-based check is not enough
    if not (IsList or IsDictionary or IsLazy) then
    begin
       if RttiType is TRttiInterfaceType then
       begin
          Intf := TRttiInterfaceType(RttiType);
          while Intf <> nil do
          begin
            if Intf.Name.Contains('IList<') or
               Intf.Name.Contains('IEnumerable<') or
               Intf.Name.Contains('List<') or
               Intf.Name.Contains('Collection<') or
               (Intf.GetMethod('Add') <> nil) then
            begin
              IsList := True;
              Break;
            end;
            if Intf.Name.Contains('IDictionary<') then
            begin
              IsDictionary := True;
              Break;
            end;
            if Intf.Name.Contains('ILazy') then
            begin
              IsLazy := True;
              Break;
            end;
            if (Intf.BaseType <> nil) and
               (Intf.BaseType is TRttiInterfaceType) then
              Intf := TRttiInterfaceType(Intf.BaseType)
            else
              Intf := nil;
          end;
       end
       else if RttiType is TRttiInstanceType then
       begin
          for ImplIntf in
            TRttiInstanceType(RttiType).GetImplementedInterfaces do
          begin
            if ImplIntf.Name.Contains('IList<') or
               ImplIntf.Name.Contains('IEnumerable<') or
               ImplIntf.Name.Contains('List<') or
               ImplIntf.Name.Contains('Collection<') or
               (ImplIntf.GetMethod('Add') <> nil) then
            begin
              IsList := True;
              Break;
            end;
            if ImplIntf.Name.Contains('IDictionary<') then
            begin
              IsDictionary := True;
              Break;
            end;
            if ImplIntf.Name.Contains('ILazy') then
            begin
              IsLazy := True;
              Break;
            end;
          end;
       end;
    end;
    
    // If discovered as Lazy, try to extract InnerType
    if IsLazy and (InnerType = nil) then
    begin
       LTMark := TypeName.IndexOf('<');
       if (LTMark > 0) and TypeName.EndsWith('>') then
       begin
          LInnerName := TypeName.Substring(LTMark + 1, TypeName.Length - LTMark - 2).Trim;
          LInnerRtti := TReflection.FContext.FindType(LInnerName);
          if LInnerRtti = nil then LInnerRtti := TReflection.FContext.FindType('System.' + LInnerName);
          if LInnerRtti <> nil then InnerType := LInnerRtti.Handle;
       end;
       
       if InnerType = nil then
       begin
          ValProp := RttiType.GetProperty('Value');
          if (ValProp <> nil) and (ValProp.PropertyType <> nil) then 
            InnerType := ValProp.PropertyType.Handle;
       end;
    end;

    // If discovered as collection, try to extract ElementType
    if IsList or IsDictionary then
    begin
      LTMark := TypeName.IndexOf('<');
      if (LTMark > 0) and TypeName.EndsWith('>') then
      begin
        LGenParts := TypeName.Substring(LTMark + 1, TypeName.Length - LTMark - 2).Split([',']);
        if Length(LGenParts) > 0 then
        begin
          LElementName := LGenParts[High(LGenParts)].Trim; // Last part is usually the element or value
          LElementRtti := TReflection.FContext.FindType(LElementName);
          if LElementRtti = nil then LElementRtti := TReflection.FContext.FindType('System.' + LElementName);
          if LElementRtti <> nil then ElementType := LElementRtti.Handle;
        end;
      end;
      
      // Fallback: look at 'Add' method or 'Items' property
      if ElementType = nil then
      begin
        AddM := RttiType.GetMethod('Add');
        if (AddM <> nil) and (Length(AddM.GetParameters) > 0) and (AddM.GetParameters[High(AddM.GetParameters)].ParamType <> nil) then
          ElementType := AddM.GetParameters[High(AddM.GetParameters)].ParamType.Handle;
      end;
    end;
  end;

end;

function TTypeMetadata.GetValidatorInterfaceType: PTypeInfo;
var
  LNormName: string;
  LFullName: string;
  LType: TRttiType;
begin
  if FValidatorReady = 0 then
  begin
    FLock.BeginWrite;
    try
      if FValidatorReady = 0 then
      begin
        FValidatorInterfaceType := nil;
        if RttiType <> nil then
        begin
          // Delphi RTTI exposes generic interfaces with the full type name including
          // the 'T' prefix (e.g. 'IValidator<TValidatedEntity>').
          // NormalizedName strips the T prefix (e.g. 'ValidatedEntity').
          // We match both to be safe.
          LNormName := NormalizedName;  // 'ValidatedEntity'
          LFullName := RttiType.Name;   // 'TValidatedEntity'

          for LType in TReflection.FContext.GetTypes do
          begin
            // Matching logic: only interfaces that start with 'IValidator'
            if (LType is TRttiInterfaceType) and LType.Name.StartsWith('IValidator') then
            begin
              // Match by full RTTI name ('TValidatedEntity') OR normalized ('ValidatedEntity')
              if LType.Name.EndsWith('<' + LFullName + '>') or
                 LType.Name.EndsWith('<' + LNormName + '>') or
                 LType.Name.EndsWith('.' + LFullName + '>') or
                 LType.Name.EndsWith('.' + LNormName + '>') then
              begin
                FValidatorInterfaceType := LType.Handle;
                Break;
              end;
            end;
          end;
        end;
        TInterlocked.Exchange(FValidatorReady, 1);
      end;
    finally
      FLock.EndWrite;
    end;
  end;
  Result := FValidatorInterfaceType;
end;

destructor TTypeMetadata.Destroy;
begin
  FHandlers := nil;
  FSnakeMap := nil;
  FLock.Free;
  inherited;
end;

function TTypeMetadata.GetHandlers: IDictionary<string, IPropertyHandler>;
begin
  // Lock-free fast path: if FHandlersReady=1, the dictionary is stable (no more writes)
  if FHandlersReady = 1 then
    Exit(FHandlers);

  // First access: exclusive lock + initialize
  FLock.BeginWrite;
  try
    if FHandlers = nil then
      FHandlers := TCollections.CreateDictionary<string, IPropertyHandler>(True);
    Result := FHandlers;
  finally
    FLock.EndWrite;
  end;
end;

function TTypeMetadata.GetSnakeMap: IDictionary<string, IPropertyHandler>;
begin
  // Lock-free fast path: if FSnakeReady=1, the dictionary is stable (no more writes)
  if FSnakeReady = 1 then
    Exit(FSnakeMap);

  // First access: exclusive lock + initialize
  FLock.BeginWrite;
  try
    if FSnakeMap = nil then
      FSnakeMap := TCollections.CreateDictionary<string, IPropertyHandler>(True);
    Result := FSnakeMap;
  finally
    FLock.EndWrite;
  end;
end;

function TTypeMetadata.GetHandlerBySnakeCase(const ASnakeName: string): IPropertyHandler;
var
  LSnake: string;
  LHandler: IPropertyHandler;
  Prop: TRttiProperty;
begin
  // Lock-free fast path: map fully populated, direct read (no lock needed)
  if FSnakeReady = 1 then
  begin
    FSnakeMap.TryGetValue(ASnakeName, Result);
    Exit;
  end;

  // Slow write path: populate the entire snake map once, then mark it ready
  FLock.BeginWrite;
  try
    if FSnakeMap = nil then
      FSnakeMap := TCollections.CreateDictionary<string, IPropertyHandler>(True);
    // Double-check after acquiring the lock
    if FSnakeReady = 1 then
    begin
      FSnakeMap.TryGetValue(ASnakeName, Result);
      Exit;
    end;

    // Populate entire snake map from RTTI properties
    if RttiType <> nil then
    begin
      if FHandlers = nil then
        FHandlers := TCollections.CreateDictionary<string, IPropertyHandler>(True);
      for Prop in RttiType.GetProperties do
      begin
        LSnake := Prop.Name.ToLower;
        if not FSnakeMap.ContainsKey(LSnake) then
        begin
          if not FHandlers.TryGetValue(Prop.Name, LHandler) then
          begin
            LHandler := TPropertyHandler.Create(Prop);
            FHandlers.Add(Prop.Name, LHandler);
          end;
          FSnakeMap.Add(LSnake, LHandler);
        end;
      end;
    end;
    // Mark both maps as ready (full memory barrier via TInterlocked)
    TInterlocked.Exchange(FHandlersReady, 1);
    TInterlocked.Exchange(FSnakeReady, 1);
    FSnakeMap.TryGetValue(ASnakeName, Result);
  finally
    FLock.EndWrite;
  end;
end;

function TTypeMetadata.GetHandler(const APropName: string): IPropertyHandler;
var
  Member: TRttiMember;
begin
  // Lock-free fast path: once FHandlersReady=1, FHandlers is fully populated
  // and will only be read - no lock needed
  if FHandlersReady = 1 then
  begin
    FHandlers.TryGetValue(APropName, Result);
    Exit;
  end;

  // Slow write path: first miss goes through the exclusive lock
  FLock.BeginWrite;
  try
    if FHandlers = nil then
      FHandlers := TCollections.CreateDictionary<string, IPropertyHandler>(True);
    // Double-checked locking: another thread may have populated it already
    if FHandlers.TryGetValue(APropName, Result) then
      Exit;

    Member := nil;
    if RttiType <> nil then
    begin
      Member := RttiType.GetProperty(APropName);
      if Member = nil then
        Member := RttiType.GetField(APropName);
    end;

    if Member <> nil then
    begin
      Result := TPropertyHandler.Create(Member);
      FHandlers.Add(APropName, Result);
      // Signal that this handler is now permanently cached.
      // NOTE: FHandlersReady=1 is a stronger guarantee set by GetHandlerBySnakeCase
      // (which populates ALL handlers at once). For individual GetHandler calls,
      // we keep the write lock for safety - reads outside the lock only happen
      // when the full population has completed.
    end;
  finally
    FLock.EndWrite;
  end;
end;

function TTypeMetadata.GetPropertyHandlers: TArray<IPropertyHandler>;
var
  LHandlers: IList<IPropertyHandler>;
  Prop: TRttiProperty;
begin
  LHandlers := TCollections.CreateList<IPropertyHandler>;
  if RttiType <> nil then
    for Prop in RttiType.GetProperties do
      LHandlers.Add(GetHandler(Prop.Name));
  Result := LHandlers.ToArray;
end;

{ TReflection }

class constructor TReflection.Create;
begin
  FContext := TRttiContext.Create;
  FCache := TCollections.CreateDictionary<PTypeInfo, TTypeMetadata>(True);
  FLock := TCriticalSection.Create;
end;

class destructor TReflection.Destroy;
begin
  FCache := nil;
  FLock.Free;
  FContext.Free;
end;

class function TReflection.GetMetadata(AType: PTypeInfo): TTypeMetadata;
begin
  FLock.Enter;
  try
    if FCache.TryGetValue(AType, Result) then Exit;

    Result := TTypeMetadata.Create;
    FCache.Add(AType, Result);
    
    try
      Result.Initialize(AType);
    except
      FCache.Remove(AType);
      Result.Free;
      raise;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TReflection.GetHandler(AType: PTypeInfo; const APropName: string): IPropertyHandler;
begin
  Result := GetMetadata(AType).GetHandler(APropName);
end;

class procedure TReflection.SetValue(
  AInstance: Pointer;
  AMember: TRttiMember;
  const AValue: TValue
);
var
  TargetType: PTypeInfo;
  Meta: TTypeMetadata;
  Current, Converted: TValue;
begin
  if (AInstance = nil) or (AMember = nil) then Exit;
  
  if AMember is TRttiProperty then
    TargetType := TRttiProperty(AMember).PropertyType.Handle
  else if AMember is TRttiField then
    TargetType := TRttiField(AMember).FieldType.Handle
  else
    Exit;

  // Align TypeInfo pointers for identical record types to avoid EInvalidCast across DCU boundaries
  if (AValue.TypeInfo <> TargetType) and (AValue.TypeInfo <> nil)
     and (TargetType <> nil)
     and (AValue.TypeInfo^.Kind = tkRecord)
     and (TargetType^.Kind = tkRecord)
     and SameText(string(AValue.TypeInfo^.Name),
                  string(TargetType^.Name)) then
  begin
    TValue.Make(AValue.GetReferenceToRawData, TargetType, Converted);
  end
  else
    Converted := AValue;

  Meta := TReflection.GetMetadata(TargetType);
  if Meta.IsSmartProp or Meta.IsLazy then
  begin
    // Fast path: if the value is already of the target type, just set it directly
    if Converted.TypeInfo = TargetType then
    begin
      if AMember is TRttiProperty then
        TRttiProperty(AMember).SetValue(AInstance, Converted)
      else if AMember is TRttiField then
        TRttiField(AMember).SetValue(AInstance, Converted);
      Exit;
    end;

    Current := TValue.Empty;
    if AMember is TRttiProperty then
      Current := TRttiProperty(AMember).GetValue(AInstance)
    else if AMember is TRttiField then
      Current := TRttiField(AMember).GetValue(AInstance);
    
    if TReflection.TryWrapProp(Current, Converted) then
    begin
      if AMember is TRttiProperty then
        TRttiProperty(AMember).SetValue(AInstance, Current)
      else if AMember is TRttiField then
        TRttiField(AMember).SetValue(AInstance, Current);
      Exit;
    end;
  end;

  Converted := TValueConverter.Convert(Converted, TargetType);

  if AMember is TRttiProperty then
    TRttiProperty(AMember).SetValue(AInstance, Converted)
  else if AMember is TRttiField then
    TRttiField(AMember).SetValue(AInstance, Converted);
end;

class function TReflection.GetValue(AInstance: TObject; const APropertyName: string): TValue;
var
  RType: TRttiType;
  Prop: TRttiProperty;
  Field: TRttiField;
  Raw, Unwrapped: TValue;
begin
  Result := TValue.Empty;
  if AInstance = nil then Exit;
  
  RType := TReflection.FContext.GetType(AInstance.ClassType);
  if RType = nil then Exit;

  // 1. Try Property
  Prop := RType.GetProperty(APropertyName);
  if Prop <> nil then
    Raw := Prop.GetValue(Pointer(AInstance))
  else
  begin
    // 2. Try Field (FPropName or PropName)
    Field := RType.GetField(APropertyName);
    if Field = nil then
      Field := RType.GetField('F' + APropertyName);
      
    if Field <> nil then
      Raw := Field.GetValue(Pointer(AInstance))
    else
      Exit;
  end;

  if TReflection.TryUnwrapProp(Raw, Unwrapped) then
    Result := Unwrapped
  else
    Result := Raw;
end;

class procedure TReflection.SetValueByPath(AInstance: TObject; const APath: string; const AValue: TValue);
var
  Parts: TArray<string>;
  Prop: TRttiProperty;
  CurObj: TObject;
  SubPath: string;
begin
  if (AInstance = nil) or (APath = '') then Exit;
  
  // Support both . and _ as separators
  if APath.Contains('_') then Parts := APath.Split(['_'])
  else Parts := APath.Split(['.']);

  if Length(Parts) = 1 then
  begin
    Prop := TReflection.FContext.GetType(AInstance.ClassInfo).GetProperty(Parts[0]);
    if Prop <> nil then SetValue(Pointer(AInstance), Prop, AValue);
    Exit;
  end;

  // Level 1: Find the first part
  Prop := TReflection.FContext.GetType(AInstance.ClassInfo).GetProperty(Parts[0]);
  if (Prop <> nil) and (Prop.PropertyType.TypeKind = tkClass) then
  begin
    CurObj := Prop.GetValue(Pointer(AInstance)).AsObject;
    if CurObj = nil then
    begin
       // Auto-instantiate nested classes
       CurObj := TActivator.CreateInstance(GetTypeData(Prop.PropertyType.Handle)^.ClassType, []);
       Prop.SetValue(Pointer(AInstance), CurObj);
    end;
    
    // Recursive call for the rest of the path
    SubPath := string.Join('.', Parts, 1, Length(Parts) - 1);
    SetValueByPath(CurObj, SubPath, AValue);
  end;
end;

class function TReflection.IsSmartProp(AType: PTypeInfo): Boolean;
var
  Meta: TTypeMetadata;
begin
  Meta := GetMetadata(AType);
  Result := Meta.IsSmartProp or Meta.IsLazy;
end;

class function TReflection.GetUnderlyingType(AType: PTypeInfo): PTypeInfo;
begin
  Result := GetMetadata(AType).InnerType;
  if Result = nil then
    Result := AType;
end;

class function TReflection.GetUnderlyingType(const AValue: TValue): PTypeInfo;
var
  LLazy: ILazy;
  LIntf: IInterface;
begin
  Result := nil;
  // If it's an interface, check if it's an ILazy to get TargetType without loading
  if AValue.Kind = tkInterface then
  begin
    LIntf := AValue.AsInterface;
    if (LIntf <> nil) and (LIntf.QueryInterface(ILazy, LLazy) = S_OK) then
      Exit(LLazy.TargetType);
  end;

  // Fallback to static type information
  if AValue.TypeInfo <> nil then
    Result := GetUnderlyingType(AValue.TypeInfo);

  if Result = nil then
    Result := AValue.TypeInfo;
end;

class function TReflection.TryUnwrapProp(const ASource: TValue; var ADest: TValue): Boolean;
var
  PData: Pointer;
  Unwrapped: TValue;
  LIntf: IInterface;
  LLazy: ILazy;
  Meta: TTypeMetadata;
begin
  ADest := ASource;
  Result := False;

  if ASource.TypeInfo = nil then Exit;

  // Direct support for ILazy interface
  if ASource.Kind = tkInterface then
  begin
    LIntf := ASource.AsInterface;
    if (LIntf <> nil) and (LIntf.QueryInterface(ILazy, LLazy) = S_OK) then
    begin
       Unwrapped := LLazy.Value;
       if TryUnwrapProp(Unwrapped, ADest) then
         Result := True
       else
       begin
         ADest := Unwrapped;
         Result := True;
       end;
       Exit;
    end;
  end;

  // For other types, only unwrap if it is a registered SmartProp (Record or Class)
  if not (ASource.Kind in [tkRecord, tkClass]) then Exit;

  Meta := GetMetadata(ASource.TypeInfo);
  if (Meta.IsSmartProp or Meta.IsLazy) and (Meta.ValueField <> nil) then
  begin
    PData := ASource.GetReferenceToRawData;
    if PData = nil then Exit;

    // For Nullable<T>, check HasValue first
    if Meta.IsNullable and (Meta.HasValueField <> nil) then
    begin
        if not Meta.HasValueField.GetValue(PData).AsBoolean then
        begin
          ADest := TValue.Empty;
          Result := True;
          Exit;
        end;
    end;

    Unwrapped := Meta.ValueField.GetValue(PData);
    ADest := Unwrapped;

    // If unwrapped is an ILazy interface, extract its value
    if (Unwrapped.Kind = tkInterface) then
    begin
       LIntf := Unwrapped.AsInterface;
       if (LIntf <> nil) and (LIntf.QueryInterface(ILazy, LLazy) = S_OK) then
       begin
          Unwrapped := LLazy.Value;
       end;
    end;
    // RECURSIVE UNWRAP
    if TryUnwrapProp(Unwrapped, ADest) then
      Result := True
    else
    begin
      ADest := Unwrapped;
      Result := True;
    end;
  end;
end;

class function TReflection.TryWrapProp(var ADest: TValue; const ASource: TValue): Boolean;
var
  PData: Pointer;
  Meta: TTypeMetadata;
  Converted: TValue;
begin
  Result := False;
  if ADest.TypeInfo = nil then Exit;

  Meta := GetMetadata(ADest.TypeInfo);
  if Meta.IsSmartProp and (Meta.ValueField <> nil) then
  begin
    PData := ADest.GetReferenceToRawData;
    if PData <> nil then
    begin
      // If it's Nullable, also set HasValue
      if Meta.IsNullable and (Meta.HasValueField <> nil) then
        Meta.HasValueField.SetValue(PData, not ASource.IsEmpty);

      if not ASource.IsEmpty then
      begin
        Converted := TValueConverter.Convert(ASource, Meta.InnerType);
        Meta.ValueField.SetValue(PData, Converted);
      end
      else
      begin
        if (Meta.InnerType <> nil) and (Meta.InnerType.Kind in [tkString, tkUString, tkWString, tkLString, tkChar, tkWChar]) then
          Converted := TValue.FromVariant('')
        else if Meta.InnerType <> nil then
          Converted := TValueConverter.Convert(TValue.FromVariant(0), Meta.InnerType)
        else
          Converted := TValue.FromVariant('');

        Meta.ValueField.SetValue(PData, Converted);
      end;
      Result := True;
    end;
  end;
end;

class function TReflection.CreateInstance(AClass: TClass): TObject;
begin
  Result := TActivator.CreateInstance(AClass, []);
end;

class function TReflection.GetFieldPtr(Instance: TObject; const FieldName: string): Pointer;
var
  RField: TRttiField;
begin
  RField := FContext.GetType(Instance.ClassType).GetField(FieldName);
  if RField <> nil then
    Result := PByte(Instance) + RField.Offset
  else
    Result := nil;
end;

class function TReflection.NormalizeFieldName(const AFieldName: string): string;
begin
  Result := AFieldName;
  
  // Remove 'F' or 'T' prefixes if followed by an uppercase letter (Chars is 0-indexed)
  if (Result.Length > 1) and (Result.Chars[1].IsUpper) and ((Result.Chars[0] = 'F') or (Result.Chars[0] = 'T')) then
    Result := Result.Substring(1);

  // Normalize Smart Property prefixes: Lazy, Prop, Proxy, Nullable
  if Result.StartsWith('Lazy', True) and (Result.Length > 4) and (Char.IsUpper(Result, 4)) then
    Result := Result.Substring(4)
  else if Result.StartsWith('Prop', True) and (Result.Length > 4) and (Char.IsUpper(Result, 4)) then
    Result := Result.Substring(4)
  else if Result.StartsWith('Proxy', True) and (Result.Length > 5) and (Char.IsUpper(Result, 5)) then
    Result := Result.Substring(5)
  else if Result.StartsWith('Nullable', True) and (Result.Length > 8) and (Char.IsUpper(Result, 8)) then
    Result := Result.Substring(8);
end;

class function TReflection.IsListType(AType: PTypeInfo): Boolean;
begin
  Result := GetMetadata(AType).IsList;
end;

class function TReflection.GetListElementType(AType: PTypeInfo): PTypeInfo;
begin
  Result := GetMetadata(AType).ElementType;
end;

class function TReflection.GetCollectionItemType(AType: PTypeInfo): TClass;
var
  LElementType: PTypeInfo;
  LRtti: TRttiType;
begin
  Result := nil;
  LElementType := GetListElementType(AType);
  if LElementType <> nil then
  begin
    LRtti := FContext.GetType(LElementType);
    if LRtti is TRttiInstanceType then
      Result := TRttiInstanceType(LRtti).MetaclassType;
  end;
end;

class function TReflection.IsDictionaryType(AType: PTypeInfo): Boolean;
begin
  Result := GetMetadata(AType).IsDictionary;
end;

class function TReflection.GetDictionaryKeyType(AType: PTypeInfo): PTypeInfo;
var
  TypeName: string;
  LTMark: Integer;
  LGenParts: TArray<string>;
  LKeyName: string;
  LRtti: TRttiType;
begin
  Result := nil;
  if not IsDictionaryType(AType) then Exit;
  
  TypeName := string(AType^.Name);
  LTMark := TypeName.IndexOf('<');
  if LTMark > 0 then
  begin
    LGenParts := TypeName.Substring(LTMark + 1, TypeName.Length - LTMark - 2).Split([',']);
    if Length(LGenParts) >= 1 then
    begin
      LKeyName := LGenParts[0].Trim;
      LRtti := FContext.FindType(LKeyName);
      if LRtti = nil then LRtti := FContext.FindType('System.' + LKeyName);
      if LRtti <> nil then Result := LRtti.Handle;
    end;
  end;
end;

class function TReflection.GetDictionaryValueType(AType: PTypeInfo): PTypeInfo;
begin
  Result := GetListElementType(AType);
end;

class function TReflection.CastFromString(const AValue: string; AType: PTypeInfo): TValue;
var
  G: TGUID;
  DecodedValue: string;
  DTVal: TDateTime;
  Parsed: Boolean;
  S: string;
  Y, M, D, H, N, Sc: Integer;
  F: Double;
  B: Boolean;
  GuidStr: string;
  U: TUUID;
begin
  if AValue = '' then
  begin
    TValue.Make(nil, AType, Result);
    Exit;
  end;

  // Auto URL Decode
  DecodedValue := TNetEncoding.URL.Decode(AValue);

  try
    case AType.Kind of
      tkInteger, tkInt64: Result := TValue.FromOrdinal(AType, StrToInt64Def(DecodedValue, 0));
      tkFloat:
        begin
          if (AType = TypeInfo(TDateTime)) or (AType = TypeInfo(TDate)) or (AType = TypeInfo(TTime)) then
          begin
            // Parse date string in a locale-independent way.
            // Supports ISO 8601: 'yyyy-mm-dd', 'yyyy-mm-ddThh:nn:ss', 'yyyy-mm-dd hh:nn:ss'
            DTVal := 0;
            S := DecodedValue.Trim;
            // The JSON forms first (Dext.Core.DateUtils): milliseconds, and a
            // 'Z' or an offset converted to local time
            if AType = TypeInfo(TTime) then
              Parsed := TryParseJsonTime(S, DTVal)
            else
              Parsed := TryParseJsonDateTime(S, DTVal);
            // Check for ISO date pattern: starts with 4 digits, dash, 2 digits, dash, 2 digits
            if not Parsed and (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') then
            begin
              try
                Y := StrToInt(Copy(S, 1, 4));
                M := StrToInt(Copy(S, 6, 2));
                D := StrToInt(Copy(S, 9, 2));
                DTVal := EncodeDate(Y, M, D);
                // Check for time component: 'yyyy-mm-ddThh:nn:ss' or 'yyyy-mm-dd hh:nn:ss'
                if (Length(S) >= 19) and CharInSet(S[11], ['T', 't', ' ']) then
                begin
                  H := StrToIntDef(Copy(S, 12, 2), 0);
                  N := StrToIntDef(Copy(S, 15, 2), 0);
                  Sc := StrToIntDef(Copy(S, 18, 2), 0);
                  DTVal := DTVal + EncodeTime(H, N, Sc, 0);
                end;
                Parsed := True;
              except
                // Fall through to locale-based parsing
              end;
            end;
            if not Parsed then
              DTVal := StrToDateTimeDef(S, 0);
            Result := TValue.From<TDateTime>(DTVal);
          end
          else
          begin
            if TryStrToFloat(DecodedValue, F, TFormatSettings.Invariant) then
              Result := TValue.From<Double>(F)
            else
              Result := TValue.From<Double>(0);
          end;
        end;
      tkString, tkLString, tkWString, tkUString: Result := TValue.From<string>(DecodedValue);
      tkEnumeration:
        begin
          if AType = TypeInfo(Boolean) then
          begin
            B := (DecodedValue.Trim.ToLower = 'true') or (DecodedValue.Trim = '1') or (DecodedValue.Trim = 'on') or (DecodedValue.Trim = 'yes');
            Result := TValue.From<Boolean>(B);
          end
          else
            Result := TValue.FromOrdinal(AType, StrToIntDef(DecodedValue, 0));
        end;
      tkRecord:
        begin
          if AType = TypeInfo(TGUID) then
          begin
            GuidStr := DecodedValue.Trim;
            if GuidStr <> '' then
            begin
              if not GuidStr.StartsWith('{') then GuidStr := '{' + GuidStr + '}';
              try
                G := StringToGUID(GuidStr);
                TValue.Make(@G, AType, Result);
              except
                Result := TValue.From<TGUID>(TGUID.Empty);
              end;
            end
            else Result := TValue.From<TGUID>(TGUID.Empty);
          end
          else if AType = TypeInfo(TUUID) then
          begin
             U := TUUID.FromString(DecodedValue.Trim);
             TValue.Make(@U, AType, Result);
          end
          else
            TValue.Make(nil, AType, Result);
        end;
      else
        TValue.Make(nil, AType, Result);
    end;
  except
    TValue.Make(nil, AType, Result);
  end;
end;

class function TReflection.GetDefaultValue(AMember: TRttiObject; AType: PTypeInfo): TValue;
var
  Attr: TCustomAttribute;
  AttrRtti: TRttiType;
  ValField: TRttiField;
  ValProp: TRttiProperty;
  AttrValue: TValue;
  V: Variant;
begin
  // Check for [DefaultValue] attribute via RTTI (avoids direct unit dependency)
  if AMember <> nil then
  begin
    for Attr in AMember.GetAttributes do
    begin
      if SameText(Attr.ClassName, 'DefaultValueAttribute') then
      begin
        AttrRtti := FContext.GetType(Attr.ClassType);
        if AttrRtti <> nil then
        begin
          // Try the backing field FValue first (avoids Variant/TValue wrapping issues)
          ValField := AttrRtti.GetField('FValue');
          if ValField <> nil then
          begin
            AttrValue := ValField.GetValue(Attr);
            try
              V := AttrValue.AsVariant;
              if not VarIsEmpty(V) and not VarIsNull(V) then
              begin
                Result := CastFromString(VarToStr(V), AType);
                Exit;
              end;
            except
              // Fall through to default
            end;
          end
          else
          begin
            // Try the property if the field isn't directly accessible
            ValProp := AttrRtti.GetProperty('Value');
            if ValProp <> nil then
            begin
              AttrValue := ValProp.GetValue(Attr);
              try
                V := AttrValue.AsVariant;
                if not VarIsEmpty(V) and not VarIsNull(V) then
                begin
                  Result := CastFromString(VarToStr(V), AType);
                  Exit;
                end;
              except
                // Fall through to default
              end;
            end;
          end;
        end;
        Break;
      end;
    end;
  end;

  // No [DefaultValue] attribute found - return zero/empty for type
  TValue.Make(nil, AType, Result);
end;

end.
