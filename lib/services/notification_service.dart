import 'dart:io';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Service for showing native desktop notifications via D-Bus (Linux only)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  DBusClient? _client;
  DBusRemoteObject? _notifications;
  bool _initialized = false;
  int _lastNotificationId = 0;
  String _appIconPath = 'audio-x-generic';

  Future<void> initialize() async {
    if (_initialized || !Platform.isLinux) return;

    if (kDebugMode) print('[NotificationService] Initializing D-Bus...');

    try {
      _client = DBusClient.session();
      _notifications = DBusRemoteObject(
        _client!,
        name: 'org.freedesktop.Notifications',
        path: DBusObjectPath('/org/freedesktop/Notifications'),
      );

      // Check if running in Flatpak
      final isFlatpak = Platform.environment.containsKey('FLATPAK_ID');

      if (isFlatpak) {
        // Use symbolic icon name (following Telegram's pattern for separate notification icon)
        _appIconPath = 'dev.myyc.nhac-symbolic';
      } else {
        // Use bundled asset for local development
        final execDir = path.dirname(Platform.resolvedExecutable);
        final iconPath = path.join(execDir, 'data', 'flutter_assets', 'assets', 'icons', 'fgnhac.png');
        if (await File(iconPath).exists()) {
          _appIconPath = iconPath;
        }
      }
      if (kDebugMode) print('[NotificationService] Using icon: $_appIconPath');

      _initialized = true;
      if (kDebugMode) print('[NotificationService] D-Bus initialized');
    } catch (e) {
      if (kDebugMode) print('[NotificationService] D-Bus init failed: $e');
    }
  }

  Future<void> showTrackNotification({
    required String title,
    required String artist,
    required String album,
    String? albumArtPath,
  }) async {
    if (kDebugMode) print('[NotificationService] showTrackNotification: $title');
    if (!Platform.isLinux || !_initialized || _notifications == null) {
      if (kDebugMode) print('[NotificationService] Not ready, skipping');
      return;
    }

    try {
      // Build hints dict
      final hints = <DBusValue, DBusValue>{
        // Tell GNOME which app this is (uses icon from desktop entry)
        const DBusString('desktop-entry'): const DBusVariant(DBusString('dev.myyc.nhac')),
      };

      // Add album art as image-path hint (shown on left side)
      if (albumArtPath != null && await File(albumArtPath).exists()) {
        hints[const DBusString('image-path')] = DBusVariant(DBusString(albumArtPath));
      }

      // Call org.freedesktop.Notifications.Notify
      // See: https://specifications.freedesktop.org/notification-spec/latest/
      final result = await _notifications!.callMethod(
        'org.freedesktop.Notifications',
        'Notify',
        [
          const DBusString('Nhac'),                    // app_name
          DBusUint32(_lastNotificationId),             // replaces_id (0 = new)
          DBusString(_appIconPath ?? 'audio-x-generic'), // app_icon
          DBusString(title),                           // summary
          DBusString('$artist • $album'),              // body
          DBusArray.string([]),                        // actions
          DBusDict(DBusSignature('s'), DBusSignature('v'), hints), // hints
          const DBusInt32(3000),                       // expire_timeout (ms)
        ],
        replySignature: DBusSignature('u'),
      );

      _lastNotificationId = (result.values.first as DBusUint32).value;
      if (kDebugMode) print('[NotificationService] Notification shown, id: $_lastNotificationId');
    } catch (e) {
      if (kDebugMode) print('[NotificationService] D-Bus call failed: $e');
    }
  }

  Future<void> dispose() async {
    await _client?.close();
    _client = null;
    _notifications = null;
    _initialized = false;
  }
}
