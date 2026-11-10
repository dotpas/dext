unit Dext.Testing.SmartDates.Tests;

// Should must accept every date/time Smart Property and Nullable date type
// directly, without casting to TDateTime.

interface

uses
  System.SysUtils,
  System.DateUtils,
  Dext.Testing,
  Dext.Core.SmartTypes,
  Dext.Types.Nullable;

type
  TSmartAgenda = class
  private
    FCriadoEm: DateTimeType;
    FVencimento: DateType;
    FHorario: TimeType;
  public
    property CriadoEm: DateTimeType read FCriadoEm write FCriadoEm;
    property Vencimento: DateType read FVencimento write FVencimento;
    property Horario: TimeType read FHorario write FHorario;
  end;

  [TestFixture]
  TSmartDateAssertionTests = class
  public
    [Test]
    procedure Should_Accepts_DateTimeType;
    [Test]
    procedure Should_Accepts_DateType;
    [Test]
    procedure Should_Accepts_TimeType;
    [Test]
    procedure Should_DateType_Fails_With_Different_Date;
    [Test]
    procedure Should_Accepts_Nullable_Date_Types;
    [Test]
    procedure Should_Nullable_Date_Fails_When_Null;
    [Test]
    procedure ShouldDate_Accepts_DateTimeType;
  end;

implementation

{ TSmartDateAssertionTests }

procedure TSmartDateAssertionTests.Should_Accepts_DateTimeType;
var
  A: TSmartAgenda;
begin
  A := TSmartAgenda.Create;
  try
    A.CriadoEm := EncodeDateTime(2026, 11, 9, 14, 30, 0, 0);
    Should(A.CriadoEm).Be(EncodeDateTime(2026, 11, 9, 14, 30, 0, 0));
    Should(A.CriadoEm).BeAfter(EncodeDate(2026, 11, 9));
  finally
    A.Free;
  end;
end;

procedure TSmartDateAssertionTests.Should_Accepts_DateType;
var
  A: TSmartAgenda;
begin
  A := TSmartAgenda.Create;
  try
    A.Vencimento := EncodeDate(2026, 12, 10);
    Should(A.Vencimento).Be(EncodeDate(2026, 12, 10));
    Should(A.Vencimento).BeBefore(EncodeDate(2026, 12, 11));
  finally
    A.Free;
  end;
end;

procedure TSmartDateAssertionTests.Should_Accepts_TimeType;
var
  A: TSmartAgenda;
begin
  A := TSmartAgenda.Create;
  try
    A.Horario := EncodeTime(9, 15, 0, 0);
    Should(A.Horario).Be(EncodeTime(9, 15, 0, 0));
  finally
    A.Free;
  end;
end;

procedure TSmartDateAssertionTests.Should_DateType_Fails_With_Different_Date;
var
  A: TSmartAgenda;
begin
  A := TSmartAgenda.Create;
  try
    A.Vencimento := EncodeDate(2026, 12, 10);
    Should(
      procedure
      begin
        Should(A.Vencimento).Be(EncodeDate(2026, 12, 11));
      end).Throw<EAssertionFailed>;
  finally
    A.Free;
  end;
end;

procedure TSmartDateAssertionTests.Should_Accepts_Nullable_Date_Types;
var
  Quando: Nullable<TDateTime>;
  Dia: Nullable<TDate>;
  Hora: Nullable<TTime>;
begin
  Quando := EncodeDateTime(2026, 11, 9, 8, 0, 0, 0);
  Dia := TDate(EncodeDate(2026, 11, 9));
  Hora := TTime(EncodeTime(8, 0, 0, 0));
  Should(Quando).Be(EncodeDateTime(2026, 11, 9, 8, 0, 0, 0));
  Should(Dia).Be(EncodeDate(2026, 11, 9));
  Should(Hora).Be(EncodeTime(8, 0, 0, 0));
end;

procedure TSmartDateAssertionTests.Should_Nullable_Date_Fails_When_Null;
var
  Dia: Nullable<TDate>;
begin
  Should(
    procedure
    begin
      Should(Dia).Be(EncodeDate(2026, 11, 9));
    end).Throw<EAssertionFailed>
    .AndAlso.ThrowWithMessageContaining('Nullable<TDate>');
end;

procedure TSmartDateAssertionTests.ShouldDate_Accepts_DateTimeType;
var
  A: TSmartAgenda;
begin
  A := TSmartAgenda.Create;
  try
    A.CriadoEm := EncodeDateTime(2026, 11, 9, 23, 59, 0, 0);
    ShouldDate(A.CriadoEm).BeSameDateAs(EncodeDate(2026, 11, 9));
  finally
    A.Free;
  end;
end;

end.
