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
{  Created: 2026-11-12                                                      }
{                                                                           }
{  Many-to-many join tables: Lazy<IList<T>> collections are read by         }
{  SaveChanges and PersistManyToMany, and the keys of both sides may be     }
{  composite (the join columns are listed in the order of the key           }
{  properties, separated by commas).                                        }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.ManyToManyKeys.Tests;

interface

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  Dext.Assertions,
  Dext.Collections,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Mapping,
  Dext.Testing.Attributes,
  Dext.Types.Lazy;

type
  TLzCourse = class;

  [Table('LzStudents')]
  TLzStudent = class
  private
    FId: Integer;
    FName: string;
    FCourses: Lazy<IList<TLzCourse>>;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    [ManyToMany('LzStudentCourses', 'student_id', 'course_id')]
    property Courses: Lazy<IList<TLzCourse>> read FCourses write FCourses;
  end;

  [Table('LzCourses')]
  TLzCourse = class
  private
    FId: Integer;
    FTitle: string;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Title: string read FTitle write FTitle;
  end;

  // A label whose key has two columns
  [Table('Labels')]
  TLabel = class
  private
    FArea: string;
    FCode: Integer;
    FText: string;
  public
    [PK]
    property Area: string read FArea write FArea;
    [PK]
    property Code: Integer read FCode write FCode;
    property Text: string read FText write FText;
  end;

  // Composite key on the owner and on the target, plain IList
  [Table('Orders')]
  TOrder = class
  private
    FSeries: string;
    FNumber: Integer;
    FLabels: IList<TLabel>;
  public
    constructor Create;
    [PK]
    property Series: string read FSeries write FSeries;
    [PK]
    property Number: Integer read FNumber write FNumber;
    [ManyToMany('OrdersLabels', 'order_series,order_number', 'label_area,label_code')]
    property Labels: IList<TLabel> read FLabels write FLabels;
  end;

  // The same, with a Lazy collection
  [Table('Shipments')]
  TShipment = class
  private
    FSeries: string;
    FNumber: Integer;
    FLabels: Lazy<IList<TLabel>>;
  public
    [PK]
    property Series: string read FSeries write FSeries;
    [PK]
    property Number: Integer read FNumber write FNumber;
    [ManyToMany('ShipmentsLabels', 'shipment_series,shipment_number', 'label_area,label_code')]
    property Labels: Lazy<IList<TLabel>> read FLabels write FLabels;
  end;

  // Lists one left column for a key of two
  // A key of two columns; the wrong join is declared by TBadDb only (the
  // scan of the process finds every class, and a broken join declared here
  // would fail every other fixture that creates a schema)
  TBadOrder = class
  private
    FSeries: string;
    FNumber: Integer;
    FLabels: IList<TLabel>;
  public
    constructor Create;
    [PK]
    property Series: string read FSeries write FSeries;
    [PK]
    property Number: Integer read FNumber write FNumber;
    property Labels: IList<TLabel> read FLabels write FLabels;
  end;

  // One left column for the key of two
  TBadDb = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  end;

  TManyToManyKeysBase = class
  protected
    FDbPath: string;
    FCtx: TDbContext;
    function Connect: IDbConnection;
    function NewContext: TDbContext; virtual;
    function Scalar(const ASql: string): Integer;
    function Courses: IDbSet<TLzCourse>;
    function Labels: IDbSet<TLabel>;
  public
    [Setup]
    procedure Setup; virtual;
    [TearDown]
    procedure TearDown; virtual;
  end;

  [TestFixture('Many-to-many with Lazy<IList<T>> collections')]
  TManyToManyLazyTests = class(TManyToManyKeysBase)
  protected
    function NewContext: TDbContext; override;
  public
    procedure Setup; override;
    [Test]
    procedure Lazy_Add_PersistManyToMany_WritesTheRow;
    [Test]
    procedure Lazy_Add_SaveChanges_WritesTheRow;
    [Test]
    procedure Lazy_Remove_SaveChanges_DeletesTheRow;
    [Test]
    procedure Lazy_Loaded_RemoveItem_SaveChanges_DeletesTheRow;
    [Test]
    procedure Lazy_Untouched_SaveChanges_KeepsTheRows;
    [Test]
    procedure Lazy_Loaded_AddThird_SaveChanges_AddsOneRow;
  end;

  [TestFixture('Many-to-many with composite keys')]
  TManyToManyCompositeTests = class(TManyToManyKeysBase)
  protected
    function NewContext: TDbContext; override;
  public
    procedure Setup; override;
    [Test]
    procedure JoinTableScript_ListsEveryColumn;
    [Test]
    procedure EnsureCreated_CreatesTheJoinTable;
    [Test]
    procedure Link_WritesAllTheKeyColumns;
    [Test]
    procedure Unlink_RemovesOnlyThatRow;
    [Test]
    procedure Sync_ReplacesTheSet;
    [Test]
    procedure SaveChanges_WritesAndRemovesRows;
    [Test]
    procedure PersistManyToMany_Deleted_RemovesOnlyTheOwnersRows;
    [Test]
    procedure Include_LoadsTheCollection;
    [Test]
    procedure LazyCollection_LoadsFromACompositeKey;
    [Test]
    procedure LazyCollection_SaveChanges_WritesTheRow;
    [Test]
    procedure WrongNumberOfColumns_Raises;
  end;

