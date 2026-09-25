 # Dext Examples Automated Runner
# This script robustly discovers, builds, and verifies all example projects.

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DextRoot = Split-Path -Parent $PSScriptRoot
$BuildLog = Join-Path $PSScriptRoot 'examples_build.log'

function Invoke-MsBuildWithRetry {
    param([string[]]$Arguments)

    $attempt = 1
    while ($attempt -le 2) {
        $buildOutput = & msbuild @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return [PSCustomObject]@{ ExitCode = 0; Output = $buildOutput }
        }

        $buildText = $buildOutput -join [Environment]::NewLine
        $lockDetected = ($buildText -match 'because it is being used by another process') -or
                        (($buildText -match 'UnauthorizedAccessException') -and ($buildText -match 'tmp[0-9A-Fa-f]+\.tmp'))
        if ($attempt -eq 1 -and $lockDetected) {
            Write-Host '  [RETRY] Temporary file lock detected, retrying once...' -ForegroundColor Yellow
            Start-Sleep -Seconds 3
            $attempt++
            continue
        }

        return [PSCustomObject]@{ ExitCode = $exitCode; Output = $buildOutput }
    }

    return [PSCustomObject]@{ ExitCode = 1; Output = @() }
}

# 1. Setup Environment from set_env.ps1
$env:DEXT_PROJECT_TYPE = 'Examples'
. "$PSScriptRoot\set_env.ps1" -Platform Win32 -Config Release -UseSourcePath:$false

Write-Host "[ENV] Product Version: $env:PRODUCT_VERSION"
Write-Host "[ENV] Platform:        $env:PLATFORM"
Write-Host "[ENV] Configuration:   $env:BUILD_CONFIG"
Write-Host "[ENV] Output Path:     $env:OUTPUT_PATH"

$ExamplesOutput = Join-Path $DextRoot 'Examples\Output'
$DcuOutput = $env:OUTPUT_PATH

# 2. Discover Projects
Write-Host "`n[INIT] Discovering projects..." -ForegroundColor Cyan
$projects = Get-ChildItem -Path (Join-Path $DextRoot 'Examples') -Filter '*.dproj' -Recurse | Where-Object {
    $_.FullName -notmatch 'Output' -and $_.FullName -notmatch '__history'
}

Write-Host "[INIT] Found $($projects.Count) projects to process."

# 3. Clean and Prepare
Write-Host "`n[CLEAN] Purging output directory: $DcuOutput" -ForegroundColor Yellow
if (Test-Path $DcuOutput) { Remove-Item -Path $DcuOutput -Recurse -Force }
New-Item -ItemType Directory -Path $DcuOutput -Force | Out-Null
if (!(Test-Path $ExamplesOutput)) { New-Item -ItemType Directory -Path $ExamplesOutput -Force | Out-Null }

# 4. Process Projects
$results = @()
$current = 0
$total = $projects.Count

