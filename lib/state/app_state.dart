import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repositories/settings_repository.dart';
import '../data/seed_data.dart';

/// 全局设置与数据变更通知。
///
/// [revision] 在任意数据增删改后自增，页面通过 watch 它来刷新列表。
class AppState extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.dark;
  int lowStockThreshold = 10;
  String lcscApiKey = '';
  int lastLocationId = kUnassignedLocationId;
  int revision = 0;

  bool _loaded = false;

  bool get loaded => _loaded;

  Future<void> load() async {
    themeMode = _parseThemeMode(
      await SettingsRepository.get(SettingsRepository.keyThemeMode),
    );
    final threshold = await SettingsRepository.get(
      SettingsRepository.keyLowStockThreshold,
    );
    lowStockThreshold = int.tryParse(threshold ?? '') ?? 10;
    lcscApiKey = await SettingsRepository.get(
          SettingsRepository.keyLcscApiKey,
        ) ??
        '';
    final lastLocation = await SettingsRepository.get(
      SettingsRepository.keyLastLocationId,
    );
    lastLocationId =
        int.tryParse(lastLocation ?? '') ?? kUnassignedLocationId;
    _loaded = true;
    notifyListeners();
  }

  static ThemeMode _parseThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  static String themeModeKey(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.dark:
        return 'dark';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await SettingsRepository.set(
      SettingsRepository.keyThemeMode,
      themeModeKey(mode),
    );
  }

  Future<void> setLowStockThreshold(int value) async {
    lowStockThreshold = value;
    notifyListeners();
    await SettingsRepository.set(
      SettingsRepository.keyLowStockThreshold,
      value.toString(),
    );
  }

  Future<void> setLcscApiKey(String value) async {
    lcscApiKey = value.trim();
    notifyListeners();
    await SettingsRepository.set(
      SettingsRepository.keyLcscApiKey,
      lcscApiKey,
    );
  }

  Future<void> setLastLocationId(int value) async {
    lastLocationId = value;
    await SettingsRepository.set(
      SettingsRepository.keyLastLocationId,
      value.toString(),
    );
  }

  /// 数据发生变更，通知所有监听页面刷新。
  void notifyDataChanged() {
    revision++;
    notifyListeners();
  }

  double thresholdFor(MaterialItem item) =>
      item.lowStockThreshold ?? lowStockThreshold.toDouble();

  bool isLowStock(MaterialItem item) =>
      item.qtyRemaining <= thresholdFor(item);
}
