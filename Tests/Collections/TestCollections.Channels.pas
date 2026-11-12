unit TestCollections.Channels;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Threading,
  Dext.Testing,
  Dext.Threading.CancellationToken,
  Dext.Collections.Channels;

type
  [TestFixture('Collections - Channels')]
  TChannelTests = class
  public
    [Test]
    procedure TryWrite_ShouldSucceedForUnbounded;
    [Test]
    procedure TryRead_ShouldReturnFalseIfEmpty;
    [Test]
    procedure Bounded_TryWrite_ShouldFailWhenFull;
    [Test]
    procedure Concurrent_WriteAndRead_ShouldPassMessages;
    [Test]
    procedure Read_After_Close_Drains_Then_Reports_Completed;
    [Test]
    procedure Write_On_Closed_Channel_Raises_Closed;
    [Test]
    procedure TryRead_With_Timeout_Gives_Up_When_Empty;
    [Test]
    procedure TryWrite_With_Timeout_Succeeds_When_Room_Appears;
    [Test]
    procedure Read_With_Token_Wakes_On_Cancel;
    [Test]
    procedure Write_With_Token_Wakes_On_Cancel_When_Full;
    [Test]
    procedure Close_Wakes_Blocked_Reader;
    [Test]
    procedure Capacity_Below_One_Is_Rejected;
  end;

implementation

{ TChannelTests }

procedure TChannelTests.TryWrite_ShouldSucceedForUnbounded;
var
  Chan: IChannel<string>;
begin
  Chan := TChannel<string>.CreateUnbounded;
  Should(Chan.TryWrite('msg1')).BeTrue;
  Should(Chan.TryWrite('msg2')).BeTrue;
  
  Chan.Close;
end;

procedure TChannelTests.TryRead_ShouldReturnFalseIfEmpty;
var
  Chan: IChannel<string>;
  Val: string;
begin
  Chan := TChannel<string>.CreateUnbounded;
  Should(Chan.TryRead(Val)).BeFalse;
  Chan.Close;
end;

procedure TChannelTests.Bounded_TryWrite_ShouldFailWhenFull;
var
  Chan: IChannel<Integer>;
begin
  Chan := TChannel<Integer>.CreateBounded(2);
  Should(Chan.TryWrite(1)).BeTrue;
  Should(Chan.TryWrite(2)).BeTrue;
  Should(Chan.TryWrite(3)).BeFalse; // Should be full
  
  Chan.Close;
end;

procedure TChannelTests.Concurrent_WriteAndRead_ShouldPassMessages;
var
  Chan: IChannel<Integer>;
  Sum: Integer;
  Tasks: TArray<ITask>;
begin
  Chan := TChannel<Integer>.CreateBounded(10);
  Sum := 0;
  
  SetLength(Tasks, 2);
  
  Tasks[0] := TTask.Run(
    procedure
    var
      I, Val: Integer;
    begin
      for I := 1 to 50 do
      begin
        Val := Chan.Read;
        TInterlocked.Add(Sum, Val);
      end;
    end
  );
  
  Tasks[1] := TTask.Run(
    procedure
    var
      I: Integer;
    begin
      for I := 1 to 50 do
      begin
        Chan.Write(I);
      end;
    end
  );
  
  TTask.WaitForAll(Tasks);
  Chan.Close;
  
  // Sum of 1..50 = 1275
  Should(Sum).Be(1275);
end;

procedure TChannelTests.Read_After_Close_Drains_Then_Reports_Completed;
var
  Chan: IChannel<Integer>;
  LCompleted: Boolean;
begin
  Chan := TChannel<Integer>.CreateBounded(4);
  Chan.Write(1);
  Chan.Write(2);
  Chan.Close;
  Should(Chan.IsCompleted).BeFalse; // items still queued
  Should(Chan.Read).Be(1);
  Should(Chan.Read).Be(2);
  Should(Chan.IsCompleted).BeTrue;
  LCompleted := False;
  try
    Chan.Read;
  except
    on E: EChannelCompletedException do LCompleted := True;
  end;
  Should(LCompleted).BeTrue;
end;

