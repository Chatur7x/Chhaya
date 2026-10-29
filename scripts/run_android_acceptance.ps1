param(
    [Parameter(Mandatory = $true)][string]$Device,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z][a-z0-9]{0,15}$')][string]$Instance,
    [Parameter(Mandatory = $true)][ValidatePattern('^integration_test/[a-zA-Z0-9_]+\.dart$')][string]$Test
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$adb = Join-Path $repo '.android-sdk/platform-tools/adb.exe'
$flutter = 'D:/flutter/bin/flutter.bat'
$expected = "com.chaaya.app.chaaya.acceptance_$Instance"
$buildTools = Join-Path $repo '.android-sdk/build-tools'
$previousInstance = $env:CHHAYA_ACCEPTANCE_INSTANCE
$aapt = Get-ChildItem -LiteralPath $buildTools -Directory | Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $aapt) { throw 'Android aapt was not found.' }
if (-not (Test-Path -LiteralPath (Join-Path $repo $Test))) { throw 'Integration test does not exist.' }

Push-Location $repo
try {
    $present = & $adb -s $Device shell pm list packages -u $expected
    if ($LASTEXITCODE -ne 0) { throw 'Could not check installed packages.' }
    if ($present -contains "package:$expected") { throw "Refusing to use existing package $expected; select a fresh instance." }
    $env:CHHAYA_ACCEPTANCE_INSTANCE = $Instance
    & $flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { throw 'Acceptance APK build failed.' }
    $apk = Join-Path $repo 'build/app/outputs/flutter-apk/app-debug.apk'
    $badging = & $aapt dump badging $apk
    $expectedPattern = "^package: name='$([regex]::Escape($expected))' "
    if ($LASTEXITCODE -ne 0 -or -not ($badging | Select-String -Pattern $expectedPattern)) {
        throw 'Cached APK package ID did not match the isolated acceptance instance.'
    }
    & $flutter test --no-uninstall -d $Device $Test
    if ($LASTEXITCODE -ne 0) { throw 'Acceptance test failed.' }
} finally {
    if ($null -eq $previousInstance) { Remove-Item Env:CHHAYA_ACCEPTANCE_INSTANCE -ErrorAction SilentlyContinue }
    else { $env:CHHAYA_ACCEPTANCE_INSTANCE = $previousInstance }
    Pop-Location
}
