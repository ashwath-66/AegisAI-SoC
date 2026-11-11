#!/bin/bash
# Full SoC integration test (Ibex boots soc/fw/boot.hex, DMA+Speck+TCM+GEMM end to end)
cd "$(dirname "$0")/.."
flow/run_tb.sh soc/tb/tb_aegisai_soc.f +FW=soc/fw/boot.hex
