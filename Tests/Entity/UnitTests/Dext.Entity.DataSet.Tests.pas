unit Dext.Entity.DataSet.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Entity.DataSet,
  Dext.Specifications.Parser,
  Dext.Core.SmartTypes,
  Dext.Types.Nullable,
  Dext.Types.Lazy,
  Dext.Entity.Attributes,
  Dext.Entity,
  Dext.Collections,
  Dext.DI.Attributes,
  Dext.Core.Activator;

type
  // =========================================================================
  //  Simple entity for basic tests
  // =========================================================================
  [Table('users')]
  TUserTest = class
  private
    FId: Integer;
    FName: string;
    FScore: Double;
    FActive: Boolean;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
    property Score: Double read FScore write FScore;
    property Active: Boolean read FActive write FActive;
  end;

  // =========================================================================
  //  Complex entity for variety of types and Blobs
  // =========================================================================
  [Table('products')]
  TProductTest = class
  private
    FId: Integer;
    FName: string;
    FDescription: string;
    FPrice: Currency;
    FWeight: Double;
    FStockQty: Int64;
    FActive: Boolean;
    FCreatedAt: TDateTime;
    FPhoto: TBytes;
  public
    [PrimaryKey, AutoInc]
    property Id: Integer read FId write FId;

    [Required, MaxLength(100)]
    property Name: string read FName write FName;

    [MaxLength(500)]
    property Description: string read FDescription write FDescription;

    [Required]
    property Price: Currency read FPrice write FPrice;

    property Weight: Double read FWeight write FWeight;
    property StockQty: Int64 read FStockQty write FStockQty;
    property Active: Boolean read FActive write FActive;
    property CreatedAt: TDateTime read FCreatedAt write FCreatedAt;
    property Photo: TBytes read FPhoto write FPhoto;
  end;

  // =========================================================================
  //  Detail entity for master-detail tests
  // =========================================================================
  [Table('order_items')]
  TOrderItemTest = class
  private
    FId: Integer;
    FOrderId: Integer;
    FProductName: string;
    FQuantity: Integer;
    FUnitPrice: Currency;
  public
    [PrimaryKey, AutoInc]
    property Id: Integer read FId write FId;

    [Required]
    property OrderId: Integer read FOrderId write FOrderId;

    [Required, MaxLength(100)]
    property ProductName: string read FProductName write FProductName;

    [Required]
    property Quantity: Integer read FQuantity write FQuantity;

    [Required]
    property UnitPrice: Currency read FUnitPrice write FUnitPrice;
  end;

  // =========================================================================
  //  Entity with Smart Properties for mapping tests
  // =========================================================================
  TTestSmartEntity = class
  private
    FId: Integer;
    FLazyDescription: Lazy<string>;
    FPropPrice: Prop<Double>;
    FNullableAge: Nullable<Integer>;
  public
    [PrimaryKey, AutoInc]
    property Id: Integer read FId write FId;
    property Description: Lazy<string> read FLazyDescription write FLazyDescription;
    property Price: Prop<Double> read FPropPrice write FPropPrice;
    property Age: Nullable<Integer> read FNullableAge write FNullableAge;
  end;

  // =========================================================================
  //  Order Entity for native master-detail tests
  // =========================================================================
  [Table('orders_native')]
  TOrderTest = class
  private
    FId: Integer;
    FItems: IList<TOrderItemTest>;
  public
    constructor Create;
    destructor Destroy; override;
    [PrimaryKey] property Id: Integer read FId write FId;
    [HasMany] property Items: IList<TOrderItemTest> read FItems write FItems;
  end;

  [TestFixture('TEntityDataSet Automation and Stability')]
  TEntityDataSetAutomationTests = class
  private
    FMasterDS: TEntityDataSet;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_AutoInstantiate_Collection_Via_Attribute;
    [Test]
    procedure Test_MasterDetail_ID_Sync_Nested;
    [Test]
    procedure Test_TActivator_Tip_Error_Message;
  end;

  TGhostEntity = class
    Id: Integer;
  end;

  // Classe sem registro para testar falha do Activator
  TUnregisteredEntity = class
  private
    FItems: IList<TGhostEntity>; // IList nao registrada no TActivator para o tipo TGhostEntity
  public
    [HasMany] property Items: IList<TGhostEntity> read FItems write FItems;
  end;

  [TestFixture('TEntityDataSet Smart Properties')]
  TSmartPropertyDataSetTests = class
  private
    FDataSet: TEntityDataSet;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Smart_Fields_Naming_And_Types;
  end;

  // =========================================================================
  //  SmartTypes Entity
  // =========================================================================
  TSmartProduct = class
  private
    FID: IntType;
    FName: StringType;
    FPrice: Prop<Double>;
    FQuantity: Nullable<Integer>;
    FActive: BoolType;
    FDescription: Lazy<string>;
  public
    property ID: IntType read FID write FID;
    property Name: StringType read FName write FName;
    property Price: Prop<Double> read FPrice write FPrice;
    property Quantity: Nullable<Integer> read FQuantity write FQuantity;
    property Active: BoolType read FActive write FActive;
    property Description: Lazy<string> read FDescription write FDescription;
  end;

  // =========================================================================
  //  Shadow Property Entity
  // =========================================================================
  TShadowUser = class
  private
    FId: Integer;
    FName: string;
  public
    [PrimaryKey]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  TShadowTestContext = class(TDbContext)
  protected
    procedure OnModelCreating(Builder: TModelBuilder); override;
  end;

  // =========================================================================
  //  Floating Point and Currency tests
  // =========================================================================

  [Table('floating_point')]
  TFloatingPointTest = class
  private
    FId: Integer;
    FDoubleVal: Double;
    FCurrencyVal: Currency;
  public
    [PrimaryKey] property Id: Integer read FId write FId;
    property DoubleVal: Double read FDoubleVal write FDoubleVal;
    property CurrencyVal: Currency read FCurrencyVal write FCurrencyVal;
  end;

  [TestFixture('TEntityDataSet Floating Point and Currency')]
  TFloatingPointDataSetTests = class
  private
    FDataSet: TEntityDataSet;
    FObj: TFloatingPointTest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Double_Value;
    [Test]
    procedure Test_Currency_Value;
    [Test]
    procedure Test_Format_And_Precision;
  end;

  // =========================================================================
  //  Fixtures
  // =========================================================================

  [TestFixture('TEntityDataSet Basic Loading and Navigation')]
  TEntityDataSetTests = class
  private
    FDataSet: TEntityDataSet;
    FUsers: TArray<TObject>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_LoadArray_Count;
    [Test]
    procedure Test_FieldValues;
    [Test]
    procedure Test_Navigation_Next_Prior;
    [Test]
    procedure Test_Filter_Expression;
    [Test]
    procedure Test_Locate_Success;
    [Test]
    procedure Test_GenericArrayLoad;
    [Test]
    procedure Test_GenericIListLoad;
    [Test]
    procedure Test_ExportToJson;
    [Test]
    procedure Test_LoadFromJson;
    [Test]
    procedure Test_Filter_And_Or_Parentheses;
    [Test]
    procedure Test_Filter_Not;
    [Test]
    procedure Test_Filter_Like_In_And_Null;
    [Test]
    procedure Test_Filter_Quoted_Text_With_Spaces_And_Quote;
    [Test]
    procedure Test_Filter_Invalid_Text_Raises;
    [Test]
    procedure Test_Filter_Always_False_Shows_No_Row;
  end;

  [TestFixture('TEntityDataSet Complex Types and Blobs')]
  TProductDataSetTests = class
  private
    FDataSet: TEntityDataSet;
    FProducts: TArray<TObject>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_FieldCount;
    [Test]
    procedure Test_Field_MaxLength;
    [Test]
    procedure Test_Field_Required;
    [Test]
    procedure Test_Field_DataTypes;
    [Test]
    procedure Test_DateTime_Persistence;
    [Test]
    procedure Test_Blob_FieldType;
    [Test]
    procedure Test_Blob_IsNull_When_Empty;
    [Test]
    procedure Test_Blob_Read_Stream;
    [Test]
    procedure Test_Blob_Write_Stream;
    [Test]
    procedure Test_Memo_Read_Stream;
    [Test]
    procedure Test_Memo_Write_Stream;
    [Test]
    procedure Test_Sort_By_Name;
    [Test]
    procedure Test_Sort_By_Price;
    [Test]
    procedure Test_Filter_By_Price;
  end;

  [TestFixture('TEntityDataSet Master-Detail')]
  TMasterDetailDataSetTests = class
  private
    FMasterDS: TEntityDataSet;
    FDetailDS: TEntityDataSet;
    FOrders: TArray<TObject>;
    FItems: TArray<TObject>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Detail_FieldValues;

    [Test]
    procedure Test_Detail_Count;

    [Test]
    procedure Test_Detail_FilterByMaster;

    [Test]
    procedure Test_Real_MasterDetail_Link;
  end;

  [TestFixture('TEntityDataSet Native Master-Detail')]
  TNativeMasterDetailTests = class
  private
    FDataSet: TEntityDataSet;
    FOrder: TOrderTest;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Access_Detail_DataSet;
    [Test]
    procedure Test_Detail_RecordCount;
  end;

  [TestFixture('TEntityDataSet CRUD Operations')]
  TEntityDataSetCRUDTests = class
  private
    FDataSet: TEntityDataSet;
    FSourceList: IList<TObject>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Append_And_Post;
    [Test]
    procedure Test_Edit_Existing;
    [Test]
    procedure Test_Delete_And_Sync;
    [Test]
    procedure Test_Insert_Between_Records;
    [Test]
    procedure Test_Refresh_Syncs_External_Changes;
    [Test]
    procedure Test_Cancel_Edit_Restores_Value;
    [Test]
    procedure Test_Cancel_Edit_Keeps_Earlier_Posted_Edit;
    [Test]
    procedure Test_Cancel_Edit_Does_Not_Leak_Dirty_Fields;
    [Test]
    procedure Test_Append_Goes_To_The_End;
    [Test]
    procedure Test_Insert_Goes_Before_The_Current_Row;
    [Test]
    procedure Test_ReadOnly_Blocks_Edit_Append_And_Delete;
  end;

  [TestFixture('TEntityDataSet Stress and Filtering')]
  TEntityDataSetStressTests = class
  private
    FDataSet: TEntityDataSet;
    FUsers: IList<TObject>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Stress_1k_Records_Filter;
    [Test]
    procedure Test_Edit_Into_Filter_Hides_Record;
  end;

  [TestFixture('TEntityDataSet SmartTypes Support')]
  TDataSetSmartTypesTests = class
  public
    [Test]
    procedure Test_Read_SmartTypes;
    [Test]
    procedure Test_Read_Nullable_Empty;
    [Test]
    procedure Test_Read_Lazy_Value;
  end;

  [TestFixture('TEntityDataSet Shadow Properties')]
  TShadowDataSetTests = class
  private
    FContext: TShadowTestContext;
    FDataSet: TEntityDataSet;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_ShadowProperty_Read_From_Context;
    [Test]
    procedure Test_ShadowProperty_Write_Updates_Context;
  end;

  [TestFixture('TEntityDataSet Calculated Fields')]
  TCalculatedFieldsTests = class
  private
    FDataSet: TEntityDataSet;
    procedure OnCalcFields(DataSet: TDataSet);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_Calculated_Field;
    [Test]
    procedure Test_Internal_Calculated_Field;
  end;

