# Dext Database Integration Testing

This directory contains Docker infrastructure for running ORM integration tests against multiple database engines.

## Quick Start

```bash
# Start all database containers
.\Run-DBTests.ps1 -StartOnly

# Run tests against all databases
.\Run-DBTests.ps1

# Run tests against specific database
.\Run-DBTests.ps1 -Database pg

# Stop all containers
.\Run-DBTests.ps1 -StopOnly
```

## Supported Databases

ORM drivers in Dext are **Stable** for: PostgreSQL, SQL Server, MySQL, SQLite, Oracle, Firebird, and **InterBase**.

This folder is the **Docker integration-test harness** (Preview → evolve toward a Testcontainers-like DX; optional Sidecar tab later). Status below is for **containers in this compose**, not driver maturity.

| Database | Container | Port | Container harness |
|----------|-----------|------|-------------------|
| PostgreSQL 15 | `dext_postgres` | 5432 | ✅ Stable |
| SQL Server 2022 | `dext_sqlserver` | 1433 | ✅ Stable |
| MySQL 8.0 | `dext_mysql` | 3306 | ✅ Stable |
| Firebird 4.0 | `dext_firebird` | 3050 | ✅ Stable |
| Oracle 23c Free | `dext_oracle` | 1521 | ✅ Stable |
| InterBase | — | — | Host/native (no image in this compose yet) |
| SQLite | — | — | File DB (no container) |
| Redis | `dext_redis` | 6379 | 🔮 Cache / future tests |

## Connection Strings

### PostgreSQL
```
Server=localhost;Port=5432;Database=dext_test_db;User_Name=dext_user;Password=dext_password
```

### SQL Server
```
Server=localhost,1433;Database=dext_test_db;User_Id=sa;Password=DextPassword123!
```

### MySQL
```
Server=localhost;Port=3306;Database=dext_test_db;User_Name=dext_user;Password=dext_password
```

### Firebird
```
Server=localhost;Port=3050;Database=dext_test_db;User_Name=SYSDBA;Password=masterkey
```

### Oracle
```
Server=localhost:1521/FREEPDB1;User_Name=dext_user;Password=dext_password
```

## Manual Testing

After starting containers, you can connect using any database client:

```bash
# PostgreSQL
psql -h localhost -p 5432 -U dext_user -d dext_test_db

# SQL Server (using sqlcmd)
sqlcmd -S localhost,1433 -U sa -P "DextPassword123!"

# MySQL
mysql -h localhost -P 3306 -u dext_user -p dext_test_db

# Firebird (using isql)
isql localhost:dext_test_db -u SYSDBA -p masterkey
```

## Docker Commands

```bash
# View running containers
docker ps --filter "name=dext_"

# View logs
docker logs dext_postgres
docker logs dext_sqlserver

# Enter container shell
docker exec -it dext_postgres bash
docker exec -it dext_sqlserver bash

# Restart specific container
docker restart dext_postgres
```

## Troubleshooting

### SQL Server: Password complexity
SQL Server requires a strong password with uppercase, lowercase, numbers, and special characters. The default password is `DextPassword123!`.

### Oracle: Slow startup
Oracle container takes longer to start (up to 2 minutes). Increase `-WaitSeconds` if needed:
```bash
.\Run-DBTests.ps1 -WaitSeconds 120
```

### Port conflicts
If ports are in use, stop conflicting services or modify `docker-compose.yml`.

### Memory issues
Oracle and SQL Server require significant memory. Ensure Docker has at least 4GB allocated.
