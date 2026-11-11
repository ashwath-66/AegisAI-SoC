#!/bin/bash
# Run ONE testbench:   flow/run_tb.sh <path/to/tb_name.f> [simulator plusargs]
# The .f file lists the TB, helper models and "@ip_name" = include that IP's rtl.f ("@all" = whole SoC).
# Needs Verilator >= 5.020.  GATE=1 builds with +define+GATE (latch-ICG PE variant).
set -e
cd "$(dirname "$0")/.."
F=$1; shift
TOP=$(basename "$F" .f)
mkdir -p build
: > build/$TOP.f
while IFS= read -r l; do
  case "$l" in
    "@all") for x in ip/*/rtl.f soc/rtl.f; do cat "$x"; done >> build/$TOP.f ;;
    "@"*)   cat "ip/${l#@}/rtl.f" >> build/$TOP.f ;;
    ""|"//"*) ;;
    *)      echo "$l" >> build/$TOP.f ;;
  esac
done < "$F"
awk '!seen[$0]++' build/$TOP.f > build/$TOP.uniq.f      # a shared file (e.g. axil_regif) is listed once
OPT="--binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTH -Wno-UNOPTFLAT --assert"
[ "$GATE" = "1" ] && OPT="$OPT -DGATE"
echo "=================== $TOP"
verilator $OPT --top-module $TOP -Mdir build/obj_$TOP -f build/$TOP.uniq.f > build/$TOP.log 2>&1 || { tail -30 build/$TOP.log; exit 1; }
./build/obj_$TOP/V$TOP "$@" | tail -${TAIL:-25}
