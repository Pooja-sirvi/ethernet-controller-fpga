`timescale 1ns / 1ps

module top #(
    // PHY reset length in 125 MHz clocks (65535 = about 0.5 ms). Testbench makes it shorter.
    parameter [15:0] PHY_RST_MAX = 16'hFFFF,
    // Time between packets in 125 MHz clocks (12_500_000 = 100 ms). Testbench makes it shorter.
    parameter [23:0] TX_PERIOD   = 24'd12_500_000
)(
    input  wire       CLK100MHZ,
    input  wire       BTNC,
    output wire [7:0] LED,

    output wire       ETH_TXEN,
    output wire [1:0] ETH_TXD,
    output wire       ETH_REFCLK,
    output wire       ETH_RSTN
);

    // ============================================================
    // ALL WIRES DECLARED FIRST (fix: nothing is used before it is declared)
    // ============================================================
    wire        clk_125, clk_50, clk_out3, clk_locked;

    wire [7:0]  bram_addr;
    wire        bram_en;
    wire [31:0] bram_rdata;

    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    wire        m_axis_tready;

    wire        busy;
    wire        done;

    wire [32:0] fifo_din;
    wire [32:0] fifo_dout;
    wire        fifo_wr_en;
    wire        fifo_rd_en;
    wire        fifo_full;
    wire        fifo_empty;
    wire        fifo_wr_rst_busy;
    wire        fifo_rd_rst_busy;

    wire        mac_busy;
    wire [3:0]  mac_debug_state;

    // ============================================================
    // CLOCKS
    // ============================================================
    clk_wiz_0 clk_gen (
        .clk_in1  (CLK100MHZ),
        .reset    (1'b0),
        .clk_out1 (clk_125),
        .clk_out2 (clk_50),
        .clk_out3 (clk_out3),
        .locked   (clk_locked)
    );

    assign ETH_REFCLK = clk_out3;

    // ============================================================
    // RESETS (fix: held ON at power-up and until the clock is locked)
    // ============================================================
    wire rst_async = BTNC | ~clk_locked;

    reg [1:0] reset_sync_125 = 2'b11;
    always @(posedge clk_125 or posedge rst_async) begin
        if (rst_async) reset_sync_125 <= 2'b11;
        else           reset_sync_125 <= {reset_sync_125[0], 1'b0};
    end
    wire reset_125 = reset_sync_125[1];

    reg [1:0] reset_sync_50 = 2'b11;
    always @(posedge clk_50 or posedge rst_async) begin
        if (rst_async) reset_sync_50 <= 2'b11;
        else           reset_sync_50 <= {reset_sync_50[0], 1'b0};
    end
    wire reset_50 = reset_sync_50[1];

    // ============================================================
    // PHY RESET (ETH_RSTN is active LOW)
    // ============================================================
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
        else begin
            phy_reset_n       <= 1'b1;
        end
    end

    assign ETH_RSTN = phy_reset_n;

    // ============================================================
    // START DMA - one clean 1-clock pulse, repeated every TX_PERIOD
    // (fix: the real PHY needs time to wake up, so one frame is not enough)
    // ============================================================
    reg [23:0] tx_timer;
    reg        start;

    always @(posedge clk_125) begin
        start <= 1'b0;
        if (reset_125 || !phy_reset_n) begin
            tx_timer <= 24'd0;
        end
        else if (tx_timer == TX_PERIOD - 1) begin
            tx_timer <= 24'd0;
            if (!busy && !fifo_wr_rst_busy)
                start <= 1'b1;
        end
        else begin
            tx_timer <= tx_timer + 1'b1;
        end
    end

    // ============================================================
    // TX BRAM
    // ============================================================
    tx_bram tx_bram_inst (
        .clka  (clk_125),
        .ena   (bram_en),
        .wea   (1'b0),
        .addra (bram_addr),
        .dina  (32'b0),
        .douta (bram_rdata)
    );

    // ============================================================
    // FIFO connections
    // ============================================================
    assign fifo_din      = {m_axis_tlast, m_axis_tdata};
    assign fifo_wr_en    = m_axis_tvalid && m_axis_tready;
    assign m_axis_tready = !fifo_full && !fifo_wr_rst_busy;

    fifo_generator_0 tx_fifo_inst (
        .rst          (reset_125),
        .wr_clk       (clk_125),
        .rd_clk       (clk_50),
        .din          (fifo_din),
        .wr_en        (fifo_wr_en),
        .rd_en        (fifo_rd_en),
        .dout         (fifo_dout),
        .full         (fifo_full),
        .empty        (fifo_empty),
        .wr_rst_busy  (fifo_wr_rst_busy),
        .rd_rst_busy  (fifo_rd_rst_busy)
    );

    // ============================================================
    // CUSTOM TX MAC (50 MHz)
    // ============================================================
    tx_mac tx_mac_inst (
        .clk_50       (clk_50),
        .reset        (reset_50),
        .fifo_dout    (fifo_dout),
        .fifo_empty   (fifo_empty),
        .fifo_rd_en   (fifo_rd_en),
        .eth_tx_en    (ETH_TXEN),
        .eth_txd      (ETH_TXD),
        .busy         (mac_busy),
        .debug_state  (mac_debug_state)
    );

    // ============================================================
    // LED - low byte of the last word written into the FIFO
    // ============================================================
    reg [7:0] led_reg;
    always @(posedge clk_125) begin
        if (reset_125)
            led_reg <= 8'h00;
        else if (m_axis_tvalid && m_axis_tready)
            led_reg <= m_axis_tdata[7:0];
    end
    assign LED = led_reg;

    // ============================================================
    // TX DMA
    // ============================================================
    tx_dma #(
        .DATA_WIDTH   (32),
        .ADDR_WIDTH   (8),
        .PACKET_WORDS (8)
    ) dma_inst (
        .clk           (clk_125),
        .reset         (reset_125),
        .start         (start),
        .bram_addr     (bram_addr),
        .bram_en       (bram_en),
        .bram_rdata    (bram_rdata),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast),
        .busy          (busy),
        .done          (done)
    );

    // ============================================================
    // ILA (unchanged)
    // ============================================================
    ila_0 ila_inst (
        .clk    (clk_50),
        .probe0 (ETH_TXEN),
        .probe1 (ETH_TXD),
        .probe2 (fifo_rd_en),
        .probe3 (mac_debug_state)
    );

endmodule