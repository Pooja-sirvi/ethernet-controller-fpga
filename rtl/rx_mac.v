`timescale 1ns / 1ps
// ============================================================
// RX MAC (clk = 50 MHz RMII reference clock)
//
// Mirror image of tx_mac:
//   RMII dibits -> bytes -> check CRC -> drop FCS -> 32-bit words -> FIFO
//
// Store-and-forward: the whole frame is kept in a local buffer first.
// Only if the CRC is good are the words pushed into the RX FIFO, so a
// bad frame never reaches the DMA/BRAM.
//
// FIFO word = {TLAST, DATA[31:0]}, first received byte in DATA[31:24]
// (same byte order as tx_mac, so TX BRAM word == RX BRAM word).
//
// A 64-byte frame = 60 bytes + 4 FCS, so 15 words are delivered:
// the 8 data words followed by 7 padding words of zeros.
// ============================================================
module rx_mac (
    input  wire        clk_50,
    input  wire        reset,

    // RMII from PHY
    input  wire        crs_dv,
    input  wire [1:0]  rxd,
    input  wire        rx_er,

    // RX FIFO write side
    output reg  [32:0] fifo_din,
    output reg         fifo_wr_en,
    input  wire        fifo_full,

    // status
    output reg         frame_ok,      // 1-clock pulse: good frame delivered
    output reg         frame_err,     // 1-clock pulse: bad frame dropped
    output reg         busy,
    output wire [3:0]  debug_state
);

    localparam S_IDLE     = 4'd0;
    localparam S_PREAMBLE = 4'd1;
    localparam S_DATA     = 4'd2;
    localparam S_CHECK    = 4'd3;
    localparam S_PUSH     = 4'd4;

    reg [3:0] state;
    assign debug_state = state;

    // register the PHY inputs once
    reg       crs_q, er_q;
    reg [1:0] rxd_q;
    always @(posedge clk_50) begin
        crs_q <= crs_dv;
        rxd_q <= rxd;
        er_q  <= rx_er;
    end

    reg [7:0] pkt_mem [0:255];
    reg [8:0] nbytes;
    reg [7:0] sh;
    reg [1:0] dib_cnt;
    reg [31:0] crc_reg;
    reg       err_flag, overflow;

    reg [8:0] payload_bytes;
    reg [6:0] widx;

    wire [7:0] full_byte = {rxd_q, sh[7:2]};

    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0]  data;
        integer i;
        reg [31:0] c;
        begin
            c = crc;
            for (i = 0; i < 8; i = i + 1) begin
                if (c[0] ^ data[i]) c = (c >> 1) ^ 32'hEDB88320;
                else                c = c >> 1;
            end
            crc32_byte = c;
        end
    endfunction

    // ---- word builder for the PUSH state ----
    wire [8:0] base = {widx, 2'b00};
    function [7:0] gb;
        input [8:0] a;
        begin
            gb = (a < payload_bytes) ? pkt_mem[a[7:0]] : 8'h00;
        end
    endfunction
    wire [31:0] word = {gb(base), gb(base + 9'd1), gb(base + 9'd2), gb(base + 9'd3)};
    wire        last = ((base + 9'd4) >= payload_bytes);

    always @(posedge clk_50) begin
        if (reset) begin
            state <= S_IDLE;
            fifo_din <= 33'd0;
            fifo_wr_en <= 1'b0;
            frame_ok <= 1'b0;
            frame_err <= 1'b0;
            busy <= 1'b0;
            nbytes <= 9'd0;
            sh <= 8'd0;
            dib_cnt <= 2'd0;
            crc_reg <= 32'hFFFFFFFF;
            err_flag <= 1'b0;
            overflow <= 1'b0;
            payload_bytes <= 9'd0;
            widx <= 7'd0;
        end
        else begin
            fifo_wr_en <= 1'b0;
            frame_ok   <= 1'b0;
            frame_err  <= 1'b0;

            case (state)

            S_IDLE: begin
                busy     <= 1'b0;
                nbytes   <= 9'd0;
                dib_cnt  <= 2'd0;
                crc_reg  <= 32'hFFFFFFFF;
                err_flag <= 1'b0;
                overflow <= 1'b0;
                // frame starts: carrier valid and first preamble dibit (01)
                if (crs_q && rxd_q == 2'b01) begin
                    busy  <= 1'b1;
                    state <= S_PREAMBLE;
                end
            end

            // wait here while we see 01 01 01 ...; the first 11 is the SFD
            S_PREAMBLE: begin
                if (!crs_q)
                    state <= S_IDLE;                 // frame ended too early
                else if (rxd_q == 2'b11) begin
                    dib_cnt <= 2'd0;
                    state   <= S_DATA;               // data starts next dibit
                end
                else if (rxd_q != 2'b01)
                    state <= S_IDLE;                 // not a valid preamble
            end

            S_DATA: begin
                if (crs_q) begin
                    if (er_q) err_flag <= 1'b1;
                    sh      <= {rxd_q, sh[7:2]};
                    dib_cnt <= dib_cnt + 1'b1;
                    if (dib_cnt == 2'd3) begin
                        if (nbytes == 9'd256) overflow <= 1'b1;
                        else begin
                            pkt_mem[nbytes[7:0]] <= full_byte;
                            nbytes <= nbytes + 1'b1;
                        end
                        crc_reg <= crc32_byte(crc_reg, full_byte);
                    end
                end
                else begin
                    state <= S_CHECK;                // carrier dropped = end of frame
                end
            end

            S_CHECK: begin
                // CRC over data+FCS leaves the fixed value DEBB20E3 when the frame is good
                if (crc_reg == 32'hDEBB20E3 && !err_flag && !overflow &&
                    dib_cnt == 2'd0 && nbytes > 9'd4) begin
                    payload_bytes <= nbytes - 9'd4;  // drop the 4 FCS bytes
                    widx  <= 7'd0;
                    state <= S_PUSH;
                end
                else begin
                    frame_err <= 1'b1;
                    state <= S_IDLE;
                end
            end

            S_PUSH: begin
                if (!fifo_full) begin
                    fifo_din   <= {last, word};
                    fifo_wr_en <= 1'b1;
                    if (last) begin
                        frame_ok <= 1'b1;
                        state    <= S_IDLE;
                    end
                    else widx <= widx + 1'b1;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end
endmodule
