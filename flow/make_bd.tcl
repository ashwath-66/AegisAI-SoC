# Build the AegisAI SoC block design from the packaged IPs.
#   vivado -mode batch -source flow/make_bd.tcl                (build + validate + wrapper)
#   vivado -mode batch -source flow/make_bd.tcl -tclargs synth (also run synthesis + utilization report)
# Run from the project root in a plain terminal.  Needs the 8 IPs packaged (flow/package_all.sh).
set part "xc7a100tcsg324-1"
create_project -force aegis_soc_bd build/bd_soc -part $part

set repos {}
foreach ip {aegis_cpu aegis_dma aegis_qspi aegis_tcm aegis_gemm aegis_rom aegis_sram aegis_sysregs} {
    lappend repos [file normalize ip/$ip/release]
}
set_property ip_repo_paths $repos [current_project]
update_ip_catalog -rebuild

create_bd_design aegis_soc

# ---------------- cells -------------------------------------------------------------------------
foreach ip {aegis_cpu aegis_dma aegis_qspi aegis_tcm aegis_gemm aegis_rom aegis_sram aegis_sysregs} {
    create_bd_cell -type ip -vlnv aegis:ip:$ip:1.0 ${ip}_0
}
set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 smartconnect_0]
set_property -dict [list CONFIG.NUM_SI 2 CONFIG.NUM_MI 6 CONFIG.NUM_CLKS 1] $sc
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_0

set c3 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_cat3]
set_property -dict [list CONFIG.NUM_PORTS 3] $c3
set c15 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 irq_cat15]
set_property -dict [list CONFIG.NUM_PORTS 4 CONFIG.IN0_WIDTH 1 CONFIG.IN1_WIDTH 1 CONFIG.IN2_WIDTH 1 CONFIG.IN3_WIDTH 12] $c15
set k0 [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 zero12]
set_property -dict [list CONFIG.CONST_WIDTH 12 CONFIG.CONST_VAL 0] $k0

# ---------------- clock / reset --------------------------------------------------------------------
create_bd_port -dir I -type clk -freq_hz 50000000 clk
create_bd_port -dir I -type rst rst_n
set_property CONFIG.POLARITY ACTIVE_LOW [get_bd_ports rst_n]
connect_bd_net [get_bd_ports clk]   [get_bd_pins rst_0/slowest_sync_clk]
connect_bd_net [get_bd_ports rst_n] [get_bd_pins rst_0/ext_reset_in]
foreach ip {aegis_cpu aegis_dma aegis_qspi aegis_tcm aegis_gemm aegis_rom aegis_sram aegis_sysregs} {
    connect_bd_net [get_bd_ports clk]               [get_bd_pins ${ip}_0/clk]
    connect_bd_net [get_bd_pins rst_0/peripheral_aresetn] [get_bd_pins ${ip}_0/rst_n]
}
connect_bd_net [get_bd_ports clk]               [get_bd_pins smartconnect_0/aclk]
connect_bd_net [get_bd_pins rst_0/peripheral_aresetn] [get_bd_pins smartconnect_0/aresetn]

# ---------------- AXI4-Lite fabric: CPU masters -> 6 slaves --------------------------------------------
connect_bd_intf_net [get_bd_intf_pins aegis_cpu_0/m_axil_i] [get_bd_intf_pins smartconnect_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins aegis_cpu_0/m_axil_d] [get_bd_intf_pins smartconnect_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] [get_bd_intf_pins aegis_rom_0/s]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M01_AXI] [get_bd_intf_pins aegis_sram_0/s]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M02_AXI] [get_bd_intf_pins aegis_dma_0/s_axil]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M03_AXI] [get_bd_intf_pins aegis_qspi_0/s_axil]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M04_AXI] [get_bd_intf_pins aegis_gemm_0/s_axil]
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M05_AXI] [get_bd_intf_pins aegis_sysregs_0/s]

# ---------------- data path: QSPI -> (stream) -> DMA -> (AXI4) -> TCM ----------------------------------
connect_bd_intf_net [get_bd_intf_pins aegis_qspi_0/m_axis] [get_bd_intf_pins aegis_dma_0/s_axis]
connect_bd_intf_net [get_bd_intf_pins aegis_dma_0/m_axi]   [get_bd_intf_pins aegis_tcm_0/s_axi]

# ---------------- sideband signals -------------------------------------------------------------------------
foreach {src dst} {
    aegis_dma_0/rd_start  aegis_qspi_0/rd_start
    aegis_dma_0/rd_addr   aegis_qspi_0/rd_addr
    aegis_dma_0/rd_len    aegis_qspi_0/rd_len
    aegis_qspi_0/rd_busy  aegis_dma_0/rd_busy
    aegis_dma_0/fill_done aegis_gemm_0/fill_done
    aegis_dma_0/fill_bank aegis_gemm_0/fill_bank
    aegis_gemm_0/dma_auto_prefetch aegis_dma_0/dma_auto_prefetch
    aegis_gemm_0/g_en     aegis_tcm_0/g_en
    aegis_gemm_0/g_bank   aegis_tcm_0/g_bank
    aegis_gemm_0/g_word   aegis_tcm_0/g_word
    aegis_tcm_0/g_rdata   aegis_gemm_0/g_rdata
} {
    connect_bd_net [get_bd_pins $src] [get_bd_pins $dst]
}

