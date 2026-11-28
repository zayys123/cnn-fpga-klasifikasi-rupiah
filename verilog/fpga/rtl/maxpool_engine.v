
module maxpool_engine #(
    parameter integer INPUT_WIDTH = 32,
    parameter integer NUM_CHANNELS = 8
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,

    // INPUT FEATURE MAP RAM
    output reg          input_rd_en,
    output reg  [12:0]  input_rd_addr,
    input  wire [7:0]   input_rd_data,

    // OUTPUT FEATURE MAP RAM
    output reg          output_wr_en,
    output reg  [10:0]  output_wr_addr,
    output reg  [7:0]   output_wr_data,

    // STATUS
    output reg          busy,
    output reg          done,
    output reg          error
);

    // =====================================
    // CONFIGURATION
    // =====================================

    localparam integer OUTPUT_WIDTH =
        INPUT_WIDTH / 2;

    localparam integer INPUT_PIXELS_PER_CHANNEL =
        INPUT_WIDTH * INPUT_WIDTH;

    localparam integer OUTPUT_PIXELS_PER_CHANNEL =
        OUTPUT_WIDTH * OUTPUT_WIDTH;

    // =====================================
    // FSM STATES
    // =====================================

    localparam ST_IDLE       = 4'd0;
    localparam ST_READ_P00   = 4'd1;
    localparam ST_WAIT_P00   = 4'd2;
    localparam ST_READ_P01   = 4'd3;
    localparam ST_WAIT_P01   = 4'd4;
    localparam ST_READ_P10   = 4'd5;
    localparam ST_WAIT_P10   = 4'd6;
    localparam ST_READ_P11   = 4'd7;
    localparam ST_WAIT_P11   = 4'd8;
    localparam ST_WRITE      = 4'd9;

    reg [3:0] state;

    // =====================================
    // POSITION COUNTERS
    // =====================================

    reg [4:0] channel_index;
    reg [4:0] output_y;
    reg [4:0] output_x;

    // =====================================
    // PIXEL REGISTERS
    // =====================================

    reg [7:0] pixel00;
    reg [7:0] pixel01;
    reg [7:0] pixel10;
    reg [7:0] pixel11;

    // =====================================
    // INPUT ADDRESS GENERATION
    // Layout: [channel][y][x]
    // =====================================

    wire [12:0] input_addr_p00;
    wire [12:0] input_addr_p01;
    wire [12:0] input_addr_p10;
    wire [12:0] input_addr_p11;

    assign input_addr_p00 =
        (channel_index * INPUT_PIXELS_PER_CHANNEL) +
        ((output_y * 2) * INPUT_WIDTH) +
        (output_x * 2);

    assign input_addr_p01 =
        input_addr_p00 + 13'd1;

    assign input_addr_p10 =
        input_addr_p00 + INPUT_WIDTH;

    assign input_addr_p11 =
        input_addr_p10 + 13'd1;

    // =====================================
    // OUTPUT ADDRESS GENERATION
    // Layout: [channel][y][x]
    // =====================================

    wire [10:0] output_addr_calc;

    assign output_addr_calc =
        (channel_index * OUTPUT_PIXELS_PER_CHANNEL) +
        (output_y * OUTPUT_WIDTH) +
        output_x;

    // =====================================
    // MAXIMUM VALUE CALCULATION
    // =====================================

    wire [7:0] max_top;
    wire [7:0] max_bottom;
    wire [7:0] pooled_value;

    assign max_top =
        (pixel00 > pixel01) ?
        pixel00 : pixel01;

    assign max_bottom =
        (pixel10 > pixel11) ?
        pixel10 : pixel11;

    assign pooled_value =
        (max_top > max_bottom) ?
        max_top : max_bottom;

    // =====================================
    // COMBINATIONAL CONTROL
    // =====================================

    always @(*) begin

        input_rd_en   = 1'b0;
        input_rd_addr = 13'd0;

        output_wr_en   = 1'b0;
        output_wr_addr = 11'd0;
        output_wr_data = pooled_value;

        case (state)

            ST_READ_P00: begin
                input_rd_en   = 1'b1;
                input_rd_addr = input_addr_p00;
            end

            ST_READ_P01: begin
                input_rd_en   = 1'b1;
                input_rd_addr = input_addr_p01;
            end

            ST_READ_P10: begin
                input_rd_en   = 1'b1;
                input_rd_addr = input_addr_p10;
            end

            ST_READ_P11: begin
                input_rd_en   = 1'b1;
                input_rd_addr = input_addr_p11;
            end

            ST_WRITE: begin
                output_wr_en   = 1'b1;
                output_wr_addr = output_addr_calc;
                output_wr_data = pooled_value;
            end

            default: begin
            end

        endcase

    end

    // =====================================
    // MAIN FSM
    // =====================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state         <= ST_IDLE;

            channel_index <= 5'd0;
            output_y      <= 5'd0;
            output_x      <= 5'd0;

            pixel00 <= 8'd0;
            pixel01 <= 8'd0;
            pixel10 <= 8'd0;
            pixel11 <= 8'd0;

            busy  <= 1'b0;
            done  <= 1'b0;
            error <= 1'b0;

        end

        else begin

            done <= 1'b0;

            case (state)

                // =========================
                // IDLE
                // =========================

                ST_IDLE: begin

                    busy <= 1'b0;

                    if (start && !error) begin

                        if (
                            !(
                                (INPUT_WIDTH == 32 &&
                                 NUM_CHANNELS == 8) ||
                                (INPUT_WIDTH == 16 &&
                                 NUM_CHANNELS == 16)
                            )
                        ) begin

                            error <= 1'b1;

                        end

                        else begin

                            channel_index <= 5'd0;
                            output_y      <= 5'd0;
                            output_x      <= 5'd0;

                            busy  <= 1'b1;
                            state <= ST_READ_P00;

                        end

                    end

                end

                // =========================
                // READ PIXEL 00
                // =========================

                ST_READ_P00: begin
                    state <= ST_WAIT_P00;
                end

                ST_WAIT_P00: begin

                    pixel00 <= input_rd_data;

                    state <= ST_READ_P01;

                end

                // =========================
                // READ PIXEL 01
                // =========================

                ST_READ_P01: begin
                    state <= ST_WAIT_P01;
                end

                ST_WAIT_P01: begin

                    pixel01 <= input_rd_data;

                    state <= ST_READ_P10;

                end

                // =========================
                // READ PIXEL 10
                // =========================

                ST_READ_P10: begin
                    state <= ST_WAIT_P10;
                end

                ST_WAIT_P10: begin

                    pixel10 <= input_rd_data;

                    state <= ST_READ_P11;

                end

                // =========================
                // READ PIXEL 11
                // =========================

                ST_READ_P11: begin
                    state <= ST_WAIT_P11;
                end

                ST_WAIT_P11: begin

                    pixel11 <= input_rd_data;

                    state <= ST_WRITE;

                end

                // =========================
                // WRITE OUTPUT
                // =========================

                ST_WRITE: begin

                    if (output_x == OUTPUT_WIDTH - 1) begin

                        output_x <= 5'd0;

                        if (output_y == OUTPUT_WIDTH - 1) begin

                            output_y <= 5'd0;

                            if (channel_index == NUM_CHANNELS - 1) begin

                                busy  <= 1'b0;
                                done  <= 1'b1;

                                state <= ST_IDLE;

                            end

                            else begin

                                channel_index <=
                                    channel_index + 1'b1;

                                state <= ST_READ_P00;

                            end

                        end

                        else begin

                            output_y <= output_y + 1'b1;

                            state <= ST_READ_P00;

                        end

                    end

                    else begin

                        output_x <= output_x + 1'b1;

                        state <= ST_READ_P00;

                    end

                end

                // =========================
                // DEFAULT
                // =========================

                default: begin

                    state <= ST_IDLE;
                    busy  <= 1'b0;
                    error <= 1'b1;

                end

            endcase

        end

    end

endmodule
