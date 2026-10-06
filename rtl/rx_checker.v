`timescale 1ns / 1ps
// ============================================================
// RX checker (125 MHz). When rx_dma finishes a frame (start pulse),
// reads RX BRAM words 0..7 and compares them with the expected packet
// (the same 8 words as tx_bram.coe).
//   match_ok  = 1 -> all 8 words equal
//   match_bad = 1 -> at least one word differs
// ============================================================
module rx_checker #(
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  start,

    output reg  [ADDR_WIDTH-1:0] rd_addr,
    input  wire [31:0]           rd_data,

    output reg                   match_ok,
    output reg                   match_bad
);

    function [31:0] expected;
        input [2:0] i;
        begin
            case (i)
                3'd0: expected = 32'hFFFFFFFF;
                3'd1: expected = 32'hFFFF0011;
                3'd2: expected = 32'h22334455;
                3'd3: expected = 32'h88B5AABB;
                3'd4: expected = 32'hCCDDEEFF;
                3'd5: expected = 32'h01020304;
                3'd6: expected = 32'h05060708;
                default: expected = 32'h090A0B0C;
            endcase
        end
    endfunction

    localparam S_IDLE = 2'd0, S_SET = 2'd1, S_WAIT = 2'd2, S_CMP = 2'd3;

    reg [1:0] state;
    reg [2:0] idx;
    reg       mismatch;

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            idx <= 3'd0;
            mismatch <= 1'b0;
            rd_addr <= 0;
            match_ok <= 1'b0;
            match_bad <= 1'b0;
        end
        else begin
            case (state)
            S_IDLE: if (start) begin
                idx <= 3'd0;
                mismatch <= 1'b0;
                state <= S_SET;
            end

            S_SET: begin
                rd_addr <= idx;
                state <= S_WAIT;
            end

            S_WAIT: state <= S_CMP;          // BRAM read takes one clock

            S_CMP: begin
                if (rd_data !== expected(idx)) mismatch <= 1'b1;
                if (idx == 3'd7) begin
                    match_ok  <= !(mismatch || (rd_data !== expected(idx)));
                    match_bad <=  (mismatch || (rd_data !== expected(idx)));
                    state <= S_IDLE;
                end
                else begin
                    idx <= idx + 1'b1;
                    state <= S_SET;
                end
            end
            endcase
        end
    end
endmodule
