
module sync_rom_mif #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 256,
    parameter integer ADDR_WIDTH = 8,
    parameter INIT_FILE = ""
)(
    input wire clk,

    input wire [ADDR_WIDTH-1:0] addr,

    output wire [WIDTH-1:0] data
);

    // Intel FPGA synchronous ROM
    altsyncram rom_inst (
        .address_a(addr),
        .clock0(clk),
        .q_a(data)
    );


    defparam
        rom_inst.address_reg_a = "CLOCK0",
        rom_inst.clock_enable_input_a = "BYPASS",
        rom_inst.clock_enable_output_a = "BYPASS",
        rom_inst.init_file = INIT_FILE,
        rom_inst.intended_device_family = "Cyclone V",
        rom_inst.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
        rom_inst.lpm_type = "altsyncram",
        rom_inst.numwords_a = DEPTH,
        rom_inst.operation_mode = "ROM",
        rom_inst.outdata_aclr_a = "NONE",
        rom_inst.outdata_reg_a = "UNREGISTERED",
        rom_inst.widthad_a = ADDR_WIDTH,
        rom_inst.width_a = WIDTH,
        rom_inst.width_byteena_a = 1;

endmodule