implementation

{ TEntityDataSetTests }

procedure TEntityDataSetTests.Setup;
var
  U1, U2: TUserTest;
begin
  SetLength(FUsers, 2);
  U1 := TUserTest.Create; U1.Id := 1; U1.Name := 'Cesar'; U1.Score := 100; U1.Active := True;
  U2 := TUserTest.Create; U2.Id := 2; U2.Name := 'Romero'; U2.Score := 200; U2.Active := False;
  FUsers[0] := U1; FUsers[1] := U2;

  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.Load(FUsers, TUserTest);
end;

procedure TEntityDataSetTests.TearDown;
var
  U: TObject;
begin
  FDataSet.Free;
  for U in FUsers do U.Free;
end;

procedure TEntityDataSetTests.Test_Filter_And_Or_Parentheses;
begin
  FDataSet.Filtered := True;
  // Cesar: Score 100, active. Romero: Score 200, not active.
  FDataSet.Filter := 'Score > 50 AND Active = True';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Cesar');

  FDataSet.Filter := 'Name = ''Cesar'' OR Name = ''Romero''';
  Should(FDataSet.RecordCount).Be(2);

  FDataSet.Filter := '(Score > 50 AND Active = False) OR Name = ''Cesar''';
  Should(FDataSet.RecordCount).Be(2);

  FDataSet.Filter := 'Score > 50 AND (Active = False OR Name = ''X'')';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Romero');
