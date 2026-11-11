# Full-SoC synthesis.  vivado -mode batch -source flow/synth_soc.tcl   (project root, plain terminal)
set part xc7a100tcsg324-1
set_param general.maxThreads 2
source flow/read_list.tcl
set lists {}
foreach f [lsort [glob ip/*/rtl.f]] { lappend lists $f }
lappend lists soc/rtl.f
lassign [read_filelist $lists] srcs incs
read_verilog -sv $srcs
file copy -force soc/fw/boot.hex boot.hex
read_xdc flow/aegis.xdc
synth_design -top aegisai_top -part $part -include_dirs $incs \
    -verilog_define SYNTHESIS -verilog_define AEGIS_FPGA -flatten_hierarchy rebuilt
file mkdir reports
write_checkpoint -force reports/soc_post_synth.dcp
report_utilization -file reports/soc_util.rpt
report_utilization -hierarchical -file reports/soc_util_hier.rpt
report_timing_summary -file reports/soc_timing.rpt
puts "SYNTHESIS FINISHED"
