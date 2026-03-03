import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'pb_helper.dart';

class PurchasesService {
  final pb = PBHelper().pb;

  // ==================== الموردين ====================
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    final records = await pb
        .collection('suppliers')
        .getFullList(sort: 'name', filter: 'is_deleted = false');
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<RecordModel> insertSupplier(Map<String, dynamic> body) async {
    body.remove('id');
    return await pb.collection('suppliers').create(body: body);
  }

  Future<RecordModel> updateSupplier(
    String id,
    Map<String, dynamic> body,
  ) async {
    return await pb.collection('suppliers').update(id, body: body);
  }

  // ✅ دالة الحذف الآمن للمورد (Soft Delete)
  Future<void> deleteSupplier(String id) async {
    // بدل delete(id) بنستخدم update لتغيير الحالة فقط
    await pb.collection('suppliers').update(id, body: {'is_deleted': true});
  }

  Future<double> getSupplierOpeningBalance(String supplierId) async {
    try {
      final records = await pb
          .collection('supplier_opening_balances')
          .getList(filter: 'supplier = "$supplierId"', perPage: 1);
      if (records.items.isNotEmpty) {
        return (records.items.first.data['amount'] ?? 0).toDouble();
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<void> updateSupplierOpeningBalance(
    String supplierId,
    double newAmount,
  ) async {
    try {
      final records = await pb
          .collection('supplier_opening_balances')
          .getList(filter: 'supplier = "$supplierId"', perPage: 1);
      double oldAmount = 0.0;

      if (records.items.isNotEmpty) {
        final record = records.items.first;
        oldAmount = (record.data['amount'] ?? 0).toDouble();
        await pb
            .collection('supplier_opening_balances')
            .update(record.id, body: {'amount': newAmount});
      } else {
        await pb
            .collection('supplier_opening_balances')
            .create(
              body: {
                'supplier': supplierId,
                'amount': newAmount,
                'date': DateTime.now().toIso8601String(),
                'notes': 'رصيد افتتاحي (معدل)',
              },
            );
      }

      double diff = newAmount - oldAmount;
      if (diff != 0) {
        final supplier = await pb.collection('suppliers').getOne(supplierId);
        double currentBal = (supplier.data['balance'] ?? 0).toDouble();
        await pb
            .collection('suppliers')
            .update(supplierId, body: {'balance': currentBal + diff});
      }
    } catch (e) {}
  }

  Future<void> createPurchase(
    String supplierId,
    double totalAmount,
    List<Map<String, dynamic>> items, {
    String? refNumber,
    String? customDate,
    String paymentType = 'cash',
    double taxAmount = 0.0,
    double whtAmount = 0.0,
    double discount = 0.0,
  }) async {
    RecordModel? purchaseRecord;

    try {
      // ============================================================
      // 1. الخطوة الأولى: إنشاء فاتورة المشتريات الأساسية
      // ============================================================
      final body = {
        'supplier': supplierId,
        'totalAmount': totalAmount,
        'paymentType': paymentType,
        'date': customDate ?? DateTime.now().toIso8601String(),
        'referenceNumber': refNumber ?? '',
        'taxAmount': taxAmount,
        'whtAmount': whtAmount,
        'discount': discount,
      };

      purchaseRecord = await pb.collection('purchases').create(body: body);

      // ============================================================
      // 2. الخطوة الثانية: إضافة الأصناف وتزويد المخزن (Loop)
      // ============================================================
      for (var item in items) {
        // أ. تسجيل الصنف في تفاصيل الفاتورة
        await pb
            .collection('purchase_items')
            .create(
              body: {
                'purchase': purchaseRecord.id,
                'product': item['productId'],
                'quantity': item['quantity'],
                'costPrice': item['price'], // لاحظ الاسم costPrice
              },
            );

        // ب. تحديث المخزن (زيادة الكمية + تحديث سعر الشراء)
        try {
          final product = await pb
              .collection('products')
              .getOne(item['productId']);
          int currentStock = (product.data['stock'] ?? 0).toInt();
          int newStock = currentStock + (item['quantity'] as int); // زيادة (+)

          await pb
              .collection('products')
              .update(
                product.id,
                body: {
                  'stock': newStock,
                  'buyPrice': item['price'], // تحديث سعر الشراء لآخر سعر
                },
              );
        } catch (e) {
          print("خطأ في تحديث مخزن الصنف ${item['name']}: $e");
          throw e; // نرمي الخطأ عشان الـ Catch الرئيسي يلقطه ويعمل Rollback
        }
      }

      // ============================================================
      // 3. الخطوة الثالثة: تحديث رصيد المورد (لو آجل)
      // ============================================================
      if (paymentType == 'credit') {
        try {
          final supplier = await pb.collection('suppliers').getOne(supplierId);
          double currentBalance = (supplier.data['balance'] ?? 0).toDouble();

          // المديونية بتزيد علينا (+)
          await pb
              .collection('suppliers')
              .update(
                supplierId,
                body: {'balance': currentBalance + totalAmount},
              );
        } catch (e) {
          print("خطأ في تحديث رصيد المورد: $e");
          throw e;
        }
      }

      // ✅ لو وصلنا هنا يبقى العملية تمت بنجاح
    } catch (e) {
      // 🚨 حصلت مشكلة! (نت فصل أو غيره)
      print("خطأ أثناء حفظ فاتورة المشتريات: $e");

      // 🛑 Rollback: التراجع الفوري وحذف الفاتورة
      if (purchaseRecord != null) {
        print("جاري التراجع وحذف الفاتورة المعلقة...");
        try {
          await pb.collection('purchases').delete(purchaseRecord.id);
          // ملاحظة: تراجع المخزن ورصيد المورد هنا معقد،
          // لكن حذف الفاتورة يمنع ظهورها كسجل مالي وهو الأهم.
        } catch (deleteError) {
          print("فشل حذف الفاتورة: $deleteError");
        }
      }

      // إعادة رمي الخطأ للواجهة
      throw Exception("فشل حفظ فاتورة المشتريات. تم التراجع.");
    }
  }

  // دالة لتعديل رقم مرجع الفاتورة (للمشتريات)
  Future<void> updatePurchaseReference(
    String purchaseId,
    String newRefNumber,
  ) async {
    try {
      await pb
          .collection('purchases')
          .update(purchaseId, body: {'referenceNumber': newRefNumber});
    } catch (e) {
      throw Exception("فشل تعديل رقم المرجع: $e");
    }
  }

  // ✅ تعديل: جلب المشتريات بفلتر التاريخ
  Future<List<Map<String, dynamic>>> getPurchases({
    String? startDate,
    String? endDate,
  }) async {
    String filter = '';
    if (startDate != null && endDate != null) {
      filter = 'date >= "$startDate" && date <= "$endDate"';
    }
    final records = await pb
        .collection('purchases')
        .getFullList(sort: '-date', expand: 'supplier', filter: filter);
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getPurchaseItems(String purchaseId) async {
    final records = await pb
        .collection('purchase_items')
        .getFullList(filter: 'purchase = "$purchaseId"', expand: 'product');
    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      if (r.expand.containsKey('product')) {
        map['productName'] = r.expand['product']?.first.data['name'];
      }
      return map;
    }).toList();
  }

  // ✅ دالة لجلب المشتريات المحذوفة مع بيانات المورد
  Future<List<Map<String, dynamic>>> getDeletedPurchases() async {
    final records = await pb
        .collection('purchases')
        .getFullList(
          filter: 'is_deleted = true',
          sort: '-updated',
          expand: 'supplier', // 👈 ده المهم عشان الاسم يظهر
        );

    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      map['collectionName'] =
          'purchases'; // لازم نضيف ده عشان TrashScreen تفهمه
      return map;
    }).toList();
  }

