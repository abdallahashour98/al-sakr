import 'package:flutter/material.dart';
import 'services/auth_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  // متغير لتخزين صلاحياتي أنا (المستخدم الحالي) للإدارة
  bool _iCanManagePermissions = false;

  // الآيدي الخاص بالسوبر أدمن (أنت)
  final String _superAdminId = "1sxo74splxbw1yh";

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _checkMyPermissions();
  }

  // فحص هل أنا أملك صلاحية إدارة المستخدمين
  void _checkMyPermissions() {
    final user = AuthService().pb.authStore.record;
    if (user != null) {
      setState(() {
        _iCanManagePermissions =
            (user.id == _superAdminId) ||
            (user.data['allow_manage_permissions'] == true);
      });
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await AuthService().getUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading users: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================================================
  // 1. ديالوج إضافة مستخدم جديد (تمت إعادته) ✅
  // ==================================================
  void _showAddUserDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String role = 'viewer';
    String? emailErrorText;
    const String fixedDomain = "@alsakr.com";

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("إضافة مستخدم جديد"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "الاسم",
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    labelText: "اسم المستخدم (بدون @)",
                    prefixIcon: const Icon(Icons.email),
                    suffixText: fixedDomain,
                    errorText: emailErrorText,
                  ),
                  onChanged: (val) {
                    if (emailErrorText != null)
                      setStateDialog(() => emailErrorText = null);
                  },
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "كلمة المرور",
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text("مدير (Admin)"),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text("مستخدم (User)"),
                    ),
                  ],
                  onChanged: (val) => setStateDialog(() => role = val!),
                  decoration: const InputDecoration(
                    labelText: "الصلاحية الأساسية",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("إلغاء"),
            ),
            ElevatedButton(
              onPressed: () async {
                String inputName = nameCtrl.text.trim();
                String inputUserPart = emailCtrl.text.trim();

                if (inputName.isEmpty || inputUserPart.isEmpty) return;

                if (inputUserPart.contains('@')) {
                  setStateDialog(
                    () => emailErrorText = "اكتب الاسم فقط بدون @alsakr.com",
                  );
                  return;
                }

                if (passCtrl.text.length < 5) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("كلمة المرور قصيرة جداً")),
                  );
                  return;
                }

                try {
                  // دمج الاسم مع الدومين
                  String finalEmail = "$inputUserPart$fixedDomain";

                  await AuthService().createUser(
                    inputName,
                    finalEmail,
                    passCtrl.text,
                    role,
                  );

                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadUsers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم إضافة المستخدم بنجاح ✅"),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (e.toString().contains("email") ||
                      e.toString().contains("unique")) {
                    setStateDialog(
                      () => emailErrorText = "هذا الاسم مستخدم بالفعل!",
                    );
                  } else {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("خطأ: $e")));
                  }
                }
              },
              child: const Text("حفظ"),
            ),
          ],
        ),
      ),
    );
  }

  // ==================================================
  // 2. ديالوج الصلاحيات التفصيلية (الشاشات + الإجراءات)
  // ==================================================
  // 2. ديالوج الصلاحيات التفصيلية (تم التحديث لإضافة الإعدادات)
  // ==================================================
  // 2. ديالوج الصلاحيات المطور (Groups & Modules)
  // ==================================================
  void _showUserPermissionsDialog(Map<String, dynamic> user) {
    // تجهيز خريطة الصلاحيات الحالية
    Map<String, bool> perms = {
      // --- الإدارة والأمان ---
      'allow_manage_permissions': user['allow_manage_permissions'] ?? false,
      'allow_edit_settings': user['allow_edit_settings'] ?? false,
      'allow_backup_data': user['allow_backup_data'] ?? false,

      // --- المبيعات ---
      'show_sales': user['show_sales'] ?? false,
      'show_sales_history': user['show_sales_history'] ?? false, // سجل المبيعات
      'allow_add_orders': user['allow_add_orders'] ?? false,
      'allow_edit_orders': user['allow_edit_orders'] ?? false,
      'allow_delete_orders': user['allow_delete_orders'] ?? false,
      'allow_add_returns': user['allow_add_returns'] ?? false, // مرتجع بيع
      // --- المشتريات ---
      'show_purchases': user['show_purchases'] ?? false,
      'show_purchase_history':
          user['show_purchase_history'] ?? false, // سجل المشتريات
      'allow_add_purchases': user['allow_add_purchases'] ?? false,
      'allow_edit_purchases': user['allow_edit_purchases'] ?? false,
      'allow_delete_purchases': user['allow_delete_purchases'] ?? false,

      // --- المخزن ---
      'show_stock': user['show_stock'] ?? false,
      'allow_add_products': user['allow_add_products'] ?? false,
      'allow_edit_products': user['allow_edit_products'] ?? false,
      'allow_delete_products': user['allow_delete_products'] ?? false,
      'show_delivery': user['show_delivery'] ?? false, // أذونات التسليم
      'allow_add_delivery': user['allow_add_delivery'] ?? false,
      'allow_delete_delivery': user['allow_delete_delivery'] ?? false,

      // --- العملاء والموردين ---
      'show_clients': user['show_clients'] ?? false,
      'show_suppliers': user['show_suppliers'] ?? false,
      'allow_add_clients': user['allow_add_clients'] ?? false, // إضافة وتعديل
      'allow_delete_clients': user['allow_delete_clients'] ?? false,

      // --- المصروفات ---
      'show_expenses': user['show_expenses'] ?? false,
      'allow_add_expenses': user['allow_add_expenses'] ?? false,
      'allow_delete_expenses': user['allow_delete_expenses'] ?? false,

      // --- التقارير (منفصلة) ---
      'show_reports':
          user['show_reports'] ?? false, // شاشة الرسوم البيانية والأرباح
      'show_returns':
          user['show_returns'] ?? false, // شاشة سجل المرتجعات المجمع
      'allow_delete_returns': user['allow_delete_returns'] ?? false,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(
              "صلاحيات: ${user['name']}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  // 1. قسم الإدارة العليا
                  _buildModuleHeader("👑 الإدارة والأمان", Colors.purple),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_manage_permissions',
                    'إدارة المستخدمين والصلاحيات',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_edit_settings',
                    'تعديل إعدادات الشركة',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_backup_data',
                    'النسخ الاحتياطي (Backup)',
                  ),
                  const SizedBox(height: 15),

                  // 2. قسم المبيعات
                  _buildModuleHeader("🛒 المبيعات والعملاء", Colors.blue),
                  _buildSectionLabel("الشاشات:"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_sales',
                    'فتح شاشة البيع ',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_sales_history',
                    'فتح سجل الفواتير السابق',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_clients',
                    'فتح شاشة العملاء',
                  ),
                  _buildSectionLabel("الإجراءات (التحكم):"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_add_orders',
                    '✅ إضافة/حفظ فاتورة',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_edit_orders',
                    '✏️ تعديل فاتورة قديمة',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_orders',
                    '🗑️ حذف فاتورة',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_add_clients',
                    '➕ إضافة/تعديل عميل',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_clients',
                    '❌ حذف عميل',
                  ),
                  const SizedBox(height: 15),

                  // 3. قسم المشتريات
                  _buildModuleHeader("🚚 المشتريات والموردين", Colors.brown),
                  _buildSectionLabel("الشاشات:"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_purchases',
                    'فتح شاشة الشراء (التوريد)',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_purchase_history',
                    'فتح سجل المشتريات السابق',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_suppliers',
                    'فتح شاشة الموردين',
                  ),
                  _buildSectionLabel("الإجراءات (التحكم):"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_add_purchases',
                    '✅ إضافة فاتورة شراء',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_edit_purchases',
                    '✏️ تعديل فاتورة شراء',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_purchases',
                    '🗑️ حذف فاتورة شراء',
                  ),
                  const SizedBox(height: 15),

                  // 4. قسم المخزن
                  _buildModuleHeader("📦 المخزن والأصناف", Colors.orange[800]!),
                  _buildSectionLabel("الشاشات:"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_stock',
                    'فتح شاشة المخزن',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_delivery',
                    'فتح أذونات التسليم',
                  ),
                  _buildSectionLabel("الإجراءات (التحكم):"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_add_products',
                    '➕ تعريف صنف جديد',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_edit_products',
                    '✏️ تعديل بيانات صنف',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_products',
                    '🗑️ حذف صنف نهائياً',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_add_delivery',
                    '📝 إنشاء إذن تسليم',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_delivery',
                    '❌ حذف إذن تسليم',
                  ),
                  const SizedBox(height: 15),

                  // 5. قسم المالية والتقارير
                  _buildModuleHeader(
                    "💰 المالية والتقارير",
                    Colors.green[700]!,
                  ),
                  _buildSectionLabel("الشاشات:"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_expenses',
                    'فتح شاشة المصروفات',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_reports',
                    '📊 التقارير الشاملة ',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'show_returns',
                    '↩️ سجل المرتجعات العام',
                  ),
                  _buildSectionLabel("الإجراءات (التحكم):"),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_add_expenses',
                    '💸 تسجيل مصروف',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_expenses',
                    '❌ حذف مصروف',
                  ),
                  _buildPermissionItem(
                    setStateDialog,
                    perms,
                    'allow_delete_returns',
                    '🗑️ حذف مرتجع',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء"),
              ),
              ElevatedButton(
                onPressed: () async {
                  await AuthService().updateUser(user['id'], perms);
                  if (mounted) {
                    Navigator.pop(ctx);
                    _loadUsers();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم تحديث الصلاحيات بنجاح ✅"),
                      ),
                    );
                  }
                },
                child: const Text("حفظ التغييرات"),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- Widgets للتنظيم البصري ---

  // 1. عنوان القسم (مع خلفية ملونة خفيفة)
  Widget _buildModuleHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.layers, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // 2. عنوان فرعي صغير (شاشات / إجراءات)
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4, right: 10, left: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  // 3. زر التبديل (Switch)
  Widget _buildPermissionItem(
    Function setStateDialog,
    Map<String, bool> perms,
    String key,
    String label,
  ) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: perms[key] ?? false,
      activeColor: Colors.blue,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 15),
      visualDensity: VisualDensity.compact,
      // ✅ التعديل هنا: إضافة (?? false) عشان لو القيمة راجعة null نعتبرها false
      onChanged: (val) => setStateDialog(() => perms[key] = val ?? false),
    );
  }

  Widget _buildSwitch(
    Function setStateDialog,
    Map<String, bool> perms,
    String key,
    String label, {
    Color color = Colors.blue,
  }) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      value: perms[key] ?? false,
      activeThumbColor: color,
      dense: true,
      contentPadding: EdgeInsets.zero,
      onChanged: (val) => setStateDialog(() => perms[key] = val),
    );
  }

  // ==================================================
  // 3. ديالوج تعديل البيانات الأساسية
  // ==================================================
  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameCtrl = TextEditingController(text: user['name']);
    String role = user['role'] ?? 'viewer';
    bool isTargetSuperAdmin = (user['id'] == _superAdminId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تعديل البيانات"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "الاسم"),
            ),
            const SizedBox(height: 10),
            if (!isTargetSuperAdmin)
              DropdownButtonFormField<String>(
                initialValue: role,
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text("مدير")),
                  DropdownMenuItem(value: 'viewer', child: Text("مستخدم")),
                ],
                onChanged: (v) => role = v!,
                decoration: const InputDecoration(labelText: "الرتبة"),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () async {
              await AuthService().updateUser(user['id'], {
                'name': nameCtrl.text,
                'role': isTargetSuperAdmin ? 'admin' : role,
              });
              if (mounted) {
                Navigator.pop(ctx);
                _loadUsers();
              }
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // 4. ديالوج تغيير كلمة المرور
  // ==================================================
  void _showChangePassDialog(String userId) {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تغيير كلمة المرور"),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(labelText: "الجديدة"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (c.text.length < 5) return;
              await AuthService().updateUserPassword(userId, c.text);
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("تم")));
              }
            },
            child: const Text("حفظ"),
          ),
        ],
      ),
    );
  }

  // ==================================================
  // 5. وظيفة الحذف
  // ==================================================
  void _deleteUser(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("حذف"),
        content: const Text("متأكد؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إلغاء"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await AuthService().deleteUser(id);
              if (mounted) {
                Navigator.pop(ctx);
                _loadUsers();
              }
            },
            child: const Text("حذف"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService().pb.authStore.record;
    final myId = currentUser?.id;
    final bool amISuperAdmin = (myId == _superAdminId);

    // إذا كنت سوبر أدمن، أو أملك صلاحية الإدارة -> أرى كل المستخدمين
    // غير ذلك -> أرى نفسي فقط
    final bool canViewAll = amISuperAdmin || _iCanManagePermissions;
    final displayList = canViewAll
        ? _users
        : _users.where((u) => u['id'] == myId).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("إدارة المستخدمين")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: displayList.length,
              itemBuilder: (ctx, i) {
                final user = displayList[i];
                final bool isTargetSuperAdmin = (user['id'] == _superAdminId);

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isTargetSuperAdmin
                          ? Colors.purple
                          : Colors.blueGrey,
                      child: Icon(
                        isTargetSuperAdmin ? Icons.shield : Icons.person,
                        color: Colors.white,
                      ),
                    ),
                    title: Text(user['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['email'].isEmpty && isTargetSuperAdmin
                              ? "Super Admin"
                              : user['email'],
                        ),
                        if (canViewAll)
                          SelectableText(
                            "ID: ${user['id']}",
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),

                    trailing: PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'edit') _showEditUserDialog(user);
                        if (val == 'pass') _showChangePassDialog(user['id']);
                        if (val == 'perms') _showUserPermissionsDialog(user);
                        if (val == 'delete') _deleteUser(user['id']);
                      },
                      itemBuilder: (c) {
                        bool hasEditRights =
                            amISuperAdmin || _iCanManagePermissions;
                        bool targetIsSafe =
                            isTargetSuperAdmin && !amISuperAdmin;

                        return [
                          if (hasEditRights && !targetIsSafe)
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('تعديل البيانات'),
                            ),
                          if (hasEditRights && !targetIsSafe)
                            const PopupMenuItem(
                              value: 'pass',
                              child: Text('تغيير كلمة المرور'),
                            ),
                          if (hasEditRights && !isTargetSuperAdmin)
                            const PopupMenuItem(
                              value: 'perms',
                              child: Text(
                                '👑 تعديل الصلاحيات',
                                style: TextStyle(color: Colors.deepPurple),
                              ),
                            ),
                          if (hasEditRights && !targetIsSafe)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text(
                                'حذف',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                        ];
                      },
                    ),
                  ),
                );
              },
            ),
      // زر الإضافة العائم (عاد للعمل) ✅
      floatingActionButton: (amISuperAdmin || _iCanManagePermissions)
          ? FloatingActionButton(
              onPressed: _showAddUserDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
