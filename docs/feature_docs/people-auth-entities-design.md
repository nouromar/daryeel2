# Daryeel 2 entity design: people, profiles, auth, and roles

## Goal

Define an industry-aligned entity model for Daryeel 2 that supports:

- 3 top-level person types: `customer`, `provider`, `staff`
- global, high-volume customer growth
- smaller but growing provider network
- tightly controlled staff access
- OTP-first customer sign-in
- support for multiple authentication methods and multi-factor authentication
- geo and service scoping for providers and staff

## Core design principles

1. **Separate identity from access**
   - `people` and profile tables model the human and their business data.
   - auth tables model how they sign in.
   - role and scope tables model what they can do.

2. **Keep auth out of the people table**
   - Do not store OTP, password, TOTP, passkey, or session state on `people`.
   - Keep those in dedicated auth tables.

3. **Use role assignments, not hard-coded booleans**
   - Prefer `roles` and `person_role_assignments` over fields like `is_admin`.

4. **Use first-class scope tables**
   - Geo, service, and organization access should be relational data, not JSON blobs.

5. **Allow future overlap**
   - A person can have one primary type but may hold multiple roles over time.

## Recommended v1 entity set

### 1. `people`

The root table for any human in the platform.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable internal identifier |
| `primary_person_type` | enum | `customer`, `provider`, `staff` |
| `status` | enum | `active`, `pending_verification`, `suspended`, `disabled`, `deleted` |
| `display_name` | varchar(200) nullable | Safe display label |
| `first_name` | varchar(100) nullable | Legal/preferred name component |
| `last_name` | varchar(100) nullable | Legal/preferred name component |
| `preferred_language` | varchar(16) nullable | e.g. `en`, `so`, `ar` |
| `timezone` | varchar(64) nullable | IANA timezone |
| `country_code` | varchar(2) nullable | ISO 3166-1 alpha-2 |
| `phone_e164` | varchar(32) nullable | Optional denormalized primary phone |
| `email` | varchar(320) nullable | Optional denormalized primary email |
| `date_of_birth` | date nullable | Only if required by business/regulation |
| `avatar_url` | varchar(500) nullable | Profile image |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |
| `deleted_at` | timestamptz nullable | Soft delete marker |

**Notes**

- Keep `phone_e164` and `email` here only as convenience fields. The source of truth for sign-in identifiers should be `auth_identities`.
- Add unique partial indexes for active canonical phone/email if desired.

### 2. `customer_profiles`

Customer-specific business profile.

| Field | Type | Notes |
| --- | --- | --- |
| `person_id` | UUID PK/FK -> `people.id` | One-to-one with `people` |
| `customer_number` | varchar(64) unique nullable | Human-friendly reference |
| `marketing_consent` | boolean | Default false |
| `support_tier` | varchar(32) nullable | Optional CRM/service tier |
| `default_country_code` | varchar(2) nullable | Useful for UX/localization |
| `notes_internal` | text nullable | Internal support note; restricted access |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 3. `provider_profiles`

Provider-specific business profile.

| Field | Type | Notes |
| --- | --- | --- |
| `person_id` | UUID PK/FK -> `people.id` | One-to-one with `people` |
| `provider_kind` | enum | `doctor`, `nurse`, `pharmacist`, `driver`, `medic` |
| `employment_type` | enum nullable | `employee`, `contractor`, `partner` |
| `license_number` | varchar(128) nullable | Professional or regulatory license |
| `license_country_code` | varchar(2) nullable | License jurisdiction |
| `license_expires_at` | date nullable | Expiry tracking |
| `verification_status` | enum | `pending`, `verified`, `rejected`, `expired` |
| `availability_status` | enum | `available`, `offline`, `on_leave`, `suspended` |
| `home_country_code` | varchar(2) nullable | Primary operating country |
| `notes_internal` | text nullable | Restricted internal note |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 4. `staff_profiles`

Internal/admin/operations profile.

