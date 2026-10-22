# Dext Test Explorer — build and install

The Dext Test Explorer is the RAD Studio expert that shows the test tree inside the IDE. It discovers the suite, runs it, opens the failing line and, when the platform has a line source, paints coverage in the editor.

> [!IMPORTANT]
> Soon we will offer a simpler way to install the expert directly in the IDE, possibly through GetIt. Until then, you compile the DLL with your RAD Studio and register it with the script. This is not an Embarcadero feature yet.

> [!IMPORTANT]
> We are still deciding whether to publish a prebuilt DLL. The expert is not digitally signed. A development certificate has a cost, and without that signature Windows treats the file as a plugin from an unknown publisher. Build it on your machine. Do not run a loose DLL from an attachment.

## What you need

- RAD Studio with Delphi installed. The sample script uses Studio 37.0 (RAD Studio 13). Replace `37.0` with the folder of your version under `HKCU\Software\Embarcadero\BDS`.
- A clone of the Dext repository.
- The IDE closed while the script copies the DLL. `bds.exe` locks the registered file.

## 1. Build the DLL

Open a prompt at the repository root, call that version's `rsvars.bat`, and build the expert in Release.

32-bit IDE:

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Apps\TestExplorerExpert\Dext.Testing.Design.ExpertLib.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal
```

64-bit IDE: the same command with `/p:Platform=Win64`. The DLL name carries the `x64` suffix (`Dext.Testing.Design.ExpertLibx64.dll`).

Output lands in `Output\<version>\<Win32|Win64>\Release\`. The install script copies that file into `Apps\TestExplorerExpert\bin`, because the IDE locks the registered copy and a rebuild must still be free to write under `Output`.

## 2. Install

Close RAD Studio. From `Installers\DextTestExplorer`:

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0
```

For the 64-bit IDE:

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Ide64
```

Open RAD Studio. On the View menu, open **Dext Test Explorer**. The window docks like the Project Manager.

To remove the registry value without deleting the DLL:

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Uninstall
```

After a source change: build again (the IDE can stay open, because the build writes to `Output`), close the IDE, run the script again, and reopen.

## 3. Open a test project

The Explorer combo lists the open project when the file is a `.dproj` or a `.cbproj` and the file name contains `test`. A Delphi package (`.dpk`) stays out.

| What you want to see | Project |
|---|---|
| DUnit on C++Builder | `Tests\Samples\Cpp.DUnitSmoke\DextDUnitSmokeTestsP.cbproj` |
| Google Test on C++Builder | `Tests\Samples\Cpp.GTestSmoke\DextGTestSmokeTests.cbproj` |
| A Delphi suite with `Dext.Testing` | a `.dproj` whose name contains `test`, for example `Tests\Core\UnitTests\Dext.Core.UnitTests.dproj` |

Open the `.cbproj` on its own. The DUnit sample wants Win32 Clang (`BCC_UseClassicCompiler=false`). The Google Test sample wants Google Test 1.17 from the RAD Studio GetIt package manager (`GoogleTest-13-cb`). That GetIt entry is the test library. The expert itself is still installed by the script on this page.

Both samples are manual. `IntentionalFail` and `DeepCallFail` fail on purpose, so the tree can show a failure and the stack can open the `.cpp`. The Google Test exe exits with a non-zero code. That is why it stays out of `Scripts\run_examples.ps1`.

## What each feature accepts

| Feature | Project | Where it works |
|---|---|---|
| Discover the suite, run it, open the failing line | `.dproj` with `Dext.Testing` | The platforms of that Delphi project |
| Discover the suite, run it, open the failing line | `.cbproj` DUnit or Google Test | The C++ project you built. The DUnit sample on this page is Win32 Clang |
| Line coverage | `.dproj` | Delphi Code Coverage, with the detailed map (Debug Trace / MAP Detailed) |
| Line coverage | `.cbproj` | The **Win64x** platform only (`bcc64x`) |
| Stack from the map | `.cbproj` | The detailed map. That map has no line table |

On a `.cbproj`, when the active platform is Win32, classic Win64, `bcc32c`, or `bcc64`, the Explorer hides the coverage checkbox, the coverage menu, and the Coverage tab. On Run, the log says that Win32 and classic Win64 do not support code coverage. A `.dproj` keeps Delphi Code Coverage.

## Line coverage on Delphi

On the `.dproj`, turn on the detailed map (Debug Trace / MAP Detailed). In the Explorer, check **Collect code coverage on Run All / Selected** and run the suite. The expert calls Delphi Code Coverage, reads the XML, and paints the gutter. The same report comes from the command line with `dext test --coverage`.

## Line coverage on C++Builder (Win64x only)

In the Win64x option group, the compiler and the linker need these two lines. MSBuild invokes `bcc64x -cc1`. The driver flag `-fprofile-instr-generate` does not reach that mode.

```xml
<BCC_UserSuppliedOptions>-fprofile-instrument=clang -fcoverage-mapping $(BCC_UserSuppliedOptions)</BCC_UserSuppliedOptions>
<ILINK_AdditionalOptions>-lclang_rt.profile-x86_64 $(ILINK_AdditionalOptions)</ILINK_AdditionalOptions>
```

`libclang_rt.profile-x86_64.a` already ships with RAD Studio, under `lib\clang\20\lib\windows`. The instrumented test writes `default.profraw` next to the exe. The Explorer merges that file with `llvm-profdata` and asks `llvm-cov` for LCOV. Both tools are LLVM 20, installed separately. RAD Studio does not ship `llvm-cov` or `llvm-profdata`. LLVM 18 cannot read the profraw that `bcc64x` writes.

The Win64x group in `Tests\Samples\Cpp.GTestSmoke\DextGTestSmokeTests.cbproj` already carries those two options. Check Collect coverage, select Win64x, and run.

The C++ map still serves the stack. It has no line table for Delphi Code Coverage, so that program stays on the `.dproj`.

## What this guide does not promise

C++ support in the expert is in review. Win32, classic Win64, `bcc32c`, and `bcc64` stay without line coverage. We are not embedding a profiler for those platforms. An integrated profiler is an idea for later.

---

[← Testing](README.md)
