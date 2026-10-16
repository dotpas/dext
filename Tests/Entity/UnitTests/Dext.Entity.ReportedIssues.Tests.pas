unit Dext.Entity.ReportedIssues.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  Data.DB,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Collections,
  Dext.Entity.DataSet,
  Dext.Entity.DataProvider,
  Dext.Entity.Core,
  Dext.EF.Design.Metadata;

type
  [TestFixture('Reported Issues from Flash Session')]
  TEntityReportedIssuesTests = class
  private
    FDataProvider: TEntityDataProvider;
    FDataSet: TEntityDataSet;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Issue_3_TableName_Should_Be_Serialized_And_Restored;

    [Test]
    procedure Issue_2_5_AddFields_Should_Not_Contain_Fields_From_Other_Entities;

    [Test]
    procedure Issue_6_Activate_Dataset_Should_Not_AV_Even_Without_RTTI_Class;
    
    [Test]
    procedure Test_Metadata_Persistence_Via_Streams;

    [Test]
    procedure Test_GenerateFields_Should_Not_Duplicate_Existing_Fields;

    [Test]
    procedure Issue_192_FireDAC_Param_Binding_Should_Not_Truncate_Int64;
  end;

implementation

uses
  System.IOUtils,
  System.Rtti,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  Dext.Types.Nullable,
  Dext.Entity.Dialects,
  Dext.Entity.Drivers.FireDAC;

procedure SetComponentDesigning(AComponent: TComponent; ADesigning: Boolean);
var
  Context: TRttiContext;
  RType: TRttiType;
  Field: TRttiField;
  State: TComponentState;
begin
  Context := TRttiContext.Create;
  RType := Context.GetType(TComponent);
  Field := RType.GetField('FComponentState');
  if Field <> nil then
  begin
    State := AComponent.ComponentState;
    if ADesigning then
      Include(State, csDesigning)
    else
      Exclude(State, csDesigning);
    Field.SetValue(AComponent, TValue.From<TComponentState>(State));
  end;
end;

procedure TEntityReportedIssuesTests.Setup;
begin
  FDataProvider := TEntityDataProvider.Create(nil);
  FDataSet := TEntityDataSet.Create(nil);
  FDataSet.DataProvider := FDataProvider;
end;

procedure TEntityReportedIssuesTests.TearDown;
begin
  FDataSet.Free;
  FDataProvider.Free;
end;

procedure TEntityReportedIssuesTests.Issue_3_TableName_Should_Be_Serialized_And_Restored;
var
  MD: TEntityClassMetadata;
begin
  MD := TEntityClassMetadata.Create;
  try
    MD.EntityClassName := 'TOrder';
    MD.TableName := 'orders_table_name';
    MD.EntityUnitName := 'MasterDetailForm';
    FDataProvider.AddOrSetMetadata(MD);
  finally
    MD.Free;
  end;

  SetComponentDesigning(FDataSet, True);
  try
    FDataSet.EntityClassName := 'TOrder';
    Should(FDataSet.TableName).Be('orders_table_name');
  finally
    SetComponentDesigning(FDataSet, False);
  end;
  
  FDataSet.TableName := 'custom_orders_table';
  
  var Stream := TMemoryStream.Create;
  try
    Stream.WriteComponent(FDataSet);
    Stream.Position := 0;
    
    var NewDataSet := TEntityDataSet.Create(nil);
    try
      NewDataSet.DataProvider := FDataProvider;
      Stream.ReadComponent(NewDataSet);
      
      Should(NewDataSet.TableName).Be('custom_orders_table');
    finally
      NewDataSet.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TEntityReportedIssuesTests.Issue_2_5_AddFields_Should_Not_Contain_Fields_From_Other_Entities;
var
  MDOrder, MDCustomer: TEntityClassMetadata;
  FieldDefs: TFieldDefs;
begin
  MDOrder := TEntityClassMetadata.Create;
  try
    MDOrder.EntityClassName := 'TOrder';
    MDOrder.Members.Add.Name := 'OrderId';
    FDataProvider.AddOrSetMetadata(MDOrder);
  finally
    MDOrder.Free;
  end;

  MDCustomer := TEntityClassMetadata.Create;
  try
    MDCustomer.EntityClassName := 'TCustomer';
    MDCustomer.Members.Add.Name := 'CustomerId';
    FDataProvider.AddOrSetMetadata(MDCustomer);
  finally
    MDCustomer.Free;
  end;

  SetComponentDesigning(FDataSet, True);
  try
    FDataSet.EntityClassName := 'TOrder';
    
    FieldDefs := FDataSet.FieldDefs;
    FieldDefs.Update;
    
    Should(FieldDefs.Count).Be(1);
    Should(FieldDefs[0].Name).Be('OrderId');
    
    FDataSet.EntityClassName := 'TCustomer';
    FieldDefs.Update;
    
    Should(FieldDefs.Count).Be(1);
    Should(FieldDefs[0].Name).Be('CustomerId');
  finally
    SetComponentDesigning(FDataSet, False);
  end;
end;

procedure TEntityReportedIssuesTests.Issue_6_Activate_Dataset_Should_Not_AV_Even_Without_RTTI_Class;
begin
  FDataSet.EntityClassName := 'TNonExistentClass';
  
  try
    FDataSet.Active := True;
  except
    on E: EAccessViolation do
      Assert.Fail('Should not raise Access Violation when activating dataset without RTTI class: ' + E.Message);
    on E: Exception do
      ;
  end;
