import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_runtime/flutter_runtime.dart';

import 'location_value.dart';
import 'map_pin_picker_screen.dart';

final class AddressPickerScreen extends StatefulWidget {
  const AddressPickerScreen({
    super.key,
    required this.title,
    required this.initialQuery,
    required this.recents,
    required this.defaultAddress,
    required this.currentLocation,
    required this.savedPlaces,
    required this.sources,
    required this.autocomplete,
  });

  final String title;
  final String initialQuery;
  final List<LocationValue> recents;
  final LocationValue? defaultAddress;
  final LocationValue? currentLocation;
  final List<LocationValue> savedPlaces;

  /// Enabled/disabled location sources.
  final AddressPickerSources sources;

  /// Autocomplete config (optional).
  final AddressAutocompleteConfig? autocomplete;

  @override
  State<AddressPickerScreen> createState() => _AddressPickerScreenState();
}

final class AddressPickerSources {
  const AddressPickerSources({
    this.defaultAddress = true,
    this.currentLocation = true,
    this.providerAutocomplete = false,
    this.savedPlaces = true,
    this.recents = true,
    this.manualEntry = true,
    this.mapPin = false,
  });

  final bool defaultAddress;
  final bool currentLocation;
  final bool providerAutocomplete;
  final bool savedPlaces;
  final bool recents;
  final bool manualEntry;
  final bool mapPin;
}

final class AddressAutocompleteConfig {
  const AddressAutocompleteConfig({
    required this.path,
    this.queryParam = 'q',
    this.dataPath,
    this.staticParams = const <String, String>{},
    this.queryKey,
  });

  final String path;
  final String queryParam;
  final String? dataPath;
  final Map<String, String> staticParams;

  /// Optional explicit query key; otherwise derived.
  final String? queryKey;
}

class _AddressPickerScreenState extends State<AddressPickerScreen> {
  static const _debounceDuration = Duration(milliseconds: 250);

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  Timer? _debounceTimer;
  bool _isLocating = false;

  String get _query => _controller.text.trim();

