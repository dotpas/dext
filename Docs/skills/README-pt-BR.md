# Dext Framework — Agent Skills (Habilidades do Agente)

> [!NOTE]
> **Propósito**: Esta pasta contém pacotes de instruções focados em agentes de IA (como Antigravity, Claude e Codex). Enquanto o **Dext Book** é o guia mestre para humanos, o **Skills** é otimizado para que IAs possam ler e aplicar padrões de código idiomáticos do Dext rapidamente.

Pacotes de instruções focados para escrever código **Dext** (framework moderno para Delphi) correto e idiomático.

## Habilidades Disponíveis

| Habilidade | Arquivo | Carregar Quando |
|-------|------|-----------|
| **dext-app-structure** | `dext-app-structure.md` | Configuração de novo projeto, classe Startup, pipeline de middleware, bootstrap `.dpr`, layout do projeto |
| **dext-web** | `dext-web.md` | Endpoints HTTP, Minimal APIs, Controllers, roteamento, model binding, padrão Results |
| **dext-orm** | `dext-orm.md` | Entidades ORM, DbContext, consultas, Smart Properties, CRUD, hidratação S54 e planos de campo diretos |
| **dext-orm-advanced** | `dext-orm-advanced.md` | Relacionamentos, eager loading, herança (TPH/TPT), Especificações, migrations, SQL bruto, stored procedures, locking, multi-tenancy |
| **dext-di** | `dext-di.md` | Registro de serviços, tempos de vida (Scoped/Singleton/Transient), injeção via construtor, atributo `[Inject]` |
| **dext-auth** | `dext-auth.md` | Autenticação JWT, endpoints de login, `[Authorize]`, claims, `TClaimsBuilder` |
| **dext-testing** | `dext-testing.md` | Testes de unidade, `Mock<T>`, assertions fluentes (`Should`), `[TestFixture]`, testes de snapshot, instalação do Test Explorer, cobertura no Win64x |
| **dext-collections** | `dext-collections.md` | `IList<T>`, `TCollections`, operações LINQ, semântica de ownership, `IChannel<T>` |
| **dext-json** | `dext-json.md` | Serialização JSON (`TDextJson`), configurações customizadas, DOM e comportamento do plano direto S54 |
| **dext-api-features** | `dext-api-features.md` | Middleware, CORS, rate limiting, cache de resposta, health checks, OpenAPI/Swagger, arquivos estáticos, compressão |
| **dext-validation** | `dext-validation.md` | Validação baseada em atributos, TAbstractValidator<T>, validação fortemente tipada com Prop<T>, registro de padrões, auto-validação no model binding |
| **dext-background** | `dext-background.md` | Workers em segundo plano (`IHostedService`), configuração (`IConfiguration`, padrão Options), tarefas assíncronas (`TAsyncTask`) |
| **dext-networking** | `dext-networking.md` | Cliente REST, HTTP assíncrono, gRPC/protobuf, codecs diretos/gerados S54, respostas tipadas e pool de conexões |
| **dext-logging** | `dext-logging.md` | Logging estruturado (`ILogger`), níveis de log, log assíncrono (RingBuffer), sinks APM (Seq, OpenTelemetry OTLP) |
| **dext-resilience** | `dext-resilience.md` | Pipeline de Resiliência estilo Polly (Retry, Circuit Breaker, Fallback, Timeout) |
| **dext-realtime** | `dext-realtime.md` | Hubs (`THub`), mensagens em tempo real compatíveis com SignalR, grupos, `IHubContext<T>` |
| **dext-database-as-api** | `dext-database-as-api.md` | API REST CRUD instantânea de entidades ORM com zero código (`MapDataApi<T>`) |
| **dext-desktop-ui** | `dext-desktop-ui.md` | Aplicativos desktop VCL, Navigator (inspirado no Flutter), Magic Binding (bidirecional, declarativo), MVVM |
| **dext-server-adapters** | `dext-server-adapters.md` | Adaptador Indy (self-hosted), SSL/HTTPS (OpenSSL/Taurus), `Run` vs `Start`, padrões de deploy, WebBroker/ISAPI (roadmap) |
| **dext-mcp** | `dext-mcp.md` | Model Context Protocol, servidores MCP, registrar ferramentas, recursos e prompts, chamadas de BD via IA |
| **dext-symbols** | `dext-symbols.md` | Localizar classes, interfaces, records, métodos, propriedades e constantes no código usando mapas pré-gerados na raiz |


## Instalação Manual

Copie a pasta `Docs/Skills/` para o seu projeto e, em seguida, referencie as habilidades pelo nome do arquivo.

| Agente | Caminho no projeto | Caminho global |
|-------|--------------------|-------------|
| **Antigravity** | `.gemini/skills/` | `.gemini/skills/` |
| **Claude Code** | `.claude/skills/` | `~/.claude/skills/` |
| **Cursor** | `.agents/skills/` | `~/.agents/skills/` |
| **Cline** | `.cline/skills/` | `~/.cline/skills/` |
| **OpenCode** | `.agents/skills/` | `~/.agents/skills/` |
| **Continue** | `.continue/skills/` | `~/.continue/skills/` |

