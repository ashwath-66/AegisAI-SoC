// AegisAI-SoC boot firmware (runs from ROM on the Ibex core)
//
//  1. read a 16-byte plaintext header from QSPI flash through the CPU polling path
//  2. program the SPECK key into the DMA
//  3. start the DMA; the GEMM controller then auto-prefetches the following tiles
//  4. for every tile: wait for GEMM, copy the result matrix to SRAM, release the buffer
//  5. report PASS/FAIL through the system registers
typedef unsigned int u32;
#define R(a) (*(volatile u32 *)(a))

#define DMA   0x40000000u
#define SPI   0x40001000u
#define GEMM  0x40010000u
#define SYS   0x40020000u
#define TCM_A 0x10000000u
#define TCM_B 0x10002000u
#define RES   0x20000000u          // result copies in CPU SRAM
#define RES_MAX 0x3000u            // 12 KB, stack lives above

#define HDR_MAGIC 0xAE615A15u

static void putc_(char c) { R(SYS + 0x04) = (u32)c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }
static void finish(u32 code) { R(SYS + 0x10) = code; for (;;) { } }
static void fail(const char *m) { puts_(m); puts_("\nFAIL\n"); finish(2); }

int main(void) {
    puts_("AegisAI boot\n");

    // ---- 1. header from flash via the QSPI CSR polling path --------------------
    R(SPI + 0x10) = 2;                         // clear DONE
    R(SPI + 0x08) = 0;                         // flash address 0
    R(SPI + 0x0C) = 16;                        // 16 bytes = 1 beat
    R(SPI + 0x00) = 1;                         // START
    while (!(R(SPI + 0x10) & 2)) { }           // DONE
    while (R(SPI + 0x10) & 1) { }              // BUSY (CS gap) over
    while (R(SPI + 0x10) & 4) { }              // RX FIFO not empty
    u32 magic  = R(SPI + 0x20);
    u32 ntiles = R(SPI + 0x24);
    u32 rows   = R(SPI + 0x28);
    u32 base   = R(SPI + 0x2C);
    R(SPI + 0x30) = 1;                         // pop
    R(SPI + 0x10) = 2;

    if (magic != HDR_MAGIC)                    fail("bad magic");
    if (ntiles == 0 || ntiles > 6)             fail("bad tile count");
    if (rows == 0 || rows > 64)                fail("bad rows");
    if (ntiles * rows * 64u > RES_MAX)         fail("results do not fit");
    puts_("header ok\n");

    u32 len = 256u + 16u * rows;

    // ---- 2. SPECK key into the DMA ------------------------------------------------
    R(DMA + 0x20) = 0x03020100u;
    R(DMA + 0x24) = 0x0b0a0908u;
    R(DMA + 0x28) = 0x13121110u;
    R(DMA + 0x2C) = 0x1b1a1918u;
    R(DMA + 0x30) = 1;                         // KEY_LOAD
    while (!(R(DMA + 0x04) & 8)) { }           // KEY_VALID

    // ---- 3. GEMM controller + DMA ---------------------------------------------------
    R(GEMM + 0x08) = rows;
    R(GEMM + 0x00) = 0x9;                      // ENABLE | AUTO_PF_EN (prefetch at drain)
    R(DMA + 0x08) = base;                      // flash address of tile 0
    R(DMA + 0x0C) = len;
    R(DMA + 0x10) = TCM_A;
    R(DMA + 0x14) = TCM_B;
    R(DMA + 0x18) = len;                       // stride between tiles
    R(DMA + 0x1C) = ntiles - 1u;               // auto tiles after the first
    R(DMA + 0x00) = 0x7;                       // START | AUTO_EN | DECRYPT_EN

    // ---- 4. consume the tiles ---------------------------------------------------------
    u32 csum = 0;
    for (u32 t = 0; t < ntiles; t++) {
        while (!(R(GEMM + 0x04) & 2)) { }      // TILE_DONE
        volatile u32 *src = (volatile u32 *)(GEMM + 0x1000u);
        volatile u32 *dst = (volatile u32 *)(RES + t * rows * 64u);
        for (u32 i = 0; i < rows * 16u; i++) {
            u32 v = src[i];
            dst[i] = v;
            csum += v;
        }
        if (R(GEMM + 0x04) & 0x18) fail("gemm error");
        R(GEMM + 0x04) = 2;                    // clear TILE_DONE
        R(GEMM + 0x10) = 1;                    // release result buffer
    }
    if (R(DMA + 0x04) & 4) fail("dma error");

    R(SYS + 0x08) = csum;
    puts_("tiles done\nPASS\n");
    finish(1);
    return 0;
}
