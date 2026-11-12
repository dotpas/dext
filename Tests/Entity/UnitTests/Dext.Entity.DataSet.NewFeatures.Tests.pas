unit Dext.Entity.DataSet.NewFeatures.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  Dext.Core.Span,
  Dext.Testing,
  Dext.Entity.DataSet,
  Dext.Entity.Attributes,
  Dext.Collections;

type
  [Table('products_feat')]
  TProductFeaturesTest = class
  private
    FId: Integer;
    FName: string;
    FPrice: Double;
    FStock: SmallInt;
    FStatus: Byte;
  public
    [PrimaryKey, AutoInc]
    property Id: Integer read FId write FId;

    [Required, MaxLength(100), DisplayWidth(50), DisplayLabel('Product Name')]
    property Name: string read FName write FName;

    [DisplayWidth(15), DisplayLabel('Unit Price')]
    property Price: Double read FPrice write FPrice;

    property Stock: SmallInt read FStock write FStock;
    property Status: Byte read FStatus write FStatus;
  end;

  TRow = class
  private
    FUID: Integer;
    FCOGNOME: string;
    FANNO: Integer;
  public
    property UID: Integer read FUID write FUID;
    property COGNOME: string read FCOGNOME write FCOGNOME;
    property ANNO: Integer read FANNO write FANNO;
  end;

  // Hacker para o TDataLink (permitir acesso a membros publicos/protegidos)
  TMyDataLink = class(TDataLink)
  public
    property ActiveRecord;
    property BufferCount;
  end;

  [TestFixture('TEntityDataSet New Features')]
  TEntityDataSetFeaturesTests = class
  private
    FDataSet: TEntityDataSet;
    FRefreshLog: string;
    procedure DoPrepareField(Sender: TObject; AField: TField);
    procedure DoBeforeRefresh(ADataSet: TDataSet);
    procedure DoAfterRefresh(ADataSet: TDataSet);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure Test_DisplayAttributes_Mapping;
    [Test]
    procedure Test_OnPrepareField_Event;
    [Test]
    procedure Test_Grid_Painting_Simulation_MultiBuffer;
    [Test]
    procedure Test_SmallOrdinals_Serialization;
    [Test]
    procedure Test_ChangeLog_Tracking;
    [Test]
    procedure Test_RejectChanges_Rollback;
    [Test]
    procedure Test_LoadFromJson_PlainDTO_Regression;
    [Test]
    procedure Test_ChangesAsJson_Empty;
    [Test]
    procedure Test_ChangesAsJson_Contract;
    [Test]
    procedure Test_ChangesAsJson_EscapesControlCharacters;
    [Test]
    procedure Test_Refresh_Fires_BeforeRefresh_And_AfterRefresh;
  end;

implementation

{ TEntityDataSetFeaturesTests }

procedure TEntityDataSetFeaturesTests.Setup;
begin
  FDataSet := TEntityDataSet.Create(nil);
end;

procedure TEntityDataSetFeaturesTests.TearDown;
begin
  FDataSet.Free;
end;

procedure TEntityDataSetFeaturesTests.DoPrepareField(Sender: TObject; AField: TField);
begin
  if AField.FieldName = 'Name' then
    AField.ReadOnly := True;
end;

procedure TEntityDataSetFeaturesTests.DoBeforeRefresh(ADataSet: TDataSet);
begin
  FRefreshLog := FRefreshLog + 'B';
end;

procedure TEntityDataSetFeaturesTests.DoAfterRefresh(ADataSet: TDataSet);
begin
  FRefreshLog := FRefreshLog + 'A';
end;

procedure TEntityDataSetFeaturesTests.Test_Refresh_Fires_BeforeRefresh_And_AfterRefresh;
var
  LList: IList<TProductFeaturesTest>;
begin
  // BeforeRefresh and AfterRefresh are published events; Refresh must fire
  // them like any TDataSet, before and after the rows are read again.
  LList := TCollections.CreateList<TProductFeaturesTest>;
  FDataSet.Load<TProductFeaturesTest>(LList);
  FDataSet.BeforeRefresh := DoBeforeRefresh;
  FDataSet.AfterRefresh := DoAfterRefresh;
  FRefreshLog := '';

  FDataSet.Refresh;

  Should(FRefreshLog).Be('BA');
