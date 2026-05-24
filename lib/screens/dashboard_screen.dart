import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../models/task.dart';
import '../services/notification_service.dart';
import '../services/obsidian_launcher.dart';
import '../services/widget_service.dart';
import '../services/settings_service.dart';
import '../services/task_writer.dart';
import '../services/vault_service.dart';
import '../widgets/quick_add_sheet.dart';
import '../widgets/task_card.dart';
import 'calendar_screen.dart';
import 'onboarding_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _settings = SettingsService();
  final _vault = VaultService();
  final _writer = TaskWriter();
  final _launcher = ObsidianLauncher();
  final _widget = WidgetService();
  final _notif = NotificationService();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {
    'overdue': GlobalKey(),
    'today': GlobalKey(),
    'week': GlobalKey(),
    'next30': GlobalKey(),
    'floating': GlobalKey(),
  };

  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void dispose() {
    _scrollController.dispose();
    _widgetClickSub?.cancel();
    super.dispose();
  }

  String? _vaultPath;
  bool _useAdvancedUri = false;
  bool _sortByFile = false;
  Set<String> _collapsed = <String>{};
  // In-memory only — cleared on app restart.
  final Set<String> _activeTagFilters = <String>{};
  final Set<String> _activeFolderFilters = <String>{};
  final Set<DateTime> _activeDateFilters = <DateTime>{};

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  List<Task> _tasks = const [];
  int _fileCount = 0;
  List<String> _errors = const [];
  bool _loading = true;
  String? _error;

  void _toggleTagFilter(String tag) {
    setState(() {
      if (!_activeTagFilters.remove(tag)) _activeTagFilters.add(tag);
    });
  }

  void _toggleFolderFilter(String folder) {
    setState(() {
      if (!_activeFolderFilters.remove(folder)) _activeFolderFilters.add(folder);
    });
  }

  void _toggleDateFilter(DateTime day) {
    setState(() {
      if (!_activeDateFilters.remove(day)) _activeDateFilters.add(day);
    });
  }

  String _buildNotificationBody() {
    final parts = <String>[];
    if (_overdue.isNotEmpty) parts.add('⚠️ ${_overdue.length} overdue');
    parts.add('📅 ${_todayTasks.length} today');
    if (_thisWeek.isNotEmpty) parts.add('📆 ${_thisWeek.length} this week');
    return parts.join(' · ');
  }

  bool _passesFilter(Task t) {
    for (final tag in _activeTagFilters) {
      if (!t.tags.contains(tag)) return false;
    }
    for (final folder in _activeFolderFilters) {
      if (t.sourceLabel != folder) return false;
    }
    if (_activeDateFilters.isNotEmpty) {
      final d = t.dueDate ?? t.scheduledDate;
      if (d == null) return false;
      if (!_activeDateFilters.contains(_dayOf(d))) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _setupWidgetClickListener();
  }

  /// Listen for widget-initiated launches that carry a URI we recognise.
  /// `obsidian-agenda://quick-add` opens the inbox quick-add sheet.
  void _setupWidgetClickListener() {
    if (!Platform.isAndroid) return;
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
    _widgetClickSub = HomeWidget.widgetClicked.listen(_handleWidgetUri);
  }

  void _handleWidgetUri(Uri? uri) {
    if (uri == null) return;
    if (uri.host == 'quick-add' || uri.path == '/quick-add') {
      // Wait until the dashboard has finished its first build + bootstrap
      // before showing the sheet; vault path must be known.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vaultPath != null) _quickAdd();
      });
    }
  }

  Future<void> _bootstrap() async {
    // First-launch wizard. Skip silently for existing users who already
    // configured a vault before the wizard existed.
    final onboardingDone = await _settings.getOnboardingDone();
    final preExistingPath = await _settings.getVaultPath();
    if (!onboardingDone) {
      if (preExistingPath != null) {
        await _settings.setOnboardingDone(true);
      } else if (mounted) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    }

    final path = await _settings.getVaultPath();
    final adv = await _settings.getUseAdvancedUri();
    final collapsed = await _settings.getCollapsedSections();
    final sortByFile = await _settings.getSortByFile();
    setState(() {
      _vaultPath = path;
      _useAdvancedUri = adv;
      _collapsed = collapsed;
      _sortByFile = sortByFile;
    });
    if (path == null) {
      setState(() => _loading = false);
      return;
    }
    await _reload();
  }

  Future<void> _scrollToSection(String id) async {
    if (_collapsed.contains(id)) {
      setState(() => _collapsed.remove(id));
      await _settings.setCollapsedSections(_collapsed);
      await WidgetsBinding.instance.endOfFrame;
    }
    final ctx = _sectionKeys[id]?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: 0.0,
    );
  }

  Future<void> _toggleSection(String id) async {
    setState(() {
      if (_collapsed.contains(id)) {
        _collapsed.remove(id);
      } else {
        _collapsed.add(id);
      }
    });
    await _settings.setCollapsedSections(_collapsed);
  }

  Future<void> _reload() async {
    if (_vaultPath == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _vault.loadVault(_vaultPath!);
      if (!mounted) return;
      setState(() {
        _tasks = res.tasks;
        _fileCount = res.fileCount;
        _errors = res.errors;
        _loading = false;
      });
      // Push the freshly bucketed agenda out to the Android home widget.
      // Computed after setState so the getters see the new _tasks.
      final opacity = await _settings.getWidgetOpacity();
      await _widget.push(
        overdue: _overdue,
        today: _todayTasks,
        week: _thisWeek,
        next30: _next30,
        floating: _floating,
        vaultPath: _vaultPath!,
        useAdvancedUri: _useAdvancedUri,
        opacity: opacity,
      );

      // Reschedule (or cancel) the daily notification with fresh counts.
      if (await _settings.getNotifyEnabled()) {
        final h = await _settings.getNotifyHour();
        final m = await _settings.getNotifyMinute();
        final body = _buildNotificationBody();
        await _notif.schedule(hour: h, minute: m, body: body);
      } else {
        await _notif.cancel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (changed == true) {
      await _bootstrap();
    }
  }

  Future<void> _quickAdd() async {
    if (_vaultPath == null) return;
    // Count tag frequency across the whole vault so the suggestion
    // chips surface the user's most-used tags first.
    final counts = <String, int>{};
    for (final t in _tasks) {
      for (final tag in t.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final knownTags = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(
        vaultPath: _vaultPath!,
        knownTags: knownTags,
      ),
    );
    if (added == true) {
      await _reload();
    }
  }

  Future<void> _openInObsidian(Task task) async {
    if (_vaultPath == null) return;
    final ok = await _launcher.openTask(
      task,
      vaultPath: _vaultPath!,
      useAdvancedUri: _useAdvancedUri,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open Obsidian. Is the app installed and is "${_vaultPath!.split('/').last}" '
            'registered as a vault?',
          ),
        ),
      );
    }
  }

  Future<void> _changeStatus(Task task, TaskStatus newStatus) async {
    final newLine = await _writer.setStatus(task, newStatus);
    if (newLine == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not update — source file changed since loading. Pull to refresh.',
          ),
        ),
      );
      return;
    }
    await _reload();
  }

  Future<void> _reschedule(Task task, DateTime? newDue) async {
    final newLine = await _writer.setDueDate(task, newDue);
    if (newLine == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reschedule — source file changed since loading. Pull to refresh.',
          ),
        ),
      );
      return;
    }
    await _reload();
  }

  // ---- bucketing ----

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Task> get _open =>
      _tasks.where((t) => !t.isDone && _passesFilter(t)).toList();

  List<Task> get _overdue => _open
      .where((t) => t.dueDate != null && t.dueDate!.isBefore(_today))
      .toList()
    ..sort(_byDueThenPriority);

  List<Task> get _todayTasks => _open
      .where((t) =>
          (t.dueDate != null && _isSameDay(t.dueDate!, _today)) ||
          (t.scheduledDate != null && _isSameDay(t.scheduledDate!, _today)))
      .toList()
    ..sort(_byDueThenPriority);

  List<Task> get _thisWeek {
    final end = _today.add(const Duration(days: 7));
    return _open
        .where((t) =>
            t.dueDate != null &&
            t.dueDate!.isAfter(_today) &&
            t.dueDate!.isBefore(end))
        .toList()
      ..sort(_byDueThenPriority);
  }

  List<Task> get _next30 {
    final weekEnd = _today.add(const Duration(days: 7));
    final monthEnd = _today.add(const Duration(days: 30));
    return _open
        .where((t) =>
            t.dueDate != null &&
            !t.dueDate!.isBefore(weekEnd) &&
            t.dueDate!.isBefore(monthEnd))
        .toList()
      ..sort(_byDueThenPriority);
  }

  List<Task> get _floating =>
      _open.where((t) => t.dueDate == null && t.scheduledDate == null).toList()
        ..sort(_sortByFile
            ? _byFileThenPriority
            : (a, b) => a.priority.rank.compareTo(b.priority.rank));

  int _byDueThenPriority(Task a, Task b) {
    if (_sortByFile) return _byFileThenPriority(a, b);
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

  int _byFileThenPriority(Task a, Task b) {
    final c = a.sourceLabel.toLowerCase().compareTo(b.sourceLabel.toLowerCase());
    if (c != 0) return c;
    // Within the same file, fall back to line order so tasks appear in
    // the same sequence as in the source markdown.
    final l = a.lineNumber.compareTo(b.lineNumber);
    if (l != 0) return l;
    return a.priority.rank.compareTo(b.priority.rank);
  }

  static const _sectionOrder = ['overdue', 'today', 'week', 'next30', 'floating'];

  Map<ShortcutActivator, VoidCallback> _shortcuts() {
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (var i = 0; i < _sectionOrder.length; i++) {
      final id = _sectionOrder[i];
      final digit = LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i);
      // ⌘ on macOS, Ctrl on Linux/Windows/Android — both bind here so the
      // dashboard feels native everywhere.
      bindings[SingleActivator(digit, meta: true)] = () => _scrollToSection(id);
      bindings[SingleActivator(digit, control: true)] = () => _scrollToSection(id);
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: _shortcuts(),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Agenda'),
            actions: [
              IconButton(
                icon: Icon(_sortByFile
                    ? Icons.folder_outlined
                    : Icons.event_outlined),
                tooltip: _sortByFile
                    ? 'Sorted by file — switch to by date'
                    : 'Sorted by date — switch to by file',
                onPressed: _vaultPath == null
                    ? null
                    : () async {
                        await _settings.setSortByFile(!_sortByFile);
                        setState(() => _sortByFile = !_sortByFile);
                      },
              ),
              IconButton(
                icon: const Icon(Icons.calendar_month),
                tooltip: 'Calendar view',
                onPressed: _vaultPath == null
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CalendarScreen()),
                        );
                        // Reload in case the user toggled state from
                        // inside the calendar view.
                        if (mounted) await _reload();
                      },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _vaultPath == null ? null : _reload,
                tooltip: 'Reload',
              ),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: _openSettings,
                tooltip: 'Settings',
              ),
            ],
          ),
          body: _buildBody(),
          floatingActionButton: _vaultPath == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: _quickAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Inbox'),
                  tooltip: 'Quick-add to inbox.md',
                ),
          bottomNavigationBar: _vaultPath == null || _tasks.isEmpty
              ? null
              : _AnchorBar(
                  entries: [
                    _AnchorEntry('overdue', '⚠️', _overdue.length, Colors.red, 1),
                    _AnchorEntry('today', '📅', _todayTasks.length, Colors.blue, 2),
                    _AnchorEntry('week', '📆', _thisWeek.length, Colors.green, 3),
                    _AnchorEntry('next30', '🔜', _next30.length, Colors.orange, 4),
                    _AnchorEntry('floating', '📂', _floating.length, Colors.grey, 5),
                  ],
                  onTap: _scrollToSection,
                ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_vaultPath == null) {
      return _Empty(
        icon: Icons.folder_off,
        title: 'No vault selected',
        message:
            'Open settings and pick the folder containing your Obsidian markdown files.',
        action: FilledButton.icon(
          onPressed: _openSettings,
          icon: const Icon(Icons.folder_open),
          label: const Text('Pick vault folder'),
        ),
      );
    }
    if (_error != null) {
      return _Empty(
        icon: Icons.error_outline,
        title: 'Could not read vault',
        message: _error!,
        action: FilledButton(onPressed: _bootstrap, child: const Text('Retry')),
      );
    }
    if (_tasks.isEmpty) {
      return _Empty(
        icon: Icons.task_alt,
        title: 'No tasks found',
        message:
            'Scanned $_fileCount markdown files but found no Obsidian Tasks lines.',
        action: FilledButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_activeTagFilters.isNotEmpty ||
                _activeFolderFilters.isNotEmpty ||
                _activeDateFilters.isNotEmpty)
              _FilterBar(
                tags: _activeTagFilters,
                folders: _activeFolderFilters,
                dates: _activeDateFilters,
                onRemoveTag: _toggleTagFilter,
                onRemoveFolder: _toggleFolderFilter,
                onRemoveDate: _toggleDateFilter,
                onClearAll: () => setState(() {
                  _activeTagFilters.clear();
                  _activeFolderFilters.clear();
                  _activeDateFilters.clear();
                }),
              ),
            _section('overdue', '⚠️ Overdue', _overdue, color: Colors.red),
            _section('today', '📅 Today', _todayTasks, color: Colors.blue),
            _section('week', '📆 This week', _thisWeek, color: Colors.green),
            _section('next30', '🔜 Next 30 days', _next30, color: Colors.orange),
            _section('floating', '📂 Floating (no date)', _floating,
                color: Colors.grey),
            if (_errors.isNotEmpty) _errorsBox(),
          ],
        ),
      ),
    );
  }

  Widget _section(String id, String title, List<Task> tasks,
      {required MaterialColor color}) {
    final collapsed = _collapsed.contains(id);
    final p = _paletteFor(color, Theme.of(context).brightness);
    return Padding(
      key: _sectionKeys[id],
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleSection(id),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    color: p.icon,
                    size: 22,
                  ),
                  const SizedBox(width: 2),
                  Text(title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: p.icon,
                      )),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.bg,
                      border: Border.all(color: p.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${tasks.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: p.text,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            if (tasks.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Nothing here.',
                    style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              ...tasks.map((t) => TaskCard(
                    task: t,
                    onChangeStatus: (s) => _changeStatus(t, s),
                    onOpen: () => _openInObsidian(t),
                    onReschedule: (d) => _reschedule(t, d),
                    onToggleTagFilter: _toggleTagFilter,
                    onToggleFolderFilter: _toggleFolderFilter,
                    onToggleDateFilter: _toggleDateFilter,
                    activeTags: _activeTagFilters,
                    activeFolders: _activeFolderFilters,
                    activeDates: _activeDateFilters,
                  )),
        ],
      ),
    );
  }

  Widget _errorsBox() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: ExpansionTile(
        title: Text('${_errors.length} parse errors',
            style: const TextStyle(color: Colors.redAccent)),
        children: _errors
            .map((e) => ListTile(
                  dense: true,
                  title: Text(e, style: const TextStyle(fontSize: 12)),
                ))
            .toList(),
      ),
    );
  }
}

