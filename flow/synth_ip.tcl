# Out-of-context synthesis of ONE IP.   vivado -mode batch -source flow/synth_ip.tcl -tclargs <ip_name> [part]
set ip   [lindex $argv 0]
set part [expr {[llength $argv] > 1 ? [lindex $argv 1] : "xc7a100tcsg324-1"}]
source flow/read_list.tcl
set fh [open ip/$ip/top.txt]; set top [string trim [read $fh]]; close $fh
lassign [read_filelist [list ip/$ip/rtl.f]] srcs incs
set_param general.maxThreads 2
read_verilog -sv $srcs
set xdc ip/$ip/synth/clk.xdc
set f [open $xdc w]; puts $f "create_clock -name clk -period 10.000 \[get_ports clk\]"; close $f
read_xdc -mode out_of_context $xdc
synth_design -top $top -part $part -mode out_of_context -include_dirs $incs \
    -verilog_define SYNTHESIS -verilog_define AEGIS_FPGA -flatten_hierarchy rebuilt
file mkdir reports/ip
report_utilization -file reports/ip/${ip}_util.rpt
report_timing_summary -file reports/ip/${ip}_timing.rpt
puts "IP SYNTHESIS FINISHED: $ip ($top)"
