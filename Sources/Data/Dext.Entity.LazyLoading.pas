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
unit Dext.Entity.LazyLoading;

interface

uses
  System.Classes,
  Dext.Collections,
  System.Rtti,
  System.TypInfo,
  System.SysUtils,
  Dext.Entity.Core,
  Dext.Entity.Attributes,
  Dext.Entity.Mapping,
  Dext.Entity.Drivers.Interfaces,
  Dext.Types.Lazy,
  Dext.Types.Nullable,
  Dext.Specifications.Types,
  Dext.Specifications.Interfaces,
  Dext.Entity.Collections,
  Dext.Core.Activator;

type
  /// <summary>
  ///   Injects Lazy&lt;T&gt; logic into entities.
  /// </summary>
  TLazyInjector = class
  private
    class procedure InjectField(AContext: IDbContext; AEntity: TObject; AField: TRttiField);
  public
    class procedure Inject(AContext: IDbContext; AEntity: TObject);
  end;

  /// <summary>
  ///   Standard implementation of ILazy for Entity Framework.
  ///   Replaces the old TVirtualInterface-based approach.
  /// </summary>
  TLazyLoader = class(TInterfacedObject, ILazy)
  private
    FContext: TObject; // Stored as object to avoid interface refcounting issues, cast to TDbContext in implementation
    FEntity: TObject;
    FPropName: string;
    FLoaded: Boolean;
    FValue: TValue;
    FIsCollection: Boolean;
    FOwnsValue: Boolean; // Added flag
    
    procedure LoadValue;
    procedure LoadManyToMany(Prop: TRttiProperty; const PropMap: TPropertyMap);
    
    // ILazy implementation
    function GetIsValueCreated: Boolean;
    function GetValue: TValue;
    function GetTargetType: PTypeInfo;
  public
    constructor Create(AContext: TObject; AEntity: TObject; const APropName: string; AIsCollection: Boolean; const AValue: TValue);
    destructor Destroy; override;
  end;

implementation

uses
  Dext.Core.Reflection,
  Dext.Entity.Context;

{ Helper Functions }

/// <summary>
///   Unwraps Nullable&lt;T&gt; values and validates if FK is valid (non-zero for integers, non-empty for strings)
/// </summary>
function TryUnwrapAndValidateFK(var AValue: TValue): Boolean;
var
  Helper: TNullableHelper;
  Instance: Pointer;
begin
  Result := False;
  
  // Handle Nullable<T> unwrapping
  if IsNullable(AValue.TypeInfo) then
  begin
      Helper := TNullableHelper.Create(AValue.TypeInfo);
      Instance := AValue.GetReferenceToRawData;
      
      if not Helper.HasValue(Instance) then
      begin
        // Null value is valid (conceptually) but means "no FK to traverse"
        // Return False to skip loading
        Exit; 
      end;
        
      // Get the underlying value
      AValue := Helper.GetValue(Instance);
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


{ TLazyInjector }

class procedure TLazyInjector.Inject(AContext: IDbContext; AEntity: TObject);
var
  Typ: TRttiType;
  Field: TRttiField;
  Map: TEntityMap;
  PropMap: TPropertyMap;
begin
  if AEntity = nil then Exit;
  
  Map := TEntityMap(AContext.GetMapping(AEntity.ClassInfo));
  if Map = nil then Exit;

  Typ := TReflection.Context.GetType(AEntity.ClassType);
  if Typ = nil then Exit;

  // 1. Handle Explicit Lazy<T> (Attributes or Implicit)
  for Field in Typ.GetFields do
  begin
    // Use Contains to handle qualified names like Dext.Types.Lazy.Lazy<T>
    if (Field.FieldType.TypeKind = tkRecord) and Field.FieldType.Name.Contains('Lazy<') then
    begin
      InjectField(AContext, AEntity, Field);
    end;
  end;
  
  // 2. Handle Fluent Mapping IsLazy (For future Auto-Proxies)
  for PropMap in Map.Properties.Values do
  begin
    if PropMap.IsLazy and not PropMap.PropertyName.StartsWith('Lazy<') then
    begin
      // If it's a class but not Lazy<T>, it's a candidate for Auto-Proxying
    end;
  end;
end;

