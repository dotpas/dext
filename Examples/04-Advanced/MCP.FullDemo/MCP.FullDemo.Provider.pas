{***************************************************************************}
{                                                                           }
{  MCP Full Demo - Provider RTTI                                            }
{                                                                           }
{  Demonstra os três pilares do Dext MCP 2025-03-26:                       }
{                                                                           }
{    TOOLS    - lógica invocável pelo LLM                                  }
{    RESOURCES - documentos/dados que o LLM pode ler                       }
{    PROMPTS  - templates de mensagens reutilizáveis                       }
{                                                                           }
{  Usando o padrão RTTI (provider class com atributos):                    }
{    - [MCPTool]      marca um método como tool                            }
{    - [MCPParam]     descreve parâmetros de entrada                       }
{    - [MCPResource]  expõe dados como resource                            }
{    - [MCPPrompt]    cria template de prompt                              }
{                                                                           }
{***************************************************************************}
unit MCP.FullDemo.Provider;

interface

uses
  System.SysUtils,
  DextJsonDataObjects,
  Dext.AI.MCP.Attributes,
  Dext.AI.MCP.Protocol,
  Dext.AI.MCP.Types,
  Dext.AI.MCP.Tools;

// ---------------------------------------------------------------------------
// TDemoProvider
//
// Um único provider que implementa Tools + Resources + Prompts.
// Na prática você pode separar em providers por domínio:
//   TClienteProvider, TFinanceiroProvider, TRelatorioProvider, etc.
// ---------------------------------------------------------------------------

type
  TDemoProvider = class(TMCPToolProvider)
  public

    // =========================================================================
    // TOOLS - operações que o LLM pode executar
    // =========================================================================

    [MCPTool('calcular-desconto',
      'Calcula o desconto progressivo sobre um valor de venda. ' +
      'Regras: até R$100 = 5%, R$101-500 = 10%, R$501-1000 = 15%, acima = 20%. ' +
      'Retorna o valor com desconto e o percentual aplicado.')]
    [MCPParam('valor', 'Valor bruto da venda em reais', ptNumber)]
    function CalcularDesconto(const Args: TJsonObject): TMCPToolResult; virtual;

    [MCPTool('validar-cpf',
      'Valida se um CPF é matematicamente correto (dígitos verificadores). ' +
      'Não consulta base de dados - apenas valida o formato e dígitos. ' +
      'Aceita CPF com ou sem pontuação (999.999.999-99 ou 99999999999).')]
    [MCPParam('cpf', 'CPF a validar (com ou sem formatação)', ptString)]
    function ValidarCPF(const Args: TJsonObject): TMCPToolResult; virtual;

    [MCPTool('calcular-imc',
      'Calcula o IMC (Índice de Massa Corporal) com classificação OMS. ' +
      'Classificações: Abaixo do peso (<18.5), Normal (18.5-24.9), ' +
      'Sobrepeso (25-29.9), Obesidade grau I (30-34.9), ' +
      'Obesidade grau II (35-39.9), Obesidade grau III (>=40).')]
    [MCPParam('peso', 'Peso em kg (ex: 75.5)', ptNumber)]
    [MCPParam('altura', 'Altura em metros (ex: 1.72)', ptNumber)]
    function CalcularIMC(const Args: TJsonObject): TMCPToolResult; virtual;

    [MCPTool('gerar-relatorio-texto',
      'Gera um relatório de exemplo com múltiplos conteúdos. ' +
      'Demonstra o uso de TMCPToolResult.AddContent para resultados ricos.')]
    [MCPParam('titulo', 'Título do relatório', ptString)]
    [MCPParam('linhas', 'Número de linhas de dados de exemplo', ptInteger, False)]
    function GerarRelatorio(const Args: TJsonObject): TMCPToolResult; virtual;

    // =========================================================================
    // RESOURCES - dados que o LLM pode consultar por URI
    // =========================================================================

    [MCPResource('config://demo', 'Configuração Demo',
      'Configurações atuais do servidor de demonstração', 'application/json')]
    function ReadConfig(const AUri: string): TMCPResourceContents; virtual;

    [MCPResource('docs://regras-desconto', 'Regras de Desconto',
      'Tabela completa de regras de desconto por faixa de valor', 'text/plain')]
    function ReadRegrasDesconto(const AUri: string): TMCPResourceContents; virtual;

    // =========================================================================
    // PROMPTS - templates de mensagens reutilizáveis
    // =========================================================================

    [MCPPrompt('analise-venda',
      'Analisa os dados de uma venda e sugere ações comerciais')]
    [MCPPromptArg('valor', 'Valor da venda em reais')]
    [MCPPromptArg('produto', 'Nome do produto ou serviço')]
    [MCPPromptArg('cliente', 'Nome do cliente', {required=}False)]
    function AnaliseVenda(const Args: TJsonObject): TMCPPromptResult; virtual;

    [MCPPrompt('revisao-codigo-delphi',
      'Template para revisão de código Delphi com foco em qualidade e performance')]
    [MCPPromptArg('codigo', 'Código Delphi para revisar')]
    [MCPPromptArg('contexto', 'Contexto ou objetivo do código', {required=}False)]
    function RevisaoCodigoDelphi(const Args: TJsonObject): TMCPPromptResult; virtual;
  end;

