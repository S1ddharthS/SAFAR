import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/safar_theme.dart';

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.maxLines});

  final String text;
  final Color? color;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: color ?? context.safar.faint,
      ),
    );
  }
}

class SafarCard extends StatelessWidget {
  const SafarCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.borderColor,
    this.radius = 22,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? palette.line),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.action,
    this.onAction,
  });

  final String title;
  final String? eyebrow;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Eyebrow(eyebrow!),
                  const SizedBox(height: 5),
                ],
                Text(title, style: context.texts.headlineSmall),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class SafarAvatar extends StatelessWidget {
  const SafarAvatar({
    super.key,
    required this.name,
    this.size = 40,
    this.imageUrl,
    this.highlight = false,
  });

  final String name;
  final double size;
  final String? imageUrl;
  final bool highlight;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final image = imageUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highlight ? palette.emberSoft : palette.raised,
        border: Border.all(
          color: highlight ? palette.ember : palette.line,
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: image != null && image.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: image,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorWidget: (context, url, error) => _initialsText(palette),
            )
          : _initialsText(palette),
    );
  }

  Widget _initialsText(SafarPalette palette) => Text(
    _initials,
    style: TextStyle(
      fontFamily: 'SafarSerif',
      fontSize: size * 0.36,
      fontWeight: FontWeight.w600,
      color: highlight ? palette.ember : palette.muted,
    ),
  );
}

class SafarImage extends StatelessWidget {
  const SafarImage({
    super.key,
    required this.url,
    this.height = 180,
    this.radius = 22,
    this.fit = BoxFit.cover,
    this.label,
  });

  final String? url;
  final double height;
  final double radius;
  final BoxFit fit;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final imageUrl = url;
    if (imageUrl == null || imageUrl.isEmpty) {
      return _fallback(palette);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: height,
        width: double.infinity,
        fit: fit,
        placeholder: (context, url) => _fallback(palette, loading: true),
        errorWidget: (context, url, error) => _fallback(palette),
      ),
    );
  }

  Widget _fallback(SafarPalette palette, {bool loading = false}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.raised, palette.emberSoft],
        ),
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.faint.withValues(alpha: 0.6),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  label == null
                      ? Icons.photo_outlined
                      : Icons.landscape_outlined,
                  color: palette.faint,
                  size: 26,
                ),
                if (label != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    label!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'SafarSerif',
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: palette.ink.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

enum ChipTone { neutral, ember, jade, rose }

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = ChipTone.neutral, this.icon});

  final String label;
  final ChipTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final (bg, fg) = switch (tone) {
      ChipTone.neutral => (palette.raised, palette.muted),
      ChipTone.ember => (palette.emberSoft, palette.ember),
      ChipTone.jade => (palette.jadeSoft, palette.jade),
      ChipTone.rose => (
        palette.rose.withValues(alpha: 0.12),
        palette.rose,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Text(
            titleCaseLabel(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.1,
            ),
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: fg),
                const SizedBox(width: 4),
              ],
              if (constraints.hasBoundedWidth) Flexible(child: text) else text,
            ],
          );
        },
      ),
    );
  }

  static String titleCaseLabel(String value) {
    if (value.isEmpty) return value;
    final cleaned = value.replaceAll('_', ' ');
    return '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: palette.faint),
                const SizedBox(width: 5),
              ],
              Expanded(child: Eyebrow(label, maxLines: 1)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.texts.titleLarge?.copyWith(fontSize: 19),
          ),
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint!, style: context.texts.bodySmall),
          ],
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.tone = ChipTone.neutral,
  });

  final String text;
  final IconData icon;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    final (bg, fg) = switch (tone) {
      ChipTone.neutral => (palette.raised, palette.muted),
      ChipTone.ember => (palette.emberSoft, palette.ember),
      ChipTone.jade => (palette.jadeSoft, palette.jade),
      ChipTone.rose => (palette.rose.withValues(alpha: 0.1), palette.rose),
    };
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: context.texts.bodySmall?.copyWith(color: fg, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class SafarErrorView extends StatelessWidget {
  const SafarErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: palette.raised,
                shape: BoxShape.circle,
                border: Border.all(color: palette.line),
              ),
              child: Icon(Icons.cloud_off_outlined, color: palette.muted),
            ),
            const SizedBox(height: 16),
            Text(
              'Something interrupted the journey',
              textAlign: TextAlign.center,
              style: context.texts.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class SafarEmpty extends StatelessWidget {
  const SafarEmpty({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.explore_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: palette.emberSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: palette.ember),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: context.texts.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: context.texts.bodySmall),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 14,
    this.width,
    this.radius = 10,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.safar.line.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3, this.itemHeight = 92});

  final int count;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              SafarCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(height: 12, width: 90),
                    SizedBox(height: 12),
                    SkeletonBox(height: 18),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 180),
                  ],
                ),
              ),
              if (i != count - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.skeleton,
    this.padding,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final Widget? skeleton;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => padding == null
          ? (skeleton ?? const SkeletonList())
          : Padding(padding: padding!, child: skeleton ?? const SkeletonList()),
      error: (error, stack) => Padding(
        padding: padding ?? EdgeInsets.zero,
        child: SafarErrorView(
          message: error.toString(),
          onRetry: onRetry,
        ),
      ),
    );
  }
}

class SafarSheetHeader extends StatelessWidget {
  const SafarSheetHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.texts.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: context.texts.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Resolves after the sheet's route has been popped *and* its subtree has been
/// unmounted. Callers typically create controllers before the sheet and
/// dispose them once this future completes; the route future alone resolves at
/// the start of the exit animation, while the sheet contents are still
/// mounted, so disposing then throws during teardown.
Future<T?> showSafarSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) async {
  final unmounted = Completer<void>();
  final result = await showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    builder: (context) => _SheetScope(
      onUnmounted: () {
        if (!unmounted.isCompleted) unmounted.complete();
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom +
              24,
        ),
        child: builder(context),
      ),
    ),
  );
  await unmounted.future.timeout(
    const Duration(seconds: 2),
    onTimeout: () {},
  );
  return result;
}

class _SheetScope extends StatefulWidget {
  const _SheetScope({required this.onUnmounted, required this.child});

  final VoidCallback onUnmounted;
  final Widget child;

  @override
  State<_SheetScope> createState() => _SheetScopeState();
}

class _SheetScopeState extends State<_SheetScope> {
  @override
  void dispose() {
    widget.onUnmounted();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SafarActionTile extends StatelessWidget {
  const SafarActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.caption,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.safar;
    return SafarCard(
      padding: const EdgeInsets.all(13),
      radius: 18,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: palette.emberSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: palette.ember),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.texts.titleSmall),
                if (caption != null)
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall,
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: palette.faint),
        ],
      ),
    );
  }
}

class SourceLabel extends StatelessWidget {
  const SourceLabel({super.key, required this.source, this.confidence});

  final String? source;
  final String? confidence;

  @override
  Widget build(BuildContext context) {
    if ((source == null || source!.isEmpty) &&
        (confidence == null || confidence!.isEmpty)) {
      return const SizedBox.shrink();
    }
    final parts = <String>[
      if (source != null && source!.isNotEmpty) source!,
      if (confidence != null && confidence!.isNotEmpty) confidence!,
    ];
    return Text(
      parts.join(' · ').toUpperCase(),
      style: TextStyle(
        fontSize: 9.5,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
        color: context.safar.faint,
      ),
    );
  }
}
