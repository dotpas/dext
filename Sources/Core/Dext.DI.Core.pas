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
{  Updated: 2025-12-10 - Refactored ownership model for explicit memory     }
{                        management. Interface-based services are managed   }
{                        by ARC, class-based services by explicit Free.     }
{                                                                           }
{***************************************************************************}
unit Dext.DI.Core;

interface

uses
  System.SysUtils, System.SyncObjs,
  Dext.Collections, Dext.Collections.Dict, Dext.DI.Interfaces, Dext.DI.Comparers;

type
  TDextServiceScope = class;

  /// <summary>
  ///   Service Provider (Dext DI Container). Resolves registered instances respecting the lifecycle.
  ///   Manages hybrid storage to ensure correct cleanup of Objects (Free) and Interfaces (ARC).
  /// </summary>
  TDextServiceProvider = class(TInterfacedObject, IServiceProvider)
  private
    FDescriptors: IList<TServiceDescriptor>;
    
    // Class-based service storage (DI owns and frees these)
    FSingletons: IDictionary<TServiceType, TObject>;
    FScopedInstances: IDictionary<TServiceType, TObject>;
    
    // Interface-based service storage (ARC manages these)
    FSingletonInterfaces: IDictionary<TServiceType, IInterface>;
    FScopedInterfaces: IDictionary<TServiceType, IInterface>;
    
    FIsRootProvider: Boolean;
    FParentProvider: IServiceProvider;
    FLock: TCriticalSection;
    FOwnsDescriptors: Boolean;

    function CreateInstance(ADescriptor: TServiceDescriptor): TObject;
    function FindDescriptor(const AServiceType: TServiceType): TServiceDescriptor;
  public
    constructor Create(const ADescriptors: IList<TServiceDescriptor>); overload;
    /// <summary>Creates a provider with an isolated scope, inheriting registrations from the parent provider for 'Scoped' instances.</summary>
    constructor CreateScoped(AParent: IServiceProvider; const ADescriptors: IList<TServiceDescriptor>); overload;
    destructor Destroy; override;

    /// <summary>Resolves an instance of the requested service. Returns nil if the service is not registered.</summary>
    function GetService(const AServiceType: TServiceType): TObject;
    /// <summary>Resolves an instance and returns it as an interface (requires ARC support on the resolved object).</summary>
    function GetServiceAsInterface(const AServiceType: TServiceType): IInterface;
    /// <summary>Resolves an instance of the service. Raises an EServiceNotFound exception if the service is not registered.</summary>
    function GetRequiredService(const AServiceType: TServiceType): TObject;
    /// <summary>Starts a new isolation scope (e.g., for a new HTTP request or background task).</summary>
    function CreateScope: IServiceScope;
  end;

  /// <summary>
  ///   Service scope. Ensures that services registered as 'Scoped' are freed at the end of the lifecycle (e.g., end of an HTTP request).
  /// </summary>
  TDextServiceScope = class(TInterfacedObject, IServiceScope)
  private
    FServiceProvider: IServiceProvider;
  public
    constructor Create(AServiceProvider: IServiceProvider);
    function GetServiceProvider: IServiceProvider;
  end;

  /// <summary>
  ///   Collection of service registrations. Allows configuring the DI container following the Builder pattern.
  /// </summary>
  TDextServiceCollection = class(TInterfacedObject, IServiceCollection)
  private
    FDescriptors: IList<TServiceDescriptor>;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    function GetDescriptors: IList<TServiceDescriptor>;
    /// <summary>Registers a persistent service for the entire application lifetime (Shared/Static).</summary>
    function AddSingleton(const AServiceType: TServiceType;
                         const AImplementationClass: TClass;
                         const AFactory: TFunc<IServiceProvider, TObject> = nil): IServiceCollection; overload;
    
    /// <summary>Registers a pre-existing instance as a Singleton (the container assumes ownership).</summary>
    function AddSingleton(const AServiceType: TServiceType;
                         AInstance: TObject): IServiceCollection; overload;

    /// <summary>Registers a service that will be recreated on each resolution request.</summary>
    function AddTransient(const AServiceType: TServiceType;
                          const AImplementationClass: TClass;
                          const AFactory: TFunc<IServiceProvider, TObject> = nil): IServiceCollection;

    /// <summary>Registers a service whose instance is kept alive only within the current scope (e.g., IServiceScope).</summary>
    function AddScoped(const AServiceType: TServiceType;
                       const AImplementationClass: TClass;
                       const AFactory: TFunc<IServiceProvider, TObject> = nil): IServiceCollection;

    procedure AddRange(const AOther: IServiceCollection);
    /// <summary>Finalizes configurations and materializes the service provider (Container) for use.</summary>
    function BuildServiceProvider: IServiceProvider;
  end;

