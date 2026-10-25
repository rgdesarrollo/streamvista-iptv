<p align="center">
  <img src="logo.png" width="144" alt="StreamVista IPTV logo">
</p>

<h1 align="center">StreamVista IPTV</h1>

<p align="center">
  A polished, TV-first IPTV player for authorised Xtream Codes and M3U playlists.
</p>

<p align="center">
  <a href="https://github.com/rgdesarrollo/streamvista-iptv/releases/latest/download/StreamVista-IPTV-Setup-v1.0.2.exe"><strong>Download for Windows</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/rgdesarrollo/streamvista-iptv/releases/latest/download/app-arm64-v8a-release.apk"><strong>Download for Android</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/rgdesarrollo/streamvista-iptv/releases">All releases</a>
  &nbsp;·&nbsp;
  <a href="SECURITY.md">Security policy</a>
</p>

> StreamVista does not include, promote, or distribute playlists, channels, or copyrighted content. Use it only with services you are authorised to access.

## Designed for the big screen

StreamVista puts live TV, movies, and series in a focused interface built for comfortable viewing. Add your authorised provider details, browse your content, and enjoy a responsive playback experience on Windows, Linux, and Android.

## Highlights

- TV-first home screen for Live TV, Movies, and Series
- Three-pane Live TV browser with groups, channels, preview, and programme details
- Single-click preview and double-click fullscreen playback
- Fullscreen channel overlay with live status, transport controls, audio, subtitles, and favourites
- Movies and series: time bar with seeking and 10-second skip back/forward
- M3U playlists are sorted automatically into Live TV, Movies, and Series
- Xtream Codes and HTTPS M3U/M3U8 playlist support
- Hardware-accelerated playback through `media_kit`
- Windows, Linux, Android phone/tablet, and Android TV support
- Encrypted local credential storage and HTTPS-only portal/stream endpoints

## Platform support

| Platform | Status | Distribution |
| --- | --- | --- |
| Windows 10/11 | Supported | Installer |
| Linux (Debian/Ubuntu) | Supported | `.deb` package (build from source, see below) |
| Android phone/tablet | Supported | APK |
| Android TV | Supported | ARM64 APK |
| macOS | Project scaffold present | Build on a Mac with Xcode |
| Apple TV (tvOS) | Not supported | Requires a separate tvOS application |

## Windows installation

1. Download **StreamVista-IPTV-Setup-v1.0.2.exe** from the latest release above.
2. Run the installer and follow the on-screen steps.
3. Open StreamVista and add the details from a provider you are authorised to use.

Windows 10 or 11 is required. The installer is currently not code-signed, so Windows SmartScreen may ask you to confirm before opening it.

## Android installation

1. Download **app-arm64-v8a-release.apk** from the latest release above. Use `app-armeabi-v7a-release.apk` for older 32-bit devices.
2. Open the downloaded file on your Android device.
3. Allow installation from your browser or file manager when Android asks, then follow the prompts.

The APK works on modern Android phones, tablets, and compatible Android TV devices. Android may display a confirmation because the app is installed outside Google Play.

## Linux installation

Build the `.deb` package from source (see [Build release artifacts](#build-release-artifacts)), then install it:

```bash
sudo apt install ./dist/streamvista-iptv_<version>_amd64.deb
```

## Run locally

### Prerequisites

- Flutter stable SDK
- Windows: Visual Studio with **Desktop development with C++**
- Android: Android Studio, Android SDK, and a device or emulator
- Linux: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev libsecret-1-dev liblzma-dev`

```bash
flutter pub get
flutter run -d windows   # or: -d linux
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

# Linux .deb package (output in dist/)
./packaging/linux/build_deb.sh
```

Before Android release builds, configure your own signing key in `android/key.properties`. The template is intentionally excluded from version control; never commit a keystore or its passwords.

## Privacy and security

- Portal credentials are stored with platform-backed encrypted storage, not plain preferences.
- The app accepts HTTPS portal and stream URLs only.
- No credentials, playlists, API keys, signing keys, or build logs are tracked in Git.
- StreamVista sends the configured credentials only to the portal address you enter. Never share your provider credentials or playlists publicly.

See [SECURITY.md](SECURITY.md) for vulnerability reporting and release guidance.

## Pairing portal

The optional `pairing_portal/` directory contains a Firebase-based administrator portal for securely provisioning a device. Follow its [setup guide](pairing_portal/README.md) before deployment and keep Firebase configuration under your control.

## Project layout

```text
lib/              Flutter application source
android/          Android and Android TV runner
windows/          Windows runner
linux/            Linux runner
macos/            macOS runner scaffold
packaging/linux/  Linux .deb packaging script
pairing_portal/   Optional Firebase pairing portal
installer/        Windows installer recipe
```

## Need help?

Open an issue in this repository with your operating system, StreamVista version, and a description of the problem. Please do not include provider credentials, private playlist URLs, or account information.

## Contributing

Keep pull requests focused, run `flutter analyze` and `flutter test`, and never include provider credentials, private playlists, keystores, or release binaries in a commit.

## License

All rights reserved. The source is published for reference; no open-source licence has been granted yet.