| Field | Type | Notes |
| --- | --- | --- |
| `person_id` | UUID PK/FK -> `people.id` | One-to-one with `people` |
| `staff_code` | varchar(64) unique nullable | Internal identifier |
| `employment_type` | enum nullable | `employee`, `contractor` |
| `department` | varchar(64) nullable | e.g. ops, support, clinical |
| `vpn_required` | boolean | Default true for sensitive roles |
| `mfa_required` | boolean | Default true |
| `break_glass_eligible` | boolean | Default false |
| `notes_internal` | text nullable | Restricted internal note |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

## Organization and scope model

### 5. `organizations`

Use for provider groups, pharmacies, clinics, ambulance partners, and internal business units.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable internal identifier |
| `organization_type` | enum | `pharmacy`, `clinic`, `hospital`, `ambulance_partner`, `internal` |
| `name` | varchar(200) | Display name |
| `code` | varchar(64) unique nullable | Internal short code |
| `status` | enum | `active`, `inactive`, `suspended` |
| `address_text` | varchar(255) nullable | Optional business/legal address |
| `country_code` | varchar(2) nullable | Headline country |
| `region_code` | varchar(64) nullable | Region/subdivision |
| `city_name` | varchar(128) nullable | City/locality |
| `lat` | numeric(10,7) nullable | Optional geo point latitude |
| `lng` | numeric(10,7) nullable | Optional geo point longitude |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 6. `organization_memberships`

Connect people to organizations.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `person_id` | UUID FK -> `people.id` | Member person |
| `organization_id` | UUID FK -> `organizations.id` | Owning organization |
| `membership_type` | enum | `provider`, `staff`, `manager` |
| `title` | varchar(128) nullable | Human title |
| `status` | enum | `active`, `inactive`, `pending` |
| `starts_at` | timestamptz nullable | Effective start |
| `ends_at` | timestamptz nullable | Effective end |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 7. `service_definitions`

Relational backing table for the platform `ServiceDefinition` concept.

Current repo terminology and implementation notes:

- The repo consistently uses `ServiceDefinition` for this concept.
- The API currently exposes it via `/v1/service-definitions`.
- Today the stable service identifier is a short string key such as `ambulance`, `home_visit`, or `pharmacy`.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | varchar(64) PK | Stable service key used by current APIs; e.g. `pharmacy`, `ambulance`, `home_visit` |
| `title` | varchar(128) | Display name; aligns with current `ServiceDefinition` payloads |
| `subtitle` | varchar(200) nullable | Optional catalog summary |
| `icon` | varchar(64) nullable | Optional icon token for service pickers |
| `status` | enum | `active`, `inactive` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 8. `person_service_scopes`

What services a provider or staff member can work in.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `person_id` | UUID FK -> `people.id` | Scoped person |
| `service_id` | varchar(64) FK -> `service_definitions.id` | Allowed service |
| `scope_level` | enum | `full`, `limited`, `read_only` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 9. `geo_scopes`

Normalized geography references.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `scope_type` | enum | `country`, `region`, `city`, `zone` |
| `country_code` | varchar(2) | ISO country |
| `region_code` | varchar(64) nullable | Internal or ISO subdivision |
| `city_code` | varchar(64) nullable | Internal city code |
| `zone_code` | varchar(64) nullable | Service zone code |
| `name` | varchar(200) | Display name |
| `status` | enum | `active`, `inactive` |

### 10. `person_geo_scopes`

What geographies a provider or staff member is allowed to operate in.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `person_id` | UUID FK -> `people.id` | Scoped person |
| `geo_scope_id` | UUID FK -> `geo_scopes.id` | Allowed geography |
| `access_mode` | enum | `allow`, `deny` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

## Role and permission model

### 11. `roles`

Catalog of assignable roles.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `code` | varchar(64) unique | e.g. `customer`, `pharmacist`, `dispatcher`, `admin`, `specialist` |
| `role_group` | enum | `customer`, `provider`, `staff` |
| `name` | varchar(128) | Display name |
| `description` | text nullable | Admin documentation |
| `is_system` | boolean | Built-in role marker |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 12. `permissions`

