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
unit Dext.DI.Interfaces;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Collections;

type
  IServiceCollection = interface;
  IServiceProvider = interface;

  TServiceLifetime = (Singleton, Transient, Scoped);

  EDextDIException = class(Exception);

  // Type to identify services (can be TClass or TGUID for interfaces)
  TServiceType = record
  private
    FTypeInfo: Pointer; // Used for Interface TypeInfo (or legacy)
    FClass: TClass;     // Explicitly store class reference
    FGuid: TGUID;       // Used for Interface GUID
    FIsInterface: Boolean;
  public
    // Constructors
    class function FromClass(AClass: TClass): TServiceType; overload; static;
    class function FromClass(ATypeInfo: PTypeInfo): TServiceType; overload; static;
    class function FromInterface(const AGuid: TGUID): TServiceType; overload; static;
    class function FromInterface(ATypeInfo: PTypeInfo): TServiceType; overload; static;

    // Checks
    function IsClass: Boolean;
    function IsInterface: Boolean;
    
    // Accessors
    function AsClass: TClass;
    function AsInterface: TGUID;
    function ToString: string;

    // Equality
    class operator Equal(const A, B: TServiceType): Boolean;
    
    // Implicit Conversion
    class operator Implicit(A: TClass): TServiceType;
    class operator Implicit(A: PTypeInfo): TServiceType;
  end;

  /// <summary>
  ///   Describes a service registration in the DI container.
  ///   Contains metadata about how to create and manage the service instance.
  /// </summary>
  TServiceDescriptor = class
  public
    ServiceType: TServiceType;
    ImplementationClass: TClass;
    Lifetime: TServiceLifetime;
    Factory: TFunc<IServiceProvider, TObject>;
    Instance: TObject;  // Pre-created instance for instance registration
    /// <summary>
    ///   True when the container owns the pre-created Instance (registered with
    ///   TDextServices.AddSingletonInstance) and frees it even if it was never
    ///   resolved. Other instance registrations stay with the caller.
    /// </summary>
    OwnsInstance: Boolean;
    /// <summary>
    ///   Indicates if this service was registered as an interface type.
    ///   Interface services are managed by ARC (TInterfacedObject).
    ///   Class services are managed explicitly by the DI container (Free).
    /// </summary>
    IsInterfaceService: Boolean;
    
    constructor Create(const AServiceType: TServiceType;
      AImplementationClass: TClass; ALifetime: TServiceLifetime;
      AFactory: TFunc<IServiceProvider, TObject>);
    function Clone: TServiceDescriptor;
    destructor Destroy; override;
  end;

  IServiceScope = interface
    ['{F2E7D3F4-9C6E-4B8A-8D2C-7F5A1B3E8D9F}']
    function GetServiceProvider: IServiceProvider;
    property ServiceProvider: IServiceProvider read GetServiceProvider;
  end;

  IServiceCollection = interface
    ['{A1F8C5D2-8B4E-4A7D-9C3B-6E8F4A2D1C7A}']
    function GetDescriptors: IList<TServiceDescriptor>;

    function AddSingleton(const AServiceType: TServiceType;
                         const AImplementationClass: TClass;
                         const AFactory: TFunc<IServiceProvider, TObject> = nil): IServiceCollection; overload;
    
    // Instance registration - register pre-created singleton instance
    function AddSingleton(const AServiceType: TServiceType;
                         AInstance: TObject): IServiceCollection; overload;

    function AddTransient(const AServiceType: TServiceType;
                          const AImplementationClass: TClass;
                          const AFactory: TFunc<IServiceProvider, TObject> = nil): IServiceCollection;

    function AddScoped(const AServiceType: TServiceType;
                       const AImplementationClass: TClass;
                       const AFactory: TFunc<IServiceProvider, TObject> = nil): IServiceCollection;

    procedure AddRange(const AOther: IServiceCollection);
    function BuildServiceProvider: IServiceProvider;
  end;

  IServiceProvider = interface
    ['{B2E7D3F4-9C6E-4B8A-8D2C-7F5A1B3E8D9F}']
    function GetService(const AServiceType: TServiceType): TObject;
    function GetServiceAsInterface(const AServiceType: TServiceType): IInterface;
    function GetRequiredService(const AServiceType: TServiceType): TObject;
    function CreateScope: IServiceScope;
  end;

  /// <summary>
  ///   Wrapper for IServiceCollection to provide Generic Extensions and Fluent API.
  /// </summary>
  /// <remarks>
  ///   <para><b>Interface vs Class Registration Lifecycle:</b></para>
  ///   <para>
  ///     - <b>Interface services</b> (AddSingleton&lt;IService, TImpl&gt;): Managed by ARC.
  ///       The object is automatically destroyed when no longer referenced.
  ///   </para>
  ///   <para>
  ///     - <b>Class services</b> (AddSingleton&lt;TClass&gt;): Managed by DI container.
  ///       Singleton/Scoped classes are freed when the container is destroyed.
  ///   </para>
  ///   <para>
  ///     - <b>Transient class services</b>: Created per request but NOT automatically freed.
  ///       Use with caution! Consider using interface-based registration for Transient
  ///       services to leverage ARC, or ensure manual disposal in endpoint code.
  ///   </para>
  ///   <para>
  ///     <b>Class Helper Inheritance:</b> This is a class (not record) to enable
  ///     class helper inheritance across packages (Core → Entity → Web).
  ///   </para>
  /// </remarks>
  TDextServices = record
  private
    FServices: IServiceCollection;
    class var FDefaultProvider: IServiceProvider;
  public
    class property DefaultProvider: IServiceProvider read FDefaultProvider write FDefaultProvider;
    constructor Create(AServices: IServiceCollection);
    class function New: TDextServices; static;
    function Unwrap: IServiceCollection;
    procedure AddRange(const AOther: TDextServices);
    property Collection: IServiceCollection read FServices;

    // Generic Overloads for Interface + Implementation pairs
    function AddSingleton<TService: IInterface; TImplementation: class>: TDextServices; overload; inline;
    function AddSingleton<TService: IInterface; TImplementation: class>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices; overload; inline;
    
    function AddTransient<TService: IInterface; TImplementation: class>: TDextServices; overload; inline;
    function AddTransient<TService: IInterface; TImplementation: class>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices; overload; inline;
    
    function AddScoped<TService: IInterface; TImplementation: class>: TDextServices; overload; inline;
    function AddScoped<TService: IInterface; TImplementation: class>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices; overload; inline;

    // Generic Overloads for Instance registration
    function AddSingleton<T: IInterface>(const AInstance: T): TDextServices; overload; inline;
    function AddSingletonInstance<T: class>(const AInstance: T): TDextServices; overload; inline;

    // Generic Overloads for Class-only registration (no interface)
    function AddSingleton<T: class>: TDextServices; overload; inline;
    function AddSingleton<T: class>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices; overload; inline;
    
    function AddTransient<T: class>: TDextServices; overload; inline;
    function AddTransient<T: class>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices; overload; inline;
    
    function AddScoped<T: class>: TDextServices; overload; inline;
    function AddScoped<T: class>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices; overload; inline;

    // Non-generic forwarding
    function AddSingleton(const AServiceType: TServiceType; const AImplementationClass: TClass; const AFactory: TFunc<IServiceProvider, TObject> = nil): TDextServices; overload; inline;
    function AddTransient(const AServiceType: TServiceType; const AImplementationClass: TClass; const AFactory: TFunc<IServiceProvider, TObject> = nil): TDextServices; overload; inline;
    function AddScoped(const AServiceType: TServiceType; const AImplementationClass: TClass; const AFactory: TFunc<IServiceProvider, TObject> = nil): TDextServices; overload; inline;

    function BuildServiceProvider: IServiceProvider; inline;

    // Resolution Extensions (v2)
    class function GetServiceObject<T: class>(const AProvider: IServiceProvider): T; static; inline;
    class function GetRequiredServiceObject<T: class>(const AProvider: IServiceProvider): T; static; inline;
    class function GetService<T: IInterface>(const AProvider: IServiceProvider): T; static; inline;
    class function GetRequiredService<T: IInterface>(const AProvider: IServiceProvider): T; static; inline;
  end;

  TDextDIFactory = class
  public
    class var CreateServiceCollectionFunc: TFunc<IServiceCollection>;
    class function CreateServiceCollection: IServiceCollection;
  end;

