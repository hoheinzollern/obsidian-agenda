// Command-line interface for the Obsidian Agenda vault. Mirrors the
// in-app dashboard: list buckets, capture a new task to the inbox,
// flip status.
//
// Usage:
//   dart run tool/agenda.dart <subcommand>
//   # or once compiled:
//   #   dart compile exe tool/agenda.dart -o ~/.local/bin/agenda
//   #   agenda <subcommand>
//
// Vault is read from `--vault <path>` or the OBSIDIAN_AGENDA_VAULT
// environment variable.

import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import 'package:gtd/models/task.dart';
import 'package:gtd/parser/gtd_parser.dart';
import 'package:gtd/services/inbox_writer.dart';
import 'package:gtd/services/task_writer.dart';
import 'package:gtd/services/vault_service.dart';

Future<int> main(List<String> argv) async {
  final runner = CommandRunner<int>(
    'agenda',
    'Command-line interface for an Obsidian Agenda vault.',
  )
    ..argParser.addOption('vault',
        abbr: 'v',
        help: 'Vault root path. Defaults to \$OBSIDIAN_AGENDA_VAULT.')
    ..argParser.addFlag('no-color',
        negatable: false, help: 'Disable ANSI colour output.')
    ..addCommand(ListCommand())
    ..addCommand(_BucketShortcut('today', 'Tasks due or scheduled today.'))
    ..addCommand(_BucketShortcut('overdue', 'Tasks past their due date.'))
    ..addCommand(_BucketShortcut('week', 'Tasks due in the next 7 days.'))
    ..addCommand(_BucketShortcut('next30', 'Tasks due in days 8–30.'))
    ..addCommand(_BucketShortcut('floating', 'Tasks with no due/scheduled date.'))
    ..addCommand(AddCommand())
    ..addCommand(StatusCommand('done', 'Mark a task DONE (writes ✅ date).', 'x'))
    ..addCommand(StatusCommand('cancel', 'Mark a task CANCELLED (writes ❌ date).', '-'))
    ..addCommand(StatusCommand('wait', 'Set a task to WAIT (in progress).', '/'))
    ..addCommand(StatusCommand('todo', 'Reopen a task as TODO.', ' '))
    ..addCommand(RescheduleCommand())
    ..addCommand(ScanCommand())
    ..addCommand(ConfigCommand());

  try {
    final code = await runner.run(argv);
    return code ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    return 64;
  } on _CliError catch (e) {
    stderr.writeln('error: ${e.message}');
    return 1;
  }
}

// ============== shared helpers ==============

class _CliError implements Exception {
  final String message;
  _CliError(this.message);
}

/// Vault path resolution order: `--vault` flag > env > config file.
String _resolveVault(ArgResults? global) {
  final fromFlag = global?['vault'] as String?;
  final fromEnv = Platform.environment['OBSIDIAN_AGENDA_VAULT'];
  final fromConfig = _readConfig()['vault'];
  final path = (fromFlag?.isNotEmpty ?? false)
      ? fromFlag
      : (fromEnv?.isNotEmpty ?? false)
          ? fromEnv
          : fromConfig;
  if (path == null || path.isEmpty) {
    throw _CliError(
      'No vault configured. Set one with:\n'
      '  agenda config set vault /path/to/vault\n'
      'Or pass --vault, or export OBSIDIAN_AGENDA_VAULT.',
    );
  }
  if (!Directory(path).existsSync()) {
    throw _CliError('Vault folder not found: $path');
  }
  return path;
}

// ============== config file ==============

String _configPath() {
  final xdg = Platform.environment['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) {
    return p.join(xdg, 'obsidian-agenda', 'config');
  }
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw _CliError('HOME not set; cannot locate config directory.');
  }
  return p.join(home, '.config', 'obsidian-agenda', 'config');
}

Map<String, String> _readConfig() {
  try {
    final f = File(_configPath());
    if (!f.existsSync()) return const {};
    final out = <String, String>{};
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final i = t.indexOf('=');
      if (i < 0) continue;
      out[t.substring(0, i).trim()] = t.substring(i + 1).trim();
    }
    return out;
  } catch (_) {
    return const {};
  }
}

void _writeConfig(Map<String, String> map) {
  final path = _configPath();
  Directory(p.dirname(path)).createSync(recursive: true);
  final buf = StringBuffer('# obsidian-agenda config\n');
  final keys = map.keys.toList()..sort();
  for (final k in keys) {
    buf.writeln('$k=${map[k]}');
  }
  File(path).writeAsStringSync(buf.toString());
}

