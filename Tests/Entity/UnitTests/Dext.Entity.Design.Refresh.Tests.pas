unit Dext.Entity.Design.Refresh.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Phys.Intf,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Collections,
  Dext.Collections.Dict,
  Dext.Entity.Dialects,
  Dext.Entity.DataProvider,
  Dext.Entity.Scaffolding,
  Dext.EF.Design.Scaffolding.Helpers,
  Dext.EF.Design.Metadata;

type
  [TestFixture('Design-time refresh of the entity metadata')]
  TEntityDesignRefreshTests = class
  private
    FSavedHook: TGetSourceContentEvent;
    function NewProvider: TEntityDataProvider;
    function NewConnection: TFDConnection;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test('Refreshing the metadata does not leak the parsed classes')]
    procedure Refresh_DoesNotLeak;
    [Test('A unit that cannot be read is named in the refresh summary')]
    procedure Refresh_NamesTheMissingUnit;
    [Test('A refresh with every unit readable reports no missing unit')]
    procedure Refresh_AllReadable_ReportsNoMissingUnit;
    [Test('The SQL Server preview has the ORDER BY its paging requires')]
    procedure Preview_SqlServer_HasAnOrderBy;
    [Test('The other dialects keep the preview SQL without an ORDER BY')]
    procedure Preview_OtherDialects_HaveNoOrderBy;
    [Test('A preview without a connection says why it is empty')]
    procedure Preview_NoConnection_ReportsWhy;
    [Test('A failed preview query is reported, not swallowed')]
    procedure Preview_FailedQuery_IsReported;
    [Test('A working preview returns the rows and clears the error')]
    procedure Preview_Works_ClearsTheError;
  end;

  [TestFixture('Design-time: entity from a dataset (field type mapping)')]
  TEntityDesignDataSetMappingTests = class
  private
    function DelphiTypeOf(AType: TFieldType; ASize: Integer = 0): string;
  public
    [Test('A Currency field becomes Currency, not an integer')]
    procedure Currency_BecomesCurrency;
    [Test('A Float field becomes Double, not an integer')]
    procedure Float_BecomesDouble;
    [Test('A SmallInt field becomes SmallInt, not a string')]
    procedure SmallInt_BecomesSmallInt;
    [Test('A Byte field becomes SmallInt and a Word field Integer')]
    procedure ByteAndWord_FitTheirRange;
    [Test('A Time field becomes TTime, not a string')]
    procedure Time_BecomesTime;
    [Test('The types that were already right stay right')]
    procedure Existing_Mappings_Stay;
  end;

implementation

const
  ModelSource =
    'unit Design.Refresh.Model;' + sLineBreak +
    'interface' + sLineBreak +
    'uses Dext.Entity.Attributes;' + sLineBreak +
    'type' + sLineBreak +
    '  [Table(''items'')]' + sLineBreak +
    '  TRefreshItem = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FId: Integer;' + sLineBreak +
    '    FName: string;' + sLineBreak +
    '    FPrice: Currency;' + sLineBreak +
    '  public' + sLineBreak +
    '    [PrimaryKey, AutoInc]' + sLineBreak +
    '    property Id: Integer read FId write FId;' + sLineBreak +
    '    [Required, MaxLength(60)]' + sLineBreak +
    '    property Name: string read FName write FName;' + sLineBreak +
    '    property Price: Currency read FPrice write FPrice;' + sLineBreak +
    '  end;' + sLineBreak +
    'implementation' + sLineBreak +
    'end.';

function SourceOfTheModel(const AFileName: string): string;
begin
  // Only the one unit exists; any other name has no source, like a unit
  // that was deleted after the provider listed it.
  if SameText(ExtractFileName(AFileName), 'Design.Refresh.Model.pas') then
    Result := ModelSource
  else
    Result := '';
end;

function LiveBlocks: NativeInt;
var
  State: TMemoryManagerState;
  I: Integer;
begin
  GetMemoryManagerState(State);
  Result := State.TotalAllocatedMediumBlockSize + State.TotalAllocatedLargeBlockSize;
  for I := 0 to High(State.SmallBlockTypeStates) do
    Result := Result + NativeInt(State.SmallBlockTypeStates[I].AllocatedBlockCount);
end;

{ TEntityDesignRefreshTests }