end;

procedure TEntityDataSetTests.Test_Filter_Not;
begin
  FDataSet.Filtered := True;
  FDataSet.Filter := 'NOT (Score > 150)';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Cesar');
end;

procedure TEntityDataSetTests.Test_Filter_Like_In_And_Null;
begin
  FDataSet.Filtered := True;
  FDataSet.Filter := 'Name LIKE ''Ces%''';
  Should(FDataSet.RecordCount).Be(1);

  FDataSet.Filter := 'Name NOT LIKE ''Ces%''';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Romero');

  FDataSet.Filter := 'Score IN (100, 300)';
  Should(FDataSet.RecordCount).Be(1);

  FDataSet.Filter := 'Name IN (''Romero'', ''Nobody'')';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Romero');

  FDataSet.Filter := 'Name NOT IN (''Romero'')';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Cesar');
end;

procedure TEntityDataSetTests.Test_Filter_Quoted_Text_With_Spaces_And_Quote;
begin
  // A value with a space and a quote, written the way the filter reads it.
  FDataSet.First;
  FDataSet.Next;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Ana O''Neil';
  FDataSet.Post;
  FDataSet.Filtered := True;
  FDataSet.Filter := 'Name = ''Ana O''''Neil''';
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Id').AsInteger).Be(2);
end;

procedure TEntityDataSetTests.Test_Filter_Invalid_Text_Raises;
begin
  FDataSet.Filtered := True;
  // An unreadable filter must not quietly show every row.
  Should(
    procedure
    begin
      FDataSet.Filter := 'Score >';
    end).Throw<EFilterSyntaxError>;
  Should(
    procedure
    begin
      FDataSet.Filter := 'Score > 1 AND';
    end).Throw<EFilterSyntaxError>;
  Should(
    procedure
    begin
      FDataSet.Filter := 'Name = ''abc';
    end).Throw<EFilterSyntaxError>;
end;

procedure TEntityDataSetTests.Test_Filter_Always_False_Shows_No_Row;
begin
  // The master-detail link uses "1=0" for "no master row": it must show
  // nothing, not every row.
  FDataSet.Filtered := True;
  FDataSet.Filter := '1=0';
  Should(FDataSet.RecordCount).Be(0);
  FDataSet.Filter := '1 = 1';
  Should(FDataSet.RecordCount).Be(2);
end;

procedure TEntityDataSetTests.Test_LoadArray_Count;
begin
  Should(FDataSet.RecordCount).Be(2);
end;

procedure TEntityDataSetTests.Test_FieldValues;
begin
  Should(FDataSet.FieldByName('Name').AsString).Be('Cesar');
  Should(FDataSet.FieldByName('Score').AsFloat).Be(100.0);
end;

procedure TEntityDataSetTests.Test_Navigation_Next_Prior;
begin
  FDataSet.Next;
  Should(FDataSet.FieldByName('Name').AsString).Be('Romero');
  FDataSet.Prior;
  Should(FDataSet.FieldByName('Name').AsString).Be('Cesar');
end;

procedure TEntityDataSetTests.Test_Filter_Expression;
begin
  FDataSet.Filter := 'Score > 150';
  FDataSet.Filtered := True;
  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('Name').AsString).Be('Romero');
end;

procedure TEntityDataSetTests.Test_Locate_Success;
begin
  Should(FDataSet.Locate('Name', 'Romero', [])).BeTrue;
  Should(FDataSet.FieldByName('Id').AsInteger).Be(2);
end;

procedure TEntityDataSetTests.Test_GenericArrayLoad;
var
  TypedDS: TEntityDataSet;
  TypedArray: TArray<TUserTest>;
begin
  SetLength(TypedArray, 1);
  TypedArray[0] := TUserTest.Create;
  TypedArray[0].Name := 'Alex';
  
  TypedDS := TEntityDataSet.Create(nil);
  try
    TypedDS.Load<TUserTest>(TypedArray);
    Should(TypedDS.RecordCount).Be(1);
    Should(TypedDS.FieldByName('Name').AsString).Be('Alex');
  finally
    TypedDS.Free;
    TypedArray[0].Free;
  end;
end;

procedure TEntityDataSetTests.Test_GenericIListLoad;
var
  TypedDS: TEntityDataSet;
  TypedList: IList<TUserTest>;
  U: TUserTest;
begin
  TypedList := TCollections.CreateList<TUserTest>(False);
  U := TUserTest.Create;
  U.Name := 'Alex List';
  TypedList.Add(U);
  
  TypedDS := TEntityDataSet.Create(nil);
  try
    TypedDS.Load<TUserTest>(TypedList, True);
    Should(TypedDS.RecordCount).Be(1);
    Should(TypedDS.FieldByName('Name').AsString).Be('Alex List');
  finally
    TypedDS.Free;
  end;
end;

procedure TEntityDataSetTests.Test_ExportToJson;
var
  Json, ObjJson: string;
