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
{  Created: 2026-01-03                                                      }
{                                                                           }
{  Dext.Interception - Core interception layer for proxying and AOP.        }
{                                                                           }
{  This unit provides the foundation for:                                   }
{  - Mocking frameworks (Dext.Mocks)                                        }
{  - Aspect-Oriented Programming (logging, caching, transactions)           }
{  - Security/Authorization interceptors                                    }
{  - Performance monitoring                                                 }
{                                                                           }
{***************************************************************************}
unit Dext.Interception;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.TypInfo;

type
  /// <summary>
  ///   Exception raised for interception-related errors.
  /// </summary>
  EInterceptionException = class(Exception);

  /// <summary>
  ///   Represents a method invocation that has been intercepted.
  ///   Provides access to the method metadata, arguments, and result.
  /// </summary>
  IInvocation = interface
    ['{A8C9E7B2-5D4F-4A3E-B1C0-9F8E7D6C5B4A}']
    /// <summary>Returns the RTTI method being invoked.</summary>
    function GetMethod: TRttiMethod;
    /// <summary>Returns the arguments passed to the method.</summary>
    function GetArguments: TArray<TValue>;
    /// <summary>Returns the current result value.</summary>
    function GetResult: TValue;
    /// <summary>Sets the result value to return from the method.</summary>
    procedure SetResult(const Value: TValue);
    /// <summary>Returns the target instance if proxying with target.</summary>
    function GetTarget: TValue;

    /// <summary>
    ///   Proceeds to the next interceptor in the chain, or to the
    ///   target method if this is the last interceptor.
    /// </summary>
    procedure Proceed;

    /// <summary>The RTTI method being invoked.</summary>
    property Method: TRttiMethod read GetMethod;
    /// <summary>The arguments passed to the method (modifiable for var/out params).</summary>
    property Arguments: TArray<TValue> read GetArguments;
    /// <summary>The return value of the method.</summary>
    property Result: TValue read GetResult write SetResult;
    /// <summary>The target instance (nil for proxies without target).</summary>
    property Target: TValue read GetTarget;
  end;

  /// <summary>
  ///   Optional capability of an invocation: lets an interceptor ask the proxy
  ///   to run the original implementation instead of the intercepted result.
  ///   Class proxies run the inherited method body; interface proxies with a
  ///   target forward the call to the target.
  /// </summary>
  IInvocationCallBase = interface
    ['{E4A1C7D2-8B3F-4E6A-9D5C-2F7B1A8E3C60}']
    procedure RequestCallBase;
    function GetCallBaseRequested: Boolean;
    property CallBaseRequested: Boolean read GetCallBaseRequested;
  end;

  /// <summary>
  ///   Interface for method interceptors. Implement this interface to
  ///   intercept method calls on proxied objects.
  /// </summary>
  /// <remarks>
  ///   Interceptors form a chain - call Invocation.Proceed to pass
  ///   control to the next interceptor or to the target method.
  /// </remarks>
  IInterceptor = interface
    ['{B7D8E9F0-6C5B-4A3D-8E7F-1A2B3C4D5E6F}']
    /// <summary>
    ///   Called when a method is invoked on the proxy.
    /// </summary>
    /// <param name="Invocation">The invocation context.</param>
    procedure Intercept(const Invocation: IInvocation);
  end;

  /// <summary>
  ///   Provides access to the proxy's interceptors and target.
  /// </summary>
  IProxyTargetAccessor = interface
    ['{C9E0F1A2-7D6C-5B4E-9F8A-2B3C4D5E6F7A}']
    function GetInterceptors: TArray<IInterceptor>;
    function GetTarget: TValue;

    property Interceptors: TArray<IInterceptor> read GetInterceptors;
    property Target: TValue read GetTarget;
  end;

  /// <summary>
  ///   Factory for creating proxy instances. Proxies intercept method
  ///   calls and delegate to the specified interceptors.
  /// </summary>
  TProxy = record
  public
    /// <summary>
    ///   Creates an interface proxy without a target.
    ///   All method calls go through the interceptor.
    /// </summary>
    /// <typeparam name="T">The interface type to proxy.</typeparam>
    /// <param name="Interceptor">The interceptor to handle method calls.</param>
    /// <returns>A proxy instance implementing T.</returns>
    class function CreateInterface<T>(
      const Interceptor: IInterceptor): T; overload; static;

    /// <summary>
    ///   Creates an interface proxy with multiple interceptors.
    /// </summary>
    class function CreateInterface<T>(
      const Interceptors: TArray<IInterceptor>): T; overload; static;

    /// <summary>
    ///   Creates an interface proxy with a target instance.
    ///   Method calls can be forwarded to the target via Proceed.
    /// </summary>
    /// <typeparam name="T">The interface type to proxy.</typeparam>
    /// <param name="Target">The target instance to wrap.</param>
    /// <param name="Interceptor">The interceptor to handle method calls.</param>
    /// <returns>A proxy instance implementing T.</returns>
    class function CreateInterfaceWithTarget<T>(
      const Target: T;
      const Interceptor: IInterceptor): T; overload; static;

    /// <summary>
    ///   Creates an interface proxy with a target and multiple interceptors.
    /// </summary>
    class function CreateInterfaceWithTarget<T>(
      const Target: T;
      const Interceptors: TArray<IInterceptor>): T; overload; static;
  end;

