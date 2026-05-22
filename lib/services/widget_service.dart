import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:path/path.dart' as p;

import '../models/task.dart';

/// Pushes the agenda summary out to the Android home-screen widget.
///
/// On non-Android platforms this is a no-op so the dashboard code can call
/// it unconditionally.
class WidgetService {
  /// Fully-qualified Android receiver class name. Must match the receiver
  /// declared in AndroidManifest.xml.
  static const _receiver = 'com.alessandrobruni.gtd.AgendaWidgetReceiver';

  /// Cap per bucket so massive lists don't blow up the IPC payload.
  static const _perBucketCap = 200;

  Future<void> push({
    required List<Task> overdue,
    required List<Task> today,
    required List<Task> week,
    required List<Task> next30,
    required List<Task> floating,
    required String vaultPath,
    required bool useAdvancedUri,
    required int opacity,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final vaultName = p.basename(vaultPath);
      String enc(List<Task> ts) => jsonEncode(
            ts.take(_perBucketCap).map((t) {
              final rel = p.relative(t.filePath, from: vaultPath);
              return {
                'description': t.description,
                'path': t.filePath,
                'rel_path': rel,
                'line': t.lineNumber,
                'status': t.status.marker,
                'raw_line': t.rawLine,
                'tags': t.tags,
                'source': t.sourceLabel,
              };
            }).toList(),
          );

      await HomeWidget.saveWidgetData<int>(
          'agenda_overdue_count', overdue.length);
      await HomeWidget.saveWidgetData<int>(
          'agenda_today_count', today.length);
      await HomeWidget.saveWidgetData<int>('agenda_week_count', week.length);
      await HomeWidget.saveWidgetData<int>('agenda_next30_count', next30.length);
      await HomeWidget.saveWidgetData<int>(
          'agenda_floating_count', floating.length);

      await HomeWidget.saveWidgetData<String>('agenda_overdue_json', enc(overdue));
      await HomeWidget.saveWidgetData<String>('agenda_today_json', enc(today));
      await HomeWidget.saveWidgetData<String>('agenda_week_json', enc(week));
      await HomeWidget.saveWidgetData<String>('agenda_next30_json', enc(next30));
      await HomeWidget.saveWidgetData<String>(
          'agenda_floating_json', enc(floating));

      await HomeWidget.saveWidgetData<String>('agenda_vault_name', vaultName);
      await HomeWidget.saveWidgetData<String>('agenda_vault_path', vaultPath);
      await HomeWidget.saveWidgetData<bool>(
          'agenda_use_advanced_uri', useAdvancedUri);
      await HomeWidget.saveWidgetData<int>('agenda_widget_opacity', opacity);
      await HomeWidget.saveWidgetData<String>(
        'agenda_last_updated',
        DateTime.now().toIso8601String(),
      );

      await HomeWidget.updateWidget(qualifiedAndroidName: _receiver);
    } catch (e, st) {
      // ignore: avoid_print
      print('[WidgetService] push failed: $e\n$st');
    }
  }

  /// Push only the Advanced-URI flag, e.g. when the user flips it in
  /// Settings without going back through the dashboard reload.
  Future<void> setUseAdvancedUri(bool value) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData<bool>('agenda_use_advanced_uri', value);
    } catch (_) {}
  }

  /// Update the widget opacity (0-100) and immediately re-render any
  /// installed widgets so the user sees the result of the slider.
  Future<void> setOpacity(int value) async {
    if (!Platform.isAndroid) return;
    try {
      await HomeWidget.saveWidgetData<int>('agenda_widget_opacity', value);
      await HomeWidget.updateWidget(qualifiedAndroidName: _receiver);
    } catch (_) {}
  }
}
