import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/safar_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/widgets/safar_widgets.dart';
import 'auth_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    const ink = Color(0xFF12110E);
    const cream = Color(0xFFF5EFE3);
    const ember = Color(0xFFF0A34A);
    final failed = auth.error != null && !auth.signedIn;

    return Scaffold(
      backgroundColor: ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 3),
              Container(
                width: 46,
                height: 2,
                color: ember,
              ),
              const SizedBox(height: 26),
              const Text(
                'SAFAR',
                style: TextStyle(
                  fontFamily: 'SafarSerif',
                  fontSize: 52,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 6,
                  color: cream,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Travel, negotiated with care.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: cream.withValues(alpha: 0.62),
                ),
              ),
              const Spacer(flex: 4),
              if (failed) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cream.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cream.withValues(alpha: 0.14)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 18, color: ember),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          auth.error!,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: cream.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: ember,
                    foregroundColor: ink,
                  ),
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).bootstrap(),
                  child: const Text('Try again'),
                ),
              ] else ...[
                SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Color(0x22F5EFE3),
                      color: ember,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Restoring your private session…',
                  style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1.2,
                    color: cream.withValues(alpha: 0.4),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'PRIVATE BY DEFAULT · GROUP APPROVED',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                  color: cream.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _WelcomePage(
      icon: Icons.route_outlined,
      eyebrow: 'A shared plan, not a compromise',
      title: 'Travel that fits\neveryone in the group',
      body:
          'SAFAR negotiates the itinerary with your group. Preferences stay private; '
          'the plan explains itself and never changes without approval.',
    ),
    _WelcomePage(
      icon: Icons.auto_awesome_outlined,
      eyebrow: 'Intelligence with receipts',
      title: 'Guidance that shows\nwhere it came from',
      body:
          'Recommendations, crowd estimates and Dream Import results come with their '
          'source, confidence and limits. Nothing is invented or presented as fact.',
    ),
    _WelcomePage(
      icon: Icons.lock_outline,
      eyebrow: 'Yours, kept quietly',
      title: 'Memories for the group,\nprivacy for the person',
      body:
          'Journey DNA is editable, budgets stay private, and your location is never '
          'published. You decide what the group can see and what stays yours.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).complete();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 14, 0),
              child: Row(
                children: [
                  Text(
                    'SAFAR',
                    style: TextStyle(
                      fontFamily: 'SafarSerif',
                      fontSize: 18,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _pages[index],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? palette.ink : palette.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(
                        _page == _pages.length - 1
                            ? 'Start planning'
                            : 'Continue',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('I already have an account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 236,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.emberSoft, palette.raised, palette.jadeSoft],
              ),
              border: Border.all(color: palette.line),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  bottom: -40,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: palette.ember.withValues(alpha: 0.28),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 34,
                  top: 44,
                  child: Icon(
                    icon,
                    size: 74,
                    color: palette.ink.withValues(alpha: 0.82),
                  ),
                ),
                Positioned(
                  left: 24,
                  bottom: 24,
                  child: Container(
                    width: 34,
                    height: 2,
                    color: palette.ember,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Eyebrow(eyebrow),
          const SizedBox(height: 10),
          Text(title, style: context.texts.displaySmall),
          const SizedBox(height: 12),
          Text(
            body,
            style: context.texts.bodyMedium?.copyWith(
              color: palette.muted,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
