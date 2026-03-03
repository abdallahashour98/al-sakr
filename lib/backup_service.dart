import 'dart:io';
import 'package:al_sakr/services/pb_helper.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'services/inventory_service.dart';
import 'services/purchases_service.dart';
import 'services/sales_service.dart';

// ... وهكذا
class ExcelService {
  final pbHelper = PBHelper();

  // =============================================================
  // 1️⃣ دالة التصدير الشامل (Export All Sheets)
  // =============================================================
  Future<void> exportFullBackup() async {
    try {
      var excel = Excel.createExcel();
      excel.delete('Sheet1');

      // 1. المخزن (الأصناف)
      _addSheet(
        excel,
        'المخزن',
        await InventoryService().getProducts(),
        [
          'id', // ده أصبح نص دلوقتي (String)
          'name',
          'code',
          'barcode',
          'buyPrice',
          'sellPrice',
          'stock',
          'unit', // تأكد إن الحقل ده موجود في PB
        ],
        [
          'ID',
          'اسم الصنف',
          'كود',
          'باركود',
          'سعر الشراء',
          'سعر البيع',
          'الرصيد',
          'الوحدة',
        ],
      );

      // 2. سجل المبيعات
      _addSheet(
        excel,
        'سجل المبيعات',
        await SalesService().getSales(), // ✅ دالة جديدة
        [
          'id',
          'clientName', // بيجي من expand في PBHelper
          'totalAmount',
          'discount',
          'netAmount',
          'date',
          'paymentType',
        ],
        [
          'رقم الفاتورة',
          'اسم العميل',
          'الإجمالي',
          'الخصم',
          'الصافي',
          'التاريخ',
          'طريقة الدفع',
        ],
      );

      // 3. مرتجعات المبيعات (عملاء)
      _addSheet(
        excel,
        'مرتجعات العملاء',
        await SalesService().getReturns(), // ✅ دالة جديدة
        ['id', 'sale', 'clientName', 'totalAmount', 'date'],
        [
          'رقم المرتجع',
          'رقم الفاتورة (ID)',
          'العميل',
          'المبلغ المسترد',
          'التاريخ',
        ],
      );

      // 4. سجل المشتريات
      _addSheet(
        excel,
        'سجل المشتريات',
        await PurchasesService().getPurchases(), // ✅ دالة جديدة
        [
          'id',
          'supplierName',
          'totalAmount',
          'taxAmount',
          'date',
          'referenceNumber',
        ],
        [
          'رقم الفاتورة',
          'المورد',
          'الإجمالي',
          'الضريبة',
          'التاريخ',
          'رقم المرجع',
        ],
      );

      // 5. حسابات العملاء
      _addSheet(
        excel,
        'حسابات العملاء',
        await SalesService().getClients(),
        ['id', 'name', 'phone', 'address', 'balance'],
        ['ID', 'اسم العميل', 'رقم الهاتف', 'العنوان', 'المديونية الحالية'],
      );

      // 6. حسابات الموردين
      _addSheet(
        excel,
        'حسابات الموردين',
        await PurchasesService().getSuppliers(),
        ['id', 'name', 'phone', 'contactPerson', 'balance'],
        ['ID', 'اسم المورد', 'رقم الهاتف', 'المسئول', 'المديونية الحالية'],
      );

      // 7. المصروفات
      _addSheet(
        excel,
        'المصروفات',
        await PurchasesService().getExpenses(),
        ['id', 'title', 'amount', 'category', 'date', 'notes'],
        ['ID', 'البند', 'المبلغ', 'التصنيف', 'التاريخ', 'ملاحظات'],
      );

      // --- مرحلة الحفظ والإخراج ---
      final fileBytes = excel.save();
      if (fileBytes == null) return;

      final tempDir = await getTemporaryDirectory();
      final dateStr = DateTime.now()
          .toString()
          .replaceAll(':', '-')
          .split('.')[0];
      final fileName = "تقرير_الصقر_الشامل_$dateStr.xlsx";
      final tempPath = "${tempDir.path}/$fileName";

      File(tempPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);

      if (Platform.isAndroid || Platform.isIOS) {
        await Share.shareXFiles([
          XFile(tempPath),
        ], text: 'التقرير المحاسبي الشامل - الصقر');
      } else {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'اختر مكان حفظ الملف',
          fileName: fileName,
          allowedExtensions: ['xlsx'],
          type: FileType.custom,
        );
        if (outputFile != null) {
          if (!outputFile.toLowerCase().endsWith('.xlsx'))
            outputFile = '$outputFile.xlsx';
          await File(tempPath).copy(outputFile);
        }
      }
    } catch (e) {
      debugPrint('Excel Export Error: $e');
    }
  }

  // =============================================================
  // 2️⃣ دالة الاستيراد الشامل (Import Data)
  // =============================================================
  Future<String> importFullBackup() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) return "لم يتم اختيار ملف";

      var bytes = File(result.files.single.path!).readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);

      int prodCount = 0;
      int clientCount = 0;
      int suppCount = 0;
      int expCount = 0;

      // أ. استيراد المنتجات
      var prodTable = excel.tables['المخزن'] ?? excel.tables['المنتجات'];
      if (prodTable != null) {
        for (int i = 1; i < prodTable.maxRows; i++) {
          var row = prodTable.rows[i];
          if (row.isEmpty || row[1]?.value == null) continue;
          Map<String, dynamic> data = {
            'name': row[1]?.value?.toString(),
            'code': row[2]?.value?.toString() ?? '',
            'barcode': row[3]?.value?.toString() ?? '',
            'buyPrice':
                double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0.0,
            'sellPrice':
                double.tryParse(row[5]?.value?.toString() ?? '0') ?? 0.0,
            'stock':
                double.tryParse(row[6]?.value?.toString() ?? '0') ??
                0, // Stock في PB ممكن يكون float
            'unit': row[7]?.value?.toString() ?? 'قطعة',
          };
          // بنبعت اسم الـ Collection عشان الدالة العامة تحت
          await _insertOrUpdatePB('products', row[0]?.value?.toString(), data);
          prodCount++;
        }
      }

      // ب. استيراد العملاء
      var clientTable =
          excel.tables['حسابات العملاء'] ?? excel.tables['العملاء'];
      if (clientTable != null) {
        for (int i = 1; i < clientTable.maxRows; i++) {
          var row = clientTable.rows[i];
          if (row.isEmpty || row[1]?.value == null) continue;
          Map<String, dynamic> data = {
            'name': row[1]?.value?.toString(),
            'phone': row[2]?.value?.toString() ?? '',
            'address': row[3]?.value?.toString() ?? '',
            'balance': double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0.0,
          };
          await _insertOrUpdatePB('clients', row[0]?.value?.toString(), data);
          clientCount++;
        }
      }

      // ج. استيراد الموردين
      var suppTable =
          excel.tables['حسابات الموردين'] ?? excel.tables['الموردين'];
      if (suppTable != null) {
        for (int i = 1; i < suppTable.maxRows; i++) {
          var row = suppTable.rows[i];
          if (row.isEmpty || row[1]?.value == null) continue;
          Map<String, dynamic> data = {
            'name': row[1]?.value?.toString(),
            'phone': row[2]?.value?.toString() ?? '',
            'contactPerson': row[3]?.value?.toString() ?? '',
            'balance': double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0.0,
          };
          await _insertOrUpdatePB('suppliers', row[0]?.value?.toString(), data);
          suppCount++;
        }
      }

      // د. استيراد المصروفات
      var expTable = excel.tables['المصروفات'];
      if (expTable != null) {
        for (int i = 1; i < expTable.maxRows; i++) {
          var row = expTable.rows[i];
          if (row.isEmpty || row[1]?.value == null) continue;
          Map<String, dynamic> data = {
            'title': row[1]?.value?.toString(),
            'amount': double.tryParse(row[2]?.value?.toString() ?? '0') ?? 0.0,
            'category': row[3]?.value?.toString() ?? 'عام',
            'date': row[4]?.value?.toString() ?? DateTime.now().toString(),
            'notes': row[5]?.value?.toString() ?? '',
          };
          await _insertOrUpdatePB('expenses', row[0]?.value?.toString(), data);
          expCount++;
        }
      }

      return "تم الاستيراد بنجاح ✅\n- أصناف: $prodCount\n- عملاء: $clientCount\n- موردين: $suppCount\n- مصروفات: $expCount";
    } catch (e) {
      return "خطأ أثناء الاستيراد: $e";
    }
  }

  // =============================================================
  // 🛠️ دوال مساعدة (Helper Methods)
  // =============================================================

  void _addSheet(
    Excel excel,
    String sheetName,
    List<Map<String, dynamic>> data,
    List<String> dbKeys,
    List<String> headers,
  ) {
    Sheet sheet = excel[sheetName];
    sheet.isRTL = true;

    CellStyle headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      backgroundColorHex: ExcelColor.blueGrey700,
      fontColorHex: ExcelColor.white,
    );

    for (int i = 0; i < headers.length; i++) {
      var cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, 20.0);
    }

    for (int row = 0; row < data.length; row++) {
      for (int col = 0; col < dbKeys.length; col++) {
        var value = data[row][dbKeys[col]];
        var cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
        );
        cell.cellStyle = CellStyle(horizontalAlign: HorizontalAlign.Center);

        if (value == null) {
          cell.value = TextCellValue("-");
        } else if (value is num) {
          cell.value = DoubleCellValue(value.toDouble());
        } else {
          cell.value = TextCellValue(value.toString());
        }
      }
    }
  }

  // ✅ دالة الإدخال أو التعديل المخصصة لـ PocketBase
  Future<void> _insertOrUpdatePB(
    String collection,
    String? idStr,
    Map<String, dynamic> data,
  ) async {
    // 1. لو فيه ID وجاي من PocketBase (نص طويل 15 حرف)، نحاول نعدل عليه
    if (idStr != null && idStr.length > 5) {
      try {
        await PBHelper().pb.collection(collection).update(idStr, body: data);
        return; // لو نجح التعديل نخرج
      } catch (e) {
        // لو فشل (مش موجود)، كمل عشان ينشئه جديد
      }
    }

    // 2. لو مفيش ID، أو الـ ID كان رقم قديم من SQLite (مش هينفع نستخدمه كـ ID في PB)
    // هننشئ سجل جديد
    await PBHelper().pb.collection(collection).create(body: data);
  }
}