implementation

uses
  System.Math,
  System.NetEncoding;

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

function TDemoProvider.CalcularDesconto(
  const Args: TJsonObject): TMCPToolResult;
var
  Valor, Desconto, ValorFinal: Double;
  Percentual: Integer;
  Msg: string;
begin
  Valor := Args.F['valor'];

  if Valor <= 0 then
    Exit(TMCPToolResult.Error('Valor deve ser maior que zero'));

  if Valor <= 100 then
    Percentual := 5
  else if Valor <= 500 then
    Percentual := 10
  else if Valor <= 1000 then
    Percentual := 15
  else
    Percentual := 20;

  Desconto   := Valor * Percentual / 100;
  ValorFinal := Valor - Desconto;

  Msg := Format(
    'Valor bruto: R$ %.2f' + sLineBreak +
    'Desconto:    %d%% (R$ %.2f)' + sLineBreak +
    'Valor final: R$ %.2f',
    [Valor, Percentual, Desconto, ValorFinal]);

  Result := TMCPToolResult.Text(Msg);
end;

function TDemoProvider.ValidarCPF(const Args: TJsonObject): TMCPToolResult;
var
  CPF: string;
  Digits: string;
  I, Sum, Rem: Integer;

  function Digit(const S: string; Index: Integer): Integer;
  begin
    Result := StrToInt(S[Index]);
  end;

begin
  CPF := Args.S['cpf'].Trim;

  // Remove formatting
  Digits := '';
  for I := 1 to Length(CPF) do
    if CharInSet(CPF[I], ['0'..'9']) then
      Digits := Digits + CPF[I];

  if Length(Digits) <> 11 then
    Exit(TMCPToolResult.Error(
      Format('CPF inválido: "%s" - deve ter 11 dígitos', [CPF])));

  // Check all-same-digit
  if (Copy(Digits, 2, 10) = StringOfChar(Digits[1], 10)) then
    Exit(TMCPToolResult.Error(
      Format('CPF inválido: "%s" - dígitos todos iguais', [CPF])));

  // Verify first check digit
  Sum := 0;
  for I := 1 to 9 do
    Sum := Sum + Digit(Digits, I) * (11 - I);
  Rem := (Sum * 10) mod 11;
  if Rem = 10 then Rem := 0;
  if Rem <> Digit(Digits, 10) then
    Exit(TMCPToolResult.Error(
      Format('CPF inválido: "%s" - primeiro dígito verificador incorreto', [CPF])));

  // Verify second check digit
  Sum := 0;
  for I := 1 to 10 do
    Sum := Sum + Digit(Digits, I) * (12 - I);
  Rem := (Sum * 10) mod 11;
  if Rem = 10 then Rem := 0;
  if Rem <> Digit(Digits, 11) then
    Exit(TMCPToolResult.Error(
      Format('CPF inválido: "%s" - segundo dígito verificador incorreto', [CPF])));

  Result := TMCPToolResult.Text(
    Format('CPF válido: %s.%s.%s-%s',
      [Copy(Digits, 1, 3), Copy(Digits, 4, 3),
       Copy(Digits, 7, 3), Copy(Digits, 10, 2)]));
