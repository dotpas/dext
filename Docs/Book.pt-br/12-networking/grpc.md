# gRPC & Protocol Buffers (Integração gRPC)

O Dext Framework oferece uma pilha de comunicação binária baseada no protocolo de mensagens gRPC e em Protocol Buffers (proto3): serviços code-first declarados como interfaces Delphi, um despachante que os chama e um cliente que chama o despachante no mesmo processo ou por HTTP.

---

## 1. Arquitetura

1. **Serialização** (`Dext.Serialization.Protobuf`): o `TProtobufSerializer` escreve e lê mensagens proto3 de classes cujas propriedades têm `[ProtoMember(n)]`.
2. **Codec** (`Dext.Grpc.Codec`): o `TGrpcMessageCodec` enquadra a mensagem como uma Length-Prefixed Message do gRPC (1 byte de flags, 4 bytes de tamanho em big-endian, depois a carga).
3. **Servidor** (`Dext.Web.Grpc.Server`): o `TDextGrpcDispatcher` transforma um pedido para `/<serviço>/<método>` numa chamada ao serviço registrado. Ele não mapeia rotas sozinho: a aplicação mapeia uma rota POST para `Dispatcher.Invoke`.
4. **Cliente e DataSet** (`Dext.Entity.GrpcProvider`): o `TGrpcClient` chama um despachante no mesmo processo, ou faz POST em `http://host:porta/<serviço>/<método>`. O `TEntitygRpcProvider<T>` carrega uma lista de entidades pelo cliente.

---

## 2. Mensagens e Serviços

Uma mensagem é uma classe marcada com `[GrpcMessage]`, com `[ProtoMember(n)]` em cada propriedade. Uma lista é uma propriedade `IList<T>`, escrita como campo repetido.

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

Cada método recebe uma classe de mensagem e devolve uma classe de mensagem. O nome do método no gRPC é o nome em Delphi; `[GrpcMethod('Nome')]` o troca. Um método com outra assinatura faz o `RegisterService` levantar `EArgumentException`.

## 3. Servidor

Registre o serviço num despachante e mapeie uma rota para ele:

```pascal
Dispatcher := TDextGrpcDispatcher.Create;
Dispatcher.RegisterService<IUserService>(TUserService);

App.GetApplicationBuilder.MapPost('/dext.services.UserService/GetUser',
  procedure(Ctx: IHttpContext)
  begin
    Dispatcher.Invoke(Ctx);
  end);
```

`RegisterService(IUserService, TUserService)` (pelo GUID) procura a interface na RTTI do programa, e não acha uma interface declarada no próprio `.dpr`; a sobrecarga genérica funciona em qualquer lugar. As duas levantam `EArgumentException` quando a interface não é achada, quando o serviço já está registrado ou quando um método tem assinatura não suportada.

A resposta é sempre HTTP 200, com o resultado em `grpc-status` e `grpc-message`: `0` para sucesso, `12` (UNIMPLEMENTED) para serviço ou método desconhecido, `13` (INTERNAL) quando o serviço levanta uma exceção. A mensagem da exceção vai para o cliente.

## 4. Cliente

```pascal
Client := TGrpcClient.Create('localhost', 8080);
Client.CallMethod('dext.services.UserService', 'GetUser', Request, Response);
```

`TGrpcClient.Create(Dispatcher)` chama o despachante no mesmo processo, sem rede. Um status diferente de `0` levanta uma `Exception` com o status e a mensagem.

## 5. Entidades por gRPC

`TEntitygRpcProvider<T>.FetchAll` chama o método `FetchAll` do serviço e espera uma resposta com os itens no campo repetido 1. Ele devolve uma `TList<T>` cujos itens pertencem a quem chamou.

`ApplyChanges` não está implementado e levanta `ENotSupportedException`. Para gravar as mudanças de um `TEntityDataSet`, envie o `Changes` numa chamada de serviço própria.

## 6. Não Verificado

A pilha foi exercitada no mesmo processo, e os bytes do Protobuf foram comparados com a especificação do proto3. O uso com um cliente ou servidor gRPC de outra pilha (HTTP/2, trailers) não foi verificado.
