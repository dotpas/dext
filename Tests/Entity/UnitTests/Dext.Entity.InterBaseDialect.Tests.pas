unit Dext.Entity.InterBaseDialect.Tests;

// InterBase is not Firebird: no BIGINT, no identity column, no RETURNING, no
// OFFSET/FETCH, no CREATE SEQUENCE / NEXT VALUE FOR. What the dialect writes
// was checked against InterBase 15 (isql); these tests pin the SQL.

interface

uses
  System.SysUtils,
  System.TypInfo,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Entity.Dialects;

type
  [TestFixture('InterBase dialect')]
  TInterBaseDialectTests = class
  private
    FDialect: ISQLDialect;
  public
    [Setup]
    procedure CreateDialect;

    [Test]
    [Description('The dialect identifies itself as InterBase, not Firebird')]
    procedure Identifies_As_InterBase;

    [Test]
    [Description('Paging uses ROWS m TO n; OFFSET/FETCH does not exist in InterBase')]
    procedure Paging_Uses_Rows_To;

    [Test]
    [Description('INSERT ... RETURNING is not available')]
    procedure Does_Not_Support_Insert_Returning;

    [Test]
    [Description('Int64 maps to NUMERIC(18,0): InterBase has no BIGINT')]
    procedure Int64_Maps_To_Numeric;

    [Test]
    [Description('Integer, string, boolean and decimal keep their types')]
    procedure Other_Types_Are_Kept;

    [Test]
    [Description('An auto-increment column is refused: InterBase has no identity')]
    procedure AutoIncrement_Is_Refused_With_A_Clear_Message;

    [Test]
    [Description('Sequences are generators: GEN_ID, CREATE GENERATOR')]
    procedure Sequences_Are_Generators;

    [Test]
    [Description('Firebird keeps its own SQL')]
    procedure Firebird_Is_Unchanged;
  end;

implementation

procedure TInterBaseDialectTests.CreateDialect;
begin
  FDialect := TInterBaseDialect.Create;
end;

procedure TInterBaseDialectTests.Identifies_As_InterBase;
begin
  Should(Ord(FDialect.GetDialect)).Be(Ord(ddInterbase));
end;

procedure TInterBaseDialectTests.Paging_Uses_Rows_To;
begin
  Should(FDialect.GeneratePaging('SELECT "Id" FROM "t" ORDER BY "Id"', 10, 5))
    .Be('SELECT "Id" FROM "t" ORDER BY "Id" ROWS 11 TO 15');
  Should(FDialect.GeneratePaging('SELECT "Id" FROM "t"', 0, 3))
    .Be('SELECT "Id" FROM "t" ROWS 1 TO 3');
end;

procedure TInterBaseDialectTests.Does_Not_Support_Insert_Returning;
begin
  Should(FDialect.SupportsInsertReturning).BeFalse;
end;

procedure TInterBaseDialectTests.Int64_Maps_To_Numeric;
begin
  Should(FDialect.GetColumnType(TypeInfo(Int64))).Be('NUMERIC(18,0)');
end;

procedure TInterBaseDialectTests.Other_Types_Are_Kept;
begin
  Should(FDialect.GetColumnType(TypeInfo(Integer))).Be('INTEGER');
  Should(FDialect.GetColumnType(TypeInfo(string))).Be('VARCHAR(255)');
  Should(FDialect.GetColumnType(TypeInfo(Boolean))).Be('BOOLEAN');
  Should(FDialect.GetColumnType(TypeInfo(Currency))).Be('DECIMAL(18,4)');
end;

procedure TInterBaseDialectTests.AutoIncrement_Is_Refused_With_A_Clear_Message;
begin
  Should(
    procedure
    begin
      FDialect.GetColumnType(TypeInfo(Integer), True);
    end).Throw<ENotSupportedException>.AndAlso.ThrowWithMessageContaining('Sequence');
end;

procedure TInterBaseDialectTests.Sequences_Are_Generators;
begin
  Should(FDialect.GetSequenceNextValSQL('SEQ_A', 1))
    .Be('SELECT GEN_ID(SEQ_A, 1) FROM rdb$database');
  Should(FDialect.GetSequenceNextValSQL('SEQ_A', 50))
    .Be('SELECT GEN_ID(SEQ_A, 50) FROM rdb$database');
  Should(FDialect.GetCreateSequenceSQL('SEQ_A', 50)).Be('CREATE GENERATOR SEQ_A');
end;

procedure TInterBaseDialectTests.Firebird_Is_Unchanged;
var
  Fb: ISQLDialect;
begin
  Fb := TFirebirdDialect.Create;
  Should(Fb.GeneratePaging('SELECT 1', 10, 5))
    .Be('SELECT 1 OFFSET 10 ROWS FETCH NEXT 5 ROWS ONLY');
  Should(Fb.SupportsInsertReturning).BeTrue;
  Should(Fb.GetColumnType(TypeInfo(Int64))).Be('BIGINT');
  Should(Fb.GetSequenceNextValSQL('SEQ_A', 1))
    .Be('SELECT NEXT VALUE FOR SEQ_A FROM rdb$database');
end;

end.
