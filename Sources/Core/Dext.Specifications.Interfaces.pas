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
unit Dext.Specifications.Interfaces;

interface

uses
  System.Rtti;

type
  TMatchMode = (mmExact, mmStart, mmEnd, mmAnywhere);
  TJoinType = (jtInner, jtLeft, jtRight, jtFull, jtCross);

  /// <summary>
  ///   Specifies the type of pessimistic lock to be applied to a query.
  /// </summary>
  TLockMode = (lmNone, lmShared, lmExclusive, lmExclusiveNoWait);

  /// <summary>
  ///   Represents an expression in a query (e.g., "Age > 18").
  /// </summary>
  IExpression = interface
    ['{D8D6EF4A-ED35-4833-8521-4B91D8C6901F}']
    function ToString: string; // For debugging/logging
  end;

  /// <summary>
  ///   Represents an order by clause.
  /// </summary>
  IOrderBy = interface
    ['{52493B12-2C04-4274-B07A-90074FED13B0}']
    function GetPropertyName: string;
    function GetAscending: Boolean;
    /// <summary>The table of the entity that declares the property ('' when
    ///   unknown): a query with joins orders by the column of that table.</summary>
    function GetOwner: string;
  end;

  /// <summary>
  ///   Represents a JOIN clause.
  /// </summary>
  IJoin = interface
    ['{0466EABA-BC1B-45B3-9D07-6F54E4C8E522}']
    function GetTableName: string;
    function GetAlias: string;
    function GetJoinType: TJoinType;
    function GetCondition: IExpression;
  end;

  /// <summary>
  ///   Base interface for specifications containing non-generic query members.
  /// </summary>
  ISpecification = interface
    ['{07C752B7-2DB8-42C7-85CC-B12398799703}']
    function GetExpression: IExpression;
    function GetIncludes: TArray<string>;
    function GetOrderBy: TArray<IOrderBy>;
    function GetSkip: Integer;
    function GetTake: Integer;
    function IsPagingEnabled: Boolean;
    function GetSelectedColumns: TArray<string>;
    function IsTrackingEnabled: Boolean;
    function GetJoins: TArray<IJoin>;
    function GetGroupBy: TArray<string>;
    function IsIgnoringFilters: Boolean;
    function IsOnlyDeleted: Boolean;
    function GetLockMode: TLockMode;
    function GetSignature: string;

    procedure Take(const ACount: Integer);
    procedure Skip(const ACount: Integer);
    procedure EnableTracking(const AValue: Boolean);
    procedure AsNoTracking;
    procedure Include(const APath: string);
    procedure RemoveInclude(const APath: string);
    procedure OrderBy(const AOrderBy: IOrderBy);
    procedure Select(const AColumn: string);
    procedure Where(const AExpression: IExpression);
    procedure Join(const ATable: string; const AAlias: string; AType: TJoinType; const ACondition: IExpression);
    procedure GroupBy(const AColumn: string);
    procedure IgnoreQueryFilters(const AValue: Boolean = True);
    procedure OnlyDeleted(const AValue: Boolean = True);
    procedure WithLock(const ALockMode: TLockMode);
    
    property Expression: IExpression read GetExpression;
  end;

  /// <summary>
  ///   Generic interface for specifications.
  ///   Encapsulates query logic for an entity type T.
  /// </summary>
  ISpecification<T> = interface(ISpecification)
    ['{1FBFFBCF-768E-44DB-8F6B-91C9B4A8EF45}']
    function Clone: ISpecification<T>;
    function AndSpec(const Other: ISpecification<T>): ISpecification<T>;
    function OrSpec(const Other: ISpecification<T>): ISpecification<T>;
    function NotSpec: ISpecification<T>;
    function IsSatisfiedBy(const AEntity: T): Boolean;
  end;

  /// <summary>
  ///   Visitor interface for traversing the expression tree.
  ///   This is used by the ORM/Repository to translate expressions to SQL.
  /// </summary>
  IExpressionVisitor = interface
    ['{970B2E95-CBB3-459B-8F51-3009CC4C366D}']
    procedure Visit(const AExpression: IExpression);
  end;

implementation

end.