implementation

uses
  Dext.DI.Core;

{ TServiceDescriptor }

constructor TServiceDescriptor.Create(const AServiceType: TServiceType;
  AImplementationClass: TClass; ALifetime: TServiceLifetime;
  AFactory: TFunc<IServiceProvider, TObject>);
begin
  inherited Create;
  ServiceType := AServiceType;
  ImplementationClass := AImplementationClass;
  Lifetime := ALifetime;
  Factory := AFactory;
  Instance := nil;  // Initialize as nil (will be set for instance registration)
  OwnsInstance := False;
  // Determine ownership model based on how the service was registered
  IsInterfaceService := AServiceType.IsInterface;
end;

destructor TServiceDescriptor.Destroy;
begin
  Factory := nil; // Explicitly release the closure reference
  inherited;
end;

function TServiceDescriptor.Clone: TServiceDescriptor;
begin
  Result := TServiceDescriptor.Create(ServiceType, ImplementationClass, Lifetime, Factory);
  Result.IsInterfaceService := IsInterfaceService;
  Result.Instance := Instance;  // Copy instance reference (for instance registration)
  Result.OwnsInstance := OwnsInstance;
end;

{ TServiceType }

class function TServiceType.FromClass(AClass: TClass): TServiceType;
begin
  Result.FIsInterface := False;
  Result.FClass := AClass;
  Result.FTypeInfo := AClass.ClassInfo; // Keep it if available, but optional
