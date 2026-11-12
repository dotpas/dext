unit TestCollections.Vector;

interface

uses
  System.SysUtils,
  Dext.Testing,
  Dext.Core.Span,
  Dext.Collections.Vector;

type
  [TestFixture('Collections - Vector')]
  TVectorTests = class
  public
    [Test]
    procedure Add_ShouldStoreValue;
    [Test]
    procedure Add_ShouldTriggerHeapAllocationAfterSVO;
    [Test]
    procedure Clear_ShouldResetCountAndFreeHeap;
    [Test]
    procedure ToArray_ShouldCopyData;
    [Test]
    procedure Remove_String_KeepsTheOthers;
    [Test]
    procedure RemoveAt_String_Last_And_Middle;
    [Test]
    procedure Remove_String_OnHeap;
    [Test]
    procedure Remove_Integer_KeepsTheOthers;
    [Test]
    procedure Remove_Missing_DoesNothing;
  end;

implementation

{ TVectorTests }

function Join(var V: TVector<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to V.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + V[I];
  end;
end;

procedure TVectorTests.Remove_String_KeepsTheOthers;
var
  V: TVector<string>;
begin
  V.Add('A');
  V.Add('B');
  V.Add('C');
  V.Remove('A');
  Should(V.Count).Be(2);
  Should(Join(V)).Be('B,C');
end;

procedure TVectorTests.RemoveAt_String_Last_And_Middle;
var
  V: TVector<string>;
begin
  V.Add('A');
  V.Add('B');
  V.Add('C');
  V.Add('D');
  V.RemoveAt(1);
  Should(Join(V)).Be('A,C,D');
  V.RemoveAt(2);
  Should(Join(V)).Be('A,C');
end;

procedure TVectorTests.Remove_String_OnHeap;
var
  V: TVector<string>;
  I: Integer;
begin
  for I := 1 to 40 do
    V.Add('item' + IntToStr(I));
  V.Remove('item3');
  Should(V.Count).Be(39);
  Should(V[2]).Be('item4');
  Should(V[38]).Be('item40');
end;

procedure TVectorTests.Remove_Integer_KeepsTheOthers;
var
  V: TVector<Integer>;
begin
  V.Add(1);
  V.Add(2);
  V.Add(3);
  V.Remove(1);
  Should(V.Count).Be(2);
  Should(V[0]).Be(2);
  Should(V[1]).Be(3);
end;

procedure TVectorTests.Remove_Missing_DoesNothing;
var
  V: TVector<string>;
begin
  V.Add('A');
  V.Remove('Z');
  Should(Join(V)).Be('A');
end;

procedure TVectorTests.Add_ShouldStoreValue;
var
  V: TVector<Integer>;
begin
  V.Add(10);
  Should(V.Count).Be(1);
  Should(V[0]).Be(10);
end;

procedure TVectorTests.Add_ShouldTriggerHeapAllocationAfterSVO;
var
  V: TVector<Integer>;
  I: Integer;
begin
  // SVO_BUFFER_SIZE in TVector is 64 bytes. For Integers (4 bytes), SVO supports 16 items.
  for I := 1 to 20 do
    V.Add(I);
    
  Should(V.Count).Be(20);
  Should(V[19]).Be(20);
  Should(V.Capacity).BeGreaterThan(16); // Heap transitioned
end;

procedure TVectorTests.Clear_ShouldResetCountAndFreeHeap;
var
  V: TVector<Integer>;
begin
  V.Add(1);
  V.Clear;
  Should(V.Count).Be(0);
  Should(V.Capacity).Be(16);
end;

procedure TVectorTests.ToArray_ShouldCopyData;
var
  V: TVector<Integer>;
  Arr: TArray<Integer>;
begin
  V.Add(10);
  V.Add(20);
  Arr := V.ToArray;
  
  Should(Length(Arr)).Be(2);
  Should(Arr[0]).Be(10);
  Should(Arr[1]).Be(20);
end;

end.
