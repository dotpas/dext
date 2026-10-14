<#
.SYNOPSIS
  Dedicated installer scaffold for Dext Test Explorer (C++Builder personality).

.DESCRIPTION
  Registers the C++ design package with RAD Studio without installing the full
  Delphi Dext Testing framework BPLs into the user's C++ projects.

  THIS IS A SCAFFOLD. Fill package paths after S75 build artifacts exist.
  Do not distribute to beta testers until discovery notes are complete.

.PARAMETER StudioVersion
  e.g. 23.0 (RAD Studio 12), 37.0 (RAD Studio 13) — confirm against target BDS.

.PARAMETER PackagePath
  Full path to Dext.Testing.Design.Cpp.bpl once built.
#>
[CmdletBinding()]
param(
  [string]$StudioVersion = '23.0',
  [string]$PackagePath = ''
)

$ErrorActionPreference = 'Stop'

Write-Host 'Dext Test Explorer — C++Builder installer (scaffold)' -ForegroundColor Cyan
Write-Host "StudioVersion: $StudioVersion"

if (-not $PackagePath) {
  Write-Warning 'PackagePath not set. Build Design.Cpp package first, then re-run.'
  Write-Host 'Expected later: Packages\<ver>\Win32\Release\Dext.Testing.Design.Cpp.bpl'
  exit 1
}

if (-not (Test-Path $PackagePath)) {
  throw "Package not found: $PackagePath"
}

$regPath = "HKCU:\Software\Embarcadero\BDS\$StudioVersion\Known Packages"
if (-not (Test-Path $regPath)) {
  throw "RAD Studio registry key not found: $regPath — is this Studio installed?"
}

$description = 'Dext Test Explorer (C++Builder)'
New-ItemProperty -Path $regPath -Name $PackagePath -Value $description -PropertyType String -Force | Out-Null
Write-Host "Registered: $PackagePath" -ForegroundColor Green
Write-Host 'Restart RAD Studio (C++Builder personality) to load the Expert.'
Write-Host 'Beta checklist: Docs/Plans/Dext-Testing-Cpp-Discovery.md'
