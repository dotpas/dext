unit Dext.Json.CollectionGuard.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Collections,
  Dext.Json;

type
  TJsonInterfaceItem = class
  private
    FName: string;
  public
    property Name: string read FName write FName;
  end;

  [TestFixture('JSON - SerializeUtf8(IInterface) with a collection')]
  TJsonInterfaceTests = class
  public
    [Test('A list passed as IInterface is refused, not written as {}')]
    procedure List_AsInterface_IsRefused;
    [Test('The refusal names the generic overload to use')]
    procedure Refusal_NamesTheGenericOverload;
    [Test('The generic overload writes the list as an array')]
    procedure List_WithExplicitType_IsAnArray;
  end;

implementation

function NewList: IList<TJsonInterfaceItem>;
var
  Item: TJsonInterfaceItem;
begin
  Result := TCollections.CreateObjectList<TJsonInterfaceItem>(True);
  Item := TJsonInterfaceItem.Create;
  Item.Name := 'a';
  Result.Add(Item);
end;

procedure TJsonInterfaceTests.List_AsInterface_IsRefused;
var
  List: IList<TJsonInterfaceItem>;
begin
  List := NewList;
  Should(procedure
    begin
      TDextJson.SerializeUtf8(List);
    end).Throw<EDextJsonException>;
end;

procedure TJsonInterfaceTests.Refusal_NamesTheGenericOverload;
var
  List: IList<TJsonInterfaceItem>;
  Msg: string;
begin
  List := NewList;
  Msg := '';
  try
    TDextJson.SerializeUtf8(List);
  except
    on E: EDextJsonException do
      Msg := E.Message;
  end;
  Should(Msg).Contain('SerializeUtf8<');
end;

procedure TJsonInterfaceTests.List_WithExplicitType_IsAnArray;
var
  List: IList<TJsonInterfaceItem>;
  Json: string;
begin
  List := NewList;
  Json := TEncoding.UTF8.GetString(
    TDextJson.SerializeUtf8<IList<TJsonInterfaceItem>>(List));
  Should(Json).Be('[{"Name":"a"}]');
end;

end.