implementation

uses
  FireDAC.Comp.Client,
  FireDAC.ConsoleUI.Wait,
  FireDAC.DApt,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Stan.Async,
  FireDAC.Stan.Def,
  FireDAC.Stan.Error,
  FireDAC.Stan.ExprFuncs,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Pool,
  FireDAC.UI.Intf;

{ TOrder }

constructor TOrder.Create;
begin
  inherited Create;
  FLabels := TCollections.CreateList<TLabel>(False);
end;

{ TBadOrder }

constructor TBadOrder.Create;
begin
  inherited Create;
  FLabels := TCollections.CreateList<TLabel>(False);
end;

{ TBadDb }

procedure TBadDb.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TBadOrder>
    .HasManyToMany('Labels')
    .UsingEntity('BadJoin', 'order_series', 'label_area,label_code');
end;

{ TManyToManyKeysBase }


function TManyToManyKeysBase.Connect: IDbConnection;
var
  FDConn: TFDConnection;
begin
  FDConn := TFDConnection.Create(nil);
  FDConn.DriverName := 'SQLite';
  FDConn.Params.Values['Database'] := FDbPath;
  FDConn.Params.Values['LockingMode'] := 'Normal';
  Result := TFireDACConnection.Create(FDConn);
  Result.Connect;
end;

function TManyToManyKeysBase.NewContext: TDbContext;
begin
  Result := TDbContext.Create(Connect, TSQLiteDialect.Create);
end;

function TManyToManyKeysBase.Scalar(const ASql: string): Integer;
begin
  Result := FCtx.Connection.CreateCommand(ASql).ExecuteScalar.AsInteger;
end;

function TManyToManyKeysBase.Courses: IDbSet<TLzCourse>;
begin
  Result := FCtx.Entities<TLzCourse>;
end;

function TManyToManyKeysBase.Labels: IDbSet<TLabel>;
begin
  Result := FCtx.Entities<TLabel>;
end;

procedure TManyToManyKeysBase.Setup;
begin
  FDbPath := TPath.Combine(TPath.GetTempPath,
    'dext_m2m_keys_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.db');
  FCtx := NewContext;
  FCtx.EnsureCreated;
end;

procedure TManyToManyKeysBase.TearDown;
begin
  FreeAndNil(FCtx);
  if (FDbPath <> '') and TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);
end;

{ TManyToManyLazyTests }

function TManyToManyLazyTests.NewContext: TDbContext;
begin
  Result := inherited NewContext;
  Result.Entities<TLzStudent>;
  Result.Entities<TLzCourse>;
end;

procedure TManyToManyLazyTests.Setup;
var
  I: Integer;
  Student: TLzStudent;
  Course: TLzCourse;