end;

class function TServiceType.FromClass(ATypeInfo: PTypeInfo): TServiceType;
begin
  if (ATypeInfo = nil) or (ATypeInfo.Kind <> tkClass) then
    raise EDextDIException.Create('TypeInfo must be for a class');

  Result.FIsInterface := False;
  Result.FClass := GetTypeData(ATypeInfo)^.ClassType;
  Result.FTypeInfo := ATypeInfo;
end;

class function TServiceType.FromInterface(const AGuid: TGUID): TServiceType;
begin
  Result.FGuid := AGuid;
  Result.FTypeInfo := nil;
  Result.FClass := nil;
  Result.FIsInterface := True;
end;

class function TServiceType.FromInterface(ATypeInfo: PTypeInfo): TServiceType;
var
  LTypeData: PTypeData;
begin
  if (ATypeInfo = nil) or (ATypeInfo.Kind <> tkInterface) then
    raise EDextDIException.Create('TypeInfo must be for an interface');

  LTypeData := GetTypeData(ATypeInfo);
  Result.FGuid := LTypeData.Guid;
  Result.FTypeInfo := ATypeInfo;
  Result.FClass := nil;
  Result.FIsInterface := True;
end;

function TServiceType.IsClass: Boolean;
begin
  Result := not FIsInterface;
end;

function TServiceType.IsInterface: Boolean;
begin
  Result := FIsInterface;
end;

function TServiceType.AsClass: TClass;
var
  LTypeData: PTypeData;
begin
  if not FIsInterface then
  begin
    if FClass <> nil then
      Result := FClass
    else if FTypeInfo <> nil then
    begin
       // Fallback if FClass was somehow not set but TypeInfo was
       LTypeData := GetTypeData(FTypeInfo);
       if Assigned(LTypeData) then
         Result := LTypeData^.ClassType
       else
         raise EDextDIException.Create('Invalid class type info');
    end
    else
       raise EDextDIException.Create('Class TypeInfo is nil and FClass is nil');
  end
  else
    raise EDextDIException.Create('Service type is an interface, not a class');
