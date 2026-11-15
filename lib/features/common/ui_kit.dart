import 'package:flutter/material.dart';

import '../../core/utils/transfer_metrics.dart';
import '../../theme/app_theme.dart';

/// Rounded surface panel used across screens.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Material(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor ?? AppColors.border),
          ),
          child: content,
        ),
      ),
    );
  }
}

/// Small rounded pill used for statuses and badges.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Large circular hero action used on the home screen.
class HeroActionButton extends StatelessWidget {
  const HeroActionButton({
    super.key,
    required this.emoji,
    required this.label,
    required this.caption,
    required this.onTap,
    this.color = AppColors.primary,
  });

  final String emoji;
  final String label;
  final String caption;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: 0.9),
                    color.withValues(alpha: 0.55),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 38)),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps a category name to its icon + accent colour.
class CategoryStyle {
  const CategoryStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static CategoryStyle of(String category) {
    switch (category) {
      case 'Videos':
        return const CategoryStyle(Icons.movie_rounded, Color(0xFF8B5CF6));
      case 'Images':
      case 'Photos':
        return const CategoryStyle(Icons.photo_rounded, Color(0xFF06B6D4));
      case 'Apps':
        return const CategoryStyle(Icons.android_rounded, Color(0xFF22C55E));
      case 'Audio':
      case 'Music':
        return const CategoryStyle(Icons.music_note_rounded, Color(0xFFF59E0B));
      default:
        return const CategoryStyle(Icons.description_rounded, Color(0xFF60A5FA));
    }
  }
}

/// Icon chip with a tinted background, used in list rows.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 44});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: style.color.withValues(alpha: 0.3)),
      ),
      child: Icon(style.icon, color: style.color, size: size * 0.5),
    );
  }
}

/// Middle-truncating text that never overflows its parent.
class TruncatedName extends StatelessWidget {
  const TruncatedName({
    super.key,
    required this.name,
    this.maxLength = 28,
    this.style,
  });

  final String name;
  final int maxLength;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      TransferMetrics.middleTruncate(name, maxLength: maxLength),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ??
          const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
    );
  }
}

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
