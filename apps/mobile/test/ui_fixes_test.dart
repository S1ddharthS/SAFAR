import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/core/widgets/safar_widgets.dart';
import 'package:safar_mobile/features/trip/pulse_screen.dart' show formatDayLabel;

void main() {
  test('pulse day label pairs the weekday with a readable date', () {
    expect(formatDayLabel('2026-11-20'), 'Friday · 20 Nov 2026');
    expect(formatDayLabel('20/11/2026'), '20/11/2026');
  });

  testWidgets('image placeholder shows the destination name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SafarTheme.light(),
        home: const Scaffold(
          body: Center(child: SafarImage(url: '', label: 'Kyoto')),
        ),
      ),
    );

    expect(find.text('Kyoto'), findsOneWidget);
    expect(find.byIcon(Icons.photo_outlined), findsNothing);
  });

  testWidgets('image placeholder without a label stays icon-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SafarTheme.light(),
        home: const Scaffold(body: Center(child: SafarImage(url: ''))),
      ),
    );

    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });
}
