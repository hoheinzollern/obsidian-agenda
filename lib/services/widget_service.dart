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

      // Build one combined list with header rows interleaved with task
      // rows. The widget renders the whole thing into a single ListView;
      // chips drive setScrollPosition by looking up the header's index.
      final combined = <Map<String, dynamic>>[];
      final headerIndices = <String, int>{};

      void addBucket(String id, String emoji, String label, List<Task> tasks) {
        headerIndices[id] = combined.length;
        combined.add({
          'type': 'header',
          'bucket': id,
          'emoji': emoji,
          'label': label,
          'count': tasks.length,
        });
        for (final t in tasks.take(_perBucketCap)) {
          final rel = p.relative(t.filePath, from: vaultPath);
          combined.add({
            'type': 'task',
            'description': t.description,
            'path': t.filePath,
            'rel_path': rel,
            'line': t.lineNumber,
            'status': t.status.marker,
            'raw_line': t.rawLine,
            'tags': t.tags,
            'source': t.sourceLabel,
          });
        }
      }

      addBucket('overdue', '⚠️', 'Overdue', overdue);
      addBucket('today', '📅', 'Today', today);
      addBucket('week', '📆', 'This week', week);
      addBucket('next30', '🔜', 'Next 30 days', next30);
      addBucket('floating', '📂', 'Floating', floating);
      // Tall blank tail so ListView.setSelection on the last bucket's
      // header still lands the header at the top of the viewport.
      combined.add({'type': 'filler'});

      await HomeWidget.saveWidgetData<int>(
          'agenda_overdue_count', overdue.length);
      await HomeWidget.saveWidgetData<int>(
          'agenda_today_count', today.length);
      await HomeWidget.saveWidgetData<int>('agenda_week_count', week.length);
      await HomeWidget.saveWidgetData<int>('agenda_next30_count', next30.length);
      await HomeWidget.saveWidgetData<int>(
          'agenda_floating_count', floating.length);

      await HomeWidget.saveWidgetData<String>(
          'agenda_combined_json', jsonEncode(combined));
      await HomeWidget.saveWidgetData<String>(
          'agenda_header_indices', jsonEncode(headerIndices));

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
