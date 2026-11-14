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
{  The schema provider lists the tables of the database the connection      }
{  points to. On Oracle a "database" is a user: the connection can see the  }
{  tables of other users (WMSYS, SI_INFORMTN_SCHEMA...), and those are not  }
{  the tables to scaffold.                                                  }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.ScaffoldingServer.Tests;

interface

uses
  System.SysUtils,
  Dext.Assertions,
  Dext.Core.SmartTypes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Core,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Scaffolding,
  Dext.Entity.TestServer,
  Dext.Testing.Attributes;

type
  [Table('SCAF_ONE')]
  TScafOne = class
  private
    FID: IntType;
  public
    [PK]
    property ID: IntType read FID write FID;
  end;

  [Table('SCAF_TWO')]
  TScafTwo = class
  private
    FID: IntType;
  public
    [PK]
    property ID: IntType read FID write FID;
  end;

  TScafDb = class(TDbContext)
  end;

  [TestFixture('Schema provider lists only the tables of the connected database')]
  TScaffoldingServerTests = class
  private
    FCtx: TScafDb;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('GetTables returns the two tables the database has, and no table of another schema')]
    procedure GetTables_Returns_Only_The_Tables_Of_The_Database;
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
  DbName = 'dext_ut_scafsrv';

procedure TScaffoldingServerTests.Setup;
begin
  FCtx := TScafDb.Create(TestDbOptions(DbName));
  TestDbPrepare(FCtx, DbName);
  FCtx.Entities<TScafOne>;
  FCtx.Entities<TScafTwo>;
  FCtx.EnsureCreated;
end;

procedure TScaffoldingServerTests.TearDown;
begin
  TestDbRelease(TDbContext(FCtx), DbName);
end;

procedure TScaffoldingServerTests.GetTables_Returns_Only_The_Tables_Of_The_Database;
var
  Provider: ISchemaProvider;
  Tables: TArray<string>;
begin
  Provider := TFireDACSchemaProvider.Create(FCtx.Connection);
  Tables := Provider.GetTables;

  Should(Length(Tables)).Be(2);
end;

end.
