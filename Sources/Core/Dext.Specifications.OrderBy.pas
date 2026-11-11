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
unit Dext.Specifications.OrderBy;

interface

uses
  Dext.Specifications.Interfaces;

type
  /// <summary>
  ///   Implementation of IOrderBy for sorting specifications
  /// </summary>
  TOrderBy = class(TInterfacedObject, IOrderBy)
  private
    FPropertyName: string;
    FAscending: Boolean;
    FOwner: string;
  public
    constructor Create(const APropertyName: string; AAscending: Boolean;
      const AOwner: string = '');
    
    function GetPropertyName: string;
    function GetAscending: Boolean;
    function GetOwner: string;
  end;

implementation

{ TOrderBy }

constructor TOrderBy.Create(const APropertyName: string; AAscending: Boolean;
  const AOwner: string);
begin
  inherited Create;
  FPropertyName := APropertyName;
  FAscending := AAscending;
  FOwner := AOwner;
end;

function TOrderBy.GetOwner: string;
begin
  Result := FOwner;
end;

function TOrderBy.GetPropertyName: string;
begin
  Result := FPropertyName;
end;

function TOrderBy.GetAscending: Boolean;
begin
  Result := FAscending;
end;

end.