class procedure TLazyInjector.InjectField(AContext: IDbContext; AEntity: TObject; AField: TRttiField);
var
  LazyRecordType: TRttiRecordType;
  InstanceField: TRttiField;
  PropName: string;
  IsCollection: Boolean;
  Loader: TLazyLoader;
  LazyIntf: ILazy;
  LazyVal: TValue;
  IntfVal: TValue;
  ExistingInstance: TValue;
  ExistingValue: TValue;
  LazyInst: ILazy;
begin
  // 1. Determine Property Name from Field Name (FAddress -> Address)
  PropName := AField.Name;
  if PropName.StartsWith('F') then
    Delete(PropName, 1, 1);
    
  // 2. Determine if Collection
  IsCollection := False;
  if AField.FieldType.Name.Contains('TList<') or 
     AField.FieldType.Name.Contains('TObjectList<') or
     AField.FieldType.Name.Contains('IList<') then
    IsCollection := True;

  // 3. Get Lazy<T> record structure
  LazyRecordType := AField.FieldType.AsRecord;
  InstanceField := LazyRecordType.GetField('FInstance');
  if InstanceField = nil then 
    Exit;
  
  // 4. Capture Existing Value (e.g. List created in constructor)
  ExistingValue := TValue.Empty;
  
  LazyVal := AField.GetValue(AEntity);
  ExistingInstance := InstanceField.GetValue(LazyVal.GetReferenceToRawData);
  
  if not ExistingInstance.IsEmpty then
  begin
    if ExistingInstance.Kind = tkInterface then
    begin
      // Extract the ILazy interface from the record's FInstance
      if ExistingInstance.TryAsType<ILazy>(LazyInst) and (LazyInst <> nil) then
      begin
         // If it is value created (like TValueLazy from constructor), get the value
         if LazyInst.IsValueCreated then
         begin
           try
             ExistingValue := LazyInst.Value;
           except
             // Ignore errors extracting value
           end;
         end;
      end;
    end;
  end;

  // 5. Create Loader passing existing value
  Loader := TLazyLoader.Create(TDbContext(AContext), AEntity, PropName, IsCollection, ExistingValue);
  LazyIntf := Loader;

  // 6. Assign interface to Lazy<T>.FInstance
  // Create TValue with ILazy type safely
  IntfVal := TValue.From<ILazy>(LazyIntf);
  
  // Set FInstance on the record - replaces existing one
  InstanceField.SetValue(LazyVal.GetReferenceToRawData, IntfVal);
  
  // Set the record back to the entity
  AField.SetValue(AEntity, LazyVal);
end;

{ TLazyLoader }

constructor TLazyLoader.Create(AContext: TObject; AEntity: TObject; const APropName: string; AIsCollection: Boolean; const AValue: TValue);
begin
  inherited Create;
  FContext := AContext;
  FEntity := AEntity;
  FPropName := APropName;
  FIsCollection := AIsCollection;
  FLoaded := False;
  FValue := AValue; // Store existing list if any
  FOwnsValue := False; // Default no ownership unless we create a non-refcounted object
end;

destructor TLazyLoader.Destroy;
begin
  if FIsCollection and FLoaded and (not FValue.IsEmpty) and FOwnsValue then
  begin
    // If it's a collection and we explicitly own it (e.g. TObjectList)
    if FValue.Kind = tkClass then
      FValue.AsObject.Free;
  end;
  inherited;
end;



function TLazyLoader.GetIsValueCreated: Boolean;
begin
  Result := FLoaded;
end;

function TLazyLoader.GetValue: TValue;
begin
  if not FLoaded then
  begin
    try
      LoadValue;
    except
      on E: Exception do
      begin
        FLoaded := True;
      end;
    end;
  end;

  Result := FValue;
end;

function TLazyLoader.GetTargetType: PTypeInfo;
var
  Prop: TRttiProperty;
  TypeName: string;
  StartPos, EndPos: Integer;
  ItemTypeName: string;
  ItemType: TRttiType;
begin
  Prop := TReflection.Context.GetType(FEntity.ClassType).GetProperty(FPropName);
  if Prop <> nil then
  begin
    // Extract inner type from Lazy<T>
    TypeName := Prop.PropertyType.Name;
    if TypeName.StartsWith('Lazy<') then
    begin
      StartPos := Pos('<', TypeName);
      EndPos := Pos('>', TypeName);
      if (StartPos > 0) and (EndPos > StartPos) then
      begin
        ItemTypeName := Copy(TypeName, StartPos + 1, EndPos - StartPos - 1);
        ItemType := TReflection.Context.FindType(ItemTypeName);
        if ItemType <> nil then
          Exit(ItemType.Handle);
      end;
    end;
    Result := Prop.PropertyType.Handle;
  end
  else
    Result := nil;
