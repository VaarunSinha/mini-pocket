import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocket_proxy/main.dart';

void main() {
  testWidgets('Mini Pocket basic layout smoke test', (
    WidgetTester tester,
  ) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const PocketProxyApp());

    // App bar title is present.
    expect(find.text('Mini Pocket'), findsWidgets);

    // Section headers exist.
    expect(find.text('Pairing'), findsOneWidget);
    expect(find.text('Record'), findsWidgets);

    // Record button icon is rendered.
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
