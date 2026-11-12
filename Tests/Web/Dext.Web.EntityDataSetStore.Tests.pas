unit Dext.Web.EntityDataSetStore.Tests;

interface

uses
  System.SysUtils,
  System.Variants,
  System.DateUtils,
  Dext.Types.Nullable,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Collections,
  Dext.Json,
  Dext.Json.Types,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC,
  Dext.Web.EntityDataSetApi,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt;

type
  {$M+}
  [Table('eds_items')]
  TEdsItem = class
  private
    FCode: string;
    FName: string;
  public
    [PK, Column('code')]
    property Code: string read FCode write FCode;
    [Column('name')]
    property Name: string read FName write FName;
  end;
  {$M-}

  /// <summary>
  ///   TDbContextEntityDataSetStore.ApplyChanges against a real SQLite
  ///   database: eds_items.name is UNIQUE, and the row ('s1', 'seed') is there
  ///   before every test, so inserting the name 'seed' again makes an item fail.
  ///   The key is a string: the store passes every key and value as a string
  ///   (see the PR notes about non-string properties).
  /// </summary>
  [TestFixture('EntityDataSet store - ApplyChanges atomicity')]
  TEntityDataSetStoreTests = class
  private
    FConn: TFDConnection;
    FContext: TDbContext;
    function Apply(const AJson: string;
      AContinueOnError: Boolean = False): IList<TApplyItemResult>;
    function RowCount(const AName: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test('Should apply nothing when one item of the batch fails')]
    procedure TestFailingItemRollsBackTheWholeBatch;

    [Test('Should report every item of a failed batch as not applied')]
    procedure TestFailedBatchReportsEveryItem;

    [Test('Should leave nothing tracked after a failed batch')]
    procedure TestFailedBatchLeavesTheContextClean;

    [Test('Should apply inserts, updates and deletes together and return the new keys')]
    procedure TestSuccessfulBatchAppliesEverything;

    [Test('Should keep the other items when ContinueOnError is set')]
    procedure TestContinueOnErrorKeepsTheOtherItems;

    [Test('Should not retry a failed item on the next SaveChanges with ContinueOnError')]
    procedure TestContinueOnErrorDoesNotRetryTheFailedItem;

    [Test('Should serialize the list the GET endpoint returns as a JSON array')]
    procedure TestListIsServedAsJsonArray;

    [Test('Should serialize the apply results with success, message and keys')]
    procedure TestApplyResultsAreServedAsJson;
  end;

var
  /// Instances of TEdsTyped destroyed so far. The store builds its entities
  /// through the class reference, so only the destructor can be counted.
  GEdsTypedFreed: Integer = 0;

