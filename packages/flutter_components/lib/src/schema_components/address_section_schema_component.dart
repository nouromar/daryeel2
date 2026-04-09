import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import '../location/address_picker_screen.dart';
import '../location/location_value.dart';
import 'schema_component_context.dart';

void registerAddressSectionSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('AddressSection', (node, _) {
    return _AddressSectionWidget(node: node, context: context);
  });
}

final class _AddressSectionWidget extends StatefulWidget {
  const _AddressSectionWidget({required this.node, required this.context});

  final ComponentNode node;
  final SchemaComponentContext context;

  @override
  State<_AddressSectionWidget> createState() => _AddressSectionWidgetState();
}

class _AddressSectionWidgetState extends State<_AddressSectionWidget> {
  bool _initializedDefault = false;

  String? _stateKeyFromBind(String rawBind) {
    const statePrefixDot = r'$state.';
    const statePrefixColon = r'$state:';

    final trimmed = rawBind.trim();
    if (trimmed.startsWith(statePrefixDot)) {
      return trimmed.substring(statePrefixDot.length).trim();
    }
    if (trimmed.startsWith(statePrefixColon)) {
      return trimmed.substring(statePrefixColon.length).trim();
    }
    return null;
  }

  bool _asBool(Object? raw, {required bool defaultValue}) {
    if (raw is bool) return raw;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    return defaultValue;
  }