end;

function TDemoProvider.CalcularIMC(const Args: TJsonObject): TMCPToolResult;
var
  Peso, Altura, IMC: Double;
  Classificacao: string;
begin
  Peso   := Args.F['peso'];
  Altura := Args.F['altura'];

  if (Peso <= 0) or (Altura <= 0) then
    Exit(TMCPToolResult.Error('Peso e altura devem ser maiores que zero'));

  if (Altura > 3) then
    Exit(TMCPToolResult.Error(
      'Altura deve ser em metros (ex: 1.72), não em centímetros'));

  IMC := Peso / (Altura * Altura);

  if IMC < 18.5 then
    Classificacao := 'Abaixo do peso'
  else if IMC < 25 then
    Classificacao := 'Peso normal'
  else if IMC < 30 then
    Classificacao := 'Sobrepeso'
  else if IMC < 35 then
    Classificacao := 'Obesidade grau I'
  else if IMC < 40 then
    Classificacao := 'Obesidade grau II'
  else
    Classificacao := 'Obesidade grau III';

  Result := TMCPToolResult.Text(
    Format(
      'Peso: %.1f kg | Altura: %.2f m' + sLineBreak +
      'IMC: %.1f' + sLineBreak +
      'Classificação OMS: %s',
      [Peso, Altura, IMC, Classificacao]));
end;

function TDemoProvider.GerarRelatorio(const Args: TJsonObject): TMCPToolResult;
var
  Titulo: string;
  Linhas, I: Integer;
  Header, Row, Footer: string;
begin
  if Args.Contains('titulo') then
    Titulo := Args.S['titulo']
  else
    Titulo := 'Relatório Demo';
  if Args.Contains('linhas') then
    Linhas := Args.I['linhas']
  else
    Linhas := 3;
  Linhas := Max(1, Min(Linhas, 10)); // clamp 1..10

  // First content: header
  Header :=
    '=== ' + Titulo + ' ===' + sLineBreak +
    'Gerado em: ' + FormatDateTime('dd/mm/yyyy hh:nn:ss', Now) + sLineBreak +
    StringOfChar('-', 40);

  Result := TMCPToolResult.Text(Header);

  // Additional content items: data rows
  for I := 1 to Linhas do
  begin
    Row := Format(
      'Linha %d | Produto %s | R$ %.2f | Qtd: %d',
      [I, Chr(64 + I), Random(10000) / 100, Random(100) + 1]);
    Result.AddContent(TMCPContent.Text(Row));
  end;

  // Footer
  Footer := StringOfChar('-', 40) + sLineBreak +
    Format('Total de linhas: %d | Status: OK', [Linhas]);
  Result.AddContent(TMCPContent.Text(Footer));
end;

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

function TDemoProvider.ReadConfig(
  const AUri: string): TMCPResourceContents;
const
  Config =
    '{' + sLineBreak +
    '  "servidor": "MCP Full Demo",' + sLineBreak +
    '  "versao": "1.0.0",' + sLineBreak +
    '  "protocolo": "MCP 2025-03-26",' + sLineBreak +
    '  "transporte": "HTTP Streamable",' + sLineBreak +
    '  "http_stack": "Indy TIdHTTPServer",' + sLineBreak +
    '  "capacidades": ["tools", "resources", "prompts"],' + sLineBreak +
    '  "tools_registradas": 4,' + sLineBreak +
    '  "resources_registradas": 2,' + sLineBreak +
    '  "prompts_registrados": 2' + sLineBreak +
    '}';
