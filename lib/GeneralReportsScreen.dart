import 'package:al_sakr/services/pb_helper.dart';
import 'package:flutter/material.dart';
import 'services/reports_service.dart';

// ✅ استيراد شاشات التفاصيل (للانتقال إليها عند الضغط على الكروت)
import 'reports_screen.dart';
import 'purchase_history_screen.dart';
import 'expenses_screen.dart';
import 'store_screen.dart';
import 'suppliers_screen.dart';
import 'clients_screen.dart';
import 'returns_list_screen.dart';

/// نوع الفلترة المستخدم في التقرير: إما شهري أو سنوي
enum ReportFilter { monthly, yearly }

/// ============================================================
/// 📊 شاشة التقرير المالي الشامل (General Reports Dashboard)
/// ============================================================
/// الغرض:
/// عرض ملخص للحالة المالية للمشروع (المبيعات، المصروفات، الأرباح، السيولة).
///
/// الميزات الأساسية:
/// 1. **Live Updates:** تستمع لجميع التغييرات في الداتابيز وتحدث الأرقام لحظياً.
/// 2. **Time Filtering:** إمكانية التبديل بين العرض الشهري والسنوي.
/// 3. **Navigation:** تعمل كنقطة انطلاق لشاشات التفاصيل (مثل تفاصيل المبيعات).
class GeneralReportsScreen extends StatefulWidget {
  const GeneralReportsScreen({super.key});

  @override
  State<GeneralReportsScreen> createState() => _GeneralReportsScreenState();
}

class _GeneralReportsScreenState extends State<GeneralReportsScreen> {
  // ============================================================
  // 1️⃣ المتغيرات وإدارة الحالة (State Variables)
  // ============================================================

  bool _isLoading = true; // حالة التحميل

  /// خريطة تحتوي على الأرقام المالية (مبيعات، مرتجعات، مخزون...)
  Map<String, double> _data = {};

  /// نوع الفلتر الحالي (الافتراضي: شهري)
  ReportFilter _filterType = ReportFilter.monthly;

  /// التاريخ المحدد حالياً (يتحكم في الشهر أو السنة المعروضة)
  DateTime _selectedDate = DateTime.now();

  /// 📝 قائمة الجداول التي يجب مراقبتها لتحديث التقرير تلقائياً
  /// أي تغيير في هذه الجداول سيؤدي لإعادة حساب الأرقام في هذه الشاشة
  final List<String> _collectionsToWatch = [
    'sales', // المبيعات
    'sales_items', // تفاصيل المبيعات
    'returns', // مرتجعات العملاء
    'purchases', // المشتريات
    'purchase_returns', // مرتجعات الموردين
    'expenses', // المصروفات
    'supplier_payments', // دفعات الموردين
    'client_payments', // دفعات العملاء
  ];