end;

function TServiceType.AsInterface: TGUID;
begin
  if FIsInterface then
    Result := FGuid
  else
    raise EDextDIException.Create('Service type is a class, not an interface');
end;

function TServiceType.ToString: string;
begin
  if FIsInterface then
  begin
    // IMPORTANT: for generic interfaces (e.g., IList<T>) GUID may be shared
    // across different specializations. TypeInfo must be the primary identity.
    if FTypeInfo <> nil then
      Result := 'IT:' + IntToHex(NativeUInt(FTypeInfo), SizeOf(Pointer) * 2)
    else if not IsEqualGUID(FGuid, TGUID.Empty) then
      Result := 'I:' + GUIDToString(FGuid)
    else
      Result := 'I:EMPTY';
  end
  else
    Result := 'C:' + AsClass.ClassName;
end;

class operator TServiceType.Equal(const A, B: TServiceType): Boolean;
begin
  if A.FIsInterface <> B.FIsInterface then
    Exit(False);

  if A.FIsInterface then
  begin
    // IMPORTANT: when both have TypeInfo (common for generic interfaces),
    // compare TypeInfo first to avoid collisions between specializations.
    if (A.FTypeInfo <> nil) and (B.FTypeInfo <> nil) then
      Result := A.FTypeInfo = B.FTypeInfo
    else if not IsEqualGUID(A.FGuid, TGUID.Empty) and not IsEqualGUID(B.FGuid, TGUID.Empty) then
      Result := IsEqualGUID(A.FGuid, B.FGuid)
    else
      Result := A.FTypeInfo = B.FTypeInfo;
  end
  else
    Result := A.AsClass = B.AsClass;
end;

class operator TServiceType.Implicit(A: TClass): TServiceType;
begin
  Result := TServiceType.FromClass(A);
end;

class operator TServiceType.Implicit(A: PTypeInfo): TServiceType;
begin
  if A.Kind = tkInterface then
    Result := TServiceType.FromInterface(A)
  else
    Result := TServiceType.FromClass(A);
end;

{ TDextServices }

constructor TDextServices.Create(AServices: IServiceCollection);
begin
  FServices := AServices;
end;

class function TDextServices.New: TDextServices;
begin
  Result := TDextServices.Create(TDextDIFactory.CreateServiceCollection);
end;

procedure TDextServices.AddRange(const AOther: TDextServices);
begin
  if (FServices <> nil) and (AOther.FServices <> nil) then
    FServices.AddRange(AOther.FServices);
end;

function TDextServices.Unwrap: IServiceCollection;
begin
  Result := FServices;
end;

function TDextServices.AddSingleton<TService, TImplementation>: TDextServices;
begin
  Result := AddSingleton<TService, TImplementation>(nil);
end;

function TDextServices.AddSingleton<TService, TImplementation>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddSingleton(TServiceType.FromInterface(TypeInfo(TService)), TImplementation, AFactory);
  Result := Self;
end;

function TDextServices.AddSingletonInstance<T>(const AInstance: T): TDextServices;
begin
  FServices.AddSingleton(TServiceType.FromClass(TypeInfo(T)), AInstance);
  // The container assumes ownership of the instance (see the declaration).
  FServices.GetDescriptors.Last.OwnsInstance := True;
  Result := Self;
end;

function TDextServices.AddSingleton<T>(const AInstance: T): TDextServices;
begin
  FServices.AddSingleton(TServiceType.FromInterface(TypeInfo(T)), AInstance as TObject);
  Result := Self;
end;

function TDextServices.AddTransient<TService, TImplementation>: TDextServices;
begin
  Result := AddTransient<TService, TImplementation>(nil);
end;

function TDextServices.AddTransient<TService, TImplementation>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddTransient(TServiceType.FromInterface(TypeInfo(TService)), TImplementation, AFactory);
  Result := Self;
end;

