# Create a Vivado PROJECT for one IP from its rtl.f (no manual "Add Sources", nothing can be missed).
#   vivado -mode batch -source flow/create_ip_project.tcl -tclargs aegis_cpu [part]
# then open  build/vivado_<ip>/<ip>.xpr  in the GUI.   (run from the project root)
#   add the word  flat  to use the flattened single-file release (for packaging):
#   vivado -mode batch -source flow/create_ip_project.tcl -tclargs aegis_cpu flat
set ip   [lindex $argv 0]
set flat [expr {[lsearch -exact $argv flat] >= 0}]
set part "xc7a100tcsg324-1"
if {[llength $argv] > 1 && [lindex $argv 1] ne "flat"} { set part [lindex $argv 1] }
source flow/read_list.tcl
set fh [open ip/$ip/top.txt]; set top [string trim [read $fh]]; close $fh
lassign [read_filelist [list ip/$ip/rtl.f]] srcs incs
if {$flat} {
    set srcs [list ip/$ip/release/${ip}_flat.sv]
    set incs {}
}

set pdir [expr {$flat ? "build/vivado_${ip}_flat" : "build/vivado_$ip"}]
create_project -force $ip $pdir -part $part
set abs {}
foreach s $srcs { lappend abs [file normalize $s] }
add_files -norecurse -fileset sources_1 $abs
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] *.sv]

set absinc {}
foreach i $incs { lappend absinc [file normalize $i] }
if {[llength $absinc] > 0} { set_property include_dirs $absinc [get_filesets sources_1] }
set_property verilog_define {AEGIS_FPGA} [get_filesets sources_1]
set_property top $top [get_filesets sources_1]

# this IP's own testbenches -> simulation sources
set tbs [glob -nocomplain ip/$ip/tb/*.sv]
if {[llength $tbs] > 0} {
    set abstb {}
    foreach t $tbs { lappend abstb [file normalize $t] }
    add_files -norecurse -fileset sim_1 $abstb
    set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
}
update_compile_order -fileset sources_1
puts "IP $ip : top = $top, [llength [get_files -of_objects [get_filesets sources_1]]] design files, [llength $incs] include dir(s)"
close_project
