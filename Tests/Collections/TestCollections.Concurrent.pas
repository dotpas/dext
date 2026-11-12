unit TestCollections.Concurrent;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Dext.Testing,
  Dext.Collections.Concurrent;

type
  [TestFixture('Collections - Concurrent Dictionary')]
  TConcurrentDictionaryTests = class
  public
    [Test]
    procedure TryAdd_ShouldAddSuccessfullyWhenKeyIsNew;
    [Test]
    procedure TryAdd_ShouldFailWhenKeyExists;
    [Test]
    procedure GetOrAdd_ShouldReturnExistingOrNew;
    [Test]
    procedure TryUpdate_ShouldUpdateOnlyWhenComparisonMatches;
    [Test]
    procedure TryRemove_ShouldRemoveExistingKey;
    [Test]
    procedure Multithreaded_SpikingShouldNotCrash;
    [Test]
    procedure GetOrAdd_Under_Race_Stores_One_Value_For_Everyone;
    [Test]
    procedure GetOrAdd_Factory_May_Reenter_The_Dictionary;
  end;

implementation

{ TConcurrentDictionaryTests }

procedure TConcurrentDictionaryTests.TryAdd_ShouldAddSuccessfullyWhenKeyIsNew;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create;
  Should(Dict.TryAdd('key1', 100)).BeTrue;
  Should(Dict.Count).Be(1);
end;

procedure TConcurrentDictionaryTests.TryAdd_ShouldFailWhenKeyExists;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create;
  Dict.TryAdd('key1', 100);
  Should(Dict.TryAdd('key1', 200)).BeFalse;
  Should(Dict.Count).Be(1);
end;

procedure TConcurrentDictionaryTests.GetOrAdd_ShouldReturnExistingOrNew;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
  Val: Integer;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create;
  Val := Dict.GetOrAdd('key1', function(Arg: string): Integer begin Result := 50; end);
  Should(Val).Be(50);
  
  Val := Dict.GetOrAdd('key1', function(Arg: string): Integer begin Result := 150; end);
  Should(Val).Be(50); // Should retain the existing
end;

procedure TConcurrentDictionaryTests.TryUpdate_ShouldUpdateOnlyWhenComparisonMatches;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
  Val: Integer;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create;
  Dict.TryAdd('key1', 100);
  
  Should(Dict.TryUpdate('key1', 200, 50)).BeFalse; // Comparison mismatch
  Dict.TryGetValue('key1', Val);
  Should(Val).Be(100);
  
  Should(Dict.TryUpdate('key1', 200, 100)).BeTrue; // Match
  Dict.TryGetValue('key1', Val);
  Should(Val).Be(200);
end;

procedure TConcurrentDictionaryTests.TryRemove_ShouldRemoveExistingKey;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
  Val: Integer;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create;
  Dict.TryAdd('key1', 100);
  Should(Dict.TryRemove('key1', Val)).BeTrue;
  Should(Val).Be(100);
  Should(Dict.Count).Be(0);
end;

procedure TConcurrentDictionaryTests.Multithreaded_SpikingShouldNotCrash;
var
  Dict: IDextConcurrentDictionary<Integer, Integer>;
  Threads: TArray<TThread>;
  I: Integer;
begin
  Dict := TConcurrentDictionary<Integer, Integer>.Create;
  SetLength(Threads, 16);
  for I := 0 to 15 do
  begin
    Threads[I] := TThread.CreateAnonymousThread(
      procedure
      var
        J: Integer;
      begin
        for J := 0 to 999 do
          Dict.TryAdd(J, J * 2); // Many threads hitting the same keys
      end
    );
    Threads[I].FreeOnTerminate := False;
    Threads[I].Start;
  end;
  
  for I := 0 to 15 do
  begin
    Threads[I].WaitFor;
    Threads[I].Free;
  end;
  
  Should(Dict.Count).Be(1000);
end;

procedure TConcurrentDictionaryTests.GetOrAdd_Under_Race_Stores_One_Value_For_Everyone;
const
  N = 8;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
  LResults: array[0..N - 1] of Integer;
  LCounter: Integer;
  LGo: TEvent;
  LDone: array[0..N - 1] of TEvent;
  I: Integer;
  Start: TProc<Integer>;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create;
  Start :=
    procedure(AIdx: Integer)
    begin
      TThread.CreateAnonymousThread(
        procedure
        begin
          LGo.WaitFor(5000);
          LResults[AIdx] := Dict.GetOrAdd('k',
            function(K: string): Integer
            begin
              Result := TInterlocked.Increment(LCounter);
              Sleep(20);
            end);
          LDone[AIdx].SetEvent;
        end).Start;
    end;
  LCounter := 0;
  LGo := TEvent.Create(nil, True, False, '');
  for I := 0 to N - 1 do
    LDone[I] := TEvent.Create(nil, True, False, '');
  try
    for I := 0 to N - 1 do
      Start(I);
    LGo.SetEvent; // release every racer at once
    for I := 0 to N - 1 do
      Should(LDone[I].WaitFor(5000) = wrSignaled).BeTrue;
    for I := 1 to N - 1 do
      Should(LResults[I]).Be(LResults[0]); // one stored value for everyone
    Should(Dict.Count).Be(1);
  finally
    LGo.Free;
    for I := 0 to N - 1 do
      LDone[I].Free;
  end;
end;

procedure TConcurrentDictionaryTests.GetOrAdd_Factory_May_Reenter_The_Dictionary;
var
  Dict: IDextConcurrentDictionary<string, Integer>;
  V: Integer;
begin
  Dict := TConcurrentDictionary<string, Integer>.Create(1);
  // One stripe: if the factory ran under the stripe lock this would hang.
  V := Dict.GetOrAdd('a',
    function(K: string): Integer
    var
      Tmp: Integer;
    begin
      Dict.TryGetValue(K, Tmp);
      Result := Dict.Count + 41;
    end);
  Should(V).Be(41);
  Should(Dict.GetOrAdd('a', function(K: string): Integer begin Result := 7; end)).Be(41);
end;

end.