begin
  inherited;
  for I := 1 to 2 do
  begin
    Student := TLzStudent.Create;
    Student.Name := 'Student ' + IntToStr(I);
    FCtx.Entities<TLzStudent>.Add(Student);
  end;
  for I := 1 to 3 do
  begin
    Course := TLzCourse.Create;
    Course.Title := 'Course ' + IntToStr(I);
    Courses.Add(Course);
  end;
  FCtx.SaveChanges;
end;

procedure TManyToManyLazyTests.Lazy_Add_PersistManyToMany_WritesTheRow;
var
  Student: TLzStudent;
begin
  Student := FCtx.Entities<TLzStudent>.Find(1);
  Student.Courses.Value.Add(Courses.Find(1));
  Should((FCtx.Entities<TLzStudent> as IDbSet).PersistManyToMany(Student, False)).Be(1);
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses')).Be(1);
end;

procedure TManyToManyLazyTests.Lazy_Add_SaveChanges_WritesTheRow;
var
  Student: TLzStudent;
begin
  Student := FCtx.Entities<TLzStudent>.Find(1);
  Student.Courses.Value.Add(Courses.Find(1));
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses')).Be(1);
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses WHERE student_id = 1 AND course_id = 1')).Be(1);
end;

procedure TManyToManyLazyTests.Lazy_Remove_SaveChanges_DeletesTheRow;
var
  Student: TLzStudent;
begin
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(1));
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(2));
  FCtx.DetachAll;

  Student := FCtx.Entities<TLzStudent>.Find(1);
  Should(Student.Courses.Value.Count).Be(2);
  Student.Courses.Value.Delete(0);
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses')).Be(1);
end;

procedure TManyToManyLazyTests.Lazy_Loaded_RemoveItem_SaveChanges_DeletesTheRow;
var
  Student: TLzStudent;
begin
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(1));
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(2));
  FCtx.DetachAll;

  Student := FCtx.Entities<TLzStudent>.Find(1);
  Should(Student.Courses.Value.Count).Be(2);
  Student.Courses.Value.Remove(Student.Courses.Value[0]);
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses')).Be(1);
end;

procedure TManyToManyLazyTests.Lazy_Untouched_SaveChanges_KeepsTheRows;
var
  Student: TLzStudent;
begin
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(1));
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(2));
  FCtx.DetachAll;

  Student := FCtx.Entities<TLzStudent>.Find(1);
  Student.Name := 'changed';
  FCtx.SaveChanges;
  // The collection was never read: the rows must stay.
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses')).Be(2);
end;

procedure TManyToManyLazyTests.Lazy_Loaded_AddThird_SaveChanges_AddsOneRow;
var
  Student: TLzStudent;
begin
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(1));
  FCtx.Entities<TLzStudent>.LinkManyToMany(FCtx.Entities<TLzStudent>.Find(1), 'Courses', Courses.Find(2));
  FCtx.DetachAll;

  Student := FCtx.Entities<TLzStudent>.Find(1);
  Should(Student.Courses.Value.Count).Be(2);
  Student.Courses.Value.Add(Courses.Find(3));
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM LzStudentCourses')).Be(3);
end;

{ TManyToManyCompositeTests }

function TManyToManyCompositeTests.NewContext: TDbContext;
begin
  Result := inherited NewContext;
  Result.Entities<TLabel>;
  Result.Entities<TOrder>;
  Result.Entities<TShipment>;
end;

procedure TManyToManyCompositeTests.Setup;
var
  Order: TOrder;
  Shipment: TShipment;
  Lbl: TLabel;
  I: Integer;
  Areas: array[0..2] of string;
  Codes: array[0..2] of Integer;
begin
  inherited;
  Areas[0] := 'x'; Codes[0] := 1;
  Areas[1] := 'x'; Codes[1] := 2;
  Areas[2] := 'y'; Codes[2] := 1;
  for I := 0 to 2 do
  begin
    Lbl := TLabel.Create;
    Lbl.Area := Areas[I];
    Lbl.Code := Codes[I];
    Lbl.Text := Areas[I] + IntToStr(Codes[I]);
    Labels.Add(Lbl);
  end;
  for I := 1 to 2 do
  begin
    Order := TOrder.Create;
    Order.Series := 'A';
    Order.Number := I;
    FCtx.Entities<TOrder>.Add(Order);
    Shipment := TShipment.Create;
    Shipment.Series := 'S';
    Shipment.Number := I;
    FCtx.Entities<TShipment>.Add(Shipment);
  end;
  FCtx.SaveChanges;
