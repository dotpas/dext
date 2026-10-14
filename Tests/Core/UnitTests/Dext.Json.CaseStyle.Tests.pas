unit Dext.Json.CaseStyle.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types;

type
  // One class per test: the plan cache is global, so each test must be the
  // first one to serialize its class.

  TCaseStyleCamelFirst = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  TCaseStyleDefaultFirst = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  TCaseStyleEveryStyle = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  TCaseStyleGlobal = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  TCaseStyleJsonName = class
  private
    FCompanyName: string;
    FVatNumber: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
    [JsonName('VAT')]
    property VatNumber: string read FVatNumber write FVatNumber;
  end;

  TCaseStyleChild = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  TCaseStyleParent = class
  private
    FOrderCode: string;
    FCustomer: TCaseStyleChild;
  public
    constructor Create;
    destructor Destroy; override;
    property OrderCode: string read FOrderCode write FOrderCode;
    property Customer: TCaseStyleChild read FCustomer write FCustomer;
  end;

  TCaseStyleRoundTrip = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  TCaseStyleThreaded = class
  private
    FCompanyName: string;
  public
    property CompanyName: string read FCompanyName write FCompanyName;
  end;

  [TestFixture('JSON - the case style of each call, whichever style serialized the class first (#257)')]
  TJsonCaseStyleTests = class
  public
    [Test('CamelCase first, then Unchanged: each call gets its own style')]
    procedure CamelFirst_ThenUnchanged;
    [Test('Unchanged first, then CamelCase: each call gets its own style')]
    procedure UnchangedFirst_ThenCamel;
    [Test('The same class in every case style, twice')]
    procedure EveryStyle_SameClass;
    [Test('The global settings changed between two calls')]
    procedure GlobalSettings_FollowedOnEachCall;
    [Test('[JsonName] wins over every case style')]
    procedure JsonName_WinsOverEveryStyle;
    [Test('A nested object follows the style of the call too')]
    procedure Nested_FollowsTheStyle;
    [Test('Written and read back in the same style')]
    procedure RoundTrip_SnakeAfterUnchanged;
    [Test('Threads with different styles on the same class get their own names')]
    procedure Threads_DifferentStyles;
  end;

implementation

{ TCaseStyleParent }

constructor TCaseStyleParent.Create;
begin
  inherited Create;
  FCustomer := TCaseStyleChild.Create;
end;

destructor TCaseStyleParent.Destroy;
begin
  FCustomer.Free;
  inherited;
end;

type
  /// Serializes the same object many times in one case style.
  TCaseStyleWorker = class(TThread)
  private
    FValue: TCaseStyleThreaded;
    FSettings: TJsonSettings;
    FExpected: string;
    FWrong: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AValue: TCaseStyleThreaded; const ASettings: TJsonSettings;
      const AExpected: string);
    property Wrong: Integer read FWrong;
  end;

constructor TCaseStyleWorker.Create(AValue: TCaseStyleThreaded;
  const ASettings: TJsonSettings; const AExpected: string);
begin
  inherited Create(True);
  FValue := AValue;
  FSettings := ASettings;
  FExpected := AExpected;
end;

procedure TCaseStyleWorker.Execute;
var
  I: Integer;
begin
  for I := 1 to 2000 do
  begin
    if TDextJson.Serialize<TCaseStyleThreaded>(FValue, FSettings) <> FExpected then
      Inc(FWrong);
  end;
end;

{ TJsonCaseStyleTests }

procedure TJsonCaseStyleTests.CamelFirst_ThenUnchanged;
var
  D: TCaseStyleCamelFirst;
begin
  D := TCaseStyleCamelFirst.Create;
  try
    D.CompanyName := 'Acme';
    Should(TDextJson.Serialize<TCaseStyleCamelFirst>(D, TJsonSettings.Default.CamelCase))
      .Be('{"companyName":"Acme"}');
    Should(TDextJson.Serialize<TCaseStyleCamelFirst>(D, TJsonSettings.Default))
      .Be('{"CompanyName":"Acme"}');
    Should(TDextJson.Serialize<TCaseStyleCamelFirst>(D, TJsonSettings.Default.SnakeCase))
      .Be('{"company_name":"Acme"}');
  finally
    D.Free;
  end;
end;

procedure TJsonCaseStyleTests.UnchangedFirst_ThenCamel;
var
  D: TCaseStyleDefaultFirst;
begin
  D := TCaseStyleDefaultFirst.Create;
  try
    D.CompanyName := 'Acme';
    Should(TDextJson.Serialize<TCaseStyleDefaultFirst>(D, TJsonSettings.Default))
      .Be('{"CompanyName":"Acme"}');
    Should(TDextJson.Serialize<TCaseStyleDefaultFirst>(D, TJsonSettings.Default.CamelCase))
      .Be('{"companyName":"Acme"}');
  finally
    D.Free;
  end;
end;

procedure TJsonCaseStyleTests.EveryStyle_SameClass;
var
  D: TCaseStyleEveryStyle;
  Round: Integer;