Optional but recommended if role-based access is expected to grow.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `code` | varchar(128) unique | e.g. `requests.dispatch`, `pharmacy.manage_orders` |
| `name` | varchar(128) | Display name |
| `description` | text nullable | Admin documentation |

### 13. `role_permissions`

Maps roles to permissions.

| Field | Type | Notes |
| --- | --- | --- |
| `role_id` | UUID FK -> `roles.id` | Composite PK part |
| `permission_id` | UUID FK -> `permissions.id` | Composite PK part |
| `created_at` | timestamptz | Audit |

### 14. `person_role_assignments`

Assign roles directly to people, optionally scoped.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `person_id` | UUID FK -> `people.id` | Assigned person |
| `role_id` | UUID FK -> `roles.id` | Granted role |
| `organization_id` | UUID FK -> `organizations.id` nullable | Optional org scope |
| `service_id` | varchar(64) FK -> `service_definitions.id` nullable | Optional service scope |
| `geo_scope_id` | UUID FK -> `geo_scopes.id` nullable | Optional geo scope |
| `status` | enum | `active`, `inactive`, `pending` |
| `assigned_by_person_id` | UUID FK -> `people.id` nullable | Audit actor |
| `starts_at` | timestamptz nullable | Effective start |
| `ends_at` | timestamptz nullable | Effective end |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

## Auth model

### 15. `auth_identities`

Canonical login identifiers. A person may have many.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `person_id` | UUID FK -> `people.id` | Owning person |
| `identity_type` | enum | `phone`, `email`, `username`, `external_subject` |
| `identity_value` | varchar(320) | Raw or normalized identifier |
| `identity_value_normalized` | varchar(320) | Indexed canonical form |
| `is_primary` | boolean | Default false |
| `is_verified` | boolean | Default false |
| `verified_at` | timestamptz nullable | Verification time |
| `status` | enum | `active`, `inactive`, `blocked` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

**Examples**

- customer: one or more phone numbers, maybe email later
- staff: work email + phone
- provider: phone + email + external identity from partner SSO if needed

### 16. `auth_factors`

Enrolled authentication factors for a person.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `person_id` | UUID FK -> `people.id` | Factor owner |
| `identity_id` | UUID FK -> `auth_identities.id` nullable | Linked identifier when relevant |
| `factor_type` | enum | `phone_otp`, `email_otp`, `password`, `totp`, `passkey`, `backup_code` |
| `display_label` | varchar(128) nullable | Safe admin/user label |
| `secret_ref` | varchar(255) nullable | Reference to secret store; do not store plaintext secrets |
| `credential_hash` | varchar(255) nullable | Password hash or derived verifier |
| `is_primary` | boolean | Default false |
| `is_verified` | boolean | Default false |
| `verified_at` | timestamptz nullable | Verification time |
| `status` | enum | `active`, `inactive`, `revoked` |
| `last_used_at` | timestamptz nullable | Audit |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 17. `auth_challenges`

Tracks OTP and step-up verification attempts.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Challenge identifier |
| `person_id` | UUID FK -> `people.id` nullable | Known person if resolved |
| `identity_id` | UUID FK -> `auth_identities.id` nullable | Target identity |
| `factor_type` | enum | Same factor enum family |
| `challenge_type` | enum | `sign_in`, `sign_up`, `step_up`, `recover`, `verify_identity` |
| `delivery_channel` | enum nullable | `sms`, `whatsapp`, `email`, `app`, `security_key` |
| `code_hash` | varchar(255) nullable | Hashed OTP or verifier |
| `attempt_count` | integer | Default 0 |
| `max_attempts` | integer | Configurable limit |
| `expires_at` | timestamptz | Expiry |
| `completed_at` | timestamptz nullable | Success time |
| `failed_at` | timestamptz nullable | Terminal failure |
| `status` | enum | `pending`, `completed`, `expired`, `failed`, `cancelled` |
| `ip_address` | inet nullable | Risk signal |
| `user_agent` | text nullable | Risk signal |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 18. `auth_sessions`

