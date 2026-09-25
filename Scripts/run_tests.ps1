param(
    [string]$ProjectName = ''
)

# Dext Tests Automated Runner V2
# This script robustly discovers, builds, and executes unit tests individually.
# Based on the dynamic feedback pattern of run_examples.ps1

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$DextRoot = Split-Path -Parent $PSScriptRoot

# Force console to UTF-8 (Code Page 65001) for correct character and emoji display
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
if (Get-Command chcp.com -ErrorAction SilentlyContinue) { chcp.com 65001 | Out-Null }

function Resolve-MsBuildExe {
    $Candidates = @(
        'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe',
        'C:\Windows\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe'
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            return $Candidate
        }
    }

    $Command = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($Command -ne $null) {
        return $Command.Source
    }

    return $null
}

$MsBuildExe = Resolve-MsBuildExe
if ($MsBuildExe -eq $null) {
    Write-Host 'MSBuild.exe not found.' -ForegroundColor Red
    exit 1
}

function Invoke-MsBuildWithRetry {
    param([string[]]$Arguments)

    $attempt = 1
    while ($attempt -le 5) {
        $buildOutput = & $script:MsBuildExe @Arguments 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return [PSCustomObject]@{ ExitCode = 0; Output = $buildOutput }
        }

        $buildText = $buildOutput -join [Environment]::NewLine
        $lockDetected = ($buildText -match 'because it is being used by another process') -or
                        (($buildText -match 'UnauthorizedAccessException') -and ($buildText -match 'tmp[0-9A-Fa-f]+\.tmp'))
        if ($lockDetected -and ($attempt -lt 5)) {
            Write-Host '  [RETRY] Temporary file lock detected, retrying...' -ForegroundColor Yellow
            Start-Sleep -Seconds (2 * $attempt + 1)
            $attempt++
            continue
        }

        return [PSCustomObject]@{ ExitCode = $exitCode; Output = $buildOutput }
    }

    return [PSCustomObject]@{ ExitCode = 1; Output = @() }
}

# 1. Setup Environment from set_env.ps1
$env:DEXT_PROJECT_TYPE = 'Tests'
. "$PSScriptRoot\set_env.ps1" -Platform Win32 -Config Release -UseSourcePath:$false

$RunTempPath = Join-Path $DextRoot ("Temp\37.0\Win32\Release\run_tests_{0}" -f ([Guid]::NewGuid().ToString('N')))
if (-not (Test-Path $RunTempPath)) {
    New-Item -ItemType Directory -Path $RunTempPath -Force | Out-Null
}
$env:TEMP = $RunTempPath
$env:TMP = $RunTempPath

$TestsOutput = Join-Path $DextRoot 'Tests\Output'
if (-not (Test-Path $TestsOutput)) {
    New-Item -ItemType Directory -Path $TestsOutput -Force | Out-Null
}

$SuccessCount = 0
$FailCount = 0
$FailedTests = @()
$SingleProjectMode = $false

if ($ProjectName) {
    $SingleProjectMode = $true
}

# --- STEP 1: BUILD ---
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host 'Step 1: Building All Tests (Discovery)' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan

$TestProjects = Get-ChildItem -Path (Join-Path $DextRoot 'Tests') -Filter '*.dproj' -Recurse | Where-Object { $_.Name -like '*test*' }

if ($SingleProjectMode) {
    $TestProjects = $TestProjects | Where-Object {
        $_.BaseName -ieq $ProjectName -or $_.Name -ieq "$ProjectName.dproj"
    }
}

if (-not $TestProjects -or $TestProjects.Count -eq 0) {
    Write-Host "No test project found for '$ProjectName'." -ForegroundColor Red
    exit 1
}

foreach ($proj in $TestProjects) {
    $projName = $proj.BaseName
    if ($projName -eq 'VclOpenSslTest') {
        Write-Host "[SKIP] Project: $projName (form-based test)" -ForegroundColor DarkYellow
        continue
    }
    Write-Host "[BUILD] Project: $projName" -ForegroundColor Yellow

    $MSBuildArgs = @(
        $proj.FullName,
        '/t:Build',
        '/p:Config=Release',
        '/p:Platform=Win32',
        "/p:DCC_ExeOutput=`"$TestsOutput`"",
        "/p:DCC_DcuOutput=`"$env:OUTPUT_PATH`"",
        '/v:minimal',
        '/nologo'
    )

    $buildResult = Invoke-MsBuildWithRetry -Arguments $MSBuildArgs
    if ($buildResult.Output.Count -gt 0) {
        $buildResult.Output | ForEach-Object { Write-Host $_ }
    }

    if ($buildResult.ExitCode -ne 0) {
        Write-Host "  [ERROR] Build failed for $projName" -ForegroundColor Red
        if ($SingleProjectMode) {
            exit 1
        }
    }

    if ($SingleProjectMode) {
        break
    }
}

# --- STEP 2: RUN ---
$Tests = Get-ChildItem -Path $TestsOutput -Filter '*.exe'
if ($SingleProjectMode) {
    $Tests = $Tests | Where-Object { $_.BaseName -ieq $ProjectName }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "Step 2: Running $($Tests.Count) Tests" -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan

foreach ($test in $Tests) {
    $testName = $test.BaseName
    if ($testName -eq 'VclOpenSslTest') {
        Write-Host "`n[SKIP] Testing: $testName (form-based test)" -ForegroundColor DarkYellow
        continue
    }
    Write-Host "`n------------------------------------------"
    Write-Host "[RUN] Testing: $testName" -ForegroundColor Yellow
    Write-Host '------------------------------------------'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $test.FullName
    $psi.Arguments = '-no-wait'
    $psi.WorkingDirectory = $RunTempPath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false

    $job = [System.Diagnostics.Process]::Start($psi)
    $job.WaitForExit()

    if ($job.ExitCode -eq 0) {
        Write-Host "[PASSED] $testName" -ForegroundColor Green
        $SuccessCount++
    } else {
        Write-Host "[FAILED] $testName - Exit code: $($job.ExitCode)" -ForegroundColor Red
        $FailedTests += $testName
        $FailCount++
    }

    if ($SingleProjectMode) {
        break
    }
}

# --- SUMMARY ---
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host 'Test Summary' -ForegroundColor Cyan
Write-Host '==========================================' -ForegroundColor Cyan
Write-Host "  Tests Passed:   $SuccessCount" -ForegroundColor Green
Write-Host "  Tests Failed:   $FailCount" -ForegroundColor $(if ($FailCount -gt 0) { 'Red' } else { 'Green' })

if ($FailedTests.Count -gt 0) {
    Write-Host "`nFailed Tests:" -ForegroundColor Red
    foreach ($p in $FailedTests) { Write-Host "  - $p" -ForegroundColor Red }
    Write-Host "`nTESTS COMPLETED WITH FAILURES" -ForegroundColor Red
    exit 1
}

Write-Host "`nALL TESTS PASSED!" -ForegroundColor Green
exit 0
