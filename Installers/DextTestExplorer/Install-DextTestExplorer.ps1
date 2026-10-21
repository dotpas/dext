<#
.SYNOPSIS
  Copies ExpertLib.dll to Apps\TestExplorerExpert\bin and registers that path as a RAD Studio Expert.

  Why copy: the IDE locks the registered DLL. Build output stays under Output\…;
  install always registers the Apps copy so rebuilds do not hit "DLL in use".

.PARAMETER StudioVersion
  BDS version folder, e.g. 23.0 (RAD Studio 12), 22.0 (11), 37.0 (13).

.PARAMETER DllPath
  Source DLL (build output). Default: newest Output\*\Win32\Release\Dext.Testing.Design.ExpertLib.dll
  or, with -Ide64, Dext.Testing.Design.ExpertLib64.dll. {$LIBSUFFIX '64'} on Win64.
  relative to the repo, matching -Ide64.

.PARAMETER Ide64
  Register under "Experts X64" and prefer Win64 build output.

.PARAMETER Uninstall
  Remove the registry value (does not delete the Apps copy).

Example:
 powershell -ExecutionPolicy Bypass -File .\Install-DextTestExplorer.ps1 -StudioVersion 37.0 -DllPath '.\Output\37.0\Win32\Release\Dext.Testing.Design.ExpertLib.dll'  
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$StudioVersion,

  [Parameter(Mandatory = $false)]
  [string]$DllPath = '',

  [switch]$Ide64,

  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$Platform = if ($Ide64) { 'Win64' } else { 'Win32' }
$DllSuffix = if ($Ide64) { '64' } else { '' }
$DllName = "Dext.Testing.Design.ExpertLib$DllSuffix.dll"
$InstallDir = Join-Path $RepoRoot "Apps\TestExplorerExpert\bin\$Platform"
$InstallDll = Join-Path $InstallDir $DllName

$ExpertsKey = if ($Ide64) { 'Experts X64' } else { 'Experts' }
$RegPath = "HKCU:\Software\Embarcadero\BDS\$StudioVersion\$ExpertsKey"
$ValueName = 'DextTestExplorer'

if ($Uninstall) {
  if (Test-Path $RegPath) {
    Remove-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue
    Write-Host "Removed $RegPath\$ValueName"
  }
  else {
    Write-Host "Experts key not found: $RegPath"
  }
  exit 0
}

function Find-DefaultBuildDll {
  $OutputRoot = Join-Path $RepoRoot 'Output'
  if (-not (Test-Path $OutputRoot)) {
    return $null
  }
  $candidates = Get-ChildItem -Path $OutputRoot -Recurse -Filter $DllName -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match [regex]::Escape("\$Platform\") -and $_.FullName -match '\\Release\\' } |
    Sort-Object LastWriteTime -Descending
  if ($candidates) {
    return $candidates[0].FullName
  }
  return $null
}

if (-not $DllPath) {
  $DllPath = Find-DefaultBuildDll
  if (-not $DllPath) {
    Write-Error "No build DLL found under Output\…\$Platform\Release\. Build ExpertLib first, or pass -DllPath."
  }
  Write-Host "Using build output: $DllPath"
}

$Source = [System.IO.Path]::GetFullPath($DllPath)
if (-not (Test-Path $Source)) {
  Write-Error "DLL not found: $Source"
}

if (-not (Test-Path $InstallDir)) {
  New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}

try {
  Copy-Item -Path $Source -Destination $InstallDll -Force
  Write-Host "Copied to: $InstallDll"
}
catch {
  Write-Error @"
Could not copy to $InstallDll
The IDE likely has this file locked. Close RAD Studio and run this script again.
$($_.Exception.Message)
"@
}

if (-not (Test-Path $RegPath)) {
  New-Item -Path $RegPath -Force | Out-Null
}

New-ItemProperty -Path $RegPath -Name $ValueName -PropertyType String -Value $InstallDll -Force | Out-Null
Write-Host "Registered Expert ($ExpertsKey):"
Write-Host "  $RegPath\$ValueName = $InstallDll"
Write-Host "Restart RAD Studio. Rebuilds write to Output\; re-run this script (IDE closed) to refresh the Apps copy."