implementation

uses
  System.Rtti,
  System.TypInfo,
  Dext.Core.Activator;

/// <summary>
///   TVirtualInterface (mocks, interface proxies) answers the service GUID only
///   through QueryInterface, never through the class interface table, so
///   GetInterface alone would reject a registered mock.
/// </summary>
function GetServiceInterface(Obj: TObject; const ServiceGuid: TGUID; out Intf: IInterface): Boolean;
var
  Unknown: IInterface;
begin
  Result := Obj.GetInterface(ServiceGuid, Intf);
  if not Result and (Obj is TVirtualInterface) and Obj.GetInterface(IInterface, Unknown) then
    Result := Unknown.QueryInterface(ServiceGuid, Intf) = S_OK;
end;

{ TDextServiceCollection }

constructor TDextServiceCollection.Create;
begin
  inherited Create;
  FDescriptors := TCollections.CreateList<TServiceDescriptor>(True);
  FLock := TCriticalSection.Create;
end;

destructor TDextServiceCollection.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TDextServiceCollection.GetDescriptors: IList<TServiceDescriptor>;
begin
  Result := FDescriptors;
end;

function TDextServiceCollection.AddSingleton(const AServiceType: TServiceType;
  const AImplementationClass: TClass;
  const AFactory: TFunc<IServiceProvider, TObject>): IServiceCollection;
var
  Descriptor: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Descriptor := TServiceDescriptor.Create(
      AServiceType, AImplementationClass, TServiceLifetime.Singleton, AFactory);
    FDescriptors.Add(Descriptor);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

// Instance registration overload - register pre-created singleton
function TDextServiceCollection.AddSingleton(const AServiceType: TServiceType;
  AInstance: TObject): IServiceCollection;
var
  Descriptor: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Descriptor := TServiceDescriptor.Create(
      AServiceType, nil, TServiceLifetime.Singleton, nil);
    Descriptor.Instance := AInstance;  // Set the pre-created instance
    FDescriptors.Add(Descriptor);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

function TDextServiceCollection.AddTransient(const AServiceType: TServiceType;
  const AImplementationClass: TClass;
  const AFactory: TFunc<IServiceProvider, TObject>): IServiceCollection;
var
  Descriptor: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Descriptor := TServiceDescriptor.Create(
      AServiceType, AImplementationClass, TServiceLifetime.Transient, AFactory);
    FDescriptors.Add(Descriptor);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

function TDextServiceCollection.AddScoped(const AServiceType: TServiceType;
  const AImplementationClass: TClass;
  const AFactory: TFunc<IServiceProvider, TObject>): IServiceCollection;
var
  Descriptor: TServiceDescriptor;
begin
  FLock.Enter;
  try
    Descriptor := TServiceDescriptor.Create(
      AServiceType, AImplementationClass, TServiceLifetime.Scoped, AFactory);
    FDescriptors.Add(Descriptor);
  finally
    FLock.Leave;
  end;
  Result := Self;
end;

procedure TDextServiceCollection.AddRange(const AOther: IServiceCollection);
var
  OtherColl: TDextServiceCollection;
  Desc: TServiceDescriptor;
begin
  if Assigned(AOther) and (TObject(AOther) is TDextServiceCollection) then
  begin
    OtherColl := TDextServiceCollection(TObject(AOther));
    FLock.Enter;
    try
      for Desc in OtherColl.FDescriptors do
        FDescriptors.Add(Desc.Clone);
    finally
      FLock.Leave;
    end;
  end;
end;

function TDextServiceCollection.BuildServiceProvider: IServiceProvider;
begin
  Result := TDextServiceProvider.Create(FDescriptors);
end;

{ TDextServiceProvider }

constructor TDextServiceProvider.Create(const ADescriptors: IList<TServiceDescriptor>);
var
  Desc: TServiceDescriptor;
begin
  inherited Create;
  // Clone descriptors so the provider owns its own copies.
  // This is critical: factory closures in descriptors capture interface references
  // (like IConfiguration) that MUST be released when the provider is destroyed.
  FDescriptors := TCollections.CreateList<TServiceDescriptor>(True);
  for Desc in ADescriptors do
    FDescriptors.Add(Desc.Clone);
  FOwnsDescriptors := True;

  // Class-based storage (DI owns these objects)
  FSingletons := TDictionary<TServiceType, TObject>.Create(TServiceTypeComparer.Create);
  FScopedInstances := TDictionary<TServiceType, TObject>.Create(TServiceTypeComparer.Create);
  
  // Interface-based storage (ARC owns these objects)
  FSingletonInterfaces := TDictionary<TServiceType, IInterface>.Create(TServiceTypeComparer.Create);
  FScopedInterfaces := TDictionary<TServiceType, IInterface>.Create(TServiceTypeComparer.Create);
  
  FLock := TCriticalSection.Create;
  FIsRootProvider := True;
  FParentProvider := nil;
