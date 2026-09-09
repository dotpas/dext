unit MCP.VclDbDemo.Main;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.Grids, Vcl.DBGrids, Vcl.StdCtrls,
  Vcl.ExtCtrls, Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Error, FireDAC.UI.Intf, FireDAC.Phys.Intf, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef, FireDAC.Stan.ExprFuncs, FireDAC.VCLUI.Wait,
  FireDAC.Comp.Client, FireDAC.Comp.UI, DextJsonDataObjects,
  Dext.AI.MCP.Server, Dext.AI.MCP.Tools, Dext.AI.MCP.Types, Dext.AI.MCP.Attributes,
  Dext.AI.MCP.Protocol, FireDAC.Phys.SQLiteWrapper.Stat, FireDAC.ConsoleUI.Wait, FireDAC.Stan.Param, FireDAC.DatS,
  FireDAC.DApt.Intf, FireDAC.DApt, FireDAC.Comp.DataSet;

type
  TFormMain = class(TForm)
    PanelTop: TPanel;
    PanelLeft: TPanel;
    PanelRight: TPanel;
    LabelPort: TLabel;
    EditPort: TEdit;
    BtnStart: TButton;
    BtnStop: TButton;
    MemoLogs: TMemo;
    DBGrid1: TDBGrid;
    LabelLogs: TLabel;
    LabelDB: TLabel;
    FDConnection: TFDConnection;
    FDPhysSQLiteDriverLink1: TFDPhysSQLiteDriverLink;
    FDGUIxWaitCursor1: TFDGUIxWaitCursor;
    DataSource1: TDataSource;
    FDTableParticipantes: TFDTable;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BtnStartClick(Sender: TObject);
    procedure BtnStopClick(Sender: TObject);
  private
    FMCPServer: TMCPServer;
    procedure InitDatabase;
    procedure LogMsg(const AMsg: string);
    procedure SyncRefreshGrid;
  public
    // Tool callbacks (invoked by the MCP provider)
    function DoListar(const Args: TJsonObject): TMCPToolResult;
    function DoSortear(const Args: TJsonObject): TMCPToolResult;
    function DoExecutarSQL(const Args: TJsonObject): TMCPToolResult;
  end;

  // RTTI tool provider class
  // ===========================================================================
  // AVISO DE ARQUITETURA & ESCALABILIDADE:
  //
  // Este provedor de MCP (TDatabaseMCPProvider) está fortemente acoplado à classe
  // TFormMain e compartilha diretamente suas conexões e estado de tela.
  // Esta decisão de design foi tomada CONSCIENTEMENTE apenas por simplicidade
  // de demonstração, visando exemplificar como injetar lógica de IA em projetos
  // legados VCL existentes.
  //
  // Em uma aplicação real/produção baseada no Dext Framework, você deve:
  //   1. Criar classes de Provedor MCP e Serviços isoladas do código de UI.
  //   2. Utilizar Injeção de Dependência (DI) nativa do Dext para prover conexões.
  //   3. Criar conexões de banco por escopo (scoped/transient) nas threads secundárias
  //      das requisições MCP, evitando colidir/concorrer com a conexão da tela principal.
  // ===========================================================================
  TDatabaseMCPProvider = class(TMCPToolProvider)
  private
    FForm: TFormMain;
  public
    constructor Create(AForm: TFormMain);

    [MCPTool('listar-participantes', 'Retorna a lista de todos os participantes do sorteio cadastrados no banco.')]
    function ListarParticipantes(const Args: TJsonObject): TMCPToolResult; virtual;

    [MCPTool('sortear-participante', 'Sorteia um participante que ainda não ganhou e o marca como sorteado.')]
    [MCPParam('evento', 'Nome do evento de sorteio (opcional)', ptString, False)]
    function SortearParticipante(const Args: TJsonObject): TMCPToolResult; virtual;

    [MCPTool('executar-sql', 'Executa uma consulta SQL SELECT ou comando UPDATE/INSERT no banco SQLite.')]
    [MCPParam('sql', 'O comando SQL completo a ser executado', ptString, True)]
    function ExecutarSQL(const Args: TJsonObject): TMCPToolResult; virtual;
  end;

var
  FormMain: TFormMain;

implementation

{$R *.dfm}

{ TDatabaseMCPProvider }

constructor TDatabaseMCPProvider.Create(AForm: TFormMain);
begin
  inherited Create;
  FForm := AForm;
end;

function TDatabaseMCPProvider.ListarParticipantes(const Args: TJsonObject): TMCPToolResult;
begin
  Result := FForm.DoListar(Args);
end;

