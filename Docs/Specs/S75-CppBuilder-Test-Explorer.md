# S75 — C++Builder Test Explorer (mesma BPL + personalidade)

**Status:** Discovery (Sprint F) — ver [Cpp-Discovery](../Plans/Dext-Testing-Cpp-Discovery.md)  
**Depends on:** S36 Expert estável (Delphi)

## Goal

O **mesmo** `Dext.Testing.Design.bpl` instalado também para `CPlusPlusBuilder.Personality`, sem package `.Cpp` separado. Discovery valida o que funciona (menu, dock, `.cbproj`, DUnit) e o que falta (adapters GTest, etc.).

## Architecture (hipótese MVP)

```
RAD Studio (C++Builder personality)
  └─ Dext.Testing.Design.bpl  (mesmo OTA Expert Delphi)
       ├─ InstallIDEPackage(..., "CPlusPlusBuilder.Personality")
       └─ Descoberta / run: TBD após smoke DUnit + deep research
```

## Deliverables (após discovery)

1. Provar install do BPL na personalidade C++.  
2. Smoke DUnit (baseline Embarcadero).  
3. Lista de gaps (descoberta `.cbproj`, runners, compile path).  
4. Só então: adapters / GetIt actions — **sem** BPL `Design.Cpp`.

## Non-goals

- Package `Dext.Testing.Design.Cpp` (scaffold **removido** 2026-10).  
- Anunciar suporte C++ pronto.  
- Substituir GTest/Catch2 APIs.

## Removido do repo

`Sources/Testing/Design.Cpp/`, `Packages/*/Dext.Testing.Design.Cpp.*`, `Installers/DextTestExplorer-CppBuilder/`.
