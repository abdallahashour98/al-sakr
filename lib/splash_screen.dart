import 'dart:async';
import 'package:al_sakr/services/sales_service.dart';
import 'package:flutter/material.dart';
import 'dashboard.dart'; // تأكد أن ملف الداشبورد موجود
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // دالة للتحقق من حالة الدخول
  void _checkLoginStatus() {
    // ننتظر 3 ثواني عشان اللوجو يظهر للمستخدم
    Timer(const Duration(seconds: 3), () {
      if (!mounted) return;

      // ✅ هنا الفحص السحري:
      // PBHelper بيحمل التوكن من SharedPreferences أوتوماتيك في main.dart
      // فاحنا بس بنسأله: هل التوكن ده لسه شغال؟
      bool isLoggedIn = SalesService().pb.authStore.isValid;

      if (isLoggedIn) {
        // لو مسجل دخول، روح للداشبورد علطول
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const DashboardScreen()),
        );
      } else {
        // لو مش مسجل، روح لشاشة اللوجين
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // اللوجو
            Image.asset('assets/splash_logo.png', width: 250, height: 250),
            const SizedBox(height: 20),

            // مؤشر التحميل
            const CircularProgressIndicator(color: Colors.teal),
          ],
        ),
      ),
    );
  }
}