function TDatabaseMCPProvider.SortearParticipante(const Args: TJsonObject): TMCPToolResult;
begin
  Result := FForm.DoSortear(Args);
end;

function TDatabaseMCPProvider.ExecutarSQL(const Args: TJsonObject): TMCPToolResult;
begin
  Result := FForm.DoExecutarSQL(Args);
end;

{ TFormMain }

procedure TFormMain.FormCreate(Sender: TObject);
begin
  ReportMemoryLeaksOnShutdown := True;
  EditPort.Text := '3031';
  BtnStart.Enabled := True;
  BtnStop.Enabled := False;
  InitDatabase;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  BtnStopClick(nil);
end;

procedure TFormMain.InitDatabase;
var
  Qry: TFDQuery;
begin
  // Configura conexão SQLite em memória
  FDConnection.Params.Clear;
  FDConnection.Params.Add('DriverID=SQLite');
  FDConnection.Params.Add('Database=:memory:');
  FDConnection.Connected := True;

  // Cria tabela e insere dados fictícios
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDConnection;
    Qry.ExecSQL(
      'CREATE TABLE participantes (' +
      '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      '  nome VARCHAR(100),' +
      '  email VARCHAR(100),' +
      '  sorteado BOOLEAN DEFAULT 0,' +
      '  data_sorteio DATETIME' +
      ')'
    );

    Qry.SQL.Text := 'INSERT INTO participantes (nome, email) VALUES (:nome, :email)';
    
    Qry.ParamByName('nome').AsString := 'Landerson Gomes';
    Qry.ParamByName('email').AsString := 'landerson@embarcadero.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'Cesar Romero';
    Qry.ParamByName('email').AsString := 'cesar@dextframework.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'Marco Cantu';
    Qry.ParamByName('email').AsString := 'marco.cantu@embarcadero.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'David I';
    Qry.ParamByName('email').AsString := 'david.i@embarcadero.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'Jim McKeeth';
    Qry.ParamByName('email').AsString := 'jim.mckeeth@embarcadero.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'Alister Christie';
    Qry.ParamByName('email').AsString := 'alister@codegearguru.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'Ray Konopka';
    Qry.ParamByName('email').AsString := 'ray@raize.com';
    Qry.ExecSQL;

    Qry.ParamByName('nome').AsString := 'Bruno Fierens';
    Qry.ParamByName('email').AsString := 'bruno@tmssoftware.com';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;

  // Abre tabela no DBGrid
  FDTableParticipantes.Connection := FDConnection;
  FDTableParticipantes.TableName := 'participantes';
  FDTableParticipantes.Active := True;
  DataSource1.DataSet := FDTableParticipantes;
end;

procedure TFormMain.LogMsg(const AMsg: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      MemoLogs.Lines.Add(FormatDateTime('hh:nn:ss', Now) + ' -> ' + AMsg);
    end);
end;

procedure TFormMain.SyncRefreshGrid;
begin
  TThread.Queue(nil,
    procedure
    begin
      if FDTableParticipantes.Active then
      begin
        FDTableParticipantes.Close;
        FDTableParticipantes.Open;
      end;
    end);
end;

procedure TFormMain.BtnStartClick(Sender: TObject);
var
  PortVal: Integer;
begin
  if not TryStrToInt(EditPort.Text, PortVal) then
  begin
    ShowMessage('Porta inválida.');
    Exit;
  end;

  FMCPServer := TMCPServer.Create('vcl-mcp-db-demo', '1.0.0');
  FMCPServer.RegisterProvider(TDatabaseMCPProvider.Create(Self));

  try
    FMCPServer.Run(mtStreamable, 'http://localhost:' + EditPort.Text);
    LogMsg('Servidor MCP rodando em http://localhost:' + EditPort.Text + '/mcp');
    BtnStart.Enabled := False;
    BtnStop.Enabled := True;
    EditPort.Enabled := False;
  except
    on E: Exception do
    begin
      LogMsg('Erro ao iniciar servidor: ' + E.Message);
      FreeAndNil(FMCPServer);
    end;
  end;
end;

procedure TFormMain.BtnStopClick(Sender: TObject);
begin
  if FMCPServer <> nil then
  begin
    FMCPServer.Stop;
    FreeAndNil(FMCPServer);
    LogMsg('Servidor MCP parado.');
    BtnStart.Enabled := True;
    BtnStop.Enabled := False;
    EditPort.Enabled := True;
  end;
end;

function TFormMain.DoListar(const Args: TJsonObject): TMCPToolResult;
var
  Qry: TFDQuery;
  JA: TJsonArray;
  JO: TJsonObject;
