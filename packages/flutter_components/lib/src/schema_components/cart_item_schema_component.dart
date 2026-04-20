import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../widgets/cart_item_widget.dart';
import 'schema_component_context.dart';

void registerCartItemSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('CartItem', (node, componentRegistry) {
    final titleTemplate = (node.props['title'] as String?)?.trim() ?? '';
    final subtitleTemplate = (node.props['subtitle'] as String?)?.trim() ?? '';
    final unitPriceTemplate = (node.props['unitPriceText'] as String?)?.trim();
    final lineTotalTemplate = (node.props['lineTotalText'] as String?)?.trim();
    final badgeTemplate = (node.props['badgeLabel'] as String?)?.trim();
    final rxRequiredTemplate = (node.props['rxRequired'] as String?)?.trim();
    final surface = (node.props['surface'] as String?)?.trim() ?? 'raised';
    final density = (node.props['density'] as String?)?.trim() ?? 'comfortable';
    final readonly = (node.props['readonly'] as bool?) ?? false;
    final quantityRaw = node.props['quantity'];

    final incrementAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'increment',
    );
    final decrementAction = resolveComponentAction(
      screen: context.screen,
      node: node,
      actionKey: 'decrement',
    );

    int resolveQuantity(BuildContext buildContext) {
      final rawValue = switch (quantityRaw) {
        String value => interpolateSchemaString(value, buildContext).trim(),
        _ => quantityRaw,
      };

      if (rawValue is num) return rawValue.toInt();
      return int.tryParse('${rawValue ?? ''}'.trim()) ?? 0;
    }

    String? resolveOptionalTemplate(
        String? template, BuildContext buildContext) {
      if (template == null || template.isEmpty) return null;
      final value = interpolateSchemaString(template, buildContext).trim();
      return value.isEmpty ? null : value;
    }

    bool resolveRxRequired(BuildContext buildContext) {
      if (rxRequiredTemplate == null || rxRequiredTemplate.isEmpty) return false;
      final val =
          interpolateSchemaString(rxRequiredTemplate, buildContext).trim().toLowerCase();
      return val == 'true' || val == '1';
    }

    Widget buildItem(BuildContext buildContext) {
      final title = interpolateSchemaString(titleTemplate, buildContext).trim();
      final subtitle =
          interpolateSchemaString(subtitleTemplate, buildContext).trim();

      Future<void> dispatch(String actionKey) async {
        final result = await tryDispatchComponentAction(
          context: buildContext,
          screen: context.screen,
          node: node,
          actionKey: actionKey,
          dispatcher: context.actionDispatcher,
          diagnostics: context.diagnostics,
          diagnosticsContext: context.diagnosticsContext,
        );

        final failure = result.failure;
        if (failure == null) return;
        if (!buildContext.mounted) return;

        ScaffoldMessenger.of(buildContext).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
      }

      return CartItemWidget(
        title: title,
        subtitle: subtitle,
        quantity: resolveQuantity(buildContext),
        unitPriceText: resolveOptionalTemplate(unitPriceTemplate, buildContext),
        lineTotalText: resolveOptionalTemplate(lineTotalTemplate, buildContext),
        badgeLabel: resolveOptionalTemplate(badgeTemplate, buildContext),
        rxRequired: resolveRxRequired(buildContext),
        surface: surface,
        density: density,
        readonly: readonly,
        onIncrement: readonly || incrementAction == null
            ? null
            : () => dispatch('increment'),
        onDecrement: readonly || decrementAction == null
            ? null
            : () => dispatch('decrement'),
      );
    }

    final store = Builder(
      builder: (buildContext) {
        final stateStore = SchemaStateScope.maybeOf(buildContext);
        final needsReactive = stateStore != null &&
            [
              titleTemplate,
              subtitleTemplate,
              if (quantityRaw is String) quantityRaw,
              if (unitPriceTemplate != null) unitPriceTemplate,
              if (lineTotalTemplate != null) lineTotalTemplate,
              if (badgeTemplate != null) badgeTemplate,
              if (rxRequiredTemplate != null) rxRequiredTemplate,
            ].any(hasSchemaInterpolation);

        if (needsReactive) {
          return AnimatedBuilder(
            animation: stateStore,
            builder: (ctx, __) => buildItem(ctx),
          );
        }

        return buildItem(buildContext);
      },
    );

    return store;
  });
}
