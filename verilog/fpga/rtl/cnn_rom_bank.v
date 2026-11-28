
module cnn_rom_bank (

    input wire clk,

    // =====================================
    // CONV1 ROM INTERFACE
    // =====================================

    input wire [7:0] conv1_weight_addr,
    output wire signed [7:0] conv1_weight_data,

    input wire [2:0] conv1_param_addr,
    output wire signed [31:0] conv1_bias_data,
    output wire [31:0] conv1_multiplier_data,
    output wire signed [7:0] conv1_shift_data,

    // =====================================
    // CONV2 ROM INTERFACE
    // =====================================

    input wire [10:0] conv2_weight_addr,
    output wire signed [7:0] conv2_weight_data,

    input wire [3:0] conv2_param_addr,
    output wire signed [31:0] conv2_bias_data,
    output wire [31:0] conv2_multiplier_data,
    output wire signed [7:0] conv2_shift_data,

    // =====================================
    // CONV3 ROM INTERFACE
    // =====================================

    input wire [11:0] conv3_weight_addr,
    output wire signed [7:0] conv3_weight_data,

    input wire [4:0] conv3_param_addr,
    output wire signed [31:0] conv3_bias_data,
    output wire [31:0] conv3_multiplier_data,
    output wire signed [7:0] conv3_shift_data,

    // =====================================
    // FC ROM INTERFACE
    // =====================================

    input wire [7:0] fc_weight_addr,
    output wire signed [7:0] fc_weight_data,

    input wire [2:0] fc_bias_addr,
    output wire signed [31:0] fc_bias_data

);

    // =====================================
    // CONV1 ROM
    // =====================================

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(216),
        .ADDR_WIDTH(8),
        .INIT_FILE("../weights/mif/conv1_weights_int8.mif")
    ) rom_conv1_weights (
        .clk(clk),
        .addr(conv1_weight_addr),
        .data(conv1_weight_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(8),
        .ADDR_WIDTH(3),
        .INIT_FILE("../weights/mif/conv1_bias_int32.mif")
    ) rom_conv1_bias (
        .clk(clk),
        .addr(conv1_param_addr),
        .data(conv1_bias_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(8),
        .ADDR_WIDTH(3),
        .INIT_FILE("../weights/mif/conv1_requant_multiplier_q31.mif")
    ) rom_conv1_multiplier (
        .clk(clk),
        .addr(conv1_param_addr),
        .data(conv1_multiplier_data)
    );

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(8),
        .ADDR_WIDTH(3),
        .INIT_FILE("../weights/mif/conv1_requant_shift_s8.mif")
    ) rom_conv1_shift (
        .clk(clk),
        .addr(conv1_param_addr),
        .data(conv1_shift_data)
    );

    // =====================================
    // CONV2 ROM
    // =====================================

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(1152),
        .ADDR_WIDTH(11),
        .INIT_FILE("../weights/mif/conv2_weights_int8.mif")
    ) rom_conv2_weights (
        .clk(clk),
        .addr(conv2_weight_addr),
        .data(conv2_weight_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(16),
        .ADDR_WIDTH(4),
        .INIT_FILE("../weights/mif/conv2_bias_int32.mif")
    ) rom_conv2_bias (
        .clk(clk),
        .addr(conv2_param_addr),
        .data(conv2_bias_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(16),
        .ADDR_WIDTH(4),
        .INIT_FILE("../weights/mif/conv2_requant_multiplier_q31.mif")
    ) rom_conv2_multiplier (
        .clk(clk),
        .addr(conv2_param_addr),
        .data(conv2_multiplier_data)
    );

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(16),
        .ADDR_WIDTH(4),
        .INIT_FILE("../weights/mif/conv2_requant_shift_s8.mif")
    ) rom_conv2_shift (
        .clk(clk),
        .addr(conv2_param_addr),
        .data(conv2_shift_data)
    );

    // =====================================
    // CONV3 ROM
    // =====================================

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(3456),
        .ADDR_WIDTH(12),
        .INIT_FILE("../weights/mif/conv3_weights_int8.mif")
    ) rom_conv3_weights (
        .clk(clk),
        .addr(conv3_weight_addr),
        .data(conv3_weight_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(24),
        .ADDR_WIDTH(5),
        .INIT_FILE("../weights/mif/conv3_bias_int32.mif")
    ) rom_conv3_bias (
        .clk(clk),
        .addr(conv3_param_addr),
        .data(conv3_bias_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(24),
        .ADDR_WIDTH(5),
        .INIT_FILE("../weights/mif/conv3_requant_multiplier_q31.mif")
    ) rom_conv3_multiplier (
        .clk(clk),
        .addr(conv3_param_addr),
        .data(conv3_multiplier_data)
    );

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(24),
        .ADDR_WIDTH(5),
        .INIT_FILE("../weights/mif/conv3_requant_shift_s8.mif")
    ) rom_conv3_shift (
        .clk(clk),
        .addr(conv3_param_addr),
        .data(conv3_shift_data)
    );

    // =====================================
    // FULLY CONNECTED ROM
    // =====================================

    sync_rom_mif #(
        .WIDTH(8),
        .DEPTH(168),
        .ADDR_WIDTH(8),
        .INIT_FILE("../weights/mif/fc_weights_int8.mif")
    ) rom_fc_weights (
        .clk(clk),
        .addr(fc_weight_addr),
        .data(fc_weight_data)
    );

    sync_rom_mif #(
        .WIDTH(32),
        .DEPTH(7),
        .ADDR_WIDTH(3),
        .INIT_FILE("../weights/mif/fc_bias_int32.mif")
    ) rom_fc_bias (
        .clk(clk),
        .addr(fc_bias_addr),
        .data(fc_bias_data)
    );

endmodule
