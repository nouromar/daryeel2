# Daryeel 2 API design: pharmacy catalog entities

## Goal

Define the v1 pharmacy catalog entity model for `services/api`.

This document covers:

- canonical products
- product categories
- pharmacy ownership and branch/store modeling
- branch-level product offers
- product images and barcode handling

This document does **not** cover pharmacy order entities, request workflow, fulfillment, or delivery operations.

## Current repo baseline

Today `services/api/app/routers/pharmacy.py` serves a temporary fixture-backed catalog through `GET /v1/pharmacy/catalog`.

Current fixture items include fields like:

- `id`
- `name`
- `rx_required`
- `price`
- `subtitle`
- `icon`

This is enough for schema/UI demos, but it does not yet model:

- canonical products
- category taxonomy
- organizations vs pharmacy branches
- branch-level stock and pricing
- reusable images

## Decisions

### 1. Product-first for v1

Customer browsing in v1 is product-first.

That means:

- customers browse/search products first
- the model must still support branch-level offers behind the scenes
- we do not hardcode the browsing mode into the entity design

The design must also support a future pharmacy-first experience in some markets without requiring a core schema redesign.

### 2. Neutral entity design for both product-first and pharmacy-first

We support both browsing modes by separating:

- canonical product identity
- branch/store offer data
- owner organization data

So:

- `products` = what the item is
- `pharmacies` = the branch/store that can fulfill
- `pharmacy_products` = the branch-level offer for that product

### 3. Organization and pharmacy are separate

Use both `organizations` and `pharmacies`.

Relationship:

- one organization -> many pharmacies
- one pharmacy -> one organization

Meaning:

- `organizations` = legal/business owner, partner, chain, or group
- `pharmacies` = operational branch/store/location

### 4. Price belongs to the branch offer

Price is not part of canonical product identity.

So:

- pricing belongs on `pharmacy_products`
- `products` must not own the live sale price

### 5. Rx flag belongs to the product

Use `products.rx_required` as the canonical v1 flag.

We are not adding branch-level overrides for v1.

### 6. Category uses assignment table

We will use:

- `product_categories`
- `product_category_assignments`

This is more flexible than a single `category_id` on `products` and supports future multi-category browsing without redesign.

### 7. Barcode belongs to the product

Barcode is treated as canonical product data, not branch offer data.

So:

- add `barcode` on `products`
- if a branch later needs its own internal code, use a separate field like `seller_sku` on `pharmacy_products`

### 8. Product images are separate

Use a dedicated `product_images` table rather than a single image column on `products`.

That supports:

- multiple images
- primary image selection
- sort order

### 9. ID strategy

For the target entity model in this document:

- use `UUIDv7` for core business entity primary keys
- use `UUIDv7` foreign keys consistently across related entities
- keep composite primary keys for pure assignment tables where appropriate

This document describes the target model, not the current integer-ID implementation style in existing API tables.

### 10. Location fields use structured columns

For pharmacy catalog entities, use structured canonical location fields rather than a single opaque JSON column.

Entity-specific rule:

- `pharmacies` gets the full branch/store location subset
- `organizations` may keep an optional business/legal address subset
- `pharmacy_products` does **not** own location fields

If extra provider/geocoder payload must be preserved later, add an optional metadata JSON field instead of replacing the structured columns.

## Recommended v1 entity set

### 1. `products`

Canonical medicine/product identity.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Canonical internal product ID; use `UUIDv7` |
| `sku` | varchar(64) nullable | Optional internal catalog code |
| `barcode` | varchar(64) nullable | Canonical barcode/GTIN-like value |
| `name` | varchar(200) | Primary display name |
| `generic_name` | varchar(200) nullable | Generic medicine name |
| `brand_name` | varchar(200) nullable | Brand/trade name |
| `form` | varchar(64) nullable | e.g. tablet, syrup, capsule |
| `strength` | varchar(64) nullable | e.g. 500mg |
| `rx_required` | boolean | Canonical prescription requirement |
| `status` | varchar(32) | `active`, `inactive` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

Notes:

- `products.id` is the canonical identity.
- `sku` is optional and should not replace the canonical product ID.
- canonical product data belongs here, not on the branch offer.

### 2. `product_images`

Product media.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `product_id` | uuid FK -> `products.id` | Owning product |
| `storage_key` | varchar(512) | Storage reference/path |
| `sort_order` | integer | Display order |
| `is_primary` | boolean | Primary/default image |
| `created_at` | timestamptz | Audit |

### 3. `product_categories`

Catalog taxonomy.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `code` | varchar(64) | Stable category code |
| `name` | varchar(128) | Display name |
| `parent_id` | uuid FK -> `product_categories.id` nullable | Optional hierarchy |
| `status` | varchar(32) | `active`, `inactive` |
| `sort_order` | integer nullable | Optional display order |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 4. `product_category_assignments`

Links products to categories.

