import 'pb_helper.dart';

class TrashService {
  final pb = PBHelper().pb;

  /// جلب العناصر المحذوفة من جدول معين
  Future<List<Map<String, dynamic>>> getDeletedItems(
    String collectionName,
  ) async {
    try {
      final records = await pb
          .collection(collectionName)
          .getFullList(filter: 'is_deleted = true', sort: '-updated');

      // تحويل النتائج إلى Map
      return records.map((r) {
        var map = PBHelper.recordToMap(r);
        // إضافة اسم المجموعة عشان نعرف نرجعها
        map['collectionName'] = collectionName;
        return map;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// استرجاع عنصر من سلة المهملات
  Future<void> restoreItem(String collectionName, String id) async {
    await pb.collection(collectionName).update(id, body: {'is_deleted': false});
  }

  /// حذف نهائي (لا يمكن التراجع عنه)
  Future<void> deleteForever(String collectionName, String id) async {
    await pb.collection(collectionName).delete(id);
  }

  // دالة الحذف النهائي لأي عنصر من أي جدول
  Future<void> deleteItemForever(String collection, String id) async {
    await pb.collection(collection).delete(id);
  }

  /// دالة مساعدة للحصول على الاسم المناسب للعرض حسب الجدول
  String getItemName(Map<String, dynamic> item, String type) {
    if (type == 'products' || type == 'clients' || type == 'suppliers') {
      return item['name'] ?? 'بدون اسم';
    } else if (type == 'expenses') {
      return item['title'] ?? item['category'] ?? 'مصروف';
    } else if (type == 'sales') {
      return "فاتورة مبيعات #${item['referenceNumber'] ?? item['id']}";
    } else if (type == 'purchases') {
      // ✅ الإضافة الجديدة: معالجة اسم فاتورة المشتريات
      return "فاتورة شراء #${item['referenceNumber'] ?? item['id']}";
    }
    return 'عنصر';
  }
}
