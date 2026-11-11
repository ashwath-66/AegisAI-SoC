# Simulate the Vivado block design (xsim) with the Ibex firmware.
#   vivado -mode batch -source flow/sim_bd.tcl 2>&1 | tee reports/sim_bd.log      (project root, plain terminal)
# Needs build/bd_soc (flow/make_bd.tcl). Prints the SoC test verdict; look for  [TB PASS] tb_bd_soc
set root [pwd]
open_project build/bd_soc/aegis_soc_bd.xpr
add_files -fileset sim_1 -norecurse [list [file normalize soc/tb/tb_bd_soc.sv] [file normalize ip/aegis_qspi/tb/flash_model.sv]]
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_bd_soc [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1
# the ROM IP reads boot.hex from the simulator working directory
set simdir [file normalize build/bd_soc/aegis_soc_bd.sim/sim_1/behav/xsim]
catch { launch_simulation -scripts_only }
file mkdir $simdir
file copy -force [file normalize soc/fw/boot.hex] $simdir/boot.hex
launch_simulation
puts "SIM_BD FINISHED"
close_project
