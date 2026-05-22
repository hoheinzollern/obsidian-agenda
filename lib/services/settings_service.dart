import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _vaultPathKey = 'vault_path';
  static const _useAdvancedUriKey = 'use_advanced_uri';

  Future<String?> getVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_vaultPathKey);
  }

  Future<void> setVaultPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vaultPathKey, path);
  }

  Future<void> clearVaultPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vaultPathKey);
  }

  Future<bool> getUseAdvancedUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useAdvancedUriKey) ?? false;
  }

  Future<void> setUseAdvancedUri(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useAdvancedUriKey, value);
  }

  static const _collapsedSectionsKey = 'collapsed_sections';

  Future<Set<String>> getCollapsedSections() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_collapsedSectionsKey)?.toSet() ?? <String>{};
  }

  Future<void> setCollapsedSections(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_collapsedSectionsKey, ids.toList());
  }

  static const _widgetOpacityKey = 'widget_opacity';

  Future<int> getWidgetOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_widgetOpacityKey) ?? 90;
  }

  Future<void> setWidgetOpacity(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_widgetOpacityKey, value.clamp(0, 100));
  }

  static const _onboardingDoneKey = 'onboarding_done';

  Future<bool> getOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingDoneKey) ?? false;
  }

  Future<void> setOnboardingDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingDoneKey, value);
  }
}
