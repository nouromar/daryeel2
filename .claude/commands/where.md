---
description: Answer "where do I change X?" using docs/ai-grounding.md
argument-hint: <topic, e.g. "schema renderer" or "pharmacy actions">
---

Answer "where do I change **$ARGUMENTS**?" by consulting `docs/ai-grounding.md` (specifically its "Where do I change X?" section) plus the directory layout.

Steps:
1. Read `docs/ai-grounding.md` and locate the closest match for the user's topic.
2. If the topic is app-specific (e.g. "pharmacy cart"), also point to `apps/customer-app/lib/src/services/<service>/` and the relevant registry/dispatcher.
3. If the topic is framework/runtime, point to the `packages/*` location AND remind the user that `packages/*` edits need explicit approval per CLAUDE.md.
4. Return a tight answer: 1–3 file paths with one-line rationale each. No prose intro. If genuinely unsure, say so and suggest grep targets.
