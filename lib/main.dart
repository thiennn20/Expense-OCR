import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/theme.dart';
import 'data/expense_repository.dart';
import 'data/receipt_image_store.dart';
import 'services/ocr_service.dart';
import 'state/expense_store.dart';
import 'ui/screens/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final images = await ReceiptImageStore.open();
  final repository = await SqfliteExpenseRepository.open();
  final store = ExpenseStore(repository, images: images)..load();

  runApp(ExpenseApp(store: store, images: images, ocr: OcrService()));
}

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({
    super.key,
    required this.store,
    required this.images,
    required this.ocr,
    this.home,
  });

  final ExpenseStore store;
  final ReceiptImageStore images;
  final OcrService ocr;
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      store: store,
      images: images,
      ocr: ocr,
      child: MaterialApp(
        title: 'Expense-OCR',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: home ?? const HomeShell(),
      ),
    );
  }
}
