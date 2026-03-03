import 'dart:async';
import 'dart:io';
import 'package:al_sakr/splash_screen.dart'; // تأكد من المسار
import 'package:al_sakr/notices_screen.dart'; // ✅ تأكد من استيراد هذا الملف
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // ✅ تمت الإضافة
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/pb_helper.dart';
import 'services/notice_service.dart';
import 'login_screen.dart';
import 'notification_service.dart';
import 'background_listener.dart';

import 'services/settings_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en'));

// ✅ دالة موحدة للتعامل مع الضغط على الإشعار
void onNotificationTap(NotificationResponse details) {
  if (details.payload == 'navigate_to_notices') {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (context) => const NoticesScreen()),
      );
    }
  }
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final settings = SettingsService();
      final savedTheme = await settings.getThemeMode();
      themeNotifier.value = savedTheme;

      // 2. تحميل اللغة
      final savedLocale = await settings.getLocale();
      localeNotifier.value = savedLocale;

      try {
        await NotificationService.init(
          requestPermission: true, // نطلب الصلاحية هنا
          onNotificationTap: onNotificationTap,
        );

        if (Platform.isAndroid) await Permission.notification.request();

        // 2. تهيئة PBHelper وتمرير دالة التوجيه أيضاً لضمان عدم مسحها
        await PBHelper.init(onNotificationTap: onNotificationTap);

        if (Platform.isAndroid || Platform.isIOS) {
          // 📱 للموبايل: شغل خدمة الخلفية فقط
          await initializeService();
        } else {
          // 💻 للكمبيوتر: شغل المستمع العادي فقط
          NoticeService().startListeningToAnnouncements();
        }
      } catch (e) {
        print("Error in main: $e");
      }
      runApp(const AlSakrApp());
    },
    (error, stack) {
      print("Zoned Error: $error");
    },
  );
}

class AlSakrApp extends StatelessWidget {
  const AlSakrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentTheme, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: localeNotifier,
          builder: (context, currentLocale, _) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Al Sakr',
              debugShowCheckedModeBanner: false,
              supportedLocales: const [Locale('ar'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              locale: currentLocale,
              themeMode: currentTheme,
              theme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: Colors.blue,
                brightness: Brightness.light,
                fontFamily: 'Cairo',
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorSchemeSeed: Colors.blue,
                brightness: Brightness.dark,
                fontFamily: 'Cairo',
              ),
              home: const ConnectionCheckWrapper(),
            );
          },
        );
      },
    );
  }
}

class ConnectionCheckWrapper extends StatefulWidget {
  const ConnectionCheckWrapper({super.key});

  @override
  State<ConnectionCheckWrapper> createState() => _ConnectionCheckWrapperState();
}

class _ConnectionCheckWrapperState extends State<ConnectionCheckWrapper> {
  bool _isConnected = false;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  Future<void> _checkServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // مهلة 5 ثواني للاتصال
      final health = await PBHelper().pb.health.check().timeout(
        const Duration(seconds: 5),
      );

      if (health.code == 200) {
        // ✅ هام جداً: عند إعادة التهيئة، نمرر دالة التوجيه مرة أخرى
        // لكي لا يتم استبدالها بـ null ويتوقف التوجيه عن العمل
        await PBHelper.init(onNotificationTap: onNotificationTap);
        // فحص هل تم فتح التطبيق من إشعار (والتطبيق مغلق تماماً)
        bool launchedFromNotification = false;
        if (Platform.isAndroid || Platform.isIOS) {
          launchedFromNotification =
              await NotificationService.didAppLaunchFromNotification();
        }

        if (mounted) {
          setState(() {
            _isConnected = true;
            _isLoading = false;
          });

          // التوجيه إذا كان التطبيق مفتوحاً بسبب إشعار
          if (launchedFromNotification && PBHelper().isLoggedIn) {
            // تأخير بسيط لضمان بناء الواجهة
            Future.delayed(const Duration(milliseconds: 500), () {
              navigatorKey.currentState?.push(
                MaterialPageRoute(builder: (context) => const NoticesScreen()),
              );
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isLoading = false;
          _errorMessage = "تعذر الاتصال بالسيرفر: $e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                "جاري الاتصال بالنظام...",
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isConnected) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 80, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  "فشل الاتصال بالسيرفر",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _checkServer,
                  icon: const Icon(Icons.refresh),
                  label: const Text("إعادة المحاولة"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // الانتقال للشاشة المناسبة
    return PBHelper().isLoggedIn ? const SplashScreen() : const LoginScreen();
  }
}
