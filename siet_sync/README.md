# VisionGate (Faculty Sphere & Student Attendance)

Automated Face Attendance & Geofence Verification System built with Flutter, supporting **Windows**, **Linux**, **macOS**, **Web**, **Android**, and **iOS**.

---

## 🚀 Cross-Platform Support Matrix

| Feature | Windows Desktop | Linux Desktop | macOS Desktop | Web | Android / iOS |
|---|---|---|---|---|---|
| **Live Biometric Face Verification** | ✅ Native Camera (`camera_windows`) | ✅ Supported | ✅ AVFoundation Camera | ✅ Web Camera | ✅ Front/Back Camera |
| **Geofence Attendance Verification** | ✅ Windows Location | ✅ System Location / LAN | ✅ CoreLocation | ✅ Browser Geolocation | ✅ GPS High Accuracy |
| **Network & SSID Verification** | ✅ Wi-Fi & Ethernet LAN | ✅ Wi-Fi & Ethernet LAN | ✅ Wi-Fi & Ethernet LAN | ✅ College Domain / IP | ✅ Wi-Fi SSID Matching |
| **VPN & Proxy Detection** | ✅ Wintun / Tailscale / Win32 | ✅ tun / tap / wg / ppp | ✅ utun / ipsec / WireGuard | ✅ Server-side & Header check | ✅ VpnService / utun |
| **Excel & PDF Exporting** | ✅ Direct File System Write | ✅ Direct File System Write | ✅ Direct File System Write | ✅ Browser Blob Download | ✅ Native Share Sheet / Storage |
| **Theme & Responsive UI** | ✅ Dynamic Light / Dark | ✅ Dynamic Light / Dark | ✅ Dynamic Light / Dark | ✅ Full Responsive Grid | ✅ Native Mobile Layout |

---

## 🛠️ How to Build & Run on Each Platform

### 1. Windows Desktop
**Prerequisites:** Visual Studio 2022 with "Desktop development with C++".
```bash
# Debug Mode
flutter run -d windows

# Production Release Build
flutter build windows --release
# Executable output: build/windows/x64/runner/Release/VisionGate.exe
```

### 2. Linux Desktop
**Prerequisites:** Clang, CMake, GTK development headers, pkg-config.
```bash
# Install dependencies (Ubuntu/Debian)
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

# Debug Mode
flutter run -d linux

# Production Release Build
flutter build linux --release
# Executable output: build/linux/x64/release/bundle/
```

### 3. macOS Desktop
**Prerequisites:** macOS with Xcode installed.
```bash
# Debug Mode
flutter run -d macos

# Production Release Build
flutter build macos --release
# Application output: build/macos/Build/Products/Release/VisionGate.app
```

### 4. Web Application
```bash
# Debug Mode (Chrome)
flutter run -d chrome

# Production Web Release
flutter build web --release
```

### 5. Android & iOS
```bash
# Android APK
flutter build apk --release

# iOS Bundle
flutter build ipa --release
```

---

## ⚙️ Configuration
Backend API server URL is configured in `lib/config/college_ip_config.dart`.
Default URL is set to `http://127.0.0.1:8001` or your production server IP.