end;

procedure TEntityReportedIssuesTests.Test_Metadata_Persistence_Via_Streams;
var
  Stream: TMemoryStream;
  LoadedProvider: TEntityDataProvider;
  MD: TEntityClassMetadata;
  LoadedMD: TEntityClassMetadata;
begin
  MD := TEntityClassMetadata.Create;
  try
    MD.EntityClassName := 'TPersistentOrder';
    MD.TableName := 'orders';
    MD.EntityUnitName := 'OrderUnit';
    
    var M1 := MD.Members.Add;
    M1.Name := 'Id';
    M1.MemberType := 'Integer';
    M1.IsPrimaryKey := True;
    
    var M2 := MD.Members.Add;
    M2.Name := 'Total';
    M2.MemberType := 'Currency';
    
    FDataProvider.AddOrSetMetadata(MD);
  finally
    MD.Free;
  end;

  Stream := TMemoryStream.Create;
  try
    Stream.WriteComponent(FDataProvider);
    Stream.Position := 0;
    
    LoadedProvider := TEntityDataProvider.Create(nil);
    try
      Stream.ReadComponent(LoadedProvider);
      
      Should(LoadedProvider.EntityCount).Be(1);
      LoadedMD := LoadedProvider.GetEntityMetadata('TPersistentOrder');
      Should(LoadedMD).NotBeNil;
      Should(LoadedMD.TableName).Be('orders');
      Should(LoadedMD.EntityUnitName).Be('OrderUnit');
      Should(LoadedMD.Members.Count).Be(2);
      Should(LoadedMD.Members[0].Name).Be('Id');
      Should(LoadedMD.Members[0].IsPrimaryKey).BeTrue;
      Should(LoadedMD.Members[1].Name).Be('Total');
      Should(LoadedMD.Members[1].MemberType).Be('Currency');
    finally
      LoadedProvider.Free;
    end;
  finally
    Stream.Free;
  end;
end;

procedure TEntityReportedIssuesTests.Test_GenerateFields_Should_Not_Duplicate_Existing_Fields;
var
  MD: TEntityClassMetadata;
  Member: TEntityMemberMetadata;
  F: TField;
begin
  MD := TEntityClassMetadata.Create;
  try
    MD.EntityClassName := 'TOrder';
    
    Member := MD.Members.Add;
    Member.Name := 'OrderId';
    Member.MemberType := 'Integer';
    
    FDataProvider.AddOrSetMetadata(MD);
  finally
    MD.Free;
  end;
  
  FDataSet.EntityClassName := 'TOrder';
  
  F := TIntegerField.Create(FDataSet);
  F.FieldName := 'OrderId';
  F.DataSet := FDataSet;
  
  Should(FDataSet.FieldCount).Be(1);
  
  SetComponentDesigning(FDataSet, True);
  try
    FDataSet.FieldDefs.Update;
    FDataSet.GenerateFields;
    
    Should(FDataSet.FieldCount).Be(1);
    Should(FDataSet.Fields[0].FieldName).Be('OrderId');
  finally
    SetComponentDesigning(FDataSet, False);
  end;
end;

procedure TEntityReportedIssuesTests.Issue_192_FireDAC_Param_Binding_Should_Not_Truncate_Int64;
var
  Conn: TFDConnection;
  Cmd: TFireDACCommand;
  EanValue: Int64;
  MaxInt64Value: Int64;
  NullableEan: Nullable<Int64>;
  EmptyNullable: Nullable<Int64>;
begin
  EanValue := 7898040321642; 
  MaxInt64Value := 9223372036854775807;
  NullableEan := EanValue;
  // Nullable<Int64> has no managed fields, so a local is NOT zero-initialized
  EmptyNullable.Clear;

  Conn := TFDConnection.Create(nil);
  try
    Cmd := TFireDACCommand.Create(Conn, ddSQLite);
    try
      Cmd.SetSQL('SELECT * FROM dummy WHERE pEan = :pEan AND pMax = :pMax AND pNullEan = :pNullEan AND pEmpty = :pEmpty AND pInt32 = :pInt32');

      Cmd.AddParam('pEan', TValue.From<Int64>(EanValue));
      Should(Cmd.GetParamValue('pEan').AsInt64).Be(EanValue);

      Cmd.AddParam('pMax', TValue.From<Int64>(MaxInt64Value));
      Should(Cmd.GetParamValue('pMax').AsInt64).Be(MaxInt64Value);

      Cmd.AddParam('pNullEan', TValue.From<Nullable<Int64>>(NullableEan));
      Should(Cmd.GetParamValue('pNullEan').AsInt64).Be(EanValue);

      Cmd.AddParam('pEmpty', TValue.From<Nullable<Int64>>(EmptyNullable));
      Should(Cmd.Query.ParamByName('pEmpty').DataType = ftLargeInt).BeTrue;
      Should(Cmd.Query.ParamByName('pEmpty').IsNull).BeTrue;

      Cmd.AddParam('pInt32', TValue.From<Integer>(12345));
      Should(Cmd.GetParamValue('pInt32').AsInteger).Be(12345);
    finally
      Cmd.Free;
    end;
  finally
    Conn.Free;
  end;
end;

end.
