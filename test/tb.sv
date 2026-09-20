`timescale 1ns/1ps
module tb;
    parameter integer N=16;
    reg clk=0, rst_n=0, ena=1;
    reg [7:0] ui_in=0, uio_in=0;
    wire [7:0] uo_out,uio_out,uio_oe;
    izh_bridge #(.N(N)) dut(.*);
    always #5 clk=~clk;
    task tick; @(posedge clk); #1; endtask
    task drive; @(negedge clk); endtask
    task pulse(input [3:0] mask);
        drive(); uio_in[7:4]=mask;
        repeat(5) tick();
        drive(); uio_in[7:4]=0;
        repeat(5) tick();
    endtask
    task transact(input [39:0] command, input [39:0] expected);
        integer j, timeout;
        reg [7:0] held;
        for(j=0;j<5;j=j+1) begin
            drive(); ui_in=command[39-j*8 -: 8]; uio_in[0]=1;
            timeout=0;
            while(!uio_out[1]) begin tick(); timeout++; if(timeout>3000) $fatal(1,"RX timeout"); end
            tick(); drive(); uio_in[0]=0;
            // Deliberate command pauses exercise packet framing.
            if(j==2) repeat(2) tick();
        end
        timeout=0;
        while(!uio_out[3]) begin tick(); timeout++; if(timeout>3000) $fatal(1,"TX timeout"); end
        for(j=0;j<5;j=j+1) begin
            held=uo_out;
            // Backpressure: a byte must remain stable without ready.
            repeat(2) begin tick(); if(uo_out!==held || !uio_out[3]) $fatal(1,"Unstable response"); end
            if(held!==expected[39-j*8 -: 8])
                $fatal(1,"row=%0d byte=%0d cmd=%h expected=%h actual=%h",rows,j,command,expected,held);
            drive(); uio_in[2]=1; tick(); drive(); uio_in[2]=0;
        end
    endtask
    integer cycles=0, step_start=-1;
    reg reported=0;
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(dut.bank.req_valid && dut.bank.req_ready && dut.bank.op==3) step_start<=cycles;
        if(step_start>=0 && dut.bank.resp_valid && !reported) begin
            $display("STEP N=%0d core_cycles=%0d",N,cycles-step_start-1);
            reported<=1;
        end
    end
    integer fd, rc, rows=0;
    reg [7:0] event_flags;
    reg [39:0] command, expected;
    string filename;
    initial begin
        if(!$value$plusargs("vectors=%s",filename)) $fatal(1,"Missing vectors file");
        repeat(4) tick(); drive(); rst_n=1;
        fd=$fopen(filename,"r"); if(fd==0) $fatal(1,"No vectors");
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h\n",event_flags,command,expected);
            if(rc==3) begin
                if(event_flags[3:0]!=0) pulse(event_flags[3:0]);
                if(event_flags[4]) pulse(event_flags[3:0]);
                transact(command,expected); rows++;
            end
        end
        $fclose(fd);
        // Reset clears configured and dynamic state and partially assembled frames.
        drive(); ui_in=8'h01; uio_in[0]=1; tick();
        drive(); ui_in=8'h40; tick();
        drive(); uio_in[0]=0; rst_n=0; repeat(4) tick(); drive(); rst_n=1;
        transact(40'h0200000000,40'h00009a5903);
        if(uio_oe!==8'h0a) $fatal(1,"Incorrect pin direction");
        $display("PASS N=%0d transactions=%0d; state/readback, backpressure, external events, reset",N,rows);
        $finish;
    end
endmodule
