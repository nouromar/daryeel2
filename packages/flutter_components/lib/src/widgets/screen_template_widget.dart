import 'package:flutter/widgets.dart';

import 'screen_primary_scroll_widget.dart';

class ScreenTemplateWidget extends StatelessWidget {
  const ScreenTemplateWidget({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
    this.headerGap = 8,
    this.bodyPadding = const EdgeInsets.all(16),
    this.primaryScrollPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.footerPadding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final List<Widget> header;
  final List<Widget> body;
  final List<Widget> footer;

  /// Spacing inserted between header and body when header is present.
  final double headerGap;

  /// Padding applied to non-primary-scroll body content.
  final EdgeInsetsGeometry bodyPadding;

  /// Padding applied around the single primary scroll widget (when present).
  final EdgeInsetsGeometry primaryScrollPadding;

  /// Padding applied around the footer content.
  final EdgeInsetsGeometry footerPadding;

  int? _singlePrimaryScrollIndex(List<Widget> widgets) {
    int? index;
    for (var i = 0; i < widgets.length; i++) {
      final w = widgets[i];
      final isPrimaryScroll = w is ScrollView || w is ScreenPrimaryScrollWidget;
      if (isPrimaryScroll) {
        if (index != null) return null;
        index = i;
      }
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final scrollIndex =
        body.isNotEmpty ? _singlePrimaryScrollIndex(body) : null;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header.isNotEmpty) ...[...header, SizedBox(height: headerGap)],
          Expanded(
            child: (scrollIndex == null)
                ? SingleChildScrollView(
                    padding: bodyPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: body,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (scrollIndex > 0)
                        Padding(
                          padding: bodyPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: body.take(scrollIndex).toList(
                                  growable: false,
                                ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: primaryScrollPadding,
                          child: body[scrollIndex],
                        ),
                      ),
                      if (scrollIndex < body.length - 1)
                        Padding(
                          padding: bodyPadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: body.skip(scrollIndex + 1).toList(
                                  growable: false,
                                ),
                          ),
                        ),
                    ],
                  ),
          ),
          if (footer.isNotEmpty)
            Padding(
              padding: footerPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: footer,
              ),
            ),
        ],
      ),
    );
  }
}
