// Base target responder: extend it and override addressed() / rx_byte() /
// tx_byte() (the kit's i2c_target_if). body() runs forever, offering the
// responder to the driver; start it in the background (fork ... join_none)
// on the target agent's sequencer. This base ACKs everything and sends 0xFF.
class fwvip_i2c_tgt_seq extends uvm_sequence #(fwvip_i2c_tgt_item) implements i2c_target_if;
    `uvm_object_utils(fwvip_i2c_tgt_seq)

    function new(string name = "fwvip_i2c_tgt_seq");
        super.new(name);
    endfunction

    virtual task addressed(input bit [9:0] addr, input bit addr_10b,
                           input bit read, output bit ack);
        ack = 1'b1;
    endtask

    virtual task rx_byte(input bit [7:0] data, output bit ack);
        ack = 1'b1;
    endtask

    virtual task tx_byte(output bit [7:0] data, input bit ack);
        data = 8'hff;
    endtask

    task body();
        fwvip_i2c_tgt_item it = fwvip_i2c_tgt_item::type_id::create("it");
        it.handler = this;
        forever begin
            start_item(it);
            finish_item(it);
        end
    endtask
endclass
