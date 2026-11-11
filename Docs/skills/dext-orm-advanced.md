---
name: dext-orm-advanced
description: Advanced Dext ORM features — entity relationships, inheritance mapping (TPH/TPT), specifications, migrations, raw SQL (FromSql), stored procedures, pessimistic/optimistic locking, multi-tenancy, and JSON column queries.
---

# Dext ORM — Advanced Features

> For basic entity definition, DbContext, CRUD, and Smart Properties, see `dext-orm.md`.

## Relationships

### One-to-Many

```pascal
uses
  Dext.Entity, Dext.Types.Lazy; // ILazy<T>

type
  TUser = class;

  [Table('orders')]
  TOrder = class
  private
    FId: Integer;
    FUserId: Integer;
    FUser: ILazy<TUser>;
    function GetUser: TUser;
    procedure SetUser(const Value: TUser);
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;

    [ForeignKey('user_id'), BelongsTo]
    property UserId: Integer read FUserId write FUserId;

    // Lazy-loaded navigation
    property User: TUser read GetUser write SetUser; 
  end;

  [Table('users')]
  TUser = class
  private
    FId: Integer;
    FOrders: ILazy<TList<TOrder>>;
    function GetOrders: TList<TOrder>;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;

    [InverseProperty('User'), HasMany]
    property Orders: TList<TOrder> read GetOrders;
  end;

// Implementation of Getter/Setter
function TOrder.GetUser: TUser;
begin
  if FUser = nil then FUser := TLazy<TUser>.Create;
  Result := FUser.Value;
end;

procedure TOrder.SetUser(Value: TUser);
begin
  if FUser = nil then FUser := TLazy<TUser>.Create;
  FUser.Value := Value;
  if Value <> nil then FUserId := Value.Id;
end;
```

### Many-to-Many

```pascal
type
  [Table('users')]
  TUser = class
  public
    [ManyToMany('user_roles', 'user_id', 'role_id')]
    property Roles: TList<TRole> read GetRoles;
  end;

  [Table('roles')]
  TRole = class
  public
    [ManyToMany('user_roles', 'role_id', 'user_id')]
    property Users: TList<TUser> read GetUsers;
  end;

// Link / Unlink
Db.Users.LinkManyToMany(User, 'Roles', AdminRole);
Db.Users.UnlinkManyToMany(User, 'Roles', AdminRole);
Db.Users.SyncManyToMany(User, 'Roles', [Role1, Role2]);
Db.SaveChanges;
```

### Include (Eager Loading — Avoid N+1)

```pascal
uses Dext.Entity.Prototype;

var o := Prototype.Entity<TOrder>;

// 1. Type-safe include (Recommended - protects against typos)
var Orders := Db.Orders
  .Include(o.User)
  .Include(o.Items)
  .ToList;

// 2. Deep include (string path)
var Orders := Db.Orders
  .Include(o.User)
  .Include('Items.Product')
  .ToList;
```

### Strongly-Typed Fluent Joins

Dext Entity provides a set of strongly-typed fluent join methods: `JoinInner`, `JoinLeft`, `JoinRight`, `JoinFull`, and `JoinCross`. These compile directly to optimized database-level joins.

#### Explicit Join Condition
Write explicit `ON` conditions using entity Smart Properties:
```pascal
var u := TUser.Props;
var a := TAddress.Props;

var Results := Db.Users
  .JoinLeft<TAddress>('u', 'a', u.AddressId = a.Id)
  .Where(u.Age >= 18)
  .ToList;
```

#### Auto-Join via Relationship Metadata
If the entity relationship is configured in `TModelBuilder`, Dext resolves the `ON` condition automatically:
```pascal
var u := TUser.Props;

// ON condition is resolved automatically from the metadata relations
var Results := Db.Users
  .JoinInner<TAddress>
  .Where(u.Age >= 18)
  .ToList;
```

#### Cross Join (Cartesian Product)
Creates a cartesian product, generating no `ON` clause in SQL:
```pascal
var Results := Db.Users
  .JoinCross<TDepartment>
  .ToList;
```

Available join methods:
- `JoinInner<TInner>` / `JoinInner<TInner>(AliasOuter, AliasInner, Condition)`
- `JoinLeft<TInner>` / `JoinLeft<TInner>(AliasOuter, AliasInner, Condition)`
- `JoinRight<TInner>` / `JoinRight<TInner>(AliasOuter, AliasInner, Condition)`
- `JoinFull<TInner>` / `JoinFull<TInner>(AliasOuter, AliasInner, Condition)`
- `JoinCross<TInner>` / `JoinCross<TInner>(AliasOuter, AliasInner)`

