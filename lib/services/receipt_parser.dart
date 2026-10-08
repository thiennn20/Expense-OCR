import '../models/expense_category.dart';
import 'text_utils.dart';

enum Confidence { high, medium, low }

/// One monetary value found on the receipt, with the heuristic score that
/// decided how likely it is to be the grand total.
class AmountCandidate {
  const AmountCandidate({
    required this.value,
    required this.score,
    required this.lineIndex,
    required this.line,
    required this.reason,
  });

  final double value;
  final int score;
  final int lineIndex;
  final String line;
  final String reason;

  @override
  String toString() => 'AmountCandidate($value, score: $score, "$line")';
}

class ParsedReceipt {
  const ParsedReceipt({
    required this.lines,
    this.merchant,
    this.merchantConfidence = Confidence.low,
    this.total,
    this.totalConfidence = Confidence.low,
    this.date,
    this.dateConfidence = Confidence.low,
    this.category = ExpenseCategory.food,
    this.categoryMatched = false,
    this.amountCandidates = const [],
  });

  final List<String> lines;
  final String? merchant;
  final Confidence merchantConfidence;
  final double? total;
  final Confidence totalConfidence;
  final DateTime? date;
  final Confidence dateConfidence;
  final ExpenseCategory category;
  final bool categoryMatched;
  final List<AmountCandidate> amountCandidates;
}

class KnownBrand {
  const KnownBrand(this.name, this.patterns, this.category);
  final String name;
  final List<String> patterns;
  final ExpenseCategory category;
}

/// Heuristic, regex-based receipt parser tuned for Vietnamese receipts
/// (VND amounts such as `150,000 VND`, `150.000 đ`, dates in `DD/MM/YYYY`)
/// with English fallbacks.
///
/// Pure Dart: it only sees text rows, never ML Kit objects, so every rule is
/// covered by plain unit tests.
class ReceiptParser {
  const ReceiptParser();

  // ---------------------------------------------------------------- amounts

  static final _dateLike = RegExp(
    r'(?<!\d)\d{1,4}\s*[/\-.]\s*\d{1,2}\s*[/\-.]\s*\d{2,4}(?!\d)',
  );
  static final _timeLike = RegExp(r'(?<!\d)\d{1,2}:\d{2}(?::\d{2})?(?!\d)');
  static final _percent = RegExp(r'\d+(?:[.,]\d+)?\s*%');
  static final _spacedThousands = RegExp(
    r'(?<!\d)(\d{1,3})((?: \d{3})+)(?=\s*(?:vnd|vnđ|đ|₫|d\b))',
  );
  static final _money = RegExp(
    r'(?<![\d.,])(\d+(?:[.,]\d+)*)(?!\d)\s*(k(?![a-z])|vnđ|vnd|đồng|dong(?![a-z])|đ|₫|d(?![a-z]))?',
  );

  static final _ignoreLine = _words([
    'mst',
    'ma so thue',
    'tax code',
    'tax id',
    'dien thoai',
    'dt',
    'sdt',
    'tel',
    'hotline',
    'fax',
    'so hd',
    'so hoa don',
    'ma hd',
    'ma hoa don',
    'invoice no',
    'receipt no',
    'stk',
    'so tk',
    'ma vach',
    'barcode',
    'www',
    'http',
    'ma don',
    'order no',
    'ky hieu',
    'serial',
  ]);
  static final _subtotal = _words([
    'tam tinh',
    'sub total',
    'subtotal',
    'thanh tien',
    'tien hang',
    'cong tien hang',
  ]);
  static final _strongTotal = _words([
    'tong cong',
    'tong tien',
    'tong thanh toan',
    'tong so tien',
    'tong tien thanh toan',
    'can thanh toan',
    'khach can tra',
    'khach phai tra',
    'phai thanh toan',
    'thanh toan',
    'grand total',
    'total amount',
    'amount due',
    'total due',
    'net total',
    'total',
    'tong hoa don',
  ]);
  static final _weakTotal = _words(['tong', 'sum']);
  static final _negative = _words([
    'tien khach dua',
    'khach dua',
    'tien mat',
    'cash',
    'tien thua',
    'tien tra lai',
    'tra lai',
    'thoi lai',
    'change',
    'giam gia',
    'discount',
    'chiet khau',
    'khuyen mai',
    'vat',
    'thue',
    'tax',
    'diem',
    'points',
    'so luong',
    'sl',
    'don gia',
    'unit price',
    'qty',
    'tich luy',
    'voucher',
  ]);
  static final _includesTax = RegExp(
    r'(da )?(bao )?gom\s*(vat|thue)|incl\.?\s*(vat|tax)',
  );