begin
  Json := FDataSet.AsJsonArray;
  Should(Json.Contains('Cesar')).BeTrue;
  Should(Json.Contains('Romero')).BeTrue;
  
  FDataSet.First;
  ObjJson := FDataSet.AsJsonObject;
  Should(ObjJson.Contains('Cesar')).BeTrue;
  Should(ObjJson.Contains('Romero')).BeFalse;
end;

procedure TEntityDataSetTests.Test_LoadFromJson;
var
  Json: string;
  TypedDS: TEntityDataSet;
begin
  Json := '[{"Id":1,"Name":"JSON 1","Active":true},{"Id":2,"Name":"JSON 2","Active":false}]';
  TypedDS := TEntityDataSet.Create(nil);
  try
    TypedDS.LoadFromJson<TUserTest>(Json);
    Should(TypedDS.RecordCount).Be(2);
    TypedDS.First;
    Should(TypedDS.FieldByName('Name').AsString).Be('JSON 1');
    TypedDS.Next;
    Should(TypedDS.FieldByName('Name').AsString).Be('JSON 2');
  finally
    TypedDS.Free;
  end;
end;

{ TProductDataSetTests }

procedure TProductDataSetTests.Setup;
var
  P1, P2, P3: TProductTest;
begin
  SetLength(FProducts, 3);
  P1 := TProductTest.Create;
  P1.Id := 1; P1.Name := 'Widget Alpha'; P1.Price := 29.90; P1.Active := True;
  P1.Description := 'Premium widget for daily use';
  P1.Photo := [$FF, $D8, $FF, $E0];
  FProducts[0] := P1;

  P2 := TProductTest.Create;
  P2.Id := 2; P2.Name := 'Gadget Beta'; P2.Price := 149.99; P2.Active := True;
  FProducts[1] := P2;

  P3 := TProductTest.Create;
  P3.Id := 3; P3.Name := 'Tool Gamma'; P3.Price := 9.50; P3.Active := False;
  P3.CreatedAt := Now;
  FProducts[2] := P3;

  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.Load(FProducts, TProductTest);
end;

procedure TProductDataSetTests.TearDown;
var
  P: TObject;
begin
  FDataSet.Free;
  for P in FProducts do P.Free;
end;

procedure TProductDataSetTests.Test_FieldCount;
begin
  Should(FDataSet.FieldCount).Be(9);
end;

procedure TProductDataSetTests.Test_Field_MaxLength;
begin
  Should(FDataSet.FieldByName('Name').Size).Be(100);
  Should(FDataSet.FieldByName('Description').Size).Be(500);
end;

procedure TProductDataSetTests.Test_Field_Required;
begin
  Should(FDataSet.FieldByName('Name').Required).BeTrue;
  Should(FDataSet.FieldByName('Price').Required).BeTrue;
  Should(FDataSet.FieldByName('Description').Required).BeFalse;
end;

procedure TProductDataSetTests.Test_Field_DataTypes;
begin
  Should(FDataSet.FieldByName('Price').DataType).Be(ftCurrency);
  Should(FDataSet.FieldByName('StockQty').DataType).Be(ftLargeint);
  Should(FDataSet.FieldByName('Photo').DataType).Be(ftBlob);
  Should(FDataSet.FieldByName('CreatedAt').DataType).Be(ftDateTime);
end;

procedure TProductDataSetTests.Test_DateTime_Persistence;
var
  OriginalDate, DataSetDate: TDateTime;
begin
  FDataSet.Last; // Go to P3
  OriginalDate := TProductTest(FProducts[2]).CreatedAt;
  DataSetDate := FDataSet.FieldByName('CreatedAt').AsDateTime;
  
  // We compare formatted strings down to seconds cross-checked with raw double 
  // to ensure our MSecs conversion doesn't lose data.
  Should(FormatDateTime('yyyy-mm-dd hh:nn:ss', DataSetDate)).Be(FormatDateTime('yyyy-mm-dd hh:nn:ss', OriginalDate));
  Should(Abs(DataSetDate - OriginalDate) < 0.00000001).BeTrue;
end;

procedure TProductDataSetTests.Test_Blob_FieldType;
begin
  Should(FDataSet.FieldByName('Photo') is TBlobField).BeTrue;
end;

procedure TProductDataSetTests.Test_Blob_IsNull_When_Empty;
begin
  FDataSet.Next; // P2 (nil photo)
  Should(FDataSet.FieldByName('Photo').IsNull).BeTrue;
end;

procedure TProductDataSetTests.Test_Blob_Read_Stream;
var Stream: TStream;
begin
  FDataSet.First;
  Stream := FDataSet.CreateBlobStream(FDataSet.FieldByName('Photo'), bmRead);
  try
    Should(Stream.Size).Be(4);
  finally
    Stream.Free;
  end;
end;

procedure TProductDataSetTests.Test_Blob_Write_Stream;
var 
  Stream: TStream;
  NewData: TBytes;
begin
  FDataSet.First;
  FDataSet.Edit;
  Stream := FDataSet.CreateBlobStream(FDataSet.FieldByName('Photo'), bmWrite);
  try
    NewData := [$01, $02, $03];
    Stream.Write(NewData[0], 3);
  finally
    Stream.Free;
  end;
  FDataSet.Post;
  Should(Length(TProductTest(FProducts[0]).Photo)).Be(3);
end;

procedure TProductDataSetTests.Test_Memo_Read_Stream;
var
  Stream: TStream;
  Reader: TStreamReader;
begin
  FDataSet.First;
  Stream := FDataSet.CreateBlobStream(FDataSet.FieldByName('Description'), bmRead);
  try
    Reader := TStreamReader.Create(Stream, TEncoding.Unicode);
    try
      Should(Reader.ReadToEnd).Be('Premium widget for daily use');
    finally
      Reader.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TProductDataSetTests.Test_Memo_Write_Stream;
var
  Stream: TStream;
  Writer: TStreamWriter;
begin
  FDataSet.First;
  FDataSet.Edit;
  Stream := FDataSet.CreateBlobStream(FDataSet.FieldByName('Description'), bmWrite);
  try
    Writer := TStreamWriter.Create(Stream, TEncoding.Unicode);
    try
      Writer.Write('Novo Texto');
    finally
      Writer.Free;
    end;
  finally
    Stream.Free;
  end;
  FDataSet.Post;
  Should(TProductTest(FProducts[0]).Description).Be('Novo Texto');
