#!/bin/bash
# Run all testbenches of one IP:   flow/run_ip_tb.sh aegis_gemm
cd "$(dirname "$0")/.."
for f in ip/$1/tb/*.f; do flow/run_tb.sh "$f" || exit 1; done
