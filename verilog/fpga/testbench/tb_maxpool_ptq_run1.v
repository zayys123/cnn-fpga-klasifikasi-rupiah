`timescale 1ns/1ps

module tb_maxpool_ptq_run1;

    reg [7:0] pixel00;
    reg [7:0] pixel01;
    reg [7:0] pixel10;
    reg [7:0] pixel11;

    wire [7:0] pooled_value;

    reg [47:0] vectors [0:43007];
    reg [47:0] current_vector;

    reg [7:0] expected_value;
    reg [7:0] layer_id;

    integer i;
    integer errors;
    integer total_checked;
    integer pool1_count;
    integer pool2_count;
    integer invalid_count;

    maxpool2x2_uint8 dut (
        .pixel00(pixel00),
        .pixel01(pixel01),
        .pixel10(pixel10),
        .pixel11(pixel11),
        .pooled_value(pooled_value)
    );

    initial begin

        errors = 0;
        total_checked = 0;
        pool1_count = 0;
        pool2_count = 0;
        invalid_count = 0;

        pixel00 = 0;
        pixel01 = 0;
        pixel10 = 0;
        pixel11 = 0;

        $display("-----------------------------------------");
        $display("LOADING ACTUAL CNN MAXPOOL VECTORS");
        $display("-----------------------------------------");

        $readmemh(
            "../../../artifacts/ptq_int8_32x32_20261127_run1/rtl_vectors/maxpool_actual_vectors.mem",
            vectors
        );

        for (i = 0; i < 43008; i = i + 1) begin

            current_vector = vectors[i];

            pixel00 = current_vector[47:40];
            pixel01 = current_vector[39:32];
            pixel10 = current_vector[31:24];
            pixel11 = current_vector[23:16];

            expected_value = current_vector[15:8];
            layer_id = current_vector[7:0];

            #1;

            total_checked = total_checked + 1;

            if (layer_id == 8'd1)
                pool1_count = pool1_count + 1;

            else if (layer_id == 8'd2)
                pool2_count = pool2_count + 1;

            else
                invalid_count = invalid_count + 1;

            if (pooled_value !== expected_value) begin

                errors = errors + 1;

                if (errors <= 20) begin

                    $display(
                        "MISMATCH vector=%0d layer=%0d",
                        i, layer_id
                    );

                    $display(
                        "INPUT=%0d,%0d,%0d,%0d",
                        pixel00, pixel01, pixel10, pixel11
                    );

                    $display(
                        "RTL=%0d EXPECTED=%0d",
                        pooled_value, expected_value
                    );

                end

            end

            if ((i + 1) % 10000 == 0)
                $display("Processed %0d vectors", i + 1);

        end

        $display("-----------------------------------------");
        $display("ACTUAL MAXPOOL VERIFICATION SUMMARY");
        $display("-----------------------------------------");

        $display("Total vectors : %0d", total_checked);
        $display("Pool1 vectors : %0d", pool1_count);
        $display("Pool2 vectors : %0d", pool2_count);
        $display("Invalid IDs   : %0d", invalid_count);
        $display("Total errors  : %0d", errors);

        $display("-----------------------------------------");

        if (
            total_checked == 43008 &&
            pool1_count == 28672 &&
            pool2_count == 14336 &&
            invalid_count == 0 &&
            errors == 0
        ) begin

            $display("ALL ACTUAL MAXPOOL TESTS PASSED");

        end

        else begin

            $fatal(1, "ACTUAL MAXPOOL VERIFICATION FAILED");

        end

        $display("-----------------------------------------");

        $finish;

    end

endmodule
