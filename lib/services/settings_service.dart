import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pb_helper.dart';

class SettingsService {
  final pb = PBHelper().pb;

  // ============================================================
  // 1. إعدادات الشركة (من قاعدة البيانات)
  // ============================================================

  Future<Map<String, dynamic>> getCompanySettings() async {
    try {
      final records = await pb
          .collection('settings')
          .getList(page: 1, perPage: 1);
      if (records.items.isNotEmpty) {
        return PBHelper.recordToMap(records.items.first);
      }
    } catch (e) {
      // ignore
    }
    return {};
  }

  Future<void> saveCompanySettings(Map<String, dynamic> data) async {
    try {
      final records = await pb
          .collection('settings')
          .getList(page: 1, perPage: 1);
      if (records.items.isNotEmpty) {
        await pb
            .collection('settings')
            .update(records.items.first.id, body: data);
      } else {
        await pb.collection('settings').create(body: data);
      }
    } catch (e) {
      rethrow;
    }
  }

  // ============================================================
  // 2. إعدادات التطبيق المحلية (Theme & Language) - الدوال الناقصة
  // ============================================================

  /// حفظ وضع الثيم (Dark/Light)
  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.toString());
  }

  /// استرجاع وضع الثيم
  Future<ThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString('theme_mode');

    if (saved == 'ThemeMode.dark') return ThemeMode.dark;
    if (saved == 'ThemeMode.light') return ThemeMode.light;

    return ThemeMode.system;
  }

  /// حفظ اللغة
  Future<void> saveLocale(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', languageCode);
  }

  /// استرجاع اللغة
  Future<Locale> getLocale() async {
    final prefs = await SharedPreferences.getInstance();
    String? lang = prefs.getString('app_lang');
    if (lang == 'en') return const Locale('en');
    // الافتراضي عربي
    return const Locale('ar');
  }
}
