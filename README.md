<p align="center">
  <img src="logo.png" width="240" alt="StreamVista IPTV gold SV logo on charcoal">
</p>

<h1 align="center">StreamVista IPTV</h1>

<p align="center">
  A polished, TV-first IPTV player for authorised Xtream Codes and M3U playlists.
</p>

<p align="center">
  <a href="https://github.com/rgdesarrollo/streamvista-iptv/releases/download/v1.0.6/StreamVista-IPTV-Setup-v1.0.6.exe"><strong>Download for Windows (v1.0.6)</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/rgdesarrollo/streamvista-iptv/releases/latest/download/app-arm64-v8a-release.apk"><strong>Download for Android</strong></a>
  &nbsp;·&nbsp;
  <a href="#whats-new-in-v106"><strong>What’s new in v1.0.6</strong></a>
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
- Local provider settings and HTTPS portal/stream endpoints

## Platform support

| Platform | Status | Distribution |
| --- | --- | --- |
| Windows 10/11 | Supported | Installer |
| Linux (Debian/Ubuntu) | Supported | `.deb` package (build from source, see below) |
| Android phone/tablet | Supported | APK |
| Android TV | Supported | ARM64 APK |
| macOS | Project scaffold present | Build on a Mac with Xcode |
| Apple TV (tvOS) | Not supported | Requires a separate tvOS application |

## What's new in v1.0.6

The [v1.0.6 release](https://github.com/rgdesarrollo/streamvista-iptv/releases/tag/v1.0.6) provides updated Android APKs and a Windows installer from the same app source.

- New charcoal-and-gold logo in the launcher and app menus, plus the Windows executable and setup icon.
- Updated device-pairing screen with the website link, copy-link button, device ID and PIN, code regeneration, and expiry handling.
- Windows setup with shortcuts and an uninstaller; Android APKs signed with the same release key as v1.0.5 for updates.
- Includes Live TV preview/fullscreen playback, movies and series controls, and M3U content sorting.

Device pairing still depends on the pairing service allowing public access; the preview service returned HTTP 403. PayPal payments and license verification are not implemented. The Android release APK cannot update the earlier debug preview in place because the signing keys differ.

## Windows installation

1. Download **StreamVista-IPTV-Setup-v1.0.6.exe** using the Windows link above.
2. Run the installer and follow the on-screen steps.
3. Open StreamVista and add the details from a provider you are authorised to use.

Windows 10 or 11 is required. The installer is currently not code-signed, so Windows SmartScreen may ask you to confirm before opening it.

## Android installation

1. Download **app-arm64-v8a-release.apk** from the latest release above. Use `app-armeabi-v7a-release.apk` for older 32-bit devices.
2. Open the downloaded file on your Android device.
3. Allow installation from your browser or file manager when Android asks, then follow the prompts.

The APK works on modern Android phones, tablets, and compatible Android TV devices. Android may display a confirmation because the app is installed outside Google Play.

## Linux installation

Download the [stable Linux installer (v1.0.5)](https://github.com/rgdesarrollo/streamvista-iptv/releases/download/v1.0.5/streamvista-iptv_1.0.5-5_amd64.deb), then install it:

```bash
sudo apt install ./streamvista-iptv_1.0.5-5_amd64.deb
```

You can also build the `.deb` package from source (see [Build release artifacts](#build-release-artifacts)) and install it from `dist/`:

```bash
sudo apt install ./dist/streamvista-iptv_<version>_amd64.deb
```

## New-logo preview (Linux and Android)

The [v1.0.5-preview.7 release](https://github.com/rgdesarrollo/streamvista-iptv/releases/tag/v1.0.5-preview.7) includes the new charcoal-and-gold logo in the launcher, main menu, and catalogs.

- [Linux x64 installer (.deb)](https://github.com/rgdesarrollo/streamvista-iptv/releases/download/v1.0.5-preview.7/streamvista-iptv_1.0.5-7_amd64.deb)
- [Linux x64 archive (.tar.gz)](https://github.com/rgdesarrollo/streamvista-iptv/releases/download/v1.0.5-preview.7/Steamvista-linux-x64-interior-logo.tar.gz)
- [Android / Android TV test APK](https://github.com/rgdesarrollo/streamvista-iptv/releases/download/v1.0.5-preview.7/Steamvista-interior-logo-test.apk)
- [SHA-256 checksums](https://github.com/rgdesarrollo/streamvista-iptv/releases/download/v1.0.5-preview.7/SHA256SUMS-linux-android.txt)

To install the Linux preview:

```bash
sudo apt install ./streamvista-iptv_1.0.5-7_amd64.deb
```

This is a test release. The Linux build requires glibc 2.38 or newer, GLIBCXX_3.4.32, GTK 3, libmpv2, and libsecret. The Android APK is a debug build signed with a different key from the stable release, so it may not install as an update; save your playlists before changing installations. Device pairing currently returns HTTP 403, and PayPal payments and license verification are not enabled.

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

- Provider credentials are saved locally in app preferences. Protect access to your device and its app data.
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
