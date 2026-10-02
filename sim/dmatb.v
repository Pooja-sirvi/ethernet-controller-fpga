`timescale 1ns/1ps

module tx_dma_tb;

// ------------------------------------------------
// Clock
// ------------------------------------------------

reg clk;

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// 10 ns period = 100 MHz


// ------------------------------------------------
// Reset and control
// ------------------------------------------------

reg reset;
reg start;


// ------------------------------------------------
// BRAM signals
// ------------------------------------------------

wire [7:0]  bram_addr;
wire        bram_en;
wire [31:0] bram_rdata;


// ------------------------------------------------
// AXI Stream
// ------------------------------------------------

wire [31:0] m_axis_tdata;
wire        m_axis_tvalid;
reg         m_axis_tready;
wire        m_axis_tlast;


// ------------------------------------------------
// Status
// ------------------------------------------------

wire busy;
wire done;


// ------------------------------------------------
// REAL TX BRAM
// ------------------------------------------------
// This is the actual Block Memory Generator IP.
// Its contents come from tx_bram.coe.
//
// Address 0 -> 11111111
// Address 1 -> 22222222
// ...
// Address 7 -> 88888888
// ------------------------------------------------

tx_bram tx_bram_inst (

    .clka(clk),
    .ena(bram_en),
    .wea(1'b0),
    .addra(bram_addr),
    .dina(32'b0),
    .douta(bram_rdata)

);


// ------------------------------------------------
// Instantiate TX DMA
// ------------------------------------------------

tx_dma uut (

    .clk(clk),
    .reset(reset),

    .start(start),

    .bram_addr(bram_addr),
    .bram_en(bram_en),
    .bram_rdata(bram_rdata),

    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),

    .busy(busy),
    .done(done)

);


// ------------------------------------------------
// Test
// ------------------------------------------------

initial begin

    // Initial conditions

    reset = 1;
    start = 0;
    m_axis_tready = 0;


    // Hold reset

    #30;

    reset = 0;


    // Wait a little

    #20;


    // Start DMA

    start = 1;

    #10;

    start = 0;


    // AXI receiver is ready

    m_axis_tready = 1;


    // Wait until DMA finishes

    wait(done);

    #20;

    $finish;

end


// ------------------------------------------------
// AXI STREAM TRANSFER MONITOR
// ------------------------------------------------

always @(posedge clk) begin

    if (m_axis_tvalid && m_axis_tready) begin

        $display(
            "AXI TRANSFER: time=%0t DATA=%h TLAST=%b",
            $time,
            m_axis_tdata,
            m_axis_tlast
        );

    end

end


// ------------------------------------------------
// Generate waveform
// ------------------------------------------------

initial begin

    $dumpfile("dump.vcd");
    $dumpvars(0, tx_dma_tb);

end

endmodule