// Copyright 2026 Vyges Inc.
// SPDX-License-Identifier: Apache-2.0
//
// clkmgr_lite — Lightweight clock manager with TL-UL register interface
//
// Features:
//   - Up to NUM_CLOCKS output clock domains (default 4)
//   - Per-clock 8-bit integer divider (div-by-1 .. div-by-256)
//   - Per-clock software-controlled clock gating
//   - Glitch-free gating (enable synchronized on falling edge)
//   - Single-cycle TL-UL response

`ifndef CLKMGR_LITE_SV
`define CLKMGR_LITE_SV

module clkmgr_lite
  import tlul_pkg::*;
#(
  parameter int unsigned NUM_CLOCKS = 4
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  // TL-UL device port
  input  tlul_pkg::tl_h2d_t     tl_i,
  output tlul_pkg::tl_d2h_t     tl_o,

  // Clock outputs
  output logic [NUM_CLOCKS-1:0]  clk_o,
  output logic [NUM_CLOCKS-1:0]  clk_status_o
);

  // ---------------------------------------------------------------------------
  // Register address map
  // ---------------------------------------------------------------------------
  localparam logic [7:0] ADDR_CLK_EN     = 8'h00;
  localparam logic [7:0] ADDR_CLK_STATUS = 8'h04;
  localparam logic [7:0] ADDR_CLK_DIV0   = 8'h10;
  localparam logic [7:0] ADDR_CLK_DIV1   = 8'h14;
  localparam logic [7:0] ADDR_CLK_DIV2   = 8'h18;
  localparam logic [7:0] ADDR_CLK_DIV3   = 8'h1C;

  // ---------------------------------------------------------------------------
  // Registers
  // ---------------------------------------------------------------------------
  logic [NUM_CLOCKS-1:0] clk_en_q;
  logic [7:0]            clk_div_q [NUM_CLOCKS];

  // ---------------------------------------------------------------------------
  // TL-UL response — single-cycle
  // ---------------------------------------------------------------------------
  logic        tl_ack;
  logic [31:0] tl_rdata;
  logic        tl_err;

  assign tl_ack = tl_i.a_valid;

  // Address decode (use low byte for register select)
  logic [7:0] reg_addr;
  assign reg_addr = tl_i.a_address[7:0];

  // Write handling
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      clk_en_q <= {NUM_CLOCKS{1'b1}}; // all clocks enabled on reset
      for (int i = 0; i < NUM_CLOCKS; i++) begin
        clk_div_q[i] <= 8'h00; // div-by-1
      end
    end else if (tl_i.a_valid && (tl_i.a_opcode == PutFullData ||
                                   tl_i.a_opcode == PutPartialData)) begin
      case (reg_addr)
        ADDR_CLK_EN: clk_en_q <= tl_i.a_data[NUM_CLOCKS-1:0];
        ADDR_CLK_DIV0: if (NUM_CLOCKS > 0) clk_div_q[0] <= tl_i.a_data[7:0];
        ADDR_CLK_DIV1: if (NUM_CLOCKS > 1) clk_div_q[1] <= tl_i.a_data[7:0];
        ADDR_CLK_DIV2: if (NUM_CLOCKS > 2) clk_div_q[2] <= tl_i.a_data[7:0];
        ADDR_CLK_DIV3: if (NUM_CLOCKS > 3) clk_div_q[3] <= tl_i.a_data[7:0];
        default: ;
      endcase
    end
  end

  // Read handling (combinational)
  always_comb begin
    tl_rdata = 32'h0;
    tl_err   = 1'b0;
    if (tl_i.a_valid && tl_i.a_opcode == Get) begin
      case (reg_addr)
        ADDR_CLK_EN:     tl_rdata = {{(32-NUM_CLOCKS){1'b0}}, clk_en_q};
        ADDR_CLK_STATUS: tl_rdata = {{(32-NUM_CLOCKS){1'b0}}, clk_status_o};
        ADDR_CLK_DIV0:   tl_rdata = (NUM_CLOCKS > 0) ? {24'h0, clk_div_q[0]} : 32'h0;
        ADDR_CLK_DIV1:   tl_rdata = (NUM_CLOCKS > 1) ? {24'h0, clk_div_q[1]} : 32'h0;
        ADDR_CLK_DIV2:   tl_rdata = (NUM_CLOCKS > 2) ? {24'h0, clk_div_q[2]} : 32'h0;
        ADDR_CLK_DIV3:   tl_rdata = (NUM_CLOCKS > 3) ? {24'h0, clk_div_q[3]} : 32'h0;
        default:         tl_err   = 1'b1;
      endcase
    end
  end

  // TL-UL D-channel response
  assign tl_o = '{
    d_valid  : tl_ack,
    d_opcode : (tl_i.a_opcode == Get) ? AccessAckData : AccessAck,
    d_param  : '0,
    d_size   : tl_i.a_size,
    d_source : tl_i.a_source,
    d_sink   : '0,
    d_data   : tl_rdata,
    d_user   : '0,
    d_error  : tl_err,
    a_ready  : 1'b1
  };

  // ---------------------------------------------------------------------------
  // Clock dividers and glitch-free gating
  // ---------------------------------------------------------------------------
  logic [NUM_CLOCKS-1:0] div_clk;
  logic [NUM_CLOCKS-1:0] gate_en_sync;

  for (genvar g = 0; g < NUM_CLOCKS; g++) begin : gen_clk

    // --- Divider ---
    logic [7:0] cnt_q;
    logic       div_out_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        cnt_q     <= 8'h00;
        div_out_q <= 1'b0;
      end else begin
        if (clk_div_q[g] == 8'h00) begin
          // div-by-1: pass through
          div_out_q <= 1'b1; // held high; gating produces clk_i
          cnt_q     <= 8'h00;
        end else if (cnt_q >= clk_div_q[g]) begin
          cnt_q     <= 8'h00;
          div_out_q <= ~div_out_q;
        end else begin
          cnt_q <= cnt_q + 8'h01;
        end
      end
    end

    // Mux: div-by-1 passes clk_i directly; otherwise use toggle output
    assign div_clk[g] = (clk_div_q[g] == 8'h00) ? clk_i : div_out_q;

    // --- Glitch-free clock gate ---
    // Synchronise enable on the falling edge of the divided clock so the
    // AND-gate output never glitches.
    logic gate_latch;

    always_latch begin
      if (!div_clk[g]) begin
        gate_latch = clk_en_q[g];
      end
    end

    assign gate_en_sync[g] = gate_latch;
    assign clk_o[g]        = div_clk[g] & gate_en_sync[g];
  end

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------
  assign clk_status_o = gate_en_sync;

endmodule

`endif // CLKMGR_LITE_SV
