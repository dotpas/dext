unit Dext.Json.Nullable.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types,
  Dext.Core.DateUtils,
  Dext.Types.Nullable;

type
  /// Nullable properties backed by their F<Name> field: the plan reads them
  /// on the direct path.
  TJsonNullableRow = class
  private
    FCount: Nullable<Integer>;
    FBig: Nullable<Int64>;
    FName: Nullable<string>;
    FAmount: Nullable<Double>;
    FActive: Nullable<Boolean>;
    FWhen: Nullable<TDateTime>;
  public
    property Count: Nullable<Integer> read FCount write FCount;
    property Big: Nullable<Int64> read FBig write FBig;
    property Name: Nullable<string> read FName write FName;
    property Amount: Nullable<Double> read FAmount write FAmount;
    property Active: Nullable<Boolean> read FActive write FActive;
    property When: Nullable<TDateTime> read FWhen write FWhen;
  end;

  /// The same Nullable behind a getter: no backing field by name, so the
  /// RTTI path. Used as the reference for the direct path.
  TJsonNullableGetterRow = class
  private
    FValue: Nullable<Integer>;
    function GetCount: Nullable<Integer>;
  public
    property Count: Nullable<Integer> read GetCount write FValue;
  end;

  [TestFixture('JSON - Nullable properties on the direct path')]
  TJsonNullableTests = class
  public
    [Test('A Nullable without a value is written as null, not as 0, '''' or false')]
    procedure NoValue_WrittenAsNull;
    [Test('A Nullable without a value is dropped with IgnoreNullValues')]
    procedure NoValue_WithIgnoreNullValues_Dropped;
    [Test('A Nullable holding the default (0, '''', false) has a value and is written')]
    procedure DefaultValue_IsAValue;
    [Test('A Nullable with a value is written as that value')]
    procedure Value_Written;
    [Test('Backing field and getter give the same JSON')]
    procedure FieldAndGetter_SameJson;
  end;

implementation

{ TJsonNullableGetterRow }

function TJsonNullableGetterRow.GetCount: Nullable<Integer>;
begin
  Result := FValue;
end;

{ TJsonNullableTests }

procedure TJsonNullableTests.NoValue_WrittenAsNull;
var
  R: TJsonNullableRow;
  Json: string;
begin
  R := TJsonNullableRow.Create; // no value anywhere
  try
    Json := TDextJson.Serialize(R);
    // Before: the direct path read the inner value and wrote 0, '', false.
    Should(Json).Contain('"Count":null');
    Should(Json).Contain('"Big":null');
    Should(Json).Contain('"Name":null');
    Should(Json).Contain('"Amount":null');
    Should(Json).Contain('"Active":null');
    Should(Json).Contain('"When":null');
  finally
    R.Free;
  end;
end;

procedure TJsonNullableTests.NoValue_WithIgnoreNullValues_Dropped;
var
  R: TJsonNullableRow;
begin
  R := TJsonNullableRow.Create;
  try
    Should(TDextJson.Serialize(R, TJsonSettings.Default.IgnoreNullValues)).Be('{}');
  finally
    R.Free;
  end;
end;

procedure TJsonNullableTests.DefaultValue_IsAValue;
var
  R: TJsonNullableRow;
  Json: string;
begin
  R := TJsonNullableRow.Create;
  try
    R.Count := Nullable<Integer>.Create(0);
    R.Name := Nullable<string>.Create('');
    R.Active := Nullable<Boolean>.Create(False);
    Json := TDextJson.Serialize(R);
    Should(Json).Contain('"Count":0');
    Should(Json).Contain('"Name":""');
    Should(Json).Contain('"Active":false');
    // the ones never set stay null
    Should(Json).Contain('"Big":null');
  finally
    R.Free;
  end;
end;

procedure TJsonNullableTests.Value_Written;
var
  R: TJsonNullableRow;
  Json: string;
begin
  R := TJsonNullableRow.Create;
  try
    R.Count := Nullable<Integer>.Create(7);
    R.Big := Nullable<Int64>.Create(9007199254740993);
    R.Name := Nullable<string>.Create('x');
    R.Amount := Nullable<Double>.Create(1.5);
    R.Active := Nullable<Boolean>.Create(True);
    R.When := Nullable<TDateTime>.Create(EncodeDate(2026, 10, 8) +
      EncodeTime(13, 45, 0, 0));
    Json := TDextJson.Serialize(R);
    Should(Json).Contain('"Count":7');
    Should(Json).Contain('"Big":9007199254740993');
    Should(Json).Contain('"Name":"x"');
    Should(Json).Contain('"Amount":1.5');
    Should(Json).Contain('"Active":true');
    Should(Json).Contain('"When":"' + FormatJsonDateTime(EncodeDate(2026, 10, 8) + EncodeTime(13, 45, 0, 0)) + '"');
  finally
    R.Free;
  end;
end;

procedure TJsonNullableTests.FieldAndGetter_SameJson;
var
  F: TJsonNullableRow;
  G: TJsonNullableGetterRow;
begin
  F := TJsonNullableRow.Create;
  G := TJsonNullableGetterRow.Create;
  try
    // only Count, so that both classes have the same shape
    Should(TDextJson.Serialize(F, TJsonSettings.Default.IgnoreNullValues))
      .Be(TDextJson.Serialize(G, TJsonSettings.Default.IgnoreNullValues));
    F.Count := Nullable<Integer>.Create(0);
    G.Count := Nullable<Integer>.Create(0);
    Should(TDextJson.Serialize(F, TJsonSettings.Default.IgnoreNullValues))
      .Be(TDextJson.Serialize(G, TJsonSettings.Default.IgnoreNullValues));
  finally
    G.Free;
    F.Free;
  end;
end;

end.
