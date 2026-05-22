import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/task.dart';
import '../services/obsidian_launcher.dart';
import '../services/settings_service.dart';
import '../services/task_writer.dart';
import '../services/vault_service.dart';
import '../widgets/task_card.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _settings = SettingsService();
  final _vault = VaultService();
  final _writer = TaskWriter();
  final _launcher = ObsidianLauncher();

  String? _vaultPath;
  bool _useAdvancedUri = false;
  Map<DateTime, List<Task>> _eventsByDay = const {};
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = _today();
  CalendarFormat _format = CalendarFormat.month;
  bool _loading = true;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = await _settings.getVaultPath();
    final adv = await _settings.getUseAdvancedUri();
    if (path == null) {
      setState(() {
        _vaultPath = null;
        _useAdvancedUri = adv;
        _loading = false;
      });
      return;
    }
    final res = await _vault.loadVault(path);
    if (!mounted) return;
    setState(() {
      _vaultPath = path;
      _useAdvancedUri = adv;
      _eventsByDay = _groupByDay(res.tasks);
      _loading = false;
    });
  }

  Map<DateTime, List<Task>> _groupByDay(List<Task> tasks) {
    final map = <DateTime, List<Task>>{};
    for (final t in tasks) {
      if (t.isDone) continue;
      final date = t.dueDate ?? t.scheduledDate;
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      map.putIfAbsent(day, () => []).add(t);
    }
    return map;
  }

  List<Task> _eventsForDay(DateTime day) {
    return _eventsByDay[DateTime(day.year, day.month, day.day)] ?? const [];
  }

  Future<void> _changeStatus(Task task, TaskStatus newStatus) async {
    final newLine = await _writer.setStatus(task, newStatus);
    if (newLine == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update — source file changed since loading. Reload.',
          ),
        ),
      );
      return;
    }
    await _load();
  }

  Future<void> _reschedule(Task task, DateTime? newDue) async {
    final newLine = await _writer.setDueDate(task, newDue);
    if (newLine == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not reschedule — source file changed since loading. Reload.'),
        ),
      );
      return;
    }
    await _load();
  }

  Future<void> _openInObsidian(Task task) async {
    if (_vaultPath == null) return;
    await _launcher.openTask(
      task,
      vaultPath: _vaultPath!,
      useAdvancedUri: _useAdvancedUri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Jump to today',
            onPressed: () => setState(() {
              _focusedDay = DateTime.now();
              _selectedDay = _today();
            }),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _vaultPath == null
              ? const Center(child: Text('Pick a vault in Settings first.'))
              : Column(
                  children: [
                    Material(
                      color: theme.colorScheme.surfaceContainerLow,
                      child: TableCalendar<Task>(
                        firstDay: DateTime(DateTime.now().year - 2, 1, 1),
                        lastDay: DateTime(DateTime.now().year + 3, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (d) =>
                            isSameDay(_selectedDay, d),
                        calendarFormat: _format,
                        availableCalendarFormats: const {
                          CalendarFormat.month: 'Month',
                          CalendarFormat.twoWeeks: '2 weeks',
                          CalendarFormat.week: 'Week',
                        },
                        eventLoader: _eventsForDay,
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        onDaySelected: (selected, focused) {
                          setState(() {
                            _selectedDay = DateTime(
                                selected.year, selected.month, selected.day);
                            _focusedDay = focused;
                          });
                        },
                        onFormatChanged: (fmt) =>
                            setState(() => _format = fmt),
                        onPageChanged: (focused) => _focusedDay = focused,
                        calendarStyle: CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          todayTextStyle: TextStyle(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold),
                          selectedDecoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          markerDecoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          markersMaxCount: 3,
                          markerSize: 5,
                          markersAlignment: Alignment.bottomCenter,
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonShowsNext: false,
                          titleCentered: true,
                        ),
                        calendarBuilders: CalendarBuilders<Task>(
                          defaultBuilder: (ctx, day, focused) =>
                              _dropTargetCell(ctx, day, _DayKind.normal),
                          todayBuilder: (ctx, day, focused) =>
                              _dropTargetCell(ctx, day, _DayKind.today),
                          selectedBuilder: (ctx, day, focused) =>
                              _dropTargetCell(ctx, day, _DayKind.selected),
                          outsideBuilder: (ctx, day, focused) =>
                              _dropTargetCell(ctx, day, _DayKind.outside),
                        ),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Text(
                            DateFormat('EEEE, MMM d')
                                .format(_selectedDay),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          Text(
                            '${_eventsForDay(_selectedDay).length} open',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 8),
                    Expanded(
                      child: _eventsForDay(_selectedDay).isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No tasks for this day.',
                                  style: TextStyle(
                                      color: theme.colorScheme.outline),
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                              children: _eventsForDay(_selectedDay)
                                  .map((t) => LongPressDraggable<Task>(
                                        data: t,
                                        delay: const Duration(milliseconds: 280),
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: SizedBox(
                                            width: MediaQuery.of(context).size.width - 24,
                                            child: Opacity(
                                              opacity: 0.85,
                                              child: TaskCard(
                                                task: t,
                                                onChangeStatus: (_) {},
                                                onOpen: () {},
                                              ),
                                            ),
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.4,
                                          child: TaskCard(
                                            task: t,
                                            onChangeStatus: (_) {},
                                            onOpen: () {},
                                          ),
                                        ),
                                        child: TaskCard(
                                          task: t,
                                          onChangeStatus: (s) =>
                                              _changeStatus(t, s),
                                          onOpen: () => _openInObsidian(t),
                                          onReschedule: (d) =>
                                              _reschedule(t, d),
                                        ),
                                      ))
                                  .toList(),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _dropTargetCell(BuildContext context, DateTime day, _DayKind kind) {
    final theme = Theme.of(context);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final task = details.data;
        final target = DateTime(day.year, day.month, day.day);
        // Skip the no-op (dropped on a day that's already the due date).
        final existing = task.dueDate ?? task.scheduledDate;
        if (existing != null &&
            existing.year == day.year &&
            existing.month == day.month &&
            existing.day == day.day) {
          return;
        }
        _reschedule(task, target);
      },
      builder: (ctx, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return _DayCell(day: day, kind: kind, dropHovering: hovering, theme: theme);
      },
    );
  }
}

enum _DayKind { normal, today, selected, outside }

class _DayCell extends StatelessWidget {
  final DateTime day;
  final _DayKind kind;
  final bool dropHovering;
  final ThemeData theme;

  const _DayCell({
    required this.day,
    required this.kind,
    required this.dropHovering,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    Color? bg;
    Color fg = theme.textTheme.bodyMedium?.color ?? Colors.black;
    if (kind == _DayKind.selected) {
      bg = theme.colorScheme.primary;
      fg = theme.colorScheme.onPrimary;
    } else if (kind == _DayKind.today) {
      bg = theme.colorScheme.primaryContainer;
      fg = theme.colorScheme.onPrimaryContainer;
    } else if (kind == _DayKind.outside) {
      fg = theme.colorScheme.outline;
    }
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dropHovering
            ? theme.colorScheme.tertiaryContainer
            : bg,
        shape: BoxShape.circle,
        border: dropHovering
            ? Border.all(color: theme.colorScheme.tertiary, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '${day.day}',
        style: TextStyle(
          color: dropHovering ? theme.colorScheme.onTertiaryContainer : fg,
          fontWeight: kind == _DayKind.today || kind == _DayKind.selected
              ? FontWeight.bold
              : FontWeight.normal,
        ),
      ),
    );
  }
}
