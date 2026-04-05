import 'package:flutter/material.dart';

class PrimaryActionBarWidget extends StatelessWidget {
  const PrimaryActionBarWidget({
    super.key,
    required this.primaryLabel,
    this.onPrimaryPressed,
    this.contentAlignment = Alignment.center,
    this.expand = true,
  });

  final String primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final AlignmentGeometry contentAlignment;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final shrinkWrapOverrides = FilledButton.styleFrom(
      minimumSize: const Size(0, 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

    final themeStyle = FilledButtonTheme.of(context).style;
    final effectiveStyle = expand
        ? themeStyle
        : (themeStyle == null
            ? shrinkWrapOverrides
            : themeStyle.merge(shrinkWrapOverrides));

    final button = FilledButton(
      style: effectiveStyle,
      onPressed: onPrimaryPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Align(
          alignment: contentAlignment,
          widthFactor: expand ? null : 1.0,
          child: Text(primaryLabel),
        ),
      ),
    );

    if (!expand) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [Flexible(fit: FlexFit.loose, child: button)],
      );
    }

    return SizedBox(width: double.infinity, child: button);
  }
}
