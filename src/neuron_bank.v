`timescale 1ns/1ps
`default_nettype none
// One arithmetic engine, N independently stored neuron contexts (N=4 or 16).
// State/current values are (biological model value / 100) * 65536.
// a,b are unscaled dimensionless values * 65536. dt = 1/16 ms.
module neuron_bank #(parameter integer N = 16) (
    input wire clk, rst_n,
    input wire [3:0] ext_event,
    input wire req_valid, output wire req_ready,
    input wire [7:0] op, address, input wire [17:0] data,
    output reg resp_valid, input wire resp_ready,
    output reg [7:0] status, response_address,
    output reg [17:0] response_data
);
    reg signed [17:0] v[0:N-1], u[0:N-1], syn[0:N-1], bias[0:N-1];
    reg signed [17:0] a[0:N-1], b[0:N-1], c[0:N-1], d[0:N-1];
    reg signed [17:0] w0[0:N-1], w1[0:N-1];
    reg [4:0] src0[0:N-1], src1[0:N-1];
    reg [15:0] spikes, next_spikes;
    reg [3:0] pending, ext_frame;
    reg event_overrun, clipped;
    reg [3:0] idx;
    localparam integer AW = $clog2(N);
    wire [AW-1:0] ix=idx[AW-1:0];
    wire [AW-1:0] tx=address[AW-1:0];
    localparam IDLE=0, LOAD=1, VWAIT=2, BWAIT=3, AWAIT=4, FINISH=5;
    reg [2:0] state;
    localparam [4:0] COUNT = N[4:0];
    reg mul_start;
    reg signed [19:0] ma, mb;
    wire mul_done, mul_busy;
    wire signed [39:0] product;
    reg signed [31:0] quadratic;
    reg signed [17:0] snew;
    serial_mul mul(clk, rst_n, mul_start, ma, mb, mul_busy, mul_done, product);
    assign req_ready = (state == IDLE) && !resp_valid;
    wire [3:0] target = address[3:0];
    wire [3:0] field = address[7:4];

    function signed [31:0] sx;
        input signed [17:0] x;
        begin sx = {{14{x[17]}},x}; end
    endfunction
    function signed [17:0] sat;
        input signed [31:0] x;
        begin
            if (x > 131071) sat = 18'sd131071;
            else if (x < -131072) sat = -18'sd131072;
            else sat = x[17:0];
        end
    endfunction
    function outside;
        input signed [31:0] x;
        begin outside = (x > 131071) || (x < -131072); end
    endfunction
    function fired;
        input [4:0] source;
        begin
            if (source < COUNT) fired = spikes[source[3:0]];
            else if (source >= 16 && source < 20) fired = ext_frame[source[1:0]];
            else fired = 1'b0;
        end
    endfunction
    // Decay toward zero; avoids a negative one-LSB fixed point.
    wire signed [31:0] s_old = sx(syn[ix]);
    wire signed [31:0] s_decay = s_old < 0 ? -(((-s_old)+15) >>> 4) : (s_old+15) >>> 4;
    wire signed [31:0] s_calc = s_old - s_decay
        + (fired(src0[ix]) ? sx(w0[ix]) : 32'sd0)
        + (fired(src1[ix]) ? sx(w1[ix]) : 32'sd0);
    wire signed [31:0] p16 = $signed({{8{product[39]}},product[39:16]}) + $signed({31'd0,product[15]});
    wire signed [31:0] bv_minus_u = p16 - sx(u[ix]);
    wire signed [31:0] v_calc = sx(v[ix]) + ((quadratic
        + (sx(v[ix]) <<< 2) + sx(v[ix]) + 32'sd91750
        - sx(u[ix]) + sx(bias[ix]) + sx(snew) + 32'sd8) >>> 4);
    wire signed [31:0] u_calc = sx(u[ix]) + $signed({{12{product[39]}},product[39:20]}) + $signed({31'd0,product[19]});
    wire crosses = v_calc >= 32'sd19661;
    wire signed [31:0] u_final = u_calc + (crosses ? sx(d[ix]) : 32'sd0);
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE; resp_valid <= 0; status <= 0; response_address <= 0;
            response_data <= 0; pending <= 0; ext_frame <= 0; event_overrun <= 0;
            clipped <= 0; idx <= 0; spikes <= 0; next_spikes <= 0;
            mul_start <= 0; ma <= 0; mb <= 0; quadratic <= 0; snew <= 0;
            for (k=0;k<N;k=k+1) begin
                v[k] <= -18'sd42598; u[k] <= -18'sd8520; syn[k] <= 0; bias[k] <= 0;
                a[k] <= 18'sd1311; b[k] <= 18'sd13107; c[k] <= -18'sd42598;
                d[k] <= 18'sd5243; w0[k] <= 0; w1[k] <= 0;
                src0[k] <= 31; src1[k] <= 31;
            end
        end else begin
            pending <= pending | ext_event;
            if (|(pending & ext_event)) event_overrun <= 1;
            mul_start <= 0;
            if (resp_valid && resp_ready) resp_valid <= 0;
            case (state)
                IDLE: if (req_valid && req_ready) begin
                    status <= 0; response_address <= address; response_data <= 0;
                    if (op == 8'h03) begin
                        idx <= 0; next_spikes <= 0; clipped <= 0;
                        ext_frame <= pending | ext_event; pending <= 0; state <= LOAD;
                    end else if (op != 8'h01 && op != 8'h02) begin
                        status <= 8'h80; resp_valid <= 1;
                    end else if ({1'b0,target} >= COUNT || field > 11) begin
                        status <= 8'h81; resp_valid <= 1;
                    end else begin
                        resp_valid <= 1;
                        if (op == 8'h01) begin
                            case (field)
                                0: v[tx] <= data; 1: u[tx] <= data;
                                2: syn[tx] <= data; 3: bias[tx] <= data;
                                4: a[tx] <= data; 5: b[tx] <= data;
                                6: c[tx] <= data; 7: d[tx] <= data;
                                8: w0[tx] <= data; 9: w1[tx] <= data;
                                10: src0[tx] <= data[4:0]; 11: src1[tx] <= data[4:0];
                                default: ;
                            endcase
                        end else case (field)
                            0: response_data <= v[tx]; 1: response_data <= u[tx];
                            2: response_data <= syn[tx]; 3: response_data <= bias[tx];
                            4: response_data <= a[tx]; 5: response_data <= b[tx];
                            6: response_data <= c[tx]; 7: response_data <= d[tx];
                            8: response_data <= w0[tx]; 9: response_data <= w1[tx];
                            10: response_data <= {13'd0,src0[tx]};
                            11: response_data <= {13'd0,src1[tx]};
                            default: ;
                        endcase
                    end
                end
                LOAD: begin
                    snew <= sat(s_calc); clipped <= clipped | outside(s_calc);
                    ma <= {{2{v[ix][17]}},v[ix]}; mb <= {{2{v[ix][17]}},v[ix]};
                    mul_start <= 1; state <= VWAIT;
                end
                VWAIT: if (mul_done) begin
                    quadratic <= $signed({{6{product[39]}},product[39:14]}) + $signed({31'd0,product[13]}); // 4*x*x in Q16
                    ma <= {{2{b[ix][17]}},b[ix]}; mb <= {{2{v[ix][17]}},v[ix]};
                    mul_start <= 1; state <= BWAIT;
                end
                BWAIT: if (mul_done) begin
                    ma <= {{2{a[ix][17]}},a[ix]}; mb <= bv_minus_u[19:0];
                    mul_start <= 1; state <= AWAIT;
                end
                AWAIT: if (mul_done) begin
                    v[ix] <= crosses ? c[ix] : sat(v_calc);
                    u[ix] <= sat(u_final); syn[ix] <= snew;
                    clipped <= clipped | outside(u_final) | (!crosses && outside(v_calc));
                    next_spikes[idx] <= crosses;
                    if ({1'b0,idx} == COUNT-5'd1) state <= FINISH;
                    else begin idx <= idx + 1'b1; state <= LOAD; end
                end
                FINISH: begin
                    spikes <= next_spikes; response_data <= {2'd0,next_spikes};
                    response_address <= 0;
                    status <= {6'd0,event_overrun,clipped};
                    resp_valid <= 1; state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
    wire _unused = &{1'b0,mul_busy,bv_minus_u[31:20],product[13:0]};
endmodule
`default_nettype wire
