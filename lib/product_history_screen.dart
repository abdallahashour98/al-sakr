import 'package:al_sakr/services/inventory_service.dart';
import 'package:flutter/material.dart';

class ProductHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductHistoryScreen({super.key, required this.product});

  @override
  State<ProductHistoryScreen> createState() => _ProductHistoryScreenState();
}

class _ProductHistoryScreenState extends State<ProductHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() async {
    // ✅ الـ ID أصبح String ويتم جلبه من PBHelper
    final data = await InventoryService().getProductHistory(
      widget.product['id'],
    );
    if (mounted) {
      setState(() {
        _history = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text('سجل حركات: ${widget.product['name']}')),
      body: Column(
        children: [
          // كارت ملخص سريع
          Container(
            padding: const EdgeInsets.all(15),
            color: isDark ? Colors.grey[900] : Colors.blue[50],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('الرصيد الحالي'),
                    Text(
                      '${widget.product['stock']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('سعر البيع'),
                    Text(
                      '${widget.product['sellPrice']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // قائمة الحركات
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                ? const Center(child: Text('لا توجد حركات مسجلة لهذا الصنف'))
                : ListView.builder(
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];
                      Color color;
                      IconData icon;

                      if (item['type'] == 'بيع') {
                        color = Colors.green;
                        icon = Icons.arrow_upward;
                      } else if (item['type'] == 'شراء') {
                        color = Colors.blue;
                        icon = Icons.arrow_downward;
                      } else {
                        // مرتجع
                        color = Colors.orange;
                        icon = Icons.refresh;
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.1),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        title: Text(
                          '${item['type']} - الكمية: ${item['quantity']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${item['date'].toString().split(' ')[0]} ${item['ref'] != '' ? "(${item['ref']})" : ""}',
                        ),
                        trailing: Text(
                          '${item['price']} ج.م',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
