import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/task.dart';

/// Appends a new TODO line to `<vault>/inbox.md` (creates the file if
/// it doesn't exist yet). Returns the line that was written.
class InboxWriter {
  static Future<String?> append({
    required String vaultPath,
    required String description,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    List<String> tags = const [],
  }) async {
    final desc = description.trim();
    if (desc.isEmpty) return null;

    final buf = StringBuffer('- [ ] $desc');
    if (priority != TaskPriority.none) {
      buf.write(' ${priority.emoji}');
    }
    if (dueDate != null) {
      buf.write(' 📅 ${DateFormat('yyyy-MM-dd').format(dueDate)}');
    }
    for (final tag in tags) {
      final clean = tag.trim().replaceFirst(RegExp(r'^#'), '');
      if (clean.isEmpty) continue;
      buf.write(' #$clean');
    }
    final line = buf.toString();

    final file = File(p.join(vaultPath, 'inbox.md'));
    if (!await file.exists()) {
      await file.writeAsString('---\ntitle: Inbox\n---\n\n# Inbox\n\n$line\n');
      return line;
    }
    final existing = await file.readAsString();
    final sep = existing.endsWith('\n') ? '' : '\n';
    await file.writeAsString('$existing$sep$line\n');
    return line;
  }
}
