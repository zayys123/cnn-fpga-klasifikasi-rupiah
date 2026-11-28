module conv3_engine (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,

    // INPUT FEATURE MAP RAM
    output reg                input_rd_en,
    output reg  [9:0]         input_rd_addr,
    input  wire [7:0]         input_rd_data,

    // CONV3 WEIGHT ROM
    output reg                weight_rd_en,
    output reg  [11:0]        weight_rd_addr,
    input  wire signed [7:0]  weight_rd_data,

    // PARAMETER ROM
    output reg                param_rd_en,
    output reg  [4:0]         param_rd_addr,

    input  wire signed [31:0] bias_rd_data,
    input  wire        [31:0] multiplier_rd_data,
    input  wire signed [7:0]  shift_rd_data,

    // OUTPUT FEATURE MAP RAM
    output reg                output_wr_en,
    output reg  [10:0]        output_wr_addr,
    output reg  [7:0]         output_wr_data,

    // STATUS
    output reg                busy,
    output reg                done,
    output reg                error,
    output reg                saturated
);

    // FSM STATES
    localparam ST_IDLE         = 4'd0;
    localparam ST_PARAM_READ   = 4'd1;
    localparam ST_PIXEL_START  = 4'd2;
    localparam ST_WAIT_TAP_REQ = 4'd3;
    localparam ST_TAP_READ     = 4'd4;
    localparam ST_TAP_FEED     = 4'd5;
    localparam ST_WAIT_PIXEL   = 4'd6;
    localparam ST_WRITE_PIXEL  = 4'd7;

    reg [3:0] state;

    // OUTPUT POSITION
    reg [4:0] output_channel;
    reg [2:0] output_y;
    reg [2:0] output_x;

    // PIXEL ENGINE INTERFACE
    reg pixel_start;
    reg pixel_tap_valid;

    reg [7:0] pixel_activation;
    reg signed [7:0] pixel_weight;

    wire [7:0] pixel_tap_index;
    wire pixel_tap_request;

    wire [7:0] pixel_out;

    wire pixel_done;
    wire pixel_busy;
    wire pixel_saturated;
    wire pixel_error;

    // PADDING CONTROL
    reg tap_padding;

    // TAP ADDRESS GENERATION
    wire [3:0] tap_ic;
    wire [1:0] tap_ky;
    wire [1:0] tap_kx;

    wire signed [5:0] output_y_signed;
    wire signed [5:0] output_x_signed;

    wire signed [5:0] tap_ky_signed;
    wire signed [5:0] tap_kx_signed;

    wire signed [5:0] input_y_calc;
    wire signed [5:0] input_x_calc;

    wire input_in_bounds;

    wire [9:0] input_addr_calc;
    wire [11:0] weight_addr_calc;
    wire [10:0] output_addr_calc;

    // TAP INDEX MAPPING
    assign tap_ic =
        pixel_tap_index / 8'd9;

    assign tap_ky =
        (pixel_tap_index % 8'd9) / 8'd3;

    assign tap_kx =
        pixel_tap_index % 8'd3;

    // COORDINATE EXTENSION
    assign output_y_signed =
        $signed({3'b000, output_y});

    assign output_x_signed =
        $signed({2'b00, output_x});

    assign tap_ky_signed =
        $signed({4'b0000, tap_ky});

    assign tap_kx_signed =
        $signed({4'b0000, tap_kx});

    // PADDING OFFSET
    assign input_y_calc =
        output_y_signed + tap_ky_signed - 6'sd1;

    assign input_x_calc =
        output_x_signed + tap_kx_signed - 6'sd1;

    // INPUT BOUNDS
    assign input_in_bounds =
        (input_y_calc >= 6'sd0) &&
        (input_y_calc < 6'sd8) &&
        (input_x_calc >= 6'sd0) &&
        (input_x_calc < 6'sd8);

    // NCHW INPUT ADDRESS
    // [channel][8][8]
    assign input_addr_calc =
        {tap_ic, 6'd0} +
        {4'd0, input_y_calc[2:0], 3'd0} +
        {7'd0, input_x_calc[2:0]};

    // OIHW WEIGHT ADDRESS
    // [output_channel][16][3][3]
    assign weight_addr_calc =
        (output_channel * 12'd144) +
        {4'd0, pixel_tap_index};

    // OUTPUT FEATURE MAP ADDRESS
    // [output_channel][8][8]
    assign output_addr_calc =
        {output_channel, 6'd0} +
        {5'd0, output_y, 3'd0} +
        {8'd0, output_x};

    // PIXEL ENGINE
    conv3_pixel_engine u_pixel_engine (
        .clk(clk),
        .rst_n(rst_n),

        .start(pixel_start),

        .bias(bias_rd_data),
        .multiplier_q31(multiplier_rd_data),
        .shift(shift_rd_data),

        .tap_index(pixel_tap_index),
        .tap_request(pixel_tap_request),

        .tap_valid(pixel_tap_valid),
        .activation(pixel_activation),
        .weight(pixel_weight),

        .pixel_out(pixel_out),

        .done(pixel_done),
        .busy(pixel_busy),
        .saturated(pixel_saturated),
        .error(pixel_error)
    );

    // COMBINATIONAL CONTROL
    always @(*) begin

        pixel_start = 1'b0;
        pixel_tap_valid = 1'b0;

        pixel_activation = 8'd0;
        pixel_weight = 8'sd0;

        input_rd_en = 1'b0;
        input_rd_addr = 10'd0;

        weight_rd_en = 1'b0;
        weight_rd_addr = 12'd0;

        param_rd_en = 1'b0;
        param_rd_addr = output_channel;

        output_wr_en = 1'b0;
        output_wr_addr = 11'd0;
        output_wr_data = pixel_out;

        case (state)

            ST_PARAM_READ: begin
                param_rd_en = 1'b1;
                param_rd_addr = output_channel;
            end

            ST_PIXEL_START: begin
                pixel_start = 1'b1;
            end

            ST_TAP_READ: begin
                weight_rd_en = 1'b1;
                weight_rd_addr = weight_addr_calc;

                if (input_in_bounds) begin
                    input_rd_en = 1'b1;
                    input_rd_addr = input_addr_calc;
                end
            end

            ST_TAP_FEED: begin
                pixel_tap_valid = 1'b1;

                if (tap_padding)
                    pixel_activation = 8'd0;
                else
                    pixel_activation = input_rd_data;

                pixel_weight = weight_rd_data;
            end

            ST_WRITE_PIXEL: begin
                output_wr_en = 1'b1;
                output_wr_addr = output_addr_calc;
                output_wr_data = pixel_out;
            end

            default: begin
            end

        endcase
    end

    // MAIN FSM
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            output_channel <= 5'd0;
            output_y <= 3'd0;
            output_x <= 3'd0;

            tap_padding <= 1'b0;

            busy <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            saturated <= 1'b0;

        end
        else begin

            done <= 1'b0;

            case (state)

                ST_IDLE: begin

                    busy <= 1'b0;

                    if (start) begin

                        output_channel <= 5'd0;
                        output_y <= 3'd0;
                        output_x <= 3'd0;

                        tap_padding <= 1'b0;

                        error <= 1'b0;
                        saturated <= 1'b0;

                        busy <= 1'b1;

                        state <= ST_PARAM_READ;

                    end

                end

                ST_PARAM_READ: begin
                    state <= ST_PIXEL_START;
                end

                ST_PIXEL_START: begin
                    state <= ST_WAIT_TAP_REQ;
                end

                ST_WAIT_TAP_REQ: begin

                    if (pixel_tap_request)
                        state <= ST_TAP_READ;

                end

                ST_TAP_READ: begin

                    tap_padding <= !input_in_bounds;

                    state <= ST_TAP_FEED;

                end

                ST_TAP_FEED: begin

                    if (pixel_tap_index == 8'd143)
                        state <= ST_WAIT_PIXEL;
                    else
                        state <= ST_TAP_READ;

                end

                ST_WAIT_PIXEL: begin

                    if (pixel_done) begin

                        if (pixel_error) begin

                            error <= 1'b1;
                            busy <= 1'b0;
                            done <= 1'b1;

                            state <= ST_IDLE;

                        end
                        else begin

                            if (pixel_saturated)
                                saturated <= 1'b1;

                            state <= ST_WRITE_PIXEL;

                        end

                    end

                end

                ST_WRITE_PIXEL: begin

                    if (output_x == 3'd7) begin

                        output_x <= 3'd0;

                        if (output_y == 3'd7) begin

                            output_y <= 3'd0;

                            if (output_channel == 5'd23) begin

                                busy <= 1'b0;
                                done <= 1'b1;

                                state <= ST_IDLE;

                            end
                            else begin

                                output_channel <=
                                    output_channel + 1'b1;

                                state <= ST_PARAM_READ;

                            end

                        end
                        else begin

                            output_y <= output_y + 1'b1;

                            state <= ST_PIXEL_START;

                        end

                    end
                    else begin

                        output_x <= output_x + 1'b1;

                        state <= ST_PIXEL_START;

                    end

                end

                default: begin

                    state <= ST_IDLE;

                    busy <= 1'b0;
                    error <= 1'b1;
                    done <= 1'b1;

                end

            endcase

        end

    end

endmodule
