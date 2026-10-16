# fwvip-i2c — I2C Verification IP

`fwvip-i2c` is the UVM Verification IP for I2C (NXP/Philips UM10204): the
methodology layer over the `fw-proto-i2c` transactor kit (vendored under
`packages/`). See {doc}`design` for the full design rationale.

```{admonition} Status
:class: note
The kit and the UVM layer (controller, target and monitor agents, a
memory responder, a back-to-back bench) are implemented; these pages are
not yet updated to describe them. See {doc}`open-issues` and
{doc}`design` §8.
```

## Where to start

- {doc}`getting-started` — build and run (once there is something to run).
- {doc}`integration` — how to wire the controller/target/monitor agents into a bench.
- {doc}`sequences` — the transaction item and sequences.
- {doc}`reference` — constants, link presets and classes.
- {doc}`verification` — what is tested, and what testing found.
- {doc}`open-issues` — open design questions carried over from `design.md` §8.

```{toctree}
:maxdepth: 2
:hidden:

getting-started
integration
sequences
reference
verification
open-issues
design
```