begin
  Result := TMCPResourceContents.TextResource(AUri, Config, 'application/json');
end;

function TDemoProvider.ReadRegrasDesconto(
  const AUri: string): TMCPResourceContents;
const
  Regras =
    'TABELA DE DESCONTOS PROGRESSIVOS' + sLineBreak +
    '================================' + sLineBreak +
    sLineBreak +
    'Faixa de Valor        Desconto' + sLineBreak +
    '--------------------  --------' + sLineBreak +
    'Até R$ 100,00          5%' + sLineBreak +
    'R$ 101,00 - R$ 500,00  10%' + sLineBreak +
    'R$ 501,00 - R$1000,00  15%' + sLineBreak +
    'Acima de R$1000,00     20%' + sLineBreak +
    sLineBreak +
    'Regras adicionais:' + sLineBreak +
    '- Desconto aplicado sobre o valor bruto' + sLineBreak +
    '- Não cumulativo com outras promoções' + sLineBreak +
    '- Válido para vendas à vista';
begin
  Result := TMCPResourceContents.TextResource(AUri, Regras, 'text/plain');
end;

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

function TDemoProvider.AnaliseVenda(
  const Args: TJsonObject): TMCPPromptResult;
var
  Valor, Produto, Cliente, Prompt: string;
begin
  if Args.Contains('valor') then
    Valor := Args.S['valor']
  else
    Valor := '0';
  Produto := Args.S['produto'];
  if Args.Contains('cliente') then
    Cliente := Args.S['cliente']
  else
    Cliente := 'cliente';

  Prompt :=
    'Analise a seguinte venda e sugira ações comerciais:' + sLineBreak +
    sLineBreak +
    'Produto: ' + Produto + sLineBreak +
    'Valor: R$ ' + Valor + sLineBreak +
    'Cliente: ' + Cliente + sLineBreak +
    sLineBreak +
    'Por favor:' + sLineBreak +
    '1. Avalie se o valor está adequado ao mercado' + sLineBreak +
    '2. Sugira o desconto apropriado conforme nossa tabela progressiva' + sLineBreak +
    '3. Indique oportunidades de cross-sell ou up-sell' + sLineBreak +
    '4. Proponha uma abordagem personalizada para o cliente';

  Result := TMCPPromptResult.Create('Análise de venda');
  Result.AddMessage(TMCPPromptMessage.User(Prompt));
end;

function TDemoProvider.RevisaoCodigoDelphi(
  const Args: TJsonObject): TMCPPromptResult;
var
  Codigo, Contexto, Prompt: string;
begin
  Codigo   := Args.S['codigo'];
  Contexto := Args.S['contexto'];

  Prompt :=
    'Faça uma revisão detalhada do código Delphi abaixo.' + sLineBreak +
    sLineBreak;

  if Contexto <> '' then
    Prompt := Prompt + 'Contexto: ' + Contexto + sLineBreak + sLineBreak;

  Prompt := Prompt +
    'Verifique e comente sobre:' + sLineBreak +
    '- Nomenclatura e convenções Delphi' + sLineBreak +
    '- Gerenciamento de memória (try/finally, Free)' + sLineBreak +
    '- Tratamento de exceções' + sLineBreak +
    '- Thread safety' + sLineBreak +
    '- Performance e uso de recursos' + sLineBreak +
    '- Boas práticas do Dext Framework (se aplicável)' + sLineBreak +
    sLineBreak +
    '```delphi' + sLineBreak +
    Codigo + sLineBreak +
    '```';

  Result := TMCPPromptResult.Create('Revisão de código Delphi');
  Result.AddMessage(TMCPPromptMessage.User(Prompt));
end;

end.
