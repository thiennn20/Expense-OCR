import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/formatters.dart';
import '../models/expense.dart';
import 'screens/camera_screen.dart';
import 'screens/review_screen.dart';

void openCamera(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CameraScreen()));

void openManualEntry(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReviewScreen.manual()));

void openEdit(BuildContext context, Expense expense) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => ReviewScreen(initial: expense)));

/// Deletes immediately with an "Undo" snackbar; receipt files are only
/// purged once the snackbar closes without undo.
Future<void> deleteWithUndo(BuildContext context, Expense expense) async {
  final store = AppScope.read(context).store;
  final messenger = ScaffoldMessenger.of(context);
  await store.remove(expense);
  messenger.hideCurrentSnackBar();
  final reason = await messenger
      .showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${expense.merchant} · ${formatVnd(expense.amount)}',
          ),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ),
      )
      .closed;
  if (reason == SnackBarClosedReason.action) {
    await store.restore(expense);
  } else {
    await store.purgeImages(expense);
  }
}
