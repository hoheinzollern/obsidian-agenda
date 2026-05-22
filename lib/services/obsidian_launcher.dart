import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/task.dart';

/// Opens an Obsidian note via the `obsidian://` URI scheme.
///
/// The vault must be registered in Obsidian under the basename of
/// [vaultPath] — e.g. if the path is `/Users/brun/Projects/gtd/obsidian-experiment`,
/// Obsidian needs to know that folder as a vault named `obsidian-experiment`.
///
/// Line navigation requires the Advanced URI community plugin. If installed,
/// pass `useAdvancedUri: true` (see SettingsService) and we use that scheme;
/// otherwise we fall back to the built-in `obsidian://open` which jumps to
/// the closest heading above the task.
class ObsidianLauncher {
  Future<bool> openTask(
    Task task, {
    required String vaultPath,
    bool useAdvancedUri = false,
    String? heading,
  }) {
    final vaultName = p.basename(vaultPath);
    final relPath = p.relative(task.filePath, from: vaultPath);
    // Obsidian wants the file path without the .md extension.
    final relPathNoExt =
        relPath.endsWith('.md') ? relPath.substring(0, relPath.length - 3) : relPath;

    final Uri uri;
    if (useAdvancedUri) {
      uri = Uri(
        scheme: 'obsidian',
        host: 'advanced-uri',
        queryParameters: {
          'vault': vaultName,
          'filepath': relPath,
          'line': '${task.lineNumber + 1}', // 1-based for Advanced URI.
        },
      );
    } else {
      uri = Uri(
        scheme: 'obsidian',
        host: 'open',
        queryParameters: {
          'vault': vaultName,
          'file': relPathNoExt,
          if (heading != null) 'heading': heading,
        },
      );
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
