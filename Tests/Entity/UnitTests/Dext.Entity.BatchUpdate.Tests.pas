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
{  SaveChanges checks the rows every UPDATE affects, as EF Core does: an    }
{  update that finds no row raises a concurrency exception, whether the     }
{  entity is updated alone or in a batch with others.                       }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.BatchUpdate.Tests;

interface

uses
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
  [Table('BATCH_UPD_WIDGETS')]
  TBatchUpdWidget = class
  private
    FID: IntType;
    FNAME: StringType;
  public
    [PK]
    property ID: IntType read FID write FID;
    property NAME: StringType read FNAME write FNAME;
  end;

  /// <summary>
  ///   Its own context class: the model of a context is cached by class, and
  ///   a model shared with other tests would create their tables here too
  ///   (a real server can refuse some of them).
  /// </summary>
  TBatchUpdateDb = class(TDbContext)
  end;

  /// <summary>
  ///   Rows 1, 2 and 3 are there before every test, in a SQLite database in
  ///   memory, or in a database of the server chosen by DEXT_TEST_SERVER (see
  ///   Dext.Entity.TestServer). Row 2 is removed from the table behind the context's back when a
  ///   test needs an update that finds nothing.
  /// </summary>
  [TestFixture('SaveChanges - rows affected by batch UPDATE')]
  TBatchUpdateTests = class
  private
    FCtx: TBatchUpdateDb;
    function Quoted(const AName: string): string;
    procedure ChangeRow(const AId: Integer);
    function NameOf(const AId: Integer): string;
    procedure DeleteBehindTheContext(const AId: Integer);
    function RowCount: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('A batch of updates that all find their row is applied')]
    procedure Batch_Updates_Existing_Rows;

    [Test]
    [Description('A batch with an update that finds no row raises a concurrency exception')]
    procedure Batch_With_A_Missing_Row_Raises;

    [Test]
    [Description('A failed batch applies none of its updates')]
    procedure Failed_Batch_Rolls_Back_The_Other_Updates;

    [Test]
    [Description('A single update that finds no row raises (control)')]
    procedure Single_Update_Of_A_Missing_Row_Raises;
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

{ TBatchUpdateTests }

const
  DbName = 'dext_ut_batchupd';

procedure TBatchUpdateTests.Setup;
var
  I: Integer;
  Widget: TBatchUpdWidget;
begin
  FCtx := TBatchUpdateDb.Create(TestDbOptions(DbName));
  TestDbPrepare(FCtx, DbName);
  FCtx.Entities<TBatchUpdWidget>;
  FCtx.EnsureCreated;

  for I := 1 to 3 do
  begin
    Widget := TBatchUpdWidget.Create;
    Widget.ID := I;
    Widget.NAME := 'widget ' + IntToStr(I);
    FCtx.Entities<TBatchUpdWidget>.Add(Widget);
  end;
  FCtx.SaveChanges;
end;

procedure TBatchUpdateTests.TearDown;
begin
  TestDbRelease(TDbContext(FCtx), DbName);
end;

function TBatchUpdateTests.Quoted(const AName: string): string;
begin
  Result := FCtx.Dialect.QuoteIdentifier(AName);
end;

procedure TBatchUpdateTests.ChangeRow(const AId: Integer);
var
  Widget: TBatchUpdWidget;
begin
  Widget := FCtx.Entities<TBatchUpdWidget>.Find(AId);
  Widget.NAME := 'changed ' + IntToStr(AId);
  FCtx.Entities<TBatchUpdWidget>.Update(Widget);
end;

function TBatchUpdateTests.NameOf(const AId: Integer): string;
begin
  Result := FCtx.Connection.CreateCommand(
    'SELECT ' + Quoted('NAME') + ' FROM ' + Quoted('BATCH_UPD_WIDGETS') +
    ' WHERE ' + Quoted('ID') + ' = ' + IntToStr(AId)).ExecuteScalar.AsString;
end;

procedure TBatchUpdateTests.DeleteBehindTheContext(const AId: Integer);
begin
  FCtx.Connection.CreateCommand(
    'DELETE FROM ' + Quoted('BATCH_UPD_WIDGETS') + ' WHERE ' + Quoted('ID') +
    ' = ' + IntToStr(AId)).ExecuteNonQuery;
end;

function TBatchUpdateTests.RowCount: Integer;
begin
  Result := FCtx.Connection.CreateCommand(
    'SELECT COUNT(*) FROM ' + Quoted('BATCH_UPD_WIDGETS')).ExecuteScalar.AsInteger;
end;

procedure TBatchUpdateTests.Batch_Updates_Existing_Rows;
begin
  ChangeRow(1);
  ChangeRow(2);

  FCtx.SaveChanges;

  Should(NameOf(1)).Be('changed 1');
  Should(NameOf(2)).Be('changed 2');
end;

procedure TBatchUpdateTests.Batch_With_A_Missing_Row_Raises;
begin
  ChangeRow(1);
  ChangeRow(2);
  DeleteBehindTheContext(2);

  Should(
    procedure
    begin
      FCtx.SaveChanges;
    end).Throw<EOptimisticConcurrencyException>;
end;

procedure TBatchUpdateTests.Failed_Batch_Rolls_Back_The_Other_Updates;
begin
  ChangeRow(1);
  ChangeRow(2);
  DeleteBehindTheContext(2);

  try
    FCtx.SaveChanges;
  except
    on E: EOptimisticConcurrencyException do ;
  end;

  // The update of row 1 was rolled back with the batch.
  Should(NameOf(1)).Be('widget 1');
end;

procedure TBatchUpdateTests.Single_Update_Of_A_Missing_Row_Raises;
begin
  ChangeRow(2);
  DeleteBehindTheContext(2);

  Should(
    procedure
    begin
      FCtx.SaveChanges;
    end).Throw<EOptimisticConcurrencyException>;
end;

end.