end;

procedure TEntityDataSetFeaturesTests.Test_DisplayAttributes_Mapping;
var
  LList: IList<TProductFeaturesTest>;
  FldName, FldPrice: TField;
begin
  LList := TCollections.CreateList<TProductFeaturesTest>;
  FDataSet.Load<TProductFeaturesTest>(LList);
  
  FldName := FDataSet.FindField('Name');
  FldPrice := FDataSet.FindField('Price');
  
  Should(FldName).NotBeNil;
  Should(FldName.DisplayWidth).Be(50);
  Should(FldName.DisplayLabel).Be('Product Name');
  
  Should(FldPrice).NotBeNil;
  Should(FldPrice.DisplayWidth).Be(15);
  Should(FldPrice.DisplayLabel).Be('Unit Price');
end;

procedure TEntityDataSetFeaturesTests.Test_OnPrepareField_Event;
var
  LList: IList<TProductFeaturesTest>;
begin
  LList := TCollections.CreateList<TProductFeaturesTest>;
  FDataSet.OnPrepareField := DoPrepareField;
  
  FDataSet.Load<TProductFeaturesTest>(LList);
  
  Should(FDataSet.FieldByName('Name').ReadOnly).BeTrue;
  Should(FDataSet.FieldByName('Price').ReadOnly).BeFalse;
end;

procedure TEntityDataSetFeaturesTests.Test_Grid_Painting_Simulation_MultiBuffer;
var
  L: IList<TProductFeaturesTest>;
  LDataSource: TDataSource;
  LDataLink: TMyDataLink;
  P1, P2: TProductFeaturesTest;
begin
  L := TCollections.CreateList<TProductFeaturesTest>(True);
  P1 := TProductFeaturesTest.Create;
  P1.Id := 1; P1.Name := 'Product 1';
  P2 := TProductFeaturesTest.Create;
  P2.Id := 2; P2.Name := 'Product 2';
  L.Add(P1);
  L.Add(P2);

  FDataSet.Load<TProductFeaturesTest>(L);
  FDataSet.Open;

  LDataSource := TDataSource.Create(nil);
  LDataLink := TMyDataLink.Create;
  try
    LDataSource.DataSet := FDataSet;
    LDataLink.DataSource := LDataSource;
    
    // Simula a Grid tendo espaco para buffers (BufferCount > 1)
    LDataLink.BufferCount := 5;

    // 1. Dataset posicionado no primeiro registro (FCurrentRec = 0)
    FDataSet.First;
    Should(FDataSet.FieldByName('Id').AsInteger).Be(1);
    Should(LDataLink.ActiveRecord).Be(0);

    // 2. SIMULACAO DA GRID PINTANDO A SEGUNDA LINHA:
    // A Grid seta o ActiveRecord do DataLink como 1.
    // Isso dispara o mecanismo interno do TDataSet (via unit Data.DB) 
    // que aponta o ActiveBuffer para o segundo buffer da lista.
    LDataLink.ActiveRecord := 1;

    // 3. VALIDACAO DA CORRECAO:
    // O TEntityDataSet deve ler o BookmarkIndex contido no ActiveBuffer (que agora eh 1),
    // e retornar o valor do segundo objeto ('Product 2'), 
    // mesmo que globalmente o cursor ainda esteja em First (0).
    Should(FDataSet.FieldByName('Id').AsInteger).Be(2).Because('O Dataset deve respeitar o buffer alternativo setado pela Grid/DataLink');
    Should(FDataSet.FieldByName('Name').AsString).Be('Product 2');

    // 4. Volta para o indice 0 para confirmar restauracao do contexto
    LDataLink.ActiveRecord := 0;
    Should(FDataSet.FieldByName('Id').AsInteger).Be(1);

  finally
    LDataLink.Free;
    LDataSource.Free;
  end;
end;

procedure TEntityDataSetFeaturesTests.Test_SmallOrdinals_Serialization;
var
  JsonData: string;
  Span: TByteSpan;
  Bytes: TBytes;
