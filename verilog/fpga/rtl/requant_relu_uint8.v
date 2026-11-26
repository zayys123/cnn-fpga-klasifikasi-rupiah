module requant_relu_uint8 (
    input  wire signed [31:0] accumulator,
    input  wire        [31:0] multiplier_q31,
    input  wire signed [7:0]  shift,

    output reg         [7:0]  activation_out,
    output reg                saturated,
    output reg                invalid_config
);

    // Internal signals
    reg [31:0] acc_relu;

    reg [63:0] product;
    reg [63:0] rounding_offset;
    reg [63:0] rounded_numerator;
    reg [63:0] rounded_value;

    reg signed [8:0] denominator_shift_signed;
    reg        [5:0] denominator_shift;


    always @(*) begin

        // Default values
        activation_out = 8'd0;
        saturated      = 1'b0;
        invalid_config = 1'b0;

        acc_relu          = 32'd0;
        product           = 64'd0;
        rounding_offset   = 64'd0;
        rounded_numerator = 64'd0;
        rounded_value     = 64'd0;

        denominator_shift_signed = 9'sd31 -
            $signed({{1{shift[7]}}, shift});

        denominator_shift = 6'd0;


        // Python behavior:
        // Zero multiplier produces zero output.
        if (multiplier_q31 == 32'd0) begin

            activation_out = 8'd0;

        end

        // Validate Q31 multiplier and signed shift
        else if (
            (shift < -8'sd31) ||
            (shift >  8'sd30) ||
            multiplier_q31[31]
        ) begin

            invalid_config = 1'b1;

        end

        else begin

            // ReLU
            if (accumulator > 32'sd0)
                acc_relu = accumulator[31:0];
            else
                acc_relu = 32'd0;


            // Q31 multiplication
            product =
                {32'd0, acc_relu} *
                {32'd0, multiplier_q31};


            // Denominator shift = 31 - signed shift
            denominator_shift =
                denominator_shift_signed[5:0];


            // Round-to-nearest, ties upward
            rounding_offset =
                64'd1 << (denominator_shift - 6'd1);


            rounded_numerator =
                product + rounding_offset;


            // Divide by power of two
            rounded_value =
                rounded_numerator >> denominator_shift;


            // UINT8 saturation
            if (rounded_value > 64'd255) begin

                activation_out = 8'd255;
                saturated = 1'b1;

            end

            else begin

                activation_out = rounded_value[7:0];
                saturated = 1'b0;

            end

        end

    end

endmodule
