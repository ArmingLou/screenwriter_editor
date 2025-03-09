import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screenwriter_editor/main.dart';

void main() {
  testWidgets('App renders correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ScreenwriterEditorApp());

    // Verify that the app renders without errors
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
