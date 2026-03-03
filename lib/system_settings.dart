// ملف: system_settings.dart

class SystemSettings {
  // === إعدادات النظام العامة ===
  bool allowUserAddOrders; // السماح لليوزر بالإضافة
  bool allowAdminDeleteUsers; // السماح للأدمن بالحذف
  bool isMaintenanceMode; // وضع الصيانة

  // === إظهار/إخفاء أقسام البرنامج ===
  bool showSales;
  bool showPurchases;
  bool showStock;
  bool showReturns;
  bool showSalesHistory;
  bool showPurchaseHistory;
  bool showClients;
  bool showSuppliers;
  bool showDelivery;
  bool showExpenses;
  bool showReports;

  SystemSettings({
    required this.allowUserAddOrders,
    required this.allowAdminDeleteUsers,
    required this.isMaintenanceMode,

    required this.showSales,
    required this.showPurchases,
    required this.showStock,
    required this.showReturns,
    required this.showSalesHistory,
    required this.showPurchaseHistory,
    required this.showClients,
    required this.showSuppliers,
    required this.showDelivery,
    required this.showExpenses,
    required this.showReports,
  });

  factory SystemSettings.fromJson(Map<String, dynamic> json) {
    return SystemSettings(
      // العامة
      allowUserAddOrders: json['allow_user_add_orders'] ?? true,
      allowAdminDeleteUsers: json['allow_admin_delete_users'] ?? true,
      isMaintenanceMode: json['is_maintenance_mode'] ?? false,

      // الأقسام (ملاحظة: تأكد أن الأسماء هنا تطابق PocketBase بالضبط)
      showSales: json['show_sales'] ?? true,
      showPurchases: json['show_purchases'] ?? true,
      showStock: json['show_stock'] ?? true,
      showReturns: json['show_returns'] ?? true,
      showSalesHistory: json['show_sales_history'] ?? true,
      showPurchaseHistory: json['show_purchase_history'] ?? true,
      showClients: json['show_clients'] ?? true,
      showSuppliers: json['show_suppliers'] ?? true,
      showDelivery: json['show_delivery'] ?? true,
      showExpenses: json['show_expenses'] ?? true,
      showReports: json['show_reports'] ?? true,
    );
  }
}
