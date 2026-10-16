// The back-to-back test: one case, chosen by +SEQ=<case sequence>, on the
// controller agent, with the memory responder on the target agent. At the
// end the scoreboard must have matched transactions on the bus; the
// scoreboard and the monitor agent check the rest themselves.
class fwvip_i2c_b2b_test extends uvm_test;
    `uvm_component_utils(fwvip_i2c_b2b_test)

    fwvip_i2c_b2b_env m_env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_env = fwvip_i2c_b2b_env::type_id::create("m_env", this);
        // A wedged bus (a target stretching forever) fails instead of hanging.
        uvm_root::get().set_timeout(50ms, 0);
    endfunction

    // The case to run: +SEQ=<name>, the smoke case by default.
    virtual function fwvip_i2c_b2b_seq_base make_seq();
        string      name = "fwvip_i2c_smoke_seq";
        uvm_object  obj;
        fwvip_i2c_b2b_seq_base seq;
        void'($value$plusargs("SEQ=%s", name));
        obj = uvm_factory::get().create_object_by_name(name, "", "seq");
        if (obj == null || !$cast(seq, obj))
            `uvm_fatal(get_type_name(), $sformatf("+SEQ=%s is not a fwvip_i2c_b2b_seq_base", name))
        return seq;
    endfunction

    task run_phase(uvm_phase phase);
        fwvip_i2c_b2b_seq_base seq = make_seq();
        phase.raise_objection(this);
        m_env.wait_ready();
        m_env.start_responder();
        seq.env = m_env;
        seq.defaults();
        `uvm_info(get_type_name(), $sformatf("running %s", seq.get_type_name()), UVM_LOW)
        seq.start(m_env.m_ctrl.m_seqr);
        seq.settle();
        post_case();
        phase.drop_objection(this);
    endtask

    // After the case, before the end of the run: for tests that add a step.
    virtual task post_case();
    endtask

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (m_env.m_sb.n_matched == 0)
            `uvm_error(get_type_name(), "the scoreboard matched no transaction on the bus")
    endfunction
endclass
