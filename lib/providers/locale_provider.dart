import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/analytics_service.dart';

class LocaleProvider extends ChangeNotifier {
  static const String _key = 'app_locale';

  // Default: Traditional Chinese
  Locale _locale = const Locale('zh', 'TW');

  Locale get locale => _locale;

  static const List<Locale> supportedLocales = [
    Locale('zh', 'TW'),
    Locale('zh', 'CN'),
    Locale('en'),
  ];

  Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved == null) return;

    final parts = saved.split('_');
    final loaded = parts.length >= 2
        ? Locale(parts[0], parts[1])
        : Locale(parts[0]);

    _locale = loaded;
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final value = locale.countryCode != null
        ? '${locale.languageCode}_${locale.countryCode}'
        : locale.languageCode;
    await prefs.setString(_key, value);

    // 同步更新 Analytics 使用者語言屬性
    AnalyticsService.instance.setUserProperty('app_language', value);
  }

  String displayName(Locale locale) {
    if (locale.languageCode == 'zh' && locale.countryCode == 'TW') {
      return '繁體中文';
    } else if (locale.languageCode == 'zh' && locale.countryCode == 'CN') {
      return '简体中文';
    }
    return 'English';
  }

  String flagEmoji(Locale locale) {
    if (locale.languageCode == 'zh' && locale.countryCode == 'TW') return '🇹🇼';
    if (locale.languageCode == 'zh' && locale.countryCode == 'CN') return '🇨🇳';
    return '🇺🇸';
  }
}