  static RegExp _words(List<String> phrases) {
    final escaped = phrases.map(RegExp.escape).join('|');
    return RegExp('(?<![a-z0-9])(?:$escaped)(?![a-z0-9])');
  }

  /// Parses a single numeric token using Vietnamese conventions: `.` and `,`
  /// are both accepted as thousands separators (`150.000`, `150,000`,
  /// `1.250.000`); a final group of 1–2 digits is a decimal part
  /// (`150,000.00`, `12.50`).
  static double? parseAmountToken(String token) {
    final groups = token.split(RegExp(r'[.,]'));
    if (groups.any((g) => g.isEmpty)) return null;
    if (groups.length == 1) return double.tryParse(token);

    bool thousands(List<String> g) =>
        g.first.length <= 3 && g.skip(1).every((x) => x.length == 3);

    if (thousands(groups)) return double.parse(groups.join());

    final tail = groups.last;
    final head = groups.sublist(0, groups.length - 1);
    if (tail.length <= 2 && (head.length == 1 || thousands(head))) {
      return double.parse('${head.join()}.$tail');
    }
    return null;
  }

  /// Every plausible monetary value on [line], before scoring.
  static List<({double value, bool currency})> extractAmounts(String line) {
    var text = repairDigits(line).toLowerCase();
    text = text
        .replaceAll(_dateLike, ' ')
        .replaceAll(_timeLike, ' ')
        .replaceAll(_percent, ' ')
        .replaceAllMapped(
          _spacedThousands,
          (m) => '${m[1]}${m[2]!.replaceAll(' ', '')}',
        );

    final results = <({double value, bool currency})>[];
    for (final m in _money.allMatches(text)) {
      final token = m[1]!;
      final suffix = m[2];
      final hasSeparator = token.contains(RegExp(r'[.,]'));
      // Phone numbers, barcodes and invoice ids: long digit runs / leading 0.
      if (!hasSeparator && token.length >= 8) continue;
      if (!hasSeparator && token.length > 1 && token.startsWith('0')) continue;

      var value = parseAmountToken(token);
      if (value == null || value <= 0) continue;
      if (suffix == 'k') value *= 1000;
      results.add((value: value, currency: suffix != null));
    }
    return results;
  }

  List<AmountCandidate> scoreAmounts(List<String> lines) {
    final candidates = <AmountCandidate>[];
    var carryBonus = 0;
    var carryReason = '';

    for (var i = 0; i < lines.length; i++) {
      final folded = fold(lines[i]);
      if (_ignoreLine.hasMatch(folded)) {
        carryBonus = 0;
        continue;
      }

      var lineScore = 0;
      var reason = 'Amount';
      final isSubtotal = _subtotal.hasMatch(folded);
      if (isSubtotal) {
        lineScore += 2;
        reason = 'Subtotal line';
      } else if (_strongTotal.hasMatch(folded)) {
        lineScore += 8;
        reason = 'Total line';
      } else if (_weakTotal.hasMatch(folded) && !folded.contains('cong ty')) {
        lineScore += 4;
        reason = 'Total line';
      }
      final negativeText = folded.replaceAll(_includesTax, ' ');
      if (_negative.hasMatch(negativeText)) {
        lineScore -= 7;
        reason = 'Cash / discount / tax line';
      }
      if (i >= lines.length / 2) lineScore += 1;

      final amounts = extractAmounts(lines[i]);
      if (amounts.isEmpty) {
        // Label printed on its own row, value on the next one.
        if (lineScore >= 4) {
          carryBonus = lineScore - 1;
          carryReason = reason;
        } else {
          carryBonus = 0;
        }
        continue;
      }

      for (final a in amounts) {
        var score = lineScore;
        var why = reason;
        if (carryBonus > 0 && lineScore <= 1) {
          score += carryBonus;
          why = carryReason;
        }
        if (a.currency) score += 2;
        final isWhole = a.value == a.value.roundToDouble();
        if (a.value < 1000 && !a.currency && isWhole) score -= 4;
        candidates.add(
          AmountCandidate(
            value: a.value,
            score: score,
            lineIndex: i,
            line: lines[i],
            reason: why,
          ),
        );
      }
      carryBonus = 0;
    }
    return candidates;
  }

