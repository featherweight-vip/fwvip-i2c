# Sequences

## The transaction item

`fwvip_i2c_xact` is one transaction: START, one or more segments, STOP.
Each segment (`fwvip_i2c_segment`) is an address+R/W byte followed by data
bytes in one direction. The second and later segments begin with a repeated
START.

| Field | Before the run | After the run |
|---|---|---|
| `seg[i].addr`, `.read` | the target address and direction | unchanged |
| `seg[i].data` | the bytes to write, or sized to the number of bytes to read | exactly the bytes that crossed the bus |
| `seg[i].addr_ack` | — | the target's ACK of the address byte |
| `seg[i].ack[j]` | — | the ACK bit after `data[j]`: the target's for a write; the controller's for a read (1 for every byte but the last) |
| `status` | — | `FWVIP_I2C_OK`, `_ADDR_NACK`, `_DATA_NACK` or `_ARB_LOST` |
| `nack_seg`, `nack_byte` | — | where the NACK was (`nack_byte = -1` for the address byte) |

On a NACK the controller issues STOP, and a write NACKed partway is
truncated after the NACKed byte. On arbitration loss it issues no STOP,
because the core has already released the bus; the caller retries the whole
transaction.

Build one by hand with `add_write(addr, data)` and `add_read(addr, n)`.
`convert2string()` prints it compactly; a trailing `~` marks a NACKed byte:

```text
OK [W 0x50 10 a0 a1 a2 a3]
OK [R 0x50 a0 a1 a2 a3~]
ADDR_NACK [W 0x23 NACK]
```

```{admonition} Repeated START is not usable yet
:class: warning
Multi-segment items are modeled, but the v1 kit target core does not tell a
repeated START from the start of another data byte. Use write + STOP + read
for a register read (as `mem_read()` in the bench does).
```

## Controller sequences

Extend `fwvip_i2c_ctrl_seq_base` and run on `fwvip_i2c_ctrl_agent.m_seqr`.
Its helpers return the completed item:

`write(t, addr7, data[])`
: START, address (write), `data`, STOP.

`read(t, addr7, n)`
: START, address (read), `n` bytes with the last NACKed, STOP.
  `t.seg[0].data` holds the bytes read.

`do_xact(t)`
: runs a hand-built item.

`rand_addr7()`
: a random 7-bit address outside the reserved ranges.

```systemverilog
class my_seq extends fwvip_i2c_ctrl_seq_base;
    `uvm_object_utils(my_seq)
    function new(string name = "my_seq"); super.new(name); endfunction
    task body();
        fwvip_i2c_xact t;
        bit [7:0] wr[] = '{8'h10, 8'hde, 8'had};   // pointer 0x10, then two bytes
        write(t, 7'h50, wr);
        if (t.status != FWVIP_I2C_OK) `uvm_error("SEQ", t.convert2string())
        wr = '{8'h10};
        write(t, 7'h50, wr);                          // set the pointer
        read(t, 7'h50, 2);                            // t.seg[0].data == '{de, ad}
    endtask
endclass
```

Ready-made sequences. Set the fields, then `start()`:

| Sequence | Fields | Does |
|---|---|---|
| `fwvip_i2c_write_seq` | `addr`, `data[]`; result in `t` | one write |
| `fwvip_i2c_read_seq` | `addr`, `n`; result in `t` | one read |
| `fwvip_i2c_rand_seq` | `n_xacts` (20), `max_bytes` (8), `read_pct` (50), `addrs[$]` | random single-segment writes (0..`max_bytes` bytes) and reads (1..`max_bytes`) to a random entry of `addrs`, or to a random legal address if `addrs` is empty |

## Target responders

A responder implements the kit's `i2c_target_if`. Extend `fwvip_i2c_tgt_seq`
and override:

`addressed(addr, addr_10b, read, ack)`
: an address byte matching this target; return its ACK.

`rx_byte(data, ack)`
: a byte the controller wrote; return its ACK.

`tx_byte(data, ack)`
: supply a byte the controller reads. `ack` is the controller's
  decision on it, which arrives only after the byte; it is 0 on the last
  byte.

The base class ACKs everything and returns 0xFF. `body()` runs forever, so
start it in the background:

```systemverilog
fork resp.start(env.m_tgt.m_seqr); join_none
```

The config NACKs non-matching addresses without calling the responder. While
any of these tasks blocks, the target core holds SCL low (clock stretching),
so latency in a responder becomes clock stretching on the bus.

### `fwvip_i2c_mem_responder_seq`

An EEPROM-style target: 256 bytes behind an 8-bit pointer.

- The first byte of a write sets the pointer. Each later write byte is
  stored at the pointer, and each read byte comes from it. Both advance it,
  wrapping at 256.
- The pointer persists across transactions, so "write the offset, STOP,
  read" is a random read.
- Unwritten bytes read as `init_byte(off)` (`off ^ 8'ha5`). `peek(off)`
  reads the memory without touching the pointer.

| Knob | Default | Effect |
|---|---|---|
| `lat_min`, `lat_max` | 0, 0 | cycles of the agent's clock to wait before each decision, so cycles of SCL stretch (needs the agent's `"clock"`) |
| `nack_at` | -1 | NACK that data byte of every write (0 is the pointer byte); it is not stored |
