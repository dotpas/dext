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
{  Created: 2026-10-16                                                      }
{                                                                           }
{  Regression tests for issue #267: IDbSet.PersistUpdate must take          }
{  ownership of the entity up front, even when the UPDATE fails or the key  }
{  is already tracked by the identity map.                                  }
{                                                                           }
{***************************************************************************}
unit Dext.Entity.PersistOwnership.Tests;

interface

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  Dext.Assertions,
  Dext.Core.SmartTypes,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Core,
  Dext.Entity.DbSet,
  Dext.Entity.Dialects,
  Dext.Entity.Validator,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Drivers.Interfaces,
  Dext.Testing.Attributes;

type
  [Table('OWNERSHIP_WIDGETS')]
  TOwnershipWidget = class
  private
    FID: IntType;
    FNAME: StringType;
  public
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;

    [PK]
    property ID: IntType read FID write FID;
    property NAME: StringType read FNAME write FNAME;
  end;

  // An entity with validation rules, for the range persistence tests
  [Table('RANGE_WIDGETS')]
  TRangeWidget = class
  private
    FID: IntType;
    FNAME: StringType;
  public
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;

    [PK]
    property ID: IntType read FID write FID;
    [Required, MaxLength(10)]
    property NAME: StringType read FNAME write FNAME;
  end;

  [TestFixture('PersistAddRange/UpdateRange/RemoveRange - ownership and validation')]
  TPersistRangeTests = class
  private
    FDbPath: string;
    function NewContext: TDbContext;
    function NewWidget(const AId: Integer): TOwnershipWidget;
    function NewRange(const AId: Integer; const AName: string): TRangeWidget;
    function CountRows(const ATable: string): Integer;
    function NameOf(const AId: Integer): string;
    function Leaked(const ACase: TProc): Integer;
    procedure RunAddRange;
    procedure RunAddRangeDuplicateKey;
    procedure RunUpdateRangeSecondInstance;
    procedure RunRemoveRange;
    procedure RunAddRangeInvalid;
    procedure RunUpdateRangeInvalid;
    procedure RunPersistAdd;
    procedure RunPersistRemoveStub;
    procedure RunPersistAddInvalid;
    procedure RunPersistUpdateInvalid;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('PersistAddRange must adopt the entities it inserts')]
    procedure PersistAddRange_AdoptsTheEntities;

    [Test]
    [Description('PersistAddRange must adopt the entities even when the insert fails')]
    procedure PersistAddRange_FailedInsert_AdoptsTheEntities;

    [Test]
    [Description('PersistUpdateRange must adopt an instance that is not the tracked one')]
    procedure PersistUpdateRange_SecondInstance_AdoptsTheEntities;

    [Test]
    [Description('PersistRemoveRange must adopt the entities it deletes')]
    procedure PersistRemoveRange_AdoptsTheEntities;

    [Test]
    [Description('PersistRemoveRange deletes the rows')]
    procedure PersistRemoveRange_DeletesTheRows;

    [Test]
    [Description('PersistAddRange validates: nothing is inserted and nothing leaks')]
    procedure PersistAddRange_InvalidEntity_RaisesAndInsertsNothing;

    [Test]
    [Description('PersistAddRange inserts valid entities (control)')]
    procedure PersistAddRange_ValidEntities_Inserts;

    [Test]
    [Description('PersistUpdateRange validates: the row keeps its value')]
    procedure PersistUpdateRange_InvalidEntity_RaisesAndUpdatesNothing;

    [Test]
    [Description('PersistRemoveRange does not validate: an invalid entity can be deleted')]
    procedure PersistRemoveRange_DoesNotValidate;

    [Test]
    [Description('PersistAdd must adopt the entity it inserts')]
    procedure PersistAdd_AdoptsTheEntity;

    [Test]
    [Description('PersistRemove must adopt an instance that is not the tracked one')]
    procedure PersistRemove_SecondInstance_AdoptsTheEntity;

    [Test]
    [Description('PersistAdd validates the entity, as SaveChanges does')]
    procedure PersistAdd_InvalidEntity_RaisesAndInsertsNothing;

    [Test]
    [Description('PersistUpdate validates the entity, as SaveChanges does')]
    procedure PersistUpdate_InvalidEntity_RaisesAndUpdatesNothing;
  end;

  [TestFixture('Issue #267 - PersistUpdate entity ownership')]
  TPersistUpdateOwnershipTests = class
  private
    FDbPath: string;
    function NewContext: TDbContext;
    function NewWidget(const AId: Integer): TOwnershipWidget;
    procedure RunUpdateMissingRow;
    procedure RunPersistUpdateMissingRow;
    procedure RunUpdateSecondInstance;
    procedure RunPersistUpdateSecondInstance;
    procedure RunPersistUpdateTrackedInstance;
    function Leaked(const ACase: TProc): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('Update + SaveChanges on a missing row must not leak (control)')]
    procedure Update_MissingRow_DoesNotLeak;

    [Test]
    [Description('PersistUpdate on a missing row must adopt the entity before raising')]
    procedure PersistUpdate_MissingRow_DoesNotLeak;

    [Test]
    [Description('Update + SaveChanges with a second instance for a tracked key must not leak (control)')]
    procedure Update_SecondInstance_DoesNotLeak;

    [Test]
    [Description('PersistUpdate with a second instance for a tracked key must adopt it')]
    procedure PersistUpdate_SecondInstance_DoesNotLeak;

    [Test]
    [Description('PersistUpdate with the instance already tracked must not double free')]
    procedure PersistUpdate_TrackedInstance_DoesNotLeakOrDoubleFree;
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

