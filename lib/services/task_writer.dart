import 'dart:io';

import 'package:intl/intl.dart';

import '../models/task.dart';

/// Modifies markdown files in place to toggle task completion.
///
/// Strategy: read the file, verify the target line still matches the task
/// we expect to modify (defends against the file having shifted out from
/// under us), rewrite that one line, write the file back.
class TaskWriter {
  static final _doneStamp = RegExp(r'\s*✅\s*\d{4}-\d{2}-\d{2}');
  static final _cancelledStamp = RegExp(r'\s*❌\s*\d{4}-\d{2}-\d{2}');
  static final _dueStamp = RegExp(r'\s*📅\s*\d{4}-\d{2}-\d{2}');
  static final _checkbox = RegExp(r'^(\s*- \[)([ xX/\-])(\])');

  /// Quick toggle: flip between todo and done (the most common case).
  /// Returns the updated `rawLine` so callers can refresh in-memory state,
  /// or null if the file drifted since parsing.
  Future<String?> toggle(Task task) {
    final next = task.isDone ? TaskStatus.todo : TaskStatus.done;
    return setStatus(task, next);
  }

  /// Replace (or remove) the task's due date `📅 YYYY-MM-DD`. Pass
  /// `null` to strip any existing due stamp.
  Future<String?> setDueDate(Task task, DateTime? newDate) async {
    final file = File(task.filePath);
    final lines = await file.readAsLines();

    if (task.lineNumber < 0 || task.lineNumber >= lines.length) return null;
    if (lines[task.lineNumber] != task.rawLine) return null;

    var newLine = lines[task.lineNumber].replaceAll(_dueStamp, '');
    if (newDate != null) {
      final stamp = DateFormat('yyyy-MM-dd').format(newDate);
      newLine = '${newLine.trimRight()} 📅 $stamp';
    }
    newLine = newLine.replaceAll(RegExp(r' {2,}'), ' ').trimRight();

    lines[task.lineNumber] = newLine;
    final originalContent = await file.readAsString();
    final endsWithNewline = originalContent.endsWith('\n');
    final out = lines.join('\n') + (endsWithNewline ? '\n' : '');
    await file.writeAsString(out, flush: true);
    return newLine;
  }

  /// Set the task to any of the four Obsidian Tasks states.
  ///
  /// Adds a `✅ <today>` stamp when transitioning into [TaskStatus.done] (if
  /// not already present), and strips the stamp when leaving the done state.
  Future<String?> setStatus(Task task, TaskStatus newStatus) async {
    final file = File(task.filePath);
    final lines = await file.readAsLines();

    if (task.lineNumber < 0 || task.lineNumber >= lines.length) {
      return null;
    }
    if (lines[task.lineNumber] != task.rawLine) {
      // File changed since we parsed; bail rather than corrupt it.
      return null;
    }

    final newLine = _writeStatus(lines[task.lineNumber], newStatus);
    if (newLine == null) return null;

    lines[task.lineNumber] = newLine;
    final originalContent = await file.readAsString();
    final endsWithNewline = originalContent.endsWith('\n');
    final out = lines.join('\n') + (endsWithNewline ? '\n' : '');
    await file.writeAsString(out, flush: true);
    return newLine;
  }

  static String? _writeStatus(String line, TaskStatus s) {
    final m = _checkbox.firstMatch(line);
    if (m == null) return null;

    var newLine =
        line.replaceFirst(_checkbox, '${m.group(1)}${s.marker}${m.group(3)}');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    switch (s) {
      case TaskStatus.done:
        // Add ✅ if not present, strip any ❌.
        newLine = newLine.replaceAll(_cancelledStamp, '');
        if (!_doneStamp.hasMatch(newLine)) {
          newLine = '${newLine.trimRight()} ✅ $today';
        }
        break;
      case TaskStatus.cancelled:
        // Add ❌ if not present, strip any ✅.
        newLine = newLine.replaceAll(_doneStamp, '');
        if (!_cancelledStamp.hasMatch(newLine)) {
          newLine = '${newLine.trimRight()} ❌ $today';
        }
        break;
      case TaskStatus.todo:
      case TaskStatus.inProgress:
        // Any "open" status: strip both stamps.
        newLine = newLine.replaceAll(_doneStamp, '');
        newLine = newLine.replaceAll(_cancelledStamp, '');
        break;
    }
    newLine = newLine.replaceAll(RegExp(r' {2,}'), ' ').trimRight();
    return newLine;
  }
}
