import 'package:flutter/material.dart';

import 'services/purchases_service.dart';

class SupplierStatementScreen extends StatefulWidget {
  const SupplierStatementScreen({super.key});

  @override
  State<SupplierStatementScreen> createState() =>
      _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends State<SupplierStatementScreen> {
  // القوائم
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _statementData = [];

  // المتغيرات
  String? _selectedSupplierId; // ✅ ID المورد نصي
  double _finalBalance = 0;

  // فلاتر التاريخ (افتراضي آخر 30 يوم)
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  // 1. تحميل قائمة الموردين
  void _loadSuppliers() async {
    final data = await PurchasesService().getSuppliers();
    setState(() {
      _suppliers = data;
    });
  }

  // 2. تحميل كشف الحساب
  void _loadStatement(String supplierId) async {
    // أ. جلب الحركات (فواتير، دفعات، مرتجعات) في الفترة
    final data = await PurchasesService().getSupplierStatement(
      supplierId,
      startDate: _startDate,
      endDate: _endDate,
    );

    // ب. جلب الرصيد الافتتاحي للمورد
    double openingBalance = await PurchasesService().getSupplierOpeningBalance(
      supplierId,
    );

    // ج. حساب الرصيد التراكمي
    // معادلة الرصيد: الرصيد الافتتاحي + (الفواتير - المرتجعات - المدفوعات)
    double billTotal = 0;
    double paymentTotal = 0;
    double returnTotal = 0;

    for (var item in data) {
      double amount = (item['amount'] as num).toDouble();
      if (item['type'] == 'bill') {
        billTotal += amount;
      } else if (item['type'] == 'payment') {
        paymentTotal += amount;
      } else if (item['type'] == 'return') {
        returnTotal += amount;
      }
    }

    // د. دمج الرصيد الافتتاحي كأول عنصر في القائمة للعرض
    List<Map<String, dynamic>> finalData = List.from(data);
    if (openingBalance != 0) {
      finalData.insert(0, {
        'id': 'opening',
        'type': 'opening',
        'amount': openingBalance.abs(),
        'date': _startDate.toIso8601String(),
        'description': 'رصيد افتتاحي / سابق',
      });
    }

    setState(() {
      _statementData = finalData;
      // الرصيد النهائي = الافتتاحي + صافي الحركة
      _finalBalance = openingBalance + billTotal - returnTotal - paymentTotal;
    });
  }

  // 3. عرض تفاصيل الفاتورة
  void _showInvoiceDetails(String invoiceId, String title) async {
    final items = await PurchasesService().getPurchaseItems(invoiceId);
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: 500,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Text(
              title, // عنوان الفاتورة (رقمها)
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.brown[200] : Colors.brown,
              ),
            ),
            const Divider(),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('لا توجد تفاصيل'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          title: Text(item['productName'] ?? 'صنف'),
                          subtitle: Text(
                            'سعر: ${item['costPrice']}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: Text(
                            '${((item['quantity'] as num) * (item['costPrice'] as num)).toStringAsFixed(1)} ج.م',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : Colors.black,
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: isDark
                                ? Colors.brown.withOpacity(0.2)
                                : Colors.brown[100],
                            child: Text(
                              '${item['quantity']}',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.brown[100]
                                    : Colors.brown[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 4. إضافة سند دفع
  void _showAddPaymentDialog() {
    if (_selectedSupplierId == null) return;

    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final refController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('تسجيل سند دفع لمورد'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المدفوع',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setStateSB(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${selectedDate.year}-${selectedDate.month}-${selectedDate.day}",
                            ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // خيارات الدفع
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile(
                            title: const Text(
                              'كاش',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: 'cash',
                            groupValue: paymentMethod,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) => setStateSB(
                              () => paymentMethod = val.toString(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile(
                            title: const Text(
                              'بنك',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: 'bank',
                            groupValue: paymentMethod,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) => setStateSB(
                              () => paymentMethod = val.toString(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile(
                            title: const Text(
                              'شيك',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: 'check',
                            groupValue: paymentMethod,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (val) => setStateSB(
                              () => paymentMethod = val.toString(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (paymentMethod != 'cash')
                      TextField(
                        controller: refController,
                        decoration: InputDecoration(
                          labelText: paymentMethod == 'bank'
                              ? 'رقم التحويل'
                              : 'رقم الشيك',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown,
                  ),
                  onPressed: () async {
                    if (amountController.text.isNotEmpty) {
                      String methodText = paymentMethod == 'cash'
                          ? 'نقدأ'
                          : (paymentMethod == 'bank' ? 'تحويل بنكي' : 'شيك');
                      String finalNotes =
                          "($methodText) ${refController.text} ${notesController.text}";

                      await PurchasesService().addSupplierPayment(
                        supplierId: _selectedSupplierId!,
                        amount: double.parse(amountController.text),
                        notes: finalNotes,
                        date: selectedDate.toIso8601String(),
                      );
                      Navigator.pop(context);
                      _loadStatement(_selectedSupplierId!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم حفظ السند ✅')),
                      );
                    }
                  },
                  child: const Text(
                    'حفظ',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 5. حذف سند الدفع
  void _deletePayment(String id, double amount) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السند'),
        content: const Text('هل أنت متأكد؟ سيتم إعادة المبلغ لمديونية المورد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await PurchasesService().deleteSupplierPayment(
                id,
                _selectedSupplierId!,
                amount,
              );
              _loadStatement(_selectedSupplierId!);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('تم حذف السند')));
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 6. اختيار التاريخ
  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart)
          _startDate = picked;
        else
          _endDate = picked;
      });
      if (_selectedSupplierId != null) _loadStatement(_selectedSupplierId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double runningBalance = 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('كشف حساب مورد (تفصيلي)')),
      body: Column(
        children: [
          // قائمة اختيار المورد
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'اختر المورد',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.white,
                prefixIcon: const Icon(Icons.business),
              ),
              items: _suppliers
                  .map(
                    (s) => DropdownMenuItem(
                      value: s['id'] as String,
                      child: Text(s['name']),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() => _selectedSupplierId = val);
                if (_selectedSupplierId != null) {
                  _loadStatement(_selectedSupplierId!);
                }
              },
            ),
          ),

          // فلاتر التاريخ
          if (_selectedSupplierId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              color: isDark ? Colors.black12 : Colors.grey[100],
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(true),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "من:",
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              _startDate.toString().split(' ')[0],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(false),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "إلى:",
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              _endDate.toString().split(' ')[0],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // عرض الرصيد النهائي
          if (_selectedSupplierId != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.brown.withOpacity(0.15)
                    : Colors.brown[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.brown),
              ),
              child: Column(
                children: [
                  const Text(
                    "الرصيد النهائي المستحق",
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "${_finalBalance.toStringAsFixed(2)} ج.م",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _finalBalance > 0
                          ? Colors.red
                          : (_finalBalance < 0 ? Colors.green : Colors.brown),
                    ),
                  ),
                  Text(
                    _finalBalance > 0
                        ? "(علينا للمورد)"
                        : (_finalBalance < 0 ? "(لنا عند المورد)" : "(خالص)"),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),

          // قائمة الحركات
          Expanded(
            child: _selectedSupplierId == null
                ? const Center(child: Text("الرجاء اختيار مورد"))
                : _statementData.isEmpty
                ? const Center(child: Text("لا توجد حركات في هذه الفترة"))
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _statementData.length,
                    itemBuilder: (context, index) {
                      final item = _statementData[index];
                      final isBill = item['type'] == 'bill';
                      final isPayment = item['type'] == 'payment';
                      final isReturn = item['type'] == 'return';
                      final isOpening = item['type'] == 'opening';

                      double amount = (item['amount'] as num).toDouble();

                      // حساب الرصيد التراكمي (للعرض فقط)
                      if (isBill || (isOpening && amount > 0))
                        runningBalance += amount;
                      else
                        runningBalance -= amount;

                      IconData icon = Icons.circle;
                      Color color = Colors.grey;

                      if (isBill) {
                        icon = Icons.receipt_long;
                        color = Colors.orange;
                      } else if (isPayment) {
                        icon = Icons.payment;
                        color = Colors.green;
                      } else if (isReturn) {
                        icon = Icons.assignment_return;
                        color = Colors.red;
                      } else if (isOpening) {
                        icon = Icons.account_balance;
                        color = Colors.blueGrey;
                      }

                      return Card(
                        elevation: isOpening ? 0 : 2,
                        color: isOpening
                            ? (isDark ? Colors.grey[900] : Colors.grey[200])
                            : null,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: isBill
                              ? () => _showInvoiceDetails(
                                  item['id'],
                                  item['description'],
                                )
                              : null,
                          leading: CircleAvatar(
                            backgroundColor: color.withOpacity(0.1),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  item['description'] ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                "${isBill ? '+' : '-'} ${amount.toStringAsFixed(1)}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            "${item['date'].toString().split(' ')[0]}",
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: isPayment
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _deletePayment(item['id'], amount),
                                )
                              : (isBill
                                    ? const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 12,
                                        color: Colors.grey,
                                      )
                                    : null),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selectedSupplierId != null
          ? FloatingActionButton.extended(
              onPressed: _showAddPaymentDialog,
              label: const Text(
                'سند دفع',
                style: TextStyle(color: Colors.white),
              ),
              icon: const Icon(Icons.money_off, color: Colors.white),
              backgroundColor: Colors.brown[700],
            )
          : null,
    );
  }
}
