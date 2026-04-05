import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A simple, bounded form state store for schema-driven UI.
///
/// The runtime uses this store to collect bound field values and attach
/// submission/validation state.
class SchemaFormStore extends ChangeNotifier {
  SchemaFormStore({
    this.maxFieldsPerForm = 200,
    this.maxStringLength = 4 * 1024,
    this.maxEnumValues = 200,
    this.maxPatternLength = 512,
    this.maxJsonDepth = 8,
    this.maxJsonNodes = 800,
    this.maxJsonEntriesPerMap = 80,
    this.maxJsonItemsPerList = 200,
    this.maxJsonKeyLength = 80,
  });

  final int maxFieldsPerForm;
  final int maxStringLength;
  final int maxEnumValues;
  final int maxPatternLength;

  /// Budgets for structured JSON-like values stored in form state.
  ///
  /// These enable schema components to bind richer values (e.g. locations)
  /// while preventing untrusted schemas from pushing arbitrarily large
  /// structures into memory.
  final int maxJsonDepth;
  final int maxJsonNodes;
  final int maxJsonEntriesPerMap;
  final int maxJsonItemsPerList;
  final int maxJsonKeyLength;

  final Map<String, _SchemaFormState> _forms = <String, _SchemaFormState>{};

  /// Registers (or replaces) validation rules for a single field.
  ///
  /// A field can be registered multiple times; the most recent rules win.
  ///
  /// Validation itself is run by [validateField] / [validateForm].
  void registerFieldValidation(
    String formId,
    String fieldKey,
    SchemaFieldValidationRules? rules,
  ) {
    if (formId.isEmpty || fieldKey.isEmpty) return;
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    if (rules == null) {
      state.validationRules.remove(fieldKey);
      return;
    }
    state.validationRules[fieldKey] = rules._normalized(
      maxEnumValues: maxEnumValues,
      maxPatternLength: maxPatternLength,
    );
  }

  /// Validates a single field against its registered rules.
  ///
  /// Returns `true` if valid.
  bool validateField(String formId, String fieldKey) {
    if (formId.isEmpty || fieldKey.isEmpty) return true;
    final state = _forms[formId];
    if (state == null) return true;

    final rules = state.validationRules[fieldKey];
    if (rules == null) return true;

    final value = state.values[fieldKey];
    final error = rules.validate(value);
    _setFieldErrorInternal(formId, fieldKey, error);
    return error == null;
  }

  /// Validates all registered fields in a form.
  ///
  /// Returns `true` if the form is valid.
  bool validateForm(String formId) {
    if (formId.isEmpty) return true;
    final state = _forms[formId];
    if (state == null) return true;

    var isValid = true;
    for (final entry in state.validationRules.entries) {
      final fieldKey = entry.key;
      final error = entry.value.validate(state.values[fieldKey]);
      _setFieldErrorInternal(formId, fieldKey, error);
      if (error != null) {
        isValid = false;
      }
    }
    return isValid;
  }

  /// Watches a single field value for reactive UI bindings.
  ///
  /// This returns a stable [ValueListenable] per (formId, fieldKey) pair.
  ValueListenable<Object?> watchFieldValue(String formId, String fieldKey) {
    if (formId.isEmpty || fieldKey.isEmpty) {
      return ValueNotifier<Object?>(null);
    }
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    return state.valueNotifiers.putIfAbsent(
      fieldKey,
      () => ValueNotifier<Object?>(state.values[fieldKey]),
    );
  }

  /// Watches a single field error message for reactive UI bindings.
  ValueListenable<String?> watchFieldError(String formId, String fieldKey) {
    if (formId.isEmpty || fieldKey.isEmpty) {
      return ValueNotifier<String?>(null);
    }
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    return state.errorNotifiers.putIfAbsent(
      fieldKey,
      () => ValueNotifier<String?>(state.fieldErrors[fieldKey]),
    );
  }

  /// Watches whether the form is currently submitting.
  ValueListenable<bool> watchSubmitting(String formId) {
    if (formId.isEmpty) {
      return ValueNotifier<bool>(false);
    }
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    return state.submittingNotifier;
  }

