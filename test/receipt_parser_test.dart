import 'package:flutter_test/flutter_test.dart';
import 'package:expense_ocr/models/expense_category.dart';
import 'package:expense_ocr/services/receipt_layout.dart';
import 'package:expense_ocr/services/receipt_parser.dart';
import 'package:expense_ocr/services/text_utils.dart';

void main() {
  const parser = ReceiptParser();
  final now = DateTime(2026, 10, 8, 12);

  group('text utils', () {
    test('fold strips Vietnamese diacritics', () {
      expect(fold('TỔNG CỘNG Thanh Toán'), 'tong cong thanh toan');
      expect(fold('Đường Nguyễn Văn Linh'), 'duong nguyen van linh');
    });

    test('repairDigits fixes O read instead of 0', () {
      expect(repairDigits('15O.0OO đ'), '150.000 đ');
      expect(repairDigits('Tổng: 2OO,OOO'), 'Tổng: 200,000');
      expect(repairDigits('COCA COLA 1 Oreo'), 'COCA COLA 1 Oreo');
    });
  });

  group('amount tokens', () {
    test('Vietnamese thousands separators', () {
      expect(ReceiptParser.parseAmountToken('150.000'), 150000);
      expect(ReceiptParser.parseAmountToken('150,000'), 150000);
      expect(ReceiptParser.parseAmountToken('1.250.000'), 1250000);
      expect(ReceiptParser.parseAmountToken('45000'), 45000);
    });

    test('decimal part', () {
      expect(ReceiptParser.parseAmountToken('150,000.00'), 150000);
      expect(ReceiptParser.parseAmountToken('12.50'), 12.5);
      expect(ReceiptParser.parseAmountToken('1.250.000,50'), 1250000.5);
    });

    test('rejects malformed tokens', () {
      expect(ReceiptParser.parseAmountToken('1.2345.6'), isNull);
    });

    test('extractAmounts ignores dates, times, phones and percentages', () {
      final found = ReceiptParser.extractAmounts(
        'Ngày 05/10/2026 14:32  ĐT 0905123456  VAT 10%  150.000 đ',
      );
      expect(found.map((a) => a.value), [150000]);
      expect(found.single.currency, isTrue);
    });

    test('currency suffixes and k shorthand', () {
      expect(ReceiptParser.extractAmounts('150,000 VND').single.value, 150000);
      expect(ReceiptParser.extractAmounts('150.000₫').single.currency, isTrue);
      expect(ReceiptParser.extractAmounts('Trà sữa 45k').single.value, 45000);
      expect(ReceiptParser.extractAmounts('150 000 đ').single.value, 150000);
    });
  });

  group('full receipts', () {
    test('supermarket receipt with cash and change lines', () {
      final r = parser.parse([
        'CO.OPMART HẢI CHÂU',
        'Địa chỉ: 478 Điện Biên Phủ, Đà Nẵng',
        'ĐT: 0236 3888 999',
        'HÓA ĐƠN BÁN HÀNG',
        'Ngày: 05/10/2026 18:42',
        'Sữa tươi Vinamilk 1L  2  32.000  64.000',
        'Bánh mì sandwich  1  25.000  25.000',
        'Táo Envy  1  61.000  61.000',
        'Tổng cộng  150.000',
        'Tiền khách đưa  200.000',
        'Tiền thừa  50.000',
        'Cảm ơn quý khách!',
      ], now: now);

      expect(r.total, 150000);
      expect(r.totalConfidence, Confidence.high);
      expect(r.merchant, 'Co.opmart');
      expect(r.date, DateTime(2026, 10, 5, 18, 42));
      expect(r.dateConfidence, Confidence.high);
      expect(r.category, ExpenseCategory.food);
      expect(r.amountCandidates.first.value, 150000);
    });

    test('total label and value on separate rows', () {
      final r = parser.parse([
        'NHÀ SÁCH THÀNH NGHĨA',
        'Giáo trình Lập trình Flutter  120.000',
        'Bút bi Thiên Long  2  5.000  10.000',
        'TỔNG THANH TOÁN',
        '130.000 VND',
        '12/09/2026',
      ], now: now);

      expect(r.total, 130000);
      expect(r.merchant, 'NHÀ SÁCH THÀNH NGHĨA');
      expect(r.category, ExpenseCategory.study);
      expect(r.date, DateTime(2026, 9, 12));
    });

    test('VAT-inclusive total line is not penalised as tax', () {
      final r = parser.parse([
        'HIGHLANDS COFFEE',
        'Phin sữa đá  1  39.000',
        'Thuế VAT 8%  3.120',
        'Tổng tiền (đã gồm VAT)  42.120',
      ], now: now);
      expect(r.total, 42120);
      expect(r.merchant, 'Highlands Coffee');
    });

    test('falls back to largest amount when no total keyword', () {
      final r = parser.parse([
        'QUÁN BÚN BÒ CÔ BA',
        'Bún bò đặc biệt  55.000',
        'Trà đá  5.000',
        '60.000',
      ], now: now);
      expect(r.total, 60000);
      expect(r.totalConfidence, Confidence.low);
      expect(r.merchant, 'QUÁN BÚN BÒ CÔ BA');
    });

    test('English receipt with decimals and ISO date', () {
      final r = parser.parse([
        'CGV VINCOM DA NANG',
        'Date: 2026-10-01 20:15',
        'Ticket x2  180,000',
        'Popcorn combo  89,000',
        'Subtotal  269,000',
        'Grand Total  269,000.00 VND',
        'Cash  300,000',
        'Change  31,000',
      ], now: now);
      expect(r.total, 269000);
      expect(r.merchant, 'CGV');
      expect(r.category, ExpenseCategory.entertainment);
      expect(r.date, DateTime(2026, 10, 1, 20, 15));
    });

    test('ignores future dates and invalid calendar days', () {
      final r = parser.parse([
        'SHOP A',
        'Bảo hành đến 31/12/2027',
        '31/02/2026',
        'Ngày 03/10/2026',
        'Total 99.000',
      ], now: now);
      expect(r.date, DateTime(2026, 10, 3));
    });

    test('Vietnamese long-form date', () {
      final r = parser.parse([
        'Ngày 07 tháng 10 năm 2026',
        'Tổng cộng 10.000',
      ], now: now);
      expect(r.date, DateTime(2026, 10, 7));
    });

    test('empty input', () {
      final r = parser.parse(const []);
      expect(r.total, isNull);
      expect(r.merchant, isNull);
    });
  });

  group('row merging', () {
    test('merges label and value printed in separate ML Kit blocks', () {
      final rows = mergeIntoRows(const [
        OcrLine('150.000', left: 400, top: 502, right: 480, bottom: 530),
        OcrLine('CIRCLE K', left: 120, top: 10, right: 300, bottom: 50),
        OcrLine('Tổng cộng', left: 20, top: 500, right: 160, bottom: 528),
        OcrLine('Mì ly', left: 20, top: 440, right: 90, bottom: 468),
        OcrLine('15.000', left: 400, top: 438, right: 470, bottom: 466),
      ]);
      expect(rows, ['CIRCLE K', 'Mì ly  15.000', 'Tổng cộng  150.000']);
      expect(parser.parse(rows, now: now).total, 150000);
    });
  });
}
