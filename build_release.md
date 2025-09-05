# Build Commands for v1.0.1 Release

## Prerequisites
```bash
# Clean any previous builds
flutter clean
flutter pub get
```

## Android APK
```bash
# Build release APK (splits by ABI for smaller size)
flutter build apk --release --split-per-abi

# Build universal APK (larger but works on all devices)
flutter build apk --release

# Output location:
# build/app/outputs/flutter-apk/app-release.apk
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
# build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# build/app/outputs/flutter-apk/app-x86_64-release.apk
```

## macOS Bundle
```bash
# Build macOS app
flutter build macos --release

# Create DMG (optional, for easier distribution)
# You'll need to install create-dmg: brew install create-dmg
create-dmg \
  --volname "Nhac" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "nhac.app" 175 120 \
  --hide-extension "nhac.app" \
  --app-drop-link 425 120 \
  build/macos/Build/Products/Release/nhac-1.0.1.dmg \
  build/macos/Build/Products/Release/nhac.app

# Output location:
# build/macos/Build/Products/Release/nhac.app
```

## Flatpak
```bash
# Make sure you're in the project root
cd /var/home/o/Projects/nhac

# Build Flatpak
./build-flatpak

# Output location:
# nhac-1.0.1.flatpak
```

## Files for GitHub Release
After building, these are the files to upload:
- `build/app/outputs/flutter-apk/app-release.apk` (universal APK)
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (ARM64)
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` (ARMv7)
- `build/app/outputs/flutter-apk/app-x86_64-release.apk` (x86_64)
- `build/macos/Build/Products/Release/nhac-1.0.1.dmg` (if created)
- `nhac-1.0.1.flatpak`

## Notes
- Do NOT commit any of these build artifacts to git
- All build outputs are already in .gitignore
- Upload artifacts directly to GitHub Release page