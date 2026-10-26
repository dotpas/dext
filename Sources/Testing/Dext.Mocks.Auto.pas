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

unit Dext.Mocks.Auto;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Interception,
  Dext.Interception.ClassProxy,
  Dext.Interception.Proxy,
  Dext.Mocks,
  Dext.Mocks.Interceptor;

type
  TAutoMocker = class
  private
    FInterceptors: IDictionary<PTypeInfo, IInterceptor>;
    FClassProxies: IDictionary<PTypeInfo, TObject>; // OwnsProxies
    FMocks: IDictionary<PTypeInfo, IMock>;
    function GetMockInterceptor(Info: PTypeInfo): IInterceptor;
  public
    constructor Create;
    destructor Destroy; override;
    function CreateInstance<T: class>: T;
    function GetMock<T>: Mock<T>;
  end;

implementation

uses
  Dext.Core.Reflection,
  System.Variants;

{ TAutoMocker }

constructor TAutoMocker.Create;
begin
  inherited Create;
  FInterceptors := TCollections.CreateDictionary<PTypeInfo, IInterceptor>;
  FClassProxies := TCollections.CreateDictionary<PTypeInfo, TObject>(True);
  FMocks := TCollections.CreateDictionary<PTypeInfo, IMock>;
end;

destructor TAutoMocker.Destroy;
var
  Interceptor: IInterceptor;
begin
  if FInterceptors <> nil then
  begin
    for Interceptor in FInterceptors.Values do
      (Interceptor as TMockInterceptor).ClearInterceptors;
    FInterceptors := nil;
  end;

  FMocks := nil;
  FClassProxies := nil; // own objects

  inherited;
end;

function TAutoMocker.GetMockInterceptor(Info: PTypeInfo): IInterceptor;
begin
  if not FInterceptors.TryGetValue(Info, Result) then
  begin
    Result := TMockInterceptor.Create(TMockBehavior.Loose);
    FInterceptors.Add(Info, Result);
  end;
end;

function TAutoMocker.GetMock<T>: Mock<T>;
var
  Info: PTypeInfo;
  MockRef: IMock;
  Interceptor: IInterceptor;
  CProxy: TObject;
begin
  Info := TypeInfo(T);
  if not (Info.Kind in [tkInterface, tkClass]) then
    raise Exception.Create('T must be an interface or class');
    
  if FMocks.TryGetValue(Info, MockRef) then
    Exit(Mock<T>.FromInterface(MockRef as IMock<T>));

  Interceptor := GetMockInterceptor(Info);
  if Info.Kind = tkClass then
  begin
    if not FClassProxies.TryGetValue(Info, CProxy) then
    begin
      CProxy := TClassProxy.Create(Info.TypeData.ClassType, [Interceptor], False);
      FClassProxies.Add(Info, CProxy);
    end;
    Result := Mock<T>.FromInterface(TMock<T>.Create(TMockInterceptor(Interceptor), TClassProxy(CProxy), False));
  end
  else
    Result := Mock<T>.FromInterface(TMock<T>.Create(TMockInterceptor(Interceptor)));

  FMocks.Add(Info, Result.ProxyInterface);
end;

function TAutoMocker.CreateInstance<T>: T;
var
  RttiType: TRttiType;
  Method, ConstructorMethod: TRttiMethod;
  Params: TArray<TRttiParameter>;
  Args: TArray<TValue>;
  ParamType: TRttiType;
  ParamInfo: PTypeInfo;
  Interceptor: IInterceptor;
  CProxy: TObject;
  ProxyObj: TInterfaceProxy;
  ProxyIntf: IInterface;
  I: Integer;
  ObjInstance: TObject;
begin
  RttiType := TReflection.Context.GetType(TypeInfo(T));
  if RttiType = nil then
    raise Exception.Create('Type not found in RTTI: ' + T.ClassName);

  ConstructorMethod := nil;
  for Method in RttiType.GetMethods do
  begin
    if Method.IsConstructor then
    begin
      if (ConstructorMethod = nil) or (Length(Method.GetParameters) > Length(ConstructorMethod.GetParameters)) then
        ConstructorMethod := Method;
    end;
  end;

  if ConstructorMethod = nil then
    raise Exception.Create('No constructor found for ' + T.ClassName);

  Params := ConstructorMethod.GetParameters;
  SetLength(Args, Length(Params));

  for I := 0 to High(Params) do
  begin
    ParamType := Params[I].ParamType;
    ParamInfo := ParamType.Handle;
    if (ParamType.TypeKind in [tkInterface, tkClass]) then
    begin
       Interceptor := GetMockInterceptor(ParamInfo);
       if ParamType.TypeKind = tkClass then
       begin
         if not FClassProxies.TryGetValue(ParamInfo, CProxy) then
         begin
           CProxy := TClassProxy.Create(ParamInfo.TypeData.ClassType, [Interceptor], False);
           FClassProxies.Add(ParamInfo, CProxy);
         end;
          // Fix: Use TValue.Make with correct TypeInfo to avoid RTTI typecast errors
          ObjInstance := TClassProxy(CProxy).Instance;
          TValue.Make(@ObjInstance, ParamInfo, Args[I]);
       end
       else
       begin
         if Length(ParamType.GetMethods) = 0 then
           raise EMockException.CreateFmt(
             'Cannot auto-mock %s for %s: the interface has no method RTTI. ' +
             'Declare it between {$M+} and {$M-} or inherit from IInvokable.',
             [ParamType.Name, T.ClassName]);
         ProxyObj := TInterfaceProxy.Create(ParamInfo, [Interceptor], TValue.Empty);
         if ProxyObj.QueryInterface(ParamInfo.TypeData.Guid, ProxyIntf) <> S_OK then
           raise Exception.Create('Failed to query interface for mock: ' + ParamType.Name);
         TValue.Make(@ProxyIntf, ParamInfo, Args[I]);
       end;
    end
    else
      TValue.Make(nil, ParamInfo, Args[I]);
  end;

  Result := ConstructorMethod.Invoke(RttiType.AsInstance.MetaclassType, Args).AsType<T>;
end;

end.