type
  {$M+}
  [Table('eds_typed')]
  TEdsTyped = class
  private
    FId: Integer;
    FQty: Int64;
    FPrice: Double;
    FAmount: Currency;
    FActive: Boolean;
    FDue: TDateTime;
    FRating: Nullable<Integer>;
  public
    destructor Destroy; override;
    [PK, AutoInc, Column('id')]
    property Id: Integer read FId write FId;
    [Column('qty')]
    property Qty: Int64 read FQty write FQty;
    [Column('price')]
    property Price: Double read FPrice write FPrice;
    [Column('amount')]
    property Amount: Currency read FAmount write FAmount;
    [Column('active')]
    property Active: Boolean read FActive write FActive;
    [Column('due')]
    property Due: TDateTime read FDue write FDue;
    [Column('rating')]
    property Rating: Nullable<Integer> read FRating write FRating;
  end;
  {$M-}

  /// <summary>
  ///   Non-string properties (#213): integer and auto-increment keys, Int64,
  ///   Double, Currency, Boolean, TDateTime and Nullable values, whether the
  ///   JSON carries them as strings or with their own JSON type. The row
  ///   (1, ...) is there before every test.
  /// </summary>
  [TestFixture('EntityDataSet store - non-string properties')]
  TEntityDataSetStoreTypesTests = class
  private
    FConn: TFDConnection;
    FContext: TDbContext;
    function Apply(const AJson: string): IList<TApplyItemResult>;
    function Scalar(const ASql: string): Variant;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test('Should insert typed values sent as JSON strings')]
    procedure TestInsertTypedValuesSentAsStrings;

    [Test('Should insert typed values sent with their JSON types')]
    procedure TestInsertTypedValuesSentAsJsonTypes;

    [Test('Should return the auto-increment key of an inserted row')]
    procedure TestInsertReturnsTheAutoIncKey;

    [Test('Should modify a row by its integer key')]
    procedure TestModifyByIntegerKey;

    [Test('Should modify a row by its integer key sent as a string')]
    procedure TestModifyByIntegerKeySentAsString;

    [Test('Should delete a row by its integer key')]
    procedure TestDeleteByIntegerKey;

    [Test('Should free the entity it builds for a deleted item')]
    procedure TestDeletedItemIsFreed;

    [Test('Should free the entity of a deleted item that failed')]
    procedure TestFailedDeletedItemIsFreed;

    [Test('Should delete the instance the context already tracks, not a twin')]
    procedure TestDeleteUsesTheTrackedInstance;

    [Test('Should modify a nullable column to a value')]
    procedure TestModifyNullableColumn;

    [Test('Should modify a column to its default value (0, false)')]
    procedure TestModifyToDefaultValue;

    [Test('Should store NULL when a nullable value is null')]
    procedure TestNullClearsANullableColumn;

    [Test('Should read the decimal point whatever the machine locale')]
    procedure TestDecimalPointIgnoresTheLocale;

    [Test('Should fail the item, naming the property, when a value cannot be converted')]
    procedure TestUnconvertibleValueFailsTheItem;
  end;

  {$M+}
  [Table('eds_required')]
  TEdsRequired = class
  private
    FCode: string;
    FName: string;
    FNote: string;
  public
    [PK, Column('code')]
    property Code: string read FCode write FCode;
    [Required, Column('name')]
    property Name: string read FName write FName;
    [Column('note')]
    property Note: string read FNote write FNote;
  end;
  {$M-}

  /// <summary>
  ///   A modified item changes only some columns. The entity SaveChanges
  ///   validates must still be complete: with a [Required] property that the
  ///   item does not carry, a bare stub would be rejected.
  /// </summary>
  [TestFixture('EntityDataSet store - partial update of a required entity')]
  TEntityDataSetStoreRequiredTests = class
  private
    FConn: TFDConnection;
    FContext: TDbContext;
    function Apply(const AJson: string): IList<TApplyItemResult>;
    function Scalar(const ASql: string): Variant;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test('Should update one column of an entity that has a required property')]
    procedure TestPartialUpdateKeepsTheRequiredColumn;

    [Test('Should still fail a modified item whose row does not exist')]
    procedure TestModifiedItemOfAMissingRowFails;

    [Test('Should still reject a value that breaks a rule of the stored entity')]
    procedure TestPartialUpdateIsStillValidated;
  end;

implementation

{ TEntityDataSetStoreTests }

procedure TEntityDataSetStoreTests.Setup;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE eds_items (code VARCHAR(20) PRIMARY KEY, ' +
    'name VARCHAR(50) NOT NULL UNIQUE)');
  FConn.ExecSQL('INSERT INTO eds_items (code, name) VALUES (''s1'', ''seed'')');

  FContext := TDbContext.Create(TFireDACConnection.Create(FConn, False),
    TSQLiteDialect.Create);
  // Registers the DbSet, as a typed context property would.
  FContext.Entities<TEdsItem>;
end;

procedure TEntityDataSetStoreTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

function TEntityDataSetStoreTests.Apply(const AJson: string;
  AContinueOnError: Boolean): IList<TApplyItemResult>;
var
  Store: IEntityDataSetStore;
  Changes: IDextJsonArray;
begin
  Store := TDbContextEntityDataSetStore.Create(AContinueOnError);
  Changes := (TDextJson.Provider.Parse(AJson) as IDextJsonObject).GetArray('changes');
  Result := Store.ApplyChanges(TEdsItem, Changes, FContext);
end;

function TEntityDataSetStoreTests.RowCount(const AName: string): Integer;
begin
  Result := FConn.ExecSQLScalar('SELECT COUNT(*) FROM eds_items WHERE name = :n',
    [AName]);