end;

procedure TLazyLoader.LoadValue;
var
  Prop: TRttiProperty;
  FKName: string;
  Attr: TCustomAttribute;
  TypeName: string;
  StartPos, EndPos: Integer;
  ItemTypeName: string;
  ItemType: TRttiType;
  ChildSet: IDbSet;
  ParentName: string;
  FKPropName: string;
  P: TRttiProperty;
  PKVal: string;
  PropHelper: TPropExpression;
  Expr: IExpression;
  ResList: IList<TObject>;
  ListObj: TObject;
  AddMethod: TRttiMethod;
  Obj: TObject;
  FKProp: TRttiProperty;
  FKVal: TValue;
  TargetType: PTypeInfo;
  TargetSet: IDbSet;
  LoadedObj: TObject;
  IntVal: Integer;
  ExpectedClass: TClass;
  UseExistingInterface: Boolean;
  Map: TEntityMap;
  PropMap: TPropertyMap;
  GenericTypeName: string;
  SPos, EPos: Integer;
  ListIntf: IInterface;
  LIntfType: TRttiType;
  LTypeName: string;
  IntfType: TRttiType;
begin
  if FLoaded then Exit;
  
  try
    try
      if FIsCollection then
    begin
        // Load Collection
        Prop := TReflection.Context.GetType(FEntity.ClassType).GetProperty(FPropName);
        if Prop = nil then Exit;
        
        // Check if this is a Many-to-Many relationship
        Map := TEntityMap(TDbContext(FContext).GetMapping(FEntity.ClassInfo));
        if (Map <> nil) and Map.Properties.TryGetValue(FPropName, PropMap) then
        begin
          if (PropMap.Relationship = rtManyToMany) and (PropMap.JoinTableName <> '') then
          begin
            LoadManyToMany(Prop, PropMap);
            FLoaded := True;
            Exit;
          end;
        end;
        
        // Standard One-to-Many loading
        FKName := '';
        for Attr in Prop.GetAttributes do
          if Attr is ForeignKeyAttribute then
          begin
            FKName := ForeignKeyAttribute(Attr).ColumnName;
            Break;
          end;
        
        TypeName := Prop.PropertyType.Name;
        StartPos := Pos('<', TypeName);
        EndPos := Pos('>', TypeName);
        
        if (StartPos > 0) and (EndPos > StartPos) then
        begin
            ItemTypeName := Copy(TypeName, StartPos + 1, EndPos - StartPos - 1);
            ItemType := TReflection.Context.FindType(ItemTypeName);
            
            if ItemType <> nil then
            begin
                ChildSet := TDbContext(FContext).DataSet(ItemType.Handle);
                
                ParentName := FEntity.ClassName;
                if ParentName.StartsWith('T') then Delete(ParentName, 1, 1);
                
                FKPropName := ParentName + 'Id'; 
                
                P := ItemType.GetProperty(FKPropName);
                if P <> nil then
                begin
                    PKVal := TDbContext(FContext).DataSet(FEntity.ClassInfo).GetEntityId(FEntity);
                    
                    PropHelper := TPropExpression.Create(FKPropName);
                    
                    // Try to convert PK to Integer if possible, as most FKs are ints
                    if TryStrToInt(PKVal, IntVal) then
                       Expr := PropHelper = IntVal
                    else
                       Expr := PropHelper = PKVal;
                       
                    ResList := ChildSet.ListObjects(Expr);
                    try
                      // Try to use existing list stored in FValue (passed from constructor)
                      UseExistingInterface := False;
                      ListObj := nil;
                      
                      if not FValue.IsEmpty then
                      begin
                        if FValue.Kind = tkInterface then
                        begin
                           // Existing IList<T>
                           UseExistingInterface := True;
                           // Note: We don't need to extract the interface pointer, invoke works on TValue wrapping interface
                        end
                        else if FValue.IsObject then
                        begin
                           // Existing TObjectList
                           ListObj := FValue.AsObject;
                        end;
                      end;
                      
                // Create TTrackingList via Factory
                if ListObj = nil then
                begin
                   ListObj := TTrackingListFactory.CreateList(ItemType.Handle, TDbContext(FContext), FEntity, FPropName);
                end;

                if ListObj = nil then
                  Exit;
                      
                      // Get Add method
                      if UseExistingInterface then
                      begin
                         GenericTypeName := Prop.PropertyType.Name;
                         if GenericTypeName.StartsWith('Lazy<') then
                         begin
                           SPos := Pos('<', GenericTypeName);
                           EPos := Pos('>', GenericTypeName);
                           if (SPos > 0) and (EPos > SPos) then
                             GenericTypeName := Copy(GenericTypeName, SPos + 1, EPos - SPos - 1);
                         end;
                         
                         IntfType := TReflection.Context.FindType(GenericTypeName);
                         if IntfType <> nil then
                           AddMethod := IntfType.GetMethod('Add')
                         else
                           AddMethod := nil;
                      end
                      else
                        AddMethod := TReflection.Context.GetType(ListObj.ClassType).GetMethod('Add');
                        
                      if AddMethod = nil then
                        Exit;
                      
                      // Populate the list
                      for Obj in ResList do
                      begin
                           if Obj = nil then 
                             Continue;
                           
                           try
                            // Check if object is instance of expected type
                            if ItemType.AsInstance <> nil then
                            begin
                              ExpectedClass := ItemType.AsInstance.MetaclassType;
                              if not (Obj is ExpectedClass) then
                                Continue;
                            end;
                            
                            if UseExistingInterface then
                               AddMethod.Invoke(FValue, [Obj])
                            else
                               AddMethod.Invoke(ListObj, [Obj]);
                               
                          except
                            // Ignore errors adding individual items
                          end;
                      end;
                      
                      if not UseExistingInterface then
                      begin
                        if (ListObj <> nil) and ListObj.GetInterface(IInterface, ListIntf) then
                        begin
                           // Attempt to get the actual interface type for the TValue metadata
                           LIntfType := nil;
                           LTypeName := Prop.PropertyType.Name;
                           if LTypeName.StartsWith('Lazy<') then
                           begin
                              SPos := Pos('<', LTypeName);
                              EPos := Length(LTypeName);
                              if (SPos > 0) then
                                LIntfType := TReflection.Context.FindType(Copy(LTypeName, SPos + 1, EPos - SPos - 1));
                           end
                           else
                              LIntfType := Prop.PropertyType;

                           // Refined fix: Ensure we have the correct VTable pointer for the specific interface
                           if (LIntfType <> nil) and (LIntfType is TRttiInterfaceType) and
                              Supports(ListObj, TRttiInterfaceType(LIntfType).GUID, ListIntf) then
                           begin
                              TValue.Make(@ListIntf, LIntfType.Handle, FValue);
                           end;
                           FOwnsValue := False;
                        end
                        else
                        begin
                          FValue := TValue.From(ListObj);
                          FOwnsValue := True;
                        end;
                      end;
                        
                    finally
                      ResList := nil; // Auto-managed
                    end;
                end;
            end;
        end;
    end
  else
    begin
        // Load Reference
        FKPropName := FPropName + 'Id';
        FKProp := TReflection.Context.GetType(FEntity.ClassType).GetProperty(FKPropName);
        
        if FKProp <> nil then
        begin
            FKVal := FKProp.GetValue(FEntity);
            
            // Unwrap Nullable<T> and validate FK value
            if TryUnwrapAndValidateFK(FKVal) then
            begin
                Prop := TReflection.Context.GetType(FEntity.ClassType).GetProperty(FPropName);
                TypeName := Prop.PropertyType.Name;
                
                // Extract inner type from Lazy<T>
                if TypeName.StartsWith('Lazy<') then
                begin
                  StartPos := Pos('<', TypeName);
                  EndPos := Pos('>', TypeName);
                  if (StartPos > 0) and (EndPos > StartPos) then
                  begin
                    ItemTypeName := Copy(TypeName, StartPos + 1, EndPos - StartPos - 1);
                    ItemType := TReflection.Context.FindType(ItemTypeName);
                    if ItemType <> nil then
                      TargetType := ItemType.Handle
                    else
                      TargetType := nil;
                  end
                  else
                    TargetType := nil;
                end
                else
                  TargetType := Prop.PropertyType.Handle;
                
                if TargetType <> nil then
                begin
                  TargetSet := TDbContext(FContext).DataSet(TargetType);
                  LoadedObj := TargetSet.FindObject(FKVal.AsVariant);
                  
                  if LoadedObj <> nil then
                       FValue := TValue.From(LoadedObj);
                end;
            end;
        end;
    end;
    
    FLoaded := True;
  except
    on E: Exception do
    begin
      // Suppress loading errors for now
      FLoaded := True;
    end;
  end;
