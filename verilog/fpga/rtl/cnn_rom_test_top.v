
module cnn_rom_test_top (
    input  wire        clk,
    input  wire [3:0]  rom_select,
    input  wire [11:0] rom_addr,
    output reg  [31:0] rom_data
);

    // ROM selection pipeline
    reg [3:0] rom_select_d;

    always @(posedge clk) begin
        rom_select_d <= rom_select;
    end

    // CONV1
    wire signed [7:0]  conv1_weight_data;
    wire signed [31:0] conv1_bias_data;
    wire [31:0]        conv1_multiplier_data;
    wire signed [7:0]  conv1_shift_data;

    // CONV2
    wire signed [7:0]  conv2_weight_data;
    wire signed [31:0] conv2_bias_data;
    wire [31:0]        conv2_multiplier_data;
    wire signed [7:0]  conv2_shift_data;

    // CONV3
    wire signed [7:0]  conv3_weight_data;
    wire signed [31:0] conv3_bias_data;
    wire [31:0]        conv3_multiplier_data;
    wire signed [7:0]  conv3_shift_data;

    // FC
    wire signed [7:0]  fc_weight_data;
    wire signed [31:0] fc_bias_data;

    // Instantiate complete ROM bank
    cnn_rom_bank rom_bank_inst (

        .clk(clk),

        // CONV1
        .conv1_weight_addr(rom_addr[7:0]),
        .conv1_weight_data(conv1_weight_data),
        .conv1_param_addr(rom_addr[2:0]),
        .conv1_bias_data(conv1_bias_data),
        .conv1_multiplier_data(conv1_multiplier_data),
        .conv1_shift_data(conv1_shift_data),

        // CONV2
        .conv2_weight_addr(rom_addr[10:0]),
        .conv2_weight_data(conv2_weight_data),
        .conv2_param_addr(rom_addr[3:0]),
        .conv2_bias_data(conv2_bias_data),
        .conv2_multiplier_data(conv2_multiplier_data),
        .conv2_shift_data(conv2_shift_data),

        // CONV3
        .conv3_weight_addr(rom_addr),
        .conv3_weight_data(conv3_weight_data),
        .conv3_param_addr(rom_addr[4:0]),
        .conv3_bias_data(conv3_bias_data),
        .conv3_multiplier_data(conv3_multiplier_data),
        .conv3_shift_data(conv3_shift_data),

        // FC
        .fc_weight_addr(rom_addr[7:0]),
        .fc_weight_data(fc_weight_data),
        .fc_bias_addr(rom_addr[2:0]),
        .fc_bias_data(fc_bias_data)
    );

    // Output multiplexer
    // Byte ROM values are zero-extended;
    // their original 8-bit patterns remain unchanged.

    always @(*) begin

        rom_data = 32'd0;

        case (rom_select_d)

            4'd0: rom_data = {24'd0, conv1_weight_data};
            4'd1: rom_data = conv1_bias_data;
            4'd2: rom_data = conv1_multiplier_data;
            4'd3: rom_data = {24'd0, conv1_shift_data};

            4'd4: rom_data = {24'd0, conv2_weight_data};
            4'd5: rom_data = conv2_bias_data;
            4'd6: rom_data = conv2_multiplier_data;
            4'd7: rom_data = {24'd0, conv2_shift_data};

            4'd8: rom_data = {24'd0, conv3_weight_data};
            4'd9: rom_data = conv3_bias_data;
            4'd10: rom_data = conv3_multiplier_data;
            4'd11: rom_data = {24'd0, conv3_shift_data};

            4'd12: rom_data = {24'd0, fc_weight_data};
            4'd13: rom_data = fc_bias_data;

            default: rom_data = 32'd0;

        endcase

    end

endmodule
