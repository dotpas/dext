{***************************************************************************}
{                                                                           }
{           Dext Framework - Mocks, AutoMocker and Test DI regressions      }
{                                                                           }
{  Every check here sets a non-zero exit code when it fails, so the suite   }
{  breaks the build instead of printing FAIL and exiting green.             }
{                                                                           }
{***************************************************************************}
program TestMockRegressions;

{$APPTYPE CONSOLE}

uses
  Dext.MM,
  Dext.Utils,
  System.Rtti,
  System.SysUtils,
  System.TypInfo,
  Dext.Events.Interfaces,
  Dext.Interception,
  Dext.Mocks,
  Dext.Mocks.Matching,
  Dext.Mocks.Auto,
  Dext.Testing.DI;

type
  {$M+}
  IGatewayCobranca = interface
    ['{5B0C2E71-3A4D-4F7B-9C1E-8A2D6F4B1C30}']
    function Autorizar(const Documento: string; Valor: Integer): string;
    procedure Estornar(const Documento: string);
  end;

  ICalculo = interface
    ['{7D1E4A92-6B5C-4E8F-A2D3-1C9B8E7F6A41}']
    function Somar(A, B: Integer): Integer;
  end;

  ISaldo = interface
    ['{2F8A6C13-9D4E-4B7A-8E5F-3C1D2B4A6E52}']
    function Saldo: Currency;
    function Total: Int64;
  end;

  IServicoCobranca = interface
    ['{9E3B7D24-1F6A-4C8B-B4E7-5D2A3C1F8B63}']
    function Cobrar(const Documento: string; Valor: Integer): string;
  end;
  {$M-}

  ISemRtti = interface
    ['{4C6D8E35-2A7B-4D9C-A5F8-6E3B4D2C9A74}']
    procedure Fazer;
  end;

  TServicoCobranca = class(TInterfacedObject, IServicoCobranca)
  private
    FGateway: IGatewayCobranca;
  public
    constructor Create(const Gateway: IGatewayCobranca);
    function Cobrar(const Documento: string; Valor: Integer): string;
  end;

  TCalculadoraTaxa = class
  public
    function Taxa: Currency; virtual;
    function Dobro(X: Integer): Integer; virtual;
  end;

  TDependeSemRtti = class
  public
    constructor Create(const Dep: ISemRtti);
  end;

  TComNome = class
  private
    FGateway: IGatewayCobranca;
    FNome: string;
  public
    constructor Create(const Gateway: IGatewayCobranca; const Nome: string);
    property Gateway: IGatewayCobranca read FGateway;
    property Nome: string read FNome;
  end;

constructor TServicoCobranca.Create(const Gateway: IGatewayCobranca);
begin
  inherited Create;
  FGateway := Gateway;
end;

function TServicoCobranca.Cobrar(const Documento: string; Valor: Integer): string;
begin
  if FGateway = nil then
    raise Exception.Create('gateway ausente');
  Result := FGateway.Autorizar(Documento, Valor);
end;

function TCalculadoraTaxa.Taxa: Currency;
begin
  Result := 15;
end;

function TCalculadoraTaxa.Dobro(X: Integer): Integer;
begin
  Result := X * 2;
end;

constructor TDependeSemRtti.Create(const Dep: ISemRtti);
begin
  inherited Create;
end;

constructor TComNome.Create(const Gateway: IGatewayCobranca; const Nome: string);
begin
  inherited Create;
  FGateway := Gateway;
  FNome := Nome;
end;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(Condition: Boolean; const Name: string; const Detail: string = '');
begin
  Inc(Checks);
  if Condition then
    WriteLn('  PASS: ', Name)
  else
  begin
    Inc(Failures);
    if Detail <> '' then
      WriteLn('  FAIL: ', Name, ' -> ', Detail)
    else
      WriteLn('  FAIL: ', Name);
  end;
end;

