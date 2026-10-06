## 100 MHz Clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }]

## Center Push Button
set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 } [get_ports { BTNC }]

## LEDs
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { LED[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { LED[1] }]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { LED[2] }]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports { LED[3] }]
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports { LED[4] }]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports { LED[5] }]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports { LED[6] }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 } [get_ports { LED[7] }]
## Ethernet PHY - RMII TX

set_property -dict { PACKAGE_PIN B9 IOSTANDARD LVCMOS33 } [get_ports { ETH_TXEN }]

set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { ETH_TXD[0] }]

set_property -dict { PACKAGE_PIN A8 IOSTANDARD LVCMOS33 } [get_ports { ETH_TXD[1] }]
## Ethernet PHY - RMII Reference Clock

set_property -dict { PACKAGE_PIN D5 IOSTANDARD LVCMOS33 } [get_ports { ETH_REFCLK }]
create_clock -add -name eth_ref_clk -period 20.00 -waveform {0 10} [get_ports { ETH_REFCLK }]
## Ethernet PHY - Reset

set_property -dict { PACKAGE_PIN B3 IOSTANDARD LVCMOS33 } [get_ports { ETH_RSTN }]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { SW0 }];
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { ETH_CRSDV }];
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { ETH_RXERR }];
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { ETH_RXD[0] }];
set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { ETH_RXD[1] }];