  SchemaFormSnapshot snapshot(String formId) {
    final state = _forms[formId];
    if (state == null) {
      return SchemaFormSnapshot(
        formId: formId,
        values: const <String, Object?>{},
        fieldErrors: const <String, String>{},
        isSubmitting: false,
      );
    }
    return SchemaFormSnapshot(
      formId: formId,
      values: Map<String, Object?>.unmodifiable(state.values),
      fieldErrors: Map<String, String>.unmodifiable(state.fieldErrors),
      isSubmitting: state.isSubmitting,
    );
  }

  void setFieldValue(String formId, String fieldKey, Object? value) {
    if (formId.isEmpty || fieldKey.isEmpty) return;

    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    if (state.values.length >= maxFieldsPerForm &&
        !state.values.containsKey(fieldKey)) {
      return;
    }

    final sanitized = _sanitizeValue(value);
    state.values[fieldKey] = sanitized;
    state.valueNotifiers[fieldKey]?.value = sanitized;

    // Clear existing error once user edits.
    if (state.fieldErrors.remove(fieldKey) != null) {
      state.errorNotifiers[fieldKey]?.value = null;
    }
    notifyListeners();
  }

  /// Sets or clears a single field error.
  void setFieldError(String formId, String fieldKey, String? error) {
    if (formId.isEmpty || fieldKey.isEmpty) return;
    _setFieldErrorInternal(formId, fieldKey, error);
  }

  Object? getFieldValue(String formId, String fieldKey) {
    return _forms[formId]?.values[fieldKey];
  }

  void setFieldErrors(String formId, Map<String, String> errors) {
    if (formId.isEmpty) return;
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    state.fieldErrors
      ..clear()
      ..addAll(errors);

    // Update reactive notifiers.
    for (final entry in state.errorNotifiers.entries) {
      entry.value.value = state.fieldErrors[entry.key];
    }
    notifyListeners();
  }

  void _setFieldErrorInternal(String formId, String fieldKey, String? error) {
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());

    if (error == null || error.isEmpty) {
      if (state.fieldErrors.remove(fieldKey) != null) {
        state.errorNotifiers[fieldKey]?.value = null;
        notifyListeners();
      }
      return;
    }

    final current = state.fieldErrors[fieldKey];
    if (current == error) return;
    state.fieldErrors[fieldKey] = error;
    state.errorNotifiers[fieldKey]?.value = error;
    notifyListeners();
  }

  void clearFieldErrors(String formId) {
    final state = _forms[formId];
    if (state == null) return;
    if (state.fieldErrors.isEmpty) return;
    state.fieldErrors.clear();

    for (final notifier in state.errorNotifiers.values) {
      notifier.value = null;
    }
    notifyListeners();
  }

  void setSubmitting(String formId, bool isSubmitting) {
    final state = _forms.putIfAbsent(formId, () => _SchemaFormState());
    if (state.isSubmitting == isSubmitting) return;
    state.isSubmitting = isSubmitting;
    state.submittingNotifier.value = isSubmitting;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final state in _forms.values) {
      state.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> snapshotValues(String formId) {
    final state = _forms[formId];
    if (state == null) return const <String, Object?>{};
    return Map<String, Object?>.unmodifiable(state.values);
  }

  Object? _sanitizeValue(Object? value) {
    if (value == null) return null;

    if (value is String) {
      if (value.length <= maxStringLength) return value;
      return value.substring(0, maxStringLength);
    }

    if (value is num || value is bool) return value;

    // Allow bounded JSON-like values (decoded Maps/Lists + primitives).
    if (value is Map || value is List) {
      final sanitizer = _JsonLikeSanitizer(
        maxDepth: maxJsonDepth,
        maxNodes: maxJsonNodes,
        maxEntriesPerMap: maxJsonEntriesPerMap,
        maxItemsPerList: maxJsonItemsPerList,
        maxKeyLength: maxJsonKeyLength,
        maxStringLength: maxStringLength,
      );
      final out = sanitizer.sanitize(value);
      if (out != null) return out;
    }

    // Fail-closed: do not accept arbitrary objects into form state.
    return value.toString();
  }
}

final class _JsonLikeSanitizer {
  _JsonLikeSanitizer({
    required this.maxDepth,
    required this.maxNodes,
    required this.maxEntriesPerMap,
    required this.maxItemsPerList,
    required this.maxKeyLength,
    required this.maxStringLength,
  }) : _remainingNodes = maxNodes;

