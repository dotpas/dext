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
{  The soft delete filter of an entity with a Boolean flag runs on every     }
{  server: the literal it compares with must fit the column type (on        }
{  InterBase, COALESCE(boolean, 0) is an arithmetic error).                 }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.SoftDeleteServer.Tests;

interface

uses
  System.SysUtils,
  Dext.Assertions,
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
  [Table('SOFT_SRV_TASKS'), SoftDelete('IsDeleted')]
  TSoftSrvTask = class
  private
    FId: Integer;
    FTitle: string;
    FIsDeleted: Boolean;
  public
    [PK]
    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;
    property IsDeleted: Boolean read FIsDeleted write FIsDeleted;
  end;

  TSoftDeleteServerDb = class(TDbContext)
  end;

  [TestFixture('Soft delete with a Boolean flag on every server')]
  TSoftDeleteServerTests = class
  private
    FCtx: TSoftDeleteServerDb;
    function NewTask(const AId: Integer): TSoftSrvTask;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('A soft deleted row is hidden from the list and from Find')]
    procedure Removed_Row_Is_Hidden;

    [Test]
    [Description('IgnoreQueryFilters still finds the soft deleted row')]
    procedure IgnoreQueryFilters_Finds_The_Removed_Row;
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
  DbName = 'dext_ut_softsrv';

procedure TSoftDeleteServerTests.Setup;
begin
  FCtx := TSoftDeleteServerDb.Create(TestDbOptions(DbName));
  TestDbPrepare(FCtx, DbName);
  FCtx.Entities<TSoftSrvTask>;
  FCtx.EnsureCreated;

  FCtx.Entities<TSoftSrvTask>.Add(NewTask(1));
  FCtx.Entities<TSoftSrvTask>.Add(NewTask(2));
  FCtx.SaveChanges;
end;

procedure TSoftDeleteServerTests.TearDown;
begin
  TestDbRelease(TDbContext(FCtx), DbName);
end;

function TSoftDeleteServerTests.NewTask(const AId: Integer): TSoftSrvTask;
begin
  Result := TSoftSrvTask.Create;
  Result.Id := AId;
  Result.Title := 'task ' + IntToStr(AId);
  Result.IsDeleted := False;
end;

procedure TSoftDeleteServerTests.Removed_Row_Is_Hidden;
begin
  FCtx.Entities<TSoftSrvTask>.Remove(FCtx.Entities<TSoftSrvTask>.Find(1));
  FCtx.SaveChanges;
  FCtx.Clear;

  Should(FCtx.Entities<TSoftSrvTask>.ToList.Count).Be(1);
  Should(FCtx.Entities<TSoftSrvTask>.Find(1) = nil).BeTrue;
end;

procedure TSoftDeleteServerTests.IgnoreQueryFilters_Finds_The_Removed_Row;
begin
  FCtx.Entities<TSoftSrvTask>.Remove(FCtx.Entities<TSoftSrvTask>.Find(1));
  FCtx.SaveChanges;
  FCtx.Clear;

  Should(FCtx.Entities<TSoftSrvTask>.IgnoreQueryFilters.Find(1) <> nil).BeTrue;
end;

end.
