import 'package:flutter/material.dart';

import 'location_value.dart';

final class MapPinPickerScreen extends StatefulWidget {
  const MapPinPickerScreen({
    super.key,
    required this.title,
    required this.initialText,
  });

  final String title;
  final String initialText;

  @override
  State<MapPinPickerScreen> createState() => _MapPinPickerScreenState();
}

class _MapPinPickerScreenState extends State<MapPinPickerScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _textController = TextEditingController(
    text: widget.initialText,
  );

  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  double? _tryParseDouble(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final text = _textController.text.trim();
    final lat = _tryParseDouble(_latController.text);
    final lng = _tryParseDouble(_lngController.text);

    Navigator.of(context).pop<LocationValue>(<String, Object?>{
      'text': text,
      'lat': lat,
      'lng': lng,
      'accuracy_m': null,
      'place_id': null,
      'region_id': null,
      'source': 'map_pin',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Map pin picker is not yet connected to a map provider in this runtime.\n'
                'For now, you can enter coordinates (optional) and a label.',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _textController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'e.g. Near Hodan Market',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return 'Enter a label';
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Latitude (optional)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        if (raw.isEmpty) return null;
                        if (_tryParseDouble(raw) == null) return 'Invalid';
                        return null;
                      },
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true, signed: true),
                      decoration: const InputDecoration(
                        labelText: 'Longitude (optional)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        if (raw.isEmpty) return null;
                        if (_tryParseDouble(raw) == null) return 'Invalid';
                        return null;
                      },
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: const Text('Use this location'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
