import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/inbox_writer.dart';

/// Modal bottom sheet for quickly capturing a new task into the vault's
/// inbox.md file. Returns true via [Navigator.pop] when a task was saved.
class QuickAddSheet extends StatefulWidget {
  final String vaultPath;

  /// Tags already seen in the vault — used as suggestion chips below the
  /// tag input field.
  final List<String> knownTags;

  const QuickAddSheet({
    super.key,
    required this.vaultPath,
    this.knownTags = const [],
  });

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _descController = TextEditingController();
  final _tagController = TextEditingController();
  final _descFocus = FocusNode();
  DateTime? _dueDate;
  TaskPriority _priority = TaskPriority.none;
  final Set<String> _selectedTags = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _descFocus.requestFocus());
  }

  @override
  void dispose() {
    _descController.dispose();
    _tagController.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  void _toggleTag(String tag) {
    setState(() {
      if (!_selectedTags.remove(tag)) _selectedTags.add(tag);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final desc = _descController.text.trim();
    if (desc.isEmpty) {
      _descFocus.requestFocus();
      return;
    }
    setState(() => _saving = true);

    final tags = <String>{
      ..._selectedTags,
      ..._tagController.text
          .split(RegExp(r'[\s,]+'))
          .where((t) => t.isNotEmpty),
    }.toList();

    final line = await InboxWriter.append(
      vaultPath: widget.vaultPath,
      description: desc,
      dueDate: _dueDate,
      priority: _priority,
      tags: tags,
    );

    if (!mounted) return;
    setState(() => _saving = false);
    if (line != null) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New inbox task',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _descController,
            focusNode: _descFocus,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What is the task?',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            maxLines: 3,
            minLines: 1,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event, size: 18),
                label: Text(_dueDate == null
                    ? 'Set due date'
                    : DateFormat('MMM d, y').format(_dueDate!)),
              ),
              if (_dueDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Clear date',
                  onPressed: () => setState(() => _dueDate = null),
                ),
              const SizedBox(width: 8),
              DropdownButton<TaskPriority>(
                value: _priority,
                underline: const SizedBox.shrink(),
                items: TaskPriority.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(p == TaskPriority.none
                              ? 'No priority'
                              : '${p.emoji}  ${_priorityName(p)}'),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _priority = v ?? TaskPriority.none),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tagController,
            decoration: const InputDecoration(
              labelText: 'Tags',
              hintText: 'space- or comma-separated, no # needed',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag, size: 18),
            ),
          ),
          if (widget.knownTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Suggestions',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in widget.knownTags)
                  FilterChip(
                    label: Text('#$tag'),
                    selected: _selectedTags.contains(tag),
                    onSelected: (_) => _toggleTag(tag),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Save to inbox'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _priorityName(TaskPriority p) {
    switch (p) {
      case TaskPriority.highest:
        return 'highest';
      case TaskPriority.high:
        return 'high';
      case TaskPriority.medium:
        return 'medium';
      case TaskPriority.none:
        return 'none';
      case TaskPriority.low:
        return 'low';
      case TaskPriority.lowest:
        return 'lowest';
    }
  }
}
