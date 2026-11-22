import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/widgets/safar_widgets.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(email: _email.text, password: _password.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Sign in could not be completed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    button: true,
                    label: 'Back to welcome',
                    child: InkWell(
                      onTap: () => context.go('/welcome'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'SAFAR',
                          style: TextStyle(
                            fontFamily: 'SafarSerif',
                            fontSize: 18,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  const Eyebrow('Sign in'),
                  const SizedBox(height: 10),
                  Text('Welcome back.', style: context.texts.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your session is kept in a secure, revocable cookie on this device.',
                    style: context.texts.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    InfoBanner(
                      text: _error!,
                      icon: Icons.error_outline,
                      tone: ChipTone.rose,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (!text.contains('@') || text.length < 5) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                      ),
                    ),
                    validator: (value) =>
                        (value == null || value.isEmpty) ? 'Enter your password' : null,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => context.go('/register'),
                      child: const Text('New to SAFAR? Create an account'),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const InfoBanner(
                    text:
                        'SAFAR never asks for your social media password. '
                        'Dream Import works from notes you paste yourself.',
                    icon: Icons.shield_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).register(
        email: _email.text,
        password: _password.text,
        displayName: _name.text,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object {
      if (!mounted) return;
      setState(() => _error = 'Your account could not be created. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    button: true,
                    label: 'Back to welcome',
                    child: InkWell(
                      onTap: () => context.go('/welcome'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'SAFAR',
                          style: TextStyle(
                            fontFamily: 'SafarSerif',
                            fontSize: 18,
                            letterSpacing: 3,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  const Eyebrow('Create account'),
                  const SizedBox(height: 10),
                  Text('Start a private trip.', style: context.texts.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Trips are private by default. You can invite the group once the plan exists.',
                    style: context.texts.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    InfoBanner(
                      text: _error!,
                      icon: Icons.error_outline,
                      tone: ChipTone.rose,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      hintText: 'How the group will see you',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.length < 2) return 'Use at least 2 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (!text.contains('@') || text.length < 5) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 8 characters',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 8) {
                        return 'Use at least 8 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create account'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => context.go('/login'),
                      child: const Text('I already have an account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
