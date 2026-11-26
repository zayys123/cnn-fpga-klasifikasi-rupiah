`timescale 1ns/1ps

module tb_maxpool2x2_uint8;

    reg [7:0] pixel00;
    reg [7:0] pixel01;
    reg [7:0] pixel10;
    reg [7:0] pixel11;

    wire [7:0] pooled_value;

    integer errors;
    integer passed;

    maxpool2x2_uint8 dut (

        .pixel00(pixel00),
        .pixel01(pixel01),
        .pixel10(pixel10),
        .pixel11(pixel11),

        .pooled_value(pooled_value)

    );


    task check_case;

        input integer case_id;

        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;

        input [7:0] expected;

        begin

            pixel00 = a;
            pixel01 = b;
            pixel10 = c;
            pixel11 = d;

            #1;

            if (pooled_value !== expected) begin

                errors = errors + 1;

                $display(
                    "TEST %0d FAILED: OUT=%0d EXPECTED=%0d",
                    case_id,
                    pooled_value,
                    expected
                );

            end

            else begin

                passed = passed + 1;

                $display("TEST %0d PASSED", case_id);

            end

        end

    endtask


    initial begin

        errors = 0;
        passed = 0;

        pixel00 = 0;
        pixel01 = 0;
        pixel10 = 0;
        pixel11 = 0;

        #2;

        // TEST 1: All zeros
        check_case(
            1, 0, 0, 0, 0, 0
        );

        // TEST 2: Increasing values
        check_case(
            2, 1, 2, 3, 4, 4
        );

        // TEST 3: Maximum at pixel00
        check_case(
            3, 255, 10, 20, 30, 255
        );

        // TEST 4: Maximum at pixel01
        check_case(
            4, 10, 255, 20, 30, 255
        );

        // TEST 5: Maximum at pixel10
        check_case(
            5, 10, 20, 255, 30, 255
        );

        // TEST 6: Maximum at pixel11
        check_case(
            6, 10, 20, 30, 255, 255
        );

        // TEST 7: All values identical
        check_case(
            7, 77, 77, 77, 77, 77
        );

        // TEST 8: Unsigned comparison
        check_case(
            8, 128, 200, 127, 199, 200
        );

        // TEST 9: High UINT8 values
        check_case(
            9, 254, 253, 252, 251, 254
        );

        // TEST 10: Normal pooling
        check_case(
            10, 10, 20, 30, 40, 40
        );

        // TEST 11: Single nonzero value
        check_case(
            11, 0, 1, 0, 0, 1
        );

        // TEST 12: Duplicate maximum
        check_case(
            12, 10, 250, 250, 1, 250
        );


        $display("-----------------------------------------");

        $display("MAXPOOL 2x2 UINT8 SUMMARY");

        $display("Total tests : 12");
        $display("Passed      : %0d", passed);
        $display("Errors      : %0d", errors);

        if (errors == 0) begin

            $display("-----------------------------------------");
            $display("ALL MAXPOOL UINT8 TESTS PASSED");
            $display("-----------------------------------------");

        end

        else begin

            $fatal(1, "MAXPOOL VERIFICATION FAILED");

        end

        $finish;

    end

endmodule