# ---------------- interrupts: {spi,dma,gemm} -> sysregs.irq_raw ; {12'b0,spi,dma,gemm} -> cpu.irq_fast ----------
connect_bd_net [get_bd_pins aegis_gemm_0/irq] [get_bd_pins irq_cat3/In0]
connect_bd_net [get_bd_pins aegis_dma_0/irq]  [get_bd_pins irq_cat3/In1]
connect_bd_net [get_bd_pins aegis_qspi_0/irq] [get_bd_pins irq_cat3/In2]
connect_bd_net [get_bd_pins irq_cat3/dout]    [get_bd_pins aegis_sysregs_0/irq_raw]
connect_bd_net [get_bd_pins aegis_gemm_0/irq] [get_bd_pins irq_cat15/In0]
connect_bd_net [get_bd_pins aegis_dma_0/irq]  [get_bd_pins irq_cat15/In1]
connect_bd_net [get_bd_pins aegis_qspi_0/irq] [get_bd_pins irq_cat15/In2]
connect_bd_net [get_bd_pins zero12/dout]      [get_bd_pins irq_cat15/In3]
connect_bd_net [get_bd_pins irq_cat15/dout]   [get_bd_pins aegis_cpu_0/irq_fast]

# ---------------- chip-level pins -----------------------------------------------------------------------------------
foreach {pin name} {
    aegis_qspi_0/qspi_sck qspi_sck   aegis_qspi_0/qspi_cs_n qspi_cs_n   aegis_qspi_0/qspi_io qspi_io
    aegis_sysregs_0/dbg_char_valid dbg_char_valid  aegis_sysregs_0/dbg_char dbg_char
    aegis_sysregs_0/dbg_done dbg_done  aegis_sysregs_0/dbg_pass dbg_pass
    aegis_cpu_0/cpu_sleep cpu_sleep    aegis_cpu_0/cpu_alert cpu_alert
} {
    make_bd_pins_external -name $name [get_bd_pins $pin]
}

# ---------------- address map (same as the RTL SoC) ----------------------------------------------------------------
# Explicit assignment (no auto-assign): every slave window gets its exact offset and size in BOTH CPU address spaces.
proc map_seg {space seg off rng} {
    if {[catch {assign_bd_address -offset $off -range $rng \
            -target_address_space [get_bd_addr_spaces $space] [get_bd_addr_segs $seg]} err]} {
        puts "WARNING: could not map $seg into $space at $off ($rng): $err"
    }
}
foreach space {aegis_cpu_0/m_axil_i aegis_cpu_0/m_axil_d} {
    map_seg $space aegis_rom_0/s/reg0          0x00000000 16K
    map_seg $space aegis_sram_0/s/reg0         0x20000000 16K
    map_seg $space aegis_dma_0/s_axil/reg0     0x40000000 4K
    map_seg $space aegis_qspi_0/s_axil/reg0    0x40001000 4K
    map_seg $space aegis_gemm_0/s_axil/reg0    0x40010000 8K
    map_seg $space aegis_sysregs_0/s/reg0      0x40020000 4K
}
map_seg aegis_dma_0/m_axi aegis_tcm_0/s_axi/reg0 0x10000000 16K

puts "================ ADDRESS MAP ================"
foreach space {aegis_cpu_0/m_axil_i aegis_cpu_0/m_axil_d aegis_dma_0/m_axi} {
    foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $space]] {
        puts [format "  %-24s %-36s offset %-12s range %s" $space [get_property NAME $seg] [get_property OFFSET $seg] [get_property RANGE $seg]]
    }
}

# ---------------- validate, save, wrapper ------------------------------------------------------------------------
set rc [catch {validate_bd_design} verr]
puts "validate_bd_design: [expr {$rc ? "FAILED: $verr" : "OK"}]"
save_bd_design
make_wrapper -files [get_files aegis_soc.bd] -top -import
set_property top aegis_soc_wrapper [current_fileset]
set f [open build/bd_soc/aegis_soc.xdc w]; puts $f "create_clock -name clk -period 20.000 \[get_ports clk\]"; close $f
add_files -fileset constrs_1 -norecurse build/bd_soc/aegis_soc.xdc
update_compile_order -fileset sources_1
puts "BLOCK DESIGN BUILT: build/bd_soc/aegis_soc_bd.xpr"

if {[lsearch -exact $argv synth] >= 0} {
    set_param general.maxThreads 2
    launch_runs synth_1 -jobs 2
    wait_on_run synth_1
    open_run synth_1
    file mkdir reports
    report_utilization -file reports/bd_soc_util.rpt
    report_utilization -hierarchical -file reports/bd_soc_util_hier.rpt
    report_timing_summary -file reports/bd_soc_timing.rpt
    puts "BD SYNTHESIS FINISHED"
}
