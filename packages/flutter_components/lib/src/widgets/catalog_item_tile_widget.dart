import 'package:flutter/material.dart';

class CatalogItemTileWidget extends StatelessWidget {
  const CatalogItemTileWidget({
    super.key,
    required this.title,
    required this.subtitle,
    this.surface = 'flat',
    this.rxRequired = false,
    this.onTap,
    this.onAddPressed,
  });

  final String title;
  final String subtitle;
  final String surface;
  final bool rxRequired;
  final VoidCallback? onTap;
  final VoidCallback? onAddPressed;

  @override
  Widget build(BuildContext context) {
    final subtitleStyle = Theme.of(context).textTheme.bodyMedium;
    final rxStyle = (subtitleStyle ?? const TextStyle()).copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w600,
    );

    List<InlineSpan> buildSubtitleSpans() {
      if (subtitle.isEmpty && !rxRequired) return const <InlineSpan>[];
      if (!rxRequired) {
        return <InlineSpan>[TextSpan(text: subtitle, style: subtitleStyle)];
      }

      final lower = subtitle.toLowerCase();
      final rxIndex = lower.indexOf('rx');

      // If the subtitle already contains "rx", emphasize that substring.
      if (rxIndex >= 0) {
        final before = subtitle.substring(0, rxIndex);
        final rx = subtitle.substring(rxIndex, rxIndex + 2);
        final after = subtitle.substring(rxIndex + 2);
        return <InlineSpan>[
          if (before.isNotEmpty) TextSpan(text: before, style: subtitleStyle),
          TextSpan(text: rx, style: rxStyle),
          if (after.isNotEmpty) TextSpan(text: after, style: subtitleStyle),
        ];
      }

      // Otherwise append an emphasized "• Rx".
      return <InlineSpan>[
        if (subtitle.isNotEmpty) TextSpan(text: subtitle, style: subtitleStyle),
        TextSpan(
          text: subtitle.isEmpty ? 'Rx' : ' • Rx',
          style: rxStyle,
        ),
      ];
    }

    return Card(
      elevation: switch (surface) {
        'flat' => 0,
        'subtle' => 0.5,
        _ => 1.5,
      },
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (subtitle.isNotEmpty || rxRequired) ...[
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: buildSubtitleSpans(),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onAddPressed,
                tooltip: 'Add to cart',
                icon: const Icon(Icons.add_shopping_cart_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
