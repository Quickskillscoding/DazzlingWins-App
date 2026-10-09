
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'api.dart';
import 'session.dart';

/// Promo-campaign notifications, no Firebase needed:
///  * Android WorkManager runs [checkCampaigns] about every 15 minutes in the background
///    (Android decides the exact moment to save battery), and
///  * the app checks right away every time it opens or comes back to the foreground.
/// The server (/api/app/notifications) returns only campaigns delivered to THIS player.
class AppNotifications {
  AppNotifications._();

  static const _task = 'dw-campaign-check';
  static const _cursorKey = 'dw_campaign_cursor';
  static const _channelId = 'promotions';
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> _initPlugin() async {
    if (_initialized) return;
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_dw'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    ));
    _initialized = true;
  }

  /// Call once at startup (main isolate).
  static Future<void> init() async {
    try {
      await _initPlugin();
      await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
      );
    } catch (_) {
      // Notifications are a bonus; never block the app.
    }
  }

  /// Android 13+: ask once, after sign-in (not on the splash).
  static Future<void> requestPermission() async {
    try {
      await _initPlugin();
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Fetch new campaigns for the signed-in player and show each as a system notification.
  static Future<int> checkCampaigns() async {
    await Session.instance.load();
    if (!Session.instance.isSignedIn) return 0;
    await _initPlugin();
    final prefs = await SharedPreferences.getInstance();
    final cursor = prefs.getString(_cursorKey);
    final data = await ApiClient.instance.get('/api/app/notifications', query: {if (cursor != null) 'since': cursor});
    final items = listOf(data['notifications']);
    var shown = 0;
    String? newest = cursor;
    for (final n in items) {
      final id = strOf(n['id']);
      await _plugin.show(
        id.hashCode & 0x7fffffff,
        strOf(n['title'], 'New offer for you'),
        strOf(n['body']),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Promotions & offers',
            channelDescription: 'Bonuses, free spins and offers from DazzlingWins',
            importance: Importance.high,
            priority: Priority.high,
            color: const Color(0xFFF5C451),
            styleInformation: BigTextStyleInformation(strOf(n['body'])),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
      shown++;
      final at = strOf(n['at']);
      if (at.isNotEmpty) newest = at;
    }
    // First run with nothing new: start from the server's clock so old campaigns never pop up.
    newest ??= strOf(data['serverTime']).isEmpty ? null : strOf(data['serverTime']);
    if (newest != null) await prefs.setString(_cursorKey, newest);
    return shown;
  }

  static Future<void> clearOnSignOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cursorKey);
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

/// Background entry point (separate isolate). Must be top-level and kept by the compiler.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await AppNotifications.checkCampaigns();
    } catch (_) {
      // Network down / signed out: try again next period.
    }
    return true;
  });
}
