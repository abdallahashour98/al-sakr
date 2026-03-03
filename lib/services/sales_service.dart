import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'pb_helper.dart';

class SalesService {
  final pb = PBHelper().pb;

  // ==================== العملاء ====================
  Future<List<Map<String, dynamic>>> getClients() async {
    final records = await pb
        .collection('clients')
        .getFullList(sort: 'name', filter: 'is_deleted = false');
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<RecordModel> insertClient(Map<String, dynamic> body) async {
    body.remove('id');
    return await pb.collection('clients').create(body: body);
  }

  Future<RecordModel> updateClient(String id, Map<String, dynamic> body) async {
    return await pb.collection('clients').update(id, body: body);
  }

  Future<void> deleteClient(String id) async {
    await pb.collection('clients').update(id, body: {'is_deleted': true});
  }

  Future<double> getClientOpeningBalance(String clientId) async {
    try {
      final records = await pb
          .collection('opening_balances')
          .getList(filter: 'client = "$clientId"', perPage: 1);
      if (records.items.isNotEmpty) {
        return (records.items.first.data['amount'] ?? 0).toDouble();
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<void> updateClientOpeningBalance(
    String clientId,
    double newAmount,
  ) async {
    try {
      final records = await pb
          .collection('opening_balances')
          .getList(filter: 'client = "$clientId"', perPage: 1);
      double oldAmount = 0.0;

      if (records.items.isNotEmpty) {
        final record = records.items.first;
        oldAmount = (record.data['amount'] ?? 0).toDouble();
        await pb
            .collection('opening_balances')
            .update(record.id, body: {'amount': newAmount});
      } else {
        await pb
            .collection('opening_balances')
            .create(
              body: {
                'client': clientId,
                'amount': newAmount,
                'date': DateTime.now().toIso8601String(),
                'notes': 'رصيد افتتاحي',
              },
            );
      }

      double diff = newAmount - oldAmount;
      if (diff != 0) {
        final client = await pb.collection('clients').getOne(clientId);
        double currentBal = (client.data['balance'] ?? 0).toDouble();
        await pb
            .collection('clients')
            .update(clientId, body: {'balance': currentBal + diff});
      }
    } catch (e) {}
  }

  Future<void> createSale(
    String clientId,
    String clientName,
    double totalAmount,
    double taxAmount,
    List<Map<String, dynamic>> items, {
    String refNumber = '',
    double discount = 0.0,
    bool isCash = true,
    double whtAmount = 0.0,
  }) async {
    RecordModel? saleRecord;

    try {
      // ============================================================
      // 1. الخطوة الأولى: إنشاء رأس الفاتورة (مبدئياً)
      // ============================================================
      final saleBody = {
        'client': clientId,
        'totalAmount': totalAmount,
        'discount': discount,
        'taxAmount': taxAmount,
        'whtAmount': whtAmount,
        'netAmount': (totalAmount - discount) + taxAmount - whtAmount,
        'paymentType': isCash ? 'cash' : 'credit',
        'date': DateTime.now().toIso8601String(),
        'referenceNumber': refNumber,
      };

      saleRecord = await pb.collection('sales').create(body: saleBody);

      // ============================================================
      // 2. الخطوة الثانية: إضافة الأصناف وتحديث المخزن (Loop)
      // ============================================================
      for (var item in items) {
        // أ. تسجيل الصنف في الفاتورة
        await pb
            .collection('sale_items')
            .create(
              body: {
                'sale': saleRecord.id,
                'product': item['productId'],
                'quantity': item['quantity'],
                'price': item['price'],
              },
            );

        // ب. خصم الكمية من المخزن
        final product = await pb
            .collection('products')
            .getOne(item['productId']);
        int currentStock = (product.data['stock'] ?? 0).toInt();
        int newStock = currentStock - (item['quantity'] as int);

        await pb
            .collection('products')
            .update(product.id, body: {'stock': newStock});
      }

      // ============================================================
      // 3. الخطوة الثالثة: تحديث رصيد العميل (لو آجل)
      // ============================================================
      if (!isCash) {
        final client = await pb.collection('clients').getOne(clientId);
        double currentBal = (client.data['balance'] ?? 0).toDouble();
        double netTotal = (totalAmount - discount) + taxAmount - whtAmount;

        await pb
            .collection('clients')
            .update(clientId, body: {'balance': currentBal + netTotal});
      }

      // ✅ لو وصلنا هنا يبقى كل حاجة تمام
    } catch (e) {
      // 🚨 كارثة! حصل خطأ في النص (النت فصل أو غيره)
      print("حدث خطأ أثناء حفظ الفاتورة: $e");

      // 🛑 Rollback: التراجع فوراً
      if (saleRecord != null) {
        print("جاري حذف الفاتورة غير المكتملة...");
        try {
          // 1. نحذف الفاتورة اللي اتعملت عشان الداتا متنقصش
          await pb.collection('sales').delete(saleRecord.id);

          // ملحوظة: لو عاوز ترجع المخزن اللي اتخصم (لو اللوب وقف في النص)، الموضوع معقد شوية
          // لكن حذف الفاتورة هو أهم خطوة عشان الحسابات المالية متضربش.
        } catch (deleteError) {
          print("فشل حذف الفاتورة المعلقة: $deleteError");
        }
      }

      // نعيد رمي الخطأ عشان الـ UI يظهر رسالة حمراء
      throw Exception("فشلت العملية وتم التراجع عن الفاتورة. تأكد من الاتصال.");
    }
  }

  // دالة لتعديل رقم الفاتورة اليدوي فقط
  Future<void> updateSaleReference(String saleId, String newRefNumber) async {
    try {
      await pb
          .collection('sales')
          .update(
            saleId,
            body: {
              'referenceNumber': newRefNumber, // اسم الحقل في الداتا بيز
            },
          );
      print("✅ تم تعديل رقم الفاتورة بنجاح");
    } catch (e) {
      throw Exception("فشل تعديل رقم الفاتورة: $e");
    }
  }

  // ✅ تعديل: دالة جلب المبيعات لتقبل فلتر التاريخ
  Future<List<Map<String, dynamic>>> getSales({
    String? startDate,
    String? endDate,
  }) async {
    // ✅ إضافة شرط (is_deleted = false) للفلتر
    String filter = 'is_deleted = false';

    if (startDate != null && endDate != null) {
      filter += ' && date >= "$startDate" && date <= "$endDate"';
    }

    final records = await pb
        .collection('sales')
        .getFullList(sort: '-date', expand: 'client', filter: filter);
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getSalesByClient(String clientId) async {
    final records = await pb
        .collection('sales')
        .getFullList(filter: 'client = "$clientId"', sort: '-date');
    return records.map((e) => e.toJson()).toList();
  }

  Future<List<Map<String, dynamic>>> getSaleItems(String saleId) async {
    final records = await pb
        .collection('sale_items')
        .getFullList(filter: 'sale = "$saleId"', expand: 'product');
    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      if (r.expand.containsKey('product'))
        map['productName'] = r.expand['product']?.first.data['name'];
      return map;
    }).toList();
  }

  Future<Map<String, dynamic>?> getSaleById(String saleId) async {
    try {
      final record = await pb.collection('sales').getOne(saleId);
      return PBHelper.recordToMap(record);
    } catch (e) {
      return null;
    }
  }

  // ==================== المرتجعات (Returns) ====================
  Future<void> createReturn(
    String saleId,
    String clientId,
    double returnTotal,
    List<Map<String, dynamic>> itemsToReturn, {
    double discount = 0.0,
  }) async {
    final batch = pb.createBatch();
    final String returnId = PBHelper.generateId();

    // 1. إنشاء سجل المرتجع
    batch
        .collection('returns')
        .create(
          body: {
            'id': returnId,
            'sale': saleId,
            'client': clientId,
            'totalAmount': returnTotal,
            'discount': discount,
            'date': DateTime.now().toIso8601String(),
            'notes': 'مرتجع مبيعات',
          },
        );

    // 2. إضافة الأصناف المرتجعة + زيادة المخزن
    for (var item in itemsToReturn) {
      batch
          .collection('return_items')
          .create(
            body: {
              'return': returnId,
              'product': item['productId'],
              'quantity': item['quantity'],
              'price': item['price'],
            },
          );

      // زيادة المخزن
      try {
        final product = await pb
            .collection('products')
            .getOne(item['productId']);
        int currentStock = (product.data['stock'] ?? 0).toInt();
        batch
            .collection('products')
            .update(
              item['productId'],
              body: {'stock': currentStock + (item['quantity'] as int)},
            );
      } catch (e) {
        throw Exception("خطأ في قراءة رصيد المنتج");
      }
    }

    // 3. خصم القيمة من رصيد العميل
    try {
      final client = await pb.collection('clients').getOne(clientId);
      double currentBalance = (client.data['balance'] ?? 0).toDouble();
      batch
          .collection('clients')
          .update(clientId, body: {'balance': currentBalance - returnTotal});
    } catch (e) {
      throw Exception("خطأ في قراءة رصيد العميل");
    }

    // 4. تنفيذ العملية
    await batch.send();
  }

  // ✅ تعديل: دالة جلب المرتجعات لتقبل فلتر التاريخ
  Future<List<Map<String, dynamic>>> getReturns({
    String? startDate,
    String? endDate,
  }) async {
    String filter = '';
    if (startDate != null && endDate != null) {
      filter = 'date >= "$startDate" && date <= "$endDate"';
    }
    final records = await pb
        .collection('returns')
        .getFullList(sort: '-date', expand: 'client', filter: filter);
    return records.map(PBHelper.recordToMap).toList();
  }

  // ✅ دالة جلب المصروفات مع فلتر التاريخ (لحساب صافي الحركة)
  Future<List<Map<String, dynamic>>> getExpenses({
    String? startDate,
    String? endDate,
  }) async {
    String filter = '';
    if (startDate != null && endDate != null) {
      filter = 'date >= "$startDate" && date <= "$endDate"';
    }

    final records = await pb
        .collection('expenses')
        .getFullList(sort: '-date', filter: filter);
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getReturnItems(String returnId) async {
    final records = await pb
        .collection('return_items')
        .getFullList(filter: 'return = "$returnId"', expand: 'product');
    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      if (r.expand.containsKey('product'))
        map['productName'] = r.expand['product']?.first.data['name'];
      return map;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getReturnsByClient(String clientId) async {
    final records = await pb
        .collection('returns')
        .getFullList(filter: 'client = "$clientId"', sort: '-date');
    return records.map((e) => e.toJson()).toList();
  }

  Future<void> deleteReturnSafe(String returnId) async {
    final retRecord = await pb.collection('returns').getOne(returnId);
    final items = await getReturnItems(returnId);
    final clientId = retRecord.data['client'];
    final totalAmount = (retRecord.data['totalAmount'] as num).toDouble();

    for (var item in items) {
      String prodId = item['product'];
      int qty = (item['quantity'] as num).toInt();
      final prod = await pb.collection('products').getOne(prodId);
      int currentStock = (prod.data['stock'] as num).toInt();
      await pb
          .collection('products')
          .update(prodId, body: {'stock': currentStock - qty});
    }

    if (clientId != null && clientId.toString().isNotEmpty) {
      final client = await pb.collection('clients').getOne(clientId);
      double currentBal = (client.data['balance'] as num).toDouble();
      await pb
          .collection('clients')
          .update(clientId, body: {'balance': currentBal + totalAmount});
    }

    await pb.collection('returns').delete(returnId);
  }

  Future<void> payReturnCash(
    String returnId,
    String clientId,
    double amount,
  ) async {
    await pb
        .collection('client_payments')
        .create(
          body: {
            'client': clientId,
            'amount': amount,
            'date': DateTime.now().toIso8601String(),
            'notes': 'صرف نقدية عن مرتجع',
            'type': 'return_refund',
          },
        );
    final retRecord = await pb.collection('returns').getOne(returnId);
    double oldPaid = (retRecord.data['paidAmount'] ?? 0).toDouble();
    await pb
        .collection('returns')
        .update(returnId, body: {'paidAmount': oldPaid + amount});
  }

  Future<Map<String, int>> getAlreadyReturnedItems(String saleId) async {
    Map<String, int> result = {};
    try {
      final returns = await pb
          .collection('returns')
          .getFullList(filter: 'sale = "$saleId"');
      for (var ret in returns) {
        final items = await pb
            .collection('return_items')
            .getFullList(filter: 'return = "${ret.id}"');
        for (var item in items) {
          String prodId = item.data['product'];
          int qty = (item.data['quantity'] as num).toInt();
          result[prodId] = (result[prodId] ?? 0) + qty;
        }
      }
    } catch (e) {}
    return result;
  }

  // ==================== أذونات التسليم (Delivery Orders) ====================
  Future<List<Map<String, dynamic>>> getAllDeliveryOrders() async {
    try {
      final records = await pb
          .collection('delivery_orders')
          .getFullList(sort: '-date', expand: 'client');
      return records.map((r) {
        var map = PBHelper.recordToMap(r);
        if (map['signedImage'] != null &&
            map['signedImage'].toString().isNotEmpty) {
          map['signedImagePath'] = PBHelper().getImageUrl(
            r.collectionId,
            r.id,
            map['signedImage'],
          );
        }
        return map;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDeliveryOrderItems(
    String orderId,
  ) async {
    try {
      final records = await pb
          .collection('delivery_order_items')
          .getFullList(
            filter: 'delivery_order = "$orderId"',
            expand: 'product',
          );
      return records.map((r) {
        var map = PBHelper.recordToMap(r);
        if (r.expand.containsKey('product')) {
          map['productName'] = r.expand['product']?.first.data['name'];
          // ✅ السطر ده هيجيب الوحدة الأصلية اللي متسجلة في الداتا بيز للصنف
          map['unit'] = r.expand['product']?.first.data['unit'];
        } else {
          map['productName'] = r.data['description'] ?? 'صنف';
        }
        return map;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> createDeliveryOrder(
    String clientId,
    String supplyOrderNumber,
    String manualNo,
    String address,
    String date,
    String notes,
    List<Map<String, dynamic>> items,
  ) async {
    final order = await pb
        .collection('delivery_orders')
        .create(
          body: {
            'client': clientId,
            'supplyOrderNumber': supplyOrderNumber,
            'manualNo': manualNo,
            'address': address,
            'date': date,
            'notes': notes,
            'isLocked': false,
          },
        );

    for (var item in items) {
      String? productId = item['productId'];
      if (productId == null) {
        // محاولة إيجاد المنتج بالاسم
        try {
          final p = await pb
              .collection('products')
              .getList(filter: 'name = "${item['productName']}"', perPage: 1);
          if (p.items.isNotEmpty) productId = p.items.first.id;
        } catch (_) {}
      }
      await pb
          .collection('delivery_order_items')
          .create(
            body: {
              'delivery_order': order.id,
              'product': productId,
              'quantity': item['quantity'],
              'description': item['description'] ?? item['productName'],
              'relatedSupplyOrder': item['relatedSupplyOrder'],
            },
          );
    }
  }

  Future<void> updateDeliveryOrder(
    String id,
    String clientId,
    String supplyOrderNumber,
    String manualNo,
    String address,
    String date,
    String notes,
    List<Map<String, dynamic>> items,
  ) async {
    await pb
        .collection('delivery_orders')
        .update(
          id,
          body: {
            'client': clientId,
            'supplyOrderNumber': supplyOrderNumber,
            'manualNo': manualNo,
            'address': address,
            'date': date,
            'notes': notes,
          },
        );

    final oldItems = await pb
        .collection('delivery_order_items')
        .getFullList(filter: 'delivery_order = "$id"');
    for (var item in oldItems) {
      await pb.collection('delivery_order_items').delete(item.id);
    }

    for (var item in items) {
      String? productId = item['productId'];
      if (productId == null) {
        try {
          final p = await pb
              .collection('products')
              .getList(filter: 'name = "${item['productName']}"', perPage: 1);
          if (p.items.isNotEmpty) productId = p.items.first.id;
        } catch (_) {}
      }
      await pb
          .collection('delivery_order_items')
          .create(
            body: {
              'delivery_order': id,
              'product': productId,
              'quantity': item['quantity'],
              'description': item['description'],
              'relatedSupplyOrder': item['relatedSupplyOrder'],
            },
          );
    }
  }

  Future<void> deleteDeliveryOrder(String id) async {
    await pb.collection('delivery_orders').delete(id);
  }

  Future<void> toggleOrderLock(
    String id,
    bool isLocked, {
    String? imagePath,
  }) async {
    Map<String, dynamic> body = {'isLocked': isLocked};
    if (isLocked && imagePath != null) {
      await pb
          .collection('delivery_orders')
          .update(
            id,
            body: body,
            files: [
              await http.MultipartFile.fromPath('signedImage', imagePath),
            ],
          );
    } else {
      await pb.collection('delivery_orders').update(id, body: body);
    }
  }

  Future<void> updateOrderImage(String id, String? imagePath) async {
    if (imagePath != null) {
      await pb
          .collection('delivery_orders')
          .update(
            id,
            files: [
              await http.MultipartFile.fromPath('signedImage', imagePath),
            ],
          );
    } else {
      await pb
          .collection('delivery_orders')
          .update(id, body: {'signedImage': null});
    }
  }

  // ==================== السندات (Receipts) ====================
  Future<void> createReceipt(
    String clientId,
    double amount,
    String notes,
    String date, {
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
        .collection('receipts')
        .create(
          body: {
            'client': clientId,
            'amount': amount,
            'notes': notes,
            'date': date,
            'method': paymentMethod,
          },
          files: files,
        );
  }

  Future<List<Map<String, dynamic>>> getAllSales() async {
    return await getSales();
  }

  Future<List<Map<String, dynamic>>> getAllReceipts() async {
    final records = await pb
        .collection('receipts')
        .getFullList(sort: '-date', expand: 'client');
    return records.map(PBHelper.recordToMap).toList();
  }

  Future<List<Map<String, dynamic>>> getReceiptsByClient(
    String clientId,
  ) async {
    final records = await pb
        .collection('receipts')
        .getFullList(filter: 'client = "$clientId"', sort: '-date');
    return records.map((e) => e.toJson()).toList();
  }

  // ✅ دالة الحذف الآمن (النسخة الشاملة التي لا تتعطل)
  // ✅ دالة الحذف الآمن (تعالج المرتجعات وتمنع تضاعف المخزن)
  Future<void> deleteSaleSafe(String saleId) async {
    try {
      // 1. جلب بيانات الفاتورة
      final sale = await pb.collection('sales').getOne(saleId);
      final isCredit = sale.data['paymentType'] != 'cash';
      final clientId = sale.data['client'];
      final netAmount =
          (sale.data['netAmount'] ?? sale.data['totalAmount'] ?? 0).toDouble();

      // 2. جلب الأصناف الأصلية
      final items = await getSaleItems(saleId);

      // 3. 🔥 جلب الكميات التي تم إرجاعها مسبقاً (عشان منرجعهاش تاني)
      final returnedMap = await getAlreadyReturnedItems(saleId);

      // 4. إرجاع البضاعة للمخزن (الصافي فقط)
      for (var item in items) {
        String prodId = '';
        if (item['product'] is Map) {
          prodId = item['product']['id'];
        } else if (item['expand'] != null &&
            item['expand']['product'] != null) {
          prodId = item['expand']['product']['id'];
        } else {
          prodId = item['product']?.toString() ?? '';
        }

        if (prodId.isEmpty) continue;

        // الكمية الأصلية في الفاتورة
        int originalQty = (item['quantity'] as num).toInt();
        // الكمية اللي رجعت قبل كدة
        int alreadyReturned =
            returnedMap[item['product']] ?? 0; // نستخدم item['product'] كـ ID

        // ✅ الكمية اللي المفروض ترجع دلوقتي (الباقي عند العميل)
        int qtyToRestock = originalQty - alreadyReturned;

        if (qtyToRestock > 0) {
          try {
            final productRec = await pb.collection('products').getOne(prodId);
            int currentStock = (productRec.data['stock'] as num).toInt();

            await pb
                .collection('products')
                .update(prodId, body: {'stock': currentStock + qtyToRestock});
          } catch (_) {}
        }
      }

      // 5. تصحيح رصيد العميل
      if (isCredit && clientId != null && clientId != "") {
        try {
          final clientRec = await pb.collection('clients').getOne(clientId);
          double currentBalance = (clientRec.data['balance'] as num).toDouble();

          // بنخصم قيمة الفاتورة الصافية (السيستم المفروض حاسبها صح بعد المرتجع)
          // ملاحظة: لو المرتجع كان مخصوم من الفاتورة، يبقى netAmount مظبوط.
          // لو المرتجع منفصل، يبقى لازم نراعي ده، بس للتبسيط هنفترض إن netAmount هو القيمة القائمة.
          await pb
              .collection('clients')
              .update(clientId, body: {'balance': currentBalance - netAmount});
        } catch (_) {}
      }

      // 6. 🔥 حذف سجلات المرتجعات المرتبطة (تنظيف الداتا)
      try {
        final relatedReturns = await pb
            .collection('returns')
            .getFullList(filter: 'sale = "$saleId"');
        for (var ret in relatedReturns) {
          await pb.collection('returns').delete(ret.id);
        }
      } catch (_) {}

      // 7. حذف الأصناف والفاتورة
      for (var item in items) {
        await pb.collection('sale_items').delete(item['id']);
      }
      await pb.collection('sales').delete(saleId);
    } catch (e) {
      throw Exception("فشل الحذف: $e");
    }
  }

  // ✅ دالة لجلب المبيعات المحذوفة مع بيانات العميل
  Future<List<Map<String, dynamic>>> getDeletedSales() async {
    final records = await pb
        .collection('sales')
        .getFullList(
          filter: 'is_deleted = true',
          sort: '-updated',
          expand: 'client', // 👈 ده المهم عشان اسم العميل يظهر
        );

    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      map['collectionName'] = 'sales';
      return map;
    }).toList();
  }

  // ✅ دالة لجلب العملاء المحذوفين
  Future<List<Map<String, dynamic>>> getDeletedClients() async {
    final records = await pb
        .collection('clients')
        .getFullList(filter: 'is_deleted = true', sort: '-updated');

    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      map['collectionName'] = 'clients';
      return map;
    }).toList();
  }

  // ✅ دالة لجلب المصروفات المحذوفة
  Future<List<Map<String, dynamic>>> getDeletedExpenses() async {
    // المصروفات عادة لا تحذف بـ flag ولكن بالحذف المباشر،
    // ولكن إذا كنت تستخدم is_deleted، فهذا هو الكود:
    final records = await pb
        .collection('expenses')
        .getFullList(filter: 'is_deleted = true', sort: '-updated');

    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      map['collectionName'] = 'expenses';
      return map;
    }).toList();
  }

  // ✅ دالة الحذف الآمن للمصروف (Soft Delete)
  Future<void> deleteExpense(String id) async {
    await pb.collection('expenses').update(id, body: {'is_deleted': true});
  }
  // ==================== إدارة سلة المهملات للمبيعات ====================

  /// 🗑️ حذف مؤقت: يرجع البضاعة للمخزن ويخصم المديونية من العميل
  Future<void> softDeleteSale(String saleId) async {
    // 1. جلب بيانات الفاتورة والأصناف
    final sale = await pb.collection('sales').getOne(saleId);
    final items = await getSaleItems(saleId);

    // لو الفاتورة محذوفة بالفعل، لا تفعل شيء
    if (sale.data['is_deleted'] == true) return;

    final isCredit = sale.data['paymentType'] != 'cash';
    final clientId = sale.data['client'];
    final netAmount = (sale.data['netAmount'] ?? 0).toDouble();

    // 2. 🔥 إرجاع البضاعة للمخزن
    for (var item in items) {
      String prodId = '';
      // استخراج ID المنتج بشكل آمن
      if (item['product'] is Map) {
        prodId = item['product']['id'];
      } else if (item['expand'] != null && item['expand']['product'] != null) {
        prodId = item['expand']['product']['id'];
      } else {
        prodId = item['product']?.toString() ?? '';
      }

      if (prodId.isNotEmpty) {
        try {
          // هات المنتج الحالي
          final prod = await pb.collection('products').getOne(prodId);
          int currentStock = (prod.data['stock'] as num).toInt();
          int qty = (item['quantity'] as num).toInt();

          // زود المخزون (ترجيع)
          await pb
              .collection('products')
              .update(prodId, body: {'stock': currentStock + qty});
        } catch (_) {}
      }
    }

    // 3. 💰 تعديل رصيد العميل (لو آجل) -> بنشيل الفلوس من عليه
    if (isCredit && clientId != null && clientId != "") {
      try {
        final clientRec = await pb.collection('clients').getOne(clientId);
        double currentBalance = (clientRec.data['balance'] as num).toDouble();

        await pb
            .collection('clients')
            .update(clientId, body: {'balance': currentBalance - netAmount});
      } catch (_) {}
    }

    // 4. 📝 تعليم الفاتورة أنها محذوفة
    await pb.collection('sales').update(saleId, body: {'is_deleted': true});
  }

  /// ♻️ استرجاع الفاتورة: يخصم البضاعة من المخزن ويعيد المديونية
  Future<void> restoreSale(String saleId) async {
    final sale = await pb.collection('sales').getOne(saleId);
    final items = await getSaleItems(saleId);

    // لو الفاتورة سليمة أصلاً، لا تفعل شيء
    if (sale.data['is_deleted'] == false) return;

    final isCredit = sale.data['paymentType'] != 'cash';
    final clientId = sale.data['client'];
    final netAmount = (sale.data['netAmount'] ?? 0).toDouble();

    // 1. 🔥 خصم البضاعة من المخزن مرة أخرى
    for (var item in items) {
      String prodId = item['product'] is Map
          ? item['product']['id']
          : item['product'].toString();
      int qty = (item['quantity'] as num).toInt();

      try {
        final prod = await pb.collection('products').getOne(prodId);
        int currentStock = (prod.data['stock'] as num).toInt();

        // خصم المخزون
        await pb
            .collection('products')
            .update(prodId, body: {'stock': currentStock - qty});
      } catch (_) {}
    }

    // 2. 💰 إعادة المديونية للعميل (لو آجل)
    if (isCredit && clientId != null && clientId != "") {
      try {
        final clientRec = await pb.collection('clients').getOne(clientId);
        double currentBalance = (clientRec.data['balance'] as num).toDouble();

        await pb
            .collection('clients')
            .update(clientId, body: {'balance': currentBalance + netAmount});
      } catch (_) {}
    }

    // 3. 📝 إزالة علامة الحذف
    await pb.collection('sales').update(saleId, body: {'is_deleted': false});
  }

  /// ❌ حذف نهائي (فقط يحذف السجل لأن الأثر المالي اتشال في الـ Soft Delete)
  Future<void> deleteSaleForever(String saleId) async {
    // نقوم بحذف الأصناف أولاً
    final items = await getSaleItems(saleId);
    for (var item in items) {
      await pb.collection('sale_items').delete(item['id']);
    }
    // حذف الفاتورة نفسها
    await pb.collection('sales').delete(saleId);
  }
  // ==================== إدارة سلة مهملات أذونات التسليم ====================

  // 1. جلب الأذونات المحذوفة
  Future<List<Map<String, dynamic>>> getDeletedDeliveryOrders() async {
    final records = await pb
        .collection('delivery_orders')
        .getFullList(
          filter: 'is_deleted = true',
          sort: '-updated',
          expand: 'client', // عشان نجيب اسم العميل
        );
    return records.map((r) {
      var map = PBHelper.recordToMap(r);
      map['collectionName'] = 'delivery_orders';
      return map;
    }).toList();
  }

  // 2. حذف مؤقت (نقل للسلة)
  Future<void> softDeleteDeliveryOrder(String id) async {
    await pb
        .collection('delivery_orders')
        .update(id, body: {'is_deleted': true});
  }

  // 3. استرجاع من السلة
  Future<void> restoreDeliveryOrder(String id) async {
    await pb
        .collection('delivery_orders')
        .update(id, body: {'is_deleted': false});
  }

  // 4. حذف نهائي (مع العناصر التابعة له)
  Future<void> deleteDeliveryOrderForever(String id) async {
    // حذف تفاصيل الإذن أولاً
    final items = await pb
        .collection('delivery_order_items')
        .getFullList(filter: 'delivery_order = "$id"');
    for (var item in items) {
      await pb.collection('delivery_order_items').delete(item.id);
    }
    // حذف الإذن نفسه
    await pb.collection('delivery_orders').delete(id);
  }
}
