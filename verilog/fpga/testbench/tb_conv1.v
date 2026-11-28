`timescale 1ns/1ps

module tb_conv1;

    localparam NUM_IMAGES = 14;
    localparam INPUT_VALUES_PER_IMAGE = 3072;
    localparam OUTPUTS_PER_IMAGE = 8192;
    localparam TOTAL_INPUTS = 43008;
    localparam TOTAL_OUTPUTS = 114688;

    reg clk;
    reg rst_n;
    reg start;

    // Input image synchronous RAM
    wire input_rd_en;
    wire [11:0] input_rd_addr;
    reg [7:0] input_rd_data;

    // Weight synchronous ROM
    wire weight_rd_en;
    wire [7:0] weight_rd_addr;
    reg signed [7:0] weight_rd_data;

    // Parameter synchronous ROM
    wire param_rd_en;
    wire [2:0] param_rd_addr;

    reg signed [31:0] bias_rd_data;
    reg [31:0] multiplier_rd_data;
    reg signed [7:0] shift_rd_data;

    // Output feature map RAM interface
    wire output_wr_en;
    wire [12:0] output_wr_addr;
    wire [7:0] output_wr_data;

    // Status
    wire busy;
    wire done;
    wire error;
    wire saturated;

    // Golden memories
    reg [7:0] input_mem [0:TOTAL_INPUTS-1];
    reg [7:0] expected_mem [0:TOTAL_OUTPUTS-1];

    reg signed [7:0] weight_mem [0:215];
    reg signed [31:0] bias_mem [0:7];
    reg [31:0] multiplier_mem [0:7];
    reg signed [7:0] shift_mem [0:7];

    // Output address tracking
    reg seen [0:OUTPUTS_PER_IMAGE-1];

    integer image_index;
    integer input_index;
    integer expected_index;
    integer i;

    integer write_count;
    integer total_write_count;
    integer mismatch_count;
    integer duplicate_count;
    integer address_error_count;
    integer image_fail_count;
    integer missing_count;

    integer mismatch_before;
    integer duplicate_before;
    integer address_before;
    integer fail_this_image;

    integer image_cycle_count;

    // =====================================
    // CLOCK
    // =====================================

    always #5 clk = ~clk;

    // =====================================
    // DUT
    // =====================================

    conv1_engine dut (

        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .input_rd_en(input_rd_en),
        .input_rd_addr(input_rd_addr),
        .input_rd_data(input_rd_data),

        .weight_rd_en(weight_rd_en),
        .weight_rd_addr(weight_rd_addr),
        .weight_rd_data(weight_rd_data),

        .param_rd_en(param_rd_en),
        .param_rd_addr(param_rd_addr),

        .bias_rd_data(bias_rd_data),
        .multiplier_rd_data(multiplier_rd_data),
        .shift_rd_data(shift_rd_data),

        .output_wr_en(output_wr_en),
        .output_wr_addr(output_wr_addr),
        .output_wr_data(output_wr_data),

        .busy(busy),
        .done(done),
        .error(error),
        .saturated(saturated)

    );

    // =====================================
    // SYNCHRONOUS RAM / ROM MODEL
    // =====================================

    always @(posedge clk) begin

        if (!rst_n) begin

            input_rd_data <= 8'd0;
            weight_rd_data <= 8'sd0;

            bias_rd_data <= 32'sd0;
            multiplier_rd_data <= 32'd0;
            shift_rd_data <= 8'sd0;

        end

        else begin

            // Input image RAM
            if (input_rd_en) begin

                if (input_rd_addr < 12'd3072) begin

                    input_index =
                        image_index * INPUT_VALUES_PER_IMAGE
                        + input_rd_addr;

                    input_rd_data <= input_mem[input_index];

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

            // Weight ROM
            if (weight_rd_en) begin

                if (weight_rd_addr < 8'd216)
                    weight_rd_data <= weight_mem[weight_rd_addr];

                else begin

                    weight_rd_data <= 8'sd0;
                    address_error_count =
                        address_error_count + 1;

                    $display(
                        "ERROR: Invalid weight address %0d",
                        weight_rd_addr
                    );

                end

            end

            // Parameter ROM
            if (param_rd_en) begin

                bias_rd_data <= bias_mem[param_rd_addr];

                multiplier_rd_data <=
                    multiplier_mem[param_rd_addr];

                shift_rd_data <= shift_mem[param_rd_addr];

            end

            // =================================
            // GOLDEN OUTPUT COMPARATOR
            // =================================

            if (output_wr_en) begin

                expected_index =
                    image_index * OUTPUTS_PER_IMAGE
                    + output_wr_addr;

                if (
                    expected_index >= 0 &&
                    expected_index < TOTAL_OUTPUTS
                ) begin

                    // Compare actual RTL against Python
                    if (
                        output_wr_data !==
                        expected_mem[expected_index]
                    ) begin

                        mismatch_count = mismatch_count + 1;

                        if (mismatch_count <= 20) begin

                            $display(
                                "MISMATCH: Image=%0d Addr=%0d Expected=%02h Actual=%02h",
                                image_index + 1,
                                output_wr_addr,
                                expected_mem[expected_index],
                                output_wr_data
                            );

                        end

                    end

                    // Detect duplicate output addresses
                    if (seen[output_wr_addr] === 1'b1) begin

                        duplicate_count =
                            duplicate_count + 1;

                    end

                    else begin

                        seen[output_wr_addr] = 1'b1;

                    end

                    write_count = write_count + 1;
                    total_write_count = total_write_count + 1;

                end

                else begin

                    address_error_count =
                        address_error_count + 1;

                    $display(
                        "ERROR: Invalid output index %0d",
                        expected_index
                    );

                end

            end

        end

    end

    // =====================================
    // PER-IMAGE TIMEOUT
    // =====================================

    always @(posedge clk) begin

        if (!rst_n) begin

            image_cycle_count = 0;

        end

        else if (busy) begin

            image_cycle_count = image_cycle_count + 1;

            if (image_cycle_count > 750000) begin

                $display(
                    "FATAL: TIMEOUT on image %0d",
                    image_index + 1
                );

                $finish;

            end

        end

        else begin

            image_cycle_count = 0;

        end

    end

    // =====================================
    // GLOBAL TIMEOUT
    // =====================================

    initial begin

        #200000000;

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

        write_count = 0;
        total_write_count = 0;

        mismatch_count = 0;
        duplicate_count = 0;
        address_error_count = 0;

        image_fail_count = 0;
        missing_count = 0;

        image_cycle_count = 0;

        // Load golden vectors

        $readmemh(
            "vectors/conv1/conv1_input_images.mem",
            input_mem
        );

        $readmemh(
            "vectors/conv1/conv1_weights_int8.mem",
            weight_mem
        );

        $readmemh(
            "vectors/conv1/conv1_bias_int32.mem",
            bias_mem
        );

        $readmemh(
            "vectors/conv1/conv1_multiplier_q31.mem",
            multiplier_mem
        );

        $readmemh(
            "vectors/conv1/conv1_shift_s8.mem",
            shift_mem
        );

        $readmemh(
            "vectors/conv1/conv1_expected_outputs.mem",
            expected_mem
        );

        $display("----------------------------------------");
        $display("CONV1 RTL VERIFICATION");
        $display("----------------------------------------");

        $display("Input images       : %0d", NUM_IMAGES);
        $display("Input values       : %0d", TOTAL_INPUTS);
        $display("Weight values      : 216");
        $display("Expected outputs   : %0d", TOTAL_OUTPUTS);

        $display("Input[0]           : %02h", input_mem[0]);
        $display("Weight[0]          : %02h", weight_mem[0]);
        $display("Bias[0]            : %08h", bias_mem[0]);
        $display("Expected[0]        : %02h", expected_mem[0]);

        // Check memory loading

        if (
            (^input_mem[0]) === 1'bx ||
            (^input_mem[TOTAL_INPUTS-1]) === 1'bx ||
            (^weight_mem[0]) === 1'bx ||
            (^bias_mem[0]) === 1'bx ||
            (^multiplier_mem[0]) === 1'bx ||
            (^shift_mem[0]) === 1'bx ||
            (^expected_mem[0]) === 1'bx ||
            (^expected_mem[TOTAL_OUTPUTS-1]) === 1'bx
        ) begin

            $display("FATAL: GOLDEN MEMORY LOADING FAILED");

            $finish;

        end

        $display("Golden memory loading: PASS");

        // Reset

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

            write_count = 0;

            mismatch_before = mismatch_count;
            duplicate_before = duplicate_count;
            address_before = address_error_count;

            // Clear address tracking

            for (i = 0; i < OUTPUTS_PER_IMAGE; i = i + 1)
                seen[i] = 1'b0;

            $display("");
            $display("----------------------------------------");
            $display(
                "TEST IMAGE %0d / %0d",
                image_index + 1,
                NUM_IMAGES
            );
            $display("----------------------------------------");

            // Start one image

            @(negedge clk);
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            wait (busy === 1'b1);

            // Wait until Conv1 finishes

            wait (done === 1'b1);

            @(negedge clk);

            // Check missing output addresses

            missing_count = 0;

            for (i = 0; i < OUTPUTS_PER_IMAGE; i = i + 1) begin

                if (seen[i] !== 1'b1)
                    missing_count = missing_count + 1;

            end

            // =================================
            // IMAGE RESULT
            // =================================

            fail_this_image = 0;

            if (error !== 1'b0) begin

                $display("ERROR: Conv1 engine reported error");

                fail_this_image = 1;

            end

            if (saturated !== 1'b0) begin

                $display("ERROR: Unexpected saturation");

                fail_this_image = 1;

            end

            if (write_count != OUTPUTS_PER_IMAGE) begin

                $display(
                    "ERROR: Output count = %0d, expected = %0d",
                    write_count,
                    OUTPUTS_PER_IMAGE
                );

                fail_this_image = 1;

            end

            if ((mismatch_count - mismatch_before) != 0) begin

                $display(
                    "ERROR: Mismatches = %0d",
                    mismatch_count - mismatch_before
                );

                fail_this_image = 1;

            end

            if ((duplicate_count - duplicate_before) != 0) begin

                $display("ERROR: Duplicate output addresses");

                fail_this_image = 1;

            end

            if ((address_error_count - address_before) != 0) begin

                $display("ERROR: Invalid memory address detected");

                fail_this_image = 1;

            end

            if (missing_count != 0) begin

                $display(
                    "ERROR: Missing output addresses = %0d",
                    missing_count
                );

                fail_this_image = 1;

            end

            if (fail_this_image == 0) begin

                $display(
                    "IMAGE %0d: PASS",
                    image_index + 1
                );

                $display("Output writes: %0d", write_count);

            end

            else begin

                $display(
                    "IMAGE %0d: FAIL",
                    image_index + 1
                );

                image_fail_count = image_fail_count + 1;

            end

        end

        // =================================
        // FINAL RESULT
        // =================================

        $display("");
        $display("========================================");
        $display("FINAL CONV1 VERIFICATION RESULT");
        $display("========================================");

        $display("Images tested       : %0d", NUM_IMAGES);
        $display("Total output writes : %0d", total_write_count);
        $display("Expected outputs    : %0d", TOTAL_OUTPUTS);

        $display("Total mismatches    : %0d", mismatch_count);
        $display("Duplicate addresses : %0d", duplicate_count);
        $display("Address errors      : %0d", address_error_count);
        $display("Failed images       : %0d", image_fail_count);

        if (
            mismatch_count == 0 &&
            duplicate_count == 0 &&
            address_error_count == 0 &&
            image_fail_count == 0 &&
            total_write_count == TOTAL_OUTPUTS
        ) begin

            $display("");
            $display("========================================");
            $display("CONV1 VERIFICATION PASS");
            $display("ZERO MISMATCH");
            $display("========================================");

        end

        else begin

            $display("");
            $display("========================================");
            $display("CONV1 VERIFICATION FAIL");
            $display("========================================");

        end

        $finish;

    end

endmodule