function TDextServices.AddScoped<TService, TImplementation>: TDextServices;
begin
  Result := AddScoped<TService, TImplementation>(nil);
end;

function TDextServices.AddScoped<TService, TImplementation>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddScoped(TServiceType.FromInterface(TypeInfo(TService)), TImplementation, AFactory);
  Result := Self;
end;

function TDextServices.AddSingleton<T>: TDextServices;
begin
  Result := AddSingleton<T>(nil);
end;

function TDextServices.AddSingleton<T>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddSingleton(TServiceType.FromClass(T), T, AFactory);
  Result := Self;
end;

function TDextServices.AddTransient<T>: TDextServices;
begin
  Result := AddTransient<T>(nil);
end;

function TDextServices.AddTransient<T>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddTransient(TServiceType.FromClass(T), T, AFactory);
  Result := Self;
end;

function TDextServices.AddScoped<T>: TDextServices;
begin
  Result := AddScoped<T>(nil);
end;

function TDextServices.AddScoped<T>(const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddScoped(TServiceType.FromClass(T), T, AFactory);
  Result := Self;
end;

function TDextServices.AddSingleton(const AServiceType: TServiceType; const AImplementationClass: TClass; const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddSingleton(AServiceType, AImplementationClass, AFactory);
  Result := Self;
end;

function TDextServices.AddTransient(const AServiceType: TServiceType; const AImplementationClass: TClass; const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddTransient(AServiceType, AImplementationClass, AFactory);
  Result := Self;
end;

function TDextServices.AddScoped(const AServiceType: TServiceType; const AImplementationClass: TClass; const AFactory: TFunc<IServiceProvider, TObject>): TDextServices;
begin
  FServices.AddScoped(AServiceType, AImplementationClass, AFactory);
  Result := Self;
end;

function TDextServices.BuildServiceProvider: IServiceProvider;
begin
  Result := FServices.BuildServiceProvider;
  if FDefaultProvider = nil then
    FDefaultProvider := Result;
end;

{ TDextDIFactory }

class function TDextDIFactory.CreateServiceCollection: IServiceCollection;
begin
  if Assigned(CreateServiceCollectionFunc) then
    Result := CreateServiceCollectionFunc()
  else
    raise EDextDIException.Create('DI Factory not initialized. Make sure Dext.DI.Core is in your uses.');
end;

{ TDextServices resolution extensions }

class function TDextServices.GetRequiredService<T>(const AProvider: IServiceProvider): T;
var
  LService: IInterface;
begin
  if AProvider = nil then
    raise EDextDIException.Create('Service provider is not initialized');
    
  LService := AProvider.GetServiceAsInterface(TServiceType.FromInterface(TypeInfo(T)));
  if not Assigned(LService) then
    raise EDextDIException.Create('Service not registered: ' + string(PTypeInfo(TypeInfo(T))^.Name));
  IInterface(Result) := LService;
end;

class function TDextServices.GetRequiredServiceObject<T>(const AProvider: IServiceProvider): T;
var
  LObj: TObject;
begin
  if AProvider = nil then
    raise EDextDIException.Create('Service provider is not initialized');

  LObj := AProvider.GetRequiredService(TServiceType.FromClass(T));
  Result := T(LObj);
end;

class function TDextServices.GetService<T>(const AProvider: IServiceProvider): T;
var
  Intf: IInterface;
begin
  if AProvider = nil then
    Exit(Default(T));

  Intf := AProvider.GetServiceAsInterface(TServiceType.FromInterface(TypeInfo(T)));
  if Intf = nil then
    Exit(Default(T));
  IInterface(Result) := Intf;
end;

class function TDextServices.GetServiceObject<T>(const AProvider: IServiceProvider): T;
var
  LObj: TObject;
begin
  if AProvider = nil then
    Exit(nil);

  LObj := AProvider.GetService(TServiceType.FromClass(T));
  if LObj = nil then
    Exit(nil);
  Result := T(LObj);
end;

end.

