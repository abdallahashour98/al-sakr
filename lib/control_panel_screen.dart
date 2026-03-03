import 'package:flutter/material.dart';
import 'services/pb_helper.dart';
import 'system_settings.dart';

class ControlPanelScreen extends StatefulWidget {
  const ControlPanelScreen({super.key});

  @override
  State<ControlPanelScreen> createState() => _ControlPanelScreenState();
}

class _ControlPanelScreenState extends State<ControlPanelScreen> {
  bool _isLoading = true;
  String? _errorMessage; // متغير لحفظ رسالة الخطأ وعرضها

  // ✅ التعديل 1: جعل المتغير nullable (بدون late) لمنع الانهيار
  SystemSettings? currentSettings;

  // ✅ الآيدي الخاص بسجل الإعدادات
  final String settingsRecordId = "g7e7u2dmeilb10e";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final record = await PBHelper().pb
          .collection('system_settings')
          .getOne(settingsRecordId);

      if (mounted) {
        setState(() {
          currentSettings = SystemSettings.fromJson(record.data);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          // حفظ رسالة الخطأ لعرضها للمستخدم
          _errorMessage = "لا توجد صلاحية لقراءة الإعدادات (تأكد من API Rules)";
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (currentSettings == null) return; // حماية إضافية

    setState(() => _isLoading = true);
    try {
      await PBHelper().pb
          .collection('system_settings')
          .update(
            settingsRecordId,
            body: {
              // العامة
              'allow_user_add_orders': currentSettings!.allowUserAddOrders,
              'allow_admin_delete_users':
                  currentSettings!.allowAdminDeleteUsers,
              'is_maintenance_mode': currentSettings!.isMaintenanceMode,

              // الأقسام
              'show_sales': currentSettings!.showSales,
              'show_purchases': currentSettings!.showPurchases,
              'show_stock': currentSettings!.showStock,
              'show_returns': currentSettings!.showReturns,
              'show_sales_history': currentSettings!.showSalesHistory,
              'show_purchase_history': currentSettings!.showPurchaseHistory,
              'show_clients': currentSettings!.showClients,
              'show_suppliers': currentSettings!.showSuppliers,
              'show_delivery': currentSettings!.showDelivery,
              'show_expenses': currentSettings!.showExpenses,
              'show_reports': currentSettings!.showReports,
            },
          );

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم حفظ الصلاحيات وتطبيقها بنجاح ✅"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("خطأ في الحفظ: $e")));
      }
    }
  }

  Widget _buildSwitch(
    String title,
    String subtitle,
    bool val,
    Function(bool) onChange, {
    Color activeColor = Colors.blue,
  }) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      value: val,
      activeThumbColor: activeColor,
      onChanged: onChange,
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          color: Colors.blueAccent[100],
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("لوحة التحكم بالصلاحيات ⚙️")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null || currentSettings == null)
          // ✅ التعديل 2: عرض رسالة خطأ بدلاً من انهيار التطبيق
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 50),
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage ?? "حدث خطأ غير معروف",
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loadSettings,
                    child: const Text("إعادة المحاولة"),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // تم استخدام !currentSettings لأننا تأكدنا أنه ليس null في الأعلى

                // 1. التحكم العام
                _buildSectionHeader("⚠️ تحكم النظام العام"),
                _buildSwitch(
                  "وضع الصيانة (Maintenance Mode)",
                  "سيتم منع الجميع من استخدام التطبيق ما عدا السوبر أدمن",
                  currentSettings!.isMaintenanceMode,
                  (v) => setState(() => currentSettings!.isMaintenanceMode = v),
                  activeColor: Colors.red,
                ),
                _buildSwitch(
                  "السماح للمستخدمين بإضافة طلبات",
                  "تفعيل/إيقاف زر الإضافة عند الموظفين",
                  currentSettings!.allowUserAddOrders,
                  (v) =>
                      setState(() => currentSettings!.allowUserAddOrders = v),
                ),
                _buildSwitch(
                  "السماح للأدمن بحذف المستخدمين",
                  "تفعيل/إيقاف الحذف للمشرفين العاديين",
                  currentSettings!.allowAdminDeleteUsers,
                  (v) => setState(
                    () => currentSettings!.allowAdminDeleteUsers = v,
                  ),
                ),
                const Divider(thickness: 2),

                // 2. العمليات والمخزن
                _buildSectionHeader("📦 العمليات والمخزن"),
                _buildSwitch(
                  "فاتورة مبيعات",
                  "إظهار/إخفاء",
                  currentSettings!.showSales,
                  (v) => setState(() => currentSettings!.showSales = v),
                ),
                _buildSwitch(
                  "شراء (توريد)",
                  "إظهار/إخفاء",
                  currentSettings!.showPurchases,
                  (v) => setState(() => currentSettings!.showPurchases = v),
                ),
                _buildSwitch(
                  "المخزن والأصناف",
                  "إظهار/إخفاء",
                  currentSettings!.showStock,
                  (v) => setState(() => currentSettings!.showStock = v),
                ),
                _buildSwitch(
                  "المرتجعات",
                  "إظهار/إخفاء",
                  currentSettings!.showReturns,
                  (v) => setState(() => currentSettings!.showReturns = v),
                ),
                _buildSwitch(
                  "أذونات التسليم",
                  "إظهار/إخفاء",
                  currentSettings!.showDelivery,
                  (v) => setState(() => currentSettings!.showDelivery = v),
                ),

                const Divider(),

                // 3. العملاء والموردين والمالية
                _buildSectionHeader("👥 العملاء والمالية"),
                _buildSwitch(
                  "إدارة العملاء",
                  "إظهار/إخفاء",
                  currentSettings!.showClients,
                  (v) => setState(() => currentSettings!.showClients = v),
                ),
                _buildSwitch(
                  "إدارة الموردين",
                  "إظهار/إخفاء",
                  currentSettings!.showSuppliers,
                  (v) => setState(() => currentSettings!.showSuppliers = v),
                ),
                _buildSwitch(
                  "المصروفات",
                  "إظهار/إخفاء",
                  currentSettings!.showExpenses,
                  (v) => setState(() => currentSettings!.showExpenses = v),
                ),

                const Divider(),

                // 4. التقارير والسجلات
                _buildSectionHeader("📊 التقارير والسجلات"),
                _buildSwitch(
                  "سجل المبيعات",
                  "إظهار/إخفاء",
                  currentSettings!.showSalesHistory,
                  (v) => setState(() => currentSettings!.showSalesHistory = v),
                ),
                _buildSwitch(
                  "سجل المشتريات",
                  "إظهار/إخفاء",
                  currentSettings!.showPurchaseHistory,
                  (v) =>
                      setState(() => currentSettings!.showPurchaseHistory = v),
                ),
                _buildSwitch(
                  "التقارير الشاملة",
                  "إظهار/إخفاء",
                  currentSettings!.showReports,
                  (v) => setState(() => currentSettings!.showReports = v),
                ),

                const SizedBox(height: 30),

                // زر الحفظ
                ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text(
                    "حفظ التغييرات وتطبيقها فوراً",
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
    );
  }
}
