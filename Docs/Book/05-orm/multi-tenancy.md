# Multi-Tenancy

Implement SaaS applications with transparent data isolation.

## Multi-Tenancy Strategies

Dext supports three main strategies:

1. **Shared Database (Column-based isolation)**
2. **Separate Schema (PostgreSQL/SQL Server)**
3. **Separate Database**

## Shared Database (Column-based)

Add the `ITenantAware` interface to your classes, and Dext will automatically apply filters to all queries and populate the `TenantId` on save.

```pascal
type
  [Table('orders')]
  TOrder = class(TObject, ITenantAware)
  private
    FTenantId: string;
    // ...
  public
    [PK] property Id: Integer;
    property TenantId: string read FTenantId write FTenantId; // Isolation column
    property Description: string;
  end;
```

> 💡 **Tip**: You can inherit from `TTenantEntity` to get a default implementation of `ITenantAware`.

## Auto-Population

When you save a new entity that implements `ITenantAware`, the `DbContext` automatically populates the `TenantId` using the current `ITenantProvider`:

1. The entity is tracked by the `DbContext`.
2. During `SaveChanges`, the framework detects `ITenantAware`.
3. It assigns `FTenantProvider.Tenant.Id` to the entity.
4. The record is persisted with the correct isolation ID.

This ensures that even if you forget to set the tenant ID in your business logic, the data remains isolated and secure.

## Providing the Tenant

The current tenant is held by an `ITenantProvider` (`TTenantProvider` is the ready-made implementation), which is passed to the `TDbContext` constructor. `TTenant.Create` takes the id, the name, the connection string and, optionally, the schema:

```pascal
Provider := TTenantProvider.Create;
Provider.Tenant := TTenant.Create('acme', 'Acme Corp', '');
Db := TMyDb.Create(DbContextOptions.UseSQLite('app.db'), Provider);
```

Switching tenant is assigning `Provider.Tenant`. `ITenant.Properties` is a string dictionary for per-tenant settings (rates, limits, feature switches) that application code can read.

In a web application, `TMultiTenancyMiddleware` (`Dext.Web.MultiTenancy`) resolves the tenant per request: an `ITenantResolutionStrategy` extracts the tenant id from the `IHttpContext` (header, host, query, whatever the application defines), an `ITenantStore` returns the `ITenant` for that id, and the middleware puts it in the scoped `ITenantProvider`. Both interfaces are implemented by the application.

> ⚠️ If the strategy returns an empty id, or the store does not know it, the provider is left **without a tenant**, and a context without a tenant does **not filter** (see below). Reject such requests before any query.

## Behavior Notes

- **Stamping:** when an `ITenantAware` entity is added, the context sets `TenantId` to the current tenant, replacing any value the code assigned.
- **Queries:** every query and `Find` on an `ITenantAware` entity is filtered by the current tenant, including after a tenant switch on the same context.
- **No tenant, no filter:** with no tenant in the provider, nothing is filtered or stamped.
- **`IgnoreQueryFilters`** also turns off the tenant filter (and the stamp) for that query.
- **Writes:** `UPDATE` and `DELETE` carry the tenant in the `WHERE`. A row of another tenant is not touched, and `SaveChanges` raises `EOptimisticConcurrencyException`, for updates and for deletes (a delete matching no row no longer passes silently). Deletes executed in bulk batches do not report unmatched rows.
- **Raw SQL** (`Connection.CreateCommand`) is not filtered: include the tenant in the `WHERE`.
- **Tracker:** switching tenant does not clear the context's tracked entities. Use one context per tenant and per request, or call `Clear` when switching.

## Schema or Database per Tenant

When the `ITenant` has a `Schema`, the context creates it in `EnsureCreated` and switches the connection to it before operations (the PostgreSQL dialect issues `SET search_path TO "schema", public`; each dialect has its own command). When it has a `ConnectionString` (FireDAC format, e.g. `DriverID=SQLite;Database=...`), the context reconnects with it when the tenant changes. Both are applied before queries as well as before writes. The tables of these strategies do not need the `TenantId` column.

## Advantages of Multi-Tenancy in Dext

- **Transparency**: You write `Context.Users.ToList` and the framework adds `WHERE TenantId = 'abc'` automatically.
- **Security**: Prevents data leakage between customers at the architectural level.
- **Migrations**: The `dext migrate:up` CLI can apply migrations across all tenant schemas/databases.

---

[← Scaffolding](scaffolding.md) | [Next: Database as API →](../06-database-as-api/README.md)
