`timescale 1ns/1ps
module tb_mul;
    reg clk=0,rst_n=0,start=0;
    reg signed [19:0] a=0,b=0;
    wire busy,done;
    wire signed [39:0] product;
    serial_mul dut(.*);
    always #5 clk=~clk;
    task check(input signed [19:0] x,y);
        reg signed [39:0] expected;
        expected=x*y;
        @(negedge clk); a=x; b=y; start=1;
        @(negedge clk); start=0;
        while(!done) begin @(posedge clk); #1; end
        if(product!==expected) $fatal(1,"multiply %0d * %0d got %0d expected %0d",x,y,product,expected);
    endtask
    integer i,j;
    reg signed [19:0] edge_values[0:6];
    initial begin
        edge_values[0]=-524288; edge_values[1]=-1; edge_values[2]=0;
        edge_values[3]=1; edge_values[4]=524287; edge_values[5]=-131072; edge_values[6]=131071;
        repeat(3) @(negedge clk); rst_n=1;
        for(i=0;i<7;i++) for(j=0;j<7;j++) check(edge_values[i],edge_values[j]);
        for(i=0;i<1000;i++) check(20'($random),20'($random));
        $display("PASS multiplier: 49 signed corner pairs and 1000 random pairs");
        $finish;
    end
endmodule
