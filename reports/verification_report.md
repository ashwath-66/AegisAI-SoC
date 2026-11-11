# AegisAI-SoC – Simulation Verification Report (Phase 1)

Date: 7 Nov 2026  |  Simulator: Verilator 5.055 (OSS CAD Suite)  |  Result: **ALL TESTBENCHES PASS**

## 1. Summary

| # | Testbench | Scope | Result |
|---|-----------|-------|--------|
| 1 | tb_pe | PE: plain MAC vs clock-enable vs latch-ICG gating, 14,006 cycles | PASS |
| 2 | tb_speck | Speck-64/128 decryptor | PASS |
| 3 | tb_gemm (CLK_GATE=0) | 16x16 systolic array, 304 rows | PASS, 0 errors |
| 4 | tb_gemm (CLK_GATE=1, latch ICG) | same, gated build | PASS, 0 errors |
| 5 | tb_qspi | QSPI engine + FIFO + APB regs | PASS |
| 6 | tb_tcm | ping-pong TCM (AXI write, GEMM read) | PASS |
| 7 | tb_dma | AXI DMA with inline decrypt | PASS |
| 8 | tb_gemm_subsys | flash -> decrypt -> TCM -> GEMM, 7 scenarios | PASS |
| 9 | tb_aegisai_soc | full SoC, Ibex boots firmware | PASS, 0 / 1536 mismatches |

## 2. Results per block

**Innovation 3 – zero-sensing / clock-gated PE (tb_pe, tb_gemm)**
- Clock-enable PE and latch-ICG PE are bit-identical to a plain always-clocked PE on every cycle (zero-heavy random stimulus).
- Gate fired in 4,522 of 14,006 cycles (32.3 %) in the PE test; it never fired with a non-zero input.
- Array level: all 304 result rows correct in both CLK_GATE modes.
- Fraction of PE-cycles with the multiplier isolated (zero operand), as printed by tb_gemm:

| Scenario | rows checked | errors | PE idle |
|---|---|---|---|
| dense random | 64 | 0 | 37.1 % |
| sparse 50 % zeros | 128 | 0 | 83.0 % |
| dense, gapped stream (40 % idle) | 192 | 0 | 57.9 % |
| all -128 x -128 | 200 | 0 | 81.8 % |
| -128 x 127 | 208 | 0 | 81.8 % |
| very sparse 90 % zeros | 272 | 0 | 99.3 % |
| weight reload, mixed | 304 | 0 | 65.5 % |

  Note: "PE idle" counts multiplier isolation (skip), not clock-gated cycles. The per-PE gated count (`pe_gated`) exists but is not yet logged at array level.

**Innovation 1 – inline Speck-64 decryption (tb_speck, tb_dma)**
- Published Speck-64/128 test vector decrypts correctly; 200 random round-trips, stalled-output and key-reload cases: 0 errors.
- Throughput: 29 cycles per 128-bit beat (27 rounds + handshake) versus 32 cycles per beat delivered by QSPI, so decryption keeps up with the flash stream.
- DMA: 256 B tile decrypt+write in 2,175 cycles; unaligned destination split at 256 B boundary; bypass (decrypt off); 1 KB tile with AXI ready 30 %; invalid LEN (20) rejected with ERR and no AXI traffic; START while busy ignored; IRQ assert/clear; AXI protocol checks (WLAST, size, 4 KB, 256 B) clean.

**QSPI (tb_qspi)** – EBh 64 B/256 B (div 0,1,3), 6Bh 128 B, 512 B with slow consumer (15 % ready), back-to-back reads, FIFO back-pressure, CPU pop path (256 B), IRQ, PSLVERR on unmapped register: all pass.

**TCM (tb_tcm)** – 150 random write+readback bursts with partial strobes, narrow accesses, DECERR/SLVERR responses, 5,096 concurrent GEMM reads: 0 bad bytes, 0 AXI errors.

**Innovation 2 – CPU-bypassed handshake (tb_gemm_subsys, tb_dma)** – DMA auto-prefetch ping-pong A/B/A/B and GEMM controller bank handshake verified:

| Scenario | tiles x rows | cycles | result |
|---|---|---|---|
| dense, drain prefetch | 4 x 16 | 18,416 | ok |
| sparse 50 % | 4 x 40 | 32,716 | ok |
| early prefetch | 5 x 32 | 33,969 | ok |
| slow CPU ack (result-buffer back-pressure) | 4 x 24 | 26,181 | ok |
| max rows 64 | 2 x 64 | 26,080 | ok |
| single tile, 1 row | 1 x 1 | 2,437 | ok |
| ROWS=0 flagged ERR, controller stays idle | – | – | ok |

**Full SoC (tb_aegisai_soc)** – Ibex boots from ROM, prints banner, validates flash header, DMA streams 4 encrypted tiles through Speck into the TCM, GEMM computes, CPU copies results to SRAM: firmware finished after 82,627 cycles; 1,536 result words compared against the software model, 0 mismatches; no Ibex alerts.

## 3. Defects found and fixed during this phase
1. gemm_controller.sv was a stale placeholder: replaced with the full controller.
2. Dead/duplicate RTL files removed; missing Ibex prim modules added.
3. PE rewritten with real zero-sensing and clock gating (CLK_GATE parameter).
4. DMA: START ignored while an auto tile is pending.
5. Testbench bugs (not RTL): tb_dma and tb_aegisai_soc used variable initialisers inside a static block (evaluated once at time 0); tb_pe directed check sampled one cycle late.

## 4. Known limits / open items
- Decryptor is iterative (not 1 beat/cycle); it is rate-matched to QSPI, not faster.
- Clock-gated cycle percentage is measured at PE level only; array-level gated % not logged yet.
- Do not write the DMA TILES register while AUTO is running.
- Not yet done: synthesis, implementation, timing, power, gate-level simulation.
