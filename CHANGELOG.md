# Changelog

## [1.1.0] - 2025-11-26

### Added
- **Offline mode**: Download albums for offline playback
- Battery-optimized background operations
- Network state detection with automatic recovery
- Pull-to-search gesture on all content screens
- Settings screen with download management
- Popular offline albums section when offline

### Fixed
- FLAC support on macOS
- Flatpak icon-not-found error
- Home screen getting stuck on "loading" when switching network modes
- Menu positioning on desktop (now appears below button)
- RenderFlex overflow in now playing bar

### Improved
- New app icon design
- Album UI and player buffering feedback
- Login screen behavior and error handling
- Social share image colors with vibrant backgrounds
- Database resilience
- CI/CD with GitHub Actions

## [1.0.1] - 2025-09-05

### Added
- Background library scanning with automatic updates
- Periodic scanning that adjusts to network conditions
- Silent UI refresh when new content is detected

### Fixed
- macOS native window controls and traffic light buttons
- Dark mode forced instead of respecting system theme

### Improved
- Keyboard navigation
- Window frame handling for macOS/Linux

## [1.0.0] - 2025-09-03

Initial release - A simple cross-platform Navidrome client.

- Music streaming and playback
- Album/artist browsing and search
- Android: Share to social media
- Linux: MPRIS and Flatpak support
- Experimental offline caching
