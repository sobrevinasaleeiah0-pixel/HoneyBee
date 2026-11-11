import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/widgets/supabase_startup_gate.dart';

void main() {
  testWidgets('shows a retryable error when Supabase startup fails', (
    tester,
  ) async {
    var attempts = 1;
    final firstAttempt = Completer<void>();
    var initialization = firstAttempt.future;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => SupabaseStartupGate(
            initialization: initialization,
            onRetry: () {
              setState(() {
                attempts++;
                initialization = Future<void>.value();
              });
            },
            child: const Text('Admin Portal'),
          ),
        ),
      ),
    );
    firstAttempt.completeError(StateError('Supabase unavailable'));
    await tester.pumpAndSettle();

    expect(find.text('Admin service unavailable'), findsOneWidget);
    expect(find.textContaining('Supabase unavailable'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Admin service unavailable'), findsNothing);
    expect(find.text('Admin Portal'), findsOneWidget);
  });
}
