#!/bin/bash
# Flatten + package every packageable IP.  Plain terminal (Vivado). Logs: reports/pkg_<ip>.log
#   flow/package_all.sh            or      flow/package_all.sh aegis_tcm aegis_qspi
# aegis_fabric is NOT packaged: it has packed-array ports; use an AXI interconnect IP in the block design instead.
cd "$(dirname "$0")/.."
mkdir -p reports
list="$@"; [ -z "$list" ] && list="aegis_cpu aegis_tcm aegis_qspi aegis_dma aegis_gemm aegis_sram aegis_sysregs aegis_rom"
for ip in $list; do
  echo "######## $ip"
  python3 flow/flatten_ip.py $ip | head -1
  vivado -mode batch -source flow/package_ip.tcl -tclargs $ip > reports/pkg_$ip.log 2>&1
  grep -E "PACKAGED|interface:|ERROR" reports/pkg_$ip.log | head -12
done