bool _useColor(ArgResults? global) {
  final disabled = (global?['no-color'] as bool?) ?? false;
  if (disabled) return false;
  if (Platform.environment['NO_COLOR']?.isNotEmpty ?? false) return false;
  return stdout.hasTerminal;
}

String _colored(String s, String code, bool on) =>
    on ? '[${code}m$s[0m' : s;

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

Map<String, List<Task>> _bucketize(List<Task> all) {
  final open = all.where((t) => !t.isDone);
  final today = _today();
  final weekEnd = today.add(const Duration(days: 7));
  final monthEnd = today.add(const Duration(days: 30));

  final overdue = <Task>[];
  final todayTasks = <Task>[];
  final week = <Task>[];
  final next30 = <Task>[];
  final floating = <Task>[];

  for (final t in open) {
    final due = t.dueDate;
    final sched = t.scheduledDate;
    if (due != null && due.isBefore(today)) {
      overdue.add(t);
    } else if ((due != null && _sameDay(due, today)) ||
        (sched != null && _sameDay(sched, today))) {
      todayTasks.add(t);
    } else if (due != null && due.isAfter(today) && due.isBefore(weekEnd)) {
      week.add(t);
    } else if (due != null && !due.isBefore(weekEnd) && due.isBefore(monthEnd)) {
      next30.add(t);
    } else if (due == null && sched == null) {
      floating.add(t);
    }
  }

  int byDate(Task a, Task b) {
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

  for (final list in [overdue, todayTasks, week, next30]) {
    list.sort(byDate);
  }
  floating.sort((a, b) => a.priority.rank.compareTo(b.priority.rank));

  return {
    'overdue': overdue,
    'today': todayTasks,
    'week': week,
    'next30': next30,
    'floating': floating,
  };
}

String _statusGlyph(TaskStatus s, bool color) {
  switch (s) {
    case TaskStatus.todo:
      return _colored('☐', '90', color);
    case TaskStatus.inProgress:
      return _colored('◐', '33', color);
    case TaskStatus.done:
      return _colored('☑', '32', color);
    case TaskStatus.cancelled:
      return _colored('☒', '37', color);
  }
}

String _formatTask(Task t, String vaultPath, bool color) {
  final rel = p.relative(t.filePath, from: vaultPath);
  final ref = '$rel:${t.lineNumber + 1}';
  final overdue = t.dueDate != null &&
      !t.isDone &&
      t.dueDate!.isBefore(_today());
  final glyph = _statusGlyph(t.status, color);
  final id = _colored(ref.padRight(36), '90', color);
  final desc = t.description;
  final extras = <String>[];
  if (t.priority != TaskPriority.none) extras.add(t.priority.emoji);
  if (t.dueDate != null) {
    final s = '📅 ${DateFormat('MMM d').format(t.dueDate!)}';
    extras.add(overdue ? _colored(s, '31', color) : s);
  } else if (t.scheduledDate != null) {
    extras.add('⏳ ${DateFormat('MMM d').format(t.scheduledDate!)}');
  }
  if (t.tags.isNotEmpty) {
    extras.add(_colored(t.tags.map((x) => '#$x').join(' '), '36', color));
  }
  return '$glyph $id $desc${extras.isEmpty ? '' : '  ${extras.join('  ')}'}';
}

Future<List<Task>> _loadAll(String vaultPath) async {
  final res = await VaultService().loadVault(vaultPath);
  return res.tasks;
}

/// Parse a `file:line` (1-based line) reference into an absolute path
/// and 0-based line index. Throws _CliError if malformed or missing.
({String absPath, int lineIndex}) _resolveRef(String ref, String vault) {
  final i = ref.lastIndexOf(':');
  if (i < 0) throw _CliError('Expected <file>:<line>, got: $ref');
  final relOrAbs = ref.substring(0, i);
  final line = int.tryParse(ref.substring(i + 1));
  if (line == null || line < 1) {
    throw _CliError('Line number must be a positive integer (1-based).');
  }
  final abs = p.isAbsolute(relOrAbs) ? relOrAbs : p.join(vault, relOrAbs);
  if (!File(abs).existsSync()) throw _CliError('File not found: $abs');
  return (absPath: abs, lineIndex: line - 1);
}

// ============== list / today / overdue / etc. ==============

class ListCommand extends Command<int> {
  @override
  String get name => 'list';

  @override
  String get description =>
      'List tasks. Default bucket is "today"; pass overdue, week, next30, '
      'floating, or all.';

  @override
  String get invocation => 'agenda list [bucket]';

  ListCommand() {
    argParser
      ..addOption('tag', help: 'Only show tasks with this tag.')
      ..addOption('folder',
          help: 'Only show tasks in this source file (basename).')
      ..addFlag('count',
          negatable: false, help: 'Print only the count of matching tasks.');
  }

  @override
  Future<int> run() async {
    final vault = _resolveVault(globalResults);
    final color = _useColor(globalResults);
    final tasks = await _loadAll(vault);
    final buckets = _bucketize(tasks);

    final rest = argResults?.rest ?? const [];
    final bucket = rest.isEmpty ? 'today' : rest.first;
    if (!buckets.containsKey(bucket) && bucket != 'all') {
      throw _CliError(
          'Unknown bucket "$bucket". Valid: ${buckets.keys.join(', ')}, all.');
    }

    final tag = argResults?['tag'] as String?;
    final folder = argResults?['folder'] as String?;
    final countOnly = argResults?['count'] as bool? ?? false;

    bool passes(Task t) {
      if (tag != null && !t.tags.contains(tag.replaceFirst('#', ''))) return false;
      if (folder != null && t.sourceLabel != folder) return false;
      return true;
    }

    if (bucket == 'all') {
      var total = 0;
      for (final key in buckets.keys) {
        final list = buckets[key]!.where(passes).toList();
        if (list.isEmpty) continue;
        total += list.length;
        if (countOnly) continue;
        _printSection(key, list, vault, color);
      }
      if (countOnly) print(total);
    } else {
      final list = buckets[bucket]!.where(passes).toList();
      if (countOnly) {
        print(list.length);
      } else {
        _printSection(bucket, list, vault, color);
      }
    }
    return 0;
  }

  void _printSection(String name, List<Task> tasks, String vault, bool color) {
    final headerColor = {
      'overdue': '31',
      'today': '34',
      'week': '32',
      'next30': '33',
      'floating': '90',
    }[name] ?? '37';
    final emoji = {
      'overdue': '⚠️ ',
      'today': '📅 ',
      'week': '📆 ',
      'next30': '🔜 ',
      'floating': '📂 ',
    }[name] ?? '';
    print('');
    print(_colored('$emoji$name (${tasks.length})', '1;$headerColor', color));
    if (tasks.isEmpty) {
      print(_colored('  Nothing here.', '90', color));
      return;
    }
    for (final t in tasks) {
      print('  ${_formatTask(t, vault, color)}');
    }
  }
}

class _BucketShortcut extends Command<int> {
  @override
  final String name;
  @override
  final String description;

  _BucketShortcut(this.name, this.description);

  @override
  Future<int> run() async {
    // Dispatch to the real list command with a fixed bucket argument.
    final list = ListCommand();
    final args = [name, ...?argResults?.rest];
    // Build a fake ArgResults by re-parsing — easier to just call _printSection.
    final vault = _resolveVault(globalResults);
    final color = _useColor(globalResults);
    final tasks = await _loadAll(vault);
    final buckets = _bucketize(tasks);
    list._printSection(name, buckets[name]!, vault, color);
    // Silence unused warning.
    args.toString();
    return 0;
  }
}

// ============== add ==============

class AddCommand extends Command<int> {
  @override
  String get name => 'add';

  @override
  String get description => 'Append a new TODO to <vault>/inbox.md.';

  @override
  String get invocation => 'agenda add <description...> [flags]';

  AddCommand() {
    argParser
      ..addOption('due', help: 'Due date YYYY-MM-DD.')
      ..addOption('prio',
          allowed: ['highest', 'high', 'medium', 'low', 'lowest', 'none'],
          defaultsTo: 'none',
          help: 'Priority level.')
      ..addMultiOption('tag', help: 'Tag (no #). Pass multiple times for multiple tags.');
  }

  @override
  Future<int> run() async {
    final vault = _resolveVault(globalResults);
    final color = _useColor(globalResults);
    final rest = argResults?.rest ?? const [];
    if (rest.isEmpty) {
      throw _CliError('Provide a task description, e.g. agenda add "Reply to Alice".');
    }
    final desc = rest.join(' ');

    DateTime? due;
    final dueStr = argResults?['due'] as String?;
    if (dueStr != null && dueStr.isNotEmpty) {
      due = DateTime.tryParse(dueStr);
      if (due == null) throw _CliError('Invalid date: $dueStr (use YYYY-MM-DD).');
    }

    final prio = {
      'highest': TaskPriority.highest,
      'high': TaskPriority.high,
      'medium': TaskPriority.medium,
      'low': TaskPriority.low,
      'lowest': TaskPriority.lowest,
      'none': TaskPriority.none,
    }[argResults?['prio'] as String? ?? 'none']!;

    final tags = (argResults?['tag'] as List<String>?) ?? const [];

    final line = await InboxWriter.append(
      vaultPath: vault,
      description: desc,
      dueDate: due,
      priority: prio,
      tags: tags,
    );
    if (line == null) {
      throw _CliError('Nothing written (empty description?).');
    }
    print('${_colored('✓', '32', color)} added to inbox.md:');
    print('  $line');
    return 0;
  }
}

// ============== status (done / cancel / wait / todo) ==============

class StatusCommand extends Command<int> {
  @override
  final String name;
  @override
  final String description;

  final String _newMarker;

  StatusCommand(this.name, this.description, this._newMarker);

  @override
  String get invocation => 'agenda $name <file>:<line>';

  @override
  Future<int> run() async {
    final vault = _resolveVault(globalResults);
    final color = _useColor(globalResults);
    final rest = argResults?.rest ?? const [];
    if (rest.length != 1) {
      throw _CliError('Expected exactly one <file>:<line> reference.');
    }
    final ref = _resolveRef(rest.first, vault);

    // Read fresh + parse the target line so we can use TaskWriter's
    // rawLine-protected setStatus (matches the GUI's safety invariant).
    final file = File(ref.absPath);
    final lines = await file.readAsLines();
    if (ref.lineIndex < 0 || ref.lineIndex >= lines.length) {
      throw _CliError('Line ${ref.lineIndex + 1} is out of range in ${ref.absPath}.');
    }
    final raw = lines[ref.lineIndex];
    final parsed = GtdParser.parseLine(
      line: raw,
      filePath: ref.absPath,
      lineNumber: ref.lineIndex,
    );
    if (parsed == null) {
      throw _CliError('Line ${ref.lineIndex + 1} is not a task line.');
    }
    final newStatus = TaskStatus.fromMarker(_newMarker);
    final newLine = await TaskWriter().setStatus(parsed, newStatus);
    if (newLine == null) {
      throw _CliError('Could not update — file changed between read and write.');
    }
    print('${_colored('✓', '32', color)} ${rest.first}');
    print('  $newLine');
    return 0;
  }
}

// ============== scan ==============

// ============== reschedule ==============

class RescheduleCommand extends Command<int> {
  @override
  String get name => 'reschedule';

  @override
  String get description =>
      'Set, change, or clear a task\'s due date.';

  @override
  String get invocation =>
      'agenda reschedule <file>:<line> <when>\n'
      '  where <when> is one of: YYYY-MM-DD, today, tomorrow,\n'
      '  +Nd (N days from today), +Nw (N weeks from today), clear';

  @override
  Future<int> run() async {
    final vault = _resolveVault(globalResults);
    final color = _useColor(globalResults);
    final rest = argResults?.rest ?? const [];
    if (rest.length != 2) {
      throw _CliError('Expected: reschedule <file>:<line> <when>');
    }
    final ref = _resolveRef(rest[0], vault);
    final when = rest[1];

    DateTime? target;
    final today = _today();
    if (when == 'clear' || when == 'none') {
      target = null;
    } else if (when == 'today') {
      target = today;
    } else if (when == 'tomorrow') {
      target = today.add(const Duration(days: 1));
    } else {
      final relMatch = RegExp(r'^\+(\d+)([dw])$').firstMatch(when);
      if (relMatch != null) {
        final n = int.parse(relMatch.group(1)!);
        final unit = relMatch.group(2)!;
        target = today.add(Duration(days: unit == 'w' ? n * 7 : n));
      } else {
        target = DateTime.tryParse(when);
        if (target == null) {
          throw _CliError(
            'Invalid <when>: $when. Use YYYY-MM-DD, today, tomorrow, +Nd, +Nw, or clear.',
          );
        }
      }
    }

    final file = File(ref.absPath);
    final lines = await file.readAsLines();
    if (ref.lineIndex < 0 || ref.lineIndex >= lines.length) {
      throw _CliError('Line ${ref.lineIndex + 1} out of range.');
    }
    final raw = lines[ref.lineIndex];
    final parsed = GtdParser.parseLine(
      line: raw,
      filePath: ref.absPath,
      lineNumber: ref.lineIndex,
    );
    if (parsed == null) {
      throw _CliError('Line ${ref.lineIndex + 1} is not a task line.');
    }
    final newLine = await TaskWriter().setDueDate(parsed, target);
    if (newLine == null) {
      throw _CliError('Could not update — file changed between read and write.');
    }
    print('${_colored('✓', '32', color)} ${rest[0]} → '
        '${target == null ? '(no date)' : DateFormat('yyyy-MM-dd').format(target)}');
    print('  $newLine');
    return 0;
  }
}

// ============== config ==============

class ConfigCommand extends Command<int> {
  @override
  String get name => 'config';

  @override
  String get description =>
      'Read or write the on-disk CLI config (~/.config/obsidian-agenda/config).';

  ConfigCommand() {
    addSubcommand(_ConfigGet());
    addSubcommand(_ConfigSet());
    addSubcommand(_ConfigPathSub());
    addSubcommand(_ConfigShow());
  }
}

class _ConfigGet extends Command<int> {
  @override
  String get name => 'get';
  @override
  String get description => 'Print the stored value of a key (e.g. `vault`).';
  @override
  String get invocation => 'agenda config get <key>';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const [];
    if (rest.length != 1) throw _CliError('Expected exactly one key.');
    final v = _readConfig()[rest.first];
    if (v == null) {
      stderr.writeln('(unset)');
      return 1;
    }
    print(v);
    return 0;
  }
}

