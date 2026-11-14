# 🗄️ Orm.EntityDemo - Showcase do Dext ORM

Uma demonstração abrangente das capacidades do **Dext Entity ORM**. Este projeto mostra funcionalidades modernas de ORM incluindo queries fortemente tipadas, lazy loading, soft delete e suporte multi-banco.

---

## ✨ Funcionalidades Demonstradas

### Funcionalidades Core do ORM
- **Operações CRUD** - Create, Read, Update, Delete com change tracking automático
- **Relacionamentos** - Foreign keys, propriedades de navegação, ações em cascata
- **Lazy Loading** - Carregamento automático de entidades relacionadas ao acessar
- **Explicit Loading** - Carregamento manual com `.Include()`
- **No Tracking** - Queries read-only para performance

### Queries Avançadas
- **Expressões Fortemente Tipadas** - `Where(TUserType.Age > 18)`
- **Fluent Query Builder** - Métodos encadeáveis: `.Where().OrderBy().Take()`
- **Padrões de SQL Join** - Veja `EntityDemo.Tests.Join.pas` para `.AsNoTracking + .Join('table','alias', jtInner, condition) + .OrderBy + .ToList`
- **Join Genérico (Em Memória)** - Veja `EntityDemo.Tests.Join.pas` (`Join<TInner,TKey,TResult>` materializa sequências externa/interna e correlaciona em memória)
- **Padrão Specifications** - Critérios de query reutilizáveis
- **Filtros Complexos** - Condições AND/OR, LIKE, StartsWith, IsNull

### Integridade de Dados
- **Composite Keys** - Chaves primárias multi-coluna (Integer + String)
- **Soft Delete** - Exclusão lógica com atributo `[SoftDelete]`
- **Controle de Concorrência** - Lock otimístico com `[Version]`
- **Tipos Nullable** - Suporte completo a `Nullable<T>`

### Gerenciamento de Schema
- **Migrations** - Versionamento de schema do banco
- **Scaffolding** - Engenharia reversa de entidades de DB existente
- **Fluent Mapping** - Alternativa aos atributos

### Performance
- **Operações em Lote** - Insert/update/delete em batch
- **Lazy Query Execution** - Geração de SQL adiada
- **Suporte Async** - Operações de banco não-bloqueantes

---

## 🚀 Começando

### Pré-requisitos
- Delphi 11+ (Alexandria ou posterior)
- Dext Framework no Library Path

### Executando os Testes

1. Abra `Orm.EntityDemo.dproj` no Delphi
2. Compile o projeto (F9)
3. Execute o binário

Os testes usam **SQLite Em Memória** por padrão - nenhuma configuração de banco necessária!

### Trocar Provedor de Banco

Edite `Orm.EntityDemo.dpr` e altere o provedor:

```pascal
// Padrão: SQLite Memory (não requer configuração)
ConfigureDatabase(dpSQLiteMemory);

// SQLite Arquivo (persistido)
ConfigureDatabase(dpSQLite);

// PostgreSQL
ConfigureDatabase(dpPostgreSQL);

// Firebird
ConfigureDatabase(dpFirebird);

// SQL Server
ConfigureDatabase(dpSQLServer);

// MySQL / MariaDB
ConfigureDatabase(dpMySQL);
```

---

## 📋 Suíte de Testes

A demo inclui **18 suítes de teste abrangentes**:

| # | Teste | Descrição |
|---|-------|-----------|
| 1 | **TCRUDTest** | Create, Read, Update, Delete básico |
| 2 | **TRelationshipTest** | Foreign Keys e propriedades de navegação |
| 3 | **TAdvancedQueryTest** | Queries complexas com filtros e projeções |
| 4 | **TCompositeKeyTest** | Chaves primárias multi-coluna |
| 5 | **TExplicitLoadingTest** | Carregamento manual de entidades relacionadas |
| 6 | **TLazyLoadingTest** | Carregamento automático ao acessar propriedade |
| 7 | **TFluentAPITest** | Query builder e operações estilo LINQ |
| 8 | **TLazyExecutionTest** | Execução de query adiada |
| 9 | **TBulkTest** | Operações de insert/update/delete em lote |
| 10 | **TConcurrencyTest** | Controle de concorrência otimístico |
| 11 | **TScaffoldingTest** | Engenharia reversa do banco de dados |
| 12 | **TMigrationsTest** | Versionamento de schema e migrations |
| 13 | **TCollectionsTest** | Integração com IList<T> |
| 14 | **TNoTrackingTest** | Queries read-only para performance |
| 15 | **TMixedCompositeKeyTest** | Composite keys Integer + String |
| 16 | **TSoftDeleteTest** | Exclusão lógica com filtros |
| 17 | **TAsyncTest** | Operações de banco assíncronas |
| 18 | **TTypeSystemTest** | Expressões de propriedade fortemente tipadas |

