# 400G Ethernet Controller Architecture - FPGA Prototype

Scaled-down prototype on Nexys A7-100T (Artix-7) with LAN8720A PHY over RMII.
Custom Verilog TX MAC; Vivado 2026.1.

## Status
- BRAM -> TX DMA -> async FIFO -> TX MAC: verified in simulation
  (self-checking testbench tb_top.v: valid 64-byte frame, correct CRC)
- Hardware test on board: pending
- RX path (RX MAC -> FIFO -> DMA -> BRAM): planned

## Architecture
BRAM -> TX DMA (125 MHz) -> async FIFO -> TX MAC (50 MHz) -> RMII -> LAN8720A