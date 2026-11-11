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
unit Dext.Entity.Collections;

interface

uses
  System.SysUtils,
  Dext.Collections,
  System.Rtti,
  System.TypInfo,
  Dext.Collections.Base,
  Dext.Collections.Dict,
  Dext.Entity.Core;

type
  /// <summary>
  ///   Specialized list that tracks additions and removals to automatically 
  ///   synchronize database relationships (One-to-Many and Many-to-Many).
  /// </summary>
  TTrackingList<T: class> = class(TSmartList<T>)
  private
    FContext: IDbContext;
    FOwner: TObject;
    FPropertyName: string;
    FSuppressTracking: Boolean;
    
    procedure SetInverseProperty(const AItem: T);
    procedure ClearInverseProperty(const AItem: T);
  protected
    procedure Notify(Sender: TObject; const Item: T; Action: TCollectionNotification); override;
  public
    constructor Create(const AContext: IDbContext; const AOwner: TObject; const APropertyName: string);
    
    // Allows loading data without triggering tracking events
    procedure Load(const AItems: IEnumerable<T>);
  end;

  /// <summary>
  ///   Factory for creating strongly-typed tracking lists dynamically via RTTI.
  /// </summary>
  TTrackingListFactory = class
  public
    class function CreateList(AItemType: PTypeInfo; const AContext: IDbContext; const AOwner: TObject; const APropertyName: string): TObject; static;
  end;

implementation

uses
  Dext.Core.Reflection,
  Dext.Core.Activator,
  Dext.Entity.Mapping,
  Dext.Entity.Context; // To access TDbContext internals if needed, or stick to IDbContext

{ TTrackingList<T> }

constructor TTrackingList<T>.Create(const AContext: IDbContext; const AOwner: TObject; const APropertyName: string);
begin
  // Tracking lists don't own objects; the DbContext/IdentityMap does.
  inherited Create(False); 
  FContext := AContext;
  FOwner := AOwner;
  FPropertyName := APropertyName;
  FSuppressTracking := False;
end;

procedure TTrackingList<T>.Load(const AItems: IEnumerable<T>);
begin
  FSuppressTracking := True;
  try
    Self.Clear;
    Self.AddRange(AItems);
  finally
    FSuppressTracking := False;
  end;
end;

procedure TTrackingList<T>.Notify(Sender: TObject; const Item: T; Action: TCollectionNotification);
var
  Map: TEntityMap;
  Prop: TPropertyMap;
begin
  inherited; // Handles standard list logic
  
  if FSuppressTracking or (FContext = nil) or (FOwner = nil) then Exit;

  // 1. Resolve mapping for the owner entity
  Map := TEntityMap(FContext.GetMapping(FOwner.ClassInfo));
  if (Map = nil) or (not Map.Properties.TryGetValue(FPropertyName, Prop)) then Exit;

  // Many-to-many rows are written by SaveChanges, which compares the
  // collection with the snapshot taken when it was loaded or last saved
  if Prop.Relationship = rtManyToMany then Exit;

  case Action of
    cnAdded:
    begin
       // One-to-Many: Ensure item is tracked and set the back-reference (InverseProperty)
       if Prop.Relationship = rtOneToMany then
       begin
         FContext.DataSet(Item.ClassInfo).Add(Item);
         SetInverseProperty(Item);
       end;
    end;
    
    cnRemoved:
    begin
       // One-to-Many: Clear back-reference
       if Prop.Relationship = rtOneToMany then
         ClearInverseProperty(Item);
    end;
  end;
end;

procedure TTrackingList<T>.SetInverseProperty(const AItem: T);
var
  ParentMap: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
  InvProp: TRttiProperty;
begin
  ParentMap := TEntityMap(FContext.GetMapping(FOwner.ClassInfo));
  if (ParentMap = nil) or (not ParentMap.Properties.TryGetValue(FPropertyName, PropMap)) then Exit;
  if PropMap.InverseProperty = '' then Exit;

  try
    Typ := TReflection.Context.GetType(AItem.ClassType);
    InvProp := Typ.GetProperty(PropMap.InverseProperty);
    if InvProp <> nil then
    begin
       // Use TReflection to handle Prop<T> or standard property
       TReflection.SetValue(Pointer(AItem), InvProp, TValue.From<TObject>(FOwner));
    end;
  except
    raise;
  end;
end;

procedure TTrackingList<T>.ClearInverseProperty(const AItem: T);
var
  ParentMap: TEntityMap;
  PropMap: TPropertyMap;
  Typ: TRttiType;
  InvProp: TRttiProperty;
begin
  ParentMap := TEntityMap(FContext.GetMapping(FOwner.ClassInfo));
  if (ParentMap = nil) or (not ParentMap.Properties.TryGetValue(FPropertyName, PropMap)) then Exit;
  if PropMap.InverseProperty = '' then Exit;

  try
    Typ := TReflection.Context.GetType(AItem.ClassType);
    InvProp := Typ.GetProperty(PropMap.InverseProperty);
    if InvProp <> nil then
       TReflection.SetValue(Pointer(AItem), InvProp, TValue.Empty);
  except
    raise;
  end;
end;

{ TTrackingListFactory }

class function TTrackingListFactory.CreateList(AItemType: PTypeInfo; const AContext: IDbContext; const AOwner: TObject;
  const APropertyName: string): TObject;
var
  Typ: TRttiType;
  ListTypName: string;
  ListTyp: TRttiType;
  TypeNamePattern: string;
  ListPattern: string;
  tRtti: TRttiType;
begin
  try
    Typ := TReflection.Context.GetType(AItemType);
    // Generic name for TTrackingList<T>
    ListTypName := 'Dext.Entity.Collections.TTrackingList<' + Typ.QualifiedName + '>';
    ListTyp := TReflection.Context.FindType(ListTypName);
    
    if ListTyp = nil then
    begin
      // Fallback search: iterate all types in RTTI
      TypeNamePattern := 'TTrackingList<' + Typ.Name + '>';
      for tRtti in TReflection.Context.GetTypes do
      begin
        if tRtti.IsInstance and (tRtti.Name.Contains(TypeNamePattern) or tRtti.QualifiedName.Contains(TypeNamePattern)) then
        begin
          ListTyp := tRtti;
          Break;
        end;
      end;
    end;
    
    if ListTyp = nil then
    begin
      // Last resort: try TList<T>
      ListPattern := 'TList<' + Typ.Name + '>';
      for tRtti in TReflection.Context.GetTypes do
      begin
        if tRtti.IsInstance and (tRtti.Name.Contains(ListPattern) or tRtti.QualifiedName.Contains(ListPattern)) then
        begin
          ListTyp := tRtti;
          Break;
        end;
      end;
    end;
    
    if ListTyp = nil then
      raise Exception.CreateFmt('Could not find specialized list RTTI for %s. Make sure the unit or the list is used.', [ListTypName]);

    Result := TActivator.CreateInstance(ListTyp.AsInstance.MetaclassType, [TValue.From<IDbContext>(AContext), AOwner, APropertyName]);
  except
    raise;
  end;
end;

end.
