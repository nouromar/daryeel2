---
description: Run flutter analyze + flutter test for apps/packages with uncommitted changes
---

Determine which Flutter apps/packages have uncommitted changes, then run `flutter analyze` and `flutter test` in each affected directory.

Steps:
1. Run `git status --short` to list modified paths.
2. Map each modified path back to its owning Flutter package — i.e. the nearest ancestor directory containing a `pubspec.yaml`. Common roots: `apps/customer-app`, `apps/provider-app`, `packages/flutter_*`, `packages/schema_runtime_dart`.
3. For each unique owning package, run `flutter analyze` and `flutter test` from that directory. Run independent packages' commands in parallel via separate Bash calls in one message.
4. Report a compact summary: package → pass/fail, and surface any analyzer warnings or failing tests verbatim.
5. If a `packages/*` directory shows uncommitted changes, flag it — the user has a hard rule against unapproved `packages/*` edits.

Skip directories that have no `pubspec.yaml` (e.g. `docs/`, `apps/admin-ops-web` if it's a non-Flutter web app, schema JSON edits with no Dart change).
