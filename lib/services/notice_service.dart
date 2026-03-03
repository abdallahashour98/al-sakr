import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'pb_helper.dart';

class NoticeService {
  final pb = PBHelper().pb;

  // إنشاء تعميم جديد
  Future<RecordModel> createAnnouncement(
    String title,
    String content,
    String priority, {
    List<File>? files,
    List<String>? targetUserIds,
  }) async {
    final body = <String, dynamic>{
      "title": title,
      "content": content,
      "priority": priority,
      "user": pb.authStore.model.id,
    };

    if (targetUserIds != null) {
      body["target_users"] = targetUserIds;
    }

    if (files != null && files.isNotEmpty) {
      return await pb
          .collection('announcements')
          .create(
            body: body,
            files: files
                .map(
                  (e) => http.MultipartFile.fromBytes(
                    'image',
                    e.readAsBytesSync(),
                    filename: e.path.split('/').last,
                  ),
                )
                .toList(),
          );
    } else {
      return await pb.collection('announcements').create(body: body);
    }
  }

  Future<void> updateAnnouncement(
    String id,
    String title,
    String content,
    String priority, {
    List<String>? targetUserIds,
  }) async {
    final body = <String, dynamic>{
      "title": title,
      "content": content,
      "priority": priority,
      if (targetUserIds != null) "target_users": targetUserIds,
    };
    await pb.collection('announcements').update(id, body: body);
  }

  Future<void> deleteAnnouncement(String id) async {
    await pb.collection('announcements').delete(id);
  }

  Future<void> markAnnouncementAsSeen(String id) async {
    final userId = pb.authStore.record!.id;
    await pb.collection('announcements').update(id, body: {'seen_by+': userId});
  }

  Future<List<RecordModel>> getUsersNoticesScreen() async {
    return await pb.collection('users').getFullList();
  }

  // --- العداد (Unread Count) ---

  Stream<int> getUnreadCountStream() {
    late StreamController<int> controller;
    Function? unsubscribeFunc;

    void startListen() async {
      controller.add(await getInitialUnreadCount());
      unsubscribeFunc = await pb.collection('announcements').subscribe("*", (
        e,
      ) async {
        if (!controller.isClosed) {
          controller.add(await getInitialUnreadCount());
        }
      });
    }

    void stopListen() async {
      if (unsubscribeFunc != null) await unsubscribeFunc!();
    }

    controller = StreamController<int>(
      onListen: startListen,
      onCancel: stopListen,
    );

    return controller.stream;
  }

  Future<int> getInitialUnreadCount() async {
    final userId = pb.authStore.record?.id;
    if (userId == null) return 0;
    try {
      final records = await pb
          .collection('announcements')
          .getFullList(sort: '-created');
      int count = 0;
      for (var doc in records) {
        String creatorId = doc.data['user'] ?? doc.data['created_by'] ?? '';
        if (creatorId == userId) continue;
        List seenBy = doc.data['seen_by'] ?? [];
        if (seenBy.contains(userId)) continue;
        List targetUsers = doc.data['target_users'] ?? [];
        if (targetUsers.isEmpty || targetUsers.contains(userId)) {
          count++;
        }
      }
      return count;
    } catch (e) {
      return 0;
    }
  }

  // --- الاستماع للإشعارات في وضع سطح المكتب ---
  void startListeningToAnnouncements() {
    // ⚠️ منع التشغيل على الأندرويد لأن الخلفية (Background Service) تقوم بالمهمة
    if (Platform.isAndroid || Platform.isIOS) return;

    print("🎧 Start Listening to Announcements (Desktop Mode)...");
    try {
      pb.collection('announcements').subscribe('*', (e) {
        if (e.action == 'create') {
          // الشرط 1: منع الإشعار الذاتي
          if (e.record!.data['user'] == pb.authStore.model.id) return;

          // الشرط 2: التحقق من التوجيه (Target Users)
          List targets = e.record!.data['target_users'] ?? [];
          if (targets.isNotEmpty && !targets.contains(pb.authStore.model.id))
            return;

          String title = e.record!.data['title'] ?? 'تنبيه إداري';
          String rawContent = e.record!.data['content'] ?? '';
          String cleanContent = _parseQuillContent(rawContent);

          PBHelper.showNotification(title: title, body: cleanContent);
        }
      });
    } catch (e) {
      print("Error listening to announcements: $e");
    }
  }

  String _parseQuillContent(String jsonString) {
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
}
