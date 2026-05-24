import '../models/task.dart';

/// Pure bucketing of open tasks into the five agenda buckets the
/// dashboard / widget / CLI all share. Sorting honours [sortByFile] —
/// when true, tasks within each bucket are ordered by source filename
/// then by line number; otherwise by due date then priority.
class Buckets {
  final List<Task> overdue;
  final List<Task> today;
  final List<Task> week;
  final List<Task> next30;
  final List<Task> floating;

  const Buckets({
    required this.overdue,
    required this.today,
    required this.week,
    required this.next30,
    required this.floating,
  });

  static Buckets compute(List<Task> tasks, {bool sortByFile = false}) {
    final today0 = _today();
    final weekEnd = today0.add(const Duration(days: 7));
    final monthEnd = today0.add(const Duration(days: 30));

    final overdue = <Task>[];
    final todayTasks = <Task>[];
    final week = <Task>[];
    final next30 = <Task>[];
    final floating = <Task>[];

    for (final t in tasks) {
      if (t.isDone) continue;
      final due = t.dueDate;
      final sched = t.scheduledDate;
      if (due != null && due.isBefore(today0)) {
        overdue.add(t);
      } else if ((due != null && _sameDay(due, today0)) ||
          (sched != null && _sameDay(sched, today0))) {
        todayTasks.add(t);
      } else if (due != null && due.isAfter(today0) && due.isBefore(weekEnd)) {
        week.add(t);
      } else if (due != null &&
          !due.isBefore(weekEnd) &&
          due.isBefore(monthEnd)) {
        next30.add(t);
      } else if (due == null && sched == null) {
        floating.add(t);
      }
    }

    final cmp = sortByFile ? _byFile : _byDue;
    for (final list in [overdue, todayTasks, week, next30, floating]) {
      list.sort(cmp);
    }

    return Buckets(
      overdue: overdue,
      today: todayTasks,
      week: week,
      next30: next30,
      floating: floating,
    );
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static int _byDue(Task a, Task b) {
    final ad = a.dueDate ?? a.scheduledDate;
    final bd = b.dueDate ?? b.scheduledDate;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    return a.priority.rank.compareTo(b.priority.rank);
  }

  static int _byFile(Task a, Task b) {
    final c = a.sourceLabel.toLowerCase().compareTo(b.sourceLabel.toLowerCase());
    if (c != 0) return c;
    final l = a.lineNumber.compareTo(b.lineNumber);
    if (l != 0) return l;
    return a.priority.rank.compareTo(b.priority.rank);
  }
}
