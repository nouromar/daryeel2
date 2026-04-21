import 'package:flutter/material.dart';
import 'package:flutter_components/flutter_components.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

void registerCustomerHomeNotificationsSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('CustomerHomeNotifications', (node, _) {
    return Builder(
      builder: (buildContext) {
        final dataScope = SchemaDataScope.maybeOf(buildContext);
        final raw = dataScope?.data;

        if (raw == null) {
          return const UnknownSchemaWidget(
            componentName: 'CustomerHomeNotifications(missing-data)',
          );
        }

        if (raw is! Map) {
          return const UnknownSchemaWidget(
            componentName: 'CustomerHomeNotifications(data-not-map)',
          );
        }

        final primaryRaw = raw['primary'];
        final primary = (primaryRaw is Map) ? primaryRaw : null;
        if (primary == null) {
          return const SizedBox.shrink();
        }

        final title = (primary['title'] as String?)?.trim() ?? '';
        final subtitle = (primary['subtitle'] as String?)?.trim() ?? '';
        final iconName = (primary['icon'] as String?)?.trim() ?? '';

        final routeRaw = primary['route'];
        final String? route;
        final Object? routeValue;
        if (routeRaw is String) {
          route = routeRaw;
          routeValue = null;
        } else if (routeRaw is Map) {
          final dynamic name = routeRaw['route'] ?? routeRaw['name'];
          route = name is String ? name : null;
          routeValue =
              routeRaw['value'] ?? routeRaw['args'] ?? routeRaw['params'];
        } else {
          route = null;
          routeValue = null;
        }

        final moreCount = _coerceInt(raw['moreCount']) ?? 0;
        final moreByService = _coerceStringIntMap(raw['moreByService']);

        Future<void> onPrimaryTap() async {
          if (route == null || route.trim().isEmpty) return;
          try {
            await context.actionDispatcher.dispatch(
              buildContext,
              ActionDefinition(
                type: SchemaActionTypes.navigate,
                route: route,
                value: routeValue,
              ),
            );
          } catch (error) {
            if (!buildContext.mounted) return;
            ScaffoldMessenger.of(buildContext).showSnackBar(
              SnackBar(content: Text('Navigation failed: $error')),
            );
          }
        }

        Future<void> onViewAllTap() async {
          try {
            await context.actionDispatcher.dispatch(
              buildContext,
              const ActionDefinition(
                type: SchemaActionTypes.navigate,
                route: 'customer.schema_screen',
                value: <String, Object?>{
                  'screenId': 'customer_activities',
                  'title': 'Activities',
                },
              ),
            );
          } catch (error) {
            if (!buildContext.mounted) return;
            ScaffoldMessenger.of(buildContext).showSnackBar(
              SnackBar(content: Text('Navigation failed: $error')),
            );
          }
        }

        final effectiveTitle = title.isEmpty ? 'Updates' : title;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionCardWidget(
              title: effectiveTitle,
              subtitle: subtitle,
              icon: iconName.isEmpty ? null : _resolveIcon(iconName),
              surface: 'raised',
              density: 'comfortable',
              titleVariant: 'title',
              titleWeight: 'semibold',
              subtitleVariant: 'body',
              subtitleColor: 'muted',
              onTap: (route == null || route.trim().isEmpty)
                  ? null
                  : onPrimaryTap,
            ),
            if (moreCount > 0) ...[
              const SizedBox(height: 10),
              _ActiveSummaryChips(
                moreCount: moreCount,
                moreByService: moreByService,
                onTap: onViewAllTap,
              ),
            ],
          ],
        );
      },
    );
  });
}

final class _ActiveSummaryChips extends StatelessWidget {
  const _ActiveSummaryChips({
    required this.moreCount,
    required this.moreByService,
    required this.onTap,
  });

  final int moreCount;
  final Map<String, int> moreByService;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final topServices = moreByService.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final chips = <Widget>[
      _chip(context, label: '+$moreCount more', onPressed: onTap),
    ];

    for (final entry in topServices.take(2)) {
      final label = _serviceLabel(entry.key);
      chips.add(
        _chip(context, label: '$label ${entry.value}', onPressed: onTap),
      );
    }

    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 0),
      ),
      child: Text(label),
    );
  }
}

int? _coerceInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}');
}

Map<String, int> _coerceStringIntMap(Object? value) {
  if (value is! Map) return const <String, int>{};

  final out = <String, int>{};
  for (final entry in value.entries) {
    final key = '${entry.key}'.trim();
    if (key.isEmpty) continue;

    final v = _coerceInt(entry.value) ?? 0;
    if (v <= 0) continue;

    out[key] = v;
  }
  return out;
}

String _serviceLabel(String raw) {
  final key = raw.trim().toLowerCase();
  return switch (key) {
    'pharmacy' => 'Pharmacy',
    'home_visit' || 'home' => 'Home visit',
    'ambulance' => 'Ambulance',
    _ => raw.trim().isEmpty ? 'Service' : raw.trim(),
  };
}

IconData _resolveIcon(String raw) {
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) return Icons.circle_outlined;

  // Keep this in sync with the core Icon component vocabulary.
  return switch (key) {
    'ambulance' ||
    'local_hospital' ||
    'hospital' => Icons.local_hospital_outlined,
    'home' || 'house' || 'home_visit' => Icons.home_outlined,
    'pharmacy' || 'local_pharmacy' || 'pill' => Icons.local_pharmacy_outlined,
    'history' => Icons.history,
    _ => Icons.circle_outlined,
  };
}