  // ✅ دالة لجلب الموردين المحذوفين
  Future<List<Map<String, dynamic>>> getDeletedSuppliers() async {
    final records = await pb
        .collection('suppliers')
        .getFullList(filter: 'is_deleted = true', sort: '-updated');

    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      map['collectionName'] = 'suppliers';
      return map;
    }).toList();
  }

  Future<Map<String, dynamic>?> getPurchaseById(String purchaseId) async {
    try {
      final record = await pb.collection('purchases').getOne(purchaseId);
      return PBHelper.recordToMap(record);
    } catch (e) {
      return null;
    }
  }

  // ==================== مرتجعات المشتريات - بنظام Batch ====================
  Future<void> createPurchaseReturn(
    String purchaseId,
    String supplierId,
    double returnTotal,
    List<Map<String, dynamic>> itemsToReturn,
  ) async {
    final batch = pb.createBatch();
    final String returnId = PBHelper.generateId();

    // 1. إنشاء المرتجع
    batch
        .collection('purchase_returns')
        .create(
          body: {
            'id': returnId,
            'purchase': purchaseId,
            'supplier': supplierId,
            'totalAmount': returnTotal,
            'date': DateTime.now().toIso8601String(),
            'notes': 'مرتجع مشتريات',
          },
        );

    // 2. الأصناف + خصم المخزن
    for (var item in itemsToReturn) {
      batch
          .collection('purchase_return_items')
          .create(
            body: {
              'purchase_return': returnId,
              'product': item['productId'],
              'quantity': item['quantity'],
              'price': item['price'],
            },
          );

      try {
        final product = await pb
            .collection('products')
            .getOne(item['productId']);
        int currentStock = (product.data['stock'] ?? 0).toInt();
        batch
            .collection('products')
            .update(
              item['productId'],
              body: {'stock': currentStock - (item['quantity'] as int)},
            );
      } catch (e) {
        throw Exception("خطأ في بيانات الصنف");
      }
    }

    // 3. خصم من رصيد المورد
    try {
      final supplier = await pb.collection('suppliers').getOne(supplierId);
      double currentBalance = (supplier.data['balance'] ?? 0).toDouble();
      batch
          .collection('suppliers')
          .update(supplierId, body: {'balance': currentBalance - returnTotal});
    } catch (e) {
      throw Exception("خطأ في بيانات المورد");
    }

    await batch.send();
  }

  // ✅ تعديل: جلب مرتجعات المشتريات بفلتر التاريخ
  Future<List<Map<String, dynamic>>> getAllPurchaseReturns({
    String? startDate,
    String? endDate,
  }) async {
    String filter = '';
    if (startDate != null && endDate != null) {
      filter = 'date >= "$startDate" && date <= "$endDate"';
    }
    final records = await pb
        .collection('purchase_returns')
        .getFullList(sort: '-date', expand: 'supplier', filter: filter);
    return records.map(PBHelper.recordToMap).toList();
  }

  // 🔍 دالة مساعدة: معرفة الكميات التي تم إرجاعها مسبقاً من فاتورة معينة
  Future<Map<String, int>> getAlreadyReturnedItems(String purchaseId) async {
    Map<String, int> result = {};
    try {
      final returns = await pb
          .collection('purchase_return_items')
          .getFullList(filter: 'purchase_return.purchase = "$purchaseId"');
      for (var item in returns) {
        String prodId = item.data['product'];
        int qty = (item.data['quantity'] as num).toInt();
        result[prodId] = (result[prodId] ?? 0) + qty;
      }
    } catch (_) {}
    return result;
  }

  // 🗑️ دالة الحذف الآمن لفاتورة المشتريات (تخصم من المخزن والرصيد)
  Future<void> deletePurchaseSafe(String purchaseId) async {
    try {
      // 1. جلب بيانات الفاتورة
      final purchase = await pb.collection('purchases').getOne(purchaseId);
      final isCredit = purchase.data['paymentType'] != 'cash';
      final supplierId = purchase.data['supplier'];
      final totalAmount = (purchase.data['totalAmount'] as num).toDouble();

      // 2. جلب الأصناف الأصلية
      final items = await getPurchaseItems(purchaseId);

      // 3. جلب ما تم إرجاعه مسبقاً (عشان منخصمش من المخزن مرتين)
      final returnedMap = await getAlreadyReturnedItems(purchaseId);

      // 4. خصم البضاعة من المخزن (الصافي فقط)
      for (var item in items) {
        String prodId = item['product'];
        int originalQty = (item['quantity'] as num).toInt();
        int alreadyReturned = returnedMap[prodId] ?? 0;

        // الكمية اللي دخلت المخزن ولسه موجودة (ولازم نشيلها عشان بنحذف الفاتورة)
        int qtyToRemove = originalQty - alreadyReturned;

        if (qtyToRemove > 0) {
          try {
            final productRec = await pb.collection('products').getOne(prodId);
            int currentStock = (productRec.data['stock'] as num).toInt();

            // 🔻 هنا الفرق الجوهري عن المبيعات: المشتريات بتزود المخزن، فالحذف ينقصه
            await pb
                .collection('products')
                .update(prodId, body: {'stock': currentStock - qtyToRemove});
          } catch (_) {}
        }
      }

      // 5. تصحيح رصيد المورد (لو آجل)
      if (isCredit && supplierId != null && supplierId != "") {
        try {
          final supplierRec = await pb
              .collection('suppliers')
              .getOne(supplierId);
          double currentBalance = (supplierRec.data['balance'] as num)
              .toDouble();

          // المديونية كانت زادت، دلوقتي بنقللها
          await pb
              .collection('suppliers')
              .update(
                supplierId,
                body: {'balance': currentBalance - totalAmount},
              );
        } catch (_) {}
      }

      // 6. حذف سجلات المرتجعات المرتبطة (تنظيف)
      try {
        final relatedReturns = await pb
            .collection('purchase_returns')
            .getFullList(filter: 'purchase = "$purchaseId"');
        for (var ret in relatedReturns) {
          await pb.collection('purchase_returns').delete(ret.id);
        }
      } catch (_) {}

      // 7. حذف الأصناف والفاتورة نفسها
      for (var item in items) {
        await pb.collection('purchase_items').delete(item['id']);
      }
      await pb.collection('purchases').delete(purchaseId);
    } catch (e) {
      throw Exception("فشل حذف فاتورة المشتريات: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getPurchaseReturnItems(
    String returnId,
  ) async {
    final records = await pb
        .collection('purchase_return_items')
        .getFullList(
          filter: 'purchase_return = "$returnId"',
          expand: 'product',
        );
    return records.map((e) {
      final map = PBHelper.recordToMap(e);
      if (e.expand.containsKey('product')) {
        map['productName'] = e.expand['product']![0].data['name'];
      }
      return map;
    }).toList();
  }

  Future<void> deletePurchaseReturnSafe(String returnId) async {
    final retRecord = await pb.collection('purchase_returns').getOne(returnId);
    final items = await getPurchaseReturnItems(returnId);
    final supplierId = retRecord.data['supplier'];
    final totalAmount = (retRecord.data['totalAmount'] as num).toDouble();

    for (var item in items) {
      String prodId = item['product'];
      int qty = (item['quantity'] as num).toInt();
      final prod = await pb.collection('products').getOne(prodId);
      int currentStock = (prod.data['stock'] as num).toInt();
      await pb
          .collection('products')
          .update(prodId, body: {'stock': currentStock + qty});
    }

    if (supplierId != null && supplierId.toString().isNotEmpty) {
      final supp = await pb.collection('suppliers').getOne(supplierId);
      double currentBal = (supp.data['balance'] as num).toDouble();
      await pb
          .collection('suppliers')
          .update(supplierId, body: {'balance': currentBal - totalAmount});
    }

    await pb.collection('purchase_returns').delete(returnId);
  }

  // ==================== المدفوعات للموردين ====================
  Future<void> addSupplierPayment({
    required String supplierId,
    required double amount,
    required String notes,
    required String date,
    String paymentMethod = 'cash',
    String? imagePath,
  }) async {
    List<http.MultipartFile> files = [];
    if (imagePath != null && imagePath.isNotEmpty) {
      final file = File(imagePath);
      if (await file.exists()) {
        files.add(await http.MultipartFile.fromPath('receiptImage', imagePath));
      }
    }

    await pb
        .collection('supplier_payments')
        .create(
          body: {
            'supplier': supplierId,
            'amount': amount,
            'notes': notes,
            'date': date,
            'method': paymentMethod,
          },
          files: files,
        );

    final supplier = await pb.collection('suppliers').getOne(supplierId);
    double currentBalance = (supplier.data['balance'] ?? 0).toDouble();
    await pb
        .collection('suppliers')
        .update(supplierId, body: {'balance': currentBalance - amount});
  }

  Future<void> deleteSupplierPayment(
    String paymentId,
    String supplierId,
    double amount,
  ) async {
    await pb.collection('supplier_payments').delete(paymentId);
    final supplier = await pb.collection('suppliers').getOne(supplierId);
    double currentBalance = (supplier.data['balance'] ?? 0).toDouble();
    await pb
        .collection('suppliers')
        .update(supplierId, body: {'balance': currentBalance + amount});
  }

  Future<List<Map<String, dynamic>>> getAllSupplierPayments() async {
    final records = await pb
        .collection('supplier_payments')
        .getFullList(sort: '-date', expand: 'supplier');
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getSupplierStatement(
    String supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String dateFilter = "";
    if (startDate != null && endDate != null) {
      String start = startDate.toIso8601String();
      String end = endDate.add(const Duration(days: 1)).toIso8601String();
      dateFilter = ' && date >= "$start" && date < "$end"';
    }
    List<Map<String, dynamic>> statement = [];

    final purchases = await pb
        .collection('purchases')
        .getFullList(
          filter: 'supplier = "$supplierId" $dateFilter',
          sort: 'date',
        );
    for (var p in purchases) {
      statement.add({
        'type': 'bill',
        'date': p.data['date'],
        'amount': (p.data['totalAmount'] as num).toDouble(),
        'description': 'فاتورة شراء #${p.id.substring(0, 5)}',
        'id': p.id,
      });
    }

    try {
      final returns = await pb
          .collection('purchase_returns')
          .getFullList(
            filter: 'supplier = "$supplierId" $dateFilter',
            sort: 'date',
          );
      for (var r in returns) {
        statement.add({
          'type': 'return',
          'date': r.data['date'],
          'amount': (r.data['totalAmount'] as num).toDouble(),
          'description': 'مرتجع مشتريات #${r.id.substring(0, 5)}',
          'id': r.id,
        });
      }
    } catch (e) {}

    try {
      final payments = await pb
          .collection('supplier_payments')
          .getFullList(
            filter: 'supplier = "$supplierId" $dateFilter',
            sort: 'date',
          );
      for (var p in payments) {
        statement.add({
          'type': 'payment',
          'date': p.data['date'],
          'amount': (p.data['amount'] as num).toDouble(),
          'description': p.data['notes'] ?? 'سند دفع',
          'id': p.id,
        });
      }
    } catch (e) {}

    statement.sort(
      (a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])),
    );
    return statement;
  }

  // ==================== المصروفات (Expenses) ====================
  Future<List<Map<String, dynamic>>> getExpenses() async {
    final records = await pb
        .collection('expenses')
        .getFullList(sort: '-created', filter: 'is_deleted = false');
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<RecordModel> insertExpense(Map<String, dynamic> body) async {
    body.remove('id');
    return await pb.collection('expenses').create(body: body);
  }

  Future<void> updateExpense(String id, Map<String, dynamic> body) async {
    await pb.collection('expenses').update(id, body: body);
  }

  Future<void> deleteExpense(String id) async {
    await pb.collection('expenses').update(id, body: {'is_deleted': true});
  }
  // ==================== إدارة سلة المهملات للمشتريات ====================

  /// 🗑️ حذف مؤقت: يخصم البضاعة من المخزن ويقلل مديونية المورد
  Future<void> softDeletePurchase(String purchaseId) async {
    final purchase = await pb.collection('purchases').getOne(purchaseId);

    // جلب الأصناف (تأكد أن عندك دالة getPurchaseItems مشابهة للمبيعات)
    final items = await pb
        .collection('purchase_items')
        .getFullList(filter: 'purchase = "$purchaseId"');

    if (purchase.data['is_deleted'] == true) return;

    final isCredit = purchase.data['paymentType'] != 'cash';
    final supplierId = purchase.data['supplier'];
    final totalAmount = (purchase.data['totalAmount'] ?? 0).toDouble();

    // 1. 🔥 خصم البضاعة من المخزن (لأننا لغينا الشراء)
    for (var item in items) {
      String prodId = item.data['product'];
      int qty = (item.data['quantity'] as num).toInt();

      try {
        final prod = await pb.collection('products').getOne(prodId);
        int currentStock = (prod.data['stock'] as num).toInt();

        await pb
            .collection('products')
            .update(
              prodId,
              body: {
                'stock': currentStock - qty, // نقص المخزون
              },
            );
      } catch (_) {}
    }

    // 2. 💰 تعديل حساب المورد
    if (isCredit && supplierId != null && supplierId != "") {
      try {
        final suppRec = await pb.collection('suppliers').getOne(supplierId);
        double currentBal = (suppRec.data['balance'] as num).toDouble();

        await pb
            .collection('suppliers')
            .update(
              supplierId,
              body: {
                'balance': currentBal - totalAmount, // شيل الفلوس من عليه
              },
            );
      } catch (_) {}
    }

    await pb
        .collection('purchases')
        .update(purchaseId, body: {'is_deleted': true});
  }

  /// ♻️ استرجاع الشراء: يزود المخزن ويعيد مديونية المورد
  Future<void> restorePurchase(String purchaseId) async {
    final purchase = await pb.collection('purchases').getOne(purchaseId);
    final items = await pb
        .collection('purchase_items')
        .getFullList(filter: 'purchase = "$purchaseId"');

    if (purchase.data['is_deleted'] == false) return;

    final isCredit = purchase.data['paymentType'] != 'cash';
    final supplierId = purchase.data['supplier'];
    final totalAmount = (purchase.data['totalAmount'] ?? 0).toDouble();

    // 1. 🔥 إعادة البضاعة للمخزن
    for (var item in items) {
      String prodId = item.data['product'];
      int qty = (item.data['quantity'] as num).toInt();

      try {
        final prod = await pb.collection('products').getOne(prodId);
        int currentStock = (prod.data['stock'] as num).toInt();

        await pb
            .collection('products')
            .update(prodId, body: {'stock': currentStock + qty});
      } catch (_) {}
    }

    // 2. 💰 إعادة حساب المورد
    if (isCredit && supplierId != null && supplierId != "") {
      try {
        final suppRec = await pb.collection('suppliers').getOne(supplierId);
        double currentBal = (suppRec.data['balance'] as num).toDouble();

        await pb
            .collection('suppliers')
            .update(supplierId, body: {'balance': currentBal + totalAmount});
      } catch (_) {}
    }

    await pb
        .collection('purchases')
        .update(purchaseId, body: {'is_deleted': false});
  }
}