## Como Funciona

As habilidades são carregadas dinamicamente quando o agente precisa delas. O README é sempre carregado para que o agente saiba qual habilidade ativar. Os arquivos de habilidades individuais são carregados sob demanda — mantendo a janela de contexto leve. Note que alguns usuários avançados preferem configurar links simbólicos para apontar ferramentas como o `claude-code` de `.claude/skills` diretamente para o repositório em `Docs/Skills`.

## Guia de Ativação (Triggers)

**Carregue `dext-app-structure`** quando:

- Criar um novo projeto Dext do zero
- Configurar a classe Startup e o pipeline de middleware
- Configurar o ponto de entrada `.dpr`
- Organizar arquivos e módulos do projeto

**Carregue `dext-web`** quando:

- Criar ou modificar endpoints HTTP (`MapGet`, `MapPost`, `MapQuery`, `[HttpGet]`, `[HttpPost]`, `[HttpQuery]`)
- Escrever controllers (`[ApiController]`, `TInterfacedObject`)
- Lidar com model binding, parâmetros de rota, query strings, headers
- Usar `Results.Ok`, `Results.Created`, etc.

**Carregue `dext-orm`** quando:

- Definir classes de entidade com `[Table]`, `[PK]`, `[Required]`, etc.
- Escrever subclasses de `TDbContext` com propriedades `IDbSet<T>`
- Consultar com `.Where`, `.ToList`, `.Find`, Smart Properties
- Adicionar/atualizar/remover registros, db seeding

**Carregue `dext-orm-advanced`** quando:

- Definir relacionamentos (`[ForeignKey]`, `[InverseProperty]`, `[ManyToMany]`)
- Usar eager loading (`.Include`)
- Trabalhar com herança TPH/TPT (`[Inheritance]`, `[DiscriminatorColumn]`)
- Escrever classes Specification, migrations, SQL bruto, stored procedures
- Implementar locking (otimista/pessimista) ou multi-tenancy

**Carregue `dext-di`** quando:

- Registrar serviços usando `.AddScoped`, `.AddSingleton`, `.AddTransient`
- Configurar `ConfigureServices` em uma classe Startup
- Injetar serviços via construtores ou pelo atributo `[Inject]`
- Usar o registro de factory com `IServiceProvider`

**Carregue `dext-auth`** quando:

- Implementar autenticação JWT
- Criar endpoints de login
- Usar `[Authorize]`, `[AllowAnonymous]`
- Construir claims usando `TClaimsBuilder`

**Carregue `dext-testing`** quando:

- Escrever classes com `[TestFixture]`
- Usar `Mock<T>` (de `Dext.Mocks`)
- Escrever assertions fluentes com `Should(...)`
- Configurar projetos de teste (`.dpr`)
- Usar snapshot testing (`MatchSnapshot`)
- Instalar o Test Explorer ou configurar cobertura de linha no Win64x

**Carregue `dext-collections`** quando:

- Usar `IList<T>`, `TCollections.CreateList`, `TCollections.CreateObjectList`
- Escrever consultas estilo LINQ em listas em memória
- Usar `IChannel<T>` para comunicação entre threads

**Carregue `dext-json`** quando:

- Serializar objetos ou records em strings JSON (`TDextJson.Serialize`)
- Desserializar strings JSON em estruturas tipadas (`TDextJson.Deserialize<T>`)
- Analisar e navegar em documentos JSON utilizando as interfaces de DOM (`IDextJsonObject`, `IDextJsonArray`)
- Configurar estilos de casing (`TCaseStyle`) ou outras propriedades de formatação (`TJsonSettings`)

**Carregue `dext-api-features`** quando:

- Adicionar middleware (CORS, rate limiting, compressão, arquivos estáticos)
- Configurar a documentação OpenAPI/Swagger
- Configurar health checks, cache de respostas

**Carregue `dext-validation`** quando:

- Escrever atributos de validação (`[Required]`, `[StringLength]`, `[Range]`, etc.)
- Criar validadores de model customizados com `TAbstractValidator<T>` e `RuleFor`
- Mapear validações fortemente tipadas via `Prototype.Entity<T>` e smart properties
- Registrar padrões de expressões regulares localizados em `TValidationPatterns`
- Configurar a auto-validação no pipeline de model binding Web

**Carregue `dext-background`** quando:

- Criar workers em background com `IHostedService`
- Carregar ou realizar bind de configurações (`appsettings.json`, variáveis de ambiente, padrão Options)
- Usar `TAsyncTask` para operações assíncronas não-bloqueantes

**Carregue `dext-networking`** quando:

- Fazer requisições HTTP de saída para APIs externas
- Usar `TRestClient` para chamadas REST
- Precisar de chamadas HTTP assíncronas com desserialização tipada

**Carregue `dext-logging`** quando:

- Configurar o logger ou registrar sinks (Console, File, Seq, OpenTelemetry)
- Gravar mensagens de log usando interfaces `ILogger` e structured placeholders
- Configurar propriedades de lote (`TBatchOptions`) ou utilizar o RingBuffer de alta performance

**Carregue `dext-resilience`** quando:

- Configurar ou ajustar políticas de execução (Retry, Circuit Breaker, Fallback, Timeout)
- Envolver operações de I/O (requisições REST, execução de BD) em wrappers de resiliência

**Carregue `dext-realtime`** quando:

- Construir recursos em tempo real (WebSockets, push notifications)
- Usar `THub` e `IHubContext<T>`
- Enviar mensagens para clientes conectados ou grupos

**Carregue `dext-database-as-api`** quando:

- Precisar de CRUD REST instantâneo para uma entidade sem código de controller
- Usar `App.Builder.MapDataApi<T>` para painéis administrativos ou prototipagem rápida

**Carregue `dext-server-adapters`** quando:

- Configurar SSL/HTTPS (`SslProvider`, `SslCert`, `SslKey`)
- Escolher entre `App.Run` (bloqueante) e `App.Start` (não-bloqueante)
- Fazer deploy atrás de proxy reverso IIS/nginx
- Tiver dúvidas sobre suporte futuro a adaptadores ou ISAPI/WebBroker

**Carregue `dext-desktop-ui`** quando:

- Construir aplicativos desktop VCL com o Dext Navigator
- Implementar o Magic Binding (binding bidirecional declarativo)
- Seguir o padrão MVVM com ViewModel + Controller + Frame

**Carregue `dext-mcp`** quando:

- Criar ou configurar um servidor MCP (Model Context Protocol)
- Expor ferramentas (tools), recursos ou prompts customizados para assistentes de IA
- Configurar conexões SQLite ou integração de banco de dados com chamadas de IA
- Sincronizar atualizações de banco de dados com threads de interface gráfica VCL/FMX

**Carregue `dext-symbols`** quando:

- Buscar definições de tipos, classes, interfaces, records, métodos, propriedades ou constantes no código-fonte do Dext
- Precisar navegar diretamente para números de linhas de declaração de símbolos ou conferir assinaturas de métodos públicos

## Fatos Principais sobre o Framework

- **Pacotes**: Dext.Core, Dext.EF.Core, Dext.Web.Core, Dext.Testing, Dext.Net
- **Alvo**: Delphi 11 Alexandria e posteriores
- **Paradigma**: Inspirado no ASP.NET Core (Minimal APIs, padrão Controller, DI, ORM)
- **Código-fonte**: `$(DEXT)\Sources\` — configure a variável de ambiente `DEXT`
- **Exemplos**: `$(DEXT)\Examples\` — 39 projetos de exemplo completos
- **Documentação**: `$(DEXT)\Docs\Book\` — 79 capítulos em markdown

## Regras Críticas (Aplicam-se a Todas as Habilidades)

1. **Parâmetros de rota usam a sintaxe `{id}`**, não `:id` (estilo Express)
2. **Parâmetros de rota em controllers DEVEM começar com `/`**: `[HttpGet('/{id}')]`
3. **NUNCA nomeie um método de controller como `Create`** — cria conflito com os construtores do Delphi (use `CreateUser`, `CreateOrder`, etc.)
4. **NUNCA use `Ctx.RequestServices.GetService<T>`** — use parâmetros de tipo genéricos
5. **NUNCA use `TObjectList<T>`** para resultados de ORM — use `IList<T>` de `Dext.Collections`
6. **NUNCA use `[StringLength]`** — use `[MaxLength(N)]`
7. **NUNCA use `NavType<T>`** — use `Nullable<T>` de `Dext.Types.Nullable`
8. **Sempre `.WithPooling(True)`** para DbContexts em Web APIs
9. **Sempre chame `.Update(Entity)` antes de `SaveChanges`** para entidades desanexadas (detached)
10. **`Mock<T>` é um Record** — nunca chame `.Free` nele
11. **`Dext.Entity.Core`** deve estar na seção `uses` para os genéricos de `IDbSet<T>` compilarem
12. **`SetConsoleCharSet`** é OBRIGATÓRIO em todos os projetos console (test runners, ferramentas de linha de comando CLI)
13. **Ordem das Uses (CRÍTICA)**: Devido à limitação de apenas um class helper por tipo no Delphi, a ordem nas cláusulas `uses` deve ser sempre: `Dext` → `Dext.Entity` → `Dext.Web`. O último sempre vence e garante visibilidade dos métodos Web.
14. **Smart Properties**: Para entidades, use sempre os aliases **IntType**, **StringType**, **DoubleType** e **BoolType** (de `Dext.Core.SmartTypes`) em vez de `Prop<T>`. Para **colunas anuláveis (nullable)**, use sempre a composição `Prop<Nullable<T>>` (ex: `Prop<Nullable<Integer>>`) em vez do padrão legado `Nullable<Prop<T>>` (ex: `Nullable<StringType>`), que está obsoleto, gera alertas e quebra a ordenação de consultas (`OrderBy`).
15. **Método HTTP QUERY**: O método `QUERY` (RFC 10008) é suportado. Use `MapQuery` / `TRestClient.Query` e metadados `AcceptsQuery` para especificar os formatos de consulta suportados, os quais são expostos de forma automática em chamadas OPTIONS através do cabeçalho `Accept-Query`.