end;

procedure TProductDataSetTests.Test_Sort_By_Name;
begin
  FDataSet.IndexFieldNames := 'Name';
  FDataSet.First;
  Should(FDataSet.FieldByName('Name').AsString).Be('Gadget Beta');
end;

procedure TProductDataSetTests.Test_Sort_By_Price;
begin
  FDataSet.IndexFieldNames := 'Price';
  FDataSet.First;
  Should(FDataSet.FieldByName('Name').AsString).Be('Tool Gamma');
end;

procedure TProductDataSetTests.Test_Filter_By_Price;
begin
  FDataSet.Filter := 'Price > 20';
  FDataSet.Filtered := True;
  Should(FDataSet.RecordCount).Be(2);
end;

{ TCalculatedFieldsTests }

procedure TCalculatedFieldsTests.Setup;
var
  U: TUserTest;
  Lst: IList<TUserTest>;
  Fld: TFloatField;
begin
  FDataSet := TEntityDataSet.Create(nil);
  U := TUserTest.Create;
  U.Id := 10;
  U.Score := 20;
  Lst := TCollections.CreateList<TUserTest>(True);
  Lst.Add(U);
  FDataSet.Load(Lst as IObjectList, TUserTest, True);
  FDataSet.Close;
  
  // Add calculated field manually
  Fld := TFloatField.Create(FDataSet);
  Fld.FieldName := 'CalculatedScore';
  Fld.FieldKind := fkCalculated;
  Fld.DataSet := FDataSet;

  FDataSet.OnCalcFields := Self.OnCalcFields;
  FDataSet.Open;
end;

procedure TCalculatedFieldsTests.TearDown;
begin
  FDataSet.Free;
end;

procedure TCalculatedFieldsTests.OnCalcFields(DataSet: TDataSet);
begin
  DataSet.FieldByName('CalculatedScore').AsFloat := DataSet.FieldByName('Score').AsFloat * 2;
end;

procedure TCalculatedFieldsTests.Test_Calculated_Field;
begin
  Should(FDataSet.FieldByName('CalculatedScore').AsFloat).Be(40);
end;

procedure TCalculatedFieldsTests.Test_Internal_Calculated_Field;
var
  Fld: TFloatField;
begin
  FDataSet.Close;
  
  // Add internal calc field manually
  Fld := TFloatField.Create(FDataSet);
  Fld.FieldName := 'InternalCalc';
  Fld.FieldKind := fkInternalCalc;
  Fld.DataSet := FDataSet;
  
  FDataSet.Open;
  
  // Set value manually (simulating internal calc logic or event)
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('InternalCalc').AsFloat := 55;
  FDataSet.Post;
  
  Should(FDataSet.FieldByName('InternalCalc').AsFloat).Be(55);
end;

{ TMasterDetailDataSetTests }

procedure TMasterDetailDataSetTests.Setup;
var
  O1, O2: TUserTest;
  I1, I2, I3: TOrderItemTest;
begin
  FMasterDS := TEntityDataSet.Create(nil);
  FDetailDS := TEntityDataSet.Create(nil);

  SetLength(FOrders, 2);
  O1 := TUserTest.Create; O1.Id := 100; O1.Name := 'O1'; FOrders[0] := O1;
  O2 := TUserTest.Create; O2.Id := 200; O2.Name := 'O2'; FOrders[1] := O2;

  SetLength(FItems, 3);
  I1 := TOrderItemTest.Create; I1.Id := 1; I1.OrderId := 100; FItems[0] := I1;
  I2 := TOrderItemTest.Create; I2.Id := 2; I2.OrderId := 100; FItems[1] := I2;
  I3 := TOrderItemTest.Create; I3.Id := 3; I3.OrderId := 200; FItems[2] := I3;

  FMasterDS.Load(FOrders, TUserTest);
  FDetailDS.Load(FItems, TOrderItemTest);
end;

procedure TMasterDetailDataSetTests.TearDown;
var
  O, I: TObject;
begin
  FDetailDS.Free; FMasterDS.Free;
  for O in FOrders do O.Free;
  for I in FItems do I.Free;
end;

procedure TMasterDetailDataSetTests.Test_Detail_Count;
begin
  Should(FDetailDS.RecordCount).Be(3);
end;

procedure TMasterDetailDataSetTests.Test_Detail_FilterByMaster;
begin
  FDetailDS.Filter := 'OrderId = 100';
  FDetailDS.Filtered := True;
  Should(FDetailDS.RecordCount).Be(2);
end;

procedure TMasterDetailDataSetTests.Test_Detail_FieldValues;
begin
  Should(FDetailDS.FieldByName('OrderId').Required).BeTrue;
end;

procedure TMasterDetailDataSetTests.Test_Real_MasterDetail_Link;
var
  MasterDataSource: TDataSource;
begin
  MasterDataSource := TDataSource.Create(nil);
  try
    MasterDataSource.DataSet := FMasterDS;

    // Configurar o vÃ­nculo clÃ¡ssico
    FDetailDS.MasterSource := MasterDataSource;
    FDetailDS.MasterFields := 'Id';
    FDetailDS.IndexFieldNames := 'OrderId';
    FDetailDS.Open;

    // Master estÃ¡ no registro 100 (Setup posiciona First)
    Should(FMasterDS.FieldByName('Id').AsInteger).Be(100);
    Should(FDetailDS.RecordCount).Be(2);

    // Mudar master para o registro 200
    FMasterDS.Next;
    Should(FMasterDS.FieldByName('Id').AsInteger).Be(200);

    // O detalhe deve ter filtrado automaticamente
    Should(FDetailDS.RecordCount).Be(1);
    Should(FDetailDS.FieldByName('OrderId').AsInteger).Be(200);
  finally
    MasterDataSource.Free;
  end;
end;

{ TEntityDataSetCRUDTests }

