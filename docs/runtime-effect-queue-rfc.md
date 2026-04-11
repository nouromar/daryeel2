---
description: "RFC: phase-safe runtime effect queue for submit_form and other async action completions"
status: draft
owner: schema-runtime
last_updated: 2026-04-11
---

# RFC: Runtime Effect Queue for Phase-Safe Async Actions

## Summary

This RFC proposes a runtime-owned effect model that prevents app and runtime code from mutating reactive state or triggering UI side effects at unsafe points in the Flutter frame lifecycle.

The immediate trigger is the pharmacy checkout submit flow, where a successful submit cleared shared cart state and popped the checkout route in the same async completion. That produced repeated Flutter exceptions:

- `setState() or markNeedsBuild() called during build`

The app-level mitigation is already in place in customer-app, but the root issue is broader than checkout. The current runtime contract allows any async handler to:

- mutate shared state after an async gap
- set field errors after an async gap
- show a snackbar after an async gap
- navigate after an async gap

without a framework-owned, phase-safe commit boundary.

This RFC moves those side effects into a runtime effect queue so the framework, not each app handler, controls when effects are applied.

## Problem Statement

### Current behavior

Today, `submit_form` works like this:

1. Runtime validates the form.
2. Runtime sets `isSubmitting = true`.
3. Runtime calls `SubmitFormHandler.submit(BuildContext context, SubmitFormRequest request)`.
4. Handler does network work and may also mutate state, navigate, and show UI messages.
5. Runtime resumes and sets field errors and `isSubmitting = false`.

Current contract location:

- `packages/flutter_runtime/lib/src/actions/submit_form_dispatcher.dart`

This contract is too permissive for async flows because it exposes a `BuildContext` and does not define a safe effect-application phase.

### Why this fails

Async handlers often resume while Flutter is still processing route transitions, listener rebuilds, overlay changes, or parent widget updates. If the handler immediately performs one or more of these operations:

- `SchemaStateStore.setValue(...)`
- `SchemaStateStore.removeValue(...)`
- `SchemaFormStore.setFieldErrors(...)`
- `Navigator.pop(...)`
- `ScaffoldMessenger.showSnackBar(...)`

then multiple reactive listeners may be dirtied during an active build/transition frame.

### Root design issue

The bug is not pharmacy-specific. The root issue is that runtime and app code currently mix three concerns in the same async completion:

1. business outcome
2. state mutations
3. UI side effects

The framework needs an explicit post-completion effect phase.

## Goals

- Prevent `markNeedsBuild during build` style bugs from async action completions.
- Keep apps thin by moving frame-safety rules into shared runtime code.
- Replace imperative post-submit UI work with declarative effect results.
- Apply effects in a deterministic order.
- Support batching of multiple related state updates.
- Keep existing schema contracts stable where possible.
- Provide a migration path from current `SubmitFormHandler` implementations.

## Non-goals

- This RFC does not redesign the schema language for `submit_form`.
- This RFC does not introduce arbitrary scripting or general-purpose workflow engines.
- This RFC does not require backend contract changes.
- This RFC does not require immediate migration of every runtime action type on day one.

## Design Principles

1. Async handlers return intent, not imperative UI work.
2. Runtime owns the commit phase for all reactive mutations and UI effects.
3. Multiple state writes should be batched into one logical flush when possible.
4. Effects must have explicit ordering.
5. The first implementation should solve `submit_form`, but the abstraction should be reusable by other async actions.

## Proposed Design

## 1. Introduce a Runtime Effect Model

Add a shared runtime effect type owned by `packages/flutter_runtime/`.

Illustrative shape:

```dart
sealed class RuntimeEffect {
  const RuntimeEffect();
}

final class SetStateEffect extends RuntimeEffect {
  const SetStateEffect({required this.path, required this.value});
  final String path;
  final Object? value;
}

final class RemoveStateEffect extends RuntimeEffect {
  const RemoveStateEffect({required this.path});
  final String path;
}

final class PatchStateEffect extends RuntimeEffect {
  const PatchStateEffect({required this.ops});
  final List<StatePatchOperation> ops;
}

final class SetFieldErrorsEffect extends RuntimeEffect {
  const SetFieldErrorsEffect({required this.formId, required this.errors});
  final String formId;
  final Map<String, String> errors;
}

final class ClearFieldErrorsEffect extends RuntimeEffect {
  const ClearFieldErrorsEffect({required this.formId});
  final String formId;
}

final class ShowMessageEffect extends RuntimeEffect {
  const ShowMessageEffect({required this.message, this.level = MessageLevel.info});
  final String message;
  final MessageLevel level;
}

final class PopRouteEffect extends RuntimeEffect {
  const PopRouteEffect();
}

final class PushNamedRouteEffect extends RuntimeEffect {
  const PushNamedRouteEffect({required this.routeName, this.arguments});
  final String routeName;
  final Object? arguments;
}
```

