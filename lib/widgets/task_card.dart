import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';

class TaskCard extends StatelessWidget {
  final Task task;

  /// Called when the user changes the task's status. Triggered by either
  /// a tap on the status button (toggle) or a selection from the
  /// long-press / right-click menu (any of the four states).
  final void Function(TaskStatus newStatus) onChangeStatus;

  /// Called when the user taps the card body — opens the source in Obsidian.
  final VoidCallback onOpen;

  /// Reschedule the task to a new due date (null = clear the date). Triggered
  /// from the long-press menu or from a long-press on the date chip itself.
  final void Function(DateTime? newDue)? onReschedule;

  /// Tag / folder / date filter toggles. Optional — if null, those chips
  /// render as plain decorations like before.
  final void Function(String tag)? onToggleTagFilter;
  final void Function(String folder)? onToggleFolderFilter;
  final void Function(DateTime date)? onToggleDateFilter;
  final Set<String> activeTags;
  final Set<String> activeFolders;

  /// Active date filters, normalised to start-of-day.
  final Set<DateTime> activeDates;

  const TaskCard({
    super.key,
    required this.task,
    required this.onChangeStatus,
    required this.onOpen,
    this.onReschedule,
    this.onToggleTagFilter,
    this.onToggleFolderFilter,
    this.onToggleDateFilter,
    this.activeTags = const {},
    this.activeFolders = const {},
    this.activeDates = const {},
  });

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _openMenuAt(BuildContext context, Offset globalPos) async {
    final picked = await _showCardMenu(context, task, globalPos);
    if (picked == null || !context.mounted) return;
    await _applyAction(context, picked);
  }

  Future<void> _applyAction(BuildContext context, _CardAction action) async {
    switch (action) {
      case _SetStatus(:final status):
        if (status != task.status) onChangeStatus(status);
        return;
      case _RescheduleTo(:final date):
        if (onReschedule != null) onReschedule!(date);
        return;
      case _ReschedulePick():
        final picked = await showDatePicker(
          context: context,
          initialDate: task.dueDate ?? DateTime.now(),
          firstDate: DateTime(DateTime.now().year - 1),
          lastDate: DateTime(DateTime.now().year + 5),
        );
        if (picked != null && onReschedule != null) onReschedule!(picked);
        return;
    }
  }

  Future<void> _openMenuFromWidget(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final pos = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
    await _openMenuAt(context, pos);
  }

