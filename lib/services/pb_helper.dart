import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

class PBHelper {
  // Singleton Pattern
  static final PBHelper _instance = PBHelper._internal();
  factory PBHelper() => _instance;

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // متغير لتتبع حالة التهيئة (الإصلاح رقم 1)
  static bool _isInitialized = false;

  PocketBase pb = PocketBase(AppConfig.baseUrl);

  // Constructor خاص
  PBHelper._internal();

  // ============================================================
  // 🚀 1. التهيئة (Initialization)
  // ============================================================
  static Future<void> init({
    bool requestPermission = false,
    Function(NotificationResponse)? onNotificationTap,
  }) async {
    // ✅ الإصلاح رقم 1: منع التكرار
    if (_isInitialized) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. إعداد مخزن المصادقة
    final store = AsyncAuthStore(
      save: (String data) async => await prefs.setString('pb_auth', data),
      initial: prefs.getString('pb_auth'),
    );

    // 2. تهيئة PocketBase
    PBHelper().pb = PocketBase(AppConfig.baseUrl, authStore: store);

    // 3. إعدادات الإشعارات

    // ✅ الإصلاح رقم 2: توحيد اسم الأيقونة (تأكد أن الصورة موجودة في drawable)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('notification_icon');

    final LinuxInitializationSettings linuxSettings =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    // ❌ تم إزالة إعدادات الويندوز من هنا لحل مشكلة الـ Build

    final InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
      // ❌ تم إزالة ربط الويندوز من هنا
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
    );

    // طلب الصلاحيات
    if (requestPermission && Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    // ✅ وضع علامة أن التهيئة تمت
    _isInitialized = true;
  }

  // ============================================================
  // 🖼️ 2. دوال مساعدة عامة (Helpers)
  // ============================================================

  bool get isLoggedIn => pb.authStore.isValid;

  String getImageUrl(String collectionId, String recordId, String filename) {
    if (filename.isEmpty) return '';
    return '${AppConfig.baseUrl}/api/files/$collectionId/$recordId/$filename';
  }

  static Map<String, dynamic> recordToMap(RecordModel record) {
    var data = Map<String, dynamic>.from(record.data);
    data['id'] = record.id;
    data['collectionId'] = record.collectionId;
    data['created'] = record.created;
    data['updated'] = record.updated;

    if (record.expand.isNotEmpty) {
      if (record.expand.containsKey('supplier')) {
        data['supplierName'] = record.expand['supplier']?.first.data['name'];
      }
      if (record.expand.containsKey('client')) {
        data['clientName'] = record.expand['client']?.first.data['name'];
      }
      if (record.expand.containsKey('product')) {
        data['productName'] = record.expand['product']?.first.data['name'];
      }
      if (record.expand.containsKey('user')) {
        data['userName'] = record.expand['user']?.first.data['name'];
      }
      if (record.expand.containsKey('seen_by')) {
        final users = record.expand['seen_by'];
        if (users != null && users.isNotEmpty) {
          data['seen_by_names'] = users.map((u) => u.data['name']).toList();
        }
      }
    }
    return data;
  }

  // ============================================================
  // ⚡ 3. البيانات الحية (Real-time Stream) - النسخة المحسنة
  // ============================================================
  Stream<List<Map<String, dynamic>>> getCollectionStream(
    String collectionName, {
    String sort = '-created',
    String? expand,
    String? filter,
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    // دالة لجلب البيانات
    Future<void> fetchData() async {
      try {
        if (controller.isClosed) return;
        final records = await pb
            .collection(collectionName)
            .getFullList(sort: sort, expand: expand, filter: filter);

        if (!controller.isClosed) {
          final data = records.map((r) => recordToMap(r)).toList();
          controller.add(data);
        }
      } catch (e) {
        print("⚠️ Error fetching stream data ($collectionName): $e");
      }
    }

    // 1. جلب البيانات فوراً
    fetchData();

    // 2. الاشتراك في التغييرات (النسخة الآمنة)
    // ✅ الإصلاح رقم 3: استخدام UnsubscribeFunc لعدم فصل باقي الشاشات
    UnsubscribeFunc? unsubscribeFunc;

    pb
        .collection(collectionName)
        .subscribe('*', (e) {
          if (!controller.isClosed) {
            fetchData();
          }
        })
        .then((func) {
          unsubscribeFunc = func;
        })
        .catchError((e) {
          print("⚠️ Realtime error ($collectionName): $e");
        });

    controller.onCancel = () async {
      try {
        // نستخدم دالة الإلغاء الخاصة بهذا الاشتراك فقط
        if (unsubscribeFunc != null) {
          await unsubscribeFunc!();
        } else {
          // كحل بديل فقط لو فشل الاشتراك الأول
          // await pb.collection(collectionName).unsubscribe('*');
        }
      } catch (_) {}
      controller.close();
    };

    return controller.stream;
  }

  // ============================================================
  // 🔔 4. الإشعارات المحلية (Notifications)
  // ============================================================
  static Future<void> showNotification({
    int? id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'announcements_channel', // id القناة
          'تنبيهات الإدارة', // اسم القناة
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          // ✅ تم التأكد من توحيد الاسم هنا (notification_icon)
          icon: 'notification_icon',
        );

    const LinuxNotificationDetails linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.critical,
    );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      linux: linuxDetails,
    );
    final notificationId = id ?? DateTime.now().millisecondsSinceEpoch % 100000;

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: payload,
    );
  }

  // ============================================================
  // 🆔 5. أدوات مساعدة (Utils)
  // ============================================================
  static String generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random();
    return String.fromCharCodes(
      Iterable.generate(15, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
  }
}
