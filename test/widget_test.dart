import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart'; // 👈 only this line changed

void main() {
  testWidgets('AniMart app smoke test', (WidgetTester tester) async {
    // testing git push
    await tester.pumpWidget(const AniMartApp());

    // Verify the app launches without crashing.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
