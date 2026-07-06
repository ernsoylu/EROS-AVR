# app.yaml JSON Schema

`app.schema.json` (JSON Schema **draft 2020-12**) is the versioned, declarative
contract for an erosgen `app.yaml`. It captures the **static** surface only:

- section key sets (`additionalProperties: false`),
- value types, and
- MCU-independent enums/consts (`tick_hz` = 1000, `spi.mode`/`clock`,
  `adc.reference`/`prescaler`, `uart` ring sizes, `pool` sizes, `gpio.dir`).

Cross-field and MCU/F_CPU-dependent rules — pin ownership, schedulability,
resource ceilings, PWM/I²C frequency ranges, peripheral availability — stay in
the code validators (`model.py`) and report through the same `Diagnostics`
sink. Each constrained node carries an `x-eros-code` annotation naming the
diagnostic code a violation maps to, so schema and code share one vocabulary.

## One source of truth

The schema is plain JSON, so it is loaded with the stdlib (no third-party dep)
and **drives `validate.ALLOWED_KEYS`** (`schema.section_keys()`). Adding a
peripheral parameter or section key is a single edit here;
`test_allowed_keys_derived_from_schema_matches_contract` pins the mapping.

## Running full validation

The dep-free key check always runs. Running the *full* schema (all draft-2020-12
keywords) needs the `jsonschema` library, shipped as the opt-in `[schema]` extra:

```sh
uv sync --extra schema
uv run python tools/erosgen.py app.yaml --schema     # validate, then generate
```

`--schema` reports every violation with a code + dotted location and fails
(rc 1) before generating; without the extra installed it exits rc 2 with a
clear message rather than silently skipping.