  final int maxDepth;
  final int maxNodes;
  final int maxEntriesPerMap;
  final int maxItemsPerList;
  final int maxKeyLength;
  final int maxStringLength;

  int _remainingNodes;

  Object? sanitize(Object? value) => _sanitize(value, depth: 0);

  Object? _sanitize(Object? value, {required int depth}) {
    if (_remainingNodes <= 0) return null;
    if (depth > maxDepth) return null;

    if (value == null) {
      _remainingNodes -= 1;
      return null;
    }

    if (value is String) {
      _remainingNodes -= 1;
      if (value.length <= maxStringLength) return value;
      return value.substring(0, maxStringLength);
    }

    if (value is num || value is bool) {
      _remainingNodes -= 1;
      return value;
    }

    if (value is List) {
      _remainingNodes -= 1;
      final out = <Object?>[];
      final limit =
          value.length < maxItemsPerList ? value.length : maxItemsPerList;
      for (var i = 0; i < limit; i++) {
        final child = _sanitize(value[i], depth: depth + 1);
        out.add(child);
        if (_remainingNodes <= 0) break;
      }
      return out;
    }

    if (value is Map) {
      _remainingNodes -= 1;
      final out = <String, Object?>{};
      var added = 0;

      for (final entry in value.entries) {
        if (added >= maxEntriesPerMap) break;
        if (_remainingNodes <= 0) break;

        final rawKey = entry.key;
        if (rawKey is! String) continue;
        var key = rawKey.trim();
        if (key.isEmpty) continue;
        if (key.length > maxKeyLength) {
          key = key.substring(0, maxKeyLength);
        }

        final child = _sanitize(entry.value, depth: depth + 1);
        out[key] = child;
        added += 1;
      }

      return out;
    }

    // Not JSON-like.
    _remainingNodes -= 1;
    return value.toString();
  }
}

final class SchemaFormSnapshot {
  const SchemaFormSnapshot({
    required this.formId,
    required this.values,
    required this.fieldErrors,
    required this.isSubmitting,
  });

  final String formId;
  final Map<String, Object?> values;
  final Map<String, String> fieldErrors;
  final bool isSubmitting;
}

final class SchemaFormScope extends InheritedWidget {
  const SchemaFormScope({
    required this.store,
    required super.child,
    super.key,
  });

  final SchemaFormStore store;

  static SchemaFormStore? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SchemaFormScope>()?.store;
  }

  static SchemaFormStore of(BuildContext context) {
    final store = maybeOf(context);
    if (store == null) {
      throw StateError('SchemaFormScope not found in widget tree');
    }
    return store;
  }

  @override
  bool updateShouldNotify(SchemaFormScope oldWidget) =>
      store != oldWidget.store;
}

class _SchemaFormState {
  final Map<String, Object?> values = <String, Object?>{};
  final Map<String, String> fieldErrors = <String, String>{};
  final Map<String, SchemaFieldValidationRules> validationRules =
      <String, SchemaFieldValidationRules>{};
  bool isSubmitting = false;

  final Map<String, ValueNotifier<Object?>> valueNotifiers =
      <String, ValueNotifier<Object?>>{};
  final Map<String, ValueNotifier<String?>> errorNotifiers =
      <String, ValueNotifier<String?>>{};
  final ValueNotifier<bool> submittingNotifier = ValueNotifier<bool>(false);

  void dispose() {
    for (final n in valueNotifiers.values) {
      n.dispose();
    }
    for (final n in errorNotifiers.values) {
      n.dispose();
    }
    submittingNotifier.dispose();
  }
}

/// Field-level validation rules.
///
/// This is intentionally small and safe. Unknown keys in user-provided JSON
/// should be ignored by the caller when constructing these rules.
final class SchemaFieldValidationRules {
  const SchemaFieldValidationRules({
    this.required = false,
    this.minLength,
    this.maxLength,
    this.min,
    this.max,
    this.pattern,
    this.enumValues,
  });

  final bool required;
  final int? minLength;
  final int? maxLength;
  final num? min;
  final num? max;
  final String? pattern;
  final List<String>? enumValues;