Notes:

- The first runtime slice does not need every effect type above, but it should define the common abstraction now.
- `submit_form` only needs a small subset initially: field errors, state changes, message, pop route.

## 2. Introduce a Runtime Effect Queue

Add a queue owned by the runtime layer that:

- accepts effects from async action completions
- schedules a safe flush after the current frame
- guarantees exactly one pending flush for a burst of effects
- applies effects in order

Illustrative API:

```dart
abstract interface class RuntimeEffectQueue {
  void enqueueAll(List<RuntimeEffect> effects);
  void flushNowIfSafe();
}
```

### Scheduling rule

Default rule:

- if effects come from an async completion, enqueue them and flush in `addPostFrameCallback`
- ensure a frame exists via `scheduleFrame()` if no frame is pending

This makes the current app-level checkout fix a runtime primitive instead of a one-off workaround.

## 3. Add a Batched State Mutation API

The runtime state store currently notifies listeners per mutation. For checkout-like completions, that creates unnecessary intermediate rebuilds.

Add a batched mutation entry point to `SchemaStateStore`:

```dart
store.batch((tx) {
  tx.setValue('pharmacy.cart.lines', const <Object?>[]);
  tx.setValue('pharmacy.cart.totalQuantity', 0);
  tx.setValue('pharmacy.cart.hasRxItem', false);
  tx.removeValue('pharmacy.cart.prescriptionUploads');
  tx.removeValue('pharmacy.checkout');
});
```

Behavior:

- all mutations are applied atomically to store state
- listeners are notified once after the batch completes
- nested batches collapse into one notification

This is useful even outside submit handling.

## 4. Replace Imperative Submit Success Work with Declarative Results

### Current contract

```dart
abstract class SubmitFormHandler {
  Future<SubmitFormResponse> submit(
    BuildContext context,
    SubmitFormRequest request,
  );
}
```

### Proposed contract

Replace the `BuildContext`-driven contract with a runtime-owned context plus declarative effects.

```dart
final class SubmitFormContext {
  const SubmitFormContext({
    required this.formId,
    required this.formValues,
    required this.stateSnapshot,
    required this.apiBaseUrl,
    required this.requestHeaders,
  });

  final String formId;
  final Map<String, Object?> formValues;
  final Map<String, Object?> stateSnapshot;
  final String apiBaseUrl;
  final Map<String, String> requestHeaders;
}

final class SubmitFormResult {
  const SubmitFormResult({
    required this.ok,
    this.message,
    this.fieldErrors = const <String, String>{},
    this.effects = const <RuntimeEffect>[],
  });

  final bool ok;
  final String? message;
  final Map<String, String> fieldErrors;
  final List<RuntimeEffect> effects;
}

abstract class SubmitFormHandler {
  const SubmitFormHandler();

  Future<SubmitFormResult> submit(SubmitFormContext context);
}
```

### Why remove `BuildContext`

`BuildContext` is the main escape hatch that lets handlers do imperative UI work at unsafe times. Removing it from the primary contract forces handlers to express outcomes declaratively.

## 5. Dispatcher Behavior

`SubmitFormSchemaActionDispatcher` becomes responsible for four phases:

1. validate form
2. mark submitting
3. await handler result
4. enqueue and flush effects safely

Proposed flow:

```dart
validate form
setSubmitting(true)
await handler.submit(...)
enqueue:
  - field error effects
  - handler returned effects
  - setSubmitting(false)
flush after frame
if !ok: surface failure after queued effects are applied
```

### Effect ordering

Effects should be applied in this order:

1. form effects
   - field errors
   - submitting false
2. shared state effects
3. query invalidation effects if introduced later
4. message effects
5. navigation effects

Rationale:

- form state should settle before navigation or route disposal
- shared state should reach the final post-submit shape before any destination screen becomes visible
- messages should attach to the current messenger before the route is popped if needed
- navigation should be the last visible transition

## 6. Backward-Compatible Migration Plan

We should not break current apps abruptly.

### Phase 1

Add the effect queue and batch support first.

- keep the old submit handler signature temporarily
- update dispatcher internals to defer its own post-await mutations
- document that app handlers should avoid direct state writes and navigation after await

### Phase 2

Add a new v2 contract alongside the old one.

Example:

- `SubmitFormHandler` remains legacy
- `SubmitFormHandlerV2` returns `SubmitFormResult`

Dispatcher preference:

- use v2 if provided
- fall back to legacy handler otherwise

### Phase 3

Migrate app handlers.

For customer-app pharmacy checkout, replace:

- direct store mutations
- direct snackbar usage
- direct navigator pop

with returned effects:

```dart
return SubmitFormResult(
  ok: true,
  effects: const <RuntimeEffect>[
    SetStateEffect(path: 'pharmacy.cart.lines', value: <Object?>[]),
    SetStateEffect(path: 'pharmacy.cart.totalQuantity', value: 0),
    SetStateEffect(path: 'pharmacy.cart.hasRxItem', value: false),
    RemoveStateEffect(path: 'pharmacy.cart.prescriptionUploads'),
    RemoveStateEffect(path: 'pharmacy.checkout'),
    ShowMessageEffect(message: 'Order submitted'),
    PopRouteEffect(),
  ],
);
```

### Phase 4

Deprecate the legacy `BuildContext`-based handler API.

## 7. Scope of the First Implementation

To keep the first package change small, the initial runtime implementation should cover:

- `submit_form` only
- runtime effect queue
- state store batching
- effect types:
  - set/remove state
  - set/clear field errors
  - show message
  - pop route

This is enough to eliminate the current class of bug without overdesigning a general workflow system.

## 8. Validation Strategy

Implementation of this RFC touches `packages/*`, so it requires explicit approval before coding. Once approved, validation should be mandatory at both runtime-package and app-integration levels.

### Required runtime validation

Run in the relevant package folders:

- `flutter test`
- `flutter analyze`

At minimum:

- `packages/flutter_runtime`
- `packages/flutter_daryeel_client_app` if messenger/navigation integration lives there

If any shared component or renderer behavior changes indirectly, also run:

- `packages/flutter_components/flutter test`
- `packages/flutter_schema_renderer/flutter test`

### Required app validation

Run in affected apps:

- `apps/customer-app/flutter test`
- `apps/customer-app/flutter analyze`

If provider-app shares the same runtime shell behavior and any wiring changes affect it, also run:

- `apps/provider-app/flutter test`
- `apps/provider-app/flutter analyze`

## 9. Testing Plan

### Unit tests in `packages/flutter_runtime`

Add focused tests for:

1. effect queue defers flush until post-frame
2. queued effects schedule a frame when needed
3. multiple enqueues before flush collapse into one flush
4. effect ordering is stable
5. state batch emits one listener notification
6. nested state batches emit one final notification
7. submit dispatcher enqueues `setSubmitting(false)` instead of applying it immediately after await
8. submit dispatcher applies field errors through effects

### Widget tests in shared runtime/client packages

Add widget tests for:

1. submit success with `ShowMessageEffect + PopRouteEffect` does not throw `markNeedsBuild during build`
2. submit success with multiple state clear effects updates dependent widgets only after flush
3. submit failure with field errors leaves the route in place and clears submitting state safely
4. legacy handler compatibility still works during migration

### App regression tests in `apps/customer-app`

Keep and adapt the existing pharmacy checkout regression test so it verifies:

1. submit returns success
2. cart state is not cleared synchronously in the same completion
3. deferred flush clears cart and checkout state
4. route pops after flush
5. snackbar shows after successful submit
6. no framework exception is thrown

### Manual validation

Manual run checklist in customer-app:

1. add pharmacy items to cart
2. open checkout
3. submit order
4. confirm checkout closes cleanly
5. confirm cart screen shows final empty state without console exceptions
6. confirm app bar cart badge updates once to zero
7. confirm success snackbar appears exactly once

### Negative-path validation

Manual and automated tests should also cover:

1. API failure leaves checkout open
2. API failure does not clear cart state
3. field errors render without route pop
4. double-tap submit still respects in-flight protection

## 10. Risks and Tradeoffs

### Pros

- fixes a real class of runtime bugs at the correct layer
- reduces app-specific lifecycle knowledge
- makes async action results easier to reason about
- creates a reusable foundation for other async handlers

### Cons

- requires shared runtime API changes in `packages/*`
- introduces a migration period with dual contracts
- navigation and messenger effects need careful ownership boundaries

### Main risk

If the effect list grows without discipline, it can become a second action engine. Keep the initial effect surface intentionally small and only expand when concrete product flows require it.

## 11. Recommended Implementation Order

1. Add `SchemaStateStore.batch(...)` and tests.
2. Add runtime effect types and effect queue with tests.
3. Update `submit_form` dispatcher to use queued post-await runtime effects internally.
4. Add v2 submit handler contract that returns effects.
5. Migrate customer-app pharmacy checkout to v2.
6. Keep legacy support until at least one app cycle validates the new path.

## 12. Decision

Recommended direction:

- treat this as a runtime/framework change, not an app-by-app pattern
- implement first for `submit_form`
- keep the effect surface small
- require shared package validation and one app-level regression before rollout

This gives the framework a single, enforceable answer to the class of bug represented by the checkout issue, instead of relying on each app handler to remember Flutter frame-safety rules.