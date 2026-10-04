`timescale 1ns / 1ps
// ============================================================
// RX DMA (125 MHz): reads words from the RX FIFO and writes them
// into RX BRAM at addresses 0,1,2,... The address restarts at 0
// after the word with TLAST, so every frame overwrites the last one.
// Mirror image of tx_dma.
// ============================================================
module rx_dma #(
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  reset,

    // RX FIFO read side (standard mode: dout valid 2 clocks after rd_en is set)
    input  wire [32:0]           fifo_dout,
    input  wire                  fifo_empty,
    output reg                   fifo_rd_en,

    // RX BRAM write side
    output reg  [ADDR_WIDTH-1:0] bram_addr,
    output reg                   bram_en,
    output reg                   bram_we,
    output reg  [31:0]           bram_wdata,

    // status
    output reg                   busy,
    output reg                   done,        // 1-clock pulse at end of frame
    output reg  [ADDR_WIDTH:0]   word_count    // words stored in the last frame
);

    localparam IDLE    = 3'd0;
    localparam REQ     = 3'd1;
    localparam WAIT    = 3'd2;
    localparam CAPTURE = 3'd3;
    localparam WRITE   = 3'd4;

    reg [2:0] state;
    reg       last_q;
    reg [ADDR_WIDTH-1:0] wr_addr;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            fifo_rd_en <= 1'b0;
            bram_addr <= 0;
            bram_en <= 1'b0;
            bram_we <= 1'b0;
            bram_wdata <= 32'd0;
            busy <= 1'b0;
            done <= 1'b0;
            word_count <= 0;
            last_q <= 1'b0;
            wr_addr <= 0;
        end
        else begin
            fifo_rd_en <= 1'b0;
            done       <= 1'b0;

            case (state)
            IDLE: begin
                busy    <= 1'b0;
                bram_en <= 1'b0;
                bram_we <= 1'b0;
                if (!fifo_empty) begin
                    busy  <= 1'b1;
                    state <= REQ;
                end
            end

            REQ: begin                       // only ask when the FIFO has data
                if (!fifo_empty) begin
                    fifo_rd_en <= 1'b1;
                    state <= WAIT;
                end
            end

            WAIT:  state <= CAPTURE;         // FIFO samples rd_en at the end of this clock

            CAPTURE: begin                   // dout is valid now
                bram_addr  <= wr_addr;
                bram_wdata <= fifo_dout[31:0];
                bram_en    <= 1'b1;
                bram_we    <= 1'b1;
                last_q     <= fifo_dout[32];
                state      <= WRITE;
            end

            WRITE: begin
                bram_en <= 1'b0;
                bram_we <= 1'b0;
                if (last_q) begin
                    word_count <= wr_addr + 1'b1;
                    wr_addr    <= 0;
                    done       <= 1'b1;
                    state      <= IDLE;
                end
                else begin
                    wr_addr <= wr_addr + 1'b1;
                    state   <= REQ;
                end
            end

            default: state <= IDLE;
            endcase
        end
    end
endmodule


// ============================================================
// RX BRAM - plain Verilog memory (Vivado turns it into block RAM).
// No IP and no COE needed. Port A writes (from rx_dma), port B reads
// (for ILA / LEDs / testbench).
// ============================================================
module rx_bram #(
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  ena,
    input  wire                  wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [31:0]           dina,

    input  wire [ADDR_WIDTH-1:0] addrb,
    output reg  [31:0]           doutb
);
    reg [31:0] mem [0:(1<<ADDR_WIDTH)-1];

    integer k;
    initial for (k = 0; k < (1<<ADDR_WIDTH); k = k + 1) mem[k] = 32'd0;

    always @(posedge clk) begin
        if (ena && wea) mem[addra] <= dina;
        doutb <= mem[addrb];
    end
endmodule
