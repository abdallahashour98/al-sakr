import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // عشان نتجاهل الويب

import 'services/pb_helper.dart';

class UpdateService {
  final String collectionName = 'app_versions';

  Future<void> checkForUpdate(
    BuildContext context, {
    bool showNoUpdateMsg = false,
  }) async {
    // 1. لو ويب، مفيش تحديثات بتنزل، المتصفح بيحدث نفسه
    if (kIsWeb) return;

    try {
      // 2. جلب آخر إصدار
      final records = await PBHelper().pb
          .collection(collectionName)
          .getList(page: 1, perPage: 1, sort: '-created');

      if (records.items.isNotEmpty) {
        final latestData = records.items.first;

        String serverVersion = latestData.data['version'] ?? '1.0.0';
        String notes = latestData.data['release_notes'] ?? 'تحسينات عامة';
        bool isForceUpdate = latestData.data['force_update'] ?? false;

        // ✅ 3. تحديد ملف التحميل بناءً على نوع الجهاز
        String filename = "";

        if (Platform.isAndroid) {
          filename =
              latestData.data['file_android'] ??
              ''; // اسم الحقل الجديد للأندرويد
        } else if (Platform.isWindows) {
          filename =
              latestData.data['file_windows'] ??
              ''; // اسم الحقل الجديد للويندوز
        } else if (Platform.isLinux) {
          filename =
              latestData.data['file_linux'] ?? ''; // اسم الحقل الجديد للينكس
        }

        // لو مفيش ملف مرفوع للمنصة دي، نوقف هنا (عشان مايقولش في تحديث وهو مش موجود للجهاز ده)
        if (filename.isEmpty) {
          if (showNoUpdateMsg && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('لا يوجد ملف تحديث متوافق مع جهازك حالياً'),
              ),
            );
          }
          return;
        }

        // تكوين الرابط
        String downloadUrl =
            "${PBHelper().pb.baseUrl}/api/files/${latestData.collectionId}/${latestData.id}/$filename";

        // 4. معرفة إصدار التطبيق الحالي
        PackageInfo packageInfo = await PackageInfo.fromPlatform();
        String currentVersion = packageInfo.version;

        print(
          "Device: ${Platform.operatingSystem} | Current: $currentVersion | Server: $serverVersion",
        );

        // 5. المقارنة
        if (_isNewer(serverVersion, currentVersion)) {
          if (context.mounted) {
            _showUpdateDialog(
              context,
              serverVersion,
              notes,
              downloadUrl,
              isForceUpdate,
            );
          }
        } else {
          if (showNoUpdateMsg && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('البرنامج محدث لآخر إصدار ✅'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        if (showNoUpdateMsg && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد معلومات عن تحديثات مسجلة حالياً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print("Error checking update: $e");
      if (showNoUpdateMsg && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التحقق: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isNewer(String server, String current) {
    try {
      List<int> s = server.split('.').map(int.parse).toList();
      List<int> c = current.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        int sPart = i < s.length ? s[i] : 0;
        int cPart = i < c.length ? c[i] : 0;
        if (sPart > cPart) return true;
        if (sPart < cPart) return false;
      }
      return false;
    } catch (e) {
      return server != current;
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    String version,
    String notes,
    String url,
    bool isForce,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !isForce,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => !isForce,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(
                isForce ? Icons.warning_amber_rounded : Icons.system_update,
                color: isForce ? Colors.red : Colors.blue,
              ),
              const SizedBox(width: 10),
              Text(isForce ? 'تحديث إجباري مطلوب' : 'تحديث جديد متاح'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الإصدار: $version',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'أبرز التغييرات:',
                style: TextStyle(color: Colors.grey),
              ),
              Text(notes),
              const SizedBox(height: 20),
              if (isForce)
                const Text(
                  '⚠️ هذا التحديث ضروري لاستمرار عمل التطبيق.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ),
          actions: [
            if (!isForce)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('لاحقاً'),
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.download, color: Colors.white, size: 18),
              onPressed: () {
                if (!isForce) Navigator.pop(ctx);
                _launchDownloadUrl(url);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isForce ? Colors.red : Colors.blue,
              ),
              label: const Text(
                'تحميل وتثبيت',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchDownloadUrl(String url) async {
    if (url.isEmpty) return;
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }
}
