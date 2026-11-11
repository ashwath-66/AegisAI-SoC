#!/bin/bash
# Out-of-context synthesis of one IP, or all of them.
#   flow/synth_ip.sh aegis_dma        |        flow/synth_ip.sh all
# Run in a PLAIN terminal (NOT the OSS CAD one).  Each IP is its own small Vivado run.
cd "$(dirname "$0")/.."
PART=${PART:-xc7a100tcsg324-1}
mkdir -p reports
list=$1; [ "$1" = "all" ] && list=$(ls ip | grep -v aegis_common)
for ip in $list; do
  echo "######## $ip"
  vivado -mode batch -source flow/synth_ip.tcl -tclargs $ip $PART > reports/synth_$ip.log 2>&1
  tail -1 reports/synth_$ip.log
done
