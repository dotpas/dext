# Rotas

Defina padrões de URL e extraia parâmetros.

## Padrões de Rota

### Rotas Estáticas

```pascal
App.MapGet('/users', Handler);           // GET /users
App.MapPost('/users', Handler);          // POST /users
App.MapGet('/api/health', Handler);      // GET /api/health
```

### Parâmetros de Rota

```pascal
App.MapGet('/users/{id}', procedure(Ctx: IHttpContext)
  begin
    var Id := Ctx.Request.RouteParams['id'];
    // Id = "123" para /users/123
  end);

App.MapGet('/orders/{orderId}/items/{itemId}', procedure(Ctx: IHttpContext)
  begin
    var OrderId := Ctx.Request.RouteParams['orderId'];
    var ItemId := Ctx.Request.RouteParams['itemId'];
  end);
```

## Rotas em Controllers

### Rota a Nível de Classe

```pascal
[Route('/api/v1/users')]
TUsersController = class(TController)
public
  [HttpGet]             // GET /api/v1/users
  function GetAll: IActionResult;
  
  [HttpGet('/{id}')]     // GET /api/v1/users/123
  function GetById(Id: Integer): IActionResult;
  
  [HttpPost]            // POST /api/v1/users
  function Create([FromBody] User: TUser): IActionResult;
end;
```

### APIs Versionadas

```pascal
[Route('/api/v1/orders')]
TOrdersV1Controller = class(TController)
end;

[Route('/api/v2/orders')]
TOrdersV2Controller = class(TController)
end;
```

## Parâmetros de Query

```pascal
// URL: /search?q=delphi&page=1&limit=20
App.MapGet('/search', procedure(Ctx: IHttpContext)
  begin
    var Query := Ctx.Request.GetQueryParam('q');
    var Page := Ctx.Request.GetQueryParam('page');
    var Limit := Ctx.Request.GetQueryParam('limit');
  end);
```

## Métodos HTTP

```pascal
App.MapGet('/resource', Handler);     // GET
App.MapPost('/resource', Handler);    // POST
App.MapPut('/resource/{id}', Handler); // PUT
App.MapPatch('/resource/{id}', Handler); // PATCH
App.MapDelete('/resource/{id}', Handler); // DELETE
App.MapQuery('/resource', Handler);   // QUERY (RFC 10008)
```

## Método HTTP QUERY (RFC 10008)

O método HTTP `QUERY` é projetado para operações de consulta seguras, idempotentes e orientadas ao corpo da requisição.

```pascal
App.MapQuery('/users/query', procedure(Ctx: IHttpContext)
  begin
    // Processa o corpo da requisição com a query estruturada
  end);
```

Você pode definir os tipos de mídia (media types) suportados usando o método `.AcceptsQuery`:

```pascal
App.MapQuery('/users/query', Handler);
TEndpointMetadataExtensions.AcceptsQuery(App, ['application/jsonpath', 'application/sql']);
```

Quando uma requisição OPTIONS é enviada para o endpoint, o Dext retorna automaticamente:
- `Allow: QUERY, OPTIONS` (e outros métodos suportados)
- `Accept-Query: application/jsonpath, application/sql`

## Agrupando Rotas

```pascal
App.MapGroup('/api/v1', procedure(Group: IRouteGroup)
  begin
    Group.MapGet('/users', UsersHandler);
    Group.MapGet('/orders', OrdersHandler);
    // Resulta em: /api/v1/users, /api/v1/orders
  end);
```

## Performance do Motor de Roteamento (Radix Tree)

O Dext utiliza um algoritmo otimizado de **Árvore Radix (Trie)** para o roteamento.
Em vez de realizar uma busca linear (`O(N)`) por todas as rotas registradas a cada
requisição, as rotas são compiladas em uma árvore de segmentos de caminho.

Principais características:
- **Complexidade de Busca O(L)**: O tempo de resolução de rotas depende estritamente
  da profundidade/segmentos do caminho da URL (`L`), e não do número de rotas (`N`).
- **Backtracking de Segmentos**: Suporte para segmentos literais, parâmetros (`{id}`)
  e curingas com backtracking para garantir que rotas exatas tenham prioridade.
- **Mapeamento de Metadados Zero-Allocation**: O motor evita o empacotamento pesado
  de RTTI/TValue ao resolver metadados de endpoint, atribuindo os valores
  diretamente por meio da propriedade `IHttpContext.EndpointMetadata`.

## Versionamento de API (API Versioning)

O Dext oferece suporte nativo e flexível a versionamento de rotas e APIs:

- **Precedência Determinística**: Se um caminho possui uma rota versionada (ex: `2.0`) e uma sem versão, a rota com correspondência exata de versão sempre vence a rota sem versão, independente da ordem em que foram registradas. A rota sem versão atua como fallback.
- **Respostas RFC 9457**: Caso uma rota exija versão e nenhuma seja enviada, ou seja solicitada uma versão não atendida pelo endpoint, o Dext responde **HTTP 400 Bad Request** com problem details (`application/problem+json`), usando os códigos `ApiVersionUnspecified` ou `UnsupportedApiVersion`.
- **Estratégias Plugáveis (`IApiVersionReader`)**: O roteador aceita leitores customizados para extrair a versão solicitada da requisição HTTP:

```pascal
uses
  Dext.Web,
  Dext.Web.Versioning;

// 1. Configurar leitor customizado no pipeline (Query String ?v=...)
App.Builder.UseApiVersionReader(TQueryStringApiVersionReader.Create('v'));

// 2. Ou leitor por cabeçalho customizado (X-Api-Version: ...)
App.Builder.UseApiVersionReader(THeaderApiVersionReader.Create('X-Api-Version'));

// 3. Ou leitor composto com prioridade (Header -> Query String)
App.Builder.UseApiVersionReader(
  TCompositeApiVersionReader.Create([
    THeaderApiVersionReader.Create('X-Api-Version'),
    TQueryStringApiVersionReader.Create('api-version')
  ])
);

// Mapeando rotas versionadas
App.MapGet('/items', ItemsV1Handler);
TWebRouteHelpers.HasApiVersion(App.GetApplicationBuilder, '1.0');

App.MapGet('/items', ItemsV2Handler);
TWebRouteHelpers.HasApiVersion(App.GetApplicationBuilder, '2.0');
```

Por padrão, caso nenhum leitor customizado seja definido, o Dext busca a versão na query string `api-version` e depois no cabeçalho `X-Version`.

---

[← Model Binding](model-binding.md) | [Próximo: Middleware →](middleware.md)

