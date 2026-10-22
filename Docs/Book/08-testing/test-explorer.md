# Dext Test Explorer — manual install

The Dext Test Explorer is the RAD Studio expert that shows the test tree inside the IDE. It discovers the suite, runs it, opens the failing line and, when the platform allows it, paints line coverage in the editor.

The distribution we want for this expert is GetIt. Until that is in place, anyone who wants to try it installs from source.

> [!IMPORTANT]
> We are still deciding whether to publish a prebuilt DLL. The expert is not digitally signed. A development certificate has a cost, and without that signature Windows treats the file as a plugin from an unknown publisher. This guide asks you to compile the DLL with your own RAD Studio and register that path with the install script. Do not run a loose DLL from an attachment.

## What you need

- RAD Studio with Delphi installed. The sample script uses Studio 37.0 (RAD Studio 13). Replace `37.0` with the folder of your version under `HKCU\Software\Embarcadero\BDS`.
- A clone of the Dext repository.
- The IDE closed while the script copies the DLL. `bds.exe` locks the registered file.

## Build the expert

Open a prompt where that version's `rsvars.bat` exists and build the design package in Release.

32-bit IDE:

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Apps\TestExplorerExpert\Dext.Testing.Design.ExpertLib.dproj /t:Build /p:Config=Release /p:Platform=Win32 /v:minimal
```

64-bit IDE: the same command with `/p:Platform=Win64`. The DLL name carries the `x64` suffix.

Output lands in `Output\<version>\<Win32|Win64>\Release\`. The install script copies that file into `Apps\TestExplorerExpert\bin`, because the IDE locks the registered copy and a rebuild must still be free to write under `Output`.

## Register the expert

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

## Line coverage on Delphi

On the `.dproj`, turn on the detailed map (Debug Trace / MAP Detailed). In the Explorer, check **Collect code coverage on Run All / Selected** and run the suite. The expert calls Delphi Code Coverage, reads the XML and paints the gutter. The same report comes from the command line with `dext test --coverage`.

## Line coverage on C++Builder

C++ line coverage stays on the **Win64x** platform (`bcc64x`). When the active `.cbproj` is Win32, classic Win64, or any other platform, the Explorer hides the coverage checkbox, the coverage menu and the Coverage tab. On Run, the log says that Win32 and classic Win64 do not support code coverage.

In the Win64x option group, the compiler and the linker need these two lines. MSBuild invokes `bcc64x -cc1`. The driver flag `-fprofile-instr-generate` does not reach that mode.

```xml
<BCC_UserSuppliedOptions>-fprofile-instrument=clang -fcoverage-mapping $(BCC_UserSuppliedOptions)</BCC_UserSuppliedOptions>
<ILINK_AdditionalOptions>-lclang_rt.profile-x86_64 $(ILINK_AdditionalOptions)</ILINK_AdditionalOptions>
```

`libclang_rt.profile-x86_64.a` already ships with RAD Studio, under `lib\clang\20\lib\windows`. The instrumented test writes `default.profraw` next to the exe. The Explorer merges that file with `llvm-profdata` and asks `llvm-cov` for LCOV. Both tools are LLVM 20, installed separately. RAD Studio does not ship `llvm-cov` or `llvm-profdata`. LLVM 18 cannot read the profraw that `bcc64x` writes.

The C++ map still serves the stack. It has no line table for Delphi Code Coverage, so do not point that program at a C++ exe.

The sample we used is `Tests\Samples\Cpp.GTestSmoke`.

## What this guide does not promise

The C++ expert is not announced as finished support, and it is not an Embarcadero feature. Win32, classic Win64, `bcc32c` and `bcc64` stay without line coverage. We are not embedding a profiler for those platforms. An integrated profiler is an idea for later.

---

[← Testing](README.md)
