import 'package:flutter/material.dart';
import 'package:flutter_runtime/flutter_runtime.dart';
import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'schema_component_context.dart';
import 'schema_component_utils.dart';

void registerIconSchemaComponent({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  registry.register('Icon', (node, _) {
    final nameTemplate = (node.props['name'] as String?)?.trim();
    final semanticLabelTemplate =
        (node.props['semanticLabel'] as String?)?.trim();

    final size = schemaAsDouble(node.props['size']);

    final colorRaw = (node.props['color'] as String?)?.trim();

    final codePointRaw = node.props['codePoint'];
    final codePoint = (codePointRaw is num)
        ? codePointRaw.toInt()
        : int.tryParse('${codePointRaw ?? ''}');

    final familyRaw = (node.props['family'] as String?)?.trim();

    return Builder(
      builder: (buildContext) {
        final theme = Theme.of(buildContext);

        final name = (nameTemplate == null || nameTemplate.isEmpty)
            ? null
            : interpolateSchemaString(nameTemplate, buildContext).trim();

        final semanticLabel =
            (semanticLabelTemplate == null || semanticLabelTemplate.isEmpty)
                ? null
                : interpolateSchemaString(semanticLabelTemplate, buildContext)
                    .trim();

        final iconData = _resolveIconData(
          name: name,
          codePoint: codePoint,
          familyRaw: familyRaw,
        );

        if (iconData == null) {
          if (name != null && name.isNotEmpty) {
            return UnknownSchemaWidget(
              componentName: 'Icon(unknown-name:${name.toLowerCase()})',
            );
          }
          return const SizedBox.shrink();
        }

        final color = _resolveColor(theme, colorRaw);

        return Icon(
          iconData,
          size: size,
          color: color,
          semanticLabel: semanticLabel,
        );
      },
    );
  });
}

IconData? _resolveIconData({
  required String? name,
  required int? codePoint,
  required String? familyRaw,
}) {
  if (codePoint != null && codePoint > 0) {
    final family = (familyRaw ?? '').trim().toLowerCase();

    // Default to MaterialIcons.
    String fontFamily;
    String? fontPackage;

    switch (family) {
      case 'materialsymbolsoutlined':
      case 'material_symbols_outlined':
      case 'symbols_outlined':
        fontFamily = 'MaterialSymbolsOutlined';
        fontPackage = null;
        break;
      case 'materialsymbolsrounded':
      case 'material_symbols_rounded':
      case 'symbols_rounded':
        fontFamily = 'MaterialSymbolsRounded';
        fontPackage = null;
        break;
      case 'materialsymbolssharp':
      case 'material_symbols_sharp':
      case 'symbols_sharp':
        fontFamily = 'MaterialSymbolsSharp';
        fontPackage = null;
        break;
      case 'materialicons':
      case 'material_icons':
      case 'icons':
      case '':
      default:
        fontFamily = 'MaterialIcons';
        fontPackage = null;
        break;
    }

    return IconData(
      codePoint,
      fontFamily: fontFamily,
      fontPackage: fontPackage,
      matchTextDirection: false,
    );
  }

  final key = (name ?? '').trim().toLowerCase();
  if (key.isEmpty) return null;

  return switch (key) {
    // Common navigation/actions.
    'close' || 'x' || 'dismiss' => Icons.close,
    'delete' || 'trash' => Icons.delete_outline,
    'remove' || 'minus' => Icons.remove_circle_outline,
    'add' || 'plus' => Icons.add_circle_outline,
    'edit' || 'pencil' => Icons.edit_outlined,
    'check' || 'done' => Icons.check,

    // Media/files.
    'camera' => Icons.photo_camera_outlined,
    'gallery' || 'photo' || 'image' => Icons.photo_outlined,
    'file' => Icons.insert_drive_file_outlined,
    'upload' || 'file_upload' => Icons.upload_file_outlined,

    // Commerce.
    'cart' || 'shopping_cart' => Icons.shopping_cart_outlined,

    // Existing app icon vocabulary.
    'ambulance' ||
    'local_hospital' ||
    'hospital' =>
      Icons.local_hospital_outlined,
    'home' || 'home_visit' => Icons.home_outlined,
    'pharmacy' || 'local_pharmacy' => Icons.local_pharmacy_outlined,
    'account' || 'person' || 'profile' => Icons.person_outline,
    'activities' || 'activity' || 'history' => Icons.history,
    _ => null,
  };
}

Color? _resolveColor(ThemeData theme, String? colorRaw) {
  final v = colorRaw?.toLowerCase();
  final scheme = theme.colorScheme;

  return switch (v) {
    'muted' || 'subtle' || 'secondarytext' => scheme.onSurfaceVariant,
    'primary' => scheme.primary,
    'secondary' => scheme.secondary,
    'error' => scheme.error,
    'default' || null || '' => null,
    _ => null,
  };
}
