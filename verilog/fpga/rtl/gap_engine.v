module gap_engine (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,

    // INPUT FEATURE MAP RAM
    output reg                input_rd_en,
    output reg  [10:0]        input_rd_addr,
    input  wire [7:0]         input_rd_data,

    // GAP OUTPUT RAM
    output reg                output_wr_en,
    output reg  [4:0]         output_wr_addr,
    output reg  [13:0]        output_wr_data,

    // STATUS
    output reg                busy,
    output reg                done,
    output reg                error
);

    // =====================================
    // CONSTANTS
    // =====================================

    localparam NUM_CHANNELS = 24;
    localparam PIXELS_PER_CHANNEL = 64;

    localparam LAST_CHANNEL = 5'd23;
    localparam LAST_PIXEL   = 6'd63;

    // =====================================
    // FSM STATES
    // =====================================

    localparam ST_IDLE        = 2'd0;
    localparam ST_READ_REQ    = 2'd1;
    localparam ST_ACCUMULATE  = 2'd2;
    localparam ST_WRITE       = 2'd3;

    reg [1:0] state;

    // =====================================
    // POSITION COUNTERS
    // =====================================

    reg [4:0] channel_index;
    reg [5:0] pixel_index;

    // =====================================
    // ACCUMULATOR
    // =====================================

    reg [13:0] accumulator;
    reg [13:0] gap_result;

    // Extended sum for overflow detection
    wire [14:0] sum_extended;

    assign sum_extended =
        {1'b0, accumulator} +
        {7'd0, input_rd_data};

    // =====================================
    // INPUT ADDRESS GENERATION
    // Layout: [channel][y][x]
    // =====================================

    wire [10:0] input_addr_calc;

    assign input_addr_calc = {
        channel_index,
        pixel_index
    };

    // =====================================
    // COMBINATIONAL CONTROL
    // =====================================

    always @(*) begin

        input_rd_en   = 1'b0;
        input_rd_addr = 11'd0;

        output_wr_en   = 1'b0;
        output_wr_addr = 5'd0;
        output_wr_data = gap_result;

        case (state)

            ST_READ_REQ: begin

                input_rd_en   = 1'b1;
                input_rd_addr = input_addr_calc;

            end

            ST_WRITE: begin

                output_wr_en   = 1'b1;
                output_wr_addr = channel_index;
                output_wr_data = gap_result;

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
            pixel_index   <= 6'd0;

            accumulator   <= 14'd0;
            gap_result    <= 14'd0;

            busy          <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;

        end

        else begin

            done <= 1'b0;

            case (state)

                // =================================
                // IDLE
                // =================================

                ST_IDLE: begin

                    busy <= 1'b0;

                    if (start && !error) begin

                        channel_index <= 5'd0;
                        pixel_index   <= 6'd0;

                        accumulator   <= 14'd0;
                        gap_result    <= 14'd0;

                        busy  <= 1'b1;
                        state <= ST_READ_REQ;

                    end

                end

                // =================================
                // READ REQUEST
                // =================================

                ST_READ_REQ: begin

                    // Synchronous RAM captures address
                    // and updates input_rd_data.

                    state <= ST_ACCUMULATE;

                end

                // =================================
                // ACCUMULATE
                // =================================

                ST_ACCUMULATE: begin

                    // Detect overflow beyond UINT14.
                    if (sum_extended[14]) begin

                        error <= 1'b1;
                        busy  <= 1'b0;
                        state <= ST_IDLE;

                    end

                    // Last pixel in current channel.
                    else if (pixel_index == LAST_PIXEL) begin

                        gap_result <= sum_extended[13:0];

                        state <= ST_WRITE;

                    end

                    // Continue accumulating.
                    else begin

                        accumulator <= sum_extended[13:0];

                        pixel_index <= pixel_index + 1'b1;

                        state <= ST_READ_REQ;

                    end

                end

                // =================================
                // WRITE GAP RESULT
                // =================================

                ST_WRITE: begin

                    if (channel_index == LAST_CHANNEL) begin

                        busy  <= 1'b0;
                        done  <= 1'b1;

                        state <= ST_IDLE;

                    end

                    else begin

                        channel_index <= channel_index + 1'b1;

                        pixel_index <= 6'd0;

                        accumulator <= 14'd0;
                        gap_result  <= 14'd0;

                        state <= ST_READ_REQ;

                    end

                end

                // =================================
                // DEFAULT
                // =================================

                default: begin

                    state <= ST_IDLE;
                    busy  <= 1'b0;
                    error <= 1'b1;

                end

            endcase

        end

    end

endmodule