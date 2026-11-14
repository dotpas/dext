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
{  Created: 2026-11-11                                                      }
{                                                                           }
{  SaveChanges checks the rows every DELETE affects, as EF Core does: a     }
{  delete that finds no row raises a concurrency exception, whether the     }
{  entity is deleted alone or in a batch with others.                       }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.BatchDelete.Tests;

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
  [Table('BATCH_WIDGETS')]
  TBatchWidget = class
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
  TBatchDeleteDb = class(TDbContext)
  end;

  /// <summary>
  ///   Rows 1, 2 and 3 are there before every test, in a SQLite database in
  ///   memory, or in a database of the server chosen by DEXT_TEST_SERVER (see
  ///   Dext.Entity.TestServer). Row 2 is removed from the table behind the context's back when a
  ///   test needs a delete that finds nothing.
  /// </summary>
  [TestFixture('SaveChanges - rows affected by batch DELETE')]
  TBatchDeleteTests = class
  private
    FCtx: TBatchDeleteDb;
    function Quoted(const AName: string): string;
    procedure RemoveRow(const AId: Integer);
    procedure DeleteBehindTheContext(const AId: Integer);
    function RowCount: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('A batch of deletes that all find their row is applied')]
    procedure Batch_Deletes_Existing_Rows;

    [Test]
    [Description('A batch with a delete that finds no row raises a concurrency exception')]
    procedure Batch_With_A_Missing_Row_Raises;

    [Test]
    [Description('A failed batch applies none of its deletes')]
    procedure Failed_Batch_Rolls_Back_The_Other_Deletes;

    [Test]
    [Description('A single delete that finds no row raises (control)')]
    procedure Single_Delete_Of_A_Missing_Row_Raises;
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

{ TBatchDeleteTests }

const
  DbName = 'dext_ut_batchdel';

procedure TBatchDeleteTests.Setup;
var
  I: Integer;
  Widget: TBatchWidget;
begin
  FCtx := TBatchDeleteDb.Create(TestDbOptions(DbName));
  TestDbPrepare(FCtx, DbName);
  FCtx.Entities<TBatchWidget>;
  FCtx.EnsureCreated;

  for I := 1 to 3 do
  begin
    Widget := TBatchWidget.Create;
    Widget.ID := I;
    Widget.NAME := 'widget ' + IntToStr(I);
    FCtx.Entities<TBatchWidget>.Add(Widget);
  end;
  FCtx.SaveChanges;
end;

procedure TBatchDeleteTests.TearDown;
begin
  TestDbRelease(TDbContext(FCtx), DbName);
end;

function TBatchDeleteTests.Quoted(const AName: string): string;
begin
  Result := FCtx.Dialect.QuoteIdentifier(AName);
end;

procedure TBatchDeleteTests.RemoveRow(const AId: Integer);
begin
  FCtx.Entities<TBatchWidget>.Remove(FCtx.Entities<TBatchWidget>.Find(AId));
end;

procedure TBatchDeleteTests.DeleteBehindTheContext(const AId: Integer);
begin
  FCtx.Connection.CreateCommand(
    'DELETE FROM ' + Quoted('BATCH_WIDGETS') + ' WHERE ' + Quoted('ID') +
    ' = ' + IntToStr(AId)).ExecuteNonQuery;
end;

function TBatchDeleteTests.RowCount: Integer;
begin
  Result := FCtx.Connection.CreateCommand(
    'SELECT COUNT(*) FROM ' + Quoted('BATCH_WIDGETS')).ExecuteScalar.AsInteger;
end;

procedure TBatchDeleteTests.Batch_Deletes_Existing_Rows;
begin
  RemoveRow(1);
  RemoveRow(2);

  FCtx.SaveChanges;

  Should(RowCount).Be(1);
end;

procedure TBatchDeleteTests.Batch_With_A_Missing_Row_Raises;
begin
  RemoveRow(1);
  RemoveRow(2);
  DeleteBehindTheContext(2);

  Should(
    procedure
    begin
      FCtx.SaveChanges;
    end).Throw<EOptimisticConcurrencyException>;
end;

procedure TBatchDeleteTests.Failed_Batch_Rolls_Back_The_Other_Deletes;
begin
  RemoveRow(1);
  RemoveRow(2);
  DeleteBehindTheContext(2);

  try
    FCtx.SaveChanges;
  except
    on E: EOptimisticConcurrencyException do ;
  end;

  // Rows 1 and 3 remain: the delete of row 1 was rolled back with the batch.
  Should(RowCount).Be(2);
end;

procedure TBatchDeleteTests.Single_Delete_Of_A_Missing_Row_Raises;
begin
  RemoveRow(2);
  DeleteBehindTheContext(2);

  Should(
    procedure
    begin
      FCtx.SaveChanges;
    end).Throw<EOptimisticConcurrencyException>;
end;

end.
