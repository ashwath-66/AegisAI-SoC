# Vivado timing constraint (100 MHz start point; tighten after first report)
create_clock -name clk -period 20.000 [get_ports clk]
set_false_path -from [get_ports rst_n]