end;

procedure TEntityDataSetStoreTests.TestFailingItemRollsBackTheWholeBatch;
begin
  Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"b1","Name":"b"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}');

  Should(RowCount('a')).Be(0)
    .Because('item 2 failed, so item 0 must not be committed');
  Should(RowCount('b')).Be(0);
  Should(RowCount('seed')).Be(1);
end;

procedure TEntityDataSetStoreTests.TestListIsServedAsJsonArray;
var
  Json: string;
begin
  Json := TEncoding.UTF8.GetString(TEntityDataSetApi.ListToJson<TEdsItem>(
    FContext.Entities<TEdsItem>.ToList));

  Should(Json).StartWith('[');
  Should(Json).Contain('seed');
end;

procedure TEntityDataSetStoreTests.TestApplyResultsAreServedAsJson;
var
  Json: string;
begin
  Json := LowerCase(TEncoding.UTF8.GetString(TEntityDataSetApi.ResultsToJson(
    Apply('{"changes":[{"state":"inserted","values":{"Code":"n1",' +
      '"Name":"fresh"}},{"state":"deleted","key":{"Code":"zz"}}]}'))));

  Should(Json).StartWith('[');
  Should(Json).Contain('"success":false');
  Should(Json).Contain('batch not applied');
end;

procedure TEntityDataSetStoreTests.TestFailedBatchReportsEveryItem;
var
  Results: IList<TApplyItemResult>;
  I: Integer;
begin
  Results := Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}');

  Should(Results.Count).Be(2);
  for I := 0 to Results.Count - 1 do
  begin
    Should(Results[I].Success).BeFalse;
    Should(Results[I].ErrorMessage).NotBeEmpty;
  end;
end;

procedure TEntityDataSetStoreTests.TestFailedBatchLeavesTheContextClean;
begin
  Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}');

  Should(FContext.ChangeTracker.HasChanges).BeFalse
    .Because('a later SaveChanges on the same context must not retry the batch');
end;

procedure TEntityDataSetStoreTests.TestSuccessfulBatchAppliesEverything;
var
  Results: IList<TApplyItemResult>;
  NewKey: Variant;
begin
  FConn.ExecSQL('INSERT INTO eds_items (code, name) VALUES (''o1'', ''old'')');

  Results := Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"modified","key":{"Code":"s1"},"values":{"Name":"seed2"}},' +
    '{"state":"deleted","key":{"Code":"o1"}}]}');

  Should(Results.Count).Be(3);
  Should(Results[0].ErrorMessage).BeEmpty;
  Should(Results[1].ErrorMessage).BeEmpty;
  Should(Results[2].ErrorMessage).BeEmpty;
  Should(Results[0].Success).BeTrue;
  Should(Results[1].Success).BeTrue;
  Should(Results[2].Success).BeTrue;

  Should(RowCount('a')).Be(1);
  Should(RowCount('seed2')).Be(1);
  Should(RowCount('seed')).Be(0);
  Should(RowCount('old')).Be(0);

  Should(Results[0].Keys <> nil).BeTrue;
  Should(Results[0].Keys.TryGetValue('Code', NewKey)).BeTrue;
  Should(string(NewKey)).Be('a1');
end;

procedure TEntityDataSetStoreTests.TestContinueOnErrorKeepsTheOtherItems;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"a1","Name":"a"}},' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}},' +
    '{"state":"inserted","values":{"Code":"c1","Name":"c"}}]}', True);

  Should(Results[0].Success).BeTrue;
  Should(Results[1].Success).BeFalse;
  Should(Results[2].Success).BeTrue
    .Because('the failed item must not drag the next one down with it');
  Should(RowCount('a')).Be(1);
  Should(RowCount('c')).Be(1);
end;

procedure TEntityDataSetStoreTests.TestContinueOnErrorDoesNotRetryTheFailedItem;
begin
  Apply('{"changes":[' +
    '{"state":"inserted","values":{"Code":"x9","Name":"seed"}}]}', True);

  Should(FContext.ChangeTracker.HasChanges).BeFalse
    .Because('the failed entity must be detached, not left as Added');
end;

{ TEntityDataSetStoreTypesTests }

