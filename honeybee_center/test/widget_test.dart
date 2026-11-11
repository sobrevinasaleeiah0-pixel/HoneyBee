import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/pages/login_page.dart';

void main() {
  testWidgets('shows the admin login screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('Honeybee Center'), findsOneWidget);
    expect(find.text('Admin Portal'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'LOGIN'), findsOneWidget);
  });
}
