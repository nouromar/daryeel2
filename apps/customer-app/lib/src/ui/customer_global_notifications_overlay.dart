import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import '../auth/customer_auth_store.dart';

/// Shell-level global notifications overlay.
///
/// - Pure Flutter (not schema-driven)
/// - Auth-aware (hide when unauthenticated)
/// - Only shows when the notifications API returns `activeCount > 0`
final class CustomerGlobalNotificationsOverlay extends StatefulWidget {
  const CustomerGlobalNotificationsOverlay({
    super.key,
    required this.authState,
  });

  final ValueListenable<CustomerAuthState> authState;

  static const String _queryKey = 'customer.global_notifications.home_summary';
  static const String _path = '/v1/notifications/home-summary';

  @override
  State<CustomerGlobalNotificationsOverlay> createState() =>
      _CustomerGlobalNotificationsOverlayState();
}

class _CustomerGlobalNotificationsOverlayState
    extends State<CustomerGlobalNotificationsOverlay>
    with WidgetsBindingObserver {
  SchemaQueryStore? _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = SchemaQueryScope.maybeOf(context);
    if (store == _store) return;
    _store = store;

    // Best-effort prefetch; the widget stays invisible if this fails.
    _refresh(force: false);
  }

  @override
  void didUpdateWidget(covariant CustomerGlobalNotificationsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authState != widget.authState) {
      _refresh(force: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(force: true);
    }
  }

  Future<void> _refresh({required bool force}) async {
    final store = _store;
    if (store == null) return;

    // Avoid doing anything until authenticated.
    if (!widget.authState.value.isAuthenticated) return;

    // In tests / misconfigured environments, API base URL may be empty.
    if (store.apiBaseUrl.trim().isEmpty) return;

    try {
      await store.executeGet(
        key: CustomerGlobalNotificationsOverlay._queryKey,
        path: CustomerGlobalNotificationsOverlay._path,
        forceRefresh: force,
      );
    } catch (_) {
      // SchemaQueryStore is defensive, but be extra safe: never throw from an overlay.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CustomerAuthState>(
      valueListenable: widget.authState,
      builder: (context, auth, _) {
        if (!auth.isAuthenticated) return const SizedBox.shrink();

        final store = SchemaQueryScope.maybeOf(context);
        if (store == null) return const SizedBox.shrink();

        return ValueListenableBuilder<SchemaQuerySnapshot>(
          valueListenable: store.watchQuery(
            CustomerGlobalNotificationsOverlay._queryKey,
          ),
          builder: (context, snapshot, _) {
            if (!snapshot.hasData) {
              // Keep the shell clean: no loading state or error UI.
              if (kDebugMode && snapshot.hasError) {
                // Still render nothing, but allow a convenient refresh on tap in debug.
              }
              return const SizedBox.shrink();
            }

            final raw = snapshot.data;
            if (raw is! Map) return const SizedBox.shrink();

            final activeCount = _coerceInt(raw['activeCount']) ?? 0;
            if (activeCount <= 0) return const SizedBox.shrink();

            final primaryRaw = raw['primary'];
            final primary = (primaryRaw is Map) ? primaryRaw : null;
            if (primary == null) return const SizedBox.shrink();

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
            final showServiceChips = moreCount > 0 && moreByService.isNotEmpty;

            Future<void> onPrimaryTap() async {
              if (route == null || route.trim().isEmpty) return;
              try {
                await Navigator.of(
                  context,
                ).pushNamed(route, arguments: routeValue);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Navigation failed: $error')),
                );
              }
            }

            Future<void> onViewAllTap() async {
              try {
                await Navigator.of(context).pushNamed(
                  'customer.schema_screen',
                  arguments: const <String, Object?>{
                    'screenId': 'customer_activities',
                    'title': 'Activities',
                  },
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Navigation failed: $error')),
                );
              }
            }

            final effectiveTitle = title.isEmpty ? 'Updates' : title;

            final theme = Theme.of(context);
            final scheme = theme.colorScheme;

            final baseSurface = scheme.surface;
            final variantSurface = scheme.surfaceVariant;
            final cardBackground = (variantSurface.value != baseSurface.value)
                ? variantSurface
                : Color.alphaBlend(
                    scheme.primary.withOpacity(0.10),
                    baseSurface,
                  );

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                color: cardBackground,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: scheme.outlineVariant.withOpacity(0.35),
                    width: 1,
                  ),
                ),
                child: InkWell(
                  onTap: (route == null || route.trim().isEmpty)
                      ? null
                      : onPrimaryTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (iconName.isNotEmpty) ...[
                          Icon(_resolveIcon(iconName), size: 20),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            '$effectiveTitle · $activeCount',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (showServiceChips)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: TextButton(
                              onPressed: onViewAllTap,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('All'),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
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