const
  // One millisecond, as a fraction of a day: dates go through the database.
  OneMs = 1 / MSecsPerDay;

procedure TEntityDataSetStoreTypesTests.Setup;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE eds_typed (id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'qty BIGINT, price DOUBLE, amount DECIMAL(18,4), active BOOLEAN, ' +
    'due DATETIME, rating INTEGER)');
  FConn.ExecSQL('INSERT INTO eds_typed (id, qty, price, amount, active, due, ' +
    'rating) VALUES (1, 1, 1.5, 1.25, 0, ''2026-01-01 08:00:00'', 3)');

  FContext := TDbContext.Create(TFireDACConnection.Create(FConn, False),
    TSQLiteDialect.Create);
  FContext.Entities<TEdsTyped>;
end;

procedure TEntityDataSetStoreTypesTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

function TEntityDataSetStoreTypesTests.Apply(
  const AJson: string): IList<TApplyItemResult>;
var
  Store: IEntityDataSetStore;
  Changes: IDextJsonArray;
begin
  Store := TDbContextEntityDataSetStore.Create;
  Changes := (TDextJson.Provider.Parse(AJson) as IDextJsonObject).GetArray('changes');
  Result := Store.ApplyChanges(TEdsTyped, Changes, FContext);
end;

function TEntityDataSetStoreTypesTests.Scalar(const ASql: string): Variant;
begin
  Result := FConn.ExecSQLScalar(ASql);
end;

