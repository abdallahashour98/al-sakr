import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:pocketbase/pocketbase.dart';
import 'notification_service.dart';

// عنوان السيرفر (يجب أن يكون ثابتاً هنا لأن الـ Background Isolate لا يرى متغيرات main.dart)
const String pbUrl = "http://192.168.1.24:8090";

/// دالة التهيئة الرئيسية التي تستدعى في main.dart
Future<void> initializeBackgroundService() async {
  // تهيئة الإشعارات أولاً
  await NotificationService.init();

  if (Platform.isAndroid) {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStartAndroid, // دالة البدء للأندرويد
        autoStart: true,
        isForegroundMode: true, // يظهر في شريط الإشعارات لضمان عدم قتله
        notificationChannelId: 'high_importance_channel',
        initialNotificationTitle: 'نظام الصقر',
        initialNotificationContent: 'خدمة الإشعارات تعمل في الخلفية...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStartAndroid,
      ),
    );
    await service.startService();
  } else {
    // للويندوز واللينكس: لا نحتاج Background Service معقدة
    // لأن التطبيق عادة يعمل كنافذة مفتوحة. سنشغل الاستماع مباشرة.
    startDesktopListener();
  }
}

// =======================
// Android Background Logic
// =======================
@pragma('vm:entry-point')
void onStartAndroid(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // نعيد تهيئة الإشعارات داخل الـ Isolate
  await NotificationService.init();

  print("🤖 Android Background Service Started");

  // الاتصال بـ PocketBase (اتصال مستقل)
  final pb = PocketBase(pbUrl);

  // الاستماع لجدول الإشعارات (notifications)
  _subscribeToNotifications(pb);

  // الاستماع لجدول التعميمات (announcements) إذا أردت
  _subscribeToAnnouncements(pb);
}

// =======================
// Desktop Listener Logic
// =======================
void startDesktopListener() {
  print("🖥️ Desktop Listener Started");
  final pb = PocketBase(pbUrl);

  _subscribeToNotifications(pb);
  _subscribeToAnnouncements(pb);
}

// =======================
// Shared Logic (Subscription)
// =======================
void _subscribeToNotifications(PocketBase pb) {
  pb.collection('notifications').subscribe('*', (e) {
    if (e.action == 'create') {
      final data = e.record?.data;
      if (data != null) {
        NotificationService.showNotification(
          title: data['title'] ?? 'إشعار جديد',
          body: data['body'] ?? '...',
        );
      }
    }
  });
}

void _subscribeToAnnouncements(PocketBase pb) {
  pb.collection('announcements').subscribe('*', (e) {
    if (e.action == 'create') {
      final data = e.record?.data;
      if (data != null) {
        // يمكنك هنا وضع شرط لفحص إذا كان المستخدم هو المستهدف
        // ولكن بما أننا في Background Isolate، قد لا نملك الـ Auth Store
        // لذا سنعرض "تعميم جديد" بشكل عام
        NotificationService.showNotification(
          title: "تعميم جديد: ${data['title']}",
          body: "يرجى مراجعة التطبيق للتفاصيل",
        );
      }
    }
  });
}
