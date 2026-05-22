import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

/// Custom folder browser for Android, since file_selector's
/// getDirectoryPath() isn't supported there and SAF returns content://
/// URIs that dart:io can't operate on.
///
/// Walks the filesystem with `dart:io` directly. Works because the app
/// holds MANAGE_EXTERNAL_STORAGE. Permission is requested up-front.
Future<String?> pickAndroidFolder(
  BuildContext context, {
  String startPath = '/storage/emulated/0',
}) async {
  if (Platform.isAndroid) {
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All-files access required to browse folders.'),
          ),
        );
      }
      return null;
    }
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PickerSheet(startPath: startPath),
  );
}

class _PickerSheet extends StatefulWidget {
  final String startPath;
  const _PickerSheet({required this.startPath});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  static const _rootCandidates = [
    '/storage/emulated/0',
    '/storage/emulated/0/Documents',
    '/sdcard',
  ];

  late Directory _current;
  List<Directory> _children = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final start = Directory(widget.startPath);
    _current = start.existsSync()
        ? start
        : Directory(_rootCandidates.firstWhere(
            (p) => Directory(p).existsSync(),
            orElse: () => '/'));
    _refresh();
  }

  void _navigateTo(Directory d) {
    setState(() => _current = d);
    _refresh();
  }

  void _refresh() {
    try {
      final kids = _current
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => !p.basename(d.path).startsWith('.'))
          .toList()
        ..sort((a, b) =>
            p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _children = kids;
        _error = null;
      });
    } on FileSystemException catch (e) {
      setState(() {
        _children = const [];
        _error = 'Cannot read: ${e.message}';
      });
    }
  }

  void _up() {
    final parent = _current.parent;
    if (parent.path != _current.path) _navigateTo(parent);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canGoUp = _current.parent.path != _current.path;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: canGoUp ? _up : null,
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Parent folder',
                ),
                Expanded(
                  child: Text(
                    _current.path,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: _children.isEmpty && _error == null
                ? Center(
                    child: Text('No subfolders here.',
                        style: TextStyle(color: theme.colorScheme.outline)),
                  )
                : ListView.builder(
                    controller: controller,
                    itemCount: _children.length,
                    itemBuilder: (_, i) {
                      final dir = _children[i];
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(p.basename(dir.path)),
                        onTap: () => _navigateTo(dir),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(_current.path),
                    icon: const Icon(Icons.check),
                    label: const Text('Use this folder'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