const
  EXISTING_ID = 1;
  MISSING_ID = 99;

var
  GLiveWidgets: Integer = 0;

{ TOwnershipWidget }

class function TOwnershipWidget.NewInstance: TObject;
begin
  Result := inherited NewInstance;
  Inc(GLiveWidgets);
end;

procedure TOwnershipWidget.FreeInstance;
begin
  Dec(GLiveWidgets);
  inherited;
end;

{ TRangeWidget }

class function TRangeWidget.NewInstance: TObject;
begin
  Result := inherited NewInstance;
  Inc(GLiveWidgets);
end;

procedure TRangeWidget.FreeInstance;
begin
  Dec(GLiveWidgets);
  inherited;
end;

{ TPersistRangeTests }

procedure TPersistRangeTests.Setup;
var
  Ctx: TDbContext;
  Widget: TOwnershipWidget;
  Range: TRangeWidget;
begin
  FDbPath := TPath.Combine(TPath.GetTempPath,
    'dext_persist_range_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.db');
  Ctx := NewContext;
  try
    Ctx.EnsureCreated;
    Widget := NewWidget(EXISTING_ID);
    Widget.NAME := 'existing';
    Ctx.Entities<TOwnershipWidget>.Add(Widget);
    Range := NewRange(EXISTING_ID, 'one');
    Ctx.Entities<TRangeWidget>.Add(Range);
    Ctx.SaveChanges;
  finally
    Ctx.Free;
  end;
end;

procedure TPersistRangeTests.TearDown;
begin
  if (FDbPath <> '') and TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);
end;

function TPersistRangeTests.NewContext: TDbContext;
var
  FDConn: TFDConnection;
  Conn: IDbConnection;
begin
  FDConn := TFDConnection.Create(nil);
  FDConn.DriverName := 'SQLite';
  FDConn.Params.Values['Database'] := FDbPath;
  FDConn.Params.Values['LockingMode'] := 'Normal';
  Conn := TFireDACConnection.Create(FDConn);
  Conn.Connect;
  Result := TDbContext.Create(Conn, TSQLiteDialect.Create);
  Result.Entities<TOwnershipWidget>;
  Result.Entities<TRangeWidget>;
end;

function TPersistRangeTests.NewWidget(const AId: Integer): TOwnershipWidget;
begin
  Result := TOwnershipWidget.Create;
  Result.ID := AId;
  Result.NAME := 'written';
end;

function TPersistRangeTests.NewRange(const AId: Integer; const AName: string): TRangeWidget;
begin
  Result := TRangeWidget.Create;
  Result.ID := AId;
  Result.NAME := AName;
end;

function TPersistRangeTests.CountRows(const ATable: string): Integer;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    Result := Ctx.Connection.CreateCommand('SELECT COUNT(*) FROM ' + ATable).ExecuteScalar.AsInteger;
  finally
    Ctx.Free;
  end;
