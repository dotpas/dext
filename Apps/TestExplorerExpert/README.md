# Dext Test Explorer — Expert DLL (ship)

Standalone IDE plugin for **Delphi and C++Builder** personalities (same `bds.exe`).

## Diagnose load failures

After starting the IDE, open:

`%TEMP%\DextExpertLib.log`

Expect lines: `library … loaded` → `InitWizard: enter` → `AddWizard` → `OnInitTimer` → `RegisterExpert` → `SetupMenus: menu added`.  
If the file is missing, the DLL was not loaded (registry path / bitness). If it stops mid-way, that step is the failure.

## Expert DLL load (GExperts pattern)

- Export `InitWizard` as `INITWIZARD0001` (`WizardEntryPoint`)
- Register with `IOTAWizardServices.AddWizard` (not only `RegisterProc`)
- Defer menus/dockable form ~1.2s after load (Tools menu is not ready in `InitWizard`)

## Build (validated)

1. Open `Dext.Testing.Design.ExpertLib.dproj` in the target RAD Studio version.
2. **Search path (project):** `..\..\Sources\Testing\Design` only for Design units. Do **not** add `$(BDS)\source\ToolsAPI` (recompiles `ToolsAPI.pas` → missing `DockForm`; use **designide**).
3. Other Dext units come from the **global Library path** (Smart Setup / TMS).
4. **Link with runtime packages:** true — `rtl;designide;vcl`.
5. Build matching the IDE bitness:
   - **32-bit IDE** → Win32 Release → register under `Experts`
   - **64-bit IDE** (RAD Studio 13+) → Win64 Release → register under `Experts X64` (`-Ide64`)

Build output: `Output\<ProductVersion>\<Win32|Win64>\Release\Dext.Testing.Design.ExpertLib.dll`  
Installed copy (registry): `Apps\TestExplorerExpert\bin\<Win32|Win64>\Dext.Testing.Design.ExpertLib.dll`

## Install

The install script **copies** Output → Apps and registers the Apps path (so rebuilds are not locked by the IDE):

```powershell
cd ..\..\Installers\DextTestExplorer
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0          # Win32 IDE
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Ide64   # Win64 IDE
```

Close the IDE before re-running install so the Apps copy can be overwritten.

## Dev vs ship

| Mode | Artifact |
|------|----------|
| Framework authors | `Packages\*\Dext.Testing.Design.bpl` (design package) |
| End users / C++ | This DLL + installer (no monorepo rebuild) |

## C++ test bridge

Headers for GTest / DUnit C++ live under `Sources\Testing\Cpp\` — add that folder to the C++ project include path; they speak the same HTTP Host protocol as Delphi adapters (`--port`).
