module mac_int8 (
    input  wire               clk,
    input  wire               rst_n,

    input  wire               clear,
    input  wire               load_bias,
    input  wire               enable,

    input  wire        [7:0]  activation,
    input  wire signed [7:0]  weight,
    input  wire signed [31:0] bias,

    output reg  signed [31:0] accumulator,
    output reg                overflow
);

    // UINT8 activation -> signed positive INT16
    wire signed [15:0] activation_ext;

    assign activation_ext = $signed({8'b0, activation});

    // Signed INT8 weight -> signed INT16
    wire signed [15:0] weight_ext;

    assign weight_ext = {{8{weight[7]}}, weight};

    // Signed INT16 multiplication
    wire signed [15:0] product;

    assign product = activation_ext * weight_ext;

    // Extend accumulator to 33 bits
    wire signed [32:0] accumulator_ext;

    assign accumulator_ext = {
        accumulator[31],
        accumulator
    };

    // Sign-extend multiplication result
    wire signed [32:0] product_ext;

    assign product_ext = {
        {17{product[15]}},
        product
    };

    // 33-bit addition for overflow detection
    wire signed [32:0] sum_ext;

    assign sum_ext = accumulator_ext + product_ext;

    // Signed INT32 overflow detection
    wire add_overflow;

    assign add_overflow = sum_ext[32] ^ sum_ext[31];

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            accumulator <= 32'sd0;
            overflow    <= 1'b0;

        end

        else if (clear) begin

            accumulator <= 32'sd0;
            overflow    <= 1'b0;

        end

        else if (load_bias) begin

            accumulator <= bias;
            overflow    <= 1'b0;

        end

        else if (enable && !overflow) begin

            if (add_overflow) begin

                overflow <= 1'b1;

            end

            else begin

                accumulator <= sum_ext[31:0];

            end

        end

    end

endmodule
