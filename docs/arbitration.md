# Arbitration at the UVM level (design note)

Status: **proposal, not started.** This is item 4 of the open-issues list:
the kit's `i2c_arb_tb` and `i2c_arb_sync_tb` cover arbitration and clock
synchronization, but the UVM bench has one controller and nothing above
the kit has ever seen an `ARB_LOST`. This note sets out what is needed for
two or more controller agents to share one bus, and which decisions need
an answer before the work starts.

## What exists

- The kit's controller core detects a loss on every bit it drives: the
  address and data bits, and the ACK bit of a read. It then releases both
  lines and returns `arb_lost = 1` (`i2c_controller_if`).
- `fwvip_i2c_ctrl_driver` turns that into `status = FWVIP_I2C_ARB_LOST`,
  issues no STOP, and truncates the item to what it moved before the loss.
  No sequence retries. No bench has ever run this path.
- The kit's monitor core does not report a loss: `observe_arb_lost()` is in
  `i2c_monitor_if` but is never called.
- The scoreboard pairs controller items with monitor items one-to-one, in
  order. That assumes one controller.

## The kit gap the bench would hit first: bus busy

**The controller core does not track whether the bus is busy.** In `IDLE`
it starts as soon as it gets a `start()`, so a controller that starts
while another controller's transaction is in progress drives a START into
the middle of it. UM10204 §3.1.4 says the bus is busy from a START until
a STOP, and a controller may only start when the bus is free (§3.1.8).
The kit's arbitration tests never hit this, because their two controllers
always start in the same clock.

Two controllers running random traffic hit this immediately. So does a
loser that retries straight away, while the winner is still mid-transfer.
The kit needs this first:

- **K1, bus busy in the controller core.** In `IDLE` the core watches
  the pins: START seen means busy, STOP seen means free once `T_BUF` has
  passed. A `start()` waits for a free bus. If SDA is already low when
  the core goes to drive its own START edge, another controller started
  in the same window. UM10204 treats the two STARTs as one, and
  arbitration then decides between them, so the core goes ahead. Also
  needed: a rule for the bus state at reset, which the core can't know.
  Options are "free" or "free after `T_BUF` of SCL and SDA high"; the
  second is safer.
- **K2, a kit sim for a late start.** A case in `i2c_arb_tb`: B's
  `start()` arrives while A is mid-byte. B must wait for A's STOP, then
  complete normally, and A must not see a collision.
- **K3, formal.** In `i2c_ctl_sync_fv`, the harness tracks bus busy from
  the pins and asserts that the core never drives a START edge while the
  bus is busy, and drives no line between a loss and the next free bus.
  This adds a few states to an existing BMC and should stay in
  `fv-quick`'s budget; that needs measuring.

## Proposed UVM changes

**V1, where the loss happened.** Add `arb_seg` and `arb_byte` to
`fwvip_i2c_xact`, beside `nack_seg` and `nack_byte` (`arb_byte = -1` for
the address byte). Keep the byte the controller meant to send, or the ACK
it meant to give, in the item as well. The scoreboard needs it to check
that the loss was real: the bus value must differ from it.

**V2, retry is up to the sequence.** The driver still returns
`ARB_LOST` and does nothing else. `fwvip_i2c_ctrl_seq_base` gains
`max_arb_retries` (default 0). With it set, the helpers re-run the whole
transaction, from START, on a loss. `fwvip_i2c_rand_seq` sets it, and
counts losses and retries. Retrying in the driver would hide the loss
from the sequence, and a test that checks recovery needs to see it.

**V3, the bench.** `fwvip_i2c_hdl_top` gets a second controller
transactor with different timing (for example `T_LOW = 7`, `T_HIGH = 3`
against the default 4/4), so every collision also exercises clock
synchronization. `fwvip_i2c_b2b_env` gets a second controller agent,
`m_ctrl2`. A controller with no sequence running leaves the bus alone, so
the existing eight cases are unchanged and it stays one image.

**V4, the scoreboard.** The monitor still sees one transaction per START
to STOP. The controller items for that bus transaction are:

- one winner, or several if their transactions were identical bit for bit
  (then no one loses, and every one of them completes). Each must match
  the monitor's item with `same_bus`, as now.
- any number of losers (`ARB_LOST`). Each must match the bus
  transaction up to the loss: the same earlier segments, a prefix of that
  segment's bytes, and at the loss point a bit where the bus differs from
  what the loser meant to send.

The two kinds arrive in a fixed order. A loser's item always completes
before the monitor's item for the same bus transaction, because it lost
before that transaction's STOP. So the scoreboard can keep losers in a
pending queue, check them all against the next monitor item, and pair
winners as it does now, from one queue per agent. To recognise
identical winners it needs each item's completion time, which goes in the
item.

The data check's reference model takes the bus transaction, not every
controller's writes. A loser's bytes before the loss reached the target
only once, from the winner. Read data a loser moved before the loss is
checked by the prefix match.

**V5, cases.**

| Case | What it does |
|---|---|
| `arb_directed` | the two controllers start at the same time, losing at each place a loss can happen: in the address, at the R/W bit (a write beats a read), in a data byte, at a read's ACK bit (an ACK beats a NACK), and in a 10-bit header's second byte; plus two identical transactions, which both complete |
| `arb_rand` | both controllers run `fwvip_i2c_rand_seq` against overlapping addresses with retries on, so collisions and late starts happen at random. The test fails unless losses happened |

`arb_directed` needs both controllers to start in the same clock.
Starting two sequences in one `fork` gets that only if the two driver
paths take the same number of delta cycles. A barrier in the test, which
both sequences wait on before their `start()`, makes it explicit.

## Decisions needed

1. **Monitor inference of arbitration loss: recommend not doing it.** On
   the pins, arbitration in I2C leaves no trace. The bus carries the
   winner's transaction as if it had been alone, which is why arbitration
   is non-destructive. A passive monitor has no way to know a second
   controller was driving. Only the losing controller's own drive intent
   shows the loss, and the controller agent already reports it.
   Recommendation: leave `observe_arb_lost()` in the API (removing it
   breaks every subscriber), document it as never called, and drop this
   from the limitations in `open-issues`. The alternative is a monitor
   that knows every controller's drive intent, which would no longer be
   passive.
2. **Retry in the sequence (V2) rather than in the driver:** recommended,
   for the reason under V2.
3. **The second controller always present in the bench (V3), rather than
   a separate image:** recommended, as one build serves every case.
4. **Out of scope:** a controller that loses arbitration in the address
   and is itself addressed by the winner (UM10204 §3.1.8). That needs an
   agent that is controller and target at once, which the VIP doesn't
   have.

## Order of work

1. K1–K3 in the kit, then commit. They are a real kit bug fix whether or
   not the UVM work follows.
2. V1 and V4, then V3 with `arb_directed`. Every existing case must still
   pass with the second controller present and idle.
3. V2 and `arb_rand`. Run `arb_directed` in `smoke`, and both nightly.
4. Docs: `verification`, `sequences`, `open-issues`, the usage skill.

This file is also the plan: the status line at the top, and each step,
get updated as the work goes.
