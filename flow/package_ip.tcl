# Package ONE IP (from its flattened release file) as a Vivado IP.   Run from the project root, plain terminal:
#   python3 flow/flatten_ip.py aegis_dma
#   vivado -mode batch -source flow/package_ip.tcl -tclargs aegis_dma
# Result: ip/<ip>/release/component.xml (+ xgui) = the IP; add  ip/*/release  to the IP repository paths.
set ip   [lindex $argv 0]
set part [expr {[llength $argv] > 1 ? [lindex $argv 1] : "xc7a100tcsg324-1"}]
set fh [open ip/$ip/top.txt]; set top [string trim [read $fh]]; close $fh
set flatf [file normalize ip/$ip/release/${ip}_flat.sv]
if {![file exists $flatf]} { puts "ERROR: $flatf missing - run: python3 flow/flatten_ip.py $ip"; exit 1 }

create_project -force pkg_$ip build/pkg_$ip -part $part
add_files -norecurse $flatf
set_property file_type SystemVerilog [get_files $flatf]
set_property top $top [get_filesets sources_1]
update_compile_order -fileset sources_1

set root [file normalize ip/$ip/release]
ipx::package_project -root_dir $root -vendor aegis -library ip -taxonomy /AegisAI -import_files -force
set core [ipx::current_core]
set_property name         $ip   $core
set_property display_name $ip   $core
set_property description  "AegisAI-SoC IP: $ip (top module $top)" $core
set_property version      1.0   $core

# ---- helper: set / create a bus-interface parameter -------------------------------------------
proc set_bp {bif pname value} {
    set bp [ipx::get_bus_parameters $pname -of_objects $bif]
    if {[llength $bp] == 0} { set bp [ipx::add_bus_parameter $pname $bif] }
    set_property value $value $bp
}

# ---- protocol of every memory-mapped interface; collect clock-associated interfaces -------------
set busifs {}
foreach b [ipx::get_bus_interfaces -of_objects $core] {
    set n [get_property name $b]
    if {$n eq "clk" || $n eq "rst_n"} continue
    lappend busifs $n
    set btype ""
    catch { set btype [get_property bus_type_name $b] }
    if {[string match "*aximm*" $btype] || [string match "*axi*" $n]} {
        if {[string match "*axil*" $n]} { catch { set_bp $b PROTOCOL AXI4LITE } }
    }
}
set clkif [ipx::get_bus_interfaces clk -of_objects $core]
if {[llength $clkif] > 0} {
    if {[llength $busifs] > 0} { set_bp $clkif ASSOCIATED_BUSIF [join $busifs ":"] }
    set_bp $clkif ASSOCIATED_RESET rst_n
}
set rstif [ipx::get_bus_interfaces rst_n -of_objects $core]
if {[llength $rstif] > 0} { set_bp $rstif POLARITY ACTIVE_LOW }

ipx::create_xgui_files $core
ipx::update_checksums  $core
ipx::check_integrity   $core
ipx::save_core         $core

puts "================ PACKAGED: aegis:ip:$ip:1.0  (top $top)"
foreach b [ipx::get_bus_interfaces -of_objects $core] {
    puts "  interface: [get_property name $b]  mode=[get_property interface_mode $b]"
}
puts "  output: $root/component.xml"
close_project