/// Brightness-aware color slot for a section. Light mode uses Material's
/// curated pale shades; dark mode tints the page background with the seed
/// instead of using near-black `shadeXXX` swatches.
typedef SectionPalette = ({Color bg, Color border, Color text, Color icon});

SectionPalette _paletteFor(MaterialColor seed, Brightness b) {
  if (b == Brightness.dark) {
    return (
      bg: seed.withValues(alpha: 0.18),
      border: seed.shade400.withValues(alpha: 0.55),
      text: seed.shade200,
      icon: seed.shade200,
    );
  }
  return (
    bg: seed.shade50,
    border: seed.shade200,
    text: seed.shade800,
    icon: seed.shade700,
  );
}

class _AnchorEntry {
  final String id;
  final String emoji;
  final int count;
  final MaterialColor color;
  final int shortcutDigit;
  _AnchorEntry(this.id, this.emoji, this.count, this.color, this.shortcutDigit);
}

class _AnchorBar extends StatelessWidget {
  final List<_AnchorEntry> entries;
  final void Function(String id) onTap;

  const _AnchorBar({required this.entries, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final modKey = isMac ? '⌘' : 'Ctrl';
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (final e in entries) ...[
                Builder(builder: (context) {
                  final p = _paletteFor(e.color, Theme.of(context).brightness);
                  return Tooltip(
                    message: '$modKey${e.shortcutDigit}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onTap(e.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(e.emoji,
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text(
                              '${e.count}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: p.text,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final Set<String> tags;
  final Set<String> folders;
  final Set<DateTime> dates;
  final void Function(String tag) onRemoveTag;
  final void Function(String folder) onRemoveFolder;
  final void Function(DateTime date) onRemoveDate;
  final VoidCallback onClearAll;

  const _FilterBar({
    required this.tags,
    required this.folders,
    required this.dates,
    required this.onRemoveTag,
    required this.onRemoveFolder,
    required this.onRemoveDate,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedDates = dates.toList()..sort();
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.filter_alt, size: 16, color: theme.colorScheme.primary),
          ),
          for (final folder in folders)
            _FilterPill(
              icon: Icons.folder_outlined,
              label: folder,
              color: theme.colorScheme.outline,
              onRemove: () => onRemoveFolder(folder),
            ),
          for (final tag in tags)
            _FilterPill(
              icon: Icons.tag,
              label: tag,
              color: theme.colorScheme.tertiary,
              onRemove: () => onRemoveTag(tag),
            ),
          for (final date in sortedDates)
            _FilterPill(
              icon: Icons.event,
              label: DateFormat('MMM d').format(date),
              color: theme.colorScheme.primary,
              onRemove: () => onRemoveDate(date),
            ),
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onRemove;

  const _FilterPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onRemove,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(width: 4),
            Icon(Icons.close, size: 13, color: color),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            action,
          ],
        ),
      ),
    );
  }
}
