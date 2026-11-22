import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/native/deep_links.dart';
import '../core/native/pending_route.dart';
import '../core/theme/safar_theme.dart';
import '../core/theme/theme_controller.dart';
import 'router.dart';

class SafarApp extends ConsumerStatefulWidget {
  const SafarApp({super.key});

  @override
  ConsumerState<SafarApp> createState() => _SafarAppState();
}

class _SafarAppState extends ConsumerState<SafarApp> {
  late final AppLinks _links;
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    _links = AppLinks();
    _subscription = _links.uriLinkStream.listen(
      _handleLink,
      onError: (Object _) {},
    );
    _links.getInitialLink().then(_handleLink, onError: (Object _) {});
  }

  void _handleLink(Uri? uri) {
    if (uri == null) return;
    final path = appPathFromUri(uri);
    if (path == null) return;
    PendingRoute.set(path);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routerProvider).go(path);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SAFAR',
      debugShowCheckedModeBanner: false,
      theme: SafarTheme.light(),
      darkTheme: SafarTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
