# gRPC & Protocol Buffers (gRPC Integration)

The Dext Framework provides a binary communication stack based on the gRPC message protocol and Protocol Buffers (proto3): code-first services declared as Delphi interfaces, a dispatcher that calls them, and a client that calls the dispatcher in-process or over HTTP.

---

## 1. Core Architecture

1. **Serialization Layer** (`Dext.Serialization.Protobuf`): `TProtobufSerializer` writes and reads proto3 messages from classes whose properties carry `[ProtoMember(n)]`.
2. **Codec Layer** (`Dext.Grpc.Codec`): `TGrpcMessageCodec` frames a message as a gRPC Length-Prefixed Message (1 byte of flags, 4 bytes of big-endian length, then the payload).
3. **Server Layer** (`Dext.Web.Grpc.Server`): `TDextGrpcDispatcher` turns a request for `/<service>/<method>` into a call on a registered service. It does not map routes by itself: the application maps a POST route to `Dispatcher.Invoke`.
4. **Client & DataSet Integration** (`Dext.Entity.GrpcProvider`): `TGrpcClient` calls a dispatcher in-process, or posts to `http://host:port/<service>/<method>`. `TEntitygRpcProvider<T>` loads a list of entities through the client.

---

## 2. Messages and Services

A message is a class marked `[GrpcMessage]`, with `[ProtoMember(n)]` on each property. A list is an `IList<T>` property, written as a repeated field.

```pascal
type
  [GrpcMessage]
  TUserRequest = class
  private
    FId: Integer;
  public
    [ProtoMember(1)]
    property Id: Integer read FId write FId;
  end;

  [GrpcService('dext.services.UserService')]
  IUserService = interface(IInvokable)
    ['{A1B2C3D4-E5F6-7A8B-9C0D-1E2F3A4B5C6D}']
    function GetUser(const ARequest: TUserRequest): TUserResponse;
  end;
```

Each method takes one message class and returns one message class. The gRPC method name is the Delphi name; `[GrpcMethod('Name')]` renames it. A method with another signature makes `RegisterService` raise `EArgumentException`.

## 3. Server

Register the service on a dispatcher, and map a route to it:

```pascal
Dispatcher := TDextGrpcDispatcher.Create;
Dispatcher.RegisterService<IUserService>(TUserService);

App.GetApplicationBuilder.MapPost('/dext.services.UserService/GetUser',
  procedure(Ctx: IHttpContext)
  begin
    Dispatcher.Invoke(Ctx);
  end);
```

`RegisterService(IUserService, TUserService)` (by GUID) searches the RTTI of the program, and does not find an interface declared in the `.dpr` itself; the generic overload works anywhere. Both raise `EArgumentException` when the interface is not found, when the service is already registered, or when a method has an unsupported signature.

The answer is always HTTP 200, with the result in `grpc-status` and `grpc-message`: `0` for success, `12` (UNIMPLEMENTED) for an unknown service or method, `13` (INTERNAL) when the service raises an exception. The message of the exception goes to the client.

## 4. Client

```pascal
Client := TGrpcClient.Create('localhost', 8080);
Client.CallMethod('dext.services.UserService', 'GetUser', Request, Response);
```

`TGrpcClient.Create(Dispatcher)` calls the dispatcher in-process, with no network. A status other than `0` raises an `Exception` with the status and message.

## 5. Entities Over gRPC

`TEntitygRpcProvider<T>.FetchAll` calls the method `FetchAll` of the service and expects a reply with the items as repeated field 1. It returns a `TList<T>` whose items the caller owns.

`ApplyChanges` is not implemented and raises `ENotSupportedException`. To save the changes of a `TEntityDataSet`, send `Changes` with a service call of your own.

## 6. Not Verified

The stack was exercised in-process, and the Protobuf bytes were compared with the proto3 specification. Its use with a gRPC client or server from another stack (HTTP/2, trailers) was not verified.