end;

constructor TDextServiceProvider.CreateScoped(AParent: IServiceProvider; 
  const ADescriptors: IList<TServiceDescriptor>);
var
  Desc: TServiceDescriptor;
begin
  inherited Create;
  FDescriptors := TCollections.CreateList<TServiceDescriptor>(False);
  for Desc in ADescriptors do
    FDescriptors.Add(Desc);
  FOwnsDescriptors := True;

  // Scoped providers don't manage singletons - they delegate to parent
  FSingletons := nil;
  FSingletonInterfaces := nil;
  
  // But they do manage scoped instances
  FScopedInstances := TDictionary<TServiceType, TObject>.Create(TServiceTypeComparer.Create);
  FScopedInterfaces := TDictionary<TServiceType, IInterface>.Create(TServiceTypeComparer.Create);
  
  FLock := TCriticalSection.Create;
  FIsRootProvider := False;
  FParentProvider := AParent;
end;

destructor TDextServiceProvider.Destroy;
var
  Pair: TPair<TServiceType, TObject>;
begin
  // === SINGLETON CLEANUP (only for root provider) ===
  if FIsRootProvider then
  begin
    // 1. Clear interface-based singletons (ARC manages)
    // We do this BEFORE freeing classes because interfaces (like THostedServiceManager)
    // might hold references to classes (like THostingLifecycleEventBridge).
    FSingletonInterfaces := nil;

    // 2. Free class-based singletons (non-TInterfacedObject)
    if Assigned(FSingletons) then
    begin
      for Pair in FSingletons do
        Pair.Value.Free;
      FSingletons := nil;
    end;
  end;

  // === SCOPED CLEANUP ===
  // Scoped items also follow the same logic: Interfaces first
  FScopedInterfaces := nil;
  
  if Assigned(FScopedInstances) then
  begin
    for Pair in FScopedInstances do
      Pair.Value.Free;
    FScopedInstances := nil;
  end;

  if FOwnsDescriptors then
    FDescriptors := nil;

  FLock.Free;
  inherited Destroy;
end;

function TDextServiceProvider.CreateScope: IServiceScope;
var
  ScopedProvider: IServiceProvider;
begin
  ScopedProvider := TDextServiceProvider.CreateScoped(Self, FDescriptors);
  Result := TDextServiceScope.Create(ScopedProvider);
end;

function TDextServiceProvider.FindDescriptor(const AServiceType: TServiceType): TServiceDescriptor;
var
  I: Integer;
begin
  // Iterate backwards to find the most recent registration (Standard DI behavior)
  for I := FDescriptors.Count - 1 downto 0 do
  begin
    if FDescriptors[I].ServiceType = AServiceType then
      Exit(FDescriptors[I]);
  end;
  Result := nil;
end;

function TDextServiceProvider.CreateInstance(ADescriptor: TServiceDescriptor): TObject;
begin
  // Check if descriptor has pre-created instance (instance registration)
  if Assigned(ADescriptor.Instance) then
    Result := ADescriptor.Instance
  else if Assigned(ADescriptor.Factory) then
    Result := ADescriptor.Factory(Self)
  else
    Result := TActivator.CreateInstance(Self, ADescriptor.ImplementationClass);
end;

function TDextServiceProvider.GetService(const AServiceType: TServiceType): TObject;
var
  Descriptor: TServiceDescriptor;
  Instance: TObject;
  Intf: IInterface;
