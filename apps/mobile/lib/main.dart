import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/services/diagnostics_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DiagnosticsService.setupGlobalErrorHandling();
  runApp(const ProviderScope(child: SafarApp()));
}
