import 'package:flutter/material.dart';
import 'services/sales_service.dart';
// ✅ تأكد من استيراد ملفات الطباعة وشاشة البيع
import 'package:al_sakr/pdf/invoice_pdf_service.dart';
import 'sales_screen.dart';

class ReportsScreen extends StatefulWidget {
  final DateTime? initialDate;
  const ReportsScreen({super.key, this.initialDate});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _selectedDate;
  List<Map<String, dynamic>> _monthlySales = [];
  Map<String, List<Map<String, dynamic>>> _groupedSales = {};

  // خرائط التتبع
  Map<String, double> _invoiceReturnsTotalMap = {};
  Map<String, double> _invoiceReturnsPaidMap = {};

  // الإجماليات
  double _totalNetSalesForMonth = 0.0;
  double _totalReturnsForMonth = 0.0;
  double _totalExpensesForMonth = 0.0;
  double _netMovementForMonth = 0.0;

  bool _isLoading = true;

  // ✅ الصلاحيات (مفعلة افتراضياً لتظهر لك، ويتم تحديثها من الداتا بيز)
  bool _canAddReturn = true;
  bool _canDelete = true;
  final String _superAdminId = "1sxo74splxbw1yh";

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _loadPermissions();
    _loadData();
  }

  Future<void> _loadPermissions() async {
    // ✅ 1. تفعيل الحذف والتعديل إجبارياً للجميع (مؤقتاً للتجربة)
    if (mounted) {
      setState(() {
        _canAddReturn = true;
        _canDelete = true; // 👈 خليناها True دائماً عشان الأزرار تظهر
      });
    }

    // الكود القديم (تم إيقافه مؤقتاً عشان الأزرار تظهر)
    /*
    final myId = PBHelper().pb.authStore.record?.id;
    if (myId == null) return;

    if (myId == _superAdminId) {
      if (mounted) setState(() { _canAddReturn = true; _canDelete = true; });
      return;
    }

    try {
      final userRecord = await PBHelper().pb.collection('users').getOne(myId);
      if (mounted) {
        setState(() {
          _canAddReturn = userRecord.data['allow_add_returns'] ?? false;
          _canDelete = userRecord.data['allow_delete_invoices'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Error permissions: $e");
    }
    */
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month + offset,
        1,
      );
      _isLoading = true;
    });
    _loadData();
  }

  void _loadData() async {
    DateTime startOfMonth = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      1,
    );
    DateTime endOfMonth = DateTime(
      _selectedDate.year,
      _selectedDate.month + 1,
      0,
      23,
      59,
      59,
    );

    String startStr = startOfMonth.toIso8601String();
    String endStr = endOfMonth.toIso8601String();

    try {
      final salesData = await SalesService().getSales(
        startDate: startStr,
        endDate: endStr,
      );
      final returnsThisMonth = await SalesService().getReturns(
        startDate: startStr,
        endDate: endStr,
      );
      final expensesData = await SalesService().getExpenses(
        startDate: startStr,
        endDate: endStr,
      );
      final allReturnsForStatus = await SalesService().getReturns();

      double totalSalesNet = 0.0;
      Map<String, List<Map<String, dynamic>>> grouped = {};

      for (var sale in salesData) {
        String clientName = sale['clientName'] ?? 'عميل غير معروف';
        grouped.putIfAbsent(clientName, () => []).add(sale);

        double net = (sale['netAmount'] as num? ?? sale['totalAmount'])
            .toDouble();
        totalSalesNet += net;
      }

      double totalReturnsValue = returnsThisMonth.fold(
        0.0,
        (sum, item) => sum + (item['totalAmount'] as num).toDouble(),
      );
      double totalExpensesValue = expensesData.fold(
        0.0,
        (sum, item) => sum + (item['amount'] as num).toDouble(),
      );

      Map<String, double> invReturnsTotal = {};
      Map<String, double> invReturnsPaid = {};

      for (var ret in allReturnsForStatus) {
        String saleId = (ret['sale'] is Map)
            ? ret['sale']['id']
            : (ret['sale']?.toString() ?? '');
        if (saleId.isNotEmpty) {
          double total = (ret['totalAmount'] as num?)?.toDouble() ?? 0.0;
          double paid = (ret['paidAmount'] as num?)?.toDouble() ?? 0.0;
          invReturnsTotal[saleId] = (invReturnsTotal[saleId] ?? 0.0) + total;
          invReturnsPaid[saleId] = (invReturnsPaid[saleId] ?? 0.0) + paid;
        }
      }

      if (mounted) {
        setState(() {
          _monthlySales = salesData;
          _groupedSales = grouped;
          _invoiceReturnsTotalMap = invReturnsTotal;
          _invoiceReturnsPaidMap = invReturnsPaid;
          _totalNetSalesForMonth = totalSalesNet;
          _totalReturnsForMonth = totalReturnsValue;
          _totalExpensesForMonth = totalExpensesValue;
          _netMovementForMonth =
              (_totalNetSalesForMonth - _totalReturnsForMonth) -
              _totalExpensesForMonth;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String fmt(dynamic number) {
    if (number == null) return "0.00";
    if (number is num) return number.toDouble().toStringAsFixed(2);
    return double.tryParse(number.toString())?.toStringAsFixed(2) ?? "0.00";
  }

  String _getMonthName(int month) {
    const months = [
      "يناير",
      "فبراير",
      "مارس",
      "أبريل",
      "مايو",
      "يونيو",
      "يوليو",
      "أغسطس",
      "سبتمبر",
      "أكتوبر",
      "نوفمبر",
      "ديسمبر",
    ];
    return months[month - 1];
  }

  // ============================================================
  // ⚙️ العمليات (تعديل، حذف، طباعة)
  // ============================================================

  // 1. تعديل الفاتورة (حذف القديم + فتح شاشة البيع)
  // تعديل الفاتورة (بدون حذف مسبق)// ✅ دالة تعديل الفاتورة (ضعها قبل Widget build)
  // ✅ دالة تعديل الفاتورة (تضاف في reports_screen.dart)
  Future<void> _modifyInvoice(Map<String, dynamic> sale) async {
    // 1. فحص هل يوجد مرتجع لهذه الفاتورة؟
    double returnedTotal = _invoiceReturnsTotalMap[sale['id']] ?? 0.0;

    if (returnedTotal > 0) {
      // ⛔ منع التعديل وإظهار رسالة
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("تنبيه هام"),
          content: const Text(
            "لا يمكن تعديل هذه الفاتورة لأن لها مرتجعات سابقة.\n\nيرجى حذف المرتجع أولاً.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("موافق"),
            ),
          ],
        ),
      );
      return;
    }

    // 2. البدء في التعديل
    setState(() => _isLoading = true);

    try {
      final items = await SalesService().getSaleItems(sale['id']);

      setState(() => _isLoading = false);

      if (!mounted) return;

      // الذهاب لشاشة البيع (SalesScreen) مع بيانات الفاتورة
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SalesScreen(
            oldSaleData: sale, // 👈 بنبعت الفاتورة القديمة هنا
            initialItems: items, // 👈 وبنبعت الأصناف هنا
          ),
        ),
      );

      _loadData(); // تحديث الشاشة عند العودة
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    }
  }

  // 2. حذف الفاتورة نهائياً
  // 2. حذف الفاتورة (نقل لسلة المهملات)
  Future<void> _deleteInvoice(String saleId) async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("نقل لسلة المهملات"), // غيرنا العنوان
            content: const Text(
              "هل أنت متأكد؟ سيتم نقل الفاتورة للسلة واسترجاع المخزن مؤقتاً.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("إلغاء"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("حذف", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      try {
        // ✅✅ التغيير المهم هنا: استدعاء دالة الحذف المؤقت ✅✅
        await SalesService().softDeleteSale(saleId);

        // تحديث القائمة لإخفاء الفاتورة المحذوفة
        _loadData();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم نقل الفاتورة لسلة المهملات 🗑️"),
            backgroundColor: Colors.orange, // لون مميز للحذف المؤقت
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
      }
    }
  } // 3. الطباعة

  Future<void> _printInvoice(Map<String, dynamic> sale) async {
    try {
      final items = await SalesService().getSaleItems(sale['id']);
      await InvoicePdfService.generateInvoice(sale, items);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("خطأ الطباعة: $e")));
    }
  }

  // ============================================================
  // 🎨 بناء الكارت (نفس التصميم القديم بالضبط)
  // ============================================================

  Widget _buildInvoiceCard(Map<String, dynamic> sale, bool isDark) {
    double itemsTotal = (sale['totalAmount'] as num).toDouble();
    double discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
    double tax = (sale['taxAmount'] as num?)?.toDouble() ?? 0.0;

    // ✅ استخراج خصم المنبع (1%)
    double wht = (sale['whtAmount'] as num?)?.toDouble() ?? 0.0;

    double finalNet = (itemsTotal - discount) + tax - wht;

    double returnedTotal = _invoiceReturnsTotalMap[sale['id']] ?? 0.0;
    bool isFullyReturned = (returnedTotal >= finalNet - 0.1) && finalNet > 0;

    bool isCashSale = (sale['paymentType'] == 'cash');

    String refNumber = sale['referenceNumber']?.toString() ?? '';
    String displayId = refNumber.isNotEmpty
        ? "#$refNumber"
        : "#${sale['id'].toString().substring(0, 5)}";

    return Card(
      elevation: 0,
      color: isDark ? Colors.grey[800] : Colors.grey[100],
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        title: Row(
          children: [
            Expanded(
              child: Text(
                "فاتورة $displayId",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isFullyReturned ? Colors.red : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isCashSale
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isCashSale ? "كاش" : "آجل",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isCashSale ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          "الصافي: ${fmt(finalNet)} ج.م",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),

        // ✅✅ القائمة (3 نقاط) - تم إضافة الخيارات المفقودة
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.blue),
          onSelected: (value) {
            if (value == 'edit_id') _showEditRefDialog(sale);
            if (value == 'modify') _modifyInvoice(sale);
            if (value == 'return') _showReturnDialog(sale);
            if (value == 'delete') _deleteInvoice(sale['id']); // حذف الفاتورة
            if (value == 'print') _printInvoice(sale);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'print',
              child: Row(
                children: [
                  Icon(Icons.print, color: Colors.grey),
                  SizedBox(width: 8),
                  Text("طباعة PDF"),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit_id',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue),
                  SizedBox(width: 8),
                  Text("تعديل رقم الفاتورة"),
                ],
              ),
            ),

            // ✅ خيار تعديل الأصناف (يظهر إذا كان هناك صلاحية)
            if (_canDelete)
              const PopupMenuItem(
                value: 'modify',
                child: Row(
                  children: [
                    Icon(Icons.edit_note, color: Colors.orange),
                    SizedBox(width: 8),
                    Text("تعديل الأصناف"),
                  ],
                ),
              ),

            // ✅ خيار المرتجع
            if (_canAddReturn && !isFullyReturned)
              const PopupMenuItem(
                value: 'return',
                child: Row(
                  children: [
                    Icon(Icons.assignment_return, color: Colors.purple),
                    SizedBox(width: 8),
                    Text("عمل مرتجع"),
                  ],
                ),
              ),

            // ✅ خيار الحذف
            if (_canDelete)
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red),
                    SizedBox(width: 8),
                    Text("حذف الفاتورة"),
                  ],
                ),
              ),
          ],
        ),

        // ✅✅ الجسم الداخلي (عرض التفاصيل + إضافة ضريبة الـ 1%)
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.white,
            ),
            child: Column(
              children: [
                _buildInfoRow("إجمالي الأصناف", "${fmt(itemsTotal)} ج.م"),
                if (discount > 0)
                  _buildInfoRow(
                    "الخصم",
                    "-${fmt(discount)} ج.م",
                    color: Colors.red,
                  ),
                if (tax > 0)
                  _buildInfoRow(
                    "الضريبة (14%)",
                    "+${fmt(tax)} ج.م",
                    color: Colors.orange,
                  ),

                // ✅ عرض خصم المنبع إذا وجد
                if (wht > 0)
                  _buildInfoRow(
                    "خصم منبع (1%)",
                    "-${fmt(wht)} ج.م",
                    color: Colors.purple,
                  ),

                const Divider(),
                _buildInfoRow(
                  "الإجمالي النهائي",
                  "${fmt(finalNet)} ج.م",
                  isBold: true,
                  size: 15,
                  color: isDark ? Colors.tealAccent : Colors.teal,
                ),
                if (returnedTotal > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    padding: const EdgeInsets.all(5),
                    color: Colors.red.withOpacity(0.1),
                    child: _buildInfoRow(
                      "مرتجعات سابقة",
                      "-${fmt(returnedTotal)} ج.م",
                      color: Colors.red,
                      isBold: true,
                    ),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showItemsBottomSheet(sale),
                    icon: const Icon(Icons.list, size: 16),
                    label: const Text("عرض قائمة الأصناف والتفاصيل"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? color,
    bool isBold = false,
    double size = 13,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: size),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: size,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 📋 عرض التفاصيل في الأسفل (Bottom Sheet)
  // ============================================================
  void _showItemsBottomSheet(Map<String, dynamic> sale) async {
    final items = await SalesService().getSaleItems(sale['id']);
    if (!mounted) return;

    double total = (sale['totalAmount'] ?? 0).toDouble();
    double discount = (sale['discount'] ?? 0).toDouble();
    double tax = (sale['taxAmount'] ?? 0).toDouble();
    // ✅ استخراج خصم المنبع للعرض في القائمة التفصيلية
    double wht = (sale['whtAmount'] ?? 0).toDouble();
    double net = (sale['netAmount'] ?? 0).toDouble();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (context, scrollController) => Container(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              const Center(
                child: Text(
                  "تفاصيل الفاتورة",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ...items
                  .map(
                    (item) => ListTile(
                      title: Text(item['productName'] ?? 'صنف'),
                      subtitle: Text("${item['quantity']} x ${item['price']}"),
                      trailing: Text(
                        "${(item['quantity'] * item['price']).toStringAsFixed(1)} ج.م",
                      ),
                    ),
                  )
                  .toList(),
              const Divider(),
              _buildSummaryRow("الإجمالي", total),
              if (discount > 0)
                _buildSummaryRow("الخصم", -discount, color: Colors.red),
              if (tax > 0)
                _buildSummaryRow("ضريبة (14%)", tax, color: Colors.orange),

              // ✅ سطر خصم المنبع 1%
              if (wht > 0)
                _buildSummaryRow("خصم منبع (1%)", -wht, color: Colors.purple),

              const Divider(),
              _buildSummaryRow(
                "الصافي النهائي",
                net,
                isBold: true,
                scale: 1.2,
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    double val, {
    Color? color,
    bool isBold = false,
    double scale = 1.0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 14 * scale,
            ),
          ),
          Text(
            "${val.toStringAsFixed(2)} ج.م",
            style: TextStyle(
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: 14 * scale,
            ),
          ),
        ],
      ),
    );
  }

  // --- دوال الديالوج ---

  void _showEditRefDialog(Map<String, dynamic> sale) {
    final refController = TextEditingController(
      text: sale['referenceNumber']?.toString() ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تعديل رقم الفاتورة"),
        content: TextField(
          controller: refController,
          decoration: const InputDecoration(labelText: "رقم الفاتورة اليدوي"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () async {
              await SalesService().updateSaleReference(
                sale['id'],
                refController.text,
              );
              Navigator.pop(ctx);
              _loadData();
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  void _showReturnDialog(Map<String, dynamic> sale) async {
    // 1. فحص الصلاحية
    if (!_canAddReturn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ليس لديك صلاحية عمل مرتجع")),
      );
      return;
    }

    // عرض لودينج
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // جلب البيانات
    final items = await SalesService().getSaleItems(sale['id']);
    final previouslyReturnedMap = await SalesService().getAlreadyReturnedItems(
      sale['id'],
    );

    Navigator.pop(context); // إغلاق اللودينج

    Map<String, int> returnQuantities = {};
    for (var item in items) {
      returnQuantities[item['id']] = 0;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateSB) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          // ✅ الحصول على أبعاد الشاشة لجعل الديالوج متجاوباً
          final screenHeight = MediaQuery.of(context).size.height;
          final screenWidth = MediaQuery.of(context).size.width;

          // --- الحسابات (نفس المنطق السابق) ---
          double grossReturnTotal = 0;
          List<Map<String, dynamic>> itemsToReturn = [];

          for (var item in items) {
            String itemId = item['id'];
            int qty = returnQuantities[itemId] ?? 0;
            if (qty > 0) {
              double price = (item['price'] as num).toDouble();
              grossReturnTotal += qty * price;

              String prodId = '';
              if (item['product'] is Map)
                prodId = item['product']['id'];
              else if (item['expand'] != null &&
                  item['expand']['product'] != null)
                prodId = item['expand']['product']['id'];
              else
                prodId = item['product'] ?? item['productId'];

              itemsToReturn.add({
                'productId': prodId,
                'quantity': qty,
                'price': price,
              });
            }
          }

          double saleItemsTotal = (sale['totalAmount'] as num).toDouble();
          double saleDiscount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
          double discountRatio = (saleItemsTotal > 0)
              ? (saleDiscount / saleItemsTotal)
              : 0;
          double returnDiscountShare = grossReturnTotal * discountRatio;
          double netReturnBeforeTax = grossReturnTotal - returnDiscountShare;
          double returnTaxShare = (sale['taxAmount'] ?? 0) > 0
              ? netReturnBeforeTax * 0.14
              : 0.0;
          double returnWhtShare = (sale['whtAmount'] ?? 0) > 0
              ? netReturnBeforeTax * 0.01
              : 0.0;
          double finalReturnTotal =
              netReturnBeforeTax + returnTaxShare - returnWhtShare;

          return Dialog(
            // ✅ تقليل الحواف الجانبية في الموبايل
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            child: Container(
              padding: const EdgeInsets.all(15),
              // ✅ تحديد الارتفاع كنسبة من الشاشة (80%) لمنع الـ Overflow
              width: screenWidth > 600
                  ? 500
                  : screenWidth, // عرض كامل للموبايل ومحدد للتابلت
              height: screenHeight * 0.85,

              child: Column(
                children: [
                  // 1. العنوان (ثابت)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.assignment_return,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        "مرتجع فاتورة",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // 2. قائمة الأصناف (✅ Expanded يجعلها تأخذ المساحة المتبقية وتقبل السكرول)
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text("لا توجد أصناف"))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (c, i) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) {
                              final item = items[i];
                              int originalQty = (item['quantity'] as num)
                                  .toInt();
                              String prodIdKey = '';
                              if (item['product'] is Map)
                                prodIdKey = item['product']['id'];
                              else if (item['expand'] != null)
                                prodIdKey = item['expand']['product']['id'];
                              else
                                prodIdKey = item['product'] ?? '';

                              int returnedBefore =
                                  previouslyReturnedMap[prodIdKey] ?? 0;
                              int available = originalQty - returnedBefore;
                              if (available < 0) available = 0;

                              int currentQty =
                                  returnQuantities[item['id']] ?? 0;

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: currentQty > 0
                                        ? Colors.red.withOpacity(0.5)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // الصف العلوي: الاسم والسعر
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item['productName'] ?? '---',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          "${item['price']} ج.م",
                                          style: TextStyle(
                                            color: Colors.blue[700],
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // الصف السفلي: العداد والمتاح
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "متاح: $available",
                                          style: TextStyle(
                                            color: available == 0
                                                ? Colors.red
                                                : Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                        // أزرار العداد
                                        Container(
                                          height: 35,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.black26
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: Colors.grey.withOpacity(
                                                0.3,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildCounterBtn(
                                                Icons.remove,
                                                isDark,
                                                () {
                                                  if (currentQty > 0)
                                                    setStateSB(
                                                      () =>
                                                          returnQuantities[item['id']] =
                                                              currentQty - 1,
                                                    );
                                                },
                                              ),
                                              Container(
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 25,
                                                    ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  "$currentQty",
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              _buildCounterBtn(
                                                Icons.add,
                                                isDark,
                                                available == 0 ||
                                                        currentQty >= available
                                                    ? null
                                                    : () {
                                                        if (currentQty <
                                                            available)
                                                          setStateSB(
                                                            () =>
                                                                returnQuantities[item['id']] =
                                                                    currentQty +
                                                                    1,
                                                          );
                                                      },
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  const SizedBox(height: 10),

                  // 3. الفوتر (ثابت في الأسفل)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey[50],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "إجمالي المرتجع:",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              "${finalReturnTotal.toStringAsFixed(2)} ج.م",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 45,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: finalReturnTotal <= 0
                                ? null
                                : () async {
                                    try {
                                      Navigator.pop(ctx);
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (_) => const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );

                                      await SalesService().createReturn(
                                        sale['id'],
                                        sale['client'],
                                        finalReturnTotal,
                                        itemsToReturn,
                                        discount: returnDiscountShare,
                                      );

                                      if (mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text("تم المرتجع بنجاح ✅"),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                        _loadData();
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text("خطأ: $e"),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            child: const Text(
                              "تأكيد المرتجع",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Helper للزر الصغير
  Widget _buildCounterBtn(IconData icon, bool isDark, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null
              ? Colors.grey
              : (isDark ? Colors.white : Colors.black),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color profitColor = _netMovementForMonth >= 0 ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المبيعات'),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.arrow_back_ios, size: 18),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Text(
                  "${_getMonthName(_selectedDate.month)} ${_selectedDate.year}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.arrow_forward_ios, size: 18),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            color: isDark
                ? const Color(0xFF1E1E1E)
                : const Color.fromARGB(255, 9, 38, 62),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text(
                      "إجمالي مبيعات الشهر",
                      style: TextStyle(color: Colors.white70),
                    ),
                    Text(
                      "${fmt(_totalNetSalesForMonth)} ج.م",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(height: 30, width: 1, color: Colors.white24),
                Column(
                  children: [
                    const Text(
                      "عدد الفواتير",
                      style: TextStyle(color: Colors.white70),
                    ),
                    Text(
                      "${_monthlySales.length}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _groupedSales.isEmpty
                ? const Center(child: Text("لا توجد مبيعات"))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _groupedSales.keys.length,
                    itemBuilder: (context, index) {
                      String clientName = _groupedSales.keys.elementAt(index);
                      List<Map<String, dynamic>> invoices =
                          _groupedSales[clientName]!;
                      return Card(
                        child: ExpansionTile(
                          title: Text(
                            clientName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text("${invoices.length} فواتير"),
                          children: invoices
                              .map((sale) => _buildInvoiceCard(sale, isDark))
                              .toList(),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "صافي حركة الشهر:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "${fmt(_netMovementForMonth)} ج.م",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: profitColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
