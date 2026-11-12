{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2026 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
{                                                                           }
{  Author:  Cesar Romero & Dext Contributors                                }
{  Created: 2026-07-07                                                      }
{                                                                           }
{  Description:                                                             }
{    Unit tests for gRPC, Protobuf, and dispatcher subsystems.              }
{                                                                           }
{***************************************************************************}
unit Dext.Grpc.Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Dext.Collections,
  Dext.Testing,
  Dext.Grpc.Attributes,
  Dext.Grpc.Codec,
  Dext.Core.Span,
  Dext.Serialization.Protobuf,
  Dext.Web.Grpc.Server,
  Dext.Entity.GrpcProvider;

type
  [GrpcMessage]
  TDummyRequest = class
  private
    FMessage: string;
    FValue: Integer;
  public
    [ProtoMember(1)]
    property Message: string read FMessage write FMessage;
    [ProtoMember(2)]
    property Value: Integer read FValue write FValue;
  end;

  [GrpcMessage]
  TDummyResponse = class
  private
    FResult: string;
    FSuccess: Boolean;
  public
    [ProtoMember(1)]
    property Result: string read FResult write FResult;
    [ProtoMember(2)]
    property Success: Boolean read FSuccess write FSuccess;
  end;

  [GrpcService('dext.test.v1.DummyService')]
  IDummyService = interface(IInvokable)
    ['{E8F8B6C7-674A-4835-AB37-A3BA476C55AF}']
    [GrpcMethod('DummyCall')]
    function DummyCall(const ARequest: TDummyRequest): TDummyResponse;
  end;

  TDummyService = class(TInterfacedObject, IDummyService)
  public
    function DummyCall(const ARequest: TDummyRequest): TDummyResponse;
  end;

  [GrpcMessage]
  TCatalogQuery = class
  private
    FFilter: string;
  public
    [ProtoMember(1)]
    property Filter: string read FFilter write FFilter;
  end;

  [GrpcMessage]
  TCatalogItem = class
  private
    FId: Integer;
    FName: string;
  public
    [ProtoMember(1)]
    property Id: Integer read FId write FId;
    [ProtoMember(2)]
    property Name: string read FName write FName;
  end;

  [GrpcMessage]
  TCatalogItems = class
  private
    FItems: IList<TCatalogItem>;
  public
    constructor Create;
    [ProtoMember(1)]
    property Items: IList<TCatalogItem> read FItems write FItems;
  end;

  // The methods carry no [GrpcMethod]: the Delphi name is the gRPC name.
  [GrpcService('dext.test.v1.Catalog')]
  ICatalogService = interface(IInvokable)
    ['{6D0C4F43-2B5E-4C57-9E6B-0B1E4C6A9A11}']
    function FetchAll(const ARequest: TCatalogQuery): TCatalogItems;
    function Failing(const ARequest: TCatalogQuery): TCatalogItems;
  end;

  TCatalogService = class(TInterfacedObject, ICatalogService)
  public
    function FetchAll(const ARequest: TCatalogQuery): TCatalogItems;
    function Failing(const ARequest: TCatalogQuery): TCatalogItems;
  end;

  [TestFixture('gRPC & Protobuf Infrastructure')]
  TGrpcTests = class
  public
    [Test]
    procedure Test_Protobuf_Serialization_Deserialization;
    [Test]
    procedure Test_Grpc_Lpm_Codec;
    [Test]
    procedure Test_Grpc_Lpm_EncodeInto;
    [Test]
    procedure Test_Grpc_Lpm_FrameInPlace;
    [Test]
    procedure Test_Protobuf_SerializeToStream;
    [Test]
    procedure Test_EndToEnd_Grpc_Dispatcher_And_Client;
    [Test]
    procedure Test_Wire_Format_Matches_The_Protobuf_Spec;
    [Test]
    procedure Test_Negative_Int32_Takes_Ten_Bytes;
    [Test]
    procedure Test_RegisterService_Unknown_Interface_Raises;
    [Test]
    procedure Test_RegisterService_Twice_Raises;
    [Test]
    procedure Test_RegisterService_Generic_Overload;
    [Test]
    procedure Test_Method_Without_GrpcMethod_Uses_Its_Own_Name;
    [Test]
    procedure Test_Unknown_Service_Reports_Unimplemented;
    [Test]
    procedure Test_Unknown_Method_Reports_Unimplemented;
    [Test]
    procedure Test_Server_Error_Reports_Status_13;
    [Test]
    procedure Test_Provider_FetchAll_Returns_The_Server_Items;
    [Test]
    procedure Test_Provider_ApplyChanges_Is_Not_Silent;
  end;

implementation

{ TDummyService }

function TDummyService.DummyCall(
  const ARequest: TDummyRequest): TDummyResponse;
begin
  Result := TDummyResponse.Create;
  Result.Result := 'Echo: ' + ARequest.Message + ' with value ' +
    IntToStr(ARequest.Value);
  Result.Success := True;
end;

{ TCatalogItems }

constructor TCatalogItems.Create;
begin
  inherited Create;
  FItems := TCollections.CreateList<TCatalogItem>(True);
end;

{ TCatalogService }

function TCatalogService.FetchAll(
  const ARequest: TCatalogQuery): TCatalogItems;
var
  Item: TCatalogItem;
begin
  Result := TCatalogItems.Create;
  Item := TCatalogItem.Create;
  Item.Id := 1;
  Item.Name := 'Alpha';
  Result.Items.Add(Item);
  Item := TCatalogItem.Create;
  Item.Id := 2;
  Item.Name := 'Beta';
  Result.Items.Add(Item);
end;

function TCatalogService.Failing(
  const ARequest: TCatalogQuery): TCatalogItems;
begin
  raise Exception.Create('catalog is offline');
end;

{ TGrpcTests }

procedure TGrpcTests.Test_Protobuf_Serialization_Deserialization;
var
  Req: TDummyRequest;
  Res: TDummyRequest;
  Bytes: TBytes;
begin
  Req := TDummyRequest.Create;
  Req.Message := 'Hello Protobuf';
  Req.Value := 12345;
  try
    Bytes := TProtobufSerializer.Serialize(Req);
    Should(Length(Bytes)).BeGreaterThan(0);

    Res := TDummyRequest.Create;
    try
      TProtobufSerializer.Deserialize(Bytes, Res);
      Should(Res.Message).Be('Hello Protobuf');
      Should(Res.Value).Be(12345);
    finally
      Res.Free;
    end;
  finally
    Req.Free;
  end;
end;

procedure TGrpcTests.Test_Grpc_Lpm_Codec;
var
  Payload: TBytes;
  Framed: TBytes;
  Decoded: TBytes;
  Offset: Integer;
  Compressed: Boolean;
begin
  SetLength(Payload, 4);
  Payload[0] := $AA;
  Payload[1] := $BB;
  Payload[2] := $CC;
  Payload[3] := $DD;

  Framed := TGrpcMessageCodec.Encode(Payload, False);
  Should(Length(Framed)).Be(9);
  Should(Framed[0]).Be(0); // Uncompressed
  Should(Framed[4]).Be(4); // Length 4

  Offset := 0;
  Should(TGrpcMessageCodec.TryDecode(
    Framed, Offset, Compressed, Decoded)).BeTrue;
  Should(Offset).Be(9);
  Should(Compressed).BeFalse;
  Should(Length(Decoded)).Be(4);
  Should(Decoded[0]).Be($AA);
end;

procedure TGrpcTests.Test_Grpc_Lpm_EncodeInto;
var
  Payload: TBytes;
  Framed: TBytes;
  Span: TByteSpan;
begin
  SetLength(Payload, 4);
  Payload[0] := $AA;
  Payload[1] := $BB;
  Payload[2] := $CC;
  Payload[3] := $DD;
  Span := TByteSpan.Create(@Payload[0], Length(Payload));
  Should(TGrpcMessageCodec.EncodeInto(Span, Framed)).Be(9);
  Should(Length(Framed)).Be(9);
  Should(Framed[0]).Be(0);
  Should(Framed[4]).Be(4);
  Should(Framed[5]).Be($AA);
end;

procedure TGrpcTests.Test_Grpc_Lpm_FrameInPlace;
var
  Framed: TBytes;
begin
  SetLength(Framed, 4);
  Framed[0] := $AA;
  Framed[1] := $BB;
  Framed[2] := $CC;
  Framed[3] := $DD;
  Should(TGrpcMessageCodec.FrameInPlace(Framed)).Be(9);
  Should(Length(Framed)).Be(9);
  Should(Framed[0]).Be(0);
  Should(Framed[4]).Be(4);
  Should(Framed[5]).Be($AA);
  Should(Framed[8]).Be($DD);
end;

procedure TGrpcTests.Test_Protobuf_SerializeToStream;
var
  Obj: TDummyRequest;
  Expected: TBytes;
  Stream: TBytesStream;
  Actual: TBytes;
begin
  Obj := TDummyRequest.Create;
  try
    Obj.Message := 'stream';
    Obj.Value := 7;
    Expected := TProtobufSerializer.Serialize(Obj, pcmRtti);
    Stream := TBytesStream.Create(nil);
    try
      TProtobufSerializer.SerializeToStream(Obj, Stream, pcmRtti);
      Actual := Stream.Bytes;
      SetLength(Actual, Stream.Size);
      Should(Length(Actual)).Be(Length(Expected));
      if Length(Expected) > 0 then
        Should(CompareMem(@Actual[0], @Expected[0], Length(Expected))).BeTrue;
    finally
      Stream.Free;
    end;
  finally
    Obj.Free;
  end;
end;

procedure TGrpcTests.Test_EndToEnd_Grpc_Dispatcher_And_Client;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Req: TDummyRequest;
  Res: TDummyResponse;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService(IDummyService, TDummyService);
    Client := TGrpcClient.Create(Dispatcher);
    try
      Req := TDummyRequest.Create;
      Req.Message := 'Test Call';
      Req.Value := 42;
      Res := TDummyResponse.Create;
      try
        Client.CallMethod('dext.test.v1.DummyService', 'DummyCall', Req, Res);
        Should(Res.Success).BeTrue;
        Should(Res.Result).Be('Echo: Test Call with value 42');
      finally
        Req.Free;
        Res.Free;
      end;
    finally
      Client.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Wire_Format_Matches_The_Protobuf_Spec;
var
  Req: TDummyRequest;
  Bytes: TBytes;
begin
  Req := TDummyRequest.Create;
  try
    Req.Message := 'Hello';
    Req.Value := 12345;
    Bytes := TProtobufSerializer.Serialize(Req);
  finally
    Req.Free;
  end;

  // Field 1, length-delimited: tag 0A, length 5, "Hello".
  // Field 2, varint: tag 10, 12345 = B9 60.
  Should(Length(Bytes)).Be(10);
  Should(Bytes[0]).Be($0A);
  Should(Bytes[1]).Be(5);
  Should(Bytes[2]).Be(Ord('H'));
  Should(Bytes[6]).Be(Ord('o'));
  Should(Bytes[7]).Be($10);
  Should(Bytes[8]).Be($B9);
  Should(Bytes[9]).Be($60);
end;

procedure TGrpcTests.Test_Negative_Int32_Takes_Ten_Bytes;
var
  Req: TDummyRequest;
  Bytes: TBytes;
  I: Integer;
begin
  Req := TDummyRequest.Create;
  try
    Req.Message := 'x';
    Req.Value := -1;
    Bytes := TProtobufSerializer.Serialize(Req);
  finally
    Req.Free;
  end;

  // A negative int32 is sign-extended to 64 bits: nine FF bytes and a 01.
  Should(Length(Bytes)).Be(14);
  Should(Bytes[3]).Be($10);
  for I := 4 to 12 do
    Should(Bytes[I]).Be($FF);
  Should(Bytes[13]).Be($01);
end;

procedure TGrpcTests.Test_RegisterService_Unknown_Interface_Raises;
var
  Dispatcher: TDextGrpcDispatcher;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Should(procedure
      begin
        Dispatcher.RegisterService(
          StringToGUID('{11111111-2222-3333-4444-555555555555}'),
          TDummyService);
      end).Throw<EArgumentException>;
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_RegisterService_Twice_Raises;
var
  Dispatcher: TDextGrpcDispatcher;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService(IDummyService, TDummyService);
    Should(procedure
      begin
        Dispatcher.RegisterService(IDummyService, TDummyService);
      end).Throw<EArgumentException>;
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_RegisterService_Generic_Overload;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Req: TDummyRequest;
  Res: TDummyResponse;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService<IDummyService>(TDummyService);
    Client := TGrpcClient.Create(Dispatcher);
    Req := TDummyRequest.Create;
    Res := TDummyResponse.Create;
    try
      Req.Message := 'generic';
      Client.CallMethod('dext.test.v1.DummyService', 'DummyCall', Req, Res);
      Should(Res.Result).Be('Echo: generic with value 0');
    finally
      Req.Free;
      Res.Free;
      Client.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Method_Without_GrpcMethod_Uses_Its_Own_Name;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Req: TCatalogQuery;
  Res: TCatalogItems;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService(ICatalogService, TCatalogService);
    Client := TGrpcClient.Create(Dispatcher);
    Req := TCatalogQuery.Create;
    Res := TCatalogItems.Create;
    try
      Client.CallMethod('dext.test.v1.Catalog', 'FetchAll', Req, Res);
      Should(Res.Items.Count).Be(2);
      Should(Res.Items[1].Name).Be('Beta');
    finally
      Req.Free;
      Res.Free;
      Client.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Unknown_Service_Reports_Unimplemented;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Req: TCatalogQuery;
  Res: TCatalogItems;
  Msg: string;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Client := TGrpcClient.Create(Dispatcher);
    Req := TCatalogQuery.Create;
    Res := TCatalogItems.Create;
    Msg := '';
    try
      try
        Client.CallMethod('no.Such', 'Method', Req, Res);
      except
        on E: Exception do
          Msg := E.Message;
      end;
    finally
      Req.Free;
      Res.Free;
      Client.Free;
    end;
    Should(Msg).Contain('Status: 12');
    Should(Msg).Contain('no.Such');
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Unknown_Method_Reports_Unimplemented;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Req: TCatalogQuery;
  Res: TCatalogItems;
  Msg: string;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService(ICatalogService, TCatalogService);
    Client := TGrpcClient.Create(Dispatcher);
    Req := TCatalogQuery.Create;
    Res := TCatalogItems.Create;
    Msg := '';
    try
      try
        Client.CallMethod('dext.test.v1.Catalog', 'Missing', Req, Res);
      except
        on E: Exception do
          Msg := E.Message;
      end;
    finally
      Req.Free;
      Res.Free;
      Client.Free;
    end;
    Should(Msg).Contain('Status: 12');
    Should(Msg).Contain('Missing');
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Server_Error_Reports_Status_13;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Req: TCatalogQuery;
  Res: TCatalogItems;
  Msg: string;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService(ICatalogService, TCatalogService);
    Client := TGrpcClient.Create(Dispatcher);
    Req := TCatalogQuery.Create;
    Res := TCatalogItems.Create;
    Msg := '';
    try
      try
        Client.CallMethod('dext.test.v1.Catalog', 'Failing', Req, Res);
      except
        on E: Exception do
          Msg := E.Message;
      end;
    finally
      Req.Free;
      Res.Free;
      Client.Free;
    end;
    Should(Msg).Contain('Status: 13');
    Should(Msg).Contain('catalog is offline');
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Provider_FetchAll_Returns_The_Server_Items;
var
  Dispatcher: TDextGrpcDispatcher;
  Client: TGrpcClient;
  Provider: IEntityDataProvider<TCatalogItem>;
  Items: TList<TCatalogItem>;
  Item: TCatalogItem;
begin
  Dispatcher := TDextGrpcDispatcher.Create;
  try
    Dispatcher.RegisterService(ICatalogService, TCatalogService);
    Client := TGrpcClient.Create(Dispatcher);
    try
      Provider := TEntitygRpcProvider<TCatalogItem>.Create(
        Client, 'dext.test.v1.Catalog');
      Items := Provider.FetchAll('');
      try
        Should(Items.Count).Be(2);
        Should(Items[0].Name).Be('Alpha');
        Should(Items[1].Id).Be(2);
      finally
        for Item in Items do
          Item.Free;
        Items.Free;
      end;
    finally
      Provider := nil;
      Client.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TGrpcTests.Test_Provider_ApplyChanges_Is_Not_Silent;
var
  Client: TGrpcClient;
  Provider: IEntityDataProvider<TCatalogItem>;
  List: TList<TCatalogItem>;
begin
  Client := TGrpcClient.Create('localhost', 1);
  List := TList<TCatalogItem>.Create;
  try
    Provider := TEntitygRpcProvider<TCatalogItem>.Create(
      Client, 'dext.test.v1.Catalog');
    Should(procedure
      begin
        Provider.ApplyChanges(List);
      end).Throw<ENotSupportedException>;
  finally
    Provider := nil;
    List.Free;
    Client.Free;
  end;
end;

end.
