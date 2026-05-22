import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gtd/models/task.dart';
import 'package:gtd/parser/gtd_parser.dart';
import 'package:gtd/services/task_writer.dart';
import 'package:intl/intl.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gtd_writer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<File> writeMd(String body) async {
    final f = File('${tempDir.path}/notes.md');
    await f.writeAsString(body);
    return f;
  }

  test('toggling a TODO appends today\'s done stamp and flips checkbox',
      () async {
    final file = await writeMd(
      '# Notes\n'
      '- [ ] Reply to Alice 📅 2026-05-19 #admin\n'
      '- [ ] Second item\n',
    );
    final tasks = await GtdParser.parseFile(file);
    expect(tasks, hasLength(2));

    final updated = await TaskWriter().toggle(tasks.first);
    expect(updated, isNotNull);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final content = await file.readAsString();
    expect(
      content,
      '# Notes\n'
      '- [x] Reply to Alice 📅 2026-05-19 #admin ✅ $today\n'
      '- [ ] Second item\n',
    );
  });

  test('toggling a DONE task strips the done stamp and flips checkbox',
      () async {
    final file = await writeMd(
      '- [x] Conference registration #admin ✅ 2026-05-21\n',
    );
    final tasks = await GtdParser.parseFile(file);
    expect(tasks, hasLength(1));

    await TaskWriter().toggle(tasks.first);
    final content = await file.readAsString();
    expect(content, '- [ ] Conference registration #admin\n');
  });

  test('bails safely when the file has drifted since parsing', () async {
    final file = await writeMd('- [ ] Original line\n');
    final tasks = await GtdParser.parseFile(file);

    // Simulate someone editing the file outside the app.
    await file.writeAsString('- [ ] Different line entirely\n');

    final result = await TaskWriter().toggle(tasks.first);
    expect(result, isNull,
        reason: 'Should refuse to write when rawLine no longer matches');

    final content = await file.readAsString();
    expect(content, '- [ ] Different line entirely\n');
  });

  test('preserves the absence of a trailing newline', () async {
    final file = await writeMd('- [ ] No trailing newline');
    final tasks = await GtdParser.parseFile(file);
    await TaskWriter().toggle(tasks.first);

    final content = await file.readAsString();
    expect(content.endsWith('\n'), isFalse);
  });

  test('setting CANCELLED writes ❌ stamp and uses [-] marker', () async {
    final file = await writeMd('- [ ] Skip this 📅 2026-05-19 #admin\n');
    final tasks = await GtdParser.parseFile(file);

    await TaskWriter().setStatus(tasks.first, TaskStatus.cancelled);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final content = await file.readAsString();
    expect(content, '- [-] Skip this 📅 2026-05-19 #admin ❌ $today\n');
  });

  test('cancelled → done swaps ❌ for ✅', () async {
    final file = await writeMd('- [-] Was cancelled ❌ 2026-05-15\n');
    final tasks = await GtdParser.parseFile(file);

    await TaskWriter().setStatus(tasks.first, TaskStatus.done);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final content = await file.readAsString();
    expect(content, '- [x] Was cancelled ✅ $today\n');
  });

  test('reopening (TODO/WAIT) strips both ✅ and ❌', () async {
    final file = await writeMd('- [x] Was done ✅ 2026-05-21\n');
    final tasks = await GtdParser.parseFile(file);

    await TaskWriter().setStatus(tasks.first, TaskStatus.inProgress);

    final content = await file.readAsString();
    expect(content, '- [/] Was done\n');
  });
}