begin
  D := TCaseStyleEveryStyle.Create;
  try
    D.CompanyName := 'Acme';
    // Twice: the second round is served by the cache
    for Round := 1 to 2 do
    begin
      Should(TDextJson.Serialize<TCaseStyleEveryStyle>(D, TJsonSettings.Default.SnakeCase))
        .Be('{"company_name":"Acme"}');
      Should(TDextJson.Serialize<TCaseStyleEveryStyle>(D, TJsonSettings.Default.CamelCase))
        .Be('{"companyName":"Acme"}');
      Should(TDextJson.Serialize<TCaseStyleEveryStyle>(D, TJsonSettings.Default.PascalCase))
        .Be('{"CompanyName":"Acme"}');
      Should(TDextJson.Serialize<TCaseStyleEveryStyle>(D, TJsonSettings.Default.UnchangedCase))
        .Be('{"CompanyName":"Acme"}');
    end;
  finally
    D.Free;
  end;
end;

procedure TJsonCaseStyleTests.GlobalSettings_FollowedOnEachCall;
var
  D: TCaseStyleGlobal;
  Saved: TJsonSettings;
begin
  Saved := TDextJson.GetDefaultSettings;
  D := TCaseStyleGlobal.Create;
  try
    D.CompanyName := 'Acme';
    TDextJson.SetDefaultSettings(TJsonSettings.Default.CamelCase);
    Should(TDextJson.Serialize<TCaseStyleGlobal>(D)).Be('{"companyName":"Acme"}');
    TDextJson.SetDefaultSettings(TJsonSettings.Default);
    Should(TDextJson.Serialize<TCaseStyleGlobal>(D)).Be('{"CompanyName":"Acme"}');
    TDextJson.SetDefaultSettings(TJsonSettings.Default.SnakeCase);
    Should(TDextJson.Serialize<TCaseStyleGlobal>(D)).Be('{"company_name":"Acme"}');
  finally
    TDextJson.SetDefaultSettings(Saved);
    D.Free;
  end;
end;

procedure TJsonCaseStyleTests.JsonName_WinsOverEveryStyle;
var
  D: TCaseStyleJsonName;
begin
  D := TCaseStyleJsonName.Create;
  try
    D.CompanyName := 'Acme';
    D.VatNumber := 'IT1';
    Should(TDextJson.Serialize<TCaseStyleJsonName>(D, TJsonSettings.Default.CamelCase))
      .Be('{"companyName":"Acme","VAT":"IT1"}');
    Should(TDextJson.Serialize<TCaseStyleJsonName>(D, TJsonSettings.Default.SnakeCase))
      .Be('{"company_name":"Acme","VAT":"IT1"}');
    Should(TDextJson.Serialize<TCaseStyleJsonName>(D, TJsonSettings.Default))
      .Be('{"CompanyName":"Acme","VAT":"IT1"}');
  finally
    D.Free;
  end;
end;

procedure TJsonCaseStyleTests.Nested_FollowsTheStyle;
var
  P: TCaseStyleParent;
begin
  P := TCaseStyleParent.Create;
  try
    P.OrderCode := 'O1';
    P.Customer.CompanyName := 'Acme';
    Should(TDextJson.Serialize<TCaseStyleParent>(P, TJsonSettings.Default.CamelCase))
      .Be('{"orderCode":"O1","customer":{"companyName":"Acme"}}');
    Should(TDextJson.Serialize<TCaseStyleParent>(P, TJsonSettings.Default.SnakeCase))
      .Be('{"order_code":"O1","customer":{"company_name":"Acme"}}');
  finally
    P.Free;
  end;
end;

procedure TJsonCaseStyleTests.RoundTrip_SnakeAfterUnchanged;
var
  D, R: TCaseStyleRoundTrip;
  Json: string;
begin
  D := TCaseStyleRoundTrip.Create;
  try
    D.CompanyName := 'Acme';
    TDextJson.Serialize<TCaseStyleRoundTrip>(D, TJsonSettings.Default);
    Json := TDextJson.Serialize<TCaseStyleRoundTrip>(D, TJsonSettings.Default.SnakeCase);
    Should(Json).Be('{"company_name":"Acme"}');
    R := TDextJson.Deserialize<TCaseStyleRoundTrip>(Json, TJsonSettings.Default.SnakeCase);
    try
      Should(R.CompanyName).Be('Acme');
    finally
      R.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TJsonCaseStyleTests.Threads_DifferentStyles;
var
  D: TCaseStyleThreaded;
  Workers: array[0..3] of TCaseStyleWorker;
  I, Wrong: Integer;
begin
  D := TCaseStyleThreaded.Create;
  try
    D.CompanyName := 'Acme';
    Workers[0] := TCaseStyleWorker.Create(D, TJsonSettings.Default, '{"CompanyName":"Acme"}');
    Workers[1] := TCaseStyleWorker.Create(D, TJsonSettings.Default.CamelCase, '{"companyName":"Acme"}');
    Workers[2] := TCaseStyleWorker.Create(D, TJsonSettings.Default.SnakeCase, '{"company_name":"Acme"}');
    Workers[3] := TCaseStyleWorker.Create(D, TJsonSettings.Default.CamelCase, '{"companyName":"Acme"}');
    try
      for I := 0 to High(Workers) do
        Workers[I].Start;
      Wrong := 0;
      for I := 0 to High(Workers) do
      begin
        Workers[I].WaitFor;
        Inc(Wrong, Workers[I].Wrong);
      end;
      Should(Wrong).Be(0);
    finally
      for I := 0 to High(Workers) do
        Workers[I].Free;
    end;
  finally
    D.Free;
  end;
end;

end.
