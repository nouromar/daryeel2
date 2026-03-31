# schema_runtime_ts

Pure TypeScript schema runtime core for Daryeel2.

This package owns:
- Typed schema nodes (`SchemaNode`, `ComponentNode`, `RefNode`)
- Parsing helpers (`parseScreenSchema`, `parseFragmentSchema`, ...)
- Reference resolution (`resolveScreenRefs`)

It is framework-agnostic (usable by Angular, Node, etc.).
