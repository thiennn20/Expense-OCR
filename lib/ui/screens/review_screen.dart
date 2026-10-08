import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/formatters.dart';
import '../../models/expense.dart';
import '../../models/expense_category.dart';
import '../../services/receipt_parser.dart';
import '../widgets/category_picker.dart';

/// Lets the user check and correct OCR results before saving, and doubles as
/// the edit screen for saved expenses.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.initial,
    this.parsed,
    this.ocrTime,
  });

  ReviewScreen.manual({super.key})
    : initial = Expense(
        merchant: '',
        amount: 0,
        category: ExpenseCategory.food,
        date: DateTime.now(),
        createdAt: DateTime.now(),
      ),
      parsed = null,
      ocrTime = null;

  final Expense initial;
  final ParsedReceipt? parsed;
  final Duration? ocrTime;

  bool get isNew => initial.id == null;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _merchant = TextEditingController(text: widget.initial.merchant);
  late final _amount = TextEditingController(
    text: widget.initial.amount > 0
        ? groupThousands(widget.initial.amount)
        : '',
  );
  late final _note = TextEditingController(text: widget.initial.note);
  late DateTime _date = widget.initial.date;
  late ExpenseCategory _category = widget.initial.category;
  bool _saving = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _isUnsavedScan => widget.isNew && widget.initial.hasReceipt;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final scope = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final expense = widget.initial.copyWith(
      merchant: _merchant.text.trim(),
      amount: parseTypedAmount(_amount.text),
      category: _category,
      date: _date,
      note: _note.text.trim(),
    );
    try {
      if (widget.isNew) {
        await scope.store.add(expense);
      } else {
        await scope.store.update(expense);
      }
      _finished = true;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${widget.isNew ? 'Saved' : 'Updated'} ${formatVnd(expense.amount)} · ${expense.merchant}',
          ),
        ),
      );
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      title: 'Delete this expense?',
      message: 'The receipt photo will also be removed.',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;
    final scope = AppScope.read(context);
    final navigator = Navigator.of(context);
    await scope.store.remove(widget.initial);
    await scope.store.purgeImages(widget.initial);
    _finished = true;
    navigator.pop(true);
  }

  Future<void> _discardScan() async {
    final scope = AppScope.read(context);
    final navigator = Navigator.of(context);
    final confirmed = await _confirm(
      title: 'Discard this scan?',
      message: 'The captured receipt will not be saved.',
      action: 'Discard',
    );
    if (!confirmed) return;
    _finished = true;
    await scope.images.delete(
      widget.initial.imageFile,
      widget.initial.thumbFile,
    );
    navigator.pop(false);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String? _hint(Confidence? c) => switch (c) {
    null => null,
    Confidence.high => 'Auto-detected',
    Confidence.medium => 'Auto-detected — please verify',
    Confidence.low => 'Low confidence — please check',
  };

  TextStyle? _hintStyle(Confidence? c) => c == Confidence.low
      ? TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w600)
      : null;

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsed;
    final theme = Theme.of(context);
    final scope = AppScope.read(context);
    final typed = parseTypedAmount(_amount.text);

    return PopScope(
      canPop: !_isUnsavedScan || _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _discardScan();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.isNew
                ? (widget.initial.hasReceipt ? 'Review receipt' : 'New expense')
                : 'Edit expense',
          ),
          actions: [
            if (!widget.isNew)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _delete,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (widget.initial.imageFile != null)
                _ReceiptPreview(
                  file: scope.images.resolve(widget.initial.imageFile!),
                  ocrTime: widget.ocrTime,
                ),
              if (parsed != null && parsed.lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    color: theme.colorScheme.errorContainer,
                    child: const ListTile(
                      leading: Icon(Icons.text_fields_rounded),
                      title: Text('No text detected'),
                      subtitle: Text(
                        'Try again with better lighting, or fill the fields manually.',
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _merchant,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Merchant',
                  prefixIcon: const Icon(Icons.storefront_outlined),
                  helperText: _hint(parsed?.merchantConfidence),
                  helperStyle: _hintStyle(parsed?.merchantConfidence),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter the merchant name'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  labelText: 'Total amount',
                  prefixIcon: const Icon(Icons.payments_outlined),
                  suffixText: '₫',
                  helperText: _hint(parsed?.totalConfidence),
                  helperStyle: _hintStyle(parsed?.totalConfidence),
                ),
                validator: (v) => (parseTypedAmount(v ?? '') ?? 0) <= 0
                    ? 'Enter an amount greater than 0'
                    : null,
              ),
              if (parsed != null && parsed.amountCandidates.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Detected amounts — tap to use',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final c in parsed.amountCandidates)
                      ChoiceChip(
                        label: Text(formatVnd(c.value)),
                        tooltip: '${c.reason}: "${c.line}"',
                        selected: typed == c.value.roundToDouble(),
                        onSelected: (_) =>
                            _amount.text = groupThousands(c.value),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Date',
                    prefixIcon: const Icon(Icons.event_outlined),
                    helperText: parsed == null
                        ? null
                        : parsed.date == null
                        ? 'No date found — defaulted to today'
                        : _hint(parsed.dateConfidence),
                    helperStyle: parsed?.date == null
                        ? _hintStyle(Confidence.low)
                        : _hintStyle(parsed?.dateConfidence),
                  ),
                  child: Text(
                    weekdayDayMonth.format(_date),
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Category', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              CategoryPicker(
                selected: _category,
                onChanged: (c) => setState(() => _category = c),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              if (widget.initial.rawText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: const Icon(Icons.document_scanner_outlined),
                    title: const Text('Recognised text'),
                    subtitle: Text(
                      '${widget.initial.rawText.split('\n').length} lines · on-device ML Kit',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      SelectableText(
                        widget.initial.rawText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(widget.isNew ? 'Save expense' : 'Save changes'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({required this.file, this.ocrTime});

  final File file;
  final Duration? ocrTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 190,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Material(
              color: scheme.surfaceContainerHighest,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _FullImage(file: file)),
                ),
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  cacheWidth: 900,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
            if (ocrTime != null)
              Positioned(
                left: 10,
                top: 10,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text('On-device OCR · ${ocrTime!.inMilliseconds} ms'),
                ),
              ),
            const Positioned(
              right: 10,
              bottom: 10,
              child: Icon(Icons.zoom_out_map_rounded, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullImage extends StatelessWidget {
  const _FullImage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Receipt'),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(child: Image.file(file)),
      ),
    );
  }
}
