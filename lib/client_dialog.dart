import 'package:al_sakr/services/sales_service.dart';
import 'package:flutter/material.dart';

class ClientDialog extends StatefulWidget {
  final Map<String, dynamic>? client;
  const ClientDialog({super.key, this.client});

  @override
  State<ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<ClientDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _openingBalanceController = TextEditingController(text: '0');
  String _balanceType = 'debit';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.client != null) _initData();
  }

  void _initData() async {
    final c = widget.client!;
    _nameController.text = c['name'];
    _phoneController.text = c['phone'] ?? '';
    _addressController.text = c['address'] ?? '';
    double openBal = await SalesService().getClientOpeningBalance(c['id']);
    _openingBalanceController.text = openBal.abs().toString();
    setState(() => _balanceType = openBal >= 0 ? 'debit' : 'credit');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      insetPadding: const EdgeInsets.all(15),
      child: Container(
        width: 500, // عرض مناسب للديالوج
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min, // يأخذ حجم المحتوى فقط
          children: [
            Text(
              widget.client != null ? 'تعديل بيانات العميل' : 'إضافة عميل جديد',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 15),

            // منطقة السكرول (هنا الحل السحري)
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: 'الاسم',
                        prefixIcon: const Icon(Icons.person),
                        filled: true,
                        fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: 'الهاتف',
                        prefixIcon: const Icon(Icons.phone),
                        filled: true,
                        fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: 'العنوان',
                        prefixIcon: const Icon(Icons.location_on),
                        filled: true,
                        fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const Divider(height: 20),

                    const Text(
                      'الرصيد الافتتاحي',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _openingBalanceController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: 'المبلغ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        isDense: true,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile(
                            title: const Text(
                              'مدين (عليه)',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: 'debit',
                            groupValue: _balanceType,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) =>
                                setState(() => _balanceType = v.toString()),
                          ),
                        ),
                        Expanded(
                          child: RadioListTile(
                            title: const Text(
                              'دائن (له)',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: 'credit',
                            groupValue: _balanceType,
                            contentPadding: EdgeInsets.zero,
                            onChanged: (v) =>
                                setState(() => _balanceType = v.toString()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("إلغاء"),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[800],
                    ),
                    onPressed: _isLoading ? null : _saveClient,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            "حفظ",
                            style: TextStyle(color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveClient() async {
    if (_nameController.text.isEmpty) return;
    setState(() => _isLoading = true);
    // ... نفس كود الحفظ القديم ...
    Map<String, dynamic> data = {
      'name': _nameController.text,
      'phone': _phoneController.text,
      'address': _addressController.text,
    };

    try {
      String clientId;
      if (widget.client == null) {
        data['balance'] = 0.0;
        final rec = await SalesService().insertClient(data);
        clientId = rec.id;
      } else {
        await SalesService().updateClient(widget.client!['id'], data);
        clientId = widget.client!['id'];
      }

      double amount = double.tryParse(_openingBalanceController.text) ?? 0.0;
      double finalBal = (_balanceType == 'debit') ? amount : -amount;
      await SalesService().updateClientOpeningBalance(clientId, finalBal);

      if (mounted) {
        Navigator.pop(context, {'id': clientId, 'name': data['name']});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        setState(() => _isLoading = false);
      }
    }
  }
}