finally
  // Context is global
end;
end;

procedure TLazyLoader.LoadManyToMany(Prop: TRttiProperty; const PropMap: TPropertyMap);
var
  AddMethod: TRttiMethod;
  Cmd: IDbCommand;
  EntityId: string;
  IntfType: TRttiType;
  ItemType: TRttiType;
  ItemTypeName: string;
  ListIntf: IInterface;
  ListObj: TObject;
  Obj: TObject;
  Reader: IDbReader;
  RelatedDbSet: IDbSet;
  RelatedIds: Dext.Collections.TList<TValue>;
  ResList: Dext.Collections.IList<TObject>;
  SB: TStringBuilder;
  SQL: string;
  StartPos, EndPos: Integer;
  TypeName: string;
  UseExistingInterface: Boolean;
  SearchName: string;
  T: TRttiType;
  IntfName: string;
  IntVal: Integer;
  V: TValue;
  i: Integer;
  m: TRttiMethod;
  ListRtti: TRttiType;
begin
  // Get entity's primary key value
  EntityId := TDbContext(FContext).DataSet(FEntity.ClassInfo).GetEntityId(FEntity);
  if EntityId = '' then Exit;

  ListObj := nil;
  UseExistingInterface := False;
  ResList := nil;
  
  // Build SQL to query join table
  SB := TStringBuilder.Create;
  try
    SB.Append('SELECT ');
    SB.Append(TDbContext(FContext).Dialect.QuoteIdentifier(PropMap.RightKeyColumn));
    SB.Append(' FROM ');
    SB.Append(TDbContext(FContext).Dialect.QuoteIdentifier(PropMap.JoinTableName));
    SB.Append(' WHERE ');
    SB.Append(TDbContext(FContext).Dialect.QuoteIdentifier(PropMap.LeftKeyColumn));
    SB.Append(' = :p1');
    SQL := SB.ToString;
  finally
    SB.Free;
  end;
  
  // Prop.PropertyType is Lazy<IList<T>>. We need IList<T>.
  TypeName := Prop.PropertyType.Name;
  IntfType := nil;
  SearchName := '';
  if TypeName.StartsWith('Lazy<') then
  begin
    StartPos := Pos('<', TypeName);
    EndPos := Length(TypeName);
    if (StartPos > 0) then
    begin
        SearchName := Copy(TypeName, StartPos + 1, EndPos - StartPos - 1);
        IntfType := TReflection.Context.FindType(SearchName);
    end;
  end;

  if (IntfType = nil) and (SearchName <> '') then 
  begin
    // Robust fallback: search all types for matching name or qualified name
    for T in TReflection.Context.GetTypes do
       if (T.TypeKind = tkInterface) and (SameText(T.Name, SearchName) or SameText(T.QualifiedName, SearchName)) then
       begin
          IntfType := T;
          break;
       end;
  end;

  // Re-extract ItemType for the query
  ItemType := nil;
  if IntfType <> nil then
  begin
     IntfName := IntfType.Name;
     StartPos := Pos('<', IntfName);
     EndPos := Pos('>', IntfName);
     if (StartPos > 0) and (EndPos > StartPos) then
     begin
        ItemTypeName := Copy(IntfName, StartPos + 1, EndPos - StartPos - 1);
        ItemType := TReflection.Context.FindType(ItemTypeName);
        
        if ItemType = nil then
        begin
          for T in TReflection.Context.GetTypes do
            if SameText(T.Name, ItemTypeName) or SameText(T.QualifiedName, ItemTypeName) then
            begin
               ItemType := T;
               break;
            end;
        end;
     end;
  end;

  // Execute query
  RelatedIds := Dext.Collections.TList<TValue>.Create;
  try
    Cmd := TDbContext(FContext).Connection.CreateCommand(SQL);
    
    // Try to pass PK with correct type (Integer if possible)
    if TryStrToInt(EntityId, IntVal) then
      Cmd.AddParam('p1', TValue.From<Integer>(IntVal))
    else
      Cmd.AddParam('p1', TValue.From<string>(EntityId));
      
    Reader := Cmd.ExecuteQuery;
    
    while Reader.Next do
    begin
      V := Reader.GetValue(0);
      RelatedIds.Add(V);
    end;
      
    if (RelatedIds.Count = 0) then
    begin
       // Initialize empty list to avoid returning nil to the property
       if (not UseExistingInterface) and (ListObj = nil) and (not FValue.IsEmpty) then
       begin
         // Keep existing list (likely from constructor)
       end
       else if (not UseExistingInterface) and (ListObj = nil) then
       begin
          try
            ListObj := TTrackingListFactory.CreateList(ItemType.Handle, TDbContext(FContext), FEntity, FPropName);
          except
             ListObj := TCollections.CreateList<TObject>(False) as TObject;
          end;
          
          if (ListObj <> nil) and ListObj.GetInterface(IInterface, ListIntf) then
          begin
             // Use TValue.Make to ensure correct interface type metadata
             if (IntfType <> nil) and (IntfType is TRttiInterfaceType) and
                Supports(ListObj, TRttiInterfaceType(IntfType).GUID, ListIntf) then
               TValue.Make(@ListIntf, IntfType.Handle, FValue)
             else
               FValue := TValue.From<IInterface>(ListIntf);
             FOwnsValue := False;
          end;
       end;
       
       FLoaded := True;
       Exit;
    end;

    if ItemType = nil then Exit;
    
    // Load related objects
    RelatedDbSet := TDbContext(FContext).DataSet(ItemType.Handle);

    // Each target is read by its own key: the related entity does not have to
    // call it Id (the identity map answers the ones already loaded)
    ResList := Dext.Collections.TCollections.CreateList<TObject>(False);
    for i := 0 to RelatedIds.Count - 1 do
    begin
      Obj := RelatedDbSet.FindObject(RelatedIds[i].AsVariant);
      if Obj <> nil then
        ResList.Add(Obj);
    end;
    
    // Resolve collection object
    UseExistingInterface := False;
    ListObj := nil;
    
    if not FValue.IsEmpty then
    begin
      if FValue.Kind = tkInterface then
        UseExistingInterface := True
      else if FValue.IsObject then
        ListObj := FValue.AsObject;
    end;

    if not UseExistingInterface and (ListObj = nil) then
    begin
      try
        ListObj := TTrackingListFactory.CreateList(ItemType.Handle, TDbContext(FContext), FEntity, FPropName);
      except
        ListObj := nil;
      end;
    end;
    
    if (ListObj = nil) and (not UseExistingInterface) then
    begin
        // Final attempt: fallback to TObject list if all fails, but try to keep it typed if possible
        ListObj := TCollections.CreateList<TObject>(False) as TObject;
    end;

    // Resolve Add method
    if UseExistingInterface then
    begin
       AddMethod := IntfType.GetMethod('Add');
       if AddMethod = nil then
         for m in IntfType.GetMethods do
           if SameText(m.Name, 'Add') then begin AddMethod := m; break; end;
    end
    else
    begin
       ListRtti := TReflection.Context.GetType(ListObj.ClassType);
       AddMethod := ListRtti.GetMethod('Add');
       if AddMethod = nil then
         for m in ListRtti.GetMethods do
           if SameText(m.Name, 'Add') then begin AddMethod := m; break; end;
    end;

    if AddMethod <> nil then
    begin
      for Obj in ResList do
      begin
        try
          if UseExistingInterface then
            AddMethod.Invoke(FValue, [Obj])
          else
            AddMethod.Invoke(ListObj, [Obj]);
        except
        end;
      end;
    end;
    
    // Final assignment to FValue
    if not UseExistingInterface then
    begin
      if (ListObj <> nil) and ListObj.GetInterface(IInterface, ListIntf) then
      begin
        if (IntfType <> nil) and (IntfType is TRttiInterfaceType) and
          Supports(ListObj, TRttiInterfaceType(IntfType).GUID, ListIntf) then
        begin
          TValue.Make(@ListIntf, IntfType.Handle, FValue);
        end
        else
        begin
          FValue := TValue.From<IInterface>(ListIntf);
        end;
        FOwnsValue := False;
      end
      else
      begin
        FValue := TValue.From(ListObj);
        FOwnsValue := True;
      end;
    end;
  finally
    RelatedIds.Free;
  end;
  FLoaded := True;
end;

end.

