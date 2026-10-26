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
{  Dext.Interception.Proxy - Interface proxy implementation using          }
{  TVirtualInterface from the Delphi RTL.                                   }
{                                                                           }
{***************************************************************************}
unit Dext.Interception.Proxy;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Interception;

type
  /// <summary>
  ///   Implementation of IInvocation that represents an intercepted method call.
  /// </summary>
  TInvocation = class(TInterfacedObject, IInvocation, IInvocationCallBase)
  private
    FMethod: TRttiMethod;
    FArguments: TArray<TValue>;
    FResult: TValue;
    FTarget: TValue;
    FInterceptors: TArray<IInterceptor>;
    FCurrentIndex: Integer;
    FCallBaseRequested: Boolean;
  protected
    function GetMethod: TRttiMethod;
    function GetArguments: TArray<TValue>;
    function GetResult: TValue;
    procedure SetResult(const Value: TValue);
    function GetTarget: TValue;
    procedure RequestCallBase;
    function GetCallBaseRequested: Boolean;
  public
    constructor Create(
      const AMethod: TRttiMethod;
      const AArguments: TArray<TValue>;
      const AInterceptors: TArray<IInterceptor>;
      const ATarget: TValue);

    procedure Proceed;

    property Method: TRttiMethod read GetMethod;
    property Arguments: TArray<TValue> read GetArguments;
    property Result: TValue read GetResult write SetResult;
    property Target: TValue read GetTarget;
  end;

  /// <summary>
  ///   Interface proxy implementation using TVirtualInterface.
  ///   Intercepts all method calls and delegates to interceptors.
  /// </summary>
  TInterfaceProxy = class(TVirtualInterface)
  private
    FInterceptors: TArray<IInterceptor>;
    FTarget: TValue;
    FTypeInfo: PTypeInfo;

    procedure HandleInvoke(Method: TRttiMethod;
      const Args: TArray<TValue>; out Result: TValue);
  public
    constructor Create(
      ATypeInfo: PTypeInfo;
      const AInterceptors: TArray<IInterceptor>;
      const ATarget: TValue);

    property Interceptors: TArray<IInterceptor> read FInterceptors;
    property Target: TValue read FTarget;
    property TypeInfo: PTypeInfo read FTypeInfo;
  end;

implementation

{ TInvocation }

constructor TInvocation.Create(
  const AMethod: TRttiMethod;
  const AArguments: TArray<TValue>;
  const AInterceptors: TArray<IInterceptor>;
  const ATarget: TValue);
begin
  inherited Create;
  FMethod := AMethod;
  FArguments := AArguments;
  FInterceptors := AInterceptors;
  FTarget := ATarget;
  FCurrentIndex := -1;
end;

function TInvocation.GetMethod: TRttiMethod;
begin
  Result := FMethod;
end;

function TInvocation.GetArguments: TArray<TValue>;
begin
  Result := FArguments;
end;

function TInvocation.GetResult: TValue;
begin
  Result := FResult;
end;

procedure TInvocation.SetResult(const Value: TValue);
begin
  FResult := Value;
end;

function TInvocation.GetTarget: TValue;
begin
  Result := FTarget;
end;

procedure TInvocation.RequestCallBase;
begin
  FCallBaseRequested := True;
end;

function TInvocation.GetCallBaseRequested: Boolean;
begin
  Result := FCallBaseRequested;
end;

procedure TInvocation.Proceed;
begin
  Inc(FCurrentIndex);

  if FCurrentIndex < Length(FInterceptors) then
  begin
    // Call next interceptor in chain
    FInterceptors[FCurrentIndex].Intercept(Self);
  end
  else if not FTarget.IsEmpty then
  begin
    // No more interceptors, call target method if available
    FResult := FMethod.Invoke(FTarget, FArguments);
  end;
  // If no target and no more interceptors, Result stays as-is (set by interceptor)
end;

{ TInterfaceProxy }

constructor TInterfaceProxy.Create(
  ATypeInfo: PTypeInfo;
  const AInterceptors: TArray<IInterceptor>;
  const ATarget: TValue);
begin
  // IMPORTANT: Initialize fields BEFORE calling inherited Create
  // because inherited Create might trigger HandleInvoke immediately
  FTypeInfo := ATypeInfo;
  FInterceptors := AInterceptors;
  FTarget := ATarget;

  // Now call inherited - this sets up the virtual interface
  inherited Create(ATypeInfo, HandleInvoke);
end;

procedure TInterfaceProxy.HandleInvoke(Method: TRttiMethod;
  const Args: TArray<TValue>; out Result: TValue);
var
  Invocation: IInvocation;
  Arguments: TArray<TValue>;
  I: Integer;
begin
  // Skip first argument (Self) - TVirtualInterface passes it as Args[0]
  if Length(Args) > 1 then
  begin
    SetLength(Arguments, Length(Args) - 1);
    for I := 1 to High(Args) do
      Arguments[I - 1] := Args[I];
  end
  else
    Arguments := nil;

  // Create invocation and start interceptor chain
  Invocation := TInvocation.Create(Method, Arguments, FInterceptors, FTarget);
  Invocation.Proceed;

  if (Invocation as IInvocationCallBase).CallBaseRequested and not FTarget.IsEmpty then
    Result := Method.Invoke(FTarget, Arguments)
  else
    Result := Invocation.Result;
end;

end.