begin
  JsonData := '[{"Id":1,"Name":"A","Stock":100,"Status":2}]';
  Bytes := TEncoding.UTF8.GetBytes(JsonData);
  Span := TByteSpan.FromBytes(Bytes);
  FDataSet.LoadFromUtf8Json<TProductFeaturesTest>(Span);
  FDataSet.Open;

  Should(FDataSet.FieldByName('Stock').AsInteger).Be(100);
  Should(FDataSet.FieldByName('Status').AsInteger).Be(2);
end;

procedure TEntityDataSetFeaturesTests.Test_ChangeLog_Tracking;
var
  List: IList<TProductFeaturesTest>;
  Prod: TProductFeaturesTest;
  Changes: IList<TEntityChange>;
begin
  List := TCollections.CreateList<TProductFeaturesTest>(True);
  Prod := TProductFeaturesTest.Create;
  Prod.Id := 1;
  Prod.Name := 'Original';
  Prod.Stock := 50;
  Prod.Status := 1;
  List.Add(Prod);

  FDataSet.Load<TProductFeaturesTest>(List);
  FDataSet.Open;

  // 1. Initial State -> Should be empty
  Should(FDataSet.Changes.Count).Be(0);

  // 2. Modify existing
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Modified';
  FDataSet.Post;

  Changes := FDataSet.Changes;
  Should(Changes.Count).Be(1);
  Should(Changes[0].State = ersModified).BeTrue;
  Should(Changes[0].DirtyFields[0]).Be('Name');

  // 3. Insert new
  FDataSet.Append;
  FDataSet.FieldByName('Id').AsInteger := 2;
  FDataSet.FieldByName('Name').AsString := 'New';
  FDataSet.Post;

  Should(FDataSet.Changes.Count).Be(2);
  Should(FDataSet.Changes[1].State = ersInserted).BeTrue;

  // 4. Delete existing (loaded)
  FDataSet.Locate('Id', 1, []);
  FDataSet.Delete;

  // Original modified change should be removed, replaced by ersDeleted tombstone.
  // Inserted change remains at index 0.
  Should(FDataSet.Changes.Count).Be(2);
  Should(FDataSet.Changes[0].State = ersInserted).BeTrue;
  Should(FDataSet.Changes[1].State = ersDeleted).BeTrue;
  Should(FDataSet.Changes[1].Key[0].Key).Be('Id');
  Should(FDataSet.Changes[1].Key[0].Value).Be(1);

  // 5. AcceptChanges
  FDataSet.AcceptChanges;
  Should(FDataSet.Changes.Count).Be(0);
end;

procedure TEntityDataSetFeaturesTests.Test_ChangesAsJson_Empty;
var
  List: IList<TProductFeaturesTest>;
begin
  List := TCollections.CreateList<TProductFeaturesTest>(True);
  FDataSet.Load<TProductFeaturesTest>(List);
  FDataSet.Open;
  Should(FDataSet.ChangesAsJson).Be('{"changes":[]}');
end;

procedure TEntityDataSetFeaturesTests.Test_ChangesAsJson_Contract;
var
  List: IList<TProductFeaturesTest>;
  Prod: TProductFeaturesTest;
  I: Integer;
begin
  List := TCollections.CreateList<TProductFeaturesTest>(True);
  for I := 1 to 3 do
  begin
    Prod := TProductFeaturesTest.Create;
    Prod.Id := I;
    Prod.Name := 'P' + IntToStr(I);
    List.Add(Prod);
  end;
  FDataSet.Load<TProductFeaturesTest>(List);
  FDataSet.Open;

  FDataSet.Locate('Id', 1, []);
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Renamed';
  FDataSet.Post;

  FDataSet.Append;
  FDataSet.FieldByName('Name').AsString := 'New';
  FDataSet.FieldByName('Price').AsFloat := 2.5;
  FDataSet.FieldByName('Stock').AsInteger := 3;
  FDataSet.FieldByName('Status').AsInteger := 4;
  FDataSet.Post;

  FDataSet.Locate('Id', 3, []);
  FDataSet.Delete;

  Should(FDataSet.ChangesAsJson).Be(
    '{"changes":[' +
    '{"state":"modified","key":{"Id":1},"values":{"Name":"Renamed"}},' +
    '{"state":"inserted","values":{"Name":"New","Price":2.5,' +
    '"Stock":3,"Status":4}},' +
    '{"state":"deleted","key":{"Id":3}}]}');
end;

