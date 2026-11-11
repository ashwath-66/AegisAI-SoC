open_project build/bd_soc/aegis_soc_bd.xpr
set_param general.maxThreads 1
reset_run aegis_soc_aegis_cpu_0_0_synth_1
launch_runs aegis_soc_aegis_cpu_0_0_synth_1 -jobs 1
wait_on_run aegis_soc_aegis_cpu_0_0_synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
open_run synth_1
file mkdir reports
report_utilization -file reports/bd_soc_util.rpt
report_utilization -hierarchical -file reports/bd_soc_util_hier.rpt
report_timing_summary -file reports/bd_soc_timing.rpt
puts "BD SYNTHESIS FINISHED"
