# Install Dext Test Explorer (Expert DLL)

Copies the build DLL from `Output\…` into `Apps\TestExplorerExpert\bin\<Win32|Win64>\` and registers **that** path. The IDE locks the registered file; keeping Output free lets you rebuild without "DLL in use".

```powershell
cd Installers\DextTestExplorer

# 32-bit IDE (finds newest Output\*\Win32\Release\…dll)
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0

# 64-bit IDE
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Ide64

# Or explicit source
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -DllPath '..\..\Output\37.0\Win32\Release\Dext.Testing.Design.ExpertLib.dll'
```

Workflow: build ExpertLib → close IDE → run install → open IDE. After code changes: rebuild (Output ok while IDE runs) → close IDE → install again → reopen.

Uninstall (registry only):

```powershell
.\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -Uninstall
```

`StudioVersion` must match `HKCU\Software\Embarcadero\BDS\<ver>`.