procedure TEntityDataSetFeaturesTests.Test_ChangesAsJson_EscapesControlCharacters;
var
  List: IList<TProductFeaturesTest>;
  Prod: TProductFeaturesTest;
begin
  List := TCollections.CreateList<TProductFeaturesTest>(True);
  Prod := TProductFeaturesTest.Create;
  Prod.Id := 1;
  Prod.Name := 'x';
  List.Add(Prod);
  FDataSet.Load<TProductFeaturesTest>(List);
  FDataSet.Open;

  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Say "hi"'#10 + Chr(92) + #9;
  FDataSet.Post;

  Should(FDataSet.ChangesAsJson).Be(
    '{"changes":[{"state":"modified","key":{"Id":1},' +
    '"values":{"Name":"Say \"hi\"\n\\\t"}}]}');
end;

procedure TEntityDataSetFeaturesTests.Test_RejectChanges_Rollback;
var
  List: IList<TProductFeaturesTest>;
  Prod1: TProductFeaturesTest;
  Prod2: TProductFeaturesTest;
begin
  List := TCollections.CreateList<TProductFeaturesTest>(True);
  Prod1 := TProductFeaturesTest.Create;
  Prod1.Id := 1;
  Prod1.Name := 'Product 1';
  Prod1.Stock := 10;
  Prod1.Status := 1;
  List.Add(Prod1);

  Prod2 := TProductFeaturesTest.Create;
  Prod2.Id := 2;
  Prod2.Name := 'Product 2';
  Prod2.Stock := 20;
  Prod2.Status := 1;
  List.Add(Prod2);

  // Load dataset
  FDataSet.Load<TProductFeaturesTest>(List);
  FDataSet.Open;

  // 1. Executa modificações locais
  // A. Modificar existente (Prod1)
  FDataSet.First;
  FDataSet.Edit;
  FDataSet.FieldByName('Name').AsString := 'Modified Name';
  FDataSet.Post;

  // B. Inserir novo registro
  FDataSet.Append;
  FDataSet.FieldByName('Id').AsInteger := 3;
  FDataSet.FieldByName('Name').AsString := 'Inserted Product';
  FDataSet.Post;

  // C. Deletar existente (Prod2)
  FDataSet.Locate('Id', 2, []);
  FDataSet.Delete;

  // Verifica estado intermediário antes do rollback
  Should(FDataSet.RecordCount).Be(2); // Modificado + Inserido (Deletado sumiu)
  Should(FDataSet.Changes.Count).Be(3); // Modificado, Inserido e Deletado

  // 2. Executa o Rollback
  FDataSet.RejectChanges;

  // 3. Validações pós-rollback
  Should(FDataSet.RecordCount).Be(2); // Deve voltar ao tamanho original (Prod1 + Prod2)
  Should(FDataSet.Changes.Count).Be(0); // Lista de alterações deve estar vazia

  // Deve achar Prod1 e seu valor original deve estar restaurado
  FDataSet.Locate('Id', 1, []);
  Should(FDataSet.FieldByName('Name').AsString).Be('Product 1');

  // Deve achar Prod2 (que havia sido deletado e foi restaurado)
  Should(FDataSet.Locate('Id', 2, [])).BeTrue;
  Should(FDataSet.FieldByName('Name').AsString).Be('Product 2');

  // Não deve achar o registro que foi inserido e descartado
  Should(FDataSet.Locate('Id', 3, [])).BeFalse;
end;

procedure TEntityDataSetFeaturesTests.Test_LoadFromJson_PlainDTO_Regression;
var
  JsonData: string;
  Span: TByteSpan;
  Bytes: TBytes;
begin
  JsonData := '[{"UID":11,"COGNOME":"ROSSI","ANNO":2024}]';
  Bytes := TEncoding.UTF8.GetBytes(JsonData);
  Span := TByteSpan.FromBytes(Bytes);
  FDataSet.LoadFromUtf8Json<TRow>(Span);
  FDataSet.Open;

  Should(FDataSet.RecordCount).Be(1);
  Should(FDataSet.FieldByName('UID').AsInteger).Be(11);
  Should(FDataSet.FieldByName('COGNOME').AsString).Be('ROSSI');
  Should(FDataSet.FieldByName('ANNO').AsInteger).Be(2024);
end;

end.
