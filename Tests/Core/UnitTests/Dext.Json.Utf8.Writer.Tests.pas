{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{***************************************************************************}

unit Dext.Json.Utf8.Writer.Tests;

interface

uses
  Dext.Testing.Attributes,
  Dext.Assertions,
  System.Classes,
  System.SysUtils,
  Dext.Json.Utf8;

type
  [TestFixture('UTF-8 JSON Writer')]
  TUtf8JsonWriterTests = class
  private
    function StreamText(AStream: TMemoryStream): string;
  public
    [Test]
    procedure ShouldWriteAsciiEscapesWithoutChangingSemantics;
    [Test]
    procedure ShouldWriteUnicodeStrings;
    [Test]
    procedure ShouldWriteInt64Limits;
    [Test]
    procedure ShouldWriteDoubleNumbers;
  end;

implementation

function TUtf8JsonWriterTests.StreamText(AStream: TMemoryStream): string;
var
  Bytes: TBytes;
begin
  SetLength(Bytes, AStream.Size);
  if AStream.Size > 0 then
  begin
    AStream.Position := 0;
    AStream.ReadBuffer(Bytes[0], Length(Bytes));
  end;
  Result := TEncoding.UTF8.GetString(Bytes);
end;

procedure TUtf8JsonWriterTests.ShouldWriteAsciiEscapesWithoutChangingSemantics;
var
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
begin
  Stream := TMemoryStream.Create;
  try
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteString('a"b\c'#8#9#10#12#13#1);
    Should(StreamText(Stream)).Be('"a\"b\\c\b\t\n\f\r\u0001"');
  finally
    Stream.Free;
  end;
end;

procedure TUtf8JsonWriterTests.ShouldWriteUnicodeStrings;
var
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
begin
  Stream := TMemoryStream.Create;
  try
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteString('ação 😀');
    Should(StreamText(Stream)).Be('"ação 😀"');
  finally
    Stream.Free;
  end;
end;

procedure TUtf8JsonWriterTests.ShouldWriteInt64Limits;
var
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
begin
  Stream := TMemoryStream.Create;
  try
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteStartArray;
    Writer.WriteNumber(Low(Int64));
    Writer.WriteNumber(High(Int64));
    Writer.WriteEndArray;
    Should(StreamText(Stream)).Be(
      '[-9223372036854775808,9223372036854775807]');
  finally
    Stream.Free;
  end;
end;

procedure TUtf8JsonWriterTests.ShouldWriteDoubleNumbers;
var
  Stream: TMemoryStream;
  Writer: TUtf8JsonWriter;
begin
  Stream := TMemoryStream.Create;
  try
    Writer := TUtf8JsonWriter.Create(Stream);
    Writer.WriteStartArray;
    Writer.WriteNumber(0.0);
    Writer.WriteNumber(123.456);
    Writer.WriteNumber(-0.5);
    Writer.WriteEndArray;
    Should(StreamText(Stream)).Be('[0,123.456,-0.5]');
  finally
    Stream.Free;
  end;
end;

end.
