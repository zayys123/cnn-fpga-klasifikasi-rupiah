`timescale 1ns/1ps

module tb_fc_ptq_run1;

    localparam NUM_IMAGES = 14;
    localparam NUM_CLASSES = 7;
    localparam NUM_FEATURES = 24;

    localparam TOTAL_GAP_INPUTS = NUM_IMAGES * NUM_FEATURES;
    localparam TOTAL_WEIGHTS = NUM_CLASSES * NUM_FEATURES;
    localparam TOTAL_LOGITS = NUM_IMAGES * NUM_CLASSES;

    reg clk;
    reg rst_n;
    reg start;

    wire input_rd_en;
    wire [4:0] input_rd_addr;
    reg [13:0] input_rd_data;

    wire weight_rd_en;
    wire [7:0] weight_rd_addr;
    reg signed [7:0] weight_rd_data;

    wire bias_rd_en;
    wire [2:0] bias_rd_addr;
    reg signed [31:0] bias_rd_data;

    wire output_wr_en;
    wire [2:0] output_wr_addr;
    wire signed [31:0] output_wr_data;

    wire busy;
    wire done;
    wire error;

    // Golden memories
    reg [13:0] gap_mem [0:TOTAL_GAP_INPUTS-1];
    reg signed [7:0] weight_mem [0:TOTAL_WEIGHTS-1];
    reg signed [31:0] bias_mem [0:NUM_CLASSES-1];
    reg signed [31:0] expected_logits_mem [0:TOTAL_LOGITS-1];
    reg [2:0] expected_classes_mem [0:NUM_IMAGES-1];
    reg signed [31:0] actual_logits_mem [0:TOTAL_LOGITS-1];

    reg seen [0:NUM_CLASSES-1];

    integer image_index;
    integer input_index;
    integer weight_index;
    integer expected_index;
    integer i;
    integer c;
    integer predicted_class;
    integer max_logit;

    integer input_read_count;
    integer weight_read_count;
    integer bias_read_count;
    integer output_write_count;

    integer total_input_read_count;
    integer total_weight_read_count;
    integer total_bias_read_count;
    integer total_output_write_count;

    integer logit_mismatch_count;
    integer class_mismatch_count;
    integer duplicate_count;
    integer address_error_count;
    integer missing_count;
    integer image_fail_count;

    // Clock
    always #5 clk = ~clk;

    // DUT
    fc_engine dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .input_rd_en(input_rd_en),
        .input_rd_addr(input_rd_addr),
        .input_rd_data(input_rd_data),

        .weight_rd_en(weight_rd_en),
        .weight_rd_addr(weight_rd_addr),
        .weight_rd_data(weight_rd_data),

        .bias_rd_en(bias_rd_en),
        .bias_rd_addr(bias_rd_addr),
        .bias_rd_data(bias_rd_data),

        .output_wr_en(output_wr_en),
        .output_wr_addr(output_wr_addr),
        .output_wr_data(output_wr_data),

        .busy(busy),
        .done(done),
        .error(error)
    );

    // Synchronous GAP RAM, weight ROM, and bias ROM models.
    always @(posedge clk) begin
        if (!rst_n) begin
            input_rd_data  <= 14'd0;
            weight_rd_data <= 8'sd0;
            bias_rd_data   <= 32'sd0;
        end
        else begin
            if (input_rd_en) begin
                input_index = image_index * NUM_FEATURES + input_rd_addr;

                if ((input_rd_addr < NUM_FEATURES) &&
                    (input_index >= 0) &&
                    (input_index < TOTAL_GAP_INPUTS)) begin
                    input_rd_data <= gap_mem[input_index];
                    input_read_count = input_read_count + 1;
                    total_input_read_count = total_input_read_count + 1;
                end
                else begin
                    input_rd_data <= 14'd0;
                    address_error_count = address_error_count + 1;
                    $display("ERROR: Invalid GAP address image=%0d addr=%0d", image_index, input_rd_addr);
                end
            end

            if (weight_rd_en) begin
                weight_index = weight_rd_addr;

                if (weight_index < TOTAL_WEIGHTS) begin
                    weight_rd_data <= weight_mem[weight_index];
                    weight_read_count = weight_read_count + 1;
                    total_weight_read_count = total_weight_read_count + 1;
                end
                else begin
                    weight_rd_data <= 8'sd0;
                    address_error_count = address_error_count + 1;
                    $display("ERROR: Invalid FC weight address %0d", weight_rd_addr);
                end
            end

            if (bias_rd_en) begin
                if (bias_rd_addr < NUM_CLASSES) begin
                    bias_rd_data <= bias_mem[bias_rd_addr];
                    bias_read_count = bias_read_count + 1;
                    total_bias_read_count = total_bias_read_count + 1;
                end
                else begin
                    bias_rd_data <= 32'sd0;
                    address_error_count = address_error_count + 1;
                    $display("ERROR: Invalid FC bias address %0d", bias_rd_addr);
                end
            end

            if (output_wr_en) begin
                expected_index = image_index * NUM_CLASSES + output_wr_addr;

                if ((output_wr_addr < NUM_CLASSES) &&
                    (expected_index >= 0) &&
                    (expected_index < TOTAL_LOGITS)) begin

                    if (output_wr_data !== expected_logits_mem[expected_index]) begin
                        logit_mismatch_count = logit_mismatch_count + 1;
                        $display(
                            "LOGIT MISMATCH: Image=%0d Class=%0d Expected=%08h Actual=%08h",
                            image_index + 1,
                            output_wr_addr,
                            expected_logits_mem[expected_index],
                            output_wr_data
                        );
                    end

                    actual_logits_mem[expected_index] = output_wr_data;

                    if (seen[output_wr_addr] === 1'b1) begin
                        duplicate_count = duplicate_count + 1;
                        $display("ERROR: Duplicate output class address %0d", output_wr_addr);
                    end
                    else begin
                        seen[output_wr_addr] = 1'b1;
                    end

                    output_write_count = output_write_count + 1;
                    total_output_write_count = total_output_write_count + 1;
                end
                else begin
                    address_error_count = address_error_count + 1;
                    $display("ERROR: Invalid FC output address %0d", output_wr_addr);
                end
            end
        end
    end

    // Main test
    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        image_index = 0;

        input_read_count = 0;
        weight_read_count = 0;
        bias_read_count = 0;
        output_write_count = 0;

        total_input_read_count = 0;
        total_weight_read_count = 0;
        total_bias_read_count = 0;
        total_output_write_count = 0;

        logit_mismatch_count = 0;
        class_mismatch_count = 0;
        duplicate_count = 0;
        address_error_count = 0;
        missing_count = 0;
        image_fail_count = 0;

        $readmemh("../../../artifacts/ptq_int8_32x32_20261127_run1/gap_golden_run1/gap_expected_sums_u14.mem", gap_mem);
        $readmemh("../../../artifacts/ptq_int8_32x32_20261127_run1/fc_golden_run1/fc_weights_int8.mem", weight_mem);
        $readmemh("../../../artifacts/ptq_int8_32x32_20261127_run1/fc_golden_run1/fc_bias_int32.mem", bias_mem);
        $readmemh("../../../artifacts/ptq_int8_32x32_20261127_run1/fc_golden_run1/fc_expected_logits_int32.mem", expected_logits_mem);
        $readmemh("../../../artifacts/ptq_int8_32x32_20261127_run1/fc_golden_run1/fc_expected_classes_u3.mem", expected_classes_mem);

        $display("========================================");
        $display("FC PTQ RUN1 RTL VERIFICATION");
        $display("========================================");
        $display("Images               : %0d", NUM_IMAGES);
        $display("GAP inputs/image     : %0d", NUM_FEATURES);
        $display("Classes              : %0d", NUM_CLASSES);
        $display("Weights              : %0d", TOTAL_WEIGHTS);
        $display("Expected logits       : %0d", TOTAL_LOGITS);
        $display("Golden memory loading: PASS");

        // Release reset on a falling edge.
        @(negedge clk);
        rst_n = 1'b1;

        for (image_index = 0; image_index < NUM_IMAGES; image_index = image_index + 1) begin
            input_read_count = 0;
            weight_read_count = 0;
            bias_read_count = 0;
            output_write_count = 0;

            for (i = 0; i < NUM_CLASSES; i = i + 1)
                seen[i] = 1'b0;

            $display("\n----------------------------------------");
            $display("TEST IMAGE %0d / %0d", image_index + 1, NUM_IMAGES);
            $display("----------------------------------------");

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            wait(done || error);
            #1;

            if (error) begin
                $display("FATAL: FC engine asserted error on image %0d", image_index + 1);
                image_fail_count = image_fail_count + 1;
                $finish;
            end

            if (input_read_count != 168) begin
                $display("ERROR: Image %0d GAP reads=%0d expected=168", image_index + 1, input_read_count);
                image_fail_count = image_fail_count + 1;
            end

            if (weight_read_count != 168) begin
                $display("ERROR: Image %0d weight reads=%0d expected=168", image_index + 1, weight_read_count);
                image_fail_count = image_fail_count + 1;
            end

            if (bias_read_count != 7) begin
                $display("ERROR: Image %0d bias reads=%0d expected=7", image_index + 1, bias_read_count);
                image_fail_count = image_fail_count + 1;
            end

            if (output_write_count != 7) begin
                $display("ERROR: Image %0d output writes=%0d expected=7", image_index + 1, output_write_count);
                image_fail_count = image_fail_count + 1;
            end

            for (i = 0; i < NUM_CLASSES; i = i + 1) begin
                if (seen[i] !== 1'b1) begin
                    missing_count = missing_count + 1;
                    image_fail_count = image_fail_count + 1;
                    $display("ERROR: Image %0d missing class output %0d", image_index + 1, i);
                end
            end

            // Determine predicted class from the seven signed INT32 logits.
            max_logit = actual_logits_mem[image_index * NUM_CLASSES];
            predicted_class = 0;

            for (c = 1; c < NUM_CLASSES; c = c + 1) begin
                if (actual_logits_mem[image_index * NUM_CLASSES + c] > max_logit) begin
                    max_logit = actual_logits_mem[image_index * NUM_CLASSES + c];
                    predicted_class = c;
                end
            end

            if (predicted_class != expected_classes_mem[image_index]) begin
                class_mismatch_count = class_mismatch_count + 1;
                $display(
                    "CLASS MISMATCH: Image=%0d Expected=%0d Actual=%0d",
                    image_index + 1,
                    expected_classes_mem[image_index],
                    predicted_class
                );
            end

            $display("IMAGE %0d: %s", image_index + 1,
                ((input_read_count == 168) &&
                 (weight_read_count == 168) &&
                 (bias_read_count == 7) &&
                 (output_write_count == 7)) ? "READ/WRITE COUNTS PASS" : "COUNT CHECK FAILED");
            $display("GAP reads=%0d, Weight reads=%0d, Bias reads=%0d, Logit writes=%0d, Predicted class=%0d",
                input_read_count, weight_read_count, bias_read_count, output_write_count, predicted_class);
        end

        $display("\n========================================");
        $display("FINAL FC VERIFICATION RESULT");
        $display("========================================");
        $display("Images tested          : %0d", NUM_IMAGES);
        $display("Total GAP reads        : %0d", total_input_read_count);
        $display("Total weight reads     : %0d", total_weight_read_count);
        $display("Total bias reads       : %0d", total_bias_read_count);
        $display("Total logit writes     : %0d", total_output_write_count);
        $display("Expected GAP reads     : %0d", NUM_IMAGES * 168);
        $display("Expected weight reads  : %0d", NUM_IMAGES * 168);
        $display("Expected bias reads    : %0d", NUM_IMAGES * 7);
        $display("Expected logit writes  : %0d", TOTAL_LOGITS);
        $display("Logit mismatches       : %0d", logit_mismatch_count);
        $display("Class mismatches       : %0d", class_mismatch_count);
        $display("Duplicate addresses    : %0d", duplicate_count);
        $display("Address errors         : %0d", address_error_count);
        $display("Missing outputs        : %0d", missing_count);
        $display("Failed images          : %0d", image_fail_count);

        if ((total_input_read_count == NUM_IMAGES * 168) &&
            (total_weight_read_count == NUM_IMAGES * 168) &&
            (total_bias_read_count == NUM_IMAGES * 7) &&
            (total_output_write_count == TOTAL_LOGITS) &&
            (logit_mismatch_count == 0) &&
            (class_mismatch_count == 0) &&
            (duplicate_count == 0) &&
            (address_error_count == 0) &&
            (missing_count == 0) &&
            (image_fail_count == 0)) begin
            $display("========================================");
            $display("FC VERIFICATION PASS");
            $display("ZERO LOGIT MISMATCH");
            $display("ALL 14 IMAGES VERIFIED");
            $display("ALL 98 LOGITS EXACT MATCH");
            $display("========================================");
        end
        else begin
            $display("========================================");
            $display("FC VERIFICATION FAIL");
            $display("========================================");
        end

        $finish;
    end

    // Global timeout guard.
    initial begin
        #100000000;
        $display("FATAL: GLOBAL FC SIMULATION TIMEOUT");
        $finish;
    end

endmodule
