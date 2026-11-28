
`timescale 1ns/1ps

module tb_maxpool_engine_ptq_run1;

    // =====================================
    // CONFIGURATION
    // =====================================

    localparam NUM_IMAGES = 14;

    localparam P1_INPUTS_PER_IMAGE  = 8192;
    localparam P1_OUTPUTS_PER_IMAGE = 2048;

    localparam P2_INPUTS_PER_IMAGE  = 4096;
    localparam P2_OUTPUTS_PER_IMAGE = 1024;

    localparam P1_TOTAL_INPUTS  = 114688;
    localparam P1_TOTAL_OUTPUTS = 28672;

    localparam P2_TOTAL_INPUTS  = 57344;
    localparam P2_TOTAL_OUTPUTS = 14336;

    // =====================================
    // CLOCK AND RESET
    // =====================================

    reg clk;
    reg rst_n;

    always #5 clk = ~clk;

    // =====================================
    // POOL1 SIGNALS
    // =====================================

    reg p1_start;

    wire p1_input_rd_en;
    wire [12:0] p1_input_rd_addr;
    reg [7:0] p1_input_rd_data;

    wire p1_output_wr_en;
    wire [10:0] p1_output_wr_addr;
    wire [7:0] p1_output_wr_data;

    wire p1_busy;
    wire p1_done;
    wire p1_error;

    // =====================================
    // POOL2 SIGNALS
    // =====================================

    reg p2_start;

    wire p2_input_rd_en;
    wire [12:0] p2_input_rd_addr;
    reg [7:0] p2_input_rd_data;

    wire p2_output_wr_en;
    wire [10:0] p2_output_wr_addr;
    wire [7:0] p2_output_wr_data;

    wire p2_busy;
    wire p2_done;
    wire p2_error;

    // =====================================
    // GOLDEN MEMORIES
    // =====================================

    reg [7:0] p1_input_mem [0:P1_TOTAL_INPUTS-1];

    reg [7:0] p1_expected_mem [0:P1_TOTAL_OUTPUTS-1];

    reg [7:0] p2_input_mem [0:P2_TOTAL_INPUTS-1];

    reg [7:0] p2_expected_mem [0:P2_TOTAL_OUTPUTS-1];

    // =====================================
    // OUTPUT ADDRESS TRACKING
    // =====================================

    reg p1_seen [0:P1_OUTPUTS_PER_IMAGE-1];

    reg p2_seen [0:P2_OUTPUTS_PER_IMAGE-1];

    // =====================================
    // IMAGE INDEX
    // =====================================

    integer p1_image_index;
    integer p2_image_index;

    integer p1_input_index;
    integer p1_output_index;

    integer p2_input_index;
    integer p2_output_index;

    // =====================================
    // VERIFICATION COUNTERS
    // =====================================

    integer p1_read_count;
    integer p1_total_read_count;

    integer p1_write_count;
    integer p1_total_write_count;

    integer p1_mismatch_count;
    integer p1_duplicate_count;
    integer p1_address_error_count;
    integer p1_missing_count;
    integer p1_failed_images;

    integer p2_read_count;
    integer p2_total_read_count;

    integer p2_write_count;
    integer p2_total_write_count;

    integer p2_mismatch_count;
    integer p2_duplicate_count;
    integer p2_address_error_count;
    integer p2_missing_count;
    integer p2_failed_images;

    integer mismatch_before;
    integer duplicate_before;
    integer address_before;
    integer missing_before;

    integer timeout_count;

    integer i;
    integer j;

    // =====================================
    // POOL1 DUT
    // =====================================

    maxpool_engine #(
        .INPUT_WIDTH(32),
        .NUM_CHANNELS(8)
    ) u_pool1 (

        .clk(clk),
        .rst_n(rst_n),
        .start(p1_start),

        .input_rd_en(p1_input_rd_en),
        .input_rd_addr(p1_input_rd_addr),
        .input_rd_data(p1_input_rd_data),

        .output_wr_en(p1_output_wr_en),
        .output_wr_addr(p1_output_wr_addr),
        .output_wr_data(p1_output_wr_data),

        .busy(p1_busy),
        .done(p1_done),
        .error(p1_error)

    );

    // =====================================
    // POOL2 DUT
    // =====================================

    maxpool_engine #(
        .INPUT_WIDTH(16),
        .NUM_CHANNELS(16)
    ) u_pool2 (

        .clk(clk),
        .rst_n(rst_n),
        .start(p2_start),

        .input_rd_en(p2_input_rd_en),
        .input_rd_addr(p2_input_rd_addr),
        .input_rd_data(p2_input_rd_data),

        .output_wr_en(p2_output_wr_en),
        .output_wr_addr(p2_output_wr_addr),
        .output_wr_data(p2_output_wr_data),

        .busy(p2_busy),
        .done(p2_done),
        .error(p2_error)

    );

    // =====================================
    // SYNCHRONOUS RAM MODELS
    // =====================================

    always @(posedge clk) begin

        if (!rst_n) begin

            p1_input_rd_data <= 8'd0;
            p2_input_rd_data <= 8'd0;

        end

        else begin

            // =================================
            // POOL1 INPUT RAM
            // =================================

            if (p1_input_rd_en) begin

                p1_input_index =
                    p1_image_index * P1_INPUTS_PER_IMAGE
                    + p1_input_rd_addr;

                if (
                    p1_input_rd_addr < P1_INPUTS_PER_IMAGE &&
                    p1_input_index >= 0 &&
                    p1_input_index < P1_TOTAL_INPUTS
                ) begin

                    p1_input_rd_data <=
                        p1_input_mem[p1_input_index];

                    p1_read_count =
                        p1_read_count + 1;

                    p1_total_read_count =
                        p1_total_read_count + 1;

                end

                else begin

                    p1_input_rd_data <= 8'd0;

                    p1_address_error_count =
                        p1_address_error_count + 1;

                    $display(
                        "POOL1 INPUT ADDRESS ERROR: %0d",
                        p1_input_rd_addr
                    );

                end

            end

            // =================================
            // POOL1 OUTPUT RAM
            // =================================

            if (p1_output_wr_en) begin

                p1_output_index =
                    p1_image_index * P1_OUTPUTS_PER_IMAGE
                    + p1_output_wr_addr;

                if (
                    p1_output_wr_addr < P1_OUTPUTS_PER_IMAGE &&
                    p1_output_index >= 0 &&
                    p1_output_index < P1_TOTAL_OUTPUTS
                ) begin

                    p1_write_count =
                        p1_write_count + 1;

                    p1_total_write_count =
                        p1_total_write_count + 1;

                    if (p1_seen[p1_output_wr_addr]) begin

                        p1_duplicate_count =
                            p1_duplicate_count + 1;

                    end

                    else begin

                        p1_seen[p1_output_wr_addr] = 1'b1;

                    end

                    if (
                        p1_output_wr_data !==
                        p1_expected_mem[p1_output_index]
                    ) begin

                        p1_mismatch_count =
                            p1_mismatch_count + 1;

                        if (p1_mismatch_count <= 20) begin

                            $display(
                                "POOL1 MISMATCH IMAGE=%0d ADDR=%0d RTL=%0d EXPECTED=%0d",
                                p1_image_index + 1,
                                p1_output_wr_addr,
                                p1_output_wr_data,
                                p1_expected_mem[p1_output_index]
                            );

                        end

                    end

                end

                else begin

                    p1_address_error_count =
                        p1_address_error_count + 1;

                    $display(
                        "POOL1 OUTPUT ADDRESS ERROR: %0d",
                        p1_output_wr_addr
                    );

                end

            end

            // =================================
            // POOL2 INPUT RAM
            // =================================

            if (p2_input_rd_en) begin

                p2_input_index =
                    p2_image_index * P2_INPUTS_PER_IMAGE
                    + p2_input_rd_addr;

                if (
                    p2_input_rd_addr < P2_INPUTS_PER_IMAGE &&
                    p2_input_index >= 0 &&
                    p2_input_index < P2_TOTAL_INPUTS
                ) begin

                    p2_input_rd_data <=
                        p2_input_mem[p2_input_index];

                    p2_read_count =
                        p2_read_count + 1;

                    p2_total_read_count =
                        p2_total_read_count + 1;

                end

                else begin

                    p2_input_rd_data <= 8'd0;

                    p2_address_error_count =
                        p2_address_error_count + 1;

                    $display(
                        "POOL2 INPUT ADDRESS ERROR: %0d",
                        p2_input_rd_addr
                    );

                end

            end

            // =================================
            // POOL2 OUTPUT RAM
            // =================================

            if (p2_output_wr_en) begin

                p2_output_index =
                    p2_image_index * P2_OUTPUTS_PER_IMAGE
                    + p2_output_wr_addr;

                if (
                    p2_output_wr_addr < P2_OUTPUTS_PER_IMAGE &&
                    p2_output_index >= 0 &&
                    p2_output_index < P2_TOTAL_OUTPUTS
                ) begin

                    p2_write_count =
                        p2_write_count + 1;

                    p2_total_write_count =
                        p2_total_write_count + 1;

                    if (p2_seen[p2_output_wr_addr]) begin

                        p2_duplicate_count =
                            p2_duplicate_count + 1;

                    end

                    else begin

                        p2_seen[p2_output_wr_addr] = 1'b1;

                    end

                    if (
                        p2_output_wr_data !==
                        p2_expected_mem[p2_output_index]
                    ) begin

                        p2_mismatch_count =
                            p2_mismatch_count + 1;

                        if (p2_mismatch_count <= 20) begin

                            $display(
                                "POOL2 MISMATCH IMAGE=%0d ADDR=%0d RTL=%0d EXPECTED=%0d",
                                p2_image_index + 1,
                                p2_output_wr_addr,
                                p2_output_wr_data,
                                p2_expected_mem[p2_output_index]
                            );

                        end

                    end

                end

                else begin

                    p2_address_error_count =
                        p2_address_error_count + 1;

                    $display(
                        "POOL2 OUTPUT ADDRESS ERROR: %0d",
                        p2_output_wr_addr
                    );

                end

            end

        end

    end

    // =====================================
    // MAIN TEST
    // =====================================

    initial begin

        clk = 1'b0;
        rst_n = 1'b0;

        p1_start = 1'b0;
        p2_start = 1'b0;

        p1_image_index = 0;
        p2_image_index = 0;

        p1_read_count = 0;
        p1_total_read_count = 0;
        p1_write_count = 0;
        p1_total_write_count = 0;

        p1_mismatch_count = 0;
        p1_duplicate_count = 0;
        p1_address_error_count = 0;
        p1_missing_count = 0;
        p1_failed_images = 0;

        p2_read_count = 0;
        p2_total_read_count = 0;
        p2_write_count = 0;
        p2_total_write_count = 0;

        p2_mismatch_count = 0;
        p2_duplicate_count = 0;
        p2_address_error_count = 0;
        p2_missing_count = 0;
        p2_failed_images = 0;

        timeout_count = 0;

        // =================================
        // LOAD GOLDEN MEMORIES
        // =================================

        $display("========================================");
        $display("LOADING MAXPOOL GOLDEN MEMORIES");
        $display("========================================");

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/maxpool_golden_run1/pool1_input_features_u8.mem",
            p1_input_mem
        );

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/maxpool_golden_run1/pool1_expected_outputs_u8.mem",
            p1_expected_mem
        );

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/maxpool_golden_run1/pool2_input_features_u8.mem",
            p2_input_mem
        );

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/maxpool_golden_run1/pool2_expected_outputs_u8.mem",
            p2_expected_mem
        );

        $display("Pool1 golden loading: PASS");
        $display("Pool2 golden loading: PASS");

        // =================================
        // RESET
        // =================================

        repeat (5) @(negedge clk);

        rst_n = 1'b1;

        // =================================
        // POOL1 VERIFICATION
        // =================================

        $display("");
        $display("========================================");
        $display("START POOL1 VERIFICATION");
        $display("========================================");

        for (i = 0; i < NUM_IMAGES; i = i + 1) begin

            p1_image_index = i;

            p1_read_count = 0;
            p1_write_count = 0;

            mismatch_before = p1_mismatch_count;
            duplicate_before = p1_duplicate_count;
            address_before = p1_address_error_count;
            missing_before = p1_missing_count;

            for (j = 0; j < P1_OUTPUTS_PER_IMAGE; j = j + 1)
                p1_seen[j] = 1'b0;

            @(negedge clk);
            p1_start = 1'b1;

            @(negedge clk);
            p1_start = 1'b0;

            timeout_count = 0;

            while (
                p1_done !== 1'b1 &&
                timeout_count < 50000
            ) begin

                @(negedge clk);
                timeout_count = timeout_count + 1;

            end

            if (p1_done !== 1'b1) begin

                $fatal(
                    1,
                    "POOL1 TIMEOUT IMAGE %0d",
                    i + 1
                );

            end

            @(negedge clk);

            // Check missing output addresses.

            for (j = 0; j < P1_OUTPUTS_PER_IMAGE; j = j + 1) begin

                if (!p1_seen[j])
                    p1_missing_count =
                        p1_missing_count + 1;

            end

            if (
                p1_read_count != P1_INPUTS_PER_IMAGE ||
                p1_write_count != P1_OUTPUTS_PER_IMAGE ||
                p1_mismatch_count != mismatch_before ||
                p1_duplicate_count != duplicate_before ||
                p1_address_error_count != address_before ||
                p1_missing_count != missing_before ||
                p1_error
            ) begin

                p1_failed_images =
                    p1_failed_images + 1;

                $display(
                    "POOL1 IMAGE %0d: FAIL",
                    i + 1
                );

                $display(
                    "Reads=%0d Writes=%0d",
                    p1_read_count,
                    p1_write_count
                );

            end

            else begin

                $display(
                    "POOL1 IMAGE %0d: PASS | Reads=%0d Writes=%0d",
                    i + 1,
                    p1_read_count,
                    p1_write_count
                );

            end

        end

        // =================================
        // POOL2 VERIFICATION
        // =================================

        $display("");
        $display("========================================");
        $display("START POOL2 VERIFICATION");
        $display("========================================");

        for (i = 0; i < NUM_IMAGES; i = i + 1) begin

            p2_image_index = i;

            p2_read_count = 0;
            p2_write_count = 0;

            mismatch_before = p2_mismatch_count;
            duplicate_before = p2_duplicate_count;
            address_before = p2_address_error_count;
            missing_before = p2_missing_count;

            for (j = 0; j < P2_OUTPUTS_PER_IMAGE; j = j + 1)
                p2_seen[j] = 1'b0;

            @(negedge clk);
            p2_start = 1'b1;

            @(negedge clk);
            p2_start = 1'b0;

            timeout_count = 0;

            while (
                p2_done !== 1'b1 &&
                timeout_count < 50000
            ) begin

                @(negedge clk);
                timeout_count = timeout_count + 1;

            end

            if (p2_done !== 1'b1) begin

                $fatal(
                    1,
                    "POOL2 TIMEOUT IMAGE %0d",
                    i + 1
                );

            end

            @(negedge clk);

            for (j = 0; j < P2_OUTPUTS_PER_IMAGE; j = j + 1) begin

                if (!p2_seen[j])
                    p2_missing_count =
                        p2_missing_count + 1;

            end

            if (
                p2_read_count != P2_INPUTS_PER_IMAGE ||
                p2_write_count != P2_OUTPUTS_PER_IMAGE ||
                p2_mismatch_count != mismatch_before ||
                p2_duplicate_count != duplicate_before ||
                p2_address_error_count != address_before ||
                p2_missing_count != missing_before ||
                p2_error
            ) begin

                p2_failed_images =
                    p2_failed_images + 1;

                $display(
                    "POOL2 IMAGE %0d: FAIL",
                    i + 1
                );

                $display(
                    "Reads=%0d Writes=%0d",
                    p2_read_count,
                    p2_write_count
                );

            end

            else begin

                $display(
                    "POOL2 IMAGE %0d: PASS | Reads=%0d Writes=%0d",
                    i + 1,
                    p2_read_count,
                    p2_write_count
                );

            end

        end

        // =================================
        // FINAL SUMMARY
        // =================================

        $display("");
        $display("========================================");
        $display("FINAL MAXPOOL ENGINE VERIFICATION");
        $display("========================================");

        $display("");
        $display("POOL1:");

        $display("Total input reads  : %0d", p1_total_read_count);
        $display("Total output writes: %0d", p1_total_write_count);
        $display("Expected reads     : %0d", P1_TOTAL_INPUTS);
        $display("Expected writes    : %0d", P1_TOTAL_OUTPUTS);

        $display("Mismatches         : %0d", p1_mismatch_count);
        $display("Duplicate addresses: %0d", p1_duplicate_count);
        $display("Address errors     : %0d", p1_address_error_count);
        $display("Missing outputs    : %0d", p1_missing_count);
        $display("Failed images      : %0d", p1_failed_images);

        $display("");
        $display("POOL2:");

        $display("Total input reads  : %0d", p2_total_read_count);
        $display("Total output writes: %0d", p2_total_write_count);
        $display("Expected reads     : %0d", P2_TOTAL_INPUTS);
        $display("Expected writes    : %0d", P2_TOTAL_OUTPUTS);

        $display("Mismatches         : %0d", p2_mismatch_count);
        $display("Duplicate addresses: %0d", p2_duplicate_count);
        $display("Address errors     : %0d", p2_address_error_count);
        $display("Missing outputs    : %0d", p2_missing_count);
        $display("Failed images      : %0d", p2_failed_images);

        // =================================
        // PASS / FAIL
        // =================================

        if (
            p1_total_read_count == P1_TOTAL_INPUTS &&
            p1_total_write_count == P1_TOTAL_OUTPUTS &&
            p1_mismatch_count == 0 &&
            p1_duplicate_count == 0 &&
            p1_address_error_count == 0 &&
            p1_missing_count == 0 &&
            p1_failed_images == 0 &&
            !p1_error &&

            p2_total_read_count == P2_TOTAL_INPUTS &&
            p2_total_write_count == P2_TOTAL_OUTPUTS &&
            p2_mismatch_count == 0 &&
            p2_duplicate_count == 0 &&
            p2_address_error_count == 0 &&
            p2_missing_count == 0 &&
            p2_failed_images == 0 &&
            !p2_error
        ) begin

            $display("");
            $display("========================================");
            $display("MAXPOOL ENGINE VERIFICATION PASS");
            $display("ZERO MISMATCH");
            $display("ALL 14 IMAGES VERIFIED");
            $display("POOL1 AND POOL2 EXACT MATCH");
            $display("========================================");

        end

        else begin

            $fatal(
                1,
                "MAXPOOL ENGINE VERIFICATION FAILED"
            );

        end

        $finish;

    end

endmodule
