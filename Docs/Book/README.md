# 📚 The Dext Book

> A comprehensive guide to building modern web applications with the Dext Framework for Delphi.

---

## Quick Links

- [Where to Start?](01-getting-started/where-to-start.md) - Choosing your path
- [Getting Started](01-getting-started/README.md) - Installation & Hello World
- [Web Framework](02-web-framework/README.md) - Minimal APIs & Controllers
- [ORM](05-orm/README.md) - Database access & queries
- [Security](11-security/README.md) - Authentication & Authorization
- [Deployment](12-deployment/README.md) - Publishing your application
- [AI Assistants & Skills](13-ai-assistants/README.md) - Integrating AI capabilities

---

## Table of Contents

### Part I: Foundations

#### [1. Getting Started](01-getting-started/README.md)

- [Where to Start?](01-getting-started/where-to-start.md)
- [Installation](01-getting-started/installation.md)
- [Hello World](01-getting-started/hello-world.md)
- [Project Structure](01-getting-started/project-structure.md)

#### [2. Web Framework](02-web-framework/README.md)

- [Minimal APIs](02-web-framework/minimal-apis.md) - Route handlers with `MapGet`, `MapPost`
- [Controllers](02-web-framework/controllers.md) - MVC-style controllers
- [Model Binding](02-web-framework/model-binding.md) - JSON/Form to objects
- [Routing](02-web-framework/routing.md) - URL patterns & parameters
- [Middleware](02-web-framework/middleware.md) - Request pipeline
- [WebBroker Adapter](02-web-framework/webbroker.md) ⭐ **NEW** - Deploy as ISAPI/CGI on IIS/Apache
- [HTMX & Streamable](02-web-framework/htmx-streamable.md) ⭐ **NEW** - Native HTMX and session state management

#### [3. Generic Collections](01-getting-started/collections.md) ⭐ **NEW**

