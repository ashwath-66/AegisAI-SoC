#!/bin/bash
# Per-IP synthesis summary table from reports/ip/*.rpt and reports/synth_*.log
#   flow/summarize.sh            (run from anywhere)
cd "$(dirname "$0")/.."
printf "%-14s %-8s %8s %8s %6s %5s %6s %10s %10s\n" IP STATUS LUT FF BRAM36 DSP LATCH "WNS@10ns" "WHS"
for ip in aegis_cpu aegis_dma aegis_qspi aegis_tcm aegis_gemm aegis_fabric aegis_rom aegis_sram aegis_sysregs; do
  u=reports/ip/${ip}_util.rpt; t=reports/ip/${ip}_timing.rpt; l=reports/synth_${ip}.log
  if grep -q "IP SYNTHESIS FINISHED" $l 2>/dev/null && [ -f $u ]; then st=OK; else st=FAILED; fi
  if [ -f $u ]; then
    lut=$(awk -F'|' '/\| Slice LUTs/ {gsub(/ /,"",$3); print $3; exit}' $u)
    ff=$(awk -F'|' '/\| Slice Registers/ {gsub(/ /,"",$3); print $3; exit}' $u)
    br=$(awk -F'|' '/\| Block RAM Tile/ {gsub(/ /,"",$3); print $3; exit}' $u)
    dsp=$(awk -F'|' '/\| DSPs/ {gsub(/ /,"",$3); print $3; exit}' $u)
    lat=$(awk -F'|' '/Register as Latch/ {gsub(/ /,"",$3); print $3; exit}' $u)
  fi
  if [ -f $t ]; then
    row=$(grep -A6 "Design Timing Summary" $t | tail -1)
    wns=$(echo $row | awk '{print $1}'); whs=$(echo $row | awk '{print $5}')
  fi
  printf "%-14s %-8s %8s %8s %6s %5s %6s %10s %10s\n" $ip $st "${lut:--}" "${ff:--}" "${br:--}" "${dsp:--}" "${lat:--}" "${wns:--}" "${whs:--}"
  unset lut ff br dsp lat wns whs
done
echo; echo "Errors per log (should be 0):"
for l in reports/synth_*.log; do printf "  %-34s %s\n" $l "$(grep -c '^ERROR' $l)"; done