begin
  LogMsg('Tool "listar-participantes" invocada.');

  // Como as ferramentas rodam em threads do servidor HTTP, criamos conexões ou queries locais
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDConnection;
    Qry.Open('SELECT id, nome, email, sorteado FROM participantes');

    JA := TJsonArray.Create;
    try
      while not Qry.Eof do
      begin
        JO := JA.AddObject;
        JO.I['id'] := Qry.FieldByName('id').AsInteger;
        JO.S['nome'] := Qry.FieldByName('nome').AsString;
        JO.S['email'] := Qry.FieldByName('email').AsString;
        JO.B['sorteado'] := Qry.FieldByName('sorteado').AsBoolean;
        Qry.Next;
      end;

      Result := TMCPToolResult.Text(JA.ToJSON);
    finally
      JA.Free;
    end;
    LogMsg('Lista de participantes retornada com sucesso.');
  finally
    Qry.Free;
  end;
end;

function TFormMain.DoSortear(const Args: TJsonObject): TMCPToolResult;
var
  Qry: TFDQuery;
  Evento, Nome, Email: string;
  Id: Integer;
begin
  if Args.Contains('evento') then
    Evento := Args.S['evento']
  else
    Evento := 'Embarcadero Conference';
  LogMsg('Tool "sortear-participante" invocada para o evento: ' + Evento);
  
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDConnection;
    Qry.Open('SELECT id, nome, email FROM participantes WHERE sorteado = 0 ORDER BY RANDOM() LIMIT 1');
    
    if Qry.IsEmpty then
    begin
      LogMsg('Aviso: Nenhum participante elegível restante para sorteio.');
      Exit(TMCPToolResult.Error('Nenhum participante disponível para sorteio ou todos já foram sorteados.'));
    end;
      
    Id    := Qry.FieldByName('id').AsInteger;
    Nome  := Qry.FieldByName('nome').AsString;
    Email := Qry.FieldByName('email').AsString;
    
    Qry.Close;
    Qry.SQL.Text := 'UPDATE participantes SET sorteado = 1, data_sorteio = CURRENT_TIMESTAMP WHERE id = :id';
    Qry.ParamByName('id').AsInteger := Id;
    Qry.ExecSQL;
    
    LogMsg('Ganhador sorteado: ' + Nome + ' (' + Email + ')');
    SyncRefreshGrid;
    
    Result := TMCPToolResult.Text(Format('Ganhador sorteado para o evento "%s": %s (%s)', [Evento, Nome, Email]));
  finally
    Qry.Free;
  end;
end;

function TFormMain.DoExecutarSQL(const Args: TJsonObject): TMCPToolResult;
var
  Sql: string;
  Qry: TFDQuery;
  JA: TJsonArray;
  JO: TJsonObject;
  I: Integer;
begin
  Sql := Args.S['sql'];
  LogMsg('Tool "executar-sql" invocada: ' + Sql);

  if Sql = '' then
    Exit(TMCPToolResult.Error('O parâmetro "sql" não pode ser vazio.'));

  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDConnection;
    Qry.SQL.Text := Sql;

    if Sql.Trim.ToLower.StartsWith('select') then
    begin
      Qry.Open;
      JA := TJsonArray.Create;
      try
        while not Qry.Eof do
        begin
          JO := JA.AddObject;
          for I := 0 to Qry.FieldCount - 1 do
          begin
            if Qry.Fields[I].IsNull then
              JO.O[Qry.Fields[I].FieldName] := nil
            else
            begin
              case Qry.Fields[I].DataType of
                ftInteger, ftSmallint, ftWord, ftLargeint:
                  JO.L[Qry.Fields[I].FieldName] := Qry.Fields[I].AsLargeInt;
                ftFloat, ftCurrency, ftBCD, ftFMTBcd:
                  JO.F[Qry.Fields[I].FieldName] := Qry.Fields[I].AsFloat;
                ftBoolean:
                  JO.B[Qry.Fields[I].FieldName] := Qry.Fields[I].AsBoolean;
                else
                  JO.S[Qry.Fields[I].FieldName] := Qry.Fields[I].AsString;
              end;
            end;
          end;
          Qry.Next;
        end;
        Result := TMCPToolResult.Text(JA.ToJSON);
      finally
        JA.Free;
      end;
      LogMsg('SQL SELECT executado com sucesso.');
    end
    else
    begin
      Qry.ExecSQL;
      SyncRefreshGrid;
      Result := TMCPToolResult.Text(Format('Comando SQL executado com sucesso. Linhas afetadas: %d', [Qry.RowsAffected]));
      LogMsg('SQL DML executado com sucesso.');
    end;
  finally
    Qry.Free;
  end;
end;

end.
