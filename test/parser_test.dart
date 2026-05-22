import 'package:flutter_test/flutter_test.dart';
import 'package:gtd/models/task.dart';
import 'package:gtd/parser/gtd_parser.dart';

Task? parse(String line) => GtdParser.parseLine(
      line: line,
      filePath: 'areas/admin.md',
      lineNumber: 0,
    );

void main() {
  test('parses a basic todo with due date and tag', () {
    final t = parse('- [ ] Reply to Alice 📅 2026-05-19 #admin')!;
    expect(t.status, TaskStatus.todo);
    expect(t.description, 'Reply to Alice');
    expect(t.dueDate, DateTime.parse('2026-05-19'));
    expect(t.tags, ['admin']);
    expect(t.priority, TaskPriority.none);
  });

  test('parses a done task with done date', () {
    final t = parse('- [x] Conference registration #admin ✅ 2026-05-21')!;
    expect(t.status, TaskStatus.done);
    expect(t.isDone, true);
    expect(t.doneDate, DateTime.parse('2026-05-21'));
    expect(t.tags, ['admin']);
    expect(t.description, 'Conference registration');
  });

  test('strips wiki link aliases', () {
    final t = parse(
      '- [ ] Email [[bob-smith|Bob]] + [[carol-jones|Carol]] re: conference satellite 📅 2026-05-20 #admin',
    )!;
    expect(t.description, 'Email Bob + Carol re: conference satellite');
  });

  test('parses scheduled date', () {
    final t = parse('- [ ] Dave — redirect ⏳ 2026-06-01 #admin')!;
    expect(t.dueDate, isNull);
    expect(t.scheduledDate, DateTime.parse('2026-06-01'));
  });

  test('parses priority', () {
    final t = parse('- [ ] Urgent thing ⏫ 📅 2026-05-19')!;
    expect(t.priority, TaskPriority.high);
  });

  test('returns null for non-task lines', () {
    expect(parse('## Quick wins'), isNull);
    expect(parse(''), isNull);
    expect(parse('- regular bullet'), isNull);
  });

  test('preserves the raw line for write-back', () {
    const line = '- [ ] Reply to Alice 📅 2026-05-19 #admin';
    final t = parse(line)!;
    expect(t.rawLine, line);
  });
}
