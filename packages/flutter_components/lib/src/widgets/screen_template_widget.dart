import 'package:flutter/widgets.dart';

import 'screen_primary_scroll_widget.dart';

class ScreenTemplateWidget extends StatelessWidget {
  const ScreenTemplateWidget({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
  });

  final List<Widget> header;
  final List<Widget> body;
  final List<Widget> footer;

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
          if (header.isNotEmpty) ...[...header, const SizedBox(height: 8)],
          Expanded(
            child: (scrollIndex == null)
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
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
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: body.take(scrollIndex).toList(
                                  growable: false,
                                ),
                          ),
                        ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: body[scrollIndex],
                        ),
                      ),
                      if (scrollIndex < body.length - 1)
                        Padding(
                          padding: const EdgeInsets.all(16),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
