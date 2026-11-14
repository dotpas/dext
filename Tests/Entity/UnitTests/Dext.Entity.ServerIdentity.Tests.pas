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
{  Created: 2026-11-14                                                      }
{                                                                           }
{  An AutoInc key comes back from the server on insert (Oracle: INSERT ... }
{  RETURNING INTO an output parameter), and a whole number a query reads    }
{  (a key, a COUNT) is an integer on every server, not a decimal.           }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.ServerIdentity.Tests;

interface

uses
  System.Rtti,
  System.SysUtils,
  Dext.Assertions,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.TestServer,
  Dext.Testing.Attributes;

type
  [Table('IDENT_ITEMS')]
  TIdentItem = class
  private
    FID: IntType;
    FNAME: StringType;
  public
    [PK, AutoInc]
    property ID: IntType read FID write FID;
    property NAME: StringType read FNAME write FNAME;
  end;

  TIdentityDb = class(TDbContext)
  end;

  [TestFixture('Identity and whole numbers on every server')]
  TServerIdentityTests = class
  private
    FCtx: TIdentityDb;
    function Quoted(const AName: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('The AutoInc key of an inserted entity is filled in and is not zero')]
    procedure Insert_Fills_The_AutoInc_Key;

    [Test]
    [Description('Two inserted entities get two different keys')]
    procedure Two_Inserts_Get_Different_Keys;

    [Test]
    [Description('COUNT(*) read through a reader is an integer, not a decimal')]
    procedure Reader_Count_Is_An_Integer;

    [Test]
    [Description('COUNT(*) read as a scalar is an integer, not a decimal')]
    procedure Scalar_Count_Is_An_Integer;
  end;

implementation

uses
  FireDAC.Comp.Client,
  FireDAC.ConsoleUI.Wait,
  FireDAC.DApt,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool;

const
  DbName = 'dext_ut_identity';

procedure TServerIdentityTests.Setup;
begin
  FCtx := TIdentityDb.Create(TestDbOptions(DbName));
  TestDbPrepare(FCtx, DbName);
  FCtx.Entities<TIdentItem>;
  FCtx.EnsureCreated;
end;

procedure TServerIdentityTests.TearDown;
begin
  TestDbRelease(TDbContext(FCtx), DbName);
end;

function TServerIdentityTests.Quoted(const AName: string): string;
begin
  Result := FCtx.Dialect.QuoteIdentifier(AName);
end;

procedure TServerIdentityTests.Insert_Fills_The_AutoInc_Key;
var
  Item: TIdentItem;
begin
  Item := TIdentItem.Create;
  Item.NAME := 'first';
  FCtx.Entities<TIdentItem>.Add(Item);
  FCtx.SaveChanges;

  Should(Integer(Item.ID) > 0).BeTrue;
end;

procedure TServerIdentityTests.Two_Inserts_Get_Different_Keys;
var
  A, B: TIdentItem;
begin
  A := TIdentItem.Create;
  A.NAME := 'a';
  FCtx.Entities<TIdentItem>.Add(A);
  FCtx.SaveChanges;
  B := TIdentItem.Create;
  B.NAME := 'b';
  FCtx.Entities<TIdentItem>.Add(B);
  FCtx.SaveChanges;

  Should(Integer(A.ID) <> Integer(B.ID)).BeTrue;
end;

procedure TServerIdentityTests.Reader_Count_Is_An_Integer;
var
  Reader: IDbReader;
  V: TValue;
begin
  Reader := FCtx.Connection.CreateCommand(
    'SELECT COUNT(*) FROM ' + Quoted('IDENT_ITEMS')).ExecuteQuery;
  Reader.Next;
  V := Reader.GetValue(0);

  Should(V.Kind in [tkInteger, tkInt64]).BeTrue;
  Should(V.AsInt64).Be(0);
end;

procedure TServerIdentityTests.Scalar_Count_Is_An_Integer;
var
  V: TValue;
begin
  V := FCtx.Connection.CreateCommand(
    'SELECT COUNT(*) FROM ' + Quoted('IDENT_ITEMS')).ExecuteScalar;

  Should(V.Kind in [tkInteger, tkInt64]).BeTrue;
  Should(V.AsInt64).Be(0);
end;

end.
