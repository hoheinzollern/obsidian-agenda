import 'dart:io';

import '../models/task.dart';

/// Parses Obsidian Tasks markdown lines into [Task] objects.
///
/// Recognised emoji metadata (from the Obsidian Tasks plugin):
///   📅 YYYY-MM-DD  — due (DEADLINE)
///   ⏳ YYYY-MM-DD  — scheduled
///   🛫 YYYY-MM-DD  — start
///   ✅ YYYY-MM-DD  — done date
///   ❌ YYYY-MM-DD  — cancelled date
///   🔺 ⏫ 🔼 🔽 🔻  — priority
class GtdParser {
  static final _taskLine =
      RegExp(r'^(\s*)- \[([ xX/\-])\]\s+(.*)$', multiLine: false);

  static final _dateRe =
      RegExp(r'(📅|⏳|🛫|✅|❌)\s*(\d{4}-\d{2}-\d{2})');

  static final _priorityRe = RegExp(r'(🔺|⏫|🔼|🔽|🔻)');

  static final _tagRe = RegExp(r'(?:^|\s)#([A-Za-z0-9_\-/]+)');

  // [[target|display]] or [[target]]
  static final _wikiLinkRe = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');

  /// Parse a single line. Returns null if the line is not a task.
  static Task? parseLine({
    required String line,
    required String filePath,
    required int lineNumber,
  }) {
    final m = _taskLine.firstMatch(line);
    if (m == null) return null;

    final marker = m.group(2)!;
    final rest = m.group(3)!;

    final status = TaskStatus.fromMarker(marker);

    DateTime? due;
    DateTime? scheduled;
    DateTime? start;
    DateTime? done;
    DateTime? cancelled;
    for (final dm in _dateRe.allMatches(rest)) {
      final date = DateTime.tryParse(dm.group(2)!);
      if (date == null) continue;
      switch (dm.group(1)) {
        case '📅':
          due = date;
          break;
        case '⏳':
          scheduled = date;
          break;
        case '🛫':
          start = date;
          break;
        case '✅':
          done = date;
          break;
        case '❌':
          cancelled = date;
          break;
      }
    }

    final priorityMatch = _priorityRe.firstMatch(rest);
    final priority = TaskPriority.fromEmoji(priorityMatch?.group(1));

    final tags = <String>[];
    for (final tm in _tagRe.allMatches(rest)) {
      tags.add(tm.group(1)!);
    }

    // Build the human-readable description by stripping all metadata.
    var desc = rest
        .replaceAll(_dateRe, '')
        .replaceAll(_priorityRe, '')
        .replaceAll(_tagRe, '');
    desc = desc.replaceAllMapped(_wikiLinkRe, (m) {
      return m.group(2) ?? m.group(1)!;
    });
    desc = desc.replaceAll(RegExp(r'\s+'), ' ').trim();

    return Task(
      description: desc,
      status: status,
      filePath: filePath,
      lineNumber: lineNumber,
      rawLine: line,
      dueDate: due,
      scheduledDate: scheduled,
      startDate: start,
      doneDate: done,
      cancelledDate: cancelled,
      priority: priority,
      tags: tags,
    );
  }

  /// Parse every task in the given file.
  static Future<List<Task>> parseFile(File file) async {
    final lines = await file.readAsLines();
    final tasks = <Task>[];
    for (var i = 0; i < lines.length; i++) {
      final t = parseLine(line: lines[i], filePath: file.path, lineNumber: i);
      if (t != null) tasks.add(t);
    }
    return tasks;
  }
}