  // ============================================================
  // 2️⃣ دورة حياة الشاشة (Lifecycle Methods)
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadReportData(); // تحميل البيانات لأول مرة
    _subscribeToRealtime(); // بدء الاستماع للتغييرات
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime(); // إيقاف الاستماع عند الخروج لتوفير الذاكرة
    super.dispose();
  }

  /// 📡 الاشتراك في خدمة الـ Real-time
  void _subscribeToRealtime() {
    for (var collection in _collectionsToWatch) {
      PBHelper().pb
          .collection(collection)
          .subscribe(
            '*',
            (e) => _loadReportData(),
          ); // عند حدوث أي تغيير -> أعد التحميل
    }
  }

  /// 🛑 إلغاء الاشتراك
  void _unsubscribeFromRealtime() {
    for (var collection in _collectionsToWatch) {
      PBHelper().pb.collection(collection).unsubscribe('*');
    }
  }

  // ============================================================
  // 3️⃣ منطق التحكم في التاريخ والبيانات (Logic)
  // ============================================================

  /// تغيير التاريخ (للأمام أو للخلف) بناءً على الفلتر المختار
  /// [offset] : +1 للشهر/السنة القادمة، -1 للشهر/السنة السابقة
  void _changeDate(int offset) {
    setState(() {
      if (_filterType == ReportFilter.monthly) {
        // لو شهري: زود/نقص شهور
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month + offset,
          1,
        );
      } else {
        // لو سنوي: زود/نقص سنوات
        _selectedDate = DateTime(_selectedDate.year + offset, 1, 1);
      }
      _isLoading = true;
    });
    _loadReportData();
  }

  /// 📥 جلب البيانات من السيرفيس
  Future<void> _loadReportData() async {
    // إظهار اللودينج فقط لو مفيش داتا قديمة (عشان التحديث الصامت للريل تايم)
    if (_data.isEmpty) setState(() => _isLoading = true);

    String startDate;
    String endDate;

    // حساب بداية ونهاية الفترة الزمنية
    if (_filterType == ReportFilter.monthly) {
      // من أول يوم في الشهر إلى آخر لحظة في آخر يوم
      DateTime start = DateTime(_selectedDate.year, _selectedDate.month, 1);
      DateTime end = DateTime(
        _selectedDate.year,
        _selectedDate.month + 1,
        0, // يوم 0 في الشهر التالي يعني آخر يوم في الشهر الحالي
        23,
        59,
        59,
      );
      startDate = start.toIso8601String();
      endDate = end.toIso8601String();
    } else {
      // من أول السنة لآخرها
      DateTime start = DateTime(_selectedDate.year, 1, 1);
      DateTime end = DateTime(_selectedDate.year, 12, 31, 23, 59, 59);
      startDate = start.toIso8601String();
      endDate = end.toIso8601String();
    }

    try {
      final data = await ReportsService().getGeneralReportData(
        startDate: startDate,
        endDate: endDate,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading report: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 🚀 دالة مساعدة للتنقل وتمرير سياق التحديث
  /// عند العودة من الشاشة الفرعية، نقوم بتحديث البيانات
  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    ).then((_) => _loadReportData());
  }

  /// تحويل رقم الشهر لاسم عربي
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
  // 4️⃣ بناء الواجهة (UI Build)
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    // --- استخراج البيانات للمعالجة ---
    double sales = _data['monthlySales'] ?? 0.0;
    double clientReturns = _data['clientReturns'] ?? 0.0;
    double supplierReturns = _data['supplierReturns'] ?? 0.0;
    double expenses = _data['monthlyExpenses'] ?? 0.0;
    double supplierPayments = _data['monthlyPayments'] ?? 0.0;
    double purchasesBills = _data['monthlyBills'] ?? 0.0;

    // --- المعادلات الحسابية للعرض ---
    // 1. صافي المبيعات = المبيعات - المرتجعات
    double netSales = sales - clientReturns;

    // 2. صافي السيولة (Cash Flow)
    // المعادلة: (إيراد المبيعات الصافي) - (المصروفات) - (الفلوس اللي دفعناها للموردين)
    // نستخدم abs() لضمان أننا بنطرح القيمة المطلقة للمصروفات بغض النظر عن إشارة الرقم في الداتابيز
    double netCashFlow = netSales - expenses.abs() - supplierPayments.abs();

    // عنوان الفترة الزمنية (مثال: يناير 2025)
    String filterTitle = _filterType == ReportFilter.monthly
        ? "${_getMonthName(_selectedDate.month)} ${_selectedDate.year}"
        : "${_selectedDate.year}";

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقرير المالي الشامل'),
        centerTitle: true,
        // زر الفلتر في الأعلى (Popup Menu)
        actions: [
          PopupMenuButton<ReportFilter>(
            icon: const Icon(Icons.filter_alt_outlined),
            onSelected: (ReportFilter result) {
              setState(() {
                _filterType = result;
                _selectedDate =
                    DateTime.now(); // إعادة ضبط التاريخ عند تغيير الفلتر
                _loadReportData();
              });
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: ReportFilter.monthly,
                child: Text('عرض شهري'),
              ),
              const PopupMenuItem(
                value: ReportFilter.yearly,
                child: Text('عرض سنوي'),
              ),
            ],
          ),
        ],
        // شريط التنقل الزمني (الأسهم والشهر)
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _changeDate(-1), // السابق
                  icon: const Icon(Icons.arrow_back_ios, size: 20),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _filterType == ReportFilter.monthly
                            ? Icons.calendar_month
                            : Icons.calendar_today,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        filterTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _changeDate(1), // التالي
                  icon: const Icon(Icons.arrow_forward_ios, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: _loadReportData,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 2000,
                    ), // لدعم الشاشات العريضة
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // ================= القسم الأول: حركة السيولة =================
                          _buildSectionHeader("حركة السيولة ($filterTitle)"),
                          Container(
                            padding: const EdgeInsets.all(15),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[900]
                                  : Colors.blue[50],
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildCashRow(
                                  "صافي المبيعات (إيراد)",
                                  netSales,
                                  Colors.green,
                                ),
                                const Divider(),
                                _buildCashRow(
                                  "مصاريف تشغيل (خرج)",
                                  -expenses.abs(),
                                  Colors.red,
                                ),
                                _buildCashRow(
                                  "مدفوعات موردين (خرج)",
                                  -supplierPayments.abs(),
                                  Colors.orange[800]!,
                                ),
                                const Divider(thickness: 2),
                                // عرض الصافي النهائي
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "صافي السيولة :",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      "${netCashFlow.toStringAsFixed(1)} ج.م",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: netCashFlow >= 0
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 25),

                          // ================= القسم الثاني: تفاصيل النشاط =================
                          _buildSectionHeader("النشاط التجاري ($filterTitle)"),

                          // كروت التنقل للشاشات الفرعية مع تمرير التاريخ المختار
                          _buildListTileCard(
                            "إجمالي المبيعات",
                            sales,
                            Icons.point_of_sale,
                            Colors.teal,
                            cardBg,
                            textColor,
                            () => _navigateTo(
                              ReportsScreen(initialDate: _selectedDate),
                            ),
                          ),

                          _buildListTileCard(
                            "إجمالي فواتير الشراء",
                            purchasesBills,
                            Icons.inventory,
                            Colors.blue,
                            cardBg,
                            textColor,
                            () => _navigateTo(
                              PurchaseHistoryScreen(initialDate: _selectedDate),
                            ),
                          ),

                          _buildListTileCard(
                            "مرتجعات العملاء",
                            -clientReturns,
                            Icons.assignment_return,
                            Colors.deepPurple,
                            cardBg,
                            textColor,
                            () => _navigateTo(
                              ReturnsListScreen(
                                initialIndex: 0,
                                initialDate: _selectedDate,
                              ),
                            ),
                          ),

                          _buildListTileCard(
                            "مرتجعات الموردين",
                            -supplierReturns,
                            Icons.unarchive,
                            Colors.orange,
                            cardBg,
                            textColor,
                            () => _navigateTo(
                              ReturnsListScreen(
                                initialIndex: 1,
                                initialDate: _selectedDate,
                              ),
                            ),
                          ),

                          _buildListTileCard(
                            "المصروفات",
                            -expenses,
                            Icons.money_off,
                            Colors.redAccent,
                            cardBg,
                            textColor,
                            () => _navigateTo(const ExpensesScreen()),
                          ),

                          const SizedBox(height: 25),

                          // ================= القسم الثالث: المركز المالي =================
                          _buildSectionHeader(
                            "المركز المالي (الأرصدة الحالية)",
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryCard(
                                  "قيمة المخزون",
                                  _data['inventory'] ?? 0,
                                  Icons.store,
                                  Colors.blue,
                                  isDark,
                                  () => _navigateTo(const StoreScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryCard(
                                  "لنا عند العملاء",
                                  _data['receivables'] ?? 0,
                                  Icons.account_balance_wallet,
                                  Colors.green,
                                  isDark,
                                  () => _navigateTo(const ClientsScreen()),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildSummaryCard(
                                  "علينا للموردين",
                                  _data['payables'] ?? 0,
                                  Icons.money_off,
                                  Colors.red,
                                  isDark,
                                  () => _navigateTo(const SuppliersScreen()),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ============================================================
  // 5️⃣ دوال بناء العناصر المساعدة (Helper Widgets)
  // ============================================================

  /// عنوان القسم (نص رمادي صغير يظهر فوق الكروت)
  Widget _buildSectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10, right: 5),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    ),
  );

  /// سطر في قسم السيولة (اسم البند + القيمة)
  Widget _buildCashRow(String title, double amount, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 14)),
        Text(
          "${amount.toStringAsFixed(1)} ج.م",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );

  /// كارت ملخص مربع (للمخزون والديون)
  Widget _buildSummaryCard(
    String title,
    double amount,
    IconData icon,
    Color color,
    bool isDark,
    VoidCallback onTap,
  ) => Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            FittedBox(
              child: Text(
                "${amount.abs().toStringAsFixed(1)} ج.م",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// كارت تفصيلي طولي (للمبيعات والمصروفات)
  Widget _buildListTileCard(
    String title,
    double amount,
    IconData icon,
    Color color,
    Color cardBg,
    Color textColor,
    VoidCallback onTap,
  ) => Card(
    color: cardBg,
    elevation: 1,
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // عرض القيمة المالية
          Text(
            "${amount.toStringAsFixed(1)} ج.م",
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 8),
          // سهم صغير للدلالة على القابلية للنقر
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Colors.grey.withOpacity(0.5),
          ),
        ],
      ),
    ),
  );
}
