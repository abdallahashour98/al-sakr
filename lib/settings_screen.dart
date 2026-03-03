import 'package:flutter/material.dart';
import 'excel_service.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'main.dart';
import 'update_service.dart';
import 'users_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  final String _appVersion = "3.0.0 (Online)";

  // الكونترولرز (موجودين عشان يحافظوا على الداتا حتى لو مش ظاهرين)
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _taxNumberController = TextEditingController();

  // متغيرات الصلاحيات
  bool _isSuperAdmin = false;
  bool _canEditCompanySettings = false;
  bool _canBackupData = false;
  bool _canManageUsers = false;

  final String _superAdminId = "1sxo74splxbw1yh";

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadCompanyData();
  }

  void _checkPermission() {
    final user = SettingsService().pb.authStore.record;
    if (user != null) {
      final myId = user.id;
      final data = user.data;

      setState(() {
        _isSuperAdmin = (myId == _superAdminId);
        _canEditCompanySettings =
            _isSuperAdmin || (data['allow_edit_settings'] ?? false);
        _canBackupData = _isSuperAdmin || (data['allow_backup_data'] ?? false);
        _canManageUsers =
            _isSuperAdmin || (data['allow_manage_permissions'] ?? false);
      });
    }
  }

  // تحميل البيانات من الداتا بيز
  void _loadCompanyData() async {
    setState(() => _isLoading = true);
    final data = await SettingsService().getCompanySettings();
    if (data.isNotEmpty) {
      _companyNameController.text = data['companyName'] ?? '';
      _addressController.text = data['address'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _mobileController.text = data['mobile'] ?? '';
      _emailController.text = data['email'] ?? '';
      _websiteController.text = data['website'] ?? '';
      _taxNumberController.text = data['taxNumber'] ?? '';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveCompanyData() async {
    await _performAction(() async {
      await SettingsService().saveCompanySettings({
        'companyName':
            _companyNameController.text, // بيتحفظ زي ما هو من الداتا بيز
        'address': _addressController.text,
        'phone': _phoneController.text,
        'mobile': _mobileController.text,
        'email': _emailController.text,
        'website': _websiteController.text,
        'taxNumber': _taxNumberController.text, // بيتحفظ زي ما هو
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ بيانات الشركة بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  Future<void> _performAction(Future<void> Function() action) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await action();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('الإعدادات'), centerTitle: true),
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. المظهر واللغة
                  _buildSectionTitle('المظهر', Icons.palette, Colors.blueGrey),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 5,
                      ),
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeNotifier,
                        builder: (context, currentMode, child) {
                          return DropdownButtonHideUnderline(
                            child: DropdownButton<ThemeMode>(
                              value: currentMode,
                              isExpanded: true,
                              icon: const Icon(Icons.brightness_6),
                              items: const [
                                DropdownMenuItem(
                                  value: ThemeMode.system,
                                  child: Text('النظام (الافتراضي)'),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.light,
                                  child: Text('فاتح (Light Mode)'),
                                ),
                                DropdownMenuItem(
                                  value: ThemeMode.dark,
                                  child: Text('داكن (Dark Mode)'),
                                ),
                              ],
                              onChanged: (ThemeMode? newMode) async {
                                if (newMode != null) {
                                  themeNotifier.value = newMode;
                                  await SettingsService().saveThemeMode(
                                    newMode,
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  _buildSectionTitle(
                    'اللغة / Language',
                    Icons.language,
                    Colors.purple,
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 5,
                      ),
                      child: ValueListenableBuilder<Locale>(
                        valueListenable: localeNotifier,
                        builder: (context, currentLocale, child) {
                          return DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: currentLocale.languageCode,
                              isExpanded: true,
                              icon: const Icon(Icons.translate),
                              items: const [
                                DropdownMenuItem(
                                  value: 'ar',
                                  child: Text('العربية (RTL)'),
                                ),
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text('English (LTR)'),
                                ),
                              ],
                              onChanged: (String? newLang) async {
                                if (newLang != null) {
                                  localeNotifier.value = Locale(newLang);
                                  await SettingsService().saveLocale(newLang);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 20),

                  // 2. بيانات الشركة
                  if (_canEditCompanySettings) ...[
                    _buildSectionTitle(
                      'بيانات الشركة ',
                      Icons.business,
                      Colors.orange,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        leading: const Icon(
                          Icons.edit_note,
                          color: Colors.orange,
                        ),
                        title: const Text(
                          'تعديل بيانات الشركة',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(15.0),
                            child: Column(
                              children: [
                                // ❌❌ تم إخفاء اسم الشركة والرقم الضريبي من هنا
                                TextField(
                                  controller: _addressController,
                                  decoration: const InputDecoration(
                                    labelText: 'العنوان التفصيلي',
                                    prefixIcon: Icon(Icons.location_on),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _emailController,
                                  decoration: const InputDecoration(
                                    labelText: 'البريد الإلكتروني',
                                    prefixIcon: Icon(Icons.email),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _websiteController,
                                  decoration: const InputDecoration(
                                    labelText: 'الموقع الإلكتروني',
                                    prefixIcon: Icon(Icons.language),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _phoneController,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(
                                          labelText: 'TeleFax',
                                          prefixIcon: Icon(Icons.phone),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextField(
                                        controller: _mobileController,
                                        keyboardType: TextInputType.phone,
                                        decoration: const InputDecoration(
                                          labelText: 'Mobile',
                                          prefixIcon: Icon(Icons.smartphone),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange[800],
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: _saveCompanyData,
                                    icon: const Icon(Icons.save),
                                    label: const Text('حفظ التعديلات'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],

                  // 3. النسخ الاحتياطي
                  if (_canBackupData) ...[
                    _buildSectionTitle(
                      'التعامل مع Excel (Backup)',
                      Icons.table_chart,
                      Colors.green,
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: 'تصدير (Backup)',
                            icon: Icons.download,
                            color: Colors.green[700]!,
                            onTap: () async {
                              await _performAction(() async {
                                await ExcelService().exportFullBackup();
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('تم التصدير بنجاح'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: _buildActionButton(
                            label: 'استيراد (Restore)',
                            icon: Icons.upload_file,
                            color: Colors.green[900]!,
                            onTap: () async {
                              await _performAction(() async {
                                String res = await ExcelService()
                                    .importFullBackup();
                                if (mounted)
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('تقرير الاستيراد'),
                                      content: SingleChildScrollView(
                                        child: Text(res),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('حسنًا'),
                                        ),
                                      ],
                                    ),
                                  );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 20),
                    // داخل الـ build في المكان اللي تحبه
                    ListTile(
                      leading: const Icon(
                        Icons.system_update,
                        color: Colors.blue,
                      ),
                      title: const Text("التحقق من التحديثات"),
                      onTap: () {
                        // هنا بنبعت true عشان لو مفيش تحديث يطلع رسالة "أنت على آخر إصدار"
                        UpdateService().checkForUpdate(
                          context,
                          showNoUpdateMsg: true,
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    const Divider(),
                    const SizedBox(height: 20),
                  ],

                  // 4. الحساب والأمان
                  _buildSectionTitle(
                    'الحساب والأمان',
                    Icons.security,
                    Colors.redAccent,
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        if (_canManageUsers) ...[
                          ListTile(
                            leading: const Icon(
                              Icons.manage_accounts,
                              color: Colors.blueGrey,
                            ),
                            title: const Text("إدارة المستخدمين والصلاحيات"),
                            trailing: const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UsersScreen(),
                              ),
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                        ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text(
                            "تسجيل خروج",
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("تأكيد"),
                                content: const Text("هل تريد تسجيل الخروج؟"),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("إلغاء"),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () {
                                      AuthService().logout();
                                      Navigator.pop(ctx);
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const LoginScreen(),
                                        ),
                                        (route) => false,
                                      );
                                    },
                                    child: const Text("خروج"),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        const Text(
                          'Developed by',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Abdallah Ashour',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Version: $_appVersion',
                            style: TextStyle(
                              color: Colors.grey[800],
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