class _ConfigSet extends Command<int> {
  @override
  String get name => 'set';
  @override
  String get description =>
      'Store a key=value pair. Common keys: vault.';
  @override
  String get invocation => 'agenda config set <key> <value>';

  @override
  Future<int> run() async {
    final color = _useColor(globalResults);
    final rest = argResults?.rest ?? const [];
    if (rest.length != 2) {
      throw _CliError('Expected: config set <key> <value>');
    }
    final key = rest[0];
    final value = rest[1];

    // Friendly validation for known keys.
    if (key == 'vault' && !Directory(value).existsSync()) {
      throw _CliError('Vault folder does not exist: $value');
    }

    final cfg = Map<String, String>.from(_readConfig());
    cfg[key] = value;
    _writeConfig(cfg);
    print('${_colored('✓', '32', color)} $key = $value');
    print('  ${_colored('(saved to ${_configPath()})', '90', color)}');
    return 0;
  }
}

class _ConfigPathSub extends Command<int> {
  @override
  String get name => 'path';
  @override
  String get description => 'Print the path to the config file.';

  @override
  Future<int> run() async {
    print(_configPath());
    return 0;
  }
}

class _ConfigShow extends Command<int> {
  @override
  String get name => 'show';
  @override
  String get description => 'Print every key/value currently stored.';