---

## 📖 Exemplos de Código

### CRUD Básico

```pascal
// Create
var User := TUser.Create;
User.Name := 'Alice';
User.Age := 25;
Context.Entities<TUser>.Add(User);
Context.SaveChanges;

// Read
var Found := Context.Entities<TUser>.Find(1);

// Update
Found.Age := 26;
Context.Entities<TUser>.Update(Found);
Context.SaveChanges;

// Delete
Context.Entities<TUser>.Remove(Found);
Context.SaveChanges;
```

### Queries Fortemente Tipadas

```pascal
// Usando TypeSystem para segurança em tempo de compilação
var Adults := Context.Entities<TUser>.QueryAll
  .Where(TUserType.Age >= 18)
  .OrderBy(TUserType.Name.Asc)
  .ToList;

// Filtros complexos
var NYAdults := Context.Entities<TUser>.QueryAll
  .Where((TUserType.Age > 21) and (TUserType.City = 'NY'))
  .ToList;

// Operações com strings
var AliceUsers := Context.Entities<TUser>.QueryAll
  .Where(TUserType.Name.StartsWith('Ali'))
  .ToList;
```

### Definição de Entidade

```pascal
[Table('users')]
TUser = class
private
  FId: Integer;
  FName: string;
  FAddressId: Nullable<Integer>;
  FAddress: Lazy<TAddress>;
public
  [PK, AutoInc]
  property Id: Integer read FId write FId;

  [Column('full_name')]
  property Name: string read FName write FName;

  [ForeignKey('AddressId'), NotMapped]
  property Address: TAddress read GetAddress write SetAddress;
end;
```

### Soft Delete

```pascal
// Entidade com soft delete
[Table('tasks'), SoftDelete('IsDeleted')]
TTask = class
  // ...
  property IsDeleted: Boolean read FIsDeleted write FIsDeleted;
end;

// Query normal exclui deletados
var ActiveTasks := Context.Entities<TTask>.QueryAll.ToList;

// Incluir deletados
var AllTasks := Context.Entities<TTask>.QueryAll
  .IgnoreQueryFilters
  .ToList;

// Apenas deletados
var Trash := Context.Entities<TTask>.QueryAll
  .OnlyDeleted
  .ToList;
```

---

## ⚙️ Configuração de Banco de Dados

### SQLite (Padrão)
Não requer configuração! Usa banco em memória.

### PostgreSQL
```pascal
TDbConfig.ConfigurePostgreSQL('localhost', 5432, 'postgres', 'postgres', 'senha');
```

### Firebird
```pascal
TDbConfig.ConfigureFirebird('C:\temp\test.fdb', 'SYSDBA', 'masterkey');
```

### SQL Server
```pascal
// Autenticação Windows
TDbConfig.ConfigureSQLServerWindowsAuth('localhost', 'dext_test');

// Autenticação SQL
TDbConfig.ConfigureSQLServer('localhost', 'dext_test', 'sa', 'senha');
```

### Oracle

> **Nota**: precisa de `{$DEFINE DEXT_ENABLE_DB_ORACLE}` no `Dext.inc`. No
> Oracle um "banco" é um usuário (esquema) do banco plugável.

```pascal
// Servidor, porta, serviço, esquema, senha do esquema, senha do DBA, oci.dll
TDbConfig.ConfigureOracle('localhost', 1521, 'XEPDB1', 'dext_demo', 'dext_demo',
  'senha-do-SYSTEM', 'C:\db\Oracle\21c\dbhomeXE\bin\oci.dll');
```

