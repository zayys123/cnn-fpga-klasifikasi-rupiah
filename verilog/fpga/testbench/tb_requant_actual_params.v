`timescale 1ns/1ps

module tb_requant_actual_params;

    parameter NUM_VECTORS = 193536;

    reg signed [31:0] accumulator;
    reg        [31:0] multiplier_q31;
    reg signed [7:0]  shift;

    wire [7:0] activation_out;
    wire saturated;
    wire invalid_config;

    reg [95:0] test_vectors [0:NUM_VECTORS-1];

    reg [7:0] expected_activation;
    reg expected_saturated;
    reg expected_invalid;

    reg [1:0] layer_id;

    integer i;
    integer errors;

    integer count_conv1;
    integer count_conv2;
    integer count_conv3;

    integer fd;

    requant_relu_uint8 dut (
        .accumulator(accumulator),
        .multiplier_q31(multiplier_q31),
        .shift(shift),
        .activation_out(activation_out),
        .saturated(saturated),
        .invalid_config(invalid_config)
    );

    initial begin

        accumulator = 0;
        multiplier_q31 = 0;
        shift = 0;

        expected_activation = 0;
        expected_saturated = 0;
        expected_invalid = 0;

        errors = 0;

        count_conv1 = 0;
        count_conv2 = 0;
        count_conv3 = 0;

        // Check vector file
        fd = $fopen("vectors/requant_actual_vectors.mem", "r");

        if (fd == 0)
            $fatal(1, "Cannot open actual vector file.");

        $fclose(fd);

        $display("-----------------------------------------");
        $display("LOADING ACTUAL CNN Q31 VECTORS");
        $display("-----------------------------------------");

        $readmemh(
            "vectors/requant_actual_vectors.mem",
            test_vectors
        );

        // Process all vectors
        for (i = 0; i < NUM_VECTORS; i = i + 1) begin

            accumulator = test_vectors[i][95:64];

            multiplier_q31 = test_vectors[i][63:32];

            shift = test_vectors[i][31:24];

            expected_activation = test_vectors[i][23:16];

            expected_saturated = test_vectors[i][15];

            expected_invalid = test_vectors[i][14];

            layer_id = test_vectors[i][13:12];

            // Allow combinational logic to settle
            #1;

            // Count layer vectors
            case (layer_id)

                2'd0: count_conv1 = count_conv1 + 1;

                2'd1: count_conv2 = count_conv2 + 1;

                2'd2: count_conv3 = count_conv3 + 1;

                default: begin
                    errors = errors + 1;
                    $display("INVALID LAYER ID at vector %0d", i);
                end

            endcase

            // Compare actual RTL with Python reference
            if (
                activation_out !== expected_activation ||
                saturated !== expected_saturated ||
                invalid_config !== expected_invalid
            ) begin

                errors = errors + 1;

                // Limit error messages
                if (errors <= 20) begin

                    $display("--------------------------------");

                    $display("MISMATCH AT VECTOR %0d", i);

                    $display("LAYER ID: %0d", layer_id);

                    $display(
                        "ACC=%0d MULT=%08h SHIFT=%0d",
                        accumulator,
                        multiplier_q31,
                        shift
                    );

                    $display(
                        "RTL OUT=%0d SAT=%b INVALID=%b",
                        activation_out,
                        saturated,
                        invalid_config
                    );

                    $display(
                        "EXP OUT=%0d SAT=%b INVALID=%b",
                        expected_activation,
                        expected_saturated,
                        expected_invalid
                    );

                end

            end

            // Progress indicator
            if ((i + 1) % 50000 == 0)
                $display("Processed %0d vectors", i + 1);

        end

        $display("-----------------------------------------");
        $display("ACTUAL Q31 VERIFICATION SUMMARY");
        $display("-----------------------------------------");

        $display("Total vectors : %0d", NUM_VECTORS);

        $display("Conv1 vectors : %0d", count_conv1);

        $display("Conv2 vectors : %0d", count_conv2);

        $display("Conv3 vectors : %0d", count_conv3);

        $display("Total errors  : %0d", errors);

        if (
            count_conv1 != 114688 ||
            count_conv2 != 57344 ||
            count_conv3 != 21504
        )
            errors = errors + 1;

        if (errors == 0) begin

            $display("-----------------------------------------");
            $display("ALL ACTUAL Q31 TESTS PASSED");
            $display("-----------------------------------------");

        end

        else begin

            $display("-----------------------------------------");
            $display("ACTUAL Q31 VERIFICATION FAILED");
            $display("-----------------------------------------");

            $fatal(1, "RTL DOES NOT MATCH PYTHON REFERENCE.");

        end

        $finish;

    end

endmodule
