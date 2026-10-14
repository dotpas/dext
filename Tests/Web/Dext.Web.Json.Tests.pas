unit Dext.Web.Json.Tests;

interface

uses
  Dext.Testing.Attributes,
  Dext.Testing.Fluent,
  Dext.Testing,
  Dext.Types.Nullable,
  Dext.Json,
  System.SysUtils;

type
  [TestClass]
  TJsonNullableTests = class
  private
    type
      TPerson = record
        Id: Integer;
        PersonParentId: Nullable<Integer>;
        Name: string;
        Email: Nullable<string>;
        CreatedAt: TDateTime;
        UpdatedAt: Nullable<TDateTime>;
      end;
  public
    [Test]
    procedure Should_Serialize_Nullable_Fields_As_Null_When_Empty;
    [Test]
    procedure Should_Serialize_Nullable_Fields_With_Values;
    [Test]
    procedure Should_Skip_Nullable_Fields_When_Empty_And_IgnoreNullValues_Is_True;
  end;

implementation

uses
  Dext.Core.DateUtils;

{ TJsonNullableTests }

procedure TJsonNullableTests.Should_Serialize_Nullable_Fields_As_Null_When_Empty;
var
  Person: TPerson;
  Json: string;
begin
  Person.Id := 1;
  Person.PersonParentId.Clear;
  Person.Name := 'John Doe';
  Person.Email.Clear;
  Person.CreatedAt := EncodeDate(2026, 3, 28) + EncodeTime(9, 50, 2, 0);
  Person.UpdatedAt.Clear;

  Json := TDextJson.Serialize<TPerson>(Person, TJsonSettings.Default.Indented);

  // Expected JSON should contain null for nullable fields with no value
  // Instead of 0, "", or "1899-12-30T00:00:00.000"
  
  Should(Json).Contain('"PersonParentId": null');
  Should(Json).Contain('"Email": null');
  Should(Json).Contain('"UpdatedAt": null');
  
  // Verify non-nullable/valued fields
  Should(Json).Contain('"Id": 1');
  Should(Json).Contain('"Name": "John Doe"');
end;

procedure TJsonNullableTests.Should_Serialize_Nullable_Fields_With_Values;
var
  Person: TPerson;
  Json: string;
begin
  Person.Id := 1;
  Person.PersonParentId := 10;
  Person.Name := 'John Doe';
  Person.Email := 'john@dext.com';
  Person.CreatedAt := EncodeDate(2026, 3, 28) + EncodeTime(9, 50, 2, 0);
  Person.UpdatedAt := EncodeDate(2026, 3, 29) + EncodeTime(10, 0, 0, 0);

  Json := TDextJson.Serialize<TPerson>(Person, TJsonSettings.Default.Indented);

  Should(Json).Contain('"PersonParentId": 10');
  Should(Json).Contain('"Email": "john@dext.com"');
  Should(Json).Contain('"UpdatedAt": "' +
    FormatJsonDateTime(EncodeDate(2026, 3, 29) + EncodeTime(10, 0, 0, 0)) + '"');
end;

procedure TJsonNullableTests.Should_Skip_Nullable_Fields_When_Empty_And_IgnoreNullValues_Is_True;
var
  Person: TPerson;
  Json: string;
begin
  Person.Id := 1;
  Person.PersonParentId.Clear;
  Person.Name := 'John Doe';
  Person.Email.Clear;
  Person.CreatedAt := EncodeDate(2026, 3, 28) + EncodeTime(9, 50, 2, 0);
  Person.UpdatedAt.Clear;

  Json := TDextJson.Serialize<TPerson>(Person, TJsonSettings.Default.IgnoreNullValues);

  Should(Json).NotContain('"PersonParentId"');
  Should(Json).NotContain('"Email"');
  Should(Json).NotContain('"UpdatedAt"');
end;

end.
