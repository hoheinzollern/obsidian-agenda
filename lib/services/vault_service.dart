import 'dart:io';

import '../models/task.dart';
import '../parser/gtd_parser.dart';

class VaultLoadResult {
  final List<Task> tasks;
  final int fileCount;
  final List<String> errors;

  VaultLoadResult({
    required this.tasks,
    required this.fileCount,
    required this.errors,
  });
}

class VaultService {
  /// Recursively scan [vaultPath] for `.md` files and parse all tasks.
  ///
  /// Skips dotfiles (e.g., `.obsidian`, `.trash`) and the `templates/` folder
  /// since template files contain placeholder tasks that aren't real.
  Future<VaultLoadResult> loadVault(String vaultPath) async {
    final root = Directory(vaultPath);
    if (!await root.exists()) {
      throw FileSystemException('Vault directory not found', vaultPath);
    }

    final tasks = <Task>[];
    final errors = <String>[];
    var fileCount = 0;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.md')) continue;
      if (_isSkipped(entity.path, vaultPath)) continue;

      fileCount++;
      try {
        tasks.addAll(await GtdParser.parseFile(entity));
      } catch (e) {
        errors.add('${entity.path}: $e');
      }
    }

    return VaultLoadResult(
      tasks: tasks,
      fileCount: fileCount,
      errors: errors,
    );
  }

  static bool _isSkipped(String path, String vaultPath) {
    final rel = path.startsWith(vaultPath)
        ? path.substring(vaultPath.length)
        : path;
    final segments = rel.split(Platform.pathSeparator);
    for (final seg in segments) {
      if (seg.startsWith('.')) return true;
      if (seg == 'templates') return true;
    }
    return false;
  }
}