### Cascade Delete

```pascal
[ForeignKey('user_id'), OnDeleteCascade]
property UserId: Integer;
```

## Inheritance Mapping

### Table Per Hierarchy (TPH) — Default

All classes share one table; a discriminator column identifies the type:

```pascal
type
  [Table('people'), Inheritance(TablePerHierarchy)]
  [DiscriminatorColumn('person_type')]
  TPerson = class
  private
    FId: Integer;
    FName: string;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;
    property Name: string read FName write FName;
  end;

  [DiscriminatorValue('student')]
  TStudent = class(TPerson)
  private
    FEnrollment: string;
  public
    property EnrollmentNumber: string read FEnrollment write FEnrollment;
  end;

  [DiscriminatorValue('teacher')]
  TTeacher = class(TPerson)
  private
    FSubject: string;
  public
    property Subject: string read FSubject write FSubject;
  end;

// Polymorphic query — returns TStudent and TTeacher instances
var People := Db.People.ToList;
for var P in People do
  if P is TStudent then
    WriteLn(TStudent(P).EnrollmentNumber);
```

TPH is fast — no JOINs needed for polymorphic queries.

### Table Per Type (TPT) — Normalized Schema

Each class gets its own table, sharing the PK:

```pascal
type
  [Table('vehicles')]
  [Inheritance(TablePerType)]
  TVehicle = class
  private
    FId: Integer;
    FBrand: string;
  public
    [PK]
    property Id: Integer read FId write FId;
    property Brand: string read FBrand write FBrand;
  end;

  [Table('cars')]
  TCar = class(TVehicle)
  private
    FDoors: Integer;
  public
    property NumberOfDoors: Integer read FDoors write FDoors;
  end;
```

## Specifications

Encapsulate reusable, composable query predicates:

```pascal
uses Dext.Specifications, Dext.Entity.Prototype;

type
  TActiveAdultSpec = class(TSpecification<TUser>)
  public
    constructor Create;
  end;

constructor TActiveAdultSpec.Create;
var
  u: TUser;
begin
  inherited Create;
  u := Prototype.Entity<TUser>;
  Where((u.IsActive = True) and (u.Age >= 18));
end;

// Usage
var Spec := TActiveAdultSpec.Create;
var Users := Db.Users.Where(Spec).ToList;
```

### Combining Specifications

```pascal
var Active := TActiveUserSpec.Create;
var Adult  := TAdultUserSpec.Create;

var Combined := Active.And(Adult);           // AND
var Either   := AdminSpec.Or(ModeratorSpec); // OR
var Inactive := ActiveSpec.Not;              // NOT

// Parameterized
var ByAge := TAgeRangeSpec.Create(MinAge, MaxAge);
```

## Migrations

```pascal
unit Migration_001_CreateUsers;

interface
uses
  Dext.Entity.Migrations;

type
  [Migration(1, 'CreateUsers')]
  TMigration_001_CreateUsers = class(TMigration)
  public
    procedure Up; override;
    procedure Down; override;
  end;

implementation

procedure TMigration_001_CreateUsers.Up;
begin
  CreateTable('users', procedure(T: TTableBuilder)
    begin
      T.AddColumn('id').AsInteger.PrimaryKey.AutoIncrement;
      T.AddColumn('name').AsString(100).NotNull;
      T.AddColumn('email').AsString(255).NotNull.Unique;
      T.AddColumn('created_at').AsDateTime.Default('CURRENT_TIMESTAMP');
    end);
end;

procedure TMigration_001_CreateUsers.Down;
begin
  DropTable('users');
end;
```

### Table Builder API

