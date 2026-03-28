# vyges-clkmgr-lite

Lightweight clock manager with native TL-UL slave interface. No OpenTitan RACL or lifecycle dependencies.

## Features

- Up to 4 configurable output clock domains
- Per-clock 8-bit integer divider (divide-by-1 to divide-by-256)
- Software-controlled clock gating via TL-UL registers
- Glitch-free clock gating (latch-based, gate transitions only when clock is low)
- Single-cycle TL-UL response
- ~200 lines of SystemVerilog

## Register Map

| Offset | Name       | Access | Description                                      |
|--------|------------|--------|--------------------------------------------------|
| 0x00   | CLK_EN     | RW     | Per-clock gate enable. Bit N enables clock N.     |
| 0x04   | CLK_STATUS | RO     | Per-clock active status.                          |
| 0x10   | CLK_DIV0   | RW     | Clock 0 divider. 0 = div1, 255 = div256.         |
| 0x14   | CLK_DIV1   | RW     | Clock 1 divider.                                  |
| 0x18   | CLK_DIV2   | RW     | Clock 2 divider.                                  |
| 0x1C   | CLK_DIV3   | RW     | Clock 3 divider.                                  |

## Parameters

| Parameter  | Default | Description                    |
|------------|---------|--------------------------------|
| NUM_CLOCKS | 4       | Number of output clock domains |

## soc-spec.yaml Usage

```yaml
clkmgr:
  ip: vyges-clkmgr-lite
  base_addr: 0x4008_0000
  parameters:
    NUM_CLOCKS: 4
  connections:
    tl_i: main_xbar.tl_clkmgr
    clk_o:
      - periph_clk
      - spi_clk
      - uart_clk
      - timer_clk
```

## License

Apache-2.0. Copyright 2026 Vyges Inc.
