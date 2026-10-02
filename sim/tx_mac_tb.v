`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/15/2026 12:27:41 PM
// Design Name: 
// Module Name: tx_mac_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns / 1ps

module tx_mac_tb;

    // ============================================================
    // CLOCK AND RESET
    // ============================================================

    reg clk_50;
    reg reset;

    initial begin
        clk_50 = 1'b0;
        forever #10 clk_50 = ~clk_50;   // 50 MHz
    end


    // ============================================================
    // FIFO INTERFACE
    // ============================================================

    reg  [32:0] fifo_dout;
    reg         fifo_empty;
    wire        fifo_rd_en;

    // Test packet:
    // [32]   = TLAST
    // [31:0] = DATA

    reg [32:0] fifo_mem [0:7];

    integer fifo_ptr;


    // ============================================================
    // RMII OUTPUTS
    // ============================================================

    wire       eth_tx_en;
    wire [1:0] eth_txd;

    wire mac_busy;


    // ============================================================
    // DUT - YOUR ACTUAL TX MAC
    // ============================================================

    tx_mac dut (

        .clk_50       (clk_50),
        .reset        (reset),

        .fifo_dout    (fifo_dout),
        .fifo_empty   (fifo_empty),
        .fifo_rd_en   (fifo_rd_en),

        .eth_tx_en    (eth_tx_en),
        .eth_txd      (eth_txd),

        .busy         (mac_busy)
    );


    // ============================================================
    // INITIALIZATION
    // ============================================================

    initial begin

        // Same data used in our previous DMA test

        fifo_mem[0] = {1'b0, 32'h11111111};
        fifo_mem[1] = {1'b0, 32'h22222222};
        fifo_mem[2] = {1'b0, 32'h33333333};
        fifo_mem[3] = {1'b0, 32'h44444444};
        fifo_mem[4] = {1'b0, 32'h55555555};
        fifo_mem[5] = {1'b0, 32'h66666666};
        fifo_mem[6] = {1'b0, 32'h77777777};

        // Last word
        fifo_mem[7] = {1'b1, 32'h88888888};

        fifo_ptr   = 0;
        fifo_dout  = 33'd0;
        fifo_empty = 1'b0;

        reset = 1'b1;

        #100;

        reset = 1'b0;

        // Allow MAC to transmit
        #20000;

        $display("==============================================");
        $display("TX MAC TEST COMPLETED");
        $display("==============================================");

        $finish;
    end


    // ============================================================
    // SIMPLE FIFO MODEL
    //
    // MAC asserts fifo_rd_en.
    // One clock later the requested word appears on fifo_dout.
    // This matches the Standard FIFO latency used in our design.
    // ============================================================

    always @(negedge clk_50) begin

        if (reset) begin
            fifo_ptr  <= 0;
            fifo_dout <= 33'd0;
        end

        else begin

            if (fifo_rd_en) begin

                fifo_dout <= fifo_mem[fifo_ptr];

                if (fifo_ptr < 7) begin
    fifo_ptr <= fifo_ptr + 1;
end
else begin
    fifo_empty <= 1'b1;
end
            end

        end

    end


    // ============================================================
    // RMII BYTE DECODER
    //
    // RMII sends:
    //
    // cycle 0 -> bits [1:0]
    // cycle 1 -> bits [3:2]
    // cycle 2 -> bits [5:4]
    // cycle 3 -> bits [7:6]
    //
    // After 4 cycles we reconstruct one byte.
    // ============================================================

    reg [1:0] rmii_count;
    reg [7:0] reconstructed_byte;

    integer byte_count;

    always @(negedge clk_50) begin

        if (reset) begin
            rmii_count         <= 2'd0;
            reconstructed_byte <= 8'd0;
            byte_count         <= 0;
        end

        else begin

            if (eth_tx_en) begin

                case (rmii_count)

                    2'd0:
                        reconstructed_byte[1:0] <= eth_txd;

                    2'd1:
                        reconstructed_byte[3:2] <= eth_txd;

                    2'd2:
                        reconstructed_byte[5:4] <= eth_txd;

                    2'd3: begin

                        reconstructed_byte[7:6] <= eth_txd;

                        // Display complete byte
                        $display(
                            "MAC TX BYTE [%0d] = %02h",
                            byte_count,
                            {eth_txd,
                             reconstructed_byte[5:0]}
                        );

                        byte_count <= byte_count + 1;

                    end

                endcase


                if (rmii_count == 2'd3)
                    rmii_count <= 2'd0;
                else
                    rmii_count <= rmii_count + 1'b1;

            end

            else begin
                rmii_count <= 2'd0;
            end

        end

    end


    // ============================================================
    // OPTIONAL: DISPLAY TXEN ACTIVITY
    // ============================================================

    reg previous_tx_en;

    always @(negedge clk_50) begin

        if (reset) begin
            previous_tx_en <= 1'b0;
        end

        else begin

            if (eth_tx_en && !previous_tx_en)
                $display("---------- MAC TRANSMISSION START ----------");

            if (!eth_tx_en && previous_tx_en)
                $display("---------- MAC TRANSMISSION END ------------");

            previous_tx_en <= eth_tx_en;

        end

    end

endmodule
