param(
    [Parameter(Mandatory=$false)]
    [string]$Connection = (Join-Path $env:TEMP "dext-scaffolding\test_scaffolding.db"),
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = (Join-Path $env:TEMP "dext-scaffolding\sqlite_test"),
    
    [Parameter(Mandatory=$false)]
    [switch]$Smart,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoMetadata,
    
    [Parameter(Mandatory=$false)]
    [switch]$WithMetadata,
    
    [Parameter(Mandatory=$false)]
    [switch]$Poco
)

$ErrorActionPreference = "Stop"

# Localizar dext.exe
$DextExe = Join-Path $PSScriptRoot "..\..\Apps\dext.exe"
if (-not (Test-Path $DextExe)) {
    $DextExe = "dext.exe" 
}

Write-Host "--- Dext Scaffolding Test (SQLite) ---" -ForegroundColor Cyan
Write-Host "Connection: $Connection"
Write-Host "Output Dir: $OutputDir"
Write-Host ""

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

function Run-Scaffold {
    param($Name, [string[]]$ExtraArgs)
    
    Write-Host "Testing Option: $Name" -ForegroundColor Yellow
    $OutputFile = Join-Path $OutputDir "$Name.pas"
    
    # Montar array de argumentos
    $AllArgs = @("scaffold", "-c", $Connection, "-d", "sqlite", "-o", $OutputFile)
    if ($Smart) { $AllArgs += @("--smart") }
    if ($Poco) { $AllArgs += @("--poco") }
    if ($NoMetadata) { $AllArgs += @("--no-metadata") }
    if ($WithMetadata) { $AllArgs += @("--with-metadata") }
    if ($ExtraArgs) { $AllArgs += $ExtraArgs }
    
    Write-Host "Running: $DextExe $($AllArgs -join ' ')" -ForegroundColor Gray
    
    try {
        & $DextExe $AllArgs
        
        if (Test-Path $OutputFile) {
            Write-Host "PASS: File generated at $OutputFile" -ForegroundColor Green
        } else {
            Write-Host "FAIL: Command finished but file was not created." -ForegroundColor Red
        }
    } catch {
        Write-Host "FAIL: Error during execution." -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
    Write-Host ""
}

# 1. Default (Smart Types)
Run-Scaffold "Entities_SQLite_Smart"

# 2. POCO + Metadata
Run-Scaffold "Entities_SQLite_POCO" -ExtraArgs "--poco"

Write-Host "SQLite Scaffold Tests Completed." -ForegroundColor Cyan