procedure TEntityDesignRefreshTests.Setup;
begin
  FSavedHook := GOnGetSourceContent;
  GOnGetSourceContent := SourceOfTheModel;
end;

procedure TEntityDesignRefreshTests.TearDown;
begin
  GOnGetSourceContent := FSavedHook;
end;

function TEntityDesignRefreshTests.NewProvider: TEntityDataProvider;
begin
  Result := TEntityDataProvider.Create(nil);
  Result.ModelUnits.Add('C:\model\Design.Refresh.Model.pas');
end;

function TEntityDesignRefreshTests.NewConnection: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  Result.Params.Values['DriverID'] := 'SQLite';
  Result.Params.Values['Database'] := ':memory:';
  Result.Connected := True;
end;

procedure TEntityDesignRefreshTests.Refresh_DoesNotLeak;
var
  Provider: TEntityDataProvider;
  Before, After: NativeInt;
  I: Integer;
begin
  Provider := NewProvider;
  try
    // The first refresh warms up the parser and the provider caches.
    RefreshProviderMetadata(Provider);
    Before := LiveBlocks;
    Should(Before).BeGreaterThan(0);

    for I := 1 to 50 do
      RefreshProviderMetadata(Provider);
    After := LiveBlocks;

    // Each refresh used to leave the parsed class and its members behind
    // (about a dozen blocks); 50 refreshes are far above this margin.
    Should(After - Before).BeLessThan(50);
  finally
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Refresh_NamesTheMissingUnit;
var
  Provider: TEntityDataProvider;
begin
  Provider := NewProvider;
  try
    Provider.ModelUnits.Add('C:\model\Ghost.Unit.pas');
    RefreshProviderMetadata(Provider);

    Should(Provider.EntityCount).Be(1);
    Should(Provider.LastRefreshSummary).Contain('Ghost.Unit.pas');
  finally
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Refresh_AllReadable_ReportsNoMissingUnit;
var
  Provider: TEntityDataProvider;
begin
  Provider := NewProvider;
  try
    RefreshProviderMetadata(Provider);

    Should(Provider.LastRefreshSummary).Be('1 entity(ies) found in 1 unit(s).');
  finally
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Preview_SqlServer_HasAnOrderBy;
var
  Provider: TEntityDataProvider;
begin
  Provider := NewProvider;
  try
    RefreshProviderMetadata(Provider);
    Provider.Dialect := ddSQLServer;

    // OFFSET ... FETCH is only valid after an ORDER BY in SQL Server.
    Should(Provider.BuildPreviewSql('TRefreshItem', 10)).Be(
      'SELECT * FROM [items] ORDER BY (SELECT NULL) ' +
      'OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY');
  finally
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Preview_OtherDialects_HaveNoOrderBy;
var
  Provider: TEntityDataProvider;
begin
  Provider := NewProvider;
  try
    RefreshProviderMetadata(Provider);

    Provider.Dialect := ddSQLite;
    Should(Provider.BuildPreviewSql('TRefreshItem', 10)).Be(
      'SELECT * FROM "items" LIMIT 10 OFFSET 0');
    Provider.Dialect := ddPostgreSQL;
    Should(Provider.BuildPreviewSql('TRefreshItem', 10)).Be(
      'SELECT * FROM "items" LIMIT 10 OFFSET 0');
    Provider.Dialect := ddMySQL;
    Should(Provider.BuildPreviewSql('TRefreshItem', 10)).Be(
      'SELECT * FROM `items` LIMIT 10 OFFSET 0');
    Provider.Dialect := ddFirebird;
    Should(Provider.BuildPreviewSql('TRefreshItem', 10)).Be(
      'SELECT * FROM "items" OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY');
  finally
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Preview_NoConnection_ReportsWhy;
var
  Provider: TEntityDataProvider;
  Rows: IList<IDictionary<string, Variant>>;
begin
  Provider := NewProvider;
  try
    RefreshProviderMetadata(Provider);
    Provider.Dialect := ddSQLite;

    Rows := Provider.GetPreviewData('TRefreshItem', 10);

    Should(Rows.Count).Be(0);
    Should(Provider.LastPreviewError).Contain('DatabaseConnection');
  finally
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Preview_FailedQuery_IsReported;
var
  Provider: TEntityDataProvider;
  Conn: TFDConnection;
  Rows: IList<IDictionary<string, Variant>>;
