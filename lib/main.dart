import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import 'screens/dashboard_screen.dart';
import 'services/bucket_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';
import 'services/vault_service.dart';
import 'services/widget_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    HomeWidget.registerInteractivityCallback(agendaBackgroundCallback);
  }
  if (NotificationService.supported) {
    try {
      await NotificationService.init();
    } catch (e, st) {
      // Notification plugin failure must not block the rest of the app.
      // ignore: avoid_print
      print('[NotificationService.init] failed: $e\n$st');
    }
  }
  runApp(const GtdApp());
}

/// Top-level Dart callback invoked by home_widget when the user taps the
/// refresh FAB on the Android home-screen widget. Runs in a background
/// isolate; re-scans the vault and pushes fresh data, without surfacing
/// any UI.
@pragma('vm:entry-point')
Future<void> agendaBackgroundCallback(Uri? uri) async {
  if (uri == null) return;
  final action = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
  if (action != 'refresh') return;

  final settings = SettingsService();
  final path = await settings.getVaultPath();
  if (path == null) return;

  final adv = await settings.getUseAdvancedUri();
  final opacity = await settings.getWidgetOpacity();
  final sortByFile = await settings.getSortByFile();

  try {
    final res = await VaultService().loadVault(path);
    final buckets = Buckets.compute(res.tasks, sortByFile: sortByFile);
    await WidgetService().push(
      overdue: buckets.overdue,
      today: buckets.today,
      week: buckets.week,
      next30: buckets.next30,
      floating: buckets.floating,
      vaultPath: path,
      useAdvancedUri: adv,
      opacity: opacity,
    );
  } catch (e, st) {
    // Background isolate has no UI to surface errors; log and bail.
    // ignore: avoid_print
    print('[agendaBackgroundCallback] $e\n$st');
  }
}

class GtdApp extends StatelessWidget {
  const GtdApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF455A64),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'GTD',
      theme: base,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF455A64),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}
