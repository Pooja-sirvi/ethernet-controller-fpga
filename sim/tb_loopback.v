`timescale 1ns / 1ps
// ============================================================
// Loopback test, no board needed:
//   top (TX path) --RMII--> rx_mac -> RX FIFO -> rx_dma -> rx_bram
// Frames 1 and 2 are sent clean and must arrive in RX BRAM.
// Frame 3 gets one bit flipped on the "wire": the RX MAC must drop it
// (frame_err) and RX BRAM must stay unchanged.
// Needs a second FIFO IP named fifo_generator_1 (same settings as
// fifo_generator_0, see instructions).
// ============================================================
module tb_loopback;

    reg  CLK100MHZ = 0;
    reg  BTNC      = 0;
    wire [7:0] LED;
    wire ETH_TXEN, ETH_REFCLK, ETH_RSTN;
    wire [1:0] ETH_TXD;

    always #5 CLK100MHZ = ~CLK100MHZ;

    top #(.PHY_RST_MAX(16'd200), .TX_PERIOD(24'd6000)) dut (
        .CLK100MHZ(CLK100MHZ), .BTNC(BTNC), .LED(LED),
        .ETH_TXEN(ETH_TXEN), .ETH_TXD(ETH_TXD),
        .ETH_REFCLK(ETH_REFCLK), .ETH_RSTN(ETH_RSTN)
    );

    initial begin BTNC = 1; #200; BTNC = 0; end

    wire clk_50  = dut.clk_50;
    wire clk_125 = dut.clk_125;

    // ---------- wire between the two "boards" (+ one injected error) ----------
    integer txcyc = 0, txframe = 0;
    reg     txen_d = 0;
    always @(posedge clk_50) begin
        txen_d <= ETH_TXEN;
        if (ETH_TXEN) txcyc <= txcyc + 1;
        else          txcyc <= 0;
        if (txen_d && !ETH_TXEN) txframe <= txframe + 1;
    end
    wire flip   = ETH_TXEN && (txframe == 2) && (txcyc == 100);
    wire crs_dv = ETH_TXEN;
    wire [1:0] rxd = ETH_TXD ^ {1'b0, flip};

    // ---------- RX path ----------
    wire [32:0] rx_fifo_din, rx_fifo_dout;
    wire rx_fifo_wr_en, rx_fifo_rd_en, rx_fifo_full, rx_fifo_empty;
    wire rx_wr_busy, rx_rd_busy;
    wire frame_ok, frame_err, rx_busy;
    wire [3:0] rx_state;

    rx_mac rx_mac_inst (
        .clk_50(clk_50), .reset(dut.reset_50),
        .crs_dv(crs_dv), .rxd(rxd), .rx_er(1'b0),
        .fifo_din(rx_fifo_din), .fifo_wr_en(rx_fifo_wr_en),
        .fifo_full(rx_fifo_full | rx_wr_busy),
        .frame_ok(frame_ok), .frame_err(frame_err),
        .busy(rx_busy), .debug_state(rx_state)
    );

    fifo_generator_1 rx_fifo_inst (
        .rst(dut.reset_125),
        .wr_clk(clk_50), .rd_clk(clk_125),
        .din(rx_fifo_din), .wr_en(rx_fifo_wr_en),
        .rd_en(rx_fifo_rd_en), .dout(rx_fifo_dout),
        .full(rx_fifo_full), .empty(rx_fifo_empty),
        .wr_rst_busy(rx_wr_busy), .rd_rst_busy(rx_rd_busy)
    );

    wire [7:0]  rb_addr;
    wire        rb_en, rb_we;
    wire [31:0] rb_wdata;
    wire        dma_done, dma_busy;
    wire [8:0]  dma_words;

    rx_dma #(.ADDR_WIDTH(8)) rx_dma_inst (
        .clk(clk_125), .reset(dut.reset_125),
        .fifo_dout(rx_fifo_dout), .fifo_empty(rx_fifo_empty),
        .fifo_rd_en(rx_fifo_rd_en),
        .bram_addr(rb_addr), .bram_en(rb_en), .bram_we(rb_we), .bram_wdata(rb_wdata),
        .busy(dma_busy), .done(dma_done), .word_count(dma_words)
    );

    reg [7:0] dbg_addr = 0;
    wire [31:0] dbg_data;
    rx_bram #(.ADDR_WIDTH(8)) rx_bram_inst (
        .clk(clk_125), .ena(rb_en), .wea(rb_we), .addra(rb_addr), .dina(rb_wdata),
        .addrb(dbg_addr), .doutb(dbg_data)
    );

    // ---------- expected packet = tx_bram.coe ----------
    reg [31:0] words [0:7];
    initial begin
        words[0]=32'hFFFFFFFF; words[1]=32'hFFFF0011; words[2]=32'h22334455;
        words[3]=32'h88B5AABB; words[4]=32'hCCDDEEFF; words[5]=32'h01020304;
        words[6]=32'h05060708; words[7]=32'h090A0B0C;
    end

    integer ok_cnt = 0, err_cnt = 0, errors = 0, k;
    always @(posedge clk_50) begin
        if (frame_ok)  begin ok_cnt  = ok_cnt  + 1; $display("%0t: RX frame_ok  (#%0d)",  $time, ok_cnt);  end
        if (frame_err) begin err_cnt = err_cnt + 1; $display("%0t: RX frame_err (bad CRC frame dropped)", $time); end
    end

    // ---------- final check ----------
    initial begin
        wait (ok_cnt == 2 && err_cnt == 1);
        repeat (50) @(posedge clk_125);
        $display("RX DMA stored %0d words in the last good frame", dma_words);
        if (dma_words != 15) begin errors = errors + 1; $display("FAIL: expected 15 words"); end
        for (k = 0; k < 15; k = k + 1) begin
            dbg_addr = k; repeat (3) @(posedge clk_125);
            if (k < 8) begin
                if (dbg_data !== words[k]) begin errors = errors + 1;
                    $display("FAIL: RX BRAM[%0d]=%h expected %h", k, dbg_data, words[k]); end
            end
            else if (dbg_data !== 32'h0) begin errors = errors + 1;
                $display("FAIL: RX BRAM[%0d]=%h expected padding 0", k, dbg_data); end
        end
        for (k = 0; k < 8; k = k + 1) begin
            dbg_addr = k; repeat (3) @(posedge clk_125);
            $display("  TX word %0d = %h   RX BRAM[%0d] = %h", k, words[k], k, dbg_data);
        end
        if (errors == 0) $display("*** PASS: TX BRAM data == RX BRAM data, bad frame dropped ***");
        else             $display("*** %0d FAILURES ***", errors);
        $finish;
    end

    initial begin
        #600000;
        $display("TIMEOUT: ok=%0d err=%0d", ok_cnt, err_cnt);
        $finish;
    end
endmodule
