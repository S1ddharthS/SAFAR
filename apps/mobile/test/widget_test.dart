import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar_mobile/core/theme/safar_theme.dart';
import 'package:safar_mobile/features/auth/login_screen.dart';

Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(theme: SafarTheme.light(), home: child),
);

void main() {
  testWidgets('login form validates input before calling the API', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('password field can be revealed and hidden', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));

    EditableText field() => tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextFormField).at(1),
        matching: find.byType(EditableText),
      ),
    );

    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(field().obscureText, isTrue);
  });

  testWidgets('registration form asks for name, email and password', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const RegisterScreen()));

    expect(find.text('Start a private trip.'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