procedure TEntityDataSetCRUDTests.Setup;
var
  U1: TUserTest;
begin
  FDataSet := TEntityDataSet.Create(nil);
  FSourceList := TCollections.CreateList<TObject>(True);
  U1 := TUserTest.Create; U1.Id := 1; U1.Name := 'Cesar'; FSourceList.Add(U1);
  FDataSet.Load(FSourceList as IObjectList, TUserTest, False);
end;

procedure TEntityDataSetCRUDTests.TearDown;
begin
  FDataSet.Free;
end;

procedure TEntityDataSetCRUDTests.Test_Append_And_Post;
begin
  FDataSet.Append;
  FDataSet.FieldByName('Id').AsInteger := 2;
  FDataSet.FieldByName('Name').AsString := 'New';
  FDataSet.Post;
  Should(FSourceList.Count).Be(2);
end;

procedure TEntityDataSetCRUDTests.Test_Edit_Existing;
begin
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Editado';
  FDataSet.Post;
  Should(TUserTest(FSourceList[0]).Name).Be('Editado');
end;

procedure TEntityDataSetCRUDTests.Test_Cancel_Edit_Restores_Value;
begin
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Editado';
  FDataSet.Cancel;
  // Edit writes straight to the entity, so Cancel has to put the value back
  // and forget the change it had started to track.
  Should(TUserTest(FSourceList[0]).Name).Be('Cesar');
  Should(FDataSet.FieldByName('Name').AsString).Be('Cesar');
  Should(FDataSet.Changes.Count).Be(0);
end;

procedure TEntityDataSetCRUDTests.Test_Cancel_Edit_Keeps_Earlier_Posted_Edit;
begin
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Um';
  FDataSet.Post;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Dois';
  FDataSet.FieldByName('Score').AsFloat := 5;
  FDataSet.Cancel;
  // Cancel goes back to the value before THIS edit, not to the original one.
  Should(TUserTest(FSourceList[0]).Name).Be('Um');
  Should(TUserTest(FSourceList[0]).Score).Be(0.0);
  Should(FDataSet.Changes.Count).Be(1);
  Should(Length(FDataSet.Changes[0].DirtyFields)).Be(1);
end;

procedure TEntityDataSetCRUDTests.Test_Cancel_Edit_Does_Not_Leak_Dirty_Fields;
begin
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('Score').AsFloat := 9;
  FDataSet.Cancel;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Novo';
  FDataSet.Post;
  // The cancelled field must not show up as dirty in the next post.
  Should(FDataSet.Changes.Count).Be(1);
  Should(Length(FDataSet.Changes[0].DirtyFields)).Be(1);
  Should(FDataSet.Changes[0].DirtyFields[0]).Be('Name');
end;

procedure TEntityDataSetCRUDTests.Test_Append_Goes_To_The_End;
begin
  FDataSet.First;
  FDataSet.Append;
  FDataSet.FieldByName('Name').AsString := 'Fim';
  FDataSet.Post;
  // Append is "at the end", wherever the cursor was.
  Should(TUserTest(FSourceList[0]).Name).Be('Cesar');
  Should(TUserTest(FSourceList[1]).Name).Be('Fim');
end;

procedure TEntityDataSetCRUDTests.Test_Insert_Goes_Before_The_Current_Row;
begin
  FDataSet.First;
  FDataSet.Insert;
  FDataSet.FieldByName('Name').AsString := 'Antes';
  FDataSet.Post;
  Should(TUserTest(FSourceList[0]).Name).Be('Antes');
  Should(TUserTest(FSourceList[1]).Name).Be('Cesar');
end;

procedure TEntityDataSetCRUDTests.Test_ReadOnly_Blocks_Edit_Append_And_Delete;
begin
  FDataSet.ReadOnly := True;
  Should(FDataSet.CanModify).BeFalse;
  FDataSet.First;
  Should(
    procedure
    begin
      FDataSet.Edit;
    end).Throw<EDatabaseError>;
  Should(
    procedure
    begin
      FDataSet.Append;
    end).Throw<EDatabaseError>;
  Should(
    procedure
    begin
      FDataSet.Delete;
    end).Throw<EDatabaseError>;
  Should(FSourceList.Count).Be(1);

  FDataSet.ReadOnly := False;
  Should(FDataSet.CanModify).BeTrue;
end;

procedure TEntityDataSetCRUDTests.Test_Delete_And_Sync;
begin
  FDataSet.First;
  FDataSet.Delete;
  Should(FSourceList.Count).Be(0);
end;

procedure TEntityDataSetCRUDTests.Test_Insert_Between_Records;
var
  U2: TUserTest;
begin
  U2 := TUserTest.Create; U2.Id := 3; U2.Name := 'Treis'; FSourceList.Add(U2);
  FDataSet.Refresh;
  FDataSet.Last;
  FDataSet.Insert;
  FDataSet.FieldByName('Id').AsInteger := 2;
  FDataSet.FieldByName('Name').AsString := 'Dois';
  FDataSet.Post;
  FDataSet.First; FDataSet.Next;
  Should(FDataSet.FieldByName('Id').AsInteger).Be(2);
end;

procedure TEntityDataSetCRUDTests.Test_Refresh_Syncs_External_Changes;
var
  U2: TUserTest;
begin
  U2 := TUserTest.Create;
  U2.Id := 2;
  U2.Name := 'Externo';
  FSourceList.Add(U2);
  FDataSet.Refresh;
  Should(FDataSet.RecordCount).Be(2);
  FDataSet.Last;
  Should(FDataSet.FieldByName('Name').AsString).Be('Externo');
end;

{ TEntityDataSetStressTests }

procedure TEntityDataSetStressTests.Setup;
var
  I: Integer;
  U: TUserTest;
begin
  FUsers := TCollections.CreateList<TObject>(True);
  for I := 1 to 1000 do
  begin
    U := TUserTest.Create;
    U.Id := I; U.Name := 'U' + I.ToString; U.Score := I * 2; U.Active := (I mod 2 = 0);
    FUsers.Add(U);
  end;
  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.Load(FUsers as IObjectList, TUserTest, False);