end;

procedure TManyToManyCompositeTests.JoinTableScript_ListsEveryColumn;
var
  Scripts: TArray<TJoinTableScript>;
begin
  Scripts := FCtx.Entities<TOrder>.GenerateJoinTableScripts;
  Should(Length(Scripts)).Be(1);
  Should(Scripts[0].TableName).Be('OrdersLabels');
  Should(Scripts[0].Sql).Contain('PRIMARY KEY ("order_series", "order_number", "label_area", "label_code")');
  Should(Scripts[0].Sql).Contain('FOREIGN KEY ("order_series", "order_number") REFERENCES');
  Should(Scripts[0].Sql).Contain('FOREIGN KEY ("label_area", "label_code") REFERENCES');
end;

procedure TManyToManyCompositeTests.EnsureCreated_CreatesTheJoinTable;
begin
  Should(FCtx.Connection.TableExists('OrdersLabels')).BeTrue;
  Should(FCtx.Connection.TableExists('ShipmentsLabels')).BeTrue;
end;

procedure TManyToManyCompositeTests.Link_WritesAllTheKeyColumns;
begin
  FCtx.Entities<TOrder>.LinkManyToMany(FCtx.Entities<TOrder>.Find(['A', 1]), 'Labels', Labels.Find(['x', 2]));
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(1);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels WHERE order_series = ''A'' AND order_number = 1 ' +
    'AND label_area = ''x'' AND label_code = 2')).Be(1);
end;

procedure TManyToManyCompositeTests.Unlink_RemovesOnlyThatRow;
var
  Order: TOrder;
begin
  Order := FCtx.Entities<TOrder>.Find(['A', 1]);
  FCtx.Entities<TOrder>.LinkManyToMany(Order, 'Labels', Labels.Find(['x', 1]));
  FCtx.Entities<TOrder>.LinkManyToMany(Order, 'Labels', Labels.Find(['x', 2]));
  FCtx.Entities<TOrder>.UnlinkManyToMany(Order, 'Labels', Labels.Find(['x', 1]));
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(1);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels WHERE label_area = ''x'' AND label_code = 2')).Be(1);
end;

procedure TManyToManyCompositeTests.Sync_ReplacesTheSet;
var
  Order: TOrder;
begin
  Order := FCtx.Entities<TOrder>.Find(['A', 1]);
  FCtx.Entities<TOrder>.SyncManyToMany(Order, 'Labels',
    TArray<TObject>.Create(Labels.Find(['x', 1]), Labels.Find(['x', 2])));
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(2);
  FCtx.Entities<TOrder>.SyncManyToMany(Order, 'Labels',
    TArray<TObject>.Create(Labels.Find(['x', 2]), Labels.Find(['y', 1])));
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(2);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels WHERE label_area = ''x'' AND label_code = 1')).Be(0);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels WHERE label_area = ''y'' AND label_code = 1')).Be(1);
end;

procedure TManyToManyCompositeTests.SaveChanges_WritesAndRemovesRows;
var
  Order: TOrder;
  First: TLabel;
begin
  Order := FCtx.Entities<TOrder>.Find(['A', 1]);
  First := Labels.Find(['x', 1]);
  Order.Labels.Add(First);
  Order.Labels.Add(Labels.Find(['x', 2]));
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(2);

  Order.Labels.Remove(First);
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(1);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels WHERE label_area = ''x'' AND label_code = 2')).Be(1);
end;

procedure TManyToManyCompositeTests.PersistManyToMany_Deleted_RemovesOnlyTheOwnersRows;
var
  First, Second: TOrder;
