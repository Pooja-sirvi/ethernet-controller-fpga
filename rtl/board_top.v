`timescale 1ns / 1ps
// ============================================================
// board_top - ONE design for BOTH boards.
//
//   SW0 = 1 : this board TRANSMITS the packet every ~100 ms (Board 1)
//   SW0 = 0 : this board only RECEIVES (Board 2)
//
// The receive path is always running on both boards.
//
// LEDs:
//   LED0     RX BRAM matches the expected packet
//   LED1     RX BRAM does NOT match
//   LED2     a frame with a bad CRC was dropped (sticky)
//   LED3     PHY has shown carrier on CRS_DV (sticky)
//   LED7:4   number of good frames received (counts up, wraps at 15)
//
// ILA (same 4 probes as before, chosen by SW0):
//   SW0=1 : ETH_TXEN, ETH_TXD, fifo_rd_en, tx state
//   SW0=0 : ETH_CRSDV, ETH_RXD, frame_ok, rx state
// ============================================================
module board_top #(
    parameter [15:0] PHY_RST_MAX = 16'hFFFF,
    parameter [23:0] TX_PERIOD   = 24'd12_500_000
)(
    input  wire       CLK100MHZ,
    input  wire       BTNC,
    input  wire       SW0,
    output wire [7:0] LED,

    // RMII TX
    output wire       ETH_TXEN,
    output wire [1:0] ETH_TXD,
    // RMII RX
    input  wire       ETH_CRSDV,
    input  wire [1:0] ETH_RXD,
    input  wire       ETH_RXERR,
    // PHY clock / reset
    output wire       ETH_REFCLK,
    output wire       ETH_RSTN
);

    // ---------------- wires ----------------
    wire clk_125, clk_50, clk_out3, clk_locked;

    wire [7:0]  bram_addr;   wire bram_en;   wire [31:0] bram_rdata;
    wire [31:0] m_axis_tdata; wire m_axis_tvalid, m_axis_tlast, m_axis_tready;
    wire busy, done;

    wire [32:0] fifo_din, fifo_dout;
    wire fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
    wire fifo_wr_rst_busy, fifo_rd_rst_busy;

    wire mac_busy;
    wire [3:0] mac_debug_state;

    wire [32:0] rx_fifo_din, rx_fifo_dout;
    wire rx_fifo_wr_en, rx_fifo_rd_en, rx_fifo_full, rx_fifo_empty;
    wire rx_wr_busy, rx_rd_busy;
    wire frame_ok, frame_err, rx_busy;
    wire [3:0] rx_state;

    // ---------------- clocks ----------------
    clk_wiz_0 clk_gen (
        .clk_in1(CLK100MHZ), .reset(1'b0),
        .clk_out1(clk_125), .clk_out2(clk_50), .clk_out3(clk_out3),
        .locked(clk_locked)
    );
    assign ETH_REFCLK = clk_out3;

    // ---------------- resets ----------------
    wire rst_async = BTNC | ~clk_locked;

    reg [1:0] reset_sync_125 = 2'b11;
    always @(posedge clk_125 or posedge rst_async)
        if (rst_async) reset_sync_125 <= 2'b11;
        else           reset_sync_125 <= {reset_sync_125[0], 1'b0};
    wire reset_125 = reset_sync_125[1];

    reg [1:0] reset_sync_50 = 2'b11;
    always @(posedge clk_50 or posedge rst_async)
        if (rst_async) reset_sync_50 <= 2'b11;
        else           reset_sync_50 <= {reset_sync_50[0], 1'b0};
    wire reset_50 = reset_sync_50[1];

    // ---------------- PHY reset ----------------
    reg [15:0] phy_reset_counter;
    reg        phy_reset_n;
    always @(posedge clk_125) begin
        if (reset_125) begin
            phy_reset_counter <= 16'd0;
            phy_reset_n       <= 1'b0;
        end
        else if (phy_reset_counter != PHY_RST_MAX) begin
            phy_reset_counter <= phy_reset_counter + 1'b1;
            phy_reset_n       <= 1'b0;
        end
        else phy_reset_n <= 1'b1;
    end
    assign ETH_RSTN = phy_reset_n;

    // ============================================================
    // TX PATH (unchanged from top.v, start is gated by SW0)
    // ============================================================
    reg [23:0] tx_timer;
    reg        start;
    always @(posedge clk_125) begin
        start <= 1'b0;
        if (reset_125 || !phy_reset_n) tx_timer <= 24'd0;
        else if (tx_timer == TX_PERIOD - 1) begin
            tx_timer <= 24'd0;
            if (SW0 && !busy && !fifo_wr_rst_busy) start <= 1'b1;
        end
        else tx_timer <= tx_timer + 1'b1;
    end

    tx_bram tx_bram_inst (
        .clka(clk_125), .ena(bram_en), .wea(1'b0),
        .addra(bram_addr), .dina(32'b0), .douta(bram_rdata)
    );

    assign fifo_din      = {m_axis_tlast, m_axis_tdata};
    assign fifo_wr_en    = m_axis_tvalid && m_axis_tready;
    assign m_axis_tready = !fifo_full && !fifo_wr_rst_busy;

    fifo_generator_0 tx_fifo_inst (
        .rst(reset_125), .wr_clk(clk_125), .rd_clk(clk_50),
        .din(fifo_din), .wr_en(fifo_wr_en), .rd_en(fifo_rd_en),
        .dout(fifo_dout), .full(fifo_full), .empty(fifo_empty),
        .wr_rst_busy(fifo_wr_rst_busy), .rd_rst_busy(fifo_rd_rst_busy)
    );

    tx_mac tx_mac_inst (
        .clk_50(clk_50), .reset(reset_50),
        .fifo_dout(fifo_dout), .fifo_empty(fifo_empty), .fifo_rd_en(fifo_rd_en),
        .eth_tx_en(ETH_TXEN), .eth_txd(ETH_TXD),
        .busy(mac_busy), .debug_state(mac_debug_state)
    );

    tx_dma #(.DATA_WIDTH(32), .ADDR_WIDTH(8), .PACKET_WORDS(8)) dma_inst (
        .clk(clk_125), .reset(reset_125), .start(start),
        .bram_addr(bram_addr), .bram_en(bram_en), .bram_rdata(bram_rdata),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .busy(busy), .done(done)
    );

    // ============================================================
    // RX PATH: RMII -> rx_mac -> RX FIFO -> rx_dma -> RX BRAM -> checker
    // ============================================================
    rx_mac rx_mac_inst (
        .clk_50(clk_50), .reset(reset_50),
        .crs_dv(ETH_CRSDV), .rxd(ETH_RXD), .rx_er(ETH_RXERR),
        .fifo_din(rx_fifo_din), .fifo_wr_en(rx_fifo_wr_en),
        .fifo_full(rx_fifo_full | rx_wr_busy),
        .frame_ok(frame_ok), .frame_err(frame_err),
        .busy(rx_busy), .debug_state(rx_state)
    );

    fifo_generator_1 rx_fifo_inst (
        .rst(reset_125), .wr_clk(clk_50), .rd_clk(clk_125),
        .din(rx_fifo_din), .wr_en(rx_fifo_wr_en), .rd_en(rx_fifo_rd_en),
        .dout(rx_fifo_dout), .full(rx_fifo_full), .empty(rx_fifo_empty),
        .wr_rst_busy(rx_wr_busy), .rd_rst_busy(rx_rd_busy)
    );

    wire [7:0]  rb_addr;  wire rb_en, rb_we;  wire [31:0] rb_wdata;
    wire        rx_done, rx_dma_busy;
    wire [8:0]  rx_words;

    rx_dma #(.ADDR_WIDTH(8)) rx_dma_inst (
        .clk(clk_125), .reset(reset_125),
        .fifo_dout(rx_fifo_dout), .fifo_empty(rx_fifo_empty), .fifo_rd_en(rx_fifo_rd_en),
        .bram_addr(rb_addr), .bram_en(rb_en), .bram_we(rb_we), .bram_wdata(rb_wdata),
        .busy(rx_dma_busy), .done(rx_done), .word_count(rx_words)
    );

    wire [7:0]  chk_addr;
    wire [31:0] chk_data;
    wire        match_ok, match_bad;

    rx_bram #(.ADDR_WIDTH(8)) rx_bram_inst (
        .clk(clk_125), .ena(rb_en), .wea(rb_we), .addra(rb_addr), .dina(rb_wdata),
        .addrb(chk_addr), .doutb(chk_data)
    );

    rx_checker #(.ADDR_WIDTH(8)) rx_checker_inst (
        .clk(clk_125), .reset(reset_125), .start(rx_done),
        .rd_addr(chk_addr), .rd_data(chk_data),
        .match_ok(match_ok), .match_bad(match_bad)
    );

    // ============================================================
    // LEDs (50 MHz domain for the sticky flags and the frame counter)
    // ============================================================
    reg       err_seen = 1'b0, crs_seen = 1'b0;
    reg [3:0] good_cnt = 4'd0;
    always @(posedge clk_50) begin
        if (reset_50) begin
            err_seen <= 1'b0;
            crs_seen <= 1'b0;
            good_cnt <= 4'd0;
        end
        else begin
            if (frame_err)  err_seen <= 1'b1;
            if (ETH_CRSDV)  crs_seen <= 1'b1;
            if (frame_ok)   good_cnt <= good_cnt + 1'b1;
        end
    end
    assign LED = {good_cnt, crs_seen, err_seen, match_bad, match_ok};

    // ============================================================
    // ILA - same four probes as before, selected by SW0
    // ============================================================
    wire       dbg0 = SW0 ? ETH_TXEN      : ETH_CRSDV;
    wire [1:0] dbg1 = SW0 ? ETH_TXD       : ETH_RXD;
    wire       dbg2 = SW0 ? fifo_rd_en    : frame_ok;
    wire [3:0] dbg3 = SW0 ? mac_debug_state : rx_state;

    ila_0 ila_inst (
        .clk(clk_50),
        .probe0(dbg0), .probe1(dbg1), .probe2(dbg2), .probe3(dbg3)
    );

endmodule