  ({double? total, Confidence confidence}) pickTotal(
    List<AmountCandidate> candidates,
  ) {
    if (candidates.isEmpty) return (total: null, confidence: Confidence.low);

    final best = candidates.reduce((a, b) {
      if (a.score != b.score) return a.score > b.score ? a : b;
      return a.value >= b.value ? a : b;
    });
    if (best.score >= 6) {
      return (total: best.value, confidence: Confidence.high);
    }
    if (best.score >= 4) {
      return (total: best.value, confidence: Confidence.medium);
    }

    // No reliable "total" label: the grand total is normally the largest
    // non-cash amount on the receipt.
    final plausible = candidates.where((c) => c.score >= 0).toList();
    if (plausible.isEmpty) {
      return (total: best.value, confidence: Confidence.low);
    }
    final largest = plausible.reduce((a, b) => a.value >= b.value ? a : b);
    return (total: largest.value, confidence: Confidence.low);
  }

  // ------------------------------------------------------------------ dates

  static final _dmy = RegExp(
    r'(?<!\d)(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4}|\d{2})(?!\d)',
  );
  static final _ymd = RegExp(
    r'(?<!\d)(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)',
  );
  static final _vnWords = RegExp(
    r'ngay\s*(\d{1,2})\s*thang\s*(\d{1,2})\s*nam\s*(\d{4})',
  );
  static final _time = RegExp(r'(?<!\d)([01]?\d|2[0-3])[:h]([0-5]\d)(?!\d)');
  static final _dateKeyword = _words([
    'ngay',
    'date',
    'thoi gian',
    'time',
    'gio',
    'ngay ban',
  ]);

  static DateTime? _validDate(int y, int m, int d) {
    if (y < 100) y += 2000;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final date = DateTime(y, m, d);
    if (date.month != m || date.day != d) return null;
    return date;
  }

  ({DateTime? date, Confidence confidence}) findDate(
    List<String> lines, {
    required DateTime now,
  }) {
    DateTime? best;
    var bestScore = -1 << 30;
    final latest = now.add(const Duration(days: 1));
    final earliest = DateTime(now.year - 5, now.month, now.day);

    for (final raw in lines) {
      final line = repairDigits(raw);
      final folded = fold(line);
      final found = <DateTime>[];

      for (final m in _ymd.allMatches(line)) {
        final d = _validDate(
          int.parse(m[1]!),
          int.parse(m[2]!),
          int.parse(m[3]!),
        );
        if (d != null) found.add(d);
      }
      for (final m in _dmy.allMatches(line)) {
        final a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
        // Day-first is the Vietnamese default; month-first only as a rescue
        // for receipts printed by US-configured POS systems.
        final d = _validDate(y, b, a) ?? _validDate(y, a, b);
        if (d != null) found.add(d);
      }
      for (final m in _vnWords.allMatches(folded)) {
        final d = _validDate(
          int.parse(m[3]!),
          int.parse(m[2]!),
          int.parse(m[1]!),
        );
        if (d != null) found.add(d);
      }

      for (var date in found) {
        if (date.isAfter(latest)) continue;
        var score = 0;
        if (_dateKeyword.hasMatch(folded)) score += 2;
        if (date.isBefore(earliest)) score -= 3;
        final t = _time.firstMatch(line);
        if (t != null) {
          date = DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(t[1]!),
            int.parse(t[2]!),
          );
          score += 1;
        }
        if (score > bestScore) {
          bestScore = score;
          best = date;
        }
      }
    }

