import 'package:flutter/widgets.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/cart_summary_widget.dart';
import 'schema_component_context.dart';

void registerCartSummarySchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('CartSummary', (node, componentRegistry) {
    final titleTemplate =
        (node.props['title'] as String?)?.trim() ?? 'Order summary';
    final linesPath = (node.props['linesPath'] as String?)?.trim();
    final totalPath = (node.props['totalPath'] as String?)?.trim();
    final surface = (node.props['surface'] as String?)?.trim() ?? 'raised';
    final density = (node.props['density'] as String?)?.trim() ?? 'comfortable';
    final hideZeroLines = node.props['hideZeroLines'] != false;

    const statePrefixDot = r'$state.';
    const statePrefixColon = r'$state:';

    bool isStatePath(String? path) {
      if (path == null || path.isEmpty) return false;
      return path.startsWith(statePrefixDot) ||
          path.startsWith(statePrefixColon);
    }

    String? toStateKey(String? path) {
      if (!isStatePath(path)) return null;
      if (path!.startsWith(statePrefixDot)) {
        return path.substring(statePrefixDot.length);
      }
      return path.substring(statePrefixColon.length);
    }

    Object? resolvePathValue(BuildContext buildContext, String? path) {
      if (path == null || path.isEmpty) return null;
      final stateKey = toStateKey(path);
      if (stateKey != null) {
        return SchemaStateScope.maybeOf(buildContext)?.getValue(stateKey);
      }

      final dataScope = SchemaDataScope.maybeOf(buildContext);
      final data = dataScope?.data ?? dataScope?.item;
      return readJsonPath(data, path);
    }

    double coerceAmount(Object? raw) {
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw.trim()) ?? 0.0;
      return 0.0;
    }

    CartSummaryRowData? coerceRow(Object? raw, {bool isTotal = false}) {
      if (raw is! Map) return null;

      final label =
          (raw['label'] ?? (isTotal ? 'Total' : '')).toString().trim();
      if (label.isEmpty) return null;

      final amount = coerceAmount(raw['amount']);
      final amountTextRaw = raw['amountText'];
      final amountText = (amountTextRaw?.toString().trim().isNotEmpty ?? false)
          ? amountTextRaw.toString().trim()
          : amount.toStringAsFixed(2);

      return CartSummaryRowData(
        label: label,
        amount: amount,
        amountText: amountText,
        kind: (raw['kind'] ?? (isTotal ? 'total' : 'default')).toString(),
        emphasis:
            (raw['emphasis'] ?? (isTotal ? 'strong' : 'normal')).toString(),
      );
    }

    Widget buildSummary(BuildContext buildContext) {
      final title = interpolateSchemaString(titleTemplate, buildContext).trim();
      final linesRaw = resolvePathValue(buildContext, linesPath);
      final totalRaw = resolvePathValue(buildContext, totalPath);

      final rows = <CartSummaryRowData>[];
      if (linesRaw is List) {
        for (final entry in linesRaw) {
          final row = coerceRow(entry);
          if (row != null) rows.add(row);
        }
      }

      return CartSummaryWidget(
        title: title,
        lines: rows,
        total: coerceRow(totalRaw, isTotal: true),
        surface: surface,
        density: density,
        hideZeroLines: hideZeroLines,
      );
    }

    return Builder(
      builder: (buildContext) {
        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive = store != null &&
            (hasSchemaInterpolation(titleTemplate) ||
                isStatePath(linesPath) ||
                isStatePath(totalPath));

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (_, __) => buildSummary(buildContext),
          );
        }

        return buildSummary(buildContext);
      },
    );
  });
}
