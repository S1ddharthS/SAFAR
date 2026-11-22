import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/common.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';
import '../auth/auth_controller.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  void _afterSave() {
    ref.invalidate(meProvider);
    ref.read(authControllerProvider.notifier).reload();
  }

  Future<void> _save(
    Future<void> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      _afterSave();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editField({
    required String title,
    required String label,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || !mounted) return;
    await _save(() => onSave(value), '$title updated.');
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = await ref.read(userRepositoryProvider).exportData();
      if (!mounted) return;
      await showSafarSheet<void>(
        context,
        builder: (_) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SafarSheetHeader(
                title: 'Your data export',
                subtitle:
                    'Private member information is excluded. Copy this if you need a record.',
              ),
              SelectableText(data, style: context.texts.bodySmall),
            ],
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount(Me me) async {
    if (me.user.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Administrator accounts must be transferred first.'),
        ),
      );
      return;
    }
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your personal learning, private planning data and profile details are erased. '
              'This cannot be undone. Type DELETE to continue.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'DELETE'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () => Navigator.of(
              context,
            ).pop(controller.text.trim() == 'DELETE'),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true) return;
    await _save(
      () => ref.read(userRepositoryProvider).deleteAccount(),
      'Account deletion requested.',
    );
    if (!mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } on Object {
      ref.invalidate(meProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: me,
          onRetry: () => ref.invalidate(meProvider),
          builder: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Eyebrow('Appearance'),
              const SizedBox(height: 8),
              SafarCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: context.texts.titleMedium),
                    const SizedBox(height: 10),
                    SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: ThemeMode.system,
                          label: Text('System'),
                          icon: Icon(Icons.brightness_auto_outlined, size: 16),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (value) => ref
                          .read(themeModeProvider.notifier)
                          .set(value.first),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(eyebrow: 'Account', title: 'Identity'),
              SafarCard(
                child: Column(
                  children: [
                    _Row(
                      label: 'Display name',
                      value: data.user.displayName,
                      onTap: () => _editField(
                        title: 'Display name',
                        label: 'Name',
                        initial: data.user.displayName,
                        hint: 'How the group sees you',
                        onSave: (value) async {
                          if (value.length < 2) {
                            throw ApiException(
                              message: 'Name needs at least two characters.',
                            );
                          }
                          await ref
                              .read(userRepositoryProvider)
                              .updateSettings({'display_name': value});
                        },
                      ),
                    ),
                    const Divider(height: 20),
                    _Row(
                      label: 'Headline',
                      value: data.profile.headline ?? 'Not set',
                      onTap: () => _editField(
                        title: 'Headline',
                        label: 'Headline',
                        initial: data.profile.headline ?? '',
                        hint: 'A short line about how you travel',
                        onSave: (value) => ref
                            .read(userRepositoryProvider)
                            .updateProfile({'headline': value}),
                      ),
                    ),
                    const Divider(height: 20),
                    _Row(
                      label: 'Home city',
                      value: data.profile.homeCity ?? 'Not set',
                      onTap: () => _editField(
                        title: 'Home city',
                        label: 'City',
                        initial: data.profile.homeCity ?? '',
                        hint: 'Used for travel time estimates',
                        onSave: (value) => ref
                            .read(userRepositoryProvider)
                            .updateProfile({'home_city': value}),
                      ),
                    ),
                    const Divider(height: 20),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Quiet mode'),
                      subtitle: const Text(
                        'Fewer nudges. Critical approvals still arrive.',
                      ),
                      value: data.user.quietMode,
                      onChanged: _busy
                          ? null
                          : (value) => _save(
                              () => ref
                                  .read(userRepositoryProvider)
                                  .updateSettings({'quiet_mode': value}),
                              value ? 'Quiet mode on.' : 'Quiet mode off.',
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(eyebrow: 'Privacy', title: 'What others see'),
              SafarCard(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Public profile'),
                      subtitle: const Text(
                        'Show your headline and interests outside your trips.',
                      ),
                      value: data.profile.publicProfile,
                      onChanged: _busy
                          ? null
                          : (value) => _save(
                              () => ref
                                  .read(userRepositoryProvider)
                                  .updateProfile({'public_profile': value}),
                              'Profile visibility updated.',
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Traveller discovery'),
                      subtitle: const Text(
                        'Allow compatible travellers to find you. Mutual acceptance is always required.',
                      ),
                      value: data.profile.allowDiscovery,
                      onChanged: _busy
                          ? null
                          : (value) => _save(
                              () => ref
                                  .read(userRepositoryProvider)
                                  .updateProfile({'allow_discovery': value}),
                              'Discovery preference updated.',
                            ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Location sharing'),
                      subtitle: const Text(
                        'Share current location with trip members only. Exact live locations are never public.',
                      ),
                      value: data.profile.locationSharing,
                      onChanged: _busy
                          ? null
                          : (value) => _save(
                              () => ref
                                  .read(userRepositoryProvider)
                                  .updateProfile({'location_sharing': value}),
                              'Location sharing updated.',
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(eyebrow: 'Consents', title: 'Permissions'),
              SafarCard(
                child: Column(
                  children: [
                    for (final entry in data.consents.entries)
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(titleCase(entry.key)),
                        subtitle: Text(
                          'Policy ${entry.value.policyVersion}'
                          '${entry.value.updatedAt == null ? '' : ' · ${timeAgo(entry.value.updatedAt)}'}',
                        ),
                        value: entry.value.granted,
                        onChanged: _busy
                            ? null
                            : (value) => _save(
                                () => ref
                                    .read(userRepositoryProvider)
                                    .updateConsents({entry.key: value}),
                                'Consent updated.',
                              ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Personalisation and location consents can be withdrawn at any time. '
                      'Marketing is off unless you opt in.',
                      style: context.texts.labelSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const SectionHeader(eyebrow: 'Your data', title: 'Control'),
              SafarActionTile(
                icon: Icons.download_outlined,
                label: 'Export my data',
                caption: 'Download what SAFAR holds about you',
                onTap: _busy ? null : _export,
              ),
              const SizedBox(height: 8),
              SafarCard(
                borderColor: context.colors.error.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete account',
                      style: context.texts.titleSmall?.copyWith(
                        color: context.colors.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Erases private planning data, learning signals and profile details. '
                      'Trip history for the group is retained under SAFAR policy.',
                      style: context.texts.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.error,
                      ),
                      onPressed: _busy ? null : () => _deleteAccount(data),
                      child: const Text('Delete my account'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'SAFAR policy ${data.policyVersion} · ${data.user.locale.toUpperCase()}'
                '${data.user.timezone == null ? '' : ' · ${data.user.timezone}'}',
                style: context.texts.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.texts.labelSmall),
                  const SizedBox(height: 2),
                  Text(value, style: context.texts.bodyMedium),
                ],
              ),
            ),
            Icon(Icons.edit_outlined, size: 16, color: context.safar.faint),
          ],
        ),
      ),
    );
  }
}