begin
  Provider := NewProvider;
  Conn := NewConnection;
  try
    RefreshProviderMetadata(Provider);
    Provider.Dialect := ddSQLite;
    Provider.DatabaseConnection := Conn;

    // The table "items" was never created.
    Rows := Provider.GetPreviewData('TRefreshItem', 10);

    Should(Rows.Count).Be(0);
    Should(Provider.LastPreviewError).Contain('items');
  finally
    Provider.DatabaseConnection := nil;
    Conn.Free;
    Provider.Free;
  end;
end;

procedure TEntityDesignRefreshTests.Preview_Works_ClearsTheError;
var
  Provider: TEntityDataProvider;
  Conn: TFDConnection;
  Rows: IList<IDictionary<string, Variant>>;
begin
  Provider := NewProvider;
  Conn := NewConnection;
  try
    RefreshProviderMetadata(Provider);
    Provider.Dialect := ddSQLite;
    Provider.DatabaseConnection := Conn;
    Provider.GetPreviewData('TRefreshItem', 10);
    Should(Provider.LastPreviewError).NotBeEmpty;

    Conn.ExecSQL('create table items (Id integer primary key, Name text, ' +
      'Price numeric)');
    Conn.ExecSQL('insert into items (Name, Price) values (''Pen'', 3.5)');
    Rows := Provider.GetPreviewData('TRefreshItem', 10);

    Should(Rows.Count).Be(1);
    Should(Provider.LastPreviewError).BeEmpty;
  finally
    Provider.DatabaseConnection := nil;
    Conn.Free;
    Provider.Free;
  end;
end;

{ TEntityDesignDataSetMappingTests }

function TEntityDesignDataSetMappingTests.DelphiTypeOf(AType: TFieldType;
  ASize: Integer): string;
var
  Mem: TFDMemTable;
  Def: TFieldDef;
  Meta: TMetaTable;
  Generator: TDelphiEntityGenerator;
begin
  Mem := TFDMemTable.Create(nil);
  try
    Def := Mem.FieldDefs.AddFieldDef;
    Def.Name := 'Value';
    Def.DataType := AType;
    if ASize > 0 then
      Def.Size := ASize;
    Mem.CreateDataSet;

    Meta := TScaffoldingHelper.DataSetToMetaTable(Mem);

    Generator := TDelphiEntityGenerator.Create;
    try
      Result := Generator.SQLTypeToDelphiType(Meta.Columns[0].DataType,
        Meta.Columns[0].Precision, Meta.Columns[0].Scale);
    finally
      Generator.Free;
    end;
  finally
    Mem.Free;
  end;
end;

procedure TEntityDesignDataSetMappingTests.Currency_BecomesCurrency;
begin
  Should(DelphiTypeOf(ftCurrency)).Be('Currency');
end;

procedure TEntityDesignDataSetMappingTests.Float_BecomesDouble;
begin
  Should(DelphiTypeOf(ftFloat)).Be('Double');
end;

procedure TEntityDesignDataSetMappingTests.SmallInt_BecomesSmallInt;
begin
  Should(DelphiTypeOf(ftSmallint)).Be('SmallInt');
end;

procedure TEntityDesignDataSetMappingTests.ByteAndWord_FitTheirRange;
begin
  Should(DelphiTypeOf(ftByte)).Be('SmallInt');
  Should(DelphiTypeOf(ftWord)).Be('Integer');
end;

procedure TEntityDesignDataSetMappingTests.Time_BecomesTime;
begin
  Should(DelphiTypeOf(ftTime)).Be('TTime');
end;

procedure TEntityDesignDataSetMappingTests.Existing_Mappings_Stay;
begin
  Should(DelphiTypeOf(ftString, 40)).Be('string');
  Should(DelphiTypeOf(ftInteger)).Be('Integer');
  Should(DelphiTypeOf(ftLargeint)).Be('Int64');
  Should(DelphiTypeOf(ftBoolean)).Be('Boolean');
  Should(DelphiTypeOf(ftDateTime)).Be('TDateTime');
  Should(DelphiTypeOf(ftBlob)).Be('TBytes');
end;

end.
