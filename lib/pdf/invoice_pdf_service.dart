import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

import '../services/settings_service.dart';

class InvoicePdfService {
  /// دالة مساعدة لتنسيق الأرقام (1500.00 -> 1,500)
  static String formatNumber(dynamic number) {
    if (number == null) return "0";
    double numVal = double.tryParse(number.toString()) ?? 0.0;
    final formatter = NumberFormat("#,###.##");
    return formatter.format(numVal);
  }

  static Future<void> generateInvoice(
    Map<String, dynamic> sale,
    List<Map<String, dynamic>> items,
  ) async {
    final pdf = pw.Document();

    // 1. إعدادات الشركة
    String address = 'Address not set';
    String phone = '---';
    String mobile = '---';
    String Website = '---';
    String email = '---';

    try {
      final companyData = await SettingsService().getCompanySettings();
      address = companyData['address'] ?? address;
      phone = companyData['phone'] ?? phone;
      mobile = companyData['mobile'] ?? mobile;
      Website = companyData['website'] ?? Website;
      email = companyData['email'] ?? email;
    } catch (_) {}

    // 2. تجهيز البيانات
    String rawDate = sale['date'].toString();
    String formattedDate = rawDate.split(' ')[0];
    try {
      DateTime parsedDate = DateTime.parse(rawDate);
      formattedDate = DateFormat('yyyy-MM-dd').format(parsedDate);
    } catch (_) {}

    String refNumber =
        sale['referenceNumber'] ?? sale['id'].toString().substring(0, 5);
    String clientName = sale['clientName'] ?? 'Cash Client';
    String paymentType = sale['paymentType'] == 'cash' ? 'Cash' : 'postpaid';

    // 3. الخطوط
    final fontData = await rootBundle.load("assets/fonts/Amiri-Regular.ttf");
    final ttf = pw.Font.ttf(fontData);
    pw.Font ttfBold = ttf;
    try {
      final fontDataBold = await rootBundle.load("assets/fonts/Amiri-Bold.ttf");
      ttfBold = pw.Font.ttf(fontDataBold);
    } catch (_) {}

    // 4. اللوجو
    pw.MemoryImage? imageProvider;
    try {
      final logoImage = await rootBundle.load('assets/splash_logo.png');
      imageProvider = pw.MemoryImage(logoImage.buffer.asUint8List());
    } catch (_) {
      imageProvider = null;
    }

    // --- بناء الصفحة ---
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        textDirection: pw.TextDirection.ltr,

        build: (pw.Context context) {
          return [
            // ================= Header Section =================
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Logo & Company Info
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    if (imageProvider != null)
                      pw.Container(
                        width: 80,
                        height: 80,
                        child: pw.Image(imageProvider),
                      ),
                    if (imageProvider != null) pw.SizedBox(width: 10),

                    pw.Container(width: 1, height: 80, color: PdfColors.black),
                    pw.SizedBox(width: 10),

                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(height: 5),
                        pw.Text(
                          address,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.Text(
                          "$phone / $mobile",
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.Text(
                          Website,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.black,
                          ),
                        ),
                        pw.Text(
                          email,
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Invoice Info Box
                pw.Container(
                  width: 180,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(4),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        "INVOICE",
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 2,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.Divider(color: PdfColors.grey400),
                      _buildInfoRow("NO:", "#$refNumber"),
                      _buildInfoRow("DATE:", formattedDate),
                      _buildInfoRow("CLIENT:", clientName),
                      _buildInfoRow("TYPE:", paymentType),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 40),

            // ================= Items Table =================
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                columnWidths: {
                  0: const pw.FixedColumnWidth(40), // No
                  1: const pw.FlexColumnWidth(4), // Item
                  2: const pw.FlexColumnWidth(1), // Qty
                  3: const pw.FlexColumnWidth(1.5), // Price
                  4: const pw.FlexColumnWidth(1.5), // Total
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                    children: [
                      _buildCell("No", isHeader: true),
                      _buildCell(
                        "Item / Description",
                        isHeader: true,
                        align: pw.Alignment.center,
                      ),
                      _buildCell("Qty", isHeader: true),
                      _buildCell("Price", isHeader: true),
                      _buildCell("Total Price", isHeader: true),
                    ],
                  ),
                  ...List.generate(items.length, (index) {
                    final item = items[index];
                    final qty = (item['quantity'] as num);
                    final price = (item['price'] as num);
                    final total = qty * price;
                    return pw.TableRow(
                      children: [
                        _buildCell((index + 1).toString()),
                        _buildCell(
                          item['productName'] ?? item['name'] ?? '',
                          align: pw.Alignment.center,
                        ),
                        _buildCell(formatNumber(qty)),
                        _buildCell(formatNumber(price)),
                        _buildCell(formatNumber(total), isBold: true),
                      ],
                    );
                  }),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // ================= Totals Table (Modified) =================
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Container(
                  width: 250, // عرض مناسب للجدول
                  child: pw.Table(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                    children: [
                      // 1. Total Amount
                      pw.TableRow(
                        children: [
                          _buildSummaryCell("Total Amount"),
                          _buildSummaryCell(
                            formatNumber(sale['totalAmount']),
                            align: pw.Alignment.centerRight,
                          ),
                        ],
                      ),

                      // 2. Discount (Only if exists)
                      if ((sale['discount'] ?? 0) > 0)
                        pw.TableRow(
                          children: [
                            _buildSummaryCell("Discount", color: PdfColors.red),
                            _buildSummaryCell(
                              "- ${formatNumber(sale['discount'])}",
                              color: PdfColors.red,
                              align: pw.Alignment.centerRight,
                            ),
                          ],
                        ),

                      // 3. VAT (Only if exists)
                      if ((sale['taxAmount'] ?? 0) > 0)
                        pw.TableRow(
                          children: [
                            _buildSummaryCell("VAT (14%)"),
                            _buildSummaryCell(
                              "+ ${formatNumber(sale['taxAmount'])}",
                              align: pw.Alignment.centerRight,
                            ),
                          ],
                        ),

                      // 4. WHT (Only if exists)
                      if ((sale['whtAmount'] ?? 0) > 0)
                        pw.TableRow(
                          children: [
                            _buildSummaryCell("WHT (1%)"),
                            _buildSummaryCell(
                              "- ${formatNumber(sale['whtAmount'])}",
                              align: pw.Alignment.centerRight,
                            ),
                          ],
                        ),

                      // 5. Net Total (With Background)
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey300,
                        ),
                        children: [
                          _buildSummaryCell(
                            "Net Total",
                            isBold: true,
                            fontSize: 12,
                          ),
                          _buildSummaryCell(
                            formatNumber(sale['netAmount']),
                            isBold: true,
                            fontSize: 12,
                            align: pw.Alignment.centerRight,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.Spacer(),
          ];
        },
      ),
    );

    try {
      final output = await getApplicationDocumentsDirectory();
      final file = File("${output.path}/Invoice_$refNumber.pdf");
      await file.writeAsBytes(await pdf.save());
      await OpenFile.open(file.path);
    } catch (e) {
      print("Error opening PDF: $e");
    }
  }

  // ================= Helpers =================

  static pw.Widget _buildInfoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 9),
              textAlign: pw.TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildCell(
    String text, {
    bool isHeader = false,
    pw.Alignment align = pw.Alignment.center,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: isHeader ? 10 : 9,
            fontWeight: (isHeader || isBold)
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
            color: isHeader ? PdfColors.blue900 : PdfColors.black,
          ),
        ),
      ),
    );
  }

  // خلية خاصة لجدول الإجماليات
  static pw.Widget _buildSummaryCell(
    String text, {
    PdfColor? color,
    bool isBold = false,
    double fontSize = 10,
    pw.Alignment align = pw.Alignment.centerLeft, // Default left for labels
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? PdfColors.black,
          ),
        ),
      ),
    );
  }
}
