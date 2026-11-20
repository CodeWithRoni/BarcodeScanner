Turn your phone into a wireless barcode & QR scanner for your computer. Scan with your phone, and the code is typed straight into whatever app is focused on your computer — or copied to the clipboard, or just logged. Both devices only need to be on the same Wi-Fi.

## ✨ Highlights

- **Zero-config pairing** — your computer and phone find each other automatically over mDNS with a UDP fallback. First-time phones need one click on **Allow**; after that they reconnect silently.
- **QR & manual fallback** — scan the pairing code on the dashboard, or type the address, when your router blocks discovery.
- **Three output modes** — *Type* into the focused app (with optional Auto-Enter), *Clipboard*, or *Log only*.
- **Rock-solid connection** — 5-second heartbeat, automatic reconnect with back-off, and an offline queue. Nothing is lost, and nothing is typed twice.
- **Instant feedback** — haptic + sound confirmation on the phone the moment the computer receives a scan.
- **Lives in your tray** — closing hides to the system tray; launch at login and start minimized are one toggle away.
- **Live scan history** — search, filter, copy, and export to CSV / JSON / TXT.
- **Light & dark mode** on both apps.

**Supported codes:** EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, ITF, Codabar, QR, DataMatrix, PDF417, Aztec.

## 📦 Downloads

| Platform | File |
| --- | --- |
| Windows | `BarcodeSync_{{VERSION}}_x64-setup.exe` (recommended) or `.msi` |
| macOS (Apple Silicon & Intel) | `BarcodeSync_{{VERSION}}_universal.dmg` |
| Linux | `BarcodeSync_{{VERSION}}_amd64.deb` or `.AppImage` |
| Android (almost every phone) | `BarcodeSync-{{VERSION}}-android-arm64.apk` |
| Android (older 32-bit phones) | `BarcodeSync-{{VERSION}}-android-armv7.apk` |
| Android (emulators / x86 devices) | `BarcodeSync-{{VERSION}}-android-x86_64.apk` |
| iOS | `BarcodeSync-{{VERSION}}-ios-unsigned.ipa` (needs re-signing, e.g. AltStore / Sideloadly) |

## 🚀 Getting started

1. Install and open **BarcodeSync** on your computer.
2. Install the app on your phone and open it on the same Wi-Fi.
3. Tap your computer on the phone, then click **Allow** on the computer.
4. Tap **Start scanning** — done.

## ⚠️ Good to know

- **macOS:** the first time, allow BarcodeSync under *System Settings → Privacy & Security → Accessibility* so it can type into other apps. The app isn't notarized yet, so right-click → **Open** on first launch.
- **Windows:** allow BarcodeSync on **private networks** when the firewall asks.
- **Linux:** typing works on X11 and XWayland apps; use **Clipboard** mode for native Wayland apps.
- **Android:** allow installing from unknown sources to install the APK. Not sure which file? Pick **arm64**. The scanner needs Google Play services (it downloads the barcode model on install).
