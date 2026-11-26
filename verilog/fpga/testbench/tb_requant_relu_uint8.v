`timescale 1ns/1ps

module tb_requant_relu_uint8;

    reg signed [31:0] accumulator;
    reg        [31:0] multiplier_q31;
    reg signed [7:0]  shift;

    wire [7:0] activation_out;
    wire saturated;
    wire invalid_config;


    requant_relu_uint8 dut (

        .accumulator(accumulator),
        .multiplier_q31(multiplier_q31),
        .shift(shift),

        .activation_out(activation_out),
        .saturated(saturated),
        .invalid_config(invalid_config)

    );


    task check_case;

        input integer case_id;

        input signed [31:0] acc_value;
        input        [31:0] mult_value;
        input signed [7:0]  shift_value;

        input [7:0] expected_out;
        input expected_saturated;
        input expected_invalid;

        begin

            accumulator = acc_value;
            multiplier_q31 = mult_value;
            shift = shift_value;

            #1;

            if (
                activation_out !== expected_out ||
                saturated !== expected_saturated ||
                invalid_config !== expected_invalid
            ) begin

                $display("TEST %0d FAILED", case_id);

                $display(
                    "ACC=%0d MULT=%h SHIFT=%0d",
                    accumulator,
                    multiplier_q31,
                    shift
                );

                $display(
                    "OUTPUT=%0d SAT=%b INVALID=%b",
                    activation_out,
                    saturated,
                    invalid_config
                );

                $display(
                    "EXPECTED=%0d SAT=%b INVALID=%b",
                    expected_out,
                    expected_saturated,
                    expected_invalid
                );

                $fatal(1, "REQUANTIZATION TEST FAILED");

            end

            else begin

                $display("TEST %0d PASSED", case_id);

            end

        end

    endtask


    initial begin

        accumulator = 0;
        multiplier_q31 = 0;
        shift = 0;

        #2;


        // TEST 1: Normal multiplication
        // 100 * 0.5 = 50

        check_case(
            1, 100, 32'h40000000, 0,
            50, 0, 0
        );


        // TEST 2: Negative accumulator -> ReLU = 0

        check_case(
            2, -123, 32'h40000000, 0,
            0, 0, 0
        );


        // TEST 3: Zero accumulator

        check_case(
            3, 0, 32'h40000000, 0,
            0, 0, 0
        );


        // TEST 4: Exact half -> round upward
        // 1 * 0.5 = 0.5 -> 1

        check_case(
            4, 1, 32'h40000000, 0,
            1, 0, 0
        );


        // TEST 5: 1.5 -> 2

        check_case(
            5, 3, 32'h40000000, 0,
            2, 0, 0
        );


        // TEST 6: Below half
        // 1 * 0.25 = 0.25 -> 0

        check_case(
            6, 1, 32'h20000000, 0,
            0, 0, 0
        );


        // TEST 7: Above half
        // 1 * 0.75 = 0.75 -> 1

        check_case(
            7, 1, 32'h60000000, 0,
            1, 0, 0
        );


        // TEST 8: Negative shift
        // 400 * 0.5 / 2 = 100

        check_case(
            8, 400, 32'h40000000, -1,
            100, 0, 0
        );


        // TEST 9: Positive shift
        // 100 * 0.5 * 2 = 100

        check_case(
            9, 100, 32'h40000000, 1,
            100, 0, 0
        );


        // TEST 10: Exact 255
        // Must NOT trigger saturation

        check_case(
            10, 510, 32'h40000000, 0,
            255, 0, 0
        );


        // TEST 11: Saturation above 255

        check_case(
            11, 1000, 32'h40000000, 1,
            255, 1, 0
        );


        // TEST 12: Zero multiplier

        check_case(
            12, 1000, 32'h00000000, 0,
            0, 0, 0
        );


        // TEST 13: Minimum valid shift = -31

        check_case(
            13, 1, 32'h7FFFFFFF, -31,
            0, 0, 0
        );


        // TEST 14: Maximum valid shift = +30

        check_case(
            14, 1, 32'h40000000, 30,
            255, 1, 0
        );


        // TEST 15: Invalid shift +31

        check_case(
            15, 100, 32'h40000000, 31,
            0, 0, 1
        );


        // TEST 16: Invalid shift -32

        check_case(
            16, 100, 32'h40000000, -32,
            0, 0, 1
        );


        // TEST 17: Invalid Q31 multiplier

        check_case(
            17, 100, 32'h80000000, 0,
            0, 0, 1
        );


        $display("-----------------------------------------");
        $display("ALL REQUANT RELU UINT8 TESTS PASSED");
        $display("-----------------------------------------");

        $finish;

    end

endmodule
