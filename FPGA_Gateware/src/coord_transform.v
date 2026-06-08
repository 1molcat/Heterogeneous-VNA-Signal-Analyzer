`timescale 1ns / 1ps

// This module performs coordinate transformations and compensation using LUTs.
// It is fully pipelined for high throughput.
module coord_transform (
    input clk,
    input rst,

    // --- Control Signals ---
    input                            op_start, // Start a new operation
    
    // --- Input Data ---
    input      signed [15:0]         i_in,     // Rectangular I input
    input      signed [15:0]         q_in,     // Rectangular Q input
    input      signed [15:0]         i_filt,   // Filter I for compensation
    input      signed [15:0]         q_filt,   // Filter Q for compensation

    // --- Output Data ---
    output reg                       op_done_pulse,  // Pulse indicating output is valid
    output reg signed [15:0]         compensated_amp_out, // Final amplitude for DDS
    output reg signed [16:0]         compensated_phase_out // Final phase for DDS (17 bits for full range)
);

    //================================================================
    //== 1. LUT (ROM) Instantiation
    //================================================================
    wire [11:0] sqrt_addr;
    wire [15:0] sqrt_data;
    sqrt_lut u_sqrt_lut (.address(sqrt_addr), .clock(clk), .q(sqrt_data));

    wire [7:0] atan_addr;
    wire [15:0] atan_data;
    arctan_lut u_arctan_lut (.address(atan_addr), .clock(clk), .q(atan_data));
    
    //================================================================
    //== 2. Pipelined Divider (for ratio and magnitude division)
    //================================================================
    // A pipelined divider is essential. You can use an IP core from your FPGA vendor
    // or write a simple one. For now, we'll use the '/' operator, but assume
    // it's pipelined. Let's create a 32-bit by 16-bit divider.
    reg signed [47:0] div_dividend;
    reg signed [15:0] div_divisor;
    reg             div_start;
    wire signed [31:0] div_quotient;
    wire            div_done;

    // Placeholder for a real pipelined divider IP
    // For simulation, we can use a simple registered version.
    reg signed [31:0] div_quotient_reg;
    always @(posedge clk) begin
        if (div_start) begin
            if (div_divisor != 0)
                div_quotient_reg <= div_dividend / div_divisor;
            else
                div_quotient_reg <= 32'h7FFFFFFF; // Avoid division by zero, saturate
        end
    end
    assign div_quotient = div_quotient_reg;
    // In a real design, div_done would come from the IP. We'll simulate it.
    assign div_done = $past(div_start, 8); // Assume 8-cycle latency for divider


    //================================================================
    //== 3. Pipelined Rect_to_Polar Conversion
    //================================================================
    // This sub-module converts one (I,Q) pair to (Mag, Phase)
    
    // Pipeline Registers
    reg signed [15:0] p1_i_in, p1_q_in, p1_i_filt, p1_q_filt;
    
    // Stage 1: Absolute values and square
    reg signed [31:0] p2_i_in_sq, p2_q_in_sq;
    reg signed [31:0] p2_i_filt_sq, p2_q_filt_sq;
    reg signed [15:0] p2_abs_i_in, p2_abs_q_in;
    reg signed [15:0] p2_abs_i_filt, p2_abs_q_filt;
    reg               p2_q_in_sign, p2_i_in_sign;
    reg               p2_q_filt_sign, p2_i_filt_sign;

    // Stage 2: Sum of squares and divider setup for atan
    reg [31:0]        p3_mag_in_sq, p3_mag_filt_sq;
    
    // Stage 3 & 4: Wait for divider
    
    // Stage 5: Get divider result (ratio for atan)
    reg signed [15:0] p5_atan_ratio_in, p5_atan_ratio_filt;
    
    // Stage 6: Get sqrt result (magnitude) and atan_base
    reg [15:0]        p6_mag_in, p6_mag_filt;
    reg [15:0]        p6_atan_base_in, p6_atan_base_filt;
    
    // Stage 7: Quadrant correction for phase
    reg signed [16:0] p7_phase_in, p7_phase_filt;
    
    // Stage 8: Final compensation calculation (Mag division and Phase subtraction)
    // Stage 9-16: Wait for final division
    
    // Let's simplify and show the logic flow, assuming proper pipelining
    
    // --- Rect to Polar for INPUT signal ---
    wire signed [15:0] i_in_abs = i_in[15] ? -i_in : i_in;
    wire signed [15:0] q_in_abs = q_in[15] ? -q_in : q_in;
    wire signed [31:0] mag_in_sq = i_in * i_in + q_in * q_in;
    
    // --- Rect to Polar for FILTER signal ---
    wire signed [15:0] i_filt_abs = i_filt[15] ? -i_filt : i_filt;
    wire signed [15:0] q_filt_abs = q_filt[15] ? -q_filt : q_filt;
    wire signed [31:0] mag_filt_sq = i_filt * i_filt + q_filt * q_filt;

    // Use a helper module for the conversion to keep code clean
    wire [15:0] mag_in, mag_filt;
    wire signed [16:0] phase_in, phase_filt;

    rect_to_polar_converter r2p_input (
        .clk(clk), .rst(rst), .i(i_in), .q(q_in), .mag(mag_in), .phase(phase_in)
    );
    rect_to_polar_converter r2p_filter (
        .clk(clk), .rst(rst), .i(i_filt), .q(q_filt), .mag(mag_filt), .phase(phase_filt)
    );

    // --- Final Compensation ---
    // Mag_out = Mag_in / Mag_filt
    // We need to scale Mag_in to maintain precision before division
    reg [15:0] p_mag_in, p_mag_filt;
    reg signed [16:0] p_phase_in, p_phase_filt;
    reg p_op_start;

    always @(posedge clk) begin
        p_mag_in <= mag_in;
        p_mag_filt <= mag_filt;
        p_phase_in <= phase_in;
        p_phase_filt <= phase_filt;
        p_op_start <= op_start;
        if(p_op_start) begin
            div_dividend <= {p_mag_in, 16'd0}; // Scale up by 2^16 for precision
            div_divisor  <= p_mag_filt;
            div_start    <= 1'b1;
        end else begin
            div_start <= 1'b0;
        end
    end
    
    reg signed [16:0] p_phase_out;
    always @(posedge clk) begin
        p_phase_out <= p_phase_in - p_phase_filt;
    end
    
    // Final output stage
    always @(posedge clk) begin
        op_done_pulse <= 1'b0;
        if (div_done) begin
             // The result from divider has 16 fractional bits. We want the integer part.
            compensated_amp_out   <= div_quotient[31:16]; 
            compensated_phase_out <= p_phase_out;
            op_done_pulse         <= 1'b1;
        end
    end

endmodule


// Helper module for I,Q -> Mag,Phase
// =========================================================================
// ==  CORRECTED VERSION of the rect_to_polar_converter helper module
// =========================================================================
module rect_to_polar_converter (
    input clk,
    input rst,
    input signed [15:0] i,
    input signed [15:0] q,
    output reg [15:0] mag,
    output reg signed [16:0] phase
);
    // Use LUTs provided
    wire [11:0] sqrt_addr;
    wire [15:0] sqrt_data;
    sqrt_rom u_sqrt_rom (.address(sqrt_addr), .clock(clk), .q(sqrt_data));

    wire [7:0] atan_addr;
    wire [15:0] atan_data;
    arctan_rom u_arctan_rom (.address(atan_addr), .clock(clk), .q(atan_data));

    // Pipelined Divider (8-bit output for atan LUT)
    reg signed [23:0] p_div_dividend;
    reg signed [15:0] p_div_divisor;
    reg             p_div_start;
    wire [7:0]      p_div_quotient;
    // For an 8-cycle divider IP:
    // wire            p_div_done;
    // pipelined_divider_8bit u_divider_atan ( .clk(clk), .start(p_div_start), .dividend(p_div_dividend), .divisor(p_div_divisor), .quotient(p_div_quotient), .done(p_div_done));
    
    // Simple behavioral divider for simulation (assuming 5 cycles)
    reg [7:0] p_div_quotient_reg;
    always @(posedge clk) begin
        if(p_div_start) begin
            if (p_div_divisor != 0)
                p_div_quotient_reg <= p_div_dividend / p_div_divisor;
            else
                p_div_quotient_reg <= 8'hFF;
        end
    end
    assign p_div_quotient = $past(p_div_quotient_reg, 4); // Simulate 5-cycle total latency


    // Pipeline registers
    reg signed [15:0] p1_i, p1_q;
    reg signed [31:0] p2_mag_sq;
    reg               p2_i_sign, p2_q_sign;
    reg               p2_q_gt_i;
    reg [7:0]         p7_div_result;
    reg [15:0]        p7_atan_base;
    reg [15:0]        p7_mag;
    reg               p7_q_gt_i;
    reg               p7_i_sign, p7_q_sign;

    localparam PI_DIV_2 = 17'd16384; // 65536/4
    localparam PI       = 17'd32768; // 65536/2

    // ===================================
    // === FIX IS HERE ===================
    // Move the assignments OUT of the always block. They become continuous assignments.
    // ===================================
    assign sqrt_addr = p2_mag_sq[25:14];
    assign atan_addr = p7_div_result;

    always @(posedge clk) begin
        if (rst) begin
            mag <= 0;
            phase <= 0;
            p_div_start <= 0;
        end else begin
            // --- Stage 1 ---
            p1_i <= i;
            p1_q <= q;
            p_div_start <= 1'b1; // Always calculating for this helper

            // --- Stage 2 ---
            p2_mag_sq <= p1_i * p1_i + p1_q * p1_q;
            p2_i_sign <= p1_i[15];
            p2_q_sign <= p1_q[15];
            if ( (p1_i[15] ? -p1_i : p1_i) >= (p1_q[15] ? -p1_q : p1_q) ) begin
                p2_q_gt_i <= 1'b0; // |i| >= |q|, so we calculate q/i
                p_div_dividend <= { (p1_q[15] ? -p1_q : p1_q), 8'd0 }; 
                p_div_divisor  <= (p1_i[15] ? -p1_i : p1_i);
            end else begin
                p2_q_gt_i <= 1'b1; // |q| > |i|, so we calculate i/q
                p_div_dividend <= { (p1_i[15] ? -p1_i : p1_i), 8'd0 };
                p_div_divisor  <= (p1_q[15] ? -p1_q : p1_q);
            end

            // --- Stage 7 (after 5-cycle divider latency) ---
            p7_div_result <= p_div_quotient;
            p7_atan_base  <= atan_data; // Result of atan_addr from previous cycle
            p7_mag        <= sqrt_data; // Result of sqrt_addr from previous cycle
            p7_q_gt_i     <= $past(p2_q_gt_i, 5);
            p7_i_sign     <= $past(p2_i_sign, 5);
            p7_q_sign     <= $past(p2_q_sign, 5);
            
            // --- Stage 8 ---
            mag <= p7_mag;
            
            // Quadrant correction for atan2
            casex({p7_i_sign, p7_q_sign, p7_q_gt_i})
                // Q1
                3'b000: phase <= p7_atan_base;                  // atan(q/i)
                3'b001: phase <= PI_DIV_2 - p7_atan_base;       // pi/2 - atan(i/q)
                // Q2
                3'b100: phase <= PI - p7_atan_base;             // pi - atan(|q/i|)
                3'b101: phase <= PI_DIV_2 + p7_atan_base;       // pi/2 + atan(|i/q|)
                // Q3
                3'b110: phase <= -PI + p7_atan_base;            // -pi + atan(q/i)
                3'b111: phase <= -PI_DIV_2 - p7_atan_base;      // -pi/2 - atan(i/q)
                // Q4
                3'b010: phase <= -p7_atan_base;                 // -atan(|q/i|)
                3'b011: phase <= -PI_DIV_2 + p7_atan_base;      // -pi/2 + atan(|i/q|)
                default: phase <= 0;
            endcase
        end
    end
endmodule

