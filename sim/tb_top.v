`timescale 1ns / 1ps
// Full-chain test: real top.v (BRAM -> DMA -> FIFO -> TX MAC).
// Captures the RMII output and checks TWO consecutive frames automatically.
module tb_top;

    reg  CLK100MHZ = 0;
    reg  BTNC      = 0;
    wire [7:0] LED;
    wire ETH_TXEN, ETH_REFCLK, ETH_RSTN;
    wire [1:0] ETH_TXD;

    always #5 CLK100MHZ = ~CLK100MHZ;          // 100 MHz

    // Short PHY reset and short gap between frames, only for simulation
    top #(.PHY_RST_MAX(16'd200), .TX_PERIOD(24'd6000)) dut (
        .CLK100MHZ(CLK100MHZ), .BTNC(BTNC), .LED(LED),
        .ETH_TXEN(ETH_TXEN), .ETH_TXD(ETH_TXD),
        .ETH_REFCLK(ETH_REFCLK), .ETH_RSTN(ETH_RSTN)
    );

    initial begin
        BTNC = 1; #200; BTNC = 0;
    end

    // ---- expected packet (must match your COE file) ----
    reg [31:0] words [0:7];
    initial begin
        words[0]=32'hFFFFFFFF; words[1]=32'hFFFF0011; words[2]=32'h22334455;
        words[3]=32'h88B5AABB; words[4]=32'hCCDDEEFF; words[5]=32'h01020304;
        words[6]=32'h05060708; words[7]=32'h090A0B0C;
    end

    function [7:0] exp_byte;
        input integer idx;
        reg [31:0] w;
        begin
            w = words[idx >> 2];
            exp_byte = w >> (24 - 8 * (idx & 3));
        end
    endfunction

    // ---- RMII capture + checks ----
    reg [7:0]  cap [0:255];
    reg [7:0]  b;
    reg [31:0] c;
    integer n = 0, dib = 0, cyc = 0, errors = 0, frames = 0, i, j;

    task fail;
        input [255:0] msg;
        begin errors = errors + 1; $display("FAIL: %0s", msg); end
    endtask

    always @(posedge dut.clk_50) begin
        if (ETH_TXEN) begin
            b[2*dib +: 2] = ETH_TXD;
            dib = dib + 1;
            cyc = cyc + 1;
            if (dib == 4) begin cap[n] = b; n = n + 1; dib = 0; end
        end
        else if (n > 0) begin
            frames = frames + 1;
            $display("--- frame %0d at %0t: TXEN=%0d cycles, %0d bytes", frames, $time, cyc, n);
            if (cyc != 288) fail("TXEN length != 288");
            if (n != 72)    fail("byte count != 72");
            for (i = 0; i < 7; i = i + 1) if (cap[i] !== 8'h55) fail("preamble");
            if (cap[7] !== 8'hD5) fail("SFD");
            for (i = 0; i < 32; i = i + 1)
                if (cap[8+i] !== exp_byte(i)) begin
                    fail("data byte mismatch");
                    $display("  byte %0d got %h expected %h", i, cap[8+i], exp_byte(i));
                end
            for (i = 40; i < 68; i = i + 1) if (cap[i] !== 8'h00) fail("padding");
            c = 32'hFFFFFFFF;                     // CRC over dest MAC .. FCS must give DEBB20E3
            for (i = 8; i < 72; i = i + 1)
                for (j = 0; j < 8; j = j + 1)
                    c = (c[0] ^ cap[i][j]) ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
            if (c !== 32'hDEBB20E3) fail("CRC residue wrong");
            $display("    FCS = %h %h %h %h", cap[68], cap[69], cap[70], cap[71]);
            n = 0; dib = 0; cyc = 0;
            if (frames == 2) begin
                if (errors == 0) $display("*** PASS: 2 valid frames from BRAM -> DMA -> FIFO -> MAC ***");
                else             $display("*** %0d FAILURES ***", errors);
                $finish;
            end
        end
    end

    initial begin
        #400000;
        $display("TIMEOUT: only %0d frame(s) seen. Check reset, start pulse and FIFO.", frames);
        $finish;
    end
endmodule