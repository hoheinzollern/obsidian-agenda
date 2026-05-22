import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/settings_service.dart';
import '../services/widget_service.dart';
import '../widgets/android_folder_picker.dart';

/// Linear setup flow shown on first launch (and reachable from Settings).
///
/// Pages:
///   1. Welcome — what this app does.
///   2. Vault — required.
///   3. Options — Advanced URI + widget opacity (Android only).
///   4. Done — wrap-up + add-widget instructions on Android.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _settings = SettingsService();
  final _widget = WidgetService();
  final _controller = PageController();
  final _vaultController = TextEditingController();

  int _page = 0;
  String? _savedPath;
  String? _vaultError;
  bool _useAdvancedUri = false;
  int _opacity = 90;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _controller.dispose();
    _vaultController.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    final path = await _settings.getVaultPath();
    final adv = await _settings.getUseAdvancedUri();
    final op = await _settings.getWidgetOpacity();
    if (!mounted) return;
    setState(() {
      _savedPath = path;
      _vaultController.text = path ?? _suggestedDefault();
      _useAdvancedUri = adv;
      _opacity = op;
    });
  }

  String _suggestedDefault() {
    if (Platform.isAndroid) {
      return '/storage/emulated/0/obsidian-experiment';
    }
    return '${Platform.environment['HOME'] ?? '/'}/obsidian-experiment';
  }

  int get _totalPages => Platform.isAndroid ? 4 : 4;

  bool get _isLastPage => _page == _totalPages - 1;

  Future<void> _next() async {
    // Page 1 (vault) is the only one that can block progression.
    if (_page == 1 && !await _saveVault()) return;
    if (_isLastPage) {
      await _settings.setOnboardingDone(true);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _back() {
    if (_page == 0) {
      Navigator.of(context).pop(false);
      return;
    }
    _controller.previousPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Future<bool> _saveVault() async {
    final raw = _vaultController.text.trim();
    if (raw.isEmpty) {
      setState(() => _vaultError = 'A vault path is required.');
      return false;
    }
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All-files access denied.')),
          );
        }
        return false;
      }
    }
    if (!await Directory(raw).exists()) {
      setState(() => _vaultError = 'Folder does not exist.');
      return false;
    }
    await _settings.setVaultPath(raw);
    setState(() {
      _savedPath = raw;
      _vaultError = null;
    });
    return true;
  }

  Future<void> _pickVaultFolder() async {
    final String? path = Platform.isAndroid
        ? await pickAndroidFolder(
            context,
            startPath: _vaultController.text.trim().isNotEmpty
                ? _vaultController.text.trim()
                : '/storage/emulated/0',
          )
        : await getDirectoryPath(
            confirmButtonText: 'Use this vault',
            initialDirectory: _vaultController.text.trim().isNotEmpty
                ? _vaultController.text.trim()
                : null,
          );
    if (path == null || !mounted) return;
    setState(() {
      _vaultController.text = path;
      _vaultError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(),
                  _VaultPage(
                    controller: _vaultController,
                    error: _vaultError,
                    savedPath: _savedPath,
                    onPick: _nativeFolderPickerSupported ? _pickVaultFolder : null,
                  ),
                  _OptionsPage(
                    useAdvancedUri: _useAdvancedUri,
                    onAdvancedChanged: (v) async {
                      await _settings.setUseAdvancedUri(v);
                      await _widget.setUseAdvancedUri(v);
                      setState(() => _useAdvancedUri = v);
                    },
                    opacity: _opacity,
                    onOpacityChanged: (v) {
                      setState(() => _opacity = v.round());
                    },
                    onOpacityChangeEnd: (v) async {
                      final value = v.round();
                      await _settings.setWidgetOpacity(value);
                      await _widget.setOpacity(value);
                    },
                  ),
                  const _DonePage(),
                ],
              ),
            ),
            _Footer(
              page: _page,
              totalPages: _totalPages,
              onBack: _back,
              onNext: _next,
              nextLabel: _isLastPage ? 'Open dashboard' : 'Continue',
            ),
          ],
        ),
      ),
    );
  }

  bool get _nativeFolderPickerSupported => true;
}

