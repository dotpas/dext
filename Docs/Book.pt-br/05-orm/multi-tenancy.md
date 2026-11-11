# Multi-Tenancy

Implemente aplicações SaaS com isolamento de dados transparente.

## Estratégias de Multi-Tenancy

O Dext suporta três estratégias principais:

1. **Banco de Dados Compartilhado (Isolamento por Coluna)**
2. **Schema Separado (PostgreSQL/SQL Server)**
3. **Banco de Dados Separado**

## Banco Compartilhado (Column-based)

Adicione a interface `ITenantAware` em suas entidades e o Dext aplicará filtros automáticos em todas as queries e preencherá o `TenantId` ao salvar.

```pascal
type
  [Table('orders')]
  TOrder = class(TObject, ITenantAware)
  private
    FTenantId: string;
    // ...
  public
    [PK] property Id: Integer;
    property TenantId: string read FTenantId write FTenantId; // Coluna de isolamento
    property Description: string;
  end;
```

> 💡 **Dica**: Você pode herdar de `TTenantEntity` para obter uma implementação padrão de `ITenantAware`.

## Auto-Preenchimento (Auto-Population)

Ao salvar uma nova entidade que implementa `ITenantAware`, o `DbContext` preenche automaticamente o `TenantId` usando o `ITenantProvider` atual:

1. A entidade é rastreada pelo `DbContext`.
2. Durante o `SaveChanges`, o framework detecta `ITenantAware`.
3. O `TenantId` do inquilino atual é atribuído à entidade.
4. O registro é persistido com o ID de isolamento correto.

Isso garante que, mesmo que você esqueça de setar o ID do tenant em sua lógica de negócio, os dados permanecerão isolados e seguros.

## Informando o Locatário

O locatário corrente fica num `ITenantProvider` (`TTenantProvider` é a implementação pronta), que é passado ao construtor do `TDbContext`. O `TTenant.Create` recebe o id, o nome, a cadeia de conexão e, opcionalmente, o esquema:

```pascal
Provider := TTenantProvider.Create;
Provider.Tenant := TTenant.Create('acme', 'Acme Corp', '');
Db := TMyDb.Create(DbContextOptions.UseSQLite('app.db'), Provider);
```

Trocar de locatário é atribuir `Provider.Tenant`. O `ITenant.Properties` é um dicionário de textos para configurações por locatário (taxas, limites, chaves de recurso) que o código do aplicativo pode ler.

Numa aplicação web, o `TMultiTenancyMiddleware` (`Dext.Web.MultiTenancy`) resolve o locatário a cada requisição: uma `ITenantResolutionStrategy` extrai o id do locatário do `IHttpContext` (cabeçalho, host, query, o que o aplicativo definir), um `ITenantStore` devolve o `ITenant` desse id, e o middleware o grava no `ITenantProvider` do escopo. As duas interfaces são implementadas pelo aplicativo.

> ⚠️ Se a estratégia devolve um id vazio, ou o store não o conhece, o provedor fica **sem locatário**, e um contexto sem locatário **não filtra** (veja abaixo). Rejeite essas requisições antes de qualquer consulta.

## Comportamento

- **Carimbo:** ao acrescentar uma entidade `ITenantAware`, o contexto grava o `TenantId` do locatário corrente, substituindo qualquer valor que o código tenha atribuído.
- **Consultas:** toda consulta e todo `Find` de uma entidade `ITenantAware` é filtrado pelo locatário corrente, inclusive depois de uma troca de locatário no mesmo contexto.
- **Sem locatário, sem filtro:** sem locatário no provedor, nada é filtrado nem carimbado.
- **`IgnoreQueryFilters`** também desliga o filtro do locatário (e o carimbo) naquela consulta.
- **Escritas:** `UPDATE` e `DELETE` levam o locatário no `WHERE`. A linha de outro locatário não é tocada, e o `SaveChanges` lança `EOptimisticConcurrencyException`, na alteração e na remoção (um `DELETE` que não encontra linha deixou de passar em silêncio). As remoções executadas em lote não informam as linhas não encontradas.
- **SQL escrito à mão** (`Connection.CreateCommand`) não é filtrado: inclua o locatário no `WHERE`.
- **Rastreador:** trocar de locatário não esvazia as entidades rastreadas do contexto. Use um contexto por locatário e por requisição, ou chame `Clear` na troca.

## Esquema ou Banco por Locatário

Quando o `ITenant` tem `Schema`, o contexto o cria no `EnsureCreated` e aponta a conexão para ele antes das operações (o dialeto do PostgreSQL executa `SET search_path TO "esquema", public`; cada dialeto tem o seu comando). Quando tem `ConnectionString` (formato do FireDAC, por exemplo `DriverID=SQLite;Database=...`), o contexto reconecta com ela quando o locatário muda. As duas são aplicadas antes das consultas e antes das escritas. As tabelas dessas estratégias não precisam da coluna `TenantId`.

## Vantagens do Multi-Tenancy no Dext

- **Transparência**: Você escreve `Context.Users.ToList` e o framework adiciona `WHERE TenantId = 'abc'` automaticamente.
- **Segurança**: Previne vazamento de dados entre clientes no nível arquitetural.
- **Migrações**: O CLI `dext migrate:up` pode aplicar migrations em todos os schemas/bancos de tenants.

---

[← Scaffolding](scaffolding.md) | [Próximo: Database as API →](../06-database-as-api/README.md)
