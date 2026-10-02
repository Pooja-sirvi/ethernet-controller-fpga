`timescale 1ns / 1ps
// ============================================================
// TX MAC - store-and-forward version
//
// Phase 1 (READ_REQ/READ_WAIT/LOAD_WORD): pull the WHOLE packet out of
//   the FIFO into a small local buffer, one word at a time, only when
//   the FIFO is not empty, until the TLAST bit is seen.
// Phase 2 (PREAMBLE..IFG): transmit from the local buffer. It can never
//   underrun, so TXEN can never hang waiting for the FIFO.
//
// Ports and state numbers are identical to the old design, so top.v and
// the ILA state mapping do not change.
// Bytes go out MSB-first within each 32-bit word (11223344 -> 11 22 33 44),
// and each byte goes out LSB-first as 2-bit pieces on RMII.
// ============================================================
module tx_mac #(
    parameter ADDR_BITS = 6          // buffer = 64 words = 256 bytes
)(
    input  wire        clk_50,
    input  wire        reset,

    input  wire [32:0] fifo_dout,    // {TLAST, DATA[31:0]}
    input  wire        fifo_empty,
    output reg         fifo_rd_en,

    output reg         eth_tx_en,
    output reg  [1:0]  eth_txd,
    output reg         busy,
    output wire [3:0]  debug_state
);

    localparam STATE_IDLE      = 4'd0;
    localparam STATE_READ_REQ  = 4'd1;
    localparam STATE_READ_WAIT = 4'd2;
    localparam STATE_LOAD_WORD = 4'd3;
    localparam STATE_PREAMBLE  = 4'd4;
    localparam STATE_SFD       = 4'd5;
    localparam STATE_DATA      = 4'd6;
    localparam STATE_PADDING   = 4'd7;
    localparam STATE_FCS       = 4'd8;
    localparam STATE_IFG       = 4'd9;

    reg [3:0] state;
    assign debug_state = state;

    // local packet buffer
    reg [31:0] pkt_mem [0:(1<<ADDR_BITS)-1];
    reg [ADDR_BITS-1:0] wr_idx;
    reg [ADDR_BITS-1:0] rd_idx;
    reg [ADDR_BITS-1:0] last_idx;

    reg [1:0] byte_index;
    reg [1:0] rmii_pair;
    reg [2:0] preamble_byte_count;
    reg [5:0] padding_count;
    reg [31:0] crc_reg;
    reg [31:0] fcs_reg;
    reg [1:0]  fcs_index;
    reg [5:0]  ifg_count;

    wire [31:0] cur_word = pkt_mem[rd_idx];
    wire [8:0]  data_bytes =
        ({{(9-ADDR_BITS){1'b0}}, last_idx} + 9'd1) << 2;

    reg [7:0] tx_byte;
    always @(*) begin
        case (byte_index)
            2'd0: tx_byte = cur_word[31:24];
            2'd1: tx_byte = cur_word[23:16];
            2'd2: tx_byte = cur_word[15:8];
            default: tx_byte = cur_word[7:0];
        endcase
    end

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

    always @(posedge clk_50) begin
        if (reset) begin
            state <= STATE_IDLE;
            fifo_rd_en <= 1'b0;
            eth_tx_en <= 1'b0;
            eth_txd <= 2'b00;
            busy <= 1'b0;
            wr_idx <= 0;
            rd_idx <= 0;
            last_idx <= 0;
            byte_index <= 2'd0;
            rmii_pair <= 2'd0;
            preamble_byte_count <= 3'd0;
            padding_count <= 6'd0;
            crc_reg <= 32'hFFFFFFFF;
            fcs_reg <= 32'h0;
            fcs_index <= 2'd0;
            ifg_count <= 6'd0;
        end
        else begin
            fifo_rd_en <= 1'b0;

            case (state)

            STATE_IDLE: begin
                eth_tx_en <= 1'b0;
                eth_txd   <= 2'b00;
                busy      <= 1'b0;
                wr_idx    <= 0;
                rd_idx    <= 0;
                byte_index <= 2'd0;
                rmii_pair  <= 2'd0;
                preamble_byte_count <= 3'd0;
                crc_reg <= 32'hFFFFFFFF;
                if (!fifo_empty) begin
                    busy  <= 1'b1;
                    state <= STATE_READ_REQ;
                end
            end

            // Only read when the FIFO really has data. If it is empty
            // we simply wait here (no timeout needed for the demo).
            STATE_READ_REQ: begin
                eth_tx_en <= 1'b0;
                eth_txd   <= 2'b00;
                busy      <= 1'b1;
                if (!fifo_empty) begin
                    fifo_rd_en <= 1'b1;      // high during READ_WAIT
                    state <= STATE_READ_WAIT;
                end
            end

            STATE_READ_WAIT: begin           // FIFO samples rd_en at end of this cycle
                state <= STATE_LOAD_WORD;
            end

            STATE_LOAD_WORD: begin           // dout is valid now
                pkt_mem[wr_idx] <= fifo_dout[31:0];
                if (fifo_dout[32] || (&wr_idx)) begin   // TLAST (or buffer full)
                    last_idx   <= wr_idx;
                    rd_idx     <= 0;
                    byte_index <= 2'd0;
                    rmii_pair  <= 2'd0;
                    preamble_byte_count <= 3'd0;
                    crc_reg    <= 32'hFFFFFFFF;
                    state      <= STATE_PREAMBLE;
                end
                else begin
                    wr_idx <= wr_idx + 1'b1;
                    state  <= STATE_READ_REQ;
                end
            end

            STATE_PREAMBLE: begin
                eth_tx_en <= 1'b1;
                eth_txd   <= 2'b01;
                if (rmii_pair == 2'd3) begin
                    rmii_pair <= 2'd0;
                    if (preamble_byte_count == 3'd6) begin
                        preamble_byte_count <= 3'd0;
                        state <= STATE_SFD;
                    end
                    else preamble_byte_count <= preamble_byte_count + 1'b1;
                end
                else rmii_pair <= rmii_pair + 1'b1;
            end

            STATE_SFD: begin
                eth_tx_en <= 1'b1;
                eth_txd   <= (rmii_pair == 2'd3) ? 2'b11 : 2'b01;
                if (rmii_pair == 2'd3) begin
                    rmii_pair  <= 2'd0;
                    byte_index <= 2'd0;
                    state <= STATE_DATA;
                end
                else rmii_pair <= rmii_pair + 1'b1;
            end

            STATE_DATA: begin
                eth_tx_en <= 1'b1;
                case (rmii_pair)
                    2'd0: eth_txd <= tx_byte[1:0];
                    2'd1: eth_txd <= tx_byte[3:2];
                    2'd2: eth_txd <= tx_byte[5:4];
                    2'd3: eth_txd <= tx_byte[7:6];
                endcase

                if (rmii_pair == 2'd3) begin
                    rmii_pair <= 2'd0;
                    crc_reg <= crc32_byte(crc_reg, tx_byte);

                    if (byte_index == 2'd3) begin
                        byte_index <= 2'd0;
                        if (rd_idx == last_idx) begin
                            if (data_bytes < 9'd60) begin
                                padding_count <= 6'd60 - data_bytes[5:0];
                                state <= STATE_PADDING;
                            end
                            else begin
                                fcs_reg   <= ~crc32_byte(crc_reg, tx_byte);
                                fcs_index <= 2'd0;
                                state <= STATE_FCS;
                            end
                        end
                        else rd_idx <= rd_idx + 1'b1;
                    end
                    else byte_index <= byte_index + 1'b1;
                end
                else rmii_pair <= rmii_pair + 1'b1;
            end

            STATE_PADDING: begin
                eth_tx_en <= 1'b1;
                eth_txd   <= 2'b00;
                if (rmii_pair == 2'd3) begin
                    rmii_pair <= 2'd0;
                    crc_reg   <= crc32_byte(crc_reg, 8'h00);
                    if (padding_count == 6'd1) begin
                        fcs_reg   <= ~crc32_byte(crc_reg, 8'h00);
                        fcs_index <= 2'd0;
                        state <= STATE_FCS;
                    end
                    else padding_count <= padding_count - 1'b1;
                end
                else rmii_pair <= rmii_pair + 1'b1;
            end

            STATE_FCS: begin
                eth_tx_en <= 1'b1;
                // byte0 = fcs[7:0] first, each byte LSB dibit first
                eth_txd   <= fcs_reg[{fcs_index, rmii_pair, 1'b0} +: 2];
                if (rmii_pair == 2'd3) begin
                    rmii_pair <= 2'd0;
                    if (fcs_index == 2'd3) begin
                        ifg_count <= 6'd0;
                        state <= STATE_IFG;
                    end
                    else fcs_index <= fcs_index + 1'b1;
                end
                else rmii_pair <= rmii_pair + 1'b1;
            end

            STATE_IFG: begin
                eth_tx_en <= 1'b0;
                eth_txd   <= 2'b00;
                busy      <= 1'b0;
                if (ifg_count == 6'd47) begin
                    ifg_count <= 6'd0;
                    state <= STATE_IDLE;
                end
                else ifg_count <= ifg_count + 1'b1;
            end

            default: begin
                state <= STATE_IDLE;
                eth_tx_en <= 1'b0;
                eth_txd <= 2'b00;
                busy <= 1'b0;
            end
            endcase
        end
    end
endmodule