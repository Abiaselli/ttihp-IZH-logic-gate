`timescale 1ns/1ps
`default_nettype none
// Byte-stream transport. Host signals synchronous to clk; external events async.
module izh_bridge #(parameter integer N=16)(
    input wire [7:0] ui_in, output wire [7:0] uo_out,
    input wire [7:0] uio_in, output wire [7:0] uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    wire _unused = &{1'b0,uio_in[3],uio_in[1]};
    localparam RX=0, ISSUE=1, WAIT=2, TX=3;
    reg [1:0] state;
    reg [2:0] byte_idx;
    reg [7:0] op, address;
    reg [17:0] data;
    reg [3:0] sync1, sync2, delayed;
    wire [3:0] events = sync2 & ~delayed;
    wire req_ready, resp_valid;
    wire [7:0] status, response_address;
    wire [17:0] response_data;
    wire response_taken = ena && state == TX && byte_idx == 4 && uio_in[2];
    neuron_bank #(.N(N)) bank(
        .clk(clk),.rst_n(rst_n),.ext_event(events),
        .req_valid(ena && state==ISSUE),.req_ready(req_ready),.op(op),.address(address),.data(data),
        .resp_valid(resp_valid),.resp_ready(response_taken),
        .status(status),.response_address(response_address),.response_data(response_data));
    assign uio_oe = 8'h0a;
    assign uio_out = {4'd0,(ena && state==TX),1'b0,(ena && state==RX),1'b0};
    assign uo_out = byte_idx==0 ? status : byte_idx==1 ? response_address :
                    byte_idx==2 ? response_data[7:0] : byte_idx==3 ? response_data[15:8] :
                    {6'd0,response_data[17:16]};
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=RX; byte_idx<=0; op<=0; address<=0; data<=0;
            sync1<=0; sync2<=0; delayed<=0;
        end else begin
            sync1<=uio_in[7:4]; sync2<=sync1; delayed<=sync2;
            if (ena) case (state)
                RX: if (uio_in[0]) begin
                    case (byte_idx)
                        0: op<=ui_in; 1: address<=ui_in;
                        2: data[7:0]<=ui_in; 3: data[15:8]<=ui_in;
                        4: data[17:16]<=ui_in[1:0];
                        default: ;
                    endcase
                    if (byte_idx==4) begin state<=ISSUE; byte_idx<=0; end
                    else byte_idx<=byte_idx+1'b1;
                end
                ISSUE: if (req_ready) state<=WAIT;
                WAIT: if (resp_valid) begin state<=TX; byte_idx<=0; end
                TX: if (uio_in[2]) begin
                    if (byte_idx==4) begin state<=RX; byte_idx<=0; end
                    else byte_idx<=byte_idx+1'b1;
                end
            endcase
        end
    end
endmodule

module tt_um_abiaselli_izh_bridge_6x4(
    input wire [7:0] ui_in, output wire [7:0] uo_out,
    input wire [7:0] uio_in, output wire [7:0] uio_out, uio_oe,
    input wire ena, clk, rst_n
);
    izh_bridge #(.N(16)) impl(
        .ui_in(ui_in), .uo_out(uo_out),
        .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );
endmodule

`default_nettype wire