  String? _asString(Object? raw) {
    final v = raw;
    if (v is String) {
      final trimmed = v.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return null;
  }

  AddressPickerSources _sourcesFromProps(Map<String, Object?> props) {
    final raw = props['sources'];
    final sources = (raw is Map) ? raw : const <Object?, Object?>{};

    bool getBool(String key, bool defaultValue) =>
        _asBool(sources[key], defaultValue: defaultValue);

    return AddressPickerSources(
      defaultAddress: getBool('defaultAddress', true),
      currentLocation: getBool('currentLocation', true),
      providerAutocomplete: getBool('providerAutocomplete', false),
      savedPlaces: getBool('savedPlaces', true),
      recents: getBool('recents', true),
      manualEntry: getBool('manualEntry', true),
      mapPin: getBool('mapPin', false),
    );
  }

  AddressAutocompleteConfig? _autocompleteFromProps(
    Map<String, Object?> props,
    String resolvedKey,
  ) {
    final raw = props['autocomplete'];
    if (raw is! Map) return null;

    final obj =
        raw.map((k, v) => MapEntry(k.toString(), v)).cast<String, Object?>();

    final path = _asString(obj['path']);
    if (path == null) return null;

    final queryParam = _asString(obj['queryParam']) ?? 'q';
    final dataPath = _asString(obj['dataPath']);

    final staticParamsRaw = obj['params'];
    final staticParams = <String, String>{};
    if (staticParamsRaw is Map) {
      for (final entry in staticParamsRaw.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if (v == null) continue;
        staticParams[k] = v.toString();
      }
    }

    final queryKey =
        _asString(obj['key']) ?? 'address_autocomplete:$resolvedKey';

    return AddressAutocompleteConfig(
      path: path,
      queryParam: queryParam,
      dataPath: dataPath,
      staticParams: staticParams,
      queryKey: queryKey,
    );
  }

  String _recentsKeyFor(String key) => '${key}Recents';

  List<LocationValue> _readLocationList(SchemaStateStore store, String key) {
    final raw = store.getValue(key);
    if (raw is! List) return const <LocationValue>[];

    final out = <LocationValue>[];
    for (final item in raw) {
      final coerced = coerceLocationValue(item);
      if (coerced == null) continue;
      out.add(coerced);
    }
    return out;
  }

  List<LocationValue> _readSavedPlaces(
    SchemaStateStore store,
    Map<String, Object?> props,
  ) {
    final bind = _asString(props['savedPlacesBind']);
    if (bind == null) return const <LocationValue>[];

    final key = _stateKeyFromBind(bind);
    if (key == null || key.isEmpty) return const <LocationValue>[];

    return _readLocationList(store, key);
  }

  LocationValue? _readBoundValue(SchemaStateStore store, String resolvedKey) {
    return coerceLocationValue(store.getValue(resolvedKey));
  }

  LocationValue? _readOptionalBound(SchemaStateStore store, String? bind) {
    if (bind == null || bind.isEmpty) return null;
    final key = _stateKeyFromBind(bind);
    if (key == null || key.isEmpty) return null;
    return coerceLocationValue(store.getValue(key));
  }

  void _maybeInitializeDefault(
      SchemaStateStore store, Map<String, Object?> props, String resolvedKey) {
    if (_initializedDefault) return;
    _initializedDefault = true;

    final current = _readBoundValue(store, resolvedKey);
    if (locationText(current).isNotEmpty) return;

    final sources = _sourcesFromProps(props);

    final autoSelectDefault =
        _asBool(props['autoSelectDefault'], defaultValue: true);
    final autoSelectCurrent =
        _asBool(props['autoSelectCurrentLocation'], defaultValue: true);

    final defaultAddress = sources.defaultAddress
        ? _readOptionalBound(store, _asString(props['defaultAddressBind']))
        : null;
    if (autoSelectDefault &&
        defaultAddress != null &&
        locationText(defaultAddress).isNotEmpty) {
      store.setValue(resolvedKey, defaultAddress);
      return;
    }

    final currentLocation = sources.currentLocation
        ? _readOptionalBound(store, _asString(props['currentLocationBind']))
        : null;
    if (autoSelectCurrent &&
        currentLocation != null &&
        locationText(currentLocation).isNotEmpty) {
      store.setValue(resolvedKey, currentLocation);
    }
  }

  void _writeRecents(
    SchemaStateStore store,
    String resolvedKey,
    LocationValue picked,
  ) {
    final recentsKey = _recentsKeyFor(resolvedKey);
    final existing = _readLocationList(store, recentsKey);

    final pickedText = locationText(picked);

    final next = <Object?>[];
    if (pickedText.isNotEmpty) next.add(picked);

    for (final r in existing) {
      final rText = locationText(r);
      if (rText.isEmpty) continue;
      if (pickedText.isNotEmpty &&
          rText.toLowerCase() == pickedText.toLowerCase()) {
        continue;
      }
      next.add(r);
      if (next.length >= 5) break;
    }

    store.setValue(recentsKey, next);
  }

  Future<void> _openPicker({
    required SchemaStateStore store,
    required String resolvedKey,
    required Map<String, Object?> props,
    required String title,
    required String currentText,
  }) async {
    final sources = _sourcesFromProps(props);

    final defaultAddress = sources.defaultAddress
        ? _readOptionalBound(store, _asString(props['defaultAddressBind']))
        : null;

    final currentLocation = sources.currentLocation
        ? _readOptionalBound(store, _asString(props['currentLocationBind']))
        : null;

    final savedPlaces = sources.savedPlaces
        ? _readSavedPlaces(store, props)
        : const <LocationValue>[];

    final recents = sources.recents
        ? _readLocationList(store, _recentsKeyFor(resolvedKey))
        : const <LocationValue>[];

    final autocomplete = _autocompleteFromProps(props, resolvedKey);

    final picked = await Navigator.of(context).push<LocationValue>(
      MaterialPageRoute<LocationValue>(
        builder: (_) => AddressPickerScreen(
          title: title,
          initialQuery: currentText,
          recents: recents,
          defaultAddress: defaultAddress,
          currentLocation: currentLocation,
          savedPlaces: savedPlaces,
          sources: sources,
          autocomplete: autocomplete,
        ),
      ),
    );

    if (picked == null) return;

    store.setValue(resolvedKey, picked);
    _writeRecents(store, resolvedKey, picked);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;

    final title = (_asString(node.props['title']) ?? 'Delivery address');
    final variantRaw =
        (_asString(node.props['variant']) ?? 'default').toLowerCase();

    final rawBind = node.bind;
    if (rawBind == null || rawBind.trim().isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'AddressSection(missing-bind)',
      );
    }

    final resolvedKey = _stateKeyFromBind(rawBind);
    if (resolvedKey == null || resolvedKey.isEmpty) {
      return const UnknownSchemaWidget(
        componentName: 'AddressSection(bind-not-state)',
      );
    }

    final store = SchemaStateScope.maybeOf(context);
    if (store == null) {
      return const UnknownSchemaWidget(
        componentName: 'AddressSection(missing-state-scope)',
      );
    }

    _maybeInitializeDefault(store, node.props, resolvedKey);

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final value = _readBoundValue(store, resolvedKey);
        final text = locationText(value);
        final hasValue = text.isNotEmpty;

        final labelText = title;
        final valueText = hasValue ? text : 'Add delivery address';
        final isCompact = variantRaw == 'compact';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
              child: Text(
                labelText,
                style: (isCompact
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium)
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Card(
              elevation: 0,
              child: ListTile(
                dense: isCompact,
                visualDensity:
                    isCompact ? VisualDensity.compact : VisualDensity.standard,
                leading: Icon(
                  hasValue ? Icons.place : Icons.location_on_outlined,
                ),
                title: Text(
                  valueText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: hasValue
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPicker(
                  store: store,
                  resolvedKey: resolvedKey,
                  props: node.props,
                  title: title,
                  currentText: text,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