end;

procedure TEntityDataSetStressTests.TearDown;
begin
  FDataSet.Free;
end;

procedure TEntityDataSetStressTests.Test_Stress_1k_Records_Filter;
begin
  FDataSet.Filter := 'Score > 1000';
  FDataSet.Filtered := True;
  Should(FDataSet.RecordCount).Be(500);
end;

procedure TEntityDataSetStressTests.Test_Edit_Into_Filter_Hides_Record;
begin
  FDataSet.Filter := 'Active = True';
  FDataSet.Filtered := True;
  FDataSet.First; // ID 2
  FDataSet.Edit;
  FDataSet.FieldByName('Active').AsBoolean := False;
  FDataSet.Post;
  Should(FDataSet.RecordCount).Be(499);
end;

{ TDataSetSmartTypesTests }

procedure TDataSetSmartTypesTests.Test_Read_SmartTypes;
var
  DataSet: TEntityDataSet;
  Product: TSmartProduct;
begin
  Product := TSmartProduct.Create;
  try
    Product.ID := 1; Product.Name := 'Smart Watch'; Product.Price := 299.90; Product.Quantity := 10; Product.Active := True;
    DataSet := TEntityDataSet.Create(nil);
    DataSet.Load(TArray<TObject>.Create(Product), TSmartProduct);
    try
      DataSet.Open;
      Should(DataSet.FieldByName('ID').AsInteger).Be(1);
      Should(DataSet.FieldByName('Name').AsString).Be('Smart Watch');
    finally
      DataSet.Free;
    end;
  finally
    Product.Free;
  end;
end;

procedure TDataSetSmartTypesTests.Test_Read_Nullable_Empty;
var
  DataSet: TEntityDataSet;
  Product: TSmartProduct;
begin
  Product := TSmartProduct.Create;
  try
    Product.Quantity.Clear;
    DataSet := TEntityDataSet.Create(nil);
    try
      DataSet.Load(TArray<TObject>.Create(Product), TSmartProduct);
      DataSet.Open;
      Should(DataSet.FieldByName('Quantity').IsNull).BeTrue;
    finally
      DataSet.Free;
    end;
  finally
    Product.Free;
  end;
end;

procedure TDataSetSmartTypesTests.Test_Read_Lazy_Value;
var
  DataSet: TEntityDataSet;
  Product: TSmartProduct;
begin
  Product := TSmartProduct.Create;
  try
    Product.Description := 'Lazy';
    DataSet := TEntityDataSet.Create(nil);
    try
      DataSet.Load(TArray<TObject>.Create(Product), TSmartProduct);
      DataSet.Open;
      Should(DataSet.FieldByName('Description').AsString).Be('Lazy');
    finally
      DataSet.Free;
    end;
  finally
    Product.Free;
  end;
end;

{ TShadowTestContext }

procedure TShadowTestContext.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TShadowUser>.ShadowProperty('CreatedBy');
end;

{ TShadowDataSetTests }

procedure TShadowDataSetTests.Setup;
begin
  FContext := TShadowTestContext.Create(nil, nil, nil); 
  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.DbContext := FContext;
  FDataSet.IncludeShadowProperties := True;
end;

procedure TShadowDataSetTests.TearDown;
begin
  FDataSet.Free;
  FContext.Free;
end;

procedure TShadowDataSetTests.Test_ShadowProperty_Read_From_Context;
var
  U: TShadowUser;
begin
  U := TShadowUser.Create;
  try
    U.Id := 1;
    U.Name := 'Cesar';
    
    // Set a shadow value in the context
    FContext.ChangeTracker.Track(U, esUnchanged);
    FContext.Entry(U).Member('CreatedBy').SetCurrentValue('Admin');
    
    FDataSet.Load(TArray<TObject>.Create(U), TShadowUser);
    FDataSet.Open;
    
    Should(FDataSet.FieldByName('CreatedBy').AsString).Be('Admin');
  finally
    U.Free;
  end;
end;

procedure TShadowDataSetTests.Test_ShadowProperty_Write_Updates_Context;
var
  U: TShadowUser;
begin
  U := TShadowUser.Create;
  try
    U.Id := 1;
    U.Name := 'Cesar';
    FContext.ChangeTracker.Track(U, esUnchanged);
    
    FDataSet.Load(TArray<TObject>.Create(U), TShadowUser);
    FDataSet.Open;
    
    FDataSet.Edit;
    FDataSet.FieldByName('CreatedBy').AsString := 'Manager';
    FDataSet.Post;
    
    // Verify context was updated
    Should(FContext.Entry(U).Member('CreatedBy').GetCurrentValue.AsString).Be('Manager');
  finally
    U.Free;
  end;
end;

{ TSmartPropertyDataSetTests }

procedure TSmartPropertyDataSetTests.Setup;
begin
  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.Load<TTestSmartEntity>(TArray<TTestSmartEntity>.Create());
end;

procedure TSmartPropertyDataSetTests.TearDown;
begin
  FDataSet.Free;
end;

procedure TSmartPropertyDataSetTests.Test_Smart_Fields_Naming_And_Types;
var
  LField: TField;
begin
  FDataSet.Open;
  
  // Verify Description text field type (sfAuto without provider defaults to ftString)
  LField := FDataSet.FindField('Description');
  Should(LField).NotBeNull;
  Should(LField.DataType).Be(ftString);

  // Verify Price (Prop<Double> -> ftFloat)
  LField := FDataSet.FindField('Price');
  Should(LField).NotBeNull;
  Should(LField.DataType).Be(ftFloat);

  // Verify Age (Nullable<Integer> -> ftInteger)
  LField := FDataSet.FindField('Age');
  Should(LField).NotBeNull;
  Should(LField.DataType).Be(ftInteger);
end;

{ TFloatingPointDataSetTests }

