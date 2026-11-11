`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// aegis_cpu : CPU subsystem IP  (lowRISC Ibex RV32IMC + 2 OBI->AXI4-Lite shims)
//   Interfaces : clk/rst_n, irq_fast[14:0], two AXI4-Lite masters
//                  m_axil_i_*  instruction fetch (read-only, aw/w/b channels idle)
//                  m_axil_d_*  load/store
//   Status     : cpu_sleep, cpu_alert
//-----------------------------------------------------------------------------
module aegis_cpu (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [14:0]  irq_fast,
    output logic         cpu_sleep,
    output logic         cpu_alert,

    // AXI4-Lite master : instruction fetch
    output logic [31:0]  m_axil_i_awaddr,
    output logic         m_axil_i_awvalid,
    input  logic         m_axil_i_awready,
    output logic [31:0]  m_axil_i_wdata,
    output logic [3:0]   m_axil_i_wstrb,
    output logic         m_axil_i_wvalid,
    input  logic         m_axil_i_wready,
    input  logic [1:0]   m_axil_i_bresp,
    input  logic         m_axil_i_bvalid,
    output logic         m_axil_i_bready,
    output logic [31:0]  m_axil_i_araddr,
    output logic         m_axil_i_arvalid,
    input  logic         m_axil_i_arready,
    input  logic [31:0]  m_axil_i_rdata,
    input  logic [1:0]   m_axil_i_rresp,
    input  logic         m_axil_i_rvalid,
    output logic         m_axil_i_rready,
    // AXI4-Lite master : data load/store
    output logic [31:0]  m_axil_d_awaddr,
    output logic         m_axil_d_awvalid,
    input  logic         m_axil_d_awready,
    output logic [31:0]  m_axil_d_wdata,
    output logic [3:0]   m_axil_d_wstrb,
    output logic         m_axil_d_wvalid,
    input  logic         m_axil_d_wready,
    input  logic [1:0]   m_axil_d_bresp,
    input  logic         m_axil_d_bvalid,
    output logic         m_axil_d_bready,
    output logic [31:0]  m_axil_d_araddr,
    output logic         m_axil_d_arvalid,
    input  logic         m_axil_d_arready,
    input  logic [31:0]  m_axil_d_rdata,
    input  logic [1:0]   m_axil_d_rresp,
    input  logic         m_axil_d_rvalid,
    output logic         m_axil_d_rready
);
    logic        instr_req, instr_gnt, instr_rvalid, instr_err;
    logic [31:0] instr_addr, instr_rdata;
    logic        data_req, data_gnt, data_rvalid, data_we, data_err;
    logic [3:0]  data_be;
    logic [31:0] data_addr, data_wdata, data_rdata;
    logic        alert_minor, alert_major_int, alert_major_bus;

    ibex_top #(
        .PMPEnable(1'b0), .MHPMCounterNum(0), .RV32E(1'b0),
        .RV32M(ibex_pkg::RV32MFast), .RV32B(ibex_pkg::RV32BNone),
        .RegFile(ibex_pkg::RegFileFF), .BranchTargetALU(1'b0), .WritebackStage(1'b0),
        .ICache(1'b0), .ICacheECC(1'b0), .BranchPredictor(1'b0),
        .DbgTriggerEn(1'b0), .SecureIbex(1'b0)
    ) u_ibex (
        .clk_i(clk), .rst_ni(rst_n), .test_en_i(1'b0),
        .ram_cfg_i('0),
        .hart_id_i(32'h0), .boot_addr_i(32'h0000_0000),
        .instr_req_o(instr_req), .instr_gnt_i(instr_gnt), .instr_rvalid_i(instr_rvalid),
        .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata), .instr_rdata_intg_i(7'b0),
        .instr_err_i(instr_err),
        .data_req_o(data_req), .data_gnt_i(data_gnt), .data_rvalid_i(data_rvalid),
        .data_we_o(data_we), .data_be_o(data_be), .data_addr_o(data_addr),
        .data_wdata_o(data_wdata), .data_wdata_intg_o(),
        .data_rdata_i(data_rdata), .data_rdata_intg_i(7'b0), .data_err_i(data_err),
        .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(1'b0),
        .irq_fast_i(irq_fast), .irq_nm_i(1'b0),
        .scramble_key_valid_i(1'b0), .scramble_key_i('0), .scramble_nonce_i('0), .scramble_req_o(),
        .debug_req_i(1'b0), .crash_dump_o(), .double_fault_seen_o(),
        .fetch_enable_i(ibex_pkg::IbexMuBiOn),
        .alert_minor_o(alert_minor), .alert_major_internal_o(alert_major_int),
        .alert_major_bus_o(alert_major_bus), .core_sleep_o(cpu_sleep),
        .scan_rst_ni(1'b1)
    );
    assign cpu_alert = alert_minor | alert_major_int | alert_major_bus;

    obi_to_axil #(.READ_ONLY(1'b1)) u_ishim (
        .clk(clk), .rst_n(rst_n),
        .req(instr_req), .gnt(instr_gnt), .we(1'b0), .be(4'hF), .addr(instr_addr), .wdata(32'b0),
        .rvalid(instr_rvalid), .rdata(instr_rdata), .err(instr_err),
        .m_awaddr(m_axil_i_awaddr),
        .m_awvalid(m_axil_i_awvalid),
        .m_awready(m_axil_i_awready),
        .m_wdata(m_axil_i_wdata),
        .m_wstrb(m_axil_i_wstrb),
        .m_wvalid(m_axil_i_wvalid),
        .m_wready(m_axil_i_wready),
        .m_bresp(m_axil_i_bresp),
        .m_bvalid(m_axil_i_bvalid),
        .m_bready(m_axil_i_bready),
        .m_araddr(m_axil_i_araddr),
        .m_arvalid(m_axil_i_arvalid),
        .m_arready(m_axil_i_arready),
        .m_rdata(m_axil_i_rdata),
        .m_rresp(m_axil_i_rresp),
        .m_rvalid(m_axil_i_rvalid),
        .m_rready(m_axil_i_rready)
    );
    obi_to_axil #(.READ_ONLY(1'b0)) u_dshim (
        .clk(clk), .rst_n(rst_n),
        .req(data_req), .gnt(data_gnt), .we(data_we), .be(data_be), .addr(data_addr), .wdata(data_wdata),
        .rvalid(data_rvalid), .rdata(data_rdata), .err(data_err),
        .m_awaddr(m_axil_d_awaddr),
        .m_awvalid(m_axil_d_awvalid),
        .m_awready(m_axil_d_awready),
        .m_wdata(m_axil_d_wdata),
        .m_wstrb(m_axil_d_wstrb),
        .m_wvalid(m_axil_d_wvalid),
        .m_wready(m_axil_d_wready),
        .m_bresp(m_axil_d_bresp),
        .m_bvalid(m_axil_d_bvalid),
        .m_bready(m_axil_d_bready),
        .m_araddr(m_axil_d_araddr),
        .m_arvalid(m_axil_d_arvalid),
        .m_arready(m_axil_d_arready),
        .m_rdata(m_axil_d_rdata),
        .m_rresp(m_axil_d_rresp),
        .m_rvalid(m_axil_d_rvalid),
        .m_rready(m_axil_d_rready)
    );
endmodule
