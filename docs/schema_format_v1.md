# Schema Format v1

## 1. Purpose

This document defines the first practical schema format for Daryeel2.

The format is designed to:
- compose screens from known components
- customize those components through typed props
- wire supported actions safely
- support reuse through references and slots
- remain small enough to validate and debug reliably

This is a schema for composition, not a general-purpose UI programming language.

## 2. Document Shape

Every schema document should include:
- schema version
- document id
- screen/template type
- target product
- optional target service/domain
- `themeId`
- optional `themeMode`
- component tree
- optional references used by the tree
- action definitions limited to known action types

Example root:

```json
{
  "schemaVersion": "1.0",
  "id": "delivery_checkout_screen",
  "documentType": "screen",
  "product": "customer_app",
  "service": "delivery",
  "themeId": "patient-default",
  "themeMode": "light",
  "root": {
    "type": "ScreenTemplate",
    "slots": {
      "body": [
        { "ref": "section:delivery_address_v1" },
        { "ref": "section:payment_options_v2" },
        {
          "type": "PrimaryActionBar",
          "props": {
            "primaryLabel": "Place order"
          },
          "actions": {
            "primary": "submit_request"
          }
        }
      ]
    }
  },
  "actions": {
    "submit_request": {
      "type": "submit_form",
      "formId": "delivery_checkout"
    }
  }
}
```

## 3. Node Types

Supported node types in v1:
- `component`
- `ref`

For convenience, component nodes may use `type` directly as the component name.

### 3.1 Component node

```json
{
  "type": "QuoteSummaryCard",
  "props": {
    "variant": "compact",
    "showIcon": true
  }
}
```

### 3.2 Reference node

```json
{
  "ref": "section:quote_summary_compact_v1"
}
```

References allow reuse of approved fragments.

## 4. Props

Props must match the registered contract for the component.

Rules:
- only declared props are allowed
- types must match contract definitions
- required props must be present unless defaults exist
- enums must use known values
- unknown props are rejected or ignored based on strictness mode

Styling-related props should use bounded semantic values such as:
- `variant`
- `tone`
- `size`
- `surface`
- `density`

Schema should not rely on raw style objects as a primary mechanism.

Example:

```json
{
  "type": "ProviderCard",
  "props": {
    "variant": "detailed",
    "tone": "default",
    "surface": "raised",
    "showRating": true,
    "showEta": true
  }
}
```

## 5. Theming Model

v1 theming should use four mechanisms together:
- token-based themes
- component variants
- theme inheritance
- bounded styling overrides

Canonical reference (how it’s implemented + where to change what): `docs/theming.md`.

### 5.1 Theme selection
Schema selects a theme with `themeId` and may optionally select a mode such as `light` or `dark`.

Example:

```json
{
  "themeId": "patient-default",
  "themeMode": "dark"
}
```

### 5.2 Token-based themes
Themes should resolve to semantic design tokens, for example:
- `color.surface.primary`
- `color.text.primary`
- `color.action.brand`
- `space.md`
- `radius.md`
- `elevation.card`

### 5.3 Theme inheritance
Themes may inherit in layers, for example:
- base theme
- product theme
- service theme
- mode override

### 5.4 Bounded overrides
Allowed override fields should be semantic and limited.

Examples:
- `surface: raised`
- `density: compact`
- `tone: emphasized`

Avoid:
- arbitrary colors
- arbitrary padding values on nodes
- unrestricted `style` blobs

## 6. Slots

Components can define typed slots.

Example:

```json
{
  "type": "ScreenTemplate",
  "slots": {
    "header": [
      {
        "type": "HeaderBar",
        "props": {
          "title": "Checkout"
        }
      }
    ],
    "body": [
      {
        "type": "AddressSection"
      },
      {
        "type": "PaymentOptionsSection"
      }
    ],
    "footer": [
      {
        "type": "PrimaryActionBar",
        "props": {
            "primaryLabel": "Continue",
            "tone": "brand"
        },
        "actions": {
          "primary": "continue_checkout"
        }
      }
    ]
  }
}
```

## 7. Actions

Actions are declared centrally and referenced by components.

Supported action types (implemented in the Flutter runtime as of Apr 2026):
- `navigate`
- `open_url`
- `set_state`
- `patch_state`
- `submit_form`
- `track_event`

Example:

```json
{
  "actions": {
    "continue_checkout": {
      "type": "navigate",
      "route": "checkout.review"
    },
    "open_terms": {
      "type": "open_url",
      "route": "https://example.com/terms"
    },
    "submit_request": {
      "type": "submit_form",
      "formId": "request_form"
    },
    "track_view": {
      "type": "track_event",
      "eventName": "screen.view",
      "properties": {
        "screenId": "checkout",
        "variant": "v1"
      }
    }
  }
}
```