end;

function TPersistRangeTests.NameOf(const AId: Integer): string;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    Result := Ctx.Connection.CreateCommand(
      'SELECT NAME FROM RANGE_WIDGETS WHERE ID = ' + IntToStr(AId)).ExecuteScalar.ToString;
  finally
    Ctx.Free;
  end;
end;

function TPersistRangeTests.Leaked(const ACase: TProc): Integer;
var
  Before: Integer;
begin
  Before := GLiveWidgets;
  ACase();
  Result := GLiveWidgets - Before;
end;

procedure TPersistRangeTests.RunAddRange;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistAddRange(
      TArray<TObject>.Create(NewWidget(10), NewWidget(11)));
  finally
    Ctx.Free;
  end;
end;

procedure TPersistRangeTests.RunAddRangeDuplicateKey;
var
  Ctx: TDbContext;
  Raised: Boolean;
begin
  Raised := False;
  Ctx := NewContext;
  try
    try
      (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistAddRange(
        TArray<TObject>.Create(NewWidget(EXISTING_ID), NewWidget(12)));
    except
      on E: Exception do
        Raised := True;
    end;
  finally
    Ctx.Free;
  end;
  Should(Raised).BeTrue;
end;

procedure TPersistRangeTests.RunUpdateRangeSecondInstance;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    Ctx.Entities<TOwnershipWidget>.Find(EXISTING_ID);
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistUpdateRange(
      TArray<TObject>.Create(NewWidget(EXISTING_ID)));
  finally
    Ctx.Free;
  end;
end;

procedure TPersistRangeTests.RunRemoveRange;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistRemoveRange(
      TArray<TObject>.Create(NewWidget(EXISTING_ID)));
  finally
    Ctx.Free;
  end;
end;

procedure TPersistRangeTests.RunAddRangeInvalid;
var
  Ctx: TDbContext;
  Raised: Boolean;
begin
  Raised := False;
  Ctx := NewContext;
  try
    try
      (Ctx.Entities<TRangeWidget> as IDbSet).PersistAddRange(
        TArray<TObject>.Create(NewRange(10, 'ok'), NewRange(11, '')));
    except
      on E: EValidationException do
        Raised := True;
    end;
  finally
    Ctx.Free;
  end;
  Should(Raised).BeTrue;
end;

procedure TPersistRangeTests.RunUpdateRangeInvalid;
var
  Ctx: TDbContext;
  Raised: Boolean;
begin
  Raised := False;
  Ctx := NewContext;
  try
    try
      (Ctx.Entities<TRangeWidget> as IDbSet).PersistUpdateRange(
        TArray<TObject>.Create(NewRange(EXISTING_ID, 'much too long a name')));
    except
      on E: EValidationException do
        Raised := True;
    end;
  finally
    Ctx.Free;
  end;
  Should(Raised).BeTrue;
end;

procedure TPersistRangeTests.PersistAddRange_AdoptsTheEntities;
begin
  Should(Leaked(RunAddRange)).Be(0);
  Should(CountRows('OWNERSHIP_WIDGETS')).Be(3);
end;

procedure TPersistRangeTests.PersistAddRange_FailedInsert_AdoptsTheEntities;
begin
  Should(Leaked(RunAddRangeDuplicateKey)).Be(0);
end;

procedure TPersistRangeTests.PersistUpdateRange_SecondInstance_AdoptsTheEntities;
begin
  Should(Leaked(RunUpdateRangeSecondInstance)).Be(0);
end;

procedure TPersistRangeTests.PersistRemoveRange_AdoptsTheEntities;
begin
  Should(Leaked(RunRemoveRange)).Be(0);
end;

procedure TPersistRangeTests.PersistRemoveRange_DeletesTheRows;
begin
  RunRemoveRange;
  Should(CountRows('OWNERSHIP_WIDGETS')).Be(0);
end;

procedure TPersistRangeTests.PersistAddRange_InvalidEntity_RaisesAndInsertsNothing;
begin
  Should(Leaked(RunAddRangeInvalid)).Be(0);
  Should(CountRows('RANGE_WIDGETS')).Be(1);
end;

procedure TPersistRangeTests.PersistAddRange_ValidEntities_Inserts;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    (Ctx.Entities<TRangeWidget> as IDbSet).PersistAddRange(
      TArray<TObject>.Create(NewRange(10, 'ok'), NewRange(11, 'fine')));
  finally
    Ctx.Free;
  end;
  Should(CountRows('RANGE_WIDGETS')).Be(3);
end;

procedure TPersistRangeTests.PersistUpdateRange_InvalidEntity_RaisesAndUpdatesNothing;
begin
  Should(Leaked(RunUpdateRangeInvalid)).Be(0);
  Should(NameOf(EXISTING_ID)).Be('one');
end;

procedure TPersistRangeTests.PersistRemoveRange_DoesNotValidate;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    (Ctx.Entities<TRangeWidget> as IDbSet).PersistRemoveRange(
      TArray<TObject>.Create(NewRange(EXISTING_ID, '')));
  finally
    Ctx.Free;
  end;
  Should(CountRows('RANGE_WIDGETS')).Be(0);
end;

procedure TPersistRangeTests.RunPersistAdd;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistAdd(NewWidget(10));
  finally
    Ctx.Free;
  end;
end;

procedure TPersistRangeTests.RunPersistRemoveStub;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistRemove(
      NewWidget(EXISTING_ID));
  finally
    Ctx.Free;
  end;
end;

procedure TPersistRangeTests.RunPersistAddInvalid;
var
  Ctx: TDbContext;
  Raised: Boolean;
begin
  Raised := False;
  Ctx := NewContext;
  try
    try
      (Ctx.Entities<TRangeWidget> as IDbSet).PersistAdd(NewRange(10, ''));
    except
      on E: EValidationException do
        Raised := True;
    end;
  finally
    Ctx.Free;
  end;
  Should(Raised).BeTrue;
end;

procedure TPersistRangeTests.RunPersistUpdateInvalid;
var
  Ctx: TDbContext;
  Raised: Boolean;
begin
  Raised := False;
  Ctx := NewContext;
  try
    try
      (Ctx.Entities<TRangeWidget> as IDbSet).PersistUpdate(
        NewRange(EXISTING_ID, 'much too long a name'));
    except
      on E: EValidationException do
        Raised := True;
    end;
  finally
    Ctx.Free;
  end;
  Should(Raised).BeTrue;
end;

procedure TPersistRangeTests.PersistAdd_AdoptsTheEntity;
begin
  Should(Leaked(RunPersistAdd)).Be(0);
  Should(CountRows('OWNERSHIP_WIDGETS')).Be(2);
end;

procedure TPersistRangeTests.PersistRemove_SecondInstance_AdoptsTheEntity;
begin
  Should(Leaked(RunPersistRemoveStub)).Be(0);
  Should(CountRows('OWNERSHIP_WIDGETS')).Be(0);
end;

procedure TPersistRangeTests.PersistAdd_InvalidEntity_RaisesAndInsertsNothing;
begin
  Should(Leaked(RunPersistAddInvalid)).Be(0);
  Should(CountRows('RANGE_WIDGETS')).Be(1);
end;

procedure TPersistRangeTests.PersistUpdate_InvalidEntity_RaisesAndUpdatesNothing;
begin
  Should(Leaked(RunPersistUpdateInvalid)).Be(0);
  Should(NameOf(EXISTING_ID)).Be('one');
end;

{ TPersistUpdateOwnershipTests }

procedure TPersistUpdateOwnershipTests.Setup;
var
  Ctx: TDbContext;
  Widget: TOwnershipWidget;
begin
  FDbPath := TPath.Combine(TPath.GetTempPath,
    'dext_persist_ownership_' + TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.db');

  Ctx := NewContext;
  try
    Ctx.EnsureCreated;
    Widget := TOwnershipWidget.Create;
    Widget.ID := EXISTING_ID;
    Widget.NAME := 'existing';
    Ctx.Entities<TOwnershipWidget>.Add(Widget);
    Ctx.SaveChanges;
  finally
    Ctx.Free;
  end;
end;

procedure TPersistUpdateOwnershipTests.TearDown;
begin
  if (FDbPath <> '') and TFile.Exists(FDbPath) then
    TFile.Delete(FDbPath);
end;

function TPersistUpdateOwnershipTests.NewContext: TDbContext;
var
  FDConn: TFDConnection;
  Conn: IDbConnection;
begin
  FDConn := TFDConnection.Create(nil);
  FDConn.DriverName := 'SQLite';
  FDConn.Params.Values['Database'] := FDbPath;
  FDConn.Params.Values['LockingMode'] := 'Normal';
  Conn := TFireDACConnection.Create(FDConn);
  Conn.Connect;
  Result := TDbContext.Create(Conn, TSQLiteDialect.Create);
  Result.Entities<TOwnershipWidget>;
end;

function TPersistUpdateOwnershipTests.NewWidget(const AId: Integer): TOwnershipWidget;
begin
  Result := TOwnershipWidget.Create;
  Result.ID := AId;
  Result.NAME := 'written';
end;

// Each scenario runs in its own routine so DbSet/query interfaces are
// finalised before the live count is taken by Leaked.

procedure TPersistUpdateOwnershipTests.RunUpdateMissingRow;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    Ctx.Entities<TOwnershipWidget>.Update(NewWidget(MISSING_ID));
    try
      Ctx.SaveChanges;
    except
      on E: EOptimisticConcurrencyException do ;
    end;
  finally
    Ctx.Free;
  end;
end;

procedure TPersistUpdateOwnershipTests.RunPersistUpdateMissingRow;
var
  Ctx: TDbContext;
  Raised: Boolean;
begin
  Raised := False;
  Ctx := NewContext;
  try
    try
      (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistUpdate(NewWidget(MISSING_ID));
    except
      on E: EOptimisticConcurrencyException do
        Raised := True;
    end;
  finally
    Ctx.Free;
  end;
  Should(Raised).BeTrue;
end;

procedure TPersistUpdateOwnershipTests.RunUpdateSecondInstance;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    Ctx.Entities<TOwnershipWidget>.Find(EXISTING_ID);
    Ctx.Entities<TOwnershipWidget>.Update(NewWidget(EXISTING_ID));
    Ctx.SaveChanges;
  finally
    Ctx.Free;
  end;
end;

procedure TPersistUpdateOwnershipTests.RunPersistUpdateSecondInstance;
var
  Ctx: TDbContext;
begin
  Ctx := NewContext;
  try
    Ctx.Entities<TOwnershipWidget>.Find(EXISTING_ID);
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistUpdate(NewWidget(EXISTING_ID));
  finally
    Ctx.Free;
  end;
end;

procedure TPersistUpdateOwnershipTests.RunPersistUpdateTrackedInstance;
var
  Ctx: TDbContext;
  Tracked: TOwnershipWidget;
begin
  Ctx := NewContext;
  try
    Tracked := Ctx.Entities<TOwnershipWidget>.Find(EXISTING_ID);
    Tracked.NAME := 'changed';
    (Ctx.Entities<TOwnershipWidget> as IDbSet).PersistUpdate(Tracked);
  finally
    Ctx.Free;
  end;
end;

function TPersistUpdateOwnershipTests.Leaked(const ACase: TProc): Integer;
var
  Before: Integer;
begin
  Before := GLiveWidgets;
  ACase();
  Result := GLiveWidgets - Before;
end;

procedure TPersistUpdateOwnershipTests.Update_MissingRow_DoesNotLeak;
begin
  Should(Leaked(RunUpdateMissingRow)).Be(0);
end;

procedure TPersistUpdateOwnershipTests.PersistUpdate_MissingRow_DoesNotLeak;
begin
  Should(Leaked(RunPersistUpdateMissingRow)).Be(0);
end;

procedure TPersistUpdateOwnershipTests.Update_SecondInstance_DoesNotLeak;
begin
  Should(Leaked(RunUpdateSecondInstance)).Be(0);
end;

procedure TPersistUpdateOwnershipTests.PersistUpdate_SecondInstance_DoesNotLeak;
begin
  Should(Leaked(RunPersistUpdateSecondInstance)).Be(0);
end;

procedure TPersistUpdateOwnershipTests.PersistUpdate_TrackedInstance_DoesNotLeakOrDoubleFree;
begin
  Should(Leaked(RunPersistUpdateTrackedInstance)).Be(0);
end;

end.
