# schema-contracts

Machine-readable definitions for Daryeel2 schema documents.

Examples: screen schemas, refs, actions, bindings, and visibility rule models.

## Validation

Run the full validation/lint pass against `examples/` via schema-service:

```bash
cd Daryeel2/services/schema-service
pyenv exec python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m app.validate_all
```
