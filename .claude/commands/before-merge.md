---
description: Pre-merge checklist — analyze, tests, packages/* guardrail, generated artifacts, schema validity
---

Run a pre-merge audit on the current branch's uncommitted + committed-since-main changes. Report a single punch list: PASS / FAIL / WARN per item, with file pointers for any failure.

Checks (run independent ones in parallel):

1. **Analyze + tests** — invoke the `/run-checks` workflow logic for changed apps/packages.
2. **`packages/*` guardrail** — `git diff --name-only main...HEAD` and `git status --short`. If any path under `packages/*` is modified, FAIL with the file list and remind the user that `packages/*` changes need explicit approval per CLAUDE.md.
3. **Generated artifacts** — fail if any of these are staged or committed: `build/`, `.dart_tool/`, `ios/Pods/`, `*/Flutter/ephemeral/`, `android/local.properties`, `*.iml`.
4. **Schema validity (light)** — for any modified `*.screen.json` or `*.fragment.json`, confirm it's valid JSON (`python3 -c 'import json,sys; json.load(open(sys.argv[1]))' <path>`). Don't validate against contracts here — that's the schema-service's job.
5. **Tracked secrets** — grep diff for accidental `.env`, `*.pem`, `*.key`, `key.properties`. WARN if any match.
6. **Route prefix sanity** — if `services/api` is touched, confirm new routes follow the `/v1/<service>/...` convention.

End with a one-line verdict: **READY TO MERGE** or **BLOCKED** + the top blocker.