procedure TChannelTests.Write_On_Closed_Channel_Raises_Closed;
var
  Chan: IChannel<Integer>;
  LRaised: Boolean;
begin
  Chan := TChannel<Integer>.CreateUnbounded;
  Chan.Close;
  Should(Chan.TryWrite(1)).BeFalse;
  LRaised := False;
  try
    Chan.Write(1);
  except
    on E: EChannelClosedException do LRaised := True;
  end;
  Should(LRaised).BeTrue;
end;

procedure TChannelTests.TryRead_With_Timeout_Gives_Up_When_Empty;
var
  Chan: IChannel<Integer>;
  V: Integer;
begin
  Chan := TChannel<Integer>.CreateUnbounded;
  Should(Chan.TryRead(V, 30)).BeFalse;
  Should(Chan.IsCompleted).BeFalse; // a timeout is not the end of the stream
end;

procedure TChannelTests.TryWrite_With_Timeout_Succeeds_When_Room_Appears;
var
  Chan: IChannel<Integer>;
  LOk: Boolean;
  LDone: TEvent;
begin
  Chan := TChannel<Integer>.CreateBounded(1);
  Chan.Write(1);
  Should(Chan.TryWrite(2, 20)).BeFalse; // stays full
  LDone := TEvent.Create(nil, True, False, '');
  try
    LOk := False;
    TTask.Run(
      procedure
      begin
        LOk := Chan.TryWrite(3, 3000);
        LDone.SetEvent;
      end);
    Sleep(50);
    Should(Chan.Read).Be(1); // makes room
    Should(LDone.WaitFor(3000) = wrSignaled).BeTrue;
    Should(LOk).BeTrue;
    Should(Chan.Read).Be(3);
  finally
    LDone.Free;
  end;
end;

procedure TChannelTests.Read_With_Token_Wakes_On_Cancel;
var
  Chan: IChannel<Integer>;
  Src: TCancellationTokenSource;
  LCancelled: Boolean;
begin
  Chan := TChannel<Integer>.CreateUnbounded;
  Src := TCancellationTokenSource.Create;
  try
    Src.CancelAfter(50);
    LCancelled := False;
    try
      Chan.Read(Src.Token); // would block forever without the token
    except
      on E: EOperationCancelled do LCancelled := True;
    end;
    Should(LCancelled).BeTrue;
  finally
    Src.Free;
  end;
end;

procedure TChannelTests.Write_With_Token_Wakes_On_Cancel_When_Full;
var
  Chan: IChannel<Integer>;
  Src: TCancellationTokenSource;
  LCancelled: Boolean;
begin
  Chan := TChannel<Integer>.CreateBounded(1);
  Chan.Write(1);
  Src := TCancellationTokenSource.Create;
  try
    Src.CancelAfter(50);
    LCancelled := False;
    try
      Chan.Write(2, Src.Token);
    except
      on E: EOperationCancelled do LCancelled := True;
    end;
    Should(LCancelled).BeTrue;
    Should(Chan.Count).Be(1);
  finally
    Src.Free;
  end;
end;

procedure TChannelTests.Close_Wakes_Blocked_Reader;
var
  Chan: IChannel<Integer>;
  LCompleted: Boolean;
  LDone: TEvent;
begin
  Chan := TChannel<Integer>.CreateUnbounded;
  LDone := TEvent.Create(nil, True, False, '');
  try
    LCompleted := False;
    TTask.Run(
      procedure
      begin
        try
          Chan.Read;
        except
          on E: EChannelCompletedException do LCompleted := True;
        end;
        LDone.SetEvent;
      end);
    Sleep(50);
    Chan.Close;
    Should(LDone.WaitFor(3000) = wrSignaled).BeTrue;
    Should(LCompleted).BeTrue;
  finally
    LDone.Free;
  end;
end;

procedure TChannelTests.Capacity_Below_One_Is_Rejected;
var
  LRaised: Boolean;
begin
  LRaised := False;
  try
    TChannel<Integer>.CreateBounded(0);
  except
    on E: EArgumentOutOfRangeException do LRaised := True;
  end;
  Should(LRaised).BeTrue;
end;

end.
