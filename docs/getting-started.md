# Getting started

## Set up

```sh
ivpm update            # fetch the dev dep-set into packages/
direnv allow           # or: source .envrc (puts packages/python, verilator, ... on PATH)
```

fw-hdl's dfm plugin lives below the fw-hdl repo root, so `ivpm update` does
not install it. Install it once:

```sh
uv pip install --python packages/python/bin/python -e packages/fw-hdl/python
```

## Run

`flow.yaml` builds on the `project.dv.uvm` archetype, so the standard verbs
apply:

```sh
dfm run tests                    # every back-to-back UVM case (Verilator)
dfm run tests --tests stretch    # one case
dfm run smoke                    # what CI runs on every push: smoke, mon_teeth
dfm run tests-info               # the case inventory, building nothing
dfm run docs                     # these pages; sphinx-build -W, so a warning fails
```

The seven cases are described in {doc}`verification`. Two plusargs help when
one fails:

`+fwvip_i2c_mon_trace`
: the monitor agent prints every transaction it reconstructs.

`+fwvip_i2c_bus_trace`
: the bench's HDL top prints every change on SCL/SDA and on each
  transactor's `*_oe`.

## The kit

The transactors are `fw-proto-i2c`'s, vendored under
`packages/fw-proto-i2c`. It has its own tests (a back-to-back sim, a
two-controller arbitration sim, a formal harness); run them from that
directory:

```sh
cd packages/fw-proto-i2c
dfm run tests          # i2c_proto, i2c_arb
dfm run fv             # back-to-back BMC (see its tests/formal/PROPERTIES.md)
```

## Using the VIP from another project

Fetch the `use` dep-set (the kit and fwvip-core) and depend on
`org.fwvip.i2c.vip-uvm-hvlsrc` in your flow. A bench also needs
`org.fwvip.core.clock-reset-xtor` for the clock and reset providers. Wiring
is in {doc}`integration`.
