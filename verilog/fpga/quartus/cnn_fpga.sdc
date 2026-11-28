# Provisional clock constraint: 50 MHz
# Update after confirming the physical board clock.

create_clock -name clk -period 20.000 [get_ports {clk}]
