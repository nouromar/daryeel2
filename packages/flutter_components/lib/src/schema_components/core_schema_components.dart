import 'package:flutter_schema_renderer/flutter_schema_renderer.dart';

import 'action_card_schema_component.dart';
import 'address_section_schema_component.dart';
import 'bottom_tabs_schema_component.dart';
import 'bound_action_card_schema_component.dart';
import 'for_each_schema_component.dart';
import 'gap_schema_component.dart';
import 'if_schema_component.dart';
import 'icon_button_schema_component.dart';
import 'icon_schema_component.dart';
import 'info_card_schema_component.dart';
import 'layout_schema_components.dart';
import 'payment_options_section_schema_component.dart';
import 'primary_action_bar_schema_component.dart';
import 'remote_paged_list_schema_component.dart';
import 'remote_query_schema_component.dart';
import 'schema_component_context.dart';
import 'screen_template_schema_component.dart';
import 'status_timeline_panel_schema_component.dart';
import 'tap_area_schema_component.dart';
import 'text_button_schema_component.dart';
import 'text_schema_component.dart';
import 'text_input_schema_component.dart';

/// Registers the standard set of schema components shipped by `flutter_components`.
///
/// Apps can call this to avoid missing-registration runtime errors
/// (e.g. unsupported `Padding`/`Column`). Apps may then register additional
/// components or override defaults by re-registering the same component name.
void registerCoreSchemaComponents({
  required SchemaWidgetRegistry registry,
  required SchemaComponentContext context,
}) {
  // Common UI components.
  registerTextInputSchemaComponent(registry: registry, context: context);
  registerScreenTemplateSchemaComponent(registry: registry, context: context);
  registerInfoCardSchemaComponent(registry: registry, context: context);
  registerActionCardSchemaComponent(registry: registry, context: context);
  registerGapSchemaComponent(registry: registry, context: context);
  registerBottomTabsSchemaComponent(registry: registry, context: context);
  registerPrimaryActionBarSchemaComponent(registry: registry, context: context);
  registerTextButtonSchemaComponent(registry: registry, context: context);
  registerTextSchemaComponent(registry: registry, context: context);
  registerStatusTimelinePanelSchemaComponent(
      registry: registry, context: context);
  registerIconSchemaComponent(registry: registry, context: context);
  registerIconButtonSchemaComponent(registry: registry, context: context);
  registerAddressSectionSchemaComponent(registry: registry, context: context);
  registerPaymentOptionsSectionSchemaComponent(
    registry: registry,
    context: context,
  );

  // Data-driven components.
  registerRemoteQuerySchemaComponent(registry: registry, context: context);
  registerRemotePagedListSchemaComponent(registry: registry, context: context);
  registerForEachSchemaComponent(registry: registry, context: context);
  registerIfSchemaComponent(registry: registry, context: context);
  registerBoundActionCardSchemaComponent(registry: registry, context: context);

  // Layout components.
  registerRowSchemaComponent(registry: registry, context: context);
  registerColumnSchemaComponent(registry: registry, context: context);
  registerStackSchemaComponent(registry: registry, context: context);
  registerWrapSchemaComponent(registry: registry, context: context);
  registerPaddingSchemaComponent(registry: registry, context: context);
  registerAlignSchemaComponent(registry: registry, context: context);
  registerSizedBoxSchemaComponent(registry: registry, context: context);
  registerExpandedSchemaComponent(registry: registry, context: context);
  registerTapAreaSchemaComponent(registry: registry, context: context);
}
