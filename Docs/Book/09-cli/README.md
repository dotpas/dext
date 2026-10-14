# 9. CLI Tool

The `dext` CLI provides commands for migrations, testing, scaffolding, and more.

## Chapters

1. [Commands](commands.md) - Overview of all commands
2. [Migrations](migrations.md) - Database schema management
3. [Scaffolding](scaffolding.md) - Generate entities from DB
4. [Testing](testing.md) - Run tests with coverage
5. [Dashboard](dashboard.md) - Web UI for monitoring
6. [Documentation](documentation.md) - Generate API Docs

## Quick Reference

```bash
# Help
dext help

# Migrations
dext migrate:up
dext migrate:down
dext migrate:list
dext migrate:generate

# Testing
dext test
dext test --coverage
dext test --html

# Scaffolding
dext scaffold -c "mydb.db" -d sqlite -o Entities.pas

# Dashboard — DextSidecar.exe (tray), not dext ui

# Documentation
dext doc
dext doc --output ./Docs

# Symbol Indexing
dext index
dext index --path ./Sources --format json
```

## Installation and Building

The Dext CLI can be used in two ways:

### 1. Global Tool (dext.exe)
The framework includes a project called **DextTool.dpr** located in `Apps\CLI`.
- This project has a **post-build script** that automatically copies and renames the output to `$(DEXT)\Apps\dext.exe`.
- To use it globally, add the `$(DEXT)\Apps` folder to your Windows **PATH** environment variable.
- You can build it using the Delphi IDE or via command line:
  ```bash
  msbuild Apps\CLI\DextTool.dproj /p:Configuration=Release
  ```

### 2. Embedded in your application
You can also embed the CLI directly in your application. Add `Dext.Hosting.CLI` to your uses:

```pascal
uses
  Dext.Hosting.CLI;

begin
  var CLI := TDextCLI.Create(
    function: IDbContext
    begin
      Result := TAppDbContext.Create(Connection, Dialect);
    end
  );
  
  if CLI.Run then
    Exit; // CLI command executed
    
  // Normal app startup...
end.
```

---

[← Testing](../08-testing/README.md) | [Next: Commands →](commands.md)
