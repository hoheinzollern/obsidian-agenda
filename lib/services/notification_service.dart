import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily agenda notification. Body is computed by the caller (usually the
/// dashboard after a reload) and we schedule a single fire at the next
/// configured wall-clock time. Each dashboard reload re-arms the
/// notification with fresh content; this means the user must open the
/// app at least once a day for accurate counts, but it avoids needing a
/// long-running background isolate.
///
/// We sidestep `flutter_timezone` (currently has a JVM-target mismatch
/// with our AGP 9 / Java 11 setup) by computing the desired moment as a
/// local `DateTime`, converting it to UTC, and handing the UTC moment to
/// `tz.TZDateTime` with the UTC zone. The OS still fires the alarm at
/// the right wall-clock time because it ultimately uses the absolute
/// epoch we pass in.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'agenda_daily';
  static const _notifId = 1001;
  static bool _initialised = false;

  static bool get supported => Platform.isAndroid || Platform.isMacOS;

  /// Must be called from `main()` before `runApp`.
  static Future<void> init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      // Don't ask at init — only when the user toggles the setting on.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const init = InitializationSettings(
      android: androidInit,
      macOS: darwinInit,
    );
    await _plugin.initialize(init);
    _initialised = true;
  }

  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final notif = await android?.requestNotificationsPermission() ?? false;
      await android?.requestExactAlarmsPermission();
      return notif;
    }
    if (Platform.isMacOS) {
      final mac = _plugin.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      return await mac?.requestPermissions(alert: true, sound: true) ?? true;
    }
    return true;
  }

  /// Fire an immediate notification — useful for testing the pipeline
  /// without waiting until the scheduled hour.
  Future<void> showNow({required String title, required String body}) async {
    if (!supported) return;
    await init();
    const android = AndroidNotificationDetails(
      _channelId,
      'Daily agenda',
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwin = DarwinNotificationDetails();
    const details = NotificationDetails(android: android, macOS: darwin);
    await _plugin.show(_notifId + 1, title, body, details);
  }

  /// Schedule the next notification at [hour]:[minute] local time with
  /// the given [body]. If that time has already passed today, the
  /// notification fires tomorrow. Idempotent — any previously-scheduled
  /// agenda notification is cancelled first.
  Future<void> schedule({
    required int hour,
    required int minute,
    required String body,
  }) async {
    if (!supported) return;
    await init();
    await _plugin.cancel(_notifId);

    final now = DateTime.now();
    var targetLocal = DateTime(now.year, now.month, now.day, hour, minute);
    if (!targetLocal.isAfter(now)) {
      targetLocal = targetLocal.add(const Duration(days: 1));
    }
    final tzTarget = tz.TZDateTime.fromMillisecondsSinceEpoch(
      tz.UTC,
      targetLocal.toUtc().millisecondsSinceEpoch,
    );

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Daily agenda',
      channelDescription: 'Morning summary of overdue and today\'s tasks',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    );
    const darwinDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, macOS: darwinDetails);

    await _plugin.zonedSchedule(
      _notifId,
      "Today's agenda",
      body,
      tzTarget,
      details,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> cancel() async {
    if (!supported) return;
    await _plugin.cancel(_notifId);
  }
}
