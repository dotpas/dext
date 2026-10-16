# Cpp.DUnitSmoke — DUnit C++ ↔ Dext Test Explorer

Project: `DextTestExplorerTests.cbproj` (name contains `test` → aparece no combo do Explorer).

| File | Role |
|------|------|
| `DextDUnitSmokeTests.cpp` | `main` → `RunDextDUnit` |
| `SmokeTestCase.h/.cpp` | pass + direct fail + `TestDeepCallFail` (`RegisterDunitTestCase<T>`) |
| `SmokeDeep.h/.cpp` | Gateway → Auditor → `NoteFailureStack` + `CheckEquals` (multi-frame stack) |
| `DextTestExplorerTests.cpp` | wizard stub — **not compiled** |
| `Sources/Testing/Cpp/*.hpp` | Host + DUnit discover/run |

## Build settings (already in `.cbproj`)

1. **Include path:** `..\..\..\Sources\Testing\Cpp`
2. **Win32 Clang** (`BCC_UseClassicCompiler=false`) — classic fails in `SystemRtti.h`
3. **Link libs from `$(BDSLIB)\win32c\$(Config)`** — not `win32\`
4. Console + DUnit (`dunitrtl`)

After changing headers: **Project → Clean**, then Build.

## Discover vs Run (TestInsight-style)

DUnit already has the tree (`RegisteredTests`). The adapter walks it — it does **not** invent nodes from the `.exe` name (DUnit’s registry root is `ExtractFileName(ParamStr(0))`).

| Explorer | Exe args | Effect |
|----------|----------|--------|
| **Refresh** | `--port N --discover -no-wait` | Walk tree, POST `Idle` for each leaf — **no asserts** |
| **Run All / Selected** | `--port N -no-wait` | `GET /tests` filter, execute, POST Passed/Failed |

## Stack / MAP / Location

| Artifact | Role |
|----------|------|
| **`.tds`** | IDE debugger symbols |
| **`.map` DetailedSegments** | Linker map (`ILINK_MapFileType=DetailedSegments`, UI: Detailed segment map). Not the string `Detailed` — that breaks ilink (`DETAILED.OBJ`). Tiny default `.map` (~200 B) is useless. |
| **`StackTrace()`** | Empty in stock **dunitrtl** unless that RTL was built with JCL/madExcept (project link settings do not rebuild dunitrtl). |
| **`AddressInfo()`** | Raw `$XXXXXXXX` only. Adapter resolves via EXE `.map` + ASLR → `[0] TClass::Method (File.cpp)`. |
| **`NoteFailureStack()`** | Snap *before* `CheckEquals` for deep chains (`TestDeepCallFail`). After unwind, DUnit only keeps ExceptAddr. |

**Location / double-click** uses a scan of `TClass::TestMethod` in `.cpp` / `.h`. MAP has publics, not line numbers.

## Standalone

```text
Win32\Debug\DextTestExplorerTests.exe
Win32\Debug\DextTestExplorerTests.exe --port 8102 --discover
```

Exit code ≠ 0 on a normal run because of `TestIntentionalFail`.
