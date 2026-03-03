class UserModel {
  final String uid;
  final String email;
  final String role; // 'owner', 'manager', 'employee'

  UserModel({required this.uid, required this.email, required this.role});

  // تحويل البيانات القادمة من Firestore إلى كلاس
  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      uid: docId,
      email: map['email'] ?? '',
      role: map['role'] ?? 'employee', // الافتراضي موظف لو مش محدد
    );
  }

  // تحويل الكلاس إلى بيانات للحفظ في Firestore
  Map<String, dynamic> toMap() {
    return {'email': email, 'role': role};
  }
}