begin
  First := FCtx.Entities<TOrder>.Find(['A', 1]);
  Second := FCtx.Entities<TOrder>.Find(['A', 2]);
  FCtx.Entities<TOrder>.LinkManyToMany(First, 'Labels', Labels.Find(['x', 1]));
  FCtx.Entities<TOrder>.LinkManyToMany(First, 'Labels', Labels.Find(['x', 2]));
  FCtx.Entities<TOrder>.LinkManyToMany(Second, 'Labels', Labels.Find(['x', 1]));
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(3);

  (FCtx.Entities<TOrder> as IDbSet).PersistManyToMany(First, True);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels')).Be(1);
  Should(Scalar('SELECT COUNT(*) FROM OrdersLabels WHERE order_number = 2')).Be(1);
end;

procedure TManyToManyCompositeTests.Include_LoadsTheCollection;
var
  Orders: IList<TOrder>;
begin
  FCtx.Entities<TOrder>.LinkManyToMany(FCtx.Entities<TOrder>.Find(['A', 1]), 'Labels', Labels.Find(['x', 1]));
  FCtx.Entities<TOrder>.LinkManyToMany(FCtx.Entities<TOrder>.Find(['A', 1]), 'Labels', Labels.Find(['y', 1]));
  FCtx.Entities<TOrder>.LinkManyToMany(FCtx.Entities<TOrder>.Find(['A', 2]), 'Labels', Labels.Find(['x', 2]));
  FCtx.DetachAll;

  Orders := FCtx.Entities<TOrder>.QueryAll.Include('Labels').ToList;
  Should(Orders.Count).Be(2);
  Should(Orders[0].Labels.Count + Orders[1].Labels.Count).Be(3);
  if Orders[0].Number = 1 then
    Should(Orders[0].Labels.Count).Be(2)
  else
    Should(Orders[1].Labels.Count).Be(2);
end;

procedure TManyToManyCompositeTests.LazyCollection_LoadsFromACompositeKey;
var
  Shipment: TShipment;
begin
  FCtx.Entities<TShipment>.LinkManyToMany(FCtx.Entities<TShipment>.Find(['S', 1]), 'Labels', Labels.Find(['x', 1]));
  FCtx.Entities<TShipment>.LinkManyToMany(FCtx.Entities<TShipment>.Find(['S', 1]), 'Labels', Labels.Find(['y', 1]));
  FCtx.Entities<TShipment>.LinkManyToMany(FCtx.Entities<TShipment>.Find(['S', 2]), 'Labels', Labels.Find(['x', 2]));
  FCtx.DetachAll;

  Shipment := FCtx.Entities<TShipment>.Find(['S', 1]);
  Should(Shipment.Labels.Value.Count).Be(2);
  Should(Shipment.Labels.Value[0].Area + Shipment.Labels.Value[1].Area).Be('xy');
end;

procedure TManyToManyCompositeTests.LazyCollection_SaveChanges_WritesTheRow;
var
  Shipment: TShipment;
begin
  Shipment := FCtx.Entities<TShipment>.Find(['S', 2]);
  Shipment.Labels.Value.Add(Labels.Find(['y', 1]));
  FCtx.SaveChanges;
  Should(Scalar('SELECT COUNT(*) FROM ShipmentsLabels WHERE shipment_series = ''S'' AND shipment_number = 2 ' +
    'AND label_area = ''y'' AND label_code = 1')).Be(1);
end;

procedure TManyToManyCompositeTests.WrongNumberOfColumns_Raises;
var
  Ctx: TDbContext;
  Bad: TBadOrder;
begin
  Ctx := TBadDb.Create(Connect, TSQLiteDialect.Create);
  try
    Ctx.Entities<TBadOrder>;
    Bad := TBadOrder.Create;
    Bad.Series := 'B';
    Bad.Number := 1;
    Ctx.Entities<TBadOrder>.Add(Bad);
    Should(
      procedure
      begin
        Ctx.Entities<TBadOrder>.LinkManyToMany(Bad, 'Labels', Labels.Find(['x', 1]));
      end).Throw<Exception>.AndAlso.ThrowWithMessageContaining('Labels');
  finally
    Ctx.Free;
  end;
end;

end.
