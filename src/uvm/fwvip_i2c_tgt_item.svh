// The item a target responder sequence sends, over and over: it carries the
// responder itself (UVM does not let a sequence be sent through
// start_item). The driver takes the handler from it and calls it.
class fwvip_i2c_tgt_item extends uvm_sequence_item;
    `uvm_object_utils(fwvip_i2c_tgt_item)

    i2c_target_if handler;

    function new(string name = "fwvip_i2c_tgt_item");
        super.new(name);
    endfunction
endclass