- [Introduction](01-getting-started/collections.md) - IList, IDictionary & LINQ
- [Ownership & Safety](01-getting-started/collections.md#ownership) - Memory management guide

#### [4. Authentication & Security](03-authentication/README.md)

- [JWT Authentication](03-authentication/jwt-auth.md) - Token-based auth
- [Claims Builder](03-authentication/claims-builder.md) - User claims

#### [4. API Features](04-api-features/README.md)

- [OpenAPI / Swagger](04-api-features/openapi-swagger.md) - API documentation
- [Rate Limiting](04-api-features/rate-limiting.md) - Request throttling
- [CORS](04-api-features/cors.md) - Cross-origin requests
- [Response Caching](04-api-features/caching.md) - Cache headers
- [Health Checks](04-api-features/health-checks.md) - `/health` endpoint

---

### Part II: Data Access

#### [5. ORM (Dext.Entity)](05-orm/README.md)

- [Getting Started](05-orm/getting-started.md) - First entity & context
- [Entities & Mapping](05-orm/entities.md) - `[Table]`, `[Column]`, `[PK]`
- [Querying](05-orm/querying.md) - `Where`, `OrderBy`, `Take`
- [Smart Properties](05-orm/smart-properties.md) - Type-safe expressions
- [JSON Queries](05-orm/json-queries.md) ⭐ **NEW** - Query JSON/JSONB columns
- [Specifications](05-orm/specifications.md) - Reusable query patterns
- [Relationships](05-orm/relationships.md) - 1:1, 1:N, Lazy Loading
- [Migrations](05-orm/migrations.md) - Schema versioning
- [Scaffolding](05-orm/scaffolding.md) - DB-first code generation
- [Multi-Tenancy](05-orm/multi-tenancy.md) - Schema/DB/Column isolation

#### [6. Database as API](06-database-as-api/README.md)

- [Zero-Code CRUD](06-database-as-api/zero-code-crud.md) - REST from entities

---

### Part III: Advanced Features

#### [7. Real-Time Communication](07-real-time/README.md)

- [Hubs (SignalR)](07-real-time/hubs-signalr.md) - WebSocket messaging

#### [8. Testing](08-testing/README.md)

- [Mocking](08-testing/mocking.md) - `Mock<T>` and verification
- [Assertions](08-testing/assertions.md) - Fluent `Should()` syntax
- [Snapshots](08-testing/snapshots.md) - JSON snapshot testing

#### [9. CLI Tool](09-cli/README.md)

- [Commands](09-cli/commands.md) - `dext` CLI overview
- [Migrations](09-cli/migrations.md) - `migrate:up`, `migrate:down`
- [Scaffolding](09-cli/scaffolding.md) - `dext scaffold`
- [Testing](09-cli/testing.md) - `dext test --coverage`
- [Dashboard](09-cli/dashboard.md) - `dext ui`

#### [10. Advanced Topics](10-advanced/README.md)

- [Dependency Injection](10-advanced/dependency-injection.md)
- [Background Services](10-advanced/background-services.md)
- [Configuration](10-advanced/configuration.md) - `IOptions<T>` (JSON, YAML)
- [Async API](10-advanced/async-api.md) - `TAsyncTask`
- [Template Engine (S09)](10-advanced/templating.md) ⭐ **NEW** - Razor-style AST engine
- [Serialization & Globalization](10-advanced/serialization-globalization.md) ⭐ **NEW** - Handling locales and JSON formats
- [Resilience Pipeline (S32)](10-advanced/resilience.md) ⭐ **NEW** - Polly-style fault handling (Retry, Circuit Breaker, Fallback, Timeout)
- [Delphi64RTL Optimization (Win64)](10-advanced/performance-delphi64rtl.md) ⭐ **NEW** - Using optimized assembly and SIMD
- [Direct Codecs & Static Generation](10-advanced/direct-codecs-static-generation.md) ⭐ **NEW** - Direct-offset and generated codec paths

#### [11. Desktop UI (Dext.UI)](11-desktop-ui/README.md) ⭐ NEW

- [Navigator Framework](11-desktop-ui/navigator.md) - Push/Pop navigation with middlewares
- [Magic Binding](11-desktop-ui/magic-binding.md) - Declarative UI data binding
- [MVVM Patterns](11-desktop-ui/mvvm-patterns.md) - Architecture guide

#### [12. Networking (Dext.Net)](12-networking/rest-client.md) ⭐ NEW

- [REST Client](12-networking/rest-client.md) - Fluent HTTP Client
- [TCP/UDP Sockets](12-networking/low-level-sockets.md) - Low-level networking and connection handling
- [MQTT Client & Broker](12-networking/mqtt.md) - Pub/sub message routing and MQTT protocol

#### [13. AI Assistants & MCP](13-ai-assistants/README.md) ⭐ NEW

- [AI Skills](13-ai-assistants/README.md) - Native AI integration skills
- [MCP Server](15-mcp-server/README.md) - Model Context Protocol implementation

#### [16. AI Agents & Orchestration](16-ai-agents/README.md) ⭐ NEW

- Dext.AI.Agent - Single-agent ReAct loop (LangChain-style)
- Dext.AI.Graph - Graph orchestration, checkpointing, human-in-the-loop, subgraphs (LangGraph-style)

---

### Appendix

- [Type System Reference](appendix/type-system.md)
- [Database Dialects](appendix/dialects.md)
- [Troubleshooting](appendix/troubleshooting.md)
- [Advanced Debugging Guide](appendix/debugging-guide.md)

---

## Examples

Each chapter references working examples from the `Examples/` directory:

| Example | Topics |
|---------|--------|
| [Web.MinimalAPI](../../Examples/Web.MinimalAPI/) | Minimal APIs, Routing |
| [Web.ControllerExample](../../Examples/Web.ControllerExample/) | Controllers, DI |
| [Web.JwtAuthDemo](../../Examples/Web.JwtAuthDemo/) | JWT, Authentication |
| [Web.SwaggerExample](../../Examples/Web.SwaggerExample/) | OpenAPI, Documentation |
| [Web.RateLimitDemo](../../Examples/Web.RateLimitDemo/) | Rate Limiting |
| [Web.DatabaseAsApi](../../Examples/Web.DatabaseAsApi/) | Zero-Code CRUD |
| [Web.DextStore](../../Examples/Web.DextStore/) | Full E-commerce API |
| [Orm.EntityDemo](../../Examples/Orm.EntityDemo/) | ORM Basics |
| [Hubs](../../Examples/Hubs/) | Real-Time SignalR |
| [Desktop.MVVM.CustomerCRUD](../../Examples/Desktop.MVVM.CustomerCRUD/) | Navigator, MVVM, Testing |
| [AI.AgentDemo](../../Examples/AI/AgentDemo/) | Dext.AI.Agent, ReAct loop |
| [AI.GraphDemo](../../Examples/AI/GraphDemo/) | Dext.AI.Graph, checkpointing, HITL, subgraphs |

---

## Contributing

Found an error? Want to improve the docs? Please open an issue or submit a PR!

---

*Last updated: January 2026*
