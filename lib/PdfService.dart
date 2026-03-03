import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/settings_service.dart';

class PdfService {
  static Future<void> generateDeliveryOrderPdf(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> items,
  ) async {
    final pdf = pw.Document();

    // 1. إعداد البيانات
    final companyData = await SettingsService().getCompanySettings();
    String address =
        companyData['address'] ??
        '18 Al-Ansar st. Dokki – Giza – Postal Code 12311';
    String phone = companyData['phone'] ?? '0237622293';
    String mobile = companyData['mobile'] ?? '01001409814 - 01280973000';
    String email = companyData['email'] ?? 'info@alsakr-computer.com';
    String website = "www.alsakr-computer.com";

    String rawDate =
        order['date'] ?? order['deliveryDate'] ?? DateTime.now().toString();
    String formattedDate = rawDate.split(' ')[0];

    // تحميل الخطوط
    final fontDataAr = await rootBundle.load(
      "assets/fonts/Traditional-Arabic.ttf",
    );
    final ttfAr = pw.Font.ttf(fontDataAr);
    final fontDataEn = await rootBundle.load("assets/fonts/Tinos-Regular.ttf");
    final ttfEn = pw.Font.ttf(fontDataEn);
    final fontDataEnBold = await rootBundle.load("assets/fonts/Tinos-Bold.ttf");
    final ttfEnBold = pw.Font.ttf(fontDataEnBold);

    final logoImage = await rootBundle.load('assets/splash_logo.png');
    final imageProvider = pw.MemoryImage(logoImage.buffer.asUint8List());

    // تجهيز الصفوف
    List<Map<String, dynamic>> processedRows = [];
    Map<String, List<Map<String, dynamic>>> groups = {};
    String mainOrderNumber = order['supplyOrderNumber'] ?? '---';

    Set<String> allSupplyOrders = {};
    if (order['supplyOrderNumber'] != null &&
        order['supplyOrderNumber'].toString().isNotEmpty) {
      allSupplyOrders.add(order['supplyOrderNumber'].toString());
    }
    for (var item in items) {
      if (item['relatedSupplyOrder'] != null &&
          item['relatedSupplyOrder'].toString().isNotEmpty) {
        allSupplyOrders.add(item['relatedSupplyOrder'].toString());
      }
    }
    String combinedSupplyOrdersText = allSupplyOrders.isEmpty
        ? "---"
        : (allSupplyOrders.length == 1
              ? allSupplyOrders.first
              : "[ ${allSupplyOrders.join(' - ')} ]");

    for (var item in items) {
      String key =
          item['relatedSupplyOrder'] != null &&
              item['relatedSupplyOrder'].toString().isNotEmpty
          ? item['relatedSupplyOrder']
          : 'MAIN_ORDER';
      if (!groups.containsKey(key)) groups[key] = [];
      groups[key]!.add(item);
    }

    bool showSectionHeaders = groups.length > 1;
    void addGroupToRows(
      String title,
      List<Map<String, dynamic>> groupItems,
      bool isMain,
    ) {
      if (showSectionHeaders) {
        processedRows.add({
          'type': 'header',
          'title': isMain ? mainOrderNumber : title,
        });
      }
      for (int i = 0; i < groupItems.length; i++) {
        processedRows.add({'type': 'item', 'data': groupItems[i]});
      }
    }

    if (groups.containsKey('MAIN_ORDER')) {
      addGroupToRows(mainOrderNumber, groups['MAIN_ORDER']!, true);
      groups.remove('MAIN_ORDER');
    }
    groups.forEach(
      (orderNum, groupItems) => addGroupToRows(orderNum, groupItems, false),
    );

    int totalQty = 0;
    for (var item in items) {
      totalQty += int.tryParse(item['quantity'].toString()) ?? 0;
    }

    // إعدادات الحدود
    const borderSide = pw.BorderSide(color: PdfColors.black, width: 0.8);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(
          base: ttfAr,
          fontFallback: [ttfEn, ttfEnBold],
        ),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              // 1. الهيدر (ارتفاع ثابت)
              pw.Container(
                height: 220,
                child: _buildHeaderContent(
                  imageProvider,
                  address,
                  phone,
                  mobile,
                  website,
                  email,
                  order,
                  formattedDate,
                  combinedSupplyOrdersText,
                  ttfAr,
                  ttfEn,
                  ttfEnBold,
                ),
              ),

              pw.SizedBox(height: 10),

              // 2. الجدول الديناميكي (يملأ الصفحة للأسفل)
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      // ✅ التعديل هنا: خلينا سُمك الخط العلوي 2.0 عشان يكون تقيل وواضح
                      top: pw.BorderSide(color: PdfColors.black, width: 2.0),
                      left: borderSide,
                      right: borderSide,
                      // ⚠️ لا يوجد حد سفلي هنا لأن صف "فقط وقدره" سيغلقه
                    ),
                  ),
                  child: pw.Stack(
                    children: [
                      // الطبقة الخلفية: خطوط الطول (Grid Lines)
                      pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // عمود البيان
                          pw.Expanded(
                            flex: 4,
                            child: pw.Container(
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(right: borderSide),
                              ),
                            ),
                          ),
                          // عمود العدد
                          pw.Expanded(
                            flex: 1,
                            child: pw.Container(
                              decoration: const pw.BoxDecoration(
                                border: pw.Border(right: borderSide),
                              ),
                            ),
                          ),
                          // عمود الوحدة
                          pw.Expanded(flex: 1, child: pw.Container()),
                        ],
                      ),

                      // الطبقة الأمامية: المحتوى
                      pw.Column(
                        children: [
                          // أ. ترويسة الجدول (Header Row)
                          pw.Container(
                            height: 35,
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.grey200,
                              border: pw.Border(bottom: borderSide),
                            ),
                            child: pw.Row(
                              children: [
                                _buildCellContent(
                                  flex: 4,
                                  borderRight: true,
                                  // ✅ التوسيط (البيان في المنتصف)
                                  alignment: pw.Alignment.center,
                                  child: _buildHeaderCellTitle(
                                    "البيان",
                                    "Description",
                                    ttfAr,
                                    ttfEnBold,
                                  ),
                                ),
                                _buildCellContent(
                                  flex: 1,
                                  borderRight: true,
                                  alignment: pw.Alignment.center,
                                  child: _buildHeaderCellTitle(
                                    "العدد",
                                    "Quantity",
                                    ttfAr,
                                    ttfEnBold,
                                  ),
                                ),
                                _buildCellContent(
                                  flex: 1,
                                  borderRight: false,
                                  alignment: pw.Alignment.center,
                                  child: _buildHeaderCellTitle(
                                    "الوحدة",
                                    "Unit",
                                    ttfAr,
                                    ttfEnBold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ب. صفوف الأصناف
                          ...processedRows.map((row) {
                            if (row['type'] == 'header') {
                              return pw.Container(
                                width: double.infinity,
                                padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: const pw.BoxDecoration(
                                  color: PdfColors.grey100,
                                  border: pw.Border(bottom: borderSide),
                                ),
                                child: pw.Text(
                                  "${row['title']}",
                                  style: pw.TextStyle(
                                    font: ttfEnBold,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              );
                            } else {
                              final data = row['data'] as Map<String, dynamic>;
                              String unitText =
                                  data['unit'] ?? data['category'] ?? 'قطعة';
                              return pw.Container(
                                // ✅ إضافة خط فاصل أسفل كل صنف
                                decoration: const pw.BoxDecoration(
                                  border: pw.Border(bottom: borderSide),
                                ),
                                child: pw.Row(
                                  children: [
                                    _buildCellContent(
                                      flex: 4,
                                      padding: 5,
                                      child: pw.Column(
                                        crossAxisAlignment:
                                            pw.CrossAxisAlignment.start,
                                        children: [
                                          pw.Text(
                                            data['productName'],
                                            style: pw.TextStyle(
                                              font: ttfEnBold,
                                              fontSize: 12,
                                              fontWeight: pw.FontWeight.bold,
                                            ),
                                          ),
                                          if (data['description'] != null &&
                                              data['description']
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty &&
                                              data['description'] !=
                                                  data['productName'])
                                            pw.Padding(
                                              padding: const pw.EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: pw.Text(
                                                data['description'],
                                                style: pw.TextStyle(
                                                  font: ttfEn,
                                                  fontSize: 10,
                                                  color: PdfColors.grey700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    _buildCellContent(
                                      flex: 1,
                                      padding: 5,
                                      alignment: pw.Alignment.center,
                                      child: pw.Text(
                                        "${data['quantity']}",
                                        style: pw.TextStyle(
                                          font: ttfEn,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    _buildCellContent(
                                      flex: 1,
                                      padding: 5,
                                      alignment: pw.Alignment.center,
                                      child: pw.Directionality(
                                        textDirection: pw
                                            .TextDirection
                                            .rtl, // ✅ عشان الكلمة العربي تتظبط
                                        child: pw.Text(
                                          unitText,
                                          style: pw.TextStyle(
                                            font:
                                                ttfAr, // ✅ تم التغيير لخط عربي عشان يقرأ "كرتونة"، "علبة"
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                          }).toList(),

                          // ج. Spacer لدفع المجموع للأسفل
                          pw.Spacer(),

                          // د. صف المجموع
                          pw.Container(
                            height: 35,
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(top: borderSide),
                            ),
                            child: pw.Row(
                              children: [
                                _buildCellContent(
                                  flex: 4,
                                  alignment: pw.Alignment.center,
                                  child: pw.Text(
                                    "Total",
                                    style: pw.TextStyle(
                                      font: ttfEnBold,
                                      fontSize: 12,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _buildCellContent(
                                  flex: 1,
                                  alignment: pw.Alignment.center,
                                  child: pw.Text(
                                    "$totalQty",
                                    style: pw.TextStyle(
                                      font: ttfEnBold,
                                      fontSize: 12,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                ),
                                _buildCellContent(
                                  flex: 1,
                                  alignment: pw.Alignment.center,
                                  child: pw.Text(
                                    "ITEMS",
                                    style: pw.TextStyle(
                                      font: ttfEnBold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // هـ. سطر "فقط وقدره" (مدمج ويغلق الجدول)
                          // هـ. سطر "فقط وقدره" (مدمج ويغلق الجدول بخط سميك)
                          pw.Container(
                            height: 30,
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5,
                            ),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.white,
                              border: pw.Border(
                                top: borderSide,
                                left: borderSide,
                                right: borderSide,
                                // ✅ هنا التعديل: جعلنا الخط السفلي سميكاً (عرض 2.0)
                                bottom: pw.BorderSide(
                                  color: PdfColors.black,
                                  width: 2.0,
                                ),
                              ),
                            ),
                            child: pw.Directionality(
                              textDirection: pw.TextDirection.rtl,
                              child: pw.Align(
                                alignment: pw.Alignment.centerRight,
                                child: pw.Text(
                                  "فقط وقدره : .......................................................................",
                                  style: pw.TextStyle(
                                    font: ttfAr,
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              pw.SizedBox(height: 15),

              // 3. الفوتر (Footer)
              pw.Container(
                height: 100,
                child: pw.Directionality(
                  textDirection: pw.TextDirection.rtl,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text(
                        "أستلمت الأصناف والأعداد الموضحة بعاليه بحالة جيدة وخالية من عيوب الصناعة.",
                        style: pw.TextStyle(font: ttfAr, fontSize: 15),
                      ),
                      pw.Spacer(),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSignature("مسئول البيع", ttfAr),
                          _buildSignature("اسم المستلم", ttfAr),
                          _buildSignature("التوقيع", ttfAr),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ✅ تعديل: رفع الفوتر قليلاً عن حافة الصفحة (مسافة صغيرة بدلاً من 100)
              pw.SizedBox(height: 30),
            ],
          );
        },
      ),
    );

    // ==============================================================
    // 💾 منطق تسمية الملف
    // ==============================================================
    String fileName = "Delivery_Order";

    String manualNo = (order['manualNo'] ?? '').toString().trim();
    String supplyNo = (order['supplyOrderNumber'] ?? '').toString().trim();

    String sanitize(String input) {
      return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
    }

    if (manualNo.isNotEmpty || supplyNo.isNotEmpty) {
      List<String> parts = [];
      if (manualNo.isNotEmpty) parts.add(sanitize(manualNo));
      if (supplyNo.isNotEmpty) parts.add(sanitize(supplyNo));
      fileName += "_${parts.join('_')}";
    } else {
      fileName += "_$formattedDate";
    }

    fileName += ".pdf";

    final output = await getApplicationDocumentsDirectory();
    final file = File("${output.path}/$fileName");
    await file.writeAsBytes(await pdf.save());
    await OpenFile.open(file.path);
  }

  // ================= Helpers =================

  static pw.Widget _buildCellContent({
    required int flex,
    required pw.Widget child,
    bool borderRight = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
    double padding = 0,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        padding: padding > 0 ? pw.EdgeInsets.all(padding) : null,
        alignment: alignment,
        decoration: borderRight
            ? const pw.BoxDecoration(
                border: pw.Border(right: pw.BorderSide(width: 0.8)),
              )
            : null,
        child: child,
      ),
    );
  }

  static pw.Widget _buildHeaderCellTitle(
    String ar,
    String en,
    pw.Font arFont,
    pw.Font enFont,
  ) {
    return pw.Column(
      mainAxisSize: pw.MainAxisSize.min,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Text(
            ar,
            style: pw.TextStyle(
              font: arFont,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(en, style: pw.TextStyle(font: enFont, fontSize: 12)),
      ],
    );
  }

  static pw.Widget _buildHeaderContent(
    pw.MemoryImage logo,
    String address,
    String phone,
    String mobile,
    String website,
    String email,
    Map<String, dynamic> order,
    String formattedDate,
    String combinedSupplyOrders,
    pw.Font ttfAr,
    pw.Font ttfEn,
    pw.Font ttfEnBold,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          width: 150,
          padding: const pw.EdgeInsets.all(10),
          alignment: pw.Alignment.center,
          child: pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.Container(width: 1, color: PdfColors.black),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                flex: 5,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.only(
                    left: 15,
                    top: 5,
                    bottom: 5,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      _buildHeaderLine("Address :", address, ttfEnBold, ttfEn),
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(
                                text: "TeleFax :",
                                style: pw.TextStyle(
                                  color: PdfColors.red,
                                  font: ttfEnBold,
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.TextSpan(
                                text: " $phone",
                                style: pw.TextStyle(
                                  color: PdfColors.black,
                                  font: ttfEn,
                                  fontSize: 13,
                                ),
                              ),
                              pw.TextSpan(text: "   "),
                              pw.TextSpan(
                                text: "MOB :",
                                style: pw.TextStyle(
                                  color: PdfColors.red,
                                  font: ttfEnBold,
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.TextSpan(
                                text: " $mobile",
                                style: pw.TextStyle(
                                  color: PdfColors.black,
                                  font: ttfEn,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildHeaderLine(
                        "Website :",
                        website,
                        ttfEnBold,
                        ttfEn,
                        isLink: true,
                      ),
                      _buildHeaderLine(
                        "E-mail :",
                        email,
                        ttfEnBold,
                        ttfEn,
                        isLink: true,
                      ),
                    ],
                  ),
                ),
              ),
              pw.Container(height: 1, color: PdfColors.black),
              pw.Expanded(
                flex: 5,
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                    children: [
                      pw.Center(
                        child: pw.RichText(
                          textDirection: pw.TextDirection.rtl,
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(
                                text: "إذن تسليم خاص ",
                                style: pw.TextStyle(
                                  fontSize: 20,
                                  fontWeight: pw.FontWeight.bold,
                                  font: ttfAr,
                                  color: PdfColors.blue900,
                                ),
                              ),
                              if (order['manualNo'] != null &&
                                  order['manualNo'].toString().isNotEmpty)
                                pw.TextSpan(
                                  text: "(${order['manualNo']})",
                                  style: pw.TextStyle(
                                    fontSize: 20,
                                    fontWeight: pw.FontWeight.bold,
                                    font: ttfEnBold,
                                    color: PdfColors.blue900,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            _buildLabelValueRow(
                              "التاريخ",
                              formattedDate,
                              ttfAr,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Row(
                              children: [
                                pw.Text(
                                  "السادة : ",
                                  style: pw.TextStyle(
                                    font: ttfAr,
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  "..... ${order['clientName']} ......",
                                  style: pw.TextStyle(
                                    font: ttfAr,
                                    fontSize: 12,
                                  ),
                                ),
                                pw.SizedBox(width: 30),
                                pw.Text(
                                  "رقم أمر التوريد : ",
                                  style: pw.TextStyle(
                                    font: ttfAr,
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.Text(
                                  combinedSupplyOrders,
                                  style: pw.TextStyle(
                                    font: ttfEnBold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 4),
                            _buildLabelValueRow(
                              "العنوان",
                              "..... ${order['address']} .....",
                              ttfAr,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildHeaderLine(
    String label,
    String value,
    pw.Font labelFont,
    pw.Font valueFont, {
    bool isLink = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: label,
              style: pw.TextStyle(
                color: PdfColors.red,
                font: labelFont,
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.TextSpan(
              text: "   $value",
              style: pw.TextStyle(
                color: isLink ? PdfColors.blue : PdfColors.black,
                font: valueFont,
                fontSize: 13,
                decoration: isLink ? pw.TextDecoration.underline : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildLabelValueRow(
    String label,
    String value,
    pw.Font font,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            "$label : ",
            style: pw.TextStyle(
              font: font,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 12)),
        ],
      ),
    );
  }

  static pw.Widget _buildSignature(String title, pw.Font font) {
    return pw.Column(
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            font: font,
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text("......................................"),
      ],
    );
  }
}
