import 'package:al_sakr/trash_screen.dart';
import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import 'package:shared_preferences/shared_preferences.dart'; // ✅ 1. إضافة المكتبة
import 'services/notice_service.dart';
import 'notices_screen.dart';
import 'notification_service.dart';
import 'update_service.dart';

// ✅ استيراد باقي الشاشات
import 'sales_screen.dart';
import 'store_screen.dart';
import 'clients_screen.dart';
import 'suppliers_screen.dart';
import 'purchase_screen.dart';
import 'purchase_history_screen.dart';
import 'reports_screen.dart';
import 'GeneralReportsScreen.dart';
import 'delivery_orders_screen.dart';
import 'returns_list_screen.dart';
import 'expenses_screen.dart';
import 'settings_screen.dart';

// موديل عنصر القائمة
class MenuItem {
  final String title;
  final IconData icon;
  final Color color;
  final Widget page;

  MenuItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.page,
  });
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _currentUserData = {};

  // المتغير الافتراضي
  bool _isGridView = true;

  late Stream<int> _unreadStream;
  final String _superAdminId = "1sxo74splxbw1yh";

  @override
  void initState() {
    super.initState();
    NotificationService.init();
    _unreadStream = NoticeService().getUnreadCountStream();

    // ✅ 2. تحميل وضع العرض المحفوظ فوراً عند الفتح
    _loadViewPreference();

    _loadUserData();
    _subscribeToUserUpdates();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) UpdateService().checkForUpdate(context);
    });
  }

  // ✅ دالة قراءة الوضع المحفوظ
  Future<void> _loadViewPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // لو مفيش قيمة محفوظة، ارجع للوضع الافتراضي (true أي شبكة)
        _isGridView = prefs.getBool('dashboard_view_mode') ?? true;
      });
    }
  }

  // ✅ دالة تغيير الوضع وحفظه
  Future<void> _toggleViewMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isGridView = !_isGridView;
    });
    // حفظ القيمة الجديدة
    await prefs.setBool('dashboard_view_mode', _isGridView);
  }

  Future<void> _loadUserData() async {
    final myId = NoticeService().pb.authStore.record?.id;
    if (myId == null) return;

    try {
      final record = await NoticeService().pb.collection('users').getOne(myId);
      if (mounted) {
        setState(() {
          _currentUserData = record.data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("خطأ في جلب بيانات المستخدم: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToUserUpdates() {
    final myId = NoticeService().pb.authStore.record?.id;
    if (myId == null) return;

    NoticeService().pb.collection('users').subscribe(myId, (e) {
      if (e.record != null && mounted) {
        setState(() {
          _currentUserData = e.record!.data;
        });
      }
    });
  }

  @override
  void dispose() {
    final myId = NoticeService().pb.authStore.record?.id;
    if (myId != null) {
      NoticeService().pb.collection('users').unsubscribe(myId);
    }
    NoticeService().pb.collection('announcements').unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = NoticeService().pb.authStore.record;
    final bool amISuperAdmin = (currentUser?.id == _superAdminId);

    final List<MenuItem> menuItems = [];

    void addIfAllowed(
      String title,
      IconData icon,
      Color color,
      Widget page,
      String permissionKey,
    ) {
      if (amISuperAdmin || (_currentUserData[permissionKey] == true)) {
        menuItems.add(
          MenuItem(title: title, icon: icon, color: color, page: page),
        );
      }
    }

    addIfAllowed(
      'فاتورة مبيعات',
      Icons.point_of_sale,
      Colors.blue[700]!,
      const SalesScreen(),
      'show_sales',
    );
    addIfAllowed(
      'شراء (توريد)',
      Icons.add_shopping_cart,
      Colors.blue[700]!,
      const PurchaseScreen(),
      'show_purchases',
    );
    addIfAllowed(
      'المخزن والأصناف',
      Icons.inventory_2,
      Colors.orange[800]!,
      const StoreScreen(),
      'show_stock',
    );
    addIfAllowed(
      'المرتجعات',
      Icons.assignment_return,
      Colors.red[700]!,
      const ReturnsListScreen(),
      'show_returns',
    );
    addIfAllowed(
      'إدارة العملاء',
      Icons.people,
      Colors.brown[600]!,
      const ClientsScreen(),
      'show_clients',
    );
    addIfAllowed(
      'إدارة الموردين',
      Icons.local_shipping,
      Colors.brown[600]!,
      const SuppliersScreen(),
      'show_suppliers',
    );
    addIfAllowed(
      'سجل المبيعات',
      Icons.history_edu,
      Colors.green[900]!,
      const ReportsScreen(),
      'show_sales_history',
    );
    addIfAllowed(
      'سجل المشتريات',
      Icons.receipt_long,
      Colors.green[900]!,
      const PurchaseHistoryScreen(),
      'show_purchase_history',
    );
    addIfAllowed(
      'المصروفات',
      Icons.money_off,
      Colors.redAccent,
      const ExpensesScreen(),
      'show_expenses',
    );
    addIfAllowed(
      'أذونات التسليم',
      Icons.receipt,
      Colors.redAccent,
      const DeliveryOrdersScreen(),
      'show_delivery',
    );
    addIfAllowed(
      'التقارير الشاملة',
      Icons.bar_chart,
      const Color(0xFFFBC02D),
      const GeneralReportsScreen(),
      'show_reports',
    );

    menuItems.add(
      MenuItem(
        title: 'الإعدادات',
        icon: Icons.settings,
        color: Colors.grey[700]!,
        page: const SettingsScreen(),
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF121212)
          : Colors.grey[100],

      appBar: AppBar(
        title: const Text("لوحة التحكم"),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (c) => const TrashScreen()),
              ).then((_) {
                setState(() {
                  _unreadStream = NoticeService().getUnreadCountStream();
                });
              });
            },
          ),
          // ✅ 3. استخدام دالة التبديل الجديدة هنا
          IconButton(
            onPressed: _toggleViewMode,
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
            tooltip: _isGridView ? "عرض كقائمة" : "عرض كشبكة",
          ),

          StreamBuilder<int>(
            stream: _unreadStream,
            initialData: 0,
            builder: (context, snapshot) {
              int count = snapshot.data ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: badges.Badge(
                  position: badges.BadgePosition.topEnd(top: 0, end: 3),
                  showBadge: count > 0,
                  badgeContent: Text(
                    count > 99 ? "+99" : count.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  badgeAnimation: const badges.BadgeAnimation.scale(),
                  child: IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => const NoticesScreen(),
                        ),
                      ).then((_) {
                        setState(() {
                          _unreadStream = NoticeService()
                              .getUnreadCountStream();
                        });
                      });
                    },
                  ),
                ),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (MediaQuery.of(context).size.width > 600)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${currentUser?.data['name'] ?? 'مستخدم'}",
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        "أهلاً بك",
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                const SizedBox(width: 8),
                const CircleAvatar(radius: 18, child: Icon(Icons.person)),
              ],
            ),
          ),
        ],
      ),

      body: (_isLoading && !amISuperAdmin)
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    int crossAxisCount;
                    double childAspectRatio;

                    if (_isGridView) {
                      double width = constraints.maxWidth;
                      if (width > 1200) {
                        crossAxisCount = 5;
                      } else if (width > 900) {
                        crossAxisCount = 4;
                      } else if (width > 600) {
                        crossAxisCount = 3;
                      } else {
                        crossAxisCount = 2;
                      }
                      childAspectRatio = 1.1;
                    } else {
                      crossAxisCount = 1;
                      childAspectRatio = constraints.maxWidth / 80;
                    }

                    return GridView.builder(
                      itemCount: menuItems.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 15,
                        mainAxisSpacing: 15,
                        childAspectRatio: childAspectRatio,
                      ),
                      itemBuilder: (context, index) {
                        return DashboardCard(
                          item: menuItems[index],
                          isListView: !_isGridView,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
    );
  }
}

class DashboardCard extends StatelessWidget {
  final MenuItem item;
  final bool isListView;

  const DashboardCard({super.key, required this.item, this.isListView = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget cardContent;

    if (isListView) {
      cardContent = Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 28, color: item.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ),
          if (!isDark)
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[300]),
          const SizedBox(width: 20),
        ],
      );
    } else {
      cardContent = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: 32, color: item.color),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      elevation: 4,
      shadowColor: item.color.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => item.page),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [item.color.withOpacity(0.15), Colors.transparent]
                  : [item.color.withOpacity(0.08), Colors.white],
            ),
          ),
          child: cardContent,
        ),
      ),
    );
  }

  //
}