| Field | Type | Notes |
| --- | --- | --- |
| `product_id` | uuid FK -> `products.id` | Composite PK part |
| `category_id` | uuid FK -> `product_categories.id` | Composite PK part |
| `sort_order` | integer nullable | Optional per-category ordering |
| `created_at` | timestamptz | Audit |

### 5. `organizations`

Owner or partner group.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `name` | varchar(200) | Business/legal or partner name |
| `status` | varchar(32) | `active`, `inactive` |
| `address_text` | varchar(255) nullable | Optional business/legal address |
| `country_code` | varchar(2) nullable | ISO country |
| `region_code` | varchar(64) nullable | Region/subdivision |
| `city_name` | varchar(128) nullable | City/locality |
| `lat` | numeric(10,7) nullable | Optional geo point latitude |
| `lng` | numeric(10,7) nullable | Optional geo point longitude |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 6. `pharmacies`

Operational branch/store/location.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | Use `UUIDv7` |
| `organization_id` | uuid FK -> `organizations.id` | Owning organization |
| `name` | varchar(200) | Branch/store display name |
| `branch_code` | varchar(64) nullable | Internal/store code |
| `status` | varchar(32) | `active`, `inactive` |
| `address_text` | varchar(255) nullable | Human-readable branch/store address |
| `country_code` | varchar(2) nullable | ISO country |
| `region_code` | varchar(64) nullable | Region/subdivision |
| `city_name` | varchar(128) nullable | City/locality |
| `zone_code` | varchar(64) nullable | Operational zone or neighborhood code |
| `lat` | numeric(10,7) nullable | Geo point latitude |
| `lng` | numeric(10,7) nullable | Geo point longitude |
| `place_id` | varchar(255) nullable | Geocoder/provider place identifier |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

Notes:

- branch/store-level operations should reference `pharmacies`
- `pharmacies` is the correct level for inventory, availability, and fulfillment selection
- this is the fullest location-bearing catalog entity in pharmacy v1

### 7. `pharmacy_products`

Branch-level offer for a product.

| Field | Type | Notes |
| --- | --- | --- |
| `pharmacy_id` | uuid FK -> `pharmacies.id` | Composite PK part; branch/store offering the product |
| `product_id` | uuid FK -> `products.id` | Composite PK part; canonical product |
| `seller_sku` | varchar(64) nullable | Optional branch/seller-specific code |
| `price_amount` | numeric(12,2) | Branch-level sale price |
| `currency_code` | varchar(3) | ISO currency code |
| `stock_status` | varchar(32) | `in_stock`, `low_stock`, `out_of_stock`, `unavailable` |
| `available_quantity` | integer nullable | Optional exact quantity |
| `status` | varchar(32) | `active`, `inactive` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

Notes:

- one product may have many branch-level offers
- `pharmacy_products` is the core entity that allows both product-first and pharmacy-first browsing
- `pharmacy_products` is also the checkout/source-offer model, but after order creation the authoritative customer-facing price lives on the order snapshot
- if fulfillment later reroutes to another pharmacy branch, the canonical ordered product remains `product_id` on the order item rather than the branch-level offer row
- `pharmacy_products` does not need a standalone surrogate `id` in v1; the natural key is `(pharmacy_id, product_id)`

## Constraints and indexes

- unique index on `product_categories(code)`
- unique composite index on `product_category_assignments(product_id, category_id)`
- composite PK on `pharmacy_products(pharmacy_id, product_id)`
- index on `pharmacy_products(product_id, status)`
- index on `pharmacies(organization_id, status)`
- optional unique index on `products(sku)` when source data is clean enough
- optional unique index on `products(barcode)` if barcode quality is reliable enough

## How product-first v1 works with this model

Product-first browsing:

- search starts from `products`
- category browsing starts from `product_categories` and `product_category_assignments`
- the app resolves available branch/store offers through `pharmacy_products`

This keeps the customer experience simple in v1 while still preserving branch-level offer data.

## How pharmacy-first can be added later

If some markets later need a pharmacy-first experience:

- customer selects a pharmacy branch first
- browsing is then scoped to that pharmacy's `pharmacy_products`
- the core entities do not need to change

Only query patterns, ranking/filtering, and UI flow change.

## Non-goals for this document

- pharmacy order entities
- request pricing snapshots
- substitutions and confirmation workflows
- branch fulfillment or dispatch
- customer identity verification

## Implementation impact on current API

- replace `_PHARMACY_CATALOG` fixture items with DB-backed `products` + `pharmacy_products`
- keep `GET /v1/pharmacy/catalog` product-first in v1
- derive UI price/subtitle from `pharmacy_products`
- derive Rx badge from `products.rx_required`
- support future branch-scoped browsing without changing the core schema

## Open follow-ups

- whether category hierarchy is needed in v1 or can stay effectively flat
- whether to add separate external/public product codes in addition to `UUIDv7` primary keys