// ============== pages ==============

class _WelcomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: const Color(0xFFF5EFE2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.checklist,
                size: 48, color: Color(0xFF00695C)),
          ),
          const SizedBox(height: 24),
          Text('Obsidian Agenda',
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            'A fast org-agenda dashboard for the tasks already in your '
            'Obsidian vault. Local-only, reads and writes the .md files '
            'directly.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          for (final entry in const [
            ('⚠️', 'Overdue · Today · Week · Next 30 — at a glance'),
            ('☑️', 'Tap to mark done, long-press for full state'),
            ('🔗', 'Tap a task to jump straight into Obsidian'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.$1, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(entry.$2, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VaultPage extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final String? savedPath;
  final VoidCallback? onPick;
  const _VaultPage({
    required this.controller,
    required this.error,
    required this.savedPath,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Where's your vault?",
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            Platform.isAndroid
                ? 'Point this at the folder where your Obsidian vault lives '
                    'on the phone. Typically it\'s the directory Syncthing or '
                    'Obsidian Sync writes to under shared storage.'
                : 'Pick the root of your Obsidian vault on this machine.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '/path/to/vault',
                    errorText: error,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  maxLines: 2,
                  minLines: 1,
                ),
              ),
              if (onPick != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onPick,
                  icon: const Icon(Icons.folder_open),
                  tooltip: 'Choose folder…',
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (savedPath != null)
            Text('Currently saved: $savedPath',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontFamily: 'monospace',
                )),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'On the next step Android will ask for "All files '
                      'access" so the app can read & write inside the vault.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionsPage extends StatelessWidget {
  final bool useAdvancedUri;
  final ValueChanged<bool> onAdvancedChanged;
  final int opacity;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onOpacityChangeEnd;

  const _OptionsPage({
    required this.useAdvancedUri,
    required this.onAdvancedChanged,
    required this.opacity,
    required this.onOpacityChanged,
    required this.onOpacityChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      children: [
        Text('Options',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          'You can change these later in Settings.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Line-precise Obsidian navigation'),
          subtitle: const Text(
            'Tap a task → jumps to the exact line in Obsidian. Requires the '
            'Advanced URI community plugin.',
          ),
          value: useAdvancedUri,
          onChanged: onAdvancedChanged,
        ),
        if (Platform.isAndroid) ...[
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Android widget translucency'),
            subtitle: Text(
              opacity == 100
                  ? 'Opaque panel'
                  : opacity == 0
                      ? 'Fully transparent (text only)'
                      : '$opacity% opaque',
            ),
          ),
          Slider(
            value: opacity.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            label: '$opacity%',
            onChanged: onOpacityChanged,
            onChangeEnd: onOpacityChangeEnd,
          ),
        ],
      ],
    );
  }
}

class _DonePage extends StatelessWidget {
  const _DonePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle,
              size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('All set',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text(
            'Hit "Open dashboard" and your agenda lands.',
            style: theme.textTheme.bodyLarge,
          ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.widgets_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Add the home-screen widget',
                        style: theme.textTheme.titleMedium),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Long-press the home screen → Widgets → '
                    'Obsidian Agenda. Drop it anywhere; it shows today\'s '
                    'tasks with a filter bar.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final int page;
  final int totalPages;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final String nextLabel;

  const _Footer({
    required this.page,
    required this.totalPages,
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(
        children: [
          TextButton(onPressed: onBack, child: Text(page == 0 ? 'Skip' : 'Back')),
          const Spacer(),
          Row(
            children: List.generate(totalPages, (i) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == page ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == page
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const Spacer(),
          FilledButton(onPressed: onNext, child: Text(nextLabel)),
        ],
      ),
    );
  }
}