procedure TEntityDataSetStoreTypesTests.TestInsertTypedValuesSentAsStrings;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"inserted","values":{' +
    '"Qty":"5000000000","Price":"3.5","Amount":"12.34","Active":"true",' +
    '"Due":"2026-10-02T10:30:00","Rating":"4"}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Int64(Scalar('SELECT qty FROM eds_typed WHERE id = 2'))).Be(5000000000);
  Should(Double(Scalar('SELECT price FROM eds_typed WHERE id = 2'))).Be(3.5);
  Should(Double(Scalar('SELECT amount FROM eds_typed WHERE id = 2')))
    .BeApproximately(12.34, 0.00001);
  Should(Boolean(Scalar('SELECT active FROM eds_typed WHERE id = 2'))).BeTrue;
  Should(Double(Scalar('SELECT due FROM eds_typed WHERE id = 2')))
    .BeApproximately(EncodeDateTime(2026, 10, 2, 10, 30, 0, 0), OneMs);
  Should(Integer(Scalar('SELECT rating FROM eds_typed WHERE id = 2'))).Be(4);
end;

procedure TEntityDataSetStoreTypesTests.TestInsertTypedValuesSentAsJsonTypes;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"inserted","values":{' +
    '"Qty":5000000000,"Price":3.5,"Amount":12.34,"Active":true,' +
    '"Due":"2026-10-02","Rating":4}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Int64(Scalar('SELECT qty FROM eds_typed WHERE id = 2'))).Be(5000000000);
  Should(Double(Scalar('SELECT price FROM eds_typed WHERE id = 2'))).Be(3.5);
  Should(Double(Scalar('SELECT amount FROM eds_typed WHERE id = 2')))
    .BeApproximately(12.34, 0.00001);
  Should(Boolean(Scalar('SELECT active FROM eds_typed WHERE id = 2'))).BeTrue;
  Should(Double(Scalar('SELECT due FROM eds_typed WHERE id = 2')))
    .BeApproximately(EncodeDate(2026, 10, 2), OneMs);
  Should(Integer(Scalar('SELECT rating FROM eds_typed WHERE id = 2'))).Be(4);
end;

procedure TEntityDataSetStoreTypesTests.TestInsertReturnsTheAutoIncKey;
var
  Results: IList<TApplyItemResult>;
  NewKey: Variant;
begin
  Results := Apply('{"changes":[{"state":"inserted","values":{' +
    '"Qty":"7","Price":"1","Amount":"1","Active":"false",' +
    '"Due":"2026-10-02"}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Results[0].Keys.TryGetValue('Id', NewKey)).BeTrue;
  Should(Integer(NewKey)).Be(2);
  Should(Int64(Scalar('SELECT qty FROM eds_typed WHERE id = 2'))).Be(7);
end;

procedure TEntityDataSetStoreTypesTests.TestModifyByIntegerKey;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Id":1},' +
    '"values":{"Price":7.25,"Due":"2026-12-31T23:59:00"}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Double(Scalar('SELECT price FROM eds_typed WHERE id = 1'))).Be(7.25);
  Should(Double(Scalar('SELECT due FROM eds_typed WHERE id = 1')))
    .BeApproximately(EncodeDateTime(2026, 12, 31, 23, 59, 0, 0), OneMs);
end;

procedure TEntityDataSetStoreTypesTests.TestModifyByIntegerKeySentAsString;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Id":"1"},' +
    '"values":{"Qty":"99"}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Int64(Scalar('SELECT qty FROM eds_typed WHERE id = 1'))).Be(99);
end;

destructor TEdsTyped.Destroy;
begin
  Inc(GEdsTypedFreed);
  inherited;
end;

procedure TEntityDataSetStoreTypesTests.TestDeletedItemIsFreed;
var
  Before: Integer;
  Results: IList<TApplyItemResult>;
begin
  Before := GEdsTypedFreed;
  Results := Apply('{"changes":[{"state":"deleted","key":{"Id":1}}]}');
  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);

  // The context owns what it tracks: with it gone, the entity the store
  // built for the item must be gone too.
  FreeAndNil(FContext);
  Should(GEdsTypedFreed - Before).Be(1);
end;

procedure TEntityDataSetStoreTypesTests.TestDeleteUsesTheTrackedInstance;
var
  Loaded: TObject;
  Results: IList<TApplyItemResult>;
begin
  // The context has already read the row (a GET and an apply on one
  // context). Deleting through a second, key-only instance would free the
  // loaded one from the identity map while the tracker still points at it.
  Loaded := FContext.Entities<TEdsTyped>.ToList[0];

  Results := Apply('{"changes":[{"state":"deleted","key":{"Id":1}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Ord(FContext.ChangeTracker.GetState(Loaded))).Be(Ord(esDetached));
end;

procedure TEntityDataSetStoreTypesTests.TestFailedDeletedItemIsFreed;
var
  Before: Integer;
  Results: IList<TApplyItemResult>;
begin
  Before := GEdsTypedFreed;
  // No row has the key 999: the DELETE affects nothing and the item fails.
  Results := Apply('{"changes":[{"state":"deleted","key":{"Id":999}}]}');
  Should(Results[0].Success).BeFalse;

  FreeAndNil(FContext);
  Should(GEdsTypedFreed - Before).Be(1);
end;

procedure TEntityDataSetStoreTypesTests.TestDeleteByIntegerKey;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"deleted","key":{"Id":1}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Integer(Scalar('SELECT COUNT(*) FROM eds_typed'))).Be(0);
end;

procedure TEntityDataSetStoreTypesTests.TestModifyNullableColumn;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Id":1},' +
    '"values":{"Rating":5}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Integer(Scalar('SELECT rating FROM eds_typed WHERE id = 1'))).Be(5);
end;

procedure TEntityDataSetStoreTypesTests.TestModifyToDefaultValue;
var
  Results: IList<TApplyItemResult>;
begin
  // The stored row has qty = 1 and price = 1.5. The store builds a fresh
  // entity, whose values are the defaults, so a modification TO the default
  // looks like no change unless the explicit IsModified is honoured.
  Results := Apply('{"changes":[{"state":"modified","key":{"Id":1},' +
    '"values":{"Qty":0,"Price":0}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Int64(Scalar('SELECT qty FROM eds_typed WHERE id = 1'))).Be(0);
  Should(Double(Scalar('SELECT price FROM eds_typed WHERE id = 1'))).Be(0);
end;

procedure TEntityDataSetStoreTypesTests.TestNullClearsANullableColumn;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Id":1},' +
    '"values":{"Rating":null}}]}');

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Scalar('SELECT rating FROM eds_typed WHERE id = 1')).BeNull;
end;

procedure TEntityDataSetStoreTypesTests.TestDecimalPointIgnoresTheLocale;
var
  Results: IList<TApplyItemResult>;
  OldDecimal, OldThousand: Char;
begin
  // A machine whose decimal separator is the comma: JSON still uses the dot.
  OldDecimal := FormatSettings.DecimalSeparator;
  OldThousand := FormatSettings.ThousandSeparator;
  FormatSettings.DecimalSeparator := ',';
  FormatSettings.ThousandSeparator := '.';
  try
    Results := Apply('{"changes":[{"state":"modified","key":{"Id":1},' +
      '"values":{"Price":"3.5","Amount":"1234.5"}}]}');
  finally
    FormatSettings.DecimalSeparator := OldDecimal;
    FormatSettings.ThousandSeparator := OldThousand;
  end;

  Should(Results[0].Success).BeTrue.Because(Results[0].ErrorMessage);
  Should(Double(Scalar('SELECT price FROM eds_typed WHERE id = 1'))).Be(3.5);
  Should(Double(Scalar('SELECT amount FROM eds_typed WHERE id = 1')))
    .BeApproximately(1234.5, 0.00001);
end;

procedure TEntityDataSetStoreTypesTests.TestUnconvertibleValueFailsTheItem;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Id":1},' +
    '"values":{"Qty":"abc"}}]}');

  Should(Results[0].Success).BeFalse
    .Because('"abc" is not a number: it must not be written as 0');
  Should(Results[0].ErrorMessage).Contain('Qty');
  Should(Int64(Scalar('SELECT qty FROM eds_typed WHERE id = 1'))).Be(1);
