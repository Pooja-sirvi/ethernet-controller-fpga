`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 09/01/2026 03:03:17 PM
// Design Name:
// Module Name: dma
// Project Name:
// Target Devices:
// Tool Versions:
// Description: BRAM to AXI4-Stream TX DMA
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////

module tx_dma #(
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 8,
    parameter PACKET_WORDS = 8
)(
    input  wire                     clk,
    input  wire                     reset,

    // ---------------------------------------------------------
    // Control
    // ---------------------------------------------------------
    input  wire                     start,

    // ---------------------------------------------------------
    // BRAM interface
    // ---------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]    bram_addr,
    output reg                      bram_en,
    input  wire [DATA_WIDTH-1:0]    bram_rdata,

    // ---------------------------------------------------------
    // AXI4-Stream output
    // ---------------------------------------------------------
    output reg  [DATA_WIDTH-1:0]    m_axis_tdata,
    output reg                      m_axis_tvalid,
    input  wire                     m_axis_tready,
    output reg                      m_axis_tlast,

    // ---------------------------------------------------------
    // Status
    // ---------------------------------------------------------
    output reg                      busy,
    output reg                      done
);

    // ---------------------------------------------------------
    // State machine
    // ---------------------------------------------------------
    localparam IDLE         = 3'd0;
    localparam READ_REQ     = 3'd1;
    localparam READ_WAIT    = 3'd2;
    localparam READ_CAPTURE = 3'd3;
    localparam SEND         = 3'd4;
    localparam DONE         = 3'd5;

    reg [2:0] state;

    // ---------------------------------------------------------
    // Number of the word currently being transmitted
    // ---------------------------------------------------------
    reg [ADDR_WIDTH-1:0] read_count;

    // ---------------------------------------------------------
    // Main sequential logic
    // ---------------------------------------------------------
    always @(posedge clk) begin

        if (reset) begin

            // State
            state <= IDLE;

            // BRAM
            bram_addr <= {ADDR_WIDTH{1'b0}};
            bram_en   <= 1'b0;

            // AXI Stream
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;

            // Counter
            read_count <= {ADDR_WIDTH{1'b0}};

            // Status
            busy <= 1'b0;
            done <= 1'b0;

        end

        else begin

            // done is a one-clock pulse
            done <= 1'b0;

            case (state)

                // =================================================
                // IDLE
                // =================================================
                IDLE: begin

                    busy          <= 1'b0;
                    bram_en       <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;

                    if (start) begin

                        busy       <= 1'b1;
                        read_count <= {ADDR_WIDTH{1'b0}};
                        bram_addr  <= {ADDR_WIDTH{1'b0}};

                        state <= READ_REQ;

                    end

                end


                // =================================================
                // READ REQUEST
                // =================================================
                READ_REQ: begin

                    busy    <= 1'b1;
                    bram_en <= 1'b1;

                    // Request data from current BRAM address
                    state <= READ_WAIT;

                end


                // =================================================
                // READ WAIT
                // =================================================
                READ_WAIT: begin

                    busy    <= 1'b1;
                    bram_en <= 1'b0;

                    // Wait one clock for synchronous BRAM
                    // to update bram_rdata
                    state <= READ_CAPTURE;

                end


                // =================================================
                // READ CAPTURE
                // =================================================
                READ_CAPTURE: begin

                    busy    <= 1'b1;
                    bram_en <= 1'b0;

                    // BRAM data is now valid
                    m_axis_tdata  <= bram_rdata;
                    m_axis_tvalid <= 1'b1;

                    // Last word of packet?
                    if (read_count == PACKET_WORDS - 1)
                        m_axis_tlast <= 1'b1;
                    else
                        m_axis_tlast <= 1'b0;

                    state <= SEND;

                end


                // =================================================
                // SEND
                // =================================================
                SEND: begin

                    busy <= 1'b1;

                    // AXI transfer occurs only when
                    // VALID = 1 and READY = 1
                    if (m_axis_tvalid && m_axis_tready) begin

                        m_axis_tvalid <= 1'b0;

                        // Last word transmitted
                        if (read_count == PACKET_WORDS - 1) begin

                            state <= DONE;

                        end

                        else begin

                            // Move to next BRAM word
                            read_count <= read_count + 1'b1;
                            bram_addr  <= bram_addr + 1'b1;

                            state <= READ_REQ;

                        end

                    end

                end


                // =================================================
                // DONE
                // =================================================
                DONE: begin

                    busy          <= 1'b0;
                    done          <= 1'b1;

                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;

                    state <= IDLE;

                end


                // =================================================
                // DEFAULT
                // =================================================
                default: begin

                    state <= IDLE;

                    busy          <= 1'b0;
                    bram_en       <= 1'b0;
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;

                end

            endcase

        end

    end

endmodule