  String _queryKey(AddressAutocompleteConfig config) {
    final explicit = config.queryKey?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return 'address_autocomplete:${widget.title.toLowerCase()}';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _select(LocationValue value) {
    Navigator.of(context).pop<LocationValue>(value);
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatPlacemark(Placemark p) {
    final parts = <String>[];

    void add(String? v) {
      final t = v?.trim();
      if (t == null || t.isEmpty) return;
      if (parts.contains(t)) return;
      parts.add(t);
    }

    add(p.name);
    add(p.street);
    add(p.subLocality);
    add(p.locality);
    add(p.administrativeArea);
    add(p.country);

    return parts.join(', ');
  }

  Future<void> _pickCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Location services are disabled.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        _showMessage('Location permission denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Location permission permanently denied in Settings.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      var text = 'Current location';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final formatted = _formatPlacemark(placemarks.first);
          if (formatted.trim().isNotEmpty) text = formatted;
        }
      } catch (_) {
        // Best-effort only.
      }

      _select(<String, Object?>{
        'text': text,
        'lat': position.latitude,
        'lng': position.longitude,
        'source': 'current_location',
      });
    } catch (e) {
      _showMessage('Could not get current location.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickOnMap({required String initialText}) async {
    final picked = await showModalBottomSheet<LocationValue>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height;
        return SizedBox(
          height: height * 0.85,
          child: MapPinPickerScreen(
            title: 'Pick a location',
            initialText: initialText,
          ),
        );
      },
    );
    if (picked == null) return;
    _select(picked);
  }

  void _scheduleAutocomplete(
      AddressAutocompleteConfig config, SchemaQueryStore store) {
    final query = _query;
    if (query.isEmpty) return;

    _debounceTimer?.cancel();

    _debounceTimer = Timer(_debounceDuration, () {
      if (!mounted) return;
      final params = <String, String>{
        ...config.staticParams,
        config.queryParam: query
      };
      // ignore: discarded_futures
      store.executeGet(
        key: _queryKey(config),
        path: config.path,
        params: params,
        forceRefresh: true,
      );
    });
  }

  List<LocationValue> _coerceSuggestionList(Object? raw) {
    if (raw is! List) return const <LocationValue>[];

    final out = <LocationValue>[];
    for (final item in raw) {
      if (item is String) {
        out.add(buildManualLocationValue(item));
        continue;
      }
      final asMap = coerceLocationValue(item);
      if (asMap == null) continue;
      out.add(asMap);
    }
    return out;
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(title, style: Theme.of(context).textTheme.labelLarge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final query = _query;

    final sources = widget.sources;
    final defaultAddress = widget.defaultAddress;
    final savedPlaces = widget.savedPlaces;
    final recents = widget.recents;

    final showManual = sources.manualEntry && query.isNotEmpty;

    final queryStore = SchemaQueryScope.maybeOf(context);
    final autocomplete = widget.autocomplete;

    final canAutocomplete = sources.providerAutocomplete &&
        autocomplete != null &&
        queryStore != null;

    if (canAutocomplete) {
      _scheduleAutocomplete(autocomplete, queryStore);
    }

    final suggestionsListenable =
        canAutocomplete ? queryStore.watchQuery(_queryKey(autocomplete)) : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Search address',
                hintText: 'Type your area, street, or landmark',
                border: const OutlineInputBorder(),
                suffixIcon: sources.mapPin
                    ? IconButton(
                        tooltip: 'Pick on map',
                        icon: const Icon(Icons.place_outlined),
                        onPressed: () => _pickOnMap(initialText: query),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (value) {
                final trimmed = value.trim();
                if (trimmed.isEmpty) return;
                if (!sources.manualEntry) return;
                _select(buildManualLocationValue(trimmed));
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (sources.defaultAddress && defaultAddress != null)
                  ActionChip(
                    avatar: const Icon(Icons.home, size: 18),
                    label: const Text('Home'),
                    onPressed: () => _select(defaultAddress),
                  ),
                if (sources.currentLocation)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isLocating ? null : _pickCurrentLocation,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLocating)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(Icons.my_location, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          _isLocating ? 'Locating…' : 'Use current location',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  if (showManual) ...[
                    ListTile(
                      leading: const Icon(Icons.edit_location_alt),
                      title: Text('Use "$query"'),
                      subtitle: const Text('Set this as your address'),
                      onTap: () => _select(buildManualLocationValue(query)),
                    ),
                    const Divider(height: 1),
                  ],
                  if (canAutocomplete && suggestionsListenable != null) ...[
                    ValueListenableBuilder<SchemaQuerySnapshot>(
                      valueListenable: suggestionsListenable,
                      builder: (context, snapshot, _) {
                        if (query.isEmpty) return const SizedBox.shrink();

                        if (snapshot.isLoading) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: const [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Searching...'),
                              ],
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              snapshot.errorMessage ?? 'Search error',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          );
                        }

                        final raw = readJsonPath(
                                snapshot.data, autocomplete.dataPath) ??
                            snapshot.data;
                        final suggestions = _coerceSuggestionList(raw);
                        if (suggestions.isEmpty) return const SizedBox.shrink();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle(context, 'Suggestions'),
                            for (final s in suggestions)
                              ListTile(
                                leading: const Icon(Icons.search),
                                title: Text(locationText(s).isEmpty
                                    ? 'Address'
                                    : locationText(s)),
                                onTap: () => _select(s),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  if (sources.savedPlaces && savedPlaces.isNotEmpty) ...[
                    _sectionTitle(context, 'Saved'),
                    for (final p in savedPlaces)
                      ListTile(
                        leading: const Icon(Icons.star_border),
                        title: Text(locationText(p).isEmpty
                            ? 'Place'
                            : locationText(p)),
                        onTap: () => _select(p),
                      ),
                  ],
                  if (sources.recents && recents.isNotEmpty) ...[
                    _sectionTitle(context, 'Recent'),
                    for (final r in recents)
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(locationText(r).isEmpty
                            ? 'Address'
                            : locationText(r)),
                        onTap: () => _select(r),
                      ),
                  ],
                  if ((sources.savedPlaces && savedPlaces.isEmpty) &&
                      (sources.recents && recents.isEmpty) &&
                      !(canAutocomplete && query.isNotEmpty) &&
                      !showManual)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No locations yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