procedure CheckRaises(const Action: TProc; ExpectedClass: ExceptClass; const Name: string);
begin
  try
    Action();
    Check(False, Name, 'no exception was raised');
  except
    on E: Exception do
      Check(E.InheritsFrom(ExpectedClass), Name, E.ClassName + ': ' + E.Message);
  end;
end;

procedure CheckNoRaise(const Action: TProc; const Name: string);
begin
  try
    Action();
    Check(True, Name);
  except
    on E: Exception do
      Check(False, Name, E.ClassName + ': ' + E.Message);
  end;
end;

procedure TestSetupMixingLiteralAndMatcher;
var
  Gateway: Mock<IGatewayCobranca>;
begin
  WriteLn('Setup mixing a literal and an Arg matcher');
  Gateway := Mock<IGatewayCobranca>.Create;
  Gateway.Setup.Returns('AUT-1').When.Autorizar('12345678000199', Arg.Any<Integer>);
  Gateway.Setup.Returns('AUT-2').When.Autorizar(Arg.StartsWith('99'), 950);

  Check(Gateway.Instance.Autorizar('12345678000199', 950) = 'AUT-1', 'literal first, matcher second matches');
  Check(Gateway.Instance.Autorizar('00000000000100', 950) = '', 'literal first does not match another document');
  Check(Gateway.Instance.Autorizar('99000000000100', 950) = 'AUT-2', 'matcher first, literal second matches');
  Check(Gateway.Instance.Autorizar('99000000000100', 951) = '', 'matcher first does not match another value');
end;

procedure TestAmbiguousMatcherIsReported;
var
  Calculo: Mock<ICalculo>;
begin
  WriteLn('Ambiguous matcher position is reported');
  Calculo := Mock<ICalculo>.Create;
  CheckRaises(
    procedure
    begin
      Calculo.Setup.Returns(1).When.Somar(0, Arg.Any<Integer>);
    end, EMockException, 'literal default value next to a matcher of the same type raises');
  CheckNoRaise(
    procedure
    begin
      Calculo.Setup.Returns(7).When.Somar(Arg.IsEqual<Integer>(0), Arg.Any<Integer>);
    end, 'Arg.IsEqual(0) resolves the ambiguity');
  Check(Calculo.Instance.Somar(0, 5) = 7, 'disambiguated setup matches');
end;

procedure TestReceivedComparesLiteralArguments;
var
  Gateway: Mock<IGatewayCobranca>;
begin
  WriteLn('Received compares literal arguments');
  Gateway := Mock<IGatewayCobranca>.Create;
  Gateway.Instance.Autorizar('12345678000199', 950);

  CheckNoRaise(
    procedure
    begin
      Gateway.Received(Times.Once).Autorizar('12345678000199', 950);
    end, 'same literals are received');
  CheckRaises(
    procedure
    begin
      Gateway.Received.Autorizar('12345678000270', 950);
    end, EMockException, 'another document was not received');
  CheckRaises(
    procedure
    begin
      Gateway.Received.Autorizar('12345678000199', 951);
    end, EMockException, 'another value was not received');
  CheckNoRaise(
    procedure
    begin
      Gateway.Received(Times.Once).Autorizar('12345678000199', Arg.Any<Integer>);
    end, 'literal plus matcher is received');
  CheckRaises(
    procedure
    begin
      Gateway.Received.Autorizar('12345678000270', Arg.Any<Integer>);
    end, EMockException, 'literal plus matcher rejects another document');
  CheckNoRaise(
    procedure
    begin
      Gateway.DidNotReceive.Autorizar('12345678000270', 950);
    end, 'DidNotReceive with another document passes');
end;

procedure TestVerifyChecksEverySetup;
var
  Gateway: Mock<IGatewayCobranca>;
