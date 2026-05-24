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

  static const _notifyEnabledKey = 'notify_daily_enabled';
  static const _notifyHourKey = 'notify_daily_hour';
  static const _notifyMinuteKey = 'notify_daily_minute';

  Future<bool> getNotifyEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notifyEnabledKey) ?? false;
  }

  Future<void> setNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifyEnabledKey, value);
  }

  Future<int> getNotifyHour() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notifyHourKey) ?? 8;
  }

  Future<int> getNotifyMinute() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_notifyMinuteKey) ?? 0;
  }

  Future<void> setNotifyTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_notifyHourKey, hour);
    await prefs.setInt(_notifyMinuteKey, minute);
  }

  static const _sortByFileKey = 'sort_by_file';

  Future<bool> getSortByFile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_sortByFileKey) ?? false;
  }

  Future<void> setSortByFile(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sortByFileKey, value);
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