    if (best == null) return (date: null, confidence: Confidence.low);
    return (
      date: best,
      confidence: bestScore >= 2 ? Confidence.high : Confidence.medium,
    );
  }

  // --------------------------------------------------------------- merchant

  static const _brands = <KnownBrand>[
    KnownBrand('Co.opmart', [
      'coopmart',
      'co.opmart',
      'co.op mart',
      'co op mart',
    ], ExpenseCategory.food),
    KnownBrand('Co.opXtra', ['coopxtra', 'co.opxtra'], ExpenseCategory.food),
    KnownBrand('WinMart', [
      'winmart',
      'winmart+',
      'vinmart',
    ], ExpenseCategory.food),
    KnownBrand('Bách Hóa Xanh', [
      'bach hoa xanh',
      'bachhoaxanh',
    ], ExpenseCategory.food),
    KnownBrand('Circle K', ['circle k'], ExpenseCategory.food),
    KnownBrand('GS25', ['gs25'], ExpenseCategory.food),
    KnownBrand('7-Eleven', [
      '7-eleven',
      '7 eleven',
      '7eleven',
    ], ExpenseCategory.food),
    KnownBrand('FamilyMart', [
      'familymart',
      'family mart',
    ], ExpenseCategory.food),
    KnownBrand('Ministop', ['ministop'], ExpenseCategory.food),
    KnownBrand('Lotte Mart', ['lotte mart', 'lottemart'], ExpenseCategory.food),
    KnownBrand('GO! / Big C', [
      'big c',
      'bigc',
      'go mart',
    ], ExpenseCategory.food),
    KnownBrand('AEON', ['aeon'], ExpenseCategory.food),
    KnownBrand('MM Mega Market', [
      'mega market',
      'mm mega',
    ], ExpenseCategory.food),
    KnownBrand('Highlands Coffee', [
      'highlands coffee',
      'highlands',
    ], ExpenseCategory.food),
    KnownBrand('Phúc Long', ['phuc long'], ExpenseCategory.food),
    KnownBrand('The Coffee House', ['the coffee house'], ExpenseCategory.food),
    KnownBrand('Starbucks', ['starbucks'], ExpenseCategory.food),
    KnownBrand('Katinat', ['katinat'], ExpenseCategory.food),
    KnownBrand('Cộng Cà Phê', ['cong ca phe'], ExpenseCategory.food),
    KnownBrand('KFC', ['kfc'], ExpenseCategory.food),
    KnownBrand('Lotteria', ['lotteria'], ExpenseCategory.food),
    KnownBrand('Jollibee', ['jollibee'], ExpenseCategory.food),
    KnownBrand('Pizza Hut', ['pizza hut'], ExpenseCategory.food),
    KnownBrand('Fahasa', ['fahasa'], ExpenseCategory.study),
    KnownBrand('Nhà sách Phương Nam', [
      'nha sach phuong nam',
      'phuong nam book',
    ], ExpenseCategory.study),
    KnownBrand('Thế Giới Di Động', [
      'the gioi di dong',
      'thegioididong',
    ], ExpenseCategory.gear),
    KnownBrand('Điện Máy Xanh', [
      'dien may xanh',
      'dienmayxanh',
    ], ExpenseCategory.gear),
    KnownBrand('CellphoneS', ['cellphones'], ExpenseCategory.gear),
    KnownBrand('FPT Shop', ['fpt shop', 'fptshop'], ExpenseCategory.gear),
    KnownBrand('GearVN', ['gearvn'], ExpenseCategory.gear),
    KnownBrand('Phong Vũ', ['phong vu'], ExpenseCategory.gear),
    KnownBrand('CGV', ['cgv'], ExpenseCategory.entertainment),
    KnownBrand('Lotte Cinema', ['lotte cinema'], ExpenseCategory.entertainment),
    KnownBrand('Galaxy Cinema', [
      'galaxy cinema',
      'galaxy cine',
    ], ExpenseCategory.entertainment),
    KnownBrand('BHD Star', ['bhd star', 'bhd'], ExpenseCategory.entertainment),
    KnownBrand('Grab', ['grab', 'grabfood', 'grabcar'], ExpenseCategory.travel),
    KnownBrand('Petrolimex', ['petrolimex'], ExpenseCategory.travel),
    KnownBrand('Vietjet Air', ['vietjet'], ExpenseCategory.travel),
    KnownBrand('Vietnam Airlines', [
      'vietnam airlines',
    ], ExpenseCategory.travel),
  ];

  static final _brandMatchers = [
    for (final b in _brands) (brand: b, re: _words(b.patterns)),
  ];

  static final _headerNoise = RegExp(
    r'dia chi|d/c|dc:|address|dien thoai|\bdt\b|\btel\b|hotline|phone|\bmst\b'
    r'|ma so thue|\btax\b|website|www|http|\.com|\.vn|email|@|hoa don|phieu'
    r'|receipt|invoice|\bbill\b|\bso:|\bngay\b|\bdate\b|thu ngan|cashier'
    r'|nhan vien|\bquay\b|\bban so\b|xin chao|welcome|chi nhanh|branch'
    r'|lien he|\bgio\b|\btime\b|ma don|order|cam on|thank',
  );
  static final _businessWords = _words([
    'cong ty',
    'cty',
    'tnhh',
    'co phan',
    'store',
    'mart',
    'shop',
    'cafe',
    'coffee',
    'ca phe',
    'restaurant',
    'nha hang',
    'quan',
    'sieu thi',
    'cua hang',
    'tap hoa',
    'nha sach',
    'bakery',
    'tiem',
    'market',
  ]);

  KnownBrand? _findBrand(List<String> lines) {
    for (final line in lines) {
      final folded = fold(line);
      for (final m in _brandMatchers) {
        if (m.re.hasMatch(folded)) return m.brand;
      }
    }
    return null;
  }

  static String _cleanName(String s) => s
      .replaceAll(RegExp(r'^[\s*#=\-_.:|~]+|[\s*#=\-_.:|~]+$'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  ({String? merchant, Confidence confidence}) findMerchant(
    List<String> lines, {
    KnownBrand? brand,
  }) {
    if (brand != null) {
      return (merchant: brand.name, confidence: Confidence.high);
    }

    String? best;
    var bestScore = double.negativeInfinity;
    final header = lines.take(8).toList();
    for (var i = 0; i < header.length; i++) {
      final line = _cleanName(header[i]);
      final folded = fold(line);
      if (letterCount(line) < 3 || digitRatio(line) > 0.25) continue;
      if (_headerNoise.hasMatch(folded)) continue;

      var score = 10 - i * 1.2;
      final letters = line.replaceAll(RegExp(r'[^A-Za-zÀ-ỹĐđ]'), '');
      final upper = letters.split('').where((c) => c == c.toUpperCase()).length;
      if (letters.isNotEmpty && upper / letters.length >= 0.6) score += 2;
      if (_businessWords.hasMatch(folded)) score += 3;
      if (line.length > 40) score -= 2;
      if (score > bestScore) {
        bestScore = score;
        best = line;
      }
    }
    if (best == null) return (merchant: null, confidence: Confidence.low);
    if (best.length > 48) best = best.substring(0, 48).trim();
    return (
      merchant: best,
      confidence: bestScore >= 10 ? Confidence.medium : Confidence.low,
    );
  }

  // --------------------------------------------------------------- category

  static final Map<ExpenseCategory, RegExp> _categoryKeywords = {
    ExpenseCategory.food: _words([
      'sieu thi',
      'mart',
      'bach hoa',
      'tap hoa',
      'coffee',
      'cafe',
      'ca phe',
      'tra sua',
      'milk tea',
      'tea',
      'nha hang',
      'restaurant',
      'quan an',
      'com tam',
      'com ga',
      'com chien',
      'pho',
      'bun',
      'banh',
      'banh mi',
      'bakery',
      'food',
      'do an',
      'thuc pham',
      'rau',
      'thit',
      'sua',
      'pizza',
      'ga ran',
      'chicken',
      'burger',
      'mi tom',
      'nuoc ngot',
      'snack',
      'trai cay',
      'fruit',
      'drink',
      'tra dao',
    ]),
    ExpenseCategory.study: _words([
      'nha sach',
      'sach',
      'book',
      'books',
      'van phong pham',
      'but',
      'but bi',
      'vo',
      'tap vo',
      'photo',
      'photocopy',
      'in an',
      'hoc phi',
      'tuition',
      'khoa hoc',
      'course',
      'giao trinh',
      'stationery',
      'pen',
      'notebook',
      'thuoc ke',
      'may tinh casio',
      'casio',
    ]),
    ExpenseCategory.travel: _words([
      'taxi',
      'xe om',
      'bus',
      'xe buyt',
      've xe',
      've tau',
      'train',
      'airlines',
      'hang khong',
      'flight',
      'xang',
      'dau diesel',
      'ron 95',
      'gui xe',
      'parking',
      'hotel',
      'khach san',
      'homestay',
      'booking',
      'du lich',
      'tour',
      'toll',
      'tram thu phi',
      'cau duong',
      'nha xe',
      'limousine',
    ]),
    ExpenseCategory.gear: _words([
      'dien may',
      'laptop',
      'chuot',
      'mouse',
      'ban phim',
      'keyboard',
      'tai nghe',
      'headphone',
      'earphone',
      'sac',
      'charger',
      'cap sac',
      'cable',
      'usb',
      'ssd',
      'hdd',
      'man hinh',
      'monitor',
      'op lung',
      'loa',
      'speaker',
      'webcam',
      'pin du phong',
      'power bank',
      'router',
    ]),
    ExpenseCategory.entertainment: _words([
      'cinema',
      'rap phim',
      'karaoke',
      'game',
      'bowling',
      'billiard',
      'bida',
      'netflix',
      'spotify',
      'concert',
      've xem',
      'movie',
      'phim',
      'bap rang',
      'popcorn',
      'khu vui choi',
      'theme park',
      'escape room',
      'ticket',
    ]),
  };

  ({ExpenseCategory category, bool matched}) suggestCategory(
    List<String> lines, {
    KnownBrand? brand,
  }) {
    final folded = lines.map(fold).join('\n');
    final scores = {for (final c in ExpenseCategory.values) c: 0};
    if (brand != null) scores[brand.category] = scores[brand.category]! + 5;
    _categoryKeywords.forEach((category, re) {
      scores[category] = scores[category]! + re.allMatches(folded).length;
    });
    final best = scores.entries.reduce((a, b) => b.value > a.value ? b : a);
    if (best.value == 0) {
      return (category: ExpenseCategory.food, matched: false);
    }
    return (category: best.key, matched: true);
  }

  // ------------------------------------------------------------------ entry

  ParsedReceipt parse(List<String> rawLines, {DateTime? now}) {
    final lines = rawLines
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return ParsedReceipt(lines: lines);

    final brand = _findBrand(lines);
    final candidates = scoreAmounts(lines);
    final total = pickTotal(candidates);
    final date = findDate(lines, now: now ?? DateTime.now());
    final merchant = findMerchant(lines, brand: brand);
    final category = suggestCategory(lines, brand: brand);

    // Distinct values, best first, for the "tap to use" chips on review.
    final seen = <double>{};
    final ranked = [...candidates]
      ..sort(
        (a, b) => a.score != b.score
            ? b.score.compareTo(a.score)
            : b.value.compareTo(a.value),
      );
    final distinct = [
      for (final c in ranked)
        if (c.score > -3 && seen.add(c.value)) c,
    ].take(6).toList();

    return ParsedReceipt(
      lines: lines,
      merchant: merchant.merchant,
      merchantConfidence: merchant.confidence,
      total: total.total,
      totalConfidence: total.confidence,
      date: date.date,
      dateConfidence: date.confidence,
      category: category.category,
      categoryMatched: category.matched,
      amountCandidates: distinct,
    );
  }
}
