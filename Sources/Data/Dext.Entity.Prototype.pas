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
{  Created: 2025-12-27                                                      }
{                                                                           }
{  Prototype - ORM factory for "ghost entities" used in query building.     }
{                                                                           }
{  The Prototype class itself lives in Dext.Core.SmartTypes (Core), so      }
{  HaveValue and typed validation work without the ORM. This unit plugs the }
{  ORM mapping into it: column names from TEntityMap and nested entities.   }
{                                                                           }
{  Usage:                                                                   }
{    u := Prototype.Entity<TSmartPerson>;                                   }
{    List := SetPerson.Where(u.Age = 30).ToList;                            }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.Prototype;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  Dext.Core.SmartTypes;

type
  /// <summary>
  ///   The prototype factory is in Dext.Core.SmartTypes. This alias keeps
  ///   existing code that uses Dext.Entity.Prototype.Prototype compiling;
  ///   linking this unit registers the ORM factory (Prototype.Creator).
  /// </summary>
  Prototype = Dext.Core.SmartTypes.Prototype;

  // Backward compatibility alias
  Build = Prototype;

implementation

uses
  Dext.Core.Reflection,
  Dext.Entity.Core,
  Dext.Entity.Mapping,
  Dext.Validation;

/// <summary>
///   ORM factory: injects IPropInfo with the mapped column name and
///   drill-down sub-prototypes for nested entities.
/// </summary>
function CreateEntityPrototype(ATypeInfo: PTypeInfo): TObject;
var
  Typ: TRttiType;
  PropInfo: IPropInfo;
  InstancePtr: Pointer;
  ColumnName: string;
  EntityMap: TEntityMap;
  PropMap: TPropertyMap;
begin
  Typ := TReflection.Context.GetType(ATypeInfo);

  // Create Instance - Prefer default constructor if available
  Result := Typ.AsInstance.MetaclassType.Create;
  InstancePtr := Result;

  EntityMap := TModelBuilder.Instance.GetMap(ATypeInfo);
  if EntityMap <> nil then
  begin
    for PropMap in EntityMap.Properties.Values do
    begin
      // 1. Inject IPropInfo (Metadata for SQL generation)
      // CRITICAL: We use MetadataOffset (FInfo interface) instead of FieldOffset (Boolean flag).
      if PropMap.MetadataOffset <> -1 then
      begin
        ColumnName := PropMap.ColumnName;
        if ColumnName = '' then ColumnName := PropMap.PropertyName;

        PropInfo := TPropInfo.Create(PropMap.ColumnName, PropMap.PropertyName,
          EntityMap.TableName);
        // Manually AddRef since we're storing it in raw memory as a raw pointer
        // This prevents the interface from being freed when this scope ends.
        PropInfo._AddRef;
        PPointer(NativeInt(InstancePtr) + PropMap.MetadataOffset)^ := Pointer(PropInfo);
      end;

      // 2. Inject Sub-Prototypes (Recursive Drill-down Support)
      // A class stored as a JSON column is not an entity: it has no prototype.
      if (PropMap.FieldValueOffset <> -1) and (PropMap.PropertyType <> nil) and
         (PropMap.PropertyType.Kind = tkClass) and (not PropMap.IsJsonColumn) then
      begin
         // The non-generic Entity call handles the cache and recursion.
         // A class with no Smart Properties (a JSON class configured in a fluent
         // mapping this singleton map does not see, for example) is not an entity:
         // it just gets no sub-prototype.
         try
           PPointer(NativeInt(InstancePtr) + PropMap.FieldValueOffset)^ :=
             Prototype.Entity(PropMap.PropertyType);
         except
           on Exception do
             PPointer(NativeInt(InstancePtr) + PropMap.FieldValueOffset)^ := nil;
         end;
      end;
    end;
  end;
end;

initialization
  Prototype.ClearCache;
  Prototype.Creator := CreateEntityPrototype;
  Dext.Validation.PrototypeFactory := function(ATypeInfo: PTypeInfo): TObject
    begin
      Result := Prototype.Entity(ATypeInfo);
    end;

finalization
  // Free the ORM prototypes while their classes are still loaded (the cache
  // lives in Core, which is finalized after this unit).
  Prototype.ClearCache;
  Prototype.Creator := nil;
  Dext.Validation.PrototypeFactory := nil;

end.
