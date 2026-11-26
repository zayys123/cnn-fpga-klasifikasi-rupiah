module maxpool2x2_uint8 (

    input wire [7:0] pixel00,
    input wire [7:0] pixel01,
    input wire [7:0] pixel10,
    input wire [7:0] pixel11,

    output reg [7:0] pooled_value

);

    always @(*) begin

        // Initialize with first pixel
        pooled_value = pixel00;

        // Compare second pixel
        if (pixel01 > pooled_value)
            pooled_value = pixel01;

        // Compare third pixel
        if (pixel10 > pooled_value)
            pooled_value = pixel10;

        // Compare fourth pixel
        if (pixel11 > pooled_value)
            pooled_value = pixel11;

    end

endmodule
