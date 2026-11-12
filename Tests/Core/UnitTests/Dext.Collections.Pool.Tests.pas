unit Dext.Collections.Pool.Tests;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  System.Classes,
  Dext.Collections.Pool;

type
  [TestFixture]
  TTestPoolItem = class(TNoRefCountObject, IPoolable)
  private
    FResetCount: Integer;
    FState: string;
  public
    constructor Create;
    procedure ResetState;
    property ResetCount: Integer read FResetCount;
    property State: string read FState write FState;
  end;

  [TestFixture]
  TDextPoolTests = class
  public
    [Test]
    procedure Test_Pool_Warmup_And_Acquire;
    [Test]
    procedure Test_Pool_AutoResetState_OnRelease;
    [Test]
    procedure Test_Pool_Use_RAII;
    [Test]
    procedure Test_Pool_MaxSize_Limit;
    [Test]
    procedure Test_Pool_IdleTimeout_Trims_To_MinSize;
    [Test]
    procedure Test_Pool_IdleTimeout_Keeps_Fresh_Items;
  end;

implementation

{ TTestPoolItem }

constructor TTestPoolItem.Create;
begin
  inherited Create;
  FResetCount := 0;
  FState := 'Initial';
end;

procedure TTestPoolItem.ResetState;
begin
  Inc(FResetCount);
  FState := 'Clean';
end;

{ TDextPoolTests }

procedure TDextPoolTests.Test_Pool_Warmup_And_Acquire;
var
  Config: TDextPoolConfig;
  Pool: IDextPool<TTestPoolItem>;
  Item1, Item2: TTestPoolItem;
begin
  Config := TDextPoolConfig.Default;
  Config.MinSize := 2;
  Config.MaxSize := 5;

  Pool := TDextPool<TTestPoolItem>.Create(Config);
  Assert.AreEqual(2, Pool.Count);

  Assert.IsTrue(Pool.Acquire(Item1));
  Assert.AreEqual(1, Pool.Count);

  Assert.IsTrue(Pool.Acquire(Item2));
  Assert.AreEqual(0, Pool.Count);

  Pool.Release(Item1);
  Pool.Release(Item2);
  Assert.AreEqual(2, Pool.Count);
end;

procedure TDextPoolTests.Test_Pool_AutoResetState_OnRelease;
var
  Config: TDextPoolConfig;
  Pool: IDextPool<TTestPoolItem>;
  Item: TTestPoolItem;
begin
  Config := TDextPoolConfig.Default;
  Config.MinSize := 1;
  Config.MaxSize := 2;

  Pool := TDextPool<TTestPoolItem>.Create(Config);
  Assert.IsTrue(Pool.Acquire(Item));

  Item.State := 'DirtyState';
  Pool.Release(Item);

  Assert.AreEqual(1, Item.ResetCount);
  Assert.AreEqual('Clean', Item.State);
end;

procedure TDextPoolTests.Test_Pool_Use_RAII;
var
  Config: TDextPoolConfig;
  Pool: IDextPool<TTestPoolItem>;
  Executed: Boolean;
  Proc: TProc<TTestPoolItem>;
begin
  Config := TDextPoolConfig.Default;
  Config.MinSize := 1;
  Config.MaxSize := 2;
  Executed := False;

  Pool := TDextPool<TTestPoolItem>.Create(Config);
  Proc := procedure(Item: TTestPoolItem)
    begin
      Executed := True;
      Item.State := 'Used';
    end;
  Pool.Use(Proc);

  Assert.IsTrue(Executed);
  Assert.AreEqual(1, Pool.Count);
end;

procedure TDextPoolTests.Test_Pool_MaxSize_Limit;
var
  Config: TDextPoolConfig;
  Pool: IDextPool<TTestPoolItem>;
  Item1, Item2, Item3: TTestPoolItem;
begin
  Config := TDextPoolConfig.Default;
  Config.MinSize := 0;
  Config.MaxSize := 2;
  Config.AcquireTimeoutMs := 100;

  Pool := TDextPool<TTestPoolItem>.Create(Config);
  Assert.IsTrue(Pool.Acquire(Item1));
  Assert.IsTrue(Pool.Acquire(Item2));
  Assert.IsFalse(Pool.Acquire(Item3)); // Timed out waiting for item

  Pool.Release(Item1);
  Pool.Release(Item2);
end;


procedure TDextPoolTests.Test_Pool_IdleTimeout_Trims_To_MinSize;
var
  Config: TDextPoolConfig;
  Pool: IDextPool<TTestPoolItem>;
  A, B, C, D: TTestPoolItem;
begin
  Config := TDextPoolConfig.Default;
  Config.MinSize := 1;
  Config.MaxSize := 4;
  Config.IdleTimeoutMs := 50;

  Pool := TDextPool<TTestPoolItem>.Create(Config);
  Pool.Acquire(A);
  Pool.Acquire(B);
  Pool.Acquire(C);
  Pool.Release(A);
  Pool.Release(B);
  Pool.Release(C);
  Assert.AreEqual(3, Pool.Count);

  TThread.Sleep(150);

  // The next Acquire evicts the idle surplus, never going below MinSize.
  Assert.IsTrue(Pool.Acquire(D));
  Assert.AreEqual(0, Pool.Count);
  Pool.Release(D);
  Assert.AreEqual(1, Pool.Count);
end;

procedure TDextPoolTests.Test_Pool_IdleTimeout_Keeps_Fresh_Items;
var
  Config: TDextPoolConfig;
  Pool: IDextPool<TTestPoolItem>;
  A, B: TTestPoolItem;
begin
  Config := TDextPoolConfig.Default;
  Config.MinSize := 0;
  Config.MaxSize := 4;
  Config.IdleTimeoutMs := 60000;

  Pool := TDextPool<TTestPoolItem>.Create(Config);
  Pool.Acquire(A);
  Pool.Acquire(B);
  Pool.Release(A);
  Pool.Release(B);
  Assert.AreEqual(2, Pool.Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TDextPoolTests);

end.
