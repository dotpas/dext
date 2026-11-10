unit Dext.Core.SmartTypes.Prototype.Tests;

// Prototype is part of Dext.Core.SmartTypes: HaveValue and typed rules must
// work with the Core factory (RTTI only), without the ORM mapping.

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Testing,
  Dext.Core.SmartTypes;

type
  TPrototypeFatura = class
  private
    FNumero: IntType;
    FStatus: StringType;
    FObservacao: string;
  public
    property Numero: IntType read FNumero write FNumero;
    property Status: StringType read FStatus write FStatus;
    property Observacao: string read FObservacao write FObservacao;
  end;

  TPrototypeSemSmartProperty = class
  private
    FNome: string;
  public
    property Nome: string read FNome write FNome;
  end;

  [TestFixture]
  TSmartPrototypeTests = class
  private
    FSavedCreator: TFunc<PTypeInfo, TObject>;
  public
    [Setup]
    procedure UseCoreFactory;
    [TearDown]
    procedure RestoreFactory;
    [Test]
    procedure Core_Prototype_Injects_Property_Name;
    [Test]
    procedure Core_Prototype_Uses_Property_Name_As_Column;
    [Test]
    procedure Core_Prototype_Is_Cached;
    [Test]
    procedure HaveValue_Passes_With_Core_Prototype;
    [Test]
    procedure HaveValue_Fails_With_Different_Value;
    [Test]
    procedure Class_Without_Smart_Properties_Raises;
    [Test]
    procedure HaveProperty_Reads_Smart_Property_Value;
  end;

implementation

{ TSmartPrototypeTests }

procedure TSmartPrototypeTests.UseCoreFactory;
begin
  FSavedCreator := Prototype.Creator;
  Prototype.Creator := nil;
  Prototype.ClearCache;
end;

procedure TSmartPrototypeTests.RestoreFactory;
begin
  Prototype.ClearCache;
  Prototype.Creator := FSavedCreator;
end;

procedure TSmartPrototypeTests.Core_Prototype_Injects_Property_Name;
var
  P: TPrototypeFatura;
  Info: IPropInfo;
begin
  P := Prototype.Entity<TPrototypeFatura>;
  Should(P.Status.IsQueryMode).BeTrue;
  Info := P.Status;
  Should(Info.PropertyName).Be('Status');
  Info := P.Numero;
  Should(Info.PropertyName).Be('Numero');
end;

procedure TSmartPrototypeTests.Core_Prototype_Uses_Property_Name_As_Column;
var
  P: TPrototypeFatura;
  Info: IPropInfo;
begin
  P := Prototype.Entity<TPrototypeFatura>;
  Info := P.Status;
  Should(Info.ColumnName).Be('Status');
end;

procedure TSmartPrototypeTests.Core_Prototype_Is_Cached;
begin
  Should(Prototype.Entity(TPrototypeFatura.ClassInfo) =
    Prototype.Entity(TPrototypeFatura.ClassInfo)).BeTrue;
end;

procedure TSmartPrototypeTests.HaveValue_Passes_With_Core_Prototype;
var
  P, Fatura: TPrototypeFatura;
begin
  P := Prototype.Entity<TPrototypeFatura>;
  Fatura := TPrototypeFatura.Create;
  try
    Fatura.Status := 'PAGA';
    Fatura.Numero := 105;
    Should(Fatura).HaveValue(P.Status, 'PAGA');
    Should(Fatura).HaveValue(P.Numero, 105);
  finally
    Fatura.Free;
  end;
end;

procedure TSmartPrototypeTests.HaveValue_Fails_With_Different_Value;
var
  P, Fatura: TPrototypeFatura;
begin
  P := Prototype.Entity<TPrototypeFatura>;
  Fatura := TPrototypeFatura.Create;
  try
    Fatura.Status := 'EMITIDA';
    Should(
      procedure
      begin
        Should(Fatura).HaveValue(P.Status, 'PAGA');
      end).Throw<EAssertionFailed>
      .AndAlso.ThrowWithMessageContaining('but was "EMITIDA"');
  finally
    Fatura.Free;
  end;
end;

procedure TSmartPrototypeTests.Class_Without_Smart_Properties_Raises;
begin
  Should(
    procedure
    begin
      Prototype.Entity<TPrototypeSemSmartProperty>;
    end).Throw<Exception>;
end;

procedure TSmartPrototypeTests.HaveProperty_Reads_Smart_Property_Value;
var
  Fatura: TPrototypeFatura;
begin
  Fatura := TPrototypeFatura.Create;
  try
    Fatura.Status := 'PAGA';
    Fatura.Numero := 105;
    Should(TObject(Fatura)).HaveProperty('Status').WhichString.Be('PAGA');
    Should(TObject(Fatura)).HaveProperty('Numero').WhichInteger.Be(105);
  finally
    Fatura.Free;
  end;
end;

end.