begin
  WriteLn('Verify checks that every setup was exercised');
  Gateway := Mock<IGatewayCobranca>.Create(TMockBehavior.Strict);
  Gateway.Setup.Returns('AUT').When.Autorizar(Arg.Any<string>, Arg.Any<Integer>);
  Gateway.Setup.Executes(procedure(Inv: IInvocation) begin end).When.Estornar(Arg.Any<string>);

  Gateway.Instance.Autorizar('105', 950);
  CheckRaises(
    procedure
    begin
      Gateway.Verify;
    end, EMockException, 'Verify fails while Estornar was never called');

  Gateway.Instance.Estornar('105');
  CheckNoRaise(
    procedure
    begin
      Gateway.Verify;
    end, 'Verify passes once every setup was exercised');

  // The Executes closure shares this routine's frame, which holds Gateway:
  // Reset drops the setup and breaks the reference cycle.
  Gateway.Reset;
end;

procedure TestCallsBaseForUnconfiguredMembers;
var
  Calculadora: Mock<TCalculadoraTaxa>;
begin
  WriteLn('CallsBaseForUnconfiguredMembers runs the original implementation');
  Calculadora := Mock<TCalculadoraTaxa>.Create.CallsBaseForUnconfiguredMembers;
  Calculadora.Setup.Returns(99).When.Dobro(Arg.Any<Integer>);

  Check(Calculadora.Instance.Taxa = 15, 'unconfigured member runs the base class',
    CurrToStr(Calculadora.Instance.Taxa));
  Check(Calculadora.Instance.Dobro(4) = 99, 'configured member returns the setup value');
end;

procedure TestReturnValueIsCoerced;
var
  Saldo: Mock<ISaldo>;
begin
  WriteLn('Return value is coerced to the method return type');
  Saldo := Mock<ISaldo>.Create;
  Saldo.Setup.Returns(1250.5).When.Saldo;
  Saldo.Setup.Returns(42).When.Total;

  CheckNoRaise(
    procedure
    begin
      Check(Saldo.Instance.Saldo = 1250.5, 'Double setup returns as Currency');
    end, 'Currency method with a Double setup does not raise');
  CheckNoRaise(
    procedure
    begin
      Check(Saldo.Instance.Total = 42, 'Integer setup returns as Int64');
    end, 'Int64 method with an Integer setup does not raise');
end;

procedure TestServiceProviderInjectsMocks;
var
  Provider: TTestServiceProvider;
  Gateway: Mock<IGatewayCobranca>;
  Servico: IServicoCobranca;
  Resultado: string;
begin
  WriteLn('TTestServiceProvider injects mocks into services built by the container');
  Gateway := Mock<IGatewayCobranca>.Create;
  Gateway.Setup.Returns('AUT-DI').When.Autorizar(Arg.Any<string>, Arg.Any<Integer>);

  Provider := TTestServiceProvider.Create;
  try
    Provider.AddTransient<IServicoCobranca, TServicoCobranca>;
    Provider.AddMock<IGatewayCobranca>(Gateway);
    Resultado := '';
    CheckNoRaise(
      procedure
      begin
        Servico := Provider.GetMockOrService<IServicoCobranca>;
        Resultado := Servico.Cobrar('105', 950);
      end, 'service built by the container receives the mock');
    Check(Resultado = 'AUT-DI', 'mock setup reaches the service', Resultado);
    Servico := nil;
  finally
    Provider.Free;
  end;
end;

procedure TestServiceProviderReplace;
var
  Provider: TTestServiceProvider;
  Real, Substituto: Mock<IGatewayCobranca>;
  Servico: IServicoCobranca;
begin
  WriteLn('TTestServiceProvider.Replace wins over an earlier registration');
  Real := Mock<IGatewayCobranca>.Create;
  Real.Setup.Returns('REAL').When.Autorizar(Arg.Any<string>, Arg.Any<Integer>);
  Substituto := Mock<IGatewayCobranca>.Create;
  Substituto.Setup.Returns('SUBSTITUTO').When.Autorizar(Arg.Any<string>, Arg.Any<Integer>);

  Provider := TTestServiceProvider.Create;
  try
    Provider.AddTransient<IServicoCobranca, TServicoCobranca>;
    Provider.AddMock<IGatewayCobranca>(Real);
    Provider.Replace<IGatewayCobranca>(Substituto);
    Servico := Provider.GetMockOrService<IServicoCobranca>;
    Check(Servico.Cobrar('105', 950) = 'SUBSTITUTO', 'replacement is the one injected');
    Servico := nil;
  finally
    Provider.Free;
  end;
