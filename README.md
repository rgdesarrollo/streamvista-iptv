<p align="center">
  <img src="icon.png" width="144" alt="StreamVista logo">
</p>

<h1 align="center">StreamVista IPTV</h1>

<p align="center">
  A polished, TV-first IPTV client for authorised Xtream Codes and M3U playlists.
</p>

<p align="center">
  <a href="SECURITY.md">Security policy</a>
</p>

> StreamVista does not include, promote, or distribute playlists, channels, or copyrighted content. Use it only with services you are authorised to access.

## Highlights

- TV-first home screen for Live TV, Movies, and Series
- Three-pane Live TV browser with groups, channels, preview, and programme details
- Single-click preview and double-click fullscreen playback
- Fullscreen channel overlay with live status, transport controls, audio, subtitles, and favourites
- Xtream Codes and HTTPS M3U/M3U8 playlist support
- Hardware-accelerated playback through `media_kit`
- Windows, Android phone/tablet, and Android TV support
- Encrypted local credential storage and HTTPS-only portal/stream endpoints

## Platform support

| Platform | Status | Distribution |
| --- | --- | --- |
| Windows 10/11 | Supported | Installer or unpacked release folder |
| Android phone/tablet | Supported | Signed APK or Play Store App Bundle |
| Android TV | Supported | Signed ARM64 APK or Play Store App Bundle |
| macOS | Project scaffold present | Build on a Mac with Xcode |
| Apple TV (tvOS) | Not supported | Requires a separate tvOS application |

## Install a release

Windows users should run the latest `StreamVista-IPTV-Setup-*.exe` installer from the project release. Android TV and modern Android devices should use the `arm64-v8a` APK; for Google Play, upload the `.aab` bundle.

Windows installers are not code-signed in this repository, so SmartScreen may request confirmation. A production public release should use an Authenticode certificate.

### Current release artifacts

| Artifact | Use |
| --- | --- |
| `StreamVista-IPTV-Setup-v8.exe` | Windows installer |
| `app-release.aab` | Google Play and Android TV publishing |
| `app-arm64-v8a-release.apk` | Modern Android and Android TV sideloading |
| `app-armeabi-v7a-release.apk` | 32-bit Android devices |
| `app-x86_64-release.apk` | x64 Android emulators |

## Run locally

### Prerequisites

- Flutter stable SDK
- Windows: Visual Studio with **Desktop development with C++**
- Android: Android Studio, Android SDK, and a device or emulator

```bash
flutter pub get
flutter run -d windows
```

To run on Android, connect a device with USB debugging enabled and run:

```bash
flutter run
```

## Build release artifacts

```bash
# Windows
flutter build windows --release --obfuscate --split-debug-info=build/symbols/windows

# Google Play / Android TV bundle
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android

# Direct-install Android APKs
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/android
```

Before Android release builds, configure your own signing key in `android/key.properties`. The template is intentionally excluded from version control; never commit a keystore or its passwords.

## Security and privacy

- Portal credentials are stored with platform-backed encrypted storage, not plain preferences.
- The app accepts HTTPS portal and stream URLs only.
- No credentials, playlists, API keys, signing keys, or build logs are tracked in Git.
- Use a provider you trust. StreamVista sends the configured credentials only to the portal address you enter.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and release guidance.

## Pairing portal

The optional `pairing_portal/` directory contains a Firebase-based administrator portal for securely provisioning a device. Follow its [setup guide](pairing_portal/README.md) before deployment and keep Firebase configuration under your control.

## Project layout

```text
lib/              Flutter application source
android/          Android and Android TV runner
windows/          Windows runner
macos/            macOS runner scaffold
pairing_portal/   Optional Firebase pairing portal
installer/        Windows installer recipe
```

## Contributing

Keep pull requests focused, run `flutter analyze` and `flutter test`, and never include provider credentials, private playlists, keystores, or release binaries in a commit.

The GitHub Actions workflow runs formatting, analysis, and tests for every pull request targeting `main`.

## License

No licence has been selected for this repository yet. Add one before accepting external contributions or publishing a public release.
