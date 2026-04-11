# Pharmacy Checkout Design

## Status

Approved design for implementation.

This document defines the schema-first checkout flow for pharmacy shopping and the request-building split between common request handling and pharmacy-specific payload construction.

## Screen layout

The pharmacy checkout screen should render these sections in order:

1. Delivery address
2. Notes
3. Cart summary
4. Uploaded prescription files
5. Payment widget
6. Checkout button

The screen remains schema-first. Shared components should be used wherever they exist. Service-specific app widgets should only remain where the shared component set is genuinely insufficient.

## Checkout state contract

The checkout screen reads and writes the following state paths:

### Common checkout state

- `pharmacy.cart.deliveryAddress`
- `pharmacy.checkout.notes`
- `pharmacy.checkout.payment.method`
- `pharmacy.checkout.payment.timing`

### Cart-derived display state

- `pharmacy.cart.summary.lines`
- `pharmacy.cart.summary.total`
- `pharmacy.cart.prescriptionUploads`

### Cart payload state

- `pharmacy.cart.lines`

## Schema composition

The checkout screen should use the following schema composition:

- `AddressSection` for delivery address
- `TextInput` for notes
- `CartSummary` for order summary
- `ForEach` over `pharmacy.cart.prescriptionUploads` for uploaded files
- `PaymentOptionsSection` for customer-facing payment method selection
- `PrimaryActionBar` for submit

`PaymentOptionsSection` is a shared component and must not be pharmacy-specific.
Payment timing remains part of backend-facing request state but is hidden from the customer UI for now.

## Payment options backend contract

The checkout screen needs a backend read endpoint for payment choices.

Recommended endpoint:

- `GET /v1/pharmacy/checkout_options`

Recommended response:

```json
{
  "payment_options": {
    "methods": [
      {
        "id": "cash",
        "label": "Cash",
        "description": "Pay with cash"
      },
      {
        "id": "mobile_money",
        "label": "Mobile money",
        "description": "Pay using EVC or Zaad"
      }
    ],
    "timings": [
      {
        "id": "after_delivery",
        "label": "After delivery"
      },
      {
        "id": "before_delivery",
        "label": "Before delivery"
      }
    ]
  }
}
```

The shared payment widget should consume this data and bind the chosen values into checkout state.

## PaymentOptionsSection contract

`PaymentOptionsSection` is a reusable shared component for service request flows.

Responsibilities:

- render payment methods
- optionally render payment timings
- show current selection for each group
- write chosen values into state

Proposed component props:

- `title`
- `methodsPath`
- `timingsPath`
- `methodBind`
- `timingBind`
- `methodTitle`
- `timingTitle`
- `showTiming`

Notes:

- `methodsPath` and `timingsPath` are read relative to the current `SchemaDataScope`, typically inside a `RemoteQuery`
- `methodBind` and `timingBind` are state binds

## Request building split

Checkout submit must be split into:

1. Common request handling
2. Pharmacy-specific payload construction

The common request handler is responsible for the stable request envelope.

Pharmacy is responsible for building the pharmacy payload fragment.

## Submit envelope

The submit pipeline should construct this request shape:

```json
{
  "service_id": "pharmacy",
  "delivery_location": {
    "text": "Hodan, Mogadishu",
    "lat": 2.046934,
    "lng": 45.318162,
    "accuracy_m": 15,
    "place_id": "optional",
    "region_id": "optional"
  },
  "notes": "Leave at reception",
  "payment": {
    "method": "cash",
    "timing": "after_delivery"
  },
  "payload": {
    "cart_lines": [
      {
        "product_id": "prod_paracetamol_500mg",
        "quantity": 2
      }
    ],
    "summary_lines": [
      {
        "id": "subtotal",
        "label": "Subtotal",
        "amount": 10.0,
        "amountText": "$10.00"
      },
      {
        "id": "tax",
        "label": "Tax",
        "amount": 0.5,
        "amountText": "$0.50"
      }
    ],
    "summary_total": {
      "label": "Total",
      "amount": 10.5,
      "amountText": "$10.50"
    },
    "prescription_upload_ids": [
      "rx_123"
    ]
  }
}
```

## Backend persistence split

The backend `ServiceRequest` split should remain:

- `service_id` from common request envelope
- `delivery_location_json` from common request envelope
- `notes` from common request envelope
- `payment_json` from common request envelope
- `payload_json` from pharmacy payload fragment

This preserves a reusable spine while keeping pharmacy-specific order content isolated.

## Pricing summary rule

The client will include summary lines and total in the payload for now.

However:

- the backend must validate and recompute pricing
- backend-computed totals remain authoritative
- client summary data is treated as display-oriented input, not the final source of truth

## Implementation order

Implementation must follow this order:

1. Add pharmacy payment-options backend endpoint
2. Build shared `PaymentOptionsSection` component and contract
3. Compose checkout screen in schema using shared components
4. Update submit handling to build the common envelope plus pharmacy payload
5. Add focused tests
6. Validate app and backend changes