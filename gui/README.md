# EROS Configurator (GUI)

A thin **PySide6** front-end over the `erosgen` engine (`tools/erosgen/`). It
holds **zero domain logic** — every fact (validation, diagnostics, RTE
resolution, code generation, MCU profiles) comes from the engine. If a rule
isn't in `erosgen`, it isn't in the GUI.

```sh
uv run --extra gui python -m gui [path/to/app.yaml]
```

## What it does

- **Project tree** (left): system + MCU, tasks, models (with each port's
  binding), and the pre-flash **static-RAM budget** (kernel / pool / rings /
  free) — the "see RAM before you flash" figure the report prints.
- **Live diagnostics** (right): the engine's `collect_diagnostics()` +
  model port-binding checks, as a colour-coded problem list that updates on
  every edit (e.g. `PIN_CONFLICT`, `UNKNOWN_MCU`, `TYPE_TOO_NARROW`,
  `PORT_NO_DRIVER`, `HARMONIC`).
- **Build console** (bottom): streams `make` via `QProcess`.
- **Menus**
  - **File** — New Project… · Open… · Save · Save As… · Generate · Build
  - **Edit** — Add Task… · Remove Selected Task
  - **Model** — Add Model from codegen… (parses a `<model>_ert_rtw` dir and
    lists its signals) · Bind Port… (bind a signal to `adc`/`dio`/`pwm`)
  - **MCU selector** (toolbar) — retarget live; diagnostics + budget re-derive
- **YAML** is round-tripped with `ruamel.yaml`, so comments and key order
  survive a Save (flow-map inner spacing may normalize — a ruamel default, not
  comment loss).

## Not included

- **Signal→signal wiring between tasks/models** (one model's output to
  another's input). The engine has no model-to-model connection concept —
  cross-rate signals are the hand-written `asw_signals` layer — so there is no
  menu for it; it would be a new engine feature, not just a GUI one.

## Layout & tests

```
gui/
  __init__.py     puts tools/ on the path for `import erosgen`
  project.py      ProjectModel — the pure, Qt-free bridge (load/save/edit,
                  diagnostics, budget, model parsing + port binding, generate)
  main_window.py  the two-pane MainWindow (a view over ProjectModel)
  __main__.py     `python -m gui` entry point
  test_gui.py     11 tests, run headless under Qt's offscreen platform
```

```sh
QT_QPA_PLATFORM=offscreen uv run --extra gui python -m pytest gui/test_gui.py
```

The CI `gui` job runs exactly that.
