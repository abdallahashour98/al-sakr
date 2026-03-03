import 'dart:io';
import 'package:flutter/foundation.dart'; // عشان kIsWeb

class AppConfig {
  // ============================================================
  // 🎚️ مفتاح التبديل (Switch)
  // ============================================================

  // اجعل هذه القيمة true لاستخدام السيرفر الحقيقي (Production)
  // اجعلها false لاستخدام سيرفر التطوير المحلي (Development)
  static const bool isProduction = true;

  // ============================================================
  // 🌍 1. إعدادات السيرفر الحقيقي (Online / Production)
  // ============================================================

  // الرابط الكامل للسيرفر الخارجي
  static const String productionUrl = "http://company-system.ddns.net:8090";

  // ============================================================
  // 💻 2. إعدادات سيرفر التطوير (Local / Development)
  // ============================================================

  // ⚠️ هام: ضع هنا IP جهاز الكمبيوتر الخاص بك (من إعدادات الواي فاي)
  static const String devServerIp = "192.168.1.9";

  // المنفذ (Port)
  static const String devPort = "8090";

  // ============================================================
  // 🔗 3. الدالة الذكية لتحديد الرابط (Base URL Logic)
  // ============================================================

  static String get baseUrl {
    // 🅰️ الحالة الأولى: لو شغالين Production (السيرفر الحقيقي)
    if (isProduction) {
      return productionUrl;
    }

    // 🅱️ الحالة الثانية: لو شغالين Development (السيرفر المحلي)

    // 1. لو ويب (Web)
    if (kIsWeb) return "http://127.0.0.1:$devPort";

    // 2. لو أندرويد (Android)
    if (Platform.isAndroid) {
      // لو محاكي (Emulator) نستخدم 10.0.2.2
      // return "http://10.0.2.2:$devPort";

      // لو موبايل حقيقي نستخدم IP الكمبيوتر
      return "http://$devServerIp:$devPort";
    }

    // 3. لو ويندوز أو لينكس (Desktop)
    return "http://127.0.0.1:$devPort";
  }

  // ============================================================
  // 🛡️ 4. الثوابت الإدارية (Admin Constants)
  // ============================================================

  // الآيدي الخاص بالسوبر أدمن (أنت)
  static const String superAdminId = "1sxo74splxbw1yh";

  // النطاق الثابت للإيميلات
  static const String emailDomain = "@alsakr.com";
}
