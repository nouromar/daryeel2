# Skills (AI Playbooks)

This folder contains short, high-signal “skills” that capture *how we do things in this repo*.

These docs are designed for both humans and Copilot:
- They’re concrete (copy/paste snippets)
- They focus on the repo’s actual runtime behavior and conventions
- They avoid speculative/aspirational features

## Index

- [Expression Engine](expression-engine.md)
- [Schema Screen Authoring](schema-screen.md)

## How to add a new skill

1. Create a focused doc in `docs/` (or link to an existing one).
2. Add it to the index above.
3. If it should be consulted frequently, add a pointer in:
   - `.github/copilot-instructions.md` (preferred)
   - `docs/ai-grounding.md` (optional)