```pascal
T.AddColumn('id').AsInteger.PrimaryKey.AutoIncrement;
T.AddColumn('name').AsString(100).NotNull;
T.AddColumn('email').AsString(255).Nullable;
T.AddColumn('price').AsDecimal(10, 2).Default('0.00');
T.AddColumn('active').AsBoolean.Default('true');
T.AddColumn('created_at').AsDateTime;
T.AddColumn('data').AsText;           // CLOB/TEXT for large strings
T.AddColumn('binary').AsBlob;         // BLOB
T.AddColumn('uuid').AsGuid;

// Constraints & Indexes
T.AddColumn('email').AsString(255).Unique;
T.AddColumn('status').AsString(20).Check('status IN (''active'', ''inactive'')');
T.AddForeignKey('user_id', 'users', 'id').OnDeleteCascade;
T.AddIndex('idx_email', 'email');
T.AddUniqueIndex('idx_email_unique', 'email');

// Alter
AlterTable('users', procedure(T: TTableBuilder)
  begin
    T.AddColumn('phone').AsString(20).Nullable;
    T.DropColumn('legacy');
    T.RenameColumn('name', 'full_name');
  end);

// Raw SQL
Execute('CREATE INDEX CONCURRENTLY ...');
```

Register migrations — add to the program's `uses` clause:

```pascal
uses
  Migration_001_CreateUsers,
  Migration_002_AddEmailIndex;
// Dext auto-discovers [Migration] attributed classes
```

### Migration CLI

```bash
dext migrate:up               # Apply pending
dext migrate:down             # Rollback last
dext migrate:list             # Show status
dext migrate:generate --name AddOrdersTable
```

## Custom Type Converters

Dext provides a flexible type conversion system to handle data types not supported natively or to customize how Delphi types are stored in the database.

### 1. Attribute-Based Converter

Apply a converter to a specific property using the `[TypeConverter]` attribute.

```pascal
type
  [Table('events')]
  TEvent = class
  private
    FPayload: TJSONObject;
  public
    // Store TJSONObject as string in DB
    [TypeConverter(TJsonConverter)]
    property Payload: TJSONObject read FPayload write FPayload;
  end;
```

### 2. Global Registration

Register a converter globally to handle a specific Delphi type across all entities in your application.

```pascal
uses
  Dext.Entity.TypeConverters;

initialization
  // Option A: Register a general converter (CanConvert will be called)
  TTypeConverterRegistry.Instance.RegisterConverter(TMyGlobalConverter.Create);

  // Option B: Register specifically for a type (most efficient)
  TTypeConverterRegistry.Instance.RegisterConverterForType(
    TypeInfo(TMyCustomType), 
    TMyCustomTypeConverter.Create
  );
```

### Example: Unix Timestamp Converter

```pascal
type
  TUnixTimestampConverter = class(TTypeConverterBase)
  public
    function CanConvert(ATypeInfo: PTypeInfo): Boolean; override;
    function ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue; override;
    function FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue; override;
  end;

function TUnixTimestampConverter.CanConvert(ATypeInfo: PTypeInfo): Boolean;
begin
  Result := ATypeInfo = TypeInfo(TDateTime);
end;

function TUnixTimestampConverter.ToDatabase(const AValue: TValue; ADialect: TDatabaseDialect): TValue;
begin
  Result := DateTimeToUnix(AValue.AsType<TDateTime>);
end;

function TUnixTimestampConverter.FromDatabase(const AValue: TValue; ATypeInfo: PTypeInfo): TValue;
begin
  Result := UnixToDateTime(AValue.AsInt64);
end;
```

## Raw SQL with FromSql

```pascal
// Basic
var Users := Db.Users.FromSql('SELECT * FROM Users WHERE Active = 1').ToList;

// Parameterized (always use params to prevent injection)
var Adults := Db.Users
  .FromSql('SELECT * FROM Users WHERE Age >= :Age', [MinAge])
  .ToList;

// Chain fluent API after FromSql
var List := Db.Users
  .FromSql('SELECT * FROM Users WHERE Role = :Role', ['Admin'])
  .Where(Prop('Active') = True)
  .OrderBy(Prop('Name'))
  .Skip(10).Take(5)
  .ToList;

// Large result sets — streaming
var Query := Db.Users.FromSql('SELECT * FROM Users');
var Iterator := TSqlQueryIterator<TUser>.Create(Query);
try
  while Iterator.Next do
    ProcessUser(Iterator.Current);
finally
  Iterator.Free;
end;
```

`.AsNoTracking` — read-only, not tracked by DbContext.

## Stored Procedures

