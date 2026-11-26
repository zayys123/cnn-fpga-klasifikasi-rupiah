`timescale 1ns/1ps

module tb_conv_pixel_engine_actual;

    reg clk;
    reg rst_n;
    reg start;

    integer image_index;
    integer output_channel;
    integer output_y;
    integer output_x;

    reg [7:0] input_mem [0:43007];
    reg [7:0] weight_mem [0:215];

    reg [31:0] bias_mem [0:7];
    reg [31:0] multiplier_mem [0:7];
    reg [7:0] shift_mem [0:7];

    reg [7:0] expected_mem [0:114687];

    wire signed [31:0] bias;
    wire [31:0] multiplier_q31;
    wire signed [7:0] shift;

    wire [4:0] tap_index;
    wire tap_request;
    reg tap_valid;

    reg [7:0] activation;
    reg signed [7:0] weight;

    wire [7:0] pixel_out;
    wire done;
    wire busy;
    wire saturated;
    wire error;

    integer ic;
    integer ky;
    integer kx;
    integer iy;
    integer ix;

    integer input_addr;
    integer weight_addr;
    integer expected_addr;

    integer total_checked;
    integer errors;
    integer saturation_count;

    integer img;
    integer ch;
    integer row;
    integer col;

    conv_pixel_engine dut (

        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .bias(bias),
        .multiplier_q31(multiplier_q31),
        .shift(shift),

        .tap_index(tap_index),
        .tap_request(tap_request),

        .tap_valid(tap_valid),
        .activation(activation),
        .weight(weight),

        .pixel_out(pixel_out),
        .done(done),
        .busy(busy),
        .saturated(saturated),
        .error(error)

    );

    always #5 clk = ~clk;

    assign bias = $signed(bias_mem[output_channel]);

    assign multiplier_q31 = multiplier_mem[output_channel];

    assign shift = $signed(shift_mem[output_channel]);


    // Combinational-memory model for the actual CNN vectors.
    always @(*) begin

        tap_valid = 1'b0;

        activation = 8'd0;
        weight = 8'sd0;

        ic = 0;
        ky = 0;
        kx = 0;

        iy = 0;
        ix = 0;

        input_addr = 0;
        weight_addr = 0;

        if (tap_request) begin

            tap_valid = 1'b1;

            // Tap order:
            // [input_channel][kernel_y][kernel_x]

            ic = tap_index / 9;

            ky = (tap_index % 9) / 3;

            kx = tap_index % 3;

            // Zero padding = 1

            iy = output_y + ky - 1;
            ix = output_x + kx - 1;

            // OIHW weight layout

            weight_addr = output_channel * 27 + tap_index;

            weight = $signed(weight_mem[weight_addr]);

            // NCHW input layout

            if (
                iy >= 0 && iy < 32 &&
                ix >= 0 && ix < 32
            ) begin

                input_addr =
                    image_index * 3072 +
                    ic * 1024 +
                    iy * 32 +
                    ix;

                activation = input_mem[input_addr];

            end

            else begin

                activation = 8'd0;

            end

        end

    end


    // Execute and compare one output pixel.
    task run_pixel;

        input integer img_arg;
        input integer ch_arg;
        input integer row_arg;
        input integer col_arg;

        integer watchdog;

        begin

            @(negedge clk);

            image_index = img_arg;
            output_channel = ch_arg;
            output_y = row_arg;
            output_x = col_arg;

            start = 1'b1;

            @(negedge clk);

            start = 1'b0;

            watchdog = 0;

            while (done !== 1'b1 && watchdog < 40) begin

                @(negedge clk);

                watchdog = watchdog + 1;

            end

            if (done !== 1'b1) begin

                $display(
                    "TIMEOUT image=%0d channel=%0d y=%0d x=%0d",
                    img_arg, ch_arg, row_arg, col_arg
                );

                $fatal(1, "PIXEL ENGINE TIMEOUT");

            end

            #1;

            expected_addr =
                img_arg * 8192 +
                ch_arg * 1024 +
                row_arg * 32 +
                col_arg;

            total_checked = total_checked + 1;

            if (
                pixel_out !== expected_mem[expected_addr] ||
                error !== 1'b0
            ) begin

                errors = errors + 1;

                if (errors <= 20) begin

                    $display(
                        "MISMATCH image=%0d channel=%0d y=%0d x=%0d",
                        img_arg, ch_arg, row_arg, col_arg
                    );

                    $display(
                        "RTL=%02X EXPECTED=%02X ERROR=%b",
                        pixel_out,
                        expected_mem[expected_addr],
                        error
                    );

                end

            end

            if (saturated !== 1'b0)
                saturation_count = saturation_count + 1;

        end

    endtask


    initial begin

        clk = 0;
        rst_n = 0;
        start = 0;

        image_index = 0;
        output_channel = 0;
        output_y = 0;
        output_x = 0;

        total_checked = 0;
        errors = 0;
        saturation_count = 0;

        $display("-----------------------------------------");
        $display("LOADING CONV1 ACTUAL CNN VECTORS");
        $display("-----------------------------------------");

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

        #12;

        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        $display("-----------------------------------------");
        $display("STARTING CONV1 PIXEL VERIFICATION");
        $display("-----------------------------------------");

        for (img = 0; img < 14; img = img + 1) begin

            for (ch = 0; ch < 8; ch = ch + 1) begin

                for (row = 0; row < 32; row = row + 1) begin

                    for (col = 0; col < 32; col = col + 1) begin

                        run_pixel(img, ch, row, col);

                        if (total_checked % 16384 == 0)
                            $display(
                                "Processed %0d pixels",
                                total_checked
                            );

                    end

                end

            end

        end

        $display("-----------------------------------------");
        $display("CONV1 PIXEL VERIFICATION SUMMARY");
        $display("-----------------------------------------");

        $display("Total pixels     : %0d", total_checked);
        $display("Expected pixels  : 114688");
        $display("Total errors     : %0d", errors);
        $display("Saturation count : %0d", saturation_count);

        $display("-----------------------------------------");

        if (
            total_checked == 114688 &&
            errors == 0 &&
            saturation_count == 0
        ) begin

            $display("ALL CONV1 PIXEL TESTS PASSED");

        end

        else begin

            $fatal(1, "CONV1 PIXEL VERIFICATION FAILED");

        end

        $display("-----------------------------------------");

        $finish;

    end

endmodule
