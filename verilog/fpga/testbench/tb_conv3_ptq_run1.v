`timescale 1ns/1ps

module tb_conv3_ptq_run1;

    localparam NUM_IMAGES = 14;

    localparam INPUT_VALUES_PER_IMAGE = 1024;
    localparam OUTPUTS_PER_IMAGE = 1536;

    localparam TOTAL_INPUTS = 14336;
    localparam TOTAL_OUTPUTS = 21504;

    localparam WEIGHT_COUNT = 3456;
    localparam NUM_CHANNELS = 24;

    reg clk;
    reg rst_n;
    reg start;

    // INPUT FEATURE MAP RAM
    wire input_rd_en;
    wire [9:0] input_rd_addr;
    reg [7:0] input_rd_data;

    // WEIGHT ROM
    wire weight_rd_en;
    wire [11:0] weight_rd_addr;
    reg signed [7:0] weight_rd_data;

    // PARAMETER ROM
    wire param_rd_en;
    wire [4:0] param_rd_addr;

    reg signed [31:0] bias_rd_data;
    reg [31:0] multiplier_rd_data;
    reg signed [7:0] shift_rd_data;

    // OUTPUT FEATURE MAP
    wire output_wr_en;
    wire [10:0] output_wr_addr;
    wire [7:0] output_wr_data;

    // STATUS
    wire busy;
    wire done;
    wire error;
    wire saturated;

    // GOLDEN MEMORIES
    reg [7:0] input_mem [0:TOTAL_INPUTS-1];

    reg [7:0] expected_mem [0:TOTAL_OUTPUTS-1];

    reg [31:0] expected_acc_mem [0:TOTAL_OUTPUTS-1];

    reg signed [7:0] weight_mem [0:WEIGHT_COUNT-1];

    reg signed [31:0] bias_mem [0:NUM_CHANNELS-1];

    reg [31:0] multiplier_mem [0:NUM_CHANNELS-1];

    reg signed [7:0] shift_mem [0:NUM_CHANNELS-1];

    // ADDRESS TRACKING
    reg seen [0:OUTPUTS_PER_IMAGE-1];

    integer image_index;
    integer input_index;
    integer expected_index;

    integer i;

    integer write_count;
    integer total_write_count;

    integer activation_mismatch_count;
    integer accumulator_mismatch_count;

    integer duplicate_count;
    integer address_error_count;

    integer image_fail_count;
    integer missing_count;

    integer activation_before;
    integer accumulator_before;
    integer duplicate_before;
    integer address_before;

    integer fail_this_image;

    integer image_cycle_count;

    integer shift_fd;
    integer shift_value;
    integer scan_count;

    integer total_error_messages;

    integer saturation_detected_count;

    // =====================================
    // CLOCK
    // =====================================

    always #5 clk = ~clk;

    // =====================================
    // DUT
    // =====================================

    conv3_engine dut (

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

            // INPUT FEATURE MAP RAM
            // Conv3 input map: 16 channels x 8 x 8 = 1024 values/image.
            // The 10-bit address bus covers exactly 0..1023.

            if (input_rd_en) begin

                input_index =
                    image_index * INPUT_VALUES_PER_IMAGE
                    + input_rd_addr;

                if (
                    input_index >= 0 &&
                    input_index < TOTAL_INPUTS
                )
                    input_rd_data <= input_mem[input_index];

                else begin

                    input_rd_data <= 8'd0;

                    address_error_count =
                        address_error_count + 1;

                    $display(
                        "ERROR: Invalid input index %0d (image=%0d addr=%0d)",
                        input_index,
                        image_index,
                        input_rd_addr
                    );

                end

            end

            // WEIGHT ROM

            if (weight_rd_en) begin

                if (weight_rd_addr < 12'd3456)

                    weight_rd_data <=
                        weight_mem[weight_rd_addr];

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

            // PARAMETER ROM

            if (param_rd_en) begin

                if (param_rd_addr < NUM_CHANNELS) begin

                    bias_rd_data <=
                        bias_mem[param_rd_addr];

                    multiplier_rd_data <=
                        multiplier_mem[param_rd_addr];

                    shift_rd_data <=
                        shift_mem[param_rd_addr];

                end

                else begin

                    bias_rd_data <= 32'sd0;
                    multiplier_rd_data <= 32'd0;
                    shift_rd_data <= 8'sd0;

                    address_error_count =
                        address_error_count + 1;

                    $display(
                        "ERROR: Invalid parameter address %0d",
                        param_rd_addr
                    );

                end

            end

            // =================================
            // GOLDEN OUTPUT COMPARATOR
            // =================================

            if (output_wr_en) begin

                expected_index =
                    image_index * OUTPUTS_PER_IMAGE
                    + output_wr_addr;

                if (
                    output_wr_addr < OUTPUTS_PER_IMAGE &&
                    expected_index >= 0 &&
                    expected_index < TOTAL_OUTPUTS
                ) begin

                    // Compare INT8 activation

                    if (
                        output_wr_data !==
                        expected_mem[expected_index]
                    ) begin

                        activation_mismatch_count =
                            activation_mismatch_count + 1;

                        if (total_error_messages < 20) begin

                            $display(
                                "ACTIVATION MISMATCH: Image=%0d Addr=%0d Expected=%02h Actual=%02h",
                                image_index + 1,
                                output_wr_addr,
                                expected_mem[expected_index],
                                output_wr_data
                            );

                            total_error_messages =
                                total_error_messages + 1;

                        end

                    end

                    // Compare raw INT32 accumulator
                    // Hierarchical access to MAC output

                    if (
                        dut.u_pixel_engine.accumulator !==
                        expected_acc_mem[expected_index]
                    ) begin

                        accumulator_mismatch_count =
                            accumulator_mismatch_count + 1;

                        if (total_error_messages < 20) begin

                            $display(
                                "ACCUMULATOR MISMATCH: Image=%0d Addr=%0d Expected=%08h Actual=%08h",
                                image_index + 1,
                                output_wr_addr,
                                expected_acc_mem[expected_index],
                                dut.u_pixel_engine.accumulator
                            );

                            total_error_messages =
                                total_error_messages + 1;

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

            image_cycle_count =
                image_cycle_count + 1;

            if (image_cycle_count > 1000000) begin

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

        #500000000;

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

        activation_mismatch_count = 0;
        accumulator_mismatch_count = 0;

        duplicate_count = 0;
        address_error_count = 0;

        image_fail_count = 0;
        missing_count = 0;

        image_cycle_count = 0;

        total_error_messages = 0;

        saturation_detected_count = 0;

        // =================================
        // LOAD INPUT GOLDEN VECTORS
        // =================================

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/conv3_golden_run1/conv3_input_features_u8.mem",
            input_mem
        );

        // =================================
        // LOAD EXPECTED INT8 OUTPUTS
        // =================================

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/conv3_golden_run1/conv3_expected_outputs_u8.mem",
            expected_mem
        );

        // =================================
        // LOAD EXPECTED INT32 ACCUMULATORS
        // =================================

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/conv3_golden_run1/conv3_expected_acc_int32.mem",
            expected_acc_mem
        );

        // =================================
        // LOAD WEIGHTS
        // =================================

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/weights_mem/conv3_weights_int8.mem",
            weight_mem
        );

        // =================================
        // LOAD BIASES
        // =================================

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/weights_mem/conv3_bias_int32.mem",
            bias_mem
        );

        // =================================
        // LOAD Q31 MULTIPLIERS
        // =================================

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/weights_mem/conv3_requant_multiplier_q31.mem",
            multiplier_mem
        );

        // =================================
        // LOAD SIGNED DECIMAL SHIFTS
        // =================================

        shift_fd = $fopen(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/weights_mem/conv3_requant_shift.txt",
            "r"
        );

        if (shift_fd == 0) begin

            $display("FATAL: Cannot open Conv3 shift file.");

            $finish;

        end

        for (i = 0; i < NUM_CHANNELS; i = i + 1) begin

            scan_count = $fscanf(
                shift_fd,
                "%d",
                shift_value
            );

            if (scan_count != 1) begin

                $display(
                    "FATAL: Cannot read shift channel %0d",
                    i
                );

                $finish;

            end

            if (
                shift_value < -128 ||
                shift_value > 127
            ) begin

                $display(
                    "FATAL: Invalid signed shift at channel %0d",
                    i
                );

                $finish;

            end

            shift_mem[i] = shift_value;

        end

        $fclose(shift_fd);

        // =================================
        // VERIFY MEMORY LOADING
        // =================================

        $display("");
        $display("========================================");
        $display("CONV3 PTQ RUN1 RTL VERIFICATION");
        $display("========================================");

        $display("Images              : %0d", NUM_IMAGES);

        $display("Input values        : %0d", TOTAL_INPUTS);

        $display("Output values       : %0d", TOTAL_OUTPUTS);

        $display("Weight values       : %0d", WEIGHT_COUNT);

        $display("Output channels     : %0d", NUM_CHANNELS);

        $display("Expected accumulators: %0d", TOTAL_OUTPUTS);

        $display("Input[0]            : %02h", input_mem[0]);

        $display("Weight[0]           : %02h", weight_mem[0]);

        $display("Bias[0]             : %08h", bias_mem[0]);

        $display("Multiplier[0]       : %08h", multiplier_mem[0]);

        $display("Shift[0]            : %0d", shift_mem[0]);

        $display("Expected output[0]  : %02h", expected_mem[0]);

        $display("Expected acc[0]     : %08h", expected_acc_mem[0]);

        if (

            (^input_mem[0]) === 1'bx ||

            (^input_mem[TOTAL_INPUTS-1]) === 1'bx ||

            (^weight_mem[0]) === 1'bx ||

            (^weight_mem[WEIGHT_COUNT-1]) === 1'bx ||

            (^bias_mem[0]) === 1'bx ||

            (^multiplier_mem[0]) === 1'bx ||

            (^shift_mem[0]) === 1'bx ||

            (^expected_mem[0]) === 1'bx ||

            (^expected_mem[TOTAL_OUTPUTS-1]) === 1'bx ||

            (^expected_acc_mem[0]) === 1'bx ||

            (^expected_acc_mem[TOTAL_OUTPUTS-1]) === 1'bx

        ) begin

            $display("FATAL: GOLDEN MEMORY LOADING FAILED");

            $finish;

        end

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

            write_count = 0;

            activation_before =
                activation_mismatch_count;

            accumulator_before =
                accumulator_mismatch_count;

            duplicate_before =
                duplicate_count;

            address_before =
                address_error_count;

            // CLEAR ADDRESS TRACKING

            for (
                i = 0;
                i < OUTPUTS_PER_IMAGE;
                i = i + 1
            )

                seen[i] = 1'b0;

            $display("");

            $display("----------------------------------------");

            $display(
                "TEST IMAGE %0d / %0d",
                image_index + 1,
                NUM_IMAGES
            );

            $display("----------------------------------------");

            // START ENGINE

            @(negedge clk);

            start = 1'b1;

            @(negedge clk);

            start = 1'b0;

            wait (busy === 1'b1);

            // WAIT UNTIL CONV3 FINISHES

            wait (done === 1'b1);

            @(negedge clk);

            // CHECK MISSING ADDRESSES

            missing_count = 0;

            for (
                i = 0;
                i < OUTPUTS_PER_IMAGE;
                i = i + 1
            ) begin

                if (seen[i] !== 1'b1)

                    missing_count = missing_count + 1;

            end

            // =================================
            // IMAGE RESULT
            // =================================

            fail_this_image = 0;

            if (saturated !== 1'b0) begin

                saturation_detected_count =
                    saturation_detected_count + 1;

                $display(
                    "ERROR: Saturation detected in image %0d",
                    image_index + 1
                );

                fail_this_image = 1;

            end

            if (error !== 1'b0) begin

                $display("ERROR: Conv3 engine reported error");

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

            if (
                activation_mismatch_count -
                activation_before != 0
            ) begin

                $display(
                    "ERROR: Activation mismatches = %0d",
                    activation_mismatch_count -
                    activation_before
                );

                fail_this_image = 1;

            end

            if (
                accumulator_mismatch_count -
                accumulator_before != 0
            ) begin

                $display(
                    "ERROR: Accumulator mismatches = %0d",
                    accumulator_mismatch_count -
                    accumulator_before
                );

                fail_this_image = 1;

            end

            if (
                duplicate_count -
                duplicate_before != 0
            ) begin

                $display("ERROR: Duplicate output addresses");

                fail_this_image = 1;

            end

            if (
                address_error_count -
                address_before != 0
            ) begin

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

                $display(
                    "Output writes: %0d",
                    write_count
                );

            end

            else begin

                $display(
                    "IMAGE %0d: FAIL",
                    image_index + 1
                );

                image_fail_count =
                    image_fail_count + 1;

            end

        end

        // =================================
        // FINAL RESULT
        // =================================

        $display("");

        $display("========================================");

        $display("FINAL CONV3 VERIFICATION RESULT");

        $display("========================================");

        $display("Images tested          : %0d", NUM_IMAGES);

        $display("Total output writes    : %0d", total_write_count);

        $display("Expected outputs       : %0d", TOTAL_OUTPUTS);

        $display(
            "Activation mismatches : %0d",
            activation_mismatch_count
        );

        $display(
            "Accumulator mismatches: %0d",
            accumulator_mismatch_count
        );

        $display("Duplicate addresses    : %0d", duplicate_count);

        $display("Address errors         : %0d", address_error_count);

        $display("Failed images          : %0d", image_fail_count);

        $display("Images with saturation : %0d", saturation_detected_count);

        if (

            activation_mismatch_count == 0 &&

            accumulator_mismatch_count == 0 &&

            duplicate_count == 0 &&

            address_error_count == 0 &&

            image_fail_count == 0 &&

            saturation_detected_count == 0 &&

            total_write_count == TOTAL_OUTPUTS

        ) begin

            $display("");

            $display("========================================");

            $display("CONV3 VERIFICATION PASS");

            $display("ZERO MISMATCH");

            $display("INT32 ACCUMULATORS EXACT MATCH");

            $display("INT8 OUTPUTS EXACT MATCH");

            $display("========================================");

        end

        else begin

            $display("");

            $display("========================================");

            $display("CONV3 VERIFICATION FAIL");

            $display("========================================");

        end

        $finish;

    end

endmodule
