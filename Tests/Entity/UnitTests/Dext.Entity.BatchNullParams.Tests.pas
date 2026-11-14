unit Dext.Entity.BatchNullParams.Tests;

// The MySQL/MariaDB batch UPDATE found this on MariaDB: a NULL value was bound
// without a data type ("Parameter [S0_4] data type is unknown"). The type has
// to come from the property when the value is NULL.

interface

uses
  System.Rtti,
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Entity.Core,
  Dext.Entity.Context,
  Dext.Entity.BatchStrategy,
  Dext.Entity.Setup,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Drivers.FireDAC,
  Dext.Entity.Attributes,
  Dext.Types.Nullable;

type
  [Table('batch_null_rows')]
  TBatchNullRow = class
  private
    FId: Integer;
    FName: string;
    FRegion: Nullable<Integer>;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Region: Nullable<Integer> read FRegion write FRegion;
  end;

  TBatchNullContext = class(TDbContext)
  end;

  [TestFixture('Batch UPDATE with NULL values')]
  TBatchNullParamsTests = class
  private
    FConn: TFDConnection;
    FContext: TBatchNullContext;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    [Description('A NULL column of the MySQL batch UPDATE is bound with the type of the property')]
    procedure MySql_Batch_Update_Binds_Null_With_The_Property_Type;
  end;

implementation

procedure TBatchNullParamsTests.Setup;
var
  Options: TDbContextOptions;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE batch_null_rows (id INTEGER PRIMARY KEY, name TEXT, region INTEGER)');
  FConn.ExecSQL('INSERT INTO batch_null_rows VALUES (1, ''a'', 7), (2, ''b'', 7), (3, ''c'', 7)');

  Options := TDbContextOptions.Create;
  try
    Options.UseSQLite(':memory:');
    Options.CustomConnection := TFireDACConnection.Create(FConn, False);
    FContext := TBatchNullContext.Create(Options);
  finally
    Options.Free;
  end;
end;

procedure TBatchNullParamsTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

procedure TBatchNullParamsTests.MySql_Batch_Update_Binds_Null_With_The_Property_Type;
var
  Ctx: TRttiContext;
  RType: TRttiType;
  SetProps, WhereProps: IList<TPair<TRttiProperty, string>>;
  Rows: TArray<TObject>;
  Row: TBatchNullRow;
  i: Integer;
begin
  Ctx := TRttiContext.Create;
  RType := Ctx.GetType(TBatchNullRow);
  SetProps := TCollections.CreateList<TPair<TRttiProperty, string>>;
  SetProps.Add(TPair<TRttiProperty, string>.Create(RType.GetProperty('Name'), 'name'));
  SetProps.Add(TPair<TRttiProperty, string>.Create(RType.GetProperty('Region'), 'region'));
  WhereProps := TCollections.CreateList<TPair<TRttiProperty, string>>;
  WhereProps.Add(TPair<TRttiProperty, string>.Create(RType.GetProperty('Id'), 'id'));

  SetLength(Rows, 3);
  try
    for i := 0 to 2 do
    begin
      Row := TBatchNullRow.Create;
      Row.Id := i + 1;
      Row.Name := 'renamed ' + IntToStr(i);
      Row.Region := Default(Nullable<Integer>);
      Rows[i] := Row;
    end;

    TDextMySqlBatchStrategy.ExecuteUpdateBatch(FContext, 'batch_null_rows',
      SetProps, WhereProps, Rows, 100);

    Should(Integer(FConn.ExecSQLScalar('SELECT COUNT(*) FROM batch_null_rows WHERE region IS NULL')))
      .Be(3);
    Should(Integer(FConn.ExecSQLScalar('SELECT COUNT(*) FROM batch_null_rows WHERE name LIKE ''renamed%''')))
      .Be(3);
  finally
    for i := 0 to High(Rows) do
      Rows[i].Free;
  end;
end;

end.
