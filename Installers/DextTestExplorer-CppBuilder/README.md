# Installer — Dext Test Explorer for C++Builder

Separate from the Delphi Testing Design package on purpose:

- C++ users should not pull Delphi framework BPLs.
- Beta circle: Thiago (Embarcadero BR), David Millington, Leonardo (UFPR MVP) — **after** discovery and a real `.bpl`.

## Usage (when artifact exists)

```powershell
.\Install-DextTestExplorer-Cpp.ps1 -StudioVersion 23.0 -PackagePath 'C:\path\to\Dext.Testing.Design.Cpp.bpl'
```

## Uninstall

Remove the `Known Packages` value pointing at the BPL (or use RAD Studio Install Packages UI).
