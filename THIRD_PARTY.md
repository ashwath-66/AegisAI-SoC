# Third-party components

## lowRISC Ibex (ip/aegis_cpu/rtl/ibex)
RISC-V RV32IMC core and `prim_*` support modules, https://github.com/lowRISC/ibex, licensed under **Apache License 2.0**
(SPDX identifiers are kept in every file header). Used with the configuration in `ip/aegis_cpu/rtl/aegis_cpu.sv`.

Changes made for this project (all marked in the source):
- `prim_generic_clock_gating.sv`: the clock gate is bypassed by default (FPGA / packaged IP); define `AEGIS_ASIC` to restore the latch-based gate.
- `ibex_if_stage.sv`: the two DPI-C exports used by Verilator C++ testbenches are limited to `VERILATOR` (Vivado xsim cannot compile them).
- Added small equivalents of `prim_generic_and2`, `prim_generic_clock_mux2`, `prim_sec_anchor_buf`, `prim_xilinx_clock_gating`.

## Speck-64/128
Block cipher published by the NSA (Beaulieu et al., 2013); implemented from the public specification and checked against the published test vector.

## AMD (Xilinx) IP
The block design uses AMD SmartConnect and Processor System Reset from the Vivado IP catalog; they are not distributed in this repository.
