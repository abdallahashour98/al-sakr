import 'inventory_service.dart';
import 'pb_helper.dart';
import 'purchases_service.dart';
import 'sales_service.dart';

class ReportsService {
  final pb = PBHelper().pb;
  // ✅ جلب البيانات مع فلتر التاريخ
  Future<Map<String, double>> getGeneralReportData({
    String? startDate,
    String? endDate,
  }) async {
    // 1. جلب البيانات من الخدمات بفلتر التاريخ
    final sales = await SalesService().getSales(
      startDate: startDate,
      endDate: endDate,
    );
    final returns = await SalesService().getReturns(
      startDate: startDate,
      endDate: endDate,
    );
    final expenses = await SalesService().getExpenses(
      startDate: startDate,
      endDate: endDate,
    );

    final purchases = await PurchasesService().getPurchases(
      startDate: startDate,
      endDate: endDate,
    );
    final purchaseReturns = await PurchasesService().getAllPurchaseReturns(
      startDate: startDate,
      endDate: endDate,
    );
    final supplierPayments = await PurchasesService()
        .getAllSupplierPayments(); // يحتاج فلترة يدوية لو السيرفس مفيهوش فلتر

    // 2. تجميع الأرقام
    // أ. المبيعات (نستخدم netAmount لأنه الأهم)
    double totalSales = sales.fold(
      0.0,
      (sum, item) =>
          sum + ((item['netAmount'] ?? item['totalAmount']) as num).toDouble(),
    );

    // ب. مرتجعات العملاء
    double totalClientReturns = returns.fold(
      0.0,
      (sum, item) => sum + (item['totalAmount'] as num).toDouble(),
    );

    // ج. المصروفات
    double totalExpenses = expenses.fold(
      0.0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    // د. فواتير المشتريات
    double totalPurchasesBills = purchases.fold(
      0.0,
      (sum, item) => sum + (item['totalAmount'] as num).toDouble(),
    );

    // هـ. مرتجعات الموردين
    double totalSupplierReturns = purchaseReturns.fold(
      0.0,
      (sum, item) => sum + (item['totalAmount'] as num).toDouble(),
    );

    // و. مدفوعات الموردين (فلترة يدوية للتأكيد)
    double totalSupplierPayments = 0.0;
    if (startDate != null && endDate != null) {
      DateTime start = DateTime.parse(startDate);
      DateTime end = DateTime.parse(endDate);
      for (var p in supplierPayments) {
        // تأكد من وجود حقل date في المدفوعات
        if (p['date'] != null) {
          DateTime pDate = DateTime.parse(p['date']);
          if (pDate.isAfter(start) && pDate.isBefore(end)) {
            totalSupplierPayments += (p['amount'] as num).toDouble();
          }
        }
      }
    } else {
      totalSupplierPayments = supplierPayments.fold(
        0.0,
        (sum, item) => sum + (item['amount'] as num).toDouble(),
      );
    }

    // ز. قيمة المخزون (تراكمية - لا تتأثر بالفلتر)
    // ✅ هنا نستدعي الدالة اللي لسه ضايفينها في InventoryService
    double inventoryVal = 0.0;
    try {
      // تأكد من عمل import لـ inventory_service.dart
      inventoryVal = await InventoryService().getInventoryValue();
    } catch (_) {}

    return {
      'monthlySales': totalSales,
      'clientReturns': totalClientReturns,
      'monthlyReturns': totalClientReturns, // نفس القيمة
      'monthlyExpenses': totalExpenses,
      'monthlyBills': totalPurchasesBills,
      'supplierReturns': totalSupplierReturns,
      'monthlyPayments': totalSupplierPayments,
      'inventory': inventoryVal,
      'receivables': 0.0, // يمكن إضافتها لاحقاً من ClientService
      'payables': 0.0, // يمكن إضافتها لاحقاً من SupplierService
    };
  }
}
