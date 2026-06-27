# Catus Chat Setup Guide

Since this is a deeply integrated offline hardware project, you must set up your local environment and native permissions before compiling the project.

## 1. Prerequisites
- **Flutter SDK**: Ensure Flutter is installed and added to your system `PATH`.
- **Java 17+**: Required for the Spring Boot backend.
- **Android Studio / Xcode**: Required for building to physical devices.

## 2. Generate the Flutter Project
Open a terminal in the `frontend` folder and run:
```bash
cd frontend
flutter create .
```
*(This will generate the missing `android/` and `ios/` folders without overwriting our custom `lib/main.dart` code).*

## 3. Add Native Permissions (CRITICAL)

### Android 
Open `frontend/android/app/src/main/AndroidManifest.xml` and add these inside the `<manifest>` tag, above `<application>`:

```xml
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
```

### iOS
Open `frontend/ios/Runner/Info.plist` and add inside the `<dict>` tag:

```xml
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
```

## 4. Run the Project
Once permissions are set, you can run the app on a physical device (Emulators do not support BLE/WiFi Direct well):

```bash
cd frontend
flutter pub get
flutter run --release
```

To start the backend (for store-and-forward backup when devices reconnect to a mutual WiFi):
```bash
cd backend
mvn spring-boot:run
```

