import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';
import 'package:intl/intl.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerStatusTimelinePanelSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('StatusTimelinePanel', (node, componentRegistry) {
    final title = (node.props['title'] as String?)?.trim();

    const defaultDateFormat = 'dd/MM/yyyy hh:mm a';
    final dateFormat = (node.props['dateFormat'] as String?)?.trim();

    final itemsPath = (node.props['itemsPath'] as String?)?.trim();
    final itemKeyPath = (node.props['itemKeyPath'] as String?)?.trim();

    final titleKey = (node.props['titleKey'] as String?)?.trim();
    final subtitleKey = (node.props['subtitleKey'] as String?)?.trim();

    final paddingLeft = schemaAsDouble(node.props['paddingLeft']) ?? 20;
    final itemGap = schemaAsDouble(node.props['itemGap']) ?? 8;
    final rowSpacing = schemaAsDouble(node.props['rowSpacing']) ?? 12;

    const statePrefixDot = r'$state.';
    const statePrefixColon = r'$state:';
    final isStateItemsPath = itemsPath != null &&
        (itemsPath.startsWith(statePrefixDot) ||
            itemsPath.startsWith(statePrefixColon));
    final stateItemsKey = isStateItemsPath
        ? (itemsPath.startsWith(statePrefixDot)
            ? itemsPath.substring(statePrefixDot.length)
            : itemsPath.substring(statePrefixColon.length))
        : null;

    return Builder(
      builder: (buildContext) {
        final dataScope = SchemaDataScope.maybeOf(buildContext);

        Object? resolveItems() {
          if (isStateItemsPath) {
            final key = (stateItemsKey ?? '').trim();
            if (key.isEmpty) return null;
            final store = SchemaStateScope.maybeOf(buildContext);
            return store?.getValue(key);
          }

          final data = dataScope?.data;
          if (itemsPath == null || itemsPath.isEmpty) return data;
          return readJsonPath(data, itemsPath);
        }

        String? stableKeyForItem(Object? item, int index) {
          final path =
              (itemKeyPath == null || itemKeyPath.isEmpty) ? 'id' : itemKeyPath;

          final v = readJsonPath(item, path);
          if (v is String) {
            final trimmed = v.trim();
            return trimmed.isEmpty ? null : trimmed;
          }
          if (v is num || v is bool) {
            return v.toString();
          }
          return null;
        }

        String readString(Object? item, String key, {String fallback = ''}) {
          final v = readJsonPath(item, key);
          if (v == null) return fallback;
          if (v is String) return v;
          return v.toString();
        }

        String normalizeDateFormat(String format) {
          var normalized = format.trim();
          if (normalized.isEmpty) return normalized;

          // Accept a small alias used in product specs.
          normalized = normalized.replaceAll(
            RegExp('am/pm', caseSensitive: false),
            'a',
          );

          // Common month/minute confusion in specs.
          normalized = normalized
              .replaceAll('dd/Mm/yyyy', 'dd/MM/yyyy')
              .replaceAll('dd/mm/yyyy', 'dd/MM/yyyy');

          return normalized;
        }

        String formatMaybeDateSubtitle(String subtitle) {
          final trimmed = subtitle.trim();
          if (trimmed.isEmpty) return trimmed;

          final parsed = DateTime.tryParse(trimmed);
          if (parsed == null) return subtitle;

          final locale = Localizations.localeOf(buildContext).toString();
          final preferred =
              normalizeDateFormat(dateFormat ?? defaultDateFormat);
          final fallback = normalizeDateFormat(defaultDateFormat);

          try {
            return DateFormat(preferred, locale).format(parsed.toLocal());
          } catch (_) {
            try {
              return DateFormat(fallback, locale).format(parsed.toLocal());
            } catch (_) {
              return subtitle;
            }
          }
        }

        Widget buildPanel() {
          final items = resolveItems();

          final List itemsList;
          if (items == null) {
            itemsList = const <Object?>[];
          } else if (items is List) {
            itemsList = items;
          } else {
            return const UnknownSchemaWidget(
              componentName: 'StatusTimelinePanel(items-not-list)',
            );
          }

          final theme = Theme.of(buildContext);
          final scheme = theme.colorScheme;

          final headerStyle = theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.secondary,
          );

          final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: scheme.onSurfaceVariant,
          );

          final titleStyle = theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (title != null && title.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(left: paddingLeft),
                  child: Text(title, style: headerStyle),
                ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: itemsList.length,
                itemBuilder: (context, index) {
                  final item = itemsList[index];

                  final itemTitle = readString(
                    item,
                    (titleKey == null || titleKey.isEmpty) ? 'title' : titleKey,
                  ).trim();

                  final itemSubtitle = readString(
                    item,
                    (subtitleKey == null || subtitleKey.isEmpty)
                        ? 'subtitle'
                        : subtitleKey,
                  ).trim();

                  final formattedSubtitle =
                      formatMaybeDateSubtitle(itemSubtitle);

                  final stable = stableKeyForItem(item, index);
                  final key = ValueKey<String>(
                    stable == null ? 'item_index:$index' : 'item:$stable',
                  );

                  return SchemaDataScope(
                    key: key,
                    data: dataScope?.data,
                    item: item,
                    index: index,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: EdgeInsets.only(left: paddingLeft),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  itemTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: titleStyle,
                                ),
                              ),
                              SizedBox(width: rowSpacing),
                              Flexible(
                                child: Text(
                                  formattedSubtitle,
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  style: subtitleStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (index < itemsList.length - 1)
                          SizedBox(height: itemGap),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        }

        if (!isStateItemsPath) return buildPanel();

        final store = SchemaStateScope.maybeOf(buildContext);
        if (store == null) {
          return const UnknownSchemaWidget(
            componentName: 'StatusTimelinePanel(missing-state-scope)',
          );
        }

        return AnimatedBuilder(
          animation: store,
          builder: (_, __) => buildPanel(),
        );
      },
    );
  });
}