end;

procedure TestAutoMockerWithoutRtti;
var
  Mocker: TAutoMocker;
begin
  WriteLn('TAutoMocker reports an interface without RTTI instead of crashing');
  Mocker := TAutoMocker.Create;
  try
    CheckRaises(
      procedure
      begin
        Mocker.CreateInstance<TDependeSemRtti>.Free;
      end, EMockException, 'interface without {$M+} raises EMockException');
  finally
    Mocker.Free;
  end;
end;

procedure TestAutoMockerNonOrdinalParameters;
var
  Mocker: TAutoMocker;
  Instancia: TComNome;
begin
  WriteLn('TAutoMocker fills non-ordinal constructor parameters with defaults');
  Mocker := TAutoMocker.Create;
  try
    Instancia := nil;
    CheckNoRaise(
      procedure
      begin
        Instancia := Mocker.CreateInstance<TComNome>;
      end, 'string parameter does not raise');
    if Instancia <> nil then
    try
      Check(Instancia.Gateway <> nil, 'interface parameter receives a mock');
      Check(Instancia.Nome = '', 'string parameter receives an empty string');
      Mocker.GetMock<IGatewayCobranca>.Setup.Returns('AUTO').When.Autorizar(Arg.Any<string>, Arg.Any<Integer>);
      Check(Instancia.Gateway.Autorizar('105', 950) = 'AUTO', 'GetMock configures the injected mock');
    finally
      Instancia.Free;
    end;
  finally
    Mocker.Free;
  end;
end;

procedure TestEventBusCanBeMocked;
var
  Bus: Mock<IEventBus>;
begin
  WriteLn('IEventBus can be mocked and verified');
  Bus := Mock<IEventBus>.Create;
  Bus.Instance.DispatchBackground(TypeInfo(Integer), TValue.From<Integer>(105));
  CheckNoRaise(
    procedure
    begin
      Bus.Received(Times.Once).DispatchBackground(Arg.Any<PTypeInfo>, Arg.Any<TValue>);
    end, 'DispatchBackground was received');
end;

procedure Run(const Test: TProc; const Name: string);
begin
  try
    Test();
  except
    on E: Exception do
    begin
      Inc(Failures);
      WriteLn('  FAIL: ', Name, ' crashed -> ', E.ClassName, ': ', E.Message);
    end;
  end;
  WriteLn;
end;

begin
  SetConsoleCharSet;
  Run(TestSetupMixingLiteralAndMatcher, 'TestSetupMixingLiteralAndMatcher');
  Run(TestAmbiguousMatcherIsReported, 'TestAmbiguousMatcherIsReported');
  Run(TestReceivedComparesLiteralArguments, 'TestReceivedComparesLiteralArguments');
  Run(TestVerifyChecksEverySetup, 'TestVerifyChecksEverySetup');
  Run(TestCallsBaseForUnconfiguredMembers, 'TestCallsBaseForUnconfiguredMembers');
  Run(TestReturnValueIsCoerced, 'TestReturnValueIsCoerced');
  Run(TestServiceProviderInjectsMocks, 'TestServiceProviderInjectsMocks');
  Run(TestServiceProviderReplace, 'TestServiceProviderReplace');
  Run(TestAutoMockerWithoutRtti, 'TestAutoMockerWithoutRtti');
  Run(TestAutoMockerNonOrdinalParameters, 'TestAutoMockerNonOrdinalParameters');
  Run(TestEventBusCanBeMocked, 'TestEventBusCanBeMocked');

  WriteLn(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures > 0 then
    ExitCode := 1;
end.
