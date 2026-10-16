# fwvip-i2c

`fw-proto-i2c` (signal-level protocol kit, vendored under `packages/`) +
`fwvip-i2c` (the UVM class-layer VIP built on top of it) for I2C
(NXP/Philips UM10204), following the two-package split used by
`fwvip-chi`/`fw-proto-chi` and `fwvip-wb`/`fw-proto-wb`.

**Status:** controller, target and monitor agents, an EEPROM-style memory
responder and a back-to-back UVM bench (six cases, all passing). 7-bit
addressing only; repeated START is not usable yet (a kit target-core gap).

```sh
dfm run tests        # every UVM case
dfm run smoke        # what CI runs on every push
dfm run docs         # Sphinx, warnings as errors
```

See [`docs/design.md`](docs/design.md) for the design,
[`skills/fwvip-i2c-usage/SKILL.md`](skills/fwvip-i2c-usage/SKILL.md) for
how to wire and drive the agents, and [`docs/`](docs/) for the
user-facing documentation (not yet updated for the UVM layer).

Setup note: fw-hdl's dfm plugin is not installed by `ivpm update`; install
it once with `uv pip install --python packages/python/bin/python -e
packages/fw-hdl/python` (see `ivpm.yaml`).
