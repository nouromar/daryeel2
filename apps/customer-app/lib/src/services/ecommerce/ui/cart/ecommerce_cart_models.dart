import 'package:flutter/foundation.dart';

@immutable
final class EcommerceCartLine {
  const EcommerceCartLine({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.rxRequired,
    required this.price,
    required this.currencySymbol,
  });

  final String id;
  final String title;
  final String subtitle;
  final int quantity;
  final bool rxRequired;

  /// Unit price in display currency.
  ///
  /// Kept as a raw value so we can preserve the cart line record shape
  /// when only quantity changes.
  final Object? price;

  /// Currency symbol to show (e.g. `$`).
  ///
  /// Prefer passing this explicitly for theme/app consistency.
  final String currencySymbol;

  double? get priceValue {
    final raw = price;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  double? get lineTotalValue {
    final p = priceValue;
    if (p == null) return null;
    return p * quantity;
  }
}

@immutable
final class EcommerceCartTotals {
  const EcommerceCartTotals({
    required this.subtotal,
    required this.tax,
    required this.discount,
  });

  final double subtotal;
  final double tax;
  final double discount;

  double get total => subtotal + tax - discount;
}
