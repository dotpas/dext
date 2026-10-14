# Dext Test Explorer — C++Builder personality (scaffold)

This folder will host the **C++Builder-only** OTA Expert surface.

## Current state

Scaffolding only. Do **not** announce as shipping. Fill requirements from `Docs/Plans/Dext-Testing-Cpp-Discovery.md` before implementing adapters.

## Planned layout

| Path | Role |
|------|------|
| `Dext.Testing.Design.Cpp.Registration.pas` | OTA register/unregister for C++ personality |
| `Dext.Testing.Design.Cpp.Expert.pas` | Tools menu entry |
| Shared UI | Reuse or thin-wrap `Design/DockableForm` once package deps are clean |
| `Adapters/` | Google Test / Catch2 result bridges (MVP TBD by discovery) |

## Build

Package project will live under `Packages/<studio>/Dext.Testing.Design.Cpp.dpk` and must **not** `requires Dext.Testing` (framework). Prefer Design-local IPC + JSON only.

## Installer

`Installers/DextTestExplorer-CppBuilder/Install-DextTestExplorer-Cpp.ps1`
