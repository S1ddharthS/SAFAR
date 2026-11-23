import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/env.dart';
import '../../core/models/safety.dart';
import '../../core/providers.dart';
import '../../core/theme/safar_theme.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/safar_widgets.dart';

class SoloSafetyScreen extends ConsumerStatefulWidget {
  const SoloSafetyScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<SoloSafetyScreen> createState() => _SoloSafetyScreenState();
}

class _SoloSafetyScreenState extends ConsumerState<SoloSafetyScreen> {
  bool _busy = false;

  Future<void> _callPhone(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open phone dialer for $phone')),
      );
    }
  }

  Future<void> _shareBeacon(String shareToken, String tripName) async {
    final url = '${Env.apiBaseUrl}/api/safety/beacon/$shareToken';
    final text = 'Track my journey safety updates for "$tripName" on SAFAR: $url';
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'SAFAR Journey Safety Beacon',
      ),
    );
  }

  Future<void> _showCheckInDialog(SoloSafetyStatus status) async {
    String selectedStatus = 'safe';
    final locationController = TextEditingController();
    final messageController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            final palette = dialogCtx.safar;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(dialogCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Record Check-In', style: dialogCtx.texts.titleLarge),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('How are you doing?', style: dialogCtx.texts.labelMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All Safe'),
                          selected: selectedStatus == 'safe',
                          selectedColor: palette.jadeSoft,
                          onSelected: (val) =>
                              setModalState(() => selectedStatus = 'safe'),
                        ),
                        ChoiceChip(
                          label: const Text('Delayed'),
                          selected: selectedStatus == 'delayed',
                          selectedColor: palette.emberSoft,
                          onSelected: (val) =>
                              setModalState(() => selectedStatus = 'delayed'),
                        ),
                        ChoiceChip(
                          label: const Text('Needs Help'),
                          selected: selectedStatus == 'needs_assistance',
                          selectedColor: palette.rose.withValues(alpha: 0.16),
                          onSelected: (val) => setModalState(
                              () => selectedStatus = 'needs_assistance'),
                        ),
                        ChoiceChip(
                          label: const Text('Journey Done'),
                          selected: selectedStatus == 'completed',
                          selectedColor: palette.surface,
                          onSelected: (val) =>
                              setModalState(() => selectedStatus = 'completed'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Current Location (optional)',
                        hintText: 'e.g. Kyoto Station, Hotel reception',
                        prefixIcon: Icon(Icons.pin_drop_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Message or Note (optional)',
                        hintText: 'e.g. Taking train to Arashiyama, battery at 60%',
                        prefixIcon: Icon(Icons.chat_bubble_outline, size: 20),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final loc = locationController.text.trim();
                          final msg = messageController.text.trim();
                          final messenger = ScaffoldMessenger.of(context);
                          Navigator.pop(modalContext);
                          setState(() => _busy = true);
                          try {
                            await ref
                                .read(safetyRepositoryProvider)
                                .recordCheckIn(
                                  widget.tripId,
                                  status: selectedStatus,
                                  locationName: loc,
                                  message: msg,
                                );
                            ref.invalidate(soloSafetyProvider(widget.tripId));
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Safety check-in recorded.'),
                              ),
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Failed to check in: $e')),
                            );
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                        child: const Text('Submit Check-In'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddContactDialog() async {
    final nameCtrl = TextEditingController();
    final relCtrl = TextEditingController(text: 'Family');
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool isPrimary = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(dialogCtx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add Emergency Contact', style: dialogCtx.texts.titleLarge),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(modalContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Contact Name *',
                        hintText: 'e.g. Sarah Jenkins',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: relCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Relationship *',
                        hintText: 'e.g. Partner, Parent, Sibling, Friend',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number *',
                        hintText: '+1 555 123 4567',
                        prefixIcon: Icon(Icons.phone_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email (optional)',
                        hintText: 'sarah@example.com',
                        prefixIcon: Icon(Icons.email_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'e.g. Lives in local time zone, knows hotel name',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Primary emergency contact'),
                      subtitle: const Text('Appears first for quick calling'),
                      value: isPrimary,
                      onChanged: (val) => setModalState(() => isPrimary = val),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          final rel = relCtrl.text.trim();
                          final phone = phoneCtrl.text.trim();
                          final email = emailCtrl.text.trim();
                          final notes = notesCtrl.text.trim();
                          final messenger = ScaffoldMessenger.of(context);

                          if (name.isEmpty || phone.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please enter name and phone number.'),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(modalContext);
                          setState(() => _busy = true);
                          try {
                            await ref
                                .read(safetyRepositoryProvider)
                                .addEmergencyContact(
                                  widget.tripId,
                                  name: name,
                                  relationship: rel,
                                  phone: phone,
                                  email: email,
                                  notes: notes,
                                  isPrimary: isPrimary,
                                );
                            ref.invalidate(soloSafetyProvider(widget.tripId));
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Emergency contact added.'),
                              ),
                            );
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text('Error adding contact: $e')),
                            );
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                        child: const Text('Save Contact'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _deleteContact(String contactId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Remove $name from emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(safetyRepositoryProvider)
          .deleteEmergencyContact(widget.tripId, contactId);
      ref.invalidate(soloSafetyProvider(widget.tripId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Emergency contact removed.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error deleting contact: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final safetyAsync = ref.watch(soloSafetyProvider(widget.tripId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Solo Safety Centre'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(soloSafetyProvider(widget.tripId)),
          ),
        ],
      ),
      body: AsyncView(
        value: safetyAsync,
        onRetry: () => ref.invalidate(soloSafetyProvider(widget.tripId)),
        skeleton: const SkeletonList(count: 3),
        builder: (status) {
          final settings = status.settings;
          final localNums = status.localEmergencyNumbers;
          final contacts = status.contacts;
          final lastCheckIn = status.lastCheckIn;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              // 1. Informational Disclaimer
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: palette.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 20, color: palette.ember),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'SAFAR Solo Safety is a personal check-in and trusted-contact coordination tool. It does not provide continuous GPS surveillance or automated emergency dispatch.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. Live Safety Status Card
              SafarCard(
                padding: const EdgeInsets.all(18),
                radius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Eyebrow(
                            'CURRENT SAFETY STATUS',
                            color: palette.ember,
                          ),
                        ),
                        StatusChip(
                          lastCheckIn?.status.toUpperCase() ?? 'ACTIVE',
                          tone: status.isOverdue
                              ? ChipTone.rose
                              : (lastCheckIn?.status == 'safe' || lastCheckIn == null
                                  ? ChipTone.jade
                                  : ChipTone.ember),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (status.isOverdue) ...[
                      InfoBanner(
                        text:
                            'Check-in is ${status.hoursOverdue.toStringAsFixed(1)}h overdue. Please check in or notify your contacts.',
                        icon: Icons.warning_amber_rounded,
                        tone: ChipTone.rose,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      lastCheckIn != null
                          ? 'Last check-in: ${formatDate(lastCheckIn.createdAt)}'
                          : 'No check-ins recorded yet on this trip',
                      style: context.texts.titleMedium,
                    ),
                    if (lastCheckIn?.locationName != null &&
                        lastCheckIn!.locationName!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.pin_drop_outlined,
                              size: 16, color: palette.faint),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lastCheckIn.locationName!,
                              style: context.texts.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (lastCheckIn?.message != null &&
                        lastCheckIn!.message!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '"${lastCheckIn.message!}"',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                          color: palette.faint,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _showCheckInDialog(status),
                            icon: const Icon(Icons.check_circle_outline, size: 18),
                            label: const Text('Check In Now'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. Local Emergency Services (Country Aware)
              const SectionHeader(
                eyebrow: 'Local Assistance',
                title: 'Emergency Numbers',
              ),
              Text(
                'Direct device dialers for ${localNums.countryName} (${localNums.countryCode}). Works offline.',
                style: context.texts.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _EmergencyDialButton(
                      label: 'Police',
                      number: localNums.police,
                      icon: Icons.local_police_outlined,
                      tone: ChipTone.neutral,
                      onTap: () => _callPhone(localNums.police),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EmergencyDialButton(
                      label: 'Ambulance',
                      number: localNums.ambulance,
                      icon: Icons.medical_services_outlined,
                      tone: ChipTone.rose,
                      onTap: () => _callPhone(localNums.ambulance),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EmergencyDialButton(
                      label: 'Fire',
                      number: localNums.fire,
                      icon: Icons.fire_truck_outlined,
                      tone: ChipTone.ember,
                      onTap: () => _callPhone(localNums.fire),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4. Trusted Contact Beacon (Public Share Link)
              const SectionHeader(
                eyebrow: 'Peace of Mind',
                title: 'Trusted Contact Beacon',
              ),
              SafarCard(
                padding: const EdgeInsets.all(16),
                radius: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Public Safety Beacon',
                                style: context.texts.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Allow loved ones to check your status without an account',
                                style: context.texts.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: settings.locationSharingEnabled,
                          onChanged: _busy
                              ? null
                              : (enabled) async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  setState(() => _busy = true);
                                  try {
                                    await ref
                                        .read(safetyRepositoryProvider)
                                        .updateSettings(
                                          widget.tripId,
                                          locationSharingEnabled: enabled,
                                        );
                                    ref.invalidate(
                                        soloSafetyProvider(widget.tripId));
                                  } catch (e) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              'Failed to update beacon: $e')),
                                    );
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                        ),
                      ],
                    ),
                    if (settings.locationSharingEnabled &&
                        settings.shareToken != null) ...[
                      const Divider(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _shareBeacon(
                                settings.shareToken!,
                                status.tripName,
                              ),
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: const Text('Share Beacon Link'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 5. Emergency Contacts
              SectionHeader(
                eyebrow: 'In Case of Need',
                title: 'Emergency Contacts',
                action: 'Add Contact',
                onAction: _busy ? null : _showAddContactDialog,
              ),
              if (contacts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.line),
                  ),
                  child: Center(
                    child: Text(
                      'No emergency contacts added yet. Tap "Add Contact" to save trusted family or friends.',
                      textAlign: TextAlign.center,
                      style: context.texts.bodySmall,
                    ),
                  ),
                )
              else
                for (final contact in contacts) ...[
                  SafarCard(
                    padding: const EdgeInsets.all(14),
                    radius: 18,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: contact.isPrimary
                                ? palette.emberSoft
                                : palette.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: palette.line),
                          ),
                          child: Icon(
                            Icons.person_outline,
                            size: 20,
                            color: contact.isPrimary
                                ? palette.ember
                                : palette.ink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    contact.name,
                                    style: context.texts.titleSmall,
                                  ),
                                  if (contact.isPrimary) ...[
                                    const SizedBox(width: 6),
                                    const StatusChip(
                                      'Primary',
                                      tone: ChipTone.ember,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${contact.relationship} · ${contact.phone}',
                                style: context.texts.bodySmall,
                              ),
                              if (contact.notes != null &&
                                  contact.notes!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  contact.notes!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.faint,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Call ${contact.name}',
                          icon: Icon(Icons.phone, color: palette.jade),
                          onPressed: () => _callPhone(contact.phone),
                        ),
                        IconButton(
                          tooltip: 'Delete contact',
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: palette.faint),
                          onPressed: () =>
                              _deleteContact(contact.id, contact.name),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 20),

              // 6. Check-in Frequency
              const SectionHeader(
                eyebrow: 'Preferences',
                title: 'Check-In Frequency',
              ),
              SafarCard(
                padding: const EdgeInsets.all(16),
                radius: 20,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Expected check-in interval',
                        style: context.texts.titleSmall,
                      ),
                    ),
                    DropdownButton<int>(
                      value: settings.checkInFrequencyHours,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                        DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                        DropdownMenuItem(value: 24, child: Text('Every 24 hours')),
                        DropdownMenuItem(value: 48, child: Text('Every 48 hours')),
                      ],
                      onChanged: (hours) async {
                        if (hours == null) return;
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _busy = true);
                        try {
                          await ref
                              .read(safetyRepositoryProvider)
                              .updateSettings(
                                widget.tripId,
                                checkInFrequencyHours: hours,
                              );
                          ref.invalidate(soloSafetyProvider(widget.tripId));
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Error updating frequency: $e'),
                            ),
                          );
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmergencyDialButton extends StatelessWidget {
  const _EmergencyDialButton({
    required this.label,
    required this.number,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final String number;
  final IconData icon;
  final ChipTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    Color bg;
    Color fg;
    switch (tone) {
      case ChipTone.rose:
        bg = palette.rose.withValues(alpha: 0.14);
        fg = palette.rose;
        break;
      case ChipTone.ember:
        bg = palette.emberSoft;
        fg = palette.ember;
        break;
      case ChipTone.jade:
        bg = palette.jadeSoft;
        fg = palette.jade;
        break;
      case ChipTone.neutral:
        bg = palette.surface;
        fg = palette.ink;
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: fg.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              number,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