Rode com `Orm.EntityDemo.exe oracle`. Quando a variável de ambiente
`DEXT_ORACLE_ADMIN_PASSWORD` tem a senha do `SYSTEM`, o esquema `dext_demo` é
criado se não existir.

- O `oci.dll` precisa ter o bitness do executável (Win64: o cliente do Oracle XE;
  Win32: um Instant Client de 32 bits). `ConfigureOracle` põe a pasta dele no
  `PATH` do processo.
- O Oracle guarda a string vazia como `NULL`: duas verificações da suíte conferem
  `IS NOT NULL` em vez de `<> ''` nele.
- Resultado no Oracle XE 21c (Win64): 193 passam, 0 falham.


### MySQL / MariaDB

> **Nota**: Para MySQL/MariaDB você precisa configurar o caminho da biblioteca cliente.

```pascal
// Com VendorLib e VendorHome (recomendado para 64-bit)
TDbConfig.ConfigureMySQL(
  'localhost',           // Host
  3306,                  // Porta
  'dext_test',           // Banco de dados
  'root',                // Usuário
  'senha',               // Senha
  'libmariadb.dll',      // VendorLib
  'C:\Program Files\MariaDB 12.1'  // VendorHome
);

// Configuração mínima (se libmariadb.dll está no PATH)
TDbConfig.ConfigureMySQL('localhost', 3306, 'dext_test', 'root', 'senha');
```

**Pré-requisitos para MariaDB:**
1. Instale o MariaDB Server (ex: MariaDB 12.1)
2. Certifique-se que `libmariadb.dll` está acessível (no PATH ou especificando VendorHome)
3. Para apps Delphi 64-bit, use instalação MariaDB 64-bit
4. O banco será criado automaticamente se não existir

---

## 🔧 Estrutura do Projeto

```
Orm.EntityDemo/
├── Orm.EntityDemo.dpr              # Programa principal
├── EntityDemo.DbConfig.pas         # Configuração do banco
├── EntityDemo.Entities.pas         # Definições de entidades
├── EntityDemo.Entities.Info.pas    # Metadados do TypeSystem
├── EntityDemo.Tests.Base.pas       # Classe base de testes
├── EntityDemo.Tests.*.pas          # Suítes de teste individuais
└── README.md                       # Este arquivo
```

---

## 🐛 Solução de Problemas

### "Driver not found"
Certifique-se de que os drivers FireDAC estão na cláusula uses:
- SQLite: `FireDAC.Phys.SQLite`
- PostgreSQL: `FireDAC.Phys.PG`
- Firebird: `FireDAC.Phys.FB`
- SQL Server: `FireDAC.Phys.MSSQL`
- MySQL/MariaDB: `FireDAC.Phys.MySQL`
- Oracle: `FireDAC.Phys.Oracle` e `FireDAC.Phys.OracleDef` (com `DEXT_ENABLE_DB_ORACLE`)

### MySQL "VendorLib not found"
Para MySQL/MariaDB, certifique-se de especificar VendorHome e VendorLib corretos:
```pascal
// Exemplo MariaDB 12.1 64-bit
TDbConfig.ConfigureMySQL('localhost', 3306, 'dext_test', 'root', 'senha',
  'libmariadb.dll', 'C:\Program Files\MariaDB 12.1');
```

### "Table already exists"
Os testes automaticamente removem tabelas antes de executar. Se ver este erro:
1. Delete o arquivo `test.db` (se usando SQLite arquivo)
2. Ou remova manualmente as tabelas no seu banco

### Memory Leaks Reportados
Alguns leaks são esperados com singletons do FDConnection. O framework usa FastMM4 para detecção de leaks.

---

## 📚 Documentação Relacionada

- [Guia do Dext ORM](../../Docs/orm-guide.md)
- [Suporte a Tipos Nullable](../../Docs/NULLABLE_SUPPORT.md)
- [Configuração de Banco de Dados](../../Docs/DATABASE_CONFIG.md)
- [English Version](README.md)

---

## 📄 Licença

Este exemplo faz parte do Dext Framework e está licenciado sob a Apache License 2.0.

---

*Happy Coding! 🚀*