begin
  // Special handling for IServiceProvider to return Self without dictionary cycle
  if AServiceType.IsInterface and IsEqualGUID(AServiceType.AsInterface, IServiceProvider) then
    Exit(TObject(Self));

  Descriptor := FindDescriptor(AServiceType);
  if not Assigned(Descriptor) then
    Exit(nil);

  FLock.Enter;
  try
    case Descriptor.Lifetime of
      TServiceLifetime.Singleton:
      begin
        if FIsRootProvider then
        begin
          // Determine storage based on registration type (Class vs Interface)
          if Descriptor.IsInterfaceService then
          begin
            if FSingletonInterfaces.TryGetValue(AServiceType, Intf) then
            begin
               Result := Intf as TObject;
               Exit;
            end;
          end
          else
          begin
            if FSingletons.TryGetValue(AServiceType, Instance) then
              Exit(Instance);
          end;

          // Create new instance
          Instance := CreateInstance(Descriptor);
          
          // Store based on registration type
          if Descriptor.IsInterfaceService then
          begin
            if Supports(Instance, IInterface, Intf) then
              FSingletonInterfaces.Add(AServiceType, Intf);
          end
          else
            FSingletons.Add(AServiceType, Instance);
          
          Result := Instance;
        end
        else
          Result := FParentProvider.GetService(AServiceType);
      end;

      TServiceLifetime.Scoped:
      begin
        // Similar check for Scoped
        if Descriptor.IsInterfaceService then
        begin
          if FScopedInterfaces.TryGetValue(AServiceType, Intf) then
          begin
            Result := Intf as TObject;
            Exit;
          end;
        end
        else
        begin
          if FScopedInstances.TryGetValue(AServiceType, Instance) then
            Exit(Instance);
        end;

        // Create new instance
        Instance := CreateInstance(Descriptor);
        if Descriptor.IsInterfaceService then
        begin
          if Supports(Instance, IInterface, Intf) then
            FScopedInterfaces.Add(AServiceType, Intf);
        end
        else
          FScopedInstances.Add(AServiceType, Instance);
        Result := Instance;
      end;

      TServiceLifetime.Transient:
        Result := CreateInstance(Descriptor);
    else
      Result := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDextServiceProvider.GetServiceAsInterface(const AServiceType: TServiceType): IInterface;
var
  Descriptor: TServiceDescriptor;
  Intf: IInterface;
  Obj: TObject;
  ServiceGuid: TGUID;
  Resolved: Boolean;
begin
  // Special handling for IServiceProvider to return Self without dictionary cycle
  if AServiceType.IsInterface and IsEqualGUID(AServiceType.AsInterface, IServiceProvider) then
    Exit(Self);

  Descriptor := FindDescriptor(AServiceType);
  if not Assigned(Descriptor) then
    Exit(nil);

  ServiceGuid := AServiceType.AsInterface;

  FLock.Enter;
  try
    case Descriptor.Lifetime of
      TServiceLifetime.Singleton:
      begin
        if FIsRootProvider then
        begin
          if not FSingletonInterfaces.TryGetValue(AServiceType, Intf) then
          begin
            Obj := CreateInstance(Descriptor);
            if not IsEqualGUID(ServiceGuid, TGUID.Empty) then
              Resolved := GetServiceInterface(Obj, ServiceGuid, Intf)
            else
              Resolved := Supports(Obj, IInterface, Intf);
            if not Resolved then
            begin
              Obj.Free;
              raise EDextDIException.CreateFmt('Service %s does not implement IInterface', [Obj.ClassName]);
            end;
            FSingletonInterfaces.Add(AServiceType, Intf);
            // Note: The object is now owned by ARC via the interface reference
          end;
          Result := Intf;
        end
        else
          Result := FParentProvider.GetServiceAsInterface(AServiceType);
      end;

      TServiceLifetime.Scoped:
      begin
        if not FScopedInterfaces.TryGetValue(AServiceType, Intf) then
        begin
          Obj := CreateInstance(Descriptor);
          if not IsEqualGUID(ServiceGuid, TGUID.Empty) then
            Resolved := GetServiceInterface(Obj, ServiceGuid, Intf)
          else
            Resolved := Supports(Obj, IInterface, Intf);
          if not Resolved then
          begin
            Obj.Free;
            raise EDextDIException.CreateFmt('Service %s does not implement IInterface', [Obj.ClassName]);
          end;
          FScopedInterfaces.Add(AServiceType, Intf);
        end;
        Result := Intf;
      end;

      TServiceLifetime.Transient:
      begin
        Obj := CreateInstance(Descriptor);
        if not IsEqualGUID(ServiceGuid, TGUID.Empty) then
          Resolved := GetServiceInterface(Obj, ServiceGuid, Intf)
        else
          Resolved := Supports(Obj, IInterface, Intf);
        if not Resolved then
        begin
          Obj.Free;
          raise EDextDIException.CreateFmt('Service %s does not implement IInterface', [Obj.ClassName]);
        end;
        Result := Intf;
      end;
    else
      Result := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDextServiceProvider.GetRequiredService(const AServiceType: TServiceType): TObject;
begin
  Result := GetService(AServiceType);
  if not Assigned(Result) then
    raise EDextDIException.CreateFmt('Required service not found: %s', [AServiceType.ToString]);
end;

{ TDextServiceScope }

constructor TDextServiceScope.Create(AServiceProvider: IServiceProvider);
begin
  inherited Create;
  FServiceProvider := AServiceProvider;
end;

function TDextServiceScope.GetServiceProvider: IServiceProvider;
begin
  Result := FServiceProvider;
end;

initialization
  TDextDIFactory.CreateServiceCollectionFunc := 
    function: IServiceCollection
    begin
      Result := TDextServiceCollection.Create;
    end;

end.
