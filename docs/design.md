# fwvip-i2c Design Document

Status: draft for review
Scope: `fw-proto-i2c` (signal-level protocol kit) + `fwvip-i2c` (UVM class-layer
VIP built on top of it), following the two-package split used by
`fwvip-chi`/`fw-proto-chi`, `fwvip-wb`/`fw-proto-wb`, and `fw-proto-uart`.

## 1. Background and references

- Protocol reference: NXP/Philips **UM10204 I2C-bus specification and user
  manual**.
- Register-level reference core: **freecores/opencores `i2c`**
  (`i2c_master_top` / `i2c_master_byte_ctrl` / `i2c_master_bit_ctrl`), a
  WISHBONE-attached I2C master. Used here only as a *second opinion* on what a
  real controller's bit/byte FSMs look like — the VIP itself is pin-level
  (SDA/SCL), not tied to this or any register map (see §7).
- Architecture pattern: `packages/fw-hdl/skills/fw-proto-kit/SKILL.md`
  (present in `fwvip-chi`, `fwvip-wb`) — roles (initiator/target/monitor), the
  six per-role elements, the interface↔core ready/valid link convention, and
  the mandatory back-to-back sim + formal components. (`fwvip-spi` predates
  this pattern — it still vendors an older `fwvip-wb` copy with its own
  `_formal_tb.sv`/`*_tb.sv` naming, not the kit's `_xtor_core.sv`/`_fv.sv`
  convention — so it is not cited as precedent here.)
