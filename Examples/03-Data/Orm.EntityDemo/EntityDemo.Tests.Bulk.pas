unit EntityDemo.Tests.Bulk;

interface

uses
  System.SysUtils,
  Dext.Collections,
  Dext.Entity.Core,
  Dext.Entity.Dialects,
  EntityDemo.Tests.Base,
  EntityDemo.Entities,
  EntityDemo.DbConfig;

type
  TBulkTest = class(TBaseTest)
  public
    procedure Run; override;
  end;

implementation

{ TBulkTest }

procedure TBulkTest.Run;
var
  BulkUsers: IList<TUser>;
  BulkSeqUsers: IList<TSequencedUser>;
  i: Integer;
  StartTime: TDateTime;
  Duration: TDateTime;
  Count: Integer;
  Dialect: ISQLDialect;
  SQL: string;
  U: TUser;
  SU: TSequencedUser;
begin
  Dialect := TDbConfig.CreateDialect;

  Log('📦 Running Bulk Operation Tests...');
  Log('================================');

  // Verify Bulk Safety Guards
  Log('   Verifying Bulk Safety Guards...');
  AssertTrue(not FContext.Entities<TUser>.IsBulkInsertSafe, 'TUser Insert should not be bulk safe (AutoInc)', 'TUser Insert bulk safe mismatch');
  AssertTrue(FContext.Entities<TUser>.IsBulkUpdateSafe, 'TUser Update should be bulk safe', 'TUser Update bulk safe mismatch');
  AssertTrue(FContext.Entities<TUser>.IsBulkDeleteSafe, 'TUser Delete should be bulk safe', 'TUser Delete bulk safe mismatch');

  AssertTrue(not FContext.Entities<TProduct>.IsBulkInsertSafe, 'TProduct Insert should not be bulk safe (AutoInc)', 'TProduct Insert bulk safe mismatch');
  AssertTrue(not FContext.Entities<TProduct>.IsBulkUpdateSafe, 'TProduct Update should not be bulk safe (Version)', 'TProduct Update bulk safe mismatch');
  AssertTrue(not FContext.Entities<TProduct>.IsBulkDeleteSafe, 'TProduct Delete should not be bulk safe (Version)', 'TProduct Delete bulk safe mismatch');

  AssertTrue(not FContext.Entities<TTask>.IsBulkInsertSafe, 'TTask Insert should not be bulk safe (AutoInc)', 'TTask Insert bulk safe mismatch');
  AssertTrue(FContext.Entities<TTask>.IsBulkUpdateSafe, 'TTask Update should be bulk safe', 'TTask Update bulk safe mismatch');
  AssertTrue(not FContext.Entities<TTask>.IsBulkDeleteSafe, 'TTask Delete should not be bulk safe (SoftDelete)', 'TTask Delete bulk safe mismatch');

  AssertTrue(FContext.Entities<TOrderItem>.IsBulkInsertSafe, 'TOrderItem Insert should be bulk safe', 'TOrderItem Insert bulk safe mismatch');
  AssertTrue(FContext.Entities<TOrderItem>.IsBulkUpdateSafe, 'TOrderItem Update should be bulk safe', 'TOrderItem Update bulk safe mismatch');
  AssertTrue(FContext.Entities<TOrderItem>.IsBulkDeleteSafe, 'TOrderItem Delete should be bulk safe', 'TOrderItem Delete bulk safe mismatch');

  AssertTrue(FContext.Entities<TSequencedUser>.IsBulkInsertSafe, 'TSequencedUser Insert should be bulk safe (Sequenced)', 'TSequencedUser Insert bulk safe mismatch');
  LogSuccess('Bulk Safety Guards verified successfully.');

  BulkUsers := TCollections.CreateList<TUser>(False);
  try
    // 1. Bulk Insert
    Log('   Preparing 100 users...');
    for i := 1 to 100 do
    begin
      U := TUser.Create;
      U.Name := 'Bulk User ' + i.ToString;
      U.Age := 20;
      U.Email := 'bulk' + i.ToString + '@dext.com';
      U.Address := nil;
      BulkUsers.Add(U);
    end;

    StartTime := Now;
    FContext.Entities<TUser>.AddRange(BulkUsers);
    FContext.SaveChanges;
    Duration := Now - StartTime;

    LogSuccess(Format('Inserted 100 users in %s', [FormatDateTime('ss.zzz', Duration)]));

    SQL := Format('SELECT COUNT(*) FROM %s WHERE %s = 20 AND %s LIKE ''Bulk User%%''',
      [Dialect.QuoteIdentifier('users'), Dialect.QuoteIdentifier('Age'), Dialect.QuoteIdentifier('full_name')]);
    Count := FConn.ExecSQLScalar(SQL);
    AssertTrue(Count = 100, 'Bulk Add Verified.', Format('Bulk Add Failed: Found %d users.', [Count]));

    // 2. Bulk Update
    Log('   Updating 100 users...');
    for U in BulkUsers do
    begin
      U.Age := 30;
    end;

    StartTime := Now;
    FContext.Entities<TUser>.UpdateRange(BulkUsers);
    FContext.SaveChanges;
    Duration := Now - StartTime;

    LogSuccess(Format('Updated 100 users in %s', [FormatDateTime('ss.zzz', Duration)]));

    SQL := Format('SELECT COUNT(*) FROM %s WHERE %s = 30 AND %s LIKE ''Bulk User%%''',
      [Dialect.QuoteIdentifier('users'), Dialect.QuoteIdentifier('Age'), Dialect.QuoteIdentifier('full_name')]);
    Count := FConn.ExecSQLScalar(SQL);
    AssertTrue(Count = 100, 'Bulk Update Verified.', Format('Bulk Update Failed: Found %d users.', [Count]));

    // 3. Bulk Remove
    Log('   Removing 100 users...');
    StartTime := Now;
    FContext.Entities<TUser>.RemoveRange(BulkUsers);
    FContext.SaveChanges;
    Duration := Now - StartTime;

    LogSuccess(Format('Removed 100 users in %s', [FormatDateTime('ss.zzz', Duration)]));

    SQL := Format('SELECT COUNT(*) FROM %s WHERE %s LIKE ''Bulk User%%''',
      [Dialect.QuoteIdentifier('users'), Dialect.QuoteIdentifier('full_name')]);
    Count := FConn.ExecSQLScalar(SQL);
    AssertTrue(Count = 0, 'Bulk Remove Verified.', Format('Bulk Remove Failed: Found %d users.', [Count]));

  finally
  end;

  // 4. Sequenced Entities Bulk insert/update/delete test
  Log('   Preparing 100 sequenced users...');
  BulkSeqUsers := TCollections.CreateList<TSequencedUser>(False);
  try
    for i := 1 to 100 do
    begin
      SU := TSequencedUser.Create;
      SU.Name := 'Seq User ' + i.ToString;
      SU.Age := 25;
      BulkSeqUsers.Add(SU);
    end;

    StartTime := Now;
    FContext.Entities<TSequencedUser>.AddRange(BulkSeqUsers);
    FContext.SaveChanges;
    Duration := Now - StartTime;

    LogSuccess(Format('Inserted 100 sequenced users in %s', [FormatDateTime('ss.zzz', Duration)]));

    var MinId, MaxId: Integer;
    MinId := BulkSeqUsers[0].Id;
    MaxId := BulkSeqUsers[0].Id;
    for i := 1 to 99 do
    begin
      if BulkSeqUsers[i].Id < MinId then MinId := BulkSeqUsers[i].Id;
      if BulkSeqUsers[i].Id > MaxId then MaxId := BulkSeqUsers[i].Id;
    end;

    // Assert ids are pre-allocated and correct
    AssertTrue(MinId > 0, 'First sequenced user ID is set', 'First sequenced user ID is not set');
    AssertTrue(MaxId = MinId + 99, 'Sequenced IDs are contiguous', 'Sequenced IDs are not contiguous');

    SQL := Format('SELECT COUNT(*) FROM %s WHERE %s = 25 AND %s LIKE ''Seq User%%''',
      [Dialect.QuoteIdentifier('sequenced_users'), Dialect.QuoteIdentifier('Age'), Dialect.QuoteIdentifier('Name')]);
    Count := FConn.ExecSQLScalar(SQL);
    AssertTrue(Count = 100, 'Bulk Add for Sequenced Entities Verified.', Format('Bulk Add for Sequenced Entities Failed: Found %d users.', [Count]));

    // 4.2 Bulk Update Sequenced Entities
    Log('   Updating 100 sequenced users...');
    for SU in BulkSeqUsers do
      SU.Age := 35;

    StartTime := Now;
    FContext.Entities<TSequencedUser>.UpdateRange(BulkSeqUsers);
    FContext.SaveChanges;
    Duration := Now - StartTime;

    LogSuccess(Format('Updated 100 sequenced users in %s', [FormatDateTime('ss.zzz', Duration)]));

    SQL := Format('SELECT COUNT(*) FROM %s WHERE %s = 35 AND %s LIKE ''Seq User%%''',
      [Dialect.QuoteIdentifier('sequenced_users'), Dialect.QuoteIdentifier('Age'), Dialect.QuoteIdentifier('Name')]);
    Count := FConn.ExecSQLScalar(SQL);
    AssertTrue(Count = 100, 'Bulk Update for Sequenced Entities Verified.', Format('Bulk Update Failed: Found %d users.', [Count]));

    // 4.3 Bulk Remove Sequenced Entities
    Log('   Removing 100 sequenced users...');
    StartTime := Now;
    FContext.Entities<TSequencedUser>.RemoveRange(BulkSeqUsers);
    FContext.SaveChanges;
    Duration := Now - StartTime;

    LogSuccess(Format('Removed 100 sequenced users in %s', [FormatDateTime('ss.zzz', Duration)]));

    SQL := Format('SELECT COUNT(*) FROM %s WHERE %s LIKE ''Seq User%%''',
      [Dialect.QuoteIdentifier('sequenced_users'), Dialect.QuoteIdentifier('Name')]);
    Count := FConn.ExecSQLScalar(SQL);
    AssertTrue(Count = 0, 'Bulk Remove for Sequenced Entities Verified.', Format('Bulk Remove Failed: Found %d users.', [Count]));
  finally
    // for SU in BulkSeqUsers do
    //   SU.Free;
  end;

  Log('');
end;

end.
