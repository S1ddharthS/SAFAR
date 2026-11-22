import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/safar_theme.dart';
import '../widgets/safar_widgets.dart';

/// Metadata describing an exported local file.
class ExportedFileResult {
  const ExportedFileResult({
    required this.file,
    required this.filename,
    required this.mimeType,
    required this.bytesCount,
    required this.content,
  });

  final File file;
  final String filename;
  final String mimeType;
  final int bytesCount;
  final String content;

  String get formattedSize {
    if (bytesCount < 1024) return '$bytesCount B';
    if (bytesCount < 1024 * 1024) {
      return '${(bytesCount / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytesCount / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Service managing file exports to local device storage and native sharing.
class FileExporter {
  const FileExporter();

  /// Sanitizes a filename to avoid path traversal and invalid filesystem characters.
  static String sanitizeFilename(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    String base;
    String ext = '';
    if (dotIndex != -1) {
      base = filename.substring(0, dotIndex);
      ext = filename.substring(dotIndex);
    } else {
      base = filename;
    }
    var sanitizedBase = base.replaceAll(RegExp(r'[^\w-]'), '_');
    while (sanitizedBase.contains('__')) {
      sanitizedBase = sanitizedBase.replaceAll('__', '_');
    }
    sanitizedBase = sanitizedBase.replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitizedBase.isEmpty) sanitizedBase = 'export';

    var sanitizedExt = ext.replaceAll(RegExp(r'[^\w.]'), '');
    return '$sanitizedBase$sanitizedExt';
  }

  /// Saves [content] into the application temporary/cache directory.
  Future<ExportedFileResult> saveToCache({
    required String filename,
    required String content,
    required String mimeType,
    Directory? customDirectory,
  }) async {
    final sanitized = sanitizeFilename(filename);
    final dir = customDirectory ?? await getTemporaryDirectory();
    final file = File('${dir.path}/$sanitized');
    await file.writeAsString(content, flush: true);
    final length = await file.length();
    return ExportedFileResult(
      file: file,
      filename: sanitized,
      mimeType: mimeType,
      bytesCount: length,
      content: content,
    );
  }

  /// Saves binary [bytes] into the application temporary/cache directory.
  Future<ExportedFileResult> saveBytesToCache({
    required String filename,
    required List<int> bytes,
    required String mimeType,
    Directory? customDirectory,
  }) async {
    final sanitized = sanitizeFilename(filename);
    final dir = customDirectory ?? await getTemporaryDirectory();
    final file = File('${dir.path}/$sanitized');
    await file.writeAsBytes(bytes, flush: true);
    final length = await file.length();
    return ExportedFileResult(
      file: file,
      filename: sanitized,
      mimeType: mimeType,
      bytesCount: length,
      content: '',
    );
  }

  /// Attempts to open the exported file using the platform's default document handler.
  Future<bool> openFile(File file) async {
    try {
      final uri = Uri.file(file.path);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('FileExporter.openFile failed: $e');
    }
    return false;
  }

  /// Dispatches the native Android/iOS share sheet for the exported file.
  Future<bool> shareFile({
    required File file,
    required String mimeType,
    required String title,
    String? subject,
    String? text,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          title: title,
          subject: subject ?? title,
          text: text,
        ),
      );
      return result.status != ShareResultStatus.unavailable;
    } catch (e) {
      debugPrint('FileExporter.shareFile failed: $e');
      return false;
    }
  }
}

/// Bottom sheet presented after an export finishes, providing Open & Share actions.
class ExportActionSheet extends StatefulWidget {
  const ExportActionSheet({
    super.key,
    required this.result,
    required this.title,
    required this.subtitle,
    required this.formatLabel,
    required this.formatIcon,
    this.infoBannerText,
    this.openActionLabel = 'Open file',
    this.shareActionLabel = 'Share file',
    this.fileExporter = const FileExporter(),
  });

  final ExportedFileResult result;
  final String title;
  final String subtitle;
  final String formatLabel;
  final IconData formatIcon;
  final String? infoBannerText;
  final String openActionLabel;
  final String shareActionLabel;
  final FileExporter fileExporter;

  @override
  State<ExportActionSheet> createState() => _ExportActionSheetState();
}

class _ExportActionSheetState extends State<ExportActionSheet> {
  bool _busy = false;

  Future<void> _handleOpen() async {
    setState(() => _busy = true);
    try {
      final opened = await widget.fileExporter.openFile(widget.result.file);
      if (!mounted) return;
      if (!opened) {
        // On modern Android versions where direct file:// URIs are restricted without custom intents,
        // fall back smoothly to the system share sheet where the user can pick Chrome / Sheets / Drive.
        final shared = await widget.fileExporter.shareFile(
          file: widget.result.file,
          mimeType: widget.result.mimeType,
          title: widget.title,
        );
        if (!mounted) return;
        if (!shared) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not launch a viewer directly. Use "Share file" to select an app.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleShare() async {
    setState(() => _busy = true);
    try {
      await widget.fileExporter.shareFile(
        file: widget.result.file,
        mimeType: widget.result.mimeType,
        title: widget.title,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SafarSheetHeader(
            title: widget.title,
            subtitle: widget.subtitle,
          ),
          const SizedBox(height: 8),
          // File Details Card
          SafarCard(
            color: palette.raised,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.line),
                  ),
                  child: Icon(
                    widget.formatIcon,
                    color: palette.ember,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.result.filename,
                        style: context.texts.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.formatLabel} · ${widget.result.formattedSize}',
                        style: context.texts.labelSmall?.copyWith(
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.jade.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: palette.jade),
                      const SizedBox(width: 4),
                      Text(
                        'Saved',
                        style: context.texts.labelSmall?.copyWith(
                          color: palette.jade,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Actions
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _handleOpen,
                  icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  label: Text(widget.openActionLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _handleShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: Text(widget.shareActionLabel),
                ),
              ),
            ],
          ),
          if (widget.infoBannerText != null) ...[
            const SizedBox(height: 14),
            InfoBanner(
              icon: Icons.privacy_tip_outlined,
              text: widget.infoBannerText!,
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
