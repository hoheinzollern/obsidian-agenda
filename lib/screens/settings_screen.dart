import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/settings_service.dart';
import '../services/widget_service.dart';
import '../widgets/android_folder_picker.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = SettingsService();
  final _widget = WidgetService();
  final _controller = TextEditingController();
  String? _savedPath;
  bool _loading = true;
  bool _useAdvancedUri = false;
  int _widgetOpacity = 90;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await _settings.getVaultPath();
    final adv = await _settings.getUseAdvancedUri();
    final op = await _settings.getWidgetOpacity();
    if (!mounted) return;
    setState(() {
      _savedPath = p;
      _controller.text = p ?? _suggestedDefault();
      _useAdvancedUri = adv;
      _widgetOpacity = op;
      _loading = false;
    });
  }

  String _suggestedDefault() {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/obsidian-experiment';
    }
    return '${Platform.environment['HOME'] ?? '/'}/obsidian-experiment';
  }

  Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'All-files access denied. Grant it in system settings to read/write '
            'your vault.',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  // The folder picker is available on every platform; Android uses our
  // dart:io browser, the others use the OS-native NSOpenPanel /
  // GtkFileChooser via file_selector.
  bool get _nativePickerSupported => true;

  Future<void> _pickFolder() async {
    final String? path = Platform.isAndroid
        ? await pickAndroidFolder(
            context,
            startPath: _controller.text.trim().isNotEmpty
                ? _controller.text.trim()
                : '/storage/emulated/0',
          )
        : await getDirectoryPath(
            confirmButtonText: 'Use this vault',
            initialDirectory: _controller.text.trim().isNotEmpty
                ? _controller.text.trim()
                : null,
          );
    if (path == null || !mounted) return;
    setState(() {
      _controller.text = path;
      _validationError = null;
    });
  }

  Future<void> _save() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _validationError = 'Path is required');
      return;
    }
    final granted = await _ensurePermission();
    if (!granted) return;

    final dir = Directory(raw);
    if (!await dir.exists()) {
      if (!mounted) return;
      setState(() => _validationError =
          'Folder does not exist (or app cannot see it yet). Granted permissions?');
      return;
    }
    await _settings.setVaultPath(raw);
    if (!mounted) return;
    setState(() {
      _savedPath = raw;
      _validationError = null;
    });
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Vault folder',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: '/storage/emulated/0/obsidian-experiment',
                          errorText: _validationError,
                        ),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        maxLines: 2,
                        minLines: 1,
                      ),
                    ),
                    if (_nativePickerSupported) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _pickFolder,
                        icon: const Icon(Icons.folder_open),
                        tooltip: 'Choose folder…',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _savedPath == null
                      ? 'No vault saved yet.'
                      : 'Saved: $_savedPath',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: const Text('Save'),
                ),
                const Divider(height: 32),
                SwitchListTile(
                  title: const Text('Line-precise Obsidian navigation'),
                  subtitle: const Text(
                    'Use obsidian://advanced-uri to jump to the task\'s exact '
                    'line. Requires the Advanced URI community plugin to be '
                    'installed and enabled in Obsidian.',
                  ),
                  value: _useAdvancedUri,
                  onChanged: (v) async {
                    await _settings.setUseAdvancedUri(v);
                    // Mirror the flag into the widget's SharedPreferences
                    // so an external Obsidian launch from the widget
                    // picks up the new behaviour immediately.
                    await _widget.setUseAdvancedUri(v);
                    if (!mounted) return;
                    setState(() => _useAdvancedUri = v);
                  },
                ),
                if (Platform.isAndroid) ...[
                  const Divider(height: 32),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Android widget translucency'),
                    subtitle: Text(
                      _widgetOpacity == 100
                          ? 'Opaque panel'
                          : _widgetOpacity == 0
                              ? 'Fully transparent (text only)'
                              : '$_widgetOpacity% opaque',
                    ),
                  ),
                  Slider(
                    value: _widgetOpacity.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '$_widgetOpacity%',
                    onChanged: (v) {
                      setState(() => _widgetOpacity = v.round());
                    },
                    onChangeEnd: (v) async {
                      final value = v.round();
                      await _settings.setWidgetOpacity(value);
                      await _widget.setOpacity(value);
                    },
                  ),
                ],
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Run setup wizard again'),
                  subtitle: const Text(
                    'Re-runs the four-step intro flow from a fresh state.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await _settings.setOnboardingDone(false);
                    if (!context.mounted) return;
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) => const OnboardingScreen()),
                    );
                    if (!context.mounted) return;
                    // Pop settings → dashboard re-bootstraps.
                    Navigator.of(context).pop(true);
                  },
                ),
                const Divider(height: 32),
                const Text('About the vault path',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  'Point this at the root of a folder containing your Obsidian '
                  'markdown files — e.g. the obsidian-experiment/ directory '
                  'synced onto the phone via Syncthing.\n\n'
                  'On Android 11+ the app needs "All files access" to read and '
                  'write arbitrary folders on shared storage. Tapping Save will '
                  'prompt for it the first time.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
    );
  }
}
