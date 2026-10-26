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
{  Dext.Interception.ClassProxy - Virtual Method Interception for Classes   }
{                                                                           }
{***************************************************************************}
unit Dext.Interception.ClassProxy;

interface

uses
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Interception,
  Dext.Interception.Proxy,
  Dext.Core.Activator;

type
  /// <summary>
  ///   Proxy for class types using TVirtualMethodInterceptor.
  /// </summary>
  TClassProxy = class
  private
    FVMI: TVirtualMethodInterceptor;
    FInstance: TObject;
    FInterceptors: TArray<IInterceptor>;
    FOwnsInstance: Boolean;
    FInstanceIsDead: Boolean;
    
    procedure DoBefore(Instance: TObject; Method: TRttiMethod;
      const Args: TArray<TValue>; out DoInvoke: Boolean; out Result: TValue);
  public
    /// <summary>
    ///   Creates a class proxy. 
    ///   This instantiates the class using TActivator to ensure the constructor is executed.
    /// </summary>
    constructor Create(AClass: TClass; const AInterceptors: TArray<IInterceptor>; AOwnsInstance: Boolean = True);
    destructor Destroy; override;
    procedure Unproxify;
    
    property Instance: TObject read FInstance;
    property OwnsInstance: Boolean read FOwnsInstance write FOwnsInstance;
  end;

implementation

{ TClassProxy }

constructor TClassProxy.Create(AClass: TClass; const AInterceptors: TArray<IInterceptor>; AOwnsInstance: Boolean);
begin
  inherited Create;
  FInterceptors := AInterceptors;
  FOwnsInstance := AOwnsInstance;
  
  // Create instance using Activator to call the constructor
  FInstance := TActivator.CreateInstance(AClass, []);
  
  // Create Interceptor for the class
  FVMI := TVirtualMethodInterceptor.Create(AClass);
  
  // Setup callbacks
  FVMI.OnBefore := DoBefore;
  
  // Install interceptor on specific instance
  // This overwrites the VTable pointer in FInstance to point to VMI's dynamic VTable
  FVMI.Proxify(FInstance);
end;

procedure TClassProxy.Unproxify;
begin
  if Assigned(FVMI) then
  begin
    if Assigned(FInstance) and not FInstanceIsDead then
      FVMI.Unproxify(FInstance);
    FreeAndNil(FVMI);
  end;
end;

destructor TClassProxy.Destroy;
begin
  if FOwnsInstance and Assigned(FInstance) and not FInstanceIsDead then
    FreeAndNil(FInstance);
  
  Unproxify;
  inherited;
end;

procedure TClassProxy.DoBefore(Instance: TObject; Method: TRttiMethod;
  const Args: TArray<TValue>; out DoInvoke: Boolean; out Result: TValue);
var
  Invocation: IInvocation;
begin
  // Don't intercept TObject methods (lifecycle, etc.)
  if Method.Parent.AsInstance.MetaclassType = TObject then
  begin
    if SameText(Method.Name, 'BeforeDestruction') then
    begin
      // Revert VMT now while instance is still valid to avoid AV in destructor
      if Assigned(FVMI) then
      begin
        FVMI.Unproxify(Instance);
        FInstanceIsDead := True;
        FOwnsInstance := False;
      end;
    end;
    DoInvoke := True;
    Exit;
  end;

  // Don't intercept if dying
  if FInstanceIsDead then
  begin
    DoInvoke := True;
    Exit;
  end;

  // Create invocation wrapper
  Invocation := TInvocation.Create(Method, Args, FInterceptors, Instance);
  
  // Execute interception chain
  Invocation.Proceed;
  
  // An interceptor may ask for the inherited implementation to run
  if (Invocation as IInvocationCallBase).CallBaseRequested then
  begin
    DoInvoke := True;
    Exit;
  end;

  // Set result
  Result := Invocation.Result;
  
  // Suppress original execution (Loose mock behavior)
  DoInvoke := False;
end;

end.
