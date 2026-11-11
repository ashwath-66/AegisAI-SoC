open_project build/bd_soc/aegis_soc_bd.xpr
set_param general.maxThreads 1
open_bd_design [get_files aegis_soc.bd]
foreach space [get_bd_addr_spaces] { foreach seg [get_bd_addr_segs -of_objects $space] { puts [format "MAP %-30s %-34s offset %s range %s" $space [get_property NAME $seg] [get_property OFFSET $seg] [get_property RANGE $seg]] } }
close_bd_design [current_bd_design]
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
open_run synth_1
file mkdir reports
report_utilization -file reports/bd_soc_util.rpt
report_utilization -hierarchical -file reports/bd_soc_util_hier.rpt
report_timing_summary -file reports/bd_soc_timing.rpt
puts "BD SYNTHESIS FINISHED"