Session and refresh-token tracking.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Session identifier |
| `person_id` | UUID FK -> `people.id` | Session owner |
| `session_token_hash` | varchar(255) | Never store plaintext token |
| `refresh_token_hash` | varchar(255) nullable | If refresh tokens are used |
| `auth_strength` | enum | `single_factor`, `multi_factor`, `step_up` |
| `issued_at` | timestamptz | Issue time |
| `expires_at` | timestamptz | Expiry |
| `revoked_at` | timestamptz nullable | Revocation time |
| `revoke_reason` | varchar(128) nullable | Audit |
| `ip_address` | inet nullable | Risk/audit |
| `user_agent` | text nullable | Risk/audit |
| `device_id` | varchar(128) nullable | Optional client device reference |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

### 19. `auth_policies`

Central rules for required auth strength by subject and scope.

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID PK | Stable identifier |
| `subject_type` | enum | `person_type`, `role`, `service`, `organization` |
| `subject_value` | varchar(128) | e.g. `customer`, `staff`, `dispatcher`, `pharmacy` |
| `allowed_factor_types` | jsonb | Allowed factors list |
| `min_factor_count` | integer | e.g. 1 or 2 |
| `require_verified_identity` | boolean | Default true |
| `require_vpn` | boolean | Typically true for sensitive staff roles |
| `session_ttl_minutes` | integer | Policy-specific TTL |
| `status` | enum | `active`, `inactive` |
| `created_at` | timestamptz | Audit |
| `updated_at` | timestamptz | Audit |

## Recommended defaults by person type

### Customers

- Primary type: `customer`
- Typical roles: `customer`
- Auth: `phone_otp` first
- Geo scope: not required for sign-in
- Service scope: not usually needed
- MFA: optional now, supported later

### Providers

- Primary type: `provider`
- Typical roles: `doctor`, `nurse`, `pharmacist`, `driver`, `medic`
- Auth: password + OTP or OTP-only initially, depending risk level
- Geo scope: usually required
- Service scope: usually required
- Organization membership: usually required

### Staff

- Primary type: `staff`
- Typical roles: `dispatcher`, `admin`, `specialist`
- Auth: MFA required
- VPN requirement: recommended for sensitive operations
- Geo scope: optional, depends on operating model
- Service scope: often required
- Organization membership: usually internal organization

## Recommended constraints and indexes

- `people(id)` as UUID PK
- unique index on `roles(code)`
- unique index on `permissions(code)`
- unique composite index on `role_permissions(role_id, permission_id)`
- unique composite index on active `auth_identities(identity_type, identity_value_normalized)`
- unique composite index on active `person_service_scopes(person_id, service_id)`
- unique composite index on active `organization_memberships(person_id, organization_id, membership_type)`
- partial unique index for one active primary identity per person
- partial unique index for one active primary factor per factor family if desired

## Recommended implementation order

### Phase 1: people and roles foundation

1. `people`
2. `customer_profiles`
3. `provider_profiles`
4. `staff_profiles`
5. `roles`
6. `person_role_assignments`
7. `service_definitions`
8. `person_service_scopes`
9. `geo_scopes`
10. `person_geo_scopes`

### Phase 2: organizations

1. `organizations`
2. `organization_memberships`

### Phase 3: auth foundation

1. `auth_identities`
2. `auth_factors`
3. `auth_challenges`
4. `auth_sessions`
5. `auth_policies`

### Phase 4: permission hardening

1. `permissions`
2. `role_permissions`

## Final recommendation

For Daryeel 2, the most industry-aligned structure is:

- **one root `people` table**
- **profile tables per top-level type**
- **dedicated auth tables for identities, factors, challenges, and sessions**
- **catalog-based roles and permissions**
- **explicit geo, service, and organization scope tables**

This keeps customers scalable, providers governable, and staff secure without locking the platform into an OTP-only or single-role design.