- Sibling kits reviewed for precedent: `fw-proto-wb` (single req/rsp stream,
  closest in shape to an I2C byte transfer) and `fw-proto-uart` (an
  asynchronous serial point-to-point protocol with its own bit-timing
  generator — the closest existing analog to I2C's wire-level clocking).
- UVM class-layer precedent: `fwvip-chi`'s agent/driver/sequence/config_db
  structure and its L1 (flit-level) vs. requester/completer (transaction-level)
  split.

## 2. What makes I2C different from the existing kits

| Property | ready/valid (example) | Wishbone | UART | **I2C** |
|---|---|---|---|---|
| Clock | shared system clock | shared system clock | none (async, oversampled) | **shared, but wire-level and bidirectional** (SCL) |
| Data line | push/pull | push/pull | push/pull, point-to-point | **open-drain, shared, bidirectional** (SDA) |
| # of masters | 1 fixed role | 1 fixed role | 1 fixed role (TX side) | **multi-master**, arbitration required |
| Addressing | none | memory address | none | **7-bit / 10-bit target address on the bus itself** |
| Flow control | ready/valid | none (single outstanding) | none (framing only) | **clock stretching**: a target holds SCL low |
| Framing | — | — | start/stop bit, parity | **START/Sr/STOP conditions as SDA transitions while SCL high** |

Three design problems fall out of this that none of the existing kits solve
directly, and are the crux of the fw-proto-i2c design:

1. **SCL is not a free-running clock the core can sample on — it is a signal
   the core itself drives (as initiator) or monitors (as target), and must
   also *sense being driven low by someone else*** (clock stretching,
   synchronization). This breaks the usual "everything is clocked off `clock`"
   assumption at the pin boundary: `clock`/`reset` still drive the *internal*
   FSM (design rule 1 from the kit skill still applies to the core's own
   logic), but SCL/SDA are modeled as `inout`-like tri-state pairs
   (`scl_o`/`scl_oe`/`scl_i`, `sda_o`/`sda_oe`/`sda_i` — the same pad-enable
   convention the freecores core uses, §7) oversampled by `clock` the way
   `fw-proto-uart`'s receiver oversamples `rxd` (§5.1 of that core) — but here
   oversampling BOTH edges of SCL as driven by the *other* side, not just a
   data line.
2. **The initiator role must arbitrate against other initiators and must be
   able to lose mid-byte.** No existing kit's core has a "bail out, someone
   else owns the bus now" transition. This is new FSM shape, not a
   parameter tweak.
3. **The target role must be able to stretch the clock (assert backpressure
   onto SCL itself)**, which no existing target core does (Wishbone's target
   has no wire-level clock to hold; UART has no backpressure at all). This
   makes the I2C target core's "ready" signal partly a *bus-level* action
   (driving SCL low), not just an internal FIFO condition.

## 3. Stream decomposition

Per the kit's "decompose into independent activity streams" rule: I2C is
**one bus**, but it does **not** decompose the way Wishbone/AXI do (parallel
channels). It decomposes along **roles that contend for a single shared
half-duplex channel**:

- **Controller (initiator) stream**: one request/response pair per
  *transaction* = START + (addr7/addr10 + R/W) + N data bytes (each with
  ACK/NACK) [+ repeated START + address + more bytes]* + STOP. Unlike
  Wishbone's one-beat-per-request, an I2C "access" is a **multi-byte framed
  sequence with an internal ACK/NACK decision point after every byte** —
  closer in shape to UART's byte framing (start/data/stop bits) composed with
  Wishbone's request/response blocking, but framed at the **transaction**
  level, not the byte level, because repeated-START lets a controller change
  direction mid-transaction without releasing the bus.
- **Target (responder) stream**: mirror side — receives address match
  (filtered at the class layer against a configured address/mask, see §6),
  then streams bytes in the direction the R/W bit selected, choosing ACK/NACK
  per byte (or per the model under test, for a DUT target).
- **Monitor stream**: taps SDA/SCL and reconstructs START/Sr/STOP, address +
  R/W, each data byte + ACK/NACK, and arbitration-loss/clock-stretch events,
  republishing one beat per **byte** (plus synthesized START/STOP/Sr markers)
  — matching the kit's "monitor republishes one beat through a port" shape,
  with the beat granularity set at byte-with-metadata rather than raw bit.

So: **one stream, but framed at transaction granularity with a byte-level
sub-FSM**, rather than N independent parallel streams. The `access()`-style
single task from `wb_proto_if` is not quite enough on its own (a transaction
is N bytes, not one beat); the API needs an UART-like start/data/stop framing
composed with Wishbone-like per-byte blocking acknowledgement. See §4.

## 4. Proposed `fw-proto-i2c` APIs (class layer)

Two role APIs, **per-byte** rather than whole-transaction (revised from an
earlier whole-segment `segment()`/`data_phase()` draft): each task moves
exactly one byte-sized unit across the bus and returns, mirroring the kit's
"one stream ⇒ one task" rule and `uart_tx_if`/`uart_rx_if`'s
`tx`/`rx`-per-byte shape more directly than `wb_proto_if`'s single blocking
`access()`. A sequence composes `start()`/`tx_byte()`/`rx_byte()`/`stop()`
calls into a transaction at the class layer (mirrors `fwvip_chi_rn_seq_base`
composing low-level calls — see fwvip-chi precedent in the UVM layer, §6);
repeated-START is just another `start()` call before `stop()`.

```systemverilog
// Controller-side API (initiator role). Parameter order, blocking tasks,
// `FW_I2C_<ROLE>_IMP` macro per the kit convention.
interface class i2c_controller_if;
    // Drives START (or Sr if the bus is already owned by this caller --
    // `repeated` selects which) and the address+R/W byte. Returns the
    // ACK/NACK for the address byte and whether arbitration was lost
    // acquiring/re-asserting the bus (caller must abandon the whole
    // transaction and retry per spec, not resume mid-byte).
    pure virtual task start(
            input  bit [9:0] addr,       // 7b stored right-justified; 10b flag separate
            input  bit       addr_10b,
            input  bit       read,       // R/W bit
            input  bit       repeated,   // Sr instead of S
            output bit       ack,
            output bit       arb_lost);

    // One byte in the write direction (this role is sending). Returns the
    // target's ACK/NACK and whether arbitration was lost driving this byte.
    pure virtual task tx_byte(
            input  bit [7:0] data,
            output bit       ack,
            output bit       arb_lost);

    // One byte in the read direction (this role is receiving). `ack` is an
    // INPUT here: per spec it is the MASTER that decides whether to keep
    // reading -- ack=1 requests another byte, ack=0 NACKs (this is the last
    // byte wanted) -- so the caller supplies it before the byte clocks in.
    pure virtual task rx_byte(
            input  bit       ack,
            output bit [7:0] data,
            output bit       arb_lost);

    // Terminates the transaction (STOP). Separate from start()/tx_byte()/
    // rx_byte() so a sequence can chain further start() calls (repeated
    // START) before releasing the bus.
    pure virtual task stop();
endclass

// Target-side API (completer role). The bridge calls into a model once per
// address phase and once per data byte; the model drives ACK/NACK and (for
// reads) data. Clock-stretch delay is a bridge/core concern (see core notes
// below), not exposed in this call -- matches the kit's "transactor hides
// the wire-level mechanics, the class API stays in the protocol's logical
// vocabulary" rule.
interface class i2c_target_if;
    // Called once a START/Sr + address phase matches this target's
    // configured address/mask. read selects the direction of the tx_byte/
    // rx_byte calls that follow.
    pure virtual task addressed(input bit [9:0] addr, input bit addr_10b,
                                 input bit read, output bit ack);

    // One byte in the write direction (controller is sending): data is the
    // byte received, the target returns its ACK/NACK.
    pure virtual task rx_byte(output bit [7:0] data, output bit ack);

    // One byte in the read direction (controller is receiving): the target
    // supplies data; ack comes back as an INPUT from the controller's
    // decision on THIS byte -- the target has no advance knowledge of when
    // the read ends, since per spec it is the MASTER that decides by
    // NACKing the last byte it wants, not the target. The bridge calls
    // tx_byte() again only if ack=1.
    pure virtual task tx_byte(output bit [7:0] data, input bit ack);
endclass
```

Monitor API (non-blocking, per kit rule): `observe_start()`,
`observe_repeated_start()`, `observe_stop()`,
`observe_byte(addr_phase, data, ack, nack)`, `observe_arb_lost()`.

## 5. Transactor layer (signal level)

### Pins
`scl_i`/`scl_o`/`scl_oe`, `sda_i`/`sda_o`/`sda_oe` per role instance — the
open-drain pad convention from freecores' `i2c_master_top` (§7), wired at the
testbench level the same way: `assign scl = scl_oe ? 1'bz : scl_o; assign
scl_i = scl;` (and SDA likewise), with pull-ups modeled in the top-level bus
wrapper, not in any transactor. **Both roles drive and sense both lines** —
unlike every existing kit, there is no fixed "driver owns the output" split;
`scl_oe`/`sda_oe` can both be asserted by multiple instances simultaneously,
which is the whole point (wired-AND) and must be modeled as such in the
back-to-back test bus (a true multi-driver net or an explicit AND-reduction
of `_o when _oe else 1` across all connected instances).

### Controller core (`i2c_controller_xtor_core.sv`)
A clocked FSM oversampling SCL/SDA at a configurable tick rate (parameter,
analogous to `fw-proto-uart`'s `OVERSAMPLE`/`cfg_divisor`, but here the core
itself *generates* SCL high/low timing when it owns the bus, rather than only
sampling). States (naming informed by, but not copied from, the freecores
bit-controller): `IDLE`, `ARB_START` (drive SDA 1→0 while SCL is high),
`CLK_LOW`/`CLK_HIGH` per bit (shift `addr`/`data`/`ack` bits MSB-first),
`ARB_CHECK` (every bit this core drives low-impedance-high, it must sample
`sda_i` back and compare — mismatch while driving high ⇒ **arbitration
lost**, abandon the current segment, release bus, report `arb_lost`),
`CLK_STRETCH_WAIT` (after this core releases SCL high, wait for `scl_i` to
actually read high before counting the high period — this is how clock
stretching by a target, OR synchronization against another master's slower
clock, is honored; both are the *same* wait-for-SCL-high mechanism per
UM10204 §3.1.10/3.1.11), `ACK_PHASE`, `REP_START`, `STOP`. Timing parameters
(`T_LOW`, `T_HIGH`, `T_SU_STA`, `T_HD_STA`, `T_SU_STO`, `T_BUF`, ...) are
runtime `cfg_*` inputs sampled per transaction (same "held runtime
configuration" pattern as `uart_tx_xtor_core`'s `cfg_*` ports), so one core
instance covers Standard/Fast/Fast-plus by reprogramming divisors; Hs-mode and
Ultra-fast are flagged as open issues (§8). *(As built: the `T_*` values are
module parameters counted in ticks, and one runtime scalar, `prescale`, set
through `set_prescale()`, sets the tick length. See reference.md.)*

### Target core (`i2c_target_xtor_core.sv`)
Passively samples SCL/SDA to detect START/Sr/STOP (edge-on-SDA-while-SCL-high
per UM10204 §3.1.4) and to shift in address+data MSB-first, same oversampling
discipline. Drives SDA only during: its own ACK/NACK bit, and (in read
direction) its data bits — classic open-drain slave behavior. Drives **SCL
low** to clock-stretch: an explicit `stretch` state entered after sampling the
8th bit of any byte it must process before ACKing, held until the class layer
(via the bridge, blocking on the `data_phase`/`addressed` task) returns.
This is the one place in the whole kit family where a **core's readiness is
communicated onto the bus itself** rather than only through the internal
up-link `ready` — document this prominently as the kit's one true deviation
from "the core never backpressures below the internal link" (it does, but
only as literally specified by the protocol, not as an artifact of transactor
plumbing).

### Monitor core
Mirrors the target core's START/STOP/byte detection logic (shared detection
block, instantiated as read-only — never drives `_oe`), plus arbitration-loss
detection (`sda_i` low when expected high, with no local drive asserted —
i.e., inferred from bus behavior rather than from a specific initiator's own
"I was driving" state, since a monitor cannot know who was driving).

### Internal link
Per design rule 2, each core's bus-facing side still talks to its
transactor-interface over a plain ready/valid up-link carrying **one
segment's result** (controller) or **one addressed+data_phase round-trip**
(target) — the multi-byte, multi-phase complexity lives entirely in the core
FSM and the class-layer API in §4, not in the link encoding.

## 6. `fwvip-i2c` UVM class layer

Following the `fwvip-chi` precedent (agent/driver/sequencer per role, a
`*_config` object holding the kit's bridge/vif via `config_db`, an `ap`
analysis port for completed items):

- `fwvip_i2c_xact` — one transaction: segments (addr, addr_10b, read,
  repeated_start, data[]) list + overall status (completed OK / arb_lost /
  nacked-at(segment,byte)). Mirrors `fwvip_chi_xact`'s request/response split.
- Controller role: `fwvip_i2c_ctrl_config` (`i2c_controller_if` handle),
  `fwvip_i2c_ctrl_driver`, `fwvip_i2c_ctrl_agent` (`ap` of completed
  `fwvip_i2c_xact`), `fwvip_i2c_ctrl_seq_base` (`do_xact()` helper), plus
  `fwvip_i2c_write_seq`/`fwvip_i2c_read_seq`/`fwvip_i2c_rand_seq` — directly
  parallel to `fwvip_chi_rn_*`.
- Target role: `fwvip_i2c_tgt_config` (address + mask, or a list of
  addresses — general-call/10-bit awareness, see §8), `fwvip_i2c_tgt_driver`
  (implements `i2c_target_if`, calls a pluggable responder, mirroring
  `fwvip_chi_sn_driver`), `fwvip_i2c_tgt_agent`, `fwvip_i2c_mem_responder_seq`
  (an addressable byte-memory model, the I2C analog of
  `fwvip_chi_mem_responder_seq` — very common real-world target, e.g. EEPROM).
- Monitor: `fwvip_i2c_mon_config`, `fwvip_i2c_mon_agent` publishing
  reconstructed transactions (coalescing byte-level monitor beats back into
  `fwvip_i2c_xact`-shaped items) — this coalescer is new; CHI's monitor
  doesn't need one because its L1 agent already publishes flit-grain and a
  separate flow-checker (not requested here, but worth flagging, §8) does
  transaction reconstruction there.
- **No L1-equivalent layer is proposed initially.** CHI's L1 exists because
  CHI flits are the natural stand-alone unit for link-level/negative testing.
  I2C's natural stand-alone unit *is* the byte-with-ACK, which the monitor
  already exposes at that grain; a dedicated raw-bit-level agent is listed as
  an open question (§8) rather than committed to, since most negative testing
  (bad ACK, premature STOP, clock stretch starvation) can be driven from the
  transaction-level API via explicit low-level knobs on the sequence item
  instead of a parallel bit-level driver.

## 7. Relationship to the freecores/opencores reference core

The opencores `i2c_master_top` (WISHBONE regs: `PRERlo/PRERhi` prescale,
`CTR` enable/interrupt-enable, `TXR`/`RXR`, `CR` command bits
`STA/STO/RD/WR/ACK/IACK`, `SR` status `RxACK/Busy/AL/TIP/IF`) is a **specific
DUT shape** — a byte-at-a-time, interrupt/poll-driven register interface
layered over its own internal bit/byte controllers. `fwvip-i2c` must **not**
be modeled around this register map: it verifies the **pins** (SDA/SCL), so
it is equally usable against this core, against a pure hardware state
machine with no register interface, or against another vendor's controller.
The core's bit-controller FSM (`idle → START → read/write state machine →
ACK state`, divided into sub-states A/B/C/D per bit for START/Sr/STOP and
A/B/C/D/idle for read/write) is useful precedent for §5's controller-core
state shape, and its **status-bit semantics are a good checklist for what the
monitor/scoreboard must be able to observe independently of any register
model**: `RxACK` (ACK/NACK per byte), `Busy` (bus free vs. not, i.e.
START-seen vs. STOP-seen), `AL` (arbitration lost: STOP seen when not
requested, OR this core drove SDA high but sensed it low), `TIP` (transfer in
progress). If/when an I2C **DUT register-model agent** is wanted (to drive a
specific controller IP like this one through its registers while checking
what appears on the wire matches), that is a *separate*, DUT-specific
register-layer VIP consuming `fwvip-i2c`'s target/monitor side — out of scope
for this package, called out as a candidate follow-on in §8.

## 8. Open issues and opportunities (needs review)

1. **Multi-driver bus modeling for the back-to-back sim test.** The kit's
   mandatory back-to-back test wires exactly two transactors directly
   together for every other protocol; I2C's back-to-back test needs **two
   controllers and at least one target on one real wired-AND net** to
   exercise arbitration at all (without a second driver, arbitration logic in
   the controller core is untested by the kit's own required test). Need to
   decide: does the mandatory back-to-back test include a 2-controller
   arbitration scenario, or is that a separate (also mandatory, specific to
   this kit) `i2c_arb_tb`? Recommend treating it as a **second required
   back-to-back test** specific to this kit, analogous to how AXI's kit would
   need a burst-specific scenario beyond the generic one.
2. **Formal back-to-back component shape.** The kit skill's formal harness
   pattern (`free src --up link--> core --bus--> core --up link--> free
   snk`) assumes one producer core and one consumer core. For I2C the
   "cores" on the bus are a controller core and a target core talking
   open-drain, with **mutual sensing** (target stretches, controller must
   honor it; both drive SDA at different phases). The anyconst-index
   data-integrity method still applies to the byte stream, but the
   bus-contract invariants (table in the skill doc) need new rows specific to
   this protocol: START/STOP legality (never a STOP without a prior START in
   the same transaction; a repeated-START only mid-transaction), ACK timing
   (ACK bit sampled on 9th clock, not before), and the clock-low-wins
   synchronization rule. This invariant list should be written up as this
   kit's `PROPERTIES.md` before core RTL is finalized — recommend doing that
   mining pass as the very next step after this design is approved, since (per
   the skill) it drives both the sim assertions and the formal proof and is
   cheap to get wrong silently (vacuous proof risk per the skill's "teeth
   check" warning).
3. **Hs-mode (3.4 MHz) and Ultra Fast mode (5 MHz, unidirectional).**
   Hs-mode requires an 8-bit master code (`0000 1xxx`) transmitted at Fast/SM
   speed before switching to Hs timing, with no clock stretching allowed
   during Hs-mode data phases, and a different (lower) bus capacitance/timing
   profile. Ultra Fast mode is **push-pull, unidirectional, no ACK, no
   clock-stretch, no arbitration** — closer in shape to a stripped-down
   version of the UART transmitter than to the bidirectional core in §5.
   Recommend: design the core parameterizable for Standard/Fast/Fast-plus
   now (shared FSM, different timing constants), and treat Hs-mode and UFm as
   **separate, later core variants** rather than modes of the same FSM, given
   how structurally different Ufm in particular is (no ACK, no arbitration
   logic needed at all).
4. **10-bit addressing and reserved address handling.** 10-bit addressing
   needs two address bytes (`11110 addr9:8 R/W`, then `addr7:0`), and the R/W
   bit semantics on the *first* byte are special when read direction needs a
   repeated START (per UM10204 §3.1.13). Reserved 7-bit patterns
   (`0000 000` general call, `0000 001` START byte / CBUS, `0000 01x`
   different-bus, `0000 1xx` Hs master code, `1111 1xx` device ID, `1111 0xx`
   10-bit prefix) all need explicit handling in the target-address-match logic
   (§6's `fwvip_i2c_tgt_config`) — not just "any 7-bit value." Recommend the
   target config expose a reserved-address policy table rather than hoping
   test writers avoid these values, since a controller sequence item
   randomizing `addr[6:0]` freely WILL eventually hit them.
5. **SMBus compatibility.** Not requested, but SMBus devices are extremely
   common on I2C buses in practice (power management, sensors) and add: a
   bus-timeout requirement (`T_TIMEOUT`, ~35ms, after which a hung device must
   release the bus — the opposite of "stretch forever"), the SMBus ALERT
   protocol (a dedicated address + target-initiated interrupt), and PEC
   (packet error checking, a CRC-8 appended byte). Recommend scoping SMBus
   out of v1 explicitly (note it in README/docs) rather than silently
   omitting it, since "does this behave like SMBus" will be an early
   question from any real user plugging in sensor models.
6. **Glitch/spike filtering and analog timing parameters.** UM10204 specifies
   input spike suppression (`t_SP`) and a long list of per-mode timing
   bounds (`t_LOW`, `t_HIGH`, `t_SU;STA`, `t_HD;STA`, `t_SU;STO`, `t_BUF`,
   `t_SU;DAT`, `t_HD;DAT`, rise/fall times). A digital VIP can't model
   analog rise/fall, but **should** make `t_SU/t_HD` violations by the DUT
   detectable (i.e., the monitor should timestamp edges finely enough, or the
   formal checkers should assert on cycle-accurate setup/hold relative to the
   oversample tick) rather than silently accepting anything that eventually
   produces a valid-looking bit. Needs a decision on oversample-tick
   resolution vs. simulation performance trade-off.
7. **DUT register-model agent (opencores-style, or others).** As noted in
   §7, a register-level agent that drives a *specific* I2C controller IP
   (starting with the freecores/opencores core's CTR/CR/SR/TXR/RXR map as a
   concrete first target) through its WISHBONE/APB/AHB register interface
   while the `fwvip-i2c` target+monitor check the resulting wire traffic
   would be a natural, high-value follow-on package (e.g.
   `fwvip-i2c-opencores` or a `std`-style register adapter per the kit
   skill's adapter pattern) — flagged as future work, not part of this
   design.
8. **General call and other broadcast addressing.** `0000 000 0` (general
   call) lets a controller address *all* targets at once; a target's
   response to it is configurable per-device (ignore, or react per a
   second byte's meaning, which is device-specific and not standardized
   beyond `0000 0110`=reset+program-address and `0000 0100`=reset). Recommend
   the target-side model support an opt-in general-call listener but not
   attempt to standardize second-byte semantics.
9. **Bit-level/negative-test agent (the "no L1 layer" decision in §6).**
   Revisit after the transaction-level sequence item's negative-testing knobs
   (deliberately wrong ACK, premature STOP, SCL held low past a timeout,
   clock-stretch-while-not-TIP, multi-master collision timing) are drafted —
   if those can't cover realistic negative scenarios without a dedicated
   bit-level driver, add the L1-equivalent layer then rather than
   speculatively now.

## 9. Proposed skeleton

Mirrors `fwvip-spi`/`fwvip-wb` top level and the `fw-proto-kit` skill's
`references/example/` layout, with `fw-proto-i2c` vendored under `packages/`
exactly as `fw-proto-chi`/`fw-proto-wb`/`fw-proto-uart` are in their parent
repos:

```
fwvip-i2c/
  .envrc, .gitignore, LICENSE, README.md     (present)
  ivpm.yaml            # use/dev dep-sets incl. fw-proto-i2c, fwvip-core, fw-hdl
  flow.yaml            # package; fragments [src, tests]; project.dv.uvm archetype
  fwvip-i2c.code-workspace
  .github/workflows/ci.yml, .forgejo/workflows/ci.yml
  docs/                # sphinx: index/getting-started/reference/sequences/
                        #   l1-agent-or-equivalent/integration/verification
  src/uvm/              # fwvip_i2c_* classes per §6
  tests/uvm/            # bench + directed/random tests
  packages/
    fw-hdl/, fwvip-core/, dv-flow-*, python/, verilator/, yosys/, sphinx-*, svdep/
    fw-proto-i2c/        # NEW kit package, laid out per fw-proto-kit SKILL.md:
      src/                #   i2c_{controller,target,monitor}_{if.svh,xtor_*}
      tests/i2c_proto_tb.sv              # required back-to-back sim test
      tests/arb/i2c_arb_tb.sv            # required 2-controller arbitration test (§8.1)
      tests/formal/i2c_proto_fv.sv + PROPERTIES.md  # required formal component (§8.2)
      docs/
```