  SchemaFieldValidationRules _normalized({
    required int maxEnumValues,
    required int maxPatternLength,
  }) {
    final normalizedEnum = enumValues == null
        ? null
        : enumValues!
            .where((e) => e.trim().isNotEmpty)
            .take(maxEnumValues)
            .toList(growable: false);

    final normalizedPattern = pattern == null
        ? null
        : (pattern!.length <= maxPatternLength
            ? pattern
            : pattern!.substring(0, maxPatternLength));

    return SchemaFieldValidationRules(
      required: required,
      minLength: minLength,
      maxLength: maxLength,
      min: min,
      max: max,
      pattern: normalizedPattern,
      enumValues: normalizedEnum,
    );
  }

  static SchemaFieldValidationRules? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final required = raw['required'] == true;

    int? asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    num? asNum(Object? v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    final minLength = asInt(raw['minLength']);
    final maxLength = asInt(raw['maxLength']);
    final min = asNum(raw['min']);
    final max = asNum(raw['max']);
    final pattern = raw['pattern'] as String?;

    List<String>? enumValues;
    final enumRaw = raw['enum'];
    if (enumRaw is List) {
      enumValues = enumRaw.whereType<String>().toList(growable: false);
    }

    if (!required &&
        minLength == null &&
        maxLength == null &&
        min == null &&
        max == null &&
        (pattern == null || pattern.isEmpty) &&
        (enumValues == null || enumValues.isEmpty)) {
      return null;
    }

    return SchemaFieldValidationRules(
      required: required,
      minLength: minLength,
      maxLength: maxLength,
      min: min,
      max: max,
      pattern: (pattern == null || pattern.isEmpty) ? null : pattern,
      enumValues:
          (enumValues == null || enumValues.isEmpty) ? null : enumValues,
    );
  }

  String? validate(Object? value) {
    if (required) {
      if (value == null) return 'Required';
      if (value is String && value.trim().isEmpty) return 'Required';
    }

    if (value is String) {
      final len = value.length;
      if (minLength != null && len < minLength!) {
        return 'Too short';
      }
      if (maxLength != null && len > maxLength!) {
        return 'Too long';
      }

      if (pattern != null) {
        final re = RegExp(pattern!);
        if (!re.hasMatch(value)) {
          return 'Invalid format';
        }
      }

      if (enumValues != null && enumValues!.isNotEmpty) {
        if (!enumValues!.contains(value)) {
          return 'Invalid selection';
        }
      }
    }

    num? asNum(Object? v) {
      if (v is num) return v;
      if (v is String) return num.tryParse(v);
      return null;
    }

    final numeric = (min != null || max != null) ? asNum(value) : null;
    if ((min != null || max != null) && numeric == null) {
      if (value == null || (value is String && value.trim().isEmpty)) {
        // Let `required` handle empty values.
      } else {
        return 'Invalid number';
      }
    }

    if (numeric != null) {
      if (min != null && numeric < min!) {
        return 'Too small';
      }
      if (max != null && numeric > max!) {
        return 'Too large';
      }
    }

    if (enumValues != null && enumValues!.isNotEmpty && value is! String) {
      // enumValues only makes sense for string fields; fail closed.
      return 'Invalid selection';
    }

    return null;
  }
}

/// Parsed binding reference for a single field.
///
/// The current wire format is a simple string: `<formId>.<fieldKey>`.
///
/// To reduce migration friction we also accept `:` and `/` as separators.
final class SchemaFieldBinding {
  const SchemaFieldBinding({required this.formId, required this.fieldKey});

  final String formId;
  final String fieldKey;

  static SchemaFieldBinding? tryParse(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    int index = trimmed.indexOf('.');
    if (index <= 0) {
      index = trimmed.indexOf(':');
    }
    if (index <= 0) {
      index = trimmed.indexOf('/');
    }
    if (index <= 0 || index >= trimmed.length - 1) return null;

    final formId = trimmed.substring(0, index).trim();
    final fieldKey = trimmed.substring(index + 1).trim();
    if (formId.isEmpty || fieldKey.isEmpty) return null;
    return SchemaFieldBinding(formId: formId, fieldKey: fieldKey);
  }
}
