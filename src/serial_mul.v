`timescale 1ns/1ps
`default_nettype none
// Original portable RTL. Exact signed 20 x 20 multiply, 20 iterations.
module serial_mul (
    input wire clk, input wire rst_n, input wire start,
    input wire signed [19:0] a, b,
    output reg busy, output reg done, output reg signed [39:0] product
);
    reg [39:0] acc, shifted;
    reg [19:0] remaining;
    reg [4:0] count;
    reg negative;
    wire [39:0] sum = acc + (remaining[0] ? shifted : 40'd0);
    wire [19:0] amag = a[19] ? -a : a;
    wire [19:0] bmag = b[19] ? -b : b;
    always @(posedge clk) begin
        if (!rst_n) begin
            acc <= 0; shifted <= 0; remaining <= 0; count <= 0;
            negative <= 0; busy <= 0; done <= 0; product <= 0;
        end else begin
            done <= 0;
            if (start && !busy) begin
                acc <= 0; shifted <= {20'd0, amag}; remaining <= bmag;
                negative <= a[19] ^ b[19]; count <= 0; busy <= 1;
            end else if (busy) begin
                acc <= sum; shifted <= shifted << 1; remaining <= remaining >> 1;
                count <= count + 1'b1;
                if (count == 19) begin
                    product <= negative ? -$signed(sum) : $signed(sum);
                    busy <= 0; done <= 1;
                end
            end
        end
    end
endmodule
`default_nettype wire
