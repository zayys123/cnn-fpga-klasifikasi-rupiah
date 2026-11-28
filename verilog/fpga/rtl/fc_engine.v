module fc_engine (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,

    // GAP OUTPUT RAM: 24 UINT14 VALUES PER IMAGE
    output reg                input_rd_en,
    output reg  [4:0]         input_rd_addr,
    input  wire [13:0]        input_rd_data,

    // FC WEIGHT ROM: [class][channel], 7 x 24 SIGNED INT8
    output reg                weight_rd_en,
    output reg  [7:0]         weight_rd_addr,
    input  wire signed [7:0]  weight_rd_data,

    // FC BIAS ROM: 7 SIGNED INT32 VALUES
    output reg                bias_rd_en,
    output reg  [2:0]         bias_rd_addr,
    input  wire signed [31:0] bias_rd_data,

    // LOGIT OUTPUT RAM: 7 SIGNED INT32 VALUES
    output reg                output_wr_en,
    output reg  [2:0]         output_wr_addr,
    output reg  signed [31:0] output_wr_data,

    // STATUS
    output reg                busy,
    output reg                done,
    output reg                error
);

    localparam NUM_CLASSES  = 7;
    localparam NUM_FEATURES = 24;

    localparam ST_IDLE        = 3'd0;
    localparam ST_BIAS_REQ    = 3'd1;
    localparam ST_BIAS_LOAD   = 3'd2;
    localparam ST_FEATURE_REQ = 3'd3;
    localparam ST_MAC         = 3'd4;
    localparam ST_WRITE       = 3'd5;

    reg [2:0] state;
    reg [2:0] class_index;
    reg [4:0] feature_index;

    reg signed [63:0] accumulator;
    reg signed [31:0] logit_result;

    wire [7:0] weight_addr_calc;

    assign weight_addr_calc =
        (class_index * 8'd24) + {3'd0, feature_index};

    // Explicitly extend UINT14 input and signed INT8 weight to INT64.
    wire signed [63:0] activation_ext;
    wire signed [63:0] weight_ext;
    wire signed [63:0] product;
    wire signed [63:0] sum_next;
    wire signed [63:0] bias_ext;
    wire sum_fits_int32;

    assign activation_ext = $signed({50'd0, input_rd_data});
    assign weight_ext = {{56{weight_rd_data[7]}}, weight_rd_data};
    assign product = activation_ext * weight_ext;
    assign sum_next = accumulator + product;
    assign bias_ext = {{32{bias_rd_data[31]}}, bias_rd_data};

    // A signed 64-bit value fits INT32 when its upper 32 bits
    // are all copies of bit 31.
    assign sum_fits_int32 =
        (sum_next[63:32] == {32{sum_next[31]}});

    // ============================================================
    // SYNCHRONOUS MEMORY CONTROL
    // ============================================================

    always @(*) begin
        input_rd_en    = 1'b0;
        input_rd_addr  = 5'd0;

        weight_rd_en   = 1'b0;
        weight_rd_addr = 8'd0;

        bias_rd_en     = 1'b0;
        bias_rd_addr   = class_index;

        output_wr_en   = 1'b0;
        output_wr_addr = class_index;
        output_wr_data = logit_result;

        case (state)
            ST_BIAS_REQ: begin
                bias_rd_en   = 1'b1;
                bias_rd_addr = class_index;
            end

            ST_FEATURE_REQ: begin
                input_rd_en    = 1'b1;
                input_rd_addr  = feature_index;

                weight_rd_en   = 1'b1;
                weight_rd_addr = weight_addr_calc;
            end

            ST_WRITE: begin
                output_wr_en   = 1'b1;
                output_wr_addr = class_index;
                output_wr_data = logit_result;
            end

            default: begin
            end
        endcase
    end

    // ============================================================
    // MAIN FSM
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            class_index   <= 3'd0;
            feature_index <= 5'd0;
            accumulator   <= 64'sd0;
            logit_result  <= 32'sd0;
            busy          <= 1'b0;
            done          <= 1'b0;
            error         <= 1'b0;
        end
        else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;

                    if (start && !error) begin
                        class_index   <= 3'd0;
                        feature_index <= 5'd0;
                        accumulator   <= 64'sd0;
                        logit_result  <= 32'sd0;
                        busy          <= 1'b1;
                        state         <= ST_BIAS_REQ;
                    end
                end

                // Bias ROM is synchronous: request, then load next cycle.
                ST_BIAS_REQ: begin
                    state <= ST_BIAS_LOAD;
                end

                ST_BIAS_LOAD: begin
                    accumulator   <= bias_ext;
                    feature_index <= 5'd0;
                    state         <= ST_FEATURE_REQ;
                end

                // GAP RAM and weight ROM are read synchronously in parallel.
                ST_FEATURE_REQ: begin
                    state <= ST_MAC;
                end

                ST_MAC: begin
                    // Match the Python reference: accumulate in INT64 and
                    // validate INT32 range only after the final feature.
                    if (feature_index == 5'd23) begin
                        if (!sum_fits_int32) begin
                            error <= 1'b1;
                            busy  <= 1'b0;
                            state <= ST_IDLE;
                        end
                        else begin
                            logit_result <= sum_next[31:0];
                            state        <= ST_WRITE;
                        end
                    end
                    else begin
                        accumulator   <= sum_next;
                        feature_index <= feature_index + 1'b1;
                        state         <= ST_FEATURE_REQ;
                    end
                end

                ST_WRITE: begin
                    if (class_index == 3'd6) begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                    else begin
                        class_index <= class_index + 1'b1;
                        state       <= ST_BIAS_REQ;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                    busy  <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
    end

endmodule
