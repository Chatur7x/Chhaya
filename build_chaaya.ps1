<#
.SYNOPSIS
Installs and compiles Catus Chat by generating Flutter Native modules and injecting security permissions.

.DESCRIPTION
This script automatically runs `flutter create .`, safely modifies the AndroidManifest.xml and Info.plist with required hardware permissions, and forces a pub get.
#>

$ErrorActionPreference = "Stop"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "🚀 Catus Chat — Automated Native Build Script" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# 1. Check if Flutter exists
Write-Host "[1/4] Checking for Flutter SDK..." -ForegroundColor Yellow
$flutterExists = Get-Command "flutter" -ErrorAction SilentlyContinue
if (-not $flutterExists) {
    Write-Host "`n[ERROR] Flutter SDK is not installed or not in your Windows PATH." -ForegroundColor Red
    Write-Host "Please download Flutter from https://docs.flutter.dev/get-started/install/windows/mobile" -ForegroundColor Yellow
    Write-Host "Extract it to C:\src\flutter and add C:\src\flutter\bin to your Environment Variables." -ForegroundColor Yellow
    Write-Host "Then reopen this terminal and run this script again.`n" -ForegroundColor White
    Pause
    exit
}

cd "$PSScriptRoot\frontend"

# 2. Generate native folders
Write-Host "`n[2/4] Generating Android and iOS Native Scaffolding..." -ForegroundColor Yellow
flutter create . --platforms android,ios
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to run flutter create." -ForegroundColor Red
    Pause
    exit
}

# 3. Inject Android Permissions
Write-Host "`n[3/4] Injecting Hardware Permissions into AndroidManifest.xml..." -ForegroundColor Yellow
$manifestPath = "android\app\src\main\AndroidManifest.xml"
if (Test-Path $manifestPath) {
    $manifestContent = Get-Content $manifestPath -Raw
    
    $permissions = @"
    <uses-permission android:name="android.permission.BLUETOOTH" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
"@

    # Only inject if not already present
    if (-not $manifestContent.Contains("android.permission.BLUETOOTH_CONNECT")) {
        $updatedManifest = $manifestContent -replace "(<application)", "`n$permissions`n    `$1"
        Set-Content -Path $manifestPath -Value $updatedManifest
        Write-Host "  -> Android permissions safely injected!" -ForegroundColor Green
    } else {
        Write-Host "  -> Android permissions already exist. Skipping." -ForegroundColor DarkGray
    }
} else {
    Write-Host "[ERROR] AndroidManifest.xml not found!" -ForegroundColor Red
}

# 3.5 Inject iOS Permissions
Write-Host "`n[3.5/4] Injecting Hardware Permissions into Info.plist..." -ForegroundColor Yellow
$plistPath = "ios\Runner\Info.plist"
if (Test-Path $plistPath) {
    $plistContent = Get-Content $plistPath -Raw
    
    $iosPermissions = @"
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Catus Chat needs Bluetooth to route offline messages and discover peers.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Catus Chat needs location access for SOS and safety maps.</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Catus Chat needs local network access for high-speed WiFi Direct transfers.</string>
	<key>NSCameraUsageDescription</key>
	<string>Catus Chat needs camera access for QR pairing and field reports.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Catus Chat needs microphone access for Walkie-Talkie and voice calls.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Catus Chat needs photo access to save media to the encrypted vault.</string>
"@

    if (-not $plistContent.Contains("NSBluetoothAlwaysUsageDescription")) {
        $updatedPlist = $plistContent -replace "(<dict>)", "`$1`n$iosPermissions"
        Set-Content -Path $plistPath -Value $updatedPlist
        Write-Host "  -> iOS permissions safely injected!" -ForegroundColor Green
    } else {
        Write-Host "  -> iOS permissions already exist. Skipping." -ForegroundColor DarkGray
    }
} else {
    Write-Host "  -> Skipping iOS (Info.plist not found, maybe building on Windows only)." -ForegroundColor DarkGray
}

# 4. Fetch dependencies
Write-Host "`n[4/4] Fetching Dart packages..." -ForegroundColor Yellow
flutter pub get

Write-Host "`n=============================================" -ForegroundColor Green
Write-Host "✅ Catus Chat BUILD COMPLETE" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host "If you have an Android device plugged in, you can now run:" -ForegroundColor White
Write-Host "  cd frontend ; flutter run --release" -ForegroundColor Cyan
Write-Host "`nPress any key to close..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