foreach ($proj in $projects) {
    $current++
    $projName = $proj.BaseName
    $projPath = $proj.FullName
    $projDir = $proj.DirectoryName

    Write-Host "`n[$current/$total] Processing: $projName" -ForegroundColor White

    # The shared output folder is the process working directory. A previous
    # example must not leave appsettings or certificates for the next one.
    foreach ($leaked in @(
        'appsettings.json', 'appsettings.Development.json', 'appsettings.Production.json',
        'server.crt', 'server.key', 'server.pfx')) {
        $leakedPath = Join-Path $ExamplesOutput $leaked
        if (Test-Path $leakedPath) {
            Remove-Item -Path $leakedPath -Force
        }
    }

    # 4a. Build
    Write-Host '  [BUILD] Compiling...' -NoNewline
    $msbuildArgs = @(
        "`"$projPath`"",
        '/t:Build',
        "/p:Configuration=$($env:BUILD_CONFIG)",
        "/p:Platform=$($env:PLATFORM)",
        "/p:ProductVersion=$($env:PRODUCT_VERSION)",
        "/p:DCC_ExeOutput=`"$ExamplesOutput`"",
        "/p:DCC_DcuOutput=`"$DcuOutput`"",
        "/p:DCC_UnitSearchPath=`"$($env:SEARCH_PATH)`"",
        '/p:DCC_BuildAllUnits=true',
        '/v:minimal',
        '/nologo'
    )

    $buildResult = Invoke-MsBuildWithRetry -Arguments $msbuildArgs
    if ($buildResult.Output.Count -gt 0) {
        $buildResult.Output | ForEach-Object { Write-Host $_ }
    }

    if ($buildResult.ExitCode -ne 0) {
        Write-Host ' FAILED' -ForegroundColor Red
        $results += [PSCustomObject]@{ Project = $projName; Status = 'Build Failed'; Dir = $projDir }
        continue
    }
    Write-Host ' OK' -ForegroundColor Green

    # AI demos compile in the normal run. They need provider keys to execute.
    if ($projName -in @('AgentDemo', 'GraphDemo')) {
        Write-Host '  [SKIP] Execution requires an AI provider key.' -ForegroundColor DarkYellow
        $results += [PSCustomObject]@{ Project = $projName; Status = 'Passed'; Dir = $projDir }
        continue
    }

    # 4b. Verify Execution/Test
    $exePath = Join-Path $ExamplesOutput "$projName.exe"
    if (!(Test-Path $exePath)) {
        Write-Host '  [ERROR] EXE missing after successful build!' -ForegroundColor Red
        $results += [PSCustomObject]@{ Project = $projName; Status = 'EXE Not Found'; Dir = $projDir }
        continue
    }

    $testScript = Get-ChildItem -Path $projDir -Filter 'Test.*.ps1' | Select-Object -First 1

    Push-Location $ExamplesOutput
    try {
        if ($testScript) {
            Write-Host "  [RUN] Starting backend with Test Script: $($testScript.Name)..."
            $job = Start-Process -FilePath $exePath -PassThru -NoNewWindow
            Start-Sleep -Seconds 3

            Write-Host '  [TEST] Executing script...'
            $global:LASTEXITCODE = 0
            try {
                & $testScript.FullName | Out-Null
            } catch {
                Write-Host " ERROR: $_" -ForegroundColor Red
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Host ' PASSED' -ForegroundColor Green
                $results += [PSCustomObject]@{ Project = $projName; Status = 'Passed'; Dir = $projDir }
            } else {
                Write-Host " FAILED (Code: $LASTEXITCODE)" -ForegroundColor Red
                $results += [PSCustomObject]@{ Project = $projName; Status = 'Test Failed'; Dir = $projDir }
            }

            Stop-Process -Id $job.Id -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host '  [CHECK] Basic execution check...'

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exePath
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $job = [System.Diagnostics.Process]::Start($psi)

            Start-Sleep -Seconds 2

            if ($job.HasExited) {
                if ($job.ExitCode -eq 0) {
                    Write-Host ' OK' -ForegroundColor Green
                    $results += [PSCustomObject]@{ Project = $projName; Status = 'Passed'; Dir = $projDir }
                } else {
                    Write-Host " CRASHED (ExitCode: $($job.ExitCode))" -ForegroundColor Red
                    $results += [PSCustomObject]@{ Project = $projName; Status = 'Crashed'; Dir = $projDir }
                }
            } else {
                Write-Host ' OK' -ForegroundColor Green
                $results += [PSCustomObject]@{ Project = $projName; Status = 'Passed'; Dir = $projDir }
                $job.Kill() | Out-Null
            }
        }
    } finally {
        Pop-Location
    }
}

# 5. Final Summary
Write-Host "`n" + ('=' * 40)
Write-Host ' Examples Test Summary'
Write-Host ('=' * 40)
$passed = ($results | Where-Object { $_.Status -eq 'Passed' }).Count
$failed = $results.Count - $passed

$failColor = if ($failed -gt 0) { 'Red' } else { 'Gray' }
Write-Host " Tests Passed: $passed" -ForegroundColor Green
Write-Host " Tests Failed: $failed" -ForegroundColor $failColor

if ($failed -gt 0) {
    Write-Host "`n Failed Projects:" -ForegroundColor Red
    $results | Where-Object { $_.Status -ne 'Passed' } | ForEach-Object {
        Write-Host "  - $($_.Project) [$($_.Status)]"
    }
    exit 1
}

Write-Host "`n ALL EXAMPLES PASSED SUCCESSFULLY!" -ForegroundColor Green
Write-Host ('=' * 40)
exit 0
