# S75 — C++Builder Test Explorer (DLL + dedicated installer)

**Status:** Scaffolding / Planned (blocked on [discovery notes](../Plans/Dext-Testing-Cpp-Discovery.md))  
**Depends on:** S36 Expert stability (Delphi personality)

## Goal

Ship a **separate** RAD Studio design package for the **C++Builder personality** that reuses the Explorer Model/Presenter/IPC protocol, without requiring Delphi `Dext.Testing` BPLs in the C++ user’s project.

## Architecture

```
RAD Studio (C++Builder personality)
  └─ Dext.Testing.Design.Cpp.bpl  (OTA Expert, VCL UI)
       ├─ Shared protocol (JSON over Winsock — same as Delphi Expert)
       └─ Runner adapters (Phase 0 chooses MVP: Google Test XML, etc.)
Test exe (GTest / Catch2 / …)
  └─ Posts results to Expert port (or Expert parses JUnit/GTest XML)
```

## Deliverables

1. **DLL/BPL** — `Packages/<ver>/Dext.Testing.Design.Cpp.dpk` (or C++ package) containing dockable form + OTA registration only.
2. **Shared core** — extract IPC server + tree model into units with **zero** dependency on `Dext.Testing` runner (already mostly true via `Dext.Testing.Core` / Design-local JSON).
3. **Installer** — `Installers/DextTestExplorer-CppBuilder/` MSI or PowerShell setup that registers the package for C++ personalities only.
4. **Beta** — Thiago / David Millington / Leonardo after discovery checklist is filled.

## Non-goals (this spec revision)

- Full Delphi catalog inside C++ projects.
- Replacing Google Test / Catch2 assert APIs.
- WebView desktop shell.

## Scaffolding in repo

See `Sources/Testing/Design.Cpp/` and `Installers/DextTestExplorer-CppBuilder/`.