```pascal
type
  TMyProcs = class
  public
    [StoredProcedure('sp_GetCustomerBalance')]
    procedure GetBalance(
      [DbParam(pdInput)] CustomerId: Integer;
      [DbParam(pdOutput)] out Balance: Currency
    );

    [StoredProcedure('fn_GetActiveCustomers')]
    function GetActiveCustomers(
      [DbParam(pdInput)] RegionId: Integer
    ): IList<TCustomer>;
  end;

// Execute
var Procs := ServiceProvider.GetService<TMyProcs>;
var Balance: Currency;
Procs.GetBalance(123, Balance);

// Multiple result sets
var Results := Db.ExecuteProcedure('sp_GetInvoicesAndItems', [CustomerId]);
var Invoices := Results.Read<TInvoice>;
var Items    := Results.Read<TInvoiceItem>;
```

`[DbParam]` directions: `pdInput`, `pdOutput`, `pdInputOutput`, `pdReturnValue`.

## Locking

### Optimistic (Version Column)

```pascal
type
  [Table('products')]
  TProduct = class
  private
    FId: Integer;
    FVersion: Integer;
  public
    [PK, AutoInc]
    property Id: Integer read FId write FId;

    [Version]
    property Version: Integer read FVersion write FVersion; // Auto-incremented on update
  end;

// On conflict, SaveChanges raises DbUpdateConcurrencyException
```

### Pessimistic (Lock at Query Time)

```pascal
var Product := Db.Products
  .Where(Prop('Id') = 1)
  .Lock(TLockMode.Update)  // FOR UPDATE / UPDLOCK
  .FirstOrDefault;

Product.Price := Product.Price * 1.1;
Db.SaveChanges;
// Lock released when transaction ends
```

| Mode | SQL |
|------|-----|
| `TLockMode.None` | (default) |
| `TLockMode.Update` | `FOR UPDATE` / `UPDLOCK` |
| `TLockMode.Shared` | `FOR SHARE` / `HOLDLOCK` |

## Shadow Properties

Shadow properties are properties that are not defined in your Delphi entity class but are defined in the Dext model for that entity type. They are useful for data that shouldn't clutter your domain model (like `LastModifiedBy` or `IsSystemRecord`).

### Configuration

Override `OnModelCreating` to define shadow properties:

```pascal
procedure TAppDbContext.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TProduct>()
    .ShadowProperty('TenantId').HasDbType(ftString).HasMaxLength(50);
end;
```

### Accessing Shadow Values

Since the property doesn't exist in the class, you must use the `DbContext.Entry` API:

```pascal
var Product := Db.Products.Find(1);

// Read
var TenantId := Db.Entry(Product).Member('TenantId').CurrentValue.AsString;

// Write
Db.Entry(Product).Member('TenantId').CurrentValue := 'MyTenant';
Db.SaveChanges;
```

## Multi-Tenancy

### Strategy 1: Shared Database (Column-Based)

```pascal
type
  [Table('orders')]
  TOrder = class(TObject, ITenantAware)
  private
    FId: Integer;
    FTenantId: string;
    FDescription: string;
  public
    [PK]
    property Id: Integer read FId write FId;
    property TenantId: string read FTenantId write FTenantId; // Auto-populated
    property Description: string read FDescription write FDescription;
  end;
  // Or inherit from TTenantEntity
```

Provide the tenant with an `ITenantProvider` passed to the context constructor:

```pascal
Provider := TTenantProvider.Create;
Provider.Tenant := TTenant.Create('acme', 'Acme Corp', '');
Db := TMyDb.Create(DbContextOptions.UseSQLite('app.db'), Provider);
```

In a web app, `TMultiTenancyMiddleware` (`Dext.Web.MultiTenancy`) fills the scoped provider from an app-implemented `ITenantResolutionStrategy` and `ITenantStore`. If the tenant is not resolved, the provider has no tenant and **queries are not filtered**: reject the request first.

All queries and `Find` automatically get `WHERE TenantId = 'current-tenant'`, and added entities are stamped with the current tenant (replacing any assigned value).

`GenerateUpdate` / `GenerateDelete` (and batch templates) also append `AND TenantId = :…`. A row of another tenant is not touched and `SaveChanges` raises `EOptimisticConcurrencyException` for updates and deletes (bulk batch deletes do not report unmatched rows). `.IgnoreQueryFilters` bypasses the tenant filter and the stamp, like the soft-delete filter. Raw SQL is not filtered. Switching tenant does not clear the tracker: one context per tenant/request, or `Clear`.

### Strategy 2: Schema Isolation / Strategy 3: Database per Tenant

