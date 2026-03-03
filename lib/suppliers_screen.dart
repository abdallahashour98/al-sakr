import 'package:al_sakr/services/pb_helper.dart';
import 'package:al_sakr/services/purchases_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'services/auth_service.dart';
import 'supplier_dialog.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<Map<String, dynamic>> _allPurchases = [];
  List<Map<String, dynamic>> _allPayments = [];
  double _totalPurchases = 0.0;
  double _totalPaid = 0.0;

  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // ✅ متغير الستريم الثابت
  late Stream<List<Map<String, dynamic>>> _suppliersStream;

  bool _canAdd = false;
  bool _canEdit = false;
  bool _canDelete = false;

  final String _superAdminId = "1sxo74splxbw1yh";

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadStaticStats();
    // ✅ تهيئة الستريم مرة واحدة
    _suppliersStream = PBHelper().getCollectionStream(
      'suppliers',
      sort: 'name',
    );
  }

  Future<void> _loadPermissions() async {
    final myId = AuthService().pb.authStore.record?.id;
    if (myId == null) return;

    if (myId == _superAdminId) {
      if (mounted) {
        setState(() {
          _canAdd = true;
          _canEdit = true;
          _canDelete = true;
        });
      }
      return;
    }

    try {
      final userRecord = await AuthService().pb
          .collection('users')
          .getOne(myId);
      if (mounted) {
        setState(() {
          _canAdd = userRecord.data['allow_add_clients'] ?? false;
          _canEdit =
              (userRecord.data['allow_add_clients'] ?? false) ||
              (userRecord.data['allow_edit_clients'] ?? false);
          _canDelete = userRecord.data['allow_delete_clients'] ?? false;
        });
      }
    } catch (e) {
      debugPrint("Error loading permissions: $e");
    }
  }

  Future<void> _loadStaticStats() async {
    try {
      final purchases = await PurchasesService().getPurchases();
      final payments = await PurchasesService().getAllSupplierPayments();
      if (mounted) {
        setState(() {
          _allPurchases = purchases;
          _allPayments = payments;
          _calculateStaticDashboard();
        });
      }
    } catch (e) {
      print(e);
    }
  }

  void _calculateStaticDashboard() {
    double tPurchases = 0.0;
    double tPaid = 0.0;
    for (var bill in _allPurchases)
      tPurchases += (bill['totalAmount'] as num? ?? 0.0);
    for (var pay in _allPayments) tPaid += (pay['amount'] as num? ?? 0.0);
    setState(() {
      _totalPurchases = tPurchases;
      _totalPaid = tPaid;
    });
  }

  void _showSupplierDialog({Map<String, dynamic>? supplier}) async {
    if (supplier == null && !_canAdd) return;
    if (supplier != null && !_canEdit) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SupplierDialog(supplier: supplier),
    );
  }

  void _deleteSupplier(String id) {
    if (!_canDelete) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف المورد"),
        content: const Text("هل تريد نقل هذا المورد إلى سلة المهملات؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await PurchasesService().deleteSupplier(id);
                _loadStaticStats();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("تم نقل المورد للسلة ♻️")),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
              }
            },
            child: const Text(
              "نقل للسلة",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('إدارة الموردين'), centerTitle: true),
      // ✅ استخدام الستريم الثابت
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _suppliersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text("خطأ: ${snapshot.error}"));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final allSuppliers = snapshot.data!;
          final filtered = allSuppliers.where((s) {
            if (s['is_deleted'] == true) return false;
            return _searchQuery.isEmpty ||
                s['name'].toString().toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();

          double totalDebt = 0.0;
          for (var s in filtered) {
            double bal = (s['balance'] as num? ?? 0.0).toDouble();
            if (bal > 0) totalDebt += bal;
          }
          filtered.sort(
            (a, b) => (b['balance'] as num).compareTo(a['balance'] as num),
          );

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: isDark ? const Color(0xFF1A1A1A) : Colors.brown[50],
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 2000),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _summaryCard(
                              "إجمالي المشتريات",
                              _totalPurchases,
                              Colors.orange,
                              Icons.shopping_cart,
                              isDark,
                            ),
                            const SizedBox(width: 8),
                            _summaryCard(
                              "إجمالي المدفوعات",
                              _totalPaid,
                              Colors.green,
                              Icons.payment,
                              isDark,
                            ),
                            const SizedBox(width: 8),
                            _summaryCard(
                              "المستحق للموردين",
                              totalDebt,
                              Colors.red,
                              Icons.warning,
                              isDark,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchController,
                          // ✅ تحديث الحالة عند البحث ليعيد بناء الـ Builder فقط
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: "بحث...",
                            hintStyle: TextStyle(color: subColor),
                            prefixIcon: Icon(Icons.search, color: subColor),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2C2C2C)
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, top: 10),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, index) {
                    final s = filtered[index];
                    double bal = (s['balance'] as num? ?? 0.0).toDouble();

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 2000),
                        child: Card(
                          color: cardColor,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: bal > 0
                                  ? Colors.red.withOpacity(0.2)
                                  : Colors.green.withOpacity(0.2),
                              child: Text(
                                s['name'][0].toUpperCase(),
                                style: TextStyle(
                                  color: bal > 0 ? Colors.red : Colors.green,
                                ),
                              ),
                            ),
                            title: Text(
                              s['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            subtitle: Text(
                              "ت: ${s['phone'] ?? '-'}",
                              style: TextStyle(color: subColor),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      "${bal.abs().toStringAsFixed(1)} ج.م",
                                      style: TextStyle(
                                        color: bal > 0
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      bal > 0 ? "له" : "لنا",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: subColor,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_canEdit || _canDelete)
                                  PopupMenuButton<String>(
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: subColor,
                                    ),
                                    onSelected: (value) {
                                      if (value == 'edit')
                                        _showSupplierDialog(supplier: s);
                                      if (value == 'delete')
                                        _deleteSupplier(s['id']);
                                    },
                                    itemBuilder: (c) => [
                                      if (_canEdit)
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(width: 10),
                                              Text('تعديل'),
                                            ],
                                          ),
                                        ),
                                      if (_canDelete)
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                              SizedBox(width: 10),
                                              Text('حذف'),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SupplierDetailScreen(supplier: s),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _canAdd
          ? FloatingActionButton.extended(
              onPressed: () => _showSupplierDialog(),
              label: const Text(
                "مورد جديد",
                style: TextStyle(color: Colors.white),
              ),
              icon: const Icon(Icons.add, color: Colors.white),
              backgroundColor: Colors.brown[700],
            )
          : null,
    );
  }

  Widget _summaryCard(
    String title,
    double amount,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? color.withOpacity(0.15) : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 5),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              NumberFormat.compact().format(amount),
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------
// بقية كود SupplierDetailScreen
// (يفضل تركه كما هو أو تطبيق نفس المنطق إذا كان هناك بحث داخلي ثقيل)
// ---------------------------------------------
// =============================================================================
// شاشة التفاصيل (SupplierDetailScreen) - النسخة المحسنة
// =============================================================================

class SupplierDetailScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;
  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  bool _loading = true;
  String _filterType = "الكل";
  DateTimeRange? _dateRange;
  double _currentVisibleBalance = 0.0;

  // صلاحيات
  bool _canAddPayment = false;
  bool _canManagePayments = false; // للتعديل والحذف
  final String _superAdminId = "1sxo74splxbw1yh";

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadDetails();
  }

  Future<void> _loadPermissions() async {
    final myId = PBHelper().pb.authStore.record?.id;
    if (myId == null) return;
    if (myId == _superAdminId) {
      if (mounted)
        setState(() {
          _canAddPayment = true;
          _canManagePayments = true;
        });
      return;
    }
    try {
      final userRecord = await PBHelper().pb.collection('users').getOne(myId);
      if (mounted) {
        setState(() {
          _canAddPayment = (userRecord.data['allow_add_purchases'] ?? false);
          // افترضنا أن صلاحية حذف العملاء تعطي صلاحية حذف الموردين (أو يمكنك إضافة حقل جديد في الداتا بيز)
          _canManagePayments =
              (userRecord.data['allow_delete_clients'] ?? false);
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _loadDetails() async {
    setState(() => _loading = true);
    final purchases = await PurchasesService().getSupplierStatement(
      widget.supplier['id'],
    );
    final openingBal = await PurchasesService().getSupplierOpeningBalance(
      widget.supplier['id'],
    );

    List<Map<String, dynamic>> temp = [];
    for (var item in purchases) {
      double amount = (item['amount'] as num).toDouble();
      bool isBill =
          item['type'] ==
          'bill'; // الفاتورة = دين علينا (Debit/Credit logic here depends on perspective)

      // بالنسبة للمورد:
      // فاتورة شراء (Bill) -> تزيد المديونية (علينا)
      // سند دفع (Payment) -> تقلل المديونية (سددنا)
      // مرتجع شراء (Return) -> تقلل المديونية (رجعنا بضاعة)

      temp.add({
        'id': item['id'],
        'date': item['date'],
        'type': isBill
            ? "فاتورة شراء"
            : (item['type'] == 'return' ? "مرتجع شراء" : "سند دفع"),
        'amount': amount,
        'isDebit': isBill, // True = تزيد الرصيد، False = تنقص الرصيد
        'category': isBill
            ? "فواتير"
            : (item['type'] == 'return' ? "مرتجع" : "دفعات"),
        'rawDate': DateTime.parse(item['date']),
        'rawRecord': item, // للاستخدام في التعديل
      });
    }

    temp.sort((a, b) => (a['rawDate'] as DateTime).compareTo(b['rawDate']));

    List<Map<String, dynamic>> calculatedList = [];
    double runningBalance = openingBal;

    for (var t in temp) {
      if (t['isDebit']) {
        runningBalance += t['amount']; // فاتورة -> الدين يزيد
      } else {
        runningBalance -= t['amount']; // دفع أو مرتجع -> الدين يقل
      }
      t['runningBalance'] = runningBalance;
      calculatedList.add(t);
    }

    _applyFilters(calculatedList, openingBal);
  }

  void _applyFilters(
    List<Map<String, dynamic>> fullList,
    double initialOpening,
  ) {
    List<Map<String, dynamic>> result = [];
    double startBalance = initialOpening;

    if (_dateRange != null) {
      final beforeRange = fullList
          .where((t) => (t['rawDate'] as DateTime).isBefore(_dateRange!.start))
          .toList();
      if (beforeRange.isNotEmpty)
        startBalance = beforeRange.last['runningBalance'];
      result = fullList.where((t) {
        final d = t['rawDate'] as DateTime;
        return d.isAfter(
              _dateRange!.start.subtract(const Duration(seconds: 1)),
            ) &&
            d.isBefore(_dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    } else {
      result = fullList;
    }

    List<Map<String, dynamic>> finalDisplay = [];
    finalDisplay.add({
      'type': 'رصيد سابق',
      'amount': startBalance.abs(),
      'isDebit': startBalance >= 0,
      'runningBalance': startBalance,
      'isHeader': true,
      'category': 'الكل',
      'date': '---',
    });

    finalDisplay.addAll(result);

    if (_filterType != "الكل") {
      finalDisplay = finalDisplay
          .where((t) => t['category'] == _filterType || t['isHeader'] == true)
          .toList();
    }

    if (mounted) {
      setState(() {
        _allTransactions = fullList;
        _filteredTransactions = finalDisplay;
        _currentVisibleBalance = fullList.isNotEmpty
            ? fullList.last['runningBalance']
            : startBalance;
        _loading = false;
      });
    }
  }

  // ✅ دالة حذف السند وتحديث رصيد المورد
  Future<void> _deletePayment(String paymentId, double amount) async {
    try {
      // 1. حذف السند
      await PBHelper().pb.collection('supplier_payments').delete(paymentId);

      // 2. تحديث رصيد المورد (إعادة المبلغ للمديونية)
      // لأننا حذفنا "سداد"، فالدين يرجع يزيد تاني
      final suppRec = await PBHelper().pb
          .collection('suppliers')
          .getOne(widget.supplier['id']);
      double currentBal = (suppRec.data['balance'] ?? 0).toDouble();

      await PBHelper().pb
          .collection('suppliers')
          .update(
            widget.supplier['id'],
            body: {'balance': currentBal + amount},
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم حذف السند وتحديث الرصيد"),
            backgroundColor: Colors.red,
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    }
  }

  // ✅ دالة تعديل السند (بنفس ستايل العميل)
  void _showEditPaymentDialog(Map<String, dynamic> rawRecord) {
    final amountCtrl = TextEditingController(
      text: rawRecord['amount'].toString(),
    );
    final notesCtrl = TextEditingController(text: rawRecord['notes']);
    String paymentMethod = rawRecord['method'] ?? 'cash';
    DateTime selectedDate = DateTime.parse(rawRecord['date']);
    double oldAmount = (rawRecord['amount'] as num).toDouble();

    // التعامل مع الصورة
    String? currentServerImage =
        rawRecord['receiptImage'] != null &&
            rawRecord['receiptImage'].toString().isNotEmpty
        ? rawRecord['receiptImage']
        : null;
    String? newLocalImagePath;
    bool deleteImage = false;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final txt = isDark ? Colors.white : Colors.black;
    final border = isDark ? Colors.grey[600]! : Colors.grey;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.edit, color: Colors.blue),
              const SizedBox(width: 10),
              Text("تعديل سند الدفع", style: TextStyle(color: txt)),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // المبلغ
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: txt),
                    decoration: InputDecoration(
                      labelText: "المبلغ",
                      labelStyle: TextStyle(color: isDark ? Colors.grey : null),
                      prefixIcon: Icon(
                        Icons.attach_money,
                        color: isDark ? Colors.grey : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // طريقة الدفع
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    dropdownColor: isDark
                        ? const Color(0xFF333333)
                        : Colors.white,
                    decoration: InputDecoration(
                      labelText: "طريقة الدفع",
                      labelStyle: TextStyle(color: isDark ? Colors.grey : null),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: "cash",
                        child: Text("نقدي", style: TextStyle(color: txt)),
                      ),
                      DropdownMenuItem(
                        value: "cheque",
                        child: Text("شيك", style: TextStyle(color: txt)),
                      ),
                      DropdownMenuItem(
                        value: "bank_transfer",
                        child: Text("تحويل", style: TextStyle(color: txt)),
                      ),
                    ],
                    onChanged: (v) => setStateDialog(() => paymentMethod = v!),
                  ),
                  const SizedBox(height: 15),

                  // التاريخ
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (c, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: isDark
                                ? const ColorScheme.dark(
                                    primary: Colors.blue,
                                    onPrimary: Colors.white,
                                    surface: Color(0xFF424242),
                                    onSurface: Colors.white,
                                  )
                                : const ColorScheme.light(primary: Colors.blue),
                            dialogTheme: DialogThemeData(
                              backgroundColor: isDark
                                  ? const Color(0xFF424242)
                                  : Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (d != null) setStateDialog(() => selectedDate = d);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: "التاريخ",
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey : null,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: border),
                        ),
                        prefixIcon: Icon(
                          Icons.calendar_today,
                          color: isDark ? Colors.grey : null,
                        ),
                      ),
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(selectedDate),
                        style: TextStyle(color: txt),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // الصورة
                  GestureDetector(
                    onTap: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (image != null) {
                        setStateDialog(() {
                          newLocalImagePath = image.path;
                          deleteImage = false;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            color: isDark ? Colors.grey : Colors.blueGrey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              newLocalImagePath != null
                                  ? "تم اختيار صورة جديدة ✅"
                                  : (currentServerImage != null && !deleteImage
                                        ? "يوجد صورة حالية (اضغط للتغيير)"
                                        : "إرفاق صورة (اختياري)"),
                              style: TextStyle(
                                color: newLocalImagePath != null
                                    ? Colors.green
                                    : (isDark ? Colors.grey : Colors.black54),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (newLocalImagePath != null ||
                              (currentServerImage != null && !deleteImage))
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                setStateDialog(() {
                                  newLocalImagePath = null;
                                  if (currentServerImage != null)
                                    deleteImage = true;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (currentServerImage != null &&
                      !deleteImage &&
                      newLocalImagePath == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        "⚠️ سيتم الاحتفاظ بالصورة القديمة",
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ),
                  const SizedBox(height: 15),

                  // ملاحظات
                  TextField(
                    controller: notesCtrl,
                    style: TextStyle(color: txt),
                    decoration: InputDecoration(
                      labelText: "ملاحظات",
                      labelStyle: TextStyle(color: isDark ? Colors.grey : null),
                      prefixIcon: Icon(
                        Icons.note,
                        color: isDark ? Colors.grey : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                double newAmount = double.tryParse(amountCtrl.text) ?? 0;
                if (newAmount <= 0) return;

                try {
                  Map<String, dynamic> body = {
                    'amount': newAmount,
                    'notes': notesCtrl.text,
                    'method': paymentMethod,
                    'date': selectedDate.toIso8601String(),
                  };
                  if (deleteImage && newLocalImagePath == null) {
                    body['receiptImage'] = null;
                  }

                  if (newLocalImagePath != null) {
                    await PBHelper().pb
                        .collection('supplier_payments')
                        .update(
                          rawRecord['id'],
                          body: body,
                          files: [
                            await http.MultipartFile.fromPath(
                              'receiptImage',
                              newLocalImagePath!,
                            ),
                          ],
                        );
                  } else {
                    await PBHelper().pb
                        .collection('supplier_payments')
                        .update(rawRecord['id'], body: body);
                  }

                  // تحديث رصيد المورد بالفرق
                  // لو المبلغ زاد -> الدين يقل
                  double diff = newAmount - oldAmount;
                  final suppRec = await PBHelper().pb
                      .collection('suppliers')
                      .getOne(widget.supplier['id']);
                  double currentBal = (suppRec.data['balance'] ?? 0).toDouble();

                  await PBHelper().pb
                      .collection('suppliers')
                      .update(
                        widget.supplier['id'],
                        body: {'balance': currentBal - diff},
                      );

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadDetails();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم التعديل بنجاح ✅"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                }
              },
              child: const Text("حفظ التعديلات"),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ عرض الصورة
  void _showImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGenericDetails(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item['type']),
        content: Text(
          "المبلغ: ${item['amount']}\nالتاريخ: ${item['date'].toString().split(' ')[0]}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إغلاق"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _dateRange,
    );
    if (picked != null)
      setState(() {
        _dateRange = picked;
        _loadDetails();
      });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.supplier['name']),
        actions: [
          IconButton(
            icon: Icon(
              Icons.calendar_month,
              color: _dateRange != null ? Colors.orange : null,
            ),
            onPressed: _pickDateRange,
          ),
          if (_dateRange != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _dateRange = null;
                  _loadDetails();
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: isDark ? const Color(0xFF1A1A1A) : Colors.brown[50],
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 2000),
                child: Column(
                  children: [
                    Text(
                      _dateRange != null
                          ? "الرصيد في نهاية الفترة"
                          : "الرصيد الحالي",
                      style: TextStyle(color: subColor),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "${_currentVisibleBalance.abs().toStringAsFixed(1)} ج.م",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _currentVisibleBalance > 0
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                    Text(
                      _currentVisibleBalance > 0 ? "له (علينا)" : "لنا (مقدم)",
                      style: TextStyle(color: subColor),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: ["الكل", "فواتير", "دفعات", "مرتجعات"].map((
                          filter,
                        ) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(filter),
                              selected: _filterType == filter,
                              onSelected: (val) => setState(() {
                                _filterType = filter;
                                _loadDetails();
                              }),
                              selectedColor: Colors.brown,
                              backgroundColor: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey[300],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_dateRange != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange.withOpacity(0.1),
              child: Text(
                "عرض الفترة من: ${DateFormat('yyyy-MM-dd').format(_dateRange!.start)} إلى: ${DateFormat('yyyy-MM-dd').format(_dateRange!.end)}",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 10, bottom: 150),
                    itemCount: _filteredTransactions.length,
                    itemBuilder: (ctx, i) {
                      final item = _filteredTransactions[i];
                      bool isDebit = item['isDebit'];
                      bool isHeader = item['isHeader'] == true;
                      bool isPayment = item['category'] == 'دفعات';

                      String? imageUrl;
                      if (isPayment) {
                        final raw = item['rawRecord'];
                        if (raw['receiptImage'] != null &&
                            raw['receiptImage'].toString().isNotEmpty) {
                          imageUrl = PBHelper().getImageUrl(
                            raw['collectionId'],
                            raw['id'],
                            raw['receiptImage'],
                          );
                        }
                      }

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 2000),
                          child: Card(
                            color: isHeader
                                ? (isDark ? Colors.grey[800] : Colors.grey[200])
                                : cardColor,
                            margin: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 10,
                              ),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (imageUrl != null)
                                        _showImage(imageUrl);
                                      else if (!isHeader)
                                        _showGenericDetails(item);
                                    },
                                    child: Stack(
                                      children: [
                                        Icon(
                                          isHeader
                                              ? Icons.account_balance
                                              : (isDebit
                                                    ? Icons.arrow_downward
                                                    : Icons.arrow_upward),
                                          size: 30,
                                          color: isHeader
                                              ? subColor
                                              : (isDebit
                                                    ? Colors.red
                                                    : Colors.green),
                                        ),
                                        if (imageUrl != null)
                                          const Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Icon(
                                              Icons.image,
                                              size: 14,
                                              color: Colors.orange,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (imageUrl != null)
                                          _showImage(imageUrl);
                                        else if (!isHeader)
                                          _showGenericDetails(item);
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['type'],
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: textColor,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            isHeader
                                                ? "---"
                                                : "${item['date'].toString().split(' ')[0]}",
                                            style: TextStyle(
                                              color: subColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "${item['amount'].toStringAsFixed(1)}",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isHeader
                                              ? textColor
                                              : (isDebit
                                                    ? Colors.red
                                                    : Colors.green),
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        "رصيد: ${item['runningBalance'].toStringAsFixed(1)}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: subColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isPayment &&
                                      _canManagePayments &&
                                      !isHeader) ...[
                                    const SizedBox(width: 5),
                                    SizedBox(
                                      width: 30,
                                      child: PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          Icons.more_vert,
                                          color: subColor,
                                        ),
                                        onSelected: (val) {
                                          if (val == 'edit')
                                            _showEditPaymentDialog(
                                              item['rawRecord'],
                                            );
                                          else if (val == 'delete') {
                                            showDialog(
                                              context: context,
                                              builder: (c) => AlertDialog(
                                                title: const Text("حذف السند"),
                                                content: const Text(
                                                  "هل أنت متأكد؟ سيتم إعادة المبلغ لمديونية المورد.",
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c),
                                                    child: const Text("إلغاء"),
                                                  ),
                                                  ElevatedButton(
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                    onPressed: () {
                                                      Navigator.pop(c);
                                                      _deletePayment(
                                                        item['id'],
                                                        (item['amount'] as num)
                                                            .toDouble(),
                                                      );
                                                    },
                                                    child: const Text(
                                                      "حذف",
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.edit,
                                                  color: Colors.blue,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text("تعديل"),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.delete,
                                                  color: Colors.red,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text("حذف"),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else if (!isHeader) ...[
                                    const SizedBox(width: 35),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _canAddPayment
          ? Padding(
              padding: const EdgeInsets.only(bottom: 20, left: 10),
              child: FloatingActionButton.extended(
                onPressed: () => _showAddPaymentDialog(context),
                label: const Text(
                  "سداد دفعة",
                  style: TextStyle(color: Colors.white),
                ),
                icon: const Icon(Icons.payment, color: Colors.white),
                backgroundColor: Colors.brown,
              ),
            )
          : null,
    );
  }

  // ✅ تحسين ديلوج الدفع (Modern Style)
  void _showAddPaymentDialog(BuildContext context) {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String paymentMethod = "cash";
    String? selectedImagePath;
    DateTime selectedDate = DateTime.now();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
    final txt = isDark ? Colors.white : Colors.black;
    final border = isDark ? Colors.grey[600]! : Colors.grey;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: bg,
          title: Text("سند دفع للمورد", style: TextStyle(color: txt)),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amtCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: txt),
                    decoration: InputDecoration(
                      labelText: "المبلغ",
                      labelStyle: TextStyle(color: isDark ? Colors.grey : null),
                      prefixIcon: Icon(
                        Icons.attach_money,
                        color: isDark ? Colors.grey : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    dropdownColor: isDark
                        ? const Color(0xFF333333)
                        : Colors.white,
                    decoration: InputDecoration(
                      labelText: "طريقة الدفع",
                      labelStyle: TextStyle(color: isDark ? Colors.grey : null),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: "cash",
                        child: Text(
                          "نـقـدي (Cash)",
                          style: TextStyle(color: txt),
                        ),
                      ),
                      DropdownMenuItem(
                        value: "cheque",
                        child: Text(
                          "شـيـك (Cheque)",
                          style: TextStyle(color: txt),
                        ),
                      ),
                      DropdownMenuItem(
                        value: "bank_transfer",
                        child: Text(
                          "تحويل بنكي (Transfer)",
                          style: TextStyle(color: txt),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setStateDialog(() => paymentMethod = val!),
                  ),
                  const SizedBox(height: 15),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (c, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: isDark
                                ? const ColorScheme.dark(
                                    primary: Colors.brown,
                                    onPrimary: Colors.white,
                                    surface: Color(0xFF424242),
                                    onSurface: Colors.white,
                                  )
                                : const ColorScheme.light(
                                    primary: Colors.brown,
                                  ),
                            dialogTheme: DialogThemeData(
                              backgroundColor: isDark
                                  ? const Color(0xFF424242)
                                  : Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (d != null) setStateDialog(() => selectedDate = d);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: "التاريخ",
                        labelStyle: TextStyle(
                          color: isDark ? Colors.grey : null,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: border),
                        ),
                        prefixIcon: Icon(
                          Icons.calendar_today,
                          color: isDark ? Colors.grey : null,
                        ),
                      ),
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(selectedDate),
                        style: TextStyle(color: txt),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  GestureDetector(
                    onTap: () async {
                      final ImagePicker picker = ImagePicker();
                      final XFile? image = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (image != null)
                        setStateDialog(() => selectedImagePath = image.path);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt,
                            color: isDark ? Colors.grey : Colors.blueGrey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              selectedImagePath != null
                                  ? "تم اختيار صورة ✅"
                                  : "إرفاق صورة (اختياري)",
                              style: TextStyle(
                                color: selectedImagePath != null
                                    ? Colors.green
                                    : (isDark ? Colors.grey : Colors.black54),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (selectedImagePath != null)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => setStateDialog(
                                () => selectedImagePath = null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: noteCtrl,
                    style: TextStyle(color: txt),
                    decoration: InputDecoration(
                      labelText: "ملاحظات",
                      labelStyle: TextStyle(color: isDark ? Colors.grey : null),
                      prefixIcon: Icon(
                        Icons.note,
                        color: isDark ? Colors.grey : null,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: border),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (amtCtrl.text.isNotEmpty) {
                  await PurchasesService().addSupplierPayment(
                    supplierId: widget.supplier['id'],
                    amount: double.parse(amtCtrl.text),
                    notes: noteCtrl.text,
                    date: selectedDate.toIso8601String(),
                    paymentMethod: paymentMethod,
                    imagePath: selectedImagePath,
                  );
                  Navigator.pop(ctx);
                  _loadDetails();
                }
              },
              child: const Text("حفظ"),
            ),
          ],
        ),
      ),
    );
  }
}