implementation

uses
  Dext.Core.Reflection,
  Dext.Interception.Proxy;

{ TProxy }

class function TProxy.CreateInterface<T>(const Interceptor: IInterceptor): T;
begin
  Result := CreateInterface<T>([Interceptor]);
end;

class function TProxy.CreateInterface<T>(const Interceptors: TArray<IInterceptor>): T;
var
  Proxy: IInterface;
  TypeInfo: PTypeInfo;
  RttiType: TRttiType;
begin
  TypeInfo := System.TypeInfo(T);
  if TypeInfo.Kind <> tkInterface then
    raise EInterceptionException.CreateFmt('Type %s is not an interface', [TypeInfo.Name]);

  // Verify interface has RTTI (requires {$M+} directive)
  RttiType := TReflection.Context.GetType(TypeInfo);
  if (RttiType = nil) or (Length(RttiType.GetMethods) = 0) then
    raise EInterceptionException.CreateFmt(
      'Interface %s has no RTTI. Add {$M+} directive before interface declaration.',
      [TypeInfo.Name]);

  // TInterfaceProxy inherits from TVirtualInterface which implements the target interface
  // The Supports call will keep the proxy alive via reference counting
  Proxy := TInterfaceProxy.Create(TypeInfo, Interceptors, TValue.Empty);
  if not Supports(Proxy, GetTypeData(TypeInfo).Guid, Result) then
    raise EInterceptionException.CreateFmt('Failed to create proxy for %s', [TypeInfo.Name]);
end;

class function TProxy.CreateInterfaceWithTarget<T>(const Target: T;
  const Interceptor: IInterceptor): T;
begin
  Result := CreateInterfaceWithTarget<T>(Target, [Interceptor]);
end;

class function TProxy.CreateInterfaceWithTarget<T>(const Target: T;
  const Interceptors: TArray<IInterceptor>): T;
var
  Proxy: IInterface;
  TypeInfo: PTypeInfo;
  TargetValue: TValue;
begin
  TypeInfo := System.TypeInfo(T);
  if TypeInfo.Kind <> tkInterface then
    raise EInterceptionException.CreateFmt('Type %s is not an interface', [TypeInfo.Name]);

  TValue.Make(@Target, TypeInfo, TargetValue);
  Proxy := TInterfaceProxy.Create(TypeInfo, Interceptors, TargetValue);
  if not Supports(Proxy, GetTypeData(TypeInfo).Guid, Result) then
    raise EInterceptionException.CreateFmt('Failed to create proxy for %s', [TypeInfo.Name]);
end;

end.