```pascal
// Schema per tenant: EnsureCreated creates it, the connection is switched to it
Provider.Tenant := TTenant.Create('customer1', 'Customer 1', '', 'customer1');
Db.EnsureCreated;

// Database per tenant: the context reconnects when the tenant changes
Provider.Tenant := TTenant.Create('customer2', 'Customer 2',
  'DriverID=SQLite;Database=customer2.db');
```

The schema (PostgreSQL: `SET search_path`) or the connection is applied before queries and writes. Schema switching is dialect-specific.

## Dynamic Query Filters

Override global filters (Soft Delete, Multi-Tenancy) for a specific query.

### Direct DbSet Call

```pascal
// All records — including soft-deleted
var All := Db.Users.IgnoreQueryFilters.ToList;

// Only soft-deleted records
var Trash := Db.Users.OnlyDeleted.ToList;
```

### Via Specification

```pascal
var Spec := TSpecification<TUser>.Create;
Spec.IgnoreQueryFilters;

var All := Db.Users.ToList(Spec);
```

### Admin Spec Pattern

```pascal
type
  TAllUsersAdminSpec = class(TSpecification<TUser>)
  public
    constructor Create;
  end;

constructor TAllUsersAdminSpec.Create;
var
  u: TUser;
begin
  inherited Create;
  u := Prototype.Entity<TUser>;
  IgnoreQueryFilters; // Bypasses Soft Delete & Tenancy
  OrderBy(u.Name.Asc);
end;

// Clean, reusable
var All := Db.Users.ToList(TAllUsersAdminSpec.Create);
```

`IgnoreQueryFilters` is **call-scoped** — it does not affect subsequent queries on the same `DbSet`.

## Database Sequence Generators & HiLo (Bulk Insert Optimization)

By default, entities configured with `[AutoInc]` cannot utilize high-performance batch insert (`PersistAddRange`) because IDs are generated on the database server during insert execution. Dext resolves this through client-side pre-allocation via sequences and the **HiLo Optimizer** (Pooled-lo algorithm).

### 1. Attribute Configuration
Configure the primary key with `[Sequence]`:

```pascal
type
  [Table('sequenced_users')]
  TSequencedUser = class
  private
    FId: IntType;
    FName: StringType;
  public
    [PK, Sequence('SEQ_USER_ID', 50)]
    property Id: IntType read FId write FId;

    property Name: StringType read FName write FName;
  end;
```

* **SequenceName**: Name of the sequence object in the database.
* **AllocationSize**: Range pre-allocated in memory per roundtrip (defaults to `50`).

### 2. Fluent API Configuration
```pascal
procedure TAppDbContext.OnModelCreating(Builder: TModelBuilder);
begin
  Builder.Entity<TSequencedUser>()
    .Property('Id')
    .UseSequence('SEQ_USER_ID', 50);
end;
```

### 3. Execution Integration
When inserting in bulk, Dext pre-allocates IDs on the client side, assigns them to the objects, and routes the operation safely through `PersistAddRange` using FireDAC batch DML (ExecuteBatch) in a single roundtrip:

```pascal
var BulkList: IList<TSequencedUser>;
BulkList := TCollections.CreateList<TSequencedUser>(False);
try
  for var i := 1 to 100 do
  begin
    var SU := TSequencedUser.Create;
    SU.Name := 'User ' + i.ToString;
    BulkList.Add(SU);
  end;

  // Fully optimized batch insert in a single network roundtrip!
  Db.Entities<TSequencedUser>.AddRange(BulkList);
  Db.SaveChanges;
finally
  for var SU in BulkList do SU.Free;
end;
```

## Dialect-Aware Batch UPDATE & DELETE (Spec S59)

Dext ORM optimizes bulk updates and deletions (`UpdateRange` / `RemoveRange`) using `TDextBatchStrategyFactory`, bypassing FireDAC Array DML emulation bottlenecks on engines without native protocol array binding.

```pascal
uses
  Dext.Entity, Dext.Entity.BatchStrategy;

// PostgreSQL: Single-statement UPDATE table SET ... FROM (VALUES (...), (...)) AS v(...)
// MySQL: Single-statement UPDATE table SET col = CASE WHEN pk = x THEN y END WHERE pk IN (...)
// Oracle/Firebird: Native Protocol Array DML
Db.Users.UpdateRange(UserArray);
Db.Users.RemoveRange(UserArray);
```


