#!/bin/bash
# Every IP testbench, then the full-SoC integration test.
cd "$(dirname "$0")/.."
for d in ip/*/; do ip=$(basename $d); ls ip/$ip/tb/*.f >/dev/null 2>&1 && flow/run_ip_tb.sh $ip; done
flow/run_soc.sh
