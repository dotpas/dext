unit Dext.Entity.Sequences.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.Variants,
  Dext.Collections,
  Dext.Assertions,
  Dext.Testing.Attributes,
  Dext.Mocks,
  Dext.Mocks.Matching,
  Dext.Entity.Attributes,
  Dext.Entity.Context,
  Dext.Entity.Drivers.Interfaces,
  Dext.Entity.Dialects,
  Dext.Interception,
  Dext.Entity.Core;

type
  [Table('test_seq_entities')]
  TTestSeqEntity = class
  private
    FId: Integer;
    FName: string;
  public
    [PK, Sequence('SEQ_TEST_ENTITY', 50)]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  // A key that is both [AutoInc] and sequenced: the sequence wins, so a dialect
  // without identity columns (InterBase) can still create the table.
  [Table('test_seq_auto_entities')]
  TTestSeqAutoEntity = class
  private
    FId: Integer;
    FName: string;
  public
    [PK, AutoInc, Sequence('SEQ_TEST_AUTO', 1)]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  [TestFixture('Entity Sequences and HiLo')]
  TEntitySequencesTests = class
  public
    [Test]
    procedure Should_Create_Sequences_During_EnsureCreated;

    [Test]
    procedure Should_Preallocate_Ids_During_SaveChanges;

    [Test]
    procedure Sequence_Wins_Over_AutoInc_In_The_Create_Table_Script;

    [Test]
    procedure Sequence_Wins_Over_AutoInc_In_The_Insert;
  end;

implementation

procedure TEntitySequencesTests.Should_Create_Sequences_During_EnsureCreated;
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Reader: Mock<IDbReader>;
  Ctx: TDbContext;
begin
  Conn := Mock<IDbConnection>.Create;
  Cmd := Mock<IDbCommand>.Create;
  Reader := Mock<IDbReader>.Create;

  Reader.Setup.Returns(False).When.Next;
  Cmd.Setup.Returns(Reader.Instance).When.ExecuteQuery;
  Conn.Setup.Returns(Cmd.Instance).When.CreateCommand(Arg.Any<string>);
  Conn.Setup.Returns(False).When.TableExists(Arg.Any<string>);

  Ctx := TDbContext.Create(Conn.Instance, TFirebirdDialect.Create);
  try
    Ctx.Entities<TTestSeqEntity>;
    Ctx.EnsureCreated;

    Conn.Received.CreateCommand('CREATE SEQUENCE SEQ_TEST_ENTITY');
  finally
    Ctx.Free;
  end;
end;

procedure TEntitySequencesTests.Should_Preallocate_Ids_During_SaveChanges;
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Reader: Mock<IDbReader>;
  Tx: Mock<IDbTransaction>;
  Ctx: TDbContext;
  E: TTestSeqEntity;
begin
  Conn := Mock<IDbConnection>.Create;
  Cmd := Mock<IDbCommand>.Create;
  Reader := Mock<IDbReader>.Create;
  Tx := Mock<IDbTransaction>.Create;

  Reader.Setup.Returns(True).When.Next;
  Reader.Setup.Returns(TValue.From<Int64>(150)).When.GetValue(0);

  Cmd.Setup.Returns(Reader.Instance).When.ExecuteQuery;
  Conn.Setup.Returns(Cmd.Instance).When.CreateCommand(Arg.Any<string>);
  Conn.Setup.Returns(Tx.Instance).When.BeginTransaction;

  Ctx := TDbContext.Create(Conn.Instance, TFirebirdDialect.Create);
  try
    E := TTestSeqEntity.Create;
    E.Name := 'Test';
    Ctx.Entities<TTestSeqEntity>.Add(E);
    Ctx.SaveChanges;

    // With allocation size = 50 and HiLo, first ID should be GeneratedId - AllocationSize + 1
    // 150 - 50 + 1 = 101
    Should(E.Id).Be(101);
  finally
    Ctx.Free;
  end;
end;

procedure TEntitySequencesTests.Sequence_Wins_Over_AutoInc_In_The_Create_Table_Script;
var
  Conn: Mock<IDbConnection>;
  Ctx: TDbContext;
  Script: string;
begin
  Conn := Mock<IDbConnection>.Create;

  Ctx := TDbContext.Create(Conn.Instance, TInterBaseDialect.Create);
  try
    // InterBase raises ENotSupportedException for an identity column.
    Script := Ctx.Entities<TTestSeqAutoEntity>.GenerateCreateTableScript;

    Should(Script).Contain('CREATE TABLE');
  finally
    Ctx.Free;
  end;
end;

procedure TEntitySequencesTests.Sequence_Wins_Over_AutoInc_In_The_Insert;
var
  Conn: Mock<IDbConnection>;
  Cmd: Mock<IDbCommand>;
  Reader: Mock<IDbReader>;
  Tx: Mock<IDbTransaction>;
  Ctx: TDbContext;
  E: TTestSeqAutoEntity;
begin
  Conn := Mock<IDbConnection>.Create;
  Cmd := Mock<IDbCommand>.Create;
  Reader := Mock<IDbReader>.Create;
  Tx := Mock<IDbTransaction>.Create;

  Reader.Setup.Returns(True).When.Next;
  Reader.Setup.Returns(TValue.From<Int64>(7)).When.GetValue(0);
  Cmd.Setup.Returns(Reader.Instance).When.ExecuteQuery;
  Conn.Setup.Returns(Cmd.Instance).When.CreateCommand(Arg.Any<string>);
  Conn.Setup.Returns(Tx.Instance).When.BeginTransaction;

  Ctx := TDbContext.Create(Conn.Instance, TInterBaseDialect.Create);
  try
    E := TTestSeqAutoEntity.Create;
    E.Name := 'Test';
    Ctx.Entities<TTestSeqAutoEntity>.Add(E);
    Ctx.SaveChanges;

    // The id comes from the generator; it is not overwritten by the identity
    // path (InterBase has none) after the INSERT.
    Should(E.Id).Be(7);
  finally
    Ctx.Free;
  end;
end;

end.
