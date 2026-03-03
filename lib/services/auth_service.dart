import 'package:shared_preferences/shared_preferences.dart';
import 'pb_helper.dart';

class AuthService {
  final pb = PBHelper().pb;

  Future<bool> login(String email, String password) async {
    try {
      await pb.collection('users').authWithPassword(email, password);

      if (pb.authStore.isValid) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('my_user_id', pb.authStore.model.id);
      }
      return pb.authStore.isValid;
    } catch (e) {
      return false;
    }
  }

  void logout() async {
    pb.realtime.unsubscribe();
    pb.authStore.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('my_user_id');
  }

  bool get isAdmin {
    if (!pb.authStore.isValid) return false;
    final record = pb.authStore.record;
    if (record == null) return false;
    return record.data['role'] == 'admin';
  }

  Future<List<Map<String, dynamic>>> getUsers() async {
    final records = await pb.collection('users').getFullList(sort: '-created');
    return records.map((record) {
      final data = Map<String, dynamic>.from(record.data);
      data['id'] = record.id;
      if (!data.containsKey('email') || data['email'] == "") {
        data['email'] = record.getStringValue('email');
      }
      return data;
    }).toList();
  }

  Future<void> createUser(
    String name,
    String email,
    String password,
    String role,
  ) async {
    final body = {
      "username":
          name.replaceAll(' ', '').toLowerCase() +
          "${DateTime.now().millisecond}",
      "email": email,
      "emailVisibility": true,
      "password": password,
      "passwordConfirm": password,
      "name": name,
      "role": role,
    };
    await pb.collection('users').create(body: body);
  }

  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await pb.collection('users').update(id, body: data);
  }

  Future<void> deleteUser(String id) async {
    await pb.collection('users').delete(id);
  }

  Future<void> updateUserPassword(String userId, String newPassword) async {
    final body = {"password": newPassword, "passwordConfirm": newPassword};
    await pb.collection('users').update(userId, body: body);
  }
}