end;

{ TEntityDataSetStoreRequiredTests }

procedure TEntityDataSetStoreRequiredTests.Setup;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE eds_required (code VARCHAR(20) PRIMARY KEY, ' +
    'name VARCHAR(50) NOT NULL, note VARCHAR(50))');
  FConn.ExecSQL('INSERT INTO eds_required (code, name, note) ' +
    'VALUES (''r1'', ''Seed'', ''first'')');

  FContext := TDbContext.Create(TFireDACConnection.Create(FConn, False),
    TSQLiteDialect.Create);
  FContext.Entities<TEdsRequired>;
end;

procedure TEntityDataSetStoreRequiredTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

function TEntityDataSetStoreRequiredTests.Apply(
  const AJson: string): IList<TApplyItemResult>;
var
  Store: IEntityDataSetStore;
  Changes: IDextJsonArray;
begin
  Store := TDbContextEntityDataSetStore.Create;
  Changes := (TDextJson.Provider.Parse(AJson) as IDextJsonObject).GetArray('changes');
  Result := Store.ApplyChanges(TEdsRequired, Changes, FContext);
end;

function TEntityDataSetStoreRequiredTests.Scalar(const ASql: string): Variant;
begin
  Result := FConn.ExecSQLScalar(ASql);
end;

procedure TEntityDataSetStoreRequiredTests.TestPartialUpdateKeepsTheRequiredColumn;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Code":"r1"},' +
    '"values":{"Note":"changed"}}]}');

  Should(Results[0].ErrorMessage).BeEmpty;
  Should(Results[0].Success).BeTrue;
  Should(string(Scalar('SELECT note FROM eds_required'))).Be('changed');
  Should(string(Scalar('SELECT name FROM eds_required'))).Be('Seed');
end;

procedure TEntityDataSetStoreRequiredTests.TestModifiedItemOfAMissingRowFails;
var
  Results: IList<TApplyItemResult>;
begin
  Results := Apply('{"changes":[{"state":"modified","key":{"Code":"nope"},' +
    '"values":{"Note":"x"}}]}');

  Should(Results[0].Success).BeFalse;
  Should(Integer(Scalar('SELECT COUNT(*) FROM eds_required'))).Be(1);
end;

procedure TEntityDataSetStoreRequiredTests.TestPartialUpdateIsStillValidated;
var
  Results: IList<TApplyItemResult>;
begin
  // Blanking a required column is still refused.
  Results := Apply('{"changes":[{"state":"modified","key":{"Code":"r1"},' +
    '"values":{"Name":""}}]}');

  Should(Results[0].Success).BeFalse;
  Should(string(Scalar('SELECT name FROM eds_required'))).Be('Seed');
end;

end.