procedure TFloatingPointDataSetTests.Setup;
begin
  FObj := TFloatingPointTest.Create;
  FObj.Id := 1;
  FObj.DoubleVal := 123.456;
  FObj.CurrencyVal := 987.6543;

  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.Load([FObj], TFloatingPointTest);
end;

procedure TFloatingPointDataSetTests.TearDown;
begin
  FDataSet.Free;
  FObj.Free;
end;

procedure TFloatingPointDataSetTests.Test_Double_Value;
begin
  FDataSet.Open;
  Should(FDataSet.FieldByName('DoubleVal').AsFloat).Be(123.456);
end;

procedure TFloatingPointDataSetTests.Test_Currency_Value;
begin
  // Currency has 4 decimal places precision.
  FDataSet.Open;
  Should(FDataSet.FieldByName('CurrencyVal').AsCurrency).Be(987.6543);
end;

procedure TFloatingPointDataSetTests.Test_Format_And_Precision;
begin
  // A common issue with Currency in DataSets is scientific notation
  // if not handled as ftCurrency.
  FDataSet.Open;
  Should(FDataSet.FieldByName('CurrencyVal').DataType).Be(ftCurrency);
  
  // FireDAC-like behavior: no forced default DisplayFormat.
  // Formatting should come from locale/consumer unless explicitly configured.
  Should(TFloatField(FDataSet.FieldByName('DoubleVal')).DisplayFormat).Be('');
  Should(TCurrencyField(FDataSet.FieldByName('CurrencyVal')).DisplayFormat).Be('');
end;

{ TOrderTest }

constructor TOrderTest.Create;
begin
  FItems := TCollections.CreateList<TOrderItemTest>(True);
end;

destructor TOrderTest.Destroy;
begin
  FItems := nil;
  inherited;
end;

{ TNativeMasterDetailTests }

procedure TNativeMasterDetailTests.Setup;
var
  Item: TOrderItemTest;
begin
  FOrder := TOrderTest.Create;
  FOrder.Id := 1;
  
  Item := TOrderItemTest.Create;
  Item.Id := 101;
  Item.ProductName := 'Item 1';
  FOrder.Items.Add(Item);

  Item := TOrderItemTest.Create;
  Item.Id := 102;
  Item.ProductName := 'Item 2';
  FOrder.Items.Add(Item);

  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.Load([FOrder], TOrderTest);
  FDataSet.Open;
end;

procedure TNativeMasterDetailTests.TearDown;
begin
  FDataSet.Free;
  FOrder.Free;
end;

procedure TNativeMasterDetailTests.Test_Access_Detail_DataSet;
var
  DetailField: TDataSetField;
begin
  DetailField := FDataSet.FieldByName('Items') as TDataSetField;
  Should(DetailField.NestedDataSet).NotBeNull;
  
  DetailField.NestedDataSet.Open;
  Should(DetailField.NestedDataSet.FieldByName('ProductName').AsString).Be('Item 1');
end;

procedure TNativeMasterDetailTests.Test_Detail_RecordCount;
var
  DetailField: TDataSetField;
begin
  DetailField := FDataSet.FieldByName('Items') as TDataSetField;
  DetailField.NestedDataSet.Open;
  Should(DetailField.NestedDataSet.RecordCount).Be(2);
end;

{ TEntityDataSetAutomationTests }

procedure TEntityDataSetAutomationTests.Setup;
begin
  FMasterDS := TEntityDataSet.Create(nil);
  FMasterDS.Load<TOrderTest>(TCollections.CreateList<TOrderTest>(False), True);
end;

procedure TEntityDataSetAutomationTests.TearDown;
begin
  FMasterDS.Free;
end;

procedure TEntityDataSetAutomationTests.Test_AutoInstantiate_Collection_Via_Attribute;
var
  LObj: TOrderTest;
begin
  // Nota: Renomeado mentalmente para "Via_Activator" ja que Inject eh instavel com o Linker em certos tipos
  FMasterDS.Append;
  LObj := FMasterDS.GetCurrentObject as TOrderTest;
  
  // A lista Items deve ter sido instanciada internamente pelo InternalInsert
  // via registro global no initialization desta unit
  Should(LObj.Items).NotBeNil;
  FMasterDS.Cancel;
end;

procedure TEntityDataSetAutomationTests.Test_MasterDetail_ID_Sync_Nested;
var
  LItemsField: TDataSetField;
  LDetailDS: TEntityDataSet;
begin
  // 1. Carrega o mestre (Load ja cria os campos automaticamente via RTTI)
  FMasterDS.Append;
  FMasterDS.FieldByName('Id').AsInteger := 500;
  FMasterDS.Post;
  
  // 2. Busca o campo aninhado gerado automaticamente pelo Load<TOrderTest>
  LItemsField := FMasterDS.FieldByName('Items') as TDataSetField;
  LDetailDS := LItemsField.NestedDataSet as TEntityDataSet;
  
  // 3. Configura a vinculacao (o TDataSetField ja os conhece mas o dataset detalhe precisa deles para o sync)
  LDetailDS.MasterFields := 'Id';
  LDetailDS.IndexFieldNames := 'OrderId';
  
  // 4. Insere no detalhe e valida a heranca automatica do ID
  LDetailDS.Append;
  Should(LDetailDS.FieldByName('OrderId').AsInteger).Be(500);
  LDetailDS.Cancel;
end;

procedure TEntityDataSetAutomationTests.Test_TActivator_Tip_Error_Message;
var
  LDS: TEntityDataSet;
begin
  LDS := TEntityDataSet.Create(nil);
  try
    // Forcar erro via Append em uma classe com lista nao registrada
    LDS.Load<TUnregisteredEntity>(TCollections.CreateList<TUnregisteredEntity>(False), True);
    try
      LDS.Append;
      raise Exception.Create('Should have raised an exception with a Tip');
    except
      on E: Exception do
        Should(E.Message).Contain('Tip: Register the implementation');
    end;
  finally
    LDS.Free;
  end;
end;

initialization
  // Ensure we have some base registration for tests that need it
  TActivator.RegisterDefault<IList<TOrderItemTest>, TList<TOrderItemTest>>;

end.
