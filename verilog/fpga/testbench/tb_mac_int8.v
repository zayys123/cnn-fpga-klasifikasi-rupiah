`timescale 1ns/1ps

module tb_mac_int8;

    reg clk;
    reg rst_n;

    reg clear;
    reg load_bias;
    reg enable;

    reg [7:0] activation;
    reg signed [7:0] weight;
    reg signed [31:0] bias;

    wire signed [31:0] accumulator;
    wire overflow;

    mac_int8 dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .load_bias(load_bias),
        .enable(enable),
        .activation(activation),
        .weight(weight),
        .bias(bias),
        .accumulator(accumulator),
        .overflow(overflow)
    );

    always #5 clk = ~clk;

    task tick;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    initial begin

        clk = 0;
        rst_n = 0;

        clear = 0;
        load_bias = 0;
        enable = 0;

        activation = 0;
        weight = 0;
        bias = 0;

        // Reset
        #12;
        rst_n = 1;
        tick();

        // Test 1: Load bias
        load_bias = 1;
        bias = 32'sd100;
        tick();
        load_bias = 0;

        // Test 2: 100 + (10 * 3) = 130
        activation = 8'd10;
        weight = 8'sd3;
        enable = 1;
        tick();
        enable = 0;

        if (accumulator !== 32'sd130)
            $fatal(1, "TEST 1 FAILED");

        // Test 3: 130 + (255 * -127) = -32255
        activation = 8'd255;
        weight = -8'sd127;
        enable = 1;
        tick();
        enable = 0;

        if (accumulator !== -32'sd32255)
            $fatal(1, "TEST 2 FAILED");

        // Test 4: Clear
        clear = 1;
        tick();
        clear = 0;

        if (accumulator !== 32'sd0)
            $fatal(1, "TEST 3 FAILED");

        // Test 5: Positive overflow
        load_bias = 1;
        bias = 32'sh7FFFFFFF;
        tick();
        load_bias = 0;

        activation = 8'd1;
        weight = 8'sd1;
        enable = 1;
        tick();
        enable = 0;

        if (overflow !== 1'b1)
            $fatal(1, "TEST 4 FAILED: overflow not detected");

        if (accumulator !== 32'sh7FFFFFFF)
            $fatal(1, "TEST 4 FAILED: accumulator changed");

        // Test 6: Clear overflow
        clear = 1;
        tick();
        clear = 0;

        if (overflow !== 1'b0)
            $fatal(1, "TEST 5 FAILED");

        if (accumulator !== 32'sd0)
            $fatal(1, "TEST 5 FAILED");

        $display("--------------------------------");
        $display("ALL MAC INT8 TESTS PASSED");
        $display("--------------------------------");

        $finish;

    end

endmodule
