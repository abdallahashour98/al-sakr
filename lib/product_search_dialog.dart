import 'package:flutter/material.dart';

class ProductSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> allProducts;

  const ProductSearchDialog({Key? key, required this.allProducts})
    : super(key: key);

  @override
  State<ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends State<ProductSearchDialog> {
  List<Map<String, dynamic>> _filteredProducts = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredProducts = widget.allProducts;
  }

  void _runFilter(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = widget.allProducts;
      } else {
        _filteredProducts = widget.allProducts
            .where(
              (item) => item['name'].toString().toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(16),
        height: 500, // ارتفاع النافذة
        child: Column(
          children: [
            const Text(
              "بحث عن صنف",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            // --- خانة البحث ---
            TextField(
              controller: _searchCtrl,
              onChanged: _runFilter,
              decoration: InputDecoration(
                hintText: 'اكتب اسم الصنف...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
            const SizedBox(height: 10),

            // --- القائمة ---
            Expanded(
              child: _filteredProducts.isNotEmpty
                  ? ListView.separated(
                      itemCount: _filteredProducts.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = _filteredProducts[index];
                        return ListTile(
                          // هنا يظهر الاسم فقط (بدون الكود)
                          title: Text(
                            product['name'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          onTap: () {
                            // عند الاختيار نرجع بيانات الصنف بالكامل
                            Navigator.pop(context, product);
                          },
                        );
                      },
                    )
                  : const Center(child: Text("لا توجد نتائج")),
            ),

            // زر الإغلاق
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("إلغاء", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
