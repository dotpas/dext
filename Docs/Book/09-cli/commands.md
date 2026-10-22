# CLI Commands

Overview of all `dext` CLI commands.

## Available Commands

| Command | Description |
|---------|-------------|
| `help` | Show all commands |
| `migrate:up` | Run pending migrations |
| `migrate:down` | Rollback last migration |
| `migrate:list` | List migration status |
| `migrate:generate` | Generate new migration |
| `test` | Run test suite |
| `scaffold` | Generate entities from DB |
| `ui` | Start web dashboard |
| `config:init` | Initialize configuration |
| `env:scan` | Scan for Delphi environments |
| `facade` | Generate Facade Unit |
| `index` | Generate Symbol Index Map |

## Migration Commands

### migrate:up

Run all pending migrations:

```bash
dext migrate:up
```

### migrate:down

Rollback the last applied migration:

```bash
dext migrate:down
```

### migrate:list

Show migration status:

```bash
dext migrate:list
```

Output:
```
Migration Status
================
[✓] 001_CreateUsers       Applied: 2026-01-05 10:30:00
[✓] 002_AddEmailToUsers   Applied: 2026-01-06 14:15:00
[ ] 003_CreateOrders      Pending
```

### migrate:generate

Create a new migration class:

```bash
dext migrate:generate --name CreateProducts
```

## Test Commands

### Basic test run

```bash
dext test
```

### With code coverage

```bash
dext test --coverage
```

### Generate HTML report

```bash
dext test --html --output TestReport.html
```

### All options

```bash
dext test --coverage --html --xml --json --output ./reports/
```

## Scaffold Command

Generate entities from database:

```bash
dext scaffold -c "mydb.db" -d sqlite -o Entities.pas
```

Options:
- `-c, --connection` - Connection string
- `-d, --driver` - Database driver (sqlite, pg, mssql, firebird)
- `-o, --output` - Output file
- `--fluent` - Use fluent mapping
- `-t, --tables` - Specific tables (comma-separated)

## Facade Command
 
Generate a "Facade Unit" (wildcard unit) that re-exports types and constants from a set of source units. This simplifies the `uses` clause for end-users.
 
```bash
dext facade -p Sources\Data -t Sources\Data\Dext.Entity.pas -x Dext.Entity
```
 
Options:
- `-p, --path` - Source directory to scan for Pascal units.
- `-t, --target` - Target output file (Pas file).
- `-x, --target-unit` - The name of the target unit (e.g., `Dext.Entity`).
- `--verbose` - Enable verbose logging.
 
## Index Command

Generate a complete map/index of all public symbols (classes, records, interfaces, methods, properties, constants, enums, etc.) across multiple formats with their exact declaration line numbers. Extremely useful for AI agents (such as Antigravity/Codex) and tools like NotebookLM.

```bash
dext index -p Sources -f markdown -o dext-symbols.md
```

Options:
- `-p, --path` - Source directory to scan recursively (Default: current directory).
- `-o, --output` - Path of the output file.
- `-f, --format` - Format of the symbol map: `markdown` (default), `json`, or `csv`.
- `-x, --exclude` - Comma-separated list of directories/files/units to ignore (e.g., `External,__recovery`).

## Dashboard

Use **DextSidecar** (system tray). The old `dext ui` CLI command has been removed.

```text
DextSidecar.exe   →  http://localhost:3030
```

## Dev Certs Command (`dev-certs`)

Generate and manage local self-signed SSL/TLS development certificates
for `localhost` and `127.0.0.1` (similar to `dotnet dev-certs https`), including automated Windows Kernel (`http.sys`) binding.

```bash
dext dev-certs https [--trust] [--force] [--out-cert <path>]
```

| Option | Description |
|--------|-------------|
| `https` | Subcommand to generate self-signed X.509 development certificate with SAN extension (`localhost`, `127.0.0.1`). |
| `--trust` | Imports certificate into Trusted Root Store (`Root`), Personal Store (`My`), and binds port 8080 in Windows Kernel (`http.sys`). |
| `--force` | Force overwriting existing certificates and keys in the target directory. |
| `--out-cert` | Path of the generated certificate file (default: `server.crt`). |

### Example Usage:

```bash
# Generate server.crt, server.key, server.pfx and bind in Windows Kernel
dext dev-certs https --trust
```

Generated artifacts:
- `server.crt`: PEM-encoded X.509 Certificate.
- `server.key`: PEM-encoded RSA Private Key.
- `server.pfx`: PKCS#12 bundle with linked private key for Windows Schannel.
- Automatic store installation in `LocalMachine\My` and Kernel binding via `netsh http add sslcert ipport=0.0.0.0:8080 certhash=<THUMBPRINT> appid={4f3b2c10-8a9b-4d7e-8f12-3456789abcde}`.

---

[← CLI](README.md) | [Next: Migrations →](migrations.md)
