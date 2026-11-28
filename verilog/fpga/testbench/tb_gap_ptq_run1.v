`timescale 1ns/1ps

module tb_gap_ptq_run1;

    // =====================================
    // CONSTANTS
    // =====================================

    localparam NUM_IMAGES = 14;

    localparam INPUT_VALUES_PER_IMAGE = 1536;
    localparam OUTPUTS_PER_IMAGE = 24;

    localparam TOTAL_INPUTS = 21504;
    localparam TOTAL_OUTPUTS = 336;

    // =====================================
    // SIGNALS
    // =====================================

    reg clk;
    reg rst_n;
    reg start;

    wire input_rd_en;
    wire [10:0] input_rd_addr;
    reg [7:0] input_rd_data;

    wire output_wr_en;
    wire [4:0] output_wr_addr;
    wire [13:0] output_wr_data;

    wire busy;
    wire done;
    wire error;

    // =====================================
    // GOLDEN MEMORIES
    // =====================================

    reg [7:0] input_mem [0:TOTAL_INPUTS-1];

    reg [13:0] expected_mem [0:TOTAL_OUTPUTS-1];

    reg seen [0:OUTPUTS_PER_IMAGE-1];

    // =====================================
    // COUNTERS
    // =====================================

    integer image_index;
    integer input_index;
    integer expected_index;

    integer i;

    integer read_count;
    integer total_read_count;

    integer write_count;
    integer total_write_count;

    integer gap_mismatch_count;
    integer duplicate_count;
    integer address_error_count;
    integer missing_count;
    integer image_fail_count;

    integer mismatch_before;
    integer duplicate_before;
    integer address_before;
    integer missing_before;

    integer timeout_count;

    // =====================================
    // CLOCK
    // =====================================

    always #5 clk = ~clk;

    // =====================================
    // DUT
    // =====================================

    gap_engine dut (

        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .input_rd_en(input_rd_en),
        .input_rd_addr(input_rd_addr),
        .input_rd_data(input_rd_data),

        .output_wr_en(output_wr_en),
        .output_wr_addr(output_wr_addr),
        .output_wr_data(output_wr_data),

        .busy(busy),
        .done(done),
        .error(error)

    );

    // =====================================
    // SYNCHRONOUS RAM MODEL
    // =====================================

    always @(posedge clk) begin

        if (!rst_n) begin

            input_rd_data <= 8'd0;

        end

        else begin

            // INPUT FEATURE MAP RAM

            if (input_rd_en) begin

                input_index =
                    image_index * INPUT_VALUES_PER_IMAGE
                    + input_rd_addr;

                if (
                    input_rd_addr < 11'd1536 &&
                    input_index >= 0 &&
                    input_index < TOTAL_INPUTS
                ) begin

                    input_rd_data <= input_mem[input_index];

                    read_count = read_count + 1;

                    total_read_count =
                        total_read_count + 1;

                end

                else begin

                    input_rd_data <= 8'd0;

                    address_error_count =
                        address_error_count + 1;

                    $display(
                        "ERROR: Invalid input address %0d",
                        input_rd_addr
                    );

                end

            end

            // GAP OUTPUT RAM MONITOR

            if (output_wr_en) begin

                expected_index =
                    image_index * OUTPUTS_PER_IMAGE
                    + output_wr_addr;

                if (
                    output_wr_addr < 5'd24 &&
                    expected_index >= 0 &&
                    expected_index < TOTAL_OUTPUTS
                ) begin

                    // Compare GAP result

                    if (
                        output_wr_data !==
                        expected_mem[expected_index]
                    ) begin

                        gap_mismatch_count =
                            gap_mismatch_count + 1;

                        if (gap_mismatch_count <= 20) begin

                            $display(
                                "GAP MISMATCH: Image=%0d Channel=%0d Expected=%04h Actual=%04h",
                                image_index + 1,
                                output_wr_addr,
                                expected_mem[expected_index],
                                output_wr_data
                            );

                        end

                    end

                    // Duplicate address detection

                    if (seen[output_wr_addr] === 1'b1) begin

                        duplicate_count =
                            duplicate_count + 1;

                    end

                    else begin

                        seen[output_wr_addr] = 1'b1;

                    end

                    write_count = write_count + 1;

                    total_write_count =
                        total_write_count + 1;

                end

                else begin

                    address_error_count =
                        address_error_count + 1;

                    $display(
                        "ERROR: Invalid output address %0d",
                        output_wr_addr
                    );

                end

            end

        end

    end

    // =====================================
    // PER-IMAGE TIMEOUT
    // =====================================

    initial begin

        #5000000;

        $display("FATAL: GLOBAL SIMULATION TIMEOUT");

        $finish;

    end

    // =====================================
    // MAIN TEST
    // =====================================

    initial begin

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;

        image_index = 0;
        input_index = 0;
        expected_index = 0;

        read_count = 0;
        total_read_count = 0;

        write_count = 0;
        total_write_count = 0;

        gap_mismatch_count = 0;
        duplicate_count = 0;
        address_error_count = 0;
        missing_count = 0;
        image_fail_count = 0;

        mismatch_before = 0;
        duplicate_before = 0;
        address_before = 0;
        missing_before = 0;

        timeout_count = 0;

        // =================================
        // LOAD GOLDEN MEMORIES
        // =================================

        $display("");
        $display("========================================");
        $display("GAP PTQ RUN1 RTL VERIFICATION");
        $display("========================================");

        $display("Images              : %0d", NUM_IMAGES);
        $display("Input values        : %0d", TOTAL_INPUTS);
        $display("Output values       : %0d", TOTAL_OUTPUTS);

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/gap_golden_run1/gap_input_features_u8.mem",
            input_mem
        );

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/gap_golden_run1/gap_expected_sums_u14.mem",
            expected_mem
        );

        $display("Golden memory loading: PASS");

        // =================================
        // RESET
        // =================================

        repeat (5) @(negedge clk);

        rst_n = 1'b1;

        // =================================
        // TEST ALL 14 IMAGES
        // =================================

        for (
            image_index = 0;
            image_index < NUM_IMAGES;
            image_index = image_index + 1
        ) begin

            $display("");
            $display("----------------------------------------");
            $display(
                "TEST IMAGE %0d / %0d",
                image_index + 1,
                NUM_IMAGES
            );
            $display("----------------------------------------");

            // Reset per-image counters

            read_count = 0;
            write_count = 0;

            // Clear address tracking

            for (i = 0; i < OUTPUTS_PER_IMAGE; i = i + 1)
                seen[i] = 1'b0;

            // Save previous error counters

            mismatch_before = gap_mismatch_count;
            duplicate_before = duplicate_count;
            address_before = address_error_count;
            missing_before = missing_count;

            // START ENGINE

            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            // WAIT FOR DONE WITH TIMEOUT

            timeout_count = 0;

            while (
                done !== 1'b1 &&
                timeout_count < 10000
            ) begin

                @(posedge clk);

                timeout_count = timeout_count + 1;

            end

            if (done !== 1'b1) begin

                $display(
                    "FATAL: TIMEOUT ON IMAGE %0d",
                    image_index + 1
                );

                $display("Busy  : %b", busy);
                $display("Error : %b", error);

                $finish;

            end

            @(negedge clk);

            // =================================
            // CHECK MISSING CHANNELS
            // =================================

            for (
                i = 0;
                i < OUTPUTS_PER_IMAGE;
                i = i + 1
            ) begin

                if (seen[i] !== 1'b1) begin

                    missing_count = missing_count + 1;

                    $display(
                        "MISSING GAP CHANNEL: Image=%0d Channel=%0d",
                        image_index + 1,
                        i
                    );

                end

            end

            // =================================
            // PER-IMAGE RESULT
            // =================================

            if (
                read_count != INPUT_VALUES_PER_IMAGE ||
                write_count != OUTPUTS_PER_IMAGE ||
                gap_mismatch_count != mismatch_before ||
                duplicate_count != duplicate_before ||
                address_error_count != address_before ||
                missing_count != missing_before ||
                error !== 1'b0
            ) begin

                image_fail_count =
                    image_fail_count + 1;

                $display("IMAGE %0d: FAIL", image_index + 1);

                $display("Input reads : %0d", read_count);
                $display("GAP writes  : %0d", write_count);

            end

            else begin

                $display(
                    "IMAGE %0d: PASS",
                    image_index + 1
                );

                $display(
                    "Input reads: %0d",
                    read_count
                );

                $display(
                    "GAP writes : %0d",
                    write_count
                );

            end

        end

        // =====================================
        // FINAL VERIFICATION RESULT
        // =====================================

        $display("");
        $display("========================================");
        $display("FINAL GAP VERIFICATION RESULT");
        $display("========================================");

        $display(
            "Images tested          : %0d",
            NUM_IMAGES
        );

        $display(
            "Total input reads      : %0d",
            total_read_count
        );

        $display(
            "Total GAP output writes: %0d",
            total_write_count
        );

        $display(
            "Expected input reads   : %0d",
            TOTAL_INPUTS
        );

        $display(
            "Expected GAP outputs   : %0d",
            TOTAL_OUTPUTS
        );

        $display(
            "GAP mismatches         : %0d",
            gap_mismatch_count
        );

        $display(
            "Duplicate addresses    : %0d",
            duplicate_count
        );

        $display(
            "Address errors         : %0d",
            address_error_count
        );

        $display(
            "Missing outputs        : %0d",
            missing_count
        );

        $display(
            "Failed images          : %0d",
            image_fail_count
        );

        // =====================================
        // PASS / FAIL
        // =====================================

        if (
            total_read_count == TOTAL_INPUTS &&
            total_write_count == TOTAL_OUTPUTS &&
            gap_mismatch_count == 0 &&
            duplicate_count == 0 &&
            address_error_count == 0 &&
            missing_count == 0 &&
            image_fail_count == 0 &&
            error == 1'b0
        ) begin

            $display("");
            $display("========================================");
            $display("GAP VERIFICATION PASS");
            $display("ZERO MISMATCH");
            $display("ALL 14 IMAGES VERIFIED");
            $display("24 GAP CHANNELS PER IMAGE");
            $display("========================================");

        end

        else begin

            $display("");
            $display("========================================");
            $display("GAP VERIFICATION FAIL");
            $display("PLEASE INSPECT ERROR COUNTERS");
            $display("========================================");

        end

        $finish;

    end

endmodule
