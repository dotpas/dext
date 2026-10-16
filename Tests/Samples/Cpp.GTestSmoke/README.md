# Cpp.GTestSmoke — Google Test ↔ Dext Test Explorer

Project: `DextGTestSmokeTests.cbproj` (name contains `test` → aparece no combo do Explorer).

## Prerequisite

**Tools → GetIt → Google Test 1.17** (package `GoogleTest-13-cb`).  
GetIt builds `gtest` / libs under:

`$(BDSCOMMONDIR)\CatalogRepository\GoogleTest-13-cb\1.17\`

## Build settings (in `.cbproj`)

1. **Include path:** `..\..\..\Sources\Testing\Cpp` + GetIt `googletest\include`
2. **Library path:** GetIt `cbuilder\lib\$(Platform)\Release` (+ `$(BDSLIB)\win32c\$(Config)` on Win32 Clang)
3. **Win32 Clang** (`BCC_UseClassicCompiler=false`)
4. **Link with Dynamic RTL** = True (C++ Linker) — fixes `std::codecvt` / `locale` unresolved from `gtest.lib`
5. **Link with Delphi Runtime Library** = False
6. Link `gtest.lib` (Win32 / Win64x) or `gtest.a` (Win64) — `#pragma comment` in `SmokeGTestMain.cpp`

Sources:
- `SmokeGTestMain.cpp` — **MainSource** (`#pragma hdrstop` + `main` only). No `TEST`, no `System.hpp` (Delphi RTL is off for GetIt gtest).
- `SmokeGTestSuite.cpp` — OnePlusOne, IntentionalFail (open this for the suite tests)
- `SmokeGTestDeep.cpp` — DeepCallFail chain (`Gateway` → `Auditor` → `NoteFailureStack` + `EXPECT`)

### MainSource will not open in the editor

Known C++Builder quirk for this console project (Delphi RTL = False, GetIt gtest): double-click / File Open on the MainSource unit does nothing; sibling `.cpp` units open normally. **Acceptable for this sample.**

Workarounds: edit `SmokeGTestSuite.cpp` / `SmokeGTestDeep.cpp`, or **Project → View Source**. Click-to-code from Test Explorer targets the suite/deep units, not MainSource.

### Deep stack (Explorer)

Win32 Clang often cannot unwind (`CaptureStackBackTrace` empty). The smoke uses **`FailureStackScope` breadcrumbs** in Gateway → Auditor → TEST, then `NoteFailureStack()` before `EXPECT`. Explorer should show 3 frames.

The gtest message line `Ledger::Balance()` is only the **expression** inside `EXPECT_EQ` — not a stack frame. A single `[0] DeepCallFail @ …:line` means Host fell back to gtest location (no pending breadcrumb stack).

After changing headers: **Project → Clean**, then Build. Open **only** this `.cbproj` (not the GetIt GoogleTest group) to avoid double-build / IDE AV.

## Discover vs Run

| Explorer | Exe args | Effect |
|----------|----------|--------|
| **Refresh** | `--port N --discover -no-wait` | Walk GTest registry, POST `Idle` |
| **Run All / Selected** | `--port N -no-wait` | Execute; POST Passed/Failed |

## Standalone

```text
Win32\Debug\DextGTestSmokeTests.exe
Win32\Debug\DextGTestSmokeTests.exe --port 8102 --discover
```

Exit code ≠ 0 on a normal run because of `IntentionalFail`.