  /// Long-press on the due-date chip → date picker.
  Future<void> _pickDateFromChip(BuildContext context) async {
    if (onReschedule == null) return;
    final initial = task.dueDate ?? task.scheduledDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) onReschedule!(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue = task.dueDate != null &&
        !task.isDone &&
        task.dueDate!.isBefore(_today());

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onOpen,
        onLongPress: () => _openMenuFromWidget(context),
        onSecondaryTapDown: (d) => _openMenuAt(context, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusButton(
                status: task.status,
                onTap: () => onChangeStatus(_nextOnTap(task.status)),
                onOpenMenu: (pos) => _openMenuAt(context, pos),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.description,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          decoration: task.isDone
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.isDone
                              ? theme.disabledColor
                              : theme.textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (task.priority != TaskPriority.none)
                            Text(task.priority.emoji,
                                style: const TextStyle(fontSize: 14)),
                          if (task.dueDate != null)
                            _Chip(
                              icon: Icons.event,
                              label: _fmt(task.dueDate!),
                              color: overdue
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                              active: activeDates.contains(_dayOf(task.dueDate!)),
                              onTap: onToggleDateFilter == null
                                  ? null
                                  : () => onToggleDateFilter!(_dayOf(task.dueDate!)),
                              onLongPress: onReschedule == null
                                  ? null
                                  : () => _pickDateFromChip(context),
                            ),
                          if (task.scheduledDate != null &&
                              task.dueDate == null)
                            _Chip(
                              icon: Icons.schedule,
                              label: _fmt(task.scheduledDate!),
                              color: theme.colorScheme.secondary,
                              active: activeDates.contains(_dayOf(task.scheduledDate!)),
                              onTap: onToggleDateFilter == null
                                  ? null
                                  : () => onToggleDateFilter!(_dayOf(task.scheduledDate!)),
                              onLongPress: onReschedule == null
                                  ? null
                                  : () => _pickDateFromChip(context),
                            ),
                          _Chip(
                            icon: Icons.folder_outlined,
                            label: task.sourceLabel,
                            color: theme.colorScheme.outline,
                            active: activeFolders.contains(task.sourceLabel),
                            onTap: onToggleFolderFilter == null
                                ? null
                                : () => onToggleFolderFilter!(task.sourceLabel),
                          ),
                          for (final tag in task.tags)
                            _Chip(
                              icon: Icons.tag,
                              label: tag,
                              color: theme.colorScheme.tertiary,
                              active: activeTags.contains(tag),
                              onTap: onToggleTagFilter == null
                                  ? null
                                  : () => onToggleTagFilter!(tag),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static TaskStatus _nextOnTap(TaskStatus current) {
    switch (current) {
      case TaskStatus.todo:
      case TaskStatus.inProgress:
        return TaskStatus.done;
      case TaskStatus.done:
      case TaskStatus.cancelled:
        return TaskStatus.todo;
    }
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _fmt(DateTime d) => DateFormat('MMM d').format(d);
}

class _StatusButton extends StatelessWidget {
  final TaskStatus status;
  final VoidCallback onTap;
  final void Function(Offset globalPos) onOpenMenu;

  const _StatusButton({
    required this.status,
    required this.onTap,
    required this.onOpenMenu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Tap to toggle · long-press / right-click for states',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        onLongPress: () {
          final box = context.findRenderObject()! as RenderBox;
          onOpenMenu(box.localToGlobal(
              Offset(box.size.width, box.size.height / 2)));
        },
        onSecondaryTapDown: (d) => onOpenMenu(d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            _statusIcon(status),
            size: 24,
            color: _statusColor(status, theme),
          ),
        ),
      ),
    );
  }
}

// --- shared menu helpers ---

sealed class _CardAction {
  const _CardAction();
}

class _SetStatus extends _CardAction {
  final TaskStatus status;
  const _SetStatus(this.status);
}

class _RescheduleTo extends _CardAction {
  /// null = clear the due date.
  final DateTime? date;
  const _RescheduleTo(this.date);
}

class _ReschedulePick extends _CardAction {
  const _ReschedulePick();
}

Future<_CardAction?> _showCardMenu(
  BuildContext context,
  Task task,
  Offset globalPos,
) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final today = DateTime.now();
  final today0 = DateTime(today.year, today.month, today.day);
  final tomorrow = today0.add(const Duration(days: 1));
  final inAWeek = today0.add(const Duration(days: 7));
  return showMenu<_CardAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      globalPos.dx,
      globalPos.dy,
      overlay.size.width - globalPos.dx,
      overlay.size.height - globalPos.dy,
    ),
    items: [
      for (final s in TaskStatus.values)
        PopupMenuItem<_CardAction>(
          value: _SetStatus(s),
          child: Row(
            children: [
              Icon(_statusIcon(s),
                  size: 18, color: _statusColor(s, Theme.of(context))),
              const SizedBox(width: 10),
              Text(_statusLabel(s)),
              const Spacer(),
              if (s == task.status)
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(Icons.check, size: 16),
                ),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<_CardAction>(
        value: _RescheduleTo(tomorrow),
        child: const _RescheduleRow(label: 'Reschedule to tomorrow'),
      ),
      PopupMenuItem<_CardAction>(
        value: _RescheduleTo(inAWeek),
        child: const _RescheduleRow(label: 'Reschedule +1 week'),
      ),
      const PopupMenuItem<_CardAction>(
        value: _ReschedulePick(),
        child: _RescheduleRow(label: 'Reschedule to…'),
      ),
      if (task.dueDate != null)
        const PopupMenuItem<_CardAction>(
          value: _RescheduleTo(null),
          child: _RescheduleRow(
            label: 'Clear due date',
            icon: Icons.event_busy,
          ),
        ),
    ],
  );
}

class _RescheduleRow extends StatelessWidget {
  final String label;
  final IconData icon;
  const _RescheduleRow({required this.label, this.icon = Icons.event});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

IconData _statusIcon(TaskStatus s) {
  switch (s) {
    case TaskStatus.todo:
      return Icons.check_box_outline_blank;
    case TaskStatus.inProgress:
      return Icons.timelapse;
    case TaskStatus.done:
      return Icons.check_box;
    case TaskStatus.cancelled:
      return Icons.indeterminate_check_box;
  }
}

Color _statusColor(TaskStatus s, ThemeData theme) {
  switch (s) {
    case TaskStatus.todo:
      return theme.colorScheme.onSurfaceVariant;
    case TaskStatus.inProgress:
      return theme.colorScheme.tertiary;
    case TaskStatus.done:
      return theme.colorScheme.primary;
    case TaskStatus.cancelled:
      return theme.disabledColor;
  }
}

String _statusLabel(TaskStatus s) {
  switch (s) {
    case TaskStatus.todo:
      return 'TODO';
    case TaskStatus.inProgress:
      return 'WAIT';
    case TaskStatus.done:
      return 'DONE';
    case TaskStatus.cancelled:
      return 'CANCELLED';
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool active;

  const _Chip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.onLongPress,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgAlpha = active ? 0.32 : 0.12;
    final fg = active ? color : color;
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(10),
        border: active ? Border.all(color: color, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(active ? Icons.check : icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              )),
        ],
      ),
    );
    if (onTap == null && onLongPress == null) return chip;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: chip,
    );
  }
}