  @override
  Future<int> run() async {
    final cfg = _readConfig();
    if (cfg.isEmpty) {
      stderr.writeln('(empty — config file: ${_configPath()})');
      return 0;
    }
    final keys = cfg.keys.toList()..sort();
    for (final k in keys) {
      print('$k=${cfg[k]}');
    }
    return 0;
  }
}

class ScanCommand extends Command<int> {
  @override
  String get name => 'scan';

  @override
  String get description => 'Summarise the vault — file count, totals, errors.';

  @override
  Future<int> run() async {
    final vault = _resolveVault(globalResults);
    final color = _useColor(globalResults);
    final res = await VaultService().loadVault(vault);
    final open = res.tasks.where((t) => !t.isDone).length;
    final done = res.tasks.length - open;
    final overdue = res.tasks
        .where((t) =>
            !t.isDone &&
            t.dueDate != null &&
            t.dueDate!.isBefore(_today()))
        .length;

    print('${_colored('vault', '1', color)}   $vault');
    print('files   ${res.fileCount}');
    print('tasks   ${res.tasks.length}  (${_colored('$open open', '34', color)} · $done done)');
    print('overdue ${_colored('$overdue', '31', color)}');
    if (res.errors.isNotEmpty) {
      print(_colored('\n${res.errors.length} parse errors:', '31', color));
      for (final e in res.errors) {
        print('  $e');
      }
    }
    return 0;
  }
}