Not supported in v1:
- arbitrary backend endpoints declared from schema
- arbitrary multi-step logic graphs
- unbounded scripting / expression programs (the runtime only supports a bounded, one-line expression engine in specific fields)

Reserved for a future schema format version (not currently implemented):
- `open_modal`
- `refresh_data`
- `select_value`
- `dismiss`

## 8. Visibility and Conditional Rules

v1 should keep conditionals narrow.

Supported patterns (implemented in the Flutter runtime as of Apr 2026):
- feature flag enabled (`visibleWhen.featureFlag`)
- expression evaluates to true (`visibleWhen.expr`)

Other conditional keys described in earlier drafts (service/role/state/etc.) are not implemented in the current runtime. Unknown keys are treated as visible (and should emit a diagnostic warning) to avoid accidental content loss.

Example:

```json
{
  "type": "TipSection",
  "visibleWhen": {
    "featureFlag": "show_driver_tip"
  }
}
```

Expression example:

```json
{
  "type": "Text",
  "props": {"text": "Only visible when state.showGreeting is true"},
  "visibleWhen": {
    "expr": "state.showGreeting == true"
  }
}
```

Notes:
- `visibleWhen.expr` must evaluate to a boolean. Non-boolean results default to **visible** and emit a warning diagnostic.
- `expr` may be written as either a plain expression (`"state.a > 0"`) or wrapped (`"${state.a > 0}"`).
- If both `featureFlag` and `expr` are provided, they are combined with **AND**.

For full branching (then/else subtrees), use the `If` component. It supports the legacy `valuePath`/`op` condition style and `props.expr`.

Avoid using expressions for complex workflow logic in v1. The runtime expression engine is intentionally bounded, side-effect free, and budgeted.

## 9. Data Binding

Bindings should be explicit and limited.

Allowed binding targets:
- form fields
- view model fields
- known state keys

Example:

```json
{
  "type": "PhoneField",
  "props": {
    "label": "Phone number",
    "variant": "default"
  },
  "bind": "form.customer_phone"
}
```

## 10. References and Reuse

References should point to approved schema fragments.

Recommended naming:
- `component:...`
- `section:...`
- `template:...`
- `flow:...`

Examples:
- `section:pickup_dropoff_v1`
- `template:request_detail_v2`
- `component:primary_action_bar_v1`

## 11. Validation Rules

Server-side validation:
- schema version supported
- product/service targets valid
- `themeId` and `themeMode` valid
- all refs resolvable
- all components registered
- props compatible with contracts
- actions valid for v1

Client-side validation:
- schema version supported by app
- theme and mode supported by this client build
- required components available in this client build
- required slots/props present
- unsupported nodes rejected safely

## 12. Fallback Rules

If a schema cannot be safely rendered:
- fall back to a default built-in screen when available
- fall back to a default theme and default mode when theme resolution fails
- log validation failure details
- record schema id and version for debugging

Fallback behavior should be deterministic.

## 13. Example End-to-End

```json
{
  "schemaVersion": "1.0",
  "id": "taxi_request_screen",
  "documentType": "screen",
  "product": "customer_app",
  "service": "taxi",
  "themeId": "patient-default",
  "themeMode": "dark",
  "root": {
    "type": "ScreenTemplate",
    "slots": {
      "header": [
        {
          "type": "HeaderBar",
          "props": {
            "title": "Request a ride"
          }
        }
      ],
      "body": [
        {
          "type": "AddressSection",
          "props": {
            "title": "Pickup",
            "mode": "pickup"
          },
          "bind": "form.pickup"
        },
        {
          "type": "AddressSection",
          "props": {
            "title": "Dropoff",
            "mode": "dropoff"
          },
          "bind": "form.dropoff"
        },
        {
          "type": "PaymentOptionsSection",
          "props": {
            "allowedMethods": ["cash", "mobile_money", "card"],
            "surface": "subtle"
          },
          "bind": "form.payment_method"
        },
        {
          "type": "QuoteSummaryCard",
          "props": {
            "variant": "compact",
            "surface": "raised"
          }
        }
      ],
      "footer": [
        {
          "type": "PrimaryActionBar",
          "props": {
            "primaryLabel": "Find driver",
            "tone": "brand",
            "size": "large"
          },
          "actions": {
            "primary": "submit_request"
          }
        }
      ]
    }
  },
  "actions": {
    "submit_request": {
      "type": "submit_form",
      "formId": "taxi_request_form"
    }
  }
}
```

## 14. V1 Scope Boundary

v1 is intentionally limited.

Included:
- typed components
- token-based theming
- component variants
- theme inheritance
- bounded styling overrides
- slots
- references
- limited actions
- limited visibility rules
- limited bindings

Deferred:
- complex conditional logic
- arbitrary expression language
- dynamic backend action definitions
- free-form layout engine
- raw style objects as a primary mechanism
- workflow scripting

This keeps the first schema format implementable and supportable.