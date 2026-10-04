# 400G Ethernet Controller Architecture - FPGA Prototype

Scaled-down prototype on Nexys A7-100T (Artix-7) with LAN8720A PHY over RMII.
Custom Verilog TX MAC; Vivado 2026.1.

## Status
- - TX path: verified in simulation
- RX path (RX MAC -> FIFO -> DMA -> BRAM): verified in simulation
- Loopback test (tb_loopback.v): TX BRAM data == RX BRAM data, bad-CRC frame dropped
- Hardware test on boards: pending

## Architecture
BRAM -> TX DMA (125 MHz) -> async FIFO -> TX MAC (50 MHz) -> RMII -> LAN8720A