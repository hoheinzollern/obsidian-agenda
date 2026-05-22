enum TaskStatus {
  todo,
  done,
  inProgress,
  cancelled;

  String get marker {
    switch (this) {
      case TaskStatus.todo:
        return ' ';
      case TaskStatus.done:
        return 'x';
      case TaskStatus.inProgress:
        return '/';
      case TaskStatus.cancelled:
        return '-';
    }
  }

  static TaskStatus fromMarker(String marker) {
    switch (marker) {
      case 'x':
      case 'X':
        return TaskStatus.done;
      case '/':
        return TaskStatus.inProgress;
      case '-':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.todo;
    }
  }
}

/// Obsidian Tasks priority emojis, lowest numeric value = highest priority.
enum TaskPriority {
  highest(0, '🔺'),
  high(1, '⏫'),
  medium(2, '🔼'),
  none(3, ''),
  low(4, '🔽'),
  lowest(5, '🔻');

  final int rank;
  final String emoji;
  const TaskPriority(this.rank, this.emoji);

  static TaskPriority fromEmoji(String? emoji) {
    if (emoji == null || emoji.isEmpty) return TaskPriority.none;
    for (final p in TaskPriority.values) {
      if (p.emoji == emoji) return p;
    }
    return TaskPriority.none;
  }
}

class Task {
  final String description;
  final TaskStatus status;
  final DateTime? dueDate;
  final DateTime? scheduledDate;
  final DateTime? startDate;
  final DateTime? doneDate;
  final DateTime? cancelledDate;
  final TaskPriority priority;
  final List<String> tags;

  /// Absolute path of the markdown file the task came from.
  final String filePath;

  /// 0-based line number within the file.
  final int lineNumber;

  /// The exact source line as read from disk — used to do a safe
  /// read-modify-write round-trip when toggling status.
  final String rawLine;

  Task({
    required this.description,
    required this.status,
    required this.filePath,
    required this.lineNumber,
    required this.rawLine,
    this.dueDate,
    this.scheduledDate,
    this.startDate,
    this.doneDate,
    this.cancelledDate,
    this.priority = TaskPriority.none,
    this.tags = const [],
  });

  bool get isDone =>
      status == TaskStatus.done || status == TaskStatus.cancelled;

  /// File name without extension (e.g. "admin" for areas/admin.md).
  String get sourceLabel {
    final slash = filePath.lastIndexOf('/');
    final back = filePath.lastIndexOf(r'\');
    final cut = slash > back ? slash : back;
    final name = cut >= 0 ? filePath.substring(cut + 1) : filePath;
    return name.endsWith('.md') ? name.substring(0, name.length - 3) : name;
  }
}
