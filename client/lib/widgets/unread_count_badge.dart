import 'package:flutter/material.dart';

class UnreadCountBadge extends StatelessWidget {
  final int count;
  final String semanticsLabel;
  final Color backgroundColor;
  final Color foregroundColor;

  const UnreadCountBadge({
    super.key,
    required this.count,
    required this.semanticsLabel,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class UnreadBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final String semanticsLabel;
  final Key? badgeKey;
  final Color iconColor;
  final Color badgeBackgroundColor;
  final Color badgeForegroundColor;
  final double iconSize;

  const UnreadBadgeIcon({
    super.key,
    required this.icon,
    required this.count,
    required this.semanticsLabel,
    this.badgeKey,
    required this.iconColor,
    required this.badgeBackgroundColor,
    required this.badgeForegroundColor,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, color: iconColor, size: iconSize);
    if (count <= 0) return iconWidget;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        iconWidget,
        Positioned(
          right: -8,
          top: -7,
          child: UnreadCountBadge(
            key: badgeKey,
            count: count,
            semanticsLabel: semanticsLabel,
            backgroundColor: badgeBackgroundColor,
            foregroundColor: badgeForegroundColor,
          ),
        ),
      ],
    );
  }
}
