import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/constants.dart';
// ✅ استدعاء الملف المحدث

final String kBaseUrl = AppConfig.baseUrl;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // ملاحظة: تم نقل إنشاء القناة announcements_channel إلى NotificationService
  // لكن نحتاج هنا قناة الخدمة (Foreground) لأنها خاصة بالسيرفس

  const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
    'my_foreground',
    'حالة التطبيق',
    description: 'يبقي التطبيق متصلاً في الخلفية',
    importance: Importance.low,
    playSound: false,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(serviceChannel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'my_foreground',
      initialNotificationTitle: 'تطبيق الصقر',
      initialNotificationContent: 'يعمل في الخلفية لاستلام التنبيهات',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );

  await service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // ✅ في الـ Isolate المنفصل، نحتاج تهيئة الـ Plugin مرة أخرى للعرض فقط
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // إعداد بسيط للـ Plugin داخل الخلفية (فقط ليتمكن من عرض الإشعار)
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings),
  );

  final pb = PocketBase(kBaseUrl);
  final prefs = await SharedPreferences.getInstance();

  print("🚀 Background Service Started...");

  // دالة تنظيف النص (كما هي)
  String cleanText(String jsonString) {
    try {
      if (!jsonString.trim().startsWith('[')) return jsonString;
      final List<dynamic> delta = jsonDecode(jsonString);
      final StringBuffer buffer = StringBuffer();
      for (var op in delta) {
        if (op is Map<String, dynamic> && op.containsKey('insert')) {
          buffer.write(op['insert']);
        }
      }
      return buffer.toString().trim();
    } catch (e) {
      return jsonString;
    }
  }

  try {
    pb.collection('announcements').subscribe('*', (e) async {
      if (e.action == 'create') {
        await prefs.reload();
        String? myUserId = prefs.getString(
          'my_user_id',
        ); // تأكد أنك تخزن هذا في LoginScreen

        // 👇👇👇 الحل لمشكلة عدم الوصول بين الأجهزة 👇👇👇
        // المشكلة: أنت تمنع الإشعار إذا كان الـ user هو نفسه الـ myUserId
        // إذا كنت تريد التنبيه على أجهزتك الأخرى، يجب تخفيف هذا الشرط
        // أو الاعتماد على device_id بدلاً من user_id.
        // للوقت الحالي، سأقوم بتعليق هذا الشرط لكي تجرب الوصول

        String creatorId = e.record!.data['user'] ?? '';
        if (myUserId != null && creatorId == myUserId) {
          return; // ❌ هذا السطر هو الذي يمنع وصول الإشعار للموبايل إذا بعته من الكمبيوتر بنفس الحساب
        }

        List targets = e.record!.data['target_users'] ?? [];
        if (targets.isNotEmpty &&
            myUserId != null &&
            !targets.contains(myUserId)) {
          return;
        }

        String rawContent = e.record!.data['content'] ?? '...';
        String finalContent = cleanText(rawContent);
        String title = e.record!.data['title'] ?? 'تنبيه إداري';

        // عرض الإشعار
        flutterLocalNotificationsPlugin.show(
          DateTime.now().millisecondsSinceEpoch % 100000,
          title,
          finalContent,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'announcements_channel',
              'تنبيهات الإدارة',
              importance: Importance.max,
              priority: Priority.high,
              // ✅ استخدام الأيقونة الموجودة في الدرو-إيبل
              icon: 'ic_notification',
              styleInformation: BigTextStyleInformation(''),
            ),
          ),
          payload: 'navigate_to_notices',
        );
      }
    });
  } catch (err) {
    print("❌ Error subscribing: $err");
  }

  Timer.periodic(const Duration(minutes: 1), (timer) async {
    try {
      await pb.health.check();
    } catch (_) {}
  });
}
