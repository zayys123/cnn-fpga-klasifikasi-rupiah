module conv3_pixel_engine (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,

    input  wire signed [31:0] bias,
    input  wire        [31:0] multiplier_q31,
    input  wire signed [7:0]  shift,

    output reg         [7:0]  tap_index,
    output wire               tap_request,

    input  wire               tap_valid,
    input  wire        [7:0]  activation,
    input  wire signed [7:0]  weight,

    output reg         [7:0]  pixel_out,
    output reg                done,
    output reg                busy,
    output reg                saturated,
    output reg                error
);

    localparam IDLE      = 2'd0;
    localparam LOAD_BIAS = 2'd1;
    localparam WAIT_TAP  = 2'd2;
    localparam REQUANT   = 2'd3;

    reg [1:0] state;

    reg signed [31:0] bias_latched;
    reg        [31:0] multiplier_latched;
    reg signed [7:0]  shift_latched;

    wire signed [31:0] accumulator;
    wire mac_overflow;

    reg mac_load_bias;
    reg mac_enable;

    wire [7:0] requantized;
    wire requant_saturated;
    wire invalid_config;

    assign tap_request = (state == WAIT_TAP);

    always @(*) begin
        mac_load_bias = 1'b0;
        mac_enable    = 1'b0;

        if (state == LOAD_BIAS)
            mac_load_bias = 1'b1;

        if (state == WAIT_TAP && tap_valid)
            mac_enable = 1'b1;
    end

    mac_int8 u_mac (
        .clk(clk),
        .rst_n(rst_n),
        .clear(1'b0),
        .load_bias(mac_load_bias),
        .enable(mac_enable),
        .activation(activation),
        .weight(weight),
        .bias(bias_latched),
        .accumulator(accumulator),
        .overflow(mac_overflow)
    );

    requant_relu_uint8 u_requant (
        .accumulator(accumulator),
        .multiplier_q31(multiplier_latched),
        .shift(shift_latched),
        .activation_out(requantized),
        .saturated(requant_saturated),
        .invalid_config(invalid_config)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= IDLE;
            tap_index          <= 8'd0;

            bias_latched       <= 32'sd0;
            multiplier_latched <= 32'd0;
            shift_latched      <= 8'sd0;

            pixel_out          <= 8'd0;

            done               <= 1'b0;
            busy               <= 1'b0;
            saturated          <= 1'b0;
            error              <= 1'b0;
        end
        else begin
            done      <= 1'b0;
            saturated <= 1'b0;
            error     <= 1'b0;

            case (state)

                IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        bias_latched       <= bias;
                        multiplier_latched <= multiplier_q31;
                        shift_latched      <= shift;

                        tap_index <= 8'd0;

                        busy  <= 1'b1;
                        state <= LOAD_BIAS;
                    end
                end

                LOAD_BIAS: begin
                    state <= WAIT_TAP;
                end

                WAIT_TAP: begin
                    if (tap_valid) begin
                        if (tap_index == 8'd143)
                            state <= REQUANT;
                        else
                            tap_index <= tap_index + 1'b1;
                    end
                end

                REQUANT: begin
                    if (mac_overflow || invalid_config) begin
                        pixel_out <= 8'd0;
                        error     <= 1'b1;
                    end
                    else begin
                        pixel_out <= requantized;
                        saturated <= requant_saturated;
                    end

                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end

            endcase
        end
    end

endmodule
