import 'package:flutter/widgets.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'pharmacy_request_detail_cart_item_widget.dart';

void registerPharmacyRequestDetailCartItemSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('PharmacyRequestDetailCartItem', (node, _) {
    final titleTemplate = (node.props['title'] as String?)?.trim() ?? '';
    final unitPriceTemplate =
        (node.props['unitPriceText'] as String?)?.trim() ?? '';
    final rxRequiredTemplate = (node.props['rxRequired'] as String?)?.trim();
    final density = (node.props['density'] as String?)?.trim() ?? 'compact';
    final surface = (node.props['surface'] as String?)?.trim() ?? 'flat';
    final quantityRaw = node.props['quantity'];

    int resolveQuantity(BuildContext buildContext) {
      final rawValue = switch (quantityRaw) {
        String value => interpolateSchemaString(value, buildContext).trim(),
        _ => quantityRaw,
      };

      if (rawValue is num) return rawValue.toInt();
      return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
    }

    bool resolveRxRequired(BuildContext buildContext) {
      if (rxRequiredTemplate == null || rxRequiredTemplate.isEmpty)
        return false;
      final val = interpolateSchemaString(
        rxRequiredTemplate,
        buildContext,
      ).trim().toLowerCase();
      return val == 'true' || val == '1';
    }

    Widget buildItem(BuildContext buildContext) {
      final title = interpolateSchemaString(titleTemplate, buildContext).trim();
      final unitPriceText = interpolateSchemaString(
        unitPriceTemplate,
        buildContext,
      ).trim();

      return PharmacyRequestDetailCartItemWidget(
        title: title,
        quantity: resolveQuantity(buildContext),
        unitPriceText: unitPriceText,
        rxRequired: resolveRxRequired(buildContext),
        surface: surface,
        density: density,
      );
    }

    return Builder(
      builder: (buildContext) {
        final store = SchemaStateScope.maybeOf(buildContext);
        final needsReactive =
            store != null &&
            [
              titleTemplate,
              unitPriceTemplate,
              if (quantityRaw is String) quantityRaw,
              if (rxRequiredTemplate != null) rxRequiredTemplate,
            ].any(hasSchemaInterpolation);

        if (needsReactive) {
          return AnimatedBuilder(
            animation: store,
            builder: (ctx, __) => buildItem(ctx),
          );
        }

        return buildItem(buildContext);
      },
    );
  });
}
