# Routing

Define URL patterns and extract parameters.

## Route Patterns

### Static Routes

```pascal
App.MapGet('/users', Handler);           // GET /users
App.MapPost('/users', Handler);          // POST /users
App.MapGet('/api/health', Handler);      // GET /api/health
```

### Route Parameters

```pascal
App.MapGet('/users/{id}', procedure(Ctx: IHttpContext)
  begin
    var Id := Ctx.Request.RouteParams['id'];
    // Id = "123" for /users/123
  end);

App.MapGet('/orders/{orderId}/items/{itemId}', procedure(Ctx: IHttpContext)
  begin
    var OrderId := Ctx.Request.RouteParams['orderId'];
    var ItemId := Ctx.Request.RouteParams['itemId'];
  end);
```

### Optional Parameters

```pascal
App.MapGet('/files/{path*}', procedure(Ctx: IHttpContext)
  begin
    var Path := Ctx.Request.RouteParams['path'];
    // Captures rest of path: /files/docs/readme.md → "docs/readme.md"
  end);
```

## Controller Routes

### Class-Level Route

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

### Versioned APIs

```pascal
[Route('/api/v1/orders')]
TOrdersV1Controller = class(TController)
end;

[Route('/api/v2/orders')]
TOrdersV2Controller = class(TController)
end;
```

## Query Parameters

```pascal
// URL: /search?q=delphi&page=1&limit=20
App.MapGet('/search', procedure(Ctx: IHttpContext)
  begin
    var Query := Ctx.Request.GetQueryParam('q');
    var Page := Ctx.Request.GetQueryParam('page');
    var Limit := Ctx.Request.GetQueryParam('limit');
  end);
```

### In Controllers

```pascal
[HttpGet('/search')]
function Search(
  [FromQuery] Q: string;
  [FromQuery('page')] PageNum: Integer;  // Custom name
  [FromQuery] Limit: Integer = 20        // Default value
): IActionResult;
```

## Route Constraints

Validate parameters at route level:

```pascal
// Only match if id is numeric
App.MapGet('/users/{id}<int>', Handler);
// Matches: /users/123
// No Match: /users/abc

// Only match specific values
App.MapGet('/status/{status}<active|inactive>', Handler);
```

## HTTP Methods

```pascal
App.MapGet('/resource', Handler);     // GET
App.MapPost('/resource', Handler);    // POST
App.MapPut('/resource/{id}', Handler); // PUT
App.MapPatch('/resource/{id}', Handler); // PATCH
App.MapDelete('/resource/{id}', Handler); // DELETE
App.MapOptions('/resource', Handler); // OPTIONS
App.MapHead('/resource', Handler);    // HEAD
App.MapQuery('/resource', Handler);   // QUERY (RFC 10008)
```

## HTTP QUERY Method (RFC 10008)

The HTTP `QUERY` method is designed for safe, idempotent request-body-driven query operations.

```pascal
App.MapQuery('/users/query', procedure(Ctx: IHttpContext)
  begin
    // Process query payload from request body
  end);
```

You can define the supported media types using the `.AcceptsQuery` method:

```pascal
App.MapQuery('/users/query', Handler);
TEndpointMetadataExtensions.AcceptsQuery(App, ['application/jsonpath', 'application/sql']);
```

When an OPTIONS request is made to the endpoint, Dext automatically returns:
- `Allow: QUERY, OPTIONS` (and other supported methods)
- `Accept-Query: application/jsonpath, application/sql`

## Grouping Routes

```pascal
App.MapGroup('/api/v1', procedure(Group: IRouteGroup)
  begin
    Group.MapGet('/users', UsersHandler);
    Group.MapGet('/orders', OrdersHandler);
    // Results in: /api/v1/users, /api/v1/orders
  end);
```

## Routing Engine Performance (Radix Tree)

Dext uses an optimized **Radix Tree (Trie)** routing algorithm. Instead of
performing a linear search (`O(N)`) through all registered routes on each
incoming request, routes are compiled into a tree of path segments.

Key features:
- **O(L) Matching Complexity**: Route matching time depends strictly on the
  depth/segments of the URL path (`L`) rather than the number of routes (`N`).
- **Segment Backtracking**: Support for literals, parameters (`{id}`), and
  wildcards with backtracking to ensure exact routes take precedence.
- **Zero-Allocation Metadata Mapping**: The engine bypasses RTTI/TValue
  wrapping when resolving endpoint metadata by directly assigning values via
  the `IHttpContext.EndpointMetadata` property.

## API Versioning

Dext provides native, flexible API and route versioning support:

- **Deterministic Precedence**: If a path declares a versioned route (e.g. `2.0`) alongside an unversioned route, the exact version match always takes precedence over the unversioned route regardless of registration order. The unversioned route acts strictly as a fallback.
- **RFC 9457 Problem Details**: If a route requires a version and none is provided, or a requested version is not served by any route on that path, Dext answers **HTTP 400 Bad Request** with problem details (`application/problem+json`), using either `ApiVersionUnspecified` or `UnsupportedApiVersion`.
- **Pluggable Readers (`IApiVersionReader`)**: The router integrates directly with pluggable version readers configured in the application pipeline:

```pascal
uses
  Dext.Web,
  Dext.Web.Versioning;

// 1. Configure custom query string reader (?v=...)
App.Builder.UseApiVersionReader(TQueryStringApiVersionReader.Create('v'));

// 2. Or custom header reader (X-Api-Version: ...)
App.Builder.UseApiVersionReader(THeaderApiVersionReader.Create('X-Api-Version'));

// 3. Or composite reader with priority (Header -> Query String fallback)
App.Builder.UseApiVersionReader(
  TCompositeApiVersionReader.Create([
    THeaderApiVersionReader.Create('X-Api-Version'),
    TQueryStringApiVersionReader.Create('api-version')
  ])
);

// Mapping versioned routes
App.MapGet('/items', ItemsV1Handler);
TWebRouteHelpers.HasApiVersion(App.GetApplicationBuilder, '1.0');

App.MapGet('/items', ItemsV2Handler);
TWebRouteHelpers.HasApiVersion(App.GetApplicationBuilder, '2.0');
```

By default, when no custom reader is configured, Dext looks for `api-version` in query string parameters and `X-Version` in request headers.

---

[← Model Binding](model-binding.md) | [Next: Middleware →](middleware.md)

