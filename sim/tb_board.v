`timescale 1ns / 1ps
// board_top with SW0=1: its own TX output is wired to its own RX pins
// (a stand-in for the cable). Checks the LED outputs after a few frames.
module tb_board;

    reg  CLK100MHZ = 0;
    reg  BTNC      = 0;
    reg  SW0       = 1;
    wire [7:0] LED;
    wire ETH_TXEN, ETH_REFCLK, ETH_RSTN;
    wire [1:0] ETH_TXD;

    always #5 CLK100MHZ = ~CLK100MHZ;

    board_top #(.PHY_RST_MAX(16'd200), .TX_PERIOD(24'd6000)) dut (
        .CLK100MHZ(CLK100MHZ), .BTNC(BTNC), .SW0(SW0), .LED(LED),
        .ETH_TXEN(ETH_TXEN), .ETH_TXD(ETH_TXD),
        .ETH_CRSDV(ETH_TXEN), .ETH_RXD(ETH_TXD), .ETH_RXERR(1'b0),
        .ETH_REFCLK(ETH_REFCLK), .ETH_RSTN(ETH_RSTN)
    );

    initial begin BTNC = 1; #200; BTNC = 0; end

    initial begin
        wait (LED[7:4] >= 4'd3);
        #5000;
        $display("LED = %b   (LED0 match_ok=%b, LED1 match_bad=%b, LED2 err_seen=%b, LED3 crs_seen=%b, good frames=%0d)",
                 LED, LED[0], LED[1], LED[2], LED[3], LED[7:4]);
        if (LED[0] && !LED[1] && !LED[2] && LED[3])
            $display("*** PASS: board_top receives its own frames, RX BRAM matches ***");
        else
            $display("*** FAIL ***");
        $finish;
    end

    initial begin
        #800000;
        $display("TIMEOUT, LED = %b", LED);
        $finish;
    end
endmodule
